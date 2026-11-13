extends SkeletonModifier3D
## Spring physics for the cape and the ears, layered over the imported clips like lane_look.gd.
## Each link (cape, cape_tip, ear_*, ear_tip_*) owns a point mass at its bone tail, simulated in
## world space: a spring pulls it toward where the clip puts the tail, so lane changes, jumps,
## landings and the clip's own motion all make it lag, overshoot and settle. The cape is heavy and
## loose (about 1.2 Hz, under-damped: it swings behind the stride); the ears are light and stiff
## (about 10 Hz, well above the 3.3 Hz stride, so they ride the run and only whip on dashes and
## jumps). The bone is then turned from the clip's direction to the simulated one. The skeleton
## restores the clip pose before each pass, so nothing accumulates in the bones; only the point
## masses persist.
##
## The visual feeds `pending` (seconds to simulate), `wind` and `amount` every frame. The skeleton
## may run its modifiers more than once a frame: a pass with no pending time holds the masses where
## they are. A long gap, a clip pose that jumps (the roll starts unblended) or settle() snaps the
## masses back onto the clip pose; posed fixtures call settle() (capture_a1.gd pose_for_view).

## Per link: bone, stiffness (1/s^2), damping (1/s), wind drag, largest swing (rad).
const LINKS := [
	["cape", 55.0, 4.5, 6.0, 0.6],
	["cape_tip", 40.0, 3.2, 9.0, 0.7],
	["ear_L", 4000.0, 36.0, 6.0, 0.3],
	["ear_tip_L", 2500.0, 26.0, 10.0, 0.45],
	["ear_R", 4000.0, 36.0, 6.0, 0.3],
	["ear_tip_R", 2500.0, 26.0, 10.0, 0.45],
]
const CAPE_LINKS := 2
## Fixed integration step; a frame is split into as many as MAX_STEPS of them.
const STEP := 1.0 / 120.0
const MAX_STEPS := 8
## A longer gap than this (a hitch, a fixture jumping the clock) snaps instead of simulating.
const SNAP_AFTER := 0.25
## A clip tail that moves further than this fraction of its link in one pass has teleported.
const TELEPORT := 0.5
## How far (as a fraction of its length) a cape link may swing forward of the clip pose, toward
## the body, before it is held back: the cloth drapes over the back instead of passing through it.
const CAPE_FORWARD := 0.12

## Seconds of simulation owed; the visual adds its frame delta, each pass consumes it.
var pending := 0.0
## Air pushing on the cloth, in skeleton space (+Z is behind Hoppy), in m/s^2 per unit drag.
var wind := Vector3.ZERO
## 0..1 scale on the applied swing (the slide keeps the cape low).
var amount := 1.0
## False in fixtures that step the simulation by hand and must leave the bones untouched.
var apply_pose := true
var _bones := PackedInt32Array()
var _parents := PackedInt32Array()
## Bone-local vector from each bone's origin to its tail.
var _tails := PackedVector3Array()
var _points := PackedVector3Array()
var _velocities := PackedVector3Array()
## Last applied swing per link (rad) and the mass's offset from the clip tail, for tests and tuning.
var _swings := PackedFloat32Array()
var _offsets := PackedVector3Array()
## Each link's clip tail in skeleton space on the last pass, to spot a pose that jumps.
var _clip_tails := PackedVector3Array()
var _settled := false

## Resolves the links once; a rig missing any of them leaves the modifier inert.
func bind(skeleton: Skeleton3D) -> bool:
	_bones.clear()
	_parents.clear()
	_tails.clear()
	for link: Array in LINKS:
		var bone := skeleton.find_bone(link[0])
		if bone < 0:
			_bones.clear()
			return false
		_bones.append(bone)
		_parents.append(skeleton.get_bone_parent(bone))
	for index in _bones.size():
		var bone := _bones[index]
		var tail := Vector3.ZERO
		for child in skeleton.get_bone_children(bone):
			if child in _bones:
				tail = skeleton.get_bone_rest(child).origin
		if tail == Vector3.ZERO:
			# A chain tip: as long as its parent link, along the bone's own axis.
			tail = Vector3(0.0, skeleton.get_bone_rest(bone).origin.length(), 0.0)
		_tails.append(tail)
	_points.resize(_bones.size())
	_velocities.resize(_bones.size())
	_swings.resize(_bones.size())
	_offsets.resize(_bones.size())
	_clip_tails.resize(_bones.size())
	_settled = false
	return true

func bound() -> bool:
	return not _bones.is_empty()

## Drops every mass back onto the clip pose on the next pass (teleports, run resets).
func settle() -> void:
	_settled = false

## Swing applied to a link on the last pass (rad).
func swing(link: int) -> float:
	return _swings[link]

## World-space offset of a link's mass from where the clip puts its tail, on the last pass.
func offset(link: int) -> Vector3:
	return _offsets[link]

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not bound():
		return
	var delta := pending
	pending = 0.0
	var snap_all := not _settled or delta > SNAP_AFTER
	_settled = true
	var steps := clampi(ceili(delta / STEP), 1, MAX_STEPS)
	var step := delta / float(steps)
	# The visual opts out of physics interpolation but renders at its interpolated parent's pose.
	var frame := skeleton.get_global_transform_interpolated()
	var frame_basis := frame.basis.orthonormalized()
	var world_wind := frame_basis * wind
	for index in _bones.size():
		var link: Array = LINKS[index]
		var bone := _bones[index]
		# Read after the parent link was turned, so a chain bends link by link.
		var pose := skeleton.get_bone_global_pose(bone)
		var origin := frame * pose.origin
		var clip_tail := pose * _tails[index]
		var target := frame * clip_tail
		var reach := target - origin
		var length := reach.length()
		if length < 0.0001:
			continue
		var point := _points[index]
		var velocity := _velocities[index]
		var snap := snap_all or clip_tail.distance_to(_clip_tails[index]) > TELEPORT * length
		_clip_tails[index] = clip_tail
		if snap:
			point = target
			velocity = Vector3.ZERO
		elif delta > 0.0:
			var stiffness: float = link[1]
			var damping: float = link[2]
			var push: Vector3 = world_wind * float(link[3])
			for _i in steps:
				velocity += ((target - point) * stiffness - velocity * damping + push) * step
				point += velocity * step
		# Keep the link's length and its largest swing; the cape also may not pass into the body.
		var aim := reach / length
		var arm := point - origin
		var heading := arm.normalized() if arm.length_squared() > 0.000001 else aim
		var angle := aim.angle_to(heading)
		var limit: float = link[4]
		if angle > limit:
			heading = aim.slerp(heading, limit / angle).normalized()
		if index < CAPE_LINKS:
			var forward := frame_basis.z * -1.0
			var most := minf(aim.dot(forward) + CAPE_FORWARD, 1.0)
			var lead := heading.dot(forward)
			if lead > most:
				var side := heading - forward * lead
				heading = forward * most + side.normalized() * sqrt(1.0 - most * most) if side.length_squared() > 0.000001 else aim
				velocity -= forward * maxf(velocity.dot(forward), 0.0)
		angle = aim.angle_to(heading)
		point = origin + heading * length
		# A taut link cannot stretch: drop the speed along it.
		velocity -= heading * velocity.dot(heading)
		_points[index] = point
		_velocities[index] = velocity
		_offsets[index] = point - target
		_swings[index] = angle * amount
		if not apply_pose or angle * amount < 0.0005:
			continue
		# Turn the bone from the clip direction to the simulated one, in skeleton space.
		var from := frame_basis.inverse() * aim
		var to := frame_basis.inverse() * heading
		var turn := Quaternion(from, to)
		if amount < 1.0:
			turn = Quaternion.IDENTITY.slerp(turn, amount)
		var parent_basis := skeleton.get_bone_global_pose(_parents[index]).basis.orthonormalized()
		var turned := Basis(turn) * pose.basis.orthonormalized()
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * turned).get_rotation_quaternion())
