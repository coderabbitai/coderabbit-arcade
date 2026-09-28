extends Node3D
const Forge = preload("res://scenes/runner/powerups/visuals/hifi/mesh_forge.gd")
const Finish = preload("res://scenes/runner/powerups/visuals/hifi/pickup_materials.gd")
const Grab = preload("res://scenes/runner/powerups/visuals/hifi/grab_affordance.gd")
const Burst = preload("res://scenes/runner/powerups/visuals/hifi/collect_burst.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const BACKED_KINDS := [&"approve_shield",&"auto_fix",&"lgtm",&"nitro",&"super_jump",&"code_review",&"review_comment",&"lint_rule",&"unit_test",&"auto_fix_patch"]
const BODY_MINT := Color(115.5/255.0,230.25/255.0,191.5/255.0) # MINT.lerp(MATRIX,0.25)
static var FRAME_MINT := Palette.SLATE.lerp(Palette.MINT,0.45).lightened(0.18)
static var FRAME_REVIEW := FRAME_MINT.lightened(0.10).lerp(Palette.MINT,0.12)
static var FRAME_ORANGE := Palette.ORANGE.lerp(Palette.CREAM,0.15)
const TAGS := {&"approve_shield":"APPROVE", &"auto_fix":"AUTO FIX", &"lgtm":"LGTM", &"nitro":"NITRO", &"super_jump":"JUMP", &"code_review":"REVIEW", &"review_comment":"COMMENT", &"lint_rule":"LINT", &"unit_test":"TEST", &"auto_fix_patch":"PATCH"}
var _kind: StringName
var _core_node: MeshInstance3D
var _teeth: MultiMeshInstance3D
var _is_tool := false
var pivot: Node3D:
	get: return _pivot
var _pivot: Node3D
var _tag: Label3D
var _tag_plate: MeshInstance3D
var _pool: MeshInstance3D
var _glyph: MeshInstance3D
var _near_fade := 1.0
var _glyph_coverage := 1.0
var _beam_width := 0.35
var _depth_alpha := 1.0
var _rear_mix := 0.0
var _beam_offset := 0.0
var _last_affordance_clock := 0.0
const PICKUP_GROUP := &"a4_pickup_art"
## Ring and halo projection height: clear of the corridor LaneGlow decal (y 0.012) so the two
## additive floor layers never share a depth plane and z-fight.
const POOL_Y := 0.04
## Per-kind immutable build output (meshes, tag size, glyph coverage), shared by every spawn so a
## pickup entering the corridor never re-runs MeshForge, font measuring or a texture readback.
static var _kind_cache: Dictionary = {}
static var _plate_mesh: ArrayMesh
static var _plate_material: ShaderMaterial
static var _glyph_quad: QuadMesh
## One snapshot of every live pickup per process frame, instead of a group scan per pickup.
static var _peer_frame := -1
static var _peers: Array[Dictionary] = []
var _materials: Array[ShaderMaterial] = []
## Surface materials that take range_boost, collected once instead of per frame.
var _surface_materials: Array[ShaderMaterial] = []
var _phase := 0.0
var _range_boost := -1.0
var _t := 0.0
var _collect_time := -1.0
var _accent := Palette.MINT

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func build(kind: StringName) -> void:
	if _pivot != null: return
	add_to_group(PICKUP_GROUP)
	_kind = kind if TAGS.has(kind) else &"approve_shield"
	var is_tool := kind in [&"review_comment",&"lint_rule",&"unit_test",&"auto_fix_patch"]
	_is_tool = is_tool
	_accent = Palette.ORANGE if is_tool else Palette.MINT
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var shapes := kind_shapes(_kind)
	_phase = float(TAGS.keys().find(_kind))*0.37
	var frame_mesh: ArrayMesh = shapes.frame
	var frame_tint := Palette.CREAM
	# Lift only the magnifier diffuse plating; mint mix retains saturation.
	if _kind == &"code_review": frame_tint = Palette.CREAM
	var frame_material := Finish.material(frame_tint,0.12)
	frame_material.set_shader_parameter("inlay_tint",Palette.ORANGE if is_tool else BODY_MINT)
	_add_mesh("Ring",frame_mesh,frame_material,_pivot)
	if kind == &"auto_fix": frame_material.set_shader_parameter("emission_inset",0.26)
	if shapes.core != null:
		_core_node = _add_mesh("InnerCore",shapes.core,Finish.material(_accent,4.8),_pivot)
		_core_node.material_override.set_shader_parameter("emission_fill",0.65)
	# Filter prongs are part of the solid cartridge core.
	if not is_tool:
		# Opaque frame contributes the same broad patch as ORANGE tool frames.
		# Diffuse frame and all sculpture emission remain in the MINT family.
		for material in _materials: material.set_shader_parameter("emission_tint",BODY_MINT)
	# Unlit (energy 0) NAVY backing: its clock never reaches the image, so one material serves all.
	_tag_plate = _add_mesh("TagPlate",_plate_mesh,_plate_material,self,false)
	_tag_plate.position = Vector3(0,-0.50,0.01)
	_tag = Label3D.new()
	_tag.name = "Tag"
	_tag.text = TAGS.get(kind,"PICKUP")
	_tag.pixel_size = 0.0045
	_tag.outline_size = 6
	# Fitted once per kind in kind_shapes(); the larger world pixel size is kept.
	_tag.font_size = shapes.tag_size
	_tag.outline_modulate = Palette.NAVY_BG
	_tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_tag.modulate = Palette.CREAM
	_tag.position = Vector3(0,-0.50,0.045)
	_tag.no_depth_test = false
	add_child(_tag)
	var friendly := Palette.ORANGE if is_tool else Palette.MINT
	_pool = _add_mesh("BeaconRingHalo",Grab.mesh(),Grab.material(friendly),self)
	# Shader-expanded sheath must also have an honest culling bound.
	_pool.custom_aabb = AABB(Vector3(-1.9,0,-1.2),Vector3(3.8,3.2,2.4))
	_pool.material_override.set_shader_parameter("beam_core_gain",1.12 if is_tool else 1.0)
	_pool.set_meta("ring_diameter",1.392)
	_pool.set_meta("halo_diameter",2.4)
	_pool.position.y = -1.0 + POOL_Y
	_glyph = _add_mesh("HologramGlyph",_glyph_quad,Grab.material(friendly,_kind),self)
	_glyph.position.y = 1.15
	# Measured from the CPU raster; get_image() on the uploaded texture was a GPU readback stall.
	_glyph_coverage = shapes.coverage
	for material in _materials:
		if material.shader == Finish.template("opaque").shader or material.shader == Finish.template("glass").shader:
			_surface_materials.append(material)
	_set_modes(self)

## Builds (once per kind) every immutable piece of a pickup: merged frame, core, tag fit and glyph
## coverage. Also a warm-up hook: calling it before play moves all of that CPU work off the run.
static func kind_shapes(kind: StringName) -> Dictionary:
	if not TAGS.has(kind): kind = &"approve_shield"
	if _kind_cache.has(kind): return _kind_cache[kind]
	if _plate_mesh == null:
		var plate := Forge.new()
		plate.bar(Vector3.ZERO,Vector2(0.72,0.16),0.0,0.025)
		_plate_mesh = plate.finish()
		_plate_material = Finish.material(Palette.NAVY_2)
		_glyph_quad = QuadMesh.new()
		_glyph_quad.size = Vector2.ONE
	var builder = new()
	var metal := Forge.new()
	var glass := Forge.new()
	var core := Forge.new()
	builder._build_icon(kind,metal,glass,core)
	builder.free()
	if kind in BACKED_KINDS:
		# Closed, thick core behind the thin icon, merged into its frame draw.
		# The depth keeps a solid silhouette during the existing sculpture spin.
		var disc := PackedVector2Array()
		for i in 24: disc.append(Vector2(cos(TAU*i/24.0),sin(TAU*i/24.0))*0.15)
		metal.panel(disc,0.26,0.025,Vector3(0,0,-0.09))
	# Merge the inlay into the frame surface; vertex alpha selects glass shading.
	var inlay_mesh := glass.finish()
	var arrays := inlay_mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in colors.size(): colors[i].a = 0.5
	arrays[Mesh.ARRAY_COLOR] = colors
	var marked := ArrayMesh.new()
	marked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	# Index the existing frame before appending an indexed mesh.
	metal.surface.index()
	metal.surface.append_from(marked,0,Transform3D.IDENTITY)
	metal.vertex_count += glass.vertex_count
	metal.panel_bounds.append_array(glass.panel_bounds)
	var frame_mesh := metal.finish()
	frame_mesh.set_meta("expected_triangles",metal.vertex_count/3)
	frame_mesh.set_meta("inlay_bounds",glass.panel_bounds.duplicate())
	# Fit the longest tag inside the plate at the fixed 0.0045 world pixel size.
	var text: String = TAGS[kind]
	var tag_size := 32
	var tag_font: Font = ThemeDB.fallback_font
	while (tag_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,tag_size).x+6*2)*0.0045 > 0.70:
		tag_size -= 1
	var shapes := {"frame": frame_mesh, "core": core.finish() if core.vertex_count > 0 else null, "tag_size": tag_size, "coverage": Grab.coverage(kind)}
	_kind_cache[kind] = shapes
	return shapes

## Warm-up hook: every per-kind CPU cache (meshes, glyph raster, tag fit) for `kind`.
static func warm_kind(kind: StringName) -> void:
	kind_shapes(kind)

## Drops the static caches (tests call this before quitting, like Finish.cache.clear()).
static func release_caches() -> void:
	_kind_cache.clear()
	_plate_mesh = null
	_plate_material = null
	_glyph_quad = null
	_peers.clear()
	_peer_frame = -1

func _set_modes(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in node.get_children(): _set_modes(child)

func _add_mesh(title: String, shape: Mesh, material: ShaderMaterial, parent: Node3D, animated := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = title
	mesh.mesh = shape
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	if animated: _materials.append(material)
	return mesh

func _polygon(forge: RefCounted, points: Array, depth := 0.07, z := 0.0) -> void:
	var packed := PackedVector2Array()
	for point: Vector2 in points: packed.append(point)
	forge.panel(packed,depth,0.012,Vector3(0,0.015,z))

func _check(core: RefCounted, offset := Vector3.ZERO, factor := 1.0) -> void:
	core.bar(Vector3(-0.055,-0.015,0.063)+offset,Vector2(0.10,0.026)*factor,-0.7,0.025)
	core.bar(Vector3(0.035,0.024,0.063)+offset,Vector2(0.19,0.026)*factor,0.8,0.025)

func _framed_polygon(metal: RefCounted, glass: RefCounted, points: Array, size := Vector2(1.45,1.45), depth := 0.12) -> void:
	var outline := PackedVector2Array()
	for point: Vector2 in points: outline.append(point*size)
	if Geometry2D.is_polygon_clockwise(outline): outline.reverse()
	metal.panel(outline,depth,0.012)
	var inner: PackedVector2Array = metal.inset(outline,0.018)
	glass.panel(inner,0.045,0.006,Vector3(0,0,depth/2+0.004))

func _build_teeth() -> void:
	var forge := Forge.new()
	# Native dimensions keep the actual chamfer width; instances only translate.
	forge.bar(Vector3.ZERO,Vector2(0.048,0.38),0,0.075)
	var teeth := MultiMeshInstance3D.new()
	_teeth = teeth
	teeth.name = "CombTeeth"
	teeth.multimesh = MultiMesh.new()
	teeth.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	teeth.multimesh.mesh = forge.finish()
	teeth.multimesh.instance_count = 5
	for i in 5:
		teeth.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3((i-2)*0.115,0.04,0)))
	var material := Finish.material(Palette.MATRIX,3.2)
	teeth.material_override = material
	_materials.append(material)
	teeth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(teeth)

func _equipment_box(forge: RefCounted, center: Vector3, size: Vector3, angle := 0.0) -> void:
	forge.bar(center,Vector2(size.x,size.y),angle,size.z)

func _equipment_hex(forge: RefCounted, center: Vector3, radius: float, depth: float) -> void:
	var points := PackedVector2Array()
	for i in 8: points.append(Vector2(cos(TAU*i/8.0+PI/8),sin(TAU*i/8.0+PI/8))*radius)
	forge.panel(points,depth,0.015,center)

func _build_icon(kind: StringName, metal: RefCounted, glass: RefCounted, core: RefCounted) -> void:
	# Tangible equipment, with depth and attached working parts, not floating UI icons.
	match kind:
		&"approve_shield":
			_framed_polygon(metal,glass,[Vector2(0,-0.29),Vector2(0.27,-0.08),Vector2(0.25,0.20),Vector2(-0.25,0.20),Vector2(-0.27,-0.08)],Vector2.ONE,0.24)
			for side in [-1,1]:
				_equipment_box(metal,Vector3(side*0.16,0.26,-0.03),Vector3(0.10,0.28,0.18),-side*0.18)
			_check(core,Vector3(0,0,0.09),1.7)
		&"auto_fix":
			_equipment_box(metal,Vector3(-0.04,0.10,0),Vector3(0.44,0.21,0.26),0.12)
			_equipment_box(metal,Vector3(-0.13,-0.12,0),Vector3(0.14,0.32,0.22),-0.22)
			_equipment_box(metal,Vector3(0.23,0.13,0),Vector3(0.16,0.12,0.18))
			_equipment_box(glass,Vector3(-0.10,0.10,0.145),Vector3(0.18,0.11,0.035))
			for side in [-1,1]: _equipment_box(core,Vector3(0.27,0.13+side*0.075,0.02),Vector3(0.13,0.035,0.13))
		&"lgtm":
			_equipment_hex(metal,Vector3(0,-0.19,0),0.29,0.25)
			_equipment_box(metal,Vector3(0,0.05,0),Vector3(0.16,0.32,0.20))
			for side in [-1,1]: _equipment_box(metal,Vector3(side*0.11,0.24,0),Vector3(0.11,0.24,0.20),-side*0.18)
			_equipment_hex(glass,Vector3(0,-0.19,0.14),0.22,0.04)
			_check(core,Vector3(0,-0.17,0.105),1.55)
		&"nitro":
			_equipment_box(metal,Vector3(0,0,0),Vector3(0.45,0.19,0.22))
			for side in [-1,1]:
				_equipment_hex(metal,Vector3(side*0.16,0.11,0),0.15,0.24)
				_equipment_box(metal,Vector3(side*0.16,-0.07,0),Vector3(0.21,0.40,0.25))
				_equipment_box(glass,Vector3(side*0.16,0.02,0.14),Vector3(0.10,0.28,0.035))
				_equipment_box(core,Vector3(side*0.16,-0.32,0),Vector3(0.10,0.19,0.12))
		&"super_jump":
			for side in [-1,1]:
				_equipment_box(metal,Vector3(side*0.17,-0.23,0.035),Vector3(0.24,0.15,0.34))
				_equipment_box(metal,Vector3(side*0.17,0.03,-0.03),Vector3(0.15,0.44,0.20))
				_equipment_box(glass,Vector3(side*0.17,0.10,0.08),Vector3(0.10,0.25,0.035))
				for y in [-0.12,-0.05,0.02]: _equipment_box(core,Vector3(side*0.17,y,0.11),Vector3(0.20,0.025,0.05))
			_equipment_box(metal,Vector3(0,0.18,-0.04),Vector3(0.25,0.075,0.15))
		&"code_review":
			_equipment_box(metal,Vector3(0,0.05,-0.05),Vector3(0.56,0.30,0.25))
			_equipment_box(metal,Vector3(0,-0.19,-0.05),Vector3(0.16,0.23,0.20))
			for side in [-1,1]:
				_equipment_hex(metal,Vector3(side*0.16,0.06,0.08),0.16,0.20)
				_equipment_hex(glass,Vector3(side*0.16,0.06,0.19),0.115,0.03)
				_equipment_box(core,Vector3(side*0.16,0.06,0.21),Vector3(0.12,0.025,0.025))
		&"review_comment":
			_equipment_box(metal,Vector3(0,-0.04,0),Vector3(0.38,0.45,0.27))
			_equipment_box(metal,Vector3(-0.13,0.28,0),Vector3(0.075,0.26,0.12),-0.12)
			_equipment_box(glass,Vector3(0,0.04,0.15),Vector3(0.29,0.19,0.035))
			for x in [-0.085,0,0.085]: _equipment_box(core,Vector3(x,0.03,0.175),Vector3(0.028,0.08 if x != 0 else 0.14,0.025))
			for y in [-0.13,-0.20]: _equipment_box(metal,Vector3(0,y,0.16),Vector3(0.27,0.025,0.025))
		&"lint_rule":
			_equipment_box(metal,Vector3(0,-0.10,0),Vector3(0.56,0.25,0.25))
			_equipment_box(glass,Vector3(0,-0.10,0.14),Vector3(0.46,0.13,0.035))
			for x in [-0.23,0.23]: _equipment_box(metal,Vector3(x,0.11,0),Vector3(0.075,0.43,0.20))
			for x in [-0.12,0,0.12]: _equipment_box(core,Vector3(x,0.12,0.01),Vector3(0.055,0.35,0.11))
		&"unit_test":
			_equipment_hex(metal,Vector3(0,0,0),0.32,0.32)
			_equipment_hex(glass,Vector3(0,0,0.18),0.235,0.055)
			for x in [-0.29,0.29]:
				for y in [-0.17,0.17]: _equipment_box(metal,Vector3(x,y,0),Vector3(0.07,0.10,0.18))
			_check(core,Vector3(0,0,0.15),1.55)
		&"auto_fix_patch":
			_equipment_box(metal,Vector3(0,0,0),Vector3(0.43,0.55,0.24),0.16)
			_equipment_box(glass,Vector3(0,0,0.14),Vector3(0.30,0.39,0.04),0.16)
			for side in [-1,1]:
				_equipment_box(metal,Vector3(side*0.25,0,0),Vector3(0.09,0.23,0.20))
			_equipment_box(core,Vector3(0,0,0.17),Vector3(0.25,0.075,0.04))
			_equipment_box(core,Vector3(0,0,0.17),Vector3(0.075,0.27,0.04))

	# Dark rubber grips and service seams give the shells working surfaces.
	metal.color = Color(0.22,0.29,0.34)
	match kind:
		&"auto_fix":
			for y in [-0.08,-0.15,-0.22]: _equipment_box(metal,Vector3(-0.13,y,0.12),Vector3(0.11,0.022,0.025),-0.22)
		&"nitro":
			for side in [-1,1]: _equipment_box(metal,Vector3(side*0.16,-0.14,0.14),Vector3(0.20,0.05,0.025))
		&"super_jump":
			for side in [-1,1]: _equipment_box(metal,Vector3(side*0.17,-0.30,0.035),Vector3(0.24,0.035,0.34))
		&"review_comment":
			for y in [-0.13,-0.20]: _equipment_box(metal,Vector3(0,y,0.179),Vector3(0.25,0.015,0.015))
		&"auto_fix_patch":
			for y in [-0.20,0.20]: _equipment_box(metal,Vector3(0,y,0.18),Vector3(0.17,0.025,0.025))
		&"code_review":
			for y in [-0.15,-0.21]: _equipment_box(metal,Vector3(0,y,0.064),Vector3(0.15,0.03,0.025))
	metal.color = Color.WHITE

func _signature_idle() -> void:
	if _teeth != null: _teeth.position.y = 0.012*pow(maxf(0.0,sin(_t*5.0)),6.0)
	if _core_node == null: return
	var wave := sin(_t*4.0)
	match _kind:
		&"approve_shield": _core_node.scale = Vector3.ONE*(1.0+0.04*wave)
		&"auto_fix": _core_node.rotation.z = 0.10*sin(_t*6.0)
		&"lgtm": _core_node.position.y = 0.012*maxf(0.0,wave)
		&"nitro": _core_node.scale.y = 1.0+0.07*sin(_t*9.0)
		&"super_jump": _core_node.scale.y = 1.0+0.10*sin(_t*3.0)
		&"code_review": _core_node.position.y = 0.009*sin(_t*2.0)
		&"review_comment": _core_node.scale.x = 1.0+0.06*sin(_t*5.0)
		&"unit_test": _core_node.position.y = 0.01*sin(_t*2.5)
		&"auto_fix_patch": _core_node.position.x = 0.014*sin(_t*6.0)

func reset() -> void:
	_t = 0.0
	_rear_mix = 0.0
	_beam_offset = 0.0
	_last_affordance_clock = 0.0
	_range_boost = -1.0
	_collect_time = -1.0
	_pivot.transform = Transform3D.IDENTITY
	if _core_node != null: _core_node.transform = Transform3D.IDENTITY
	if _teeth != null: _teeth.position = Vector3.ZERO
	_tag.modulate.a = 1.0
	_tag.transform = Transform3D(Basis.IDENTITY,Vector3(0,-0.50,0.045))
	_pool.show()
	_glyph.show()
	_update_affordance()
	show()
	set_process(true)

func collect() -> void:
	if _collect_time >= 0.0: return
	_collect_time = 0.0
	_glyph.hide()
	# Use the enclosing live scene, never Window or backend-owned Tools/Chunks.
	# The arena counts all direct children of Tools, not just gameplay groups.
	var host: Node = self
	while host.get_parent() != null and host.get_parent() != get_tree().root:
		host = host.get_parent()
	if host == self or host == get_parent() or host == get_tree().root:
		_pool.hide()
		return
	# Pooled under the host: a repeat grab restarts an idle burst instead of building one.
	var burst := Burst.acquire(host)
	burst.global_position = global_position
	burst.start(_accent)
	_pool.hide()

func _process(delta: float) -> void:
	if _pivot == null: return
	_t += delta
	var clock := _t*(1.0+_phase*0.12)+_phase
	for material in _materials:
		material.set_shader_parameter("clock",clock)
	# A bounded display-rock keeps each solid icon readable throughout its idle cycle.
	_pivot.rotation.y = 0.0 if _is_tool else sin(_t * 1.6) * 0.28
	_pivot.position.y = 0.06*sin(_t*(3.6 if _is_tool else 2.4))
	# Ground projection follows actual backend spawn height, including jump tools.
	_pool.global_position.y = POOL_Y
	_update_affordance(true)
	_signature_idle()
	if _collect_time < 0.0: return
	_collect_time += delta
	var u := clampf(_collect_time/0.25,0.0,1.0)
	var size := lerpf(1.0,1.45,u/0.35) if u < 0.35 else lerpf(1.45,0.0,(u-0.35)/0.65)
	_pivot.scale = Vector3.ONE * maxf(0.001,size)
	_tag.modulate.a = 1.0-u
	if u >= 1.0:
		get_parent().hide()
		set_process(false)

func _glyph_size(camera: Camera3D, center: Vector3) -> float:
	var depth := maxf(0.1,-camera.to_local(center).z)
	var height := maxf(1.0,get_viewport().get_visible_rect().size.y)
	var distance := maxf(0.0,depth-8.0)
	var pixels := lerpf(32.0,24.0,smoothstep(6.0,45.0,distance))
	var metres := pixels/_glyph_coverage*2.0*depth*tan(deg_to_rad(camera.fov)*0.5)/height
	var size := metres
	# Entire quad, including transparent corners, stays inside the corridor.
	var axes := camera.global_basis.orthonormalized()
	var extent := (axes.x.abs()+axes.y.abs())*0.5
	size = minf(size,(4.0-absf(center.x))/maxf(0.001,extent.x))
	size = minf(size,(6.4-center.y)/maxf(0.001,extent.y))
	size = minf(size,(center.y-0.05)/maxf(0.001,extent.y))
	return clampf(size,0.01,3.8)

func _glyph_rect(camera: Camera3D, center: Vector3, size: float) -> Rect2:
	var screen := camera.unproject_position(center)
	var radius := camera.unproject_position(center+camera.global_basis.y*size*0.5).distance_to(screen)
	return Rect2(screen-Vector2.ONE*radius,Vector2.ONE*radius*2.0)

## Screen data other pickups compare against: depth, lateral offset and grown glyph rect.
func _peer_entry(camera: Camera3D) -> Dictionary:
	var local := camera.to_local(global_position)
	var center: Vector3 = global_position+Vector3.UP*0.9
	return {"art": self, "depth": -local.z, "x": local.x, "rect": _glyph_rect(camera,center,_glyph_size(camera,center)).grow(3.0)}

## Live peers. `shared` (the per-frame _process path) reuses one snapshot per process frame;
## direct calls rebuild it so callers that move pickups between calls see fresh poses.
static func _peer_snapshot(tree: SceneTree, camera: Camera3D, shared: bool) -> Array[Dictionary]:
	var stamp := Engine.get_process_frames()
	if shared and stamp == _peer_frame: return _peers
	_peer_frame = stamp if shared else -1
	_peers.clear()
	for other in tree.get_nodes_in_group(PICKUP_GROUP):
		if not is_instance_valid(other) or not other.is_visible_in_tree() or other._collect_time >= 0.0: continue
		_peers.append(other._peer_entry(camera))
	return _peers

func _set_if_changed(material: ShaderMaterial, key: StringName, value: float) -> void:
	# Per-instance uniforms are only rewritten when they move, not every frame.
	if material.get_shader_parameter(key) != value: material.set_shader_parameter(key,value)

func _update_affordance(shared := false) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var depth := -camera.to_local(global_position).z
	var player_distance := maxf(0.0,depth-8.0)
	_near_fade = smoothstep(0.0,6.0,player_distance)
	_set_if_changed(_pool.material_override,&"near_fade",_near_fade)
	var pixel_metres := 2.0*maxf(0.1,depth)*tan(deg_to_rad(camera.fov)*0.5)/maxf(1.0,get_viewport().get_visible_rect().size.y)
	# Soft flared sheath stays narrower than half a lane at every distance.
	_beam_width = clampf(8.0*pixel_metres,0.35,0.9)
	_set_if_changed(_pool.material_override,&"beam_width",_beam_width)
	_pool.global_rotation.y = camera.global_rotation.y
	var boost := lerpf(1.0,3.0,smoothstep(10.0,60.0,player_distance))
	if boost != _range_boost:
		_range_boost = boost
		for material in _surface_materials: material.set_shader_parameter("range_boost",boost)
	_glyph.position = Vector3(0,0.9,0)
	var center := _glyph.global_position
	var size := _glyph_size(camera,center)
	var rear := false
	var same_lane_rear := false
	var same_lane_front := false
	var own_x := camera.to_local(global_position).x
	var own_rect := _glyph_rect(camera,center,size)
	for other: Dictionary in _peer_snapshot(get_tree(),camera,shared):
		if other.art == self: continue
		var other_depth: float = other.depth
		if other_depth <= 0.0: continue
		var same_lane := absf(float(other.x)-own_x) < 0.75
		if other_depth >= depth-0.1:
			same_lane_front = same_lane_front or same_lane
			continue
		var overlap := own_rect.intersects(other.rect)
		rear = rear or same_lane or overlap
		same_lane_rear = same_lane_rear or same_lane
	# The pausable art clock controls a half-second smooth transition, never a hide.
	var elapsed := maxf(0.0,_t-_last_affordance_clock)
	_last_affordance_clock = _t
	_rear_mix = move_toward(_rear_mix,1.0 if rear else 0.0,elapsed/0.5)
	var blend := smoothstep(0.0,1.0,_rear_mix)
	size *= lerpf(1.0,0.32,blend)
	_depth_alpha = lerpf(1.0,0.45,blend)*pow(60.0/maxf(60.0,player_distance),0.5)
	# Opposed narrow beam centers provide a second positional cue within the lane.
	var target_offset := 0.65 if same_lane_rear else (-0.45 if same_lane_front else 0.0)
	_beam_offset = move_toward(_beam_offset,target_offset,elapsed*2.2)
	_set_if_changed(_pool.material_override,&"beam_offset",_beam_offset)
	_glyph.position.x = _beam_offset
	size = minf(size,_glyph_size(camera,_glyph.global_position))
	_glyph.scale = Vector3.ONE*size
	_glyph.global_basis = camera.global_basis.orthonormalized()*Basis.from_scale(_glyph.scale)
	_set_if_changed(_glyph.material_override,&"depth_alpha",_depth_alpha)
	_glyph.visible = _collect_time < 0.0
