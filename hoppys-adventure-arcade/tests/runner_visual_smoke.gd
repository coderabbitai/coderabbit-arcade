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
