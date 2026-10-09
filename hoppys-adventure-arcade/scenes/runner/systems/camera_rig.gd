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
## Contract §11.10 fallbacks, used only when no config has been supplied yet.
const DEFAULT_TURN_CAMERA_YAW := 55.0
const DEFAULT_TURN_CAMERA_BANK := 12.0
const DEFAULT_TURN_SWING_IN_FRACTION := 0.3
const DEFAULT_TURN_SWING_OUT_FRACTION := 0.3
## Contract 2.6 §11.14 boss shots, one per cinematic mode. A pose is placed off the Boss node:
## `distance` metres back toward the player, `height` metres off the boss centre (below it is a low
## angle looking up), `orbit` degrees of yaw around the boss, and the lens aims `look_y` metres above
## the centre. Keys are [p, distance, height, orbit, fov, look_y], smoothstepped between. The blend
## ramps in over [0, cut] and back out over [ret, 1]; `ret` is where a skip lands at the default
## lengths (the last boss_cinematic_skip_tail 0.3 s), so a skip never pops the camera.
const BOSS_SHOTS := {
	&"intro_full": {
		"cut": 0.03,
		"ret": 0.94,
		"keys": [
			# Cut in low and wide, push up at the boss (FOV 70 -> 48), freeze under the title card,
			# then widen behind Hoppy for the hint row.
			[0.0, 9.0, -1.5, 0.0, 70.0, 0.4],
			[0.4, 5.4, -1.0, 0.0, 48.0, 0.5],
			[0.66, 5.2, -0.9, 0.0, 48.0, 0.5],
			[0.84, 16.0, 1.0, 0.0, 62.0, 0.0],
			[1.0, 16.0, 1.0, 0.0, 62.0, 0.0]
		]
	},
	&"intro_short": {
		"cut": 0.05,
		"ret": 0.88,
		"keys": [
			[0.0, 8.0, -1.3, 0.0, 64.0, 0.4],
			[0.45, 5.6, -0.9, 0.0, 50.0, 0.5],
			[0.88, 7.0, -0.5, 0.0, 54.0, 0.4],
			[1.0, 7.0, -0.5, 0.0, 54.0, 0.4]
		]
	},
	&"defeat_full": {
		"cut": 0.04,
		"ret": 0.917,
		"keys": [
			# Punch in through the hit-stop, orbit the close-up -12 -> +12 deg, then pull back wide
			# over Hoppy's shoulder for the triumphant beat.
			[0.0, 7.0, -0.4, -12.0, 56.0, 0.3],
			[0.06, 4.4, -0.3, -12.0, 44.0, 0.3],
			[0.5, 4.2, -0.2, 12.0, 44.0, 0.3],
			[0.8, 19.0, 2.4, 6.0, 58.0, 0.0],
			[1.0, 19.0, 2.4, 6.0, 58.0, 0.0]
		]
	},
	&"defeat_short": {
		"cut": 0.06,
		"ret": 0.85,
		"keys": [
			[0.0, 7.0, -0.4, -12.0, 56.0, 0.3],
			[0.08, 4.6, -0.3, -12.0, 46.0, 0.3],
			[0.45, 4.4, -0.2, 12.0, 46.0, 0.3],
			[0.75, 18.0, 2.2, 6.0, 58.0, 0.0],
			[1.0, 18.0, 2.2, 6.0, 58.0, 0.0]
		]
	}
}

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
## 0..1 through the cinematic turn; 0 outside one (contract §11.9).
var turn_progress := 0.0
## -1 left, +1 right, 0 outside a turn.
var turn_direction := 0
## 0..1 through the boss cinematic and its mode, &"" outside one (contract 2.6 §11.14).
var boss_progress := 0.0
var boss_mode: StringName = &""
## The Boss node, in this rig's space, that the shot is framed on.
var boss_target := Vector3.ZERO

## Where the rig wants the camera before shake, refreshed in _physics_process.
var _rest_position := Vector3(0, 4, 8)
## The pose _aim() left behind, so the turn swing is applied on top of it and never accumulates.
var _base_rotation := Vector3.ZERO

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	# The authored pose is the fallback resting rotation, so a rig without a config still keeps the
	# scene's pitch instead of snapping to zero the first time the turn swing resolves.
	if camera != null:
		_base_rotation = camera.rotation
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
	turn_progress = 0.0
	turn_direction = 0
	boss_progress = 0.0
	boss_mode = &""
	boss_target = Vector3.ZERO
	_rest_position = base_position
	if camera != null:
		camera.position = base_position
		camera.rotation = _base_rotation
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
	_base_rotation = Vector3(pitch, yaw, 0.0)
	camera.rotation = _base_rotation
	camera.reset_physics_interpolation()

## The cinematic turn swing (contract §11.9). The StageManager calls this every physics tick of the
## `turn` phase and once with (0, 0) at each end of it; the swing profile is zero at both ends, so
## at p = 0 and p = 1 the camera sits exactly where the follow left it.
func set_turn(progress: float, direction: int) -> void:
	turn_progress = clampf(progress, 0.0, 1.0)
	turn_direction = signi(direction)

## The ramp-hold-return swing envelope (contract §11.9): a smoothstep up over the first
## `turn_swing_in_fraction` of the bend, a hold at the peak, a smoothstep back down over the last
## `turn_swing_out_fraction`. That is what makes the corner read as a committed turn rather than as
## a wave — the camera is pointed into the corner for the whole middle of the bend.
##
## The result is exactly 0 at p = 0 and p = 1 whatever the fractions are, so the camera can never be
## left displaced: the endpoints are answered before the ramps, which also covers an authored 0/0
## that would otherwise leave a step at each end. Fractions that together exceed the whole bend are
## scaled down in proportion, so the hold shrinks to nothing rather than the ramps overlapping.
func turn_swing_profile(progress: float) -> float:
	var p := clampf(progress, 0.0, 1.0)
	if p <= 0.0 or p >= 1.0:
		return 0.0
	var rise := clampf(turn_swing_in_fraction(), 0.0, 1.0)
	var fall := clampf(turn_swing_out_fraction(), 0.0, 1.0)
	var total := rise + fall
	if total > 1.0:
		rise /= total
		fall /= total
	if rise > 0.0 and p < rise:
		return smoothstep(0.0, 1.0, p / rise)
	if fall > 0.0 and p > 1.0 - fall:
		return smoothstep(0.0, 1.0, (1.0 - p) / fall)
	return 1.0

func turn_camera_yaw_degrees() -> float:
	return float(config.turn_camera_yaw_degrees) if config != null else DEFAULT_TURN_CAMERA_YAW

func turn_camera_bank_degrees() -> float:
	return float(config.turn_camera_bank_degrees) if config != null else DEFAULT_TURN_CAMERA_BANK

func turn_swing_in_fraction() -> float:
	if config == null or not (&"turn_swing_in_fraction" in config):
		return DEFAULT_TURN_SWING_IN_FRACTION
	return float(config.turn_swing_in_fraction)

func turn_swing_out_fraction() -> float:
	if config == null or not (&"turn_swing_out_fraction" in config):
		return DEFAULT_TURN_SWING_OUT_FRACTION
	return float(config.turn_swing_out_fraction)

## The boss cinematic shot (contract 2.6 §11.14). The StageManager calls this every physics tick of
## the `boss` phase, the way it drives set_turn(), and with (0, &"") once the cinematic is over;
## `boss_position` is the Boss node's global position. boss_shot() blends to 0 at p = 0 and p = 1,
## so the camera hands back to the follow exactly where it left it.
func set_boss_cinematic(progress: float, mode: StringName, boss_position: Vector3) -> void:
	boss_progress = clampf(progress, 0.0, 1.0)
	boss_mode = mode
	boss_target = to_local(boss_position) if is_inside_tree() else boss_position

## Pure shot curve for `mode` at progress `p`: {blend, distance, height, orbit, fov, look_y} (see
## BOSS_SHOTS). Like turn_swing_profile, `blend` is exactly 0 at p = 0 and p = 1 — the endpoints are
## answered before the ramps — and an unknown or empty mode never blends at all.
static func boss_shot(p: float, mode: StringName) -> Dictionary:
	var progress := clampf(p, 0.0, 1.0)
	var table: Dictionary = BOSS_SHOTS.get(mode, {})
	var keys: Array = table.get("keys", [])
	var shot := {"blend": 0.0, "distance": 0.0, "height": 0.0, "orbit": 0.0, "fov": 0.0, "look_y": 0.0}
	if keys.is_empty():
		return shot
	var pose: Array = _shot_pose(keys, progress)
	shot["distance"] = float(pose[1])
	shot["height"] = float(pose[2])
	shot["orbit"] = float(pose[3])
	shot["fov"] = float(pose[4])
	shot["look_y"] = float(pose[5])
	if progress <= 0.0 or progress >= 1.0:
		return shot
	var cut := clampf(float(table.get("cut", 0.0)), 0.0, 1.0)
	var ret := clampf(float(table.get("ret", 1.0)), cut, 1.0)
	var blend := 1.0
	if cut > 0.0 and progress < cut:
		blend = smoothstep(0.0, 1.0, progress / cut)
	elif ret < 1.0 and progress > ret:
		blend = smoothstep(0.0, 1.0, (1.0 - progress) / (1.0 - ret))
	shot["blend"] = blend
	return shot

## The key pose at `progress`, smoothstepped between the two keys around it.
static func _shot_pose(keys: Array, progress: float) -> Array:
	var first: Array = keys[0]
	if progress <= float(first[0]):
		return first
	for index in range(1, keys.size()):
		var to: Array = keys[index]
		if progress > float(to[0]):
			continue
		var from: Array = keys[index - 1]
		var span := float(to[0]) - float(from[0])
		var t := smoothstep(0.0, 1.0, (progress - float(from[0])) / span) if span > 0.0 else 1.0
		var pose := [progress]
		for column in range(1, from.size()):
			pose.append(lerpf(float(from[column]), float(to[column]), t))
		return pose
	return keys[keys.size() - 1]

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
	_apply_turn_swing()
	var shot := boss_shot(boss_progress, boss_mode)
	var blend := float(shot["blend"])
	_apply_boss_shot(shot, blend, offset)
	if fov_punch > 0.0:
		fov_punch = maxf(fov_punch - fov_punch_decay * delta, 0.0)
	var speed_boost := 0.0
	if game != null:
		speed_boost = speed_fov_boost * clampf(float(game.normalized_speed), 0.0, 1.2)
	var fov := base_fov + fov_punch + speed_boost
	# The punch rides the shot too, so a defeat explosion still kicks the close-up.
	camera.fov = lerpf(fov, float(shot["fov"]) + fov_punch, blend) if blend > 0.0 else fov

## Swing the camera around the player and bank it, on top of the follow and shake result. Both
## angles ride turn_swing_profile(progress), so the bend starts and ends at the resting pose exactly
## and spends its middle held at the peak.
func _apply_turn_swing() -> void:
	var swing := float(turn_direction) * turn_swing_profile(turn_progress)
	if is_zero_approx(swing):
		camera.rotation = _base_rotation
		return
	var yaw := deg_to_rad(turn_camera_yaw_degrees()) * swing
	var bank := deg_to_rad(turn_camera_bank_degrees()) * swing
	var pivot := Vector3.ZERO
	if game != null and is_instance_valid(game.player):
		pivot = game.player.position
	camera.position = pivot + (camera.position - pivot).rotated(Vector3.UP, yaw)
	camera.rotation = _base_rotation + Vector3(0.0, yaw, bank)

## Blend the follow pose toward the boss shot (contract 2.6 §11.14): the camera sits off the Boss
## node where the shot says and aims at it, the shake offset rides along, and position and rotation
## both mix by `blend`, which is 0 outside a cinematic and at both of its ends.
func _apply_boss_shot(shot: Dictionary, blend: float, offset: Vector3) -> void:
	if blend <= 0.0:
		return
	var orbit := deg_to_rad(float(shot["orbit"]))
	var lens := boss_target + Vector3(0.0, float(shot["height"]), float(shot["distance"])).rotated(Vector3.UP, orbit)
	var aim := boss_target + Vector3(0.0, float(shot["look_y"]), 0.0)
	var follow_rotation := camera.quaternion
	camera.position = camera.position.lerp(lens + offset, blend)
	var look := aim - lens
	if look.is_zero_approx():
		return
	var shot_rotation := Basis.looking_at(look, Vector3.UP).get_rotation_quaternion()
	camera.quaternion = follow_rotation.slerp(shot_rotation, blend)
