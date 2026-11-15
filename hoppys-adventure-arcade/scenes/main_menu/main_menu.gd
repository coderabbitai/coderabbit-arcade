extends Node2D
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Preview = preload("res://scenes/main_menu/preview.gd")
const Prompts := preload("res://app/controller_prompts.gd")
const GameCatalog = preload("res://scenes/main_menu/game_catalog.gd")
const GameTile = preload("res://scenes/main_menu/game_tile.gd")
const TITLE_Y := 46.0
@onready var showcase = $Showcase
@onready var hoppy = $Interface/Hoppy
var ui: Control
## The six game tiles in grid order, then Settings, Quit Game and Credits.
var buttons: Array[Button] = []
var tiles: Array[Button] = []
var utilities: Array[Button] = []
var preview_note: Label
var caption: Label
var dots: Label
var modal: Control
var modal_return: Control
var keyboard_input := false
var hovered := -1
var shade: TextureRect
var footer_shade: TextureRect
var title: VBoxContainer
var elapsed := 0.0
var save_warning: Label

func _ready() -> void:
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Style.theme()
	$Interface.add_child(ui)
	$Interface.move_child(ui, 0)
	shade = TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.025, 0.045, 0.08, 0.97))
	gradient.set_color(1, Color(0.025, 0.045, 0.08, 0.35))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0.1)
	shade.texture = texture
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	# Bright stage floors need a separate lower scrim for preview captions and controls.
	footer_shade = TextureRect.new()
	var footer_gradient := Gradient.new()
	footer_gradient.set_color(0, Color(0.025, 0.045, 0.08, 0.0))
	footer_gradient.set_color(1, Color(0.025, 0.045, 0.08, 0.9))
	var footer_texture := GradientTexture2D.new()
	footer_texture.gradient = footer_gradient
	footer_texture.fill_from = Vector2(0, 0.7)
	footer_texture.fill_to = Vector2(0, 0.95)
	footer_shade.texture = footer_texture
	footer_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(footer_shade)
	hoppy.reparent(ui)
	var eyebrow := Style.label("C O D E R A B B I T   /   A R C A D E", 13, Style.MINT)
	eyebrow.position = Vector2(76, 30)
	ui.add_child(eyebrow)
	title = VBoxContainer.new()
	title.position = Vector2(72, TITLE_Y)
	title.add_theme_constant_override("separation", -8)
	ui.add_child(title)
	title.add_child(Style.label("HOPPY'S ADVENTURE", 44))
	title.add_child(Style.label("A R C A D E", 24, Color("f5a568")))
	var subtitle := Style.label("SIX GAMES. ONE HOPPY. PICK A TILE TO PLAY.", 13, Color("afbdc9"))
	subtitle.position = Vector2(77, 128)
	ui.add_child(subtitle)
	var grid := GridContainer.new()
	grid.name = "Games"
	grid.columns = GameCatalog.COLUMNS
	grid.position = Vector2(77, 160)
	# Wider than the 1.05 grow of a focused tile, so grown tiles never cover their neighbours.
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	ui.add_child(grid)
	for i in GameCatalog.GAMES.size():
		var game: Dictionary = GameCatalog.GAMES[i]
		var tile := Button.new()
		tile.set_script(GameTile)
		grid.add_child(tile)
		tile.setup(i, game)
		tiles.append(tile)
		buttons.append(tile)
		_connect_button(tile, i, false)
		tile.pressed.connect(_launch.bind(game.route))
	var utility_row := HBoxContainer.new()
	utility_row.position = Vector2(76, 584)
	# Wider than the focus arrow's 25 px reach, so it never sits on the neighbouring button.
	utility_row.add_theme_constant_override("separation", 28)
	ui.add_child(utility_row)
	for i in 2:
		var button := Style.button("Settings" if i == 0 else "Quit Game", 46)
		button.custom_minimum_size.x = 160
		utility_row.add_child(button)
		buttons.append(button)
		utilities.append(button)
		_connect_button(button, -1)
		button.pressed.connect(_open_settings.bind(button) if i == 0 else _open_quit.bind(button))
	# Last in `buttons`, so the tiles come first and Settings and Quit Game keep their places.
	var credits := Style.button("Credits", 46)
	credits.name = "CreditsButton"
	credits.custom_minimum_size.x = 160
	utility_row.add_child(credits)
	buttons.append(credits)
	utilities.append(credits)
	_connect_button(credits, -1)
	credits.pressed.connect(_launch.bind("credits"))
	_wire_focus()
	var footer := Style.label("", 12, Color("9baebc"))
	Prompts.track(footer, func() -> String:
		return "← → ↑ ↓  SELECT     %s  PLAY     %s  QUIT" % [
			Prompts.either("ENTER", &"ui_accept", true), Prompts.either("ESC", &"ui_cancel", true)])
	footer.position = Vector2(76, 672)
	ui.add_child(footer)
	caption = Style.label("", 18)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.position = Vector2(640, 594)
	caption.size.x = 563
	ui.add_child(caption)
	dots = Style.label("", 13, Style.MINT)
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dots.position = Vector2(640, 624)
	dots.size.x = 563
	ui.add_child(dots)
	preview_note = Style.label("WORLD PREVIEW", 11, Color("afbdc9"))
	preview_note.position = Vector2(640, 578)
	preview_note.size.x = 563
	preview_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(preview_note)
	showcase.preview_changed.connect(_preview_changed)
	_preview_changed(showcase.active_index)
	get_viewport().size_changed.connect(_layout)
	# Deferred: sizing full-rect-anchored controls inside _ready is overridden (and warned about).
	_layout.call_deferred()
	buttons[0].grab_focus()

## Arrows and the D-pad move across the grid: left and right wrap within a row, up and down step
## between the two rows and, past them, to the utility button in the same column (Settings, Quit
## Game, Credits), which lead back onto the grid. Tab follows `buttons` order.
func _wire_focus() -> void:
	var columns := GameCatalog.COLUMNS
	var rows := ceili(tiles.size() / float(columns))
	for i in tiles.size():
		var column := i % columns
		var row := i / columns
		var tile := tiles[i]
		tile.focus_neighbor_left = tile.get_path_to(tiles[row * columns + (column + columns - 1) % columns])
		tile.focus_neighbor_right = tile.get_path_to(tiles[row * columns + (column + 1) % columns])
		var utility := utilities[mini(column, utilities.size() - 1)]
		tile.focus_neighbor_top = tile.get_path_to(tiles[i - columns] if row > 0 else utility)
		tile.focus_neighbor_bottom = tile.get_path_to(tiles[i + columns] if row < rows - 1 else utility)
	for u in utilities.size():
		var button := utilities[u]
		button.focus_neighbor_left = button.get_path_to(utilities[(u + utilities.size() - 1) % utilities.size()])
		button.focus_neighbor_right = button.get_path_to(utilities[(u + 1) % utilities.size()])
		var column := mini(u, columns - 1)
		button.focus_neighbor_top = button.get_path_to(tiles[(rows - 1) * columns + column])
		button.focus_neighbor_bottom = button.get_path_to(tiles[column])
	for i in buttons.size():
		buttons[i].focus_previous = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_next = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])

func _process(delta: float) -> void:
	elapsed += delta
	title.position.y = TITLE_Y + sin(elapsed * PI) * 2

# Keep composition centered as expand stretch exposes extra width or height. Runs on resize only:
# rewriting sizes every frame forces the button containers to re-sort (and reset their scale).
func _layout() -> void:
	var extra := (get_viewport_rect().size - Vector2(1280, 720)) * 0.5
	ui.position = extra
	ui.size = Vector2(1280, 720)
	shade.position = -extra
	shade.size = get_viewport_rect().size
	footer_shade.position = -extra
	footer_shade.size = get_viewport_rect().size
	if modal:
		modal.get_child(0).position = -extra
		modal.get_child(0).size = get_viewport_rect().size
	hoppy.position = Vector2(1160, 150)
	hoppy.scale = Vector2.ONE * 0.66

func _input(event: InputEvent) -> void:
	if AppRouter.busy:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and event.relative.length() > 0:
		keyboard_input = false
	elif event is InputEventKey or event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		keyboard_input = true
		if not modal:
			var focused := get_viewport().gui_get_focus_owner()
			var id := buttons.find(focused)
			_select(id if id < tiles.size() else -1)
	if event.is_action_pressed("ui_cancel"):
		if modal:
			_close_modal()
		else:
			_open_quit(utilities[1])
		get_viewport().set_input_as_handled()

func _connect_button(button: Button, group: int, arrow_marker := true) -> void:
	if arrow_marker:
		var arrow := Style.label("›", 26, Style.MINT)
		arrow.position = Vector2(-25, 13)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.visible = false
		button.add_child(arrow)
		button.focus_entered.connect(func(): arrow.visible = true)
		button.focus_exited.connect(func(): arrow.visible = false)
	button.mouse_entered.connect(func():
		if modal or AppRouter.busy: return
		keyboard_input = false
		hovered = group
		_select(group)
		AudioService.play_ui())
	button.mouse_exited.connect(func():
		if not keyboard_input and not modal:
			hovered = -1
			_select(-1))
	button.focus_entered.connect(func():
		if keyboard_input and not modal:
			_select(group)
			AudioService.play_ui())

func _launch(route: String) -> void:
	if not modal and not AppRouter.busy:
		AudioService.play_ui(1)
		AppRouter.go(route)

## `group` is a tile's index in GameCatalog.GAMES, or -1 for none.
func _select(group: int) -> void:
	showcase.select_group(group)
	hoppy.reaction = GameCatalog.GAMES[group].reaction if group >= 0 else -1

## Booth idle on the hub (AppRouter): back to the state the hub opens in, with nothing selected, so
## a focus left on Endless Runner doesn't keep Hoppy's 3D portrait rendering until the next visitor.
func reset_attract() -> void:
	if modal:
		return
	keyboard_input = false
	hovered = -1
	_select(-1)
	buttons[0].grab_focus()

func _preview_changed(index: int) -> void:
	caption.text = Preview.TITLES[index]
	preview_note.text = Preview.collection(index)
	caption.add_theme_color_override("font_color", Preview.COLORS[index])
	var count: int = showcase.COUNT
	dots.text = " ".join(PackedStringArray(Array(range(count)).map(func(i): return "◆" if i == index else "·"))) + "    %02d / %02d" % [index + 1, count]

func _make_modal(invoker: Control, heading: String) -> VBoxContainer:
	AudioService.play_ui(1)
	modal_return = invoker
	showcase.suspended = true
	for button in buttons:
		button.focus_mode = Control.FOCUS_NONE
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Above a hovered tile, which menu_button.gd raises to z 1 so it grows over its neighbours.
	modal.z_index = 2
	ui.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(330, 140)
	panel.size = Vector2(620, 440)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("122632")
	box.border_color = Style.MINT
	box.set_border_width_all(2)
	box.content_margin_left = 36
	box.content_margin_right = 36
	box.content_margin_top = 28
	box.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", box)
	modal.add_child(panel)
	_layout()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	column.add_child(Style.label(heading, 28))
	return column

func _open_settings(invoker: Control) -> void:
	if modal or AppRouter.busy: return
	var column := _make_modal(invoker, "SETTINGS")
	var first: HSlider
	for bus in ["Master", "Music", "SFX"]:
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := Style.label(bus.to_upper(), 15)
		label.custom_minimum_size.x = 110
		row.add_child(label)
		var slider := HSlider.new()
		slider.name = bus + "Volume"
		slider.custom_minimum_size = Vector2(330, 26)
		slider.max_value = 1
		slider.step = 0.05
		slider.value = SaveService.values[bus]
		row.add_child(slider)
		var value_label := Style.label(str(roundi(slider.value * 100)) + "%", 15)
		row.add_child(value_label)
		slider.value_changed.connect(func(value):
			SaveService.values[bus] = value
			value_label.text = str(roundi(value * 100)) + "%"
			AudioService.apply_volumes())
		if first == null: first = slider
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = SaveService.values.fullscreen
	column.add_child(fullscreen)
	fullscreen.toggled.connect(func(value):
		SaveService.values.fullscreen = value
		SaveService.apply_display())
	var hint := Style.label("", 13, Color("afbdc9"))
	Prompts.track(hint, func() -> String:
		return "%s: select\n%s: confirm   •   %s: back" % [
			Prompts.keys_or_pad("Arrows", Prompts.if_pad("D-pad / stick")),
			Prompts.either("Enter", &"ui_accept"),
			Prompts.either("Esc", &"ui_cancel")])
	column.add_child(hint)
	var close := Style.button("Save & return", 45)
	column.add_child(close)
	close.pressed.connect(_close_modal)
	first.grab_focus()

func _open_quit(invoker: Control) -> void:
	if modal or AppRouter.busy: return
	var column := _make_modal(invoker, "LEAVING THE ARCADE?")
	column.add_child(Style.label("There's always another adventure.", 16))
	var cancel := Style.button("Keep playing")
	column.add_child(cancel)
	cancel.pressed.connect(_close_modal)
	var confirm := Style.button("Quit Game")
	column.add_child(confirm)
	confirm.pressed.connect(func(): AppRouter.quit_game())
	cancel.grab_focus()

func _close_modal() -> void:
	if not modal or AppRouter.busy: return
	if SaveService.persist() != OK:
		if save_warning == null:
			save_warning = Style.label("Settings could not be saved to disk.", 14, Color("ff7185"))
			save_warning.position = Vector2(76, 636)
			ui.add_child(save_warning)
	elif save_warning:
		save_warning.queue_free()
		save_warning = null
	modal.queue_free()
	modal = null
	for button in buttons:
		button.focus_mode = Control.FOCUS_ALL
	showcase.suspended = false
	modal_return.grab_focus()
	if not keyboard_input: _select(-1)
	AudioService.play_ui(1)
