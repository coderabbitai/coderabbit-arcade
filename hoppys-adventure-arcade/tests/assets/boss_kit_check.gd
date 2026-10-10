extends SceneTree

const MODEL_SCRIPT_PATH := "res://scenes/runner/boss/hifi/boss_model.gd"
const BossModelScript := preload("res://scenes/runner/boss/hifi/boss_model.gd")
const SELFTEST_PATH := "res://Assets/runner/bosses/kit_selftest/kit_selftest.glb"
const BUILD_PATH := "res://Assets/runner/bosses/kit_selftest/kit_selftest.build.json"
const REST_VALIDATION_META := &"_boss_rest_validation_v2"
const ACTIONS: Array[StringName] = [&"intro", &"idle", &"telegraph", &"attack", &"hurt", &"phase_change", &"defeat", &"retreat"]
const SOCKETS: Array[StringName] = [&"fx_core", &"fx_0", &"fx_1", &"fx_2", &"fx_3", &"fx_4", &"fx_5", &"muzzle_0", &"muzzle_1", &"muzzle_2"]
const MAX_TRIANGLES := 18000
const MAX_MATERIALS := 4
const MAX_BONES := 40
const MAX_SURFACES := 6
const DISSOLVE_PROGRESS := [0.0, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.0]
const DISSOLVE_RETENTION_BANDS := {
	0.60: Vector2(0.82, 0.87),
	0.75: Vector2(0.52, 0.58),
	0.90: Vector2(0.18, 0.23),
	0.95: Vector2(0.01, 0.05),
}

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOSS KIT: " + message)


func has_shader_param(material: ShaderMaterial, name: StringName) -> bool:
	if material == null or material.shader == null:
		return false
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if StringName(uniform.get("name", "")) == name:
			return true
	return false


func check_build_report() -> Dictionary:
	check(FileAccess.file_exists(BUILD_PATH), "host-generated kit self-test build report exists")
	if not FileAccess.file_exists(BUILD_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILD_PATH))
	check(parsed is Dictionary, "build report parses as an object")
	if not parsed is Dictionary:
		return {}
	var report: Dictionary = parsed
	check(report.get("quick", true) == false, "self-test uses the full bake")
	check(int(report.get("kit_revision", 0)) >= 2, "self-test uses the rest-position kit revision")
	check(report.get("rest_position_encoding", "") == "TEXCOORD_1.xy,TEXCOORD_2.x;TEXCOORD_2.y=1", "report declares the rest-position attribute ABI")
	check(int(report.get("animation_sample_rate", -1)) == 120, "build report samples animations at 120 Hz")
	check(int(report.get("triangles", -1)) >= 0 and int(report.get("triangles", MAX_TRIANGLES + 1)) <= MAX_TRIANGLES, "build report triangle budget <= 18000")
	check(int(report.get("materials", -1)) >= 0 and int(report.get("materials", MAX_MATERIALS + 1)) <= MAX_MATERIALS, "build report material budget <= 4")
	check(int(report.get("bones", -1)) >= 0 and int(report.get("bones", MAX_BONES + 1)) <= MAX_BONES, "build report bone budget <= 40")
	check(int(report.get("surfaces", -1)) >= 0 and int(report.get("surfaces", MAX_SURFACES + 1)) <= MAX_SURFACES, "build report surface budget <= 6")
	var actions: Array = report.get("actions", [])
	for action in ACTIONS:
		check(actions.has(String(action)) or actions.has(action), "build report includes action " + String(action))
	var sockets: Array = report.get("sockets", [])
	for socket_name in SOCKETS:
		check(sockets.has(String(socket_name)) or sockets.has(socket_name), "build report includes socket " + String(socket_name))
	return report


func mesh_skeleton_census(model: Node3D) -> Dictionary:
	var triangle_count := 0
	var surface_count := 0
	var materials: Dictionary = {}
	var bone_count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			surface_count += 1
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangle_count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source != null:
				materials[source.get_instance_id()] = true
	for node in model.find_children("*", "Skeleton3D", true, false):
		bone_count += (node as Skeleton3D).get_bone_count()
	return {"triangles": triangle_count, "materials": materials.size(), "bones": bone_count, "surfaces": surface_count}


func check_mesh_skeleton_census(model: Node3D, report: Dictionary) -> void:
	var census := mesh_skeleton_census(model)
	for key in ["triangles", "materials", "bones", "surfaces"]:
		check(int(report.get(key, -1)) == int(census[key]), "build report %s matches imported census (%d vs %d)" % [key, int(report.get(key, -1)), int(census[key])])


func check_rest_positions(model: Node3D, model_script: Script) -> void:
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var restored: PackedVector3Array = model_script.call("rest_positions", node.mesh, surface)
			check(restored.size() == vertices.size(), "every imported vertex preserves encoded rest xyz and version marker")
			var error := 0.0
			for index in mini(vertices.size(), restored.size()):
				error = maxf(error, vertices[index].distance_to(restored[index]))
			check(error <= 0.0001, "rest coordinates survive glTF import within 0.1 mm")
	# An older mesh must use procedural fallback instead of silently burning from (0,0,0).
	var old_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	old_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	check(model_script.call("rest_positions", old_mesh, 0).is_empty(), "missing rest-position attributes are rejected")


func rest_scan_count() -> int:
	return BossModelScript._rest_position_scan_count


func source_meshes(model: Node3D) -> Array[Mesh]:
	var result: Array[Mesh] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null and not result.has(mesh):
			result.append(mesh)
	return result


func source_surface_count(meshes: Array[Mesh]) -> int:
	var count := 0
	for mesh in meshes:
		count += mesh.get_surface_count()
	return count


func make_rest_validation_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var valid := []
	valid.resize(Mesh.ARRAY_MAX)
	valid[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	valid[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2(0, 1)])
	valid[Mesh.ARRAY_CUSTOM0] = PackedFloat32Array([0.0, 1.0, 0.0, 1.0, 0.0, 1.0])
	var rest_flags := Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, valid, [], {}, rest_flags)
	var invalid := []
	invalid.resize(Mesh.ARRAY_MAX)
	invalid[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, invalid)
	return mesh


func cache_validity(model_script: Script, mesh: Mesh, surface: int) -> bool:
	return bool(model_script.call("_has_valid_rest_positions", mesh, surface))


func check_rest_validation_cache(model_script: Script) -> void:
	var mesh := make_rest_validation_mesh()
	var before := rest_scan_count()
	check(cache_validity(model_script, mesh, 0), "first valid surface cache lookup accepts encoded rest data")
	check(rest_scan_count() == before + 1, "first lookup freshly scans its surface")
	check(cache_validity(model_script, mesh, 0), "repeat lookup returns cached valid surface")
	check(rest_scan_count() == before + 1, "repeat lookup does not rescan a valid surface")
	check(not cache_validity(model_script, mesh, 1), "invalid second surface is rejected")
	check(rest_scan_count() == before + 2, "second surface is validated independently")
	check(not cache_validity(model_script, mesh, 1), "repeat lookup returns cached invalid surface")
	check(rest_scan_count() == before + 2, "cached invalid surface does not rescan")
	check(mesh.has_meta(REST_VALIDATION_META), "validated surfaces are recorded on the Mesh")
	var duplicate := mesh.duplicate() as Mesh
	check(duplicate != null and duplicate.get_instance_id() != mesh.get_instance_id(), "duplicate is a distinct Mesh resource")
	if duplicate != null:
		# Force the copied stale owner id so this assertion covers duplicate metadata even
		# if a future Godot version stops copying custom metadata automatically.
		var copied_cache: Dictionary = mesh.get_meta(REST_VALIDATION_META)
		duplicate.set_meta(REST_VALIDATION_META, copied_cache.duplicate(true))
		var before_duplicate := rest_scan_count()
		check(cache_validity(model_script, duplicate, 0), "duplicate with stale metadata validates its own valid surface")
		check(rest_scan_count() == before_duplicate + 1, "duplicate owner id forces a fresh scan")
		check(cache_validity(model_script, duplicate, 0), "duplicate then caches its valid surface")
		check(rest_scan_count() == before_duplicate + 1, "duplicate valid surface is warm after its first scan")
		check(not cache_validity(model_script, duplicate, 1), "duplicate independently rejects its invalid surface")
		check(rest_scan_count() == before_duplicate + 2, "duplicate caches each surface independently")
	mesh.emit_changed()
	check(not mesh.has_meta(REST_VALIDATION_META), "Mesh.changed invalidates its validation metadata")
	var before_changed := rest_scan_count()
	check(cache_validity(model_script, mesh, 0), "changed Mesh revalidates a valid surface")
	check(rest_scan_count() == before_changed + 1, "changed Mesh rescans its valid surface")
	check(not cache_validity(model_script, mesh, 1), "changed Mesh revalidates an invalid surface")
	check(rest_scan_count() == before_changed + 2, "changed Mesh rescans each surface independently")
	duplicate = null
	mesh = null
	var temporary_ref := cached_temporary_mesh_ref(model_script)
	await process_frame
	check(temporary_ref.get_ref() == null, "validation cache does not keep a temporary Mesh alive")


func cached_temporary_mesh_ref(model_script: Script) -> WeakRef:
	var temporary := make_rest_validation_mesh()
	check(cache_validity(model_script, temporary, 0), "temporary Mesh receives a validation cache entry")
	check(temporary.has_meta(REST_VALIDATION_META), "temporary Mesh stores cache metadata locally")
	return weakref(temporary)


func dissolve_mask(viewport: SubViewport, instance: Node3D, progress: float, label: String) -> PackedByteArray:
	# Convert global cinematic progress to linear dissolve input; the shader remaps that input to its threshold.
	instance.call("set_dissolve", clampf((progress - 0.55) / 0.45, 0.0, 1.0))
	# Seeks reach the rendered skin and BoneAttachments on physics updates.
	for frame in 3:
		await physics_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			var directory := argument.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(directory)
			pixels.save_png(directory.path_join("%s-p%03d.png" % [label, roundi(progress * 100)]))
	var bytes := pixels.get_data()
	var mask := PackedByteArray()
	mask.resize(pixels.get_width() * pixels.get_height())
	for index in mask.size():
		mask[index] = 1 if bytes[index * 4 + 3] > 127 else 0
	return mask


func check_retention_band(progress: float, visible: int, intact: int, pose_name: String) -> float:
	var fraction := float(visible) / maxi(intact, 1)
	if DISSOLVE_RETENTION_BANDS.has(progress):
		var band: Vector2 = DISSOLVE_RETENTION_BANDS[progress]
		check(fraction >= band.x and fraction <= band.y,
			"%s pose retains %.0f%% to %.0f%% at global cinematic progress %.2f (observed %.4f)" %
			[pose_name, band.x * 100.0, band.y * 100.0, progress, fraction])
	return fraction


func check_dissolve_smoothness(masks: Dictionary, intact: int, pose_name: String) -> void:
	var previous_progress := 0.55
	var previous_visible: int = masks[previous_progress].count(1)
	for index in range(2, DISSOLVE_PROGRESS.size()):
		var progress: float = DISSOLVE_PROGRESS[index]
		var visible: int = masks[progress].count(1)
		var decrease := float(previous_visible - visible) / maxi(intact, 1)
		check(visible <= previous_visible,
			"%s dissolve coverage is monotonic from progress %.2f to %.2f" % [pose_name, previous_progress, progress])
		check(decrease <= 0.19,
			"%s dissolve coverage decreases by at most 19%% from progress %.2f to %.2f (observed %.4f)" %
			[pose_name, previous_progress, progress, decrease])
		previous_progress = progress
		previous_visible = visible


func check_dissolve_render(instance: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		check(not OS.get_cmdline_user_args().has("--require-gpu"), "--require-gpu requires a graphical renderer")
		print("BOSS KIT GPU: SKIP (headless; rerun graphically with -- --require-gpu)")
		return
	# Transparent offscreen rendering measures actual shader discard, not a CPU approximation.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 320)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	instance.reparent(viewport)
	instance.call("set_flash", 0.0)
	instance.call("set_phase_tint", Color.WHITE)
	var player := instance.get("animation_player") as AnimationPlayer
	player.stop()
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skeleton := instance.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	skeleton.reset_bone_poses()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	camera.position = Vector3(0.3, 0.65, 4.0)
	viewport.add_child(camera)
	camera.current = true
	var rest_camera := camera.transform
	var masks := {}
	for progress: float in DISSOLVE_PROGRESS:
		masks[progress] = await dissolve_mask(viewport, instance, progress, "rest")
	var intact: int = masks[0.0].count(1)
	check(intact > 10000, "GPU fixture has a measurable intact silhouette")
	check_dissolve_smoothness(masks, intact, "rest")
	var rest_retention := {}
	for progress: float in DISSOLVE_RETENTION_BANDS:
		rest_retention[progress] = check_retention_band(progress, masks[progress].count(1), intact, "rest")
	check(masks[1.0].count(1) == 0, "dissolve 1 removes every pixel")
	# This exported defeat is a uniform collapse into fx_core. Counter-transform the
	# camera to hold projected geometry fixed, isolating the mask from silhouette changes.
	player.play(&"defeat", 0.0)
	player.seek(player.get_animation(&"defeat").length, true)
	player.advance(0.0)
	var bone := skeleton.find_bone("root")
	var collapse := skeleton.get_bone_global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse()
	check(collapse.basis.get_scale().is_equal_approx(Vector3.ONE * 0.25), "exported defeat collapses to one-quarter scale")
	camera.position = collapse * rest_camera.origin
	camera.basis = collapse.basis.orthonormalized() * rest_camera.basis
	camera.size = 2.2 * collapse.basis.get_scale().x
	var defeat_intact := 0
	var max_changed := 0
	var defeat_retention := {}
	var defeat_masks := {}
	for progress: float in DISSOLVE_PROGRESS:
		var actual := await dissolve_mask(viewport, instance, progress, "defeat")
		defeat_masks[progress] = actual
		var expected: PackedByteArray = masks[progress]
		var changed := 0
		for index in actual.size():
			if actual[index] != expected[index]: changed += 1
		max_changed = maxi(max_changed, changed)
		check(float(changed) / maxi(intact, 1) <= 0.01, "dissolve mask stays pose-invariant at global progress %.2f" % progress)
		if progress == 0.0: defeat_intact = actual.count(1)
		if DISSOLVE_RETENTION_BANDS.has(progress):
			defeat_retention[progress] = check_retention_band(progress, actual.count(1), defeat_intact, "defeat")
		if progress == 1.0:
			check(actual.count(1) == 0, "dissolve removes every defeat-pose pixel at global progress 1.0")
	check_dissolve_smoothness(defeat_masks, defeat_intact, "defeat")
	print("BOSS KIT GPU: rest_p95=%.4f defeat_p95=%.4f max_mask_delta=%d/%d" % [rest_retention[0.95], defeat_retention[0.95], max_changed, intact])
	instance.reparent(root)
	viewport.free()


func check_imported_orm(model: Node3D) -> void:
	var packed_orm_count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null or source.get_texture(BaseMaterial3D.TEXTURE_METALLIC) == null:
				continue
			packed_orm_count += 1
			check(source.get_texture(BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION) == source.get_texture(BaseMaterial3D.TEXTURE_METALLIC), "imported occlusion and metallic slots use packed ORM")
			check(source.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS) == source.get_texture(BaseMaterial3D.TEXTURE_METALLIC), "imported roughness and metallic slots use packed ORM")
			check(source.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, "imported ORM red channel is occlusion")
			check(source.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN, "imported ORM green channel is roughness")
			check(source.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "imported ORM blue channel is metallic")
	check(packed_orm_count > 0, "imported GLB contains at least one packed ORM surface")


func check_instance_isolation(first: Node3D, second: Node3D) -> void:
	var first_materials: Array = first.get("materials")
	var second_materials: Array = second.get("materials")
	check(first_materials.size() > 0, "loaded model exposes shader materials")
	check(first_materials.size() == second_materials.size(), "instances expose matching material sets")
	for index in mini(first_materials.size(), second_materials.size()):
		var first_material: Variant = first_materials[index]
		var second_material: Variant = second_materials[index]
		check(first_material is ShaderMaterial and second_material is ShaderMaterial, "runtime material is a ShaderMaterial")
		if not first_material is ShaderMaterial or not second_material is ShaderMaterial:
			continue
		check(first_material != second_material, "mutable shader materials are per-instance")
		for parameter in [&"dissolve", &"flash", &"phase_tint"]:
			check(has_shader_param(first_material, parameter), "shader declares " + String(parameter))
			check(has_shader_param(second_material, parameter), "peer shader declares " + String(parameter))
			check(first_material.get_shader_parameter(parameter) == second_material.get_shader_parameter(parameter), "instances begin with equal " + String(parameter))
		first_material.set_shader_parameter(&"flash", 0.37)
		check(not is_equal_approx(float(second_material.get_shader_parameter(&"flash")), 0.37), "mutating one instance does not change peer flash")
		first_material.set_shader_parameter(&"flash", 0.0)


func check_socket_animation(instance: Node3D, animation_player: AnimationPlayer) -> void:
	var socket := instance.call("socket", &"muzzle_0") as Node3D
	check(socket != null, "arm-attached muzzle socket exists")
	if socket == null or not animation_player.has_animation(&"attack"):
		return
	var model := instance.get("model") as Node3D
	var skeletons: Array = model.find_children("*", "Skeleton3D", true, false)
	animation_player.stop()
	animation_player.play(&"attack", 0.0)
	animation_player.speed_scale = 0.0
	var attack_clip: Animation = animation_player.get_animation(&"attack")
	animation_player.seek(0.0, true)
	await process_frame
	for skeleton_node in skeletons:
		(skeleton_node as Skeleton3D).force_update_all_bone_transforms()
	var start := socket.global_position
	var arm_index := (skeletons[0] as Skeleton3D).find_bone("arm")
	var arm_rotation_start := (skeletons[0] as Skeleton3D).get_bone_pose_rotation(arm_index)
	animation_player.seek(attack_clip.length * 0.5, true)
	await process_frame
	for skeleton_node in skeletons:
		(skeleton_node as Skeleton3D).force_update_all_bone_transforms()
	var arm_rotation_middle := (skeletons[0] as Skeleton3D).get_bone_pose_rotation(arm_index)
	check(not arm_rotation_middle.is_equal_approx(arm_rotation_start), "arm bone rotates during attack")
	check(socket.global_position.distance_to(start) > 0.01, "muzzle socket follows its animated arm bone during attack")
	animation_player.speed_scale = 1.0


func run() -> void:
	await process_frame
	check(FileAccess.file_exists(SELFTEST_PATH), "host-generated kit self-test GLB exists")
	var build_report := check_build_report()
	check(FileAccess.file_exists(MODEL_SCRIPT_PATH), "BossModel loader script exists")
	if not FileAccess.file_exists(MODEL_SCRIPT_PATH):
		finish()
		return
	var model_script: Script = load(MODEL_SCRIPT_PATH)
	check(model_script != null, "BossModel script loads")
	if model_script == null:
		finish()
		return
	var fallback: Variant = model_script.call("load_model", "res://Assets/runner/bosses/kit_selftest/missing.glb")
	check(fallback == null, "missing model path returns null for procedural fallback")
	if not FileAccess.file_exists(SELFTEST_PATH):
		finish()
		return
	var packed_scene := load(SELFTEST_PATH) as PackedScene
	check(packed_scene != null, "self-test PackedScene is held for repeated loads")
	var scans_before_first := rest_scan_count()
	var first: Variant = model_script.call("load_model", SELFTEST_PATH)
	check(first is Node3D, "self-test GLB loads through BossModel")
	if not first is Node3D:
		finish()
		return
	var first_model := first.get("model") as Node3D
	var first_meshes := source_meshes(first_model)
	check(rest_scan_count() - scans_before_first == source_surface_count(first_meshes),
		"first load scans each unique source mesh surface once")
	root.add_child(first)
	var scans_before_second := rest_scan_count()
	var second: Variant = model_script.call("load_model", SELFTEST_PATH)
	check(second is Node3D, "second self-test instance loads")
	if not second is Node3D:
		first.free()
		finish()
		return
	check(rest_scan_count() == scans_before_second, "second load reuses cached rest validation")
	root.add_child(second)
	var imported_model := first_model
	var second_meshes := source_meshes(second.get("model") as Node3D)
	check(second_meshes.size() == first_meshes.size(), "repeated loads have matching source mesh sets")
	for index in mini(first_meshes.size(), second_meshes.size()):
		check(second_meshes[index] == first_meshes[index], "repeated loads share held source Mesh %d" % index)
	check_imported_orm(imported_model)
	check_mesh_skeleton_census(imported_model, build_report)
	await check_rest_validation_cache(model_script)
	check_rest_positions(imported_model, model_script)
	var animation_player: Variant = first.get("animation_player")
	check(animation_player is AnimationPlayer, "loaded instance exposes AnimationPlayer")
	if animation_player is AnimationPlayer:
		for action in ACTIONS:
			check(animation_player.has_animation(action), "runtime animation exists: " + String(action))
		var idle: Animation = animation_player.get_animation(&"idle") if animation_player.has_animation(&"idle") else null
		check(idle != null and idle.loop_mode != Animation.LOOP_NONE, "idle animation loops")
		first.call("play", &"idle")
		check(animation_player.current_animation == &"idle", "play(idle) selects idle")
		first.call("set_time_factor", 0.25)
		check(is_equal_approx(animation_player.speed_scale, 0.25), "time factor scales animation playback")
		first.call("set_time_factor", 1.0)
		await check_socket_animation(first, animation_player)
	else:
		for action in ACTIONS:
			check(false, "runtime animation cannot be checked without AnimationPlayer: " + String(action))
	for socket_name in SOCKETS:
		var socket: Variant = first.call("socket", socket_name)
		check(socket is Node3D, "socket resolves to Node3D: " + String(socket_name))
	var materials: Variant = first.get("materials")
	check(materials is Array, "loaded instance exposes materials array")
	if materials is Array:
		check(materials.size() > 0, "GLB surfaces have rebuilt materials")
		for material: Variant in materials:
			check(material is ShaderMaterial, "rebuilt material uses boss shader")
			if material is ShaderMaterial:
				check(has_shader_param(material, &"dissolve"), "boss shader exposes dissolve")
				check(has_shader_param(material, &"flash"), "boss shader exposes flash")
				check(has_shader_param(material, &"phase_tint"), "boss shader exposes phase_tint")
	check_instance_isolation(first, second)
	if materials is Array:
		first.call("set_dissolve", 0.23)
		first.call("set_flash", 0.61)
		first.call("set_phase_tint", Color(0.2, 0.6, 0.9, 1.0))
		for material: Variant in materials:
			if material is ShaderMaterial:
				check(is_equal_approx(float(material.get_shader_parameter(&"dissolve")), 0.23), "set_dissolve updates rebuilt surfaces")
				check(is_equal_approx(float(material.get_shader_parameter(&"flash")), 0.61), "set_flash updates rebuilt surfaces")
				check(material.get_shader_parameter(&"phase_tint").is_equal_approx(Color(0.2, 0.6, 0.9, 1.0)), "set_phase_tint updates rebuilt surfaces")
	for material: Variant in second.get("materials"):
		if material is ShaderMaterial:
			check(is_equal_approx(float(material.get_shader_parameter(&"dissolve")), 0.0), "peer dissolve remains unchanged")
			check(is_equal_approx(float(material.get_shader_parameter(&"flash")), 0.0), "peer flash remains unchanged")
			check(material.get_shader_parameter(&"phase_tint").is_equal_approx(Color.WHITE), "peer phase tint remains unchanged")
	await check_dissolve_render(first)
	first.free()
	second.free()
	finish()


func finish() -> void:
	call_deferred("finish_after_cleanup")


func finish_after_cleanup() -> void:
	print("BOSS KIT CHECK: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
