extends SceneTree
## Presentation-only checks for boss_cinematic.tscn and boss_copy.gd.
## Run with --path hoppys-adventure-arcade --script res://tests/runner_boss_presentation.gd.

const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const BossCopy = preload("res://scenes/runner/ui/boss_copy.gd")
const CinematicScene = preload("res://scenes/runner/ui/boss_cinematic.tscn")
const BossHud = preload("res://scenes/runner/ui/boss_hud.gd")
const PostFX = preload("res://scenes/runner/ui/post_fx.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const RunnerAudioScene = preload("res://scenes/runner/audio/runner_audio.tscn")
var scratch_board := "user://runner_boss_presentation_%d.cfg" % (randi() % 1000000)

class Facade extends Node:
	signal boss_cinematic(kind: StringName, mode: StringName, seconds: float)
	signal boss_cinematic_skipped(mode: StringName)
	signal boss_cinematic_ended(mode: StringName)
	signal boss_defeated(kind: StringName, bonus: int)
	signal boss_spawned(kind: StringName, hp: int)
	signal boss_health_changed(hp: int, max_hp: int)
	signal boss_phase_changed(phase: int)
	signal boss_retreated(kind: StringName, bonus: int)
	signal tool_collected(kind: StringName, damage: int)
	signal phase_changed(phase: StringName)
	signal caught
	signal run_started(seed: int)
	signal stage_cleared(index: int, bonus: int)
	var leaderboard_path := ""
	var paused := false
	var state: StringName = &"running"
	var normalized_speed := 0.0
	var stage_index := 1
	var boss_cinematic_progress := 0.0
	var boss_time_factor := 1.0
	var config: Resource
	var can_skip := false
	var boss_info := {
		"kind": &"flaky_test_swarm", "name": "Flaky Test Swarm", "hp": 100,
		"max_hp": 100, "phase": 1, "phase_count": 3, "accepted_tools": [],
		"pending_attacks": []
	}

	func get_boss_info() -> Dictionary:
		return boss_info

	func can_skip_boss_cinematic() -> bool:
		return can_skip and not paused

class RecordingRunnerAudio extends "res://scenes/runner/audio/runner_audio.gd":
	var stop_requests: Array[StringName] = []

	func _stop_cue(kind: StringName) -> void:
		stop_requests.append(kind)
		super._stop_cue(kind)

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER BOSS PRESENTATION: " + message)

func run() -> void:
	_test_copy_contract()
	var facade := Facade.new()
	## Set the scratch board path before adding the facade, matching runner_game fixture setup.
	facade.leaderboard_path = scratch_board
	root.add_child(facade)
	var cinematic := CinematicScene.instantiate()
	root.add_child(cinematic)
	cinematic.bind(facade)
	_test_full_timing_and_skip(cinematic, facade)
	_test_full_card_dwell(cinematic, facade)
	_test_short_mode(cinematic, facade)
	_test_pause_freezes_presentation(cinematic, facade)
	_test_resolved_bonus(cinematic, facade)
	_test_zero_length_hp_plate(facade)
	_test_post_fx_skip_tail(facade)
	await _test_audio_defeat_fanfare_lifecycle()
	var audio_service := root.get_node_or_null("AudioService")
	if audio_service != null and audio_service.has_method("shutdown"):
		audio_service.shutdown()
		await process_frame
		await create_timer(0.3).timeout
	for child in root.get_children():
		if child != self:
			child.free()
	await process_frame
	print("RUNNER BOSS PRESENTATION: %s (%d checks / %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _test_copy_contract() -> void:
	for stage in range(1, 4):
		var def: Dictionary = BossDefs.base_def(stage)
		var rows: Array[Dictionary] = BossCopy.hint_rows(def)
		check(rows.size() == BossDefs.PHASE_COUNT, "%s has one hint row per phase" % def.kind)
		for phase in range(1, BossDefs.PHASE_COUNT + 1):
			if phase > rows.size():
				continue
			var row: Dictionary = rows[phase - 1]
			var accepted: Array[StringName] = BossDefs.accepted_tools(def, phase)
			var accepts_every_tool := accepted.size() == ToolDefs.kinds().size()
			check(row.phase == phase, "%s hint row has phase %d" % [def.kind, phase])
			check(row.accepted_tools == accepted, "%s phase %d copy eligibility matches BossDefs.accepted_tools" % [def.kind, phase])
			check(row.all_tools == accepts_every_tool, "%s phase %d all-tools marker matches acceptance" % [def.kind, phase])
			var expected_tools: Array = Array(accepted)
			check(row.tools == expected_tools, "%s phase %d glyph list matches accepted tools" % [def.kind, phase])
	check(BossCopy.epithet(&"flaky_test_swarm", 1).find("REGRESSED") == -1, "first lap epithet has no regression tag")
	check(BossCopy.epithet(&"flaky_test_swarm", 2).contains("REGRESSED v2"), "second lap epithet has regression tag")

func _test_full_timing_and_skip(cinematic: Node, facade: Facade) -> void:
	facade.can_skip = false
	facade.boss_cinematic.emit(&"flaky_test_swarm", &"intro_full", 5.0)
	facade.boss_cinematic_progress = 0.399
	update_cinematic(cinematic)
	check(not cinematic.title_group.visible, "full title stays hidden before its facade-progress threshold")
	facade.boss_cinematic_progress = 0.40
	update_cinematic(cinematic)
	check(cinematic.title_group.visible, "full title appears at its facade-progress threshold")
	check(cinematic.threat.visible and cinematic.threat.visible_characters == 0, "threat typing starts with title timing")
	facade.boss_cinematic_progress = 0.50
	update_cinematic(cinematic)
	var typed_at_half: int = cinematic.threat.visible_characters
	check(typed_at_half == 12, "threat typing advances at 40 characters per facade-clock second")
	update_cinematic(cinematic)
	check(cinematic.threat.visible_characters == typed_at_half, "fixed facade progress produces fixed title-card text")
	facade.boss_cinematic_progress = 0.099
	update_cinematic(cinematic)
	check(not cinematic.skip_prompt.visible, "full intro does not show skip before the 0.5-second backend guard")
	facade.can_skip = true
	facade.boss_cinematic_progress = 0.10
	update_cinematic(cinematic)
	check(cinematic.skip_prompt.visible, "full intro shows skip when the facade says the 0.5-second guard is open")
	facade.boss_cinematic_ended.emit(&"intro_full")
	facade.can_skip = false

func _test_short_mode(cinematic: Node, facade: Facade) -> void:
	facade.can_skip = false
	facade.boss_cinematic.emit(&"merge_conflict_hydra", &"intro_short", 2.5)
	facade.boss_cinematic_progress = 0.199
	update_cinematic(cinematic)
	check(not cinematic.skip_prompt.visible, "short skip prompt stays hidden before the 0.5-second facade guard")
	facade.boss_cinematic_progress = 0.28
	update_cinematic(cinematic)
	check(cinematic.title_group.visible, "short title appears from the facade clock")
	check(not cinematic.chyron.visible and not cinematic.source_path.visible, "short intro omits chyron and source path")
	check(not cinematic.threat.visible and not cinematic.hints.visible, "short intro omits threat and tool hints")
	check(not cinematic.skip_prompt.visible and not cinematic.resolved.visible, "short intro presents its title and epithet without threat or resolved copy")
	facade.can_skip = true
	facade.boss_cinematic_progress = 0.28
	update_cinematic(cinematic)
	check(cinematic.skip_prompt.visible, "short intro shows skip when the facade says the 0.5-second guard is open")
	facade.boss_cinematic_skipped.emit(&"intro_short")
	check(not cinematic.skip_prompt.visible, "short skip prompt hides after the facade reports a skip")
	facade.can_skip = false

func _test_full_card_dwell(cinematic: Node, facade: Facade) -> void:
	const CARD_SECONDS := 5.0
	const SAMPLE_SECONDS := 0.005
	const THREAT_DWELL_REQUIRED := 1.2
	const HINTS_DWELL_REQUIRED := 1.0
	for stage in range(1, 4):
		facade.stage_index = stage
		facade.can_skip = false
		var kind: StringName = BossDefs.base_def(stage).kind
		facade.boss_cinematic.emit(kind, &"intro_full", CARD_SECONDS)
		var threat_visible := false
		var threat_dwell := 0.0
		var longest_threat_dwell := 0.0
		var hints_visible := false
		var hints_dwell := 0.0
		var longest_hints_dwell := 0.0
		for sample in range(1, int(CARD_SECONDS / SAMPLE_SECONDS) + 1):
			var elapsed := float(sample) * SAMPLE_SECONDS
			facade.boss_cinematic_progress = elapsed / CARD_SECONDS
			update_cinematic(cinematic)
			var threat_fully_shown: bool = (
				cinematic.threat.visible
				and cinematic.threat.visible_characters >= cinematic.threat.get_total_character_count()
				and cinematic.threat.modulate.a >= 0.999
			)
			if threat_fully_shown:
				threat_dwell = threat_dwell + SAMPLE_SECONDS if threat_visible else 0.0
				threat_visible = true
				longest_threat_dwell = maxf(longest_threat_dwell, threat_dwell)
			else:
				threat_visible = false
				threat_dwell = 0.0
			var hints_fully_shown: bool = cinematic.hints.visible and cinematic.hints.modulate.a >= 0.999
			if hints_fully_shown:
				hints_dwell = hints_dwell + SAMPLE_SECONDS if hints_visible else 0.0
				hints_visible = true
				longest_hints_dwell = maxf(longest_hints_dwell, hints_dwell)
			else:
				hints_visible = false
				hints_dwell = 0.0
		check(longest_threat_dwell >= THREAT_DWELL_REQUIRED,
			"stage %d threat copy is fully typed and visible at full alpha for at least 1.2 seconds" % stage)
		check(longest_hints_dwell >= HINTS_DWELL_REQUIRED,
			"stage %d tool hints are visible at full alpha for at least 1.0 second" % stage)
		print("BOSS PRESENTATION DWELL: stage=%d threat=%.3fs hints=%.3fs" % [stage, longest_threat_dwell, longest_hints_dwell])
		facade.boss_cinematic_ended.emit(&"intro_full")

func _test_pause_freezes_presentation(cinematic: Node, facade: Facade) -> void:
	facade.boss_cinematic.emit(&"flaky_test_swarm", &"intro_full", 5.0)
	facade.boss_cinematic_progress = 0.50
	update_cinematic(cinematic)
	var chars_before_pause: int = cinematic.threat.visible_characters
	facade.paused = true
	facade.boss_cinematic_progress = 0.65
	update_cinematic(cinematic)
	check(cinematic.threat.visible_characters == chars_before_pause, "paused facade progress does not advance cinematic copy")
	facade.paused = false
	update_cinematic(cinematic)
	check(cinematic.threat.visible_characters > chars_before_pause, "presentation resumes from the updated facade progress")
	facade.boss_cinematic_ended.emit(&"intro_full")

func _test_resolved_bonus(cinematic: Node, facade: Facade) -> void:
	facade.can_skip = true
	facade.boss_defeated.emit(&"legacy_monolith", 245)
	facade.boss_cinematic.emit(&"legacy_monolith", &"defeat_full", 3.6)
	facade.boss_cinematic_progress = 0.599
	update_cinematic(cinematic)
	check(not cinematic.resolved.visible, "resolved callout stays hidden before 60 percent")
	check(not cinematic.skip_prompt.visible, "defeat cinematic never shows the skip prompt")
	facade.boss_cinematic_progress = 0.60
	update_cinematic(cinematic)
	check(cinematic.resolved.visible and cinematic.resolved_title.text == "THREAD RESOLVED", "resolved callout appears at 60 percent")
	check(cinematic.bonus_label.text.contains("245"), "resolved callout displays the boss-defeated bonus")
	facade.boss_cinematic_ended.emit(&"defeat_full")
	facade.can_skip = false

func _test_zero_length_hp_plate(facade: Facade) -> void:
	var hud := BossHud.new()
	root.add_child(hud)
	hud.bind(facade)
	## Contract sends no cinematic signal for a zero-length intro. Spawn must reveal the plate itself.
	facade.boss_spawned.emit(&"flaky_test_swarm", 100)
	check(hud.visible and hud._fight_active, "zero-length intro with no cinematic signal shows the HP plate on spawn")

func _test_post_fx_skip_tail(facade: Facade) -> void:
	facade.config = RunConfig.new()
	facade.config.set("boss_cinematic_skip_tail", 0.8)
	facade.boss_time_factor = 1.0
	facade.boss_cinematic_progress = 0.0
	var post_fx := PostFX.new()
	root.add_child(post_fx)
	post_fx.bind(facade)
	facade.boss_cinematic.emit(&"flaky_test_swarm", &"intro_full", 5.0)
	facade.boss_cinematic_progress = 0.84
	facade.boss_cinematic_skipped.emit(&"intro_full")
	check(is_equal_approx(float(post_fx.values.letterbox), 1.0), "post FX keeps letterbox fully open at the configured skip-tail start")
	facade.boss_cinematic_progress = 0.92
	post_fx._process(0.0)
	check(is_equal_approx(float(post_fx.values.letterbox), 0.5), "post FX letterbox eases halfway through the configured skip tail")
	facade.boss_cinematic_progress = 1.0
	post_fx._process(0.0)
	facade.boss_cinematic_ended.emit(&"intro_full")
	post_fx._process(0.0)
	check(is_equal_approx(float(post_fx.values.letterbox), 0.0), "post FX letterbox reaches zero at cinematic end")
	var clock_before := post_fx.clock
	facade.boss_time_factor = 0.4
	post_fx._process(1.0)
	check(is_equal_approx(post_fx.clock - clock_before, 0.4), "post FX local clock applies the facade boss time factor")
	post_fx.bind(null)

func _test_audio_defeat_fanfare_lifecycle() -> void:
	var facade := Facade.new()
	facade.leaderboard_path = scratch_board
	root.add_child(facade)
	var audio := RunnerAudioScene.instantiate()
	audio.set_script(RecordingRunnerAudio)
	root.add_child(audio)
	audio.bind(facade)
	var stops: Array[StringName] = audio.get("stop_requests")
	stops.clear()
	var first_voice := _start_resolved_voice(audio, facade)
	var playback: AudioStreamPlaybackPolyphonic = audio.get("_playback")
	check(first_voice != AudioStreamPlaybackPolyphonic.INVALID_ID and playback.is_stream_playing(first_voice),
		"defeat-short fanfare starts as a real polyphonic playback voice")
	facade.boss_cinematic_progress = 1.0
	facade.boss_cinematic_ended.emit(&"defeat_short")
	check(not stops.has(&"boss_resolved"), "cinematic end does not request stopping the resolved fanfare")
	facade.stage_cleared.emit(1, 400)
	check(not stops.has(&"boss_resolved"), "stage clear leaves the resolved fanfare stop request history unchanged")
	check(playback.is_stream_playing(first_voice), "resolved fanfare remains a real active voice before catch cleanup")
	facade.caught.emit()
	await process_frame
	check(stops.has(&"boss_resolved"), "catch cleanup requests stopping the resolved fanfare after cinematic end")
	await create_timer(0.5).timeout
	check(not playback.is_stream_playing(first_voice), "catch cleanup stops the resolved fanfare playback voice")
	stops.clear()
	var run_started_voice := _start_resolved_voice(audio, facade)
	check(run_started_voice != AudioStreamPlaybackPolyphonic.INVALID_ID and playback.is_stream_playing(run_started_voice),
		"run-start cleanup fixture starts a real resolved fanfare voice")
	facade.run_started.emit(2)
	await process_frame
	check(stops.has(&"boss_resolved"), "new-run cleanup requests stopping the prior cinematic fanfare")
	await create_timer(0.5).timeout
	check(not playback.is_stream_playing(run_started_voice), "new-run cleanup stops the prior resolved playback voice")
	stops.clear()
	var teardown_voice := _start_resolved_voice(audio, facade)
	var teardown_playback: AudioStreamPlaybackPolyphonic = audio.get("_playback")
	check(teardown_voice != AudioStreamPlaybackPolyphonic.INVALID_ID and teardown_playback.is_stream_playing(teardown_voice),
		"teardown fixture starts another real resolved fanfare voice")
	audio.queue_free()
	await process_frame
	check(stops.has(&"boss_resolved"), "RunnerAudio teardown requests stopping active resolved fanfare")
	await create_timer(0.5).timeout
	check(not teardown_playback.is_stream_playing(teardown_voice), "RunnerAudio teardown stops active cinematic voices")

func _start_resolved_voice(audio: Node, facade: Facade) -> int:
	facade.boss_cinematic_progress = 0.0
	facade.boss_cinematic.emit(&"legacy_monolith", &"defeat_short", 2.0)
	facade.boss_cinematic_progress = 0.60
	audio._process(0.0)
	for voice: int in audio.get("_voices"):
		if audio.get("_voice_kinds").get(voice) == &"boss_resolved":
			return voice
	return AudioStreamPlaybackPolyphonic.INVALID_ID

func update_cinematic(cinematic: Node) -> void:
	cinematic._process(0.0)
