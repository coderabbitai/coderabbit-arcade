extends Node3D
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const SPEEDS: Array[float] = [0.0, 4.0, 8.0, 12.0, 16.0, 26.0, 32.0]
var _corridor: Node3D
var _pursuit := false
var _speed := 12.0
var _status: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_corridor = Corridor.instantiate()
	add_child(_corridor)
	_corridor.set_scroll_speed(_speed)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 4, 8)
	camera.fov = 60
	add_child(camera)
	camera.look_at(Vector3(0, 1, -8))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(28, 28)
	panel.theme = Style.theme()
	layer.add_child(panel)
	panel.add_child(Style.label("THE CODEBASE CORRIDOR / ENVIRONMENT PREVIEW", 20, Style.MINT))
	panel.add_child(Style.label("1-7  0 / 4 / 8 / 12 / 16 / 26 / 32 m/s    P pursuit    SPACE pause", 14))
	_status = Style.label("", 14)
	panel.add_child(_status)
	_update_status()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key: int = event.physical_keycode
	if key >= KEY_1 and key <= KEY_7:
		_speed = SPEEDS[key - KEY_1]
		_corridor.set_scroll_speed(_speed)
	elif key == KEY_P:
		_pursuit = not _pursuit
		_corridor.set_pursuit(1.0 if _pursuit else 0.0)
	elif key == KEY_SPACE:
		get_tree().paused = not get_tree().paused
	_update_status()

func _update_status() -> void:
	_status.text = "SPEED %02.0f m/s   PURSUIT %s   %s" % [_speed, "ON" if _pursuit else "OFF", "PAUSED" if get_tree().paused else "RUNNING"]

func _exit_tree() -> void:
	get_tree().paused = false
