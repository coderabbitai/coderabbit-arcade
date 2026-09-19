extends CanvasLayer
## Graybox game over overlay (contract §5.6). Backend-authored placeholder, frozen after the
## contract PR. ui_cancel is bound here (and only while visible), per contract §4.4.

const Style = preload("res://scenes/main_menu/menu_style.gd")

var game: Node
var score_label: Label
var time_label: Label
var board_label: Label
var name_field: LineEdit
var save_button: Button
var retry_button: Button

func _ready() -> void:
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = Style.theme()
	add_child(ui)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	column.add_child(Style.label("CAUGHT", 40, Color("ff7185")))
	score_label = Style.label("SCORE 0", 26)
	column.add_child(score_label)
	time_label = Style.label("0.0s  •  0 m", 16, Color("afbdc9"))
	column.add_child(time_label)
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 12)
	column.add_child(entry)
	name_field = LineEdit.new()
	name_field.max_length = 16
	name_field.placeholder_text = "Hoppy"
	name_field.custom_minimum_size = Vector2(280, 46)
	entry.add_child(name_field)
	save_button = Style.button("Save", 46)
	save_button.custom_minimum_size.x = 128
	entry.add_child(save_button)
	save_button.pressed.connect(_on_save_pressed)
	board_label = Style.label("", 15, Style.MINT)
	column.add_child(board_label)
	retry_button = Style.button("Retry", 52)
	column.add_child(retry_button)
	retry_button.pressed.connect(func() -> void: _call_game(&"retry"))
	var menu := Style.button("Runner Menu", 52)
	column.add_child(menu)
	menu.pressed.connect(func() -> void: _call_game(&"go_to_menu"))

func bind(runner: Node) -> void:
	game = runner
	runner.run_finished.connect(_on_run_finished)

func _on_run_finished(result: Dictionary) -> void:
	var board: Array = []
	if game != null and game.has_method("get_leaderboard"):
		board = game.get_leaderboard()
	show_result(result, board)

## Contract §5.6: the overlay renders the finished run and the current top 10.
func show_result(result: Dictionary, leaderboard: Array) -> void:
	score_label.text = "SCORE %d" % int(result.get("score", 0))
	time_label.text = "%.1fs  •  %d m" % [float(result.get("duration", 0.0)), int(result.get("distance", 0.0))]
	name_field.text = String(result.get("player_name", ""))
	_render_board(leaderboard)
	visible = true
	retry_button.grab_focus()

func _render_board(leaderboard: Array) -> void:
	var lines := PackedStringArray()
	for i in mini(leaderboard.size(), 10):
		var entry: Dictionary = leaderboard[i]
		lines.append("%2d. %-16s %6d" % [i + 1, String(entry.get("name", "Hoppy")), int(entry.get("score", 0))])
	board_label.text = "\n".join(lines) if not lines.is_empty() else "No runs on the board yet."

func _on_save_pressed() -> void:
	if game == null or not game.has_method("submit_name"):
		return
	if game.submit_name(name_field.text) and game.has_method("get_leaderboard"):
		_render_board(game.get_leaderboard())

func _call_game(method: StringName) -> void:
	if game != null and game.has_method(method):
		game.call(method)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	_call_game(&"go_to_menu")
	get_viewport().set_input_as_handled()
