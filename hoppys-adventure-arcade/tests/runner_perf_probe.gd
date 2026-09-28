extends SceneTree
## Endless Runner frame-time probe. Rendered runs only (headless does not draw):
## Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/runner_perf_probe.gd [-- seconds=60 seed=4242]
## Plays an autopilot run from the runner menu's Play route and attributes every slow frame to what
## happened on it (pickup, chunk spawn, turn, boss, stage). Writes a throwaway leaderboard only.
const HITCH_MS := 25.0
var seconds := 60.0
var run_seed := 4242
var game: Node
var events: Array[String] = []
var counts := {}
var spans: Array[float] = []
var hitches: Array[String] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() == 2 and parts[0] == "seconds": seconds = float(parts[1])
		if parts.size() == 2 and parts[0] == "seed": run_seed = int(parts[1])
	call_deferred("run")

func _note(what: String) -> void:
	events.append(what)
	counts[what] = int(counts.get(what, 0)) + 1

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("RUNNER PERF: requires a graphical display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var load_start := Time.get_ticks_usec()
	game = (load("res://scenes/runner/runner_game.tscn") as PackedScene).instantiate()
	game.autostart = false
	game.leaderboard_path = OS.get_temp_dir().path_join("runner_perf_probe_leaderboard.cfg")
	root.add_child(game)
	print("RUNNER PERF: scene ready in %.0f ms" % ((Time.get_ticks_usec() - load_start) / 1000.0))
	game.power_up_collected.connect(func(kind, _d): _note("pickup:" + String(kind)))
	game.tool_collected.connect(func(kind, _d): _note("tool:" + String(kind)))
	game.chunk_spawned.connect(func(_c): _note("chunk"))
	game.turn_started.connect(func(_d, _s): _note("turn"))
	game.boss_spawned.connect(func(kind, _h): _note("boss:" + String(kind)))
	game.stage_started.connect(func(i, _n, _s): _note("stage:%d" % i))
	game.damage_taken.connect(func(kind, _h): _note("hit:" + String(kind)))
	game.pursuit_started.connect(func(_s): _note("pursuit"))
	game.start_run(run_seed)
	game.set_autopilot(true)
	var last := Time.get_ticks_usec()
	var first := true
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		events.clear()
		await process_frame
		var now := Time.get_ticks_usec()
		var span := (now - last) / 1000.0
		last = now
		if game.state != &"running":
			game.start_run(run_seed + 1)
			game.set_autopilot(true)
			continue
		if first:
			first = false
			print("RUNNER PERF: first frame %.1f ms" % span)
			continue
		spans.append(span)
		if span > HITCH_MS:
			hitches.append("%6.1f ms  t=%5.1fs  %s" % [span, game.elapsed, ", ".join(events) if events.size() else "-"])
	var sorted := spans.duplicate()
	sorted.sort()
	var total := 0.0
	for s in spans: total += s
	print("RUNNER PERF: frames=%d avg=%.2fms p50=%.1f p99=%.1f p999=%.1f max=%.1f hitches(>%dms)=%d" % [
		sorted.size(), total / maxf(1, sorted.size()), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.99)],
		sorted[int(sorted.size() * 0.999)], sorted.max(), int(HITCH_MS), hitches.size()])
	for line in hitches.slice(0, 40):
		print("RUNNER PERF HITCH ", line)
	print("RUNNER PERF events: ", counts)
	game.queue_free()
	await create_timer(0.3).timeout
	quit(0)
