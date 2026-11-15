extends SceneTree
## Run with --path <project> --script res://tests/menu_smoke.gd. Runs headless in CI; a rendered run
## also saves screenshots. Pointer moves go through tests/support/pointer.gd so they hover headless.
## The hub is a grid of six game tiles (scenes/main_menu/game_catalog.gd), then Settings, Quit Game
## and Credits: `buttons[0..5]` are the tiles, `buttons[6]` Settings, `buttons[7]` Quit Game.
const Pointer := preload("res://tests/support/pointer.gd")
const GameCatalog := preload("res://scenes/main_menu/game_catalog.gd")
const HowToPlayData := preload("res://app/how_to_play_data.gd")
const SETTINGS := 6
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func wait(seconds: float) -> void:
	await create_timer(seconds).timeout
## One press and release of a pad button, each its own event, dispatched through Godot's input.
func pad_press(button: JoyButton) -> void:
	for pressed in [true, false]:
		var pad := InputEventJoypadButton.new()
		pad.button_index = button
		pad.pressed = pressed
		Input.parse_input_event(pad)
		await process_frame
func run() -> void:
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await wait(0.2)
	var menu = current_scene
	var showcase = menu.showcase
	check(showcase.active_index == 0, "Initial preview")
	showcase.set_process(false)
	showcase.idle_remaining = 4.0
	showcase.select_group(3)
	await wait(0.9)
	check(showcase.active_index == 3, "Runner tile selects corridor")
	showcase._process(3.1)
	await wait(0.7)
	check(showcase.active_index == 4, "Runner cycles its gameplay previews")
	check(showcase.idle_remaining == 4.0, "Focus preserves idle dwell")
	showcase.select_group(-1)
	showcase._process(1.0)
	check(showcase.active_index == 4, "Resume waits two seconds")
	showcase._process(1.1)
	await wait(1.3)
	check(showcase.active_index == 0, "Resume restores idle index")
	showcase.select_group(1)
	await wait(0.7)
	# A rendered run can still be finishing the 1.2 s resume fade here; let it land first.
	while showcase.fade and showcase.fade.is_running():
		await process_frame
	showcase._process(3.1)
	await wait(0.7)
	check(showcase.active_index == 1, "A one-stage platformer tile holds its preview")
	showcase.select_group(4)
	await wait(0.7)
	showcase._process(3.1)
	await wait(0.7)
	check(showcase.active_index == 8, "Code City Brawl cycles its districts")
	for expected in [9, 7]:
		showcase._process(3.0)
		await wait(0.7)
		check(showcase.active_index == expected, "Code City Brawl wraps its districts")
	showcase.select_group(5)
	await wait(0.7)
	for expected in [11, 12, 10]:
		showcase._process(3.0)
		await wait(0.7)
		check(showcase.active_index == expected, "Heroes vs. Villains cycles its stages and wraps")
	check(showcase.GROUPS.size() == GameCatalog.GAMES.size(), "One showcase group per tile")
	for i in 30:
		showcase.select_group(i % showcase.GROUPS.size())
		check(showcase.get_child_count() <= 2, "Preview count bounded during rapid input")
	showcase.select_group(3)
	await wait(1.8)
	check(showcase.active_index == 3 and showcase.get_child_count() == 1, "Latest focus wins and settles")
	for i in showcase.COUNT:
		showcase.transition_to(i, 0)
		check(showcase.active_index == i, "All configured previews instantiate")
		check(not showcase.active.plates.is_empty(), "Preview has stage artwork: %d" % i)
	menu._open_settings(menu.buttons[SETTINGS])
	check(menu.modal != null and showcase.suspended, "Settings pauses showcase")
	check(menu.modal.is_ancestor_of(root.gui_get_focus_owner()), "Settings captures focus")
	check(menu.modal.z_index > menu.buttons[0].z_index, "Settings draws over a grown tile")
	menu._close_modal()
	await process_frame
	check(menu.modal == null and not showcase.suspended, "Settings closes cleanly")
	check(root.gui_get_focus_owner() == menu.buttons[SETTINGS], "Settings restores focus")
	# Esc on the hub asks before quitting; Esc again keeps playing.
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	check(menu.modal != null and menu.modal_return == menu.buttons[7], "Esc opens the quit prompt")
	Input.parse_input_event(escape)
	await process_frame
	check(menu.modal == null and root.gui_get_focus_owner() == menu.buttons[7], "Esc closes it again")
	var router = root.get_node("AppRouter")
	router.go("invalid")
	check(not router.busy, "Invalid routes do not lock UI")
	# Every tile names a real gameplay route with a how-to-play card and shows its own art and copy.
	check(menu.buttons.size() == GameCatalog.GAMES.size() + 3, "Six tiles, then Settings, Quit Game and Credits")
	check(menu.buttons[SETTINGS].text == "Settings" and menu.buttons[7].text == "Quit Game"
		and menu.buttons[8].text == "Credits", "Utility buttons keep their order")
	for i in GameCatalog.GAMES.size():
		var game: Dictionary = GameCatalog.GAMES[i]
		var tile = menu.buttons[i]
		check(tile.route == game.route and router.ROUTES.has(game.route) and HowToPlayData.has_game(game.route),
			"Tile %d routes to a gameplay route with a card: %s" % [i, game.route])
		check(not tile.art.is_empty() and tile.art[0].texture != null, "Tile has art: " + game.title)
		var texts: Array = tile.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
		check(game.title in texts and game.tagline in texts and game.family in texts,
			"Tile shows its family, title and tagline: " + game.title)
		check(tile.get_parent() == menu.buttons[0].get_parent() and tile.get_parent() is GridContainer,
			"Tiles share one grid")
	# Every tile launches its game and the game's scene gives the hub back.
	for i in GameCatalog.GAMES.size():
		var route: String = GameCatalog.GAMES[i].route
		current_scene.buttons[i].pressed.emit()
		router.go("runner")
		for frame in 300:
			if not router.busy: break
			await process_frame
		await wait(0.3)
		check(current_scene.scene_file_path == router.ROUTES[route], "Tile launches its game: " + route)
		check(not router.busy, "Navigation unlocks")
		router.go("hub")
		for frame in 300:
			if not router.busy: break
			await process_frame
		await wait(0.3)
		check(current_scene.name == "MainMenu", "Game returns to the hub: " + route)
	# Nullable, like runner_smoke.gd: a missing autoload is a failed check with a clear message, not
	# a crash. Still exactly one check, so the documented 4.7.0 baseline count is unchanged.
	var audio := root.get_node_or_null("AudioService")
	check(audio != null and audio.get_child_count() == 2,
		"AudioService has %d children, expected Music and SFX only (-1 = autoload missing)"
			% (audio.get_child_count() if audio != null else -1))
	# Exercise actual Godot input dispatch, not just controller methods.
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	down.pressed = false
	Input.parse_input_event(down)
	check(root.gui_get_focus_owner() == current_scene.buttons[3], "Keyboard Down moves to the second row")
	check(current_scene.showcase.focus_group == 3, "Keyboard focus selects the runner")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_RIGHT
	pad.pressed = true
	Input.parse_input_event(pad)
	await process_frame
	pad.pressed = false
	Input.parse_input_event(pad)
	check(root.gui_get_focus_owner() == current_scene.buttons[4], "Gamepad D-pad Right moves along the row")
	check(current_scene.showcase.focus_group == 4, "Gamepad focus selects Code City Brawl")
	await pad_press(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == current_scene.buttons[7], "D-pad Down from the bottom row reaches Quit Game")
	check(current_scene.showcase.focus_group == -1, "A utility button releases the game preview")
	await pad_press(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == current_scene.buttons[1], "D-pad Down from Quit Game wraps to the top row")
	await pad_press(JOY_BUTTON_DPAD_LEFT)
	check(root.gui_get_focus_owner() == current_scene.buttons[0], "D-pad Left moves along the row")
	await pad_press(JOY_BUTTON_DPAD_LEFT)
	check(root.gui_get_focus_owner() == current_scene.buttons[2], "D-pad Left wraps within the row")
	Pointer.hover(current_scene.buttons[3])
	await process_frame
	check(current_scene.showcase.focus_group == 3, "Mouse hover overrides old gamepad focus")
	Pointer.move(root, Pointer.corner(root), Vector2(420, 250))
	await process_frame
	check(current_scene.showcase.focus_group == -1, "Pointer exit releases mode preview")
	current_scene.showcase.select_group(-1)
	await wait(3.5)
	current_scene.buttons[0].grab_focus()
	if DisplayServer.get_name() != "headless":
		await wait(0.3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/hoppy-main-menu.png")
		current_scene._open_settings(current_scene.buttons[SETTINGS])
		await wait(0.2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/hoppy-settings.png")
		current_scene._close_modal()
		root.size = Vector2i(1440, 900)
		await wait(0.4)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/hoppy-main-menu-tall.png")
	await process_frame
	print("MENU SMOKE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	# The verdict is already printed; a missing or renamed autoload must not stop quit(failures)
	# from running, or the process hangs instead of reporting.
	var shutdown_audio := root.get_node_or_null("AudioService")
	if shutdown_audio != null and shutdown_audio.has_method("settle"):
		await shutdown_audio.settle()
	quit(failures)
