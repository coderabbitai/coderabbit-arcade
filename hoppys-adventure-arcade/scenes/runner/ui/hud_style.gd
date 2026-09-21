extends RefCounted
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const MINT := Palette.MINT
const CREAM := Palette.CREAM
const Finish = preload("res://scenes/runner/ui/hifi/panel_finish.gd")
const Glyph = preload("res://scenes/runner/ui/hifi/utility_glyph.gd")

static var _theme: Theme

static func theme() -> Theme:
	if _theme == null: _theme = Style.theme()
	return _theme

static func label(text: String, size: int, color: Color = Palette.CREAM, _weight: StringName = &"body") -> Label:
	var node := Style.label(text, maxi(18, size), color)
	node.add_theme_constant_override("outline_size", maxi(6, roundi(size * 0.30)))
	node.add_theme_color_override("font_outline_color", Palette.NAVY_BG)
	node.add_theme_constant_override("shadow_offset_x", 0)
	node.add_theme_constant_override("shadow_offset_y", 2)
	node.add_theme_color_override("font_shadow_color", Color(Palette.NAVY_BG, 0.75))
	return node

static func button(text: String, height: float = 62) -> Button:
	var node := Style.button(text, height)
	node.add_theme_constant_override("outline_size", 6)
	node.add_theme_color_override("font_outline_color", Palette.NAVY_BG)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := panel(Palette.SLATE if state in ["normal", "disabled"] else Palette.MINT, 0.96)
		box.content_margin_left = 22
		box.content_margin_right = 22
		box.bg_color = Palette.NAVY_2 if state in ["hover", "focus"] else Palette.NAVY_BG
		box.shadow_color = Color(Palette.MINT, 0.12 if state in ["hover", "focus"] else 0.0)
		box.shadow_size = 6 if state in ["hover", "focus"] else 0
		if state == "focus": box.bg_color = Color.TRANSPARENT
		if state == "disabled":
			box.bg_color = Palette.NAVY_BG.darkened(0.45)
			box.border_color = Palette.SLATE.darkened(0.55)
			node.add_theme_color_override("font_disabled_color", Palette.SLATE.lerp(Palette.CREAM, 0.2))
		node.add_theme_stylebox_override(state, box)
	return node

static func polish(node: PanelContainer, _depth: bool = false) -> void:
	# Only the finish paints the interior; avoid alpha accumulating over a second fill.
	var box := node.get_theme_stylebox("panel") as StyleBoxFlat
	if box.draw_center:
		var local := box.duplicate() as StyleBoxFlat
		local.draw_center = false
		node.add_theme_stylebox_override("panel", local)
	if node.has_node("PanelFinish"): return
	var finish := Finish.new()
	finish.name = "PanelFinish"
	node.add_child(finish)
	node.move_child(finish, 0)

static func icon(kind: StringName, tint: Color = Palette.MINT, extent: Vector2 = Vector2(30, 30)) -> Control:
	var glyph := Glyph.new()
	glyph.kind = kind
	glyph.tint = tint
	glyph.custom_minimum_size = extent
	return glyph

static func panel(border: Color, alpha: float = 0.82) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.NAVY_BG, alpha)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.corner_detail = 1
	box.shadow_color = Color(Palette.NAVY_BG, 0.65)
	box.shadow_size = 5
	box.shadow_offset = Vector2(0, 3)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

static func backed(text: String, size: int, color: Color, pad: Vector2 = Vector2(12, 6)) -> PanelContainer:
	var node := PanelContainer.new()
	var box := panel(color)
	box.content_margin_left = pad.x
	box.content_margin_right = pad.x
	box.content_margin_top = pad.y
	box.content_margin_bottom = pad.y
	node.add_theme_stylebox_override("panel", box)
	polish(node)
	node.add_child(label(text, size, color))
	return node

static func bar(extent: Vector2, fill: Color, track: Color = Palette.SLATE) -> ProgressBar:
	var node := ProgressBar.new()
	node.custom_minimum_size = extent
	node.show_percentage = false
	node.max_value = 1.0
	var background := StyleBoxFlat.new()
	background.bg_color = track
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = fill
	node.add_theme_stylebox_override("background", background)
	node.add_theme_stylebox_override("fill", foreground)
	return node
