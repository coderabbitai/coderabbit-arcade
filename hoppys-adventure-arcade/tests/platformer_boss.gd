extends SceneTree
var failures := 0
var level
var player
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func wait_for(condition: Callable, timeout_seconds: float, message: String) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(condition.call(), message)
func capture(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
func run() -> void:
	change_scene_to_file("res://scenes/platformer/bay_area_blitz.tscn")
	await frames(20)
	level = current_scene
	player = level.player
	await process_frame
	level._resume()
	check(level.music.stream == level.LEVEL_MUSIC, "Summer Sunday starts the level")
	level.boss.take_hit()
	check(level.boss.hp == 8, "Boss inactive before encounter")
	player.position = Vector2(4310, 600)
	player.reset_physics_interpolation()
	level.camera.reset_smoothing()
	await frames(3)
	check(level.encounter == "intro" and not level.boss.active, "Entry starts safe intro")
	check(not player.is_physics_processing(), "Intro holds player input")
	await frames(45)
	await capture("/tmp/hoppy-boss-intro.png")
	await process_frame
	level._pause()
	var remaining: float = level.intro_remaining
	await frames(20)
	check(level.intro_remaining == remaining, "Pause freezes intro")
	await process_frame
	level._resume()
	await frames(120)
	check(level.encounter == "fight" and level.boss.active, "Intro starts fight")
	check(level.music.stream == level.MUSIC, "Boss music switches at intro")
	var center: Vector2 = level.camera.get_screen_center_position()
	player.invulnerable = 100
	Input.action_press("move_left")
	await frames(100)
	Input.action_release("move_left")
	check(player.position.x >= 4206, "Arena gate prevents retreat")
	check(level.camera.get_screen_center_position().distance_to(center) < 1, "Camera stays fixed when Hoppy moves")
	level.boss.phase = 0
	var boss_x: float = level.boss.position.x
	await frames(50)
	check(level.boss.position.x < boss_x, "Boss tracks Hoppy")
	level.boss.phase = 3.6
	await frames(46)
	check(level.projectiles.get_child_count() == 3, "Telegraphed volley spawns three projectiles")
	await capture("/tmp/hoppy-boss-volley.png")
	var projectile = level.projectiles.get_child(0)
	await process_frame
	level._pause()
	var before: Vector2 = projectile.position
	await frames(10)
	check(projectile.position == before, "Pause freezes projectiles")
	await process_frame
	level._resume()
	# Damage uses the player's existing shield/i-frame policy.
	level._clear_projectiles()
	await frames(2)
	level.boss.phase = 2.9
	player.position = Vector2(4550, 600)
	player.velocity = Vector2.ZERO
	player.invulnerable = 0
	player.shield = false
	player.hp = 3
	level._spawn_projectile(Vector2(4440, 565), Vector2.RIGHT)
	await frames(25)
	check(player.hp == 2, "Projectile deals one damage")
	player.invulnerable = 100
	level._spawn_projectile(Vector2(4800, 510), Vector2.LEFT)
	for i in 8:
		level.boss.hit_flash = 0
		level.boss.take_hit()
	# Victory celebrates before restoring traversal, gates and the follow camera.
	await wait_for(func() -> bool: return level.encounter == "cleared", 8.0, "Victory celebration completes")
	await frames(3)
	check(level.boss_down and level.encounter == "cleared", "Defeat clears encounter")
	check(level.projectiles.get_child_count() == 0 and not level.arena_gates.visible, "Defeat clears bullets and gates")
	await frames(65)
	check(level.music.stream == level.LEVEL_MUSIC, "Summer Sunday returns after boss")
	# A jump from beneath the one-way button must finish only on descent.
	player.position = Vector2(5090, 600)
	player.velocity = Vector2.ZERO
	await frames(5)
	check(not level.finished, "Standing beside button does not activate it")
	Input.action_press("jump")
	await frames(12)
	check(not level.finished, "Ascending through button does not activate it")
	for i in 90:
		await frames(1)
		if level.finished: break
	Input.action_release("jump")
	check(level.finished and paused, "Landing on unlocked MERGE completes level")
	# Results input becomes available after the frozen victory moment.
	await wait_for(func() -> bool: return level.overlay.visible, 2.0, "Results overlay appears before skip")
	check(level.results_reveal.is_running(), "Results fade is active before skip")
	var skip := InputEventAction.new()
	skip.action = "jump"
	skip.pressed = true
	Input.parse_input_event(skip)
	await process_frame
	await process_frame
	check(level.overlay.visible and is_equal_approx(level.overlay.modulate.a, 1.0), "Jump skips the results fade")
	check(level.resume_button.get_parent().get_child(3).has_focus() and not level.results_reveal.is_running(), "Skipped results still focus Retry")
	check(current_scene == level, "Skip press does not also trigger Retry")
	await capture("/tmp/hoppy-boss-merge-result.png")
	paused = false
	root.get_node("AppRouter").go("bay_area_blitz")
	await create_timer(0.7).timeout
	level = current_scene
	await process_frame
	level._resume()
	check(level.encounter == "approach" and not level.boss.active and level.projectiles.get_child_count() == 0, "Retry resets encounter")
	check(level.music.stream == level.LEVEL_MUSIC and level.camera.get_parent() == level.player, "Retry restores music and following camera")
	# Landing cannot bypass the boss lock.
	level.encounter = "test_locked_exit"
	level.player.position = Vector2(5090, 500)
	level.player.velocity = Vector2(0, 150)
	await frames(30)
	check(not level.finished, "Landing on locked MERGE does not complete level")
	print("BOSS TEST: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	change_scene_to_file("res://scenes/platformer/platformer_menu.tscn")
	await frames(2)
	root.get_node("AudioService").shutdown()
	await create_timer(0.4).timeout
	quit(failures)
