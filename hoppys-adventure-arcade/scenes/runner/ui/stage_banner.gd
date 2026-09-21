extends Control
const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
var game: Node
var connections: Dictionary = {}
var panel: PanelContainer
var title: Label
var subtitle: Label
var age := 0.0
signal opened
signal closed

func bind(runner: Node) -> void:
	if game == runner: return
	if is_instance_valid(game):
		for event: StringName in connections:
			if game.is_connected(event, connections[event]): game.disconnect(event, connections[event])
	game = runner
	for event: StringName in connections:
		if game.has_signal(event): game.connect(event, connections[event])
	_close()

func _close() -> void:
	if visible:
		hide()
		closed.emit()

func _base_phase(value: StringName) -> void:
	if value == &"idle": _close()

func _base(extent: Vector2) -> VBoxContainer:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	panel.custom_minimum_size = extent
	panel.pivot_offset = extent * 0.5
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size * 0.5)
	panel.add_theme_stylebox_override("panel", Style.panel(Palette.MATRIX, 0.9))
	Style.polish(panel, true)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	hide()
	return box

var pending: Dictionary = {}
var turning := false
var boss_visible := false
var rules: Array[ColorRect] = []

func _ready() -> void:
	connections = {&"boss_intro": _intro, &"turn_incoming": _turn, &"stage_started": _stage, &"turn_started": _turn, &"turn_finished": _finish_turn, &"boss_spawned": _boss, &"phase_changed": _phase}
	var box := _base(Vector2(820, 180))
	title = Style.label("S T A G E  1", 30, Palette.MINT)
	subtitle = Style.label("", 52)
	for label in [title, subtitle]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
	for i in 2:
		var rule := ColorRect.new()
		rule.color = Palette.MINT
		rule.custom_minimum_size.y = 2
		box.add_child(rule)
		rules.append(rule)

func _stage(index: int, boss_name: StringName, _speed: float) -> void:
	pending = {"index": index, "name": boss_name}
	if not turning and not boss_visible: _show_pending()

func _show_pending() -> void:
	if pending.is_empty() or boss_visible: return
	title.text = "S T A G E  %d" % int(pending.index)
	subtitle.text = String(pending.name).to_upper()
	pending.clear()
	age = 0.0
	show()
	_process(0.0)
	opened.emit()

func _turn(_direction: int, _seconds: float) -> void:
	turning = true
	_close()

func _finish_turn() -> void:
	turning = false
	_show_pending()

func _boss(_kind: StringName, _hp: int) -> void:
	boss_visible = true
	_close()

func _phase(value: StringName) -> void:
	_base_phase(value)
	if value == &"run": boss_visible = false
	if value == &"idle":
		pending.clear()
		turning = false
		boss_visible = false

func _process(delta: float) -> void:
	if not visible or (is_instance_valid(game) and bool(game.get("paused"))): return
	age += delta
	panel.modulate.a = minf(age / 0.35, 1.0) * (1.0 - clampf((age - 1.95) / 0.4, 0, 1))
	for rule in rules:
		rule.pivot_offset.x = rule.size.x * 0.5
		rule.scale.x = smoothstep(0.0, 0.35, age)
	if age >= 2.35: _close()

func _intro(_kind: StringName, _name: String, _seconds: float) -> void:
	boss_visible = true
	_close()
