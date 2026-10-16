extends SceneTree
## The hub plays the instrumental "Send in the Rabbit" title loop, and booth mode switches it to
## the attract playlist (vocal theme, then the title loop) and back, without changing the shared
## imported streams. Run headless with --script res://tests/theme_music.gd.
const TITLE_PATH := "res://Assets/Audio/Main Menu/send_in_the_rabbit_title_loop.ogg"
const VOCAL_PATH := "res://Assets/Audio/Main Menu/send_in_the_rabbit.ogg"
## Verse 2's downbeat in the title loop, as recorded in Assets/Audio/Main Menu/PROMPTS.md.
const TITLE_LOOP_START := 54.021224
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func run() -> void:
	var audio: Node = root.get_node("AudioService")
	var router: Node = root.get_node("AppRouter")
	await create_timer(0.2, true).timeout

	var title := audio.TITLE_THEME as AudioStreamOggVorbis
	check(title != null and title.resource_path == TITLE_PATH, "The title theme is the instrumental loop")
	check(title.loop and absf(title.loop_offset - TITLE_LOOP_START) < 0.001,
		"The title loop's .import loops it after its intro, from verse 2 at %.3f s" % TITLE_LOOP_START)
	check(is_equal_approx(title.bpm, 118.338) and title.bar_beats == 4 and title.beat_count == 0,
		"The title loop carries its tempo and bar for bar-synced switching, and loops at the file end")
	check(audio.default_track == title and audio.music.stream == title and audio.music.playing,
		"The hub starts on the title loop")

	var attract := audio.ATTRACT_THEME as AudioStreamPlaylist
	check(attract != null and attract.stream_count == 2 and attract.loop and not attract.shuffle,
		"The attract playlist holds two streams and repeats in order")
	var vocal := attract.get_list_stream(0) as AudioStreamOggVorbis
	check(vocal != null and vocal.resource_path == VOCAL_PATH and not vocal.loop,
		"The attract playlist opens with the vocal theme, played through once")
	check(attract.get_list_stream(1) == title, "The attract playlist follows the vocal theme with the title loop")
	await check_playlist_order(attract, vocal.get_length(), title.get_length())

	router.set_booth(true)
	check(audio.default_track == attract and audio.music.stream == attract and audio.music.playing,
		"Booth mode switches the playing hub music to the attract playlist")
	check(title.loop and not vocal.loop, "Switching leaves the shared imported streams unchanged")
	router.set_booth(false)
	check(audio.default_track == title and audio.music.stream == title and audio.music.playing,
		"Leaving booth mode returns the hub to the title loop")

	audio.play_music(vocal)
	router.set_booth(true)
	check(audio.music.stream == vocal and audio.music.playing and audio.default_track == attract,
		"Booth mode leaves a playing non-default stream alone and only changes the default")
	router.set_booth(false)
	check(audio.music.stream == vocal and audio.default_track == title,
		"Leaving booth mode also leaves a playing non-default stream alone")

	audio.music.stop()
	router.set_booth(true)
	check(audio.default_track == attract and not audio.music.playing,
		"Booth mode only changes the default when hub music is not playing")
	audio.play_default_music()
	check(audio.music.stream == attract and audio.music.playing, "The hub then starts the attract playlist")
	router.set_booth(false)

	print("THEME MUSIC: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	await audio.settle()
	quit(1 if failures else 0)

## Mixes the playlist offline, faster than real time: the vocal theme plays through, the title
## loop follows and plays its full length, then the playlist wraps to the vocal theme.
func check_playlist_order(attract: AudioStreamPlaylist, vocal_len: float, title_len: float) -> void:
	var playback := attract.instantiate_playback()
	playback.start(0.0)
	var rate := AudioServer.get_mix_rate()
	var chunk := int(rate * 0.5)
	var mixed := 0.0
	var title_peak := 0.0
	var wrapped_at := -1.0
	while mixed < vocal_len + title_len + 2.0:
		var frames: PackedVector2Array = playback.mix_audio(1.0, chunk)
		mixed += float(frames.size()) / rate
		if mixed > vocal_len + 1.0 and mixed < vocal_len + title_len - 1.0:
			for frame in frames:
				title_peak = maxf(title_peak, absf(frame.x))
		if wrapped_at < 0.0 and playback.get_loop_count() == 1:
			wrapped_at = mixed
		if frames.size() < chunk:
			break
	check(title_peak > 0.05, "After the vocal theme the playlist plays the title loop")
	check(absf(wrapped_at - (vocal_len + title_len)) < 0.6,
		"The playlist wraps back to the vocal theme after the title loop's full length (at %.1f s)" % wrapped_at)
	check(playback.is_playing(), "The attract playlist keeps going after it wraps")
	playback.stop()
	await process_frame
