extends SceneTree
## Graphical proof: --always-on-top, --real for the mounted game, --output=<directory>.
## Real captures advance the live facade clock, then freeze the tree for a rendered readback.
const Mock = preload("res://scenes/runner/ui/dev/mock_run_intro_game.gd")
const FULL := [0.12, 0.65, 1.20, 2.15, 3.12, 3.93, 4.73, 5.50]
const ORBIT := [2.10, 2.35, 2.60, 2.85]
const SHORT := [0.30, 1.12, 1.70, 2.10]
var folder := ""
var failures := 0
var game: Node3D
var real_game := false
var frozen := false
var duration := 6.0
var facade_script: GDScript
var board := "user://capture_run_intro_%d.cfg" % OS.get_process_id()
var telemetry: Array[Dictionary] = []

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
		if arg == "--real": real_game = true
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		printerr("RUN INTRO CAPTURE: cannot create output directory")
		quit(1)
		return
	if real_game:
		facade_script = load("res://scenes/runner/runner_game.gd") as GDScript
		game = load("res://scenes/runner/runner_game.tscn").instantiate()
		game.autostart = false
		game.leaderboard_path = board
	else:
		game = Mock.new()
		game.scenery = true
	root.add_child(game)
	if not game.is_node_ready(): await game.ready
	var ui := _ui()
	if not game.is_inside_tree() or ui == null:
		printerr("RUN INTRO CAPTURE: fixture failed to mount")
		quit(1)
		return
	if real_game:
		game.paused_changed.connect(_ignore_focus_pause)
		_check(game.find_child("EntryBulkhead", true, false) != null, "real corridor mounts EntryBulkhead")
	await physics_frame
	await capture_sequence(&"full", FULL, 4)
	await capture_sequence(&"short", SHORT, 4)
	await capture_sequence(&"full", ORBIT, 4, "full-orbit")
	_begin(&"full")
	await _advance_to(1.2)
	_check(game.skip_run_intro(), "skip accepted after title")
	await _advance_to(duration - 0.2)
	await capture_frame("full-skip-tail")
	await _advance_to(duration - 0.05)
	await capture_frame("full-skip-fade")
	_check(_ui().countdown.modulate.a < 0.30, "skipped GO fades before hand-back")
	if real_game:
		_freeze(false)
		var deadline := Time.get_ticks_msec() + 2000
		while game.phase == &"intro" and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(game.phase == &"run", "skip hands the real scene back to run")
		_freeze(true)
	else:
		game.advance_intro(0.3)
	await capture_frame("after-intro")
	_freeze(false)
	game.free()
	if facade_script != null: facade_script.set(&"pending_intro_mode", &"full")
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"): audio.shutdown()
	# Stop queues playback disposal on the audio thread, which must finish before exit.
	await create_timer(0.3).timeout
	await process_frame
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(board + suffix): DirAccess.remove_absolute(board + suffix)
	var output := FileAccess.open(folder.path_join("telemetry.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"real_game": real_game, "failures": failures, "frames": telemetry}, "\t"))
	else:
		failures += 1
	print("RUN INTRO CAPTURE: %s (%s, real=%s)" % ["PASS" if failures == 0 else "FAIL", folder, real_game])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if condition: return
	failures += 1
	push_error("RUN INTRO CAPTURE: " + label)

func _ui() -> CanvasLayer:
	return game.get_node_or_null("HUD/RunIntro") if real_game else game.ui

func _begin(mode: StringName) -> void:
	duration = 2.2 if mode == &"short" else 6.0
	if real_game:
		_freeze(false)
		facade_script.set(&"pending_intro_mode", mode)
		game.start_run(4704)
		_check(game.run_intro_mode == mode and game.phase == &"intro", "real facade starts " + String(mode))
	else:
		game.begin_intro(mode)

func _clock() -> float:
	return float(game.run_intro_progress) * duration if real_game else float(game.elapsed)

func _advance_to(target: float) -> void:
	if not real_game:
		game.advance_intro(maxf(0, target - _clock()))
		_check(is_equal_approx(_clock(), target), "mock reached requested clock")
		return
	_freeze(false)
	var deadline := Time.get_ticks_msec() + 10000
	while game.phase == &"intro" and _clock() < target and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(game.phase == &"intro" and _clock() >= target, "real clock reached %.2fs" % target)
	# The facade is PROCESS_ALWAYS, so freeze its bookkeeping as well as the pausable world.
	# No pause signal is sent: these are frames of the playing cinematic, not the pause menu.
	_freeze(true)

func _freeze(value: bool) -> void:
	if not real_game: return
	frozen = value
	game.set_physics_process(not value)
	paused = value

func _ignore_focus_pause(value: bool) -> void:
	if value:
		game.resume()
		paused = frozen

func capture_sequence(mode: StringName, points: Array, columns: int, label: String = "") -> void:
	if label.is_empty(): label = String(mode)
	_begin(mode)
	var strip := Image.create(columns * 640, ceili(float(points.size()) / columns) * 360, false, Image.FORMAT_RGB8)
	for i in points.size():
		var target := float(points[i])
		await _advance_to(target)
		var frame := await capture_frame("%s-%02d-%.2fs" % [label, i, target])
		frame.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		frame.convert(Image.FORMAT_RGB8)
		strip.blit_rect(frame, Rect2i(0, 0, 640, 360), Vector2i(i % columns * 640, i / columns * 360))
	if strip.save_png(folder.path_join("%s-strip.png" % label)) != OK: failures += 1

func capture_frame(label: String) -> Image:
	var ui := _ui()
	if real_game:
		ui._process(0)
		game.get_node("HUD/PostFX")._process(0)
		var camera: Camera3D = game.camera_rig.camera
		var entry := game.find_child("EntryBulkhead", true, false) as Node3D
		var visual: Node = game.player.visual
		_check(visual != null, "real Hoppy visual is mounted")
		if label == "full-02-1.20s":
			_check(visual != null and visual.get("anim_state") == &"victory", "title beat plays Hoppy victory")
			_check(ui.title_group.visible, "title card is visible with victory")
		if ui.count_label.text == "GO!" and ui.countdown.visible:
			_check(not game.can_skip_run_intro() and not ui.skip_button.visible, "GO closes the skip window")
		if label == "after-intro":
			_check(not ui.root.visible, "intro overlay clears on hand-back")
		telemetry.append({"frame": label, "mode": String(game.run_intro_mode),
			"progress": game.run_intro_progress, "phase": String(game.phase), "beat": ui.count_label.text,
			"title_visible": ui.title_group.visible, "count_visible": ui.countdown.visible,
			"count_alpha": ui.countdown.modulate.a, "skip_visible": ui.skip_button.visible,
			"entry_bulkhead": entry != null, "camera_position": str(camera.global_position),
			"camera_rotation": str(camera.global_rotation), "player_position": str(game.player.global_position),
			"visual": String(visual.get("anim_state")) if visual != null else ""})
	else:
		game.update_visuals()
	# Flush the skeleton and draw the frozen scene before reading the viewport.
	await physics_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var path := folder.path_join(label + ".png")
	if frame.save_png(path) != OK: failures += 1
	print("RUN INTRO FRAME: ", path)
	return frame
