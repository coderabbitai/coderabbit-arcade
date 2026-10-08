extends SceneTree
var game
var failures := 0
var captures: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	print("PASS: " if ok else "FAIL: ",text)
	if not ok: failures+=1
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false);game.player.controlled=false
	for e in game.enemies+game.bosses:
		if is_instance_valid(e): e.set_physics_process(false)
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless" or captures.has(name): return
	captures[name]=true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://../docs/previews/heroes-villains")
	root.get_texture().get_image().save_png("res://../docs/previews/heroes-villains/"+name+".png")
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/beatem_menu.tscn")
	await process_frame;await process_frame
	current_scene.find_child("HeroesButton",true,false).grab_focus()
	await capture("mode_select")
	check(current_scene.selected_mode==1 and current_scene.description.text.contains("FOUR VILLAINS"),"Mode select previews Heroes vs. Villains")
	root.get_node("AppRouter").go("heroes_vs_villains")
	for i in 100:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path.ends_with("heroes_vs_villains.tscn") and not root.get_node("AppRouter").busy: break
	game=current_scene
	check(game.scene_file_path.ends_with("heroes_vs_villains.tscn"),"Router loads new mode")
	if not game.scene_file_path.ends_with("heroes_vs_villains.tscn"):
		quit(1);return
	game.test_mode=true;freeze()
	game._physics_process(.35)
	await capture("opening")
	while game.state=="cards": game.next_card()
	# Live event mappings: movement, jump, combo, pickup and charged ability.
	var key := InputEventKey.new();key.physical_keycode=KEY_W;key.pressed=true
	Input.parse_input_event(key);await process_frame
	game.player.controlled=true;game.player.input_lock=0
	var before: Vector2=game.player.position
	game.player.tick(.05)
	check(game.player.position.y<before.y and game.player.height==0,"Keyboard W changes depth, not jump")
	key.pressed=false;Input.parse_input_event(key)
	var joy := InputEventJoypadButton.new();joy.device=0;joy.button_index=JOY_BUTTON_A;joy.pressed=true
	Input.parse_input_event(joy);await process_frame
	game.player.tick(.02)
	check(game.player.height>0,"Gamepad A jumps")
	joy.pressed=false;Input.parse_input_event(joy)
	game.player.height=0;game.player.rise=0
	joy=InputEventJoypadButton.new();joy.button_index=JOY_BUTTON_X;joy.pressed=true
	Input.parse_input_event(joy);await process_frame
	game.player.tick(.02)
	check(game.player.swing_left>0,"Gamepad X attacks")
	joy.pressed=false;Input.parse_input_event(joy)
	game.player.swing_left=0
	game.player.position=Vector2(230,595)
	joy=InputEventJoypadButton.new();joy.button_index=JOY_BUTTON_Y;joy.pressed=true
	Input.parse_input_event(joy);await process_frame
	game.player.tick(.02)
	check(game.player.weapon=="review_stamp","Gamepad Y equips nearby weapon")
	joy.pressed=false;Input.parse_input_event(joy)
	game.player.controlled=false
	var rooms: Dictionary={}
	var phases: Dictionary={}
	var maxima := Vector3i.ZERO
	var completed_steps := 0
	# Combat bot tests reachability with invulnerability, not difficulty balance.
	for step in 36000:
		completed_steps=step
		freeze()
		var p=game.player
		p.invulnerable=999
		rooms["%d_%d" % [game.stage_index,game.room]]=true
		if game.state=="won": break
		if game.state=="stage_clear":
			await capture("capability_deployed_%d" % game.stage_index)
			var confirm := InputEventAction.new()
			confirm.action="heroes_popup_advance";confirm.pressed=true
			game._input(confirm)
			await process_frame;freeze()
			var stage_confirm := InputEventAction.new()
			stage_confirm.action="heroes_popup_advance";stage_confirm.pressed=true
			game._input(stage_confirm)
			await process_frame;freeze()
			continue
		if game.state=="boss_victory":
			game._physics_process(1.0/60.0)
			if game.state=="boss_victory" and game.victory_clock>.3: await capture("hoppy_victory_%d" % game.stage_index)
			if step%15==0: await process_frame
			continue
		if game.state=="cards":
			game._physics_process(1.0/60.0)
			if game.state=="cards" and game.card_clock>.35:
				await capture(game.card_queue[0])
				var advance := InputEventAction.new()
				advance.action="heroes_popup_advance";advance.pressed=true
				game._unhandled_input(advance)
			if step%15==0: await process_frame
			continue
		if game.playing:
			var target=null
			var distance := INF
			var shielded := false
			for b in game.bosses:
				if is_instance_valid(b) and not b.dead:
					phases[b.kind+str(b.phase)]=true
					if b.shield_active: shielded=true
			for e in game.enemies:
				if not is_instance_valid(e) or e.dead: continue
				var d: float=p.position.distance_to(e.position)
				if d<distance: target=e;distance=d
			if not shielded:
				for b in game.bosses:
					if is_instance_valid(b) and not b.dead:
						target=b;break
			if target!=null:
				var goal: Vector2=target.position+Vector2(-78,0)
				p.position=game.clamp_ground(p.position.move_toward(goal,260.0/60.0))
				p.facing=1
				if p.position.distance_to(goal)<26 and step%8==0: p.request_attack()
			elif game.gate_open:
				p.position.x=minf(p.position.x+6,game.room_start()+1260)
			if step%60==0 and p.weapon=="": game.pickup_weapon()
			p.tick(1.0/60.0)
			for e in game.enemies.duplicate()+game.bosses.duplicate():
				if is_instance_valid(e) and not e.dead: e.tick(1.0/60.0)
			game._physics_process(1.0/60.0)
			if step%150==0:
				await capture("stage_%d_room_%d" % [game.stage_index+1,game.room+1])
				for b in game.bosses:
					if is_instance_valid(b) and not b.dead: await capture("fight_"+b.kind+"_phase_"+str(b.phase))
		maxima.x=maxi(maxima.x,game.living_enemies())
		maxima.y=maxi(maxima.y,game.bullets.size())
		maxima.z=maxi(maxima.z,game.warnings.size())
		if step%15==0: await process_frame
	check(game.state=="won" and game.completion_count==1,"Combat traversal reaches one victory after %d steps" % completed_steps)
	check(rooms.size()==9,"All nine gated encounters reached")
	check(phases.has("ai_slop3") and phases.has("ai_augmented_hacker3") and phases.has("ten_thousand_line_pr1"),"Traversal reaches all boss mechanics")
	check(maxima.x<=14 and maxima.y<=32 and maxima.z<=12,"Runtime pools remain bounded: "+str(maxima))
	check(game.capabilities.review and game.capabilities.triage and game.capabilities.change_stack and game.capabilities.security,"All capabilities persist through the run")
	await capture("victory_result")
	game.leave()
	for i in 100:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path.ends_with("beatem_menu.tscn") and not root.get_node("AppRouter").busy: break
	check(current_scene.scene_file_path.ends_with("beatem_menu.tscn") and not paused,"Victory returns to an unpaused mode menu")
	current_scene.queue_free();await process_frame
	root.get_node("AudioService").shutdown();await create_timer(.3).timeout
	print("Heroes vs. Villains smoke failures: ",failures)
	quit(0 if failures==0 else 1)
