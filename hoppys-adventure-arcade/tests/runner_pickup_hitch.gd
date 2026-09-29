extends SceneTree
## Gate: grabbing an item must never stall a frame. Rendered runs only (headless does not draw, so
## shader compiles and uploads would not show):
## Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/runner_pickup_hitch.gd [-- via_menu=1]
## Fresh process, nothing warmed by hand: every power-up kind is placed in Hoppy's lane during a live
## autopilot run and grabbed for the FIRST time. For each kind it records the worst frame from the
## pickup appearing to COLLECT_FRAMES after the grab. Fails if any frame exceeds LIMIT_MS.
## via_menu=1 first shows the runner menu for MENU_SECONDS (the normal route into a run).
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")
const LIMIT_MS := 25.0
const COLLECT_FRAMES := 20
const MENU_SECONDS := 4.0
const PLACE_Z := -9.0
const ATTEMPT_SECONDS := 4.0
var game: Node
var failures := 0
var last := 0
var via_menu := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "via_menu=1": via_menu = true
	# A window close or app quit request reaches AppRouter, which quits with code 0 a second later:
	# the run would end silently and look like a pass to anything reading only the exit code.
	root.close_requested.connect(func():
		print("PICKUP HITCH: ABORTED (window close / app quit requested before the gate finished)")
		quit(2))
	call_deferred("run")

func frame() -> float:
	await process_frame
	var now := Time.get_ticks_usec()
	var span := (now - last) / 1000.0
	last = now
	return span

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PICKUP HITCH: requires a graphical display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	last = Time.get_ticks_usec()
	if via_menu:
		var menu := (load("res://scenes/runner/runner_menu.tscn") as PackedScene).instantiate()
		root.add_child(menu)
		var until := Time.get_ticks_msec() + int(MENU_SECONDS * 1000)
		while Time.get_ticks_msec() < until:
			await frame()
		menu.queue_free()
		await frame()
	game = (load("res://scenes/runner/runner_game.tscn") as PackedScene).instantiate()
	game.autostart = false
	game.leaderboard_path = OS.get_temp_dir().path_join("runner_pickup_hitch_leaderboard.cfg")
	root.add_child(game)
	game.start_run(777)
	game.set_autopilot(true)
	# Let the run settle; start-up frames are the probe's business, not this gate's.
	for i in 90:
		await frame()
		if game.paused: game.resume()
	var collected := {}
	game.power_up_collected.connect(func(kind, _d): collected[kind] = true)
	var kinds: Array = PowerUpDefs.kinds()
	var worst_overall := 0.0
	for kind: StringName in kinds:
		var result := await _grab(kind, collected)
		if result < 0.0:
			failures += 1
			push_error("PICKUP HITCH: %s was never collected" % kind)
			continue
		worst_overall = maxf(worst_overall, result)
		var ok := result <= LIMIT_MS
		if not ok:
			failures += 1
		print("PICKUP HITCH %-16s worst frame %6.1f ms  %s" % [kind, result, "ok" if ok else "OVER %.0f ms" % LIMIT_MS])
	print("PICKUP HITCH: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures, worst %.1f ms, limit %.0f ms, via_menu=%s)" % [worst_overall, LIMIT_MS, via_menu])
	game.queue_free()
	await create_timer(0.3).timeout
	quit(failures)

# Place `kind` on a live chunk straight ahead of Hoppy; retry if the bot swerves or a hazard intervenes.
func _grab(kind: StringName, collected: Dictionary) -> float:
	var player: Node3D = game.player
	for attempt in 6:
		if game.state != &"running":
			game.start_run(778 + attempt)
			game.set_autopilot(true)
			for i in 30: await frame()
		var chunk := _chunk_at(PLACE_Z)
		if chunk == null:
			await frame()
			continue
		var pickup := (load("res://scenes/runner/powerups/power_up.tscn") as PackedScene).instantiate()
		pickup.kind = kind
		var spot := Vector3(player.global_position.x, float(game.config.pickup_height_run), PLACE_Z)
		# Measured from the frame the pickup appears: first-spawn art cost counts too.
		var worst := 0.0
		chunk.add_child(pickup)
		pickup.global_position = spot
		pickup.setup(game)
		pickup.reset_physics_interpolation()
		var after := -1
		# Time-bounded, not frame-bounded: at 4 ms frames 240 frames end before the pickup arrives.
		var deadline := Time.get_ticks_msec() + int(ATTEMPT_SECONDS * 1000)
		while Time.get_ticks_msec() < deadline:
			worst = maxf(worst, await frame())
			if game.paused:
				# The runner pauses itself when its window loses focus; this gate measures play, not that.
				game.resume()
			if collected.has(kind) and after < 0:
				after = 0
			if after >= 0:
				after += 1
				if after >= COLLECT_FRAMES:
					return worst
			if not is_instance_valid(pickup) or (pickup.global_position.z > 3.0 and after < 0):
				break
		if is_instance_valid(pickup) and not collected.has(kind):
			pickup.queue_free()
	return -1.0

# Nearest live chunk to z: the pickup rides it, exactly like a spawner-placed pickup.
func _chunk_at(z: float) -> Node3D:
	var best: Node3D = null
	for chunk in game.get_node("World/Chunks").get_children():
		var node := chunk as Node3D
		if node and node.is_inside_tree() and not node.is_queued_for_deletion() and (best == null or absf(node.global_position.z - z) < absf(best.global_position.z - z)):
			best = node
	return best
