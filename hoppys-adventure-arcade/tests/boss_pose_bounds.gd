extends RefCounted
## CPU skinning for the dummy renderer. Deduplicate mesh vertices by their skin weights so
## animation-envelope checks inspect actual deformed points without repeated UV seam vertices.
static var _points: Dictionary = {}

static func mesh_bounds(mesh: MeshInstance3D) -> AABB:
	if mesh.skin == null: return mesh.global_transform * mesh.get_aabb()
	var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if skeleton == null: return mesh.global_transform * mesh.get_aabb()
	skeleton.force_update_all_bone_transforms()
	if not _points.has(mesh.mesh):
		var groups := {}
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / vertices.size()
			for i in vertices.size():
				var ids := PackedInt32Array()
				var gains := PackedFloat32Array()
				for j in stride:
					if weights[i * stride + j] <= 0.0: continue
					ids.append(bones[i * stride + j])
					gains.append(weights[i * stride + j])
				var key := var_to_str([ids, gains])
				if not groups.has(key): groups[key] = {"ids": ids, "gains": gains, "points": {}}
				groups[key].points[vertices[i]] = true
		var compact := []
		for group: Dictionary in groups.values():
			group.points = PackedVector3Array(group.points.keys())
			compact.append(group)
		_points[mesh.mesh] = compact
	var transforms: Array[Transform3D] = []
	for bind in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		assert(bone >= 0)
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
	var bounds := AABB()
	var first := true
	for group: Dictionary in _points[mesh.mesh]:
		var pose := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
		for i in group.ids.size():
			var part: Transform3D = transforms[group.ids[i]]
			var gain: float = group.gains[i]
			pose.origin += part.origin * gain
			pose.basis.x += part.basis.x * gain
			pose.basis.y += part.basis.y * gain
			pose.basis.z += part.basis.z * gain
		for point: Vector3 in group.points:
			var world := pose * point
			bounds = AABB(world, Vector3.ZERO) if first else bounds.expand(world)
			first = false
	return bounds
