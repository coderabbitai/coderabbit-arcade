extends SceneTree
const Mock = preload("res://scenes/runner/ui/dev/mock_runner_game.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Alert = preload("res://scenes/runner/ui/pursuit_alert.gd")
const Pursuer = preload("res://scenes/runner/pursuer/pursuer_visual.gd")
const Finish = preload("res://scenes/runner/ui/hifi/panel_finish.gd")
const Glyph = preload("res://scenes/runner/ui/hifi/utility_glyph.gd")
const Tally = preload("res://scenes/runner/ui/hifi/result_tally.gd")
const Raster = preload("res://scenes/runner/ui/hifi/portrait_raster_check.gd")
const Capture = preload("res://scenes/runner/ui/dev/capture_a7.gd")
const Style = preload("res://scenes/runner/ui/hud_style.gd")
class ErrorCapture extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING: count += 1
var logger := ErrorCapture.new()
var checks := 0
var failures := 0
var canvas_items := 0
var mesh_triangles := 0
var draws_3d := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A7: " + message)
func frames() -> void:
	await process_frame
	await process_frame
func census(node: Node) -> void:
	if node is CanvasItem: canvas_items += 1
	if node is CollisionObject3D: check(false, "UI must not add gameplay hitboxes")
	if node is MeshInstance3D:
		draws_3d += 1
		if node.mesh != null:
			mesh_triangles += node.mesh.get_faces().size() / 3
	if node is MultiMeshInstance3D:
		draws_3d += 1
		check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "cosmetic MultiMesh interpolation")
	if node is GPUParticles3D: check(node.amount <= 64, "particle budget")
	if node is Label:
		check(node.get_theme_font_size("font_size") >= 18, "font >=18: " + node.text)
		check(node.get_theme_constant("outline_size") >= 6, "outline >=6: " + node.text)
		var parent := node.get_parent()
		while parent != null and not parent is PanelContainer: parent = parent.get_parent()
		check(parent != null, "panel backing: " + node.text)
	if node.name == "PanelFinish":
		check(node.process_mode == Node.PROCESS_MODE_PAUSABLE, "panel motion pausable")
		check(node.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "panel interpolation off")
	for child in node.get_children(): census(child)
func run() -> void:
	OS.add_logger(logger)
	create_timer(30.0).timeout.connect(func() -> void: quit(1))
	root.size = Vector2i(1280, 720)
	var mock := Mock.new()
	mock.autoplay = false
	root.add_child(mock)
	mock.start_run()
	await frames()
	check_round2_static(mock)
	check_overlay_fonts(mock)
	check_tally_cleanup()
	await check_bracket_occupancy()
	Capture.seed_capture_values(mock)
	check(mock.score == 12840 and mock.elapsed > 80 and mock.hud.time_label.text != "00:00.0", "R4 capture seeds real score and time")
	check(mock.hud.game == mock, "HUD bind")
	check_raster_rejection()
	check(mock.pause_menu.game == mock, "pause bind")
	check(mock.game_over.game == mock, "results bind")
	for overlay in [mock.hud.pursuit_alert, mock.boss_overlay, mock.stage_banner, mock.stage_clear]:
		overlay.bind(mock)
		overlay.bind(mock)
		check(overlay.game == mock, "idempotent bind " + overlay.name)
	mock.health_changed.emit(1, 2)
	check(mock.hud.hp_row.get_child_count() == 2, "approval pips")
	mock.score_changed.emit(1024, 1.5)
	mock.speed_changed.emit(32.0, 1.0)
	for kind in [&"approve_shield", &"lgtm", &"nitro", &"super_jump", &"code_review"]:
		mock.collect(kind, 8.0)
		check(mock.hud.chips.has(kind), "power-up glyph " + kind)
	mock.pursuit_started.emit(18.0)
	mock.pursuit_progress.emit(4.0, 18.0)
	mock.pursuit_alert.emit(&"critical", 4.0)
	mock.hud.pursuit_alert._process(0.4)
	check(mock.hud.pursuit_alert.visible, "alert incoming")
	mock.damage_blocked.emit(&"pr_backlog_low", &"shield")
	mock.pursuit_recovered.emit(&"timer")
	mock.hud.pursuit_alert._process(1.5)
	check(not mock.hud.pursuit_alert.visible, "alert recovery closes")
	mock.stage_started.emit(2, &"Merge Conflict Hydra", 24.0)
	mock.stage_banner._process(0.5)
	check(mock.stage_banner.visible, "stage banner")
	mock.turn_incoming.emit(1, 1.0)
	mock.turn_started.emit(1, 1.0)
	mock.stage_started.emit(3, &"Legacy Monolith", 26.0)
	check(not mock.stage_banner.visible, "turn defers banner")
	mock.turn_finished.emit()
	check(mock.stage_banner.visible, "turn releases banner")
	mock.boss_hp = 140
	mock.boss_intro.emit(mock.boss_kind, "Merge Conflict Hydra", 1.0)
	mock.boss_spawned.emit(mock.boss_kind, 140)
	mock.boss_overlay._process(1.1)
	mock.boss_health_changed.emit(70, 140)
	mock.boss_phase_changed.emit(2)
	check(mock.boss_overlay.pips[1].filled, "phase glyphs")
	check(mock.boss_overlay._target == 0.5, "segmented HP target")
	check(not mock.boss_overlay.tool_glyph.visible, "B6 tool glyph hidden before first pickup")
	mock.pursuit_started.emit(18.0)
	mock.pursuit_progress.emit(6.5, 18.0)
	await create_timer(0.35).timeout
	for extent in [Vector2i(1280,720), Vector2i(1440,900)]:
		root.size = extent
		root.content_scale_size = extent
		await frames()
		mock.hud._toast("+25 BONUS")
		mock.hud._process(0.01)
		mock.hud.turn_label.text = "TURN RIGHT 3"
		mock.hud.turn_panel.show()
		await frames()
		await check_centered_titles(mock)
		check(absf(mock.hud.turn_panel.get_global_rect().get_center().x-extent.x*0.5) <= 2, "R7 centered turn plate")
		var label: Label = mock.hud.turn_label
		var text_width := label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
		check(label.get_theme_font_size("font_size") >= 34, "R7 warning type minimum")
		check((label.size.x-text_width)*0.5 >= mock.hud.turn_icon.position.x+mock.hud.turn_icon.size.x+6, "R7 vector arrow clears centered copy")
		check(mock.hud.turn_icon.tint == mock.hud.turn_label.get_theme_color("font_color"), "R7 arrow and turn copy share hue")
		# Boss cards deliberately share one slot, but must never be visible together.
		var panels := {
			"approvals": mock.hud.hp_row.get_parent().get_parent(),
			"timer": mock.hud.time_label.get_parent(),
			"score": mock.hud.score_label.get_parent().get_parent(),
			"pursuit countdown": mock.hud.pursuit_panel,
			"boss plate": mock.boss_overlay.panel,
			"intro card": mock.boss_overlay.intro_card,
			"turn plate": mock.hud.turn_panel,
			"toast": mock.hud.toast_panel,
			"pursuit alert": mock.hud.pursuit_alert,
		}
		var scale_xy := Vector2(extent) / Vector2(1280, 720)
		var top_band := Rect2(Vector2.ZERO, Vector2(extent.x, 130 * scale_xy.y))
		var viewing_region := Rect2(Vector2(300, 130) * scale_xy, Vector2(680, 350) * scale_xy)
		# Lay out the longest authored intro while it is visible, then verify handover.
		mock.boss_intro.emit(mock.boss_kind, "Merge Conflict Hydra", 3.0)
		mock.boss_overlay._process(1.0)
		await frames()
		check(not mock.boss_overlay.visible and mock.boss_overlay.intro_card.visible, "intro replaces boss plate")
		for card in [mock.boss_overlay.panel, mock.boss_overlay.intro_card]:
			var rect: Rect2 = card.get_global_rect()
			check(top_band.encloses(rect), "boss card inside top band at " + str(extent) + ": " + str(rect))
			check(not viewing_region.intersects(rect), "boss card clears viewing region at " + str(extent))
		check(mock.boss_overlay.hp.size.y <= 14, "compact boss HP track")
		var names := panels.keys()
		for i in names.size():
			var rect: Rect2 = panels[names[i]].get_global_rect()
			print("A7 HUD RECT %s %s: %s" % [extent, names[i], rect])
			for j in range(i + 1, names.size()):
				if names[i] == "boss plate" and names[j] == "intro card":
					check(not (panels[names[i]].is_visible_in_tree() and panels[names[j]].is_visible_in_tree()), "shared boss slot is exclusive")
					continue
				check(not rect.intersects(panels[names[j]].get_global_rect()), "%s / %s separated at %s" % [names[i], names[j], extent])
		mock.boss_overlay._process(3.0)
		mock.boss_spawned.emit(mock.boss_kind, 140)
		await create_timer(0.35).timeout
		check(mock.boss_overlay.visible and not mock.boss_overlay.intro_card.visible, "spawned boss owns top slot after intro")
		check(mock.hud.turn_panel.get_global_rect().position.y >= 530, "turn warning below hazard read zone")
		check(not mock.hud.turn_panel.get_global_rect().intersects(mock.hud.speed_label.get_parent().get_parent().get_global_rect()), "turn and speed separated")

	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	await frames()
	for kind in [&"review_comment", &"lint_rule", &"unit_test", &"auto_fix_patch"]:
		mock.tool_collected.emit(kind, 10)
		check(mock.boss_overlay.tool_glyph.visible and mock.boss_overlay.tool_glyph.kind == kind and mock.boss_overlay.tool_glyph.tint == Palette.ORANGE, "B6 collected tool visible and orange")
		await frames()
		check(Rect2(300, 8, 680, 56).encloses(mock.boss_overlay.panel.get_global_rect()), "tool pickup keeps compact boss plate")
		var icon := Style.icon(kind)
		mock.hud.widgets.add_child(icon)
	mock.boss_defeated.emit(mock.boss_kind, 550)
	Capture.seed_stage_values(mock)
	mock.stage_cleared.emit(3, 550)
	mock.stage_clear._process(0.5)
	check(int(mock.stage_clear.tools_label.text) >= 3 and mock.stage_clear.time_label.text != "00:00.0", "R5 nonzero stage capture stats")
	await frames()
	await check_centered_titles(mock)
	check(mock.stage_clear.bonus_label.text == "+550", "stage clear tally")
	check(mock.stage_clear.bonus_label.get_theme_color("font_color") == Palette.ORANGE, "B9 orange bonus")
	mock.boss_retreated.emit(mock.boss_kind, 0)
	mock.pause()
	check(mock.pause_menu.visible and mock.pause_menu.resume_button.has_focus(), "pause focus")
	var finish: Node = mock.stage_clear.panel.get_node("PanelFinish")
	var frozen: int = finish.invalidations
	var finish_box: StyleBoxFlat = mock.stage_clear.panel.get_theme_stylebox("panel")
	finish_box.bg_color.a = 0.75
	finish._process(0.5)
	check(finish.invalidations == frozen, "pause suppresses decoration invalidation")
	mock.resume()
	finish._process(0.1)
	check(finish.invalidations == frozen+1, "R4 resumed style change invalidates drawing")
	mock.caught.emit()
	mock.hud.pursuit_alert._process(1.0)
	mock.finish_demo()
	await frames()
	check(mock.game_over.visible, "result hook")
	check(mock.game_over.retry_button.get_global_rect().position.y - mock.game_over.board.get_global_rect().end.y <= 10, "R6 results board has no surplus button gap")
	check(mock.game_over.stats.get_child(0).text.begins_with("SCORE "), "tally retains canonical result")
	for overlay in [mock.hud, mock.pause_menu, mock.game_over]:
		census(overlay)
		check_panel_decorations(overlay)
	check(draws_3d == 0 and mesh_triangles == 0, "UI bible vector-only budget")
	print("A7 UI CENSUS: canvas_items=%d; 3D draws=%d; mesh triangles=%d; procedural textures=0; portrait viewport=256x256; UI draw/triangle cap=n/a" % [canvas_items, draws_3d, mesh_triangles])
	var shader := FileAccess.get_file_as_string("res://scenes/runner/shaders/scanline_portrait.gdshader")
	check(not shader.contains("TIME"), "portrait shader has no TIME")
	check(shader.contains("uniform float clock"), "explicit shader clock")
	check(shader.count("texture(screen_texture,") == 1 and not shader.contains("shift"), "R7 zero RGB channel separation")
	check(shader.contains("filter_linear") and shader.contains("rgb * pulse"), "R7 smooth sampling and luminance flicker")
	check(mock.game_over.name_field.get_theme_stylebox("normal").corner_radius_top_left == 10, "R7 chamfered name field")
	check(mock.game_over.name_field.get_theme_stylebox("focus").border_color == Palette.MINT, "R7 mint name focus")
	var label_count := 0
	for overlay in [mock.hud, mock.pause_menu, mock.game_over]:
		label_count += overlay.find_children("*", "Label", true, false).size()
	check(label_count >= 55, "B5 accessibility label census >=55")
	var alert: Control = mock.hud.pursuit_alert
	alert.reparent(mock.hud)
	Capture.frame_closeup(alert)
	await frames()
	check(alert.size == Capture.CLOSEUP_SIZE and alert.scale == Capture.CLOSEUP_SCALE, "B4 closeup explicit size and 2x scale")
	check(alert.panel.size.x >= 420 and alert.panel.size.y >= 196, "B4 closeup content does not collapse")
	var closeup := alert.get_global_rect()
	check(closeup.size == Vector2(840,392) and Rect2(0,0,1280,720).encloses(closeup), "B4 closeup fits frame")
	mock.free()
	await frames()
	var menu := load("res://scenes/runner/runner_menu.tscn").instantiate() as Node
	root.add_child(menu)
	await frames()
	check(menu.ui.get_theme_default_font() == Style.theme().default_font, "R4 runner menu shared font")
	check(menu.buttons.size() == 4, "menu buttons preserved")
	menu._toggle_leaderboard()
	await frames()
	check(menu.modal != null and menu.board.get_child_count() == 10, "leaderboard rows and medals")
	for label: Label in menu.ui.find_children("*", "Label", true, false):
		check(label.get_theme_font_size("font_size") >= 18, "menu font >=18")
		check(label.get_theme_constant("outline_size") >= 6, "menu outline >=6")
		var rect := label.get_global_rect()
		check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 1280 and rect.end.y <= 720, "menu label fits viewport: " + label.text)
		var backing := label.get_parent()
		while backing != null and not backing is PanelContainer: backing = backing.get_parent()
		check(backing != null, "menu panel backing")
	for i in 10:
		var marker: Control = menu.board.get_child(i).get_child(0)
		var row_text: String = menu.board.get_child(i).get_child(1).text
		if i >= 3 or row_text.contains("---"):
			check(not "kind" in marker, "R5 no medal for empty/nonpodium row")
	for i in 3:
		var marker: Control = menu.rank_marker(i,true)
		check(marker.tint == [Palette.CREAM.lerp(Palette.ORANGE,0.35),Palette.SLATE.lerp(Palette.CREAM,0.65),Palette.ORANGE.lerp(Palette.NAVY_2,0.3)][i], "R5 populated podium tint")
		marker.free()
	for label: Label in menu.ui.find_children("*", "Label", true, false):
		if label.text == "KEEP THE BUILD MOVING": check(label.get_theme_font_size("font_size") == 26, "R5 menu heading scale")
		if label.text.begins_with("A / D"): check(label.get_theme_font_size("font_size") == 22, "R5 menu controls scale")
		if label.text.begins_with("Two hits"): check(label.get_theme_font_size("font_size") == 18, "R5 menu caption scale")
	check_panel_decorations(menu.ui)
	menu._close_leaderboard()
	check(menu.buttons[1].has_focus(), "leaderboard returns focus")
	menu.free()
	await frames()
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	await create_timer(0.15).timeout
	check(logger.count == 0, "no runtime engine/script errors")
	OS.remove_logger(logger)
	print("ASSET A7: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func check_round2_static(mock: Node) -> void:
	var headlines := Alert.PortraitArt.headlines()
	check(headlines.size() <= 3, "B1 no more than three portrait cards")
	var art: Control = mock.hud.pursuit_alert.portrait_viewport.get_child(0)
	var font: Font = art.portrait_font
	check(font == Style.theme().default_font and art.deferred_redraws >= 1, "R5 shared mono portrait font and deferred redraw")
	check(headlines.size() == 1 and Alert.PortraitArt.CARD_TYPE[0] >= 64, "R3 one display-size headline")
	for i in headlines.size():
		check(Pursuer.HEADLINES.has(headlines[i]), "B1 shared headlines source")
		check(Alert.PortraitArt.CARD_TYPE[i] >= 32, "B1 portrait type >=32")
		check(not Alert.PortraitArt.EYE_PLATE.intersects(Alert.PortraitArt.CARD_RECTS[i]), "B1 eyes have separate plate")
		for word in headlines[i].split(" "):
			check(font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, Alert.PortraitArt.CARD_TYPE[i]).x <= Alert.PortraitArt.CARD_RECTS[i].size.x-16, "B1 headline fits card")
	for panel in [mock.hud.time_label.get_parent(), mock.hud.speed_label.get_parent().get_parent()]:
		var finish: Node = panel.get_node("PanelFinish")
		var box: StyleBoxFlat = panel.get_theme_stylebox("panel")
		check(is_equal_approx(finish.surface_alpha(), 0.70), "B2 authored time/speed opacity")
		check(not box.draw_center, "B2 only one interior fill")
		check(is_equal_approx(finish.corner_cut(), box.corner_radius_top_left), "aligned chamfer")
		finish._process(0.1)
		var frozen: int = finish.invalidations
		finish._process(0.1)
		check(finish.invalidations == frozen, "static panel does not invalidate unchanged drawing")
	check(Finish.STATIC_COMMANDS == 4, "R3 four static panel commands and no sweeps")
	var source := FileAccess.get_file_as_string("res://scenes/runner/ui/hifi/panel_finish.gd")
	check(not source.contains("scan_y") and not source.contains("for i in 12") and not source.contains("for i in 5"), "B3 no scanline/grain/telemetry dashes")
	var fingerprints: Array[String] = []
	for kind in [&"approve_shield", &"lgtm", &"nitro", &"super_jump", &"code_review", &"auto_fix", &"review_comment", &"lint_rule", &"unit_test", &"auto_fix_patch", &"unknown"]:
		var shape := Glyph.geometry(kind)
		var signature := var_to_str(shape)
		check(not fingerprints.has(signature), "B5 distinct vector geometry: " + kind)
		fingerprints.append(signature)
		for paths in [shape.lines, shape.fills]:
			for path in paths:
				for point: Vector2 in path: check(absf(point.x) <= 1 and absf(point.y) <= 1, "B5 glyph within bounds")
	check(Glyph.STROKE >= 3, "three-pixel glyph strokes")
	var chip_fill: StyleBoxFlat = mock.boss_overlay.chip.get_theme_stylebox("fill")
	var chip_track: StyleBoxFlat = mock.boss_overlay.chip.get_theme_stylebox("background")
	check(chip_fill.bg_color == Palette.SLATE and chip_track.bg_color == Palette.NAVY_2, "B6 subdued damage chip")
	check(chip_track.border_color == Palette.CREAM and chip_track.border_width_top == 1, "B6 thin cream edge")
	var button: Button = mock.game_over.save_button
	var disabled: StyleBoxFlat = button.get_theme_stylebox("disabled")
	var normal: StyleBoxFlat = button.get_theme_stylebox("normal")
	check(disabled.bg_color.get_luminance() < normal.bg_color.get_luminance(), "B8 disabled fill dimmer")
	check(disabled.border_color.get_luminance() < normal.border_color.get_luminance(), "B8 disabled border dimmer")
	check(button.get_theme_color("font_disabled_color").get_luminance() < button.get_theme_color("font_color").get_luminance(), "B8 disabled text muted")
	var panel_a := PanelContainer.new()
	var panel_b := PanelContainer.new()
	var shared := Style.panel(Palette.MINT, 0.7)
	panel_a.add_theme_stylebox_override("panel", shared)
	panel_b.add_theme_stylebox_override("panel", shared)
	Style.polish(panel_a)
	check(shared.draw_center and panel_b.get_theme_stylebox("panel").draw_center, "polish does not mutate shared style")
	panel_a.free()
	panel_b.free()
	check(not mock.game_over.error_label.has_meta("legibility_exemption"), "remove dead exemption")
	mock.pursuit_started.emit(18.0)
	mock.pursuit_progress.emit(18.0,18.0)
	mock.hud.pursuit_alert._process(0.4)
	check(mock.hud.pursuit_alert.waveform.tint == Palette.MATRIX, "waveform safe proximity")
	mock.pursuit_progress.emit(0.0,18.0)
	mock.hud.pursuit_alert._process(0.1)
	check(mock.hud.pursuit_alert.waveform.tint.is_equal_approx(Palette.DANGER), "waveform danger proximity")

func check_panel_decorations(node: Node) -> void:
	if node is PanelContainer and node.has_node("PanelFinish"):
		var finish: Node2D = node.get_node("PanelFinish")
		var bracket: Rect2 = finish.bracket_rect()
		if bracket.has_area(): check(node.size.x-bracket.end.x >= 14, "R4 bracket separated from border")
		if node.size.y < 56: check(not bracket.has_area(), "R3 short panels omit bracket")
		for item in node.find_children("*", "CanvasItem", true, false):
			if item == finish or not item.is_visible_in_tree(): continue
			if item is Control:
				var transform: Transform2D = node.get_global_transform().affine_inverse() * item.get_global_transform()
				var bounds: Rect2 = transform * Rect2(Vector2.ZERO,item.size)
				check(not bracket.has_area() or not bracket.intersects(bounds.grow(2)), "R6 all content clear of bracket: " + item.name)
			else:
				check(not bracket.has_area(), "R6 unknown CanvasItem suppresses bracket")
		for label: Label in node.find_children("*", "Label", true, false):
			if not label.is_visible_in_tree(): continue
			var local: Transform2D = node.get_global_transform().affine_inverse() * label.get_global_transform()
			var rect: Rect2 = local * Rect2(Vector2.ZERO,label.size)
			check(not bracket.has_area() or not bracket.intersects(rect), "R3 label clear of bracket: " + label.text)
			# Absolute portrait layout retains its separately tested design margins.
			if label.get_parent() == node:
				check(node.size.x-rect.end.x >= 12, "R5 symmetric direct label padding: " + label.text)
	for child in node.get_children(): check_panel_decorations(child)

func check_raster_rejection() -> void:
	var blocks := Image.create(256,256,false,Image.FORMAT_RGBA8)
	blocks.fill(Palette.NAVY_BG)
	check(not Raster.inspect(blocks).passed, "R3 raster gate rejects blank card")
	for i in 5: blocks.fill_rect(Rect2i(30+i*40,150,25,46),Palette.CREAM)
	check(not Raster.inspect(blocks).passed, "R3 raster gate rejects solid rectangular glyphs")
	var colors := Image.create(256,256,false,Image.FORMAT_RGBA8)
	colors.fill(Palette.CREAM)
	check(Raster.inspect_palette(colors).passed, "R7 cream palette accepted")
	for hue in [Color8(14,78,205),Color8(254,239,39),Color8(250,30,44)]:
		colors.fill(hue)
		check(not Raster.inspect_palette(colors).passed, "R7 captured RGB artifact rejected")
	for allowed in [Palette.DANGER,Palette.NAVY_BG,Palette.SLATE]:
		colors.fill(allowed)
		check(Raster.inspect_palette(colors).passed, "R7 authored palette accepted")
	colors.fill(Palette.CREAM)
	colors.fill_rect(Rect2i(20,132,7,82),Color.BLUE)
	check(not Raster.inspect_palette(colors).passed, "R7 more than three percent off-palette rejected")
	colors.fill(Palette.CREAM)
	colors.fill_rect(Rect2i(20,132,6,82),Color.BLUE)
	check(Raster.inspect_palette(colors).passed, "R7 less than three percent tolerance")
	print("A7 PORTRAIT RASTER: NOT VERIFIED (headless; coordinator capture performs pixel gate)")

func check_overlay_fonts(mock: Node) -> void:
	var shared: Font = Style.theme().default_font
	check(shared == Style.theme().default_font, "R4 stable shared theme font")
	for ui: Control in [mock.hud.screen, mock.pause_menu.get_child(0), mock.game_over.get_node("Screen"), mock.boss_overlay, mock.boss_overlay.intro_card, mock.stage_banner, mock.stage_clear, mock.hud.pursuit_alert]:
		check(ui.get_theme_default_font() == shared, "R4 overlay font: " + ui.name)
		for label: Label in ui.find_children("*", "Label", true, false):
			check(label.get_theme_font("font") == shared, "R4 label font: " + label.text)

func check_tally_cleanup() -> void:
	var label := Style.label("SCORE 12840",22)
	root.add_child(label)
	var tally := Tally.new()
	label.add_child(tally)
	check(label.visible_characters == 0, "R4 tally begins with its own drawing")
	label.remove_child(tally)
	check(label.visible_characters == -1, "R4 interrupted tally restores real label")
	tally.free()
	label.free()

func check_centered_titles(mock: Node) -> void:
	# Hidden containers retain stale bounds. Measure each card after visible layout.
	var cards := [mock.boss_overlay.intro_card, mock.stage_banner, mock.stage_clear]
	var visibility: Array[bool] = []
	for card: Control in cards:
		visibility.append(card.visible)
		card.show()
	await frames()
	for pair in [[mock.stage_banner.panel,mock.stage_banner.title], [mock.stage_banner.panel,mock.stage_banner.subtitle], [mock.stage_clear.panel,mock.stage_clear.title], [mock.stage_clear.panel,mock.stage_clear.subtitle]]:
		var panel: Control = pair[0]
		var title: Label = pair[1]
		var box: StyleBoxFlat = panel.get_theme_stylebox("panel")
		check(is_equal_approx(box.content_margin_left,box.content_margin_right), "R5 symmetric title margins")
		check(absf(title.get_global_rect().get_center().x-panel.get_global_rect().get_center().x) <= 2, "R5 title horizontally centered: " + title.text)
	var intro: Label = mock.boss_overlay.intro_name
	check(mock.boss_overlay.intro_card.get_global_rect().encloses(intro.get_global_rect()), "intro title fits top-band card")
	check(not intro.get_global_rect().intersects(intro.get_parent().get_child(0).get_global_rect()), "intro title clears warning eyebrow")
	for card: Control in cards: check_panel_decorations(card)
	check_panel_decorations(mock.boss_overlay)
	for index in cards.size():
		cards[index].visible = visibility[index]

func check_bracket_occupancy() -> void:
	var panel := PanelContainer.new()
	panel.size = Vector2(240,120)
	panel.add_theme_stylebox_override("panel",Style.panel(Palette.MINT))
	root.add_child(panel)
	Style.polish(panel)
	var finish: Node = panel.get_node("PanelFinish")
	await frames()
	check(finish.bracket_rect().has_area(), "R6 empty corner has bracket")
	var scans: int = finish.occupancy_scans
	for i in 20:
		finish._process(0.016)
		finish.bracket_rect()
	check(finish.occupancy_scans == scans, "R6 unchanged frames reuse occupancy cache")
	var rule := ColorRect.new()
	rule.set_as_top_level(true)
	panel.add_child(rule)
	await frames()
	rule.position = Vector2(205,95)
	rule.size = Vector2(30,2)
	check(not finish.bracket_rect().has_area(), "R6 ColorRect rule suppresses bracket")
	rule.hide()
	check(finish.bracket_rect().has_area(), "R6 hidden rule invalidates occupancy")
	rule.show()
	check(not finish.bracket_rect().has_area(), "R6 shown rule invalidates occupancy")
	rule.position = Vector2.ZERO
	check(finish.bracket_rect().has_area(), "R6 moved rule invalidates occupancy")
	var unknown := Node2D.new()
	panel.add_child(unknown)
	check(not finish.bracket_rect().has_area(), "R6 custom CanvasItem conservatively suppresses bracket")
	unknown.free()
	check(finish.bracket_rect().has_area(), "R6 removed child invalidates occupancy")
	panel.free()
