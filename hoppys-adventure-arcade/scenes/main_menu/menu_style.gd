extends RefCounted
const CREAM := Color("fff0d3")
const MINT := Color("79e0c4")
## One shared theme (and SystemFont): glyphs rasterized in one scene stay cached for the next.
static var _theme: Theme
static func theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme
static func _build_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono"])
	font.font_weight = 700
	result.default_font = font
	result.default_font_size = 19
	result.set_color("font_color", "Label", CREAM)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("142735") if state == "normal" else Color("244447")
		box.border_color = Color("435464") if state == "normal" else MINT
		box.set_border_width_all(2)
		box.content_margin_left = 22
		box.content_margin_right = 22
		result.set_stylebox(state, "Button", box)
		result.set_color("font_" + state + "_color", "Button", CREAM)
	result.set_color("font_color", "Button", CREAM)
	return result
static func label(text: String, font_size: int, color: Color = CREAM) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node
static func button(text: String, height: float = 62) -> Button:
	var node := Button.new()
	node.set_script(preload("res://scenes/main_menu/menu_button.gd"))
	node.text = text
	node.custom_minimum_size = Vector2(420, height)
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return node
