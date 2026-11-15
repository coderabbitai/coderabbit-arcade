extends "res://scenes/main_menu/menu_button.gd"
## One game on the hub grid: its stage art cover-cropped behind a lower scrim, the family, title
## and tagline, and a PLAY prompt that appears while the tile is focused or hovered. The Button
## itself owns focus, hover and pressed; every child ignores the mouse, so the tile reacts as one
## control. The grow on focus comes from menu_button.gd.
const Style := preload("res://scenes/main_menu/menu_style.gd")
const Preview := preload("res://scenes/main_menu/preview.gd")
const Prompts := preload("res://app/controller_prompts.gd")
const TILE_SIZE := Vector2(362, 188)
const BORDER := 3
var route := ""
var game_index := -1
var art: Array[TextureRect] = []
var play_prompt: Label

func setup(index: int, game: Dictionary) -> void:
	game_index = index
	route = game.route
	name = String(game.route).to_pascal_case() + "Tile"
	text = ""
	custom_minimum_size = TILE_SIZE
	clip_contents = true
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("10182b")
		box.border_color = Color("435464") if state == "normal" else Style.MINT
		box.set_border_width_all(BORDER)
		add_theme_stylebox_override(state, box)
	var first: int = game.previews[0]
	for texture in Preview.textures(first):
		var plate := TextureRect.new()
		plate.texture = texture
		plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if Preview.STILLS.has(first) \
			else CanvasItem.TEXTURE_FILTER_NEAREST
		_fill(plate)
		art.append(plate)
	var scrim := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.025, 0.045, 0.08, 0.0))
	gradient.set_color(1, Color(0.025, 0.045, 0.08, 0.92))
	var scrim_texture := GradientTexture2D.new()
	scrim_texture.gradient = gradient
	scrim_texture.fill_from = Vector2(0, 0.4)
	scrim_texture.fill_to = Vector2(0, 1.0)
	scrim.texture = scrim_texture
	_fill(scrim)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored to the bottom-left corner and growing upward, so the text block hugs the bottom
	# whatever its height.
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_left = 16
	column.offset_top = -14
	column.offset_bottom = -14
	add_child(column)
	for label: Label in [Style.label(game.family, 11, Style.MINT), Style.label(game.title, 21),
			Style.label(game.tagline, 12, Color("afbdc9"))]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
	play_prompt = Style.label("", 12, Style.MINT)
	play_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Bright stage ceilings sit behind the prompt, so it carries its own dark edge.
	play_prompt.add_theme_color_override("font_outline_color", Color(0.025, 0.045, 0.08, 0.9))
	play_prompt.add_theme_constant_override("outline_size", 5)
	play_prompt.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	play_prompt.offset_left = -176
	play_prompt.offset_right = -16
	play_prompt.offset_top = 12
	play_prompt.offset_bottom = 36
	play_prompt.visible = false
	Prompts.track(play_prompt, func() -> String:
		return "%s  PLAY" % Prompts.either("ENTER", &"ui_accept", true))
	add_child(play_prompt)
	for signal_name in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
		connect(signal_name, _update_prompt)

func _fill(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.offset_left = BORDER
	node.offset_top = BORDER
	node.offset_right = -BORDER
	node.offset_bottom = -BORDER
	add_child(node)

func _update_prompt() -> void:
	play_prompt.visible = is_hovered() or has_focus()
