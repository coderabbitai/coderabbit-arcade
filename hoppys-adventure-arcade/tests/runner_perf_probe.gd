extends SceneTree
## Endless Runner frame-time probe. Rendered runs only (headless does not draw):
## Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/runner_perf_probe.gd [-- seconds=60 seed=4242]
## Add -- boss_cinematic=true for the opt-in full intro and defeat capture across stages 1-3.
## Plays an autopilot run from the runner menu's Play route and attributes every slow frame to what
## happened on it (pickup, chunk spawn, turn, boss, stage). Writes a throwaway leaderboard only.
const HITCH_MS := 25.0
const BOSS_DRAW_BUDGET := 40
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const StageDefs = preload("res://scenes/runner/data/stage_defs.gd")
var seconds := 60.0
var run_seed := 4242
var boss_cinematic_probe := false
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
		if parts.size() == 2 and parts[0] == "boss_cinematic":
			boss_cinematic_probe = parts[1].to_lower() in ["true", "1", "yes"]
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
	if boss_cinematic_probe:
		await _run_boss_cinematic_probe()
		return
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
		if game.paused:
			# The runner pauses itself when its window loses focus; this probe measures play.
			game.resume()
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

## Explicit boss presentation mode. It keeps the real RunnerGame, BossEncounter, mounted visuals,
## FX, HUD and camera, but jumps directly to stages 1-3 so each cinematic can be measured promptly.
func _run_boss_cinematic_probe() -> void:
	var load_start := Time.get_ticks_usec()
	game = (load("res://scenes/runner/runner_game.tscn") as PackedScene).instantiate()
	game.autostart = false
	game.leaderboard_path = OS.get_temp_dir().path_join("runner_perf_probe_boss_cinematic_%d.cfg" % Time.get_ticks_msec())
	root.add_child(game)
	await process_frame
	print("RUNNER PERF BOSS CINEMATIC: scene ready in %.0f ms" % ((Time.get_ticks_usec() - load_start) / 1000.0))
	game.start_run(run_seed)
	var manager: Node = game.stage_manager
	var encounter: Node = game.boss_encounter
	var failed := false
	for stage in range(1, 4):
		manager.stage_index = stage
		manager.stage_name = StageDefs.boss_name(stage)
		manager._publish()
		manager._enter_boss()
		var expected_kind: StringName = BossDefs.boss_kind(stage)
		var kind: StringName = encounter.kind
		var intro_mode: StringName = encounter.cinematic_mode
		if kind != expected_kind or intro_mode != &"intro_full":
			push_error("RUNNER PERF BOSS CINEMATIC: stage %d opened %s / %s, expected %s / intro_full" % [stage, kind, intro_mode, expected_kind])
			failed = true
		var census := {"surfaces": 0, "multimesh_draws": 0, "multimesh_instances": 0,
			"particle_draws": 0, "label_draws": 0, "geometry_peak": 0, "render_peak": 0}
		var sampled_frames := 0
		var defeat_samples := 0
		var saw_defeat := false
		var steps := 0
		while encounter.cinematic_mode in [&"intro_full", &"defeat_full"] and steps < 1200:
			await _probe_frame(encounter, manager)
			if encounter.cinematic_mode == &"defeat_full": saw_defeat = true
			if saw_defeat: defeat_samples += 1
			_sample_render_and_geometry(census)
			sampled_frames += 1
			steps += 1
		if encounter.cinematic_mode != &"":
			push_error("RUNNER PERF BOSS CINEMATIC: stage %d intro did not end inside the frame guard" % stage)
			failed = true
		# Exercise actual accepted tool damage and the regular boss_defeated -> defeat cinematic path.
		var hits := 0
		while int(encounter.hp) > 0 and hits < 32:
			var accepted: Array[StringName] = BossDefs.accepted_tools(encounter.def, int(encounter.phase))
			var tool_kind: StringName = accepted[0] if not accepted.is_empty() else ToolDefs.kinds()[0]
			encounter.apply_tool(tool_kind)
			hits += 1
		if int(encounter.hp) > 0 or encounter.cinematic_mode != &"defeat_full":
			push_error("RUNNER PERF BOSS CINEMATIC: stage %d did not reach a real defeat after %d accepted tools" % [stage, hits])
			failed = true
		saw_defeat = encounter.cinematic_mode == &"defeat_full"
		steps = 0
		while not bool(encounter.finished) and steps < 1200:
			await _probe_frame(encounter, manager)
			if encounter.cinematic_mode == &"defeat_full": saw_defeat = true
			if saw_defeat: defeat_samples += 1
			_sample_render_and_geometry(census)
			sampled_frames += 1
			steps += 1
		if not bool(encounter.finished):
			push_error("RUNNER PERF BOSS CINEMATIC: stage %d defeat did not finish inside the frame guard" % stage)
			failed = true
		var boss_draws := int(census.geometry_peak)
		var passed := defeat_samples > 0 and boss_draws > 0 and boss_draws <= BOSS_DRAW_BUDGET
		if not passed:
			failed = true
		var status := "PASS" if passed else "FAIL"
		var report := "RUNNER PERF BOSS CINEMATIC: %s stage=%d kind=%s accepted_hits=%d frames=%d defeat_samples=%d render_calls_peak=%d boss_fx_draws_peak=%d (surfaces=%d multimesh_draws=%d multimeshes=%d particle_draws=%d labels=%d)" % [
			status, stage, kind, hits, sampled_frames, defeat_samples, int(census.render_peak), boss_draws,
			int(census.surfaces), int(census.multimesh_draws), int(census.multimesh_instances),
			int(census.particle_draws), int(census.label_draws)]
		print(report)
	game.queue_free()
	await create_timer(0.3).timeout
	print("RUNNER PERF BOSS CINEMATIC: %s (boss+FX budget <=%d per defeat; defeat samples required >0)" % ["FAIL" if failed else "PASS", BOSS_DRAW_BUDGET])
	quit(1 if failed else 0)

func _probe_frame(encounter: Node, manager: Node) -> void:
	if game.paused: game.resume()
	await process_frame
	# RunnerGame owns the regular physics tick. This keeps real pose/FX/audio updates and only
	# explicitly refreshes the camera in case a host's render cadence misses a physics step.
	if encounter.cinematic_mode != &"":
		manager._apply_boss_camera()
	var arena := game.get_node("World/TurnRig/BossArena") as Node
	var fx := arena.get_node_or_null("BossFX")
	if fx != null and fx.has_method("_process"): fx._process(0.0)
	await RenderingServer.frame_post_draw

func _sample_render_and_geometry(census: Dictionary) -> void:
	var arena := game.get_node_or_null("World/TurnRig/BossArena") as Node
	if arena == null: return
	var current := {"surfaces": 0, "multimesh_draws": 0, "multimesh_instances": 0,
		"particle_draws": 0, "label_draws": 0}
	_count_boss_draws(arena, current)
	var draws := _draw_total(current)
	if draws > int(census.geometry_peak):
		for key in current: census[key] = current[key]
		census.geometry_peak = draws
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if calls > int(census.render_peak): census.render_peak = calls

func _count_boss_draws(node: Node, tally: Dictionary) -> void:
	if (node is Node3D or node is CanvasItem) and not node.is_visible_in_tree(): return
	if node is Label3D:
		var label_3d := node as Label3D
		if not label_3d.text.is_empty():
			tally.label_draws = int(tally.label_draws) + (2 if label_3d.outline_size > 0 else 1)
	elif node is Label:
		if not (node as Label).text.is_empty(): tally.label_draws = int(tally.label_draws) + 1
	elif node is MultiMeshInstance3D:
		var instance := node as MultiMeshInstance3D
		if instance.multimesh != null and instance.multimesh.mesh != null \
				and instance.multimesh.visible_instance_count != 0:
			tally.multimesh_instances = int(tally.multimesh_instances) + 1
			tally.multimesh_draws = int(tally.multimesh_draws) + _surface_passes(instance, instance.multimesh.mesh.get_surface_count())
	elif node is GPUParticles3D:
		var particles := node as GPUParticles3D
		for pass_index in int(particles.get("draw_passes")):
			var mesh := particles.get_draw_pass_mesh(pass_index)
			if mesh != null: tally.particle_draws = int(tally.particle_draws) + _surface_passes(particles, mesh.get_surface_count())
	elif node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null: tally.surfaces = int(tally.surfaces) + _surface_passes(mesh_instance, mesh_instance.mesh.get_surface_count())
	for child in node.get_children(): _count_boss_draws(child, tally)

func _surface_passes(instance: GeometryInstance3D, surface_count: int) -> int:
	return surface_count * (2 if instance.material_overlay != null else 1)

func _draw_total(tally: Dictionary) -> int:
	return int(tally.surfaces) + int(tally.multimesh_draws) + int(tally.particle_draws) + int(tally.label_draws)
