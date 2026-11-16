extends SceneTree
## The shared pause menu (app/pause_menu.gd) in all six games: the `pause` action opens it with
## Resume focused and the same buttons everywhere; Resume, a second `pause` press and a mouse click
## resume; Restart reloads the game's own route; Main Menu lands on the hub, unpaused, with the hub
## music back; How to Play reopens the card in PAUSE mode and gives focus back; the runner's
## Leaderboard button opens the top ten with its Reset scores flow and closes without resuming.
## Run headless with --script res://tests/pause_menu.gd.
const PauseMenu := preload("res://app/pause_menu.gd")
const HowToPlay := preload("res://app/how_to_play.gd")
const HeroesCatalog := preload("res://modes/beatem_up/reinvent/catalog.gd")
const Pointer := preload("res://tests/support/pointer.gd")
const RunnerLeaderboard := preload("res://scenes/runner/systems/runner_leaderboard.gd")
const ROUTES: Array[String] = ["bay_area_blitz", "orbital_ops", "enchanted_repo", "runner_game", "code_city_brawl", "heroes_vs_villains"]
var RUNNER_SCORES := "user://test_pause_menu_leaderboard_%d.cfg" % OS.get_process_id()
var failures := 0
var router: Node
var audio: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout

## Waits for the router to finish, on a wall clock: a rendered runner load can take seconds.
func settle_route() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while router.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 3:
		await process_frame

func on(route: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == router.ROUTES[route]

## A real `pause` press and release through Input, as a key or Start would send.
func press_pause() -> void:
	var press := InputEventAction.new()
	press.action = "pause"
	press.pressed = true
	Input.parse_input_event(press)
	var release := press.duplicate() as InputEventAction
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	for i in 2:
		await process_frame

func action(name: StringName) -> void:
	var press := InputEventAction.new()
	press.action = name
	press.pressed = true
	Input.parse_input_event(press)
	var release := press.duplicate() as InputEventAction
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame

func key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func click(control: Control) -> void:
	Pointer.hover(control)
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		control.get_viewport().push_input(event, true)
	await process_frame

## A rendered run saves the screen to /tmp for layout review; headless runs draw nothing.
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/pause-menu-%s.png" % name)

func card() -> Node:
	for i in range(root.get_child_count() - 1, -1, -1):
		var child := root.get_child(i)
		if child.get_script() == HowToPlay and not child.is_queued_for_deletion() and child.visible:
			return child
	return null

## The scene's shared pause menu, wherever the game keeps it.
func menu_of(scene: Node) -> CanvasLayer:
	if scene.has_node("Overlays/PauseMenu"):
		return scene.get_node("Overlays/PauseMenu")
	return scene.get("pause_menu")

## Opens `route` and brings it to a state the player could pause.
func enter(route: String) -> Node:
	router.go(route)
	await settle_route()
	check(on(route), "%s opens" % route)
	var scene := current_scene
	match route:
		"runner_game":
			scene.leaderboard_path = RUNNER_SCORES
			# Autopilot keeps Hoppy alive while the menu is driven at a rendered run's real speed.
			scene.set_autopilot(true)
			scene.skip_run_intro()
			for i in 600:
				if scene.state == &"running" and not scene.can_skip_run_intro():
					break
				await process_frame
		"heroes_vs_villains":
			scene.state = "combat"
	# A rendered window that never had focus pauses the game on its own; start from play.
	await wait(0.3)
	if scene.is_player_paused():
		if scene.has_method("_resume"):
			scene._resume()
		else:
			scene.resume()
		await wait(0.1)
	return scene

func run() -> void:
	router = root.get_node("AppRouter")
	audio = root.get_node("AudioService")
	HeroesCatalog.install_input()
	check(audio.sfx.process_mode == Node.PROCESS_MODE_ALWAYS, "UI blips process while a game is paused")
	await wait(0.3)
	for route in ROUTES:
		await check_route(route)
	await check_runner_leaderboard()
	router.go("hub")
	await settle_route()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(RUNNER_SCORES + suffix):
			DirAccess.remove_absolute(RUNNER_SCORES + suffix)
	print("PAUSE MENU: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	await audio.settle()
	quit(1 if failures else 0)

func check_route(route: String) -> void:
	var scene := await enter(route)
	var menu := menu_of(scene)
	check(menu != null and not menu.is_open(), "%s: the pause menu exists and starts closed" % route)
	if menu == null:
		return
	check(menu.layer == PauseMenu.LAYER and menu.process_mode == Node.PROCESS_MODE_ALWAYS,
		"%s: the menu sits on the shared layer and keeps processing while paused" % route)
	# Open with a real pause press.
	await press_pause()
	check(paused and menu.is_open() and scene.is_player_paused(), "%s: pause opens the menu and pauses the game" % route)
	check(menu.resume_button.has_focus(), "%s: Resume takes focus" % route)
	var expected: Array[String] = ["Resume", "Restart", "How to Play", "Main Menu"]
	if route == "runner_game":
		expected.insert(3, "Leaderboard")
	var texts: Array[String] = []
	for button in menu.buttons:
		texts.append(button.text)
	check(texts == expected, "%s: buttons are %s (got %s)" % [route, expected, texts])
	check(menu.eyebrow.visible and not menu.eyebrow.text.is_empty() and menu.title_label.text == "PAUSED", "%s: the card names the game under PAUSED" % route)
	await capture(route)
	for label: Label in menu.ui.find_children("*", "Label", true, false):
		check(label.get_theme_font_size("font_size") >= 18 and label.get_theme_constant("outline_size") >= 6,
			"%s: legible label '%s'" % [route, label.text])
	# Focus wraps in both directions (D-pad and stick ride ui_up / ui_down).
	await action(&"ui_up")
	check(menu.buttons[menu.buttons.size() - 1].has_focus(), "%s: up from Resume wraps to Main Menu" % route)
	await action(&"ui_down")
	check(menu.resume_button.has_focus(), "%s: down from Main Menu wraps to Resume" % route)
	# Mouse hover focuses; a click on Resume resumes.
	Pointer.hover(menu.restart_button)
	await process_frame
	check(menu.restart_button.has_focus(), "%s: hovering a button focuses it" % route)
	await click(menu.resume_button)
	check(not paused and not menu.is_open() and not scene.is_player_paused(), "%s: clicking Resume resumes" % route)
	# A second pause press resumes too.
	await press_pause()
	check(paused and menu.is_open(), "%s: pause reopens the menu" % route)
	await press_pause()
	check(not paused and not menu.is_open(), "%s: pause again resumes" % route)
	# Confirm on the focused Resume (keyboard / pad A) resumes.
	await press_pause()
	await action(&"ui_accept")
	check(not paused and not menu.is_open(), "%s: Enter on Resume resumes" % route)
	# How to Play opens the card over the menu, the game stays paused, focus comes back.
	await press_pause()
	router.how_to_play_enabled = true
	menu.how_to_play_button.grab_focus()
	menu.how_to_play_button.pressed.emit()
	var shown := card()
	check(shown != null and shown.mode == HowToPlay.Mode.PAUSE and shown.route == route, "%s: How to Play opens the card in pause mode" % route)
	check(paused and menu.is_open(), "%s: the game stays paused under the card" % route)
	if shown != null:
		shown.age = HowToPlay.ARM_SECONDS
		key(KEY_ESCAPE)
		key(KEY_ESCAPE, false)
		for i in 10:
			await physics_frame
		await process_frame
		check(card() == null and paused and menu.is_open(), "%s: Esc closes the card and leaves the menu up" % route)
		check(menu.how_to_play_button.has_focus(), "%s: focus returns to How to Play" % route)
	router.how_to_play_enabled = false
	# Restart reloads the same route as a fresh scene, unpaused, and locks the menu meanwhile.
	var old: WeakRef = weakref(scene)
	menu.restart_button.pressed.emit()
	check(menu.locked and menu.menu_button.disabled, "%s: a press locks the menu until the route lands" % route)
	await settle_route()
	check(on(route) and old.get_ref() == null and not paused, "%s: Restart reloads the game unpaused" % route)
	check(card() == null, "%s: Restart shows no how-to-play card" % route)
	scene = await enter(route)
	menu = menu_of(scene)
	# Main Menu lands on the hub, unpaused, with the hub music back.
	await press_pause()
	check(paused and menu.is_open(), "%s: paused before Main Menu" % route)
	menu.menu_button.pressed.emit()
	await settle_route()
	check(current_scene != null and current_scene.name == "MainMenu" and not paused, "%s: Main Menu lands on the hub, unpaused" % route)
	check(audio.music.stream == audio.default_track and audio.music.playing and not audio.music.stream_paused,
		"%s: the hub music is back" % route)
	check(audio.music.process_mode == Node.PROCESS_MODE_INHERIT, "%s: the hub music pauses with the tree again" % route)
	await wait(0.2)

func check_runner_leaderboard() -> void:
	for i in 3:
		RunnerLeaderboard.submit({"run_id": "seed-%d" % i, "name": "Tester", "score": 100 + i * 10,
			"duration": 60.0, "seed": 1, "submitted_at": 1700000000}, RUNNER_SCORES)
	var scene := await enter("runner_game")
	var menu := menu_of(scene)
	await press_pause()
	check(paused and menu.is_open(), "runner: paused for the leaderboard")
	menu.leaderboard_button.grab_focus()
	menu.leaderboard_button.pressed.emit()
	await process_frame
	var board: Control = menu.leaderboard
	check(board != null and board.board.get_child_count() == 10 and board.close_btn.has_focus(), "runner: Leaderboard opens the top ten with Close focused")
	if board == null:
		return
	check(board.leaderboard_path_at_open == RUNNER_SCORES and not board.reset_btn.disabled, "runner: the panel reads the game's board and offers Reset")
	await capture("runner-leaderboard")
	for button in menu.buttons:
		check(button.disabled, "runner: the menu's %s is blocked under the board" % button.text)
	# Start closes the board, not the run's pause.
	await press_pause()
	check(menu.leaderboard == null and paused and menu.is_open() and menu.leaderboard_button.has_focus(),
		"runner: Start closes the board, keeps the run paused and refocuses Leaderboard")
	# Reset asks first; Keep scores cancels; Reset clears.
	menu.leaderboard_button.pressed.emit()
	await process_frame
	board = menu.leaderboard
	var entries_before := RunnerLeaderboard.load_entries(RUNNER_SCORES).size()
	board.reset_btn.pressed.emit()
	await process_frame
	var keep: Button = board.reset_confirm.find_child("KeepScoresButton", true, false) as Button if board.reset_confirm else null
	check(keep != null and keep.has_focus(), "runner: Reset asks, with Keep scores focused")
	if keep:
		keep.pressed.emit()
	await process_frame
	check(board.reset_confirm == null and RunnerLeaderboard.load_entries(RUNNER_SCORES).size() == entries_before, "runner: Keep scores keeps them")
	board.reset_btn.pressed.emit()
	await process_frame
	var confirm: Button = board.reset_confirm.find_child("ResetConfirmButton", true, false) as Button if board.reset_confirm else null
	if confirm:
		confirm.pressed.emit()
	await process_frame
	check(RunnerLeaderboard.load_entries(RUNNER_SCORES).is_empty() and board.reset_btn.disabled and board.close_btn.has_focus(),
		"runner: Reset clears the board and disables itself")
	board.close_btn.pressed.emit()
	await process_frame
	check(menu.leaderboard == null and paused, "runner: Close shuts the board; the run is still paused")
	menu.menu_button.pressed.emit()
	await settle_route()
	check(current_scene != null and current_scene.name == "MainMenu" and not paused, "runner: Main Menu after the leaderboard lands on the hub")
