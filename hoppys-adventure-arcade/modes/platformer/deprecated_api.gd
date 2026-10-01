extends "res://modes/platformer/enemy.gd"
const OrbitalArt = preload("res://modes/platformer/orbital_art.gd")
signal fired(start: Vector2, direction: Vector2)
const STATES := ["tracking", "cannon_warning", "cannon_fire", "cannon_recover", "slam_warning", "slam", "slam_stalled", "dash_warning", "dash", "dash_brake", "overheat", "vulnerable", "reboot"]
const DURATIONS := [1.0, 0.85, 0.15, 0.7, 0.9, 0.2, 0.9, 0.8, 0.55, 0.8, 0.4, 1.5, 0.5]
var active := false
var state_index := 0
var state_time := 0.0
var attack_name := "AWAITING CONNECTION"
var aim := Vector2.LEFT
var dash_direction := -1.0

func _ready() -> void:
	kind = "deprecated_api"
	hp = 10
	sprite = OrbitalArt.sprite(kind, "idle")
	sprite.offset.y = -77
	add_child(sprite)
	hurtbox = Area2D.new()
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 2
	hurtbox.add_child(Art.shape(Vector2(108,116),Vector2(0,-58)))
	add_child(hurtbox)

func state() -> String:
	return STATES[state_index]

func _physics_process(dt: float) -> void:
	if dead or not active or player.hp <= 0: return
	hit_flash = maxf(0, hit_flash-dt)
	state_time += dt
	if state_time >= DURATIONS[state_index]:
		_enter_state((state_index+1) % STATES.size())
	var current := state()
	attack_name = {"tracking":"LEGACY ROUTINE", "cannon_warning":"OLD PROTOCOL — DODGE THE SHOT", "slam_warning":"STALLED CALL — JUMP!", "dash_warning":"RETRY STORM — JUMP THE DASH", "vulnerable":"CORE EXPOSED — ATTACK!"}.get(current, current.replace("_", " ").to_upper())
	sprite.play("idle" if current == "tracking" else current)
	sprite.modulate = Color(2,1,1) if hit_flash > 0 else (Color(.65,1,1) if current == "vulnerable" else Color.WHITE)
	if current == "tracking":
		var distance := player.position.x-position.x
		if absf(distance) > 155:
			position.x = clampf(position.x + signf(distance)*90*dt, 4350,4820)
		sprite.flip_h = distance > 0
	elif current == "slam":
		if absf(player.position.x-position.x) < 190 and player.position.y > position.y-45:
			player.damage(position.x)
	elif current == "dash":
		position.x = clampf(position.x + dash_direction*480*dt, 4320,4820)
	if hurtbox.overlaps_body(player):
		if player.velocity.y > 120 and player.position.y < position.y-85:
			take_hit()
			player.velocity.y = -440
		elif current not in ["vulnerable", "overheat", "slam_stalled", "dash_brake", "cannon_recover", "reboot"]:
			player.damage(position.x)
	queue_redraw()

func _enter_state(index: int) -> void:
	state_index = index
	state_time = 0
	if state() == "cannon_warning":
		aim = (player.position + Vector2(0,-35) - (position+Vector2(0,-52))).normalized()
		sprite.flip_h = aim.x > 0
	elif state() == "cannon_fire":
		fired.emit(position + Vector2(signf(aim.x)*55,-52), aim)
	elif state() == "dash_warning":
		dash_direction = 1 if player.position.x > position.x else -1
		sprite.flip_h = dash_direction > 0
	sprite.stop()

func take_hit() -> void:
	if not active or dead or hit_flash > 0: return
	hp -= 1
	hit_flash = .25
	if hp <= 0:
		dead = true
		active = false
		hurtbox.set_deferred("monitorable",false)
		sprite.play("defeat")
		defeated.emit(1000)
		queue_redraw()
		await sprite.animation_finished
		queue_free()

func _draw() -> void:
	if dead or not active: return
	if state() in ["slam_warning", "slam"]:
		draw_rect(Rect2(-190,-8,380,8), Color(1,.65,.2,.5) if state()=="slam_warning" else Color(1,.25,.2,.85))
		for x in range(-190,191,38): draw_line(Vector2(x,-8),Vector2(x+10,-20),Color("ffc769"),3)
	elif state() == "cannon_warning":
		draw_line(Vector2(0,-52),Vector2(0,-52)+aim*180,Color("ffc769"),2)
	elif state() == "dash_warning":
		draw_line(Vector2.ZERO,Vector2(dash_direction*260,0),Color("b695ff"),6)
		var end := Vector2(dash_direction*260,0)
		draw_line(end, end+Vector2(-dash_direction*22,-18),Color("b695ff"),4)
