extends SceneTree
## Cape and ear spring physics (scenes/runner/player/hifi/sway_rig.gd): the cloth and the ears lag
## behind lane changes and jumps, the cape overshoots and swings back, everything settles, the
## running air flutters the cape, and limits, snapping and the slide damping hold.
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
const TICK := 1.0 / 60.0
enum {CAPE, CAPE_TIP, EAR_L, EAR_TIP_L, EAR_R, EAR_TIP_R}
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SWAY: " + message)

## One simulated frame: the visual feeds the rig, then the rig runs without touching the bones.
func step(hoppy: Node3D, delta: float = TICK) -> void:
	hoppy._process(delta)
	hoppy._sway._process_modification()

func settle(hoppy: Node3D) -> void:
	hoppy._sway.settle()
	step(hoppy, 0.0)

func run() -> void:
	await process_frame
	root.get_node("AudioService").music.stop()
	var mover := Node3D.new()
	mover.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(mover)
	var hoppy := Hoppy.instantiate()
	mover.add_child(hoppy)
	hoppy.set_process(false)
	var player: AnimationPlayer = hoppy.animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	hoppy.set_anim_state(&"run")
	hoppy.set_run_speed(0.0)
	var sway: SkeletonModifier3D = hoppy._sway
	check(sway != null and sway.bound(), "sway rig bound to the cape and ear chains")
	check(hoppy.skeleton.get_child(hoppy.skeleton.get_child_count() - 1) == sway, "sway runs after the other modifiers")
	sway.apply_pose = false
	settle(hoppy)
	for link in 6:
		check(sway.swing(link) == 0.0 and sway.offset(link).length() < 0.0001, "settled link %d rests on the clip pose" % link)

	# Lane dash to the right (+X): 2 m in 0.18 s, eased. Cloth and ears trail to the left, then the
	# cape swings past the clip pose (overshoot) before it settles.
	var cape_lag := 0.0
	var ear_lag := 0.0
	for frame in 11:
		var t := minf(float(frame + 1) * TICK / 0.18, 1.0)
		mover.position.x = 2.0 * (1.0 - (1.0 - t) * (1.0 - t))
		step(hoppy)
		cape_lag = minf(cape_lag, sway.offset(CAPE_TIP).x)
		ear_lag = minf(ear_lag, sway.offset(EAR_TIP_L).x)
	var cape_overshoot := 0.0
	var ear_overshoot := 0.0
	for frame in 60:
		step(hoppy)
		cape_overshoot = maxf(cape_overshoot, sway.offset(CAPE_TIP).x)
		ear_overshoot = maxf(ear_overshoot, sway.offset(EAR_TIP_L).x)
	print("SWAY DASH: cape tip lag %.3f m, overshoot %.3f m; ear tip lag %.3f m, overshoot %.3f m" % [cape_lag, cape_overshoot, ear_lag, ear_overshoot])
	check(cape_lag < -0.06, "cape trails a lane dash")
	check(ear_lag < -0.01, "ears trail a lane dash")
	check(absf(ear_lag) < absf(cape_lag), "ears are stiffer than the cape")
	check(cape_overshoot > 0.02, "cape swings back past its rest after the dash")
	check(ear_overshoot > 0.002, "ears whip back after the dash")
	for frame in 240:
		step(hoppy)
	for link in 6:
		check(sway.offset(link).length() < 0.004, "link %d settles within 5 s: %.4f m" % [link, sway.offset(link).length()])

	# Jump: the body rises 1.2 m in 0.25 s; cape and ears are left below their clip pose.
	var cape_drop := 0.0
	var ear_drop := 0.0
	for frame in 15:
		mover.position.y = 1.2 * sin(float(frame + 1) / 15.0 * PI * 0.5)
		step(hoppy)
		cape_drop = minf(cape_drop, sway.offset(CAPE_TIP).y)
		ear_drop = minf(ear_drop, sway.offset(EAR_TIP_R).y)
	print("SWAY JUMP: cape tip %.3f m, ear tip %.3f m below the clip pose" % [cape_drop, ear_drop])
	# The cape already hangs straight down, so a taut link has little room to drop further.
	check(cape_drop < -0.01 and ear_drop < -0.015, "cape and ears drag down on take-off")
	check(sway.swing(EAR_L) > 0.0 or sway.swing(EAR_TIP_L) > 0.0, "physics reaches the ears on a jump")
	mover.position.y = 0.0
	settle(hoppy)

	# Running air: the cape streams back (+Z, behind Hoppy) and keeps fluttering.
	hoppy.set_run_speed(1.0)
	var low := INF
	var high := -INF
	var mean := 0.0
	for frame in 180:
		step(hoppy)
		if frame >= 60:
			low = minf(low, sway.offset(CAPE_TIP).z)
			high = maxf(high, sway.offset(CAPE_TIP).z)
			mean += sway.offset(CAPE_TIP).z / 120.0
	print("SWAY WIND: cape tip streams %.3f..%.3f m (mean %.3f) behind the clip pose" % [low, high, mean])
	check(mean > 0.03 and high - low > 0.02, "running air streams and flutters the cape")
	hoppy.set_run_speed(0.0)

	# The stride alone (no wind): the heavy cape lags behind it, the stiff ears ride it.
	settle(hoppy)
	var stride_cape := 0.0
	var stride_ear := 0.0
	for frame in 120:
		player.advance(TICK)
		step(hoppy)
		if frame >= 36:
			stride_cape = maxf(stride_cape, sway.swing(CAPE_TIP))
			stride_ear = maxf(stride_ear, maxf(sway.swing(EAR_L), sway.swing(EAR_TIP_L)))
	print("SWAY STRIDE: cape tip swings up to %.3f rad, ears up to %.3f rad" % [stride_cape, stride_ear])
	check(stride_cape > 0.05, "the cape swings behind the stride")
	check(stride_ear < 0.15, "the ears ride the stride without flopping")
	settle(hoppy)

	# A violent shove stays inside each link's limit and the cape never passes into the body.
	for shove: Vector3 in [Vector3(3, 0, 0), Vector3(-3, 2, 0), Vector3(0, 0, 3), Vector3(0, -2, -3)]:
		mover.position += shove
		step(hoppy)
		for link in 6:
			var limit: float = sway.LINKS[link][4]
			check(sway.swing(link) <= limit + 0.001 and is_finite(sway.offset(link).length()), "link %d inside its %.2f rad limit" % [link, limit])
		for link in [CAPE, CAPE_TIP]:
			var forward: float = sway.offset(link).dot(-hoppy.skeleton.global_basis.z.normalized())
			check(forward <= sway.CAPE_FORWARD * 0.36 + 0.001, "cape link %d held off the body: %.3f m forward" % [link, forward])
	mover.position = Vector3.ZERO

	# Slow frames below the snap deadline still settle stiff ears instead of hitting swing limits.
	for delta in [0.1, 0.2, 0.25]:
		settle(hoppy)
		mover.position.x += 0.02
		step(hoppy, delta)
		for frame in 30:
			step(hoppy, delta)
		for link in [EAR_L, EAR_TIP_L, EAR_R, EAR_TIP_R]:
			check(sway.offset(link).length() < 0.001, "ear %d settles with %.2f s frames" % [link, delta])

	# A long gap snaps instead of simulating; the slide damps the applied swing.
	step(hoppy, 1.0)
	check(sway.swing(CAPE) == 0.0 and sway.offset(CAPE_TIP).length() < 0.0001, "a long gap snaps the cloth to the clip pose")
	hoppy.set_anim_state(&"roll")
	for frame in 30:
		step(hoppy)
	check(is_equal_approx(sway.amount, hoppy.SWAY_ROLL_AMOUNT), "the slide damps the swing")
	hoppy.set_anim_state(&"run")
	for frame in 30:
		step(hoppy)
	check(is_equal_approx(sway.amount, 1.0), "the swing returns after the slide")

	# Live passes turn the bones but the skeleton restores the clip pose: nothing accumulates.
	sway.apply_pose = true
	hoppy.set_process(true)
	var cape_bone: int = hoppy.skeleton.find_bone("cape")
	var before: Quaternion = hoppy.skeleton.get_bone_pose_rotation(cape_bone)
	for frame in 6:
		mover.position.x += 0.3
		await process_frame
	check(hoppy.skeleton.get_bone_pose_rotation(cape_bone).is_equal_approx(before), "clip pose restored after live passes")
	check(sway.swing(CAPE) > 0.0, "live passes swing the cape")

	print("SWAY CHECK: %d checks, %d failures" % [checks, failures])
	await Cleanup.release(self, [mover])
	quit(0 if failures == 0 else 1)
