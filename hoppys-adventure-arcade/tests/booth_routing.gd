extends SceneTree
## Booth routing: --attract picks where idle and finished players go; a game over in booth mode
## sends the player on once their --retries are used, with a next-player card, and ends their
## session as game_over; outside booth mode every game's own retry screen is unchanged. Each game
## (Heroes vs. Villains, Code City Brawl, a platformer level, the runner) is driven through its
## real game-over path. Run headless with --script res://tests/booth_routing.gd.
const ChildGame := preload("res://tests/support/child_game.gd")
const LOG_DIR := "user://test_booth_routing_sessions"
const RUNNER_GAME_OVER := "res://scenes/runner/ui/game_over.tscn"
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

## Launch the game headless with user args for one simulated second; return its output.
func launch(user_args: Array[String]) -> String:
	var args: Array[String] = ["--fixed-fps", "60", "--quit-after", "60", "--"]
	args.append_array(user_args)
	var child: Dictionary = await ChildGame.run(self, args)
	return child.log

func ended_by() -> Array:
	var reasons := []
	var file := FileAccess.open(router.session_log.path, FileAccess.READ)
	while file != null and not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var record: Variant = JSON.parse_string(line)
		if record is Dictionary and record.event == "end":
			reasons.append(record.ended_by)
	return reasons

func clean() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(LOG_DIR)

func run() -> void:
	router = root.get_node("AppRouter")
	clean()
	await wait(0.3)
	check(router.attract_route(PackedStringArray()) == "hub", "The hub is the default attract route")
	check(router.attract_route(PackedStringArray(["--attract=beatem_up"])) == "beatem_up",
		"--attract names the attract route")
	check(router.attract_route(PackedStringArray(["--attract=nowhere"])) == "hub",
		"An unknown --attract falls back to the hub")
	check(router.retry_count(PackedStringArray()) == 0, "Booth players get no retries by default")
	check(router.retry_count(PackedStringArray(["--retries=2"])) == 2, "--retries sets the retries")
	check(router.retry_count(PackedStringArray(["--retries=-1"])) == 0
		and router.retry_count(PackedStringArray(["--retries=lots"])) == 0,
		"A bad --retries means none")
	var kiosk: String = await launch(["--booth", "--attract=beatem_up", "--retries=1"])
	check(kiosk.contains("AppRouter: booth attract route beatem_up, 1 retries per player"),
		"The launch flags reach the router")

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
	for i in 100:
		await wait(0.1)
		if card_up():
			break
	check(card_up() and not level.overlay.visible,
		"A platformer level hands its game over to the booth after the knockout")
	await finish_card()
	check(on("beatem_up") and not paused, "The platformer's next player starts unpaused")

	var runner_screen: CanvasLayer = load(RUNNER_GAME_OVER).instantiate()
	root.add_child(runner_screen)
	runner_screen._finished({"score": 4242})
	check(not runner_screen.visible and card_up()
		and router.next_player.summary.text == "SCORE 00004242",
		"The runner's game over hands off to the booth with its score")
	runner_screen.queue_free()
	await finish_card()

	router.attract = "platformer"
	await visit("orbital_ops")
	router.idle_limit = 0.4
	await wait(0.8)
	await settle_route()
	check(on("platformer"), "An idle game returns to the attract route")
	router.idle_limit = router.IDLE_SECONDS

	router.session_log.end("quit")
	var reasons := ended_by()
	check(reasons.slice(0, 3) == ["game_over", "game_over", "game_over"] and "idle" in reasons,
		"Booth game overs end their sessions as game_over (got %s)" % [reasons])

	router.set_booth(false)
	router.attract = "hub"
	router.retry_limit = 0
	check(not card_up(), "Leaving booth mode clears the card")
	clean()
	await root.get_node("AudioService").settle()
	print("Booth routing failures: ", failures)
	quit(1 if failures else 0)
