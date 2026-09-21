extends SceneTree
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Forge = preload("res://scenes/runner/player/hifi/forge.gd")
const Capture = preload("res://scenes/runner/player/dev/capture_a1.gd")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var checks := 0
var failures := 0
var draws := 0
var triangles := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func mesh_tris(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total

func census(node: Node) -> void:
	check(node.process_mode == Node.PROCESS_MODE_PAUSABLE or node is AnimationPlayer, "pausable " + str(node.name))
	if node is MeshInstance3D:
		draws += node.mesh.get_surface_count()
		triangles += mesh_tris(node.mesh)
		if node.material_override is ShaderMaterial:
			check(not node.material_override.shader.code.contains("TIME"), "clock-only shader " + str(node.name))
		if node.material_overlay != null:
			draws += 1
			triangles += mesh_tris(node.mesh)
	if node is MultiMeshInstance3D:
		check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "MultiMesh interpolation disabled")
		if node.material_override is ShaderMaterial:
			check(not node.material_override.shader.code.contains("TIME"), "clock-only MultiMesh shader")
		draws += 1
		triangles += mesh_tris(node.multimesh.mesh) * node.multimesh.instance_count
	if node is GPUParticles3D:
		check(node.amount <= 64, "particle cap")
		draws += 1
		triangles += mesh_tris(node.draw_pass_1) * node.amount
	for child in node.get_children():
		census(child)

func bounds(node: Node3D, relative: Node3D) -> AABB:
	var result := AABB()
	if node is MeshInstance3D and node.is_visible_in_tree():
		result = relative.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
	if node is MultiMeshInstance3D and node.is_visible_in_tree():
		for i in node.multimesh.instance_count:
			var box: AABB = relative.global_transform.affine_inverse() * node.global_transform * node.get_meta("poses")[i] * node.multimesh.mesh.get_aabb()
			result = box if result.size == Vector3.ZERO else result.merge(box)
	for child in node.get_children():
		if child is Node3D:
			var box := bounds(child, relative)
			if box.size != Vector3.ZERO:
				result = box if result.size == Vector3.ZERO else result.merge(box)
	return result

func run() -> void:
	root.get_node("AudioService").music.stop()
	var cached_slate := Materials.lit(Palette.SLATE)
	var cached_values := Vector2(cached_slate.metallic, cached_slate.roughness)
	var hoppy := Hoppy.instantiate()
	hoppy.show_shield(true)
	root.add_child(hoppy)
	hoppy.set_process(false)
	var player: AnimationPlayer = hoppy.animation_player
	player.pause()
	hoppy.show_shield(false)
	player.seek(0, true)
	check_round_two_model(hoppy, cached_slate, cached_values)
	check_round_three(hoppy)
	check_round_four(hoppy)
	var standing := bounds(hoppy, hoppy)
	check(absf(standing.position.y) < 0.001 and absf(standing.end.y - 1.8) < 0.001, "standing envelope " + str(standing))
	for state: StringName in hoppy.STATES:
		hoppy.set_anim_state(state)
		check(hoppy.anim_state == state, "state " + state)
		if state == &"roll":
			hoppy.show_shield(true)
			hoppy.show_aura(&"lgtm", true)
			for sample in 121:
				player.seek(sample / 240.0, true)
				hoppy._process(0.0)
				check_roll_articulation(hoppy)
				for bubble: MeshInstance3D in [hoppy._aura, hoppy._shield]:
					var physical_cell: float = bubble.material_override.get_shader_parameter("hex_cell_size") * bubble.global_basis.x.length()
					check(is_equal_approx(physical_cell, 0.09), "R4 B1 roll maintains 9cm panel projection")
				var box := bounds(hoppy, hoppy)
				check(box.position.y >= -0.001 and box.end.y <= 0.901, "roll sample %d: %s" % [sample, box])
			player.seek(0, true)
			var start: Transform3D = hoppy.get_node("Root").transform
			player.seek(0.5, true)
			check(start.is_equal_approx(hoppy.get_node("Root").transform), "B2 roll spin endpoint continuity")
			hoppy.show_aura(&"lgtm", false)
			hoppy.show_shield(false)
	for speed in [0.0, 0.5, 1.2]:
		hoppy.set_run_speed(speed)
		check(is_equal_approx(hoppy._speed, speed), "speed hook")
	for lean in [-1.0, 0.0, 1.0]:
		hoppy.set_lane_lean(lean)
		check(is_equal_approx(hoppy.rotation.z, -lean * 0.12), "lean hook")
	hoppy.set_lane_lean(0)
	for kind: StringName in [&"lgtm", &"nitro", &"code_review"]:
		hoppy.show_aura(kind, true)
		check(hoppy._aura.visible, "aura on")
		hoppy.show_aura(kind, false)
		check(not hoppy._aura.visible, "aura off")
	hoppy.show_shield(true)
	check(hoppy._shield.visible, "shield hook")
	hoppy.on_hit()
	check(hoppy.get_node("Root/Model/Body").material_overlay != null, "hit hook")
	census(hoppy)
	check(draws <= 40, "draw budget: %d" % draws)
	check(triangles <= 20000, "triangle budget: %d" % triangles)
	var textures := 0
	for maps: Array in Forge.cache.values():
		for texture: Texture2D in maps:
			textures += 1
			check(texture.get_image().has_mipmaps(), "B5 mipmaps present")
			check(texture.get_width() <= 512 and texture.get_height() <= 512, "texture dimensions")
	check(textures <= 6, "texture count")
	check(Forge.maps("fur")[0] == Forge.maps("fur")[0], "texture cache identity")
	check(hoppy.get_node("Root/Model/Logo").position.z < 0, "chest faces negative Z")
	hoppy.set_process(true)
	paused = true
	var clock_before: float = hoppy._clock
	for frame in 4:
		await process_frame
	check(hoppy._clock == clock_before, "pause freezes shader clock")
	paused = false
	hoppy.set_process(false)
	var shader := FileAccess.get_file_as_string("res://scenes/runner/player/hifi/energy.gdshader")
	check(not shader.contains("cull_disabled"), "back-face culling enabled")
	check(shader.contains("1.0 + 0.3 * sin(clock * 4.0)"), "pulse spans 0.7 to 1.3")
	check(not shader.contains("TIME"), "shader uses explicit clock")
	hoppy._process(0.1)
	check(hoppy.get_node("Root/Model/Body").material_overlay == null, "hit clears")
	print("A1 CENSUS: %d draws, %d triangles, %d textures (256x256)" % [draws, triangles, textures])
	hoppy.free()
	Forge.cache.clear()
	await process_frame
	print("ASSET A1: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func check_round_two_model(hoppy: Node3D, cached: StandardMaterial3D, snapshot: Vector2) -> void:
	var model: Node3D = hoppy.get_node("Root/Model")
	var head: Node3D = model.get_node("Head")
	var frame: MeshInstance3D = head.get_node("GogglesL")
	check(frame.material_override != cached, "B1 goggle material duplicated")
	check(Vector2(cached.metallic, cached.roughness) == snapshot, "B1 cached SLATE unchanged by build")
	var sibling := Hoppy.instantiate()
	root.add_child(sibling)
	var other: Material = sibling.get_node("Root/Model/Head/GogglesL").material_override
	frame.material_override.roughness = 0.4
	check(is_equal_approx(other.roughness, 0.28) and Vector2(cached.metallic, cached.roughness) == snapshot, "B1 instance mutation isolated")
	frame.material_override.roughness = 0.28
	sibling.free()
	for path in ["LegL/Foot", "LegR/Foot", "Pocket"]:
		var mesh: Mesh = model.get_node(path).mesh
		check(mesh_tris(mesh) == 44, "B3 true chamfer topology " + path)
		check_mesh(mesh)
	for side in ["L", "R"]:
		var lens: MeshInstance3D = head.get_node("Lens" + side)
		var goggle: MeshInstance3D = head.get_node("Goggles" + side)
		var eye: MeshInstance3D = head.get_node("Eye" + side)
		check(is_equal_approx(lens.position.y, eye.position.y) and is_equal_approx(goggle.position.x, eye.position.x), "B4 goggles at eye line")
		check(lens.position.z < eye.position.z - 0.049, "B4 glass in front of sclera and pupil")
		check(goggle.position.z + goggle.mesh.get_aabb().size.y * 0.5 > -0.245, "B4 frame housing reaches face")
		check(goggle.mesh.get_aabb().size.x > lens.mesh.get_aabb().size.x, "B4 frame surrounds lens")
		check_mesh(goggle.mesh)
		check_mesh(lens.mesh)
		var circumferences := {}
		for uv: Vector2 in goggle.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
			circumferences[roundi(uv.x * 24000)] = true
		check(circumferences.size() >= 25, "B3 cylinder has at least 24 radial segments")
	check(head.has_node("GoggleStrapBridge"), "B4 connected strap and bridge")
	check(hoppy._glass.get_shader_parameter("color").a <= 0.35, "R4 B4 clear glass opacity")
	check(model.get_node("Hood").mesh is ArrayMesh, "dropped hood cup geometry")
	check(model.get_node("Tail").position.y >= 0.699, "tail above legs")
	check(model.get_node("RearLogo").position.z > 0.27, "rear branding faces gameplay camera")
	check(model.get_node("Body").material_override.rim_enabled, "hoodie rim separation")
	var seams: MultiMeshInstance3D = model.get_node("Stitches")
	for pose: Transform3D in seams.get_meta("poses").values():
		var radial := Vector3(pose.origin.x, 0, pose.origin.z).normalized()
		check(pose.basis.z.normalized().dot(radial) > 0.9, "B6 stitch faces outward")
		var height := pose.origin.y - 0.78
		var body_radius := 0.28 * sqrt(1.0 - height * height / (0.4 * 0.4))
		check(Vector2(pose.origin.x, pose.origin.z).length() > body_radius, "B6 stitches outside body")
		check(pose.basis.x.length() * 0.035 >= 0.03, "B6 stitches at least 3cm wide")
	var albedo: Image = Forge.maps("fur")[0].get_image()
	var darkest := 1.0
	var lightest := 0.0
	for y in range(0, 256, 8):
		for x in range(0, 256, 8):
			darkest = minf(darkest, albedo.get_pixel(x, y).r)
			lightest = maxf(lightest, albedo.get_pixel(x, y).r)
	check(lightest - darkest < 0.03, "R4 B2 subtle fur albedo range")
	var skull_uvs: PackedVector2Array = head.get_node("Skull").mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var ear_uvs: PackedVector2Array = head.get_node("EarL/Fur").mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var skull_max := Vector2.ZERO
	var ear_max := Vector2.ZERO
	for uv in skull_uvs:
		skull_max = skull_max.max(uv)
	for uv in ear_uvs:
		ear_max = ear_max.max(uv)
	check(skull_max != ear_max, "B5 per-part texture scale")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.rotation = Vector3(-0.4, 0.65, 0)
	camera.current = true
	hoppy.set_anim_state(&"run")
	hoppy.animation_player.seek(0.1, true)
	hoppy.set_run_speed(1)
	hoppy._clock = 0
	hoppy._process(0)
	for pose: Transform3D in hoppy._glyphs.get_meta("poses").values():
		check((hoppy._glyphs.global_basis * pose.basis).z.normalized().dot(camera.global_basis.z) > 0.999, "orbit glyph billboard")
	var first: Transform3D = hoppy._trail.get_meta("poses")[0]
	var hood: Node3D = model.get_node("Hood")
	check(first.origin.is_equal_approx(hoppy.to_local(hood.to_global(Vector3(0,-0.025,0.095)))), "trail originates on animated hood")
	camera.free()
	hoppy.set_anim_state(&"idle")
	hoppy.animation_player.play(&"idle", 0)
	hoppy.animation_player.seek(0, true)
	hoppy.animation_player.pause()
	hoppy._process(0)

func check_mesh(mesh: Mesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var good_uv := true
	var good_winding := true
	for point in uv:
		good_uv = good_uv and point.x >= 0 and point.is_finite() and point.y >= 0
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i+1]
		var c := indices[i+2]
		var cross_product := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		good_winding = good_winding and cross_product.dot(normals[a] + normals[b] + normals[c]) <= 0.000001
	check(good_uv, "hard-surface metric UVs finite and nonnegative")
	check(good_winding, "B3 clockwise faces agree with outward normals")

func check_roll_articulation(hoppy: Node3D) -> void:
	var rig: Node3D = hoppy.get_node("Root")
	check(is_equal_approx(rig.scale.x, rig.scale.y) and is_equal_approx(rig.scale.y, rig.scale.z), "B2 uniform rolling root")
	var model: Node3D = rig.get_node("Model")
	var head: Node3D = model.get_node("Head")
	var normalized_head := (head.position - Vector3(0,0.78,0)) / Vector3(0.28,0.4,0.28)
	check(normalized_head.length_squared() > 1.25 and head.rotation.x < -0.4, "B2 head curled forward outside torso")
	for side in ["L", "R"]:
		var ear: Node3D = head.get_node("Ear" + side)
		var base := head.transform * ear.position
		var tip := head.transform * ear.transform * Vector3(0,0.35,0)
		check(ear.position.length() < 0.27 and tip.z > base.z + 0.2 and tip.y < base.y, "B2 attached ears fold along back")
		var arm: Node3D = model.get_node("Arm" + side)
		var leg: Node3D = model.get_node("Leg" + side)
		check(arm.rotation.x > 1.0 and leg.rotation.x > 0.8, "B2 real arm and leg tuck")
		for pair: Array in [[arm,"Sleeve","Paw"], [leg,"Fur","Foot"]]:
			var a: MeshInstance3D = pair[0].get_node(pair[1])
			var b: MeshInstance3D = pair[0].get_node(pair[2])
			check((a.transform * a.get_aabb()).intersects(b.transform * b.get_aabb()), "B2 paw or foot attachment overlaps limb")
		for pivot: Node3D in [head, ear, arm, leg]:
			var basis := pivot.global_basis
			check(absf(basis.x.normalized().dot(basis.y.normalized())) < 0.0001 and absf(basis.y.normalized().dot(basis.z.normalized())) < 0.0001, "B2 orthogonal articulated frame")

func check_round_three(hoppy: Node3D) -> void:
	var player: AnimationPlayer = hoppy.animation_player
	# Exercise the exact capture helper in view order, including roll to rear idle.
	for state: StringName in [&"idle", &"run", &"run", &"roll", &"idle", &"roll", &"roll"]:
		check(Capture.pose_for_view(hoppy, state, 0.24), "R3 B1 requested capture animation applied")
		if state == &"run":
			var left: Node3D = hoppy.get_node("Root/Model/ArmL")
			var right: Node3D = hoppy.get_node("Root/Model/ArmR")
			check(absf(left.rotation.x) > 0.5 and absf(left.rotation.x + right.rotation.x) < 0.001, "R3 B1 run capture has opposite limb swings")
		if state == &"idle":
			check(hoppy.get_node("Root").rotation.is_zero_approx(), "R3 B1 idle capture is upright after roll")
	player.playback_default_blend_time = 0.08
	for end_time in [0.49, 0.5]:
		for target: StringName in [&"run", &"idle"]:
			hoppy.set_anim_state(&"roll")
			player.seek(end_time, true)
			var previous: float = hoppy.get_node("Root").rotation.x
			hoppy.set_anim_state(target)
			for frame in 12:
				var current: float = hoppy.get_node("Root").rotation.x
				check(absf(angle_difference(previous, current)) < 0.15, "R3 B3 roll exit has no backspin frame")
				previous = current
				player.advance(1.0 / 60.0)
	# Every planar face must preserve physical texture density, including bevels.
	for size in [Vector3(0.2,0.14,0.32), Vector3(0.33,0.17,0.055)]:
		var mesh := Forge.bevel_box(size)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var a := indices[i]
			var b := indices[i+1]
			check(is_equal_approx(uv[a].distance_to(uv[b]), vertices[a].distance_to(vertices[b]) * Forge.UV_PER_METER), "R3 B2 face UVs use physical dimensions")
	var cloth: Image = Forge.maps("cloth")[0].get_image()
	var crossings := 0
	for x in range(1, cloth.get_width()):
		if cloth.get_pixel(x-1,0).r <= 0.94 and cloth.get_pixel(x,0).r > 0.94:
			crossings += 1
	check(crossings == 64, "R3 B2 cloth has 64 cells per texture")
	check(is_equal_approx(1.0 / (Forge.CLOTH_CELLS * Forge.UV_PER_METER), 0.01), "R3 B2 weave cell measures one centimeter")
	check(cloth.has_mipmaps(), "R3 B2 fine cloth retains mipmaps")
	check(hoppy.get_node("Root/Model/Drawstrings").position.z < -0.28, "drawstrings project forward")
	var hood_colors: PackedColorArray = hoppy.get_node("Root/Model/Hood").mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var dark_lining := false
	for color in hood_colors:
		dark_lining = dark_lining or color.r < 0.3
	check(dark_lining, "hood has dark inner lining")
	check(hoppy._trim.multimesh.instance_count == 3, "goggle and hem edge light instances")
	Capture.pose_for_view(hoppy, &"idle", 0.0)
	hoppy._process(0)
	player.playback_default_blend_time = 0.08

func check_round_four(hoppy: Node3D) -> void:
	for sphere: MeshInstance3D in [hoppy._shield, hoppy._aura]:
		var uvs: PackedVector2Array = sphere.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
		var uv_min := Vector2(INF, INF)
		var uv_max := Vector2.ZERO
		for uv in uvs:
			uv_min = uv_min.min(uv)
			uv_max = uv_max.max(uv)
		check(uv_min.is_equal_approx(Vector2.ZERO) and uv_max.is_equal_approx(Vector2.ONE), "R4 B1 energy UV2 normalized")
		var material := sphere.material_override as ShaderMaterial
		var cell: float = material.get_shader_parameter("hex_cell_size")
		check(cell >= 0.08 and cell <= 0.10, "R4 B1 hex panels have 8 to 10cm flat-to-flat spacing")
		check(material.shader.code.contains("surface_position.xy") and material.shader.code.contains("fwidth(edge)"), "R4 B1 physical panel projection with antialiasing")
	var fur: StandardMaterial3D = hoppy.get_node("Root/Model/Head/Skull").material_override
	check(fur.uv1_triplanar, "R4 B2 fur has no spherical meridian convergence")
	check(1.0 / (Forge.FUR_CELLS * fur.uv1_scale.x) <= 0.005, "R4 B2 fur streaks at most 5mm")
	var lathe := Forge.lathe([Vector2(0.1,0),Vector2(0.1,0.2)], 24)
	var uv: PackedVector2Array = lathe.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var largest := Vector2.ZERO
	for point in uv:
		largest = largest.max(point)
	check(is_equal_approx(largest.x, TAU * 0.1 * Forge.UV_PER_METER) and is_equal_approx(largest.y, 0.2 * Forge.UV_PER_METER), "R4 B2 lathe circumference and profile arc use meters")
	var hood: MeshInstance3D = hoppy.get_node("Root/Model/Hood")
	var box := hood.transform * hood.get_aabb()
	check(box.size.x <= 0.37 and box.size.y < 0.2 and box.size.z < 0.2, "R4 B3 compact collapsed hood envelope")
	var body: MeshInstance3D = hoppy.get_node("Root/Model/Body")
	check(box.intersects(body.transform * body.get_aabb()), "R4 B3 hood meets torso shoulder volume")
	check(hood.position.y > 1.0 and hood.position.z < 0.15, "R4 B3 mouth tucked behind skull")
	for direction in [-1.0, 0.0, 1.0]:
		hoppy.set_lane_lean(direction)
		for pupil: MeshInstance3D in hoppy._pupils:
			var rest := -0.115 if pupil.name == "PupilL" else 0.115
			check(is_equal_approx(pupil.position.x, rest + direction * 0.014), "R4 B4 pupils track lane")
	hoppy.set_lane_lean(0)
	for side in ["L","R"]:
		var sclera: StandardMaterial3D = hoppy.get_node("Root/Model/Head/Eye" + side).material_override
		check(sclera.albedo_color == Palette.CREAM and sclera.albedo_texture == null, "R4 B4 bright unbanded sclera")
		var colors: PackedColorArray = hoppy.get_node("Root/Model/Head/Pupil" + side).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(colors.size() > 0 and colors[0].b > colors[0].r, "R4 B4 navy iris surrounds pupil")
	var nose: StandardMaterial3D = hoppy.get_node("Root/Model/Head/Nose").material_override
	check(nose.albedo_color.r > nose.albedo_color.b, "R4 B4 warm nose tint")
	check(hoppy._glass.shader.code.contains("highlight_x") and not hoppy._glass.shader.code.contains("UV.x * 15.0"), "R4 B4 one translated highlight instead of pinwheel")
