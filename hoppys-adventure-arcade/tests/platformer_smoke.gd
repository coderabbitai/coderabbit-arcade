extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func capture(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
func run() -> void:
	for binding in [["move_left", KEY_LEFT], ["move_right", KEY_RIGHT], ["jump", KEY_UP]]:
		var key := InputEventKey.new()
		key.physical_keycode = binding[1]
		check(InputMap.action_has_event(binding[0], key), "Arrow key mapping: " + binding[0])
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	check(InputMap.action_has_event("jump", pad), "Controller jump binding")
	pad.button_index = JOY_BUTTON_X
	check(InputMap.action_has_event("attack", pad), "Controller attack binding")
	change_scene_to_file("res://scenes/platformer/bay_area_blitz.tscn")
	await frames(30)
	var level = current_scene
	var player = level.player
	level._resume()
	await frames(10)
	check(player.is_on_floor(), "Spawn lands on solid street")
	await capture("/tmp/hoppy-bay-start.png")
	Input.action_press("jump")
	await frames(3)
	check(player.velocity.y < 0, "Jump launches")
	Input.action_release("jump")
	await frames(45)
	check(player.is_on_floor(), "Jump returns to street")
	# Jump buffering consumes an input pressed shortly before landing.
	player.position = Vector2(150, 570)
	player.velocity = Vector2(0, 240)
	await frames(2)
	Input.action_press("jump")
	await frames(7)
	check(player.velocity.y < 0, "Buffered jump fires on landing")
	Input.action_release("jump")
	await frames(50)
	# Step off a ledge, then jump during the grace window.
	player.position = Vector2(1030, 600)
	player.velocity = Vector2.ZERO
	await frames(3)
	Input.action_press("move_right")
	for i in 25:
		await frames(1)
		if not player.is_on_floor(): break
	await frames(2)
	Input.action_press("jump")
	await frames(2)
	check(player.velocity.y < 0, "Coyote jump works just beyond ledge")
	Input.action_release("jump")
	Input.action_release("move_right")
	player.position = Vector2(150, 500)
	player.velocity = Vector2.ZERO
	await frames(40)
	player.damage(player.position.x + 10)
	player.damage(player.position.x + 10)
	check(player.hp == 2, "Sustained damage honors i-frames")
	player.heal(20)
	check(player.hp == 3, "Healing clamps at three")
	player.invulnerable = 0
	player.shield = true
	player.damage(0)
	check(player.hp == 3 and not player.shield, "Shield absorbs one hit")
	player.invulnerable = 0
	player.boost = 5
	player.damage(0)
	check(player.hp == 3, "Boost prevents damage")
	level._pause()
	var time_before: float = level.elapsed
	var pos_before: Vector2 = player.position
	await frames(10)
	check(level.elapsed == time_before and player.position == pos_before, "Pause freezes world and timers")
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(2)
	check(not paused, "Pause input resumes while tree paused")
	player.boost = 0
	player.position = Vector2(1650, 500)
	player.velocity = Vector2.ZERO
	level.camera.reset_smoothing()
	await frames(5)
	await capture("/tmp/hoppy-bay-cars.png")
	var car = level.cars[0].body
	player.position = car.position + Vector2(0, -130)
	player.velocity = Vector2.ZERO
	await frames(40)
	check(player.is_on_floor() and absf(player.position.x - car.position.x) < 65, "Cable car carries Hoppy on its roof")
	await capture("/tmp/hoppy-bay-car-ride.png")
	# A melee activation cannot apply repeated hits to a two-HP reviewer.
	var reviewer = level._enemy(1650, "request_reviewer")
	reviewer.radius = 0
	player.position = Vector2(1590, 600)
	player.facing = 1
	player.hurt_time = 0
	player.invulnerable = 3
	Input.action_press("attack")
	await frames(20)
	Input.action_release("attack")
	check(reviewer.hp == 1, "Swipe hits each target once")
	await frames(10)
	Input.action_press("attack")
	await frames(20)
	Input.action_release("attack")
	check(reviewer.dead, "Second swipe defeats reviewer")
	check(level.score >= 100, "Enemy defeat awards score")
	player.position = Vector2(4400, 600)
	player.velocity = Vector2.ZERO
	level.camera.reset_smoothing()
	await frames(5)
	await capture("/tmp/hoppy-bay-boss.png")
	check(not level.boss_down and not level.finished, "MERGE remains locked before boss defeat")
	for i in 8:
		level.boss.hit_flash = 0
		level.boss.take_hit()
	check(level.boss_down, "Boss defeat unlocks exit")
	player.position = Vector2(5090, 600)
	player.attack_time = 0.2
	await frames(3)
	check(level.finished and paused, "MERGE finishes run once")
	await capture("/tmp/hoppy-bay-result.png")
	paused = false
	root.get_node("AppRouter").go("bay_area_blitz")
	await create_timer(0.7).timeout
	level = current_scene
	level._resume()
	check(level.score == 0 and level.player.hp == 3 and not level.boss_down, "Retry creates clean session")
	# Traverse the complete ground route with real movement/jumps, no teleportation.
	player = level.player
	player.invulnerable = 60
	Input.action_press("move_right")
	var jumps := [980.0, 2320.0]
	for i in 1000:
		if not jumps.is_empty() and player.position.x >= jumps[0] and player.is_on_floor():
			Input.action_press("jump")
			jumps.pop_front()
		if player.velocity.y > 0: Input.action_release("jump")
		await frames(1)
		if player.position.x >= 4380 or level.finished: break
	Input.action_release("move_right")
	Input.action_release("jump")
	check(player.position.x >= 4380 and player.hp > 0, "Ground route and both gaps are traversable")
	level.player.shield = false
	level.player.boost = 0
	level.player.invulnerable = 0
	level.player.damage(0)
	level.player.invulnerable = 0
	level.player.damage(0)
	level.player.invulnerable = 0
	level.player.damage(0)
	check(level.finished and level.player.hp == 0, "Death ends run")
	paused = false
	root.get_node("AppRouter").go("platformer")
	await create_timer(0.7).timeout
	current_scene._select()
	await frames(3)
	await capture("/tmp/hoppy-level-select.png")
	check(not root.get_node("AudioService").music.stream_paused, "Menu music restored")
	print("PLATFORMER SMOKE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	await frames(35)
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	quit(failures)
