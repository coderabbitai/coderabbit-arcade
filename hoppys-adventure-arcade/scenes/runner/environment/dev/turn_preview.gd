extends Node3D
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Style = preload("res://scenes/runner/ui/hud_style.gd")
var corridor: Node3D
var progress := 0.0
var direction := 1
var playing := false
var readout: Label
var _previous_paused := false

func _ready() -> void:
	_previous_paused = get_tree().paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	corridor = Corridor.instantiate()
	add_child(corridor)
	corridor.set_scroll_speed(20.0)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 4, 8)
	camera.fov = 60
	add_child(camera)
	camera.look_at(Vector3(0, 1, -8))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(28, 28)
	panel.add_theme_stylebox_override("panel", Style.panel(Style.MINT))
	layer.add_child(panel)
	readout = Style.label("", 20)
	panel.add_child(readout)
	_process(0.0)

func _process(delta: float) -> void:
	if playing and not get_tree().paused:
		progress = minf(1.0, progress + delta / 2.5)
		corridor.set_turn(progress, direction)
		if progress >= 1.0: playing = false
	var calls := get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	readout.text = "LEFT / RIGHT play   [ / ] scrub   SPACE pause\np %.2f   direction %+d   bend %.5f   yaw %.1f°   draw calls %d" % [progress, direction, corridor.bend, corridor.rotation_degrees.y, calls]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_LEFT, KEY_RIGHT:
			direction = -1 if event.physical_keycode == KEY_LEFT else 1
			progress = 0.0
			playing = true
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if get_tree().paused: return
			playing = false
			progress = clampf(progress + (-0.05 if event.physical_keycode == KEY_BRACKETLEFT else 0.05), 0, 1)
			corridor.set_turn(progress, direction)
		KEY_SPACE: get_tree().paused = not get_tree().paused

func _exit_tree() -> void:
	get_tree().paused = _previous_paused
