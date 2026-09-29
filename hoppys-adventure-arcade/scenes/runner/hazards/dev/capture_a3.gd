extends SceneTree
## Host-only fixture: every hazard case in the SHIPPING starship corridor (corridor.tscn mounted
## unmodified: its floor grid, walls, lights, environment and retro render scale) seen from the gameplay
## chase camera, plus the art-review measurements (DANGER share, beetle size, diff-screen ink contrast),
## 3-frame motion strips per hazard kind and the pit occlusion proofs.
##   Godot --path . --always-on-top --script res://scenes/runner/hazards/dev/capture_a3.gd [-- --with-gallery --with-a4]
## `--with-gallery` / `--with-a4` batch capture_gallery.gd and capture_a4.gd into this one window.
const Metrics = preload("res://scenes/runner/hazards/visuals/hifi/capture_metrics.gd")
const Check = preload("res://tests/assets/a3_check.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const CORRIDOR = preload("res://scenes/runner/environment/corridor.tscn")
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const A4Job = preload("res://scenes/runner/powerups/dev/capture_a4_job.gd")
const GalleryCapture = preload("res://scenes/runner/hazards/dev/capture_gallery.gd")
## Gameplay camera (runner_game.tscn Camera, run_config.gd camera_position / camera_look_at / fov).
const GAMEPLAY_POSITION := Vector3(0,4,8)
const GAMEPLAY_LOOK_AT := Vector3(0,1,-8)
## Views that keep the gameplay camera and move the hazard this many metres ahead of the player.
## "approach" (pits only): 6 m ahead, where the player judges the jump; the pit-mouth contrast oracle
## assumes an unobstructed mouth, which holds there and at the oblique view, not at a grazing 20 m.
const DISTANCE_VIEWS := {"gameplay": 20.0, "distance40": 40.0, "distance60": 60.0, "approach": 6.0}
const VIEWS := ["gameplay","close","oblique","distance40","distance60"]
const REQUIRED_VIEWS := 16*5+2+4+8
## Art review r1: DANGER-red pixels >= 8% of the screen box at 40 m (enforced on the flagged kinds).
const DANGER_SHARE_MIN := 0.08
const DANGER_GUARDED := ["pr_backlog_low","pr_backlog_high","merge_conflict","comment_flood"]
const INK_CONTRAST_MIN := 0.15
## Unshaded classification of baked hazard texels: code-line ink (bright, low saturation) red, every
## other prop texel green. Raw sRGB texels (no source_color), no fog, no glow.
const INK_MASK_CODE := """shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
uniform sampler2D albedo_atlas : filter_nearest, repeat_disable;
uniform float prop_part = 0.0;
void fragment(){
 vec3 c = texture(albedo_atlas, UV).rgb;
 float hi = max(c.r,max(c.g,c.b));
 float lo = min(c.r,min(c.g,c.b));
 float s = hi > 0.0 ? (hi-lo)/hi : 0.0;
 ALBEDO = prop_part < 0.5 ? vec3(0.0) : ((hi > 0.45 && s < 0.45) ? vec3(0.6,0.0,0.0) : vec3(0.0,0.6,0.0));
}
"""
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
var folder := ""
var _strip_kinds: Dictionary = {}

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

func _settle() -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw

func _capture() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	# The shipping corridor, read-only: no fixture panels, lights, environment or render-scale override.
	var corridor := CORRIDOR.instantiate()
	world.add_child(corridor)
	while not Prewarm.is_complete(): await process_frame
	corridor.set_scroll_speed(0.0)
	corridor._offset = 0.0
	corridor._clock = 0.5
	corridor._process(0.0)
	A4Job.freeze_subtree(corridor)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 60
	camera.near = 0.15
	camera.far = 200.0
	world.add_child(camera)
	camera.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24,24)
	caption.add_theme_font_size_override("font_size",22)
	caption.add_theme_color_override("font_color",Palette.CREAM)
	layer.add_child(caption)
	folder = ProjectSettings.globalize_path("res://../docs/previews/assets")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		printerr("ASSET A3 CAPTURE: FAIL (cannot create output directory)")
		quit(1)
		return
	for entry: Array in Check.CASES:
		var visual := Check.spawn(entry,world)
		visual.set_process(false)
		visual._process(0.18)
		var slug := str(entry[0]) + ("-"+str(entry[1]) if entry[1] != "" else "")
		for view in (VIEWS+["approach"] if entry[0] == "deprecated_pit" else VIEWS):
			_pose(visual,view)
			visual._art.update_view_distance()
			if entry[1] == "timed": visual.set_telegraph(0.75 if view in ["close","distance40","distance60"] else 0.0)
			visual.hide()
			await _settle()
			var baseline := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			var background := root.get_texture().get_image()
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
			if result == OK and entry[0] == "deprecated_pit" and view in ["gameplay","approach","oblique"]:
				if not _check_saved_pit(folder+"/a3-"+slug+"-"+view+".png",visual,slug+"/"+view,view) and view != "gameplay":
					_record_failure("%s/%s pit contrast" % [slug,view])
			print("A3 CAPTURE: %s/%s total_draws=%d asset_delta=%d" % [slug,view,total,total-baseline])
			if view == "distance40" and entry[0] != "projectile":
				await _measure_danger(visual,background,slug)
				if entry[0] == "bug_swarm": _measure_beetles(visual,slug)
			if entry[0] == "merge_conflict" and view in ["close","gameplay"]:
				await _measure_ink(visual,slug,view)
		# One strip per barrier kind; the laser strip shows the timed CHARGING ramp.
		if entry[0] != "projectile" and not _strip_kinds.has(entry[0]) and (entry[0] != "laser_grid" or entry[1] == "timed"):
			await _motion_strip(visual,entry)
		if entry[0] == "deprecated_pit":
			visual.position = Vector3.ZERO
			await _prove_pit_occlusion(visual,folder,slug)
		visual.free()
		await process_frame
	caption.hide()
	world.free()
	world = null
	if OS.get_cmdline_user_args().has("--with-gallery"):
		var gallery_failures: int = await GalleryCapture.capture_into(self,folder)
		if gallery_failures > 0: _record_failure("%d gallery capture failures" % gallery_failures)
	var a3_errors := errors.count
	if OS.get_cmdline_user_args().has("--with-a4"):
		var a4_passed: bool = await A4Job.new(self).capture()
		if not a4_passed: _record_failure("ASSET A4 CAPTURE guards failed")
		# The standalone A4 capture never counted engine errors; report its phase separately.
		print("A4 PHASE ENGINE ERRORS: %d (reported; not an A3 guard)" % (errors.count-a3_errors))
	if a3_errors > 0:
		_record_failure("%d renderer/runtime errors" % a3_errors)
	if saved_views != REQUIRED_VIEWS: _record_failure("saved %d of %d required views" % [saved_views,REQUIRED_VIEWS])
	print("A3 CAPTURE SAVED: %d / %d" % [saved_views,REQUIRED_VIEWS])
	for failure in failures: printerr("A3 CAPTURE FAILURE: "+failure)
	print("ASSET A3 CAPTURE: PASS" if failures.is_empty() else "ASSET A3 CAPTURE: FAIL (%d failures)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _record_failure(message: String) -> void:
	failures.append(message)
	printerr("A3 CAPTURE CHECK: "+message)

func _prove_pit_occlusion(visual: Node3D, out_folder: String, slug: String) -> void:
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
	visual._art.update_view_distance()
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
		if actual.save_png(out_folder+"/a3-"+slug+"-occlusion-"+pose+".png") != OK:
			_record_failure("%s/%s occlusion PNG write" % [slug,pose])
		else:
			saved_views += 1
			var saved_image := Image.load_from_file(out_folder+"/a3-"+slug+"-occlusion-"+pose+".png")
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

## Hazard at the origin framed by the close / oblique cameras, or `distance` metres ahead of the
## player with the camera at the gameplay chase pose.
func _pose(visual: Node3D, view: String) -> void:
	if DISTANCE_VIEWS.has(view):
		visual.position = Vector3(0,0,-float(DISTANCE_VIEWS[view]))
		camera.position = GAMEPLAY_POSITION
		camera.look_at(GAMEPLAY_LOOK_AT)
		return
	visual.position = Vector3.ZERO
	var center: Vector3 = visual.hitbox_offset
	camera.position = center+(Vector3(0,1.3,maxf(2.3,visual.hitbox_size.x*1.02)) if view == "close" else Vector3(3.0,2.6,6.0))
	camera.look_at(center)

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
	print("A3 PIT CONTRAST: %s top=%.6f top_min=%.6f middle=%.6f bottom=%.6f floor_mean=%.6f floor_median=%.6f floor_p90=%.6f mouth=%s %s" % [title,metrics.top,metrics.top_min,metrics.middle,metrics.bottom,metrics.floor,metrics.floor_median,metrics.floor_p90,metrics.mouth_pass,"PASS" if metrics.mouth_pass else "FAIL"])
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

## The shipping corridor's own floor beside the hazard: neither black nor blown out (a broken or
## overexposed capture), with the corridor's calibrated band (Metrics.corridor_exposure).
func _check_exposure(image: Image, visual: Node3D, title: String, extra_bounds: Array[AABB] = []) -> void:
	var reference := _floor_probes(image,visual,extra_bounds)
	var probes: Array[Vector2i] = []
	probes.assign(reference.pixels)
	var measured := Metrics.corridor_exposure(image,probes)
	if probes.size() < 60:
		print("A3 EXPOSURE: %s floor_median=%.6f floor_p90=%.6f probes=%d SKIP (%s)" % [title,measured.median,measured.p90,probes.size(),reference.reason])
		return
	print("A3 EXPOSURE: %s floor_median=%.6f floor_p90=%.6f probes=%d %s" % [title,measured.median,measured.p90,probes.size(),"PASS" if measured.pass else "FAIL"])
	if not measured.pass: _record_failure(title+" corridor floor exposure")

## Every visible batch instance of the rig as [world pose, unit mesh vertices, pivot].
static func _instances(art: Node3D) -> Array:
	var out: Array = []
	for batch: Dictionary in art._batches:
		var vertices: PackedVector3Array = batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in batch.instances.size():
			var pivot: Node3D = batch.instances[i][0]
			if not pivot.is_visible_in_tree(): continue
			out.append([batch.node.global_transform*batch.node.multimesh.get_instance_transform(i),vertices,pivot])
	return out

## Exact screen rectangle of the given instances' vertices.
func _screen_rect(instances: Array) -> Rect2:
	var rect := Rect2()
	var first := true
	for item: Array in instances:
		var world_pose: Transform3D = item[0]
		for point: Vector3 in item[1]:
			var screen := camera.unproject_position(world_pose*point)
			rect = Rect2(screen,Vector2.ZERO) if first else rect.expand(screen)
			first = false
	return rect

## DANGER-red share of the hazard's screen box at 40 m, prop only (floor footprint hidden) and as shown.
func _measure_danger(visual: Node3D, background: Image, slug: String) -> void:
	var art: Node3D = visual._art
	var shown := root.get_texture().get_image()
	var markers: Array[Node3D] = []
	for title in ["FloorMarker","SafeGap"]:
		var marker := art.get_node_or_null(title) as Node3D
		if marker != null and marker.visible:
			marker.hide()
			markers.append(marker)
	caption.hide()
	await _settle()
	var prop := root.get_texture().get_image()
	for marker in markers: marker.show()
	caption.show()
	var rect := Rect2i(_screen_rect(_instances(art)).grow(0.5))
	rect = rect.intersection(Rect2i(Vector2i.ZERO,prop.get_size()))
	var prop_share := Metrics.danger_share(prop,background,rect)
	var shown_share := Metrics.danger_share(shown,background,rect)
	var guarded := String(visual.kind) in DANGER_GUARDED
	var passed := prop_share.x >= DANGER_SHARE_MIN
	print("A3 DANGER 40m: %s box=%s danger_share_of_box=%.3f (prop only) %.3f (with footprint) share_of_hazard_pixels=%.3f target>=%.2f %s" % [slug,rect,prop_share.x,shown_share.x,prop_share.y,DANGER_SHARE_MIN,("PASS" if passed else "FAIL") if guarded else ("reported, "+("meets" if passed else "below")+" target")])
	if guarded and not passed: _record_failure("%s DANGER share %.3f below %.2f at 40 m" % [slug,prop_share.x,DANGER_SHARE_MIN])

## Width in pixels of each beetle (all of its body and wing vertices) and of the swarm at 40 m.
func _measure_beetles(visual: Node3D, slug: String) -> void:
	var art: Node3D = visual._art
	var all := _instances(art)
	var widths: Array[String] = []
	for bug: Node in art.body.get_children():
		if not String(bug.name).begins_with("Bug"): continue
		var own: Array = []
		for item: Array in all:
			if bug.is_ancestor_of(item[2]): own.append(item)
		var rect := _screen_rect(own)
		widths.append("%s=%.1fx%.1fpx" % [bug.name,rect.size.x,rect.size.y])
	var swarm := _screen_rect(all)
	print("A3 BEETLES 40m: %s %s swarm=%.1fx%.1fpx (review target 24 px per beetle)" % [slug," ".join(widths),swarm.size.x,swarm.size.y])

## Diff-screen code-line ink against its own slab: an unshaded texel-classification pass marks ink
## (red) and slab (green) pixels; contrast is the lit luminance difference inside each screen.
func _measure_ink(visual: Node3D, slug: String, view: String) -> void:
	var art: Node3D = visual._art
	var lit := root.get_texture().get_image()
	var shader := Shader.new()
	shader.code = INK_MASK_CODE
	var saved: Array = []
	for batch: Dictionary in art._batches:
		saved.append(batch.node.material_override)
		var material := ShaderMaterial.new()
		material.shader = shader
		# Only baked prop texels classify; label backings and energy pieces are excluded (black).
		if batch.material.shader == art.Prop:
			material.set_shader_parameter("albedo_atlas",batch.material.get_shader_parameter("albedo_atlas"))
			material.set_shader_parameter("prop_part",1.0)
		batch.node.material_override = material
	var hidden: Array[Node3D] = []
	var toggles: Array[Node3D] = []
	toggles.append_array(art._labels)
	if art.get_node_or_null("FloorMarker") != null: toggles.append(art.get_node("FloorMarker"))
	for node in toggles:
		if node.visible:
			node.hide()
			hidden.append(node)
	caption.hide()
	await _settle()
	var mask := root.get_texture().get_image()
	for i in art._batches.size(): art._batches[i].node.material_override = saved[i]
	for node in hidden: node.show()
	caption.show()
	mask.save_png(folder+"/a3-"+slug+"-"+view+"-inkmask.png")
	var labels: Array[Rect2] = []
	for label: Label3D in art._labels:
		var box: AABB = label.global_transform*label.get_aabb()
		var rect := Rect2(camera.unproject_position(box.position),Vector2.ZERO)
		for i in 8: rect = rect.expand(camera.unproject_position(box.get_endpoint(i)))
		labels.append(rect.grow(2.0))
	for half in ["Ours0","Theirs0"]:
		var pivot := art.body.get_node_or_null(half) as Node3D
		if pivot == null:
			_record_failure("%s missing %s half" % [slug,half])
			continue
		var s := 1.0 if half == "Ours0" else -1.0
		var screen := Rect2(camera.unproject_position(pivot.to_global(Vector3(-0.06*s-0.68,-0.28,0.238))),Vector2.ZERO)
		for corner in [Vector3(-0.06*s+0.68,-0.28,0.238),Vector3(-0.06*s-0.68,0.24,0.238),Vector3(-0.06*s+0.68,0.24,0.238)]:
			screen = screen.expand(camera.unproject_position(pivot.to_global(corner)))
		var result := Metrics.ink_contrast(lit,mask,Rect2i(screen.grow(-2.0)),labels,view == "close")
		var passed: bool = result.ink >= 20 and result.slab >= 20 and result.contrast >= INK_CONTRAST_MIN
		var enforce := view == "close"
		print("A3 INK CONTRAST: %s/%s %s ink_luminance=%.3f slab_luminance=%.3f contrast=%.3f ink_px=%d slab_px=%d target>=%.2f %s" % [slug,view,half.trim_suffix("0"),result.ink_luminance,result.slab_luminance,result.contrast,result.ink,result.slab,INK_CONTRAST_MIN,("PASS" if passed else "FAIL") if enforce else ("reported, "+("meets" if passed else "below")+" target")])
		if enforce and not passed: _record_failure("%s/%s %s ink contrast %.3f" % [slug,view,half,result.contrast])

## Three frames of each kind's idle motion from the gameplay camera, cropped around the hazard and laid
## side by side (crate shudder, scanner sweep, bug flutter, slab grind, pit seams, laser charge, card
## flutter, debris spin). Prints the mean per-pixel change between consecutive frames.
func _motion_strip(visual: Node3D, entry: Array) -> void:
	var kind := String(entry[0])
	_strip_kinds[kind] = true
	visual.position = Vector3(0,0,-10.0 if kind != "comment_flood" else -14.0)
	camera.position = GAMEPLAY_POSITION
	camera.look_at(GAMEPLAY_LOOK_AT)
	visual._art.update_view_distance()
	caption.hide()
	var frames: Array[Image] = []
	var crop := Rect2i()
	for frame in 3:
		if entry[1] == "timed": visual.set_telegraph(0.25+0.25*frame)
		visual._process(0.0 if frame == 0 else 0.35)
		visual._art._update_batches()
		await _settle()
		var image := root.get_texture().get_image()
		if frame == 0:
			crop = Rect2i(_screen_rect(_instances(visual._art)).grow(24.0)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		frames.append(image.get_region(crop))
	caption.show()
	var height := 240
	var width := maxi(1,int(float(crop.size.x)*height/maxf(1.0,crop.size.y)))
	var strip := Image.create(width*3+16,height,false,Image.FORMAT_RGBA8)
	strip.fill(Palette.NAVY_BG)
	var deltas: Array[String] = []
	for i in 3:
		if i > 0: deltas.append("%.4f" % Metrics.mean_delta(frames[i-1],frames[i]))
		var scaled := frames[i].duplicate() as Image
		scaled.convert(Image.FORMAT_RGBA8)
		scaled.resize(width,height,Image.INTERPOLATE_BILINEAR)
		strip.blit_rect(scaled,Rect2i(Vector2i.ZERO,scaled.get_size()),Vector2i(i*(width+8),0))
	var path := folder+"/a3-strip-"+kind+".png"
	if strip.save_png(path) != OK: _record_failure(kind+" motion strip PNG write")
	else: saved_views += 1
	if entry[1] == "timed": visual.set_telegraph(0.0)
	print("A3 MOTION STRIP: %s frames=3 dt=0.35s crop=%s mean_change=%s" % [kind,crop,",".join(deltas)])
