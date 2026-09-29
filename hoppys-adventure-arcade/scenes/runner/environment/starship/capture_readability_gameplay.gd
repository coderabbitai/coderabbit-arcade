extends SceneTree
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("STARSHIP GAMEPLAY: graphical renderer required")
		quit(1)
		return
	root.size = Vector2i(1440,900)
	var game := (load("res://scenes/runner/runner_game.tscn") as PackedScene).instantiate()
	var fast := "--max-speed" in OS.get_cmdline_user_args()
	if fast:
		# Diagnostic fixture only. The shipping RunConfig remains untouched.
		game.config = game.config.duplicate()
		game.config.base_speed = game.config.max_speed
	game.autostart = false
	game.leaderboard_path = "user://starship_capture_unused.cfg"
	root.add_child(game)
	while not Prewarm.is_complete(): await process_frame
	game.start_run(12345)
	game.set_autopilot(true)
	game.autopilot.set_mode(2)
	var last := 0.0
	var error := OK
	var times := [8.0,14.0] if fast else [8.0,14.0,22.0,32.0]
	for seconds in times:
		await create_timer(seconds-last).timeout
		last = seconds
		paused = true
		await RenderingServer.frame_post_draw
		var output := ProjectSettings.globalize_path("res://../docs/previews/readability/%s-%02d.png" % ["speed24" if fast else "gameplay",int(seconds)])
		error = root.get_texture().get_image().save_png(output)
		print("READABILITY GAMEPLAY: time=%d save=%d state=%s stage=%d speed=%.1f" % [seconds,error,game.state,game.stage_index,game.speed])
		paused = false
	await Cleanup.release(self,[game])
	quit(0 if error == OK else 1)
