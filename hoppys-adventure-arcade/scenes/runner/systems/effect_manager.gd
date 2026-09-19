extends Node
## The six power-ups: refresh-not-stack timers, invulnerability sources, one-shot tokens
## (systems spec §6). PR 1 scaffold: state and the public API; behaviour lands in PR 2.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")

var game: RunnerGame
var config: RunConfig
## kind -> {"remaining": float, "total": float} for timed effects only.
var active := {}
## Super Jump is a stored token, consumed by the player when a jump starts.
var super_jump_ready := false
## Code Review Bonus lasts until an unblocked hit.
var code_review_held := false
var power_ups_collected := 0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

func reset() -> void:
	active = {}
	super_jump_ready = false
	code_review_held = false
	power_ups_collected = 0

## Apply a collected power-up. Timed kinds refresh rather than stack.
func apply(_kind: StringName) -> void:
	pass # PR 2: shield / auto_fix / lgtm / nitro / super_jump / code_review.

## True once per Super Jump pickup; the player calls this when a jump starts.
func consume_super_jump() -> bool:
	return false # PR 2.

## An unblocked hit landed: the Code Review Bonus is lost.
func on_damage_applied() -> void:
	pass # PR 2.

## Total duration for a kind; 0.0 for one-shot kinds (contract §4.1).
func duration_for(kind: StringName) -> float:
	return PowerUpDefs.duration(kind)

func is_active(kind: StringName) -> bool:
	return active.has(kind)

func has_super_jump() -> bool:
	return super_jump_ready

## Snapshot for HUD polling: kind -> {remaining, total}.
func get_active_effects() -> Dictionary:
	var snapshot := {}
	for kind in active:
		snapshot[kind] = (active[kind] as Dictionary).duplicate()
	return snapshot

func _physics_process(_delta: float) -> void:
	pass # PR 2: tick timers, ease Nitro down, emit power_up_expired once per activation.
