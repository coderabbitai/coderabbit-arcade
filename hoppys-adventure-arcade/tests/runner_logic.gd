extends SceneTree
## Endless Runner rules unit tests (systems spec §8, list 1-9 plus the autopilot planner).
## Run with --path <project> --script res://tests/runner_logic.gd.
##
## Every system runs as a plain node that is never added to the tree and is driven by direct
## _physics_process(1/60) calls, so the results depend on nothing but the systems themselves:
## no frame timing, no physics server, no scene the other workstreams are still authoring.
## The facade is a Node3D carrying runner_game.gd (plus a counting _on_caught override), so the
## signals the systems emit are the real contract §4.1 signals.

## Only the scripts that do not reach runner_game.gd can be preloaded: under --script the test is
## compiled before the autoloads exist, and runner_game.gd needs AppRouter at compile time, so
## every system script is loaded inside run() instead.
const RunnerLeaderboard = preload("res://scenes/runner/systems/runner_leaderboard.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
const TICK := 1.0 / 60.0
## The timed laser slot with the hitbox off (hazard.gd OFF_STATE).
const OFF_STATE: StringName = &"off"

## RunnerGame with a countable catch hook: HitManager calls _on_caught(), the facade emits `caught`.
const FAKE_GAME_SOURCE := "extends \"res://scenes/runner/runner_game.gd\"\nvar caught_calls := 0\nfunc _on_caught() -> void:\n\tcaught_calls += 1\n\tcaught.emit()\n"
## The hazard surface HitManager and Autopilot actually use (systems spec §5.3).
const FAKE_HAZARD_SOURCE := "extends Node3D\nvar kind: StringName = &\"pr_backlog_low\"\nvar dodge_hint: StringName = &\"JUMP\"\nvar box := Vector3(5.6, 1.0, 1.2)\nvar center_y := 0.5\nvar blocking := true\nfunc is_blocking() -> bool:\n\treturn blocking\nfunc occupies_lane(index: int) -> bool:\n\treturn absf((float(index) - 1.0) * 2.0 - global_position.x) < box.x * 0.5 + 0.39\nfunc get_world_aabb() -> AABB:\n\treturn AABB(global_position + Vector3(0.0, center_y, 0.0) - box * 0.5, box)\n"
## Spawner stand-in for Auto-Fix (systems spec §5.2 clear_hazards_in_range).
const FAKE_SPAWNER_SOURCE := "extends Node\nvar cleared := 0\nvar calls := 0\nfunc clear_hazards_in_range() -> int:\n\tcalls += 1\n\treturn cleared\n"
## The slice of the player the autopilot drives: the lane tween with runner_player's one-queued-
## change limit, plus a request counter so a bot that spams request_lane is visible.
const FAKE_PLAYER_SOURCE := "extends Node\nvar target_lane := 1\nvar lane_t := 1.0\nvar queued_lane_dir := 0\nvar requests := 0\nfunc request_lane(direction: int) -> void:\n\trequests += 1\n\tvar dir := signi(direction)\n\tif lane_t < 1.0:\n\t\tqueued_lane_dir = dir\n\t\treturn\n\ttarget_lane = clampi(target_lane + dir, 0, 2)\n\tlane_t = 0.0\nfunc finish_tween() -> void:\n\tif lane_t >= 1.0:\n\t\treturn\n\tlane_t = 1.0\n\tif queued_lane_dir == 0:\n\t\treturn\n\tvar dir := queued_lane_dir\n\tqueued_lane_dir = 0\n\ttarget_lane = clampi(target_lane + dir, 0, 2)\n\tlane_t = 0.0\n"

var failures := 0
var checks := 0
var base_config: RunConfig
var game_script: GDScript
var hazard_script: GDScript
## The real hazard.gd (Area3D), used by section 11; loaded at runtime for the same reason.
var real_hazard_script: GDScript
var spawner_script: GDScript
var player_script: GDScript
var hit_manager_script: GDScript
var score_manager_script: GDScript
var effect_manager_script: GDScript
var speed_controller_script: GDScript
var autopilot_script: GDScript
## Everything this test built, freed in _report().
var junk: Array[Node] = []
var temp_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER LOGIC: " + message)

func run() -> void:
	base_config = (load(CONFIG_PATH) as RunConfig).duplicate()
	hit_manager_script = load("res://scenes/runner/systems/hit_manager.gd") as GDScript
	score_manager_script = load("res://scenes/runner/systems/score_manager.gd") as GDScript
	effect_manager_script = load("res://scenes/runner/systems/effect_manager.gd") as GDScript
	speed_controller_script = load("res://scenes/runner/systems/speed_controller.gd") as GDScript
	autopilot_script = load("res://scenes/runner/systems/autopilot.gd") as GDScript
	real_hazard_script = load("res://scenes/runner/hazards/hazard.gd") as GDScript
	game_script = _compile(FAKE_GAME_SOURCE)
	hazard_script = _compile(FAKE_HAZARD_SOURCE)
	spawner_script = _compile(FAKE_SPAWNER_SOURCE)
	player_script = _compile(FAKE_PLAYER_SOURCE)
	if game_script == null or hazard_script == null or spawner_script == null \
			or player_script == null or real_hazard_script == null:
		check(false, "the test harness scripts failed to compile")
		_report()
		return
	_test_hit_basics()
	_test_recovery()
	_test_shared_tick()
	_test_shield()
	_test_invulnerability()
	_test_score()
	_test_effects()
	_test_leaderboard()
	_test_config_sanity()
	_test_autopilot()
	_test_timed_laser_shutdown()
	_report()

# --- 1. HitManager: SAFE -> PURSUED -> DEAD ---

func _test_hit_basics() -> void:
	var game := _make_game()
	var events := _watch(game)
	var hits: Node = _systems(game)["hits"]
	check(hits.state == hits.HitState.SAFE, "1: a fresh run starts SAFE")
	check(hits.hp == 2, "1: a fresh run starts on 2 hp")
	check(hits.is_alive() and not hits.is_pursued(), "1: a fresh run is alive and unpursued")

	var outcome: StringName = hits.report_hit(_hazard(&"bug_swarm"))
	check(outcome == hits.DAMAGED, "1: the first hit damages, got %s" % outcome)
	check(hits.state == hits.HitState.PURSUED and hits.hp == 1, "1: the first hit starts the pursuit")
	check(events["pursuit_started"].size() == 1, "1: pursuit_started fires once")
	check(is_equal_approx(float(events["pursuit_started"][0]), 18.0), "1: pursuit_started carries recovery_seconds")
	check(events["damage_taken"].size() == 1 and events["damage_taken"][0][0] == &"bug_swarm",
		"1: damage_taken carries the hazard kind")
	check(events["health_changed"].size() == 1 and events["health_changed"][0][0] == 1,
		"1: health_changed reports 1 hp")

	var blocked: StringName = hits.report_hit(_hazard(&"pr_backlog_low"))
	check(blocked == hits.BLOCKED_INVULN, "1: a hit inside the i-frames is blocked, got %s" % blocked)
	check(events["damage_blocked"].size() == 1 and events["damage_blocked"][0][1] == &"iframes",
		"1: the blocked hit reports reason iframes")
	check(hits.hp == 1 and hits.state == hits.HitState.PURSUED, "1: a blocked hit costs nothing")

	_tick([hits], _ticks(0.9))
	check(hits.iframe_remaining == 0.0, "1: the i-frames run out after 0.8 s")
	var killed: StringName = hits.report_hit(_hazard(&"comment_flood"))
	check(killed == hits.DAMAGED, "1: the second hit lands, got %s" % killed)
	check(hits.state == hits.HitState.DEAD and hits.hp == 0, "1: the second hit is fatal")
	check(int(game.caught_calls) == 1, "1: the facade catch hook ran exactly once")
	check(int(events["caught"]) == 1, "1: caught is emitted exactly once")
	check(not hits.is_alive(), "1: a caught runner is not alive")

	check(hits.report_hit(_hazard(&"bug_swarm")) == hits.IGNORED, "1: hits after the catch are ignored")
	check(int(events["caught"]) == 1, "1: caught never fires twice")
	check(hits.hits_taken == 2 and hits.blocked_hits == 1, "1: the hit counters match the run")

# --- 2. Recovery timer ---

func _test_recovery() -> void:
	var game := _make_game()
	var events := _watch(game)
	var hits: Node = _systems(game)["hits"]
	hits.report_hit(_hazard(&"bug_swarm"))
	_tick([hits], _ticks(17.99))
	check(hits.state == hits.HitState.PURSUED, "2: still pursued at 17.99 s")
	check(events["pursuit_progress"] >= 1000, "2: pursuit_progress ticks every physics frame")
	check(events["pursuit_recovered"].is_empty(), "2: no recovery before the deadline")
	_tick([hits], _ticks(0.04))
	check(hits.state == hits.HitState.SAFE and hits.hp == 2, "2: the timer restores full health")
	check(events["pursuit_recovered"].size() == 1 and events["pursuit_recovered"][0] == &"timer",
		"2: pursuit_recovered reports the timer")
	check(hits.recoveries == 1, "2: the recovery counter moved")

	_tick([hits], _ticks(1.0))
	hits.report_hit(_hazard(&"merge_conflict"))
	check(hits.state == hits.HitState.PURSUED and hits.hp == 1, "2: a later hit starts a new cycle")
	check(events["pursuit_started"].size() == 2, "2: the new cycle announces itself")
	check(is_equal_approx(hits.recovery_remaining, 18.0), "2: the new cycle gets the full timer")

# --- 3. Damage and the recovery deadline on one tick ---

func _test_shared_tick() -> void:
	var game := _make_game()
	var hits: Node = _systems(game)["hits"]
	hits.report_hit(_hazard(&"bug_swarm"))
	hits.iframe_remaining = 0.0
	# The overlap is delivered before any _physics_process, so queued damage resolves first.
	hits.recovery_remaining = 0.005
	var outcome: StringName = hits.report_hit(_hazard(&"build_shockwave"))
	check(outcome == hits.DAMAGED, "3: the queued hit lands before the deadline, got %s" % outcome)
	check(hits.state == hits.HitState.DEAD, "3: a hit on the deadline tick kills")
	_tick([hits], 1)
	check(hits.state == hits.HitState.DEAD and hits.hp == 0, "3: the expiring timer cannot revive")
	check(int(game.caught_calls) == 1, "3: the catch still ran once")

# --- 4. Approve Shield ---

func _test_shield() -> void:
	var game := _make_game()
	var events := _watch(game)
	var hits: Node = _systems(game)["hits"]
	hits.set_shield(true)
	check(events["shield_changed"].size() == 1 and bool(events["shield_changed"][0]),
		"4: storing the shield is announced")
	var outcome: StringName = hits.report_hit(_hazard(&"bug_swarm"))
	check(outcome == hits.BLOCKED_SHIELD, "4: the shield eats the hit, got %s" % outcome)
	check(hits.state == hits.HitState.SAFE and hits.hp == 2, "4: a shielded runner stays safe")
	check(not hits.shield, "4: the shield is spent")
	check(events["shield_changed"].size() == 2 and not bool(events["shield_changed"][1]),
		"4: spending the shield is announced")
	check(events["damage_blocked"].size() == 1 and events["damage_blocked"][0][1] == &"shield",
		"4: the blocked hit reports reason shield")
	check(hits.recoveries == 0, "4: a shield used while SAFE is not a recovery")

	var pursued_game := _make_game()
	var pursued_events := _watch(pursued_game)
	var pursued: Node = _systems(pursued_game)["hits"]
	pursued.report_hit(_hazard(&"bug_swarm"))
	_tick([pursued], _ticks(0.9))
	pursued.set_shield(true)
	var absorbed: StringName = pursued.report_hit(_hazard(&"pr_backlog_high"))
	check(absorbed == pursued.BLOCKED_SHIELD, "4: the shield answers a pursued hit, got %s" % absorbed)
	check(pursued.is_safe() and pursued.hp == 2, "4: the shield buys the pursuit back")
	check(pursued.recovery_remaining == 0.0, "4: the recovery timer is cleared")
	check(pursued_events["pursuit_recovered"].size() == 1
		and pursued_events["pursuit_recovered"][0] == &"shield",
		"4: pursuit_recovered reports the shield")
	# Systems spec §4: recoveries counts every PURSUED -> SAFE exit, by shield as well as by timer.
	check(pursued.recoveries == 1, "4: the shield recovery is counted in recoveries")

# --- 5. Invulnerability sources and hazard dedupe ---

func _test_invulnerability() -> void:
	var game := _make_game()
	var events := _watch(game)
	var hits: Node = _systems(game)["hits"]
	hits.add_invuln_source(&"lgtm")
	check(hits.is_invulnerable(), "5: an invulnerability source blocks damage")
	var outcome: StringName = hits.report_hit(_hazard(&"bug_swarm"))
	check(outcome == hits.BLOCKED_INVULN, "5: LGTM smashes through, got %s" % outcome)
	check(events["damage_blocked"][0][1] == &"lgtm", "5: the blocked hit names the source")
	check(hits.hp == 2, "5: LGTM costs no health")
	hits.remove_invuln_source(&"lgtm")
	check(not hits.is_invulnerable(), "5: removing the source restores vulnerability")

	var hazard := _hazard(&"merge_conflict")
	check(hits.report_hit(hazard) == hits.DAMAGED, "5: the next hit lands")
	check(hits.report_hit(hazard) == hits.IGNORED, "5: the same hazard cannot hit twice")
	_tick([hits], _ticks(0.9))
	check(hits.report_hit(hazard) == hits.IGNORED, "5: the dedupe outlives the i-frames")
	check(hits.hp == 1, "5: the deduped hazard never damaged twice")
	hits.add_invulnerability(&"nitro")
	check(hits.is_invulnerable(), "5: the spelled-out alias adds a source")
	hits.remove_invulnerability(&"nitro")
	check(not hits.is_invulnerable(), "5: the spelled-out alias removes a source")

# --- 6. ScoreManager ---

func _test_score() -> void:
	var game := _make_game()
	var events := _watch(game)
	var systems := _systems(game)
	var score: Node = systems["score"]
	var hits: Node = systems["hits"]
	var effects: Node = systems["effects"]
	_tick([score], 60)
	check(absf(float(score.exact) - 10.0) < 0.001, "6: one second at x1 is 10 points, got %f" % score.exact)
	check(score.score == floori(score.exact), "6: the shown score is the floor of the accumulator")
	check(events["score_changed"].size() <= 12 and events["score_changed"].size() >= 8,
		"6: score_changed only fires on an integer change, got %d" % events["score_changed"].size())

	score.set_nitro(true)
	check(is_equal_approx(float(score.multiplier), 2.0), "6: Nitro doubles the multiplier")
	var before := float(score.exact)
	_tick([score], 60)
	check(absf(float(score.exact) - before - 20.0) < 0.001, "6: one second at x2 is 20 points")

	score.set_code_review(true)
	check(is_equal_approx(float(score.multiplier), 3.0), "6: Nitro and Code Review compose to x3")
	before = float(score.exact)
	_tick([score], 60)
	check(absf(float(score.exact) - before - 30.0) < 0.001, "6: one second at x3 is 30 points")
	check(is_equal_approx(float(score.best_multiplier), 3.0), "6: the best multiplier is remembered")

	effects.code_review_held = true
	hits.report_hit(_hazard(&"bug_swarm"))
	check(not score.code_review_active, "6: an unblocked hit drops the Code Review Bonus")
	check(is_equal_approx(float(score.multiplier), 2.0), "6: the multiplier falls back to Nitro alone")

	var bonus_before: int = score.score
	score.add_bonus(25, &"approve_shield")
	check(score.score == bonus_before + 25, "6: a bonus lands on the score immediately")
	check(score.bonus_total == 25, "6: bonuses are totalled for the result")
	check(events["bonus_awarded"].size() == 1 and events["bonus_awarded"][0][1] == &"approve_shield",
		"6: bonus_awarded carries the reason")

	# Frame-rate independence: the same second at 30 fps and at 60 fps pays the same.
	var slow: Node = _systems(_make_game())["score"]
	var fast: Node = _systems(_make_game())["score"]
	_tick([slow], 30, 1.0 / 30.0)
	_tick([fast], 60, TICK)
	check(absf(float(slow.exact) - float(fast.exact)) < 0.001,
		"6: 30 fps and 60 fps award the same points (%f vs %f)" % [slow.exact, fast.exact])

# --- 7. EffectManager ---

func _test_effects() -> void:
	var game := _make_game()
	var events := _watch(game)
	var systems := _systems(game)
	var effects: Node = systems["effects"]
	var hits: Node = systems["hits"]
	var score: Node = systems["score"]
	var speed: Node = systems["speed"]
	var spawner: Node = systems["spawner"]

	effects.apply(&"approve_shield")
	check(hits.shield, "7: Approve Shield is stored on the hit manager")
	check(score.score == 25, "7: every pickup pays the flat bonus")
	check(events["power_up_collected"].size() == 1 and events["power_up_collected"][0][0] == &"approve_shield",
		"7: power_up_collected names the kind")
	check(is_equal_approx(float(events["power_up_collected"][0][1]), 0.0),
		"7: a one-shot pickup reports duration 0")

	# Refresh, never stack.
	effects.apply(&"lgtm")
	check(effects.is_active(&"lgtm") and hits.is_invulnerable(), "7: LGTM grants invulnerability")
	check(is_equal_approx(float(effects.get_active_effects()[&"lgtm"]["total"]), 5.0),
		"7: LGTM lasts 5 s")
	_tick([effects], _ticks(3.0))
	effects.apply(&"lgtm")
	var refreshed := float(effects.get_active_effects()[&"lgtm"]["remaining"])
	check(absf(refreshed - 5.0) < 0.05, "7: a second LGTM refreshes to 5 s, got %f" % refreshed)
	check(events["power_up_expired"].is_empty(), "7: refreshing never expires the first activation")
	_tick([effects], _ticks(5.05))
	check(not effects.is_active(&"lgtm"), "7: LGTM ends on time")
	check(not hits.is_invulnerable(), "7: LGTM gives its invulnerability back")
	check(events["power_up_expired"].size() == 1 and events["power_up_expired"][0] == &"lgtm",
		"7: power_up_expired fires once per activation")

	# Nitro: speed multiplier, score multiplier, invulnerability through the ease-down.
	effects.apply(&"nitro")
	check(is_equal_approx(float(speed.multiplier), 1.25), "7: Nitro drives the speed multiplier")
	check(score.nitro_active, "7: Nitro doubles the score rate")
	check(hits.is_invulnerable(), "7: Nitro grants invulnerability")
	check(is_equal_approx(float(events["power_up_collected"][3][1]), 8.0), "7: Nitro reports 8 s")
	_tick([effects], _ticks(8.05))
	check(not effects.is_active(&"nitro"), "7: Nitro ends after 8 s")
	check(not score.nitro_active, "7: the score multiplier ends with Nitro")
	check(hits.is_invulnerable(), "7: the i-frames survive into the ease-down")
	check(float(speed.multiplier) < 1.25 and float(speed.multiplier) > 1.0,
		"7: the speed eases down, got %f" % speed.multiplier)
	_tick([effects], _ticks(1.05))
	check(is_equal_approx(float(speed.multiplier), 1.0), "7: the ease-down lands on 1.0")
	check(not hits.is_invulnerable(), "7: the ease-down releases the invulnerability")

	# Super Jump: one token, consumed once.
	effects.apply(&"super_jump")
	check(effects.has_super_jump(), "7: Super Jump stores a token")
	check(effects.consume_super_jump(), "7: the token is spendable")
	check(not effects.consume_super_jump(), "7: the token is spent only once")
	var expired: Array = events["power_up_expired"]
	check(expired[expired.size() - 1] == &"super_jump", "7: spending the token reports it")

	# Code Review Bonus until an unblocked hit.
	effects.apply(&"code_review")
	check(score.code_review_active, "7: Code Review raises the multiplier")
	effects.on_damage_applied()
	check(not score.code_review_active and not effects.has_code_review(),
		"7: an unblocked hit drops Code Review")

	# Auto-Fix pays per hazard and announces the blast once.
	spawner.cleared = 3
	var before: int = score.score
	effects.apply(&"auto_fix")
	check(int(spawner.calls) == 1, "7: Auto-Fix asks the spawner once")
	check(score.score == before + 3 * 10 + 25, "7: Auto-Fix pays 10 per hazard plus the pickup bonus")
	check(events["hazards_blasted"].size() == 1 and int(events["hazards_blasted"][0]) == 3,
		"7: hazards_blasted reports the count once")
	check(effects.power_ups_collected == 7, "7: every pickup is counted")
	effects.reset()
	check(effects.get_active_effects().is_empty() and not effects.has_super_jump(),
		"7: reset clears every effect")

# --- 8. Leaderboard ---

func _test_leaderboard() -> void:
	check(RunnerLeaderboard.sanitize_name("  Test  ") == "Test", "8: names are trimmed")
	check(RunnerLeaderboard.sanitize_name("") == "Hoppy", "8: a blank name falls back to Hoppy")
	check(RunnerLeaderboard.sanitize_name("   ") == "Hoppy", "8: whitespace falls back to Hoppy")
	check(RunnerLeaderboard.sanitize_name("a\tb\nc") == "abc", "8: control characters are dropped")
	check(RunnerLeaderboard.sanitize_name("0123456789abcdefghij").length() == 16, "8: names cap at 16")

	var path := "user://test_leaderboard_%d.cfg" % (randi() % 1000000)
	temp_paths.append(path)
	check(RunnerLeaderboard.load_entries(path).is_empty(), "8: a missing board loads empty")
	for i in 12:
		var result := RunnerLeaderboard.submit(_entry("run-%d" % i, 100 + i * 10), path)
		check(int(result["error"]) == OK, "8: submit %d persisted" % i)
	var entries := RunnerLeaderboard.load_entries(path)
	check(entries.size() == 10, "8: the board keeps ten entries, got %d" % entries.size())
	check(int(entries[0]["score"]) == 210 and int(entries[9]["score"]) == 120,
		"8: the board is sorted by score")
	check(not FileAccess.file_exists(path + ".tmp"), "8: no .tmp is left behind")
	check(not FileAccess.file_exists(path + ".bak"), "8: no .bak is left behind")
	var stored := ConfigFile.new()
	check(stored.load(path) == OK, "8: the board file parses")
	check(int(stored.get_value("meta", "version", 0)) == RunnerLeaderboard.SCHEMA_VERSION,
		"8: the schema version is stored")

	var repeat := RunnerLeaderboard.submit(_entry("run-11", 500), path)
	check(int(repeat["rank"]) == 1, "8: a better run takes the top spot")
	check(RunnerLeaderboard.load_entries(path).size() == 10, "8: resubmitting a run_id never grows the board")
	check(RunnerLeaderboard.rename("run-11", "  Hoppy Jr  ", path) == OK, "8: rename succeeds")
	var renamed := RunnerLeaderboard.load_entries(path)
	check(String(renamed[0]["name"]) == "Hoppy Jr", "8: the renamed entry is sanitised")
	check(renamed.size() == 10, "8: rename never adds an entry")
	check(RunnerLeaderboard.rename("missing", "X", path) == ERR_DOES_NOT_EXIST,
		"8: renaming an unknown run fails")

	var corrupt := "user://test_leaderboard_corrupt_%d.cfg" % (randi() % 1000000)
	temp_paths.append(corrupt)
	var file := FileAccess.open(corrupt, FileAccess.WRITE)
	check(file != null, "8: the corrupt fixture was written")
	if file != null:
		file.store_string("this is not a ConfigFile {{{")
		file.close()
	check(RunnerLeaderboard.load_entries(corrupt).is_empty(), "8: a corrupt board loads empty")
	var recovered := RunnerLeaderboard.submit(_entry("run-fresh", 42), corrupt)
	check(int(recovered["error"]) == OK and int(recovered["rank"]) == 1,
		"8: a corrupt board still accepts the next run")
	check(RunnerLeaderboard.load_entries(corrupt).size() == 1, "8: the recovered board holds one entry")

# --- 9. RunConfig sanity ---

func _test_config_sanity() -> void:
	var c := base_config
	# systems spec §1: an Area3D overlap can never tunnel at the Nitro cap.
	var per_tick := float(c.hard_cap_speed) * float(c.nitro_speed_multiplier) / 60.0
	var overlap_ticks := (float(c.min_hazard_depth) + 0.8) / per_tick
	check(overlap_ticks >= 2.0, "9: hazards overlap for %.2f ticks, need 2" % overlap_ticks)
	var apex := float(c.jump_velocity) * float(c.jump_velocity) / (2.0 * float(c.gravity))
	check(apex >= 1.6, "9: the jump apex is %.3f m, need 1.6" % apex)
	var super_apex := float(c.super_jump_velocity) * float(c.super_jump_velocity) / (2.0 * float(c.gravity))
	check(super_apex >= 3.0, "9: the super jump apex is %.3f m, need 3.0" % super_apex)
	check(int(c.max_hp) == 2 and is_equal_approx(float(c.recovery_seconds), 18.0),
		"9: health tuning matches contract §7")
	check(is_equal_approx(float(c.hit_iframes), 0.8)
		and is_equal_approx(float(c.caught_sequence_seconds), 1.6), "9: hit tuning matches contract §7")
	check(is_equal_approx(float(c.base_speed), 12.0) and is_equal_approx(float(c.max_speed), 24.0)
		and is_equal_approx(float(c.time_to_max_speed), 165.0), "9: speed tuning matches contract §7")
	check(float(c.hard_cap_speed) >= float(c.max_speed)
		and float(c.nitro_speed_cap) >= float(c.hard_cap_speed) * float(c.nitro_speed_multiplier) - 0.5,
		"9: the speed caps are ordered")
	check(is_equal_approx(float(c.base_score_rate), 10.0) and int(c.pickup_bonus) == 25
		and int(c.blast_bonus_per_hazard) == 10, "9: score tuning matches contract §7")
	check(is_equal_approx(float(c.nitro_score_multiplier), 2.0)
		and is_equal_approx(float(c.code_review_score_multiplier), 1.5), "9: the multipliers match contract §7")
	check(is_equal_approx(float(c.lane_width), 2.0) and is_equal_approx(float(c.lane_change_time), 0.13),
		"9: lane tuning matches contract §7")
	check(is_equal_approx(c.t_spacing(0.0), 1.2) and is_equal_approx(c.t_spacing(1.0), 0.85),
		"9: t_spacing runs 1.2 -> 0.85")
	check(is_equal_approx(c.powerup_chance(0.0), 0.55) and is_equal_approx(c.powerup_chance(1.0), 0.35),
		"9: the power-up chance runs 0.55 -> 0.35")
	check(int(c.max_active_chunks) == 9 and is_equal_approx(float(c.spawn_horizon_z), -90.0)
		and is_equal_approx(float(c.despawn_z), 12.0), "9: spawner tuning matches contract §7")
	check(is_equal_approx(c.lane_x(0), -2.0) and is_equal_approx(c.lane_x(1), 0.0)
		and is_equal_approx(c.lane_x(2), 2.0), "9: lane centres are -2 / 0 / +2")

# --- 10. Autopilot planning (the half the chunk validator reuses) ---

func _test_autopilot() -> void:
	var game := _make_game()
	var bot: Node = autopilot_script.new()
	junk.append(bot)
	bot.setup(game)
	check(not bot.enabled, "10: the bot never switches itself on")

	var wall := _hazard(&"pr_backlog_low")
	wall.position = Vector3(0.0, 0.0, -20.0)
	var slices: Array = bot.slices_for([wall], 24.0, 0.0)
	check(slices.size() == 1, "10: one hazard is one slice")
	check(int(slices[0]["blocked"]) == 0b111, "10: a full-width wall blocks every lane")
	check(bool(slices[0]["jumpable"]) and not bool(slices[0]["rollable"]),
		"10: a low wall is jumpable, not rollable")
	var plan: Dictionary = bot.plan_for(slices[0], 1)
	check(StringName(plan["action"]) == bot.ACTION_JUMP, "10: PREFER_LANE jumps what it cannot dodge")

	var swarm := _hazard(&"bug_swarm")
	swarm.box = Vector3(1.6, 0.9, 1.2)
	swarm.center_y = 0.45
	swarm.dodge_hint = &"JUMP_OR_LANE"
	swarm.position = Vector3(0.0, 0.0, -20.0)
	var lane_slices: Array = bot.slices_for([swarm], 24.0, 0.0)
	check(int(lane_slices[0]["blocked"]) == 0b010, "10: a one-lane swarm blocks the centre only")
	check(StringName(bot.plan_for(lane_slices[0], 1)["action"]) == bot.ACTION_LANE,
		"10: PREFER_LANE steps aside")
	bot.set_mode(bot.Mode.PREFER_JUMP)
	check(StringName(bot.plan_for(lane_slices[0], 1)["action"]) == bot.ACTION_JUMP,
		"10: PREFER_JUMP jumps the same slice")
	bot.set_mode(bot.Mode.PREFER_LANE)

	var flood := _hazard(&"comment_flood")
	flood.box = Vector3(3.6, 4.0, 1.2)
	flood.center_y = 2.0
	flood.dodge_hint = &"LANE"
	flood.position = Vector3(-1.0, 0.0, -20.0)
	var flood_slices: Array = bot.slices_for([flood], 24.0, 0.0)
	check(int(flood_slices[0]["blocked"]) == 0b011, "10: a two-lane flood blocks lanes 0 and 1")
	var flood_plan: Dictionary = bot.plan_for(flood_slices[0], 1)
	check(StringName(flood_plan["action"]) == bot.ACTION_LANE and int(flood_plan["lane"]) == 2,
		"10: the only answer to a wall of comments is the free lane")
	bot.set_mode(bot.Mode.PREFER_JUMP)
	check(StringName(bot.plan_for(flood_slices[0], 1)["action"]) == bot.ACTION_LANE,
		"10: even PREFER_JUMP takes the lane when a hazard is too tall")
	bot.set_mode(bot.Mode.PREFER_LANE)

	var bar := _hazard(&"pr_backlog_high")
	bar.box = Vector3(5.6, 1.8, 1.2)
	bar.center_y = 2.0
	bar.dodge_hint = &"ROLL"
	bar.position = Vector3(0.0, 0.0, -20.5)
	var merged: Array = bot.slices_for([wall, bar], 24.0, 0.0)
	check(merged.size() == 1, "10: hazards within 0.8 m are one slice")
	check(not bool(merged[0]["jumpable"]) and not bool(merged[0]["rollable"]),
		"10: a merged slice only claims what answers all of it")
	check(int(merged[0]["key"]) == wall.get_instance_id(),
		"10: a merged slice is keyed by its nearest hazard")

	# A merged slice keeps one key for its whole life. Keying it by the smallest instance id of the
	# moment moved the key as hazards entered and left the scan range, so an already-answered slice
	# came back under a new key and earned a second manoeuvre.
	var merged_key := StringName(str(merged[0]["key"]))
	bot._done[merged_key] = true
	var tail_only: Array = bot.slices_for([bar], 24.0, 0.0)
	check(tail_only.size() == 1 and StringName(str(tail_only[0]["key"])) == merged_key,
		"10: a merged slice keeps its key when the hazard that owns it is gone")
	bot._prune(tail_only, [])
	check(bot._next_slice(tail_only).is_empty(),
		"10: an answered merged slice is never planned a second time")
	bot.reset()

	# A high pickup hangs over one lane: the jump only reaches it from that lane.
	var high_pickup := _pickup(Vector3(2.0, 1.8, -20.0))
	var pickups: Array = bot.pickup_targets([high_pickup], 24.0)
	check(pickups.size() == 1 and int(pickups[0]["lane"]) == 2 and bool(pickups[0]["high"]),
		"10: a pickup above running height in lane 2 is read as high")
	var detour: Dictionary = bot.plan_pickup(pickups, [], 1, 24.0)
	check(StringName(detour["action"]) == bot.ACTION_LANE and int(detour["lane"]) == 2
		and int(detour["steps"]) == 1, "10: a high pickup in another lane is approached by lane")
	var hop: Dictionary = bot.plan_pickup(pickups, [], 2, 24.0)
	check(StringName(hop["action"]) == bot.ACTION_JUMP,
		"10: a high pickup is jumped once the player is in its lane")
	var late := _pickup(Vector3(2.0, 1.8, -1.0))
	var late_targets: Array = bot.pickup_targets([late], 24.0)
	check(StringName(bot.plan_pickup(late_targets, [], 1, 24.0)["action"]) == bot.ACTION_NONE,
		"10: a high pickup too close to change lanes for is left alone")

	# A lane plan is answered by arrival, not by one request: marking it done after the first
	# transition left a two-step move stranded in the lane it was only passing through.
	var mover: Node = _fake_player()
	mover.target_lane = 0
	var two_step := {"action": bot.ACTION_LANE, "lane": 2, "steps": 2}
	var lane_key := StringName("two-step")
	bot._execute(two_step, 0.0, 24.0, mover, lane_key)
	check(int(mover.target_lane) == 1 and not bot._done.has(lane_key),
		"10: the first transition of a two-step lane plan does not answer it")
	bot._execute(two_step, 0.0, 24.0, mover, lane_key)
	check(int(mover.queued_lane_dir) == 1, "10: the second step is queued behind the running tween")
	var issued := int(mover.requests)
	bot._execute(two_step, 0.0, 24.0, mover, lane_key)
	bot._execute(two_step, 0.0, 24.0, mover, lane_key)
	check(int(mover.requests) == issued,
		"10: the bot does not spam request_lane while a change is already queued")
	check(not bot._done.has(lane_key), "10: the plan stays pending in the lane it passes through")
	mover.finish_tween()
	check(int(mover.target_lane) == 2, "10: the queued step starts when the tween ends")
	bot._execute(two_step, 0.0, 24.0, mover, lane_key)
	check(bot._done.has(lane_key), "10: the lane plan is answered by reaching the target lane")
	bot.reset()

	check(is_equal_approx(bot.jump_trigger_z(24.0), -(24.0 * 0.22 + 0.4)), "10: the jump lead is 0.22 s")
	check(is_equal_approx(bot.roll_trigger_z(24.0), -(24.0 * 0.15 + 0.4)), "10: the roll lead is 0.15 s")
	check(is_equal_approx(bot.plan_trigger_z(24.0), -(24.0 * 0.6 + 0.4)), "10: the plan lead is 0.6 s")

	check(bot.timed_state_at(0.0) == &"ground", "10: the timed laser starts on the ground")
	check(bot.timed_state_at(1.3) == &"off", "10: the timed laser blinks off at 1.2 s")
	check(bot.timed_state_at(2.0) == &"high", "10: the timed laser rises at 1.5 s")
	check(bot.timed_state_at(2.8) == &"off", "10: the timed laser blinks off at 2.7 s")
	check(bot.timed_state_at(3.1) == &"ground", "10: the timed laser cycle repeats every 3 s")

	var laser := _hazard(&"laser_grid")
	laser.box = Vector3(5.6, 0.4, 1.2)
	laser.center_y = 0.3
	laser.dodge_hint = &"TIMED"
	laser.position = Vector3(0.0, 0.0, -6.0)
	check(bot.slices_for([laser], 24.0, 0.0).size() == 1, "10: an active timed laser is a slice")
	check(bot.slices_for([laser], 24.0, 1.05).is_empty(), "10: an off timed laser is not a threat")
	var high_slice: Array = bot.slices_for([laser], 24.0, 1.6)
	check(high_slice.size() == 1 and bool(high_slice[0]["rollable"]),
		"10: the high phase of the timed laser is rolled under")

	bot.set_reckless(1)
	check(bot.reckless_slices == 1, "10: reckless mode is armed by slice count")
	bot.reset()
	check(not bot.enabled and bot.reckless_slices == 0, "10: reset disables the bot")

# --- 11. The real hazard: a finished timed laser shuts down (systems spec §5.3, contract §8) ---

## The only hazard with a per-tick state machine is the timed laser, and it is the only one that can
## outlive its own removal: once Auto-Fix clears it, or once it has taken its one hit, it must stop
## advancing. A laser that keeps cycling re-arms `monitoring` on its next `on` slot, keeps driving
## set_laser_state()/set_telegraph() on a visual that was told it is gone, and re-shows the graybox
## that clear() just hid.
func _test_timed_laser_shutdown() -> void:
	var armed := _timed_laser()
	var laser: Area3D = armed["hazard"]
	check(laser.is_timed(), "11: laser_grid/timed owns a state machine")
	_run_laser(armed, 0.1)
	check(laser.laser_state == &"ground", "11: the cycle opens on the ground phase, got %s" % laser.laser_state)
	check(laser.monitoring, "11: an on-phase laser arms its hitbox")
	_run_laser(armed, 1.2)
	check(laser.laser_state == OFF_STATE, "11: the cycle blinks off after 1.2 s, got %s" % laser.laser_state)
	check(not laser.monitoring, "11: the hitbox is disarmed between states")
	check(laser.is_blocking(), "11: an off laser is still blocking, it comes back")
	_run_laser(armed, 0.6)
	check(laser.laser_state == &"high" and laser.monitoring, "11: the hitbox re-arms on the high phase")

	# Auto-Fix cleared it.
	var cleared_pair := _timed_laser()
	var cleared: Area3D = cleared_pair["hazard"]
	_run_laser(cleared_pair, 0.1)
	check(cleared.monitoring, "11: the laser was armed before clear()")
	cleared.clear()
	var state_at_clear: StringName = cleared.laser_state
	check(not cleared.is_blocking(), "11: clear() stops the hazard blocking")
	check(not cleared.is_physics_processing(), "11: clear() stops the timed cycle")
	check(not cleared.is_in_group(&"runner_hazards"), "11: a cleared hazard leaves the group")
	check(not cleared.visual.visible, "11: clear() hides the graybox")
	# A full 3 s period: without the shutdown this walks ground -> off -> high -> off -> ground.
	_check_laser_inert(cleared_pair, 3.0, state_at_clear, "a cleared laser")
	check(not cleared.visual.visible, "11: a cleared laser never re-shows its graybox")

	# It took its one hit.
	var hit_pair := _timed_laser()
	var hit: Area3D = hit_pair["hazard"]
	var hits: Node = hit_pair["hits"]
	_run_laser(hit_pair, 0.1)
	check(hit.monitoring, "11: the laser was armed before hit_player()")
	hit.hit_player(null)
	var state_at_hit: StringName = hit.laser_state
	check(hit.consumed and not hit.is_blocking(), "11: the hit consumes the hazard")
	check(hits.hits_taken == 1, "11: the hit reached the hit manager")
	check(not hit.is_physics_processing(), "11: hit_player() stops the timed cycle")
	_check_laser_inert(hit_pair, 3.0, state_at_hit, "a consumed laser")
	check(hits.hits_taken == 1, "11: the consumed laser never reported a second hit")

# --- harness ---

func _compile(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		return null
	return script

## A RunnerGame facade with no children: the systems only ever touch its signals, its state and the
## manager references the test wires up by hand.
func _make_game() -> Node3D:
	var game := Node3D.new()
	game.set_script(game_script)
	game.config = base_config.duplicate()
	game.state = &"running"
	junk.append(game)
	return game

## Fresh systems for one facade, wired to each other exactly as runner_game.tscn wires them.
func _systems(game: Node3D) -> Dictionary:
	var hits: Node = hit_manager_script.new()
	var score: Node = score_manager_script.new()
	var effects: Node = effect_manager_script.new()
	var speed: Node = speed_controller_script.new()
	var spawner := Node.new()
	spawner.set_script(spawner_script)
	for node in [hits, score, effects, speed, spawner]:
		junk.append(node)
	game.hit_manager = hits
	game.score_manager = score
	game.effect_manager = effects
	game.speed_controller = speed
	game.spawner = spawner
	hits.setup(game)
	score.setup(game)
	effects.setup(game)
	speed.setup(game)
	return {"hits": hits, "score": score, "effects": effects, "speed": speed, "spawner": spawner}

## Hazards live under `root` because global_position is only defined inside the tree, and the
## autopilot reads hazards exactly the way it does in a live run.
func _hazard(kind: StringName) -> Node3D:
	var hazard := Node3D.new()
	hazard.set_script(hazard_script)
	hazard.kind = kind
	root.add_child(hazard)
	junk.append(hazard)
	return hazard

## A power-up stand-in for the autopilot's greedy planner: pickup_targets only reads
## global_position, so a bare Node3D in the tree is the whole surface.
func _pickup(at: Vector3) -> Node3D:
	var pickup := Node3D.new()
	root.add_child(pickup)
	pickup.position = at
	junk.append(pickup)
	return pickup

## A player stand-in with only the lane state the autopilot reads and drives.
func _fake_player() -> Node:
	var player := Node.new()
	player.set_script(player_script)
	junk.append(player)
	return player

## A real hazard.gd timed laser, in the tree (its hitbox and group need it) and on its own facade
## with a real HitManager behind it. kind/variant are set before the hazard enters the tree so
## _ready() builds the timed def.
func _timed_laser() -> Dictionary:
	var game := _make_game()
	var systems := _systems(game)
	var laser := Area3D.new()
	laser.set_script(real_hazard_script)
	laser.kind = &"laser_grid"
	laser.variant = &"timed"
	root.add_child(laser)
	laser.setup(game)
	junk.append(laser)
	return {"game": game, "hazard": laser, "hits": systems["hits"]}

## Drive a real timed laser by hand, advancing the run clock its cycle is phased off. The call is
## unconditional on purpose: a hazard that stopped its own physics processing must still be inert
## when _physics_process() is reached anyway.
func _run_laser(pair: Dictionary, seconds: float) -> void:
	var game: Node3D = pair["game"]
	var laser: Area3D = pair["hazard"]
	for i in _ticks(seconds):
		game.elapsed += TICK
		laser._physics_process(TICK)

## Advance a finished laser `seconds` in 0.5 s slices, asserting after each that it is still inert.
## One 3 s jump would land back on the same phase of the 3 s cycle and hide a machine that never
## stopped, so the invariants have to be checked mid-cycle as well.
func _check_laser_inert(pair: Dictionary, seconds: float, state: StringName, tag: String) -> void:
	var laser: Area3D = pair["hazard"]
	var elapsed := 0.0
	while elapsed < seconds - 0.0001:
		var slice := minf(0.5, seconds - elapsed)
		_run_laser(pair, slice)
		elapsed += slice
		check(not laser.monitoring, "11: %s never re-arms monitoring (at %.1f s)" % [tag, elapsed])
		check(not laser.is_blocking(), "11: %s stays finished (at %.1f s)" % [tag, elapsed])
		check(laser.laser_state == state, "11: %s stops advancing its state (at %.1f s), got %s"
			% [tag, elapsed, laser.laser_state])

func _entry(run_id: String, score: int) -> Dictionary:
	return {
		"run_id": run_id,
		"name": "Hoppy",
		"score": score,
		"duration": float(score) / 10.0,
		"seed": 1234,
		"submitted_at": 1700000000
	}

## Physics ticks worth `seconds`, rounded to the nearest whole tick.
func _ticks(seconds: float) -> int:
	return int(roundf(seconds / TICK))

## Drive systems by hand, in the order runner_game.tscn processes them.
func _tick(nodes: Array, count: int, delta := TICK) -> void:
	for i in count:
		for node in nodes:
			node._physics_process(delta)

## Record every contract §4.1 signal the systems emit.
func _watch(game: Node) -> Dictionary:
	var events := {
		"damage_taken": [],
		"damage_blocked": [],
		"health_changed": [],
		"shield_changed": [],
		"pursuit_started": [],
		"pursuit_recovered": [],
		"pursuit_progress": 0,
		"caught": 0,
		"score_changed": [],
		"bonus_awarded": [],
		"power_up_collected": [],
		"power_up_expired": [],
		"hazards_blasted": []
	}
	game.damage_taken.connect(func(kind: StringName, hp: int) -> void:
		events["damage_taken"].append([kind, hp]))
	game.damage_blocked.connect(func(kind: StringName, reason: StringName) -> void:
		events["damage_blocked"].append([kind, reason]))
	game.health_changed.connect(func(hp: int, max_hp: int) -> void:
		events["health_changed"].append([hp, max_hp]))
	game.shield_changed.connect(func(active: bool) -> void:
		events["shield_changed"].append(active))
	game.pursuit_started.connect(func(seconds: float) -> void:
		events["pursuit_started"].append(seconds))
	game.pursuit_recovered.connect(func(reason: StringName) -> void:
		events["pursuit_recovered"].append(reason))
	game.pursuit_progress.connect(func(_remaining: float, _total: float) -> void:
		events["pursuit_progress"] += 1)
	game.caught.connect(func() -> void:
		events["caught"] += 1)
	game.score_changed.connect(func(score: int, multiplier: float) -> void:
		events["score_changed"].append([score, multiplier]))
	game.bonus_awarded.connect(func(points: int, reason: StringName) -> void:
		events["bonus_awarded"].append([points, reason]))
	game.power_up_collected.connect(func(kind: StringName, duration: float) -> void:
		events["power_up_collected"].append([kind, duration]))
	game.power_up_expired.connect(func(kind: StringName) -> void:
		events["power_up_expired"].append(kind))
	game.hazards_blasted.connect(func(count: int) -> void:
		events["hazards_blasted"].append(count))
	return events

func _report() -> void:
	for path in temp_paths:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	for node in junk:
		if is_instance_valid(node):
			node.free()
	junk.clear()
	# Drop the runtime harness scripts so nothing outlives the SceneTree.
	game_script = null
	hazard_script = null
	spawner_script = null
	player_script = null
	print("RUNNER LOGIC: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures / ", checks, " checks)")
	quit(failures)
