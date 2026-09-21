extends Control
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var segments := 24
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
func _draw() -> void:
	for i in range(1, segments):
		var x := size.x * i / segments
		draw_line(Vector2(x, 2), Vector2(x, size.y-2), Palette.NAVY_BG, 3)
	draw_line(Vector2(2, 3), Vector2(size.x-2, 3), Color(Palette.CREAM, 0.25), 1)
