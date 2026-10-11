extends SceneTree
## Coordinator-only graphical capture. Never accepts a headless renderer.
const Prewarm = preload("res://scenes/runner/environment/hifi/prewarm.gd")
const Cleanup = preload("res://scenes/runner/environment/hifi/fixture_cleanup.gd")
const Metrics = preload("res://scenes/runner/environment/hifi/capture_metrics.gd")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A2 CAPTURE: requires graphical display")
		await Cleanup.release(self, [])
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var corridor := Corridor.instantiate()
	root.add_child(corridor)
	while not Prewarm.is_complete(): await process_frame
	corridor.set_scroll_speed(24.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 60
	var output := ProjectSettings.globalize_path("res://../docs/previews/assets")
	DirAccess.make_dir_recursive_absolute(output)
	var failures := 0
	for view in ["gameplay", "close-up"]:
		# Freeze a repeatable module phase so the near frame-face ROI cannot drift off hardware.
		corridor.set_process(false)
		corridor._offset = 6.4 if view == "close-up" else 0.0
		corridor._clock = 1.0
		corridor._process(0.0)
		var eye := Vector3(0, 4, 8)
		var target := Vector3(0, 1, -8)
		if view == "close-up":
			eye = Vector3(1.6, 3.3, 0)
			target = Vector3(3.94, 3.0, -4.0)
		camera.position = corridor.transform * eye
		camera.look_at(corridor.transform * target)
		await create_timer(0.8).timeout
		corridor.set_process(false)
		await RenderingServer.frame_post_draw
		var calls := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var error := root.get_texture().get_image().save_png(output + "/a2-" + view + ".png")
		print("ASSET A2 CAPTURE: %s draw_calls=%d save_error=%d" % [view, calls, error])
		if view == "close-up" and error == OK:
			var saved := Image.load_from_file(output + "/a2-close-up.png")
			var stats := Metrics.restored_frame_stats(saved)
			print("ASSET A2 FRAME: rect=%s mean=%.3f std=%.3f lit_fraction=%.3f %s" % [Metrics.FRAME_REGION, stats.mean, stats.std, stats.lit_fraction, "PASS" if stats["pass"] else "FAIL"])
			if not stats["pass"]: failures += 1
			var detail := Metrics.wall_stats(saved)
			print("ASSET A2 WALL-DETAIL: rect=%s detail=%.3f edge_density=%.4f mean=%.3f std=%.3f dark_fraction=%.3f dx=%.3f dy=%.3f axis_ratio=%.3f %s" % [Metrics.WALL_DETAIL_REGION, detail.detail, detail.edge_density, detail.mean, detail.std, detail.dark_fraction, detail.dx, detail.dy, detail.axis_ratio, "PASS" if detail["pass"] else "FAIL"])
			if not detail["pass"]: failures += 1
		if view == "gameplay" and error == OK:
			var saved := Image.load_from_file(output + "/a2-gameplay.png")
			var stats := Metrics.floor_stats(saved)
			print("ASSET A2 FLOOR: mean=%.3f std=%.3f lit_fraction=%.3f detail=%.3f %s" % [stats.mean, stats.std, stats.lit_fraction, stats.detail, "PASS" if stats["pass"] else "FAIL"])
			if not stats["pass"]: failures += 1
			var ceiling := Metrics.ceiling_stats(saved)
			print("ASSET A2 CEILING: mean=%.3f %s" % [ceiling.mean, "PASS" if ceiling["pass"] else "FAIL"])
			if not ceiling["pass"]: failures += 1
		if view in ["close-up", "gameplay"] and error == OK:
			var saved := Image.load_from_file(output + "/a2-" + view + ".png")
			var region: Rect2i = Metrics.SCREEN_REGION if view == "close-up" else Metrics.GAMEPLAY_SCREEN_REGION
			var ink := Metrics.screen_stats(saved, region)
			print("ASSET A2 SCREEN-INK: view=%s rect=%s p95=%.3f edge=%.3f %s" % [view, region, ink.p95, ink.edge, "PASS" if ink["pass"] else "FAIL"])
			if not ink["pass"]: failures += 1
		if error != OK or calls > 14: failures += 1

	await Cleanup.release(self, [corridor, camera])
	print("ASSET A2 CAPTURE: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
