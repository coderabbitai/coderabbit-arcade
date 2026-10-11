extends SceneTree
## Contract 2.7 §11.15. The run intro in front of a fresh run, a retry and a boss checkpoint.
## Run with --path <project> --script res://tests/runner_run_intro.gd.

const GAME_SCENE := "res://scenes/runner/runner_game.tscn"
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
const SHOTS_PATH := "res://scenes/runner/data/run_intro_shots.gd"
const CAMERA_SCRIPT_PATH := "res://scenes/runner/systems/camera_rig.gd"
const FACADE_SCRIPT_PATH := "res://scenes/runner/runner_game.gd"
const TICK := 1.0 / 60.0
const FULL_SECONDS := 6.0
const SHORT_SECONDS := 2.2
const SKIP_AFTER := 0.3
const SKIP_TAIL := 0.4
const FULL_BEATS: Array[String] = ["title", "3", "2", "1", "GO!"]
const FULL_TIMES: Array[float] = [1.0, 3.0, 3.8, 4.6, 5.4]
const SHORT_BEATS: Array[String] = ["READY", "GO!"]
const SHORT_TIMES: Array[float] = [1.0, 1.6]
const REST: Array[float] = [1.0, 8.0, 4.0, 0.0, 60.0, 2.5]

const ROUTE_SOURCE := "extends \"res://scenes/runner/runner_game.gd\"\nvar routes: Array[String] = []\nfunc _route(route: String) -> void:\n\troutes.append(route)\n"

var failures := 0
var checks := 0
var board := "user://runner_run_intro_%d.cfg" % OS.get_process_id()
var facade_script: GDScript
var camera_script: GDScript
var route_script: GDScript

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER RUN INTRO: " + message)

func run() -> void:
	facade_script = load(FACADE_SCRIPT_PATH) as GDScript
	camera_script = load(CAMERA_SCRIPT_PATH) as GDScript
	check(facade_script != null and camera_script != null, "facade or camera script failed to load")
	if facade_script == null or camera_script == null:
		_finish()
		return
	_set_mode(&"full")
	check(_compile_route(), "the route recorder failed to compile")
	_test_shot_curve()
	await _test_full_intro()
	await _test_short_retry()
	await _test_checkpoint_retry()
	await _test_skip_window_and_jump()
	await _test_pause_and_endings()
	await _test_opt_out_and_direct_begin()
	_set_mode(&"full")
	_finish()

func _finish() -> void:
	if paused:
		paused = false
	Input.action_release("jump")
	Input.action_release("ui_accept")
	for suffix in ["", ".tmp", ".bak"]:
		var path := board + String(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if failures == 0:
		print("RUNNER RUN INTRO: PASS (%d checks)" % checks)
	else:
		print("RUNNER RUN INTRO: FAIL (%d failures / %d checks)" % [failures, checks])
	quit(0 if failures == 0 else 1)

# --- shots ------------------------------------------------------------------------

func _test_shot_curve() -> void:
	var constants: Dictionary = camera_script.get_script_constant_map()
	var fallback: Dictionary = constants.get("RUN_INTRO_FALLBACK_SHOTS", {})
	check(fallback.has(&"full") and fallback.has(&"short"), "fallback shots cover full and short")
	_assert_fallback_table(fallback)
	var file_exists := ResourceLoader.exists(SHOTS_PATH)
	_reset_shot_cache()
	var cold: Dictionary = camera_script.call(&"run_intro_shots")
	var cached: Dictionary = camera_script.call(&"run_intro_shots")
	check(float(cold.get(&"full", {}).get("ret", -1.0)) == float(cached.get(&"full", {}).get("ret", -2.0)),
		"run_intro_shots caches the table it read")
	if file_exists:
		var file_script := load(SHOTS_PATH) as Script
		var authored: Dictionary = {}
		if file_script != null:
			authored = file_script.get_script_constant_map().get("SHOTS", {})
		check(not authored.is_empty(), "run_intro_shots.gd has a SHOTS table")
		check(float(cold.get(&"full", {}).get("ret", -1.0)) == float(authored.get(&"full", {}).get("ret", -2.0)),
			"a reset cache reads the shots file, not the built-in table")
		print("RUNNER RUN INTRO: shot path is the frontend file")
		_assert_curve(cold)
	else:
		check(is_equal_approx(float(cold.get(&"full", {}).get("ret", -1.0)), float(fallback.get(&"full", {}).get("ret", -2.0))),
			"with no shots file, a reset cache uses the built-in table")
		var at_rest: Dictionary = camera_script.call(&"run_intro_shot", 1.0, &"full")
		_assert_pose(at_rest, REST, "fallback full at p=1")
		var short_rest: Dictionary = camera_script.call(&"run_intro_shot", 1.0, &"short")
		_assert_pose(short_rest, REST, "fallback short at p=1")
		print("RUNNER RUN INTRO: shot path is the built-in fallback")
		_assert_curve(cold)
	for mode in [&"", &"nope"]:
		var empty: Dictionary = camera_script.call(&"run_intro_shot", 0.4, mode)
		check(float(empty.get("blend", -1.0)) == 0.0, "blend is exactly 0 for mode %s" % mode)
		check(is_zero_approx(float(empty.get("distance", -1.0))) and is_zero_approx(float(empty.get("height", -1.0)))
			and is_zero_approx(float(empty.get("orbit", -1.0))) and is_zero_approx(float(empty.get("fov", -1.0)))
			and is_zero_approx(float(empty.get("look_bias", -1.0))),
			"an unknown intro shot is the zero pose (%s)" % mode)

func _assert_fallback_table(fallback: Dictionary) -> void:
	for mode in [&"full", &"short"]:
		var entry: Dictionary = fallback.get(mode, {})
		check(is_zero_approx(float(entry.get("cut", -1.0))), "%s fallback cut is 0" % mode)
		var keys: Array = entry.get("keys", [])
		check(not keys.is_empty(), "%s fallback has keys" % mode)
		if keys.is_empty():
			continue
		var last: Array = keys[keys.size() - 1]
		_assert_key(last, REST, "%s fallback rest key" % mode)
		for key in keys:
			var row: Array = key
			var lateral := absf(float(row[1]) * sin(deg_to_rad(float(row[3]))))
			check(lateral <= 3.4, "%s fallback key stays inside the corridor (lateral %.2f)" % [mode, lateral])
	var full_ret := float(fallback.get(&"full", {}).get("ret", 2.0))
	var short_ret := float(fallback.get(&"short", {}).get("ret", 2.0))
	check(is_equal_approx(full_ret, 0.86) and full_ret <= (FULL_SECONDS - SKIP_TAIL) / FULL_SECONDS,
		"full fallback ret %.3f stays at or below the skip landing" % full_ret)
	check(is_equal_approx(short_ret, 0.8) and short_ret <= (SHORT_SECONDS - SKIP_TAIL) / SHORT_SECONDS,
		"short fallback ret %.3f stays at or below the skip landing" % short_ret)

func _assert_curve(table: Dictionary) -> void:
	for mode in [&"full", &"short"]:
		var entry: Dictionary = table.get(mode, {})
		check(not entry.is_empty(), "active shots have %s" % mode)
		if entry.is_empty():
			continue
		var at0: Dictionary = camera_script.call(&"run_intro_shot", 0.0, mode)
		if is_zero_approx(float(entry.get("cut", -1.0))):
			check(float(at0.get("blend", -1.0)) == 1.0, "%s blend is 1 at p=0 when cut is 0" % mode)
		var at1: Dictionary = camera_script.call(&"run_intro_shot", 1.0, mode)
		check(float(at1.get("blend", -1.0)) == 0.0, "%s blend is exactly 0 at p=1" % mode)
		var keys: Array = entry.get("keys", [])
		if not keys.is_empty():
			_assert_pose(at1, keys[keys.size() - 1], "%s p=1 pose" % mode)

func _assert_key(key: Array, expected: Array, tag: String) -> void:
	check(key.size() >= expected.size(), "%s key is short" % tag)
	if key.size() < expected.size():
		return
	for column in expected.size():
		check(is_equal_approx(float(key[column]), float(expected[column])),
			"%s column %d is %.3f, expected %.3f" % [tag, column, float(key[column]), float(expected[column])])

func _assert_pose(shot: Dictionary, key: Array, tag: String) -> void:
	check(is_equal_approx(float(shot.get("distance", -1.0)), float(key[1]))
		and is_equal_approx(float(shot.get("height", -1.0)), float(key[2]))
		and is_equal_approx(float(shot.get("orbit", -1.0)), float(key[3]))
		and is_equal_approx(float(shot.get("fov", -1.0)), float(key[4]))
		and is_equal_approx(float(shot.get("look_bias", -1.0)), float(key[5])),
		"%s pose %s, expected %s" % [tag, [shot.get("distance"), shot.get("height"), shot.get("orbit"), shot.get("fov"), shot.get("look_bias")], key.slice(1)])

func _reset_shot_cache() -> void:
	camera_script.set(&"_run_intro_shots_read", false)
	camera_script.set(&"_run_intro_shots", {})

# --- full intro -------------------------------------------------------------------

func _test_full_intro() -> void:
	_set_mode(&"full")
	var game : Node = await _open(true)
	var log := _watch(game)
	var config: Resource = game.config
	check(is_equal_approx(float(config.get(&"run_intro_full_seconds")), FULL_SECONDS), "full intro is 6.0 s")
	check(is_equal_approx(float(config.get(&"run_intro_short_seconds")), SHORT_SECONDS), "short intro is 2.2 s")
	game.start_run(4242)
	check(_pending_mode() == &"full", "start_run puts pending_intro_mode back to full")
	check(game.state == &"running" and game.phase == &"intro", "a fresh run opens in the intro phase (%s)" % game.phase)
	check(game.run_intro_mode == &"full" and is_zero_approx(game.run_intro_progress), "the facade mirrors the full intro at 0")
	var opened: Array = log["intro"]
	check(opened.size() == 1 and StringName(opened[0][0]) == &"full" and is_equal_approx(float(opened[0][1]), FULL_SECONDS),
		"run_intro announced %s" % [opened])
	check(bool(game.stage_manager.cinematic_hold) and not bool(game.player.controls_enabled),
		"controls are held from the first intro frame")
	check(is_equal_approx(float(game.speed_controller.cinematic_scale), float(config.get(&"boss_cinematic_speed_scale"))),
		"the corridor snaps to the cinematic speed scale")
	check(game.camera_rig.intro_mode == &"full", "the camera rig takes the full intro")
	_assert_hud(game, true, "during the full intro")
	var chunks_before: int = game.spawner.get_active_chunks().size()
	var clock_before: float = game.run_clock
	_tick(game, 20)
	var chunks_after: int = game.spawner.get_active_chunks().size()
	check(chunks_after == chunks_before, "the spawner places nothing during the intro (%d -> %d)" % [chunks_before, chunks_after])
	check(is_equal_approx(game.run_clock, clock_before), "run_clock stays frozen during the intro")
	check(game.camera_rig.intro_mode == &"full" and game.camera_rig.intro_progress > 0.0
		and is_equal_approx(game.camera_rig.intro_progress, game.run_intro_progress),
		"set_run_intro keeps the rig on the facade's progress")
	var guard := _until_phase_changes(game, &"intro")
	check(guard > 0 and game.phase == &"run", "the full intro hands over to run (phase %s after %d ticks)" % [game.phase, guard])
	_assert_beats(log, FULL_BEATS, FULL_TIMES, "full")
	check(bool(log["victory"]), "the title beat plays Hoppy's victory pose")
	var stages: Array = log["stages"]
	check(stages.size() == 1 and int(stages[0]) == 1, "stage_started fired once for stage 1, got %s" % [stages])
	check(int(log["ended"]) == 1, "run_intro_ended fired %d times on a natural end" % int(log["ended"]))
	check(game.run_intro_mode == &"" and is_zero_approx(game.run_intro_progress), "the intro mirror clears at the end")
	check(game.camera_rig.intro_mode == &"" and is_zero_approx(game.camera_rig.intro_progress),
		"the camera rig drops the intro at the end")
	_assert_rest_pose(game)
	_assert_hud(game, false, "after the full intro")
	check(bool(game.player.controls_enabled) and not bool(game.stage_manager.cinematic_hold),
		"controls are live once the intro has handed over")
	_tick(game, 10)
	check(int(log["ended"]) == 1, "a finished intro does not emit run_intro_ended again")
	_close(game)

# --- short retry ------------------------------------------------------------------

func _test_short_retry() -> void:
	if route_script == null:
		return
	var recorder := _recorder()
	recorder.retry()
	var routes: Array = recorder.get("routes")
	check(routes.size() == 1 and String(routes[0]) == "runner_game", "retry() records runner_game, got %s" % [routes])
	check(_pending_mode() == &"short", "retry() asks for the short intro")
	var game : Node = await _open(true)
	var log := _watch(game)
	game.start_run(7)
	check(_pending_mode() == &"full", "the short intro is consumed and pending returns to full")
	check(game.phase == &"intro" and game.run_intro_mode == &"short", "the retry instance opens on the short intro")
	var opened: Array = log["intro"]
	check(opened.size() == 1 and StringName(opened[0][0]) == &"short" and is_equal_approx(float(opened[0][1]), SHORT_SECONDS),
		"run_intro announced %s for the retry" % [opened])
	_until_phase_changes(game, &"intro")
	check(game.phase == &"run", "the short intro hands over to run, got %s" % game.phase)
	_assert_beats(log, SHORT_BEATS, SHORT_TIMES, "short")
	check(not bool(log["victory"]), "the short intro has no title beat, so it does not celebrate")
	var stages: Array = log["stages"]
	check(stages.size() == 1 and int(stages[0]) == 1, "the short intro still announces stage 1 once, got %s" % [stages])
	check(int(log["ended"]) == 1, "the short intro ended once, got %d" % int(log["ended"]))
	_close(game)
	recorder.free()

func _test_checkpoint_retry() -> void:
	var recorder := _recorder()
	var checkpoint := {
		"stage_index": 1,
		"seed": 99,
		"run_clock": 4.5,
		"score_exact": 80.0,
		"score": 80,
		"elapsed": 4.5,
		"distance": 50.0,
	}
	recorder.boss_checkpoint = checkpoint.duplicate(true)
	recorder.retry_boss()
	var routes: Array = recorder.get("routes")
	check(routes.size() == 1 and String(routes[0]) == "runner_game", "retry_boss() records runner_game, got %s" % [routes])
	check(_pending_mode() == &"short", "retry_boss() asks for the short intro")
	var game : Node = await _open(true)
	var log := _watch(game)
	game.start_run(0)
	check(bool(game.checkpoint_retry), "the checkpoint retry is flagged")
	check(game.seed == 99, "the checkpoint retry keeps seed 99, got %d" % game.seed)
	check(game.phase == &"intro" and game.run_intro_mode == &"short",
		"a checkpoint retry opens on the short intro, got %s / %s" % [game.phase, game.run_intro_mode])
	check((log["stages"] as Array).is_empty(), "stage_started waits until the checkpoint intro ends")
	check(is_equal_approx(game.run_clock, 4.5), "run_clock is restored and frozen at %.3f" % game.run_clock)
	_tick(game, 10)
	check((log["stages"] as Array).is_empty() and is_equal_approx(game.run_clock, 4.5),
		"the checkpoint intro still holds stage_started and run_clock")
	_until_phase_changes(game, &"intro")
	var stages: Array = log["stages"]
	check(stages.size() == 1 and int(stages[0]) == 1, "stage_started fired once as the checkpoint intro ended, got %s" % [stages])
	check(game.phase == &"boss", "the checkpoint intro hands over to the boss, got %s" % game.phase)
	check(int(log["ended"]) == 1 and game.run_intro_mode == &"", "the checkpoint intro ended once")
	_close(game)
	recorder.free()

# --- skip, jump, pause, endings ---------------------------------------------------

func _test_skip_window_and_jump() -> void:
	var early : Node = await _open(true)
	_set_mode(&"full")
	var early_log := _watch(early)
	early.start_run(3)
	_press(early, "jump")
	_tick(early, 4)
	check(int(early_log["skipped"]) == 0 and early.phase == &"intro" and not early.can_skip_run_intro(),
		"a jump before 0.3 s does not skip")
	check(not bool(early.player.is_airborne) and early.player.velocity.y < 1.0, "that early press does not jump")
	_release_input()
	var refused := false
	while float(early.stage_manager._intro_clock) < SKIP_AFTER - 0.0001:
		check(not early.can_skip_run_intro() and not early.skip_run_intro(), "skip is refused before 0.3 s")
		refused = true
		_tick(early, 1)
		if float(early.stage_manager._intro_clock) > FULL_SECONDS:
			break
	check(refused and early.can_skip_run_intro(), "skip is accepted once 0.3 s have played")
	_close(early)

	var skipped : Node = await _open(true)
	_set_mode(&"full")
	var log := _watch(skipped)
	var order: Array = []
	skipped.run_intro_skipped.connect(func() -> void: order.append(&"skipped"))
	skipped.run_intro_beat.connect(func(_index: int, label: String) -> void: order.append(StringName(label)))
	skipped.start_run(4)
	_advance_to_window(skipped)
	var did: bool = skipped.skip_run_intro()
	check(did, "skip_run_intro accepts the press inside the window")
	check(bool(skipped.player.controls_enabled) and not bool(skipped.stage_manager.cinematic_hold),
		"a skip releases the hold before the tail plays out")
	check(not skipped.can_skip_run_intro() and not skipped.skip_run_intro(), "a second skip is refused")
	check(skipped.phase == &"intro", "the skip leaves the tail of the intro running")
	_until_phase_changes(skipped, &"intro")
	check(skipped.phase == &"run", "the skip tail hands over to run")
	check(int(log["skipped"]) == 1 and int(log["ended"]) == 1, "skip emits skipped once and ended once (%d / %d)"
		% [int(log["skipped"]), int(log["ended"])])
	check(order.size() == 2 and StringName(order[0]) == &"skipped" and StringName(order[1]) == &"GO!",
		"a skip emits run_intro_skipped then GO and nothing it jumped, got %s" % [order])
	var stages: Array = log["stages"]
	check(stages.size() == 1 and int(stages[0]) == 1, "the skipped intro still announces stage 1 once")
	_close(skipped)

	var tail : Node = await _open(true)
	_set_mode(&"full")
	tail.start_run(5)
	var tail_guard := 0
	# Step until the clock is on the tail. A sum of 1/60 can print as 5.600 while still a hair under
	# it, and that hair is still inside the window, so take the tick that lands past the boundary.
	while float(tail.stage_manager._intro_clock) + 0.000001 < FULL_SECONDS - SKIP_TAIL and tail_guard < 800:
		_tick(tail, 1)
		tail_guard += 1
	if tail.can_skip_run_intro():
		_tick(tail, 1)
	var tail_clock: float = float(tail.stage_manager._intro_clock)
	check(tail.phase == &"intro" and tail_clock >= FULL_SECONDS - SKIP_TAIL - 0.0001 and tail_clock < FULL_SECONDS
		and not tail.can_skip_run_intro() and not tail.skip_run_intro(),
		"skip is refused in the last 0.4 s (clock %.4f, phase %s)" % [tail_clock, tail.phase])
	_close(tail)

	await _assert_consumed_press("jump")
	await _assert_consumed_press("ui_accept")

func _assert_consumed_press(action: String) -> void:
	var game : Node = await _open(true)
	_set_mode(&"full")
	var log := _watch(game)
	var jumps := {"n": 0}
	game.player_action.connect(func(kind: StringName) -> void:
		if kind == &"jump":
			jumps["n"] += 1)
	game.start_run(6)
	_advance_to_window(game)
	var y0: float = game.player.global_position.y
	_press(game, action)
	game._unhandled_input(_action_event(action, true))
	_tick(game, 8)
	check(int(log["skipped"]) == 1, "%s inside the window skips the intro" % action)
	check(bool(game.player.controls_enabled), "%s releases controls at once" % action)
	check(int(jumps["n"]) == 0 and not bool(game.player.is_airborne) and game.player.velocity.y < 1.0
		and game.player.global_position.y <= y0 + 0.05,
		"%s was consumed and Hoppy stayed on the floor (airborne %s, y %.3f -> %.3f, vy %.3f, jumps %d)"
			% [action, game.player.is_airborne, y0, game.player.global_position.y, game.player.velocity.y, int(jumps["n"])])
	_release_input()
	_close(game)

func _test_pause_and_endings() -> void:
	var game : Node = await _open(true)
	_set_mode(&"full")
	var log := _watch(game)
	game.start_run(11)
	_advance_to_window(game)
	var progress: float = game.run_intro_progress
	var clock: float = game.stage_manager._intro_clock
	check(game.can_skip_run_intro(), "the pause sample is inside the skip window")
	game.pause()
	_tick(game, 20)
	check(game.paused and is_equal_approx(game.run_intro_progress, progress)
		and is_equal_approx(float(game.stage_manager._intro_clock), clock),
		"pause freezes run_intro_progress (%.4f -> %.4f)" % [progress, game.run_intro_progress])
	check(not game.can_skip_run_intro(), "skip is refused while the run is paused")
	game.resume()
	check(game.can_skip_run_intro(), "skip is available again once the run resumes")
	_tick(game, 3)
	check(game.run_intro_progress > progress + 0.001, "progress moves again after resume")
	_close(game)

	var restarted : Node = await _open(true)
	_set_mode(&"full")
	var restart_log := _watch(restarted)
	restarted.start_run(12)
	_tick(restarted, 30)
	check(restarted.phase == &"intro" and int(restart_log["ended"]) == 0, "the restart sample is still inside its intro")
	restarted.start_run(13)
	check(int(restart_log["ended"]) == 1, "start_run mid-intro emits run_intro_ended once, got %d" % int(restart_log["ended"]))
	check(restarted.phase == &"intro" and restarted.run_intro_mode == &"full",
		"the replacement run is a live full intro, got %s / %s" % [restarted.phase, restarted.run_intro_mode])
	_tick(restarted, 5)
	check(int(restart_log["ended"]) == 1, "the replacement intro has not ended yet")
	_close(restarted)

	var caught : Node = await _open(true)
	_set_mode(&"full")
	var catch_log := _watch(caught)
	caught.start_run(14)
	_tick(caught, 10)
	check(caught.phase == &"intro", "the catch sample is inside the intro")
	_report_hit(caught, &"bug_swarm")
	caught.hit_manager.iframe_remaining = 0.0
	_report_hit(caught, &"comment_flood")
	check(int(catch_log["ended"]) == 1, "a catch emits run_intro_ended once, got %d" % int(catch_log["ended"]))
	check(caught.phase == &"idle" and caught.run_intro_mode == &"", "a catch leaves the intro and goes idle (%s)" % caught.phase)
	_tick(caught, 5)
	check(int(catch_log["ended"]) == 1, "the catch path does not emit run_intro_ended again")
	_close(caught)

func _test_opt_out_and_direct_begin() -> void:
	_set_mode(&"full")
	var disabled : Node = await _open(false)
	var log := _watch(disabled)
	disabled.start_run(15)
	check(disabled.phase == &"run" and disabled.run_intro_mode == &"",
		"run_intro_enabled false opens on run, got %s / %s" % [disabled.phase, disabled.run_intro_mode])
	check((log["intro"] as Array).is_empty() and int(log["ended"]) == 0, "an opted-out run emits no intro signals")
	var stages: Array = log["stages"]
	check(stages.size() == 1 and int(stages[0]) == 1, "an opted-out run still announces stage 1")
	check(bool(disabled.player.controls_enabled), "an opted-out run starts with live controls")
	_close(disabled)

	_set_mode(&"")
	var cleared : Node = await _open(true)
	var cleared_log := _watch(cleared)
	cleared.start_run(16)
	check(_pending_mode() == &"full", "an empty pending mode is consumed back to full")
	check(cleared.phase == &"run" and cleared.run_intro_mode == &"" and (cleared_log["intro"] as Array).is_empty(),
		"pending_intro_mode empty opens with no intro, got %s" % cleared.phase)
	_close(cleared)

	var direct : Node = await _open(true)
	var direct_log := _watch(direct)
	direct.stage_manager.begin()
	check(direct.phase == &"run" and direct.run_intro_mode == &"" and (direct_log["intro"] as Array).is_empty(),
		"StageManager.begin() with no mode goes straight to run, got %s" % direct.phase)
	direct.stage_manager.begin_at_boss({"stage_index": 2, "seed": 3, "run_clock": 1.0})
	check(direct.phase == &"boss" and direct.run_intro_mode == &"" and (direct_log["intro"] as Array).is_empty(),
		"begin_at_boss() with no mode opens on the boss, got %s" % direct.phase)
	var direct_stages: Array = direct_log["stages"]
	check(direct_stages.size() == 2 and int(direct_stages[1]) == 2,
		"the direct boss open announces its stage, got %s" % [direct_stages])
	_close(direct)

# --- harness ----------------------------------------------------------------------

func _open(intro_enabled: bool) -> Node:
	if paused:
		paused = false
	var packed := load(GAME_SCENE) as PackedScene
	check(packed != null, "runner_game.tscn failed to load")
	if packed == null:
		return null
	var game := packed.instantiate()
	game.autostart = false
	var source: Resource = game.config as Resource
	if source == null:
		source = load(CONFIG_PATH)
	var config := source.duplicate()
	config.set(&"run_intro_enabled", intro_enabled)
	game.config = config
	game.leaderboard_path = board
	root.add_child(game)
	await physics_frame
	_quiet(game)
	return game

func _quiet(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)
	for child in node.get_children():
		_quiet(child)

func _close(game: Node) -> void:
	_release_input()
	if game != null and is_instance_valid(game):
		if bool(game.get("paused")):
			game.resume()
		game.free()
	if paused:
		paused = false

func _tick(game: Node, count: int) -> void:
	if game == null or not is_instance_valid(game):
		return
	for _i in count:
		game.speed_controller._physics_process(TICK)
		game.stage_manager._physics_process(TICK)
		game.camera_rig._physics_process(TICK)
		game.player._physics_process(TICK)
		game._physics_process(TICK)

func _until_phase_changes(game: Node, phase: StringName) -> int:
	var guard := 0
	while StringName(game.phase) == phase and guard < 900:
		_tick(game, 1)
		guard += 1
	return guard

func _advance_to_window(game: Node) -> void:
	var guard := 0
	while float(game.stage_manager._intro_clock) < SKIP_AFTER and guard < 80:
		_tick(game, 1)
		guard += 1

func _watch(game: Node) -> Dictionary:
	var log := {"intro": [], "beats": [], "skipped": 0, "ended": 0, "stages": [], "victory": false}
	game.run_intro.connect(func(mode: StringName, seconds: float) -> void:
		log["intro"].append([mode, seconds]))
	game.run_intro_beat.connect(func(index: int, label: String) -> void:
		var visual: Node = game.player.get("visual")
		if label == "title" and visual != null and StringName(visual.get(&"anim_state")) == &"victory":
			log["victory"] = true
		log["beats"].append([
			index, label, float(game.stage_manager.get(&"_intro_clock")),
			bool(game.player.controls_enabled), bool(game.stage_manager.cinematic_hold),
		]))
	game.run_intro_skipped.connect(func() -> void: log["skipped"] += 1)
	game.run_intro_ended.connect(func() -> void: log["ended"] += 1)
	game.stage_started.connect(func(index: int, _stage_name: StringName, _speed: float) -> void:
		log["stages"].append(index))
	return log

func _assert_beats(log: Dictionary, labels: Array[String], times: Array[float], tag: String) -> void:
	var beats: Array = log["beats"]
	check(beats.size() == labels.size(), "%s played %d beats, expected %d (%s)" % [tag, beats.size(), labels.size(), beats])
	if beats.size() != labels.size():
		return
	for index in labels.size():
		var row: Array = beats[index]
		var clock: float = float(row[2])
		check(int(row[0]) == index and String(row[1]) == labels[index],
			"%s beat %d is %s, expected %s" % [tag, index, row, [index, labels[index]]])
		check(clock + 0.0001 >= times[index] and clock < times[index] + TICK + 0.0001,
			"%s beat %s landed at %.4f s, expected %.3f within one tick" % [tag, labels[index], clock, times[index]])
		var last := index == labels.size() - 1
		check(bool(row[3]) == last and bool(row[4]) == (not last),
			"%s beat %s controls %s hold %s" % [tag, labels[index], row[3], row[4]])

func _assert_hud(game: Node, hidden: bool, tag: String) -> void:
	var hud := game.get_node_or_null("HUD/RunnerHud")
	check(hud != null, "RunnerHud is mounted")
	if hud == null:
		return
	if hidden:
		check(is_zero_approx(hud.widgets.modulate.a) and not hud.ready_panel.visible and not hud.get_ready.visible,
			"%s keeps the widgets and GET READY hidden" % tag)
	else:
		check(hud.ready_panel.visible and hud.get_ready.visible,
			"%s shows GET READY" % tag)

func _assert_rest_pose(game: Node) -> void:
	var camera := game.get_node("CameraRig/Camera") as Camera3D
	var rest: Vector3 = game.config.camera_position
	var look: Vector3 = game.config.camera_look_at
	check(camera.position.distance_to(rest) < 0.05,
		"the camera rests at %s, expected about %s" % [camera.position, rest])
	var dir := (look - rest).normalized()
	var pitch := atan2(dir.y, sqrt(dir.x * dir.x + dir.z * dir.z))
	check(absf(camera.rotation.x - pitch) < 0.01, "the camera pitch is %.2f deg, expected %.2f"
		% [rad_to_deg(camera.rotation.x), rad_to_deg(pitch)])
	check(absf(rad_to_deg(camera.rotation.x) - (-10.6)) < 0.3,
		"the rest pitch is about -10.6 deg, got %.2f" % rad_to_deg(camera.rotation.x))

func _report_hit(game: Node, kind: StringName) -> void:
	var hazard := Node3D.new()
	hazard.set(&"kind", kind)
	game.add_child(hazard)
	game.hit_manager.report_hit(hazard)

func _compile_route() -> bool:
	route_script = GDScript.new()
	route_script.source_code = ROUTE_SOURCE
	return route_script.reload() == OK

func _recorder() -> Node:
	var node := Node3D.new()
	root.add_child(node)
	node.set_script(route_script)
	return node

func _pending_mode() -> StringName:
	return StringName(facade_script.get(&"pending_intro_mode"))

func _set_mode(mode: StringName) -> void:
	facade_script.set(&"pending_intro_mode", mode)

func _press(game: Node, action: String) -> void:
	Input.action_press(action)
	Input.parse_input_event(_action_event(action, true))
	game._unhandled_input(_action_event(action, true))

func _action_event(action: String, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0
	return event

func _release_input() -> void:
	for action in ["jump", "ui_accept"]:
		if InputMap.has_action(action):
			Input.action_release(action)
			Input.parse_input_event(_action_event(action, false))
