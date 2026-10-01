extends StaticBody2D
const Art = preload("res://modes/platformer/art.gd")
const ForestArt = preload("res://modes/platformer/enchanted_art.gd")
var width := 180.0
var state := "intact"
var clock := 0.0
var visual: Sprite2D
var collider: CollisionShape2D

func _ready() -> void:
	collision_layer = 1
	collider = Art.shape(Vector2(width,12),Vector2(0,6))
	collider.one_way_collision = true
	add_child(collider)
	visual = Sprite2D.new()
	visual.centered = false
	add_child(visual)
	_show("branch_intact")

func _show(clip: String) -> void:
	visual.texture = ForestArt.crop("hazards",clip)
	visual.position = Vector2(-width/2,0)
	visual.scale = Vector2(width,48)/visual.texture.get_size()

func tick(dt: float, player: CharacterBody2D) -> void:
	var on_top := absf(player.position.x-position.x) < width/2+15 and absf(player.position.y-position.y) < 6 and player.is_on_floor()
	if state == "intact":
		if on_top:
			state = "warning"
			clock = 0
			_show("branch_warning")
	else:
		clock += dt
		if state == "warning" and clock >= 0.7:
			state = "breaking"
			clock = 0
			collider.set_deferred("disabled",true)
			_show("branch_break")
		elif state == "breaking" and clock >= 0.25:
			state = "gone"
			clock = 0
			_show("branch_fall")
		elif state == "gone":
			visual.position.y = minf(95,clock*140)
			visual.modulate.a = maxf(0,1-clock*2)
			# Never rematerialize into Hoppy's body.
			var occupied := absf(player.position.x-position.x) < width/2+20 and player.position.y > position.y-10 and player.position.y < position.y+80
			if clock >= 3.5 and not occupied:
				state = "intact"
				clock = 0
				visual.modulate = Color.WHITE
				collider.set_deferred("disabled",false)
				_show("branch_intact")
