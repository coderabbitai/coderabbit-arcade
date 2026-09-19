extends SceneTree
## Run non-headless from the repository root. Captures both F0/F1 fixtures.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PREVIEW CAPTURE: requires a graphical display; no images written")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	for fixture in ["renderer_spike", "corridor_preview"]:
		var scene := load("res://scenes/runner/environment/dev/%s.tscn" % fixture) as PackedScene
		var instance := scene.instantiate()
		root.add_child(instance)
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		var suffix := "spike" if fixture == "renderer_spike" else "corridor"
		var output := ProjectSettings.globalize_path("res://../docs/previews/endless-runner-%s.png" % suffix)
		var error := root.get_texture().get_image().save_png(output)
		if error != OK:
			failures += 1
		print("CAPTURE: ", suffix, " error=", error, " draw_calls=", root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		if fixture == "corridor_preview":
			instance._corridor.set_scroll_speed(26.0)
			await create_timer(1.0).timeout
			for child in instance.get_children():
				if child is CanvasLayer:
					child.hide()
			await RenderingServer.frame_post_draw
			var calls := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			print("CORRIDOR DRAW BUDGET: ", calls, " / 15 (preview UI hidden)")
			if calls > 15:
				failures += 1
		instance.free()
		await process_frame
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	print("PREVIEW CAPTURE: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
