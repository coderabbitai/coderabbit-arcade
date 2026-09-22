extends RefCounted
## Masks come from baked albedo in a separate unlit pass, never from output hue.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")

static func measure(image: Image, mask: Image) -> Dictionary:
	var sums := [Vector2.ZERO, Vector2.ZERO]
	var counts := [0, 0]
	var luma_sums := [0.0, 0.0]
	var body := 0
	var white := 0
	# Read contiguous bytes once; avoid two Image.get_pixel calls per viewport pixel.
	var pixels := image.duplicate() as Image
	var classes := mask.duplicate() as Image
	pixels.convert(Image.FORMAT_RGB8)
	classes.convert(Image.FORMAT_RGB8)
	var rgb := pixels.get_data()
	var masks := classes.get_data()
	for offset in range(0, image.get_width() * image.get_height() * 3, 3):
		var r := masks[offset]
		var g := masks[offset + 1]
		var b := masks[offset + 2]
		if maxi(r, maxi(g, b)) < 204:
			continue
		body += 1
		if mini(rgb[offset], mini(rgb[offset + 1], rgb[offset + 2])) >= 243:
			white += 1
		var index := 0 if r > 204 and g < 51 else (1 if g > 204 and r < 51 else -1)
		if index >= 0:
			var c := Color(float(rgb[offset]) / 255.0, float(rgb[offset + 1]) / 255.0, float(rgb[offset + 2]) / 255.0)
			sums[index] += Vector2(cos(c.h * TAU), sin(c.h * TAU))
			counts[index] += 1
			luma_sums[index] += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	var hues := [fposmod(sums[0].angle() / TAU, 1.0), fposmod(sums[1].angle() / TAU, 1.0)]
	var orange_delta := absf(wrapf(hues[0] - Palette.ORANGE.h, -0.5, 0.5)) * 360.0
	var cream_delta := absf(wrapf(hues[1] - Palette.CREAM.h, -0.5, 0.5)) * 360.0
	var hoodie_luma: float = luma_sums[0] / maxi(counts[0], 1)
	var fur_luma: float = luma_sums[1] / maxi(counts[1], 1)
	var ratio := float(white) / maxi(body, 1)
	return {"pass": counts[0] >= 8 and counts[1] >= 8 and orange_delta <= 12.0 and cream_delta <= 15.0 and ratio <= 0.05
		and fur_luma >= 0.55 and fur_luma <= 0.90 and hoodie_luma >= 0.30 and hoodie_luma <= 0.75,
		"hoodie_luma": hoodie_luma, "fur_luma": fur_luma, "hoodie_hue": hues[0] * 360.0, "fur_hue": hues[1] * 360.0, "white_ratio": ratio, "pixels": counts}
