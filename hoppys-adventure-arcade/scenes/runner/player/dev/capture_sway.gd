extends SceneTree
## Graphical fixture for the cape and ear physics (hifi/sway_rig.gd): Hoppy runs, dashes two lanes
## right, jumps and lands while frames are saved as contact strips (rear and front cameras).
## Godot --path hoppys-adventure-arcade --always-on-top --script res://scenes/runner/player/dev/capture_sway.gd -- --output=<folder>
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const TICK := 1.0 / 60.0
const CELL := Vector2i(320, 360)
## Label, frames to simulate, frames between saved cells.
const BEATS := [["run", 48, 8], ["dash", 36, 4], ["jump", 60, 6]]

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.get_node("AudioService").music.stop()
	if DisplayServer.get_name() == "headless":
		printerr("SWAY CAPTURE: graphical renderer required")
		quit(1)
		return
	var output := "user://sway"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = CELL
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.2, 0.27)
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 150, 0)
	stage.add_child(sun)
	var mover := Node3D.new()
	mover.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage.add_child(mover)
	var hoppy := Hoppy.instantiate()
	mover.add_child(hoppy)
	hoppy.set_process(false)
	var player: AnimationPlayer = hoppy.animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 40
	stage.add_child(camera)
	camera.current = true
	for view: Array in [["rear", Vector3(1.2, 1.9, 4.2)], ["front", Vector3(-1.0, 1.5, -4.2)]]:
		mover.position = Vector3.ZERO
		hoppy.set_anim_state(&"run")
		hoppy.set_run_speed(0.8)
		hoppy._sway.settle()
		for beat: Array in BEATS:
			var cells: Array[Image] = []
			for frame in int(beat[1]):
				var t := float(frame + 1) * TICK
				if beat[0] == "dash":
					mover.position.x = 2.0 * (1.0 - pow(1.0 - minf(t / 0.18, 1.0), 2.0))
				elif beat[0] == "jump":
					var air := minf(t / 0.7, 1.0)
					mover.position.y = 1.3 * 4.0 * air * (1.0 - air)
					hoppy.set_anim_state(&"jump" if air < 0.5 else (&"fall" if air < 1.0 else &"run"))
					if frame == 42:
						hoppy.play_move(&"land")
				player.advance(TICK)
				hoppy._process(TICK)
				camera.position = mover.position * Vector3(1, 0.35, 1) + view[1]
				camera.look_at(mover.position * Vector3(1, 0.35, 1) + Vector3(0, 0.95, 0))
				await RenderingServer.frame_post_draw
				if frame % int(beat[2]) == int(beat[2]) - 1:
					cells.append(root.get_texture().get_image())
			var size := cells[0].get_size()
			var strip := Image.create(size.x * cells.size(), size.y, false, cells[0].get_format())
			for index in cells.size():
				strip.blit_rect(cells[index], Rect2i(Vector2i.ZERO, size), Vector2i(size.x * index, 0))
			var path := output.path_join("sway-%s-%s.png" % [view[0], beat[0]])
			if strip.save_png(path) != OK:
				printerr("SWAY CAPTURE: failed to save " + path)
			print("SWAY CAPTURE %s %s: %d cells, cape swing %.2f rad, ear swing %.2f rad" % [view[0], beat[0], cells.size(), hoppy._sway.swing(0), hoppy._sway.swing(2)])
	root.get_node("AudioService").shutdown()
	stage.free()
	await process_frame
	quit(0)
