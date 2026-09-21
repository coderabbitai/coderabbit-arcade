extends CanvasLayer
const Tally = preload("res://scenes/runner/ui/hifi/result_tally.gd")
const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var game: Node
var panel: PanelContainer
var dim: ColorRect
var stats: GridContainer
var name_row: HBoxContainer
var name_field: LineEdit
var save_button: Button
var retry_button: Button
var menu_button: Button
var board: VBoxContainer
var error_label: Label
var result := {}
var saved := false

func _ready() -> void:
	var screen := Control.new()
	screen.name = "Screen"
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = Style.theme()
	dim = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.88)
	screen.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var box := Style.panel(Palette.DANGER)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", box)
	Style.polish(panel, false)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(Style.label("CAUGHT BY THE BACKLOG", 34, Palette.DANGER))
	stats = GridContainer.new()
	stats.name = "Stats"
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 32)
	column.add_child(stats)
	name_row = HBoxContainer.new()
	name_row.name = "NameRow"
	column.add_child(name_row)
	name_field = LineEdit.new()
	name_field.name = "NameEdit"
	name_field.max_length = 16
	name_field.placeholder_text = "Hoppy"
	name_field.custom_minimum_size = Vector2(330, 36)
	var field_normal := Style.panel(Palette.SLATE, 0.96)
	var field_focus := Style.panel(Palette.MINT, 0.0)
	field_focus.draw_center = false
	name_field.add_theme_stylebox_override("normal", field_normal)
	name_field.add_theme_stylebox_override("focus", field_focus)
	name_field.add_theme_color_override("font_color", Palette.CREAM)
	name_field.add_theme_color_override("caret_color", Palette.MINT)
	name_field.add_theme_color_override("selection_color", Palette.SLATE)
	name_field.add_theme_color_override("font_selected_color", Palette.CREAM)
	name_row.add_child(name_field)
	save_button = Style.button("Save", 36)
	save_button.custom_minimum_size.x = 160
	name_row.add_child(save_button)
	save_button.pressed.connect(_save)
	name_field.text_submitted.connect(func(_text: String) -> void: _save())
	name_field.gui_input.connect(_name_input)
	error_label = Style.label("", 18, Palette.DANGER)
	error_label.hide()
	column.add_child(error_label)
	column.add_child(Style.label("TOP 10", 19, Palette.MINT))
	board = VBoxContainer.new()
	board.add_theme_constant_override("separation", 1)
	column.add_child(board)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)
	retry_button = Style.button("Retry")
	menu_button = Style.button("Runner Menu")
	for button in [retry_button, menu_button]:
		button.custom_minimum_size.x = 280
		actions.add_child(button)
	retry_button.pressed.connect(func() -> void: game.retry())
	menu_button.pressed.connect(func() -> void: game.go_to_menu())
	hide()

func bind(runner: Node) -> void:
	game = runner
	game.run_finished.connect(_finished)

func _finished(value: Dictionary) -> void:
	show_result(value, game.get_leaderboard())

func show_result(value: Dictionary, leaderboard: Array) -> void:
	result = value.duplicate(true)
	saved = false
	var can_save := _can_save_result()
	save_button.disabled = not can_save
	save_button.text = "Save"
	name_field.editable = can_save
	name_field.text = String(result.get("player_name", ""))
	name_row.visible = can_save
	error_label.text = "Leaderboard could not be saved." if int(result.get("leaderboard_error", OK)) != OK else ""
	error_label.visible = not error_label.text.is_empty()
	for child in stats.get_children():
		child.free()
	var lines := ["SCORE %08d" % int(result.get("score", 0)), "TIME " + _time(float(result.get("duration", 0))),
		"DISTANCE %d m" % int(result.get("distance", 0)), "DODGED %d" % int(result.get("hazards_dodged", 0)),
		"POWER-UPS %d" % int(result.get("power_ups", 0)), "RANK %s" % (str(result.get("rank", 0)) if int(result.get("rank", 0)) > 0 else "UNPLACED")]
	for i in lines.size():
		var stat := Style.label(lines[i], 22, Palette.MINT if i == 0 else Palette.CREAM)
		stats.add_child(stat)
		var tally := Tally.new()
		tally.delay = i * 0.045
		stat.add_child(tally)
	_render_board(leaderboard)
	visible = true
	dim.modulate.a = 0
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
	panel.modulate.a = 0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.2)
	_focus_chain()
	if name_row.visible:
		name_field.grab_focus()
		name_field.select_all()
	else:
		retry_button.grab_focus()

func _time(seconds: float) -> String:
	return "%02d:%04.1f" % [int(seconds) / 60, fmod(seconds, 60)]

func _render_board(entries: Array) -> void:
	for child in board.get_children():
		child.free()
	for i in mini(10, entries.size()):
		var entry: Dictionary = entries[i]
		var seconds := int(entry.get("duration", 0))
		var current := String(entry.get("run_id", "")) == String(result.get("run_id", ""))
		var row := Style.label("%2d  %-16s %8d  %02d:%02d" % [i + 1, String(entry.get("name", "Hoppy")), int(entry.get("score", 0)), seconds / 60, seconds % 60], 19, Palette.MINT if current else Palette.CREAM)
		row.set_meta("current_run", current)
		board.add_child(row)
	if entries.is_empty():
		board.add_child(Style.label("No runs on the board yet.", 19))

func _focus_chain() -> void:
	var controls: Array[Control] = [retry_button, menu_button]
	if name_row.visible and not saved:
		controls = [name_field, save_button, retry_button, menu_button]
	for i in controls.size():
		var previous := controls[i].get_path_to(controls[posmod(i - 1, controls.size())])
		var next := controls[i].get_path_to(controls[(i + 1) % controls.size()])
		controls[i].focus_previous = previous
		controls[i].focus_next = next
		controls[i].focus_neighbor_top = previous
		controls[i].focus_neighbor_bottom = next
		controls[i].focus_neighbor_left = previous
		controls[i].focus_neighbor_right = next

func _can_save_result() -> bool:
	return bool(result.get("qualifies", false)) and int(result.get("leaderboard_error", OK)) == OK

func _save() -> void:
	if saved or not _can_save_result() or not visible or not name_row.visible or game == null:
		return
	if not game.submit_name(name_field.text):
		error_label.text = "Could not save to disk."
		error_label.show()
		return
	saved = true
	save_button.disabled = true
	save_button.text = "SAVED"
	name_field.editable = false
	name_field.text = String(game.get_result().get("player_name", name_field.text))
	error_label.hide()
	_render_board(game.get_leaderboard())
	_focus_chain()
	retry_button.grab_focus()

func _name_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down") and not saved:
		save_button.grab_focus()
		name_field.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if game != null and visible and event.is_action_pressed("ui_cancel"):
		game.go_to_menu()
		get_viewport().set_input_as_handled()
