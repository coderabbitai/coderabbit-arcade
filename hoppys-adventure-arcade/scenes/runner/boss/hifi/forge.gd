extends RefCounted
## Three shared 256² maps; bevelled geometry uses one surface per batch.
static var maps: Dictionary = {}
static var atlas: ImageTexture
static var meshes: Dictionary = {}

static func bevel_box(size: Vector3, bevel: float = 0.08) -> ArrayMesh:
	var key := str(size) + str(bevel)
	if meshes.has(key): return meshes[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var radius := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.45)
	var inner := half - Vector3.ONE * radius
	for axis in 3:
		for side in [-1.0, 1.0]:
			var u_axis := (axis + 1) % 3
			var v_axis := (axis + 2) % 3
			var us := [-half[u_axis], -inner[u_axis], inner[u_axis], half[u_axis]]
			var vs := [-half[v_axis], -inner[v_axis], inner[v_axis], half[v_axis]]
			for row in 3:
				for col in 3:
					var points: Array[Vector3] = []
					var normals: Array[Vector3] = []
					for corner: Vector2i in [Vector2i(col, row), Vector2i(col + 1, row), Vector2i(col + 1, row + 1), Vector2i(col, row + 1)]:
						var point := Vector3.ZERO
						point[axis] = half[axis] * side
						point[u_axis] = us[corner.x]
						point[v_axis] = vs[corner.y]
						var clamped := point.clamp(-inner, inner)
						var normal := (point - clamped).normalized()
						points.append(clamped + normal * radius)
						normals.append(normal)
					for index: int in ([0, 2, 1, 0, 3, 2] if side > 0 else [0, 1, 2, 0, 2, 3]):
						surface.set_normal(normals[index])
						surface.set_uv(Vector2(points[index][u_axis] / size[u_axis] + 0.5, points[index][v_axis] / size[v_axis] + 0.5))
						surface.add_vertex(points[index])
	surface.generate_tangents()
	var mesh := surface.commit()
	meshes[key] = mesh
	return mesh

static func textures() -> Dictionary:
	if not maps.is_empty(): return maps
	var width := 256
	var height := PackedFloat32Array()
	height.resize(width * width)
	var albedo := Image.create(width, width, false, Image.FORMAT_RGBA8)
	var normal := Image.create(width, width, false, Image.FORMAT_RGBA8)
	var rough := Image.create(width, width, false, Image.FORMAT_RGBA8)
	for y in width:
		for x in width:
			var seam := x % 64 < 3 or y % 128 < 3
			var rivet := Vector2(x % 64 - 8, y % 128 - 8).length() < 2.5
			var grain := sin(x * 1.73 + sin(y * 0.13)) * 0.014 + sin(y * 2.41) * 0.012
			var h := (0.2 if seam else 0.62) + (0.25 if rivet else 0.0) + grain
			height[y * width + x] = h
			var value := (0.48 if seam else 0.86) + grain * 2.0
			albedo.set_pixel(x, y, Color(value, value, value, 1))
			rough.set_pixel(x, y, Color(0.3 + (1.0 - h) * 0.18, 0, 0, 1))
	for y in width:
		for x in width:
			var dx := 0.0
			var dy := 0.0
			for j in range(-1, 2):
				for i in range(-1, 2):
					var h := height[posmod(y + j, width) * width + posmod(x + i, width)]
					dx += h * i * (2.0 if j == 0 else 1.0)
					dy += h * j * (2.0 if i == 0 else 1.0)
			var n := Vector3(-dx * 1.4, -dy * 1.4, 1).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	albedo.generate_mipmaps()
	normal.generate_mipmaps(true)
	rough.generate_mipmaps()
	maps = {"albedo": ImageTexture.create_from_image(albedo), "normal": ImageTexture.create_from_image(normal), "rough": ImageTexture.create_from_image(rough)}
	return maps

static func metal(color: Color) -> StandardMaterial3D:
	var textures_by_name := textures()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = textures_by_name.albedo
	material.normal_enabled = true
	material.normal_texture = textures_by_name.normal
	material.normal_scale = 0.7
	material.roughness_texture = textures_by_name.rough
	material.roughness = 1.0
	material.metallic = 0.78
	return material

static func glyph_atlas() -> ImageTexture:
	if atlas != null: return atlas
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var cell := x / 64
			var p := Vector2(float(x % 64) / 64.0, float(y) / 256.0)
			var ink := (absf(p.x - 0.25) < 0.06 or absf(p.x - 0.75) < 0.06) and p.y > 0.2 and p.y < 0.8
			ink = ink or (absf(p.y - 0.5) < 0.045 and p.x > 0.25 and p.x < 0.75 and cell % 2 == 0)
			image.set_pixel(x, y, Color(1, 1, 1, 1 if ink else 0))
	image.generate_mipmaps()
	atlas = ImageTexture.create_from_image(image)
	return atlas

static func unit_bevel_box(size: Vector3, bevel: float) -> ArrayMesh:
	var key := "unit" + str(size) + str(bevel)
	if meshes.has(key): return meshes[key]
	var arrays := bevel_box(size, bevel).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	for i in vertices.size():
		vertices[i] /= size
		normals[i] = (normals[i] * size).normalized()
		var tangent := (Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2]) / size).normalized()
		tangents[i * 4] = tangent.x
		tangents[i * 4 + 1] = tangent.y
		tangents[i * 4 + 2] = tangent.z
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("world_bevel", bevel)
	meshes[key] = mesh
	return mesh

static func hydra_head() -> ArrayMesh:
	if meshes.has("head"): return meshes.head
	var arrays := bevel_box(Vector3(1.12, 1.05, 1.02), 0.06).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		var tip := maxf(vertices[i].z / 0.51, 0.0)
		vertices[i].x *= 1.0 - tip * 0.3
		vertices[i].y -= tip * 0.12
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var snout := ArrayMesh.new()
	snout.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(snout, 0, Transform3D.IDENTITY)
	# Integrated brow plate stays in the same draw as the tapered head.
	surface.append_from(bevel_box(Vector3(0.88, 0.16, 0.18), 0.025), 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.40, 0.49)))
	surface.generate_normals()
	surface.generate_tangents()
	var result := surface.commit()
	meshes.head = result
	return result

static func channel() -> ArrayMesh:
	if meshes.has("channel"): return meshes.channel
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(bevel_box(Vector3(1, 1, 0.08), 0.01), 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.46)))
	for side in [-1, 1]:
		surface.append_from(bevel_box(Vector3(0.14, 1, 1), 0.01), 0, Transform3D(Basis.IDENTITY, Vector3(side * 0.43, 0, 0)))
	var result := surface.commit()
	meshes.channel = result
	return result

static func sleeve() -> ArrayMesh:
	if meshes.has("sleeve"): return meshes.sleeve
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1, 1]:
		surface.append_from(bevel_box(Vector3(0.14, 1, 1), 0.04), 0, Transform3D(Basis.IDENTITY, Vector3(side * 0.43, 0, 0)))
		surface.append_from(bevel_box(Vector3(0.72, 1, 0.14), 0.04), 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, side * 0.43)))
	var mesh := surface.commit()
	meshes.sleeve = mesh
	return mesh

static func bevelled_path(points: Array[Vector3], section: Vector2) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var direction := points[i + 1] - points[i]
		var orientation := Basis(Quaternion(Vector3.UP, direction.normalized()))
		surface.append_from(bevel_box(Vector3(section.x, direction.length() * 1.08, section.y), minf(section.x, section.y) * 0.2), 0, Transform3D(orientation, points[i].lerp(points[i + 1], 0.5)))
	return surface.commit()

static func recessed_arc_segment() -> ArrayMesh:
	if meshes.has("arc_segment"): return meshes.arc_segment
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# An inset floor at Z=.28, behind the chamfered front lips at Z=.5.
	surface.append_from(bevel_box(Vector3(0.6, 0.84, 0.08), 0.025), 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.24)))
	for side in [-1, 1]:
		surface.append_from(bevel_box(Vector3(0.2, 1, 1), 0.04), 0, Transform3D(Basis.IDENTITY, Vector3(side * 0.4, 0, 0)))
		surface.append_from(bevel_box(Vector3(0.6, 0.08, 1), 0.025), 0, Transform3D(Basis.IDENTITY, Vector3(0, side * 0.46, 0)))
	var mesh := surface.commit()
	meshes.arc_segment = mesh
	return mesh

static func clear_cache() -> void:
	maps.clear()
	meshes.clear()
	atlas = null

# Eight-sided chamfered rectangular section swept around a containment band.
static func forged_band(radius: float, width: float, depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var section: Array[Vector2] = [Vector2(-0.5,-0.3), Vector2(-0.3,-0.5), Vector2(0.3,-0.5), Vector2(0.5,-0.3), Vector2(0.5,0.3), Vector2(0.3,0.5), Vector2(-0.3,0.5), Vector2(-0.5,0.3)]
	for segment in 24:
		for side in 8:
			var points: Array[Vector3] = []
			for corner in [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(0,1)]:
				var angle: float = TAU * (segment + corner.x) / 24.0
				var cross_section := section[(side + corner.y) % 8]
				points.append(Vector3(cos(angle) * (radius + cross_section.x * width), sin(angle) * (radius + cross_section.x * width), cross_section.y * depth))
			for index in [0,2,1,0,3,2]:
				var corner: Vector2i = [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)][index]
				surface.set_uv(Vector2(float(segment+corner.x) / 24.0, float(side+corner.y) / 8.0))
				surface.add_vertex(points[index])
	surface.generate_normals()
	surface.generate_tangents()
	var mesh := surface.commit()
	mesh.set_meta("section_width", width)
	mesh.set_meta("section_depth", depth)
	return mesh

static func reactor_housing() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(forged_band(0.60, 0.28, 0.34), 0, Transform3D(Basis.IDENTITY, Vector3(0,0,-0.08)))
	for i in 8:
		var angle: float = TAU * i / 8.0
		var rotation := Basis(Vector3.BACK, angle)
		surface.append_from(bevel_box(Vector3(0.27,0.31,0.20),0.03), 0, Transform3D(rotation, Vector3(cos(angle)*0.60,sin(angle)*0.60,0.20)))
	return surface.commit()

static func reactor_vents() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var angle: float = TAU * (i + 0.5) / 8.0
		surface.append_from(bevel_box(Vector3(0.16,0.055,0.035),0.008), 0, Transform3D(Basis(Vector3.BACK,angle),Vector3(cos(angle)*0.60,sin(angle)*0.60,0.12)))
	return surface.commit()

static func reactor_heart() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 12:
		for col in 24:
			for corner in [Vector2i(0,0),Vector2i(0,1),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(1,0)]:
				var uv := Vector2(float(col + corner.x) / 24.0, float(row + corner.y) / 12.0)
				var normal := Vector3(sin(uv.y*PI)*cos(uv.x*TAU), cos(uv.y*PI), sin(uv.y*PI)*sin(uv.x*TAU))
				surface.set_normal(normal)
				surface.set_uv(uv)
				surface.add_vertex(normal * 0.46)
	surface.generate_tangents()
	return surface.commit()
