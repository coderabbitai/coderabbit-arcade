extends CharacterBody2D
const Art = preload("res://modes/beatem_up/reinvent/art.gd")
const Catalog = preload("res://modes/beatem_up/reinvent/catalog.gd")
const BASE_FRAMES = preload("res://Assets/heroes-vs-villains-assets-only/heroes_villains/hoppy.tres")
const COMBAT_FRAMES = BASE_FRAMES
const MOTION_FRAMES = preload("res://Assets/heroes-vs-villains-assets-only/heroes_villains/hoppy_locomotion.tres")
const MOVE_SPEED := 264.0
const WeaponRig = preload("res://modes/beatem_up/reinvent/weapon_rig.gd")
var arena: Node2D
var body: AnimatedSprite2D
var held: Node2D
var visual_weapon := ""
var block_time := 0.0
var hp := 3
var facing := 1.0
var height := 0.0
var rise := 0.0
var invulnerable := 0.0
var stagger := 0.0
var pickup_time := 0.0
var input_lock := .2
var effects: Dictionary = {}
var shield := false
var weapon := ""
var durability := 0
var combo := 0
var combo_window := 0.0
var swing_left := 0.0
var swing_duration := .3
var swing_fired := false
var queued := false
var attack_weapon := ""
var swing_serial := 0
var knock := Vector2.ZERO
var controlled := true
var review_charge := 0.0
var review_cooldown := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	add_child(Art.shadow())
	body = AnimatedSprite2D.new()
	body.sprite_frames = COMBAT_FRAMES
	body.offset = Vector2(0,-51)
	body.scale = Vector2.ONE * 1.65
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(body)
	held = WeaponRig.new()
	add_child(held)
	held.hide()

func _physics_process(dt: float) -> void:
	if not arena.playing: return
	tick(dt)

func tick(dt: float) -> void:
	review_cooldown = maxf(0,review_cooldown-dt)
	if controlled and Input.is_action_pressed("review_burst") and arena.capabilities.review and hp>0 and stagger<=0:
		review_charge += dt
		if review_charge >= .45 and review_cooldown <= 0: activate_review()
	else: review_charge = 0.0
	block_time = maxf(0,block_time-dt)
	invulnerable = maxf(0,invulnerable-dt)
	stagger = maxf(0,stagger-dt)
	input_lock = maxf(0,input_lock-dt)
	pickup_time = maxf(0,pickup_time-dt)
	combo_window = maxf(0,combo_window-dt)
	for key in effects.keys():
		effects[key] -= dt
		if effects[key] <= 0: effects.erase(key)
	if hp <= 0: return
	var movement := Vector2.ZERO
	if controlled and input_lock <= 0 and stagger <= 0:
		movement = Input.get_vector("move_left","move_right","move_up","move_down")
		if effects.has("confused"): movement = -movement
		if absf(movement.x) > .15 and swing_left<=0: facing = signf(movement.x)
		if Input.is_action_just_pressed("brawl_jump"): jump()
		if Input.is_action_just_pressed("brawl_attack"): request_attack()
		if Input.is_action_just_pressed("brawl_pickup") and swing_left <= 0 and height < 20:
			arena.pickup_weapon()
	if swing_left > 0:
		swing_left -= dt
		if not swing_fired and swing_left <= swing_duration * .56:
			swing_fired = true
			arena.resolve_swing(self)
		if swing_left <= 0:
			combo_window = .48
			if queued:
				queued = false
				start_attack()
	var speed := MOVE_SPEED
	if effects.has("speed_surge"): speed *= 1.4
	if effects.has("overwhelmed"): speed *= .6
	if swing_left > 0: speed *= .3
	if pickup_time > 0 or stagger > 0: speed = 0
	velocity = movement * speed + knock
	move_and_slide()
	knock = knock.move_toward(Vector2.ZERO,800*dt)
	position = arena.clamp_ground(position)
	if height > 0 or rise > 0:
		height = maxf(0,height+rise*dt)
		rise -= 1150*dt
		if height <= 0: rise = 0
	body.position.y = -height
	body.modulate.a = .4 if invulnerable > 0 and int(invulnerable*14)%2==0 else 1.0
	var pose := "idle"
	var base := false
	if stagger > 0: pose = "hurt"
	elif swing_left > 0: pose = attack_pose()
	elif pickup_time > 0: pose = "pickup"
	elif height > 0: pose = "jump"
	elif movement.length() > .1:
		if absf(movement.y) > absf(movement.x)*1.3: pose = "walk_up" if movement.y<0 else "walk_down"
		else:
			pose = "run"
			base = true
	show_pose(pose,base)
	# Keep foot cadence proportional to travel, including analog input and statuses.
	if pose in ["run","walk_up","walk_down"]:
		body.speed_scale=movement.length()*speed/MOVE_SPEED
	var attacking := swing_left>0
	var progress := clampf(1.0-swing_left/swing_duration,0,1)
	if attacking and visual_weapon!="":
		# Match Hoppy's hands to the weapon's windup/contact/recovery timeline.
		body.pause()
		body.position.x=facing*sin(progress*PI)*5
	else: body.position.x=0
	held.position=Vector2(0,-height)
	held.scale=Vector2(facing,1)
	held.animate(visual_weapon if attacking else weapon,combo,progress,attacking,movement,dt,block_time)

func show_pose(pose: String, _base := false) -> void:
	var moving := pose in ["run","walk_up","walk_down"]
	var frames: SpriteFrames = MOTION_FRAMES if moving else COMBAT_FRAMES
	if body.sprite_frames != frames: body.sprite_frames = frames
	body.speed_scale=1.0
	body.flip_h = facing < 0 and pose not in ["walk_up","walk_down"]
	if pose == "death": pose = "defeat"
	if pose in ["jab","swing","kick"] and swing_left>0:
		var progress := 1.0-swing_left/swing_duration
		if progress<.4: pose += "_warning"
		elif progress>.8: pose = "idle"
	body.play(pose)

func activate_review() -> bool:
	if not arena.capabilities.review or review_cooldown>0 or hp<=0: return false
	review_cooldown = 8.0
	review_charge = 0.0
	invulnerable = maxf(invulnerable,.85)
	block_time = .85
	arena.review_burst(position)
	return true

func jump() -> void:
	if height > 0 or stagger > 0: return
	rise = 510
	height = 1
	arena.sound("jump",position)

func request_attack() -> void:
	if hp <= 0 or stagger > 0 or pickup_time > 0: return
	if swing_left > 0:
		if swing_left < .24: queued = true
		return
	start_attack()

func attack_pose() -> String:
	if visual_weapon!="":
		return "swing" if visual_weapon in ["triage_hammer","change_stack_baton"] or combo!=1 else "jab"
	return ["jab","swing","kick"][maxi(0,combo-1)]

func start_attack() -> void:
	combo = combo%3+1 if combo_window > 0 else 1
	attack_weapon = weapon
	visual_weapon = weapon
	swing_duration = float(Catalog.WEAPONS[attack_weapon].time) if attack_weapon != "" else [.3,.38,.46][combo-1]
	swing_left = swing_duration
	combo_window = 0
	swing_fired = false
	swing_serial += 1
	show_pose(attack_pose())
	body.frame = 0
	arena.sound(["jab","swing","kick"][combo-1],position)

func equip(kind: String) -> void:
	weapon = kind
	durability = Catalog.WEAPONS[kind].uses
	pickup_time = .3
	combo = 0
	combo_window = 0
	arena.sound("pickup",position)

func spend_weapon() -> void:
	if weapon == "": return
	durability -= 1
	if durability <= 0:
		arena.fx("capabilities_fx","unlock_sparkle",position-Vector2(0,40),.5,.5)
		weapon = ""
		durability = 0
		arena.sound("break",position)
		arena.toast("WEAPON BROKEN — back to combos")

func apply_effect(kind: String) -> void:
	if kind=="random_buff": kind=["review_shield","speed_surge","health_capsule"][arena.rng.randi_range(0,2)]
	if kind == "health_capsule": hp = mini(3,hp+1)
	elif kind == "review_shield": shield = true
	elif kind == "score_coin": arena.score += 100
	else:
		effects[kind] = {"speed_surge":8.0,"confused":3.0,"strength_down":5.0,"overwhelmed":5.0}.get(kind,4.0)

func take_hit(source: Vector2, status := "", force := 180.0) -> bool:
	if hp <= 0 or invulnerable > 0 or height > 38: return false
	invulnerable = 1.25
	if shield:
		shield = false
		arena.toast("REVIEW SHIELD BLOCKED A HIT")
		return false
	hp -= 1
	arena.player_damaged()
	stagger = .32
	swing_left = 0
	queued = false
	combo = 0
	combo_window = 0
	knock = (position-source).normalized()*force
	if status != "": apply_effect(status)
	arena.sound("hurt",position)
	arena.shake = 8
	if hp <= 0:
		held.hide()
		body.position.x=0
		show_pose("death",true)
		arena.game_over()
	return true
