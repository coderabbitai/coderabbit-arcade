extends SceneTree
## Child process for tests/booth_session_log.gd, skipped as a suite in tools/tests/suites.toml. It
## opens a game with a session log, then quits through AppRouter.quit_game(true), as a window close
## does, so the parent can check the log's "quit" end without quitting itself.
## Usage: --script res://tests/support/session_log_quit.gd -- <log folder>

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var router := root.get_node("AppRouter")
	if args.is_empty():
		push_error("session_log_quit: pass the log folder after --")
		quit(2)
		return
	router.start_session_log(args[0])
	router.go("bay_area_blitz")
	for i in 300:
		await process_frame
		if not router.busy and current_scene != null \
				and current_scene.scene_file_path == router.ROUTES["bay_area_blitz"]:
			break
	router.quit_game(true)
