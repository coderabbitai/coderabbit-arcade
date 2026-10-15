extends SceneTree
const ForestEnemy = preload("res://modes/platformer/enchanted_enemy.gd")
var failures := 0
var level
var player

func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func wait_for(condition: Callable, timeout_seconds: float, message: String) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(condition.call(), message)
func capture(path: String) -> void:
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
func place(pos: Vector2) -> void:
	player.position=pos
	player.velocity=Vector2.ZERO
	player.hurt_time=0
	player.attack_time=0
	player.buffer=0
	player.reset_physics_interpolation()
	level.camera.reset_smoothing()
func release() -> void:
	for action in ["jump","move_right","move_left","attack"]: Input.action_release(action)

func run() -> void:
	change_scene_to_file("res://scenes/platformer/enchanted_repo.tscn")
	await frames(12)
	level=current_scene
	player=level.player
	await process_frame
	level._resume()
	check(player.hp==3 and player.is_on_floor(),"Fresh run spawns on visible ground")
	check(level.music.stream==level.FOREST_MUSIC,"Silent Forest starts traversal")
	check(not level.boss.active and level.boss.hp==12,"Monolith waits with intact armor")
	await capture("/tmp/enchanted-spawn.png")
	# Board a raised platform using the real controller.
	player.invulnerable=999
	place(Vector2(470,600))
	await frames(12)
	Input.action_press("jump")
	await frames(60)
	Input.action_release("jump")
	check(player.is_on_floor() and absf(player.position.y-480)<3,"Jump passes through and lands on root platform")
	# Crumble from a real landing, freeze in warning, then verify collision and regrowth.
	var branch=level.branches[2]
	place(Vector2(2110,600))
	await frames(12)
	Input.action_press("jump")
	await frames(55)
	Input.action_release("jump")
	check(branch.state=="warning" and player.is_on_floor(),"Landing starts branch warning while it still supports Hoppy")
	await process_frame
	level._pause()
	var branch_clock: float=branch.clock
	var hazard_clock: float=level.forest_hazards[0].clock
	await frames(12)
	check(branch.clock==branch_clock and level.forest_hazards[0].clock==hazard_clock,"Pause freezes branch and trap clocks")
	await process_frame
	level._resume()
	await frames(60)
	check(branch.state=="gone" and branch.collider.disabled and player.position.y>500,"Collapsed branch removes collision")
	await frames(240)
	check(branch.state=="intact" and not branch.collider.disabled,"Branch regrows safely after cooldown")
	# Damage phases, shields and i-frames.
	place(Vector2(900,600))
	player.hp=3
	player.shield=false
	player.invulnerable=0
	var comment=level.forest_hazards[0]
	comment.clock=2.1
	await frames(8)
	check(comment.state=="warning" and player.hp==3,"Amber comment warning is safe")
	comment.clock=2.95
	await frames(5)
	check(player.hp==2,"Comment burst deals one damage")
	await frames(12)
	check(player.hp==2,"Persistent burst respects invulnerability")
	place(Vector2(900,600))
	player.invulnerable=0
	player.shield=true
	comment.clock=2.95
	await frames(5)
	check(player.hp==2 and not player.shield,"Comment burst consumes shield without health loss")
	player.invulnerable=999
	var vine=level.forest_hazards[1]
	place(Vector2(1830,600))
	vine.clock=2.1
	await frames(4)
	check(vine.state=="warning","Vine telegraphs before whipping")
	player.invulnerable=0
	vine.clock=2.95
	await frames(4)
	check(player.hp==1,"Active vine whip hits its warned side")
	player.invulnerable=999
	player.hp=3
	# An actual swipe must not hit the same troll repeatedly.
	var troll
	for child in level.get_children():
		if child is ForestEnemy and child.kind=="bloat_troll":
			troll=child
			break
	troll.set_physics_process(false)
	troll.position=Vector2(1510,600)
	place(Vector2(1430,600))
	player.facing=1
	await frames(12)
	Input.action_press("attack")
	await frames(24)
	Input.action_release("attack")
	check(troll.hp==1,"One swipe deals exactly one troll damage")
	troll.hit_flash=0
	Input.action_press("attack")
	await frames(24)
	Input.action_release("attack")
	check(not is_instance_valid(troll) or troll.dead,"Second swipe defeats troll")
	# Whole route: movement/jump input only; invulnerability isolates reachability.
	place(Vector2(150,600))
	var gap := 0
	var jumping := false
	var starts := [1010.0,2290.0,3410.0]
	var ends := [1300.0,2590.0,3710.0]
	Input.action_press("move_right")
	for i in 1050:
		if gap<3 and not jumping and player.position.x>starts[gap] and player.is_on_floor():
			Input.action_press("jump")
			jumping=true
		if gap<3 and jumping and player.position.x>ends[gap]:
			Input.action_release("jump")
			jumping=false
			gap+=1
		if level.encounter=="intro" or level.finished: break
		await frames(1)
	release()
	print("Route endpoint: ",player.position," gaps=",gap," encounter=",level.encounter)
	check(level.encounter=="intro" and gap==3 and player.hp>0,"Entire forest route and all three gaps reach arena by input")
	if level.encounter!="intro":
		await shutdown()
		return
	check(not player.is_physics_processing() and not level.boss.active,"Intro safely locks player and boss")
	level.boss.take_hit()
	check(level.boss.hp==12,"Intro rejects boss damage")
	await process_frame
	level._pause()
	var intro_clock: float=level.intro_remaining
	await frames(12)
	check(level.intro_remaining==intro_clock,"Pause freezes intro")
	await process_frame
	level._resume()
	await frames(120)
	check(level.encounter=="fight" and level.music.stream==level.BOSS_MUSIC,"Battle 1 starts for the boss fight")
	await capture("/tmp/enchanted-boss.png")
	var center: Vector2=level.camera.get_screen_center_position()
	Input.action_press("move_left")
	await frames(50)
	Input.action_release("move_left")
	check(player.position.x>=4206 and level.camera.get_screen_center_position().distance_to(center)<1,"Arena gate and fixed camera hold")
	# Locked armor versus recovery windows.
	level.boss._enter_state(1)
	level.boss.take_hit()
	check(level.boss.hp==12,"Armored warning rejects damage")
	place(level.boss.position+Vector2(-140,-100))
	player.invulnerable=0
	player.hp=3
	level.boss._enter_state(2)
	await frames(3)
	check(player.hp==3,"Jump clears the slam damage band")
	place(level.boss.position+Vector2(-140,0))
	level.boss._enter_state(2)
	await frames(3)
	check(player.hp==2,"Grounded slam deals one damage")
	player.invulnerable=999
	place(level.boss.position+Vector2(-180,0))
	level.boss._enter_state(5)
	var committed: float=level.boss.direction
	place(level.boss.position+Vector2(180,0))
	await frames(56)
	check(level.boss.direction==committed and level.boss.state()=="sweep","Sweep commits to telegraphed side")
	level.boss._enter_state(9)
	await frames(62)
	check(level.projectiles.get_child_count()==1,"Stomp warning emits one ground shockwave")
	await process_frame
	level._pause()
	var wave=level.projectiles.get_child(0)
	var wave_pos: Vector2=wave.position
	var boss_clock: float=level.boss.state_time
	await frames(12)
	check(wave.position==wave_pos and level.boss.state_time==boss_clock,"Pause freezes wave and boss attack")
	await process_frame
	level._resume()
	level._clear_projectiles()
	# Actual projectile flight, using shared shield behavior.
	place(Vector2(4390,600))
	player.hp=3
	player.invulnerable=0
	player.shield=true
	level.boss._enter_state(3)
	level._spawn_wave(Vector2(4280,582),Vector2.RIGHT)
	await frames(30)
	check(player.hp==3 and not player.shield,"Ground wave consumes shield via collision")
	player.invulnerable=999
	# Swipe through actual hurtbox, then exercise both armor transitions.
	level.boss._enter_state(3)
	place(level.boss.position+Vector2(-90,0))
	player.facing=1
	await frames(12)
	Input.action_press("attack")
	await frames(24)
	Input.action_release("attack")
	check(level.boss.hp==11,"Recovery swipe chips armor once")
	for i in 2:
		level.boss.hit_flash=0
		level.boss.take_hit()
	check(level.boss.hp==9 and level.boss.armor_stage==1 and level.boss.break_time>0,"First layer strips after three hits")
	level.boss.take_hit()
	check(level.boss.hp==9,"Armor-break interlude rejects duplicate damage")
	await frames(65)
	check(level.boss.sprite.animation=="cracked_exposed","Recovery retains partly stripped appearance")
	for i in 3:
		level.boss.hit_flash=0
		level.boss.take_hit()
	check(level.boss.hp==6 and level.boss.armor_stage==2,"Second layer exposes the six-hit core")
	await frames(65)
	check(level.boss.sprite.animation=="bare_exposed","Bare recovery never restores stripped armor")
	await capture("/tmp/enchanted-core.png")
	var score_before: int=level.score
	level._spawn_wave(Vector2(4550,582),Vector2.LEFT)
	for i in 7:
		level.boss.hit_flash=0
		level.boss.take_hit()
	# Victory celebrates before restoring traversal, gates and the follow camera.
	await wait_for(func() -> bool: return level.encounter == "cleared", 8.0, "Victory celebration completes")
	await frames(3)
	check(level.boss_down and level.encounter=="cleared" and level.projectiles.get_child_count()==0,"Defeat clears waves and unlocks MERGE")
	check(level.score==score_before+1000,"Boss score awards exactly once")
	check(not level.arena_gates.visible and level.camera.get_parent()==player,"Defeat opens gates and restores follow camera")
	await frames(65)
	check(level.music.stream==level.FOREST_MUSIC,"Silent Forest resumes after victory")
	place(Vector2(5090,600))
	await frames(5)
	check(not level.finished,"Standing beside MERGE cannot finish")
	Input.action_press("jump")
	await frames(12)
	check(not level.finished,"Rising through MERGE cannot finish")
	await frames(80)
	Input.action_release("jump")
	check(level.finished and paused,"Landing on unlocked MERGE completes level")
	await capture("/tmp/enchanted-complete.png")
	root.get_node("AppRouter").go("enchanted_repo")
	await create_timer(.75).timeout
	level=current_scene
	player=level.player
	await process_frame
	level._resume()
	check(not level.finished and player.hp==3 and level.score==0 and level.boss.armor_stage==0 and level.boss.hp==12,"Retry resets player, score and both armor layers")
	check(level.branches[2].state=="intact" and level.projectiles.get_child_count()==0 and level.encounter=="approach","Retry resets branches, waves and encounter")
	check(level.music.stream==level.FOREST_MUSIC,"Retry starts Silent Forest")
	level.encounter="test_locked_exit"
	place(Vector2(5090,500))
	player.velocity.y=150
	await frames(30)
	check(not level.finished,"Locked exit cannot bypass boss")
	place(Vector2(1150,870))
	await frames(3)
	check(level.finished and player.hp==0,"Pit fall produces retry result")
	root.get_node("AppRouter").go("platformer")
	await create_timer(.75).timeout
	check(not paused and not root.get_node("AudioService").music.stream_paused,"Returning to menu restores audio and pause state")
	current_scene._select()
	await frames(3)
	await capture("/tmp/enchanted-level-select.png")
	print("ENCHANTED REPO: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	await shutdown()

func shutdown() -> void:
	release()
	paused=false
	change_scene_to_file("res://scenes/platformer/platformer_menu.tscn")
	await frames(2)
	await root.get_node("AudioService").settle()
	quit(failures)
