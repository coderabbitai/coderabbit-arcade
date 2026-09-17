extends Node
var music := AudioStreamPlayer.new()
var sfx := AudioStreamPlayer.new()
var tones: Array[AudioStreamWAV] = []
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
	var track := load("res://Assets/Audio/happy_adveture.mp3") as AudioStreamMP3
	track.loop = true
	music.stream = track
	music.volume_db = -10
	music.play()
	for frequency in [660.0, 990.0, 330.0]:
		tones.append(_tone(frequency))
	apply_volumes()
func apply_volumes() -> void:
	for bus in ["Master", "Music", "SFX"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(float(SaveService.values[bus])))
func play_ui(kind: int = 0) -> void:
	sfx.stream = tones[kind]
	sfx.volume_db = -19
	sfx.play()
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
	music.stop()
	sfx.stop()
	music.stream = null
	sfx.stream = null

func _exit_tree() -> void:
	shutdown()
