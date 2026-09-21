extends RefCounted
## Asset-local procedural surface library. Six cached 256-square maps total.
const UV_PER_METER := 1.5625
const CLOTH_CELLS := 64.0
const FUR_CELLS := 64.0
const FUR_REPEATS_PER_METER := 6.25
static var cache: Dictionary = {}

static func maps(kind: String) -> Array:
	if cache.has(kind):
		return cache[kind]
	var n := 256
	var height := Image.create(n, n, false, Image.FORMAT_RF)
	var albedo := Image.create(n, n, false, Image.FORMAT_RGB8)
	var normal := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 4104
	noise.frequency = 0.07
	for y in n:
		for x in n:
			var h := 0.5 + 0.16 * sin((x + y * 0.37) * TAU * FUR_CELLS / n + noise.get_noise_2d(x, y) * 5.0)
			if kind == "cloth":
				h = 0.5 + 0.22 * sin(x * TAU * CLOTH_CELLS / n) * cos(y * TAU * CLOTH_CELLS / n)
			height.set_pixel(x, y, Color(h, h, h))
			# Albedo and roughness share the same height field.
			albedo.set_pixel(x, y, Color.WHITE * ((0.92 + h * 0.04) if kind == "cloth" else (0.975 + h * 0.02)))
	for y in n:
		for x in n:
			var dx := 0.0
			var dy := 0.0
			for k in range(-1, 2):
				var weight := 2.0 if k == 0 else 1.0
				dx += weight * (height.get_pixel((x + 1) % n, posmod(y + k, n)).r - height.get_pixel(posmod(x - 1, n), posmod(y + k, n)).r)
				dy += weight * (height.get_pixel(posmod(x + k, n), (y + 1) % n).r - height.get_pixel(posmod(x + k, n), posmod(y - 1, n)).r)
			var v := Vector3(-dx * 0.4, -dy * 0.4, 1).normalized()
			normal.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5))
	var rough := Image.create(n, n, false, Image.FORMAT_R8)
	for y in n:
		for x in n:
			var r := 0.84 + height.get_pixel(x, y).r * 0.15
			rough.set_pixel(x, y, Color(r, r, r))
	albedo.generate_mipmaps()
	normal.generate_mipmaps(true)
	rough.generate_mipmaps()
	cache[kind] = [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(normal), ImageTexture.create_from_image(rough)]
	return cache[kind]

static func material(color: Color, kind: String) -> StandardMaterial3D:
	var textures := maps(kind)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = textures[0]
	m.normal_enabled = true
	m.normal_texture = textures[1]
	m.normal_scale = 0.12 if kind == "fur" else 0.25
	if kind == "fur":
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * FUR_REPEATS_PER_METER
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness_texture = textures[2]
	m.roughness = 1.0
	return m

static func vertex(st: SurfaceTool, center: Vector3, size: Vector3, u: float, v: float, gradient: bool = false, uv_scale: Vector2 = Vector2.ONE) -> void:
	var a := u * TAU
	var b := v * PI
	var p := Vector3(sin(b) * cos(a), cos(b), sin(b) * sin(a))
	st.set_color(Color.WHITE.lerp(Color(1.0, 0.66, 0.4), sin(v * PI) * 0.55) if gradient else Color.WHITE)
	st.set_normal((p / size).normalized())
	st.set_uv(Vector2(u, v) * uv_scale)
	st.set_uv2(Vector2(u, v))
	st.add_vertex(center + p * size)

static func shapes(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var center: Vector3 = part[0]
		var size: Vector3 = part[1]
		var gradient: bool = part.size() > 2 and part[2]
		var uv_scale := Vector2(TAU * size.x, PI * size.y) * UV_PER_METER
		# Keep 32 latitude rings, allocating circumference detail by silhouette size.
		var maximum := 24 if size.length() > 0.3 else 10
		for ring in 32:
			var v0 := float(ring) / 32.0
			var v1 := float(ring + 1) / 32.0
			var n0 := maxi(4, int(round(sin(v0 * PI) * maximum)))
			var n1 := maxi(4, int(round(sin(v1 * PI) * maximum)))
			var i := 0
			var j := 0
			while i < n0 or j < n1:
				var u0 := float(i) / n0
				var u1 := float(j) / n1
				if i < n0 and (j == n1 or float(i + 1) / n0 <= float(j + 1) / n1):
					vertex(st, center, size, u0, v0, gradient, uv_scale)
					vertex(st, center, size, u1, v1, gradient, uv_scale)
					vertex(st, center, size, float(i + 1) / n0, v0, gradient, uv_scale)
					i += 1
				else:
					vertex(st, center, size, u0, v0, gradient, uv_scale)
					vertex(st, center, size, u1, v1, gradient, uv_scale)
					vertex(st, center, size, float(j + 1) / n1, v1, gradient, uv_scale)
					j += 1
	st.generate_tangents()
	st.index()
	return st.commit()

## Flat faces, 45-degree edge strips and triangular corner chamfers.
static func bevel_box(size: Vector3, bevel: float = 0.025) -> ArrayMesh:
	var half := size * 0.5
	var b := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.75)
	var core := half - Vector3.ONE * b
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			for corner in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
				var p := Vector3.ZERO
				p[axis] = half[axis] * sign_value
				p[u] = core[u] * corner.x
				p[v] = core[v] * corner.y
				points.append(p)
			face(st, points)
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				for corner in [Vector2(-1,0), Vector2(1,0), Vector2(1,1), Vector2(-1,1)]:
					var p := Vector3.ZERO
					p[axis] = corner.x * core[axis]
					p[u] = (half[u] if corner.y == 0 else core[u]) * su
					p[v] = (core[v] if corner.y == 0 else half[v]) * sv
					points.append(p)
				face(st, points)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				face(st, [Vector3(half.x*x,core.y*y,core.z*z), Vector3(core.x*x,half.y*y,core.z*z), Vector3(core.x*x,core.y*y,half.z*z)])
	st.generate_tangents()
	st.index()
	return st.commit()

static func face(st: SurfaceTool, points: Array[Vector3]) -> void:
	var center := Vector3.ZERO
	for p in points:
		center += p / points.size()
	var n := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	if n.dot(center) > 0:
		points.reverse()
	else:
		n = -n
	var tangent := (points[1] - points[0]).normalized()
	var bitangent := n.cross(tangent)
	var face_uv: Array[Vector2] = []
	var minimum := Vector2(INF, INF)
	for point in points:
		var uv := Vector2(point.dot(tangent), point.dot(bitangent)) * UV_PER_METER
		face_uv.append(uv)
		minimum = minimum.min(uv)
	for i in range(1, points.size() - 1):
		for j in [0, i, i + 1]:
			st.set_normal(n)
			st.set_uv(face_uv[j] - minimum)
			st.add_vertex(points[j])

## Bevelled annular cylinder along Y. Twenty-four radial segments minimum.
static func cylinder(radius: float, height: float, inner: float = 0.0) -> ArrayMesh:
	var b := minf(height * 0.2, radius * 0.12)
	var profile: Array[Vector2] = [Vector2(radius-b,-height*0.5), Vector2(radius,-height*0.5+b), Vector2(radius,height*0.5-b), Vector2(radius-b,height*0.5), Vector2(inner,height*0.5), Vector2(inner,-height*0.5), Vector2(radius-b,-height*0.5)]
	return lathe(profile, 24)

static func hood() -> ArrayMesh:
	# Folded, tapered fabric against the shoulders; mouth points into the skull.
	var folded := lathe([Vector2(0,-0.12), Vector2(0.10,-0.09), Vector2(0.155,-0.025), Vector2(0.18,0.035), Vector2(0.15,0.035), Vector2(0.13,0.0), Vector2(0.07,-0.07), Vector2(0,-0.08)], 32, 3)
	return combine([[folded, Transform3D(Basis(Vector3.RIGHT, -1.1).scaled_local(Vector3(1, 0.6, 0.45)), Vector3.ZERO)]])

static func lathe(profile: Array[Vector2], segments: int, lining_start: int = -1) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arc: Array[float] = [0.0]
	var max_radius := 0.0
	for row in profile.size():
		max_radius = maxf(max_radius, profile[row].x)
		if row > 0:
			arc.append(arc.back() + profile[row].distance_to(profile[row-1]))
	for row in profile.size() - 1:
		for i in segments:
			var points: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for ij in [Vector2i(i,row),Vector2i(i+1,row),Vector2i(i+1,row+1),Vector2i(i,row+1)]:
				var a := float(ij.x) / segments * TAU
				var p := profile[ij.y]
				points.append(Vector3(cos(a)*p.x,p.y,sin(a)*p.x))
				uvs.append(Vector2(float(ij.x)/segments * TAU * p.x, arc[ij.y]) * UV_PER_METER)
			for j in [0,1,2,0,2,3]:
				var edge := profile[row+1] - profile[row]
				var a := float(i + (1 if j in [1,2] else 0)) / segments * TAU
				st.set_color(Color(0.24, 0.24, 0.24) if lining_start >= 0 and row > lining_start else (Color(0.55, 0.55, 0.55) if row == lining_start else Color.WHITE))
				st.set_normal(Vector3(cos(a)*edge.y,-edge.x,sin(a)*edge.y).normalized())
				st.set_uv(uvs[j])
				st.set_uv2(Vector2(points[j].x, points[j].z) / (2.0 * max_radius) + Vector2.ONE * 0.5)
				st.add_vertex(points[j])
	st.generate_tangents()
	st.index()
	return st.commit()

static func combine(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		st.append_from(part[0], 0, part[1])
	return st.commit()

static func tinted(mesh: Mesh, color: Color) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var colors := PackedColorArray()
	colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
	colors.fill(color)
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
