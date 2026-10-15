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
## Contract 2.6 §11.14 boss shots, one per cinematic mode. The lens is placed off the Boss mount:
## `distance` metres back toward the player, `height` metres off the mount (below it is a low angle
## looking up), `orbit` degrees of yaw around it. It aims at the visual's cinematic focus (§11.5,
## the centre of the upper third of its rest bounds unless the visual says otherwise) plus
## `look_bias` metres. The default focus sits about 2.4 to 3.1 m above the mount on the three
## shipped bosses, so the biases land the hold near +1.6 m and the defeat close-up near +1.9 m, and
## a taller boss is aimed higher. Keys are [p, distance, height, orbit, fov, look_bias], smoothstepped
## between. The blend ramps in over [0, cut] and back out over [ret, 1]; `ret` is where a skip lands at
## the default lengths (the last boss_cinematic_skip_tail 0.3 s), so a skip never pops the camera.
## The intro push lands on BossVisualBase.INTRO_POSE_AT and the hold ends on INTRO_HOLD_UNTIL.
const BOSS_SHOTS := {
	&"intro_full": {
		"cut": 0.03,
		"ret": 0.94,
		"keys": [
			# Cut in low and wide, push up at the boss (FOV 70 -> 52) to land with the pose and the
			# title card at 0.40, hold under the card until 0.66, then widen behind Hoppy for the hint
			# row. The hold sits far enough back that the Hydra's crests clear the top letterbox.
			[0.0, 9.0, -1.5, 0.0, 70.0, -1.9],
			[0.4, 6.5, -1.0, 0.0, 52.0, -1.1],
			[0.66, 6.3, -0.9, 0.0, 52.0, -1.1],
			[0.84, 16.0, 1.0, 0.0, 62.0, -2.4],
			[1.0, 16.0, 1.0, 0.0, 62.0, -2.4]
		]
	},
	&"intro_short": {
		"cut": 0.05,
		"ret": 0.88,
		"keys": [
			# The same push and hold, compressed: the push lands at 0.28 and the hold runs to the
			# return at 0.88.
			[0.0, 8.0, -1.3, 0.0, 64.0, -1.9],
			[0.28, 6.7, -0.9, 0.0, 54.0, -1.1],
			[0.88, 7.4, -0.5, 0.0, 56.0, -1.2],
			[1.0, 7.4, -0.5, 0.0, 56.0, -1.2]
		]
	},
	&"defeat_full": {
		"cut": 0.04,
		"ret": 0.917,
		"keys": [
			# Punch in through the hit-stop, orbit the close-up -12 -> +12 deg, then pull back wide
			# over Hoppy's shoulder for the triumphant beat. The close-up stands far enough back, and
			# aims high enough, that the Monolith's eyes and brow stay clear of the top letterbox.
			[0.0, 7.0, -0.4, -12.0, 56.0, -1.35],
			[0.06, 5.6, -0.3, -12.0, 50.0, -0.8],
			[0.5, 5.4, -0.2, 12.0, 50.0, -0.8],
			[0.8, 19.0, 2.4, 6.0, 58.0, -2.1],
			[1.0, 19.0, 2.4, 6.0, 58.0, -2.1]
		]
	},
	&"defeat_short": {
		"cut": 0.06,
		"ret": 0.85,
		"keys": [
			[0.0, 7.0, -0.4, -12.0, 56.0, -1.35],
			[0.08, 5.8, -0.3, -12.0, 52.0, -0.8],
			[0.45, 5.6, -0.2, 12.0, 52.0, -0.8],
			[0.75, 18.0, 2.2, 6.0, 58.0, -2.1],
			[1.0, 18.0, 2.2, 6.0, 58.0, -2.1]
		]
	}
}

## Contract 2.7 §11.15: the run intro's shot table is frontend data. It lives in this script once it
## exists — `const SHOTS := {&"full": {cut, ret, keys}, &"short": {...}}`, rows in the BOSS_SHOTS
## layout — and is read through ResourceLoader.exists + load(), never preloaded, so the backend runs
## without it on the built-in fallback below.
const RUN_INTRO_SHOTS_PATH := "res://scenes/runner/data/run_intro_shots.gd"
## The built-in intro shots, used per mode whenever the frontend table is missing or lacks the mode.
## Unlike a boss shot the lens is placed off Hoppy's feet (`focus`): `distance` metres behind him
## along +Z, rotated `orbit` degrees around him, so orbit ±180 looks back at him from down the corridor.
## The rest pose is [8.0, 4.0, 0.0, 60.0, 2.5]: the gameplay camera at (0, 4, 8) aimed 2.5 m above the
## feet, which is the same line as the follow's look-at (0, 1, -8). Side-on keys stay within 3.4 m of
## Hoppy so the lens never enters the corridor walls (x ±4.4). `cut` 0 is a hard cut on frame one.
const RUN_INTRO_FALLBACK_SHOTS := {
	&"full": {
		"cut": 0.0,
		"ret": 0.86,
		"keys": [
			# Open 14 m down the corridor looking back at Hoppy, push in for the title card, rise over
			# his shoulder side-on, then land on the rest pose behind him for the 3-2-1-GO.
			[0.0, 14.0, 2.2, -180.0, 58.0, 1.2],
			[0.28, 6.0, 1.6, -180.0, 50.0, 1.1],
			[0.45, 5.6, 1.7, -175.0, 50.0, 1.1],
			[0.55, 2.5, 5.0, -90.0, 60.0, 1.5],
			[0.7, 8.0, 4.0, 0.0, 60.0, 2.5],
			[1.0, 8.0, 4.0, 0.0, 60.0, 2.5]
		]
	},
	&"short": {
		"cut": 0.0,
		"ret": 0.8,
		"keys": [
			# A gentle push down onto the rest pose.
			[0.0, 10.0, 5.0, 0.0, 64.0, 2.6],
			[0.6, 8.0, 4.0, 0.0, 60.0, 2.5],
			[1.0, 8.0, 4.0, 0.0, 60.0, 2.5]
		]
	}
}
## The shot table, read once per session on first use.
static var _run_intro_shots: Dictionary = {}
static var _run_intro_shots_read := false

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
## 0..1 through the boss cinematic and its mode, &"" outside one (contract 2.6 §11.14).
var boss_progress := 0.0
var boss_mode: StringName = &""
## The Boss mount, in this rig's space, that the lens is placed off.
var boss_target := Vector3.ZERO
## The visual's cinematic focus, in this rig's space, that the lens aims at (contract §11.5).
var boss_focus := Vector3.ZERO
## 0..1 through the run intro and its mode, &"" outside one (contract 2.7 §11.15).
var intro_progress := 0.0
var intro_mode: StringName = &""
## Hoppy's feet, in this rig's space, that the intro lens is placed off and aims above.
var intro_focus := Vector3.ZERO
## Set when an intro opens; the next tick snaps the interpolated camera onto its first shot.
var _intro_cut := false

## Where the rig wants the camera before shake, refreshed in _physics_process.
var _rest_position := Vector3(0, 4, 8)
## The rest rotation _aim() left behind. Every tick starts from it, so a boss shot blended on top
## never accumulates.
var _base_rotation := Vector3.ZERO

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	# The authored pose is the fallback resting rotation, so a rig without a config still keeps the
	# scene's pitch instead of snapping to zero on its first tick.
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
	boss_progress = 0.0
	boss_mode = &""
	boss_target = Vector3.ZERO
	boss_focus = Vector3.ZERO
	intro_progress = 0.0
	intro_mode = &""
	intro_focus = Vector3.ZERO
	_intro_cut = false
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

## The boss cinematic shot (contract 2.6 §11.14). The StageManager calls this every physics tick of
## the `boss` phase, and with (0, &"") once the cinematic is over.
## `boss_position` is the Boss mount's global position and `focus_position` the global point the
## shot aims at (the mount plus the visual's cinematic focus, §11.5); without one the shot aims at
## the mount itself. boss_shot() blends to 0 at p = 0 and p = 1, so the camera hands back to the
## follow exactly where it left it.
func set_boss_cinematic(progress: float, mode: StringName, boss_position: Vector3,
		focus_position: Variant = null) -> void:
	boss_progress = clampf(progress, 0.0, 1.0)
	boss_mode = mode
	boss_target = to_local(boss_position) if is_inside_tree() else boss_position
	var focus: Vector3 = focus_position if focus_position is Vector3 else boss_position
	boss_focus = to_local(focus) if is_inside_tree() else focus

## Pure shot curve for `mode` at progress `p`: {blend, distance, height, orbit, fov, look_bias} (see
## BOSS_SHOTS). `blend` is exactly 0 at p = 0 and p = 1 — the endpoints are answered before the
## ramps — and an unknown or empty mode never blends at all.
static func boss_shot(p: float, mode: StringName) -> Dictionary:
	var progress := clampf(p, 0.0, 1.0)
	var table: Dictionary = BOSS_SHOTS.get(mode, {})
	var keys: Array = table.get("keys", [])
	var shot := {"blend": 0.0, "distance": 0.0, "height": 0.0, "orbit": 0.0, "fov": 0.0, "look_bias": 0.0}
	if keys.is_empty():
		return shot
	var pose: Array = _shot_pose(keys, progress)
	shot["distance"] = float(pose[1])
	shot["height"] = float(pose[2])
	shot["orbit"] = float(pose[3])
	shot["fov"] = float(pose[4])
	shot["look_bias"] = float(pose[5])
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

## The run intro shot (contract 2.7 §11.15). The StageManager calls this every physics tick of the
## `intro` phase and with (0, &"") once the intro is over. `focus` is Hoppy's global position (his
## feet). A fresh intro hard-cuts in, so the camera never slides over from wherever it was.
func set_run_intro(progress: float, mode: StringName, focus: Vector3) -> void:
	if intro_mode == &"" and mode != &"":
		_intro_cut = true
	intro_progress = clampf(progress, 0.0, 1.0)
	intro_mode = mode
	intro_focus = to_local(focus) if is_inside_tree() else focus

## Pure shot curve for the run intro: {blend, distance, height, orbit, fov, look_bias}, from the
## frontend table when it has `mode`, else from RUN_INTRO_FALLBACK_SHOTS. `blend` is exactly 0 at
## p = 1 and for an unknown or empty mode; at p = 0 it is 1 when `cut` is 0 (a hard cut) and 0
## otherwise, ramping in over [0, cut] and out over [ret, 1] as a boss shot does.
static func run_intro_shot(p: float, mode: StringName) -> Dictionary:
	var shot := {"blend": 0.0, "distance": 0.0, "height": 0.0, "orbit": 0.0, "fov": 0.0, "look_bias": 0.0}
	if mode == &"":
		return shot
	var table: Variant = run_intro_shots().get(mode, RUN_INTRO_FALLBACK_SHOTS.get(mode, {}))
	if not (table is Dictionary):
		return shot
	var keys: Variant = table.get("keys", [])
	if not (keys is Array) or keys.is_empty():
		return shot
	var progress := clampf(p, 0.0, 1.0)
	var pose: Array = _shot_pose(keys, progress)
	shot["distance"] = float(pose[1])
	shot["height"] = float(pose[2])
	shot["orbit"] = float(pose[3])
	shot["fov"] = float(pose[4])
	shot["look_bias"] = float(pose[5])
	if progress >= 1.0:
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

## The frontend's SHOTS table when its script exists, else the built-in one. Read once: the script
## is loaded only for its constant map and not kept.
static func run_intro_shots() -> Dictionary:
	if _run_intro_shots_read:
		return _run_intro_shots
	_run_intro_shots_read = true
	_run_intro_shots = RUN_INTRO_FALLBACK_SHOTS
	if not ResourceLoader.exists(RUN_INTRO_SHOTS_PATH):
		return _run_intro_shots
	var script := load(RUN_INTRO_SHOTS_PATH) as Script
	if script == null:
		push_warning("Run intro shots at %s are not a script; using the built-in shots" % RUN_INTRO_SHOTS_PATH)
		return _run_intro_shots
	var table: Variant = script.get_script_constant_map().get("SHOTS", null)
	if table is Dictionary and not table.is_empty():
		_run_intro_shots = table
	else:
		push_warning("Run intro shots at %s have no SHOTS table; using the built-in shots" % RUN_INTRO_SHOTS_PATH)
	return _run_intro_shots

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
	camera.rotation = _base_rotation
	var shot := boss_shot(boss_progress, boss_mode)
	var blend := float(shot["blend"])
	_apply_boss_shot(shot, blend, offset)
	# The run intro and a boss cinematic never overlap (different phases); the intro, when live,
	# frames the camera instead.
	if intro_mode != &"":
		var intro := run_intro_shot(intro_progress, intro_mode)
		if float(intro["blend"]) > 0.0:
			shot = intro
			blend = float(intro["blend"])
			_apply_shot(intro_focus, intro_focus, shot, blend, offset)
	if fov_punch > 0.0:
		fov_punch = maxf(fov_punch - fov_punch_decay * delta, 0.0)
	var speed_boost := 0.0
	if game != null:
		speed_boost = speed_fov_boost * clampf(float(game.normalized_speed), 0.0, 1.2)
	var fov := base_fov + fov_punch + speed_boost
	# The punch rides the shot too, so a defeat explosion still kicks the close-up.
	camera.fov = lerpf(fov, float(shot["fov"]) + fov_punch, blend) if blend > 0.0 else fov
	if _intro_cut:
		# The intro's first frame is a cut, not a move: drop the interpolated previous pose.
		_intro_cut = false
		camera.reset_physics_interpolation()

## Blend the follow pose toward the boss shot (contract 2.6 §11.14): the lens sits off the Boss
## mount where the shot says and aims at the visual's focus plus the shot's look_bias, the shake
## offset rides along, and position and rotation both mix by `blend`, which is 0 outside a cinematic
## and at both of its ends.
func _apply_boss_shot(shot: Dictionary, blend: float, offset: Vector3) -> void:
	_apply_shot(boss_target, boss_focus, shot, blend, offset)

## The shared lens placement: `distance` metres from `target` along +Z rotated `orbit` degrees about
## it, `height` metres up, aimed at `focus` plus `look_bias`, mixed with the follow pose by `blend`.
func _apply_shot(target: Vector3, focus: Vector3, shot: Dictionary, blend: float, offset: Vector3) -> void:
	if blend <= 0.0:
		return
	var orbit := deg_to_rad(float(shot["orbit"]))
	var lens := target + Vector3(0.0, float(shot["height"]), float(shot["distance"])).rotated(Vector3.UP, orbit)
	var aim := focus + Vector3(0.0, float(shot["look_bias"]), 0.0)
	var follow_rotation := camera.quaternion
	camera.position = camera.position.lerp(lens + offset, blend)
	var look := aim - lens
	if look.is_zero_approx():
		return
	var shot_rotation := Basis.looking_at(look, Vector3.UP).get_rotation_quaternion()
	camera.quaternion = follow_rotation.slerp(shot_rotation, blend)
