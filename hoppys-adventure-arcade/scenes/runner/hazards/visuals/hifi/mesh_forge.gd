extends RefCounted
## Unit-envelope primitives. Every repeated component shares these meshes.
static var _cache: Dictionary = {}

static func bevel_box() -> ArrayMesh:
	if _cache.has("box"): return _cache.box
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.5
	var a := 0.40
	# Six inset faces, twelve chamfer strips, eight triangular corner facets.
	for axis in 3:
		for side in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			for uv: Vector2 in [Vector2(-a, -a), Vector2(a, -a), Vector2(a, a), Vector2(-a, a)]:
				var p := Vector3.ZERO
				p[axis] = side * h
				p[(axis + 1) % 3] = uv.x
				p[(axis + 2) % 3] = uv.y
				points.append(p)
			_face(st, points)
	for axis in 3:
		for s in [-1.0, 1.0]:
			for t in [-1.0, 1.0]:
				var points: Array[Vector3] = []
				for ends: Vector3 in [Vector3(-a, h, a), Vector3(a, h, a), Vector3(a, a, h), Vector3(-a, a, h)]:
					var p := Vector3.ZERO
					p[axis] = ends.x
					p[(axis + 1) % 3] = ends.y * s
					p[(axis + 2) % 3] = ends.z * t
					points.append(p)
				_face(st, points)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				_face(st, [Vector3(h*x,a*y,a*z), Vector3(a*x,h*y,a*z), Vector3(a*x,a*y,h*z)])
	st.generate_tangents()
	_cache.box = st.commit()
	return _cache.box

static func _face(st: SurfaceTool, points: Array, expected_normal := Vector3.ZERO) -> void:
	var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var center := Vector3.ZERO
	for p in points: center += p
	if normal.dot(center if expected_normal == Vector3.ZERO else expected_normal) < 0.0:
		points.reverse()
		normal = -normal
	# Godot uses clockwise winding when viewed from outside.
	for i in range(1, points.size() - 1):
		for j in [0, i + 1, i]:
			st.set_normal(normal)
			var p: Vector3 = points[j]
			var uv := Vector2(p.x, p.y)
			if absf(normal.y) > 0.7: uv = Vector2(p.x, p.z)
			elif absf(normal.x) > 0.7: uv = Vector2(p.z, p.y)
			st.set_uv((uv + Vector2.ONE * 0.5).clamp(Vector2.ZERO,Vector2.ONE))
			st.add_vertex(p)

static func ring() -> ArrayMesh:
	if _cache.has("ring"): return _cache.ring
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 48:
		for j in 8:
			for corner: Vector2i in [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(0,0), Vector2i(1,1), Vector2i(0,1)]:
				var u := float(i + corner.x) / 48.0
				var v := float(j + corner.y) / 8.0
				var n := Vector3(cos(u*TAU)*cos(v*TAU), sin(v*TAU), sin(u*TAU)*cos(v*TAU))
				st.set_normal(n)
				st.set_uv(Vector2(u, v))
				st.add_vertex(Vector3(cos(u*TAU)*0.42, 0, sin(u*TAU)*0.42) + n*0.08)
	st.generate_tangents()
	_cache.ring = st.commit()
	return _cache.ring

static func sphere() -> ArrayMesh:
	if not _cache.has("sphere"):
		var source := SphereMesh.new()
		source.radius = 0.5
		source.height = 1.0
		source.radial_segments = 32
		source.rings = 32
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.get_mesh_arrays())
		_cache.sphere = mesh
	return _cache.sphere

static func quad() -> QuadMesh:
	if not _cache.has("quad"):
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		_cache.quad = mesh
	return _cache.quad

static func cylinder() -> ArrayMesh:
	if _cache.has("cylinder"): return _cache.cylinder
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [Vector2(0.40,-0.5),Vector2(0.50,-0.4),Vector2(0.50,0.4),Vector2(0.40,0.5)]
	for ring_index in 3:
		for i in 24:
			for corner: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var angle := float(i+corner.x)*TAU/24.0
				var point: Vector2 = profile[ring_index+corner.y]
				var slope := -1.0 if ring_index == 0 else 1.0 if ring_index == 2 else 0.0
				st.set_normal(Vector3(cos(angle),slope,sin(angle)).normalized())
				st.set_uv(Vector2(float(i+corner.x)/24.0,point.y+0.5))
				st.add_vertex(Vector3(cos(angle)*point.x,point.y,sin(angle)*point.x))
	for side in [-1.0,1.0]:
		for i in 24:
			for j in [-1, i if side > 0 else i+1, i+1 if side > 0 else i]:
				var pos := Vector3(0,side*0.5,0)
				if j >= 0: pos += Vector3(cos(float(j)*TAU/24),0,sin(float(j)*TAU/24))*0.4
				st.set_normal(Vector3.UP*side)
				st.set_uv(Vector2(pos.x,pos.z)+Vector2.ONE*0.5)
				st.add_vertex(pos)
	st.generate_tangents()
	_cache.cylinder = st.commit()
	return _cache.cylinder

static func carapace() -> ArrayMesh:
	if not _cache.has("carapace"):
		var source := SphereMesh.new()
		source.radius = 0.5
		source.height = 1.0
		source.radial_segments = 16
		source.rings = 32
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.get_mesh_arrays())
		_cache.carapace = mesh
	return _cache.carapace

static func limb() -> ArrayMesh:
	if not _cache.has("limb"):
		var source := CylinderMesh.new()
		source.top_radius = 0.27
		source.bottom_radius = 0.5
		source.height = 1.0
		source.radial_segments = 24
		source.rings = 0
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.get_mesh_arrays())
		_cache.limb = mesh
	return _cache.limb

static func wing() -> ArrayMesh:
	if _cache.has("wing"): return _cache.wing
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tapered elliptical perimeter, with explicit reverse faces for the membrane.
	for side in [1.0,-1.0]:
		for i in 16:
			var angles := [float(i)*TAU/16,float(i+1)*TAU/16]
			if side < 0: angles.reverse()
			var points := [Vector3.ZERO]
			for angle: float in angles:
				var y := cos(angle)*0.5
				points.append(Vector3(sin(angle)*(0.34+0.14*(y+0.5)),y,0))
			for index in [0,1,2]:
				var point: Vector3 = points[index]
				st.set_normal(Vector3(0,0,side))
				st.set_uv(Vector2(point.x,point.y)+Vector2.ONE*0.5)
				st.add_vertex(point)
	_cache.wing = st.commit()
	_cache.wing.custom_aabb = AABB(Vector3(-0.5,-0.5,-0.075),Vector3(1,1,0.15))
	return _cache.wing

static func wedge() -> ArrayMesh:
	if _cache.has("wedge"): return _cache.wedge
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5,-0.5,-0.5)
	var b := Vector3(0.5,-0.5,-0.5)
	var c := Vector3(-0.5,0.5,-0.5)
	var d := Vector3(0.5,0.5,-0.5)
	var e := Vector3(-0.45,-0.3,0.5)
	var f := Vector3(0.45,-0.3,0.5)
	for face: Array in [[a,b,d,c],[a,e,f,b],[c,d,f,e],[a,c,e],[b,f,d]]:
		_face(st,face)
	st.generate_tangents()
	_cache.wedge = st.commit()
	return _cache.wedge

static func shard() -> ArrayMesh:
	if _cache.has("shard"): return _cache.shard
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.5,-0.5,-0.4),Vector3(0.5,-0.4,-0.3),Vector3(0.1,-0.2,0.5),Vector3(-0.15,0.5,0.05)]
	for ids: Array in [[0,1,2],[0,3,1],[1,3,2],[2,3,0]]:
		_face(st,[points[ids[0]],points[ids[1]],points[ids[2]]])
	st.generate_tangents()
	_cache.shard = st.commit()
	return _cache.shard

static func crescent() -> ArrayMesh:
	if _cache.has("crescent"): return _cache.crescent
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 32:
		var t0 := lerpf(-1.25,1.25,float(i)/32)
		var t1 := lerpf(-1.25,1.25,float(i+1)/32)
		var p0 := Vector3(sin(t0)*0.50,0,cos(t0)*0.65-0.43)
		var p1 := Vector3(sin(t1)*0.50,0,cos(t1)*0.65-0.43)
		var n0 := Vector3(sin(t0),0,cos(t0))*0.035
		var n1 := Vector3(sin(t1),0,cos(t1))*0.035
		var y := Vector3(0,0.30,0)
		var faces := [[p0-n0-y,p1-n1-y,p1+n1-y,p0+n0-y],[p0+n0+y,p1+n1+y,p1-n1+y,p0-n0+y],[p0+n0-y,p1+n1-y,p1+n1+y,p0+n0+y],[p0-n0+y,p1-n1+y,p1-n1-y,p0-n0-y]]
		var normals := [Vector3.DOWN,Vector3.UP,(n0+n1).normalized(),-(n0+n1).normalized()]
		for face_index in 4: _face(st,faces[face_index],normals[face_index])
		if i == 0: _face(st,[p0-n0-y,p0+n0-y,p0+n0+y,p0-n0+y],Vector3(-cos(t0),0,sin(t0)))
		if i == 31: _face(st,[p1-n1-y,p1+n1-y,p1+n1+y,p1-n1+y],Vector3(cos(t1),0,-sin(t1)))
	st.generate_tangents()
	_cache.crescent = st.commit()
	return _cache.crescent

static func trail() -> ArrayMesh:
	if _cache.has("trail"): return _cache.trail
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Crossed, two-sided ribbons. Width tapers continuously toward the aft tip.
	for axis in 2:
		for side in [1.0,-1.0]:
			for i in 8:
				for uv: Vector2 in [Vector2(0,float(i)/8),Vector2(1,float(i+1)/8),Vector2(1,float(i)/8),Vector2(0,float(i)/8),Vector2(0,float(i+1)/8),Vector2(1,float(i+1)/8)]:
					var point := Vector3((uv.x-0.5)*uv.y,0,uv.y-0.5)
					if axis == 1: point = Vector3(0,point.x,point.z)
					if side < 0: point = Vector3(-point.x,-point.y,point.z)
					st.set_normal((Vector3.UP if axis == 0 else Vector3.RIGHT)*side)
					st.set_uv(uv)
					st.add_vertex(point)
	_cache.trail = st.commit()
	return _cache.trail

static func wave_arc() -> ArrayMesh:
	if _cache.has("wave_arc"): return _cache.wave_arc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A shallow circular arc, authored in metres: 5.36 wide, 0.39 high.
	# Radius 13m, lower major circle lies below the floor; only the crest is built.
	for i in 64:
		for j in 8:
			for corner: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var u := float(i+corner.x)/64
				var v := float(j+corner.y)/8
				var angle := lerpf(-0.205,0.205,u)
				var radial := Vector3(sin(angle),cos(angle),0)
				var n := radial*cos(v*TAU)+Vector3.BACK*sin(v*TAU)
				var p := Vector3(13*sin(angle),13*cos(angle)-12.72,0)+n*0.055
				st.set_normal(n)
				st.set_uv(Vector2(u,v))
				st.add_vertex(Vector3(p.x/5.41,(p.y-0.144)/0.39,p.z/0.11))
	st.generate_tangents()
	_cache.wave_arc = st.commit()
	return _cache.wave_arc

static func jointed_leg() -> ArrayMesh:
	if _cache.has("jointed_leg"): return _cache.jointed_leg
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two 24-sided tapered sections share a bent knee; the foot closes to a point.
	var centers := [Vector3(-0.5,0.35,0),Vector3(0.12,0.08,0),Vector3(0.5,-0.5,0)]
	var radii := [0.11,0.075,0.0]
	for segment in 2:
		for side in 24:
			var corners := [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1)] if segment == 1 else [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]
			for corner: Vector2i in corners:
				var angle := TAU*float(side+corner.y)/24.0
				var ring := segment+corner.x
				var normal := Vector3(0,cos(angle),sin(angle))
				st.set_normal(normal)
				st.set_uv(Vector2(float(side+corner.y)/24.0,float(ring)/2.0))
				st.add_vertex(centers[ring]+normal*radii[ring])
	st.generate_tangents()
	_cache.jointed_leg = st.commit()
	return _cache.jointed_leg

static func plasma_sphere() -> ArrayMesh:
	if not _cache.has("plasma_sphere"):
		var source := SphereMesh.new()
		source.radius = 0.5
		source.height = 1.0
		source.radial_segments = 40
		source.rings = 36
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.get_mesh_arrays())
		_cache.plasma_sphere = mesh
	return _cache.plasma_sphere


static func shard_glint() -> ArrayMesh:
	if _cache.has("shard_glint"): return _cache.shard_glint
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# One outward-facing tetrahedron facet, displaced slightly to avoid z fighting.
	_face(st,[Vector3(0.501,-0.4,-0.299),Vector3(-0.149,0.5,0.051),Vector3(0.101,-0.2,0.501)])
	st.generate_tangents()
	_cache.shard_glint = st.commit()
	return _cache.shard_glint
