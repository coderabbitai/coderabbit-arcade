extends RefCounted
const ROOT := "res://Assets/bay-area-blitz-assets-only/bay_area/"
static func sprite(sheet: String, clip: String, pos := Vector2.ZERO) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = load(ROOT + sheet + ".tres")
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = pos
	s.play(clip)
	return s
static func shape(size: Vector2, pos := Vector2.ZERO) -> CollisionShape2D:
	var c := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	c.shape = rect
	c.position = pos
	return c
