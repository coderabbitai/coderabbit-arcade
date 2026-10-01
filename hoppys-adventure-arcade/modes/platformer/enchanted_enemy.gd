extends "res://modes/platformer/enemy.gd"
const ForestArt = preload("res://modes/platformer/enchanted_art.gd")
var cooldown := 1.0
var attack_clock := -1.0
var direction := -1.0

func _ready() -> void:
	origin = position
	hp = 2 if kind == "bloat_troll" else 1
	radius = 65
	sprite = ForestArt.sprite(kind, "idle")
	sprite.offset.y = -58 if kind == "bloat_troll" else -38
	sprite.scale = Vector2.ONE * (1.45 if kind == "bloat_troll" else 1.1)
	add_child(sprite)
	hurtbox = Area2D.new()
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 2
	var size := Vector2(84, 88) if kind == "bloat_troll" else Vector2(40, 50)
	hurtbox.add_child(Art.shape(size, Vector2(0, -size.y / 2)))
	add_child(hurtbox)

func _physics_process(dt: float) -> void:
	if dead or player.hp <= 0: return
	hit_flash = maxf(0, hit_flash - dt)
	sprite.modulate = Color(2, 1, 1) if hit_flash > 0 else Color.WHITE
	if absf(player.position.x - position.x) > 750: return
	cooldown -= dt
	var troll := kind == "bloat_troll"
	var reach := 125.0 if troll else 85.0
	var warning := 0.95 if troll else 0.6
	var active_end := warning + 0.22
	if attack_clock < 0 and cooldown <= 0 and absf(player.position.x-position.x) < reach+35 and absf(player.position.y-position.y) < 90:
		attack_clock = 0
		direction = 1 if player.position.x > position.x else -1
		sprite.flip_h = direction > 0
	if attack_clock >= 0:
		attack_clock += dt
		var move := "club" if troll else "jab"
		sprite.play(move+"_warning" if attack_clock < warning else (move if attack_clock < active_end else "recover"))
		if attack_clock >= warning and attack_clock < active_end:
			var dx := (player.position.x-position.x)*direction
			if dx >= -15 and dx < reach and player.position.y > position.y-(55 if troll else 38) and player.position.y < position.y+35:
				player.damage(position.x)
		if attack_clock >= active_end + (1.0 if troll else 0.65):
			attack_clock = -1
			cooldown = 1.4
	else:
		phase += dt * (0.6 if troll else 1.1)
		position.x = origin.x + sin(phase)*radius
		sprite.flip_h = cos(phase) > 0
		sprite.play("walk")
	if hit_flash > 0: sprite.play("hurt")
	if hurtbox.overlaps_body(player):
		if player.velocity.y > 120 and player.position.y < position.y-(65 if troll else 32):
			take_hit()
			player.velocity.y = -440
		elif attack_clock < 0 or attack_clock < active_end:
			player.damage(position.x)
	queue_redraw()

func _draw() -> void:
	if dead or attack_clock < 0: return
	var warning := 0.95 if kind == "bloat_troll" else 0.6
	if attack_clock < warning:
		var reach := 125.0 if kind == "bloat_troll" else 85.0
		draw_line(Vector2.ZERO, Vector2(direction*reach, 0), Color("ffc769"), 4)
		draw_circle(Vector2(0, -115 if kind == "bloat_troll" else -65), 5, Color("ffc769"))

func take_hit() -> void:
	super.take_hit()
	queue_redraw()
