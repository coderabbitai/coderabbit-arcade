extends "res://scenes/runner/pursuer/pursuer_visual_base.gd"
## QUARANTINE: compact rabbit-eared repo security drone. Cosmetic-only rig.
const Forge = preload("res://scenes/runner/pursuer/hifi/forge.gd")
# Existing alert copy remains compatible with the HUD's rotating status messages.
const HEADLINES := ["PR #3312 UNREVIEWED", "CHANGES REQUESTED", "STALE", "NEEDS REBASE", "DO NOT MERGE", "0 approvals"]
const ARMOR := Color("c4d0d1")
const DARK := Color("142735")
const METAL := Color("607d8a")
const RED := Color("ff4d3d")
var _wall: Node3D
var _light: OmniLight3D
var _arms: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _fans: Array[Node3D] = []
var _jets: MeshInstance3D
var _t := 0.0
var _threat := 0.0
var _reaction: StringName = &"idle"
var _reaction_time := 0.0
var _retreated := true
var _start_pose := Transform3D.IDENTITY
var _last_threat_pose := Transform3D.IDENTITY

func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
func _ready() -> void:
	_build()
	_apply()
func surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st
func part(st: SurfaceTool, size: Vector3, pos: Vector3, color := ARMOR, angle := 0.0) -> void:
	Forge.chassis_part(st,size,pos,color,minf(0.07,minf(size.x,minf(size.y,size.z))*0.22),angle)
func mesh_node(title: String, mesh: Mesh, parent: Node3D, emissive := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.25
	mat.roughness = 0.48
	if emissive:
		mat.albedo_color = RED
		mat.emission_enabled = true
		mat.emission = RED
		mat.emission_energy_multiplier = 0.65
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
func _build() -> void:
	if _wall != null: return
	_wall = Node3D.new()
	_wall.name = "Hunter"
	add_child(_wall)
	var shell := surface()
	# Faceted central head, projecting brow and small sensor snout.
	part(shell,Vector3(0.94,0.59,0.67),Vector3(0,1.30,0))
	part(shell,Vector3(0.85,0.26,0.08),Vector3(0,1.34,0.36),DARK)
	part(shell,Vector3(0.98,0.13,0.27),Vector3(0,1.57,0.23),METAL)
	part(shell,Vector3(0.28,0.18,0.23),Vector3(0,1.11,0.37),ARMOR)
	part(shell,Vector3(0.11,0.07,0.08),Vector3(0,1.15,0.51),DARK)
	part(shell,Vector3(0.61,0.30,0.49),Vector3(0,0.92,-0.05),METAL)
	for side in [-1.0,1.0]:
		part(shell,Vector3(0.33,0.12,0.24),Vector3(side*0.56,1.22,0),DARK)
		part(shell,Vector3(0.16,0.32,0.32),Vector3(side*0.44,1.29,-0.03),METAL)
		# Physical code-bracket cheek marks, instead of labels or panels.
		for y in [1.21,1.38]: part(shell,Vector3(0.09,0.035,0.025),Vector3(side*0.38,y,0.411),RED)
		part(shell,Vector3(0.035,0.19,0.025),Vector3(side*0.415,1.295,0.411),RED)
	mesh_node("HeadAndTorso",shell.commit(),_wall)
	var eyes := surface()
	for side in [-1.0,1.0]: part(eyes,Vector3(0.24,0.065,0.045),Vector3(side*0.18,1.36,0.412),Color.WHITE,side*0.16)
	mesh_node("Optics",eyes.commit(),_wall,true)
	for side in [-1.0,1.0]:
		var ear := Node3D.new()
		ear.name = "AntennaL" if side < 0 else "AntennaR"
		_wall.add_child(ear)
		ear.position = Vector3(side*0.27,1.57,-0.10)
		var e := surface()
		part(e,Vector3(0.17,0.62,0.16),Vector3(0,0.27,0),ARMOR,side*0.14)
		part(e,Vector3(0.045,0.39,0.03),Vector3(0,0.28,0.09),RED,side*0.14)
		mesh_node("Receiver",e.commit(),ear)
		_ears.append(ear)
		var arm := Node3D.new()
		arm.name = "ClawL" if side < 0 else "ClawR"
		_wall.add_child(arm)
		arm.position = Vector3(side*0.51,1.03,0.04)
		var a := surface()
		part(a,Vector3(0.15,0.37,0.19),Vector3(side*0.09,-0.15,0),METAL,-side*0.30)
		part(a,Vector3(0.22,0.14,0.28),Vector3(side*0.14,-0.35,0.11),ARMOR)
		for finger in [-1.0,1.0]:
			part(a,Vector3(0.055,0.19,0.13),Vector3(side*0.14+finger*0.085,-0.45,0.19),DARK,finger*0.15)
			part(a,Vector3(0.09,0.055,0.13),Vector3(side*0.14+finger*0.063,-0.51,0.24),RED)
		mesh_node("Pincer",a.commit(),arm)
		_arms.append(arm)
		# Twin ducted lift fans give the pursuer a believable propulsion silhouette.
		var housing := TorusMesh.new()
		housing.inner_radius = 0.19
		housing.outer_radius = 0.30
		housing.rings = 32
		housing.ring_segments = 12
		var duct := mesh_node("LiftDuct",housing,_wall)
		duct.material_override.albedo_color = METAL
		duct.position = Vector3(side*0.77,1.12,-0.10)
		duct.rotation.x = PI/2
		var fan := Node3D.new()
		_wall.add_child(fan)
		fan.position = duct.position
		var blades := surface()
		for i in 5:
			var angle := i*TAU/5
			part(blades,Vector3(0.07,0.23,0.045),Vector3(sin(-angle)*0.09,cos(angle)*0.09,0),DARK,angle)
		mesh_node("Rotor",blades.commit(),fan)
		_fans.append(fan)
	var jets := surface()
	for side in [-1.0,1.0]: part(jets,Vector3(0.11,0.25,0.12),Vector3(side*0.77,0.72,-0.10),Color.WHITE)
	_jets = mesh_node("Thrust",jets.commit(),_wall,true)
	_light = OmniLight3D.new()
	_light.name = "RedLight"
	_light.light_color = RED
	_light.omni_range = 3
	_light.position = Vector3(0,1.2,0.7)
	add_child(_light)
	_configure(self)
func _configure(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in node.get_children(): _configure(child)
func set_threat(value: float) -> void:
	_build()
	_threat = clampf(value,0,1)
	if _reaction != &"idle":
		if (_reaction == &"catch" and (_threat <= 0.001 or _reaction_time >= 1.4)) or (_threat > 0.001 and (_reaction == &"retreat" or _retreated)):
			_reaction = &"idle"
			_retreated = _threat <= 0.001
		else: return
	if _threat > 0.001: _retreated = false
	_apply()
func play_catch() -> void:
	_build()
	if _reaction == &"catch": return
	show()
	_retreated = false
	_reaction = &"catch"
	_reaction_time = 0
	_start_pose = _wall.transform
func play_retreat() -> void:
	_build()
	if _reaction == &"retreat": return
	# While the backend is still gliding the threat down, its next set_threat() cancels a retreat on
	# the following tick; starting one here only flashed the light off and the pose back for a frame.
	if _threat > 0.001: return
	show()
	_reaction = &"retreat"
	_reaction_time = 0
	_start_pose = _last_threat_pose
	_wall.transform = _start_pose
	_set_light(0.0)
func _process(delta: float) -> void:
	_t += delta
	if _wall == null: return
	if _reaction == &"idle": _apply()
	else:
		_reaction_time += delta
		_wall.transform = _start_pose
		if _reaction == &"catch":
			var u := smoothstep(0,1,clampf(_reaction_time/1.4,0,1))
			_wall.position.z += 2.3*u
			_wall.position.y += 0.65*sin(u*PI*0.5)
			_wall.rotation.x = -0.22*sin(u*PI)
			_set_light(3.0)
		else:
			var u := clampf(_reaction_time/0.7,0,1)
			_wall.position.z -= 2*u
			_wall.rotation.y = u*PI
			_wall.scale = Vector3.ONE*maxf(0.001,1-u)
			if u >= 1:
				_retreated = true
				_reaction = &"idle"
				_threat = 0
				hide()
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_ears[i].rotation.z = side*(0.12+0.08*sin(_t*2+i))
		_ears[i].rotation.x = -0.12*_threat
		_arms[i].rotation.x = -0.85*sin(clampf(_reaction_time/1.4,0,1)*PI) if _reaction == &"catch" else 0.10*sin(_t*3+i)
		_arms[i].rotation.z = side*(0.16 if _reaction == &"catch" else 0.06*sin(_t*2))
		_fans[i].rotation.z = side*_t*(18+_threat*15)
	_jets.scale.y = 1+0.06*sin(_t*26)
func _apply() -> void:
	visible = not (_retreated and _threat <= 0.001)
	_wall.transform = Transform3D.IDENTITY
	_wall.position = Vector3(sin(_t*1.7)*0.07, sin(_t*3)*0.055,0)
	_wall.rotation.z = sin(_t*1.7)*0.035
	_wall.rotation.x = -0.08*_threat
	if _threat > 0.001: _last_threat_pose = _wall.transform
	_set_light(1.5*_threat)
# The light is re-posed every frame; only a visible energy change is worth a renderer update.
func _set_light(energy: float) -> void:
	if absf(_light.light_energy - energy) >= 0.01 or (energy == 0.0 and _light.light_energy != 0.0):
		_light.light_energy = energy
