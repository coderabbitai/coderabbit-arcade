extends SceneTree

const MODEL_SCRIPT_PATH := "res://scenes/runner/boss/hifi/boss_model.gd"
const VISUAL_SCRIPT_PATH := "res://scenes/runner/boss/visuals/legacy_monolith_visual.gd"
const MODEL_PATH := "res://Assets/runner/bosses/legacy_monolith/legacy_monolith.glb"
const BUILD_PATH := "res://Assets/runner/bosses/legacy_monolith/legacy_monolith.build.json"
const ACTIONS: Array[StringName] = [&"intro", &"idle", &"telegraph", &"attack", &"hurt", &"phase_change", &"defeat", &"retreat"]
const SOCKETS: Array[StringName] = [&"fx_core", &"fx_0", &"fx_1", &"fx_2", &"fx_3", &"fx_4", &"fx_5", &"muzzle_0", &"muzzle_1", &"muzzle_2"]
const MAX_TRIANGLES := 18000
const MAX_BONES := 40
const ACCENT := Color("6a7ba2")
const REST_POSITION_ENCODING := "TEXCOORD_1.xy,TEXCOORD_2.x;TEXCOORD_2.y=1"
const BASELINE_BOUNDS := AABB(Vector3(-3.1, -0.945, -0.825), Vector3(6.2, 3.93, 1.825))
const EXPECTED_MOUNT := Vector3(0.0, 2.6, -14.0)
const POSE_BOUNDS := preload("res://tests/boss_pose_bounds.gd")
const ENVELOPE_X_MIN := -3.5
const ENVELOPE_X_MAX := 3.5
const ENVELOPE_Y_MIN := 1.6
const ENVELOPE_Y_MAX := 6.1
const ENVELOPE_DEPTH_MAX := 3.0
const ENVELOPE_Z_FRONT_MARGIN := 3.0
const ENVELOPE_SAMPLE_RATE := 120.0

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LEGACY MONOLITH: " + message)


func report_array_contains(values: Array, value: StringName) -> bool:
	return values.has(String(value)) or values.has(value)


func sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(file.get_buffer(file.get_length()))
	return context.finish().hex_encode()


func is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if not "0123456789abcdef".contains(character):
			return false
	return true


func check_report() -> Dictionary:
	check(FileAccess.file_exists(BUILD_PATH), "full-bake build report exists")
	if not FileAccess.file_exists(BUILD_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILD_PATH))
	check(parsed is Dictionary, "build report parses as an object")
	if not parsed is Dictionary:
		return {}
	var report: Dictionary = parsed
	check(report.get("kind", "") == "legacy_monolith", "report kind is Legacy Monolith")
	check(report.get("quick", true) == false, "report describes a full bake")
	check(int(report.get("kit_revision", 0)) >= 2, "full bake includes kit v2 rest-position data")
	check(report.get("rest_position_encoding", "") == REST_POSITION_ENCODING, "report declares the shared rest-position attribute encoding")
	check(int(report.get("animation_sample_rate", -1)) == 120, "actions are sampled at 120 Hz")
	check(int(report.get("triangles", MAX_TRIANGLES + 1)) > 0 and int(report.get("triangles", MAX_TRIANGLES + 1)) <= MAX_TRIANGLES, "reported triangle count is within the 18,000 budget")
	check(int(report.get("materials", -1)) == 1, "full bake has exactly one material")
	check(int(report.get("surfaces", -1)) == 1, "full bake has exactly one surface")
	check(int(report.get("bones", MAX_BONES + 1)) > 0 and int(report.get("bones", MAX_BONES + 1)) <= MAX_BONES, "reported bone count is within the 40-bone budget")
	var budget: Dictionary = report.get("budget", {})
	check(int(budget.get("triangles", -1)) == MAX_TRIANGLES, "report records the 18,000-triangle budget")
	check(int(budget.get("materials", -1)) == 4, "report records the four-material budget")
	check(int(budget.get("bones", -1)) == MAX_BONES, "report records the 40-bone budget")
	check(int(budget.get("surfaces", -1)) == 6, "report records the six-surface budget")
	for action in ACTIONS:
		check(report_array_contains(report.get("actions", []), action), "report includes action " + String(action))
	for socket_name in SOCKETS:
		check(report_array_contains(report.get("sockets", []), socket_name), "report includes socket " + String(socket_name))
	var hashes: Dictionary = report.get("source_hashes", {})
	check(not hashes.is_empty(), "report includes source provenance hashes")
	for source_path: String in ["tools/blender/bosses/build_legacy_monolith.py", "tools/blender/bosses/boss_kit.py", "tools/blender/bosses/bosses_budget.json", "tools/blender/glb_atlas.py", "tools/blender/props/props_kit.py"]:
		check(hashes.has(source_path) and is_sha256(String(hashes.get(source_path, ""))), "provenance includes a SHA-256 for " + source_path)
		var source_file := "res://" + source_path
		check(FileAccess.file_exists(source_file), "provenance source exists: " + source_path)
		if FileAccess.file_exists(source_file):
			check(String(hashes.get(source_path, "")) == sha256(source_file), "provenance hash matches source: " + source_path)
	var glb: Dictionary = report.get("glb", {})
	check(glb.get("file", "") == "legacy_monolith.glb", "report names the expected GLB")
	check(int(glb.get("bytes", 0)) > 0, "report records a nonzero GLB size")
	check(is_sha256(String(glb.get("sha256", ""))), "report records a GLB SHA-256")
	check(FileAccess.file_exists(MODEL_PATH), "full-bake GLB exists")
	if FileAccess.file_exists(MODEL_PATH):
		check(int(glb.get("bytes", -1)) == FileAccess.get_file_as_bytes(MODEL_PATH).size(), "reported GLB byte count matches the file")
		check(String(glb.get("sha256", "")) == sha256(MODEL_PATH), "reported GLB hash matches the file")
	var textures: Dictionary = report.get("textures", {})
	for texture_key in ["albedo", "normal", "orm", "emission"]:
		var texture: Dictionary = textures.get(texture_key, {})
		var file_name := String(texture.get("file", ""))
		var texture_path := "res://Assets/runner/bosses/legacy_monolith/" + file_name
		check(not file_name.is_empty() and FileAccess.file_exists(texture_path), "report's " + texture_key + " texture exists")
		check(is_sha256(String(texture.get("sha256", ""))), "report's " + texture_key + " texture has a SHA-256")
		if FileAccess.file_exists(texture_path):
			check(String(texture.get("sha256", "")) == sha256(texture_path), "reported " + texture_key + " hash matches the file")
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
	check(census.triangles > 0 and census.triangles <= MAX_TRIANGLES, "imported GLB is within the 18,000-triangle budget")
	check(census.materials == 1, "imported GLB has exactly one material")
	check(census.surfaces == 1, "imported GLB has exactly one surface")
	check(census.bones > 0 and census.bones <= MAX_BONES, "imported GLB is within the 40-bone budget")
	for key in ["triangles", "materials", "bones", "surfaces"]:
		check(int(report.get(key, -1)) == int(census[key]), "reported %s matches imported GLB census (%d vs %d)" % [key, int(report.get(key, -1)), int(census[key])])
	var bounds := mesh_bounds_in_space(model, model)
	check(bounds.size.x >= BASELINE_BOUNDS.size.x * 0.8 and bounds.size.x <= BASELINE_BOUNDS.size.x * 1.2, "imported model width stays within 20% of procedural baseline")
	check(bounds.size.y >= BASELINE_BOUNDS.size.y * 0.8 and bounds.size.y <= BASELINE_BOUNDS.size.y * 1.2, "imported model height stays within 20% of procedural baseline")
	check(bounds.size.z >= BASELINE_BOUNDS.size.z * 0.8 and bounds.size.z <= BASELINE_BOUNDS.size.z * 1.2, "imported model depth stays within 20% of procedural baseline")


func check_imported_orm(model: Node3D) -> void:
	var packed_orm_surfaces := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null or source.get_texture(BaseMaterial3D.TEXTURE_METALLIC) == null:
				continue
			packed_orm_surfaces += 1
			var orm := source.get_texture(BaseMaterial3D.TEXTURE_METALLIC)
			check(source.get_texture(BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION) == orm, "imported AO slot shares packed ORM texture")
			check(source.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS) == orm, "imported roughness slot shares packed ORM texture")
			check(source.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, "imported ORM red channel is occlusion")
			check(source.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN, "imported ORM green channel is roughness")
			check(source.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "imported ORM blue channel is metallic")
	check(packed_orm_surfaces == 1, "single imported surface contains packed ORM")


func check_rest_positions(model: Node3D, model_script: Script) -> void:
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null:
			continue
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var rest: PackedVector3Array = model_script.call("rest_positions", node.mesh, surface)
			check(rest.size() == vertices.size() and not rest.is_empty(), "every imported vertex carries shared rest-position attributes")
			var maximum_error := 0.0
			for index in mini(vertices.size(), rest.size()):
				maximum_error = maxf(maximum_error, vertices[index].distance_to(rest[index]))
			check(maximum_error <= 0.0001, "rest-position attributes match imported vertices within 0.1 mm")


func has_shader_param(material: ShaderMaterial, name: StringName) -> bool:
	if material == null or material.shader == null:
		return false
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if StringName(uniform.get("name", "")) == name:
			return true
	return false


func add_transformed_box(accumulator: Dictionary, box: AABB, transform: Transform3D) -> void:
	for corner in 8:
		var point := transform * box.get_endpoint(corner)
		if not accumulator.has("bounds"):
			accumulator["bounds"] = AABB(point, Vector3.ZERO)
		else:
			var bounds: AABB = accumulator["bounds"]
			bounds = bounds.expand(point)
			accumulator["bounds"] = bounds


func mesh_bounds_in_space(container: Node3D, space: Node3D) -> AABB:
	var accumulator := {}
	for node in container.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative := space.global_transform.affine_inverse() * mesh_instance.global_transform
		add_transformed_box(accumulator, mesh_instance.mesh.get_aabb(), relative)
	return accumulator.get("bounds", AABB())


func procedural_art_bounds(art: Node) -> AABB:
	var accumulator := {}
	var art_node := art as Node3D
	var batches: Array = art.get("batches")
	for entry: Dictionary in batches:
		for pose: Transform3D in entry.get("poses", []):
			add_transformed_box(accumulator, AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE), pose)
	for node in art.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative: Transform3D = art_node.global_transform.affine_inverse() * mesh_instance.global_transform
		add_transformed_box(accumulator, mesh_instance.mesh.get_aabb(), relative)
	return accumulator.get("bounds", AABB())


func check_bounds_match(actual: AABB, expected: AABB, tolerance: float, label: String) -> void:
	check(actual.position.distance_to(expected.position) <= tolerance, label + " bounds origin matches procedural baseline")
	check(actual.size.distance_to(expected.size) <= tolerance, label + " bounds size matches procedural baseline")


func check_adapter(adapter: Node3D, report: Dictionary) -> void:
	check(adapter != null, "BossModel loads the Legacy Monolith GLB")
	if adapter == null:
		return
	var model := adapter.get("model") as Node3D
	check(model != null, "adapter exposes imported model")
	if model == null:
		return
	check_mesh_skeleton_census(model, report)
	check_imported_orm(model)
	var model_script := load(MODEL_SCRIPT_PATH) as Script
	check_rest_positions(model, model_script)
	var player := adapter.get("animation_player") as AnimationPlayer
	check(player != null, "adapter exposes AnimationPlayer")
	if player != null:
		for action in ACTIONS:
			check(player.has_animation(action), "runtime animation exists: " + String(action))
		var idle: Animation = player.get_animation(&"idle") if player.has_animation(&"idle") else null
		check(idle != null and idle.loop_mode != Animation.LOOP_NONE, "idle animation loops")
		adapter.call("play", &"idle")
		check(player.current_animation == &"idle", "adapter can select idle")
	for socket_name in SOCKETS:
		var socket: Variant = adapter.call("socket", socket_name)
		check(socket is Node3D, "adapter resolves socket " + String(socket_name))
	var materials: Array = adapter.get("materials")
	check(materials.size() == 1, "adapter exposes the single rebuilt shader material")
	for material: Variant in materials:
		check(material is ShaderMaterial, "runtime material uses boss shader")
		if material is ShaderMaterial:
			for parameter in [&"dissolve", &"flash", &"phase_tint"]:
				check(has_shader_param(material, parameter), "boss shader exposes " + String(parameter))
	adapter.call("set_dissolve", 0.27)
	adapter.call("set_flash", 0.63)
	adapter.call("set_phase_tint", Color(0.2, 0.6, 0.9, 1.0))
	for material: Variant in materials:
		if material is ShaderMaterial:
			check(is_equal_approx(float(material.get_shader_parameter(&"dissolve")), 0.27), "adapter sets dissolve")
			check(is_equal_approx(float(material.get_shader_parameter(&"flash")), 0.63), "adapter sets flash")
			check(material.get_shader_parameter(&"phase_tint").is_equal_approx(Color(0.2, 0.6, 0.9, 1.0)), "adapter sets phase tint")


func property_exists(node: Object, property_name: StringName) -> bool:
	for property: Dictionary in node.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func inherited_timing_map(constant_name: StringName) -> Dictionary:
	var base_script := load("res://scenes/runner/boss/boss_visual_base.gd") as Script
	if base_script == null:
		return {}
	var constants := base_script.get_script_constant_map()
	var value: Variant = constants.get(constant_name, {})
	return value if value is Dictionary else {}


func skeleton_pose_snapshot(adapter: Node3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	if adapter == null:
		return poses
	var skeletons := adapter.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return poses
	var skeleton := skeletons[0] as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose(bone))
	return poses


func bone_pose_snapshots_match(left: Array[Transform3D], right: Array[Transform3D], tolerance: float = 0.0001) -> bool:
	if left.is_empty() or left.size() != right.size():
		return false
	for index in left.size():
		if not left[index].is_equal_approx(right[index]) or left[index].origin.distance_to(right[index].origin) > tolerance:
			return false
	return true


func drive_visual(visual: Node, delta: float) -> void:
	visual.call("_process", delta)


func visual_dissolve(visual: Node) -> float:
	var adapter := visual.get("_model") as Node3D
	if adapter != null:
		var materials: Array = adapter.get("materials")
		if not materials.is_empty() and materials[0] is ShaderMaterial:
			return float(materials[0].get_shader_parameter(&"dissolve"))
		var art := visual.get("_art") as Node
		if art != null:
			for node in art.find_children("*", "MeshInstance3D", true, false):
				var material := (node as MeshInstance3D).material_override as ShaderMaterial
				if has_shader_param(material, &"dissolve"):
					return float(material.get_shader_parameter(&"dissolve"))
	return -1.0


func visual_flash(visual: Node) -> float:
	var adapter := visual.get("_model") as Node3D
	if adapter == null:
		return -1.0
	var materials: Array = adapter.get("materials")
	if materials.is_empty() or not materials[0] is ShaderMaterial:
		return -1.0
	return float(materials[0].get_shader_parameter(&"flash"))


func visual_emission_energy(visual: Node) -> float:
	var adapter := visual.get("_model") as Node3D
	if adapter == null:
		return -1.0
	var materials: Array = adapter.get("materials")
	if materials.is_empty() or not materials[0] is ShaderMaterial:
		return -1.0
	return float(materials[0].get_shader_parameter(&"emission_energy"))


func visual_dissolve_color(visual: Node) -> Color:
	var adapter := visual.get("_model") as Node3D
	if adapter == null:
		return Color.TRANSPARENT
	var materials: Array = adapter.get("materials")
	if materials.is_empty() or not materials[0] is ShaderMaterial:
		return Color.TRANSPARENT
	return materials[0].get_shader_parameter(&"dissolve_color")


func new_envelope_summary() -> Dictionary:
	return {"bounds": AABB(), "has_bounds": false, "frames": 0, "max_frame_depth": 0.0, "max_depth_label": "", "violations": {}, "details": {}, "hitstop_failures": []}


func cpu_skinned_world_bounds(container: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for node in container.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var mesh_bounds: AABB = POSE_BOUNDS.mesh_bounds(mesh)
		bounds = mesh_bounds if not found else bounds.merge(mesh_bounds)
		found = true
	return bounds if found else AABB()


func record_envelope_bounds(summary: Dictionary, bounds: AABB, label: String, hover_z: float) -> void:
	if not summary.has_bounds:
		summary.bounds = bounds
		summary.has_bounds = true
	else:
		var accumulated: AABB = summary.bounds
		summary.bounds = accumulated.merge(bounds)
	summary.frames += 1
	if bounds.size.z > float(summary.max_frame_depth):
		summary.max_frame_depth = bounds.size.z
		summary.max_depth_label = label
	var min_x := bounds.position.x
	var max_x := bounds.position.x + bounds.size.x
	var min_y := bounds.position.y
	var max_y := bounds.position.y + bounds.size.y
	var max_z := bounds.position.z + bounds.size.z
	var violations: Array[String] = []
	if min_x < ENVELOPE_X_MIN - 0.001: violations.append("x_min=%.3f<%.1f" % [min_x, ENVELOPE_X_MIN])
	if max_x > ENVELOPE_X_MAX + 0.001: violations.append("x_max=%.3f>%.1f" % [max_x, ENVELOPE_X_MAX])
	if min_y < ENVELOPE_Y_MIN - 0.001: violations.append("y_min=%.3f<%.1f" % [min_y, ENVELOPE_Y_MIN])
	if max_y > ENVELOPE_Y_MAX + 0.001: violations.append("y_max=%.3f>%.1f" % [max_y, ENVELOPE_Y_MAX])
	if bounds.size.z > ENVELOPE_DEPTH_MAX + 0.001: violations.append("depth=%.3f>%.1f" % [bounds.size.z, ENVELOPE_DEPTH_MAX])
	if max_z > hover_z + ENVELOPE_Z_FRONT_MARGIN + 0.001:
		violations.append("front_z=%.3f>hover_z+3=%.3f" % [max_z, hover_z + ENVELOPE_Z_FRONT_MARGIN])
	for violation in violations:
		var counts: Dictionary = summary.violations
		counts[violation.get_slice("=", 0)] = int(counts.get(violation.get_slice("=", 0), 0)) + 1
		summary.violations = counts
		var details: Dictionary = summary.details
		details[violation.get_slice("=", 0)] = "%s (%s)" % [label, violation]
		summary.details = details


func record_envelope_sample(summary: Dictionary, container: Node, label: String, hover_z: float, expand_for_ambient: bool = false) -> void:
	var bounds := cpu_skinned_world_bounds(container)
	if expand_for_ambient:
		bounds.position.x -= 0.14
		bounds.size.x += 0.28
		bounds.size.y += 0.02
	record_envelope_bounds(summary, bounds, label, hover_z)


func envelope_report(summary: Dictionary) -> String:
	if not summary.has_bounds:
		return "no skinned mesh frames sampled"
	var bounds: AABB = summary.bounds
	var extrema := "x[%.3f, %.3f] y[%.3f, %.3f] z[%.3f, %.3f] depth=%.3f" % [
		bounds.position.x, bounds.position.x + bounds.size.x,
		bounds.position.y, bounds.position.y + bounds.size.y,
		bounds.position.z, bounds.position.z + bounds.size.z, float(summary.max_frame_depth),
	]
	if summary.violations.is_empty():
		return "%d frames, %s, max-frame-depth=%.3f at %s" % [summary.frames, extrema, float(summary.max_frame_depth), summary.max_depth_label]
	var failures_by_bound: Array[String] = []
	for key: String in summary.violations:
		failures_by_bound.append("%s x%d at %s" % [key, summary.violations[key], summary.details[key]])
	failures_by_bound.sort()
	return "%d frames, %s, max-frame-depth=%.3f at %s, violations: %s" % [summary.frames, extrema, float(summary.max_frame_depth), summary.max_depth_label, "; ".join(failures_by_bound)]


func finish_envelope_scenario(summary: Dictionary, label: String) -> void:
	var ok: bool = summary.has_bounds and summary.frames > 0 and summary.violations.is_empty() and summary.hitstop_failures.is_empty()
	check(ok, "%s world envelope: %s%s" % [label, envelope_report(summary), " hit-stop: " + "; ".join(summary.hitstop_failures) if not summary.hitstop_failures.is_empty() else ""])
	if ok:
		print("LEGACY ENVELOPE: PASS %s | %s" % [label, envelope_report(summary)])


func sample_visual_action_frame(visual: Node, action: StringName, seconds: float, duration: float) -> void:
	visual.set("_state", action)
	visual.set("_age", seconds)
	visual.set("_duration", maxf(duration, 0.001))
	visual.set("_clock", seconds)
	visual.call("_sample_pose")


func sample_all_action_envelopes(visual: Node3D, adapter: Node3D) -> void:
	var player := adapter.get("animation_player") as AnimationPlayer
	var model := adapter.get("model") as Node3D
	if player == null or model == null:
		check(false, "world envelope action sweep has AnimationPlayer and model")
		return
	for action in ACTIONS:
		var clip := player.get_animation(action)
		if clip == null:
			continue
		var duration := maxf(clip.length, 1.0 / ENVELOPE_SAMPLE_RATE)
		var last_frame := int(ceil(duration * ENVELOPE_SAMPLE_RATE))
		var summary := new_envelope_summary()
		for phase in range(1, 4):
			for health in [0, 100]:
				visual.position.x = 0.0
				visual.position.y = 0.0
				visual.call("set_phase", phase)
				visual.call("set_health", health, 100)
				visual.set("_mode", &"")
				visual.set("_wall_mask", 0)
				visual.set("_aim", 0.0)
				visual.call("_play_action", action, duration)
				for frame in range(last_frame + 1):
					var seconds := minf(float(frame) / ENVELOPE_SAMPLE_RATE, duration)
					sample_visual_action_frame(visual, action, seconds, duration)
					record_envelope_sample(summary, model, "%s phase%d hp%d frame%d/%.3fs" % [String(action), phase, health, frame, seconds], float(visual.get("hover_z")), action != &"intro")
		finish_envelope_scenario(summary, "all 120 Hz frames for %s, phases 1-3, health 0/100" % String(action))


func sample_signature_envelopes(visual: Node3D, adapter: Node3D) -> void:
	var model := adapter.get("model") as Node3D
	var player := adapter.get("animation_player") as AnimationPlayer
	if model == null or player == null:
		check(false, "signature envelope sweep has imported model and AnimationPlayer")
		return
	var kinds: Array[StringName] = [&"slab", &"quake", &"debris"]
	for kind in kinds:
		var telegraph_summary := new_envelope_summary()
		var attack_summary := new_envelope_summary()
		for mask in range(1, 8):
			for phase in range(1, 4):
				for health in [0, 100]:
					visual.call("on_spawned")
					visual.position.x = 0.0
					visual.position.y = 0.0
					visual.call("set_phase", phase)
					visual.call("set_health", health, 100)
					visual.call("play_telegraph", mask, kind, 0.8)
					var telegraph_frames := int(ceil(0.8 * ENVELOPE_SAMPLE_RATE))
					for frame in range(telegraph_frames + 1):
						var seconds := minf(float(frame) / ENVELOPE_SAMPLE_RATE, 0.8)
						sample_visual_action_frame(visual, &"telegraph", seconds, 0.8)
						record_envelope_sample(telegraph_summary, model, "telegraph %s mask%d phase%d hp%d frame%d" % [String(kind), mask, phase, health, frame], float(visual.get("hover_z")), true)
					visual.call("play_attack", kind)
					var attack_duration := maxf(float(visual.get("_duration")), 0.001)
					var attack_frames := int(ceil(attack_duration * ENVELOPE_SAMPLE_RATE))
					for frame in range(attack_frames + 1):
						var seconds := minf(float(frame) / ENVELOPE_SAMPLE_RATE, attack_duration)
						sample_visual_action_frame(visual, &"attack", seconds, attack_duration)
						record_envelope_sample(attack_summary, model, "attack %s mask%d phase%d hp%d frame%d" % [String(kind), mask, phase, health, frame], float(visual.get("hover_z")), true)
		finish_envelope_scenario(telegraph_summary, "all telegraph masks/phases/health for %s at 120 Hz" % String(kind))
		finish_envelope_scenario(attack_summary, "all attack masks/phases/health for %s at 120 Hz" % String(kind))


func sample_runtime_one_shot(visual: Node3D, adapter: Node3D, action: StringName, label: String) -> void:
	var player := adapter.get("animation_player") as AnimationPlayer
	var model := adapter.get("model") as Node3D
	if player == null or model == null or not player.has_animation(action):
		return
	var clip := player.get_animation(action)
	var duration := maxf(clip.length, 1.0 / ENVELOPE_SAMPLE_RATE)
	var summary := new_envelope_summary()
	for progress in [0.0, 0.25, 0.5, 0.75, 1.0]:
		sample_visual_action_frame(visual, action, duration * progress, duration)
		record_envelope_sample(summary, model, "%s p%.2f" % [label, progress], float(visual.get("hover_z")))
	finish_envelope_scenario(summary, "runtime one-shot %s" % label)


func sample_idle_sway_envelopes(visual: Node3D, adapter: Node3D) -> void:
	var model := adapter.get("model") as Node3D
	var period := maxf(float(visual.get("sway_period")), 0.1)
	for phase in [1, 2, 3]:
		for health in [0, 100]:
			visual.call("on_spawned")
			visual.call("set_phase", phase)
			visual.call("set_health", health, 100)
			visual.call("_play_action", &"idle")
			var summary := new_envelope_summary()
			var last_frame := int(ceil(period * 2.0 * ENVELOPE_SAMPLE_RATE))
			for frame in range(last_frame + 1):
				if frame > 0:
					visual.call("_process", 1.0 / ENVELOPE_SAMPLE_RATE)
				record_envelope_sample(summary, model, "idle phase%d hp%d frame%d/%.3fs" % [phase, health, frame, float(frame) / ENVELOPE_SAMPLE_RATE], float(visual.get("hover_z")))
			finish_envelope_scenario(summary, "two idle sway periods phase%d hp%d" % [phase, health])


func sample_cinematic_envelope(visual: Node3D, adapter: Node3D, mode: StringName, duration: float, phase: int, health: int, summary: Dictionary) -> void:
	var model := adapter.get("model") as Node3D
	visual.call("on_spawned")
	visual.call("set_phase", phase)
	visual.call("set_health", health, 100)
	var captured_combat_bounds := AABB()
	if mode in [&"defeat_full", &"defeat_short"]:
		# Capture a real combat pose before the cinematic cue freezes it for hit-stop.
		visual.call("play_telegraph", 5, &"quake", 0.8)
		visual.set("_age", 0.36)
		visual.call("_sample_pose")
		captured_combat_bounds = cpu_skinned_world_bounds(model)
	visual.call("play_cinematic", mode, duration)
	var last_frame := int(ceil(duration * ENVELOPE_SAMPLE_RATE))
	for frame in range(last_frame + 1):
		var seconds := minf(float(frame) / ENVELOPE_SAMPLE_RATE, duration)
		var progress := seconds / duration
		visual.call("set_cinematic_progress", mode, progress)
		record_envelope_sample(summary, model, "%s frame%d p%.5f" % [String(mode), frame, progress], float(visual.get("hover_z")))
		if frame == 0 and mode in [&"defeat_full", &"defeat_short"]:
			var hitstop_bounds := cpu_skinned_world_bounds(model)
			if hitstop_bounds.position.distance_to(captured_combat_bounds.position) > 0.005 or hitstop_bounds.size.distance_to(captured_combat_bounds.size) > 0.005:
				summary.hitstop_failures.append("%s phase%d hp%d did not preserve the combat bounds" % [String(mode), phase, health])


func check_cinematic_envelopes(visual: Node3D, adapter: Node3D) -> void:
	for mode in [&"intro_full", &"intro_short", &"defeat_full", &"defeat_short"]:
		var duration := 5.0 if mode == &"intro_full" else (2.5 if mode == &"intro_short" else (3.6 if mode == &"defeat_full" else 2.0))
		var summary := new_envelope_summary()
		for phase in range(1, 4):
			for health in [0, 100]:
				sample_cinematic_envelope(visual, adapter, mode, duration, phase, health, summary)
		finish_envelope_scenario(summary, "runtime cinematic %s every 120 Hz across phases/health" % String(mode))


func check_retreat_completion_timing(visual: Node3D, adapter: Node3D) -> void:
	visual.call("on_spawned")
	visual.call("play_retreat")
	var player := adapter.get("animation_player") as AnimationPlayer
	var retreat_clip := player.get_animation(&"retreat") if player != null else null
	check(retreat_clip != null, "retreat completion timing has its imported clip")
	if retreat_clip == null:
		return
	drive_visual(visual, 0.8)
	var mid_dissolve := visual_dissolve(visual)
	check(mid_dissolve > 0.0 and mid_dissolve < 1.0, "retreat dissolve is progressing before its completion endpoint")
	drive_visual(visual, 0.15)
	check(is_equal_approx(float(visual.get("_duration")), 0.95), "public retreat uses the backend-aligned 0.95 second duration")
	check(is_equal_approx(player.current_animation_position, retreat_clip.length), "retreat samples the imported clip endpoint by 0.95 seconds")
	check(is_equal_approx(visual_dissolve(visual), 1.0), "retreat dissolve reaches 1 by 0.95 seconds")


func check_world_envelope_contract(visual: Node3D, adapter: Node3D) -> void:
	check(FileAccess.file_exists("res://tests/boss_pose_bounds.gd"), "CPU skinning bounds helper is available (tests/boss_pose_bounds.gd dependency)")
	if adapter == null or not FileAccess.file_exists("res://tests/boss_pose_bounds.gd"):
		return
	visual.call("on_spawned")
	visual.set("sway_amplitude", 0.14)
	visual.call("set_time_factor", 1.0)
	sample_all_action_envelopes(visual, adapter)
	sample_signature_envelopes(visual, adapter)
	sample_idle_sway_envelopes(visual, adapter)
	for phase in [1, 2, 3]:
		for health in [0, 100]:
			visual.call("on_spawned")
			visual.call("set_health", health, 100)
			visual.call("set_phase", phase)
			sample_runtime_one_shot(visual, adapter, &"phase_change", "phase_change phase%d hp%d" % [phase, health])
			visual.call("play_hit", &"whip", 1)
			sample_runtime_one_shot(visual, adapter, &"hurt", "hit/hurt phase%d hp%d" % [phase, health])
			visual.call("on_spawned")
			visual.call("set_phase", phase)
			visual.call("set_health", health, 100)
			visual.call("_play_action", &"idle")
			visual.call("play_resist", &"whip")
			sample_runtime_one_shot(visual, adapter, &"idle", "resist idle pose phase%d hp%d" % [phase, health])
			visual.call("on_spawned")
			visual.call("set_phase", phase)
			visual.call("set_health", health, 100)
			visual.call("play_retreat")
			sample_runtime_one_shot(visual, adapter, &"retreat", "retreat phase%d hp%d" % [phase, health])
	check_retreat_completion_timing(visual, adapter)
	check_cinematic_envelopes(visual, adapter)
	visual.call("on_spawned")


func check_visual_contract() -> void:
	var script := load(VISUAL_SCRIPT_PATH) as Script
	check(script != null, "Legacy Monolith visual script loads")
	if script == null:
		return
	var source := script.source_code
	check(not source.contains("create_tween") and not source.contains("Tween.new"), "visual has no independent Tween animation")
	var intro_pose_at := inherited_timing_map(&"INTRO_POSE_AT")
	var intro_hold_until := inherited_timing_map(&"INTRO_HOLD_UNTIL")
	check(is_equal_approx(float(intro_pose_at.get(&"intro_full", -1.0)), 0.40) and is_equal_approx(float(intro_pose_at.get(&"intro_short", -1.0)), 0.28), "visual inherits the shared full/short intro pose timing map")
	check(is_equal_approx(float(intro_hold_until.get(&"intro_full", -1.0)), 0.66) and is_equal_approx(float(intro_hold_until.get(&"intro_short", -1.0)), 0.88), "visual inherits the shared full/short intro hold timing map")
	var visual := script.new() as Node3D
	check(visual != null, "visual instance can be created")
	if visual == null:
		return
	visual.set("kind", &"legacy_monolith")
	visual.set("hover_z", -14.0)
	var mount := Node3D.new()
	mount.position = EXPECTED_MOUNT
	root.add_child(mount)
	mount.add_child(visual)
	check(property_exists(visual, &"model_path"), "visual exposes public model_path")
	if property_exists(visual, &"model_path"):
		visual.set("model_path", MODEL_PATH)
	visual.call("on_spawned")
	visual.set_process(false)
	check(visual.global_position.distance_to(EXPECTED_MOUNT) <= 0.02, "visual remains mounted at (0, 2.6, -14)")
	var adapter := visual.get("_model") as Node3D
	var art := visual.get("_art") as Node
	check((adapter != null) != (art != null), "visual selects exactly one of GLB adapter or procedural fallback")
	check(adapter != null, "configured valid model path selects the GLB adapter")
	var phase_one_emission := visual_emission_energy(visual)
	check(is_equal_approx(phase_one_emission, 1.0), "phase one idle emission stays at the baked baseline")
	check(visual_dissolve_color(visual).is_equal_approx(Color("f78949")), "visual sets reactor orange as the dissolve edge color")
	if adapter != null:
		var mounted_model := adapter.get("model") as Node3D
		if mounted_model != null:
			check(mounted_model.position.length() <= 0.02, "imported model root stays at the existing boss mount")
	if adapter != null:
		var model := adapter.get("model") as Node3D
		if model != null:
			var child_tweens := visual.find_children("*", "Tween", true, false)
			check(child_tweens.is_empty(), "model visual tree contains no Tween nodes")
	visual.call("set_phase", 2)
	check(StringName(visual.get("_state")) == &"phase_change", "phase change enters phase_change state")
	check(int(visual.get("_phase")) == 2, "phase state records phase two")
	if adapter != null:
		var materials: Array = adapter.get("materials")
		if not materials.is_empty() and materials[0] is ShaderMaterial:
			var tint: Variant = materials[0].get_shader_parameter(&"phase_tint")
			check(tint is Color and not tint.is_equal_approx(Color.WHITE), "phase change applies a phase tint")
		var skeletons := adapter.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var skeleton := skeletons[0] as Skeleton3D
			var shell_index := skeleton.find_bone("shell_L")
			check(shell_index >= 0, "phase crack offsets target the left shell bone")
			if shell_index >= 0:
				drive_visual(visual, 0.05)
				var phase_two_shell := skeleton.get_bone_pose_position(shell_index)
				visual.call("set_phase", 3)
				drive_visual(visual, 0.05)
				check(skeleton.get_bone_pose_position(shell_index).distance_to(phase_two_shell) > 0.05, "phase three spreads shell cracks farther than phase two")
	drive_visual(visual, 1.2)
	check(StringName(visual.get("_state")) == &"idle", "phase change returns to idle")
	check(is_equal_approx(visual_emission_energy(visual), phase_one_emission), "phase three idle does not boost emission above phase one")
	visual.call("play_intro", 4.0)
	check(StringName(visual.get("_state")) == &"intro", "intro enters intro state")
	check(is_equal_approx(float(visual.get("_duration")), 4.0), "intro honors requested duration")
	visual.call("set_time_factor", 0.0)
	var frozen_age := float(visual.get("_age"))
	var frozen_clock := float(visual.get("_clock")) if property_exists(visual, &"_clock") else 0.0
	var frozen_position := 0.0
	if adapter != null:
		var player := adapter.get("animation_player") as AnimationPlayer
		if player != null:
			frozen_position = player.current_animation_position
	drive_visual(visual, 0.2)
	check(is_equal_approx(float(visual.get("_age")), frozen_age), "time factor zero freezes visual animation age")
	if property_exists(visual, &"_clock"):
		check(is_equal_approx(float(visual.get("_clock")), frozen_clock), "time factor zero freezes the visual clock")
	if adapter != null:
		var player := adapter.get("animation_player") as AnimationPlayer
		if player != null:
			check(is_equal_approx(player.current_animation_position, frozen_position), "time factor zero freezes imported animation playback")
	visual.call("set_time_factor", 1.0)
	drive_visual(visual, 4.1)
	check(StringName(visual.get("_state")) == &"idle", "intro returns to idle after its duration")
	visual.call("play_telegraph", 7, &"quake", 0.6)
	drive_visual(visual, 0.14)
	var telegraph_heat := visual_emission_energy(visual)
	check(telegraph_heat >= 1.68, "telegraph heat remains fully hot")
	drive_visual(visual, 0.6)
	visual.call("play_cinematic", &"intro_full", 5.0)
	check(StringName(visual.get("_cinematic_mode")) == &"intro_full", "full intro cinematic mode is recorded")
	check(StringName(visual.get("_state")) == &"intro", "full cinematic enters intro state")
	var full_pose_progress := float(intro_pose_at.get(&"intro_full", 0.40))
	var full_hold_end := float(intro_hold_until.get(&"intro_full", 0.66))
	visual.call("set_cinematic_progress", &"intro_full", full_pose_progress * 0.5)
	var full_mid_window_poses := skeleton_pose_snapshot(adapter)
	var full_mid_window_position := (adapter.get("animation_player") as AnimationPlayer).current_animation_position if adapter != null else 0.0
	visual.call("set_cinematic_progress", &"intro_full", full_pose_progress)
	var full_landed_poses := skeleton_pose_snapshot(adapter)
	visual.call("set_cinematic_progress", &"intro_full", 0.65)
	var full_hold_poses := skeleton_pose_snapshot(adapter)
	var intro_hold_heat := visual_emission_energy(visual)
	visual.call("set_cinematic_progress", &"intro_full", full_hold_end)
	var full_hold_end_poses := skeleton_pose_snapshot(adapter)
	var intro_late_hold_heat := visual_emission_energy(visual)
	check(bone_pose_snapshots_match(full_landed_poses, full_hold_poses) and bone_pose_snapshots_match(full_landed_poses, full_hold_end_poses), "full intro holds every bone from INTRO_POSE_AT through INTRO_HOLD_UNTIL")
	check(intro_hold_heat >= 1.68 and is_equal_approx(intro_hold_heat, intro_late_hold_heat), "full intro eyes and reactor stay hot through the shared hold")
	visual.call("set_cinematic_progress", &"intro_full", 0.94)
	check(bone_pose_snapshots_match(full_landed_poses, skeleton_pose_snapshot(adapter)) and is_equal_approx(float(visual.get("_age")), 4.7), "full intro skip jump lands on the held pose and requested cinematic time")
	var frozen_cinematic_age := float(visual.get("_age"))
	var frozen_cinematic_pose := (adapter.get("animation_player") as AnimationPlayer).current_animation_position if adapter != null else 0.0
	visual.call("set_time_factor", 0.5)
	drive_visual(visual, 0.75)
	check(is_equal_approx(float(visual.get("_age")), frozen_cinematic_age), "time factor and process delta do not advance cinematic age")
	if adapter != null:
		var player := adapter.get("animation_player") as AnimationPlayer
		check(is_equal_approx(player.current_animation_position, frozen_cinematic_pose), "time factor and process delta do not advance cinematic pose")
	visual.call("set_cinematic_progress", &"intro_full", 0.9)
	var full_hold_position := (adapter.get("animation_player") as AnimationPlayer).current_animation_position if adapter != null else 0.0
	visual.call("set_cinematic_progress", &"intro_full", 0.95)
	if adapter != null:
		check(is_equal_approx((adapter.get("animation_player") as AnimationPlayer).current_animation_position, full_hold_position), "full intro holds the completed action pose")
	visual.call("set_cinematic_progress", &"intro_full", 1.0)
	check(StringName(visual.get("_state")) == &"idle", "full intro cinematic returns to idle")
	visual.call("play_cinematic", &"intro_short", 2.5)
	check(StringName(visual.get("_cinematic_mode")) == &"intro_short", "short intro cinematic mode is recorded")
	var short_pose_progress := float(intro_pose_at.get(&"intro_short", 0.28))
	var short_hold_end := float(intro_hold_until.get(&"intro_short", 0.88))
	visual.call("set_cinematic_progress", &"intro_short", short_pose_progress * 0.5)
	var short_mid_window_poses := skeleton_pose_snapshot(adapter)
	var short_mid_window_position := (adapter.get("animation_player") as AnimationPlayer).current_animation_position if adapter != null else 0.0
	check(bone_pose_snapshots_match(full_mid_window_poses, short_mid_window_poses), "full/short intro poses match at equal fractions of each shared action window")
	check(is_equal_approx(full_mid_window_position, short_mid_window_position), "equal action-window fractions sample the same imported animation time")
	check((5.0 * full_pose_progress) > 2.0 * (2.5 * short_pose_progress), "short intro reaches its held pose more than twice as quickly in wall time")
	visual.call("set_cinematic_progress", &"intro_short", short_pose_progress)
	var short_landed_poses := skeleton_pose_snapshot(adapter)
	visual.call("set_cinematic_progress", &"intro_short", 0.85)
	var short_hold_poses := skeleton_pose_snapshot(adapter)
	var short_hold_heat := visual_emission_energy(visual)
	visual.call("set_cinematic_progress", &"intro_short", short_hold_end)
	var short_hold_end_poses := skeleton_pose_snapshot(adapter)
	var short_late_hold_heat := visual_emission_energy(visual)
	check(bone_pose_snapshots_match(short_landed_poses, short_hold_poses) and bone_pose_snapshots_match(short_landed_poses, short_hold_end_poses), "short intro holds every bone from INTRO_POSE_AT through INTRO_HOLD_UNTIL")
	check(bone_pose_snapshots_match(full_hold_poses, short_hold_poses), "full .65 and short .85 holds share identical bone poses")
	check(short_hold_heat >= 1.68 and is_equal_approx(short_hold_heat, short_late_hold_heat), "short intro eyes and reactor stay hot through the shared hold")
	visual.call("set_cinematic_progress", &"intro_short", 0.96)
	check(bone_pose_snapshots_match(short_landed_poses, skeleton_pose_snapshot(adapter)) and is_equal_approx(float(visual.get("_age")), 2.4), "short intro skip jump lands on the held pose and requested cinematic time")
	visual.call("set_cinematic_progress", &"intro_short", 1.0)
	check(StringName(visual.get("_state")) == &"idle", "short intro cinematic returns to idle")
	visual.call("play_cinematic", &"defeat_full", 2.0)
	visual.call("set_cinematic_progress", &"defeat_full", 0.005)
	var strobe_on := visual_flash(visual)
	var defeat_pose_at_strobe := (adapter.get("animation_player") as AnimationPlayer).current_animation_position if adapter != null else 0.0
	visual.call("set_cinematic_progress", &"defeat_full", 0.02)
	var strobe_off := visual_flash(visual)
	check(strobe_on >= 0.8 and strobe_off < strobe_on, "full defeat begins with a hit-stop pose and a flash strobe")
	if adapter != null:
		check(is_equal_approx((adapter.get("animation_player") as AnimationPlayer).current_animation_position, defeat_pose_at_strobe), "defeat hit-stop holds the captured pose")
	var frozen_defeat_age := float(visual.get("_age"))
	var frozen_defeat_dissolve := visual_dissolve(visual)
	visual.call("set_time_factor", 1.0)
	drive_visual(visual, 0.75)
	check(is_equal_approx(float(visual.get("_age")), frozen_defeat_age), "process delta cannot advance defeat cinematic progress")
	check(is_equal_approx(visual_dissolve(visual), frozen_defeat_dissolve), "process delta cannot advance defeat dissolve")
	visual.call("set_cinematic_progress", &"defeat_full", 0.6)
	var dissolve_at_60 := visual_dissolve(visual)
	visual.call("set_cinematic_progress", &"defeat_full", 0.9)
	var dissolve_at_90 := visual_dissolve(visual)
	visual.call("set_cinematic_progress", &"defeat_full", 1.0)
	var final_dissolve := visual_dissolve(visual)
	check(final_dissolve >= 0.99, "full cinematic defeat reaches dissolve 1")
	check(dissolve_at_60 >= 0.0 and dissolve_at_60 < final_dissolve, "full cinematic defeat progresses to dissolve during its final section")
	check(dissolve_at_90 > dissolve_at_60, "full cinematic dissolve advances toward completion")
	check(bool(visual.get("_terminal")) and StringName(visual.get("_state")) == &"defeat", "full cinematic defeat remains terminal")
	visual.call("set_cinematic_progress", &"defeat_full", 0.45)
	var emission_at_45 := visual_emission_energy(visual)
	var dissolve_at_45 := visual_dissolve(visual)
	visual.call("set_cinematic_progress", &"defeat_full", 0.8)
	var emission_at_80 := visual_emission_energy(visual)
	var dissolve_at_80 := visual_dissolve(visual)
	check(is_equal_approx(emission_at_45, 1.0) and emission_at_80 <= 0.01, "defeat emissive atlas fades to zero by normalized progress 0.80")
	check(dissolve_at_45 <= 0.01 and is_equal_approx(dissolve_at_80, (0.8 - 0.55) / 0.45), "emission fade leaves the cinematic dissolve curve unchanged")
	visual.call("play_cinematic", &"defeat_short", 1.0)
	check(StringName(visual.get("_cinematic_mode")) == &"defeat_short", "short defeat cinematic mode is recorded")
	visual.call("set_cinematic_progress", &"defeat_short", 0.9)
	check(is_equal_approx(visual_dissolve(visual), dissolve_at_90), "short and full defeat share normalized dissolve progress")
	visual.call("set_cinematic_progress", &"defeat_short", 1.0)
	check(visual_dissolve(visual) >= 0.99, "short cinematic defeat reaches dissolve 1")
	visual.call("on_spawned")
	check(StringName(visual.get("_state")) == &"idle" and not bool(visual.get("_terminal")), "on_spawned resets the defeated visual for replay")
	check(is_equal_approx(visual_dissolve(visual), 0.0), "on_spawned resets dissolve for replay")
	check(is_equal_approx(visual_emission_energy(visual), phase_one_emission), "on_spawned restores the normal glow for replay")
	var second_visual := script.new() as Node3D
	second_visual.set("kind", &"legacy_monolith")
	second_visual.set("hover_z", -14.0)
	root.add_child(second_visual)
	second_visual.set("model_path", MODEL_PATH)
	second_visual.call("on_spawned")
	check(visual_dissolve_color(second_visual).is_equal_approx(Color("f78949")), "second visual instance also uses reactor orange for dissolve")
	var first_materials: Array = adapter.get("materials") if adapter != null else []
	var second_adapter := second_visual.get("_model") as Node3D
	var second_materials: Array = second_adapter.get("materials") if second_adapter != null else []
	check(not first_materials.is_empty() and not second_materials.is_empty() and first_materials[0] != second_materials[0], "visual instances keep dissolve materials isolated")
	second_visual.free()

	var fallback_visual := script.new() as Node3D
	fallback_visual.set("kind", &"legacy_monolith")
	fallback_visual.set("hover_z", -14.0)
	var fallback_mount := Node3D.new()
	fallback_mount.position = EXPECTED_MOUNT
	root.add_child(fallback_mount)
	fallback_mount.add_child(fallback_visual)
	check(property_exists(fallback_visual, &"model_path"), "fallback visual exposes public model_path")
	if property_exists(fallback_visual, &"model_path"):
		fallback_visual.set("model_path", "res://Assets/runner/bosses/legacy_monolith/missing.glb")
	fallback_visual.call("on_spawned")
	check(fallback_visual.get("_model") == null, "missing configured model path falls back instead of mounting a partial adapter")
	check(fallback_visual.get("_art") != null, "missing configured model path builds procedural Legacy Monolith art")
	check(fallback_visual.global_position.distance_to(EXPECTED_MOUNT) <= 0.02, "procedural fallback preserves the boss mount")
	if fallback_visual.get("_art") != null:
		var fallback_bounds := procedural_art_bounds(fallback_visual.get("_art"))
		check_bounds_match(fallback_bounds, BASELINE_BOUNDS, 0.08, "procedural fallback")
	check_world_envelope_contract(visual, adapter)
	mount.free()
	fallback_mount.free()


func check_socket_motion(adapter: Node3D) -> void:
	var socket := adapter.call("socket", &"muzzle_1") as Node3D
	var player := adapter.get("animation_player") as AnimationPlayer
	var model := adapter.get("model") as Node3D
	check(socket != null and player != null and model != null, "animated arm socket test has its socket, player, and model")
	if socket == null or player == null or model == null or not player.has_animation(&"attack"):
		return
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	check(not skeletons.is_empty(), "imported model has a skeleton for its arm socket")
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var arm_index := skeleton.find_bone("arm_L")
	check(arm_index >= 0, "Legacy Monolith skeleton includes the left arm bone")
	if arm_index < 0:
		return
	player.stop()
	player.speed_scale = 0.0
	player.play(&"attack", 0.0)
	player.seek(0.0, true)
	await process_frame
	skeleton.force_update_all_bone_transforms()
	var start := socket.global_position
	var initial_arm_pose := skeleton.get_bone_global_pose(arm_index)
	player.seek(player.get_animation(&"attack").length * 0.5, true)
	await process_frame
	skeleton.force_update_all_bone_transforms()
	var middle_arm_pose := skeleton.get_bone_global_pose(arm_index)
	check(not middle_arm_pose.is_equal_approx(initial_arm_pose), "arm bone changes pose during attack")
	check(socket.global_position.distance_to(start) > 0.01, "arm-mounted muzzle socket moves after an animation frame")
	player.speed_scale = 1.0


func sample_action(adapter: Node3D, action: StringName, progress: float) -> Skeleton3D:
	var player := adapter.get("animation_player") as AnimationPlayer
	var model := adapter.get("model") as Node3D
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if player == null or skeletons.is_empty() or not player.has_animation(action):
		return null
	var skeleton := skeletons[0] as Skeleton3D
	player.stop()
	player.speed_scale = 0.0
	player.play(action, 0.0)
	player.seek(player.get_animation(action).length * clampf(progress, 0.0, 1.0), true)
	await process_frame
	skeleton.force_update_all_bone_transforms()
	return skeleton


func bone_offset(skeleton: Skeleton3D, bone_name: String) -> Transform3D:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return Transform3D.IDENTITY
	return skeleton.get_bone_global_rest(index).affine_inverse() * skeleton.get_bone_global_pose(index)


func bone_world_shift(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.ZERO
	return skeleton.get_bone_global_pose(index).origin - skeleton.get_bone_global_rest(index).origin


func bone_rotation_amount(offset: Transform3D) -> float:
	return offset.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)


func check_reviewed_animation_poses(adapter: Node3D) -> void:
	var intro_start := await sample_action(adapter, &"intro", 0.0)
	check(intro_start != null, "intro start pose samples from imported GLB")
	if intro_start == null:
		return
	var root_start := bone_world_shift(intro_start, "root")
	check(absf(root_start.y) <= 0.05 and root_start.z <= -3.8, "intro begins at floor height and enters from at least 3.8 m toward the far end")

	var intro_end := await sample_action(adapter, &"intro", 1.0)
	if intro_end != null:
		var tower := bone_offset(intro_end, "tower")
		var arm_left := bone_offset(intro_end, "arm_L")
		var arm_right := bone_offset(intro_end, "arm_R")
		check(bone_rotation_amount(tower) >= 0.06, "intro end leans the tower forward")
		check(bone_rotation_amount(arm_left) >= 0.25 and bone_rotation_amount(arm_right) >= 0.25, "intro end raises both arms into the power-up stance")
		check(bone_world_shift(intro_end, "arm_L").y >= 0.08 and bone_world_shift(intro_end, "arm_R").y >= 0.08, "intro end lifts both arm joints from rest")

	var hurt := await sample_action(adapter, &"hurt", 0.375)
	if hurt != null:
		var rack := bone_offset(hurt, "rack_1")
		check(rack.origin.x >= 0.28, "hurt slides rack one at least 0.28 m sideways")
		check(absf(rack.origin.z) <= 0.03, "hurt rack jolt has no significant view-axis displacement")
		check(bone_rotation_amount(rack) >= 0.055, "hurt yaws rack one")

	var defeat := await sample_action(adapter, &"defeat", 0.98)
	if defeat != null:
		var head := bone_offset(defeat, "rack_3")
		var rack_two := bone_offset(defeat, "rack_2")
		check(head.origin.y <= -1.0, "defeat drops the head rack at least 1 m")
		check(bone_rotation_amount(head) >= 0.70, "defeat pitches the head rack forward")
		check(rack_two.origin.x <= -0.40, "defeat shears rack two at least 0.4 m sideways")

	var slam_plateau_a := await sample_action(adapter, &"attack", 0.32)
	var slam_plateau_b := await sample_action(adapter, &"attack", 0.40)
	if slam_plateau_a != null and slam_plateau_b != null:
		var fist_a := bone_world_shift(slam_plateau_a, "hand_L")
		var fist_b := bone_world_shift(slam_plateau_b, "hand_L")
		var arm_a := bone_world_shift(slam_plateau_a, "arm_L")
		var arm_b := bone_world_shift(slam_plateau_b, "arm_L")
		check(arm_a.y <= -0.39 and arm_a.z >= 0.30 and fist_a.y <= -0.39, "quake slam drives the arm and fist down while reaching forward (arm=%s fist=%s)" % [arm_a, fist_a])
		check(fist_a.distance_to(fist_b) <= 0.04, "quake slam holds a plateau from 0.32 to 0.40 normalized time")
		check(arm_a.distance_to(arm_b) <= 0.04, "quake slam holds the arm pose through the impact plateau")


func run() -> void:
	await process_frame
	check(FileAccess.file_exists(MODEL_SCRIPT_PATH), "BossModel loader script exists")
	check(FileAccess.file_exists(VISUAL_SCRIPT_PATH), "Legacy Monolith visual script exists")
	var report := check_report()
	if FileAccess.file_exists(MODEL_SCRIPT_PATH):
		var model_script := load(MODEL_SCRIPT_PATH) as Script
		check(model_script != null, "BossModel loader script loads")
		if model_script != null:
			check(model_script.call("load_model", "res://Assets/runner/bosses/legacy_monolith/missing.glb") == null, "BossModel returns null for a missing model path")
			if FileAccess.file_exists(MODEL_PATH):
				var adapter := model_script.call("load_model", MODEL_PATH) as Node3D
				if adapter != null:
					root.add_child(adapter)
				check_adapter(adapter, report)
				if adapter != null:
					await check_socket_motion(adapter)
					await check_reviewed_animation_poses(adapter)
					adapter.free()
	check_visual_contract()
	finish()


func finish() -> void:
	call_deferred("finish_after_cleanup")


func finish_after_cleanup() -> void:
	print("LEGACY MONOLITH CHECK: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
