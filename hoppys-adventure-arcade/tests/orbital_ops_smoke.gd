extends SceneTree
const OrbitalEnemy = preload("res://modes/platformer/orbital_enemy.gd")
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
func place(pos: Vector2) -> void:
	player.position=pos
	player.velocity=Vector2.ZERO
	player.reset_physics_interpolation()
	level.camera.reset_smoothing()

func run() -> void:
	change_scene_to_file("res://scenes/platformer/orbital_ops.tscn")
	await frames(12)
	level=current_scene
	player=level.player
	await process_frame
	level._resume()
	check(player.hp==3 and player.is_on_floor(),"Spawn settles on visible station floor")
	check(level.music.stream==level.ORBITAL_LEVEL_MUSIC,"Zero-G Deploy starts traversal")
	check(level.projectiles.get_child_count()==0 and not level.boss.active,"Fresh run starts with inactive boss and no shots")
	await capture("/tmp/orbital-spawn.png")
	# Same physical jump used in Bay Area, onto a 120px rise.
	place(Vector2(490,600))
	await frames(12) # Resume deliberately ignores input for 150ms.
	Input.action_press("jump")
	await frames(60)
	Input.action_release("jump")
	check(player.is_on_floor() and absf(player.position.y-480)<3,"Normal jump boards upper one-way deck from below")
	# Board the service shuttle using actual input, then ride and pause.
	player.invulnerable=100
	place(Vector2(1840,600))
	level.elapsed=0
	await frames(3)
	Input.action_press("jump")
	await frames(60)
	Input.action_release("jump")
	check(player.is_on_floor() and absf(player.position.y-level.cars[0].body.position.y)<4,"Jump boards service shuttle at its lower stop")
	await frames(155)
	check(player.position.x>1980 and player.is_on_floor(),"Service shuttle carries Hoppy along its route")
	await process_frame
	level._pause()
	var car_pos: Vector2=level.cars[0].body.position
	var hazard_clock: float=level.orbital_hazards[0].clock
	await frames(10)
	check(level.cars[0].body.position==car_pos and level.orbital_hazards[0].clock==hazard_clock,"Pause freezes shuttle and hazard phases")
	await process_frame
	level._resume()
	# True zero gravity with bounded thrust and braking, above the bay's gap.
	place(Vector2(2670,470))
	await frames(12)
	check(player.zero_gravity and absf(player.velocity.y)<1,"Zero-g zone suspends Hoppy above open space")
	Input.action_press("jump")
	await frames(35)
	Input.action_release("jump")
	check(player.position.y<400,"Holding jump provides upward zero-g thrust")
	await frames(60)
	check(absf(player.velocity.y)<1,"Releasing thrust brakes vertical drift")
	Input.action_press("move_down")
	await frames(28)
	Input.action_release("move_down")
	check(player.velocity.y>150,"Down input descends in zero gravity")
	await capture("/tmp/orbital-zero-g.png")
	place(Vector2(3250,350))
	await frames(10)
	check(not player.zero_gravity and player.velocity.y>100,"Leaving the bay restores normal gravity")
	# Hazard state boundaries and i-frame deduplication.
	place(Vector2(1390,600))
	player.hp=3
	player.shield=false
	player.invulnerable=0
	var laser=level.orbital_hazards[0]
	laser.clock=2.1
	await frames(10)
	check(laser.state=="warning" and player.hp==3,"Amber laser telegraph cannot damage")
	laser.clock=3.0
	await frames(5)
	check(player.hp==2,"Active CI laser deals one damage")
	await frames(20)
	check(player.hp==2,"Sustained laser overlap respects invulnerability")
	player.invulnerable=100
	var vent=level.orbital_hazards[3]
	place(Vector2(880,490))
	vent.clock=3.0
	await frames(5)
	check(player.environmental_acceleration.y>0 and player.environmental_acceleration.x<0,"Active vacuum pulls downward and toward grille")
	# Projectile flight must use shared shield and damage policy, not bypass it.
	level._clear_projectiles()
	place(Vector2(350,600))
	player.hp=3
	player.invulnerable=0
	player.shield=true
	level._spawn_projectile(Vector2(250,565),Vector2.RIGHT)
	await frames(25)
	check(player.hp==3 and not player.shield,"Plasma collision consumes shield without health loss")
	player.invulnerable=0
	level._spawn_projectile(Vector2(250,565),Vector2.RIGHT)
	await frames(25)
	check(player.hp==2,"Unshielded plasma flight deals one damage")
	player.invulnerable=100
	# Actual swipe hit detection must deduplicate one attack across overlapping frames.
	var bot
	for child in level.get_children():
		if child is OrbitalEnemy and child.kind=="rogue_ai":
			bot=child
			break
	bot.set_physics_process(false)
	bot.position=Vector2(740,600)
	place(Vector2(690,600))
	player.facing=1
	await frames(12)
	Input.action_press("attack")
	await frames(22)
	Input.action_release("attack")
	check(bot.hp==1,"Swipe deals exactly one damage to rogue AI")
	bot.hit_flash=0
	Input.action_press("attack")
	await frames(24)
	Input.action_release("attack")
	check(not is_instance_valid(bot) or bot.dead,"Second swipe defeats rogue AI")
	# The drone must commit to a warning target rather than home during its dive.
	var drone
	for child in level.get_children():
		if child is OrbitalEnemy and child.kind=="security_drone":
			drone=child
			break
	place(drone.origin+Vector2(-100,200))
	drone.cooldown=0
	drone.attack_clock=-1
	await frames(3)
	var warned_target: Vector2=drone.dive_target
	check(drone.sprite.animation=="ambush_warning","Drone shows a warning before ambushing")
	place(player.position+Vector2(-100,0))
	await frames(53)
	check(drone.dive_target==warned_target and drone.sprite.animation=="dive","Drone dives toward its committed warning target")
	# Traversal validates all gaps with movement inputs, ignoring combat damage only.
	place(Vector2(150,600))
	var jumped := false
	Input.action_press("move_right")
	for i in 950:
		if player.position.x>980 and not jumped:
			Input.action_press("jump")
			jumped=true
		if player.position.x>1230: Input.action_release("jump")
		if player.position.x>2310 and player.position.x<2940: Input.action_press("jump")
		elif player.position.x>=2940:
			Input.action_release("jump")
			Input.action_press("move_down")
		if level.encounter=="intro": break
		await frames(1)
	Input.action_release("move_right")
	Input.action_release("jump")
	Input.action_release("move_down")
	print("Route endpoint: ",player.position," HP=",player.hp," encounter=",level.encounter)
	check(player.position.x>=4300 and level.encounter=="intro" and player.hp>0,"Whole station route and both gaps reach boss via movement inputs")
	if level.finished or level.encounter!="intro":
		await shutdown()
		return
	check(not player.is_physics_processing() and not level.boss.active,"Boss intro locks input and keeps boss inactive")
	level.boss.take_hit()
	check(level.boss.hp==10,"Boss rejects damage during intro")
	await process_frame
	level._pause()
	var intro_time: float=level.intro_remaining
	await frames(10)
	check(level.intro_remaining==intro_time,"Pause freezes boss intro")
	await process_frame
	level._resume()
	await frames(120)
	check(level.encounter=="fight" and level.music.stream==level.ORBITAL_BOSS_MUSIC,"Intro starts fight and The Deprecated API theme")
	var camera_center: Vector2=level.camera.get_screen_center_position()
	Input.action_press("move_left")
	await frames(50)
	Input.action_release("move_left")
	check(player.position.x>=4206 and level.camera.get_screen_center_position().distance_to(camera_center)<1,"Boss arena gate and fixed camera hold")
	level._clear_projectiles()
	level.boss._enter_state(1)
	await frames(54)
	check(level.projectiles.get_child_count()==1,"Cannon warning produces a single committed shot")
	if level.projectiles.get_child_count()==0:
		await shutdown()
		return
	await capture("/tmp/orbital-boss.png")
	await process_frame
	level._pause()
	var shot=level.projectiles.get_child(0)
	var shot_position: Vector2=shot.position
	var boss_time: float=level.boss.state_time
	await frames(10)
	check(shot.position==shot_position and level.boss.state_time==boss_time,"Pause freezes boss attack and projectile")
	await process_frame
	level._resume()
	level._clear_projectiles()
	# Slam is avoidable above its damage band; grounded player takes one hit.
	place(level.boss.position+Vector2(-150,-110))
	player.invulnerable=0
	player.hp=3
	level.boss._enter_state(5)
	await frames(3)
	check(player.hp==3,"Jump height clears boss slam")
	place(level.boss.position+Vector2(-150,0))
	level.boss._enter_state(5)
	await frames(3)
	check(player.hp==2,"Grounded slam deals one damage")
	player.invulnerable=100
	level.boss._enter_state(7)
	var boss_x: float=level.boss.position.x
	await frames(70)
	check(absf(level.boss.position.x-boss_x)>100 and level.boss.position.x>=4320 and level.boss.position.x<=4820,"Dash commits to warned direction and stays inside arena")
	level.boss._enter_state(11)
	await frames(2)
	check(level.boss.sprite.animation=="vulnerable","Broken cycle exposes core during recovery")
	# Land an ordinary swipe on the live boss through its actual hurtbox.
	place(level.boss.position+Vector2(-85,0))
	player.facing=1
	await frames(3)
	Input.action_press("attack")
	await frames(22)
	Input.action_release("attack")
	check(level.boss.hp==9,"An ordinary swipe damages the exposed boss exactly once")
	var score_before_boss: int=level.score
	level._spawn_projectile(Vector2(4600,400),Vector2.LEFT)
	for i in 10:
		level.boss.hit_flash=0
		level.boss.take_hit()
	# Victory celebrates before restoring traversal, gates and the follow camera.
	await wait_for(func() -> bool: return level.encounter == "cleared", 8.0, "Victory celebration completes")
	await frames(3)
	check(level.boss_down and level.encounter=="cleared" and level.projectiles.get_child_count()==0,"Boss defeat unlocks exit and clears shots once")
	check(level.score==score_before_boss+1000,"Boss score is awarded only once")
	check(not level.arena_gates.visible and level.camera.get_parent()==player,"Defeat opens arena and restores following camera")
	await frames(65)
	check(level.music.stream==level.ORBITAL_LEVEL_MUSIC,"Zero-G Deploy resumes after boss defeat")
	place(Vector2(5090,600))
	await frames(5)
	check(not level.finished,"Standing beside MERGE does not complete level")
	Input.action_press("jump")
	await frames(12)
	check(not level.finished,"Ascending through MERGE does not complete level")
	await frames(80)
	Input.action_release("jump")
	check(level.finished and paused,"Landing on unlocked MERGE completes Orbital Ops")
	await capture("/tmp/orbital-complete.png")
	root.get_node("AppRouter").go("orbital_ops")
	await create_timer(.75).timeout
	level=current_scene
	player=level.player
	await process_frame
	level._resume()
	check(not level.finished and player.hp==3 and not player.zero_gravity and level.score==0,"Retry creates fresh health, score, gravity and completion state")
	check(level.music.stream==level.ORBITAL_LEVEL_MUSIC and level.encounter=="approach","Retry restores traversal music and inactive encounter")
	level.encounter="test_locked_exit"
	place(Vector2(5090,500))
	player.velocity.y=150
	await frames(30)
	check(not level.finished,"Locked MERGE cannot bypass boss")
	place(Vector2(2700,870))
	await frames(3)
	check(level.finished and player.hp==0,"Falling out of station produces retry result")
	root.get_node("AppRouter").go("platformer")
	await create_timer(.75).timeout
	check(not paused and not root.get_node("AudioService").music.stream_paused,"Return to platformer menu restores app audio and pause state")
	current_scene._select()
	await frames(3)
	await capture("/tmp/orbital-level-select.png")
	print("ORBITAL OPS: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	await shutdown()

func shutdown() -> void:
	paused=false
	change_scene_to_file("res://scenes/platformer/platformer_menu.tscn")
	await frames(2)
	await root.get_node("AudioService").settle()
	quit(failures)
