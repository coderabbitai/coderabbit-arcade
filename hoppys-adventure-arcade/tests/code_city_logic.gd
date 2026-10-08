extends SceneTree
var Game
const Catalog = preload("res://modes/beatem_up/catalog.gd")
var failures := 0
var game
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures += 1
func frames(n: int) -> void:
	for i in n: await physics_frame
func clear_enemies() -> void:
	for e in game.enemies:
		if is_instance_valid(e): e.queue_free()
	game.enemies.clear()
func enemy(kind: String, pos: Vector2, split := false):
	var e=game.spawn_enemy(kind,pos,split)
	e.set_physics_process(false)
	return e
func freeze() -> void:
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.controlled=false
	for e in game.enemies: e.set_physics_process(false)
	if is_instance_valid(game.boss): game.boss.set_physics_process(false)
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame
	await process_frame
	await frames(5)
	game=current_scene
	Game=game.get_script()
	game.test_mode=true
	freeze()
	check(game.state=="intro" and not game.playing,"Opening sequence precedes combat")
	game.begin_play()
	check(game.playing and game.stage_index==0,"Skip/complete enters stage 1")
	var p=game.player
	check(p.get_child(0).polygon.size()==24,"Ground shadow has visible geometry independent of jump height")
	clear_enemies()
	check(not InputMap.action_get_events("brawl_jump").any(func(e): return e is InputEventKey and e.physical_keycode==KEY_W),"W depth movement cannot trigger jump")
	p.position=Vector2(400,550)
	p.jump()
	p.tick(.1)
	check(p.height>30 and is_equal_approx(p.position.y,550.0),"Jump height is independent of ground depth")
	p.height=0;p.rise=0
	p.start_attack()
	check(p.combo==1,"Combo begins with jab")
	p.swing_left=0;p.combo_window=.3;p.start_attack()
	check(p.combo==2,"Next timely input chains to swing")
	p.swing_left=0;p.combo_window=.3;p.start_attack()
	check(p.combo==3,"Third input chains to kick")
	p.swing_left=0;p.combo_window=0;p.start_attack()
	check(p.combo==1,"Expired window resets combo")
	p.swing_left=.1;p.request_attack()
	check(p.queued,"Late input buffers the next combo step")
	p.tick(.11)
	check(p.combo==2 and not p.queued,"Buffered step is consumed exactly once")
	p.swing_left=0;p.queued=false;p.combo=1;p.facing=1
	var a=enemy("syntax_error_sprite",Vector2(470,550))
	var b=enemy("syntax_error_sprite",Vector2(470,640))
	p.swing_serial+=1;p.attack_weapon=""
	game.resolve_swing(p)
	game.resolve_swing(p)
	check(a.hp==1 and b.hp==2,"One attack hits once and excludes another depth lane")
	check(not Game.melee_contains(Vector2(-65,0),1,110,45),"Melee excludes targets behind Hoppy")
	p.equip("linter_staff")
	b.position.y=590
	p.start_attack()
	game.resolve_swing(p)
	check(p.durability==7 and a.dead and b.hp==1,"AoE hits multiple targets for one durability charge")
	p.durability=1;p.spend_weapon()
	check(p.weapon=="" and p.durability==0,"Final weapon charge returns to unarmed")
	clear_enemies()
	p.position=Vector2(400,550);p.equip("refactor_hammer")
	var hammer_target=enemy("syntax_error_sprite",Vector2(470,550))
	game.spawn_prop("kiosk",Vector2(480,550),0)
	var hammer_prop=game.props.back()
	p.start_attack();game.resolve_swing(p)
	check(hammer_target.dead and hammer_prop.hp==2 and p.durability==2,"Hammer hits one target even with a prop in range")
	p.hp=3;p.invulnerable=0;p.shield=true
	p.take_hit(Vector2(350,550),"confused")
	check(p.hp==3 and not p.shield and not p.effects.has("confused"),"Approval shield blocks HP and status")
	p.equip("firewall_shield");p.invulnerable=0
	p.take_hit(Vector2(350,550))
	check(p.hp==3 and p.durability==2,"Firewall shield spends a blocked-hit charge")
	p.weapon="";p.invulnerable=0;p.swing_left=.2;p.queued=true
	p.take_hit(Vector2(350,550),"slow")
	p.take_hit(Vector2(350,550))
	check(p.hp==2 and p.swing_left==0 and not p.queued,"Damage cancels attacks and i-frames stop repeat damage")
	p.apply_effect("slow");p.effects.slow=.05;p.stagger=0;p.knock=Vector2.ZERO;p.tick(.1)
	check(not p.effects.has("slow"),"Status expiry clears its movement modifier")
	p.apply_effect("coffee");p.apply_effect("coffee")
	check(p.hp==3,"Healing clamps to three HP")
	clear_enemies()
	var lint=enemy("linter_enforcer",Vector2(500,550))
	lint.take_hit(4,0,p.position)
	check(lint.hp==2 and not lint.armor and lint.body.sprite_frames==preload("res://modes/beatem_up/art.gd").frames("linter_bare"),"First Linter hit consumes armor and one HP, preserving bare appearance")
	clear_enemies()
	var soldier=enemy("merge_conflict_soldier",Vector2(600,550),true)
	soldier.take_hit(1,0,p.position)
	check(game.living_enemies()==2,"Soldier's first hit registers a gate-blocking duplicate")
	var clone=game.enemies[1]
	clone.set_physics_process(false)
	clone.take_hit(1,0,p.position)
	check(game.living_enemies()==2 and not clone.can_split,"Duplicates cannot recursively duplicate")
	soldier.take_hit(5,0,p.position)
	check(game.living_enemies()==1,"Gate remains blocked by the surviving duplicate")
	clear_enemies()
	var zombie=enemy("stale_branch_zombie",Vector2(600,550))
	zombie.take_hit(3,0,p.position)
	check(not zombie.dead and game.living_enemies()==1 and zombie.state=="fallen","First zombie defeat remains registered with the gate")
	zombie.tick(1.81);zombie.tick(.61)
	check(zombie.hp==2 and zombie.resurrected,"Zombie returns once with two HP")
	zombie.take_hit(3,0,p.position)
	check(zombie.dead and game.living_enemies()==0,"Second zombie defeat is permanent")
	game.gate_open=false
	game._physics_process(.01)
	check(game.gate_open,"Gate opens only after permanent combatant clearance")
	game.drop("api_key_whip",p.position)
	game._tick_items(.01)
	check(p.weapon=="","Walking over a weapon does not auto-equip")
	game.pickup_weapon()
	check(p.weapon=="api_key_whip","Dedicated pickup equips the nearby weapon")
	game.ground_warning(p.position,Vector2(60,35),1,.2,"bomb")
	p.invulnerable=0;p.hp=3
	game._tick_threats(.5)
	check(p.hp==3,"Hazard telegraph is harmless")
	p.height=70
	game._tick_threats(.55)
	check(p.hp==3,"Jump clears an active ground hazard")
	p.height=0
	game.clear_threats()
	game.ground_warning(p.position,Vector2(60,35),.01,.2,"head")
	game._tick_threats(.02)
	check(p.hp==2 and p.effects.has("confused"),"Detached HEAD applies damage and temporary inversion")
	game.clear_threats()
	var saved_clock=game.elapsed
	var saved_effect=p.effects.confused
	game.state="paused";game.playing=false;paused=true
	game._physics_process(2)
	await frames(4)
	check(game.elapsed==saved_clock and p.effects.confused==saved_effect,"Pause freezes clocks and statuses")
	game.resume()
	check(not paused and game.playing,"Resume restores play without resetting stage")
	game.score=345;game.checkpoint_score=200
	game.start_stage(2)
	await frames(2);freeze();game.begin_play();clear_enemies()
	game.enter_room(2);freeze()
	p=game.player
	var boss=game.boss
	check(game.music.stream is AudioStreamMP3 and game.music.stream.loop,"Boss music has an independent looping stream")
	boss.vulnerable=false
	boss.take_hit(4,0,p.position,true)
	check(boss.hp==24,"Boss rejects damage outside recovery")
	boss.vulnerable=true
	boss.take_hit(1,0,Vector2.ZERO,false)
	check(boss.hp==24,"Boss opening requires a finisher")
	# Exercise the actual swing path, not just the boss's direct damage method.
	var nearby_enemy=enemy("syntax_error_sprite",boss.position)
	p.combo=3;p.attack_weapon="";p.weapon=""
	for facing in [1.0,-1.0]:
		p.facing=facing
		p.position=boss.position-Vector2(175*facing,85)
		p.swing_serial+=1
		var before_hp: float=boss.hp
		game.resolve_swing(p);game.resolve_swing(p)
		check(boss.hp==before_hp-2,"Exposed core accepts an off-center finisher once, facing %s" % facing)
	check(nearby_enemy.hp==2,"Core forgiveness does not enlarge ordinary enemy hit areas")
	check(boss.melee_reaches(Vector2(180,90),1,110,46),"Expanded core includes the intended reach/depth boundary")
	check(not boss.melee_reaches(Vector2(181,0),1,110,46) and not boss.melee_reaches(Vector2(0,91),1,110,46),"Expanded core still rejects attacks outside its bounds")
	check(not boss.melee_reaches(Vector2(-65,0),1,110,46),"Core forgiveness does not allow attacks facing away")
	boss.vulnerable=false
	check(not boss.melee_reaches(Vector2(175,85),1,110,46),"Extra reach/depth applies only while the core is exposed")
	p.swing_serial+=1
	var closed_hp: float=boss.hp
	game.resolve_swing(p)
	check(boss.hp==closed_hp,"Off-center attack cannot damage a closed core")
	clear_enemies()
	boss.hp=24;boss.vulnerable=true
	boss.take_hit(12,0,Vector2.ZERO,true)
	check(boss.phase==2 and boss.transition_count==1,"Boss switches to split phase at 50 percent")
	boss.vulnerable=true;boss.take_hit(6,0,Vector2.ZERO,true)
	check(boss.phase==3 and boss.transition_count==2,"Boss enters chaos at 25 percent")
	boss.vulnerable=true;boss.take_hit(6,0,Vector2.ZERO,true)
	check(game.state=="finisher" and game.bullets.is_empty() and game.warnings.is_empty(),"Boss defeat cancels threats and begins Force Merge")
	game._physics_process(4.1)
	game._physics_process(4.1)
	check(game.state=="won" and game.completion_count==1,"Force Merge completes once")
	game.retry_stage()
	await frames(2);freeze()
	check(game.stage_index==2 and game.room==0 and game.player.hp==3 and game.player.weapon=="" and game.score==200,"Retry restores current-stage checkpoint and fresh player state")
	check(game.bullets.is_empty() and game.warnings.is_empty() and game.player.effects.is_empty(),"Retry clears threats and temporary effects")
	check(game.screen_fx.material.get_shader_parameter("phase")==0.0 and game.camera.offset==Vector2.ZERO,"Retry clears boss screen effects and camera shake")
	check(Catalog.MUSIC[0].resource_path.ends_with("Zodik - Future Travel.ogg") and Catalog.MUSIC[1].resource_path.ends_with("helldrake(extended).ogg") and Catalog.MUSIC[2].resource_path.ends_with("kim_lightyear_-_angel_eyes_vision_ii.mp3") and Catalog.BOSS_MUSIC.resource_path.ends_with("Kim Lightyear - The Final.mp3"),"All four user music mappings match")
	# Code-made bindings must answer every pad, not only device 0 (booths, reconnects).
	for binding in [["brawl_jump",0],["brawl_attack",2],["brawl_pickup",3]]:
		for device in [0,1,3]:
			var pad := InputEventJoypadButton.new();pad.device=device;pad.button_index=binding[1];pad.pressed=true
			check(InputMap.event_is_action(pad,binding[0]),"%s answers pad %d" % [binding[0],device])
	print("Code City logic failures: ",failures)
	game.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(.4).timeout
	quit(1 if failures else 0)
