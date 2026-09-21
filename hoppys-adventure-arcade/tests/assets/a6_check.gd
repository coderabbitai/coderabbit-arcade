extends SceneTree
const Scene = preload("res://scenes/runner/pursuer/pursuer_visual.tscn")
const Forge = preload("res://scenes/runner/pursuer/hifi/forge.gd")
var checks := 0
var failures := 0
var draws := 0
var tris := 0
var textures: Dictionary = {}

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func mesh_triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return count

func material_check(material: Material) -> void:
	if material is ShaderMaterial:
		check(not material.shader.code.contains("TIME"), "Shader must use clock")
		check(not material.shader.code.contains("cull_disabled"), "Back-face culling enabled")
		for uniform in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(uniform.name)
			if value is Texture2D: textures[value.get_instance_id()] = value

func census(node: Node) -> void:
	check(node.process_mode == Node.PROCESS_MODE_PAUSABLE, "Pausable " + str(node.name))
	if node is GeometryInstance3D:
		check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Cosmetic interpolation " + str(node.name))
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
		var instances: int = 1 if node is MeshInstance3D else node.multimesh.instance_count
		draws += mesh.get_surface_count()
		tris += mesh_triangles(mesh) * instances
		material_check(node.material_override)
		for surface in mesh.get_surface_count(): material_check(mesh.surface_get_material(surface))
	elif node is GPUParticles3D:
		check(node.amount <= 64, "Particle cap")
		draws += node.draw_passes
		tris += mesh_triangles(node.draw_pass_1) * node.amount
		material_check(node.draw_pass_1.surface_get_material(0))
	elif node is Label3D:
		draws += 1 if node.outline_size == 0 else 2
		tris += node.text.length() * 2
	for child in node.get_children(): census(child)

func bounds(visual: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node: GeometryInstance3D in visual.find_children("*", "GeometryInstance3D", true, false):
		if node.name == "Shockwave": continue
		var relative := visual.global_transform.affine_inverse() * node.global_transform
		var boxes: Array[AABB] = []
		if node is MultiMeshInstance3D:
			for pose in visual.card_transforms(): boxes.append(relative * pose * node.multimesh.mesh.get_aabb())
		else:
			boxes.append(relative * (node.visibility_aabb if node is GPUParticles3D else node.get_aabb()))
		for box in boxes:
			result = box if first else result.merge(box)
			first = false
	return result

func run() -> void:
	var visual := Scene.instantiate()
	root.add_child(visual)
	visual.set_process(false)
	check(visual.HEADLINES == ["PR #3312 UNREVIEWED", "CHANGES REQUESTED", "STALE", "NEEDS REBASE", "DO NOT MERGE", "0 approvals"], "Portrait headlines unchanged")
	check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "No gameplay hitbox")
	visual.set_threat(-1)
	check(not visual.visible, "Zero threat hides")
	var envelope := AABB()
	for i in 121:
		visual.set_threat(1.5)
		visual._process(1.0 / 60.0)
		var box := bounds(visual)
		envelope = box if i == 0 else envelope.merge(box)
	check(envelope.size.x <= 6 and envelope.size.y <= 2.6 and envelope.position.y >= 0, "Threat envelope " + str(envelope))
	round_two_checks(visual)
	census(visual)
	check(draws <= 28, "Draw budget")
	check(tris <= 20000, "Triangle budget")
	check(textures.size() == 3, "Exactly three cached material maps")
	for texture: Texture2D in textures.values(): check(texture.get_width() <= 1024 and texture.get_height() <= 1024, "Texture resolution")
	check(Forge.maps()[0] == Forge.maps()[0], "Map cache reuse")
	var count := visual.get_child_count()
	visual.play_catch()
	visual._process(0.2)
	visual.play_catch()
	check(is_equal_approx(visual._reaction_time, 0.2), "Catch idempotent")
	visual._process(1.2)
	check(visual.get_node("Wall").position.z > 2, "Catch surges")
	visual.set_threat(1)
	var pose: Transform3D = visual.get_node("Wall").transform
	visual.set_threat(0)
	visual.play_retreat()
	check(visual.get_node("Wall").transform.is_equal_approx(pose), "Retreat continuity")
	visual._process(0.7)
	check(not visual.visible, "Retreat completes")
	visual.set_threat(0.7)
	check(visual.visible and count == visual.get_child_count(), "Reuse without allocation")
	visual.set_process(true)
	paused = true
	var clock: float = visual._t
	await process_frame
	await process_frame
	check(visual._t == clock, "Pause freezes clock")
	paused = false
	print("A6 CENSUS: %d draws, %d triangles (all particles and text included), %d textures at 256x256" % [draws, tris, textures.size()])
	print("A6 THREAT ENVELOPE: ", envelope)
	visual.free()
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	await create_timer(0.3).timeout
	print("ASSET A6: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func check_box_uv(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var valid := true
	var front_only := true
	for i in range(0, vertices.size(), 3):
		var clockwise := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i])
		var center := (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0
		valid = valid and clockwise.dot(normals[i]) > 0 and normals[i].dot(center) > 0
	for i in vertices.size():
		valid = valid and uvs[i].x >= 0 and uvs[i].x <= 1 and uvs[i].y >= 0 and uvs[i].y <= 1
		front_only = front_only and is_equal_approx(colors[i].r, 1.0 if normals[i].z > 0.999 else 0.0)
	check(valid, "Clockwise outward winding and normalized UVs")
	check(front_only, "Only front inset faces carry emission tag")
	check(mesh_triangles(mesh) == 44, "Chamfers emitted once, no coplanar duplicate strips")
	for axis in 3:
		for sign_value in [-1.0, 1.0]:
			var low := Vector2.ONE
			var high := Vector2.ZERO
			for i in vertices.size():
				if normals[i][axis] * sign_value > 0.999:
					low = low.min(uvs[i])
					high = high.max(uvs[i])
			check(low.is_equal_approx(Vector2.ZERO) and high.is_equal_approx(Vector2.ONE), "Each of six faces spans full UV square")

func round_two_checks(visual: Node3D) -> void:
	var wall := visual.get_node("Wall") as MultiMeshInstance3D
	var material := wall.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var source := material.shader.code
	check(not wall.multimesh.use_colors, "B1 no unused instance colors")
	var script_source := FileAccess.get_file_as_string("res://scenes/runner/pursuer/pursuer_visual.gd")
	check(not script_source.contains("set_instance_color"), "B1 no per-frame color uploads")
	visual.set_threat(0.5)
	check(is_equal_approx(material.get_shader_parameter("threat"), 0.5) and source.contains("threat * threat * 0.55"), "B1 live uniform drives albedo tint")
	visual.set_threat(1)
	var marks: Array = material.get_shader_parameter("diff_marks")
	check(marks.size() == 11 and source.contains("fwidth(uv)") and source.contains("mask * 0.18"), "B2 sparse antialiased reduced-weight diff shader")
	var covered := 0
	# Count the union including the maximum AA and view-offset fringe, not just centers.
	for y in 256:
		for x in 256:
			var uv := Vector2((x + 0.5) / 256.0, (y + 0.5) / 256.0)
			for rect: Vector4 in marks:
				if uv.x >= rect.x - 0.028 and uv.x <= rect.z + 0.028 and uv.y >= rect.y - 0.028 and uv.y <= rect.w + 0.028:
					covered += 1
					break
	var coverage := covered / 65536.0
	check(coverage <= 0.4, "B2 worst-fringe emissive coverage <= 40 percent")
	print("A6 DIFF COVERAGE: %.2f%% (includes maximum AA and parallax fringe)" % (coverage * 100.0))
	for texture in Forge.maps(): check(texture.get_image().has_mipmaps(), "B2 material maps have mipmaps")
	check_box_uv(wall.multimesh.mesh)
	check_box_uv(Forge.bevel_box(Vector3(0.065, 0.09, 0.025), 0.006))
	var cables := visual.get_node("Wall/CableTendrils") as MeshInstance3D
	var cable_arrays := cables.mesh.surface_get_arrays(0)
	var cable_uvs: PackedVector2Array = cable_arrays[Mesh.ARRAY_TEX_UV]
	var cable_vertices: PackedVector3Array = cable_arrays[Mesh.ARRAY_VERTEX]
	var valid_uvs := true
	var visible_vertices := 0
	for uv in cable_uvs:
		valid_uvs = valid_uvs and uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1
	for vertex in cable_vertices:
		if absf(vertex.x) > 2.6: visible_vertices += 1
	check(valid_uvs, "B3 cable UVs normalized circumferentially and longitudinally")
	check(cables.material_override.get_shader_parameter("glyph_enabled") == 0.0, "B3 cable material does not carry card badges")
	var eye := visual.get_node("Wall/EyeL") as MeshInstance3D
	var eye_box: AABB = eye.transform * eye.mesh.get_aabb()
	check(eye_box.end.y < 1.985 and eye_box.position.z < 0.15 and eye_box.end.z > 0.15, "B4 eyes recessed across top-row front at z=0.15")
	check(source.contains("float lens_energy = clamp(") and source.contains("0.0, 0.95)") and source.contains("core * 0.65 + fresnel * 0.18"), "B4 bounded lens core and Fresnel")
	var ring := visual.get_node("Wall/Shockwave") as MeshInstance3D
	check(ring.mesh.ring_segments >= 24 and ring.mesh.rings >= 64, "B5 smooth torus segmentation")
	var ring_pose := ring.transform
	# Evaluate maximum pulse size, independently of the current pulse phase.
	ring_pose.basis = Basis(Vector3.RIGHT, PI / 2).scaled(Vector3.ONE * 3.4)
	var ring_box: AABB = ring_pose * ring.mesh.get_aabb()
	check(ring_box.position.z > 0.6 and ring_box.size.x <= 5.201, "B5 torus clear of solid wall at maximum pulse")
	check(ring.material_override.shader.code.contains("leading_edge") and ring.material_override.shader.code.contains("4.0 * falloff"), "B5 bright leading edge and soft tail")
	var exhaust := visual.get_node("Wall/Glitch") as GPUParticles3D
	var process := exhaust.process_material as ParticleProcessMaterial
	check(exhaust.position.z - process.emission_box_extents.z > 0.4 and process.direction.z == 1.0, "B6 exhaust originates in front and travels toward camera")
	check(process.initial_velocity_min * exhaust.lifetime >= 0.6 and exhaust.draw_pass_1 is QuadMesh, "B6 visible trail and dedicated glyph quad")
	check(exhaust.draw_pass_1.material.shader.code.contains("horizontal") and exhaust.draw_pass_1.material.shader.code.contains("tail"), "B6 glyph plus streak shader")
	var travel := process.initial_velocity_max * exhaust.lifetime
	var lateral := travel * sin(deg_to_rad(process.spread))
	var required := AABB(-process.emission_box_extents - Vector3(lateral + 0.04, lateral + 0.11, 0.0), process.emission_box_extents * 2.0 + Vector3(2 * lateral + 0.08, 2 * lateral + 0.22, travel + 0.04))
	check(exhaust.visibility_aabb.encloses(required), "B6 culling AABB covers emission, travel, spread, glyph size")
	check(mesh_triangles(cables.mesh) <= 2700 and float(visible_vertices) / cable_vertices.size() > 0.3 and cables.mesh.get_aabb().position.z > 0.25, "B7 cables flank silhouette within 2700 triangles")
	var backing := visual.get_node("Wall/HeadlineBackings") as MeshInstance3D
	check(mesh_triangles(backing.mesh) == 6 * 44 and backing.material_override.get_shader_parameter("glyph_enabled") == 0.0, "Six nonemissive headline backings in one draw")
	check(script_source.contains('HEADLINES.find("CHANGES REQUESTED")'), "Danger headline selected semantically")
	var second := Scene.instantiate()
	root.add_child(second)
	second.set_process(false)
	second.set_threat(0.2)
	check(second._metal != material and second._lens != visual._lens and is_equal_approx(material.get_shader_parameter("threat"), 1.0), "Instance-local materials do not mutate another pursuer")
	check(second._metal.get_shader_parameter("plating") == material.get_shader_parameter("plating"), "Instances share immutable cached maps only")
	second.free()
