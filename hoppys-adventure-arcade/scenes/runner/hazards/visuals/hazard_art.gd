extends Node3D
## Normalized collision geometry and metre-space annotations share one bounded rig.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const MeshForge = preload("res://scenes/runner/hazards/visuals/hifi/mesh_forge.gd")
const TextureForge = preload("res://scenes/runner/hazards/visuals/hifi/texture_forge.gd")
const Surface = preload("res://scenes/runner/hazards/visuals/hifi/surface.gdshader")
const Energy = preload("res://scenes/runner/hazards/visuals/hifi/energy.gdshader")
const Wing = preload("res://scenes/runner/hazards/visuals/hifi/wing.gdshader")
const PitInterior = preload("res://scenes/runner/hazards/visuals/hifi/pit_interior.gdshader")
const PitMouth = preload("res://scenes/runner/hazards/visuals/hifi/pit_mouth.gdshader")
const Trail = preload("res://scenes/runner/hazards/visuals/hifi/trail.gdshader")
const BatchRoot = preload("res://scenes/runner/hazards/visuals/hifi/batch_root.gd")
const LASER_HIGH_Y := 1.3
## Footprint decal heights: distinct from each other and from the corridor LaneGlow (y 0.012) so no
## two additive floor layers share a depth plane (z-fighting flicker).
const MARKER_Y := 0.02
const SAFE_GAP_Y := 0.03
## Immutable resources shared by every spawn (none animate per rig): footprint quads and
## materials, spark draw pass and process materials. Keeping one live reference also keeps each
## material variant's compiled shader alive after the GPU warm-up.
static var _shared: Dictionary = {}
var body: Node3D
var beams: Node3D
var scanner: Node3D
var tag: Label3D
var _kind: StringName
var _variant: StringName
var _size := Vector3.ONE
var _offset := Vector3.ZERO
var _t := 0.0
var _reaction := 0.0
var _hit := false
var _cleared := false
var _state: StringName = &"ground"
var _batches: Array[Dictionary] = []
var _moving: Array[Dictionary] = []
var _materials: Dictionary = {}
var _labels: Array[Label3D] = []
var _plates: Array[Node3D] = []
var _charge := 0.0
var _distance_gain := 0.0
var _pit_mouth: MeshInstance3D
## Last hit/distance values written, so steady uniforms are not re-sent every frame.
var _hit_written := -1.0
var _gain_written := -1.0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _pivot(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(node)
	node.position = pos
	return node

func _material(key: String) -> ShaderMaterial:
	if _materials.has(key): return _materials[key]
	var mat := ShaderMaterial.new()
	var maps := TextureForge.maps()
	mat.shader = Trail if key == "trail" else Wing if key == "glass" else Energy if key in ["halo", "glyph"] else PitInterior if key in ["pit_bottom", "pit_wall"] else Surface
	mat.set_shader_parameter("atlas", maps.albedo)
	mat.set_shader_parameter("accent", Palette.CREAM if key == "eyes" else Palette.DANGER if key == "glass" else Palette.LILAC if key.begins_with("lilac") else Palette.DANGER)
	if key == "glass": mat.set_shader_parameter("membrane_color",Palette.DANGER)
	if mat.shader == Surface: mat.set_shader_parameter("diff_color",Palette.CREAM)
	if mat.shader in [Surface, PitInterior]:
		mat.set_shader_parameter("normal_atlas", maps.normal)
		mat.set_shader_parameter("rough_atlas", maps.roughness)
		mat.set_shader_parameter("tint", Palette.SLATE if key in ["metal", "housing", "pit_wall", "wheel"] else Palette.NAVY_BG if key == "pit_bottom" else Palette.NAVY_2)
		if key in ["metal", "housing", "wheel"]: mat.set_shader_parameter("tint",Color("8b9ca9"))
		if key == "shell": mat.set_shader_parameter("tint",Color("bd5545"))
		if key == "carapace" and _kind == &"bug_swarm": mat.set_shader_parameter("tint",Color("b7a69a"))
		if key == "eyes": mat.set_shader_parameter("tint",Palette.CREAM)
		if key in ["edge", "wheel_edge", "threat"]: mat.set_shader_parameter("tint",Palette.DANGER*0.55)
		if key.begins_with("lilac"): mat.set_shader_parameter("tint",Palette.LILAC*0.45)
		mat.set_shader_parameter("tile", 1.0 if key in ["screen", "lilac_screen"] else 2.0 if key == "stripe" else 3.0 if key == "lilac" else 0.0)
		mat.set_shader_parameter("emission_gain", 0.28 if key.begins_with("lilac") else 0.65 if key in ["edge", "eyes", "wheel_edge", "threat"] else 0.40 if key == "screen" else 0.30 if key == "stripe" else 0.0)
		if key in ["wheel", "wheel_edge"]: mat.set_shader_parameter("roll_rate",2.0)
	elif mat.shader == Energy:
		mat.set_shader_parameter("strength", 0.28 if key == "glass" else 0.55)
		mat.set_shader_parameter("glyph", 1.0 if key == "glyph" else 0.0)

	if mat.shader in [Surface, Energy, Trail]: mat.set_shader_parameter("distance_gain",_distance_gain)
	_materials[key] = mat
	return mat

func _piece(parent: Node3D, pos: Vector3, size: Vector3, material: String, mesh: Mesh = null) -> Node3D:
	if mesh == null: mesh = MeshForge.bevel_box()
	var pivot := _pivot(parent, pos)
	var mat := _material(material)
	var group: Dictionary = {}
	for batch in _batches:
		if batch.material == mat and batch.mesh == mesh:
			group = batch
			break
	if group.is_empty():
		group = {"material": mat, "mesh": mesh, "instances": [], "poses": []}
		_batches.append(group)
	group.instances.append([pivot, size])
	return pivot

func _animate(node: Node3D, style: String, phase: float = 0.0) -> void:
	_moving.append({"node": node, "rest": node.position, "rotation": node.rotation, "style": style, "phase": phase})

func build(kind: StringName, variant: StringName, size: Vector3, offset: Vector3) -> void:
	name = "Artwork"
	_kind = kind
	_variant = variant
	_size = size
	_offset = offset
	update_view_distance()
	if kind != &"projectile":
		_floor_marker("FloorMarker", size, MARKER_Y, Palette.DANGER, 0.35)
		if kind == &"pr_backlog_high": _floor_marker("SafeGap", size * Vector3(1,1,0.6), SAFE_GAP_Y, Palette.MATRIX, 0.25)
	body = BatchRoot.new()
	body.process_mode = Node.PROCESS_MODE_PAUSABLE
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(body)
	body.position = offset
	body.batches = _batches
	body.name = "Body"
	body.scale = size
	match kind:
		&"pr_backlog_low", &"pr_backlog_high": _backlog()
		&"bug_swarm": _bugs()
		&"merge_conflict": _merge()
		&"deprecated_pit": _pit()
		&"laser_grid": _laser()
		&"comment_flood": _comments()
		&"build_shockwave": _shockwave()
		&"projectile": _projectile()
	_flush()
	update_view_distance()
	if kind in [&"pr_backlog_low", &"deprecated_pit", &"build_shockwave"]: _sparks()

func _floor_marker(title: String, size: Vector3, elevation: float, color: Color, opacity: float) -> void:
	var node := MeshInstance3D.new()
	node.name = title
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.mesh = _marker_quad(Vector2(size.x, size.z))
	node.position = Vector3(_offset.x, elevation, _offset.z)
	node.rotation.x = -PI/2.0
	node.material_override = _marker_material(color, opacity)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	# Preserve the smoke's footprint metadata, but never paint across the hole.
	if _kind == &"deprecated_pit" and title == "FloorMarker": node.hide()

static func _marker_quad(extent: Vector2) -> QuadMesh:
	var key := "quad:%s" % extent
	if not _shared.has(key):
		var quad := QuadMesh.new()
		quad.size = extent
		_shared[key] = quad
	return _shared[key]

## Footprint border material per colour (also the cleared MINT swap); shared, never mutated.
static func _marker_material(color: Color, opacity: float) -> StandardMaterial3D:
	var key := "marker:%s:%s" % [color.to_html(), opacity]
	if not _shared.has(key):
		var mat := Materials.additive(color, opacity).duplicate() as StandardMaterial3D
		# A bounded border locates the occupied lane without covering its floor.
		mat.albedo_texture = TextureForge.marker_border()
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.9
		_shared[key] = mat
	return _shared[key]

## Drops the shared resources (tests call this before quitting).
static func release_caches() -> void:
	_shared.clear()

func _label(text: String, pos: Vector3, width: float, height: float) -> Label3D:
	# Input layout is normalized; glyph transforms are authored in metres at unit scale.
	var label := Label3D.new()
	label.process_mode = Node.PROCESS_MODE_PAUSABLE
	label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	label.text = text
	label.font_size = 64
	label.outline_size = 3
	label.outline_modulate = Palette.NAVY_BG
	label.modulate = Palette.CREAM
	var width_m := width*_size.x
	var height_m := minf(maxf(height*_size.y,0.17),_size.y*0.65)
	label.pixel_size = minf(width_m/(float(text.length())*40.0+24),height_m/80.0)
	label.position = _offset+Vector3(pos.x*_size.x,clampf(pos.y*_size.y,-_size.y*0.30,_size.y*0.30),_size.z*0.515)
	label.no_depth_test = false
	add_child(label)
	var plate := _piece(self,label.position-Vector3(0,0,0.025),Vector3(width_m,height_m+0.015,0.025),"dark")
	plate.name = "TextBacking%d" % _labels.size()
	_labels.append(label)
	_plates.append(plate)
	return label

func _backlog() -> void:
	var high := _kind == &"pr_backlog_high"
	# Collision-normalized geometry: all solids remain in the occupied volume.
	if high:
		# Suspended merge scanner: a heavy overhead bridge with downward sensors.
		_piece(body,Vector3(0,0.26,0),Vector3(0.97,0.42,0.72),"metal")
		_piece(body,Vector3(0,0.23,0.38),Vector3(0.78,0.20,0.08),"screen")
		for side in [-1,1]:
			_piece(body,Vector3(side*0.42,-0.08,0),Vector3(0.14,0.78,0.80),"shell")
			_piece(body,Vector3(side*0.30,-0.06,0.22),Vector3(0.12,0.33,0.30),"metal")
			_piece(body,Vector3(side*0.30,-0.25,0.27),Vector3(0.11,0.06,0.34),"edge")
		# Lower scanning beam coincides with the actual underside of the hitbox.
		_piece(body,Vector3(0,-0.44,0.28),Vector3(0.82,0.075,0.10),"edge")
	else:
		# A jammed merge conduit: two branch pipes converge into a raised lock.
		_piece(body,Vector3(0,-0.35,0),Vector3(0.97,0.25,0.85),"metal")
		for side in [-1,1]:
			var branch := _piece(body,Vector3(side*0.28,-0.05,0.04),Vector3(0.43,0.35,0.55),"shell")
			branch.rotation.z = side*0.16
			for x in [0.14,0.27,0.40]:
				_piece(body,Vector3(side*x,-0.04,0.34),Vector3(0.028,0.31,0.04),"metal")
		_piece(body,Vector3(0,0.08,0),Vector3(0.25,0.79,0.74),"metal")
		_piece(body,Vector3(0,0.10,0.40),Vector3(0.18,0.48,0.10),"screen")
		# A physical split-arrow on the cap makes the jump crest legible.
		for side in [-1,1]:
			var arrow := _piece(body,Vector3(side*0.05,0.33,0.46),Vector3(0.13,0.07,0.035),"edge")
			arrow.rotation.z = -side*0.6
	# End caps and interrupted red status strips distinguish blocked equipment.
	for side in [-1,1]:
		_piece(body,Vector3(side*0.44,0.31 if high else -0.32,0.43),Vector3(0.10,0.10,0.06),"edge")
	tag = _label("ROLL" if high else "JUMP",Vector3(0,0.26 if high else -0.28,0.48),0.28,0.13)

func _bugs() -> void:
	# Three curved 32-ring beetles replace seven boxes without exceeding 6000 tris.
	for i in 3:
		var insect := _pivot(body,Vector3((i-1)*0.24,0.08 if i == 1 else -0.12,-0.10 if i == 1 else 0.10))
		_animate(insect,"bug",float(i))
		var shell := _piece(insect,Vector3.ZERO,Vector3(0.29,0.34,0.38),"shell",MeshForge.carapace())
		shell.name = "Carapace%d" % i
		_piece(insect,Vector3(0,0.135,0),Vector3(0.075,0.032,0.31),"edge")
		var head := _piece(insect,Vector3(0,0,0.20),Vector3(0.19,0.16,0.18),"shell",MeshForge.wedge())
		head.rotation.x = -0.18
		for side in [-1,1]:
			_piece(insect,Vector3(side*0.048,0.035,0.275),Vector3(0.060,0.065,0.025),"eyes")
			for leg in 3:
				var limb := _piece(insect,Vector3(side*0.16,-0.09,(leg-1)*0.105),Vector3(0.20,0.20,0.03),"carapace",MeshForge.jointed_leg())
				limb.rotation.y = PI if side < 0 else 0.0
				limb.name = "JointedLeg%d_%d" % [side,leg]
			var wing := _piece(insect,Vector3(side*0.10,0.17,-0.075),Vector3(0.20,0.35,0.10),"glass",MeshForge.wing())
			wing.name = "Wing%d_%d" % [i,side]
			wing.rotation.x = -0.8
			_animate(wing,"wing",float(i)+side)
	tag = _label("BUGS",Vector3(0,-0.32,0.48),0.68,0.20)

func _merge() -> void:
	# Staggered fragments form a jagged physical fracture, with recessed branch light.
	for side in [-1,1]:
		for row in 5:
			var width := 0.41 - (0.025 if row%2 else 0.0)
			_piece(body,Vector3(side*(0.055+width*0.5),(row-2)*0.17,0),Vector3(width,0.165,0.66),"lilac_plate" if side > 0 else "metal")
			var seam := _piece(body,Vector3(side*(0.033+0.01*(row%2)),(row-2)*0.17,0.34),Vector3(0.024,0.175,0.026),"lilac" if side>0 else "edge")
			seam.rotation.z = side*(0.15 if row%2 else -0.15)
		var glyph := _piece(body,Vector3(side*0.25,0.05,0.39),Vector3(0.36,0.42,0.014),"lilac_screen" if side>0 else "screen")
		_animate(glyph,"card",float(side))
	_label("<<<<<<<",Vector3(-0.25,-0.18,0.40),0.35,0.12)
	_label(">>>>>>>",Vector3(0.25,-0.18,0.40),0.35,0.12)
	tag = _label("CONFLICT",Vector3(0,0.42,0.39),0.64,0.10)

func _pit() -> void:
	# Physical well below the floor, with a normally depth-tested parallax mouth.
	# Opaque corridor floor is not edited or bypassed.
	var bottom := _piece(body,Vector3(0,-0.45,0),Vector3(0.90,0.04,0.88),"pit_bottom")
	bottom.name = "PitBottom"
	for side in [-1,1]:
		_piece(body,Vector3(side*0.46,-0.20,0),Vector3(0.065,0.44,0.98),"pit_wall")
		_piece(body,Vector3(0,-0.20,side*0.455),Vector3(0.89,0.44,0.065),"pit_wall")
		_piece(body,Vector3(side*0.46,0.010,0),Vector3(0.050,0.04,0.98),"carapace")
		_piece(body,Vector3(0,0.010,side*0.455),Vector3(0.90,0.04,0.055),"stripe")
		for cable in 3:
			var wire := _piece(body,Vector3(side*0.41,-0.20,cable*0.22-0.22),Vector3(0.012,0.36,0.025),"pit_wall")
			wire.rotation.z = side*0.06
		for bolt in 6:
			_piece(body,Vector3(side*0.46,0.035,(bolt-2.5)*0.14),Vector3(0.014,0.020,0.018),"metal")
		_piece(body,Vector3(side*0.45,0.030,0.38),Vector3(0.035,0.035,0.09),"edge")
	# The red mouth rim marks the exact opening without painting over its depth.
	for side in [-1.0,1.0]:
		_piece(self,Vector3(side*_size.x*0.46,0.011,0),Vector3(0.045,0.018,_size.z*0.94),"edge")
		_piece(self,Vector3(0,0.011,side*_size.z*0.46),Vector3(_size.x*0.94,0.018,0.055),"edge")
	tag = _label("@deprecated",Vector3.ZERO,0.46,0.30)
	tag.position = Vector3(0,0.028,1.38)
	tag.pixel_size = minf(_size.x*0.42/440.0,0.006)
	tag.rotation.x = -PI/2
	var plate: Node3D = _plates.back()
	plate.position = tag.position-Vector3(0,0.015,0)
	# The backing is an XZ slab, so its local Y remains the upward surface normal.
	plate.rotation = Vector3.ZERO
	plate.scale = Vector3.ONE
	for batch in _batches:
		for item: Array in batch.instances:
			if item[0] == plate: item[1] = Vector3(_size.x*0.46,0.012,0.48)
	_pit_mouth = MeshInstance3D.new()
	_pit_mouth.name = "PitMouth"
	_pit_mouth.process_mode = Node.PROCESS_MODE_PAUSABLE
	_pit_mouth.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mouth := PlaneMesh.new()
	mouth.size = Vector2(_size.x*0.88,_size.z*0.84)
	_pit_mouth.mesh = mouth
	_pit_mouth.position = Vector3(_offset.x,0.001,_offset.z)
	_pit_mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mouth_material := ShaderMaterial.new()
	mouth_material.shader = PitMouth
	mouth_material.set_shader_parameter("opening_size",mouth.size)
	mouth_material.set_shader_parameter("well_depth",1.6)
	mouth_material.set_shader_parameter("bottom_color",Palette.NAVY_BG)
	mouth_material.set_shader_parameter("wall_shadow",Palette.NAVY_2)
	mouth_material.set_shader_parameter("wall_color",Palette.SLATE)
	mouth_material.set_shader_parameter("accent",Palette.DANGER)
	mouth_material.set_shader_parameter("cable_color",Palette.MATRIX)
	_pit_mouth.material_override = mouth_material
	add_child(_pit_mouth)

func _laser() -> void:
	for side in [-1,1]:
		_piece(body,Vector3(side*0.46,0,0),Vector3(0.075,0.90,0.66),"housing")
		_piece(body,Vector3(side*0.46,0.34,0.36),Vector3(0.025,0.09,0.04),"eyes")
		_piece(body,Vector3(side*0.46,0,0.36),Vector3(0.045,0.40,0.04),"halo",MeshForge.carapace())
		for vent in 4: _piece(body,Vector3(side*0.46,(vent-1.5)*0.18,0.34),Vector3(0.048,0.045,0.025),"metal")
		for row in 3:
			_piece(body,Vector3(side*0.415,(row-1)*0.28,0),Vector3(0.033,0.19,0.26),"edge")
	beams = _pivot(body)
	beams.name = "Beams"
	for row in 3:
		_piece(beams,Vector3(0,(row-1)*0.28,0),Vector3(0.035,0.81,0.045),"edge",MeshForge.cylinder()).rotation.z = PI/2
		_piece(beams,Vector3(0,(row-1)*0.28,0),Vector3(0.15,0.82,0.19),"halo",MeshForge.cylinder()).rotation.z = PI/2
	scanner = _pivot(body)
	scanner.name = "Scanner"
	_piece(scanner,Vector3(0,0,0.39),Vector3(0.81,0.22,0.075),"edge")
	_piece(scanner,Vector3(0,0,0.40),Vector3(0.83,0.32,0.08),"halo")
	scanner.hide()
	_state = &"high" if _variant == &"high" else &"ground"
	tag = _label(_laser_hint(),Vector3(0,0,0.50),0.38,0.48)

func _laser_hint() -> String:
	if _variant == &"timed" and _state == &"off": return "OFF"
	if _variant == &"high" or (_variant == &"timed" and _state == &"high"): return "ROLL"
	if _variant == &"mid": return "DUCK / JUMP"
	return "JUMP"

func _comments() -> void:
	# Opaque panel layers resolve depth; their glyph faces follow the helix.
	for layer in 3:
		for i in 7:
			var angle := float(i)*2.1 + layer*0.7
			var card := _pivot(body,Vector3(sin(angle)*0.30,(i-3)*0.13,(layer-1)*0.28))
			_animate(card,"tornado",float(i+layer*7))
			_piece(card,Vector3.ZERO,Vector3(0.26,0.095,0.06),"metal")
			_piece(card,Vector3(0,0,0.036),Vector3(0.23,0.072,0.009),"screen")
			_piece(card,Vector3(-0.09,-0.049,0),Vector3(0.035,0.02,0.05),"metal")
	tag = _label("BLOCKED",Vector3(0,0.43,0.43),0.72,0.06)

func _shockwave() -> void:
	# One 64-segment crest spans all lanes, clipped to a low circular arc.
	_piece(self,_offset,Vector3(5.41,0.39,0.11),"metal",MeshForge.wave_arc()).name = "WaveCrest"
	_piece(self,_offset+Vector3(0,0,0.075),Vector3(5.41,0.39,0.07),"threat",MeshForge.wave_arc()).name = "WaveLeadingEdge"
	_piece(self,_offset+Vector3(0,-0.08,-0.42),Vector3(5.20,0.30,0.07),"threat",MeshForge.wave_arc()).name = "WaveTrailingEdge"
	for i in 20:
		var shard := _piece(body,Vector3((i-9.5)*0.046,0.08,sin(float(i))*0.27),Vector3(0.045,0.40,0.16),"metal",MeshForge.shard())
		_piece(shard,Vector3.ZERO,Vector3(0.045,0.40,0.16),"edge",MeshForge.shard_glint())
		shard.name = "Shard%d" % i
		shard.rotation.z = sin(float(i))*0.20
		_animate(shard,"debris",float(i))
	tag = _label("JUMP",Vector3(0,-0.20,0.51),0.35,0.35)

func _projectile() -> void:
	match _variant:
		&"orb":
			_piece(body,Vector3(0,0,0.16),Vector3(0.44,0.64,0.48),"threat",MeshForge.plasma_sphere()).name = "OrbCore"
			_piece(body,Vector3(0,0,0.16),Vector3(0.49,0.70,0.54),"halo",MeshForge.sphere())
			var collar := _piece(body,Vector3(0,0,0.16),Vector3(0.55,0.48,0.66),"edge",MeshForge.ring())
			collar.rotation.x = PI/2
		&"low":
			_piece(body,Vector3(0,-0.20,0.12),Vector3(0.92,0.42,0.65),"threat",MeshForge.wedge()).name = "LowWedge"
			for side in [-1,1]: _piece(body,Vector3(side*0.34,-0.40,0.05),Vector3(0.18,0.10,0.80),"edge")
		&"high":
			_piece(body,Vector3(0,0,0.14),Vector3(0.95,0.22,0.33),"threat").name = "HighBar"
			_piece(body,Vector3(0,0,0.32),Vector3(0.89,0.12,0.04),"edge")
			for side in [-1,1]: _piece(body,Vector3(side*0.33,0.04,0.06),Vector3(0.12,0.83,0.50),"metal",MeshForge.wedge())
		&"wide":
			_piece(body,Vector3(0,0,0.06),Vector3(0.95,0.95,0.92),"threat",MeshForge.crescent()).name = "WideCrescent"
			_piece(body,Vector3(0,0,0.07),Vector3(0.95,0.18,0.92),"edge",MeshForge.crescent())
	# Trails extend aft toward -Z, outside the core's screen-space silhouette.
	for side in [-1,1]:
		var trail := _piece(body,Vector3(side*(0.34 if _variant == &"orb" else 0.49),0,-0.16),Vector3(0.075,0.12,0.78),"trail",MeshForge.trail())
		trail.name = "AftTrail%d" % side
		_animate(trail,"trail",float(side))

func _flush() -> void:
	for batch in _batches:
		var node := MultiMeshInstance3D.new()
		node.name = "Batch%02d" % body.get_child_count()
		node.process_mode = Node.PROCESS_MODE_PAUSABLE
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.mesh = batch.mesh
		node.multimesh.instance_count = batch.instances.size()
		node.material_override = batch.material
		body.add_child(node)
		batch.node = node
	_update_batches()

func _update_batches() -> void:
	for batch in _batches:
		var bounds := AABB()
		var first := true
		batch.poses.clear()
		for i in batch.instances.size():
			var item: Array = batch.instances[i]
			var pivot: Node3D = item[0]
			var pose := body.global_transform.affine_inverse()*pivot.global_transform
			pose.basis = pose.basis.scaled_local(item[1])
			if not pivot.is_visible_in_tree(): pose.basis = pose.basis.scaled_local(Vector3.ZERO)
			batch.poses.append(pose)
			batch.node.multimesh.set_instance_transform(i,pose)
			var box: AABB = pose * batch.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		batch.node.multimesh.custom_aabb = bounds

func react(cleared: bool) -> void:
	_hit = not cleared
	_cleared = cleared
	_reaction = 0.0
	if cleared:
		var marker := get_node_or_null("FloorMarker") as MeshInstance3D
		if marker != null:
			# Shared cleared variant (albedo MINT at 0.35, MINT emission), not a per-hit duplicate.
			marker.material_override = _marker_material(Palette.MINT,0.35)
		if tag != null:
			tag.text = "AUTO-FIXED"
			tag.modulate = Palette.MINT
	if scanner != null: scanner.hide()

func telegraph(t: float) -> void:
	if scanner == null or _variant != &"timed": return
	var amount := clampf(t,0,1)
	scanner.visible = amount > 0 and not _cleared
	_charge = amount
	scanner.position.y = lerpf(-0.25,0.25,amount)
	scanner.scale.x = lerpf(0.15,1.0,amount)
	_material("housing").set_shader_parameter("charge",amount)
	_material("halo").set_shader_parameter("charge",amount)
	if tag != null: tag.text = "CHARGING" if amount > 0 else _laser_hint()
	_update_batches()

func laser_state(state: StringName) -> void:
	if beams == null or _variant != &"timed" or state not in [&"ground",&"high",&"off"]: return
	_state = state
	beams.visible = state != &"off" and not _cleared
	if state != &"off":
		var elevation := LASER_HIGH_Y if state == &"high" else _offset.y
		var shift := elevation-body.position.y
		body.position.y = elevation
		for label in _labels: label.position.y += shift
		for plate in _plates: plate.position.y += shift
	telegraph(0)
	_update_batches()

func advance(delta: float) -> void:
	update_view_distance()
	_t += delta
	if _pit_mouth != null: _pit_mouth.material_override.set_shader_parameter("clock",_t)
	_reaction += delta
	var hit := maxf(0,1-_reaction*8) if _hit else 0.0
	var write_hit := hit != _hit_written
	_hit_written = hit
	for key: String in _materials:
		var mat: ShaderMaterial = _materials[key]
		mat.set_shader_parameter("clock",_t)
		if write_hit and mat.shader in [Surface, PitInterior]: mat.set_shader_parameter("hit",hit)
	for item in _moving:
		var node: Node3D = item.node
		var phase: float = item.phase
		node.position = item.rest
		node.rotation = item.rotation
		match item.style:
			"card": node.position.x += sin(_t*2.5+phase)*0.005
			"bug": node.position.y += sin(_t*5+phase)*0.025
			"wing": node.rotation.z += sin(_t*38+phase)*0.24
			"tornado":
				var angle := _t*1.5+phase*2.399
				node.position.x = sin(angle)*(0.18+(item.rest.y+0.4)*0.2)
				node.position.z = cos(angle)*0.30
				node.position.y += sin(_t*2+phase)*0.008
			"debris": node.position.y += sin(_t*8+phase)*0.05
			"trail": node.scale.z = 0.75+0.20*sin(_t*18+phase)
	# Collapse rather than expand: impact and clear never breach collision bounds.
	if _cleared:
		body.scale = _size * maxf(0.001,1.0-_reaction*3)
	elif _hit:
		body.scale = _size * (1.0-0.04*sin(minf(_reaction*10,PI)))
	_update_batches()

func _sparks() -> void:
	var sparks := GPUParticles3D.new()
	var key := "sparks:%s" % _size
	sparks.name = "BoundedSparks"
	sparks.process_mode = Node.PROCESS_MODE_PAUSABLE
	sparks.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sparks.position = _offset
	sparks.amount = 12
	sparks.lifetime = 0.6
	sparks.preprocess = 0.6
	sparks.visibility_aabb = AABB(-_size*0.45,_size*0.9)
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _shared.has(key):
		var motion := ParticleProcessMaterial.new()
		motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		motion.emission_box_extents = _size*0.27
		motion.gravity = Vector3.ZERO
		motion.direction = Vector3.UP
		motion.initial_velocity_min = 0.01
		motion.initial_velocity_max = 0.04
		motion.color = Palette.DANGER
		motion.anim_offset_min = 0.25
		motion.anim_offset_max = 0.25
		_shared[key] = motion
	# Each emitter keeps its own copy of the per-size prototype (one process material shared by
	# several emitters leaked its shader at exit); the draw pass is shared outright.
	sparks.process_material = (_shared[key] as ParticleProcessMaterial).duplicate()
	if not _shared.has("sparks_draw"):
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE*0.025
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.particles_anim_h_frames = 4
		mat.albedo_texture = TextureForge.maps().albedo
		mat.albedo_color = Color(Palette.DANGER,0.40)
		quad.material = mat
		_shared["sparks_draw"] = quad
	sparks.draw_pass_1 = _shared["sparks_draw"]
	add_child(sparks)

func update_view_distance() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var distance := absf(global_position.z) if is_inside_tree() else 0.0
	if camera != null: distance = camera.global_position.distance_to(global_position)
	_distance_gain = clampf((distance-18.0)/42.0,0.0,1.0)*4.5
	# New materials take _distance_gain when built; existing ones only need a changed value.
	if _distance_gain == _gain_written: return
	_gain_written = _distance_gain
	for material: ShaderMaterial in _materials.values():
		if material.shader in [Surface,Energy,Trail]: material.set_shader_parameter("distance_gain",_distance_gain)
