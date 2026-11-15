extends SceneTree
## How long the Endless Runner takes to open, stage by stage. Rendered runs only:
## Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/runner_open_probe.gd [-- idle=true]
## Opens the runner menu and then the game straight from the hub, printing each route's total open
## time (two 250 ms veil fades included) next to the GPU warm-up's stage build and forced-draw time
## and the CPU prewarm. With idle=true it first sits on the hub until the background warm-up pass
## (scenes/runner/warmup/background_warm.gd, which --script runs otherwise skip) has finished, so
## the numbers are a booth's after the hub has idled; the worst hub frame during the pass is printed.
const GpuWarmup = preload("res://scenes/runner/warmup/gpu_warmup.gd")
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const BackgroundWarm = preload("res://scenes/runner/warmup/background_warm.gd")
const PASS_TIMEOUT := 120.0
var idle := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() == 2 and parts[0] == "idle": idle = parts[1].to_lower() in ["true", "1", "yes"]
	if root.is_node_ready(): call_deferred("run")
	else: root.ready.connect(run, CONNECT_ONE_SHOT)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("RUNNER OPEN requires a graphical display")
		quit(1)
		return
	var router = root.get_node("AppRouter")
	await router.go("hub")
	if idle:
		var warm = BackgroundWarm.new(router.ROUTES["hub"])
		router.add_child(warm)
		var started := Time.get_ticks_msec()
		var worst := 0.0
		var last := Time.get_ticks_usec()
		var frames := 0
		while is_instance_valid(warm) and Time.get_ticks_msec() - started < PASS_TIMEOUT * 1000.0:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			frames += 1
		print("RUNNER OPEN hub idled %.1f s (%d frames, worst %.0f ms) for the background pass; finished=%s" % [
			(Time.get_ticks_msec() - started) / 1000.0, frames, worst, not is_instance_valid(warm)])
	for route in ["runner", "runner_game"]:
		var opened := Time.get_ticks_usec()
		await router.go(route)
		print("RUNNER OPEN %-12s %5.0f ms total; own warm-up build %4.0f ms, draw %4.0f ms; prewarm %3.0f ms" % [
			route, (Time.get_ticks_usec() - opened) / 1000.0, GpuWarmup.build_ms, GpuWarmup.draw_ms, Prewarm.elapsed_ms])
		var settle_end := Time.get_ticks_msec() + 1500
		while Time.get_ticks_msec() < settle_end: await process_frame
	await root.get_node("AudioService").settle()
	quit(0)
