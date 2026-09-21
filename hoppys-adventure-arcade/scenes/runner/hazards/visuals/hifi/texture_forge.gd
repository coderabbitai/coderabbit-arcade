extends RefCounted
## One shared 512-square atlas set: RGB albedo, tangent normal, packed roughness.
## Four horizontal tiles: milled plate, diff screen, hazard stripe, code chevrons.
static var _cache: Dictionary = {}
const SIZE := 512

static func maps() -> Dictionary:
	if not _cache.is_empty(): return _cache
	var height := Image.create(SIZE, SIZE, false, Image.FORMAT_RF)
	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rough := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var tile := x / 128
			var u := x % 128
			var v := y % 128
			var grain := fmod(sin(float(x * 73 + y * 927)) * 43758.5, 1.0) * 0.025
			var edge := u < 4 or u > 123 or v < 4 or v > 123
			var rivet := Vector2(u % 112 - 8, v % 112 - 8).length() < 3.0
			var h := 0.5 + grain - (0.22 if edge else 0.0) + (0.20 if rivet else 0.0)
			var glyph := tile == 0 and v >= 49 and v <= 78 and u > 5 and u < 122
			if tile == 1:
				# Diff plus/minus prefixes and deliberately separated code strokes.
				var row := v / 20
				var line_y := v % 20
				glyph = (u > 10 and u < 23 and line_y >= 8 and line_y <= 10) or (row % 2 == 0 and u >= 15 and u <= 17 and line_y > 3 and line_y < 16)
				glyph = glyph or (u > 33 and u < 110 - row * 8 and line_y >= 7 and line_y < 11 and u % 27 > 3)
			elif tile == 2:
				glyph = (u + v) % 40 < 13
			elif tile == 3:
				glyph = absi(u % 24 - 12 - absi(v % 32 - 16) / 2) < 3
			var tone := 0.34 + grain + (0.15 if rivet else 0.0)
			albedo.set_pixel(x, y, Color(tone, tone, tone, 1.0 if glyph else 0.0))
			height.set_pixel(x, y, Color(h + (0.03 if glyph else 0.0), 0, 0))
			rough.set_pixel(x, y, Color(0.31 if edge else 0.40 + grain, 0, 0))
	for y in SIZE:
		for x in SIZE:
			var dx := 0.0
			var dy := 0.0
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					var h := height.get_pixel(posmod(x+ox, SIZE), posmod(y+oy, SIZE)).r
					dx += h * float(ox) * (2.0 if oy == 0 else 1.0)
					dy += h * float(oy) * (2.0 if ox == 0 else 1.0)
			var n := Vector3(-dx * 1.8, -dy * 1.8, 1).normalized()
			normal.set_pixel(x, y, Color(n.x*0.5+0.5, n.y*0.5+0.5, n.z*0.5+0.5))
	albedo.generate_mipmaps()
	normal.generate_mipmaps(true)
	rough.generate_mipmaps()
	_cache = {"albedo": ImageTexture.create_from_image(albedo), "normal": ImageTexture.create_from_image(normal), "roughness": ImageTexture.create_from_image(rough)}
	return _cache

static var _border: ImageTexture
static func marker_border() -> ImageTexture:
	if _border != null: return _border
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,0))
	for y in 256:
		for x in 256:
			if x < 8 or x > 247 or y < 8 or y > 247:
				image.set_pixel(x,y,Color.WHITE)
	image.generate_mipmaps()
	_border = ImageTexture.create_from_image(image)
	return _border
