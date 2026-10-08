extends SceneTree
## Frame-time probe. Run rendered (not headless) for meaningful numbers:
## Godot --always-on-top --path <project> --script res://tests/perf_probe.gd
## Reports wall-clock frame spans; a "hitch" is any frame longer than HITCH_MS.
const HITCH_MS := 20.0
var last := 0
var spans: Array[float] = []
func _initialize() -> void:
	call_deferred("run")
func tick() -> float:
	await process_frame
	var now := Time.get_ticks_usec()
	var span := (now - last) / 1000.0
	last = now
	spans.append(span)
	return span
func settle(count: int) -> void:
	for i in count: await tick()
	spans.clear()
func worst(count: int) -> float:
	var result := 0.0
	for i in count: result = maxf(result, await tick())
	return result
func report(name: String) -> void:
	var sorted := spans.duplicate()
	sorted.sort()
	var hitches := sorted.filter(func(s): return s > HITCH_MS).size()
	var p99: float = sorted[int(sorted.size() * 0.99)] if sorted.size() > 0 else 0.0
	print("PROBE %-18s frames=%4d max=%6.1fms p99=%5.1fms hitches=%d" % [name, sorted.size(), sorted.max() if sorted.size() else 0.0, p99, hitches])
	spans.clear()
func run() -> void:
	last = Time.get_ticks_usec()
	var router = root.get_node("AppRouter")
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await settle(30)
	# Menu showcase: every preview transition, twice (second pass shows reload cost).
	var showcase = current_scene.showcase
	showcase.set_process(false)
	for pass_index in 2:
		for i in 7:
			showcase.transition_to((i + 1) % 7, 0.3)
			await worst(24)
	report("menu_transitions")
	# Scene swap hub -> level.
	router.go("bay_area_blitz")
	await worst(60)
	report("swap_to_level")
	var level = current_scene
	var player = level.player
	level._resume()
	await settle(10)
	# Jumps in place: each jump plays a sound effect.
	for i in 6:
		Input.action_press("jump")
		await worst(3)
		Input.action_release("jump")
		await worst(55)
	report("jumps")
	# Every pickup kind, first time collected.
	var kinds := {}
	for item in level.pickups:
		if not kinds.has(item.kind): kinds[item.kind] = item
	for kind in kinds:
		var item: Dictionary = kinds[kind]
		player.position = item.node.position + Vector2(0, 30)
		player.velocity = Vector2.ZERO
		var frame_max := await worst(8)
		print("PROBE pickup %-14s worst frame=%6.1fms collected=%s" % [kind, frame_max, not is_instance_valid(item.node) or item.node.is_queued_for_deletion()])
	report("pickups")
	# Take a hit (hurt sound + empty heart texture).
	player.invulnerable = 0
	player.boost = 0
	player.shield = false
	player.position = Vector2(1320, 590)
	await worst(20)
	report("hit")
	# Run right with periodic jumps.
	player.position = Vector2(150, 590)
	player.hp = 3
	Input.action_press("move_right")
	for i in 480:
		if i % 50 == 0: Input.action_press("jump")
		if i % 50 == 20: Input.action_release("jump")
		var score_before: int = level.score
		var span := await tick()
		if span > HITCH_MS * 0.9:
			print("PROBE   slow frame %5.1fms at x=%d score_changed=%s on_floor=%s" % [span, int(player.position.x), level.score != score_before, player.is_on_floor()])
	Input.action_release("move_right")
	Input.action_release("jump")
	report("run_right")
	paused = false
	router.go("hub")
	await worst(60)
	report("swap_to_hub")
	await root.get_node("AudioService").settle()
	quit(0)
