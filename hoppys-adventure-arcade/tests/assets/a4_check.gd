extends SceneTree
const Art = preload("res://scenes/runner/powerups/visuals/power_up_art.gd")
const Grab = preload("res://scenes/runner/powerups/visuals/hifi/grab_affordance.gd")
const Forge = preload("res://scenes/runner/powerups/visuals/hifi/mesh_forge.gd")
const Finish = preload("res://scenes/runner/powerups/visuals/hifi/pickup_materials.gd")
const Textures = preload("res://scenes/runner/powerups/visuals/hifi/texture_forge.gd")
const Burst = preload("res://scenes/runner/powerups/visuals/hifi/collect_burst.gd")
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
	var emission_baseline: Variant = Finish.template("opaque").get_shader_parameter("emission_tint")
	a.set_shader_parameter("emission_tint",Art.BODY_MINT)
	check(b.get_shader_parameter("emission_tint") == Palette.ORANGE and Finish.template("opaque").get_shader_parameter("emission_tint") == emission_baseline,"R7 emission tint never mutates another instance or cache")
	check(Grab.TOOL_GLYPH_TINT.is_equal_approx(Palette.ORANGE.darkened(0.08)),"R9 tool glyph tint is derived from palette ORANGE")
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
	check(Capture.CORRIDOR.resource_path == "res://scenes/runner/environment/corridor.tscn","capture mounts shipping corridor")

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
	check(frame.mesh.get_aabb().size.z >= 0.24,"equipment has physical depth " + kind)
	check(frame.material_override.get_shader_parameter("tint") == Palette.CREAM,"neutral equipment shell separates friendly inlays")

func run() -> void:
	root.size = Vector2i(1280,720)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,4,8)
	camera.look_at(Vector3(0,1,-8))
	camera.fov = 60
	camera.make_current()
	round5_fixture_checks()
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
		affordance_checks(art, camera, kind)
		var count := visual.find_children("*","",true,false).size()
		visual.on_spawned()
		check(count == visual.find_children("*","",true,false).size(),"idempotent spawn " + kind)
		silhouettes[kind] = silhouette(art)
		check(art._tag.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y and art._tag.outline_size >= 6,"outlined Y-billboard tag over real grid")
		var tag_pose := art._tag.transform
		var plate_pose := art._tag_plate.transform
		check(art.has_node("TagPlate") and art._tag_plate.get_parent() == art,"R9 plate is independent of spinning sculpture")
		check(art._tag_plate.material_override.get_shader_parameter("tint") == Palette.NAVY_2 and art._tag_plate.material_override.get_shader_parameter("energy") == 0.0,"R9 opaque unlit NAVY_2 backing")
		check(not art._tag_plate.material_override.shader.code.contains("ALPHA ="),"R9 plate uses opaque surface shader")
		var tag_font: Font = art._tag.font if art._tag.font != null else ThemeDB.fallback_font
		var text_width := (tag_font.get_string_size(art._tag.text,HORIZONTAL_ALIGNMENT_LEFT,-1,art._tag.font_size).x+art._tag.outline_size*2)*art._tag.pixel_size
		check(text_width <= 0.72,"tag fits enlarged backing")
		check(is_equal_approx(art._tag.pixel_size,0.0045),"R10 readable tag pixel size")
		check(art._tag_plate.mesh.get_aabb().size.is_equal_approx(Vector3(0.72,0.16,0.025)),"R10 enlarged tag backing bounds")
		var draws := 0
		var tris := 48
		for node in visual.find_children("*","",true,false):
			check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,"interpolation OFF " + node.name)
			if node is GeometryInstance3D and node.material_override is ShaderMaterial:
				check(node.material_override.get_shader_parameter("tint") in [Palette.MINT,Palette.MATRIX,Palette.ORANGE,Palette.CREAM,Palette.SLATE,Palette.NAVY_2,Grab.TOOL_GLYPH_TINT,Art.FRAME_MINT,Art.FRAME_ORANGE,Art.FRAME_REVIEW],"friendly or neutral material, never DANGER " + kind)
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
		for sample in 40:
			art._process(0.125)
			check(absf(art._pivot.rotation.y) <= 0.2801,"solid pickup stays readable through its full idle cycle")
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
				check(min_y >= -0.52 and max_y <= 0.52,"authored vertical idle bound " + kind)
		check(art._tag.transform == tag_pose and art._tag_plate.transform == plate_pose,"R9 label and restored plate remain fixed through sculpture spin")
		check(is_equal_approx(art._pool.global_position.y,Art.POOL_Y) and Art.POOL_Y <= 0.05,"pool at floor")
		# The corridor LaneGlow decal sits at y 0.012; a shared plane z-fights.
		check(absf(Art.POOL_Y-0.012) >= 0.02,"pool clear of the corridor lane glow plane")
		var glyph_pose := art._glyph.transform
		var beacon_clock: Variant = art._pool.material_override.get_shader_parameter("clock")
		var fade := art._rear_mix
		var offset := art._beam_offset
		var t := art._t
		paused = true
		await process_frame
		await process_frame
		check(art._t == t,"pause freezes clock")
		check(art._rear_mix == fade and art._beam_offset == offset,"R6 pause freezes fade and stagger")
		check(art._glyph.transform == glyph_pose and art._pool.material_override.get_shader_parameter("clock") == beacon_clock,"pause freezes glyph and beacon")
		paused = false
		visual.on_collected()
		check(not art._pool.visible and not art._glyph.visible,"collection removes beacon and glyph")
		visual.on_collected()
		var bursts := scene.find_children("A4CollectBurst*","GPUParticles3D",false,false)
		check(bursts.size() == 1,"one scene-owned burst per collection")
		check(tools_root.get_child_count() == 1,"burst never enters backend tool census")
		if not bursts.is_empty(): check(bursts[0].amount <= 64 and bursts[0].one_shot,"bounded burst")
		art._process(0.251)
		check(not visual.visible,"collection hides")
		visual.on_spawned()
		check(visual.visible and art._collect_time < 0.0 and art._pool.visible and art._glyph.visible,"reuse resets collection")
		if not bursts.is_empty():
			# Pooled burst: an idle one is restarted, never rebuilt, and its draw pass is shared.
			bursts[0]._process(Burst.LIFETIME)
			check(not bursts[0].busy,"burst idles after its lifetime instead of freeing")
			visual.on_collected()
			check(scene.find_children("A4CollectBurst*","GPUParticles3D",false,false).size() == 1 and bursts[0].busy,"repeat collection reuses the pooled burst")
			check(bursts[0].draw_pass_1 == Burst.draw_mesh(art._accent),"burst draw pass shared per accent")
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
	Art.release_caches()
	Burst.release_caches()
	Finish.cache.clear()
	Textures.cache.clear()
	check(Finish.cache.is_empty() and Textures.cache.is_empty() and Art._kind_cache.is_empty(),"static caches released before quit")
	# The actual previous exit leak was the global MP3 playback, not these caches.
	var audio := root.get_node_or_null("AudioService")
	if audio != null:
		audio.shutdown()
		audio.default_track = null
	await create_timer(0.2).timeout
	print("ASSET A4: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func affordance_checks(art: Art, camera: Camera3D, kind: StringName) -> void:
	var hue := Palette.ORANGE if art._is_tool else Palette.MINT
	check(art.has_node("BeaconRingHalo") and art.has_node("HologramGlyph"),"beam ring halo and glyph exist " + kind)
	check(art._pool.mesh.get_aabb().size.is_equal_approx(Vector3(2.4,3.2,2.4)),"beacon height and halo bounds")
	check(art._pool.get_meta("ring_diameter") >= 1.2 and art._pool.get_meta("ring_diameter") <= 1.6,"ring diameter")
	for node in [art._pool,art._glyph]:
		check(node.material_override.get_shader_parameter("tint") == (Grab.TOOL_GLYPH_TINT if node == art._glyph and art._is_tool else hue),"friendly hue " + kind)
		check(not node.material_override.shader.code.contains("TIME"),"pausable affordance shader")
	round5_affordance_checks(art,camera,kind)
	var frame: MeshInstance3D = art._pivot.get_node("Ring")
	check(triangles(frame.mesh) == frame.mesh.get_meta("expected_triangles"),"R9 merged surface retains every frame, backing and inlay triangle")
	var frame_colors: PackedColorArray = frame.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var has_inlay := false
	var has_frame := false
	for color in frame_colors:
		has_inlay = has_inlay or color.a < 0.75
		has_frame = has_frame or color.a >= 0.75
	check(has_inlay and has_frame,"R9 per-face frame and inlay shading retained")
	check(kind in Art.BACKED_KINDS,"R9 every kind receives the same small closed core")
	if kind in Art.BACKED_KINDS:
		var backing_found := false
		for bounds: AABB in frame.mesh.get_meta("panel_bounds"):
			if bounds.size.is_equal_approx(Vector3(0.3,0.3,0.26)) and bounds.position.is_equal_approx(Vector3(-0.15,-0.15,-0.22)): backing_found = true
		check(backing_found,"R8 closed 0.30m backing is merged behind thin silhouette " + kind)
	check(is_equal_approx(art._pool.material_override.get_shader_parameter("beam_core_gain"),1.12 if art._is_tool else 1.0),"R8 twelve percent boost isolated to tool beam cores")
	check(is_equal_approx(frame.material_override.get_shader_parameter("energy"),0.12),"Subdued hardware emission across both families")
	if not art._is_tool:
		for node in art._pivot.get_children():
			check(node.material_override.get_shader_parameter("emission_tint") == Art.BODY_MINT,"R7 every MINT body surface emits deeper mint")
	check(is_equal_approx(art._glyph.material_override.get_shader_parameter("glyph_gain"),0.675 if art._is_tool else 0.75),"R7 isolated ten percent tool glyph reduction")
	check(frame.material_override.get_shader_parameter("tint") == Palette.CREAM,"Neutral hardware with colored functional inlays")
	check(Finish.CODE.contains("METALLIC = mix(0.32, 0.18, glassness);"),"R10 diffuse response retained without reflection probe")
	check(Finish.CODE.contains("max(texture(plating, UV).rgb, vec3(0.55))"),"R10 plating cannot eat diffuse lift")
	check(Finish.CODE.contains("mix(min(texture(roughness_map, UV).r, 0.62), 0.19, glassness)"),"R10 roughness ceiling")
	var pose: Vector3 = art.get_parent().position
	# Sixty metres ahead of the player, camera at the actual contract pose.
	art.get_parent().position = Vector3(0,1,-60)
	art._update_affordance()
	check(float(frame.material_override.get_shader_parameter("range_boost")) <= 3.0,"R9 body range gain capped at three")
	var projected := Capture.projected_body_rect(camera,art._pivot)
	var contains_body := true
	for node in art._pivot.get_children():
		for point in mesh_points(node):
			var pixel := camera.unproject_position(art._pivot.to_global(point))
			contains_body = contains_body and pixel.x >= projected.position.x+1 and pixel.y >= projected.position.y+1 and pixel.x <= projected.end.x-1 and pixel.y <= projected.end.y-1
	check(contains_body,"R8 projected animated sculpture bounds include one-pixel dilation")
	var center := art._glyph.global_position
	var up := camera.global_basis.y*art._glyph.scale.y*art._glyph_coverage*0.5
	var pixels := camera.unproject_position(center+up).distance_to(camera.unproject_position(center-up))
	print("A4 GLYPH %s: %.2f visible pixels at 60m" % [kind,pixels])
	check(pixels >= 23.0 and pixels <= 36.0,"60m bounded attached vector glyph 23..36px: %.2f " % pixels + kind)
	check(is_equal_approx(art._near_fade,1.0),"far beam full intensity")
	# Compare projected quad area for the same glyph, so its alpha coverage is constant.
	for lane in [-2.0,0.0,2.0]:
		var previous_area := INF
		for distance in [20.0,40.0,60.0]:
			art.get_parent().position = Vector3(lane,1,-distance)
			art._update_affordance()
			var corners := PackedVector2Array()
			for corner in [Vector3(-0.5,-0.5,0),Vector3(0.5,-0.5,0),Vector3(0.5,0.5,0),Vector3(-0.5,0.5,0)]:
				corners.append(camera.unproject_position(art._glyph.to_global(corner)))
			var screen_area := polygon_area(corners)
			check(screen_area <= previous_area+0.01,"R10 glyph area decreases with depth " + kind)
			previous_area = screen_area

	for distance in [0.0,3.0,6.0,15.0]:
		# Test forward depth independent of the camera's pitch.
		art.global_position = camera.to_global(Vector3(0,0,-8.0-distance))
		art._update_affordance()
		check(is_equal_approx(art._near_fade,smoothstep(0.0,6.0,distance)),"last six metres beam fade")
		check(art._glyph.scale.x > 0.0 and art._glyph.scale.x <= 3.8,"R10 near glyph keeps corridor clamp")
	art.position = Vector3.ZERO
	art.get_parent().position = pose
	art._update_affordance()
	var area := Vector2.ZERO
	for node in art._pivot.get_children():
		var shape: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
		var measured := emission_area(shape,float(node.material_override.get_shader_parameter("emission_inset")))
		if node is MultiMeshInstance3D: measured *= node.multimesh.instance_count
		if float(node.material_override.get_shader_parameter("energy")) <= 0.0: measured.y = 0.0
		area += measured
	var coverage := area.y/area.x
	print("A4 EMISSIVE %s: %.2f percent sculpture area" % [kind,coverage*100.0])
	check(coverage <= 0.4 and Finish.CODE.contains("emission_mask * glow_tint"),"masked emissive surface below forty percent")

func polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in points.size(): area += points[i].cross(points[(i+1)%points.size()])
	return absf(area)*0.5

func emission_area(mesh: Mesh, inset: float) -> Vector2:
	# Exact UV polygon clipping weighted by each triangle's real surface area.
	var result := Vector2.ZERO
	var interior := PackedVector2Array([Vector2(inset,inset),Vector2(1.0-inset,inset),Vector2(1.0-inset,1.0-inset),Vector2(inset,1.0-inset)])
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var a := indices[i]
			var b := indices[i+1]
			var c := indices[i+2]
			var area := (points[b]-points[a]).cross(points[c]-points[a]).length()*0.5
			var triangle := PackedVector2Array([uvs[a],uvs[b],uvs[c]])
			var unlit := 0.0
			for clipped in Geometry2D.intersect_polygons(triangle,interior): unlit += polygon_area(clipped)
			result.x += area
			result.y += area*clampf(unlit/polygon_area(triangle),0.0,1.0)
	return result

func round5_fixture_checks() -> void:
	var corridor := Capture.CORRIDOR.instantiate()
	root.add_child(corridor)
	for title in ["Floor","Ceiling","WallL","WallR","LaneGlow","FarGlow","Rain","Sun","KeyLight"]:
		check(corridor.has_node(title),"shipping capture fixture includes " + title)
	check(corridor.get_node("Floor").material_override.shader.resource_path.ends_with("floor_grid.gdshader"),"capture includes emissive shipping floor")
	corridor.free()
	var source := FileAccess.get_file_as_string("res://scenes/runner/powerups/dev/capture_a4.gd")
	check(source.contains("backdrop+0.15") and source.contains("percentile(region_values(background,rect),0.5)"),"paired same-region shipping backdrop median plus 0.15")
	check(source.contains('"stacked-tools"') and source.contains("visual.position.x = 0.0"),"capture includes stacked lane views")
	check(source.contains("body_image_guard(body,background,visual)"),"body-only guard cannot pass on a detached glyph")
	for code in [Grab.BEAM_CODE,Grab.GLYPH_CODE]:
		check(not code.contains("TIME") and not code.contains("cull_disabled"),"affordance clock and explicit front/back faces")
	check(Grab.BEAM_CODE.contains("a*near_fade"),"beam ring and halo all fade near player")
	check(Grab.BEAM_CODE.contains("clock*0.65") and Grab.BEAM_CODE.contains("ribbons"),"slow ribbon pair motif")
	var beam_arrays := Grab.mesh().surface_get_arrays(0)
	var beam_colors: PackedColorArray = beam_arrays[Mesh.ARRAY_COLOR]
	var beam_normals: PackedVector3Array = beam_arrays[Mesh.ARRAY_NORMAL]
	for i in beam_colors.size():
		if beam_colors[i].r > 0.5: check(beam_normals[i].y > 0.99,"back-face culled floor ring faces up")
	check(Grab.BEAM_CODE.contains("depth_test_disabled"),"R6 B2 beam cannot be bitten by sculpture depth")
	check(Grab.BEAM_CODE.contains("pow(max(0.0,1.0-pow(UV.x*2.0-1.0,2.0)),2.0)"),"R6 B2 smooth radial profile reaches zero at edges")
	check(Grab.GLYPH_CODE.contains("ALBEDO = tint.rgb*glyph_gain") and Grab.BEAM_CODE.contains("ALBEDO = tint.rgb*0.85"),"R6 B5 subunit hue-preserving tint gains")
	check(source.contains("beacon_image_guard(beam,background,visual)") and source.contains('set_shader_parameter("beam_only",1.0)'),"R6 isolated beam guard excludes body ring halo glyph")
	check(source.contains("glyph_color_guard(image,visual)") and source.contains("stacked_peak_guard(image,background"),"R6 color and stacked pixel guards wired")
	var mint_quality := Capture.color_quality([Palette.MINT,Palette.MINT])
	var white_quality := Capture.color_quality([Color.WHITE,Color.WHITE])
	check(mint_quality.x >= 0.25 and mint_quality.y <= 0.05,"R6 B5 saturation accepts mint")
	check(white_quality.x < 0.25 and white_quality.y > 0.05,"R6 B5 rejects white glyphs")
	check(Capture.separated_peaks([0.0,0.3,0.2,0.02,0.1,0.35,0.0],1,5),"R6 B4 accepts two separated lane peaks")
	check(not Capture.separated_peaks([0.0,0.3,0.3,0.3,0.3,0.35,0.0],1,5),"R6 B4 rejects merged lane blob")
	check(source.contains('views.append("distance-"+str(kind))') and source.contains("selection = [kind,kind,kind]"),"R7 every kind captured at all three distances")
	check(source.contains("kind=%s %dm") and source.contains('"tools" if visual._art._is_tool else "powerups"'),"R7 self-describing per-kind family measurements")
	var ramp: Array[float] = []
	for i in 100: ramp.append(float(i)/100.0)
	check(is_equal_approx(Capture.brightest_body_p75(ramp),0.84),"R8 p75 of brightest sixty percent uses documented order statistic")
	check(is_equal_approx(Capture.percentile(ramp,0.75),0.74),"R8 whole-box p75 is distinct from retained-body p75")
	check(Capture.brightest_body_p75([0.0,0.0,0.0]) == 0.0 and Capture.brightest_body_p75([]) == 0.0,"R8 empty/dark masks cannot fabricate light")
	check(source.contains("projected_body_rect(camera,visual._art._pivot)") and source.contains("brightest_body_p75(values)") and source.contains("maxf(0.16,backdrop+0.08)"),"R11 actual sculpture bbox and sampler use coordinator calibration")
	check(Finish.CODE.contains("min(0.65,energy*clamp(range_boost,1.0,3.0)"),"R9 complete emissive product capped, not just one factor")
	check(is_equal_approx(Capture.body_threshold(40.0,0.10),0.18) and is_equal_approx(Capture.body_threshold(40.01,0.10),0.13),"R11 exact forty-metre decision boundary")
	check(is_equal_approx(Capture.body_threshold(20.0,0.02),0.16),"R11 near brightness floor remains 0.16")
	check(Capture.body_accepts(60.0,0.10,0.13,3,Vector2(0.30,0.03)),"R11 three hue-true pixels pass distant presence")
	check(not Capture.body_accepts(60.0,0.10,0.13,2,Vector2(0.30,0.03)),"R11 two distant pixels cannot pass")
	check(not Capture.body_accepts(60.0,0.10,0.129,3,Vector2(0.30,0.03)),"R11 distant brightness must clear backdrop plus 0.03")
	for distance in [20.0,40.0]:
		check(not Capture.body_accepts(distance,0.164,0.204,23,Vector2(0.30,0.03)),"R11 dark nearby body at backdrop plus 0.04 fails")
	check(Capture.body_accepts(20.0,0.164,0.250,23,Vector2(0.30,0.03)),"R11 measured APPROVE 0.250 versus 0.164 passes")
	check(Capture.body_accepts(60.0,0.062,0.098,3,Vector2(0.30,0.03)),"R11 measured stacked PATCH presence passes")
	check(source.contains("brightness_min=%.3f lit_pixels_min=%d saturation_min=0.25 white_ratio_max=0.05"),"R11 guard logs all acceptance thresholds")
	check(not Capture.body_accepts(60.0,0.10,1.0,60,Vector2(0.01,1.0)),"R9 white blowout fails despite brightness")
	check(not Capture.body_accepts(20.0,0.10,0.60,60,Vector2(0.30,0.06)),"R9 white fraction above five percent fails")
	var clipped: Array[Color] = []
	for i in 80: clipped.append(Color.BLACK)
	for i in 20: clipped.append(Color.WHITE)
	check(Capture.body_color_quality(clipped) == Vector2(0,1),"R9 brightest twenty-percent hue detects white hidden by a dark bbox")
	var first := Grab.material(Palette.MINT,&"approve_shield")
	var second := Grab.material(Palette.MINT,&"approve_shield")
	first.set_shader_parameter("depth_alpha",0.1)
	check(first != second and first.shader == second.shader,"private affordance uniforms share shader")
	check(second.get_shader_parameter("depth_alpha") != 0.1,"cached material isolation")
	var texture: Texture2D = first.get_shader_parameter("glyph")
	check(texture == second.get_shader_parameter("glyph") and texture.get_image().has_mipmaps(),"glyph texture shared with mipmaps")

func round5_affordance_checks(art: Art, camera: Camera3D, kind: StringName) -> void:
	check(art._pool.custom_aabb.size.is_equal_approx(Vector3(3.8,3.2,2.4)),"B2 shader-expanded beam culling bound")
	var visual := art.get_parent() as Node3D
	var original := visual.position
	for distance in [20.0,40.0,60.0,90.0]:
		for lane in [-2.0,0.0,2.0]:
			for altitude in [1.0,2.2]:
				visual.position = Vector3(lane,altitude,-distance)
				art._update_affordance()
				check(art._glyph.position.y <= 1.2,"B1 attached world-height glyph " + kind)
				var gem: MeshInstance3D = art._pivot.get_node("Ring")
				check(float(gem.material_override.get_shader_parameter("range_boost")) <= 3.0,"R9 bounded body gain " + kind)
				check(Finish.CODE.contains("step(emission_inset,UV.x)") and not Finish.CODE.contains("edge_distance"),"B1 broad patch replaces subpixel edge")
				for x in [-0.5,0.5]:
					for y in [-0.5,0.5]:
						var corner := art._glyph.to_global(Vector3(x,y,0))
						check(absf(corner.x) <= 4.0001 and corner.y <= 6.4001 and corner.y >= 0.0499,"B5 whole quad inside shipping corridor at %dm" % distance)
				var beam_center := Vector3(lane,1.0,-distance)
				var beam_edge := camera.global_basis.x*art._beam_width*0.31
				var pixels := camera.unproject_position(beam_center+beam_edge).distance_to(camera.unproject_position(beam_center-beam_edge))
				check(art._beam_width <= 0.9 and pixels > 0.0,"R6 B2 lane-safe capped soft sheath")
	visual.position = Vector3(0,1,-60)
	art._update_affordance()
	var full_size := art._glyph.scale.x
	var peer := Art.new()
	root.add_child(peer)
	peer.build(kind)
	var own_ring: MeshInstance3D = art._pivot.get_node("Ring")
	var peer_ring: MeshInstance3D = peer._pivot.get_node("Ring")
	check(peer_ring.mesh == own_ring.mesh and own_ring.mesh == Art.kind_shapes(kind).frame,"per-kind frame mesh built once and shared " + kind)
	check(peer_ring.material_override != own_ring.material_override and peer._glyph.mesh == art._glyph.mesh,"animated materials stay per pickup, quads shared " + kind)
	check(is_equal_approx(peer._glyph_coverage,art._glyph_coverage) and art._glyph_coverage > 0.5 and art._glyph_coverage <= 1.0,"cached CPU glyph coverage " + kind)
	peer.position = Vector3(0,1,-40)
	peer._update_affordance()
	art._update_affordance()
	var before := art._depth_alpha
	art._process(0.10)
	check(art._glyph.visible and art._depth_alpha < before and art._depth_alpha > 0.45,"R6 B3 gradual fade, never binary hide")
	art._process(0.41)
	peer._process(0.51)
	check(art._glyph.scale.x <= full_size*0.33 and art._depth_alpha >= 0.44,"R6 B3 rear glyph shrinks with readable residual alpha")
	check(art._glyph.visible and peer._glyph.visible,"R6 B3 both glyphs retained")
	check(art._beam_offset > 0.6 and peer._beam_offset < -0.4,"R6 B4 separated same-lane beam centers")
	peer.position.x = 3.5
	peer._update_affordance()
	art._rear_mix = 0.0
	art._process(0.51)
	check(art._rear_mix < 0.01 and art._glyph.visible,"Compact badges in separate lanes no longer overlap")
	peer._collect_time = 0.0
	art._process(0.51)
	check(art._glyph.visible and is_equal_approx(art._glyph.scale.x,full_size),"R6 B3 smooth promotion after collection")
	peer.free()
	check(get_nodes_in_group(Art.PICKUP_GROUP).size() == 1,"B4 freed pickup leaves sorting group")
	visual.position = original
	art._update_affordance()
