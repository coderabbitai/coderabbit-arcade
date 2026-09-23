extends SceneTree
## Host-only fixture. Does not preload or run the gameplay facade.
const Metrics = preload("res://scenes/runner/hazards/visuals/hifi/capture_metrics.gd")
const Check = preload("res://tests/assets/a3_check.gd")
const Forge = preload("res://scenes/runner/hazards/visuals/hifi/mesh_forge.gd")
const Textures = preload("res://scenes/runner/hazards/visuals/hifi/texture_forge.gd")
const CorridorMaterials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
class CaptureErrors extends Logger:
	var count := 0
	var mutex := Mutex.new()
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			mutex.lock()
			count += 1
			mutex.unlock()

var errors := CaptureErrors.new()
var logger_registered := false
var failures: Array[String] = []
var saved_views := 0
var world: Node3D
var camera: Camera3D
var caption: Label

func _initialize() -> void:
	call_deferred("_begin")

func _begin() -> void:
	# The visual fixture does not use autoload music. Stop its MP3 playback while
	# the audio server is alive, then allow queued playback references to drain.
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"): audio.shutdown()
	await create_timer(0.1).timeout
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A3 CAPTURE: FAIL (graphical display required)")
		quit(1)
		return
	OS.add_logger(errors)
	logger_registered = true
	await _capture()

func _panel(pos: Vector3, size: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.mesh = Forge.bevel_box()
	node.position = pos
	node.scale = size
	var mat := Metrics.fixture_plate()
	# Keep relief without multiplying the navy albedo by the atlas's dark RGB.
	mat.normal_enabled = true
	mat.normal_texture = Textures.maps().normal
	node.material_override = mat
	world.add_child(node)

func _settle() -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw

func _capture() -> void:
	root.size = Vector2i(1280,720)
	root.scaling_3d_scale = 0.5
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = CorridorMaterials.environment()
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50,-25,0)
	key.light_color = Palette.MATRIX
	key.light_energy = 0.35
	key.shadow_enabled = false
	world.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0,3,1)
	fill.light_color = Palette.CREAM
	fill.light_energy = 1.6
	fill.omni_range = 9.0
	fill.shadow_enabled = false
	world.add_child(fill)
	_panel(Vector3(0,-0.10,-8),Vector3(9,0.20,40))
	for side in [-1,1]:
		_panel(Vector3(side*4.5,3,-8),Vector3(0.25,6,40))
		for z in 8: _panel(Vector3(side*4.28,2.5,-float(z)*4),Vector3(0.2,5,0.18))
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 60
	world.add_child(camera)
	camera.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24,24)
	caption.add_theme_font_size_override("font_size",22)
	caption.add_theme_color_override("font_color",Palette.CREAM)
	layer.add_child(caption)
	var folder := ProjectSettings.globalize_path("res://../docs/previews/assets")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		printerr("ASSET A3 CAPTURE: FAIL (cannot create output directory)")
		quit(1)
		return
	for entry: Array in Check.CASES:
		var visual := Check.spawn(entry,world)
		visual.set_process(false)
		visual._process(0.18)
		var slug := str(entry[0]) + ("-"+str(entry[1]) if entry[1] != "" else "")
		var center := visual.hitbox_offset
		for view in ["gameplay","close","oblique","distance60"]:
			match view:
				"gameplay": camera.position = Vector3(0,4,12)
				"distance60": camera.position = Vector3(0,4,60)
				"close": camera.position = center+Vector3(0,1.3,maxf(2.3,visual.hitbox_size.x*1.02))
				"oblique": camera.position = center+Vector3(4,3,6)
			camera.look_at(center)
			visual._art.update_view_distance()
			if entry[1] == "timed": visual.set_telegraph(0.75 if view in ["close","distance60"] else 0.0)
			visual.hide()
			await _settle()
			var baseline := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			visual.show()
			visual._art._update_batches()
			await _settle()
			var total := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			if total-baseline > 16:
				_record_failure("%s/%s asset draw budget exceeded" % [slug,view])
			caption.text = "A3 / %s / %s    total draws %d | asset delta %d" % [slug,view,total,total-baseline]
			await _settle()
			var result := root.get_texture().get_image().save_png(folder+"/a3-"+slug+"-"+view+".png")
			if result != OK:
				_record_failure("%s/%s PNG write %d" % [slug,view,result])
			else:
				saved_views += 1
				var saved_image := Image.load_from_file(folder+"/a3-"+slug+"-"+view+".png")
				_check_exposure(saved_image,visual,slug+"/"+view)
			if result == OK and entry[0] == "deprecated_pit" and view in ["gameplay","oblique"]:
				if not _check_saved_pit(folder+"/a3-"+slug+"-"+view+".png",visual,slug+"/"+view,view):
					_record_failure("%s/%s pit contrast" % [slug,view])
			print("A3 CAPTURE: %s/%s total_draws=%d asset_delta=%d" % [slug,view,total,total-baseline])
		if entry[0] == "deprecated_pit":
			await _prove_pit_occlusion(visual,folder,slug)
		visual.free()
		await process_frame
	if errors.count > 0:
		_record_failure("%d renderer/runtime errors" % errors.count)
	if saved_views != 68: _record_failure("saved %d of 68 required views" % saved_views)
	print("A3 CAPTURE SAVED: %d / 68" % saved_views)
	for failure in failures: printerr("A3 CAPTURE FAILURE: "+failure)
	print("ASSET A3 CAPTURE: PASS" if failures.is_empty() else "ASSET A3 CAPTURE: FAIL (%d failures)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _record_failure(message: String) -> void:
	failures.append(message)
	printerr("A3 CAPTURE CHECK: "+message)

func _prove_pit_occlusion(visual: Node3D, folder: String, slug: String) -> void:
	var capsule := MeshInstance3D.new()
	capsule.name = "StandInCapsule"
	capsule.process_mode = Node.PROCESS_MODE_PAUSABLE
	capsule.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	capsule.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shape := CapsuleMesh.new()
	shape.radius = 0.4
	shape.height = 1.8
	shape.radial_segments = 32
	shape.rings = 32
	capsule.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Palette.MINT
	capsule.material_override = material
	world.add_child(capsule)
	caption.hide()
	camera.position = Vector3(3.5,3.2,5.5)
	camera.look_at(Vector3(0,0.75,0))
	for pose in ["landing","apex"]:
		# Six cm landing clearance avoids intentionally foreground rim/label geometry.
		capsule.position = Vector3(0,0.96 if pose == "landing" else 2.3,0.15)
		visual.hide()
		capsule.hide()
		await _settle()
		var background := root.get_texture().get_image()
		capsule.show()
		await _settle()
		var reference := root.get_texture().get_image()
		visual.show()
		visual._art._update_batches()
		await _settle()
		var actual := root.get_texture().get_image()
		var pixels := Metrics.compare_capsule(reference,background,actual)
		var passed := pixels.x >= 500 and pixels.y == 0
		# Always save evidence, including a failed occlusion image, and keep going.
		if actual.save_png(folder+"/a3-"+slug+"-occlusion-"+pose+".png") != OK:
			_record_failure("%s/%s occlusion PNG write" % [slug,pose])
		else:
			saved_views += 1
			var saved_image := Image.load_from_file(folder+"/a3-"+slug+"-occlusion-"+pose+".png")
			_check_exposure(saved_image,visual,slug+"/occlusion-"+pose,[capsule.global_transform*capsule.get_aabb()])
		if not passed: _record_failure("%s/%s occlusion checked=%d overwritten=%d" % [slug,pose,pixels.x,pixels.y])
		print("A3 OCCLUSION: %s/occlusion-%s checked=%d overwritten=%d %s" % [slug,pose,pixels.x,pixels.y,"PASS" if passed else "FAIL"])
	capsule.free()
	caption.show()

func _finalize() -> void:
	if logger_registered: OS.remove_logger(errors)
	errors = null
	# SceneTree has already released the root before _finalize.
	# Drop script references and the logger without touching the destroyed tree.
	world = null
	camera = null
	caption = null

func _check_saved_pit(path: String, visual: Node3D, title: String, view: String) -> bool:
	# Reopen the saved PNG, not the live framebuffer. Sample clear mouth and floor.
	var image := Image.load_from_file(path)
	if image == null: return false
	var mouth: Array[Vector2i] = []
	var floor_pixels: Array[Vector2i] = []
	var mouth_mesh: MeshInstance3D = visual._art._pit_mouth
	var half_size: Vector2 = mouth_mesh.mesh.size*0.5
	for row in 20:
		for col in 24:
			var point := mouth_mesh.to_global(Vector3(lerpf(-0.65,0.65,float(col)/23.0)*half_size.x,0,lerpf(-0.88,0.88,float(row)/19.0)*half_size.y))
			var pixel := Vector2i(camera.unproject_position(point))
			if Rect2i(Vector2i.ZERO,image.get_size()).has_point(pixel): mouth.append(pixel)
	var reference := _floor_probes(image,visual)
	floor_pixels.assign(reference.pixels)
	var metrics := Metrics.pit_contrast(image,mouth,floor_pixels,view)
	if floor_pixels.size() < 60:
		print("A3 PIT CONTRAST: %s top=%.6f top_min=%.6f middle=%.6f bottom=%.6f floor_median=%.6f floor_p90=%.6f SKIP (%s)" % [title,metrics.top,metrics.top_min,metrics.middle,metrics.bottom,metrics.floor_median,metrics.floor_p90,reference.reason])
		return true
	print("A3 PIT CONTRAST: %s top=%.6f top_min=%.6f middle=%.6f bottom=%.6f floor_mean=%.6f floor_median=%.6f floor_p90=%.6f exposure=%s mouth=%s %s" % [title,metrics.top,metrics.top_min,metrics.middle,metrics.bottom,metrics.floor,metrics.floor_median,metrics.floor_p90,metrics.exposure_pass,metrics.mouth_pass,"PASS" if metrics.mouth_pass else "FAIL"])
	return metrics.mouth_pass

func _floor_probes(image: Image, visual: Node3D, extra_bounds: Array[AABB] = []) -> Dictionary:
	var pixels: Array[Vector2i] = []
	# Beyond the depth-fog midpoint the reference is fog, not exposed floor.
	if camera.global_position.distance_to(visual.global_position) >= 55.0:
		return {"pixels":pixels,"reason":"floor reference is fog-dominated at >=55m"}
	var bounds := AABB(visual.global_position+visual.hitbox_offset-visual.hitbox_size*0.55,visual.hitbox_size*1.1)
	var viewport_rect := Rect2i(Vector2i(4,4),image.get_size()-Vector2i(8,8))
	for side in [-1,1]:
		for column in 6:
			var x: float = side*(visual.hitbox_size.x*0.60+float(column)*0.07)
			if absf(x) >= 4.05: continue # Stay clear of the corridor wall.
			for row in 32:
				var point: Vector3 = visual.global_position+Vector3(x,0.002,lerpf(-0.9,0.9,float(row)/31))
				if camera.is_position_behind(point): continue
				var pixel := Vector2i(camera.unproject_position(point))
				if not viewport_rect.has_point(pixel): continue
				if bounds.intersects_segment(camera.global_position,point) != null: continue
				var blocked := false
				for extra in extra_bounds:
					if extra.intersects_segment(camera.global_position,point) != null: blocked = true
				if not blocked and not pixels.has(pixel): pixels.append(pixel)
	return {"pixels":pixels,"reason":"fewer than 60 distinct visible floor probes outside the hazard footprint (%d)" % pixels.size()}

func _check_exposure(image: Image, visual: Node3D, title: String, extra_bounds: Array[AABB] = []) -> void:
	var reference := _floor_probes(image,visual,extra_bounds)
	var probes: Array[Vector2i] = []
	probes.assign(reference.pixels)
	var measured := Metrics.floor_exposure(image,probes)
	if probes.size() < 60:
		print("A3 EXPOSURE: %s floor_median=%.6f floor_p90=%.6f probes=%d SKIP (%s)" % [title,measured.median,measured.p90,probes.size(),reference.reason])
		return
	print("A3 EXPOSURE: %s floor_median=%.6f floor_p90=%.6f probes=%d %s" % [title,measured.median,measured.p90,probes.size(),"PASS" if measured.pass else "FAIL"])
	if not measured.pass: _record_failure(title+" floor reference exposure")
