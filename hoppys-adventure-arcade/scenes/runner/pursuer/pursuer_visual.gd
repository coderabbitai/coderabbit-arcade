extends "res://scenes/runner/pursuer/pursuer_visual_base.gd"
## QUARANTINE: compact rabbit-eared repo security drone. Cosmetic-only rig.
const Forge = preload("res://scenes/runner/pursuer/hifi/forge.gd")
# Existing alert copy remains compatible with the HUD's rotating status messages.
const HEADLINES := ["PR #3312 UNREVIEWED", "CHANGES REQUESTED", "STALE", "NEEDS REBASE", "DO NOT MERGE", "0 approvals"]
const ARMOR := Color("c4d0d1")
const DARK := Color("142735")
const METAL := Color("607d8a")
const RED := Color("ff4d3d")
const Field = preload("res://scenes/runner/pursuer/hifi/quarantine_field.gdshader")
## The catch (contract §5.4), timed from play_catch(). The drone notices (ALERT), pounces over
## Hoppy while turning to face him (POUNCE), dives and clamps its claws on him at CLAMP_AT, the
## moment hifi/knockout_rig.gd pins him, then drops the QUARANTINE field and holds him there
## until the run ends.
const ALERT := 0.35
const POUNCE := 1.2
const CLAMP_AT := 1.6
const FIELD_RISE := 0.25
## Where a knocked-out Hoppy lies, from his player origin: the dead clip lays him face-down along
## -Z, feet at the origin and ear tips about 1.6 m ahead, so this is his torso.
const VICTIM_OFFSET := Vector3(0, 0, -0.9)
## The containment field's half-extents (x, height, z) around him.
const FIELD_SIZE := Vector3(0.62, 0.95, 1.05)
const LIGHT_HOME := Vector3(0, 1.2, 0.7)
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
## The drone's world pose when the catch began, and the field it drops.
var _catch_from := Transform3D.IDENTITY
var _field: MeshInstance3D
var _field_material: ShaderMaterial

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
	_light.position = LIGHT_HOME
	add_child(_light)
	_build_field()
	_configure(self)
## One mesh: twelve bars, three elliptical rings and a faint wall, in unit space (radius 1,
## height 1); the node's scale sets FIELD_SIZE. It is placed in world space over the victim.
func _build_field() -> void:
	var st := surface()
	var bars := 12
	for i in bars:
		var a := i*TAU/bars
		_strip(st,Vector3(cos(a),0,sin(a)),Vector3(cos(a),1,sin(a)),0.035,Color.WHITE)
	var ring := 32
	for height in [0.02,0.5,1.0]:
		for i in ring:
			var a := i*TAU/ring
			var b := (i+1)*TAU/ring
			_strip(st,Vector3(cos(a),height,sin(a)),Vector3(cos(b),height,sin(b)),0.06 if height < 0.1 else 0.03,Color(0.6,0.6,0.6) if height == 0.5 else Color.WHITE)
	var low := Color(0.22,0.22,0.22)
	var high := Color(0.02,0.02,0.02)
	for i in ring:
		var a := i*TAU/ring
		var b := (i+1)*TAU/ring
		for corner in [[a,0.0,low],[b,0.0,low],[b,1.0,high],[a,0.0,low],[b,1.0,high],[a,1.0,high]]:
			st.set_color(corner[2])
			st.add_vertex(Vector3(cos(corner[0]),corner[1],sin(corner[0])))
	_field = MeshInstance3D.new()
	_field.name = "QuarantineField"
	_field.mesh = st.commit()
	_field_material = ShaderMaterial.new()
	_field_material.shader = Field
	_field.material_override = _field_material
	_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_field.top_level = true
	_field.visible = false
	add_child(_field)
## A flat glowing strip from a to b, `width` wide, facing outward from the field's axis.
func _strip(st: SurfaceTool, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var along := (b-a).normalized()
	var out := Vector3(a.x+b.x,0,a.z+b.z).normalized()
	var side := along.cross(out).normalized()*width*0.5
	st.set_color(color)
	for v in [a-side,b-side,b+side,a-side,b+side,a+side]: st.add_vertex(v)
func _configure(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in node.get_children(): _configure(child)
func set_threat(value: float) -> void:
	_build()
	_threat = clampf(value,0,1)
	if _reaction != &"idle":
		# A catch holds Hoppy until the run resets the threat to 0.
		if (_reaction == &"catch" and _threat <= 0.001) or (_threat > 0.001 and (_reaction == &"retreat" or _retreated)):
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
	_catch_from = _wall.global_transform
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
			_pose_catch(_reaction_time)
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
		if _reaction == &"catch": _pose_claw(i,side,_reaction_time)
		else:
			_arms[i].rotation.x = 0.10*sin(_t*3+i)
			_arms[i].rotation.z = side*0.06*sin(_t*2)
		_fans[i].rotation.z = side*_t*(18+_threat*15)
	_jets.scale.y = 1+0.06*sin(_t*26)
## Where Hoppy lies, in world space: from the backend's player when there is one, else 4 m
## ahead of where the drone started (previews and the standalone smoke).
func _victim() -> Vector3:
	# The backend pursuer (pursuer.gd) owns `game`; the visual is mounted below it.
	var host := get_parent()
	while host != null and not ("game" in host): host = host.get_parent()
	var game: Variant = host.get("game") if host != null else null
	if game is Node and is_instance_valid(game) and game.get("player") is Node3D:
		var body: Node3D = game.player
		return Vector3(body.global_position.x,0,body.global_position.z)+VICTIM_OFFSET
	return Vector3(_catch_from.origin.x,0,_catch_from.origin.z-4.0)+VICTIM_OFFSET
## The drone's world pose through the catch. It rears back, leaps over Hoppy (keeping its eyes on
## him and the camera) and lands beyond his head, so he stays in view in front of it. Then it
## leans over him, jolts as the claws bite, and hovers there menacingly.
func _pose_catch(t: float) -> void:
	var victim := _victim()
	var land := Transform3D(Basis.IDENTITY,victim+Vector3(0,0.3,-1.8))
	var pin := Transform3D(Basis(Vector3.RIGHT,0.36),victim+Vector3(0,-0.04,-1.55))
	var pose := _catch_from
	if t < ALERT:
		pose.origin += Vector3(0,0.18*sin(PI*0.5*t/ALERT),0.15*sin(PI*0.5*t/ALERT))
		pose.basis = pose.basis*Basis(Vector3.RIGHT,0.16*sin(PI*t/ALERT))
	elif t < POUNCE:
		var u := smoothstep(0,1,(t-ALERT)/(POUNCE-ALERT))
		pose = _catch_from.translated(Vector3(0,0.18,0.15)).interpolate_with(land,u)
		pose.origin.y += 1.5*sin(PI*u)
		pose.basis = pose.basis*Basis(Vector3.RIGHT,-0.45*sin(PI*u))
	elif t < CLAMP_AT:
		var u := (t-POUNCE)/(CLAMP_AT-POUNCE)
		pose = land.interpolate_with(pin,u*u)
	else:
		var held := t-CLAMP_AT
		pose = pin
		pose.origin.y += -0.07*sin(PI*clampf(held/0.18,0,1))+0.03*sin(held*4.0)
	_wall.global_transform = pose
	var energy := 3.0
	if t < ALERT: energy = lerpf(1.5,3.0,t/ALERT)
	elif t >= CLAMP_AT:
		var held := t-CLAMP_AT
		energy = 3.2+2.6*exp(-held*5.0)+0.4*sin(held*7.0)
	_set_light(energy)
	# The red light slides over Hoppy as the drone closes in, so the field bathes him.
	var over := clampf((t-POUNCE)/(CLAMP_AT-POUNCE),0,1)
	_light.global_position = to_global(LIGHT_HOME).lerp(victim+Vector3(0,1.4,0.1),over)
	_pose_field(t,victim)
## Claws: snap open as it pounces, swing forward and shut on him at CLAMP_AT, then grip with a tremor.
func _pose_claw(i: int, side: float, t: float) -> void:
	var opened := smoothstep(ALERT,ALERT+0.25,t)
	var closing := smoothstep(CLAMP_AT-0.12,CLAMP_AT,t)
	var reach := smoothstep(POUNCE,CLAMP_AT,t)
	var arm := _arms[i]
	arm.rotation.x = -0.45*opened-0.85*reach+0.03*sin(t*31.0+i)*closing
	arm.rotation.z = side*(0.65*opened*(1.0-closing)+0.06*closing)
	_ears[i].rotation.x = -0.35*opened+0.2*closing
## The field grows out of the deck around him once the claws have shut, pulsing while it holds.
func _pose_field(t: float, victim: Vector3) -> void:
	var held := t-CLAMP_AT
	_field.visible = held >= 0.0
	if not _field.visible: return
	var spread := 0.3+0.7*_back_out(clampf(held/0.2,0,1))
	var rise := smoothstep(0,FIELD_RISE,held)
	_field.global_transform = Transform3D(Basis.from_scale(Vector3(FIELD_SIZE.x*spread,maxf(FIELD_SIZE.y*rise,0.001),FIELD_SIZE.z*spread)),victim)
	_field_material.set_shader_parameter("energy",1.0+1.8*exp(-held*6.0)+0.25*sin(held*7.0))
	_field_material.set_shader_parameter("clock",held)
## Ease-out with a small overshoot, for the field snapping out to full size.
static func _back_out(u: float) -> float:
	var c := 1.7
	return 1.0+(c+1.0)*pow(u-1.0,3)+c*pow(u-1.0,2)
func _apply() -> void:
	visible = not (_retreated and _threat <= 0.001)
	if _field != null: _field.visible = false
	_light.position = LIGHT_HOME
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
