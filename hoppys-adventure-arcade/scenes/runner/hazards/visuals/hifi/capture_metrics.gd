extends RefCounted

static func _color_delta(a: Color, b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

static func capsule_pixel(reference: Image, background: Image, x: int, y: int) -> bool:
	var pixel := reference.get_pixel(x,y)
	return pixel.g > pixel.r+0.1 and _color_delta(pixel,background.get_pixel(x,y)) > 0.15

static func compare_capsule(reference: Image, background: Image, actual: Image) -> Vector2i:
	# Erode antialiased silhouette edges. Every remaining capsule pixel must survive.
	var checked := 0
	var overwritten := 0
	for y in range(3,reference.get_height()-3):
		for x in range(3,reference.get_width()-3):
			if not capsule_pixel(reference,background,x,y): continue
			var interior := true
			for offset: Vector2i in [Vector2i(-3,0),Vector2i(3,0),Vector2i(0,-3),Vector2i(0,3),Vector2i(-3,-3),Vector2i(3,-3),Vector2i(-3,3),Vector2i(3,3)]:
				if not capsule_pixel(reference,background,x+offset.x,y+offset.y): interior = false
			if not interior: continue
			checked += 1
			if _color_delta(reference.get_pixel(x,y),actual.get_pixel(x,y)) > 0.15: overwritten += 1
	return Vector2i(checked,overwritten)


static func luminance(color: Color) -> float:
	return color.r*0.2126+color.g*0.7152+color.b*0.0722

static func pit_contrast(image: Image, mouth: Array[Vector2i], floor_pixels: Array[Vector2i], view: String = "gameplay") -> Dictionary:
	var sums := [0.0,0.0,0.0]
	var counts := [0,0,0]
	var min_y := image.get_height()
	var max_y := 0
	for pixel in mouth:
		min_y = mini(min_y,pixel.y)
		max_y = maxi(max_y,pixel.y)
	# Screen Y grows downward: the far/lit edge is the top third.
	for pixel in mouth:
		var third := mini(2,int(3.0*(pixel.y-min_y)/maxf(max_y-min_y+1,1)))
		sums[third] += luminance(image.get_pixelv(pixel))
		counts[third] += 1
	var exposure := floor_exposure(image,floor_pixels)
	var floor_mean: float = exposure.mean
	var floor_median: float = exposure.median
	var floor_p90: float = exposure.p90
	var top: float = sums[0]/maxf(counts[0],1)
	var middle: float = sums[1]/maxf(counts[1],1)
	var bottom: float = sums[2]/maxf(counts[2],1)
	var enough: bool = mouth.size() >= 80 and floor_pixels.size() >= 20 and counts.min() >= 10
	var exposure_pass: bool = exposure.pass
	var top_min := (6.0 if view == "oblique" else 12.0)/255.0
	var mouth_pass: bool = enough and top >= top_min and top <= maxf(floor_p90,26.0/255.0) and maxf(middle,bottom) <= 0.45*top and bottom <= maxf(floor_median,4.0/255.0) and middle > bottom-2.0/255.0
	return {"top_min":top_min,"top":top,"middle":middle,"bottom":bottom,"floor":floor_mean,"floor_median":floor_median,"floor_p90":floor_p90,"exposure_pass":exposure_pass,"mouth_pass":mouth_pass,"pass":exposure_pass and mouth_pass}

static func fixture_plate() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var palette = preload("res://scenes/runner/environment/runner_palette.gd")
	mat.albedo_color = palette.NAVY_2
	mat.metallic = 0.15
	mat.roughness = 0.6
	return mat

static func floor_exposure(image: Image, probes: Array[Vector2i]) -> Dictionary:
	var values: Array[float] = []
	var sum := 0.0
	for pixel in probes:
		var value := luminance(image.get_pixelv(pixel))
		values.append(value)
		sum += value
	values.sort()
	var median := 0.0 if values.is_empty() else values[values.size()/2]
	var p90 := 0.0 if values.is_empty() else values[int((values.size()-1)*0.9)]
	# Nominal minimum 6/255 with one code-value tolerance for the requested 5/255 PASS pin.
	return {"median":median,"p90":p90,"mean":sum/maxf(values.size(),1),"count":values.size(),"pass":not values.is_empty() and median >= (6.0-1.0)/255.0 and median <= 40.0/255.0 and p90 >= 12.0/255.0 and p90 <= 72.0/255.0}

## Shipping-corridor floor exposure (captures mount corridor.tscn, whose lit grid floor is brighter than
## the retired navy fixture plate): the floor beside the hazard must be neither black (broken capture)
## nor blown out. Measured corridor floor at the gameplay camera: median ~41-47/255, p90 45-190/255.
static func corridor_exposure(image: Image, probes: Array[Vector2i]) -> Dictionary:
	var measured := floor_exposure(image,probes)
	measured.pass = measured.count > 0 and measured.median >= 6.0/255.0 and measured.median <= 110.0/255.0 and measured.p90 >= 12.0/255.0 and measured.p90 <= 235.0/255.0
	return measured

## Hazard DANGER red as the player sees it: red hue (345..16 deg, DANGER is 5 deg; ORANGE 22 deg and
## LILAC never qualify), saturated and not black.
static func is_danger(color: Color) -> bool:
	var hue := color.h*360.0
	return (hue <= 16.0 or hue >= 345.0) and color.s >= 0.45 and color.v >= 0.18

## x: DANGER pixels changed by the hazard / screen-box pixels; y: DANGER / hazard-changed pixels.
static func danger_share(image: Image, background: Image, rect: Rect2i) -> Vector2:
	var box := 0
	var changed := 0
	var red := 0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			box += 1
			var c := image.get_pixel(x,y)
			if _color_delta(c,background.get_pixel(x,y)) < 0.03: continue
			changed += 1
			if is_danger(c): red += 1
	return Vector2(float(red)/maxf(box,1),float(red)/maxf(changed,1))

static func _mask_class(mask: Image, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= mask.get_width() or y >= mask.get_height(): return 0
	var c := mask.get_pixel(x,y)
	if c.r > 0.2 and c.g < 0.1: return 2
	if c.g > 0.2 and c.r < 0.1: return 1
	return 0

## Lit luminance of code-line ink (mask class 2) against the slab around it (class 1) inside `rect`,
## skipping label rectangles. `erode` keeps only pixels whose four neighbours share the class.
static func ink_contrast(lit: Image, mask: Image, rect: Rect2i, excluded: Array[Rect2], erode: bool) -> Dictionary:
	var sums := [0.0,0.0,0.0]
	var counts := [0,0,0]
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO,lit.get_size()))
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var skip := false
			for area in excluded:
				if area.has_point(Vector2(x,y)): skip = true
			if skip: continue
			var kind := _mask_class(mask,x,y)
			if kind == 0: continue
			if erode and (_mask_class(mask,x-1,y) != kind or _mask_class(mask,x+1,y) != kind or _mask_class(mask,x,y-1) != kind or _mask_class(mask,x,y+1) != kind): continue
			sums[kind] += luminance(lit.get_pixel(x,y))
			counts[kind] += 1
	var ink: float = sums[2]/maxf(counts[2],1)
	var slab: float = sums[1]/maxf(counts[1],1)
	return {"ink_luminance": ink, "slab_luminance": slab, "contrast": ink-slab, "ink": counts[2], "slab": counts[1]}

## Mean absolute per-channel change between two equally sized frames (motion evidence).
static func mean_delta(a: Image, b: Image) -> float:
	var total := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x,y)
			var q := b.get_pixel(x,y)
			total += (absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b))/3.0
	return total/maxf(a.get_width()*a.get_height(),1)
