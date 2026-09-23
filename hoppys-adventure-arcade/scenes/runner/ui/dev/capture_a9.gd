extends SceneTree
## Host only. Measures paired frozen frames with and without the single post draw.
const Metrics = preload("res://scenes/runner/ui/dev/post_fx_capture_metrics.gd")
const Preview = preload("res://scenes/runner/ui/dev/post_fx_preview.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func _settle() -> void:
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("ASSET A9 CAPTURE: FAIL (requires graphical display; no images written)")
		if root.has_node("AudioService"):
			root.get_node("AudioService").shutdown()
		await create_timer(0.3).timeout
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var directory := ProjectSettings.globalize_path("res://../docs/previews/assets")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		quit(1)
		return
	var fixture := Preview.instantiate()
	root.add_child(fixture)
	var count := Metrics.canvas_items(fixture.post)
	print("ASSET A9 CAPTURE: post_canvas_items=%d expected=1" % count)
	if count != 1:
		failures += 1
	var names := ["gameplay", "close-up-nitro", "pursuit", "boss-intro", "stage-clear"]
	for index in names.size():
		fixture.set_view(index)
		await create_timer(0.45).timeout
		paused = true
		fixture.post.hide()
		await _settle()
		var before := root.get_texture().get_image()
		fixture.post.show()
		await _settle()
		var after := root.get_texture().get_image()
		var delta := Metrics.pixel_delta(before, after)
		var error := after.save_png(directory.path_join("a9-%s.png" % names[index]))
		# This is a 3D backdrop counter only, never a post-draw measurement.
		var backdrop_calls := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		print("ASSET A9 CAPTURE: %s backdrop_3d_draw_calls=%d changed_pixels=%d mean_rgb_delta=%.4f max_rgb_delta=%d save_error=%d" % [names[index], backdrop_calls, delta.changed_pixels, delta.mean_rgb_delta, delta.max_rgb_delta, error])
		if error != OK or not Metrics.has_visible_delta(delta):
			failures += 1
		paused = false
	# One frozen scene and camera, with ONLY grade toggled. No grain/motion confound.
	fixture.set_view(5)
	await create_timer(0.45).timeout
	paused = true
	await _settle()
	var grade_off := root.get_texture().get_image()
	var off_error := grade_off.save_png(directory.path_join("a9-grade-off.png"))
	fixture.post.set_settings({"grade": true})
	await _settle()
	var grade_on := root.get_texture().get_image()
	var on_error := grade_on.save_png(directory.path_join("a9-grade-on.png"))
	var grade_delta := Metrics.pixel_delta(grade_off, grade_on)
	print("ASSET A9 CAPTURE: grade-off/grade-on changed_pixels=%d mean_rgb_delta=%.4f max_rgb_delta=%d save_errors=%d,%d" % [grade_delta.changed_pixels, grade_delta.mean_rgb_delta, grade_delta.max_rgb_delta, off_error, on_error])
	if off_error != OK or on_error != OK or not Metrics.has_visible_delta(grade_delta):
		failures += 1
	paused = false
	fixture.free()
	if root.has_node("AudioService"):
		root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	print("ASSET A9 CAPTURE: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
