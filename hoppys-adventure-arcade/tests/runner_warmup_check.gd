extends SceneTree
## W3 warm-up check (headless). A directly launched runner_game.tscn must finish every prewarm job
## inside its own _ready (bind), so no package is finalized during play and every cue, including
## the pickup SFX, is cached before the first pickup can spawn. The GPU warm-up stage must mount
## every runtime visual batch cleanly and leave nothing behind. Headless cannot compile shaders, so
## the forced draws themselves are measured by tests/runner_pickup_hitch.gd (rendered).
## Run with --path <project> --script res://tests/runner_warmup_check.gd.
## Scripts are loaded at run time: under --script this is compiled before the autoloads exist.
const GAME_PATH := "res://scenes/runner/runner_game.tscn"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RUNNER WARMUP: " + message)

func run() -> void:
	await process_frame
	var Prewarm: Script = load("res://scenes/runner/environment/hifi/prewarm.gd")
	var Synth: Script = load("res://scenes/runner/audio/sfx_synth.gd")
	var GpuWarmup: Script = load("res://scenes/runner/warmup/gpu_warmup.gd")
	check(Prewarm.get("runs") == 0, "fresh process starts cold")
	var game: Node = (load(GAME_PATH) as PackedScene).instantiate()
	game.autostart = false
	game.leaderboard_path = OS.get_temp_dir().path_join("runner_warmup_check_leaderboard.cfg")
	var started := Time.get_ticks_usec()
	root.add_child(game)
	print("RUNNER WARMUP: direct scene ready %.0f ms (finish %.0f ms)" % [(Time.get_ticks_usec() - started) / 1000.0, Prewarm.get("finish_ms")])
	check(Prewarm.call("is_complete"), "prewarm complete after bind, before the first frame")
	check(not process_frame.is_connected(Callable(Prewarm, "poll")), "poll disconnected once complete")
	check(Prewarm.get("generated_on_workers"), "audio and images generated on workers")
	check(Prewarm.get("finalized_on_main"), "finalized on main")
	var cache: Dictionary = Synth.get("_cache")
	for kind: StringName in Synth.get("RECIPES"):
		check(cache.has(kind), "cue cached before play: " + kind)
	for kind in [&"powerup", &"nitro", &"lgtm", &"auto_fix", &"tool_pickup", &"shield_block"]:
		check(cache.has(kind), "pickup cue cached before play: " + kind)
	for kind in [&"projectile_whoosh", &"turn_whoosh"]:
		for mask in 8:
			check(cache.has(StringName("%s_pan_%d" % [kind, mask])), "panned %s %d cached" % [kind, mask])
	for surface in 3:
		for strike in 2:
			check(cache.has(StringName("footstep_surface_%d_variant_%d" % [surface, strike])), "footstep variant cached")
	# Identity: a later on-demand call returns the stream prewarm installed.
	check(Synth.call("sound", &"lgtm") == cache[&"lgtm"], "installed stream identity kept")
	# Headless: the guard is spent once and the forced draws are skipped.
	check(GpuWarmup.get("done"), "GPU warm-up guard set by the first bind")
	check(not GpuWarmup.call("run", game), "GPU warm-up runs once per process")
	check(game.get_node_or_null("GpuWarmup") == null, "no stage left in the game")
	game.start_run(4242)
	var before: int = game.get_child_count()
	# Mount every batch the rendered warm-up draws, tick it, then clear it.
	var camera := Camera3D.new()
	root.add_child(camera)
	var stage: Node3D = GpuWarmup.call("stage_for", game, camera)
	var census: Dictionary = GpuWarmup.get("census")
	census.clear()
	for batch: StringName in GpuWarmup.call("batches"):
		stage.call("build", batch)
		for i in 2: await process_frame
		check(stage.get_child_count() == 2, "batch %s mounted into one group" % batch)
		stage.call("clear")
		check(stage.get_child_count() == 1, "batch %s cleared" % batch)
	var expected := {"pickup": 20, "burst": 2, "hazard": 34, "boss": 6, "boss_fx": 5, "pursuer": 2, "hoppy": 2, "canvas": 1}
	for category in expected:
		check(int(census.get(category, 0)) >= expected[category], "%s mounted (%d)" % [category, census.get(category, 0)])
	print("RUNNER WARMUP census: ", census)
	stage.free()
	camera.free()
	# Collect bursts detach to the scene root by design (they outlive the pickup); nothing else may.
	var extra: Array[String] = []
	for i in range(before, game.get_child_count()):
		if not game.get_child(i) is GPUParticles3D: extra.append(game.get_child(i).name)
	check(extra.is_empty(), "stage leaves the game tree as it found it: %s" % [extra])
	check(game.state == &"running", "run still live after staging")
	game.free()
	var Cleanup: Script = load("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
	await Cleanup.call("release", self, [] as Array[Node])
	if failures == 0: print("RUNNER WARMUP: PASS (%d checks)" % checks)
	else: print("RUNNER WARMUP: FAIL (%d failures / %d checks)" % [failures, checks])
	quit(0 if failures == 0 else 2)
