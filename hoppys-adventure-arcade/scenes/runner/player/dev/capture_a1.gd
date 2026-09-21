extends SceneTree
## Coordinator-only graphical fixture. Never renders in headless mode.
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
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
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Palette.NAVY_BG
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Palette.CREAM
	environment.environment.ambient_light_energy = 0.45
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.4
	stage.add_child(light)
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
	stage.add_child(floor_mesh)
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
		["gameplay", Vector3(0, 4, 8), Vector3(0, 1, -8), &"run", false],
		["shield", Vector3(-2.4, 1.7, -3.3), Vector3(0, 0.9, 0), &"run", true],
		["roll", Vector3(1.2, 1.0, -1.9), Vector3(0, 0.45, 0), &"roll", false],
		["trail", Vector3(1.4, 1.8, 2.8), Vector3(0, 1.0, 0.4), &"run", false],
		["rear", Vector3(1.3, 1.55, 2.3), Vector3(0, 0.95, 0), &"idle", false],
		["roll-gameplay", Vector3(0, 4, 8), Vector3(0, 1, -8), &"roll", false],
		["roll-shield", Vector3(1.6, 1.25, -2.7), Vector3(0, 0.45, 0), &"roll", true]]
	for view: Array in views:
		camera.position = view[1]
		camera.look_at(view[2])
		if not pose_for_view(hoppy, view[3], 0.24):
			printerr("ASSET A1 CAPTURE: incorrect animation for " + str(view[0]))
			await finish(stage, 1)
			return
		hoppy.show_shield(view[4])
		hoppy.show_aura(&"lgtm", view[4])
		hoppy.set_run_speed(1)
		hoppy._process(0.1)
		if view[0] == "trail":
			assert(hoppy._trail.visible and hoppy._speed == 1.0, "Trail capture must run at speed")
		for frame in 4:
			await process_frame
		assert(hoppy.animation_player.current_animation == view[3], "Capture animation mismatch")
		await RenderingServer.frame_post_draw
		var calls := RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var error := root.get_texture().get_image().save_png(directory.path_join("a1-%s.png" % view[0]))
		if error != OK:
			printerr("ASSET A1 CAPTURE: failed to save " + str(view[0]))
			await finish(stage, 1)
			return
		print("A1 CAPTURE %s: %d measured viewport draws (includes floor)" % [view[0], calls])
	print("ASSET A1 CAPTURE: PASS")
	await finish(stage, 0)

static func pose_for_view(hoppy: Node3D, state: StringName, time: float) -> bool:
	var player: AnimationPlayer = hoppy.animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_default_blend_time = 0.0
	hoppy.set_anim_state(state)
	player.play(state, 0.0)
	player.advance(0.0)
	player.seek(time, true)
	return player.current_animation == state

func finish(stage: Node3D, code: int) -> void:
	root.get_node("AudioService").shutdown()
	if is_instance_valid(stage):
		stage.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	quit(code)
