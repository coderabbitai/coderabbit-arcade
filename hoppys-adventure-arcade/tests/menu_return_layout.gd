extends SceneTree
## Returning from Bay Area Blitz must leave a working, non-overlapping main menu.
## Run with --path <project> --script res://tests/menu_return_layout.gd (rendered run also saves captures).
var failures := 0
var router: Node
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)
func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout
func settle() -> void:
	for i in 240:
		if not router.busy: break
		await process_frame
	await wait(0.4)
func open_level() -> Node:
	router.go("bay_area_blitz")
	await settle()
	var level = current_scene
	level._resume()
	await wait(0.2)
	return level
func overlay_button(level: Node, index: int) -> Button:
	return level.resume_button.get_parent().get_child(index)
func check_menu(label: String) -> void:
	var menu = current_scene
	check(menu.name == "MainMenu", label + ": back on the main menu")
	check(not router.busy, label + ": router unlocked")
	check(is_zero_approx(router.veil.modulate.a), label + ": veil cleared")
	check(not paused, label + ": tree unpaused")
	await wait(0.3)
	var rects: Array[Rect2] = []
	for button: Button in menu.buttons:
		rects.append(button.get_global_transform() * Rect2(Vector2.ZERO, button.size))
		check(button.pivot_offset.is_equal_approx(button.size * 0.5), label + ": centered pivot on " + button.text.strip_edges())
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			check(not rects[i].intersects(rects[j]), label + ": buttons %d and %d do not overlap" % [i, j])
	var focused := root.gui_get_focus_owner() as Button
	check(focused != null and focused.scale.is_equal_approx(Vector2.ONE * 1.05), label + ": focused button settles at 1.05")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/hoppy-return-%s.png" % label)
func park_mouse_on(menu_index: int) -> void:
	# Leave the pointer where the menu button will appear, as a player's mouse would be.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(200, 360 + menu_index * 74)
	motion.relative = Vector2(1, 1)
	Input.parse_input_event(motion)
func run() -> void:
	router = root.get_node("AppRouter")
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await wait(0.5)
	# 1. Pause -> Return to Arcade.
	var level := await open_level()
	level._pause()
	park_mouse_on(1)
	overlay_button(level, 5).pressed.emit()
	await settle()
	await check_menu("pause-return")
	# 2. Escape pressed during the fade-out re-pauses the dying level.
	level = await open_level()
	level._pause()
	overlay_button(level, 5).pressed.emit()
	await wait(0.1)
	var escape := InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	Input.parse_input_event(escape)
	await wait(1.5)
	await check_menu("escape-during-fade")
	# 3. Focus loss during the fade-out.
	level = await open_level()
	level._pause()
	overlay_button(level, 5).pressed.emit()
	await wait(0.1)
	level.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait(1.5)
	await check_menu("focus-loss-during-fade")
	# 4. Death -> results -> Return to Arcade, with the mouse over a menu button.
	level = await open_level()
	level.player.position.y = 900
	await wait(0.3)
	check(level.finished, "Falling ends the run")
	park_mouse_on(2)
	overlay_button(level, 5).pressed.emit()
	await settle()
	await check_menu("death-return")
	# 5. Retry -> Platformer menu -> hub.
	level = await open_level()
	level._pause()
	overlay_button(level, 3).pressed.emit()
	await settle()
	check(current_scene.name == "BayAreaBlitz", "Retry reloads the level")
	current_scene._pause()
	overlay_button(current_scene, 4).pressed.emit()
	await settle()
	router.go("hub")
	await settle()
	await check_menu("retry-platformer-hub")
	print("MENU RETURN: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	await root.get_node("AudioService").settle()
	quit(failures)
