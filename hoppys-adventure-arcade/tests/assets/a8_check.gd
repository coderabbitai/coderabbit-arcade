extends SceneTree
const Synth = preload("res://scenes/runner/audio/sfx_synth.gd")
const Scene = preload("res://scenes/runner/audio/runner_audio.tscn")
const Mock = preload("res://scenes/runner/ui/dev/mock_runner_game.gd")
var checks := 0
var failures := 0
var pcm_bytes := 0
var maximum := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func audio_check(stream: AudioStreamWAV, seconds: float, label: String) -> void:
	var channels := 2 if stream.stereo else 1
	var data := stream.data
	var count := data.size() / (2 * channels)
	pcm_bytes += data.size()
	check(absf(float(count) / stream.mix_rate - seconds) <= 1.0 / stream.mix_rate, label + " duration")
	for channel in channels:
		var sum := 0.0
		var peak := 0.0
		for i in count:
			var value := data.decode_s16((i * channels + channel) * 2) / 32767.0
			sum += value
			peak = maxf(peak, absf(value))
		maximum = maxf(maximum, peak)
		check(peak > 0.001 and peak <= 0.9, label + " peak")
		check(absf(sum / count) < 0.0001, label + " DC")
		var first := data.decode_s16(channel * 2) / 32767.0
		var last := data.decode_s16(((count - 1) * channels + channel) * 2) / 32767.0
		if stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			check(absf(last - first) < 0.015, label + " wrap continuity")
		else:
			check(absf(first) < 64.0 / 32767.0 and absf(last) < 64.0 / 32767.0, label + " endpoints")

func census(node: Node) -> Vector2i:
	var result := Vector2i.ZERO
	if node is MeshInstance3D:
		result.x += node.mesh.get_surface_count()
		result.y += node.mesh.get_faces().size() / 3
	if node is MultiMeshInstance3D:
		check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "cosmetic multimesh interpolation")
		result.x += 1
		result.y += node.multimesh.mesh.get_faces().size() / 3 * node.multimesh.instance_count
	for child in node.get_children(): result += census(child)
	return result

func window_metrics(stream: AudioStreamWAV, start: float, end: float) -> Vector2:
	var stride := 4 if stream.stereo else 2
	var data := stream.data
	var first := int(start * stream.mix_rate)
	var last := mini(int(end * stream.mix_rate), data.size() / stride)
	var energy := 0.0
	var peak := 0.0
	for i in range(first, last):
		var value := float(data.decode_s16(i * stride)) / 32767.0
		energy += value * value
		peak = maxf(peak, absf(value))
	return Vector2(sqrt(energy / maxi(1, last - first)), peak)

func run() -> void:
	check(Synth.RECIPES.size() == 32, "32 recipes")
	for kind: StringName in Synth.RECIPES:
		audio_check(Synth.sound(kind), Synth.RECIPES[kind][0], kind)
		check(Synth.sound(kind) == Synth.sound(kind), "cached " + kind)
	for surface in 3:
		for variant in 2:
			var step := Synth.footstep(surface, variant)
			audio_check(step, 0.07, "surface %d variant %d" % [surface, variant])
			check(step.get_meta(&"surface") == surface, "surface axis preserved")
			check(step.get_meta(&"variant") == variant, "variant axis preserved")
			check(step == Synth.footstep(surface, variant), "variant cached")
		check(Synth.footstep(surface, 0).data != Synth.footstep(surface, 1).data, "different strike PCM")
		check(Synth.footstep(surface, 0).get_meta(&"seed") != Synth.footstep(surface, 1).get_meta(&"seed"), "different strike seeds")
		check(Synth.footstep(surface, 0).get_meta(&"softness") == Synth.footstep(surface, 1).get_meta(&"softness"), "strike keeps surface filter")
	for kind: StringName in Synth.RECIPES:
		check(Synth.raw_peaks[kind] > 0.001 and Synth.raw_peaks[kind] <= 0.9, "pre-normalization peak " + kind)
	for kind: StringName in Synth.PERCUSSIVE:
		var duration := float(Synth.RECIPES[kind][0])
		check(Synth._envelope(Synth.family_for(kind), duration * 0.7, duration) < 0.02, "percussive decay " + kind)
	for kind in [&"boss_hit", &"caught", &"hit", &"land", &"roll"]:
		var duration := float(Synth.RECIPES[kind][0])
		check(Synth._envelope(Synth.family_for(kind), duration * 0.16, duration) > 0.36, "duration-scaled impact body " + kind)
		var body := window_metrics(Synth.sound(kind), duration * 0.20, duration * 0.40)
		check(body.x > 0.006, "rendered impact body audible " + kind)
	for kind in [&"boss_hit", &"caught"]:
		var duration := float(Synth.RECIPES[kind][0])
		var sub_energy := 0.0
		for i in 100:
			var t := duration * (0.2 + 0.2 * float(i) / 100.0)
			sub_energy += pow(Synth.impact_sub(t, duration), 2.0)
		check(sub_energy / 100.0 > 0.4, "impact sub persists " + kind)
	check(absf(Synth.click_transient(0.0021)) > 0.5, "separate crisp click")
	check(Synth.click_transient(0.004) == 0.0 and Synth.click_transient(0.020) == 0.0, "click ends after four milliseconds")
	var fire := Synth.sound(&"tool_fire")
	check(Synth.family_for(&"tool_fire") == &"percussive", "launch uses fast attack")
	check(window_metrics(fire, 0.0, 0.015).y >= window_metrics(fire, 0.0, 0.18).y * 0.8, "launch rendered attack within 15 ms")
	check(Synth._envelope(Synth.family_for(&"jump"), 0.12, 0.22) < 0.15, "jump has a tonal decay")
	check(Synth._envelope(Synth.family_for(&"pursuit_start"), 0.45, 0.75) > Synth._envelope(Synth.family_for(&"pursuit_start"), 0.15, 0.75) * 2.0, "pursuit second stage rises")
	for kind in [&"turn_whoosh", &"projectile_whoosh"]:
		var original := Synth.sound(kind).data
		var center := Synth.panned_whoosh(2, kind).data
		check(original == center, "center whoosh preserves stereo channels " + kind)
		var left := Synth.panned_whoosh(1, kind).data
		var right := Synth.panned_whoosh(4, kind).data
		for i in range(0, original.size(), 400):
			check(left.decode_s16(i) == original.decode_s16(i), "left whoosh preserves near channel")
			check(right.decode_s16(i + 2) == original.decode_s16(i + 2), "right whoosh preserves near channel")
	check(Synth._envelope(&"chime", 0.1, 0.65) > 0.5, "chime retains ring")
	for kind in [&"lgtm", &"recovered_chime", &"stage_clear", &"tool_pickup", &"powerup"]:
		check(Synth.LAYERS[Synth.family_for(kind)][3] == 0.0, "clean tonal noise weight " + kind)
	check(absf(Synth.sting_sub(2.405, 3.0, true)) > 0.8, "intro impact sub survives at 2.4 seconds")
	for gate in 3:
		check(absf(Synth.sting_sub(float(gate) / 9.0 + 0.005, 0.55, false)) > 0.8, "alert sub restarts each gate")
	var drone := Synth.sound(&"pursuit_drone").data
	var count := drone.size() / 2
	for i in range(count - 132, count):
		var t := float(i) / Synth.RATE
		var expected := Synth.drone_sample(t) * (0.7 + 0.3 * cos(TAU * t)) * 0.45
		check(absf(drone.decode_s16(i * 2) / 32767.0 - expected) < 0.001, "drone tail retains authored layers")
	var source := FileAccess.get_file_as_string("res://scenes/runner/audio/sfx_synth.gd")
	var sample_loop := source.get_slice("for i in count:", 1).get_slice("# Remove DC", 0)
	check(not sample_loop.contains("kind in [") and not sample_loop.contains("float(["), "no per-sample recipe arrays")
	for kind in [&"turn_whoosh", &"projectile_whoosh"]:
		for mask in 8: audio_check(Synth.panned_whoosh(mask, kind), Synth.RECIPES[kind][0], "%s mask %d" % [kind, mask])
	check(Synth.ui_click() == Synth.sound(&"telegraph_tick"), "UI tick reuse")
	for path in ["sfx_synth.gd", "runner_audio.gd", "hifi/bus_chain.gd"]:
		check(not FileAccess.get_file_as_string("res://scenes/runner/audio/" + path).contains("TIME"), "no shader TIME: " + path)
	var before := AudioServer.bus_count
	var old_send := AudioServer.get_bus_send(AudioServer.get_bus_index(&"SFX"))
	var mock := Mock.new()
	mock.autoplay = false
	root.add_child(mock)
	var audio := Scene.instantiate()
	mock.add_child(audio)
	audio.bind(mock)
	audio.bind(mock)
	check(AudioServer.bus_count == before + 2, "idempotent bus acquisition")
	var room := AudioServer.get_bus_index(&"RunnerSFX")
	var whoosh := AudioServer.get_bus_index(&"RunnerWhoosh")
	check(room >= 0 and whoosh >= 0, "named buses")
	check(AudioServer.get_bus_effect(room, 0) is AudioEffectReverb and AudioServer.get_bus_effect(room, 1) is AudioEffectCompressor, "room compressor chain")
	check(AudioServer.get_bus_effect(whoosh, 0) is AudioEffectDelay, "whoosh delay")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"SFX")) == &"RunnerSFX", "SFX sends into room")
	var second := Scene.instantiate()
	root.add_child(second)
	second.free()
	check(AudioServer.bus_count == before + 2, "overlap lease survives")
	mock.remove_child(audio)
	check(AudioServer.bus_count == before, "removal releases lease")
	mock.add_child(audio)
	check(AudioServer.bus_count == before + 2, "re-entry reacquires lease")
	check(AudioServer.get_bus_index(audio._whoosh_bus) >= 0, "re-entry whoosh route exists")
	for player in audio.get_children(): check(AudioServer.get_bus_index(player.bus) >= 0, "re-entry player route exists")
	audio.bind(mock)
	var delay := AudioServer.get_bus_effect(AudioServer.get_bus_index(audio._whoosh_bus), 0) as AudioEffectDelay
	check(is_equal_approx(delay.get_tap1_delay_ms(), 74.0) and is_equal_approx(delay.get_tap2_delay_ms(), 148.0), "delay times")
	check(is_equal_approx(delay.get_tap1_pan(), -0.8) and is_equal_approx(delay.get_tap2_pan(), 0.8), "delay pans")
	check(is_equal_approx(delay.get_tap1_level_db(), -19.0) and is_equal_approx(delay.get_tap2_level_db(), -24.0), "delay levels")
	check(not delay.is_feedback_active(), "delay feedback disabled")
	var budget := census(audio)
	check(budget == Vector2i.ZERO, "audio has zero geometry")
	for surface in 3: audio.set_footstep_surface(surface)
	audio.play_ui_click()
	var heard := {}
	audio.sound_played.connect(func(kind: StringName, _stream: AudioStream) -> void: heard[kind] = true)
	# Existing mock timeline exercises all 32 signal-triggered recipes.
	for i in 405:
		audio.one_shots.stop()
		audio.one_shots.play()
		audio._playback = audio.one_shots.get_stream_playback()
		audio._voices.clear()
		audio._voice_kinds.clear()
		mock.advance_demo(0.1)
		audio._process(0.1)
		check(audio.active_voice_count() <= 10, "voice cap")
	for kind: StringName in Synth.RECIPES: check(heard.has(kind), "trigger exercised: " + kind)
	audio._stop_all()
	audio.one_shots.play()
	audio._playback = audio.one_shots.get_stream_playback()
	audio._last_play.clear()
	audio._play(&"pursuit_drone", audio.drone)
	audio._play(&"heartbeat", audio.heartbeat)
	audio._play(&"footstep", audio.footsteps)
	for cue in [&"jump", &"land", &"roll", &"lane_left", &"lane_right", &"telegraph_tick", &"tool_pickup"]: audio._play(cue)
	check(audio.active_voice_count() == 10, "unreset burst reaches ten voices")
	for cue in Synth.RECIPES:
		audio._play(cue)
		check(audio.active_voice_count() <= 10, "unreset burst never exceeds cap")
	check(root.get_node("AudioService").get_child_count() == 2, "shared players unchanged")
	mock.free()
	await create_timer(0.3).timeout
	check(AudioServer.bus_count == before, "bus teardown")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"SFX")) == old_send, "send restored")
	print("A8 AUDIO: 32 recipes; peak=%.6f; checked PCM bytes=%d; draw census=%d; triangles=%d; textures=0" % [maximum, pcm_bytes, budget.x, budget.y])
	print("ASSET A8: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	for player in root.get_node("AudioService").get_children():
		if player is AudioStreamPlayer: player.stop()
	await create_timer(0.3).timeout
	quit(0 if failures == 0 else 1)
