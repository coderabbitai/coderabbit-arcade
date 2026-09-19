extends Node
## The six power-ups: refresh-not-stack timers, invulnerability sources, one-shot tokens
## (systems spec §6). Timed kinds keep one activation alive, so power_up_expired fires once.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")

const SHIELD: StringName = &"approve_shield"
const AUTO_FIX: StringName = &"auto_fix"
const LGTM: StringName = &"lgtm"
const NITRO: StringName = &"nitro"
const SUPER_JUMP: StringName = &"super_jump"
const CODE_REVIEW: StringName = &"code_review"

var game: RunnerGame
var config: RunConfig
## kind -> {"remaining": float, "total": float} for timed effects only.
var active := {}
## Super Jump is a stored token, consumed by the player when a jump starts.
var super_jump_ready := false
## Code Review Bonus lasts until an unblocked hit.
var code_review_held := false
var power_ups_collected := 0
## Seconds left of the Nitro ease-down: the speed multiplier falls back to 1.0 across it and the
## nitro invulnerability source is held until it ends (contract §7).
var nitro_ease_remaining := 0.0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

## `new_config` lets a test swap in a duplicated RunConfig; the shared .tres is never mutated.
func reset(new_config: RunConfig = null) -> void:
	if new_config != null:
		config = new_config
	active = {}
	super_jump_ready = false
	code_review_held = false
	power_ups_collected = 0
	nitro_ease_remaining = 0.0

## Apply a collected power-up. Timed kinds refresh rather than stack.
func apply(kind: StringName) -> void:
	power_ups_collected += 1
	match kind:
		SHIELD:
			_hit_manager_call("set_shield", [true])
		AUTO_FIX:
			_apply_auto_fix()
		LGTM:
			_start_timed(LGTM, duration_for(LGTM))
			_hit_manager_call("add_invuln_source", [LGTM])
		NITRO:
			_start_timed(NITRO, duration_for(NITRO))
			nitro_ease_remaining = 0.0
			_set_speed_multiplier(float(config.nitro_speed_multiplier) if config != null else 1.0)
			_score_call("set_nitro", [true])
			_hit_manager_call("add_invuln_source", [NITRO])
		SUPER_JUMP:
			super_jump_ready = true
		CODE_REVIEW:
			code_review_held = true
			_score_call("set_code_review", [true])
		_:
			push_warning("Runner effect manager: unknown power-up kind %s" % kind)
	# Every pickup pays the same flat bonus (contract §7).
	_score_call("add_bonus", [pickup_bonus(), kind])
	if game != null:
		game.power_up_collected.emit(kind, duration_for(kind))

## True once per Super Jump pickup; the player calls this when a jump starts, and owns the
## invulnerability source (&"super_jump") until landing + 0.5 s (contract §7).
func consume_super_jump() -> bool:
	if not super_jump_ready:
		return false
	super_jump_ready = false
	if game != null:
		game.power_up_expired.emit(SUPER_JUMP)
	return true

## An unblocked hit landed: the Code Review Bonus is lost.
func on_damage_applied() -> void:
	if not code_review_held:
		return
	code_review_held = false
	_score_call("set_code_review", [false])
	if game != null:
		game.power_up_expired.emit(CODE_REVIEW)

## Total duration for a kind; 0.0 for one-shot kinds (contract §4.1).
func duration_for(kind: StringName) -> float:
	if config != null:
		match kind:
			NITRO:
				return float(config.nitro_duration)
			LGTM:
				return float(config.lgtm_duration)
			_:
				return 0.0
	return PowerUpDefs.duration(kind)

func pickup_bonus() -> int:
	return int(config.pickup_bonus) if config != null else 0

func is_active(kind: StringName) -> bool:
	return active.has(kind)

func has_super_jump() -> bool:
	return super_jump_ready

func has_code_review() -> bool:
	return code_review_held

## Snapshot for HUD polling: kind -> {remaining, total}.
func get_active_effects() -> Dictionary:
	var snapshot := {}
	for kind in active:
		snapshot[kind] = (active[kind] as Dictionary).duplicate()
	return snapshot

func _physics_process(delta: float) -> void:
	if game == null or game.state != &"running":
		return
	for kind in active.keys():
		var entry: Dictionary = active[kind]
		entry["remaining"] = float(entry["remaining"]) - delta
		if float(entry["remaining"]) > 0.0:
			continue
		active.erase(kind)
		_on_timed_expired(kind)
	_tick_nitro_ease(delta)

## Refresh-not-stack: a second pickup restarts the same activation, so no expiry fires in between.
func _start_timed(kind: StringName, total: float) -> void:
	if total <= 0.0:
		return
	active[kind] = {"remaining": total, "total": total}

func _on_timed_expired(kind: StringName) -> void:
	match kind:
		LGTM:
			_hit_manager_call("remove_invuln_source", [LGTM])
		NITRO:
			_score_call("set_nitro", [false])
			# The corridor eases back to the base speed; i-frames hold until it is done.
			nitro_ease_remaining = float(config.nitro_ease_down) if config != null else 0.0
			if nitro_ease_remaining <= 0.0:
				_end_nitro_ease()
	if game != null:
		game.power_up_expired.emit(kind)

func _tick_nitro_ease(delta: float) -> void:
	if nitro_ease_remaining <= 0.0:
		return
	nitro_ease_remaining -= delta
	var total := float(config.nitro_ease_down) if config != null else 0.0
	var peak := float(config.nitro_speed_multiplier) if config != null else 1.0
	if nitro_ease_remaining <= 0.0 or total <= 0.0:
		_end_nitro_ease()
		return
	_set_speed_multiplier(lerpf(1.0, peak, clampf(nitro_ease_remaining / total, 0.0, 1.0)))

func _end_nitro_ease() -> void:
	nitro_ease_remaining = 0.0
	_set_speed_multiplier(1.0)
	_hit_manager_call("remove_invuln_source", [NITRO])

## Auto-Fix clears every blocking hazard ahead and pays per hazard (systems spec §5.2 / §6).
func _apply_auto_fix() -> void:
	var cleared := 0
	var spawner: Node = game.spawner if game != null else null
	if spawner != null and is_instance_valid(spawner) and spawner.has_method("clear_hazards_in_range"):
		cleared = int(spawner.clear_hazards_in_range())
	if cleared > 0:
		var per := int(config.blast_bonus_per_hazard) if config != null else 0
		_score_call("add_bonus", [per * cleared, AUTO_FIX])
	# Once per Auto-Fix, after every hazard_cleared (contract §4.1).
	if game != null:
		game.hazards_blasted.emit(cleared)

func _set_speed_multiplier(value: float) -> void:
	var controller: Node = game.speed_controller if game != null else null
	if controller != null and is_instance_valid(controller) and &"multiplier" in controller:
		controller.set(&"multiplier", value)

func _hit_manager_call(method: String, args: Array) -> void:
	var hits: Node = game.hit_manager if game != null else null
	if hits != null and is_instance_valid(hits) and hits.has_method(method):
		hits.callv(method, args)

func _score_call(method: String, args: Array) -> void:
	var score: Node = game.score_manager if game != null else null
	if score != null and is_instance_valid(score) and score.has_method(method):
		score.callv(method, args)
