extends SceneTree
var game
var failures := 0
var captures: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.controlled=false
	for e in game.enemies:
		if is_instance_valid(e): e.set_physics_process(false)
	if is_instance_valid(game.boss): game.boss.set_physics_process(false)
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless" or captures.has(name): return
	captures[name]=true
	# The bot steps the game by hand between engine ticks; draw the current state, not the last tick.
	if is_instance_valid(game):
		game.world.reset_physics_interpolation()
		game.camera.reset_physics_interpolation()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://../docs/previews/code-city")
	root.get_texture().get_image().save_png("res://../docs/previews/code-city/"+name+".png")
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/beatem_menu.tscn")
	await process_frame;await process_frame
	await capture("menu")
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame;await process_frame
	game=current_scene
	game.test_mode=true
	# A window that starts unfocused can focus-pause the game before test_mode is set.
	paused=false
	if game.state=="paused": game.resume()
	freeze()
	# Verify event mappings against the live controller, including gamepad buttons.
	# The run itself never confirms: no begin_play, advance_stage, or button press.
	var key := InputEventKey.new()
	key.physical_keycode=KEY_W;key.pressed=true
	Input.parse_input_event(key)
	await process_frame
	game.player.controlled=true;game.player.input_lock=0
	var before: Vector2=game.player.position
	game.player.tick(.05)
	check(game.player.position.y<before.y and game.player.height==0,"Keyboard W moves in depth without jumping")
	key.pressed=false;Input.parse_input_event(key)
	var joy := InputEventJoypadButton.new()
	joy.device=0;joy.button_index=JOY_BUTTON_A;joy.pressed=true
	Input.parse_input_event(joy)
	await process_frame
	game.player.tick(.02)
	check(game.player.height>0,"Gamepad A mapping jumps")
	joy.pressed=false;Input.parse_input_event(joy)
	game.player.height=0;game.player.rise=0
	await process_frame
	var attack_event := InputEventJoypadButton.new()
	attack_event.device=0;attack_event.button_index=JOY_BUTTON_X;attack_event.pressed=true
	Input.parse_input_event(attack_event)
	await process_frame
	game.player.tick(.02)
	check(game.player.swing_left>0,"Gamepad X mapping attacks")
	attack_event.pressed=false;Input.parse_input_event(attack_event)
	game.player.controlled=false
	var max_enemies := 0
	var max_bullets := 0
	var rooms: Dictionary = {}
	var elapsed_steps := 0
	var stage_exits := 0
	var stage_enters := 0
	var combat_starts := 0
	var combat_from_enter := true
	var first_enter_step := -1
	# This bot tests reachability/cleanup with invulnerability, not game balance.
	# 24000 steps covers the 13.5s intro plus about 2.1s for each of the two transitions.
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	for step in 24000:
		await physics_frame
		elapsed_steps=step
		freeze()
		var p=game.player
		p.invulnerable=999
		var tag="%d_%d" % [game.stage_index,game.room]
		rooms[tag]=true
		if game.state=="won": break
		if step%120==0:
			# Stage previews show combat, not the intro or the run-in (stage_banner covers that).
			if game.room==0 and game.playing and not game.flow.banner_panel.visible: await capture("stage_%d" % (game.stage_index+1))
			if is_instance_valid(game.boss): await capture("boss_phase_%d" % game.boss.phase)
		if game.playing:
			var target=null
			var best=INF
			for e in game.enemies:
				if not is_instance_valid(e) or e.dead or e.state in ["fallen","rise"]: continue
				var d: float=e.position.distance_to(p.position)
				if d<best: target=e;best=d
			# Pursue the mobile boss through its setup, rather than spending every
			# recovery window clearing its renewable reinforcements.
			if is_instance_valid(game.boss) and not game.boss.dead: target=game.boss
			if target!=null:
				var goal: Vector2=target.position+Vector2(-67,0)
				p.position=game.clamp_ground(p.position.move_toward(goal,250.0/60.0))
				p.facing=1
				if p.position.distance_to(goal)<24 and step%10==0: p.request_attack()
			elif game.gate_open:
				p.position.x += 260.0/60.0
			game.player.tick(1.0/60.0)
			for e in game.enemies.duplicate():
				if is_instance_valid(e): e.tick(1.0/60.0)
			if is_instance_valid(game.boss): game.boss.tick(1.0/60.0)
		var prev: String = game.state
		game._physics_process(1.0/60.0)
		# The intro preview is the first story scene once its caption is typed (it opens on black).
		if game.state=="intro" and game.intro_page==0 and game.intro_clock>=3.0: await capture("intro")
		if game.state=="stage_exit" and prev!="stage_exit": stage_exits += 1
		if game.state=="stage_enter" and prev!="stage_enter":
			stage_enters += 1
			if first_enter_step<0: first_enter_step = step
		if game.state=="combat" and prev!="combat":
			combat_starts += 1
			if prev!="stage_enter": combat_from_enter = false
		if game.flow.phase=="fade_out" and game.flow.veil.color.a>=0.4 and game.flow.veil.color.a<=0.7:
			await capture("stage_fade")
		if game.state=="combat" and game.stage_index==1 and game.flow.banner_panel.visible and game.flow.banner_panel.modulate.a>0.9:
			await capture("stage_banner")
		max_enemies=maxi(max_enemies,game.living_enemies())
		max_bullets=maxi(max_bullets,game.bullets.size())
		if step%60==0: await process_frame
	check(game.state=="won","All three stages and final boss can reach completion")
	check(rooms.size()==9,"Traversal visited all nine gated encounters")
	check(max_enemies<=12 and max_bullets<=32,"Combat pools remain bounded")
	check(game.completion_count==1,"Full run reports one completion")
	check(stage_exits==2 and stage_enters==3,"Passed through stage_exit twice and stage_enter three times")
	check(combat_starts==3 and combat_from_enter,"Every combat start was preceded by stage_enter")
	check(first_enter_step>=780,"No confirm input; intro auto-advanced into stage_enter")
	if game.state=="won": await capture("victory")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("Simulation steps: ",elapsed_steps,"; rooms: ",rooms.size(),"; state: ",game.state,"; enemies: ",game.living_enemies())
	if is_instance_valid(game.boss): print("Boss HP ",game.boss.hp," phase ",game.boss.phase)
	change_scene_to_file("res://scenes/beatem_up/beatem_menu.tscn")
	await process_frame;await process_frame
	check(not paused and current_scene.name=="BeatemMenu","Completion returns cleanly to the mode menu")
	current_scene.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(.4).timeout
	quit(1 if failures else 0)
