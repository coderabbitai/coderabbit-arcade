extends Node
## Single owner of the authoritative corridor speed and difficulty (systems spec §1.2).
## PR 1 scaffold: signatures and state only; the curve is implemented in PR 2.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")

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

func _physics_process(_delta: float) -> void:
	pass # PR 2: advance elapsed/difficulty, apply the curve, Nitro and the catch stop.
