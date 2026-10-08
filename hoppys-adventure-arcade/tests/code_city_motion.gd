extends SceneTree
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Art = preload("res://modes/beatem_up/art.gd")
const COMBAT_FRAMES = preload("res://Assets/code-city-brawl-player/combat.tres")
const PLATFORMER_FRAMES = preload("res://Assets/bay-area-blitz-assets-only/bay_area/hoppy/platformer.tres")
var game
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func phase_frame(phase: float) -> int:
	return 0 if phase < .3 else 1 if phase < .64 else 2
func opaque_width(frames: SpriteFrames, clip: String, index: int) -> float:
	return frames.get_frame_texture(clip, index).get_image().get_used_rect().size.x
## A swing that misses, or lands on one enemy placed inside reach. The burst is the last child of actors.
func swing_effect(actor, facing: float, landed: bool) -> void:
	actor.facing = facing
	actor.swing_left = 0
	actor.combo_window = 0
	actor.queued = false
	actor.held.show()
	var foe = null
	if landed:
		foe = game.spawn_enemy("syntax_error_sprite", actor.position + Vector2(facing * 60, 0), false)
		foe.set_physics_process(false)
	actor.start_attack()
	game.resolve_swing(actor)
	var fx := game.actors.get_child(game.actors.get_child_count() - 1) as AnimatedSprite2D
	# Misses always use melee_sweep. A hammer hit uses hammer_impact. Both leave the tip.
	var pose := "hammer_impact" if landed and actor.attack_weapon == "refactor_hammer" else "melee_sweep"
	var kind := "hit" if landed else "miss"
	check(fx != null and fx.animation == pose and fx.flip_h == (facing > 0) and fx.position.is_equal_approx(actor.tip_position()), actor.weapon + " " + kind + " " + pose + " anchors at the tip facing " + str(facing))
	if foe != null:
		game.enemies.erase(foe)
		foe.position = Vector2(-10000, -10000)
		foe.queue_free()
	if fx != null: fx.queue_free()
	for item in game.pickups:
		if is_instance_valid(item.node): item.node.queue_free()
	game.pickups.clear()
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
		var sheet = Art.armed(weapon)
		var ready_position: Vector2=actor.held.sprite.position
		if sheet != null:
			check(actor.body.sprite_frames==sheet and actor.body.animation=="hold_idle",weapon+" holds idle on its armed sheet")
			check(not actor.held.sprite.visible,weapon+" hides the legacy cel while armed")
		actor.start_attack();actor.swing_left=actor.swing_duration*.56;actor.swing_fired=true;actor.tick(0)
		if sheet != null:
			check(actor.combo==1 and actor.body.animation=="step1" and actor.body.frame==1,weapon+" contact plays step1 frame 1")
			check(not actor.held.sprite.visible and actor.body.position.x==0,weapon+" keeps the legacy cel hidden and the feet planted")
			var contact_trail: bool = weapon != "firewall_shield"
			check((not actor.held.trail.points.is_empty())==contact_trail,weapon+" trail follows the armed contact window")
		else:
			check(actor.combo==1 and actor.held.sprite.position.distance_to(ready_position)>8,weapon+" animates from guard to contact")
			if weapon=="api_key_whip": check(actor.held.sprite.animation=="api_key_whip_extended","Whip uses its extended contact cel")
		for step in [2,3]:
			actor.swing_left=0;actor.combo_window=.4;actor.start_attack()
			check(actor.combo==step,weapon+" chains step "+str(step))
			if sheet != null: check(actor.body.animation=="step%d"%step,weapon+" plays step "+str(step))
		actor.facing=-1;actor.tick(0)
		check(is_equal_approx(actor.held.scale.x,actor.facing),weapon+" mirrors around the hand when facing left")
		if sheet != null:
			check(actor.body.flip_h and is_equal_approx(actor.body.offset.x,-Art.armed_offset(weapon).x),weapon+" flips the armed pivot when facing left")
		actor.facing=1;actor.tick(0)
		check(is_equal_approx(actor.held.scale.x,actor.facing),weapon+" keeps the rig scale facing right")
		if sheet != null:
			check(not actor.body.flip_h and is_equal_approx(actor.body.offset.x,Art.armed_offset(weapon).x),weapon+" uses the armed pivot when facing right")
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
			var sheet = Art.armed(actor.weapon)
			if sheet == null: continue
			var frame := phase_frame(phase)
			check(actor.body.sprite_frames==sheet and actor.body.animation=="step%d"%actor.combo and actor.body.frame==frame,actor.weapon+" step frame "+str(frame)+" at "+str(phase))
			check(actor.body.position.x==0 and not actor.held.sprite.visible,actor.weapon+" stays planted with the legacy cel hidden at "+str(phase))
			var contact: bool = phase >= .3 and phase < .64 and actor.weapon != "firewall_shield"
			check((not actor.held.trail.points.is_empty())==contact,actor.weapon+" trail at "+str(phase))
		await capture("weapons_%02d" % int(phase*100))
	# Forced cache miss: still the legacy rig after every weapon has a sheet.
	var fallback=game.Player.new()
	fallback.arena=game;game.actors.add_child(fallback)
	fallback.set_physics_process(false);fallback.controlled=false
	fallback.position=Vector2(-500,565)
	Art.armed_sheets["debug_stick"]=null
	fallback.equip("debug_stick");fallback.pickup_time=0;fallback.tick(.01)
	var guard_position: Vector2=fallback.held.sprite.position
	fallback.start_attack();fallback.swing_left=fallback.swing_duration*.56;fallback.swing_fired=true;fallback.tick(0)
	check(fallback.held.sprite.visible and fallback.held.sprite.position.distance_to(guard_position)>8,"Fallback debug stick animates from guard to contact")
	check(fallback.body.sprite_frames==COMBAT_FRAMES and not fallback.armed,"Fallback debug stick uses the unarmed combat frames")
	Art.armed_sheets.erase("debug_stick")
	fallback.queue_free()
	var carrier=null
	for actor in players:
		if Art.armed(actor.weapon)!=null:
			carrier=actor
			break
	if carrier!=null:
		for pose in ["walk_up","walk_down","jump"]:
			carrier.show_pose(pose)
			carrier.held.animate(carrier.weapon,1,0.0,false,Vector2.ZERO,0.0,0.0)
			var behind: bool=pose=="walk_up"
			check(carrier.held.carry.visible and not carrier.held.sprite.visible and carrier.held.carry.scale==carrier.body.scale and (carrier.held.get_index()<carrier.body.get_index())==behind,carrier.weapon+" carry on "+pose+(" sits behind the body" if behind else " sits in front of the body"))
	p.invulnerable=0;p.swing_left=p.swing_duration*.56;p.swing_fired=true;p.tick(0)
	if Art.armed(p.weapon)!=null and p.weapon!="firewall_shield":
		check(not p.held.trail.points.is_empty(),p.weapon+" draws a contact trail before the hit")
	p.take_hit(p.position-Vector2(30,0));p.tick(.01)
	check(p.swing_left==0 and p.held.trail.points.is_empty(),"Damage cancels the swing trail and returns weapon to carry")
	if Art.armed(p.weapon)!=null: check(p.body.animation=="hurt","Damage leaves the armed step clip for hurt")
	var shield=players.filter(func(a): return a.weapon=="firewall_shield")[0]
	shield.invulnerable=0;shield.swing_left=0;shield.tick(0)
	if Art.armed("firewall_shield")!=null:
		shield.take_hit(shield.position-Vector2(30,0));shield.tick(.1)
		check(shield.hp==3 and shield.block_time>0 and shield.body.animation=="hurt","Shield block plays hurt without damaging Hoppy")
	else:
		var guard_rotation: float=shield.held.sprite.rotation
		var guard_x: float=shield.held.sprite.position.x
		shield.take_hit(shield.position-Vector2(30,0));shield.tick(.1)
		check(shield.hp==3 and shield.block_time>0 and shield.held.sprite.rotation<guard_rotation-.1 and shield.held.sprite.position.x<guard_x-4,"Shield block recoils without damaging Hoppy")
	var whip=Art.armed("api_key_whip")
	if whip!=null:
		var contact_width:=opaque_width(whip,"step2",1)
		var widest:=contact_width
		for frame_index in whip.get_frame_count("step2"):
			widest=maxf(widest,opaque_width(whip,"step2",frame_index))
		check(whip.get_frame_count("step2")>1 and contact_width==widest,"Whip contact frame is the widest step2 frame")
	# Shield swings clear attack_weapon, so a landed burst anchors on the enemy. Misses still leave the tip.
	for weapon in Catalog.WEAPONS:
		if Art.armed(weapon)==null: continue
		p.held.show();p.equip(weapon);p.pickup_time=0;p.hp=3;p.position=Vector2(400,560)
		for facing in [1.0,-1.0]:
			swing_effect(p,facing,false)
		if weapon=="firewall_shield": continue
		p.equip(weapon);p.pickup_time=0
		for facing in [1.0,-1.0]:
			swing_effect(p,facing,true)
	var sheet_weapon:=""
	for weapon in Catalog.WEAPONS:
		if Art.armed(weapon)!=null:
			sheet_weapon=weapon
			break
	if sheet_weapon!="":
		p.held.show();p.equip(sheet_weapon);p.pickup_time=0;p.swing_left=0;p.stagger=0;p.facing=1
		p.show_pose("run",true)
		check(p.body.sprite_frames==Art.armed(sheet_weapon) and p.body.animation=="run" and not p.held.sprite.visible and not p.held.carry.visible,"Stage run plays the armed clip without carry or legacy overlays")
		p.held.hide();p.show_pose("run",true)
		check(p.armed_sheet()==null and not p.armed and p.body.sprite_frames==PLATFORMER_FRAMES and p.body.animation=="run","Hiding the weapon returns the finisher to the unarmed platformer frames")
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
