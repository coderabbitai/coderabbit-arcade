extends Node3D
const Forge = preload("res://scenes/runner/powerups/visuals/hifi/mesh_forge.gd")
const Finish = preload("res://scenes/runner/powerups/visuals/hifi/pickup_materials.gd")
const Grab = preload("res://scenes/runner/powerups/visuals/hifi/grab_affordance.gd")
const Burst = preload("res://scenes/runner/powerups/visuals/hifi/collect_burst.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
## Scripted Blender hero props (tools/blender/props/build_props.py): PU_<kind> holds the neutral
## shell ("Ring") and the family-coloured working part ("InnerCore").
const PropScene = preload("res://Assets/runner/props/pickup_props.glb")
## Subdued hardware glow on the shell's baked inlays; the working part carries the family colour.
const FRAME_ENERGY := 0.40
const CORE_ENERGY := 0.55
const BACKED_KINDS := [&"approve_shield",&"auto_fix",&"lgtm",&"nitro",&"super_jump",&"code_review",&"review_comment",&"lint_rule",&"unit_test",&"auto_fix_patch"]
## Deeper body mint (art review r1): the hue of MINT.lerp(MATRIX,0.25) at saturation 0.62 and 95% of
## its value; Blender bakes the same colour (build_props.py BODY_MINT, 53daad).
const BODY_MINT := Color(83.0/255.0,218.0/255.0,173.0/255.0)
static var FRAME_MINT := Palette.SLATE.lerp(Palette.MINT,0.45).lightened(0.18)
static var FRAME_REVIEW := FRAME_MINT.lightened(0.10).lerp(Palette.MINT,0.12)
static var FRAME_ORANGE := Palette.ORANGE.lerp(Palette.CREAM,0.15)
const TAGS := {&"approve_shield":"APPROVE", &"auto_fix":"AUTO FIX", &"lgtm":"LGTM", &"nitro":"NITRO", &"super_jump":"JUMP", &"code_review":"REVIEW", &"review_comment":"COMMENT", &"lint_rule":"LINT", &"unit_test":"TEST", &"auto_fix_patch":"PATCH"}
var _kind: StringName
var _core_node: MeshInstance3D
var _core_rest := Transform3D.IDENTITY
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
## PU_<kind> -> {role: [mesh, transform]} read once from the GLB SceneState (no scene instancing).
static var _prop_layouts: Dictionary = {}
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
	# Neutral CREAM shell with baked MINT / ORANGE inlays; all sculpture emission stays in the family.
	var glow := Grab.TOOL_ORANGE if is_tool else BODY_MINT
	_add_mesh("Ring",shapes.frame,Finish.prop(Palette.CREAM,FRAME_ENERGY,glow),_pivot)
	if shapes.core != null:
		_core_node = _add_mesh("InnerCore",shapes.core,Finish.prop(_accent,CORE_ENERGY,glow),_pivot)
		_core_rest = shapes.core_rest
		_core_node.transform = _core_rest
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
	var friendly := Grab.TOOL_BEAM if is_tool else Palette.MINT
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
		if material.shader in [Finish.template("opaque").shader,Finish.template("glass").shader,Finish.template("prop").shader]:
			_surface_materials.append(material)
	_set_modes(self)

## Builds (once per kind) every immutable piece of a pickup: baked shell and core meshes, tag fit and
## glyph coverage. Also a warm-up hook: calling it before play moves all of that CPU work off the run.
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
	var parts := prop_parts(kind)
	var frame_mesh: Mesh = parts.Ring[0]
	var core_part: Array = parts.get("InnerCore",[null,Transform3D.IDENTITY])
	# Fit the longest tag inside the plate at the fixed 0.0045 world pixel size.
	var text: String = TAGS[kind]
	var tag_size := 32
	var tag_font: Font = ThemeDB.fallback_font
	while (tag_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,tag_size).x+6*2)*0.0045 > 0.70:
		tag_size -= 1
	var shapes := {"frame": frame_mesh, "core": core_part[0], "core_rest": core_part[1], "tag_size": tag_size, "coverage": Grab.coverage(kind)}
	_kind_cache[kind] = shapes
	return shapes

## {role: [mesh, rest transform]} of PU_<kind>, read from the GLB's SceneState once for all kinds.
static func prop_parts(kind: StringName) -> Dictionary:
	if _prop_layouts.is_empty():
		var state := PropScene.get_state()
		for i in state.get_node_count():
			var path := String(state.get_node_path(i)).trim_prefix("./").split("/")
			if path.size() != 2: continue
			var mesh: Mesh = null
			var pose := Transform3D.IDENTITY
			for p in state.get_node_property_count(i):
				match state.get_node_property_name(i,p):
					&"mesh": mesh = state.get_node_property_value(i,p)
					&"transform": pose = state.get_node_property_value(i,p)
			var role := String(state.get_node_name(i)).split("__")[1]
			if not _prop_layouts.has(path[0]): _prop_layouts[path[0]] = {}
			_prop_layouts[path[0]][role] = [mesh,pose]
	return _prop_layouts.get("PU_"+String(kind),{})

## Warm-up hook: every per-kind CPU cache (meshes, glyph raster, tag fit) for `kind`.
static func warm_kind(kind: StringName) -> void:
	kind_shapes(kind)

## Drops the static caches (tests call this before quitting, like Finish.cache.clear()).
static func release_caches() -> void:
	_kind_cache.clear()
	_prop_layouts.clear()
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

func _signature_idle() -> void:
	if _core_node == null: return
	var wave := sin(_t*4.0)
	# Every working part moves about its own baked rest pose, within the pickup envelope.
	var pose := _core_rest
	match _kind:
		&"approve_shield": pose = pose.scaled_local(Vector3.ONE*(1.0+0.04*wave))
		&"auto_fix": pose = pose*Transform3D(Basis(Vector3.UP,_t*5.0))
		&"lgtm": pose.origin.y += 0.012*maxf(0.0,wave)
		&"nitro": pose = pose.scaled_local(Vector3(1.0,1.0+0.07*sin(_t*9.0),1.0))
		&"super_jump": pose = pose.scaled_local(Vector3(1.0,1.0+0.10*sin(_t*3.0),1.0))
		&"code_review": pose.origin.y += 0.009*sin(_t*2.0)
		&"review_comment": pose = pose.scaled_local(Vector3(1.0+0.06*sin(_t*5.0),1.0,1.0))
		&"lint_rule": pose = pose*Transform3D(Basis(Vector3.UP,sin(_t*1.5)*0.35))
		&"unit_test": pose.origin.y += 0.01*sin(_t*2.5)
		&"auto_fix_patch": pose.origin.x += 0.014*sin(_t*6.0)
	_core_node.transform = pose

func reset() -> void:
	_t = 0.0
	_rear_mix = 0.0
	_beam_offset = 0.0
	_last_affordance_clock = 0.0
	_range_boost = -1.0
	_collect_time = -1.0
	_pivot.transform = Transform3D.IDENTITY
	if _core_node != null: _core_node.transform = _core_rest
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

## unproject_position() projects through get_camera_transform(), which for a physics-interpolated
## camera is the pose it was last drawn at, not global_transform: a camera created or moved this
## frame is still at its old pose (identity for a new one) until its next process tick. A point on
## that pose's camera plane made the engine log "p.d == 0" once per pickup and peer (294 errors in
## the a4 capture, whose pickups sit at z 0 with a fresh camera). A point not in front of the drawn
## camera has no screen rect: an empty one far off screen, which overlaps nothing even grown.
func _glyph_rect(camera: Camera3D, center: Vector3, size: float) -> Rect2:
	var view := camera.get_camera_transform().affine_inverse()
	var top := center+camera.global_basis.y*size*0.5
	if (view*center).z > -camera.near or (view*top).z > -camera.near: return Rect2(-1e6,-1e6,0,0)
	var screen := camera.unproject_position(center)
	var radius := camera.unproject_position(top).distance_to(screen)
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
