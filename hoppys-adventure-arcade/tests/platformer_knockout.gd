extends SceneTree
## Real shared-level death paths, including off-screen falls. Rendered runs save key poses.
const LEVELS := ["bay_area_blitz", "enchanted_repo", "orbital_ops"]
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

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/platformer-ko-" + name + ".png")

func die(fell: bool) -> void:
	if fell:
		game.player.position.y = 900
		game.player._physics_process(0.0)
	else:
		game.player.hp = 1
		game.player.invulnerable = 0
		game.player.damage(game.player.position.x + 80)

func run() -> void:
	for route in LEVELS:
		for fell in [false, true]:
			await open_level(route)
			var label: String = route + (" pit" if fell else " hit")
			if route == "orbital_ops" and not fell:
				game._change_music(game.boss_track)
				await create_timer(1.0).timeout
			# Dying during a crossfade must retain the stream that is actually playing.
			if fell: game._change_music(game.boss_track)
			var stream: AudioStream = game.music.stream
			var volume: float = game.music.volume_db
			var position: float = game.music.get_playback_position()
			die(fell)
			var completions := [0]
			game.knockout.completed.connect(func(): completions[0] += 1)
			check(game.finished and paused and game.knockout.active, label + ": death starts cutaway with frozen world")
			check(not game.player.sprite.visible and game.knockout.visible, label + ": only cutaway rabbit visible")
			for item in game.gameplay_hud:
				check(not item.visible, label + ": gameplay HUD hidden")
			var world_time: float = game.elapsed
			var world_position: Vector2 = game.player.position
			var camera_transform: Transform2D = game.camera.transform
			var camera_zoom: Vector2 = game.camera.zoom
			game.player._die()
			game._finish(false)
			var jump := InputEventAction.new()
			jump.action = "jump"
			jump.pressed = true
			game._input(jump)
			check(game.results_reveal == null and not game.overlay.visible, label + ": repeat death and input cannot reveal results")
			await create_timer(0.6).timeout
			check(game.knockout.elapsed > 0.4 and game.knockout.rabbit.frame > 0, label + ": cutaway advances through pause")
			check(game.elapsed == world_time and game.player.position == world_position, label + ": world stays still")
			check(game.camera.transform == camera_transform and game.camera.zoom == camera_zoom, label + ": camera untouched")
			check(game.music.playing and not game.music.stream_paused and game.music.stream == stream, label + ": current track continues")
			check(game.music.get_playback_position() > position, label + ": playback advances without restart")
			check(is_equal_approx(game.music.volume_db, volume - 12.0), label + ": music ducks by 12 dB")
			if not fell: await capture(route + "-air")
			game.knockout.set_process(false)
			game.knockout.tick(2.2 - game.knockout.elapsed)
			check(game.knockout.callout.modulate.a == 1.0 and game.knockout.rabbit.frame == 5, label + ": final pose and KO callout")
			check(game.knockout.rabbit.position.distance_to(game.knockout.size * Vector2(0.5, 0.56)) < 100, label + ": close-up centered even after a pit fall")
			if not fell: await capture(route + "-stars")
			game.knockout.tick(10)
			game.knockout.tick(10)
			check(completions[0] == 1 and not game.knockout.active, label + ": exactly one completion")
			await create_timer(0.75).timeout
			check(game.overlay.visible and is_equal_approx(game.overlay.modulate.a, 1.0), label + ": results fade completes")
			var retry: Button = game.resume_button.get_parent().get_child(3)
			check(retry.has_focus(), label + ": Retry focused")
			if not fell: await capture(route + "-results")
			var old_cutaway: WeakRef = weakref(game.knockout)
			retry.pressed.emit()
			await create_timer(1.3).timeout
			game = current_scene
			check(old_cutaway.get_ref() == null and not game.finished and game.player.hp == 3, label + ": retry creates a clean run")
			check(not paused and game.music.process_mode == Node.PROCESS_MODE_PAUSABLE and is_equal_approx(game.music.volume_db, -13.0), label + ": retry restores normal audio and play")
	# Leave at distinct presentation phases; no delayed callback may pause the next screen.
	for seconds in [0.0, 0.8, 2.4]:
		await open_level("bay_area_blitz")
		die(false)
		game.knockout.tick(seconds)
		var old_cutaway: WeakRef = weakref(game.knockout)
		var old_music: WeakRef = weakref(game.music)
		root.get_node("AppRouter").go("platformer")
		await create_timer(1.3).timeout
		check(old_cutaway.get_ref() == null and old_music.get_ref() == null, "Exit frees cutaway and music at %.1f seconds" % seconds)
		check(not paused and not root.get_node("AudioService").music.stream_paused, "Exit restores menu audio and tree")
	print("PLATFORMER KNOCKOUT: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
