extends RefCounted
## Local booth analytics: JSON Lines, one line per event, in a folder that holds one file per run of
## the game (sessions-<local date and time>-<process id>.jsonl). A watchdog relaunch or a second
## copy started by mistake never writes to another run's file. Nothing leaves the machine and
## nothing identifies a player. The only fields are the game, local times, the session length and
## how it ended:
##   {"event":"launch","launch":"2026-11-30T09:58:12.345","time":"2026-11-30T09:58:12",
##    "version":"0.1.0"}
##   {"event":"start","launch":"2026-11-30T09:58:12.345","session":1,"game":"heroes_vs_villains",
##    "time":"2026-11-30T10:02:03"}
##   {"event":"end","launch":"2026-11-30T09:58:12.345","session":1,"game":"heroes_vs_villains",
##    "time":"2026-11-30T10:04:26","duration_s":143.2,"ended_by":"idle","retries":0}
## A session is one visit to a game route. Re-entering the same game (the runner's or a platformer
## level's Retry) counts as a retry within it. `ended_by` is "menu" (the player left through the
## game's own menu), "idle" (booth mode's idle return), "game_over" (booth mode sent a player who had
## used their retries back to the attract route) or "quit". A start with no end means the game
## stopped without quitting: a crash, a power cut or a forced kill.
## tools/booth/sessions_report.py summarizes a folder of these files.

## Routes that are games. The hub and mode menus end a session but never start one.
const GAMES: Array[String] = ["heroes_vs_villains", "code_city_brawl", "bay_area_blitz",
	"orbital_ops", "enchanted_repo", "runner_game"]
## This run's file.
var path := ""
## When this run of the game started, to the millisecond. With `session` it identifies a session
## when logs from several runs are read together.
var launch := ""
## The game being played, or "" between sessions.
var game := ""
var session := 0
var retries := 0
var started_msec := 0
## Set after the first failed write: the game keeps running, unlogged, rather than retrying.
var failed := false

## Start this run's file in `folder` (absolute or user://), creating the folder if needed.
func _init(folder: String) -> void:
	var now := Time.get_unix_time_from_system()
	var local := int(now) + int(Time.get_time_zone_from_system().bias) * 60
	var stamp := Time.get_datetime_string_from_unix_time(local)
	var millis := int(fmod(now, 1.0) * 1000.0)
	launch = "%s.%03d" % [stamp, millis]
	path = folder.path_join("sessions-%s-%03d-%d.jsonl" % [stamp.replace(":", "-"), millis,
		OS.get_process_id()])
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
	_write({"event": "launch", "time": launch.get_slice(".", 0),
		"version": str(ProjectSettings.get_setting("application/config/version", ""))})

## AppRouter calls this after each successful route change. `reason` is how the session in
## progress, if any, ends.
func route_changed(route: String, reason: String) -> void:
	if game != "" and route == game:
		retries += 1
		return
	end(reason)
	if route in GAMES:
		game = route
		session += 1
		retries = 0
		started_msec = Time.get_ticks_msec()
		_write({"event": "start", "session": session, "game": game,
			"time": Time.get_datetime_string_from_system()})

## Close the session in progress, if any. Durations use the monotonic clock, so a wall-clock change
## mid-session can't skew them.
func end(reason: String) -> void:
	if game == "":
		return
	var seconds := (Time.get_ticks_msec() - started_msec) / 1000.0
	_write({"event": "end", "session": session, "game": game,
		"time": Time.get_datetime_string_from_system(), "duration_s": snappedf(seconds, 0.1),
		"ended_by": reason, "retries": retries})
	game = ""

## Open, append and close per event, so a crash loses at most the line being written.
func _write(fields: Dictionary) -> void:
	if failed:
		return
	var record := {"event": fields.event, "launch": launch}
	record.merge(fields)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path)
		else FileAccess.WRITE)
	if file == null:
		_fail(error_string(FileAccess.get_open_error()))
		return
	file.seek_end()
	var written := file.store_line(JSON.stringify(record, "", false))
	file.close()
	if not written:
		_fail("write failed")

func _fail(reason: String) -> void:
	failed = true
	push_warning("Booth session log: cannot write %s (%s); session logging is off." % [path, reason])
