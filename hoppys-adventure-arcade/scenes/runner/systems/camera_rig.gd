extends Node3D
## Camera follow, shake and FOV punch (contract §7 camera row, systems spec §1.3).
## Exports stay tunable by the frontend; the rig itself is backend-owned.
## Every per-frame write to the Camera3D happens in _physics_process: the player moves there, and an
## interpolated Camera3D written from _process both warns and defeats physics interpolation
## (project.godot physics/common/physics_interpolation is on). The exceptions are the one-shot
## teleports in setup(), reset() and _aim(), which place the camera outside the physics step on
## boot and on restart; each of those calls reset_physics_interpolation() so the camera snaps to
## the new pose instead of sliding in from the previous run's.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")

@onready var camera: Camera3D = $Camera

@export var follow_smoothing := 8.0
@export var shake_amplitude := 0.12
## Extra degrees of FOV at full normalized speed.
@export var speed_fov_boost := 5.0

var game: RunnerGame
var config: RunConfig
var base_position := Vector3(0, 4, 8)
var base_fov := 60.0
var lateral_follow := 0.4
var follow_x := 0.0
## Trauma decays linearly; the offset uses trauma squared so small knocks stay subtle.
var trauma := 0.0
var trauma_decay := 0.0
var fov_punch := 0.0
var fov_punch_decay := 0.0
var rng := RandomNumberGenerator.new()

## Where the rig wants the camera before shake, refreshed in _physics_process.
var _rest_position := Vector3(0, 4, 8)

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	if config != null:
		base_position = config.camera_position
		base_fov = float(config.camera_fov)
		lateral_follow = float(config.camera_lateral_follow)
		_aim(config.camera_look_at)
	reset()

func reset() -> void:
	follow_x = 0.0
	trauma = 0.0
	trauma_decay = 0.0
	fov_punch = 0.0
	fov_punch_decay = 0.0
	_rest_position = base_position
	if camera != null:
		camera.position = base_position
		camera.fov = base_fov
		# Teleport, not a move: drop the interpolated previous pose so the first frame after a
		# restart renders at base_position/base_fov instead of easing over from the last run.
		camera.reset_physics_interpolation()

## Point the camera at `target` from base_position without touching the rig transform.
func _aim(target: Vector3) -> void:
	if camera == null:
		return
	var dir := (target - base_position).normalized()
	if dir.is_zero_approx():
		return
	var pitch := atan2(dir.y, sqrt(dir.x * dir.x + dir.z * dir.z))
	var yaw := atan2(-dir.x, -dir.z)
	camera.rotation = Vector3(pitch, yaw, 0.0)
	camera.reset_physics_interpolation()

func shake(strength: float, duration := 0.35) -> void:
	if duration <= 0.0 or strength <= 0.0:
		return
	# A stronger shake always wins; a weaker one never cuts the current one short.
	if strength >= trauma or trauma <= 0.0:
		trauma = minf(strength, 1.0)
		trauma_decay = trauma / duration

func punch_fov(degrees: float, seconds: float) -> void:
	if seconds <= 0.0:
		return
	# A bigger punch takes over with its own decay rate; a smaller one never cuts the active punch
	# short by replacing that rate with a faster one.
	if degrees < fov_punch:
		return
	fov_punch = degrees
	fov_punch_decay = degrees / seconds

## Follow, shake and FOV, all in the physics step so the interpolated camera keeps its own
## smoothing and never warns about a write from outside physics process.
func _physics_process(delta: float) -> void:
	var target_x := 0.0
	if game != null and is_instance_valid(game.player):
		target_x = game.player.position.x * lateral_follow
	follow_x = lerpf(follow_x, target_x, 1.0 - exp(-follow_smoothing * delta))
	_rest_position = base_position + Vector3(follow_x, 0.0, 0.0)
	if camera == null:
		return
	var offset := Vector3.ZERO
	if trauma > 0.0:
		trauma = maxf(trauma - trauma_decay * delta, 0.0)
		var amount := trauma * trauma * shake_amplitude
		offset = Vector3(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount), 0.0)
	camera.position = _rest_position + offset
	if fov_punch > 0.0:
		fov_punch = maxf(fov_punch - fov_punch_decay * delta, 0.0)
	var speed_boost := 0.0
	if game != null:
		speed_boost = speed_fov_boost * clampf(float(game.normalized_speed), 0.0, 1.2)
	camera.fov = base_fov + fov_punch + speed_boost
