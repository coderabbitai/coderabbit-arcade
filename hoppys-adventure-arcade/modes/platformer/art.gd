extends RefCounted
const ROOT := "res://Assets/bay-area-blitz-assets-only/bay_area/"
## Decoded atlas pages for Art.run, once each: get_image() is a GPU readback on this renderer.
static var images := {}
## Repeatable interior textures for Art.run, keyed by crop region and trim.
static var strips := {}
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

## Seamless runs of a cropped kit tile. Butting whole crops side by side shows each one's end
## caps (rounded corners, bolts, ragged edges) as a dark gutter between every tile, so a long
## platform reads as a row of boxes. A run keeps one cap at each end and repeats the painted
## interior between them, so it reads as one piece of any length.

## The crop's interior, `trim.x` texels in from its left edge and `trim.y` from its right, as a
## texture that can repeat.
static func strip(cropped: AtlasTexture, trim: Vector2i) -> ImageTexture:
	var key := "%s %s %s" % [cropped.atlas.resource_path, cropped.region, trim]
	if not strips.has(key):
		if not images.has(cropped.atlas.resource_path):
			images[cropped.atlas.resource_path] = cropped.atlas.get_image()
		var region := Rect2i(cropped.region)
		region.position.x += trim.x
		region.size.x -= trim.x + trim.y
		var page: Image = images[cropped.atlas.resource_path]
		strips[key] = ImageTexture.create_from_image(page.get_region(region))
	return strips[key]

## `cropped` laid across `size` from `pos`: a cap at each end and the interior repeated between.
## Texels are as wide as one crop's when stretched to `tile.x`, so a run matches the tiles it
## replaces, and the run is exactly `size.y` tall, so a thin platform stays thin whatever the kit
## tile's height. A run too short for both caps is the whole crop stretched to fit.
static func run(cropped: AtlasTexture, pos: Vector2, size: Vector2, tile: Vector2,
		trim := Vector2i.ZERO) -> Node2D:
	var group := Node2D.new()
	group.position = pos
	var texels := cropped.region.size
	var scale := Vector2(tile.x / texels.x, size.y / texels.y)
	var caps := Vector2(trim.x, trim.y) * scale.x
	if caps.x + caps.y + scale.x > size.x:
		var whole := Sprite2D.new()
		whole.texture = cropped
		whole.centered = false
		whole.scale = size / texels
		group.add_child(whole)
		return group
	var middle := Sprite2D.new()
	middle.texture = strip(cropped, trim)
	middle.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	middle.centered = false
	middle.position.x = caps.x
	middle.scale = scale
	middle.region_enabled = true
	middle.region_rect = Rect2(0, 0, (size.x - caps.x - caps.y) / scale.x, texels.y)
	group.add_child(middle)
	for side in 2:
		var width := trim.x if side == 0 else trim.y
		if width == 0: continue
		var cap := Sprite2D.new()
		var piece := AtlasTexture.new()
		piece.atlas = cropped.atlas
		var inset := Vector2(0 if side == 0 else texels.x - width, 0)
		piece.region = Rect2(cropped.region.position + inset, Vector2(width, texels.y))
		piece.filter_clip = true
		cap.texture = piece
		cap.centered = false
		cap.position.x = 0.0 if side == 0 else size.x - caps.y
		cap.scale = scale
		group.add_child(cap)
	return group
