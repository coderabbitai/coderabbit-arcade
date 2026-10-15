extends SceneTree
## Booth session log (app/booth_log.gd): each visit to a game writes a start and an end line,
## re-entering the same game counts as a retry, menus never start a session, idle and quit say how
## a session ended, and nothing is written unless --booth or --session-log asks for it. The flags
## are checked by launching the game as a child process, so _ready()'s argument handling is covered.
## Run headless with --script res://tests/booth_session_log.gd.
const BoothLog := preload("res://app/booth_log.gd")
const LOG := "user://test_booth_sessions.jsonl"
const CHILD_LOG := "user://test_booth_child_sessions.jsonl"
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

## Launch the game headless with user args for two simulated seconds and return its exit code.
func launch(user_args: Array[String]) -> int:
	var args: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--quit-after", "120", "--"]
	args.append_array(user_args)
	var output: Array = []
	return OS.execute(OS.get_executable_path(), args, output, true)

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

func run() -> void:
	router = root.get_node("AppRouter")
	await wait(0.3)
	check(router.session_log == null, "No session log without --booth or --session-log")
	check(router.session_log_path(PackedStringArray(), false) == "",
		"No flags means no session log")
	check(router.session_log_path(PackedStringArray(["--booth"]), true) == router.SESSION_LOG_DEFAULT,
		"Booth mode logs to the default file")
	check(router.session_log_path(PackedStringArray(["--session-log=user://playtest.jsonl"]), false)
		== "user://playtest.jsonl", "--session-log picks a file, with or without --booth")
	check(router.session_log_path(PackedStringArray(["--session-log="]), false) == "",
		"An empty --session-log is ignored")

	check(launch(["--route=bay_area_blitz"]) == 0, "A plain launch exits cleanly")
	check(not FileAccess.file_exists(router.SESSION_LOG_DEFAULT),
		"A launch without --booth writes no session log")
	check(launch(["--booth", "--route=heroes_vs_villains"]) == 0, "A booth launch exits cleanly")
	var booth_log := records(router.SESSION_LOG_DEFAULT)
	check(booth_log.size() == 2 and booth_log[0].event == "launch"
		and booth_log[0].version == ProjectSettings.get_setting("application/config/version")
		and booth_log[1].event == "start" and booth_log[1].game == "heroes_vs_villains",
		"--booth logs the launch and the launch route's session start")
	# --quit-after stops the child without a quit request, as a crash would: the start stays open.
	check(events(booth_log, "end").is_empty(), "A run that stops without quitting leaves no end")
	check(launch(["--session-log=" + ProjectSettings.globalize_path(CHILD_LOG),
		"--route=orbital_ops"]) == 0, "A --session-log launch exits cleanly")
	var child_log := records(CHILD_LOG)
	check(child_log.size() == 2 and child_log[1].game == "orbital_ops",
		"--session-log logs without --booth")

	# A file where the log's folder should be: logging switches itself off with a warning.
	var blocker := FileAccess.open("user://test_booth_blocker", FileAccess.WRITE)
	blocker.store_line("not a folder")
	blocker.close()
	var broken := BoothLog.new("user://test_booth_blocker/sessions.jsonl")
	broken.route_changed("heroes_vs_villains", "menu")
	broken.end("quit")
	check(broken.failed and broken.game == "",
		"An unwritable log turns itself off and the session bookkeeping carries on")

	router.start_session_log(LOG)
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
	# quit_game(true) would end this suite; it calls the same end("quit").
	router.session_log.end("quit")

	var entries := records(LOG)
	var starts := events(entries, "start")
	var ends := events(entries, "end")
	check(entries.size() > 0 and entries[0].event == "launch", "The log opens with a launch line")
	check(starts.map(func(record: Dictionary) -> String: return record.game)
		== ["bay_area_blitz", "heroes_vs_villains", "code_city_brawl"],
		"Each game visit starts one session; menus and the hub start none")
	check(ends.size() == 3, "Every session ends")
	if ends.size() == 3:
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
	for record in entries:
		for key in record:
			if key not in FIELDS:
				extra.append(key)
	check(extra.is_empty(), "The log holds only the documented fields (found %s)" % [extra])

	await root.get_node("AudioService").settle()
	print("Booth session log failures: ", failures)
	quit(1 if failures else 0)
