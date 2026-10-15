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
const Art = preload("res://scenes/runner/hazards/visuals/hazard_art.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
## Baked hazard atlases exactly as the runtime binds them.
var albedo_image: Image
var emission_image: Image
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
	# Review r1: captures render inside the shipping corridor, which applies the gameplay retro scale itself.
	check(capture_source.contains("CORRIDOR.instantiate()") and not capture_source.contains("scaling_3d_scale"),"R5 capture renders at the shipping corridor's own gameplay render scale")
	check(capture_source.contains("camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF"),"R9 exact camera pose for saved-image probes")
	check(not capture_source.contains("fixture frame exposure") and not capture_source.contains("Metrics.frame_median"),"R9 no frame-wide exposure guard")
	check(capture_source.contains("_check_exposure(saved_image,visual,slug+\"/occlusion-\""),"R9 occlusion views also check floor exposure")

	check(capture_source.contains('const CORRIDOR = preload("res://scenes/runner/environment/corridor.tscn")') and not capture_source.contains("WorldEnvironment.new()"),"R6 shipping corridor environment, never a fixture copy")
	check(not capture_source.contains("DirectionalLight3D") and not capture_source.contains("OmniLight3D") and not capture_source.contains("_panel("),"R8 shipping corridor lights and walls only; no fixture panels or lights")
	check(capture_source.contains("GAMEPLAY_POSITION := Vector3(0,4,8)") and capture_source.contains("GAMEPLAY_LOOK_AT := Vector3(0,1,-8)") and capture_source.contains("camera.near = 0.15") and capture_source.contains("camera.far = 200.0"),"r1 gameplay chase camera (runner_game.tscn / run_config.gd)")
	check(capture_source.contains('"gameplay": 20.0, "distance40": 40.0, "distance60": 60.0') and capture_source.contains("Metrics.corridor_exposure(image,probes)"),"r1 gameplay-camera distance views and corridor exposure guard")
	check(capture_source.contains('"approach": 6.0') and capture_source.contains('and view != "gameplay"'),"r1 pit mouth contrast enforced at the 6 m approach and oblique views, reported at 20 m")
	check(capture_source.contains("await _measure_danger(visual,background,slug)") and capture_source.contains("DANGER_SHARE_MIN := 0.08") and capture_source.contains('DANGER_GUARDED := ["pr_backlog_low","pr_backlog_high","merge_conflict","comment_flood"]'),"r1 DANGER share guard at 40 m on the flagged kinds")
	check(capture_source.contains("await _measure_ink(visual,slug,view)") and capture_source.contains("INK_CONTRAST_MIN := 0.15") and capture_source.contains("_measure_beetles(visual,slug)") and capture_source.contains("await _motion_strip(visual,entry)"),"r1 ink contrast, beetle size and motion strips wired")
	# Review r1 pixel oracles (synthetic): corridor exposure band, DANGER classifier, box share, ink contrast.
	var metrics := load("res://scenes/runner/hazards/visuals/hifi/capture_metrics.gd") as GDScript
	var floor_image := Image.create(4,4,false,Image.FORMAT_RGBAF)
	var floor_probes: Array[Vector2i] = []
	for y in 4:
		for x in 4: floor_probes.append(Vector2i(x,y))
	for sample: Array in [[41.0,63.0,true],[46.0,190.0,true],[3.0,20.0,false],[120.0,150.0,false],[41.0,250.0,false],[10.0,8.0,false]]:
		for pixel in floor_probes:
			var shade: float = (sample[0] if pixel.y < 3 else sample[1])/255.0
			floor_image.set_pixelv(pixel,Color(shade,shade,shade))
		check(metrics.corridor_exposure(floor_image,floor_probes).pass == sample[2],"r1 corridor exposure band pin %s" % str(sample))
	check(metrics.is_danger(Palette.DANGER) and metrics.is_danger(Palette.DANGER.darkened(0.6)) and not metrics.is_danger(Palette.DANGER.darkened(0.85)),"r1 DANGER classifier accepts lit and shaded DANGER, rejects near-black")
	check(not metrics.is_danger(Palette.ORANGE) and not metrics.is_danger(Color.from_hsv(Palette.ORANGE.h,0.86,0.9)) and not metrics.is_danger(Palette.LILAC) and not metrics.is_danger(Palette.CREAM) and not metrics.is_danger(Palette.MINT),"r1 DANGER classifier rejects ORANGE, LILAC, CREAM and MINT")
	var box_bg := Image.create(10,10,false,Image.FORMAT_RGBA8)
	box_bg.fill(Palette.NAVY_BG)
	var box_image := box_bg.duplicate() as Image
	for x in 10:
		box_image.set_pixel(x,0,Palette.DANGER)
		box_image.set_pixel(x,1,Palette.SLATE)
	box_image.set_pixel(0,5,Palette.DANGER.darkened(0.3))
	var share: Vector2 = metrics.danger_share(box_image,box_bg,Rect2i(0,0,10,10))
	check(is_equal_approx(share.x,0.11) and is_equal_approx(share.y,11.0/21.0),"r1 DANGER share of box and of hazard pixels")
	check(metrics.danger_share(box_bg,box_bg,Rect2i(0,0,10,10)).x == 0.0,"r1 unchanged background never counts as DANGER")
	var ink_mask := Image.create(8,8,false,Image.FORMAT_RGBA8)
	var ink_lit := Image.create(8,8,false,Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var is_ink := y >= 2 and y <= 4
			ink_mask.set_pixel(x,y,Color(0.6,0,0) if is_ink else Color(0,0.6,0))
			ink_lit.set_pixel(x,y,Color(0.5,0.5,0.5) if is_ink else Color(0.1,0.1,0.1))
	var no_labels: Array[Rect2] = []
	var ink: Dictionary = metrics.ink_contrast(ink_lit,ink_mask,Rect2i(0,0,8,8),no_labels,false)
	check(is_equal_approx(ink.contrast,0.4) and ink.ink == 24 and ink.slab == 40,"r1 ink contrast is lit ink minus lit slab luminance")
	var eroded: Dictionary = metrics.ink_contrast(ink_lit,ink_mask,Rect2i(0,0,8,8),no_labels,true)
	check(eroded.ink == 6 and eroded.slab < 40,"r1 eroded ink keeps only interior line pixels")
	var labelled: Array[Rect2] = [Rect2(0,0,8,8)]
	check(metrics.ink_contrast(ink_lit,ink_mask,Rect2i(0,0,8,8),labelled,false).ink == 0,"r1 label rectangles are excluded from ink sampling")


	# One shared four-map atlas set for every Blender hazard prop.
	for channel: String in Art.PROP_MAPS:
		var map: Texture2D = Art.PROP_MAPS[channel]
		check(map.get_size() == Vector2(1024,1024) and map.get_image().has_mipmaps(),"1024 square mipmapped prop atlas " + channel)
	albedo_image = (Art.PROP_MAPS.albedo as Texture2D).get_image()
	emission_image = (Art.PROP_MAPS.emission as Texture2D).get_image()
	check(not Art.Prop.code.contains("TIME") and not Art.Prop.code.contains("cull_disabled"),"clock-driven back-face culled prop shader")
	check(Art.Prop.code.contains("accent.rgb*mask*hit") and not Art.Prop.code.contains("accent.rgb*hit"),"R2 B4 hit flash only brightens the baked emissive mask")
	check(Art.Prop.code.contains("depth_draw_opaque") and not Art.Prop.code.contains("ALPHA"),"opaque depth-writing prop surfaces")
	check(Art.PROP_EMISSION_GAIN <= 1.2,"R2 B4 capped prop emission gain")
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/runner/props/props.build.json"))
	check(not build.get("quick",true) and build.get("seed") != null,"baked (non-quick) deterministic Blender build")
	# Review r1: the grey-scenery hazards carry a real DANGER glow (baked emissive area 3%..40%).
	for root_name in ["HZ_pr_backlog_low","HZ_pr_backlog_high","HZ_merge_conflict","HZ_comment_flood"]:
		var emissive: float = build.hazards.emission_share.get(root_name,0.0)
		print("A3 EMISSIVE SHARE: %s %.3f (baked area; target 0.03..0.40)" % [root_name,emissive])
		check(emissive >= 0.03 and emissive <= 0.40,"r1 %s baked emissive share %.3f within 3..40 percent" % [root_name,emissive])
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
			if action == "on_cleared" and art.has_node("FloorMarker"):
				check(art.get_node("FloorMarker").material_override.emission == art.Palette.MINT,"cleared footprint emission changes to friendly mint")
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
	preload("res://scenes/runner/hazards/visuals/hazard_art.gd").release_caches()
	print("ASSET A3: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL",checks])
	await root.get_node("AudioService").settle()
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
		if batch.material.shader == art.Prop:
			check(float(batch.material.get_shader_parameter("emission_gain")) <= 1.2,"R2 B4 capped prop emission gain")
			for channel: String in art.PROP_MAPS:
				check(batch.material.get_shader_parameter(channel+"_atlas") == art.PROP_MAPS[channel],"prop binds the shared atlas " + channel)
		for surface in batch.mesh.get_surface_count():
			var arrays: Array = batch.mesh.surface_get_arrays(surface)
			for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
				check(uv.x >= -0.001 and uv.x <= 1.001 and uv.y >= -0.001 and uv.y <= 1.001,"R2 per-face UV range")
	if visual.kind != &"projectile":
		# Every barrier is a mounted Blender prop: its batches draw baked GLB meshes, not forge boxes.
		var prop_pieces := 0
		for batch: Dictionary in art._batches:
			if batch.material.shader == art.Prop: prop_pieces += batch.instances.size()
		check(prop_pieces > 0 and not art.prop_layout(art._prop_root()).is_empty(),title+" mounts its baked prop layout")
		for batch: Dictionary in art._batches:
			if batch.material.shader != art.Prop: continue
			var unit: AABB = batch.mesh.get_aabb()
			check(unit.position.is_equal_approx(-Vector3.ONE*0.5) or unit.size.x < 1.0001,"prop batch meshes live in the shared unit box")
			var source: Mesh = batch.mesh.get_meta("source")
			for item: Array in batch.instances:
				check(item[1].is_equal_approx(source.get_aabb().size.max(Vector3.ONE*0.001)),"prop instance scale equals its baked bounds")
	if visual.kind == &"deprecated_pit":
		check(is_equal_approx(art.tag.rotation.x,-PI/2),"R3 B1 pit front faces upward")
		check(art.tag.position.y < 0.05,"R2 B3 floor-level tag")
	if visual.kind == &"bug_swarm":
		# Several articulated bodies that bob, each carrying a pair of clock-driven flapping wings.
		var bodies := 0
		var wings: Array[Node3D] = []
		for item: Dictionary in art._moving:
			if item.style == "bug": bodies += 1
			if item.style == "wing": wings.append(item.node)
		check(bodies >= 3 and wings.size() >= bodies*2,"R2 B6 several beetles, each with a visible wing pair")
		for batch: Dictionary in art._batches:
			for item: Array in batch.instances:
				if item[0].get_parent() in wings:
					var extent: Vector3 = item[1]
					check(minf(extent.x,minf(extent.y,extent.z)) <= 0.02,"R3 B5 thin wing membranes")
		if not wings.is_empty():
			var before := wings[0].rotation
			art.advance(0.013)
			check(not wings[0].rotation.is_equal_approx(before),"R2 B6 clock-driven flutter")
	if visual.kind == &"build_shockwave":
		# One broad, low cracked ring spans every lane; floating debris rides its crest.
		var span := AABB()
		var first := true
		for batch: Dictionary in art._batches:
			if batch.material.shader != art.Prop: continue
			for item: Array in batch.instances:
				var box: AABB = art.body.global_transform.affine_inverse()*item[0].global_transform.scaled_local(item[1])*batch.mesh.get_aabb()
				span = box if first else span.merge(box)
				first = false
		check(span.size.x >= visual.hitbox_size.x*0.95 and span.size.y <= visual.hitbox_size.y*1.1,"R3 B6 one continuous low ring across all lanes")
		var debris := 0
		for item: Dictionary in art._moving:
			if item.style == "debris": debris += 1
		check(debris >= 8,"R3 B6 faceted debris")
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
		check(float(art._materials.prop.get_shader_parameter("charge")) == 0.75,"R2 B8 emitter housing charge")
		check(art.tag.text == "CHARGING","R2 B8 explicit charge message")
		visual.set_telegraph(0.0)
		check(not art.scanner.visible and art._charge == 0.0,"R2 B8 charge reset")
	# Per-rig material instances must not leak telegraph/clock changes into another spawn.
	var clone := spawn([visual.kind,visual.variant,visual.hitbox_size,visual.hitbox_offset.y],root)
	clone.set_process(false)
	for key: String in art._materials:
		if clone._art._materials.has(key): check(art._materials[key] != clone._art._materials[key],"R2 instance-local materials")
	# Immutable footprint resources are shared per colour/size; a clear swaps, never mutates them.
	if art.has_node("FloorMarker"):
		var mine: MeshInstance3D = art.get_node("FloorMarker")
		var theirs: MeshInstance3D = clone._art.get_node("FloorMarker")
		check(mine.mesh == theirs.mesh and mine.material_override == theirs.material_override,"shared footprint quad and material")
		check(absf(mine.position.y-0.012) >= 0.005 and mine.position.y <= 0.05,"footprint clear of the corridor lane glow plane")
		var before: Color = theirs.material_override.emission
		clone._art.react(true)
		check(mine.material_override.emission == before and theirs.material_override.emission == art.Palette.MINT,"cleared footprint swap leaves other rigs untouched")
	if art.has_node("SafeGap"):
		check(absf(art.get_node("SafeGap").position.y-art.get_node("FloorMarker").position.y) >= 0.005,"footprint layers never share a plane")
	# Per-kind prop meshes come from one cached layout: a new spawn instances them, never rebuilds.
	for i in art._batches.size():
		if i < clone._art._batches.size() and art._batches[i].material.shader == art.Prop:
			check(art._batches[i].mesh == clone._art._batches[i].mesh,"shared per-kind prop mesh")
	for sparks: GPUParticles3D in art.find_children("BoundedSparks","GPUParticles3D",true,false):
		var twin := clone._art.get_node_or_null("BoundedSparks") as GPUParticles3D
		if twin != null: check(twin.draw_pass_1 == sparks.draw_pass_1,"shared spark draw pass")
	clone.free()

func _round_three(visual: Base) -> void:
	var art: Node3D = visual.get_node("Artwork")
	if visual.kind != &"projectile": _palette(visual)
	if visual.kind == &"merge_conflict":
		var halves: Array[ShaderMaterial] = []
		for batch: Dictionary in art._batches:
			for item: Array in batch.instances:
				var role := String(item[0].get_parent().name)
				if role.begins_with("Ours") or role.begins_with("Theirs"): halves.append(batch.material)
		check(halves.size() == 2 and halves[0] == halves[1],"R8 both slabs share one plating and normal treatment")
	if visual.kind == &"deprecated_pit":
		check(art.tag.global_basis.z.normalized().dot(Vector3.UP) > 0.999,"R3 B1 label face +Y")
		check(art.tag.global_basis.y.normalized().dot(Vector3.FORWARD) > 0.999,"R3 B1 glyph up maps to -Z")
		check(art._plates.back().global_basis.y.normalized().dot(Vector3.UP) > 0.999,"R3 B1 XZ backing normal +Y")
		# Pit contrast by construction: nothing lit lies over the opening. The tag and its backing sit
		# on the near rim band, a clearance beyond the mouth's near edge and inside the envelope.
		var mouth_near: float = visual.hitbox_offset.z+art._pit_mouth.mesh.size.y*0.5+art.PIT_TAG_CLEARANCE-0.0005
		var tag_font: Font = art.tag.font if art.tag.font != null else ThemeDB.fallback_font
		var tag_depth: float = tag_font.get_height(art.tag.font_size)*art.tag.pixel_size
		check(art.tag.position.z-tag_depth*0.5 >= mouth_near and art.tag.position.z+tag_depth*0.5 <= visual.hitbox_size.z*0.55,"R6 pit tag clear of the mouth (%.3f..%.3f, mouth edge %.3f)" % [art.tag.position.z-tag_depth*0.5,art.tag.position.z+tag_depth*0.5,mouth_near])
		for batch: Dictionary in art._batches:
			for item: Array in batch.instances:
				if item[0] == art._plates.back():
					check(item[0].position.z-item[1].z*0.5 >= mouth_near and item[0].position.z+item[1].z*0.5 <= visual.hitbox_size.z*0.55,"R6 pit tag backing clear of the mouth")
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

		var sagging := false
		for batch: Dictionary in art._batches:
			for item: Array in batch.instances:
				var bounds: AABB = item[0].global_transform.scaled_local(item[1])*batch.mesh.get_aabb()
				check(bounds.end.y <= 0.0201,"R3 B2 rim and hardware at floor level")
				if batch.material.shader == art.Prop: check(_median_value(batch.mesh.get_meta("source")) < 0.45,"R4 dark legacy-stone lip")
				sagging = sagging or bounds.position.y < -0.03
		check(sagging,"R3 B2 crumbling lip sags into the well")
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
		# Hostile red membranes and wing covers, distinct from every friendly pickup hue.
		for batch: Dictionary in art._batches:
			if batch.material.shader != art.Prop: continue
			var shares := _shares(batch.mesh)
			var wing := String(batch.instances[0][0].get_parent().name).begins_with("Wing")
			check(shares.danger >= (0.5 if wing else 0.15),"hostile %s surfaces use DANGER (%.2f)" % ["wing" if wing else "body",shares.danger])
			if wing:
				# Tapered membranes: the wing narrows to a point at both ends of its length.
				var source: Mesh = batch.mesh.get_meta("source")
				var aabb: AABB = source.get_aabb()
				for vertex: Vector3 in source.get_faces():
					if vertex.z < aabb.position.z+0.005 or vertex.z > aabb.end.z-0.002: check(absf(vertex.x) < 0.012,"R3 B5 tapered wing ends")

	var old_z := visual.position.z
	visual.position.z = -60
	art.update_view_distance()
	check(is_equal_approx(art._distance_gain,4.5),"R3 bounded distance visibility gain")
	visual.position.z = old_z
	art.update_view_distance()

## Area-weighted atlas samples (four barycentric points per triangle) of one baked mesh.
func _samples(mesh: Mesh) -> Array:
	var out: Array = []
	# Batched props draw unit-box copies; weigh areas on the baked source mesh.
	if mesh.has_meta("source"): mesh = mesh.get_meta("source")
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):
		var a := indices[i]
		var b := indices[i+1]
		var c := indices[i+2]
		var area := (points[b]-points[a]).cross(points[c]-points[a]).length()*0.5
		for w: Vector3 in [Vector3.ONE/3.0,Vector3(0.6,0.2,0.2),Vector3(0.2,0.6,0.2),Vector3(0.2,0.2,0.6)]:
			out.append([uvs[a]*w.x+uvs[b]*w.y+uvs[c]*w.z,area*0.25])
	return out

func _texel(image: Image, uv: Vector2) -> Color:
	var size := image.get_size()
	return image.get_pixel(clampi(int(uv.x*size.x),0,size.x-1),clampi(int(uv.y*size.y),0,size.y-1))

static func _hue_near(colour: Color, target: Color, width: float) -> bool:
	var d := absf(colour.h-target.h)
	return minf(d,1.0-d) < width

## Area shares of one baked mesh: DANGER albedo or emission, LILAC, help hues glowing, ink, emissive.
func _shares(mesh: Mesh) -> Dictionary:
	var out := {"area": 0.0, "danger": 0.0, "lilac": 0.0, "help_glow": 0.0, "ink": 0.0, "lit": 0.0}
	for sample: Array in _samples(mesh):
		var albedo := _texel(albedo_image,sample[0])
		var glow := _texel(emission_image,sample[0])
		var weight: float = sample[1]
		out.area += weight
		var red := (_hue_near(albedo,Palette.DANGER,0.03) and albedo.s > 0.5 and albedo.v > 0.15) or (_hue_near(glow,Palette.DANGER,0.03) and glow.v > 0.1)
		if red: out.danger += weight
		if (_hue_near(albedo,Palette.LILAC,0.05) and albedo.s > 0.2) or (_hue_near(glow,Palette.LILAC,0.05) and glow.v > 0.1 and glow.s > 0.2): out.lilac += weight
		if glow.v > 0.05 and glow.s > 0.2 and (_hue_near(glow,Palette.MINT,0.06) or _hue_near(glow,Palette.MATRIX,0.06) or _hue_near(glow,Palette.ORANGE,0.03)): out.help_glow += weight
		if albedo.v > 0.45 and albedo.s < 0.4: out.ink += weight
		if glow.v > 0.02: out.lit += weight
	for key: String in out:
		if key != "area": out[key] /= maxf(out.area,0.000001)
	return out

func _median_value(mesh: Mesh) -> float:
	var values: Array[float] = []
	for sample: Array in _samples(mesh): values.append(_texel(albedo_image,sample[0]).v)
	values.sort()
	return values[values.size()/2] if not values.is_empty() else 0.0

## Help-vs-hurt palette from the baked atlas, weighted by every instance's surface area.
func _palette(visual: Base) -> void:
	var art: Node3D = visual.get_node("Artwork")
	var total := {"area": 0.0, "danger": 0.0, "lilac": 0.0, "help_glow": 0.0, "lit": 0.0}
	for batch: Dictionary in art._batches:
		if batch.material.shader != art.Prop: continue
		var shares := _shares(batch.mesh)
		var role := String(batch.instances[0][0].get_parent().name)
		var weight: float = shares.area*batch.instances.size()
		for key: String in total: total[key] += weight if key == "area" else shares[key]*weight
		if role.begins_with("Theirs"): check(shares.lilac >= 0.05,"LILAC marks the theirs half (%.2f)" % shares.lilac)
		else: check(shares.lilac <= 0.002,"LILAC only on the merge-conflict theirs half %s (%.3f)" % [role,shares.lilac])
		if role.begins_with("Crate") or role.begins_with("Card") or role.begins_with("Ticket") or role.begins_with("Ours"):
			check(shares.ink >= 0.01,"%s carries baked CREAM code-line ink (%.3f)" % [role,shares.ink])
	for key: String in total:
		if key != "area": total[key] /= maxf(total.area,0.000001)
	print("A3 PALETTE: %s/%s danger=%.3f lilac=%.3f help_glow=%.4f emissive=%.3f" % [visual.kind,visual.variant,total.danger,total.lilac,total.help_glow,total.lit])
	check(total.danger >= 0.01,"hazard reads DANGER from its baked accents")
	check(total.help_glow <= 0.002,"no friendly MINT / MATRIX / ORANGE glow on a hazard")
	check(total.lit <= 0.40,"baked emissive surface below forty percent")

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
