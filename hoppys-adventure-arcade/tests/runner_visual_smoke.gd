extends SceneTree
const BossBounds = preload("res://tests/boss_pose_bounds.gd")
const TurnPreview = preload("res://scenes/runner/environment/dev/turn_preview.gd")
const CorridorScript = preload("res://scenes/runner/environment/corridor.gd")
const SignatureDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const SignatureAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")
const SignatureArt = preload("res://scenes/runner/boss/visuals/boss_projectile_art.gd")
## Runtime loads happen after the logger is installed so engine errors fail this test.
class ErrorCapture extends Logger:
	var count := 0
	var mutex := Mutex.new()
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			mutex.lock()
			count += 1
			mutex.unlock()
	func errors() -> int:
		mutex.lock()
		var result := count
		mutex.unlock()
		return result

class LegacyPursuitGame extends Node:
	signal pursuit_started(seconds: float)
	signal pursuit_progress(remaining: float, total: float)
	signal pursuit_recovered(reason: StringName)
	signal damage_blocked(kind: StringName, reason: StringName)
	signal caught
	var paused := false

class CinematicAudioGame extends "res://scenes/runner/ui/dev/mock_runner_game.gd":
	signal boss_cinematic(kind: StringName, mode: StringName, seconds: float)
	signal boss_cinematic_skipped(mode: StringName)
	signal boss_cinematic_ended(mode: StringName)
	var boss_cinematic_mode: StringName = &""
	var boss_cinematic_progress := 0.0
	var boss_time_factor := 1.0

var failures := 0
var _logger := ErrorCapture.new()

func _initialize() -> void:
	OS.add_logger(_logger)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("VISUAL CHECK FAILED: ", message)

func frames() -> void:
	await process_frame
	await process_frame

# Poll the observable result; wall-clock deadlines only bound a failed wait.
func wait_until(predicate: Callable, deadline_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(deadline_seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()

func bounds(node: Node3D) -> AABB:
	# Hoppy only: imported Mesh AABBs are rest bounds, so evaluate skin vertices.
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree():
			continue
		if mesh.skin == null:
			var box := mesh.global_transform * mesh.get_aabb()
			result = box if first else result.merge(box)
			first = false
			continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		check(skeleton != null, "Hoppy skin has a skeleton")
		if skeleton == null:
			continue
		skeleton.force_update_all_bone_transforms()
		var transforms: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			check(bone >= 0, "Hoppy skin bind resolves")
			transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) if bone >= 0 else mesh.global_transform)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / vertices.size()
			for i in vertices.size():
				var point := Vector3.ZERO
				for j in stride:
					var weight := weights[i * stride + j]
					if weight > 0:
						point += (transforms[bones[i * stride + j]] * vertices[i]) * weight
				result = AABB(point, Vector3.ZERO) if first else result.expand(point)
				first = false
	return result

func hoppy_wait_state(hoppy: Node3D, player: AnimationPlayer, state: StringName, seconds: float) -> bool:
	# Manual advancement plus a frame flush supports property and deferred method tracks.
	# Never await animation_finished, which may already have fired on a different frame.
	for step in int(ceil(seconds * 60.0)) + 2:
		if hoppy.anim_state == state:
			return true
		player.advance(1.0 / 60.0)
		await process_frame
	return hoppy.anim_state == state

func hoppy_material_flashes(materials: Array[ShaderMaterial]) -> Array[float]:
	var colors: Array[float] = []
	for material in materials:
		colors.append(float(material.get_shader_parameter("flash")))
	return colors

func run() -> void:
	await check_interpolation_opt_out()
	await check_dev_scenes()
	var hoppy_scene := load("res://scenes/runner/player/hoppy_runner_visual.tscn") as PackedScene
	var corridor_scene := load("res://scenes/runner/environment/corridor.tscn") as PackedScene
	check(hoppy_scene != null and corridor_scene != null, "visual scenes load")
	if hoppy_scene != null and corridor_scene != null:
		var hoppy: Node3D = hoppy_scene.instantiate()
		var corridor: Node3D = corridor_scene.instantiate()
		root.add_child(corridor)
		hoppy.show_shield(true)
		root.add_child(hoppy)
		await frames()
		check(hoppy.get_node("ShieldRing").visible, "shield requested before ready is enabled")
		var player: AnimationPlayer = hoppy.get_node("AnimationPlayer")
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.playback_default_blend_time = 0.0
		player.seek(0.0, true)
		player.advance(0.0)
		var standing := bounds(hoppy.get_node("Root"))
		check(absf(standing.position.y) < 0.002 and absf(standing.end.y - 1.8) <= 0.02, "standing feet 0 and height 1.8")
		var skeleton := hoppy.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var head := skeleton.find_bone("head")
		var eye := skeleton.find_bone("eye_L")
		check(head >= 0 and eye >= 0, "Hoppy forward landmarks exist")
		if head >= 0 and eye >= 0:
			var facing := skeleton.global_basis * (skeleton.get_bone_global_rest(eye).origin - skeleton.get_bone_global_rest(head).origin)
			check(facing.z < 0.0, "Hoppy faces negative Z")
		var private_materials: Array[ShaderMaterial] = []
		var base_colors: Array[float] = []
		for mesh: MeshInstance3D in hoppy.find_children("*", "MeshInstance3D", true, false):
			if mesh.skin == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as ShaderMaterial
				check(material != null and material != mesh.mesh.surface_get_material(surface), "imported surface material is a private instance")
				if material != null and not private_materials.has(material):
					private_materials.append(material)
					base_colors.append(0.0)
		check(not private_materials.is_empty(), "imported Hoppy materials discovered")
		for state in [&"idle", &"run", &"jump", &"fall", &"roll", &"hurt", &"dead"]:
			hoppy.set_anim_state(state)
			await frames()
			check(player.has_animation(state), "animation exists: " + state)
			check(hoppy.anim_state == state, "state selected: " + state)
			if state == &"roll":
				hoppy.show_aura(&"lgtm", true)
				player.seek(player.get_animation(&"roll").length * 0.5, true)
				player.advance(0.0)
				await frames()
				var all_meshes := bounds(hoppy)
				check(hoppy.get_node("Root/Aura").is_visible_in_tree(), "roll aura visible")
				check(all_meshes.end.y <= 0.901 and all_meshes.position.y >= -0.001, "all-mesh mid-roll bounds including aura: %s" % all_meshes)
				for sample in 61:
					player.seek(player.get_animation(&"roll").length * float(sample) / 60.0, true)
					player.advance(0.0)
					await process_frame
					var rolling := bounds(hoppy.get_node("Root"))
					check(rolling.position.y >= -0.001 and rolling.end.y <= 0.901, "roll bounds at sample %d: %s" % [sample, rolling])
				hoppy.show_aura(&"lgtm", false)
		for speed in [0.0, 0.5, 1.2]:
			hoppy.set_anim_state(&"run")
			hoppy.set_run_speed(speed)
			await frames()
			check(is_equal_approx(player.speed_scale, lerpf(0.9, 1.6, clampf(speed, 0.0, 1.0))), "run speed scaling")
		for lean in [-1.0, 0.0, 1.0]:
			hoppy.set_lane_lean(lean)
			await frames()
			check(is_equal_approx(hoppy.rotation.z, -lean * 0.12), "scene root lean")
		hoppy.set_lane_lean(0.0)
		for kind in [&"lgtm", &"nitro", &"code_review"]:
			hoppy.show_aura(kind, true)
			await frames()
			check(hoppy.get_node("Root/Aura").visible, "aura enabled")
			hoppy.show_aura(kind, false)
			await frames()
			check(not hoppy.get_node("Root/Aura").visible, "aura disabled")
		hoppy.show_aura(&"lgtm", true)
		hoppy.show_aura(&"nitro", true)
		hoppy.show_aura(&"lgtm", false)
		check(hoppy.get_node("Root/Aura").visible, "other active aura survives expiry")
		hoppy.show_aura(&"nitro", false)
		for on in [true, false]:
			hoppy.show_shield(on)
			await frames()
			check(hoppy.get_node("ShieldRing").visible == on, "shield toggle")
		# Assert public hit/recovery behavior without depending on overlay nodes,
		# pulse timestamps, or whether a clip uses method versus property tracks.
		hoppy.set_anim_state(&"idle")
		player.advance(0.1)
		await frames()
		# A queued hurt method can briefly tint the materials after changing state.
		# Settle against the zero flash uniform, not an arbitrary render frame.
		await wait_until(func() -> bool: return hoppy_material_flashes(private_materials) == base_colors, 5.0)
		check(hoppy_material_flashes(private_materials) == base_colors, "prior hurt flash settles")
		var colors_before := base_colors
		hoppy.on_hit()
		check(hoppy_material_flashes(private_materials) != colors_before, "hit flash")
		var flash_cleared := await wait_until(func() -> bool: return hoppy_material_flashes(private_materials) == colors_before, 5.0)
		check(flash_cleared, "flash clears")
		var hurt_length := player.get_animation(&"hurt").length
		for locomotion in [&"idle", &"run", &"jump", &"fall", &"roll"]:
			hoppy.set_anim_state(locomotion)
			hoppy.set_anim_state(&"hurt")
			check(hoppy.anim_state == &"hurt", "hurt starts from " + locomotion)
			var recovered := await hoppy_wait_state(hoppy, player, locomotion, hurt_length + 0.2)
			check(recovered, "hurt returns to " + locomotion)
		hoppy.set_anim_state(&"hurt")
		player.advance(minf(0.05, hurt_length * 0.25))
		await frames()
		hoppy.set_anim_state(&"dead")
		for step in int(ceil((hurt_length + 0.2) * 60.0)):
			player.advance(1.0 / 60.0)
			await process_frame
		check(hoppy.anim_state == &"dead", "new state interrupts hurt recovery")
		hoppy.free()
		corridor.free()
		await frames()
	var preview_scene := load("res://scenes/runner/player/dev/hoppy_preview.tscn") as PackedScene
	check(preview_scene != null, "preview loads")
	if preview_scene != null:
		var preview := preview_scene.instantiate()
		root.add_child(preview)
		await frames()
		for key in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_SPACE, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_A, KEY_D, KEY_L, KEY_N, KEY_C, KEY_S, KEY_H]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			event.pressed = true
			Input.parse_input_event(event)
			await frames()
			event.pressed = false
			Input.parse_input_event(event)
		var camera: Camera3D = preview.get_node("Camera")
		check(camera.position == Vector3(0, 4, 8) and camera.fov == 60.0, "preview contract camera")
		preview.free()
		await frames()
	await check_turn()
	await check_turn_warning()
	await check_boss_intro()
	await check_stage_seam()
	await check_bosses()
	await check_tools_and_projectiles()
	await check_hazards()
	await check_powerups_and_pursuer()
	await check_hud_legibility()
	await check_pursuit_alert()
	await check_runner_ui()
	await check_runner_audio()
	await check_runner_full_loop()
	await check_runner_menu_reset()
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	failures += _logger.errors()
	print("RUNNER VISUAL SMOKE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	OS.remove_logger(_logger)
	quit(failures)

func discover_dev_scenes(directory: String, paths: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	check(dir != null, "dev scene discovery opens " + directory)
	if dir == null:
		return
	if directory.get_file() == "dev":
		for file: String in dir.get_files():
			var path := directory.path_join(file)
			if file.ends_with(".tscn") and not paths.has(path):
				paths.append(path)
	for child: String in dir.get_directories():
		discover_dev_scenes(directory.path_join(child), paths)

func check_dev_scenes() -> void:
	var before := failures
	var paths: Array[String] = [
		"res://scenes/runner/environment/dev/renderer_spike.tscn",
		"res://scenes/runner/environment/dev/corridor_preview.tscn",
		"res://scenes/runner/player/dev/hoppy_preview.tscn",
		"res://scenes/runner/hazards/visuals/dev/hazard_gallery.tscn",
		"res://scenes/runner/ui/dev/hud_preview.tscn",
	]
	discover_dev_scenes("res://scenes/runner", paths)
	var instantiated := 0
	for path: String in paths:
		var errors_before := _logger.errors()
		var previous_paused := paused
		var previous_scale := root.scaling_3d_scale
		var packed := load(path) as PackedScene
		check(packed != null, "dev scene loads: " + path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		check(is_instance_valid(instance), "dev scene instantiates: " + path)
		if not is_instance_valid(instance):
			continue
		instantiated += 1
		root.add_child(instance)
		await frames()
		await physics_frame
		check(_logger.errors() == errors_before, "dev scene runs without engine errors: " + path)
		check(is_instance_valid(instance) and instance.is_inside_tree(), "dev scene remains in tree: " + path)
		check(paused == previous_paused, "dev scene preserves pause state: " + path)
		if is_instance_valid(instance):
			instance.free()
		await process_frame
		check(_logger.errors() == errors_before, "dev scene teardown without engine errors: " + path)
		check(paused == previous_paused, "dev scene teardown preserves pause state: " + path)
		check(is_equal_approx(root.scaling_3d_scale, previous_scale), "dev scene teardown restores viewport scale: " + path)
		# Isolate later sections even when a scene fails its restoration checks.
		paused = previous_paused
		root.scaling_3d_scale = previous_scale
	var entry_paused := paused
	for initial_pause in [false, true]:
		paused = initial_pause
		var preview := preload("res://scenes/runner/environment/dev/turn_preview.tscn").instantiate()
		root.add_child(preview)
		paused = not initial_pause
		preview.free()
		check(paused == initial_pause, "turn preview restores entry pause state")
	paused = entry_paused
	if failures == before:
		print("RUNNER DEV SCENES: PASS (%d scenes)" % instantiated)

func visible_hazard_bounds(body: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node: Node3D in body.find_children("*", "VisualInstance3D", true, false):
		if not node.is_visible_in_tree():
			continue
		if node is MultiMeshInstance3D:
			# Headless returns identity instance transforms and zero batch AABBs.
			# Reconstruct from the CPU artwork data, including animated parent pivots.
			var found := false
			for batch: Dictionary in body.get_parent()._batches:
				if batch.node != node: continue
				found = true
				for instance: Array in batch.instances:
					var pivot: Node3D = instance[0]
					if not pivot.is_visible_in_tree(): continue
					var pose := pivot.global_transform
					pose.basis = pose.basis.scaled_local(instance[1])
					var box: AABB = body.get_parent().global_transform.affine_inverse() * pose * AABB(-Vector3.ONE * 0.5, Vector3.ONE)
					result = box if first else result.merge(box)
					first = false
			check(found, "batch has CPU instance data")
			continue
		var box: AABB = body.get_parent().global_transform.affine_inverse() * node.global_transform * node.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func hazard_draw_count(visual: Node3D, include_hidden := false) -> int:
	# Node-based estimate: outlined Label3D = 2, MultiMesh = 1.
	# Actual renderer totals (including overlays/culling) are checked by capture_previews.
	var count := 0
	for node in visual.find_children("*", "VisualInstance3D", true, false):
		if not include_hidden and not node.is_visible_in_tree(): continue
		if node is Label3D:
			count += 2 if node.outline_size > 0 else 1
		elif node is MeshInstance3D or node is MultiMeshInstance3D or node is GPUParticles3D:
			count += 1
	return count

func check_hazard_bounds(visual: Node3D, context: String) -> void:
	var art: Node3D = visual.get_node("Artwork")
	var body: Node3D = art.get_node("Body")
	var size: Vector3 = visual.get("hitbox_size")
	var offset: Vector3 = visual.get("hitbox_offset")
	# Independent contract section 8 high-row centre, never infer bounds from artwork.
	if visual.get("variant") == &"timed" and art._state == &"high": offset.y = 1.3
	if visual.get("variant") == &"timed" and art._state == &"off":
		# Off preserves the previous discrete row while collision is disabled.
		offset.y = visual.get_meta("last_laser_y", offset.y)
	var envelope := AABB(offset - size * 0.55 - Vector3.ONE * 0.001, size * 1.1 + Vector3.ONE * 0.002)
	var actual := visible_hazard_bounds(body)
	var particles := art.get_node_or_null("GlyphParticles") as GPUParticles3D
	if particles != null:
		var particle_bounds := particles.transform * particles.visibility_aabb
		check(envelope.encloses(particle_bounds), context + " particle hitbox AABB")
		check(particles.process_mode == Node.PROCESS_MODE_PAUSABLE and not particles.trail_enabled and particles.sub_emitter.is_empty(), context + " bounded pausable particles")
		var process := particles.process_material as ParticleProcessMaterial
		var material := particles.draw_pass_1.material as StandardMaterial3D
		check(process.collision_mode == ParticleProcessMaterial.COLLISION_DISABLED, context + " no particle collision")
		check(material.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES and material.particles_anim_h_frames == 8 and material.particles_anim_v_frames == 8, context + " 8x8 billboard atlas")
	check(hazard_draw_count(visual) <= 14, context + " estimated draw budget <= 14")
	check(envelope.encloses(actual), "%s visible AABB %s within %s" % [context, actual, envelope])
	# Ground projections necessarily lie outside elevated hitboxes. Test them separately.
	var marker: MeshInstance3D = art.get_node("FloorMarker")
	var footprint := marker.transform * marker.get_aabb()
	check(is_equal_approx(footprint.size.x, size.x) and is_equal_approx(footprint.size.z, size.z), context + " exact floor footprint")
	# Raised from 0.006 to a plane of its own, clear of the corridor LaneGlow (y 0.012).
	check(is_equal_approx(marker.position.y, art.MARKER_Y) and absf(art.MARKER_Y - 0.012) >= 0.005 and art.MARKER_Y <= 0.05, context + " ground marker")
	var material := marker.material_override as StandardMaterial3D
	var expected := Color("79e0c4", 0.35) if art._cleared else Color("ff4d3d", 0.35)
	check(material.albedo_color.is_equal_approx(expected), context + " cleared/spawned marker alpha 0.35")

func check_hazards() -> void:
	var cases_checked := 0
	var total_draws := 0
	var gallery_script := load("res://scenes/runner/hazards/visuals/dev/hazard_gallery.gd")
	for entry: Array in gallery_script.CASES:
		var title := "%s/%s" % [entry[0], entry[1]]
		var packed := load("res://scenes/runner/hazards/visuals/%s_visual.tscn" % entry[0]) as PackedScene
		check(packed != null, title + " loads")
		if packed == null:
			continue
		var visual := packed.instantiate() as Node3D
		root.add_child(visual)
		check(visual.get_child_count() == 0, title + " safely waits for backend vars")
		gallery_script.apply_vars(visual, entry)
		visual.on_spawned()
		visual.set_process(false)
		await frames()
		check(visual.find_children("*", "Light3D", true, false).is_empty(), title + " no lights")
		check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), title + " no collision")
		if entry[0] == &"pr_backlog_high":
			var safe: MeshInstance3D = visual.get_node("Artwork/SafeGap")
			check((safe.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color("63f9b2", 0.25)), "approved safe-gap marker")
			check(is_equal_approx((safe.mesh as QuadMesh).size.y, visual.get("hitbox_size").z * 0.6), "safe-gap depth inset")
		for hook in ["on_spawned", "on_hit_player", "on_cleared", "set_telegraph", "set_laser_state"]:
			check(visual.has_method(hook), title + " hook " + hook)
		var peak_draws := hazard_draw_count(visual)
		var initial := visible_hazard_bounds(visual.get_node("Artwork/Body"))
		var initial_labels := hazard_labels(visual)
		var count := visual.find_children("*", "Node", true, false).size()
		for reaction in ["idle", "on_hit_player", "on_cleared"]:
			visual.on_spawned()
			if reaction != "idle": visual.call(reaction)
			await frames()
			for sample in 61:
				visual._process(1.0 / 30.0)
				check_hazard_bounds(visual, title + " " + reaction + " %d" % sample)
				peak_draws = maxi(peak_draws, hazard_draw_count(visual))
			visual.on_spawned()
			visual.on_spawned()
			await frames()
			check(visible_hazard_bounds(visual.get_node("Artwork/Body")).is_equal_approx(initial), title + " reset restores bounds")
			check(visual.find_children("*", "Node", true, false).size() == count, title + " reset does not accumulate nodes")
			check(visual.get_node("Artwork")._t == 0.0, title + " reset clock")
			check(hazard_labels(visual) == initial_labels, title + " reset text and color")
			for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
				check(mesh.material_overlay == null, title + " reset flash")
		for state in [&"ground", &"off", &"high", &"off", &"ground"]:
			visual.set_laser_state(state)
			if state != &"off": visual.set_meta("last_laser_y", 1.3 if state == &"high" else visual.get("hitbox_offset").y)
			for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
				visual.set_telegraph(t)
				await frames()
				check_hazard_bounds(visual, title + " " + state + " telegraph %s" % t)
				peak_draws = maxi(peak_draws, hazard_draw_count(visual))
			if entry[1] == &"timed":
				var body: Node3D = visual.get_node("Artwork/Body")
				check(body.get_node("Beams").visible == (state != &"off"), "timed beam visibility")
				if state != &"off": check(is_equal_approx(body.position.y, 1.3 if state == &"high" else visual.get("hitbox_offset").y), "timed beam elevation")
		print("HAZARD DRAW CENSUS: %s peak=%d" % [title, peak_draws])
		total_draws += peak_draws
		cases_checked += 1
		visual.on_spawned()
		visual.set_process(true)
		paused = true
		await frames()
		check(visual.get_node("Artwork")._t == 0.0, title + " pause freezes clock")
		paused = false
		visual.free()
		# Also exercise vars-before-ready, used by standalone frontend fixtures.
		visual = packed.instantiate()
		gallery_script.apply_vars(visual, entry)
		root.add_child(visual)
		visual.on_spawned()
		await frames()
		check_hazard_bounds(visual, title + " pre-ready vars")
		visual.free()
	print("HAZARD CASES CHECKED: %d; summed peak draw census=%d" % [cases_checked, total_draws])
	check(cases_checked == 12, "all hazard cases executed")
	var gallery_scene := load("res://scenes/runner/hazards/visuals/dev/hazard_gallery.tscn") as PackedScene
	check(gallery_scene != null, "hazard gallery scene loads")
	if gallery_scene == null:
		return
	var gallery := gallery_scene.instantiate()
	root.add_child(gallery)
	await frames()
	check(gallery.pickups.size() == 6 and gallery.fixtures.size() == 19, "gallery pickups and pursuer")
	check(gallery.visuals.size() == 12, "gallery all eight kinds and every variant")
	var camera: Camera3D = gallery.get_node("Camera")
	check(camera.position == Vector3(0, 4, 8) and camera.fov == 60.0, "gallery contract camera")
	for key in [KEY_H, KEY_R, KEY_C, KEY_R, KEY_T, KEY_1, KEY_2, KEY_3, KEY_R, KEY_RIGHT, KEY_LEFT, KEY_P, KEY_K, KEY_B, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_R]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		gallery._unhandled_key_input(event)
		await frames()
	for index in gallery.fixtures.size():
		gallery._selected = index
		gallery._focus()
		await frames()
	check(gallery._selected == 18, "gallery navigates through pursuer")
	gallery.free()
	await frames()

func hazard_labels(visual: Node3D) -> Array:
	var result: Array = []
	for label: Label3D in visual.find_children("*", "Label3D", true, false):
		result.append([label.text, label.modulate, label.visible])
	return result

func pursuer_bounds(visual: Node3D, excluded: GeometryInstance3D = null) -> AABB:
	var result := AABB()
	var first := true
	for node: GeometryInstance3D in visual.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree() or node == excluded: continue
		var relative := visual.global_transform.affine_inverse() * node.global_transform
		if node is MultiMeshInstance3D:
			var poses: Array[Transform3D] = visual.card_transforms()
			check(poses.size() == node.multimesh.instance_count and poses.size() == 20, "pursuer CPU card census")
			for pose in poses:
				var box: AABB = relative * pose * node.multimesh.mesh.get_aabb()
				result = box if first else result.merge(box)
				first = false
		else:
			var local: AABB = node.visibility_aabb if node is GPUParticles3D else node.get_aabb()
			var box: AABB = relative * local
			result = box if first else result.merge(box)
			first = false
	return result

func check_powerups_and_pursuer() -> void:
	for kind in [&"approve_shield", &"auto_fix", &"lgtm", &"nitro", &"super_jump", &"code_review"]:
		var packed := load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % kind) as PackedScene
		check(packed != null, "%s loads" % kind)
		if packed == null: continue
		var visual := packed.instantiate() as Node3D
		root.add_child(visual)
		check(visual.get_child_count() == 0, "%s waits for kind" % kind)
		visual.set("kind", kind)
		visual.on_spawned()
		check(hazard_draw_count(visual, true) <= 14, "%s draw budget <= 14" % kind)
		var art: Node3D = visual.get_node("Artwork")
		art.set_process(false)
		var count := art.get_child_count()
		visual.on_spawned()
		visual.on_spawned()
		check(art.get_child_count() == count and visual.visible, "%s idempotent spawn" % kind)
		check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s cosmetic only" % kind)
		check(visual.find_children("*", "Light3D", true, false).is_empty(), "%s no extra lights" % kind)
		art._process(0.5)
		check(is_equal_approx(art.get_node("Pivot").rotation.y, sin(0.8)*0.28), "%s bounded front-facing display rock" % kind)
		check(absf(art.get_node("Pivot").position.y) <= 0.08, "%s bob bound" % kind)
		visual.on_collected()
		art._process(0.0875)
		check(is_equal_approx(art.get_node("Pivot").scale.x, 1.45), "%s collection peak" % kind)
		visual.on_collected()
		check(is_equal_approx(art._collect_time, 0.0875), "%s repeated collection does not restart" % kind)
		art._process(0.163)
		check(not visual.visible, "%s collection hides after 0.25s" % kind)
		check(not art.is_processing(), "%s collection stops processing" % kind)
		check(art.get_node("Pivot/Ring").scale.is_equal_approx(Vector3.ONE), "%s hidden ring resets scale" % kind)
		visual.on_spawned()
		visual.on_spawned()
		check(art.is_processing(), "%s reuse enables processing" % kind)
		check(visual.visible and art.get_node("Pivot").transform.is_equal_approx(Transform3D.IDENTITY), "%s reuse resets pose and visibility" % kind)
		check(is_equal_approx(art.get_node("Tag").modulate.a, 1.0), "%s tag restored" % kind)
		visual.on_collected()
		art._process(0.05)
		visual.on_spawned()
		art._process(0.3)
		check(visual.visible and art._collect_time < 0.0, "%s spawn interrupts collection" % kind)
		visual.on_spawned()
		art.set_process(true)
		paused = true
		await frames()
		check(art._t == 0.0, "%s pause freezes clock" % kind)
		paused = false
		visual.free()
	print("POWER-UP VISUALS: 6 checked; reuse, collection and pause PASS")
	var packed := load("res://scenes/runner/pursuer/pursuer_visual.tscn") as PackedScene
	check(packed != null, "pursuer loads")
	if packed == null: return
	var pursuer := packed.instantiate() as Node3D
	root.add_child(pursuer)
	pursuer.set_process(false)
	await frames()
	check(hazard_draw_count(pursuer, true) <= 14, "pursuer draw budget <= 14")
	check(pursuer.find_children("*", "Light3D", true, false).size() == 1, "pursuer exactly one light")
	check(pursuer.find_children("*", "Label3D", true, false).is_empty(), "hunter has no wall of headlines")
	check(pursuer.find_children("*", "CollisionObject3D", true, false).is_empty(), "pursuer cosmetic only")
	for threat in [0.0,0.5,1.0]:
		pursuer.set_threat(threat)
		check(pursuer.get_node("Hunter").scale.is_equal_approx(Vector3.ONE),"hunter keeps rigid proportions")
		check(is_equal_approx(pursuer.get_node("RedLight").light_energy,threat*1.5),"hunter threat light")
	for sample in 121:
		pursuer._process(1.0/60.0)
		var box := bounds(pursuer)
		check(box.size.x <= 2.5 and box.size.y <= 2.6 and box.position.y >= 0,"compact hunter motion envelope")
	var clock: float = pursuer._t
	pursuer.set_process(true)
	paused = true
	await frames()
	check(pursuer._t == clock, "pursuer pause freezes motion")
	paused = false
	pursuer.set_process(false)
	var initial_scale: Vector3 = pursuer.get_node("Hunter").scale
	pursuer.play_catch()
	pursuer._process(0.7)
	pursuer.play_catch()
	check(is_equal_approx(pursuer._reaction_time, 0.7), "catch idempotent")
	pursuer._process(0.7)
	check(pursuer.get_node("Hunter").scale.is_equal_approx(initial_scale), "catch 1.4s keeps compact scale")
	check(is_equal_approx(pursuer.get_node("RedLight").light_energy, 3.0), "catch light")
	# Reproduce the backend zero-threat update immediately before retreat.
	pursuer.set_threat(1.0)
	var retreat_pose: Transform3D = pursuer.get_node("Hunter").transform
	pursuer.set_threat(0.0)
	pursuer.play_retreat()
	check(pursuer.get_node("Hunter").transform.is_equal_approx(retreat_pose), "retreat restores last non-zero threat pose")
	pursuer._process(0.0)
	check(pursuer.get_node("Hunter").transform.is_equal_approx(retreat_pose), "retreat starts without height pop")
	pursuer._process(0.35)
	pursuer.play_retreat()
	check(is_equal_approx(pursuer._reaction_time, 0.35), "retreat idempotent")
	check(pursuer.visible, "retreat still visible halfway")
	pursuer._process(0.35)
	check(not pursuer.visible, "retreat hides at 0.7s")
	check(pursuer.get_node("RedLight").light_energy == 0.0, "retreat light off")
	pursuer.set_threat(0.0)
	check(not pursuer.visible, "retreated zero remains hidden")
	pursuer.set_threat(1.0)
	check(pursuer.visible and pursuer.get_node("Hunter").scale.is_equal_approx(Vector3.ONE), "pursuer resumes cleanly")
	pursuer.free()
	await frames()
	print("PURSUER VISUAL: threat, catch, retreat, reuse and pause checked")

func check_runner_ui() -> void:
	root.size = Vector2i(1280, 720)
	var fixture := load("res://scenes/runner/ui/dev/hud_preview.tscn") as PackedScene
	check(fixture != null, "HUD preview scene loads")
	if fixture == null:
		return
	var mock := fixture.instantiate()
	mock.autoplay = false
	root.add_child(mock)
	await frames()
	var hud: CanvasLayer = mock.hud
	var pause_menu: CanvasLayer = mock.pause_menu
	var over: CanvasLayer = mock.game_over
	check(hud.get_ready.visible and not pause_menu.visible and not over.visible, "UI initial state")
	check(hud.layer == 10 and pause_menu.layer == 21 and over.layer == 22, "overlay layers")
	var seen_actions: Array[StringName] = []
	var seen_chunks: Array = []
	var cleared: Array = []
	var bonuses: Array = []
	var started: Array = []
	mock.player_action.connect(func(action: StringName) -> void: seen_actions.append(action))
	mock.chunk_spawned.connect(func(chunk: Node3D) -> void: seen_chunks.append(is_instance_valid(chunk)))
	mock.hazard_cleared.connect(func(hazard: Area3D) -> void: cleared.append(is_instance_valid(hazard)))
	mock.bonus_awarded.connect(func(points: int, reason: StringName) -> void: bonuses.append([points, reason]))
	mock.run_started.connect(func(value: int) -> void: started.append(value))
	mock.start_run(123456)
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 123456
	check(mock.seed == 123456 and started == [123456] and mock.cosmetic_rng.randi() == expected_rng.randi(), "start_run preserves and reseeds supplied seed")
	var saw_shield := false
	var saw_blocked := false
	var saw_auto_fix := false
	var saw_bonus := false
	for i in 100:
		mock.advance_demo(0.1)
		saw_shield = saw_shield or mock.hud.chips.has(&"approve_shield")
		saw_blocked = saw_blocked or hud.toast_queue.any(func(entry: Dictionary) -> bool: return entry.text == "BLOCKED") or hud.toast.text == "BLOCKED"
		saw_auto_fix = saw_auto_fix or hud.toast_queue.any(func(entry: Dictionary) -> bool: return entry.text == "AUTO-FIX ×3") or hud.toast.text == "AUTO-FIX ×3"
		saw_bonus = saw_bonus or hud.toast_queue.any(func(entry: Dictionary) -> bool: return entry.text == "+25 BONUS") or hud.toast.text == "+25 BONUS"
		hud._process(0.1)
	check(saw_shield and not hud.chips.has(&"approve_shield"), "demo shield chip appears then clears on blocked hit")
	check(saw_blocked and saw_auto_fix and saw_bonus, "demo BLOCKED, AUTO-FIX and bonus reach HUD toasts")
	check(cleared == [true, true, true] and not seen_chunks.is_empty() and not false in seen_chunks, "demo emits valid hazards and chunks")
	check(bonuses.size() == 4 and bonuses.all(func(value: Array) -> bool: return value == [25, &"pickup"]), "every demo pickup awards 25")
	for action in [&"jump", &"land", &"roll", &"roll_end", &"lane_left", &"lane_right"]:
		check(action in seen_actions, "demo action emitted: " + action)
	await wait_until(func() -> bool: return hud.score_label.text == "%08d" % mock.score, 5.0)
	check(not hud.get_ready.visible and hud.hp_row.get_child_count() == 2, "running HUD approvals")
	check(hud.hp_row.get_child(0).filled and not hud.hp_row.get_child(1).filled, "hit updates approval pips")
	check(hud.pursuit_warning.visible and hud.pursuit_remaining < float(mock.config.recovery_seconds), "demo pursuit")
	check(hud.score_label.text == "%08d" % mock.score, "score count-up reaches facade score")
	check(is_zero_approx(mock.camera_rig.last_shake), "HUD leaves backend-owned damage camera shake untouched")
	mock.pursuit_started.emit(7.5)
	mock.pursuit_progress.emit(3.25, 7.5)
	check(hud.pursuit_label.text == "BACKLOG  3.2s", "pursuit formats signal value")
	check(is_equal_approx(hud.pursuit_ring.fraction, 3.25 / 7.5), "ring uses supplied total")
	mock.collect(&"nitro", 8)
	hud._process(1)
	await frames()
	check(hud.chips[&"nitro"].bar.size.is_equal_approx(Vector2(112, 9)), "power-up bar remains 112x9")
	for pip in hud.hp_row.get_children():
		check(pip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "rebuilt HP pip ignores mouse")
	var pause_event := InputEventAction.new()
	pause_event.action = "pause"
	pause_event.pressed = true
	mock._unhandled_input(pause_event)
	check(mock.paused, "demo uses pause action")
	mock.resume()
	var chip_remaining: float = hud.chips[&"nitro"].remaining
	mock.pause()
	check(pause_menu.visible and pause_menu.resume_button.has_focus(), "pause shows and focuses Resume")
	hud._process(1)
	check(hud.chips[&"nitro"].remaining == chip_remaining and hud.widgets.modulate.a < 1, "paused HUD dims and freezes local timers")
	pause_menu.resume_button.pressed.emit()
	check(not pause_menu.visible and not mock.paused, "Resume calls facade")
	for i in 180:
		mock.advance_demo(0.1)
		hud._process(0.1)
	check(not hud.pursuit_warning.visible and mock.hp == 2, "demo recovery restores approvals")
	check(is_zero_approx(hud.vignette_material.get_shader_parameter("strength")), "recovery clears vignette")
	for i in 125:
		mock.advance_demo(0.1)
		hud._process(0.1)
	check(not hud.score_label.is_visible_in_tree() and not hud.pursuit_warning.visible, "caught hides gameplay")
	check(is_equal_approx(hud.vignette_material.get_shader_parameter("strength"), 1), "caught vignette")
	for restart_state: StringName in [&"running", &"ready"]:
		mock.state_changed.emit(&"caught")
		hud.widgets.modulate.a = 0.35
		mock.damage_blocked.emit(&"bug_swarm", &"shield")
		hud._process(2.0)
		mock.bonus_awarded.emit(25, &"pickup")
		var previous_flash: Tween = hud.flash_tween
		mock.state_changed.emit(restart_state)
		check(is_zero_approx(hud.vignette_material.get_shader_parameter("strength")), "%s clears caught vignette" % restart_state)
		check(hud.widgets.visible and is_equal_approx(hud.widgets.modulate.a, 1.0), "%s restores gameplay widgets" % restart_state)
		check(not previous_flash.is_valid() and hud.flash_tween == null and is_zero_approx(hud.hit_flash.color.a), "%s clears hit flash and kills tween" % restart_state)
		check(hud.toast_queue.is_empty() and hud.toast.text.is_empty() and is_zero_approx(hud.toast_remaining), "%s clears active and queued toasts" % restart_state)
	await frames()
	check(over.panel.size.x <= 760 and over.panel.size.y <= 620, "result panel fits 1280x720")
	check(over.panel.get_global_rect().end.y <= 720, "result panel inside viewport")
	check(over.name_field.focus_next == over.name_field.get_path_to(over.save_button), "name to save focus chain")
	for viewport_size in [Vector2i(1600, 900), Vector2i(1440, 900), Vector2i(1000, 720)]:
		root.size = viewport_size
		await frames()
		# canvas_items/expand uses logical coordinates at the requested window size.
		var canvas_size := root.get_visible_rect().size
		check(root.size == viewport_size, "requested window size applied")
		check(absf(hud.speed_bar.get_global_rect().end.x - (canvas_size.x - 42)) < 0.1, "HUD right anchor at %s" % viewport_size)
		check(is_equal_approx(hud.hp_row.global_position.x, 42), "HUD left anchor at %s" % viewport_size)
		check(over.panel.get_global_rect().position.x >= 0 and over.panel.get_global_rect().end.x <= canvas_size.x and over.panel.get_global_rect().end.y <= canvas_size.y, "result inside %s" % viewport_size)
		check(is_equal_approx(over.retry_button.size.y, 62) and is_equal_approx(over.menu_button.size.y, 62), "result buttons remain 62px at %s" % viewport_size)
	root.size = Vector2i(1280, 720)
	await frames()
	check(over.visible and over.name_row.visible and over.name_field.has_focus(), "finished shows qualifying name flow")
	check(over.stats.get_child(0).text == "SCORE %08d" % mock.score, "result score")
	check(over.stats.get_child(1).text == "TIME " + over._time(mock.elapsed), "result duration")
	check(over.stats.get_child(2).text == "DISTANCE %d m" % int(mock.distance), "result distance")
	check(over.stats.get_child(3).text == "DODGED 24" and over.stats.get_child(4).text == "POWER-UPS 6", "result counters")
	check(over.board.get_child_count() == 10 and over.board.get_child(2).get_meta("current_run"), "top ten highlights matching run ID")
	over.name_field.text = "Ada"
	over.name_field.text_submitted.emit("Ada")
	over.save_button.pressed.emit()
	check(mock.submit_calls == 1 and over.save_button.disabled and not over.name_field.editable, "submit name called exactly once")
	check("Ada" in over.board.get_child(2).text and over.retry_button.has_focus(), "saved board rerenders and Retry focused")
	var qualifying_result: Dictionary = mock.get_result()
	var unplaced: Dictionary = mock.get_result()
	unplaced.qualifies = false
	unplaced.rank = 0
	over.show_result(unplaced, mock.get_leaderboard())
	check(not over.name_row.visible and over.retry_button.has_focus(), "nonqualifier skips name flow")
	over.show_result(mock.get_result(), mock.get_leaderboard())
	mock.save_succeeds = false
	over.save_button.pressed.emit()
	check(over.error_label.visible and not over.save_button.disabled and over.name_field.editable, "save failure remains retryable")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	over._unhandled_input(cancel)
	check(mock.menu_calls == 1, "visible game over cancel routes to menu")
	over._unhandled_input(cancel)
	check(mock.menu_calls == 1, "hidden game over ignores cancel")
	over.game = null
	over.show_result(unplaced, [])
	over._unhandled_input(cancel)
	check(over.visible, "unbound public show_result safely ignores cancel")
	mock.free()
	await frames()
	for variant in ["nonqualifier", "leaderboard error"]:
		var variant_mock := fixture.instantiate()
		variant_mock.autoplay = false
		variant_mock.result_qualifies = variant != "nonqualifier"
		variant_mock.result_leaderboard_error = ERR_CANT_CREATE if variant == "leaderboard error" else OK
		root.add_child(variant_mock)
		variant_mock.finish_demo()
		var variant_over: CanvasLayer = variant_mock.game_over
		check(not variant_over.name_field.is_visible_in_tree() and variant_over.save_button.disabled, "%s blocks name and Save" % variant)
		check(variant_over.retry_button.has_focus(), "%s initially focuses Retry" % variant)
		check(variant_over.error_label.visible == (variant == "leaderboard error"), "%s error caption visibility" % variant)
		if variant == "leaderboard error":
			check(variant_over.error_label.text == "Leaderboard could not be saved.", "leaderboard error explains failed persistence")
		for button: Button in [variant_over.retry_button, variant_over.menu_button]:
			var target: Button = variant_over.menu_button if button == variant_over.retry_button else variant_over.retry_button
			for neighbor: StringName in [&"focus_next", &"focus_previous", &"focus_neighbor_top", &"focus_neighbor_bottom", &"focus_neighbor_left", &"focus_neighbor_right"]:
				check(button.get_node(button.get(neighbor)) == target, "%s %s reaches other action" % [variant, neighbor])
		variant_over.menu_button.grab_focus()
		check(variant_over.menu_button.has_focus(), "%s Menu can receive focus" % variant)
		variant_over.save_button.pressed.emit()
		variant_over.name_field.text_submitted.emit("Blocked")
		variant_over._save()
		check(variant_mock.submit_calls == 0, "%s never calls submit_name" % variant)
		# Even a stale visible row must not bypass the result guard.
		variant_over.name_row.show()
		variant_over._save()
		check(variant_mock.submit_calls == 0, "%s result guard blocks stale controls" % variant)
		if variant == "leaderboard error":
			var failed_result: Dictionary = variant_mock.get_result()
			failed_result.qualifies = true
			variant_over.show_result(failed_result, variant_mock.get_leaderboard())
			check(variant_over.save_button.disabled and variant_over.retry_button.has_focus(), "leaderboard error overrides qualifying flag")
			variant_over.name_row.show()
			variant_over._save()
			check(variant_mock.submit_calls == 0, "leaderboard error guard blocks qualifying flag")
		variant_over.show_result(qualifying_result, variant_mock.get_leaderboard())
		check(variant_over.name_row.visible and not variant_over.save_button.disabled and variant_over.name_field.editable and variant_over.name_field.has_focus() and not variant_over.error_label.visible, "%s resets to qualifying flow" % variant)
		variant_mock.free()
		await frames()
	var coarse_mock := fixture.instantiate()
	coarse_mock.autoplay = false
	root.add_child(coarse_mock)
	var finishes: Array[Dictionary] = []
	coarse_mock.run_finished.connect(func(result: Dictionary) -> void: finishes.append(result))
	coarse_mock.advance_demo(41.0)
	check(coarse_mock.state == &"caught" and finishes.is_empty(), "coarse demo frame stops at catch before finish")
	check(not coarse_mock._events.has(40.0), "coarse demo frame leaves scheduled finish pending")
	coarse_mock.advance_demo(float(coarse_mock.config.caught_sequence_seconds))
	check(coarse_mock.state == &"finished" and finishes.size() == 1, "later demo frame finishes after catch duration")
	coarse_mock.free()
	await frames()
	print("RUNNER UI MOCK: HUD, pursuit, pause, results, focus and save PASS")
	var scene := load("res://scenes/runner/runner_game.tscn") as PackedScene
	check(scene != null, "runner game scene loads")
	if scene == null:
		return
	var game := scene.instantiate()
	game.autostart = false
	game.leaderboard_path = "user://test_runner_visual_smoke_%d.cfg" % OS.get_process_id()
	root.add_child(game)
	game.start_run(4704)
	game.set_autopilot(true)
	await create_timer(3.0).timeout
	var real_hud: CanvasLayer = game.get_node("HUD/RunnerHud")
	check(real_hud.game == game and not real_hud.get_ready.visible, "real facade binds HUD")
	check(count_pursuit_alerts(game) == 1, "real RunnerGame mounts exactly one pursuit alert")
	var mounted_alert := game.get_node_or_null("HUD/PursuitAlert") as Control
	check(mounted_alert != null and real_hud.pursuit_alert == mounted_alert, "HUD resolves backend-owned sibling alert")
	check(game.elapsed > 2.0 and game.score > 0, "real facade autopilot runs for three seconds")
	check(real_hud.hp_row.get_child_count() == game.config.max_hp, "real facade HP")
	game.pause()
	check(game.get_node("Overlays/PauseMenu").visible, "real pause signal")
	if mounted_alert != null:
		check(is_equal_approx(mounted_alert.modulate.a, 0.35), "pause dims sibling alert")
	game.resume()
	if mounted_alert != null:
		check(is_equal_approx(mounted_alert.modulate.a, 1.0), "resume restores sibling alert")
		game.pursuit_started.emit(18.0)
		game.caught.emit()
		check(not real_hud.score_label.is_visible_in_tree() and mounted_alert.is_visible_in_tree(), "caught hides real HUD gameplay but preserves sibling portrait")
	var temporary_path: String = game.leaderboard_path
	game.free()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(temporary_path + suffix):
			DirAccess.remove_absolute(temporary_path + suffix)
	await frames()
	print("RUNNER UI REAL FACADE: autostart=false, start_run, autopilot 3s PASS")

func check_runner_audio() -> void:
	const Synth = preload("res://scenes/runner/audio/sfx_synth.gd")
	const RunnerAudio = preload("res://scenes/runner/audio/runner_audio.tscn")
	const Mock = preload("res://scenes/runner/ui/dev/mock_runner_game.gd")
	var music := load("res://Assets/Backgrounds/cyberpunk-street-files/Assets/music/cyberpunk-street.ogg") as AudioStreamOggVorbis
	check(music != null and music.loop == true, "imported runner OGG loops before audio bind")
	var mock := CinematicAudioGame.new()
	mock.autoplay = false
	root.add_child(mock)
	var audio := RunnerAudio.instantiate()
	mock.add_child(audio)
	var counts := {}
	var peak := [0]
	audio.sound_played.connect(func(kind: StringName, stream: AudioStream) -> void:
		check(stream != null, "audio hook has stream: " + kind)
		counts[kind] = int(counts.get(kind, 0)) + 1
		peak[0] = maxi(peak[0], audio.active_voice_count())
		check(audio.active_voice_count() <= 10, "audio hard ten voice cap")
	)
	mock.boss_intro.connect(func(kind, _name, seconds): mock.boss_cinematic.emit(kind, &"intro_full", seconds))
	audio.bind(mock)
	audio.bind(mock)
	audio.set_process(false)
	check(audio.name == &"RunnerAudio" and audio.process_mode == Node.PROCESS_MODE_ALWAYS, "audio scene contract")
	check(audio.get_child_count() == 4 and audio.one_shots.stream.polyphony == 7, "seven plus three voice layout")
	for player: AudioStreamPlayer in audio.get_children():
		check(player.bus == &"SFX" and player.max_polyphony == 1, "SFX routing and dedicated player cap")
	var service := root.get_node("AudioService")
	check(service.music.stream.resource_path == audio.MUSIC_PATH and service.music.stream.loop, "runner BGM loaded and looping")
	check(service.music.volume_db == -12.0, "runner BGM level")
	check(Synth.RECIPES.size() == 37, "cinematic cues extend all 32 existing recipes")
	check(audio.HIGH_PRIORITY.has(&"alert_sting"), "alert sting is high priority")
	for kind: StringName in Synth.RECIPES:
		var stream := Synth.sound(kind)
		check(stream == Synth.sound(kind), "cached PCM: " + kind)
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050, "PCM format: " + kind)
		var data := stream.data
		var maximum := 0
		for i in range(0, data.size(), 2):
			maximum = maxi(maximum, absi(data.decode_s16(i)))
		check(maximum > 0 and maximum <= int(0.8 * 32767), "non-silent bounded PCM: " + kind)
		if kind in [&"pursuit_drone", &"heartbeat", &"radar_pulse"]:
			check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == data.size() / 2, "complete loop: " + kind)
		if kind in [&"lane_left", &"lane_right"]:
			var energy := [0.0, 0.0]
			for i in range(0, data.size(), 4):
				energy[0] += absf(data.decode_s16(i))
				energy[1] += absf(data.decode_s16(i + 2))
			check(stream.stereo and (energy[0] > energy[1]) == (kind == &"lane_left"), "lane stereo pan: " + kind)
	# Drive game time synchronously. Fresh slots isolate each demo tick from the
	# real-time mixer; actual mixer contention is exercised by the burst below.
	for i in 405:
		audio.one_shots.stop()
		audio.one_shots.play()
		audio._playback = audio.one_shots.get_stream_playback()
		audio._voices.clear()
		audio._voice_kinds.clear()
		mock.advance_demo(0.1)
		audio._process(0.1)
	check(mock.state == &"finished", "audio demo completes")
	# New contract 2.6 cues use the real progress feed, including a skip and seven bursts.
	mock.state_changed.emit(&"running")
	for mode in [&"intro_full", &"intro_short", &"defeat_full"]:
		audio.one_shots.stop()
		audio.one_shots.play()
		audio._playback = audio.one_shots.get_stream_playback()
		audio._voices.clear()
		audio._voice_kinds.clear()
		mock.boss_cinematic_progress = 0.0
		mock.boss_cinematic.emit(&"flaky_test_swarm", mode, 5.0)
		for i in 20:
			audio.one_shots.stop()
			audio.one_shots.play()
			audio._playback = audio.one_shots.get_stream_playback()
			audio._voices.clear()
			audio._voice_kinds.clear()
			mock.boss_cinematic_progress = float(i) / 20
			audio._process(0.15)
			await process_frame
		if mode == &"intro_short": mock.boss_cinematic_skipped.emit(mode)
		mock.boss_cinematic_ended.emit(mode)
	for kind: StringName in Synth.RECIPES:
		check(int(counts.get(kind, 0)) > 0, "demo played trigger: " + kind)
	check(counts.get(&"heartbeat", 0) == 1, "demo heartbeat starts exactly once across low progress ticks")
	check(not audio.heartbeat.playing and not audio.drone.playing, "finished stops pursuit loops")
	# Explicit edge cases, cadence, pause, smoothing and a saturated pursuit.
	mock.state_changed.emit(&"running")
	mock.player_action.emit(&"land")
	mock.speed_changed.emit(12.0, 0.0)
	audio._step_time = 0.0
	var steps := int(counts.get(&"footstep", 0))
	audio._process(0.41)
	check(counts.get(&"footstep", 0) == steps, "slow cadence waits 0.42 seconds")
	audio._process(0.02)
	check(counts.get(&"footstep", 0) == steps + 1, "slow cadence step")
	mock.player_action.emit(&"jump")
	audio._process(1.0)
	check(not audio.footsteps.playing, "no airborne footsteps")
	mock.player_action.emit(&"roll")
	mock.player_action.emit(&"land")
	audio._process(1.0)
	check(not audio.footsteps.playing, "no rolling footsteps")
	mock.player_action.emit(&"roll_end")
	await create_timer(0.05).timeout
	mock.speed_changed.emit(32.0, 1.5)
	mock.power_up_collected.emit(&"nitro", 8.0)
	var previous_pitch: float = audio._pitch
	audio._process(0.01)
	check(audio._pitch > previous_pitch and audio._pitch < 1.2, "pitch smoothly approaches unclamped normalized plus nitro")
	audio._process(2.0)
	check(is_equal_approx(service.music.pitch_scale, 1.2), "pitch formula at nitro overspeed")
	mock.power_up_expired.emit(&"nitro")
	audio._process(2.0)
	check(absf(service.music.pitch_scale - 1.15) < 0.001, "nitro expiration lowers pitch")
	mock.paused_changed.emit(true)
	steps = int(counts.get(&"footstep", 0))
	audio._process(1.0)
	check(counts.get(&"footstep", 0) == steps and audio.one_shots.stream_paused, "pause freezes SFX and cadence")
	mock.paused_changed.emit(false)
	await create_timer(0.05).timeout
	mock.pursuit_started.emit(18.0)
	mock.pursuit_progress.emit(6.3, 18.0)
	check(audio.heartbeat.playing and audio.heartbeat.stream == Synth.sound(&"radar_pulse") and not audio._heartbeat_on, "radar remains at strict heartbeat threshold")
	audio._process(0.1)
	mock.hud.pursuit_alert._process(0.1)
	check(is_equal_approx(mock.hud.pursuit_alert.radar_phase, audio.pursuit_radar_phase()), "visual pulse and radar audio share a clock")
	for i in 20:
		mock.pursuit_progress.emit(6.0 - i * 0.1, 18.0)
	check(audio.heartbeat.stream == Synth.sound(&"heartbeat") and is_equal_approx(audio.heartbeat.pitch_scale, 0.8), "same player switches stream with pitch drop")
	check(counts.get(&"heartbeat", 0) == 2, "new pursuit resets heartbeat latch once")
	mock.damage_taken.emit(&"bug_swarm", 1)
	await wait_until(func() -> bool: return service.music.volume_db < -17.0, 5.0)
	check(service.music.volume_db < -17.0, "damage ducks music six dB")
	for kind in [&"jump", &"roll", &"lane_left", &"lane_right"]:
		mock.player_action.emit(kind)
	for kind in [&"nitro", &"lgtm", &"auto_fix"]:
		mock.power_up_collected.emit(kind, 1.0)
	mock.player_action.emit(&"land")
	mock.player_action.emit(&"roll_end")
	audio._process(0.3)
	check(peak[0] <= 10, "never exceeds ten voices")
	# No awaits: all seven slots and the footstep start in this same frame.
	audio.one_shots.stop()
	audio.one_shots.play()
	audio._playback = audio.one_shots.get_stream_playback()
	audio._voices.clear()
	audio._voice_kinds.clear()
	audio._pending.clear()
	audio._last_play.clear()
	check(audio.drone.playing and audio.heartbeat.playing, "pursuit loops already playing")
	audio._play(&"footstep", audio.footsteps)
	var ambient := [&"jump", &"roll", &"lane_left", &"lane_right", &"land", &"nitro", &"lgtm"]
	for kind in ambient:
		audio._play(kind)
	check(audio._voices.size() == 7 and audio.active_voice_count() == 10, "seven ambient one-shots plus three dedicated players saturate at exactly ten")
	var before_burst := counts.duplicate()
	var oldest_ambient: Array = audio._voices.slice(0, 2)
	# Still the same frame: important cues must reserve the two oldest ambient slots.
	audio._play(&"hit")
	audio._play(&"caught")
	check(audio._pending.has(&"hit") and audio._pending.has(&"caught"), "same-frame important cues queue for mixer release")
	check(audio._voices.size() == 5 and not audio._voices.has(oldest_ambient[0]) and not audio._voices.has(oldest_ambient[1]), "important cues evict only the two oldest ambient voices")
	var reserved_survivors: Array = audio._voices.duplicate()
	for i in 3:
		audio._process(0.001)
	check(audio._voices == reserved_survivors, "pending retries do not repeatedly evict ambient voices")
	var previous_max_fps := Engine.max_fps
	Engine.max_fps = 60
	# Dummy mixer ticks can be 100 ms apart; advance game time explicitly.
	for i in 20:
		await process_frame
		audio._process(0.004)
		# Sustained ambient demand cannot take reserved slots or evict important voices.
		var protected_voices: Array = []
		for voice in audio._voices:
			if audio.HIGH_PRIORITY.has(audio._voice_kinds[voice]):
				protected_voices.append(voice)
		audio._last_play.clear()
		for kind in ambient + [&"footstep", &"auto_fix"]:
			audio._play(kind)
		for voice in protected_voices:
			check(audio._voices.has(voice), "ambient demand never displaces an important voice")
		if counts.get(&"hit", 0) > before_burst.get(&"hit", 0) and counts.get(&"caught", 0) > before_burst.get(&"caught", 0):
			break
	Engine.max_fps = previous_max_fps
	for kind in [&"hit", &"caught"]:
		check(int(counts.get(kind, 0)) == int(before_burst.get(kind, 0)) + 1, "same-frame important cue eventually plays exactly once: " + kind)
	# Negative case and TTL boundary, without yielding to the mixer.
	audio.one_shots.stop()
	audio.one_shots.play()
	audio._playback = audio.one_shots.get_stream_playback()
	audio._voices.clear()
	audio._voice_kinds.clear()
	audio._pending.clear()
	audio._last_play.clear()
	for kind in [&"hit", &"caught", &"game_over", &"shield_block", &"pursuit_start", &"retreat", &"recovered_chime"]:
		audio._play(kind)
	var protected_pool: Array = audio._voices.duplicate()
	check(protected_pool.size() == 7, "negative case fills pool with important cues")
	var jumps_before := int(counts.get(&"jump", 0))
	audio._play(&"jump")
	audio._play(&"powerup")
	check(audio._voices == protected_pool, "ambient cue cannot evict any voice in an important-only pool")
	var queued_at: float = audio._pending[&"jump"]
	audio._play(&"jump")
	check(audio._pending[&"jump"] == queued_at, "pending duplicate does not extend TTL")
	audio._process(0.121)
	check(not audio._pending.has(&"jump") and counts.get(&"jump", 0) == jumps_before, "ambient cue drops after 120 ms without playback")
	check(audio._pending.has(&"powerup"), "important cue survives ambient TTL")
	check(audio._voices == protected_pool, "pending retries preserve important-only pool")
	audio._process(0.180)
	check(not audio._pending.has(&"powerup"), "important pending cue expires after 300 ms")
	var jumps := int(counts.get(&"jump", 0))
	mock.player_action.emit(&"jump")
	mock.player_action.emit(&"jump")
	check(counts.get(&"jump", 0) <= jumps + 1, "same sound rate limited within 40 ms")
	mock.pursuit_recovered.emit(&"timer")
	check(not audio.heartbeat.playing, "recovery stops heartbeat")
	await wait_until(func() -> bool: return not audio.drone.playing and is_equal_approx(service.music.volume_db, -12.0), 5.0)
	check(not audio.drone.playing and is_equal_approx(service.music.volume_db, -12.0), "drone fades out and music duck recovers")
	mock.pursuit_started.emit(18.0)
	mock.pursuit_progress.emit(1.0, 18.0)
	mock.caught.emit()
	check(not audio.heartbeat.playing, "caught stops heartbeat")
	check(service.get_child_count() == 2, "AudioService retains exactly two child players")
	# F8 burst keeps the existing seven plus three voice allocation.
	mock.state_changed.emit(&"running")
	mock.boss_spawned.emit(&"flaky_test_swarm", 100)
	mock.boss_spawned.emit(&"flaky_test_swarm", 100)
	check(is_equal_approx(service.music_volume_db, -16.0), "boss holds baseline once")
	await wait_until(func() -> bool: return service.duck == null and is_equal_approx(service.music.volume_db, -16.0), 5.0)
	check(service.duck == null and is_equal_approx(service.music.volume_db, -16.0), "boss hold does not refresh duck tweens")
	for i in 3: mock.tool_collected.emit(&"unit_test", 15)
	for mask in [1, 4]: mock.boss_projectile_fired.emit(null, mask, &"orb", 34.0)
	mock.boss_phase_changed.emit(2)
	audio._process(0.15)
	check(audio.active_voice_count() <= 10, "boss burst voice cap")
	check(audio.GATE.get(&"boss_hit") == 0.09, "boss hit retrigger gate is 90ms")
	for cue in [&"boss_phase", &"boss_defeat", &"tool_fire"]: check(audio.HIGH_PRIORITY.has(cue), "boss high priority " + cue)
	var scheduled: int = audio._scheduled.size()
	mock.paused_changed.emit(true)
	audio._process(0.5)
	check(audio._scheduled.size() == scheduled, "pause freezes scheduled boss cues")
	mock.paused_changed.emit(false)
	mock.boss_defeated.emit(&"flaky_test_swarm", 800)
	check(not audio._boss_active and is_equal_approx(service.music_volume_db, -12.0), "boss defeat releases music hold")
	mock.boss_spawned.emit(&"flaky_test_swarm", 100)
	mock.boss_retreated.emit(&"flaky_test_swarm", 0)
	check(is_equal_approx(service.music_volume_db, -12.0) and audio._boss_pitch_offset == 0, "boss retreat releases mix offsets")
	mock.turn_started.emit(-1, 2.5)
	check(is_equal_approx(service.music_volume_db, -17.0), "turn holds minus 5 dB")
	mock.turn_finished.emit()
	check(is_equal_approx(service.music_volume_db, -12.0), "turn restores music")
	for mask in [1, 4]:
		var pan := Synth.panned_whoosh(mask, &"turn_whoosh")
		var energy := [0.0, 0.0]
		for i in range(0, pan.data.size(), 4):
			energy[0] += absf(pan.data.decode_s16(i))
			energy[1] += absf(pan.data.decode_s16(i + 2))
		check((energy[0] > energy[1]) == (mask == 1), "turn directional stereo pan")
	mock.stage_cleared.emit(1, 400)
	audio._process(1.0)
	check(is_equal_approx(service.music_volume_db, -22.0) and audio._pitch == 1.0, "stage card holds minus 10 dB and pitch 1")
	mock.paused_changed.emit(true)
	var remaining: float = audio._clear_remaining
	audio._process(10.0)
	check(audio._clear_remaining == remaining, "pause freezes stage music hold")
	mock.paused_changed.emit(false)
	audio._process(2.0)
	check(is_equal_approx(service.music_volume_db, -12.0), "stage card releases hold")
	print("RUNNER AUDIO: 37 recipes/triggers; demo heartbeat starts=1; peak voices=", peak[0], "; AudioService players=", service.get_child_count())
	mock.free()
	await frames()
	check(is_equal_approx(service.music.pitch_scale, 1.0), "audio teardown resets pitch")

var loop_board_path := "user://test_runner_menu_leaderboard_%d.cfg" % OS.get_process_id()
var loop_instances := 0

## node_added fires before _ready, including for a fresh AppRouter retry scene.
func _isolate_routed_game(node: Node) -> void:
	if node.scene_file_path != "res://scenes/runner/runner_game.tscn":
		return
	node.autostart = false
	node.leaderboard_path = loop_board_path
	loop_instances += 1
	node.ready.connect(func() -> void:
		node.start_run(4706 + loop_instances)
		node.set_autopilot(true)
	, CONNECT_ONE_SHOT)

func _wait_for(predicate: Callable, seconds: float, message: String) -> bool:
	var success := await wait_until(predicate, seconds)
	check(success, message)
	return success

func _force_loop_hit(game: Node) -> void:
	var hazard := load("res://scenes/runner/hazards/hazard.tscn").instantiate() as Area3D
	hazard.kind = &"pr_backlog_low"
	check(game.hit_manager.report_hit(hazard) == &"damaged", "full loop forced hazard applies damage")
	hazard.free()

func check_runner_full_loop() -> void:
	var before := failures
	var router := root.get_node("AppRouter")
	var audio := root.get_node("AudioService")
	node_added.connect(_isolate_routed_game)
	router.go("runner")
	await _wait_for(func() -> bool: return not router.busy, 5, "runner route completes")
	check(current_scene != null and current_scene.name == &"RunnerMenu", "runner route is RunnerMenu")
	var menu := current_scene
	check(menu is Node3D and menu.buttons[0].has_focus(), "menu root and initial Play focus")
	check(menu.get_node("Backdrop/Camera").fov == 55, "menu camera FOV")
	check(menu.get_node("Backdrop/Hoppy").anim_state == &"run", "menu Hoppy jogs")
	check(audio.music.stream == menu.Music and audio.music.volume_db == -12.0, "menu music")
	menu.buttons[1].pressed.emit()
	await frames()
	check(menu.modal != null and menu.board.get_child_count() == 10, "leaderboard has ten rows")
	check(root.gui_get_focus_owner().text == "Close", "leaderboard focuses Close")
	for i in [0, 2, 3]:
		check(menu.buttons[i].disabled and menu.buttons[i].focus_mode == Control.FOCUS_NONE, "modal blocks other menu action %d" % i)
	check(not menu.buttons[1].disabled and menu.buttons[1].focus_mode == Control.FOCUS_ALL, "leaderboard toggle remains enabled and focusable")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	menu._unhandled_input(cancel)
	check(menu.modal == null and menu.buttons[1].has_focus() and not router.busy, "cancel closes board and restores focus before routing")
	menu.buttons[1].pressed.emit()
	menu.buttons[1].pressed.emit()
	check(menu.modal == null and menu.buttons[1].has_focus(), "leaderboard button toggles closed and restores focus")
	var track: AudioStream = audio.music.stream
	menu.buttons[0].pressed.emit()
	await _wait_for(func() -> bool: return not router.busy, 5, "Play routes to game")
	var game := current_scene
	check(game != null and game.name == &"RunnerGame" and game.state == &"running", "runner_game is running")
	check(game.leaderboard_path == loop_board_path and game.autopilot.enabled, "first routed run isolated with autopilot")
	check(audio.music.stream == track, "menu to game keeps runner track")
	var events := {"pursuit": 0, "recovery": [], "caught": 0, "finished": 0}
	game.pursuit_started.connect(func(_seconds: float) -> void: events.pursuit += 1)
	game.pursuit_recovered.connect(func(reason: StringName) -> void: events.recovery.append(reason))
	game.caught.connect(func() -> void: events.caught += 1)
	game.run_finished.connect(func(_result: Dictionary) -> void: events.finished += 1)
	_force_loop_hit(game)
	check(game.hp == 1 and game.hit_manager.is_pursued() and events.pursuit == 1, "first hit starts pursuit")
	var recovery_start: float = game.elapsed
	var recovery_seconds := float(game.config.recovery_seconds)
	await _wait_for(func() -> bool: return not events.recovery.is_empty() or game.state != &"running", recovery_seconds + 6.0, "natural recovery arrives")
	check(events.recovery == [&"timer"] and game.hp == 2 and game.hit_manager.is_safe(), "%s second timer recovers HP and safe state" % recovery_seconds)
	check(game.elapsed - recovery_start >= recovery_seconds, "recovery uses full %s second contract timer" % recovery_seconds)
	_force_loop_hit(game)
	check(game.hp == 1 and game.hit_manager.is_pursued() and events.pursuit == 2, "next hit starts new pursuit")
	await _wait_for(func() -> bool: return not game.hit_manager.is_invulnerable(), 3, "hit iframes expire naturally")
	_force_loop_hit(game)
	check(game.state == &"caught" and events.caught == 1, "second pursuit hit catches runner once")
	var over := game.get_node("Overlays/GameOver")
	check(not over.visible and events.finished == 0, "game over waits for run_finished")
	await _wait_for(func() -> bool: return events.finished > 0, 5, "catch emits run_finished")
	check(game.state == &"finished" and events.finished == 1 and over.visible, "finished shows game over exactly once")
	check(game.submit_name("Codex"), "Codex name persists")
	var entries: Array = game.get_leaderboard()
	check(entries.size() == 1 and entries[0].name == "Codex", "temporary board contains saved run")
	game.retry()
	await _wait_for(func() -> bool: return not router.busy, 5, "retry route completes")
	game = current_scene
	check(game.name == &"RunnerGame" and game.state == &"running" and loop_instances == 2, "retry creates fresh running scene")
	check(game.leaderboard_path == loop_board_path and game.autopilot.enabled, "retry is isolated before start_run")
	game.go_to_menu()
	await _wait_for(func() -> bool: return not router.busy, 5, "go_to_menu completes")
	check(current_scene.name == &"RunnerMenu" and not paused, "facade returns to RunnerMenu unpaused")
	# Exercise the menu's actual cancel route, which calls AppRouter.go("hub").
	current_scene._unhandled_input(cancel)
	await _wait_for(func() -> bool: return not router.busy, 5, "hub route completes")
	check(current_scene.name == &"MainMenu", "hub is MainMenu")
	check(audio.music.stream == audio.default_track and audio.music.playing, "hub restores default music")
	node_added.disconnect(_isolate_routed_game)
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = loop_board_path + suffix
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "temporary leaderboard cleanup")
	check(not FileAccess.file_exists(loop_board_path), "temporary leaderboard removed")
	print("RUNNER FULL LOOP: ", "PASS" if before == failures else "FAIL", " (menu, play, hit, pursuit, %ss timer recovery, hit, hit, caught, finished, game over, Codex, retry, menu, hub, default music; isolated board removed)" % recovery_seconds)
	current_scene.free()
	await frames()

func check_runner_menu_reset() -> void:
	var before := failures
	var reset_board_path := "user://test_runner_menu_reset_%d.cfg" % OS.get_process_id()
	var RunnerLeaderboard = load("res://scenes/runner/systems/runner_leaderboard.gd")

	# Seed synthetic entries so the board is non-empty.
	for i in 3:
		RunnerLeaderboard.submit({
			"run_id": "reset-seed-%d" % i, "name": "Tester", "score": 100 + i * 10,
			"duration": 60.0, "seed": 1, "submitted_at": 1700000000
		}, reset_board_path)

	var router := root.get_node("AppRouter")
	router.go("runner")
	await _wait_for(func() -> bool: return not router.busy, 5, "reset test: runner route completes")
	var menu := current_scene
	check(menu != null and menu.name == &"RunnerMenu", "reset test: at RunnerMenu")
	menu.leaderboard_path = reset_board_path

	# Open leaderboard. Check initial state: Reset enabled, Close focused.
	menu.buttons[1].pressed.emit()
	await frames()
	check(menu.modal != null and menu.board != null, "reset test: leaderboard panel open")
	check(is_instance_valid(menu.reset_btn) and not menu.reset_btn.disabled, "reset test: Reset scores enabled for non-empty board")
	check(is_instance_valid(menu.close_btn) and root.gui_get_focus_owner() == menu.close_btn, "reset test: Close has initial focus")

	# Cancel via button: bytes unchanged, no routing, focus restored to Reset.
	var bytes_before := FileAccess.get_file_as_bytes(reset_board_path)
	menu.reset_btn.pressed.emit()
	await frames()
	check(menu.reset_confirm != null, "reset test: confirmation modal opens")
	var keep_btn := menu.reset_confirm.find_child("KeepScoresButton", true, false) as Button if menu.reset_confirm != null else null
	check(keep_btn != null and root.gui_get_focus_owner() == keep_btn, "reset test: safe action focused on confirm open")
	if keep_btn != null:
		keep_btn.pressed.emit()
	await frames()
	check(menu.reset_confirm == null, "reset test: button cancel closes confirmation")
	check(FileAccess.get_file_as_bytes(reset_board_path) == bytes_before, "reset test: cancel leaves board bytes unchanged")
	check(not router.busy, "reset test: cancel does not route")
	check(is_instance_valid(menu.reset_btn) and root.gui_get_focus_owner() == menu.reset_btn, "reset test: cancel restores focus to Reset scores")

	# Cancel via ui_cancel: same guarantees.
	menu.reset_btn.pressed.emit()
	await frames()
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	menu._unhandled_input(cancel_event)
	await frames()
	check(menu.reset_confirm == null, "reset test: ui_cancel closes confirmation")
	check(menu.modal != null, "reset test: ui_cancel does not close leaderboard")
	check(FileAccess.get_file_as_bytes(reset_board_path) == bytes_before, "reset test: ui_cancel cancel leaves bytes unchanged")
	check(is_instance_valid(menu.reset_btn) and root.gui_get_focus_owner() == menu.reset_btn, "reset test: ui_cancel restores focus to Reset scores")

	# Confirm reset: placeholder rows, zero entries, companions purged, Reset disabled, Close focused.
	menu.reset_btn.pressed.emit()
	await frames()
	var confirm_btn := menu.reset_confirm.find_child("ResetConfirmButton", true, false) as Button if menu.reset_confirm != null else null
	check(confirm_btn != null, "reset test: ResetConfirmButton found")
	if confirm_btn != null:
		confirm_btn.pressed.emit()
	await frames()
	check(menu.reset_confirm == null, "reset test: confirm closes modal")
	var reloaded: Array = RunnerLeaderboard.load_entries(reset_board_path)
	check(reloaded.is_empty(), "reset test: board has zero entries after reset")
	check(not FileAccess.file_exists(reset_board_path + ".bak"), "reset test: .bak removed after reset")
	check(not FileAccess.file_exists(reset_board_path + ".tmp"), "reset test: .tmp absent after reset")
	check(is_instance_valid(menu.reset_btn) and menu.reset_btn.disabled, "reset test: Reset scores disabled after successful reset")
	check(is_instance_valid(menu.close_btn) and root.gui_get_focus_owner() == menu.close_btn, "reset test: Close focused after successful reset")
	if menu.board != null:
		for row in menu.board.get_children():
			check(row.get_child_count() >= 2, "reset test: row has children")
			var lbl := row.get_child(1) as Label if row.get_child_count() >= 2 else null
			check(lbl != null and "---" in lbl.text, "reset test: row shows placeholder after reset")

	# Close the leaderboard before the failure-path test.
	menu.close_btn.pressed.emit()
	await frames()
	check(menu.modal == null, "reset test: leaderboard closed")

	# Failure path: blocker file stands where the board directory would be.
	var blocker := "user://test_runner_menu_reset_blocker_%d" % OS.get_process_id()
	var blocker_file := FileAccess.open(blocker, FileAccess.WRITE)
	if blocker_file != null:
		blocker_file.store_string("not a directory")
		blocker_file.close()
	var blocked_path := blocker + "/leaderboard.cfg"
	# The blocked path can't be seeded (it can't be written), so open the seeded scratch board, then
	# point the board the menu captured at open time at the blocked path before confirming.
	RunnerLeaderboard.submit({
		"run_id": "fail-seed", "name": "Fail", "score": 50,
		"duration": 30.0, "seed": 1, "submitted_at": 1700000000
	}, reset_board_path)
	menu.leaderboard_path = reset_board_path
	menu.buttons[1].pressed.emit()
	await frames()
	check(menu.modal != null, "reset test: failure-path leaderboard open")
	# _confirm_reset() clears leaderboard_path_at_open (snapshotted when the board opened), so
	# changing leaderboard_path here would not reach it. Redirect the snapshot instead.
	menu.leaderboard_path_at_open = blocked_path
	menu.reset_btn.pressed.emit()
	await frames()
	var fail_confirm_btn := menu.reset_confirm.find_child("ResetConfirmButton", true, false) as Button if menu.reset_confirm != null else null
	if fail_confirm_btn != null:
		fail_confirm_btn.pressed.emit()
		await frames()
		check(menu.reset_confirm != null, "reset test: failure keeps confirmation open")
		var status: Label = menu.confirm_status
		check(status != null and status.visible, "reset test: error status visible on failure")
		var safe_btn := menu.reset_confirm.find_child("KeepScoresButton", true, false) as Button
		check(safe_btn != null and root.gui_get_focus_owner() == safe_btn, "reset test: safe action focused on failure")
	else:
		check(false, "reset test: failure-path ResetConfirmButton not found")

	# Cleanup.
	menu._close_leaderboard()
	await frames()
	var cancel_ev := InputEventAction.new()
	cancel_ev.action = &"ui_cancel"
	cancel_ev.pressed = true
	menu._unhandled_input(cancel_ev)
	await _wait_for(func() -> bool: return not router.busy, 5, "reset test: hub route completes")
	if FileAccess.file_exists(blocker):
		DirAccess.remove_absolute(blocker)
	for suffix in ["", ".tmp", ".bak"]:
		var p: String = reset_board_path + suffix
		if FileAccess.file_exists(p):
			check(DirAccess.remove_absolute(p) == OK, "reset test: scratch board cleanup %s" % suffix)
	check(not FileAccess.file_exists(reset_board_path), "reset test: scratch board removed")
	print("RUNNER MENU RESET: ", "PASS" if before == failures else "FAIL")

func check_hud_legibility() -> void:
	var before := failures
	var mock := load("res://scenes/runner/ui/dev/mock_runner_game.gd").new() as Node
	mock.autoplay = false
	root.add_child(mock)
	mock.start_run()
	mock.collect(&"nitro", 8.0)
	mock.pursuit_started.emit(18.0)
	mock.finish_demo()
	await frames()
	var count := 0
	for overlay in [mock.hud, mock.pause_menu, mock.game_over]:
		for label: Label in overlay.find_children("*", "Label", true, false):
			count += 1
			var size_units := label.get_theme_font_size("font_size")
			check(size_units >= 18 or label.has_meta("legibility_exemption"), "critical label >=18: " + label.text)
			check(label.get_theme_constant("outline_size") >= 6, "label outline >=6: " + label.text)
			var parent := label.get_parent()
			while parent != null and not parent is PanelContainer:
				parent = parent.get_parent()
			check(parent != null, "label has backing: " + label.text)
	var hud: Node = mock.hud
	hud._score(100, 2.0)
	check(hud.multiplier_label.text == "×2", "integral multiplier omits decimal")
	hud._score(100, 1.5)
	check(hud.multiplier_label.text == "×1.5", "fractional multiplier preserved")
	hud._state(&"running")
	hud._toast("+250 BONUS")
	hud._process(0.01)
	hud._toast("INCOMING", 100)
	check(hud.toast.text == "INCOMING", "urgent toast preempts bonus")
	check(hud.toast_queue.any(func(entry: Dictionary) -> bool: return entry.text == "+250 BONUS"), "preempted toast retained")
	hud._process(0.12)
	check(is_equal_approx(hud.toast_panel.modulate.a, 1.0), "toast fades in over 0.12 seconds")
	hud._state(&"running")
	hud._toast("FIRST", 0, Color.CORAL)
	hud._process(0.01)
	hud._toast("SECOND", 0, Color.CYAN)
	hud._toast("THIRD", 0, Color.GOLD)
	hud._toast("INCOMING", 100)
	check(hud.toast_queue[0].text == "FIRST" and hud.toast_queue[0].accent == Color.CORAL, "preempted toast preserves accent and original FIFO position")
	hud._process(1.6)
	check(hud.toast.text == "FIRST" and hud.toast_accent == Color.CORAL, "preempted toast resumes with original accent")
	hud._process(1.6)
	check(hud.toast.text == "SECOND", "equal-priority second toast retains FIFO order")
	hud._process(1.6)
	check(hud.toast.text == "THIRD", "equal-priority third toast retains FIFO order")
	var startup := load("res://scenes/runner/ui/dev/mock_runner_game.gd").new() as Node
	startup.autoplay = false
	root.add_child(startup)
	startup.hud.set_process(false)
	startup.start_run()
	check(startup.hud.ready_panel.visible, "real ready-to-running startup preserves GET READY")
	startup.hud._process(2.5)
	check(startup.hud.ready_panel.visible, "get ready holds 2.5 seconds")
	startup.hud._process(0.25)
	check(not startup.hud.ready_panel.visible, "get ready fades after 2.5 seconds")
	startup.free()
	check(not hud.chips[&"nitro"].label.visible, "power-up name cut after 0.6 seconds")
	check(count >= 60, "legibility census includes teaching legend, dynamic result rows and stats")
	print("HUD LEGIBILITY: ", "PASS" if before == failures else "FAIL", " (", count, " labels checked)")
	mock.free()
	await frames()

func count_pursuit_alerts(node: Node) -> int:
	var count := 1 if node.get_script() == preload("res://scenes/runner/ui/pursuit_alert.gd") else 0
	for child in node.get_children():
		count += count_pursuit_alerts(child)
	return count

func check_pursuit_alert() -> void:
	var before := failures
	var mock := load("res://scenes/runner/ui/dev/mock_runner_game.gd").new() as Node
	mock.autoplay = false
	root.add_child(mock)
	mock.start_run()
	check(count_pursuit_alerts(mock) == 1, "standalone HUD mounts exactly one pursuit alert")
	mock.hud.bind(mock)
	check(count_pursuit_alerts(mock) == 1, "same-game HUD bind preserves exactly one fallback alert")
	var alert: Control = mock.hud.pursuit_alert
	alert.set_process(false)
	var connections: int = mock.pursuit_started.get_connections().size()
	alert.bind(mock)
	alert.bind(mock)
	check(mock.pursuit_started.get_connections().size() == connections, "alert same-game binding is idempotent")
	check(alert.process_mode == Node.PROCESS_MODE_PAUSABLE, "alert PAUSABLE contract")
	mock.pursuit_started.emit(18.0)
	mock.pursuit_alert.emit(&"warn", 18.0)
	check(alert.visible and alert.position.x == -440, "alert starts offscreen and visible")
	alert._process(0.28)
	check(is_equal_approx(alert.position.x, 28), "cubic slide reaches 28 at 0.28s")
	check(alert.catch_rule.text.replace("\n", " ") == "ONE MORE HIT BEFORE RECOVERY AND IT HAS YOU", "alert states catch rule")
	var previous_rate := 0.0
	for remaining in [18.0, 12.0, 6.0, 0.0]:
		mock.pursuit_progress.emit(remaining, 18.0)
		check(alert.radar_rate > previous_rate, "radar rate strictly increases")
		previous_rate = alert.radar_rate
		check(alert.countdown.text == "CATCHES UP IN %.1f s" % remaining, "live countdown")
		alert._process(0.1)
	check(alert.portrait_viewport.size == Vector2i(256, 256) and alert.portrait_viewport.disable_3d, "portrait 256x256 2D viewport")
	check(alert.portrait_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "portrait renders deterministically")
	var back_buffer := alert.portrait_viewport.get_child(1) as BackBufferCopy
	check(back_buffer != null and back_buffer.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT, "portrait copies art before scanline screen read")
	check(alert.portrait.texture == alert.portrait_viewport.get_texture(), "portrait displays viewport texture")
	await frames()
	# The dummy headless renderer cannot read pixels; the host capture verifies pixels.
	if DisplayServer.get_name() != "headless":
		var rendered: Image = alert.portrait_viewport.get_texture().get_image()
		check(rendered != null and not rendered.is_empty(), "portrait renders pixels")
	mock.pause()
	var saved_clock: float = alert.clock
	var saved_phase: float = alert.radar_phase
	var saved_position := alert.position
	var saved_shader: float = alert.portrait_material.get_shader_parameter("clock")
	alert._process(1.0)
	check(alert.clock == saved_clock and alert.radar_phase == saved_phase and alert.position == saved_position, "facade pause freezes all alert animation")
	check(alert.portrait_material.get_shader_parameter("clock") == saved_shader, "facade pause freezes scanline shader")
	mock.resume()
	alert.set_process(true)
	paused = true
	await frames()
	check(alert.clock == saved_clock, "tree pause freezes alert")
	paused = false
	alert.set_process(false)
	mock.damage_blocked.emit(&"bug_swarm", &"shield")
	alert._process(0.1)
	check(alert.heading.text == "BLOCKED" and alert.visible, "blocked flash retains alert")
	alert._process(0.51)
	check(alert.heading.text == "INCOMING TRANSMISSION", "blocked clears after 0.6s")
	mock.pursuit_recovered.emit(&"timer")
	alert._process(1.19)
	check(alert.visible and alert.heading.text == "RECOVERED" and alert.countdown.text == "+2 APPROVALS", "recovered holds 1.2s")
	alert._process(0.24)
	check(not alert.visible, "recovered slides out")
	mock.pursuit_started.emit(18.0)
	mock.caught.emit()
	alert._process(0.45)
	check(alert.visible and alert.portrait.scale.is_equal_approx(Vector2(1.35, 1.35)), "caught portrait fills and grows")
	check(not mock.hud.score_label.is_visible_in_tree() and alert.is_visible_in_tree(), "caught hides gameplay but preserves portrait")
	alert._process(0.23)
	check(not alert.visible, "caught slides out")
	mock.free()
	await frames()
	var legacy := LegacyPursuitGame.new()
	root.add_child(legacy)
	var standalone := load("res://scenes/runner/ui/pursuit_alert.tscn").instantiate() as Control
	root.add_child(standalone)
	standalone.bind(legacy)
	standalone.bind(legacy)
	check(not legacy.has_signal("pursuit_alert"), "legacy fixture lacks optional v2 signal")
	legacy.pursuit_started.emit(10.0)
	legacy.pursuit_progress.emit(4.0, 10.0)
	check(standalone.visible and standalone.countdown.text == "CATCHES UP IN 4.0 s", "standalone alert works with v1 signals only")
	legacy.pursuit_recovered.emit(&"timer")
	check(standalone.heading.text == "RECOVERED", "v1 recovery beat")
	standalone.free()
	legacy.free()
	print("PURSUIT ALERT: ", "PASS" if before == failures else "FAIL")

## Includes the CPU MultiMesh poses that the dummy rendering server cannot return.
func boss_geometry_bounds(visual: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node: Node3D in visual.find_children("*", "VisualInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
		if node is MultiMeshInstance3D:
			var builder := node.get_parent()
			check("batches" in builder, "F8 batch has CPU poses")
			for entry: Dictionary in builder.batches:
				if entry.node != node: continue
				for pose: Transform3D in entry.poses:
					if pose.basis.determinant() == 0: continue
					var box: AABB = visual.global_transform.affine_inverse() * node.global_transform * pose * AABB(-Vector3.ONE * 0.5, Vector3.ONE)
					result = box if first else result.merge(box)
					first = false
		elif node is MeshInstance3D and node.skin != null:
			var box: AABB = visual.global_transform.affine_inverse() * BossBounds.mesh_bounds(node)
			result = box if first else result.merge(box)
			first = false
		elif not node is Label3D:
			var box: AABB = visual.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
			result = box if first else result.merge(box)
			first = false
	return result

func check_boss_envelope(visual: Node3D, context: String, entrance: bool = false) -> void:
	var box := boss_geometry_bounds(visual)
	if entrance:
		# Standalone visuals omit the arena's 2.6 m lift; normalize to that mount.
		var arena_box := visual.transform * box
		arena_box.position.y += 2.6
		check(arena_box.position.x >= -3.501 and arena_box.end.x <= 3.501, "intro x box " + context + " " + str(arena_box))
		check(arena_box.position.y >= 1.599 and arena_box.end.y <= 6.101, "intro y box " + context + " " + str(arena_box))
		check(arena_box.end.z <= visual.hover_z + 3.001, "intro travels only toward far end " + context)
		return
	check(box.size.x <= 7.01 and box.size.y <= 4.51 and box.size.z <= 3.01, "boss envelope " + context + " " + str(box))
	check(box.end.y + visual.position.y <= 3.501, "boss top <= 6.1 " + context)
	check(box.position.y + visual.position.y >= -1.001, "boss bottom >= 1.6 " + context)

func check_bosses() -> void:
	var before := failures
	var peak := 0
	for kind in [&"flaky_test_swarm", &"merge_conflict_hydra", &"legacy_monolith"]:
		var scene := load("res://scenes/runner/boss/visuals/%s_visual.tscn" % kind) as PackedScene
		check(scene != null, "boss scene loads " + kind)
		if scene == null: continue
		var visual := scene.instantiate() as Node3D
		root.add_child(visual)
		visual.kind = kind
		visual.boss_name = "Custom Boss Name"
		visual.max_hp = 100
		visual.phase_count = 3
		visual.hover_z = -14
		visual.sway_amplitude = 2.4
		visual.sway_period = 3.2
		visual.on_spawned()
		check(visual._tag.text.replace("\n", " ") == visual.boss_name, "boss plate reads boss_name")
		check(visual._tag.font_size >= 40 and visual._tag.position.y >= 3.15 and visual._tag.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR, "gallery plate above body and linearly filtered")
		var count := visual.find_children("*", "", true, false).size()
		visual.on_spawned()
		check(count == visual.find_children("*", "", true, false).size(), "idempotent boss spawn " + kind)
		check(visual.process_mode == Node.PROCESS_MODE_PAUSABLE, "boss PAUSABLE " + kind)
		check(visual._model != null, "accepted GLB mounted " + kind)
		visual.play_cinematic(&"intro_full", 3.0)
		for frame in 181:
			check_boss_envelope(visual, "%s intro frame %d" % [kind, frame], true)
			if frame < 180: visual.set_cinematic_progress(&"intro_full", float(frame + 1) / 180)
		visual.on_spawned()
		var boss_peak := 0
		for phase in [1, 2, 3]:
			visual.set_phase(phase)
			visual.set_health(100 - (phase - 1) * 35, 100)
			for i in 20:
				visual._process(0.045)
				check_boss_envelope(visual, "%s phase %d" % [kind, phase])
				boss_peak = maxi(boss_peak, hazard_draw_count(visual))
			for mask in [1, 2, 4, 3, 6, 7]:
				for variant in [&"orb", &"low", &"high", &"wide"]:
					visual.play_telegraph(mask, variant, 0.6)
					visual._process(0.3)
					check_boss_envelope(visual, "%s telegraph %s" % [kind, variant])
					visual.play_attack(variant)
					visual._process(0.06)
					check_boss_envelope(visual, String(kind) + " attack")
			# Contract 2.4 signature hooks: every signature variant, the optional commit, and fire.
			for variant in [&"scatter", &"sweep", &"force_push", &"slab", &"quake", &"debris"]:
				for mask in [2, 3, 5, 6, 7]:
					visual.play_telegraph(mask, variant, 0.7)
					for i in 3:
						visual._process(0.15)
						check_boss_envelope(visual, "%s signature telegraph %s" % [kind, variant])
						boss_peak = maxi(boss_peak, hazard_draw_count(visual))
					if visual.has_method("play_commit"):
						visual.play_commit(mask & -mask, variant, 0.25)
						visual._process(0.15)
						check_boss_envelope(visual, "%s commit %s" % [kind, variant])
					visual.play_attack(variant)
					for i in 5:
						visual._process(0.08)
						check_boss_envelope(visual, "%s signature attack %s" % [kind, variant])
						boss_peak = maxi(boss_peak, hazard_draw_count(visual))
			for tool in [&"review_comment", &"lint_rule", &"unit_test", &"auto_fix_patch"]:
				visual.play_hit(tool, 15)
				visual._process(0.09)
				check_boss_envelope(visual, String(kind) + " hit")
				visual.play_resist(tool)
				visual._process(0.09)
				check_boss_envelope(visual, String(kind) + " resist")
		var previous: Transform3D = visual.transform
		paused = true
		await frames()
		check(visual.transform == previous, "boss freezes on pause " + kind)
		paused = false
		for ending in [&"play_defeat", &"play_retreat"]:
			visual.on_spawned()
			visual.call(ending)
			if ending == &"play_defeat": visual.play_cinematic(&"defeat_full", 3.6)
			for i in 20:
				if ending == &"play_defeat": visual.set_cinematic_progress(&"defeat_full", float(i + 1) / 20)
				else: visual._process(0.05)
				check_boss_envelope(visual, String(kind) + " " + String(ending))
				boss_peak = maxi(boss_peak, hazard_draw_count(visual))
			visual._process(0.1)
			check(not visual.is_visible_in_tree() or not visual._model.visible or float(visual._model.materials[0].get_shader_parameter("dissolve")) >= 0.999, "boss terminal hides or fully dissolves")
		check(boss_peak <= 40, "boss peak draw budget " + kind)
		peak = maxi(peak, boss_peak)
		print("BOSS DRAW CENSUS: ", kind, "=", boss_peak)
		visual.free()
	print("BOSS VISUALS: ", "PASS" if before == failures else "FAIL", " (3 checked; peak draw census=", peak, ")")
	check(failures == before, "boss visual section")
	await frames()

## Contract 2.4: each boss's projectile look per signature variant, flown along its real motion,
## plus the per-boss telegraph modes on the standalone FX. Independent of a5_check's census.
func check_signature_projectiles() -> void:
	var before := failures
	var scene := preload("res://scenes/runner/hazards/visuals/projectile_visual.tscn")
	var slots := {&"flaky_test_swarm": 0, &"merge_conflict_hydra": 1, &"legacy_monolith": 2}
	for look: StringName in SignatureArt.LOOKS:
		var spec: Array = SignatureArt.LOOKS[look]
		var def: Dictionary = SignatureDefs.SLOTS[slots[spec[0]]]
		var shots: Array = []
		for phase in [1, 2, 3]:
			for beat: Dictionary in def.patterns[phase - 1]:
				if shots.is_empty() and StringName(beat.get("signature", &"")) == spec[2]:
					shots = SignatureAttacks.beat_options(beat, def, phase, null)[0][0].shots
		check(not shots.is_empty(), "signature shots for " + look)
		for shot: Dictionary in shots:
			var hazard := preload("res://scenes/runner/hazards/hazard_defs.gd").get_def(&"projectile", shot.variant)
			var size: Vector3 = hazard.size
			var offset := Vector3(0, float(hazard.y_min) + size.y * 0.5, 0)
			var visual := scene.instantiate()
			for key in ["variant", "projectile_variant"]: visual.set(key, shot.variant)
			visual.boss_kind = spec[0]
			visual.signature = spec[2]
			visual.motion = shot
			visual.hitbox_size = size
			visual.hitbox_offset = offset
			visual.closing_speed = float(shot.speed)
			root.add_child(visual)
			visual.on_spawned()
			check(visual.signature_variants and visual.get_node_or_null("BossProjectileArt") != null, "signature look mounted " + look)
			var window := SignatureAttacks.pass_window(shot)
			var age := 0.0
			while age < window.y:
				visual._process(0.03)
				age += 0.03
				check(hazard_draw_count(visual) <= 8, "signature projectile draw budget " + look)
				for node: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
					if not node.is_visible_in_tree(): continue
					var box: AABB = visual.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
					var half := size * 0.55 + Vector3.ONE * 0.002
					var low := box.position - offset
					var high := box.end - offset
					var ok := low.x >= -half.x and high.x <= half.x and low.z >= -half.z and high.z <= half.z
					if not node.has_meta("ground_projection"): ok = ok and low.y >= -half.y and high.y <= half.y
					check(ok, "signature projectile inside 110%% hitbox %s %s" % [look, node.name])
			var art: Node3D = visual.get_node("BossProjectileArt")
			var frozen: float = art.age
			paused = true
			await frames()
			check(art.age == frozen, "signature projectile freezes on pause " + look)
			paused = false
			visual.free()
	# Standalone FX: every signature telegraph mode lights the one-draw accent layer.
	var fx: Node3D = preload("res://scenes/runner/boss/boss_fx.tscn").instantiate()
	root.add_child(fx)
	var lit := {}
	for slot in 3:
		var def: Dictionary = SignatureDefs.SLOTS[slot]
		for phase in [1, 2, 3]:
			for beat: Dictionary in def.patterns[phase - 1]:
				var signature := StringName(beat.get("signature", &""))
				if signature == &"" or lit.has(signature): continue
				fx.clear()
				for attack: Dictionary in SignatureAttacks.beat_options(beat, def, phase, null)[0]:
					fx._planned(attack)
					fx._telegraph(int(attack.telegraph_mask), attack.variant, float(attack.telegraph))
				fx._process(0.4)
				lit[signature] = fx.marks.used
				check(fx.marks.visible and fx.marks.used > 0 and fx.marks is MultiMeshInstance3D and fx.marks.get_child_count() == 0, "signature telegraph mode lit " + signature)
				var danger := false
				for node in fx.telegraphs: danger = danger or node.active
				check(danger, "DANGER base telegraph under " + signature)
	check(lit.size() == SignatureAttacks.SIGNATURES.size(), "every signature has a telegraph mode (%s)" % [lit])
	fx.clear()
	check(not fx.marks.visible, "signature marks clear")
	fx.free()
	print("SIGNATURE VISUALS: ", "PASS" if failures == before else "FAIL", " (", SignatureArt.LOOKS.size(), " looks, ", lit.size(), " telegraph modes)")

func check_tools_and_projectiles() -> void:
	var before := failures
	for kind in [&"review_comment", &"lint_rule", &"unit_test", &"auto_fix_patch"]:
		var visual := (load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % kind) as PackedScene).instantiate() as Node3D
		root.add_child(visual)
		for cycle in 2:
			visual.on_spawned()
			var count := visual.find_children("*", "", true, false).size()
			visual.on_spawned()
			check(count == visual.find_children("*", "", true, false).size(), "tool idempotent spawn")
			check(visual.visible and hazard_draw_count(visual) <= 7, "tool draw budget " + kind)
			visual._art._process(0.25)
			check(visual._art.pivot.rotation == Vector3.ZERO, "tools do not spin")
			visual.on_collected()
			visual.on_collected()
			check(not visual.visible, "tool collect is idempotent")
		visual.free()
	var variants := [&"orb", &"low", &"high", &"wide"]
	var sizes := [Vector3(1.6, 0.9, 1.2), Vector3(5.6, 0.9, 1.2), Vector3(5.6, 0.4, 1.2), Vector3(3.6, 1, 1.2)]
	var projectile := preload("res://scenes/runner/hazards/visuals/projectile_visual.tscn").instantiate()
	root.add_child(projectile)
	for i in 4:
		projectile.variant = variants[i]
		projectile.hitbox_size = sizes[i]
		projectile.hitbox_offset = Vector3(0, 1.3 if i == 2 else sizes[i].y * 0.5, 0)
		projectile.closing_speed = 34
		projectile.on_spawned()
		projectile.on_spawned()
		for sample in 11:
			projectile._process(0.02)
			var box := boss_geometry_bounds(projectile)
			var permitted: Vector3 = sizes[i] * 1.1
			var relative: Vector3 = box.position - projectile.hitbox_offset
			check(relative.x >= -permitted.x / 2 - 0.001 and relative.y >= -permitted.y / 2 - 0.001 and relative.z >= -permitted.z / 2 - 0.001, "projectile lower bounds " + variants[i])
			var upper := relative + box.size
			check(upper.x <= permitted.x / 2 + 0.001 and upper.y <= permitted.y / 2 + 0.001 and upper.z <= permitted.z / 2 + 0.001, "projectile upper bounds " + variants[i])
		projectile.on_cleared()
		check(not projectile.visible, "cleared projectile hidden")
	projectile.free()
	await check_signature_projectiles()
	var mock := preload("res://scenes/runner/ui/dev/mock_runner_game.gd").new()
	mock.autoplay = false
	root.add_child(mock)
	var hud: Control = mock.boss_overlay
	hud.bind(mock)
	hud.bind(mock)
	check(mock.get_node_or_null("World") == null, "HUD mock has no fake World")
	mock.boss_fx.bind(mock)
	mock.boss_fx.bind(mock)
	check(mock.boss_fx.telegraphs.size() == 3, "idempotent standalone FX bind")
	mock.boss_phase_count = 4
	mock.boss_hp = 140
	mock.boss_spawned.emit(&"merge_conflict_hydra", 140)
	check(hud.pips.size() == 4, "HUD rebuilds phase_count pips")
	mock.boss_health_changed.emit(60, 140)
	mock.boss_phase_changed.emit(2)
	check(hud.visible and hud.title.text.contains("HYDRA") and hud.pips[1].filled and not hud.pips[2].filled, "boss HUD name and phase from facade")
	mock.boss_attack_telegraph.emit(5, &"wide", 0.6)
	var fx: Node3D = mock.boss_fx
	check(fx.telegraphs[0].active and not fx.telegraphs[1].active and fx.telegraphs[2].active, "telegraph lane mask bits")
	check(fx.telegraphs[0].tag.text == "WIDE", "telegraph names actual variant")
	for i in 8:
		mock.tool_collected.emit(&"lint_rule", 0 if i % 2 else 12)
	for tracer in fx.tracers: tracer._process(0.15)
	check(fx.tracers.size() == 4 and fx.numbers.size() == 6, "bounded auto-fire pools")
	var resisted := false
	for number in fx.numbers:
		resisted = resisted or number.tag.text == "RESISTED"
	check(resisted, "zero damage displays RESISTED")
	paused = true
	var frozen: float = fx.telegraphs[0].remaining
	await frames()
	check(fx.telegraphs[0].remaining == frozen, "telegraph freezes on pause")
	paused = false
	for node in fx.numbers + fx.telegraphs: node._process(1.0)
	for node in fx.numbers + fx.telegraphs + fx.tracers: check(not node.active, "FX pool returns idle")
	await wait_until(func() -> bool: return is_equal_approx(hud.hp.value, 60.0 / 140) and is_equal_approx(hud.chip.value, hud.hp.value), 5.0)
	check(is_equal_approx(hud.hp.value, 60.0 / 140) and is_equal_approx(hud.chip.value, hud.hp.value), "HP and delayed chip converge")
	mock.boss_defeated.emit(&"merge_conflict_hydra", 800)
	await wait_until(func() -> bool: return not hud.visible, 5.0)
	check(not hud.visible, "HUD exits on defeat")
	mock.free()
	await frames()
	# Exercise the actual backend mount and signals without simulating collisions by hand.
	var game := (load("res://scenes/runner/runner_game.tscn") as PackedScene).instantiate()
	game.autostart = false
	game.leaderboard_path = "user://test_runner_boss_mount_%d.cfg" % OS.get_process_id()
	root.add_child(game)
	var arena: Node = game.boss_encounter
	var boss_hud: Control
	for node in game.find_children("*", "Control", true, false):
		if node.get_script() == preload("res://scenes/runner/ui/boss_hud.gd"): boss_hud = node
	check(boss_hud != null, "backend mounts boss HUD")
	check(game.get_node_or_null("World/TurnRig/BossArena/BossFX") != null, "backend mounts standalone BossFX under arena")
	for stage in [1, 2, 3]:
		arena.start(stage)
		check(arena.visual.get_script().resource_path.contains("boss/visuals/"), "backend mounts shipped boss visual")
		var cinematic: Node = game.get_node("HUD/BossCinematic")
		check(cinematic.root.visible and not boss_hud.visible and cinematic.boss_name.text == String(game.get_boss_info().name).to_upper(), "real facade cinematic precedes HP plate")
		check(arena.visual.intro_calls == 1 and arena.visual._state == &"intro", "encounter forwards one cinematic entrance")
		arena.tick(float(game.config.boss_intro_seconds))
		check(boss_hud.visible and boss_hud.title.text.contains(String(game.get_boss_info().name).to_upper()), "real fight name plate after intro")
		while arena.phase < 2: arena.apply_tool(&"unit_test")
		check(boss_hud.pips[1].filled, "real fight phase pip")
		var previous_hp: int = arena.hp
		check(not arena.visual._tag.visible, "mounted boss HUD suppresses 3D name plate")
		if stage == 2: arena.apply_tool(&"review_comment")
		elif stage == 3: arena.apply_tool(&"unit_test")
		if stage > 1: check(arena.hp == previous_hp and arena.visual._model != null, "real phase resists wrong tool")
		arena.apply_tool(&"review_comment" if stage == 3 else &"unit_test")
		check(arena.hp < previous_hp, "real phase accepts correct tool")
		arena.abort()
	game.free()
	await frames()
	print("TOOLS AND PROJECTILES: ", "PASS" if failures == before else "FAIL")

func check_turn() -> void:
	var before := failures
	root.size = Vector2i(1280, 720)
	var corridor := preload("res://scenes/runner/environment/corridor.tscn").instantiate()
	root.add_child(corridor)
	corridor.set_process(false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 4, 8)
	camera.look_at(Vector3(0, 1, -8))
	var camera_rest := camera.rotation
	var rest := hazard_draw_count(corridor)
	var peak := rest
	for name in ["Floor", "Ceiling", "WallL", "WallR"]:
		check(corridor.get_node(name).mesh.subdivide_depth == 72, "turn mesh subdivisions " + name)
	for direction in [-1, 1]:
		var endpoint_pose: Transform3D
		var endpoint_pillars: Array[Transform3D] = []
		var previous := 0.0
		for progress in [0.0, 0.15, 0.3, 0.5, 0.7, 0.85, 1.0]:
			corridor.set_turn(progress, direction)
			corridor._process(0.0)
			if progress == 0.0:
				endpoint_pose = corridor.transform
				for i in 24: endpoint_pillars.append(corridor._pillars.get_instance_transform(i))
			elif progress == 1.0:
				check(corridor.transform == endpoint_pose, "turn endpoint transform equals start")
				for i in 24:
					check(corridor._pillars.get_instance_transform(i) == endpoint_pillars[i], "turn endpoint pillar equals start")
			TurnPreview.apply_camera_swing(camera, camera_rest, progress, direction)
			if progress >= 0.3 and progress <= 0.7:
				var angle := rad_to_deg((-camera.basis.z).angle_to(-corridor.basis.z))
				check(angle <= 15.0, "camera looks down turned corridor through hold")
				print("TURN CAMERA ALIGNMENT: direction=%+d p=%.1f angle=%.3f degrees" % [direction, progress, angle])
				check(is_equal_approx(absf(corridor.rotation_degrees.y), 55.0) and is_equal_approx(absf(corridor.bend), 0.010), "turn reaches sharp peak at 0.3 and holds through 0.7")
			var magnitude := absf(corridor.bend)
			check(magnitude >= previous - 0.000001 if progress <= 0.5 else magnitude <= previous + 0.000001, "turn bend monotone around peak")
			previous = magnitude
			var pose: Transform3D = corridor.transform
			corridor.set_turn(progress, direction)
			corridor._process(0.0)
			check(corridor.transform == pose, "turn idempotent")
			var opacity: float = corridor._corner_material.get_shader_parameter("opacity")
			var far: float = corridor._far_material.get_shader_parameter("opacity")
			check(is_equal_approx(opacity + far, 1.0), "corner and far crossfade complement")
			peak = maxi(peak, hazard_draw_count(corridor))
		check(is_zero_approx(corridor.rotation.y) and is_zero_approx(corridor.bend), "turn endpoint is straight")
	corridor.set_turn(0.5, 1)
	corridor._process(0.0)
	corridor.set_process(true)
	var pose: Transform3D = corridor.transform
	var offset: float = corridor._offset
	paused = true
	for i in 10: await process_frame
	check(corridor.transform == pose and corridor._offset == offset, "ten paused frames freeze turn and scroll")
	paused = false
	corridor.set_turn(0.0, 0)
	corridor._process(0.0)
	check(corridor.rotation == Vector3.ZERO and not corridor.get_node("CornerWall").visible, "explicit turn reset")
	check(rest <= 14 and peak <= 18, "corridor draw census budget")
	print("CORRIDOR DRAW CENSUS: rest=", rest, "; mid-turn=", peak, " (headless geometry census; host GPU measurement pending)")
	camera.free()
	corridor.free()
	var mock := preload("res://scenes/runner/ui/dev/mock_runner_game.gd").new()
	mock.autoplay = false
	root.add_child(mock)
	mock.start_run()
	mock.stage_banner.bind(mock)
	mock.turn_started.emit(1, 2.5)
	mock.stage_started.emit(2, &"Merge Conflict Hydra", 13.0)
	check(not mock.stage_banner.visible and is_equal_approx(mock.hud.time_label.get_parent().modulate.a, 0.55), "turn defers banner and dims HUD")
	mock.turn_finished.emit()
	check(mock.stage_banner.title.text == "S T A G E  2", "stage title letter spacing")
	check(mock.stage_banner.visible and mock.hud.time_label.get_parent().modulate.a == 1.0, "turn finish reveals banner and restores HUD")
	mock.boss_spawned.emit(&"merge_conflict_hydra", 100)
	check(not mock.stage_banner.visible, "boss suppresses banner")
	mock.stage_clear.bind(mock)
	mock.stage_cleared.emit(2, 550)
	mock.stage_clear._process(0.5)
	await frames()
	var panel_rect: Rect2 = mock.stage_clear.panel.get_global_rect()
	check(panel_rect.get_center().distance_to(root.get_visible_rect().get_center()) < 1.0, "stage card centered in viewport")
	check(panel_rect.position.x >= 0 and panel_rect.position.y >= 0 and panel_rect.end.x <= root.get_visible_rect().end.x and panel_rect.end.y <= root.get_visible_rect().end.y, "stage card fits viewport")
	check(mock.stage_clear.subtitle.text.ends_with(" \u2014 FIXED"), "stage clear design separator")
	check(mock.stage_clear.bonus_label.text == "+550", "stage bonus counts up")
	mock.pause()
	var age: float = mock.stage_clear.age
	mock.stage_clear._process(1.0)
	check(mock.stage_clear.age == age, "stage card pause freeze")
	mock.resume()
	mock.stage_clear._process(2.31)
	check(not mock.stage_clear.visible, "stage card closes after hold and exit")
	mock.free()
	print("TURN: ", "PASS" if before == failures else "FAIL")
	await frames()

func check_stage_seam() -> void:
	var before := failures
	var game := (load("res://scenes/runner/runner_game.tscn") as PackedScene).instantiate()
	game.autostart = false
	game.config = game.config.duplicate()
	game.leaderboard_path = "user://test_runner_stage_seam_%d.cfg" % OS.get_process_id()
	game.config.stage_base_distance = 260.0
	game.config.time_to_max_speed = 20.0
	game.config.boss_hp_scale = 0.4
	root.add_child(game)
	var corridor: Node = game.turn_rig.corridor
	var banner := game.get_node("HUD/StageBanner")
	var card := game.get_node("HUD/StageClear")
	var events := {"started": 0, "finished": 0, "one": false, "reset": false, "banner_open": 0, "banner_close": 0, "card_open": 0, "card_close": 0}
	game.turn_started.connect(func(_d: int, _s: float) -> void: events.started += 1)
	game.turn_finished.connect(func() -> void: events.finished += 1)
	corridor.turn_applied.connect(func(p: float, d: int) -> void:
		if p == 1.0: events.one = true
		if events.one and p == 0.0 and d == 0: events.reset = true)
	banner.opened.connect(func() -> void: events.banner_open += 1)
	banner.closed.connect(func() -> void: events.banner_close += 1)
	card.opened.connect(func() -> void: events.card_open += 1)
	card.closed.connect(func() -> void: events.card_close += 1)
	game.start_run(12345)
	game.set_autopilot(true)
	game.autopilot.set_mode(2)
	var old_scale := Engine.time_scale
	var old_ticks := Engine.physics_ticks_per_second
	var old_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = 4.0
	await _wait_for(func() -> bool: return game.stage_index >= 2 or game.state != &"running", 35.0, "real stage seam reaches stage two")
	Engine.time_scale = old_scale
	Engine.physics_ticks_per_second = old_ticks
	Engine.max_physics_steps_per_frame = old_steps
	check(game.stage_index >= 2, "shortened smoke config crosses stage seam")
	check(events.started > 0 and events.finished > 0 and events.one and events.reset, "backend forwards turn one then reset")
	check(events.banner_open > 0 and events.banner_close > 0, "real banner appears and closes")
	check(events.card_open > 0 and events.card_close > 0 and not card.visible, "real stage card appears and closes")
	check(game.turn_rig.rotation == Vector3.ZERO, "frontend hook prevents fallback rig yaw")
	var seam_board: String = game.leaderboard_path
	game.free()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(seam_board + suffix): DirAccess.remove_absolute(seam_board + suffix)
	print("STAGE SEAM: ", "PASS" if before == failures else "FAIL")
	await frames()

func check_multimesh_interpolation(node: Node) -> int:
	var count := 0
	if node is MultiMeshInstance3D:
		count = 1
		check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "cosmetic MultiMesh interpolation disabled: %s" % node.get_path())
	for child in node.get_children():
		count += check_multimesh_interpolation(child)
	return count

func check_interpolation_opt_out() -> void:
	var before := failures
	var count := 0
	var scenes: Array[String] = [
		"res://scenes/runner/environment/corridor.tscn",
		"res://scenes/runner/hazards/visuals/dev/hazard_gallery.tscn",
		"res://scenes/runner/boss/dev/boss_gallery.tscn",
	]
	# Discover every pickup, including tools that use the shared boss batch builder.
	var directory := DirAccess.open("res://scenes/runner/powerups/visuals")
	check(directory != null, "power-up visual directory exists")
	if directory != null:
		for file in directory.get_files():
			if file.ends_with("_visual.tscn"):
				scenes.append("res://scenes/runner/powerups/visuals/" + file)
	for path in scenes:
		var scene := load(path) as PackedScene
		check(scene != null, "interpolation fixture loads: " + path)
		if scene == null: continue
		var fixture := scene.instantiate()
		root.add_child(fixture)
		if fixture.has_method("on_spawned"): fixture.on_spawned()
		await frames()
		count += check_multimesh_interpolation(fixture)
		if fixture.has_method("capture_boss"):
			fixture.set_process(false)
			for index in [1, 2]:
				fixture.capture_boss(index)
				await frames()
				count += check_multimesh_interpolation(fixture.encounter)
		fixture.free()
		await frames()
	check(count > 0, "interpolation census is nonempty")
	print("INTERPOLATION OPT-OUT: ", "PASS" if failures == before else "FAIL", " (", count, " nodes)")

func check_turn_warning() -> void:
	var before := failures
	var mock := preload("res://scenes/runner/ui/dev/mock_runner_game.gd").new()
	mock.autoplay = false
	root.add_child(mock)
	mock.start_run()
	var audio := preload("res://scenes/runner/audio/runner_audio.tscn").instantiate()
	mock.add_child(audio)
	audio.bind(mock)
	var cues: Array[StringName] = []
	audio.sound_played.connect(func(kind: StringName, _stream: AudioStream) -> void: cues.append(kind))
	for direction in [-1, 1]:
		audio._clock += 4.0
		var warning_count_before: int = cues.count(&"turn_warning")
		mock.turn_incoming.emit(direction, 3.0)
		check(mock.hud.turn_panel.visible and mock.hud.turn_label.text.contains("LEFT" if direction < 0 else "RIGHT"), "directional turn banner")
		check(mock.hud.turn_label.get_theme_font_size("font_size") >= 34, "warning legibility")
		check(mock.hud.turn_fx.visible and mock.hud.turn_fx.direction == direction and mock.hud.turn_fx.multimesh.instance_count == 18, "pooled chevrons in three lanes")
		check(mock.hud.turn_fx.get_parent() is CorridorScript, "chevrons are children of mounted corridor")
		check(cues.count(&"turn_warning") == warning_count_before + 1, "warning signal plays audio exactly once")
		for tick in 3:
			mock.hud.warning_age = float(tick)
			mock.hud._update_turn_warning()
			check(mock.hud.turn_label.text.ends_with(str(3 - tick)), "three countdown ticks")
		mock.pause()
		var age: float = mock.hud.warning_age
		mock.hud._process(1.0)
		check(mock.hud.warning_age == age, "warning pause freeze")
		mock.resume()
		mock.turn_started.emit(direction, 2.5)
		check(not mock.hud.turn_fx.visible and mock.hud.turn_fx.direction == 0, "turn started clears chevrons before end wall takes over")
		mock.turn_finished.emit()
		check(not mock.hud.turn_panel.visible and not mock.hud.turn_fx.visible, "turn finish clears warning and chevrons")
		check(not audio._pending.has(&"turn_warning"), "turn finish clears pending warning audio")
	for seconds in [0.4, 1.2, 2.0, 4.5]:
		mock.turn_incoming.emit(1, seconds)
		for age in [0.0, 0.5, seconds, seconds + 0.5]:
			mock.hud.warning_age = age
			mock.hud._update_turn_warning()
			check(mock.hud.turn_label.text.ends_with(str(maxi(1, ceili(seconds - age)))), "countdown uses actual drain duration")
	mock.free()
	await frames()
	print("TURN WARNING: ", "PASS" if before == failures else "FAIL")

func check_boss_intro() -> void:
	var before := failures
	var copy := preload("res://scenes/runner/ui/boss_copy.gd")
	var game: Node = load("res://scenes/runner/runner_game.tscn").instantiate()
	game.autostart = false
	game.leaderboard_path = "user://test_runner_boss_intro_%d.cfg" % OS.get_process_id()
	root.add_child(game)
	game.start_run(721)
	game.set_process(false)
	game.set_physics_process(false)
	var overlay: Node = game.get_node("HUD/BossCinematic")
	var hud: Node = game.get_node("HUD/BossHud")
	var audio: Node = game.get_node("Audio/RunnerAudio")
	var arena: Node = game.boss_encounter
	for stage in [1, 2, 3]:
		arena.start(stage)
		var kind: StringName = game.get_boss_info().kind
		check(overlay.root.visible and not hud.visible, "cinematic replaces HP before spawn")
		check(overlay.epithet.text == copy.epithet(kind).to_upper(), "single epithet source " + kind)
		check(overlay.threat.text == copy.threat(kind), "single threat source " + kind)
		check(arena.visual._model != null and arena.visual.intro_calls == 1, "GLB cinematic receives one start")
		check(audio._boss_duck == -18.0, "cinematic duck survives spawn")
		arena.tick(2.0)
		game.stage_manager._publish()
		overlay._process(0)
		check(overlay.title_group.visible and overlay.title_group.scale.x > 1.7, "title slams during camera hold")
		arena.tick(0.75)
		game.stage_manager._publish()
		overlay._process(0)
		check(overlay.threat.visible_characters >= 22 and overlay.threat.visible_characters <= 23, "threat types at 40 characters per second")
		game.pause()
		var frozen: int = overlay.threat.visible_characters
		var duck: float = audio._boss_duck
		overlay._process(1)
		audio._process(1)
		check(overlay.threat.visible_characters == frozen and audio._boss_duck == duck, "pause freezes clock-driven UI and mix")
		game.resume()
		arena.tick(0.9)
		game.stage_manager._publish()
		overlay._process(0)
		check(overlay.hints.visible and overlay.threat.visible, "hint row and complete threat coexist for the wide shot")
		arena.tick(1.35)
		game.stage_manager._publish()
		check(not overlay.root.visible and hud.visible, "HP plate enters on cinematic end")
		check(audio._boss_duck == -4.0, "intro releases into fight mix")
		arena.abort()
	check(copy.threat(&"unknown") == "Review required.", "unknown boss has safe fallback copy")
	game.free()
	await frames()
	print("BOSS INTRO: ", "PASS" if before == failures else "FAIL")
