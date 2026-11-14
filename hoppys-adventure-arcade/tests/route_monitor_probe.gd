extends SceneTree
## Per-route cost probe. Rendered runs only (headless draws nothing):
## Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/route_monitor_probe.gd [-- routes=hub,runner dwell=8 cap=60]
## Add --disable-vsync before --script for raw throughput (ms per frame with nothing to wait for).
## Opens every AppRouter route in turn, settles 2 s, then averages the engine's monitors over the
## dwell: fps, draw calls, primitives, objects, nodes, static and video memory, the physics step,
## plus how long the route took to open. `cap=60` sets Engine.max_fps first, the way a booth runs.
var routes: PackedStringArray = []
var dwell := 8.0
var cap := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2: continue
		match parts[0]:
			"routes": routes = parts[1].split(",", false)
			"dwell": dwell = float(parts[1])
			"cap": cap = int(parts[1])
	if root.is_node_ready(): call_deferred("run")
	else: root.ready.connect(run, CONNECT_ONE_SHOT)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("MON requires a graphical display")
		quit(1)
		return
	var router = root.get_node("AppRouter")
	if routes.is_empty():
		for route: String in router.ROUTES: routes.append(route)
	Engine.max_fps = cap
	print("MON window=%s vsync=%d max_fps=%d physics_tps=%d" % [DisplayServer.window_get_size(),
		DisplayServer.window_get_vsync_mode(), Engine.max_fps, Engine.physics_ticks_per_second])
	print("MON %-20s %6s %8s %7s %8s %7s %6s %8s %8s %8s" % ["route", "fps", "ms/frame", "phys_ms",
		"draws", "prims", "objs", "nodes", "stat_mb", "vid_mb"])
	for route in routes:
		var opened := Time.get_ticks_usec()
		if not await router.go(route):
			print("MON %s failed to open" % route)
			continue
		var load_ms := (Time.get_ticks_usec() - opened) / 1000.0
		var settle_end := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < settle_end: await process_frame
		var sums := {"phys": 0.0, "draws": 0.0, "prims": 0.0, "objs": 0.0}
		var frames := 0
		var started := Time.get_ticks_usec()
		while (Time.get_ticks_usec() - started) < dwell * 1e6:
			await process_frame
			frames += 1
			sums.phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			sums.draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			sums.prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			sums.objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var seconds := (Time.get_ticks_usec() - started) / 1e6
		print("MON %-20s %6.1f %8.2f %7.2f %8.0f %7.0f %6.0f %8d %8.1f %8.1f  open=%.0fms" % [route,
			frames / seconds, 1000.0 * seconds / frames, sums.phys / frames, sums.draws / frames,
			sums.prims / frames, sums.objs / frames,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, load_ms])
	await root.get_node("AudioService").settle()
	quit(0)
