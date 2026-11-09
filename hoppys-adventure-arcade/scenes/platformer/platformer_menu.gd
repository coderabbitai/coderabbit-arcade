extends Control
const Style = preload("res://scenes/main_menu/menu_style.gd")
var column: VBoxContainer
func _ready() -> void:
	theme = Style.theme()
	var backdrop := TextureRect.new()
	backdrop.texture = load("res://Assets/bay-area-blitz-assets-only/bay_area/backdrop.png")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.07, 0.12, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	_select()
func _clear() -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
func _select() -> void:
	_clear()
	column.add_child(Style.label("HOPPY'S ADVENTURE ARCADE / 01  ·  PLATFORMER", 16, Style.MINT))
	column.add_child(Style.label("LEVEL SELECT", 42))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for i in 3:
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_constant_override("separation", 15)
		row.add_child(card)
		var preview := TextureRect.new()
		preview.texture = load(["res://Assets/bay-area-blitz-assets-only/bay-area-preview.png", "res://Assets/orbital-ops-assets-only/orbital_ops/starfield.png", "res://Assets/enchanted-repo-assets-only/enchanted_repo/sky.png"][i])
		preview.custom_minimum_size = Vector2(0, 210)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.modulate = Color.WHITE
		card.add_child(preview)
		if i in [1, 2]:
			var station := TextureRect.new()
			station.texture = load("res://Assets/orbital-ops-assets-only/orbital_ops/station_hull.png" if i == 1 else "res://Assets/enchanted-repo-assets-only/enchanted_repo/treeline.png")
			station.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			station.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			station.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			station.mouse_filter = Control.MOUSE_FILTER_IGNORE
			preview.add_child(station)
		card.add_child(Style.label(["BAY AREA BLITZ", "ORBITAL OPS", "ENCHANTED REPO"][i], 21))
		card.add_child(Style.label(["Cable cars. Code critters. Chaos.", "Zero gravity. Broken legacy routines.", "Ancient armor. Unstable branches."][i], 13))
		var play := Button.new()
		play.text = ["PLAY BAY AREA BLITZ  →", "PLAY ORBITAL OPS  →", "PLAY ENCHANTED REPO  →"][i]
		play.custom_minimum_size.y = 58
		card.add_child(play)
		if i == 0:
			play.pressed.connect(func(): AppRouter.go("bay_area_blitz"))
			play.grab_focus()
		elif i == 1:
			play.pressed.connect(func(): AppRouter.go("orbital_ops"))
		else:
			play.pressed.connect(func(): AppRouter.go("enchanted_repo"))
	var back := Style.button("← Main Menu")
	column.add_child(back)
	back.pressed.connect(func(): AppRouter.go("hub"))
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AppRouter.go("hub")
