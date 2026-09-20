extends Node
const Synth = preload("res://scenes/runner/audio/sfx_synth.gd")
const MUSIC_PATH := "res://Assets/cyberpunk-street-files/Assets/music/cyberpunk-street.ogg"
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
const HIGH_PRIORITY := {
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

func _ready() -> void:
	# Publish this frame's shared radar phase before HUD processing.
	process_priority = -10

func bind(game: Node) -> void:
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
			if _game.is_connected(event, _connections[event]):
				_game.disconnect(event, _connections[event])
	_connections.clear()

func _process(delta: float) -> void:
	if not is_instance_valid(_game) or _paused:
		return
	_clock += delta
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
	var target := 1.0 + 0.10 * _normalized + (0.05 if _nitro else 0.0)
	_pitch = lerpf(_pitch, target, 1.0 - exp(-5.0 * delta))
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
	if _paused or _clock - float(_last_play.get(kind, -1.0)) < 0.04:
		return
	var stream := Synth.sound(kind)
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
		var voice := _playback.play_stream(stream, 0.0, 0.0, 1.0, AudioServer.PLAYBACK_TYPE_DEFAULT, &"SFX")
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
	_running = false
	_nitro = false
	footsteps.stop()
	_fade_pursuit()
	_play(&"caught")

func _on_finished(_result: Dictionary) -> void:
	_running = false
	_nitro = false
	footsteps.stop()
	_stop_pursuit()
	_play(&"game_over")

func _on_paused(value: bool) -> void:
	_paused = value
	for player: AudioStreamPlayer in [one_shots, footsteps, drone, heartbeat]:
		player.stream_paused = value
	if _drone_fade != null:
		if value:
			_drone_fade.pause()
		else:
			_drone_fade.play()

func _stop_all() -> void:
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
	if _audio_service != null and _audio_service.has_method("set_music_pitch"):
		_audio_service.set_music_pitch(1.0)
