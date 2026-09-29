extends "res://scenes/runner/powerups/power_up_visual_base.gd"
const Art = preload("res://scenes/runner/powerups/visuals/power_up_art.gd")
var _art: Art

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func on_spawned() -> void:
	super()
	if _art == null:
		_art = Art.new()
		_art.name = "Artwork"
		add_child(_art)
		_art.build(kind)
	_art.reset()

func on_collected() -> void:
	if _art != null:
		_art.collect()
