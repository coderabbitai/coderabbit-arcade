extends "res://app/pause_menu.gd"
## The runner's pause menu: the shared menu (app/pause_menu.gd) plus a Leaderboard button that
## opens the local top ten with its Reset scores flow over the paused run. Display only: the facade
## owns pause state and input, and this menu binds neither `pause` nor `ui_cancel`.

const LeaderboardPanel := preload("res://scenes/runner/ui/leaderboard_panel.gd")

var game: Node
var leaderboard_button: Button
## The open leaderboard panel, or null.
var leaderboard: Control

func bind(runner: Node) -> void:
	game = runner
	setup("runner_game",
		func() -> void: _call_game(&"resume"),
		func() -> void: _call_game(&"retry"),
		func() -> void: _call_game(&"go_to_menu"))
	leaderboard_button = add_button("Leaderboard", _open_leaderboard)
	runner.paused_changed.connect(_on_paused_changed)
	_on_paused_changed(runner.paused)

func _on_paused_changed(is_paused: bool) -> void:
	if is_paused:
		open()
	else:
		close()

## Closing the menu (resume, pad reconnect, a route change) takes the leaderboard with it.
func close() -> void:
	if is_instance_valid(leaderboard):
		leaderboard.closed.disconnect(_on_leaderboard_closed)
		leaderboard.queue_free()
		leaderboard = null
		_set_menu_enabled(true)
	super.close()

func _open_leaderboard() -> void:
	if leaderboard != null or game == null:
		return
	_set_menu_enabled(false)
	leaderboard = LeaderboardPanel.new()
	leaderboard.leaderboard_path = game.leaderboard_path
	leaderboard.closed.connect(_on_leaderboard_closed)
	ui.add_child(leaderboard)

func _on_leaderboard_closed() -> void:
	leaderboard = null
	_set_menu_enabled(true)
	if visible:
		leaderboard_button.grab_focus()

## The board owns the screen while it is up: the menu's own buttons can't be reached.
func _set_menu_enabled(enabled: bool) -> void:
	for button in buttons:
		button.disabled = not enabled or locked
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func _call_game(method: StringName) -> void:
	if game != null and game.has_method(method):
		game.call(method)
