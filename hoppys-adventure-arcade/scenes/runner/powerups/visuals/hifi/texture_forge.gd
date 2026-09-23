extends RefCounted
## Shared 256-square brushed plating maps. No random global state or disk assets.
static var cache: Dictionary = {}
const TRACE_PATHS := [
	[Vector2(24,20),Vector2(24,92),Vector2(62,130),Vector2(62,216)],
	[Vector2(43,20),Vector2(43,80),Vector2(88,125),Vector2(88,188)],
	[Vector2(116,32),Vector2(116,68),Vector2(154,106),Vector2(218,106)],
	[Vector2(138,222),Vector2(138,160),Vector2(172,126),Vector2(224,126)],
	[Vector2(178,22),Vector2(178,58),Vector2(224,58)],
]

static func height_at(x: int, y: int) -> float:
	var point := Vector2(x,y)
	var trace := false
	var pad := false
	for path: Array in TRACE_PATHS:
		for i in path.size()-1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i+1]
			var along := clampf((point-a).dot(b-a)/(b-a).length_squared(),0,1)
			if point.distance_to(a+(b-a)*along) < 1.1: trace = true
		if point.distance_to(path[-1]) < 3.2: pad = true
	var grain := sin(float(x*127+y*311))*43758.5453
	grain -= floorf(grain)
	return 0.5 + (0.035 if trace else 0.0) + (0.055 if pad else 0.0) + grain*0.006


static func maps() -> Dictionary:
	if not cache.is_empty(): return cache
	var size := 256
	var height := PackedFloat32Array()
	height.resize(size * size)
	for y in size:
		for x in size:
			height[y*size+x] = height_at(x,y)
	var albedo := Image.create(size,size,false,Image.FORMAT_RGBA8)
	var normal := Image.create(size,size,false,Image.FORMAT_RGBA8)
	var rough := Image.create(size,size,false,Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var h := height[y * size + x]
			var dx := 0.0
			var dy := 0.0
			for k in range(-1,2):
				var weight := 2.0 if k == 0 else 1.0
				dx += weight * (height[posmod(y+k,size)*size+posmod(x+1,size)] - height[posmod(y+k,size)*size+posmod(x-1,size)])
				dy += weight * (height[posmod(y+1,size)*size+posmod(x+k,size)] - height[posmod(y-1,size)*size+posmod(x+k,size)])
			var n := Vector3(-dx,-dy,2.0).normalized() * 0.5 + Vector3.ONE * 0.5
			albedo.set_pixel(x,y,Color(h+0.34,h+0.36,h+0.38,1))
			normal.set_pixel(x,y,Color(n.x,n.y,n.z,1))
			var r := clampf(0.42 - absf(dx)*0.12,0.25,0.45)
			rough.set_pixel(x,y,Color(r,r,r,1))
	for entry: Array in [["albedo",albedo],["normal",normal],["roughness",rough]]:
		entry[1].generate_mipmaps()
		cache[entry[0]] = ImageTexture.create_from_image(entry[1])
	var glyph := Image.create(size,size,false,Image.FORMAT_RGBA8)
	glyph.fill(Color(1,1,1,0))
	for y in range(32,224):
		for x in range(56,200):
			if x < 76 or (y < 52 or y > 204) and x < 154:
				glyph.set_pixel(x,y,Color.WHITE)
	glyph.generate_mipmaps()
	cache["glyph"] = ImageTexture.create_from_image(glyph)
	return cache
