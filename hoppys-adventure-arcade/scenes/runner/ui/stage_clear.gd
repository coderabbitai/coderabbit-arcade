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

func _phase(value: StringName) -> void:
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
	panel.add_theme_stylebox_override("panel", Style.panel(Palette.MATRIX, 0.92))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	hide()
	return box

const DURATION := 2.8
var tools := 0
var stage_start := 0.0
var boss_name := ""
var outcome := "FIXED"
var bonus := 0
var bonus_label: Label
var time_label: Label
var tools_label: Label

func _ready() -> void:
	connections = {&"stage_started": _stage, &"stage_cleared": _clear, &"boss_spawned": _boss, &"boss_defeated": _defeated, &"boss_retreated": _retreated, &"tool_collected": _tool, &"phase_changed": _phase}
	var box := _base(Vector2(640, 360))
	title = Style.label("STAGE CLEAR", 44, Palette.MATRIX)
	subtitle = Style.label("", 26)
	for label in [title, subtitle]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
	var rows := GridContainer.new()
	rows.columns = 2
	box.add_child(rows)
	for text in ["TIME", "TOOLS USED", "BONUS"]:
		var key := Style.label(text, 24)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(key)
		var value := Style.label("0", 28 if text == "BONUS" else 24, Palette.ORANGE if text == "BONUS" else Palette.MINT)
		rows.add_child(value)
		match text:
			"TIME": time_label = value
			"TOOLS USED": tools_label = value
			"BONUS": bonus_label = value
	box.add_child(Style.label("Fixing harder bugs ahead.", 22, Palette.MINT))

func _stage(_index: int, value: StringName, _speed: float) -> void:
	tools = 0
	stage_start = float(game.get("elapsed"))
	boss_name = String(value)
	outcome = "FIXED"
	_close()

func _boss(_kind: StringName, _hp: int) -> void:
	var info: Dictionary = game.get_boss_info()
	boss_name = String(info.get("name", boss_name))

func _tool(_kind: StringName, _damage: int) -> void:
	tools += 1

func _defeated(_kind: StringName, _bonus: int) -> void:
	outcome = "FIXED"

func _retreated(_kind: StringName, _bonus: int) -> void:
	outcome = "ESCAPED"

func _clear(index: int, value: int) -> void:
	var info: Dictionary = game.get_stage_info()
	title.text = "STAGE %d CLEAR" % index
	subtitle.text = "%s — %s" % [String(info.get("name", boss_name)).to_upper(), outcome]
	var seconds := maxf(0.0, float(game.get("elapsed")) - stage_start)
	time_label.text = "%02d:%04.1f" % [int(seconds) / 60, fmod(seconds, 60)]
	tools_label.text = str(tools)
	bonus = value
	age = 0.0
	show()
	_process(0.0)
	opened.emit()

func _process(delta: float) -> void:
	if not visible or (is_instance_valid(game) and bool(game.get("paused"))): return
	age += delta
	var entrance := clampf(age / 0.25, 0, 1)
	panel.scale = Vector2.ONE * lerpf(0.92, 1.0, entrance)
	panel.modulate.a = entrance * (1 - clampf((age - 2.45) / 0.35, 0, 1))
	bonus_label.text = "+%d" % roundi(bonus * clampf(age / 0.5, 0, 1))
	if age >= DURATION: _close()
