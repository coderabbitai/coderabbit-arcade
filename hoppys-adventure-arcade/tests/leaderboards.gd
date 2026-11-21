extends SceneTree
## Every game keeps a local top ten (app/leaderboards.gd): a route maps to its own board file, a
## recorded run ranks against that board only, the runner keeps its own file, and the shared pause
## menu's Leaderboard button opens a game's board over the paused game. Run headless with
## --script res://tests/leaderboards.gd.
const Leaderboards = preload("res://app/leaderboards.gd")
const Board = preload("res://scenes/runner/systems/runner_leaderboard.gd")
const PauseMenu = preload("res://app/pause_menu.gd")
var failures := 0
var scratch := "user://test_leaderboards_%d/" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func run() -> void:
	await process_frame
	# A suite runs with --script, so with no override the boards go to this process's scratch
	# folder, never the player's. Rows left there by an earlier run with the same id are cleared
	# the first time this run uses the folder; another run's folder is left alone.
	var own := "%s%d/" % [Leaderboards.SCRATCH_PREFIX, OS.get_process_id()]
	# Another run's folder, named so two copies of this suite sharing user:// never share it.
	var neighbour := "%s%d_neighbour/" % [Leaderboards.SCRATCH_PREFIX, OS.get_process_id()]
	for folder in [own, neighbour]:
		DirAccess.make_dir_recursive_absolute(folder)
		FileAccess.open(folder + "leftover.cfg", FileAccess.WRITE).store_string("[board]\n")
	var auto := Leaderboards.dir()
	check(auto == own and not FileAccess.file_exists(own + "leftover.cfg")
			and Leaderboards.path_for("runner_game") == auto + "runner_game.cfg"
			and FileAccess.file_exists(neighbour + "leftover.cfg"),
		"A test run empties and uses its own scratch folder, the runner included, and no neighbour")
	DirAccess.remove_absolute(neighbour + "leftover.cfg")
	DirAccess.remove_absolute(neighbour)
	check(int(Leaderboards.record("bay_area_blitz", 5, 1.0).rank) == 1
			and FileAccess.file_exists(auto + "bay_area_blitz.cfg"),
		"A run recorded under test lands in the scratch folder")
	Leaderboards.clear_scratch()
	check(not DirAccess.dir_exists_absolute(auto), "clear_scratch removes the folder and its boards")
	Leaderboards.redirect_tests = false
	check(Leaderboards.path_for("runner_game") == Board.DEFAULT_PATH,
		"The runner keeps its own board file")
	check(Leaderboards.path_for("bay_area_blitz") == Leaderboards.DIR + "bay_area_blitz.cfg",
		"A game's board lives under user://leaderboards/ by route")
	Leaderboards.redirect_tests = true
	Leaderboards.override_dir = scratch
	check(Leaderboards.path_for("runner_game") == scratch + "runner_game.cfg",
		"An override directory redirects every board, the runner's too")

	var first := Leaderboards.record("bay_area_blitz", 1200, 61.5)
	check(int(first.rank) == 1 and int(first.error) == OK, "The first run on an empty board ranks #1")
	var second := Leaderboards.record("bay_area_blitz", 800, 40.0)
	check(int(second.rank) == 2, "A lower score ranks below it")
	var other := Leaderboards.record("orbital_ops", 50, 5.0)
	check(int(other.rank) == 1, "Another game's run ranks on its own board")
	var rows := Leaderboards.entries("bay_area_blitz")
	check(rows.size() == 2 and int(rows[0].score) == 1200 and rows[0].name.begins_with("Hoppy "),
		"Rows are sorted best first and named after the mascot and the time of day")
	check(FileAccess.file_exists(scratch + "bay_area_blitz.cfg") and FileAccess.file_exists(scratch + "orbital_ops.cfg"),
		"Each board is its own file")
	for i in 12:
		Leaderboards.record("code_city_brawl", 100 + i, 10.0)
	check(Leaderboards.entries("code_city_brawl").size() == Board.MAX_ENTRIES,
		"A board keeps its top ten")
	check(int(Leaderboards.record("code_city_brawl", 1, 1.0).rank) == 0, "A run below the ten does not place")
	check(Leaderboards.rank_line(first) == "LEADERBOARD  #1" and Leaderboards.rank_line({"rank": 0, "error": OK}) == ""
			and Leaderboards.rank_line({"rank": 1, "error": ERR_FILE_CANT_WRITE}) == "",
		"The results line names a placing and stays empty for a miss or a failed save")

	# The shared pause menu opens the game's board over the menu and closes it with the menu.
	var host := Node.new()
	root.add_child(host)
	var menu: Node = PauseMenu.create(host, "orbital_ops", func() -> void: pass, func() -> void: pass, func() -> void: pass)
	await process_frame
	check(menu.leaderboard_button != null and menu.leaderboard_button.text == "Leaderboard"
			and menu.buttons[menu.buttons.size() - 2] == menu.leaderboard_button,
		"The menu has a Leaderboard button just before Main Menu")
	check(menu.leaderboard_path == scratch + "orbital_ops.cfg", "The button points at the game's board")
	menu.open()
	menu.leaderboard_button.pressed.emit()
	await process_frame
	var board: Control = menu.leaderboard
	check(board != null and board.title.begins_with("ORBITAL OPS") and board.board.get_child_count() == 10
			and board.close_btn.has_focus() and not board.reset_btn.disabled,
		"Leaderboard opens the game's titled top ten with Close focused and Reset offered")
	check(menu.resume_button.disabled and menu.resume_button.focus_mode == Control.FOCUS_NONE,
		"The menu's own buttons are unreachable while the board is up")
	board.close()
	await process_frame
	check(menu.leaderboard == null and not menu.resume_button.disabled and menu.leaderboard_button.has_focus(),
		"Closing the board re-enables the menu and refocuses Leaderboard")
	menu.leaderboard_button.pressed.emit()
	await process_frame
	menu.close()
	await process_frame
	check(menu.leaderboard == null and not menu.is_open(), "Closing the menu takes an open board with it")
	host.queue_free()

	for file in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch + file)
	DirAccess.remove_absolute(scratch)
	Leaderboards.override_dir = ""
	Leaderboards.clear_scratch()
	print("LEADERBOARDS: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	var audio := root.get_node_or_null("AudioService")
	if audio: await audio.settle()
	quit(1 if failures else 0)
