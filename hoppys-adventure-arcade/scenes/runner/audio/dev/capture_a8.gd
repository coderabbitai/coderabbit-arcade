extends SceneTree
## Host-only diagnostic captures. Audio has no in-game visible geometry.
const Synth = preload("res://scenes/runner/audio/sfx_synth.gd")
const AudioScene = preload("res://scenes/runner/audio/runner_audio.tscn")
var camera: Camera3D
var screen: Sprite3D
var label: Label

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A8 CAPTURE: graphical host required")
		quit(1)
		return
	call_deferred("capture")

func waveform(kind: StringName) -> ImageTexture:
	var image := Image.create(1024, 256, false, Image.FORMAT_RGB8)
	image.fill(Color("101b2a"))
	var stream := Synth.sound(kind)
	var data := stream.data
	var stride := 4 if stream.stereo else 2
	var count := data.size() / stride
	for x in 1024:
		var peak := 0.0
		for i in range(x * count / 1024, (x + 1) * count / 1024):
			peak = maxf(peak, absf(data.decode_s16(i * stride) / 32767.0))
		for y in range(128 - int(peak * 150), 129 + int(peak * 150)):
			image.set_pixel(x, clampi(y, 0, 255), Color("9fffcf"))
	return ImageTexture.create_from_image(image)

func capture() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	var audio := AudioScene.instantiate()
	world.add_child(audio)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("080e18")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b8d6df")
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	world.add_child(environment)
	for x in [-4.0, 4.0, 0.0]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 5, 35) if x != 0 else Vector3(8, 0.15, 35)
		mesh.mesh = box
		mesh.position = Vector3(x, 2.5 if x != 0 else -0.15, -12)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("162638")
		material.metallic = 0.7
		material.roughness = 0.4
		mesh.material_override = material
		world.add_child(mesh)
	screen = Sprite3D.new()
	screen.position = Vector3(0, 2.4, -8)
	screen.pixel_size = 0.006
	world.add_child(screen)
	camera = Camera3D.new()
	camera.fov = 62
	world.add_child(camera)
	label = Label.new()
	label.position = Vector2(48, 40)
	label.add_theme_font_size_override("font_size", 26)
	root.add_child(label)
	var output := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(output)
	for view in ["gameplay", "closeup", "intro"]:
		var kind: StringName = &"boss_intro" if view == "intro" else &"boss_hit"
		screen.texture = waveform(kind)
		camera.position = Vector3(0, 3.6, 6) if view == "gameplay" else Vector3(0, 2.4, -2)
		camera.look_at(screen.position)
		label.text = "A8 / %s / %s\n32 recipes | 10 voices | layered PCM\nWaveform diagnostic, audio has no gameplay geometry" % [view.to_upper(), kind]
		audio.footsteps.stream = Synth.sound(kind)
		audio.footsteps.play()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var error := root.get_texture().get_image().save_png(output.path_join("a8-%s.png" % view))
		if error != OK:
			printerr("capture save failed: ", error)
			quit(1)
			return
		print("ASSET A8 CAPTURE: ", view, " draw_calls=", draws)
	print("ASSET A8 CAPTURE: PASS")
	quit()
