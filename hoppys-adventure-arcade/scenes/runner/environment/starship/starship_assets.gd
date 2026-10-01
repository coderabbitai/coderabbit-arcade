extends RefCounted
## Original reusable engineered starship geometry. No collision or gameplay nodes.
const Forge = preload("res://scenes/runner/environment/hifi/mesh_forge.gd")
const Surface = preload("res://scenes/runner/environment/starship/starship_surface.gdshader")
static var _noise: ImageTexture
static var _meshes: Array[ArrayMesh] = []
const HULL := 0
const DARK := 1
const ALLOY := 2
const CONDUIT := 3
const WINDOW := 4
const ENERGY := 5

static func material(kind: int) -> ShaderMaterial:
	if _noise == null:
		var noise := FastNoiseLite.new()
		noise.seed = 240922
		noise.frequency = 0.045
		noise.fractal_octaves = 5
		var image := noise.get_seamless_image(256,256)
		image.generate_mipmaps()
		_noise = ImageTexture.create_from_image(image)
	var mat := ShaderMaterial.new()
	mat.shader = Surface
	mat.set_shader_parameter("detail_map",_noise)
	mat.set_shader_parameter("tint",[Color("83939f"),Color("364553"),Color("445b70"),Color("8ce5cb"),Color("091625"),Color("ffac62")][kind])
	mat.set_shader_parameter("metallic",0.68 if kind in [HULL,DARK,ALLOY] else 0.15)
	mat.set_shader_parameter("glow",1.2 if kind == ENERGY else (0.8 if kind == CONDUIT else 0.0))
	mat.set_shader_parameter("window_mode",kind == WINDOW)
	return mat

static func box(st: SurfaceTool, p: Vector3, size: Vector3, shade: float = 1.0, bevel: float = 0.06) -> void:
	Forge.box(st,p,size,bevel,Color(shade,shade,shade,1))

## Flat six-quad slab (12 triangles): bevel-free hull plating that keeps the module budget.
static func slab(st: SurfaceTool, p: Vector3, size: Vector3, shade: float = 1.0) -> void:
	var h := size*0.5
	var color := Color(shade,shade,shade,1)
	for axis in 3:
		var u := (axis+1)%3
		var v := (axis+2)%3
		for sign_ in [-1.0,1.0]:
			var points: Array[Vector3] = []
			for pair in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var q := Vector3.ZERO
				q[axis] = h[axis]*sign_
				q[u] = h[u]*pair.x
				q[v] = h[v]*pair.y
				points.append(q)
			Forge.polygon(st,points,p,color)

static func wedge(st: SurfaceTool, angle: float, radius: float, y: float, z: float, thickness: float, depth: float, step: float) -> void:
	var vertices: Array[Vector3] = []
	for side in [-1.0,1.0]:
		for r in [radius,radius+thickness]:
			for a in [angle-step*0.47,angle+step*0.47]:
				vertices.append(Vector3(cos(a)*r,y+sin(a)*r,z+side*depth*0.5))
	var center := Vector3.ZERO
	for p in vertices: center += p/8.0
	for face in [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]:
		var points: Array[Vector3] = []
		for i in face: points.append(vertices[i]-center)
		Forge.polygon(st,points,center,Color(0.92,0.92,0.92,1))

static func beam(st: SurfaceTool, a: Vector3, b: Vector3, width: float, depth: float, shade: float = 1.0) -> void:
	var along := (b-a).normalized()
	var across := Vector3(along.y,-along.x,0)*width*0.5
	var forward := Vector3(0,0,depth*0.5)
	var center := (a+b)*0.5
	var points: Array[Vector3] = [a-across-forward,a+across-forward,b+across-forward,b-across-forward,a-across+forward,a+across+forward,b+across+forward,b-across+forward]
	for face in [[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[0,3,7,4],[1,5,6,2]]:
		var polygon: Array[Vector3] = []
		for i in face: polygon.append(points[i]-center)
		Forge.polygon(st,polygon,center,Color(shade,shade,shade,1))

static func module_meshes() -> Array[ArrayMesh]:
	if not _meshes.is_empty(): return _meshes
	var parts: Array[SurfaceTool] = []
	for i in 6:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts.append(st)
	for side in [-1.0,1.0]:
		var x: float = side*4.6
		# Octagonal pressure bulkheads and layered load-bearing feet.
		box(parts[ALLOY],Vector3(x,0.22,0),Vector3(1.1,0.44,1.5),0.8,0.15)
		box(parts[HULL],Vector3(x,2.45,0),Vector3(0.58,4.6,0.85),1.0,0.12)
		box(parts[DARK],Vector3(x-side*0.31,2.6,0),Vector3(0.075,3.1,0.52))
		box(parts[CONDUIT],Vector3(x-side*0.36,2.6,0),Vector3(0.035,2.0,0.09),1.0,0.01)
		beam(parts[HULL],Vector3(x,4.6,0),Vector3(side*2.65,6.65,0),0.58,0.85)
		beam(parts[CONDUIT],Vector3(x-side*0.13,4.45,0.44),Vector3(side*2.55,6.44,0.44),0.07,0.025)
		for h in [0.8,3.9]:
			box(parts[ALLOY],Vector3(x,h,0),Vector3(0.75,0.26,1.05),1.0,0.055)
		# Solid hull walls: continuous plating closes every 12 m module end to end (seams sit behind
		# the next bulkhead), leaving one small inset porthole per side instead of a space vista.
		box(parts[DARK],Vector3(side*5.62,0.85,6.0),Vector3(0.45,1.7,12.0),0.8)
		box(parts[DARK],Vector3(side*5.62,5.65,6.0),Vector3(0.45,1.55,12.0),1.0)
		slab(parts[DARK],Vector3(side*5.9,3.28,6.0),Vector3(0.1,3.4,12.0),0.45)
		# Hull panels with 5 cm inset seams showing the dark backing plate.
		for panel: Array in [[0.0,2.18,1.72,4.85,0.92],[2.2,3.8,1.72,2.63,0.86],[2.2,3.8,3.81,4.85,0.86],[3.82,6.9,1.72,4.85,0.98],[6.95,12.0,1.72,3.24,0.9],[6.95,12.0,3.29,4.85,0.94]]:
			slab(parts[HULL],Vector3(side*5.66,(panel[2]+panel[3])*0.5,(panel[0]+panel[1])*0.5),Vector3(0.28,panel[3]-panel[2],panel[1]-panel[0]),panel[4])
		# One small porthole (1.6 x 1.1 m) recessed behind the plating inside an alloy rim.
		slab(parts[WINDOW],Vector3(side*5.79,3.22,3.0),Vector3(0.02,1.1,1.6))
		for rim: Array in [[3.0,2.62,1.84,0.12],[3.0,3.82,1.84,0.12],[2.14,3.22,0.12,1.32],[3.86,3.22,0.12,1.32]]:
			slab(parts[ALLOY],Vector3(side*5.49,rim[1],rim[0]),Vector3(0.1,rim[3],rim[2]),0.9)
		for y in [1.66,4.78]:
			box(parts[HULL],Vector3(side*5.44,y,5.8),Vector3(0.3,0.18,11.3))
			box(parts[CONDUIT],Vector3(side*5.25,y,5.8),Vector3(0.025,0.035,10.4),0.55,0.005)
		# Floor-edge skirting, plus a sub-deck filler under the trench so the chord sag of 12 m pieces
		# against the finely bent deck never opens a sliver during turns.
		slab(parts[DARK],Vector3(side*5.2,0.22,6.0),Vector3(0.5,1.04,12.0),0.7)
		slab(parts[DARK],Vector3(side*4.14,-0.175,6.0),Vector3(1.68,0.25,12.0),0.6)
		# Armoured equipment bay breaks up the plating with layered access panels.
		box(parts[HULL],Vector3(side*5.33,3.23,9.05),Vector3(0.28,2.72,2.55),0.8,0.13)
		box(parts[DARK],Vector3(side*5.14,3.23,9.05),Vector3(0.15,2.28,2.14),0.95,0.12)
		for panel in [-1.0,1.0]:
			box(parts[ALLOY],Vector3(side*5.02,3.25,9.05+panel*0.65),Vector3(0.17,1.8,0.55),0.94,0.07)
			for vent in 3:
				box(parts[DARK],Vector3(side*4.91,2.65+vent*0.60,9.05+panel*0.65),Vector3(0.06,0.065,0.40),0.6,0.01)
		box(parts[CONDUIT],Vector3(side*4.94,3.35,9.05),Vector3(0.04,1.05,0.085),0.65,0.02)
		for diode in 3:
			box(parts[ENERGY],Vector3(side*4.98,2.42,8.83+diode*0.22),Vector3(0.04,0.07,0.09),0.65,0.01)
		# Deck-edge service trenches and orange power trunks.
		box(parts[ALLOY],Vector3(side*4.13,-0.13,5.7),Vector3(0.50,0.22,12),0.6)
		box(parts[ENERGY],Vector3(side*4.12,-0.005,5.7),Vector3(0.075,0.04,12),0.6,0.01)
		box(parts[HULL],Vector3(side*4.78,0.37,5.7),Vector3(0.42,0.74,11.7),0.7,0.09)
		for z in [2.0,5.0,8.0,11.0]:
			box(parts[DARK],Vector3(side*4.54,0.40,z),Vector3(0.10,0.32,2.55))
			for vent in 3:
				box(parts[ALLOY],Vector3(side*4.47,0.4,z-0.85+vent*0.84),Vector3(0.06,0.28,0.07),1.0,0.01)
		# Suspended coolant machinery, layered armour, vents and status lights.
		for z in [3.0,9.0]:
			box(parts[ALLOY],Vector3(side*5.02,5.2,z),Vector3(0.8,0.85,1.9),0.72,0.17)
			box(parts[HULL],Vector3(side*4.55,5.22,z),Vector3(0.14,0.55,1.45),0.8,0.06)
			for fin in 5:
				box(parts[DARK],Vector3(side*4.45,5.2,z-0.48+fin*0.24),Vector3(0.12,0.35,0.10),1.0,0.025)
			box(parts[ENERGY],Vector3(side*4.45,5.51,z),Vector3(0.04,0.055,0.9),0.5,0.01)
		# Ceiling conduits and ribbed angled hull plates.
		beam(parts[DARK],Vector3(side*5.5,5.3,6.0),Vector3(side*2.9,7.15,6.0),0.28,12.0,1.0)
		box(parts[ALLOY],Vector3(side*2.8,6.85,5.8),Vector3(0.34,0.28,12),0.7)
		box(parts[CONDUIT],Vector3(side*2.5,6.69,5.8),Vector3(0.12,0.04,10.2),0.8,0.01)
	box(parts[HULL],Vector3(0,6.67,0),Vector3(5.7,0.55,0.9),0.88,0.10)
	box(parts[DARK],Vector3(0,7.08,6.0),Vector3(5.6,0.22,12.0),0.6)
	for z in [2.0,5.0,8.0,11.0]:
		box(parts[ALLOY],Vector3(0,6.9,z),Vector3(5.1,0.15,0.14),0.85)
		box(parts[HULL],Vector3(0,6.8,z),Vector3(1.8,0.10,1.35),0.8)
		box(parts[CONDUIT],Vector3(0,6.73,z),Vector3(1.4,0.025,0.58),0.72,0.01)
	# Small amber bulkhead identifier strips establish rhythm at speed.
	for i in 3:
		box(parts[ENERGY],Vector3(-0.28+i*0.28,6.65,0.47),Vector3(0.13,0.15,0.02),0.6,0.01)
	for st in parts:
		st.generate_tangents()
		_meshes.append(st.commit())
	return _meshes
