extends Node3D
## Graybox Endless Runner menu (contract §2). Backend-authored placeholder: frozen after the
## contract PR, and the frontend may overwrite or delete it freely.

const Style = preload("res://scenes/main_menu/menu_style.gd")

var buttons: Array[Button] = []

func _ready() -> void:
	var interface := CanvasLayer.new()
	interface.name = "Interface"
	add_child(interface)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = Style.theme()
	interface.add_child(ui)
	var background := ColorRect.new()
	background.color = Color("101d2d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)
	column.add_child(Style.label("ENDLESS RUNNER", 42))
	column.add_child(Style.label("The Codebase Corridor", 18, Style.MINT))
	column.add_child(Style.label("A / D or ← → lanes   •   Space jump   •   Ctrl roll   •   Esc pause", 14, Color("afbdc9")))
	var play := Style.button("Play")
	column.add_child(play)
	buttons.append(play)
	play.pressed.connect(func() -> void: AppRouter.go("runner_game"))
	var back := Style.button("Return to Main Menu", 52)
	column.add_child(back)
	buttons.append(back)
	back.pressed.connect(func() -> void: AppRouter.go("hub"))
	var quit := Style.button("Quit Game", 52)
	column.add_child(quit)
	buttons.append(quit)
	quit.pressed.connect(func() -> void: AppRouter.quit_game())
	for i in buttons.size():
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
	play.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AppRouter.go("hub")
		get_viewport().set_input_as_handled()
