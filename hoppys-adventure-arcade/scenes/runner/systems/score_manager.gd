extends Node
## Fractional score with a composed multiplier (systems spec §6). The accumulator is a float so
## 30 fps and 60 fps runs award the same points; only the integer part is ever shown.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")

## Reasons add_bonus() carries out through bonus_awarded (contract §4.1). A power-up pays under its
## own kind (`approve_shield`, `code_review`, `super_jump`, `nitro`, `auto_fix`, `lgtm`); the four
## below are the v2 stage and boss payouts (contract §11.4, systems spec §10.7). The reason is a
## label for the HUD and the audio bank, so an unlisted one is still awarded, just unrecognised.
const REASON_TOOL: StringName = &"tool"
const REASON_BOSS_KILL: StringName = &"boss_kill"
const REASON_BOSS_RETREAT: StringName = &"boss_retreat"
const REASON_STAGE_CLEAR: StringName = &"stage_clear"
## The v2 reasons, in the order a stage pays them out.
const V2_BONUS_REASONS: Array[StringName] = [
	REASON_TOOL, REASON_BOSS_KILL, REASON_BOSS_RETREAT, REASON_STAGE_CLEAR
]

var game: RunnerGame
var config: RunConfig
## Fractional accumulator; the displayed score is floori(exact).
var exact := 0.0
var score := 0
var multiplier := 1.0
var best_multiplier := 1.0
var nitro_active := false
var code_review_active := false
## Points awarded by pickups and Auto-Fix blasts, for the result dictionary.
var bonus_total := 0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

## `new_config` lets a test swap in a duplicated RunConfig; the shared .tres is never mutated.
func reset(new_config: RunConfig = null) -> void:
	if new_config != null:
		config = new_config
	exact = 0.0
	score = 0
	nitro_active = false
	code_review_active = false
	multiplier = 1.0
	best_multiplier = 1.0
	bonus_total = 0

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

## A one-off award on top of the running score. `reason` is one of the pickup kinds or of the
## REASON_* constants above; 0 points is not an award and stays silent.
func add_bonus(points: int, reason: StringName) -> void:
	if points == 0:
		return
	exact += float(points)
	score = floori(exact)
	bonus_total += points
	if game != null:
		game.bonus_awarded.emit(points, reason)
		game.score_changed.emit(score, multiplier)

func base_rate() -> float:
	return float(config.base_score_rate) if config != null else 0.0

## base_score_rate x multiplier x delta, emitted only when the integer score or the multiplier
## changes (contract §4.1). Nothing accrues during the run intro (contract 2.7 §11.15).
func _physics_process(delta: float) -> void:
	if game == null or game.state != &"running":
		return
	if &"run_intro_mode" in game and StringName(game.get(&"run_intro_mode")) != &"":
		return
	var value := current_multiplier()
	var multiplier_changed := not is_equal_approx(value, multiplier)
	multiplier = value
	best_multiplier = maxf(best_multiplier, value)
	exact += base_rate() * multiplier * delta
	var display := floori(exact)
	var score_changed := display != score
	score = display
	if game != null and (score_changed or multiplier_changed):
		game.score_changed.emit(score, multiplier)
