extends Control
## The Endless Runner's local top ten with its Reset scores flow, opened from the runner's pause
## menu. It processes while the run is paused (its parent is the always-processing pause menu).
## `ui_cancel` or `pause` closes the confirmation first, then the panel, and never reaches the run.
## Reset asks twice; a failed reset reloads the rows from disk and reports it.

signal closed

const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Leaderboard = preload("res://scenes/runner/systems/runner_leaderboard.gd")

var leaderboard_path := Leaderboard.DEFAULT_PATH
## The path the open board read, so Reset clears what the player is looking at.
var leaderboard_path_at_open := Leaderboard.DEFAULT_PATH
var board: VBoxContainer
var reset_btn: Button
var close_btn: Button
var reset_confirm: Control
var confirm_status: Label
@onready var audio_service: Node = get_node("/root/AudioService")
@onready var router: Node = get_node("/root/AppRouter")

func _init() -> void:
	name = "Leaderboard"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	theme = Style.theme()
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	Style.polish(panel, true)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(Style.label("LOCAL LEADERBOARD", 28))
	column.add_child(Style.label("RANK  NAME                 SCORE     TIME", 18, Style.MINT))
	board = VBoxContainer.new()
	board.add_theme_constant_override("separation", 8)
	column.add_child(board)
	leaderboard_path_at_open = leaderboard_path
	var entries := Leaderboard.load_entries(leaderboard_path_at_open)
	_build_board_rows(entries)
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	column.add_child(button_row)
	reset_btn = Style.button("Reset scores", 46)
	reset_btn.name = "ResetScoresButton"
	reset_btn.disabled = entries.is_empty()
	reset_btn.focus_entered.connect(_focus_sound)
	reset_btn.mouse_entered.connect(_focus_sound)
	reset_btn.pressed.connect(_open_reset_confirm)
	button_row.add_child(reset_btn)
	close_btn = Style.button("Close", 46)
	close_btn.name = "CloseButton"
	close_btn.focus_entered.connect(_focus_sound)
	close_btn.mouse_entered.connect(_focus_sound)
	close_btn.pressed.connect(close)
	button_row.add_child(close_btn)
	_wrap_pair(reset_btn, close_btn)
	close_btn.grab_focus()

func _panel_style() -> StyleBoxFlat:
	var box := Style.panel(Style.MINT, 0.96)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 20
	box.content_margin_bottom = 20
	return box

## Focus wraps between two buttons in every direction.
static func _wrap_pair(a: Button, b: Button) -> void:
	for pair in [[a, b], [b, a]]:
		var from: Button = pair[0]
		var to: NodePath = from.get_path_to(pair[1])
		from.focus_neighbor_left = to
		from.focus_neighbor_right = to
		from.focus_neighbor_top = to
		from.focus_neighbor_bottom = to
		from.focus_next = to
		from.focus_previous = to

func _focus_sound() -> void:
	if not router.busy:
		audio_service.play_ui(0)

func _build_board_rows(entries: Array[Dictionary]) -> void:
	for child in board.get_children():
		child.queue_free()
	for i in 10:
		var text := "%02d    ---                  ---       ---" % (i + 1)
		if i < entries.size():
			var entry: Dictionary = entries[i]
			var seconds := maxi(0, int(entry.duration))
			text = "%02d    %-16s  %8d     %02d:%02d" % [i + 1, entry.name, entry.score, seconds / 60, seconds % 60]
		var row := HBoxContainer.new()
		row.add_child(rank_marker(i, i < entries.size()))
		row.add_child(Style.label(text, 18))
		board.add_child(row)

func close() -> void:
	if router.busy:
		return
	audio_service.play_ui(1)
	closed.emit()
	queue_free()

func _open_reset_confirm() -> void:
	if reset_confirm or router.busy:
		return
	audio_service.play_ui(1)
	reset_btn.disabled = true
	close_btn.disabled = true
	reset_confirm = Control.new()
	reset_confirm.name = "ResetConfirm"
	reset_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(reset_confirm)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reset_confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset_confirm.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	Style.polish(panel, true)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	column.add_child(Style.label("RESET ALL SCORES?", 28))
	column.add_child(Style.label("This deletes the top ten and cannot be undone.", 18))
	var keep := Style.button("Keep scores", 46)
	keep.name = "KeepScoresButton"
	keep.focus_entered.connect(_focus_sound)
	keep.mouse_entered.connect(_focus_sound)
	keep.pressed.connect(_close_reset_confirm)
	column.add_child(keep)
	var do_reset := Style.button("Reset", 46)
	do_reset.name = "ResetConfirmButton"
	do_reset.focus_entered.connect(_focus_sound)
	do_reset.mouse_entered.connect(_focus_sound)
	do_reset.pressed.connect(_confirm_reset)
	column.add_child(do_reset)
	confirm_status = Style.label("", 16, Color("ff7185"))
	confirm_status.name = "StatusLabel"
	confirm_status.visible = false
	column.add_child(confirm_status)
	_wrap_pair(keep, do_reset)
	keep.grab_focus()

func _close_reset_confirm() -> void:
	if not reset_confirm:
		return
	reset_confirm.queue_free()
	reset_confirm = null
	confirm_status = null
	if is_instance_valid(reset_btn):
		reset_btn.disabled = false
		reset_btn.grab_focus()
	if is_instance_valid(close_btn):
		close_btn.disabled = false
	audio_service.play_ui(1)

func _confirm_reset() -> void:
	if router.busy:
		return
	var error := Leaderboard.clear(leaderboard_path_at_open)
	if error == OK:
		reset_confirm.queue_free()
		reset_confirm = null
		confirm_status = null
		_build_board_rows(Leaderboard.load_entries(leaderboard_path_at_open))
		if is_instance_valid(reset_btn):
			reset_btn.disabled = true
		if is_instance_valid(close_btn):
			close_btn.disabled = false
			close_btn.grab_focus()
		audio_service.play_ui(1)
	else:
		# clear() may have written an empty primary before the .bak/.tmp removal failed: reload
		# the rows so the board matches what is on disk.
		var entries_after := Leaderboard.load_entries(leaderboard_path_at_open)
		_build_board_rows(entries_after)
		if is_instance_valid(reset_btn):
			reset_btn.disabled = entries_after.is_empty()
		if confirm_status != null:
			confirm_status.text = "Could not reset scores."
			confirm_status.visible = true
		var keep_btn := reset_confirm.find_child("KeepScoresButton", true, false) as Button
		if keep_btn != null:
			keep_btn.grab_focus()

## Back (Esc, B) or Start closes the confirmation first, then the board. Handled in _input so the
## press never also reaches the runner's pause toggle.
func _input(event: InputEvent) -> void:
	if not visible or router.busy:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if reset_confirm:
			_close_reset_confirm()
		else:
			close()
		get_viewport().set_input_as_handled()

static func rank_marker(index: int, occupied: bool) -> Control:
	if occupied and index < 3:
		return Style.icon(&"medal", [Palette.CREAM.lerp(Palette.ORANGE, 0.35), Palette.SLATE.lerp(Palette.CREAM, 0.65), Palette.ORANGE.lerp(Palette.NAVY_2, 0.3)][index], Vector2(24, 24))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 24)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
