extends "res://scenes/runner/powerups/power_up_visual_base.gd"
const Art = preload("res://scenes/runner/boss/tool_art.gd")
var _art: Art

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func on_spawned() -> void:
	super()
	if _art == null:
		_art = Art.new()
		add_child(_art)
		_art.build(&"review_comment")
	_art.reset()

func on_collected() -> void:
	if _art != null: _art.collect()
	hide()
