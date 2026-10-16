extends SceneTree
## The hub plays the instrumental "Send in the Rabbit" title loop, and booth mode switches it to
## the attract playlist (vocal theme, then the title loop) and back, without changing the shared
## imported streams. Run headless with --script res://tests/theme_music.gd.
const TITLE_PATH := "res://Assets/Audio/Main Menu/send_in_the_rabbit_title_loop.ogg"
const VOCAL_PATH := "res://Assets/Audio/Main Menu/send_in_the_rabbit.ogg"
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
	check(title.loop and title.loop_offset > 0.0 and title.loop_offset < title.get_length(),
		"The title loop's .import loops it after its intro")
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

	router.set_booth(true)
	check(audio.default_track == attract and audio.music.stream == attract and audio.music.playing,
		"Booth mode switches the playing hub music to the attract playlist")
	check(title.loop and not vocal.loop, "Switching leaves the shared imported streams unchanged")
	router.set_booth(false)
	check(audio.default_track == title and audio.music.stream == title and audio.music.playing,
		"Leaving booth mode returns the hub to the title loop")

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
