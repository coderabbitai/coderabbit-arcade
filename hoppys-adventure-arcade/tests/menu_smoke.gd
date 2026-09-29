extends SceneTree
## Run with --path <project> --script res://tests/menu_smoke.gd.
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func wait(seconds: float) -> void:
	await create_timer(seconds).timeout
func run() -> void:
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await wait(0.2)
	var menu = current_scene
	var showcase = menu.showcase
	check(showcase.active_index == 0, "Initial preview")
	showcase.set_process(false)
	showcase.idle_remaining = 4.0
	showcase.select_group(1)
	await wait(0.9)
	check(showcase.active_index == 3, "Runner selects corridor")
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
	showcase.select_group(0)
	showcase._process(3.1)
	await wait(0.7)
	check(showcase.active_index == 1, "Platformer cycles")
	showcase.select_group(2)
	await wait(0.7)
	showcase._process(3.1)
	await wait(0.7)
	check(showcase.active_index == 8, "Brawler cycles")
	for i in 30:
		showcase.select_group(i % 3)
		check(showcase.get_child_count() <= 2, "Preview count bounded during rapid input")
	showcase.select_group(1)
	await wait(1.8)
	check(showcase.active_index == 3 and showcase.get_child_count() == 1, "Latest focus wins and settles")
	for i in showcase.COUNT:
		showcase.transition_to(i, 0)
		check(showcase.active_index == i, "All ten previews instantiate")
	menu._open_settings(menu.buttons[3])
	check(menu.modal != null and showcase.suspended, "Settings pauses showcase")
	check(menu.modal.is_ancestor_of(root.gui_get_focus_owner()), "Settings captures focus")
	menu._close_modal()
	await process_frame
	check(menu.modal == null and not showcase.suspended, "Settings closes cleanly")
	check(root.gui_get_focus_owner() == menu.buttons[3], "Settings restores focus")
	var router = root.get_node("AppRouter")
	router.go("invalid")
	check(not router.busy, "Invalid routes do not lock UI")
	for route in ["platformer", "runner", "beatem_up"]:
		router.go(route)
		router.go("runner")
		await wait(0.65)
		check(current_scene.scene_file_path == router.ROUTES[route], "Mode route loads: " + route)
		check(not router.busy, "Navigation unlocks")
		router.go("hub")
		await wait(0.65)
		check(current_scene.name == "MainMenu", "Mode route returns")
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
	check(root.gui_get_focus_owner() == current_scene.buttons[1], "Keyboard moves focus")
	check(current_scene.showcase.focus_group == 1, "Keyboard focus selects runner")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	Input.parse_input_event(pad)
	await process_frame
	pad.pressed = false
	Input.parse_input_event(pad)
	check(root.gui_get_focus_owner() == current_scene.buttons[2], "Gamepad D-pad moves focus")
	check(current_scene.showcase.focus_group == 2, "Gamepad focus selects brawler")
	var mouse := InputEventMouseMotion.new()
	mouse.position = Vector2(200, 430)
	mouse.relative = Vector2(10, 10)
	Input.parse_input_event(mouse)
	await process_frame
	check(current_scene.showcase.focus_group == 1, "Mouse hover overrides old gamepad focus")
	mouse = InputEventMouseMotion.new()
	mouse.position = Vector2(620, 680)
	mouse.relative = Vector2(420, 250)
	Input.parse_input_event(mouse)
	await process_frame
	check(current_scene.showcase.focus_group == -1, "Pointer exit releases mode preview")
	current_scene.showcase.select_group(-1)
	await wait(3.5)
	current_scene.buttons[0].grab_focus()
	if DisplayServer.get_name() != "headless":
		await wait(0.3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/hoppy-main-menu.png")
		current_scene._open_settings(current_scene.buttons[3])
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
	if shutdown_audio != null and shutdown_audio.has_method("shutdown"):
		shutdown_audio.shutdown()
	await wait(0.3)
	quit(failures)
