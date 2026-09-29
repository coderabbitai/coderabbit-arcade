extends SceneTree
const Guard = preload("res://scenes/runner/player/hifi/palette_guard.gd")
const Capture = preload("res://scenes/runner/player/dev/capture_a1.gd")
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
const STATES: Array[StringName] = [&"idle", &"run", &"jump", &"fall", &"roll", &"hurt", &"dead",
	&"lane_dash_left", &"lane_dash_right", &"land", &"shield_brace", &"powerup_react", &"victory"]
## Round-7 grounded one-shots: authored on the run gait and sole-grounded like idle/run.
const GAIT_CLIPS: Array[StringName] = [&"lane_dash_left", &"lane_dash_right", &"land", &"shield_brace",
	&"powerup_react", &"victory"]
const GROUNDED: Array[StringName] = [&"idle", &"run", &"lane_dash_left", &"lane_dash_right", &"land",
	&"shield_brace", &"powerup_react", &"victory"]
const FACE_BONES: Array[String] = ["eye_L", "eye_R", "brow_L", "brow_R", "mouth_L", "mouth_R"]
const TRIANGLE_CAP := 48000
const BASE := "res://Assets/runner/hoppy/"
var _skin_centroid := Vector3.ZERO
var _report: Dictionary = {}
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

func budget_cap() -> int:
	var budget: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/blender/hoppy_budget.json"))
	return int(budget.get("triangle_cap", 0))

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
			if state in [&"lane_dash_left", &"lane_dash_right"]:
				# Half stride: the leading leg (dash side) recovers high while the push-off leg
				# stays in stance and extends; elbows keep the run pump.
				var leading := name.ends_with("_R") == (state == &"lane_dash_right")
				if knee and leading:
					check(span.y >= 1.2, "dash leading knee recovers " + str(state) + " " + name)
				elif knee:
					check(span.x <= 0.2 and span.y <= 0.9, "dash push-off leg extends " + str(state) + " " + name)
				else:
					check(span.x >= 1.19 and span.y <= 1.61, "dash keeps the run elbow pump " + str(state) + " " + name)
			if state == &"land":
				check(span.y >= (0.9 if knee else 0.75), "landing absorption " + name)
			if state == &"shield_brace" and not knee:
				check(span.y >= 1.55, "brace guard elbows " + name)
			if state == &"shield_brace" and knee:
				check(span.y >= 1.2, "brace crouch knees " + name)
			if state == &"powerup_react" and name == "forearm_R":
				check(span.y >= 1.5, "fist-pump elbow " + name)
			if state == &"victory" and knee:
				check(span.y >= 1.4, "victory keeps the run stride " + name)
		values[state] = ranges
	print("A1 JOINTS: ", values)
	for state in GROUNDED:
		for frame in 25:
			Capture.pose_for_view(hoppy, state, player.get_animation(state).length * frame / 24.0)
			var left := Capture.limb_bounds(hoppy, ["foot_L"])
			var right := Capture.limb_bounds(hoppy, ["foot_R"])
			check(left.position.y >= -0.003 and right.position.y >= -0.003 and absf(minf(left.position.y, right.position.y)) < 0.008, "planted sole %s frame %d: min_y=%.4f left_y=%.4f right_y=%.4f" % [state, frame, minf(left.position.y, right.position.y), left.position.y, right.position.y])
	# Match the export rate; catch import resampling/optimization regressions too.
	for state in GROUNDED:
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
	check_new_clips(hoppy)
	Capture.pose_for_view(hoppy, &"idle", 0.0)

## Chest tilt from vertical in skeleton space; positive tips the top toward +x.
func chest_roll(hoppy: Node3D) -> float:
	var sk: Skeleton3D = hoppy.skeleton
	sk.force_update_all_bone_transforms()
	var up := sk.get_bone_global_pose(sk.find_bone("chest")).basis.orthonormalized() * Vector3.UP
	return atan2(up.x, up.y)

func check_new_clips(hoppy: Node3D) -> void:
	var player: AnimationPlayer = hoppy.animation_player
	var sk: Skeleton3D = hoppy.skeleton
	# Every gait one-shot ends exactly on the run pose the runtime resumes at, so no pop.
	var exits: Dictionary = _report.get("run_exit", {})
	check(exits.size() == GAIT_CLIPS.size(), "sidecar run exit phase for every gait clip")
	for state in GAIT_CLIPS:
		var exit := float(exits.get(String(state), -1.0))
		check(is_equal_approx(exit, float(hoppy.GAIT_EXIT.get(state, 0.0))), "runtime resumes run at the authored exit " + state)
		Capture.pose_for_view(hoppy, &"run", player.get_animation(&"run").length * exit)
		var run_pose: Array[Quaternion] = []
		for bone in sk.get_bone_count():
			run_pose.append(sk.get_bone_pose_rotation(bone))
		Capture.pose_for_view(hoppy, state, player.get_animation(state).length)
		var worst := 0.0
		for bone in sk.get_bone_count():
			worst = maxf(worst, run_pose[bone].angle_to(sk.get_bone_pose_rotation(bone)))
		check(worst < 0.02, "%s ends on its run exit pose (worst bone %.4f rad)" % [state, worst])
	# Lane dashes lean into the dash, within limits, and return upright.
	for pair: Array in [[&"lane_dash_left", -1.0], [&"lane_dash_right", 1.0]]:
		var peak := 0.0
		for frame in 17:
			Capture.pose_for_view(hoppy, pair[0], player.get_animation(pair[0]).length * frame / 16.0)
			var roll := chest_roll(hoppy)
			if absf(roll) > absf(peak):
				peak = roll
		print("A1 DASH LEAN %s: peak %.4f rad" % [pair[0], peak])
		check(signf(peak) == pair[1] and absf(peak) >= 0.12 and absf(peak) <= 0.35, "dash lean direction and limits " + str(pair[0]))
	# Landing squashes below standing height and stays on the deck; victory stays in bounds.
	Capture.pose_for_view(hoppy, &"land", 0.0)
	var land := skin_bounds(hoppy)
	print("A1 LAND: ", land)
	check(land.position.y >= -0.003 and land.end.y <= 1.72, "landing squash inside 0..1.72 m")
	var victory_high := -INF
	var hands_high := -INF
	for frame in 13:
		Capture.pose_for_view(hoppy, &"victory", player.get_animation(&"victory").length * frame / 12.0)
		var bounds := skin_bounds(hoppy)
		check(bounds.position.y >= -0.003 and bounds.end.y <= 1.9 and bounds.size.x <= 1.6, "victory bounds frame %d: %s" % [frame, bounds])
		victory_high = maxf(victory_high, bounds.end.y)
		hands_high = maxf(hands_high, Capture.limb_bounds(hoppy, ["hand_L", "hand_R"]).end.y)
	print("A1 VICTORY: top %.4f m, hands up to %.4f m" % [victory_high, hands_high])
	check(hands_high >= 1.35, "victory raises both paws above the shoulders")
	# Art review r1: the lean and the celebration must read from the rear chase camera at
	# 1280x720; measured at the widest in-play FOV (smallest Hoppy), clip only (no runtime lean).
	for pair: Array in [[&"lane_dash_left", -1.0], [&"lane_dash_right", 1.0]]:
		var head_peak := 0.0
		for frame in 17:
			Capture.pose_for_view(hoppy, pair[0], player.get_animation(pair[0]).length * frame / 16.0)
			var lateral: float = Capture.chase_metrics(hoppy, Capture.CHASE_FOV_WIDEST).head_lateral_px
			if absf(lateral) > absf(head_peak):
				head_peak = lateral
		print("A1 CHASE DASH %s: head %.2f px off the centreline" % [pair[0], head_peak])
		check(signf(head_peak) == pair[1] and absf(head_peak) >= 8.0, "chase-camera dash head displacement >= 8 px " + str(pair[0]))
	var paws_peak := -INF
	var paws_held := 0
	for frame in 37:
		Capture.pose_for_view(hoppy, &"victory", player.get_animation(&"victory").length * frame / 36.0)
		var above: float = Capture.chase_metrics(hoppy, Capture.CHASE_FOV_WIDEST).paws_above_ears_px
		paws_peak = maxf(paws_peak, above)
		if above >= 6.0:
			paws_held += 1
	print("A1 CHASE VICTORY: paws up to %.2f px above the ear tips, %d/37 samples >= 6 px" % [paws_peak, paws_held])
	check(paws_peak >= 6.0 and paws_held >= 18, "chase-camera victory paws >= 6 px above the ear tips for half the clip")

func run() -> void:
	await process_frame
	root.get_node("AudioService").music.stop()
	var imported := load(BASE + "hoppy.glb") as PackedScene
	check(imported != null, "GLB loads")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "hoppy.build.json"))
	_report = report
	var file := FileAccess.open(BASE + "hoppy.glb", FileAccess.READ)
	check(file.get_32() == 0x46546c67 and file.get_32() == 2, "GLB header")
	check(file.get_32() == file.get_length(), "GLB length")
	var json_length := file.get_32()
	check(file.get_32() == 0x4e4f534a, "GLB JSON chunk")
	var gltf: Dictionary = JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
	check(report.script_sha256 == gltf.asset.extras.build_script_sha256, "sidecar matches embedded generator hash")
	check(report.generator == gltf.asset.generator and report.blender == "5.2.2 LTS", "generator provenance")
	check(FileAccess.get_sha256("res://tools/blender/build_hoppy.py") == report.script_sha256, "build script hash matches asset")
	check(report.get("contact_revision", 0) == 17, "120 Hz contact recipe (round 17: grounded one-shots) required")
	check(report.get("joint_revision", 0) == 15, "round-15 rig required: articulated limbs plus face bones")
	check(report.get("recipe_revision", 0) == 7, "round-7 bake required: palette, braces and detail pass")
	if report.get("recipe_revision", 0) == 7:
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
	check(names == expected and names.size() == STATES.size(), "sidecar action list matches GLB")
	check(report.get("grounded_clips", []) == Array(GROUNDED).map(func(s: StringName) -> String: return String(s)), "sidecar grounded clip list")
	check(int(report.get("triangle_cap", 0)) == TRIANGLE_CAP and int(report.get("led_primitives", 0)) >= 1, "sidecar triangle cap and LED mask")
	for bone: String in FACE_BONES:
		check(bone in report.get("face_bones", []), "sidecar face bone " + bone)
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
	hoppy.position.y = 1.2
	hoppy._process(0.0)
	check(is_equal_approx(hoppy.get_node("ContactShadow").global_position.y,0.016), "contact shadow stays on deck during a jump")
	check(is_equal_approx(hoppy.get_node("ContactShadow").material_override.get_shader_parameter("height"),1.2), "jump height softens contact shadow")
	hoppy.position.y = 0.0
	hoppy._process(0.0)
	hoppy._look.active = false
	var player: AnimationPlayer = hoppy.animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_default_blend_time = 0.0
	check(hoppy.find_children("*", "Light3D", true, false).is_empty(), "palette uses no clipping fill light")
	var surface_shader := preload("res://scenes/runner/player/hifi/hoppy_surface.gdshader")
	var glass_shader := preload("res://scenes/runner/player/hifi/hoppy_glass.gdshader")
	var shared := FileAccess.get_file_as_string("res://scenes/runner/player/hifi/hoppy_surface.gdshaderinc")
	check(not (surface_shader.code + glass_shader.code + shared).contains("TIME"), "surface shaders have no global time")
	check(shared.contains("ambient_energy + vec3(front_fill * front)) * orm.r"), "ambient and front fill weighted by baked occlusion")
	check(shared.contains("MODEL_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)") and shared.contains("clamp(dot(NORMAL, facing), 0.0, 1.0)"), "front fill is neutral, forward-facing only and never reaches the rear")
	var rig: Skeleton3D = hoppy.skeleton
	var eye_z := rig.get_bone_global_rest(rig.find_bone("eye_L")).origin.z
	check(eye_z < -0.15, "face looks down -Z, the front fill axis")
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
	# Review r1 capture meters: fur stats read only the fur class, peak luma catches one hot pixel,
	# and the CPU chase projection puts the camera target on the screen centre.
	var fur_image := Image.create(4, 1, false, Image.FORMAT_RGB8)
	var fur_mask := Image.create(4, 1, false, Image.FORMAT_RGB8)
	fur_image.fill(Color("d9ccb4"))
	fur_image.set_pixel(3, 0, Color.WHITE)
	fur_mask.fill(Color(0, 1, 0))
	fur_mask.set_pixel(3, 0, Color(0, 0, 1))
	var fur_probe := Capture.fur_stats(fur_image, fur_mask)
	check(fur_probe.pixels == 3 and absf(fur_probe.saturation - Color("d9ccb4").s) < 0.01, "fur stats read the fur class only")
	check(Capture.peak_luma(fur_image) > 0.99 and Capture.peak_luma(fur_mask) < 0.72, "peak luma finds the hottest pixel")
	check(Capture.chase_screen(Capture.CHASE_TARGET, 60.0).distance_to(Capture.CHASE_SIZE * 0.5) < 0.01, "chase projection centres the look target")
	check(Capture.chase_screen(Vector3(0, 1.8, 0), 60.0).y < Capture.chase_screen(Vector3(0, 0.2, 0), 60.0).y and Capture.chase_screen(Vector3(0.5, 1, 0), 60.0).x > 640.0, "chase projection orientation")
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
			var ambient_tint: Color = material.get_shader_parameter("ambient_fill")
			check(ambient_tint.s <= 0.10 and ambient_tint.s >= 0.04 and absf(ambient_tint.h - Capture.Palette.CREAM.h) * 360.0 <= 5.0, "ambient fill is a light cream, softer than CREAM")
			var fill: float = material.get_shader_parameter("front_fill")
			check(is_equal_approx(fill, hoppy.FRONT_FILL) and fill >= 0.05 and fill <= 0.5, "neutral front fill in budget")
			check(mesh.global_basis.is_equal_approx(hoppy.global_basis), "mesh forward is Hoppy forward for the front fill " + mesh.name)
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
	check(player.get_animation_list().size() == STATES.size(), "exactly thirteen actions")
	var import_settings := ConfigFile.new()
	check(import_settings.load(BASE + "hoppy.glb.import") == OK and import_settings.get_value("params", "animation/fps") == 120, "import preserves 120 Hz animation sampling")
	var root_position_keys := 0
	var run_clip := player.get_animation(&"run")
	for track in run_clip.get_track_count():
		if run_clip.track_get_type(track) == Animation.TYPE_POSITION_3D and str(run_clip.track_get_path(track)).ends_with(":root"):
			root_position_keys = run_clip.track_get_key_count(track)
	check(root_position_keys >= 73, "import retains grounded run root keys")
	var expected_lengths := {&"idle": 1.6, &"run": 0.6, &"jump": 0.5, &"fall": 0.8, &"roll": 0.8, &"hurt": 0.6, &"dead": 1.2,
		&"lane_dash_left": 8.0 / 30.0, &"lane_dash_right": 8.0 / 30.0, &"land": 0.2, &"shield_brace": 0.4,
		&"powerup_react": 0.5, &"victory": 1.2}
	for state in STATES:
		check(is_equal_approx(player.get_animation(state).length, expected_lengths[state]), "clip duration preserved " + state)
		check(player.has_animation(state), "action " + state)
		var loop := Animation.LOOP_LINEAR if state in [&"idle", &"run", &"fall"] else Animation.LOOP_NONE
		check(player.get_animation(state).loop_mode == loop, "loop flag " + state)
	for bone: String in report.bones:
		check(hoppy.skeleton.find_bone(bone) >= 0, "bone " + bone)
	check(hoppy.skeleton.get_bone_count() == 31, "bone count: 27 body bones plus brows and mouth corners")
	for bone: String in FACE_BONES:
		check(hoppy.skeleton.find_bone(bone) >= 0, "face bone " + bone)
	for hook in ["set_anim_state", "set_run_speed", "set_lane_lean", "show_aura", "show_shield", "on_hit",
			"play_move", "on_shield_block", "on_power_up", "on_power_up_end", "celebrate"]:
		check(hoppy.has_method(hook), "hook " + hook)
	var imported_tris := 0
	for mesh: MeshInstance3D in hoppy._meshes:
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			imported_tris += indices.size() / 3
	check(imported_tris == model_tris, "Godot imported triangle census matches sidecar")
	census(hoppy)
	check(draws <= 40 and triangles <= TRIANGLE_CAP and textures.size() <= 8, "whole-visual budgets")
	check(int(budget_cap()) == TRIANGLE_CAP, "shared Blender triangle cap is 48k")
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
	await check_one_shots(hoppy)
	check_face(hoppy)
	check_leds(hoppy)
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

## Round-7 one-shots: triggers, return to locomotion, and backend requests that must not cut them.
func check_one_shots(hoppy: Node3D) -> void:
	var player: AnimationPlayer = hoppy.animation_player
	for clip in GAIT_CLIPS:
		hoppy.set_anim_state(&"run")
		hoppy.set_anim_state(clip)
		check(hoppy.anim_state == clip and player.assigned_animation == clip, "one-shot plays " + clip)
		hoppy.set_anim_state(&"run")
		check(hoppy.anim_state == clip, "backend run request does not cut " + clip)
		check(is_equal_approx(player.speed_scale, lerpf(0.9, 1.6, hoppy._speed)) == (clip != &"land"), "gait one-shot keeps run cadence " + clip)
		player.advance(player.get_animation(clip).length + 0.01)
		await process_frame
		check(hoppy.anim_state == &"run" and player.assigned_animation == &"run", clip + " returns to run")
	hoppy.set_anim_state(&"idle")
	hoppy.play_move(&"lane_left")
	check(hoppy.anim_state == &"lane_dash_left", "lane_left plays the left dash")
	hoppy.play_move(&"lane_right")
	check(hoppy.anim_state == &"lane_dash_right", "lane_right retargets to the right dash")
	player.advance(1.0)
	await process_frame
	check(hoppy.anim_state == &"idle", "dash returns to the idle it started from")
	hoppy.set_anim_state(&"run")
	hoppy.play_move(&"lane_left")
	hoppy.set_anim_state(&"jump")
	check(hoppy.anim_state == &"jump", "jump interrupts a dash")
	hoppy.play_move(&"lane_right")
	check(hoppy.anim_state == &"jump", "airborne lane change keeps the jump clip")
	hoppy.set_anim_state(&"fall")
	hoppy.play_move(&"land")
	check(hoppy.anim_state == &"land", "touchdown plays land from fall")
	hoppy.set_anim_state(&"run")
	check(hoppy.anim_state == &"land", "land survives the backend's same-tick run request")
	hoppy.set_anim_state(&"roll")
	check(hoppy.anim_state == &"roll", "buffered roll interrupts land")
	hoppy.on_shield_block()
	check(hoppy.anim_state == &"roll", "no brace while rolling")
	hoppy.set_anim_state(&"run")
	hoppy.on_shield_block()
	check(hoppy.anim_state == &"shield_brace", "shield block braces when grounded")
	hoppy.on_power_up(&"code_review", 6.0)
	check(hoppy.anim_state == &"powerup_react", "power-up collection reacts when grounded")
	hoppy.set_anim_state(&"jump")
	hoppy.celebrate()
	check(hoppy.anim_state == &"jump", "airborne celebration waits")
	hoppy.set_anim_state(&"run")
	check(hoppy.anim_state == &"victory", "pending victory plays on the grounded return")
	player.advance(2.0)
	await process_frame
	check(hoppy.anim_state == &"run", "victory returns to run")
	hoppy.celebrate()
	check(hoppy.anim_state == &"victory", "grounded celebration plays victory")
	hoppy.set_anim_state(&"hurt")
	player.advance(0.7)
	await process_frame
	check(hoppy.anim_state == &"run", "hurt during a one-shot returns to its locomotion")
	hoppy.set_anim_state(&"dead")
	hoppy.play_move(&"lane_left")
	hoppy.celebrate()
	check(hoppy.anim_state == &"dead", "dead ignores moves and celebrations")

func check_face(hoppy: Node3D) -> void:
	var face: SkeletonModifier3D = hoppy._face
	var sk: Skeleton3D = hoppy.skeleton
	check(face != null and face.bound(), "face rig bound to the imported face bones")
	for pair: Array in [[&"hurt", "wince"], [&"victory", "grin"], [&"jump", "wide"], [&"run", "focused"]]:
		hoppy.set_anim_state(pair[0])
		hoppy._process(1.0)
		check(float(face.get(pair[1])) > 0.9, "state %s drives the %s expression" % pair)
	var eye := sk.find_bone("eye_L")
	var brow := sk.find_bone("brow_L")
	var mouth := sk.find_bone("mouth_R")
	for pair: Array in [[&"hurt", 0.2, 0.5], [&"jump", 1.1, 1.25]]:
		hoppy.set_anim_state(pair[0])
		hoppy._process(1.0)
		face.blink = 0.0
		face._process_modification()
		var scale := sk.get_bone_pose_scale(eye)
		var vertical := minf(scale.x, minf(scale.y, scale.z)) if pair[0] == &"hurt" else maxf(scale.x, maxf(scale.y, scale.z))
		check(vertical >= pair[1] and vertical <= pair[2], "%s eye scale %.3f" % [pair[0], vertical])
	hoppy.set_anim_state(&"victory")
	hoppy._process(1.0)
	face._process_modification()
	check(sk.get_bone_pose_position(mouth).y - sk.get_bone_rest(mouth).origin.y > 0.012, "grin lifts the mouth corner")
	check(sk.get_bone_pose_position(brow).y > sk.get_bone_rest(brow).origin.y, "grin lifts the brow")
	hoppy.set_anim_state(&"hurt")
	hoppy._process(1.0)
	face._process_modification()
	check(sk.get_bone_pose_position(mouth).y < sk.get_bone_rest(mouth).origin.y, "wince pulls the mouth corner down")
	check(not sk.get_bone_pose_rotation(brow).is_equal_approx(sk.get_bone_rest(brow).basis.get_rotation_quaternion()), "wince tilts the brow")
	# Blink closes the eyes without touching the other bones.
	face.blink = 1.0
	check(face.eye_openness() < 0.1, "blink closes the eyes")
	face.blink = 0.0

func check_leds(hoppy: Node3D) -> void:
	check(hoppy._led_materials.size() == 1, "one LED-masked accessory material")
	var segments := {}
	for mesh: MeshInstance3D in hoppy._meshes:
		for surface in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR:
				var colors: PackedColorArray = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
				for color in colors:
					if color.r > 0.5:
						segments[snappedf(color.g, 0.05)] = true
	check(segments.size() == 4, "four LED segments in the mask: " + str(segments.keys()))
	var material: ShaderMaterial = hoppy._led_materials[0]
	check(material.get_shader_parameter("has_led_mask") == true, "LED mask enabled on the accessory surface")
	hoppy.on_power_up(&"nitro", 4.0)
	hoppy._process(0.5)
	hoppy._process(1.0)
	check(hoppy.led_state().z == 0.0 and material.get_shader_parameter("led_level") >= 0.6, "nitro lights the strip")
	check(absf(material.get_shader_parameter("led_fill") - 2.5 / 4.0) < 0.01, "strip drains with the power-up: " + str(material.get_shader_parameter("led_fill")))
	hoppy.on_power_up_end(&"nitro")
	hoppy.show_shield(true)
	hoppy._process(0.6)
	check(is_equal_approx(material.get_shader_parameter("led_level"), 0.8), "stored shield glows the strip")
	hoppy.show_shield(false)
	hoppy._process(0.1)
	check(material.get_shader_parameter("led_level") == 0.0, "idle strip returns to the baked glow")
