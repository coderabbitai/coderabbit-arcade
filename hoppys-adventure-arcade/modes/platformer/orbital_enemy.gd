extends "res://modes/platformer/enemy.gd"
const OrbitalArt = preload("res://modes/platformer/orbital_art.gd")
signal fired(start: Vector2, direction: Vector2)
var cooldown := 1.0
var attack_clock := -1.0
var aim := Vector2.LEFT
var dive_target := Vector2.ZERO

func _ready() -> void:
	origin = position
	hp = 1 if kind == "security_drone" else 2
	sprite = OrbitalArt.sprite(kind, "hover" if kind == "security_drone" else "idle")
	sprite.offset.y = 0 if kind == "security_drone" else -38
	add_child(sprite)
	hurtbox = Area2D.new()
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 2
	hurtbox.add_child(Art.shape(Vector2(48, 36) if kind == "security_drone" else Vector2(44, 54), Vector2.ZERO if kind == "security_drone" else Vector2(0, -27)))
	add_child(hurtbox)

func _physics_process(dt: float) -> void:
	if dead or player.hp <= 0: return
	hit_flash = maxf(0, hit_flash - dt)
	sprite.modulate = Color(2, 1, 1) if hit_flash > 0 else Color.WHITE
	if absf(player.position.x - position.x) > 700: return
	phase += dt
	cooldown -= dt
	if attack_clock < 0 and cooldown <= 0 and absf(player.position.x - position.x) < 300:
		attack_clock = 0
		dive_target = player.position + Vector2(0, -30)
		aim = (dive_target - (position + Vector2(0, -32))).normalized()
		sprite.flip_h = aim.x > 0
	if attack_clock >= 0:
		var before := attack_clock
		attack_clock += dt
		if kind == "rogue_ai":
			sprite.play("attack_warning" if attack_clock < 0.75 else ("attack" if attack_clock < 0.95 else "recover"))
			if before < 0.75 and attack_clock >= 0.75:
				fired.emit(position + Vector2(signf(aim.x) * 26, -32), aim)
			if attack_clock > 1.5:
				attack_clock = -1
				cooldown = 2.3
		else:
			if attack_clock < 0.8: sprite.play("ambush_warning")
			elif attack_clock < 1.4:
				sprite.play("dive")
				position = position.move_toward(dive_target, 330 * dt)
			else:
				sprite.play("recover")
				position = position.move_toward(origin, 180 * dt)
				if position.distance_to(origin) < 2:
					attack_clock = -1
					cooldown = 2.4
	else:
		if kind == "rogue_ai":
			position.x = move_toward(position.x, origin.x + sin(phase) * 65, 65 * dt)
			sprite.flip_h = cos(phase) > 0
			sprite.play("walk")
		else:
			position = origin + Vector2(sin(phase) * 35, sin(phase * 2) * 10)
			sprite.play("hover")
	if hit_flash > 0: sprite.play("hurt")
	if hurtbox.overlaps_body(player):
		var top := position.y - (12 if kind == "security_drone" else 38)
		if player.velocity.y > 120 and player.position.y < top:
			take_hit()
			player.velocity.y = -440
		else: player.damage(position.x)
	queue_redraw()

func _draw() -> void:
	if dead or attack_clock < 0: return
	if kind == "rogue_ai" and attack_clock < 0.75:
		draw_line(Vector2(0,-32), Vector2(0,-32) + aim * 115, Color(1,.7,.2,.7), 2)
	elif kind == "security_drone" and attack_clock < 0.8:
		draw_line(Vector2.ZERO, dive_target-position, Color(1,.7,.2,.5), 2)
		draw_circle(dive_target-position, 20, Color("ffc769"), false, 2)
