extends SceneTree

const MODEL_SCRIPT_PATH := "res://scenes/runner/boss/hifi/boss_model.gd"
const BossVisualBase = preload("res://scenes/runner/boss/boss_visual_base.gd")
const RunConfigScript = preload("res://scenes/runner/data/run_config.gd")
const VISUAL_SCRIPT_PATH := "res://scenes/runner/boss/visuals/merge_conflict_hydra_visual.gd"
const VISUAL_SCENE_PATH := "res://scenes/runner/boss/visuals/merge_conflict_hydra_visual.tscn"
const GLB_PATH := "res://Assets/runner/bosses/merge_conflict_hydra/merge_conflict_hydra.glb"
const BUILD_PATH := "res://Assets/runner/bosses/merge_conflict_hydra/merge_conflict_hydra.build.json"
const ACTIONS: Array[StringName] = [&"intro", &"idle", &"telegraph", &"attack", &"hurt", &"phase_change", &"defeat", &"retreat"]
const SOCKETS: Array[StringName] = [&"fx_core", &"fx_0", &"fx_1", &"fx_2", &"fx_3", &"fx_4", &"fx_5", &"muzzle_0", &"muzzle_1", &"muzzle_2"]
const MAX_TRIANGLES := 18000
const MAX_BONES := 40
const PROCEDURAL_SIZE := Vector3(6.431928, 3.8582, 1.893)
const BOUNDS_HZ := 120
const MOUNT_Y := 2.6
const MOUNT_Z := -14.0
const HOVER_X_LIMIT := 0.12
const WORLD_MIN := Vector3(-3.5, 1.6, MOUNT_Z - 3.0)
const WORLD_MAX := Vector3(3.5, 6.1, MOUNT_Z + 3.0)

var checks := 0
var failures := 0
var _skinned_points_by_mesh: Dictionary = {}
var _invalid_skin_meshes: Dictionary = {}
var _validated_skin_meshes: Dictionary = {}
var _pose_bounds_summaries: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOSS MERGE CONFLICT HYDRA CHECK: " + message)


func has_shader_param(material: ShaderMaterial, name: StringName) -> bool:
	if material == null or material.shader == null:
		return false
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if StringName(uniform.get("name", "")) == name:
			return true
	return false


func read_build_report() -> Dictionary:
	check(FileAccess.file_exists(BUILD_PATH), "full-bake build report exists")
	if not FileAccess.file_exists(BUILD_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILD_PATH))
	check(parsed is Dictionary, "build report parses as an object")
	if not parsed is Dictionary:
		return {}
	var report: Dictionary = parsed
	check(report.get("quick", true) == false, "asset was produced by a full bake")
	check(int(report.get("kit_revision", 0)) >= 2, "asset uses the kit v2 rest-position ABI")
	check(report.get("rest_position_encoding", "") == "TEXCOORD_1.xy,TEXCOORD_2.x;TEXCOORD_2.y=1",
		"build report declares the kit v2 rest-position attribute encoding")
	check(int(report.get("triangles", MAX_TRIANGLES + 1)) <= MAX_TRIANGLES, "build report triangles <= 18000")
	check(int(report.get("bones", MAX_BONES + 1)) <= MAX_BONES, "build report bones <= 40")
	check(int(report.get("materials", -1)) == 1, "build report has one baked material")
	check(int(report.get("surfaces", -1)) == 1, "build report has one baked surface")
	for action in ACTIONS:
		var actions: Array = report.get("actions", [])
		check(actions.has(String(action)) or actions.has(action), "build report includes action " + String(action))
	for socket_name in SOCKETS:
		var sockets: Array = report.get("sockets", [])
		check(sockets.has(String(socket_name)) or sockets.has(socket_name), "build report includes socket " + String(socket_name))
	return report


func mesh_skeleton_census(model: Node3D) -> Dictionary:
	var triangles := 0
	var surfaces := 0
	var materials: Dictionary = {}
	var bones := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			var material := mesh_instance.mesh.surface_get_material(surface_index)
			if material != null:
				materials[material.get_instance_id()] = true
	for node in model.find_children("*", "Skeleton3D", true, false):
		bones += (node as Skeleton3D).get_bone_count()
	return {"triangles": triangles, "surfaces": surfaces, "materials": materials.size(), "bones": bones}


func check_census(model: Node3D, report: Dictionary) -> void:
	var census := mesh_skeleton_census(model)
	check(census.triangles <= MAX_TRIANGLES, "imported GLB triangle census <= 18000 (%d)" % census.triangles)
	check(census.bones <= MAX_BONES, "imported GLB bone census <= 40 (%d)" % census.bones)
	check(census.materials == 1, "imported GLB has exactly one baked material")
	check(census.surfaces == 1, "imported GLB has exactly one baked surface")
	for key in ["triangles", "bones", "materials", "surfaces"]:
		check(int(report.get(key, -1)) == int(census[key]), "build report %s matches imported census" % key)
	var actual_size := rest_mesh_bounds(model).size
	print("HYDRA REST BOUNDS: actual=%s baseline=%s" % [str(actual_size), str(PROCEDURAL_SIZE)])
	for axis in 3:
		var reference := PROCEDURAL_SIZE[axis]
		check(actual_size[axis] >= reference * 0.8 and actual_size[axis] <= reference * 1.2,
			"rest mesh axis %d stays within 20 percent of procedural baseline (%.3f vs %.3f)" % [axis, actual_size[axis], reference])


func check_rest_position_abi(model: Node3D, model_script: Script) -> void:
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var restored: PackedVector3Array = model_script.call("rest_positions", node.mesh, surface)
			check(restored.size() == vertices.size(), "every imported vertex has valid kit v2 rest xyz and marker")
			var max_error := 0.0
			for index in mini(vertices.size(), restored.size()):
				max_error = maxf(max_error, vertices[index].distance_to(restored[index]))
			check(max_error <= 0.0001, "kit v2 rest coordinates survive import within 0.1 mm")
	var old_mesh := ArrayMesh.new()
	var old_arrays: Array = []
	old_arrays.resize(Mesh.ARRAY_MAX)
	old_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	old_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, old_arrays)
	check(model_script.call("rest_positions", old_mesh, 0).is_empty(), "legacy mesh without kit v2 rest attributes is rejected")


func rest_mesh_bounds(model: Node3D) -> AABB:
	var result := AABB()
	var has_point := false
	var model_from_world := model.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_from_model := model_from_world * mesh_instance.global_transform
		var local_bounds := mesh_instance.mesh.get_aabb()
		for corner in 8:
			var point := mesh_from_model * local_bounds.get_endpoint(corner)
			if not has_point:
				result = AABB(point, Vector3.ZERO)
				has_point = true
			else:
				result = result.expand(point)
	return result


func skinned_point_groups(mesh: Mesh) -> Array[Dictionary]:
	if _skinned_points_by_mesh.has(mesh):
		return _skinned_points_by_mesh[mesh]
	var grouped: Dictionary = {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or bones.is_empty() or weights.is_empty():
			continue
		var stride := bones.size() / vertices.size()
		for vertex_index in vertices.size():
			var ids := PackedInt32Array()
			var gains := PackedFloat32Array()
			for influence in stride:
				var weight := weights[vertex_index * stride + influence]
				if weight <= 0.0:
					continue
				ids.append(bones[vertex_index * stride + influence])
				gains.append(weight)
			var key := var_to_str([ids, gains])
			if not grouped.has(key):
				grouped[key] = {"ids": ids, "gains": gains, "points": {}}
			grouped[key]["points"][vertices[vertex_index]] = true
	var compact: Array[Dictionary] = []
	for group: Dictionary in grouped.values():
		var points := PackedVector3Array(group["points"].keys())
		compact.append({"ids": group["ids"], "gains": group["gains"], "points": points})
	_skinned_points_by_mesh[mesh] = compact
	return compact


func cpu_skinned_mesh_bounds(mesh_instance: MeshInstance3D) -> AABB:
	if mesh_instance.mesh == null:
		return AABB()
	if mesh_instance.skin == null:
		return mesh_instance.global_transform * mesh_instance.get_aabb()
	var skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D
	if skeleton == null:
		return invalid_skin_bounds(mesh_instance, "skinned mesh has no resolved Skeleton3D")
	var mesh_id := mesh_instance.get_instance_id()
	if not _validated_skin_meshes.has(mesh_id):
		_validated_skin_meshes[mesh_id] = true
		var mesh_from_skeleton := skeleton.global_transform.affine_inverse() * mesh_instance.global_transform
		if not mesh_from_skeleton.is_equal_approx(Transform3D.IDENTITY):
			return invalid_skin_bounds(mesh_instance, "skinned mesh transform relative to Skeleton3D is not identity")
	skeleton.force_update_all_bone_transforms()
	var transforms: Array[Transform3D] = []
	for bind in mesh_instance.skin.get_bind_count():
		var bone := skeleton.find_bone(mesh_instance.skin.get_bind_name(bind))
		if bone < 0:
			bone = mesh_instance.skin.get_bind_bone(bind)
		if bone < 0:
			return invalid_skin_bounds(mesh_instance, "skin bind %d (%s) has no skeleton bone" % [bind, mesh_instance.skin.get_bind_name(bind)])
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh_instance.skin.get_bind_pose(bind))
	var result := AABB()
	var first := true
	for group: Dictionary in skinned_point_groups(mesh_instance.mesh):
		var pose := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
		var ids: PackedInt32Array = group["ids"]
		var gains: PackedFloat32Array = group["gains"]
		for influence in ids.size():
			var bone_index := ids[influence]
			if bone_index < 0 or bone_index >= transforms.size():
				return invalid_skin_bounds(mesh_instance, "vertex influence references invalid skin bind %d" % bone_index)
			var part: Transform3D = transforms[bone_index]
			var gain := gains[influence]
			pose.origin += part.origin * gain
			pose.basis.x += part.basis.x * gain
			pose.basis.y += part.basis.y * gain
			pose.basis.z += part.basis.z * gain
		for point: Vector3 in group["points"]:
			var world := pose * point
			result = AABB(world, Vector3.ZERO) if first else result.expand(world)
			first = false
	return result


func invalid_skin_bounds(mesh_instance: MeshInstance3D, reason: String) -> AABB:
	var mesh_id := mesh_instance.get_instance_id()
	if not _invalid_skin_meshes.has(mesh_id):
		_invalid_skin_meshes[mesh_id] = true
		check(false, "CPU skin bounds reject invalid %s: %s" % [mesh_instance.get_path(), reason])
	return AABB()


func cpu_skinned_visual_bounds(visual: Node3D) -> AABB:
	var adapter := visual.get("_model") as Node3D
	if adapter == null:
		return AABB()
	var result := AABB()
	var first := true
	for node in adapter.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_bounds := cpu_skinned_mesh_bounds(mesh_instance)
		for corner in 8:
			var point := mesh_bounds.get_endpoint(corner)
			result = AABB(point, Vector3.ZERO) if first else result.expand(point)
			first = false
	return result


func new_pose_bounds_summary(label: String) -> Dictionary:
	return {
		"label": label,
		"samples": 0,
		"minimum": Vector3(INF, INF, INF),
		"maximum": Vector3(-INF, -INF, -INF),
		"violations": 0,
		"failing_frames": []
	}


func include_pose_bounds_sample(summary: Dictionary, visual: Node3D, frame: int, far_z_exception: bool) -> void:
	var original_position := visual.position
	var hover_x := minf(float(visual.get("sway_amplitude")), HOVER_X_LIMIT)
	var label_parts: Array[String] = []
	var pose_bounds := cpu_skinned_visual_bounds(visual)
	for offset_x in [-hover_x, hover_x]:
		for offset_y in [0.0, 0.08]:
			var translation := Vector3(offset_x - original_position.x, offset_y - original_position.y, 0.0)
			var bounds := AABB(pose_bounds.position + translation, pose_bounds.size)
			summary["samples"] = int(summary["samples"]) + 1
			var minimum: Vector3 = summary["minimum"]
			var maximum: Vector3 = summary["maximum"]
			minimum.x = minf(minimum.x, bounds.position.x)
			minimum.y = minf(minimum.y, bounds.position.y)
			minimum.z = minf(minimum.z, bounds.position.z)
			maximum.x = maxf(maximum.x, bounds.end.x)
			maximum.y = maxf(maximum.y, bounds.end.y)
			maximum.z = maxf(maximum.z, bounds.end.z)
			summary["minimum"] = minimum
			summary["maximum"] = maximum
			var hover_z := float(visual.get("hover_z"))
			var problems: Array[String] = []
			if bounds.position.x < WORLD_MIN.x or bounds.end.x > WORLD_MAX.x:
				problems.append("x[%.3f,%.3f]" % [bounds.position.x, bounds.end.x])
			if bounds.position.y < WORLD_MIN.y or bounds.end.y > WORLD_MAX.y:
				problems.append("y[%.3f,%.3f]" % [bounds.position.y, bounds.end.y])
			if not far_z_exception and bounds.size.z > 3.0:
				problems.append("depth %.3f > 3.000" % bounds.size.z)
			if bounds.end.z > hover_z + 3.0:
				problems.append("zmax %.3f > %.3f" % [bounds.end.z, hover_z + 3.0])
			if not far_z_exception and bounds.position.z < hover_z - 3.0:
				problems.append("zmin %.3f < %.3f" % [bounds.position.z, hover_z - 3.0])
			if not problems.is_empty():
				summary["violations"] = int(summary["violations"]) + 1
				if label_parts.size() < 8:
					label_parts.append("f%d x=%.2f y=%.2f %s" % [frame, offset_x, offset_y, ",".join(problems)])
	if not label_parts.is_empty():
		var failing_frames: Array[String] = summary["failing_frames"]
		if failing_frames.size() < 12:
			failing_frames.append_array(label_parts)
			summary["failing_frames"] = failing_frames


func finish_pose_bounds_summary(summary: Dictionary) -> void:
	var label := String(summary["label"])
	var minimum: Vector3 = summary["minimum"]
	var maximum: Vector3 = summary["maximum"]
	var violation_count := int(summary["violations"])
	var failures_text := ""
	if violation_count > 0:
		failures_text = " failing=" + str(summary["failing_frames"])
	check(violation_count == 0,
		"%s stays inside world envelope, violations=%d%s" % [label, violation_count, failures_text])
	print("HYDRA POSE BOUNDS: %s samples=%d world_min=%s world_max=%s violations=%d%s" % [
		label, int(summary["samples"]), str(minimum), str(maximum), violation_count, failures_text
	])
	_pose_bounds_summaries.append(summary)


func sample_pose_sequence(visual: Node3D, label: String, frame_count: int, far_z_exception: bool = false) -> void:
	var summary := new_pose_bounds_summary(label)
	for frame in frame_count + 1:
		include_pose_bounds_sample(summary, visual, frame, far_z_exception)
		if frame < frame_count:
			visual.call("_process", 1.0 / float(BOUNDS_HZ))
	finish_pose_bounds_summary(summary)


func sample_cinematic_pose_sequence(visual: Node3D, mode: StringName, seconds: float, label: String) -> void:
	visual.call("play_cinematic", mode, seconds)
	var frames := maxi(1, roundi(seconds * BOUNDS_HZ))
	var summary := new_pose_bounds_summary(label)
	for frame in frames + 1:
		var progress := float(frame) / float(frames)
		visual.call("set_cinematic_progress", mode, progress)
		include_pose_bounds_sample(summary, visual, frame, mode == &"intro_full" or mode == &"intro_short")
	finish_pose_bounds_summary(summary)


func cinematic_default_seconds(mode: StringName) -> float:
	var config: Resource = RunConfigScript.new()
	match mode:
		&"intro_full": return float(config.get("boss_intro_seconds"))
		&"intro_short": return minf(float(config.get("boss_intro_short_seconds")), float(config.get("boss_intro_seconds")))
		&"defeat_full": return float(config.get("boss_defeat_seconds"))
		&"defeat_short": return minf(float(config.get("boss_defeat_short_seconds")), float(config.get("boss_defeat_seconds")))
	return 0.0


func reset_bounds_fixture(visual: Node3D, phase: int) -> void:
	visual.call("on_spawned")
	if phase >= 2:
		visual.call("set_phase", 2)
		visual.set("_sprout_age", 1.3)
		visual.call("_process", 0.0)
	if phase >= 3:
		visual.call("set_phase", 3)
		visual.call("_process", 0.0)
	visual.call("_action", &"idle")
	visual.set("_clock", 0.0)
	visual.set("_age", 0.0)
	visual.call("_process", 0.0)


func sample_bounds_action_suite(visual: Node3D, phase: int) -> void:
	var prefix := "phase%d" % phase
	var adapter := visual.get("_model") as Node3D
	var animation_player := adapter.get("animation_player") as AnimationPlayer if adapter != null else null
	if animation_player == null:
		check(false, prefix + " bounds suite has an AnimationPlayer")
		return
	var intro_length := animation_player.get_animation(&"intro").length
	reset_bounds_fixture(visual, phase)
	visual.call("play_intro", intro_length)
	sample_pose_sequence(visual, prefix + "/intro", roundi(intro_length * BOUNDS_HZ), true)
	reset_bounds_fixture(visual, phase)
	var idle_length := animation_player.get_animation(&"idle").length
	sample_pose_sequence(visual, prefix + "/idle-full-period", roundi(idle_length * BOUNDS_HZ))
	reset_bounds_fixture(visual, phase)
	visual.call("play_telegraph", 0b111, &"default", 0.8)
	visual.call("_process", 0.0)
	sample_pose_sequence(visual, prefix + "/telegraph", roundi(0.8 * BOUNDS_HZ))
	reset_bounds_fixture(visual, phase)
	visual.call("play_telegraph", 0b111, &"default", 0.05)
	visual.call("_process", 0.0)
	visual.call("play_attack", &"default")
	visual.call("_process", 0.0)
	sample_pose_sequence(visual, prefix + "/attack-and-delayed-recoil-tail", roundi(0.64 * BOUNDS_HZ))
	reset_bounds_fixture(visual, phase)
	if phase >= 2:
		visual.call("play_telegraph", 0b110, &"force_push", 0.8)
	else:
		visual.call("play_telegraph", 0b010, &"default", 0.8)
	visual.call("_process", 0.0)
	visual.call("play_attack", &"force_push" if phase >= 2 else &"default")
	visual.call("_process", 0.0)
	visual.call("play_hit", &"test_tool", 1)
	visual.call("_process", 0.0)
	sample_pose_sequence(visual, prefix + "/hurt", roundi(0.35 * BOUNDS_HZ))
	reset_bounds_fixture(visual, phase)
	visual.call("play_telegraph", 0b111, &"default", 0.8)
	visual.call("_process", 0.0)
	sample_pose_sequence(visual, prefix + "/mid-telegraph-hit/telegraph", roundi(0.4 * BOUNDS_HZ))
	visual.call("play_hit", &"test_tool", 1)
	visual.call("_process", 0.0)
	sample_pose_sequence(visual, prefix + "/mid-telegraph-hit/hurt", roundi(0.35 * BOUNDS_HZ))
	for lane in [0, 2]:
		reset_bounds_fixture(visual, phase)
		visual.call("play_telegraph", 1 << lane, &"default", 0.05)
		visual.call("_process", 0.0)
		visual.call("play_attack", &"default")
		visual.call("_process", 0.0)
		visual.call("play_hit", &"test_tool", 1)
		visual.call("_process", 0.0)
		sample_pose_sequence(visual, prefix + "/outer-lane-%d-hurt" % lane, roundi(0.35 * BOUNDS_HZ))
	reset_bounds_fixture(visual, phase)
	visual.call("play_defeat")
	sample_pose_sequence(visual, prefix + "/defeat", roundi(float(visual.get("_duration")) * BOUNDS_HZ))
	reset_bounds_fixture(visual, phase)
	visual.call("play_retreat")
	sample_pose_sequence(visual, prefix + "/retreat", roundi(float(visual.get("_duration")) * BOUNDS_HZ))
	for mode in [&"intro_full", &"intro_short", &"defeat_full", &"defeat_short"]:
		reset_bounds_fixture(visual, phase)
		var seconds := cinematic_default_seconds(mode)
		sample_cinematic_pose_sequence(visual, mode, seconds, prefix + "/" + String(mode))
	if phase >= 2:
		for pair in [{"mask": 0b011, "name": "left-centre"}, {"mask": 0b110, "name": "centre-right"}]:
			reset_bounds_fixture(visual, phase)
			visual.call("play_telegraph", int(pair["mask"]), &"force_push", 0.8)
			visual.call("_process", 0.0)
			sample_pose_sequence(visual, prefix + "/force_push_" + String(pair["name"]) + "_telegraph", roundi(0.8 * BOUNDS_HZ))
			visual.call("play_attack", &"force_push")
			visual.call("_process", 0.0)
			sample_pose_sequence(visual, prefix + "/force_push_" + String(pair["name"]) + "_attack", roundi(0.5 * BOUNDS_HZ))


func check_phase_one_identity_and_lane_reset(visual: Node3D) -> void:
	reset_bounds_fixture(visual, 1)
	visual.call("set_phase", 2)
	visual.call("_process", 1.3)
	visual.call("set_phase", 3)
	visual.call("_process", 1.2)
	visual.call("_action", &"idle")
	visual.call("_process", 0.0)
	var model := visual.get("_model") as Node3D
	var skeleton := visual.get("_skeleton") as Skeleton3D
	var fourth_bone := int(visual.get("_fourth_bone"))
	var phase3_composed := (
		model != null
		and is_equal_approx(model.position.y, -0.30)
		and is_equal_approx(model.scale.y, 0.95)
	)
	check(phase3_composed, "respawn fixture starts with the phase-three model drop and compression")
	check(skeleton != null and fourth_bone >= 0 and skeleton.get_bone_pose_scale(fourth_bone).is_equal_approx(Vector3.ONE),
		"respawn fixture starts with the grown crown")
	visual.call("play_telegraph", 0b110, &"force_push", 0.8)
	visual.call("_process", 0.1)
	visual.call("play_telegraph", 0b011, &"force_push", 0.8)
	visual.call("_process", 0.1)
	visual.call("play_attack", &"force_push")
	visual.call("_process", 0.1)
	var active_heads: Array = visual.get("_head_state")
	var pending_queue: PackedInt32Array = visual.get("_queue_mask")
	var active_overlay := false
	for state: StringName in active_heads:
		active_overlay = active_overlay or not state.is_empty()
	var queued_attack := false
	for mask in pending_queue:
		queued_attack = queued_attack or mask != 0
	check(active_overlay and queued_attack, "respawn fixture has an active force-push overlay and pending queued lanes")
	visual.call("on_spawned")
	var head_state: Array = visual.get("_head_state")
	var head_recoil: PackedFloat32Array = visual.get("_head_recoil")
	var queue_mask: PackedInt32Array = visual.get("_queue_mask")
	var lanes_clear := head_state.size() == 4 and head_recoil.size() == 4 and queue_mask.size() == 6
	for lane in mini(head_state.size(), 4):
		lanes_clear = lanes_clear and StringName(head_state[lane]).is_empty() and is_equal_approx(head_recoil[lane], 9.0)
	for slot in queue_mask.size():
		lanes_clear = lanes_clear and queue_mask[slot] == 0
	check(lanes_clear and int(visual.get("_phase")) == 1,
		"phase-three spawn reset clears every overlay, recoil timer and queued action")
	visual.call("_process", 0.0)
	model = visual.get("_model") as Node3D
	skeleton = visual.get("_skeleton") as Skeleton3D
	fourth_bone = int(visual.get("_fourth_bone"))
	check(model != null and is_zero_approx(model.position.y) and model.scale.is_equal_approx(Vector3.ONE),
		"respawn after phase three restores model position and scale to identity")
	check(skeleton != null and fourth_bone >= 0 and skeleton.get_bone_pose_scale(fourth_bone).is_equal_approx(Vector3.ONE * 0.001),
		"respawn after phase three restores the crown gate to 0.001")


func snapshot_skeleton_pose(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		result.append(skeleton.get_bone_pose(bone))
	return result


func skeleton_pose_matches(skeleton: Skeleton3D, snapshot: Array[Transform3D]) -> bool:
	if skeleton.get_bone_count() != snapshot.size():
		return false
	for bone in snapshot.size():
		if not skeleton.get_bone_pose(bone).is_equal_approx(snapshot[bone]):
			return false
	return true


func check_sprout_interrupt_hitstop(visual: Node3D) -> void:
	reset_bounds_fixture(visual, 1)
	visual.call("set_phase", 2)
	visual.call("_process", 0.4)
	var adapter := visual.get("_model") as Node3D
	var skeleton := visual.get("_skeleton") as Skeleton3D
	check(adapter != null and skeleton != null and float(visual.get("_sprout_age")) < 0.94,
		"hit-stop fixture interrupts crown sprout before growth completes")
	visual.call("play_cinematic", &"defeat_full", 2.4)
	visual.call("set_time_factor", 0.05)
	var adapter_pose: Transform3D = adapter.transform if adapter != null else Transform3D.IDENTITY
	var bones := snapshot_skeleton_pose(skeleton) if skeleton != null else []
	var summary := new_pose_bounds_summary("phase2/sprout-interrupted-defeat-hitstop")
	for frame in 4:
		var progress := float(frame) * 0.01
		visual.call("_process", 1.0 / float(BOUNDS_HZ))
		visual.call("set_cinematic_progress", &"defeat_full", progress)
		include_pose_bounds_sample(summary, visual, frame, false)
		var held := adapter != null and adapter.transform.is_equal_approx(adapter_pose)
		if skeleton != null:
			held = held and skeleton_pose_matches(skeleton, bones)
		check(held, "whole model holds its sprout pose during defeat hit-stop at progress %.2f" % progress)
	finish_pose_bounds_summary(summary)


func install_pristine_authored_adapter(visual: Node3D, model_script: Script) -> bool:
	var previous := visual.get("_model") as Node3D
	if previous != null:
		visual.remove_child(previous)
		previous.free()
	var adapter: Variant = model_script.call("load_model", GLB_PATH)
	if not adapter is Node3D:
		check(false, "pristine authored-animation adapter loads from GLB")
		return false
	visual.add_child(adapter)
	visual.set("_model", adapter)
	var skeletons: Array = adapter.model.find_children("*", "Skeleton3D", true, false)
	check(skeletons.size() == 1, "pristine authored adapter contains exactly one skeleton")
	if skeletons.size() != 1:
		return false
	visual.set("_skeleton", skeletons[0])
	visual.set("_fourth_bone", (skeletons[0] as Skeleton3D).find_bone("branch_3"))
	return true


func check_pristine_authored_clip_bounds(visual: Node3D) -> void:
	var model_script := load(MODEL_SCRIPT_PATH) as Script
	check(model_script != null, "authored-animation scan loads BossModel script")
	if model_script == null:
		return
	for phase in [1, 2, 3]:
		if not install_pristine_authored_adapter(visual, model_script):
			return
		visual.set("_phase", phase)
		visual.set("_sprout_age", 1.3 if phase >= 2 else 9.0)
		visual.set("_cinematic_mode", &"")
		visual.set("_state", &"idle")
		var adapter := visual.get("_model") as Node3D
		var skeleton := visual.get("_skeleton") as Skeleton3D
		var player := adapter.get("animation_player") as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.playback_default_blend_time = 0.0
		for action in ACTIONS:
			var clip := player.get_animation(action)
			var frames := maxi(1, ceili(clip.length * BOUNDS_HZ))
			var summary := new_pose_bounds_summary("authored-phase%d/%s" % [phase, String(action)])
			skeleton.reset_bone_poses()
			adapter.position = Vector3.ZERO
			adapter.scale = Vector3.ONE
			player.play(action, 0.0)
			for frame in frames + 1:
				var time := minf(float(frame) / float(BOUNDS_HZ), clip.length)
				player.seek(time, true)
				visual.call("_apply_fourth")
				include_pose_bounds_sample(summary, visual, frame, action == &"intro")
			finish_pose_bounds_summary(summary)


func check_every_frame_pose_bounds() -> void:
	_pose_bounds_summaries.clear()
	var packed := load(VISUAL_SCENE_PATH) as PackedScene
	check(packed != null, "every-frame bounds fixture loads Hydra visual scene")
	if packed == null:
		return
	var mount := Node3D.new()
	mount.name = "HydraBoundsMount"
	mount.position = Vector3(0.0, MOUNT_Y, MOUNT_Z)
	root.add_child(mount)
	var visual := packed.instantiate() as Node3D
	check(visual != null, "every-frame bounds fixture instantiates visual")
	if visual == null:
		mount.free()
		return
	visual.set("hover_z", MOUNT_Z)
	visual.set("sway_amplitude", 2.4)
	visual.set("sway_period", 3.2)
	mount.add_child(visual)
	visual.call("on_spawned")
	check(int(visual.get("phase_count")) == 3, "bounds fixture exercises the Hydra three-phase contract")
	check_phase_one_identity_and_lane_reset(visual)
	for phase in [1, 2, 3]:
		if phase == 2:
			reset_bounds_fixture(visual, 1)
			visual.call("set_phase", 2)
			sample_pose_sequence(visual, "phase1-to-2/phase_change", roundi(1.2 * BOUNDS_HZ))
		elif phase == 3:
			reset_bounds_fixture(visual, 2)
			visual.call("set_phase", 3)
			sample_pose_sequence(visual, "phase2-to-3/phase_change", roundi(1.2 * BOUNDS_HZ))
		sample_bounds_action_suite(visual, phase)
	check_sprout_interrupt_hitstop(visual)
	check_pristine_authored_clip_bounds(visual)
	var overall_minimum := Vector3(INF, INF, INF)
	var overall_maximum := Vector3(-INF, -INF, -INF)
	var aggregate_violations := 0
	for summary: Dictionary in _pose_bounds_summaries:
		var minimum: Vector3 = summary["minimum"]
		var maximum: Vector3 = summary["maximum"]
		overall_minimum.x = minf(overall_minimum.x, minimum.x)
		overall_minimum.y = minf(overall_minimum.y, minimum.y)
		overall_minimum.z = minf(overall_minimum.z, minimum.z)
		overall_maximum.x = maxf(overall_maximum.x, maximum.x)
		overall_maximum.y = maxf(overall_maximum.y, maximum.y)
		overall_maximum.z = maxf(overall_maximum.z, maximum.z)
		aggregate_violations += int(summary["violations"])
	print("HYDRA POSE ENVELOPE: phases=1,2,3 hz=%d aggregate_world_min=%s aggregate_world_max=%s sequences=%d violations=%d" % [
		BOUNDS_HZ, str(overall_minimum), str(overall_maximum), _pose_bounds_summaries.size(), aggregate_violations
	])
	mount.free()


func check_model_adapter(model_script: Script, report: Dictionary) -> Node3D:
	check(FileAccess.file_exists(GLB_PATH), "Hydra GLB exists")
	check(FileAccess.file_exists(MODEL_SCRIPT_PATH), "BossModel adapter script exists")
	if not FileAccess.file_exists(GLB_PATH) or model_script == null:
		return null
	var instance: Variant = model_script.call("load_model", GLB_PATH)
	check(instance is Node3D, "GLB loads through BossModel")
	if not instance is Node3D:
		return null
	root.add_child(instance)
	var model := instance.get("model") as Node3D
	check(model != null, "adapter exposes imported model")
	if model == null:
		instance.free()
		return null
	await process_frame
	check_census(model, report)
	check_rest_position_abi(model, model_script)
	var animation_player := instance.get("animation_player") as AnimationPlayer
	check(animation_player != null, "adapter exposes AnimationPlayer")
	if animation_player != null:
		for action in ACTIONS:
			check(animation_player.has_animation(action), "runtime action exists: " + String(action))
		var idle: Animation = animation_player.get_animation(&"idle") if animation_player.has_animation(&"idle") else null
		check(idle != null and idle.loop_mode != Animation.LOOP_NONE, "idle action loops")
	var muzzle_xs := PackedFloat32Array()
	for socket_name in SOCKETS:
		var socket := instance.call("socket", socket_name) as Node3D
		check(socket != null, "adapter resolves socket " + String(socket_name))
		if socket != null and String(socket_name).begins_with("muzzle_"):
			var lane := int(String(socket_name).trim_prefix("muzzle_"))
			var expected_x := float((lane - 1) * 2)
			muzzle_xs.append(socket.global_position.x)
			check(absf(socket.global_position.x - expected_x) < 0.5,
				"%s socket stays near lane x=%.0f (actual %.3f)" % [String(socket_name), expected_x, socket.global_position.x])
	print("HYDRA MUZZLE X: %s expected=(-2, 0, 2)" % str(muzzle_xs))
	check(instance.has_method("set_time_factor"), "adapter exposes set_time_factor")
	if instance.has_method("set_time_factor") and animation_player != null:
		instance.call("set_time_factor", 0.25)
		check(is_equal_approx(animation_player.speed_scale, 0.25), "adapter forwards time factor to animation player")
		instance.call("set_time_factor", 1.0)
	var materials: Array = instance.get("materials")
	check(materials.size() == 1, "adapter creates one per-instance shader material")
	for material: Variant in materials:
		check(material is ShaderMaterial, "rebuilt model material is a ShaderMaterial")
		if material is ShaderMaterial:
			for parameter in [&"dissolve", &"flash", &"phase_tint"]:
				check(has_shader_param(material, parameter), "boss shader declares " + String(parameter))
	return instance


func check_material_isolation(model_script: Script) -> void:
	var first: Variant = model_script.call("load_model", GLB_PATH)
	var second: Variant = model_script.call("load_model", GLB_PATH)
	check(first is Node3D and second is Node3D, "two model instances load for shader isolation")
	if not first is Node3D or not second is Node3D:
		if first is Node3D: first.free()
		if second is Node3D: second.free()
		return
	root.add_child(first)
	root.add_child(second)
	var first_materials: Array = first.get("materials")
	var second_materials: Array = second.get("materials")
	check(first_materials.size() == 1 and second_materials.size() == 1, "each instance has one mutable shader material")
	if first_materials.size() == 1 and second_materials.size() == 1 and first_materials[0] is ShaderMaterial and second_materials[0] is ShaderMaterial:
		var first_material := first_materials[0] as ShaderMaterial
		var second_material := second_materials[0] as ShaderMaterial
		check(first_material != second_material, "shader material is unique per model instance")
		first.call("set_flash", 0.37)
		check(not is_equal_approx(float(second_material.get_shader_parameter(&"flash")), 0.37), "flash mutation does not leak to peer instance")
		first.call("set_dissolve", 0.42)
		check(not is_equal_approx(float(second_material.get_shader_parameter(&"dissolve")), 0.42), "dissolve mutation does not leak to peer instance")
		var tint := Color(0.2, 0.6, 0.9, 1.0)
		first.call("set_phase_tint", tint)
		check(not second_material.get_shader_parameter(&"phase_tint").is_equal_approx(tint), "phase tint mutation does not leak to peer instance")
	first.free()
	second.free()


func run() -> void:
	await process_frame
	check(FileAccess.file_exists(VISUAL_SCRIPT_PATH), "Hydra visual script exists")
	check(FileAccess.file_exists(VISUAL_SCENE_PATH), "Hydra visual scene exists")
	var report := read_build_report()
	check(FileAccess.file_exists(MODEL_SCRIPT_PATH), "BossModel script exists")
	if not FileAccess.file_exists(MODEL_SCRIPT_PATH):
		finish()
		return
	var model_script := load(MODEL_SCRIPT_PATH) as Script
	check(model_script != null, "BossModel script loads")
	var adapter: Node3D = null
	if model_script != null:
		adapter = await check_model_adapter(model_script, report)
		check_material_isolation(model_script)
		if adapter != null:
			adapter.free()
	if FileAccess.file_exists(VISUAL_SCENE_PATH):
		await check_visual_runtime()
		check_every_frame_pose_bounds()
		check_head_overlay_isolation()
		check_crown_lane_targeting()
		check_missing_model_fallback()
		await check_defeat_remnant_render()
	finish()


func check_visual_runtime() -> void:
	var packed := load(VISUAL_SCENE_PATH) as PackedScene
	check(packed != null, "Hydra visual PackedScene loads")
	if packed == null:
		return
	var visual := packed.instantiate() as Node3D
	check(visual != null, "Hydra visual scene instantiates")
	if visual == null:
		return
	root.add_child(visual)
	visual.call("on_spawned")
	check(visual.get("_model") is Node3D, "visual mounts BossModel adapter without fallback art")
	check(visual.process_mode == Node.PROCESS_MODE_PAUSABLE, "visual uses pausable process mode")
	check(visual.has_method("play_cinematic"), "visual exposes cinematic intro and defeat hook")
	check(visual.has_method("set_time_factor"), "visual exposes time-factor hook")
	check(visual.has_method("set_cinematic_progress"), "visual exposes externally supplied cinematic progress")
	var skeleton := visual.get("_skeleton") as Skeleton3D
	check(skeleton != null, "visual retains Hydra skeleton reference")
	if skeleton != null:
		var fourth_index := skeleton.find_bone("branch_3")
		check(fourth_index >= 0, "skeleton contains phase-two fourth-head branch bone")
		if fourth_index >= 0:
			var fourth_rest_scale := skeleton.get_bone_pose_scale(fourth_index)
			check(fourth_rest_scale.length() < 0.01, "fourth head begins hidden before phase two")
			visual.call("set_phase", 2)
			visual.call("_process", 0.8)
			var fourth_phase2_scale := skeleton.get_bone_pose_scale(fourth_index)
			check(fourth_phase2_scale.length() > 0.1, "phase two reveals fourth head")
			visual.call("play_hit", &"test_tool", 1)
			visual.call("_process", 0.2)
			check(skeleton.get_bone_pose_scale(fourth_index).length() > 0.1, "fourth head stays visible during later hurt action")
	check_lane_queues(visual)
	await check_cinematics_and_time(visual)
	visual.free()


func check_lane_queues(visual: Node3D) -> void:
	var recoil: PackedFloat32Array = visual.get("_head_recoil")
	check(recoil.size() == 4, "visual tracks recoil independently for four heads")
	if recoil.size() != 4:
		return
	visual.call("play_telegraph", 0b101, &"default", 0.0)
	visual.call("_process", 0.0)
	visual.call("play_attack", &"default")
	recoil = visual.get("_head_recoil")
	check(recoil[0] != 9.0 and recoil[2] != 9.0, "left and right lane attacks recoil their own heads")
	check(recoil[1] == 9.0 and recoil[3] == 9.0, "unselected lane heads keep inactive recoil state")
	visual.call("play_telegraph", 0b010, &"default", 0.0)
	visual.call("_process", 0.0)
	visual.call("play_attack", &"default")
	recoil = visual.get("_head_recoil")
	check(recoil[1] != 9.0, "center lane attack selects the center head")
	check(recoil[0] != 9.0 and recoil[2] != 9.0, "independent prior lane recoils remain active")


func intro_glb_pose_matches(visual: Node3D, bones: Array[Transform3D], model_pose: Transform3D, visual_pose: Transform3D, animation_position: float) -> bool:
	var skeleton := visual.get("_skeleton") as Skeleton3D
	var model := visual.get("_model") as Node3D
	var player := model.get("animation_player") as AnimationPlayer if model != null else null
	return (
		skeleton != null
		and model != null
		and player != null
		and skeleton_pose_matches(skeleton, bones)
		and model.transform.is_equal_approx(model_pose)
		and visual.transform.is_equal_approx(visual_pose)
		and is_equal_approx(player.current_animation_position, animation_position)
	)


func check_intro_pose_hold_glb(visual: Node3D, mode: StringName, seconds: float, held_progress: float) -> void:
	visual.call("on_spawned")
	visual.call("set_time_factor", 1.0)
	visual.call("play_cinematic", mode, seconds)
	var intro_pose_at := float(BossVisualBase.INTRO_POSE_AT[mode])
	var seconds_per_frame := 1.0 / (seconds * float(BOUNDS_HZ))
	var pose_frame := roundi(intro_pose_at / seconds_per_frame)
	var before_pose_progress := float(pose_frame - 1) * seconds_per_frame
	visual.call("set_cinematic_progress", mode, before_pose_progress)
	var model := visual.get("_model") as Node3D
	var player := model.get("animation_player") as AnimationPlayer if model != null else null
	var clip := player.get_animation(&"intro") as Animation if player != null else null
	check(player != null and clip != null and player.current_animation_position < clip.length - 0.0001,
		"%s intro has not landed one 120Hz frame before INTRO_POSE_AT" % mode)
	visual.call("set_cinematic_progress", mode, intro_pose_at)
	var skeleton := visual.get("_skeleton") as Skeleton3D
	model = visual.get("_model") as Node3D
	player = model.get("animation_player") as AnimationPlayer if model != null else null
	check(skeleton != null and model != null and player != null and clip != null,
		"%s intro hold fixture exposes GLB skeleton, adapter and player" % mode)
	if skeleton == null or model == null or player == null or clip == null:
		return
	var bones := snapshot_skeleton_pose(skeleton)
	var model_pose := model.transform
	var visual_pose := visual.transform
	var animation_position := player.current_animation_position
	var was_paused := paused
	paused = true
	await process_frame
	check(intro_glb_pose_matches(visual, bones, model_pose, visual_pose, animation_position),
		"%s intro pose holds at INTRO_POSE_AT during pause without new progress" % mode)
	paused = was_paused
	var hold_frame_count := roundi((held_progress - intro_pose_at) / seconds_per_frame)
	var held_through_interval := true
	for frame in hold_frame_count:
		visual.call("_process", 1.0 / float(BOUNDS_HZ))
		var progress := intro_pose_at + float(frame + 1) * seconds_per_frame
		visual.call("set_cinematic_progress", mode, minf(progress, held_progress))
		if not intro_glb_pose_matches(visual, bones, model_pose, visual_pose, animation_position):
			held_through_interval = false
	check(held_through_interval,
		"%s intro keeps every bone and model transform unchanged at time_factor 1 from INTRO_POSE_AT %.2f through %.2f" % [mode, intro_pose_at, held_progress])


func check_cinematics_and_time(visual: Node3D) -> void:
	visual.call("set_time_factor", 0.5)
	visual.call("play_cinematic", &"intro_full", 2.0)
	check(StringName(visual.get("_cinematic_mode")) == &"intro_full", "full intro mode is retained")
	check(is_equal_approx(float(visual.get("_cinematic_seconds")), 2.0), "full intro retains requested duration")
	visual.call("set_cinematic_progress", &"intro_full", 0.4)
	var supplied_age := float(visual.get("_cinematic_age"))
	check(is_equal_approx(supplied_age, 0.8), "intro progress maps directly to its requested duration")
	var model: Node3D = visual.get("_model")
	var animation_player: AnimationPlayer = model.get("animation_player") if model != null else null
	var intro_clip: Animation = animation_player.get_animation(&"intro") if animation_player != null else null
	check(animation_player != null and intro_clip != null, "intro cinematic has a loaded animation clip")
	if animation_player != null and intro_clip != null:
		visual.call("set_cinematic_progress", &"intro_full", 0.8)
		var held_intro_position := animation_player.current_animation_position
		check(is_equal_approx(held_intro_position, intro_clip.length), "intro progress enters and holds its final pose")
		var skeleton := visual.get("_skeleton") as Skeleton3D
		if skeleton != null:
			for head in 3:
				var jaw_index := skeleton.find_bone("jaw_%d" % head)
				check(jaw_index >= 0, "intro hold jaw bone exists for head %d" % head)
				if jaw_index >= 0:
					var jaw_angle := skeleton.get_bone_pose_rotation(jaw_index).get_euler().x
					check(absf(wrapf(jaw_angle - 0.7, -PI, PI)) < 0.15,
						"sampled intro hold keeps head %d jaw open near 0.7 rad (%.3f)" % [head, jaw_angle])
		visual.call("set_cinematic_progress", &"intro_full", 0.95)
		check(is_equal_approx(animation_player.current_animation_position, held_intro_position), "intro final pose stays held through the title tail")
	visual.call("_process", 0.5)
	check(is_equal_approx(float(visual.get("_cinematic_age")), 1.9), "ordinary process delta does not advance externally driven cinematic progress")
	visual.call("set_time_factor", 0.0)
	visual.call("set_cinematic_progress", &"intro_full", 1.0)
	check(StringName(visual.get("_cinematic_mode")) == &"" and StringName(visual.get("_state")) == &"idle",
		"externally supplied skip reaches intro completion even at zero time factor")
	visual.call("set_time_factor", 0.5)
	visual.call("play_intro", 1.0)
	var standalone_age := float(visual.get("_age"))
	visual.call("_process", 0.2)
	check(StringName(visual.get("_cinematic_mode")) == &"" and is_equal_approx(float(visual.get("_age")) - standalone_age, 0.1),
		"standalone play_intro keeps its visual-clock timing")
	visual.call("play_cinematic", &"intro_full", 2.0)
	visual.call("set_cinematic_progress", &"intro_full", 0.4)
	var frozen_age := float(visual.get("_cinematic_age"))
	var held_pause_pose: Transform3D = (visual.get("_skeleton") as Skeleton3D).get_bone_pose(0)
	var was_paused := paused
	paused = true
	await process_frame
	check(is_equal_approx(float(visual.get("_cinematic_age")), frozen_age), "tree pause freezes cinematic state")
	check((visual.get("_skeleton") as Skeleton3D).get_bone_pose(0).is_equal_approx(held_pause_pose), "pause without new progress preserves sampled pose")
	paused = was_paused
	visual.call("play_cinematic", &"defeat_short", 1.2)
	visual.call("set_cinematic_progress", &"defeat_short", 0.3)
	check(StringName(visual.get("_cinematic_mode")) == &"defeat_short", "short defeat mode is retained")
	check(is_equal_approx(float(visual.get("_cinematic_age")), 0.36), "short defeat progress maps to compressed duration")
	visual.call("play_cinematic", &"defeat_full", 4.0)
	var skeleton := visual.get("_skeleton") as Skeleton3D
	var defeat_pose: Array = visual.get("_defeat_pose")
	check(skeleton != null and defeat_pose.size() == skeleton.get_bone_count(), "defeat snapshots every skeleton bone before terminal animation")
	visual.call("set_time_factor", 0.0)
	visual.call("set_cinematic_progress", &"defeat_full", 0.02)
	if skeleton != null and defeat_pose.size() == skeleton.get_bone_count():
		var snapshot_held := true
		for bone_index in defeat_pose.size():
			var expected_pose: Transform3D = defeat_pose[bone_index]
			if not skeleton.get_bone_pose(bone_index).is_equal_approx(expected_pose):
				snapshot_held = false
		check(snapshot_held, "defeat cinematic holds the captured pose through the initial hit-stop")
	visual.call("_process", 10.0)
	check(is_equal_approx(float(visual.get("_cinematic_age")), 0.08), "process delta does not move defeat progress at zero time factor")
	visual.call("set_cinematic_progress", &"defeat_full", 0.75)
	model = visual.get("_model")
	var materials: Array = model.get("materials") if model != null else []
	var dissolve_progress := -1.0
	for material: Variant in materials:
		if material is ShaderMaterial:
			dissolve_progress = float(material.get_shader_parameter(&"dissolve"))
	check(dissolve_progress > 0.0 and dissolve_progress < 1.0, "externally supplied defeat progress dissolves progressively in its final 45 percent")
	visual.call("set_cinematic_progress", &"defeat_full", 0.9)
	dissolve_progress = -1.0
	for material: Variant in materials:
		if material is ShaderMaterial:
			dissolve_progress = float(material.get_shader_parameter(&"dissolve"))
	check(is_equal_approx(dissolve_progress, 0.77778), "linear defeat dissolve at progress 0.90 is 0.77778")
	visual.call("set_cinematic_progress", &"defeat_full", 1.0)
	check(is_equal_approx(float(visual.get("_cinematic_age")), 4.0), "coarse progress jump clamps at terminal cinematic duration")
	check(bool(visual.get("_terminal")) and StringName(visual.get("_state")) == &"defeat",
		"completed defeat remains terminal instead of returning to idle")
	for material: Variant in materials:
		if material is ShaderMaterial:
			check(is_equal_approx(float(material.get_shader_parameter(&"dissolve")), 1.0), "coarse defeat completion reaches full dissolve")
	visual.call("_process", 2.0)
	check(bool(visual.get("_terminal")) and StringName(visual.get("_state")) == &"defeat",
		"additional coarse frames preserve the terminal defeated state")
	for mode in [&"intro_full", &"intro_short"]:
		await check_intro_pose_hold_glb(visual, mode, cinematic_default_seconds(mode), float(BossVisualBase.INTRO_HOLD_UNTIL[mode]))


func check_head_overlay_isolation() -> void:
	var packed := load(VISUAL_SCENE_PATH) as PackedScene
	if packed == null:
		check(false, "head overlay comparison can load Hydra visual scene")
		return
	var active := packed.instantiate() as Node3D
	var control := packed.instantiate() as Node3D
	check(active != null and control != null, "paired Hydra visuals instantiate for overlay isolation")
	if active == null or control == null:
		if active != null: active.free()
		if control != null: control.free()
		return
	root.add_child(active)
	root.add_child(control)
	active.call("on_spawned")
	control.call("on_spawned")
	var active_skeleton := active.get("_skeleton") as Skeleton3D
	var control_skeleton := control.get("_skeleton") as Skeleton3D
	check(active_skeleton != null and control_skeleton != null, "paired visuals expose their skeletons")
	if active_skeleton == null or control_skeleton == null:
		active.free()
		control.free()
		return
	var selected_bones: Array[int] = []
	var unselected_bones: Array[int] = []
	for bone_name in ["neck_lo_0", "neck_hi_0", "head_0", "jaw_0"]:
		selected_bones.append(active_skeleton.find_bone(bone_name))
	for bone_name in ["neck_lo_1", "neck_hi_1", "head_1", "jaw_1"]:
		unselected_bones.append(active_skeleton.find_bone(bone_name))
	check(not selected_bones.has(-1) and not unselected_bones.has(-1), "overlay bone groups exist for selected and unselected lanes")
	if selected_bones.has(-1) or unselected_bones.has(-1):
		active.free()
		control.free()
		return
	active.call("_process", 0.2)
	control.call("_process", 0.2)
	active.call("play_telegraph", 0b001, &"default", 0.8)
	active.call("_process", 0.16)
	control.call("_process", 0.16)
	var selected_changed := false
	for bone_index in selected_bones:
		if not active_skeleton.get_bone_pose(bone_index).is_equal_approx(control_skeleton.get_bone_pose(bone_index)):
			selected_changed = true
	check(selected_changed, "selected lane telegraph overlays its own branch bones")
	var other_lane_unchanged := true
	for bone_index in unselected_bones:
		if not active_skeleton.get_bone_pose(bone_index).is_equal_approx(control_skeleton.get_bone_pose(bone_index)):
			other_lane_unchanged = false
	check(other_lane_unchanged, "unselected lane remains at its current idle pose")
	active.call("_process", 0.8)
	control.call("_process", 0.8)
	var returned_to_idle := true
	for bone_index in selected_bones:
		if not active_skeleton.get_bone_pose(bone_index).is_equal_approx(control_skeleton.get_bone_pose(bone_index)):
			returned_to_idle = false
	check(returned_to_idle, "selected branch restores idle pose without stale overlay transforms")
	active.free()
	control.free()


func check_crown_lane_targeting() -> void:
	var left_target_rotation := check_crown_pair(0b011, -1.0, 2, "left+centre")
	var right_target_rotation := check_crown_pair(0b110, 1.0, 0, "centre+right")
	check(not left_target_rotation.is_equal_approx(right_target_rotation), "crown orientation differs for opposite force-push pairs")


func check_crown_pair(lane_mask: int, expected_x: float, unselected_lane: int, label: String) -> Quaternion:
	var packed := load(VISUAL_SCENE_PATH) as PackedScene
	if packed == null:
		check(false, label + " crown probe loads visual scene")
		return Quaternion.IDENTITY
	var active := packed.instantiate() as Node3D
	var control := packed.instantiate() as Node3D
	check(active != null and control != null, label + " crown probe instantiates paired visuals")
	if active == null or control == null:
		if active != null: active.free()
		if control != null: control.free()
		return Quaternion.IDENTITY
	root.add_child(active)
	root.add_child(control)
	active.call("on_spawned")
	control.call("on_spawned")
	active.call("set_phase", 2)
	control.call("set_phase", 2)
	active.call("_process", 1.3)
	control.call("_process", 1.3)
	var active_skeleton := active.get("_skeleton") as Skeleton3D
	var control_skeleton := control.get("_skeleton") as Skeleton3D
	check(active_skeleton != null and control_skeleton != null, label + " paired visuals expose skeletons")
	if active_skeleton == null or control_skeleton == null:
		active.free()
		control.free()
		return Quaternion.IDENTITY
	active.call("play_telegraph", lane_mask, &"force_push", 0.8)
	active.call("_process", 0.2)
	control.call("_process", 0.2)
	var crown_target := float(active.get("_crown_target_x"))
	check(is_equal_approx(crown_target, expected_x), "%s force_push targets crown x=%.0f (actual %.3f)" % [label, expected_x, crown_target])
	var fourth_index := active_skeleton.find_bone("head_3")
	check(fourth_index >= 0, "%s crown head bone exists" % label)
	var crown_rotation := active_skeleton.get_bone_pose_rotation(fourth_index) if fourth_index >= 0 else Quaternion.IDENTITY
	if fourth_index >= 0:
		active_skeleton.force_update_all_bone_transforms()
		var crown_transform := active_skeleton.global_transform * active_skeleton.get_bone_global_pose(fourth_index)
		var crown_forward := crown_transform.basis.z.normalized()
		var toward_pair := Vector3(expected_x - crown_transform.origin.x, 0.0, 1.0).normalized()
		check(crown_forward.dot(toward_pair) > 0.0,
			"%s crown global transform faces its force-push pair (forward %s, target %s)" % [label, str(crown_forward), str(toward_pair)])
	var branch_names := ["branch_%d", "neck_lo_%d", "neck_hi_%d", "head_%d", "jaw_%d"]
	var unselected_lane_matches_idle := true
	for bone_pattern in branch_names:
		var bone_index := active_skeleton.find_bone(bone_pattern % unselected_lane)
		if bone_index < 0 or not active_skeleton.get_bone_pose(bone_index).is_equal_approx(control_skeleton.get_bone_pose(bone_index)):
			unselected_lane_matches_idle = false
	check(unselected_lane_matches_idle, "%s leaves unselected main lane %d at idle pose" % [label, unselected_lane])
	active.free()
	control.free()
	return crown_rotation


func snapshot_fallback_intro_pose(fallback: Node3D, art: Node3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = [fallback.transform, art.transform]
	var heads: Array = art.get("heads")
	for head: Node3D in heads:
		result.append(head.transform)
		var jaw := head.get_node_or_null("Jaw") as Node3D
		if jaw != null:
			result.append(jaw.transform)
	var batches: Array = art.get("batches")
	for batch: Dictionary in batches:
		var node := batch.get("node") as MultiMeshInstance3D
		if node == null or node.multimesh == null:
			continue
		for instance in node.multimesh.instance_count:
			result.append(node.multimesh.get_instance_transform(instance))
	return result


func fallback_intro_pose_matches(fallback: Node3D, art: Node3D, snapshot: Array[Transform3D]) -> bool:
	var current := snapshot_fallback_intro_pose(fallback, art)
	if current.size() != snapshot.size():
		return false
	for index in snapshot.size():
		if not current[index].is_equal_approx(snapshot[index]):
			return false
	return true


func check_missing_model_fallback() -> void:
	var visual_source := FileAccess.get_file_as_string(VISUAL_SCRIPT_PATH)
	check(not visual_source.is_empty(), "fallback probe reads the Hydra visual source")
	if visual_source.is_empty():
		return
	check(visual_source.contains(GLB_PATH), "fallback probe finds the model path literal")
	var missing_path := "res://__hydra_missing_model_fallback_probe__.glb"
	var fallback_script := GDScript.new()
	fallback_script.source_code = visual_source.replace(GLB_PATH, missing_path)
	check(fallback_script.reload() == OK, "missing-model visual source reloads without changing asset files")
	if not fallback_script.can_instantiate():
		fallback_script = null
		return
	var fallback := Node3D.new()
	fallback.set_script(fallback_script)
	fallback.set("sway_amplitude", 0.12)
	fallback.set("sway_period", 1.0)
	root.add_child(fallback)
	fallback.call("on_spawned")
	var art: Node3D = fallback.get("_art") as Node3D
	check(art != null, "missing GLB mounts procedural BossArt fallback")
	if art == null:
		fallback.free()
		return
	var child_count := fallback.get_child_count()
	fallback.call("on_spawned")
	check(fallback.get_child_count() == child_count, "fallback respawn reuses its existing children")
	fallback.call("play_intro", 0.1)
	fallback.call("_process", 0.2)
	check(StringName(art.get("state")) == &"idle" and StringName(fallback.get("_state")) == &"idle",
		"standalone fallback intro returns to idle")
	check(absf(fallback.position.x) > 0.001, "fallback resumes sway after standalone intro")
	fallback.call("set_phase", 2)
	fallback.call("_process", 0.1)
	check(int(fallback.get("_phase")) == 2 and int(art.get("phase")) == 2, "fallback phase two reaction reaches BossArt")
	for mode in [&"intro_full", &"intro_short"]:
		fallback.call("on_spawned")
		fallback.call("set_time_factor", 0.0)
		var seconds := cinematic_default_seconds(mode)
		var held_progress := float(BossVisualBase.INTRO_HOLD_UNTIL[mode])
		fallback.call("play_cinematic", mode, seconds)
		var pose_at := float(BossVisualBase.INTRO_POSE_AT[mode])
		fallback.call("set_cinematic_progress", mode, pose_at)
		var intro_snapshot := snapshot_fallback_intro_pose(fallback, art)
		fallback.call("_process", 0.5)
		fallback.call("set_cinematic_progress", mode, held_progress)
		check(fallback_intro_pose_matches(fallback, art, intro_snapshot),
			"fallback %s intro holds head and MultiMesh transforms from INTRO_POSE_AT %.2f through %.2f" % [mode, pose_at, held_progress])
	fallback.call("play_cinematic", &"defeat_full", 2.0)
	fallback.call("set_time_factor", 0.0)
	fallback.call("set_cinematic_progress", &"defeat_full", 0.5)
	check(is_equal_approx(float(fallback.get("_cinematic_age")), 1.0) and StringName(art.get("state")) == &"defeated",
		"fallback defeat cinematic follows supplied progress")
	fallback.call("set_cinematic_progress", &"defeat_full", 1.0)
	check(bool(fallback.get("_terminal")) and StringName(art.get("state")) == &"defeated",
		"fallback remains defeated at terminal cinematic progress")
	fallback.call("on_spawned")
	check(fallback.get_child_count() == child_count and StringName(art.get("state")) == &"idle",
		"fallback respawn resets defeat without creating duplicate children")
	fallback.free()


func read_dissolve_amount(model: Node3D) -> float:
	var materials: Array = model.get("materials") if model != null else []
	for material: Variant in materials:
		if material is ShaderMaterial:
			return float(material.get_shader_parameter(&"dissolve"))
	return -1.0


func capture_dissolve_pixels(viewport: SubViewport, label: String) -> int:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	if pixels == null:
		return 0
	pixels.convert(Image.FORMAT_RGBA8)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			var directory := argument.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(directory)
			pixels.save_png(directory.path_join(label + ".png"))
	var bytes := pixels.get_data()
	var count := 0
	for index in pixels.get_width() * pixels.get_height():
		if bytes[index * 4 + 3] > 127:
			count += 1
	return count


func check_defeat_remnant_render() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		check(not args.has("--require-gpu"), "--require-gpu requires a graphical renderer")
		print("BOSS MERGE CONFLICT HYDRA GPU: SKIP (headless; rerun graphically with -- --require-gpu)")
		return
	var packed := load(VISUAL_SCENE_PATH) as PackedScene
	check(packed != null, "GPU defeat fixture loads Hydra visual scene")
	if packed == null:
		return
	var visual := packed.instantiate() as Node3D
	check(visual != null, "GPU defeat fixture instantiates Hydra visual")
	if visual == null:
		return
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	visual.scale = Vector3.ONE
	root.add_child(visual)
	visual.call("on_spawned")
	var adapter := visual.get("_model") as Node3D
	check(adapter != null, "GPU fixture mounts imported Hydra BossModel")
	if adapter == null:
		visual.free()
		return
	var tag := visual.get("_tag") as Node3D
	if tag != null:
		tag.visible = false
	visual.call("set_phase", 2)
	visual.call("_process", 1.3)
	var skeleton := visual.get("_skeleton") as Skeleton3D
	var crown_branch := skeleton.find_bone("branch_3") if skeleton != null else -1
	check(crown_branch >= 0 and skeleton.get_bone_pose_scale(crown_branch).length() > 0.1,
		"GPU defeat fixture reveals the fourth head before measuring all four heads")
	visual.call("set_time_factor", 0.0)
	visual.call("play_cinematic", &"defeat_full", 4.0)
	visual.set_process(false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(384, 384)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	visual.reparent(viewport)
	visual.transform = Transform3D.IDENTITY
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = Vector3(0.0, 2.0, 12.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)
	camera.current = true
	var checks_for_progress := [0.25, 0.60, 0.75, 0.90, 0.95]
	var coverage_by_progress: Dictionary = {}
	var coverage_bands := {
		0.60: Vector2(0.78, 0.99),
		0.75: Vector2(0.50, 0.82),
		0.90: Vector2(0.15, 0.55),
		0.95: Vector2(0.04, 0.28),
	}
	for progress: float in checks_for_progress:
		visual.call("set_cinematic_progress", &"defeat_full", progress)
		var expected_dissolve := clampf((progress - 0.55) / 0.45, 0.0, 1.0)
		var driven_dissolve := read_dissolve_amount(adapter)
		check(is_equal_approx(driven_dissolve, expected_dissolve),
			"cinematic progress %.2f drives linear dissolve %.5f (actual %.5f)" % [progress, expected_dissolve, driven_dissolve])
		adapter.call("set_dissolve", 0.0)
		var intact_pixels := await capture_dissolve_pixels(viewport, "progress-%.2f-pose-dissolve-0" % progress)
		adapter.call("set_dissolve", driven_dissolve)
		var remaining_pixels := await capture_dissolve_pixels(viewport, "progress-%.2f-cinematic" % progress)
		var coverage := float(remaining_pixels) / maxi(intact_pixels, 1)
		coverage_by_progress[progress] = coverage
		check(is_equal_approx(read_dissolve_amount(adapter), driven_dissolve),
			"dissolve override remains %.5f after awaiting the progress %.2f capture" % [driven_dissolve, progress])
		check(intact_pixels > 1000, "GPU defeat pose at %.2f has measurable intact pixels (%d)" % [progress, intact_pixels])
		if coverage_bands.has(progress):
			var band: Vector2 = coverage_bands[progress]
			check(coverage >= band.x and coverage <= band.y,
				"cinematic progress %.2f same-pose coverage %.4f stays in calibrated %.2f..%.2f band" % [progress, coverage, band.x, band.y])
		print("HYDRA DEFEAT GPU: progress=%.2f dissolve=%.5f remaining=%d intact=%d coverage=%.4f" % [
			progress, driven_dissolve, remaining_pixels, intact_pixels, coverage
		])
	var ordered_progress := [0.60, 0.75, 0.90, 0.95]
	var previous_coverage := 1.0
	for progress: float in ordered_progress:
		var coverage := float(coverage_by_progress.get(progress, 1.0))
		check(coverage < previous_coverage,
			"calibrated dissolve coverage decreases monotonically through progress %.2f (%.4f < %.4f)" % [progress, coverage, previous_coverage])
		previous_coverage = coverage
	visual.call("set_cinematic_progress", &"defeat_full", 1.0)
	var terminal_dissolve := read_dissolve_amount(adapter)
	adapter.call("set_dissolve", 0.0)
	var terminal_intact_pixels := await capture_dissolve_pixels(viewport, "progress-1.00-pose-dissolve-0")
	adapter.call("set_dissolve", terminal_dissolve)
	var terminal_remaining_pixels := await capture_dissolve_pixels(viewport, "progress-1.00-terminal")
	check(bool(visual.get("_terminal")), "GPU cinematic reaches terminal defeat at progress 1.0")
	check(is_equal_approx(read_dissolve_amount(adapter), terminal_dissolve),
		"restoring terminal shader dissolve remains stable after capture")
	check(terminal_remaining_pixels == 0, "cinematic progress 1.0 discards every terminal pixel")
	check(terminal_intact_pixels > 1000, "terminal defeat pose has measurable dissolve-zero pixels (%d)" % terminal_intact_pixels)
	# Report direct shader coverage near the final defeat pose, where the collapsing model
	# still has projected area. Terminal progress itself may collapse the silhouette to zero.
	visual.call("set_cinematic_progress", &"defeat_full", 0.90)
	var direct_pose_pixels := await capture_dissolve_pose_baseline(viewport, adapter)
	adapter.call("set_dissolve", 0.9)
	var direct_shader_pixels := await capture_dissolve_pixels(viewport, "progress-0.90-direct-shader-dissolve-0.90")
	var direct_shader_coverage := float(direct_shader_pixels) / maxi(direct_pose_pixels, 1)
	print("HYDRA DEFEAT GPU: progress=0.90 direct_shader_0.90 remaining=%d intact=%d coverage=%.4f samples=%s terminal_intact=%d" % [
		direct_shader_pixels, direct_pose_pixels, direct_shader_coverage, str(coverage_by_progress), terminal_intact_pixels
	])
	visual.free()
	viewport.free()


func capture_dissolve_pose_baseline(viewport: SubViewport, adapter: Node3D) -> int:
	adapter.call("set_dissolve", 0.0)
	return await capture_dissolve_pixels(viewport, "progress-1.00-pose-dissolve-0")


func finish() -> void:
	call_deferred("finish_after_cleanup")


func finish_after_cleanup() -> void:
	print("BOSS MERGE CONFLICT HYDRA CHECK: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
