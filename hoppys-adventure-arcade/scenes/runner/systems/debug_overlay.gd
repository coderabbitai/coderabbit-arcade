extends CanvasLayer
## F3 debug readout plus the developer shortcuts (systems spec §2).
## F3 toggle, F5 retry, F6 runner menu, F7 autopilot, F8 random power-up.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const Style = preload("res://scenes/main_menu/menu_style.gd")
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")
## HitManager.HitState, spelled out here so the overlay never depends on that script loading.
const HIT_STATES := ["SAFE", "PURSUED", "DEAD"]
## How many recent chunk names the readout lists.
const RECENT_CHUNKS := 3

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
	readout.text = "\n".join(PackedStringArray([
		"fps %d  state %s  paused %s" % [Engine.get_frames_per_second(), game.state, game.paused],
		"t %.1fs  d %.2f  dist %.0fm" % [game.elapsed, game.difficulty, game.distance],
		"speed %.1f (n %.2f)" % [game.speed, game.normalized_speed],
		_health_line(),
		"score %d  x%.2f" % [game.score, game.multiplier],
		"effects %s" % _effects_line(),
		"chunks %s  hazards %d  pickups %d" % [_chunk_count(), _group_count(&"runner_hazards"), _group_count(&"runner_pickups")],
		"seed %d  run %s  autopilot %s" % [game.seed, game.run_id, _autopilot_line()],
		"recent %s" % _recent_chunks()
	]))

## hp, the HitManager state, i-frames and the recovery countdown (systems spec §2).
func _health_line() -> String:
	var manager := game.hit_manager
	if manager == null or not is_instance_valid(manager):
		return "hp %d" % game.hp
	var label := "?"
	if &"state" in manager:
		var index := int(manager.get(&"state"))
		label = HIT_STATES[index] if index >= 0 and index < HIT_STATES.size() else str(index)
	var iframes := float(manager.get(&"iframe_remaining")) if &"iframe_remaining" in manager else 0.0
	var recovery := float(manager.get(&"recovery_remaining")) if &"recovery_remaining" in manager else 0.0
	var shield := bool(manager.get(&"shield")) if &"shield" in manager else false
	return "hp %d  %s  iframes %.2f  recovery %.1f  shield %s" % [game.hp, label, iframes, recovery, shield]

func _effects_line() -> String:
	var effects := game.get_active_effects()
	if effects.is_empty():
		return "none"
	var parts := PackedStringArray()
	for kind in effects:
		var entry: Dictionary = effects[kind]
		parts.append("%s %.1f/%.1f" % [kind, float(entry.get("remaining", 0.0)), float(entry.get("total", 0.0))])
	return ", ".join(parts)

func _chunk_count() -> String:
	if not _has_spawner():
		return "n/a"
	return str(_active_chunks().size())

func _autopilot_line() -> String:
	var bot := game.autopilot
	if bot == null or not is_instance_valid(bot) or not (&"enabled" in bot):
		return "n/a"
	return str(bool(bot.get(&"enabled")))

## The last few chunk names, newest first, so a bad seam can be identified from a screenshot.
func _recent_chunks() -> String:
	var chunks := _active_chunks()
	if chunks.is_empty():
		return "none"
	var names := PackedStringArray()
	var index := chunks.size() - 1
	while index >= 0 and names.size() < RECENT_CHUNKS:
		var chunk: Node = chunks[index]
		if chunk != null and is_instance_valid(chunk):
			names.append(String(chunk.name))
		index -= 1
	return ", ".join(names)

func _has_spawner() -> bool:
	return game.spawner != null and is_instance_valid(game.spawner)

func _active_chunks() -> Array:
	if not _has_spawner() or not game.spawner.has_method("get_active_chunks"):
		return []
	return game.spawner.get_active_chunks()

func _group_count(group: StringName) -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	return tree.get_nodes_in_group(group).size()
