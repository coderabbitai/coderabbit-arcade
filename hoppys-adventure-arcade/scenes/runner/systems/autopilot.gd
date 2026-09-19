extends Node
## Fair / reckless bot used by tests and the F7 debug toggle (systems spec §8, Autopilot).
## PR 1 scaffold: state and the public API; planning lands in PR 2.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")

enum Mode { PREFER_LANE, PREFER_JUMP, GREEDY_PICKUP }

var game: RunnerGame
var config: RunConfig
var enabled := false
var mode := Mode.PREFER_LANE
## Reckless mode: ignore this many upcoming slices.
var reckless_skips := 0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

func reset() -> void:
	enabled = false
	mode = Mode.PREFER_LANE
	reckless_skips = 0

func set_enabled(on: bool) -> void:
	enabled = on

func set_mode(value: int) -> void:
	mode = value as Mode

func set_reckless(slices: int) -> void:
	reckless_skips = maxi(slices, 0)

## Distance ahead the bot plans over, in metres.
func lookahead() -> float:
	if config == null or game == null:
		return 0.0
	return float(game.speed) * float(config.autopilot_plan_lead) + 0.4

func _physics_process(_delta: float) -> void:
	pass # PR 2: slice hazards ahead, plan the nearest unresolved slice, drive the player.
