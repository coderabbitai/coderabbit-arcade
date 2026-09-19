extends Node3D
const Hoppy = preload("res://scenes/runner/player/hoppy_runner_visual.tscn")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Style = preload("res://scenes/main_menu/menu_style.gd")
const STATES: Array[StringName] = [&"idle", &"run", &"jump", &"fall", &"roll", &"hurt", &"dead"]
var _hoppy: Node3D
var _corridor: Node3D
var _index := 0
var _speed := 0.0
var _status: Label
var _shield := false
var _effects := [false, false, false]

func _ready() -> void:
	_corridor = Corridor.instantiate()
	add_child(_corridor)
	_hoppy = Hoppy.instantiate()
	add_child(_hoppy)
	var camera := Camera3D.new()
	camera.name = "Camera"
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
	panel.add_child(Style.label("HOPPY / F2 VISUAL PREVIEW", 20, Style.MINT))
	panel.add_child(Style.label("1-7 states | SPACE next | [ / ] speed | A / D lean", 14))
	panel.add_child(Style.label("L LGTM | N Nitro | C Code Review | S shield | H hit", 14))
	_status = Style.label("", 14)
	panel.add_child(_status)
	_update_status()

func _process(_delta: float) -> void:
	_hoppy.set_lane_lean(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)))
	_update_status()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key: int = event.physical_keycode
	if key >= KEY_1 and key <= KEY_7:
		_index = key - KEY_1
		_hoppy.set_anim_state(STATES[_index])
	elif key == KEY_SPACE:
		_index = (_index + 1) % STATES.size()
		_hoppy.set_anim_state(STATES[_index])
	elif key == KEY_BRACKETLEFT or key == KEY_BRACKETRIGHT:
		_speed = clampf(_speed + (-0.1 if key == KEY_BRACKETLEFT else 0.1), 0.0, 1.5)
		_hoppy.set_run_speed(_speed)
	elif key == KEY_H:
		_hoppy.on_hit()
	elif key == KEY_S:
		_shield = not _shield
		_hoppy.show_shield(_shield)
	elif key in [KEY_L, KEY_N, KEY_C]:
		var index := [KEY_L, KEY_N, KEY_C].find(key)
		_effects[index] = not _effects[index]
		_hoppy.show_aura([&"lgtm", &"nitro", &"code_review"][index], _effects[index])
	_update_status()

func _update_status() -> void:
	_corridor.set_scroll_speed(12.0 + _speed * 12.0 if _hoppy.anim_state == &"run" else 0.0)
	_status.text = "STATE %s | NORMALIZED SPEED %.1f | SHIELD %s" % [_hoppy.anim_state, _speed, _shield]
