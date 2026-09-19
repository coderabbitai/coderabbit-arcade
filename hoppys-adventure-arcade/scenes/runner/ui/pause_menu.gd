extends CanvasLayer
## Graybox pause menu (contract §5.6). Backend-authored placeholder, frozen after the contract PR.
## It deliberately does NOT bind ui_cancel: RunnerGame owns the `pause` action.

const Style = preload("res://scenes/main_menu/menu_style.gd")

var game: Node
var resume_button: Button

func _ready() -> void:
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = Style.theme()
	add_child(ui)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	column.add_child(Style.label("PAUSED", 40))
	var buttons: Array[Button] = []
	resume_button = Style.button("Resume")
	column.add_child(resume_button)
	buttons.append(resume_button)
	resume_button.pressed.connect(func() -> void: _call_game(&"resume"))
	var restart := Style.button("Restart", 52)
	column.add_child(restart)
	buttons.append(restart)
	restart.pressed.connect(func() -> void: _call_game(&"retry"))
	var menu := Style.button("Runner Menu", 52)
	column.add_child(menu)
	buttons.append(menu)
	menu.pressed.connect(func() -> void: _call_game(&"go_to_menu"))
	for i in buttons.size():
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])

func bind(runner: Node) -> void:
	game = runner
	runner.paused_changed.connect(_on_paused_changed)

func _on_paused_changed(is_paused: bool) -> void:
	visible = is_paused
	if is_paused:
		resume_button.grab_focus()

func _call_game(method: StringName) -> void:
	if game != null and game.has_method(method):
		game.call(method)
