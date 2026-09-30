extends "res://modes/platformer/enemy.gd"
## Encounter-controlled boss. Movement stops during readable attack commitments.
signal fired(start: Vector2, direction: Vector2)
var active := false
var fired_this_cycle := false
var aim := Vector2.LEFT
var attack_name := ""
func _physics_process(dt: float) -> void:
	if dead or not active or player.hp <= 0:
		return
	phase += dt
	if phase >= 6.0:
		phase = fmod(phase, 6.0)
		fired_this_cycle = false
	hit_flash = maxf(0, hit_flash - dt)
	sprite.modulate = Color(2, 1, 1) if hit_flash > 0 else Color.WHITE
	if phase < 1.6:
		attack_name = "TRACKING"
		var distance := player.position.x - position.x
		if absf(distance) > 125:
			position.x = clampf(position.x + signf(distance) * 100 * dt, 4360, 4840)
		sprite.play("idle")
	elif phase < 2.4:
		attack_name = "SLAM — JUMP!"
		sprite.play("windup")
	elif phase < 2.8:
		attack_name = "SLAM"
		sprite.play("slam")
		if absf(player.position.x - position.x) < 230 and player.position.y > position.y - 40:
			player.damage(position.x)
	elif phase < 3.6:
		attack_name = "RECOVERING"
		sprite.play("idle")
	elif phase < 4.3:
		attack_name = "BRANCH VOLLEY — DODGE!"
		sprite.play("windup")
		aim = (player.position + Vector2(0, -35) - (position + Vector2(0, -90))).normalized()
	else:
		attack_name = "RECOVERING"
		sprite.play("idle")
		if not fired_this_cycle:
			fired_this_cycle = true
			for angle in [-0.24, 0.0, 0.24]:
				fired.emit(position + Vector2(0, -90), aim.rotated(angle))
	queue_redraw()
	if hurtbox.overlaps_body(player):
		if player.velocity.y > 120 and player.position.y < position.y - 90:
			take_hit()
			player.velocity.y = -440
		else:
			player.damage(position.x)
func take_hit() -> void:
	if active:
		super.take_hit()
		queue_redraw()
func _draw() -> void:
	if not active or dead: return
	if phase >= 1.6 and phase < 2.8:
		var color := Color(1, 0.65, 0.2, 0.4) if phase < 2.4 else Color(1, 0.25, 0.2, 0.8)
		draw_rect(Rect2(-230, -8, 460, 8), color)
		for x in range(-230, 231, 46):
			draw_line(Vector2(x, -8), Vector2(x + 12, -20), color, 3)
	elif phase >= 3.6 and phase < 4.3:
		var start := Vector2(0, -90)
		draw_circle(start, 15 + sin(phase * 25) * 3, Color("b9a3ff"), false, 3)
		for angle in [-0.24, 0.0, 0.24]:
			draw_line(start, start + aim.rotated(angle) * 85, Color(0.8, 0.5, 1, 0.65), 2)
