extends Node
## SAFE / PURSUED / DEAD state machine (systems spec §4).
## PR 1 scaffold: state, counters and the public API; the resolution order lands in PR 2.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")

enum HitState { SAFE, PURSUED, DEAD }

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

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

func reset() -> void:
	state = HitState.SAFE
	hp = int(config.max_hp) if config != null else 0
	iframe_remaining = 0.0
	recovery_remaining = 0.0
	recovery_total = float(config.recovery_seconds) if config != null else 0.0
	shield = false
	invuln_sources = {}
	consumed_ids = {}
	hits_taken = 0
	blocked_hits = 0
	recoveries = 0

## Resolve a hazard overlap synchronously. Returns ignored / blocked_invuln / blocked_shield / damaged.
func report_hit(_hazard: Node) -> StringName:
	return &"ignored" # PR 2: the five-step resolution order from systems spec §4.

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

func is_invulnerable() -> bool:
	return not invuln_sources.is_empty()

func is_pursued() -> bool:
	return state == HitState.PURSUED

func _physics_process(_delta: float) -> void:
	pass # PR 2: tick i-frames and the recovery timer, emit pursuit_progress.
