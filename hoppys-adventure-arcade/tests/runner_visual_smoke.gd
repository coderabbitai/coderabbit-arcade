extends SceneTree
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

func bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func run() -> void:
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
		player.seek(0.0, true)
		var standing := bounds(hoppy.get_node("Root"))
		check(absf(standing.position.y) < 0.001 and absf(standing.end.y - 1.8) < 0.001, "standing feet 0 and height 1.8")
		for state in [&"idle", &"run", &"jump", &"fall", &"roll", &"hurt", &"dead"]:
			hoppy.set_anim_state(state)
			await frames()
			check(player.has_animation(state), "animation exists: " + state)
			check(hoppy.anim_state == state, "state selected: " + state)
			if state == &"roll":
				hoppy.show_aura(&"lgtm", true)
				player.seek(0.25, true)
				var all_meshes := bounds(hoppy)
				check(hoppy.get_node("Root/Aura").is_visible_in_tree(), "roll aura visible")
				check(all_meshes.end.y <= 0.95 and all_meshes.position.y >= -0.02, "all-mesh mid-roll bounds including aura: %s" % all_meshes)
				for sample in 61:
					player.seek(float(sample) / 120.0, true)
					var rolling := bounds(hoppy.get_node("Root"))
					check(rolling.position.y >= -0.001 and rolling.end.y <= 0.901, "roll bounds at sample %d: %s" % [sample, rolling])
				hoppy.show_aura(&"lgtm", false)
		for speed in [0.0, 0.5, 1.2]:
			hoppy.set_anim_state(&"run")
			hoppy.set_run_speed(speed)
			await frames()
			check(is_equal_approx(player.speed_scale, lerpf(0.85, 1.9, speed)), "run speed scaling")
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
		# Advance standalone hurt deterministically, checking each distinct flash pulse.
		hoppy.set_anim_state(&"idle")
		hoppy.set_anim_state(&"hurt")
		player.stop()
		player.play(&"hurt", 0.0)
		player.advance(0.0)
		player.pause()
		var method_mode := player.callback_mode_method
		player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
		for delta in [0.002, 0.12, 0.12]:
			hoppy._process(0.07)
			check(hoppy.get_node("Root/Model/Body").material_overlay == null, "hurt pulse starts cleared")
			player.advance(delta)
			check(hoppy.get_node("Root/Model/Body").material_overlay != null, "standalone hurt pulse at %s" % player.current_animation_position)
		player.callback_mode_method = method_mode
		hoppy.set_anim_state(&"idle")
		hoppy.on_hit()
		check(hoppy.get_node("Root/Model/Body").material_overlay != null, "hit flash")
		await create_timer(0.1).timeout
		check(hoppy.get_node("Root/Model/Body").material_overlay == null, "flash clears")
		for locomotion in [&"idle", &"run"]:
			hoppy.set_anim_state(locomotion)
			hoppy.set_anim_state(&"hurt")
			await create_timer(0.55).timeout
			check(hoppy.anim_state == locomotion, "hurt returns to " + locomotion)
		hoppy.set_anim_state(&"hurt")
		await frames()
		hoppy.set_anim_state(&"dead")
		await create_timer(0.55).timeout
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
	await check_hazards()
	await check_powerups_and_pursuer()
	await check_runner_ui()
	await check_runner_audio()
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	failures += _logger.errors()
	print("RUNNER VISUAL SMOKE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	OS.remove_logger(_logger)
	quit(failures)

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
	check(is_equal_approx(marker.position.y, 0.006), context + " ground marker")
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

func pursuer_bounds(visual: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node: GeometryInstance3D in visual.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
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
		check(is_equal_approx(art.get_node("Pivot").rotation.y, 0.8), "%s spin 1.6 rad/s" % kind)
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
	check(pursuer.find_children("*", "Label3D", true, false).size() == 6, "pursuer six headlines")
	check(pursuer.find_children("*", "CollisionObject3D", true, false).is_empty(), "pursuer cosmetic only")
	for threat in [0.0, 0.5, 1.0]:
		pursuer.set_threat(threat)
		check(is_equal_approx(pursuer.get_node("Wall").scale.y, lerpf(0.35, 1.0, threat)), "pursuer threat height")
		check(is_equal_approx(pursuer.get_node("RedLight").light_energy, threat * 2.5), "pursuer threat light")
		check(is_equal_approx(pursuer.get_node("Wall/Glitch").amount_ratio, threat), "pursuer threat particles")
	var merged := AABB()
	for sample in 121:
		pursuer._process(1.0 / 60.0)
		var box := pursuer_bounds(pursuer)
		merged = box if sample == 0 else merged.merge(box)
		check(box.size.x <= 6.0 and box.size.y <= 2.6 and box.position.y >= -0.001, "pursuer threat 1 visible AABB %s" % box)
	check(merged.size.x <= 6.0 and merged.size.y <= 2.6, "pursuer merged motion envelope")
	print("PURSUER THREAT 1 MERGED VISIBLE AABB: ", merged)
	var clock: float = pursuer._t
	pursuer.set_process(true)
	paused = true
	await frames()
	check(pursuer._t == clock, "pursuer pause freezes motion")
	paused = false
	pursuer.set_process(false)
	var initial_scale: Vector3 = pursuer.get_node("Wall").scale
	pursuer.play_catch()
	pursuer._process(0.7)
	pursuer.play_catch()
	check(is_equal_approx(pursuer._reaction_time, 0.7), "catch idempotent")
	pursuer._process(0.7)
	check(pursuer.get_node("Wall").scale.is_equal_approx(initial_scale * 2.6), "catch 1.4s scale")
	check(is_equal_approx(pursuer.get_node("RedLight").light_energy, 6.0), "catch light")
	for label: Label3D in pursuer.find_children("*", "Label3D", true, false):
		check(label.text == "CAUGHT", "caught headline")
	# Reproduce the backend zero-threat update immediately before retreat.
	pursuer.set_threat(1.0)
	var retreat_pose: Transform3D = pursuer.get_node("Wall").transform
	pursuer.set_threat(0.0)
	pursuer.play_retreat()
	check(pursuer.get_node("Wall").transform.is_equal_approx(retreat_pose), "retreat restores last non-zero threat pose")
	pursuer._process(0.0)
	check(pursuer.get_node("Wall").transform.is_equal_approx(retreat_pose), "retreat starts without height pop")
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
	check(pursuer.visible and pursuer.get_node("Wall").scale.is_equal_approx(Vector3.ONE), "pursuer resumes cleanly")
	pursuer.free()
	await frames()
	print("PURSUER VISUAL: threat, catch, retreat, reuse and pause checked")

func check_runner_ui() -> void:
	root.size = Vector2i(1280, 720)
	var fixture := load("res://scenes/runner/ui/dev/hud_preview.tscn") as PackedScene
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
		saw_blocked = saw_blocked or "BLOCKED" in hud.toast_queue or hud.toast.text == "BLOCKED"
		saw_auto_fix = saw_auto_fix or "AUTO-FIX ×3" in hud.toast_queue or hud.toast.text == "AUTO-FIX ×3"
		saw_bonus = saw_bonus or "+25 BONUS" in hud.toast_queue or hud.toast.text == "+25 BONUS"
		hud._process(0.1)
	check(saw_shield and not hud.chips.has(&"approve_shield"), "demo shield chip appears then clears on blocked hit")
	check(saw_blocked and saw_auto_fix and saw_bonus, "demo BLOCKED, AUTO-FIX and bonus reach HUD toasts")
	check(cleared == [true, true, true] and not seen_chunks.is_empty() and not false in seen_chunks, "demo emits valid hazards and chunks")
	check(bonuses.size() == 4 and bonuses.all(func(value: Array) -> bool: return value == [25, &"pickup"]), "every demo pickup awards 25")
	for action in [&"jump", &"land", &"roll", &"roll_end", &"lane_left", &"lane_right"]:
		check(action in seen_actions, "demo action emitted: " + action)
	await create_timer(0.2).timeout
	check(not hud.get_ready.visible and hud.hp_row.get_child_count() == 2, "running HUD approvals")
	check(hud.hp_row.get_child(0).filled and not hud.hp_row.get_child(1).filled, "hit updates approval pips")
	check(hud.pursuit_warning.visible and hud.pursuit_remaining < float(mock.config.recovery_seconds), "demo pursuit")
	check(hud.score_label.text == "%08d" % mock.score, "score count-up reaches facade score")
	check(is_zero_approx(mock.camera_rig.last_shake), "HUD leaves backend-owned damage camera shake untouched")
	mock.pursuit_started.emit(7.5)
	mock.pursuit_progress.emit(3.25, 7.5)
	check(hud.pursuit_label.text == "UNREVIEWED BACKLOG · 3.2", "pursuit formats signal value")
	check(is_equal_approx(hud.pursuit_ring.fraction, 3.25 / 7.5), "ring uses supplied total")
	mock.collect(&"nitro", 8)
	hud._process(1)
	await frames()
	check(hud.chips[&"nitro"].bar.size.is_equal_approx(Vector2(90, 6)), "power-up bar remains 90x6")
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
	check(not hud.widgets.visible and not hud.pursuit_warning.visible, "caught hides gameplay")
	check(is_equal_approx(hud.vignette_material.get_shader_parameter("strength"), 1), "caught vignette")
	await frames()
	check(over.panel.size.x <= 680 and over.panel.size.y <= 620, "result panel fits 1280x720")
	check(over.panel.get_global_rect().end.y <= 720, "result panel inside viewport")
	check(over.name_field.focus_next == over.name_field.get_path_to(over.save_button), "name to save focus chain")
	for viewport_size in [Vector2i(1600, 900), Vector2i(1440, 900), Vector2i(1000, 720)]:
		root.size = viewport_size
		await frames()
		# canvas_items/expand uses logical coordinates at the requested window size.
		var canvas_size := root.get_visible_rect().size
		check(root.size == viewport_size, "requested window size applied")
		check(absf(hud.speed_bar.get_global_rect().end.x - (canvas_size.x - 28)) < 0.1, "HUD right anchor at %s" % viewport_size)
		check(is_equal_approx(hud.hp_row.global_position.x, 28), "HUD left anchor at %s" % viewport_size)
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
	print("RUNNER UI MOCK: HUD, pursuit, pause, results, focus and save PASS")
	var scene := load("res://scenes/runner/runner_game.tscn") as PackedScene
	var game := scene.instantiate()
	game.autostart = false
	game.leaderboard_path = "/tmp/f4-visual-smoke-board-%d.cfg" % OS.get_process_id()
	root.add_child(game)
	game.start_run(4704)
	game.set_autopilot(true)
	await create_timer(3.0).timeout
	var real_hud: CanvasLayer = game.get_node("HUD/RunnerHud")
	check(real_hud.game == game and not real_hud.get_ready.visible, "real facade binds HUD")
	check(game.elapsed > 2.0 and game.score > 0, "real facade autopilot runs for three seconds")
	check(real_hud.hp_row.get_child_count() == game.config.max_hp, "real facade HP")
	game.pause()
	check(game.get_node("Overlays/PauseMenu").visible, "real pause signal")
	game.resume()
	game.free()
	await frames()
	print("RUNNER UI REAL FACADE: autostart=false, start_run, autopilot 3s PASS")

func check_runner_audio() -> void:
	const Synth = preload("res://scenes/runner/audio/sfx_synth.gd")
	const RunnerAudio = preload("res://scenes/runner/audio/runner_audio.tscn")
	const Mock = preload("res://scenes/runner/ui/dev/mock_runner_game.gd")
	var mock := Mock.new()
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
	for kind: StringName in Synth.RECIPES:
		var stream := Synth.sound(kind)
		check(stream == Synth.sound(kind), "cached PCM: " + kind)
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050, "PCM format: " + kind)
		var data := stream.data
		var maximum := 0
		for i in range(0, data.size(), 2):
			maximum = maxi(maximum, absi(data.decode_s16(i)))
		check(maximum > 0 and maximum <= int(0.8 * 32767), "non-silent bounded PCM: " + kind)
		if kind in [&"pursuit_drone", &"heartbeat"]:
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
	check(not audio.heartbeat.playing, "heartbeat strict threshold")
	for i in 20:
		mock.pursuit_progress.emit(6.0 - i * 0.1, 18.0)
	check(counts.get(&"heartbeat", 0) == 2, "new pursuit resets heartbeat latch once")
	mock.damage_taken.emit(&"bug_swarm", 1)
	await create_timer(0.10).timeout
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
	await create_timer(0.4).timeout
	check(not audio.drone.playing and is_equal_approx(service.music.volume_db, -12.0), "drone fades out and music duck recovers")
	mock.pursuit_started.emit(18.0)
	mock.pursuit_progress.emit(1.0, 18.0)
	mock.caught.emit()
	check(not audio.heartbeat.playing, "caught stops heartbeat")
	check(service.get_child_count() == 2, "AudioService retains exactly two child players")
	print("RUNNER AUDIO: 19 recipes/triggers; demo heartbeat starts=1; peak voices=", peak[0], "; AudioService players=", service.get_child_count())
	mock.free()
	await frames()
	check(is_equal_approx(service.music.pitch_scale, 1.0), "audio teardown resets pitch")
