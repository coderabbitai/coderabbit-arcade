extends SceneTree
## Run on the coordinator's graphical host only.
const Scene = preload("res://scenes/runner/pursuer/pursuer_visual.tscn")
const Forge = preload("res://scenes/runner/pursuer/hifi/forge.gd")

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A6 CAPTURE: FAIL (graphical display required)")
		quit(1)
		return
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("08111c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("435464")
	environment.ambient_light_energy = 0.65
	env.environment = environment
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 1.8
	world.add_child(light)
	for side in [-1, 0, 1]:
		var backdrop := MeshInstance3D.new()
		backdrop.mesh = Forge.bevel_box(Vector3(0.25, 6, 70) if side != 0 else Vector3(8, 0.15, 70), 0.05)
		backdrop.position = Vector3(side * 4, 3 if side != 0 else -0.15, -25)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("101d2d")
		material.metallic = 0.7
		material.roughness = 0.4
		backdrop.material_override = material
		world.add_child(backdrop)
	var visual := Scene.instantiate()
	world.add_child(visual)
	visual.set_process(false)
	var camera := Camera3D.new()
	camera.fov = 60
	world.add_child(camera)
	camera.make_current()
	var output := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(output)
	for view in ["gameplay", "closeup", "three-quarter", "catch"]:
		visual.set_threat(1)
		visual.position.z = 4.5 if view == "gameplay" else 0.0
		camera.position = Vector3(0, 4, 8) if view == "gameplay" else Vector3(0, 2.8, 7)
		if view == "three-quarter": camera.position = Vector3(4, 3, 6)
		camera.look_at(Vector3(0, 1, -8) if view == "gameplay" else Vector3(0, 1.1, 0))
		if view == "catch": visual.play_catch()
		for frame in 12:
			visual._process(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var error := root.get_texture().get_image().save_png(output.path_join("a6-%s.png" % view))
		if error != OK:
			printerr("ASSET A6 CAPTURE: FAIL saving ", view)
			quit(1)
			return
		print("A6 CAPTURE %s: %d measured frame draw calls (includes backdrop)" % [view, calls])
	print("ASSET A6 CAPTURE: PASS")
	quit(0)
