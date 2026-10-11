extends RefCounted
## Display-referred luma in 0..255, measured from the saved PNG, not scene state.
const FRAME_REGION := Rect2i(840, 220, 60, 240)
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

# Clean broad plate face: excludes frame edges, LEDs and screens. Hold this ROI.
const WALL_DETAIL_REGION := Rect2i(1030, 180, 240, 360)
const WALL_MIN_DETAIL := 0.40
const WALL_EDGE_THRESHOLD := 5.0 # Display-referred 0..255 luma; central difference magnitude.
const WALL_MIN_EDGE_DENSITY := 0.04
const WALL_MIN_STD := 5.0
const WALL_MAX_STD := 14.0
const WALL_MIN_MEAN := 24.0
const WALL_MAX_MEAN := 40.0
const WALL_MAX_DARK := 0.05
const WALL_MAX_AXIS_RATIO := 2.0
static func wall_pass(stats: Dictionary) -> bool:
	return stats.detail >= WALL_MIN_DETAIL and stats.edge_density >= WALL_MIN_EDGE_DENSITY and stats.std >= WALL_MIN_STD and stats.std <= WALL_MAX_STD and stats.mean >= WALL_MIN_MEAN and stats.mean <= WALL_MAX_MEAN and stats.dark_fraction <= WALL_MAX_DARK and stats.axis_ratio <= WALL_MAX_AXIS_RATIO

static func wall_stats(image: Image, region: Rect2i = WALL_DETAIL_REGION) -> Dictionary:
	var result := {"detail": 0.0, "edge_density": 0.0, "std": 0.0, "mean": 0.0, "dark_fraction": 1.0, "dx": 0.0, "dy": 0.0, "axis_ratio": INF, "pass": false}
	if image == null or image.is_empty(): return result
	if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(region) or region.size.x < 3 or region.size.y < 3: return result
	var stats := frame_stats(image, region, 0.0, 0.0)
	result.detail = detail_energy(image, region)
	result.std = stats.std
	result.mean = stats.mean
	var dark := 0
	var edges := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var value := luma(image, x, y)
			if value < 5.0: dark += 1
			var gx := (luma(image, mini(x+1,image.get_width()-1), y)-luma(image, maxi(x-1,0), y))*0.5
			var gy := (luma(image, x, mini(y+1,image.get_height()-1))-luma(image, x, maxi(y-1,0)))*0.5
			if Vector2(gx,gy).length() > WALL_EDGE_THRESHOLD: edges += 1
			if x > region.position.x: result.dx += absf(value-luma(image, x-1, y))
			if y > region.position.y: result.dy += absf(value-luma(image, x, y-1))
	result.edge_density = float(edges)/float(region.size.x*region.size.y)
	result.dark_fraction = float(dark)/float(region.size.x*region.size.y)
	result.dx /= float((region.size.x-1)*region.size.y)
	result.dy /= float((region.size.y-1)*region.size.x)
	result.axis_ratio = result.dy/maxf(result.dx,0.000001)
	result["pass"] = wall_pass(result)
	return result

# Same frame ROI as prior rounds; stronger wall-only gate does not alter floor tests.
const FRAME_RESTORED_MIN_MEAN := 45.0
const FRAME_RESTORED_MAX_MEAN := 70.0
const FRAME_RESTORED_MIN_LIT := 0.90
const SCREEN_REGION := Rect2i(570, 285, 150, 150)
const GAMEPLAY_SCREEN_REGION := Rect2i(1030, 280, 160, 110)
const SCREEN_MIN_P95 := 26.0
const SCREEN_MIN_EDGE := 1.0
static func restored_frame_stats(image: Image, region: Rect2i = FRAME_REGION) -> Dictionary:
	var stats := frame_stats(image, region)
	stats["pass"] = stats["pass"] and stats.mean >= FRAME_RESTORED_MIN_MEAN and stats.mean <= FRAME_RESTORED_MAX_MEAN and stats.lit_fraction >= FRAME_RESTORED_MIN_LIT
	return stats

static func screen_stats(image: Image, region: Rect2i = SCREEN_REGION) -> Dictionary:
	var result := {"p95": 0.0, "edge": 0.0, "pass": false}
	if image == null or image.is_empty(): return result
	# Invalid/out-of-frame ROIs must fail, rather than pass from a tiny bright crop.
	if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(region) or region.size.x < 3 or region.size.y < 3: return result
	var values := PackedFloat32Array()
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x): values.append(luma(image, x, y))
	values.sort()
	result.p95 = values[ceili(float(values.size()) * 0.95) - 1]
	result.edge = detail_energy(image, region)
	result["pass"] = result.p95 >= SCREEN_MIN_P95 and result.edge >= SCREEN_MIN_EDGE
	return result
