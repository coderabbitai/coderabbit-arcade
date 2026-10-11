extends Node
## The run-phase state machine: [intro ->] run -> (drain) -> boss -> stage_clear -> run (contract
## §11.1, systems spec §10.1). It owns `phase`, the stage counters and `run_clock`, and it is the
## only node that drives the boss encounter and the camera's boss and run-intro shots. The corridor
## never turns: the drain at the end of `run` empties it and the boss phase follows on the same tick.
##
## The run intro (contract 2.7 §11.15) opens a run: the full one in front of stage 1 on a fresh run,
## the short one on a retry, and the short one in front of the boss on a checkpoint retry. It holds
## the player through the same cinematic hold the boss cinematics use until its last (GO) beat.
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
## Only for the kind of the boss a checkpoint is taken in front of (contract §11.13 bosses_met);
## boss_defs.gd preloads no scene script, so there is no cycle.
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")

## Contract §11.1 phases.
const PHASE_IDLE: StringName = &"idle"
const PHASE_INTRO: StringName = &"intro"
const PHASE_RUN: StringName = &"run"
const PHASE_BOSS: StringName = &"boss"
const PHASE_STAGE_CLEAR: StringName = &"stage_clear"
## Contract 2.7 §11.15 run intro modes; `run_intro_mode` is &"" outside an intro.
const INTRO_FULL: StringName = &"full"
const INTRO_SHORT: StringName = &"short"

## Mixed into the run seed so the boss's lane rolls are reproducible but never in step with the
## spawner's stream.
const STAGE_SEED_MIX := 0x5F356495
## Contract §11.10 fallbacks, used only when no config has been supplied yet.
const DEFAULT_STAGE_DRAIN_DISTANCE := 120.0
const DEFAULT_STAGE_DRAIN_TIMEOUT := 6.0
const DEFAULT_STAGE_CLEAR_LINE_Z := 8.0
const DEFAULT_STAGE_CLEAR_SECONDS := 3.0
const DEFAULT_STAGE_CLEAR_BONUS_BASE := 400
const DEFAULT_STAGE_CLEAR_BONUS_PER_STAGE := 150
const DEFAULT_STAGE_BANNER_CLEAR_SECONDS := 3.5
const DEFAULT_BOSS_CINEMATIC_SPEED_SCALE := 0.25
const DEFAULT_BOSS_Z := -14.0
const DEFAULT_RUN_INTRO_FULL_SECONDS := 6.0
const DEFAULT_RUN_INTRO_SHORT_SECONDS := 2.2
const DEFAULT_RUN_INTRO_SKIP_AFTER := 0.3
const DEFAULT_RUN_INTRO_SKIP_TAIL := 0.4
const DEFAULT_RUN_INTRO_FULL_BEATS: Array[String] = ["title", "3", "2", "1", "GO!"]
const DEFAULT_RUN_INTRO_FULL_BEAT_TIMES: Array[float] = [1.0, 3.0, 3.8, 4.6, 5.4]
const DEFAULT_RUN_INTRO_SHORT_BEATS: Array[String] = ["READY", "GO!"]
const DEFAULT_RUN_INTRO_SHORT_BEAT_TIMES: Array[float] = [1.0, 1.6]
## Contract §11.5: the Boss node's hover height, the camera's fallback target with no boss node.
const BOSS_CENTER_Y := 2.6

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
## RUN-phase seconds only: frozen through boss and stage_clear (contract §11.1).
var run_clock := 0.0
## True from boss_cinematic until that cinematic is skipped, ends, is aborted or the run is caught
## (contract 2.6 §11.14), and from run_intro until its GO beat or skip (2.7 §11.15): manual controls
## are off and the corridor eases to boss_cinematic_speed_scale for exactly as long as this holds.
var cinematic_hold := false
## Contract 2.7 §11.15, mirrored onto the facade: the intro playing (&"" outside one) and 0..1 through it.
var run_intro_mode: StringName = &""
var run_intro_progress := 0.0

# Result counters (contract §11.4). They are tallied from the facade signals, so they survive the
# boss encounter being freed and are correct whether or not an encounter is mounted at all.
var stages_cleared := 0
var bosses_defeated := 0
var bosses_escaped := 0
var tools_used := 0
var boss_damage_dealt := 0

var stage_rng := RandomNumberGenerator.new()

## Seconds inside the current phase. In `run` it only starts once the distance target is reached,
## so it measures the drain window and nothing else.
var _phase_timer := 0.0
## True between a successful boss_encounter.start() and the end of the fight.
var _boss_active := false
## True once the spawner has been told to stop placing for this stage.
var _draining := false
## The intro's own clock and length, in seconds; a skip jumps the clock to the tail.
var _intro_clock := 0.0
var _intro_seconds := 0.0
## Index of the next run_intro_beat to send; beats always go out in order.
var _intro_next_beat := 0
var _intro_labels: Array[String] = []
var _intro_times: Array[float] = []
var _intro_skipped := false
## True when this intro is a checkpoint retry's lead-in, so it hands over to the boss, not to `run`.
var _intro_then_boss := false
## The checkpoint retry's stage_started waits for its intro to end, so the stage banner never sits on
## top of the intro's own cards.
var _intro_stage_pending := false

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
	# Connected before any frontend binds, so the hold and the facade mirrors are already right by the
	# time a HUD or a visual hears the same signal (contract §11.14).
	if not runner.boss_cinematic.is_connected(_on_boss_cinematic):
		runner.boss_cinematic.connect(_on_boss_cinematic)
	if not runner.boss_cinematic_skipped.is_connected(_on_boss_cinematic_released):
		runner.boss_cinematic_skipped.connect(_on_boss_cinematic_released)
	if not runner.boss_cinematic_ended.is_connected(_on_boss_cinematic_released):
		runner.boss_cinematic_ended.connect(_on_boss_cinematic_released)

## Called from RunnerGame.start_run() alongside the other system resets; begin() follows once every
## system is back at zero.
func reset(run_seed: int) -> void:
	# A restart mid-intro still owes its run_intro_ended (exactly one per run_intro).
	_end_intro()
	_intro_stage_pending = false
	stage_rng.seed = run_seed ^ STAGE_SEED_MIX
	stage_index = 0
	stage_name = &""
	stage_distance = 0.0
	stage_distance_target = 0.0
	run_clock = 0.0
	stages_cleared = 0
	bosses_defeated = 0
	bosses_escaped = 0
	tools_used = 0
	boss_damage_dealt = 0
	_phase_timer = 0.0
	_draining = false
	# A fresh run also forgets which bosses the last one met (contract §11.14), which abort() alone
	# would leave in place until stage 1's fight.
	_reset_boss()
	_set_cinematic_hold(false)
	_apply_boss_camera_reset()
	_set_boss_arena(false)
	_set_phase(PHASE_IDLE)
	_publish()

## Enter stage 1. RunnerGame calls this after every system reset, so the first stage_started lands
## with the run already live. `intro_mode` (&"full" / &"short") opens the run on that run intro first,
## when run_intro_enabled allows; &"" goes straight to `run`.
func begin(intro_mode: StringName = &"") -> void:
	stage_index = 1
	if _intro_allowed(intro_mode):
		# Mirrors first, so the intro's listeners already read stage 1 off the facade.
		stage_distance_target = StageDefs.distance_target(stage_index, config)
		stage_name = StageDefs.boss_name(stage_index)
		_enter_intro(intro_mode, false)
		return
	_enter_run()

## Contract §11.13: open a run in front of the boss a checkpoint was taken at, instead of stage 1.
## RunnerGame calls this in place of begin() once every system is reset and the facade has restored
## its own half of the checkpoint. With an `intro_mode` the run intro is the lead-in (contract 2.7
## §11.15); _enter_boss() then runs as normal and takes a fresh checkpoint, so a boss can be retried
## any number of times.
func begin_at_boss(checkpoint: Dictionary, intro_mode: StringName = &"") -> void:
	stage_index = maxi(int(checkpoint.get("stage_index", 1)), 1)
	# Only this path re-seeds: the lane rolls of a replayed stage depend on the stage and the run seed
	# alone, never on how many draws the original run had made before it.
	stage_rng.seed = int(checkpoint.get("seed", 0)) ^ STAGE_SEED_MIX ^ stage_index
	stage_name = StageDefs.boss_name(stage_index)
	stage_distance_target = StageDefs.distance_target(stage_index, config)
	stage_distance = stage_distance_target
	run_clock = maxf(float(checkpoint.get("run_clock", 0.0)), 0.0)
	stages_cleared = int(checkpoint.get("stages_cleared", 0))
	bosses_defeated = int(checkpoint.get("bosses_defeated", 0))
	bosses_escaped = int(checkpoint.get("bosses_escaped", 0))
	tools_used = int(checkpoint.get("tools_used", 0))
	boss_damage_dealt = int(checkpoint.get("boss_damage_dealt", 0))
	# Contract §11.14: the bosses the run had met, the retried one included, so its intro is short,
	# and the ones it had beaten, so killing one of those again plays the short defeat.
	var arena := _boss_encounter()
	if arena != null and arena.has_method("mark_met"):
		var met: Variant = checkpoint.get("bosses_met", [])
		arena.mark_met(met if met is Array else [])
	if arena != null and arena.has_method("mark_defeated"):
		var beaten: Variant = checkpoint.get("bosses_defeated_kinds", [])
		arena.mark_defeated(beaten if beaten is Array else [])
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
	_publish()
	if _intro_allowed(intro_mode):
		# stage_started waits for the intro's end (_finish_intro), right before the boss opens.
		_intro_stage_pending = true
		_enter_intro(intro_mode, true)
		return
	# The HUDs key the stage label and the stage-clear card off stage_started, so it goes out once
	# here and they read this stage before the fight opens.
	game.stage_started.emit(stage_index, stage_name, _stage_base_speed())
	_enter_boss()

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
		"bosses_defeated": bosses_defeated,
		"bosses_escaped": bosses_escaped,
		"tools_used": tools_used,
		"boss_damage_dealt": boss_damage_dealt,
		"bosses_met": _bosses_met(),
		"bosses_defeated_kinds": _bosses_defeated_kinds(),
		# The Game Over stats the systems own, so a retry reports the whole run, not just its tail.
		"power_ups": int(_system_stat(game.get(&"effect_manager"), &"power_ups_collected", 0)),
		"hits_taken": int(_system_stat(game.get(&"hit_manager"), &"hits_taken", 0)),
		"recoveries": int(_system_stat(game.get(&"hit_manager"), &"recoveries", 0)),
		"blocked_hits": int(_system_stat(game.get(&"hit_manager"), &"blocked_hits", 0)),
		"max_speed_reached": float(_system_stat(game.get(&"speed_controller"), &"max_speed_reached", float(game.speed))),
		"chunks_spawned": int(_system_stat(game.get(&"spawner"), &"chunks_spawned", 0))
	}

## Contract §11.13/§11.14 `bosses_met`: every boss this run has met, plus the one the snapshot is
## taken in front of, so a retry of this fight counts as a repeat meeting.
func _bosses_met() -> Array[StringName]:
	var kinds: Array[StringName] = []
	var arena := _boss_encounter()
	if arena != null and arena.has_method("met_kinds"):
		kinds.assign(arena.met_kinds())
	var upcoming := BossDefs.boss_kind(stage_index)
	if upcoming != &"" and not kinds.has(upcoming):
		kinds.append(upcoming)
	return kinds

## Contract §11.13/§11.14 `bosses_defeated_kinds`: every boss this run has beaten before this fight.
func _bosses_defeated_kinds() -> Array[StringName]:
	var kinds: Array[StringName] = []
	var arena := _boss_encounter()
	if arena != null and arena.has_method("defeated_kinds"):
		kinds.assign(arena.defeated_kinds())
	return kinds

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
		PHASE_INTRO:
			_tick_intro(delta)
		PHASE_RUN:
			_tick_run(delta)
		PHASE_BOSS:
			_tick_boss(delta)
		PHASE_STAGE_CLEAR:
			_tick_stage_clear(delta)
	_publish()

# --- phases ---

## The intro's clock runs in real time (paused with the run), sends each beat as its time is reached
## and frames the camera on the same tick; the last tick hands over to `run`, or to the boss on a
## checkpoint retry.
func _tick_intro(delta: float) -> void:
	_intro_clock = minf(_intro_clock + maxf(delta, 0.0), _intro_seconds)
	run_intro_progress = _intro_ratio()
	_send_due_beats()
	_apply_intro_camera()
	if _intro_clock >= _intro_seconds:
		_finish_intro()

## Distance accrues at the authoritative speed; the spawner is switched off a drain's worth of
## metres early so the corridor is empty by the time the boss arrives.
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
		_enter_boss()
		return
	if not _has_blocking_hazard_ahead():
		_enter_boss()

func _tick_boss(delta: float) -> void:
	var arena := _boss_encounter()
	if not _boss_active or arena == null:
		_enter_stage_clear()
		return
	if arena.has_method("tick"):
		arena.tick(delta)
	_apply_boss_camera()
	if _boss_finished(arena):
		_enter_stage_clear()

func _tick_stage_clear(delta: float) -> void:
	_phase_timer += delta
	if _phase_timer < _stage_clear_seconds():
		return
	stage_index += 1
	_enter_run()

# --- transitions ---

## Open the run intro: hazard-free, the player held and the corridor eased down until the GO beat.
func _enter_intro(mode: StringName, then_boss: bool) -> void:
	_phase_timer = 0.0
	run_intro_mode = mode
	_intro_seconds = _intro_length(mode)
	_intro_clock = 0.0
	_intro_next_beat = 0
	_intro_skipped = false
	_intro_then_boss = then_boss
	_intro_labels = _intro_beat_labels(mode)
	_intro_times = _intro_beat_times(mode, _intro_labels.size())
	run_intro_progress = 0.0
	_set_spawning(false)
	_publish()
	_set_phase(PHASE_INTRO)
	_set_cinematic_hold(true, true)
	# The first frame is framed on the tick the intro opens; the camera hard-cuts in.
	_apply_intro_camera()
	game.run_intro.emit(mode, _intro_seconds)
	# A beat authored at 0 s goes out with the intro rather than a tick late.
	_send_due_beats()

## The intro has played out (or its skip tail has): close it, then open what it led into.
func _finish_intro() -> void:
	var then_boss := _intro_then_boss
	_end_intro()
	if then_boss:
		if _intro_stage_pending:
			_intro_stage_pending = false
			game.stage_started.emit(stage_index, stage_name, _stage_base_speed())
		_enter_boss()
		return
	_enter_run()

## Close a live intro on every exit path (played out, skipped tail done, a catch, a new run): the hold
## and the camera go back and run_intro_ended goes out exactly once. A no-op when none is live.
func _end_intro() -> void:
	if run_intro_mode == &"":
		return
	run_intro_mode = &""
	run_intro_progress = 0.0
	_intro_clock = 0.0
	_intro_seconds = 0.0
	_intro_next_beat = 0
	_intro_skipped = false
	_intro_then_boss = false
	_set_cinematic_hold(false)
	_apply_intro_camera_reset()
	_publish()
	if game != null:
		game.run_intro_ended.emit()

## Every beat whose time has been reached, in order. The last one is GO, which hands the player back
## before it is announced, so a listener on it already reads live controls.
func _send_due_beats() -> void:
	while run_intro_mode != &"" and _intro_next_beat < _intro_labels.size() \
			and _intro_clock >= minf(_intro_times[_intro_next_beat], _intro_seconds):
		_send_beat(_intro_next_beat)

func _send_beat(index: int) -> void:
	_intro_next_beat = index + 1
	if _intro_next_beat >= _intro_labels.size():
		_set_cinematic_hold(false)
		_publish()
	game.run_intro_beat.emit(index, _intro_labels[index])

## Contract 2.7 §11.15: true once the intro has played run_intro_skip_after seconds, until it is
## skipped or reaches its last run_intro_skip_tail seconds. The facade adds the running/paused gate.
func can_skip_run_intro() -> bool:
	if phase != PHASE_INTRO or run_intro_mode == &"" or _intro_skipped:
		return false
	return _intro_clock >= _intro_skip_after() and _intro_clock < _intro_seconds - _intro_skip_tail()

## Jump to the tail: the player gets control back at once, the beats jumped over are never sent, and
## the GO beat still is, right after run_intro_skipped, so a GO cue plays on every intro.
func skip_run_intro() -> bool:
	if not can_skip_run_intro():
		return false
	_intro_skipped = true
	_intro_clock = maxf(_intro_clock, _intro_seconds - _intro_skip_tail())
	run_intro_progress = _intro_ratio()
	_set_cinematic_hold(false)
	_publish()
	_apply_intro_camera()
	game.run_intro_skipped.emit()
	var last := _intro_labels.size() - 1
	if _intro_next_beat <= last:
		_send_beat(last)
	return true

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
	# The stage banner goes up on the stage_started below and covers the lanes, so the corridor is
	# held hazard-free across it (contract §11.1). This has to precede _set_spawning(true): switching
	# placement on tops the corridor up on the same tick, and the window is what those first chunks
	# are measured against. Every stage entry opens one, stage 1 included.
	_begin_clear_road()
	_set_spawning(true)
	game.stage_started.emit(stage_index, stage_name, _stage_base_speed())

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
	# The intro's first frame is framed on the tick it opens, not one tick late.
	_apply_boss_camera()
	if not _boss_active:
		_enter_stage_clear()

func _enter_stage_clear() -> void:
	_phase_timer = 0.0
	_boss_active = false
	# The encounter always closes its cinematic before it finishes; this only makes the hand-back
	# unconditional.
	_set_cinematic_hold(false)
	_apply_boss_camera_reset()
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

## A catch aborts any phase back to idle: the fight is dropped without bonuses.
## The boss checkpoint is deliberately left alone, so a catch mid-fight can offer Retry Boss.
func _on_caught() -> void:
	if phase == PHASE_IDLE:
		return
	_end_intro()
	_intro_stage_pending = false
	_phase_timer = 0.0
	_draining = false
	_abort_boss()
	_set_cinematic_hold(false)
	_apply_boss_camera_reset()
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

## A boss cinematic opened (contract 2.6 §11.14): hold the player and mirror its clock at once.
func _on_boss_cinematic(_kind: StringName, _mode: StringName, _seconds: float) -> void:
	_set_cinematic_hold(true)
	_publish()

## Skipped or ended: the player gets control back on the spot. A skip still has its tail to play,
## so the camera keeps following the encounter's clock until boss_cinematic_ended.
func _on_boss_cinematic_released(_mode: StringName) -> void:
	_set_cinematic_hold(false)
	_publish()

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

## abort() plus the encounter's run tallies and meetings, for a fresh run (reset()).
func _reset_boss() -> void:
	_boss_active = false
	var arena := _boss_encounter()
	if arena != null and arena.has_method("reset"):
		arena.reset()
	elif arena != null and arena.has_method("abort"):
		arena.abort()

## Contract 2.6 §11.14: while a cinematic holds the player, manual controls are off (the facade owns
## that rule, autopilot included) and the corridor eases to boss_cinematic_speed_scale; letting go
## gives both back. Idempotent, so every exit path can call it. `snap` sets the speed at once instead
## of easing it, for an intro that opens a run, which has no running speed to ease down from.
func _set_cinematic_hold(on: bool, snap := false) -> void:
	if cinematic_hold == on:
		return
	cinematic_hold = on
	if game == null:
		return
	if game.has_method("refresh_player_controls"):
		game.refresh_player_controls()
	var controller: Node = game.speed_controller
	if controller != null and is_instance_valid(controller) and controller.has_method("set_cinematic_scale"):
		var target := _cinematic_speed_scale() if on else 1.0
		if snap:
			controller.set_cinematic_scale(target, 0.0)
		else:
			controller.set_cinematic_scale(target)

## The camera follows the encounter's cinematic clock on every boss tick; outside a cinematic it is
## handed (0, &""), which the shot curve never blends.
func _apply_boss_camera() -> void:
	if game == null:
		return
	var camera: Node = game.camera_rig
	if camera == null or not is_instance_valid(camera) or not camera.has_method("set_boss_cinematic"):
		return
	var arena := _boss_encounter()
	var mode: StringName = _cinematic_mode(arena)
	var progress := float(arena.cinematic_progress()) if mode != &"" and arena.has_method("cinematic_progress") else 0.0
	camera.set_boss_cinematic(progress, mode, _boss_position(arena), _boss_focus_position(arena))

func _apply_boss_camera_reset() -> void:
	if game == null:
		return
	var camera: Node = game.camera_rig
	if camera != null and is_instance_valid(camera) and camera.has_method("set_boss_cinematic"):
		camera.set_boss_cinematic(0.0, &"", Vector3.ZERO)

## The run intro's shot follows its clock, aimed off Hoppy's feet (contract 2.7 §11.15).
func _apply_intro_camera() -> void:
	if game == null or run_intro_mode == &"":
		return
	var camera: Node = game.camera_rig
	if camera == null or not is_instance_valid(camera) or not camera.has_method("set_run_intro"):
		return
	camera.set_run_intro(run_intro_progress, run_intro_mode, _intro_focus())

func _apply_intro_camera_reset() -> void:
	if game == null:
		return
	var camera: Node = game.camera_rig
	if camera != null and is_instance_valid(camera) and camera.has_method("set_run_intro"):
		camera.set_run_intro(0.0, &"", Vector3.ZERO)

## Hoppy's feet, or the lane origin with no player.
func _intro_focus() -> Vector3:
	var player: Node3D = game.player as Node3D if game != null else null
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		return player.global_position
	return Vector3.ZERO

## The cinematic the encounter is playing, &"" with no encounter or none playing.
func _cinematic_mode(arena: Node) -> StringName:
	if arena == null or not is_instance_valid(arena) or not (&"cinematic_mode" in arena):
		return &""
	return StringName(arena.get(&"cinematic_mode"))

## The Boss node's global position, or where contract §11.5 hovers it when there is none.
func _boss_position(arena: Node) -> Vector3:
	if arena != null and is_instance_valid(arena) and &"boss" in arena:
		var node := arena.get(&"boss") as Node3D
		if node != null and is_instance_valid(node) and node.is_inside_tree():
			return node.global_position
	return Vector3(0.0, BOSS_CENTER_Y, _float_config(&"boss_z", DEFAULT_BOSS_Z))

## Contract §11.5: the global point the shot aims at — the Boss mount carrying the encounter's
## cinematic_focus (the visual's rest focus, read at spawn), so a pose can never move the aim.
func _boss_focus_position(arena: Node) -> Vector3:
	var focus := Vector3.ZERO
	if arena != null and is_instance_valid(arena) and &"cinematic_focus" in arena:
		var value: Variant = arena.get(&"cinematic_focus")
		if value is Vector3:
			focus = value
	if arena != null and is_instance_valid(arena) and &"boss" in arena:
		var node := arena.get(&"boss") as Node3D
		if node != null and is_instance_valid(node) and node.is_inside_tree():
			return node.to_global(focus)
	return _boss_position(arena) + focus

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
	game.run_intro_mode = run_intro_mode
	game.run_intro_progress = run_intro_progress
	# Contract 2.6 §11.14 read-only mirrors, straight off the encounter's clock.
	var arena := _boss_encounter()
	var mode := _cinematic_mode(arena)
	game.boss_cinematic_mode = mode
	game.boss_cinematic_progress = float(arena.cinematic_progress()) \
		if mode != &"" and arena.has_method("cinematic_progress") else 0.0
	game.boss_time_factor = float(arena.time_factor()) \
		if mode != &"" and arena.has_method("time_factor") else 1.0

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

## A mode plays only when the config allows intros and it is one of the two known modes.
func _intro_allowed(mode: StringName) -> bool:
	if mode != INTRO_FULL and mode != INTRO_SHORT:
		return false
	if config != null and &"run_intro_enabled" in config and not bool(config.get(&"run_intro_enabled")):
		return false
	return _intro_length(mode) > 0.0

func _intro_length(mode: StringName) -> float:
	if mode == INTRO_FULL:
		return maxf(_float_config(&"run_intro_full_seconds", DEFAULT_RUN_INTRO_FULL_SECONDS), 0.0)
	return maxf(_float_config(&"run_intro_short_seconds", DEFAULT_RUN_INTRO_SHORT_SECONDS), 0.0)

func _intro_ratio() -> float:
	return clampf(_intro_clock / _intro_seconds, 0.0, 1.0) if _intro_seconds > 0.0 else 1.0

func _intro_skip_after() -> float:
	return maxf(_float_config(&"run_intro_skip_after", DEFAULT_RUN_INTRO_SKIP_AFTER), 0.0)

func _intro_skip_tail() -> float:
	return clampf(_float_config(&"run_intro_skip_tail", DEFAULT_RUN_INTRO_SKIP_TAIL), 0.0, _intro_seconds)

func _intro_beat_labels(mode: StringName) -> Array[String]:
	var labels: Array[String] = []
	var key := &"run_intro_full_beats" if mode == INTRO_FULL else &"run_intro_short_beats"
	var value: Variant = config.get(key) if config != null and key in config else null
	if value is PackedStringArray or value is Array:
		for label: Variant in value:
			labels.append(String(label))
	else:
		labels.assign(DEFAULT_RUN_INTRO_FULL_BEATS if mode == INTRO_FULL else DEFAULT_RUN_INTRO_SHORT_BEATS)
	return labels

## One time per label, never decreasing, so the beats always go out in index order; missing times fall
## at the end of the intro.
func _intro_beat_times(mode: StringName, count: int) -> Array[float]:
	var key := &"run_intro_full_beat_times" if mode == INTRO_FULL else &"run_intro_short_beat_times"
	var value: Variant = config.get(key) if config != null and key in config else null
	var source: Array = []
	if value is PackedFloat32Array or value is PackedFloat64Array or value is Array:
		source.assign(Array(value))
	else:
		source.assign(DEFAULT_RUN_INTRO_FULL_BEAT_TIMES if mode == INTRO_FULL else DEFAULT_RUN_INTRO_SHORT_BEAT_TIMES)
	var times: Array[float] = []
	var floor_ := 0.0
	for index in count:
		var at := float(source[index]) if index < source.size() else _intro_length(mode)
		floor_ = maxf(floor_, maxf(at, 0.0))
		times.append(floor_)
	return times

func _cinematic_speed_scale() -> float:
	return clampf(_float_config(&"boss_cinematic_speed_scale", DEFAULT_BOSS_CINEMATIC_SPEED_SCALE), 0.0, 1.0)

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
