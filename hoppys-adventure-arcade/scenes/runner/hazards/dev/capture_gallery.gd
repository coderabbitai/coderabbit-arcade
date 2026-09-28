extends SceneTree
## Host-only fixture: the shipped hazard gallery (all twelve hazard cases, the six power-ups, the
## pursuer) framed at the contract camera, one PNG per fixture plus the draw census per view.
##   Godot --path . --always-on-top --script res://scenes/runner/hazards/dev/capture_gallery.gd
const Gallery = preload("res://scenes/runner/hazards/visuals/dev/hazard_gallery.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var audio := root.get_node_or_null("AudioService")
	if audio != null and audio.has_method("shutdown"): audio.shutdown()
	if DisplayServer.get_name() == "headless":
		printerr("A3 GALLERY CAPTURE: FAIL (graphical display required)")
		quit(1)
		return
	root.size = Vector2i(1280,720)
	var folder := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(folder)
	var gallery: Node = (load("res://scenes/runner/hazards/visuals/dev/hazard_gallery.tscn") as PackedScene).instantiate()
	root.add_child(gallery)
	await create_timer(1.0).timeout
	var saved := 0
	for index in gallery.fixtures.size():
		gallery._selected = index
		gallery._focus()
		for frame in 6: await process_frame
		await RenderingServer.frame_post_draw
		var slug := "pursuer"
		if index < Gallery.CASES.size():
			var entry: Array = Gallery.CASES[index]
			slug = String(entry[0]) + ("-"+String(entry[1]) if entry[1] != &"" else "")
		elif index < Gallery.CASES.size()+Gallery.POWERUPS.size():
			slug = String(Gallery.POWERUPS[index-Gallery.CASES.size()])
		var path := folder+"/a3-gallery-%02d-%s.png" % [index,slug]
		var error := root.get_texture().get_image().save_png(path)
		var draws := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		print("A3 GALLERY: %02d %s error=%d draw_calls=%d" % [index,slug,error,draws])
		if error == OK: saved += 1
		else: failures += 1
	gallery.free()
	await process_frame
	print("A3 GALLERY SAVED: %d / 19" % saved)
	if saved != 19: failures += 1
	print("A3 GALLERY CAPTURE: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
