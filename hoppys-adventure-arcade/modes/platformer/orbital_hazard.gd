extends Node2D
const Art = preload("res://modes/platformer/art.gd")
const OrbitalArt = preload("res://modes/platformer/orbital_art.gd")
var kind := "laser"
var clock := 0.0
var state := "off"
var sprite: AnimatedSprite2D
var area: Area2D

func _ready() -> void:
	sprite = OrbitalArt.sprite("hazards", "laser_off" if kind=="laser" else "vent_closed")
	sprite.offset.y = -54
	add_child(sprite)
	area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.add_child(Art.shape(Vector2(24,260) if kind=="laser" else Vector2(240,210),Vector2(0,-130 if kind=="laser" else -105)))
	add_child(area)

## The level calls this before the player tick; pause and retry share its clock ownership.
func tick(dt: float, player: CharacterBody2D) -> void:
	clock += dt
	var phase := fmod(clock,5.2)
	state = "off" if phase < 2.0 else ("warning" if phase < 2.9 else ("active" if phase < 4.5 else "cooldown"))
	if kind == "laser":
		sprite.play("laser_"+state)
		if state=="active" and area.overlaps_body(player): player.damage(position.x)
	else:
		sprite.play("vent_active" if state=="active" else ("vent_warning" if state=="warning" else "vent_closed"))
		if state=="active" and area.overlaps_body(player):
			player.environmental_acceleration += Vector2(clampf(position.x-player.position.x,-100,100)*7,900)
			if absf(player.position.x-position.x)<42 and player.position.y>580:
				player.damage(position.x)
	queue_redraw()

func _draw() -> void:
	if kind=="laser":
		if state=="active":
			draw_line(Vector2(0,-260),Vector2(0,-28),Color(1,.17,.3,.25),28)
			draw_line(Vector2(0,-260),Vector2(0,-28),Color("ff5369"),14)
			draw_line(Vector2(0,-260),Vector2(0,-28),Color("fff2cf"),4)
		elif state=="warning":
			for y in range(-260,-28,24): draw_line(Vector2(0,y),Vector2(0,y+12),Color("ffc769"),3)
	else:
		if state=="warning": draw_rect(Rect2(-48,-8,96,8),Color("ffc769"))
		elif state=="active":
			for i in 3:
				var y := -180.0 + fmod(clock*100+i*50,150)
				draw_line(Vector2(-65,y),Vector2(0,y+20),Color(.2,.9,1,.55),2)
				draw_line(Vector2(65,y),Vector2(0,y+20),Color(.2,.9,1,.55),2)
