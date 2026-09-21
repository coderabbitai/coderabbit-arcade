extends RefCounted
## Display-referred luma in 0..255, measured from the saved PNG, not scene state.
const FRAME_REGION := Rect2i(1000, 150, 100, 500)
const FLOOR_REGION := Rect2i(300, 470, 200, 120)
const FLOOR_MIN_MEAN := 10.0
const FLOOR_MAX_MEAN := 45.0
const FLOOR_DETAIL_REGION := Rect2i(780, 560, 40, 50)
const FLOOR_MIN_DETAIL := 2.0
const CEILING_REGION := Rect2i(480, 90, 320, 50)
const CEILING_MIN_MEAN := 4.0
const MIN_MEAN := 12.0
const MIN_STD := 2.0
const MIN_LIT_FRACTION := 0.55

static func frame_stats(image: Image, region: Rect2i = FRAME_REGION, minimum_mean: float = MIN_MEAN, minimum_std: float = MIN_STD) -> Dictionary:
	if image == null or image.is_empty():
		return {"mean": 0.0, "std": 0.0, "lit_fraction": 0.0, "pass": false}
	var clipped := region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return {"mean": 0.0, "std": 0.0, "lit_fraction": 0.0, "pass": false}
	var sum := 0.0
	var squared := 0.0
	var lit := 0
	var count := clipped.size.x * clipped.size.y
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var pixel := image.get_pixel(x, y)
			var luma := (pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722) * 255.0
			sum += luma
			squared += luma * luma
			if luma >= 8.0: lit += 1
	var mean := sum / count
	var deviation := sqrt(maxf(0.0, squared / count - mean * mean))
	var fraction := float(lit) / count
	return {"mean": mean, "std": deviation, "lit_fraction": fraction, "pass": mean >= minimum_mean and deviation >= minimum_std and fraction >= MIN_LIT_FRACTION}

static func floor_stats(image: Image, region: Rect2i = FLOOR_REGION, detail_region: Rect2i = FLOOR_DETAIL_REGION) -> Dictionary:
	var stats := frame_stats(image, region, FLOOR_MIN_MEAN, 0.0)
	stats["detail"] = detail_energy(image, detail_region)
	stats["pass"] = stats["pass"] and stats.mean <= FLOOR_MAX_MEAN and stats.detail >= FLOOR_MIN_DETAIL
	return stats

static func luma(image: Image, x: int, y: int) -> float:
	var pixel := image.get_pixel(x, y)
	return (pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722) * 255.0

static func detail_energy(image: Image, region: Rect2i) -> float:
	if image == null or image.get_width() < 3 or image.get_height() < 3: return 0.0
	var clipped := region.intersection(Rect2i(1, 1, image.get_width() - 2, image.get_height() - 2))
	if clipped.size.x <= 0 or clipped.size.y <= 0: return 0.0
	var total := 0.0
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var neighbourhood := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2): neighbourhood += luma(image, x + dx, y + dy)
			total += absf(luma(image, x, y) - neighbourhood / 9.0)
	return total / float(clipped.size.x * clipped.size.y)

static func ceiling_stats(image: Image, region: Rect2i = CEILING_REGION) -> Dictionary:
	var stats := frame_stats(image, region, CEILING_MIN_MEAN, 0.0)
	# Ceiling includes deliberately dark gaps. Its guard measures depth-cue mean, not floor coverage.
	stats["pass"] = stats.mean >= CEILING_MIN_MEAN
	return stats
