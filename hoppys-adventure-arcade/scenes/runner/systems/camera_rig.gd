extends Node3D
## Camera follow, shake and FOV punch (contract §7 camera row, systems spec §1.3).
## Exports stay tunable by the frontend; the rig itself is backend-owned.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")

@onready var camera: Camera3D = $Camera

@export var follow_smoothing := 8.0
@export var shake_amplitude := 0.12

var game: RunnerGame
var config: RunConfig
var base_position := Vector3(0, 4, 8)
var base_fov := 60.0
var lateral_follow := 0.4
var follow_x := 0.0
var shake_strength := 0.0
var shake_remaining := 0.0
var shake_duration := 0.0
var fov_punch := 0.0
var fov_punch_decay := 0.0
var rng := RandomNumberGenerator.new()

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
	shake_strength = 0.0
	shake_remaining = 0.0
	shake_duration = 0.0
	fov_punch = 0.0
	fov_punch_decay = 0.0
	if camera != null:
		camera.position = base_position
		camera.fov = base_fov

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

func shake(strength: float, duration := 0.35) -> void:
	if duration <= 0.0 or strength <= 0.0:
		return
	# A stronger shake always wins; a weaker one never cuts the current one short.
	if strength >= shake_strength or shake_remaining <= 0.0:
		shake_strength = strength
		shake_duration = duration
		shake_remaining = duration

func punch_fov(degrees: float, seconds: float) -> void:
	if seconds <= 0.0:
		return
	fov_punch = maxf(fov_punch, degrees)
	fov_punch_decay = fov_punch / seconds

func _physics_process(delta: float) -> void:
	if camera == null:
		return
	var target_x := 0.0
	if game != null and game.player != null:
		target_x = game.player.position.x * lateral_follow
	follow_x = lerpf(follow_x, target_x, 1.0 - exp(-follow_smoothing * delta))
	var offset := Vector3.ZERO
	if shake_remaining > 0.0:
		shake_remaining = maxf(shake_remaining - delta, 0.0)
		var falloff := shake_remaining / shake_duration if shake_duration > 0.0 else 0.0
		var amount := shake_strength * falloff * shake_amplitude
		offset = Vector3(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount), 0.0)
	camera.position = base_position + Vector3(follow_x, 0.0, 0.0) + offset
	if fov_punch > 0.0:
		fov_punch = maxf(fov_punch - fov_punch_decay * delta, 0.0)
	camera.fov = base_fov + fov_punch
