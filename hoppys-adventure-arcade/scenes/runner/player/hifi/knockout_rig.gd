extends SkeletonModifier3D
## The runner knockout, layered over the imported clips like lane_look.gd and face_rig.gd. Hoppy
## catches his trailing foot and stumbles (on the run stride), faceplants (the glb's `dead` clip
## topples him from TRIP), scrabbles to crawl away, and is pinned flat when the pursuer's claws
## clamp down at CLAMP_AT (pursuer_visual.gd uses the same moment). `time` is seconds since the
## knockout began; below 0 the modifier is inert. Every offset multiplies the animated pose, which
## the skeleton restores before each pass, so nothing accumulates. Bone conventions (recipe 10):
## +X tips an upward bone back and a downward bone forward; knees flex on -X, elbows on +X.
## The dead clip starts here; until then the trip plays over the run stride.
const TRIP := 0.3
## Face-down on the deck (the dead clip lands about 0.45 s after it starts).
const LANDED := 0.75
## The claws close on him. Must match pursuer_visual.gd CLAMP_AT.
const CLAMP_AT := 1.6
const CRAWL_RATE := TAU*2.6
enum {HIPS, SPINE, CHEST, NECK, HEAD, EAR_L, EAR_R, ARM_L, ARM_R, FOREARM_L, FOREARM_R, LEG_L, LEG_R,
	SHIN_L, SHIN_R, FOOT_L, FOOT_R, CAPE}
const NAMES := ["hips", "spine", "chest", "neck", "head", "ear_L", "ear_R", "arm_L", "arm_R",
	"forearm_L", "forearm_R", "leg_L", "leg_R", "shin_L", "shin_R", "foot_L", "foot_R", "cape"]
var time := -1.0
## False when he was caught mid-air or mid-roll: the dead clip starts at once, without the trip pose.
var trips := true
var _bones := PackedInt32Array()

## Resolves the bones once; a rig missing any of them leaves the modifier inert.
func bind(skeleton: Skeleton3D) -> bool:
	_bones.clear()
	for title in NAMES:
		var bone := skeleton.find_bone(title)
		if bone < 0:
			_bones.clear()
			return false
		_bones.append(bone)
	return true

func active() -> bool:
	return time >= 0.0 and _bones.size() == NAMES.size()

## Face weights for face_rig.gd (focused, wide, wince, grin): shock on the trip, a wince on impact,
## fear while crawling, and a pained wince once pinned.
func face() -> Vector4:
	if time < LANDED-0.2: return Vector4(0, 1, 0, 0)
	if time < 0.95: return Vector4(0, 0.3, 0.9, 0)
	if time < CLAMP_AT: return Vector4(0.25, 1, 0.15, 0)
	return Vector4(0, 0.5, 1, 0)

static func _ramp(t: float, from: float, to: float) -> float:
	return smoothstep(from, to, t)

## A one-off kick: 0 outside [at, at+span], peaking in between.
static func _bump(t: float, at: float, span: float) -> float:
	return sin(PI*clampf((t-at)/span, 0, 1))

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not active():
		return
	var t := time
	var trip := _ramp(t, 0.0, 0.1)*(1.0-_ramp(t, TRIP, TRIP+0.3))*(1.0 if trips else 0.0)
	var splat := _ramp(t, TRIP, LANDED-0.1)
	var crawl := _ramp(t, 0.9, 1.1)*(1.0-_ramp(t, CLAMP_AT, CLAMP_AT+0.08))
	var pinned := _ramp(t, CLAMP_AT, CLAMP_AT+0.08)
	var impact := _bump(t, LANDED-0.05, 0.22)
	var slam := _bump(t, CLAMP_AT, 0.2)
	var stroke := sin(t*CRAWL_RATE)
	var squirm := sin(t*9.0)
	# Trip: the trailing (left) foot catches behind him while the lead leg reaches; he pitches
	# forward with both arms flung out ahead and his ears and cape whipping back.
	var arm_l := trip*1.9 + splat*2.5
	var arm_r := trip*1.5 + splat*2.5
	var arm_spread := splat*0.35
	var forearm := trip*0.4
	var leg_l := -trip*0.75 - splat*0.1
	var leg_r := trip*0.65 + splat*0.1
	var shin_l := -trip*1.1
	var shin_r := -trip*0.35
	var chest := -trip*0.45 + 0.2*impact
	var spine := -trip*0.3
	var hips := -trip*0.2
	var head := trip*0.4 + splat*0.2 + 0.3*impact
	var ears := trip*0.7 - 0.5*impact
	var cape := -trip*0.6
	# Crawl: head up, arms clawing at the deck in turn, feet kicking, trying to get away.
	arm_l += crawl*(-0.3+0.45*stroke)
	arm_r += crawl*(-0.3-0.45*stroke)
	forearm += crawl*(0.6+0.35*absf(stroke))
	shin_l += crawl*(-0.7-0.5*stroke)
	shin_r += crawl*(-0.7+0.5*stroke)
	chest += crawl*0.2
	head += crawl*0.45
	ears += crawl*0.2
	# Pinned: slammed flat, arms splayed, ears pressed back, a weak squirm under the claws.
	arm_l += pinned*(-0.6)
	arm_r += pinned*(-0.6)
	arm_spread += pinned*0.5
	forearm += pinned*(0.8+0.15*squirm)
	shin_l += pinned*(-0.45-0.3*squirm)
	shin_r += pinned*(-0.45+0.3*squirm)
	chest += pinned*(-0.12) - 0.25*slam
	head += pinned*(0.1+0.1*squirm) - 0.35*slam
	ears += pinned*1.0
	_turn(skeleton, HIPS, hips, pinned*0.08*squirm)
	_turn(skeleton, SPINE, spine)
	_turn(skeleton, CHEST, chest, pinned*0.06*squirm)
	_turn(skeleton, HEAD, head)
	_turn(skeleton, EAR_L, ears)
	_turn(skeleton, EAR_R, ears)
	_turn(skeleton, ARM_L, arm_l, -arm_spread)
	_turn(skeleton, ARM_R, arm_r, arm_spread)
	_turn(skeleton, FOREARM_L, forearm)
	_turn(skeleton, FOREARM_R, forearm)
	_turn(skeleton, LEG_L, leg_l)
	_turn(skeleton, LEG_R, leg_r)
	_turn(skeleton, SHIN_L, shin_l)
	_turn(skeleton, SHIN_R, shin_r)
	_turn(skeleton, CAPE, cape)

## Rotates a bone by `x` about its local X axis, then `z` about its local Z, on top of its pose.
func _turn(skeleton: Skeleton3D, index: int, x: float, z := 0.0) -> void:
	if is_zero_approx(x) and is_zero_approx(z):
		return
	var bone := _bones[index]
	var turn := Quaternion(Vector3.RIGHT, x)*Quaternion(Vector3.BACK, z)
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone)*turn)
