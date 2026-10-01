extends "res://modes/platformer/orbital_projectile.gd"
const ForestArt = preload("res://modes/platformer/enchanted_art.gd")

func _ready() -> void:
	collision_layer = 0
	collision_mask = 3
	add_child(Art.shape(Vector2(38,24)))
	var visual := Sprite2D.new()
	visual.texture = ForestArt.crop("hazards","shockwave")
	visual.scale = Vector2(64,32)/visual.texture.get_size()
	visual.flip_h = velocity.x > 0
	add_child(visual)
	body_entered.connect(_hit)
