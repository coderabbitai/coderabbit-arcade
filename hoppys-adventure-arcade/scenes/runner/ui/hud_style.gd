extends RefCounted
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const MINT := Palette.MINT

static func theme() -> Theme:
	return Style.theme()

static func label(text: String, size: int, color: Color = Palette.CREAM, _weight: StringName = &"body") -> Label:
	var node := Style.label(text, size, color)
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
	return node

static func panel(border: Color, alpha: float = 0.82) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.NAVY_BG, alpha)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
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
