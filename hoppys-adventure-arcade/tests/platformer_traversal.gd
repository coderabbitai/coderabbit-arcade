extends SceneTree
## Regression for playtest feedback: real jumps onto ledges and cable cars.
var failures := 0
var level: Node2D
var player: CharacterBody2D
func _initialize() -> void:
	call_deferred("run")
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func setup_at(pos: Vector2) -> void:
	Input.action_release("jump")
	Input.action_release("move_right")
	player.position = pos
	player.velocity = Vector2.ZERO
	player.invulnerable = 999
	player.boost = 0
	await frames(12)
func jump_to(target: Vector2) -> bool:
	Input.action_press("jump")
	for i in 90:
		if player.position.x < target.x - 8: Input.action_press("move_right")
		else: Input.action_release("move_right")
		await frames(1)
		if i > 8 and player.is_on_floor():
			Input.action_release("jump")
			Input.action_release("move_right")
			return absf(player.position.y - target.y) < 3 and absf(player.position.x - target.x) < 45
	Input.action_release("jump")
	Input.action_release("move_right")
	return false
func run() -> void:
	change_scene_to_file("res://scenes/platformer/bay_area_blitz.tscn")
	await frames(3)
	level = current_scene
	player = level.player
	level._resume()
	# Street-to-ledge jumps use actual physics and pass through the underside.
	for entry in [Vector2(550, 485), Vector2(1530, 475), Vector2(2880, 480)]:
		await setup_at(Vector2(entry.x, 600))
		check(await jump_to(entry), "Board raised street platform at x=%d" % entry.x)
	# Verify both upward routes, including the previously unreachable cable-car approach.
	for pair in [[Vector2(610, 485), Vector2(770, 385)], [Vector2(1590, 475), Vector2(1800, 370)], [Vector2(2940, 480), Vector2(3110, 380)]]:
		await setup_at(pair[0])
		check(await jump_to(pair[1]), "Reach next upper platform at x=%d" % pair[1].x)
	for data in level.cars:
		# Reset timetable only to start at the boarding stop, never place Hoppy on a roof.
		level.elapsed = 0
		await setup_at(Vector2(data.origin.x, 600))
		var car: AnimatableBody2D = data.body
		check(await jump_to(Vector2(data.origin.x, data.origin.y - 51)), "Jump from street onto cable-car roof")
		var relative_x: float = player.position.x - car.position.x
		var carried := true
		var min_x: float = player.position.x
		var max_x: float = player.position.x
		for i in 660:
			await frames(1)
			min_x = minf(min_x, player.position.x)
			max_x = maxf(max_x, player.position.x)
			if not player.is_on_floor() or absf(player.position.y - (car.position.y - 51)) > 4 or absf(player.position.x - car.position.x - relative_x) > 8:
				carried = false
		check(carried and max_x - min_x > data.travel.x - 15, "Car supports and transports Hoppy through both directions and stops")
		var before: Vector2 = car.position
		level._pause()
		await frames(10)
		check(car.position == before, "Pause freezes the car")
		level._resume()
		await frames(12)
		# Ride to the far stop, then jump off onto the destination steel platform.
		for i in 660:
			await frames(1)
			if fmod(level.elapsed, 10) > 5.1 and fmod(level.elapsed, 10) < 5.4: break
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/hoppy-car-fixed-%d.png" % int(data.origin.x))
		var dest: Vector2 = Vector2(2200, 450) if data.origin.x < 2000 else Vector2(3480, 465)
		check(await jump_to(dest), "Disembark onto destination platform")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/hoppy-traversal-fixed.png")
	print("TRAVERSAL: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	for child in level.get_children():
		if child is AudioStreamPlayer2D:
			child.stop()
			child.stream = null
	level.music.stop()
	level.music.stream = null
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	# Audio cleanup uses wall time even in accelerated --fixed-fps test runs.
	OS.delay_msec(300)
	quit(failures)
