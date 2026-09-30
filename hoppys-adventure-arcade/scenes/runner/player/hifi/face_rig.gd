extends SkeletonModifier3D
## Runtime face expressions, applied after animation evaluation like lane_look.gd.
## Brow and mouth-corner bones stay at rest in every clip; the eye bones carry the sclera, iris
## and lid line, so a vertical eye scale squints, winces, blinks or widens the eyes.
## Every pose is rebuilt from the rest pose each pass, so nothing accumulates, and the pass
## only reads packed arrays and value types: no per-frame allocation.
## Expression weights, 0..1, set by the visual (hoppy_runner_visual.gd) every frame.
var focused := 0.0
var wide := 0.0
var wince := 0.0
var grin := 0.0
var blink := 0.0
## Largest inner-brow drop (radians): 60% of the full-focus tilt, so a determined or pained face
## stays friendly instead of angry.
const MAX_BROW_DROP := 0.12
## Bone indices per side (0 = L at -x, 1 = R at +x); empty until bound.
var _eyes := PackedInt32Array()
var _brows := PackedInt32Array()
var _mouths := PackedInt32Array()
## Local axis index (0..2) of each eye bone that points up in skeleton space.
var _eye_axis := PackedInt32Array()
var _eye_scale := PackedVector3Array()
## Rest origins and skeleton up/right expressed in each bone's parent (head) space.
var _brow_origin := PackedVector3Array()
var _mouth_origin := PackedVector3Array()
var _up := PackedVector3Array()
var _right := PackedVector3Array()
## Brow rest rotations and the skeleton +Z (back) axis in brow-local space.
var _brow_rest: Array[Quaternion] = []
var _brow_axis := PackedVector3Array()

func bound() -> bool:
	return _eyes.size() == 2

## Resolves the six face bones once; returns false (and stays inert) on an older rig.
func bind(skeleton: Skeleton3D) -> bool:
	_eyes.clear()
	for side in ["L", "R"]:
		var eye := skeleton.find_bone("eye_" + side)
		var brow := skeleton.find_bone("brow_" + side)
		var mouth := skeleton.find_bone("mouth_" + side)
		if eye < 0 or brow < 0 or mouth < 0:
			_eyes.clear()
			return false
		var local_up := skeleton.get_bone_global_rest(eye).basis.orthonormalized().inverse() * Vector3.UP
		var axis := 0
		for i in 3:
			if absf(local_up[i]) > absf(local_up[axis]):
				axis = i
		_eyes.append(eye)
		_brows.append(brow)
		_mouths.append(mouth)
		_eye_axis.append(axis)
		_eye_scale.append(skeleton.get_bone_rest(eye).basis.get_scale())
		var parent := skeleton.get_bone_global_rest(skeleton.get_bone_parent(brow)).basis.orthonormalized().inverse()
		_up.append(parent * Vector3.UP)
		_right.append(parent * Vector3.RIGHT)
		_brow_origin.append(skeleton.get_bone_rest(brow).origin)
		_mouth_origin.append(skeleton.get_bone_rest(mouth).origin)
		_brow_rest.append(skeleton.get_bone_rest(brow).basis.get_rotation_quaternion())
		_brow_axis.append((skeleton.get_bone_global_rest(brow).basis.orthonormalized().inverse() * Vector3.BACK).normalized())
	return true

## Vertical eye scale for the current weights (1 = authored rest).
func eye_openness() -> float:
	var open := 1.0 + 0.16 * wide - 0.2 * focused - 0.72 * wince - 0.38 * grin
	return clampf(open, 0.14, 1.2) * (1.0 - 0.86 * clampf(blink, 0.0, 1.0))

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not bound():
		return
	var open := maxf(eye_openness(), 0.1)
	var lift := 0.017 * wide - 0.009 * focused - 0.004 * wince + 0.009 * grin
	# Positive tilt drops the inner brow end (focused/wince); wide eyes lift it (worried). The drop
	# is capped so no state reaches a full scowl.
	var tilt := minf(0.2 * focused + 0.26 * wince - 0.1 * wide - 0.05 * grin, MAX_BROW_DROP)
	var pinch := 0.006 * wince + 0.002 * focused
	var corner := 0.016 * grin - 0.009 * wince - 0.005 * wide
	var spread := 0.008 * grin - 0.005 * wince
	for i in 2:
		var sign := -1.0 if i == 0 else 1.0
		var scale := _eye_scale[i]
		scale[_eye_axis[i]] *= open
		skeleton.set_bone_pose_scale(_eyes[i], scale)
		skeleton.set_bone_pose_position(_brows[i], _brow_origin[i] + _up[i] * lift - _right[i] * (sign * pinch))
		skeleton.set_bone_pose_rotation(_brows[i], _brow_rest[i] * Quaternion(_brow_axis[i], sign * tilt))
		skeleton.set_bone_pose_position(_mouths[i], _mouth_origin[i] + _up[i] * corner + _right[i] * (sign * spread))
