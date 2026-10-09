extends Node3D
## Contract 2.6: model adapter. A null load lets the visual build BossArt instead.
const Materials = preload("res://scenes/runner/boss/hifi/boss_materials.gd")
const ACTIONS: Array[StringName] = [&"intro", &"idle", &"telegraph", &"attack", &"hurt", &"phase_change", &"defeat", &"retreat"]
const SOCKETS: Array[StringName] = [&"fx_core", &"fx_0", &"fx_1", &"fx_2", &"fx_3", &"fx_4", &"fx_5", &"muzzle_0", &"muzzle_1", &"muzzle_2"]
var model: Node3D
var animation_player: AnimationPlayer
var materials: Array[ShaderMaterial] = []
var _sockets: Dictionary = {}

static func rest_positions(mesh: Mesh, surface: int) -> PackedVector3Array:
	# Kit v2 reserves UV2.xy for rest xy and CUSTOM0.xy for rest z / ABI version.
	var flags: int = mesh.surface_get_format(surface)
	if not flags & Mesh.ARRAY_FORMAT_TEX_UV2 or not flags & Mesh.ARRAY_FORMAT_CUSTOM0:
		return PackedVector3Array()
	var format: int = (flags >> Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) & Mesh.ARRAY_FORMAT_CUSTOM_MASK
	var stride := 2 if format == Mesh.ARRAY_CUSTOM_RG_FLOAT else 4 if format == Mesh.ARRAY_CUSTOM_RGBA_FLOAT else 0
	if stride == 0:
		return PackedVector3Array()
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var xy: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var encoded: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	if xy.size() != vertices.size() or encoded.size() != vertices.size() * stride:
		return PackedVector3Array()
	var result := PackedVector3Array()
	for index in vertices.size():
		if not is_equal_approx(encoded[index * stride + 1], 1.0):
			return PackedVector3Array()
		var point := Vector3(xy[index].x, xy[index].y, encoded[index * stride])
		if not point.is_finite() or point.distance_to(vertices[index]) > 0.0001:
			return PackedVector3Array()
		result.append(point)
	return result

func _bind_dissolve_origin() -> void:
	# The kit exports identity mesh transforms. Burn outwards from the core in rest space.
	var core := socket(&"fx_core")
	if core == null:
		return
	var origin := _rest_transform(core).origin
	var radius := 0.01
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var bounds := mesh.get_aabb()
		var relative := _rest_transform(mesh)
		for corner in 8:
			radius = maxf(radius, origin.distance_to(relative * bounds.get_endpoint(corner)))
	_set_parameter(&"dissolve_origin", origin)
	_set_parameter(&"dissolve_radius", radius)

func _rest_transform(node: Node3D) -> Transform3D:
	if node == self:
		return Transform3D.IDENTITY
	if node is BoneAttachment3D:
		var skeleton := node.get_parent() as Skeleton3D
		if skeleton != null:
			var index := skeleton.find_bone(node.bone_name)
			if index >= 0:
				return _rest_transform(skeleton) * skeleton.get_bone_global_rest(index)
	var parent := node.get_parent() as Node3D
	return _rest_transform(parent) * node.transform if parent != null else node.transform

static func load_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var imported := packed.instantiate()
	if not imported is Node3D:
		imported.free()
		return null
	var result = new()
	result.name = "BossModel"
	result.model = imported
	result.add_child(imported)
	if not result._bind():
		result.free()
		return null
	return result

func _bind() -> bool:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		return false
	animation_player = players[0] as AnimationPlayer
	var library := AnimationLibrary.new()
	for action in ACTIONS:
		if not animation_player.has_animation(action):
			return false
		var clip := animation_player.get_animation(action).duplicate(true) as Animation
		clip.loop_mode = Animation.LOOP_LINEAR if action == &"idle" else Animation.LOOP_NONE
		library.add_animation(action, clip)
	for key in animation_player.get_animation_library_list():
		animation_player.remove_animation_library(key)
	animation_player.add_animation_library(&"", library)
	animation_player.playback_default_blend_time = 0.08
	# Keep the imported player in place so all track and skeleton paths remain valid.
	for key in SOCKETS:
		var found := model.find_child(String(key), true, false) as Node3D
		if found == null:
			return false
		_sockets[key] = found
	var copies: Dictionary = {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for index in mesh.mesh.get_surface_count():
			# Old/unencoded assets use the visual's procedural fallback until rebuilt.
			if rest_positions(mesh.mesh, index).is_empty():
				return false
			var source := mesh.get_active_material(index) as BaseMaterial3D
			if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				return false
			if not copies.has(source):
				copies[source] = Materials.surface_from(source)
				materials.append(copies[source])
			mesh.set_surface_override_material(index, copies[source])
	_configure(self)
	_bind_dissolve_origin()
	return not materials.is_empty()

func _configure(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in node.get_children():
		_configure(child)

func play(action: StringName) -> void:
	if animation_player != null and animation_player.has_animation(action):
		animation_player.play(action)
		if is_inside_tree():
			animation_player.advance(0.0)

func socket(key: StringName) -> Node3D:
	return _sockets.get(key) as Node3D

func set_dissolve(value: float) -> void:
	_set_parameter(&"dissolve", clampf(value, 0.0, 1.0))

func set_flash(value: float) -> void:
	_set_parameter(&"flash", clampf(value, 0.0, 1.0))

func set_phase_tint(value: Color) -> void:
	_set_parameter(&"phase_tint", value)

func set_time_factor(value: float) -> void:
	if animation_player != null:
		animation_player.speed_scale = maxf(value, 0.0)

func _set_parameter(key: StringName, value: Variant) -> void:
	for material in materials:
		material.set_shader_parameter(key, value)
