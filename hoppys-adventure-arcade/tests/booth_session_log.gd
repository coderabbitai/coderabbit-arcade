extends SceneTree
## Booth session log (app/booth_log.gd): each visit to a game writes a start and an end line,
## re-entering the same game counts as a retry, menus never start a session, idle and quit say how
## a session ended, and nothing is written unless --booth or --session-log asks for it. The flags
## and the window-close quit are checked in child processes, so _ready()'s argument handling and
## quit_game() are covered. Child launches get a throwaway user-data root, so a standalone run never
## reads or writes a real booth log. Run headless with --script res://tests/booth_session_log.gd.
const BoothLog := preload("res://app/booth_log.gd")
const LOG_DIR := "user://test_booth_sessions"
const CHILD_DIR := "user://test_booth_child_sessions"
const QUIT_DIR := "user://test_booth_quit_sessions"
const RELAUNCH_DIR := "user://test_booth_relaunch_sessions"
const BLOCKER := "user://test_booth_blocker"
const CHILD_HOME := "user://test_booth_home"
const ISOLATED := ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "APPDATA", "LOCALAPPDATA",
	"USERPROFILE"]
## Every field the log may contain. Anything else would be new data about players: review it first.
const FIELDS := ["event", "launch", "time", "version", "session", "game", "duration_s", "ended_by",
	"retries"]
var failures := 0
var router: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout

func settle_route() -> void:
	for i in 300:
		if not router.busy:
			break
		await process_frame
	await process_frame

func visit(route: String) -> void:
	router.go(route)
	await settle_route()

## Run Godot on this project and return its exit code and output.
func godot(args: Array[String]) -> Dictionary:
	var full: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://")]
	full.append_array(args)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), full, output, true)
	return {"code": code, "log": "\n".join(output)}

## Launch the game for two simulated seconds with a throwaway user-data root (the variables Godot
## reads on each OS), so the default booth log is never a real one.
func launch(user_args: Array[String]) -> Dictionary:
	var home := ProjectSettings.globalize_path(CHILD_HOME)
	var saved := {}
	for variable in ISOLATED:
		saved[variable] = OS.get_environment(variable) if OS.has_environment(variable) else null
	var values := [home, home.path_join(".local/share"), home.path_join(".config"),
		home.path_join("AppData/Roaming"), home.path_join("AppData/Local"), home]
	for i in ISOLATED.size():
		OS.set_environment(ISOLATED[i], values[i])
	var args: Array[String] = ["--fixed-fps", "60", "--quit-after", "120", "--"]
	args.append_array(user_args)
	var result := godot(args)
	for variable in saved:
		if saved[variable] == null:
			OS.unset_environment(variable)
		else:
			OS.set_environment(variable, saved[variable])
	return result

## The log path a child printed at startup, or "".
func logged_path(output: String) -> String:
	for line in output.split("\n"):
		if line.begins_with("AppRouter: session log at "):
			return line.trim_prefix("AppRouter: session log at ").strip_edges()
	return ""

## The log's records in order; a line that isn't a JSON object is a failed check.
func records(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		check(parsed is Dictionary, "Log line is a JSON object: " + line)
		if parsed is Dictionary:
			result.append(parsed)
	return result

func events(entries: Array[Dictionary], kind: String) -> Array[Dictionary]:
	return entries.filter(func(record: Dictionary) -> bool: return record.event == kind)

## True when a file whose name starts with `prefix` exists anywhere under `directory`.
func find_file(directory: String, prefix: String) -> bool:
	var dir := DirAccess.open(directory)
	if dir == null:
		return false
	dir.include_hidden = true
	for file_name in dir.get_files():
		if file_name.begins_with(prefix):
			return true
	for child in dir.get_directories():
		if find_file(directory.path_join(child), prefix):
			return true
	return false

func remove_tree(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		dir.remove(file_name)
	for child in dir.get_directories():
		remove_tree(directory.path_join(child))
	DirAccess.remove_absolute(directory)

func clean() -> void:
	if FileAccess.file_exists(BLOCKER):
		DirAccess.remove_absolute(BLOCKER)
	for folder in [LOG_DIR, CHILD_DIR, QUIT_DIR, RELAUNCH_DIR, CHILD_HOME]:
		remove_tree(ProjectSettings.globalize_path(folder))

func run() -> void:
	router = root.get_node("AppRouter")
	clean()
	await wait(0.3)
	check(router.session_log == null, "No session log without --booth or --session-log")
	check(router.session_log_path(PackedStringArray(), false) == "",
		"No flags means no session log")
	check(router.session_log_path(PackedStringArray(["--booth"]), true) == "user://booth",
		"Booth mode logs to the booth folder")
	check(router.session_log_path(PackedStringArray(["--session-log=user://playtest"]), false)
		== "user://playtest", "--session-log picks a folder, with or without --booth")
	check(router.session_log_path(PackedStringArray(["--session-log="]), false) == "",
		"An empty --session-log is ignored")

	var plain := launch(["--route=bay_area_blitz"])
	check(plain.code == 0, "A plain launch exits cleanly")
	check(logged_path(plain.log) == ""
		and not find_file(ProjectSettings.globalize_path(CHILD_HOME), "sessions-"),
		"A launch without --booth writes no session log")
	var kiosk := launch(["--booth", "--route=heroes_vs_villains"])
	var booth_path := logged_path(kiosk.log)
	check(kiosk.code == 0, "A booth launch exits cleanly")
	check(booth_path.begins_with(ProjectSettings.globalize_path(CHILD_HOME))
		and booth_path.get_base_dir().ends_with("/booth")
		and booth_path.get_file().begins_with("sessions-") and booth_path.ends_with(".jsonl"),
		"--booth logs this run to booth/sessions-<time>-<pid>.jsonl in the user data (%s)" % booth_path)
	var booth_log := records(booth_path)
	check(booth_log.size() == 2 and booth_log[0].event == "launch"
		and booth_log[0].version == ProjectSettings.get_setting("application/config/version")
		and booth_log[1].event == "start" and booth_log[1].game == "heroes_vs_villains",
		"--booth logs the launch and the launch route's session start")
	# --quit-after stops the child without a quit request, as a crash would: the start stays open.
	check(events(booth_log, "end").is_empty(), "A run that stops without quitting leaves no end")
	var child := launch(["--session-log=" + ProjectSettings.globalize_path(CHILD_DIR),
		"--route=orbital_ops"])
	var child_path := logged_path(child.log)
	var child_log := records(child_path)
	check(child.code == 0 and child_path.get_base_dir() == ProjectSettings.globalize_path(CHILD_DIR)
		and child_log.size() == 2 and child_log[1].game == "orbital_ops",
		"--session-log logs to its folder without --booth")
	var closed := godot(["--script", "res://tests/support/session_log_quit.gd", "--",
		ProjectSettings.globalize_path(QUIT_DIR)])
	var quit_path := logged_path(closed.log)
	var quit_ends := events(records(quit_path), "end")
	check(closed.code == 0 and quit_ends.size() == 1 and quit_ends[0].ended_by == "quit"
		and quit_ends[0].game == "bay_area_blitz",
		"A window close (quit_game(true)) ends the session as quit")

	var first := BoothLog.new(RELAUNCH_DIR)
	first.route_changed("runner_game", "menu")
	# Separate processes differ by process id; within this one, by the millisecond in the name.
	OS.delay_msec(5)
	var second := BoothLog.new(RELAUNCH_DIR)
	second.route_changed("runner_game", "menu")
	var first_log := records(first.path)
	var second_log := records(second.path)
	check(first.path != second.path and first_log.size() == 2 and second_log.size() == 2
		and first_log[0].launch != second_log[0].launch,
		"Each run writes its own file, under its own launch id")

	# A file where the log's folder should be: logging switches itself off with a warning.
	var blocker := FileAccess.open(BLOCKER, FileAccess.WRITE)
	blocker.store_line("not a folder")
	blocker.close()
	var broken := BoothLog.new(BLOCKER)
	broken.route_changed("heroes_vs_villains", "menu")
	broken.end("quit")
	check(broken.failed and broken.game == "",
		"An unwritable log turns itself off and the session bookkeeping carries on")

	router.start_session_log(LOG_DIR)
	await visit("bay_area_blitz")
	await visit("bay_area_blitz")
	await visit("platformer")
	await visit("heroes_vs_villains")
	router.set_booth(true)
	router.idle_limit = 0.5
	await wait(1.0)
	await settle_route()
	router.set_booth(false)
	router.idle_limit = router.IDLE_SECONDS
	await visit("code_city_brawl")
	router.set_booth(true)
	router.quit_game()
	check(router.session_log.game == "code_city_brawl",
		"The menu's Quit, ignored in booth mode, leaves the session open")
	router.set_booth(false)
	# The child above covers quit_game(true); here the session just needs an end.
	router.session_log.end("quit")

	var entries := records(router.session_log.path)
	var starts := events(entries, "start")
	var ends := events(entries, "end")
	check(entries.size() > 0 and entries[0].event == "launch", "The log opens with a launch line")
	check(starts.map(func(record: Dictionary) -> String: return record.game)
		== ["bay_area_blitz", "heroes_vs_villains", "code_city_brawl"],
		"Each game visit starts one session; menus and the hub start none")
	check(ends.size() == 3, "Every session ends")
	if ends.size() == 3 and starts.size() == 3:
		check(ends[0].ended_by == "menu" and int(ends[0].retries) == 1,
			"Re-entering a game is a retry; leaving for a menu ends the session")
		check(ends[1].ended_by == "idle", "Booth mode's idle return ends a session as idle")
		check(ends[2].ended_by == "quit", "Quitting ends a session as quit")
		var numbered := true
		for i in 3:
			numbered = numbered and int(starts[i].session) == i + 1 and int(ends[i].session) == i + 1 \
				and starts[i].launch == entries[0].launch and ends[i].game == starts[i].game \
				and float(ends[i].duration_s) > 0.0
		check(numbered, "Starts and ends pair by launch and session, with a positive duration")
	var extra := []
	for path in [router.session_log.path, child_path, quit_path, booth_path]:
		for record in records(path):
			for key in record:
				if key not in FIELDS:
					extra.append(key)
	check(extra.is_empty(), "The logs hold only the documented fields (found %s)" % [extra])

	clean()
	await root.get_node("AudioService").settle()
	print("Booth session log failures: ", failures)
	quit(1 if failures else 0)
