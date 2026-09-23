extends RefCounted
## Original vector paths rasterized analytically at 24 x 32 pixels per glyph.
## Padded cells and mipmaps keep strokes antialiased without block-font upscaling.
const CELL := Vector2i(24, 32)
const RAIN_LAYERS := 3
static var _texture: ImageTexture
const PATHS := ["", "5,2 5,10;5,13 5,14", "3,2 3,5;7,2 7,5", "3,2 3,14;7,2 7,14;1,6 9,6;1,10 9,10", "9,3 1,3 1,8 9,8 9,13 1,13;5,1 5,15", "1,14 9,2;1,2 3,2 3,4 1,4 1,2;7,12 9,12 9,14 7,14 7,12", "9,14 2,7 2,3 5,2 7,4 1,11 3,14 6,14 9,9", "5,2 5,5", "7,2 3,5 3,11 7,14", "3,2 7,5 7,11 3,14", "2,5 8,11;8,5 2,11;5,3 5,13", "1,8 9,8;5,4 5,12", "5,12 3,15", "1,8 9,8", "5,13 5,14", "1,14 9,2", "2,2 8,2 9,4 9,12 8,14 2,14 1,12 1,4 2,2;2,12 8,4", "3,4 5,2 5,14;2,14 8,14", "1,4 2,2 8,2 9,4 9,6 1,14 9,14", "1,2 9,2 6,7 9,9 9,12 7,14 1,14", "7,14 7,2 1,10 10,10", "9,2 1,2 1,7 7,7 9,9 9,12 7,14 1,14", "9,2 3,2 1,5 1,12 3,14 7,14 9,12 9,9 7,7 1,7", "1,2 9,2 3,14", "3,2 7,2 9,4 9,6 1,10 1,12 3,14 7,14 9,12 9,10 1,6 1,4 3,2", "9,9 3,9 1,7 1,4 3,2 7,2 9,4 9,12 7,14 1,14", "5,5 5,6;5,11 5,12", "5,5 5,6;5,11 3,14", "8,3 2,8 8,13", "1,6 9,6;1,10 9,10", "2,3 8,8 2,13", "1,4 3,2 7,2 9,4 9,6 5,9 5,10;5,13 5,14", "9,13 3,14 1,12 1,4 3,2 7,2 9,4 9,10 5,10 5,6 9,6", "1,14 1,6 5,2 9,6 9,14;1,9 9,9", "1,14 1,2 7,2 9,4 9,6 7,8 1,8;7,8 9,10 9,12 7,14 1,14", "9,3 7,2 3,2 1,4 1,12 3,14 7,14 9,13", "1,14 1,2 6,2 9,5 9,11 6,14 1,14", "9,2 1,2 1,14 9,14;1,8 7,8", "9,2 1,2 1,14;1,8 7,8", "9,3 7,2 3,2 1,4 1,12 3,14 9,14 9,8 5,8", "1,2 1,14;9,2 9,14;1,8 9,8", "2,2 8,2;5,2 5,14;2,14 8,14", "9,2 9,12 7,14 3,14 1,12", "1,2 1,14;9,2 1,9 9,14", "1,2 1,14 9,14", "1,14 1,2 5,8 9,2 9,14", "1,14 1,2 9,14 9,2", "3,2 7,2 9,4 9,12 7,14 3,14 1,12 1,4 3,2", "1,14 1,2 7,2 9,4 9,7 7,9 1,9", "3,2 7,2 9,4 9,12 7,14 3,14 1,12 1,4 3,2;6,11 10,15", "1,14 1,2 7,2 9,4 9,7 7,9 1,9;5,9 9,14", "9,3 7,2 3,2 1,4 1,6 9,10 9,12 7,14 3,14 1,13", "1,2 9,2;5,2 5,14", "1,2 1,12 3,14 7,14 9,12 9,2", "1,2 5,14 9,2", "1,2 2,14 5,9 8,14 9,2", "1,2 9,14;9,2 1,14", "1,2 5,8 9,2;5,8 5,14", "1,2 9,2 1,14 9,14", "7,2 3,2 3,14 7,14", "1,2 9,14", "3,2 7,2 7,14 3,14", "1,6 5,2 9,6", "1,14 9,14"]

static func texture() -> ImageTexture:
	if _texture != null: return _texture
	var image := Image.create(CELL.x * 8, CELL.y * 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	for glyph in 64:
		var segments: Array[Vector4] = []
		for stroke in PATHS[glyph].split(";", false):
			var previous := Vector2.ZERO
			var first := true
			for point in stroke.split(" ", false):
				var xy: PackedStringArray = point.split(",")
				var current := Vector2(float(xy[0]), float(xy[1])) * 1.65 + Vector2(3, 2)
				if not first: segments.append(Vector4(previous.x, previous.y, current.x, current.y))
				previous = current
				first = false
		for y in CELL.y:
			for x in CELL.x:
				var distance := 100.0
				var p := Vector2(x + 0.5, y + 0.5)
				for segment in segments:
					var a := Vector2(segment.x, segment.y)
					var ab := Vector2(segment.z, segment.w) - a
					distance = minf(distance, (p - a - ab * clampf((p - a).dot(ab) / ab.length_squared(), 0, 1)).length())
				var alpha := 1.0 - smoothstep(0.80, 1.60, distance)
				image.set_pixel((glyph % 8) * CELL.x + x, (glyph / 8) * CELL.y + y, Color(1, 1, 1, alpha))
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture
