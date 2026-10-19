extends Control

const QR_TEXTURE: Texture2D = preload("res://Assets/booth/booth_qr.png")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.name = "BoothQrPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -208
	panel.offset_top = 24
	panel.offset_right = -24
	panel.offset_bottom = 230
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("fffaf2")
	panel_style.border_color = Color("182432")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)

	var heading := Label.new()
	heading.text = "SCAN TO LEARN MORE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color("182432"))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(heading)

	var code := TextureRect.new()
	code.texture = QR_TEXTURE
	code.custom_minimum_size = Vector2(148, 148)
	code.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	code.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(code)

	var attribution := Label.new()
	attribution.text = "CODERABBIT.AI"
	attribution.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attribution.add_theme_font_size_override("font_size", 10)
	attribution.add_theme_color_override("font_color", Color("536271"))
	attribution.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(attribution)
