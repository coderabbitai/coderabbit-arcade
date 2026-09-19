extends Node3D
const HazardVisualBase = preload("res://scenes/runner/hazards/hazard_visual_base.gd")
const PowerUpVisualBase = preload("res://scenes/runner/powerups/power_up_visual_base.gd")
const PursuerVisualBase = preload("res://scenes/runner/pursuer/pursuer_visual_base.gd")
const CorridorScript = preload("res://scenes/runner/environment/corridor.gd")
const Corridor = preload("res://scenes/runner/environment/corridor.tscn")
const Materials = preload("res://scenes/runner/environment/runner_materials.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Style = preload("res://scenes/main_menu/menu_style.gd")
# Independent transcription of contract section 8, also used by the visual smoke.
const CASES := [
	[&"pr_backlog_low", &"", Vector3(5.6, 1, 1.2), 0.5, 7, &"JUMP"],
	[&"pr_backlog_high", &"", Vector3(5.6, 1.8, 1.2), 2.0, 7, &"ROLL"],
	[&"bug_swarm", &"", Vector3(1.6, 0.9, 1.2), 0.45, 2, &"JUMP_OR_LANE"],
	[&"merge_conflict", &"", Vector3(3.6, 1, 1.2), 0.5, 3, &"JUMP_OR_LANE"],
	[&"deprecated_pit", &"full", Vector3(5.6, 0.4, 3), 0.0, 7, &"JUMP"],
	[&"deprecated_pit", &"two_lane", Vector3(3.6, 0.4, 3), 0.0, 3, &"JUMP_OR_LANE"],
	[&"laser_grid", &"ground", Vector3(5.6, 0.4, 1.2), 0.3, 7, &"JUMP"],
	[&"laser_grid", &"mid", Vector3(5.6, 0.3, 1.2), 1.15, 7, &"ROLL_OR_JUMP"],
	[&"laser_grid", &"high", Vector3(5.6, 0.4, 1.2), 1.3, 7, &"ROLL"],
	[&"laser_grid", &"timed", Vector3(5.6, 0.4, 1.2), 0.3, 7, &"TIMED"],
	[&"comment_flood", &"", Vector3(3.6, 4, 1.2), 2.0, 3, &"LANE"],
	[&"build_shockwave", &"", Vector3(5.6, 0.5, 1.2), 0.25, 7, &"JUMP"],
]
const POWERUPS := [&"approve_shield", &"auto_fix", &"lgtm", &"nitro", &"super_jump", &"code_review"]
var pickups: Array[PowerUpVisualBase] = []
var fixtures: Array[Node3D] = []
var pursuer: PursuerVisualBase
var _threat_slider: HSlider
var visuals: Array[HazardVisualBase] = []
var wires: Array[MeshInstance3D] = []
var _camera: Camera3D
var _status: Label
var _selected := 0
var _sweep := false
var _t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var corridor := Corridor.instantiate() as CorridorScript
	corridor.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(corridor)
	corridor.set_scroll_speed(0.0)
	for i in CASES.size():
		var entry: Array = CASES[i]
		var scene := load("res://scenes/runner/hazards/visuals/%s_visual.tscn" % entry[0]) as PackedScene
		var visual := scene.instantiate() as HazardVisualBase
		visual.position.z = -float(i) * 7.0
		# Reproduce the backend mount ordering, including ready with zero base vars.
		visual.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(visual)
		apply_vars(visual, entry)
		visual.on_spawned()
		visuals.append(visual)
		var wire := wireframe(entry[2])
		wire.position = visual.position + Vector3(0, entry[3], 0)
		add_child(wire)
		wires.append(wire)
	fixtures.assign(visuals)
	for i in POWERUPS.size():
		var scene := load("res://scenes/runner/powerups/visuals/%s_visual.tscn" % POWERUPS[i]) as PackedScene
		var pickup := scene.instantiate() as PowerUpVisualBase
		pickup.position = Vector3(0, 1, -float(CASES.size() + i) * 7.0)
		pickup.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(pickup)
		pickup.set("kind", POWERUPS[i])
		pickup.on_spawned()
		pickups.append(pickup)
		fixtures.append(pickup)
		var wire := pickup_sphere()
		wire.position = pickup.position
		add_child(wire)
	pursuer = $PursuerVisual as PursuerVisualBase
	pursuer.position.z = -float(CASES.size() + POWERUPS.size()) * 7.0 + 4.5
	pursuer.set_threat(1.0)
	fixtures.append(pursuer)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 60.0
	add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(28, 28)
	panel.theme = Style.theme()
	layer.add_child(panel)
	panel.add_child(Style.label("RUNNER VISUAL GALLERY / CONTRACT VOLUMES", 20, Style.MINT))
	panel.add_child(Style.label("Left/Right select  H hit  C clear  R reset  T telegraph  1/2/3 ground/high/off", 14))
	panel.add_child(Style.label("P collect  K catch  B retreat  [ / ] threat  Space pause", 14))
	_threat_slider = HSlider.new()
	_threat_slider.min_value = 0.0
	_threat_slider.max_value = 1.0
	_threat_slider.step = 0.05
	_threat_slider.value = 1.0
	_threat_slider.custom_minimum_size.x = 240
	_threat_slider.value_changed.connect(_set_threat)
	panel.add_child(_threat_slider)
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_status = Style.label("", 14)
	panel.add_child(_status)
	_focus()

static func apply_vars(visual: HazardVisualBase, entry: Array) -> void:
	visual.set("kind", entry[0])
	visual.set("variant", entry[1])
	visual.set("hitbox_size", entry[2])
	visual.set("hitbox_offset", Vector3(0, entry[3], 0))
	visual.set("lanes_mask", entry[4])
	visual.set("dodge_hint", entry[5])

static func wireframe(size: Vector3) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, Materials.additive(Palette.CREAM, 0.65))
	for axis in 3:
		for a in [-1.0, 1.0]:
			for b in [-1.0, 1.0]:
				var start := Vector3.ZERO
				start[axis] = -size[axis] * 0.5
				start[(axis + 1) % 3] = a * size[(axis + 1) % 3] * 0.5
				start[(axis + 2) % 3] = b * size[(axis + 2) % 3] * 0.5
				var end := start
				end[axis] *= -1
				mesh.surface_add_vertex(start)
				mesh.surface_add_vertex(end)
	mesh.surface_end()
	var result := MeshInstance3D.new()
	result.mesh = mesh
	return result

func _process(delta: float) -> void:
	if get_tree().paused: return
	_t += delta
	if _sweep:
		for visual in visuals:
			visual.set_telegraph(fmod(_t, 0.4) / 0.4)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and event.physical_keycode == KEY_SPACE:
		get_tree().paused = not get_tree().paused

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	match event.physical_keycode:
		KEY_LEFT: _selected = posmod(_selected - 1, fixtures.size())
		KEY_RIGHT: _selected = (_selected + 1) % fixtures.size()
		KEY_P:
			for pickup in pickups: pickup.on_collected()
		KEY_K: pursuer.play_catch()
		KEY_B: pursuer.play_retreat()
		KEY_BRACKETLEFT: _threat_slider.value -= 0.1
		KEY_BRACKETRIGHT: _threat_slider.value += 0.1
		KEY_H:
			for visual in visuals: visual.on_hit_player()
		KEY_C:
			for visual in visuals: visual.on_cleared()
		KEY_R:
			for pickup in pickups: pickup.on_spawned()
			pursuer.set_threat(0.0)
			pursuer.set_threat(_threat_slider.value)
			_sweep = false
			for i in visuals.size():
				visuals[i].on_spawned()
				wires[i].position.y = CASES[i][3]
				wires[i].show()
		KEY_T:
			_sweep = not _sweep
			if not _sweep:
				for visual in visuals: visual.set_telegraph(0.0)
		KEY_1, KEY_2, KEY_3:
			var state: StringName = [&"ground", &"high", &"off"][event.physical_keycode - KEY_1]
			for i in visuals.size():
				visuals[i].set_laser_state(state)
				if CASES[i][1] == &"timed":
					wires[i].visible = state != &"off"
					if state != &"off": wires[i].position.y = 1.3 if state == &"high" else 0.3
	_focus()

func _set_threat(value: float) -> void:
	pursuer.set_threat(value)
	pursuer.position.z = -float(CASES.size() + POWERUPS.size()) * 7.0 + lerpf(12.0, 4.5, value)
	_focus()

func _focus() -> void:
	var origin := fixtures[_selected].position
	var title := "UNREVIEWED PR BACKLOG / threat %.2f" % _threat_slider.value
	if _selected < CASES.size():
		title = "%s %s" % [CASES[_selected][0], CASES[_selected][1]]
	elif _selected < CASES.size() + POWERUPS.size():
		title = POWERUPS[_selected - CASES.size()]
		origin.y = 0.0
	else:
		origin = Vector3(0, 0, -float(CASES.size() + POWERUPS.size()) * 7.0)
	get_node("Corridor").position.z = origin.z
	_camera.position = origin + Vector3(0, 4, 8)
	_camera.look_at(origin + Vector3(0, 1, -8))
	_status.text = "%02d / %02d  %s" % [_selected + 1, fixtures.size(), title]

static func pickup_sphere() -> MeshInstance3D:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, Materials.additive(Palette.CREAM, 0.65))
	for axis in 3:
		for i in 32:
			for angle in [TAU * i / 32.0, TAU * (i + 1) / 32.0]:
				var point := Vector3.ZERO
				point[(axis + 1) % 3] = cos(angle) * 0.35
				point[(axis + 2) % 3] = sin(angle) * 0.35
				lines.surface_add_vertex(point)
	lines.surface_end()
	var result := MeshInstance3D.new()
	result.mesh = lines
	return result
