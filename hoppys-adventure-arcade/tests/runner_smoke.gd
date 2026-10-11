extends SceneTree
## Endless Runner end-to-end smoke test (systems spec §8). One real runner_game.tscn session driven
## by the autopilot at Engine.time_scale 6, then the routing round trip.
## Run with --path <project> --script res://tests/runner_smoke.gd.

## Only scripts that never reach runner_game.gd can be preloaded: under --script this test is
## compiled before the autoloads exist (see tests/runner_logic.gd).
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const GAME_PATH := "res://scenes/runner/runner_game.tscn"
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
const SEED := 12345
const TIME_SCALE := 6.0
const PROJECTILE_SCENE := "res://scenes/runner/hazards/projectile.tscn"
const ARENA_PATH := "World/TurnRig/BossArena"
## Autopilot policies (systems spec §8).
const PREFER_LANE := 0
const GREEDY_PICKUP := 2
## Run phases, in game seconds.
const CLEAN_SECONDS := 50.0
const RAMP_SECONDS := 20.0
const DAMAGE_WINDOW := 14.0
## Long enough for an ignored slice to travel from the scan horizon into the player.
const PASS_SECONDS := 6.0
const BLAST_QUIET_SECONDS := 2.0
const PAUSE_SECONDS := 1.0
## Wall-clock ceiling for any wait, so a stuck run fails instead of hanging.
const WALL_TIMEOUT := 40.0
## Systems spec §10.8 shortened stage: 260 m of RUN phase instead of the authored 900, so a whole
## seam (run -> boss -> stage clear -> run) fits inside the smoke run.
const STAGE_DISTANCE := 260.0
## The stage-1 boss the shortened config opens on: its authored 100 hp times boss_hp_scale, which
## the smoke config drops to BOSS_HP_SCALE so the fight fits inside the wall clock.
const BOSS_HP_SCALE := 0.4
const SMOKE_BOSS_HP := 40
## Wall-clock ceilings for the two v2 phases. The stage seam is the long one: a 260 m run, the
## drain, the 5 s boss intro, the fight, the 3.6 s defeat and the card. Every wait below
## carries its own copy of this budget, and at TIME_SCALE 6 it buys 240 game seconds each — so the
## contract 2.6 cinematics (8.6 game seconds, under a wall-clock second and a half) need no more
## room here.
const STAGE_WALL_TIMEOUT := 40.0
const BOSS_WALL_TIMEOUT := 20.0

## Godot 4.7 runs the same 60 physics ticks per second under a raised time_scale and simply makes
## each delta 6x longer, which would break the 0.10 s jump buffer and let hazards tunnel. Raising
## the tick rate alongside it keeps the per-tick delta at the real 1/60 s and still runs the game
## six times faster than the wall clock.
const PHYSICS_TICKS := 360

var failures := 0
var checks := 0
var game: Node3D
var events := {}
var restore_steps := 8
var restore_ticks := 60
var restore_scale := 1.0
## True while stage-entrance windows are still worth watching: the reckless and catch phases take
## damage on purpose, so they close the watch before they start (contract §11.1).
var banner_watch := true
## Throwaway board for this run, deleted in _report(): a smoke run must never write entries to the
## player's real user://leaderboard.cfg.
var leaderboard_path := "user://smoke_leaderboard_%d.cfg" % (randi() % 1000000)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER SMOKE: " + message)
		_dump_run()

func run() -> void:
	# All three are captured before they are touched and put back in _report(), which every exit
	# path — including the early returns below and any failing check — goes through.
	restore_steps = Engine.max_physics_steps_per_frame
	restore_ticks = Engine.physics_ticks_per_second
	restore_scale = Engine.time_scale
	Engine.time_scale = TIME_SCALE
	Engine.max_physics_steps_per_frame = 32
	Engine.physics_ticks_per_second = PHYSICS_TICKS
	if not ResourceLoader.exists(GAME_PATH):
		check(false, "runner_game.tscn does not exist")
		await _report()
		return
	var packed := load(GAME_PATH) as PackedScene
	check(packed != null, "runner_game.tscn failed to load")
	if packed == null:
		await _report()
		return
	game = packed.instantiate() as Node3D
	game.autostart = false
	game.config = _smoke_config()
	game.leaderboard_path = leaderboard_path
	root.add_child(game)
	await process_frame
	_watch()
	# The stage-entrance windows are read on the physics tick they end on, which no `await` in the
	# phases below lands on; the sampler is what catches that exact moment.
	physics_frame.connect(_sample_banner_windows)
	game.start_run(SEED)
	check(game.state == &"running", "start_run did not go live")
	check(game.seed == SEED, "the run did not take the seed it was given")

	# The key test runs first, while the run-in ahead of the first chunk is still empty: a real
	# jump takes 0.70 s with the bot switched off, and that is not a safe thing to do mid-corridor.
	await _input_phase()
	# Then the v2 seam, from the top of stage 1 (systems spec §10.8): every later phase runs on
	# whatever the stage machine happens to be doing, so this is the one that gets a clean stage 1.
	await _stage_phase()
	await _clean_phase()
	await _auto_fix_phase()
	await _pause_phase()
	await _pursuit_phase()
	await _catch_phase()
	_banner_phase()
	_leaderboard_phase()
	game.free()
	game = null
	await process_frame
	# After the main game is freed and before routing builds another one: the probes below need to be
	# the only RunnerGame in the tree, because Area3D overlaps are resolved in one shared physics
	# world and a second game's chunks sit on the same coordinates.
	await _same_tick_phase()
	await _boss_catch_phase()
	await _routing_phase()
	await _report()

## The systems spec §10.8 smoke config: the same acceleration the v1 run used, on a stage short
## enough that the whole seam fits in the wall clock. Never the shared .tres — always a duplicate.
func _smoke_config() -> RunConfig:
	var config := (load(CONFIG_PATH) as RunConfig).duplicate()
	# Reach the top speed inside the smoke run instead of the full 100 s ramp.
	config.time_to_max_speed = RAMP_SECONDS
	config.stage_base_distance = STAGE_DISTANCE
	# Stage 1 is cycle 0, so the scale alone decides the fight: 100 hp x 0.4 = SMOKE_BOSS_HP.
	config.boss_hp_scale = BOSS_HP_SCALE
	return config

## Systems spec §10.8: one whole stage seam under the shortened config. Stage 1 runs its 260 m,
## drains straight into its boss, is brought down by tools, clears and hands over to stage 2 — all
## inside a bounded wall clock, with the fair bot taking no hit at all on the way.
func _stage_phase() -> void:
	game.set_autopilot(true)
	if game.autopilot != null and game.autopilot.has_method("set_mode"):
		game.autopilot.set_mode(GREEDY_PICKUP)
	check(game.phase == &"run", "stage 1 did not open in the run phase (phase %s)" % game.phase)
	check(game.stage_index == 1, "the run opened on stage %d" % game.stage_index)
	check(events["stage_started"].size() == 1 and int(events["stage_started"][0][0]) == 1,
		"stage_started did not announce stage 1, got %s" % [events["stage_started"]])
	check(is_equal_approx(float(game.stage_distance_target), STAGE_DISTANCE),
		"stage 1 asks for %.0f m, expected %.0f" % [float(game.stage_distance_target), STAGE_DISTANCE])

	# A lambda captures these by value, so the samples live in a dictionary the closure can mutate.
	var watched := {"saw_run": false, "straight": true, "rested": true}
	check(await _wait_until(func() -> bool:
		if game.phase == &"run":
			watched.saw_run = true
			if not game.turn_rig.rotation.is_equal_approx(Vector3.ZERO):
				watched.straight = false
			var corridor: Node = game.turn_rig.get("corridor")
			if corridor is Node3D and not (corridor as Node3D).rotation.is_equal_approx(Vector3.ZERO):
				watched.straight = false
			var rig: Node = game.camera_rig
			if rig != null and rig.get("camera") is Camera3D:
				var lens := rig.get("camera") as Camera3D
				if not lens.rotation.is_equal_approx(rig.get("_base_rotation") as Vector3):
					watched.rested = false
		return not events["boss_spawned"].is_empty()
	, STAGE_WALL_TIMEOUT),
		"stage 1 never drained into the boss (%.0f/%.0f m, phase %s)"
			% [float(game.stage_distance), float(game.stage_distance_target), game.phase])
	check(bool(watched.saw_run) and bool(watched.straight), "the corridor or the TurnRig rotated during the run")
	check(bool(watched.rested), "the camera left its rest pose during the run")
	check(events["phase_changed"].size() >= 2
		and events["phase_changed"][0] == &"run"
		and events["phase_changed"][1] == &"boss",
		"the drain handed stage 1 from run to boss, got %s" % [events["phase_changed"]])
	if events["boss_spawned"].is_empty():
		return
	check(game.phase == &"boss", "the boss spawned outside the boss phase (phase %s)" % game.phase)
	check(StringName(events["boss_spawned"][0][0]) == &"flaky_test_swarm",
		"stage 1 fights %s" % events["boss_spawned"][0][0])
	check(game.boss_max_hp == SMOKE_BOSS_HP,
		"the smoke fight opened on %d hp, expected the scaled %d" % [game.boss_max_hp, SMOKE_BOSS_HP])
	check(game.boss != null, "the fight has no boss node")
	# Contract 2.6 §11.14: the run's first meeting plays the full intro, and it holds the player.
	check(not events["boss_cinematic"].is_empty() and StringName(events["boss_cinematic"][0][0]) == &"intro_full"
		and is_equal_approx(float(events["boss_cinematic"][0][1]), float(game.config.boss_intro_seconds)),
		"stage 1 did not open on a %.1f s intro_full, got %s"
			% [float(game.config.boss_intro_seconds), events["boss_cinematic"]])
	check(game.boss_cinematic_mode == &"intro_full" and bool(game.stage_manager.cinematic_hold)
		and not bool(game.player.controls_enabled),
		"the intro does not hold the player (mode %s, hold %s, controls %s)"
			% [game.boss_cinematic_mode, game.stage_manager.cinematic_hold, game.player.controls_enabled])

	check(await _wait_until(func() -> bool: return _damaging_tools() > 0, STAGE_WALL_TIMEOUT),
		"the greedy bot never landed a tool on the boss (hp %d/%d)" % [game.boss_hp, game.boss_max_hp])
	check(await _wait_until(func() -> bool: return not events["boss_defeated"].is_empty(), STAGE_WALL_TIMEOUT),
		"the boss was never defeated (hp %d/%d, %d tools)"
			% [game.boss_hp, game.boss_max_hp, events["tool_collected"].size()])
	if events["boss_defeated"].is_empty():
		return
	check(events["boss_retreated"].is_empty(), "the boss both died and ran away")
	check(int(events["boss_defeated"][0][1]) > 0, "the kill paid %d" % int(events["boss_defeated"][0][1]))
	check(_damaging_tools() >= 2, "only %d tools actually damaged the boss" % _damaging_tools())
	await _boss_cleanup()

	check(await _wait_until(func() -> bool: return not events["stage_cleared"].is_empty(), STAGE_WALL_TIMEOUT),
		"the stage never cleared after the kill")
	check(await _wait_until(func() -> bool: return events["stage_started"].size() >= 2, STAGE_WALL_TIMEOUT),
		"stage 2 never opened (phase %s, stage %d)" % [game.phase, game.stage_index])
	if events["stage_started"].size() < 2:
		return
	check(int(events["stage_started"][1][0]) == 2 and game.stage_index == 2,
		"the seam handed over to stage %d" % game.stage_index)
	check(StringName(events["stage_started"][1][1]) == &"Merge Conflict Hydra",
		"stage 2 announced %s" % events["stage_started"][1][1])
	check(game.phase == &"run", "stage 2 did not open in the run phase (phase %s)" % game.phase)
	# `and` short-circuits, so the index is only read once the array is known to have an entry: the
	# wait above can time out, and an empty array here would fault instead of failing the check.
	check(not events["stage_cleared"].is_empty() and int(events["stage_cleared"][0][1]) > 0,
		"the stage clear paid no bonus across %d stage_cleared event(s)" % events["stage_cleared"].size())
	_check_seam_cinematics()

	# The whole point of the fair bot: the shots are telegraphed and it answers every one of them.
	check(events["damage_taken"].is_empty(),
		"the fair bot took %d hit(s) crossing the seam: %s" % [events["damage_taken"].size(), events["hit_log"]])
	check(game.hp == 2, "the seam cost health (hp %d)" % game.hp)
	check(int(game.hit_manager.hits_taken) == 0,
		"the seam took %d hits" % int(game.hit_manager.hits_taken))

## Ramped, autopiloted running with no damage at all. The run clock only ticks inside the RUN
## phase now (contract §11.1), so the ramp is waited out on `run_clock` rather than on `elapsed`.
func _clean_phase() -> void:
	game.set_autopilot(true)
	if game.autopilot != null and game.autopilot.has_method("set_mode"):
		game.autopilot.set_mode(GREEDY_PICKUP)
	var ramped := func() -> bool:
		return game.run_clock >= RAMP_SECONDS + 2.0 and game.elapsed >= CLEAN_SECONDS \
			and game.phase == &"run"
	check(await _wait_until(ramped, WALL_TIMEOUT),
		"the ramp never topped out (run_clock %.1f, elapsed %.1f, phase %s)"
			% [game.run_clock, game.elapsed, game.phase])
	check(game.hp == 2, "the clean run lost health (hp %d)" % game.hp)
	check(int(game.hit_manager.hits_taken) == 0,
		"the clean run took %d hits" % int(game.hit_manager.hits_taken))
	check(events["damage_taken"].is_empty(), "the clean run reported damage")
	var top := float(game.config.max_speed)
	check(game.speed >= top - 0.5, "the corridor only reached %.1f m/s, expected %.1f" % [game.speed, top])
	check(game.normalized_speed >= 0.95, "normalized speed is %.2f at full ramp" % game.normalized_speed)
	var active: Array = game.spawner.get_active_chunks()
	check(active.size() <= int(game.config.max_active_chunks),
		"%d chunks are active, the cap is %d" % [active.size(), int(game.config.max_active_chunks)])
	check(int(game.spawner.chunks_spawned) > 0, "no chunk was ever spawned")
	check(game.score > 0, "the score is still 0 after %.0f s" % CLEAN_SECONDS)
	check(int(game.effect_manager.power_ups_collected) >= 1,
		"the greedy bot collected no power-up in %.0f s" % CLEAN_SECONDS)
	check(int(game.hazards_dodged) > 0, "no hazard was counted as dodged")

## Auto-Fix clears the corridor ahead and the run stays clean right after it. The blast only has
## something to clear inside a RUN phase with chunks still in front of the player, so the phase is
## waited for rather than assumed: a stage that happens to be draining has an empty corridor.
func _auto_fix_phase() -> void:
	var loaded := func() -> bool:
		return game.phase == &"run" and _blocking_ahead() >= 2
	check(await _wait_until(loaded, WALL_TIMEOUT),
		"no loaded run phase to blast (phase %s, %d hazards ahead)" % [game.phase, _blocking_ahead()])
	var before: int = events["hazards_blasted"].size()
	game.effect_manager.apply(&"auto_fix")
	await _wait_frames(4)
	check(events["hazards_blasted"].size() == before + 1, "Auto-Fix did not report a blast")
	var cleared := 0
	if events["hazards_blasted"].size() > before:
		cleared = int(events["hazards_blasted"][events["hazards_blasted"].size() - 1])
	check(cleared > 0, "Auto-Fix cleared %d hazards" % cleared)
	check(events["hazard_cleared"].size() >= cleared, "hazard_cleared fired %d times for %d hazards"
		% [events["hazard_cleared"].size(), cleared])
	var hits_before: int = events["damage_taken"].size()
	await _wait_run_seconds(BLAST_QUIET_SECONDS)
	check(events["damage_taken"].size() == hits_before, "a hazard landed right after Auto-Fix")

## Pausing freezes the score and the run clock, and says so.
func _pause_phase() -> void:
	var score_before: int = game.score
	var elapsed_before: float = game.elapsed
	var paused_before: int = events["paused_changed"].size()
	game.pause()
	check(paused, "pause() did not pause the tree")
	await _wait_wall_seconds(PAUSE_SECONDS)
	check(game.score == score_before, "the score moved while paused (%d -> %d)" % [score_before, game.score])
	check(is_equal_approx(game.elapsed, elapsed_before), "the run clock moved while paused")
	check(events["paused_changed"].size() == paused_before + 1 and bool(events["paused_changed"][-1]),
		"paused_changed(true) was not emitted")
	game.resume()
	await process_frame
	check(not paused, "resume() did not unpause the tree")
	# Size first, so a resume that never announced itself fails the check instead of indexing an
	# array that is still one entry short.
	check(events["paused_changed"].size() == paused_before + 2
		and not bool(events["paused_changed"][-1]), "paused_changed(false) was not emitted")

## Real Godot input dispatch, not a method call: Space is bound by physical_keycode (contract §6).
func _input_phase() -> void:
	game.set_autopilot(false)
	var ready := func() -> bool:
		return not bool(game.player.is_airborne) and _corridor_clear(1.2)
	check(await _wait_until(ready, 5.0), "no clear stretch to test a real jump in")
	var jumps := _action_count(&"jump")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await _wait_frames(6)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_SPACE
	release.pressed = false
	Input.parse_input_event(release)
	await _wait_frames(2)
	check(_action_count(&"jump") > jumps, "a real Space key event did not make the player jump")
	# Let the jump finish before the bot takes over, so it never inherits an airborne runner.
	await _wait_until(func() -> bool: return not bool(game.player.is_airborne), 3.0)
	game.set_autopilot(true)

## Reckless autopilot takes a hit, the pursuit starts, and a clean stretch wins it back.
func _pursuit_phase() -> void:
	_close_banner_watch()
	game.set_autopilot(true)
	# One ignored slice at a time, and never two in flight: arm the bot, wait until it has burned
	# the slice, then give that slice time to reach the player before arming again. Two overlapping
	# reckless slices would land two hits and end the run before the pursuit could be watched.
	# Reckless mode burns *slices*, so it only bites in a RUN phase that still has chunks in it.
	var hit := false
	var attempts := 0
	while not hit and attempts < 10 and game.state == &"running":
		attempts += 1
		await _wait_until(func() -> bool: return game.phase == &"run" and _blocking_ahead() > 0,
			WALL_TIMEOUT / TIME_SCALE)
		if game.autopilot.has_method("set_reckless"):
			game.autopilot.set_reckless(1)
		var burned := func() -> bool:
			return int(game.autopilot.reckless_slices) == 0 or not events["damage_taken"].is_empty()
		await _wait_until(burned, DAMAGE_WINDOW / TIME_SCALE)
		hit = await _wait_until(func() -> bool: return not events["damage_taken"].is_empty(),
			PASS_SECONDS / TIME_SCALE)
	if game.autopilot.has_method("set_reckless"):
		game.autopilot.set_reckless(0)
	check(hit, "the reckless bot never took a hit in %d attempts" % attempts)
	check(game.state == &"running", "the reckless phase ended the run early (state %s)" % game.state)
	if not hit:
		return
	check(game.hp == 1, "the first hit left hp %d" % game.hp)
	check(bool(game.hit_manager.is_pursued()), "the first hit did not start the pursuit")
	check(events["pursuit_started"].size() == 1, "pursuit_started fired %d times"
		% events["pursuit_started"].size())
	check(not events["pursuit_progress"].is_empty(), "pursuit_progress is not ticking")
	# Back to fair driving: the recovery timer needs a clean stretch.
	game.autopilot.set_mode(PREFER_LANE)
	game.set_autopilot(true)
	# Slack on top of the timer for the bot to find its clean stretch. Named, so the wait and the
	# failure message can never quote different numbers.
	var recovery_slack := 4.0
	var deadline := float(game.config.recovery_seconds) + recovery_slack
	var recovered := await _wait_until(func() -> bool: return not events["pursuit_recovered"].is_empty(),
		deadline / TIME_SCALE)
	check(recovered, "the pursuit never ended inside recovery_seconds + %.0f = %.1f game seconds"
		% [recovery_slack, deadline])
	if not recovered:
		return
	check(StringName(events["pursuit_recovered"][0]) == &"timer", "the recovery was not the timer")
	check(game.hp == 2, "the recovery left hp %d" % game.hp)
	check(bool(game.hit_manager.is_safe()), "the recovery did not restore the SAFE state")

## Two more hits end the run: caught, then run_finished exactly once about 1.6 s later. The
## unguided runner needs something to run into, so the phase opens on a loaded corridor or a fight.
func _catch_phase() -> void:
	game.set_autopilot(false)
	await _wait_until(func() -> bool:
		return game.phase == &"boss" or (game.phase == &"run" and _blocking_ahead() > 0),
		WALL_TIMEOUT / TIME_SCALE)
	var hits_before: int = events["damage_taken"].size()
	var caught := await _wait_until(func() -> bool: return events["caught"] > 0, WALL_TIMEOUT / TIME_SCALE)
	check(caught, "the unguided runner was never caught")
	if not caught:
		return
	check(events["damage_taken"].size() >= hits_before + 2, "the catch took fewer than two hits")
	check(game.state == &"caught", "the catch did not move the state to caught")
	check(events["caught"] == 1, "caught fired %d times" % events["caught"])
	var at_caught := Time.get_ticks_msec()
	var finished := await _wait_until(func() -> bool: return events["run_finished"] > 0, WALL_TIMEOUT / TIME_SCALE)
	check(finished, "run_finished never arrived")
	if not finished:
		return
	var span := float(Time.get_ticks_msec() - at_caught) / 1000.0 * TIME_SCALE
	check(span >= 1.0 and span <= 4.0,
		"run_finished landed %.2f game seconds after caught, expected about %.1f"
			% [span, float(game.config.caught_sequence_seconds)])
	await _wait_run_seconds(0.5)
	check(events["run_finished"] == 1, "run_finished fired %d times" % events["run_finished"])
	check(game.state == &"finished", "the run did not end in the finished state")

## Contract §11.1: the `STAGE n` banner covers the lanes, so for `stage_banner_clear_seconds` after
## every `stage_started` nothing blocking may reach the player, and the moment the window ends the
## nearest blocking hazard is still a full `stage_banner_reaction_seconds` of travel away. Checked
## over every stage the run opened before the phases that take damage on purpose — which is at
## least the two the seam itself produced.
func _banner_phase() -> void:
	var windows: Array = events["stage_windows"]
	check(windows.size() >= 2,
		"only %d stage-entrance window(s) were watched, expected one per stage across the seam" % windows.size())
	# The window must not have cost the seam its boss: this is the same run _stage_phase() drove.
	check(not events["boss_spawned"].is_empty() and events["stage_started"].size() >= 2,
		"the clear-road window broke the seam: %d boss spawn(s), %d stage(s)"
			% [events["boss_spawned"].size(), events["stage_started"].size()])
	var reaction := float(game.config.stage_banner_reaction_seconds)
	for item in windows:
		var window: Dictionary = item
		var index := int(window["index"])
		check(bool(window["closed"]), "stage %d's banner window never closed inside the run" % index)
		if not bool(window["closed"]):
			continue
		var hits := 0
		for stamp in events["damage_times"]:
			if float(stamp) >= float(window["opened"]) and float(stamp) <= float(window["ends"]):
				hits += 1
		check(hits == 0,
			"stage %d took %d hit(s) while the banner was still covering the lanes: %s"
				% [index, hits, events["hit_log"]])
		var limit := -reaction * float(window["speed"])
		check(float(window["nearest_z"]) <= limit + 0.01,
			"stage %d's banner lifted with a blocking hazard at track z %.2f; at %.1f m/s it must be at most %.2f"
				% [index, float(window["nearest_z"]), float(window["speed"]), limit])

## One window per stage_started, closed by the physics sampler once it has run its course.
func _open_banner_window(index: int) -> void:
	if not banner_watch or game == null or not is_instance_valid(game):
		return
	events["stage_windows"].append({
		"index": index,
		"opened": float(game.elapsed),
		"ends": float(game.elapsed) + float(game.config.stage_banner_clear_seconds),
		"closed": false,
		"speed": maxf(float(game.speed), 1.0),
		"nearest_z": -INF
	})

## Read the corridor on the tick a window runs out. `game.elapsed` is the run clock, so a pause
## holds the window open exactly as the spawner's own countdown does.
func _sample_banner_windows() -> void:
	if game == null or not is_instance_valid(game):
		return
	for item in events.get("stage_windows", []):
		var window: Dictionary = item
		if bool(window["closed"]) or float(game.elapsed) < float(window["ends"]):
			continue
		window["closed"] = true
		window["speed"] = maxf(float(game.speed), 1.0)
		window["nearest_z"] = _nearest_blocking_z()

## Stop watching before the phases that take damage on purpose, and drop any window still open: a
## hit the test went looking for inside one would be the test's doing, not the corridor's.
func _close_banner_watch() -> void:
	banner_watch = false
	var kept: Array = []
	for item in events["stage_windows"]:
		var window: Dictionary = item
		if bool(window["closed"]):
			kept.append(window)
	events["stage_windows"] = kept

## Track z of the blocking hazard closest to the player without having passed them; -INF when the
## corridor holds none. Boss projectiles are in runner_hazards too, so they count here.
func _nearest_blocking_z() -> float:
	var nearest := -INF
	for node in get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		if hazard.has_method("is_blocking") and not hazard.is_blocking():
			continue
		var z: float = game.track_z(hazard)
		if z > 1.0:
			continue
		nearest = maxf(nearest, z)
	return nearest

## The result reached the board, and the name can still be set afterwards.
func _leaderboard_phase() -> void:
	var result: Dictionary = game.get_result()
	check(not result.is_empty(), "the result is empty after run_finished")
	if result.is_empty():
		return
	check(String(result["run_id"]) == game.run_id, "the result carries another run_id")
	check(String(result["outcome"]) == "caught", "the outcome is %s" % result["outcome"])
	check(int(result["seed"]) == SEED, "the result lost the seed")
	check(int(result["hits_taken"]) >= 2, "the result counted %d hits" % int(result["hits_taken"]))
	check(int(result["score"]) > 0, "the result scored 0")
	check(int(result.get("leaderboard_error", -1)) == OK,
		"the board write reported error %s" % result.get("leaderboard_error", "<missing>"))
	check(events["leaderboard_saved"] > 0, "leaderboard_saved was never emitted")
	var board: Array = game.get_leaderboard()
	var entry := _find_entry(board, game.run_id)
	check(not entry.is_empty(), "this run is not on the leaderboard")
	if entry.is_empty():
		return
	check(game.submit_name("  Test  "), "submit_name did not persist")
	var renamed: Array = game.get_leaderboard()
	check(renamed.size() == board.size(), "submit_name changed the entry count")
	var again := _find_entry(renamed, game.run_id)
	check(String(again.get("name", "")) == "Test", "the entry is named %s" % again.get("name", ""))

## Route in and out of the runner twice and land on the hub with nothing left behind.
## Systems spec §4 "Same-tick ordering", proven through the real Area3D path: nothing here calls
## hit_player() by hand, the hazard's own `area_entered` does it. Godot flushes physics queries — and
## so emits `area_entered` — before any `_physics_process` in the same frame, so a hazard that starts
## overlapping the hurtbox on the frame the recovery timer would expire must kill the runner rather
## than let it recover.
func _same_tick_phase() -> void:
	var packed := load(GAME_PATH) as PackedScene
	check(packed != null, "same-tick: runner_game.tscn failed to load")
	if packed == null:
		return
	await _same_tick_case(packed, true)
	await _same_tick_case(packed, false)

## One trial. `lethal` drops a real hazard on the hurtbox; the converse leaves the corridor empty so
## the identical timer tick recovers instead, which is what makes the lethal result mean something.
##
## Frame budget, measured on 4.7.0: a hazard positioned on the hurtbox is reported exactly two
## physics frames later — the first frame carries the new transform to the physics server and its
## step finds the pair, and the signal is flushed at the top of the frame after that. So the timer is
## armed after the first of those two frames, which puts its deadline in the very frame that reports
## the overlap; the engine's flush-before-process order is then the only thing deciding the outcome.
func _same_tick_case(packed: PackedScene, lethal: bool) -> void:
	var tag := "same-tick lethal" if lethal else "same-tick converse"
	var probe := packed.instantiate() as Node3D
	probe.autostart = false
	# Before add_child, like every other RunnerGame in the suite: _ready() honours autostart, and a
	# probe must never reach the player's real board.
	probe.leaderboard_path = leaderboard_path
	root.add_child(probe)
	await process_frame
	# No corridor traffic: the only hazard allowed to touch the player is the one placed below.
	probe.spawner.set_physics_process(false)
	probe.state = &"running"
	var hits: Node = probe.hit_manager
	hits.state = hits.HitState.PURSUED
	hits.hp = 1
	hits.iframe_remaining = 0.0
	hits.recovery_remaining = 999.0
	var seen := {"caught": 0, "recovered": 0}
	probe.caught.connect(func() -> void: seen["caught"] += 1)
	probe.pursuit_recovered.connect(func(_reason: StringName) -> void: seen["recovered"] += 1)

	var hazard: Area3D = null
	if lethal:
		hazard = (load("res://scenes/runner/hazards/hazard.tscn") as PackedScene).instantiate()
		hazard.kind = &"pr_backlog_low"
		probe.get_node("World/Chunks").add_child(hazard)
		hazard.setup(probe)
		hazard.global_position = probe.player.global_position
		check(hazard.get_world_aabb().intersects(probe.player.get_hurtbox_aabb()),
			"%s: the hazard was not placed on the hurtbox" % tag)

	# One engine iteration runs: flush physics queries (this is where `area_entered` is emitted) ->
	# emit `physics_frame` (where an `await` resumes) -> node `_physics_process` -> physics step. So
	# an `await physics_frame` resumes after that frame's overlap reports and before that frame's
	# HitManager tick, which is exactly the seam this check is about.
	var tick := (1.0 / float(Engine.physics_ticks_per_second)) * float(Engine.time_scale)
	await physics_frame
	# Two ticks left, armed one frame early: frame A's tick takes it to one tick, and frame B — the
	# frame whose flush delivers the overlap, measured below — is where it would reach zero.
	hits.recovery_remaining = 2.0 * tick
	await physics_frame
	# Resumed at the top of frame B: the hit has already been reported, frame B's HitManager tick has
	# not run yet. One more frame so that tick — the deadline tick — is behind us before asserting.
	if lethal:
		check(hazard.consumed,
			"%s: the overlap was not reported on the frame the deadline falls on" % tag)
	await physics_frame

	if lethal:
		check(hits.state == hits.HitState.DEAD,
			"%s: the hit must win the shared frame, got state %d" % [tag, hits.state])
		check(int(seen["caught"]) == 1,
			"%s: caught fired %d times, expected exactly 1" % [tag, seen["caught"]])
		check(int(seen["recovered"]) == 0,
			"%s: pursuit_recovered must not fire, got %d" % [tag, seen["recovered"]])
	else:
		check(hits.state == hits.HitState.SAFE,
			"%s: the same timer tick must recover with no hazard, got state %d" % [tag, hits.state])
		check(int(seen["recovered"]) == 1,
			"%s: pursuit_recovered fired %d times, expected exactly 1" % [tag, seen["recovered"]])
		check(int(seen["caught"]) == 0,
			"%s: nothing may be caught here, got %d" % [tag, seen["caught"]])
	probe.free()
	await process_frame

## Systems spec §10.8, the second probe: a run that is already PURSUED takes a projectile in the
## middle of a boss fight. The fight aborts back to `idle`, the run ends exactly once, and the boss
## block of the result survives the arena being torn down.
func _boss_catch_phase() -> void:
	var packed := load(GAME_PATH) as PackedScene
	check(packed != null, "boss catch: runner_game.tscn failed to load")
	if packed == null:
		return
	var probe := packed.instantiate() as Node3D
	probe.autostart = false
	# The stage is trimmed to nothing so the probe is in the fight within a second of game time; the
	# leaderboard override goes on before add_child, like every other RunnerGame in the suite.
	var config := _smoke_config()
	config.stage_base_distance = 1.0
	config.stage_drain_distance = 1.0
	config.stage_drain_timeout = 0.4
	config.boss_intro_seconds = 0.2
	probe.config = config
	probe.leaderboard_path = leaderboard_path
	root.add_child(probe)
	await process_frame
	var seen := {"caught": 0, "finished": 0, "result": {}, "spawned": 0}
	probe.caught.connect(func() -> void: seen["caught"] += 1)
	probe.run_finished.connect(func(value: Dictionary) -> void:
		seen["finished"] += 1
		seen["result"] = value)
	probe.boss_spawned.connect(func(_kind: StringName, _hp: int) -> void: seen["spawned"] += 1)
	probe.start_run(SEED + 1)
	var spawned := await _wait_until(func() -> bool: return int(seen["spawned"]) > 0, BOSS_WALL_TIMEOUT)
	check(spawned, "boss catch: the probe never reached a fight (phase %s, stage %d)"
		% [probe.phase, probe.stage_index])
	if not spawned:
		probe.free()
		await process_frame
		return
	check(probe.phase == &"boss", "boss catch: the probe is in phase %s" % probe.phase)
	_check_no_turn_fields(probe, "boss catch")
	# A tool lands by hand, so the boss block of the result is populated whatever the bot does.
	var arena: Node = probe.get_node_or_null(NodePath(ARENA_PATH))
	check(arena != null and arena.has_method("apply_tool"), "boss catch: the arena has no apply_tool")
	if arena != null and arena.has_method("apply_tool"):
		arena.apply_tool(&"unit_test")
	check(int(probe.stage_manager.tools_used) == 1,
		"boss catch: %d tools were tallied" % int(probe.stage_manager.tools_used))

	# One hit from the catch, and then a real projectile dropped onto the hurtbox to land it.
	var hits: Node = probe.hit_manager
	hits.state = hits.HitState.PURSUED
	hits.hp = 1
	hits.iframe_remaining = 0.0
	hits.recovery_remaining = 999.0
	var shot := _drop_projectile(probe, arena)
	check(shot != null, "boss catch: the projectile fixture could not be placed")
	var caught := await _wait_until(func() -> bool: return int(seen["caught"]) > 0, BOSS_WALL_TIMEOUT)
	check(caught, "boss catch: the pursued runner was never caught")
	if caught:
		check(probe.phase == &"idle", "boss catch: the fight did not abort to idle, phase %s" % probe.phase)
		check(probe.boss == null, "boss catch: the boss survived the abort")
	var finished := await _wait_until(func() -> bool: return int(seen["finished"]) > 0, BOSS_WALL_TIMEOUT)
	check(finished, "boss catch: run_finished never arrived")
	await _wait_frames(30)
	check(int(seen["finished"]) == 1, "boss catch: run_finished fired %d times" % int(seen["finished"]))
	check(int(seen["caught"]) == 1, "boss catch: caught fired %d times" % int(seen["caught"]))
	var result: Dictionary = seen["result"]
	check(String(result.get("outcome", "")) == "caught",
		"boss catch: the outcome is %s" % result.get("outcome", "<missing>"))
	check(int(result.get("stage_reached", 0)) == 1,
		"boss catch: the result reached stage %s" % result.get("stage_reached", "<missing>"))
	_check_no_turn_keys(result, "boss catch result")
	check(int(result.get("tools_used", 0)) >= 1,
		"boss catch: the result counted %s tools" % result.get("tools_used", "<missing>"))
	check(int(result.get("boss_damage_dealt", 0)) >= 15,
		"boss catch: the result carries %s boss damage" % result.get("boss_damage_dealt", "<missing>"))
	check(int(result.get("bosses_defeated", -1)) == 0 and int(result.get("bosses_escaped", -1)) == 0,
		"boss catch: an aborted fight counts as neither a kill nor an escape (%s / %s)"
			% [result.get("bosses_defeated", "<missing>"), result.get("bosses_escaped", "<missing>")])
	check(int(result.get("stages_cleared", -1)) == 0,
		"boss catch: %s stages were cleared before the catch" % result.get("stages_cleared", "<missing>"))
	# Contract §11.13: the catch mid-fight leaves a boss checkpoint, and the mounted Game Over offers it.
	var checkpoint: Dictionary = probe.boss_checkpoint.duplicate(true)
	check(not checkpoint.is_empty() and int(checkpoint.get("stage_index", 0)) == 1,
		"boss catch: the catch left no stage-1 boss checkpoint (%s)" % [checkpoint])
	_check_no_turn_keys(checkpoint, "boss catch checkpoint")
	var retry_boss_button: Button = null
	for overlay in probe.get_node(^"Overlays").get_children():
		if &"retry_boss_button" in overlay:
			retry_boss_button = overlay.get(&"retry_boss_button") as Button
	check(retry_boss_button != null and retry_boss_button.is_visible_in_tree(),
		"boss catch: Game Over does not offer Retry Boss")
	var runner_script: Script = probe.get_script()
	probe.free()
	await process_frame
	if not checkpoint.is_empty():
		await _boss_retry_phase(runner_script, checkpoint)

## What retry_boss() hands the next session, minus the scene change: a fresh runner_game.tscn that
## finds the static checkpoint must open in front of the same boss, at full HP, with the score and
## run_clock the checkpoint carried. The fight starts on that same call.
func _boss_retry_phase(runner_script: Script, checkpoint: Dictionary) -> void:
	var packed := load(GAME_PATH) as PackedScene
	var probe := packed.instantiate() as Node3D
	probe.autostart = false
	var config := _smoke_config()
	config.boss_intro_seconds = 0.2
	probe.config = config
	probe.leaderboard_path = leaderboard_path
	root.add_child(probe)
	await process_frame
	var seen := {"spawned": 0}
	probe.boss_spawned.connect(func(_kind: StringName, _hp: int) -> void: seen["spawned"] += 1)
	runner_script.set(&"pending_boss_checkpoint", checkpoint.duplicate(true))
	probe.start_run(0)
	var pending: Variant = runner_script.get(&"pending_boss_checkpoint")
	check(pending is Dictionary and (pending as Dictionary).is_empty(), "boss retry: the checkpoint was not consumed")
	check(bool(probe.checkpoint_retry), "boss retry: the run is not flagged as a checkpoint retry")
	check(probe.seed == int(checkpoint["seed"]), "boss retry: seed %d, expected %d" % [probe.seed, int(checkpoint["seed"])])
	check(probe.phase == &"boss", "boss retry: the run opened in phase %s, expected boss" % probe.phase)
	check(probe.stage_index == 1, "boss retry: the run opened on stage %d" % probe.stage_index)
	check(probe.hp == int(config.max_hp), "boss retry: HP %d, expected full %d" % [probe.hp, int(config.max_hp)])
	check(probe.score == floori(float(checkpoint["score_exact"])),
		"boss retry: score %d, expected %d" % [probe.score, floori(float(checkpoint["score_exact"]))])
	check(absf(probe.run_clock - float(checkpoint["run_clock"])) < 0.0001, "boss retry: run_clock was not restored")
	check(int(seen["spawned"]) == 1, "boss retry: the fight did not open with the boss phase (spawned %d)"
		% int(seen["spawned"]))
	check(not probe.boss_checkpoint.is_empty(), "boss retry: boss entry re-took no checkpoint")
	_check_no_turn_keys(probe.boss_checkpoint, "boss retry checkpoint")
	check(absf(float(probe.boss_checkpoint.get("run_clock", -1.0)) - float(checkpoint["run_clock"])) < 0.0001,
		"boss retry: the fresh checkpoint did not keep run_clock")
	check(is_equal_approx(float(probe.boss_checkpoint.get("score_exact", -1.0)), float(checkpoint["score_exact"])),
		"boss retry: the score grew before the fight")
	check(probe.turn_rig.rotation.is_equal_approx(Vector3.ZERO), "boss retry: the TurnRig rotated")
	runner_script.set(&"pending_boss_checkpoint", {})
	probe.free()
	await process_frame

## A real projectile.tscn, parked on the hurtbox with no closing speed of its own: the only thing
## in the arena that is certain to land the second hit on the frame after next.
func _drop_projectile(probe: Node3D, arena: Node) -> Area3D:
	if arena == null or not is_instance_valid(arena):
		return null
	var mount := arena.get_node_or_null(^"Projectiles")
	if mount == null:
		return null
	var packed := load(PROJECTILE_SCENE) as PackedScene
	if packed == null:
		return null
	var shot := packed.instantiate() as Area3D
	if shot == null:
		return null
	shot.kind = &"projectile"
	shot.variant = &"orb"
	shot.closing_speed = 0.0
	mount.add_child(shot)
	shot.setup(probe)
	shot.global_position = probe.player.global_position
	return shot

func _routing_phase() -> void:
	var router := root.get_node_or_null("AppRouter")
	check(router != null, "AppRouter is missing")
	if router == null:
		return
	for i in 2:
		router.go("runner_game")
		await _wait_until(func() -> bool: return not router.busy, 10.0)
		check(current_scene != null and current_scene.scene_file_path == router.ROUTES["runner_game"],
			"pass %d did not land on runner_game.tscn" % (i + 1))
		check(not paused, "pass %d left the tree paused" % (i + 1))
	router.go("runner")
	await _wait_until(func() -> bool: return not router.busy, 10.0)
	check(current_scene != null and current_scene.scene_file_path == router.ROUTES["runner"],
		"the runner menu did not load")
	router.go("hub")
	await _wait_until(func() -> bool: return not router.busy, 10.0)
	check(current_scene != null and current_scene.name == "MainMenu", "the hub did not load")
	check(not router.busy, "AppRouter stayed busy")
	check(not paused, "the routing round trip left the tree paused")
	var audio := root.get_node_or_null("AudioService")
	check(audio != null and audio.get_child_count() == 2,
		"AudioService has %d children, expected 2" % (audio.get_child_count() if audio != null else -1))

# --- harness ---

func _watch() -> void:
	events = {
		"damage_taken": [],
		# `game.elapsed` at each hit, so a hit can be placed inside or outside a banner window.
		"damage_times": [],
		"hit_log": [],
		# One entry per stage_started: {index, opened, ends, closed, speed, nearest_z}.
		"stage_windows": [],
		"damage_blocked": [],
		"pursuit_started": [],
		"pursuit_progress": [],
		"pursuit_recovered": [],
		"paused_changed": [],
		"player_action": [],
		"hazards_blasted": [],
		"hazard_cleared": [],
		"power_up_collected": [],
		"stage_started": [],
		"stage_cleared": [],
		"phase_changed": [],
		"boss_spawned": [],
		"boss_defeated": [],
		"boss_retreated": [],
		## Contract 2.6 §11.14: [mode, seconds, elapsed at the signal] per cinematic, and the elapsed of
		## each ending, so the seam can prove the defeat really held the stage clear.
		"boss_cinematic": [],
		"boss_cinematic_skipped": [],
		"boss_cinematic_ended": [],
		"boss_defeated_at": [],
		"stage_cleared_at": [],
		"tool_collected": [],
		"caught": 0,
		"run_finished": 0,
		"leaderboard_saved": 0
	}
	game.stage_started.connect(func(index: int, name: StringName, speed: float) -> void:
		events["stage_started"].append([index, name, speed])
		_open_banner_window(index))
	game.stage_cleared.connect(func(index: int, bonus: int) -> void:
		events["stage_cleared"].append([index, bonus])
		events["stage_cleared_at"].append(float(game.elapsed)))
	game.phase_changed.connect(func(phase: StringName) -> void:
		events["phase_changed"].append(phase))
	game.boss_spawned.connect(func(kind: StringName, hp: int) -> void:
		events["boss_spawned"].append([kind, hp]))
	game.boss_defeated.connect(func(kind: StringName, bonus: int) -> void:
		events["boss_defeated"].append([kind, bonus])
		events["boss_defeated_at"].append(float(game.elapsed)))
	game.boss_cinematic.connect(func(_kind: StringName, mode: StringName, seconds: float) -> void:
		events["boss_cinematic"].append([mode, seconds, float(game.elapsed)]))
	game.boss_cinematic_skipped.connect(func(mode: StringName) -> void:
		events["boss_cinematic_skipped"].append(mode))
	game.boss_cinematic_ended.connect(func(mode: StringName) -> void:
		events["boss_cinematic_ended"].append([mode, float(game.elapsed)]))
	game.boss_retreated.connect(func(kind: StringName, bonus: int) -> void:
		events["boss_retreated"].append([kind, bonus]))
	game.tool_collected.connect(func(kind: StringName, damage: int) -> void:
		events["tool_collected"].append([kind, damage]))
	game.damage_taken.connect(func(kind: StringName, hp: int) -> void:
		events["damage_taken"].append(kind)
		events["damage_times"].append(float(game.elapsed))
		events["hit_log"].append(_hit_context(kind, hp)))
	game.damage_blocked.connect(func(kind: StringName, reason: StringName) -> void:
		events["damage_blocked"].append([kind, reason]))
	game.pursuit_started.connect(func(seconds: float) -> void:
		events["pursuit_started"].append(seconds))
	game.pursuit_progress.connect(func(remaining: float, _total: float) -> void:
		events["pursuit_progress"].append(remaining))
	game.pursuit_recovered.connect(func(reason: StringName) -> void:
		events["pursuit_recovered"].append(reason))
	game.paused_changed.connect(func(value: bool) -> void:
		events["paused_changed"].append(value))
	game.player_action.connect(func(action: StringName) -> void:
		events["player_action"].append(action))
	game.hazards_blasted.connect(func(count: int) -> void:
		events["hazards_blasted"].append(count))
	game.hazard_cleared.connect(func(_hazard: Area3D) -> void:
		events["hazard_cleared"].append(true))
	game.power_up_collected.connect(func(kind: StringName, _duration: float) -> void:
		events["power_up_collected"].append(kind))
	game.caught.connect(func() -> void:
		events["caught"] += 1)
	game.run_finished.connect(func(_result: Dictionary) -> void:
		events["run_finished"] += 1)
	game.leaderboard_saved.connect(func(_entries: Array, _rank: int) -> void:
		events["leaderboard_saved"] += 1)

## Contract 2.6 §11.14 across the stage-1 seam: the intro played its full length, the kill opened a
## defeat_full on the same tick, the stage clear waited that cinematic out, the bot never skipped,
## and the hold let go of the corridor speed. Times are game seconds off `elapsed`, so a slow frame
## cannot stretch them; two physics ticks of slack cover the tick boundary and the float countdown.
func _check_seam_cinematics() -> void:
	var slack := 2.0 / 60.0 + 0.001
	var cinematics: Array = events["boss_cinematic"]
	var ended: Array = events["boss_cinematic_ended"]
	check(cinematics.size() >= 2 and ended.size() >= 2,
		"the seam played %d cinematic(s) and ended %d, expected the intro and the defeat"
			% [cinematics.size(), ended.size()])
	if cinematics.size() < 2 or ended.size() < 2:
		return
	var intro: Array = cinematics[0]
	var intro_end: Array = ended[0]
	check(StringName(intro_end[0]) == &"intro_full"
		and absf(float(intro_end[1]) - float(intro[2]) - float(intro[1])) <= slack,
		"the intro ran %.3f s, expected %.1f" % [float(intro_end[1]) - float(intro[2]), float(intro[1])])
	var defeat: Array = cinematics[1]
	var defeat_seconds := float(game.config.boss_defeat_seconds)
	check(StringName(defeat[0]) == &"defeat_full" and is_equal_approx(float(defeat[1]), defeat_seconds),
		"the kill opened %s for %.2f s, expected defeat_full for %.2f" % [defeat[0], float(defeat[1]), defeat_seconds])
	var killed_at: Array = events["boss_defeated_at"]
	var cleared_at: Array = events["stage_cleared_at"]
	if killed_at.is_empty() or cleared_at.is_empty():
		return
	check(is_equal_approx(float(defeat[2]), float(killed_at[0])),
		"the defeat cinematic opened %.3f s after boss_defeated, expected the same tick"
			% (float(defeat[2]) - float(killed_at[0])))
	var held := float(cleared_at[0]) - float(killed_at[0])
	check(held >= defeat_seconds - slack and held <= defeat_seconds + slack,
		"the stage cleared %.3f s after the kill, expected the %.2f s defeat hold" % [held, defeat_seconds])
	check(events["boss_cinematic_skipped"].is_empty(),
		"the autopilot skipped %s; nothing but a player press may skip" % [events["boss_cinematic_skipped"]])
	check(game.boss_cinematic_mode == &"" and not bool(game.stage_manager.cinematic_hold)
		and is_equal_approx(float(game.speed_controller.cinematic_scale), 1.0),
		"the hold outlived the fight (mode %s, hold %s, scale %.2f)"
			% [game.boss_cinematic_mode, game.stage_manager.cinematic_hold, float(game.speed_controller.cinematic_scale)])

## Tools whose damage actually landed on the boss (a resisting phase reports 0).
func _damaging_tools() -> int:
	var landed := 0
	for item in events["tool_collected"]:
		if int((item as Array)[1]) > 0:
			landed += 1
	return landed

## The end of a fight takes the arena with it (systems spec §10.3). The kill itself lands inside an
## area_entered callback — the tool that fires it is a pickup touching the player — so the arena may
## not take a CollisionObject out of the tree there; everything goes the deferred way instead. The
## counts are read on the spot, because a freed node stops counting the moment it is queued, and the
## groups are read two frames later, once the frees have actually landed. A tool that outlived its
## fight would auto-fire into a boss that is gone; a projectile would still be blocking.
func _boss_cleanup() -> void:
	var arena := game.get_node_or_null(NodePath(ARENA_PATH))
	if arena != null and is_instance_valid(arena):
		check(int(arena.tool_count()) == 0 and int(arena.projectile_count()) == 0,
			"the kill left %d tool(s) and %d projectile(s) in the arena"
				% [int(arena.tool_count()), int(arena.projectile_count())])
	await _wait_frames(2)
	var tools := get_nodes_in_group(&"runner_tools")
	check(tools.is_empty(), "%d tool(s) outlived the fight" % tools.size())
	var blocking := 0
	for node in get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard) or not (&"closing_speed" in hazard):
			continue
		if hazard.has_method("is_blocking") and hazard.is_blocking():
			blocking += 1
	check(blocking == 0, "%d projectile(s) were still blocking two frames after the kill" % blocking)

## Blocking hazards between the player and the Auto-Fix blast range.
func _blocking_ahead() -> int:
	var far_z := -absf(float(game.config.blast_range_z))
	var count := 0
	for node in get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		if hazard.has_method("is_blocking") and not hazard.is_blocking():
			continue
		var z := hazard.global_position.z
		if z >= far_z and z <= 1.0:
			count += 1
	return count

## True when no blocking hazard can reach the player inside `seconds`.
func _corridor_clear(seconds: float) -> bool:
	var reach := maxf(game.speed, 1.0) * seconds
	for node in get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		if hazard.has_method("is_blocking") and not hazard.is_blocking():
			continue
		var z := hazard.global_position.z
		if z <= 1.0 and z >= -reach:
			return false
	return true

## What the runner and the corridor looked like when a hit landed, for the failure dump.
func _hit_context(kind: StringName, hp: int) -> String:
	var player: Node = game.player
	var line := "t=%.2f v=%.1f %s -> hp %d, lane %d/%d x=%.2f y=%.2f roll=%s air=%s reckless=%d" % [
		game.elapsed, game.speed, kind, hp, int(player.lane), int(player.target_lane),
		player.position.x, player.position.y, bool(player.is_rolling), bool(player.is_airborne),
		int(game.autopilot.reckless_slices)]
	for node in get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or hazard.global_position.z < -14.0 or hazard.global_position.z > 4.0:
			continue
		line += " [%s z=%.1f x=%.1f %s blocking=%s]" % [hazard.kind, hazard.global_position.z,
			hazard.global_position.x, hazard.dodge_hint, bool(hazard.is_blocking())]
	return line

func _action_count(action: StringName) -> int:
	var count := 0
	for item in events["player_action"]:
		if StringName(item) == action:
			count += 1
	return count

func _find_entry(board: Array, run_id: String) -> Dictionary:
	for item in board:
		var entry: Dictionary = item
		if String(entry.get("run_id", "")) == run_id:
			return entry
	return {}

## Wait for `seconds` of unpaused run time (game.elapsed), with a wall-clock safety net.
func _wait_run_seconds(seconds: float) -> void:
	var target: float = game.elapsed + seconds
	await _wait_until(func() -> bool: return game.elapsed >= target, seconds / TIME_SCALE + 15.0)

## Wall-clock seconds, used where the tree is paused and the run clock is standing still.
func _wait_wall_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _wait_frames(count: int) -> void:
	for i in count:
		await process_frame

func _check_no_turn_keys(record: Dictionary, tag: String) -> void:
	for key in record:
		check(not String(key).contains("turn"), "%s still records %s" % [tag, key])

func _check_no_turn_fields(node: Object, tag: String) -> void:
	if node is Node:
		for info in (node as Node).get_signal_list():
			check(not String(info["name"]).contains("turn"), "%s still signals %s" % [tag, info["name"]])
	var script: Script = node.get_script()
	while script != null:
		for prop in script.get_script_property_list():
			var prop_name := String(prop["name"])
			if prop_name == "turn_rig":
				continue
			check(not prop_name.contains("turn"), "%s still exposes %s" % [tag, prop_name])
		script = script.get_base_script()

## Returns true when the predicate came true before the wall-clock timeout.
func _wait_until(predicate: Callable, wall_timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(wall_timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

## Seed and chunk log, printed with the first failure so a flaky run can be reproduced.
func _dump_run() -> void:
	if game == null or not is_instance_valid(game):
		return
	print("RUNNER SMOKE: seed %d, elapsed %.1f s, distance %.0f m, speed %.1f, state %s, hp %d, score %d"
		% [game.seed, game.elapsed, game.distance, game.speed, game.state, game.hp, game.score])
	for line in events.get("hit_log", []):
		print("  hit: " + String(line))
	if game.spawner != null and is_instance_valid(game.spawner) and game.spawner.has_method("get_chunk_log"):
		for line in game.spawner.get_chunk_log():
			print("  chunk: " + line)

## The throwaway board and both of its write-time companions (systems spec §7 atomic write).
func _clean_leaderboard() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(leaderboard_path + suffix):
			DirAccess.remove_absolute(leaderboard_path + suffix)

func _report() -> void:
	Engine.time_scale = restore_scale
	Engine.max_physics_steps_per_frame = restore_steps
	Engine.physics_ticks_per_second = restore_ticks
	if game != null and is_instance_valid(game):
		game.free()
		game = null
	_clean_leaderboard()
	print("RUNNER SMOKE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures / ", checks, " checks)")
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	await create_timer(0.3).timeout
	quit(failures)
