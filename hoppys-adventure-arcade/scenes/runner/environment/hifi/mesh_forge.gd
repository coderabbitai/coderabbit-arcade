extends RefCounted
## Single-surface chamfered solids. Vertex alpha carries the emissive mask.
static func box(st: SurfaceTool, center: Vector3, size: Vector3, bevel: float, color: Color) -> void:
	var half := size * 0.5
	var b := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.8)
	var core := half - Vector3.ONE * b
	# Six inset faces, twelve edge strips, eight corner triangles.
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_ in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			for pair in [Vector2(-core[u], -core[v]), Vector2(core[u], -core[v]), Vector2(core[u], core[v]), Vector2(-core[u], core[v])]:
				var p := Vector3.ZERO
				p[axis] = half[axis] * sign_
				p[u] = pair.x
				p[v] = pair.y
				points.append(p)
			polygon(st, points, center, color)
		for a in [-1.0, 1.0]:
			for c in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				for pair in [Vector2(-core[axis], 0), Vector2(core[axis], 0), Vector2(core[axis], 1), Vector2(-core[axis], 1)]:
					var p := Vector3.ZERO
					p[axis] = pair.x
					p[u] = a * (half[u] if pair.y == 0 else core[u])
					p[v] = c * (core[v] if pair.y == 0 else half[v])
					points.append(p)
				polygon(st, points, center, color)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				var s := Vector3(x, y, z)
				polygon(st, [s * Vector3(half.x, core.y, core.z), s * Vector3(core.x, half.y, core.z), s * Vector3(core.x, core.y, half.z)], center, color)

static func polygon(st: SurfaceTool, points: Array[Vector3], center: Vector3, color: Color) -> void:
	var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var midpoint := Vector3.ZERO
	for p in points: midpoint += p
	if normal.dot(midpoint) < 0.0:
		points.reverse()
		normal = -normal
	for i in range(1, points.size() - 1):
		# Godot front faces wind clockwise.
		for p in [points[0], points[i + 1], points[i]]:
			st.set_normal(normal)
			st.set_color(color)
			var uv := Vector2(p.x, p.z)
			if absf(normal.x) >= absf(normal.y) and absf(normal.x) >= absf(normal.z):
				uv = Vector2(p.z, p.y)
			elif absf(normal.z) >= absf(normal.y):
				uv = Vector2(p.x, p.y)
			st.set_uv(uv * 0.5)
			# UV2 stores baked bevel exposure and a directional occlusion gradient.
			var edge := clampf((absf(normal.x) + absf(normal.y) + absf(normal.z) - 1.0) * 2.5, 0.0, 1.0)
			var exposure := clampf(0.72 + normal.y * 0.18 + normal.z * 0.08, 0.45, 1.0)
			st.set_uv2(Vector2(edge, exposure))
			st.add_vertex(center + p)

static func bevel_box(size: Vector3, bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	box(st, Vector3.ZERO, size, bevel, Color(0.26, 0.33, 0.39, 0))
	st.generate_tangents()
	return st.commit()
