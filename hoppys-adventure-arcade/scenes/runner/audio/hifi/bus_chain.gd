extends RefCounted
## Shared lease survives overlapping runner scenes and restores the original send.
static var leases := 0
static var original_send: StringName
static var room_name: StringName
static var whoosh_name: StringName

static func acquire() -> StringName:
	if leases > 0:
		leases += 1
		return whoosh_name
	var sfx := AudioServer.get_bus_index(&"SFX")
	if sfx < 0: return &"Master"
	original_send = AudioServer.get_bus_send(sfx)
	# Insert before SFX: Godot bus sends flow towards lower indices.
	AudioServer.add_bus(sfx)
	AudioServer.set_bus_name(sfx, &"RunnerSFX")
	room_name = AudioServer.get_bus_name(sfx)
	AudioServer.set_bus_send(sfx, original_send)
	var room := AudioEffectReverb.new()
	room.room_size = 0.24
	room.damping = 0.72
	room.wet = 0.10
	room.dry = 1.0
	AudioServer.add_bus_effect(sfx, room)
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -10.0
	compressor.ratio = 2.2
	compressor.attack_us = 6000.0
	compressor.release_ms = 100.0
	compressor.gain = 0.0
	AudioServer.add_bus_effect(sfx, compressor)
	AudioServer.set_bus_send(AudioServer.get_bus_index(&"SFX"), room_name)
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, &"RunnerWhoosh")
	whoosh_name = AudioServer.get_bus_name(index)
	AudioServer.set_bus_send(index, &"SFX")
	var delay := AudioEffectDelay.new()
	delay.set_tap1_delay_ms(74.0)
	delay.set_tap1_level_db(-19.0)
	delay.set_tap1_pan(-0.8)
	delay.set_tap2_delay_ms(148.0)
	delay.set_tap2_level_db(-24.0)
	delay.set_tap2_pan(0.8)
	delay.set_feedback_active(false)
	AudioServer.add_bus_effect(index, delay)
	leases = 1
	return whoosh_name

static func release() -> void:
	if leases == 0: return
	leases -= 1
	if leases > 0: return
	var sfx := AudioServer.get_bus_index(&"SFX")
	if sfx >= 0 and AudioServer.get_bus_send(sfx) == room_name:
		AudioServer.set_bus_send(sfx, original_send)
	for bus in [whoosh_name, room_name]:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0: AudioServer.remove_bus(index)
