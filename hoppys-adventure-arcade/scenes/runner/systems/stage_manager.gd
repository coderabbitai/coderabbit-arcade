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
const DEFAULT_TURN_SECONDS := 2.4
const DEFAULT_TURN_WARNING_SECONDS := 3.0
const DEFAULT_STAGE_DRAIN_DISTANCE := 120.0
const DEFAULT_STAGE_DRAIN_TIMEOUT := 6.0
const DEFAULT_STAGE_CLEAR_LINE_Z := 8.0
const DEFAULT_STAGE_CLEAR_SECONDS := 3.0
const DEFAULT_STAGE_CLEAR_BONUS_BASE := 400
const DEFAULT_STAGE_CLEAR_BONUS_PER_STAGE := 150
const DEFAULT_STAGE_BANNER_CLEAR_SECONDS := 3.5

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
## -1 left, +1 right for the turn this seam is about to take, 0 when none is pending. Set when the
## drain window opens and held through the bend, so the direction turn_incoming announced, the one
## turn_started repeats and the one the rigs sweep are always the same (contract §11.4).
var next_turn_direction := 0

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
## The direction of the last bend taken, which outlives the turn so the boss checkpoint can replay
## the same corner on its lead-in (contract §11.13).
var _last_turn_direction := 0
## True between a successful boss_encounter.start() and the end of the fight.
var _boss_active := false
## True once the spawner has been told to stop placing for this stage.
var _draining := false
## True once turn_incoming has gone out for this seam, so the warning fires exactly once.
var _turn_announced := false

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
	_last_turn_direction = 0
	_draining = false
	_turn_announced = false
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

## Contract §11.13: open a run on the turn into the boss a checkpoint was taken at, instead of
## stage 1. RunnerGame calls this in place of begin() once every system is reset and the facade has
## restored its own half of the checkpoint. The bend is the readable lead-in; _enter_boss() then runs
## as normal and takes a fresh checkpoint, so a boss can be retried any number of times.
func begin_at_boss(checkpoint: Dictionary) -> void:
	stage_index = maxi(int(checkpoint.get("stage_index", 1)), 1)
	# Only this path re-seeds: the turn and lane rolls of a replayed stage depend on the stage and
	# the run seed alone, never on how many draws the original run had made before it.
	stage_rng.seed = int(checkpoint.get("seed", 0)) ^ STAGE_SEED_MIX ^ stage_index
	stage_name = StageDefs.boss_name(stage_index)
	stage_distance_target = StageDefs.distance_target(stage_index, config)
	stage_distance = stage_distance_target
	run_clock = maxf(float(checkpoint.get("run_clock", 0.0)), 0.0)
	stages_cleared = int(checkpoint.get("stages_cleared", 0))
	# The snapshot was taken after this stage's bend was counted, and the lead-in counts it again.
	turns_taken = maxi(int(checkpoint.get("turns_taken", 0)) - 1, 0)
	bosses_defeated = int(checkpoint.get("bosses_defeated", 0))
	bosses_escaped = int(checkpoint.get("bosses_escaped", 0))
	tools_used = int(checkpoint.get("tools_used", 0))
	boss_damage_dealt = int(checkpoint.get("boss_damage_dealt", 0))
	var controller := game.speed_controller
	if controller != null and is_instance_valid(controller):
		if controller.has_method("set_stage_bonus"):
			controller.set_stage_bonus(StageDefs.speed_bonus(stage_index, config))
		if controller.has_method("set_difficulty_floor"):
			controller.set_difficulty_floor(StageDefs.difficulty_floor(stage_index, config))
	# The seam is hazard-free, exactly as a drained stage leaves it.
	_set_spawning(false)
	_clear_blocking_hazards()
	_draining = true
	_turn_announced = true
	next_turn_direction = signi(int(checkpoint.get("next_turn_direction", 0)))
	if next_turn_direction == 0:
		next_turn_direction = stage_rng.randi_range(0, 1) * 2 - 1
	_publish()
	# The HUDs key the stage label and the stage-clear card off stage_started, and the turn card off
	# turn_incoming; both go out once so they read this stage before the bend. There is no drain to
	# count down, so the turn is announced as already here.
	game.stage_started.emit(stage_index, stage_name, _stage_base_speed())
	game.turn_incoming.emit(next_turn_direction, 0.0)
	_enter_turn()

## The run as it stood on boss entry (contract §11.13): what begin_at_boss() and the facade's
## _restore_checkpoint() need to put a retry back here. HP is deliberately not part of it.
func _snapshot() -> Dictionary:
	var score: Node = game.score_manager
	var has_score := score != null and is_instance_valid(score)
	return {
		"stage_index": stage_index,
		"seed": int(game.seed),
		"score_exact": float(score.get(&"exact")) if has_score and &"exact" in score else float(game.score),
		"score": int(game.score),
		"multiplier": float(game.multiplier),
		"best_multiplier": float(score.get(&"best_multiplier")) if has_score and &"best_multiplier" in score else float(game.multiplier),
		"bonus_total": int(score.get(&"bonus_total")) if has_score and &"bonus_total" in score else 0,
		"run_clock": run_clock,
		"elapsed": float(game.elapsed),
		"distance": float(game.distance),
		"hazards_dodged": int(game.hazards_dodged),
		"hazards_blasted_total": int(game.hazards_blasted_total),
		"stages_cleared": stages_cleared,
		"turns_taken": turns_taken,
		"bosses_defeated": bosses_defeated,
		"bosses_escaped": bosses_escaped,
		"tools_used": tools_used,
		"boss_damage_dealt": boss_damage_dealt,
		"next_turn_direction": _last_turn_direction,
		# The Game Over stats the systems own, so a retry reports the whole run, not just its tail.
		"power_ups": int(_system_stat(game.get(&"effect_manager"), &"power_ups_collected", 0)),
		"hits_taken": int(_system_stat(game.get(&"hit_manager"), &"hits_taken", 0)),
		"recoveries": int(_system_stat(game.get(&"hit_manager"), &"recoveries", 0)),
		"blocked_hits": int(_system_stat(game.get(&"hit_manager"), &"blocked_hits", 0)),
		"max_speed_reached": float(_system_stat(game.get(&"speed_controller"), &"max_speed_reached", float(game.speed))),
		"chunks_spawned": int(_system_stat(game.get(&"spawner"), &"chunks_spawned", 0))
	}

## A numeric property off one of the facade's systems, or `fallback` when the system (or the
## property) is not there.
func _system_stat(node: Variant, property: StringName, fallback: Variant) -> Variant:
	if not (node is Node) or not is_instance_valid(node) or not (property in node):
		return fallback
	var value: Variant = node.get(property)
	return value if value is int or value is float else fallback

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
		# The direction is drawn here rather than at the bend, so the warning below and the
		# turn_started that follows it can never disagree (contract §11.4).
		next_turn_direction = stage_rng.randi_range(0, 1) * 2 - 1
		_publish()
		_set_spawning(false)
	# Announce the corner turn_warning_seconds of travel out. A drain shorter than that window is
	# already inside it when it opens, so the warning lands on the same tick as the drain gate.
	if _draining and not _turn_announced and stage_distance >= stage_distance_target - _turn_warning_distance():
		_announce_turn()
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
	# Mirrors before the signal: a listener on turn_finished must not still read the direction of
	# the bend that just ended off next_turn_direction.
	_publish()
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
	_turn_announced = false
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
	# The stage banner goes up on the stage_started below and covers the lanes, so the corridor is
	# held hazard-free across it (contract §11.1). This has to precede _set_spawning(true): switching
	# placement on tops the corridor up on the same tick, and the window is what those first chunks
	# are measured against. Every stage entry opens one, stage 1 included.
	_begin_clear_road()
	_set_spawning(true)
	game.stage_started.emit(stage_index, stage_name, _stage_base_speed())

## The bend takes the direction the drain drew, so it matches the turn_incoming that announced it.
## A seam that somehow reached the bend without a drain pick (a zero-length stage, a hand-driven
## test) draws one here rather than turning by 0.
func _enter_turn() -> void:
	_phase_timer = 0.0
	if next_turn_direction == 0:
		next_turn_direction = stage_rng.randi_range(0, 1) * 2 - 1
	_turn_direction = next_turn_direction
	_last_turn_direction = _turn_direction
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
	# Snapshot before the fight starts (contract §11.13); a catch leaves it in place for Game Over.
	if game != null and &"boss_checkpoint" in game:
		game.boss_checkpoint = _snapshot()
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
	# The fight is over, so there is nothing left to retry (contract §11.13).
	if game != null and &"boss_checkpoint" in game:
		game.boss_checkpoint = {}
	_publish()
	_set_phase(PHASE_STAGE_CLEAR)
	stages_cleared += 1
	var bonus := _stage_clear_bonus()
	var score: Node = game.score_manager
	if bonus != 0 and score != null and is_instance_valid(score) and score.has_method("add_bonus"):
		score.add_bonus(bonus, &"stage_clear")
	game.stage_cleared.emit(stage_index, bonus)

## A catch aborts any phase back to idle: the fight is dropped without bonuses and the rig unbends.
## The boss checkpoint is deliberately left alone, so a catch mid-fight can offer Retry Boss.
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

## turn_incoming, once per seam (contract §11.4). `seconds` is the estimated time left to the bend
## at the corridor's current speed, which is what a frontend counts an announcement card down on.
func _announce_turn() -> void:
	_turn_announced = true
	var remaining := maxf(stage_distance_target - stage_distance, 0.0)
	var pace := _turn_pace()
	var seconds := remaining / pace if pace > 0.0 else 0.0
	game.turn_incoming.emit(next_turn_direction, seconds)

## The speed the warning is measured at: the corridor's own, floored at the stage's base speed so a
## stalled or hand-driven facade still gets a sane lead rather than an infinite one.
func _turn_pace() -> float:
	var current := float(game.speed) if game != null else 0.0
	return maxf(current, _stage_base_speed())

## Metres of run left when the warning goes out: turn_warning_seconds of travel at that pace.
func _turn_warning_distance() -> float:
	return maxf(_turn_pace() * _turn_warning_seconds(), 0.0)

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

## Both rigs back to square, and no turn pending any more. The camera swing profile is zero at both
## ends of the bend, so p = 1 and p = 0 already agree; this is what makes that explicit on every
## exit path, including a catch mid-turn.
func _apply_turn_reset() -> void:
	_turn_direction = 0
	next_turn_direction = 0
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

## Ask the spawner for a hazard-free run-in the banner can sit over (contract §11.1). Defensive like
## every other collaborator call: a spawner stub without the method simply keeps the v1 behaviour.
func _begin_clear_road() -> void:
	if game == null:
		return
	var spawner: Node = game.spawner
	if spawner == null or not is_instance_valid(spawner) or not spawner.has_method("begin_clear_road"):
		return
	spawner.begin_clear_road(_banner_clear_seconds())

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
	game.next_turn_direction = next_turn_direction

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

func _turn_warning_seconds() -> float:
	return maxf(_float_config(&"turn_warning_seconds", DEFAULT_TURN_WARNING_SECONDS), 0.0)

func _drain_distance() -> float:
	return maxf(_float_config(&"stage_drain_distance", DEFAULT_STAGE_DRAIN_DISTANCE), 0.0)

func _drain_timeout() -> float:
	return maxf(_float_config(&"stage_drain_timeout", DEFAULT_STAGE_DRAIN_TIMEOUT), 0.0)

func _stage_clear_line_z() -> float:
	return _float_config(&"stage_clear_line_z", DEFAULT_STAGE_CLEAR_LINE_Z)

func _stage_clear_seconds() -> float:
	return maxf(_float_config(&"stage_clear_seconds", DEFAULT_STAGE_CLEAR_SECONDS), 0.0)

func _banner_clear_seconds() -> float:
	return maxf(_float_config(&"stage_banner_clear_seconds", DEFAULT_STAGE_BANNER_CLEAR_SECONDS), 0.0)

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
