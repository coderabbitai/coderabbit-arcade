extends RefCounted
## Pointer input that hovers controls in headless runs too. Input.parse_input_event() never hovers
## anything headless: the 64x64 headless window's stretch transform scales the event's position,
## and the menu recenters itself in the visible area, so fixed coordinates miss the buttons.
## Pushing the motion to the viewport in its own coordinates, aimed at a control's actual rect,
## hovers it the same way in rendered and headless runs.

## Move the pointer to `point` in the viewport's coordinates, having moved by `relative`. Events
## sent with Input.parse_input_event() wait for the next frame, while push_input() delivers at
## once, so pending ones are flushed first to keep the order the suite sent them in.
static func move(viewport: Viewport, point: Vector2, relative := Vector2(10, 10)) -> void:
	Input.flush_buffered_events()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = relative
	viewport.push_input(motion, true)

## Move the pointer onto the middle of `control`, in viewport coordinates (through any canvas layer
## or camera transform above it).
static func hover(control: Control) -> void:
	move(control.get_viewport(), control.get_global_transform_with_canvas() * (control.size * 0.5))

## The bottom-right corner of the visible area, which no menu button covers.
static func corner(viewport: Viewport) -> Vector2:
	return viewport.get_visible_rect().end - Vector2(8, 8)
