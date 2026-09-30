extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func wait(seconds: float) -> void:
	await create_timer(seconds).timeout
func capture(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
func run() -> void:
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await wait(1)
	var menu = current_scene
	var hoppy = menu.hoppy
	check(hoppy.sprite.animation == &"idle", "Default Hoppy idles in 2D")
	check(hoppy.runner_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden 3D render disabled")
	await capture("/tmp/menu-hoppy-2d.png")
	var mouse := InputEventMouseMotion.new()
	mouse.position = Vector2(200, 430)
	mouse.relative = Vector2(10, 10)
	Input.parse_input_event(mouse)
	await wait(1)
	check(hoppy.runner_image.visible and hoppy.runner_image.modulate.a == 1, "Runner shows 3D")
	check(hoppy.sprite.modulate.a == 0, "2D fades away")
	check(hoppy.runner.anim_state == &"run", "3D run animation active")
	await capture("/tmp/menu-hoppy-3d.png")
	menu._open_settings(menu.buttons[3])
	await wait(0.2)
	await capture("/tmp/menu-hoppy-modal.png")
	menu._close_modal()
	menu.keyboard_input = true
	menu.buttons[2].grab_focus()
	await wait(0.7)
	check(hoppy.sprite.animation == &"idle" and hoppy.sprite.sprite_frames == hoppy.PLATFORMER, "Brawler jab returns to default idle")
	await wait(1.0)
	check(hoppy.sprite.animation == &"idle", "Brawler remains idle while selected")
	menu._select(0)
	await wait(0.8)
	check(hoppy.sprite.animation == &"idle", "Platformer jump returns to idle")
	for i in 20:
		menu._select(i % 3)
		await wait(0.03)
	menu._select(-1)
	await wait(0.4)
	check(not hoppy.runner_image.visible and hoppy.sprite.modulate.a == 1, "Rapid changes settle in 2D")
	check(hoppy.runner.process_mode == Node.PROCESS_MODE_DISABLED, "Hidden rig stops processing")
	check(hoppy.get_child_count() == 3, "Switching reuses portrait nodes")
	print("MENU HOPPY SMOKE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	root.get_node("AudioService").shutdown()
	await wait(0.3)
	quit(failures)
