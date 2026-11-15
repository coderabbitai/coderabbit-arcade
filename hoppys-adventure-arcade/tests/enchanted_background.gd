extends SceneTree
## Check coverage along the full route; the rendered run also checks blend opacity
## with a constant-color fixture and captures every traversal section for review.
const ForestArt = preload("res://modes/platformer/enchanted_art.gd")
const PREVIEWS := "res://../docs/previews/enchanted-repo/"
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func check_blend() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 540)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var strip := ForestArt.treeline()
	var fixture := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	fixture.fill(Color(.2, .3, .4, .8))
	strip.texture = ImageTexture.create_from_image(fixture)
	strip.position = Vector2.ZERO
	strip.scale = Vector2(1280.0 / 960.0, 1)
	viewport.add_child(strip)
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	var reference := pixels.get_pixel(640, 200)
	var uniform := true
	for x in 1280:
		var pixel := pixels.get_pixel(x, 200)
		if absf(pixel.r-reference.r)>.005 or absf(pixel.g-reference.g)>.005 or absf(pixel.b-reference.b)>.005 or absf(pixel.a-reference.a)>.005:
			uniform = false
	check(uniform, "All repeated joins preserve constant color and opacity")
	check(absf(reference.a - .8*.62)<.01, "Treeline opacity is applied once, including overlap")
	check(pixels.get_pixel(640,539).a<.01, "Lower edge fades to transparent over floor gaps")
	viewport.queue_free()
	await process_frame

func run() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		await check_blend()
	change_scene_to_file("res://scenes/platformer/enchanted_repo.tscn")
	await process_frame
	await process_frame
	var level = current_scene
	# These are camera inspections, so stop gameplay without pausing the renderer.
	for node in level.find_children("*", "Node", true, false):
		node.set_physics_process(false)
	level.set_physics_process(false)
	level.camera.position_smoothing_enabled = false
	var strip: Sprite2D = level.find_child("ContinuousTreeline", true, false)
	check(strip != null, "Level uses the continuous treeline")
	check(strip.get_parent().get_child_count()==1, "No overlapping background sprites remain")
	for x in [150, 900, 1600, 2300, 3000, 3700, 4400, 5150]:
		level.player.position = Vector2(x, 600)
		level.player.reset_physics_interpolation()
		level.camera.reset_smoothing()
		level.camera.force_update_scroll()
		level._resume()
		await process_frame
		await process_frame
		var rect: Rect2 = strip.get_global_transform_with_canvas() * strip.get_rect()
		check(rect.position.x<=0 and rect.end.x>=root.get_visible_rect().size.x, "Background covers viewport at route x=%d"%x)
		if rendered:
			level._resume()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(PREVIEWS+"background-%04d.png"%x)
	level.queue_free()
	await process_frame
	await root.get_node("AudioService").settle()
	print("Enchanted background failures: ", failures)
	quit(0 if failures==0 else 1)
