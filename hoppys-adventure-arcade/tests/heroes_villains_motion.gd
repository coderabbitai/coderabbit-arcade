extends SceneTree
var game
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action=action;event.pressed=true
	game._unhandled_input(event)
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn")
	await process_frame;await process_frame
	game=current_scene;game.test_mode=true;paused=false;game.set_physics_process(false)
	var p=game.player
	p.set_physics_process(false)
	# Every blocking card must wait indefinitely, then advance exactly once per press.
	var names := ["opening_situation","opening_complication","opening_resolution","boss_ai_slop","boss_agent_army","boss_ten_thousand_line_pr","boss_ai_augmented_hacker","unlock_review","unlock_triage","unlock_change_stack","unlock_security","victory"]
	game.show_cards(names,game.begin_play)
	for name in names:
		game._physics_process(120)
		check(game.state=="cards" and game.card_queue[0]==name and not game.playing and game.card.position.x==0,name+" waits for player input")
		var before: int=game.card_queue.size()
		for code in [KEY_J,KEY_X,KEY_SPACE]:
			var combat := InputEventKey.new()
			combat.physical_keycode=code;combat.pressed=true
			game._unhandled_input(combat)
		for button in [JOY_BUTTON_A,JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_LEFT_SHOULDER]:
			var combat := InputEventJoypadButton.new()
			combat.button_index=button;combat.pressed=true
			game._unhandled_input(combat)
		check(game.card_queue.size()==before,"Combat/jump/pickup buttons cannot dismiss "+name)
		press("pause");game._physics_process(120)
		check(paused and game.card_queue.size()==before,"Pause keeps "+name+" pending")
		press("pause")
		var advance: InputEvent
		if before%2==0:
			var enter := InputEventKey.new()
			enter.physical_keycode=KEY_ENTER;enter.pressed=true
			advance=enter
		else:
			var select := InputEventJoypadButton.new()
			select.button_index=JOY_BUTTON_BACK;select.pressed=true
			advance=select
		check(advance.is_action_pressed("heroes_popup_advance"),"Dedicated physical input is mapped")
		game._unhandled_input(advance)
		check(game.card_queue.size()==before-1,"One press advances "+name+" once")
	check(game.playing and not paused,"Final manual advance resumes gameplay")
	# Exercise GUI dispatch too: default ui_accept/A must not click Continue.
	game.state="stage_intro";game.playing=false
	game.show_overlay("Stage", "Ready", "Continue", game.begin_play)
	var accept := InputEventJoypadButton.new()
	accept.button_index=JOY_BUTTON_A;accept.pressed=true
	root.push_input(accept)
	accept.pressed=false;root.push_input(accept)
	check(not game.playing and game.state=="stage_intro","Controller jump cannot activate focused Continue button")
	var confirm := InputEventJoypadButton.new()
	confirm.button_index=JOY_BUTTON_BACK;confirm.pressed=true
	root.push_input(confirm)
	confirm.pressed=false;root.push_input(confirm)
	check(game.playing,"Controller View confirms focused Continue button")
	for e in game.enemies: e.set_physics_process(false)
	p.input_lock=0;p.position=Vector2(500,550)
	for spec in [["move_right","run"],["move_up","walk_up"],["move_down","walk_down"]]:
		Input.action_press(spec[0]);p.tick(1.0/60.0)
		check(p.body.animation==spec[1],spec[0]+" selects directional locomotion")
		check(is_equal_approx(p.velocity.length(),264),"Unmodified movement uses responsive speed")
		var frames: SpriteFrames=p.body.sprite_frames
		var regions: Array=[]
		for i in frames.get_frame_count(spec[1]): regions.append(frames.get_frame_texture(spec[1],i).region)
		check(regions.size()==8 and frames.get_animation_loop(spec[1]),spec[1]+" has eight looping frames")
		var unique: Dictionary={}
		for region in regions: unique[region]=true
		check(unique.size()==8,spec[1]+" uses distinct cels")
		p.body.set_frame_and_progress(3,.4);p.tick(0)
		check(p.body.frame==3 and is_equal_approx(p.body.frame_progress,.4),"Repeated movement ticks preserve animation progress")
		Input.action_release(spec[0])
	Input.action_press("move_left");p.tick(.01)
	check(p.body.animation=="run" and p.body.flip_h,"Left movement mirrors side cycle")
	Input.action_release("move_left");p.tick(.01)
	check(p.body.animation=="idle" and p.body.sprite_frames==p.COMBAT_FRAMES,"Stopping restores armored idle")
	Input.action_press("move_right");p.effects.speed_surge=8;p.tick(.01)
	check(is_equal_approx(p.velocity.length(),369.6) and is_equal_approx(p.body.speed_scale,1.4),"Speed surge scales travel and foot cadence together")
	p.effects.clear();p.effects.overwhelmed=5;p.tick(.01)
	check(is_equal_approx(p.body.speed_scale,.6),"Slow status scales foot cadence")
	p.effects.clear();Input.action_release("move_right")
	p.jump();p.tick(.01)
	check(p.body.animation=="jump" and p.body.sprite_frames==p.COMBAT_FRAMES,"Jump retains armored air pose")
	p.height=0;p.rise=0;p.start_attack();p.tick(.01)
	check(p.body.sprite_frames==p.COMBAT_FRAMES,"Attack restores combat frames")
	p.swing_left=0;p.combo=0;p.combo_window=0;p.facing=1
	for side in [1,-1]:
		p.facing=side;p.tick(0)
		check(p.body.offset==Vector2(0,-51),"Unarmed offset stays (0,-51) facing %d"%side)
	p.facing=1
	p.equip("review_stamp");p.pickup_time=0;p.tick(0)
	check(p.body.animation=="hold_idle" and p.body.sprite_frames!=p.COMBAT_FRAMES and p.body.sprite_frames.has_animation("hold_idle"),"Equipped stamp idles on baked hold_idle sheet")
	check(not p.held.sprite.visible,"Baked stamp hides the legacy weapon sprite")
	check(not p.body.flip_h and is_equal_approx(p.body.offset.x,32) and is_equal_approx(p.body.offset.y,-67),"Armed idle facing right uses baked offset (32,-67)")
	p.facing=-1;p.tick(0)
	check(p.body.flip_h and p.body.animation=="hold_idle","Armed idle mirrors when facing left")
	check(is_equal_approx(p.body.offset.x,-32) and is_equal_approx(p.body.offset.y,-67),"Armed idle facing left negates offset.x only")
	p.facing=1;p.tick(0)
	check(not p.body.flip_h,"Armed idle facing right clears flip_h")
	for spec in [[.15,0],[.5,1],[.85,2]]:
		p.swing_left=0;p.combo=0;p.combo_window=0;p.start_attack()
		p.swing_fired=true;p.swing_left=p.swing_duration*(1.0-spec[0]);p.tick(0)
		check(p.body.animation=="step1" and p.body.frame==spec[1],"Armed attack progress %.2f shows step1 frame %d"%[spec[0],spec[1]])
		check(p.body.animation!="idle","Armed attack progress %.2f never snaps to idle"%spec[0])
	p.facing=-1;p.tick(0)
	check(p.body.flip_h,"Armed attack mirrors when facing left")
	p.swing_left=0;p.swing_fired=true;p.tick(0)
	for clip in ["walk_up","walk_down"]:
		p.facing=-1;p.pose_move=Vector2(0,-1 if clip=="walk_up" else 1);p.show_pose(clip)
		check(p.body.animation==clip and p.body.sprite_frames==p.MOTION_FRAMES and not p.body.flip_h,"Armed "+clip+" uses unflipped directional frames")
		if clip=="walk_up": check(p.held.carry.visible and p.held.z_index==-1,"Carried stamp sits behind the body on walk_up")
	p.pose_move=Vector2.ZERO;p.facing=1
	p.equip("triage_hammer");p.pickup_time=0;p.tick(0)
	check(p.body.animation=="idle" and p.body.sprite_frames==p.COMBAT_FRAMES,"Sheetless hammer idles on combat frames")
	check(p.held.sprite.visible and not p.held.carry.visible,"Sheetless hammer uses the legacy sprite")
	check(p.held.sprite.offset.distance_to(Vector2(56,-32))<1.0,"Hammer is gripped by its handle")
	p.swing_left=0;p.combo=0;p.combo_window=0;p.start_attack()
	p.swing_fired=true;p.swing_left=p.swing_duration*.5;p.tick(0)
	check(not p.body.animation.begins_with("step"),"Sheetless hammer never uses armed step clips")
	p.swing_left=0;p.visual_weapon="";p.weapon="";p.tick(0)

	if DisplayServer.get_name()!="headless":
		game.world.hide()
		var layer := CanvasLayer.new()
		layer.layer=100;root.add_child(layer)
		var bg := ColorRect.new()
		bg.color=Color("17212c");bg.size=Vector2(1280,720);layer.add_child(bg)
		var title := Label.new()
		title.text="THE CODERABBIT · EIGHT-FRAME DIRECTIONAL MOVEMENT"
		title.position=Vector2(35,20);title.add_theme_font_size_override("font_size",26);layer.add_child(title)
		for row in 3:
			var clip: String=["run","walk_up","walk_down"][row]
			for i in 8:
				var sprite := AnimatedSprite2D.new()
				sprite.sprite_frames=p.MOTION_FRAMES
				sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
				sprite.position=Vector2(110+i*150,150+row*205)
				sprite.scale=Vector2.ONE*1.6
				layer.add_child(sprite);sprite.play(clip);sprite.pause();sprite.frame=i
			var label := Label.new()
			label.text=clip.replace("_"," ").to_upper()+" · 14 FPS"
			label.position=Vector2(35,240+row*205);layer.add_child(label)
		p.show_pose("run");var old_frame: int=p.body.frame
		await create_timer(.12).timeout
		check(p.body.frame!=old_frame,"Rendered sprite advances naturally between physics ticks")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../docs/previews/heroes-villains/movement_cycles.png")
		layer.queue_free()
	if DisplayServer.get_name()!="headless":
		game.world.show()
		for e in game.enemies:
			if is_instance_valid(e): e.queue_free()
		game.enemies.clear()
		for prop in game.props: prop.node.queue_free()
		game.props.clear()
		for item in game.pickups: item.node.queue_free()
		game.pickups.clear()
		p.hide();game.camera.position=Vector2(640,360)
		var actors: Array=[]
		var specs := [["review_stamp",1],["triage_hammer",1],["change_stack_baton",1],["security_scanner",1],["pr_merger",1],["review_stamp",-1]]
		for i in specs.size():
			var q=game.Player.new();q.arena=game;q.set_physics_process(false)
			game.actors.add_child(q);q.position=Vector2(190+i*180,560)
			q.equip(specs[i][0]);q.pickup_time=0;q.facing=specs[i][1]
			actors.append(q)
		for shot in [[.25,"25"],[.44,"44"],[.85,"85"]]:
			for q in actors:
				q.swing_left=0;q.combo=0;q.combo_window=0;q.start_attack()
				q.swing_fired=true;q.swing_left=q.swing_duration*(1.0-shot[0]);q.tick(0)
			if shot[0]>.8: check(actors[0].body.animation=="step1","Baked stamp follow-through keeps the step pose in the capture")
			await create_timer(.1).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../docs/previews/heroes-villains/weapons_%s.png"%shot[1])
		for q in actors: q.queue_free()
	print("Heroes vs. Villains motion failures: ",failures)
	root.get_node("AudioService").shutdown()
	game.queue_free()
	await process_frame;await process_frame
	quit(1 if failures else 0)
