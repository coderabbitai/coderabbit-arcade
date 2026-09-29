extends RefCounted
## Mipmapped plating, brushed response, and circuit maps shared by all A2 metal surfaces.
static var cache: Dictionary = {}
static func maps() -> Dictionary:
	if not cache.is_empty(): return cache
	return finish_maps(generate_maps())

## Worker-safe: local Images only, no shared caches or rendering resources.
static func generate_maps() -> Dictionary:
	var n := 1024
	var fine := PackedFloat32Array()
	var coarse := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA209
	fine.resize(16 * n)
	coarse.resize(8 * n / 2)
	for i in fine.size(): fine[i] = rng.randf_range(-1.0, 1.0)
	for i in coarse.size(): coarse[i] = rng.randf_range(-1.0, 1.0)
	var height := PackedFloat32Array()
	height.resize(n * n)
	for y in n:
		for x in n:
			var fx := x / 64
			var cx := x / 128
			var f := smoothstep(0.0, 1.0, float(x % 64) / 64.0)
			var c := smoothstep(0.0, 1.0, float(x % 128) / 128.0)
			var streak_fine := lerpf(fine[y * 16 + fx], fine[y * 16 + (fx + 1) % 16], f)
			var streak_coarse := lerpf(coarse[(y / 2) * 8 + cx], coarse[(y / 2) * 8 + (cx + 1) % 8], c)
			var brush := streak_fine * 0.018 + streak_coarse * 0.008
			var edge := minf(float(x % 256), float(y % 256))
			var seam := 0.12 * (1.0 - smoothstep(1.0, 6.0, edge))
			var rivet_distance := Vector2(float(x % 256 - 18), float(y % 256 - 18)).length()
			var rivet := 0.10 * (1.0 - smoothstep(3.0, 6.0, rivet_distance))
			height[y * n + x] = 0.5 + brush - seam + rivet
	var albedo := Image.create(n, n, false, Image.FORMAT_RGB8)
	var normal := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rough := Image.create(n, n, false, Image.FORMAT_R8)
	for y in n:
		for x in n:
			var gx := 0.0
			var gy := 0.0
			for j in range(-1, 2):
				for i in range(-1, 2):
					var value := height[posmod(y + j, n) * n + posmod(x + i, n)]
					gx += value * float(i * (2 if j == 0 else 1))
					gy += value * float(j * (2 if i == 0 else 1))
			var v := Vector3(-gx * 2.0, -gy * 2.0, 1).normalized() * 0.5 + Vector3.ONE * 0.5
			normal.set_pixel(x, y, Color(v.x, v.y, v.z))
			var value := height[y * n + x]
			var plate := clampf(0.78 + (value - 0.5) * 3.2, 0.18, 1.0)
			albedo.set_pixel(x, y, Color(plate, plate, plate))
			rough.set_pixel(x, y, Color(0.28 + (1.0 - value) * 0.2, 0, 0))
	# Build mip chains only after every pixel has been authored.
	albedo.generate_mipmaps()
	normal.generate_mipmaps(true)
	rough.generate_mipmaps()
	var circuit := Image.create(256, 256, false, Image.FORMAT_R8)
	for y in 256:
		for x in 256:
			var track := (x % 64 == 12 and y % 64 < 44) or (y % 64 == 44 and x % 64 >= 12 and x % 64 <= 36)
			circuit.set_pixel(x, y, Color(1.0 if track else 0.0, 0, 0))
	circuit.generate_mipmaps()
	return {"circuit_map": circuit,"albedo_map": albedo, "normal_map": normal, "roughness_map": rough}

static func finish_maps(images: Dictionary) -> Dictionary:
	if not cache.is_empty(): return cache
	for key in images: cache[key] = ImageTexture.create_from_image(images[key])
	return cache


## Dedicated floor maps: diffuse plating, Sobel normal, and packed roughness/AO/wear.
const FLOOR_BRUSH_PERIOD := 32.0
const FLOOR_RIVET_RADIUS := 0.10
static var floor_cache: Dictionary = {}
static func floor_maps() -> Dictionary:
	if not floor_cache.is_empty(): return floor_cache
	return finish_floor_maps(generate_floor_maps())

## Worker-safe: local Images only, no shared caches or rendering resources.
static func generate_floor_maps() -> Dictionary:
	var n := 512
	var height := PackedFloat32Array()
	height.resize(n * n)
	for y in n:
		for x in n:
			var edge := float(mini(mini(x, n - 1 - x), mini(y, n - 1 - y)))
			var groove := 0.14 * (1.0 - smoothstep(2.0, 8.0, edge))
			var rivet_distance := Vector2(float(mini(x, n - 1 - x) - 38), float(mini(y, n - 1 - y) - 38)).length()
			var rivet_pixels := FLOOR_RIVET_RADIUS * float(n) / 2.0
			var rivet := 0.12 * (1.0 - smoothstep(rivet_pixels * 0.75, rivet_pixels, rivet_distance))
			var brush := sin(float(y) * TAU / FLOOR_BRUSH_PERIOD) * 0.055 + sin(float(x) * TAU / 128.0 + float(y) * TAU / 64.0) * 0.025
			height[y * n + x] = 0.5 + brush - groove + rivet
	var albedo := Image.create(n, n, false, Image.FORMAT_RGB8)
	var normal := Image.create(n, n, false, Image.FORMAT_RGB8)
	var response := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var gx := 0.0
			var gy := 0.0
			for j in range(-1, 2):
				for i in range(-1, 2):
					var sample := height[posmod(y + j, n) * n + posmod(x + i, n)]
					gx += sample * float(i * (2 if j == 0 else 1))
					gy += sample * float(j * (2 if i == 0 else 1))
			var v := Vector3(-gx * 2.0, -gy * 2.0, 1).normalized() * 0.5 + Vector3.ONE * 0.5
			normal.set_pixel(x, y, Color(v.x, v.y, v.z))
			var h := height[y * n + x]
			var plate := clampf(0.72 + (h - 0.5) * 4.0, 0.20, 0.98)
			albedo.set_pixel(x, y, Color(plate, plate, plate))
			var scratch := pow(maxf(0.0, sin(float(x) * TAU / 32.0 + sin(float(y) * TAU / 64.0))), 16.0)
			response.set_pixel(x, y, Color(0.38 + scratch * 0.06, clampf(0.8 + (h - 0.5) * 2.0, 0.5, 1.0), 1.0 - scratch * 0.28))
	albedo.generate_mipmaps()
	normal.generate_mipmaps(true)
	response.generate_mipmaps()
	return {"albedo_map": albedo, "normal_map": normal, "roughness_map": response}

static func finish_floor_maps(images: Dictionary) -> Dictionary:
	if not floor_cache.is_empty(): return floor_cache
	for key in images: floor_cache[key] = ImageTexture.create_from_image(images[key])
	return floor_cache


## A corridor needs bindings immediately; preserve texture identity when detail arrives.
static var pending: Dictionary = {}
static func prepare_async(method: String) -> void:
	var target := cache if method == "maps" else floor_cache
	if not target.is_empty(): return
	var colors := {"albedo_map": Color(0.85, 0.85, 0.85), "normal_map": Color(0.5, 0.5, 1.0), "roughness_map": Color(0.38, 0.8, 1.0)}
	if method == "maps": colors["circuit_map"] = Color.BLACK
	for key in colors:
		var image := Image.create(1, 1, false, Image.FORMAT_RGB8)
		image.fill(colors[key])
		target[key] = ImageTexture.create_from_image(image)
	pending[method] = true

static func install_async(method: String, images: Dictionary) -> Dictionary:
	var target := cache if method == "maps" else floor_cache
	if pending.has(method):
		for key in images: target[key].set_image(images[key])
		pending.erase(method)
	elif target.is_empty():
		for key in images: target[key] = ImageTexture.create_from_image(images[key])
	return target
