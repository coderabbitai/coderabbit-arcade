extends SceneTree
## Coordinator-only capture. No screenshots or graphical scenes run by the asset agent.
const Raster = preload("res://scenes/runner/ui/hifi/portrait_raster_check.gd")
var fixture: Node
var output := ""
var menu: Node
const CLOSEUP_SIZE := Vector2(420, 196)
const CLOSEUP_SCALE := Vector2(2, 2)

static func frame_closeup(alert: Control) -> void:
	alert.set_anchors_preset(Control.PRESET_TOP_LEFT)
	alert.offset_left = 220
	alert.offset_top = 160
	alert.offset_right = 220 + CLOSEUP_SIZE.x
	alert.offset_bottom = 160 + CLOSEUP_SIZE.y
	alert.scale = CLOSEUP_SCALE
	alert.set_process(false)

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("ASSET A7 CAPTURE: FAIL (requires graphical renderer)")
		shutdown.call_deferred(1)
		return
	run.call_deferred()
func shot(view: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output.path_join("a7-" + view + ".png")
	if image.save_png(path) != OK:
		printerr("ASSET A7 CAPTURE: FAIL (write " + path + ")")
		await shutdown(1)
		return false
	var canvas_draws := root.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var scene_draws := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	print("A7 CAPTURE %s: canvas draw calls=%d; scene draw calls=%d" % [view, canvas_draws, scene_draws])
	if is_instance_valid(fixture) and "hud" in fixture:
		print("A7 portrait viewport draw calls=", fixture.hud.pursuit_alert.portrait_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
	return true
func run() -> void:
	root.size = Vector2i(1280, 720)
	output = ProjectSettings.globalize_path("res://../docs/previews/assets")
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("ASSET A7 CAPTURE: FAIL (output directory)")
		await shutdown(1)
		return
	fixture = load("res://scenes/runner/ui/dev/hud_preview.tscn").instantiate()
	fixture.autoplay = false
	root.add_child(fixture)
	fixture.start_run()
	fixture.hud._process(3.0)
	seed_capture_values(fixture)
	fixture.collect(&"nitro", 8.0)
	fixture.collect(&"approve_shield", 0.0)
	fixture.pursuit_started.emit(18.0)
	fixture.pursuit_progress.emit(6.5, 18.0)
	fixture.hud.pursuit_alert._process(0.4)
	fixture.boss_hp = 140
	fixture.boss_spawned.emit(fixture.boss_kind, 140)
	fixture.boss_health_changed.emit(82, 140)
	fixture.boss_phase_changed.emit(2)
	await create_timer(0.7).timeout
	if not await verify_portrait_pixels(): return
	if not await shot("gameplay"): return
	fixture.boss_intro.emit(fixture.boss_kind, "Merge Conflict Hydra", 3.0)
	fixture.boss_overlay._process(1.2)
	if not await shot("boss-intro"): return
	fixture.boss_overlay._process(3.0)
	fixture.turn_incoming.emit(1, 3.0)
	fixture.hud._process(0.2)
	if not await shot("turn-warning"): return
	fixture.turn_finished.emit()

	fixture.boss_overlay.hide()
	fixture.hud.widgets.hide()
	# The v1 fixture owns its alert under widgets; move to a dedicated layer for close-up.
	var alert: Control = fixture.hud.pursuit_alert
	alert.reparent(fixture.hud)
	frame_closeup(alert)
	if not await shot("portrait-closeup"): return
	alert.hide()
	fixture.phase_changed.emit(&"run")
	fixture.stage_started.emit(2, &"Merge Conflict Hydra", 26.0)
	fixture.stage_banner._process(0.6)
	if not await shot("stage-banner"): return
	fixture.stage_banner.hide()
	seed_stage_values(fixture)
	fixture.stage_cleared.emit(2, 550)
	fixture.stage_clear._process(0.6)
	if not await shot("stage-clear"): return
	fixture.stage_clear.hide()
	fixture.finish_demo()
	await create_timer(1.0).timeout
	if not await shot("results"): return
	fixture.game_over.hide()
	fixture.state = &"running"
	fixture.pause()
	if not await shot("pause"): return
	fixture.free()
	fixture = null
	await process_frame
	menu = load("res://scenes/runner/runner_menu.tscn").instantiate() as Node
	root.add_child(menu)
	await create_timer(0.3).timeout
	if not await shot("menu"): return
	menu._toggle_leaderboard()
	if not await shot("leaderboard"): return
	await shutdown(0)

func shutdown(code: int) -> void:
	if is_instance_valid(fixture): fixture.free()
	fixture = null
	if is_instance_valid(menu): menu.free()
	menu = null
	var audio_service := root.get_node_or_null("AudioService")
	if audio_service != null and audio_service.has_method("shutdown"):
		audio_service.shutdown()
	# Autoload audio can retain playback resources after the preview nodes are freed.
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
	if code == 0: print("ASSET A7 CAPTURE: PASS")
	quit(code)

func verify_portrait_pixels() -> bool:
	var viewport: SubViewport = fixture.hud.pursuit_alert.portrait_viewport
	var scan := viewport.get_child(2) as ColorRect
	# Test raw lettering so chromatic scanline movement cannot disguise block glyphs.
	scan.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var result := Raster.inspect(viewport.get_texture().get_image())
	scan.show()
	await process_frame
	await RenderingServer.frame_post_draw
	# Inspect the shader-composited image too; raw lettering alone misses RGB artifacts.
	var palette := Raster.inspect_palette(viewport.get_texture().get_image())
	print("A7 PORTRAIT PALETTE: ", palette)
	if not palette.passed:
		printerr("ASSET A7 CAPTURE: FAIL (portrait off-palette pixels)")
		await shutdown(1)
		return false
	print("A7 PORTRAIT RASTER: ", result)
	if not result.passed:
		printerr("ASSET A7 CAPTURE: FAIL (portrait glyph raster)")
		await shutdown(1)
		return false
	return true

static func seed_capture_values(mock: Node) -> void:
	mock.score = 12840
	mock.elapsed = 83.4
	mock.distance = 1856.0
	mock.score_changed.emit(mock.score, 1.5)
	mock.hud._process(0.0)

static func seed_stage_values(mock: Node) -> void:
	mock.elapsed += 37.2
	for tool in [&"review_comment", &"unit_test", &"lint_rule"]:
		mock.tool_collected.emit(tool, 10)
