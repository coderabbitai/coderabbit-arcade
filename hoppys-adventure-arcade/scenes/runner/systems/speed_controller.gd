extends Node
## Single owner of the authoritative corridor speed and difficulty (systems spec §1.2).
## speed = lerp(base, max, smoothstep(0, 1, elapsed / time_to_max_speed)), then +1 m/s per 60 s of
## tail up to hard_cap, then the Nitro multiplier clamped to nitro_speed_cap.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
## The frontend only needs to hear about difficulty when it actually moves (contract §4.1).
const DIFFICULTY_EPSILON := 0.01

var game: RunnerGame
var config: RunConfig
## Metres per second the chunks travel toward +Z.
var speed := 0.0
## 0..1, clamp(elapsed / time_to_max_speed, 0, 1).
var difficulty := 0.0
## Nitro multiplier applied on top of the curve.
var multiplier := 1.0
## Unpaused running seconds; Nitro does not advance it.
var elapsed := 0.0
var max_speed_reached := 0.0
var stopping := false
var stop_seconds := 0.0

## Difficulty last pushed through difficulty_changed.
var _emitted_difficulty := 0.0
## Speed the catch deceleration started from, so begin_stop() reaches 0 in stop_seconds.
var _stop_from_speed := 0.0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

func reset() -> void:
	elapsed = 0.0
	difficulty = 0.0
	multiplier = 1.0
	stopping = false
	stop_seconds = 0.0
	_stop_from_speed = 0.0
	_emitted_difficulty = 0.0
	speed = float(config.base_speed) if config != null else 0.0
	max_speed_reached = speed

## Base corridor speed at the given unpaused run time, before the Nitro multiplier.
func speed_at(time: float) -> float:
	if config == null:
		return 0.0
	var ramp := float(config.time_to_max_speed)
	var d := clampf(time / ramp, 0.0, 1.0) if ramp > 0.0 else 1.0
	var value := lerpf(float(config.base_speed), float(config.max_speed), smoothstep(0.0, 1.0, d))
	if time > ramp:
		value += (time - ramp) / 60.0 * float(config.tail_speed_per_minute)
	return minf(value, float(config.hard_cap_speed))

## Difficulty at the given unpaused run time (contract §7).
func difficulty_at(time: float) -> float:
	if config == null:
		return 0.0
	var ramp := float(config.time_to_max_speed)
	if ramp <= 0.0:
		return 1.0
	return clampf(time / ramp, 0.0, 1.0)

## (speed - base) / (max - base); may exceed 1.0 during Nitro.
func normalized() -> float:
	if config == null:
		return 0.0
	var span := float(config.max_speed) - float(config.base_speed)
	if absf(span) < 0.0001:
		return 0.0
	return (speed - float(config.base_speed)) / span

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
		# RunnerGame owns the clock (it is the node that survives pause); mirror it so a standalone
		# controller in a unit test still advances on its own.
		elapsed = float(game.elapsed) if game != null else elapsed + delta
		_advance()
	elif stopping and state == &"caught":
		_decelerate(delta)
	else:
		return
	max_speed_reached = maxf(max_speed_reached, speed)
	_publish()

## The difficulty curve, the tail and the Nitro clamp (contract §7 Speed row).
func _advance() -> void:
	var curve := speed_at(elapsed)
	speed = curve if is_equal_approx(multiplier, 1.0) else minf(curve * multiplier, float(config.nitro_speed_cap))
	difficulty = difficulty_at(elapsed)

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
