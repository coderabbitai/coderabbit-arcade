extends SceneTree
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
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
	# Dummy rendering keeps the original get_image() snapshot after set_image().
	# Exercise the full lazy path for pixel/mipmap assertions; prewarm_check covers
	# worker Images, finalization metadata and stable live bindings separately.
	Textures.maps()
	Textures.floor_maps()
	var baseline := root.scaling_3d_scale
	var corridor := Corridor.instantiate()
	root.add_child(corridor)
	corridor.set_process(false)
	# Texture-content assertions need the full images, not startup placeholders.
	var deadline := Time.get_ticks_msec() + 15000
	while not Prewarm.is_complete() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(Prewarm.is_complete(), "asynchronous prewarm completed before texture census")
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
	check_walls(corridor)
	check_round_eight(corridor)
	check_round_nine(corridor)
	check_round_eleven(corridor)
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
	# check_walls measures every map and both atlases against the 8 x 1024² area budget.
	check(rest.x <= 14 and peak.x <= 18 and peak.y <= 60000, "draw and triangle budgets")
	print("ASSET A2 CENSUS: rest=%d turn=%d triangles=%d textures=8 (7 maps + shared wall/particle atlas)" % [rest.x, peak.x, peak.y])
	corridor.free()
	check(is_equal_approx(root.scaling_3d_scale, baseline), "viewport ownership restored")
	var camera := Camera3D.new()
	root.add_child(camera)
	await Cleanup.release(self, [camera])
	check(not is_instance_valid(camera), "fixture camera freed")
	check(Prewarm.jobs.is_empty() and Prewarm.deferred.is_empty() and Prewarm._scripts.is_empty() and Prewarm._census.is_empty(), "R11 fixture releases prewarm references")
	check(not process_frame.is_connected(Prewarm.poll), "R11 fixture disconnects prewarm poll")
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
	check(float(material.get_shader_parameter("frame_metallic")) <= 0.35, "R8 round-3 frame response restored")
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
	check(Rect2i(0, 0, 1280, 720).encloses(metrics.FRAME_REGION) and metrics.FRAME_REGION.has_area(), "frame ROI valid in capture")
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
	for y in range(metrics.FRAME_REGION.position.y, metrics.FRAME_REGION.end.y):
		for x in range(metrics.FRAME_REGION.position.x, metrics.FRAME_REGION.end.x):
			var level := 0.15 + float(x - metrics.FRAME_REGION.position.x) / float(metrics.FRAME_REGION.size.x) * 0.1
			positioned.set_pixel(x, y, Color(level, level, level))
	check(metrics.frame_stats(positioned)["pass"] and not metrics.frame_stats(positioned, Rect2i(0, 0, 16, 16))["pass"], "R4 B1 calibrated ROI avoids recessed display")
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
	check(wall.shader.code.contains("front*1.35+middle*0.48+rear*0.24+listing"), "R5 B2 full glyph ink restored")
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

func check_walls(corridor: Node3D) -> void:
	var atlas := preload("res://scenes/runner/environment/hifi/wall_atlas.gd")
	var racks := preload("res://scenes/runner/environment/hifi/rack_module.gd")
	var metrics := preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
	check(atlas.CELL.x >= 8 and atlas.CELL.y >= 12, "walls high resolution glyph cells")
	var texture := atlas.texture()
	check(texture.get_width() == atlas.CELL.x * 8 and texture.get_height() == atlas.CELL.y * 8, "walls atlas dimensions")
	check(texture == atlas.texture() and texture.get_image().has_mipmaps(), "walls cached mipmapped atlas")
	var antialiased := false
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			var alpha := image.get_pixel(x, y).a
			antialiased = antialiased or (alpha > 0.0 and alpha < 1.0)
	check(antialiased, "walls fractional stroke coverage")
	check(atlas.RAIN_LAYERS == 3, "walls three rain layers")
	var wall: ShaderMaterial = corridor.get_node("WallR").material_override
	check(wall.get_shader_parameter("atlas") == texture, "walls new atlas bound")
	for shader_name in ["code_wall", "code_wall_fade"]:
		var source := FileAccess.get_file_as_string("res://scenes/runner/shaders/" + shader_name + ".gdshader")
		check(source.count("= rain(") == atlas.RAIN_LAYERS and source.contains("float listing ="), "walls rain and persistent listing " + shader_name)
	check(Prewarm._census.wall_atlas["texture[]"] == texture, "walls new atlas prewarmed and counted")
	check(racks.VARIANT_COUNT >= 4 and corridor._rack_batches.size() == racks.BATCH_COUNT, "walls four live geometry variants")
	for shift in range(1, 12):
		var repeated := true
		for i in 12: repeated = repeated and racks.PATTERN[i] == racks.PATTERN[(i + shift) % 12]
		check(not repeated, "walls no shorter cyclic period %d" % shift)
	var area_max := 0.0
	var fingerprints: Array[int] = []
	for variant in racks.VARIANT_COUNT:
		var fingerprint: int = hash(racks.mesh(variant).surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
		check(not fingerprints.has(fingerprint), "walls distinct geometry variant %d" % variant)
		fingerprints.append(fingerprint)
		# Conservative full screen opening plus every wall LED face, even unlit glyph pixels.
		var coverage: float = (racks.WIDTHS[variant] * racks.HEIGHTS[variant] + 0.4) / (8.0 * 6.0)
		area_max = maxf(area_max, coverage)
		check(coverage <= 0.4, "walls conservative emissive area variant %d" % variant)
		var vertices: PackedVector3Array = racks.mesh(variant).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var clear := true
		for vertex in vertices: clear = clear and (absf(vertex.x) > 3.5 or vertex.y > 6.1)
		check(clear, "walls variant clears gameplay envelope")
	var texels := 0
	var maps: Array = Textures.maps().values() + Textures.floor_maps().values() + [texture]
	check(maps.size() <= 8, "walls eight procedural textures including particles")
	check(corridor._rain.draw_pass_1.material.albedo_texture == texture, "walls particles reuse new atlas")
	for map in maps: texels += map.get_width() * map.get_height()
	check(texels <= 8 * 1024 * 1024, "walls full texture area budget")
	var flat := Image.create(16, 16, false, Image.FORMAT_RGB8)
	flat.fill(Color(0.18, 0.18, 0.18))
	var roi := Rect2i(1, 1, 14, 14)
	check(not metrics.wall_stats(flat, roi)["pass"], "walls flat plating fails capture guard")
	for y in 16:
		for x in 16: flat.set_pixel(x, y, Color(38.0/255.0,38.0/255.0,38.0/255.0) if (int(x/2) + int(y/2)) % 2 == 0 else Color(22.0/255.0,22.0/255.0,22.0/255.0))
	check(metrics.wall_stats(flat, roi)["pass"], "walls textured plating passes calibrated detail bar")
	print("ASSET A2 WALLS: atlas=%dx%d cell=%dx%d layers=%d variants=%d max_emissive=%.3f texels=%d / %d" % [texture.get_width(), texture.get_height(), atlas.CELL.x, atlas.CELL.y, atlas.RAIN_LAYERS, racks.VARIANT_COUNT, area_max, texels, 8 * 1024 * 1024])

func check_round_eight(corridor: Node3D) -> void:
	var metrics := preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
	var image := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var region := Rect2i(1, 1, 30, 30)
	image.fill(Color.BLACK)
	check(not metrics.screen_stats(image, region)["pass"], "R8 black display fails")
	image.fill(Color(0.2, 0.2, 0.2))
	check(not metrics.screen_stats(image, region)["pass"], "R8 bright glass without glyph edges fails")
	image.fill(Color.BLACK)
	image.set_pixel(16, 16, Color.WHITE)
	check(not metrics.screen_stats(image, region)["pass"], "R8 isolated token cannot carry p95")
	for y in 32:
		for x in 32:
			var level := 0.18 if x % 6 < 2 and y % 10 < 8 else 0.015
			image.set_pixel(x, y, Color(level, level, level))
	check(metrics.screen_stats(image, region)["pass"], "R8 resolved bright glyph strokes pass")
	check(not metrics.screen_stats(image, Rect2i(-1, 0, 8, 8))["pass"], "R8 off-image screen ROI fails")
	image.fill(Color(0.055, 0.055, 0.055))
	check(not metrics.restored_frame_stats(image, region)["pass"], "R8 dim metal rejected despite old mean floor")
	for y in 32:
		for x in 32:
			var level := 0.18 if x % 4 < 2 else 0.23
			image.set_pixel(x, y, Color(level, level, level))
	check(metrics.restored_frame_stats(image, region)["pass"], "R8 45..60 frame exposure and full lighting accepted")
	check(Rect2i(0, 0, 1280, 720).encloses(metrics.WALL_DETAIL_REGION) and metrics.WALL_DETAIL_REGION.has_area(), "visible wall-detail ROI valid in capture")
	check(metrics.SCREEN_MIN_P95 == 26.0 and metrics.SCREEN_MIN_EDGE >= 1.0, "R8 ink and edge thresholds")
	var source: String = corridor.get_node("WallR").material_override.shader.code
	check(source.contains("textureGrad(wall_atlas") and source.contains("dFdx(p)/8.0"), "R8 atlas LOD follows continuous plane")
	check(source.contains("*2.0,world.y*2.5") and source.contains("1.7,0.78,3.0"), "R8 original glyph scale and visible rain density")
	# Projection estimate: full cap stroke is about 0.65 of a 0.4 m cell.
	# Pixel heights in the 720p / 60-degree fixture, before 0.5-scale rasterization.
	var close_pixels := 720.0 / (2.0 * tan(deg_to_rad(30.0))) * (0.65 / 2.5) / 6.0
	var gameplay_pixels := 720.0 / (2.0 * tan(deg_to_rad(30.0))) * (0.65 / 2.5) / 32.0
	check(close_pixels >= 10.0 and gameplay_pixels >= 3.0, "R8 projected glyph size at 6m close and 32m gameplay")
	print("ASSET A2 R8 GLYPH PROJECTION: close_6m=%.2fpx gameplay_32m=%.2fpx (analytic, not GPU measured)" % [close_pixels, gameplay_pixels])

# Autocorrelation samples only broad plate interiors, excluding intentional seam/rivet
# repetition. Aggregate independent columns and tiles; include lag 1 through 64 pixels.
func brush_correlation_peak(image: Image) -> float:
	var profiles: Array[PackedFloat32Array] = []
	for tile_y in 4:
		for x in [64, 128, 192, 320, 384, 448, 576, 640, 704, 832, 896, 960]:
			var samples := PackedFloat32Array()
			var mean := 0.0
			for y in range(tile_y * 256 + 40, tile_y * 256 + 224):
				var value := image.get_pixel(x, y).r
				samples.append(value)
				mean += value
			mean /= float(samples.size())
			for i in samples.size(): samples[i] -= mean
			profiles.append(samples)
	var peak := 0.0
	for lag in range(1, 65):
		var covariance := 0.0
		var a_power := 0.0
		var b_power := 0.0
		for samples in profiles:
			for i in samples.size() - lag:
				covariance += samples[i] * samples[i + lag]
				a_power += samples[i] * samples[i]
				b_power += samples[i + lag] * samples[i + lag]
		if a_power * b_power > 0.000001:
			peak = maxf(peak, covariance / sqrt(a_power * b_power))
	return peak

func check_round_nine(corridor: Node3D) -> void:
	var metrics := preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
	var racks := preload("res://scenes/runner/environment/hifi/rack_module.gd")
	# Test values just below/above the configured detail floor, rather than copying
	# the fixture's ROI coordinates and threshold into the test.
	var patch := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var region := Rect2i(1, 1, 30, 30)
	for factor in [0.6, 1.4]:
		var amplitude: float = metrics.WALL_MIN_DETAIL * factor * 9.0 / (8.0 * 255.0)
		for y in 32:
			for x in 32:
				var value: float = 0.15 + float(x) * 0.003 + (amplitude if (x + y) % 2 == 0 else -amplitude)
				patch.set_pixel(x, y, Color(value, value, value))
		check((metrics.wall_stats(patch, region).detail >= metrics.WALL_MIN_DETAIL) == (factor > 1.0), "R9 detail component brackets configured threshold independently of exposure")
	check(corridor._corner_material.get_shader_parameter("full_face") == true, "R9 end wall full face opt-in")
	var corner_source: String = corridor._corner_material.shader.code
	check(corner_source.contains("if (full_face) { screen = UV; variant = 0.0; }"), "R9 terminator aperture follows full quad")
	var canvas := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	canvas.fill(Color.BLACK)
	for i in metrics.END_WALL_REGIONS.size():
		check(not metrics.end_wall_stats(canvas, i)["pass"], "R9 black terminator fails sample %d" % i)
	canvas.fill(Color(0.1, 0.1, 0.1))
	for i in metrics.END_WALL_REGIONS.size():
		check(metrics.end_wall_stats(canvas, i)["pass"], "R9 visible terminator passes sample %d" % i)
	var peak := brush_correlation_peak(Textures.maps().albedo_map.get_image())
	check(peak < 0.4, "R9 generated plating has no dominant brush period")
	var periodic := Image.create(1024, 1024, false, Image.FORMAT_R8)
	for y in 1024:
		var value := 0.5 + 0.1 * sin(float(y) * TAU / 24.0)
		periodic.fill_rect(Rect2i(0, y, 1024, 1), Color(value, 0, 0))
	check(brush_correlation_peak(periodic) > 0.9, "R9 autocorrelation rejects old 24px ripple")
	var material: ShaderMaterial = corridor.get_node("ServerRacks").material_override
	check(material.shader.code.contains("NORMAL_MAP_DEPTH = 0.60;") and not material.shader.code.contains("brush_phase"), "R9 moderate normals and no sinusoidal shader brush")
	var first := racks.mesh(0).surface_get_arrays(0)
	var second := racks.mesh(1).surface_get_arrays(0)
	var merged: Array = corridor._rack_batches[0].mesh.surface_get_arrays(0)
	var deltas: PackedFloat32Array = merged[Mesh.ARRAY_CUSTOM0]
	var exact := true
	var frames := true
	for i in first[Mesh.ARRAY_VERTEX].size():
		var reconstructed: Vector3 = first[Mesh.ARRAY_VERTEX][i] + Vector3(deltas[i*4], deltas[i*4+1], deltas[i*4+2])
		exact = exact and reconstructed.is_equal_approx(second[Mesh.ARRAY_VERTEX][i])
		frames = frames and first[Mesh.ARRAY_NORMAL][i].distance_to(second[Mesh.ARRAY_NORMAL][i]) < 0.001
	check(exact and frames, "R9 merged layout reconstructs all variant-1 vertices with same normals")
	check(triangles(corridor._rack_batches[0].mesh) == triangles(racks.mesh(0)), "R9 delta layout adds no triangles")
	check(corridor._rack_batches.size() == 3 and census(corridor).x <= 13, "R9 one draw of rest headroom")
	var saved_offset: float = corridor._offset
	var saved_bend: float = corridor.bend
	var tags: Array[float] = []
	for offset in [0.0, 95.99, 96.0]:
		corridor._offset = offset
		corridor._update_pillars()
		var slot := [0, 0, 0]
		for i in 12:
			var batch_index: int = racks.BATCH_FOR_VARIANT[racks.PATTERN[i]]
			var data: Color = corridor._rack_data[i] # Dummy renderer does not retain MultiMesh buffer readback.
			check(is_equal_approx(data.a, racks.instance_tag(i)), "R9 stable per-instance wear tag across wrap")
			if offset == 0.0: tags.append(data.a)
			slot[batch_index] += 1
	check(tags.size() == 12 and tags[0] != tags[3], "R9 repeated variant gets different wear and label identity")
	# Shader inverse yaw uses reconstructed sine, never the repurposed tag channel.
	check(material.shader.code.contains("origin_s*p.z") and not material.shader.code.contains("INSTANCE_CUSTOM.w*p.z"), "R9 tag is not interpreted as yaw")
	corridor._offset = saved_offset
	corridor.bend = saved_bend
	corridor._update_pillars()
	var streak: ShaderMaterial = corridor._speed_lines.draw_pass_1.material
	check(streak.shader.code.contains("screen_alpha = 0.035") and streak.shader.code.contains("corridor_frame"), "R9 screen-adjacent streak attenuation in corridor frame")
	print("ASSET A2 R9: brush_autocorrelation_peak=%.4f (<0.4); merged_batches=%d; full_face=true" % [peak, corridor._rack_batches.size()])

# Guard discrimination only. No CPU image claims to predict GPU convergence.
func check_round_eleven(corridor: Node3D) -> void:
	var metrics := preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
	check(metrics.WALL_DETAIL_REGION == Rect2i(1030,180,240,360) and metrics.WALL_MIN_DETAIL == 0.40, "R12 clean face ROI/detail calibrated")
	check(metrics.WALL_MIN_STD == 5.0 and metrics.WALL_MAX_STD == 14.0 and metrics.WALL_MIN_MEAN == 24.0 and metrics.WALL_MAX_MEAN == 40.0, "R11 exposure/contrast window")
	check(metrics.WALL_MAX_DARK == 0.05 and metrics.WALL_MAX_AXIS_RATIO == 2.0, "R11 dark and axis limits")
	var good := {"detail": 0.497, "edge_density": 0.0774, "std": 8.0, "mean": 30.0, "dark_fraction": 0.0, "axis_ratio": 1.0}
	check(metrics.wall_pass(good), "R12 authored plate accepted")
	check(metrics.WALL_EDGE_THRESHOLD == 5.0 and metrics.WALL_MIN_EDGE_DENSITY == 0.04, "R12 central edge constants")
	check(metrics.FRAME_RESTORED_MIN_MEAN == 45.0 and metrics.FRAME_RESTORED_MAX_MEAN == 70.0, "R12 frame window")
	for pair in [[0.231,0.0097],[0.115,0.0]]:
		var softened := good.duplicate()
		softened.detail = pair[0]
		softened.edge_density = pair[1]
		check(not metrics.wall_pass(softened), "R12 reviewer softened counterfactual fails")
	var smear := good.duplicate()
	smear.detail = 1.056
	smear.std = 15.08
	smear.dark_fraction = 0.243
	smear.axis_ratio = 3.72
	check(not metrics.wall_pass(smear), "R12 r10 smear fails despite sufficient detail/edges")
	for pair in [["detail",0.399],["edge_density",0.039],["std",4.99],["std",14.01],["mean",23.99],["mean",40.01],["dark_fraction",0.051],["axis_ratio",2.01]]:
		var bad := good.duplicate()
		bad[pair[0]] = pair[1]
		check(not metrics.wall_pass(bad), "R11 each guard independently rejects " + str(pair))
	var patch := Image.create(64,64,false,Image.FORMAT_RGB8)
	var region := Rect2i(1,1,62,62)
	for mode in ["flat","edges","smear","crushed","bright"]:
		for y in 64:
			for x in 64:
				var value := 30.0
				if mode == "edges": value = 18.0 if x%16 < 2 or y%16 < 2 else 32.0
				if mode == "smear": value += 8.0 if y%2 == 0 else -8.0
				if mode == "crushed": value = 0.0 if x%4 == 0 else 38.0
				if mode == "bright": value = 55.0 if (x+y)%2 == 0 else 35.0
				patch.set_pixel(x,y,Color(value/255.0,value/255.0,value/255.0))
		var stats := metrics.wall_stats(patch,region)
		check(stats["pass"] == (mode == "edges"), "R11 measured fixture " + mode)
		if mode == "edges":
			for radius in [2,4]:
				var softened := soften_plate(patch,radius)
				var softened_stats := metrics.wall_stats(softened,region)
				check(not softened_stats["pass"] and softened_stats.edge_density < metrics.WALL_MIN_EDGE_DENSITY, "R12 measured box-softened plate fails edge density")
		if mode == "smear": check(stats.axis_ratio > 2.0, "R11 vertical gradients detect smear")
		if mode == "crushed": check(stats.dark_fraction > 0.05, "R11 counts crushed pixels")
	check(not metrics.wall_stats(patch,Rect2i(-1,0,10,10))["pass"], "R11 invalid ROI rejected")
	# Project a repeated CI label on the visible variant-2 upright at offset 6.4.
	# Its local z=-3.4 is outside that variant's screen aperture (-2.65..3.45).
	var forward := (Vector3(3.94,3.0,-4.0)-Vector3(1.6,3.3,0)).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward)
	var delta := Vector3(3.80,3.14,-1.0)-Vector3(1.6,3.3,0)
	var focal := 360.0/tan(deg_to_rad(30.0))
	var label_pixel := Vector2(640.0+focal*delta.dot(right)/delta.dot(forward),360.0-focal*delta.dot(up)/delta.dot(forward))
	check(Rect2(metrics.WALL_DETAIL_REGION).has_point(label_pixel), "R11 repeated stencil projects inside clean face ROI")
	var source: String = corridor.get_node("ServerRacks").material_override.shader.code
	check(source.contains("(panel_p.x-0.50)*10.0"), "R11 projected stencil placement matches shader")
	for token in ["vec2(0.022,0.008)","vec2(0.18,0.09)","vec2(0.30,0.10)","fine_grain*0.08+medium_grain*0.10+scuff*0.07-grime_signed*0.12","smoothstep(0.5,1.0,footprint)","vec3(0.40),vec3(1.20)","fine_grain*0.06","line_mask(groove_d,0.012)","-groove*0.34+bevel_lip*0.52","vec2(0.20,0.15)","-sub_groove*0.16+sub_lip*0.26","line_mask(sub_d,0.006)","line_mask(abs(sub_d-0.012),0.004)","vec2(0.40,0.30)","rivet_rim*sign(corner.y)*0.30","slat<5","float(slat)*0.03","mod(panel_id.x+panel_id.y+wear_seed,3.0)","label = max(label,local_ink)"]:
		check(source.contains(token), "R11 authored shader contract " + token)
	for cell in [Vector2(0.022,0.008),Vector2(0.18,0.09),Vector2(0.30,0.10),Vector2(0.65,0.28)]:
		check(maxf(cell.x,cell.y)/minf(cell.x,cell.y) <= 3.000001, "R11 grain aspect <=3")
	check(source.contains("fwidth(q.x)") and source.contains("fwidth(q.y)") and not source.contains("TIME"), "R11 filtered pause-static grain")
	var streak: String = corridor._speed_lines.draw_pass_1.material.shader.code
	check(streak.contains("ALPHA *= smoothstep(0.3,1.5,view_depth)"), "R11 near-plane fade retained")
	print("ASSET A2 R12: authored/softened/flat/smear guards checked; detail>=0.40 edge_density>=0.04 frame=45..70")

func soften_plate(image: Image, radius: int) -> Image:
	var result := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGB8)
	for y in image.get_height():
		for x in image.get_width():
			var sum := Color(0,0,0,0)
			for dy in range(-radius,radius+1):
				for dx in range(-radius,radius+1):
					sum += image.get_pixel(clampi(x+dx,0,image.get_width()-1),clampi(y+dy,0,image.get_height()-1))
			result.set_pixel(x,y,sum/float((radius*2+1)*(radius*2+1)))
	return result
