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
	for route in LEVELS:
		await open_level(route)
		check(game.stage_clear.stream == stream and not game.stage_clear.playing, route + ": the stinger waits for the finish")
		game._finish(true)
		await create_timer(0.5, true, false, true).timeout
		check(paused and game.stage_clear.playing and game.stage_clear.bus == &"Music",
			route + ": MERGE SUCCESSFUL plays the stinger on the Music bus while the results pause the tree")
		check(game.music.process_mode != Node.PROCESS_MODE_ALWAYS and game.music.can_process() == false,
			route + ": the level music stays paused under the stinger")
		var leave := game.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Return to Platformer Menu")
		check(not leave.is_empty(), route + ": the results offer a way out")
		if not leave.is_empty():
			(leave[0] as Button).pressed.emit()
			check(not game.stage_clear.playing, route + ": leaving the results stops the stinger before the level music resumes")
			await create_timer(0.6, true, false, true).timeout
		paused = false
		await open_level(route)
		game.player.position.y = 900
		game.player._physics_process(0.0)
		await create_timer(0.5, true, false, true).timeout
		check(not game.stage_clear.playing, route + ": a knockout does not play the stage-clear stinger")
		paused = false
	print("PLATFORMER STAGE CLEAR: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await process_frame
	await root.get_node("AudioService").settle()
	quit(1 if failures else 0)
