extends SceneTree
const Art = preload("res://scenes/runner/powerups/visuals/power_up_art.gd")
const Forge = preload("res://scenes/runner/powerups/visuals/hifi/mesh_forge.gd")
const Finish = preload("res://scenes/runner/powerups/visuals/hifi/pickup_materials.gd")
const Textures = preload("res://scenes/runner/powerups/visuals/hifi/texture_forge.gd")
const Capture = preload("res://scenes/runner/powerups/dev/capture_a4.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const KINDS := [&"approve_shield",&"auto_fix",&"lgtm",&"nitro",&"super_jump",&"code_review",&"review_comment",&"lint_rule",&"unit_test",&"auto_fix_patch"]
var checks := 0
var failures := 0
var silhouettes: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("A4: " + message)

func triangles(mesh: Mesh) -> int:
	var count := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return count

func chart_check(mesh: Mesh) -> void:
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var valid := not uvs.is_empty()
		for uv in uvs:
			valid = valid and uv.x >= -0.0001 and uv.x <= 1.0001 and uv.y >= -0.0001 and uv.y <= 1.0001
		check(valid,"local face/tube charts stay within [0,1]")
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var nondegenerate := true
		for face in range(0,indices.size(),3):
			var a := uvs[indices[face]]
			var b := uvs[indices[face+1]]
			var c := uvs[indices[face+2]]
			nondegenerate = nondegenerate and absf((b-a).cross(c-a)) > 0.00000001
		check(nondegenerate,"bevel and cap charts have nonzero UV area")

func mesh_points(node: Node3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point in vertices: points.append(node.transform*point)
	elif node is MultiMeshInstance3D:
		var vertices: PackedVector3Array = node.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for instance in node.multimesh.instance_count:
			var pose: Transform3D = node.transform*node.multimesh.get_instance_transform(instance)
			for point in vertices: points.append(pose*point)
	return points

func raster(mesh: Mesh, pose: Transform3D, pixels: PackedByteArray) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var points: Array[Vector2] = []
			for j in 3:
				var p := pose*vertices[indices[i+j]]
				points.append(Vector2((p.x+0.384)/0.768*24,(p.y+0.48)/0.96*32))
			var a := points[0]
			var b := points[1]
			var c := points[2]
			if absf((b-a).cross(c-a)) < 0.0001: continue
			for y in range(maxi(0,int(floorf(minf(a.y,minf(b.y,c.y))))),mini(32,int(ceilf(maxf(a.y,maxf(b.y,c.y)))))):
				for x in range(maxi(0,int(floorf(minf(a.x,minf(b.x,c.x))))),mini(24,int(ceilf(maxf(a.x,maxf(b.x,c.x)))))):
					var p := Vector2(x+0.5,y+0.5)
					var d0 := (b-a).cross(p-a)
					var d1 := (c-b).cross(p-b)
					var d2 := (a-c).cross(p-c)
					if (d0 >= 0 and d1 >= 0 and d2 >= 0) or (d0 <= 0 and d1 <= 0 and d2 <= 0): pixels[y*24+x] = 1

func silhouette(art: Art) -> PackedByteArray:
	var pixels := PackedByteArray()
	pixels.resize(24*32)
	for node in art._pivot.get_children():
		if node is MeshInstance3D: raster(node.mesh,node.transform,pixels)
		elif node is MultiMeshInstance3D:
			for i in node.multimesh.instance_count: raster(node.multimesh.mesh,node.transform*node.multimesh.get_instance_transform(i),pixels)
	return pixels

func forge_checks() -> void:
	var forge := Forge.new()
	forge.tube(PackedVector3Array([Vector3.ZERO,Vector3.UP]),0.1)
	var mesh := forge.finish()
	check(triangles(mesh) == 96,"24-sided tube plus both 24-triangle caps")
	chart_check(mesh)
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var smooth_normals: Dictionary = {}
	var caps := [false,false]
	for i in normals.size():
		check(is_equal_approx(normals[i].length(),1.0),"unit normals")
		if absf(normals[i].y) < 0.001: smooth_normals[str(normals[i].snapped(Vector3.ONE*0.001))] = true
		if normals[i].y < -0.99: caps[0] = true
		if normals[i].y > 0.99: caps[1] = true
	check(smooth_normals.size() == 24,"smooth radial vertex normals")
	check(caps[0] and caps[1],"both open ends sealed")
	var outward := true
	for i in range(0,indices.size(),3):
		var a := indices[i]
		var b := indices[i+1]
		var c := indices[i+2]
		outward = outward and (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).dot(normals[a]+normals[b]+normals[c]) < 0
	check(outward,"clockwise winding supports back-face culling")
	# A closed tube has a continuous transported frame at the join.
	var ring_forge := Forge.new()
	ring_forge.ring(Vector3.ZERO,0.2,0.02)
	var ring_mesh := ring_forge.finish()
	var ring_arrays := ring_mesh.surface_get_arrays(0)
	var ring_uvs: PackedVector2Array = ring_arrays[Mesh.ARRAY_TEX_UV]
	var ring_normals: PackedVector3Array = ring_arrays[Mesh.ARRAY_NORMAL]
	var ring_vertices: PackedVector3Array = ring_arrays[Mesh.ARRAY_VERTEX]
	var seam_start: Dictionary = {}
	var seam_end: Dictionary = {}
	for i in ring_uvs.size():
		var cross_index := roundi(ring_uvs[i].y*24)
		if is_zero_approx(ring_uvs[i].x): seam_start[cross_index] = i
		if is_equal_approx(ring_uvs[i].x,1.0): seam_end[cross_index] = i
	check(seam_start.size() == 25 and seam_end.size() == 25,"complete transported tube seam")
	for cross_index in seam_start:
		var a: int = seam_start[cross_index]
		var b: int = seam_end[cross_index]
		check(ring_normals[a].is_equal_approx(ring_normals[b]) and ring_vertices[a].is_equal_approx(ring_vertices[b]),"tube seam position and normal continuity")
	var inset := forge.inset(PackedVector2Array([Vector2(-2,-1),Vector2(2,-1),Vector2(2,1),Vector2(-2,1)]),0.1)
	check(inset[0].is_equal_approx(Vector2(-1.9,-0.9)),"edge-normal inset keeps constant chamfer width")

func material_checks() -> void:
	var a := Finish.material(Palette.MINT,1.0)
	var b := Finish.material(Palette.ORANGE,2.0)
	var glass := Finish.material(Palette.MINT,1.0,1.0)
	var other_glass := Finish.material(Palette.MATRIX,2.0,1.0)
	var pool := Finish.pool(Palette.MINT)
	var other_pool := Finish.pool(Palette.MATRIX)
	check(a.shader == b.shader and glass.shader == other_glass.shader and a.shader != glass.shader,"exactly two surface shader variants")
	check(pool.shader == other_pool.shader,"pool shader is cached")
	check(Finish.cache.size() == 3,"two surface templates plus one pool template")
	var baseline: Variant = Finish.template("opaque").get_shader_parameter("clock")
	a.set_shader_parameter("clock",19.0)
	a.set_shader_parameter("tint",Palette.DANGER)
	pool.set_shader_parameter("clock",13.0)
	check(Finish.template("opaque").get_shader_parameter("clock") == baseline,"cached template never mutated")
	check(b.get_shader_parameter("tint") == Palette.ORANGE and other_pool.get_shader_parameter("clock") != 13.0,"spawn uniforms are isolated")
	for template: ShaderMaterial in Finish.cache.values():
		check(not template.shader.code.contains("TIME") and not template.shader.code.contains("cull_disabled"),"clock-driven back-face culled shader")
	check(not Finish.CODE.contains("fract(") and not Finish.CODE.contains("float circuit"),"no tiled emissive masonry")
	check(Finish.CODE.contains("world_height*5.23598776") and Finish.CODE.contains("MODEL_MATRIX"),"scan density fixed at one band per 1.2 world metres")
	check(Finish.CODE.contains("fwidth(wave)") and Finish.CODE.contains("smoothstep("),"derivative-filtered broad scan")
	check(Finish.CODE.contains("0.12*scan") and Finish.CODE.contains("emission_fill"),"subdued scan with steady glyph emission")
	check(Finish.CODE.contains("0.30*sin(clock*4.0)"),"0.7 to 1.3 emission pulse")
	var maps := Textures.maps()
	check(maps.size() == 4 and maps.albedo == Textures.maps().albedo,"four shared cached maps")
	for texture: Texture2D in maps.values():
		check(texture.get_width() == 256 and texture.get_height() == 256,"256 square maps")
		check(texture.get_image().has_mipmaps(),"texture mipmaps present")
	var occupied := 0
	for y in 256:
		if Textures.height_at(64,y) > 0.525: occupied += 1
	check(occupied < 64,"no repeating solid masonry seam at x=64")
	check(Textures.height_at(24,60) > Textures.height_at(32,60)+0.025,"sparse circuit trace relief")
	var environment := Capture.fixture_environment()
	check(environment.glow_enabled and is_equal_approx(environment.glow_hdr_threshold,0.75),"capture glow enabled at 0.75")
	check(environment.background_color == Palette.NAVY_BG and environment.ambient_light_color == Palette.NAVY_2,"capture uses corridor darkness")
	check(Capture.FILL_ENERGY <= 0.2,"capture fill energy bounded")

func attachment_checks(art: Art, kind: StringName) -> void:
	var bounds: Array[AABB] = []
	for node in art._pivot.get_children():
		var points := mesh_points(node)
		if points.is_empty(): continue
		var box := AABB(points[0],Vector3.ZERO)
		for point in points: box = box.expand(point)
		bounds.append(box)
	for i in bounds.size():
		var attached := false
		for j in bounds.size():
			if i != j and bounds[i].intersects(bounds[j]): attached = true
		check(attached,"sculpture child AABB overlaps a sibling " + kind)
	var frame: MeshInstance3D = art._pivot.get_node("Ring")
	var frame_parts: Array = frame.mesh.get_meta("panel_bounds")
	if kind == &"code_review":
		check(art._core_node.mesh.get_meta("panel_bounds").size() == 2,"two broad REVIEW rows")
		check(frame.material_override.get_shader_parameter("tint") == Palette.SLATE and frame.material_override.get_shader_parameter("energy") > 0.0,"SLATE magnifier with low rim fill")
		var colors: PackedColorArray = frame.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var has_dark_card := false
		for color in colors:
			if color.r < 0.2: has_dark_card = true
		check(has_dark_card,"dark card vertex color preserves contrast without another draw")
	if kind == &"lgtm":
		check(frame_parts.size() == 2 and frame_parts[0].intersects(frame_parts[1]),"LGTM cuff overlaps hand, including within merged metal mesh")
	if kind == &"auto_fix_patch":
		var parts: Array = art._core_node.mesh.get_meta("panel_bounds")
		check(parts.size() == 2,"PATCH has two attached inlays")
		for part: AABB in parts:
			var transformed: AABB = art._core_node.transform*part
			var attached := false
			var gem: MeshInstance3D = art._pivot.get_node("Gem")
			var glass_parts: Array = gem.mesh.get_meta("panel_bounds")
			for glass_part: AABB in glass_parts:
				if transformed.intersects(gem.transform*glass_part): attached = true
			check(attached,"PATCH inlay overlaps a chevron through the entire idle")

func run() -> void:
	forge_checks()
	material_checks()
	var backend := FileAccess.get_file_as_string("res://scenes/runner/powerups/power_up.gd")
	check(backend.contains("DEFAULT_PICKUP_RADIUS := 0.35"),"pickup radius remains 0.35")
	for kind in KINDS:
		var scene := Node3D.new()
		root.add_child(scene)
		var tools_root := Node3D.new()
		tools_root.name = "Tools"
		scene.add_child(tools_root)
		var pickup := Area3D.new()
		tools_root.add_child(pickup)
		var visual := (load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % kind) as PackedScene).instantiate() as Node3D
		pickup.add_child(visual)
		visual.position.y = 2.2 if kind == &"auto_fix_patch" else 1.0
		visual.set("kind",kind)
		visual.on_spawned()
		var art: Art = visual._art
		var count := visual.find_children("*","",true,false).size()
		visual.on_spawned()
		check(count == visual.find_children("*","",true,false).size(),"idempotent spawn " + kind)
		silhouettes[kind] = silhouette(art)
		check(art._tag.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y and art._tag.outline_size >= 6,"Y-billboard tag with outline")
		var tag_pose := art._tag.transform
		var plate: MeshInstance3D = art.get_node("TagPlate")
		var plate_pose := plate.transform
		var tag_font: Font = art._tag.font if art._tag.font != null else ThemeDB.fallback_font
		var text_width := (tag_font.get_string_size(art._tag.text,HORIZONTAL_ALIGNMENT_LEFT,-1,art._tag.font_size).x+art._tag.outline_size*2)*art._tag.pixel_size
		check(text_width <= 0.77 and plate.mesh.get_aabb().size.x <= 0.77,"tag and backing horizontal footprint")
		var draws := 0
		var tris := 48
		for node in visual.find_children("*","",true,false):
			check(node.process_mode == Node.PROCESS_MODE_PAUSABLE,"pausable " + node.name)
			check(not node is CollisionObject3D and not node is CollisionShape3D,"cosmetic only")
			if node is MeshInstance3D:
				draws += node.mesh.get_surface_count()
				tris += triangles(node.mesh)
				chart_check(node.mesh)
				check(not node.material_override.shader.code.contains("TIME"),"clock shader")
			elif node is MultiMeshInstance3D:
				draws += node.multimesh.mesh.get_surface_count()
				tris += triangles(node.multimesh.mesh)*node.multimesh.instance_count
				chart_check(node.multimesh.mesh)
				check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,"MultiMesh interpolation OFF")
			elif node is Label3D:
				draws += 1 if node.outline_size == 0 else 2
				tris += node.text.length()*4
		check(draws+1 <= 8,"peak draw cap " + kind)
		check(tris <= 3000,"triangle cap " + kind)
		if kind == &"lint_rule":
			var teeth: MultiMeshInstance3D = art._pivot.get_node("CombTeeth")
			check(teeth.material_override.get_shader_parameter("tint") == Palette.MATRIX,"MATRIX comb teeth")
			check(teeth.multimesh.mesh.get_aabb().size.is_equal_approx(Vector3(0.048,0.38,0.075)),"native tooth mesh dimensions")
			for i in teeth.multimesh.instance_count:
				check(teeth.multimesh.get_instance_transform(i).basis == Basis.IDENTITY,"teeth translate without nonuniform scaling")
		for sample in 40:
			art._process(0.125)
			attachment_checks(art,kind)
			for node in art._pivot.get_children():
				var max_radius := 0.0
				var min_y := INF
				var max_y := -INF
				for point in mesh_points(node):
					var p: Vector3 = art._pivot.transform*point
					max_radius = maxf(max_radius,Vector2(p.x,p.z).length())
					min_y = minf(min_y,p.y)
					max_y = maxf(max_y,p.y)
				check(max_radius <= 0.385,"horizontal 110 percent footprint " + kind)
				check(min_y >= -0.46 and max_y <= 0.46,"authored vertical idle bound " + kind)
		check(art._tag.transform == tag_pose and plate.transform == plate_pose,"tag and plate never follow sculpture spin")
		check(is_equal_approx(art._pool.global_position.y,0.012),"pool at floor")
		var t := art._t
		paused = true
		await process_frame
		await process_frame
		check(art._t == t,"pause freezes clock")
		paused = false
		visual.on_collected()
		visual.on_collected()
		var bursts := scene.find_children("A4CollectBurst*","GPUParticles3D",false,false)
		check(bursts.size() == 1,"one scene-owned burst per collection")
		check(tools_root.get_child_count() == 1,"burst never enters backend tool census")
		if not bursts.is_empty(): check(bursts[0].amount <= 64 and bursts[0].one_shot,"bounded burst")
		art._process(0.251)
		check(not visual.visible,"collection hides")
		visual.on_spawned()
		check(visual.visible and art._collect_time < 0.0,"reuse resets collection")
		pickup.free()
		if not bursts.is_empty(): check(is_instance_valid(bursts[0]),"burst survives pickup removal")
		scene.free()
		if not bursts.is_empty(): check(not is_instance_valid(bursts[0]),"scene exit frees burst immediately")
		print("A4 CENSUS %s: %d idle / %d peak draws, %d peak triangles" % [kind,draws,draws+1,tris])
	var minimum_difference := 10000
	for i in KINDS.size():
		for j in range(i+1,KINDS.size()):
			var different := 0
			for pixel in 24*32:
				if silhouettes[KINDS[i]][pixel] != silhouettes[KINDS[j]][pixel]: different += 1
			minimum_difference = mini(minimum_difference,different)
			check(different >= 10,"distinct projected sculpture silhouettes %s/%s" % [KINDS[i],KINDS[j]])
	print("A4 SILHOUETTES: 10 unique; minimum pairwise difference %d / 768 samples" % minimum_difference)
	Finish.cache.clear()
	Textures.cache.clear()
	check(Finish.cache.is_empty() and Textures.cache.is_empty(),"static caches released before quit")
	# The actual previous exit leak was the global MP3 playback, not these caches.
	var audio := root.get_node_or_null("AudioService")
	if audio != null:
		audio.shutdown()
		audio.default_track = null
	await create_timer(0.2).timeout
	print("ASSET A4: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)
