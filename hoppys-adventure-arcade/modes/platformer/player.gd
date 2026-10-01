extends CharacterBody2D
signal health_changed
signal died
signal jumped
signal hurt
signal swiped
const Art = preload("res://modes/platformer/art.gd")
const SPEED := 310.0
const JUMP := -740.0
var input_lock := 0.0
var hp := 3
var shield := false
var boost := 0.0
var invulnerable := 0.0
var hurt_time := 0.0
var attack_time := 0.0
var coyote := 0.0
var buffer := 0.0
var facing := 1.0
var hit_targets: Array[Node] = []
## Set by the owning level before the player's physics tick; defaults preserve Bay Area.
var zero_gravity := false
var environmental_acceleration := Vector2.ZERO
var sprite: AnimatedSprite2D
var swipe: Area2D
func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 8
	platform_floor_layers = 8
	platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_ADD_UPWARD_VELOCITY
	add_child(Art.shape(Vector2(34, 68), Vector2(0, -34)))
	sprite = Art.sprite("hoppy/platformer", "idle")
	sprite.offset.y = -40
	add_child(sprite)
	swipe = Area2D.new()
	swipe.collision_layer = 0
	swipe.collision_mask = 4
	swipe.add_child(Art.shape(Vector2(92, 72)))
	add_child(swipe)
func _physics_process(dt: float) -> void:
	if hp <= 0:
		return
	input_lock = maxf(0, input_lock - dt)
	invulnerable = maxf(0, invulnerable - dt)
	boost = maxf(0, boost - dt)
	hurt_time = maxf(0, hurt_time - dt)
	attack_time = maxf(0, attack_time - dt)
	coyote = 0.12 if is_on_floor() else maxf(0, coyote - dt)
	buffer = maxf(0, buffer - dt)
	if input_lock <= 0 and Input.is_action_just_pressed("jump"):
		buffer = 0.14
	if buffer > 0 and coyote > 0:
		jumped.emit()
		velocity.y = JUMP
		buffer = 0
		coyote = 0
	if not zero_gravity and Input.is_action_just_released("jump") and velocity.y < -240:
		velocity.y = -240
	if zero_gravity:
		var thrust := 0.0
		if input_lock <= 0:
			thrust = Input.get_action_strength("move_down") - maxf(Input.get_action_strength("jump"), Input.get_action_strength("move_up"))
		# Normal-gravity jump impulses and fall speed do not carry into assisted zero-g motion.
		velocity.y = clampf(velocity.y, -230.0, 230.0)
		velocity.y = move_toward(velocity.y, thrust * 230, (700 if thrust != 0 else 260) * dt)
	else:
		velocity.y = minf(900, velocity.y + 1600 * dt)
	if hurt_time <= 0:
		var direction := Input.get_axis("move_left", "move_right")
		velocity.x = move_toward(velocity.x, direction * SPEED * (1.35 if boost > 0 else 1.0), 2400 * dt)
		if direction != 0:
			facing = signf(direction)
		if input_lock <= 0 and Input.is_action_just_pressed("attack") and attack_time <= 0:
			attack_time = 0.36
			hit_targets.clear()
			sprite.stop()
			swiped.emit()
	velocity += environmental_acceleration * dt
	swipe.position = Vector2(facing * 54, -38)
	if attack_time > 0.12 and attack_time < 0.30:
		for area in swipe.get_overlapping_areas():
			var target := area.get_parent()
			if target.has_method("take_hit") and target not in hit_targets:
				hit_targets.append(target)
				target.take_hit()
	move_and_slide()
	sprite.flip_h = facing < 0
	sprite.modulate = Color(0.6, 1, 0.8) if boost > 0 or shield else Color.WHITE
	sprite.modulate.a = 0.4 if invulnerable > 0 and fmod(invulnerable, 0.16) < 0.08 else 1.0
	var clip := "idle"
	if hurt_time > 0: clip = "hurt"
	elif attack_time > 0: clip = "attack"
	elif not is_on_floor(): clip = "jump_rise" if velocity.y < 0 else "jump_fall"
	elif absf(velocity.x) > 10: clip = "run"
	sprite.play(clip)
	if position.y > 850:
		hp = 0
		health_changed.emit()
		sprite.play("death")
		died.emit()
func damage(source_x: float) -> bool:
	if hp <= 0 or invulnerable > 0 or boost > 0:
		return false
	invulnerable = 1.2
	if shield:
		shield = false
		health_changed.emit()
		return false
	hp -= 1
	hurt.emit()
	hurt_time = 0.3
	attack_time = 0
	velocity = Vector2(340 * (-1 if source_x >= position.x else 1), -230)
	health_changed.emit()
	if hp == 0:
		sprite.play("death")
		died.emit()
	return true
func heal(amount: int) -> void:
	hp = mini(3, hp + amount)
	health_changed.emit()
