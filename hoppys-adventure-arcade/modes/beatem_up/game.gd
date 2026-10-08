extends Node2D
const Art = preload("res://modes/beatem_up/art.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Player = preload("res://modes/beatem_up/player.gd")
const Enemy = preload("res://modes/beatem_up/enemy.gd")
const Boss = preload("res://modes/beatem_up/boss.gd")
const StageFlow = preload("res://modes/beatem_up/stage_flow.gd")
const Style = preload("res://scenes/main_menu/menu_style.gd")
const PAUSABLE := ["combat","intro","stage_enter","stage_exit"]
var rng := RandomNumberGenerator.new()
var stage_index := 0
var room := 0
var score := 0
var checkpoint_score := 0
var elapsed := 0.0
var playing := false
var state := "intro"
var pause_return_state := "combat"
var intro_page := 0
var intro_clock := 0.0
var intro_bar: ProgressBar
var flow: StageFlow
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
var sound_pool: Array[AudioStreamPlayer2D] = []
var sound_index := 0
var hud: Label
var objective: Label
var boss_bar: ProgressBar
var boss_text: Label
var toast_label: Label
var toast_left := 0.0
var ui_layer: CanvasLayer
var prompt: Label
var overlay: ColorRect
var panel: VBoxContainer
var primary: Button
var screen_fx: ColorRect
var finish_clock := 0.0
var merge_button: AnimatedSprite2D
var merge_slammed := false
var completion_count := 0
var test_mode := false
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
	playing = false
	get_tree().paused = false
	for child in world.get_children(): child.queue_free()
	enemies.clear(); props.clear(); pickups.clear(); bullets.clear(); warnings.clear(); allies.clear()
	boss = null
	merge_button = null
	stage_index = index
	room = 0
	gate_open = false
	last_swing_processed = -1
	shake = 0
	camera.offset = Vector2.ZERO
	screen_fx.material.set_shader_parameter("phase",0.0)
	ground = Node2D.new()
	world.add_child(ground)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	world.add_child(actors)
	for i in 3:
		var bg := Sprite2D.new()
		bg.texture = load(Art.BASE+Catalog.THEMES[index]+"_background.png")
		bg.centered = false
		bg.position.x = i*1280
		ground.add_child(bg)
		# Standalone mid/near props break up the finite room panoramas.
		var decor := Art.sprite(Catalog.THEMES[index]+"_kit",["ide_cluster","alert_beacon","commit_tree"][index],1.3,false)
		decor.position = Vector2(i*1280+360,260)
		ground.add_child(decor)
	player = Player.new()
	player.arena = self
	# Off-screen left: every stage opens with Hoppy running in (stage_flow.gd).
	player.position = Vector2(Catalog.FLOW.enter_from_x,580)
	actors.add_child(player)
	camera.position = Vector2(640,360)
	camera.reset_physics_interpolation()
	prompt.text = ""
	flow.play_music(Catalog.looped(Catalog.MUSIC[index]),Catalog.MUSIC[index])
	enter_room(0)
	if cinematic:
		state = "intro"
		intro_page = 0
		intro_clock = 0
		show_intro()
	else: enter_stage()
	_update_hud()

## stage_enter: Hoppy runs in under the title banner, then begin_play() (see _on_flow_phase).
func enter_stage() -> void:
	overlay.hide()
	playing = false
	state = "stage_enter"
	hide_toast() # The banner owns the screen; begin_play() re-announces the encounter.
	flow.play_enter("%02d / %s" % [stage_index+1,Catalog.TITLES[stage_index]],Catalog.STORIES[stage_index])

## stage_exit: Hoppy runs out, the screen dips to black and the next district is built under it.
func exit_stage() -> void:
	playing = false
	state = "stage_exit"
	prompt.text = ""
	hide_toast()
	flow.banner("DISTRICT SECURED","Stage score saved · Next: "+Catalog.TITLES[stage_index+1],Catalog.FLOW.exit_banner)
	flow.play_exit(advance_stage)

func _on_flow_phase(phase: String) -> void:
	if phase=="" and state=="stage_enter": begin_play()

func enter_room(index: int) -> void:
	room = index
	gate_open = false
	hazard_clock = 4.0
	ally_clock = 9.0
	if is_instance_valid(gate): gate.queue_free()
	gate = Art.sprite("district_kit","encounter_gate",1.35,false)
	gate.position = Vector2(room_start()+1200,550)
	gate.modulate = [Color("76f9dd"),Color("ff8888"),Color("f2c573")][stage_index]
	ground.add_child(gate)
	var wave: Array = Catalog.WAVES[stage_index][room]
	for i in wave.size():
		spawn_enemy(wave[i],Vector2(room_start()+650+i*110,485+(i%3)*67))
	spawn_prop(["kiosk","server","pillar"][stage_index],Vector2(room_start()+360,480),0)
	spawn_prop(["ide","crate","scaffolding"][stage_index],Vector2(room_start()+920,625),1)
	if stage_index==0 and room==0: drop("debug_stick",Vector2(290,590))
	if stage_index==2 and room==2:
		boss = Boss.new()
		boss.arena = self
		boss.position = Vector2(room_start()+965,565)
		actors.add_child(boss)
		flow.swap_music(Catalog.looped(Catalog.BOSS_MUSIC),Catalog.FLOW.boss_dip,Catalog.BOSS_MUSIC)
		toast("THE GRAND MERGE CONFLICT",3)
	else: toast("ENCOUNTER %d / 3 — clear the blockers" % (room+1),2)

func spawn_enemy(kind: String, pos: Vector2, split := true) -> Node2D:
	if living_enemies() >= 12: return null
	var enemy := Enemy.new()
	enemy.arena = self
	enemy.kind = kind
	enemy.position = pos
	enemy.can_split = split
	actors.add_child(enemy)
	enemies.append(enemy)
	return enemy

func living_enemies() -> int:
	var count := 0
	for e in enemies:
		if is_instance_valid(e) and not e.dead: count += 1
	return count

func enemy_defeated(enemy: Node2D) -> void:
	score += 100
	if rng.randf() < .18: drop("coffee" if player.hp<3 else "attack_up",enemy.position)

func resolve_swing(source: Node2D) -> void:
	if not playing or source.hp <= 0 or source.swing_serial == last_swing_processed: return
	last_swing_processed = source.swing_serial
	var weapon: String = source.attack_weapon
	var def: Dictionary = Catalog.WEAPONS[weapon] if weapon != "" else {"damage":2.0 if source.combo==3 else 1.0,"reach":110.0 if source.combo==3 else 95.0,"depth":46.0,"knock":260.0 if source.combo==3 else 75.0}
	var damage: float = def.damage
	if source.effects.has("attack_up"): damage += 1
	if source.effects.has("strength_down"): damage *= .5
	var hit := false
	var targets: Array = enemies.duplicate()
	if is_instance_valid(boss): targets.append(boss)
	for enemy in targets:
		if not is_instance_valid(enemy) or enemy.dead: continue
		var offset: Vector2 = enemy.position-source.position
		var in_reach := melee_contains(offset,source.facing,def.reach,def.depth)
		if enemy==boss: in_reach=boss.melee_reaches(offset,source.facing,def.reach,def.depth)
		if in_reach:
			if enemy.take_hit(damage,def.knock,source.position,source.combo==3 or weapon!=""):
				hit = true
				fx("weapons","hammer_impact" if weapon=="refactor_hammer" else "melee_sweep",enemy.position-Vector2(0,55),.6,.16)
				if weapon=="refactor_hammer": break
	for prop in props:
		if weapon=="refactor_hammer" and hit: break
		if prop.hp <= 0: continue
		var offset: Vector2 = prop.node.position-source.position
		if melee_contains(offset,source.facing,def.reach,def.depth):
			prop.hp -= damage
			hit = true
			prop.sprite.play(prop.kind+"_cracked" if prop.kind not in ["ide","scaffolding"] else prop.kind+"_warning")
			if prop.hp <= 0: break_prop(prop)
			if weapon=="refactor_hammer": break
	if hit:
		shake = 3 if source.combo<3 else 6
		if weapon != "" and source.weapon == weapon: source.spend_weapon()
	else: fx("weapons","melee_sweep",source.position+Vector2(source.facing*65,-source.height-50),.5,.13)

static func melee_contains(offset: Vector2, facing: float, reach: float, depth: float) -> bool:
	return offset.x*facing >= -20 and offset.x*facing <= reach and absf(offset.y) <= depth

func spawn_prop(kind: String, pos: Vector2, slot: int) -> void:
	var node := Node2D.new()
	node.position = pos
	var sprite := Art.sprite(Catalog.THEMES[stage_index]+"_kit",kind+"_intact",1.25,false)
	sprite.position.y = -58
	node.add_child(sprite)
	actors.add_child(node)
	props.append({"node":node,"sprite":sprite,"kind":kind,"hp":2.0,"slot":slot,"room":room})

func break_prop(prop: Dictionary) -> void:
	var kind: String = prop.kind
	prop.sprite.play(kind+"_break")
	var tween: Tween = prop.node.create_tween()
	tween.tween_interval(.25)
	tween.tween_callback(func(): prop.sprite.play(kind+"_rubble" if kind!="ide" else "ide_fragments"))
	score += 25
	sound("break",prop.node.position)
	var reward := "coffee"
	match kind:
		"kiosk": reward = "coffee" if prop.room==0 else "linter_staff" if prop.room==1 else "api_key_whip"
		"ide": reward = "speed_boost" if rng.randf()<.5 else "attack_up"
		"server":
			reward = ["firewall_shield","refactor_hammer","linter_staff"][prop.room]
			ground_warning(prop.node.position,Vector2(140,55),.95,.25,"breach")
		"crate": reward = ["attack_up","speed_boost","slow","confused"][rng.randi_range(0,3)]
		"pillar":
			drop("commit_token",prop.node.position+Vector2(-35,0))
			reward = "attack_up"
		"scaffolding": reward = "git_branch" if prop.room%2==0 else "api_key_whip"
	drop(reward,prop.node.position+Vector2(15,22))

func drop(kind: String, pos: Vector2) -> void:
	if pickups.size() >= 24: return
	var node := Node2D.new()
	node.position = clamp_ground(pos)
	var sprite := Art.sprite("weapons" if Catalog.WEAPONS.has(kind) else "items_allies",kind,.65,false)
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

func projectile(pos: Vector2, velocity: Vector2, pose := "red_projectile", status := "") -> void:
	if bullets.size() >= 32: return
	var node := Node2D.new()
	node.position = pos
	var sprite := Art.sprite("combat_fx",pose,.6,false)
	sprite.position.y = -42
	sprite.flip_h = velocity.x<0 if pose in ["red_projectile","injection_projectile"] else velocity.x>0
	node.add_child(sprite)
	actors.add_child(node)
	bullets.append({"node":node,"velocity":velocity,"life":6.0,"status":status})

func ground_warning(pos: Vector2, radius: Vector2, delay: float, duration: float, kind: String, owner_node: Node = null) -> void:
	if warnings.size()>=12: return
	var marker := Art.sprite("combat_fx","slam_warning",1,false)
	marker.position = pos
	marker.scale = Vector2(radius.x/54.0,radius.y/14.0)
	ground.add_child(marker)
	warnings.append({"node":marker,"pos":pos,"radius":radius,"left":delay,"active":duration,"kind":kind,"fired":false,"owner":owner_node})

func clear_threats() -> void:
	for b in bullets: b.node.queue_free()
	for w in warnings: w.node.queue_free()
	bullets.clear()
	warnings.clear()

func fx(sheet: String, pose: String, pos: Vector2, magnify: float, lifetime: float) -> void:
	var sprite := Art.sprite(sheet,pose,magnify,false)
	sprite.position = pos
	actors.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite,"modulate:a",0.0,lifetime)
	tween.tween_callback(sprite.queue_free)

func sound(key: String, pos: Vector2) -> void:
	if sound_pool.is_empty(): return
	var voice := sound_pool[sound_index%sound_pool.size()]
	sound_index += 1
	voice.position = pos
	voice.stream = Catalog.SOUNDS[key]
	voice.play()

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player) or get_tree().paused: return
	if state=="finisher": _tick_finisher(dt)
	elif state=="intro": _tick_intro(dt)
	# Toasts, banners and transitions run outside combat too, so none freezes on screen.
	toast_left -= dt
	toast_label.visible = toast_left > 0
	flow.tick(dt,player)
	if not playing: return
	elapsed += dt
	shake = maxf(0,shake-dt*28)
	camera.position = camera.position.lerp(Vector2(room_start()+640,360),minf(1,dt*5))
	camera.offset = Vector2(rng.randf_range(-shake,shake),rng.randf_range(-shake,shake))
	var view := get_viewport_rect().size
	camera.zoom = Vector2.ONE*minf(view.x/1280.0,view.y/720.0)
	_tick_items(dt)
	_tick_threats(dt)
	_tick_allies(dt)
	if not playing: return
	if not gate_open and living_enemies()==0 and not is_instance_valid(boss):
		gate_open = true
		gate.hide()
		clear_threats()
		toast("BLOCKERS CLEARED — GO RIGHT  →",3)
	if gate_open and player.position.x > room_start()+1205:
		if room<2: enter_room(room+1)
		elif stage_index+1 < Catalog.TITLES.size():
			exit_stage()
			return
	if not gate_open:
		hazard_clock -= dt
		if hazard_clock <= 0:
			hazard_clock = 5.2
			stage_hazard()
	if is_instance_valid(boss):
		screen_fx.material.set_shader_parameter("phase",float(boss.phase))
		screen_fx.material.set_shader_parameter("clock",elapsed)
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
		var b: Dictionary = bullets[i]
		b.node.position += b.velocity*dt
		b.life -= dt
		var offset: Vector2 = b.node.position-player.position
		var contact: bool = absf(offset.x)<32 and absf(offset.y)<25 and player.height<38
		if contact:
			player.take_hit(b.node.position-b.velocity*.1,b.status)
		if contact or b.life<=0 or b.node.position.x<room_start()-180:
			b.node.queue_free()
			bullets.remove_at(i)
	for i in range(warnings.size()-1,-1,-1):
		var w: Dictionary = warnings[i]
		w.left -= dt
		if w.left <= 0:
			if not w.fired:
				w.fired = true
				w.node.play("slam_impact")
				match w.kind:
					"bomb": fx("district_kit","injection_blast",w.pos-Vector2(0,30),1.0,w.active)
					"scan": fx("security_kit","laser_active",w.pos-Vector2(0,45),1.8,w.active)
					"breach": fx("security_kit","breach_shockwave",w.pos,1.5,w.active)
					"head": fx("hq_kit","head_active",w.pos-Vector2(0,20),1.0,w.active)
				if w.kind!="signal": sound("kick",w.pos)
			var offset: Vector2 = (player.position-w.pos)/w.radius
			if w.kind!="signal" and offset.length()<1 and player.height<38:
				player.take_hit(w.pos-Vector2(1,0),"confused" if w.kind=="head" else "")
			if w.left <= -float(w.active):
				w.node.queue_free()
				warnings.remove_at(i)

func stage_hazard() -> void:
	if is_instance_valid(boss): return # Boss owns its arena's attack schedule.
	match stage_index:
		0:
			ground_warning(player.position,Vector2(80,38),1.25,.28,"bomb")
			var bomb := Art.sprite("district_kit","injection_bomb",.7,false)
			bomb.position = player.position-Vector2(0,320)
			actors.add_child(bomb)
			var tween := bomb.create_tween()
			tween.tween_property(bomb,"position:y",player.position.y-20,1.25)
			tween.tween_callback(bomb.queue_free)
		1: ground_warning(Vector2(clampf(player.position.x+70,room_start()+100,room_start()+1120),552),Vector2(35,110),1.2,.4,"scan")
		2:
			ground_warning(player.position,Vector2(75,35),1.2,1.0,"head")
			for lane in [480,620]: projectile(Vector2(room_start()+1250,lane),Vector2(-230,0),"cyan_projectile")

func _tick_allies(dt: float) -> void:
	ally_clock -= dt
	if ally_clock <= 0 and allies.is_empty() and not gate_open:
		ally_clock = 24
		var names := ["cr_bot","linting_fairy","senior_dev"]
		var id := stage_index if room==0 else rng.randi_range(0,2)
		var ally := Art.sprite("items_allies",names[id]+"_gift",1.15,false)
		ally.position = Vector2(room_start()+160,415)
		actors.add_child(ally)
		allies.append({"node":ally,"life":3.0})
		drop(["damage_shield","speed_boost","coffee"][id],Vector2(room_start()+220,485))
		toast(["CR BOT: approved!","LINTING FAIRY: pick up some speed!","SENIOR DEV: coffee break!"][id],2)
	for i in range(allies.size()-1,-1,-1):
		allies[i].life -= dt
		if allies[i].life<=0:
			allies[i].node.queue_free()
			allies.remove_at(i)

func begin_play() -> void:
	var entering := state in ["intro","stage_enter"]
	if flow.active(): flow.cancel()
	overlay.hide()
	state = "combat"
	playing = true
	player.input_lock = .2
	if entering:
		toast("ENCOUNTER %d / 3 — clear the blockers" % (room+1),2)
		# A fresh room's enemies telegraph no sooner than this after Hoppy gets control.
		for e in enemies:
			if is_instance_valid(e) and not e.dead: e.cooldown = maxf(e.cooldown,Catalog.FLOW.enemy_grace)

func advance_stage() -> void:
	checkpoint_score = score
	start_stage(stage_index+1)

func retry_stage() -> void:
	score = checkpoint_score
	start_stage(stage_index)

func game_over() -> void:
	if state=="game_over": return
	playing = false
	state = "game_over"
	_update_hud()
	show_overlay("REVIEW FAILED", "Retry %s with 3 HP and fresh equipment." % Catalog.TITLES[stage_index],"Retry current stage",retry_stage)

func boss_defeated() -> void:
	if state=="finisher" or state=="won": return
	playing = false
	state = "finisher"
	finish_clock = 0
	merge_slammed = false
	clear_threats()
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	enemies.clear()
	player.swing_left = 0
	player.held.hide()
	merge_button = Art.sprite("items_allies","merge_button",1.7,false)
	merge_button.position = Vector2(room_start()+740,580)
	actors.add_child(merge_button)
	toast("FORCE MERGE — SHIP THE FIX",5)
	sound("phase",boss.position)

func _tick_finisher(dt: float) -> void:
	finish_clock += dt
	player.position = player.position.move_toward(Vector2(room_start()+650,600),230*dt)
	player.facing = 1
	player.body.flip_h = false
	player.body.position.y = -sin(clampf((finish_clock-1.5)/1.0,0,1)*PI)*110
	if finish_clock <= 1.5: player.show_pose("run",true)
	elif finish_clock < 2.5: player.show_pose("jump")
	else: player.show_pose("swing" if finish_clock < 2.9 else "idle")
	if finish_clock >= 2.5 and not merge_slammed:
		merge_slammed = true
		player.show_pose("swing")
		boss.body.play("resolved_core")
		fx("combat_fx","merge_press",merge_button.position,2.4,1)
		fx("combat_fx","merge_radiance",boss.position-Vector2(0,110),3,1.2)
		sound("win",merge_button.position)
		score += 1000
		_update_hud()
		screen_fx.material.set_shader_parameter("phase",0.0)
	if finish_clock >= 4.0:
		state = "won"
		completion_count += 1
		show_overlay("MERGED. SHIPPED. SAVED.","Code City is back online.\nScore: %d   ·   Time: %d:%02d" % [score,int(elapsed)/60,int(elapsed)%60],"Return to Beat'em Up menu",leave)

func toast(message: String, seconds := 2.0) -> void:
	toast_label.text = message
	toast_label.show()
	toast_left = seconds

func hide_toast() -> void:
	toast_left = 0
	toast_label.hide()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	ui_layer = layer
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
	top.color = Color(.025,.045,.075,.93)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 105
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	hud = Style.label("",20)
	hud.position = Vector2(28,16)
	ui.add_child(hud)
	objective = Style.label("",16,Style.MINT)
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
	toast_label.offset_top = 120
	toast_label.offset_bottom = 157
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
	var controls := Style.label("WASD / stick · Move    Space / A · Jump    J, X / X · Combo    E / Y · Pickup    Esc · Pause",13)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -27
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(controls)
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
	hud.text = "HOPPY  "+health+"    SCORE %05d" % score
	var weapon: String = player.weapon.replace("_"," ").to_upper()+" [%d]" % player.durability if player.weapon!="" else "UNARMED · JAB → SWING → KICK"
	var statuses := ""
	for effect in player.effects: statuses += "  "+effect.replace("_"," ").to_upper()+" %ds" % ceili(player.effects[effect])
	if player.shield: statuses += "  APPROVAL SHIELD"
	objective.text = "%s · %d/3\n%s%s" % [Catalog.TITLES[stage_index],room+1,weapon,statuses]
	boss_bar.visible = is_instance_valid(boss)
	boss_text.visible = boss_bar.visible
	if is_instance_valid(boss):
		boss_bar.max_value = boss.max_hp
		boss_bar.value = boss.hp
		boss_text.text = "GRAND MERGE CONFLICT · PHASE %d" % boss.phase

func show_overlay(title: String, detail: String, action: String, callback: Callable) -> void:
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
	primary = Style.button(action,58)
	panel.add_child(primary)
	primary.pressed.connect(callback)
	if state != "won":
		var back := Style.button("Return to Beat'em Up menu",54)
		panel.add_child(back)
		back.pressed.connect(leave)
	overlay.show()
	primary.grab_focus()

func show_intro() -> void:
	var titles := ["CODE CITY: UNDER SIEGE", "REVIEW PIPELINE: BREACHED", "HOPPY CLOCKS IN"]
	var lines := ["Rogue Code and Slop Code have escaped the review pipeline.\nThe terminals go dark.","The firewall is failing. Conflicting branches have taken over Git HQ.","The codebase needs a review. And Hoppy delivers.\nClear three districts and force the final merge."]
	show_overlay(titles[intro_page],lines[intro_page],"Start the review →" if intro_page==2 else "Next →",next_intro)
	var skip := Style.button("Skip intro",46)
	panel.add_child(skip)
	skip.pressed.connect(enter_stage)
	# Drains while the page holds; the page turns by itself when it empties.
	intro_bar = ProgressBar.new()
	intro_bar.show_percentage = false
	intro_bar.custom_minimum_size = Vector2(720,6)
	intro_bar.max_value = 1.0
	intro_bar.step = 0.0
	intro_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in ["background","fill"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("142735") if part=="background" else Style.MINT
		intro_bar.add_theme_stylebox_override(part,box)
	panel.add_child(intro_bar)
	panel.move_child(intro_bar,2)
	_tick_intro(0)

func _tick_intro(dt: float) -> void:
	intro_clock += dt
	if is_instance_valid(intro_bar): intro_bar.value = 1.0-intro_clock/Catalog.FLOW.intro_hold
	if intro_clock >= Catalog.FLOW.intro_hold: next_intro()

func next_intro() -> void:
	intro_page += 1
	intro_clock = 0
	if intro_page>=3: enter_stage()
	else: show_intro()

func pause(detail: String) -> void:
	pause_return_state = state
	playing = false
	state = "paused"
	get_tree().paused = true
	show_overlay("REVIEW PAUSED",detail,"Resume",resume)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if state in PAUSABLE: pause("Chain three attacks for a knockback finisher. Jump or change lanes to dodge.\nApproach a weapon and press E / Y to equip it.")
		elif state=="paused": resume()
		get_viewport().set_input_as_handled()

func resume() -> void:
	get_tree().paused = false
	match pause_return_state:
		"intro":
			state = "intro"
			show_intro()
		"stage_enter", "stage_exit":
			state = pause_return_state
			overlay.hide()
		_: begin_play()

func leave() -> void:
	playing = false
	get_tree().paused = false
	music.stop()
	AppRouter.go("beatem_up")

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and state in PAUSABLE and not test_mode:
		pause("The window lost focus.")

func _exit_tree() -> void:
	get_tree().paused = false
