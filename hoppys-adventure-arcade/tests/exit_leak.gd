extends SceneTree
## Quits the game from a screen with its audio playing, as a player closing the window would, so
## a wrapper can assert the exit is clean. Godot reports leaks only after this script is gone, so
## tools/checks/exit_leak.py runs one scenario per process and fails on "leaked at exit" or
## "still in use at exit". Run with --path <project> --script res://tests/exit_leak.gd
## -- --scenario=<name>. Scenarios: hub, hub_quit (a bare quit(), as the suites end), code_city,
## mini_boss, celebration, heroes_knockout, runner_intro.
const SCENARIOS := ["hub", "hub_quit", "code_city", "mini_boss", "celebration", "heroes_knockout", "runner_intro"]
const HUB := "res://scenes/main_menu/main_menu.tscn"
const CODE_CITY := "res://scenes/beatem_up/code_city_brawl.tscn"
const HEROES := "res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn"
const RUNNER_MENU := "res://scenes/runner/runner_menu.tscn"
const RUNNER := "res://scenes/runner/runner_game.tscn"
## Wall-clock seconds the screen plays before the quit, with its music and effects running.
const HOLD := 1.5
var scenario := "hub"
var game: Node

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
	run.call_deferred()

func fail(message: String) -> void:
	print("FAIL: ", scenario, ": ", message)
	quit(1)

func router() -> Node:
	return root.get_node("AppRouter")

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

## Wall-clock deadlines: a rendered run is uncapped, so frame counts say nothing about time.
func wait_until(test: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000.0)
	while not test.call():
		if Time.get_ticks_msec() >= deadline: return false
		await process_frame
	return true

## Takes `route` through the router as the menus do, and adopts the scene it lands on.
func route(name: String, path: String) -> bool:
	if not await wait_until(func() -> bool: return not router().busy, 10.0): return false
	router().go(name)
	var landed := await wait_until(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == path and not router().busy, 30.0)
	game = current_scene
	return landed

func beat_em_up(name: String, path: String) -> bool:
	if not await route(name, path): return false
	game.test_mode = true
	# A window that starts unfocused can focus-pause the game before test_mode is set.
	paused = false
	if game.state == "paused": game.resume()
	return true

func code_city_combat() -> bool:
	if not await beat_em_up("code_city_brawl", CODE_CITY): return false
	game.finish_story()
	return await wait_until(func() -> bool: return game.state == "combat", 10.0)

func run() -> void:
	if scenario not in SCENARIOS:
		fail("unknown scenario (expected one of %s)" % ", ".join(SCENARIOS))
		return
	# A rendered start is still adding the autoloads' nodes to root for its first frames.
	await wait(.5)
	change_scene_to_file(HUB)
	if not await wait_until(func() -> bool: return current_scene != null and current_scene.scene_file_path == HUB, 10.0):
		fail("the hub never loaded")
		return
	var reached := await reach()
	if not reached:
		fail("never reached the screen")
		return
	await wait(HOLD)
	print("EXIT_LEAK reached ", scenario)
	if scenario == "hub_quit":
		quit()
	else:
		# What a window close (or Cmd+Q) delivers: AppRouter fades out and quits.
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func reach() -> bool:
	match scenario:
		"hub", "hub_quit":
			return true
		"code_city":
			return await code_city_combat()
		"mini_boss":
			# Room 3 of district 1, wave down: the district boss drops in on Boss Fight 2.
			if not await code_city_combat(): return false
			game.enter_room(2)
			game.player.position = Vector2(game.room_start()+300, 580)
			for enemy in game.enemies:
				if is_instance_valid(enemy): enemy.queue_free()
			game.enemies.clear()
			return await wait_until(func() -> bool: return game.has_mini_boss(), 5.0)
		"celebration":
			# The Grand Merge Conflict's finisher, then the party with its victory loop playing.
			if not await code_city_combat(): return false
			game.start_stage(2)
			if not await wait_until(func() -> bool: return game.state == "combat", 10.0): return false
			game.enter_room(2)
			game.player.position = Vector2(game.room_start()+300, 580)
			game.boss_defeated()
			return await wait_until(func() -> bool:
				return game.state == "celebration" and game.party.clock >= game.party.LOOP_AT, 15.0)
		"heroes_knockout":
			if not await beat_em_up("heroes_vs_villains", HEROES): return false
			for i in 6:
				if game.state != "cards": break
				game.next_card()
				await process_frame
			if not await wait_until(func() -> bool: return game.state == "combat", 10.0): return false
			game.knockout(game.player.position+Vector2(60, 0))
			return await wait_until(func() -> bool: return game.ko.phase == "card", 8.0)
		"runner_intro":
			if not await route("runner", RUNNER_MENU): return false
			if not await route("runner_game", RUNNER): return false
			if bool(game.paused): game.resume()
			return await wait_until(func() -> bool: return game.run_intro_mode != &"", 5.0)
	return false
