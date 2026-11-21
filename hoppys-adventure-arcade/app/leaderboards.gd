extends RefCounted
## One local top ten per game. The Endless Runner's leaderboard engine
## (scenes/runner/systems/runner_leaderboard.gd: validated entries, atomic writes, a .bak, a
## schema version) stores every board; this maps a game's route to its file and records a finished
## run in one call. The runner keeps its own file and name-entry flow, so its route maps to the
## engine's default path and the other five games write under user://leaderboards/.
##
## A booth has no keyboard within players' reach, so a run is recorded under a name that still
## tells rows apart on the board: "Hoppy" plus the time of day it finished.

const Board := preload("res://scenes/runner/systems/runner_leaderboard.gd")
const RUNNER_ROUTE := "runner_game"
const DIR := "user://leaderboards/"
const SCRATCH_PREFIX := "user://test_leaderboards_"
## Tests and dev captures point every board somewhere else with this; "" means the real files.
static var override_dir := ""
## A headless suite (run with --script, the convention AppRouter uses) that plays a game to its
## results screen records runs like any player. With no override_dir, those land in a scratch
## folder of this process instead of the player's boards, so a suite run outside
## tools/tests/run_tests.py (which gives each suite a private user://) still leaves them alone.
## Stale scratch folders from earlier runs are removed the first time one is used.
static var redirect_tests := true
static var scratch_dir := ""

## The folder boards are written to: the override, a test's scratch folder, or the real one.
static func dir() -> String:
	if not override_dir.is_empty():
		return override_dir
	if redirect_tests and "--script" in OS.get_cmdline_args():
		return _scratch()
	return DIR

static func _scratch() -> String:
	if scratch_dir.is_empty():
		scratch_dir = "%s%d/" % [SCRATCH_PREFIX, OS.get_process_id()]
		for folder in DirAccess.get_directories_at("user://"):
			var path := "user://" + folder + "/"
			if path.begins_with(SCRATCH_PREFIX) and path != scratch_dir:
				clear_scratch(path)
	return scratch_dir

## Removes a test's scratch folder (this process's by default) and the boards in it.
static func clear_scratch(folder := scratch_dir) -> void:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder + file)
	DirAccess.remove_absolute(folder)

## The board file for `route`.
static func path_for(route: String) -> String:
	if route == RUNNER_ROUTE and dir() == DIR:
		return Board.DEFAULT_PATH
	return dir() + route + ".cfg"

## Records a finished run and returns the engine's {rank, entries, error}: rank is 1-10 when the
## run placed, 0 otherwise. `duration` is the run's length in seconds.
static func record(route: String, score: int, duration: float, player_name := "") -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return Board.submit({
		"run_id": "%s-%d-%d" % [route, now, Time.get_ticks_usec()],
		"name": player_name if not player_name.is_empty() else default_name(),
		"score": maxi(0, score),
		"duration": maxf(0.0, duration),
		"seed": 0,
		"submitted_at": now,
	}, path_for(route))

## The sorted rows of `route`'s board, best first.
static func entries(route: String) -> Array[Dictionary]:
	return Board.load_entries(path_for(route))

## "Hoppy 14:32": the mascot plus the local time, so a booth's board stays readable without typing.
static func default_name() -> String:
	var clock := Time.get_time_dict_from_system()
	return "Hoppy %02d:%02d" % [int(clock.hour), int(clock.minute)]

## The line a results screen shows for a recorded run: a rank, or nothing when it did not place
## or could not be saved.
static func rank_line(result: Dictionary) -> String:
	var rank := int(result.get("rank", 0))
	if rank <= 0 or int(result.get("error", OK)) != OK:
		return ""
	return "LEADERBOARD  #%d" % rank
