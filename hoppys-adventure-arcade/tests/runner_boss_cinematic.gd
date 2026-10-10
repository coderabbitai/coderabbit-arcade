extends SceneTree
## Boss cinematics (contract 2.6 §11.14, plus the §11.4 signals, §11.5 visual feed and focus, and
## §11.13 bosses_met / bosses_defeated_kinds). Hand-driven 1/60 ticks, like tests/runner_logic.gd.
## Run with --path hoppys-adventure-arcade --script res://tests/runner_boss_cinematic.gd.
##
## Only scripts that never reach runner_game.gd are preloaded: under --script this file is compiled
## before the autoloads exist, and runner_game.gd needs AppRouter at compile time.

const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
const ARENA_SCENE := "res://scenes/runner/boss/boss_arena.tscn"
const GAME_SCENE := "res://scenes/runner/runner_game.tscn"
const UI_SCENE := "res://scenes/runner/ui/boss_cinematic.tscn"
const TICK := 1.0 / 60.0
## Contract §11.14 defaults. Stamped onto every duplicated config a length check reads, so a .tres
## tweak cannot move the numbers this file asserts.
const INTRO_FULL := 5.0
const INTRO_SHORT := 2.5
const DEFEAT_FULL := 3.6
const DEFEAT_SHORT := 2.0
const SKIP_AFTER := 0.5
const SKIP_TAIL := 0.3
const SPEED_SCALE := 0.25
const HITSTOP := 0.12
const SLOWMO := 0.8
const SLOWMO_FACTOR := 0.4
const OUTRO := 1.0
const HIT_STOP_FACTOR := 0.05
const EASE_SECONDS := 0.35
const KILL_BASE := 600
const KILL_PER_STAGE := 200
const TOOL_BONUS := 20
const MODES: Array[StringName] = [&"intro_full", &"intro_short", &"defeat_full", &"defeat_short"]

## Bare facade. _ready is a no-op so autostart never opens a run (the real _ready would). @onready
## still resolves when the node enters the tree, so _tree_game builds the scene paths first.
const GAME_SOURCE := "extends \"res://scenes/runner/runner_game.gd\"\nfunc _ready() -> void:\n\tpass\n"
const HAZARD_SOURCE := "extends Node3D\nvar kind: StringName = &\"pr_backlog_low\"\nvar blocking := true\nfunc is_blocking() -> bool:\n\treturn blocking\nfunc clear() -> void:\n\tblocking = false\n"
const SPAWNER_SOURCE := "extends Node\nvar spawn_calls: Array = []\nfunc set_spawning(on: bool) -> void:\n\tspawn_calls.append(on)\nfunc begin_clear_road(_seconds: float) -> void:\n\tpass\nfunc clear_hazards_in_range() -> int:\n\treturn 0\n"
const RIG_SOURCE := "extends Node3D\nvar turns: Array = []\nfunc set_turn(progress: float, direction: int) -> void:\n\tturns.append([progress, direction])\nfunc shake(_strength: float, _duration := 0.35) -> void:\n\tpass\n"
## The slice of the player the hold touches: controls_enabled plus the setter refresh_player_controls
## calls (contract §11.14). CharacterBody3D because runner_game.player is typed as one.
const CONTROLS_SOURCE := "extends CharacterBody3D\nvar controls_enabled := true\nfunc set_controls_enabled(enabled: bool) -> void:\n\tcontrols_enabled = enabled\n"
## Contract §11.5 visual feed. Extends the real base, so a hook the backend calls under a new name
## still resolves; only the cinematic ones are recorded.
const RECORDER_SOURCE := (
	"extends \"res://scenes/runner/boss/boss_visual_base.gd\"\n"
	+ "var calls: Array = []\n"
	+ "func _note(method: StringName, args: Array) -> void:\n"
	+ "\tcalls.append([method, args.duplicate()])\n"
	+ "func play_cinematic(mode: StringName, seconds: float) -> void:\n"
	+ "\t_note(&\"play_cinematic\", [mode, seconds])\n"
	+ "func set_cinematic_progress(mode: StringName, progress: float) -> void:\n"
	+ "\t_note(&\"set_cinematic_progress\", [mode, progress])\n"
	+ "func set_time_factor(factor: float) -> void:\n"
	+ "\t_note(&\"set_time_factor\", [factor])\n"
	+ "func play_defeat() -> void:\n"
	+ "\t_note(&\"play_defeat\", [])\n"
	+ "func play_retreat() -> void:\n"
	+ "\t_note(&\"play_retreat\", [])\n"
	+ "func set_health(hp: int, max_health: int) -> void:\n"
	+ "\t_note(&\"set_health\", [hp, max_health])\n"
)
## Overrides the default focus with a fixed local point (contract §11.5).
const FOCUS_SOURCE := "extends \"res://scenes/runner/boss/boss_visual_base.gd\"\nfunc cinematic_focus() -> Vector3:\n\treturn Vector3(1.5, 2.5, -0.5)\n"
## Records every set_boss_cinematic, including the optional focus argument (contract §11.14).
const CAMERA_FEED_SOURCE := "extends Node3D\nvar calls: Array = []\nfunc set_boss_cinematic(progress: float, mode: StringName, boss_position: Vector3, focus_position: Variant = null) -> void:\n\tcalls.append([progress, mode, boss_position, focus_position])\nfunc set_turn(_progress: float, _direction: int) -> void:\n\tpass\nfunc shake(_strength: float, _duration := 0.35) -> void:\n\tpass\n"

var failures := 0
var checks := 0
var base_config: RunConfig
var saved_scale := 1.0
var game_script: GDScript
var runner_game_script: GDScript
var hazard_script: GDScript
var spawner_script: GDScript
var rig_script: GDScript
var controls_script: GDScript
var recorder_script: GDScript
var focus_script: GDScript
var camera_feed_script: GDScript
var visual_base_script: GDScript
var hit_manager_script: GDScript
var score_manager_script: GDScript
var effect_manager_script: GDScript
var speed_controller_script: GDScript
var stage_manager_script: GDScript
var autopilot_script: GDScript
var encounter_script: GDScript
var camera_script: GDScript
var junk: Array[Node] = []
var temp_paths: Array[String] = []
var live_scene: Node = null
## One throwaway board for every facade. Never user://leaderboard.cfg.
var scratch_leaderboard := "user://runner_boss_cinematic_%d.cfg" % (randi() % 1000000)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER BOSS CINEMATIC: " + message)

func note(message: String) -> void:
	print("RUNNER BOSS CINEMATIC: " + message)

func run() -> void:
	saved_scale = Engine.time_scale
	temp_paths.append(scratch_leaderboard)
	note("start")
	base_config = (load(CONFIG_PATH) as RunConfig).duplicate()
	hit_manager_script = load("res://scenes/runner/systems/hit_manager.gd") as GDScript
	score_manager_script = load("res://scenes/runner/systems/score_manager.gd") as GDScript
	effect_manager_script = load("res://scenes/runner/systems/effect_manager.gd") as GDScript
	speed_controller_script = load("res://scenes/runner/systems/speed_controller.gd") as GDScript
	stage_manager_script = load("res://scenes/runner/systems/stage_manager.gd") as GDScript
	autopilot_script = load("res://scenes/runner/systems/autopilot.gd") as GDScript
	encounter_script = load("res://scenes/runner/boss/boss_encounter.gd") as GDScript
	camera_script = load("res://scenes/runner/systems/camera_rig.gd") as GDScript
	runner_game_script = load("res://scenes/runner/runner_game.gd") as GDScript
	game_script = _compile(GAME_SOURCE)
	hazard_script = _compile(HAZARD_SOURCE)
	spawner_script = _compile(SPAWNER_SOURCE)
	rig_script = _compile(RIG_SOURCE)
	controls_script = _compile(CONTROLS_SOURCE)
	recorder_script = _compile(RECORDER_SOURCE)
	focus_script = _compile(FOCUS_SOURCE)
	camera_feed_script = _compile(CAMERA_FEED_SOURCE)
	visual_base_script = load("res://scenes/runner/boss/boss_visual_base.gd") as GDScript
	if game_script == null or hazard_script == null or spawner_script == null or rig_script == null \
			or controls_script == null or recorder_script == null or focus_script == null \
			or camera_feed_script == null or visual_base_script == null or runner_game_script == null \
			or hit_manager_script == null or score_manager_script == null or effect_manager_script == null \
			or speed_controller_script == null or stage_manager_script == null or autopilot_script == null \
			or encounter_script == null or camera_script == null or base_config == null:
		check(false, "the test harness scripts failed to compile")
		await _report()
		return
	_test_curves()
	_test_full_and_short()
	_test_checkpoint()
	_test_skip()
	_test_pause()
	_test_defeat_and_retreat()
	_test_hold_and_abort()
	_test_visual_feed()
	_test_unskippable_defeats()
	_test_intro_timing_and_focus()
	_test_retreat_outro_feed()
	_test_zero_tail_skip()
	_test_set_health_feed()
	_test_zero_length()
	_test_kill_mid_intro_order()
	await _test_real_input()
	await _test_real_defeat_input()
	await _test_restart_during_intro()
	await _report()

# --- 8. Pure curves (contract §11.14 boss_shot, time_factor_profile) --------------------------

func _test_curves() -> void:
	var endpoint_bad := ""
	var range_bad := ""
	var hold_at := {}
	for mode in MODES:
		var saw_one := false
		var at := -1.0
		for i in 101:
			var p := i * 0.01
			var shot: Dictionary = camera_script.boss_shot(p, mode)
			var blend := float(shot["blend"])
			if (is_equal_approx(p, 0.0) or is_equal_approx(p, 1.0)) and blend != 0.0:
				endpoint_bad = "%s blend %.6f at p %.2f" % [mode, blend, p]
			if blend < 0.0 or blend > 1.0:
				range_bad = "%s blend %.6f at p %.2f" % [mode, blend, p]
				break
			if blend == 1.0 and not saw_one:
				saw_one = true
				at = p
		hold_at[mode] = at
		if not saw_one and range_bad == "":
			range_bad = "%s never reached blend 1" % mode
		if endpoint_bad != "" or range_bad != "":
			break
	check(endpoint_bad == "", "8: boss_shot blend is exactly 0 at p = 0 and p = 1 (%s)" % endpoint_bad)
	check(range_bad == "", "8: boss_shot blend stays in [0, 1] and hits 1 mid-shot (%s)" % range_bad)
	var empty_bad := ""
	for mode in [&"", &"not_a_cinematic"]:
		for i in 101:
			var p := i * 0.01
			var blend := float(camera_script.boss_shot(p, mode)["blend"])
			if blend != 0.0:
				empty_bad = "%s blend %.6f at p %.2f" % [mode, blend, p]
				break
		if empty_bad != "":
			break
		# Clamped outside [0, 1] too: the curve answers the endpoints before the ramps.
		for p in [-0.5, 1.5]:
			var blend := float(camera_script.boss_shot(p, mode)["blend"])
			if blend != 0.0:
				empty_bad = "%s blend %.6f at p %.2f" % [mode, blend, p]
	check(empty_bad == "", "8: boss_shot blend is exactly 0 for an empty or unknown mode (%s)" % empty_bad)
	var profile_bad := _profile_problems()
	check(profile_bad == "", "8: time_factor_profile (%s)" % profile_bad)
	note("8: curves hold-at %s, profile %s" % [hold_at, "ok" if profile_bad == "" else profile_bad])

## Hit-stop 0.05 on [0, hitstop), then slowmo_factor smoothstepped to 1, then exactly 1.
## Negative time is 1, not the hit-stop. The 0.05 is the contract constant, not a value read back
## from the same function under test.
func _profile_problems() -> String:
	if _profile(-1.0) != 1.0 or _profile(-0.001) != 1.0:
		return "negative t is %.4f / %.4f, expected 1" % [_profile(-1.0), _profile(-0.001)]
	if _profile(0.0) != HIT_STOP_FACTOR:
		return "t = 0 is %.4f, expected %.2f" % [_profile(0.0), HIT_STOP_FACTOR]
	var stop_bad := ""
	for i in 12:
		var t := i * 0.01
		if t >= HITSTOP:
			break
		if _profile(t) != HIT_STOP_FACTOR:
			stop_bad = "t %.2f is %.4f" % [t, _profile(t)]
			break
	if stop_bad != "":
		return stop_bad
	# t == hitstop is the first slow-mo sample, not still the hit-stop (the comparison is strict <).
	var at_stop := _profile(HITSTOP)
	if not is_equal_approx(at_stop, SLOWMO_FACTOR):
		return "t = hitstop %.2f is %.4f, expected slowmo_factor %.2f" % [HITSTOP, at_stop, SLOWMO_FACTOR]
	var prev := at_stop
	for i in 80:
		var t := HITSTOP + (i + 1) * (SLOWMO / 80.0)
		var value := _profile(t)
		if value + 0.000001 < prev:
			return "fell from %.4f to %.4f at t %.4f" % [prev, value, t]
		prev = value
	if _profile(HITSTOP + SLOWMO) != 1.0:
		return "t = hitstop + slowmo is %.4f, expected 1" % _profile(HITSTOP + SLOWMO)
	if _profile(HITSTOP + SLOWMO + 0.01) != 1.0 or _profile(DEFEAT_FULL) != 1.0:
		return "after the slow-mo, %.4f / %.4f, expected 1" % [_profile(HITSTOP + SLOWMO + 0.01), _profile(DEFEAT_FULL)]
	# Independent of time_factor_profile: 0.4 + 0.6 * smoothstep over the slow-mo span.
	var interior: Array[float] = [0.16, 0.24, 0.32, 0.40, 0.48, 0.52, 0.60, 0.68, 0.76, 0.84, 0.90]
	for sample in interior:
		var got: float = _profile(sample)
		var want: float = _slowmo_factor_at(sample)
		if absf(got - want) > 0.0001:
			return "t %.4f is %.6f, formula %.6f" % [sample, got, want]
	var mid: float = _profile(0.52)
	if absf(mid - 0.7) > 0.0001:
		return "t = 0.52 is %.6f, expected 0.7" % mid
	var late: float = _profile(0.9)
	if late >= 1.0:
		return "t = 0.9 is %.6f, expected below 1" % late
	return ""

## 0.4 + 0.6 * smoothstep(0, 1, (t - 0.12) / 0.8), for t inside the slow-mo ramp.
func _slowmo_factor_at(t: float) -> float:
	return SLOWMO_FACTOR + (1.0 - SLOWMO_FACTOR) * smoothstep(0.0, 1.0, (t - HITSTOP) / SLOWMO)

func _profile(elapsed: float) -> float:
	return float(encounter_script.time_factor_profile(elapsed, HITSTOP, SLOWMO, SLOWMO_FACTOR))

# --- 1. Full on stage 1, short on stage 4 (contract §11.14) ------------------------------------

func _test_full_and_short() -> void:
	var rig := _stage_rig(_overrides({"boss_timeout_seconds": 2.5}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var stage: Node = rig["stage"]
	stage.begin()
	var expected_mode: Array[StringName] = [&"intro_full", &"intro_full", &"intro_full", &"intro_short"]
	var expected_seconds := [INTRO_FULL, INTRO_FULL, INTRO_FULL, INTRO_SHORT]
	var expected_kind: Array[StringName] = [
		&"flaky_test_swarm", &"merge_conflict_hydra", &"legacy_monolith", &"flaky_test_swarm"
	]
	var summary := []
	for index in 4:
		var tag := "1: stage %d" % (index + 1)
		if index == 0:
			if not _require_boss(rig, tag, 8.0):
				break
		elif not _advance_to_next_boss(rig, tag):
			break
		var events: Dictionary = rig["events"]
		var intro: Array = events["boss_intro"]
		var cinematic: Array = events["boss_cinematic"]
		var opened: Array = intro.back() if not intro.is_empty() else []
		var shot: Array = cinematic.back() if not cinematic.is_empty() else []
		var mode: StringName = shot[1] if shot.size() >= 3 else &""
		var intro_seconds := float(opened[2]) if opened.size() >= 3 else -1.0
		var shot_seconds := float(shot[2]) if shot.size() >= 3 else -1.0
		var kind: StringName = opened[0] if opened.size() >= 1 else &""
		check(_same(events["order"].slice(maxi(events["order"].size() - 4, 0)),
			[&"intro", &"cinematic", &"spawned", &"health"]),
			"%s: signal order %s, expected intro, cinematic, spawned, health" % [tag, events["order"]])
		check(kind == expected_kind[index] and mode == expected_mode[index],
			"%s: opened %s / %s, expected %s / %s (cycle %d)"
			% [tag, kind, mode, expected_kind[index], expected_mode[index], BossDefs.cycle(index + 1)])
		check(is_equal_approx(intro_seconds, expected_seconds[index])
			and is_equal_approx(shot_seconds, intro_seconds),
			"%s: boss_intro %.4f s and boss_cinematic %.4f s, expected both %.4f"
			% [tag, intro_seconds, shot_seconds, expected_seconds[index]])
		var mirror: Dictionary = _last_mirror(events, "mirror_open")
		check(StringName(mirror.get("mode", &"")) == mode and is_equal_approx(float(mirror.get("progress", -1.0)), 0.0)
			and is_equal_approx(float(mirror.get("factor", -1.0)), 1.0) and bool(mirror.get("hold", false)),
			"%s: mirror at boss_cinematic is mode %s progress %.4f factor %.4f hold %s"
			% [tag, mirror.get("mode", &""), float(mirror.get("progress", -1.0)), float(mirror.get("factor", -1.0)), mirror.get("hold", false)])
		var window := _play_intro(rig, tag)
		var ended_delta := int(window["ended_delta"])
		check(ended_delta == 1, "%s: boss_cinematic_ended fired %d time(s) for the intro, expected 1" % [tag, ended_delta])
		check(bool(window["clean"]), "%s: a threat appeared before the intro ended (%s)" % [tag, window["threat"]])
		var after := _wait_for_threat(rig, tag, 3.0)
		# Stage 1 and stage 4 are the lengths the contract calls out; both must open the attack gate
		# only once the window is over, and the first tool / telegraph follows that (not the 5 s mark
		# on a short intro).
		if index == 0 or index == 3:
			check(bool(after["appeared"]) and int(after["post_ticks"]) > 0,
				"%s: no telegraph or tool within %.1f s after the intro (post ticks %d, phase %s)"
				% [tag, 3.0, int(after["post_ticks"]), stage.phase])
		var ended_after_intro := int(window["ended_at"])
		if not _finish_retreat(rig, tag):
			break
		var extra_ended: int = int(events["ended"].size()) - ended_after_intro
		check(extra_ended == 0,
			"%s: retreat added %d boss_cinematic_ended, expected none (intro already ended once)" % [tag, extra_ended])
		summary.append("%s %s %.3fs window %.3fs threat +%.3fs" % [
			kind, mode, shot_seconds, int(window["ticks"]) * TICK, int(after["post_ticks"]) * TICK])
		if index == 3:
			var window_seconds: float = int(window["ticks"]) * TICK
			check(absf(window_seconds - INTRO_SHORT) <= TICK + 0.0001,
				"1: stage 4 intro_short ran %.4f s (%d ticks), expected %.3f s within one tick"
				% [window_seconds, int(window["ticks"]), INTRO_SHORT])
	note("1: %s" % [", ".join(summary)])
	_free_rig(rig)

# --- 2. Short intro after a checkpoint retry (contract §11.13 bosses_met, §11.14) --------------

func _test_checkpoint() -> void:
	runner_game_script.set(&"pending_boss_checkpoint", {})
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	rig["stage"].begin()
	if not _require_boss(rig, "2: first meeting", 8.0):
		_free_rig(rig)
		return
	var game: Node = rig["game"]
	var events: Dictionary = rig["events"]
	var first: Array = events["boss_cinematic"].back()
	var first_mode: StringName = first[1] if first.size() >= 2 else &""
	check(first_mode == &"intro_full", "2: the meeting the checkpoint is taken on plays %s, expected intro_full" % first_mode)
	var checkpoint: Dictionary = (game.boss_checkpoint as Dictionary).duplicate(true)
	var met: Array = checkpoint.get("bosses_met", [])
	check(_has_kind(met, &"flaky_test_swarm") and int(checkpoint.get("stage_index", 0)) == 1,
		"2: boss-entry checkpoint bosses_met %s stage %s, expected flaky_test_swarm on stage 1"
		% [met, checkpoint.get("stage_index", "<missing>")])
	_free_rig(rig)
	_assert_retry(checkpoint, "2: begin_at_boss", false)
	_assert_retry(checkpoint, "2: start_run", true)
	runner_game_script.set(&"pending_boss_checkpoint", {})
	note("2: checkpoint bosses_met %s, both retries asked for intro_short on stage 1" % [met])

func _assert_retry(checkpoint: Dictionary, tag: String, via_start_run: bool) -> void:
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var stage: Node = rig["stage"]
	if via_start_run:
		runner_game_script.set(&"pending_boss_checkpoint", checkpoint.duplicate(true))
		game.start_run(0)
		var pending: Variant = runner_game_script.get(&"pending_boss_checkpoint")
		check(pending is Dictionary and (pending as Dictionary).is_empty(),
			"%s: pending_boss_checkpoint was not consumed (%s)" % [tag, pending])
	else:
		stage.begin_at_boss(checkpoint.duplicate(true))
	if not _require_boss(rig, tag, 8.0):
		_free_rig(rig)
		return
	var events: Dictionary = rig["events"]
	var shot: Array = events["boss_cinematic"].back()
	var intro: Array = events["boss_intro"].back()
	var mode: StringName = shot[1] if shot.size() >= 2 else &""
	var seconds := float(shot[2]) if shot.size() >= 3 else -1.0
	var intro_seconds := float(intro[2]) if intro.size() >= 3 else -1.0
	var want := minf(INTRO_SHORT, INTRO_FULL)
	check(mode == &"intro_short" and is_equal_approx(seconds, want) and is_equal_approx(intro_seconds, seconds),
		"%s: stage %d plays %s for %.4f s (boss_intro %.4f), expected intro_short %.4f s"
		% [tag, int(stage.stage_index), mode, seconds, intro_seconds, want])
	check(int(stage.stage_index) == 1, "%s: retry opened on stage %d" % [tag, int(stage.stage_index)])
	var fresh: Array = (game.boss_checkpoint as Dictionary).get("bosses_met", [])
	check(_has_kind(fresh, &"flaky_test_swarm"), "%s: the fresh checkpoint dropped bosses_met (%s)" % [tag, fresh])
	_free_rig(rig)

# --- 3. Skip (contract §11.14 skip_after / skip_tail) ------------------------------------------

func _test_skip() -> void:
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var events: Dictionary = rig["events"]
	rig["stage"].begin()
	if not _require_boss(rig, "3: skip", 8.0):
		_free_rig(rig)
		return
	check(not arena.can_skip_cinematic() and not game.skip_boss_cinematic(),
		"3: skip at progress %.4f (%.4f s) was accepted" % [arena.cinematic_progress(), _cinematic_elapsed(arena)])
	var early := _tick_until(rig, func() -> bool:
		return _cinematic_elapsed(arena) + TICK >= SKIP_AFTER, 2.0)
	check(not arena.can_skip_cinematic() and not bool(game.skip_boss_cinematic()),
		"3: skip became legal at %.4f s, before boss_cinematic_skip_after %.2f (ticks %d)"
		% [_cinematic_elapsed(arena), SKIP_AFTER, early])
	_tick_rig(rig, 1)
	var opened_at := _cinematic_elapsed(arena)
	check(arena.can_skip_cinematic() and opened_at + 0.0001 >= SKIP_AFTER and opened_at < SKIP_AFTER + TICK * 2.0,
		"3: can_skip went true at %.4f s after %d sub-threshold ticks (skip_after %.2f)"
		% [opened_at, early, SKIP_AFTER])
	# The facade also refuses while paused, even though the encounter's own can_skip does not look
	# at game.paused (contract §11.4: running and unpaused).
	game.pause()
	var encounter_would := bool(arena.can_skip_cinematic())
	var paused_skip := bool(game.skip_boss_cinematic())
	check(not paused_skip, "3: skip_boss_cinematic during pause returned true (encounter can_skip %s, elapsed %.4f s)"
		% [encounter_would, _cinematic_elapsed(arena)])
	_resume(game)
	var skipped_before: int = int(events["skipped"].size())
	var ended_before: int = int(events["ended"].size())
	var did_skip := bool(game.skip_boss_cinematic())
	var seconds := float(arena.cinematic_seconds)
	var jumped := (seconds - SKIP_TAIL) / seconds
	check(did_skip, "3: skip_boss_cinematic returned false at %.4f s" % _cinematic_elapsed(arena))
	check(is_equal_approx(arena.cinematic_progress(), jumped) and is_equal_approx(game.boss_cinematic_progress, jumped),
		"3: progress %.6f (mirror %.6f), expected (%.3f - %.3f) / %.3f = %.6f"
		% [arena.cinematic_progress(), game.boss_cinematic_progress, seconds, SKIP_TAIL, seconds, jumped])
	check(events["skipped"].size() == skipped_before + 1 and StringName(events["skipped"].back()) == &"intro_full",
		"3: boss_cinematic_skipped %s, expected one intro_full" % [events["skipped"]])
	var mirror: Dictionary = _last_mirror(events, "mirror_skip")
	check(not bool(mirror.get("hold", true)) and is_equal_approx(float(mirror.get("progress", -1.0)), jumped),
		"3: on the skipped signal the mirror read progress %.4f hold %s"
		% [float(mirror.get("progress", -1.0)), mirror.get("hold", "<missing>")])
	var again := bool(game.skip_boss_cinematic())
	check(not again and events["skipped"].size() == skipped_before + 1,
		"3: a second skip returned %s and skipped is now %s" % [again, events["skipped"]])
	var threat_during := ""
	var tail_ticks := 0
	var guard := _ticks(SKIP_TAIL + 1.0)
	var threat_base := _threat_now(rig)
	while events["ended"].size() == ended_before and tail_ticks < guard:
		_tick_rig(rig, 1)
		tail_ticks += 1
		var text := _threat_delta(rig, threat_base)
		if text != "":
			threat_during = text
			break
	var tail_elapsed := tail_ticks * TICK
	check(events["ended"].size() == ended_before + 1,
		"3: boss_cinematic_ended %d time(s) after the skip, expected 1" % (events["ended"].size() - ended_before))
	check(absf(tail_elapsed - SKIP_TAIL) <= TICK + 0.0001,
		"3: the tail ran %.4f s (%d ticks), expected %.2f s within one tick" % [tail_elapsed, tail_ticks, SKIP_TAIL])
	check(threat_during == "", "3: a threat appeared during the tail (%s)" % threat_during)
	var after := _wait_for_threat(rig, "3: after tail", 3.0)
	var from_start := (early + 1 + tail_ticks + int(after["post_ticks"])) * TICK
	check(bool(after["appeared"]) and from_start + 0.0001 < INTRO_FULL and int(after["post_ticks"]) > 0,
		"3: first threat at %.4f s from the fight opening (%.4f s after the tail), expected after the tail and before the full %.1f s intro"
		% [from_start, int(after["post_ticks"]) * TICK, INTRO_FULL])
	note("3: skip opened at %.4f s, jumped to %.4f, tail %.4f s, first threat at %.4f s" % [opened_at, jumped, tail_elapsed, from_start])
	_free_rig(rig)
	_test_skip_inside_tail()

## Once the playhead is inside the last skip_tail seconds, skip is refused even though nobody skipped.
func _test_skip_inside_tail() -> void:
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	var game: Node = rig["game"]
	rig["stage"].begin()
	if not _require_boss(rig, "3: tail gate", 8.0):
		_free_rig(rig)
		return
	var seconds := float(arena.cinematic_seconds)
	var gate := seconds - SKIP_TAIL
	var before := _tick_until(rig, func() -> bool:
		return _cinematic_elapsed(arena) + TICK >= gate, seconds + 1.0)
	var still := _cinematic_elapsed(arena)
	check(arena.can_skip_cinematic() and still < gate,
		"3: can_skip was %s at %.4f s, one tick before the tail gate %.4f" % [arena.can_skip_cinematic(), still, gate])
	_tick_rig(rig, 1)
	var inside := _cinematic_elapsed(arena)
	check(not arena.can_skip_cinematic() and not game.skip_boss_cinematic() and inside + 0.0001 >= gate,
		"3: inside the tail (%.4f s, gate %.4f, %d ticks in) skip was still accepted" % [inside, gate, before + 1])
	note("3: unskipped tail gate refuses skip at %.4f s (gate %.4f)" % [inside, gate])
	_free_rig(rig)

# --- 4. Pause freezes the cinematic (contract §11.14) ------------------------------------------

func _test_pause() -> void:
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var stage: Node = rig["stage"]
	# Bound before begin(), so the overlay hears boss_cinematic instead of attaching after it.
	var ui := _mount_cinematic_ui(game)
	stage.begin()
	if not _require_boss(rig, "4: pause", 8.0):
		_resume(game)
		_free_cinematic_ui(ui)
		_free_rig(rig)
		return
	if ui != null:
		_check_overlay_advances(ui, rig)
	var progress: float = arena.cinematic_progress()
	var mirror := float(game.boss_cinematic_progress)
	game.pause()
	var pause_ticks := 60
	var frozen_before: Array = _ui_snapshot(ui) if ui != null else []
	if ui != null and ui.has_method("_process"):
		ui._process(1.0)
	_tick_rig(rig, pause_ticks)
	if ui != null and ui.has_method("_process"):
		ui._process(1.0)
	var frozen_after: Array = _ui_snapshot(ui) if ui != null else []
	check(game.paused and pause_ticks > 0 and arena.cinematic_progress() == progress and float(game.boss_cinematic_progress) == mirror,
		"4: %d paused ticks moved progress %.6f -> %.6f (mirror %.6f -> %.6f)"
		% [pause_ticks, progress, arena.cinematic_progress(), mirror, float(game.boss_cinematic_progress)])
	if ui != null:
		check(str(frozen_before) == str(frozen_after),
			"4: the boss cinematic overlay changed across _process(1.0) and %d paused ticks\n before %s\n after %s"
			% [pause_ticks, frozen_before, frozen_after])
	_resume(game)
	_tick_rig(rig, 60)
	var advanced: float = arena.cinematic_progress()
	check(advanced > progress + 0.15 and is_equal_approx(float(game.boss_cinematic_progress), advanced),
		"4: after resume, progress %.4f (mirror %.4f), from %.4f across 60 ticks of a %.1f s intro"
		% [advanced, float(game.boss_cinematic_progress), progress, float(arena.cinematic_seconds)])
	note("4: paused progress stayed %.6f, resumed to %.4f" % [progress, advanced])
	_resume(game)
	_free_cinematic_ui(ui)
	_free_rig(rig)

## The overlay is in the tree before the fight, so one unpaused tick that crosses the title
## (progress 0.40) has to change what it shows.
func _mount_cinematic_ui(game: Node) -> Node:
	if not ResourceLoader.exists(UI_SCENE):
		print("SKIP: %s is not in the project, so pause did not check the overlay's visible state" % UI_SCENE)
		return null
	var packed := load(UI_SCENE) as PackedScene
	if packed == null:
		check(false, "4: %s exists but did not load as a PackedScene" % UI_SCENE)
		return null
	var ui := packed.instantiate()
	root.add_child(ui)
	if ui.has_method("bind"):
		ui.bind(game)
	return ui

func _free_cinematic_ui(ui: Node) -> void:
	if ui != null and is_instance_valid(ui):
		ui.free()

func _check_overlay_advances(ui: Node, rig: Dictionary) -> void:
	var arena: Node = rig["arena"]
	var seconds: float = float(arena.cinematic_seconds)
	var step: float = TICK / maxf(seconds, TICK)
	var ticks := 0
	var guard := _ticks(seconds + 1.0)
	while float(arena.cinematic_progress()) + step < 0.40 and ticks < guard:
		_tick_rig(rig, 1)
		ticks += 1
	if ui.has_method("_process"):
		ui._process(TICK)
	var title: CanvasItem = ui.get("title_group") as CanvasItem
	var before_p: float = float(arena.cinematic_progress())
	var before_visible := false if title == null else bool(title.visible)
	var before := _ui_snapshot(ui)
	_tick_rig(rig, 1)
	if ui.has_method("_process"):
		ui._process(TICK)
	var after_p: float = float(arena.cinematic_progress())
	var after_visible := false if title == null else bool(title.visible)
	var after := _ui_snapshot(ui)
	check(before_p < 0.40 and after_p >= 0.40 and not before_visible and after_visible and str(before) != str(after),
		"4: one unpaused tick %.4f -> %.4f left the title %s -> %s (overlay %s)"
		% [before_p, after_p, before_visible, after_visible, "changed" if str(before) != str(after) else "unchanged"])

# --- 5. Defeat hold, and 9. Engine.time_scale (contract §11.14) --------------------------------

func _test_defeat_and_retreat() -> void:
	var rig := _stage_rig(_overrides({
		"boss_hp_scale": 0.001,
		"boss_timeout_seconds": 55.0,
		"boss_kill_bonus_base": KILL_BASE,
		"boss_kill_bonus_per_stage": KILL_PER_STAGE,
		"tool_bonus": TOOL_BONUS,
	}))
	if rig.is_empty():
		return
	var stage: Node = rig["stage"]
	stage.begin()
	var summary := []
	for index in 4:
		var tag := "5: stage %d" % (index + 1)
		if index == 0:
			if not _require_boss(rig, tag, 8.0):
				break
		elif not _advance_to_next_boss(rig, tag):
			break
		if not _skip_current_intro(rig, tag):
			break
		var measured := _kill_and_time(rig, tag, index == 0 or index == 3)
		summary.append(measured)
		if stage.phase != &"stage_clear" and stage.phase != &"run":
			if not _drive_to_phase(rig, &"stage_clear", 2.0) and stage.phase != &"run":
				check(false, "%s: left the defeat in phase %s" % [tag, stage.phase])
				break
	note("5: %s" % [", ".join(summary)])
	_free_rig(rig)
	_test_retreat()

func _kill_and_time(rig: Dictionary, tag: String, full_check: bool) -> String:
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var stage: Node = rig["stage"]
	var events: Dictionary = rig["events"]
	var score: Node = rig["score"]
	var kind := StringName(arena.kind)
	var first_defeat := true
	# Stage 4 repeats flaky. Stages 2 and 3 are the other two kinds, each still on its first defeat.
	if kind == &"flaky_test_swarm" and int(stage.stage_index) > 1:
		first_defeat = false
	var want_mode: StringName = &"defeat_full" if first_defeat else &"defeat_short"
	var want_seconds := DEFEAT_FULL if first_defeat else minf(DEFEAT_SHORT, DEFEAT_FULL)
	var kill_bonus := KILL_BASE + KILL_PER_STAGE * (int(stage.stage_index) - 1)
	check(int(arena.hp) == 1, "%s: HP is %d before the one tool, expected 1 (hp_scale %.4f, cycle %d)"
		% [tag, int(arena.hp), float(game.config.boss_hp_scale), BossDefs.cycle(int(stage.stage_index))])
	if int(arena.hp) != 1:
		return "%s hp %d" % [tag, int(arena.hp)]
	# Intro factor is 1 (contract §11.14). Defeat is the only cinematic that leaves 1.
	check(is_equal_approx(float(arena.time_factor()), 1.0),
		"%s: time_factor during / just after the intro is %.4f, expected 1" % [tag, float(arena.time_factor())])
	var bonus_before := int(score.bonus_total)
	var awarded_before: int = int(events["bonus_awarded"].size())
	var defeated_before: int = int(events["boss_defeated"].size())
	var cinematic_before: int = int(events["boss_cinematic"].size())
	var order_before: int = int(events["order"].size())
	var sentinel := saved_scale + 0.7
	if is_equal_approx(sentinel, 0.0):
		sentinel = 1.7
	Engine.time_scale = sentinel
	arena.apply_tool(&"unit_test")
	var shot: Array = events["boss_cinematic"].back() if events["boss_cinematic"].size() > cinematic_before else []
	var mode: StringName = shot[1] if shot.size() >= 2 else &""
	var seconds := float(shot[2]) if shot.size() >= 3 else -1.0
	var defeated: Array = events["boss_defeated"].back() if events["boss_defeated"].size() > defeated_before else []
	var defeated_bonus := int(defeated[1]) if defeated.size() >= 2 else -1
	var added: Array = events["bonus_awarded"].slice(awarded_before)
	var suffix: Array = events["order"].slice(order_before)
	check(_has_subsequence(suffix, [&"defeated", &"cinematic"]),
		"%s: order after the kill %s, expected defeated then cinematic on that call" % [tag, suffix])
	check(mode == want_mode and is_equal_approx(seconds, want_seconds),
		"%s: boss_cinematic %s %.4f s, expected %s %.4f s" % [tag, mode, seconds, want_mode, want_seconds])
	check(defeated_bonus == kill_bonus,
		"%s: boss_defeated bonus %d, expected %d + %d * %d = %d"
		% [tag, defeated_bonus, KILL_BASE, KILL_PER_STAGE, int(stage.stage_index) - 1, kill_bonus])
	check(_bonus_has(added, kill_bonus, &"boss_kill") and _bonus_has(added, TOOL_BONUS, &"tool"),
		"%s: bonus_awarded added %s, expected tool %d and boss_kill %d" % [tag, added, TOOL_BONUS, kill_bonus])
	check(int(score.bonus_total) == bonus_before + TOOL_BONUS + kill_bonus,
		"%s: bonus_total %d -> %d, expected +%d tool and +%d kill"
		% [tag, bonus_before, int(score.bonus_total), TOOL_BONUS, kill_bonus])
	check(stage.phase == &"boss", "%s: phase became %s on the kill tick, before the defeat cinematic" % [tag, stage.phase])
	check(is_equal_approx(float(arena.time_factor()), HIT_STOP_FACTOR)
		and is_equal_approx(float(game.boss_time_factor), HIT_STOP_FACTOR),
		"%s: defeat opened at time_factor %.4f mirror %.4f, expected %.2f"
		% [tag, float(arena.time_factor()), float(game.boss_time_factor), HIT_STOP_FACTOR])
	var factor_bad := ""
	var ticks := 0
	var guard := _ticks(want_seconds + 2.0)
	var ended_before: int = int(events["ended"].size())
	var scale_changed := false
	while stage.phase == &"boss" and ticks < guard:
		_tick_rig(rig, 1)
		ticks += 1
		if not is_equal_approx(Engine.time_scale, sentinel):
			scale_changed = true
		if factor_bad != "":
			continue
		var live := float(arena.time_factor())
		var mirror_factor := float(game.boss_time_factor)
		if StringName(arena.cinematic_mode) == want_mode:
			var elapsed := float(arena.cinematic_progress()) * seconds
			var expected := _profile(elapsed)
			if not is_equal_approx(live, expected) or not is_equal_approx(mirror_factor, live):
				factor_bad = "tick %d elapsed %.4f live %.4f profile %.4f mirror %.4f" % [ticks, elapsed, live, expected, mirror_factor]
		elif StringName(arena.cinematic_mode) == &"":
			if not is_equal_approx(live, 1.0) or not is_equal_approx(mirror_factor, 1.0):
				factor_bad = "end tick live %.4f mirror %.4f" % [live, mirror_factor]
		else:
			factor_bad = "mode %s" % arena.cinematic_mode
	var held := ticks * TICK
	if full_check:
		check(stage.phase == &"stage_clear", "%s: phase %s after %.4f s, expected stage_clear" % [tag, stage.phase, held])
		check(absf(held - want_seconds) <= TICK + 0.0001,
			"%s: stage_clear at %.4f s (%d ticks), defeat cinematic %.4f s (within one tick)" % [tag, held, ticks, want_seconds])
		check(events["ended"].size() == ended_before + 1,
			"%s: boss_cinematic_ended fired %d time(s) for the defeat, expected 1" % [tag, events["ended"].size() - ended_before])
	check(factor_bad == "", "8: live time_factor left the profile on %s (%s)" % [tag, factor_bad])
	check(not scale_changed and is_equal_approx(Engine.time_scale, sentinel),
		"9: Engine.time_scale is %.4f after the defeat cinematic, started at %.4f" % [Engine.time_scale, sentinel])
	Engine.time_scale = saved_scale
	return "%s %s %.3fs clear@%.3fs bonus %d" % [kind, mode, seconds, held, defeated_bonus]

func _test_retreat() -> void:
	var rig := _stage_rig(_overrides({"boss_timeout_seconds": 0.05}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var stage: Node = rig["stage"]
	var events: Dictionary = rig["events"]
	rig["stage"].begin()
	if not _require_boss(rig, "5: retreat", 8.0):
		_free_rig(rig)
		return
	if not _skip_current_intro(rig, "5: retreat intro"):
		_free_rig(rig)
		return
	var cinematic_at: int = int(events["boss_cinematic"].size())
	var ended_at: int = int(events["ended"].size())
	var retreated_at: int = int(events["boss_retreated"].size())
	var ticks := 0
	var guard := _ticks(2.0)
	while events["boss_retreated"].size() == retreated_at and ticks < guard and stage.phase == &"boss":
		_tick_rig(rig, 1)
		ticks += 1
	check(events["boss_retreated"].size() == retreated_at + 1,
		"5: retreat did not fire (phase %s, fight_timer tick-in %d)" % [stage.phase, ticks])
	var hold_ticks := 0
	var hold_guard := _ticks(OUTRO + 2.0)
	var mode_during := &""
	while stage.phase == &"boss" and hold_ticks < hold_guard:
		if StringName(arena.cinematic_mode) != &"":
			mode_during = StringName(arena.cinematic_mode)
		if bool(stage.cinematic_hold):
			mode_during = &"hold"
		_tick_rig(rig, 1)
		hold_ticks += 1
	var held := hold_ticks * TICK
	check(stage.phase == &"stage_clear", "5: retreat ended in phase %s" % stage.phase)
	check(absf(held - float(game.config.boss_outro_seconds)) <= TICK + 0.0001
		and is_equal_approx(float(game.config.boss_outro_seconds), OUTRO),
		"5: retreat held %.4f s (%d ticks), expected boss_outro_seconds %.3f within one tick"
		% [held, hold_ticks, float(game.config.boss_outro_seconds)])
	check(events["boss_cinematic"].size() == cinematic_at and events["ended"].size() == ended_at and mode_during == &"",
		"5: retreat grew a cinematic (shots %d -> %d, ended %d -> %d, saw %s)"
		% [cinematic_at, events["boss_cinematic"].size(), ended_at, events["ended"].size(), mode_during])
	note("5: retreat held %.4f s with no cinematic" % held)
	_free_rig(rig)

# --- 6 and 7. Hold, controls, speed, abort, catch (contract §11.14) ----------------------------

func _test_hold_and_abort() -> void:
	_test_hold_skip()
	_test_hold_end()
	_test_abort()
	_test_catch()

func _test_hold_skip() -> void:
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var stage: Node = rig["stage"]
	var speed: Node = rig["speed"]
	var player := _attach_controls(game)
	stage.begin()
	if not _require_boss(rig, "6: hold", 8.0):
		_free_rig(rig)
		return
	var full_speed := float(game.speed)
	var clock := float(stage.run_clock)
	check(bool(stage.cinematic_hold) and not bool(player.controls_enabled),
		"6: at the intro, hold %s controls %s" % [stage.cinematic_hold, player.controls_enabled])
	_tick_rig(rig, 8)
	check(float(speed.cinematic_scale) > 0.55 and float(speed.cinematic_scale) < 0.95,
		"6: cinematic_scale %.4f after 8 ticks, expected mid-ease from 1 toward %.2f" % [float(speed.cinematic_scale), SPEED_SCALE])
	_tick_rig(rig, _ticks(EASE_SECONDS) - 8)
	check(absf(float(speed.cinematic_scale) - SPEED_SCALE) < 0.02,
		"6: cinematic_scale %.4f after %.2f s, expected %.2f" % [float(speed.cinematic_scale), EASE_SECONDS, SPEED_SCALE])
	check(float(game.speed) < full_speed * 0.5 and absf(float(game.speed) - full_speed * SPEED_SCALE) < maxf(full_speed * 0.05, 0.05),
		"6: corridor speed %.4f, from %.4f, expected about %.4f while the intro holds"
		% [float(game.speed), full_speed, full_speed * SPEED_SCALE])
	check(is_equal_approx(float(stage.run_clock), clock) and is_equal_approx(float(game.run_clock), clock),
		"6: run_clock %.4f / %.4f, expected it to stay %.4f through the intro" % [float(stage.run_clock), float(game.run_clock), clock])
	game.set_autopilot(true)
	game.set_autopilot(false)
	check(not bool(player.controls_enabled) and not bool(game.autopilot.enabled),
		"6: set_autopilot(false) during the hold left controls %s (bot %s)"
		% [player.controls_enabled, game.autopilot.enabled])
	var ready := _tick_until(rig, func() -> bool: return bool(arena_can_skip(rig)), 2.0)
	if not arena_can_skip(rig):
		_tick_rig(rig, 1)
	check(bool(game.skip_boss_cinematic()), "6: could not skip once the ease and the skip gate had both passed (ticks %d)" % ready)
	check(not bool(stage.cinematic_hold) and bool(player.controls_enabled),
		"6: after the skip, hold %s controls %s (the tail must give controls back)" % [stage.cinematic_hold, player.controls_enabled])
	_tick_rig(rig, _ticks(EASE_SECONDS))
	check(absf(float(speed.cinematic_scale) - 1.0) < 0.02,
		"6: cinematic_scale %.4f after the skip's %.2f s ease, expected 1" % [float(speed.cinematic_scale), EASE_SECONDS])
	check(absf(float(game.speed) - full_speed) < maxf(full_speed * 0.05, 0.05),
		"6: corridor speed %.4f after the skip, expected back near %.4f" % [float(game.speed), full_speed])
	note("6: hold scale %.4f speed %.3f -> %.3f, skip restored scale %.4f speed %.3f, run_clock %.4f"
		% [SPEED_SCALE, full_speed, full_speed * SPEED_SCALE, float(speed.cinematic_scale), float(game.speed), clock])
	_free_rig(rig)

func _test_hold_end() -> void:
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var stage: Node = rig["stage"]
	var speed: Node = rig["speed"]
	var events: Dictionary = rig["events"]
	var player := _attach_controls(game)
	stage.begin()
	if not _require_boss(rig, "6: end", 8.0):
		_free_rig(rig)
		return
	var full_speed := float(game.speed)
	var ended_before: int = int(events["ended"].size())
	var window := _play_intro(rig, "6: end")
	check(int(window["ended_delta"]) == 1 and events["ended"].size() == ended_before + 1,
		"6: playing the intro out fired ended %d time(s)" % int(window["ended_delta"]))
	check(not bool(stage.cinematic_hold) and bool(player.controls_enabled),
		"6: at intro end, hold %s controls %s" % [stage.cinematic_hold, player.controls_enabled])
	var mirror: Dictionary = _last_mirror(events, "mirror_end")
	check(StringName(mirror.get("mode", &"x")) == &"" and is_equal_approx(float(mirror.get("progress", -1.0)), 0.0)
		and is_equal_approx(float(mirror.get("factor", -1.0)), 1.0),
		"6: mirror at ended is mode %s progress %.4f factor %.4f"
		% [mirror.get("mode", &""), float(mirror.get("progress", -1.0)), float(mirror.get("factor", -1.0))])
	_tick_rig(rig, _ticks(EASE_SECONDS))
	check(absf(float(speed.cinematic_scale) - 1.0) < 0.02 and absf(float(game.speed) - full_speed) < maxf(full_speed * 0.05, 0.05),
		"6: after the intro ended, scale %.4f speed %.4f, expected scale 1 and speed near %.4f"
		% [float(speed.cinematic_scale), float(game.speed), full_speed])
	note("6: natural end restored scale %.4f speed %.3f (from %.3f)" % [float(speed.cinematic_scale), float(game.speed), full_speed])
	_free_rig(rig)

func _test_abort() -> void:
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var stage: Node = rig["stage"]
	var speed: Node = rig["speed"]
	var events: Dictionary = rig["events"]
	var player := _attach_controls(game)
	stage.begin()
	if not _require_boss(rig, "7: abort", 8.0):
		_free_rig(rig)
		return
	var full_speed := float(game.speed)
	_tick_rig(rig, 10)
	var ended_before: int = int(events["ended"].size())
	arena.abort()
	check(events["ended"].size() == ended_before + 1,
		"7: abort fired boss_cinematic_ended %d time(s), expected 1" % (events["ended"].size() - ended_before))
	check(not bool(stage.cinematic_hold) and bool(player.controls_enabled),
		"7: after abort, hold %s controls %s" % [stage.cinematic_hold, player.controls_enabled])
	check(StringName(game.boss_cinematic_mode) == &"" and is_equal_approx(float(game.boss_cinematic_progress), 0.0)
		and is_equal_approx(float(game.boss_time_factor), 1.0),
		"7: mirrors after abort are mode %s progress %.4f factor %.4f, expected empty / 0 / 1"
		% [game.boss_cinematic_mode, float(game.boss_cinematic_progress), float(game.boss_time_factor)])
	_tick_rig(rig, _ticks(EASE_SECONDS))
	check(absf(float(speed.cinematic_scale) - 1.0) < 0.02 and absf(float(game.speed) - full_speed) < maxf(full_speed * 0.05, 0.05),
		"7: after abort, scale %.4f speed %.4f, expected scale 1 and speed near %.4f"
		% [float(speed.cinematic_scale), float(game.speed), full_speed])
	note("7: abort ended once, mirrors clear, scale %.4f speed %.3f" % [float(speed.cinematic_scale), float(game.speed)])
	_free_rig(rig)

func _test_catch() -> void:
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var stage: Node = rig["stage"]
	var speed: Node = rig["speed"]
	var hits: Node = rig["hits"]
	var events: Dictionary = rig["events"]
	var player := _attach_controls(game)
	stage.begin()
	if not _require_boss(rig, "7: catch", 8.0):
		_free_rig(rig)
		return
	_tick_rig(rig, _ticks(EASE_SECONDS))
	var ended_before: int = int(events["ended"].size())
	var scale_before := float(speed.cinematic_scale)
	hits.report_hit(_hazard())
	hits.iframe_remaining = 0.0
	hits.report_hit(_hazard())
	check(game.state == &"caught" and stage.phase == &"idle",
		"7: catch left state %s phase %s" % [game.state, stage.phase])
	check(events["ended"].size() == ended_before + 1,
		"7: catch fired boss_cinematic_ended %d time(s), expected 1" % (events["ended"].size() - ended_before))
	check(not bool(player.controls_enabled),
		"6: catch left controls enabled (%s); they have to stay off" % player.controls_enabled)
	check(StringName(game.boss_cinematic_mode) == &"" and is_equal_approx(float(game.boss_cinematic_progress), 0.0)
		and is_equal_approx(float(game.boss_time_factor), 1.0),
		"7: mirrors after the catch are mode %s progress %.4f factor %.4f"
		% [game.boss_cinematic_mode, float(game.boss_cinematic_progress), float(game.boss_time_factor)])
	_tick_rig(rig, _ticks(EASE_SECONDS) + 2)
	var target := float(speed._cinematic_target) if &"_cinematic_target" in speed else -1.0
	check(absf(float(speed.cinematic_scale) - 1.0) < 0.02,
		"6: after the catch, cinematic_scale %.4f (target %.4f, was %.4f at the hit) did not ease back to 1 within %.2f s"
		% [float(speed.cinematic_scale), target, scale_before, EASE_SECONDS])
	note("6/7: catch controls %s scale %.4f -> %.4f (target %.4f) phase %s" % [
		player.controls_enabled, scale_before, float(speed.cinematic_scale), target, stage.phase])
	_free_rig(rig)

# --- 10. Visual feed (contract §11.5, §11.14) --------------------------------------------------

func _test_visual_feed() -> void:
	_test_feed_intro_skip()
	_test_feed_abort()
	_test_feed_defeat()

## start() mounts the graybox and plays the intro before it returns, so the recorder swapped in
## afterwards sees the intro from the next tick on. The play_cinematic -> progress 0 opening is
## asserted on the defeat, which begins after the swap.
func _test_feed_intro_skip() -> void:
	var rig := _boss_rig(_overrides({}))
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	var game: Node = rig["game"]
	var events: Dictionary = rig["events"]
	arena.start(1)
	var rec := _mount_recorder(arena)
	if rec == null:
		check(false, "10: the intro recorder did not mount")
		_free_rig(rig)
		return
	rec.calls.clear()
	var bad := ""
	var prev := -1.0
	var ticks := 0
	var guard := _ticks(SKIP_AFTER + 1.0)
	while not arena.can_skip_cinematic() and StringName(arena.cinematic_mode) != &"" and ticks < guard and bad == "":
		bad = _feed_tick(arena, rec, &"intro_full", prev, false)
		prev = _last_progress(rec)
		ticks += 1
	check(bad == "" and ticks > 0, "10: intro feed before the skip gate (%s, %d ticks)" % [bad, ticks])
	var before: int = int(rec.calls.size())
	var did := bool(arena.skip_cinematic())
	var jumped := (float(arena.cinematic_seconds) - SKIP_TAIL) / float(arena.cinematic_seconds)
	var jump_progress := _last_progress_call(rec, before)
	check(did and jump_progress.size() == 2 and StringName(jump_progress[0]) == &"intro_full"
		and is_equal_approx(float(jump_progress[1]), jumped)
		and is_equal_approx(float(arena.cinematic_progress()), jumped),
		"10: skip feed %s, arena progress %.6f, expected intro_full %.6f" % [jump_progress, float(arena.cinematic_progress()), jumped])
	var size_after_skip: int = int(rec.calls.size())
	check(not arena.skip_cinematic() and rec.calls.size() == size_after_skip,
		"10: a second skip added feed calls (%d -> %d)" % [size_after_skip, rec.calls.size()])
	prev = float(jump_progress[1]) if jump_progress.size() == 2 else prev
	var ended_before: int = int(events["ended"].size())
	var snap := {"calls": [], "mode": &""}
	var on_ended := func(mode: StringName) -> void:
		snap["calls"] = rec.calls.duplicate(true)
		snap["mode"] = mode
	game.boss_cinematic_ended.connect(on_ended)
	bad = ""
	var tail := 0
	while StringName(arena.cinematic_mode) != &"" and tail < _ticks(SKIP_TAIL + 1.0) and bad == "":
		var mode_before := StringName(arena.cinematic_mode)
		bad = _feed_tick(arena, rec, mode_before, prev, false)
		if StringName(arena.cinematic_mode) == &"":
			bad = ""
			break
		prev = _last_progress(rec)
		tail += 1
	if game.boss_cinematic_ended.is_connected(on_ended):
		game.boss_cinematic_ended.disconnect(on_ended)
	var end_progress := _last_named(snap["calls"], &"set_cinematic_progress")
	var end_factor := _last_named(snap["calls"], &"set_time_factor")
	check(events["ended"].size() == ended_before + 1 and StringName(snap["mode"]) == &"intro_full",
		"10: intro ended %d time(s) as %s" % [events["ended"].size() - ended_before, snap["mode"]])
	check(end_progress.size() == 2 and StringName(end_progress[0]) == &"intro_full" and is_equal_approx(float(end_progress[1]), 1.0)
		and end_factor.size() == 1 and is_equal_approx(float(end_factor[0]), 1.0),
		"10: final intro feed before ended was progress %s factor %s, expected (intro_full, 1) then 1"
		% [end_progress, end_factor])
	check(bad == "", "10: intro feed after the skip (%s)" % bad)
	note("10: intro feed %d ticks to the skip, jump %.4f, tail %d ticks, final %s" % [ticks, jumped, tail, end_progress])
	_free_rig(rig)

func _test_feed_abort() -> void:
	var rig := _boss_rig(_overrides({}))
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	var game: Node = rig["game"]
	var events: Dictionary = rig["events"]
	arena.start(1)
	var rec := _mount_recorder(arena)
	if rec == null:
		check(false, "10: the abort recorder did not mount")
		_free_rig(rig)
		return
	rec.calls.clear()
	for _i in 8:
		arena.tick(TICK)
	var ended_before: int = int(events["ended"].size())
	var snap := {"calls": [], "mode": &""}
	game.boss_cinematic_ended.connect(func(mode: StringName) -> void:
		snap["calls"] = rec.calls.duplicate(true)
		snap["mode"] = mode
	, CONNECT_ONE_SHOT)
	arena.abort()
	var end_progress := _last_named(snap["calls"], &"set_cinematic_progress")
	var end_factor := _last_named(snap["calls"], &"set_time_factor")
	check(events["ended"].size() == ended_before + 1 and StringName(snap["mode"]) == &"intro_full",
		"10: abort emitted ended %d time(s) as %s" % [events["ended"].size() - ended_before, snap["mode"]])
	check(end_progress.size() == 2 and StringName(end_progress[0]) == &"intro_full" and is_equal_approx(float(end_progress[1]), 1.0)
		and end_factor.size() == 1 and is_equal_approx(float(end_factor[0]), 1.0),
		"10: abort's final feed before ended was progress %s factor %s, expected (intro_full, 1) then 1"
		% [end_progress, end_factor])
	check(rec.calls.size() == (snap["calls"] as Array).size(),
		"10: abort added %d feed call(s) after boss_cinematic_ended" % (rec.calls.size() - (snap["calls"] as Array).size()))
	note("10: abort final feed %s factor %s" % [end_progress, end_factor])
	_free_rig(rig)

func _test_feed_defeat() -> void:
	var rig := _boss_rig(_overrides({"boss_hp_scale": 0.001}))
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	var game: Node = rig["game"]
	var events: Dictionary = rig["events"]
	arena.start(1)
	var rec := _mount_recorder(arena)
	if rec == null:
		check(false, "10: the defeat recorder did not mount")
		_free_rig(rig)
		return
	if not _skip_arena_intro(arena):
		check(false, "10: the defeat rig's intro never ended (mode %s)" % arena.cinematic_mode)
		_free_rig(rig)
		return
	var ended_before: int = int(events["ended"].size())
	rec.calls.clear()
	arena.apply_tool(&"unit_test")
	var opening: Array = rec.calls.duplicate(true)
	var names := _call_names(opening)
	check(_same(names.slice(0, 5), [&"set_health", &"play_defeat", &"play_cinematic", &"set_cinematic_progress", &"set_time_factor"]),
		"10: defeat opened with %s, expected set_health, play_defeat, play_cinematic, set_cinematic_progress, set_time_factor" % [names])
	var health_args: Array = opening[0][1] if not opening.is_empty() else []
	var played: Array = opening[2][1] if opening.size() >= 3 else []
	var progressed: Array = opening[3][1] if opening.size() >= 4 else []
	var factored: Array = opening[4][1] if opening.size() >= 5 else []
	var seconds := float(arena.cinematic_seconds)
	check(health_args.size() == 2 and int(health_args[0]) == 0 and int(health_args[1]) == int(arena.max_hp)
		and played.size() == 2 and StringName(played[0]) == &"defeat_full" and is_equal_approx(float(played[1]), DEFEAT_FULL)
		and progressed.size() == 2 and StringName(progressed[0]) == &"defeat_full" and is_equal_approx(float(progressed[1]), 0.0)
		and factored.size() == 1 and is_equal_approx(float(factored[0]), HIT_STOP_FACTOR),
		"10: defeat opening args health %s play %s progress %s factor %s, expected set_health(0, %d), defeat_full %.1f, progress 0, factor %.2f"
		% [health_args, played, progressed, factored, int(arena.max_hp), DEFEAT_FULL, HIT_STOP_FACTOR])
	var snap := {"calls": [], "mode": &""}
	game.boss_cinematic_ended.connect(func(mode: StringName) -> void:
		snap["calls"] = rec.calls.duplicate(true)
		snap["mode"] = mode
	, CONNECT_ONE_SHOT)
	var bad := ""
	var prev := 0.0
	var ticks := 0
	var guard := _ticks(DEFEAT_FULL + 1.0)
	while StringName(arena.cinematic_mode) == &"defeat_full" and ticks < guard and bad == "":
		bad = _feed_tick(arena, rec, &"defeat_full", prev, true, seconds)
		if StringName(arena.cinematic_mode) == &"":
			bad = ""
			break
		prev = _last_progress(rec)
		ticks += 1
	var end_progress := _last_named(snap["calls"], &"set_cinematic_progress")
	var end_factor := _last_named(snap["calls"], &"set_time_factor")
	check(bad == "", "10: defeat feed (%s)" % bad)
	check(StringName(snap["mode"]) == &"defeat_full"
		and end_progress.size() == 2 and is_equal_approx(float(end_progress[1]), 1.0)
		and end_factor.size() == 1 and is_equal_approx(float(end_factor[0]), 1.0)
		and is_equal_approx(float(end_factor[0]), _profile(seconds)),
		"10: defeat final feed before ended was %s / %s (profile at %.3f s is %.4f), ended mode %s"
		% [end_progress, end_factor, seconds, _profile(seconds), snap["mode"]])
	check(events["ended"].size() == ended_before + 1 and StringName(snap["mode"]) == &"defeat_full",
		"10: defeat emitted boss_cinematic_ended %d time(s) as %s, expected 1 defeat_full"
		% [events["ended"].size() - ended_before, snap["mode"]])
	note("10: defeat opening %s, %d feed ticks, final %s factor %s" % [names.slice(0, 5), ticks, end_progress, end_factor])
	_free_rig(rig)

## One non-ending tick: exactly one progress call matching cinematic_progress(), then one factor.
## `defeat` compares the factor to the profile; an intro's factor is exactly 1.
func _feed_tick(arena: Node, rec: Node, mode: StringName, prev: float, defeat: bool, seconds := 0.0) -> String:
	var before: int = int(rec.calls.size())
	arena.tick(TICK)
	if StringName(arena.cinematic_mode) == &"":
		return ""
	var added: Array = rec.calls.slice(before)
	if added.size() != 2:
		return "tick added %s, expected progress then factor" % [added]
	var progress_call: Array = added[0]
	var factor_call: Array = added[1]
	if StringName(progress_call[0]) != &"set_cinematic_progress" or StringName(factor_call[0]) != &"set_time_factor":
		return "tick added %s / %s" % [progress_call[0], factor_call[0]]
	var args: Array = progress_call[1]
	var progress: float = float(args[1])
	if StringName(args[0]) != mode or not is_equal_approx(progress, float(arena.cinematic_progress())):
		return "progress %s, arena %.6f mode %s" % [args, float(arena.cinematic_progress()), arena.cinematic_mode]
	if progress + 0.000001 < prev:
		return "progress fell %.6f -> %.6f" % [prev, progress]
	var factor := float((factor_call[1] as Array)[0])
	var expected := _profile(progress * seconds) if defeat else 1.0
	if not is_equal_approx(factor, expected) or not is_equal_approx(factor, float(arena.time_factor())):
		return "factor %.4f, profile %.4f, live %.4f at progress %.4f" % [factor, expected, float(arena.time_factor()), progress]
	return ""

# --- 3. A real jump press skips and does not jump ----------------------------------------------

func _test_real_input() -> void:
	_release_jump()
	paused = false
	Engine.time_scale = saved_scale
	var packed := load(GAME_SCENE) as PackedScene
	if packed == null:
		check(false, "3: runner_game.tscn failed to load")
		return
	var game := packed.instantiate() as Node3D
	game.autostart = false
	game.config = _configured(_overrides({}))
	# Before add_child: the packed scene already carries the script, so _ready would otherwise write
	# the real user://leaderboard.cfg the moment the run starts.
	game.leaderboard_path = scratch_leaderboard
	live_scene = game
	root.add_child(game)
	await process_frame
	if bool(game.paused):
		game.resume()
	var jumps := {"n": 0}
	var skipped := {"n": 0}
	game.player_action.connect(func(action: StringName) -> void:
		if action == &"jump":
			jumps["n"] += 1)
	game.boss_cinematic_skipped.connect(func(_mode: StringName) -> void:
		skipped["n"] += 1)
	game.start_run(11)
	var reached := await _wait_until(func() -> bool:
		return game.phase == &"boss" and StringName(game.boss_cinematic_mode) != &"", 20.0)
	if bool(game.paused):
		game.resume()
	check(reached, "3: the real scene never opened a cinematic (phase %s, mode %s)" % [game.phase, game.boss_cinematic_mode])
	if not reached:
		_release_jump()
		_free_live_scene()
		return
	var player: Node = game.player
	var y0 := float(player.global_position.y)
	var early_progress := float(game.boss_cinematic_progress)
	_press_jump(game)
	for _i in 8:
		await physics_frame
	var early_after := float(game.boss_cinematic_progress)
	check(int(skipped["n"]) == 0 and early_after < SKIP_AFTER,
		"3: the jump press before %.2f s skipped (skipped %d, progress %.4f -> %.4f)"
		% [SKIP_AFTER, int(skipped["n"]), early_progress, early_after])
	check(int(jumps["n"]) == 0 and not bool(player.is_airborne) and float(player.global_position.y) <= y0 + 0.05
		and float(player.velocity.y) < 1.0,
		"3: the early jump press left the floor (airborne %s, y %.3f -> %.3f, vy %.3f, player_action jump %d)"
		% [player.is_airborne, y0, float(player.global_position.y), float(player.velocity.y), int(jumps["n"])])
	var skippable := await _wait_until(func() -> bool:
		return game.boss_encounter != null and bool(game.boss_encounter.can_skip_cinematic()), 5.0)
	check(skippable, "3: the real cinematic never reached the skip gate (progress %.4f, paused %s)"
		% [float(game.boss_cinematic_progress), game.paused])
	if not skippable:
		_release_jump()
		_free_live_scene()
		return
	if bool(game.paused):
		game.resume()
	var y1 := float(player.global_position.y)
	_press_jump(game)
	for _i in 8:
		await physics_frame
	check(int(skipped["n"]) == 1 and float(game.boss_cinematic_progress) + 0.0001 >= (INTRO_FULL - SKIP_TAIL) / INTRO_FULL - 0.02,
		"3: the jump press after the skip gate did not skip (skipped %d, progress %.4f)"
		% [int(skipped["n"]), float(game.boss_cinematic_progress)])
	check(int(jumps["n"]) == 0 and not bool(player.is_airborne) and float(player.global_position.y) <= y1 + 0.05
		and float(player.velocity.y) < 1.0,
		"3: the skipping press still jumped (airborne %s, y %.3f -> %.3f, vy %.3f, player_action jump %d)"
		% [player.is_airborne, y1, float(player.global_position.y), float(player.velocity.y), int(jumps["n"])])
	var skipped_at := int(skipped["n"])
	_press_jump(game)
	await physics_frame
	check(int(skipped["n"]) == skipped_at and not bool(game.skip_boss_cinematic()),
		"3: a second real press skipped again (%d -> %d)" % [skipped_at, int(skipped["n"])])
	note("3: real jump ignored at progress %.4f, skipped at progress %.4f, airborne %s, jump signals %d"
		% [early_after, float(game.boss_cinematic_progress), player.is_airborne, int(jumps["n"])])
	_release_jump()
	_free_live_scene()

# --- 11. Defeats are unskippable, and 12. bosses_defeated_kinds (contract §11.14, §11.13) -------

## One run: the stage-1 kill is defeat_full and cannot be skipped, then a stage-index jump reaches
## stage 4 still carrying only that defeat. Its _enter_boss snapshot is the retry source. The same
## kind's defeat_short is walked the same way. Intros stay skippable (case 3).
func _test_unskippable_defeats() -> void:
	runner_game_script.set(&"pending_boss_checkpoint", {})
	var rig := _stage_rig(_overrides({
		"boss_hp_scale": 0.001,
		"boss_timeout_seconds": 55.0,
	}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var stage: Node = rig["stage"]
	stage.begin()
	if not _require_boss(rig, "11: defeat_full", 8.0):
		_free_rig(rig)
		return
	var stage1: Dictionary = (game.boss_checkpoint as Dictionary).duplicate(true)
	var beaten_early: Array = stage1.get("bosses_defeated_kinds", ["<missing>"])
	check(beaten_early.is_empty() and _has_kind(stage1.get("bosses_met", []), &"flaky_test_swarm"),
		"12: stage-1 boss-entry checkpoint bosses_defeated_kinds %s bosses_met %s, expected none beaten and flaky met"
		% [beaten_early, stage1.get("bosses_met", [])])
	if not _skip_current_intro(rig, "11: intro"):
		_free_rig(rig)
		return
	if not _walk_unskippable_defeat(rig, "11: defeat_full", &"defeat_full", DEFEAT_FULL):
		_free_rig(rig)
		return
	# The clear that is already open would advance 1 -> 2. Park the index so that increment lands
	# on stage 4 (same kind, cycle 1) without beating the bosses in between. The checkpoint itself
	# still comes from _enter_boss.
	stage.stage_index = 3
	if not _advance_to_next_boss(rig, "12: stage 4"):
		_free_rig(rig)
		return
	var stage4: Dictionary = (game.boss_checkpoint as Dictionary).duplicate(true)
	var beaten: Array = stage4.get("bosses_defeated_kinds", [])
	var intro: Array = (rig["events"] as Dictionary)["boss_cinematic"].back()
	var intro_mode: StringName = intro[1] if intro.size() >= 2 else &""
	check(int(stage.stage_index) == 4 and int(stage4.get("stage_index", 0)) == 4,
		"12: stage-4 entry is stage %s (checkpoint stage %s)" % [stage.stage_index, stage4.get("stage_index", "<missing>")])
	check(beaten.size() == 1 and StringName(beaten[0]) == &"flaky_test_swarm",
		"12: stage-4 boss-entry bosses_defeated_kinds %s, expected [&\"flaky_test_swarm\"]" % [beaten])
	check(intro_mode == &"intro_short",
		"12: stage 4 opened %s, expected intro_short (flaky was already met)" % intro_mode)
	if not _skip_current_intro(rig, "11: stage 4 intro"):
		_free_rig(rig)
		return
	if not _walk_unskippable_defeat(rig, "11: defeat_short", &"defeat_short", minf(DEFEAT_SHORT, DEFEAT_FULL)):
		_free_rig(rig)
		return
	_free_rig(rig)
	_retry_defeat(stage4, "12: stage 4 begin_at_boss", false, &"defeat_short", minf(DEFEAT_SHORT, DEFEAT_FULL))
	_retry_defeat(stage4, "12: stage 4 start_run", true, &"defeat_short", minf(DEFEAT_SHORT, DEFEAT_FULL))
	_retry_defeat(stage1, "12: stage 1 retry", false, &"defeat_full", DEFEAT_FULL)
	runner_game_script.set(&"pending_boss_checkpoint", {})
	note("12: stage 4 checkpoint bosses_defeated_kinds %s retries as defeat_short; stage 1 retry stays defeat_full" % [beaten])

## Tick the whole defeat. Skip stays false on every frame, including past skip_after and before the
## last skip_tail, and stage_clear still waits the full length (contract §11.14 Skip).
func _walk_unskippable_defeat(rig: Dictionary, tag: String, want_mode: StringName, want_seconds: float) -> bool:
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var stage: Node = rig["stage"]
	var events: Dictionary = rig["events"]
	check(int(arena.hp) == 1, "%s: HP is %d before the kill, expected 1" % [tag, int(arena.hp)])
	if int(arena.hp) != 1:
		return false
	var skipped_before: int = int(events["skipped"].size())
	var ended_before: int = int(events["ended"].size())
	var cinematic_before: int = int(events["boss_cinematic"].size())
	arena.apply_tool(&"unit_test")
	var shot: Array = events["boss_cinematic"].back() if events["boss_cinematic"].size() > cinematic_before else []
	var mode: StringName = shot[1] if shot.size() >= 2 else &""
	var seconds := float(shot[2]) if shot.size() >= 3 else -1.0
	check(mode == want_mode and is_equal_approx(seconds, want_seconds),
		"%s: opened %s for %.4f s, expected %s %.4f s" % [tag, mode, seconds, want_mode, want_seconds])
	check(stage.phase == &"boss", "%s: phase became %s on the kill tick" % [tag, stage.phase])
	var bad := ""
	var saw_mid := false
	var max_elapsed := 0.0
	var mid_progress := -1.0
	var mid_ticks := -1
	var ticks := 0
	var guard := _ticks(want_seconds + 2.0)
	var opening := _refuse_defeat_skip(game, arena)
	if opening != "":
		bad = "at 0 s " + opening
	while stage.phase == &"boss" and ticks < guard:
		var elapsed := _cinematic_elapsed(arena)
		max_elapsed = maxf(max_elapsed, elapsed)
		if StringName(arena.cinematic_mode) == want_mode:
			if elapsed > SKIP_AFTER + TICK and elapsed + TICK < want_seconds - SKIP_TAIL:
				saw_mid = true
				if mid_ticks < 0:
					mid_progress = float(arena.cinematic_progress())
					mid_ticks = ticks
			var refused := _refuse_defeat_skip(game, arena)
			if bad == "" and refused != "":
				bad = "at %.4f s (tick %d) %s" % [elapsed, ticks, refused]
			var progress := float(arena.cinematic_progress())
			var expected := ticks * TICK / want_seconds
			if bad == "" and absf(progress - expected) > 3.0 * TICK / want_seconds:
				bad = "progress %.4f after %d ticks, expected %.4f (elapsed %.4f)" % [progress, ticks, expected, elapsed]
		_tick_rig(rig, 1)
		ticks += 1
	var held := ticks * TICK
	check(bad == "", "%s: %s" % [tag, bad])
	check(saw_mid, "%s: never sampled past %.2f s and before the last %.2f s (max elapsed %.4f s)"
		% [tag, SKIP_AFTER, SKIP_TAIL, max_elapsed])
	if mid_ticks >= 0:
		var mid_expected := mid_ticks * TICK / want_seconds
		check(absf(mid_progress - mid_expected) <= 3.0 * TICK / want_seconds and mid_progress < (want_seconds - SKIP_TAIL) / want_seconds,
			"%s: mid-defeat progress %.4f at tick %d, expected %.4f and still before the tail"
			% [tag, mid_progress, mid_ticks, mid_expected])
	check(stage.phase == &"stage_clear", "%s: phase %s after %.4f s, expected stage_clear" % [tag, stage.phase, held])
	check(absf(held - want_seconds) <= TICK + 0.0001,
		"%s: stage_clear at %.4f s (%d ticks), expected the full %.4f s within one tick" % [tag, held, ticks, want_seconds])
	check(events["skipped"].size() == skipped_before,
		"%s: boss_cinematic_skipped fired %d time(s) during the defeat" % [tag, events["skipped"].size() - skipped_before])
	check(events["ended"].size() == ended_before + 1,
		"%s: boss_cinematic_ended fired %d time(s), expected 1" % [tag, events["ended"].size() - ended_before])
	note("%s: %s %.3fs unskippable, clear@%.3fs, mid progress %.4f" % [tag, mode, seconds, held, mid_progress])
	return stage.phase == &"stage_clear" and bad == ""

func _refuse_defeat_skip(game: Node, arena: Node) -> String:
	var could := bool(arena.can_skip_cinematic())
	var encounter := bool(arena.skip_cinematic())
	var facade := bool(game.skip_boss_cinematic())
	if could or encounter or facade:
		return "can_skip %s, skip_cinematic %s, skip_boss_cinematic %s, progress %.4f mode %s" \
			% [could, encounter, facade, float(arena.cinematic_progress()), arena.cinematic_mode]
	return ""

## A checkpoint retry plays intro_short, then the defeat length the beaten-kind set asks for.
func _retry_defeat(checkpoint: Dictionary, tag: String, via_start_run: bool, want_mode: StringName, want_seconds: float) -> void:
	var rig := _stage_rig(_overrides({
		"boss_hp_scale": 0.001,
		"boss_timeout_seconds": 55.0,
	}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var stage: Node = rig["stage"]
	var events: Dictionary = rig["events"]
	if via_start_run:
		runner_game_script.set(&"pending_boss_checkpoint", checkpoint.duplicate(true))
		game.start_run(0)
		var pending: Variant = runner_game_script.get(&"pending_boss_checkpoint")
		check(pending is Dictionary and (pending as Dictionary).is_empty(),
			"%s: pending_boss_checkpoint was not consumed (%s)" % [tag, pending])
	else:
		stage.begin_at_boss(checkpoint.duplicate(true))
	if not _require_boss(rig, tag, 8.0):
		_free_rig(rig)
		return
	var shot: Array = events["boss_cinematic"].back()
	var intro: Array = events["boss_intro"].back()
	var mode: StringName = shot[1] if shot.size() >= 2 else &""
	var seconds := float(shot[2]) if shot.size() >= 3 else -1.0
	var intro_seconds := float(intro[2]) if intro.size() >= 3 else -1.0
	var want_intro := minf(INTRO_SHORT, INTRO_FULL)
	var want_stage := int(checkpoint.get("stage_index", -1))
	check(mode == &"intro_short" and is_equal_approx(seconds, want_intro) and is_equal_approx(intro_seconds, seconds),
		"%s: retry plays %s for %.4f s (boss_intro %.4f), expected intro_short %.4f s"
		% [tag, mode, seconds, intro_seconds, want_intro])
	check(int(stage.stage_index) == want_stage, "%s: retry opened on stage %d, checkpoint says %d" % [tag, int(stage.stage_index), want_stage])
	if not _skip_current_intro(rig, tag):
		_free_rig(rig)
		return
	var cinematic_before: int = int(events["boss_cinematic"].size())
	var skipped_before: int = int(events["skipped"].size())
	check(int(rig["arena"].hp) == 1, "%s: HP is %d before the retry kill, expected 1" % [tag, int(rig["arena"].hp)])
	rig["arena"].apply_tool(&"unit_test")
	var defeat: Array = events["boss_cinematic"].back() if events["boss_cinematic"].size() > cinematic_before else []
	var defeat_mode: StringName = defeat[1] if defeat.size() >= 2 else &""
	var defeat_seconds := float(defeat[2]) if defeat.size() >= 3 else -1.0
	check(defeat_mode == want_mode and is_equal_approx(defeat_seconds, want_seconds),
		"%s: kill plays %s for %.4f s, expected %s %.4f s" % [tag, defeat_mode, defeat_seconds, want_mode, want_seconds])
	var held_ticks := 0
	var guard := _ticks(want_seconds + 2.0)
	while stage.phase == &"boss" and held_ticks < guard:
		if bool(rig["arena"].can_skip_cinematic()) or bool(game.skip_boss_cinematic()):
			break
		_tick_rig(rig, 1)
		held_ticks += 1
	var held := held_ticks * TICK
	check(stage.phase == &"stage_clear" and absf(held - want_seconds) <= TICK + 0.0001,
		"%s: stage_clear at %.4f s in phase %s, expected %.4f s" % [tag, held, stage.phase, want_seconds])
	check(events["skipped"].size() == skipped_before,
		"%s: the retry defeat emitted boss_cinematic_skipped (%d)" % [tag, events["skipped"].size() - skipped_before])
	note("%s: intro_short then %s %.3fs, clear@%.3fs" % [tag, defeat_mode, defeat_seconds, held])
	_free_rig(rig)

## A real jump held through the middle of a defeat must not skip it (contract §11.14 Skip).
func _test_real_defeat_input() -> void:
	_release_jump()
	paused = false
	Engine.time_scale = saved_scale
	var packed := load(GAME_SCENE) as PackedScene
	if packed == null:
		check(false, "11: runner_game.tscn failed to load")
		return
	var game := packed.instantiate() as Node3D
	game.autostart = false
	game.config = _configured(_overrides({
		"boss_hp_scale": 0.001,
		"boss_timeout_seconds": 55.0,
	}))
	game.leaderboard_path = scratch_leaderboard
	live_scene = game
	root.add_child(game)
	await process_frame
	if bool(game.paused):
		game.resume()
	var jumps := {"n": 0}
	var skipped := {"n": 0}
	game.player_action.connect(func(action: StringName) -> void:
		if action == &"jump":
			jumps["n"] += 1)
	game.boss_cinematic_skipped.connect(func(_mode: StringName) -> void:
		skipped["n"] += 1)
	game.start_run(11)
	var reached := await _wait_until(func() -> bool:
		return game.phase == &"boss" and StringName(game.boss_cinematic_mode) != &"", 20.0)
	if bool(game.paused):
		game.resume()
	if not reached or game.boss_encounter == null:
		check(false, "11: the real scene never opened a boss cinematic (phase %s, mode %s)"
			% [game.phase, game.boss_cinematic_mode])
		_release_jump()
		_free_live_scene()
		return
	var arena: Node = game.boss_encounter
	check(int(arena.hp) == 1, "11: real boss HP is %d at the intro, expected 1" % int(arena.hp))
	if int(arena.hp) != 1:
		_release_jump()
		_free_live_scene()
		return
	arena.apply_tool(&"unit_test")
	check(StringName(game.boss_cinematic_mode) == &"defeat_full" and is_equal_approx(float(arena.cinematic_seconds), DEFEAT_FULL),
		"11: the kill opened %s for %.4f s, expected defeat_full %.4f s"
		% [game.boss_cinematic_mode, float(arena.cinematic_seconds), DEFEAT_FULL])
	var in_window := await _wait_until(func() -> bool:
		if StringName(game.boss_cinematic_mode) != &"defeat_full":
			return false
		var elapsed: float = float(game.boss_cinematic_progress) * float(arena.cinematic_seconds)
		return elapsed > SKIP_AFTER + 0.1 and elapsed < DEFEAT_FULL - SKIP_TAIL
	, 8.0)
	if bool(game.paused):
		game.resume()
	var elapsed_at := float(game.boss_cinematic_progress) * float(arena.cinematic_seconds)
	check(in_window, "11: the real defeat never sat past %.2f s (elapsed %.4f, mode %s)"
		% [SKIP_AFTER, elapsed_at, game.boss_cinematic_mode])
	if not in_window:
		_release_jump()
		_free_live_scene()
		return
	var player: Node = game.player
	var y0 := float(player.global_position.y)
	var progress_at := float(game.boss_cinematic_progress)
	_press_jump(game)
	for _i in 8:
		await physics_frame
	var progress_after := float(game.boss_cinematic_progress)
	check(int(skipped["n"]) == 0 and StringName(game.boss_cinematic_mode) == &"defeat_full"
		and progress_after > progress_at and progress_after < 0.5
		and not bool(arena.can_skip_cinematic()) and not bool(game.skip_boss_cinematic()),
		"11: the mid-defeat jump skipped (skipped %d, mode %s, progress %.4f -> %.4f, can_skip %s)"
		% [int(skipped["n"]), game.boss_cinematic_mode, progress_at, progress_after, arena.can_skip_cinematic()])
	check(int(jumps["n"]) == 0 and not bool(player.is_airborne) and float(player.global_position.y) <= y0 + 0.05
		and float(player.velocity.y) < 1.0,
		"11: the defeat press left the floor (airborne %s, y %.3f -> %.3f, vy %.3f, player_action jump %d)"
		% [player.is_airborne, y0, float(player.global_position.y), float(player.velocity.y), int(jumps["n"])])
	note("11: real jump at defeat elapsed %.3f s left progress %.4f -> %.4f, skipped %d, airborne %s"
		% [elapsed_at, progress_at, progress_after, int(skipped["n"]), player.is_airborne])
	_release_jump()
	_free_live_scene()

## start_run during a live intro closes it with one ended, then the new run's controls and
## corridor scale are back (contract §11.14).
func _test_restart_during_intro() -> void:
	_release_jump()
	paused = false
	Engine.time_scale = saved_scale
	var packed := load(GAME_SCENE) as PackedScene
	if packed == null:
		check(false, "21: runner_game.tscn failed to load")
		return
	var game := packed.instantiate() as Node3D
	game.autostart = false
	game.config = _configured(_overrides({}))
	game.leaderboard_path = scratch_leaderboard
	live_scene = game
	root.add_child(game)
	await process_frame
	if bool(game.paused):
		game.resume()
	game.start_run(11)
	var reached := await _wait_until(func() -> bool:
		return game.phase == &"boss" and (StringName(game.boss_cinematic_mode) == &"intro_full" or StringName(game.boss_cinematic_mode) == &"intro_short"), 20.0)
	if bool(game.paused):
		game.resume()
	if not reached:
		check(false, "21: the real scene never opened an intro (phase %s, mode %s)" % [game.phase, game.boss_cinematic_mode])
		_release_jump()
		_free_live_scene()
		return
	var dipped := await _wait_until(func() -> bool:
		return StringName(game.boss_cinematic_mode) == &"" or float(game.speed_controller.cinematic_scale) < 0.5, 2.0)
	if bool(game.paused):
		game.resume()
	var mode_before: StringName = StringName(game.boss_cinematic_mode)
	var scale_before: float = float(game.speed_controller.cinematic_scale)
	check(dipped and (mode_before == &"intro_full" or mode_before == &"intro_short") and scale_before < 0.5,
		"21: the intro scale never left 1 (mode %s, scale %.4f)" % [mode_before, scale_before])
	if mode_before != &"intro_full" and mode_before != &"intro_short":
		_release_jump()
		_free_live_scene()
		return
	var ended: Array = []
	var on_ended := func(mode: StringName) -> void:
		ended.append(mode)
	game.boss_cinematic_ended.connect(on_ended)
	game.start_run(11)
	if game.boss_cinematic_ended.is_connected(on_ended):
		game.boss_cinematic_ended.disconnect(on_ended)
	if bool(game.paused):
		game.resume()
	paused = false
	var stage: Node = game.stage_manager
	var player: Node = game.player
	var ended_mode: StringName = &""
	if not ended.is_empty():
		ended_mode = ended[0]
	check(ended.size() == 1 and ended_mode == mode_before,
		"21: start_run emitted boss_cinematic_ended %s, expected one %s" % [ended, mode_before])
	var hold_after := false
	var controls_after := false
	if stage != null:
		hold_after = bool(stage.cinematic_hold)
	if player != null:
		controls_after = bool(player.controls_enabled)
	check(stage != null and player != null and not hold_after and controls_after,
		"21: after restart hold %s controls %s" % [hold_after, controls_after])
	check(StringName(game.boss_cinematic_mode) == &"" and game.state == &"running" and game.phase == &"run",
		"21: the new run is state %s phase %s mode %s" % [game.state, game.phase, game.boss_cinematic_mode])
	var scale_now: float = float(game.speed_controller.cinematic_scale)
	for _i in _ticks(EASE_SECONDS):
		await physics_frame
	var scale_after: float = float(game.speed_controller.cinematic_scale)
	check(absf(scale_after - 1.0) < 0.02,
		"21: cinematic_scale %.4f after %.2f s, from %.4f at the restart, expected 1 within 0.02"
		% [scale_after, EASE_SECONDS, scale_now])
	note("21: restart closed %s, scale %.4f -> %.4f, phase %s" % [mode_before, scale_now, scale_after, game.phase])
	_release_jump()
	_free_live_scene()

# --- 13. Intro timing, 14. focus default, 15. camera focus (contract §11.5, §11.14) -------------

## INTRO_POSE_AT / INTRO_HOLD_UNTIL, the shot keys those land on, and a frozen hold between them.
func _test_intro_timing_and_focus() -> void:
	_test_intro_timing()
	_test_focus_bounds()
	_test_focus_cache_and_override()
	_test_graybox_focus()
	_test_camera_focus_feed()

func _test_intro_timing() -> void:
	var base_map: Dictionary = visual_base_script.get_script_constant_map()
	var cam_map: Dictionary = camera_script.get_script_constant_map()
	var pose: Dictionary = base_map.get("INTRO_POSE_AT", {})
	var hold: Dictionary = base_map.get("INTRO_HOLD_UNTIL", {})
	var shots: Dictionary = cam_map.get("BOSS_SHOTS", {})
	var expected_pose: Dictionary = {&"intro_full": 0.40, &"intro_short": 0.28}
	var expected_hold: Dictionary = {&"intro_full": 0.66, &"intro_short": 0.88}
	var const_bad := ""
	if pose.size() != 2 or hold.size() != 2:
		const_bad = "sizes pose %d hold %d, maps have pose %s hold %s shots %s" % [
			pose.size(), hold.size(), base_map.has("INTRO_POSE_AT"), base_map.has("INTRO_HOLD_UNTIL"), cam_map.has("BOSS_SHOTS")]
	else:
		for mode in expected_pose:
			var got_pose: float = float(pose.get(mode, -1))
			var got_hold: float = float(hold.get(mode, -1))
			if not is_equal_approx(got_pose, float(expected_pose[mode])) or not is_equal_approx(got_hold, float(expected_hold[mode])):
				const_bad = "%s pose %s hold %s" % [mode, pose.get(mode, "<missing>"), hold.get(mode, "<missing>")]
				break
	check(const_bad == "",
		"13: INTRO_POSE_AT %s INTRO_HOLD_UNTIL %s, expected intro_full 0.40/0.66 and intro_short 0.28/0.88 (%s)"
		% [pose, hold, const_bad])
	var deltas := ""
	for mode in [&"intro_full", &"intro_short"]:
		var pose_at: float = float(pose.get(mode, -1))
		var hold_at: float = float(hold.get(mode, -1))
		var table: Dictionary = shots.get(mode, {})
		var ret: float = float(table.get("ret", -1))
		# intro_short's hold runs right up to its return (§11.14), so the hold may end on `ret`.
		check(pose_at < hold_at and hold_at <= ret,
			"13: %s pose %.4f hold %.4f ret %.4f, expected pose < hold <= ret" % [mode, pose_at, hold_at, ret])
		var keys: Array = table.get("keys", [])
		var has_pose := false
		var has_hold := false
		var listed := ""
		for key in keys:
			var row: Array = key
			if row.is_empty():
				continue
			var p: float = float(row[0])
			listed += " %.4f" % p
			if is_equal_approx(p, pose_at):
				has_pose = true
			if is_equal_approx(p, hold_at):
				has_hold = true
		check(has_pose and has_hold,
			"13: %s shot keys [%s ], expected one at pose %.4f and one at hold %.4f" % [mode, listed, pose_at, hold_at])
		if not has_pose or not has_hold or pose_at >= hold_at:
			check(false, "13: %s hold not sampled (pose %.4f hold %.4f)" % [mode, pose_at, hold_at])
			continue
		var anchor: Dictionary = camera_script.boss_shot(pose_at, mode)
		var anchor_fov: float = float(anchor.get("fov", -999.0))
		var anchor_dist: float = float(anchor.get("distance", -999.0))
		var worst_fov := 0.0
		var worst_dist := 0.0
		var at_fov := pose_at
		var at_dist := pose_at
		for i in 21:
			var p: float = pose_at + (hold_at - pose_at) * float(i) / 20.0
			var shot: Dictionary = camera_script.boss_shot(p, mode)
			var dfov: float = absf(float(shot.get("fov", 0.0)) - anchor_fov)
			var ddist: float = absf(float(shot.get("distance", 0.0)) - anchor_dist)
			if dfov > worst_fov:
				worst_fov = dfov
				at_fov = p
			if ddist > worst_dist:
				worst_dist = ddist
				at_dist = p
		check(worst_fov <= 3.0 and worst_dist <= 1.0,
			"13: %s between %.4f and %.4f fov moved %.3f° at p %.4f (anchor %.2f) and distance %.3f m at p %.4f (anchor %.2f); limits are ±3° and ±1 m"
			% [mode, pose_at, hold_at, worst_fov, at_fov, anchor_fov, worst_dist, at_dist, anchor_dist])
		deltas += "%s fov Δ%.3f° dist Δ%.3f m; " % [mode, worst_fov, worst_dist]
	note("13: pose %s hold %s; %s" % [pose, hold, deltas])

## Two visible boxes, one of them under a scaled pivot, plus a hidden box that must not count.
func _test_focus_bounds() -> void:
	var probe := BoxMesh.new()
	probe.size = Vector3(2, 2, 2)
	var probe_aabb: AABB = probe.get_aabb()
	check(probe_aabb.position.is_equal_approx(Vector3(-1, -1, -1)) and probe_aabb.size.is_equal_approx(Vector3(2, 2, 2)),
		"14: BoxMesh (2, 2, 2) aabb pos %s size %s, expected pos (-1, -1, -1) size (2, 2, 2)"
		% [probe_aabb.position, probe_aabb.size])
	var host := Node3D.new()
	root.add_child(host)
	junk.append(host)
	host.add_child(_focus_box(Vector3(2, 2, 2), Vector3(4, 0, 0)))
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 10, 0)
	pivot.scale = Vector3(2, 1, 1)
	host.add_child(pivot)
	pivot.add_child(_focus_box(Vector3(1, 1, 1), Vector3(0, 1, 0)))
	host.add_child(_focus_box(Vector3(10, 10, 10), Vector3(50, 0, 0), false))
	var hand := AABB(Vector3(-1, -1, -1), Vector3(6, 12.5, 2))
	var want_focus: Vector3 = _upper_third(hand)
	var got: AABB = visual_base_script.call(&"rest_bounds", host)
	var focus: Vector3 = visual_base_script.call(&"rest_focus", host)
	check(got.position.is_equal_approx(hand.position) and got.size.is_equal_approx(hand.size),
		"14: rest_bounds pos %s size %s, expected pos %s size %s with the hidden mesh ignored"
		% [got.position, got.size, hand.position, hand.size])
	check(focus.is_equal_approx(want_focus),
		"14: rest_focus %s, expected the upper-third centre %s" % [focus, want_focus])
	var hidden_root := Node3D.new()
	root.add_child(hidden_root)
	junk.append(hidden_root)
	hidden_root.add_child(_focus_box(Vector3(2, 2, 2), Vector3.ZERO, false))
	hidden_root.add_child(_focus_box(Vector3(2, 2, 2), Vector3(4, 0, 0), false))
	var hidden_hand := AABB(Vector3(-1, -1, -1), Vector3(6, 2, 2))
	var hidden_got: AABB = visual_base_script.call(&"rest_bounds", hidden_root)
	var hidden_focus: Vector3 = visual_base_script.call(&"rest_focus", hidden_root)
	check(hidden_got.position.is_equal_approx(hidden_hand.position) and hidden_got.size.is_equal_approx(hidden_hand.size),
		"14: hidden-only rest_bounds pos %s size %s, expected the fallback merge pos %s size %s"
		% [hidden_got.position, hidden_got.size, hidden_hand.position, hidden_hand.size])
	check(hidden_focus.is_equal_approx(_upper_third(hidden_hand)),
		"14: hidden-only rest_focus %s, expected %s" % [hidden_focus, _upper_third(hidden_hand)])
	var empty := Node3D.new()
	root.add_child(empty)
	junk.append(empty)
	var empty_bounds: AABB = visual_base_script.call(&"rest_bounds", empty)
	var empty_focus: Vector3 = visual_base_script.call(&"rest_focus", empty)
	check(not empty_bounds.has_volume() and empty_focus.is_equal_approx(Vector3.ZERO),
		"14: no-mesh rest_focus %s bounds pos %s size %s, expected the origin"
		% [empty_focus, empty_bounds.position, empty_bounds.size])

## The base caches cinematic_focus() on first read. An override is what the encounter stores.
func _test_focus_cache_and_override() -> void:
	var cached := Node3D.new()
	cached.set_script(recorder_script)
	root.add_child(cached)
	junk.append(cached)
	var box := _focus_box(Vector3(2, 2, 2))
	cached.add_child(box)
	var before: Vector3 = visual_base_script.call(&"rest_focus", cached)
	var first: Vector3 = cached.call(&"cinematic_focus")
	box.position = Vector3(0, 20, 0)
	box.scale = Vector3(3, 3, 3)
	var second: Vector3 = cached.call(&"cinematic_focus")
	var after: Vector3 = visual_base_script.call(&"rest_focus", cached)
	check(first.is_equal_approx(before) and second.is_equal_approx(first) and not second.is_equal_approx(after),
		"14: cinematic_focus %s then %s, rest_focus before %s after the move %s"
		% [first, second, before, after])
	var rig := _boss_rig(_overrides({}))
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	var visual := Node3D.new()
	visual.set_script(focus_script)
	visual.position = Vector3(0.25, -0.5, 0.1)
	visual.scale = Vector3(2, 3, 1)
	var boss_root: Node3D = arena.get("boss_root")
	if boss_root == null:
		check(false, "14: the encounter has no boss mount for the focus override")
		_free_rig(rig)
		return
	boss_root.add_child(visual)
	arena.set("visual", visual)
	arena.call(&"_read_cinematic_focus")
	var fixed := Vector3(1.5, 2.5, -0.5)
	var want: Vector3 = visual.transform * fixed
	var got: Vector3 = arena.get("cinematic_focus")
	check(got.is_equal_approx(want) and not got.is_equal_approx(fixed) and not got.is_equal_approx(visual.position),
		"14: arena.cinematic_focus %s, expected visual.transform * %s = %s (visual position %s)"
		% [got, fixed, want, visual.position])
	note("14: cached focus %s stayed put after the mesh moved to %s; override stored %s" % [first, after, got])
	_free_rig(rig)

## Shipped visual scenes exist, so start() does not mount the graybox. Install the encounter's own
## graybox and read the focus through the same function _mount_boss uses, then finish the fight.
func _test_graybox_focus() -> void:
	var rig := _boss_rig(_overrides({
		"boss_hp_scale": 0.001,
		"boss_timeout_seconds": 55.0,
	}))
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	arena.start(1)
	var gray := _mount_graybox(arena)
	if gray == null:
		check(false, "14: the graybox did not mount")
		_free_rig(rig)
		return
	var local_bounds: AABB = visual_base_script.call(&"rest_bounds", gray)
	var mount_bounds: AABB = gray.transform * local_bounds
	var y0: float = mount_bounds.position.y
	var y1: float = mount_bounds.position.y + mount_bounds.size.y
	var rest: Vector3 = visual_base_script.call(&"rest_focus", gray)
	var focus: Vector3 = arena.get("cinematic_focus")
	var carried: Vector3 = gray.transform * rest
	check(is_equal_approx(y0, -1.0) and is_equal_approx(y1, 1.4),
		"14: graybox mount-space y spans %.4f .. %.4f, expected -1.0 .. 1.4 (bounds pos %s size %s)"
		% [y0, y1, mount_bounds.position, mount_bounds.size])
	check(focus.is_equal_approx(carried) and focus.is_equal_approx(Vector3(0, 1, 0)),
		"14: graybox cinematic_focus %s, expected the upper-third centre %s (about (0, 1, 0))"
		% [focus, carried])
	if not _skip_arena_intro(arena):
		check(false, "14: the graybox fight's intro never ended (mode %s)" % arena.cinematic_mode)
		_free_rig(rig)
		return
	check(int(arena.hp) == 1, "14: HP is %d before the kill, expected 1" % int(arena.hp))
	if int(arena.hp) != 1:
		_free_rig(rig)
		return
	var during: Vector3 = arena.get("cinematic_focus")
	check(during.is_equal_approx(focus),
		"14: cinematic_focus moved from %s to %s before the kill" % [focus, during])
	arena.apply_tool(&"unit_test")
	var ticks := 0
	var guard := _ticks(DEFEAT_FULL + 1.0)
	while not bool(arena.finished) and ticks < guard:
		if not (arena.get("cinematic_focus") as Vector3).is_equal_approx(focus):
			break
		arena.tick(TICK)
		ticks += 1
	var after: Vector3 = arena.get("cinematic_focus")
	check(bool(arena.finished) and after.is_equal_approx(Vector3.ZERO),
		"14: finished %s after %d ticks with cinematic_focus %s, expected zero once the fight ends"
		% [arena.finished, ticks, after])
	note("14: graybox y %.3f..%.3f focus %s, cleared to %s (finished %s)" % [y0, y1, focus, after, arena.finished])
	_free_rig(rig)

## Every boss tick hands the stage the mount position and the global cinematic focus.
func _test_camera_focus_feed() -> void:
	var bias_bad := ""
	for mode in MODES:
		var shot: Dictionary = camera_script.boss_shot(0.5, mode)
		if not shot.has("look_bias") or shot.has("look_y"):
			bias_bad = "%s keys %s" % [mode, shot.keys()]
			break
	check(bias_bad == "", "15: boss_shot exposes look_bias and not look_y (%s)" % bias_bad)
	var rig := _stage_rig(_overrides({}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var stage: Node = rig["stage"]
	var feed := Node3D.new()
	feed.set_script(camera_feed_script)
	root.add_child(feed)
	junk.append(feed)
	game.camera_rig = feed
	stage.begin()
	if not _require_boss(rig, "15: camera", 8.0):
		_free_rig(rig)
		return
	_tick_rig(rig, 8)
	var arena: Node = rig["arena"]
	var boss: Node3D = arena.get("boss")
	if boss == null or not boss.is_inside_tree():
		check(false, "15: the boss mount is missing during the intro")
		_free_rig(rig)
		return
	var mount_focus: Vector3 = arena.get("cinematic_focus")
	var want_pos: Vector3 = boss.global_position
	var want_focus: Vector3 = boss.to_global(mount_focus)
	check(not mount_focus.is_equal_approx(Vector3.ZERO) and not want_focus.is_equal_approx(want_pos),
		"15: cinematic_focus %s (global %s) is not distinct from the mount %s" % [mount_focus, want_focus, want_pos])
	var calls: Array = feed.get("calls")
	var matched := 0
	var bad := ""
	for entry in calls:
		var row: Array = entry
		if row.size() < 4 or not (row[2] is Vector3) or not (row[3] is Vector3):
			bad = "call %s is not a 4-arg boss tick" % [row]
			break
		if StringName(row[1]) != &"intro_full":
			bad = "mode %s at progress %s, expected intro_full" % [row[1], row[0]]
			break
		var got_pos: Vector3 = row[2]
		var got_focus: Vector3 = row[3]
		if not got_pos.is_equal_approx(want_pos) or not got_focus.is_equal_approx(want_focus):
			bad = "passed boss %s focus %s, expected boss %s focus %s (mount focus %s)" % [
				got_pos, got_focus, want_pos, want_focus, mount_focus]
			break
		matched += 1
	check(bad == "" and matched >= 9,
		"15: %d boss tick(s) passed focus_position == boss.to_global(cinematic_focus) (%s)" % [matched, bad])
	note("15: %d intro_full ticks, mount focus %s, global focus %s, look_bias on %d modes" % [
		matched, mount_focus, want_focus, MODES.size()])
	_free_rig(rig)

# --- 16. A retreat outro feeds the visual nothing (contract §11.14) ----------------------------

## Intro length 0 so no cinematic opens. The timeout still holds boss_outro_seconds, and the same
## rig's defeat keeps the per-tick feed.
func _test_retreat_outro_feed() -> void:
	var rig := _boss_rig(_overrides({
		"boss_intro_seconds": 0.0,
		"boss_intro_short_seconds": 0.0,
		"boss_timeout_seconds": 0.05,
		"boss_hp_scale": 0.001,
	}))
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	var events: Dictionary = rig["events"]
	var cinematic_at: int = int(events["boss_cinematic"].size())
	var ended_at: int = int(events["ended"].size())
	arena.start(1)
	check(events["boss_cinematic"].size() == cinematic_at and events["ended"].size() == ended_at
		and StringName(arena.cinematic_mode) == &"",
		"16: an intro of 0 s opened %s (shots %d -> %d, ended %d -> %d)"
		% [arena.cinematic_mode, cinematic_at, events["boss_cinematic"].size(), ended_at, events["ended"].size()])
	var rec := _mount_recorder(arena)
	if rec == null:
		check(false, "16: the retreat recorder did not mount")
		_free_rig(rig)
		return
	rec.calls.clear()
	var mark := -1
	var ticks := 0
	var guard := _ticks(2.0)
	while mark < 0 and ticks < guard and not bool(arena.finished):
		var before: int = int(rec.calls.size())
		var cinematic_before: int = int(events["boss_cinematic"].size())
		var ended_before: int = int(events["ended"].size())
		arena.tick(TICK)
		ticks += 1
		if int(events["boss_retreated"].size()) > 0:
			mark = before
			cinematic_at = cinematic_before
			ended_at = ended_before
	check(mark >= 0, "16: the timeout did not retreat (finished %s after %d ticks)" % [arena.finished, ticks])
	if mark < 0:
		_free_rig(rig)
		return
	var hold_ticks := 0
	var hold_guard := _ticks(OUTRO + 2.0)
	while not bool(arena.finished) and hold_ticks < hold_guard:
		arena.tick(TICK)
		hold_ticks += 1
	var held := hold_ticks * TICK
	var calls: Array = rec.calls
	var progress := _count_calls(calls, &"set_cinematic_progress", mark)
	var factor := _count_calls(calls, &"set_time_factor", mark)
	var retreats := _count_calls(calls, &"play_retreat", 0)
	check(progress == 0 and factor == 0,
		"16: the retreat outro fed set_cinematic_progress %d time(s) and set_time_factor %d time(s)"
		% [progress, factor])
	check(events["boss_cinematic"].size() == cinematic_at and events["ended"].size() == ended_at,
		"16: the retreat emitted cinematic %d -> %d and ended %d -> %d"
		% [cinematic_at, events["boss_cinematic"].size(), ended_at, events["ended"].size()])
	check(retreats == 1, "16: play_retreat ran %d time(s), expected 1" % retreats)
	check(bool(arena.finished) and absf(held - OUTRO) <= TICK + 0.0001,
		"16: finished %s after %.4f s (%d ticks), expected boss_outro_seconds %.3f within one tick"
		% [arena.finished, held, hold_ticks, OUTRO])
	note("16: retreat outro %.4f s, play_retreat %d, progress %d, factor %d" % [held, retreats, progress, factor])
	_test_retreat_rig_defeat(rig)
	_free_rig(rig)

## The defeat on the rig that just retreated still pushes progress and the time factor every tick.
func _test_retreat_rig_defeat(rig: Dictionary) -> void:
	var arena: Node = rig["arena"]
	var events: Dictionary = rig["events"]
	arena.start(1)
	var rec := _mount_recorder(arena)
	if rec == null:
		check(false, "16: the defeat recorder did not mount")
		return
	check(int(arena.hp) == 1, "16: HP is %d before the defeat, expected 1" % int(arena.hp))
	if int(arena.hp) != 1:
		return
	var cinematic_at: int = int(events["boss_cinematic"].size())
	rec.calls.clear()
	arena.apply_tool(&"unit_test")
	var names := _call_names(rec.calls)
	var seconds: float = float(arena.cinematic_seconds)
	check(_same(names.slice(0, 5), [&"set_health", &"play_defeat", &"play_cinematic", &"set_cinematic_progress", &"set_time_factor"])
		and StringName(arena.cinematic_mode) == &"defeat_full" and is_equal_approx(seconds, DEFEAT_FULL),
		"16: defeat opened with %s mode %s for %.4f s, expected set_health then the defeat_full feed"
		% [names, arena.cinematic_mode, seconds])
	var bad := ""
	var prev := 0.0
	var feed_ticks := 0
	while feed_ticks < 8 and bad == "" and StringName(arena.cinematic_mode) == &"defeat_full":
		bad = _feed_tick(arena, rec, &"defeat_full", prev, true, seconds)
		if StringName(arena.cinematic_mode) == &"":
			bad = "defeat ended on sample tick %d" % feed_ticks
			break
		prev = _last_progress(rec)
		feed_ticks += 1
	check(bad == "" and feed_ticks == 8 and events["boss_cinematic"].size() == cinematic_at + 1,
		"16: defeat feed over %d tick(s) (%s); cinematic signals %d -> %d"
		% [feed_ticks, bad, cinematic_at, events["boss_cinematic"].size()])
	note("16: defeat_full feed held for %d ticks after the retreat" % feed_ticks)

func _count_calls(calls: Array, method: StringName, from_index: int) -> int:
	var n := 0
	for i in range(maxi(from_index, 0), calls.size()):
		var entry: Array = calls[i]
		if not entry.is_empty() and StringName(entry[0]) == method:
			n += 1
	return n

# --- 17. A zero skip tail closes the intro in the same call (contract §11.14) ------------------

func _test_zero_tail_skip() -> void:
	var rig := _stage_rig(_overrides({"boss_cinematic_skip_tail": 0.0}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var stage: Node = rig["stage"]
	var events: Dictionary = rig["events"]
	var player := _attach_controls(game)
	stage.begin()
	if not _require_boss(rig, "17: zero tail", 8.0):
		_free_rig(rig)
		return
	check(bool(stage.cinematic_hold) and not bool(player.controls_enabled) and StringName(arena.cinematic_mode) == &"intro_full",
		"17: at the intro, hold %s controls %s mode %s" % [stage.cinematic_hold, player.controls_enabled, arena.cinematic_mode])
	_tick_until(rig, func() -> bool: return bool(arena.can_skip_cinematic()), 2.0)
	if not bool(arena.can_skip_cinematic()):
		_tick_rig(rig, 1)
	check(bool(arena.can_skip_cinematic()),
		"17: can_skip stayed false at %.4f s with a zero tail" % _cinematic_elapsed(arena))
	if not bool(arena.can_skip_cinematic()):
		_free_rig(rig)
		return
	var order_at: int = int(events["order"].size())
	var ended_before: int = int(events["ended"].size())
	var skipped_before: int = int(events["skipped"].size())
	var did_skip := bool(arena.skip_cinematic())
	var tail: Array = events["order"].slice(order_at)
	check(did_skip and _same(tail, [&"skipped", &"ended"]),
		"17: skip_cinematic returned %s and the same call recorded %s, expected skipped then ended" % [did_skip, tail])
	check(events["skipped"].size() == skipped_before + 1 and StringName(events["skipped"].back()) == &"intro_full"
		and events["ended"].size() == ended_before + 1 and StringName(events["ended"].back()) == &"intro_full",
		"17: skipped %s ended %s, expected one intro_full of each" % [events["skipped"], events["ended"]])
	check(StringName(arena.cinematic_mode) == &"" and is_equal_approx(float(arena.cinematic_progress()), 0.0)
		and not bool(arena.can_skip_cinematic()),
		"17: after the skip, mode %s progress %.4f can_skip %s" % [arena.cinematic_mode, float(arena.cinematic_progress()), arena.can_skip_cinematic()])
	var mirror: Dictionary = _last_mirror(events, "mirror_end")
	check(StringName(game.boss_cinematic_mode) == &"" and is_equal_approx(float(game.boss_cinematic_progress), 0.0)
		and is_equal_approx(float(game.boss_time_factor), 1.0)
		and StringName(mirror.get("mode", &"missing")) == &"" and not bool(mirror.get("hold", true))
		and not bool(stage.cinematic_hold) and bool(player.controls_enabled),
		"17: mirrors after the call mode %s progress %.4f factor %.4f hold %s (snapshot %s), controls %s"
		% [game.boss_cinematic_mode, float(game.boss_cinematic_progress), float(game.boss_time_factor),
			stage.cinematic_hold, mirror, player.controls_enabled])
	var ended_at: int = int(events["ended"].size())
	var after := _wait_for_threat(rig, "17: zero tail", 3.0)
	check(bool(after["appeared"]) and StringName(arena.cinematic_mode) == &"" and events["ended"].size() == ended_at
		and stage.phase == &"boss",
		"17: after the skip the fight did not start (threat %s, mode %s, ended %d -> %d, phase %s)"
		% [after["appeared"], arena.cinematic_mode, ended_at, events["ended"].size(), stage.phase])
	note("17: zero tail closed intro_full in the skip call, threat +%.3f s" % (int(after["post_ticks"]) * TICK))
	_free_rig(rig)

# --- 18. set_health follows every boss_health_changed (contract §11.5) -------------------------

func _test_set_health_feed() -> void:
	var rig := _boss_rig(_overrides({
		"boss_hp_scale": 1.0,
		"boss_timeout_seconds": 55.0,
	}))
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var events: Dictionary = rig["events"]
	var holder := {"rec": null}
	var on_open := func(_hp: int, _max_hp: int) -> void:
		if holder["rec"] == null:
			holder["rec"] = _mount_recorder(arena)
	game.boss_health_changed.connect(on_open)
	# Stage 2 is the hydra: phase 2 accepts only unit_test and lint_rule, so a review comment resists.
	# Stage 1's swarm accepts every tool in every phase.
	arena.start(2)
	if game.boss_health_changed.is_connected(on_open):
		game.boss_health_changed.disconnect(on_open)
	var rec: Node = holder["rec"]
	if rec == null:
		check(false, "18: the health signal did not mount the recorder")
		_free_rig(rig)
		return
	var health_rows: Array = events["boss_health_changed"]
	var open_args := _last_named(rec.calls, &"set_health")
	check(_count_calls(rec.calls, &"set_health", 0) == 1 and health_rows.size() == 1
		and open_args.size() == 2 and int(open_args[0]) == int(health_rows[0][0]) and int(open_args[1]) == int(health_rows[0][1])
		and int(open_args[0]) == int(arena.hp) and int(open_args[0]) == int(arena.max_hp) and int(arena.hp) > 1,
		"18: opening set_health %s, signal %s, live hp %d / %d"
		% [open_args, health_rows, int(arena.hp), int(arena.max_hp)])
	var hit := _health_step(arena, rec, events, &"unit_test")
	check(_health_matches(hit) and int(hit["hp"]) < int(hit["hp_before"]) and int(hit["added"]) == 1,
		"18: unit_test set_health %s signal %s, hp %s -> %s, %d new call(s)"
		% [hit["sets"], hit["health"], hit["hp_before"], hit["hp"], int(hit["added"])])
	var climbed := 0
	while int(arena.phase) < 2 and int(arena.hp) > 20 and climbed < 12:
		var mid := _health_step(arena, rec, events, &"unit_test")
		check(_health_matches(mid) and int(mid["hp"]) < int(mid["hp_before"]),
			"18: climb set_health %s signal %s, hp %s -> %s phase %s"
			% [mid["sets"], mid["health"], mid["hp_before"], mid["hp"], arena.phase])
		climbed += 1
	check(int(arena.phase) == 2 and int(arena.hp) > 0,
		"18: phase is %d at hp %d / %d, expected phase 2 with HP left" % [int(arena.phase), int(arena.hp), int(arena.max_hp)])
	if int(arena.phase) != 2 or int(arena.hp) <= 0:
		_free_rig(rig)
		return
	var info: Dictionary = arena.get_info()
	var accepted: Array = info.get("accepted_tools", [])
	var resist_tool: StringName = &""
	for kind in [&"review_comment", &"lint_rule", &"auto_fix_patch", &"unit_test"]:
		if not accepted.has(kind):
			resist_tool = kind
			break
	check(resist_tool != &"", "18: phase %d accepted %s, so nothing resists" % [int(arena.phase), accepted])
	if resist_tool == &"":
		_free_rig(rig)
		return
	var hp_at: int = int(arena.hp)
	var resist := _health_step(arena, rec, events, resist_tool)
	check(_health_matches(resist) and int(resist["hp"]) == hp_at and int(resist["added"]) == 1,
		"18: %s set_health %s signal %s, hp %d -> %s, %d new call(s) (phase %d accepts %s)"
		% [resist_tool, resist["sets"], resist["health"], hp_at, resist["hp"], int(resist["added"]), int(arena.phase), accepted])
	var kill_tool: StringName = &"unit_test" if accepted.has(&"unit_test") else accepted[0]
	var kill := {"hp": int(arena.hp)}
	var guard := 0
	while int(arena.hp) > 0 and guard < 30:
		kill = _health_step(arena, rec, events, kill_tool)
		guard += 1
		if not _health_matches(kill):
			break
	check(_health_matches(kill) and int(kill["hp"]) == 0 and int(kill["max_hp"]) == int(arena.max_hp),
		"18: kill set_health %s signal %s, hp %s" % [kill["sets"], kill["health"], kill["hp"]])
	note("18: set_health tracked full %d, a hit, %s resisted at %d, and the kill" % [int(arena.max_hp), resist_tool, hp_at])
	_free_rig(rig)

func _health_step(arena: Node, rec: Node, events: Dictionary, tool: StringName) -> Dictionary:
	var call_at: int = int(rec.calls.size())
	var health_at: int = int(events["boss_health_changed"].size())
	var hp_before: int = int(arena.hp)
	arena.apply_tool(tool)
	var added: Array = rec.calls.slice(call_at)
	var health_all: Array = events["boss_health_changed"]
	var health: Array = health_all.slice(health_at)
	var sets: Array = []
	for entry in added:
		var row: Array = entry
		if not row.is_empty() and StringName(row[0]) == &"set_health":
			sets.append(row[1])
	return {
		"hp_before": hp_before,
		"hp": int(arena.hp),
		"max_hp": int(arena.max_hp),
		"health": health,
		"sets": sets,
		"added": added.size(),
	}

func _health_matches(step: Dictionary) -> bool:
	var sets: Array = step["sets"]
	var health: Array = step["health"]
	if sets.size() != 1 or health.size() != 1:
		return false
	var args: Array = sets[0]
	var signal_row: Array = health[0]
	if args.size() != 2 or signal_row.size() < 2:
		return false
	return int(args[0]) == int(signal_row[0]) and int(args[1]) == int(signal_row[1]) \
		and int(args[0]) == int(step["hp"]) and int(args[1]) == int(step["max_hp"])

# --- 19. A zero-length intro and defeat are not cinematics (contract §11.14) -------------------

func _test_zero_length() -> void:
	var overrides := _overrides({
		"boss_intro_seconds": 0.0,
		"boss_intro_short_seconds": 0.0,
		"boss_defeat_seconds": 0.0,
		"boss_defeat_short_seconds": 0.0,
		"boss_hp_scale": 0.001,
		"boss_timeout_seconds": 55.0,
	})
	_test_zero_length_boss(overrides)
	_test_zero_length_stage(overrides)

func _test_zero_length_boss(overrides: Dictionary) -> void:
	var rig := _boss_rig(overrides)
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	var events: Dictionary = rig["events"]
	var cinematic_at: int = int(events["boss_cinematic"].size())
	var ended_at: int = int(events["ended"].size())
	arena.start(1)
	check(events["boss_cinematic"].size() == cinematic_at and events["ended"].size() == ended_at
		and StringName(arena.cinematic_mode) == &"",
		"19: an intro of 0 s opened %s (shots %d -> %d, ended %d -> %d)"
		% [arena.cinematic_mode, cinematic_at, events["boss_cinematic"].size(), ended_at, events["ended"].size()])
	check(int(arena.hp) == 1, "19: HP is %d before the zero defeat, expected 1" % int(arena.hp))
	if int(arena.hp) != 1:
		_free_rig(rig)
		return
	arena.apply_tool(&"unit_test")
	check(bool(arena.finished) and StringName(arena.cinematic_mode) == &""
		and events["boss_cinematic"].size() == cinematic_at and events["ended"].size() == ended_at,
		"19: defeat of 0 s finished %s inside apply_tool, mode %s, shots %d -> %d, ended %d -> %d"
		% [arena.finished, arena.cinematic_mode, cinematic_at, events["boss_cinematic"].size(), ended_at, events["ended"].size()])
	note("19: boss rig finished %s with no cinematic" % arena.finished)
	_free_rig(rig)

func _test_zero_length_stage(overrides: Dictionary) -> void:
	var rig := _stage_rig(overrides)
	if rig.is_empty():
		return
	var game: Node = rig["game"]
	var arena: Node = rig["arena"]
	var stage: Node = rig["stage"]
	var events: Dictionary = rig["events"]
	var player := _attach_controls(game)
	stage.begin()
	if not _require_boss(rig, "19: zero length", 8.0):
		_free_rig(rig)
		return
	check(StringName(arena.cinematic_mode) == &"" and not bool(stage.cinematic_hold) and bool(player.controls_enabled)
		and events["boss_cinematic"].is_empty() and events["ended"].is_empty(),
		"19: boss entry with a 0 s intro is mode %s hold %s controls %s shots %d ended %d"
		% [arena.cinematic_mode, stage.cinematic_hold, player.controls_enabled, events["boss_cinematic"].size(), events["ended"].size()])
	check(int(arena.hp) == 1, "19: stage HP is %d, expected 1" % int(arena.hp))
	if int(arena.hp) != 1:
		_free_rig(rig)
		return
	arena.apply_tool(&"unit_test")
	check(bool(arena.finished) and not bool(stage.cinematic_hold) and StringName(arena.cinematic_mode) == &""
		and events["boss_cinematic"].is_empty() and events["ended"].is_empty(),
		"19: the 0 s defeat finished %s with hold %s mode %s shots %d ended %d"
		% [arena.finished, stage.cinematic_hold, arena.cinematic_mode, events["boss_cinematic"].size(), events["ended"].size()])
	_tick_rig(rig, 1)
	check(stage.phase != &"boss",
		"19: one tick after the zero defeat left phase %s" % stage.phase)
	note("19: stage hold stayed false, phase %s one tick later" % stage.phase)
	_free_rig(rig)

# --- 20. A kill during the intro ends it before the defeat cinematic ---------------------------

func _test_kill_mid_intro_order() -> void:
	var rig := _boss_rig(_overrides({
		"boss_hp_scale": 0.001,
		"boss_timeout_seconds": 55.0,
	}))
	if rig.is_empty():
		return
	var arena: Node = rig["arena"]
	var events: Dictionary = rig["events"]
	arena.start(1)
	check(StringName(arena.cinematic_mode) == &"intro_full",
		"20: the kill's intro is %s, expected intro_full" % arena.cinematic_mode)
	if StringName(arena.cinematic_mode) != &"intro_full":
		_free_rig(rig)
		return
	var order_at: int = int(events["order"].size())
	var ended_before: int = int(events["ended"].size())
	var cinematic_before: int = int(events["boss_cinematic"].size())
	arena.apply_tool(&"unit_test")
	var tail: Array = events["order"].slice(order_at)
	var ended_i := -1
	var cinematic_i := -1
	for i in tail.size():
		if StringName(tail[i]) == &"ended" and ended_i < 0:
			ended_i = i
		if StringName(tail[i]) == &"cinematic":
			cinematic_i = i
	var shot: Array = []
	if not events["boss_cinematic"].is_empty():
		shot = events["boss_cinematic"].back()
	var shot_mode: StringName = &""
	if shot.size() >= 2:
		shot_mode = shot[1]
	var ended_mode: StringName = &""
	if not events["ended"].is_empty():
		ended_mode = events["ended"].back()
	check(ended_i >= 0 and cinematic_i > ended_i
		and events["ended"].size() == ended_before + 1 and ended_mode == &"intro_full"
		and events["boss_cinematic"].size() == cinematic_before + 1 and shot_mode == &"defeat_full",
		"20: order %s (ended at %d, cinematic at %d), ended %s x%d, next shot %s"
		% [tail, ended_i, cinematic_i, ended_mode, events["ended"].size() - ended_before, shot_mode])
	note("20: ended(intro_full) then boss_cinematic(defeat_full)")
	_free_rig(rig)

func _focus_box(size: Vector3, at := Vector3.ZERO, shown := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.visible = shown
	return mesh

func _upper_third(bounds: AABB) -> Vector3:
	return bounds.position + Vector3(bounds.size.x * 0.5, bounds.size.y * 5.0 / 6.0, bounds.size.z * 0.5)

func _mount_graybox(arena: Node) -> Node3D:
	var old: Node = arena.get("visual")
	if is_instance_valid(old):
		var parent := old.get_parent()
		if parent != null:
			parent.remove_child(old)
		old.free()
	arena.set("visual", null)
	arena.set("_graybox", null)
	var boss_root: Node3D = arena.get("boss_root")
	if boss_root == null:
		return null
	var gray: Node3D = arena.call(&"_build_graybox")
	if gray == null:
		return null
	boss_root.add_child(gray)
	arena.set("visual", gray)
	arena.set("_graybox", gray)
	arena.call(&"_read_cinematic_focus")
	return gray

# --- harness ------------------------------------------------------------------------------------

func _overrides(extra: Dictionary) -> Dictionary:
	var merged := {
		"boss_intro_seconds": INTRO_FULL,
		"boss_intro_short_seconds": INTRO_SHORT,
		"boss_defeat_seconds": DEFEAT_FULL,
		"boss_defeat_short_seconds": DEFEAT_SHORT,
		"boss_cinematic_skip_after": SKIP_AFTER,
		"boss_cinematic_skip_tail": SKIP_TAIL,
		"boss_cinematic_speed_scale": SPEED_SCALE,
		"boss_hitstop_seconds": HITSTOP,
		"boss_slowmo_seconds": SLOWMO,
		"boss_slowmo_factor": SLOWMO_FACTOR,
		"boss_outro_seconds": OUTRO,
		"boss_kill_bonus_base": KILL_BASE,
		"boss_kill_bonus_per_stage": KILL_PER_STAGE,
		"tool_bonus": TOOL_BONUS,
		"stage_base_distance": 8.0,
		"stage_distance_step": 0.0,
		"stage_drain_distance": 4.0,
		"stage_drain_timeout": 0.15,
		"turn_seconds": 0.15,
		"stage_clear_seconds": 0.2,
	}
	for key in extra:
		merged[key] = extra[key]
	return merged

func _configured(overrides: Dictionary) -> RunConfig:
	var config := base_config.duplicate() as RunConfig
	for key in overrides:
		config.set(key, overrides[key])
	return config

func _compile(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		return null
	return script

## Scripted before add_child so leaderboard_path exists in time for _ready. _ready itself is a no-op
## on this compiled subclass, so autostart cannot open a run. @onready still runs on enter-tree, and
## the stand-in children below are what those lookups resolve.
func _tree_game() -> Node3D:
	var game := Node3D.new()
	_prime_facade(game)
	game.set_script(game_script)
	game.autostart = false
	game.leaderboard_path = scratch_leaderboard
	game.config = base_config.duplicate()
	root.add_child(game)
	game.set_physics_process(false)
	junk.append(game)
	return game

## Names and types match runner_game.gd's @onready paths. The test replaces the system references
## afterwards; these nodes only keep enter-tree from reporting missing children.
func _prime_facade(game: Node) -> void:
	var systems := Node.new()
	systems.name = "Systems"
	game.add_child(systems)
	for child_name in ["SpeedController", "HitManager", "ScoreManager", "EffectManager", "Spawner", "StageManager", "Autopilot"]:
		var child := Node.new()
		child.name = child_name
		systems.add_child(child)
	var world := Node3D.new()
	world.name = "World"
	game.add_child(world)
	var chunks := Node3D.new()
	chunks.name = "Chunks"
	world.add_child(chunks)
	var turn := Node3D.new()
	turn.name = "TurnRig"
	world.add_child(turn)
	for child_name in ["GrayboxEnvironment", "Environment"]:
		var child := Node3D.new()
		child.name = child_name
		turn.add_child(child)
	var player := CharacterBody3D.new()
	player.name = "Player"
	game.add_child(player)
	var pursuer := Node3D.new()
	pursuer.name = "Pursuer"
	game.add_child(pursuer)
	var camera := Node3D.new()
	camera.name = "CameraRig"
	game.add_child(camera)
	for child_name in ["HUD", "Overlays", "DebugOverlay"]:
		var layer := CanvasLayer.new()
		layer.name = child_name
		game.add_child(layer)
	var audio := Node.new()
	audio.name = "Audio"
	game.add_child(audio)

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
	speed.set_physics_process(false)
	return {"hits": hits, "score": score, "effects": effects, "speed": speed, "spawner": spawner}

func _stage_rig(overrides: Dictionary) -> Dictionary:
	var game := _tree_game()
	for key in overrides:
		game.config.set(key, overrides[key])
	game.state = &"running"
	game.speed = float(game.config.base_speed)
	var systems := _systems(game)
	var turn_rig := _fake_rig()
	var camera := _fake_rig()
	game.turn_rig = turn_rig
	game.camera_rig = camera
	var arena := _mount_arena(game)
	if arena == null:
		_free_rig({"game": game})
		return {}
	var stage: Node = stage_manager_script.new()
	root.add_child(stage)
	stage.set_physics_process(false)
	junk.append(stage)
	game.stage_manager = stage
	var events := _watch(game)
	stage.setup(game)
	# Connected after setup, so the stage machine — which binds first — has already written the
	# mirrors by the time this frontend-ordered listener runs (contract §11.14).
	_watch_mirrors(game, stage, events)
	var rig := {"game": game, "stage": stage, "arena": arena, "events": events}
	rig.merge(systems)
	return rig

func _boss_rig(overrides: Dictionary) -> Dictionary:
	var game := _tree_game()
	for key in overrides:
		game.config.set(key, overrides[key])
	game.state = &"running"
	var systems := _systems(game)
	var events := _watch(game)
	var arena := _mount_arena(game)
	if arena == null:
		_free_rig({"game": game})
		return {}
	var rig := {"game": game, "arena": arena, "events": events}
	rig.merge(systems)
	return rig

func _mount_arena(game: Node3D) -> Node3D:
	var packed := load(ARENA_SCENE) as PackedScene
	check(packed != null, "the boss arena scene failed to load")
	if packed == null:
		return null
	var world := game.get_node_or_null(^"World") as Node3D
	if world == null:
		world = Node3D.new()
		world.name = "World"
		game.add_child(world)
	var rig := world.get_node_or_null(^"TurnRig") as Node3D
	if rig == null:
		rig = Node3D.new()
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

func _hazard() -> Node3D:
	var hazard := Node3D.new()
	hazard.set_script(hazard_script)
	root.add_child(hazard)
	junk.append(hazard)
	return hazard

func _attach_controls(game: Node) -> Node:
	var player := game.get_node_or_null(^"Player") as CharacterBody3D
	if player == null:
		player = CharacterBody3D.new()
		player.name = "Player"
		game.add_child(player)
	player.set_script(controls_script)
	game.player = player
	var bot: Node = autopilot_script.new()
	game.add_child(bot)
	bot.setup(game)
	game.autopilot = bot
	return player

func _watch(game: Node) -> Dictionary:
	var events := {
		"order": [],
		"boss_intro": [],
		"boss_cinematic": [],
		"boss_spawned": [],
		"boss_health_changed": [],
		"boss_attack_telegraph": [],
		"boss_attack_planned": [],
		"boss_defeated": [],
		"boss_retreated": [],
		"bonus_awarded": [],
		"skipped": [],
		"ended": [],
		"mirror_open": [],
		"mirror_skip": [],
		"mirror_end": [],
	}
	game.boss_intro.connect(func(_kind: StringName, _name: String, _seconds: float) -> void:
		events["boss_intro"].append([_kind, _name, _seconds])
		events["order"].append(&"intro"))
	game.boss_cinematic.connect(func(kind: StringName, mode: StringName, seconds: float) -> void:
		events["boss_cinematic"].append([kind, mode, seconds])
		events["order"].append(&"cinematic"))
	game.boss_spawned.connect(func(_kind: StringName, _hp: int) -> void:
		events["boss_spawned"].append([_kind, _hp])
		events["order"].append(&"spawned"))
	game.boss_health_changed.connect(func(_hp: int, _max_hp: int) -> void:
		events["boss_health_changed"].append([_hp, _max_hp])
		events["order"].append(&"health"))
	game.boss_attack_telegraph.connect(func(mask: int, kind: StringName, seconds: float) -> void:
		events["boss_attack_telegraph"].append([mask, kind, seconds]))
	game.boss_attack_planned.connect(func(_attack: Dictionary) -> void:
		events["boss_attack_planned"].append(true))
	game.boss_defeated.connect(func(kind: StringName, bonus: int) -> void:
		events["boss_defeated"].append([kind, bonus])
		events["order"].append(&"defeated"))
	game.boss_retreated.connect(func(kind: StringName, bonus: int) -> void:
		events["boss_retreated"].append([kind, bonus])
		events["order"].append(&"retreated"))
	game.bonus_awarded.connect(func(points: int, reason: StringName) -> void:
		events["bonus_awarded"].append([points, reason]))
	game.boss_cinematic_skipped.connect(func(mode: StringName) -> void:
		events["skipped"].append(mode)
		events["order"].append(&"skipped"))
	game.boss_cinematic_ended.connect(func(mode: StringName) -> void:
		events["ended"].append(mode)
		events["order"].append(&"ended"))
	return events

func _watch_mirrors(game: Node, stage: Node, events: Dictionary) -> void:
	game.boss_cinematic.connect(func(_kind: StringName, _mode: StringName, _seconds: float) -> void:
		events["mirror_open"].append(_mirror(game, stage)))
	game.boss_cinematic_skipped.connect(func(_mode: StringName) -> void:
		events["mirror_skip"].append(_mirror(game, stage)))
	game.boss_cinematic_ended.connect(func(_mode: StringName) -> void:
		events["mirror_end"].append(_mirror(game, stage)))

func _mirror(game: Node, stage: Node) -> Dictionary:
	return {
		"mode": game.boss_cinematic_mode,
		"progress": game.boss_cinematic_progress,
		"factor": game.boss_time_factor,
		"hold": stage.cinematic_hold,
	}

func _last_mirror(events: Dictionary, key: String) -> Dictionary:
	var rows: Array = events[key]
	if rows.is_empty():
		return {}
	return rows.back()

func _tick_stage(nodes: Array, game: Node, count: int) -> void:
	for _i in count:
		if game.state == &"running" or game.state == &"caught":
			game.elapsed += TICK
			game.distance += float(game.speed) * TICK
		for node in nodes:
			node._physics_process(TICK)

func _tick_rig(rig: Dictionary, count: int) -> void:
	var nodes: Array = []
	if rig.has("speed"):
		nodes.append(rig["speed"])
	if rig.has("stage"):
		nodes.append(rig["stage"])
	_tick_stage(nodes, rig["game"], count)

func _ticks(seconds: float) -> int:
	return int(roundf(seconds / TICK))

func _drive_to_phase(rig: Dictionary, phase: StringName, seconds: float) -> bool:
	var stage: Node = rig["stage"]
	var guard := 0
	var limit := _ticks(seconds)
	while stage.phase != phase and guard < limit:
		_tick_rig(rig, 1)
		guard += 1
	return stage.phase == phase

func _require_boss(rig: Dictionary, tag: String, seconds: float) -> bool:
	if _drive_to_phase(rig, &"boss", seconds):
		return true
	var stage: Node = rig["stage"]
	check(false, "%s: did not reach boss (phase %s, distance %.2f / %.2f)"
		% [tag, stage.phase, float(stage.stage_distance), float(stage.stage_distance_target)])
	return false

## Tick until the fight in progress has been left and the next boss phase has opened.
func _advance_to_next_boss(rig: Dictionary, tag: String) -> bool:
	var stage: Node = rig["stage"]
	var left := false
	var guard := 0
	var limit := _ticks(20.0)
	while guard < limit:
		if stage.phase != &"boss":
			left = true
		elif left:
			return true
		_tick_rig(rig, 1)
		guard += 1
	check(false, "%s: never reached the next boss (phase %s)" % [tag, stage.phase])
	return false

func _tick_until(rig: Dictionary, done: Callable, seconds: float) -> int:
	var ticks := 0
	var limit := _ticks(seconds)
	while ticks < limit and not bool(done.call()):
		_tick_rig(rig, 1)
		ticks += 1
	return ticks

func _cinematic_elapsed(arena: Node) -> float:
	if StringName(arena.cinematic_mode) == &"" or float(arena.cinematic_seconds) <= 0.0:
		return 0.0
	return float(arena.cinematic_progress()) * float(arena.cinematic_seconds)

func _play_intro(rig: Dictionary, _tag: String) -> Dictionary:
	var events: Dictionary = rig["events"]
	var ended_before: int = int(events["ended"].size())
	var threat_base := _threat_now(rig)
	var ticks := 0
	var threat := ""
	var guard := _ticks(INTRO_FULL + 2.0)
	while events["ended"].size() == ended_before and ticks < guard:
		_tick_rig(rig, 1)
		ticks += 1
		# The tick that closes the intro returns before the attack clocks run, so a threat here is
		# still inside the window (contract §11.14). Baselines ignore the previous stage's shots.
		var text := _threat_delta(rig, threat_base)
		if text != "":
			threat = "%s at tick %d" % [text, ticks]
			break
		if events["ended"].size() != ended_before:
			break
	return {
		"ticks": ticks,
		"ended_delta": events["ended"].size() - ended_before,
		"ended_at": events["ended"].size(),
		"clean": threat == "",
		"threat": threat,
	}

func _wait_for_threat(rig: Dictionary, _tag: String, seconds: float) -> Dictionary:
	var events: Dictionary = rig["events"]
	var arena: Node = rig["arena"]
	var stage: Node = rig["stage"]
	var base_tele: int = int(events["boss_attack_telegraph"].size())
	var base_plan: int = int(events["boss_attack_planned"].size())
	var ticks := 0
	var limit := _ticks(seconds)
	var appeared := false
	while ticks < limit and stage.phase == &"boss" and StringName(arena.cinematic_mode) == &"":
		if events["boss_attack_telegraph"].size() > base_tele or events["boss_attack_planned"].size() > base_plan \
				or arena.tool_count() > 0 or arena.projectile_count() > 0:
			appeared = true
			break
		_tick_rig(rig, 1)
		ticks += 1
	return {"appeared": appeared, "post_ticks": ticks, "from_start": ticks * TICK}

func _threat_now(rig: Dictionary) -> Dictionary:
	var events: Dictionary = rig["events"]
	var arena: Node = rig["arena"]
	return {
		"telegraph": events["boss_attack_telegraph"].size(),
		"planned": events["boss_attack_planned"].size(),
		"tools": arena.tool_count(),
		"shots": arena.projectile_count(),
	}

func _threat_delta(rig: Dictionary, base: Dictionary) -> String:
	var now := _threat_now(rig)
	if int(now["telegraph"]) > int(base["telegraph"]):
		return "telegraph +%d" % (int(now["telegraph"]) - int(base["telegraph"]))
	if int(now["planned"]) > int(base["planned"]):
		return "planned attack +%d" % (int(now["planned"]) - int(base["planned"]))
	if int(now["tools"]) > int(base["tools"]):
		return "tool_count %d" % int(now["tools"])
	if int(now["shots"]) > int(base["shots"]):
		return "projectile_count %d" % int(now["shots"])
	return ""

func _finish_retreat(rig: Dictionary, tag: String) -> bool:
	var stage: Node = rig["stage"]
	var guard := 0
	while stage.phase == &"boss" and guard < _ticks(8.0):
		_tick_rig(rig, 1)
		guard += 1
	if stage.phase == &"boss":
		check(false, "%s: the timeout did not leave the boss (still %s after %d ticks)" % [tag, stage.phase, guard])
		return false
	return true

func _skip_current_intro(rig: Dictionary, tag: String) -> bool:
	var arena: Node = rig["arena"]
	var events: Dictionary = rig["events"]
	var ended_before: int = int(events["ended"].size())
	if StringName(arena.cinematic_mode) == &"":
		return true
	var ticks := _tick_until(rig, func() -> bool:
		return bool(arena.can_skip_cinematic()) or StringName(arena.cinematic_mode) == &"", INTRO_FULL + 1.0)
	if StringName(arena.cinematic_mode) != &"" and bool(arena.can_skip_cinematic()):
		rig["game"].skip_boss_cinematic()
	var guard := 0
	while StringName(arena.cinematic_mode) != &"" and guard < _ticks(SKIP_TAIL + 1.0):
		_tick_rig(rig, 1)
		guard += 1
	if events["ended"].size() <= ended_before or StringName(arena.cinematic_mode) != &"":
		check(false, "%s: the intro did not end (mode %s, ticks %d + %d)" % [tag, arena.cinematic_mode, ticks, guard])
		return false
	return true

func _skip_arena_intro(arena: Node) -> bool:
	var ticks := 0
	while StringName(arena.cinematic_mode) != &"" and not arena.can_skip_cinematic() and ticks < _ticks(INTRO_FULL + 1.0):
		arena.tick(TICK)
		ticks += 1
	if StringName(arena.cinematic_mode) != &"" and arena.can_skip_cinematic():
		arena.skip_cinematic()
	var guard := 0
	while StringName(arena.cinematic_mode) != &"" and guard < _ticks(SKIP_TAIL + 1.0):
		arena.tick(TICK)
		guard += 1
	return StringName(arena.cinematic_mode) == &""

func arena_can_skip(rig: Dictionary) -> bool:
	return bool(rig["arena"].can_skip_cinematic())

func _mount_recorder(arena: Node) -> Node:
	var old: Node = arena.get("visual")
	if is_instance_valid(old):
		var parent := old.get_parent()
		if parent != null:
			parent.remove_child(old)
		old.free()
	arena.set("visual", null)
	arena.set("_graybox", null)
	var boss_root: Node3D = arena.get("boss_root")
	if boss_root == null:
		return null
	var rec := Node3D.new()
	rec.set_script(recorder_script)
	boss_root.add_child(rec)
	arena.set("visual", rec)
	return rec

func _last_progress(rec: Node) -> float:
	var args := _last_named(rec.calls, &"set_cinematic_progress")
	if args.size() < 2:
		return -1.0
	return float(args[1])

func _last_progress_call(rec: Node, from_index: int) -> Array:
	var rows: Array = rec.calls.slice(from_index)
	var found: Array = []
	for entry in rows:
		if StringName(entry[0]) == &"set_cinematic_progress":
			found = entry[1]
	return found

func _last_named(calls: Array, method: StringName) -> Array:
	var found: Array = []
	for entry in calls:
		if StringName(entry[0]) == method:
			found = entry[1]
	return found

func _call_names(calls: Array) -> Array:
	var names: Array = []
	for entry in calls:
		names.append(entry[0])
	return names

func _same(got: Array, expected: Array) -> bool:
	if got.size() != expected.size():
		return false
	for i in got.size():
		if StringName(got[i]) != StringName(expected[i]):
			return false
	return true

func _has_subsequence(order: Array, needle: Array) -> bool:
	var n := 0
	for item in order:
		if n < needle.size() and StringName(item) == StringName(needle[n]):
			n += 1
	return n == needle.size()

func _has_kind(value: Variant, kind: StringName) -> bool:
	if not value is Array:
		return false
	for entry in value:
		if StringName(entry) == kind:
			return true
	return false

func _bonus_has(rows: Array, points: int, reason: StringName) -> bool:
	for row in rows:
		if int(row[0]) == points and StringName(row[1]) == reason:
			return true
	return false

func _ui_snapshot(node: Node) -> Array:
	var rows: Array = []
	_ui_walk(node, rows)
	return rows

func _ui_walk(node: Node, rows: Array) -> void:
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is RichTextLabel:
		text = (node as RichTextLabel).get_parsed_text()
	var visible := bool(node.get("visible")) if "visible" in node else true
	var modulate: Variant = node.get("modulate") if "modulate" in node else Color(1, 1, 1, 1)
	var position: Variant = node.get("position") if "position" in node else Vector2.ZERO
	rows.append([String(node.name), visible, modulate, position, text])
	for child in node.get_children():
		_ui_walk(child, rows)

func _press_jump(game: Node) -> void:
	Input.action_press("jump")
	var event := InputEventAction.new()
	event.action = "jump"
	event.pressed = true
	event.strength = 1.0
	Input.parse_input_event(event)

func _release_jump() -> void:
	if not InputMap.has_action("jump"):
		return
	Input.action_release("jump")
	var event := InputEventAction.new()
	event.action = "jump"
	event.pressed = false
	Input.parse_input_event(event)

func _silence_audio() -> void:
	_stop_players(root)
	var audio := root.get_node_or_null("AudioService")
	if audio == null:
		return
	for key in ["music", "sfx"]:
		var player := audio.get(key) as AudioStreamPlayer
		if player == null:
			continue
		player.stop()
		player.stream = null

func _stop_players(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	for child in node.get_children():
		_stop_players(child)

func _resume(game: Node) -> void:
	if is_instance_valid(game) and bool(game.paused):
		game.resume()
	paused = false

## `seconds` is game time. The bound is that many physics frames, so a slow host cannot
## exhaust the wait before the simulation has had those ticks (Godot caps physics steps per frame).
func _wait_until(predicate: Callable, seconds: float) -> bool:
	var frames := _ticks(seconds)
	for _i in frames:
		if bool(predicate.call()):
			return true
		await physics_frame
	return bool(predicate.call())

func _free_live_scene() -> void:
	if live_scene != null and is_instance_valid(live_scene):
		var scene := live_scene
		live_scene = null
		if bool(scene.paused):
			scene.resume()
		scene.free()
	paused = false

func _free_rig(rig: Dictionary) -> void:
	var game: Node = rig.get("game", null)
	if game == null or not is_instance_valid(game):
		return
	if bool(game.get("paused")):
		_resume(game)
	junk.erase(game)
	if game.get_parent() != null:
		game.get_parent().remove_child(game)
	game.free()

func _report() -> void:
	_release_jump()
	Engine.time_scale = saved_scale
	paused = false
	if runner_game_script != null:
		runner_game_script.set(&"pending_boss_checkpoint", {})
	# The audio autoload starts playback during every headless run, and the real scene swaps its
	# music. Stop it and let one frame drop the playback objects before exit.
	_silence_audio()
	await process_frame
	_free_live_scene()
	for path in temp_paths:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	for node in junk:
		if is_instance_valid(node):
			node.free()
	junk.clear()
	_silence_audio()
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	await process_frame
	await create_timer(0.3).timeout
	await process_frame
	await process_frame
	var status := "PASS" if failures == 0 else "FAIL"
	print("RUNNER BOSS CINEMATIC: ", status, " (", failures, " failures / ", checks, " checks)")
	quit(1 if failures > 0 else 0)
