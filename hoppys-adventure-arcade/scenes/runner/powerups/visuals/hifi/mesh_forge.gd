extends RefCounted
## Clockwise faces for Godot, outward authored normals, local charts per face.
var surface := SurfaceTool.new()
var vertex_count := 0
var color := Color.WHITE
var panel_bounds: Array[AABB] = []

func _init() -> void:
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

func triangle(points: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2]) -> void:
	for i in [0, 2, 1]:
		surface.set_color(color)
		surface.set_normal(normals[i])
		surface.set_uv(uvs[i])
		surface.add_vertex(points[i])
		vertex_count += 1

func flat_triangle(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var normal := (b - a).cross(c - a).normalized()
	triangle([a,b,c], [normal,normal,normal], [ua,ub,uc])

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Each bevel/side strip has its own undistorted rectangular chart.
	flat_triangle(a,b,c,Vector2.ZERO,Vector2.RIGHT,Vector2.ONE)
	flat_triangle(a,c,d,Vector2.ZERO,Vector2.ONE,Vector2.DOWN)

func inset(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points.size():
		var before := (points[i] - points[posmod(i-1,points.size())]).normalized()
		var after := (points[(i+1)%points.size()] - points[i]).normalized()
		var n0 := Vector2(-before.y,before.x)
		var n1 := Vector2(-after.y,after.x)
		var bisector := (n0+n1).normalized()
		var distance := minf(amount/maxf(0.1,bisector.dot(n1)),amount*3.0)
		result.append(points[i]+bisector*distance)
	return result

func panel(points: PackedVector2Array, depth: float, bevel: float, center := Vector3.ZERO) -> void:
	var outline := points.duplicate()
	if Geometry2D.is_polygon_clockwise(outline): outline.reverse()
	var part_bounds := AABB(center+Vector3(outline[0].x,outline[0].y,-depth/2),Vector3.ZERO)
	for point in outline:
		part_bounds = part_bounds.expand(center+Vector3(point.x,point.y,-depth/2))
		part_bounds = part_bounds.expand(center+Vector3(point.x,point.y,depth/2))
	panel_bounds.append(part_bounds)
	var inner := inset(outline,bevel)
	var bounds := Rect2(outline[0],Vector2.ZERO)
	for point in outline: bounds = bounds.expand(point)
	var indices := Geometry2D.triangulate_polygon(inner)
	for sign_z: float in [-1.0,1.0]:
		for i in range(0,indices.size(),3):
			var a := inner[indices[i]]
			var b := inner[indices[i+1]]
			var c := inner[indices[i+2]]
			if sign_z < 0:
				var swap := b
				b = c
				c = swap
			flat_triangle(center+Vector3(a.x,a.y,sign_z*depth/2),center+Vector3(b.x,b.y,sign_z*depth/2),center+Vector3(c.x,c.y,sign_z*depth/2),(a-bounds.position)/bounds.size,(b-bounds.position)/bounds.size,(c-bounds.position)/bounds.size)
	for i in outline.size():
		var j := (i+1)%outline.size()
		var a := outline[i]
		var b := outline[j]
		var ia := inner[i]
		var ib := inner[j]
		var z := depth/2-bevel
		quad(center+Vector3(a.x,a.y,-z),center+Vector3(b.x,b.y,-z),center+Vector3(b.x,b.y,z),center+Vector3(a.x,a.y,z))
		quad(center+Vector3(a.x,a.y,z),center+Vector3(b.x,b.y,z),center+Vector3(ib.x,ib.y,depth/2),center+Vector3(ia.x,ia.y,depth/2))
		quad(center+Vector3(b.x,b.y,-z),center+Vector3(a.x,a.y,-z),center+Vector3(ia.x,ia.y,-depth/2),center+Vector3(ib.x,ib.y,-depth/2))

func bar(center: Vector3, size: Vector2, angle := 0.0, depth := 0.055) -> void:
	var points := PackedVector2Array()
	for point: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		points.append((point*size/2).rotated(angle))
	panel(points,depth,minf(0.008,minf(size.x,size.y)*0.18),center)

func tube(path: PackedVector3Array, radius: float, sides := 24) -> void:
	assert(sides >= 24)
	var closed := path[0].is_equal_approx(path[-1])
	var tangents: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var lengths: Array[float] = [0.0]
	for i in path.size():
		var previous := path[maxi(i-1,0)]
		var next := path[mini(i+1,path.size()-1)]
		if closed and (i == 0 or i == path.size()-1):
			previous = path[-2]
			next = path[1]
		tangents.append((next-previous).normalized())
		if i > 0: lengths.append(lengths[-1]+path[i].distance_to(path[i-1]))
	var seed := Vector3.UP if absf(tangents[0].y) < 0.9 else Vector3.RIGHT
	normals.append((seed-tangents[0]*seed.dot(tangents[0])).normalized())
	for i in range(1,path.size()):
		var transported := Quaternion(tangents[i-1],tangents[i]) * normals[-1]
		normals.append((transported-tangents[i]*transported.dot(tangents[i])).normalized())
	if closed: normals[-1] = normals[0]
	for i in path.size()-1:
		for j in sides:
			var points: Array[Vector3] = []
			var radial: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for corner: Vector2i in [Vector2i(i,j),Vector2i(i,j+1),Vector2i(i+1,j+1),Vector2i(i+1,j)]:
				var angle := TAU*corner.y/sides
				var n := normals[corner.x]*cos(angle)+tangents[corner.x].cross(normals[corner.x])*sin(angle)
				points.append(path[corner.x]+radius*n)
				radial.append(n)
				uvs.append(Vector2(lengths[corner.x]/lengths[-1],float(corner.y)/sides))
			# Outward orientation follows tangent x radial frame.
			triangle([points[0],points[1],points[2]],[radial[0],radial[1],radial[2]],[uvs[0],uvs[1],uvs[2]])
			triangle([points[0],points[2],points[3]],[radial[0],radial[2],radial[3]],[uvs[0],uvs[2],uvs[3]])
	if not closed:
		for end in [0,path.size()-1]:
			var outward := -tangents[end] if end == 0 else tangents[end]
			var u := normals[end]
			var v := outward.cross(u)
			for j in sides:
				var a := Vector2(cos(TAU*j/sides),sin(TAU*j/sides))
				var b := Vector2(cos(TAU*(j+1)/sides),sin(TAU*(j+1)/sides))
				triangle([path[end],path[end]+radius*(u*a.x+v*a.y),path[end]+radius*(u*b.x+v*b.y)],[outward,outward,outward],[Vector2.ONE*0.5,a*0.5+Vector2.ONE*0.5,b*0.5+Vector2.ONE*0.5])

func ring(center: Vector3, radius: float, width: float, segments := 32) -> void:
	var path := PackedVector3Array()
	for i in segments+1:
		var angle := TAU*i/segments
		path.append(center+Vector3(cos(angle),sin(angle),0)*radius)
	tube(path,width)

func finish() -> ArrayMesh:
	assert(vertex_count > 0)
	surface.index()
	surface.generate_tangents()
	var mesh := surface.commit()
	mesh.set_meta("panel_bounds",panel_bounds.duplicate())
	return mesh
