extends CharacterBody2D
const Art = preload("res://modes/beatem_up/art.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const BASE_FRAMES = preload("res://Assets/bay-area-blitz-assets-only/bay_area/hoppy/platformer.tres")
const COMBAT_FRAMES = preload("res://Assets/code-city-brawl-player/combat.tres")
var arena: Node2D
var body: AnimatedSprite2D
var held: AnimatedSprite2D
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

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	add_child(Art.shadow())
	body = AnimatedSprite2D.new()
	body.sprite_frames = COMBAT_FRAMES
	body.offset = Vector2(0,-38)
	body.scale = Vector2.ONE * 1.55
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(body)
	held = Art.sprite("weapons","debug_stick",.62,false)
	add_child(held)
	held.hide()

func _physics_process(dt: float) -> void:
	if not arena.playing: return
	tick(dt)

func tick(dt: float) -> void:
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
		if absf(movement.x) > .15: facing = signf(movement.x)
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
	var speed := 240.0
	if effects.has("speed_boost"): speed *= 1.4
	if effects.has("slow"): speed *= .6
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
	elif swing_left > 0: pose = ["jab","swing","kick"][combo-1]
	elif pickup_time > 0: pose = "pickup"
	elif height > 0: pose = "jump"
	elif movement.length() > .1:
		if absf(movement.y) > absf(movement.x)*1.3: pose = "walk_up" if movement.y < 0 else "walk_down"
		else:
			pose = "run"
			base = true
	show_pose(pose,base)
	held.visible = weapon != ""
	if held.visible:
		held.play(weapon)
		held.flip_h = facing < 0
		held.position = Vector2(facing*34,-height-35)
		held.rotation = facing * (-.6 if swing_left > swing_duration*.55 else .5) if swing_left > 0 else -.25*facing

func show_pose(pose: String, base := false) -> void:
	var frames: SpriteFrames = BASE_FRAMES if base else COMBAT_FRAMES
	if body.sprite_frames != frames: body.sprite_frames = frames
	body.flip_h = facing < 0
	body.play(pose)

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

func start_attack() -> void:
	combo = combo%3+1 if combo_window > 0 else 1
	attack_weapon = weapon if weapon != "firewall_shield" else ""
	if attack_weapon != "": combo = 3
	swing_duration = float(Catalog.WEAPONS[attack_weapon].time) if attack_weapon != "" else [.3,.38,.46][combo-1]
	swing_left = swing_duration
	combo_window = 0
	swing_fired = false
	swing_serial += 1
	show_pose(["jab","swing","kick"][combo-1])
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
		arena.fx("weapons",weapon+"_broken",position-Vector2(0,40),.7,.7)
		weapon = ""
		durability = 0
		arena.sound("break",position)
		arena.toast("WEAPON BROKEN — back to combos")

func apply_effect(kind: String) -> void:
	if kind == "coffee": hp = mini(3,hp+1)
	elif kind == "damage_shield": shield = true
	elif kind == "commit_token": arena.score += 100
	else: effects[kind] = 4.0 if kind in ["confused","slow","strength_down"] else 8.0

func take_hit(source: Vector2, status := "", force := 180.0) -> bool:
	if hp <= 0 or invulnerable > 0 or height > 38: return false
	invulnerable = 1.25
	if shield:
		shield = false
		arena.toast("APPROVAL SHIELD BLOCKED A HIT")
		return false
	if weapon == "firewall_shield":
		spend_weapon()
		return false
	hp -= 1
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
		show_pose("death",true)
		arena.game_over()
	return true
