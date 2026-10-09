extends Node3D
## The Endless Runner facade (contract §3 and §4). Every frontend scene talks to this node and
## nothing else: signals out, the methods in §4.3 in. It also owns the run clock, the caught
## sequence and the single leaderboard write.

const RunnerLeaderboard = preload("res://scenes/runner/systems/runner_leaderboard.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
## Only for the phase count of the §11.4 boss block; boss_defs.gd preloads no scene script, so this
## is not the cycle boss_encounter.gd has to avoid.
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
## Seconds the corridor takes to decelerate to a stop once the pursuer catches Hoppy.
const CAUGHT_STOP_SECONDS := 0.4
## Camera shake strengths for the three events the backend owns (contract §4.2, §11.4).
const SHAKE_ON_HIT := 0.5
const SHAKE_ON_CAUGHT := 1.0
const SHAKE_ON_TOOL_HIT := 0.35
## A hazard counts as dodged once its origin is this far behind the player (who stands at z = 0).
const DODGE_LINE_Z := 1.0
## Rebuild the dodge bookkeeping once it grows past this many entries.
const DODGE_IDS_LIMIT := 1024
## Contract §11.3: the boss encounter, when one is mounted. Until the boss scene lands this is a
## bare Node3D placeholder, and every call into it is has_method-guarded.
const BOSS_ARENA_PATH := "World/TurnRig/BossArena"

## Contract §3 and §11.3 MOUNT points: mount node path -> optional frontend scenes. Each is
## instantiated only if it exists, and receives bind(self) before run_started is emitted.
const FRONTEND_MOUNTS := {
	"World/TurnRig/Environment": ["res://scenes/runner/environment/corridor.tscn"],
	## 3D fight effects (telegraphs, tracers, damage numbers) live here, inside the arena, so the
	## frontend never has to reach into World for them (contract §11.3, §11.8).
	"World/TurnRig/BossArena": ["res://scenes/runner/boss/boss_fx.tscn"],
	"HUD": [
		"res://scenes/runner/ui/runner_hud.tscn",
		"res://scenes/runner/ui/pursuit_alert.tscn",
		"res://scenes/runner/ui/boss_hud.tscn",
		"res://scenes/runner/ui/stage_banner.tscn",
		"res://scenes/runner/ui/stage_clear.tscn",
		## Contract 2.6 §11.14: the boss cinematic title card / chyron / skip prompt, driven only off
		## boss_cinematic_progress and boss_time_factor.
		"res://scenes/runner/ui/boss_cinematic.tscn",
		## Full-screen post-processing pass (colour grade, grain, vignette, letterbox, speed
		## streaks) on its own layer below the panels; optional like the rest (contract §11.8).
		"res://scenes/runner/ui/post_fx.tscn"
	],
	"Overlays": [
		"res://scenes/runner/ui/pause_menu.tscn",
		"res://scenes/runner/ui/game_over.tscn"
	],
	"Audio": ["res://scenes/runner/audio/runner_audio.tscn"]
}

enum State { READY, RUNNING, CAUGHT, FINISHED }
## State is stored and emitted as a StringName; the enum is the ordering.
const STATE_NAMES := {
	State.READY: &"ready",
	State.RUNNING: &"running",
	State.CAUGHT: &"caught",
	State.FINISHED: &"finished"
}

signal run_started(seed: int)
signal state_changed(state: StringName)
signal health_changed(hp: int, max_hp: int)
signal damage_taken(kind: StringName, hp: int)
signal damage_blocked(kind: StringName, reason: StringName)
signal shield_changed(active: bool)
signal pursuit_started(recovery_seconds: float)
signal pursuit_progress(remaining: float, total: float)
signal pursuit_recovered(reason: StringName)
signal caught
signal run_finished(result: Dictionary)
signal leaderboard_saved(entries: Array, rank: int)
signal score_changed(score: int, multiplier: float)
signal bonus_awarded(points: int, reason: StringName)
signal speed_changed(speed: float, normalized: float)
signal difficulty_changed(difficulty: float)
signal power_up_collected(kind: StringName, duration: float)
signal power_up_expired(kind: StringName)
signal hazard_cleared(hazard: Area3D)
signal hazards_blasted(count: int)
signal player_action(action: StringName)
signal chunk_spawned(chunk: Node3D)
signal paused_changed(paused: bool)

# --- contract §11.4 additions ---
signal phase_changed(phase: StringName)
signal stage_started(index: int, name: StringName, speed: float)
signal stage_cleared(index: int, bonus: int)
signal turn_incoming(direction: int, seconds: float)
signal turn_started(direction: int, seconds: float)
signal turn_finished
signal boss_intro(kind: StringName, name: String, seconds: float)
signal boss_spawned(kind: StringName, hp: int)
signal boss_health_changed(hp: int, max_hp: int)
signal boss_phase_changed(phase: int)
signal boss_attack_telegraph(lane_mask: int, kind: StringName, seconds: float)
signal boss_projectile_fired(projectile: Area3D, lane_mask: int, kind: StringName, speed: float)
## Contract 2.4 §11.4: the full attack behind the boss_attack_telegraph that follows it on the same
## tick (boss/boss_attacks.gd attack dictionary: signature, candidates, shots, impact_mask, ...).
signal boss_attack_planned(attack: Dictionary)
## Contract 2.4 §11.4: a flaky telegraph stopped alternating and settled on `lane_mask`; `seconds`
## is what is left before it fires.
signal boss_attack_committed(lane_mask: int, kind: StringName, seconds: float)
signal boss_defeated(kind: StringName, bonus: int)
signal boss_retreated(kind: StringName, bonus: int)
## Contract 2.6 §11.14: a boss cinematic of `seconds` opens. `mode` is intro_full / intro_short
## (right after boss_intro, before boss_spawned) or defeat_full / defeat_short (right after
## boss_defeated, on the same tick).
signal boss_cinematic(kind: StringName, mode: StringName, seconds: float)
## The player skipped an intro (a defeat is never skippable): it jumps to its last
## boss_cinematic_skip_tail seconds.
signal boss_cinematic_skipped(mode: StringName)
## It is over (played out, skipped tail done, or aborted by a catch / a new run).
signal boss_cinematic_ended(mode: StringName)
signal tool_collected(kind: StringName, damage: int)
signal pursuit_alert(kind: StringName, seconds_to_catch: float)
signal pursuer_distance_changed(normalized: float)

@export var config: RunConfig = preload(CONFIG_PATH)
## Tests instantiate the scene with autostart off and call start_run() themselves.
@export var autostart := true
## Where this session reads and writes the board. Tests point it at a throwaway file so a headless
## run never touches the player's real leaderboard; the game leaves it at the default.
var leaderboard_path := RunnerLeaderboard.DEFAULT_PATH

# Read-only properties (contract §4.2). Treat these as outputs; drive the run through the methods.
var state: StringName = &"ready"
var paused := false
var seed := 0
var run_id := ""
## Unpaused running seconds.
var elapsed := 0.0
## Metres travelled. RunnerGame owns this accumulator; the spawner moves chunks by the same dz but
## must not add to it, or the distance would double-count.
var distance := 0.0
var speed := 0.0
var normalized_speed := 0.0
var difficulty := 0.0
var hp := 0
var score := 0
var multiplier := 1.0
## Blocking hazards that passed the player without landing a hit, for the run result.
var hazards_dodged := 0
## Running total behind the hazards_blasted signal, for the run result.
var hazards_blasted_total := 0
## Seeded per run; the frontend may use it for deterministic cosmetics.
var cosmetic_rng := RandomNumberGenerator.new()

# Read-only v2 properties (contract §11.4). The StageManager writes the stage block every tick and
# the boss block is mirrored off the boss signals, so both survive the encounter being freed.
## idle / run / turn / boss / stage_clear, orthogonal to `state`.
var phase: StringName = &"idle"
## 1-based, never resets between stages; 0 before the first stage starts.
var stage_index := 0
## The display name of this stage's boss.
var stage_name: StringName = &""
var stage_distance := 0.0
var stage_distance_target := 0.0
## RUN-phase seconds only; drives speed and difficulty (contract §11.1).
var run_clock := 0.0
## -1 left, +1 right for the turn this seam is about to take; 0 when none is pending. Set when the
## stage enters its drain window, which is before turn_incoming announces it, and back to 0 once
## the bend is over (contract §11.4).
var next_turn_direction := 0
## The live boss node, or null outside a fight.
var boss: Node3D = null
var boss_kind: StringName = &""
var boss_hp := 0
var boss_max_hp := 0
## 1-based; 0 outside a fight.
var boss_phase := 0
## Contract 2.6 §11.14, mirrored by the StageManager off the encounter's clock: the cinematic
## playing (&"" when none), 0..1 through it, and the factor visuals, effects and HUD multiply into
## their own delta (1 outside a defeat; the engine time scale is never touched).
var boss_cinematic_mode: StringName = &""
var boss_cinematic_progress := 0.0
var boss_time_factor := 1.0

## Boss checkpoint (contract §11.13). The StageManager snapshots the run here on every boss entry
## and empties it when the stage clears, so it is non-empty only while a fight is live, or after a
## catch that landed during one. Game Over offers "Retry Boss" exactly when it is non-empty.
var boss_checkpoint := {}
## True when this run was started from a boss checkpoint rather than from zero.
var checkpoint_retry := false
## The checkpoint retry_boss() hands to the next runner_game instance. Static because the retry is
## a fresh scene through AppRouter, like retry(); start_run() consumes it and empties it at once.
static var pending_boss_checkpoint := {}

@onready var systems: Node = $Systems
@onready var speed_controller: Node = $Systems/SpeedController
@onready var hit_manager: Node = $Systems/HitManager
@onready var score_manager: Node = $Systems/ScoreManager
@onready var effect_manager: Node = $Systems/EffectManager
@onready var spawner: Node = $Systems/Spawner
@onready var stage_manager: Node = $Systems/StageManager
@onready var autopilot: Node = $Systems/Autopilot
@onready var world: Node3D = $World
@onready var chunks: Node3D = $World/Chunks
@onready var turn_rig: Node3D = $World/TurnRig
@onready var graybox_environment: Node3D = $World/TurnRig/GrayboxEnvironment
@onready var environment_mount: Node3D = $World/TurnRig/Environment
## Resolved by path rather than $: the arena is a placeholder until the boss scene lands, and a
## project without it at all must still load (contract §11.3).
@onready var boss_encounter: Node = get_node_or_null(NodePath(BOSS_ARENA_PATH))
@onready var player: CharacterBody3D = $Player
@onready var pursuer: Node3D = $Pursuer
@onready var camera_rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD
@onready var overlays: CanvasLayer = $Overlays
@onready var audio: Node = $Audio
@onready var debug_overlay: CanvasLayer = $DebugOverlay

var _result := {}
var _finished := false
var _hit_stop_active := false
## Whatever Engine.time_scale was when the current hit-stop started (tests run the runner fast).
var _time_scale_before_hit_stop := 1.0
## The catch cinematic: guarded so it only ever runs once, and timed here because RunnerGame is the
## one node that keeps processing while the tree is paused.
var _caught_started := false
var _caught_timer := 0.0
## Hazard instance ids already counted (dodged or hit), so each hazard is scored once.
var _dodged_ids := {}
## The mounted frontend corridor, if one exists.
var _corridor: Node = null
## Set by the first retry / retry_boss / go_to_menu; this instance is on its way out after that.
var _routing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = load(CONFIG_PATH) as RunConfig
	hp = int(config.max_hp)
	speed = float(config.base_speed)
	# The TurnRig and the boss arena are set up before the StageManager, so the machine finds a
	# square rig and a live encounter; the frontend mounts come last, because a corridor is handed
	# to the rig only once it exists.
	for node in [speed_controller, hit_manager, score_manager, effect_manager, spawner, turn_rig,
			boss_encounter, stage_manager, autopilot, player, pursuer, camera_rig, debug_overlay]:
		if node != null and node.has_method("setup"):
			node.setup(self)
	_connect_signals()
	_mount_frontend()
	if autostart:
		start_run(0)

## Reset every system, place the first chunks and go live. seed 0 picks a random seed.
func start_run(run_seed := 0) -> void:
	# A restart asked for from the pause menu (or any caller that skips retry()) must never begin
	# frozen: go through resume() so `paused`, `tree.paused` and paused_changed(false) all agree.
	# It is a no-op when the run was not paused.
	resume()
	# Consumed before anything else, so a checkpoint can never leak into a later run.
	var checkpoint: Dictionary = pending_boss_checkpoint
	pending_boss_checkpoint = {}
	checkpoint_retry = not checkpoint.is_empty()
	boss_checkpoint = {}
	if checkpoint_retry:
		# The same seed keeps the spawner and fight RNG streams on the run the checkpoint came from.
		run_seed = int(checkpoint.get("seed", run_seed))
	seed = run_seed if run_seed != 0 else randi()
	run_id = "%d-%d" % [Time.get_unix_time_from_system(), seed]
	if checkpoint_retry:
		# A fresh run_id (the death already wrote its own entry), unique even within one second.
		run_id += "-boss%d-%d" % [int(checkpoint.get("stage_index", 0)), Time.get_ticks_msec()]
	cosmetic_rng.seed = seed
	_result = {}
	_finished = false
	_caught_started = false
	_caught_timer = 0.0
	_dodged_ids.clear()
	elapsed = 0.0
	distance = 0.0
	difficulty = 0.0
	score = 0
	multiplier = 1.0
	speed = float(config.base_speed)
	normalized_speed = 0.0
	hp = int(config.max_hp)
	hazards_dodged = 0
	hazards_blasted_total = 0
	run_clock = 0.0
	stage_distance = 0.0
	stage_distance_target = 0.0
	next_turn_direction = 0
	_clear_boss_state()
	for node in [speed_controller, hit_manager, score_manager, effect_manager, autopilot,
			player, pursuer, camera_rig, turn_rig]:
		if node != null and node.has_method("reset"):
			node.reset()
	if spawner != null and spawner.has_method("reset"):
		spawner.reset(seed)
	if stage_manager != null and stage_manager.has_method("reset"):
		stage_manager.reset(seed)
	if player != null and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)
	if checkpoint_retry:
		_restore_checkpoint(checkpoint)
	_set_state(&"running")
	run_started.emit(seed)
	health_changed.emit(hp, int(config.max_hp))
	score_changed.emit(score, multiplier)
	speed_changed.emit(speed, normalized_speed)
	# Stage 1 opens only once every system is back at zero and the run is live, so the first
	# stage_started lands after run_started and the spawner fills against a running phase. A boss
	# checkpoint opens on the turn into that stage's boss instead.
	if checkpoint_retry and stage_manager != null and stage_manager.has_method("begin_at_boss"):
		stage_manager.begin_at_boss(checkpoint)
	elif stage_manager != null and stage_manager.has_method("begin"):
		stage_manager.begin()

## Put the facade, the ScoreManager and the systems' Game Over tallies back where the checkpoint
## left them. HP, running power-up effects and the pursuit are not restored: a checkpoint retry
## starts at full health with no effects running, so the live multiplier recomposes from those (1.0)
## while best_multiplier keeps the run's best. The StageManager restores its own block (stage,
## run_clock, tallies) in begin_at_boss().
func _restore_checkpoint(checkpoint: Dictionary) -> void:
	elapsed = float(checkpoint.get("elapsed", 0.0))
	distance = float(checkpoint.get("distance", 0.0))
	hazards_dodged = int(checkpoint.get("hazards_dodged", 0))
	hazards_blasted_total = int(checkpoint.get("hazards_blasted_total", 0))
	run_clock = float(checkpoint.get("run_clock", 0.0))
	var exact := maxf(float(checkpoint.get("score_exact", 0.0)), 0.0)
	if score_manager != null and is_instance_valid(score_manager):
		if &"exact" in score_manager:
			score_manager.set(&"exact", exact)
		if &"score" in score_manager:
			score_manager.set(&"score", floori(exact))
		if &"best_multiplier" in score_manager:
			score_manager.set(&"best_multiplier", maxf(float(checkpoint.get("best_multiplier", 1.0)), 1.0))
		if &"bonus_total" in score_manager:
			score_manager.set(&"bonus_total", int(checkpoint.get("bonus_total", 0)))
	score = _system_int(score_manager, &"score", floori(exact))
	multiplier = _system_float(score_manager, &"multiplier", 1.0)
	# The run's cumulative Game Over stats, so a retry never mixes whole-run and since-retry numbers.
	_restore_stat(effect_manager, &"power_ups_collected", int(checkpoint.get("power_ups", 0)))
	_restore_stat(hit_manager, &"hits_taken", int(checkpoint.get("hits_taken", 0)))
	_restore_stat(hit_manager, &"recoveries", int(checkpoint.get("recoveries", 0)))
	_restore_stat(hit_manager, &"blocked_hits", int(checkpoint.get("blocked_hits", 0)))
	if checkpoint.has("max_speed_reached"):
		_restore_stat(speed_controller, &"max_speed_reached", maxf(float(checkpoint["max_speed_reached"]),
			_system_float(speed_controller, &"max_speed_reached", 0.0)))
	_restore_stat(spawner, &"chunks_spawned", int(checkpoint.get("chunks_spawned", 0)))

func _restore_stat(node: Node, property: StringName, value: Variant) -> void:
	if node != null and is_instance_valid(node) and property in node:
		node.set(property, value)

# --- contract §4.3 ---

func pause() -> void:
	var tree := get_tree()
	if paused or state != &"running" or tree == null:
		return
	paused = true
	tree.paused = true
	paused_changed.emit(true)

func resume() -> void:
	if not paused:
		return
	paused = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	# Re-sync held input so a key held through the pause menu does not fire on unpause.
	if player != null and player.has_method("sync_input_state"):
		player.sync_input_state()
	paused_changed.emit(false)

func toggle_pause() -> void:
	if paused:
		resume()
	else:
		pause()

## Fresh session on the same scene; change_scene_to_file yields a new instance.
func retry() -> void:
	if _route_in_flight():
		return
	resume()
	# A full restart always starts from zero, even after a Retry Boss that never got to route.
	pending_boss_checkpoint = {}
	_take_route("runner_game")

## Contract §11.13: a fresh session that opens on the turn into the boss the checkpoint was taken
## at, with the score, clocks and tallies it held and full HP. Without a checkpoint this is retry().
func retry_boss() -> void:
	if _route_in_flight():
		return
	if boss_checkpoint.is_empty():
		retry()
		return
	resume()
	pending_boss_checkpoint = boss_checkpoint.duplicate(true)
	_take_route("runner_game")

func go_to_menu() -> void:
	if _route_in_flight():
		return
	resume()
	pending_boss_checkpoint = {}
	_take_route("runner")

## The first route asked for wins. AppRouter ignores a go() while its veil is fading, but Game Over
## keeps focus through that fade, so a second press (Esc after Retry Boss, say) must not rewrite
## pending_boss_checkpoint behind the route already taken.
func _route_in_flight() -> bool:
	if _routing:
		return true
	var router := get_node_or_null(^"/root/AppRouter")
	return router != null and bool(router.get(&"busy"))

func _take_route(route: String) -> void:
	_routing = true
	_route(route)

## Every scene change goes through here, so a test can record the route instead of taking it.
func _route(route: String) -> void:
	AppRouter.go(route)

## Brief Engine.time_scale dip, capped by config.hit_stop_max.
func hit_stop(seconds: float) -> void:
	var span := clampf(seconds, 0.0, float(config.hit_stop_max))
	if span <= 0.0 or _hit_stop_active:
		return
	var tree := get_tree()
	if tree == null:
		return
	_hit_stop_active = true
	# Restore the scale we found rather than 1.0: a harness driving the run fast keeps its setting.
	_time_scale_before_hit_stop = Engine.time_scale
	Engine.time_scale = 0.05
	await tree.create_timer(span, true, false, true).timeout
	Engine.time_scale = _time_scale_before_hit_stop
	_hit_stop_active = false

## Rename this run's leaderboard entry. Never adds a second entry.
func submit_name(name: String) -> bool:
	if _result.is_empty() or run_id.is_empty():
		return false
	var clean := RunnerLeaderboard.sanitize_name(name)
	# Only a write that reached disk renames the run: a failed rename leaves the board untouched, so
	# the frontend is told nothing was saved rather than shown a name the board does not carry.
	var error := RunnerLeaderboard.rename(run_id, clean, leaderboard_path)
	if error != OK:
		push_warning("Runner leaderboard: cannot rename this run in %s (error %d)" % [leaderboard_path, error])
		return false
	_result["player_name"] = clean
	var entries := RunnerLeaderboard.load_entries(leaderboard_path)
	leaderboard_saved.emit(entries, int(_result.get("rank", 0)))
	return true

func get_leaderboard() -> Array[Dictionary]:
	return RunnerLeaderboard.load_entries(leaderboard_path)

## Empty until the run is finished.
func get_result() -> Dictionary:
	return _result.duplicate(true)

## kind -> {remaining, total} snapshot for HUD polling.
func get_active_effects() -> Dictionary:
	if effect_manager != null and effect_manager.has_method("get_active_effects"):
		return effect_manager.get_active_effects()
	return {}

## Contract §11.4: index, name, phase, distance, target, speed_bonus, difficulty_floor. Neutral
## values before the first stage opens, so a HUD can read every key without a null check.
func get_stage_info() -> Dictionary:
	if stage_manager != null and is_instance_valid(stage_manager) and stage_manager.has_method("get_stage_info"):
		return stage_manager.get_stage_info()
	return {
		"index": stage_index,
		"name": stage_name,
		"phase": phase,
		"distance": stage_distance,
		"target": stage_distance_target,
		"speed_bonus": 0.0,
		"difficulty_floor": 0.0
	}

## Contract §11.4: kind, name, hp, max_hp, phase, phase_count, accepted_tools, pending_attacks. Outside a fight
## (or before the boss encounter is mounted) every key is present and empty — the same shape the
## encounter's own get_boss_info() returns between fights, so a HUD reading either one agrees.
func get_boss_info() -> Dictionary:
	if boss_encounter != null and is_instance_valid(boss_encounter) and boss_encounter.has_method("get_boss_info"):
		return boss_encounter.get_boss_info()
	# No arena mounted: the mirrored boss block is all there is, and _clear_boss_state() has already
	# emptied it outside the boss phase.
	var info := _empty_boss_info()
	if boss_kind == &"":
		return info
	info["kind"] = boss_kind
	info["name"] = stage_name
	info["hp"] = boss_hp
	info["max_hp"] = boss_max_hp
	info["phase"] = boss_phase
	# Every boss runs the same number of phases, so the mirror can fill this in without an arena.
	info["phase_count"] = BossDefs.PHASE_COUNT
	return info

## The contract §11.4 boss block with every field empty (boss_encounter.gd's empty_info(), built
## here rather than preloaded, because that script already preloads this one).
func _empty_boss_info() -> Dictionary:
	var empty_tools: Array[StringName] = []
	var empty_attacks: Array[Dictionary] = []
	return {
		"kind": &"",
		"name": "",
		"hp": 0,
		"max_hp": 0,
		"phase": 0,
		"phase_count": 0,
		"accepted_tools": empty_tools,
		"pending_attacks": empty_attacks
	}

## Rig-local z for anything on the track (systems spec §10.5). Gameplay never rotates, so this is
## the identity today; it exists so a bent corridor can never skew a z test.
func track_z(node: Node3D) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	if turn_rig == null or not is_instance_valid(turn_rig):
		return node.global_position.z
	return turn_rig.to_local(node.global_position).z

## The rig-local bounds of a hazard-shaped node: its own get_world_aabb() when it has one, else a
## degenerate box at its origin.
func track_aabb(node: Node3D) -> AABB:
	if node == null or not is_instance_valid(node):
		return AABB()
	var bounds := AABB(node.global_position, Vector3.ZERO)
	if node.has_method("get_world_aabb"):
		bounds = node.get_world_aabb()
	if turn_rig == null or not is_instance_valid(turn_rig):
		return bounds
	return turn_rig.global_transform.affine_inverse() * bounds

## A damaging tool landed on the boss. The shake is backend-owned (contract §11.4); the boss
## encounter calls this instead of reaching for the camera itself.
func on_tool_hit() -> void:
	if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.has_method("shake"):
		camera_rig.shake(SHAKE_ON_TOOL_HIT)

## Contract 2.6 §11.14: skip the boss intro playing now. It only takes once the intro has run
## boss_cinematic_skip_after seconds, while running and unpaused, and never during a defeat; returns
## true when it did. Jump and ui_accept reach it through _unhandled_input; the autopilot never calls
## it.
func skip_boss_cinematic() -> bool:
	if not _can_skip_boss_cinematic():
		return false
	return bool(boss_encounter.skip_cinematic())

func _can_skip_boss_cinematic() -> bool:
	if state != &"running" or paused:
		return false
	if boss_encounter == null or not is_instance_valid(boss_encounter):
		return false
	if not boss_encounter.has_method("can_skip_cinematic") or not boss_encounter.has_method("skip_cinematic"):
		return false
	return bool(boss_encounter.can_skip_cinematic())

## Tests and the F7 debug key drive the bot through here. The bot owns the player while it is on,
## so manual input is disabled for as long as it runs and comes back when it is switched off —
## unless a boss cinematic is holding the player (contract §11.14), which hands it back itself.
func set_autopilot(enabled: bool) -> void:
	if autopilot != null and autopilot.has_method("set_enabled"):
		autopilot.set_enabled(enabled)
	_apply_player_controls(not enabled)

## Manual controls are live while the run is, the bot is off and no boss cinematic holds the player
## (contract 2.6 §11.14). The StageManager calls this whenever a cinematic takes or gives back
## control, so the one rule decides every hand-back.
func refresh_player_controls() -> void:
	var bot_on := autopilot != null and is_instance_valid(autopilot) and &"enabled" in autopilot \
		and bool(autopilot.get(&"enabled"))
	_apply_player_controls(not bot_on)

func _apply_player_controls(manual: bool) -> void:
	if player == null or not is_instance_valid(player) or not player.has_method("set_controls_enabled"):
		return
	var held := stage_manager != null and is_instance_valid(stage_manager) \
		and &"cinematic_hold" in stage_manager and bool(stage_manager.get(&"cinematic_hold"))
	player.set_controls_enabled(manual and state == &"running" and not held)

# --- run loop ---

func _physics_process(delta: float) -> void:
	# RunnerGame processes while paused (it owns the pause menu), so the clock is gated by hand.
	if paused:
		return
	if state == &"running":
		elapsed += delta
		distance += speed * delta
		_track_dodges()
	elif state == &"caught":
		distance += speed * delta
		_track_dodges()
		_caught_timer += delta
		if _caught_timer >= float(config.caught_sequence_seconds):
			_finish_run(&"caught")
	_drive_corridor()

## Count every blocking hazard that made it past the player. A hazard that hit is no longer
## blocking, and Auto-Fix removes cleared ones from the group, so neither is counted as a dodge.
## An id is forgotten again while its hazard sits at or ahead of the dodge line, so a hazard that is
## repositioned or reused in front of the player is counted once more the next time it crosses,
## instead of being remembered as dodged forever.
func _track_dodges() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		var id := hazard.get_instance_id()
		if track_z(hazard) <= DODGE_LINE_Z:
			_dodged_ids.erase(id)
			continue
		if _dodged_ids.has(id):
			continue
		_dodged_ids[id] = true
		if hazard.has_method("is_blocking") and hazard.is_blocking():
			hazards_dodged += 1
	if _dodged_ids.size() > DODGE_IDS_LIMIT:
		_prune_dodge_ids()

## Drop ids whose hazard has been freed, so a long run does not grow the dictionary forever.
func _prune_dodge_ids() -> void:
	var kept := {}
	for id in _dodged_ids:
		if is_instance_id_valid(id):
			kept[id] = true
	_dodged_ids = kept

## The frontend corridor scrolls itself from the authoritative speed (contract §5.5).
func _drive_corridor() -> void:
	if _corridor == null or not is_instance_valid(_corridor):
		return
	if _corridor.has_method("set_scroll_speed"):
		_corridor.set_scroll_speed(speed)
	if _corridor.has_method("set_pursuit"):
		_corridor.set_pursuit(_pursuit_amount())

## 0 retreated .. 1 about to catch, mirrored from the pursuer.
func _pursuit_amount() -> float:
	if pursuer != null and is_instance_valid(pursuer) and &"threat" in pursuer:
		return clampf(float(pursuer.get(&"threat")), 0.0, 1.0)
	return 0.0

# --- internals ---

## The facade mirrors the managers' own signals into its read-only properties and forwards the
## player-visual hooks, so no system has to reach into RunnerGame's state.
func _connect_signals() -> void:
	health_changed.connect(_on_health_changed)
	score_changed.connect(_on_score_changed)
	damage_taken.connect(_on_damage_taken)
	shield_changed.connect(_on_shield_changed)
	power_up_collected.connect(_on_power_up_collected)
	power_up_expired.connect(_on_power_up_expired)
	hazards_blasted.connect(_on_hazards_blasted)
	# The HitManager calls _on_caught(); a manager that emits `caught` instead still starts the
	# cinematic, because the sequence is guarded and the signal it emits re-enters as a no-op.
	caught.connect(_on_caught)
	# The v2 boss block mirrors the encounter's own signals, so `boss_hp` and friends keep reading
	# correctly after the encounter frees the boss at the end of its outro.
	phase_changed.connect(_on_phase_changed)
	boss_spawned.connect(_on_boss_spawned)
	boss_health_changed.connect(_on_boss_health_changed)
	boss_phase_changed.connect(_on_boss_phase_changed)

func _on_health_changed(value: int, _max_hp: int) -> void:
	hp = value

func _on_score_changed(value: int, value_multiplier: float) -> void:
	score = value
	multiplier = value_multiplier

func _on_damage_taken(_kind: StringName, _value: int) -> void:
	if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.has_method("shake"):
		camera_rig.shake(SHAKE_ON_HIT)
	if player != null and is_instance_valid(player) and player.has_method("play_hurt"):
		player.play_hurt()

func _on_shield_changed(active: bool) -> void:
	if player != null and is_instance_valid(player) and player.has_method("apply_shield"):
		player.apply_shield(active)

func _on_power_up_collected(kind: StringName, _duration: float) -> void:
	_set_aura(kind, true)

func _on_power_up_expired(kind: StringName) -> void:
	_set_aura(kind, false)

func _set_aura(kind: StringName, on: bool) -> void:
	if player != null and is_instance_valid(player) and player.has_method("apply_aura"):
		player.apply_aura(kind, on)

func _on_hazards_blasted(count: int) -> void:
	hazards_blasted_total += count

## Leaving the boss phase ends the fight as far as the facade is concerned, whatever the encounter
## does with its own nodes afterwards.
func _on_phase_changed(value: StringName) -> void:
	phase = value
	if value != &"boss":
		_clear_boss_state()

## `spawned_hp`, not `hp`: this facade already has an `hp` of its own (the player's), and a
## parameter by that name would read as a write to it two lines down.
func _on_boss_spawned(kind: StringName, spawned_hp: int) -> void:
	boss_kind = kind
	boss_hp = spawned_hp
	boss_max_hp = maxi(boss_max_hp, spawned_hp)
	boss_phase = 1
	boss = _find_boss_node()

func _on_boss_health_changed(value: int, max_value: int) -> void:
	boss_hp = value
	boss_max_hp = max_value

func _on_boss_phase_changed(value: int) -> void:
	boss_phase = value

func _clear_boss_state() -> void:
	boss = null
	boss_kind = &""
	boss_hp = 0
	boss_max_hp = 0
	boss_phase = 0
	boss_cinematic_mode = &""
	boss_cinematic_progress = 0.0
	boss_time_factor = 1.0

## The encounter may expose the boss as a property or as a child named Boss; either is accepted and
## a missing one just leaves `boss` null.
func _find_boss_node() -> Node3D:
	if boss_encounter == null or not is_instance_valid(boss_encounter):
		return null
	if &"boss" in boss_encounter:
		var referenced := boss_encounter.get(&"boss") as Node3D
		if referenced != null and is_instance_valid(referenced):
			return referenced
	return boss_encounter.get_node_or_null(^"Boss") as Node3D

func _set_state(value: StringName) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)

## Second hit while pursued: lock controls and play the catch cinematic. Idempotent.
func _on_caught() -> void:
	if _caught_started or _finished:
		return
	_caught_started = true
	_caught_timer = 0.0
	_set_state(&"caught")
	if autopilot != null and is_instance_valid(autopilot) and autopilot.has_method("set_enabled"):
		autopilot.set_enabled(false)
	if player != null and is_instance_valid(player):
		if player.has_method("set_controls_enabled"):
			player.set_controls_enabled(false)
		if player.has_method("play_dead"):
			player.play_dead()
	if speed_controller != null and is_instance_valid(speed_controller) and speed_controller.has_method("begin_stop"):
		speed_controller.begin_stop(CAUGHT_STOP_SECONDS)
	if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.has_method("shake"):
		camera_rig.shake(SHAKE_ON_CAUGHT)
	if pursuer != null and is_instance_valid(pursuer) and pursuer.has_method("catch"):
		pursuer.catch()
	caught.emit()

## Build the result, write the leaderboard once and emit run_finished exactly once per run.
func _finish_run(outcome: StringName) -> void:
	if _finished:
		return
	_finished = true
	var now := int(Time.get_unix_time_from_system())
	var player_name := RunnerLeaderboard.sanitize_name("")
	var final_score := _system_int(score_manager, &"score", score)
	var result := {
		"run_id": run_id,
		"mode": "runner",
		"outcome": String(outcome),
		"score": final_score,
		"score_exact": _system_float(score_manager, &"exact", float(final_score)),
		"duration": elapsed,
		"distance": distance,
		"hazards_dodged": hazards_dodged,
		"power_ups": _system_int(effect_manager, &"power_ups_collected", 0),
		"hazards_blasted": hazards_blasted_total,
		"hits_taken": _system_int(hit_manager, &"hits_taken", 0),
		"recoveries": _system_int(hit_manager, &"recoveries", 0),
		"blocked_hits": _system_int(hit_manager, &"blocked_hits", 0),
		"seed": seed,
		"max_speed_reached": _system_float(speed_controller, &"max_speed_reached", speed),
		"best_multiplier": _system_float(score_manager, &"best_multiplier", multiplier),
		"chunks_spawned": _system_int(spawner, &"chunks_spawned", 0),
		# Contract §11.4. The StageManager tallies all seven off the facade signals, so they are
		# right whether or not a boss encounter was ever mounted.
		"stages_cleared": _system_int(stage_manager, &"stages_cleared", 0),
		"stage_reached": _system_int(stage_manager, &"stage_index", stage_index),
		"bosses_defeated": _system_int(stage_manager, &"bosses_defeated", 0),
		"bosses_escaped": _system_int(stage_manager, &"bosses_escaped", 0),
		"tools_used": _system_int(stage_manager, &"tools_used", 0),
		"boss_damage_dealt": _system_int(stage_manager, &"boss_damage_dealt", 0),
		"turns_taken": _system_int(stage_manager, &"turns_taken", 0),
		# Contract §11.13: true when this run was started from a boss checkpoint.
		"checkpoint_retry": checkpoint_retry,
		"score_rule_revision": int(config.score_rule_revision),
		"submitted_at": now,
		"rank": 0,
		"qualifies": false,
		"leaderboard_error": OK,
		"player_name": player_name
	}
	# One write per run (contract §4.3): the entry carries only the leaderboard §4.3 fields.
	var submission := RunnerLeaderboard.submit({
		"run_id": run_id,
		"name": player_name,
		"score": final_score,
		"duration": elapsed,
		"seed": seed,
		"submitted_at": now
	}, leaderboard_path)
	# submit() ranks the run against the board it built in memory, so a rank only means the run
	# placed once the write succeeded. leaderboard_error is always present (OK on success) so the
	# frontend can tell "did not place" apart from "could not be saved".
	var error := int(submission.get("error", OK))
	result["leaderboard_error"] = error
	var rank := int(submission.get("rank", 0)) if error == OK else 0
	result["rank"] = rank
	result["qualifies"] = rank > 0
	_result = result
	if error == OK:
		var entries: Array = submission.get("entries", [])
		leaderboard_saved.emit(entries, rank)
	else:
		push_warning("Runner leaderboard: this run was not written to %s (error %d); it keeps rank 0"
			% [leaderboard_path, error])
	_set_state(&"finished")
	run_finished.emit(get_result())

## Read an int off a sibling system without assuming it exists yet.
func _system_int(node: Node, property: StringName, fallback: int) -> int:
	var value: Variant = _system_value(node, property)
	if value is int or value is float:
		return int(value)
	return fallback

func _system_float(node: Node, property: StringName, fallback: float) -> float:
	var value: Variant = _system_value(node, property)
	if value is int or value is float:
		return float(value)
	return fallback

func _system_value(node: Node, property: StringName) -> Variant:
	if node == null or not is_instance_valid(node) or not (property in node):
		return null
	return node.get(property)

## Instantiate every frontend scene that exists and bind it to this facade. A missing or broken
## frontend file must never stop the scene from loading (contract §1 rule 2).
func _mount_frontend() -> void:
	for mount_path in FRONTEND_MOUNTS:
		var mount := get_node_or_null(NodePath(mount_path))
		if mount == null:
			continue
		for path in FRONTEND_MOUNTS[mount_path]:
			var instance := _instantiate_frontend(path)
			if instance == null:
				continue
			mount.add_child(instance)
			# The arena inherits this facade's ALWAYS process mode so the fight keeps ticking through
			# a hit-stop; fight effects must freeze with the pause menu instead, like the HUD mounts.
			if mount == boss_encounter:
				instance.process_mode = Node.PROCESS_MODE_PAUSABLE
			if instance.has_method("bind"):
				instance.bind(self)
			# A real corridor replaces the backend graybox lighting and grid (contract §3), and the
			# TurnRig hands it the bend instead of yawing the graybox itself (contract §11.9).
			if mount == environment_mount:
				_corridor = instance
				if turn_rig != null and is_instance_valid(turn_rig) and turn_rig.has_method("set_corridor"):
					turn_rig.set_corridor(instance)
				if graybox_environment != null:
					graybox_environment.queue_free()
					graybox_environment = null

## Contract §3: only a non-null PackedScene is instantiated; anything else is warned about and the
## mount is skipped (a frontend scene has no backend graybox to fall back to).
func _instantiate_frontend(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Runner frontend scene at %s is not a PackedScene; skipping the mount" % path)
		return null
	var instance := scene.instantiate()
	if instance == null:
		push_warning("Runner frontend scene at %s could not be instantiated; skipping the mount" % path)
	return instance

func _unhandled_input(event: InputEvent) -> void:
	# Contract 2.6 §11.14: jump or confirm skips a boss intro once it may be skipped. The press is
	# consumed here, and the controls the skip hands back re-sync held input, so it never also lands
	# as a jump.
	if (event.is_action_pressed("jump") or event.is_action_pressed("ui_accept")) and _can_skip_boss_cinematic():
		skip_boss_cinematic()
		get_viewport().set_input_as_handled()
		return
	# The backend owns `pause`; it toggles only while running, so Space on a focused Game Over
	# button can never jump and Esc never double-fires with the overlays.
	if not event.is_action_pressed("pause") or state != &"running":
		return
	toggle_pause()
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pause()

func _exit_tree() -> void:
	# Only a hit-stop cut short by the scene change owns Engine.time_scale; anything else set it
	# from outside the runner and keeps it.
	if _hit_stop_active:
		Engine.time_scale = _time_scale_before_hit_stop
		_hit_stop_active = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false
