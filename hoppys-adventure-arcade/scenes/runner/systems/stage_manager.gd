extends Node
## The run-phase state machine: run -> turn -> boss -> stage_clear -> run (contract §11.1,
## systems spec §10.1). It owns `phase`, the stage counters and `run_clock`, and it is the only
## node that drives the TurnRig, the camera swing and the boss encounter.
##
## `state` (ready/running/caught/finished) stays the facade's; `phase` is orthogonal to it. A catch
## aborts whatever phase is live back to `idle`.
##
## Boss fallback: the encounter lives at World/TurnRig/BossArena and is reached only through
## has_method guards (start / tick / abort / finished). When the arena is a bare placeholder — or
## missing entirely — the `boss` phase ends on the tick it starts, `boss_retreated` is skipped and
## the stage still clears, so the loop keeps running before the boss workstream lands.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const StageDefs = preload("res://scenes/runner/data/stage_defs.gd")

## Contract §11.1 phases.
const PHASE_IDLE: StringName = &"idle"
const PHASE_RUN: StringName = &"run"
const PHASE_TURN: StringName = &"turn"
const PHASE_BOSS: StringName = &"boss"
const PHASE_STAGE_CLEAR: StringName = &"stage_clear"

## Mixed into the run seed so the turn directions and the boss's lane rolls are reproducible but
## never in step with the spawner's stream.
const STAGE_SEED_MIX := 0x5F356495
## Contract §11.10 fallbacks, used only when no config has been supplied yet.
const DEFAULT_TURN_SECONDS := 2.5
const DEFAULT_STAGE_DRAIN_DISTANCE := 120.0
const DEFAULT_STAGE_DRAIN_TIMEOUT := 6.0
const DEFAULT_STAGE_CLEAR_LINE_Z := 8.0
const DEFAULT_STAGE_CLEAR_SECONDS := 3.0
const DEFAULT_STAGE_CLEAR_BONUS_BASE := 400
const DEFAULT_STAGE_CLEAR_BONUS_PER_STAGE := 150

var game: RunnerGame
var config: RunConfig

# Read-only outputs, mirrored onto the facade every tick (contract §11.4).
var phase: StringName = PHASE_IDLE
## 1-based and never reset between stages; 0 before begin().
var stage_index := 0
## The display name of this stage's boss, as `stage_started` carries it.
var stage_name: StringName = &""
var stage_distance := 0.0
var stage_distance_target := 0.0
## RUN-phase seconds only: frozen through turn, boss and stage_clear (contract §11.1).
var run_clock := 0.0

# Result counters (contract §11.4). They are tallied from the facade signals, so they survive the
# boss encounter being freed and are correct whether or not an encounter is mounted at all.
var stages_cleared := 0
var turns_taken := 0
var bosses_defeated := 0
var bosses_escaped := 0
var tools_used := 0
var boss_damage_dealt := 0

var stage_rng := RandomNumberGenerator.new()

## Seconds inside the current phase. In `run` it only starts once the distance target is reached,
## so it measures the drain window and nothing else.
var _phase_timer := 0.0
## -1 left, +1 right; 0 outside a turn.
var _turn_direction := 0
## True between a successful boss_encounter.start() and the end of the fight.
var _boss_active := false
## True once the spawner has been told to stop placing for this stage.
var _draining := false

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	_connect(runner)
	reset(0)

## The counters follow the facade signals rather than the encounter, so a boss that is freed after
## its outro still leaves its tally in the run result.
func _connect(runner: RunnerGame) -> void:
	if not runner.caught.is_connected(_on_caught):
		runner.caught.connect(_on_caught)
	if not runner.boss_defeated.is_connected(_on_boss_defeated):
		runner.boss_defeated.connect(_on_boss_defeated)
	if not runner.boss_retreated.is_connected(_on_boss_retreated):
		runner.boss_retreated.connect(_on_boss_retreated)
	if not runner.tool_collected.is_connected(_on_tool_collected):
		runner.tool_collected.connect(_on_tool_collected)

## Called from RunnerGame.start_run() alongside the other system resets; begin() follows once every
## system is back at zero.
func reset(run_seed: int) -> void:
	stage_rng.seed = run_seed ^ STAGE_SEED_MIX
	stage_index = 0
	stage_name = &""
	stage_distance = 0.0
	stage_distance_target = 0.0
	run_clock = 0.0
	stages_cleared = 0
	turns_taken = 0
	bosses_defeated = 0
	bosses_escaped = 0
	tools_used = 0
	boss_damage_dealt = 0
	_phase_timer = 0.0
	_turn_direction = 0
	_draining = false
	_abort_boss()
	_apply_turn_reset()
	_set_boss_arena(false)
	_set_phase(PHASE_IDLE)
	_publish()

## Enter stage 1. RunnerGame calls this after every system reset, so the first stage_started lands
## with the run already live.
func begin() -> void:
	stage_index = 1
	_enter_run()

## Contract §11.4: index, name, phase, distance, target, speed_bonus, difficulty_floor.
func get_stage_info() -> Dictionary:
	return {
		"index": stage_index,
		"name": stage_name,
		"phase": phase,
		"distance": stage_distance,
		"target": stage_distance_target,
		"speed_bonus": StageDefs.speed_bonus(stage_index, config),
		"difficulty_floor": StageDefs.difficulty_floor(stage_index, config)
	}

func _physics_process(delta: float) -> void:
	if game == null or config == null:
		return
	# The facade keeps processing while paused; this machine must not.
	if game.paused or game.state != &"running":
		return
	match phase:
		PHASE_RUN:
			_tick_run(delta)
		PHASE_TURN:
			_tick_turn(delta)
		PHASE_BOSS:
			_tick_boss(delta)
		PHASE_STAGE_CLEAR:
			_tick_stage_clear(delta)
	_publish()

# --- phases ---

## Distance accrues at the authoritative speed; the spawner is switched off a drain's worth of
## metres early so the corridor is empty by the time the turn starts.
func _tick_run(delta: float) -> void:
	run_clock += delta
	stage_distance += float(game.speed) * delta
	stage_distance_target = StageDefs.distance_target(stage_index, config)
	if not _draining and stage_distance >= stage_distance_target - _drain_distance():
		_draining = true
		_set_spawning(false)
	if stage_distance < stage_distance_target:
		return
	# Past the target the drain window opens: wait for the last blocking hazard to pass the clear
	# line, but never longer than stage_drain_timeout.
	_phase_timer += delta
	if _phase_timer >= _drain_timeout():
		_clear_blocking_hazards()
		_enter_turn()
		return
	if not _has_blocking_hazard_ahead():
		_enter_turn()

func _tick_turn(delta: float) -> void:
	_phase_timer += delta
	var seconds := _turn_seconds()
	var progress := 1.0 if seconds <= 0.0 else clampf(_phase_timer / seconds, 0.0, 1.0)
	_apply_turn(progress)
	if progress < 1.0:
		return
	turns_taken += 1
	_apply_turn_reset()
	game.turn_finished.emit()
	_enter_boss()

func _tick_boss(delta: float) -> void:
	var arena := _boss_encounter()
	if not _boss_active or arena == null:
		_enter_stage_clear()
		return
	if arena.has_method("tick"):
		arena.tick(delta)
	if _boss_finished(arena):
		_enter_stage_clear()

func _tick_stage_clear(delta: float) -> void:
	_phase_timer += delta
	if _phase_timer < _stage_clear_seconds():
		return
	stage_index += 1
	_enter_run()

# --- transitions ---

func _enter_run() -> void:
	_phase_timer = 0.0
	_draining = false
	stage_distance = 0.0
	stage_distance_target = StageDefs.distance_target(stage_index, config)
	stage_name = StageDefs.boss_name(stage_index)
	# Mirrors first: phase_changed listeners read stage_index and the target off the facade, so they
	# have to be the new stage's before the signal goes out.
	_publish()
	_set_phase(PHASE_RUN)
	var controller := game.speed_controller
	if controller != null and is_instance_valid(controller):
		if controller.has_method("set_stage_bonus"):
			controller.set_stage_bonus(StageDefs.speed_bonus(stage_index, config))
		if controller.has_method("set_difficulty_floor"):
			controller.set_difficulty_floor(StageDefs.difficulty_floor(stage_index, config))
	_set_spawning(true)
	game.stage_started.emit(stage_index, stage_name, _stage_base_speed())

func _enter_turn() -> void:
	_phase_timer = 0.0
	_turn_direction = stage_rng.randi_range(0, 1) * 2 - 1
	_publish()
	_set_phase(PHASE_TURN)
	_apply_turn(0.0)
	game.turn_started.emit(_turn_direction, _turn_seconds())

## The boss phase is driven entirely through has_method guards. Without a real encounter it ends on
## the tick it starts: no boss_spawned, no boss_retreated, and the stage clears anyway.
func _enter_boss() -> void:
	_phase_timer = 0.0
	_boss_active = false
	_publish()
	_set_phase(PHASE_BOSS)
	_set_boss_arena(true)
	var arena := _boss_encounter()
	if arena != null and arena.has_method("start"):
		arena.start(stage_index)
		_boss_active = not _boss_finished(arena)
	if not _boss_active:
		_enter_stage_clear()

func _enter_stage_clear() -> void:
	_phase_timer = 0.0
	_boss_active = false
	_set_boss_arena(false)
	_publish()
	_set_phase(PHASE_STAGE_CLEAR)
	stages_cleared += 1
	var bonus := _stage_clear_bonus()
	var score: Node = game.score_manager
	if bonus != 0 and score != null and is_instance_valid(score) and score.has_method("add_bonus"):
		score.add_bonus(bonus, &"stage_clear")
	game.stage_cleared.emit(stage_index, bonus)

## A catch aborts any phase back to idle: the fight is dropped without bonuses and the rig unbends.
func _on_caught() -> void:
	if phase == PHASE_IDLE:
		return
	_phase_timer = 0.0
	_draining = false
	_abort_boss()
	_apply_turn_reset()
	_set_boss_arena(false)
	_set_phase(PHASE_IDLE)
	_publish()

func _on_boss_defeated(_kind: StringName, _bonus: int) -> void:
	bosses_defeated += 1

func _on_boss_retreated(_kind: StringName, _bonus: int) -> void:
	bosses_escaped += 1

func _on_tool_collected(_kind: StringName, damage: int) -> void:
	tools_used += 1
	boss_damage_dealt += maxi(damage, 0)

# --- collaborators ---

func _set_phase(value: StringName) -> void:
	if phase == value:
		return
	phase = value
	if game != null:
		game.phase = phase
		game.phase_changed.emit(phase)
	_forward_corridor_phase()

## The frontend corridor hears about phases and the arena through optional hooks (contract §11.9).
func _forward_corridor_phase() -> void:
	var corridor := _corridor()
	if corridor != null and corridor.has_method("set_phase"):
		corridor.set_phase(phase)

func _set_boss_arena(active: bool) -> void:
	var corridor := _corridor()
	if corridor != null and corridor.has_method("set_boss_arena"):
		corridor.set_boss_arena(active)

func _corridor() -> Node:
	if game == null:
		return null
	var rig: Node = game.turn_rig
	if rig == null or not is_instance_valid(rig) or not (&"corridor" in rig):
		return null
	var corridor := rig.get(&"corridor") as Node
	if corridor == null or not is_instance_valid(corridor):
		return null
	return corridor

func _apply_turn(progress: float) -> void:
	var rig: Node = game.turn_rig
	if rig != null and is_instance_valid(rig) and rig.has_method("set_turn"):
		rig.set_turn(progress, _turn_direction)
	var camera: Node = game.camera_rig
	if camera != null and is_instance_valid(camera) and camera.has_method("set_turn"):
		camera.set_turn(progress, _turn_direction)

## Both rigs back to square. The camera swing is a sine over the bend, so p = 1 and p = 0 already
## agree; this is what makes that explicit on every exit path, including a catch mid-turn.
func _apply_turn_reset() -> void:
	_turn_direction = 0
	if game == null:
		return
	var rig: Node = game.turn_rig
	if rig != null and is_instance_valid(rig) and rig.has_method("set_turn"):
		rig.set_turn(0.0, 0)
	var camera: Node = game.camera_rig
	if camera != null and is_instance_valid(camera) and camera.has_method("set_turn"):
		camera.set_turn(0.0, 0)

func _set_spawning(on: bool) -> void:
	if game == null:
		return
	var spawner: Node = game.spawner
	if spawner != null and is_instance_valid(spawner) and spawner.has_method("set_spawning"):
		spawner.set_spawning(on)

func _boss_encounter() -> Node:
	if game == null:
		return null
	var arena: Node = game.boss_encounter
	if arena == null or not is_instance_valid(arena):
		return null
	return arena

## `finished` is a plain bool on the encounter; an arena that does not expose one is treated as
## finished so a half-built boss can never stall the loop.
func _boss_finished(arena: Node) -> bool:
	if arena == null or not is_instance_valid(arena) or not (&"finished" in arena):
		return true
	return bool(arena.get(&"finished"))

func _abort_boss() -> void:
	_boss_active = false
	var arena := _boss_encounter()
	if arena != null and arena.has_method("abort"):
		arena.abort()

# --- drain ---

## A blocking hazard still short of the clear line holds the stage open.
func _has_blocking_hazard_ahead() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var line := _stage_clear_line_z()
	for node in tree.get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		if not hazard.has_method("is_blocking") or not hazard.is_blocking():
			continue
		if game.track_z(hazard) < line:
			return true
	return false

## The drain timeout expired: take the stragglers out silently. clear() drops them from
## runner_hazards, so they are neither dodged nor scored.
func _clear_blocking_hazards() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var line := _stage_clear_line_z()
	for node in tree.get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		if not hazard.has_method("is_blocking") or not hazard.is_blocking():
			continue
		if game.track_z(hazard) >= line:
			continue
		if hazard.has_method("clear"):
			hazard.clear()

# --- mirrors and tuning ---

func _publish() -> void:
	if game == null:
		return
	game.phase = phase
	game.stage_index = stage_index
	game.stage_name = stage_name
	game.stage_distance = stage_distance
	game.stage_distance_target = stage_distance_target
	game.run_clock = run_clock

## The stage's base speed, as stage_started reports it (systems spec §10.1).
func _stage_base_speed() -> float:
	var controller: Node = game.speed_controller
	if controller != null and is_instance_valid(controller) and controller.has_method("base_for_stage"):
		return float(controller.base_for_stage())
	var base := float(config.base_speed) if config != null else 0.0
	return base + StageDefs.speed_bonus(stage_index, config)

func _stage_clear_bonus() -> int:
	var base := _int_config(&"stage_clear_bonus_base", DEFAULT_STAGE_CLEAR_BONUS_BASE)
	var step := _int_config(&"stage_clear_bonus_per_stage", DEFAULT_STAGE_CLEAR_BONUS_PER_STAGE)
	return maxi(base + step * (StageDefs.normalize_index(stage_index) - 1), 0)

func _turn_seconds() -> float:
	return _float_config(&"turn_seconds", DEFAULT_TURN_SECONDS)

func _drain_distance() -> float:
	return maxf(_float_config(&"stage_drain_distance", DEFAULT_STAGE_DRAIN_DISTANCE), 0.0)

func _drain_timeout() -> float:
	return maxf(_float_config(&"stage_drain_timeout", DEFAULT_STAGE_DRAIN_TIMEOUT), 0.0)

func _stage_clear_line_z() -> float:
	return _float_config(&"stage_clear_line_z", DEFAULT_STAGE_CLEAR_LINE_Z)

func _stage_clear_seconds() -> float:
	return maxf(_float_config(&"stage_clear_seconds", DEFAULT_STAGE_CLEAR_SECONDS), 0.0)

func _float_config(property: StringName, fallback: float) -> float:
	if config == null or not (property in config):
		return fallback
	var value: Variant = config.get(property)
	if value is int or value is float:
		return float(value)
	return fallback

func _int_config(property: StringName, fallback: int) -> int:
	if config == null or not (property in config):
		return fallback
	var value: Variant = config.get(property)
	if value is int or value is float:
		return int(value)
	return fallback
