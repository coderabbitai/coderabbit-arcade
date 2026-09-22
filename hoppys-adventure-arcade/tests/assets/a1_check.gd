extends SceneTree
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
	check(hoppy._shield.visible, "shield request before ready")
	check(player.get_animation_list().size() == 7, "exactly seven actions")
	for state in STATES:
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
	check(ours != theirs, "private imported material copies")
	hoppy.on_hit()
	check(ours.albedo_color.r > 1.0 and theirs.albedo_color.r == 1.0, "isolated hit flash")
	hoppy._process(0.1)
	check(ours.albedo_color.r == 1.0, "flash clears")
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
