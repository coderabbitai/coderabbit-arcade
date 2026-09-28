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
