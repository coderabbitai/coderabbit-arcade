extends "res://app/pause_menu.gd"
## The runner's pause menu: the shared menu (app/pause_menu.gd), whose Leaderboard button reads
## the run's own board (`game.leaderboard_path`, which a test or capture can point elsewhere).
## Display only: the facade owns pause state and input, and this menu binds neither `pause` nor
## `ui_cancel`.

var game: Node

func bind(runner: Node) -> void:
	game = runner
	setup("runner_game",
		func() -> void: _call_game(&"resume"),
		func() -> void: _call_game(&"retry"),
		func() -> void: _call_game(&"go_to_menu"))
	runner.paused_changed.connect(_on_paused_changed)
	_on_paused_changed(runner.paused)

func _on_paused_changed(is_paused: bool) -> void:
	if is_paused:
		open()
	else:
		close()

## The board is read when it opens, so a path changed after bind() (tests) is honoured.
func _open_leaderboard() -> void:
	if game != null:
		leaderboard_path = game.leaderboard_path
	super._open_leaderboard()

func _call_game(method: StringName) -> void:
	if game != null and game.has_method(method):
		game.call(method)
