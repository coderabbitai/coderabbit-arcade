extends Node
## SAFE / PURSUED / DEAD state machine (systems spec §4). Every hazard overlap is resolved here,
## synchronously and in one fixed order, and every outcome is announced through the RunnerGame
## facade signals (contract §4.1).

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")

enum HitState { SAFE, PURSUED, DEAD }

## report_hit() outcomes.
const IGNORED: StringName = &"ignored"
const BLOCKED_INVULN: StringName = &"blocked_invuln"
const BLOCKED_SHIELD: StringName = &"blocked_shield"
const DAMAGED: StringName = &"damaged"
## damage_blocked reasons (contract §4.1): iframes, shield, lgtm, nitro, super_jump.
const REASON_IFRAMES: StringName = &"iframes"
const REASON_SHIELD: StringName = &"shield"
## pursuit_recovered reasons (contract §4.1).
const RECOVERED_TIMER: StringName = &"timer"
const RECOVERED_SHIELD: StringName = &"shield"
## pursuit_alert kinds (contract §11.4): warn at pursuit start, critical once the recovery timer
## drops under pursuit_critical_seconds, clear on recovery or catch.
const ALERT_WARN: StringName = &"warn"
const ALERT_CRITICAL: StringName = &"critical"
const ALERT_CLEAR: StringName = &"clear"
const DEFAULT_PURSUIT_CRITICAL_SECONDS := 5.0
## Reported as the hazard kind when a caller passes something without one.
const UNKNOWN_KIND: StringName = &"unknown"
## Contract §7 fallbacks, used only when no config has been supplied yet. Zero would read as
## "no recovery window, no i-frames", which is a different game, so mirror the authored values.
const DEFAULT_MAX_HP := 2
const DEFAULT_RECOVERY_SECONDS := 18.0
const DEFAULT_HIT_IFRAMES := 0.8

var game: RunnerGame
var config: RunConfig
var state := HitState.SAFE
var hp := 0
var iframe_remaining := 0.0
var recovery_remaining := 0.0
var recovery_total := 0.0
var shield := false
## StringName -> true. Any entry blocks damage (lgtm, nitro, super_jump, ...).
var invuln_sources := {}
## Hazard instance id -> true, so one hazard can never damage twice.
var consumed_ids := {}
var hits_taken := 0
var blocked_hits := 0
var recoveries := 0

## The critical alert fires once per pursuit, not once per tick.
var _critical_alerted := false

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

## `new_config` lets a test swap in a duplicated RunConfig; the shared .tres is never mutated.
func reset(new_config: RunConfig = null) -> void:
	if new_config != null:
		config = new_config
	state = HitState.SAFE
	hp = max_hp()
	iframe_remaining = 0.0
	recovery_remaining = 0.0
	recovery_total = recovery_seconds()
	shield = false
	invuln_sources = {}
	consumed_ids = {}
	hits_taken = 0
	blocked_hits = 0
	recoveries = 0
	_critical_alerted = false

## Resolve a hazard overlap synchronously, in the systems spec §4 order:
## dead -> already consumed -> i-frames or invulnerability -> shield -> damage.
## Returns ignored / blocked_invuln / blocked_shield / damaged.
func report_hit(hazard: Node) -> StringName:
	# 1. Nothing touches a dead runner.
	if state == HitState.DEAD:
		return IGNORED
	# 2. One hazard, one resolution: dedupe by instance id.
	if hazard != null:
		var id := hazard.get_instance_id()
		if consumed_ids.has(id):
			return IGNORED
		consumed_ids[id] = true
	var kind := hazard_kind(hazard)
	# 3. i-frames and invulnerability sources. The hazard stays consumed: LGTM smashes through.
	var reason := block_reason()
	if reason != &"":
		blocked_hits += 1
		_emit_blocked(kind, reason)
		return BLOCKED_INVULN
	# 4. Approve Shield: one free hit, and it also buys a pursuit back.
	if shield:
		blocked_hits += 1
		shield = false
		# The shield pops on one hazard, so it has to grant the same breathing room the damage path
		# does: without the i-frames a second, different hazard overlapping on one of the next ticks
		# would land damage immediately after the block.
		iframe_remaining = iframe_seconds()
		if game != null:
			game.shield_changed.emit(false)
		_emit_blocked(kind, REASON_SHIELD)
		if state == HitState.PURSUED:
			state = HitState.SAFE
			hp = max_hp()
			recovery_remaining = 0.0
			# `recoveries` counts every exit from PURSUED back to SAFE, by shield as well as by
			# timer (systems spec §4, step 4).
			recoveries += 1
			if game != null:
				game.health_changed.emit(hp, max_hp())
				game.pursuit_recovered.emit(RECOVERED_SHIELD)
			_emit_alert(ALERT_CLEAR, 0.0)
		return BLOCKED_SHIELD
	# 5. Damage.
	hits_taken += 1
	hp = maxi(hp - 1, 0)
	iframe_remaining = iframe_seconds()
	if game != null:
		game.damage_taken.emit(kind, hp)
		game.health_changed.emit(hp, max_hp())
	_notify_damage_applied()
	if hp <= 0:
		# Second hit while pursued (hp 0): the catch cinematic owns everything from here.
		state = HitState.DEAD
		recovery_remaining = 0.0
		_announce_caught()
	elif state != HitState.PURSUED:
		# First hit (hp 1 at max_hp 2): the pursuer closes in for recovery_seconds.
		state = HitState.PURSUED
		recovery_total = recovery_seconds()
		recovery_remaining = recovery_total
		_critical_alerted = false
		if game != null:
			game.pursuit_started.emit(recovery_total)
		# The alert rides alongside pursuit_started so the incoming-transmission panel can open on
		# the same frame the pursuer does (contract §11.4).
		_emit_alert(ALERT_WARN, recovery_total)
	return DAMAGED

func set_shield(active: bool) -> void:
	if shield == active:
		return
	shield = active
	if game != null:
		game.shield_changed.emit(active)

func add_invuln_source(source: StringName) -> void:
	invuln_sources[source] = true

func remove_invuln_source(source: StringName) -> void:
	invuln_sources.erase(source)

## Spelled-out aliases; the systems keep using the short scaffold names.
func add_invulnerability(source: StringName) -> void:
	add_invuln_source(source)

func remove_invulnerability(source: StringName) -> void:
	remove_invuln_source(source)

func is_invulnerable() -> bool:
	return iframe_remaining > 0.0 or not invuln_sources.is_empty()

func is_alive() -> bool:
	return state != HitState.DEAD

func is_pursued() -> bool:
	return state == HitState.PURSUED

func is_safe() -> bool:
	return state == HitState.SAFE

## Why a hit would be blocked right now, or &"" when it would land. i-frames win over the named
## sources so a follow-up overlap in the same 0.8 s always reads as `iframes` (contract §4.1).
func block_reason() -> StringName:
	if iframe_remaining > 0.0:
		return REASON_IFRAMES
	for source in invuln_sources:
		return StringName(source)
	return &""

func hazard_kind(hazard: Node) -> StringName:
	if hazard != null and &"kind" in hazard:
		return StringName(hazard.get(&"kind"))
	return UNKNOWN_KIND

func max_hp() -> int:
	return int(config.max_hp) if config != null else DEFAULT_MAX_HP

func recovery_seconds() -> float:
	return float(config.recovery_seconds) if config != null else DEFAULT_RECOVERY_SECONDS

func iframe_seconds() -> float:
	return float(config.hit_iframes) if config != null else DEFAULT_HIT_IFRAMES

func pursuit_critical_seconds() -> float:
	if config == null or not (&"pursuit_critical_seconds" in config):
		return DEFAULT_PURSUIT_CRITICAL_SECONDS
	return float(config.pursuit_critical_seconds)

## Ordering guarantee (systems spec §4): Area3D overlaps are delivered at the start of a physics
## tick, before any _physics_process, and report_hit never grants recovery. A hit on the tick the
## recovery timer would expire therefore kills.
func _physics_process(delta: float) -> void:
	if game == null or game.state != &"running":
		return
	if iframe_remaining > 0.0:
		iframe_remaining = maxf(iframe_remaining - delta, 0.0)
	if state != HitState.PURSUED:
		return
	recovery_remaining -= delta
	if game != null:
		game.pursuit_progress.emit(maxf(recovery_remaining, 0.0), recovery_total)
	if recovery_remaining > 0.0:
		if not _critical_alerted and recovery_remaining <= pursuit_critical_seconds():
			_critical_alerted = true
			_emit_alert(ALERT_CRITICAL, recovery_remaining)
		return
	state = HitState.SAFE
	hp = max_hp()
	recovery_remaining = 0.0
	recoveries += 1
	if game != null:
		game.health_changed.emit(hp, max_hp())
		game.pursuit_recovered.emit(RECOVERED_TIMER)
	_emit_alert(ALERT_CLEAR, 0.0)

func _emit_blocked(kind: StringName, reason: StringName) -> void:
	if game != null:
		game.damage_blocked.emit(kind, reason)

## contract §11.4. The facade may predate v2, so the signal is looked up before it is used.
func _emit_alert(kind: StringName, seconds_to_catch: float) -> void:
	if game == null or not game.has_signal(&"pursuit_alert"):
		return
	game.pursuit_alert.emit(kind, maxf(seconds_to_catch, 0.0))

## An unblocked hit drops the Code Review Bonus (systems spec §6).
func _notify_damage_applied() -> void:
	if game == null:
		return
	var effects: Node = game.effect_manager
	if effects != null and is_instance_valid(effects) and effects.has_method("on_damage_applied"):
		effects.on_damage_applied()

## The facade owns the catch cinematic and emits `caught` from _on_caught() (systems spec §4);
## a facade without that hook still gets the bare signal.
func _announce_caught() -> void:
	if game == null:
		return
	# The pursuit is over either way: the panel is told to stand down before the catch cinematic.
	_emit_alert(ALERT_CLEAR, 0.0)
	if game.has_method("_on_caught"):
		game._on_caught()
	else:
		game.caught.emit()
