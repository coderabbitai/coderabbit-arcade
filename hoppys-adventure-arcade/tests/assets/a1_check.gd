extends SceneTree
const Guard = preload("res://scenes/runner/player/hifi/palette_guard.gd")
const Capture = preload("res://scenes/runner/player/dev/capture_a1.gd")
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
const STATES: Array[StringName] = [&"idle", &"run", &"jump", &"fall", &"roll", &"hurt", &"dead"]
const BASE := "res://Assets/runner/hoppy/"
var _skin_centroid := Vector3.ZERO
var checks := 0
var failures := 0
var textures: Dictionary = {}
var draws := 0
var triangles := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A1: " + message)

func material_textures(material: Material) -> void:
	if material is BaseMaterial3D:
		for slot in BaseMaterial3D.TEXTURE_MAX:
			var texture: Texture2D = material.get_texture(slot)
			if texture != null:
				textures[texture.get_instance_id()] = texture

	elif material is ShaderMaterial:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(uniform.name)
			if value is Texture2D:
				textures[value.get_instance_id()] = value

func mesh_census(mesh: Mesh, count: int = 1) -> void:
	for surface in mesh.get_surface_count():
		draws += 1
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3 * count
		material_textures(mesh.surface_get_material(surface))

func census(node: Node) -> void:
	check(node.process_mode == Node.PROCESS_MODE_PAUSABLE, "pausable " + str(node.name))
	check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "interpolation off " + str(node.name))
	if node is MeshInstance3D:
		mesh_census(node.mesh)
		material_textures(node.material_override)
		for surface in node.mesh.get_surface_count():
			material_textures(node.get_surface_override_material(surface))
	elif node is MultiMeshInstance3D:
		mesh_census(node.multimesh.mesh, node.multimesh.instance_count)
		material_textures(node.material_override)
	elif node is GPUParticles3D:
		mesh_census(node.draw_pass_1, node.amount)
	for child in node.get_children():
		census(child)

func skin_bounds(hoppy: Node3D) -> AABB:
	var sk: Skeleton3D = hoppy.skeleton
	sk.force_update_all_bone_transforms()
	var first := true
	var sum := Vector3.ZERO
	var count := 0
	var result := AABB()
	for mesh: MeshInstance3D in hoppy._meshes:
		var skin := mesh.skin
		var transforms: Array[Transform3D] = []
		for bind in skin.get_bind_count():
			var bone := skin.get_bind_bone(bind)
			if bone < 0:
				bone = sk.find_bone(skin.get_bind_name(bind))
			assert(bone >= 0, "Unknown skin bone")
			transforms.append(sk.global_transform * sk.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / vertices.size()
			for i in vertices.size():
				var point := Vector3.ZERO
				for j in stride:
					var weight := weights[i * stride + j]
					if weight > 0:
						point += (transforms[bones[i * stride + j]] * vertices[i]) * weight
				sum += point
				count += 1
				result = AABB(point, Vector3.ZERO) if first else result.expand(point)
				first = false
	_skin_centroid = sum / maxf(count, 1)
	return result

func sample(hoppy: Node3D, state: StringName, time: float) -> void:
	check(Capture.pose_for_view(hoppy, state, time), "capture sampler selects " + state)
	hoppy._process(0.0)

func check_joints(hoppy: Node3D) -> void:
	var sk: Skeleton3D = hoppy.skeleton
	var player: AnimationPlayer = hoppy.animation_player
	var values: Dictionary = {}
	for state in STATES:
		var ranges: Dictionary = {}
		for name in ["forearm_L", "forearm_R", "shin_L", "shin_R"]:
			ranges[name] = Vector2(INF, -INF)
		for frame in 25:
			Capture.pose_for_view(hoppy, state, player.get_animation(state).length * frame / 24.0)
			sk.force_update_all_bone_transforms()
			for name: String in ranges:
				var bone := sk.find_bone(name)
				var parent := sk.get_bone_parent(bone)
				var rest := (sk.get_bone_global_rest(parent).affine_inverse() * sk.get_bone_global_rest(bone)).basis.orthonormalized()
				var posed := sk.get_bone_global_pose(parent).affine_inverse() * sk.get_bone_global_pose(bone)
				var direction := posed.basis.orthonormalized() * Vector3.UP
				var angle := (rest * Vector3.UP).signed_angle_to(direction, rest * Vector3.RIGHT)
				var flexion := angle * (-1.0 if name.begins_with("shin") else 1.0)
				if state == &"run" and name.begins_with("shin"):
					if frame in [0, 12, 24]:
						check(flexion >= 0.34 and flexion <= 0.46, "contact-quarter knee absorption " + name + " frame " + str(frame))
					if (name == "shin_R" and frame == 6) or (name == "shin_L" and frame == 18):
						check(flexion >= 0.20 and flexion <= 0.26, "mid-stance knee extension " + name)
				var span: Vector2 = ranges[name]
				ranges[name] = Vector2(minf(span.x, flexion), maxf(span.y, flexion))
		for name: String in ranges:
			var span: Vector2 = ranges[name]
			var knee := name.begins_with("shin")
			check(span.x >= -0.01 and span.y <= (1.91 if knee else 1.76), "anatomical bend direction and clamp " + str(state) + " " + name)
			if state == &"run":
				check(span.y >= (1.4 if knee else 1.2), "run joint flexion " + name)
				check(span.x >= (0.15 if knee else 1.19) and span.y <= (1.7 if knee else 1.61), "run flexion band " + name)
				if knee:check(span.x >= 0.20 and span.x <= 0.26, "run shin minimum remains near 0.22 " + name)
			if state == &"idle":
				check(span.x >= (0.15 if knee else 0.25) and span.y <= (0.25 if knee else 0.4), "soft idle flexion " + name)
			if state == &"jump":
				check(span.y >= (1.2 if knee else 0.9), "jump tuck flexion " + name)
			if state == &"fall":
				check(span.x >= (0.4 if knee else 0.6) and span.y <= (0.7 if knee else 0.9), "fall relaxed extension " + name)
			if state == &"roll":
				check(span.x >= (1.8 if knee else 1.6), "full roll tuck " + name)
			if state == &"hurt" and not knee:
				check(span.y >= 1.0, "hurt elbow flinch " + name)
			if state == &"dead":
				check(span.x >= 0.3 and span.y <= 0.6, "relaxed dead joints " + name)
		values[state] = ranges
	print("A1 JOINTS: ", values)
	for state in [&"idle", &"run"]:
		for frame in 25:
			Capture.pose_for_view(hoppy, state, player.get_animation(state).length * frame / 24.0)
			var left := Capture.limb_bounds(hoppy, ["foot_L"])
			var right := Capture.limb_bounds(hoppy, ["foot_R"])
			check(left.position.y >= -0.003 and right.position.y >= -0.003 and absf(minf(left.position.y, right.position.y)) < 0.008, "planted sole %s frame %d: min_y=%.4f left_y=%.4f right_y=%.4f" % [state, frame, minf(left.position.y, right.position.y), left.position.y, right.position.y])
	# Match the export rate; catch import resampling/optimization regressions too.
	for state in [&"idle", &"run"]:
		var low := INF
		var high := -INF
		var steps := int(round(player.get_animation(state).length * 120.0))
		for frame in steps + 1:
			Capture.pose_for_view(hoppy, state, player.get_animation(state).length * frame / steps)
			var sole := Capture.limb_bounds(hoppy, ["foot_L", "foot_R"])
			low = minf(low, sole.position.y)
			high = maxf(high, sole.position.y)
		print("A1 SOLE SWEEP %s: 120 Hz min_y=%.6f max_y=%.6f samples=%d" % [state, low, high, steps + 1])
		check(low >= -0.002 and high <= 0.007, "120 Hz sole band " + state)
	Capture.pose_for_view(hoppy, &"jump", 7.5 / 30.0)
	var tuck := Capture.jump_tuck_metrics(hoppy)
	print("A1 JUMP TUCK: ", tuck)
	check(tuck["pass"], "jump skeleton heel lifts toward hips: " + str(tuck))
	Capture.pose_for_view(hoppy, &"idle", 0.0)

func run() -> void:
	await process_frame
	root.get_node("AudioService").music.stop()
	var imported := load(BASE + "hoppy.glb") as PackedScene
	check(imported != null, "GLB loads")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "hoppy.build.json"))
	var file := FileAccess.open(BASE + "hoppy.glb", FileAccess.READ)
	check(file.get_32() == 0x46546c67 and file.get_32() == 2, "GLB header")
	check(file.get_32() == file.get_length(), "GLB length")
	var json_length := file.get_32()
	check(file.get_32() == 0x4e4f534a, "GLB JSON chunk")
	var gltf: Dictionary = JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
	check(report.script_sha256 == gltf.asset.extras.build_script_sha256, "sidecar matches embedded generator hash")
	check(report.generator == gltf.asset.generator and report.blender == "5.2.2 LTS", "generator provenance")
	check(FileAccess.get_sha256("res://tools/blender/build_hoppy.py") == report.script_sha256, "build script hash matches asset")
	check(report.get("contact_revision", 0) == 16, "120 Hz contact recipe revision retained")
	check(report.get("joint_revision", 0) == 14, "round-14 articulated limb bake required")
	check(report.get("recipe_revision", 0) == 6, "round-6 bake required: palette and brace corrections")
	if report.get("recipe_revision", 0) == 6:
		var rgb: Array = report.hoodie_linear
		check(Vector3(rgb[0], rgb[1], rgb[2]).is_equal_approx(Vector3(0.930, 0.250, 0.067)), "baked recipe uses palette orange")
		var profile: Array = report.brace_profile
		check(profile[3][0] > profile[0][0] and profile[3][0] > profile[-1][0], "brace cusp outward, tips inward")
		check(report.back_mark_z > 0.262, "back brace clears battery face")
		check(Vector2(report.sole_radii[0], report.sole_radii[1]).is_equal_approx(Vector2(0.108, 0.162)), "sole follows sneaker plus 8 mm")
	for script in ["build_hoppy.py", "render_hoppy.py", "glb_atlas.py", "rebuild_hoppy.py"]:
		check(FileAccess.file_exists("res://tools/blender/" + script), "pipeline script " + script)
	var names: Array = []
	for action: Dictionary in gltf.animations:
		names.append(action.name)
	var expected: Array = report.animations.duplicate()
	names.sort()
	expected.sort()
	check(names == expected and names.size() == 7, "sidecar action list matches GLB")
	var png_names: Array = []
	for info: Dictionary in report.image_report:
		png_names.append(info.name + ".png")
		check(not FileAccess.file_exists(BASE + info.name + ".png"), "no redundant loose PNG " + info.name)
	png_names.sort()
	check(png_names == report.textures and gltf.images.size() == 8 and gltf.textures.size() == 8, "sidecar texture list and embedded count")
	check(not DirAccess.dir_exists_absolute(BASE + "source"), "no redundant third texture copy")
	for material: Dictionary in gltf.materials:
		check(material.occlusionTexture.index == material.pbrMetallicRoughness.metallicRoughnessTexture.index, "shared ORM " + material.name)
	var model_tris := 0
	for mesh: Dictionary in gltf.meshes:
		for primitive: Dictionary in mesh.primitives:
			model_tris += int(gltf.accessors[primitive.indices].count) / 3
	check(model_tris == int(report.triangles), "sidecar triangle census matches GLB")
	var hoppy := Hoppy.instantiate()
	hoppy.show_shield(true)
	root.add_child(hoppy)
	hoppy.set_process(false)
	hoppy._look.active = false
	var player: AnimationPlayer = hoppy.animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_default_blend_time = 0.0
	check(hoppy.find_children("*", "Light3D", true, false).is_empty(), "palette uses no clipping fill light")
	var surface_shader := preload("res://scenes/runner/player/hifi/hoppy_surface.gdshader")
	var glass_shader := preload("res://scenes/runner/player/hifi/hoppy_glass.gdshader")
	var shared := FileAccess.get_file_as_string("res://scenes/runner/player/hifi/hoppy_surface.gdshaderinc")
	check(not (surface_shader.code + glass_shader.code + shared).contains("TIME"), "surface shaders have no global time")
	check(shared.contains("ambient_energy * orm.r"), "ambient fill weighted by baked occlusion")
	check(glass_shader.code.contains("blend_mix, depth_prepass_alpha, cull_back") and shared.contains("ALPHA = albedo_color.a * texel.a"), "glass preserves alpha with reviewed render modes")
	check(surface_shader.code.contains("cull_back, depth_draw_opaque") and not surface_shader.code.contains("#define HOPPY_GLASS"), "body remains opaque and back culled")
	var glass_count := 0
	var mask_source := FileAccess.get_file_as_string("res://scenes/runner/player/hifi/palette_mask.gdshader")
	check(mask_source.contains("texel.a * albedo_color.a < 0.5") and mask_source.contains("discard"), "guard excludes transparent glass")
	check(mask_source.contains("> 1.12"), "fur mask excludes neutral whites")
	var band := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	band.fill(Color("a9b48d"))
	check(Capture.measure_goggle_band(band)["pass"], "studio guard accepts authored mint veil")
	band.fill(Color("62a48c"))
	check(not Capture.measure_goggle_band(band)["pass"], "studio guard rejects opaque lens regression")
	for mesh: MeshInstance3D in hoppy._meshes:
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			var source := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				glass_count += 1
				check(material != null and material.shader == glass_shader, "goggles use transparent glass variant")
				var tint: Color = material.get_shader_parameter("albedo_color")
				check(is_equal_approx(tint.a, 0.22) and tint == source.albedo_color, "goggle alpha preserves authored 0.22")
			else:
				check(material != null and material.shader == surface_shader, "body uses opaque hue-preserving shader")
			check(material.get_shader_parameter("chroma_lock") >= 0.75, "chroma lock preserved")
			var gain: float = material.get_shader_parameter("light_gain")
			var ambient: float = material.get_shader_parameter("ambient_energy")
			check(gain >= 0.4 and gain <= 0.7, "compressed direct lighting gain")
			check(ambient >= 0.25 and ambient <= 0.45, "lifted ambient budget")
			check(source.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED and source.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN and source.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "glTF ORM channels RGB")
			check(source.get_texture(BaseMaterial3D.TEXTURE_METALLIC) == source.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS) and source.get_texture(BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION) == material.get_shader_parameter("orm_map"), "one shared ORM image")
	check(glass_count == 1, "exactly one goggle glass surface")
	var synthetic := Image.create(16, 2, false, Image.FORMAT_RGB8)
	var mask := Image.create(16, 2, false, Image.FORMAT_RGB8)
	for x in 16:
		synthetic.set_pixel(x, 0, Capture.Palette.ORANGE)
		synthetic.set_pixel(x, 1, Capture.Palette.CREAM * 0.8)
		mask.set_pixel(x, 0, Color.RED)
		mask.set_pixel(x, 1, Color.GREEN)
	check(Guard.measure(synthetic, mask)["pass"], "synthetic palette accepted")
	var full_image := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	var full_mask := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	full_image.blit_rect(synthetic, Rect2i(0, 0, 16, 2), Vector2i(600, 300))
	full_mask.blit_rect(mask, Rect2i(0, 0, 16, 2), Vector2i(600, 300))
	var guard_started := Time.get_ticks_msec()
	check(Guard.measure(full_image, full_mask)["pass"], "full viewport byte guard retains small masks")
	print("A1 GUARD CPU: %d ms for 1280x720" % (Time.get_ticks_msec() - guard_started))
	# Keep hue valid while varying exposure independently for each class.
	var measured := Guard.measure(synthetic, mask)
	var cream := Capture.Palette.CREAM * 0.8
	check(absf(measured.fur_luma - (0.2126 * cream.r + 0.7152 * cream.g + 0.0722 * cream.b)) < 0.005, "Rec709 luma on saved sRGB bytes")
	for row in 2:
		var color: Color = Capture.Palette.ORANGE if row == 0 else Capture.Palette.CREAM
		for factor: float in [0.2, 1.0]:
			var exposed := color * factor
			if row == 0 and factor == 1.0:
				exposed = color.lerp(Color.WHITE, 0.65)
			for x in 16:
				synthetic.set_pixel(x, row, exposed)
			check(not Guard.measure(synthetic, mask)["pass"], "reject class %d exposure %s with valid hue" % [row, factor])
		for x in 16:
			synthetic.set_pixel(x, row, color if row == 0 else color * 0.8)
	synthetic.fill(Color(0.45, 0.55, 0.2))
	check(not Guard.measure(synthetic, mask)["pass"], "synthetic khaki rejected independently of mask")
	synthetic.fill(Color.WHITE)
	check(not Guard.measure(synthetic, mask)["pass"], "synthetic blown highlights rejected")
	check(hoppy._shield.visible, "shield request before ready")
	check(player.get_animation_list().size() == 7, "exactly seven actions")
	var import_settings := ConfigFile.new()
	check(import_settings.load(BASE + "hoppy.glb.import") == OK and import_settings.get_value("params", "animation/fps") == 120, "import preserves 120 Hz animation sampling")
	var root_position_keys := 0
	var run_clip := player.get_animation(&"run")
	for track in run_clip.get_track_count():
		if run_clip.track_get_type(track) == Animation.TYPE_POSITION_3D and str(run_clip.track_get_path(track)).ends_with(":root"):
			root_position_keys = run_clip.track_get_key_count(track)
	check(root_position_keys >= 73, "import retains grounded run root keys")
	var expected_lengths := {&"idle": 1.6, &"run": 0.6, &"jump": 0.5, &"fall": 0.8, &"roll": 0.8, &"hurt": 0.6, &"dead": 1.2}
	for state in STATES:
		check(is_equal_approx(player.get_animation(state).length, expected_lengths[state]), "clip duration preserved " + state)
		check(player.has_animation(state), "action " + state)
		var loop := Animation.LOOP_LINEAR if state in [&"idle", &"run", &"fall"] else Animation.LOOP_NONE
		check(player.get_animation(state).loop_mode == loop, "loop flag " + state)
	for bone: String in report.bones:
		check(hoppy.skeleton.find_bone(bone) >= 0, "bone " + bone)
	check(hoppy.skeleton.get_bone_count() == 27, "bone count")
	for hook in ["set_anim_state", "set_run_speed", "set_lane_lean", "show_aura", "show_shield", "on_hit"]:
		check(hoppy.has_method(hook), "hook " + hook)
	var imported_tris := 0
	for mesh: MeshInstance3D in hoppy._meshes:
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			imported_tris += indices.size() / 3
	check(imported_tris == model_tris, "Godot imported triangle census matches sidecar")
	census(hoppy)
	check(draws <= 40 and triangles <= 40000 and textures.size() <= 8, "whole-visual budgets")
	var budget: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/blender/hoppy_budget.json"))
	check(triangles - model_tris == int(budget.effect_triangles), "measured effects match shared Blender budget")
	for texture: Texture2D in textures.values():
		var limit := 1024 if texture.resource_path.contains("accessory") else 2048
		check(texture.get_width() <= limit and texture.get_height() <= limit, "atlas-specific texture dimensions")
		var settings := ConfigFile.new()
		check(settings.load(texture.resource_path + ".import") == OK, "runtime texture import exists")
		check(settings.get_value("params", "compress/mode") == 0, "Compatibility lossless texture import")
		check(texture.get_image().has_mipmaps(), "imported atlas mipmaps present")
	print("A1 CENSUS: %d draws, %d triangles, %d textures; imported model %d triangles" % [draws, triangles, textures.size(), model_tris])
	player.stop()
	hoppy.skeleton.reset_bone_poses()
	var standing := skin_bounds(hoppy)
	print("A1 STANDING: ", standing)
	check(absf(standing.position.y) < 0.002 and absf(standing.end.y - 1.8) < 0.002, "feet 0 and height 1.8")
	var sk: Skeleton3D = hoppy.skeleton
	check(sk.get_bone_global_rest(sk.find_bone("eye_L")).origin.z < sk.get_bone_global_rest(sk.find_bone("head")).origin.z, "eyes face negative Z")
	# Exercise the exact fixture sampler with runtime cross-fades enabled.
	player.playback_default_blend_time = 0.08
	sample(hoppy, &"idle", 0.24)
	var idle_arm := sk.get_bone_pose_rotation(sk.find_bone("arm_L"))
	var idle_leg := sk.get_bone_pose_rotation(sk.find_bone("leg_L"))
	var idle_bounds := skin_bounds(hoppy)
	var idle_centroid := _skin_centroid
	sample(hoppy, &"run", 0.24)
	var arm_delta := idle_arm.angle_to(sk.get_bone_pose_rotation(sk.find_bone("arm_L")))
	var leg_delta := idle_leg.angle_to(sk.get_bone_pose_rotation(sk.find_bone("leg_L")))
	var run_bounds := skin_bounds(hoppy)
	var centroid_delta := idle_centroid.distance_to(_skin_centroid)
	check(arm_delta > 0.1 and leg_delta > 0.1, "capture run moves arm_L and leg_L away from idle")
	check(not idle_bounds.is_equal_approx(run_bounds) and centroid_delta > 0.005, "capture run changes whole-skin AABB and centroid")
	sample(hoppy, &"idle", 0.24)
	check(idle_arm.is_equal_approx(sk.get_bone_pose_rotation(sk.find_bone("arm_L"))) and idle_bounds.is_equal_approx(skin_bounds(hoppy)), "rear idle does not retain previous run pose")
	print("A1 CAPTURE POSE: arm delta %.6f rad, leg delta %.6f rad, centroid delta %.6f m" % [arm_delta, leg_delta, centroid_delta])
	var light_stage := Node3D.new()
	Capture.configure_lighting(light_stage)
	var key := light_stage.get_node("CorridorKey") as OmniLight3D
	check(key.position == Vector3(0, 1.8, 1) and is_equal_approx(key.light_energy, 0.65) and is_equal_approx(key.omni_range, 3.2), "capture uses corridor rear key")
	var environment := light_stage.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
	check(environment.environment.ambient_light_energy >= 0.8, "capture ambient lifted for gameplay")
	light_stage.free()
	player.playback_default_blend_time = 0.0
	var low := INF
	var high := -INF
	for frame in 12:
		sample(hoppy, &"roll", player.get_animation(&"roll").length * float(frame) / 11.0)
		var bounds := skin_bounds(hoppy)
		low = minf(low, bounds.position.y)
		high = maxf(high, bounds.end.y)
		check(bounds.position.y >= -0.001 and bounds.end.y <= 0.901, "skinned roll frame %d: %s" % [frame, bounds])
		for shell: MeshInstance3D in [hoppy._aura, hoppy._shield]:
			var shell_bounds := shell.global_transform * shell.get_aabb()
			check(shell_bounds.position.y >= 0.0 and shell_bounds.end.y <= 0.9, "roll effect envelope")
	print("A1 ROLL: 12 sampled frames, y %.6f to %.6f" % [low, high])
	sample(hoppy, &"idle", 0.0)
	var restored := skin_bounds(hoppy)
	check(absf(restored.end.y - 1.8) < 0.004, "roll exit restores upright skeleton")
	check_joints(hoppy)
	for speed in [-1.0, 0.0, 0.5, 1.0, 2.0]:
		hoppy.set_anim_state(&"run")
		hoppy.set_run_speed(speed)
		check(is_equal_approx(player.speed_scale, lerpf(0.9, 1.6, clampf(speed, 0, 1))), "run speed clamped")
	player.advance(0.1)
	var position := player.current_animation_position
	hoppy.set_anim_state(&"run")
	check(is_equal_approx(position, player.current_animation_position), "same state does not restart")
	hoppy.set_lane_lean(1)
	check(is_equal_approx(hoppy.rotation.z, -0.12) and hoppy._look.direction == 1, "lane lean and head target")
	var head_index := sk.find_bone("head")
	var head_before := sk.get_bone_pose_rotation(head_index)
	hoppy._look._process_modification()
	check(not sk.get_bone_pose_rotation(head_index).is_equal_approx(head_before), "head modifier turns toward lane")
	sk.set_bone_pose_rotation(head_index, head_before)
	hoppy.set_lane_lean(0)
	hoppy.show_aura(&"lgtm", true)
	hoppy.show_aura(&"nitro", true)
	hoppy.show_aura(&"lgtm", false)
	check(hoppy._aura.visible, "stacked auras")
	hoppy.show_aura(&"nitro", false)
	check(not hoppy._aura.visible, "aura expiry")
	hoppy.set_run_speed(1)
	hoppy._process(0.1)
	check(hoppy._trail.visible, "MATRIX trail at speed")
	for locomotion in [&"idle", &"run", &"jump", &"fall", &"roll"]:
		hoppy.set_anim_state(locomotion)
		hoppy.set_anim_state(&"hurt")
		player.advance(player.get_animation(&"hurt").length + 0.01)
		await process_frame
		check(hoppy.anim_state == locomotion, "hurt returns to " + locomotion)
	hoppy.set_anim_state(&"hurt")
	hoppy.set_anim_state(&"dead")
	player.advance(1.3)
	await process_frame
	check(hoppy.anim_state == &"dead", "dead interrupts hurt recovery")
	# Per-instance materials must not affect a second PackedScene instance.
	var other := Hoppy.instantiate()
	root.add_child(other)
	var ours: Material = hoppy._meshes[0].get_surface_override_material(0)
	var theirs: Material = other._meshes[0].get_surface_override_material(0)
	for mesh: MeshInstance3D in hoppy._meshes:
		for surface in mesh.mesh.get_surface_count():
			check(mesh.get_active_material(surface) != mesh.mesh.surface_get_material(surface), "cached GLB material remains private")
	check(ours != theirs, "private imported material copies")
	hoppy.on_hit()
	check(ours.get_shader_parameter("flash") == 1.0 and theirs.get_shader_parameter("flash") == 0.0, "isolated hit flash")
	hoppy._process(0.07)
	check(ours.get_shader_parameter("flash") == 0.0, "flash clears")
	hoppy.set_anim_state(&"run")
	hoppy.set_process(true)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	await process_frame
	paused = true
	var clock_before: float = hoppy._clock
	var frame_before := player.current_animation_position
	var bone_before := sk.get_bone_pose(sk.find_bone("root"))
	await create_timer(0.12, true).timeout
	check(hoppy._clock == clock_before and player.current_animation_position == frame_before and sk.get_bone_pose(sk.find_bone("root")) == bone_before, "pause freezes clock, animation and skeleton")
	paused = false
	await Cleanup.release(self, [hoppy, other])
	print("ASSET A1: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
