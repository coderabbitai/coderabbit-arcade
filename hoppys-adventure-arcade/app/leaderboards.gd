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
## Tests and dev captures point every board somewhere else with this; "" means the real files.
static var override_dir := ""

## The board file for `route`.
static func path_for(route: String) -> String:
	if route == RUNNER_ROUTE and override_dir.is_empty():
		return Board.DEFAULT_PATH
	return (override_dir if not override_dir.is_empty() else DIR) + route + ".cfg"

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
