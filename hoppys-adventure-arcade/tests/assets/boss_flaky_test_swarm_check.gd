extends SceneTree

const MODEL_SCRIPT_PATH := "res://scenes/runner/boss/hifi/boss_model.gd"
const MODEL_PATH := "res://Assets/runner/bosses/flaky_test_swarm/flaky_test_swarm.glb"
const BUILD_PATH := "res://Assets/runner/bosses/flaky_test_swarm/flaky_test_swarm.build.json"
const VISUAL_SCENE_PATH := "res://scenes/runner/boss/visuals/flaky_test_swarm_visual.tscn"
const FlakyVisual = preload("res://scenes/runner/boss/visuals/flaky_test_swarm_visual.gd")
const BossVisualBase = preload("res://scenes/runner/boss/boss_visual_base.gd")
const ProjectileArt = preload("res://scenes/runner/boss/visuals/boss_projectile_art.gd")
const ACTIONS: Array[StringName] = [&"intro", &"idle", &"telegraph", &"attack", &"hurt", &"phase_change", &"defeat", &"retreat"]
const INTRO_RED_DRONES: Array[int] = [0, 2, 3, 5]
const SOCKETS: Array[StringName] = [&"fx_core", &"fx_0", &"fx_1", &"fx_2", &"fx_3", &"fx_4", &"fx_5", &"muzzle_0", &"muzzle_1", &"muzzle_2"]
const MAX_TRIANGLES := 18000
const MAX_BONES := 40
const PROCEDURAL_BOUNDS := Vector3(6.093414, 3.931789, 1.010101)
const MAX_REST_DEPTH := 1.7
const MAX_REST_FRONT_Z := 0.8601
const WORLD_HOVER_Z := -14.0
const WORLD_X_MIN := -3.5
const WORLD_X_MAX := 3.5
const WORLD_Y_MIN := 1.6
const WORLD_Y_MAX := 6.1
const WORLD_DEPTH_MAX := 3.0
const BOUNDS_SAMPLE_RATE := 120.0

var checks := 0
var failures := 0
var _cpu_skin_groups: Dictionary = {}
var _bounds_world_summary := {
	"samples": 0,
	"min": Vector3(INF, INF, INF),
	"max": Vector3(-INF, -INF, -INF),
	"max_depth": 0.0,
	"min_y_source": "",
	"max_y_source": "",
	"front_source": "",
	"depth_source": "",
}


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOSS FLAKY SWARM: " + message)


func skeleton_pose_snapshot(skeleton: Skeleton3D) -> Array[Transform3D]:
	skeleton.force_update_all_bone_transforms()
	var snapshot: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		snapshot.append(skeleton.get_bone_global_pose(bone))
	return snapshot


func check_skeleton_pose_matches(skeleton: Skeleton3D, snapshot: Array[Transform3D], label: String) -> void:
	skeleton.force_update_all_bone_transforms()
	check(skeleton.get_bone_count() == snapshot.size(), label + " keeps the same skeleton bone count")
	for bone in mini(skeleton.get_bone_count(), snapshot.size()):
		check(skeleton.get_bone_global_pose(bone).is_equal_approx(snapshot[bone]), "%s preserves bone %d pose" % [label, bone])


func node3d_transform_snapshot(root_node: Node) -> Array[Transform3D]:
	var snapshot: Array[Transform3D] = []
	var pending: Array[Node] = [root_node]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Node3D:
			snapshot.append((node as Node3D).transform)
		for child in node.get_children():
			pending.append(child)
	return snapshot


func check_node3d_transforms_match(root_node: Node, snapshot: Array[Transform3D], label: String) -> void:
	var current := node3d_transform_snapshot(root_node)
	check(current.size() == snapshot.size(), label + " keeps the same fallback geometry node count")
	for index in mini(current.size(), snapshot.size()):
		check(current[index].is_equal_approx(snapshot[index]), "%s preserves fallback node %d transform" % [label, index])


func check_intro_hold_pose(visual: Node, adapter: Node3D, skeleton: Skeleton3D, mode: StringName, seconds: float, probe_progress: float) -> void:
	var pose_progress := float(BossVisualBase.INTRO_POSE_AT[mode])
	var hold_end_progress := float(BossVisualBase.INTRO_HOLD_UNTIL[mode])
	visual.call("on_spawned")
	visual.call("play_cinematic", mode, seconds)
	visual.call("set_cinematic_progress", mode, pose_progress)
	var completed_pose := skeleton_pose_snapshot(skeleton)
	check(StringName(visual.get("_state")) == &"intro", String(mode) + " stays in intro at its shared final-pose cue")
	for progress in [probe_progress, hold_end_progress, 1.0]:
		visual.call("set_cinematic_progress", mode, progress)
		check_skeleton_pose_matches(skeleton, completed_pose, "%s hold progress %.2f" % [String(mode), progress])
	if adapter != null:
		var player := adapter.get("animation_player") as AnimationPlayer
		check(player != null and player.assigned_animation == &"intro", String(mode) + " keeps the intro clip assigned through cinematic completion")
	check(StringName(visual.get("_cinematic_mode")).is_empty(), String(mode) + " clears cinematic mode at progress 1")
	check(StringName(visual.get("_state")) == &"intro", String(mode) + " preserves the completed intro state on the last cinematic frame")
	visual.call("_process", 1.0 / BOUNDS_SAMPLE_RATE)
	check(StringName(visual.get("_state")) == &"idle", String(mode) + " enters idle on the next normal process tick")


func has_shader_param(material: ShaderMaterial, parameter: StringName) -> bool:
	if material == null or material.shader == null:
		return false
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if StringName(uniform.get("name", "")) == parameter:
			return true
	return false


func check_build_report() -> Dictionary:
	check(FileAccess.file_exists(BUILD_PATH), "full-bake build report exists")
	if not FileAccess.file_exists(BUILD_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILD_PATH))
	check(parsed is Dictionary, "build report parses as an object")
	if not parsed is Dictionary:
		return {}
	var report: Dictionary = parsed
	check(report.get("quick", true) == false, "asset report describes the full bake")
	check(int(report.get("animation_sample_rate", -1)) == 120, "actions were baked at 120 Hz")
	check(int(report.get("triangles", -1)) >= 1 and int(report.get("triangles", MAX_TRIANGLES + 1)) <= MAX_TRIANGLES, "triangle budget is at most 18000")
	check(int(report.get("materials", -1)) == 1, "full bake uses one atlas material")
	check(int(report.get("bones", -1)) >= 7 and int(report.get("bones", MAX_BONES + 1)) <= MAX_BONES, "skeleton has a root and six drone bones within budget")
	check(int(report.get("surfaces", -1)) == 1, "full bake exports one surface")
	var actions: Array = report.get("actions", [])
	for action in ACTIONS:
		check(actions.has(String(action)) or actions.has(action), "build report includes action " + String(action))
	var sockets: Array = report.get("sockets", [])
	for socket_name in SOCKETS:
		check(sockets.has(String(socket_name)) or sockets.has(socket_name), "build report includes socket " + String(socket_name))
	return report


func imported_census(model: Node3D) -> Dictionary:
	var triangles := 0
	var surfaces := 0
	var source_materials: Dictionary = {}
	var mesh_count := 0
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		mesh_count += 1
		for surface in instance.mesh.get_surface_count():
			surfaces += 1
			var arrays := instance.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			var material := instance.mesh.surface_get_material(surface)
			if material != null:
				source_materials[material.get_instance_id()] = true
	var bones := 0
	for skeleton_node in skeletons:
		bones += (skeleton_node as Skeleton3D).get_bone_count()
	return {"triangles": triangles, "materials": source_materials.size(), "bones": bones, "surfaces": surfaces, "meshes": mesh_count, "skeletons": skeletons}


func bounds_in_model_space(model: Node3D) -> AABB:
	var found := false
	var result := AABB()
	var model_inverse := model.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var local_bounds := instance.get_aabb()
		for x in [local_bounds.position.x, local_bounds.end.x]:
			for y in [local_bounds.position.y, local_bounds.end.y]:
				for z in [local_bounds.position.z, local_bounds.end.z]:
					var point := model_inverse * instance.global_transform * Vector3(x, y, z)
					if not found:
						result = AABB(point, Vector3.ZERO)
						found = true
					else:
						result = result.expand(point)
	return result


func cpu_skin_rest_bounds(model: Node3D) -> AABB:
	var rigs: Array = model.find_children("*", "Skeleton3D", true, false)
	if rigs.is_empty():
		return AABB()
	var skeleton := rigs[0] as Skeleton3D
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var model_inverse := model.global_transform.affine_inverse()
	var found := false
	var result := AABB()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var skin := instance.skin
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size() / vertices.size() if not vertices.is_empty() else 0
			for vertex_index in vertices.size():
				var point := instance.global_transform * vertices[vertex_index]
				if skin != null and influences > 0 and weights.size() == bones.size():
					var skinned_point := Vector3.ZERO
					var total_weight := 0.0
					for influence in influences:
						var offset := vertex_index * influences + influence
						var weight := weights[offset]
						if weight <= 0.0:
							continue
						var bind_index := bones[offset]
						if bind_index < 0 or bind_index >= skin.get_bind_count():
							continue
						var bone_index := skin.get_bind_bone(bind_index)
						if bone_index < 0:
							continue
						var bone_transform := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index) * skin.get_bind_pose(bind_index)
						skinned_point += bone_transform * vertices[vertex_index] * weight
						total_weight += weight
					if total_weight > 0.0:
						var remainder := maxf(1.0 - total_weight, 0.0)
						point = skinned_point + point * remainder
				point = model_inverse * point
				if not found:
					result = AABB(point, Vector3.ZERO)
					found = true
				else:
					result = result.expand(point)
	return result


func cpu_skin_groups(mesh: Mesh) -> Array:
	if _cpu_skin_groups.has(mesh):
		return _cpu_skin_groups[mesh]
	var grouped: Dictionary = {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := bone_ids.size() / vertices.size() if not vertices.is_empty() else 0
		for vertex_index in vertices.size():
			var ids := PackedInt32Array()
			var gains := PackedFloat32Array()
			for influence in stride:
				var offset := vertex_index * stride + influence
				if offset >= weights.size() or weights[offset] <= 0.0:
					continue
				ids.append(bone_ids[offset])
				gains.append(weights[offset])
			var key := var_to_str([ids, gains])
			if not grouped.has(key):
				grouped[key] = {"ids": ids, "gains": gains, "points": {}}
			grouped[key].points[vertices[vertex_index]] = true
	var compact: Array = []
	for group: Dictionary in grouped.values():
		group.points = PackedVector3Array(group.points.keys())
		compact.append(group)
	_cpu_skin_groups[mesh] = compact
	return compact


func cpu_skin_world_bounds(model_adapter: Node3D) -> AABB:
	var model := model_adapter.get("model") as Node3D
	if model == null:
		return AABB()
	var bounds := AABB()
	var found := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D
		if mesh_instance.skin == null or skeleton == null:
			var transformed := mesh_instance.global_transform * mesh_instance.get_aabb()
			for corner in 8:
				var point := transformed.get_endpoint(corner)
				bounds = AABB(point, Vector3.ZERO) if not found else bounds.expand(point)
				found = true
			continue
		skeleton.force_update_all_bone_transforms()
		var transforms: Array[Transform3D] = []
		for bind_index in mesh_instance.skin.get_bind_count():
			var bone_index := mesh_instance.skin.get_bind_bone(bind_index)
			if bone_index < 0:
				bone_index = skeleton.find_bone(mesh_instance.skin.get_bind_name(bind_index))
			if bone_index < 0:
				continue
			transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone_index) * mesh_instance.skin.get_bind_pose(bind_index))
		for group: Dictionary in cpu_skin_groups(mesh_instance.mesh):
			var pose := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
			for influence in group.ids.size():
				var bind_index: int = group.ids[influence]
				if bind_index < 0 or bind_index >= transforms.size():
					continue
				var part: Transform3D = transforms[bind_index]
				var gain: float = group.gains[influence]
				pose.origin += part.origin * gain
				pose.basis.x += part.basis.x * gain
				pose.basis.y += part.basis.y * gain
				pose.basis.z += part.basis.z * gain
			for local_point: Vector3 in group.points:
				var world_point := pose * local_point if not group.ids.is_empty() else mesh_instance.global_transform * local_point
				bounds = AABB(world_point, Vector3.ZERO) if not found else bounds.expand(world_point)
				found = true
	return bounds


func update_world_envelope(envelope: Dictionary, bounds: AABB, scenario: String) -> void:
	if envelope.samples == 0:
		envelope.min = bounds.position
		envelope.max = bounds.end
		envelope.max_depth = bounds.size.z
		envelope.min_y_source = scenario
		envelope.max_y_source = scenario
		envelope.front_source = scenario
		envelope.depth_source = scenario
	else:
		if bounds.position.x < envelope.min.x:
			envelope.min.x = bounds.position.x
		if bounds.position.y < envelope.min.y:
			envelope.min.y = bounds.position.y
			envelope.min_y_source = scenario
		if bounds.position.z < envelope.min.z:
			envelope.min.z = bounds.position.z
		if bounds.end.x > envelope.max.x:
			envelope.max.x = bounds.end.x
		if bounds.end.y > envelope.max.y:
			envelope.max.y = bounds.end.y
			envelope.max_y_source = scenario
		if bounds.end.z > envelope.max.z:
			envelope.max.z = bounds.end.z
			envelope.front_source = scenario
		if bounds.size.z > envelope.max_depth:
			envelope.max_depth = bounds.size.z
			envelope.depth_source = scenario
	envelope.samples += 1
	if _bounds_world_summary.samples == 0:
		_bounds_world_summary.min = bounds.position
		_bounds_world_summary.max = bounds.end
		_bounds_world_summary.max_depth = bounds.size.z
		_bounds_world_summary.min_y_source = scenario
		_bounds_world_summary.max_y_source = scenario
		_bounds_world_summary.front_source = scenario
		_bounds_world_summary.depth_source = scenario
	else:
		if bounds.position.x < _bounds_world_summary.min.x:
			_bounds_world_summary.min.x = bounds.position.x
		if bounds.position.y < _bounds_world_summary.min.y:
			_bounds_world_summary.min.y = bounds.position.y
			_bounds_world_summary.min_y_source = scenario
		if bounds.position.z < _bounds_world_summary.min.z:
			_bounds_world_summary.min.z = bounds.position.z
		if bounds.end.x > _bounds_world_summary.max.x:
			_bounds_world_summary.max.x = bounds.end.x
		if bounds.end.y > _bounds_world_summary.max.y:
			_bounds_world_summary.max.y = bounds.end.y
			_bounds_world_summary.max_y_source = scenario
		if bounds.end.z > _bounds_world_summary.max.z:
			_bounds_world_summary.max.z = bounds.end.z
			_bounds_world_summary.front_source = scenario
		if bounds.size.z > _bounds_world_summary.max_depth:
			_bounds_world_summary.max_depth = bounds.size.z
			_bounds_world_summary.depth_source = scenario
	_bounds_world_summary.samples += 1


func new_world_envelope() -> Dictionary:
	return {"samples": 0, "min": Vector3.ZERO, "max": Vector3.ZERO, "max_depth": 0.0, "min_y_source": "", "max_y_source": "", "front_source": "", "depth_source": ""}


func assert_world_envelope(envelope: Dictionary, scenario: String) -> void:
	check(envelope.samples > 0, "%s produced CPU-skinned world bounds" % scenario)
	if envelope.samples <= 0:
		return
	var min_point: Vector3 = envelope.min
	var max_point: Vector3 = envelope.max
	check(min_point.x >= WORLD_X_MIN, "%s world min X %.6f >= %.2f" % [scenario, min_point.x, WORLD_X_MIN])
	check(max_point.x <= WORLD_X_MAX, "%s world max X %.6f <= %.2f" % [scenario, max_point.x, WORLD_X_MAX])
	check(min_point.y >= WORLD_Y_MIN, "%s world min Y %.6f >= %.2f" % [scenario, min_point.y, WORLD_Y_MIN])
	check(max_point.y <= WORLD_Y_MAX, "%s world max Y %.6f <= %.2f" % [scenario, max_point.y, WORLD_Y_MAX])
	check(float(envelope.max_depth) <= WORLD_DEPTH_MAX, "%s world depth %.6f <= %.2f" % [scenario, float(envelope.max_depth), WORLD_DEPTH_MAX])
	check(max_point.z <= WORLD_HOVER_Z + 3.0, "%s front Z %.6f <= hover_z + 3 (%.2f)" % [scenario, max_point.z, WORLD_HOVER_Z + 3.0])


func check_model(model_adapter: Node3D, report: Dictionary) -> void:
	var model := model_adapter.get("model") as Node3D
	check(model != null, "BossModel adapter exposes the imported model")
	if model == null:
		return
	var census := imported_census(model)
	for key in ["triangles", "materials", "bones", "surfaces"]:
		check(int(report.get(key, -1)) == int(census[key]), "build report %s matches imported census (%d vs %d)" % [key, int(report.get(key, -1)), int(census[key])])
	check(census.meshes == 1, "baked swarm is one merged skinned mesh")
	check(census.skeletons.size() == 1, "baked swarm has one skeleton")
	if census.skeletons.size() == 1:
		var skeleton := census.skeletons[0] as Skeleton3D
		var root_index := skeleton.find_bone("root")
		check(root_index >= 0, "skeleton exposes root bone")
		for drone_index in 6:
			var bone_index := skeleton.find_bone("drone_%d" % drone_index)
			check(bone_index >= 0, "skeleton exposes drone_%d" % drone_index)
			if root_index >= 0 and bone_index >= 0:
				check(skeleton.get_bone_parent(bone_index) == root_index, "drone_%d is directly parented to the root" % drone_index)
	var model_bounds := bounds_in_model_space(model)
	check(not model_bounds.size.is_zero_approx(), "imported mesh has measurable bounds")
	for axis in 2:
		check(model_bounds.size[axis] >= PROCEDURAL_BOUNDS[axis] * 0.8 and model_bounds.size[axis] <= PROCEDURAL_BOUNDS[axis] * 1.2, "imported XY bounds axis %d stays within 20%% of procedural reference" % axis)
	check(model_bounds.size.z <= MAX_REST_DEPTH, "imported rest depth stays within the 1.7 m exception")
	check(model_bounds.end.z <= MAX_REST_FRONT_Z, "imported front edge stays at or behind z=0.8601 m")
	var skinned_bounds := cpu_skin_rest_bounds(model)
	check(not skinned_bounds.size.is_zero_approx(), "CPU skinning produces measurable rest-pose bounds")
	for axis in 2:
		check(skinned_bounds.size[axis] >= PROCEDURAL_BOUNDS[axis] * 0.8 and skinned_bounds.size[axis] <= PROCEDURAL_BOUNDS[axis] * 1.2, "CPU-skinned rest XY bounds axis %d stay within 20%% of procedural reference" % axis)
	check(skinned_bounds.size.z <= MAX_REST_DEPTH, "CPU-skinned rest depth stays within the 1.7 m exception")
	check(skinned_bounds.end.z <= MAX_REST_FRONT_Z, "CPU-skinned front edge stays at or behind z=0.8601 m")
	var animation_player := model_adapter.get("animation_player") as AnimationPlayer
	check(animation_player != null, "BossModel adapter exposes AnimationPlayer")
	if animation_player != null:
		for action in ACTIONS:
			check(animation_player.has_animation(action), "runtime clip exists: " + String(action))
			if animation_player.has_animation(action):
				var clip := animation_player.get_animation(action)
				check(clip.length > 0.0 and clip.get_track_count() > 0, "runtime clip has keyed motion: " + String(action))
		var idle := animation_player.get_animation(&"idle") if animation_player.has_animation(&"idle") else null
		check(idle != null and idle.loop_mode != Animation.LOOP_NONE, "idle clip loops")
	for socket_name in SOCKETS:
		check(model_adapter.call("socket", socket_name) is Node3D, "adapter resolves socket " + String(socket_name))
	var materials: Variant = model_adapter.get("materials")
	check(materials is Array and materials.size() == 1, "runtime adapter rebuilds the one atlas material")
	if materials is Array:
		for material: Variant in materials:
			check(material is ShaderMaterial, "runtime surface uses the boss shader material")
			if material is ShaderMaterial:
				for parameter in [&"dissolve", &"flash", &"phase_tint"]:
					check(has_shader_param(material, parameter), "runtime shader exposes " + String(parameter))
	model_adapter.call("set_time_factor", 0.25)
	if animation_player != null:
		check(is_equal_approx(animation_player.speed_scale, 0.25), "model adapter applies the requested animation time factor")
	model_adapter.call("set_time_factor", 1.0)


func check_animated_drone_socket(model_adapter: Node3D) -> void:
	var player := model_adapter.get("animation_player") as AnimationPlayer
	var socket := model_adapter.call("socket", &"fx_0") as Node3D
	var model := model_adapter.get("model") as Node3D
	var skeletons: Array = model.find_children("*", "Skeleton3D", true, false) if model != null else []
	check(player != null and socket != null and not skeletons.is_empty(), "drone socket and animation skeleton are available")
	if player == null or socket == null or skeletons.is_empty() or not player.has_animation(&"attack"):
		return
	player.play(&"attack", 0.0)
	player.speed_scale = 0.0
	player.seek(0.0, true)
	await process_frame
	for skeleton_node in skeletons:
		(skeleton_node as Skeleton3D).force_update_all_bone_transforms()
	var start := socket.global_position
	var attack := player.get_animation(&"attack")
	player.seek(attack.length * 0.5, true)
	await process_frame
	for skeleton_node in skeletons:
		(skeleton_node as Skeleton3D).force_update_all_bone_transforms()
	check(socket.global_position.distance_to(start) > 0.01, "fx_0 follows its drone bone during attack")
	player.speed_scale = 1.0
	player.stop()


func make_visual(model_path: String) -> Dictionary:
	var packed := load(VISUAL_SCENE_PATH) as PackedScene
	check(packed != null, "Flaky Test Swarm visual scene loads")
	if packed == null:
		return {}
	var anchor := Node3D.new()
	root.add_child(anchor)
	var visual := packed.instantiate() as Node3D
	check(visual != null, "Flaky Test Swarm visual instantiates")
	if visual == null:
		anchor.queue_free()
		return {}
	visual.set("model_path", model_path)
	anchor.add_child(visual)
	visual.call("on_spawned")
	return {"anchor": anchor, "visual": visual}


func make_world_bounds_visual() -> Dictionary:
	var packed := load(VISUAL_SCENE_PATH) as PackedScene
	check(packed != null, "bounds visual scene loads")
	if packed == null:
		return {}
	var anchor := Node3D.new()
	anchor.position = Vector3(0.0, 2.6, WORLD_HOVER_Z)
	root.add_child(anchor)
	var visual := packed.instantiate() as Node3D
	check(visual != null, "bounds visual instantiates")
	if visual == null:
		anchor.queue_free()
		return {}
	visual.set("hover_z", WORLD_HOVER_Z)
	visual.set("model_path", MODEL_PATH)
	visual.set("sway_amplitude", 2.4)
	visual.set("sway_period", 3.2)
	anchor.add_child(visual)
	visual.call("on_spawned")
	check(visual.global_position.is_equal_approx(Vector3(0.0, 2.6, WORLD_HOVER_Z)), "bounds visual mounts at (0, 2.6, -14)")
	return {"anchor": anchor, "visual": visual}


func sample_bounds_interval(visual: Node3D, model_adapter: Node3D, envelope: Dictionary, scenario: String, seconds: float, include_ambient_extrema := false) -> void:
	var full_steps := int(floor(seconds * BOUNDS_SAMPLE_RATE + 0.00001))
	var sample_index := 0
	for frame in range(full_steps + 1):
		if frame > 0:
			visual.call("_process", 1.0 / BOUNDS_SAMPLE_RATE)
		var bounds := cpu_skin_world_bounds(model_adapter)
		add_world_bounds_sample(visual, envelope, bounds, "%s frame %d" % [scenario, sample_index], include_ambient_extrema)
		sample_index += 1
	var endpoint := float(full_steps) / BOUNDS_SAMPLE_RATE
	var remainder := seconds - endpoint
	if remainder > 0.000001:
		visual.call("_process", remainder)
		var final_bounds := cpu_skin_world_bounds(model_adapter)
		add_world_bounds_sample(visual, envelope, final_bounds, "%s endpoint" % scenario, include_ambient_extrema)


func add_world_bounds_sample(visual: Node3D, envelope: Dictionary, bounds: AABB, scenario: String, include_ambient_extrema: bool) -> void:
	if not include_ambient_extrema:
		update_world_envelope(envelope, bounds, scenario)
		return
	var mounted_position := Vector3(0.0, 2.6, WORLD_HOVER_Z)
	var current_ambient := visual.global_position - mounted_position
	var unshifted := AABB(bounds.position - current_ambient, bounds.size)
	for sway_x in [-0.18, 0.18]:
		for sway_y in [0.0, 0.08]:
			var candidate_shift := Vector3(sway_x, sway_y, 0.0)
			var candidate := AABB(unshifted.position + candidate_shift, unshifted.size)
			update_world_envelope(envelope, candidate, "%s ambient x=%.2f y=%.2f" % [scenario, sway_x, sway_y])


func run_world_action_sweep(visual: Node, model_adapter: Node3D, player: AnimationPlayer, phase: int, action: StringName) -> void:
	visual.call("on_spawned")
	visual.call("set_phase", phase)
	var seconds := player.get_animation(action).length
	match action:
		&"intro": visual.call("play_intro", seconds)
		&"idle": visual.call("_play", &"idle", seconds)
		&"telegraph": visual.call("play_telegraph", 0b010, &"flaky", seconds)
		&"attack": visual.call("play_attack", &"flaky")
		&"hurt": visual.call("play_hit", &"flaky", 1)
		&"phase_change": visual.call("_play", &"phase_change", seconds)
		&"defeat":
			visual.call("play_defeat")
			seconds = float(visual.get("_state_duration"))
		&"retreat":
			visual.call("play_retreat")
			seconds = float(visual.get("_state_duration"))
	var envelope := new_world_envelope()
	var scenario := "phase %d action %s" % [phase, String(action)]
	sample_bounds_interval(visual, model_adapter, envelope, scenario, seconds, action != &"intro")
	assert_world_envelope(envelope, scenario)


func run_world_direct_clip_sweep(visual: Node, model_adapter: Node3D, player: AnimationPlayer, phase: int, action: StringName) -> void:
	visual.call("on_spawned")
	visual.call("set_phase", phase)
	var clip := player.get_animation(action)
	var seconds := clip.length
	visual.call("_play", action, seconds)
	var envelope := new_world_envelope()
	var scenario := "phase %d direct baked clip %s" % [phase, String(action)]
	var frames := int(round(seconds * BOUNDS_SAMPLE_RATE))
	for frame in range(frames + 1):
		var progress := float(frame) / float(frames)
		visual.set("_state_age", progress * seconds)
		visual.call("_seek", action, progress)
		visual.call("_apply_formation")
		var bounds := cpu_skin_world_bounds(model_adapter)
		update_world_envelope(envelope, bounds, "%s frame %d" % [scenario, frame])
	assert_world_envelope(envelope, scenario + " at 120 Hz")


func run_world_signature_sweep(visual: Node, model_adapter: Node3D, phase: int, projectile_kind: StringName, commit: bool) -> void:
	visual.call("on_spawned")
	visual.call("set_phase", phase)
	var seconds := 0.8
	var envelope := new_world_envelope()
	var scenario := "phase %d signature %s%s" % [phase, String(projectile_kind), " commit" if commit else " telegraph"]
	visual.call("play_telegraph", 0b010, projectile_kind, seconds)
	if commit:
		sample_bounds_interval(visual, model_adapter, envelope, scenario + " preview", seconds * 0.5, true)
		visual.call("play_commit", 0b100, projectile_kind, seconds * 0.5)
		sample_bounds_interval(visual, model_adapter, envelope, scenario + " committed", seconds * 0.5, true)
	else:
		sample_bounds_interval(visual, model_adapter, envelope, scenario, seconds, true)
	visual.call("play_attack", projectile_kind)
	var player := model_adapter.get("animation_player") as AnimationPlayer
	if player != null and player.has_animation(&"attack"):
		var attack_seconds := player.get_animation(&"attack").length
		sample_bounds_interval(visual, model_adapter, envelope, scenario + " then attack", attack_seconds, true)
	assert_world_envelope(envelope, scenario)


func run_world_cinematic_sweep(visual: Node, model_adapter: Node3D, phase: int, mode: StringName, seconds: float) -> void:
	var envelope := new_world_envelope()
	var frames := int(round(seconds * BOUNDS_SAMPLE_RATE))
	var inherited_offsets: Array[Vector2] = [Vector2.ZERO]
	if mode in [&"defeat_full", &"defeat_short"]:
		inherited_offsets = [Vector2(-0.18, 0.0), Vector2(-0.18, 0.08), Vector2(0.18, 0.0), Vector2(0.18, 0.08)]
	for offset in inherited_offsets:
		visual.call("on_spawned")
		visual.call("set_phase", phase)
		visual.position += Vector3(offset.x, offset.y, 0.0)
		visual.call("play_cinematic", mode, seconds)
		for frame in range(frames + 1):
			var progress := float(frame) / float(frames)
			visual.call("set_cinematic_progress", mode, progress)
			var bounds := cpu_skin_world_bounds(model_adapter)
			update_world_envelope(envelope, bounds, "phase %d %s offset %s progress %.6f" % [phase, String(mode), offset, progress])
	var scenario := "phase %d cinematic %s at 120 Hz" % [phase, String(mode)]
	assert_world_envelope(envelope, scenario)


func check_world_pose_envelopes() -> void:
	if not FileAccess.file_exists(MODEL_PATH):
		check(false, "world bounds sweeps require imported Flaky Test Swarm model")
		return
	var instance := make_world_bounds_visual()
	if instance.is_empty():
		return
	var visual := instance.visual as Node
	var model_adapter := visual.get("_model") as Node3D
	var player := model_adapter.get("animation_player") as AnimationPlayer if model_adapter != null else null
	check(model_adapter != null and player != null, "world bounds sweeps use the imported model adapter and AnimationPlayer")
	if model_adapter == null or player == null:
		instance.anchor.queue_free()
		return
	for action in ACTIONS:
		check(player.has_animation(action), "world bounds sweep clip exists: %s" % String(action))
	for phase in [1, 2, 3]:
		for action in ACTIONS:
			if player.has_animation(action):
				run_world_action_sweep(visual, model_adapter, player, phase, action)
				run_world_direct_clip_sweep(visual, model_adapter, player, phase, action)
		run_world_signature_sweep(visual, model_adapter, phase, &"flaky", false)
		run_world_signature_sweep(visual, model_adapter, phase, &"scatter", false)
		run_world_signature_sweep(visual, model_adapter, phase, &"flaky", true)
		for mode in [&"intro_full", &"intro_short", &"defeat_full", &"defeat_short"]:
			var duration := 5.0 if mode == &"intro_full" else 2.5 if mode == &"intro_short" else 3.6 if mode == &"defeat_full" else 2.0
			run_world_cinematic_sweep(visual, model_adapter, phase, mode, duration)
		run_world_cinematic_sweep(visual, model_adapter, phase, &"intro_full", 3.6)
		run_world_cinematic_sweep(visual, model_adapter, phase, &"intro_short", 3.6)
	print("BOSS FLAKY SWARM WORLD ENVELOPE: %d samples min=%s (Y at %s) max=%s (Y at %s, front at %s) depth=%.6f at %s" % [
		_bounds_world_summary.samples,
		_bounds_world_summary.min,
		_bounds_world_summary.min_y_source,
		_bounds_world_summary.max,
		_bounds_world_summary.max_y_source,
		_bounds_world_summary.front_source,
		float(_bounds_world_summary.max_depth),
		_bounds_world_summary.depth_source,
	])
	instance.anchor.queue_free()


func advance_visual(visual: Node, seconds: float, step := 1.0 / 120.0) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var delta := minf(step, remaining)
		visual.call("_process", delta)
		remaining -= delta


func shader_value(adapter: Node, parameter: StringName) -> float:
	var materials: Variant = adapter.get("materials")
	if materials is Array:
		for material: Variant in materials:
			if material is ShaderMaterial:
				return float(material.get_shader_parameter(parameter))
	return 0.0


func drone_positions(skeleton: Skeleton3D, bone_indices: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for bone_index in bone_indices:
		result.append(skeleton.get_bone_pose_position(int(bone_index)))
	return result


func average_spread(points: Array[Vector3]) -> float:
	var total := 0.0
	for point in points:
		total += Vector2(point.x, point.y - 1.02).length()
	return total / maxf(points.size(), 1)


func formation_centroid(points: Array[Vector3]) -> Vector2:
	var total := Vector2.ZERO
	for point in points:
		total += Vector2(point.x, point.y)
	return total / maxf(points.size(), 1)


func mean_formation_radius(points: Array[Vector3]) -> float:
	var centre := formation_centroid(points)
	var total := 0.0
	for point in points:
		total += Vector2(point.x, point.y).distance_to(centre)
	return total / maxf(points.size(), 1)


func minimum_pairwise_distance(points: Array[Vector3]) -> float:
	var minimum := INF
	for first in points.size():
		for second in range(first + 1, points.size()):
			minimum = minf(minimum, Vector2(points[first].x, points[first].y).distance_to(Vector2(points[second].x, points[second].y)))
	return minimum


func cinematic_snapshot(visual: Node, adapter: Node, skeleton: Skeleton3D, drone_bones: Array) -> Dictionary:
	var player := adapter.get("animation_player") as AnimationPlayer
	var positions := drone_positions(skeleton, drone_bones)
	var rotations: Array[Quaternion] = []
	for bone_index in drone_bones:
		rotations.append(skeleton.get_bone_pose_rotation(int(bone_index)))
	return {
		"state": StringName(visual.get("_state")),
		"age": float(visual.get("_cinematic_age")),
		"clip": player.current_animation_position if player != null else -1.0,
		"positions": positions,
		"rotations": rotations,
		"flash": shader_value(adapter, &"flash"),
		"dissolve": shader_value(adapter, &"dissolve"),
	}


func check_same_snapshot(first: Dictionary, second: Dictionary, message: String) -> void:
	check(first.state == second.state, message + " keeps the same action state")
	check(is_equal_approx(first.clip, second.clip), message + " keeps the same clip position")
	check(is_equal_approx(first.flash, second.flash), message + " keeps the same flash")
	check(is_equal_approx(first.dissolve, second.dissolve), message + " keeps the same dissolve")
	var first_positions: Array = first.positions
	var second_positions: Array = second.positions
	var first_rotations: Array = first.rotations
	var second_rotations: Array = second.rotations
	for index in mini(first_positions.size(), second_positions.size()):
		check(first_positions[index].distance_to(second_positions[index]) < 0.0001, message + " keeps drone %d position" % index)
		check(first_rotations[index].is_equal_approx(second_rotations[index]), message + " keeps drone %d rotation" % index)


func compare_cinematic_progress_paths(visual: Node, adapter: Node3D, skeleton: Skeleton3D, drone_bones: Array, mode: StringName, seconds: float) -> void:
	visual.call("on_spawned")
	visual.call("play_cinematic", mode, seconds)
	visual.call("set_cinematic_progress", mode, 0.0)
	visual.call("set_cinematic_progress", mode, 0.6)
	var skipped := cinematic_snapshot(visual, adapter, skeleton, drone_bones)
	visual.call("on_spawned")
	visual.call("play_cinematic", mode, seconds)
	visual.call("set_cinematic_progress", mode, 0.0)
	visual.call("set_cinematic_progress", mode, 0.25)
	visual.call("set_cinematic_progress", mode, 0.6)
	var stepped := cinematic_snapshot(visual, adapter, skeleton, drone_bones)
	check_same_snapshot(skipped, stepped, String(mode) + " direct skip matches sequential progress")
	visual.call("set_time_factor", 0.05)
	visual.call("set_cinematic_progress", mode, 0.6)
	var slow_factor := cinematic_snapshot(visual, adapter, skeleton, drone_bones)
	visual.call("set_time_factor", 1.0)
	visual.call("set_cinematic_progress", mode, 0.6)
	var normal_factor := cinematic_snapshot(visual, adapter, skeleton, drone_bones)
	check_same_snapshot(slow_factor, normal_factor, String(mode) + " progress is independent of time factor")
	var before_process := cinematic_snapshot(visual, adapter, skeleton, drone_bones)
	for delta in [0.01, 0.08, 0.4, 1.0]:
		visual.call("_process", delta)
	var after_process := cinematic_snapshot(visual, adapter, skeleton, drone_bones)
	check_same_snapshot(before_process, after_process, String(mode) + " does not drift during _process")
	visual.call("on_spawned")


func check_model_signature_beats() -> void:
	var instance := make_visual(MODEL_PATH)
	if instance.is_empty():
		return
	var visual := instance.visual as Node
	var skeleton := visual.get("_skeleton") as Skeleton3D
	var drone_bones: Array = visual.get("_drone_bones")
	check(skeleton != null and drone_bones.size() == 6, "model visual exposes all six drone bones for signature checks")
	if skeleton == null or drone_bones.size() != 6:
		instance.anchor.queue_free()
		return
	visual.call("play_telegraph", 0b101, &"orb", 1.0)
	visual.call("_process", 0.2)
	var before_commit := drone_positions(skeleton, drone_bones)
	visual.call("play_commit", 0b100, &"orb", 0.3)
	visual.call("_process", 0.12)
	var committed := drone_positions(skeleton, drone_bones)
	var before_centre := formation_centroid(before_commit)
	var committed_centre := formation_centroid(committed)
	var expected_committed_centroid_x := float(visual.get("_aim")) * 0.08
	for index in 6:
		var rotation := skeleton.get_bone_pose_rotation(int(drone_bones[index]))
		check(rotation.is_equal_approx(Quaternion(Vector3.UP, PI)), "commit turns drone %d to its red failure face" % index)
	check(committed_centre.x > before_centre.x + 0.05, "+2 lane commit moves formation centroid toward positive X")
	check(absf(committed_centre.x - expected_committed_centroid_x) < 0.03, "full commit centers the formation at aim times 0.08")
	check(mean_formation_radius(committed) < mean_formation_radius(before_commit), "committed formation contracts around its spaced lane focus")
	check(minimum_pairwise_distance(committed) >= 0.85, "committed drone centers stay at least 0.85 m apart")
	visual.call("_sample_action")
	visual.call("_apply_formation")
	var fixed_sample_a := drone_positions(skeleton, drone_bones)
	visual.call("_sample_action")
	visual.call("_apply_formation")
	var fixed_sample_b := drone_positions(skeleton, drone_bones)
	for index in 6:
		check(fixed_sample_a[index].distance_to(fixed_sample_b[index]) < 0.0001, "repeated fixed seek does not accumulate drone %d formation offsets" % index)
	visual.call("on_spawned")
	visual.call("play_telegraph", 0b010, &"orb", 0.8)
	visual.set("_state_age", 0.4)
	visual.call("_sample_action")
	visual.call("_apply_formation")
	var orb_spread := average_spread(drone_positions(skeleton, drone_bones))
	visual.call("on_spawned")
	visual.call("play_telegraph", 0b010, &"scatter", 0.8)
	visual.set("_state_age", 0.4)
	visual.call("_sample_action")
	visual.call("_apply_formation")
	var scatter_spread := average_spread(drone_positions(skeleton, drone_bones))
	check(scatter_spread > orb_spread + 0.01, "scatter signature widens the GLB drone formation versus orb at matching progress")
	visual.call("on_spawned")
	visual.call("_process", 0.01)
	var carapace_left := skeleton.find_bone("carapace_L")
	var carapace_right := skeleton.find_bone("carapace_R")
	check(carapace_left >= 0 and carapace_right >= 0, "model exposes persistent phase-split carapace bones")
	if carapace_left >= 0 and carapace_right >= 0:
		var phase_one_left := skeleton.get_bone_pose_position(carapace_left).x
		var phase_one_right := skeleton.get_bone_pose_position(carapace_right).x
		visual.call("set_phase", 3)
		visual.call("_process", 1.21)
		check(is_equal_approx(skeleton.get_bone_pose_position(carapace_left).x - phase_one_left, -0.16), "persistent left carapace split adds 0.08 m per phase")
		check(is_equal_approx(skeleton.get_bone_pose_position(carapace_right).x - phase_one_right, 0.16), "persistent right carapace split adds 0.08 m per phase")
	instance.anchor.queue_free()


func check_signature_contract() -> void:
	check(ProjectileArt.look_for(&"orb", &"flaky_test_swarm") == &"swarm_tile", "flaky signature still selects the stuttering tile projectile")
	check(ProjectileArt.look_for(&"scatter", &"flaky_test_swarm") == &"swarm_scatter", "scatter signature still selects the splitting projectile")
	var looks: Dictionary = ProjectileArt.LOOKS
	check(looks.get(&"swarm_tile", []).has(&"flaky"), "swarm tile keeps the flaky signature key")
	check(looks.get(&"swarm_scatter", []).has(&"scatter"), "swarm scatter keeps the scatter signature key")


func check_loaded_visual() -> void:
	if not FileAccess.file_exists(MODEL_PATH):
		return
	var instance := make_visual(MODEL_PATH)
	if instance.is_empty():
		return
	var visual := instance.visual as Node
	check(visual.process_mode == Node.PROCESS_MODE_PAUSABLE, "model visual remains pausable")
	var adapter := visual.get("_model") as Node3D
	check(adapter != null, "visual uses the imported model adapter")
	check(visual.get("_art") == null, "procedural art stays unused when model loading succeeds")
	if adapter == null:
		instance.anchor.queue_free()
		return
	var player := adapter.get("animation_player") as AnimationPlayer
	check(player != null and player.current_animation == &"idle", "spawn enters the idle model action")
	if player != null:
		var before_pause := player.current_animation_position
		paused = true
		await process_frame
		check(is_equal_approx(player.current_animation_position, before_pause), "pausing the scene tree freezes model animation")
		var state_before_direct_tick: float = visual.get("_state_age")
		visual.call("_process", 0.4)
		check(is_equal_approx(float(visual.get("_state_age")), state_before_direct_tick), "visual process guard freezes a direct tick while the tree is paused")
		paused = false
	visual.call("set_time_factor", 0.5)
	var clock_before: float = visual.get("_state_age")
	visual.call("_process", 0.4)
	var clock_after: float = visual.get("_state_age")
	check(is_equal_approx(clock_after - clock_before, 0.2), "visual state clock advances by delta times its time factor exactly once")
	visual.call("set_time_factor", 1.0)
	visual.call("play_cinematic", &"intro_full", 2.0)
	check(StringName(visual.get("_cinematic_mode")) == &"intro_full", "intro_full cinematic mode starts")
	if player != null:
		check(player.current_animation == &"intro", "intro_full starts the authored intro clip")
	visual.call("set_cinematic_progress", &"intro_full", 0.0)
	visual.call("set_cinematic_progress", &"intro_full", 0.6)
	check(StringName(visual.get("_state")) == &"intro", "intro_full assembles the drones through its first 55 percent")
	visual.call("set_cinematic_progress", &"intro_full", 0.9)
	check(StringName(visual.get("_state")) == &"intro", "intro_full holds its completed intro pose through the final hold")
	visual.call("set_cinematic_progress", &"intro_full", 1.0)
	check(StringName(visual.get("_cinematic_mode")).is_empty() and StringName(visual.get("_state")) == &"intro", "intro_full completes while preserving its final intro pose")
	visual.call("_process", 1.0 / BOUNDS_SAMPLE_RATE)
	check(StringName(visual.get("_state")) == &"idle", "intro_full returns to idle on the next normal process tick")
	visual.call("play_cinematic", &"intro_short", 1.0)
	check(StringName(visual.get("_cinematic_mode")) == &"intro_short", "intro_short cinematic mode starts")
	visual.call("set_cinematic_progress", &"intro_short", 0.0)
	visual.call("set_cinematic_progress", &"intro_short", 0.6)
	visual.call("set_cinematic_progress", &"intro_short", 0.9)
	check(StringName(visual.get("_state")) == &"intro", "intro_short holds its completed intro pose through the final hold")
	visual.call("set_cinematic_progress", &"intro_short", 1.0)
	check(StringName(visual.get("_cinematic_mode")).is_empty() and StringName(visual.get("_state")) == &"intro", "intro_short completes while preserving its final intro pose")
	visual.call("_process", 1.0 / BOUNDS_SAMPLE_RATE)
	check(StringName(visual.get("_state")) == &"idle", "intro_short returns to idle on the next normal process tick")
	visual.call("play_cinematic", &"intro_full", 2.0)
	visual.call("set_cinematic_progress", &"intro_full", 0.2)
	visual.call("play_defeat")
	visual.call("play_cinematic", &"intro_short", 1.0)
	check(bool(visual.get("_terminal")) and StringName(visual.get("_state")) == &"defeat", "death during intro blocks a later intro cinematic from reviving the boss")
	check(StringName(visual.get("_cinematic_mode")).is_empty(), "death during intro clears the active cinematic")
	visual.call("on_spawned")
	check(not bool(visual.get("_terminal")) and player != null and player.current_animation == &"idle", "on_spawned respawns the terminal visual into idle")
	var drone_bones: Array = visual.get("_drone_bones")
	var skeleton := visual.get("_skeleton") as Skeleton3D
	if skeleton != null and drone_bones.size() == 6:
		visual.call("on_spawned")
		visual.call("play_cinematic", &"intro_full", 2.0)
		visual.call("set_cinematic_progress", &"intro_full", 0.62)
		for drone_index in 6:
			var expected_rotation := Quaternion(Vector3.UP, PI) if INTRO_RED_DRONES.has(drone_index) else Quaternion.IDENTITY
			var intro_rotation := skeleton.get_bone_pose_rotation(int(drone_bones[drone_index]))
			check(absf(intro_rotation.dot(expected_rotation)) > 0.999, "intro hold drone %d faces %s" % [drone_index, "red" if INTRO_RED_DRONES.has(drone_index) else "green"])
		compare_cinematic_progress_paths(visual, adapter, skeleton, drone_bones, &"intro_full", 2.0)
		compare_cinematic_progress_paths(visual, adapter, skeleton, drone_bones, &"intro_short", 1.0)
		compare_cinematic_progress_paths(visual, adapter, skeleton, drone_bones, &"defeat_full", 2.0)
		compare_cinematic_progress_paths(visual, adapter, skeleton, drone_bones, &"defeat_short", 1.0)
		check_intro_hold_pose(visual, adapter, skeleton, &"intro_full", 5.0, 0.65)
		check_intro_hold_pose(visual, adapter, skeleton, &"intro_short", 2.5, 0.85)
	for mode in [&"defeat_full", &"defeat_short"]:
		visual.call("on_spawned")
		visual.call("play_cinematic", mode, 2.0)
		check(StringName(visual.get("_cinematic_mode")) == mode, String(mode) + " cinematic mode starts")
		visual.call("set_cinematic_progress", mode, 0.0)
		visual.call("set_cinematic_progress", mode, 0.15)
		check(shader_value(adapter, &"flash") > 0.0, String(mode) + " strobes its flash during the opening quarter")
		check(shader_value(adapter, &"dissolve") <= 0.01, String(mode) + " keeps dissolve off before its final phase")
		visual.call("set_cinematic_progress", mode, 0.25)
		visual.call("set_cinematic_progress", mode, 0.6)
		check(player == null or player.assigned_animation == &"defeat", String(mode) + " enters its authored defeat collapse")
		check(shader_value(adapter, &"dissolve") > 0.0, String(mode) + " begins dissolve in its final phase")
		visual.call("set_cinematic_progress", mode, 0.9)
		check(shader_value(adapter, &"dissolve") < 0.99, String(mode) + " dissolve remains partial at 90 percent")
		visual.call("set_cinematic_progress", mode, 1.0)
		check(StringName(visual.get("_cinematic_mode")).is_empty(), String(mode) + " completes its cinematic sequence")
		check(shader_value(adapter, &"dissolve") >= 0.99, String(mode) + " completes its final dissolve")
	instance.anchor.queue_free()


func check_fallback_visual() -> void:
	var instance := make_visual("res://Assets/runner/bosses/flaky_test_swarm/missing.glb")
	if instance.is_empty():
		return
	var visual := instance.visual as Node
	visual.set("show_name_plate", false)
	visual.call("on_spawned")
	check(visual.get("_model") == null, "missing model path selects procedural fallback")
	var art := visual.get("_art") as Node
	check(art != null, "procedural fallback art is constructed")
	check(int(visual.get("intro_calls")) == 0, "intro counter starts intact on fallback")
	if art != null:
		check(not (art.get("tag") as Label3D).visible, "show_name_plate still controls fallback name plate")
	visual.call("play_telegraph", 0b101, &"orb", 0.8)
	if art != null:
		check(art.get("state") == &"telegraph", "fallback handles the original telegraph beat")
		check(is_equal_approx(float(art.get("aim")), 0.0), "fallback keeps the flaky two-lane aim centered")
	visual.call("play_commit", 0b001, &"orb", 0.3)
	if art != null:
		check(float(art.get("commit_age")) == 0.0, "fallback keeps the flaky commit beat")
	visual.call("play_attack", &"orb")
	if art != null:
		check(art.get("state") == &"attack", "fallback keeps the signature attack beat")
	visual.call("play_intro", 1.2)
	check(int(visual.get("intro_calls")) == 1, "play_intro still increments intro_calls")
	visual.call("on_spawned")
	visual.call("play_cinematic", &"intro_full", 2.0)
	visual.call("set_cinematic_progress", &"intro_full", 0.6)
	if art != null:
		check(art.get("state") == &"intro", "fallback cinematic samples intro progress")
		var intro_pose_age := float(art.get("age"))
		var intro_pose_clock := float(art.get("clock"))
		var intro_pose_transforms := node3d_transform_snapshot(art)
		var intro_hold_end := float(BossVisualBase.INTRO_HOLD_UNTIL[&"intro_full"])
		var intro_hold_probe := 0.65
		visual.call("_process", 0.35)
		check(is_equal_approx(float(art.get("age")), intro_pose_age), "fallback cinematic process does not advance intro age")
		check(is_equal_approx(float(art.get("clock")), intro_pose_clock), "fallback cinematic process does not advance intro clock")
		check_node3d_transforms_match(art, intro_pose_transforms, "fallback intro cinematic process freeze")
		visual.call("set_cinematic_progress", &"intro_full", intro_hold_probe)
		check(is_equal_approx(float(art.get("age")), intro_pose_age), "fallback intro hold keeps the completed pose age")
		check(is_equal_approx(float(art.get("clock")), intro_pose_clock), "fallback intro hold keeps the completed pose clock")
		check_node3d_transforms_match(art, intro_pose_transforms, "fallback intro hold at %.0f percent" % (intro_hold_probe * 100.0))
		visual.call("set_cinematic_progress", &"intro_full", intro_hold_end)
		check_node3d_transforms_match(art, intro_pose_transforms, "fallback intro hold at shared hold end")
		visual.call("set_cinematic_progress", &"intro_full", 1.0)
		check_node3d_transforms_match(art, intro_pose_transforms, "fallback intro hold at cinematic end")
		check(art.get("state") == &"intro", "fallback keeps intro state on the last cinematic frame")
		visual.call("_process", 1.0 / BOUNDS_SAMPLE_RATE)
		check(art.get("state") == &"idle", "fallback enters idle on the next normal process tick")
	visual.call("set_cinematic_progress", &"intro_full", 1.0)
	visual.call("play_cinematic", &"defeat_full", 2.0)
	visual.call("set_cinematic_progress", &"defeat_full", 0.6)
	if art != null:
		check(art.get("state") == &"defeated", "fallback cinematic samples defeat progress")
	visual.call("set_cinematic_progress", &"defeat_full", 1.0)
	instance.anchor.queue_free()


func run() -> void:
	await process_frame
	check(FileAccess.file_exists(MODEL_SCRIPT_PATH), "BossModel loader script exists")
	var report := check_build_report()
	check_signature_contract()
	if FileAccess.file_exists(MODEL_SCRIPT_PATH) and FileAccess.file_exists(MODEL_PATH):
		var model_script: Script = load(MODEL_SCRIPT_PATH)
		var adapter := model_script.call("load_model", MODEL_PATH) as Node3D if model_script != null else null
		check(adapter != null, "full-bake GLB loads through BossModel")
		if adapter != null:
			root.add_child(adapter)
			await process_frame
			check_model(adapter, report)
			await check_animated_drone_socket(adapter)
			adapter.queue_free()
	else:
		check(false, "full-bake GLB exists for runtime model checks")
	await check_loaded_visual()
	if FileAccess.file_exists(MODEL_PATH):
		check_model_signature_beats()
		check_world_pose_envelopes()
	check_fallback_visual()
	finish()


func finish() -> void:
	await process_frame
	_cpu_skin_groups.clear()
	call_deferred("finish_after_cleanup")


func finish_after_cleanup() -> void:
	print("BOSS FLAKY SWARM CHECK: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
