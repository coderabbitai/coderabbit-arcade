extends SceneTree
const Catalog = preload("res://modes/beatem_up/catalog.gd")
var game
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	game.world.reset_physics_interpolation()
	game.camera.reset_physics_interpolation()
	game.camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://../docs/previews/code-city-motion")
	root.get_texture().get_image().save_png("res://../docs/previews/code-city-motion/"+name+".png")
func run() -> void:
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await process_frame;await process_frame
	game=current_scene
	game.test_mode=true
	game.begin_play()
	game.set_physics_process(false)
	var p=game.player
	p.set_physics_process(false);p.controlled=false
	for e in game.enemies: e.queue_free()
	game.enemies.clear()
	for prop in game.props: prop.node.queue_free()
	game.props.clear()
	for item in game.pickups: item.node.queue_free()
	game.pickups.clear()
	var players: Array=[]
	var i:=0
	for weapon in Catalog.WEAPONS:
		var actor=p if i==0 else game.Player.new()
		if i>0:
			actor.arena=game;game.actors.add_child(actor)
		actor.set_physics_process(false);actor.controlled=false
		actor.position=Vector2(120+i*185,565)
		actor.equip(weapon);actor.pickup_time=0
		actor.tick(.01)
		var ready_position: Vector2=actor.held.sprite.position
		actor.start_attack();actor.swing_left=actor.swing_duration*.56;actor.swing_fired=true;actor.tick(0)
		check(actor.combo==1 and actor.held.sprite.position.distance_to(ready_position)>8,weapon+" animates from guard to contact")
		if weapon=="api_key_whip": check(actor.held.sprite.animation=="api_key_whip_extended","Whip uses its extended contact cel")
		for step in [2,3]:
			actor.swing_left=0;actor.combo_window=.4;actor.start_attack()
			check(actor.combo==step,weapon+" chains step "+str(step))
		actor.facing=-1;actor.tick(0)
		check(actor.held.scale.x==-1,weapon+" mirrors around the hand when facing left")
		actor.facing=1
		players.append(actor)
		var label := Label.new()
		label.text=weapon.replace("_"," ");label.position=Vector2(-75,20)
		actor.add_child(label)
		i+=1
	# Capture real character/weapon rigs at synchronized contact, windup and recovery.
	game.toast("EQUIPPED WEAPON ANIMATION · windup / contact / recovery",99)
	for phase in [0.25,0.44,0.7]:
		for actor in players:
			actor.swing_left=actor.swing_duration*(1-phase)
			actor.swing_fired=true
			actor.tick(0)
		await capture("weapons_%02d" % int(phase*100))
	p.invulnerable=0;p.swing_left=.2;p.take_hit(p.position-Vector2(30,0));p.tick(.01)
	check(p.swing_left==0 and p.held.trail.points.is_empty(),"Damage cancels the swing trail and returns weapon to carry")
	var shield=players[4]
	shield.invulnerable=0;shield.swing_left=0;shield.take_hit(shield.position-Vector2(30,0));shield.tick(.1)
	check(shield.hp==3 and shield.block_time>0 and shield.held.sprite.rotation<0,"Shield block recoils without damaging Hoppy")
	for actor in players:
		if actor!=p: actor.queue_free()
	game.start_stage(2)
	await process_frame;await process_frame
	game.begin_play();game.set_physics_process(false)
	p=game.player;p.set_physics_process(false);p.controlled=false
	for e in game.enemies: e.queue_free()
	game.enemies.clear()
	game.enter_room(2)
	var boss=game.boss;boss.set_physics_process(false)
	p.position=Vector2(game.room_start()+500,580)
	game.camera.position=Vector2(game.room_start()+640,360)
	var original: Vector2=boss.position
	boss.tick(.5)
	check(boss.position.distance_to(original)>60,"Phase 1 advances toward Hoppy before attacking")
	boss.cycle=1;boss.telegraph()
	var committed: Vector2=boss.destination
	check(game.warnings.back().left>boss.timer+0.6,"Landing warning includes the leap travel time")
	p.position.x-=220
	boss.tick(.96);boss.tick(.3)
	check(boss.position.distance_to(original)>100 and boss.body.position.y < -70,"Slam travels across the ground with visible airborne height")
	check(boss.destination==committed,"Leap does not retarget after its warning")
	game._update_hud()
	await capture("boss_leap")
	boss.tick(.36)
	check(boss.state=="recover" and boss.vulnerable and boss.position.is_equal_approx(committed),"Landing exposes the core at the committed destination")
	var landing: Vector2=boss.position
	boss.tick(.5)
	check(boss.position==landing,"Recovery gives Hoppy a stationary punish window")
	for phase in [2,3]:
		boss.position=Vector2(game.room_start()+900,560)
		p.position=Vector2(game.room_start()+500,560)
		boss.phase=phase
		boss.body.sprite_frames=game.Art.frames("split_screen" if phase==2 else "merge_chaos")
		boss.begin_reposition()
		var from: Vector2=boss.position
		boss.tick(.5)
		check(boss.position.distance_to(from)>150,"Phase %d actively flanks between attacks" % phase)
		check(boss.position==boss.arena_point(boss.position),"Boss movement stays within the arena")
	# Both Phase 3 attacks must advertise their entire punish window.
	for attack in ["clone","storm"]:
		boss.phase=3;boss.move=attack;boss.state="active";boss.timer=.01
		boss.destination=boss.position;boss.leaping=false
		boss.tick(.02)
		check(boss.vulnerable and boss.body.animation=="hurt" and boss.core_cue.visible,attack+" recovery immediately displays the exposed-core animation")
		var recovery_pos: Vector2=boss.position
		var first_scale: Vector2=boss.body.scale
		boss.tick(.2)
		check(boss.body.scale!=first_scale and boss.position==recovery_pos,"Core breathes while boss stays stationary")
		check(boss.core_cue.remaining<1 and boss.core_cue.remaining>.8,"Core ring counts down the damage window")
		if attack=="storm":
			var saved_timer: float=boss.timer
			var saved_pulse: float=boss.core_cue.elapsed
			boss.set_physics_process(true)
			paused=true
			for frame in 3: await physics_frame
			check(boss.timer==saved_timer and boss.core_cue.elapsed==saved_pulse,"Pause freezes recovery and the visual countdown together")
			boss.set_physics_process(false)
			paused=false
			game._update_hud()
			await capture("boss_phase3_exposed")
		boss.tick(1.85)
		check(boss.vulnerable and boss.core_cue.visible and boss.body.animation=="hurt","Exposure cue persists to the end of recovery")
		boss.tick(.06)
		check(not boss.vulnerable and not boss.core_cue.visible and boss.body.animation=="idle","Exposure cue clears when the boss resumes moving")
	boss.phase=1;boss.hp=24;boss.vulnerable=true
	boss.take_hit(12,0,p.position,true)
	var transition_pos: Vector2=boss.position
	boss.tick(.2)
	check(boss.position==transition_pos and not boss.leaping and boss.body.position==Vector2.ZERO,"Phase transition cancels travel and aerial offsets")
	boss.phase=3;boss.state="recover";boss.timer=1;boss.vulnerable=true
	boss.body.sprite_frames=game.Art.frames("merge_chaos")
	boss.tick(0)
	check(boss.core_cue.visible,"Final strike begins with the core visibly exposed")
	boss.take_hit(24,0,p.position,true)
	boss.tick(.5)
	check(boss.position==transition_pos and not boss.leaping and not boss.core_cue.visible,"Defeat clears movement and the exposed-core cue")
	print("Code City motion failures: ",failures)
	game.queue_free()
	root.get_node("AudioService").shutdown()
	await create_timer(.4).timeout
	quit(1 if failures else 0)
