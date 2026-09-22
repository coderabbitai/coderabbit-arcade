extends SceneTree
## Host-only: actual shipping corridor, paired background/body/full renders.
const KINDS := [&"approve_shield",&"auto_fix",&"lgtm",&"nitro",&"super_jump",&"code_review",&"review_comment",&"lint_rule",&"unit_test",&"auto_fix_patch"]
const CORRIDOR = preload("res://scenes/runner/environment/corridor.tscn")
const CorridorMaterials = preload("res://scenes/runner/environment/runner_materials.gd")
var stage: Node3D
var pickups: Node3D
var camera: Camera3D
var capture_view := ""

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A4 CAPTURE: FAIL (graphical renderer required)")
		quit(1)
		return
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	stage = Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(stage)
	# Read-only instance: retains floor grid, code walls, racks, rain and FarGlow,
	# environment, lights and the shipped retro render scale.
	var corridor := CORRIDOR.instantiate()
	stage.add_child(corridor)
	corridor._process(0.5)
	corridor.set_process(false)
	camera = Camera3D.new()
	camera.fov = 60
	stage.add_child(camera)
	camera.make_current()
	pickups = Node3D.new()
	stage.add_child(pickups)
	var directory := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(directory)
	var passed := true
	var views := ["powerups","tools","closeup","gameplay","gameplay-tools","stacked","stacked-tools"]
	for kind in KINDS: views.append("distance-"+str(kind))
	for view: String in views:
		capture_view = view
		print("A4 VIEW BEGIN [%s]" % view)
		for child in pickups.get_children(): child.free()
		var gameplay: bool = view.begins_with("gameplay") or view.begins_with("stacked") or view.begins_with("distance-")
		var selection: Array = KINDS.slice(0,6) if view == "powerups" else KINDS.slice(6)
		if view == "closeup": selection = [&"approve_shield",&"super_jump",&"code_review"]
		if gameplay: selection = [&"review_comment",&"lint_rule",&"auto_fix_patch"] if view.ends_with("tools") else [&"approve_shield",&"auto_fix",&"super_jump"]
		if view.begins_with("distance-"):
			var kind := StringName(view.trim_prefix("distance-"))
			selection = [kind,kind,kind]
		camera.position = Vector3(0,4,8) if gameplay else Vector3(0,2.6,8.5)
		camera.look_at(Vector3(0,1,-8) if gameplay else Vector3(0,0.95,0))
		if view == "closeup":
			camera.position = Vector3(0.12,2.2,5.4)
			camera.look_at(Vector3(0,0.98,0))
		for i in selection.size():
			var visual := (load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % selection[i]) as PackedScene).instantiate() as Node3D
			pickups.add_child(visual)
			visual.set("kind",selection[i])
			visual.position = Vector3((i-(selection.size()-1)/2.0)*1.5,1,0)
			if gameplay: visual.position = Vector3((i-1)*2,1,-20.0*(i+1))
			if view.begins_with("stacked") and i > 0: visual.position.x = 0.0
			visual.on_spawned()
			visual._art._process(0.10)
			visual._art.set_process(false)
		# Settle the real half-second transitions before freezing each view.
		for tick in 40:
			for visual in pickups.get_children(): visual._art._process(1.0/60.0)
		# Same-region baseline excludes every pickup. Keep the live corridor intact.
		pickups.hide()
		var background: Image = await rendered_image()
		pickups.show()
		for visual in pickups.get_children():
			visual._art._pool.hide()
			visual._art._glyph.hide()
			visual._art._tag.hide()
			visual._art._tag_plate.hide()
		var body: Image = await rendered_image()
		# Isolate beam pixels: hide sculptures, tags, glyphs AND floor ring/halo.
		for visual in pickups.get_children():
			visual._art._pivot.hide()
			visual._art._pool.show()
			visual._art._pool.material_override.set_shader_parameter("beam_only",1.0)
		var beam: Image = await rendered_image()
		for visual in pickups.get_children():
			visual._art._pivot.show()
			visual._art._tag.show()
			visual._art._tag_plate.show()
			visual._art._pool.material_override.set_shader_parameter("beam_only",0.0)
			visual._art._update_affordance()
		var image: Image = await rendered_image()
		for visual in pickups.get_children():
			passed = glyph_color_guard(image,visual) and passed
			passed = body_image_guard(body,background,visual) and passed
		if gameplay:
			for visual in pickups.get_children():
				passed = beacon_image_guard(beam,background,visual) and passed
		if view.begins_with("stacked"):
			passed = stacked_peak_guard(image,background,pickups.get_child(1),pickups.get_child(2)) and passed
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var result := image.save_png(directory+"/a4-"+view+".png")
		if result != OK:
			printerr("ASSET A4 CAPTURE: FAIL (save %s: %d)" % [view,result])
			passed = false
		print("ASSET A4 CAPTURE %s: %d measured scene draw calls" % [view,draws])
	print("ASSET A4 CAPTURE: %s" % ("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)

func rendered_image() -> Image:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

static func fixture_environment() -> Environment:
	return CorridorMaterials.environment()

static func luminance(color: Color) -> float:
	return Vector3(color.r,color.g,color.b).dot(Vector3(0.2126,0.7152,0.0722))

static func percentile(values: Array[float], fraction: float) -> float:
	values.sort()
	return values[mini(values.size()-1,int((values.size()-1)*fraction))]

func region_values(image: Image, rect: Rect2i) -> Array[float]:
	var values: Array[float] = []
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x): values.append(luminance(image.get_pixel(x,y)))
	return values

static func brightest_body_p75(values: Array[float]) -> float:
	# Discard the darkest 40% of the dilated projected body rectangle, then
	# take p75 of the retained 60%. This is not p75 of the whole rectangle.
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var retained: Array[float] = []
	retained.assign(sorted.slice(floori(sorted.size()*0.4)))
	return percentile(retained,0.75)

static func projected_body_rect(camera_node: Camera3D, pivot: Node3D) -> Rect2i:
	var rect := Rect2()
	var initialized := false
	for node in pivot.get_children():
		var poses: Array[Transform3D] = []
		var bounds: AABB
		if node is MeshInstance3D:
			bounds = node.mesh.get_aabb()
			poses.append(node.global_transform)
		elif node is MultiMeshInstance3D:
			bounds = node.multimesh.mesh.get_aabb()
			for i in node.multimesh.instance_count: poses.append(node.global_transform*node.multimesh.get_instance_transform(i))
		else: continue
		for pose in poses:
			for i in 8:
				var screen := camera_node.unproject_position(pose*bounds.get_endpoint(i))
				if not initialized:
					rect = Rect2(screen,Vector2.ZERO)
					initialized = true
				else: rect = rect.expand(screen)
	if not initialized: return Rect2i()
	var start := Vector2i(floori(rect.position.x),floori(rect.position.y))-Vector2i.ONE
	var end := Vector2i(ceili(rect.end.x),ceili(rect.end.y))+Vector2i.ONE
	return Rect2i(start,end-start)

static func body_threshold(distance: float, backdrop: float) -> float:
	return maxf(0.16,backdrop+0.08) if distance <= 40.0 else backdrop+0.03

static func body_color_quality(colors: Array[Color]) -> Vector2:
	if colors.is_empty(): return Vector2(0,1)
	var sorted := colors.duplicate()
	sorted.sort_custom(func(a: Color,b: Color) -> bool: return luminance(a) < luminance(b))
	var brightest: Array[Color] = []
	brightest.assign(sorted.slice(floori(sorted.size()*0.8)))
	return color_quality(brightest)

static func body_accepts(distance: float, backdrop: float, light: float, lit_pixels: int, quality: Vector2) -> bool:
	return light >= body_threshold(distance,backdrop) and (distance <= 40.0 or lit_pixels >= 3) and quality.x >= 0.25 and quality.y <= 0.05

func body_image_guard(body: Image, background: Image, visual: Node3D) -> bool:
	var rect := projected_body_rect(camera,visual._art._pivot)
	var backdrop := percentile(region_values(background,rect),0.5)
	var values := region_values(body,rect)
	var body_light := brightest_body_p75(values)
	var distance := -visual.position.z
	var threshold := body_threshold(distance,backdrop)
	var lit_pixels := 0
	for value in values:
		if value >= threshold: lit_pixels += 1
	var colors: Array[Color] = []
	for y in range(maxi(0,rect.position.y),mini(body.get_height(),rect.end.y)):
		for x in range(maxi(0,rect.position.x),mini(body.get_width(),rect.end.x)): colors.append(body.get_pixel(x,y))
	var quality := body_color_quality(colors)
	var passed := body_accepts(distance,backdrop,body_light,lit_pixels,quality)
	print("A4 BODY HUE [%s] kind=%s %dm: saturation_brightest20=%.3f white_ratio=%.3f saturation_min=0.25 white_ratio_max=0.05 clause=%s" % [capture_view,visual._art._kind,distance,quality.x,quality.y,"brightness" if distance <= 40.0 else "presence"])
	print("A4 BODY GUARD [%s] [%s] kind=%s %dm: %s body_p75_brightest60=%.3f backdrop_median=%.3f bbox=%s samples=%d lit_pixels=%d brightness_min=%.3f lit_pixels_min=%d saturation_min=0.25 white_ratio_max=0.05" % [capture_view,"tools" if visual._art._is_tool else "powerups",visual._art._kind,-visual.position.z,"PASS" if passed else "FAIL",body_light,backdrop,rect,values.size(),lit_pixels,threshold,0 if distance <= 40.0 else 3])
	return passed

func beacon_image_guard(image: Image, background: Image, visual: Node3D) -> bool:
	var origin: Vector3 = visual.global_position+Vector3(visual._art._beam_offset,0,0)
	origin.y = 1.4
	var center := camera.unproject_position(origin)
	var radius := maxf(1.0,camera.unproject_position(origin+Vector3.RIGHT*visual._art._beam_width*0.25).distance_to(center))
	var rect := Rect2i(Vector2i(center)-Vector2i(ceili(radius),3),Vector2i(ceili(radius)*2+1,7))
	var backdrop := percentile(region_values(background,rect),0.5)
	var beam_light := percentile(region_values(image,rect),0.75)
	var passed := beam_light >= backdrop+0.15
	print("A4 ISOLATED BEAM GUARD [%s] [%s] kind=%s %dm: %s beam_p75=%.3f backdrop_median=%.3f" % [capture_view,"tools" if visual._art._is_tool else "powerups",visual._art._kind,-visual.position.z,"PASS" if passed else "FAIL",beam_light,backdrop])
	return passed

static func color_quality(colors: Array[Color]) -> Vector2:
	if colors.is_empty(): return Vector2(0,1)
	var saturation := 0.0
	var white := 0.0
	for color in colors:
		saturation += color.s
		if minf(color.r,minf(color.g,color.b)) >= 0.98: white += 1.0
	return Vector2(saturation/colors.size(),white/colors.size())

func glyph_color_guard(image: Image, visual: Node3D) -> bool:
	var art: Node3D = visual._art
	var texture: Texture2D = art._glyph.material_override.get_shader_parameter("glyph")
	var mask := texture.get_image()
	var colors: Array[Color] = []
	var visited: Dictionary = {}
	# Measure actual stroke pixels on the composite, not transparent quad padding.
	for y in range(0,mask.get_height(),2):
		for x in range(0,mask.get_width(),2):
			if mask.get_pixel(x,y).a < 0.7: continue
			var point: Vector3 = art._glyph.to_global(Vector3((x+0.5)/mask.get_width()-0.5,0.5-(y+0.5)/mask.get_height(),0))
			var pixel := Vector2i(camera.unproject_position(point))
			if not Rect2i(Vector2i.ZERO,image.get_size()).has_point(pixel):
				printerr("A4 GLYPH COLOR: FAIL (clipped stroke)")
				return false
			if visited.has(pixel): continue
			visited[pixel] = true
			colors.append(image.get_pixelv(pixel))
	var quality := color_quality(colors)
	var passed := quality.x >= 0.25 and quality.y <= 0.05
	print("A4 GLYPH COLOR [%s] kind=%s: %s saturation=%.3f white_ratio=%.3f samples=%d" % [capture_view,art._kind,"PASS" if passed else "FAIL",quality.x,quality.y,colors.size()])
	return passed

static func separated_peaks(profile: Array[float], first: int, second: int) -> bool:
	if first > second:
		var swap := first
		first = second
		second = swap
	if second-first < 3: return false
	var valley := INF
	for i in range(first+1,second): valley = minf(valley,profile[i])
	return minf(profile[first],profile[second]) >= 0.15 and valley <= minf(profile[first],profile[second])*0.75

func stacked_peak_guard(beam: Image, background: Image, front: Node3D, rear: Node3D) -> bool:
	var a := camera.unproject_position(Vector3(front.position.x+front._art._beam_offset,1.4,front.position.z))
	var b := camera.unproject_position(Vector3(rear.position.x+rear._art._beam_offset,1.4,rear.position.z))
	var direction := (b-a).normalized()
	var length := a.distance_to(b)
	var profile: Array[float] = []
	# Sample along the staggered lane cues, extending beyond both expected peaks.
	for i in range(-3,ceili(length)+4):
		var pixel := Vector2i(a+direction*i)
		profile.append(maxf(0.0,luminance(beam.get_pixelv(pixel))-luminance(background.get_pixelv(pixel))))
	var first := 3
	var second := 3+roundi(length)
	for i in range(1,6):
		if profile[i] > profile[first]: first = i
	for i in range(maxi(0,second-2),mini(profile.size(),second+3)):
		if profile[i] > profile[second]: second = i
	var passed := separated_peaks(profile,first,second)
	print("A4 STACKED PEAKS: %s separation=%dpx peaks=%.3f/%.3f" % ["PASS" if passed else "FAIL",absi(second-first),profile[first],profile[second]])
	return passed
