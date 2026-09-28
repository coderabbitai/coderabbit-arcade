extends Node2D
signal defeated(points: int)
const Art = preload("res://modes/platformer/art.gd")
var kind := "glitch_critter"
var hp := 1
var player: CharacterBody2D
var origin := Vector2.ZERO
var radius := 100.0
var phase := 0.0
var hit_flash := 0.0
var dead := false
var telegraph_drawn := false
var sprite: AnimatedSprite2D
var hurtbox: Area2D
func _ready() -> void:
	origin = position
	hp = 8 if kind == "merge_monster" else (2 if kind == "request_reviewer" else 1)
	sprite = Art.sprite(kind, "idle")
	sprite.offset.y = -77 if kind == "merge_monster" else -38
	add_child(sprite)
	hurtbox = Area2D.new()
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 2
	hurtbox.add_child(Art.shape(Vector2(130, 125) if kind == "merge_monster" else Vector2(52, 60), Vector2(0, -60 if kind == "merge_monster" else -30)))
	add_child(hurtbox)
func _physics_process(dt: float) -> void:
	if dead or player.hp <= 0:
		return
	phase += dt
	# Only the boss draws (its slam telegraph); redraw while it shows and once more to clear it.
	if kind == "merge_monster":
		var telegraph := fmod(phase, 3.4) > 1.7 and fmod(phase, 3.4) < 2.9
		if telegraph or telegraph_drawn:
			queue_redraw()
		telegraph_drawn = telegraph
	hit_flash = maxf(0, hit_flash - dt)
	sprite.modulate = Color(2, 1, 1) if hit_flash > 0 else Color.WHITE
	if kind == "merge_monster":
		if absf(player.position.x - position.x) > 650:
			phase = 0
		var cycle := fmod(phase, 3.4)
		sprite.play("windup" if cycle > 1.7 and cycle < 2.5 else ("slam" if cycle >= 2.5 else "idle"))
		if cycle >= 2.5 and cycle < 2.9 and absf(player.position.x - position.x) < 230 and player.position.y > position.y - 40:
			player.damage(position.x)
	else:
		position.x = origin.x + sin(phase * (0.8 if kind == "request_reviewer" else 1.3)) * radius
		sprite.flip_h = cos(phase * (0.8 if kind == "request_reviewer" else 1.3)) > 0
		sprite.play("hurt" if hit_flash > 0 else ("patrol" if kind == "request_reviewer" else "scuttle"))
	if hurtbox.overlaps_body(player):
		if player.velocity.y > 120 and player.position.y < position.y - (90 if kind == "merge_monster" else 40):
			take_hit()
			player.velocity.y = -440
		else:
			player.damage(position.x)
func take_hit() -> void:
	if dead or hit_flash > 0:
		return
	hp -= 1
	hit_flash = 0.22
	if hp <= 0:
		dead = true
		hurtbox.set_deferred("monitorable", false)
		sprite.play("defeat")
		defeated.emit(1000 if kind == "merge_monster" else 100)
		await sprite.animation_finished
		queue_free()

func _draw() -> void:
	if kind != "merge_monster" or dead:
		return
	var cycle := fmod(phase, 3.4)
	if cycle > 1.7 and cycle < 2.9:
		var color := Color(1, 0.65, 0.2, 0.35) if cycle < 2.5 else Color(1, 0.25, 0.2, 0.8)
		draw_rect(Rect2(-230, -8, 460, 8), color)
		for x in range(-230, 231, 46):
			draw_line(Vector2(x, -8), Vector2(x + 12, -20), color, 3)
