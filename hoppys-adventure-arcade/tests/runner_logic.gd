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
const StageDefs = preload("res://scenes/runner/data/stage_defs.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
const ARENA_SCENE := "res://scenes/runner/boss/boss_arena.tscn"
const TICK := 1.0 / 60.0
## The timed laser slot with the hitbox off (hazard.gd OFF_STATE).
const OFF_STATE: StringName = &"off"
## Contract §11.1 phases, in the order one stage runs through them. The drain is the tail of `run`
## and hands straight to `boss` on the tick it ends.
const STAGE_PHASES: Array[StringName] = [&"run", &"boss", &"stage_clear"]

## RunnerGame with a countable catch hook: HitManager calls _on_caught(), the facade emits `caught`.
const FAKE_GAME_SOURCE := "extends \"res://scenes/runner/runner_game.gd\"\nvar caught_calls := 0\nfunc _on_caught() -> void:\n\tcaught_calls += 1\n\tcaught.emit()\n"
## The same hook, but running the real catch cinematic underneath it: section 22 needs the facade to
## move to `caught` and time itself out to _finish_run().
const FAKE_CAUGHT_GAME_SOURCE := "extends \"res://scenes/runner/runner_game.gd\"\nvar caught_calls := 0\nfunc _on_caught() -> void:\n\tcaught_calls += 1\n\tsuper()\n"
## The real catch cinematic plus a recorded router: section 24b drives retry() / retry_boss() and
## must see the route they ask for without the harness actually changing scene.
const FAKE_ROUTE_GAME_SOURCE := "extends \"res://scenes/runner/runner_game.gd\"\nvar caught_calls := 0\nvar routes: Array = []\nfunc _on_caught() -> void:\n\tcaught_calls += 1\n\tsuper()\nfunc _route(route: String) -> void:\n\troutes.append(route)\n"
## The hazard surface HitManager, the StageManager drain and Autopilot actually use (systems §5.3).
const FAKE_HAZARD_SOURCE := "extends Node3D\nvar kind: StringName = &\"pr_backlog_low\"\nvar dodge_hint: StringName = &\"JUMP\"\nvar box := Vector3(5.6, 1.0, 1.2)\nvar center_y := 0.5\nvar blocking := true\nvar cleared := 0\nfunc is_blocking() -> bool:\n\treturn blocking\nfunc clear() -> void:\n\tcleared += 1\n\tblocking = false\n\tremove_from_group(&\"runner_hazards\")\nfunc occupies_lane(index: int) -> bool:\n\treturn absf((float(index) - 1.0) * 2.0 - global_position.x) < box.x * 0.5 + 0.39\nfunc get_world_aabb() -> AABB:\n\treturn AABB(global_position + Vector3(0.0, center_y, 0.0) - box * 0.5, box)\n"
## A boss shot: the same surface as the hazard stand-in plus the `closing_speed` that makes the bot
## read it as a projectile and plan its trigger from its own speed (systems spec §10.6).
const FAKE_PROJECTILE_SOURCE := "extends Node3D\nvar kind: StringName = &\"projectile\"\nvar variant: StringName = &\"orb\"\nvar dodge_hint: StringName = &\"JUMP_OR_LANE\"\nvar closing_speed := 26.0\nvar box := Vector3(1.6, 0.9, 1.2)\nvar center_y := 0.45\nvar blocking := true\nfunc is_blocking() -> bool:\n\treturn blocking\nfunc occupies_lane(index: int) -> bool:\n\treturn absf((float(index) - 1.0) * 2.0 - global_position.x) < box.x * 0.5 + 0.39\nfunc get_world_aabb() -> AABB:\n\treturn AABB(global_position + Vector3(0.0, center_y, 0.0) - box * 0.5, box)\n"
## Spawner stand-in for Auto-Fix (systems spec §5.2), the stage drain gate (§10.6) and the
## stage-entrance window (contract §11.1). `call_log` keeps the two gates in one ordered list, so a
## window opened after the corridor was already topped up is visible; `spawn_calls` stays exactly
## what the drain checks have always read.
const FAKE_SPAWNER_SOURCE := "extends Node\nvar cleared := 0\nvar calls := 0\nvar spawning := true\nvar spawn_calls: Array = []\nvar clear_road_calls: Array = []\nvar call_log: Array = []\nfunc clear_hazards_in_range() -> int:\n\tcalls += 1\n\treturn cleared\nfunc set_spawning(on: bool) -> void:\n\tspawning = on\n\tspawn_calls.append(on)\n\tcall_log.append(&\"spawning_on\" if on else &\"spawning_off\")\nfunc begin_clear_road(seconds: float) -> void:\n\tclear_road_calls.append(seconds)\n\tcall_log.append(&\"clear_road\")\n"
## TurnRig / CameraRig stand-in. The rig is a static mount: nothing in the stage machine rotates it.
## shake() is what the catch cinematic reaches for on the camera.
const FAKE_RIG_SOURCE := "extends Node3D\nvar shakes: Array = []\nfunc shake(strength: float, _duration := 0.35) -> void:\n\tshakes.append(strength)\n"
## The contract §5.1 visual hooks reset() has to clear, recorded instead of drawn.
const FAKE_VISUAL_SOURCE := "extends Node3D\nvar auras: Array = []\nvar shields: Array = []\nfunc show_aura(kind: StringName, on: bool) -> void:\n\tauras.append([kind, on])\nfunc show_shield(on: bool) -> void:\n\tshields.append(on)\n"
## The contract §5.2 hazard visual hooks, recorded. It extends the real hazard_visual_base.gd, so a
## hook the backend calls under a name the base does not declare shows up here as a miss.
const FAKE_HAZARD_VISUAL_SOURCE := "extends \"res://scenes/runner/hazards/hazard_visual_base.gd\"\nvar cleared_calls := 0\nvar hit_calls := 0\nvar laser_states: Array = []\nvar telegraphs: Array = []\nfunc on_cleared() -> void:\n\tcleared_calls += 1\nfunc on_hit_player() -> void:\n\thit_calls += 1\nfunc set_laser_state(state: StringName) -> void:\n\tlaser_states.append(state)\nfunc set_telegraph(t: float) -> void:\n\ttelegraphs.append(t)\n"
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
## The real runner_player.gd (CharacterBody3D), used by section 12; also loaded at runtime.
var real_player_script: GDScript
var spawner_script: GDScript
## The real chunk_spawner.gd, used by section 29; loaded at runtime like every other system script.
var real_spawner_script: GDScript
var player_script: GDScript
var projectile_script: GDScript
var rig_script: GDScript
var caught_game_script: GDScript
var route_game_script: GDScript
## runner_game.gd itself, for its static pending_boss_checkpoint.
var runner_game_script: GDScript
var hit_manager_script: GDScript
var score_manager_script: GDScript
var effect_manager_script: GDScript
var speed_controller_script: GDScript
var stage_manager_script: GDScript
var camera_rig_script: GDScript
var pursuer_script: GDScript
var autopilot_script: GDScript
## Everything this test built, freed in _report().
var junk: Array[Node] = []
var temp_paths: Array[String] = []
## Every facade this test builds points here, so a run that reaches _finish_run() can never touch
## the player's real user://leaderboard.cfg — including one that was never meant to finish. The
## sections that assert on a board override it with a path of their own.
var scratch_leaderboard := "user://test_leaderboard_scratch_%d.cfg" % (randi() % 1000000)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER LOGIC: " + message)

func run() -> void:
	temp_paths.append(scratch_leaderboard)
	base_config = (load(CONFIG_PATH) as RunConfig).duplicate()
	# Contract 2.7 §11.15 plays a run intro in front of every facade start_run. This suite is about
	# the corridor and the boss machine, so the duplicate it hands out turns that intro off.
	base_config.run_intro_enabled = false
	hit_manager_script = load("res://scenes/runner/systems/hit_manager.gd") as GDScript
	score_manager_script = load("res://scenes/runner/systems/score_manager.gd") as GDScript
	effect_manager_script = load("res://scenes/runner/systems/effect_manager.gd") as GDScript
	speed_controller_script = load("res://scenes/runner/systems/speed_controller.gd") as GDScript
	stage_manager_script = load("res://scenes/runner/systems/stage_manager.gd") as GDScript
	camera_rig_script = load("res://scenes/runner/systems/camera_rig.gd") as GDScript
	pursuer_script = load("res://scenes/runner/pursuer/pursuer.gd") as GDScript
	autopilot_script = load("res://scenes/runner/systems/autopilot.gd") as GDScript
	real_hazard_script = load("res://scenes/runner/hazards/hazard.gd") as GDScript
	real_player_script = load("res://scenes/runner/player/runner_player.gd") as GDScript
	real_spawner_script = load("res://scenes/runner/systems/chunk_spawner.gd") as GDScript
	game_script = _compile(FAKE_GAME_SOURCE)
	caught_game_script = _compile(FAKE_CAUGHT_GAME_SOURCE)
	route_game_script = _compile(FAKE_ROUTE_GAME_SOURCE)
	runner_game_script = load("res://scenes/runner/runner_game.gd") as GDScript
	hazard_script = _compile(FAKE_HAZARD_SOURCE)
	spawner_script = _compile(FAKE_SPAWNER_SOURCE)
	player_script = _compile(FAKE_PLAYER_SOURCE)
	projectile_script = _compile(FAKE_PROJECTILE_SOURCE)
	rig_script = _compile(FAKE_RIG_SOURCE)
	if game_script == null or hazard_script == null or spawner_script == null \
			or player_script == null or real_hazard_script == null or real_player_script == null \
			or rig_script == null or caught_game_script == null or stage_manager_script == null \
			or camera_rig_script == null or pursuer_script == null or projectile_script == null \
			or real_spawner_script == null or route_game_script == null or runner_game_script == null:
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
	_test_finish_write_failure()
	_test_clear()
	_test_config_sanity()
	_test_autopilot()
	_test_autopilot_boss()
	_test_timed_laser_shutdown()
	_test_super_jump_invuln()
	_test_dodge_tracking()
	_test_difficulty_emission()
	_test_hazard_visual_mount_order()
	_test_player_reset_clears_visual_state()
	_test_stage_machine()
	_test_escalation()
	_test_boss_fight()
	_test_boss_timeout()
	_test_pursuit_alert()
	_test_pursuer_distance()
	_test_caught_mid_boss()
	_test_boss_checkpoint()
	_test_boss_stage_seed()
	_test_stage_speed_and_floor()
	_test_leaderboard_migration()
	_test_camera_rest_pose()
	_test_boss_intro()
	_test_boss_signatures()
	# Last: this is the only section that drives a real chunk_spawner.gd, and the hazards it sweeps
	# are the whole runner_hazards group, so nothing else may still be leaning on it.
	_test_stage_banner_window()
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

	# The guarantee above rests on Godot's physics frame order — queries are flushed, and so
	# area_entered is emitted, before any _physics_process in that frame (measured on 4.7.0: an
	# overlap created in physics frame N arrives at the top of frame N+1). This half pins that the
	# order is load-bearing: run the timer first and the very same hit only opens a fresh pursuit,
	# so a change that resolves hits after the timer has to fail the checks above.
	var reversed := _make_game()
	var reversed_hits: Node = _systems(reversed)["hits"]
	reversed_hits.report_hit(_hazard(&"bug_swarm"))
	reversed_hits.iframe_remaining = 0.0
	reversed_hits.recovery_remaining = 0.005
	_tick([reversed_hits], 1)
	check(reversed_hits.state == reversed_hits.HitState.SAFE and reversed_hits.hp == 2,
		"3: with no hit delivered first, the timer alone recovers")
	var late: StringName = reversed_hits.report_hit(_hazard(&"merge_conflict"))
	check(late == reversed_hits.DAMAGED and reversed_hits.state == reversed_hits.HitState.PURSUED,
		"3: a hit resolved after the deadline only restarts pursuit, got %s" % late)
	check(int(reversed.caught_calls) == 0, "3: the reversed order never reaches the catch")

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
	# The shield pops on one hazard and grants the same i-frames the damage path does, so a second,
	# different hazard overlapping on one of the next ticks cannot land damage right after the block.
	check(is_equal_approx(hits.iframe_remaining, 0.8), "4: the shield block starts the i-frames, %.3f s"
		% hits.iframe_remaining)
	var follow_up: StringName = hits.report_hit(_hazard(&"merge_conflict"))
	check(follow_up == hits.BLOCKED_INVULN,
		"4: the hit right after a shield block is blocked by the i-frames, got %s" % follow_up)
	check(events["damage_blocked"].size() == 2 and events["damage_blocked"][1][1] == &"iframes",
		"4: the hit right after a shield block reports reason iframes")
	check(hits.hp == 2 and hits.state == hits.HitState.SAFE, "4: the follow-up block costs nothing")
	_tick([hits], _ticks(0.9))
	check(hits.report_hit(_hazard(&"comment_flood")) == hits.DAMAGED,
		"4: a hit once the shield i-frames have run out lands")

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
	check(is_equal_approx(pursued.iframe_remaining, 0.8),
		"4: the shield recovery starts the i-frames too, %.3f s" % pursued.iframe_remaining)
	var after_recovery: StringName = pursued.report_hit(_hazard(&"bug_swarm"))
	check(after_recovery == pursued.BLOCKED_INVULN,
		"4: the hit right after a shield recovery is blocked by the i-frames, got %s" % after_recovery)
	check(pursued.is_safe() and pursued.hp == 2, "4: the recovered runner keeps its health")

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

	# An unknown kind is not a pickup: it must not pay, count or announce anything. Falling through
	# the match into the shared tail would have credited a bonus for a power-up that does not exist.
	var unknown_score: int = score.score
	var unknown_collected: int = effects.power_ups_collected
	var unknown_signals: int = events["power_up_collected"].size()
	effects.apply(&"not_a_power_up")
	check(score.score == unknown_score, "7: an unknown kind pays no bonus, score moved to %d" % score.score)
	check(effects.power_ups_collected == unknown_collected,
		"7: an unknown kind is not counted, got %d" % effects.power_ups_collected)
	check(events["power_up_collected"].size() == unknown_signals,
		"7: an unknown kind emits no power_up_collected")

	effects.reset()
	check(effects.get_active_effects().is_empty() and not effects.has_super_jump(),
		"7: reset clears every effect")

	# A timed kind whose configured duration is not positive is refused outright: no timer, no
	# invulnerability source, and nothing counted or announced, so a mis-edited RunConfig cannot
	# leave LGTM permanently invulnerable behind a timer that expires on its first tick.
	var zero_game := _make_game()
	var zero_events := _watch(zero_game)
	var zero_systems := _systems(zero_game)
	var zero_effects: Node = zero_systems["effects"]
	var zero_hits: Node = zero_systems["hits"]
	var zero_score: Node = zero_systems["score"]
	var zero_config: RunConfig = zero_game.config.duplicate()
	zero_config.lgtm_duration = 0.0
	zero_effects.reset(zero_config)
	check(is_equal_approx(zero_effects.duration_for(&"lgtm"), 0.0),
		"7: the duplicated config reports a zero LGTM duration")
	zero_effects.apply(&"lgtm")
	check(not zero_effects.is_active(&"lgtm"), "7: a zero-duration LGTM never activates")
	check(not zero_hits.is_invulnerable(),
		"7: a refused LGTM adds no invulnerability source")
	check(zero_effects.power_ups_collected == 0, "7: a refused LGTM is not counted")
	check(zero_score.score == 0, "7: a refused LGTM pays no bonus")
	check(zero_events["power_up_collected"].is_empty(),
		"7: a refused LGTM emits no power_up_collected")
	# The same manager still applies a kind whose duration is fine, so the guard is not a blanket off.
	zero_effects.apply(&"nitro")
	check(zero_effects.is_active(&"nitro") and zero_effects.power_ups_collected == 1,
		"7: the guard only refuses the mis-configured kind")

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
	# Both are scratch files of the systems spec §7 write: the .tmp becomes the board and the .bak is
	# dropped once it is in place, so a successful write must leave neither. A .bak is only ever
	# retained for recovery, by a crash between the two renames.
	check(not FileAccess.file_exists(path + ".tmp"),
		"8: a successful write leaves no .tmp behind")
	check(not FileAccess.file_exists(path + ".bak"),
		"8: the .bak is temporary and must not survive a successful write")

	# The other half of that rule: a .bak is retained only when recovery is required. A crash between
	# save_entries' two renames leaves the board under .bak alone, and load_entries() reads it.
	var orphan := "user://test_leaderboard_bak_%d.cfg" % (randi() % 1000000)
	temp_paths.append(orphan)
	check(int(RunnerLeaderboard.submit(_entry("run-bak", 777), orphan)["error"]) == OK,
		"8: the recovery fixture board was written")
	check(DirAccess.rename_absolute(orphan, orphan + ".bak") == OK,
		"8: the crash fixture leaves only a .bak")
	var from_backup := RunnerLeaderboard.load_entries(orphan)
	check(from_backup.size() == 1 and int(from_backup[0]["score"]) == 777,
		"8: a .bak left by a crash mid-write loads as the last good board")

	# ...and the converse: a stale .bak is never restored over a write that succeeded. save_entries
	# only puts a backup back when this save is what created it, and a live destination means this
	# save moves the board onto the stale file and drops it on success.
	var stale := "user://test_leaderboard_stale_%d.cfg" % (randi() % 1000000)
	temp_paths.append(stale)
	check(int(RunnerLeaderboard.submit(_entry("run-old", 5), stale)["error"]) == OK,
		"8: the stale fixture board was written")
	var stale_file := FileAccess.open(stale + ".bak", FileAccess.WRITE)
	check(stale_file != null, "8: the stale .bak fixture was written")
	if stale_file != null:
		stale_file.store_string("[meta]\nversion=1\n\n[leaderboard]\nentries=[]\n")
		stale_file.close()
	check(int(RunnerLeaderboard.submit(_entry("run-new", 900), stale)["error"]) == OK,
		"8: a write over a stale .bak still succeeds")
	var after_stale := RunnerLeaderboard.load_entries(stale)
	check(after_stale.size() == 2 and int(after_stale[0]["score"]) == 900,
		"8: the successful write wins; a stale .bak is never restored over it")
	check(not FileAccess.file_exists(stale + ".bak"),
		"8: a successful write clears the stale .bak as well")

	# Forward compatibility: a board a newer build wrote is unreadable here, and overwriting it would
	# throw away someone's real board to store one run. It reads empty and every writer refuses.
	var future := "user://test_leaderboard_v99_%d.cfg" % (randi() % 1000000)
	temp_paths.append(future)
	var future_text := "[meta]\nversion=99\n\n[leaderboard]\nentries=[]\n"
	var future_file := FileAccess.open(future, FileAccess.WRITE)
	check(future_file != null, "8: the future-schema fixture was written")
	if future_file != null:
		future_file.store_string(future_text)
		future_file.close()
	var future_board := RunnerLeaderboard.read_board(future)
	check(int(future_board["version"]) == 99,
		"8: read_board reports the on-disk schema version, got %s" % future_board["version"])
	check(RunnerLeaderboard.load_entries(future).is_empty(),
		"8: a newer-schema board reads as empty")
	var refused := RunnerLeaderboard.submit(_entry("run-future", 1000), future)
	check(int(refused["error"]) != OK,
		"8: submit refuses a newer-schema board, got error %s" % refused["error"])
	check(int(refused["rank"]) == 0, "8: a refused submit never reports a rank")
	check(RunnerLeaderboard.rename("run-future", "X", future) != OK,
		"8: rename refuses a newer-schema board too")
	check(FileAccess.get_file_as_string(future) == future_text,
		"8: the newer-schema board is byte-identical after the refusals")
	check(not FileAccess.file_exists(future + ".tmp") and not FileAccess.file_exists(future + ".bak"),
		"8: a refused write leaves no .tmp or .bak")

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

	# A half-written primary — the value cut mid-entry, which is what a crash inside the write leaves
	# and what ConfigFile actually refuses to parse (the fixture above is merely unrecognised).
	var half := "user://test_leaderboard_half_%d.cfg" % (randi() % 1000000)
	temp_paths.append(half)
	check(int(RunnerLeaderboard.submit(_entry("run-backup", 700), half)["error"]) == OK,
		"8: the half-written fixture board was written")
	var good_rows := FileAccess.get_file_as_string(half)
	var half_file := FileAccess.open(half, FileAccess.WRITE)
	check(half_file != null, "8: the truncated primary fixture was written")
	if half_file != null:
		half_file.store_string("[meta]\nversion=2\n\n[leaderboard]\nentries=[{\"run_id\"")
		half_file.close()
	# No .bak yet: there is nothing to fall back to, so the truncated board is simply corrupt.
	var unbacked := RunnerLeaderboard.read_board(half)
	check(int(unbacked["error"]) == ERR_FILE_CORRUPT and (unbacked["entries"] as Array).is_empty()
		and not bool(unbacked["used_backup"]),
		"8: a corrupt board with no .bak reports ERR_FILE_CORRUPT and no rows, got error %s"
			% unbacked["error"])
	# Now the intact backup from before the truncation is put back beside it.
	var half_backup := FileAccess.open(half + ".bak", FileAccess.WRITE)
	check(half_backup != null, "8: the .bak fixture was written")
	if half_backup != null:
		half_backup.store_string(good_rows)
		half_backup.close()
	var repaired := RunnerLeaderboard.read_board(half)
	check(int(repaired["error"]) == OK and bool(repaired["used_backup"]),
		"8: a corrupt primary falls back to the .bak, got error %s" % repaired["error"])
	var repaired_rows: Array = repaired["entries"]
	check(repaired_rows.size() == 1 and String(repaired_rows[0]["run_id"]) == "run-backup",
		"8: the fallback hands back the backup rows, got %s" % [repaired_rows])
	check(int(RunnerLeaderboard.submit(_entry("run-after", 10), half)["error"]) == OK
		and RunnerLeaderboard.load_entries(half).size() == 2,
		"8: the next save repairs the primary from the recovered board")

# --- 8b. A leaderboard write that fails never reports a rank (contract §4.3) ---

## submit() ranks the run against the board it built in memory, so a run whose write failed would
## otherwise be reported as placed. The run itself must still end normally.
func _test_finish_write_failure() -> void:
	# An ordinary file standing where the board's directory would be: every write under it fails,
	# on any platform and without touching file permissions.
	var blocker := "user://test_leaderboard_blocker_%d" % (randi() % 1000000)
	temp_paths.append(blocker)
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	check(file != null, "8b: the blocking file was written")
	if file == null:
		return
	file.store_string("not a directory")
	file.close()
	var blocked := blocker + "/leaderboard.cfg"
	check(RunnerLeaderboard.submit(_entry("probe", 10), blocked)["error"] != OK,
		"8b: the blocked path really cannot be written")
	# The failure is reported before anything is moved, so nothing of a half-finished write is left.
	check(not FileAccess.file_exists(blocked) and not FileAccess.file_exists(blocked + ".tmp")
			and not FileAccess.file_exists(blocked + ".bak"),
		"8b: a write to an unwritable directory leaves no partial destination")

	var writable := "user://test_leaderboard_finish_%d.cfg" % (randi() % 1000000)
	temp_paths.append(writable)
	var saved := _finish_caught_run(writable)
	var ok_result: Dictionary = saved["result"]
	check(int(ok_result.get("leaderboard_error", -1)) == OK,
		"8b: a saved run reports leaderboard_error OK, got %s" % ok_result.get("leaderboard_error", "<missing>"))
	check(int(ok_result["rank"]) == 1 and bool(ok_result["qualifies"]), "8b: a saved run keeps its rank")
	check(int(saved["saved"]) == 1, "8b: leaderboard_saved fires once for a saved run")
	check(int(saved["finished"]) == 1, "8b: run_finished fires once for a saved run")

	var lost := _finish_caught_run(blocked)
	var result: Dictionary = lost["result"]
	check(int(result.get("leaderboard_error", OK)) != OK,
		"8b: a failed write reports leaderboard_error %s" % result.get("leaderboard_error", "<missing>"))
	check(int(result["rank"]) == 0, "8b: a failed write keeps rank 0, got %d" % int(result["rank"]))
	check(not bool(result["qualifies"]), "8b: a failed write never qualifies")
	check(int(lost["saved"]) == 0, "8b: leaderboard_saved fired %d times for a failed write"
		% int(lost["saved"]))
	check(int(lost["finished"]) == 1, "8b: run_finished fired %d times for a failed write"
		% int(lost["finished"]))
	check(RunnerLeaderboard.load_entries(blocked).is_empty(), "8b: nothing reached the blocked board")
	var game: Node3D = lost["game"]
	check(game.state == &"finished", "8b: the run still ends finished, got %s" % game.state)
	check(not game.submit_name("Test"), "8b: submit_name fails when the board cannot be written")
	check(int(lost["saved"]) == 0, "8b: a failed submit_name never emits leaderboard_saved")
	# The blocker is a file; DirAccess.remove_absolute in _report() clears it either way.
	check(not FileAccess.file_exists(blocked), "8b: the failed write left no board behind")

# --- 8c. RunnerLeaderboard.clear() ---

func _test_clear() -> void:
	# Clear success: seeded entries gone, version 2, used_backup false, no companions.
	var path := "user://test_leaderboard_clear_%d.cfg" % (randi() % 1000000)
	temp_paths.append(path)
	for i in 3:
		check(int(RunnerLeaderboard.submit(_entry("run-%d" % i, 100 + i * 10), path)["error"]) == OK,
			"8c: clear-success fixture submit %d" % i)
	check(int(RunnerLeaderboard.clear(path)) == OK, "8c: clear() returns OK")
	var board := RunnerLeaderboard.read_board(path)
	check(int(board["error"]) == OK, "8c: cleared board reads OK")
	check((board["entries"] as Array).is_empty(), "8c: cleared board has zero entries")
	check(int(board["version"]) == RunnerLeaderboard.SCHEMA_VERSION, "8c: cleared board is schema version 2")
	check(not bool(board["used_backup"]), "8c: cleared board did not use a backup")
	check(not FileAccess.file_exists(path + ".bak"), "8c: clear removes the .bak companion")
	check(not FileAccess.file_exists(path + ".tmp"), "8c: clear removes the .tmp companion")

	# Backup-only clear: primary moved to .bak before clear.
	var bak_path := "user://test_leaderboard_clear_bak_%d.cfg" % (randi() % 1000000)
	temp_paths.append(bak_path)
	check(int(RunnerLeaderboard.submit(_entry("run-bak", 500), bak_path)["error"]) == OK,
		"8c: backup-only fixture submit")
	check(DirAccess.rename_absolute(bak_path, bak_path + ".bak") == OK,
		"8c: primary moved to .bak for backup-only fixture")
	check(int(RunnerLeaderboard.clear(bak_path)) == OK, "8c: backup-only clear() returns OK")
	check(not FileAccess.file_exists(bak_path + ".bak"), "8c: backup-only clear removes the .bak")
	var bak_board := RunnerLeaderboard.read_board(bak_path)
	check(FileAccess.file_exists(bak_path), "8c: backup-only clear writes the primary")
	check(int(bak_board["error"]) == OK, "8c: backup-only primary reads OK")
	check((bak_board["entries"] as Array).is_empty(), "8c: backup-only primary has no entries")
	check(int(bak_board["version"]) == RunnerLeaderboard.SCHEMA_VERSION, "8c: backup-only primary is schema version 2")
	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(bak_path)
	check(RunnerLeaderboard.load_entries(bak_path).is_empty(),
		"8c: no old entries survive after backup-only clear")

	# Newer-schema guard: clear() refuses a v99 board and leaves bytes unchanged.
	var future_path := "user://test_leaderboard_clear_v99_%d.cfg" % (randi() % 1000000)
	temp_paths.append(future_path)
	var future_text := "[meta]\nversion=99\n\n[leaderboard]\nentries=[]\n"
	var future_file := FileAccess.open(future_path, FileAccess.WRITE)
	check(future_file != null, "8c: future-schema fixture written")
	if future_file != null:
		future_file.store_string(future_text)
		future_file.close()
	var guard_result := RunnerLeaderboard.clear(future_path)
	check(int(guard_result) != OK, "8c: clear() refuses a newer-schema board, got error %d" % int(guard_result))
	check(FileAccess.get_file_as_string(future_path) == future_text,
		"8c: newer-schema board is byte-identical after refused clear")

	# Early write failure: blocker file stands where the board directory would be.
	var blocker2 := "user://test_leaderboard_clear_blocker_%d" % (randi() % 1000000)
	temp_paths.append(blocker2)
	var blocker2_file := FileAccess.open(blocker2, FileAccess.WRITE)
	check(blocker2_file != null, "8c: write-failure blocker written")
	if blocker2_file != null:
		blocker2_file.store_string("not a directory")
		blocker2_file.close()
	var blocked2 := blocker2 + "/leaderboard.cfg"
	var fail_result := RunnerLeaderboard.clear(blocked2)
	check(int(fail_result) != OK, "8c: clear() on unwritable path returns non-OK, got %d" % int(fail_result))
	check(not FileAccess.file_exists(blocked2 + ".bak") and not FileAccess.file_exists(blocked2 + ".tmp"),
		"8c: failed clear leaves no companion files")

	# New submission after reset: rank 1, exactly one entry.
	var after_path := "user://test_leaderboard_clear_after_%d.cfg" % (randi() % 1000000)
	temp_paths.append(after_path)
	for i in 5:
		check(int(RunnerLeaderboard.submit(_entry("old-%d" % i, 200 + i), after_path)["error"]) == OK,
			"8c: after-reset fixture submit %d" % i)
	check(int(RunnerLeaderboard.clear(after_path)) == OK, "8c: after-reset clear() returns OK")
	var new_result := RunnerLeaderboard.submit(_entry("new-run", 42), after_path)
	check(int(new_result["error"]) == OK, "8c: submission after reset succeeds")
	check(int(new_result["rank"]) == 1, "8c: first post-reset submission ranks 1")
	check(RunnerLeaderboard.load_entries(after_path).size() == 1, "8c: exactly one entry after reset")

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
		and is_equal_approx(float(c.caught_sequence_seconds), 3.0), "9: hit tuning matches contract §7")
	# Contract §11.2 lowered the ramp from 165 s to 100 s and raised the Nitro cap to 38 m/s, so the
	# v2 curve reaches the top inside a first stage and Nitro still bites at the stage bonus cap.
	check(is_equal_approx(float(c.base_speed), 12.0) and is_equal_approx(float(c.max_speed), 24.0)
		and is_equal_approx(float(c.time_to_max_speed), 100.0), "9: speed tuning matches contract §11.2")
	check(float(c.hard_cap_speed) >= float(c.max_speed)
		and float(c.nitro_speed_cap) >= float(c.hard_cap_speed) * float(c.nitro_speed_multiplier) - 0.5,
		"9: the speed caps are ordered")
	check(is_equal_approx(float(c.nitro_speed_cap), 38.0), "9: the Nitro cap matches contract §11.2")
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
	# The corridor stays straight: RunConfig no longer carries a bend, and the drain / camera rest
	# are what a stage seam is measured against.
	var bend_exports: Array[String] = []
	for prop in c.get_script().get_script_property_list():
		var prop_name := String(prop["name"])
		if prop_name.begins_with("turn_"):
			bend_exports.append(prop_name)
	check(bend_exports.is_empty(), "9: RunConfig still exports %s" % [bend_exports])
	check(is_equal_approx(float(c.stage_drain_distance), 120.0)
		and is_equal_approx(float(c.stage_drain_timeout), 6.0)
		and is_equal_approx(float(c.stage_clear_line_z), 8.0),
		"9: the drain is %.0f m / %.0f s with the clear line at z %.0f, expected 120 / 6 / 8"
			% [float(c.stage_drain_distance), float(c.stage_drain_timeout), float(c.stage_clear_line_z)])
	check(c.camera_position.is_equal_approx(Vector3(0, 4, 8))
		and c.camera_look_at.is_equal_approx(Vector3(0, 1, -8))
		and is_equal_approx(float(c.camera_fov), 60.0),
		"9: the camera rests at %s looking at %s with fov %.0f, expected (0, 4, 8) / (0, 1, -8) / 60"
			% [c.camera_position, c.camera_look_at, float(c.camera_fov)])
	# Contract 2.6 §11.14: a 5 s first-meeting intro, 2.5 s repeats, a 3.6 / 2.0 s defeat, and the
	# 1 s outro left to the retreat alone.
	check(is_equal_approx(float(c.boss_intro_seconds), 5.0)
		and is_equal_approx(float(c.boss_intro_short_seconds), 2.5),
		"9: the boss intro runs %.2f s full / %.2f s short, expected 5.0 / 2.5"
			% [float(c.boss_intro_seconds), float(c.boss_intro_short_seconds)])
	check(is_equal_approx(float(c.boss_defeat_seconds), 3.6)
		and is_equal_approx(float(c.boss_defeat_short_seconds), 2.0)
		and is_equal_approx(float(c.boss_outro_seconds), 1.0),
		"9: the defeat runs %.2f / %.2f s and the retreat outro %.2f s, expected 3.6 / 2.0 / 1.0"
			% [float(c.boss_defeat_seconds), float(c.boss_defeat_short_seconds), float(c.boss_outro_seconds)])
	check(is_equal_approx(float(c.boss_cinematic_skip_after), 0.5)
		and is_equal_approx(float(c.boss_cinematic_skip_tail), 0.3)
		and is_equal_approx(float(c.boss_cinematic_speed_scale), 0.25),
		"9: the skip opens at %.2f s with a %.2f s tail and the corridor slows to %.2fx, expected 0.5 / 0.3 / 0.25"
			% [float(c.boss_cinematic_skip_after), float(c.boss_cinematic_skip_tail),
				float(c.boss_cinematic_speed_scale)])
	check(is_equal_approx(float(c.boss_hitstop_seconds), 0.12)
		and is_equal_approx(float(c.boss_slowmo_seconds), 0.8)
		and is_equal_approx(float(c.boss_slowmo_factor), 0.4),
		"9: the defeat hit-stop is %.2f s and the slow-mo %.2f s from %.2f, expected 0.12 / 0.8 / 0.4"
			% [float(c.boss_hitstop_seconds), float(c.boss_slowmo_seconds), float(c.boss_slowmo_factor)])
	# Contract §11.1/§11.10 v2.3: the stage banner covers the lanes, so the corridor stays clear
	# across it and still owes the player a reaction once it lifts.
	check(is_equal_approx(float(c.stage_banner_clear_seconds), 3.5)
		and is_equal_approx(float(c.stage_banner_reaction_seconds), 1.0),
		"9: the stage-entrance window is %.2f s with %.2f s of reaction, expected 3.5 / 1.0"
			% [float(c.stage_banner_clear_seconds), float(c.stage_banner_reaction_seconds)])
	check(float(c.stage_banner_clear_seconds) > float(c.stage_banner_reaction_seconds),
		"9: the banner has to fit inside stage_banner_clear_seconds minus the reaction time, got %.2f / %.2f"
			% [float(c.stage_banner_clear_seconds), float(c.stage_banner_reaction_seconds)])

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

# --- 10b. Autopilot in a boss fight: closing speeds and telegraph planning (systems spec §10.6) ---

## The half runner_boss_validator.gd drives offline, pinned here as a unit: a slice carries the
## speed it closes at, a shot never shares a manoeuvre with a chunk hazard, and a telegraph turns
## into an action and a moment to take it without a single node in the tree.
func _test_autopilot_boss() -> void:
	var game := _make_game()
	game.speed = 24.0
	var bot: Node = autopilot_script.new()
	junk.append(bot)
	bot.setup(game)

	# A chunk hazard closes at the corridor speed; a shot closes at its own.
	var wall := _hazard(&"pr_backlog_low")
	wall.position = Vector3(0.0, 0.0, -20.0)
	var wall_slices: Array = bot.slices_for([wall], 24.0, 0.0)
	check(is_equal_approx(float(wall_slices[0]["closing_v"]), 24.0)
		and not bool(wall_slices[0]["projectile"]),
		"10b: a chunk hazard closes at the corridor speed, got %.1f" % float(wall_slices[0]["closing_v"]))
	var shot := _projectile(Vector3(0.0, 0.0, -20.0), 34.0)
	var shot_slices: Array = bot.slices_for([shot], 24.0, 0.0)
	check(shot_slices.size() == 1 and bool(shot_slices[0]["projectile"]),
		"10b: a projectile is read as one, got %s" % [shot_slices])
	check(is_equal_approx(float(shot_slices[0]["closing_v"]), 34.0),
		"10b: a shot closes at its own speed, got %.1f" % float(shot_slices[0]["closing_v"]))
	check(int(shot_slices[0]["blocked"]) == 0b010, "10b: a centre orb blocks the middle lane only")

	# Systems spec §10.6: a shot and a chunk hazard at the same z stay two slices, because one
	# trigger distance cannot answer two different closing speeds.
	var mixed: Array = bot.slices_for([wall, shot], 24.0, 0.0)
	check(mixed.size() == 2, "10b: a projectile never merges with a chunk hazard, got %d slice(s)"
		% mixed.size())
	var second := _projectile(Vector3(2.0, 0.0, -20.3), 30.0)
	var both: Array = bot.slices_for([shot, second], 24.0, 0.0)
	check(both.size() == 1 and int(both[0]["blocked"]) == 0b110,
		"10b: two shots in the same slot are one manoeuvre, got %s" % [both])
	check(is_equal_approx(float(both[0]["closing_v"]), 34.0),
		"10b: a merged slice takes the fastest member, got %.1f" % float(both[0]["closing_v"]))
	check(is_equal_approx(bot.plan_trigger_z(34.0), -(34.0 * 0.6 + 0.4)),
		"10b: the trigger distance follows the closing speed")

	# A telegraph, straight off the contract §11.6 table and with no node anywhere.
	var low: Dictionary = bot.attack_slice(0b111, &"low", 26.0)
	check(int(low["blocked"]) == 0b111 and bool(low["jumpable"]) and not bool(low["rollable"]),
		"10b: a low wall of shots is jumped, got %s" % [low])
	var high: Dictionary = bot.attack_slice(0b111, &"high", 26.0)
	check(bool(high["rollable"]) and not bool(high["jumpable"]),
		"10b: a high wall of shots is rolled under, got %s" % [high])
	var wide: Dictionary = bot.attack_slice(0b011, &"wide", 26.0)
	check(not bool(wide["jumpable"]) and not bool(wide["rollable"]),
		"10b: a wide shot has to be side-stepped, got %s" % [wide])
	var side: Dictionary = bot.plan_for(wide, 0)
	check(StringName(side["action"]) == bot.ACTION_LANE and int(side["lane"]) == 2
		and int(side["steps"]) == 2, "10b: lane 0 answers a left-pair wide with two steps, got %s" % [side])
	check(StringName(bot.plan_for(low, 1)["action"]) == bot.ACTION_JUMP, "10b: a full-width low is jumped")
	check(StringName(bot.plan_for(high, 1)["action"]) == bot.ACTION_ROLL, "10b: a full-width high is rolled")

	# Arrival = telegraph + the travel from the boss to the hurtbox; the shot is 1.2 m deep and the
	# capsule 0.4 m, so 14 m of boss_z is 13 m of travel.
	var travel: float = bot.projectile_travel_seconds(26.0, &"orb")
	check(is_equal_approx(travel, 13.0 / 26.0), "10b: an orb at 26 m/s travels for %.4f s" % travel)
	check(is_equal_approx(bot.telegraph_arrival(0.9, 26.0, &"orb"), 0.9 + 13.0 / 26.0),
		"10b: the arrival is the telegraph plus the travel, got %.4f"
			% bot.telegraph_arrival(0.9, 26.0, &"orb"))
	check(is_equal_approx(bot.jump_peak_time(), 0.35),
		"10b: the jump apex is at %.4f s, expected 0.35 (half the 0.70 s airtime)" % bot.jump_peak_time())
	check(is_equal_approx(bot.manoeuvre_cost(bot.ACTION_JUMP, 0), 0.35)
		and is_equal_approx(bot.manoeuvre_cost(bot.ACTION_ROLL, 0), 0.35),
		"10b: both body manoeuvres cost half their window")
	check(is_equal_approx(bot.manoeuvre_cost(bot.ACTION_LANE, 2), 0.26),
		"10b: a two-step lane plan costs two tweens, got %.4f" % bot.manoeuvre_cost(bot.ACTION_LANE, 2))
	var arrival := 0.9 + 13.0 / 26.0
	check(is_equal_approx(bot.telegraph_act_at(arrival, bot.ACTION_JUMP, 0),
		arrival - 0.35 - float(game.config.autopilot_telegraph_lead)),
		"10b: the jump is taken a manoeuvre and a lead before impact, got %.4f"
			% bot.telegraph_act_at(arrival, bot.ACTION_JUMP, 0))

	# The telegraph signal itself: the bot picks it up off the facade and keeps it until it lands.
	game.boss_attack_telegraph.emit(0b001, &"orb", 0.9)
	var pending: Array = bot.pending_attacks()
	check(pending.size() == 1 and int(pending[0]["mask"]) == 0b001,
		"10b: the bot heard the telegraph, got %s" % [pending])
	check(is_equal_approx(float(pending[0]["closing_v"]), 26.0),
		"10b: the shot speed comes from this stage's boss def, got %.2f" % float(pending[0]["closing_v"]))
	check(is_equal_approx(float(pending[0]["arrival"]), arrival),
		"10b: the queued arrival is %.4f" % float(pending[0]["arrival"]))
	bot._age_attacks(arrival + 1.0)
	check(bot.pending_attacks().is_empty(), "10b: a landed shot is forgotten, got %s" % [bot.pending_attacks()])

	# Lanes a pending attack rules out: a partial mask does, a full-width one never does — it is
	# answered with the body, so it says nothing about which lane a tool may sit in.
	check(bot.pending_lane_mask([{"mask": 0b011}, {"mask": 0b111}]) == 0b011,
		"10b: only a partial attack blocks tool lanes, got %d"
			% bot.pending_lane_mask([{"mask": 0b011}, {"mask": 0b111}]))
	check(bot.pending_lane_mask([{"lane_mask": 0b100}]) == 0b100,
		"10b: the facade's own pending_attacks rows are read too")

	# Tool greed scales the lane reach: 0 ignores tools, 1 crosses the corridor.
	check(bot.tool_reach() == 2, "10b: greed 1 reaches both lanes, got %d" % bot.tool_reach())
	game.config.autopilot_tool_greed = 0.0
	check(bot.tool_reach() == 0, "10b: greed 0 ignores tools, got %d" % bot.tool_reach())
	var far_tool := _pickup(Vector3(2.0, 1.0, -20.0))
	var targets: Array = bot.pickup_targets([far_tool], 24.0)
	check(targets.size() == 1 and int(targets[0]["lane"]) == 2, "10b: the tool is read in lane 2")
	check(StringName(bot.plan_tool(targets, [], 0, 0, 24.0)["action"]) == bot.ACTION_NONE,
		"10b: greed 0 leaves every tool alone")
	game.config.autopilot_tool_greed = 0.4
	check(bot.tool_reach() == 1, "10b: greed 0.4 reaches one lane, got %d" % bot.tool_reach())
	check(StringName(bot.plan_tool(targets, [], 0, 0, 24.0)["action"]) == bot.ACTION_NONE,
		"10b: a two-lane detour is past a one-lane reach")
	check(StringName(bot.plan_tool(targets, [], 0, 1, 24.0)["action"]) == bot.ACTION_LANE,
		"10b: the same tool is taken from the lane next door")
	game.config.autopilot_tool_greed = 1.0
	check(StringName(bot.plan_tool(targets, [], 0, 0, 24.0)["action"]) == bot.ACTION_LANE,
		"10b: greed 1 crosses the corridor for a tool")
	check(StringName(bot.plan_tool(targets, [], 0b100, 0, 24.0)["action"]) == bot.ACTION_NONE,
		"10b: a tool a pending attack will shoot at is left where it is")

# --- 11. The real hazard: a finished timed laser shuts down (systems spec §5.3, contract §8) ---

## The only hazard with a per-tick state machine is the timed laser, and it is the only one that can
## outlive its own removal: once Auto-Fix clears it, or once it has taken its one hit, it must stop
## advancing. A laser that keeps cycling re-arms `monitoring` on its next `on` slot, keeps driving
## set_laser_state()/set_telegraph() on a visual that was told it is gone, and re-shows the graybox
## that clear() just hid.
##
## Contract §9: this has to prove the same thing with or without the frontend checked out, and
## `_mount_visual()` picks its mount from the environment — hazards/visuals/<kind>_visual.tscn when
## that scene exists, the code-built graybox when it does not. So neither half is asserted on
## whatever happened to be mounted: `_mount_recording_hazard_visual()` installs a recorder extending
## hazard_visual_base.gd for the contract §5.2 hook half, and `_force_graybox()` installs the
## contract §3 graybox for the visibility half. Both halves, and the same checks, run either way.
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

	# Auto-Fix cleared it, with a recorder standing in for whatever the environment would mount.
	var cleared_pair := _timed_laser()
	var cleared: Area3D = cleared_pair["hazard"]
	var hooks: Node3D = _mount_recording_hazard_visual(cleared)
	check(hooks != null, "11: the recording hazard visual failed to mount")
	if hooks == null:
		return
	_run_laser(cleared_pair, 0.1)
	check(cleared.monitoring, "11: the laser was armed before clear()")
	check(hooks.laser_states == [&"ground"],
		"11: a running laser drives set_laser_state, got %s" % [hooks.laser_states])
	check(not hooks.telegraphs.is_empty(), "11: a running laser drives set_telegraph")
	cleared.clear()
	var state_at_clear: StringName = cleared.laser_state
	var telegraphs_at_clear: int = hooks.telegraphs.size()
	check(not cleared.is_blocking(), "11: clear() stops the hazard blocking")
	check(not cleared.is_physics_processing(), "11: clear() stops the timed cycle")
	check(not cleared.is_in_group(&"runner_hazards"), "11: a cleared hazard leaves the group")
	check(hooks.cleared_calls == 1,
		"11: clear() calls on_cleared() exactly once, got %d" % hooks.cleared_calls)
	# A full 3 s period: without the shutdown this walks ground -> off -> high -> off -> ground.
	_check_laser_inert(cleared_pair, 3.0, state_at_clear, "a cleared laser")
	check(hooks.laser_states == [&"ground"],
		"11: a cleared laser never calls set_laser_state again, got %s" % [hooks.laser_states])
	check(hooks.telegraphs.size() == telegraphs_at_clear,
		"11: a cleared laser never calls set_telegraph again")
	cleared.clear()
	check(hooks.cleared_calls == 1, "11: a second clear() never calls on_cleared() again")

	# The same shutdown on the contract §3 graybox mount, forced so the graybox rules are asserted
	# in a checkout that has the frontend visual scenes as well as in one that does not.
	var boxed_pair := _timed_laser()
	var boxed: Area3D = boxed_pair["hazard"]
	var graybox := _force_graybox(boxed)
	check(graybox != null, "11: the graybox failed to mount")
	if graybox == null:
		return
	_run_laser(boxed_pair, 0.1)
	check(graybox.visible, "11: an on-phase laser shows its graybox")
	_run_laser(boxed_pair, 1.2)
	check(boxed.laser_state == OFF_STATE and not graybox.visible,
		"11: the off phase hides the graybox")
	_run_laser(boxed_pair, 0.6)
	check(boxed.laser_state == &"high" and graybox.visible,
		"11: the high phase shows the graybox again")
	boxed.clear()
	var boxed_state_at_clear: StringName = boxed.laser_state
	check(not graybox.visible, "11: clear() hides the graybox")
	_check_laser_inert(boxed_pair, 3.0, boxed_state_at_clear, "a cleared graybox laser", graybox)
	check(not graybox.visible, "11: a cleared laser never re-shows its graybox")

	# It took its one hit.
	var hit_pair := _timed_laser()
	var hit: Area3D = hit_pair["hazard"]
	var hits: Node = hit_pair["hits"]
	var hit_hooks: Node3D = _mount_recording_hazard_visual(hit)
	check(hit_hooks != null, "11: the recording hazard visual failed to mount on the hit laser")
	if hit_hooks == null:
		return
	_run_laser(hit_pair, 0.1)
	check(hit.monitoring, "11: the laser was armed before hit_player()")
	hit.hit_player(null)
	var state_at_hit: StringName = hit.laser_state
	check(hit.consumed and not hit.is_blocking(), "11: the hit consumes the hazard")
	check(hits.hits_taken == 1, "11: the hit reached the hit manager")
	check(not hit.is_physics_processing(), "11: hit_player() stops the timed cycle")
	check(hit_hooks.hit_calls == 1,
		"11: hit_player() calls on_hit_player() exactly once, got %d" % hit_hooks.hit_calls)
	check(hit_hooks.cleared_calls == 0, "11: a hit is not an Auto-Fix clear")
	_check_laser_inert(hit_pair, 3.0, state_at_hit, "a consumed laser")
	check(hits.hits_taken == 1, "11: the consumed laser never reported a second hit")
	check(hit_hooks.laser_states == [&"ground"],
		"11: a consumed laser never calls set_laser_state again, got %s" % [hit_hooks.laser_states])
	hit.hit_player(null)
	check(hit_hooks.hit_calls == 1 and hits.hits_taken == 1,
		"11: a second hit_player() on a consumed laser is a no-op")

# --- 12. Super Jump invulnerability survives a re-launch (systems spec §4, contract §12) ---

## Super Jump is invulnerable in flight and for super_jump_landing_invuln seconds after landing. A
## second Super Jump launched while that landing countdown is still running has to go back to the
## in-flight half: if the countdown is left alone, the i-frames expire under the new arc and the
## hazard the player jumped over lands a hit.
func _test_super_jump_invuln() -> void:
	var game := _make_game()
	var hits: Node = _systems(game)["hits"]
	var player := _real_player(game)
	var landing := float(game.config.super_jump_landing_invuln)

	player._grant_super_jump_invuln()
	check(hits.is_invulnerable(), "12: a Super Jump grants invulnerability")
	check(hits.invuln_sources.size() == 1, "12: the Super Jump registers one source")
	_tick_invuln(player, 0.4)
	check(is_zero_approx(player._super_jump_invuln_remaining), "12: nothing counts down in flight")
	check(hits.is_invulnerable(), "12: the whole flight is invulnerable")

	player._on_land()
	check(is_equal_approx(player._super_jump_invuln_remaining, landing),
		"12: landing starts the %.2f s window" % landing)
	_tick_invuln(player, landing * 0.6)
	check(hits.is_invulnerable(), "12: the landing window is still invulnerable at 60%")

	# The second launch: the landing countdown has to be dropped, and the source added only once.
	player._grant_super_jump_invuln()
	check(is_zero_approx(player._super_jump_invuln_remaining),
		"12: a new Super Jump clears the landing countdown, %.3f s left"
		% player._super_jump_invuln_remaining)
	check(hits.invuln_sources.size() == 1, "12: the second Super Jump does not add a second source")
	_tick_invuln(player, landing)
	check(hits.is_invulnerable(), "12: the second flight never expires mid-air")

	player._on_land()
	_tick_invuln(player, landing + 0.1)
	check(not player._super_jump_invuln, "12: the last landing window still runs out")
	check(not hits.is_invulnerable(), "12: the expired window gives its invulnerability back")
	check(hits.invuln_sources.is_empty(), "12: the Super Jump source is removed exactly once")

	# A player driven with no config at all — a bare rig, or the scene opened on its own — still has
	# to buffer a jump for the RunConfig default. A zero window would be consumed by the first
	# maxf() in _update_jump() before the grounded test could ever fire it.
	var bare := CharacterBody3D.new()
	bare.set_script(real_player_script)
	bare.config = null
	junk.append(bare)
	bare.request_jump()
	check(is_equal_approx(bare.jump_buffer_remaining, float(base_config.jump_buffer))
		and is_equal_approx(bare.jump_buffer_remaining, 0.10),
		"12: a config-less player buffers a jump for %.3f s, expected the RunConfig default 0.10"
			% bare.jump_buffer_remaining)

# --- 13. Dodges are counted per crossing (contract §4.2 result.hazards_dodged) ---

## A blocking hazard that passes the player counts once, and its instance id stops the next ticks
## counting it again. The id is forgotten again while the hazard sits at or ahead of the dodge line,
## so a hazard that is repositioned or reused in front of the player is counted once per crossing
## instead of being remembered as dodged for the rest of the run.
func _test_dodge_tracking() -> void:
	var game := _tree_game()
	var hazard := _hazard(&"pr_backlog_low")
	hazard.add_to_group(&"runner_hazards")
	# DODGE_LINE_Z is 1.0: +2 is behind the player, -6 is back out in front of it.
	var behind := Vector3(0.0, 0.0, 2.0)
	var ahead := Vector3(0.0, 0.0, -6.0)

	hazard.position = ahead
	game._track_dodges()
	check(int(game.hazards_dodged) == 0, "13: a hazard in front of the player is not a dodge")

	hazard.position = behind
	game._track_dodges()
	check(int(game.hazards_dodged) == 1, "13: a hazard past the dodge line counts once")
	game._track_dodges()
	check(int(game.hazards_dodged) == 1, "13: the same hazard is not counted twice while behind")

	hazard.position = ahead
	game._track_dodges()
	check(int(game.hazards_dodged) == 1, "13: moving it back in front counts nothing by itself")

	hazard.position = behind
	game._track_dodges()
	check(int(game.hazards_dodged) == 2, "13: the second crossing counts once more")
	game._track_dodges()
	check(int(game.hazards_dodged) == 2, "13: a third crossing is not invented by an extra tick")

# --- 14. The terminal difficulty 1.0 is always announced, exactly once (contract §4.1) ---

## difficulty_changed is suppressed while the value moves less than DIFFICULTY_EPSILON, which would
## otherwise swallow the last step onto exactly 1.0: the frontend keys its top-difficulty state off
## that emission, so it has to arrive, and it must not repeat once the curve is pinned at 1.0.
##
## v2 (contract §11.1, systems spec §10.2): the curve is read at `run_clock`, the RUN-phase clock the
## StageManager owns, not at `elapsed`. `elapsed` still counts every unpaused second — it is what the
## result duration and the timed laser ride on — so driving it here would leave the controller at
## run_clock 0 and never emit anything at all.
func _test_difficulty_emission() -> void:
	var game := _make_game()
	var speed: Node = _systems(game)["speed"]
	var ramp := float(game.config.time_to_max_speed)
	var epsilon: float = speed.DIFFICULTY_EPSILON
	var emitted: Array[float] = []
	game.difficulty_changed.connect(func(value: float) -> void:
		emitted.append(value))

	# Just under the top: inside the epsilon of 1.0, but not yet 1.0.
	_set_run_clock(game, ramp * (1.0 - epsilon * 0.5))
	speed._physics_process(TICK)
	check(emitted.size() == 1, "14: the ramp announces difficulty on the way up, got %d" % emitted.size())
	if emitted.is_empty():
		return
	var last := emitted[emitted.size() - 1]
	check(last < 1.0 and 1.0 - last < epsilon,
		"14: the last pre-max emission is %.4f, expected inside the epsilon below 1.0" % last)

	# Intermediate moves smaller than the epsilon stay suppressed.
	_set_run_clock(game, float(game.run_clock) + ramp * epsilon * 0.1)
	speed._physics_process(TICK)
	check(emitted.size() == 1, "14: a sub-epsilon step is still suppressed, got %d" % emitted.size())

	# Past time_to_max_speed the curve clamps to exactly 1.0, which always goes out.
	_set_run_clock(game, ramp + 5.0)
	speed._physics_process(TICK)
	check(emitted.size() == 2, "14: the terminal 1.0 is emitted, got %d emissions" % emitted.size())
	check(is_equal_approx(emitted[emitted.size() - 1], 1.0),
		"14: the final emission is %.4f, expected 1.0" % emitted[emitted.size() - 1])

	# Every later tick is still pinned at 1.0 and has to stay quiet.
	for i in 10:
		_set_run_clock(game, float(game.run_clock) + 1.0)
		speed._physics_process(TICK)
	check(emitted.size() == 2, "14: difficulty 1.0 is never re-emitted, got %d emissions" % emitted.size())
	check(is_equal_approx(float(speed.difficulty), 1.0), "14: the curve stays at 1.0")

	# The other half of the v2 rule: `elapsed` alone moves nothing. A run parked in the boss phase
	# keeps counting seconds, and the speed and the difficulty have to hold where run_clock left them.
	var held := _make_game()
	var held_speed: Node = _systems(held)["speed"]
	var held_emissions: Array[float] = []
	held.difficulty_changed.connect(func(value: float) -> void:
		held_emissions.append(value))
	_set_run_clock(held, ramp * 0.5)
	held_speed._physics_process(TICK)
	var frozen_speed := float(held_speed.speed)
	var frozen_difficulty := float(held_speed.difficulty)
	var frozen_emissions := held_emissions.size()
	for i in _ticks(30.0):
		held.elapsed += TICK
		held_speed._physics_process(TICK)
	check(is_equal_approx(float(held_speed.speed), frozen_speed),
		"14: a frozen run_clock holds the speed at %.3f, got %.3f" % [frozen_speed, held_speed.speed])
	check(is_equal_approx(float(held_speed.difficulty), frozen_difficulty),
		"14: a frozen run_clock holds the difficulty at %.3f" % frozen_difficulty)
	check(held_emissions.size() == frozen_emissions,
		"14: a frozen run_clock announces nothing, got %d extra emissions"
			% (held_emissions.size() - frozen_emissions))

## Move the RUN-phase clock the SpeedController reads, keeping `elapsed` in step with it: outside a
## turn, a boss or a stage-clear card the two advance together (contract §11.1).
func _set_run_clock(game: Node3D, seconds: float) -> void:
	var step := seconds - float(game.run_clock)
	game.run_clock = seconds
	game.elapsed += maxf(step, 0.0)

# --- 15. A hazard is configured before it mounts its visual (contract §5.2) ---

## `_apply_visual_vars()` feeds the visual `lanes_mask`, which is computed from `config.lane_width`
## and `config.hurtbox_radius`, and `chunk.setup()` negates the child x on a mirrored chunk. Both
## only arrive in `setup()`, which the spawner calls after the chunk is already in the tree, so a
## visual mounted straight from `_ready()` would be configured from the contract §7 fallbacks and an
## un-mirrored lane. The mount waits for `setup()` and stays idempotent: never two visuals.
func _test_hazard_visual_mount_order() -> void:
	var game := _make_game()
	# A lane width the hazard.gd DEFAULT_LANE_WIDTH fallback (2.0) cannot produce.
	game.config.lane_width = 5.0
	var hazard := Area3D.new()
	hazard.set_script(real_hazard_script)
	hazard.kind = &"bug_swarm"
	root.add_child(hazard)
	junk.append(hazard)
	check(hazard.config == null, "15: a hazard in the tree has no config until setup()")
	check(not is_instance_valid(hazard.visual),
		"15: _ready() mounts no visual while the config is still missing")

	hazard.setup(game)
	check(hazard.config != null, "15: setup() assigns the config")
	check(is_instance_valid(hazard.visual), "15: setup() mounts the visual")
	check(hazard.get_child_count() == 2,
		"15: the hazard holds one collision shape and one visual, got %d children"
			% hazard.get_child_count())
	# What `_apply_visual_vars()` reads: the lane geometry has to come from the RunConfig, not from
	# the fallbacks, at the moment the visual is mounted.
	check(is_equal_approx(hazard.lane_x(2), 5.0),
		"15: lane 2 sits at the config lane width, got %.2f" % hazard.lane_x(2))
	check(hazard.lanes_mask() == 0b010,
		"15: a 1.6 m hazard at x 0 occupies only the middle 5 m lane, got %d" % hazard.lanes_mask())

	# The _ready() fallback, for a hazard that never gets a setup(): the deferred call is
	# `_mount_visual()` itself, so calling it is the same path the engine would take.
	var orphan := Area3D.new()
	orphan.set_script(real_hazard_script)
	orphan.kind = &"merge_conflict"
	root.add_child(orphan)
	junk.append(orphan)
	orphan._mount_visual()
	check(is_instance_valid(orphan.visual),
		"15: a hazard that is never set up still falls back to the graybox")
	var mounted: Node = orphan.visual
	orphan.setup(game)
	orphan._mount_visual()
	check(orphan.visual == mounted and orphan.get_child_count() == 2,
		"15: the visual is mounted exactly once, %d children" % orphan.get_child_count())

# --- 16. reset() clears the mounted visual's power-up state (contract §5.1) ---

## The visual outlives a run: it is mounted once in setup() and never re-created by start_run(). An
## aura or the shield glow left on by the previous run would therefore still be showing on the first
## frame of the next one, so reset() has to switch every one of them off.
func _test_player_reset_clears_visual_state() -> void:
	var game := _make_game()
	_systems(game)
	var player := _real_player(game)
	var visual := _recording_visual()
	check(visual != null, "16: the recording visual failed to compile")
	if visual == null:
		return
	player.visual = visual

	player.apply_aura(&"nitro", true)
	player.apply_shield(true)
	check(visual.auras.size() == 1 and visual.shields.size() == 1,
		"16: the harness visual received the aura and the shield")
	visual.auras.clear()
	visual.shields.clear()

	player.reset()
	var cleared := {}
	for call in visual.auras:
		check(not bool(call[1]), "16: reset() only ever switches an aura off, got %s on" % call[0])
		cleared[call[0]] = true
	for kind in player.AURA_KINDS:
		check(cleared.has(kind), "16: reset() left the %s aura alone" % kind)
	check(visual.shields.size() == 1 and not bool(visual.shields[0]),
		"16: reset() clears the shield glow exactly once, got %s" % [visual.shields])

	# The same reset() on a player with no visual at all must not touch anything (graybox runs).
	player.visual = null
	player.reset()
	check(true, "16: reset() survives a player with no visual")

# --- 17. The stage machine: run -> boss -> stage_clear -> run (systems spec §10.1) ---

## One whole lap of the phase machine on a shortened stage, driven tick by tick: the distance target
## and the drain gate, the silent timeout clear, the drain handing straight into the boss, the rigs
## staying square, `run_clock` freezing everywhere but `run`, and stage 2 opening with the next
## boss's name.
func _test_stage_machine() -> void:
	var rig := _stage_rig({
		"stage_base_distance": 60.0,
		"stage_distance_step": 20.0,
		"stage_drain_distance": 20.0,
		"stage_drain_timeout": 0.5,
		"stage_clear_seconds": 0.5,
	})
	var game: Node3D = rig["game"]
	var stage: Node = rig["stage"]
	var spawner: Node = rig["spawner"]
	var turn_rig: Node3D = rig["turn_rig"]
	var camera: Node3D = rig["camera_rig"]
	var events: Dictionary = rig["events"]
	var drivers: Array = [rig["speed"], stage]

	check(stage.phase == &"idle" and int(stage.stage_index) == 0,
		"17: a reset StageManager is idle on stage 0, got %s / %d" % [stage.phase, int(stage.stage_index)])
	stage.begin()
	check(stage.phase == &"run" and int(stage.stage_index) == 1,
		"17: begin() opens stage 1 in the run phase, got %s / %d" % [stage.phase, int(stage.stage_index)])
	check(events["stage_started"].size() == 1, "17: stage 1 announces itself exactly once")
	check(int(events["stage_started"][0][0]) == 1
		and StringName(events["stage_started"][0][1]) == &"Flaky Test Swarm",
		"17: stage_started carries the index and the boss name, got %s" % [events["stage_started"][0]])
	check(is_equal_approx(float(events["stage_started"][0][2]), float(game.config.base_speed)),
		"17: stage 1 opens at the base speed, got %.2f" % float(events["stage_started"][0][2]))
	check(is_equal_approx(float(stage.stage_distance_target), 60.0),
		"17: stage 1 asks for 60 m, got %.1f" % float(stage.stage_distance_target))
	check(events["phase_changed"] == [&"run"], "17: idle -> run is the only phase change so far, got %s"
		% [events["phase_changed"]])
	check(spawner.spawn_calls == [true], "17: opening a stage turns the spawner on, got %s" % [spawner.spawn_calls])
	check(turn_rig.rotation.is_equal_approx(Vector3.ZERO) and camera.rotation.is_equal_approx(Vector3.ZERO),
		"17: both rigs open square")
	_check_no_turn_fields(game, "17")
	_check_no_turn_fields(stage, "17 stage")

	# The drain gate: the spawner stops a drain's worth of metres before the target.
	_tick(drivers, _ticks(1.0))
	check(float(game.run_clock) > 0.9, "17: run_clock advances in the run phase, got %.2f" % float(game.run_clock))
	check(bool(spawner.spawning), "17: the spawner is still placing a second into the stage")
	var clock_before_drain := float(game.run_clock)
	while float(stage.stage_distance) < 45.0 and float(game.elapsed) < 30.0:
		_tick_stage(drivers, game, 1)
	check(not bool(spawner.spawning), "17: the spawner is switched off %.1f m into a 60 m stage"
		% float(stage.stage_distance))
	check(spawner.spawn_calls == [true, false], "17: the drain gate fires once, got %s" % [spawner.spawn_calls])
	check(float(game.run_clock) > clock_before_drain, "17: the drain is still part of the run clock")
	check(turn_rig.rotation.is_equal_approx(Vector3.ZERO) and camera.rotation.is_equal_approx(Vector3.ZERO),
		"17: the rigs stay square through the drain")

	# A blocking hazard short of the clear line holds the stage open until the drain times out, and
	# then it is taken out silently: no dodge, no bonus, no hazard_cleared. With no arena mounted,
	# the boss phase is the documented fallback and ends on the same tick the drain does.
	var straggler := _hazard(&"pr_backlog_low")
	straggler.add_to_group(&"runner_hazards")
	straggler.position = Vector3(0.0, 0.0, 4.0)
	while float(stage.stage_distance) < 60.0 and float(game.elapsed) < 40.0:
		_tick_stage(drivers, game, 1)
	_tick_stage(drivers, game, _ticks(0.2))
	check(stage.phase == &"run", "17: a blocking hazard inside the clear line holds the run open")
	check(int(straggler.cleared) == 0, "17: the straggler is left alone while the drain still has time")
	check(events["bonus_awarded"].is_empty(), "17: a silent drain clear pays no bonus")
	_tick_stage(drivers, game, _ticks(0.45))
	check(int(straggler.cleared) == 1, "17: the drain timeout clears the straggler exactly once, got %d"
		% int(straggler.cleared))
	check(stage.phase == &"stage_clear", "17: the drain timeout hands straight through the boss fallback, got %s"
		% stage.phase)
	check(events["phase_changed"] == [&"run", &"boss", &"stage_clear"],
		"17: the phases go round in order, got %s" % [events["phase_changed"]])
	check(not bool(spawner.spawning) and spawner.spawn_calls == [true, false],
		"17: the spawner stays off once the drain hands off, got %s" % [spawner.spawn_calls])
	check(turn_rig.rotation.is_equal_approx(Vector3.ZERO) and camera.rotation.is_equal_approx(Vector3.ZERO),
		"17: the rigs are still square once the drain has handed off")

	# No arena is mounted here, so the boss phase is the documented fallback: it ends on the tick it
	# starts, no boss_retreated goes out, and the stage clears anyway.
	check(stage.phase == &"stage_clear", "17: a missing arena clears the stage straight away, got %s" % stage.phase)
	check(events["boss_retreated"].is_empty() and events["boss_defeated"].is_empty(),
		"17: a fallback boss phase resolves no fight")
	check(events["stage_cleared"].size() == 1 and int(events["stage_cleared"][0][0]) == 1,
		"17: stage_cleared names stage 1, got %s" % [events["stage_cleared"]])
	check(int(events["stage_cleared"][0][1]) == 400,
		"17: the stage 1 bonus is stage_clear_bonus_base, got %d" % int(events["stage_cleared"][0][1]))
	check(events["bonus_awarded"].size() == 1 and events["bonus_awarded"][0][1] == &"stage_clear",
		"17: the stage bonus reaches the score as a stage_clear bonus, got %s" % [events["bonus_awarded"]])
	check(int(stage.stages_cleared) == 1, "17: the cleared-stage counter moved, got %d" % int(stage.stages_cleared))

	# ...and on to stage 2, which is a longer run behind the next boss in the roster. The card is
	# ticked to its own end rather than for a guessed span, so the freeze is asserted over exactly
	# the phase it belongs to however much of stage_clear_seconds the boss fallback already used.
	var clock_at_clear := float(game.run_clock)
	var drifted := false
	var card_ticks := 0
	while stage.phase == &"stage_clear" and card_ticks < _ticks(2.0):
		_tick_stage(drivers, game, 1)
		card_ticks += 1
		if not is_equal_approx(float(game.run_clock), clock_at_clear):
			drifted = true
	check(not drifted, "17: run_clock is frozen through the stage-clear card, %.4f -> %.4f"
		% [clock_at_clear, float(game.run_clock)])
	check(card_ticks > 0 and card_ticks <= _ticks(0.5) + 1,
		"17: the stage-clear card ran %d ticks, expected at most %d" % [card_ticks, _ticks(0.5) + 1])
	check(stage.phase == &"run" and int(stage.stage_index) == 2,
		"17: the card hands over to stage 2, got %s / %d" % [stage.phase, int(stage.stage_index)])
	check(events["stage_started"].size() == 2
		and StringName(events["stage_started"][1][1]) == &"Merge Conflict Hydra",
		"17: stage 2 announces the next boss, got %s" % [events["stage_started"]])
	check(is_equal_approx(float(stage.stage_distance_target), 80.0),
		"17: stage 2 asks for 80 m, got %.1f" % float(stage.stage_distance_target))
	check(is_equal_approx(float(events["stage_started"][1][2]),
		float(game.config.base_speed) + float(game.config.stage_speed_step)),
		"17: stage 2 opens a step faster, got %.2f" % float(events["stage_started"][1][2]))
	check(spawner.spawn_calls == [true, false, true], "17: stage 2 turns the spawner back on, got %s"
		% [spawner.spawn_calls])
	check(events["stage_started"].size() == int(stage.stage_index),
		"17: exactly one stage_started per stage, %d for %d stages"
			% [events["stage_started"].size(), int(stage.stage_index)])

# --- 18. The escalation formula at cycles 0-4 (contract §11.10) ---

func _test_escalation() -> void:
	var c := base_config
	check(StageDefs.boss_slot(1) == 0 and StageDefs.boss_slot(3) == 2 and StageDefs.boss_slot(4) == 0,
		"18: the boss slot is (index - 1) %% 3")
	check(StageDefs.cycle(1) == 0 and StageDefs.cycle(3) == 0 and StageDefs.cycle(4) == 1
		and StageDefs.cycle(13) == 4, "18: the cycle is (index - 1) / 3")
	check(StageDefs.boss_name(2) == &"Merge Conflict Hydra" and StageDefs.boss_name(6) == &"Legacy Monolith",
		"18: the roster repeats every three stages")
	check(is_equal_approx(StageDefs.speed_bonus(1, c), 0.0)
		and is_equal_approx(StageDefs.speed_bonus(4, c), 3.0)
		and is_equal_approx(StageDefs.speed_bonus(20, c), float(c.stage_speed_bonus_max)),
		"18: the stage speed bonus steps up and stops at the cap")
	check(is_equal_approx(StageDefs.difficulty_floor(1, c), 0.0)
		and is_equal_approx(StageDefs.difficulty_floor(3, c), 0.5)
		and is_equal_approx(StageDefs.difficulty_floor(9, c), 1.0),
		"18: the difficulty floor steps up and stops at 1.0")
	check(is_equal_approx(StageDefs.distance_target(1, c), float(c.stage_base_distance))
		and is_equal_approx(StageDefs.distance_target(40, c), float(c.stage_distance_max)),
		"18: the stage distance steps up and stops at the cap")

	for slot in BossDefs.SLOTS.size():
		var base: Dictionary = BossDefs.SLOTS[slot]
		for cycle in 5:
			var stage_index := cycle * BossDefs.SLOTS.size() + slot + 1
			var def := BossDefs.fight_def(stage_index, c)
			var tag := "18: %s c%d" % [base["kind"], cycle]
			check(int(def["cycle"]) == cycle and int(def["slot"]) == slot,
				"%s: stage %d landed on slot %d cycle %d" % [tag, stage_index, int(def["slot"]), int(def["cycle"])])
			check(int(def["hp"]) == int(round(float(base["hp"]) * pow(float(c.boss_hp_growth), cycle))),
				"%s: hp is %d" % [tag, int(def["hp"])])
			check(is_equal_approx(float(def["projectile_speed"]),
				minf(float(base["projectile_speed"]) * pow(float(c.boss_projectile_speed_growth), cycle),
					float(c.boss_projectile_speed_max))),
				"%s: the projectile speed is %.3f" % [tag, float(def["projectile_speed"])])
			check(is_equal_approx(float(def["tool_interval"]),
				maxf(float(base["tool_interval"]) * pow(float(c.boss_tool_interval_growth), cycle),
					float(c.boss_tool_interval_min))),
				"%s: the tool interval is %.3f" % [tag, float(def["tool_interval"])])
			for phase in range(1, BossDefs.PHASE_COUNT + 1):
				var row: Array = base["telegraph"]
				var intervals: Array = base["attack_interval"]
				check(is_equal_approx(BossDefs.telegraph_for(def, phase),
					maxf(float(row[phase - 1]) * pow(float(c.boss_telegraph_growth), cycle),
						float(c.boss_telegraph_min))),
					"%s p%d: the telegraph is %.4f" % [tag, phase, BossDefs.telegraph_for(def, phase)])
				check(is_equal_approx(BossDefs.attack_interval_for(def, phase),
					maxf(float(intervals[phase - 1]) * pow(float(c.boss_attack_interval_growth), cycle),
						float(c.boss_attack_interval_min))),
					"%s p%d: the attack interval is %.4f" % [tag, phase, BossDefs.attack_interval_for(def, phase)])

	# Cycle 4 is the window the boss validator sweeps: the projectile speed and every telegraph are
	# already pinned there, which is what makes cycle 4 the worst case for the reaction budget. The
	# two interval curves are shallower and only bottom out later, so they are pinned at cycle 10.
	for slot in BossDefs.SLOTS.size():
		var late := BossDefs.fight_def(4 * BossDefs.SLOTS.size() + slot + 1, c)
		check(is_equal_approx(float(late["projectile_speed"]), float(c.boss_projectile_speed_max)),
			"18: %s hits the projectile speed cap by cycle 4, got %.3f"
				% [late["kind"], float(late["projectile_speed"])])
		for phase in range(1, BossDefs.PHASE_COUNT + 1):
			check(is_equal_approx(BossDefs.telegraph_for(late, phase), float(c.boss_telegraph_min)),
				"18: %s p%d hits the telegraph floor by cycle 4, got %.4f"
					% [late["kind"], phase, BossDefs.telegraph_for(late, phase)])
		check(float(late["tool_interval"]) > float(c.boss_tool_interval_min),
			"18: %s still has tool interval headroom at cycle 4, got %.3f"
				% [late["kind"], float(late["tool_interval"])])
		var deep := BossDefs.fight_def(10 * BossDefs.SLOTS.size() + slot + 1, c)
		check(is_equal_approx(float(deep["tool_interval"]), float(c.boss_tool_interval_min)),
			"18: %s hits the tool interval floor by cycle 10, got %.3f"
				% [deep["kind"], float(deep["tool_interval"])])
		check(is_equal_approx(BossDefs.attack_interval_for(deep, 3), float(c.boss_attack_interval_min)),
			"18: %s hits the attack interval floor by cycle 10, got %.3f"
				% [deep["kind"], BossDefs.attack_interval_for(deep, 3)])
		check(int(deep["hp"]) > int(late["hp"]),
			"18: %s keeps gaining hp past cycle 4 (%d -> %d)" % [deep["kind"], int(late["hp"]), int(deep["hp"])])

	# boss_hp_scale multiplies the base HP before the cycle growth, so a scaled config shortens every
	# fight without touching the curve: 100 x 0.4 at cycle 0, and 100 x 1.35 x 0.4 at cycle 1.
	var scaled := base_config.duplicate() as RunConfig
	scaled.boss_hp_scale = 0.4
	check(int(BossDefs.fight_def(1, scaled)["hp"]) == 40
		and int(BossDefs.fight_def(4, scaled)["hp"]) == 54,
		"18: boss_hp_scale 0.4 gives flaky_test_swarm %d hp at c0 and %d at c1"
			% [int(BossDefs.fight_def(1, scaled)["hp"]), int(BossDefs.fight_def(4, scaled)["hp"])])

	# Accepted tools: every phase takes all four except the three the contract §11.7 names.
	var hydra := BossDefs.fight_def(2, c)
	check(BossDefs.accepted_tools(hydra, 1).size() == ToolDefs.kinds().size(),
		"18: an unrestricted phase accepts every tool")
	check(BossDefs.accepted_tools(hydra, 2) == [&"unit_test", &"lint_rule"],
		"18: Hydra phase 2 accepts unit_test and lint_rule, got %s" % [BossDefs.accepted_tools(hydra, 2)])
	var monolith := BossDefs.fight_def(3, c)
	check(BossDefs.accepted_tools(monolith, 2) == [&"auto_fix_patch", &"review_comment"],
		"18: Monolith phase 2 accepts auto_fix_patch and review_comment")
	check(BossDefs.accepted_tools(monolith, 3) == [&"unit_test"],
		"18: Monolith phase 3 accepts unit_test alone")

# --- 19 / 20. Boss HP, phases and tool damage (systems spec §10.3) ---

func _test_boss_fight() -> void:
	# Contract 2.6 §11.14: a kill holds the fight for its defeat cinematic, shortened here to 0.2 s.
	var rig := _boss_rig({"boss_intro_seconds": 0.0, "boss_defeat_seconds": 0.2, "boss_outro_seconds": 0.0})
	var game: Node3D = rig["game"]
	var arena: Node3D = rig["arena"]
	var score: Node = rig["score"]
	var events: Dictionary = rig["events"]
	# Contract §11.4: before the first fight the facade and the arena agree on an empty boss block.
	check(_boss_info_is_empty(game.get_boss_info()) and _boss_info_is_empty(arena.get_boss_info()),
		"19: get_boss_info is empty before the first fight, got %s / %s"
			% [game.get_boss_info(), arena.get_boss_info()])
	arena.start(1)
	check(events["boss_spawned"].size() == 1 and StringName(events["boss_spawned"][0][0]) == &"flaky_test_swarm",
		"19: boss_spawned names the stage's boss, got %s" % [events["boss_spawned"]])
	check(int(events["boss_spawned"][0][1]) == 100, "19: stage 1 opens on 100 hp, got %d"
		% int(events["boss_spawned"][0][1]))
	check(int(arena.hp) == 100 and int(arena.max_hp) == 100 and int(arena.phase) == 1,
		"19: the fight starts full and in phase 1")
	check(arena.boss != null and not bool(arena.finished), "19: the fight is live with a boss node")
	check(events["boss_health_changed"].size() == 1, "19: the opening health is announced once")
	var info: Dictionary = arena.get_boss_info()
	check(StringName(info["kind"]) == &"flaky_test_swarm" and int(info["hp"]) == 100
		and int(info["phase"]) == 1 and (info["pending_attacks"] as Array).is_empty(),
		"19: get_boss_info reports the fresh fight, got %s" % [info])
	# Contract §11.4: phase_count is the fight's own phase count, so a HUD can draw "1 / 3" from the
	# one dictionary; the facade mirrors it while the arena is live.
	check(int(info["phase_count"]) == BossDefs.PHASE_COUNT
		and int(game.get_boss_info()["phase_count"]) == BossDefs.PHASE_COUNT,
		"19: get_boss_info reports phase_count %d / %d, expected %d"
			% [int(info["phase_count"]), int(game.get_boss_info()["phase_count"]), BossDefs.PHASE_COUNT])

	# Five Auto-Fix patches at 20 damage: the 66 % and the 33 % thresholds are crossed once each.
	var expected_hp := 100
	for i in 5:
		arena.apply_tool(&"auto_fix_patch")
		expected_hp -= 20
		check(int(arena.hp) == expected_hp, "19: tool %d left %d hp, expected %d" % [i, int(arena.hp), expected_hp])
		check(events["tool_collected"].size() == i + 1
			and int(events["tool_collected"][i][1]) == 20,
			"20: tool %d reported damage %s" % [i, events["tool_collected"][i]])
	check(events["boss_phase_changed"] == [2, 3],
		"19: the phase rises once per threshold, got %s" % [events["boss_phase_changed"]])
	check(int(arena.phase) == 3, "19: a boss on 0 hp is in its last phase, got %d" % int(arena.phase))
	check(int(arena.tools_used) == 5 and int(arena.boss_damage_dealt) == 100,
		"20: the fight counted %d tools for %d damage" % [int(arena.tools_used), int(arena.boss_damage_dealt)])
	check(events["boss_defeated"].size() == 1 and StringName(events["boss_defeated"][0][0]) == &"flaky_test_swarm",
		"19: boss_defeated fires once, got %s" % [events["boss_defeated"]])
	check(int(events["boss_defeated"][0][1]) == int(game.config.boss_kill_bonus_base),
		"19: the stage 1 kill bonus is boss_kill_bonus_base, got %d" % int(events["boss_defeated"][0][1]))
	check(events["boss_retreated"].is_empty(), "19: a defeated boss never also retreats")
	check(int(arena.bosses_defeated) == 1 and int(arena.bosses_escaped) == 0,
		"19: the defeat is the only ending counted")
	var tool_bonus := int(game.config.tool_bonus)
	check(int(score.bonus_total) == tool_bonus * 5 + int(game.config.boss_kill_bonus_base),
		"19: the fight paid %d in bonuses" % int(score.bonus_total))
	check(_bonus_reasons(events) == [&"tool", &"tool", &"tool", &"tool", &"tool", &"boss_kill"],
		"19: the bonus reasons are five tools and a kill, got %s" % [_bonus_reasons(events)])

	# The defeat cinematic holds the fight open so the visual gets its play_defeat time.
	check(not bool(arena.finished), "19: the fight is not finished until the outro is over")
	check(StringName(arena.cinematic_mode) == &"defeat_full" and is_equal_approx(float(arena.cinematic_seconds), 0.2),
		"19: the kill opens a %.2f s %s cinematic, expected a 0.20 s defeat_full"
			% [float(arena.cinematic_seconds), arena.cinematic_mode])
	arena.tick(0.1)
	check(not bool(arena.finished), "19: the outro is still running at 0.1 s")
	arena.tick(0.15)
	check(bool(arena.finished) and arena.boss == null, "19: the outro ends the fight and frees the boss")
	check(int(arena.hp) == 0, "19: a defeated boss stays on 0 hp")
	# And once the fight is over both readers go back to the empty block, so a stage-clear HUD never
	# shows the boss it just killed.
	check(_boss_info_is_empty(game.get_boss_info()) and _boss_info_is_empty(arena.get_boss_info()),
		"19: get_boss_info is empty after the fight finishes, got %s / %s"
			% [game.get_boss_info(), arena.get_boss_info()])
	_free_rig(rig)

	# Resisted phases: the tool is still collected and still paid for, it just deals nothing.
	var hydra_rig := _boss_rig({"boss_intro_seconds": 0.0, "boss_defeat_seconds": 0.0, "boss_outro_seconds": 0.0})
	var hydra: Node3D = hydra_rig["arena"]
	var hydra_events: Dictionary = hydra_rig["events"]
	var hydra_score: Node = hydra_rig["score"]
	hydra.start(2)
	check(int(hydra.hp) == 140, "20: stage 2 opens on 140 hp, got %d" % int(hydra.hp))
	for i in 3:
		hydra.apply_tool(&"auto_fix_patch")
	check(int(hydra.hp) == 80 and int(hydra.phase) == 2,
		"20: the Hydra is in phase 2 on %d hp" % int(hydra.hp))
	var resisted_before: int = hydra_events["tool_collected"].size()
	var score_before: int = hydra_score.bonus_total
	hydra.apply_tool(&"review_comment")
	check(int(hydra.hp) == 80, "20: a resisted tool costs the boss nothing, hp %d" % int(hydra.hp))
	check(hydra_events["tool_collected"].size() == resisted_before + 1
		and int(hydra_events["tool_collected"][resisted_before][1]) == 0,
		"20: a resisted tool reports tool_collected(kind, 0), got %s"
			% [hydra_events["tool_collected"][resisted_before]])
	check(int(hydra.tools_used) == 4, "20: a resisted tool is still a tool used, got %d" % int(hydra.tools_used))
	check(int(hydra.boss_damage_dealt) == 60, "20: a resisted tool adds no damage, got %d"
		% int(hydra.boss_damage_dealt))
	check(int(hydra_score.bonus_total) == score_before + int(hydra.config.tool_bonus),
		"20: a resisted tool still pays the tool bonus")
	hydra.apply_tool(&"unit_test")
	check(int(hydra.hp) == 65, "20: an accepted tool damages the same phase, hp %d" % int(hydra.hp))
	_free_rig(hydra_rig)

# --- 21. The boss timeout retreats, it never dies (systems spec §10.3) ---

func _test_boss_timeout() -> void:
	var rig := _boss_rig({
		"boss_intro_seconds": 0.0,
		"boss_defeat_seconds": 0.0,
		"boss_outro_seconds": 0.0,
		"boss_timeout_seconds": 1.0
	})
	var game: Node3D = rig["game"]
	var arena: Node3D = rig["arena"]
	var events: Dictionary = rig["events"]
	arena.start(3)
	check(int(arena.hp) == 180, "21: stage 3 opens on 180 hp, got %d" % int(arena.hp))
	arena.apply_tool(&"unit_test")
	check(int(arena.hp) == 165, "21: the one tool that landed took it to %d hp" % int(arena.hp))
	for i in _ticks(1.05):
		arena.tick(TICK)
	check(events["boss_retreated"].size() == 1, "21: the timeout retreats the boss once, got %d"
		% events["boss_retreated"].size())
	check(events["boss_defeated"].is_empty(), "21: a boss that timed out was never defeated")
	check(StringName(events["boss_retreated"][0][0]) == &"legacy_monolith",
		"21: boss_retreated names the boss, got %s" % events["boss_retreated"][0][0])
	# The partial bonus: the kill bonus scaled by boss_retreat_bonus_ratio and by the damage that landed.
	var kill := int(game.config.boss_kill_bonus_base) + int(game.config.boss_kill_bonus_per_stage) * 2
	var expected := int(round(float(kill) * float(game.config.boss_retreat_bonus_ratio) * (15.0 / 180.0)))
	check(int(events["boss_retreated"][0][1]) == expected,
		"21: the retreat bonus is %d, expected %d" % [int(events["boss_retreated"][0][1]), expected])
	check(int(arena.bosses_escaped) == 1 and int(arena.bosses_defeated) == 0,
		"21: the escape is the only ending counted")
	check(bool(arena.finished) and arena.boss == null,
		"21: a zero-length outro finishes the fight on the spot")
	check(arena.projectile_count() == 0 and arena.tool_count() == 0,
		"21: the retreat clears the arena")
	_free_rig(rig)

# --- 22. pursuit_alert ordering and the pursuer epsilon (contract §11.4, systems spec §10.7) ---

func _test_pursuit_alert() -> void:
	var game := _make_game()
	var hits: Node = _systems(game)["hits"]
	var alerts: Array = []
	game.pursuit_alert.connect(func(kind: StringName, seconds: float) -> void:
		alerts.append([kind, seconds]))
	var started: Array = []
	game.pursuit_started.connect(func(seconds: float) -> void:
		started.append(seconds))

	hits.report_hit(_hazard(&"bug_swarm"))
	check(alerts.size() == 1 and StringName(alerts[0][0]) == &"warn",
		"22: the first hit opens the alert with warn, got %s" % [alerts])
	check(started.size() == 1 and is_equal_approx(float(alerts[0][1]), float(started[0])),
		"22: the warn alert carries the same countdown pursuit_started does")
	var critical := float(game.config.pursuit_critical_seconds)
	_tick([hits], _ticks(float(game.config.recovery_seconds) - critical - 0.5))
	check(alerts.size() == 1, "22: nothing is announced above the critical line, got %s" % [alerts])
	_tick([hits], _ticks(1.0))
	check(alerts.size() == 2 and StringName(alerts[1][0]) == &"critical",
		"22: the critical alert fires as the timer drops under %.1f s, got %s" % [critical, alerts])
	check(float(alerts[1][1]) <= critical + 0.05 and float(alerts[1][1]) > 0.0,
		"22: the critical alert carries the seconds left, got %.3f" % float(alerts[1][1]))
	_tick([hits], _ticks(2.0))
	check(alerts.size() == 2, "22: critical fires once per pursuit, got %d alerts" % alerts.size())
	_tick([hits], _ticks(critical + 0.5))
	check(alerts.size() == 3 and StringName(alerts[2][0]) == &"clear"
		and is_zero_approx(float(alerts[2][1])),
		"22: recovery clears the alert, got %s" % [alerts])
	check(hits.is_safe(), "22: the alert cleared because the pursuit did")

	# A second cycle re-arms the critical alert, and the catch clears it before the cinematic.
	hits.report_hit(_hazard(&"merge_conflict"))
	check(alerts.size() == 4 and StringName(alerts[3][0]) == &"warn", "22: a new pursuit warns again")
	hits.iframe_remaining = 0.0
	hits.report_hit(_hazard(&"comment_flood"))
	check(alerts.size() == 5 and StringName(alerts[4][0]) == &"clear",
		"22: the catch stands the alert down, got %s" % [alerts])
	check(not hits.is_alive(), "22: that last hit really was the catch")

## The epsilon gate on pursuer_distance_changed (contract §11.4): a glide must not spam the frontend,
## and the terminal 1.0 always goes out.
func _test_pursuer_distance() -> void:
	var game := _make_game()
	var pursuer := Node3D.new()
	pursuer.set_script(pursuer_script)
	junk.append(pursuer)
	var seen: Array[float] = []
	game.pursuer_distance_changed.connect(func(value: float) -> void:
		seen.append(value))
	pursuer.setup(game)
	check(seen.is_empty(), "23: a reset pursuer announces nothing, got %s" % [seen])
	var epsilon := float(game.config.pursuer_distance_epsilon)
	pursuer.set_threat(epsilon * 0.4)
	check(seen.is_empty(), "23: a sub-epsilon step stays quiet, got %s" % [seen])
	pursuer.set_threat(epsilon * 3.0)
	check(seen.size() == 1 and is_equal_approx(seen[0], epsilon * 3.0),
		"23: a step past the epsilon is announced, got %s" % [seen])
	pursuer.set_threat(epsilon * 3.0 + epsilon * 0.4)
	check(seen.size() == 1, "23: a sub-epsilon step on top of that stays quiet, got %s" % [seen])
	pursuer.set_threat(1.0)
	check(seen.size() == 2 and is_equal_approx(seen[1], 1.0), "23: the terminal 1.0 is announced")
	pursuer.set_threat(1.0)
	check(seen.size() == 2, "23: the terminal 1.0 is never re-announced, got %d" % seen.size())
	check(is_equal_approx(pursuer.distance_epsilon(), epsilon),
		"23: the gate reads config.pursuer_distance_epsilon")
	var zero_config: RunConfig = game.config.duplicate()
	zero_config.pursuer_distance_epsilon = 0.0
	pursuer.config = zero_config
	check(pursuer.distance_epsilon() > 0.0,
		"23: an authored 0 epsilon still keeps a floor, got %.6f" % pursuer.distance_epsilon())

# --- 24. A catch mid-fight aborts to idle and ends the run once (systems spec §10.1) ---

func _test_caught_mid_boss() -> void:
	var path := "user://test_leaderboard_boss_%d.cfg" % (randi() % 1000000)
	temp_paths.append(path)
	var rig := _stage_rig({
		"stage_base_distance": 12.0,
		"stage_drain_distance": 6.0,
		"stage_drain_timeout": 0.2,
		"boss_intro_seconds": 0.0,
		"boss_defeat_seconds": 0.0,
		"boss_outro_seconds": 0.0,
		"stage_clear_seconds": 0.5
	}, true, true)
	var game: Node3D = rig["game"]
	var stage: Node = rig["stage"]
	var arena: Node3D = rig["arena"]
	var hits: Node = rig["hits"]
	var events: Dictionary = rig["events"]
	# The facade is hand-built, so it has no run_id from start_run(); the board write needs one, and
	# it goes to the throwaway path above and nowhere near user://leaderboard.cfg.
	game.leaderboard_path = path
	game.run_id = "boss-catch-%d" % (randi() % 1000000)
	var drivers: Array = [rig["speed"], stage]
	stage.begin()
	var guard := 0
	while stage.phase != &"boss" and guard < _ticks(20.0):
		_tick_stage(drivers, game, 1)
		guard += 1
	check(stage.phase == &"boss", "24: the run reached the boss phase, got %s" % stage.phase)
	check(events["boss_spawned"].size() == 1, "24: the mounted arena really started a fight")
	arena.apply_tool(&"review_comment")
	check(int(stage.tools_used) == 1 and int(stage.boss_damage_dealt) == 10,
		"24: the StageManager tallied the tool off the facade signal")
	check(int(arena.projectile_count()) >= 0, "24: the arena is live")

	hits.report_hit(_hazard(&"bug_swarm"))
	hits.iframe_remaining = 0.0
	hits.report_hit(_hazard(&"comment_flood"))
	check(int(game.caught_calls) == 1, "24: the catch ran once, got %d" % int(game.caught_calls))
	check(game.state == &"caught", "24: the facade moved to the caught state, got %s" % game.state)
	check(stage.phase == &"idle", "24: the catch aborts the fight back to idle, got %s" % stage.phase)
	check(events["phase_changed"][events["phase_changed"].size() - 1] == &"idle",
		"24: the last phase change is to idle, got %s" % [events["phase_changed"]])
	check(arena.projectile_count() == 0 and arena.tool_count() == 0,
		"24: abort() empties the arena")
	check(events["boss_defeated"].is_empty() and events["boss_retreated"].is_empty(),
		"24: an aborted fight resolves neither way")
	check(events["stage_cleared"].is_empty(), "24: an aborted fight clears no stage")

	# A Dictionary, not two locals: a GDScript lambda captures locals by value, so a counter kept in
	# a plain int would be incremented on the lambda's own copy and read back as 0 here.
	var seen := {"finished": 0, "result": {}}
	game.run_finished.connect(func(value: Dictionary) -> void:
		seen["finished"] += 1
		seen["result"] = value)
	_tick_stage([game], game, _ticks(float(game.config.caught_sequence_seconds) + 0.5))
	var finished := int(seen["finished"])
	var result: Dictionary = seen["result"]
	check(finished == 1, "24: run_finished fires exactly once, got %d" % finished)
	check(game.state == &"finished", "24: the run ends finished, got %s" % game.state)
	check(int(result.get("stage_reached", 0)) == 1, "24: the result reached stage %s"
		% result.get("stage_reached", "<missing>"))
	_check_no_turn_keys(result, "24 result")
	check(int(result.get("tools_used", 0)) == 1, "24: the result counted %s tools"
		% result.get("tools_used", "<missing>"))
	check(int(result.get("boss_damage_dealt", 0)) == 10, "24: the result carries %s boss damage"
		% result.get("boss_damage_dealt", "<missing>"))
	check(int(result.get("bosses_defeated", -1)) == 0 and int(result.get("bosses_escaped", -1)) == 0,
		"24: an aborted fight counts as neither a kill nor an escape")
	check(int(result.get("stages_cleared", -1)) == 0, "24: no stage was cleared before the catch")
	_free_rig(rig)

# --- 24b. Boss checkpoint retry (contract §11.13) ---

## The checkpoint config: a short stage so every retry reaches its boss inside a few game seconds.
func _checkpoint_overrides() -> Dictionary:
	return {
		"stage_base_distance": 12.0,
		"stage_drain_distance": 6.0,
		"stage_drain_timeout": 0.2,
		"boss_intro_seconds": 0.0,
		"boss_defeat_seconds": 0.0,
		"boss_outro_seconds": 0.0,
		"stage_clear_seconds": 0.5
	}

## A stage rig on the recording-router facade: the real catch, the real start_run(), and every
## route retry() / retry_boss() asks for kept in `game.routes`.
func _checkpoint_rig(with_arena: bool) -> Dictionary:
	return _stage_rig(_checkpoint_overrides(), with_arena, true, route_game_script)

func _pending_checkpoint() -> Dictionary:
	var value: Variant = runner_game_script.get(&"pending_boss_checkpoint")
	return value if value is Dictionary else {}

## Tick the rig until `phase` or the guard runs out.
func _drive_to_phase(rig: Dictionary, phase: StringName, seconds: float) -> bool:
	var game: Node3D = rig["game"]
	var stage: Node = rig["stage"]
	var drivers: Array = [rig["speed"], rig["score"], stage]
	var guard := 0
	while stage.phase != phase and guard < _ticks(seconds):
		_tick_stage(drivers, game, 1)
		guard += 1
	return stage.phase == phase

## Two hits land the catch; then the caught sequence times out into run_finished.
func _catch_and_finish(rig: Dictionary) -> Dictionary:
	var game: Node3D = rig["game"]
	var hits: Node = rig["hits"]
	var seen := {"result": {}}
	game.run_finished.connect(func(value: Dictionary) -> void: seen["result"] = value)
	hits.report_hit(_hazard(&"bug_swarm"))
	hits.iframe_remaining = 0.0
	hits.report_hit(_hazard(&"comment_flood"))
	_tick_stage([game], game, _ticks(float(game.config.caught_sequence_seconds) + 0.5))
	return seen["result"]

func _test_boss_checkpoint() -> void:
	runner_game_script.set(&"pending_boss_checkpoint", {})
	var seed := 4242
	# --- a catch mid-boss leaves a checkpoint ---
	var rig := _checkpoint_rig(true)
	var game: Node3D = rig["game"]
	var stage: Node = rig["stage"]
	var arena: Node3D = rig["arena"]
	game.start_run(seed)
	check(game.seed == seed and not bool(game.checkpoint_retry), "24b: a plain run is not a checkpoint retry")
	check(game.boss_checkpoint.is_empty(), "24b: no checkpoint before the boss")
	check(_drive_to_phase(rig, &"run", 0.1) or stage.phase == &"run", "24b: the run opened on stage 1")
	_tick_stage([rig["speed"], rig["score"], stage], game, _ticks(0.3))
	check(game.boss_checkpoint.is_empty(), "24b: no checkpoint during the run phase")
	# Game Over tallies the systems own, set by hand so the checkpoint has something to carry.
	rig["effects"].power_ups_collected = 3
	rig["hits"].blocked_hits = 2
	rig["hits"].recoveries = 1
	check(_drive_to_phase(rig, &"boss", 20.0), "24b: the run reached the boss, got %s" % stage.phase)
	var checkpoint: Dictionary = game.boss_checkpoint.duplicate(true)
	check(not checkpoint.is_empty(), "24b: boss entry took a checkpoint")
	check(int(checkpoint.get("stage_index", 0)) == 1 and int(checkpoint.get("seed", 0)) == seed,
		"24b: the checkpoint is stage 1 of seed %d, got %s" % [seed, checkpoint])
	_check_no_turn_keys(checkpoint, "24b checkpoint")
	check(absf(float(checkpoint.get("run_clock", -1.0)) - float(game.run_clock)) < 0.0001,
		"24b: the checkpoint holds the frozen run_clock")
	check(float(checkpoint.get("score_exact", 0.0)) > 0.0, "24b: the checkpoint carries the score so far")
	for key in ["score", "multiplier", "best_multiplier", "bonus_total", "elapsed", "distance",
			"hazards_dodged", "hazards_blasted_total", "stages_cleared", "bosses_defeated",
			"bosses_escaped", "tools_used", "boss_damage_dealt", "power_ups", "hits_taken", "recoveries",
			"blocked_hits", "max_speed_reached", "chunks_spawned"]:
		check(checkpoint.has(key), "24b: the checkpoint is missing %s" % key)
	check(int(checkpoint["power_ups"]) == 3 and int(checkpoint["blocked_hits"]) == 2
		and int(checkpoint["recoveries"]) == 1 and int(checkpoint["hits_taken"]) == 0,
		"24b: the checkpoint carries the systems' tallies, got %s" % checkpoint)
	check(float(checkpoint["max_speed_reached"]) >= float(game.config.base_speed),
		"24b: the checkpoint carries the top speed so far, got %s" % checkpoint["max_speed_reached"])
	check(not checkpoint.has("hp"), "24b: HP is not part of the checkpoint")
	arena.apply_tool(&"review_comment")
	var result := _catch_and_finish(rig)
	check(game.state == &"finished", "24b: the mid-boss run finished, got %s" % game.state)
	check(game.boss_checkpoint == checkpoint, "24b: the catch leaves the checkpoint in place")
	check(result.has("checkpoint_retry") and not bool(result["checkpoint_retry"]),
		"24b: a plain run reports checkpoint_retry false")
	var first_run_id := String(result.get("run_id", ""))
	_check_game_over_buttons(game, result, true, "24b mid-boss")
	game.retry_boss()
	check(game.routes == ["runner_game"], "24b: retry_boss routes to runner_game, got %s" % [game.routes])
	check(_pending_checkpoint() == checkpoint, "24b: retry_boss carries the checkpoint across the reload")
	# Game Over keeps focus through the route's fade: Esc (go_to_menu) or Retry right after Retry Boss
	# must neither route again nor drop the checkpoint the first route is carrying.
	game.go_to_menu()
	game.retry()
	check(game.routes == ["runner_game"], "24b: a second action mid-route does not route, got %s" % [game.routes])
	check(_pending_checkpoint() == checkpoint, "24b: a second action mid-route keeps the pending checkpoint")
	_free_rig(rig)

	# --- retry_boss reloads straight into the boss with the run intact and full HP, twice over ---
	var previous_run_id := first_run_id
	for attempt in [1, 2]:
		var tag := "24b retry %d" % attempt
		rig = _checkpoint_rig(true)
		game = rig["game"]
		stage = rig["stage"]
		var hits: Node = rig["hits"]
		var events: Dictionary = rig["events"]
		game.start_run(0)
		check(_pending_checkpoint().is_empty(), "%s: start_run consumed the pending checkpoint" % tag)
		check(bool(game.checkpoint_retry), "%s: the run knows it is a checkpoint retry" % tag)
		check(game.seed == seed, "%s: the retry keeps seed %d, got %d" % [tag, seed, game.seed])
		check(stage.phase == &"boss", "%s: the retry opens in the boss phase, got %s" % [tag, stage.phase])
		check(int(game.stage_index) == 1, "%s: the retry is on stage %d" % [tag, int(game.stage_index)])
		check(int(game.score) == int(checkpoint["score"]) or int(game.score) == floori(float(checkpoint["score_exact"])),
			"%s: the score is back at %d, got %d" % [tag, int(checkpoint["score"]), int(game.score)])
		check(is_equal_approx(float(rig["score"].exact), float(checkpoint["score_exact"])),
			"%s: the exact score is restored" % tag)
		check(absf(float(game.run_clock) - float(checkpoint["run_clock"])) < 0.0001,
			"%s: run_clock is back at %.3f, got %.3f" % [tag, float(checkpoint["run_clock"]), float(game.run_clock)])
		check(is_equal_approx(float(game.elapsed), float(checkpoint["elapsed"]))
			and is_equal_approx(float(game.distance), float(checkpoint["distance"])),
			"%s: elapsed and distance are restored" % tag)
		check(int(game.hp) == int(game.config.max_hp) and int(hits.hp) == int(game.config.max_hp),
			"%s: the retry starts at full HP, got %d / %d" % [tag, int(game.hp), int(hits.hp)])
		check(int(rig["effects"].power_ups_collected) == int(checkpoint["power_ups"])
			and int(hits.hits_taken) == int(checkpoint["hits_taken"])
			and int(hits.recoveries) == int(checkpoint["recoveries"])
			and int(hits.blocked_hits) == int(checkpoint["blocked_hits"]),
			"%s: power-ups, hits, recoveries and blocks are restored" % tag)
		check(float(rig["speed"].max_speed_reached) >= float(checkpoint["max_speed_reached"]) - 0.0001,
			"%s: the top speed carries over, got %.3f" % [tag, float(rig["speed"].max_speed_reached)])
		check(events["stage_started"].size() == 1, "%s: stage_started fired %d times, expected one"
			% [tag, events["stage_started"].size()])
		check(events["boss_spawned"].size() == 1, "%s: the boss fight opened with the phase, got %d"
			% [tag, events["boss_spawned"].size()])
		var again: Dictionary = game.boss_checkpoint
		check(not again.is_empty(), "%s: boss entry re-took the checkpoint" % tag)
		_check_no_turn_keys(again, tag)
		check(int(again.get("stage_index", 0)) == 1,
			"%s: the fresh checkpoint is the same stage, got %s" % [tag, again])
		check(absf(float(again.get("run_clock", -1.0)) - float(checkpoint["run_clock"])) < 0.0001,
			"%s: run_clock stayed frozen, %.4f vs %.4f"
				% [tag, float(again.get("run_clock", -1.0)), float(checkpoint["run_clock"])])
		check(is_equal_approx(float(again.get("score_exact", 0.0)), float(checkpoint["score_exact"])),
			"%s: the score did not grow before the fight, %.3f vs %.3f"
				% [tag, float(again.get("score_exact", 0.0)), float(checkpoint["score_exact"])])
		result = _catch_and_finish(rig)
		check(bool(result.get("checkpoint_retry", false)), "%s: the result is flagged checkpoint_retry" % tag)
		check(String(result.get("run_id", "")) != previous_run_id and not String(result.get("run_id", "")).is_empty(),
			"%s: the retry wrote under a fresh run_id" % tag)
		_check_no_turn_keys(result, tag + " result")
		check(int(result.get("stage_reached", 0)) == 1,
			"%s: the result tallies stage %s" % [tag, result.get("stage_reached", "<missing>")])
		check(int(result.get("score", 0)) >= int(checkpoint["score"]), "%s: the score continued" % tag)
		check(int(result.get("power_ups", -1)) == int(checkpoint["power_ups"])
			and int(result.get("hits_taken", -1)) == int(checkpoint["hits_taken"]) + 2
			and int(result.get("blocked_hits", -1)) == int(checkpoint["blocked_hits"]),
			"%s: Game Over stats are whole-run totals, got %s" % [tag, result])
		previous_run_id = String(result.get("run_id", ""))
		checkpoint = game.boss_checkpoint.duplicate(true)
		check(not checkpoint.is_empty(), "%s: the retry's own catch mid-boss leaves a checkpoint" % tag)
		game.retry_boss()
		check(_pending_checkpoint() == checkpoint, "%s: the next retry_boss carries it on" % tag)
		_free_rig(rig)
	runner_game_script.set(&"pending_boss_checkpoint", {})

	# --- plain Retry always restarts from zero ---
	rig = _checkpoint_rig(true)
	game = rig["game"]
	game.start_run(seed)
	check(_drive_to_phase(rig, &"boss", 20.0), "24b retry: the run reached the boss")
	_catch_and_finish(rig)
	check(not game.boss_checkpoint.is_empty(), "24b retry: a checkpoint is on offer")
	game.retry()
	check(game.routes == ["runner_game"] and _pending_checkpoint().is_empty(),
		"24b retry: plain retry routes with no checkpoint")
	_free_rig(rig)

	# --- a stage clear drops the checkpoint, and a catch outside the boss leaves none ---
	rig = _checkpoint_rig(false)
	game = rig["game"]
	stage = rig["stage"]
	game.start_run(seed)
	check(_drive_to_phase(rig, &"stage_clear", 20.0), "24b run: the placeholder boss cleared the stage")
	check(game.boss_checkpoint.is_empty(), "24b run: the stage clear dropped the checkpoint")
	check(_drive_to_phase(rig, &"run", 5.0) and int(game.stage_index) == 2, "24b run: stage 2 is running")
	result = _catch_and_finish(rig)
	check(game.state == &"finished", "24b run: the run-phase catch finished the run")
	check(game.boss_checkpoint.is_empty(), "24b run: a catch in the run phase leaves no checkpoint")
	_check_game_over_buttons(game, result, false, "24b run")
	game.retry_boss()
	check(game.routes == ["runner_game"] and _pending_checkpoint().is_empty(),
		"24b run: retry_boss without a checkpoint is a plain retry")
	_free_rig(rig)
	runner_game_script.set(&"pending_boss_checkpoint", {})

	# --- the first route wins: Esc then Retry Boss never leaks a checkpoint into the menu's Play ---
	rig = _checkpoint_rig(false)
	game = rig["game"]
	game.boss_checkpoint = {"stage_index": 2, "seed": seed}
	game.go_to_menu()
	game.retry_boss()
	check(game.routes == ["runner"], "24b route: only the menu route is taken, got %s" % [game.routes])
	check(_pending_checkpoint().is_empty(), "24b route: Retry Boss after Esc leaves no pending checkpoint")
	_free_rig(rig)

	# --- nothing routes, or touches the pending checkpoint, while AppRouter is mid-fade ---
	var router: Node = root.get_node_or_null(^"AppRouter")
	check(router != null and &"busy" in router, "24b route: the AppRouter autoload is present")
	if router != null and &"busy" in router:
		rig = _checkpoint_rig(false)
		game = rig["game"]
		game.boss_checkpoint = {"stage_index": 3, "seed": seed}
		var in_flight := {"stage_index": 1, "seed": seed}
		runner_game_script.set(&"pending_boss_checkpoint", in_flight.duplicate(true))
		var was_busy: bool = router.busy
		router.busy = true
		game.retry_boss()
		game.retry()
		game.go_to_menu()
		router.busy = was_busy
		check(game.routes.is_empty(), "24b route: no route is asked for while AppRouter is busy, got %s" % [game.routes])
		check(_pending_checkpoint() == in_flight, "24b route: a busy AppRouter leaves the pending checkpoint alone")
		_free_rig(rig)
	runner_game_script.set(&"pending_boss_checkpoint", {})

## The fight seed is a function of the run seed and the stage alone (contract §11.13): stage 2 reached
## after a whole stage-1 fight draws the same lane and tool streams as a checkpoint retry into stage 2.
func _test_boss_stage_seed() -> void:
	var overrides := {"boss_intro_seconds": 0.0, "boss_defeat_seconds": 0.0, "boss_outro_seconds": 0.0}
	var seed := 4242
	var played := _boss_rig(overrides)
	var retried := _boss_rig(overrides)
	var other := _boss_rig(overrides)
	var a: Node3D = played["arena"]
	var b: Node3D = retried["arena"]
	var c: Node3D = other["arena"]
	played["game"].seed = seed
	retried["game"].seed = seed
	other["game"].seed = seed + 1
	a.start(1)
	var stage1_state: int = a.fight_rng.state
	for i in _ticks(2.0):
		a.tick(TICK)
	check(a.fight_rng.state != stage1_state, "24b seed: the stage-1 fight drew from fight_rng")
	a.start(2)
	b.start(2)
	c.start(2)
	check(a.fight_rng.state == b.fight_rng.state,
		"24b seed: stage 2 after a stage-1 fight seeds like a retry into stage 2, got %d vs %d"
			% [a.fight_rng.state, b.fight_rng.state])
	var draws_a: Array[int] = []
	var draws_b: Array[int] = []
	for i in 4:
		draws_a.append(a.fight_rng.randi())
		draws_b.append(b.fight_rng.randi())
	check(draws_a == draws_b, "24b seed: the stage-2 draws match, got %s vs %s" % [draws_a, draws_b])
	check(c.fight_rng.state != b.fight_rng.state, "24b seed: a different run seed gives a different stage-2 stream")
	_free_rig(played)
	_free_rig(retried)
	_free_rig(other)

## The real game_over.tscn against this facade: Retry Boss is shown, and takes the default focus,
## exactly when the run left a checkpoint; plain Retry is always there.
func _check_game_over_buttons(game: Node3D, result: Dictionary, expect_boss: bool, tag: String) -> void:
	var packed := load("res://scenes/runner/ui/game_over.tscn") as PackedScene
	check(packed != null, "%s: game_over.tscn failed to load" % tag)
	if packed == null:
		return
	var overlay := packed.instantiate()
	root.add_child(overlay)
	overlay.game = game
	# Not a qualifying run, so no name entry takes the focus first.
	var shown := result.duplicate(true)
	shown["qualifies"] = false
	overlay.show_result(shown, [])
	var boss_button: Button = overlay.retry_boss_button
	var retry_button: Button = overlay.retry_button
	check(boss_button.visible == expect_boss, "%s: Retry Boss visible is %s, expected %s"
		% [tag, boss_button.visible, expect_boss])
	check(retry_button.visible, "%s: plain Retry is always offered" % tag)
	var focused: Button = boss_button if expect_boss else retry_button
	check(focused.has_focus(), "%s: %s has the default focus" % [tag, focused.text])
	if expect_boss:
		check(boss_button.focus_next == boss_button.get_path_to(retry_button),
			"%s: Retry Boss leads the focus chain into Retry" % tag)
	root.remove_child(overlay)
	overlay.free()

# --- 25. Speed with the stage bonus and the difficulty floor (systems spec §10.2) ---

func _test_stage_speed_and_floor() -> void:
	var game := _make_game()
	var speed: Node = _systems(game)["speed"]
	var c: RunConfig = game.config
	var ramp := float(c.time_to_max_speed)
	for bonus in [0.0, 3.0, 6.0]:
		speed.set_stage_bonus(bonus)
		check(is_equal_approx(speed.speed_at(0.0), float(c.base_speed) + bonus),
			"25: bonus %.0f opens at %.2f" % [bonus, speed.speed_at(0.0)])
		check(is_equal_approx(speed.speed_at(ramp), float(c.max_speed) + bonus),
			"25: bonus %.0f tops out at %.2f" % [bonus, speed.speed_at(ramp)])
		check(is_equal_approx(speed.speed_at(ramp + 6000.0), float(c.hard_cap_speed) + bonus),
			"25: bonus %.0f caps the tail at %.2f, expected %.2f"
				% [bonus, speed.speed_at(ramp + 6000.0), float(c.hard_cap_speed) + bonus])
		check(is_equal_approx(speed.base_for_stage(), float(c.base_speed) + bonus),
			"25: base_for_stage carries the bonus")
	check(is_equal_approx(speed.speed_at(ramp + 6000.0), 32.0),
		"25: the top stage bonus reaches the contract §11.2 hard cap of 32 m/s")

	# Nitro multiplies the curve and is still clamped to nitro_speed_cap at the top stage bonus.
	speed.set_stage_bonus(float(c.stage_speed_bonus_max))
	speed.multiplier = float(c.nitro_speed_multiplier)
	_set_run_clock(game, ramp + 6000.0)
	speed._physics_process(TICK)
	check(is_equal_approx(float(speed.speed), float(c.nitro_speed_cap)),
		"25: Nitro at the top stage is clamped to %.1f, got %.2f" % [float(c.nitro_speed_cap), float(speed.speed)])
	check(float(speed.speed) <= 38.0 + 0.0001, "25: Nitro never passes 38 m/s")

	# normalized() cancels the bonus at both ends, so the frontend's 0..1 never shifts per stage.
	speed.multiplier = 1.0
	speed.speed = speed.base_for_stage()
	check(is_zero_approx(speed.normalized()), "25: the stage base normalizes to 0, got %.3f" % speed.normalized())
	speed.speed = float(c.max_speed) + float(c.stage_speed_bonus_max)
	check(is_equal_approx(speed.normalized(), 1.0), "25: the stage top normalizes to 1, got %.3f" % speed.normalized())

	# The floor: difficulty can never fall below the stage's own minimum.
	var floored := _make_game()
	var floored_speed: Node = _systems(floored)["speed"]
	floored_speed.set_difficulty_floor(0.5)
	check(is_equal_approx(floored_speed.difficulty_at(0.0), 0.5),
		"25: a stage floor of 0.5 holds the opening difficulty, got %.3f" % floored_speed.difficulty_at(0.0))
	check(is_equal_approx(floored_speed.difficulty_at(ramp * 0.25), 0.5),
		"25: the curve stays on the floor until it climbs past it")
	check(is_equal_approx(floored_speed.difficulty_at(ramp * 0.75), 0.75),
		"25: the curve wins again above the floor, got %.3f" % floored_speed.difficulty_at(ramp * 0.75))
	check(is_equal_approx(floored_speed.difficulty_at(ramp), 1.0), "25: the floor never caps the top")
	floored_speed.set_difficulty_floor(2.0)
	check(is_equal_approx(floored_speed.difficulty_at(0.0), 1.0),
		"25: a floor above 1 is clamped to 1, got %.3f" % floored_speed.difficulty_at(0.0))

# --- 26. Leaderboard schema 2 migrates a v1 board in place (contract §11.11) ---

func _test_leaderboard_migration() -> void:
	check(RunnerLeaderboard.SCHEMA_VERSION == 2, "26: the schema version is 2, got %d"
		% RunnerLeaderboard.SCHEMA_VERSION)
	var path := "user://test_leaderboard_v1_%d.cfg" % (randi() % 1000000)
	temp_paths.append(path)
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "version", 1)
	legacy.set_value("leaderboard", "entries", [_entry("v1-a", 300), _entry("v1-b", 100)])
	check(legacy.save(path) == OK, "26: the version 1 fixture board was written")

	var board := RunnerLeaderboard.read_board(path)
	check(int(board["version"]) == 1, "26: read_board reports the on-disk version 1, got %s" % board["version"])
	check(int(board["error"]) == OK, "26: a version 1 board reads normally, got error %s" % board["error"])
	var loaded := RunnerLeaderboard.load_entries(path)
	check(loaded.size() == 2 and int(loaded[0]["score"]) == 300,
		"26: a version 1 board keeps its rows, got %d" % loaded.size())

	# The next successful save rewrites the file as version 2, without losing the v1 runs.
	var result := RunnerLeaderboard.submit(_entry("v2-new", 200), path)
	check(int(result["error"]) == OK, "26: a version 1 board accepts the next run, got error %s" % result["error"])
	check(int(result["rank"]) == 2, "26: the new run placed at rank %d, expected 2" % int(result["rank"]))
	var migrated := ConfigFile.new()
	check(migrated.load(path) == OK, "26: the migrated board parses")
	check(int(migrated.get_value("meta", "version", 0)) == RunnerLeaderboard.SCHEMA_VERSION,
		"26: the board was rewritten as version %d, got %s"
			% [RunnerLeaderboard.SCHEMA_VERSION, migrated.get_value("meta", "version", 0)])
	var after := RunnerLeaderboard.load_entries(path)
	check(after.size() == 3, "26: the migration kept every run, got %d" % after.size())
	check(_has_run(after, "v1-a") and _has_run(after, "v1-b") and _has_run(after, "v2-new"),
		"26: the v1 runs survived the migration alongside the v2 one")
	check(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".bak"),
		"26: the migration leaves no .tmp or .bak behind")

	# Only a version *newer* than 2 is refused; that half is section 8's, this is the boundary.
	var future := "user://test_leaderboard_v3_%d.cfg" % (randi() % 1000000)
	temp_paths.append(future)
	var newer := ConfigFile.new()
	newer.set_value("meta", "version", RunnerLeaderboard.SCHEMA_VERSION + 1)
	newer.set_value("leaderboard", "entries", [])
	check(newer.save(future) == OK, "26: the version 3 fixture board was written")
	var refused := RunnerLeaderboard.submit(_entry("v3-run", 10), future)
	check(int(refused["error"]) == ERR_FILE_UNRECOGNIZED,
		"26: a version 3 board is refused, got error %s" % refused["error"])
	check(int(refused["rank"]) == 0, "26: a refused submit reports no rank")
	check(RunnerLeaderboard.rename("v3-run", "X", future) == ERR_FILE_UNRECOGNIZED,
		"26: rename refuses a version 3 board too")
	check(RunnerLeaderboard.SUPPORTED_VERSIONS == [1, 2],
		"26: exactly versions 1 and 2 are readable, got %s" % [RunnerLeaderboard.SUPPORTED_VERSIONS])

# --- 27. The camera stays on its rest pose except during a boss shot (systems §10.5) ---

func _test_camera_rest_pose() -> void:
	# @onready $Camera only assigns inside the tree, and _physics_process is what writes the pose.
	var game := _tree_game()
	var rig := Node3D.new()
	rig.set_script(camera_rig_script)
	var lens := Camera3D.new()
	lens.name = "Camera"
	rig.add_child(lens)
	root.add_child(rig)
	junk.append(rig)
	rig.set_physics_process(false)
	rig.setup(game)
	var rest: Vector3 = rig._base_rotation
	var stayed := true
	for _i in 30:
		rig._physics_process(TICK)
		if not rig.camera.rotation.is_equal_approx(rest):
			stayed = false
	check(stayed, "27: the camera left its rest pose with no boss shot, got %s vs %s"
		% [rig.camera.rotation, rest])
	rig.set_boss_cinematic(0.5, &"intro_full", Vector3(0.0, 2.0, -30.0))
	rig._physics_process(TICK)
	check(not rig.camera.rotation.is_equal_approx(rest),
		"27: a mid intro_full shot leaves the rest pose")
	for sample in [0.0, 1.0]:
		rig.set_boss_cinematic(sample, &"intro_full", Vector3(0.0, 2.0, -30.0))
		rig._physics_process(TICK)
		check(rig.camera.rotation.is_equal_approx(rest),
			"27: intro_full at p=%.1f returns to the rest pose, got %s" % [sample, rig.camera.rotation])
	rig.set_boss_cinematic(0.5, &"", Vector3.ZERO)
	rig._physics_process(TICK)
	check(rig.camera.rotation.is_equal_approx(rest),
		"27: an empty boss mode stays on the rest pose, got %s" % rig.camera.rotation)

# --- 28. The boss entrance: boss_intro opens the fight, boss_spawned follows (contract §11.4) ---

func _test_boss_intro() -> void:
	var intro_seconds := 1.5
	var rig := _boss_rig({"boss_intro_seconds": intro_seconds, "boss_outro_seconds": 0.0})
	var arena: Node3D = rig["arena"]
	var events: Dictionary = rig["events"]
	arena.start(1)
	# Contract 2.6 §11.14: the intro cinematic opens between the card and the boss.
	check(events["boss_log"] == [&"intro", &"cinematic", &"spawned"],
		"28: the entrance card and its cinematic precede the boss, got %s" % [events["boss_log"]])
	check(events["boss_cinematic"].size() == 1 and StringName(events["boss_cinematic"][0][1]) == &"intro_full"
		and is_equal_approx(float(events["boss_cinematic"][0][2]), intro_seconds),
		"28: a first meeting plays the full %.1f s intro, got %s" % [intro_seconds, events["boss_cinematic"]])
	check(events["boss_intro"].size() == 1, "28: boss_intro fires once per fight, got %d"
		% events["boss_intro"].size())
	check(StringName(events["boss_intro"][0][0]) == &"flaky_test_swarm"
		and String(events["boss_intro"][0][1]) == "Flaky Test Swarm",
		"28: boss_intro names the boss, got %s" % [events["boss_intro"][0]])
	check(is_equal_approx(float(events["boss_intro"][0][2]), intro_seconds),
		"28: boss_intro carries boss_intro_seconds, got %.3f" % float(events["boss_intro"][0][2]))

	# Nothing is thrown and nothing is dropped while the card is up (contract §11.4).
	for i in _ticks(intro_seconds - 0.1):
		arena.tick(TICK)
	check(events["boss_attack_telegraph"].is_empty(),
		"28: the intro telegraphed %d attack(s)" % events["boss_attack_telegraph"].size())
	check(int(arena.tool_count()) == 0, "28: the intro dropped %d tool(s)" % int(arena.tool_count()))
	check(events["boss_intro"].size() == 1, "28: the intro is announced once, not per tick")

	# And once it is over the fight runs: the first beat is telegraphed on the authored interval.
	for i in _ticks(2.2):
		arena.tick(TICK)
	check(not events["boss_attack_telegraph"].is_empty(),
		"28: the fight never opened fire after the %.1f s intro" % intro_seconds)
	check(events["boss_log"] == [&"intro", &"cinematic", &"spawned", &"cinematic_ended"],
		"28: no entrance signal repeats and the intro ends once, got %s" % [events["boss_log"]])
	_free_rig(rig)

# --- 30. Boss signature attacks: beat data, shot motion, live encounter (contract 2.4 §11.6) ---

## The data half is pure (boss_attacks.gd off the shipped defs and config); the live half runs the
## real arena and real projectiles, ticked by hand, so the commit signal, the split, the gap shift,
## the sweep and the falling slab are seen doing on the node what the data says they do.
func _test_boss_signatures() -> void:
	var c := base_config
	var eps := 0.0005
	# Flaky commit timing, at cycle 0 and at the cycle 4 floors.
	for stage in [1, 13]:
		var def := BossDefs.fight_def(stage, c)
		var flaky := _beat_with(def, 1, BossAttacks.SIG_FLAKY)
		var options := BossAttacks.beat_options(flaky, def, 1, c)
		check(options.size() == 6, "30: a single-lane flaky beat has 3 pairs x 2 commits, got %d" % options.size())
		for option in options:
			var attack: Dictionary = option[0]
			var commit := float(attack["commit_at"])
			var candidates: Array = attack["candidates"]
			check(is_equal_approx(commit, float(c.boss_flaky_candidate_seconds)),
				"30: stage %d flaky commits %.3f s in, expected boss_flaky_candidate_seconds" % [stage, commit])
			check(float(attack["telegraph"]) - commit >= float(c.boss_commit_min) - eps,
				"30: stage %d flaky commits only %.3f s before fire, need boss_commit_min %.2f"
					% [stage, float(attack["telegraph"]) - commit, float(c.boss_commit_min)])
			check(is_equal_approx(float(attack["telegraph"]) - commit,
				maxf(BossDefs.telegraph_for(def, 1), float(c.boss_commit_min))),
				"30: the commit window is the phase telegraph, floored at boss_commit_min")
			check(candidates.size() == 2 and int(candidates[0]) != int(candidates[1])
				and candidates.has(int(attack["mask"]))
				and int(attack["telegraph_mask"]) == (int(candidates[0]) | int(candidates[1])),
				"30: the telegraph shows both candidates and fires one of them, got %s" % [attack])
			check(int(attack["impact_mask"]) == int(attack["mask"]),
				"30: a flaky orb hits the lane it committed to")
	var adjacent := BossAttacks.beat_options(_beat_with(BossDefs.fight_def(1, c), 2, BossAttacks.SIG_FLAKY),
		BossDefs.fight_def(1, c), 2, c)
	check(adjacent.size() == 2 and int(adjacent[0][0]["telegraph_mask"]) == BossDefs.LANE_ALL,
		"30: an adjacent-pair flaky alternates the two pairs, got %d option(s)" % adjacent.size())

	# Scatter: one orb down the middle, two outer halves after the split.
	var swarm := BossDefs.fight_def(1, c)
	var scatter: Dictionary = BossAttacks.beat_options(_beat_with(swarm, 3, BossAttacks.SIG_SCATTER), swarm, 3, c)[0][0]
	var halves: Array = scatter["shots"]
	var split := float(scatter["split_at"])
	check(halves.size() == 2, "30: the scatter orb fires two halves, got %d" % halves.size())
	check(is_equal_approx(BossAttacks.z_at(halves[0], split), -float(c.boss_scatter_split_distance)),
		"30: the split happens at track z %.2f, expected -boss_scatter_split_distance"
			% BossAttacks.z_at(halves[0], split))
	var xs: Array[float] = []
	for half in halves:
		check(BossAttacks.lane_mask_at(half, 0.0, c) == BossDefs.LANE_MIDDLE
			and is_zero_approx(BossAttacks.x_at(half, split - 0.01)),
			"30: before the split both halves fly the middle lane")
		xs.append(BossAttacks.x_at(half, split + BossAttacks.SPLIT_SECONDS))
	xs.sort()
	check(is_equal_approx(xs[0], -float(c.lane_width)) and is_equal_approx(xs[1], float(c.lane_width)),
		"30: after the split the halves sit on the outer lanes, got %s" % [xs])
	check(int(scatter["impact_mask"]) == BossDefs.LANE_OUTER and int(scatter["telegraph_mask"]) == BossDefs.LANE_MIDDLE,
		"30: the scatter telegraphs the middle and hits the outer lanes, got %s / %s"
			% [scatter["telegraph_mask"], scatter["impact_mask"]])
	check(split + BossAttacks.SPLIT_SECONDS < BossAttacks.pass_window(halves[0]).x,
		"30: the split is over before the halves reach the player")

	# Legacy wall: exactly one gap, shifting once to the next lane.
	var monolith := BossDefs.fight_def(3, c)
	var walls := BossAttacks.beat_options(_beat_with(monolith, 1, BossAttacks.SIG_LEGACY_WALL), monolith, 1, c)
	check(walls.size() == 4, "30: the gap can shift 0->1, 1->0, 1->2, 2->1, got %d option(s)" % walls.size())
	for option in walls:
		var wall: Dictionary = option[0]
		var from := int(wall["gap_from"])
		var to := int(wall["gap_to"])
		var shift := float(wall["shift_at"])
		var at_fire := 0
		var at_impact := 0
		var movers := 0
		for slab in wall["shots"]:
			at_fire |= BossAttacks.lane_mask_at(slab, 0.0, c)
			at_impact |= BossAttacks.impact_mask(slab, c)
			if not is_equal_approx(BossAttacks.x_at(slab, 0.0), BossAttacks.x_at(slab, 99.0)):
				movers += 1
				check(BossAttacks.lane_mask_at(slab, shift - 0.01, c) == 1 << to
					and BossAttacks.lane_mask_at(slab, shift + BossAttacks.SHIFT_SECONDS, c) == 1 << from,
					"30: the moving slab leaves the new gap for the old one at the shift")
		check(absi(from - to) == 1 and movers == 1, "30: one slab moves one lane, got %d mover(s)" % movers)
		check(at_fire == BossDefs.LANE_ALL & ~(1 << from) and at_impact == BossDefs.LANE_ALL & ~(1 << to),
			"30: the wall leaves gap %d at fire and gap %d at impact, got %d / %d" % [from, to, at_fire, at_impact])
		check(int(wall["telegraph_mask"]) == at_fire and shift > 0.0
			and shift + BossAttacks.SHIFT_SECONDS < BossAttacks.pass_window(wall["shots"][0]).x,
			"30: the wall telegraphs its first gap and shifts mid-flight")
		check(not bool(wall["jumpable"]) and not bool(wall["rollable"]),
			"30: the legacy wall is answered by the gap, never by the body")

	# Rebase sweep: outer lane to outer lane, low enough to jump.
	var hydra := BossDefs.fight_def(2, c)
	var sweeps := BossAttacks.beat_options(_beat_with(hydra, 3, BossAttacks.SIG_SWEEP), hydra, 3, c)
	check(sweeps.size() == 2, "30: the sweep runs both ways, got %d option(s)" % sweeps.size())
	for option in sweeps:
		var sweep: Dictionary = option[0]
		var shot: Dictionary = sweep["shots"][0]
		var end := float(sweep["sweep_end"])
		var from_x := c.lane_x(int(sweep["sweep_from"]))
		var to_x := c.lane_x(int(sweep["sweep_to"]))
		check(is_equal_approx(BossAttacks.x_at(shot, 0.0), from_x) and is_equal_approx(BossAttacks.x_at(shot, end), to_x)
			and is_equal_approx(BossAttacks.x_at(shot, end * 0.5), (from_x + to_x) * 0.5),
			"30: the sweep slides %.1f -> %.1f linearly over %.3f s" % [from_x, to_x, end])
		check(int(sweep["impact_mask"]) == 1 << int(sweep["sweep_to"]) and int(sweep["telegraph_mask"]) == BossDefs.LANE_ALL,
			"30: the sweep telegraphs its whole path and hits its end lane")
		check(bool(sweep["jumpable"]) and end < BossAttacks.pass_window(shot).x,
			"30: the sweep stays low (jumpable) and has finished sliding before it arrives")

	# Debris: shadows in one or two lanes, slabs landing before they arrive.
	var drops := BossAttacks.beat_options(_beat_with(monolith, 2, BossAttacks.SIG_DEBRIS), monolith, 2, c)
	check(drops.size() == 5, "30: debris falls in any one lane or adjacent pair, got %d option(s)" % drops.size())
	for option in drops:
		var drop: Dictionary = option[0]
		var land := float(drop["land_at"])
		var lanes := 0
		for slab in drop["shots"]:
			lanes |= BossAttacks.lane_mask_at(slab, 0.0, c)
			check(is_equal_approx(BossAttacks.y_range_at(slab, 0.0).x, float(drop["drop_height"]))
				and is_equal_approx(BossAttacks.y_range_at(slab, land).x, 0.0)
				and BossAttacks.y_range_at(slab, land * 0.5).x > 0.0,
				"30: a slab starts drop_height up and is on the floor at land_at")
			check(land < BossAttacks.pass_window(slab).x and BossAttacks.lane_mask_at(slab, land, c)
				== BossAttacks.lane_mask_at(slab, 0.0, c), "30: a slab falls straight down onto its shadow")
		check(lanes == int(drop["mask"]) and int(drop["telegraph_mask"]) == lanes and int(drop["impact_mask"]) == lanes,
			"30: the shadows are the lanes the slabs land in, got %d / %d" % [lanes, int(drop["telegraph_mask"])])
		check(bool(drop["jumpable"]), "30: a landed slab is jumpable")

	# Branching and force push.
	var volley: Array = BossAttacks.beat_options(_beat_with(hydra, 1, BossAttacks.SIG_BRANCHING), hydra, 1, c)[0]
	check(volley.size() == 2 and int(volley[0]["impact_mask"]) != int(volley[1]["impact_mask"])
		and is_equal_approx(float(volley[1]["telegraph"]) - float(volley[0]["telegraph"]), 0.3),
		"30: a branching volley is two heads on distinct lanes, 0.3 s apart, got %s" % [volley])
	var push: Dictionary = BossAttacks.beat_options(_beat_with(hydra, 2, BossAttacks.SIG_FORCE_PUSH), hydra, 2, c)[0][0]
	check(is_equal_approx(float(push["speed"]), minf(float(hydra["projectile_speed"]) * 1.3, float(c.boss_signature_speed_max)))
		and is_equal_approx(float(push["telegraph"]), BossDefs.telegraph_for(hydra, 2) * 1.6),
		"30: the force push is 1.3x fast and telegraphed 1.6x long, got %.2f m/s / %.3f s"
			% [float(push["speed"]), float(push["telegraph"])])

	# Plain beats resolve exactly as before, and a fixed beat never touches the fight RNG.
	var plain := BossAttacks.beat_options({"variant": &"orb", "lanes": BossDefs.LANES_RANDOM_SINGLE}, swarm, 1, c)
	check(plain.size() == 3 and int(plain[1][0]["impact_mask"]) == BossDefs.LANE_MIDDLE
		and (plain[1][0]["shots"] as Array).size() == 1
		and (plain[1][0]["shots"][0]["x_keys"] as PackedVector2Array).size() == 1,
		"30: a plain orb beat is one straight shot per lane option")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var state := rng.state
	var fixed_beat := {"variant": &"low", "lanes": BossDefs.LANES_FIXED, "mask": BossDefs.LANE_ALL}
	var fixed := BossAttacks.beat_options(fixed_beat, swarm, 3, c)
	check(BossAttacks.pick_option(fixed, 0, rng, BossAttacks.draws_random(fixed_beat, fixed)) == 0 and rng.state == state,
		"30: a fixed beat is drawn without a roll, so the v2.0 lane stream replays")

	_test_boss_signatures_live()
	_test_boss_signatures_bot()

## The first beat of `phase` carrying `signature`.
func _beat_with(def: Dictionary, phase: int, signature: StringName) -> Dictionary:
	for beat in BossDefs.pattern_for(def, phase):
		if StringName((beat as Dictionary).get("signature", &"")) == signature:
			return beat
	check(false, "30: %s phase %d has no %s beat" % [def.get("kind", &""), phase, signature])
	return {}

## The real arena queuing and firing signature beats.
func _test_boss_signatures_live() -> void:
	var rig := _boss_rig({"boss_intro_seconds": 0.0, "boss_outro_seconds": 0.0, "boss_timeout_seconds": 999.0})
	var game: Node3D = rig["game"]
	var arena: Node3D = rig["arena"]
	var log: Array = []
	game.boss_attack_planned.connect(func(attack: Dictionary) -> void:
		log.append([&"planned", attack]))
	game.boss_attack_telegraph.connect(func(mask: int, kind: StringName, seconds: float) -> void:
		log.append([&"telegraph", mask, kind, seconds]))
	game.boss_attack_committed.connect(func(mask: int, kind: StringName, seconds: float) -> void:
		log.append([&"committed", mask, kind, seconds, float(arena._fight_timer)]))
	var fired: Array = []
	game.boss_projectile_fired.connect(func(projectile: Area3D, mask: int, kind: StringName, speed: float) -> void:
		fired.append([projectile, mask, kind, speed]))
	arena.start(1)
	# Beat 2 of the Swarm's phase 1 is the flaky one.
	arena._beat = 1
	arena._attack_timer = 0.0
	arena.tick(TICK)
	check(log.size() == 2 and log[0][0] == &"planned" and log[1][0] == &"telegraph",
		"30: boss_attack_planned goes out right before its telegraph, got %s" % [log.map(func(e): return e[0])])
	if log.size() < 2:
		_free_rig(rig)
		return
	var attack: Dictionary = log[0][1]
	var queued_at := float(arena._fight_timer)
	check(StringName(attack["signature"]) == BossAttacks.SIG_FLAKY and int(log[1][1]) == int(attack["telegraph_mask"])
		and is_equal_approx(float(log[1][3]), float(attack["telegraph"])),
		"30: the telegraph carries the candidate mask and the whole flaky telegraph")
	var row: Dictionary = arena.get_boss_info()["pending_attacks"][0]
	check(not bool(row["committed"]) and int(row["lane_mask"]) == int(attack["telegraph_mask"]),
		"30: pending_attacks shows the uncommitted candidates, got %s" % [row])
	var guard := 0
	while fired.is_empty() and guard < 400:
		arena.tick(TICK)
		guard += 1
	var commits: Array = log.filter(func(e): return e[0] == &"committed")
	check(commits.size() == 1 and int(commits[0][1]) == int(attack["mask"]) and StringName(commits[0][2]) == &"orb",
		"30: the flaky telegraph commits once, to its fire mask, got %s" % [commits])
	if commits.size() == 1:
		var commit_time := float(commits[0][4]) - queued_at
		check(absf(commit_time - float(attack["commit_at"])) <= TICK + eps_tick(),
			"30: the commit lands %.3f s after the telegraph, expected %.3f" % [commit_time, float(attack["commit_at"])])
		check(absf(float(commits[0][3]) - (float(attack["telegraph"]) - float(attack["commit_at"]))) <= TICK + eps_tick(),
			"30: boss_attack_committed carries the %.3f s left before fire, got %.3f"
				% [float(attack["telegraph"]) - float(attack["commit_at"]), float(commits[0][3])])
	check(fired.size() == 1 and int(fired[0][1]) == int(attack["mask"]),
		"30: the flaky orb fires on the committed lane, got %s" % [fired])
	if fired.size() == 1:
		var orb: Area3D = fired[0][0]
		check(StringName(orb.get(&"boss_kind")) == &"flaky_test_swarm" and StringName(orb.get(&"signature")) == BossAttacks.SIG_FLAKY
			and (orb.get(&"motion") as Dictionary).is_empty(),
			"30: the shot carries its boss kind and signature, and a straight shot no motion")

	# Scatter: two halves spawned in the middle, on the outer lanes after the split.
	arena._clear_projectiles()
	fired.clear()
	arena.phase = 3
	arena._beat = 2
	arena._attack_timer = 0.0
	arena.tick(TICK)
	guard = 0
	while fired.is_empty() and guard < 400:
		arena.tick(TICK)
		guard += 1
	check(fired.size() == 2 and StringName(fired[0][2]) == &"scatter", "30: the scatter fires two halves, got %s" % [fired])
	if fired.size() == 2:
		check(arena._blocked_lane_mask() == BossDefs.LANE_OUTER,
			"30: the tool-lane rule blocks where the halves will hit (outer), got %d" % arena._blocked_lane_mask())
		var half: Area3D = fired[0][0]
		var other: Area3D = fired[1][0]
		check(half.lanes_mask() == BossDefs.LANE_MIDDLE and half.lane_mask_at(0.0) == BossDefs.LANE_MIDDLE
			and half.impact_lane_mask() | other.impact_lane_mask() == BossDefs.LANE_OUTER,
			"30: a scatter half starts in the middle and is planned against the outer lanes")
		# The bot's live-shot fallback reads the same impact lanes off the node.
		var reader: Node = autopilot_script.new()
		junk.append(reader)
		reader.setup(game)
		var live_slices: Array = reader.slices_for([half], 24.0, 0.0)
		check(live_slices.size() == 1 and int(live_slices[0]["blocked"]) == half.impact_lane_mask(),
			"30: a live split shot is sliced on its impact lanes, got %s" % [live_slices])
		# The halves' own motion says when the split is over: the last x key.
		var keys: PackedVector2Array = (half.get(&"motion") as Dictionary).get("x_keys", PackedVector2Array())
		check(keys.size() == 3, "30: a scatter half carries its split in its motion, got %s" % [keys])
		_fly([half, other], (keys[keys.size() - 1].x if not keys.is_empty() else 0.0) + 0.05)
		var outer := [half.position.x, other.position.x]
		outer.sort()
		check(is_equal_approx(outer[0], -2.0) and is_equal_approx(outer[1], 2.0),
			"30: after the split the live halves are on x -2 / +2, got %s" % [outer])
		check(half.lanes_mask() | other.lanes_mask() == BossDefs.LANE_OUTER,
			"30: the live hitboxes moved with them, got %d" % (half.lanes_mask() | other.lanes_mask()))
		# The fallback visual draws the base look for a variant it does not know.
		if is_instance_valid(half.visual) and &"variant" in half.visual and not (&"signature_variants" in half.visual):
			check(StringName(half.visual.get(&"variant")) == &"orb",
				"30: a scatter half is drawn with the orb look until a visual opts in, got %s" % half.visual.get(&"variant"))
	_free_rig(rig)

	# Legacy wall and debris on the Monolith.
	var mono_rig := _boss_rig({"boss_intro_seconds": 0.0, "boss_outro_seconds": 0.0, "boss_timeout_seconds": 999.0})
	var mono_game: Node3D = mono_rig["game"]
	var mono: Node3D = mono_rig["arena"]
	var shots: Array = []
	var planned: Array = []
	mono_game.boss_projectile_fired.connect(func(projectile: Area3D, _m: int, _k: StringName, _s: float) -> void:
		shots.append(projectile))
	mono_game.boss_attack_planned.connect(func(attack: Dictionary) -> void:
		planned.append(attack))
	mono.start(3)
	mono._beat = 1
	mono._attack_timer = 0.0
	mono.tick(TICK)
	guard = 0
	while shots.is_empty() and guard < 400:
		mono.tick(TICK)
		guard += 1
	check(shots.size() == 2 and not planned.is_empty(), "30: the legacy wall fires two slabs, got %d" % shots.size())
	if shots.size() == 2 and not planned.is_empty():
		var wall: Dictionary = planned[planned.size() - 1]
		var mask_at_fire := int(shots[0].lanes_mask()) | int(shots[1].lanes_mask())
		_fly(shots, float(wall["shift_at"]) + BossAttacks.SHIFT_SECONDS + 0.05)
		var mask_after := int(shots[0].lanes_mask()) | int(shots[1].lanes_mask())
		check(mask_at_fire == BossDefs.LANE_ALL & ~(1 << int(wall["gap_from"]))
			and mask_after == BossDefs.LANE_ALL & ~(1 << int(wall["gap_to"])),
			"30: the live wall's gap moved %d -> %d, got masks %d -> %d"
				% [int(wall["gap_from"]), int(wall["gap_to"]), mask_at_fire, mask_after])
	mono._clear_projectiles()
	shots.clear()
	mono.phase = 2
	mono._beat = 1
	mono._attack_timer = 0.0
	mono.tick(TICK)
	guard = 0
	while shots.is_empty() and guard < 400:
		mono.tick(TICK)
		guard += 1
	check(not shots.is_empty() and StringName(shots[0].variant) == &"debris", "30: the Monolith drops debris in phase 2")
	if not shots.is_empty():
		var slab: Area3D = shots[0]
		var drop: Dictionary = slab.get(&"motion")
		check(slab.position.y > 1.0 and slab.get_world_aabb().position.y > 1.0,
			"30: a slab is fired high above its shadow, got y %.2f" % slab.position.y)
		_fly(shots, float(drop.get("land_at", 0.0)) + 0.02)
		check(is_zero_approx(slab.position.y) and is_equal_approx(slab.get_world_aabb().position.y, 0.0),
			"30: a slab has landed on its shadow by land_at, got y %.2f" % slab.position.y)
	_free_rig(mono_rig)

func eps_tick() -> float:
	return 0.0005

## Advance hand-ticked projectiles by `seconds` on their own motion.
func _fly(projectiles: Array, seconds: float) -> void:
	var steps := int(ceilf(seconds / TICK))
	for i in steps:
		for node in projectiles:
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node._physics_process(TICK)

## The planner half: a flaky telegraph is planned against both candidates until it commits, and a
## branching volley is answered with the one lane both heads leave free.
func _test_boss_signatures_bot() -> void:
	var game := _make_game()
	game.speed = 24.0
	var bot: Node = autopilot_script.new()
	junk.append(bot)
	bot.setup(game)
	var c: RunConfig = game.config
	var swarm := BossDefs.fight_def(1, c)
	var flaky: Dictionary = BossAttacks.beat_options(_beat_with(swarm, 1, BossAttacks.SIG_FLAKY), swarm, 1, c)[0][0]
	game.boss_attack_planned.emit(flaky)
	game.boss_attack_telegraph.emit(int(flaky["telegraph_mask"]), &"orb", float(flaky["telegraph"]))
	var pending: Array = bot.pending_attacks()
	check(pending.size() == 1 and int(pending[0]["mask"]) == int(flaky["telegraph_mask"]) and not bool(pending[0]["committed"]),
		"30: an uncommitted flaky attack blocks both candidates, got %s" % [pending])
	check(is_equal_approx(float(pending[0]["arrival"]), float(flaky["enter"])),
		"30: the planner's arrival is the motion API's pass window")
	game.boss_attack_committed.emit(int(flaky["mask"]), &"orb", float(flaky["telegraph"]) - float(flaky["commit_at"]))
	check(int(pending[0]["mask"]) == int(flaky["mask"]) and bool(pending[0]["committed"]),
		"30: the commit narrows the plan to the committed lane, got %s" % [pending[0]])
	bot.reset()
	var hydra := BossDefs.fight_def(2, c)
	for option in BossAttacks.beat_options(_beat_with(hydra, 1, BossAttacks.SIG_BRANCHING), hydra, 1, c):
		var heads: Array = option
		bot.reset()
		for head in heads:
			game.boss_attack_planned.emit(head)
			game.boss_attack_telegraph.emit(int(head["telegraph_mask"]), &"orb", float(head["telegraph"]))
		var free_lane := -1
		var blocked := 0
		for head in heads:
			blocked |= int(head["impact_mask"])
		for lane in 3:
			if (blocked & (1 << lane)) == 0:
				free_lane = lane
		var group: Array = bot.pending_attacks().duplicate()
		for lane in 3:
			if lane == free_lane:
				continue
			var plan: Dictionary = bot.plan_group(group, lane)
			check(StringName(plan["action"]) == bot.ACTION_LANE and int(plan["lane"]) == free_lane,
				"30: from lane %d the volley %d is answered in lane %d, got %s" % [lane, blocked, free_lane, plan])

# --- 29. The stage-entrance window: nothing blocking while the banner is up (contract §11.1) ---

## The `STAGE n` banner covers the lanes for a couple of seconds after every `stage_started`, so a
## corridor that hands the player a hazard across it costs them a run they could not see coming.
## Six things are pinned here. The StageManager opens the window *before* it switches placement
## back on, for every stage. A frontier left stale by a drained corridor is clamped off the
## player's feet instead of parking the first chunk underfoot. Every chunk laid down while the
## window is open is hazard-free or too far out to arrive before the window and the reaction time
## have both run down — and the corridor is still filled to the spawn horizon, not left empty. The
## window burns run time only, never wall time through a pause. The promise survives a speed
## change made after it was given: Nitro mid-window re-opens the question every tick. And the
## rejected draws the substitution leaves in its wake are gone the instant they are rejected.
func _test_stage_banner_window() -> void:
	_check_banner_window_gate()
	_check_banner_window_placement()
	_check_banner_window_pause()
	_check_banner_window_sweep()
	_check_banner_window_speed_up()
	_check_banner_window_discards()

## The StageManager end: every stage entry asks for a window, with the configured length, before
## the fill that follows it.
func _check_banner_window_gate() -> void:
	var rig := _stage_rig({
		"stage_base_distance": 40.0,
		"stage_distance_step": 20.0,
		"stage_drain_distance": 15.0,
		"stage_drain_timeout": 0.2,
		"stage_clear_seconds": 0.2,
	})
	var game: Node3D = rig["game"]
	var stage: Node = rig["stage"]
	var spawner: Node = rig["spawner"]
	var drivers: Array = [rig["speed"], stage]
	var window := float(game.config.stage_banner_clear_seconds)
	stage.begin()
	check(spawner.clear_road_calls.size() == 1,
		"29: stage 1 opened %d clear-road window(s), expected exactly one"
			% spawner.clear_road_calls.size())
	check(not spawner.clear_road_calls.is_empty()
		and is_equal_approx(float(spawner.clear_road_calls[0]), window),
		"29: the window asked for %s s, expected stage_banner_clear_seconds %.2f"
			% [spawner.clear_road_calls, window])
	check(spawner.call_log == [&"clear_road", &"spawning_on"],
		"29: the window has to be open before the corridor is topped up, got %s" % [spawner.call_log])
	var guard := 0
	while int(stage.stage_index) < 2 and guard < _ticks(40.0):
		_tick_stage(drivers, game, 1)
		guard += 1
	check(int(stage.stage_index) == 2,
		"29: the rig never reached stage 2 (stage %d, phase %s)" % [int(stage.stage_index), stage.phase])
	check(spawner.clear_road_calls.size() == 2,
		"29: every stage entry opens a window, got %d across two stages" % spawner.clear_road_calls.size())
	check(spawner.call_log.slice(spawner.call_log.size() - 2) == [&"clear_road", &"spawning_on"],
		"29: stage 2 opened its window before its first fill, got %s" % [spawner.call_log])
	_free_rig(rig)

## The spawner end, on the corridor a stage seam actually leaves behind: no chunks and a frontier
## that scrolled past the player while the boss and the clear card ran.
func _check_banner_window_placement() -> void:
	for stale in [8.0, -3.0]:
		var rig := _spawner_rig({})
		if rig.is_empty():
			return
		var game: Node3D = rig["game"]
		var spawner: Node = rig["spawner"]
		var tag := "29: stale frontier %+.0f m" % stale
		var reaction := float(game.config.stage_banner_reaction_seconds)
		var window := float(game.config.stage_banner_clear_seconds)
		spawner.frontier_z = stale
		spawner.begin_clear_road(window)
		check(float(spawner.frontier_z) <= -6.0 + 0.001,
			"%s: the frontier was left at %.2f, expected at least 6 m ahead of the player"
				% [tag, float(spawner.frontier_z)])
		spawner.set_spawning(true)
		var chunks: Array[Node3D] = spawner.get_active_chunks()
		check(not chunks.is_empty(), "%s: the window left the corridor empty" % tag)
		if chunks.is_empty():
			_free_rig(rig)
			return
		check(float(chunks[0].global_position.z) <= -6.0 + 0.001,
			"%s: the first chunk entered at z %.2f, expected at most -6" % [tag, float(chunks[0].global_position.z)])
		check(float(spawner.frontier_z) <= float(game.config.spawn_horizon_z)
			or chunks.size() >= int(game.config.max_active_chunks),
			"%s: the corridor stopped %d chunk(s) short at frontier %.1f, the horizon is %.1f"
				% [tag, chunks.size(), float(spawner.frontier_z), float(game.config.spawn_horizon_z)])

		# The invariant, tick by tick: while the window is open the soonest hazard in the corridor
		# is always at least the remaining window plus the reaction time away. Both sides fall at
		# one second per second, so a chunk that was admitted stays admissible, and the moment the
		# window shuts the margin is exactly the reaction the contract promises.
		var violations := 0
		var worst := INF
		var ticks_run := 0
		while float(spawner.clear_road_remaining()) > 0.0 and ticks_run < _ticks(10.0):
			_tick([spawner], 1)
			ticks_run += 1
			if float(spawner.clear_road_remaining()) <= 0.0:
				break
			var margin := _nearest_arrival(spawner, game) \
				- float(spawner.clear_road_remaining()) - reaction
			worst = minf(worst, margin)
			if margin < -0.001:
				violations += 1
		check(violations == 0,
			"%s: %d tick(s) had a hazard inside the window, worst by %.3f s" % [tag, violations, worst])
		check(ticks_run > 0 and ticks_run <= _ticks(window) + 2,
			"%s: the window ran %d ticks, expected about %d" % [tag, ticks_run, _ticks(window)])
		var closing := _nearest_arrival(spawner, game)
		check(closing >= reaction - 0.001,
			"%s: the window shut with the nearest hazard %.3f s out, the player is owed %.2f"
				% [tag, closing, reaction])
		check(closing < INF,
			"%s: the window shut on a corridor with no hazard in it at all — the pacing went slack" % tag)
		# ...and the corridor goes back to normal chunks as soon as it may.
		_tick([spawner], _ticks(6.0))
		check(_nearest_arrival(spawner, game) < INF,
			"%s: six seconds past the window the corridor still carries no hazard" % tag)
		_free_rig(rig)

## The window is run time, not wall time: a paused game must not burn it.
func _check_banner_window_pause() -> void:
	var rig := _spawner_rig({})
	if rig.is_empty():
		return
	var game: Node3D = rig["game"]
	var spawner: Node = rig["spawner"]
	spawner.begin_clear_road(2.0)
	var opened := float(spawner.clear_road_remaining())
	check(is_equal_approx(opened, 2.0), "29: begin_clear_road(2.0) opened %.3f s" % opened)
	game.paused = true
	_tick([spawner], _ticks(1.0))
	check(is_equal_approx(float(spawner.clear_road_remaining()), opened),
		"29: a paused second burned %.3f s of the window" % (opened - float(spawner.clear_road_remaining())))
	game.paused = false
	_tick([spawner], _ticks(1.0))
	var left := float(spawner.clear_road_remaining())
	check(left > 0.0 and is_equal_approx(left, 1.0),
		"29: one unpaused second should leave 1.0 s of the window, got %.3f" % left)
	# A second call while one is open keeps the longer of the two rather than cutting it short.
	spawner.begin_clear_road(0.25)
	check(is_equal_approx(float(spawner.clear_road_remaining()), left),
		"29: a shorter re-entry shortened the window to %.3f s" % float(spawner.clear_road_remaining()))
	_tick([spawner], _ticks(2.0))
	check(is_zero_approx(float(spawner.clear_road_remaining())),
		"29: the window never closed, %.3f s left" % float(spawner.clear_road_remaining()))
	_free_rig(rig)

## The sweep is housekeeping, not Auto-Fix: a hazard already inbound when the window opens is taken
## out silently — no hazard_cleared, no hazards_blasted, no bonus, no score and no dodge counted.
func _check_banner_window_sweep() -> void:
	var rig := _spawner_rig({})
	if rig.is_empty():
		return
	var game: Node3D = rig["game"]
	var spawner: Node = rig["spawner"]
	var score: Node = score_manager_script.new()
	junk.append(score)
	game.score_manager = score
	score.setup(game)
	var events := _watch(game)
	var cleared_signals := 0
	game.hazard_cleared.connect(func(_hazard: Area3D) -> void:
		cleared_signals += 1)
	var reach := float(game.speed) * (float(game.config.stage_banner_clear_seconds)
		+ float(game.config.stage_banner_reaction_seconds))
	var inbound := _hazard(&"pr_backlog_low")
	inbound.add_to_group(&"runner_hazards")
	inbound.position = Vector3(0.0, 0.0, -reach * 0.5)
	var beyond := _hazard(&"pr_backlog_low")
	beyond.add_to_group(&"runner_hazards")
	beyond.position = Vector3(0.0, 0.0, -reach - 20.0)
	var score_before := int(game.score)
	var dodged_before := int(game.hazards_dodged)
	spawner.begin_clear_road(float(game.config.stage_banner_clear_seconds))
	check(int(inbound.cleared) == 1,
		"29: the sweep cleared the inbound hazard %d time(s), expected once" % int(inbound.cleared))
	check(int(beyond.cleared) == 0,
		"29: the sweep reached %.1f m out, past the %.1f m the window covers"
			% [absf(beyond.position.z), reach])
	check(cleared_signals == 0, "29: the sweep emitted hazard_cleared %d time(s)" % cleared_signals)
	check(events["hazards_blasted"].is_empty(),
		"29: the sweep reported a blast: %s" % [events["hazards_blasted"]])
	check(events["bonus_awarded"].is_empty(), "29: the sweep paid a bonus: %s" % [events["bonus_awarded"]])
	check(int(game.score) == score_before and int(game.hazards_dodged) == dodged_before,
		"29: the sweep moved the score (%d -> %d) or the dodge count (%d -> %d)"
			% [score_before, int(game.score), dodged_before, int(game.hazards_dodged)])
	_free_rig(rig)

## The promise has to hold for the whole window, not only for the tick it was made on. Admission is
## measured at the speed of the moment, so Nitro (x1.25) or the difficulty ramp landing mid-window
## shortens every arrival already in the corridor. The tick after the speed rises has to notice and
## sweep what it just pulled inside the window — still silently, and still only that far out.
func _check_banner_window_speed_up() -> void:
	var rig := _spawner_rig({})
	if rig.is_empty():
		return
	var game: Node3D = rig["game"]
	var spawner: Node = rig["spawner"]
	var events := _watch(game)
	var cleared_signals := 0
	game.hazard_cleared.connect(func(_hazard: Area3D) -> void:
		cleared_signals += 1)
	var window := float(game.config.stage_banner_clear_seconds)
	var reaction := float(game.config.stage_banner_reaction_seconds)
	var base_v := float(game.speed)
	# Nitro at the top of the ramp, the fastest the corridor legitimately closes (contract §7).
	var nitro_v := minf(float(game.config.max_speed) * float(game.config.nitro_speed_multiplier),
		float(game.config.nitro_speed_cap))
	check(nitro_v > base_v,
		"29: the rig needs a speed the corridor can actually rise to, got %.1f over %.1f"
			% [nitro_v, base_v])
	# One metre beyond what the window reaches at the base speed: admissible when the window opens,
	# by a margin a single Nitro erases...
	var thin := _hazard(&"pr_backlog_low")
	thin.add_to_group(&"runner_hazards")
	thin.position = Vector3(0.0, 0.0, -(base_v * (window + reaction) + 1.0))
	# ...and one far enough out to still clear the window at Nitro speed.
	var distant := _hazard(&"pr_backlog_low")
	distant.add_to_group(&"runner_hazards")
	distant.position = Vector3(0.0, 0.0, -(nitro_v * (window + reaction) + 10.0))
	var score_before := int(game.score)
	var dodged_before := int(game.hazards_dodged)
	spawner.begin_clear_road(window)
	check(int(thin.cleared) == 0 and int(distant.cleared) == 0,
		"29: the entrance sweep at %.1f m/s took a hazard it could not reach (%d / %d cleared)"
			% [base_v, int(thin.cleared), int(distant.cleared)])
	# Nitro lands while the banner is still up.
	game.speed = nitro_v
	_tick([spawner], 1)
	var left := float(spawner.clear_road_remaining())
	check(left > 0.0, "29: the window closed on the first tick, %.3f s left" % left)
	check(int(thin.cleared) == 1,
		"29: the speed increase pulled a hazard %.1f m out inside the %.1f m the window now covers, and it was swept %d time(s)"
			% [absf(thin.position.z), nitro_v * (left + reaction), int(thin.cleared)])
	check(int(distant.cleared) == 0,
		"29: the re-validation reached %.1f m out at %.1f m/s, past the %.1f m the window covers"
			% [absf(distant.position.z), nitro_v, nitro_v * (left + reaction)])
	check(cleared_signals == 0,
		"29: the re-validation emitted hazard_cleared %d time(s)" % cleared_signals)
	check(events["hazards_blasted"].is_empty(),
		"29: the re-validation reported a blast: %s" % [events["hazards_blasted"]])
	check(events["bonus_awarded"].is_empty(),
		"29: the re-validation paid a bonus: %s" % [events["bonus_awarded"]])
	check(int(game.score) == score_before and int(game.hazards_dodged) == dodged_before,
		"29: the re-validation moved the score (%d -> %d) or the dodge count (%d -> %d)"
			% [score_before, int(game.score), dodged_before, int(game.hazards_dodged)])
	_free_rig(rig)

## A draw the window rejects has to be gone before the next line of code runs, not at the end of the
## frame. The reject spends a moment inside the tree — `entry_clear()` cannot be measured anywhere
## else — which is long enough for its hazards to run `_ready()`, join `runner_hazards` and queue
## their deferred visual mount. `queue_free()` would then leave that instance alive and parentless
## until the frame ends, and every global-transform read in between (the deferred mount itself, the
## autopilot, `game.track_z()`, the frontend visuals) fires `Condition "!is_inside_tree()" is true`.
## The run never gets a quiet frame to hide that in either: the accelerated visual smoke drives
## several physics ticks per rendered frame, so the ticks below stand in for exactly that — many
## rejections, no frame boundary anywhere between them.
func _check_banner_window_discards() -> void:
	# Control first: with no window open the rigged draw is placed, not substituted. Without this
	# the run below could be passing because it only ever drew breathers.
	var control := _spawner_rig({})
	if control.is_empty():
		return
	var control_spawner: Node = control["spawner"]
	if not _rig_rejectable_library(control_spawner):
		_free_rig(control)
		return
	control_spawner.set_spawning(true)
	var control_chunks: Array[Node3D] = control_spawner.get_active_chunks()
	check(not control_chunks.is_empty() and not _is_breather(control_chunks[0]),
		"29: the rigged draw has to place the hazard chunk with no window open, got %s"
			% ("an empty corridor" if control_chunks.is_empty() else String(control_chunks[0].name)))
	_free_rig(control)

	var rig := _spawner_rig({})
	if rig.is_empty():
		return
	var spawner: Node = rig["spawner"]
	var chunks: Node3D = rig["chunks"]
	if not _rig_rejectable_library(spawner):
		_free_rig(rig)
		return
	# Every chunk that is ever parked in the corridor, kept by id so a freed one can be asked about
	# without touching it. child_entered_tree fires for direct children only, so this is the chunks
	# and nothing they carry.
	var drawn: Array[int] = []
	chunks.child_entered_tree.connect(func(node: Node) -> void:
		drawn.append(node.get_instance_id()))
	# A window no hazard chunk can clear: 30 s at the base speed reaches 360 m, four times past
	# spawn_horizon_z, so every draw that carries a hazard at all is rejected and substituted.
	spawner.begin_clear_road(30.0)
	spawner.set_spawning(true)
	var report := _discard_report(spawner, chunks, drawn)
	check(int(report["discarded"]) > 0,
		"29: the entrance fill rejected no draw at all, so the discard path was never reached")
	_check_discard_report(report, "29: the entrance fill")
	# ...and again across a run of physics ticks with no frame between them, which is where a
	# queued-but-not-freed reject would pile its zombies up. Three seconds is long enough to scroll
	# the frontier back inside the spawn horizon a couple of times and short enough that nothing has
	# reached despawn_z yet, so every discard in the count below is a rejection and not a despawn.
	var ticks := _ticks(3.0)
	var before: int = report["discarded"]
	_tick([spawner], ticks)
	report = _discard_report(spawner, chunks, drawn)
	check(int(report["discarded"]) > before,
		"29: %d tick(s) of scrolling rejected no further draw (%d total), so the run proves nothing"
			% [ticks, int(report["discarded"])])
	_check_discard_report(report, "29: %d ticks in one frame" % ticks)
	_free_rig(rig)

## Assert one _discard_report(). Split out so the same four invariants read identically before and
## after the tick run.
func _check_discard_report(report: Dictionary, tag: String) -> void:
	check(int(report["zombies"]) == 0,
		"%s: %d rejected draw(s) are still alive out of the tree; a reject must be freed on the spot"
			% [tag, int(report["zombies"])])
	check(int(report["stray_hazards"]) == 0,
		"%s: runner_hazards carries %d member(s) that left the tree or are queued for deletion"
			% [tag, int(report["stray_hazards"])])
	check(int(report["orphans"]) == 0,
		"%s: World/Chunks holds %d node(s) the spawner does not count as active"
			% [tag, int(report["orphans"])])
	check(int(report["hazard_chunks"]) == 0,
		"%s: %d chunk(s) placed inside the window carry hazards; only the breather substitute may"
			% [tag, int(report["hazard_chunks"])])

## What a rejected draw must not leave behind, measured without yielding a frame:
## `discarded` — chunks that entered the corridor and are no longer active (rejects, plus despawns);
## `zombies` — of those, the ones still alive that never ran `setup()`, i.e. rejects that were only
## queued for deletion (a despawned chunk did run `setup()` and is allowed to be queued);
## `stray_hazards` — members of `runner_hazards` that are out of the tree or queued for deletion;
## `orphans` — nodes still parented under World/Chunks that the spawner does not count as active;
## `hazard_chunks` — active chunks that are not the hazard-free substitute.
func _discard_report(spawner: Node, chunks: Node3D, drawn: Array[int]) -> Dictionary:
	var active: Array[Node3D] = spawner.get_active_chunks()
	var live := {}
	for chunk in active:
		if is_instance_valid(chunk):
			live[chunk.get_instance_id()] = true
	var report := {"discarded": 0, "zombies": 0, "stray_hazards": 0, "orphans": 0, "hazard_chunks": 0}
	for id in drawn:
		if live.has(id):
			continue
		report["discarded"] += 1
		if not is_instance_id_valid(id):
			continue
		var ghost := instance_from_id(id) as Node
		if ghost != null and not bool(ghost.get(&"_setup_done")):
			report["zombies"] += 1
	for node in get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node
		if hazard == null:
			continue
		if not hazard.is_inside_tree() or hazard.is_queued_for_deletion():
			report["stray_hazards"] += 1
	report["orphans"] = maxi(chunks.get_child_count() - active.size(), 0)
	for chunk in active:
		if is_instance_valid(chunk) and not _is_breather(chunk):
			report["hazard_chunks"] += 1
	return report

## Narrow a live spawner's library to one hazard chunk plus one breather, and point `last_index` at
## the breather. The no-repeat rule in `_pick_index()` then hands back the hazard chunk with no roll
## involved, and because `_place_next()` records the substituted breather as the last index, every
## following placement draws it again: the rejection path is reached on purpose rather than by luck
## of a seed, and the weights are left alone so `rand_weighted()` is never handed a zero sum.
func _rig_rejectable_library(spawner: Node) -> bool:
	var hazard_meta := {}
	var breather_meta := {}
	for entry in spawner.metas:
		var meta: Dictionary = entry
		if bool(meta["breather"]):
			if breather_meta.is_empty():
				breather_meta = meta
		elif hazard_meta.is_empty() and float(meta["min_difficulty"]) <= 0.0 \
				and float(meta["max_difficulty"]) >= 0.0:
			hazard_meta = meta
	if hazard_meta.is_empty() or breather_meta.is_empty():
		check(false, "29: the library needs a difficulty-0 hazard chunk and a breather to reject a draw")
		return false
	spawner.metas.clear()
	spawner.metas.append(hazard_meta)
	spawner.metas.append(breather_meta)
	spawner.last_index = 1
	return true

## The authored tag, read off the instance, so these checks do not depend on which scenes the
## library happens to hold or on how the spawner names them.
func _is_breather(chunk: Node3D) -> bool:
	var tags: PackedStringArray = chunk.tags
	return tags.has("breather")

func _has_run(entries: Array, run_id: String) -> bool:
	for item in entries:
		if String((item as Dictionary).get("run_id", "")) == run_id:
			return true
	return false

func _bonus_reasons(events: Dictionary) -> Array[StringName]:
	var reasons: Array[StringName] = []
	for item in events["bonus_awarded"]:
		reasons.append(StringName((item as Array)[1]))
	return reasons

## The contract §11.4 boss block outside a fight: every key present, every value empty.
func _boss_info_is_empty(info: Dictionary) -> bool:
	for key in ["kind", "name", "hp", "max_hp", "phase", "phase_count", "accepted_tools", "pending_attacks"]:
		if not info.has(key):
			return false
	var tools: Array = info["accepted_tools"]
	var attacks: Array = info["pending_attacks"]
	return StringName(info["kind"]) == &"" and String(info["name"]) == "" and int(info["hp"]) == 0 \
		and int(info["max_hp"]) == 0 and int(info["phase"]) == 0 and int(info["phase_count"]) == 0 \
		and tools.is_empty() and attacks.is_empty()

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
	game.leaderboard_path = scratch_leaderboard
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

## A boss shot in the tree, with the closing speed the bot plans its trigger distance from.
func _projectile(at: Vector3, closing_speed: float) -> Node3D:
	var shot := Node3D.new()
	shot.set_script(projectile_script)
	shot.closing_speed = closing_speed
	root.add_child(shot)
	shot.position = at
	junk.append(shot)
	return shot

## A power-up stand-in for the autopilot's greedy planner: pickup_targets only reads
## global_position, so a bare Node3D in the tree is the whole surface.
func _pickup(at: Vector3) -> Node3D:
	var pickup := Node3D.new()
	root.add_child(pickup)
	pickup.position = at
	junk.append(pickup)
	return pickup

## Swap whatever `_mount_visual()` chose for a hazard_visual_base.gd recorder, so the contract §5.2
## hooks can be asserted without depending on which mount this checkout produced. The displaced
## visual leaves the tree (it must stop processing) and is freed with the rest of the junk.
func _mount_recording_hazard_visual(hazard: Area3D) -> Node3D:
	var script := _compile(FAKE_HAZARD_VISUAL_SOURCE)
	if script == null:
		return null
	_unmount_visual(hazard)
	var node := Node3D.new()
	node.set_script(script)
	hazard.visual = node
	hazard.add_child(node)
	junk.append(node)
	return node

## Mount the contract §3 graybox on a hazard, exactly as `_mount_visual()`'s fallback branch does
## (`_build_graybox()` also rebuilds `_graybox_box`, which `_apply_laser_state()` resizes). A
## checkout with the frontend visual scenes would otherwise never reach the graybox rules.
func _force_graybox(hazard: Area3D) -> MeshInstance3D:
	_unmount_visual(hazard)
	var graybox: MeshInstance3D = hazard._build_graybox()
	hazard._graybox = graybox
	hazard.visual = graybox
	hazard.add_child(graybox)
	junk.append(graybox)
	return graybox

## Detach the mounted visual and forget the graybox, leaving the hazard ready for a test-owned mount.
func _unmount_visual(hazard: Area3D) -> void:
	if is_instance_valid(hazard.visual):
		hazard.remove_child(hazard.visual)
		junk.append(hazard.visual)
	hazard.visual = null
	hazard._graybox = null
	hazard._graybox_box = null

## A runner_visual_base stand-in that records the power-up hooks reset() has to clear.
func _recording_visual() -> Node3D:
	var script := _compile(FAKE_VISUAL_SOURCE)
	if script == null:
		return null
	var node := Node3D.new()
	node.set_script(script)
	junk.append(node)
	return node

## A player stand-in with only the lane state the autopilot reads and drives.
func _fake_player() -> Node:
	var player := Node.new()
	player.set_script(player_script)
	junk.append(player)
	return player

## The real runner_player.gd, outside the tree: the Super Jump invulnerability half only touches its
## own fields, `config` and game.hit_manager, so none of the @onready shapes or the visual are
## needed, and nothing ever calls move_and_slide() on it.
func _real_player(game: Node3D) -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.set_script(real_player_script)
	player.game = game
	player.config = game.config
	junk.append(player)
	return player

## Age the player's Super Jump invulnerability by hand. The full _physics_process is the whole
## movement step and needs the tree; this is the one timer section 12 is about.
func _tick_invuln(player: CharacterBody3D, seconds: float) -> void:
	for i in _ticks(seconds):
		player._update_super_jump_invuln(TICK)

## A facade inside the tree, for the run-loop helpers that call get_tree(). Scripted only after
## add_child for the reason spelled out in _finish_caught_run().
## The leaderboard override comes straight after set_script rather than before add_child: the script
## is what carries the property, and skipping _ready() is also what keeps `autostart` from ever
## opening a run, so there is no live run for it to race.
func _tree_game(script: GDScript = null) -> Node3D:
	var game := Node3D.new()
	root.add_child(game)
	game.set_script(script if script != null else game_script)
	game.leaderboard_path = scratch_leaderboard
	game.config = base_config.duplicate()
	junk.append(game)
	return game

## A live StageManager with the collaborators it drives: the v1 systems, a spawner that records the
## drain gate, and TurnRig / CameraRig stand-ins that stay square. `with_arena` mounts a
## real boss_arena.tscn where contract §11.3 puts it; `real_catch` swaps in the facade that runs the
## catch cinematic instead of only counting it, and `script` overrides the facade script outright.
## The StageManager sits in the tree (its drain scans runner_hazards through get_tree()) with its
## own physics processing off, so every tick below is the test's, never the engine's.
func _stage_rig(overrides: Dictionary, with_arena := false, real_catch := false,
		script: GDScript = null) -> Dictionary:
	var facade_script := script if script != null else (caught_game_script if real_catch else null)
	var game := _tree_game(facade_script)
	for key in overrides:
		game.config.set(key, overrides[key])
	game.state = &"running"
	game.speed = float(game.config.base_speed)
	var systems := _systems(game)
	var turn_rig := _fake_rig()
	var camera := _fake_rig()
	game.turn_rig = turn_rig
	game.camera_rig = camera
	var arena: Node3D = null
	if with_arena:
		arena = _mount_arena(game)
	var stage: Node = stage_manager_script.new()
	root.add_child(stage)
	stage.set_physics_process(false)
	junk.append(stage)
	game.stage_manager = stage
	var events := _watch_stage(game)
	stage.setup(game)
	var rig := {"game": game, "stage": stage, "arena": arena, "turn_rig": turn_rig,
		"camera_rig": camera, "events": events}
	rig.merge(systems)
	return rig

## A live chunk_spawner.gd on a facade inside the tree, with World/Chunks where runner_game.tscn
## puts it and a non-null stage_manager to arm the phase gate. The corridor opens empty on purpose:
## `reset()` runs against an `idle` phase, so the fill it ends with places nothing and section 29
## starts from exactly the corridor a drained stage seam leaves behind. The spawner never ticks
## itself — the engine runs no frames inside run(), and every advance is a hand-driven
## _physics_process.
func _spawner_rig(overrides: Dictionary) -> Dictionary:
	var game := _tree_game()
	for key in overrides:
		game.config.set(key, overrides[key])
	game.state = &"running"
	game.speed = float(game.config.base_speed)
	game.difficulty = 0.0
	game.phase = &"idle"
	var world := Node3D.new()
	world.name = "World"
	game.add_child(world)
	var chunks := Node3D.new()
	chunks.name = "Chunks"
	world.add_child(chunks)
	game.world = world
	game.chunks = chunks
	game.stage_manager = Node.new()
	game.add_child(game.stage_manager)
	var spawner: Node = real_spawner_script.new()
	game.add_child(spawner)
	spawner.set_physics_process(false)
	spawner.setup(game)
	game.spawner = spawner
	spawner.reset(20260922)
	var empty: bool = spawner.get_active_chunks().is_empty()
	check(empty, "29: the spawner rig should open on an empty corridor, got %d chunk(s)"
		% spawner.get_active_chunks().size())
	if not empty:
		_free_rig({"game": game})
		return {}
	game.phase = &"run"
	return {"game": game, "spawner": spawner, "chunks": chunks}

## Seconds until the soonest hazard in the active corridor reaches the player, at the speed the
## spawner plans against. INF when no active chunk carries one.
func _nearest_arrival(spawner: Node, game: Node3D) -> float:
	var speed := maxf(maxf(float(game.speed), float(game.config.base_speed)), 1.0)
	var soonest := INF
	for chunk in spawner.get_active_chunks():
		var node := chunk as Node3D
		if node == null or not is_instance_valid(node) or node.get_hazards().is_empty():
			continue
		soonest = minf(soonest, -(float(node.global_position.z) - float(node.entry_clear())) / speed)
	return soonest

## A boss_arena.tscn on its own facade, for the fight rules that need no stage machine.
func _boss_rig(overrides: Dictionary) -> Dictionary:
	var game := _tree_game()
	for key in overrides:
		game.config.set(key, overrides[key])
	game.state = &"running"
	var systems := _systems(game)
	var camera := _fake_rig()
	game.camera_rig = camera
	var events := _watch_stage(game)
	var arena := _mount_arena(game)
	var rig := {"game": game, "arena": arena, "camera_rig": camera, "events": events}
	rig.merge(systems)
	return rig

## Mount the real arena where runner_game.tscn mounts it (World/TurnRig/BossArena), so a tool that
## resolves its encounter by path finds it. `setup()` runs from the arena's own _ready() through
## _find_facade(); calling it again is idempotent and makes the wiring explicit.
func _mount_arena(game: Node3D) -> Node3D:
	var packed := load(ARENA_SCENE) as PackedScene
	check(packed != null, "the boss arena scene failed to load")
	if packed == null:
		return null
	var world := Node3D.new()
	world.name = "World"
	game.add_child(world)
	var rig := Node3D.new()
	rig.name = "TurnRig"
	world.add_child(rig)
	var arena := packed.instantiate() as Node3D
	if arena == null:
		check(false, "the boss arena root is not a Node3D")
		return null
	arena.name = "BossArena"
	rig.add_child(arena)
	arena.setup(game)
	game.boss_encounter = arena
	return arena

func _fake_rig() -> Node3D:
	var rig := Node3D.new()
	rig.set_script(rig_script)
	root.add_child(rig)
	junk.append(rig)
	return rig

## Free a rig's facade (and everything mounted under it) before the next one is built, so two live
## arenas never share the runner_hazards / runner_tools groups.
func _free_rig(rig: Dictionary) -> void:
	var game: Node3D = rig.get("game", null)
	if game == null or not is_instance_valid(game):
		return
	junk.erase(game)
	if game.get_parent() != null:
		game.get_parent().remove_child(game)
	game.free()

## Drive the systems one tick at a time, advancing the facade's own clock the way its
## _physics_process would. The StageManager owns run_clock, so only `elapsed` is moved here.
func _tick_stage(nodes: Array, game: Node3D, count: int) -> void:
	for i in count:
		if game.state == &"running" or game.state == &"caught":
			game.elapsed += TICK
			game.distance += float(game.speed) * TICK
		for node in nodes:
			node._physics_process(TICK)

## A record must not carry a bend tally. The corridor no longer counts one.
func _check_no_turn_keys(record: Dictionary, tag: String) -> void:
	for key in record:
		check(not String(key).contains("turn"), "%s still records %s" % [tag, key])

## The facade must not still expose a bend signal or property. `turn_rig` is the static mount and
## stays. The script chain is walked because a test facade extends runner_game.gd.
func _check_no_turn_fields(node: Object, tag: String) -> void:
	if node is Node:
		for info in (node as Node).get_signal_list():
			var signal_name := String(info["name"])
			check(not signal_name.contains("turn"), "%s still signals %s" % [tag, signal_name])
	var script: Script = node.get_script()
	while script != null:
		for prop in script.get_script_property_list():
			var prop_name := String(prop["name"])
			if prop_name == "turn_rig":
				continue
			check(not prop_name.contains("turn"), "%s still exposes %s" % [tag, prop_name])
		script = script.get_base_script()

## Record every contract §11.4 signal the stage machine and the boss encounter emit.
func _watch_stage(game: Node) -> Dictionary:
	var events := {
		"phase_changed": [],
		"stage_started": [],
		"stage_cleared": [],
		"boss_intro": [],
		## Same idea for the fight: boss_intro must precede boss_spawned, with the contract 2.6
		## §11.14 cinematic between them.
		"boss_log": [],
		"boss_cinematic": [],
		"boss_spawned": [],
		"boss_health_changed": [],
		"boss_phase_changed": [],
		"boss_attack_telegraph": [],
		"boss_defeated": [],
		"boss_retreated": [],
		"tool_collected": [],
		"bonus_awarded": []
	}
	game.phase_changed.connect(func(phase: StringName) -> void:
		events["phase_changed"].append(phase))
	game.stage_started.connect(func(index: int, name: StringName, speed: float) -> void:
		events["stage_started"].append([index, name, speed]))
	game.stage_cleared.connect(func(index: int, bonus: int) -> void:
		events["stage_cleared"].append([index, bonus]))
	game.boss_intro.connect(func(kind: StringName, name: String, seconds: float) -> void:
		events["boss_intro"].append([kind, name, seconds])
		events["boss_log"].append(&"intro"))
	game.boss_spawned.connect(func(kind: StringName, hp: int) -> void:
		events["boss_spawned"].append([kind, hp])
		events["boss_log"].append(&"spawned"))
	game.boss_cinematic.connect(func(kind: StringName, mode: StringName, seconds: float) -> void:
		events["boss_cinematic"].append([kind, mode, seconds])
		events["boss_log"].append(&"cinematic"))
	game.boss_cinematic_ended.connect(func(_mode: StringName) -> void:
		events["boss_log"].append(&"cinematic_ended"))
	game.boss_health_changed.connect(func(hp: int, max_hp: int) -> void:
		events["boss_health_changed"].append([hp, max_hp]))
	game.boss_phase_changed.connect(func(phase: int) -> void:
		events["boss_phase_changed"].append(phase))
	game.boss_attack_telegraph.connect(func(mask: int, kind: StringName, seconds: float) -> void:
		events["boss_attack_telegraph"].append([mask, kind, seconds]))
	game.boss_defeated.connect(func(kind: StringName, bonus: int) -> void:
		events["boss_defeated"].append([kind, bonus]))
	game.boss_retreated.connect(func(kind: StringName, bonus: int) -> void:
		events["boss_retreated"].append([kind, bonus]))
	game.tool_collected.connect(func(kind: StringName, damage: int) -> void:
		events["tool_collected"].append([kind, damage]))
	game.bonus_awarded.connect(func(points: int, reason: StringName) -> void:
		events["bonus_awarded"].append([points, reason]))
	return events

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
## stopped, so the invariants have to be checked mid-cycle as well. `hidden`, when given, is the
## graybox: `_apply_laser_state()` re-shows it on any `on` slot, and a re-show that the next slot
## hid again would be invisible to a single check at the end.
func _check_laser_inert(pair: Dictionary, seconds: float, state: StringName, tag: String,
		hidden: Node3D = null) -> void:
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
		if hidden != null:
			check(not hidden.visible, "11: %s keeps its graybox hidden (at %.1f s)" % [tag, elapsed])

## Drive one caught run on a bare facade all the way to run_finished. RunnerGame times the catch
## sequence in its own _physics_process, so ticking it is the whole run-end path, leaderboard write
## included. Returns {game, result, finished, saved}.
func _finish_caught_run(path: String) -> Dictionary:
	# Scripted only once it is in the tree: runner_game.gd's _ready() would go looking for the
	# scene's child systems, and setting the script afterwards skips it while get_tree() still
	# answers, which is what the run loop needs. Nothing here ever awaits, so the engine never
	# ticks the node behind the test's back.
	var game := Node3D.new()
	root.add_child(game)
	game.set_script(game_script)
	game.config = base_config.duplicate()
	junk.append(game)
	_systems(game)
	game.run_id = "finish-%d" % (randi() % 1000000)
	game.leaderboard_path = path
	game.state = &"caught"
	var seen := {"game": game, "result": {}, "finished": 0, "saved": 0}
	game.run_finished.connect(func(result: Dictionary) -> void:
		seen["finished"] += 1
		seen["result"] = result)
	game.leaderboard_saved.connect(func(_entries: Array, _rank: int) -> void:
		seen["saved"] += 1)
	for i in _ticks(float(game.config.caught_sequence_seconds) + 0.5):
		game._physics_process(TICK)
	return seen

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
