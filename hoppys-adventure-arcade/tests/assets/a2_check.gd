extends SceneTree
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
const Textures = preload("res://scenes/runner/environment/hifi/texture_forge.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ASSET A2 FAIL: " + message)

func triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return total

func census(node: Node) -> Vector2i:
	var result := Vector2i.ZERO
	for child in node.find_children("*", "VisualInstance3D", true, false):
		if not child.is_visible_in_tree(): continue
		if child is Label3D:
			result.x += 2 if child.outline_size > 0 else 1
			result.y += child.text.length() * 4
		elif child is MeshInstance3D:
			result.x += child.mesh.get_surface_count()
			result.y += triangles(child.mesh)
		elif child is MultiMeshInstance3D:
			result.x += child.multimesh.mesh.get_surface_count()
			result.y += triangles(child.multimesh.mesh) * child.multimesh.instance_count
		elif child is GPUParticles3D:
			result.x += child.draw_passes
			result.y += triangles(child.draw_pass_1) * child.amount
	return result

func run() -> void:
	var baseline := root.scaling_3d_scale
	var corridor := Corridor.instantiate()
	root.add_child(corridor)
	corridor.set_process(false)
	check(corridor.get_node("Floor").position.y == 0, "floor top remains y=0")
	check(corridor.get_node("Floor").mesh.size.x == 8, "eight meter lane envelope")
	check(corridor.find_children("*", "CollisionObject3D", true, false).is_empty(), "cosmetic only")
	for child in corridor.find_children("*", "Node", true, false):
		check(child.process_mode == Node.PROCESS_MODE_PAUSABLE, "pause mode " + child.name)
		if child is MultiMeshInstance3D:
			check(child.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "MultiMesh interpolation " + child.name)
		if child is GPUParticles3D: check(child.amount <= 64, "particle cap " + child.name)
	var rack_vertices: PackedVector3Array = corridor._racks.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lanes_clear := true
	for vertex in rack_vertices:
		if absf(vertex.x) <= 3.5 and vertex.y <= 6.1: lanes_clear = false
	check(lanes_clear, "rack hardware clears full-height boss envelope")
	check_round_two(corridor)
	check_round_three(corridor)
	check_round_four(corridor)
	check_round_five(corridor)
	check_round_six(corridor)
	check(Textures.maps()["normal_map"] == Textures.maps()["normal_map"], "procedural map cache")
	var rest := census(corridor)
	var peak := rest
	for direction in [-1, 1]:
		corridor.set_turn(0.0, direction)
		corridor._process(0.0)
		var pose: Transform3D = corridor.transform
		var racks: Transform3D = corridor._rack_poses[0]
		for p in [0.15, 0.3, 0.5, 0.7, 0.85, 1.0]:
			corridor.set_turn(p, direction)
			corridor._process(0.0)
			check(is_zero_approx(corridor._corner_material.get_shader_parameter("bend")), "B7 no shader bend on panel")
			check(corridor._turn_chevron.get_parent() == corridor._corner, "B7 shared panel pose")
			var relative: Vector3 = corridor._corner.to_local(corridor._turn_chevron.global_position)
			check(relative.is_equal_approx(Vector3(corridor.bend * 18.0 * 18.0 - corridor._corner.position.x, 0.5, 6.0)), "B7 label follows curve center in front of wall")
			var label: Label3D = corridor._turn_chevron
			var width: float = label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
			var sight_clear := true
			var sign_center: Vector3 = corridor._corner.position + relative
			for z in range(-23, 8):
				var ratio := (8.0 - float(z)) / (8.0 - sign_center.z)
				var center_x: float = corridor.bend * pow(maxf(0.0, -float(z) - 6.0), 2)
				for edge_x in [sign_center.x - width * 0.5, sign_center.x + width * 0.5]:
					if absf(edge_x * ratio - center_x) > 3.6: sight_clear = false
			check(sight_clear, "R5 TURN text and arrow sightlines clear near rack envelope")
			check(width < 6.0 and label.text.contains("TURN"), "B7 complete text fits clear corridor width")
			check(label.font.has_char(0x25BA) and label.font.has_char(0x25C4), "B7 font supports both chevrons")
			if p == 0.5:
				check(not corridor._rack_poses[5].basis.is_equal_approx(Basis.IDENTITY), "rack module tangent yaw")
			var now := census(corridor)
			peak = Vector2i(maxi(peak.x, now.x), maxi(peak.y, now.y))
			if p >= 0.3 and p <= 0.7: check(is_equal_approx(absf(corridor.rotation_degrees.y), 55), "55 degree hold")
		check(corridor.transform == pose and corridor._rack_poses[0] == racks, "identical turn endpoints")
	for speed in [0.0, 12.0, 24.0, 32.0]:
		corridor.set_scroll_speed(speed)
		corridor._offset = 95.99
		corridor._process(0.02)
		check(corridor._offset >= 0 and corridor._offset < 96, "scroll wrap")
		for i in 11:
			var a: float = corridor._rack_poses[i].origin.z
			var b: float = corridor._rack_poses[i + 1].origin.z
			check(is_equal_approx(fposmod(a-b, 96), 8), "rack spacing across wrap")
	corridor.set_pursuit(1.0)
	check(corridor._pursuit == 1.0, "pursuit hook")
	corridor.set_pursuit(0.0)
	corridor.set_phase(&"boss")
	corridor.set_boss_arena(true)
	check(corridor.boss_arena and corridor.phase == &"boss", "phase and arena hooks")
	corridor.set_boss_arena(false)
	corridor.set_phase(&"run")
	corridor.set_process(true)
	paused = true
	var clock_before: float = corridor._clock
	var offset_before: float = corridor._offset
	for frame in 10: await process_frame
	check(corridor._clock == clock_before and corridor._offset == offset_before, "pause freezes motion and shader clock")
	paused = false
	corridor.set_process(false)
	var paths := ["res://scenes/runner/environment/hifi/rack_metal.gdshader"]
	for name in ["floor_grid", "code_wall", "code_wall_fade", "far_glow", "hologram"]:
		paths.append("res://scenes/runner/shaders/" + name + ".gdshader")
	var regex := RegEx.new()
	regex.compile("\\bTIME\\b")
	for path in paths:
		var shader := load(path) as Shader
		check(shader != null and regex.search(shader.code) == null, "shader clock " + path)
	for texture in Textures.maps().values() + Textures.floor_maps().values():
		check(texture.get_image().has_mipmaps(), "B1 complete mip chain")
		check(texture.get_width() <= 1024 and texture.get_height() <= 1024, "texture size")
	check(Textures.maps().size() + Textures.floor_maps().size() + 1 <= 8, "texture budget including glyph atlas")
	check(rest.x <= 14 and peak.x <= 18 and peak.y <= 60000, "draw and triangle budgets")
	print("ASSET A2 CENSUS: rest=%d turn=%d triangles=%d textures=8 (3 x 1024² + 3 x 512² + 1 x 256² + shared glyph atlas)" % [rest.x, peak.x, peak.y])
	corridor.free()
	check(is_equal_approx(root.scaling_3d_scale, baseline), "viewport ownership restored")
	var camera := Camera3D.new()
	root.add_child(camera)
	await Cleanup.release(self, [camera])
	check(not is_instance_valid(camera), "fixture camera freed")
	var audio := root.get_node_or_null("AudioService")
	check(audio == null or (audio.music.stream == null and audio.sfx.stream == null and audio.default_track == null), "fixture playback resources released before quit")
	print("ASSET A2: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func check_round_two(corridor: Node3D) -> void:
	var floor_shader := load("res://scenes/runner/shaders/floor_grid.gdshader") as Shader
	var metal_shader := load("res://scenes/runner/environment/hifi/rack_metal.gdshader") as Shader
	for shader in [floor_shader, metal_shader]:
		for uniform_name in ["albedo_map", "normal_map", "roughness_map"]:
			var sampler_ok := false
			for line in shader.code.split("\n"):
				if line.begins_with("uniform sampler2D " + uniform_name + " "):
					sampler_ok = line.contains("filter_linear_mipmap_anisotropic")
			check(sampler_ok, "B1 anisotropic mip sampler " + uniform_name)
	check(not metal_shader.code.contains("cull_disabled"), "B5 closed solids backface culled")
	check(not metal_shader.code.contains("inverse("), "B5 no per-vertex matrix inversions")
	check(metal_shader.code.contains("INSTANCE_CUSTOM"), "B5 precomputed module inverse yaw")
	var mesh := preload("res://scenes/runner/environment/hifi/mesh_forge.gd").bevel_box(Vector3.ONE, 0.1)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var winding_ok := true
	for i in range(0, vertices.size(), 3):
		var geometric := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
		if geometric.dot(normals[i]) >= 0 or normals[i].dot(vertices[i]) <= 0: winding_ok = false
	check(winding_ok, "B5 clockwise solids with outward normals")
	var vertices_rack: PackedVector3Array = corridor._racks.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var front := 10.0
	var back := 0.0
	for vertex in vertices_rack:
		if vertex.y < 6.1:
			front = minf(front, absf(vertex.x))
			back = maxf(back, absf(vertex.x))
	var screen: float = absf(corridor.get_node("WallR").position.x)
	check(screen - 3.80 >= 0.35 and front < 3.80 and back > screen + 0.15, "B2 raised frame and solid backing around recessed display")
	check(is_equal_approx(absf(corridor.get_node("WallL").position.x), screen), "B2 symmetric screen recess")
	var key: OmniLight3D = corridor.get_node("KeyLight")
	check(key.light_color == preload("res://scenes/runner/environment/runner_palette.gd").MINT, "B3 palette key light")
	check(key.omni_range < 3.5 and key.light_energy <= 0.65 and key.position.y < key.omni_range, "B3 light reaches floor but not walls")
	check(float(corridor.get_node("Floor").material_override.get_shader_parameter("grid_strength")) >= 0.45, "B4 readable grid strength")
	for path in ["res://scenes/runner/shaders/floor_grid.gdshader", "res://scenes/runner/shaders/code_wall.gdshader", "res://scenes/runner/shaders/code_wall_fade.gdshader", "res://scenes/runner/environment/hifi/rack_metal.gdshader"]:
		var tabs_only := true
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with(" "): tabs_only = false
		check(tabs_only, "B6 shader indentation " + path)
	var first: ShaderMaterial = corridor._metal()
	var second: ShaderMaterial = corridor._metal()
	first.set_shader_parameter("clock", 123.0)
	check(first != second and second.get_shader_parameter("clock") != 123.0, "independent materials with immutable cached maps")
	check(first.get_shader_parameter("normal_map") == second.get_shader_parameter("normal_map"), "shared texture resource only")
	check(corridor.get_node("Ceiling").position.y > 6.1, "ceiling clears maximum boss height")

func check_round_three(corridor: Node3D) -> void:
	var material: ShaderMaterial = corridor.get_node("ServerRacks").material_override
	check(float(material.get_shader_parameter("frame_metallic")) <= 0.35, "R3 B1 low-metallic frame faces")
	var tint: Color = material.get_shader_parameter("base_tint")
	var luminance := tint.r * 0.2126 + tint.g * 0.7152 + tint.b * 0.0722
	check(luminance >= 0.30, "R3 B1 slate albedo luminance floor")
	check(float(material.get_shader_parameter("baked_gain")) >= 0.75 and float(material.get_shader_parameter("rim_gain")) >= 0.08, "R3 B1 baked bounce and palette rim")
	var uv2: PackedVector2Array = corridor._racks.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	var bevels := false
	var faces := false
	var range_ok := true
	for data in uv2:
		bevels = bevels or data.x > 0.9
		faces = faces or data.x < 0.1
		if data.x < 0 or data.x > 1 or data.y < 0.45 or data.y > 1: range_ok = false
	check(bevels and faces and range_ok, "R3 B1 distinct baked bevel and face exposure")
	check(material.shader.code.contains("NORMAL = yaw_rotate") and material.shader.code.contains("TANGENT = yaw_rotate") and material.shader.code.contains("BINORMAL = yaw_rotate"), "curved tangent frame rotates with geometry")
	var fresh := ShaderMaterial.new()
	fresh.shader = load("res://scenes/runner/shaders/code_wall.gdshader")
	# Dummy rendering does not expose uniform defaults; parse the declaration as well.
	check(fresh.get_shader_parameter("panel_period") == null or is_zero_approx(fresh.get_shader_parameter("panel_period")), "R3 B2 untouched shared material has no override")
	check(fresh.shader.code.contains("uniform float panel_period = 0.0;") and fresh.shader.code.contains("float panel_mask = 1.0;") and fresh.shader.code.contains("if (panel_period > 0.0)"), "R3 B2 default shader disables panel gaps")
	check(float(corridor.get_node("WallR").material_override.get_shader_parameter("panel_period")) == 8.0, "R3 B2 corridor opts into eight-meter panels")
	corridor._process(0.1)
	check(corridor.get_node("LaneGlow").material_override.get_shader_parameter("clock") == corridor._clock, "lane glow receives pause-safe clock")
	check(not corridor._scroll_materials.has(material) and not corridor._frame_materials.has(material) and corridor._metal_bend_materials.has(material), "metal receives only supported uniforms")
	check(corridor._clock_materials.size() == 8, "persistent complete clock targets")
	check(float(corridor.get_node("Ceiling").material_override.get_shader_parameter("intensity")) <= 0.15, "ceiling emission controlled")
	var metrics := preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
	var test_image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	test_image.fill(Color.BLACK)
	var region := Rect2i(0, 0, 16, 16)
	check(not metrics.frame_stats(test_image, region)["pass"], "R3 B1 capture rejects black frame")
	for y in 16: test_image.set_pixel(0, y, Color.WHITE)
	check(not metrics.frame_stats(test_image, region)["pass"], "R3 B1 isolated LED cannot hide black frame")
	test_image.fill(Color(0.15, 0.15, 0.15))
	check(not metrics.frame_stats(test_image, region)["pass"], "R3 B1 flat patch fails detail contrast")
	for y in 16:
		for x in 16:
			var level := 0.08 + float(x) * 0.015
			test_image.set_pixel(x, y, Color(level, level, level))
	check(metrics.frame_stats(test_image, region)["pass"], "R3 B1 exposed detailed frame passes metric")

func check_round_four(corridor: Node3D) -> void:
	var metrics := preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
	check(metrics.FRAME_REGION == Rect2i(1000, 150, 100, 500), "R4 B1 metal-only capture ROI")
	check(metrics.MIN_LIT_FRACTION == 0.55, "R4 B1 coverage threshold is not weakened")
	var half_display := Image.create(16, 16, false, Image.FORMAT_RGB8)
	half_display.fill(Color.BLACK)
	for y in 16:
		for x in 8:
			var level := 0.15 + float(x) * 0.02
			half_display.set_pixel(x, y, Color(level, level, level))
	var mixed: Dictionary = metrics.frame_stats(half_display, Rect2i(0, 0, 16, 16))
	check(mixed.mean >= metrics.MIN_MEAN and mixed.std >= metrics.MIN_STD and mixed.lit_fraction == 0.5 and not mixed["pass"], "R4 B1 half dark display fails mixed ROI")
	check(metrics.frame_stats(half_display, Rect2i(0, 0, 8, 16))["pass"], "R4 B1 same image passes metal-only ROI")
	var positioned := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	positioned.fill(Color.BLACK)
	for y in range(150, 650):
		for x in range(1000, 1100):
			var level := 0.15 + float(x - 1000) * 0.001
			positioned.set_pixel(x, y, Color(level, level, level))
	check(metrics.frame_stats(positioned)["pass"] and not metrics.frame_stats(positioned, Rect2i(1060, 200, 210, 450))["pass"], "R4 B1 calibrated ROI avoids recessed display")
	check(metrics.FLOOR_REGION == Rect2i(300, 470, 200, 120) and metrics.FLOOR_MIN_MEAN == 10.0, "R4 B2 floor exposure calibration")
	var floor_image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	floor_image.fill(Color(0.01, 0.01, 0.01))
	check(not metrics.floor_stats(floor_image, Rect2i(0, 0, 16, 16), Rect2i(1, 1, 14, 14))["pass"], "R4 B2 black floor fails")
	for y in 16: floor_image.set_pixel(0, y, Color.WHITE)
	check(not metrics.floor_stats(floor_image, Rect2i(0, 0, 16, 16), Rect2i(1, 1, 14, 14))["pass"], "R4 B2 bright grid cannot hide black floor")
	floor_image.fill(Color(0.07, 0.07, 0.07))
	check(not metrics.floor_stats(floor_image, Rect2i(0, 0, 16, 16), Rect2i(1, 1, 14, 14))["pass"], "R5 B1 flat plane fails despite adequate exposure")
	var floor_material: ShaderMaterial = corridor.get_node("Floor").material_override
	check(float(floor_material.get_shader_parameter("floor_metallic")) <= 0.35 and float(floor_material.get_shader_parameter("baked_gain")) >= 0.25, "R4 B2 floor material survives Compatibility ambient")
	var tint: Color = floor_material.get_shader_parameter("base_tint")
	check(tint.r * 0.2126 + tint.g * 0.7152 + tint.b * 0.0722 >= 0.30, "R4 B2 slate floor albedo")
	check(floor_material.get_shader_parameter("albedo_map") != Textures.maps()["albedo_map"] and floor_material.get_shader_parameter("albedo_map") == Textures.floor_maps()["albedo_map"], "R4 B2 dedicated floor maps cached independently")
	var response: Image = Textures.floor_maps()["roughness_map"].get_image()
	check(response.get_pixel(0, 0).g < response.get_pixel(100, 100).g, "R4 B2 plating seams have baked occlusion")
	var wear_min := 1.0
	var wear_max := 0.0
	for x in 512:
		wear_min = minf(wear_min, response.get_pixel(x, 100).b)
		wear_max = maxf(wear_max, response.get_pixel(x, 100).b)
	check(wear_max - wear_min > 0.2, "R4 B2 lane wear has measurable variation")
	check(not corridor.has_node("DataCity"), "invisible city draw and triangles reclaimed")
	check(not floor_material.shader.code.contains("float reflection"), "invisible reflection strip removed")

func check_round_five(corridor: Node3D) -> void:
	var metrics := preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
	check(metrics.FLOOR_DETAIL_REGION == Rect2i(780, 560, 40, 50) and metrics.FLOOR_MIN_DETAIL == 2.0, "R5 B1 gridless detail calibration")
	check(metrics.FLOOR_MAX_MEAN == 45.0, "R5 B2 upper exposure calibration")
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	var region := Rect2i(1, 1, 14, 14)
	image.fill(Color(0.12, 0.12, 0.12))
	check(metrics.detail_energy(image, region) < 0.001 and not metrics.floor_stats(image, region, region)["pass"], "R5 B1 constant plane fails detail guard")
	for y in 16:
		for x in 16:
			var level := 0.09 if (x + y) % 2 == 0 else 0.15
			image.set_pixel(x, y, Color(level, level, level))
	var textured: Dictionary = metrics.floor_stats(image, region, region)
	check(textured.detail >= 2.0 and textured["pass"], "R5 B1 textured controlled floor passes")
	for y in 16:
		for x in 16:
			var level := 0.3 if (x + y) % 2 == 0 else 0.4
			image.set_pixel(x, y, Color(level, level, level))
	var bright: Dictionary = metrics.floor_stats(image, region, region)
	check(bright.detail >= 2.0 and bright.mean > 45.0 and not bright["pass"], "R5 B2 bright detailed plane fails maximum exposure")
	check(Textures.FLOOR_BRUSH_PERIOD >= 8.0 and Textures.FLOOR_RIVET_RADIUS >= 0.08, "R5 B1 texture features authored at readable scale")
	var material: ShaderMaterial = corridor.get_node("Floor").material_override
	check(material.shader.code.contains("fwidth(edge_distance)") and material.shader.code.contains("plate_exposure"), "R5 B1 world-space derivative-filtered groove and bevel")
	var map: Image = Textures.floor_maps()["albedo_map"].get_image()
	check(map.get_pixel(100, 100).r - map.get_pixel(0, 0).r > 0.30, "R5 B1 strong plate versus groove albedo split")
	check(float(material.get_shader_parameter("baked_gain")) <= 0.32, "R5 B2 floor bounce cut to one third")
	var ceiling: ShaderMaterial = corridor.get_node("Ceiling").material_override
	check(float(ceiling.get_shader_parameter("baked_gain")) >= 0.12 and float(ceiling.get_shader_parameter("intensity")) >= 0.05, "R5 B2 ceiling depth cue restored")
	var wall: ShaderMaterial = corridor.get_node("WallR").material_override
	check(wall.shader.code.contains("ink+back_ink*0.15") and not wall.shader.code.contains("ink*0.8"), "R5 B2 full glyph ink restored")
	check(corridor._turn_chevron.pixel_size >= 0.014 and corridor._turn_chevron.position.z >= 6.0, "R5 larger forward TURN sign")

func check_round_six(corridor: Node3D) -> void:
	var metrics := preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
	check(metrics.FLOOR_DETAIL_REGION == Rect2i(780, 560, 40, 50), "R6 B1 detail ROI excludes lane marker")
	var image := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	image.fill(Color(0.12, 0.12, 0.12))
	for y in range(560, 610):
		for x in range(760, 775): image.set_pixel(x, y, Color.WHITE)
	check(metrics.detail_energy(image, metrics.FLOOR_DETAIL_REGION) < 0.001 and not metrics.floor_stats(image)["pass"], "R6 B1 bright lane cannot carry flat plate detail")
	var floor_material: ShaderMaterial = corridor.get_node("Floor").material_override
	check(float(floor_material.get_shader_parameter("plate_normal_depth")) > 0.5 and float(floor_material.get_shader_parameter("plate_rivet_radius")) >= 0.08, "R6 B1 strong normal response and world-scale rivets")
	var source := floor_material.shader.code
	check(source.contains("fwidth(sub_distance)") and source.contains("fwidth(rivet_distance)") and source.contains("sub_seam") and source.contains("rivet_rim"), "R6 B1 half-plate joint and corner rivets derivative-filtered")
	check(is_equal_approx(float(floor_material.get_shader_parameter("baked_gain")), 0.255), "R6 floor fill reduced fifteen percent")
	check(metrics.CEILING_REGION == Rect2i(480, 90, 320, 50) and metrics.CEILING_MIN_MEAN == 4.0, "R6 B2 ceiling image calibration")
	var patch := Image.create(16, 16, false, Image.FORMAT_RGB8)
	patch.fill(Color(0.005, 0.005, 0.005))
	var region := Rect2i(0, 0, 16, 16)
	check(not metrics.ceiling_stats(patch, region)["pass"], "R6 B2 black ceiling rejected")
	patch.fill(Color(0.025, 0.025, 0.025))
	check(metrics.ceiling_stats(patch, region)["pass"], "R6 B2 readable ceiling cue accepted")
	var metal: ShaderMaterial = corridor.get_node("ServerRacks").material_override
	check(metal.shader.code.contains("* overhead_attenuation + detail;") and not metal.shader.code.contains("+ detail) * overhead_attenuation"), "R6 B2 tray light detail exempt from fill attenuation")
	var ceiling: ShaderMaterial = corridor.get_node("Ceiling").material_override
	check(float(ceiling.get_shader_parameter("baked_gain")) >= 0.36 and float(ceiling.get_shader_parameter("intensity")) >= 0.14, "R6 B2 ceiling depth cue gain")
