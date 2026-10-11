extends SceneTree
## Graphical proof of the intro. Use --always-on-top; --output=<directory> overrides user://.
## Captures wait for the requested clock state and a rendered frame, never a frame-count delay.
const Mock = preload("res://scenes/runner/ui/dev/mock_run_intro_game.gd")
const FULL := [0.12, 0.65, 1.20, 2.15, 3.12, 3.93, 4.73, 5.50]
const ORBIT := [2.10, 2.35, 2.60, 2.85]
const SHORT := [0.30, 1.12, 1.70, 2.19]
var folder := ""
var failures := 0
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not root.is_node_ready(): await root.ready
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("RUN INTRO CAPTURE: graphical display required")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	AudioServer.set_bus_mute(0, true)
	folder = ProjectSettings.globalize_path("user://run-intro-captures")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		printerr("RUN INTRO CAPTURE: cannot create output directory")
		quit(1)
		return
	game = Mock.new()
	game.scenery = true
	root.add_child(game)
	if not game.is_node_ready(): await game.ready
	if not game.is_inside_tree() or game.ui == null:
		printerr("RUN INTRO CAPTURE: fixture failed to mount")
		quit(1)
		return
	await physics_frame
	await capture_sequence(&"full", FULL, 4)
	await capture_sequence(&"short", SHORT, 4)
	await capture_sequence(&"full", ORBIT, 4, "full-orbit")
	game.begin_intro(&"full")
	game.advance_intro(1.2)
	game.skip_run_intro()
	game.advance_intro(0.2)
	await capture_frame("full-skip-tail")
	game.advance_intro(0.3)
	await capture_frame("after-intro")
	game.free()
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"): audio.shutdown()
	# Let queued audio playback disposal finish before the SceneTree exits.
	await create_timer(0.3).timeout
	await process_frame
	print("RUN INTRO CAPTURE: %s (%s)" % ["PASS" if failures == 0 else "FAIL", folder])
	quit(0 if failures == 0 else 1)

func capture_sequence(mode: StringName, points: Array, columns: int, label: String = "") -> void:
	if label.is_empty(): label = String(mode)
	game.begin_intro(mode)
	var strip := Image.create(columns * 640, ceili(float(points.size()) / columns) * 360, false, Image.FORMAT_RGB8)
	for i in points.size():
		var target := float(points[i])
		game.advance_intro(maxf(0, target - float(game.elapsed)))
		if not is_equal_approx(float(game.elapsed), target):
			printerr("RUN INTRO CAPTURE: requested clock was not reached")
			failures += 1
			return
		var frame := await capture_frame("%s-%02d-%.2fs" % [label, i, target])
		frame.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		frame.convert(Image.FORMAT_RGB8)
		strip.blit_rect(frame, Rect2i(0, 0, 640, 360), Vector2i(i % columns * 640, i / columns * 360))
	var error := strip.save_png(folder.path_join("%s-strip.png" % label))
	if error != OK: failures += 1

func capture_frame(label: String) -> Image:
	game.update_visuals()
	# Skeleton poses and bone attachments settle at the next physics boundary.
	await physics_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var path := folder.path_join(label + ".png")
	if frame.save_png(path) != OK: failures += 1
	print("RUN INTRO FRAME: ", path)
	return frame
