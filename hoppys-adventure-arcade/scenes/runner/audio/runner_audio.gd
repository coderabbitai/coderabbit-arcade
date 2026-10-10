extends Node
const DefeatBurst = preload("res://scenes/runner/boss/defeat_burst.gd")
const BossVisual = preload("res://scenes/runner/boss/boss_visual_base.gd")
const BusChain = preload("res://scenes/runner/audio/hifi/bus_chain.gd")
var _whoosh_bus: StringName = &"SFX"
var _surface := 0
var _tread := 0
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Synth = preload("res://scenes/runner/audio/sfx_synth.gd")
const GpuWarmup = preload("res://scenes/runner/warmup/gpu_warmup.gd")
const MUSIC_PATH := "res://Assets/Backgrounds/cyberpunk-street-files/Assets/music/cyberpunk-street.ogg"
## Emitted only after an actual playback start, also usable by headless smoke tests.
signal sound_played(kind: StringName, stream: AudioStream)
var _game: Node
@onready var _audio_service: Node = get_node_or_null("/root/AudioService")
var _connections: Dictionary = {}
var _last_play: Dictionary = {}
var _clock := 0.0
# Pending lifetime and the retrigger gate use unpaused game time.
var _pending: Dictionary = {}
const PENDING_TTL := 0.12
const HIGH_PENDING_TTL := 0.30
const GATE := {&"boss_hit": 0.09, &"telegraph_tick": 0.04, &"projectile_whoosh": 0.04, &"tool_pickup": 0.04, &"tool_fire": 0.04, &"boss_phase": 0.04, &"boss_defeat": 0.04}
var _scheduled: Array[Dictionary] = []
var _intro_remaining := 0.0
var _cinematic_mode: StringName = &""
var _cinematic_seconds := 0.0
var _cinematic_bursts := 0
var _resolved_played := false
var _title_played := false
var _turn_active := false
var _clear_remaining := 0.0
var _turn_mask := 2
var _boss_active := false
var _boss_duck := 0.0
var _boss_pitch_offset := 0.0
var _whoosh_mask := 2
const HIGH_PRIORITY := {
	&"boss_intro_short": true, &"boss_explosion": true, &"boss_resolved": true, &"boss_skip": true, &"boss_title": true,
	&"turn_warning": true, &"boss_intro": true, &"stage_clear": true, &"turn_whoosh": true, &"boss_defeat": true, &"boss_phase": true, &"tool_fire": true,
	&"alert_sting": true, &"hit": true, &"caught": true, &"game_over": true, &"shield_block": true,
	&"pursuit_start": true, &"retreat": true, &"recovered_chime": true, &"powerup": true,
}
var _voice_kinds: Dictionary = {}
var _voices: Array[int] = []
var _playback: AudioStreamPlaybackPolyphonic
var _running := false
var _paused := false
var _grounded := true
var _rolling := false
var _nitro := false
var _normalized := 0.0
var _step_time := 0.0
var _pitch := 1.0
var _pursued := false
var _heartbeat_on := false
var _radar_phase := 0.0
var _radar_rate := 0.9
var _radar_age := 0.0
var _drone_fade: Tween
@onready var one_shots: AudioStreamPlayer = $OneShots
@onready var footsteps: AudioStreamPlayer = $Footsteps
@onready var drone: AudioStreamPlayer = $Drone
@onready var heartbeat: AudioStreamPlayer = $Heartbeat

func _enter_tree() -> void:
	_whoosh_bus = BusChain.acquire()

func _ready() -> void:
	# Publish this frame's shared radar phase before HUD processing.
	process_priority = -10
	for player: AudioStreamPlayer in [one_shots, footsteps, drone, heartbeat]:
		player.process_mode = Node.PROCESS_MODE_PAUSABLE

func bind(game: Node) -> void:
	# Shared warmup also covers turn cues and every panned whoosh variant. bind() runs inside the
	# game's _ready (veil opaque, before the first frame), so whatever the menu did not absorb is
	# completed here rather than one package per frame during play; then every runtime shader is
	# drawn once. Both are no-ops after the runner menu or an earlier run.
	Prewarm.warm()
	Prewarm.finish()
	GpuWarmup.run(game)
	_disconnect_game()
	_stop_all()
	_game = game
	_last_play.clear()
	_running = StringName(game.get("state")) == &"running"
	_paused = bool(game.get("paused"))
	_grounded = true
	_rolling = false
	_nitro = false
	_normalized = maxf(0.0, float(game.get("normalized_speed")))
	_pitch = 1.0
	_connections = {
		&"turn_incoming": _on_turn_warning, &"boss_cinematic": _on_cinematic, &"boss_cinematic_skipped": _on_cinematic_skipped, &"boss_cinematic_ended": _on_cinematic_ended,
		&"turn_started": _on_turn, &"turn_finished": _on_turn_finished,
		&"stage_cleared": _on_stage_clear, &"phase_changed": _on_phase,
		&"boss_spawned": _on_boss_spawned, &"boss_phase_changed": _on_boss_phase,
		&"boss_defeated": _on_boss_defeated, &"boss_retreated": _on_boss_retreated,
		&"boss_attack_telegraph": _on_telegraph, &"boss_projectile_fired": _on_projectile,
		&"tool_collected": _on_tool,
		&"run_started": _on_run_started, &"state_changed": _on_state,
		&"speed_changed": _on_speed, &"player_action": _on_action,
		&"power_up_collected": _on_powerup, &"power_up_expired": _on_expired,
		&"damage_blocked": _on_blocked, &"damage_taken": _on_damage,
		&"pursuit_started": _on_pursuit, &"pursuit_progress": _on_progress,
		&"pursuit_recovered": _on_recovered, &"caught": _on_caught,
		&"run_finished": _on_finished, &"paused_changed": _on_paused,
	}
	for event: StringName in _connections:
		if game.has_signal(event):
			game.connect(event, _connections[event])
	one_shots.play()
	_playback = one_shots.get_stream_playback() as AudioStreamPlaybackPolyphonic
	var music := load(MUSIC_PATH) as AudioStreamOggVorbis
	if music != null:
		if _audio_service != null and _audio_service.has_method("play_music"):
			_audio_service.play_music(music, -12.0)
	_on_paused(_paused)

func _disconnect_game() -> void:
	if is_instance_valid(_game):
		for event: StringName in _connections:
			if _game.has_signal(event) and _game.is_connected(event, _connections[event]):
				_game.disconnect(event, _connections[event])
	_connections.clear()

func _process(delta: float) -> void:
	if not is_instance_valid(_game) or _paused:
		return
	_tick_cinematic_audio()
	if "boss_time_factor" in _game: delta *= float(_game.get("boss_time_factor"))
	_clock += delta
	if _clear_remaining > 0.0:
		_clear_remaining = maxf(0.0, _clear_remaining - delta)
		if _clear_remaining == 0.0: _set_boss_mix(_boss_active)
	for i in range(_scheduled.size() - 1, -1, -1):
		_scheduled[i].remaining -= delta
		if float(_scheduled[i].remaining) <= 0:
			_play(_scheduled[i].kind)
			_scheduled.remove_at(i)
	if _pursued:
		var next_phase := _radar_phase + delta * _radar_rate
		_radar_age += delta
		if next_phase >= 1.0 and not _heartbeat_on:
			# One audible blip per visual revolution. The cached loop's other
			# passes remain silent, preserving the specified sweep and pitch rates.
			heartbeat.seek(0.0)
			_radar_age = 0.0
		_radar_phase = fposmod(next_phase, 1.0)
		if not _heartbeat_on:
			heartbeat.volume_db = 0.0 if _radar_age < 0.04 / heartbeat.pitch_scale else -80.0
	# Important retries get first access to slots released by the mixer.
	for high_priority in [true, false]:
		for kind: StringName in _pending.keys():
			if HIGH_PRIORITY.has(kind) != high_priority:
				continue
			var ttl := HIGH_PENDING_TTL if high_priority else PENDING_TTL
			if _clock - float(_pending[kind]) > ttl:
				_pending.erase(kind)
			else:
				_play(kind)
	var target := 1.0 + 0.10 * _normalized + (0.05 if _nitro else 0.0) + _boss_pitch_offset
	if _cinematic_mode != &"":
		var p := clampf(float(_game.get("boss_cinematic_progress")), 0, 1)
		# Mechanical tape stop under the held title; restore before the camera returns.
		var stop := smoothstep(0.18, 0.40, p) * (1.0 - smoothstep(0.66, 0.90, p))
		_pitch = lerpf(target, 0.18, stop) if String(_cinematic_mode).begins_with("intro") else maxf(0.18, float(_game.get("boss_time_factor")))
	else:
		_pitch = 1.0 if _clear_remaining > 0.0 else lerpf(_pitch, target, 1.0 - exp(-5.0 * delta))
	if _audio_service != null and _audio_service.has_method("set_music_pitch"):
		_audio_service.set_music_pitch(_pitch)
	if _running and _grounded and not _rolling:
		_step_time += delta
		if _step_time >= lerpf(0.42, 0.20, clampf(_normalized, 0.0, 1.0)):
			_step_time = 0.0
			_play(&"footstep", footsteps)
	else:
		_step_time = 0.0

func _play(kind: StringName, player: AudioStreamPlayer = null) -> void:
	if _paused or _clock - float(_last_play.get(kind, -1.0)) < float(GATE.get(kind, 0.04)):
		return
	var stream := Synth.panned_whoosh(_whoosh_mask) if kind == &"projectile_whoosh" else Synth.sound(kind)
	if kind == &"turn_whoosh": stream = Synth.panned_whoosh(_turn_mask, kind)
	if kind == &"footstep":
		stream = Synth.footstep(_surface, _tread % 2)
		_tread += 1
	if stream == null:
		return
	if player != null:
		player.stream = stream
		player.play()
	else:
		if _playback == null:
			return
		_prune_voices()
		# Reserve released slots for important pending cues, even on fresh ambient calls.
		if not HIGH_PRIORITY.has(kind) and _high_pending_count() > 0:
			_queue(kind)
			return
		var voice := _playback.play_stream(stream, 0.0, 0.0, 1.0, AudioServer.PLAYBACK_TYPE_DEFAULT, _whoosh_bus if kind in [&"turn_whoosh", &"projectile_whoosh", &"nitro"] else &"SFX")
		if voice == AudioStreamPlaybackPolyphonic.INVALID_ID:
			_queue(kind)
			var poly := one_shots.stream as AudioStreamPolyphonic
			if poly == null:
				return
			# A stopped slot is released on a later mixer tick. Count those reserved
			# slots so repeated retries do not keep evicting additional live voices.
			if HIGH_PRIORITY.has(kind) and _voices.size() + _high_pending_count() > poly.polyphony:
				for i in _voices.size():
					var oldest := _voices[i]
					if not HIGH_PRIORITY.has(_voice_kinds[oldest]):
						_playback.stop_stream(oldest)
						_voice_kinds.erase(oldest)
						_voices.remove_at(i)
						break
			return
		_voices.append(voice)
		_voice_kinds[voice] = kind
	_pending.erase(kind)
	_last_play[kind] = _clock
	sound_played.emit(kind, stream)

func _queue(kind: StringName) -> void:
	if not _pending.has(kind):
		_pending[kind] = _clock

func _high_pending_count() -> int:
	var count := 0
	for kind: StringName in _pending:
		if HIGH_PRIORITY.has(kind):
			count += 1
	return count

func _prune_voices() -> void:
	if _playback != null:
		for i in range(_voices.size() - 1, -1, -1):
			if not _playback.is_stream_playing(_voices[i]):
				_voice_kinds.erase(_voices[i])
				_voices.remove_at(i)

func active_voice_count() -> int:
	_prune_voices()
	return _voices.size() + int(footsteps.playing) + int(drone.playing) + int(heartbeat.playing)

func _on_run_started(_seed: int) -> void:
	_stop_pursuit()
	_grounded = true
	_rolling = false
	_nitro = false
	_step_time = 0.0

func _on_state(state: StringName) -> void:
	_running = state == &"running"
	if not _running:
		footsteps.stop()

func _on_speed(_speed: float, normalized: float) -> void:
	_normalized = maxf(0.0, normalized)

func _on_action(action: StringName) -> void:
	match action:
		&"jump", &"super_jump":
			_grounded = false
			footsteps.stop()
			_play(&"jump")
		&"land":
			_grounded = true
			_play(&"land")
		&"roll":
			_rolling = true
			footsteps.stop()
			_play(&"roll")
		&"roll_end": _rolling = false
		&"lane_left", &"lane_right": _play(action)

func _on_powerup(kind: StringName, _duration: float) -> void:
	_play(&"powerup")
	if kind in [&"nitro", &"lgtm", &"auto_fix"]:
		_play(kind)
	if kind == &"nitro":
		_nitro = true

func _on_expired(kind: StringName) -> void:
	if kind == &"nitro":
		_nitro = false

func _on_blocked(_kind: StringName, _reason: StringName) -> void:
	_play(&"shield_block")

func _on_damage(_kind: StringName, _hp: int) -> void:
	_play(&"hit")
	if _audio_service != null and _audio_service.has_method("duck_music"):
		_audio_service.duck_music(-6, 0.4)

func _on_pursuit(_seconds: float) -> void:
	_stop_pursuit()
	_pursued = true
	_heartbeat_on = false
	_play(&"pursuit_start")
	_play(&"alert_sting")
	_radar_phase = 0.0
	_radar_age = 0.0
	_radar_rate = 0.9
	heartbeat.pitch_scale = 0.8
	heartbeat.volume_db = 0.0
	_play(&"radar_pulse", heartbeat)
	drone.volume_db = -36.0
	_play(&"pursuit_drone", drone)
	_drone_fade = create_tween()
	_drone_fade.tween_property(drone, "volume_db", -10.0, 0.4)

func pursuit_radar_phase() -> float:
	return _radar_phase

func _on_progress(remaining: float, total: float) -> void:
	if not _pursued or total <= 0:
		return
	var fraction := clampf(remaining / total, 0, 1)
	_radar_rate = lerpf(0.9, 4.2, 1 - fraction)
	if not _heartbeat_on:
		heartbeat.pitch_scale = lerpf(0.8, 1.6, 1 - fraction)
		if fraction < 0.35:
			heartbeat.pitch_scale = 0.8
			heartbeat.volume_db = 0.0
			_play(&"heartbeat", heartbeat)
			_heartbeat_on = heartbeat.playing and heartbeat.stream == Synth.sound(&"heartbeat")

func _stop_pursuit() -> void:
	_pursued = false
	_heartbeat_on = false
	heartbeat.stop()
	if _drone_fade != null:
		_drone_fade.kill()
		_drone_fade = null
	drone.stop()

func _fade_pursuit() -> void:
	_pursued = false
	_heartbeat_on = false
	heartbeat.stop()
	if _drone_fade != null:
		_drone_fade.kill()
	_drone_fade = create_tween()
	_drone_fade.tween_property(drone, "volume_db", -60.0, 0.3)
	_drone_fade.tween_callback(drone.stop)

func _on_recovered(_reason: StringName) -> void:
	_fade_pursuit()
	_play(&"retreat")
	_play(&"recovered_chime")

func _on_caught() -> void:
	_end_boss_audio()
	_running = false
	_nitro = false
	footsteps.stop()
	_fade_pursuit()
	_play(&"caught")

func _on_finished(_result: Dictionary) -> void:
	_end_boss_audio()
	_running = false
	_nitro = false
	footsteps.stop()
	_stop_pursuit()
	_play(&"game_over")

func _on_paused(value: bool) -> void:
	_paused = value
	for player: AudioStreamPlayer in [one_shots, footsteps, drone, heartbeat]:
		player.stream_paused = value
	if _drone_fade != null and _drone_fade.is_valid():
		if value:
			_drone_fade.pause()
		else:
			_drone_fade.play()

func _stop_all() -> void:
	_end_boss_audio()
	_stop_pursuit()
	one_shots.stop()
	footsteps.stop()
	_voices.clear()
	_voice_kinds.clear()
	_pending.clear()
	_playback = null

func _exit_tree() -> void:
	_disconnect_game()
	_stop_all()
	BusChain.release()
	if _audio_service != null and _audio_service.has_method("set_music_pitch"):
		_audio_service.set_music_pitch(1.0)

func _duck(db: float, seconds: float) -> void:
	if _audio_service != null and _audio_service.has_method("duck_music"):
		_audio_service.duck_music(db, seconds)

func _set_boss_mix(active: bool) -> void:
	var target := -18.0 if _cinematic_mode != &"" else -12.0 if _intro_remaining > 0.0 else -10.0 if _clear_remaining > 0.0 else (-5.0 if _turn_active else (-4.0 if active else 0.0))
	_boss_pitch_offset = 0.04 if active else 0.0
	if is_equal_approx(_boss_duck, target): return
	# Hold the service's baseline so transient ducks return to the fight level.
	if _audio_service != null and _audio_service.has_method("duck_music") and "music_volume_db" in _audio_service:
		_audio_service.set("music_volume_db", float(_audio_service.get("music_volume_db")) + target - _boss_duck)
		_duck(0, 1.2 if _clear_remaining > 0.0 else (0.5 if _turn_active else (0.6 if active else 0.2)))
	_boss_duck = target

func _on_boss_spawned(_kind: StringName, _hp: int) -> void:
	_boss_active = true
	_set_boss_mix(true)

func _on_boss_phase(_phase: int) -> void:
	_play(&"boss_phase")
	# Another 4 dB below the held -4 dB baseline gives the -8 dB punch.
	_duck(-4 if _boss_active else -8, 0.35)

func _end_boss_audio() -> void:
	_on_cinematic_ended(_cinematic_mode)
	for kind in [&"boss_intro", &"turn_warning", &"turn_whoosh"]: _stop_cue(kind)
	_intro_remaining = 0.0
	_boss_active = false
	_turn_active = false
	_clear_remaining = 0.0
	_scheduled.clear()
	_set_boss_mix(false)

func _on_boss_defeated(_kind: StringName, _bonus: int) -> void:
	_stop_cue(&"boss_intro")
	_intro_remaining = 0.0
	for i in range(_scheduled.size() - 1, -1, -1):
		if _scheduled[i].kind == &"telegraph_tick": _scheduled.remove_at(i)
	# Preserve the killing tool's delayed fire/hit through the short outro.
	_boss_active = false
	_set_boss_mix(false)
	_play(&"boss_defeat")

func _on_boss_retreated(_kind: StringName, _bonus: int) -> void:
	_end_boss_audio()

func _on_telegraph(_mask: int, _kind: StringName, seconds: float) -> void:
	_play(&"telegraph_tick")
	_scheduled.append({"kind": &"telegraph_tick", "remaining": seconds * 0.55})
	_scheduled.append({"kind": &"telegraph_tick", "remaining": seconds * 0.85})

func _on_projectile(_projectile: Area3D, mask: int, _kind: StringName, _speed: float) -> void:
	_whoosh_mask = mask
	_play(&"projectile_whoosh")

func _on_tool(_kind: StringName, damage: int) -> void:
	_play(&"tool_pickup")
	_scheduled.append({"kind": &"tool_fire", "remaining": 0.10})
	if damage > 0: _scheduled.append({"kind": &"boss_hit", "remaining": 0.14})

func _on_turn(direction: int, _seconds: float) -> void:
	_turn_active = true
	_turn_mask = 1 if direction < 0 else 4
	_set_boss_mix(false)
	_stop_cue(&"turn_warning")
	_play(&"turn_whoosh")
	_pitch_cue(&"turn_whoosh", 2.4 / maxf(_seconds, 0.05))

func _on_turn_finished() -> void:
	_stop_cue(&"turn_warning")
	_stop_cue(&"turn_whoosh")
	_turn_active = false
	_set_boss_mix(_boss_active)

func _on_stage_clear(_index: int, _bonus: int) -> void:
	_clear_remaining = 2.8
	_pitch = 1.0
	_set_boss_mix(false)
	if _audio_service != null and _audio_service.has_method("set_music_pitch"): _audio_service.set_music_pitch(1.0)
	_play(&"stage_clear")

func _on_phase(value: StringName) -> void:
	if value in [&"idle", &"run"]:
		_turn_active = false
		_clear_remaining = 0.0
		_set_boss_mix(false)

func _on_turn_warning(_direction: int, seconds: float) -> void:
	_play(&"turn_warning")
	# Scale the three authored ticks to the facade's warning window.
	_pitch_cue(&"turn_warning", 3.0 / maxf(seconds, 0.05))

func _on_cinematic(_kind: StringName, mode: StringName, seconds: float) -> void:
	_cinematic_mode = mode
	_cinematic_seconds = seconds
	_cinematic_bursts = 0
	_resolved_played = false
	_title_played = false
	_intro_remaining = seconds if String(mode).begins_with("intro") else 0.0
	_set_boss_mix(_boss_active)
	if mode == &"intro_full": _play(&"boss_intro")
	elif mode == &"intro_short": _play(&"boss_intro_short")

func _tick_cinematic_audio() -> void:
	if _cinematic_mode == &"": return
	var p := clampf(float(_game.get("boss_cinematic_progress")), 0, 1)
	_intro_remaining = (1 - p) * _cinematic_seconds if String(_cinematic_mode).begins_with("intro") else 0.0
	if String(_cinematic_mode).begins_with("defeat"):
		while _cinematic_bursts < DefeatBurst.BEATS.size() and p >= float(DefeatBurst.BEATS[_cinematic_bursts]):
			_play(&"boss_explosion")
			_cinematic_bursts += 1
		if p >= 0.60 and not _resolved_played:
			_resolved_played = true
			_play(&"boss_resolved")
	else:
		if p >= float(BossVisual.INTRO_POSE_AT.get(_cinematic_mode, 1.0)) and not _title_played:
			_title_played = true
			_play(&"boss_title")
	for kind in [&"boss_defeat", &"boss_explosion"]:
		_pitch_cue(kind, maxf(0.2, float(_game.get("boss_time_factor"))))

func _on_cinematic_skipped(_mode: StringName) -> void:
	_stop_cue(&"boss_intro")
	_stop_cue(&"boss_intro_short")
	_stop_cue(&"boss_title")
	_title_played = true
	_cinematic_mode = &""
	_intro_remaining = 0.0
	_pitch = 1.0
	_set_boss_mix(_boss_active)
	_play(&"boss_skip")

func _on_cinematic_ended(_mode: StringName) -> void:
	for kind in [&"boss_intro", &"boss_intro_short", &"boss_title", &"boss_explosion", &"boss_resolved", &"boss_skip"]:
		_stop_cue(kind)
	_cinematic_mode = &""
	_intro_remaining = 0.0
	_cinematic_bursts = 0
	_pitch = 1.0
	_set_boss_mix(_boss_active)
	if _audio_service != null and _audio_service.has_method("set_music_pitch"): _audio_service.set_music_pitch(1.0)

func _pitch_cue(kind: StringName, pitch: float) -> void:
	if _playback == null: return
	for voice in _voices:
		if _voice_kinds.get(voice) == kind: _playback.set_stream_pitch_scale(voice, pitch)

func _stop_cue(kind: StringName) -> void:
	_pending.erase(kind)
	if _playback == null: return
	for voice in _voices:
		if _voice_kinds.get(voice) == kind: _playback.stop_stream(voice)

## Optional frontend hooks. Surface 0 metal, 1 grating, 2 rubber.
func set_footstep_surface(surface: int) -> void:
	_surface = clampi(surface, 0, 2)
	_tread = 0

## Gameplay-only audition hook. Paused UI must use AudioService.play_ui.
func play_ui_click() -> void:
	_play(&"telegraph_tick")
