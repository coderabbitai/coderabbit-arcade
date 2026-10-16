extends Node2D
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Preview = preload("res://scenes/main_menu/preview.gd")
const Prompts := preload("res://app/controller_prompts.gd")
@onready var showcase = $Showcase
@onready var hoppy = $Interface/Hoppy
var ui: Control
var buttons: Array[Button] = []
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
	gradient.set_color(1, Color(0.025, 0.045, 0.08, 0.15))
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
	footer_texture.fill_from = Vector2(0, 0.65)
	footer_texture.fill_to = Vector2(0, 0.92)
	footer_shade.texture = footer_texture
	footer_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(footer_shade)
	hoppy.reparent(ui)
	var eyebrow := Style.label("C O D E R A B B I T   /   A R C A D E", 14, Style.MINT)
	eyebrow.position = Vector2(76, 39)
	ui.add_child(eyebrow)
	title = VBoxContainer.new()
	title.position = Vector2(72, 96)
	title.add_theme_constant_override("separation", -12)
	ui.add_child(title)
	title.add_child(Style.label("HOPPY'S", 68))
	title.add_child(Style.label("ADVENTURE", 49))
	title.add_child(Style.label("A R C A D E", 30, Color("f5a568")))
	var subtitle := Style.label("THREE WAYS TO PLAY. ONE HOPPY.", 13, Color("afbdc9"))
	subtitle.position = Vector2(77, 284)
	ui.add_child(subtitle)
	var column := VBoxContainer.new()
	column.position = Vector2(76, 328)
	column.add_theme_constant_override("separation", 12)
	ui.add_child(column)
	var names := ["01   Platformer Game", "02   Endless Runner", "03   Beat'em Up"]
	var routes := ["platformer", "runner", "beatem_up"]
	for i in 3:
		var button := Style.button(names[i])
		column.add_child(button)
		buttons.append(button)
		_connect_button(button, i)
		button.pressed.connect(_launch.bind(routes[i]))
	var utilities := HBoxContainer.new()
	utilities.position = Vector2(76, 568)
	# Wider than the focus arrow's 25 px reach, so it never sits on the neighbouring button.
	utilities.add_theme_constant_override("separation", 28)
	ui.add_child(utilities)
	for i in 2:
		var button := Style.button("Settings" if i == 0 else "Quit Game", 46)
		button.custom_minimum_size.x = 160
		utilities.add_child(button)
		buttons.append(button)
		_connect_button(button, -1)
		button.pressed.connect(_open_settings.bind(button) if i == 0 else _open_quit.bind(button))
	# Last in `buttons`, so buttons[3] and buttons[4] stay Settings and Quit Game.
	var credits := Style.button("Credits", 46)
	credits.name = "CreditsButton"
	credits.custom_minimum_size.x = 160
	utilities.add_child(credits)
	buttons.append(credits)
	_connect_button(credits, -1)
	credits.pressed.connect(_launch.bind("credits"))
	for i in buttons.size():
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
	var footer := Style.label("", 12, Color("9baebc"))
	Prompts.track(footer, func() -> String:
		return "↑ ↓  SELECT     %s  CONFIRM" % Prompts.either("ENTER", &"ui_accept", true))
	footer.position = Vector2(76, 670)
	ui.add_child(footer)
	caption = Style.label("", 21)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.position = Vector2(640, 592)
	caption.size.x = 560
	ui.add_child(caption)
	dots = Style.label("", 15, Style.MINT)
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dots.position = Vector2(640, 628)
	dots.size.x = 560
	ui.add_child(dots)
	preview_note = Style.label("WORLD PREVIEW", 12, Color("afbdc9"))
	preview_note.position = Vector2(640, 566)
	preview_note.size.x = 560
	preview_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(preview_note)
	showcase.preview_changed.connect(_preview_changed)
	_preview_changed(showcase.active_index)
	get_viewport().size_changed.connect(_layout)
	# Deferred: sizing full-rect-anchored controls inside _ready is overridden (and warned about).
	_layout.call_deferred()
	buttons[0].grab_focus()

func _process(delta: float) -> void:
	elapsed += delta
	title.position.y = 96 + sin(elapsed * PI) * 3

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
	hoppy.position = Vector2(964, 552)

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
			_select(id if id < 3 else -1)
	if event.is_action_pressed("ui_cancel"):
		if modal:
			_close_modal()
		else:
			_open_quit(buttons[4])
		get_viewport().set_input_as_handled()

func _connect_button(button: Button, group: int) -> void:
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

func _select(group: int) -> void:
	showcase.select_group(group)
	hoppy.reaction = group

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
