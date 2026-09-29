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
	game.autostart = false
	game.leaderboard_path = "user://starship_capture_unused.cfg"
	root.add_child(game)
	while not Prewarm.is_complete(): await process_frame
	game.start_run(12345)
	game.set_autopilot(true)
	game.autopilot.set_mode(2)
	await create_timer(14.0).timeout
	paused = true
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../docs/previews/starship/starship-gameplay.png")
	var error := root.get_texture().get_image().save_png(output)
	print("STARSHIP GAMEPLAY: save=%d state=%s stage=%d" % [error,game.state,game.stage_index])
	paused = false
	await Cleanup.release(self,[game])
	quit(0 if error == OK else 1)
