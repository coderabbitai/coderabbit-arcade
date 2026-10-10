extends CanvasLayer
## Pause display only. The facade owns pause state and input.
## It deliberately does NOT bind ui_cancel: RunnerGame owns the `pause` action.

const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Prompts := preload("res://app/controller_prompts.gd")

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
	var panel := PanelContainer.new()
	var box := Style.panel(Style.MINT)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 24
	box.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", box)
	Style.polish(panel, false)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	column.add_child(Style.label("PAUSED", 46))
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
	var resume_hint := Style.label("", 20, Style.MINT)
	Prompts.track(resume_hint, func() -> String:
		return "%s  resume" % Prompts.either("ESC", &"pause", true))
	column.add_child(resume_hint)
	for i in buttons.size():
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
		buttons[i].focus_next = buttons[i].focus_neighbor_bottom
		buttons[i].focus_previous = buttons[i].focus_neighbor_top

func bind(runner: Node) -> void:
	game = runner
	runner.paused_changed.connect(_on_paused_changed)
	_on_paused_changed(runner.paused)

func _on_paused_changed(is_paused: bool) -> void:
	visible = is_paused
	if is_paused:
		resume_button.grab_focus()

func _call_game(method: StringName) -> void:
	if game != null and game.has_method(method):
		game.call(method)
