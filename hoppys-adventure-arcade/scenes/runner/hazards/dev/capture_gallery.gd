extends SceneTree
## Host-only fixture: the shipped hazard gallery (all twelve hazard cases, the six power-ups, the
## pursuer) in the shipping corridor, framed at the gameplay chase camera, one PNG per fixture plus the
## draw census per view, and the build shockwave again from 20 m and 40 m (nothing between it and the
## camera: the gallery hides every fixture in front of the one it frames).
##   Godot --path . --always-on-top --script res://scenes/runner/hazards/dev/capture_gallery.gd
## capture_a3.gd `-- --with-gallery` runs the same capture in its window (capture_into).
const Gallery = preload("res://scenes/runner/hazards/visuals/dev/hazard_gallery.gd")
const REQUIRED := 21
const SHOCKWAVE_DISTANCES := [20.0,40.0]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"): audio.shutdown()
	if DisplayServer.get_name() == "headless":
		printerr("A3 GALLERY CAPTURE: FAIL (graphical display required)")
		quit(1)
		return
	var folder := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(folder)
	var failures: int = await capture_into(self,folder)
	quit(0 if failures == 0 else 1)

## Captures every gallery fixture into `folder`; returns the failure count.
static func capture_into(tree: SceneTree, folder: String) -> int:
	var failures := 0
	tree.root.size = Vector2i(1280,720)
	var gallery: Node = (load("res://scenes/runner/hazards/visuals/dev/hazard_gallery.tscn") as PackedScene).instantiate()
	tree.root.add_child(gallery)
	await tree.create_timer(1.0).timeout
	var saved := 0
	var shots: Array = []
	for index in gallery.fixtures.size(): shots.append([index,0.0])
	var shockwave := Gallery.CASES.size()-1
	for distance: float in SHOCKWAVE_DISTANCES: shots.append([shockwave,distance])
	for shot: Array in shots:
		var index: int = shot[0]
		var distance: float = shot[1]
		gallery._selected = index
		gallery.frame(index,distance)
		for frame in 6: await tree.process_frame
		await RenderingServer.frame_post_draw
		var slug := "pursuer"
		if index < Gallery.CASES.size():
			var entry: Array = Gallery.CASES[index]
			slug = String(entry[0]) + ("-"+String(entry[1]) if entry[1] != &"" else "")
		elif index < Gallery.CASES.size()+Gallery.POWERUPS.size():
			slug = String(Gallery.POWERUPS[index-Gallery.CASES.size()])
		if distance > 0.0: slug += "-%dm" % int(distance)
		var path := folder+"/a3-gallery-%02d-%s.png" % [index,slug]
		var error := tree.root.get_texture().get_image().save_png(path)
		var draws := tree.root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var blockers: int = gallery.occluders(index,distance)
		print("A3 GALLERY: %02d %s error=%d draw_calls=%d fixtures_between_camera_and_target=%d" % [index,slug,error,draws,blockers])
		if blockers > 0: failures += 1
		if error == OK: saved += 1
		else: failures += 1
	gallery.free()
	await tree.process_frame
	print("A3 GALLERY SAVED: %d / %d" % [saved,REQUIRED])
	if saved != REQUIRED: failures += 1
	print("A3 GALLERY CAPTURE: %s" % ("PASS" if failures == 0 else "FAIL"))
	return failures
