extends SceneTree
## The hub plays the calm 8-bit loop from tools/build_hub_chiptune.py at AudioService.HUB_MUSIC_DB,
## in normal and booth mode alike, without changing the shared imported stream. Run headless with
## --script res://tests/theme_music.gd.
const TITLE_PATH := "res://Assets/Audio/Main Menu/hub_chiptune_loop.wav"
## 32 bars at 84 BPM, as recorded in Assets/Audio/Main Menu/PROMPTS.md.
const LOOP_SECONDS := 32 * 4 * 60.0 / 84.0
## Quiet enough to sit under conversation: peak and RMS of the decoded loop, before bus volumes.
const MAX_PEAK := 0.55
const RMS_RANGE := Vector2(0.04, 0.2)
## A click at the loop point would step many times the music's typical step around it.
const SEAM_STEP_RATIO := 4.0
var failures := 0

## Defers the run until the autoloads are in the tree.
func _initialize() -> void:
	call_deferred("run")

## Prints a PASS or FAIL line for one expectation and counts failures.
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

## Checks the hub loop, its volume and booth behaviour, then quits with the result.
func run() -> void:
	var audio: Node = root.get_node("AudioService")
	var router: Node = root.get_node("AppRouter")
	await create_timer(0.2, true).timeout

	var title := audio.TITLE_THEME as AudioStreamWAV
	check(title != null and title.resource_path == TITLE_PATH, "The hub theme is the chiptune loop")
	check(title.loop_mode == AudioStreamWAV.LOOP_FORWARD and title.loop_begin == 0,
		"The loop's .import loops it forward from the start")
	check(absf(title.get_length() - LOOP_SECONDS) < 0.01,
		"The loop is 32 bars at 84 BPM (%.3f s)" % title.get_length())
	check(not "ATTRACT_THEME" in audio, "There is no separate booth attract track")
	check(audio.default_track == title and audio.music.stream == title and audio.music.playing,
		"The hub starts on the chiptune loop")
	check(is_equal_approx(audio.music.volume_db, audio.HUB_MUSIC_DB) and audio.HUB_MUSIC_DB < -10.0,
		"The hub plays it at HUB_MUSIC_DB, below the games' -10 dB (%.1f dB)" % audio.music.volume_db)
	await check_mix(title)

	router.set_booth(true)
	check(audio.default_track == title and audio.music.stream == title and audio.music.playing,
		"Booth mode keeps the same hub loop playing")
	check(title.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Booth mode leaves the shared stream unchanged")
	router.set_booth(false)
	check(audio.default_track == title and audio.music.stream == title and audio.music.playing,
		"Leaving booth mode keeps the hub loop playing")

	var other := AudioStreamWAV.new()
	audio.play_music(other)
	router.set_booth(true)
	check(audio.music.stream == other and audio.default_track == title,
		"Booth mode leaves a playing non-default stream alone")
	router.set_booth(false)
	audio.music.stop()
	audio.play_default_music()
	check(audio.music.stream == title and audio.music.playing
			and is_equal_approx(audio.music.volume_db, audio.HUB_MUSIC_DB),
		"Returning to the hub restarts the loop at HUB_MUSIC_DB")

	print("THEME MUSIC: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	await audio.settle()
	quit(1 if failures else 0)

## Mixes the loop offline, faster than real time, through one full pass and two seconds past the
## seam: it stays quiet and keeps playing after the seam. The wrap itself (the frames either side of
## the loop point) must step no more than SEAM_STEP_RATIO times the typical step around it, so a
## click can't hide behind a louder note attack elsewhere in the loop.
func check_mix(title: AudioStreamWAV) -> void:
	var playback := title.instantiate_playback()
	playback.start(0.0)
	var rate := AudioServer.get_mix_rate()
	var length := title.get_length()
	var chunk := int(rate * 0.5)
	var mixed := 0
	var peak := 0.0
	var squares := 0.0
	var counted := 0
	var wrap_step := 0.0
	var nearby_steps := 0.0
	var nearby_count := 0
	var after_seam := 0.0
	var last := 0.0
	var seam := int(length * rate)
	var window := int(rate * 0.02)
	while mixed < int((length + 2.0) * rate):
		var frames: PackedVector2Array = playback.mix_audio(1.0, chunk)
		for frame in frames:
			var value := frame.x
			var step := absf(value - last)
			last = value
			if mixed < seam:
				peak = maxf(peak, absf(value))
				squares += value * value
				counted += 1
			# Resampling can land the wrap a frame either side of the computed seam.
			if absi(mixed - seam) <= 1:
				wrap_step = maxf(wrap_step, step)
			elif absi(mixed - seam) < window:
				nearby_steps += step
				nearby_count += 1
			if mixed > seam + window:
				after_seam = maxf(after_seam, absf(value))
			mixed += 1
		if frames.size() < chunk:
			break
	var rms := sqrt(squares / maxi(1, counted))
	check(peak > 0.1 and peak <= MAX_PEAK, "The loop peaks at %.3f, at most %.2f" % [peak, MAX_PEAK])
	check(rms >= RMS_RANGE.x and rms <= RMS_RANGE.y,
		"The loop's RMS %.3f sits in the quiet range %.2f-%.2f" % [rms, RMS_RANGE.x, RMS_RANGE.y])
	check(after_seam > 0.05 and playback.is_playing(), "The loop keeps playing past its seam")
	var typical := nearby_steps / maxi(1, nearby_count)
	check(nearby_count > 0 and wrap_step <= SEAM_STEP_RATIO * typical,
		"The wrap steps %.4f, within %.0fx the %.4f mean step in the 20 ms around it"
			% [wrap_step, SEAM_STEP_RATIO, typical])
	playback.stop()
	await process_frame
