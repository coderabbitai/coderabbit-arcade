extends SceneTree

const MODEL_SCRIPT_PATH := "res://scenes/runner/boss/hifi/boss_model.gd"
const VISUAL_SCRIPT_PATH := "res://scenes/runner/boss/visuals/merge_conflict_hydra_visual.gd"
const VISUAL_SCENE_PATH := "res://scenes/runner/boss/visuals/merge_conflict_hydra_visual.tscn"
const GLB_PATH := "res://Assets/runner/bosses/merge_conflict_hydra/merge_conflict_hydra.glb"
const BUILD_PATH := "res://Assets/runner/bosses/merge_conflict_hydra/merge_conflict_hydra.build.json"
const ACTIONS: Array[StringName] = [&"intro", &"idle", &"telegraph", &"attack", &"hurt", &"phase_change", &"defeat", &"retreat"]
const SOCKETS: Array[StringName] = [&"fx_core", &"fx_0", &"fx_1", &"fx_2", &"fx_3", &"fx_4", &"fx_5", &"muzzle_0", &"muzzle_1", &"muzzle_2"]
const MAX_TRIANGLES := 18000
const MAX_BONES := 40
const PROCEDURAL_SIZE := Vector3(6.431928, 3.8582, 1.893)

var checks := 0
var failures := 0


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
