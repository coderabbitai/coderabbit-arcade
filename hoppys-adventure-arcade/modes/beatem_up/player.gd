extends CharacterBody2D
const Art = preload("res://modes/beatem_up/art.gd")
const Catalog = preload("res://modes/beatem_up/catalog.gd")
const BASE_FRAMES = preload("res://Assets/bay-area-blitz-assets-only/bay_area/hoppy/platformer.tres")
const COMBAT_FRAMES = preload("res://Assets/code-city-brawl-player/combat.tres")
const WeaponRig = preload("res://modes/beatem_up/weapon_rig.gd")
const BODY_OFFSET := Vector2(0,-38)
## Walking speed in px/s; the armed run's foot cadence is calibrated for it.
const RUN_SPEED := 240.0
## Poses with a baked armed clip. The three attack poses become step1..3 by combo. A sheet
## without one of these clips (walk_up and walk_down are newer) falls back to the unarmed pose.
const ARMED_CLIPS := {"idle":"hold_idle","run":"run","pickup":"equip","hurt":"hurt","walk_up":"walk_up","walk_down":"walk_down"}
const ATTACK_POSES := ["jab","swing","kick"]
var arena: Node2D
var body: AnimatedSprite2D
var held: Node2D
var visual_weapon := ""
var block_time := 0.0
var hp := 3
var facing := 1.0
## The way the stick last pointed past the deadzone. A swing keeps its facing, so a turn asked
## for mid-swing waits here for the swing's end or the next step; 0 once idle with no input.
var steer := 0.0
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
var armed := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	add_child(Art.shadow())
	body = AnimatedSprite2D.new()
	body.sprite_frames = COMBAT_FRAMES
	body.offset = BODY_OFFSET
	body.scale = Vector2.ONE * 1.55
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(body)
	held = WeaponRig.new()
	held.body = body
	add_child(held)
	held.hide()

func _physics_process(dt: float) -> void:
	if not arena.playing: return
	tick(dt)

func tick(dt: float) -> void:
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
		if absf(movement.x) > .15: steer = signf(movement.x)
		if steer != 0 and swing_left <= 0: facing = steer
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
			if steer != 0: facing = steer
			if queued:
				queued = false
				start_attack()
	elif absf(movement.x) <= .15: steer = 0.0
	var speed := RUN_SPEED
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
	var kind := shown_weapon()
	held.visible = kind != ""
	var pose := "idle"
	var base := false
	if stagger > 0: pose = "hurt"
	elif swing_left > 0: pose = attack_pose()
	elif block_time > 0 and armed_sheet() != null: pose = "hurt"
	elif pickup_time > 0: pose = "pickup"
	elif height > 0: pose = "jump"
	elif movement.length() > .1:
		if absf(movement.y) > absf(movement.x)*1.3: pose = "walk_up" if movement.y < 0 else "walk_down"
		else:
			pose = "run"
			base = true
	show_pose(pose,base)
	# The stride keeps pace with travel under analog input and speed effects, so feet don't slide.
	body.speed_scale = movement.length()*speed/RUN_SPEED if pose in ["run","walk_up","walk_down"] else 1.0
	var attacking := swing_left>0
	var progress := clampf(1.0-swing_left/swing_duration,0,1)
	body.position.x=0
	if attacking and armed:
		# The baked step's windup, contact and follow-through; the hit at .44 lands on contact.
		body.pause()
		body.frame=0 if progress<.3 else 1 if progress<.64 else 2
	elif attacking and visual_weapon!="" and visual_weapon!="firewall_shield":
		# Legacy rig: match Hoppy's hands to the weapon's windup/contact/recovery timeline.
		body.pause()
		body.frame=0 if progress<.3 or progress>.82 else 1
		body.position.x=facing*sin(progress*PI)*5
	held.position=Vector2(0,-height)
	held.scale=Vector2(facing,1)
	held.animate(kind,combo,progress,attacking,movement,dt,block_time)

## The weapon Hoppy is drawn with: the swing's weapon mid-attack, else the one he holds.
func shown_weapon() -> String:
	return visual_weapon if swing_left > 0 else weapon

## Hoppy's baked sheet holding the shown weapon, or null: unarmed, no sheet yet (the
## legacy rig draws it), or the arena hid the weapon with held.hide() (finisher, death).
func armed_sheet() -> SpriteFrames:
	var kind := shown_weapon()
	return Art.armed(kind) if kind != "" and held.visible else null

func show_pose(pose: String, base := false) -> void:
	# Until the combat sheet has its victory cheer, the jump pose stands in.
	if pose=="victory" and not COMBAT_FRAMES.has_animation("victory"): pose = "jump"
	var sheet := armed_sheet()
	var clip: String = ARMED_CLIPS.get(pose,"")
	if swing_left > 0 and pose in ATTACK_POSES: clip = "step%d" % combo
	armed = sheet != null and sheet.has_animation(clip)
	var frames: SpriteFrames = sheet if armed else BASE_FRAMES if base else COMBAT_FRAMES
	if body.sprite_frames != frames: body.sprite_frames = frames
	body.flip_h = facing < 0
	if armed:
		# flip_h mirrors the texture inside its rect, not the offset: mirror the pivot shift too.
		var shift := Art.armed_offset(shown_weapon())
		body.offset = Vector2(-shift.x if body.flip_h else shift.x, shift.y)
		held.clear()
	else: body.offset = BODY_OFFSET
	body.play(clip if armed else pose)

## Arena position of the weapon tip at contact, where the swing effect is anchored.
func tip_position() -> Vector2:
	var local: Vector2 = held.tip_at(shown_weapon(),combo)
	return position+held.position+Vector2(local.x*facing,local.y)

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
	if visual_weapon!="" and visual_weapon!="firewall_shield":
		return "swing" if visual_weapon in ["refactor_hammer","git_branch"] or combo!=1 else "jab"
	return ["jab","swing","kick"][maxi(0,combo-1)]

func start_attack() -> void:
	# Each swing starts facing the way the stick last asked, so a buffered step can turn.
	if steer != 0: facing = steer
	combo = combo%3+1 if combo_window > 0 else 1
	attack_weapon = weapon if weapon != "firewall_shield" else ""
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
		block_time = .28
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
		held.hide()
		body.position.x=0
		arena.knockout(source)
	return true
