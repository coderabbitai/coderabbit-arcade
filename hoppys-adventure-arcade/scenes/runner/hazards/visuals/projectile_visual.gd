extends "res://scenes/runner/hazards/hazard_visual_base.gd"
const Rig = preload("res://scenes/runner/hazards/visuals/hazard_art.gd")
var _art: Rig

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func on_spawned() -> void:
	if _art != null:
		remove_child(_art)
		_art.queue_free()
	_art = Rig.new()
	add_child(_art)
	_art.build(&"projectile",variant,hitbox_size,hitbox_offset)
	show()

func _process(delta: float) -> void:
	if _art != null: _art.advance(delta*maxf(closing_speed/20.0,1.0))

func on_hit_player() -> void:
	hide()

func on_cleared() -> void:
	hide()
