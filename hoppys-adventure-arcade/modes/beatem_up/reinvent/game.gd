extends Node2D
const Art = preload("res://modes/beatem_up/reinvent/art.gd")
const Catalog = preload("res://modes/beatem_up/reinvent/catalog.gd")
const Player = preload("res://modes/beatem_up/reinvent/player.gd")
const Enemy = preload("res://modes/beatem_up/reinvent/enemy.gd")
const Boss = preload("res://modes/beatem_up/reinvent/boss.gd")
const StageFlow = preload("res://modes/beatem_up/stage_flow.gd")
const Knockout = preload("res://modes/beatem_up/knockout.gd")
const Style = preload("res://scenes/main_menu/menu_style.gd")
const PAUSABLE := ["combat","cards","boss_victory","stage_enter","stage_exit","knockout"]
const TERMINAL_OVERLAY_ARM := .5
const CARD_HINT := "Enter / View · Skip     Esc / Start · Pause"
var rng := RandomNumberGenerator.new()
var stage_index := 0
var room := 0
var score := 0
var checkpoint_score := 0
var elapsed := 0.0
var playing := false
var state := "intro"
var gate_open := false
var gate: AnimatedSprite2D
var world: Node2D
var ground: Node2D
var actors: Node2D
var player: CharacterBody2D
var boss: Node2D
var camera: Camera2D
var enemies: Array = []
var props: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var warnings: Array[Dictionary] = []
var allies: Array[Dictionary] = []
var ally_clock := 10.0
var hazard_clock := 4.0
var shake := 0.0
var music: AudioStreamPlayer
var flow: StageFlow
## The last-life knockout between the fatal hit and game_over().
var ko := Knockout.new(Catalog.KNOCKOUT)
var sound_pool: Array[AudioStreamPlayer2D] = []
var sound_index := 0
var hud: Label
var objective: Label
var boss_bar: ProgressBar
var boss_text: Label
var toast_label: Label
var toast_left := 0.0
## A toast raised while the stage title banner fades into combat waits for it, so the two never stack.
var held_toast := ""
var held_toast_seconds := 2.0
var ui_layer: CanvasLayer
var prompt: Label
var overlay: ColorRect
var panel: VBoxContainer
var primary: Button
var terminal_overlay_clock := TERMINAL_OVERLAY_ARM
var screen_fx: ColorRect
var completion_count := 0
var test_mode := false
var capabilities := {"review":false,"triage":false,"change_stack":false,"security":false}
var checkpoint_capabilities: Dictionary = capabilities.duplicate()
var bosses: Array = []
var army_merged := false
var boss_rewarded := false
var victory_clock := 0.0
const VICTORY_DURATION := 1.2
var reveal_time := 0.0
var surge_cooldown := 0.0
var zones: Array[Dictionary] = []
var triage_target: Node2D
var hammer_target: Node2D
var card_host: Control
var card: Control
var card_queue: Array[String] = []
var card_callback: Callable
var card_clock := 0.0
var card_progress: ProgressBar
var capability_hud: Label
var second_boss_bar: ProgressBar
var second_boss_text: Label
var pause_return_state := "combat"
var leaving := false
var last_swing_processed := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Catalog.install_input()
	rng.randomize()
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(world)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(640,360)
	add_child(camera)
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	music.volume_db = -13
	music.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(music)
	AudioService.music.stop()
	for i in 10:
		var voice := AudioStreamPlayer2D.new()
		voice.bus = "SFX"
		voice.volume_db = -13
		voice.max_distance = 2200
		voice.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(voice)
		sound_pool.append(voice)
	_build_ui()
	flow = StageFlow.new()
	add_child(flow)
	flow.setup(ui_layer,music,Catalog.FLOW)
	flow.phase_changed.connect(_on_flow_phase)
	start_stage(0,true)

func room_start() -> float: return room*1280.0
func clamp_ground(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x,room_start()+55,room_start()+(1270 if gate_open else 1150)),clampf(pos.y,455,650))

func start_stage(index: int, cinematic := false) -> void:
	ko.cancel()
	playing=false
	get_tree().paused=false
	for child in world.get_children(): child.queue_free()
	enemies.clear();props.clear();pickups.clear();bullets.clear();warnings.clear();allies.clear();zones.clear();bosses.clear()
	boss=null;triage_target=null;hammer_target=null
	stage_index=index;room=0;gate_open=false
	boss_rewarded=false;army_merged=false;victory_clock=0
	reveal_time=0;surge_cooldown=0;last_swing_processed=-1;shake=0
	camera.offset=Vector2.ZERO
	screen_fx.material.set_shader_parameter("phase",0.0)
	ground=Node2D.new();world.add_child(ground)
	actors=Node2D.new();actors.y_sort_enabled=true;world.add_child(actors)
	for i in 3:
		var bg := Sprite2D.new()
		bg.texture=load(Art.BASE+Catalog.THEMES[index]+".png")
		bg.centered=false;bg.position.x=i*1280
		ground.add_child(bg)
		var decor := Art.sprite(Catalog.KITS[index],["expo_truss","gantry","cables"][index],1.2,false)
		decor.position=Vector2(i*1280+125,230)
		ground.add_child(decor)
	player=Player.new();player.arena=self;player.position=Vector2(Catalog.FLOW.enter_from_x,580)
	actors.add_child(player)
	player.shield=capabilities.review
	camera.position=Vector2(640,360)
	camera.reset_physics_interpolation()
	flow.play_music(Catalog.looped(Catalog.MUSIC[index]),Catalog.MUSIC[index])
	enter_room(0)
	# enter_room clamps new arrivals to the room boundary. The director owns the actual entrance.
	player.position.x=Catalog.FLOW.enter_from_x
	if cinematic:
		show_cards(["opening_situation","opening_complication","opening_resolution"],enter_stage)
	else: enter_stage()
	_update_hud()

## stage_enter: Hoppy runs in under the title banner, then begin_play() on flow completion.
func enter_stage() -> void:
	overlay.hide()
	playing=false
	state="stage_enter"
	toast_left=0;held_toast="";toast_label.hide();prompt.text=""
	flow.play_enter("%02d / %s" % [stage_index+1,Catalog.TITLES[stage_index]],Catalog.STORIES[stage_index])

## stage_exit: unlock cards are gone, so Hoppy runs out while the capability banner remains visible.
func exit_stage() -> void:
	playing=false
	state="stage_exit"
	prompt.text="";toast_left=0;held_toast="";toast_label.hide()
	flow.banner("CAPABILITY DEPLOYED","Stage score saved · Next: "+Catalog.TITLES[stage_index+1],Catalog.FLOW.exit_banner)
	flow.play_exit(advance_stage)

func _on_flow_phase(phase: String) -> void:
	if phase=="" and state=="stage_enter": begin_play()

func enter_room(index: int) -> void:
	clear_threats()
	for item in pickups: item.node.queue_free()
	pickups.clear()
	for prop in props: prop.node.queue_free()
	props.clear()
	for ally in allies: ally.node.queue_free()
	allies.clear()
	for e in enemies:
		if is_instance_valid(e): e.queue_free()
	enemies.clear()
	room=index;gate_open=false;hazard_clock=4;ally_clock=9
	player.position=Vector2(maxf(player.position.x,room_start()+70),player.position.y)
	if is_instance_valid(gate): gate.queue_free()
	gate=Art.sprite("generation_kit","barrier",1.25,false)
	gate.position=Vector2(room_start()+1210,560)
	ground.add_child(gate)
	var wave: Array=Catalog.WAVES[stage_index][room]
	for i in wave.size(): spawn_enemy(wave[i],Vector2(room_start()+620+(i%4)*120,480+(i%3)*68))
	spawn_prop(Catalog.PROPS[stage_index][0],Vector2(room_start()+375,482),0)
	spawn_prop(Catalog.PROPS[stage_index][1],Vector2(room_start()+960,628),1)
	drop(["review_stamp","change_stack_baton","security_scanner"][stage_index],Vector2(room_start()+230,595))
	if room==2:
		flow.swap_music(Catalog.looped(Catalog.BOSS_MUSIC[stage_index]),Catalog.FLOW.boss_dip,Catalog.BOSS_MUSIC[stage_index])
		match stage_index:
			0: spawn_boss("ai_slop",Vector2(room_start()+945,565))
			1:
				for i in 3: spawn_boss("agent_army",Vector2(room_start()+850+(i%2)*160,480+i*70))
			2: spawn_boss("ai_augmented_hacker",Vector2(room_start()+950,550))
		show_cards([["boss_ai_slop"],["boss_agent_army"],["boss_ai_augmented_hacker"]][stage_index],begin_play)
	else: toast("ENCOUNTER %d / 3 — clear the blockers" % (room+1),2)

func spawn_enemy(kind: String, pos: Vector2, split := true) -> Node2D:
	# Two reserved slots allow a full encounter's original clone to split safely.
	enemies=enemies.filter(func(e): return is_instance_valid(e))
	if living_enemies()>=(12 if split else 14): return null
	var enemy := Enemy.new()
	enemy.arena=self;enemy.kind=kind;enemy.position=clamp_ground(pos);enemy.can_split=split
	actors.add_child(enemy)
	enemies.append(enemy)
	return enemy

func living_enemies() -> int:
	var count := 0
	for e in enemies:
		if is_instance_valid(e) and not e.dead: count += 1
	return count

func enemy_defeated(enemy: Node2D) -> void:
	score+=100
	if rng.randf()<.15: drop("health_capsule" if player.hp<3 else "score_coin",enemy.position)

func resolve_swing(source: Node2D) -> void:
	if not playing or source.hp<=0 or source.swing_serial==last_swing_processed: return
	last_swing_processed=source.swing_serial
	var weapon: String=source.attack_weapon
	var def: Dictionary=Catalog.WEAPONS[weapon] if weapon!="" else {"damage":2.0 if source.combo==3 else 1.0,"reach":125.0 if source.combo==3 else 108.0,"depth":50.0,"knock":260.0 if source.combo==3 else 80.0}
	var damage: float=def.damage
	if source.effects.has("strength_down"): damage=maxf(.5,damage-1.0)
	var hit := false
	var tip := source.position+Vector2(source.facing*70,-50)
	if source.has_method("swing_tip"): tip=source.swing_tip()
	if weapon=="security_scanner":
		reveal_time=10
		hit=true # A scan consumes one charge even without a target in the cone.
		fx("capabilities_fx","scanner_cone",source.position+Vector2(source.facing*100,-50),1.3,.4,source.facing)
	var targets: Array=enemies.duplicate()+bosses.duplicate()
	var zone_points: Array[Vector2]=[]
	for enemy in targets:
		if not is_instance_valid(enemy) or enemy.dead: continue
		var offset: Vector2=enemy.position-source.position
		var reach: float=def.reach+(65 if enemy.is_boss else 0)
		if not melee_contains(offset,source.facing,reach,def.depth): continue
		var amount := damage
		if enemy==triage_target or enemy==hammer_target: amount+=1
		if weapon=="security_scanner" and (enemy.kind in ["ai_hacker_drone","vulnerability_injector","zero_day_phantom","security_gap_crawler","ai_augmented_hacker"]): amount+=1
		if weapon=="change_stack_baton" and enemy.kind=="agent_spawner": amount=99
		if weapon=="pr_merger" and not enemy.is_boss and enemy.hp<enemy.max_hp*.25: amount=999
		if enemy.take_hit(amount,def.knock,source.position,source.combo==3):
			hit=true
			fx("capabilities_fx","unlock_sparkle",enemy.position-Vector2(0,55),.5,.18,source.facing)
			if weapon=="review_stamp": enemy.stun(.5)
			if weapon=="triage_hammer": hammer_target=enemy
			if source.combo==3 and capabilities.change_stack: zone_points.append(clamp_ground(enemy.position+Vector2(source.facing*65,0)))
			if weapon=="triage_hammer": break
	for prop in props:
		if weapon=="triage_hammer" and hit: break
		if prop.hp<=0: continue
		if melee_contains(prop.node.position-source.position,source.facing,def.reach,def.depth):
			prop.hp-=damage;hit=true
			prop.sprite.play(prop.kind+"_cracked")
			if prop.hp<=0: break_prop(prop)
			if weapon=="triage_hammer": break
	for pos in zone_points: create_zone(pos)
	if hit:
		shake=6 if source.combo==3 else 3
		if weapon=="pr_merger":
			for target in bosses:
				if is_instance_valid(target) and not target.dead: target.stun(.8)
		if weapon!="" and source.weapon==weapon: source.spend_weapon()
	else:
		fx("capabilities_fx","unlock_sparkle",tip,.5,.18,source.facing)

static func melee_contains(offset: Vector2, facing: float, reach: float, depth: float) -> bool:
	return offset.x*facing >= -20 and offset.x*facing <= reach and absf(offset.y) <= depth

func spawn_prop(kind: String, pos: Vector2, slot: int) -> void:
	var node := Node2D.new();node.position=pos
	var sprite := Art.sprite(Catalog.KITS[stage_index],kind+"_intact",.8,false)
	sprite.position.y=-54;node.add_child(sprite);actors.add_child(node)
	props.append({"node":node,"sprite":sprite,"kind":kind,"hp":3.0,"slot":slot,"room":room,"spawn_clock":7.0})

func break_prop(prop: Dictionary) -> void:
	prop.hp=0
	prop.sprite.play(prop.kind+"_destroyed")
	score+=50;sound("collapse" if prop.kind=="monolith" else "break",prop.node.position)
	var reward := "health_capsule"
	match prop.kind:
		"terminal": reward="health_capsule" if player.hp<3 else "triage_hammer"
		"kiosk": reward="review_stamp" if room==0 else "random_buff"
		"monolith":
			reward="score_coin"
			for enemy in enemies.duplicate():
				if is_instance_valid(enemy) and not enemy.dead: enemy.take_hit(3,200,prop.node.position,true)
			for target in bosses:
				if is_instance_valid(target) and not target.dead: target.take_hit(2,0,prop.node.position,true)
			fx("review_kit","nightmare_wave",prop.node.position,2,.5)
		"assembly":
			reward="speed_surge"
			player.effects.erase("overwhelmed")
			for enemy in enemies:
				if is_instance_valid(enemy) and not enemy.dead and enemy.kind=="agent_spawner" and absf(enemy.position.y-prop.node.position.y)<80: enemy.finish_death()
		"rack": reward="pr_merger" if room==2 else "security_scanner"
		"node":
			reward="score_coin"
			if not warnings.is_empty(): warnings[0].node.queue_free();warnings.remove_at(0)
			elif not bullets.is_empty(): bullets[0].node.queue_free();bullets.remove_at(0)
	drop(reward,prop.node.position+Vector2(15,22))

func drop(kind: String, pos: Vector2) -> void:
	if pickups.size() >= 24: return
	var node := Node2D.new()
	node.position = clamp_ground(pos)
	var sprite := Art.sprite("items_allies",kind,.38,false)
	sprite.position.y = -22
	node.add_child(Art.shadow(17))
	node.add_child(sprite)
	actors.add_child(node)
	pickups.append({"node":node,"sprite":sprite,"kind":kind,"age":0.0})

func pickup_weapon() -> void:
	var closest := -1
	var distance := 85.0
	for i in pickups.size():
		var item: Dictionary = pickups[i]
		if not Catalog.WEAPONS.has(item.kind): continue
		var d: float = item.node.position.distance_to(player.position)
		if d<distance:
			distance = d
			closest = i
	if closest < 0: return
	var item: Dictionary = pickups[closest]
	player.equip(item.kind)
	toast(item.kind.replace("_"," ").to_upper()+" EQUIPPED",1.5)
	item.node.queue_free()
	pickups.remove_at(closest)

func projectile(pos: Vector2, velocity: Vector2, pose := "api_projectile", status := "", tracking := false) -> void:
	if bullets.size()>=32: return
	var node := Node2D.new();node.position=pos
	var sprite := Art.sprite("core_kit" if pose=="injector_projectile" else "capabilities_fx",pose,.35,false)
	sprite.position.y=-42;sprite.flip_h=velocity.x<0
	node.add_child(sprite);actors.add_child(node)
	bullets.append({"node":node,"velocity":velocity,"life":4.0,"status":status,"tracking":tracking,"age":0.0})

func ground_warning(pos: Vector2, radius: Vector2, delay: float, duration: float, kind: String, owner_node: Node = null) -> void:
	if warnings.size()>=12: return
	var marker := Art.sprite("review_kit","slam_warning",1,false)
	marker.position=pos;marker.scale=Vector2(radius.x/90.0,radius.y/30.0)
	ground.add_child(marker)
	warnings.append({"node":marker,"pos":pos,"radius":radius,"left":delay,"active":duration,"kind":kind,"fired":false,"owner":owner_node,"hit":false})

func clear_threats() -> void:
	clear_projectiles()
	for w in warnings: w.node.queue_free()
	warnings.clear()
	for zone in zones: zone.node.queue_free()
	zones.clear()

func fx(sheet: String, pose: String, pos: Vector2, magnify: float, lifetime: float, face := 0.0) -> void:
	var sprite := Art.sprite(sheet,pose,magnify,false)
	sprite.position = pos
	sprite.flip_h = face<0.0
	actors.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite,"modulate:a",0.0,lifetime)
	tween.tween_callback(sprite.queue_free)

func sound(key: String, pos: Vector2) -> void:
	if sound_pool.is_empty(): return
	var voice := sound_pool[sound_index%sound_pool.size()]
	sound_index+=1
	voice.position=pos
	voice.stream=Catalog.CUES[key] if Catalog.CUES.has(key) else Catalog.Shared.SOUNDS.get(key)
	if voice.stream!=null: voice.play()

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player) or state=="leaving": return
	_layout_card()
	if get_tree().paused: return
	# Camera and stage-flow clocks keep running behind a presentation card. In particular, the
	# room-three pan must finish while the boss introduction remains on screen.
	# Toasts count down in every state, so none freezes behind a card, the victory hop or the exit.
	toast_left-=dt
	toast_label.visible=toast_left>0
	flow.tick(dt,player)
	if held_toast!="" and state=="combat" and not flow.banner_active(): toast(held_toast,held_toast_seconds)
	# A fallen villain collapses on this clock: during the fight, the victory hop, cards and exit.
	for target in bosses:
		if is_instance_valid(target) and target.dead: target.defeat_tick(dt)
	camera.position=camera.position.lerp(Vector2(room_start()+640,360),minf(1,dt*5))
	shake=maxf(0,shake-dt*28)
	camera.offset=Vector2(rng.randf_range(-shake,shake),rng.randf_range(-shake,shake))
	var view := get_viewport_rect().size
	camera.zoom=Vector2.ONE*minf(view.x/1280.0,view.y/720.0)
	if state in ["game_over","won"]: terminal_overlay_clock=minf(TERMINAL_OVERLAY_ARM,terminal_overlay_clock+dt)
	if state=="knockout": ko.tick(dt)
	if state=="boss_victory":
		victory_clock=minf(VICTORY_DURATION,victory_clock+dt)
		# A short celebratory hop; the ground position and combat stay frozen.
		player.hop(-18.0*sin(PI*clampf(victory_clock/.7,0,1)))
		if victory_clock>=VICTORY_DURATION:
			player.hop(0)
			show_boss_reward()
		return
	if state=="cards":
		card_clock+=dt
		if is_instance_valid(card):
			# Story scenes play in place on the card clock; the other cards slide in from the right.
			if card.has_method("advance"): card.advance(card_clock,card_hold())
			else: card.position.x=(1.0-clampf(card_clock/.3,0,1))*1280
		if is_instance_valid(card_progress): card_progress.value=maxf(0,1.0-card_clock/card_hold())
		if card_clock>=card_hold(): next_card()
		return
	if not playing: return
	elapsed+=dt;reveal_time=maxf(0,reveal_time-dt);surge_cooldown=maxf(0,surge_cooldown-dt)
	_tick_items(dt);_tick_threats(dt)
	# A fatal hit starts the knockout here, so no ally, toast or zone acts on that frame.
	if not playing: return
	_tick_allies(dt);_tick_capabilities(dt)
	check_boss_state()
	if not playing: return
	if room<2 and not gate_open and living_enemies()==0:
		gate_open=true;gate.hide();clear_threats();toast("BLOCKERS CLEARED — GO RIGHT  →",3)
	if gate_open and player.position.x>room_start()+1205:
		if room<2: enter_room(room+1)
	if not gate_open:
		hazard_clock-=dt
		if hazard_clock<=0: hazard_clock=5.5;stage_hazard()
	for prop in props:
		if prop.kind=="assembly" and prop.hp>0 and room<2 and not gate_open:
			prop.spawn_clock-=dt
			if prop.spawn_clock<=0:
				prop.spawn_clock=7
				spawn_enemy("merge_request_mob",clamp_ground(prop.node.position+Vector2(-60,0)))
	_update_hud()

func _tick_items(dt: float) -> void:
	prompt.text = ""
	for i in range(pickups.size()-1,-1,-1):
		var item: Dictionary = pickups[i]
		item.age += dt
		item.sprite.position.y = -22+sin(item.age*4)*4
		var distance: float = item.node.position.distance_to(player.position)
		if Catalog.WEAPONS.has(item.kind):
			if distance<85: prompt.text = "E / Y · PICK UP "+item.kind.replace("_"," ").to_upper()
		elif distance < 45 and player.height < 20 and player.hp>0:
			player.apply_effect(item.kind)
			sound("pickup",player.position)
			toast(item.kind.replace("_"," ").to_upper(),1.2)
			item.node.queue_free()
			pickups.remove_at(i)

func _tick_threats(dt: float) -> void:
	for i in range(bullets.size()-1,-1,-1):
		var b: Dictionary=bullets[i]
		b.age+=dt
		if b.tracking and b.age<1.25:
			var desired: Vector2=(player.position-b.node.position).normalized()*260
			b.velocity=b.velocity.lerp(desired,minf(1,dt*1.8))
		b.node.position+=b.velocity*dt;b.life-=dt
		var offset: Vector2=b.node.position-player.position
		var contact: bool=absf(offset.x)<30 and absf(offset.y)<26 and player.height<38
		if contact: player.take_hit(b.node.position-b.velocity*.1,b.status)
		if contact or b.life<=0 or absf(b.node.position.x-room_start()-640)>820:
			b.node.queue_free();bullets.remove_at(i)
	for i in range(warnings.size()-1,-1,-1):
		var w: Dictionary=warnings[i]
		w.left-=dt
		if w.left<=0:
			if not w.fired:
				w.fired=true
				w.node.modulate=Color(1,.35,.1,.9)
				match w.kind:
					"code_dump": fx("generation_kit","code_dump",w.pos-Vector2(0,80),1.2,w.active)
					"fog": fx("generation_kit","api_fog",w.pos,.9,w.active)
					"scan": fx("core_kit","scan_beam",w.pos-Vector2(0,28),3,w.active)
					"slam": fx("review_kit","falling_stack",w.pos-Vector2(0,65),1,w.active)
					"nightmare": fx("review_kit","nightmare_wave",w.pos,2,w.active)
				sound("collapse" if w.kind in ["slam","nightmare"] else "kick",w.pos)
			var offset: Vector2=(player.position-w.pos)/w.radius
			if offset.length()<1 and player.height<38 and not w.hit:
				if w.kind=="fog": player.apply_effect("confused");w.hit=true
				else: w.hit=player.take_hit(w.pos-Vector2(1,0))
			if w.left<=-float(w.active): w.node.queue_free();warnings.remove_at(i)

func stage_hazard() -> void:
	if room==2: return
	match stage_index:
		0: ground_warning(player.position,Vector2(90,42),1.15,.5,"code_dump" if rng.randf()<.65 else "fog")
		1:
			ground_warning(player.position,Vector2(105,50),1.1,.4,"slam")
			if count_kind("agent_spawner")>0:
				player.apply_effect("overwhelmed")
				for i in 2: spawn_enemy("merge_request_mob",Vector2(room_start()+1080,490+i*100))
		2: ground_warning(Vector2(room_start()+640,clampf(player.position.y,475,620)),Vector2(590,25),1.15,.35,"scan")

func _tick_allies(dt: float) -> void:
	ally_clock-=dt
	if ally_clock<=0 and allies.is_empty() and not gate_open:
		ally_clock=24
		var id := "lead_engineer" if room==2 or stage_index==0 else "devops_defender" if stage_index==1 else "security_analyst"
		var ally := Art.sprite("items_allies",id+"_strike" if id=="devops_defender" else id+"_gift",.7,false)
		ally.position=Vector2(room_start()+180,470);actors.add_child(ally)
		allies.append({"node":ally,"life":3.0})
		match id:
			"lead_engineer": drop("health_capsule",Vector2(room_start()+230,505));toast("LEAD ENGINEER: ship it!",2)
			"devops_defender":
				for enemy in enemies:
					if is_instance_valid(enemy) and not enemy.dead and enemy.kind=="agent_spawner": enemy.finish_death();break
				drop("speed_surge",Vector2(room_start()+230,505));toast("DEVOPS DEFENDER: pipeline stopped!",2)
			"security_analyst":
				for enemy in enemies:
					if is_instance_valid(enemy) and not enemy.dead and enemy.hidden_enemy: enemy.reveal_left=10;break
				drop("security_scanner",Vector2(room_start()+230,505));toast("SECURITY ANALYST: scan the hidden surface!",2)
	for i in range(allies.size()-1,-1,-1):
		allies[i].life-=dt
		if allies[i].life<=0: allies[i].node.queue_free();allies.remove_at(i)

func begin_play() -> void:
	var entering := state in ["stage_enter"]
	if flow.active(): flow.cancel()
	overlay.hide();card_host.hide()
	state="combat";playing=true
	player.input_lock=.2
	player.review_charge=0
	if entering: toast("ENCOUNTER %d / 3 — clear the blockers" % (room+1),2)

func advance_stage() -> void:
	checkpoint_score=score
	checkpoint_capabilities=capabilities.duplicate()
	start_stage(stage_index+1)

func retry_stage() -> void:
	flow.cancel()
	score=checkpoint_score
	capabilities=checkpoint_capabilities.duplicate()
	start_stage(stage_index)

## The fatal hit: play stops at once (enemies, bullets and hazards freeze), the screen clears of
## toasts and banners, and the knockout plays out before game_over(). Repeats are ignored.
func knockout(source: Vector2) -> void:
	if state in ["knockout","game_over","leaving"]: return
	flow.cancel()
	playing=false;state="knockout"
	toast_left=0;held_toast="";toast_label.hide();prompt.text=""
	flow.banner("","",0)
	_update_hud()
	ko.play(self,source,game_over)

func game_over() -> void:
	if state=="game_over": return
	ko.cancel()
	flow.cancel()
	playing = false
	state = "game_over"
	_update_hud()
	show_overlay("REVIEW FAILED", "Retry %s with 3 HP and fresh equipment." % Catalog.TITLES[stage_index],"Retry current stage",retry_stage)

func boss_defeated() -> void:
	# A knocked-out Hoppy can't win: the knockout ends in game over.
	if boss_rewarded or state=="knockout": return
	if flow.active(): flow.cancel()
	boss_rewarded=true
	playing=false;clear_threats()
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	enemies.clear()
	player.swing_left=0;player.queued=false
	score+=500
	state="boss_victory";victory_clock=0
	player.height=0;player.rise=0;player.velocity=Vector2.ZERO;player.knock=Vector2.ZERO
	player.body.position=Vector2.ZERO;player.body.modulate=Color.WHITE
	player.show_pose("victory")
	player.z_index=2 # Keep the celebration visible in front of defeated bosses.
	shake=0;camera.offset=Vector2.ZERO
	# Toasts tick in every state now, so end this one rather than only hiding the label.
	toast_left=0;held_toast="";toast_label.hide();prompt.text="" # Clear the prompt; a hidden label would never show again.
	sound("win",player.position)
	_update_hud()

func show_boss_reward() -> void:
	match stage_index:
		0:
			capabilities.review=true;player.shield=true
			show_cards(["unlock_review"],exit_stage)
		1:
			capabilities.triage=true;capabilities.change_stack=true
			show_cards(["unlock_triage","unlock_change_stack"],exit_stage)
		2:
			capabilities.security=true
			reveal_time=999
			show_cards(["unlock_security","victory"],win)

func win() -> void:
	if state=="won": return
	playing=false;state="won";completion_count+=1
	_update_hud()
	sound("win",player.position)
	show_overlay("THE CODEBASE IS TRUSTED", "All four capabilities deployed.\nScore: %d   ·   Time: %d:%02d" % [score,int(elapsed)/60,int(elapsed)%60],"Return to Beat'em Up menu",leave)

func toast(message: String, seconds := 2.0) -> void:
	# Combat opens under the fading stage title; anything said then waits for it (latest wins).
	if state=="combat" and flow.banner_active():
		held_toast=message;held_toast_seconds=seconds
		return
	held_toast=""
	toast_label.text = message
	toast_label.show()
	toast_left = seconds

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	ui_layer=layer
	add_child(layer)
	screen_fx = ColorRect.new()
	screen_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://modes/beatem_up/conflict.gdshader")
	screen_fx.material = material
	layer.add_child(screen_fx)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Style.theme()
	layer.add_child(ui)
	var top := ColorRect.new()
	top.color = Color(.035,.025,.025,.94)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 139
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	hud = Style.label("",20)
	hud.position = Vector2(28,16)
	ui.add_child(hud)
	objective = Style.label("",16,Color("ffab54"))
	objective.position = Vector2(28,51)
	ui.add_child(objective)
	boss_text = Style.label("",14,Color("ffc66c"))
	boss_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	boss_text.position = Vector2(-430,16)
	boss_text.size = Vector2(405,22)
	ui.add_child(boss_text)
	boss_bar = ProgressBar.new()
	boss_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	boss_bar.position = Vector2(-430,47)
	boss_bar.size = Vector2(405,15)
	boss_bar.show_percentage = false
	ui.add_child(boss_bar)
	toast_label = Style.label("",22,Color("ffe6a6"))
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_label.offset_top = 145
	toast_label.offset_bottom = 180
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	toast_label.add_theme_constant_override("shadow_offset_x",2)
	toast_label.add_theme_constant_override("shadow_offset_y",2)
	ui.add_child(toast_label)
	prompt = Style.label("",18,Color("ffe6a6"))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -82
	prompt.offset_bottom = -54
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(prompt)
	var controls := Style.label("WASD / stick · Move   Space / A · Jump   J, X / X · Combo   E / Y · Pickup   Hold Q / LB · REVIEW   Esc / Start · Pause",13)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -27
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(controls)
	capability_hud=Style.label("",13,Color("ffab54"))
	capability_hud.position=Vector2(28,94)
	ui.add_child(capability_hud)
	second_boss_text=Style.label("",13,Color("ffc66c"))
	second_boss_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	second_boss_text.position=Vector2(-430,66);second_boss_text.size=Vector2(405,20)
	ui.add_child(second_boss_text)
	second_boss_bar=ProgressBar.new()
	second_boss_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	second_boss_bar.position=Vector2(-430,87);second_boss_bar.size=Vector2(405,12);second_boss_bar.show_percentage=false
	ui.add_child(second_boss_bar)
	for bar in [boss_bar, second_boss_bar]:
		var background := StyleBoxFlat.new()
		background.bg_color=Color("302329")
		var fill := StyleBoxFlat.new()
		fill.bg_color=Color("ff681e")
		bar.add_theme_stylebox_override("background",background)
		bar.add_theme_stylebox_override("fill",fill)
		bar.add_theme_font_size_override("font_size",1)
		bar.size.y=12
	card_host=Control.new()
	card_host.size=Vector2(1280,720)
	card_host.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(card_host)
	card_host.hide()
	overlay = ColorRect.new()
	overlay.color = Color(.025,.04,.065,.91)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(720,0)
	panel.add_theme_constant_override("separation",18)
	center.add_child(panel)

func _update_hud() -> void:
	var health := ""
	for i in 3: health += "♥ " if i<player.hp else "· "
	hud.text="THE CODERABBIT  "+health+"  SCORE %05d" % score
	var weapon: String=player.weapon.replace("_"," ").to_upper()+" [%d]" % player.durability if player.weapon!="" else "JAB → SWING → KICK"
	objective.text="%s · %d/3\n%s" % [Catalog.TITLES[stage_index],room+1,weapon]
	var caps := ""
	for key in capabilities:
		caps += ("● " if capabilities[key] else "○ ")+key.replace("_"," ").to_upper()+"   "
	if capabilities.review: caps += " Q / LB: "+("READY" if player.review_cooldown<=0 else "%ds" % ceili(player.review_cooldown))
	if player.shield: caps += "  SHIELD"
	if not player.effects.is_empty(): caps += "\n"
	for effect in player.effects: caps += "  "+effect.replace("_"," ").to_upper()+" %ds" % ceili(player.effects[effect])
	capability_hud.text=caps
	var live: Array=[]
	for target in bosses:
		if is_instance_valid(target) and not target.dead: live.append(target)
	boss_bar.visible=not live.is_empty();boss_text.visible=boss_bar.visible
	second_boss_bar.visible=live.size()>1 and army_merged
	second_boss_text.visible=second_boss_bar.visible
	if not live.is_empty():
		var target: Node2D=live[0]
		boss_bar.max_value=target.max_hp;boss_bar.value=target.hp
		boss_text.text=Catalog.BOSS_NAMES[target.kind]
		if stage_index!=1: boss_text.text+=" · P%d" % target.phase
		if stage_index==1 and not army_merged:
			boss_bar.max_value=24;boss_bar.value=army_health()
			boss_text.text="AGENT ARMY · %d CLONES" % live.size()
	if second_boss_bar.visible:
		second_boss_bar.max_value=live[1].max_hp;second_boss_bar.value=live[1].hp
		second_boss_text.text=Catalog.BOSS_NAMES[live[1].kind]

func show_overlay(title: String, detail: String, action: String, callback: Callable) -> void:
	terminal_overlay_clock=0.0 if state in ["game_over","won"] else TERMINAL_OVERLAY_ARM
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	var title_label := Style.label(title,30)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title_label)
	var description := Style.label(detail,18)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(720,75)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(description)
	if state != "paused": description.text += "\nEnter / View (Select) · Confirm"
	primary = Style.button(action,58)
	panel.add_child(primary)
	primary.pressed.connect(callback)
	if state != "won":
		var back := Style.button("Return to Beat'em Up menu",54)
		panel.add_child(back)
		back.pressed.connect(leave)
	overlay.show()
	primary.grab_focus()

func _input(event: InputEvent) -> void:
	# Filter before focused buttons receive ui_accept (which includes jump/A).
	if state not in ["game_over","won"] or not overlay.visible: return
	if terminal_overlay_clock<TERMINAL_OVERLAY_ARM:
		if event.is_action_pressed("heroes_popup_advance") or event.is_action("ui_accept") or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("heroes_popup_advance"):
		get_viewport().set_input_as_handled()
		if not event.is_echo():
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button and panel.is_ancestor_of(focused): focused.pressed.emit()
	elif event.is_action("ui_accept"):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if state=="paused": resume()
		elif state in PAUSABLE:
			pause_return_state=state
			playing=false;state="paused";get_tree().paused=true
			show_overlay("REVIEW PAUSED","Chain attacks, sidestep warnings, and hold Q / LB to charge REVIEW.","Resume",resume)
		get_viewport().set_input_as_handled()
	elif state=="cards" and event.is_action_pressed("heroes_popup_advance") and not event.is_echo():
		if card_clock>.25: next_card()
		get_viewport().set_input_as_handled()

func resume() -> void:
	if state!="paused": return
	get_tree().paused=false
	if pause_return_state in ["cards","boss_victory","stage_enter","stage_exit","knockout"]: state=pause_return_state;overlay.hide()
	else: begin_play()

func leave() -> void:
	if leaving: return
	leaving=true;ko.cancel();flow.cancel();playing=false;state="leaving";get_tree().paused=false
	for child in panel.get_children():
		if child is BaseButton: child.disabled=true
	music.stop()
	AppRouter.go("beatem_up")

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and state in PAUSABLE and not test_mode:
		pause_return_state=state
		playing=false;state="paused";get_tree().paused=true
		show_overlay("REVIEW PAUSED","The window lost focus.","Resume",resume)

func _exit_tree() -> void:
	get_tree().paused = false

func spawn_boss(kind: String, pos: Vector2, fused := false) -> Node2D:
	var target := Boss.new()
	target.arena=self;target.kind=kind;target.position=pos;target.fused=fused
	actors.add_child(target)
	bosses.append(target)
	if not is_instance_valid(boss) or boss.dead: boss=target
	return target

func alive_bosses() -> int:
	var count := 0
	for target in bosses:
		if is_instance_valid(target) and not target.dead: count+=1
	return count

func army_health() -> float:
	var health := 0.0
	for target in bosses:
		if is_instance_valid(target) and not target.dead: health+=target.hp
	return health

func count_kind(kind: String) -> int:
	var count := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and enemy.kind==kind: count+=1
	return count

func check_boss_state() -> void:
	if room!=2 or boss_rewarded or bosses.is_empty(): return
	if stage_index==1 and not army_merged and army_health()<=12:
		army_merged=true
		clear_threats()
		for target in bosses:
			if is_instance_valid(target): target.queue_free()
		bosses.clear();boss=null
		spawn_boss("agent_army",Vector2(room_start()+760,510),true)
		var pr: Node2D=spawn_boss("ten_thousand_line_pr",Vector2(room_start()+1010,600))
		pr.pose("drop")
		show_cards(["boss_ten_thousand_line_pr"],begin_play)
		return
	if alive_bosses()==0: boss_defeated()

func player_damaged() -> void:
	if stage_index!=2 or surge_cooldown>0 or not playing: return
	surge_cooldown=2.0
	spawn_enemy("vulnerability_injector",Vector2(room_start()+1080,490 if player.position.y>555 else 620))
	fx("core_kit","surface_portal",Vector2(room_start()+1080,560),.8,.6)
	toast("ATTACK SURFACE SURGE — injector incoming",1.4)

func clear_projectiles() -> void:
	for bullet in bullets: bullet.node.queue_free()
	bullets.clear()

func clear_owned_threats(owner_node: Node) -> void:
	for i in range(warnings.size()-1,-1,-1):
		if warnings[i].owner==owner_node:
			warnings[i].node.queue_free();warnings.remove_at(i)

func review_burst(pos: Vector2) -> void:
	fx("capabilities_fx","review_burst",pos,2.0,.65)
	sound("unlock",pos)
	for enemy in enemies+bosses:
		if is_instance_valid(enemy) and not enemy.dead and enemy.position.distance_to(pos)<245: enemy.stun(1.5 if not enemy.is_boss else .7)
	toast("REVIEW BURST — nearby threats stunned",1.3)

func create_zone(pos: Vector2) -> void:
	if zones.size()>=6: return
	var sprite := Art.sprite("capabilities_fx","change_stack_zone",1.4,false)
	sprite.position=pos
	ground.add_child(sprite)
	zones.append({"node":sprite,"pos":pos,"life":2.0,"hit_ids":[]})

func _tick_capabilities(dt: float) -> void:
	if player.swing_left<=0 and player.combo_window<=0: hammer_target=null
	triage_target=null
	var highest := -INF
	for enemy in enemies+bosses:
		if not is_instance_valid(enemy) or enemy.dead: continue
		enemy.triage_marked=false
		if capabilities.triage:
			var threat: float=enemy.hp+(99 if enemy.kind=="agent_spawner" else 0)+maxf(0,600-player.position.distance_to(enemy.position))*.01
			if threat>highest: highest=threat;triage_target=enemy
	if is_instance_valid(triage_target): triage_target.triage_marked=true;triage_target.queue_redraw()
	for i in range(zones.size()-1,-1,-1):
		var zone: Dictionary=zones[i]
		zone.life-=dt
		zone.node.modulate.a=minf(1,zone.life)
		for enemy in enemies.duplicate()+bosses.duplicate():
			if not is_instance_valid(enemy) or enemy.dead: continue
			var id: int=enemy.get_instance_id()
			var offset: Vector2=(enemy.position-zone.pos)/Vector2(125,55)
			if offset.length()<1 and id not in zone.hit_ids:
				zone.hit_ids.append(id)
				enemy.take_hit(2 if enemy==triage_target or enemy==hammer_target else 1,50,zone.pos,true)
		if zone.life<=0: zone.node.queue_free();zones.remove_at(i)

func show_cards(names: Array, callback: Callable) -> void:
	playing=false;state="cards"
	card_queue.clear()
	for name in names: card_queue.append(str(name))
	card_callback=callback
	overlay.hide();card_host.show()
	_load_card()

func _load_card() -> void:
	if is_instance_valid(card):
		card_host.remove_child(card);card.queue_free()
	card=load(Art.PRESENTATION+card_queue[0]+".tscn").instantiate()
	card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	card_host.add_child(card)
	card_clock=0
	if card.has_method("advance"):
		# A story scene carries the hint and the drain bar in its lower letterbox bar.
		card.position.x=0
		card.hint.text=CARD_HINT
		card_progress=card.drain
		card.advance(0,card_hold())
	else: _dress_card()
	var name := card_queue[0]
	if name.begins_with("boss_"): sound("reveal_"+name.trim_prefix("boss_"),player.position)
	elif name.begins_with("unlock_"): sound("unlock",player.position)
	_layout_card()

## Slide-in cards get the hint and the drain bar along their bottom edge.
func _dress_card() -> void:
	card.position.x=1280
	var hint := Style.label(CARD_HINT,16)
	hint.position=Vector2(360,670)
	card.add_child(hint)
	card_progress=ProgressBar.new()
	card_progress.position=Vector2(360,696)
	card_progress.size=Vector2(560,5)
	card_progress.max_value=1.0
	card_progress.value=1.0
	card_progress.show_percentage=false
	card_progress.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var progress_background := StyleBoxFlat.new()
	progress_background.bg_color=Color("142735")
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color=Color("ffab54")
	card_progress.add_theme_stylebox_override("background",progress_background)
	card_progress.add_theme_stylebox_override("fill",progress_fill)
	card.add_child(card_progress)

func card_hold() -> float:
	if card_queue.is_empty(): return 0.0
	return float(Catalog.CARD_HOLD.get(card_queue[0],4.5))

func next_card() -> void:
	if state!="cards": return
	card_queue.pop_front()
	if card_queue.is_empty():
		card_host.hide()
		var callback := card_callback
		card_callback=Callable()
		callback.call()
	else: _load_card()

func _layout_card() -> void:
	if not is_instance_valid(card_host): return
	var size := get_viewport_rect().size
	var ratio := minf(size.x/1280.0,size.y/720.0)
	card_host.scale=Vector2.ONE*ratio
	card_host.position=(size-Vector2(1280,720)*ratio)*.5
