extends Node3D
## The Endless Runner facade (contract §3 and §4). Every frontend scene talks to this node and
## nothing else: signals out, the methods in §4.3 in.
## PR 1 scaffold: signals, state, mounting and the session/pause facade. The run simulation, the
## caught sequence and _finish_run land in PR 2.

const RunnerLeaderboard = preload("res://scenes/runner/systems/runner_leaderboard.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"

## Contract §3 MOUNT points: mount node path -> optional frontend scenes. Each is instantiated only
## if it exists, and receives bind(self) before run_started is emitted.
const FRONTEND_MOUNTS := {
	"World/Environment": ["res://scenes/runner/environment/corridor.tscn"],
	"HUD": ["res://scenes/runner/ui/runner_hud.tscn"],
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

@export var config: RunConfig = preload(CONFIG_PATH)
## Tests instantiate the scene with autostart off and call start_run() themselves.
@export var autostart := true

# Read-only properties (contract §4.2). Treat these as outputs; drive the run through the methods.
var state: StringName = &"ready"
var paused := false
var seed := 0
var run_id := ""
## Unpaused running seconds.
var elapsed := 0.0
## Metres travelled.
var distance := 0.0
var speed := 0.0
var normalized_speed := 0.0
var difficulty := 0.0
var hp := 0
var score := 0
var multiplier := 1.0
## Seeded per run; the frontend may use it for deterministic cosmetics.
var cosmetic_rng := RandomNumberGenerator.new()

@onready var systems: Node = $Systems
@onready var speed_controller: Node = $Systems/SpeedController
@onready var hit_manager: Node = $Systems/HitManager
@onready var score_manager: Node = $Systems/ScoreManager
@onready var effect_manager: Node = $Systems/EffectManager
@onready var spawner: Node = $Systems/Spawner
@onready var autopilot: Node = $Systems/Autopilot
@onready var world: Node3D = $World
@onready var chunks: Node3D = $World/Chunks
@onready var graybox_environment: Node3D = $World/GrayboxEnvironment
@onready var environment_mount: Node3D = $World/Environment
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = load(CONFIG_PATH) as RunConfig
	hp = int(config.max_hp)
	speed = float(config.base_speed)
	for node in [speed_controller, hit_manager, score_manager, effect_manager, spawner, autopilot,
			player, pursuer, camera_rig, debug_overlay]:
		if node != null and node.has_method("setup"):
			node.setup(self)
	_mount_frontend()
	if autostart:
		start_run(0)

## Reset every system, place the first chunks and go live. seed 0 picks a random seed.
func start_run(run_seed := 0) -> void:
	seed = run_seed if run_seed != 0 else randi()
	run_id = "%d-%d" % [Time.get_unix_time_from_system(), seed]
	cosmetic_rng.seed = seed
	_result = {}
	_finished = false
	elapsed = 0.0
	distance = 0.0
	difficulty = 0.0
	score = 0
	multiplier = 1.0
	speed = float(config.base_speed)
	normalized_speed = 0.0
	hp = int(config.max_hp)
	for node in [speed_controller, hit_manager, score_manager, effect_manager, autopilot,
			player, pursuer, camera_rig]:
		if node != null and node.has_method("reset"):
			node.reset()
	if spawner != null and spawner.has_method("reset"):
		spawner.reset(seed)
	if player != null and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)
	_set_state(&"running")
	run_started.emit(seed)
	health_changed.emit(hp, int(config.max_hp))
	score_changed.emit(score, multiplier)
	speed_changed.emit(speed, normalized_speed)

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
	resume()
	AppRouter.go("runner_game")

func go_to_menu() -> void:
	resume()
	AppRouter.go("runner")

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
	if RunnerLeaderboard.rename(run_id, clean) != OK:
		return false
	_result["player_name"] = clean
	var entries := RunnerLeaderboard.load_entries()
	leaderboard_saved.emit(entries, int(_result.get("rank", 0)))
	return true

func get_leaderboard() -> Array[Dictionary]:
	return RunnerLeaderboard.load_entries()

## Empty until the run is finished.
func get_result() -> Dictionary:
	return _result.duplicate(true)

## kind -> {remaining, total} snapshot for HUD polling.
func get_active_effects() -> Dictionary:
	if effect_manager != null and effect_manager.has_method("get_active_effects"):
		return effect_manager.get_active_effects()
	return {}

## Tests and the F7 debug key drive the bot through here. The bot owns the player while it is on,
## so manual input is disabled for as long as it runs and comes back when it is switched off.
func set_autopilot(enabled: bool) -> void:
	if autopilot != null and autopilot.has_method("set_enabled"):
		autopilot.set_enabled(enabled)
	if player != null and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(not enabled and state == &"running")

# --- internals ---

func _set_state(value: StringName) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)

## Second hit while pursued: lock controls and play the catch cinematic.
func _on_caught() -> void:
	pass # PR 2: state caught, stop the world, shake, pursuer.catch(), emit caught.

## Build the result, write the leaderboard once and emit run_finished exactly once per run.
func _finish_run(_outcome: StringName) -> void:
	if _finished:
		return
	_finished = true
	# PR 2: build `result`, RunnerLeaderboard.submit, leaderboard_saved, state finished, run_finished.

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
			if instance.has_method("bind"):
				instance.bind(self)
			# A real corridor replaces the backend graybox lighting and grid (contract §3).
			if mount == environment_mount and graybox_environment != null:
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
