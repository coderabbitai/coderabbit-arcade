extends SceneTree
## Finishing any platformer level plays the stage-clear stinger once over the MERGE SUCCESSFUL
## results: it keeps playing while the results pause the tree, the paused level music stays
## silent under it, and a knockout never plays it. Run headless with
## --script res://tests/platformer_stage_clear.gd.
const LEVELS := ["bay_area_blitz", "enchanted_repo", "orbital_ops"]
const STINGER := "res://Assets/Audio/Platformer/stinger_stage_clear.ogg"
var failures := 0
var game: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func open_level(route: String) -> void:
	change_scene_to_file("res://scenes/platformer/" + route + ".tscn")
	await process_frame
	await process_frame
	game = current_scene
	game._resume()
	await create_timer(0.2).timeout

func run() -> void:
	var stream := load(STINGER) as AudioStreamOggVorbis
	check(stream != null and not stream.loop and stream.get_length() > 2.0 and stream.get_length() < 6.0,
		"The stage-clear stinger is a short one-shot")
	if stream == null:
		await finish()
		return
	for route in LEVELS:
		await open_level(route)
		check(game.stage_clear.stream == stream and not game.stage_clear.playing, route + ": the stinger waits for the finish")
		game._finish(true)
		# _finish(true) starts the stinger synchronously, so this window counts from "stopped".
		var early := await watch(game.stage_clear, 0.5, true)
		check(paused and game.stage_clear.playing and game.stage_clear.bus == &"Music",
			route + ": MERGE SUCCESSFUL plays the stinger on the Music bus while the results pause the tree")
		check(game.music.process_mode != Node.PROCESS_MODE_ALWAYS and game.music.can_process() == false,
			route + ": the level music stays paused under the stinger")
		var rest := await watch(game.stage_clear, stream.get_length())
		check(early.starts + rest.starts == 1 and not game.stage_clear.playing,
			route + ": the stage-clear stinger starts once and stops after one playback (%d starts)" % (early.starts + rest.starts))
		var leave := game.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Return to Platformer Menu")
		check(not leave.is_empty(), route + ": the results offer a way out")
		if not leave.is_empty():
			game.stage_clear.play()
			(leave[0] as Button).pressed.emit()
			check(not game.stage_clear.playing, route + ": leaving the results stops the stinger before the level music resumes")
			await create_timer(0.6, true, false, true).timeout
		paused = false
		await open_level(route)
		game.player.position.y = 900
		game.player._physics_process(0.0)
		check(game.finished and not game.won_run, route + ": the fall enters knockout handling")
		# The knockout cutaway runs for 3.5 s before the shared results open; watch every frame of both.
		var knockout := await watch(game.stage_clear, 3.6)
		check(not knockout.ever_playing and not game.stage_clear.playing,
			route + ": a knockout and its results never play the stage-clear stinger")
		paused = false
	await finish()

## Samples the player every frame, paused or not: how many times playback started (from stopped,
## or by jumping back to the start) and whether it played at all.
func watch(player: AudioStreamPlayer, seconds: float, from_stopped := false) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var was_playing := player.playing and not from_stopped
	var last_position := player.get_playback_position() if was_playing else 0.0
	var result := {"starts": 0, "ever_playing": player.playing}
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var playing := player.playing
		var position := player.get_playback_position() if playing else 0.0
		if playing and (not was_playing or position + 0.05 < last_position):
			result.starts += 1
		result.ever_playing = result.ever_playing or playing
		was_playing = playing
		last_position = position
	return result

func finish() -> void:
	print("PLATFORMER STAGE CLEAR: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	paused = false
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await process_frame
	await root.get_node("AudioService").settle()
	quit(1 if failures else 0)
