extends SceneTree
## Host-only: nine boss views plus an effects plate. No gameplay dependency.
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const CLOSE_CAMERA := Vector3(3.1, 4.4, -9.6)
var previous_png := PackedByteArray()
var previous_view := ""
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A5 CAPTURE: requires a graphical host")
		call_deferred("finish_capture", 1)
		return
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Art.Materials.environment()
	environment.environment = settings
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -25, 0)
	key.light_color = Palette.MATRIX
	key.light_energy = 0.35
	world.add_child(key)
	var near_light := OmniLight3D.new()
	near_light.position = Vector3(0, 3, 1)
	near_light.light_color = Palette.CREAM
	near_light.light_energy = 1.6
	near_light.omni_range = 9.0
	near_light.shadow_enabled = false
	world.add_child(near_light)
	Art.box(world, Vector3(0, -0.2, -15), Vector3(8, 0.35, 55), Palette.NAVY_2)
	for side in [-1, 1]:
		Art.box(world, Vector3(side * 4.2, 3, -18), Vector3(0.3, 6, 50), Palette.NAVY_BG)
	for lane in [-1, 0, 1]:
		Art.box(world, Vector3(lane * 2, 0, -18), Vector3(0.025, 0.015, 45), Palette.SLATE)
	camera = Camera3D.new()
	camera.fov = 60
	world.add_child(camera)
	camera.current = true
	var folder := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(folder)
	for kind in ["flaky_test_swarm", "merge_conflict_hydra", "legacy_monolith"]:
		var mount := Node3D.new()
		mount.position = Vector3(0, 2.6, -14)
		world.add_child(mount)
		var visual: Node3D = load("res://scenes/runner/boss/visuals/%s_visual.tscn" % kind).instantiate()
		mount.add_child(visual)
		visual.hover_z = -14.0
		visual.kind = StringName(kind)
		visual.max_hp = 100
		visual.show_name_plate = false
		visual.on_spawned()
		visual.set_process(false)
		for view in ["gameplay", "close", "phase2"]:
			visual.on_spawned()
			if view == "phase2":
				visual.set_phase(2)
				visual.set_health(40, 100)
			visual._process(1.4)
			camera.position = Vector3(0, 4, 8) if view == "gameplay" else CLOSE_CAMERA
			camera.look_at(Vector3(0, 1, -8) if view == "gameplay" else Vector3(0, 2.9, -14))
			if not await save_view(folder, kind + "-" + view): return
		mount.free()
	var fx: Node3D = load("res://scenes/runner/boss/boss_fx.tscn").instantiate()
	world.add_child(fx)
	fx.telegraphs[0].start(0, &"orb", 1.0)
	fx.telegraphs[0]._process(0.5)
	fx.numbers[0].start(Vector3(0, 2.6, -6), 15, Palette.ORANGE, 0)
	fx.numbers[0]._process(0.2)
	fx.tracers[0].fire(Vector3(2, 1, 0), Vector3(0, 3, -14), &"lint_rule", 12)
	fx.tracers[0]._process(0.07)
	for node in fx.telegraphs + fx.numbers + fx.tracers: node.set_process(false)
	camera.position = Vector3(0, 4, 8)
	camera.look_at(Vector3(0, 1, -8))
	if not await save_view(folder, "effects"): return
	world.free()
	print("ASSET A5 CAPTURE: PASS")
	await finish_capture(0)

func save_view(folder: String, view: String) -> bool:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var draws := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var png := root.get_texture().get_image().save_png_to_buffer()
	if not distinct_view(png, previous_png):
		printerr("ASSET A5 CAPTURE: FAIL identical views " + previous_view + " / " + view)
		await finish_capture(1)
		return false
	previous_png = png
	previous_view = view
	var result := root.get_texture().get_image().save_png(folder.path_join("a5-" + view + ".png"))
	if result != OK:
		printerr("ASSET A5 CAPTURE: FAIL saving " + view)
		await finish_capture(1)
		return false
	print("ASSET A5 CAPTURE DRAW CALLS: %s = %d (whole fixture)" % [view, draws])
	return true

static func distinct_view(current: PackedByteArray, previous: PackedByteArray) -> bool:
	return not current.is_empty() and current != previous

func finish_capture(code: int) -> void:
	if is_instance_valid(world): world.free()
	Art.Forge.clear_cache()
	# Stop the autoload MP3 playback before the audio thread exits.
	root.get_node("AudioService").shutdown()
	await create_timer(0.25).timeout
	quit(code)
