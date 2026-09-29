extends Button
## Hover/focus grow. The parent container owns position, size and scale: every re-sort resets scale
## to 1, so the pivot tracks resizes and the target scale is re-applied after each sort.
const ACTIVE_SCALE := 1.05
var motion: Tween
func _ready() -> void:
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	pivot_offset = size * 0.5
	var container := get_parent() as Container
	if container:
		container.sort_children.connect(_restore_scale)
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5
func _target() -> Vector2:
	return Vector2.ONE * (ACTIVE_SCALE if is_hovered() or has_focus() else 1.0)
func _restore_scale() -> void:
	if not (motion and motion.is_running()):
		scale = _target()
func _refresh() -> void:
	if motion:
		motion.kill()
	# The grown button draws over its neighbours instead of under them.
	z_index = 1 if _target().x > 1.0 else 0
	motion = create_tween()
	motion.tween_property(self, "scale", _target(), 0.12)
