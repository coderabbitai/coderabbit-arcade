extends SceneTree
## Endless Runner frame-time probe. Rendered runs only (headless does not draw):
## Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/runner_perf_probe.gd [-- seconds=60 seed=4242]
## Add -- boss_cinematic=true for the opt-in full intro and defeat capture across stages 1-3.
## Add -- run_intro=true to open the run on the full run intro (contract 2.7 §11.15) instead of
## opting out, and report its frames apart from gameplay, with each beat and the GO hand-over named.
## Plays an autopilot run from the runner menu's Play route and attributes every slow frame to what
## happened on it (pickup, chunk spawn, boss, stage). Writes a throwaway leaderboard only.
const HITCH_MS := 25.0
const BOSS_DRAW_BUDGET := 40
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const StageDefs = preload("res://scenes/runner/data/stage_defs.gd")
var seconds := 60.0
var run_seed := 4242
var boss_cinematic_probe := false
var run_intro_probe := false
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
		if parts.size() == 2 and parts[0] == "run_intro":
			run_intro_probe = parts[1].to_lower() in ["true", "1", "yes"]
	# call_deferred("run") is flushed by SaveService.apply_display() inside autoload _ready,
	# and root.add_child then fails because the tree is still setting children up. Wait until
	# that setup has finished.
	if root.is_node_ready():
		call_deferred("run")
	else:
		root.ready.connect(run, CONNECT_ONE_SHOT)

## The run intro is on by default. A duplicate keeps the shared .tres intact and opens on `run`.
func _opt_out_run_intro(game: Node) -> void:
	var source: Resource = game.config as Resource
	if source == null:
		source = load("res://scenes/runner/data/run_config.tres")
	var config := source.duplicate()
	config.set(&"run_intro_enabled", false)
	game.config = config

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
	# Frame times are the gameplay run unless run_intro=true asks for the intro too. This must not
	# edit the shared run_config.tres, so the flag lives on a duplicate assigned before _ready.
	if not run_intro_probe:
		_opt_out_run_intro(game)
	root.add_child(game)
	if not game.is_inside_tree():
		push_error("RUNNER PERF: runner was not added to the tree")
		quit(1)
		return
	print("RUNNER PERF: scene ready in %.0f ms" % ((Time.get_ticks_usec() - load_start) / 1000.0))
	game.power_up_collected.connect(func(kind, _d): _note("pickup:" + String(kind)))
	game.tool_collected.connect(func(kind, _d): _note("tool:" + String(kind)))
	game.chunk_spawned.connect(func(_c): _note("chunk"))
	game.phase_changed.connect(func(phase: StringName) -> void:
		if phase == &"boss":
			_note("boss-phase"))
	game.boss_spawned.connect(func(kind, _h): _note("boss:" + String(kind)))
	game.stage_started.connect(func(i, _n, _s): _note("stage:%d" % i))
	game.damage_taken.connect(func(kind, _h): _note("hit:" + String(kind)))
	game.pursuit_started.connect(func(_s): _note("pursuit"))
	if run_intro_probe:
		game.run_intro.connect(func(mode, _s): _note("intro:" + String(mode)))
		game.run_intro_beat.connect(func(_i, label): _note("intro-beat:" + String(label)))
		game.run_intro_skipped.connect(func(): _note("intro-skipped"))
		game.run_intro_ended.connect(func(): _note("intro-ended"))
		game.phase_changed.connect(func(phase: StringName) -> void:
			if phase == &"run" and events.has("intro-ended"):
				_note("intro-handover"))
		# A fresh run from the menu: the full intro (start_run consumes this).
		game.pending_intro_mode = &"full"
	game.start_run(run_seed)
	game.set_autopilot(true)
	var intro_spans: Array[float] = []
	var intro_marks: Array[String] = []
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
		var in_intro := run_intro_probe and (StringName(game.run_intro_mode) != &"" or events.has("intro-handover"))
		if in_intro:
			intro_spans.append(span)
			for what in events:
				if what.begins_with("intro"):
					intro_marks.append("%6.1f ms  %s" % [span, what])
		else:
			spans.append(span)
		if span > HITCH_MS:
			hitches.append("%6.1f ms  t=%5.1fs %s %s" % [span, game.elapsed, "[intro]" if in_intro else "",
				", ".join(events) if events.size() else "-"])
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
	if run_intro_probe:
		var intro_sorted := intro_spans.duplicate()
		intro_sorted.sort()
		var intro_total := 0.0
		for s in intro_spans: intro_total += s
		var intro_hitches := intro_spans.filter(func(s: float) -> bool: return s > HITCH_MS).size()
		if intro_sorted.is_empty():
			print("RUNNER PERF INTRO: no intro frames were measured")
		else:
			print("RUNNER PERF INTRO: frames=%d avg=%.2fms p50=%.1f p99=%.1f max=%.1f hitches(>%dms)=%d" % [
				intro_sorted.size(), intro_total / intro_sorted.size(), intro_sorted[intro_sorted.size() / 2],
				intro_sorted[int(intro_sorted.size() * 0.99)], intro_sorted.max(), int(HITCH_MS), intro_hitches])
		for line in intro_marks:
			print("RUNNER PERF INTRO BEAT ", line)
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
	_opt_out_run_intro(game)
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
			"particle_draws": 0, "label_draws": 0, "geometry_peak": 0, "render_peak": 0,
			"render_pair_samples": 0, "render_pair_invalid": 0, "boss_render_draws_peak": -1,
			"boss_render_with_at_peak": -1, "boss_render_without_at_peak": -1}
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
		var engine_draws := int(census.boss_render_draws_peak)
		var passed := defeat_samples > 0 and boss_draws > 0 and boss_draws <= BOSS_DRAW_BUDGET \
			and int(census.render_pair_samples) > 0 and int(census.render_pair_invalid) == 0 \
			and engine_draws > 0 and engine_draws <= BOSS_DRAW_BUDGET
		if not passed:
			failed = true
		var status := "PASS" if passed else "FAIL"
		var report := "RUNNER PERF BOSS CINEMATIC: %s stage=%d kind=%s accepted_hits=%d frames=%d defeat_samples=%d render_calls_peak=%d engine_boss_draw_delta_peak=%d (with=%d without=%d pairs=%d invalid=%d) boss_fx_draws_peak=%d (surfaces=%d multimesh_draws=%d multimeshes=%d particle_draws=%d labels=%d)" % [
			status, stage, kind, hits, sampled_frames, defeat_samples, int(census.render_peak), engine_draws,
			int(census.boss_render_with_at_peak), int(census.boss_render_without_at_peak),
			int(census.render_pair_samples), int(census.render_pair_invalid), boss_draws,
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
	var arena := game.get_node_or_null("World/TurnRig/BossArena") as Node3D
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
	_sample_boss_render_delta(arena, census)

## Force three synchronous draws without advancing the scene tree, so the full-frame counter
## isolates the mounted BossArena contribution from the same rendered pose and simulation tick.
func _sample_boss_render_delta(arena: Node3D, census: Dictionary) -> void:
	var originally_visible := arena.visible
	if not originally_visible:
		census.render_pair_invalid = int(census.render_pair_invalid) + 1
		return
	arena.visible = true
	RenderingServer.force_draw(false, 0.0)
	var with_boss := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	arena.visible = false
	RenderingServer.force_draw(false, 0.0)
	var without_boss := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	arena.visible = originally_visible
	RenderingServer.force_draw(false, 0.0)
	var restored := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	census.render_pair_samples = int(census.render_pair_samples) + 1
	var delta := with_boss - without_boss
	if with_boss <= 0 or without_boss < 0 or delta < 0 or restored != with_boss:
		census.render_pair_invalid = int(census.render_pair_invalid) + 1
		return
	if delta > int(census.boss_render_draws_peak):
		census.boss_render_draws_peak = delta
		census.boss_render_with_at_peak = with_boss
		census.boss_render_without_at_peak = without_boss

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
