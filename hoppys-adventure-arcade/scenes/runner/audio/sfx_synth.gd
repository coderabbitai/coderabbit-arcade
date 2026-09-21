extends RefCounted
## Original deterministic PCM recipes. No resources or gameplay RNG are consumed.
const RATE := 22050
# seconds, start Hz, end Hz, waveform, gain
const RECIPES := {
	&"turn_warning": [3.0, 700.0, 1400.0, "warning", 0.6],
	&"boss_intro": [3.0, 35.0, 150.0, "intro", 0.7],
	&"turn_whoosh": [2.4, 300.0, 2400.0, "turn", 0.6],
	&"stage_clear": [1.0, 440.0, 880.0, "arpeggio", 0.65],
	&"telegraph_tick": [0.06, 1600.0, 1600.0, "square", 0.35],
	&"projectile_whoosh": [0.30, 900.0, 180.0, "noise", 0.45],
	&"tool_pickup": [0.22, 880.0, 1760.0, "sine", 0.55],
	&"tool_fire": [0.18, 2400.0, 600.0, "saw", 0.5],
	&"boss_hit": [0.20, 300.0, 90.0, "fm", 0.6],
	&"boss_phase": [0.80, 220.0, 440.0, "detuned", 0.6],
	&"boss_defeat": [1.30, 330.0, 1320.0, "burst", 0.7],
	&"alert_sting": [0.55, 180.0, 180.0, "alert", 0.65],
	&"radar_pulse": [0.5, 1200.0, 900.0, "radar", 0.55],
	&"footstep": [0.07, 140.0, 65.0, "noise", 0.35],
	&"jump": [0.22, 240.0, 880.0, "square", 0.48],
	&"land": [0.13, 180.0, 45.0, "noise", 0.55],
	&"roll": [0.28, 320.0, 80.0, "noise", 0.40],
	&"lane_left": [0.12, 700.0, 280.0, "saw", 0.35],
	&"lane_right": [0.12, 280.0, 700.0, "saw", 0.35],
	&"powerup": [0.24, 660.0, 1320.0, "sine", 0.55],
	&"nitro": [0.65, 110.0, 880.0, "saw", 0.55],
	&"lgtm": [0.65, 523.25, 1046.5, "chord", 0.65],
	&"auto_fix": [0.38, 1320.0, 330.0, "square", 0.50],
	&"shield_block": [0.30, 980.0, 490.0, "chord", 0.60],
	&"hit": [0.30, 220.0, 40.0, "noise", 0.75],
	&"pursuit_start": [0.75, 440.0, 220.0, "square", 0.60],
	&"pursuit_drone": [2.0, 55.0, 55.0, "drone", 0.45],
	&"heartbeat": [1.0, 65.0, 65.0, "heartbeat", 0.65],
	&"retreat": [0.50, 440.0, 110.0, "saw", 0.45],
	&"recovered_chime": [0.70, 659.25, 1318.5, "chord", 0.60],
	&"caught": [0.85, 120.0, 25.0, "noise", 0.78],
	&"game_over": [1.20, 440.0, 110.0, "chord", 0.65],
}
static var _cache: Dictionary = {}

static func sound(kind: StringName) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	if not RECIPES.has(kind):
		return null
	var recipe: Array = RECIPES[kind]
	var seconds := float(recipe[0])
	var count := int(seconds * RATE)
	var stereo := kind == &"lane_left" or kind == &"lane_right"
	var looping := kind == &"pursuit_drone" or kind == &"heartbeat" or kind == &"radar_pulse"
	var channels := 2 if stereo else 1
	var data := PackedByteArray()
	data.resize(count * channels * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4705 + String(kind).hash()
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var progress := float(i) / count
		var frequency := lerpf(float(recipe[1]), float(recipe[2]), progress)
		var envelope := minf(t / 0.008, 1.0) * pow(1.0 - progress, 1.6)
		var sample := sin(phase)
		match String(recipe[3]):
			"warning":
				frequency = 700.0 * pow(1.3, floor(t))
				var beat := fposmod(t, 1.0)
				envelope = sin(PI * beat / 0.12) if beat < 0.12 else 0.0
			"intro":
				sample = (sin(phase) + sin(phase * 1.012)) * 0.5
				envelope = smoothstep(0.0, 0.7, progress) * (1.0 - smoothstep(0.8, 1.0, progress))
				if progress >= 0.8:
					var impact := exp(-(progress - 0.8) * 35.0)
					sample = sample * 0.4 + rng.randf_range(-1.0, 1.0) * 0.6
					envelope = impact
			"turn":
				frequency = lerpf(300.0, 2400.0, sin(progress * PI))
				sample = sample * 0.4 + rng.randf_range(-1, 1) * 0.6
				envelope = sin(progress * PI)
				# Snap at the camera hold boundary, inside the same voice.
				if progress >= 0.3 and progress < 0.34:
					sample = rng.randf_range(-1.0, 1.0)
					envelope = 1.0 - (progress - 0.3) / 0.04
			"arpeggio":
				frequency = 440.0 * float([1.0, 1.25, 1.5, 2.0][mini(3, int(progress * 4))])
			"alert":
				sample = 1.0 if sin(phase) >= 0 else -1.0
				var gate := fposmod(t, 1.0 / 9.0)
				envelope = sin(PI * gate / 0.055) if t < 3.0 / 9.0 and gate < 0.055 else 0.0
			"radar":
				frequency = lerpf(1200.0, 900.0, minf(t / 0.04, 1.0))
				envelope = sin(PI * t / 0.04) if t < 0.04 else 0.0
			"square": sample = 0.65 * (1.0 if sin(phase) >= 0 else -1.0) + 0.35 * sample
			"saw": sample = 0.65 * (2.0 * fposmod(phase / TAU, 1.0) - 1.0) + 0.35 * sample
			"noise": sample = sample * 0.55 + rng.randf_range(-1.0, 1.0) * 0.45
			"fm": sample = sin(phase + 2.5 * sin(phase * 1.7))
			"detuned": sample = (sin(phase) + sin(phase * 1.006) + sin(phase * 1.5)) / 3.0
			"burst": sample = rng.randf_range(-1, 1) if t < 0.18 else (sin(phase) + sin(phase * 1.25) + sin(phase * 1.5)) / 3.0
			"chord": sample = (sample + sin(phase * 1.25) + sin(phase * 1.5)) / 3.0
			"drone":
				# Integral cycles over two seconds, including the amplitude modulation.
				sample = (sin(TAU * 55.0 * t) + sin(TAU * 57.0 * t)) * 0.5
				envelope = 0.7 + 0.3 * cos(TAU * t)
			"heartbeat":
				var beat := fposmod(t, 0.5)
				envelope = sin(PI * beat / 0.16) * exp(-beat * 18.0) if beat < 0.16 else 0.0
				sample = sin(TAU * 65.0 * beat)
		phase += TAU * frequency / RATE
		var value := clampf(sample * envelope * float(recipe[4]), -0.8, 0.8)
		for channel in channels:
			var pan := 1.0
			if stereo:
				pan = 1.0 if (channel == 0) == (kind == &"lane_left") else 0.2
			data.encode_s16((i * channels + channel) * 2, int(value * pan * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = stereo
	stream.data = data
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	_cache[kind] = stream
	return stream

static func panned_whoosh(lane_mask: int, kind: StringName = &"projectile_whoosh") -> AudioStreamWAV:
	var key := StringName("%s_pan_%d" % [kind, lane_mask & 7])
	if _cache.has(key): return _cache[key]
	var source := sound(kind)
	var mono := source.data
	var data := PackedByteArray()
	data.resize(mono.size() * 2)
	var total := 0.0
	var lanes := 0
	for lane in 3:
		if lane_mask & (1 << lane):
			total += lane - 1
			lanes += 1
	var pan := total / maxi(lanes, 1)
	for i in mono.size() / 2:
		var value := mono.decode_s16(i * 2)
		data.encode_s16(i * 4, int(value * (1 - maxf(pan, 0) * 0.8)))
		data.encode_s16(i * 4 + 2, int(value * (1 + minf(pan, 0) * 0.8)))
	var stream := source.duplicate() as AudioStreamWAV
	stream.stereo = true
	stream.data = data
	_cache[key] = stream
	return stream
