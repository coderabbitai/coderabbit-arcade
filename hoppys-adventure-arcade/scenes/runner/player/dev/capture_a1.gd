extends SceneTree
## Coordinator-only graphical fixture. Never renders in headless mode.
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Guard = preload("res://scenes/runner/player/hifi/palette_guard.gd")
const MaskShader = preload("res://scenes/runner/player/hifi/palette_mask.gdshader")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	root.get_node("AudioService").music.stop()
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A1 CAPTURE: graphical renderer required")
		await finish(null, 1)
		return
	capture()

func capture() -> void:
	var started := Time.get_ticks_msec()
	var corridor_ms := 0
	var guard_ms := 0
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(stage)
	var studio := Node3D.new()
	stage.add_child(studio)
	configure_lighting(studio)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 60)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Palette.NAVY_2
	floor_mat.roughness = 0.35
	floor_mat.metallic = 0.7
	floor_mesh.material_override = floor_mat
	floor_mesh.position.z = -20
	studio.add_child(floor_mesh)
	var hoppy := Hoppy.instantiate()
	stage.add_child(hoppy)
	hoppy.set_process(false)
	hoppy.animation_player.set_process(false)
	hoppy.animation_player.playback_default_blend_time = 0.0
	var camera := Camera3D.new()
	camera.fov = 60
	stage.add_child(camera)
	camera.current = true
	var directory := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(directory)
	var views := [
		["close", Vector3(1.35, 1.4, -2.1), Vector3(0, 0.95, 0), &"idle", false],
		["run", Vector3(1.35, 1.4, -2.1), Vector3(0, 0.95, 0), &"run", false],
		["gameplay", Vector3(0, 4, 8), Vector3(0, 1, -8), &"run", false],
		["shield", Vector3(-2.4, 1.7, -3.3), Vector3(0, 0.9, 0), &"run", true],
		["roll", Vector3(1.2, 1.0, -1.9), Vector3(0, 0.45, 0), &"roll", false],
		["trail", Vector3(1.4, 1.8, 2.8), Vector3(0, 1.0, 0.4), &"run", false],
		["rear", Vector3(1.3, 1.55, 2.3), Vector3(0, 0.95, 0), &"idle", false],
		["roll-gameplay", Vector3(0, 4, 8), Vector3(0, 1, -8), &"roll", false],
		["roll-shield", Vector3(1.6, 1.25, -2.7), Vector3(0, 0.45, 0), &"roll", true],
		["corridor", Vector3(0, 4, 8), Vector3(0, 1, -8), &"run", false],
		["corridor-close", Vector3(1.35, 1.4, -2.1), Vector3(0, 0.95, 0), &"idle", false]]
	var palette_ok := true
	for view: Array in views:
		if view[0] == "corridor":
			studio.free()
			var corridor_started := Time.get_ticks_msec()
			stage.add_child(Corridor.instantiate())
			corridor_ms = Time.get_ticks_msec() - corridor_started
			print("A1 CAPTURE TIMING corridor=%d ms" % corridor_ms)
		camera.position = view[1]
		camera.look_at(view[2])
		if not pose_for_view(hoppy, view[3], 0.0 if view[3] == &"roll" else 0.24):
			printerr("ASSET A1 CAPTURE: incorrect animation for " + str(view[0]))
			await finish(stage, 1)
			return
		hoppy.show_shield(view[4])
		hoppy.show_aura(&"lgtm", view[4])
		hoppy.set_run_speed(1)
		hoppy._process(0.1)
		if view[0] == "trail":
			assert(hoppy._trail.visible and hoppy._speed == 1.0, "Trail capture must run at speed")
		for frame in 2:
			await process_frame
		assert(hoppy.animation_player.current_animation == view[3], "Capture animation mismatch")
		await RenderingServer.frame_post_draw
		var calls := RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var error := root.get_texture().get_image().save_png(directory.path_join("a1-%s.png" % view[0]))
		if error != OK:
			printerr("ASSET A1 CAPTURE: failed to save " + str(view[0]))
			await finish(stage, 1)
			return
		if view[0] == "close":
			var studio_image := Image.load_from_file(directory.path_join("a1-close.png"))
			var lens := measure_goggle_band(studio_image)
			print("A1 GOGGLE BAND: ", lens)
			if not lens["pass"]:
				printerr("ASSET A1 CAPTURE: opaque-looking goggle band")
				palette_ok = false
		if str(view[0]).begins_with("corridor"):
			var saved := Image.load_from_file(directory.path_join("a1-%s.png" % view[0]))
			var mask := await capture_mask(hoppy, camera, stage)
			var guard_started := Time.get_ticks_msec()
			var result := Guard.measure(saved, mask)
			var measured_ms := Time.get_ticks_msec() - guard_started
			guard_ms += measured_ms
			print("A1 CAPTURE TIMING guard=%d ms view=%s" % [measured_ms, view[0]])
			print("A1 HUE %s: %s" % [view[0], result])
			if not result["pass"]:
				printerr("ASSET A1 CAPTURE: corridor palette guard failed")
				palette_ok = false
		print("A1 CAPTURE %s: %d measured viewport draws (includes floor)" % [view[0], calls])
	print("A1 CAPTURE TIMING corridor=%d guard=%d total=%d" % [corridor_ms, guard_ms, Time.get_ticks_msec() - started])
	print("ASSET A1 CAPTURE: " + ("PASS" if palette_ok else "FAIL"))
	await finish(stage, 0 if palette_ok else 1)

static func configure_lighting(stage: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Palette.NAVY_BG
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Palette.CREAM
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	# Match the corridor's rear-side player key, lighting gameplay/rear views.
	var key := OmniLight3D.new()
	key.name = "CorridorKey"
	key.position = Vector3(0, 1.8, 1)
	key.light_color = Palette.MINT
	key.light_energy = 0.65
	key.omni_range = 3.2
	key.shadow_enabled = false
	stage.add_child(key)

static func pose_for_view(hoppy: Node3D, state: StringName, time: float) -> bool:
	var player: AnimationPlayer = hoppy.animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_default_blend_time = 0.0
	hoppy.set_anim_state(state)
	# Runtime uses an explicit cross-fade; setting the default alone cannot cancel it.
	player.play(state, 0.0)
	player.advance(0.0)
	player.seek(time, true)
	player.advance(0.0)
	return player.assigned_animation == state

func finish(stage: Node3D, code: int) -> void:
	root.get_node("AudioService").shutdown()
	if is_instance_valid(stage):
		stage.free()
	await process_frame
	quit(code)

func capture_mask(hoppy: Node3D, camera: Camera3D, stage: Node3D) -> Image:
	var original: Array = []
	var layers: Array = []
	for mesh: MeshInstance3D in hoppy._meshes:
		layers.append(mesh.layers)
		mesh.layers = 1 << 19
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			original.append(material)
			var mask := ShaderMaterial.new()
			mask.shader = MaskShader
			mask.set_shader_parameter("albedo_map", material.get_shader_parameter("albedo_map"))
			mask.set_shader_parameter("albedo_color", material.get_shader_parameter("albedo_color"))
			mesh.set_surface_override_material(surface, mask)
	var world := stage.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
	var environment := world.environment
	var blank := Environment.new()
	blank.background_mode = Environment.BG_COLOR
	blank.background_color = Color.BLACK
	world.environment = blank
	var cull := camera.cull_mask
	camera.cull_mask = 1 << 19
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	camera.cull_mask = cull
	world.environment = environment
	var index := 0
	for mesh_index in hoppy._meshes.size():
		var mesh: MeshInstance3D = hoppy._meshes[mesh_index]
		mesh.layers = layers[mesh_index]
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, original[index])
			index += 1
	original.clear()
	layers.clear()
	environment = null
	blank = null
	return image

static func measure_goggle_band(image: Image) -> Dictionary:
	# Fixed studio camera, 1280x720; inclusive reviewer coordinates.
	var mean := Color(0, 0, 0, 0)
	for y in range(230, 249):
		for x in range(624, 701):
			mean += image.get_pixel(x, y)
	mean /= 77.0 * 19.0
	# Authored veil a9b48d has saturation 0.217; opaque r11 62a48c has 0.402.
	return {"pass": mean.s < 0.30, "mean_color": mean.to_html(false), "saturation": mean.s}
