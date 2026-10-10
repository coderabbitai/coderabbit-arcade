extends Control
const Segments = preload("res://scenes/runner/ui/hifi/bar_segments.gd")
const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Glyph = preload("res://scenes/runner/ui/hud_glyph.gd")
var intro_active := false
var game: Node
var connections: Dictionary = {}
var phase_row: HBoxContainer
var _fight_active := false
var panel: PanelContainer
var title: Label
var tool_glyph: Control
var hp: ProgressBar
var chip: ProgressBar
var pips: Array[Control] = []
var border: StyleBoxFlat
var slide: Tween
var drain: Tween
var fill: Tween
var pip_flash: Tween
var _clock := 0.0
var _target := 1.0

func _ready() -> void:
	theme = Style.theme()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -340
	offset_right = 340
	offset_top = 8
	offset_bottom = 64
	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border = Style.panel(Palette.DANGER, 0.92)
	border.draw_center = false
	panel.add_theme_stylebox_override("panel", border)
	Style.polish(panel, false)
	border = panel.get_theme_stylebox("panel") as StyleBoxFlat
	var column := VBoxContainer.new()
	panel.add_child(column)
	var row := HBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.add_child(row)
	tool_glyph = Style.icon(&"review_comment", Palette.ORANGE, Vector2(28, 28))
	row.add_child(tool_glyph)
	tool_glyph.hide()
	title = Style.label("BOSS", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	phase_row = row
	var bars := Control.new()
	bars.custom_minimum_size = Vector2(652, 10)
	column.add_child(bars)
	chip = Style.bar(Vector2(652, 10), Palette.SLATE, Palette.NAVY_2)
	hp = Style.bar(Vector2(652, 10), Palette.DANGER, Color.TRANSPARENT)
	for bar in [chip, hp]:
		bar.step = 0.0
		bars.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var segmentation := Segments.new()
	bars.add_child(segmentation)
	var track := chip.get_theme_stylebox("background").duplicate() as StyleBoxFlat
	track.border_color = Palette.CREAM
	track.set_border_width_all(1)
	chip.add_theme_stylebox_override("background", track)
	hide()

func bind(value: Node) -> void:
	if game == value and not connections.is_empty(): return
	_disconnect()
	game = value
	connections = {&"tool_collected": _tool_icon, &"boss_cinematic": _cinematic, &"boss_cinematic_ended": _cinematic_ended, &"phase_changed": _game_phase, &"boss_spawned": _spawn, &"boss_health_changed": _health, &"boss_phase_changed": _phase, &"boss_defeated": _end, &"boss_retreated": _retreat, &"caught": _caught}
	for event: StringName in connections:
		if game.has_signal(event): game.connect(event, connections[event])
	if game.has_method("get_boss_info"):
		var info: Dictionary = game.get_boss_info()
		if not info.is_empty() and int(info.get("hp", 0)) > 0:
			_spawn(StringName(info.get("kind", "")), int(info.hp))
			_health(int(info.hp), int(info.get("max_hp", info.hp)))
			_phase(int(info.get("phase", 1)))

func _disconnect() -> void:
	if is_instance_valid(game):
		for event: StringName in connections:
			if game.has_signal(event) and game.is_connected(event, connections[event]): game.disconnect(event, connections[event])
	connections.clear()
	for tween in [slide, drain, fill, pip_flash]:
		if tween != null: tween.kill()
	_fight_active = false
	_cancel_intro()
	hide()

func _spawn(kind: StringName, _health_value: int) -> void:
	var info: Dictionary = game.get_boss_info() if game.has_method("get_boss_info") else {}
	_fight_active = true
	tool_glyph.hide()
	_rebuild_pips(maxi(1, int(info.get("phase_count", 1))))
	title.text = "BOSS · " + String(info.get("name", String(kind).replace("_", " "))).to_upper()
	for tween in [drain, fill]:
		if tween != null: tween.kill()
	hp.value = 1
	chip.value = 1
	_target = 1
	_phase(1)
	if intro_active:
		hide()
		return
	_slide_in()

func _slide_in() -> void:
	show()
	if slide != null: slide.kill()
	panel.position.y = -180
	slide = create_tween()
	slide.tween_property(panel, "position:y", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _rebuild_pips(count: int) -> void:
	for pip in pips:
		phase_row.remove_child(pip)
		pip.queue_free()
	pips.clear()
	for i in count:
		var pip := Glyph.new()
		pip.custom_minimum_size = Vector2(26, 28)
		pip.phase_glyph = true
		phase_row.add_child(pip)
		pips.append(pip)

func _health(value: int, maximum: int) -> void:
	_target = clampf(float(value) / maxi(maximum, 1), 0, 1)
	if fill != null: fill.kill()
	if drain != null: drain.kill()
	fill = create_tween()
	fill.tween_property(hp, "value", _target, 0.18)
	drain = create_tween()
	drain.tween_interval(0.35)
	drain.tween_property(chip, "value", _target, 0.3)

func _phase(value: int) -> void:
	for i in pips.size():
		pips[i].filled = i < value
		pips[i].queue_redraw()
	if pip_flash != null: pip_flash.kill()
	panel.modulate = Color(1.5, 1.5, 1.5)
	pip_flash = create_tween()
	pip_flash.tween_property(panel, "modulate", Color.WHITE, 0.9)

func _end(_kind: StringName, _bonus: int) -> void:
	title.text = "BUG FIXED"
	_slide_out()

func _retreat(_kind: StringName, _bonus: int) -> void:
	title.text = "BOSS ESCAPED"
	_slide_out()

func _slide_out() -> void:
	_cancel_intro()
	_fight_active = false
	if slide != null: slide.kill()
	slide = create_tween()
	slide.tween_interval(0.65)
	slide.tween_property(panel, "position:y", -180.0, 0.22)
	slide.tween_callback(hide)

func _caught() -> void:
	_cancel_intro()
	_fight_active = false
	for tween in [slide, drain, fill, pip_flash]:
		if tween != null: tween.kill()
	hide()

func _process(delta: float) -> void:
	if is_instance_valid(game) and game.get("paused") == true: return
	if not visible or not _fight_active: return
	_clock += delta
	border.border_color = Palette.DANGER.lerp(Palette.CREAM, (0.5 + 0.5 * sin(_clock * 9)) if _target < 0.25 else 0)

func _exit_tree() -> void:
	_disconnect()

func _cinematic(_kind: StringName, mode: StringName, _seconds: float) -> void:
	intro_active = mode in [&"intro_full", &"intro_short"]
	if slide != null: slide.kill()
	hide()

func _cinematic_ended(mode: StringName) -> void:
	_cancel_intro()
	if mode in [&"intro_full", &"intro_short"] and _fight_active: _slide_in()

func _cancel_intro() -> void:
	intro_active = false

func _game_phase(value: StringName) -> void:
	if value in [&"idle", &"run"]: _caught()

func _tool_icon(kind: StringName, _damage: int) -> void:
	tool_glyph.show()
	tool_glyph.kind = kind
	tool_glyph.queue_redraw()
