extends SceneTree
## Run non-headless from the repository root. Captures F0/F1/F2/F3/F4 visual fixtures.
const Gallery = preload("res://scenes/runner/hazards/visuals/dev/hazard_gallery.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PREVIEW CAPTURE: requires a graphical display; no images written")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	for fixture in ["renderer_spike", "corridor_preview", "hoppy_preview", "hazard_gallery"]:
		var directory := "player" if fixture == "hoppy_preview" else "environment"
		if fixture == "hazard_gallery":
			directory = "hazards/visuals"
		var scene := load("res://scenes/runner/%s/dev/%s.tscn" % [directory, fixture]) as PackedScene
		if scene == null:
			push_error("PREVIEW CAPTURE: fixture failed to load: " + fixture)
			failures += 1
			continue
		var instance := scene.instantiate()
		root.add_child(instance)
		await create_timer(1.5 if fixture == "hoppy_preview" else 1.0).timeout
		await RenderingServer.frame_post_draw
		var suffix: String = {"renderer_spike": "spike", "corridor_preview": "corridor", "hoppy_preview": "hoppy", "hazard_gallery": "gallery"}[fixture]
		var output := ProjectSettings.globalize_path("res://../docs/previews/endless-runner-%s.png" % suffix)
		var error := root.get_texture().get_image().save_png(output)
		if error != OK:
			failures += 1
		var draw_calls := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		print("CAPTURE: ", suffix, " error=", error, " draw_calls=", draw_calls)
		if fixture == "hazard_gallery":
			var gallery_budget := (Gallery.CASES.size() + Gallery.POWERUPS.size() + 1) * 14 + 15
			print("GALLERY DRAW BUDGET: ", draw_calls, " / ", gallery_budget)
			if draw_calls > gallery_budget:
				failures += 1
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
	var hud_scene := load("res://scenes/runner/ui/dev/hud_preview.tscn") as PackedScene
	if hud_scene == null:
		push_error("PREVIEW CAPTURE: fixture failed to load: hud_preview (HUD/game-over captures skipped)")
		failures += 1
	else:
		var hud_preview := hud_scene.instantiate()
		hud_preview.autoplay = false
		root.add_child(hud_preview)
		for target in [16.0, 40.5]:
			while hud_preview.demo_time < target and hud_preview.state != &"finished":
				hud_preview.advance_demo(0.1)
				hud_preview.hud._process(0.1)
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			var suffix := "hud" if target < 40 else "gameover"
			var output := ProjectSettings.globalize_path("res://../docs/previews/endless-runner-%s.png" % suffix)
			var error := root.get_texture().get_image().save_png(output)
			print("CAPTURE: ", suffix, " error=", error)
			if error != OK:
				failures += 1
		hud_preview.free()
		await process_frame
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	print("PREVIEW CAPTURE: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
