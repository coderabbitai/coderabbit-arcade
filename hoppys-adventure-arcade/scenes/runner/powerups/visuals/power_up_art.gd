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
var _materials: Array[ShaderMaterial] = []
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
	_accent = Palette.MATRIX if is_tool else Palette.MINT
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var metal := Forge.new()
	var glass := Forge.new()
	var core := Forge.new()
	_build_icon(_kind,metal,glass,core)
	if _kind in BACKED_KINDS:
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
	var frame_tint := FRAME_ORANGE if is_tool else FRAME_MINT
	# Lift only the magnifier diffuse plating; mint mix retains saturation.
	if _kind == &"code_review": frame_tint = FRAME_REVIEW
	var frame_material := Finish.material(frame_tint,0.55)
	frame_material.set_shader_parameter("inlay_tint",Palette.MATRIX if is_tool else BODY_MINT)
	_add_mesh("Ring",frame_mesh,frame_material,_pivot)
	if kind == &"auto_fix": frame_material.set_shader_parameter("emission_inset",0.26)
	if core.vertex_count > 0:
		_core_node = _add_mesh("InnerCore",core.finish(),Finish.material(_accent,4.8),_pivot)
		_core_node.material_override.set_shader_parameter("emission_fill",0.65)
	if kind == &"lint_rule": _build_teeth()
	if not is_tool:
		# Opaque frame contributes the same broad patch as ORANGE tool frames.
		# Diffuse frame and all sculpture emission remain in the MINT family.
		for material in _materials: material.set_shader_parameter("emission_tint",BODY_MINT)
	var plate := Forge.new()
	plate.bar(Vector3.ZERO,Vector2(0.72,0.16),0.0,0.025)
	_tag_plate = _add_mesh("TagPlate",plate.finish(),Finish.material(Palette.NAVY_2),self)
	_tag_plate.position = Vector3(0,-0.50,0.01)
	_tag = Label3D.new()
	_tag.name = "Tag"
	_tag.text = TAGS.get(kind,"PICKUP")
	_tag.font_size = 32
	_tag.pixel_size = 0.0045
	_tag.outline_size = 6
	# Keep the larger world pixel size; fit the longest tag inside the plate.
	var tag_font: Font = ThemeDB.fallback_font
	while (tag_font.get_string_size(_tag.text,HORIZONTAL_ALIGNMENT_LEFT,-1,_tag.font_size).x+_tag.outline_size*2)*_tag.pixel_size > 0.70:
		_tag.font_size -= 1
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
	_pool.position.y = -1.0 + 0.012
	var glyph_quad := QuadMesh.new()
	glyph_quad.size = Vector2.ONE
	_glyph = _add_mesh("HologramGlyph",glyph_quad,Grab.material(friendly,_kind),self)
	_glyph.position.y = 1.15
	var glyph_texture: Texture2D = _glyph.material_override.get_shader_parameter("glyph")
	_glyph_coverage = float(glyph_texture.get_image().get_used_rect().size.y)/glyph_texture.get_height()
	_set_modes(self)

func _set_modes(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in node.get_children(): _set_modes(child)

func _add_mesh(title: String, shape: Mesh, material: ShaderMaterial, parent: Node3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = title
	mesh.mesh = shape
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	_materials.append(material)
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

func _build_icon(kind: StringName, metal: RefCounted, glass: RefCounted, core: RefCounted) -> void:
	match kind:
		&"approve_shield":
			_framed_polygon(metal,glass,[Vector2(0,-0.24),Vector2(0.21,-0.08),Vector2(0.21,0.16),Vector2(0,0.24),Vector2(-0.21,0.16),Vector2(-0.21,-0.08)])
			_check(core,Vector3(0,0,0.028),1.3)
		&"auto_fix":
			_framed_polygon(metal,glass,[Vector2(-0.16,-0.21),Vector2(-0.10,-0.24),Vector2(0.08,0.04),Vector2(0.17,0.07),Vector2(0.20,0.17),Vector2(0.13,0.12),Vector2(0.07,0.17),Vector2(0.09,0.23),Vector2(-0.01,0.19),Vector2(-0.02,0.09)])
			core.bar(Vector3(-0.08,-0.11,0.10),Vector2(0.024,0.25),-0.6,0.025)
			_polygon(core,[Vector2(0.21,-0.24),Vector2(0.23,-0.15),Vector2(0.30,-0.13),Vector2(0.23,-0.10),Vector2(0.21,-0.03),Vector2(0.19,-0.10),Vector2(0.12,-0.13),Vector2(0.19,-0.15)],0.035,0.10)
		&"lgtm":
			_framed_polygon(metal,glass,[Vector2(-0.18,-0.12),Vector2(0.08,-0.12),Vector2(0.16,-0.07),Vector2(0.19,0.07),Vector2(0.06,0.07),Vector2(0.07,0.21),Vector2(0.015,0.22),Vector2(-0.07,0.08),Vector2(-0.18,0.06)])
			metal.bar(Vector3(-0.225,-0.04,0),Vector2(0.09,0.32),0,0.15)
			_check(core,Vector3(0,-0.025,0.035),0.85)
		&"nitro":
			_framed_polygon(metal,glass,[Vector2(-0.09,-0.12),Vector2(0.09,-0.12),Vector2(0.105,0.12),Vector2(0.06,0.21),Vector2(0,0.24),Vector2(-0.06,0.21),Vector2(-0.105,0.12)],Vector2(1.6,1.7),0.18)
			metal.bar(Vector3(0,-0.23,0),Vector2(0.33,0.08),0,0.20)
			for side: float in [-1,1]:
				metal.bar(Vector3(side*0.19,-0.10,0),Vector2(0.075,0.25),side*0.32,0.10)
			core.bar(Vector3(0,0.095,0.12),Vector2(0.032,0.32),0,0.025)
			_polygon(core,[Vector2(-0.09,-0.29),Vector2(0,-0.41),Vector2(0.09,-0.29)],0.06)
		&"super_jump":
			var coil := PackedVector3Array()
			# 32 path sections x 24 smooth sides, with both end caps, replaces 96 x 8.
			for i in 33:
				var angle := TAU*2.5*i/32.0
				coil.append(Vector3(cos(angle)*0.19,-0.28+0.57*i/32.0,sin(angle)*0.095))
			glass.tube(coil,0.026)
			for y: float in [-0.33,0.34]: metal.bar(Vector3(0,y,0),Vector2(0.46,0.065),0,0.22)
			for side: float in [-1,1]: metal.bar(Vector3(side*0.205,0,-0.07),Vector2(0.025,0.64),0,0.04)
			core.bar(Vector3(0,0.02,0),Vector2(0.035,0.56),0,0.035)
		&"code_review":
			var lens_center := Vector3(-0.075,0.115,0.025)
			metal.ring(lens_center,0.175,0.025)
			metal.bar(Vector3(0.14,-0.17,0.025),Vector2(0.075,0.29),0.64,0.085)
			var lens := PackedVector2Array()
			for i in 32:
				var angle := TAU*i/32.0
				lens.append(Vector2(cos(angle),sin(angle))*0.145)
			glass.panel(lens,0.035,0.006,lens_center)
			# Diff card and rows fit completely within the lens opening.
			metal.color = Color(0.18,0.22,0.25)
			metal.bar(lens_center+Vector3(0,0,0.0),Vector2(0.15,0.17),0,0.012)
			metal.color = Color.WHITE
			for y: float in [-0.042,0.042]: core.bar(lens_center+Vector3(0,y,0.018),Vector2(0.13,0.030),0,0.016)
		&"review_comment":
			_framed_polygon(metal,glass,[Vector2(-0.22,-0.07),Vector2(-0.14,-0.07),Vector2(-0.18,-0.24),Vector2(0.02,-0.07),Vector2(0.21,-0.04),Vector2(0.23,0.18),Vector2(-0.20,0.21)],Vector2(1.35,1.35))
			for x: float in [-0.065,0.065]: core.bar(Vector3(x,0.075,0.095),Vector2(0.027,0.14),-0.35,0.025)
		&"lint_rule":
			metal.bar(Vector3(0,-0.22,0),Vector2(0.57,0.15),0,0.13)
			glass.bar(Vector3(0,-0.22,0.076),Vector2(0.50,0.065),0,0.025)
			# The separate MATRIX tooth MultiMesh is also this icon's illuminated core.
		&"unit_test":
			for side: float in [-1,1]:
				metal.bar(Vector3(side*0.255,0,0),Vector2(0.06,0.53),0,0.12)
				metal.bar(Vector3(0,side*0.255,0),Vector2(0.53,0.06),0,0.12)
				glass.bar(Vector3(side*0.255,0,0.07),Vector2(0.018,0.46),0,0.025)
				glass.bar(Vector3(0,side*0.255,0.07),Vector2(0.46,0.018),0,0.025)
			_check(core,Vector3(0,0,0.03),1.55)
		&"auto_fix_patch":
			for x: float in [-0.13,0.13]:
				var points := [Vector2(x-0.11,-0.24),Vector2(x+0.095,0),Vector2(x-0.11,0.24),Vector2(x-0.04,0.27),Vector2(x+0.18,0),Vector2(x-0.04,-0.27)]
				# Ensure the concave chevron has consistent winding before offsetting.
				points.reverse()
				_framed_polygon(metal,glass,points,Vector2.ONE)
			core.bar(Vector3(-0.18,-0.205,0.075),Vector2(0.09,0.023),0.82,0.025)
			core.bar(Vector3(0.08,0.205,0.075),Vector2(0.09,0.023),-0.82,0.025)

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
	var burst := Burst.new()
	# Use the enclosing live scene, never Window or backend-owned Tools/Chunks.
	# The arena counts all direct children of Tools, not just gameplay groups.
	var host: Node = self
	while host.get_parent() != null and host.get_parent() != get_tree().root:
		host = host.get_parent()
	if host == self or host == get_parent() or host == get_tree().root:
		burst.free()
		_pool.hide()
		return
	host.add_child(burst)
	burst.global_position = global_position
	burst.start(_accent)
	_pool.hide()

func _process(delta: float) -> void:
	if _pivot == null: return
	_t += delta
	for material in _materials:
		var phase := float(TAGS.keys().find(_kind))*0.37
		material.set_shader_parameter("clock",_t*(1.0+phase*0.12)+phase)
	# Preserve the tested power-up cadence; boss tools remain front-facing.
	_pivot.rotation.y = 0.0 if _is_tool else _t * 1.6
	_pivot.position.y = 0.06*sin(_t*(3.6 if _is_tool else 2.4))
	# Ground projection follows actual backend spawn height, including jump tools.
	_pool.global_position.y = 0.012
	_update_affordance()
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
	var pixels := lerpf(96.0,32.0,smoothstep(6.0,45.0,distance))
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

func _update_affordance() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var depth := -camera.to_local(global_position).z
	var player_distance := maxf(0.0,depth-8.0)
	_near_fade = smoothstep(0.0,6.0,player_distance)
	_pool.material_override.set_shader_parameter("near_fade",_near_fade)
	var pixel_metres := 2.0*maxf(0.1,depth)*tan(deg_to_rad(camera.fov)*0.5)/maxf(1.0,get_viewport().get_visible_rect().size.y)
	# Soft flared sheath stays narrower than half a lane at every distance.
	_beam_width = clampf(8.0*pixel_metres,0.35,0.9)
	_pool.material_override.set_shader_parameter("beam_width",_beam_width)
	_pool.global_rotation.y = camera.global_rotation.y
	for material in _materials:
		if material.shader == Finish.template("opaque").shader or material.shader == Finish.template("glass").shader:
			material.set_shader_parameter("range_boost",lerpf(1.0,3.0,smoothstep(10.0,60.0,player_distance)))
	_glyph.position = Vector3(0,0.9,0)
	var center := _glyph.global_position
	var size := _glyph_size(camera,center)
	var rear := false
	var same_lane_rear := false
	var same_lane_front := false
	for other in get_tree().get_nodes_in_group(PICKUP_GROUP):
		if other == self or not is_instance_valid(other) or not other.is_visible_in_tree() or other._collect_time >= 0.0: continue
		var other_depth := -camera.to_local(other.global_position).z
		if other_depth <= 0.0: continue
		var same_lane := absf(camera.to_local(other.global_position).x-camera.to_local(global_position).x) < 0.75
		if other_depth >= depth-0.1:
			same_lane_front = same_lane_front or same_lane
			continue
		var other_center: Vector3 = other.global_position+Vector3.UP*0.9
		var overlap := _glyph_rect(camera,center,size).intersects(other._glyph_rect(camera,other_center,other._glyph_size(camera,other_center)).grow(3.0))
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
	_pool.material_override.set_shader_parameter("beam_offset",_beam_offset)
	_glyph.position.x = _beam_offset
	size = minf(size,_glyph_size(camera,_glyph.global_position))
	_glyph.scale = Vector3.ONE*size
	_glyph.global_basis = camera.global_basis.orthonormalized()*Basis.from_scale(_glyph.scale)
	_glyph.material_override.set_shader_parameter("depth_alpha",_depth_alpha)
	_glyph.visible = _collect_time < 0.0
