extends RefCounted
## Host-only raster evidence. Reject blank cards and repeated solid glyph rectangles.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const MAX_OFF_PALETTE := 0.03
const SAMPLE := Rect2i(20, 132, 216, 82)
static func inspect(pixels: Image) -> Dictionary:
	if pixels == null or pixels.is_empty() or pixels.get_size() != Vector2i(256,256):
		return {"passed": false, "cream_pixels": 0, "distinct_mixed_rows": 0}
	var masks := {}
	var cream_pixels := 0
	for y in range(SAMPLE.position.y, SAMPLE.end.y):
		var mask := ""
		var bright := 0
		var dark := 0
		for x in range(SAMPLE.position.x, SAMPLE.end.x):
			var pixel := pixels.get_pixel(x,y)
			var cream := pixel.r > 0.7 and pixel.g > 0.65 and pixel.b > 0.5
			mask += "1" if cream else "0"
			if cream: bright += 1
			if pixel.r < 0.25 and pixel.g < 0.35: dark += 1
		cream_pixels += bright
		if bright >= 8 and dark >= 8: masks[mask] = true
	var palette := inspect_palette(pixels)
	return {"passed": cream_pixels >= 200 and masks.size() >= 8 and palette.passed, "cream_pixels": cream_pixels, "distinct_mixed_rows": masks.size(), "off_palette_ratio": palette.off_palette_ratio}

static func inspect_palette(pixels: Image) -> Dictionary:
	if pixels == null or pixels.is_empty() or pixels.get_size() != Vector2i(256,256):
		return {"passed": false, "off_palette_ratio": 1.0}
	var bright := 0
	var outside := 0
	for y in range(SAMPLE.position.y, SAMPLE.end.y):
		for x in range(SAMPLE.position.x, SAMPLE.end.x):
			var pixel := pixels.get_pixel(x,y)
			if pixel.v < 0.4: continue
			bright += 1
			if pixel.s < 0.35: continue
			var matches := false
			for allowed: Color in [Palette.CREAM,Palette.DANGER,Palette.NAVY_BG,Palette.NAVY,Palette.NAVY_2,Palette.SLATE]:
				var hue_delta := absf(pixel.h-allowed.h)
				hue_delta = minf(hue_delta,1.0-hue_delta)
				# Bright blue cannot pass merely because dark navy has a similar hue.
				if hue_delta <= 0.018 and pixel.s <= allowed.s+0.16 and pixel.v <= allowed.v+0.12:
					matches = true
					break
			if not matches: outside += 1
	var ratio := float(outside)/maxi(bright,1)
	return {"passed": ratio <= MAX_OFF_PALETTE, "off_palette_ratio": ratio}
