extends SceneTree
const BossBounds = preload("res://tests/boss_pose_bounds.gd")
const BossModel = preload("res://scenes/runner/boss/hifi/boss_model.gd")
const Forge = preload("res://scenes/runner/boss/hifi/forge.gd")
const Art = preload("res://scenes/runner/boss/boss_art.gd")
const Capture = preload("res://scenes/runner/boss/dev/capture_a5.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const ProjectileArt = preload("res://scenes/runner/boss/visuals/boss_projectile_art.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var boss_peak_draws := 0
var pose_context := ""
const KINDS := ["flaky_test_swarm", "merge_conflict_hydra", "legacy_monolith"]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A5: " + message)

func triangles(mesh: Mesh) -> int:
	return mesh.get_faces().size() / 3

func inspect(visual: Node3D, entrance: bool) -> Vector2i:
	var draws := 0
	var tris := 0
	var bounds := AABB()
	var first := true
	for node in visual.find_children("*", "", true, false):
		if node is Node3D:
			check(node.process_mode in [Node.PROCESS_MODE_INHERIT, Node.PROCESS_MODE_PAUSABLE], "pause inheritance")
		if node is OmniLight3D:
			var influence: AABB = node.global_transform * node.get_aabb()
			check(influence.position.x >= -3.501 and influence.end.x <= 3.501 and influence.position.y >= 1.599 and influence.end.y <= 6.101, "R4 accent influence XY envelope")
			check(influence.end.z <= visual.hover_z + 1.501 and (entrance or influence.position.z >= visual.hover_z - 1.501), "R4 accent influence depth envelope")
		if not node is GeometryInstance3D or not node.is_visible_in_tree(): continue
		var boxes: Array[AABB] = []
		if node is MultiMeshInstance3D:
			check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "MultiMesh interpolation OFF")
			draws += 1
			for index in node.multimesh.instance_count:
				var pose := Transform3D.IDENTITY
				for entry: Dictionary in node.get_parent().batches:
					if entry.node == node: pose = entry.poses[index]
				if absf(pose.basis.determinant()) < 0.000001: continue
				boxes.append(node.global_transform * pose * node.multimesh.mesh.get_aabb())
				tris += triangles(node.multimesh.mesh)
		elif node is MeshInstance3D:
			draws += node.mesh.get_surface_count()
			tris += triangles(node.mesh)
			boxes.append(node.global_transform * node.get_aabb())
		elif node is Label3D:
			draws += 2 if node.outline_size > 0 else 1
			tris += node.text.length() * 4
			# Font AABBs are not populated by the dummy headless renderer.
		elif node is GPUParticles3D:
			check(node.amount <= 64, "particle cap")
			boxes.append(node.global_transform * node.visibility_aabb)
			for pass_index in node.draw_passes:
				draws += 1
				tris += triangles(node.get_draw_pass_mesh(pass_index)) * node.amount
		if node.material_override is ShaderMaterial:
			check(not node.material_override.shader.code.contains("TIME"), "shader clock only")
		for box in boxes:
			bounds = box if first else bounds.merge(box)
			first = false
	check(bounds.position.x >= -3.501 and bounds.end.x <= 3.501, "world X envelope " + String(visual.kind) + " " + str(bounds))
	check(bounds.position.y >= 1.599 and bounds.end.y <= 6.101, "world Y envelope " + str(bounds))
	check(bounds.end.z <= visual.hover_z + 1.501, "front Z envelope")
	if not entrance:
		check(bounds.position.z >= visual.hover_z - 1.501, "back Z envelope")
	if visual._art.state == &"idle":
		check(bounds.size.x >= 5.9, "B2 broad gameplay silhouette")
		check(bounds.size.y >= 3.7, "B2 tall gameplay silhouette")
	if visual.kind == &"flaky_test_swarm":
		check(draws <= 12 and tris <= 22700, "R5 reactor within Swarm budget")
	check(draws <= 40, "stricter contract draw budget")
	check(tris <= 30000, "triangle budget")
	return Vector2i(draws, tris)

func run() -> void:
	await check_glb_bosses()
	await process_frame
	await process_frame
	for kind in KINDS:
		var mount := Node3D.new()
		mount.position = Vector3(0, 2.6, -14)
		root.add_child(mount)
		var visual: Node3D = load("res://scenes/runner/boss/visuals/%s_visual.tscn" % kind).instantiate()
		# Retain every historical procedural art assertion against the supported fallback.
		if "model_path" in visual: visual.model_path = "res://missing-boss-fallback.glb"
		else:
			visual._art = Art.new()
			visual.add_child(visual._art)
			visual._art.build(StringName(kind))
			visual._tag = visual._art.tag
		visual.kind = StringName(kind)
		visual.boss_name = kind.replace("_", " ")
		visual.max_hp = 100
		visual.hover_z = -14.0
		visual.sway_amplitude = 2.4
		mount.add_child(visual)
		visual.on_spawned()
		visual.set_process(false)
		var count := visual.get_child_count()
		visual.on_spawned()
		check(visual.get_child_count() == count, "idempotent spawn")
		check_round_two(visual)
		visual.on_spawned()
		check_round_three(visual)
		visual.on_spawned()
		check_round_four(visual)
		check_round_five(visual)
		visual.on_spawned()
		var peak := Vector2i.ZERO
		visual.play_intro(2.0)
		for frame in 61:
			visual._process(1.0 / 30.0)
			var census := inspect(visual, visual._art.state == &"intro")
			peak = Vector2i(maxi(peak.x, census.x), maxi(peak.y, census.y))
		for phase in [1, 2, 3]:
			visual.set_phase(phase)
			visual.set_health(100 - phase * 25, 100)
			for frame in 30:
				visual._process(0.1)
				var census := inspect(visual, false)
				peak = Vector2i(maxi(peak.x, census.x), maxi(peak.y, census.y))
			for variant in [&"orb", &"low", &"high", &"wide"]:
				for mask in [1, 2, 4, 7]:
					visual.play_telegraph(mask, variant, 0.6)
					for frame in 6:
						visual._process(0.09)
						inspect(visual, false)
					visual.play_attack(variant)
					visual._process(0.06)
					inspect(visual, false)
			visual.play_hit(&"unit_test", 15)
			visual._process(0.1)
			inspect(visual, false)
			visual.play_resist(&"lint_rule")
			visual._process(0.1)
			inspect(visual, false)
		var signature_peak := check_signature_reactions(visual)
		peak = Vector2i(maxi(peak.x, signature_peak.x), maxi(peak.y, signature_peak.y))
		visual.set_process(true)
		paused = true
		var previous: float = visual._art.clock
		await process_frame
		await process_frame
		check(visual._art.clock == previous, "pause freezes clock")
		paused = false
		visual.set_process(false)
		for ending in [&"play_defeat", &"play_retreat"]:
			visual.on_spawned()
			visual.call(ending)
			for frame in 10:
				visual._process(0.09)
				inspect(visual, false)
			visual._process(0.1)
			check(not visual._art.visible, "outro hides within one second")
		print("A5 CENSUS: %s = %d draws, %d triangles" % [kind, peak.x, peak.y])
		boss_peak_draws = maxi(boss_peak_draws, peak.x)
		mount.free()
	var fx: Node3D = load("res://scenes/runner/boss/boss_fx.tscn").instantiate()
	root.add_child(fx)
	var mock := Node.new()
	root.add_child(mock)
	fx.bind(mock)
	fx.bind(mock)
	check(fx.telegraphs.size() == 3 and fx.tracers.size() == 4 and fx.numbers.size() == 6, "bounded effect pools")
	for kind in [&"orb", &"low", &"high", &"wide"]:
		fx._telegraph(5, kind, 0.6)
		check(fx.telegraphs[0].active and not fx.telegraphs[1].active and fx.telegraphs[2].active, "lane bits")
		for node in fx.telegraphs:
			node._process(0.3)
			node.clear()
	for tracer in fx.tracers:
		tracer.fire(Vector3(0, 1, 0), Vector3(0, 3, -14), &"lint_rule", 12)
		tracer._process(0.07)
		check(tracer.active, "bolt travels")
		tracer._process(0.08)
		check(not tracer.active, "bolt arrival")
	for number in fx.numbers:
		number.start(Vector3.ZERO, 0, Color.WHITE, 0)
		check(number.tag.text == "RESISTED", "resisted text")
		number.start(Vector3.ZERO, 15, Color.WHITE, 0)
		number._process(0.35)
		check(number.backing.scale.x < 1.0 and number.backing.transparency == 0.0, "opaque backing scales out")
		number._process(0.36)
		check(not number.active, "number expires")
	for node in fx.telegraphs:
		node.start(1, &"orb", 1.0)
		check(not node.tag.visible, "R4 subpixel tag hidden; contract metadata retained")
	for node in fx.tracers: node.fire(Vector3.ZERO, Vector3(0, 3, -14), &"lint_rule", 15)
	for node in fx.numbers: node.start(Vector3.ZERO, 15, Color.WHITE, 0)
	# The signature accent layer is one MultiMesh however many marks are live: count it lit.
	var quake: Dictionary = first_attack(2, BossAttacks.SIG_QUAKE)
	fx._planned(quake)
	fx._telegraph(int(quake.telegraph_mask), quake.variant, float(quake.telegraph))
	fx._process(0.1)
	check(fx.marks.visible and fx.marks.used > 0, "C4 signature marks lit for the census")
	var fx_draws := 0
	var fx_triangles := 0
	for node in fx.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
		if node is MultiMeshInstance3D:
			check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "FX MultiMesh interpolation")
			fx_draws += 1
			fx_triangles += triangles(node.multimesh.mesh) * node.multimesh.instance_count
		elif node is MeshInstance3D:
			fx_draws += node.mesh.get_surface_count()
			fx_triangles += triangles(node.mesh)
		elif node is Label3D:
			fx_draws += 2
			fx_triangles += node.text.length() * 4
		if node.material_override is ShaderMaterial:
			check(not node.material_override.shader.code.contains("TIME"), "FX clock only")
	var active_numbers := 0
	for number in fx.numbers:
		if number.active: active_numbers += 1
	check(active_numbers == 3, "three concurrent numbers even for direct start calls")
	check(boss_peak_draws + fx_draws <= 44, "whole fight leaves four draws of headroom")
	print("A5 FX POOL CENSUS: %d draws, %d triangles (3 telegraphs, 4 tracers, 3 active numbers)" % [fx_draws, fx_triangles])
	print("A5 WHOLE FIGHT CENSUS: %d draws (target 44, cap 48)" % [boss_peak_draws + fx_draws])
	fx.clear()
	await check_signature_fx(fx)
	await check_projectiles()
	check_sizes()
	fx.clear()
	for i in 6:
		fx._arrival(&"unit_test", 1, Vector3.ZERO)
		check(fx.numbers[i].active and fx.number_cursor == (i + 1) % 6, "R5 all number slots reused")
	fx._end(&"legacy_monolith", 0)
	fx.clear()
	fx.free()
	mock.free()
	check(Forge.textures().size() == 3, "three procedural maps")
	for texture: Texture2D in Forge.textures().values():
		check(texture.get_image().has_mipmaps(), "material mipmaps")
		check(texture.get_width() == 256 and texture.get_height() == 256, "texture budget")
	check(Forge.glyph_atlas().get_image().has_mipmaps(), "glyph atlas mipmaps")
	check(Forge.textures().size() + 1 <= 4, "four cached textures including glyph atlas")
	check(absf(Capture.CLOSE_CAMERA.x) < 4.05, "B1 close camera inside corridor")
	check(Capture.distinct_view(PackedByteArray([1, 2]), PackedByteArray([1, 3])), "B1 distinct captures accepted")
	check(not Capture.distinct_view(PackedByteArray([1, 2]), PackedByteArray([1, 2])), "B1 identical captures rejected")
	var material_a := Forge.metal(Color.WHITE)
	var material_b := Forge.metal(Color.WHITE)
	material_a.emission_enabled = true
	check(not material_b.emission_enabled and material_a != material_b, "fresh mutable materials")
	check(material_a.albedo_texture == material_b.albedo_texture, "cached maps shared immutably")
	for path in ["res://scenes/runner/boss/hifi/reactor.gdshader","res://scenes/runner/boss/hifi/arc_metal.gdshader", "res://scenes/runner/boss/hifi/screen.gdshader", "res://scenes/runner/shaders/boss_beam.gdshader"]:
		check(not FileAccess.get_file_as_string(path).contains("cull_disabled"), "backface culling")
		check(not FileAccess.get_file_as_string(path).contains("TIME"), "shader source clock only")
	check_shader_masks()
	ProjectileArt.release_caches()
	root.get_node("AudioService").shutdown()
	check(not root.get_node("AudioService").music.playing and root.get_node("AudioService").music.stream == null, "R5 MP3 playback released before shutdown")
	Forge.clear_cache()
	check(Forge.maps.is_empty() and Forge.meshes.is_empty() and Forge.atlas == null, "R5 static caches released")
	print("ASSET A5: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	await create_timer(0.25).timeout
	quit(0 if failures == 0 else 1)

func check_round_two(visual: Node3D) -> void:
	var art: Node3D = visual._art
	check(Art.PLATING.get_luminance() > Art.Palette.SLATE.get_luminance() * 1.5, "B2 brighter neutral armour")
	for label in art.find_children("*", "Label3D", true, false):
		check(label == art.tag, "B4 no subpixel body labels; symbols carry meaning")
	check(art.tag.outline_size >= 6, "B4 gallery plate retains outlined text")
	check(art.motes.amount == 16 and art.motes.draw_passes == 1, "single bounded glyph emitter")
	check(art.motes.process_mode == Node.PROCESS_MODE_PAUSABLE, "glyph emitter pause")
	if visual.kind == &"flaky_test_swarm":
		var material: ShaderMaterial = art.batches[1].node.material_override
		check(material.get_shader_parameter("instance_accent") == true, "B5 instance colour enabled")
		check(material.shader.code.contains("tile_color = COLOR") and material.shader.code.contains("tile_color.rgb"), "B5 shader consumes instance colour")
		check(material.get_shader_parameter("accent") == Art.Palette.DANGER, "B5 explicit fallback accent")
		check(material.get_shader_parameter("symbol") == 1, "B4 check/cross replaces PASS/FAIL text")
		art.advance(0.0)
		var before: Color = art.batches[1].colors[0]
		check(before.is_equal_approx(Art.Palette.DANGER), "B5 FAIL tile is DANGER")
		check(art.batches[1].colors[1].is_equal_approx(Art.Palette.MATRIX), "B5 PASS tile is MATRIX")
		art.advance(0.34)
		check(not before.is_equal_approx(art.batches[1].colors[0]), "B5 clock changes tile state")
	elif visual.kind == &"merge_conflict_hydra":
		check(art.has_node("Torso"), "B3 shared torso")
		var start := Art.neck_pose(0, 0.0)
		var end := Art.neck_pose(0, 1.0)
		var quarter := Art.neck_pose(0, 0.25)
		check(quarter.origin.distance_to(start.origin.lerp(end.origin, 0.25)) > 0.3, "B3 curved neck in X and Z")
		check(start.basis.get_scale().x > end.basis.get_scale().x * 1.5, "B3 taper toward head")
		visual.play_telegraph(2, &"orb", 1.0)
		visual._process(0.8)
		check(art.heads[0].get_node("Jaw").rotation.x > 0.5, "B3 charge opens jaw")
		visual.play_attack(&"orb")
		visual._process(0.06)
		check(art.heads[0].get_node("Jaw").rotation.x > 0.8, "B3 attack opens jaw")
		var eye: Transform3D = art.batches[1].poses[0]
		var face: Node3D = art.heads[0].get_node("Face")
		check(eye.origin.z > (art.heads[0].transform * face.position).z + 0.07, "B3 eyes forward of screen")
		visual.set_phase(2)
		visual._process(0.1)
		check(art.heads[3].visible, "B3 fourth head in phase two")
	elif visual.kind == &"legacy_monolith":
		var rest: Transform3D = art.batches[1].rest[0]
		check(art.batches[1].rest.size() == 3 and rest.basis.get_scale().y > 3.7, "connected full-height fissures")
		visual.set_phase(1)
		visual._process(0.1)
		var width: float = art.batches[1].poses[0].basis.get_scale().x
		visual.set_phase(3)
		visual._process(0.1)
		check(art.batches[1].poses[0].basis.get_scale().x > width, "fissures widen by phase")
	visual.on_spawned()
	visual.play_hit(&"unit_test", 15)
	visual._process(0.08)
	check(art.position.z < -0.1, "hit recoil")
	check(art.flashes[0].emission_energy_multiplier >= 2.0 and art.flashes[0].emission_enabled, "visible hit flash")

func check_round_three(visual: Node3D) -> void:
	var art: Node3D = visual._art
	for material: ShaderMaterial in art.shader_materials:
		if material.get_shader_parameter("accent_path") == true:
			var gain: float = material.get_shader_parameter("accent_gain")
			check(gain >= 0.4 and gain <= 0.6, "R3 B2 hue-preserving accent gain")
			visual.play_hit(&"unit_test", 15)
			visual._process(0.08)
			check(material.get_shader_parameter("accent_gain") == gain, "R3 B2 hurt does not amplify accents")
	visual.on_spawned()
	if visual.kind == &"flaky_test_swarm":
		var plate: Vector3 = art.batches[0].rest[0].basis.get_scale()
		var screen_size: Vector3 = art.batches[1].rest[0].basis.get_scale()
		check(screen_size.x * screen_size.y / (plate.x * plate.y) < 0.25, "R3 B5 exposed metal frame exceeds 75 percent")
	elif visual.kind == &"merge_conflict_hydra":
		check(Art.EYE_POSITION.y - Art.EYE_SIZE.y * 0.5 > Art.FACE_POSITION.y + Art.FACE_SIZE.y * 0.5 + 0.15, "R3 B3 brow clears face screen")
		for head in art.heads:
			var jaw: MeshInstance3D = head.get_node("Jaw")
			check(jaw.material_override.albedo_color == Art.Palette.NAVY_2, "R3 B4 contrasting dark jaw")
		var stub: Transform3D = art.batches[0].poses[Art.NECK_SEGMENTS * 3 + 1]
		var hidden: Transform3D = art.batches[0].poses[Art.NECK_SEGMENTS * 3 + 2]
		check(stub.basis.determinant() > 0.0 and hidden.basis.determinant() == 0.0, "R3 B4 fourth-neck stub in phase one")
		var stub_bounds: AABB = stub * AABB(-Vector3.ONE * 0.5, Vector3.ONE)
		check(stub_bounds.end.y > 0.50, "R3 B4 stub emerges above torso")
		visual.set_phase(2)
		visual.play_telegraph(7, &"wide", 1.0)
		visual._process(0.8)
		for i in 4:
			var eye: Transform3D = art.heads[i].transform.affine_inverse() * art.batches[1].poses[i]
			var face: Transform3D = art.heads[i].transform.affine_inverse() * art.batches[2].poses[i]
			check(eye.origin.y - Art.EYE_SIZE.y * 0.5 > face.origin.y + Art.FACE_SIZE.y * 0.5 + 0.15, "R3 B3 animated eye and symbol remain separate")
	elif visual.kind == &"legacy_monolith":
		check(is_equal_approx(art.batches[0].node.multimesh.mesh.get_meta("world_bevel"), 0.035), "R3 brutalist plate bevel")
		check(art.has_node("FissureCavities"), "R3 recessed channel walls and backing")
		for i in 3:
			var fissure: Transform3D = art.batches[1].rest[i]
			var cavity: Transform3D = art.batches[3].rest[i]
			check(fissure.origin.z < 0.825 - 0.08, "R3 fissure recessed behind slab face")
			check(fissure.origin.z > cavity.origin.z - 0.08 and fissure.origin.z < cavity.origin.z + 0.1, "R3 orange inside dark cavity")
			for vent: Transform3D in art.batches[2].rest:
				check(absf(vent.origin.x - fissure.origin.x) > vent.basis.get_scale().x * 0.5 + 0.06, "R3 vents do not overlap fissures")

func line_mask(point: Vector2, start: Vector2, end: Vector2, width: float) -> float:
	var direction := end - start
	var t := clampf((point - start).dot(direction) / direction.length_squared(), 0.0, 1.0)
	return 1.0 - smoothstep(width, width + 0.025, (point - start - direction * t).length())

func shader_vector(source: String, name: String) -> Vector2:
	var expression := RegEx.new()
	expression.compile("uniform vec2 " + name + " = vec2\\(([^)]+)\\)")
	var found := expression.search(source)
	check(found != null, "R3 B1 shader control point " + name)
	if found == null: return Vector2.ZERO
	var coordinates := found.get_string(1).split(",")
	return Vector2(float(coordinates[0]), float(coordinates[1]))

func conflict_lines_mask(source: String, point: Vector2) -> float:
	var expression := RegEx.new()
	expression.compile("line\\(p,vec2\\(([^)]+)\\),vec2\\(([^)]+)\\),([0-9.]+)\\)")
	var value := 0.0
	for found in expression.search_all(source):
		var a := found.get_string(1).split(",")
		var b := found.get_string(2).split(",")
		value = maxf(value, line_mask(point, Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1])), float(found.get_string(3))))
	return value

func check_shader_masks() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/runner/boss/hifi/screen.gdshader")
	var start := shader_vector(source, "check_start")
	var elbow := shader_vector(source, "check_elbow")
	var end := shader_vector(source, "check_end")
	check(source.contains("line(p,check_start,check_elbow,0.1)") and source.contains("line(p,check_elbow,check_end,0.1)"), "R3 B1 shader uses tested control points")
	for point in [Vector2(-0.45, -0.1), Vector2(-0.15, -0.4), Vector2(0.375, 0.2), Vector2(0.55, 0.4)]:
		check(maxf(line_mask(point, start, elbow, 0.1), line_mask(point, elbow, end, 0.1)) > 0.99, "R3 B1 upright check arm point " + str(point))
	for point in [Vector2(-0.15, 0.4), Vector2(0.375, -0.2)]:
		check(maxf(line_mask(point, start, elbow, 0.1), line_mask(point, elbow, end, 0.1)) < 0.01, "R3 B1 rejects inverted caret point " + str(point))
	check(source.contains("min(accent_gain,0.8)"), "R3 B2 hard shader accent ceiling")
	var section := source.substr(source.find("symbol == 2"), source.find("symbol == 3") - source.find("symbol == 2"))
	for point in [Vector2(-0.59, -0.24), Vector2(0.59, -0.24), Vector2(0, -0.2)]:
		check(conflict_lines_mask(section, point) > 0.99, "R3 B3 incoming branches and conflict stem")
	for point in [Vector2(-0.23, 0), Vector2(0.23, 0)]:
		check(conflict_lines_mask(section, point) < 0.01, "R3 B3 gaps isolate conflict marker")
	var beam := (load("res://scenes/runner/shaders/boss_beam.gdshader") as Shader).code
	check(beam.contains("lens * (0.85 + rim * 0.15) * scan"), "R3 view-independent beam core")
	check(beam.contains("uniform vec4 color : source_color = vec4(1.0,0.302,0.239,0.35);"), "R3 default beam vec4 alpha")
	check(beam.contains("float scan = 0.85 + 0.15 * sin(UV.y * 80.0 - clock * 9.0);"), "R3 scan minimum is 0.70")
	check(beam.contains("ALPHA = color.a * mask * (0.9 + 0.1 * sin(clock * 6.0));"), "R3 final alpha minimum factor is 0.80")
	check(0.35 * 0.85 * 0.70 * 0.80 > 0.15, "R3 head-on beam minimum alpha at half countdown")
	var capture := FileAccess.get_file_as_string("res://scenes/runner/boss/dev/capture_a5.gd")
	check(capture.contains("Art.Materials.environment()") and capture.contains("key.light_color = Palette.MATRIX") and capture.contains("key.light_energy = 0.35"), "R3 production corridor environment and sun")

# Separating-axis test for the actual transformed unit armour boxes.
func boxes_overlap(a: Transform3D, b: Transform3D) -> bool:
	var axes: Array[Vector3] = [a.basis.x, a.basis.y, a.basis.z, b.basis.x, b.basis.y, b.basis.z]
	for first in [a.basis.x, a.basis.y, a.basis.z]:
		for second in [b.basis.x, b.basis.y, b.basis.z]: axes.append(first.cross(second))
	for axis in axes:
		if axis.length_squared() < 0.000001: continue
		axis = axis.normalized()
		var ra := 0.5 * (absf(axis.dot(a.basis.x)) + absf(axis.dot(a.basis.y)) + absf(axis.dot(a.basis.z)))
		var rb := 0.5 * (absf(axis.dot(b.basis.x)) + absf(axis.dot(b.basis.y)) + absf(axis.dot(b.basis.z)))
		if absf(axis.dot(b.origin - a.origin)) > ra + rb + 0.00001: return false
	return true

func check_round_four(visual: Node3D) -> void:
	var art: Node3D = visual._art
	var lights := art.find_children("*", "OmniLight3D", true, false)
	check(lights.size() == 1, "R4 one accent light per boss")
	check(lights[0].omni_range == 1.25 and not lights[0].shadow_enabled, "R4 bounded shadowless accent light")
	if visual.kind == &"merge_conflict_hydra":
		for head in 4:
			var chain := Art.neck_chain(head)
			for i in chain.size():
				var before := chain[maxi(i - 1, 0)].origin
				var after := chain[mini(i + 1, chain.size() - 1)].origin
				var spacing := (chain[i].origin.distance_to(before) + chain[i].origin.distance_to(after)) / (1.0 if i in [0, chain.size() - 1] else 2.0)
				check(is_equal_approx(chain[i].basis.get_scale().y, spacing * 1.08), "R4 B1 eight percent local axial overlap")
				if i > 0:
					check(boxes_overlap(chain[i - 1], chain[i]), "R4 B1 consecutive armour touches")
					check(chain[i].basis.get_scale().x <= chain[i - 1].basis.get_scale().x + 0.00001, "R4 B1 monotone width")
					check(chain[i].basis.get_scale().z <= chain[i - 1].basis.get_scale().z + 0.00001, "R4 B1 monotone depth")
				for j in range(i + 2, chain.size()):
					check(not boxes_overlap(chain[i], chain[j]), "R4 B1 nonadjacent armour separated")
		check(art.batches[3].rest.size() == 26, "R4 B1 six sleeve joints per neck")
		check(Forge.sleeve().get_surface_count() == 1 and triangles(Forge.sleeve()) > 100, "R4 B1 bevelled sleeve geometry")
		check(art.core.mesh.get_aabb().size.x > 4.9 and art.core.mesh.get_aabb().size.y > 0.22, "R4 seam arcs between neck bases")
	elif visual.kind == &"flaky_test_swarm":
		check(not art.has_node("SwarmEdgeRing"), "R4 B2 flat gizmo removed")
		check(art.batches[2].node.name == "SwarmMetalArcs", "R4 B2 metal arcs batched")
		check(Forge.recessed_arc_segment().get_aabb().size.z >= 0.99 and triangles(Forge.recessed_arc_segment()) > 100, "R4 B2 solid bevelled recessed section")
		var material: ShaderMaterial = art.batches[2].node.material_override
		check(material.get_shader_parameter("accent") == Art.Palette.MATRIX, "R4 B2 MATRIX edge insets")
		check(not material.shader.code.contains("unshaded") and material.shader.code.contains("NORMAL_MAP") and material.shader.code.contains("inset_face"), "R4 B2 lit textured metal with masked inset")
		for phase in [1, 2]:
			for frame in 120:
				var seconds := float(frame) * 0.17
				var bounds := AABB()
				for i in 24:
					var tile := AABB(Art.swarm_origin(i, phase, seconds) - Vector3(0.36, 0.32, 0.13), Vector3(0.72, 0.64, 0.26))
					bounds = tile if i == 0 else bounds.merge(tile)
					var arc := Art.swarm_arc_pose(i, phase, seconds)
					if phase == 2 and i % 8 == 7:
						check(is_zero_approx(arc.basis.determinant()), "R4 B2 three open group gaps")
					else:
						var midpoint := Art.swarm_origin(i, phase, seconds).lerp(Art.swarm_origin((i + 1) % 24, phase, seconds), 0.5) + Vector3(0, 0, -0.19)
						check(arc.origin.is_equal_approx(midpoint), "R4 B2 arcs follow tile groups")
				check(bounds.size.x >= 5.9 and bounds.size.y >= 3.7, "R4 B2 tiles alone carry silhouette")
				check(bounds.position.y + 2.6 >= 1.6 and bounds.end.y + 2.6 <= 6.1 and bounds.position.x - 0.35 >= -3.5 and bounds.end.x + 0.35 <= 3.5, "R4 B2 tile motion envelope")
	elif visual.kind == &"legacy_monolith":
		var vent: MeshInstance3D = art.get_node("CoreVent")
		var cavity := vent.transform * vent.mesh.get_aabb()
		var glow: AABB = art.core.transform * art.core.mesh.get_aabb()
		check(glow.end.z < cavity.end.z and glow.position.z > cavity.position.z, "R4 core recessed in vent")
	var beam := (load("res://scenes/runner/shaders/boss_beam.gdshader") as Shader).code
	check(beam.contains("lane_fill(UV,progress)") and beam.contains("smoothstep(0.72,1.0"), "R4 B3 mask uses soft lane fill")
	var start := shader_float(beam, "fill_start")
	var end := shader_float(beam, "fill_end")
	var centre := 0.75 * lerpf(start, end, 0.5)
	check(centre > 0.1 and centre < 0.4 and end > start, "R4 B3 centre filled at half countdown and brightens")

func shader_float(source: String, name: String) -> float:
	var expression := RegEx.new()
	expression.compile("uniform float " + name + " = ([0-9.]+)")
	var found := expression.search(source)
	check(found != null, "R4 shader fill control " + name)
	return float(found.get_string(1)) if found != null else 0.0

func check_round_five(visual: Node3D) -> void:
	var art: Node3D = visual._art
	if visual.kind == &"flaky_test_swarm":
		for node in art.find_children("*", "MeshInstance3D", true, false):
			check(not node.mesh is SphereMesh and not node.mesh is TorusMesh, "R5 no stock reactor primitives")
		check(art.core.name == "ReactorHousing" and art.core.mesh is ArrayMesh, "R5 forged reactor housing")
		var bounds: AABB = art.core.mesh.get_aabb()
		check(bounds.size.x >= 1.0 and bounds.size.y >= 1.0, "R5 housing mass at gameplay distance")
		check(art.core.material_override.albedo_color == Art.PLATING, "R5 lighter reactor armour")
		var vents: MeshInstance3D = art.core.get_node("RecessedVents")
		check(vents.mesh.get_aabb().end.z < bounds.end.z - 0.1, "R5 vents recessed behind housing face")
		check(vents.material_override.get_shader_parameter("accent") == Art.Palette.MATRIX, "R5 MATRIX vent feed")
		var band := Forge.forged_band(0.84,0.12,0.14)
		check(band.get_meta("section_width") >= 0.1 and band.get_aabb().size.z >= 0.1, "R5 containment section at least 0.1m")
		var heart: MeshInstance3D = art.core.get_node("ReactorHeart")
		check(heart.mesh is ArrayMesh and heart.material_override.shader.code.contains("rim") and heart.material_override.shader.code.contains("mask*0.48"), "R5 masked heart with fresnel shell")
	elif visual.kind == &"merge_conflict_hydra":
		check(art.core.has_node("SeamChannel"), "R5 recessed seam channel")
		var channel: MeshInstance3D = art.core.get_node("SeamChannel")
		check(channel.mesh.get_aabb().end.z > art.core.mesh.get_aabb().end.z, "R5 seam below channel lips")
		check(art.batches[3].poses[24].basis.determinant() > 0 and art.batches[3].poses[25].basis.determinant() > 0, "R5 dormant socket and mirrored shoulder vent")
	var beam := (load("res://scenes/runner/shaders/boss_beam.gdshader") as Shader).code
	check(beam.contains("1.0-smoothstep(0.9,1.0,uv.y)") and beam.contains("across*along*end_fade"), "R5 near-end lane fade wired")
	check(is_zero_approx(1.0-smoothstep(0.9,1.0,1.0)) and is_equal_approx(1.0-smoothstep(0.9,1.0,0.95),0.5), "R5 near edge fades over last ten percent")

# --- C4: signature attack visuals (contract 2.4 §11.4-§11.6) ---

## Every attack a boss's patterns can telegraph, in pattern order: [phase, attack] pairs.
static func boss_attacks(slot: int, signature: StringName = &"*") -> Array:
	var def: Dictionary = BossDefs.SLOTS[slot]
	var out: Array = []
	for phase in [1, 2, 3]:
		for beat: Dictionary in def.patterns[phase - 1]:
			if signature != &"*" and StringName(beat.get("signature", &"")) != signature: continue
			for option: Array in BossAttacks.beat_options(beat, def, phase, null):
				for attack: Dictionary in option: out.append([phase, attack])
	return out

static func first_attack(slot: int, signature: StringName) -> Dictionary:
	var found := boss_attacks(slot, signature)
	return found[0][1] if not found.is_empty() else {}

static func first_option(slot: int, signature: StringName) -> Array:
	var def: Dictionary = BossDefs.SLOTS[slot]
	for phase in [1, 2, 3]:
		for beat: Dictionary in def.patterns[phase - 1]:
			if StringName(beat.get("signature", &"")) == signature:
				return BossAttacks.beat_options(beat, def, phase, null)[0]
	return []

## Drives the real hook sequence of every signature attack through the visual, inspecting the
## envelope and budget on every frame; returns the peak census.
func check_signature_reactions(visual: Node3D) -> Vector2i:
	var art: Node3D = visual._art
	var slot: int = KINDS.find(String(visual.kind))
	var peak := Vector2i.ZERO
	var seen: Dictionary = {}
	for pair: Array in boss_attacks(slot):
		var attack: Dictionary = pair[1]
		var signature := StringName(attack.get("signature", &""))
		# Every signature once per phase, plus the first plain beat of each phase.
		var key := "%s:%d" % [signature, pair[0]]
		if seen.has(key): continue
		seen[key] = true
		visual.on_spawned()
		visual.set_phase(pair[0])
		visual._process(1.0)
		var calm := true
		for i in art.accent_materials.size(): calm = calm and Color(art.accent_materials[i].get_shader_parameter("accent")).is_equal_approx(art.accent_colors[i])
		check(calm, "C4 idle accents keep the boss colour")
		var variant := StringName(attack.variant)
		var total := float(attack.telegraph)
		var commit_at := float(attack.get("commit_at", -1.0))
		visual.play_telegraph(int(attack.telegraph_mask), variant, total)
		var t := 0.0
		var committed := commit_at < 0.0
		var rest_spread := swarm_spread(art)
		var hot_seen := false
		while t < total:
			visual._process(0.05)
			t += 0.05
			# Art review r1: attack-state accents are DANGER on the boss body.
			if art.state == &"telegraph" and art.age >= 0.12:
				var hot: bool = art.accent_materials.size() >= 3 and art.accent_light.light_color.is_equal_approx(Palette.DANGER)
				for material: ShaderMaterial in art.accent_materials: hot = hot and Color(material.get_shader_parameter("accent")).is_equal_approx(Palette.DANGER)
				hot_seen = hot_seen or hot
				check(hot, "C4 telegraph accents DANGER %s %s t=%.2f" % [visual.kind, signature, t])
			if not committed and t >= commit_at:
				committed = true
				visual.play_commit(int(attack.mask), variant, total - commit_at)
				visual._process(0.14)
				t += 0.14
				if visual.kind == &"flaky_test_swarm":
					check(art.commit_age > 0.0 and swarm_spread(art) < rest_spread * 0.8, "C4 swarm tiles converge on commit")
					check(art.batches[1].colors[0].is_equal_approx(Palette.DANGER), "C4 swarm tiles snap to one state")
			var census := inspect(visual, false)
			peak = Vector2i(maxi(peak.x, census.x), maxi(peak.y, census.y))
			if visual.kind == &"legacy_monolith" and signature == BossAttacks.SIG_QUAKE and t > total * 0.5 and t < total - 0.03:
				check(art.position.y > 0.05, "C4 monolith rises through the quake charge")
			if visual.kind == &"legacy_monolith" and signature == BossAttacks.SIG_LEGACY_WALL and t > total * 0.5 and t < total - 0.03:
				var pushed := false
				for i in 6:
					var lane := (i % 6) / 2
					var dz: float = art.batches[0].poses[i].origin.z - art.batches[0].rest[i].origin.z
					if int(attack.telegraph_mask) & (1 << lane): pushed = pushed or dz > 0.2
					else: check(absf(dz) < 0.001, "C4 gap column stays for the wall")
				check(pushed, "C4 monolith slabs push out for the wall")
		check(hot_seen, "C4 attack-state accents DANGER %s %s" % [visual.kind, signature])
		visual.play_attack(variant)
		visual._process(0.02)
		var fired: bool = art.accent_light.light_color.is_equal_approx(Palette.DANGER)
		for material: ShaderMaterial in art.accent_materials: fired = fired and Color(material.get_shader_parameter("accent")).is_equal_approx(Palette.DANGER)
		check(fired, "C4 accents stay DANGER through the attack %s %s" % [visual.kind, signature])
		if visual.kind == &"legacy_monolith" and signature == BossAttacks.SIG_QUAKE:
			check(art.state == &"slam", "C4 monolith body slams for the quake")
		for frame in 8:
			visual._process(0.05)
			var census := inspect(visual, false)
			peak = Vector2i(maxi(peak.x, census.x), maxi(peak.y, census.y))
			if visual.kind == &"legacy_monolith" and signature == BossAttacks.SIG_QUAKE and frame == 2:
				check(art.ring.visible and art.scale.y < 1.0, "C4 slam squash and shock ring")
	if visual.kind == &"merge_conflict_hydra":
		# A branching volley: the heads recoil one after another, as each head's shot leaves.
		visual.on_spawned()
		visual.set_phase(1)
		var volley := first_option(1, BossAttacks.SIG_BRANCHING)
		check(volley.size() == 2, "C4 branching volley has two heads")
		for attack: Dictionary in volley:
			visual.play_telegraph(int(attack.telegraph_mask), attack.variant, float(attack.telegraph))
		visual._process(float(volley[0].telegraph))
		visual.play_attack(volley[0].variant)
		visual._process(0.1)
		var first := -1
		for i in 4:
			if art.head_recoil[i] < Art.HEAD_RECOIL: first = i
		check(first >= 0 and art.heads[first].position.z < art.rest_poses[art.heads[first]].origin.z - 0.1, "C4 first head recoils")
		visual._process(float(volley[1].telegraph) - float(volley[0].telegraph) - 0.1)
		visual.play_attack(volley[1].variant)
		visual._process(0.05)
		var second := -1
		for i in 4:
			if i != first and art.head_recoil[i] < Art.HEAD_RECOIL and art.head_recoil[i] >= 0.0: second = i
		check(second >= 0 and art.head_recoil[first] > art.head_recoil[second] + 0.2, "C4 second head recoils after the first")
		inspect(visual, false)
	return peak

## Mean distance of the Swarm's tiles from their centroid (0 for other bosses).
func swarm_spread(art: Node3D) -> float:
	if art.boss_kind != &"flaky_test_swarm": return 0.0
	var centre := Vector3.ZERO
	for pose: Transform3D in art.batches[0].poses: centre += pose.origin
	centre /= art.batches[0].poses.size()
	var total := 0.0
	for pose: Transform3D in art.batches[0].poses: total += pose.origin.distance_to(centre)
	return total / art.batches[0].poses.size()

func marks_with(fx: Node3D, record: Dictionary) -> int:
	fx.marks.begin()
	fx.draw_record(record)
	var count: int = fx.marks.used
	fx.marks.finish()
	return count

func color_near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

func mark_count(fx: Node3D, color: Color, test: Callable = Callable()) -> int:
	var count := 0
	for i in fx.marks.used:
		if color_near(fx.marks.colors[i], color) and (not test.is_valid() or test.call(fx.marks.origins[i], fx.marks.sizes[i])): count += 1
	return count

func open(fx: Node3D, attack: Dictionary) -> Dictionary:
	fx._planned(attack)
	fx._telegraph(int(attack.telegraph_mask), attack.variant, float(attack.telegraph))
	var newest: Dictionary = fx.records[0]
	for record: Dictionary in fx.records:
		if record.active and record.id > newest.id: newest = record
	return newest

func check_signature_fx(fx: Node3D) -> void:
	var capacity: int = fx.marks.multimesh.instance_count
	check(fx.records.size() == fx.MAX_RECORDS and fx.marks.multimesh.instance_count == fx.marks.CAPACITY, "C4 preallocated records and marks")
	# Overlapping telegraphs on one lane: neither overwrites the other.
	fx._telegraph(1, &"orb", 0.5)
	fx._telegraph(1, &"orb", 1.0)
	check(fx.telegraphs[0].entry_count() == 2, "C4 overlapping lane telegraphs both kept")
	for i in 12: fx._process(0.05); fx.telegraphs[0]._process(0.05)
	check(fx.telegraphs[0].active and absf(fx.telegraphs[0].remaining - 0.4) < 0.06, "C4 later telegraph survives the first")
	fx.clear()
	# Swarm flaky: the candidates alternate, then SNAP to the commit.
	var flaky := first_attack(0, BossAttacks.SIG_FLAKY)
	var record := open(fx, flaky)
	check(record.flaky and not record.committed, "C4 flaky record opens uncommitted")
	var candidates: Array = flaky.candidates
	var swap := float(flaky.swap_seconds)
	var lanes: Array[int] = []
	for mask: int in candidates:
		for lane in 3:
			if mask & (1 << lane): lanes.append(lane)
	fx._process(0.01)
	var gain_a: float = fx.telegraphs[lanes[0]].gain
	var gain_b: float = fx.telegraphs[lanes[1]].gain
	check(gain_a > 0.9 and gain_b < 0.3, "C4 first flaky candidate shows, the other dims")
	var showing_before: int = fx.showing_mask(record)
	# Art review r1: the candidate tiles are DANGER with MATRIX glitches (was MATRIX tiles).
	var near_a := func(o: Vector3, _s: Vector2) -> bool: return absf(o.x - fx.lane_x(lanes[0])) < 0.5
	var tiles_a := mark_count(fx, Palette.DANGER, near_a) + mark_count(fx, Palette.MATRIX, near_a)
	check(mark_count(fx, Palette.DANGER, near_a) > mark_count(fx, Palette.MATRIX, near_a), "C4 flaky candidate tiles DANGER-dominant")
	for i in 3: fx._process(swap / 3.0)
	check(fx.showing_mask(record) != showing_before, "C4 flaky candidates alternate at the swap rate")
	check(fx.telegraphs[lanes[0]].gain < 0.3 and fx.telegraphs[lanes[1]].gain > 0.9, "C4 red lanes alternate with the tiles")
	check(tiles_a > 2, "C4 glitch tiles on the showing candidate")
	var lost := lanes[0] if int(flaky.mask) & (1 << lanes[1]) else lanes[1]
	var won := lanes[1] if lost == lanes[0] else lanes[0]
	fx._process(maxf(float(flaky.commit_at) - record.elapsed, 0.0))
	fx._committed(int(flaky.mask), flaky.variant, float(flaky.telegraph) - float(flaky.commit_at))
	check(record.committed and not fx.telegraphs[lost].has_entry(record.id) and fx.telegraphs[won].has_entry(record.id), "C4 commit drops the losing candidate lane")
	fx._process(0.2)
	check(not fx.telegraphs[lost].active and fx.telegraphs[won].gain > 0.99, "C4 committed lane solid")
	# Art review r1: the committed column is a DANGER fill (alpha >= 0.5), never a safe-looking lane.
	var snapped := 0
	var fill_alpha := 1.0
	for i in fx.marks.used:
		var o: Vector3 = fx.marks.origins[i]
		var s: Vector2 = fx.marks.sizes[i]
		if absf(o.x - fx.lane_x(won)) < 0.2 and s.x > 1.4 and color_near(fx.marks.colors[i], Palette.DANGER):
			snapped += 1
			fill_alpha = minf(fill_alpha, fx.marks.colors[i].a)
	check(snapped >= 6, "C4 tiles snap into the committed DANGER column")
	check(fill_alpha >= 0.5 and fx.COMMIT_FILL_ALPHA >= 0.5, "C4 committed column DANGER fill alpha >= 0.5 (%.2f)" % fill_alpha)
	var lost_near := func(o: Vector3, _s: Vector2) -> bool: return absf(o.x - fx.lane_x(lost)) < 0.6
	check(mark_count(fx, Palette.MATRIX, lost_near) + mark_count(fx, Palette.DANGER, lost_near) == 0, "C4 losing candidate tiles gone")
	var covered := 0.0
	var accent := 0.0
	for i in fx.marks.used:
		if absf(fx.marks.origins[i].x - fx.lane_x(won)) > 1.0: continue
		var area: float = fx.marks.sizes[i].x * fx.marks.sizes[i].y * fx.marks.colors[i].a
		if color_near(fx.marks.colors[i], Palette.DANGER): covered += area
		else: accent += area
	check(covered >= 3.0 * accent, "C4 committed column DANGER-dominant (%.1f vs %.1f m2)" % [covered, accent])
	print("C4 FLAKY COMMIT: DANGER fill alpha %.2f, %d tiles, DANGER %.1f m2 vs accent %.1f m2" % [fill_alpha, snapped, covered, accent])
	var danger: Color = fx.telegraphs[won].countdown_material.get_shader_parameter("color")
	check(color_near(danger, Palette.DANGER), "C4 DANGER stays the base telegraph")
	fx.clear()
	# Scatter: a fork at the split and the outer impact lanes after it.
	record = open(fx, first_attack(0, BossAttacks.SIG_SCATTER))
	fx._process(0.2)
	check(mark_count(fx, Palette.DANGER, func(o: Vector3, _s: Vector2) -> bool: return absf(absf(o.x) - 2.0) < 0.1) == 2, "C4 scatter marks both outer impact lanes")
	check(mark_count(fx, Palette.MATRIX, func(o: Vector3, _s: Vector2) -> bool: return absf(o.x) > 0.3 and absf(o.x) < 1.7) >= 2, "C4 scatter fork drawn")
	fx.clear()
	# Hydra branching: branch lines grow in firing order and are numbered.
	var volley := first_option(1, BossAttacks.SIG_BRANCHING)
	var heads: Array[Dictionary] = []
	for attack: Dictionary in volley: heads.append(open(fx, attack))
	for record_value in heads: record_value.elapsed = 0.05
	check(marks_with(fx, heads[0]) >= 2 and marks_with(fx, heads[1]) == 1, "C4 second branch waits for the first")
	for record_value in heads: record_value.elapsed = 0.7
	check(marks_with(fx, heads[1]) == marks_with(fx, heads[0]) + 1, "C4 heads numbered in firing order")
	fx.marks.begin()
	fx.draw_record(heads[0])
	check(mark_count(fx, Palette.LILAC) == fx.marks.used, "C4 hydra LILAC accent")
	fx.clear()
	# Sweep: the path crosses the lanes on the diagonal.
	var sweep := first_attack(1, BossAttacks.SIG_SWEEP)
	record = open(fx, sweep)
	fx._process(0.1)
	var sweep_end_z := -14.0 + float(sweep.speed) * float(sweep.sweep_end)
	check(mark_count(fx, Palette.LILAC, func(o: Vector3, _s: Vector2) -> bool: return absf(o.x) < 1.2 and o.z < sweep_end_z - 1.0) >= 2, "C4 sweep diagonal across the middle lane")
	check(mark_count(fx, Palette.LILAC, func(o: Vector3, _s: Vector2) -> bool: return absf(o.x - fx.lane_x(int(sweep.sweep_to))) < 0.4 and o.z > sweep_end_z + 1.0) >= 2, "C4 sweep continues down its end lane")
	fx.clear()
	record = open(fx, first_attack(1, BossAttacks.SIG_FORCE_PUSH))
	fx._process(0.1)
	check(mark_count(fx, Palette.LILAC) >= 11, "C4 force push chevrons and merge bar")
	fx.clear()
	# Monolith quake ring expands.
	record = open(fx, first_attack(2, BossAttacks.SIG_QUAKE))
	var radius := func() -> float:
		var best := 0.0
		for i in fx.marks.used:
			var o: Vector3 = fx.marks.origins[i]
			if fx.marks.sizes[i].x > 0.2: best = maxf(best, Vector2(o.x, o.z + 14.0).length())
		return best
	fx._process(0.1)
	var early: float = radius.call()
	fx._process(float(record.seconds) * 0.6)
	check(radius.call() > early + 2.0, "C4 quake ring expands")
	check(mark_count(fx, Palette.ORANGE) > 20, "C4 monolith ORANGE accent")
	fx.clear()
	# Legacy wall: the gap and its shift target in MINT from the first frame.
	var wall := first_attack(2, BossAttacks.SIG_LEGACY_WALL)
	record = open(fx, wall)
	fx._process(0.01)
	var shift_z := -14.0 + float(wall.speed) * float(wall.shift_at)
	var gap_x: float = fx.lane_x(int(wall.gap_from))
	var target_x: float = fx.lane_x(int(wall.gap_to))
	check(mark_count(fx, Palette.MINT, func(o: Vector3, _s: Vector2) -> bool: return absf(absf(o.x - gap_x) - 0.9) < 0.05 and o.z < shift_z) >= 2, "C4 wall gap lane highlighted")
	check(mark_count(fx, Palette.MINT, func(o: Vector3, _s: Vector2) -> bool: return absf(absf(o.x - target_x) - 0.9) < 0.05 and o.z > shift_z) >= 2, "C4 wall shift target shown from the start")
	check(mark_count(fx, Palette.MINT, func(o: Vector3, _s: Vector2) -> bool: return absf(o.x - (gap_x + target_x) * 0.5) < 0.3) >= 1, "C4 wall shift arrow")
	# Art review r1: gap lines >= 4 px wide at their far (boss) end from the chase camera.
	var thinnest := INF
	for i in fx.marks.used:
		if color_near(fx.marks.colors[i], Palette.MINT): thinnest = minf(thinnest, fx.marks.sizes[i].x)
	var far := Vector3(gap_x + 0.9, 0.0, -13.0)
	var gap_px := thinnest * chase_pixels_per_metre(far)
	check(gap_px >= 4.0, "C4 wall gap lines >= 4 px at the boss end (%.1f px)" % gap_px)
	print("C4 GAP LINES: %.2f m = %.1f px at z -13 from the chase camera (target >= 4)" % [thinnest, gap_px])
	fx.clear()
	# Debris shadows grow until impact.
	record = open(fx, first_attack(2, BossAttacks.SIG_DEBRIS))
	fx._process(0.05)
	var fill := func() -> float:
		var widest := 0.0
		for i in fx.marks.used: widest = maxf(widest, fx.marks.sizes[i].x)
		return widest
	var small: float = fill.call()
	fx._process(float(record.seconds) - 0.1)
	check(fill.call() > small * 1.5, "C4 debris shadows grow until impact")
	# Pause freezes the records and the marks.
	var frozen: float = record.elapsed
	paused = true
	await process_frame
	await process_frame
	check(record.elapsed == frozen, "C4 signature marks freeze on pause")
	paused = false
	fx.clear()
	check(not fx.marks.visible and fx.marks.multimesh.visible_instance_count == 0, "C4 marks clear")
	# A fight already under way when bind() runs resumes its flaky commit.
	var host := Node.new()
	var source := GDScript.new()
	source.source_code = "extends Node\nvar rows: Array = []\nfunc get_boss_info() -> Dictionary:\n\treturn {\"pending_attacks\": rows}\n"
	source.reload()
	host.set_script(source)
	root.add_child(host)
	host.rows = [{"lane_mask": int(flaky.mask), "kind": &"orb", "remaining": 0.4, "committed": true, "attack": flaky}]
	fx.bind(host)
	var resumed := false
	for record_value: Dictionary in fx.records:
		resumed = resumed or (record_value.active and record_value.committed and record_value.commit_mask == int(flaky.mask))
	check(resumed and fx.telegraphs[won].active and not fx.telegraphs[lost].active, "C4 bind resumes a committed flaky telegraph")
	fx.clear()
	fx._disconnect()
	host.free()
	# Many beats later the pools have not grown.
	for i in 40:
		open(fx, first_attack(i % 3, [BossAttacks.SIG_FLAKY, BossAttacks.SIG_SWEEP, BossAttacks.SIG_QUAKE][i % 3]))
		fx._process(0.2)
	check(fx.records.size() == fx.MAX_RECORDS and fx.marks.multimesh.instance_count == capacity, "C4 pools stay bounded")
	fx.clear()

## Every per-boss projectile look, from the real shots its attack fires: envelope (110 % of the
## hitbox, ground projections exempt on y), draws, shared resources, split, shadow, pause.
## Chase camera (run_config camera_position / fov, 1280x720): screen pixels per metre of an object
## at `point`, facing the camera.
static func chase_pixels_per_metre(point: Vector3) -> float:
	return 720.0 / (2.0 * tan(deg_to_rad(30.0)) * point.distance_to(Vector3(0, 4, 8)))

## Art review r1 size targets, measured on the real meshes from the chase camera.
func check_sizes() -> void:
	# Hydra heads: >= 40 px wide at the fight distance.
	var visual: Node3D = load("res://scenes/runner/boss/visuals/merge_conflict_hydra_visual.tscn").instantiate()
	var mount := Node3D.new()
	mount.position = Vector3(0, 2.6, -14)
	root.add_child(mount)
	visual.hover_z = -14.0
	mount.add_child(visual)
	visual._art = Art.new()
	visual.add_child(visual._art)
	visual._art.build(&"merge_conflict_hydra")
	visual._tag = visual._art.tag
	visual.on_spawned()
	var art: Node3D = visual._art
	var narrowest := INF
	for head: Node3D in art.heads:
		var shell := head.get_child(0) as MeshInstance3D
		var box: AABB = head.global_transform * shell.transform * shell.get_aabb()
		narrowest = minf(narrowest, box.size.x * chase_pixels_per_metre(box.get_center()))
	check(narrowest >= 40.0, "C4 hydra heads >= 40 px wide at fight distance (%.1f px)" % narrowest)
	print("C4 HYDRA HEADS: %.1f px wide at fight distance (target >= 40)" % narrowest)
	mount.free()
	# Bolts and the serpent: >= 16 px at 30 m; wall slabs >= 60 px tall where they are fired.
	var at_30 := 720.0 / (2.0 * tan(deg_to_rad(30.0)) * 30.0)
	var scene := load("res://scenes/runner/hazards/visuals/projectile_visual.tscn") as PackedScene
	for spec: Array in [[ProjectileArt.HYDRA_HEAD, "x", 16.0], [ProjectileArt.HYDRA_SWEEP, "x", 16.0], [ProjectileArt.MONOLITH_SLAB, "y", 60.0]]:
		var look: StringName = spec[0]
		var row: Array = ProjectileArt.LOOKS[look]
		var shot: Dictionary = first_attack(KINDS.find(String(row[0])), row[2]).shots[0]
		var def := HazardDefs.get_def(&"projectile", StringName(shot.variant))
		var shell: Node3D = scene.instantiate()
		shell.variant = StringName(shot.variant)
		shell.projectile_variant = StringName(shot.variant)
		shell.boss_kind = row[0]
		shell.signature = row[2]
		shell.motion = shot
		shell.hitbox_size = def.size
		shell.hitbox_offset = Vector3(0, float(def.y_min) + def.size.y * 0.5, 0)
		root.add_child(shell)
		shell.position = Vector3(0, 0, -14.0)
		shell.on_spawned()
		var box := AABB()
		var first := true
		for node: MeshInstance3D in shell._art.find_children("*", "MeshInstance3D", true, false):
			if not node.is_visible_in_tree() or node.has_meta("ground_projection"): continue
			var part: AABB = node.global_transform * node.get_aabb()
			box = part if first else box.merge(part)
			first = false
		var metres: float = box.size.x if spec[1] == "x" else box.size.y
		var pixels: float = metres * (at_30 if spec[1] == "x" else chase_pixels_per_metre(box.get_center()))
		check(pixels >= spec[2], "C4 %s size %.1f px (target >= %.0f)" % [look, pixels, spec[2]])
		print("C4 SIZE: %s %.2f m = %.1f px %s (target >= %.0f)" % [look, metres, pixels, "at 30 m" if spec[1] == "x" else "tall at the boss (z -14)", spec[2]])
		shell.free()

func check_projectiles() -> void:
	var scene := load("res://scenes/runner/hazards/visuals/projectile_visual.tscn") as PackedScene
	var looks_seen: Dictionary = {}
	var shared: Dictionary = {}
	for look: StringName in ProjectileArt.LOOKS:
		var spec: Array = ProjectileArt.LOOKS[look]
		var slot: int = KINDS.find(String(spec[0]))
		var attack := first_attack(slot, spec[2])
		check(not attack.is_empty(), "C4 attack for " + look)
		var shots: Array = attack.get("shots", [])
		for shot: Dictionary in shots:
			var def := HazardDefs.get_def(&"projectile", StringName(shot.variant))
			var size: Vector3 = def.size
			var offset := Vector3(0, float(def.y_min) + size.y * 0.5, 0)
			var visual: Node3D = scene.instantiate()
			visual.kind = &"projectile"
			visual.variant = StringName(shot.variant)
			visual.projectile_variant = StringName(shot.variant)
			visual.boss_kind = spec[0]
			visual.signature = spec[2]
			visual.motion = shot
			visual.hitbox_size = size
			visual.hitbox_offset = offset
			visual.closing_speed = float(shot.speed)
			root.add_child(visual)
			visual.on_spawned()
			var count := visual.find_children("*", "", true, false).size()
			visual.on_spawned()
			await process_frame
			check(visual.find_children("*", "", true, false).size() == count, "C4 projectile idempotent spawn " + look)
			var art: Node3D = visual._art
			check(art is ProjectileArt and art.look == look, "C4 projectile look selected " + look)
			visual.set_process(false)
			var window := BossAttacks.pass_window(shot)
			var peak := 0
			var t := 0.0
			var split_seen := false
			var shadow_small := INF
			var shadow_big := 0.0
			while t <= window.y + 0.05:
				visual._process(0.02 if t > 0.0 else 0.0)
				var draws := 0
				for node in art.find_children("*", "MeshInstance3D", true, false):
					check(node.process_mode in [Node.PROCESS_MODE_INHERIT, Node.PROCESS_MODE_PAUSABLE], "C4 projectile pause inheritance")
					if node.material_override is ShaderMaterial: check(not node.material_override.shader.code.contains("TIME"), "C4 projectile clock only")
					if not node.is_visible_in_tree(): continue
					draws += 1
					var box: AABB = visual.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
					var low := box.position - offset
					var high := box.end - offset
					var limit := size * 0.55 + Vector3.ONE * 0.002
					var ground := node.has_meta("ground_projection")
					check(low.x >= -limit.x and high.x <= limit.x and low.z >= -limit.z and high.z <= limit.z, "C4 projectile x/z envelope %s %s t=%.2f %s" % [look, node.name, t, box])
					if not ground: check(low.y >= -limit.y and high.y <= limit.y, "C4 projectile y envelope %s %s t=%.2f %s" % [look, node.name, t, box])
					else: check(absf(node.global_position.y - visual.global_position.y + art.motion_lift(art.age) - ProjectileArt.GROUND_Y) < 0.001, "C4 ground projection on the floor " + look)
					if String(node.name) == "GroundShadow":
						shadow_small = minf(shadow_small, node.scale.x)
						shadow_big = maxf(shadow_big, node.scale.x)
				peak = maxi(peak, draws)
				# Art review r1: DANGER-dominant bodies, accents only as glyphs and trims.
				var share: Vector2 = art.palette_area()
				var lit := share.x + share.y
				if art.is_visible_in_tree(): check(lit > 0.0 and share.x >= 0.5 * lit and share.y <= 0.25 * lit, "C4 projectile palette %s t=%.2f DANGER %.2f accent %.2f" % [look, t, share.x, share.y])
				if t == 0.0 and lit > 0.0: print("C4 PALETTE: %s DANGER %.0f%% accent %.0f%% of lit front area" % [look, 100.0 * share.x / lit, 100.0 * share.y / lit])
				if look == ProjectileArt.SWARM_SCATTER:
					var split: bool = art._split_at >= 0.0 and art.age >= art._split_at
					if bool(shot.twin): check(art.visible == split, "C4 scatter twin hidden until the split")
					else: check(art.parts.RHalf.visible == (not split), "C4 scatter primary carries both halves until the split")
					split_seen = split_seen or split
				if look == ProjectileArt.MONOLITH_SLAB and art._slide_dir != 0.0 and art.age >= art._shift_at and art.age < art._shift_end:
					check(art.parts.SlideChevron.visible, "C4 sliding slab shows its chevron")
				t += 0.02
			check(peak > 0 and peak <= 8, "C4 projectile draw budget %s = %d" % [look, peak])
			if look == ProjectileArt.SWARM_SCATTER: check(split_seen, "C4 scatter splits in flight")
			if look == ProjectileArt.MONOLITH_DEBRIS: check(shadow_big > shadow_small * 2.0, "C4 debris shadow grows until landing")
			# Shared, never per-spawn, resources.
			var cached: Array = ProjectileArt._cache.values()
			for node in art.find_children("*", "MeshInstance3D", true, false):
				check(cached.has(node.mesh) and cached.has(node.material_override), "C4 projectile resources come from the shared cache " + look)
				var key := "%s:%s" % [look, node.name]
				if shared.has(key): check(is_same(shared[key], node.material_override), "C4 projectile materials shared across spawns " + key)
				else: shared[key] = node.material_override
			# Clock-driven: a paused tree freezes the look.
			visual.set_process(true)
			var age: float = art.age
			paused = true
			await process_frame
			await process_frame
			check(art.age == age, "C4 projectile freezes on pause " + look)
			paused = false
			visual.on_cleared()
			check(not visual.visible, "C4 cleared projectile hidden " + look)
			visual.free()
			looks_seen[look] = true
		print("C4 PROJECTILE LOOK: %s (%d shots)" % [look, shots.size()])
	check(looks_seen.size() == ProjectileArt.LOOKS.size(), "C4 every look exercised")
	# Base looks stay on hazard_art for everything else.
	for spec in [[&"", &"orb"], [&"legacy_monolith", &"wide"], [&"flaky_test_swarm", &"high"]]:
		var visual: Node3D = scene.instantiate()
		visual.variant = spec[1]
		visual.projectile_variant = spec[1]
		visual.boss_kind = spec[0]
		visual.hitbox_size = HazardDefs.get_def(&"projectile", spec[1]).size
		root.add_child(visual)
		visual.on_spawned()
		check(not (visual._art is ProjectileArt) and visual.get_node_or_null("Artwork") != null, "C4 base look fallback %s %s" % spec)
		visual.free()

## Accepted GLBs run the same public phases, tool reactions, signatures and cinematic modes.
## Old geometry-specific art rounds above still run in full against forced missing-GLB fallback.
func check_glb_bosses() -> void:
	for kind in KINDS:
		var path := "res://Assets/runner/bosses/%s/%s.glb" % [kind, kind]
		check(ResourceLoader.exists(path), "accepted GLB exists " + kind)
		var mount := Node3D.new()
		mount.position = Vector3(0, 2.6, -14)
		root.add_child(mount)
		var visual: Node3D = load("res://scenes/runner/boss/visuals/%s_visual.tscn" % kind).instantiate()
		visual.kind = StringName(kind)
		visual.hover_z = -14
		visual.sway_amplitude = 2.4
		mount.add_child(visual)
		visual.on_spawned()
		visual.set_process(false)
		var model: Node3D = visual.get("_model")
		check(model != null and visual.get("_art") == null, "GLB owns production geometry " + kind)
		if model == null:
			mount.free()
			continue
		for action: StringName in BossModel.ACTIONS:
			check(model.animation_player.has_animation(action), "GLB action " + kind + " " + action)
		for socket: StringName in BossModel.SOCKETS:
			check(model.socket(socket) != null, "GLB socket " + kind + " " + socket)
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.replace(".glb", ".build.json")))
		check(int(report.get("triangles", 999999)) <= 18000 and int(report.get("materials", 999)) <= 4 and int(report.get("bones", 999)) <= 40, "GLB authored budget " + kind)
		for phase in [1, 2, 3]:
			visual.set_phase(phase)
			visual.set_health(100 - phase * 25, 100)
			visual._process(0.3)
			pose_context = "phase=%d at .3s" % phase
			inspect_glb(visual)
		var signature_peak := Vector2i.ZERO
		for pair: Array in boss_attacks(KINDS.find(kind)):
			visual.on_spawned()
			visual.set_phase(pair[0])
			var attack: Dictionary = pair[1]
			visual.play_telegraph(int(attack.telegraph_mask), StringName(attack.variant), float(attack.telegraph))
			visual._process(float(attack.telegraph) * 0.5)
			pose_context = "phase=%d variant=%s mask=%d half-telegraph" % [pair[0], attack.variant, attack.telegraph_mask]
			inspect_glb(visual)
			visual.play_commit(int(attack.telegraph_mask), StringName(attack.variant), 0.25)
			visual._process(0.15)
			pose_context += " commit+.15s"
			inspect_glb(visual)
			visual.play_attack(StringName(attack.variant))
			for frame in 4:
				visual._process(0.08)
				pose_context = "phase=%d variant=%s mask=%d attack frame=%d at %.2fs" % [pair[0], attack.variant, attack.telegraph_mask, frame, (frame + 1) * .08]
				inspect_glb(visual)
		for tool in [&"review_comment", &"lint_rule", &"unit_test", &"auto_fix_patch"]:
			visual.play_hit(tool, 15)
			visual._process(0.08)
			check(float(model.materials[0].get_shader_parameter("flash")) > 0, "GLB hit flash")
			visual.play_resist(tool)
			visual._process(0.08)
			inspect_glb(visual)
		for mode in [&"intro_full", &"intro_short", &"defeat_full", &"defeat_short"]:
			visual.on_spawned()
			visual.play_cinematic(mode, 3.6)
			for frame in 37:
				pose_context = "%s frame=%d/36" % [mode, frame]
				visual.set_cinematic_progress(mode, float(frame) / 36)
				inspect_glb(visual)
			if String(mode).begins_with("defeat"):
				check(not model.visible or float(model.materials[0].get_shader_parameter("dissolve")) >= 0.999, "GLB dissolves at cinematic end")
		visual.on_spawned()
		var clock_before: float = visual.get("_clock")
		visual.set_process(true)
		paused = true
		await process_frame
		await process_frame
		check(visual.get("_clock") == clock_before, "GLB animation freezes on pause")
		paused = false
		mount.free()

func inspect_glb(visual: Node3D) -> void:
	var bounds := AABB()
	var first := true
	var tris := 0
	var draws := 0
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		var box := BossBounds.mesh_bounds(mesh)
		bounds = box if first else bounds.merge(box)
		first = false
		tris += triangles(mesh.mesh)
		draws += mesh.mesh.get_surface_count()
	if first: return
	check(bounds.position.x >= -3.501 and bounds.end.x <= 3.501, "GLB posed X envelope %s %s %s " % [visual.kind, visual.get("_state"), visual.get("_cinematic_mode")] + str(bounds))
	check(bounds.position.y >= 1.599 and bounds.end.y <= 6.101, "GLB posed Y envelope %s %s %s " % [visual.kind, visual.get("_state"), pose_context] + str(bounds))
	check(bounds.size.z <= 3.001, "GLB posed depth envelope " + str(bounds))
	check(tris <= 18000 and draws <= 6, "GLB runtime mesh budget")
	boss_peak_draws = maxi(boss_peak_draws, draws)
