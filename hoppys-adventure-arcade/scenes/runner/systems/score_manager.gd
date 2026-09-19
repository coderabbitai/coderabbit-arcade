extends Node
## Fractional score with a composed multiplier (systems spec §6).
## PR 1 scaffold: state and the public API; accumulation lands in PR 2.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")

var game: RunnerGame
var config: RunConfig
## Fractional accumulator; the displayed score is floori(exact).
var exact := 0.0
var score := 0
var multiplier := 1.0
var best_multiplier := 1.0
var nitro_active := false
var code_review_active := false

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

func reset() -> void:
	exact = 0.0
	score = 0
	nitro_active = false
	code_review_active = false
	multiplier = 1.0
	best_multiplier = 1.0

func set_nitro(active: bool) -> void:
	nitro_active = active
	_refresh_multiplier()

func set_code_review(active: bool) -> void:
	code_review_active = active
	_refresh_multiplier()

## Recompose the multiplier and push it out immediately, so the HUD badge does not wait for the
## next integer score change (contract §4.1 score_changed).
func _refresh_multiplier() -> void:
	var value := current_multiplier()
	best_multiplier = maxf(best_multiplier, value)
	if is_equal_approx(value, multiplier):
		return
	multiplier = value
	if game != null:
		game.score_changed.emit(score, multiplier)

## Nitro x2 composed with Code Review x1.5 (contract §7).
func current_multiplier() -> float:
	if config == null:
		return 1.0
	var value := 1.0
	if nitro_active:
		value *= float(config.nitro_score_multiplier)
	if code_review_active:
		value *= float(config.code_review_score_multiplier)
	return value

func add_bonus(points: int, reason: StringName) -> void:
	if points == 0:
		return
	exact += float(points)
	score = floori(exact)
	if game != null:
		game.bonus_awarded.emit(points, reason)
		game.score_changed.emit(score, multiplier)

func _physics_process(_delta: float) -> void:
	pass # PR 2: accumulate base_score_rate * multiplier * delta and emit on integer/multiplier change.
