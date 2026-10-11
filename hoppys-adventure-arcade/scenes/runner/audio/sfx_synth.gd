extends RefCounted
## Original deterministic PCM recipes. No resources or gameplay RNG are consumed.
const RATE := 22050
# seconds, start Hz, end Hz, waveform, gain
const RECIPES := {
	&"boss_intro": [1.6, 35.0, 150.0, "intro", 0.7],
	&"boss_intro_short": [0.6, 55.0, 180.0, "detuned", 0.65],
	&"boss_title": [0.28, 160.0, 35.0, "fm", 0.72],
	&"boss_explosion": [0.30, 120.0, 25.0, "noise", 0.72],
	&"boss_resolved": [1.15, 440.0, 880.0, "arpeggio", 0.68],
	&"boss_skip": [0.25, 1800.0, 180.0, "noise", 0.5],
	# Contract 2.7 §11.15 run intro: the fly-through, the title sting, the countdown tick and GO.
	&"intro_whoosh": [2.2, 220.0, 1800.0, "sweep", 0.5],
	&"intro_title": [0.9, 110.0, 220.0, "detuned", 0.6],
	&"intro_count": [0.14, 880.0, 880.0, "square", 0.42],
	&"intro_go": [0.7, 659.25, 1318.5, "chord", 0.62],
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
const PERCUSSIVE := {&"intro_count": true, &"boss_title": true, &"boss_explosion": true,&"tool_fire": true, &"hit": true, &"land": true, &"caught": true, &"boss_hit": true, &"roll": true, &"footstep": true, &"telegraph_tick": true, &"lane_left": true, &"lane_right": true}
const ARPEGGIO := [1.0, 1.25, 1.5, 2.0]
# Authored carrier, detuned body, FM transient, filtered noise, sub.
const LAYERS := {
	&"percussive": [0.40, 0.16, 0.18, 0.12, 0.28],
	&"jump": [0.64, 0.26, 0.08, 0.0, 0.0],
	&"pursuit": [0.42, 0.22, 0.08, 0.04, 0.24],
	&"chime": [0.72, 0.22, 0.04, 0.0, 0.0],
	&"whoosh": [0.30, 0.12, 0.05, 0.38, 0.08],
	&"drone": [0.50, 0.28, 0.0, 0.0, 0.22],
	&"alarm": [0.42, 0.22, 0.08, 0.04, 0.24],
}
const FOOTSTEP_SOFTNESS := [0.85, 0.38, 0.16]
static var _cache: Dictionary = {}
static var raw_peaks: Dictionary = {}

static func family_for(kind: StringName) -> StringName:
	if kind == &"jump": return &"jump"
	if kind == &"pursuit_start": return &"pursuit"
	if PERCUSSIVE.has(kind): return &"percussive"
	var waveform := String(RECIPES[kind][3])
	if waveform in ["sine", "chord", "arpeggio"]: return &"chime"
	if kind == &"pursuit_drone": return &"drone"
	if kind in [&"projectile_whoosh", &"nitro", &"retreat", &"boss_skip", &"intro_whoosh"]: return &"whoosh"
	return &"alarm"


static func sound(kind: StringName) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	if not RECIPES.has(kind):
		return null
	return install(kind, render(kind))

## Pure PCM synthesis: reads only constants and allocates no resources, so prewarm can run it on
## WorkerThreadPool. install() turns the result into the cached stream on the main thread. Keep
## every operand typed here and in the helpers it calls (see `weights`).
static func render(kind: StringName) -> Dictionary:
	var recipe: Array = RECIPES[kind]
	var seconds := float(recipe[0])
	var count := int(seconds * RATE)
	var stereo := kind not in [&"pursuit_drone", &"heartbeat", &"radar_pulse"]
	var looping := kind == &"pursuit_drone" or kind == &"heartbeat" or kind == &"radar_pulse"
	var channels := 2 if stereo else 1
	var data := PackedByteArray()
	data.resize(count * channels * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4705 + String(kind).hash()
	var phase := 0.0
	var low_noise := 0.0
	var samples := PackedFloat64Array()
	samples.resize(count * channels)
	var waveform := String(recipe[3])
	var family := family_for(kind)
	# Typed, so the mixing line below compiles to validated float operators. Prewarm runs every
	# recipe here at once on workers. An untyped `a * b` caches its evaluator in the shared bytecode
	# on first run, without synchronisation, and threads arriving together could call a null one
	# (tests/runner_synth_threads.gd).
	var weights := PackedFloat64Array(LAYERS[family])
	var directional := kind == &"lane_left" or kind == &"lane_right"
	var left_pan := kind == &"lane_left"
	var intro := kind == &"boss_intro"
	var alert := kind == &"alert_sting"
	var impact := kind == &"boss_hit" or kind == &"caught"
	var percussive := family == &"percussive"
	var width := float(String(kind).hash() % 7 + 2) * 0.035
	for i in count:
		var t := float(i) / RATE
		var progress := float(i) / count
		var frequency := lerpf(float(recipe[1]), float(recipe[2]), progress)
		var envelope := _envelope(family, t, seconds)
		var sample := sin(phase)
		match waveform:
			"intro":
				sample = (sin(phase) + sin(phase * 1.012)) * 0.5
				envelope = smoothstep(0.0, 0.7, progress) * (1.0 - smoothstep(0.8, 1.0, progress))
				if progress >= 0.8:
					var impact_envelope := exp(-(progress - 0.8) * 35.0)
					sample = sample * 0.4 + rng.randf_range(-1.0, 1.0) * 0.6
					envelope = impact_envelope
			"sweep":
				# Rises to the top and falls back, under a noise bed: the camera flying down the corridor.
				frequency = lerpf(float(recipe[1]), float(recipe[2]), sin(progress * PI))
				sample = sample * 0.4 + rng.randf_range(-1, 1) * 0.6
				envelope = sin(progress * PI)
			"arpeggio":
				frequency = 440.0 * float(ARPEGGIO[mini(3, int(progress * 4))])
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
				sample = drone_sample(t)
				envelope = 0.7 + 0.3 * cos(TAU * t)
			"heartbeat":
				var beat := fposmod(t, 0.5)
				envelope = sin(PI * beat / 0.16) * exp(-beat * 18.0) if beat < 0.16 else 0.0
				sample = sin(TAU * 65.0 * beat)
		# Band-limited harmonic body, detuned air, FM transient and swept noise.
		var cutoff := lerpf(6200.0, 350.0, progress)
		low_noise += (rng.randf_range(-1.0, 1.0) - low_noise) * (1.0 - exp(-TAU * cutoff / RATE))
		var body := sin(phase) * 0.56 + sin(phase * 1.003) * 0.24
		var transient := sin(phase + sin(phase * 2.01) * 2.0 * exp(-t * 35.0)) * exp(-t * 28.0)
		var sub := impact_sub(t, seconds) if impact else sting_sub(t, seconds, intro) if intro or alert else sin(phase * 0.5) * exp(-t * 9.0)
		var click := click_transient(t) * 0.16 if percussive else 0.0
		if looping and kind != &"pursuit_drone":
			sample = sample * 0.78 + sin(phase * 2.0 + 0.3 * sin(phase * 3.0)) * 0.16
		if not looping:
			sample = sample * weights[0] + body * weights[1] + transient * weights[2] + low_noise * weights[3] + sub * weights[4]
		# Keep authored radar gaps and heartbeat handover precise.
		var edge := 1.0 if looping else minf(t / 0.002, 1.0) * minf((seconds - t - 1.0 / RATE) / 0.006, 1.0)
		for channel in channels:
			var side := sin(phase * 1.007) * width * (1.0 if channel == 0 else -1.0) if stereo else 0.0
			var pan := 1.0
			if directional:
				pan = 1.0 if (channel == 0) == left_pan else 0.2
			samples[i * channels + channel] = ((sample + side) * envelope + click) * float(recipe[4]) * maxf(edge, 0.0) * pan
		phase += TAU * frequency / RATE
	var raw_peak := 0.0
	for value in samples: raw_peak = maxf(raw_peak, absf(value))
	# Remove DC with a zero-ended correction window, then normalize only if needed.
	var window := PackedFloat64Array()
	window.resize(count)
	var window_sum := 0.0
	for i in count:
		window[i] = sin(PI * float(i) / (count - 1))
		window_sum += window[i]
	for channel in channels:
		var sum := 0.0
		for i in count:
			sum += samples[i * channels + channel]
		for i in count:
			samples[i * channels + channel] -= sum / window_sum * window[i]
	var peak := 0.0
	for value in samples: peak = maxf(peak, absf(value))
	var gain := minf(1.0, 0.79 / maxf(peak, 0.00001))
	for i in samples.size(): data.encode_s16(i * 2, int(samples[i] * gain * 32767.0))
	return {"data": data, "stereo": stereo, "looping": looping, "count": count, "raw_peak": raw_peak}

## Main thread only. An already cached stream wins, so a cue synthesised on demand before its
## worker result arrived keeps its identity.
static func install(kind: StringName, rendered: Dictionary) -> AudioStreamWAV:
	if _cache.has(kind): return _cache[kind]
	raw_peaks[kind] = rendered.raw_peak
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = rendered.stereo
	stream.data = rendered.data
	if rendered.looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = rendered.count
	_cache[kind] = stream
	return stream

static func panned_whoosh(lane_mask: int, kind: StringName = &"projectile_whoosh") -> AudioStreamWAV:
	var key := StringName("%s_pan_%d" % [kind, lane_mask & 7])
	if _cache.has(key): return _cache[key]
	var source := sound(kind)
	return install_panned(kind, lane_mask, panned_pcm(source.data, source.stereo, lane_mask))

static func install_panned(kind: StringName, lane_mask: int, data: PackedByteArray) -> AudioStreamWAV:
	var key := StringName("%s_pan_%d" % [kind, lane_mask & 7])
	if _cache.has(key): return _cache[key]
	var stream := sound(kind).duplicate() as AudioStreamWAV
	stream.stereo = true
	stream.data = data
	_cache[key] = stream
	return stream

## Pure, worker-safe: pans the source PCM toward the masked lanes.
static func panned_pcm(pcm: PackedByteArray, stereo: bool, lane_mask: int) -> PackedByteArray:
	var stride := 4 if stereo else 2
	var frames := pcm.size() / stride
	var data := PackedByteArray()
	data.resize(frames * 4)
	var total := 0.0
	var lanes := 0
	for lane in 3:
		if lane_mask & (1 << lane):
			total += lane - 1
			lanes += 1
	var pan := total / maxi(lanes, 1)
	for i in frames:
		var left := float(pcm.decode_s16(i * stride))
		var right := float(pcm.decode_s16(i * stride + 2)) if stereo else left
		data.encode_s16(i * 4, int(left * (1 - maxf(pan, 0) * 0.8)))
		data.encode_s16(i * 4 + 2, int(right * (1 + minf(pan, 0) * 0.8)))
	return data

static func _envelope(family: StringName, t: float, duration: float) -> float:
	if family == &"percussive":
		return smoothstep(0.0, 0.0015, t) * exp(-t / (duration * 0.16))
	if family == &"jump":
		return smoothstep(0.0, 0.003, t) * exp(-t / (duration * 0.25))
	if family == &"pursuit":
		var p := t / duration
		var strike := 0.55 * smoothstep(0.0, 0.012, t) * exp(-p * 12.0)
		var rise := 0.85 * smoothstep(0.10, 0.62, p) * (1.0 - smoothstep(0.65, 1.0, p))
		return strike + rise
	if family == &"chime":
		return smoothstep(0.0, 0.005, t) * exp(-t / (duration * 0.42)) * (1.0 - smoothstep(duration * 0.85, duration, t))
	if family == &"whoosh": return sin(PI * clampf(t / duration, 0.0, 1.0))
	return smoothstep(0.0, 0.008, t) * (1.0 - smoothstep(duration * 0.55, duration, t))

## Independent four-millisecond contact layer, outside the body envelope.
static func click_transient(t: float) -> float:
	if t < 0.0 or t >= 0.004: return 0.0
	return sin(TAU * 3200.0 * t) * sin(PI * t / 0.004)

## Falling 65 to 40 Hz thump; decay belongs to the duration-scaled body envelope.
static func impact_sub(t: float, duration: float) -> float:
	return sin(TAU * (65.0 * t - 12.5 * t * t / duration))

## Reset the sub transient at the impact or each alarm gate, not at recipe start.
static func sting_sub(t: float, duration: float, intro: bool) -> float:
	var age := maxf(0.0, t - duration * 0.8) if intro else fposmod(t, 1.0 / 9.0)
	return sin(TAU * 48.0 * age) * exp(-age * 9.0)

## Integral cycles for every layer, with no artificial seam fade.
static func drone_sample(t: float) -> float:
	var weights := PackedFloat64Array(LAYERS[&"drone"])
	return sin(TAU * 55.0 * t) * weights[0] + sin(TAU * 57.0 * t) * weights[1] + sin(TAU * 27.5 * t) * weights[4]

## Surface and strike variation are independent cache/seed axes.
static func footstep(surface: int, variant: int = 0) -> AudioStreamWAV:
	var material := clampi(surface, 0, 2)
	var strike := posmod(variant, 2)
	var key := StringName("footstep_surface_%d_variant_%d" % [material, strike])
	if _cache.has(key): return _cache[key]
	return install_footstep(material, strike, footstep_pcm(sound(&"footstep").data, material, strike))

static func install_footstep(material: int, strike: int, data: PackedByteArray) -> AudioStreamWAV:
	var key := StringName("footstep_surface_%d_variant_%d" % [material, strike])
	if _cache.has(key): return _cache[key]
	var stream := sound(&"footstep").duplicate() as AudioStreamWAV
	stream.set_meta(&"surface", material)
	stream.set_meta(&"variant", strike)
	stream.set_meta(&"seed", footstep_seed(material, strike))
	stream.set_meta(&"softness", FOOTSTEP_SOFTNESS[material])
	stream.data = data
	_cache[key] = stream
	return stream

static func footstep_seed(material: int, strike: int) -> int:
	return 8201 + material * 101 + strike * 7919

## Pure, worker-safe: the surface filter and strike gain over the base footstep PCM.
static func footstep_pcm(source: PackedByteArray, material: int, strike: int) -> PackedByteArray:
	var data := source.duplicate()
	var previous := PackedFloat64Array([0.0, 0.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = footstep_seed(material, strike)
	var strike_gain := rng.randf_range(0.88, 1.0)
	for i in data.size() / 2:
		var channel := i % 2
		previous[channel] = lerpf(previous[channel], data.decode_s16(i * 2) * strike_gain, FOOTSTEP_SOFTNESS[material])
		data.encode_s16(i * 2, int(previous[channel]))
	return data

## One worker task per recipe: the recipe plus every panned or footstep variant derived from it.
static func render_family(kind: StringName) -> Dictionary:
	var rendered := render(kind)
	var variants := {}
	if kind == &"projectile_whoosh":
		for mask in 8: variants[mask] = panned_pcm(rendered.data, rendered.stereo, mask)
	elif kind == &"footstep":
		for surface in 3:
			for strike in 2: variants[Vector2i(surface, strike)] = footstep_pcm(rendered.data, surface, strike)
	return {"base": rendered, "variants": variants}

## Main-thread finalizer for render_family(); returns every stream it installed.
static func install_family(kind: StringName, family: Dictionary) -> Array:
	var streams: Array = [install(kind, family.base)]
	for key: Variant in family.variants:
		if key is Vector2i: streams.append(install_footstep(key.x, key.y, family.variants[key]))
		else: streams.append(install_panned(kind, key, family.variants[key]))
	return streams

## Optional UI audition hook; uses the existing crisp tick recipe and voice pool.
static func ui_click() -> AudioStreamWAV:
	return sound(&"telegraph_tick")
