extends CanvasLayer
## F3 debug readout plus the developer shortcuts (systems spec §2).
## F3 toggle, F5 retry, F6 runner menu, F7 autopilot, F8 random power-up.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const Style = preload("res://scenes/main_menu/menu_style.gd")
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")

var game: RunnerGame
var readout: Label
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	readout = Style.label("", 13, Style.MINT)
	readout.position = Vector2(18, 18)
	readout.visible = false
	add_child(readout)

func setup(runner: RunnerGame) -> void:
	game = runner

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F3:
			readout.visible = not readout.visible
		KEY_F5:
			if game != null:
				game.retry()
		KEY_F6:
			if game != null:
				game.go_to_menu()
		KEY_F7:
			# The bot and the power-up cheat ship only in debug builds; F3 stays everywhere.
			if not OS.is_debug_build():
				return
			if game != null and game.autopilot != null:
				game.set_autopilot(not game.autopilot.enabled)
		KEY_F8:
			if not OS.is_debug_build():
				return
			if game != null and game.effect_manager != null:
				var kinds := PowerUpDefs.kinds()
				game.effect_manager.apply(kinds[rng.randi_range(0, kinds.size() - 1)])
		_:
			return
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not readout.visible or game == null:
		return
	# The systems are wired in _ready; the readout must survive a frame where one is still missing.
	var chunks := "n/a"
	if game.spawner != null:
		chunks = str(game.spawner.get_active_chunks().size())
	var bot := "n/a"
	if game.autopilot != null:
		bot = str(game.autopilot.enabled)
	readout.text = "\n".join(PackedStringArray([
		"state %s  paused %s  seed %d" % [game.state, game.paused, game.seed],
		"t %.1fs  d %.2f  dist %.0fm" % [game.elapsed, game.difficulty, game.distance],
		"speed %.1f (n %.2f)" % [game.speed, game.normalized_speed],
		"hp %d  score %d  x%.2f" % [game.hp, game.score, game.multiplier],
		"chunks %s  autopilot %s" % [chunks, bot]
	]))
