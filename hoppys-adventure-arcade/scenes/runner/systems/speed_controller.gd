extends Node
## Single owner of the authoritative corridor speed and difficulty (systems spec §1.2, §10.2).
## speed = lerp(base + b, max + b, smoothstep(0, 1, run_clock / time_to_max_speed)), then
## +1 m/s per 60 s of tail up to hard_cap + b, then the Nitro multiplier clamped to nitro_speed_cap,
## then the boss-cinematic scale (contract 2.6 §11.14, 1 outside a cinematic).
##
## v2: the curve is read at `run_clock` (RUN-phase seconds), not `elapsed`, so speed holds at the
## value it reached through a turn, a boss fight and the stage-clear card. The stage bonus b and the
## difficulty floor are pushed in by the StageManager on every _enter_run().

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
## The frontend only needs to hear about difficulty when it actually moves (contract §4.1).
const DIFFICULTY_EPSILON := 0.01
## Seconds set_cinematic_scale() takes to reach its target by default (contract 2.6 §11.14).
const CINEMATIC_EASE_SECONDS := 0.35

var game: RunnerGame
var config: RunConfig
## Metres per second the chunks travel toward +Z.
var speed := 0.0
## 0..1, max(clamp(run_clock / time_to_max_speed, 0, 1), difficulty_floor).
var difficulty := 0.0
## Nitro multiplier applied on top of the curve.
var multiplier := 1.0
## RUN-phase seconds; Nitro does not advance it and neither do the turn, boss or stage-clear phases.
var run_clock := 0.0
## Metres per second added to base, max and hard cap for the current stage (contract §11.2).
var stage_bonus := 0.0
## Lower bound on `difficulty` for the current stage (contract §11.2).
var difficulty_floor := 0.0
var max_speed_reached := 0.0
var stopping := false
var stop_seconds := 0.0
## 0..1 multiplier on the curve while a boss cinematic holds the player (contract 2.6 §11.14),
## eased toward its target; 1 the rest of the time. It never touches run_clock, so the curve picks
## up exactly where it was once the cinematic lets go.
var cinematic_scale := 1.0

## Difficulty last pushed through difficulty_changed.
var _emitted_difficulty := 0.0
## Speed the catch deceleration started from, so begin_stop() reaches 0 in stop_seconds.
var _stop_from_speed := 0.0
var _cinematic_target := 1.0
## Scale units per second toward _cinematic_target.
var _cinematic_rate := 0.0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

func reset() -> void:
	run_clock = 0.0
	difficulty = 0.0
	multiplier = 1.0
	stage_bonus = 0.0
	difficulty_floor = 0.0
	stopping = false
	stop_seconds = 0.0
	_stop_from_speed = 0.0
	_emitted_difficulty = 0.0
	cinematic_scale = 1.0
	_cinematic_target = 1.0
	_cinematic_rate = 0.0
	speed = base_for_stage()
	max_speed_reached = speed

## Stage bonus b: added to base, max and hard cap inside speed_at() (contract §11.2).
func set_stage_bonus(bonus: float) -> void:
	stage_bonus = maxf(bonus, 0.0)

## The floor the difficulty curve can never fall below on this stage (contract §11.2).
func set_difficulty_floor(value: float) -> void:
	difficulty_floor = clampf(value, 0.0, 1.0)

## Contract 2.6 §11.14: ease the corridor to `target` x its curve speed over `seconds` (the
## StageManager asks for boss_cinematic_speed_scale while a cinematic holds the player, then 1).
## A non-positive `seconds` snaps straight to the target.
func set_cinematic_scale(target: float, seconds := CINEMATIC_EASE_SECONDS) -> void:
	_cinematic_target = clampf(target, 0.0, 1.0)
	if seconds <= 0.0:
		cinematic_scale = _cinematic_target
		_cinematic_rate = 0.0
		return
	_cinematic_rate = absf(_cinematic_target - cinematic_scale) / seconds

## Base corridor speed for the current stage: what stage_started reports (systems spec §10.1).
func base_for_stage() -> float:
	if config == null:
		return 0.0
	return float(config.base_speed) + stage_bonus

## Base corridor speed at the given RUN-phase time, before the Nitro multiplier.
func speed_at(time: float) -> float:
	if config == null:
		return 0.0
	var ramp := float(config.time_to_max_speed)
	var d := clampf(time / ramp, 0.0, 1.0) if ramp > 0.0 else 1.0
	var value := lerpf(float(config.base_speed) + stage_bonus, float(config.max_speed) + stage_bonus,
		smoothstep(0.0, 1.0, d))
	if time > ramp:
		value += (time - ramp) / 60.0 * float(config.tail_speed_per_minute)
	return minf(value, float(config.hard_cap_speed) + stage_bonus)

## Difficulty at the given RUN-phase time (contract §7, §11.2).
func difficulty_at(time: float) -> float:
	if config == null:
		return 0.0
	var ramp := float(config.time_to_max_speed)
	if ramp <= 0.0:
		return 1.0
	return maxf(clampf(time / ramp, 0.0, 1.0), difficulty_floor)

## (speed - base_eff) / (max_eff - base_eff), both ends carrying the stage bonus; may exceed 1.0
## during Nitro.
func normalized() -> float:
	if config == null:
		return 0.0
	var span := float(config.max_speed) - float(config.base_speed)
	if absf(span) < 0.0001:
		return 0.0
	return (speed - base_for_stage()) / span

## Decelerate to a stop over `seconds` for the catch cinematic.
func begin_stop(seconds: float) -> void:
	stopping = true
	stop_seconds = maxf(seconds, 0.0)
	_stop_from_speed = speed

func _physics_process(delta: float) -> void:
	if config == null:
		return
	var state: StringName = game.state if game != null else &"running"
	if state == &"running":
		# The StageManager owns the RUN-phase clock; mirror it so a standalone controller in a unit
		# test still advances on its own. A frozen run_clock holds the speed where it was.
		run_clock = float(game.run_clock) if game != null else run_clock + delta
		_ease_cinematic_scale(delta)
		_advance()
	elif stopping and state == &"caught":
		# A catch lets go of a cinematic hold too (contract §11.14): the scale still eases home,
		# while the stop itself decelerates from the speed the corridor had already reached.
		_ease_cinematic_scale(delta)
		_decelerate(delta)
	else:
		return
	max_speed_reached = maxf(max_speed_reached, speed)
	_publish()

## The difficulty curve, the tail and the Nitro clamp (contract §7 Speed row, §11.2), then the
## cinematic scale (§11.14), which can only ever slow the corridor.
func _advance() -> void:
	var curve := speed_at(run_clock)
	speed = curve if is_equal_approx(multiplier, 1.0) else minf(curve * multiplier, float(config.nitro_speed_cap))
	speed *= cinematic_scale
	difficulty = difficulty_at(run_clock)

func _ease_cinematic_scale(delta: float) -> void:
	if is_equal_approx(cinematic_scale, _cinematic_target):
		cinematic_scale = _cinematic_target
		return
	cinematic_scale = move_toward(cinematic_scale, _cinematic_target, _cinematic_rate * delta)

func _decelerate(delta: float) -> void:
	if stop_seconds <= 0.0:
		speed = 0.0
		return
	speed = maxf(speed - _stop_from_speed / stop_seconds * delta, 0.0)

func _publish() -> void:
	if game == null:
		return
	game.speed = speed
	game.normalized_speed = normalized()
	game.difficulty = difficulty
	game.speed_changed.emit(speed, game.normalized_speed)
	# The terminal 1.0 is always announced, even though the last emitted value is inside the epsilon:
	# the frontend keys its top-difficulty state off it. Every intermediate value keeps the epsilon
	# suppression, and 1.0 is never emitted twice.
	var reached_max := difficulty >= 1.0 and _emitted_difficulty < 1.0
	if not reached_max and absf(difficulty - _emitted_difficulty) < DIFFICULTY_EPSILON:
		return
	_emitted_difficulty = difficulty
	game.difficulty_changed.emit(difficulty)
