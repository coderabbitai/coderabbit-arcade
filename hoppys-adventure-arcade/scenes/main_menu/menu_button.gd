extends Button
var motion: Tween
func _ready() -> void:
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	resized.connect(func(): pivot_offset = size * 0.5)
func _refresh() -> void:
	if motion:
		motion.kill()
	motion = create_tween()
	motion.tween_property(self, "scale", Vector2.ONE * (1.05 if is_hovered() or has_focus() else 1.0), 0.12)
