extends Node
## Longest the exit waits for the mixer to release stopped voices (see _exit_tree). Two mixes take
## about 25 ms with a sound card and about 140 ms headless.
const RELEASE_MSEC := 500
var music := AudioStreamPlayer.new()
var sfx := AudioStreamPlayer.new()
var tones: Array[AudioStreamWAV] = []
var default_track: AudioStream
var music_volume_db := -10.0
var duck: Tween
func _ready() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	music.bus = "Music"
	sfx.bus = "SFX"
	add_child(music)
	add_child(sfx)
	var track := load("res://Assets/Audio/Main Menu/happy_adveture.mp3") as AudioStreamMP3
	track.loop = true
	default_track = track
	music.stream = track
	music.volume_db = music_volume_db
	music.play()
	for frequency in [660.0, 990.0, 330.0]:
		tones.append(_tone(frequency))
	_start_ui_voices()
	apply_volumes()
func apply_volumes() -> void:
	for bus in ["Master", "Music", "SFX"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(float(SaveService.values[bus])))
func play_music(stream: AudioStream, volume_db := -10.0) -> void:
	if stream == null or (music.stream == stream and music.playing):
		return
	_stop_duck()
	music.stream = stream
	music_volume_db = volume_db
	music.volume_db = volume_db
	music.pitch_scale = 1.0
	music.play()
func play_default_music() -> void:
	play_music(default_track, -10.0)
func set_music_pitch(scale: float) -> void:
	music.pitch_scale = maxf(0.01, scale)
func duck_music(db: float, seconds: float) -> void:
	_stop_duck()
	if seconds <= 0.0:
		return
	var fall := minf(0.08, seconds * 0.5)
	duck = create_tween()
	# Ducking has to survive a paused tree, so it never processes with the scene.
	duck.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	duck.tween_property(music, "volume_db", music_volume_db - absf(db), fall)
	duck.tween_property(music, "volume_db", music_volume_db, seconds - fall)
	duck.finished.connect(func() -> void: duck = null)
func _stop_duck() -> void:
	if duck:
		duck.kill()
		duck = null
	music.volume_db = music_volume_db
## One polyphonic stream for every UI blip: overlapping blips (hover, confirm, route change, pickups)
## layer instead of each one cutting off the last and rebuilding playback.
func _start_ui_voices() -> void:
	var voices := AudioStreamPolyphonic.new()
	voices.polyphony = 6
	sfx.stream = voices
	sfx.volume_db = -19
	sfx.play()
func play_ui(kind: int = 0) -> void:
	if sfx.stream == null:
		return
	if not sfx.playing:
		sfx.play()
	var voices := sfx.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if voices:
		voices.play_stream(tones[kind])
func _tone(frequency: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	var count := 2205
	data.resize(count * 2)
	for i in count:
		var envelope := sin(PI * float(i) / count) * (1.0 - float(i) / count)
		data.encode_s16(i * 2, int(sin(TAU * frequency * i / 22050.0) * envelope * 14000))
	stream.data = data
	return stream

func shutdown() -> void:
	_stop_duck()
	music.stop()
	sfx.stop()
	music.stream = null
	sfx.stream = null

## The autoload only leaves the tree when the app exits, after the current scene has left it.
## A voice the mixer still holds when the engine shuts down is reported as leaked ("ObjectDB
## instances were leaked", "resources still in use"), and a stopped voice is let go only by the
## next mix. So, whichever way the app quit, stop every player (the scene's and ours) and let the
## mixer run twice: the first mix to start after the stops has then finished.
func _exit_tree() -> void:
	_stop_players(get_parent())
	shutdown()
	var stopped := Time.get_ticks_usec()
	var deadline := stopped+RELEASE_MSEC*1000
	var mixes := 0
	var last_mix := stopped
	while mixes < 2 and Time.get_ticks_usec() < deadline:
		OS.delay_usec(500)
		var mixed := Time.get_ticks_usec()-int(AudioServer.get_time_since_last_mix()*1000000.0)
		# A new mix starts at least a buffer (several ms) after the last; 1 ms absorbs rounding.
		if mixed > last_mix+1000:
			mixes += 1
			last_mix = mixed

static func _stop_players(top: Node) -> void:
	for node in top.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			node.stop()
