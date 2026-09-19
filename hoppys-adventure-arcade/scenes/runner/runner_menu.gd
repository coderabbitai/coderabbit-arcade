extends Node3D
## Graybox Endless Runner menu (contract §2). Backend-authored placeholder: the frontend may
## overwrite or delete it freely. It carries the four contract §2 buttons -- 01 Play,
## 02 Leaderboard, 03 Return to Main Menu, 04 Quit Game -- so the graybox and the frontend menu
## answer the same structural check.

const Style = preload("res://scenes/main_menu/menu_style.gd")
const RunnerLeaderboard = preload("res://scenes/runner/systems/runner_leaderboard.gd")
## Blank rows keep the panel the same height whatever the board holds (contract §4.3, 10 entries).
const EMPTY_ROW := "---"

var buttons: Array[Button] = []

var _board_panel: PanelContainer
var _board_rows: VBoxContainer

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
	var play := Style.button("01 Play")
	column.add_child(play)
	buttons.append(play)
	play.pressed.connect(func() -> void: AppRouter.go("runner_game"))
	var board := Style.button("02 Leaderboard", 52)
	column.add_child(board)
	buttons.append(board)
	board.pressed.connect(_toggle_board)
	var back := Style.button("03 Return to Main Menu", 52)
	column.add_child(back)
	buttons.append(back)
	back.pressed.connect(func() -> void: AppRouter.go("hub"))
	var quit := Style.button("04 Quit Game", 52)
	column.add_child(quit)
	buttons.append(quit)
	quit.pressed.connect(func() -> void: AppRouter.quit_game())
	_board_panel = _build_board_panel()
	column.add_child(_board_panel)
	for i in buttons.size():
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
	play.grab_focus()

## Contract §4.3: the menu has no game instance, so the board comes from the static reader. Read on
## every open, because a run finished since the last one may have changed it.
func _toggle_board() -> void:
	if _board_panel == null:
		return
	if _board_panel.visible:
		_board_panel.hide()
		return
	_fill_board()
	_board_panel.show()

func _build_board_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "LeaderboardPanel"
	panel.hide()
	_board_rows = VBoxContainer.new()
	_board_rows.add_theme_constant_override("separation", 4)
	panel.add_child(_board_rows)
	return panel

func _fill_board() -> void:
	if _board_rows == null:
		return
	for child in _board_rows.get_children():
		_board_rows.remove_child(child)
		child.queue_free()
	_board_rows.add_child(Style.label("TOP 10", 18, Style.MINT))
	var entries := RunnerLeaderboard.load_entries()
	for i in RunnerLeaderboard.MAX_ENTRIES:
		_board_rows.add_child(Style.label(_board_line(i, entries), 14, Color("afbdc9")))

## "%2d. <name> <score> <mm:ss>", or the blank row when the board is shorter than 10.
func _board_line(index: int, entries: Array[Dictionary]) -> String:
	if index >= entries.size():
		return "%2d. %s" % [index + 1, EMPTY_ROW]
	var entry := entries[index]
	var duration := int(float(entry.get("duration", 0.0)))
	return "%2d. %-16s %7d  %02d:%02d" % [
		index + 1, String(entry.get("name", RunnerLeaderboard.FALLBACK_NAME)),
		int(entry.get("score", 0)), duration / 60, duration % 60
	]

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# The panel closes first, exactly like the frontend menu (codex brief §4.10).
	if _board_panel != null and _board_panel.visible:
		_board_panel.hide()
		get_viewport().set_input_as_handled()
		return
	AppRouter.go("hub")
	get_viewport().set_input_as_handled()
