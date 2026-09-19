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

func hazard_draw_count(visual: Node3D) -> int:
	# Node-based estimate: outlined Label3D = 2, MultiMesh = 1.
	# Actual renderer totals (including overlays/culling) are checked by capture_previews.
	var count := 0
	for node in visual.find_children("*", "VisualInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
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
	check(gallery.visuals.size() == 12, "gallery all eight kinds and every variant")
	var camera: Camera3D = gallery.get_node("Camera")
	check(camera.position == Vector3(0, 4, 8) and camera.fov == 60.0, "gallery contract camera")
	for key in [KEY_H, KEY_R, KEY_C, KEY_R, KEY_T, KEY_1, KEY_2, KEY_3, KEY_R, KEY_RIGHT, KEY_LEFT]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		gallery._unhandled_key_input(event)
		await frames()
	gallery.free()
	await frames()

func hazard_labels(visual: Node3D) -> Array:
	var result: Array = []
	for label: Label3D in visual.find_children("*", "Label3D", true, false):
		result.append([label.text, label.modulate, label.visible])
	return result
