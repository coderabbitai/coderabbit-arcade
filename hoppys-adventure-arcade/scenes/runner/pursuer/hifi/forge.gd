extends RefCounted
## Asset-local procedural geometry and three cached 256-square material maps.
static var cache: Dictionary = {}

static func maps() -> Array[ImageTexture]:
	if cache.has("plating"): return cache["plating"]
	return finish_maps(generate_maps())

## Worker-safe: local Images only, no shared caches or rendering resources.
static func generate_maps() -> Array[Image]:
	var height := Image.create(256, 256, false, Image.FORMAT_RF)
	var albedo := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var normal := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var rough := Image.create(256, 256, false, Image.FORMAT_R8)
	for y in 256:
		for x in 256:
			var edge := mini(mini(x, 255 - x), mini(y, 255 - y))
			var grain := fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
			var rivet := Vector2(x % 224 - 16, y % 224 - 16).length() < 3.0
			var h := 0.55 + grain * 0.035 if edge > 7 else 0.2
			if rivet: h = 0.8
			height.set_pixel(x, y, Color(h, 0, 0))
			var base := Color("142735").lerp(Color("435464"), grain * 0.16 + (0.25 if edge < 5 else 0.0))
			albedo.set_pixel(x, y, base)
			rough.set_pixel(x, y, Color(0.28 + grain * 0.13, 0, 0))
	for y in 256:
		for x in 256:
			var gx := 0.0
			var gy := 0.0
			for j in range(-1, 2):
				for i in range(-1, 2):
					var h := height.get_pixel(clampi(x + i, 0, 255), clampi(y + j, 0, 255)).r
					gx += h * i * (2.0 if j == 0 else 1.0)
					gy += h * j * (2.0 if i == 0 else 1.0)
			var n := Vector3(-gx * 2.0, -gy * 2.0, 1).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	albedo.generate_mipmaps()
	normal.generate_mipmaps(true)
	rough.generate_mipmaps()
	return [albedo, normal, rough]

static func finish_maps(images: Array[Image]) -> Array[ImageTexture]:
	if cache.has("plating"): return cache["plating"]
	var result: Array[ImageTexture] = []
	for image: Image in images: result.append(ImageTexture.create_from_image(image))
	cache["plating"] = result
	return cache["plating"]

static func bevel_box(size: Vector3, bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six inset faces with chamfer strips; corner triangles close the silhouette.
	for axis in 3:
		for sign_value in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sign_value
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := n.cross(u)
			var center := n * size[axis] * 0.5
			var points: Array[Vector3] = []
			for xy in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
				points.append(center + u * xy.x * (size[(axis + 1) % 3] * 0.5 - bevel) + v * xy.y * (size[(axis + 2) % 3] * 0.5 - bevel))
			# Only the front inset face carries diff emission; sides remain metal.
			st.set_color(Color(1.0 if axis == 2 and sign_value > 0 else 0.0, 0, 0))
			quad(st, points[0], points[1], points[2], points[3])
			st.set_color(Color(0, 0, 0))
			for k in 4:
				var edge_axis := (axis + (2 if k % 2 == 0 else 1)) % 3
				if axis > edge_axis: continue # Emit each shared chamfer once.
				var a := points[k]
				var b := points[(k + 1) % 4]
				var outward := ((a + b) * 0.5 - center).normalized()
				quad(st, b, a, a + (outward - n) * bevel, b + (outward - n) * bevel)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c := Vector3(sx, sy, sz) * (size * 0.5 - Vector3.ONE * bevel)
				var a := c + Vector3(sx * bevel, 0, 0)
				var b := c + Vector3(0, sy * bevel, 0)
				var d := c + Vector3(0, 0, sz * bevel)
				triangle(st, a, d if sx * sy * sz > 0 else b, b if sx * sy * sz > 0 else d, Vector2.ZERO, Vector2(0, 1), Vector2.RIGHT)
	st.generate_tangents()
	return st.commit()

static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ta: Vector2, tb: Vector2, tc: Vector2) -> void:
	# Godot front faces are clockwise. Derive the outward normal from that order.
	var n := (c - a).cross(b - a).normalized()
	var points := [a, b, c]
	var uvs := [ta, tb, tc]
	for i in 3:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(points[i])

static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ta := Vector2(0, 1), tb := Vector2(1, 1), tc := Vector2(1, 0), td := Vector2(0, 0)) -> void:
	# Each face/strip has its own full, normalized UV rectangle regardless of size.
	triangle(st, a, c, b, ta, tc, tb)
	triangle(st, a, d, c, ta, td, tc)

static func cable_point(strand: int, t: float) -> Vector3:
	var side := -1.0 if strand < 3 else 1.0
	return Vector3(side * (2.43 + sin(t * PI) * 0.29), 0.42 + (strand % 3) * 0.51 + sin(t * TAU) * 0.13, 0.29 + t * 0.25)

static func cables() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0, 0, 0))
	# Eight longitudinal steps, retaining the bible's 24-sided tube cross section.
	for strand in 6:
		for segment in 8:
			var t := float(segment) / 8.0
			var t2 := float(segment + 1) / 8.0
			var a := cable_point(strand, t)
			var b := cable_point(strand, t2)
			var axis := (b - a).normalized()
			var u := axis.cross(Vector3.RIGHT).normalized() * 0.034
			var v := axis.cross(u)
			for side in 24:
				var angle := side * TAU / 24.0
				var next := (side + 1) * TAU / 24.0
				var r := u * cos(angle) + v * sin(angle)
				var s := u * cos(next) + v * sin(next)
				# U wraps the circumference; V runs once along the cable.
				quad(st, a + r, a + s, b + s, b + r, Vector2(side / 24.0, t), Vector2((side + 1) / 24.0, t), Vector2((side + 1) / 24.0, t2), Vector2(side / 24.0, t2))
				if segment == 0:
					triangle(st, a, a + r, a + s, Vector2(0.5, 0.5), Vector2(cos(angle), sin(angle)) * 0.5 + Vector2.ONE * 0.5, Vector2(cos(next), sin(next)) * 0.5 + Vector2.ONE * 0.5)
				if segment == 7:
					triangle(st, b, b + s, b + r, Vector2(0.5, 0.5), Vector2(cos(next), sin(next)) * 0.5 + Vector2.ONE * 0.5, Vector2(cos(angle), sin(angle)) * 0.5 + Vector2.ONE * 0.5)
	st.generate_tangents()
	return st.commit()

static func headline_backings(positions: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plate := bevel_box(Vector3(2.3, 0.34, 0.055), 0.02)
	for position in positions:
		st.append_from(plate, 0, Transform3D(Basis.IDENTITY, position + Vector3(0, 0, -0.045)))
	return st.commit()

static func diff_marks() -> Array[Vector4]:
	# Actual shader rectangles also supply the headless coverage audit.
	# Three variable-length rows, plus/minus signs, one badge and two short seams.
	return [Vector4(0.24, 0.29, 0.77, 0.31), Vector4(0.24, 0.47, 0.59, 0.49), Vector4(0.24, 0.65, 0.68, 0.67),
		Vector4(0.10, 0.285, 0.18, 0.315), Vector4(0.13, 0.25, 0.15, 0.35),
		Vector4(0.10, 0.465, 0.18, 0.495), Vector4(0.10, 0.645, 0.18, 0.675), Vector4(0.13, 0.61, 0.15, 0.71),
		Vector4(0.67, 0.83, 0.87, 0.88), Vector4(0.12, 0.11, 0.38, 0.12), Vector4(0.62, 0.11, 0.88, 0.12)]

## One surface for a continuous chassis, inset sensor sockets, vents and fasteners.
## Vertex colors separate painted armor, rubber recesses and machined edges.
static func chassis() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var armor := Color("728592")
	var edge := Color("b4c3c8")
	var dark := Color("17242e")
	var warning := Color("bb5542")
	chassis_part(st, Vector3(5.18,1.82,0.44), Vector3(0,1.06,-0.20), armor, 0.13)
	for side in [-1.0,1.0]:
		chassis_part(st, Vector3(0.38,1.94,0.62), Vector3(side*2.46,1.10,-0.01), armor, 0.10)
		chassis_part(st, Vector3(0.13,1.34,0.06), Vector3(side*2.48,1.06,0.33), dark, 0.018)
		for row in 7:
			chassis_part(st, Vector3(0.22,0.035,0.075), Vector3(side*2.48,0.55+row*0.16,0.37), edge, 0.01)
		chassis_part(st, Vector3(0.40,0.26,0.12), Vector3(side*2.42,0.25,0.32), warning, 0.04)
		chassis_part(st, Vector3(0.40,0.26,0.12), Vector3(side*2.42,1.96,0.32), warning, 0.04)
		# Deep solid sockets under the original emissive lens, with a broad brow.
		chassis_part(st, Vector3(0.96,0.25,0.22), Vector3(side*0.48,1.80,0.015), edge, 0.045, side*0.19)
		chassis_part(st, Vector3(0.86,0.15,0.06), Vector3(side*0.48,1.80,0.14), dark, 0.025, side*0.19)
		chassis_part(st, Vector3(1.10,0.12,0.22), Vector3(side*0.52,2.01,0.12), armor, 0.035, side*0.12)
		for y in [0.27,1.94]:
			chassis_part(st, Vector3(0.065,0.065,0.035), Vector3(side*2.42,y,0.40), edge, 0.015)
	# Cross rails tie the modules into one manufactured object.
	for y in [0.16,0.73,1.24,2.09]:
		chassis_part(st, Vector3(4.62,0.075,0.16), Vector3(0,y,0.10), edge, 0.024)
	chassis_part(st, Vector3(0.22,0.44,0.24), Vector3(0,1.83,0.04), armor, 0.05)
	for side in [-1.0,1.0]:
		for row in 3:
			chassis_part(st, Vector3(0.42,0.045,0.045), Vector3(side*1.67,1.72+row*0.10,0.23), dark, 0.013)
	return st.commit()

static func chassis_part(st: SurfaceTool, size: Vector3, position: Vector3, tint: Color, bevel: float, angle := 0.0) -> void:
	var mesh := bevel_box(size, bevel)
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	colors.fill(tint)
	arrays[Mesh.ARRAY_COLOR] = colors
	var painted := ArrayMesh.new()
	painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.append_from(painted, 0, Transform3D(Basis(Vector3.BACK,angle),position))
