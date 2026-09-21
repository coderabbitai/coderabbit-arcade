extends Node3D
## Standalone fixture. Keys 1-7 select looks; 0 toggles post.
const PostFX = preload("res://scenes/runner/ui/post_fx.tscn")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")

class StubGame extends Node:
	signal run_started(seed_value: int)
	signal damage_taken(kind: StringName, hp: int)
	signal tool_collected(kind: StringName, damage: int)
	signal pursuit_started(seconds: float)
	signal pursuit_progress(remaining: float, total: float)
	signal pursuit_recovered(reason: StringName)
	signal caught
	signal speed_changed(meters: float, normalized: float)
	signal power_up_collected(kind: StringName, duration: float)
	signal power_up_expired(kind: StringName)
	signal boss_intro(kind: StringName, boss_name: String, seconds: float)
	signal stage_cleared(index: int, bonus: int)
	signal phase_changed(phase: StringName)
	signal run_finished(result: Dictionary)
	signal paused_changed(value: bool)

var game := StubGame.new()
var post: CanvasLayer
var camera := Camera3D.new()
var corridor: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	corridor = Corridor.instantiate()
	add_child(corridor)
	corridor.set_scroll_speed(26.0)
	var hoppy := Hoppy.instantiate()
	add_child(hoppy)
	hoppy.set_anim_state(&"run")
	hoppy.set_run_speed(0.75)
	camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(camera)
	camera.current = true
	post = PostFX.instantiate()
	add_child(post)
	post.bind(game)
	set_view(0)

func set_view(index: int) -> void:
	post.set_settings(post.DEFAULT_SETTINGS)
	game.run_started.emit(90210)
	camera.position = Vector3(0.0, 4.0, 8.0)
	camera.fov = 60.0
	camera.look_at(Vector3(0.0, 1.0, -8.0))
	match index:
		0:
			game.speed_changed.emit(26.0, 0.75)
		1:
			camera.position = Vector3(1.5, 2.2, 3.8)
			camera.look_at(Vector3(0.0, 1.0, 0.0))
			game.power_up_collected.emit(&"nitro", 6.0)
			game.speed_changed.emit(32.0, 1.0)
		2:
			# Explicit opt-in: this isolated fixture has no HUD pursuit overlay.
			post.set_settings({"pursuit": true})
			game.pursuit_started.emit(6.0)
			game.pursuit_progress.emit(1.0, 6.0)
		3:
			game.boss_intro.emit(&"legacy_monolith", "Legacy Monolith", 3.0)
		4:
			game.stage_cleared.emit(2, 2500)

		5, 6:
			for key: String in post.settings:
				post.set_settings({key: false})
			post.set_settings({"grade": index == 6})

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not get_tree().paused:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_7:
			set_view(event.physical_keycode - KEY_1)
		elif event.physical_keycode == KEY_0:
			post.visible = not post.visible
