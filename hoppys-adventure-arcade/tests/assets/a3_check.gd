extends SceneTree
const Base = preload("res://scenes/runner/hazards/hazard_visual_base.gd")
const MeshForge = preload("res://scenes/runner/hazards/visuals/hifi/mesh_forge.gd")
const Forge = preload("res://scenes/runner/hazards/visuals/hifi/texture_forge.gd")
const CASES := [
	["pr_backlog_low","",Vector3(5.6,1,1.2),0.5],
	["pr_backlog_high","",Vector3(5.6,1.8,1.2),2.0],
	["bug_swarm","",Vector3(1.6,0.9,1.2),0.45],
	["merge_conflict","",Vector3(3.6,1,1.2),0.5],
	["deprecated_pit","full",Vector3(5.6,0.4,3),0.0],
	["deprecated_pit","two_lane",Vector3(3.6,0.4,3),0.0],
	["laser_grid","ground",Vector3(5.6,0.4,1.2),0.3],
	["laser_grid","mid",Vector3(5.6,0.3,1.2),1.15],
	["laser_grid","high",Vector3(5.6,0.4,1.2),1.3],
	["laser_grid","timed",Vector3(5.6,0.4,1.2),0.3],
	["comment_flood","",Vector3(3.6,4,1.2),2.0],
	["build_shockwave","",Vector3(5.6,0.5,1.2),0.25],
	["projectile","orb",Vector3(1.6,0.9,1.2),0.45],
	["projectile","low",Vector3(5.6,0.9,1.2),0.45],
	["projectile","high",Vector3(5.6,0.4,1.2),1.3],
	["projectile","wide",Vector3(3.6,1,1.2),0.5],
]
class RuntimeErrors extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING: count += 1

var runtime_errors := RuntimeErrors.new()
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A3: " + message)

static func spawn(entry: Array, parent: Node) -> Base:
	var scene := load("res://scenes/runner/hazards/visuals/%s_visual.tscn" % entry[0]) as PackedScene
	var visual := scene.instantiate() as Base
	parent.add_child(visual)
	visual.kind = StringName(entry[0])
	visual.variant = StringName(entry[1])
	visual.hitbox_size = entry[2]
	visual.hitbox_offset = Vector3(0,entry[3],0)
	visual.closing_speed = 34.0 if entry[0] == "projectile" else 0.0
	visual.on_spawned()
	return visual

static func census(visual: Node3D) -> Vector2i:
	var result := Vector2i.ZERO
	for node in visual.find_children("*","VisualInstance3D",true,false):
		if not node.is_visible_in_tree(): continue
		if node is MultiMeshInstance3D:
			result.x += node.multimesh.mesh.get_surface_count()
			result.y += node.multimesh.mesh.get_faces().size()/3 * node.multimesh.instance_count
		elif node is MeshInstance3D:
			result.x += node.mesh.get_surface_count()
			result.y += node.mesh.get_faces().size()/3
		elif node is GPUParticles3D:
			result.x += 1
			result.y += node.amount*2
		elif node is Label3D:
			result.x += 2 if node.outline_size > 0 else 1
			result.y += node.text.length()*2
	return result

func _bounds(visual: Base, title: String) -> void:
	var art: Node3D = visual.get_node("Artwork")
	var center := visual.hitbox_offset
	if visual.variant == &"timed": center.y = art.body.position.y
	var envelope := AABB(center-visual.hitbox_size*0.55-Vector3.ONE*0.001,visual.hitbox_size*1.1+Vector3.ONE*0.002)
	for batch: Dictionary in art._batches:
		for instance: Array in batch.instances:
			var pivot: Node3D = instance[0]
			if not pivot.is_visible_in_tree(): continue
			var pose := visual.global_transform.affine_inverse()*pivot.global_transform
			pose.basis = pose.basis.scaled_local(instance[1])
			var box: AABB = pose*batch.mesh.get_aabb()
			check(envelope.encloses(box),title+" mesh envelope "+str(box))
	for label: Label3D in art.find_children("*","Label3D",true,false):
		var box: AABB = visual.global_transform.affine_inverse()*label.global_transform*label.get_aabb()
		check(envelope.encloses(box),title+" label envelope")

func _run() -> void:
	# The global audio autoload starts MP3 playback even in a headless asset test.
	var audio := root.get_node_or_null("AudioService")
	if audio != null:
		audio.music.stop()
		audio.music.stream = null
	OS.add_logger(runtime_errors)
	var maps := Forge.maps()
	check(maps.size() == 3,"shared three-map atlas")
	check(maps.albedo == Forge.maps().albedo,"atlas cache identity")
	for texture: Texture2D in maps.values():
		check(texture.get_size() == Vector2(512,512),"512-square atlas")
		check(texture.get_image().has_mipmaps(),"R2 mipmaps present")
	check(Forge.marker_border().get_image().get_pixel(128,128).a == 0.0,"R3 SafeGap clear center")
	check(Forge.marker_border().get_image().has_mipmaps(),"R3 marker border mipmaps")
	_check_occlusion_guard()
	var capture_source := FileAccess.get_file_as_string("res://scenes/runner/hazards/dev/capture_a3.gd")
	var capture_loop := capture_source.get_slice("for entry: Array in Check.CASES:",1).get_slice("func _record_failure",0)
	check(not capture_loop.contains("quit(1)") and not capture_loop.contains("return"),"R5 view loop accumulates failures without early exits")
	var occlusion_loop := capture_source.get_slice("for pose in",1).get_slice("func _finalize",0)
	check(not occlusion_loop.contains("return") and not occlusion_loop.contains("quit("),"R5 both occlusion views saved after guard failure")
	check(capture_source.contains("root.scaling_3d_scale = 0.5"),"R5 fixture matches gameplay render scale")
	check(capture_source.contains("camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF"),"R9 exact camera pose for saved-image probes")
	check(not capture_source.contains("fixture frame exposure") and not capture_source.contains("Metrics.frame_median"),"R9 no frame-wide exposure guard")
	check(capture_source.contains("_check_exposure(saved_image,visual,slug+\"/occlusion-\""),"R9 occlusion views also check floor exposure")

	check(capture_source.contains("environment.environment = CorridorMaterials.environment()"),"R6 shared corridor environment")
	for setting in ["key.rotation_degrees = Vector3(-50,-25,0)","key.light_color = Palette.MATRIX","key.light_energy = 0.35","fill.position = Vector3(0,3,1)","fill.light_energy = 1.6","fill.omni_range = 9.0"]:
		check(capture_source.contains(setting),"R8 shipped corridor fixture light: "+setting)


	var atlas: Image = maps.albedo.get_image()
	for tile in 4:
		var lit := 0
		for y in 512:
			for x in 128:
				if atlas.get_pixel(tile*128+x,y).a > 0.5: lit += 1
		check(float(lit)/(128*512) <= 0.40,"R2 B4 atlas mask <=40 percent")
	for entry: Array in CASES:
		var title := "%s/%s" % [entry[0],entry[1]]
		var visual := spawn(entry,root)
		visual.set_process(false)
		await process_frame
		_round_two(visual,title)
		_round_three(visual)
		var peak := Vector2i.ZERO
		for action in ["idle","on_hit_player","on_cleared"]:
			visual.on_spawned()
			await process_frame
			var art: Node3D = visual.get_node("Artwork")
			if action != "idle": visual.call(action)
			for frame in 90:
				visual._process(1.0/30.0)
				if visual.visible: _bounds(visual,title+" "+action)
				var count := census(visual)
				peak.x = maxi(peak.x,count.x)
				peak.y = maxi(peak.y,count.y)
			for batch: Dictionary in art._batches:
				check(batch.node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,title+" cosmetic interpolation")
				check(batch.node.process_mode == Node.PROCESS_MODE_PAUSABLE,title+" pausable batch")
				check(not batch.material.shader.code.contains("TIME"),title+" clock-only shader")
		visual.on_spawned()
		await process_frame
		for state in [&"ground",&"off",&"high",&"off",&"ground"]:
			visual.set_laser_state(state)
			for amount in [0.0,0.25,0.5,0.75,1.0]:
				visual.set_telegraph(amount)
				_bounds(visual,title+" "+state)
			if entry[1] == "timed":
				check(visual._art.beams.visible == (state != &"off"),"timed beam visibility")
		var count := visual.get_child_count()
		visual.on_spawned()
		visual.on_spawned()
		await process_frame
		for node: Node in visual.find_children("*", "", true, false):
			check(node.process_mode == Node.PROCESS_MODE_PAUSABLE,title+" pausable child")
			if node is GPUParticles3D:
				check(node.amount <= 64,title+" emitter budget")
				var pm := node.process_material as ParticleProcessMaterial
				var reach: Vector3 = pm.emission_box_extents+Vector3.ONE*(pm.initial_velocity_max*node.lifetime+0.013)
				check(node.visibility_aabb.encloses(AABB(-reach,reach*2)),"R2 bounded full particle trajectory")
		check(visual.get_child_count() == count,title+" pooled reset")
		check(visual._art._t == 0.0,title+" reset clock")
		visual.set_process(true)
		paused = true
		await process_frame
		await process_frame
		check(visual._art._t == 0.0,title+" pause freezes clock")
		paused = false
		check(peak.x <= 14,title+" draw budget <=14")
		check(peak.y <= 6000,title+" triangle budget <=6000")
		print("A3 CENSUS: %s draws=%d triangles=%d" % [title,peak.x,peak.y])
		visual.free()
	check(runtime_errors.count == 0,"no runtime errors during asset checks")
	print("ASSET A3: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _round_two(visual: Base, title: String) -> void:
	var art: Node3D = visual.get_node("Artwork")
	for label: Label3D in art._labels:
		check(label.get_parent() == art,"R2 B1 rig-root label")
		check(label.global_basis.get_scale().is_equal_approx(Vector3.ONE),"R2 B1 undistorted glyphs")
		check(label.pixel_size >= 0.001,title+" useful glyph scale")
	check(art._plates.size() == art._labels.size(),"R2 B1 one backing per label")
	for batch: Dictionary in art._batches:
		check(not batch.material.shader.code.contains("cull_disabled"),"R2 culled surfaces / explicit two-sided wings")
		if batch.material.shader == art.Surface:
			check(batch.material.shader.code.contains("float mask = plate.a;"),"R2 B4 no full-surface emissive fallback")
			check(float(batch.material.get_shader_parameter("emission_gain")) <= 0.65,"R2 B4 capped emission gain")
		for surface in batch.mesh.get_surface_count():
			var arrays: Array = batch.mesh.surface_get_arrays(surface)
			for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
				check(uv.x >= -0.001 and uv.x <= 1.001 and uv.y >= -0.001 and uv.y <= 1.001,"R2 per-face UV range")
	if visual.kind == &"deprecated_pit":
		check(is_equal_approx(art.tag.rotation.x,-PI/2),"R3 B1 pit front faces upward")
		var bottom: Node3D = art.body.get_node("PitBottom")
		check(bottom.global_position.y < -0.15,"R2 B3 recessed bottom")
		check(art.tag.position.y < 0.05,"R2 B3 floor-level tag")
	if visual.kind == &"bug_swarm":
		var bodies := 0
		var wings := 0
		for batch: Dictionary in art._batches:
			if batch.mesh == MeshForge.carapace(): bodies += batch.instances.size()
			if batch.mesh == MeshForge.wing(): wings += batch.instances.size()
		check(bodies == 3 and wings == 6,"R2 B6 curved beetles and visible two-sided membranes")
		check(MeshForge.wing().custom_aabb.size.z >= 0.15,"R2 B6 shader displacement culling envelope")
		check(MeshForge.wing().get_faces().size() == 96,"R3 B5 teardrop front and back triangles")
		check(art.Wing.code.contains("clock*30.0"),"R2 B6 clock-driven flutter")
	if visual.kind == &"build_shockwave":
		check(art.has_node("WaveCrest") and not art.has_node("RollingRing0"),"R3 B6 one continuous crest, no small hoops")
		var arcs := 0
		var shards := 0
		for batch: Dictionary in art._batches:
			if batch.mesh == MeshForge.wave_arc():
				arcs += batch.instances.size()
				for item: Array in batch.instances:
					var box: AABB = item[0].global_transform.scaled_local(item[1])*batch.mesh.get_aabb()
					check(box.size.x > 5.0 and box.size.y < 0.55,"R3 B6 broad low arc")
			if batch.mesh == MeshForge.shard(): shards += batch.instances.size()
		check(arcs == 3 and shards == 20,"R3 B6 crest, leading edge and faceted debris")
	if visual.kind == &"projectile":
		var names := {&"orb":"OrbCore",&"low":"LowWedge",&"high":"HighBar",&"wide":"WideCrescent"}
		check(art.body.has_node(names[visual.variant]),"R2 B5 distinct silhouette")
		for side in [-1,1]:
			var trail: Node3D = art.body.get_node("AftTrail%d" % side)
			check(trail.position.z <= -0.15 and absf(trail.position.x) >= 0.34,"R2 B5 visible aft trails outside core")
	if visual.variant == &"timed":
		visual.set_telegraph(0.75)
		for batch: Dictionary in art._batches:
			for item: Array in batch.instances:
				if item[0].get_parent() == art.scanner: check(item[0].position.z >= 0.38,"R2 B8 charge bar ahead of beam plane")
		check(art.scanner.visible and art._charge == 0.75,"R2 B8 charge state")
		check(float(art._materials.housing.get_shader_parameter("charge")) == 0.75,"R2 B8 housing charge")
		check(art.tag.text == "CHARGING","R2 B8 explicit charge message")
		visual.set_telegraph(0.0)
		check(not art.scanner.visible and art._charge == 0.0,"R2 B8 charge reset")
	# Per-rig material instances must not leak telegraph/clock changes into another spawn.
	var clone := spawn([visual.kind,visual.variant,visual.hitbox_size,visual.hitbox_offset.y],root)
	clone.set_process(false)
	for key: String in art._materials:
		if clone._art._materials.has(key): check(art._materials[key] != clone._art._materials[key],"R2 instance-local materials")
	clone.free()

func _round_three(visual: Base) -> void:
	var art: Node3D = visual.get_node("Artwork")
	if visual.kind in [&"pr_backlog_low", &"pr_backlog_high"]:
		check(art.Surface.code.contains("fwidth(symbol)") and art.Surface.code.contains("diff_mark"),"R7 analytic diff glyphs")
	if visual.kind == &"merge_conflict":
		check(art._materials.lilac_plate.get_shader_parameter("tile") == art._materials.metal.get_shader_parameter("tile"),"R8 both slabs share plating tile")
		check(art._materials.lilac_plate.get_shader_parameter("normal_atlas") == art._materials.metal.get_shader_parameter("normal_atlas"),"R8 both slabs share normal treatment")
	if visual.kind == &"deprecated_pit":
		check(art.tag.global_basis.z.normalized().dot(Vector3.UP) > 0.999,"R3 B1 label face +Y")
		check(art.tag.global_basis.y.normalized().dot(Vector3.FORWARD) > 0.999,"R3 B1 glyph up maps to -Z")
		check(art._plates.back().global_basis.y.normalized().dot(Vector3.UP) > 0.999,"R3 B1 XZ backing normal +Y")
		check(not art.get_node("FloorMarker").visible,"R3 B2 no additive lid over hole")
		check(is_equal_approx(art._pit_mouth.material_override.get_shader_parameter("well_depth"),1.6),"R4 explicit deep virtual well")
		check(art.PitMouth.code.contains("ALBEDO = vec3(0.0)") and art.PitMouth.code.contains("specular_disabled"),"R5 black albedo and no key/fill specular")
		check(art.PitMouth.code.contains("EMISSION = bottom_color.rgb*0.001 + interior_light"),"R5 walls carried by emission")
		check(art.PitMouth.code.contains("inverse(MODEL_MATRIX) * INV_VIEW_MATRIX * vec4(VIEW,0.0)"),"R5 camera direction converted to object space")
		check(art.PitMouth.code.contains("abs(ray.x) < 0.00001 ? 100000.0"),"R5 parallel rays cannot produce NaN")
		check(art._pit_mouth.material_override.get_shader_parameter("wall_shadow").is_equal_approx(art.Palette.NAVY_2),"R5 NAVY_2 wall shadow")
		for camera_position: Vector3 in [Vector3(0,4,12),Vector3(4,3,6)]:
			var wall_hits := 0
			var half_size: Vector2 = art._pit_mouth.mesh.size*0.5
			for row in 12:
				for col in 12:
					var point := Vector3(lerpf(-0.65,0.65,float(col)/11)*half_size.x,0,lerpf(-0.88,0.88,float(row)/11)*half_size.y)
					var ray := (point-camera_position).normalized()
					var wall_z := (signf(ray.z)*half_size.y-point.z)/ray.z
					var wall_x := INF if absf(ray.x) < 0.0001 else (signf(ray.x)*half_size.x-point.x)/ray.x
					if minf(wall_x,wall_z) < 1.6/-ray.y: wall_hits += 1
			check(wall_hits >= 72,"R4 walls occupy most mouth samples at gameplay/oblique")

		check(art.PitMouth.code.contains("bottom_color.rgb*0.001"),"R4 dark bottom")
		check(art.PitMouth.code.contains("smoothstep(0.60,1.0,height)") and art.PitMouth.code.contains("0.07+0.03*far_wall"),"R7 upper 40 percent wall band and lower peak")
		check(art.PitMouth.code.contains("1.0-cable*0.60") and art.PitMouth.code.contains("seam*0.12*(1.0+0.15*sin"),"R6 visible cables and clock seam")
		check(art._pit_mouth.material_override.get_shader_parameter("cable_color").is_equal_approx(art.Palette.MATRIX),"R6 MATRIX cable core")

		check(art._materials.carapace.get_shader_parameter("tint").is_equal_approx(art.Palette.NAVY_2),"R4 dark lip")

		for batch: Dictionary in art._batches:
			for item: Array in batch.instances:
				var bounds: AABB = item[0].global_transform.scaled_local(item[1])*batch.mesh.get_aabb()
				check(bounds.end.y <= 0.0201,"R3 B2 rim and hardware at floor level")
		check(is_equal_approx(art._pit_mouth.position.y,0.001),"R3 B3 depth-tested mouth above opaque floor")
		for shader: Shader in [art.PitInterior,art.PitMouth]:
			check(not shader.code.contains("depth_test_disabled") and not shader.code.contains("depth_draw_never"),"R3 B3 normal depth test/write")
			check(shader.code.contains("depth_draw_opaque") and not shader.code.contains("ALPHA ="),"R3 B3 opaque depth-writing pass")
		var mouth_bounds: AABB = art._pit_mouth.transform*art._pit_mouth.get_aabb()
		check(AABB(visual.hitbox_offset-visual.hitbox_size*0.55,visual.hitbox_size*1.1).encloses(mouth_bounds),"R3 B3 mouth envelope")
		check(art.PitMouth.code.contains("bottom_t") and art.PitMouth.code.contains("far_wall"),"R3 B2 perspective bottom and far-wall gradient")
	if visual.kind == &"projectile":
		check(float(art._materials.threat.get_shader_parameter("emission_gain")) >= 0.6,"R3 B4 DANGER core emission")
		check(art._materials.threat.get_shader_parameter("accent").is_equal_approx(art.Palette.DANGER),"R3 B4 palette DANGER")
		var streaks := 0
		for batch: Dictionary in art._batches:
			if batch.mesh == MeshForge.trail(): streaks += batch.instances.size()
		check(streaks == 2 and art.Trail.code.contains("blend_add"),"R3 B4 two tapering additive ribbons")
		for batch: Dictionary in art._batches:
			if batch.mesh == MeshForge.trail():
				for item: Array in batch.instances: check(item[1].z >= 0.75,"R4 longer aft ribbons")
		check(art.Trail.code.contains("smoothstep(0.0,0.8,UV.y)"),"R4 continuous tail fade")

		var vertices := MeshForge.trail().get_faces()
		for vertex: Vector3 in vertices:
			if vertex.z < -0.499: check(absf(vertex.x)+absf(vertex.y) < 0.001,"R3 B4 zero-width aft tip")
	if visual.kind == &"bug_swarm":
		check(art._materials.glass.get_shader_parameter("membrane_color").is_equal_approx(art.Palette.MATRIX),"R3 B5 MATRIX membranes")
		check(not art.Wing.code.contains("0.68,0.76,0.79"),"R3 B5 no pale-grey wing color")
		for vertex: Vector3 in MeshForge.wing().get_faces():
			if absf(vertex.y) > 0.49: check(absf(vertex.x) < 0.01,"R3 B5 tapered wing ends")
		check(art._materials.carapace.get_shader_parameter("tint").is_equal_approx(art.Palette.NAVY_2),"R3 B5 dark carapace")
		var jointed := 0
		for batch: Dictionary in art._batches:
			if batch.mesh == MeshForge.jointed_leg(): jointed += batch.instances.size()
		check(jointed == 18,"R4 six jointed tapered legs per beetle")

	var old_z := visual.position.z
	visual.position.z = -60
	art.update_view_distance()
	check(is_equal_approx(art._distance_gain,4.5),"R3 bounded distance visibility gain")
	visual.position.z = old_z
	art.update_view_distance()

func _check_occlusion_guard() -> void:
	# Unit-check the host pixel oracle without claiming a rendered occlusion test.
	var capture := load("res://scenes/runner/hazards/visuals/hifi/capture_metrics.gd") as GDScript
	var background := Image.create(20,20,false,Image.FORMAT_RGBA8)
	background.fill(Color("08111c"))
	var reference := background.duplicate() as Image
	for y in range(3,17):
		for x in range(3,17): reference.set_pixel(x,y,Color("79e0c4"))
	var preserved: Vector2i = capture.compare_capsule(reference,background,reference)
	check(preserved.x > 0 and preserved.y == 0,"R3 B3 pixel oracle accepts preserved capsule")
	var overwritten := reference.duplicate() as Image
	overwritten.set_pixel(10,10,Color("08111c"))
	var rejected: Vector2i = capture.compare_capsule(reference,background,overwritten)
	check(rejected.y == 1,"R3 B3 pixel oracle rejects overwritten capsule")

	# Outline-only differences must not look like depth overwrites.
	var antialiased := reference.duplicate() as Image
	for y in range(3,17):
		antialiased.set_pixel(3,y,reference.get_pixel(3,y)-Color(0.05,0.05,0.05,0.0))
		antialiased.set_pixel(16,y,reference.get_pixel(16,y)-Color(0.05,0.05,0.05,0.0))
	check(capture.compare_capsule(reference,background,antialiased).y == 0,"R8 AA outline differences pass")
	var image := Image.create(40,30,false,Image.FORMAT_RGBA8)
	var mouth: Array[Vector2i] = []
	var floor_pixels: Array[Vector2i] = []
	for y in 30:
		floor_pixels.append(Vector2i(30,y))
		for x in 20: mouth.append(Vector2i(x,y))
	# floor median, floor p90, top/middle/bottom, expected result
	for sample: Array in [[5.0,28.0,20.0,1.4,2.1,true],[107.0,107.0,20.0,1.4,2.1,false],[25.0,35.0,20.0,1.4,2.1,true],[2.0,28.0,20.0,1.4,2.1,false],[5.0,28.0,40.0,1.4,2.1,false],[5.0,75.0,20.0,1.4,2.1,false],[5.0,8.0,20.0,1.4,2.1,false],[0.0,0.0,20.0,1.4,2.1,false],[5.0,28.0,0.0,0.0,0.0,false],[5.0,28.0,20.0,1.0,7.0,false]]:
		image.fill(Color.BLACK)
		for y in 30:
			var shade: float = sample[0 if y < 24 else 1]/255.0
			image.set_pixel(30,y,Color(shade,shade,shade))
		for pixel in mouth:
			var shade: float = sample[2+mini(2,pixel.y/10)]/255.0
			image.set_pixelv(pixel,Color(shade,shade,shade))
		var result: Dictionary = capture.pit_contrast(image,mouth,floor_pixels)
		check(result.pass == sample[5],"R8 calibrated well/fixture synthetic pin")
		if sample[0] == 107.0: check(not result.exposure_pass,"R8 overexposed fixture fails separately")
	var fixture: StandardMaterial3D = capture.fixture_plate()
	check(fixture.metallic <= 0.3 and is_equal_approx(fixture.roughness,0.6),"R8 diffuse fixture plate")
	check(fixture.albedo_color.is_equal_approx(preload("res://scenes/runner/environment/runner_palette.gd").NAVY_2),"R8 original navy fixture")

	# Bright artwork outside the reference probes must not affect exposure.
	image.fill(Color.WHITE)
	var exposure_pixels: Array[Vector2i] = []
	for y in 30:
		for x in range(30,34):
			var shade := (5.0 if y < 24 else 28.0)/255.0
			image.set_pixel(x,y,Color(shade,shade,shade))
			exposure_pixels.append(Vector2i(x,y))
	check(capture.floor_exposure(image,exposure_pixels).pass,"R9 bright hazard with dark floor reference passes")
	for pixel in exposure_pixels: image.set_pixelv(pixel,Color(107.0/255.0,107.0/255.0,107.0/255.0))
	check(not capture.floor_exposure(image,exposure_pixels).pass,"R9 floor median 107 fails regardless of hazard")

	# The same measured foreshortened shaft is valid only for the oblique view.
	var oblique_image := Image.create(40,30,false,Image.FORMAT_RGBAF)
	for y in 30:
		var floor_shade := 0.096 if y < 24 else 0.102
		oblique_image.set_pixel(30,y,Color(floor_shade,floor_shade,floor_shade))
	for pixel in mouth:
		var shade: float = [0.031,0.007,0.002][mini(2,pixel.y/10)]
		oblique_image.set_pixelv(pixel,Color(shade,shade,shade))
	check(capture.pit_contrast(oblique_image,mouth,floor_pixels,"oblique").pass,"R10 measured oblique shaft passes at 6/255")
	check(not capture.pit_contrast(oblique_image,mouth,floor_pixels,"gameplay").pass,"R10 gameplay keeps 12/255")
	check(not capture.pit_contrast(oblique_image,mouth,floor_pixels,"close").pass,"R10 close keeps 12/255")
