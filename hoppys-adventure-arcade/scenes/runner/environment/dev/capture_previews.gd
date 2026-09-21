extends SceneTree
## Run non-headless from the repository root. Captures F0-F9 visual fixtures.
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
	for fixture in ["renderer_spike", "corridor_preview", "hoppy_preview", "hazard_gallery", "runner_menu"]:
		var directory := "player" if fixture == "hoppy_preview" else "environment"
		if fixture == "hazard_gallery":
			directory = "hazards/visuals"
		var path := "res://scenes/runner/runner_menu.tscn" if fixture == "runner_menu" else "res://scenes/runner/%s/dev/%s.tscn" % [directory, fixture]
		var scene := load(path) as PackedScene
		if scene == null:
			push_error("PREVIEW CAPTURE: fixture failed to load: " + fixture)
			failures += 1
			continue
		var instance := scene.instantiate()
		root.add_child(instance)
		await create_timer(1.5 if fixture == "hoppy_preview" else 1.0).timeout
		await RenderingServer.frame_post_draw
		var suffix: String = {"renderer_spike": "spike", "corridor_preview": "corridor", "hoppy_preview": "hoppy", "hazard_gallery": "gallery", "runner_menu": "menu"}[fixture]
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
			print("CORRIDOR DRAW BUDGET: ", calls, " / 14 (preview UI hidden)")
			if calls > 14:
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
	var bosses := preload("res://scenes/runner/boss/dev/boss_gallery.tscn").instantiate()
	root.add_child(bosses)
	bosses.animate = false
	for i in 3:
		bosses.capture_boss(i)
		await create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		var suffix: String = ["swarm", "hydra", "monolith"][i]
		var output := ProjectSettings.globalize_path("res://../docs/previews/endless-runner-boss-%s.png" % suffix)
		var error := root.get_texture().get_image().save_png(output)
		var calls := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		print("CAPTURE: boss-", suffix, " error=", error, " draw_calls=", calls)
		# Contract has four projectile variants, so reserve four slots in the 184 budget.
		print("BOSS GALLERY DRAW BUDGET: ", calls, " / 184")
		if error != OK or calls > 184: failures += 1
	bosses.free()
	await process_frame
	var turn := preload("res://scenes/runner/environment/dev/turn_preview.tscn").instantiate()
	root.add_child(turn)
	turn.progress = 0.5
	turn.corridor.set_turn(0.5, 1)
	for child in turn.get_children():
		if child is CanvasLayer: child.hide()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var turn_calls := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var turn_error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../docs/previews/endless-runner-turn.png"))
	print("CAPTURE: turn error=", turn_error, " draw_calls=", turn_calls)
	print("TURN DRAW BUDGET: ", turn_calls, " / 18 (preview UI hidden)")
	if turn_error != OK or turn_calls > 18: failures += 1
	turn.free()
	await process_frame
	var clear := (load("res://scenes/runner/ui/dev/hud_preview.tscn") as PackedScene).instantiate()
	clear.autoplay = false
	root.add_child(clear)
	clear.start_run()
	clear.stage_banner.hide()
	clear.hud.ready_panel.hide()
	clear.set_demo_phase(&"stage_clear")
	clear.elapsed = 48.2
	clear.stage_index = 2
	clear.stage_clear.tools = 14
	clear.stage_cleared.emit(2, 2500)
	clear.stage_clear._process(0.5)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var clear_error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../docs/previews/endless-runner-stage-clear.png"))
	print("CAPTURE: stage-clear error=", clear_error)
	if clear_error != OK: failures += 1
	clear.free()
	await process_frame
	root.get_node("AudioService").shutdown()
	await create_timer(0.3).timeout
	print("PREVIEW CAPTURE: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
