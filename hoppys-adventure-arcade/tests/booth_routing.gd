extends SceneTree
## Booth routing: --attract picks the menu where idle and finished players go; a game over in booth
## mode sends the player on once their --retries are used, with a next-player card, and ends their
## session as game_over; outside booth mode every game's own retry screen is unchanged. Each game
## (Heroes vs. Villains, Code City Brawl, a platformer level, the runner) is driven through its
## real game-over path. Run headless with --script res://tests/booth_routing.gd.
const ChildGame := preload("res://tests/support/child_game.gd")
const LOG_DIR := "user://test_booth_routing_sessions"
const CHILD_LOG_DIR := "user://test_booth_routing_child_sessions"
const RUNNER_SCORES := "user://test_booth_routing_leaderboard.cfg"
var failures := 0
var router: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout

func settle_route() -> void:
	for i in 300:
		if not router.busy:
			break
		await process_frame
	await process_frame

func visit(route: String) -> void:
	router.go(route)
	await settle_route()
	await wait(0.2)

func on(route: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == router.ROUTES[route]

func card_up() -> bool:
	return router.next_player != null and router.next_player.visible

## Wait out the card's countdown (shortened) and the route change it starts.
func finish_card() -> void:
	router.next_player_left = 0.2
	for i in 50:
		await wait(0.1)
		if not card_up() and not router.busy:
			break
	await settle_route()

## Wait, at most `seconds`, until the next-player card is up.
func card_within(seconds: float) -> bool:
	for i in int(seconds * 10):
		if card_up():
			return true
		await wait(0.1)
	return card_up()

## Launch the game headless with user args for one simulated second, its session log kept in a
## folder this suite removes. Returns the child's exit code and output.
func launch(user_args: Array[String]) -> Dictionary:
	var args: Array[String] = ["--fixed-fps", "60", "--quit-after", "60", "--",
		"--session-log=" + ProjectSettings.globalize_path(CHILD_LOG_DIR)]
	args.append_array(user_args)
	return await ChildGame.run(self, args)

func ends() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(router.session_log.path, FileAccess.READ)
	while file != null and not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var record: Variant = JSON.parse_string(line)
		if record is Dictionary and record.event == "end":
			result.append(record)
	return result

func clean() -> void:
	for folder in [LOG_DIR, CHILD_LOG_DIR]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for file_name in dir.get_files():
			dir.remove(file_name)
		DirAccess.remove_absolute(folder)
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(RUNNER_SCORES + suffix):
			DirAccess.remove_absolute(RUNNER_SCORES + suffix)

func run() -> void:
	router = root.get_node("AppRouter")
	clean()
	await wait(0.3)
	check(router.attract_route(PackedStringArray()) == "hub", "The hub is the default attract route")
	check(router.attract_route(PackedStringArray(["--attract=beatem_up"])) == "beatem_up"
		and router.attract_route(PackedStringArray(["--attract=runner"])) == "runner",
		"--attract picks one of the attract menus")
	check(router.attract_route(PackedStringArray(["--attract=heroes_vs_villains"])) == "hub"
		and router.attract_route(PackedStringArray(["--attract=platformer"])) == "hub"
		and router.attract_route(PackedStringArray(["--attract=nowhere"])) == "hub",
		"A game, a menu without its own music, or an unknown name falls back to the hub")
	check(router.retry_count(PackedStringArray()) == 0, "Booth players get no retries by default")
	check(router.retry_count(PackedStringArray(["--retries=2"])) == 2, "--retries sets the retries")
	check(router.retry_count(PackedStringArray(["--retries=-1"])) == 0
		and router.retry_count(PackedStringArray(["--retries=lots"])) == 0,
		"A bad --retries means none")
	var kiosk: Dictionary = await launch(["--booth", "--attract=beatem_up", "--retries=1"])
	check(kiosk.code == 0
		and kiosk.log.contains("AppRouter: booth attract route beatem_up, 1 retries per player"),
		"The launch flags reach the router (exit %d)" % kiosk.code)

	# Outside booth mode nothing changes: the game shows its own retry screen.
	await visit("heroes_vs_villains")
	current_scene.game_over()
	await process_frame
	check(current_scene.overlay.visible and not card_up(),
		"Without booth mode, Heroes vs. Villains shows its own retry screen")
	check(not router.booth_game_over(), "booth_game_over() is false outside booth mode")

	router.start_session_log(LOG_DIR)
	router.set_booth(true)
	router.retry_limit = 1
	router.attract = "beatem_up"
	await visit("heroes_vs_villains")
	current_scene.game_over()
	await process_frame
	check(current_scene.overlay.visible and not card_up(), "With a retry left, the game offers it")
	current_scene.retry_stage()
	await wait(0.2)
	current_scene.game_over()
	await process_frame
	check(not current_scene.overlay.visible and card_up(),
		"With the retries used, the game shows no retry screen and the next-player card appears")
	check(router.next_player.summary.text == "SCORE %05d" % current_scene.score,
		"The card shows the game's score")
	check(router.next_player_left > router.NEXT_PLAYER_SECONDS - 1.0,
		"The card starts its countdown from six seconds")
	await finish_card()
	check(on("beatem_up") and not card_up() and router.game_overs == 0,
		"After the countdown the attract route opens for the next player")

	router.retry_limit = 0
	await visit("code_city_brawl")
	current_scene.game_over()
	await process_frame
	check(not current_scene.overlay.visible and card_up(),
		"Code City Brawl hands its game over to the booth")
	await finish_card()
	check(on("beatem_up"), "Code City Brawl's next player starts at the attract route")

	await visit("bay_area_blitz")
	var level := current_scene
	level._finish(false)
	check(await card_within(10.0) and not level.overlay.visible,
		"A platformer level hands its game over to the booth after the knockout")
	await finish_card()
	check(on("beatem_up") and not paused, "The platformer's next player starts unpaused")

	# The real runner: its game-over screen hears run_finished and hands off.
	await visit("runner_game")
	var runner := current_scene
	runner.leaderboard_path = RUNNER_SCORES
	runner._finish_run(&"caught")
	var screen: CanvasLayer = null
	for child in runner.find_children("*", "CanvasLayer", true, false):
		if child.has_method("show_result"):
			screen = child
	check(await card_within(5.0) and screen != null and not screen.visible
		and router.next_player.summary.text.begins_with("SCORE "),
		"The runner's game-over screen hands off to the booth with its score")
	await finish_card()
	check(on("beatem_up"), "The runner's next player starts at the attract route")

	# A game over while a route change is already under way leaves it to that change.
	await visit("code_city_brawl")
	router.go("beatem_up")
	check(not router.booth_game_over(), "No takeover while a route change is under way")
	await settle_route()

	# Turning booth mode off mid-countdown hands off at once instead of stranding the game.
	await visit("bay_area_blitz")
	current_scene._finish(false)
	check(await card_within(10.0), "The card is up before booth mode is turned off")
	router.set_booth(false)
	await settle_route()
	check(not card_up() and on("beatem_up") and not paused,
		"Leaving booth mode mid-countdown clears the card and opens the attract route")
	router.set_booth(true)
	router.retry_limit = 0

	router.attract = "runner"
	await visit("orbital_ops")
	router.idle_limit = 0.4
	await wait(0.8)
	await settle_route()
	check(on("runner"), "An idle game returns to the attract route")
	router.idle_limit = router.IDLE_SECONDS

	var records := ends()
	var reasons := records.map(func(record: Dictionary) -> String: return record.ended_by)
	check(reasons.slice(0, 4) == ["game_over", "game_over", "game_over", "game_over"]
		and "idle" in reasons, "Booth game overs end their sessions as game_over (got %s)" % [reasons])
	check(not records.is_empty() and int(records[0].game_overs) == 2,
		"The session counts both of the player's losses, the retried one included")

	router.set_booth(false)
	router.attract = "hub"
	router.retry_limit = 0
	clean()
	await root.get_node("AudioService").settle()
	print("Booth routing failures: ", failures)
	quit(1 if failures else 0)
