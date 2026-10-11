extends Node2D
const Art = preload("res://modes/beatem_up/art.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const Player = preload("res://modes/beatem_up/player.gd")
const Enemy = preload("res://modes/beatem_up/enemy.gd")
const Boss = preload("res://modes/beatem_up/boss.gd")
const MiniBoss = preload("res://modes/beatem_up/mini_boss.gd")
const StageFlow = preload("res://modes/beatem_up/stage_flow.gd")
const Knockout = preload("res://modes/beatem_up/knockout.gd")
const Celebration = preload("res://modes/beatem_up/celebration.gd")
const StoryScene = preload("res://modes/beatem_up/story_scene.gd")
const VictoryScreen = preload("res://modes/beatem_up/victory_screen.gd")
const Minimap = preload("res://modes/beatem_up/minimap.gd")
const Style = preload("res://scenes/main_menu/menu_style.gd")
const PAUSABLE := ["combat","intro","ending","stage_enter","stage_exit","knockout","boss_victory","celebration"]
## The minimap is up while Hoppy is in a room, and hidden under the story scenes and end screens.
const MINIMAP_STATES := ["stage_enter","combat","stage_exit","boss_victory","finisher","knockout"]
## Results and game-over menus arm this long after appearing (see _input).
const OVERLAY_ARM := .5
const ARMED_OVERLAYS := ["won","game_over"]
const Prompts := preload("res://app/controller_prompts.gd")
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
## The story scenes now playing: Catalog.STORY (the opening) or Catalog.ENDING (the victory
## epilogue). intro_page and intro_clock step through either.
var story_pages := "STORY"
## The opening's story scenes, with Next / Skip intro / Return in the lower bar.
var story: StoryScene
var intro_next: Button
var intro_skip: Button
var intro_return: Button
## The final results screen after the victory epilogue.
var victory: VictoryScreen
var minimap: Minimap
var overlay_clock := 0.0
var flow: StageFlow
## The last-life knockout between the fatal hit and game_over().
var ko := Knockout.new(Catalog.KNOCKOUT)
## The celebration between the Force Merge and the ending pages.
var party := Celebration.new()
## This stage's district boss has been called in (it guards room 3 once the wave is down).
var mini_boss_called := false
## Seconds into the district-boss victory hop.
var victory_clock := 0.0
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
## A toast raised while the stage title banner fades into combat waits for it, so the two never stack.
var held_toast := ""
var held_toast_seconds := 2.0
var ui_layer: CanvasLayer
## The HUD bar's backing strip and the control hints along the bottom (knockout_hud_nodes).
var hud_strip: ColorRect
var controls_hint: Label
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
	ko.cancel()
	party.cancel()
	playing = false
	get_tree().paused = false
	for child in world.get_children(): child.queue_free()
	enemies.clear(); props.clear(); pickups.clear(); bullets.clear(); warnings.clear(); allies.clear()
	boss = null
	merge_button = null
	mini_boss_called = false
	victory_clock = 0
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
		story_pages = "STORY"
		intro_page = 0
		intro_clock = 0
		hide_toast() # enter_room(0)'s line would sit behind the intro; begin_play announces the room.
		show_intro()
	else: enter_stage()
	_update_hud()

## stage_enter: Hoppy runs in under the title banner, then begin_play() (see _on_flow_phase).
func enter_stage() -> void:
	overlay.hide()
	story.hide()
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

## Room 3 of districts 1 and 2: the cleared wave calls in the district boss instead of opening
## the gate. It drops in on the right and shares the `boss` slot (HUD bar, minimap, no hazards).
func call_mini_boss() -> void:
	mini_boss_called = true
	var key: String = Catalog.MINI_BOSS_STAGES[stage_index]
	boss = MiniBoss.new()
	boss.arena = self
	boss.key = key
	boss.position = Vector2(room_start()+1000,560)
	actors.add_child(boss)
	clear_threats()
	# Its own fight track (the Grand Merge Conflict keeps BOSS_MUSIC); the next district's
	# start_stage brings that district's track back.
	flow.swap_music(Catalog.looped(Catalog.MINI_BOSS_MUSIC),Catalog.FLOW.boss_dip,Catalog.MINI_BOSS_MUSIC)
	toast("DISTRICT BOSS · %s" % Catalog.MINI_BOSSES[key].title,3)
	_update_hud()

func has_mini_boss() -> bool:
	return is_instance_valid(boss) and boss is MiniBoss

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
				# Hits burst on the victim (reach outruns the tip); the sweep cel is drawn travelling left.
				fx("weapons","hammer_impact" if weapon=="refactor_hammer" else "melee_sweep",enemy.position-Vector2(0,55),.6,.16,source.facing>0)
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
	else: fx("weapons","melee_sweep",source.tip_position(),.5,.13,source.facing>0)

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

## Removes the warnings `owner_node` planted, such as a staggered boss's dropped move.
func drop_warnings(owner_node: Node) -> void:
	for i in range(warnings.size()-1,-1,-1):
		if warnings[i].owner == owner_node:
			warnings[i].node.queue_free()
			warnings.remove_at(i)

func fx(sheet: String, pose: String, pos: Vector2, magnify: float, lifetime: float, mirror := false) -> void:
	var sprite := Art.sprite(sheet,pose,magnify,false)
	sprite.position = pos
	sprite.flip_h = mirror
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
	if not is_instance_valid(player) or get_tree().paused or state=="leaving": return
	overlay_clock += dt
	# The celebration ticks after the minimap and toast refresh below, so the chrome it hides stays
	# hidden; never on the frame the finisher starts it.
	var celebrating := state=="celebration"
	if state=="finisher": _tick_finisher(dt)
	elif state=="boss_victory": _tick_boss_victory(dt)
	elif state in ["intro","ending"]: _tick_intro(dt)
	elif state=="won" and victory.advance(dt): sound("win",player.position)
	_refresh_minimap(dt)
	# Toasts, banners and transitions run outside combat too, so none freezes on screen.
	toast_left -= dt
	toast_label.visible = toast_left > 0
	flow.tick(dt,player)
	if held_toast != "" and state=="combat" and not flow.banner_active(): toast(held_toast,held_toast_seconds)
	if state=="knockout": _tick_knockout(dt)
	if celebrating and state=="celebration": party.tick(dt)
	if not playing: return
	elapsed += dt
	shake = maxf(0,shake-dt*28)
	camera.position = camera.position.lerp(Vector2(room_start()+640,360),minf(1,dt*5))
	camera.offset = Vector2(rng.randf_range(-shake,shake),rng.randf_range(-shake,shake))
	var view := get_viewport_rect().size
	camera.zoom = Vector2.ONE*minf(view.x/1280.0,view.y/720.0)
	_tick_items(dt)
	_tick_threats(dt)
	# A fatal hit starts the knockout here, so no ally arrives or speaks on that frame.
	if not playing: return
	_tick_allies(dt)
	if not gate_open and living_enemies()==0 and not is_instance_valid(boss):
		if room==2 and Catalog.MINI_BOSS_STAGES[stage_index]!="" and not mini_boss_called: call_mini_boss()
		else:
			gate_open = true
			gate.hide()
			clear_threats()
			toast("BLOCKERS CLEARED — GO RIGHT  →",3)
	# Room 3 has no walk-out: its boss's defeat runs Hoppy off (mini_boss_defeated, the finisher).
	if gate_open and room<2 and player.position.x > room_start()+1205: enter_room(room+1)
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
			if distance<85: prompt.text = Prompts.either("E", &"brawl_pickup", true)+" · PICK UP "+item.kind.replace("_"," ").to_upper()
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
	story.hide()
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
	flow.cancel() # A pending exit must not advance the stage being retried.
	score = checkpoint_score
	start_stage(stage_index)

## The fatal hit: play stops at once (enemies, bullets and hazards freeze), the screen clears of
## toasts and banners, and the knockout plays out before game_over(). Repeats are ignored.
func knockout(source: Vector2) -> void:
	if state in ["knockout","game_over","leaving"]: return
	flow.cancel()
	playing = false
	state = "knockout"
	hide_toast()
	prompt.text = ""
	flow.banner("","",0)
	_update_hud()
	ko.play(self,source,game_over)

## Play is stopped through the knockout, so its camera shake decays here.
func _tick_knockout(dt: float) -> void:
	ko.tick(dt)
	shake = maxf(0,shake-dt*28)
	camera.offset = Vector2(rng.randf_range(-shake,shake),rng.randf_range(-shake,shake))

## Terminal paths (game over, leave) cancel the flow first, so a pending exit can never
## rebuild the next stage at black or restart its music behind them.
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
	if state in ["finisher","celebration","ending","won","knockout","boss_victory"]: return
	if has_mini_boss():
		mini_boss_defeated()
		return
	# No stage sequence may outlive the boss; a boss-music swap still finishes (it isn't one).
	if flow.active(): flow.cancel()
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

## A district boss is down: play stops, its adds and threats clear, and Hoppy hops in his victory
## pose under DISTRICT BOSS DOWN for FLOW.boss_victory seconds before running off (exit_stage).
func mini_boss_defeated() -> void:
	# No stage sequence may outlive the boss; a boss-music swap still finishes (it isn't one).
	if flow.active(): flow.cancel()
	playing = false
	state = "boss_victory"
	victory_clock = 0
	clear_threats()
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	enemies.clear()
	score += 500
	gate_open = true
	gate.hide()
	player.swing_left = 0
	player.queued = false
	player.height = 0
	player.rise = 0
	player.velocity = Vector2.ZERO
	player.knock = Vector2.ZERO
	player.body.position = Vector2.ZERO
	player.body.modulate = Color.WHITE
	player.held.hide()
	player.show_pose("victory")
	# Keep the celebration in front of the fading boss.
	player.z_index = 2
	shake = 0
	camera.offset = Vector2.ZERO
	hide_toast()
	prompt.text = ""
	flow.banner("DISTRICT BOSS DOWN","%s defeated · +500" % boss.title,float(Catalog.FLOW.boss_victory))
	sound("win",player.position)
	_update_hud()

func _tick_boss_victory(dt: float) -> void:
	var length := float(Catalog.FLOW.boss_victory)
	victory_clock = minf(length,victory_clock+dt)
	# One short hop on the spot; the ground position and combat stay frozen.
	player.body.position.y = -float(Catalog.FLOW.boss_hop)*sin(PI*clampf(victory_clock/(length*.5),0,1))
	if is_instance_valid(boss) and boss.has_method("defeat_tick"): boss.defeat_tick(dt)
	if victory_clock >= length:
		player.body.position.y = 0
		exit_stage()

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
	if finish_clock >= 4.0: celebrate()

## The celebration (confetti, the victory cheer, the jingle into the victory loop), then the
## ending pages.
func celebrate() -> void:
	if state!="finisher": return
	state = "celebration"
	hide_toast()
	prompt.text = ""
	party.play(self,start_ending)

## The victory epilogue: the ENDING story scenes play like the opening (Next / Skip, pausable),
## then the results screen counts the score up.
func start_ending() -> void:
	if state not in ["finisher","celebration"]: return
	state = "ending"
	# The celebration restores the chrome it hid just before calling this; the minimap goes at once.
	_refresh_minimap(0.0)
	story_pages = "ENDING"
	intro_page = 0
	intro_clock = 0
	hide_toast()
	prompt.text = ""
	show_intro()

## The results screen; the run counts as complete once, here.
func show_victory() -> void:
	if state=="won": return
	state = "won"
	completion_count += 1
	story.hide()
	overlay.hide()
	hide_toast()
	prompt.text = ""
	victory.show_result(Catalog.VICTORY.title,Catalog.VICTORY.line,score,elapsed,Catalog.STORY_ACCENT,"Return to Beat'em Up menu",leave)

func toast(message: String, seconds := 2.0) -> void:
	# Combat opens under the fading stage title; anything said then waits for it (latest wins).
	if state=="combat" and flow.banner_active():
		held_toast = message
		held_toast_seconds = seconds
		return
	held_toast = ""
	toast_label.text = message
	toast_label.show()
	toast_left = seconds

func hide_toast() -> void:
	held_toast = ""
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
	hud_strip = top
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
	var bar_back := StyleBoxFlat.new()
	bar_back.bg_color = Color("1d2733")
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("ffc66c")
	boss_bar.add_theme_stylebox_override("background",bar_back)
	boss_bar.add_theme_stylebox_override("fill",bar_fill)
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
	var controls := Style.label("",13)
	controls_hint = controls
	Prompts.track(controls, func() -> String:
		return "%s · Move    %s · Jump    %s · Combo    %s · Pickup    %s · Pause" % [
			Prompts.keys_or_pad("WASD", Prompts.if_pad("stick")),
			Prompts.either("Space", &"brawl_jump"),
			Prompts.either("J, X", &"brawl_attack"),
			Prompts.either("E", &"brawl_pickup"),
			Prompts.either("Esc", &"pause")])
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -27
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(controls)
	# Top-right, under the HUD bar and clear of the boss bar inside it.
	minimap = Minimap.new()
	minimap.setup(Catalog.TITLES.size(),3,[Vector2i(2,2)],Catalog.STORY_ACCENT)
	minimap.dock(top.offset_bottom)
	minimap.hide()
	ui.add_child(minimap)
	# Over the HUD (the scenes are full-bleed), under the pause overlay.
	story = StoryScene.new()
	story.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story.hint.text = "Esc · Pause"
	story.hide()
	ui.add_child(story)
	intro_next = _intro_button("Next →",next_intro)
	intro_skip = _intro_button("Skip intro",finish_story)
	intro_return = _intro_button("Return to Beat'em Up menu",leave)
	victory = VictoryScreen.new()
	victory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(victory)
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

## The gameplay chrome the knockout cinematic hides and then restores (knockout.gd): the HUD
## strip and its labels, the boss bar, toast, prompt, control hints and minimap. Menus, story
## scenes and the screen shader are not chrome.
func knockout_hud_nodes() -> Array[CanvasItem]:
	var nodes: Array[CanvasItem] = [hud_strip,hud,objective,boss_text,boss_bar,toast_label,prompt,controls_hint,minimap]
	return nodes

func _update_hud() -> void:
	var health := ""
	for i in 3: health += "♥ " if i<player.hp else "· "
	hud.text = "HOPPY  "+health+"    SCORE %05d" % score
	var weapon: String = player.weapon.replace("_"," ").to_upper()+" [%d]" % player.durability if player.weapon!="" else "UNARMED · JAB → SWING → KICK"
	var statuses := ""
	for effect in player.effects: statuses += "  "+effect.replace("_"," ").to_upper()+" %ds" % ceili(player.effects[effect])
	if player.shield: statuses += "  APPROVAL SHIELD"
	objective.text = "%s · %d/3\n%s%s" % [Catalog.TITLES[stage_index],room+1,weapon,statuses]
	# A fallen district boss leaves the HUD; the Grand Merge Conflict's bar stays for the finisher.
	boss_bar.visible = is_instance_valid(boss) and not (has_mini_boss() and boss.dead)
	boss_text.visible = boss_bar.visible
	if is_instance_valid(boss):
		boss_bar.max_value = boss.max_hp
		boss_bar.value = boss.hp
		boss_text.text = ("DISTRICT BOSS · %s" % boss.title) if has_mini_boss() else ("GRAND MERGE CONFLICT · PHASE %d" % boss.phase)

## Feeds the minimap this frame's room: Hoppy, the living enemies and the boss, and the gate.
func _refresh_minimap(dt: float) -> void:
	# The stage title banner crosses the corner; it owns the screen while it is up.
	minimap.visible = state in MINIMAP_STATES and not flow.banner_active()
	if not minimap.visible: return
	var foes := PackedVector2Array()
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead: foes.append(enemy.position)
	var heads := PackedVector2Array()
	if is_instance_valid(boss) and not boss.dead: heads.append(boss.position)
	minimap.tick(dt,{"stage":stage_index, "room":room, "cleared":gate_open or state in ["finisher","celebration"],
		"gate_open":gate_open, "room_left":room_start(), "player":player.position,
		"enemies":foes, "bosses":heads})

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
	overlay_clock = 0
	overlay.show()
	primary.grab_focus()

## Page intro_page of the story now playing (story_pages: the opening or the victory epilogue)
## as a story scene. It turns by itself after story_hold() while its bar drains; resume calls this
## again to restore the page. Past the last page the story is over (finish_story()).
func show_intro() -> void:
	var count := StoryScene.page_list(Catalog,story_pages).size()
	if intro_page>=count:
		finish_story()
		return
	overlay.hide()
	story.show_scene(Catalog,intro_page,story_pages)
	var ending := story_pages=="ENDING"
	var last := intro_page==count-1
	intro_next.text = ("Results →" if ending else "Start the review →") if last else "Next →"
	intro_skip.text = "Skip" if ending else "Skip intro"
	intro_return.visible = not ending
	story.show()
	intro_next.grab_focus()
	_tick_intro(0)

func story_hold() -> float:
	return Catalog.FLOW.ending_hold if story_pages=="ENDING" else Catalog.FLOW.intro_hold

func _tick_intro(dt: float) -> void:
	intro_clock += dt
	story.advance(intro_clock,story_hold())
	if intro_clock >= story_hold(): next_intro()

func next_intro() -> void:
	intro_page += 1
	intro_clock = 0
	if intro_page>=StoryScene.page_list(Catalog,story_pages).size(): finish_story()
	else: show_intro()

## The opening hands off to the stage entrance; the epilogue to the results screen.
func finish_story() -> void:
	if state=="ending": show_victory()
	else: enter_stage()

## A small focusable action in the story scene's lower bar. It only acts while a story runs,
## so a press that reaches it under the pause overlay or during the leave fade does nothing.
func _intro_button(text: String, action: Callable) -> Button:
	var button := Style.button(text,32)
	button.custom_minimum_size = Vector2(0,32)
	button.add_theme_font_size_override("font_size",14)
	button.pressed.connect(_intro_action.bind(action))
	story.actions.add_child(button)
	return button

func _intro_action(action: Callable) -> void:
	if state in ["intro","ending"]: action.call()

func pause(detail: String) -> void:
	pause_return_state = state
	playing = false
	state = "paused"
	get_tree().paused = true
	show_overlay("REVIEW PAUSED",detail,"Resume",resume)

## Jump's Space is also ui_accept, so a press carried over from the finisher or the fatal hit
## would fire the focused button before the player sees the screen. Swallow confirms (whatever
## they are bound to), clicks and touches, before the GUI gets them, for the first OVERLAY_ARM
## seconds. A native touch presses buttons too, not only its emulated click.
func _input(event: InputEvent) -> void:
	if state not in ARMED_OVERLAYS or not overlay.visible or overlay_clock >= OVERLAY_ARM: return
	if event.is_action("ui_accept") or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if state in PAUSABLE: pause("Chain three attacks for a knockback finisher. Jump or change lanes to dodge.\nApproach a weapon and press %s to equip it." % Prompts.either("E", &"brawl_pickup"))
		elif state=="paused": resume()
		get_viewport().set_input_as_handled()

func resume() -> void:
	if state!="paused": return
	get_tree().paused = false
	# The return state only means something while paused; consume it so a stale one can't steer
	# a later resume (pause() always sets it first).
	var back := pause_return_state
	pause_return_state = "combat"
	match back:
		"intro", "ending":
			state = back
			show_intro()
		"stage_enter", "stage_exit", "boss_victory", "celebration":
			state = back
			overlay.hide()
		"knockout":
			state = "knockout"
			overlay.hide()
		_: begin_play()

func leave() -> void:
	if state=="leaving": return
	ko.cancel()
	party.cancel()
	flow.cancel()
	# The scene keeps running through the router's fade: nothing may start play or music again.
	state = "leaving"
	playing = false
	for child in panel.get_children():
		if child is BaseButton: child.disabled = true
	victory.action.disabled = true
	get_tree().paused = false
	music.stop()
	AppRouter.go("beatem_up")

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and state in PAUSABLE and not test_mode:
		pause("The window lost focus.")

func _exit_tree() -> void:
	get_tree().paused = false
