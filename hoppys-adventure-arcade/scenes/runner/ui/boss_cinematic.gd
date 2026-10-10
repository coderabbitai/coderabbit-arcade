extends CanvasLayer
## Pure presentation of the encounter clock. No local timers, Tweens or gameplay writes.
const Copy = preload("res://scenes/runner/ui/boss_copy.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const BossVisual = preload("res://scenes/runner/boss/boss_visual_base.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Glyph = preload("res://scenes/runner/ui/hifi/utility_glyph.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const TITLE_AT: float = BossVisual.INTRO_POSE_AT[&"intro_full"]
const SHORT_TITLE_AT: float = BossVisual.INTRO_POSE_AT[&"intro_short"]
const RESOLVED_AT := 0.60
var game: Node
var connections: Dictionary = {}
var mode: StringName = &""
var seconds := 0.0
var bonus := 0
var skipped := false
var root: Control
var title_group: Control
var epithet: Label
var boss_name: Label
var threat: Label
var chyron: Label
var review_header: PanelContainer
var source_path: Label
var hints: VBoxContainer
var skip_prompt: Label
var resolved: Control
var resolved_title: Label
var bonus_label: Label
var flash: ColorRect
var lower_third: TextureRect
var _viewport_size := Vector2.ZERO
var _gameplay_hud: CanvasLayer
var _gameplay_was_visible := true
var _hint_row_count := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	layer = 12
	root = Control.new()
	root.name = "Presentation"
	root.theme = Style.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lower_third = TextureRect.new()
	lower_third.name = "LowerThirdBacking"
	lower_third.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.40, 1.0])
	gradient.colors = PackedColorArray([Color(Palette.NAVY_BG, 0.0), Color(Palette.NAVY_BG, 0.78), Color(Palette.NAVY_BG, 0.94)])
	var backing_texture := GradientTexture2D.new()
	backing_texture.gradient = gradient
	backing_texture.fill_from = Vector2(0, 0)
	backing_texture.fill_to = Vector2(0, 1)
	lower_third.texture = backing_texture
	root.add_child(lower_third)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	review_header = PanelContainer.new()
	review_header.name = "ReviewHeader"
	review_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header_style := Style.panel(Palette.DANGER, 0.96)
	header_style.content_margin_top = 2
	header_style.content_margin_bottom = 2
	header_style.shadow_size = 0
	review_header.add_theme_stylebox_override("panel", header_style)
	root.add_child(review_header)
	var review_row := HBoxContainer.new()
	review_row.alignment = BoxContainer.ALIGNMENT_CENTER
	review_row.add_theme_constant_override("separation", 10)
	review_header.add_child(review_row)
	var review_glyph := Style.icon(&"review_comment", Palette.ORANGE, Vector2(26, 26))
	review_row.add_child(review_glyph)
	chyron = _label(review_row, "CODERABBIT REVIEW · CRITICAL ISSUE", 18, Palette.ORANGE)
	chyron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	source_path = _label(root, "", 16, Palette.CREAM)
	source_path.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_group = Control.new()
	title_group.name = "TitleCard"
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_group)
	epithet = _label(title_group, "", 26, Palette.ORANGE)
	boss_name = _label(title_group, "", 64, Palette.CREAM)
	threat = _label(root, "", 22, Palette.CREAM)
	hints = VBoxContainer.new()
	hints.name = "HowToResolve"
	hints.add_theme_constant_override("separation", 5)
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hints)
	skip_prompt = _label(root, "▶ SKIP  [SPACE / A]", 18, Palette.CREAM)
	resolved = Control.new()
	resolved.name = "Resolved"
	resolved.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(resolved)
	resolved_title = _label(resolved, "THREAD RESOLVED", 64, Palette.MINT)
	bonus_label = _label(resolved, "", 26, Palette.CREAM)
	var title_font := FontVariation.new()
	title_font.base_font = Style.theme().default_font
	title_font.variation_embolden = 1.2
	title_font.spacing_glyph = 1
	for label in [boss_name, resolved_title]: label.add_theme_font_override("font", title_font)
	_layout()
	_reset()

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Style.label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label

func _layout() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	var w := _viewport_size.x
	var h := _viewport_size.y
	var inset := maxf(24, w * 0.05)
	# Review metadata lives on the mattes, leaving the boss silhouette clear.
	review_header.position = Vector2((w - 550) * 0.5, h * 0.009)
	review_header.size = Vector2(550, 34)
	source_path.position = Vector2(inset, h * 0.947)
	source_path.size = Vector2(w * 0.60, 30)
	lower_third.position = Vector2(0, h * 0.52)
	lower_third.size = Vector2(w, h * 0.42)
	title_group.position = Vector2(inset, h * 0.58)
	title_group.size = Vector2(w - inset * 2, 120)
	title_group.pivot_offset = title_group.size * 0.5
	epithet.position = Vector2.ZERO
	epithet.size = Vector2(title_group.size.x, 34)
	boss_name.position = Vector2(0, 32)
	boss_name.size = Vector2(title_group.size.x, 80)
	boss_name.add_theme_font_size_override("font_size", int(clampf(w * 0.05, 28, 72)))
	threat.position = Vector2(inset, h * 0.58 + 114)
	threat.size = Vector2(w - inset * 2, 30)
	hints.position = Vector2(inset, h * 0.80)
	hints.size = Vector2(w - inset * 2, 90)
	skip_prompt.position = Vector2(w - 300, h * 0.947)
	skip_prompt.size = Vector2(270, 30)
	resolved.position = Vector2(inset, h * 0.64)
	resolved.size = Vector2(w - inset * 2, 130)
	resolved.pivot_offset = resolved.size * 0.5
	resolved_title.size = Vector2(resolved.size.x, 88)
	resolved_title.add_theme_font_size_override("font_size", int(clampf(w * 0.055, 32, 76)))
	bonus_label.position = Vector2(0, 90)
	bonus_label.size = Vector2(resolved.size.x, 34)

func bind(value: Node) -> void:
	if game == value and not connections.is_empty(): return
	if is_instance_valid(game):
		for event: StringName in connections:
			if game.is_connected(event, connections[event]): game.disconnect(event, connections[event])
	game = value
	_reset()
	connections = {&"boss_cinematic": _cinematic, &"boss_cinematic_skipped": _skipped,
		&"boss_cinematic_ended": _ended, &"boss_defeated": _defeated, &"caught": _reset,
		&"run_started": _run_started}
	if not is_instance_valid(game): return
	for event: StringName in connections.keys():
		if game.has_signal(event): game.connect(event, connections[event])
		else: connections.erase(event)

func _cinematic(kind: StringName, cinematic_mode: StringName, duration: float) -> void:
	mode = cinematic_mode
	if _gameplay_hud == null:
		_gameplay_hud = game.get_node_or_null("HUD/RunnerHud") as CanvasLayer
		if _gameplay_hud != null: _gameplay_was_visible = _gameplay_hud.visible
	if _gameplay_hud != null: _gameplay_hud.hide()
	seconds = maxf(duration, 0.001)
	skipped = false
	var stage := int(game.get("stage_index")) if "stage_index" in game else 1
	var def: Dictionary = BossDefs.base_def(stage)
	# Signal fixtures can introduce any kind independently of the current stage.
	if StringName(def.kind) != kind:
		def = {}
		for row: Dictionary in BossDefs.SLOTS:
			if StringName(row.kind) == kind: def = row
	epithet.text = Copy.epithet(kind, BossDefs.cycle(stage) + 1).to_upper()
	boss_name.text = String(def.get("name", String(kind).replace("_", " "))).to_upper()
	threat.text = Copy.threat(kind)
	source_path.text = Copy.source_path(kind)
	bonus_label.text = "+%s BONUS" % String.num_int64(bonus)
	_build_hints(def)
	root.show()
	_process(0.0)

func _build_hints(def: Dictionary) -> void:
	for child in hints.get_children():
		hints.remove_child(child)
		child.queue_free()
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing := Style.panel(Palette.SLATE, 0.90)
	backing.content_margin_top = 4
	backing.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", backing)
	hints.add_child(chip)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	chip.add_child(content)
	_label(content, "HOW TO RESOLVE", 20, Palette.ORANGE)
	var phase_rows := VBoxContainer.new()
	phase_rows.add_theme_constant_override("separation", 4)
	content.add_child(phase_rows)
	var rows := Copy.hint_rows(def)
	var restricted := rows.any(func(row): return not row.all_tools)
	for row: Dictionary in rows:
		if restricted and row.all_tools: continue
		if not restricted and int(row.phase) != 1: continue
		if not restricted and not String(row.hint).is_empty():
			_label(phase_rows, row.hint, 22, Palette.CREAM)
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 18)
		phase_rows.add_child(line)
		_label(line, "PHASE %d" % row.phase if restricted else "EVERY TOOL LANDS", 20, Palette.CREAM)
		for tool: StringName in row.tools:
			var tool_pair := HBoxContainer.new()
			tool_pair.add_theme_constant_override("separation", 5)
			line.add_child(tool_pair)
			var glyph := Glyph.new()
			glyph.kind = tool
			glyph.tint = Palette.ORANGE
			glyph.custom_minimum_size = Vector2(36, 36)
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tool_pair.add_child(glyph)
			if restricted: _label(tool_pair, ToolDefs.label(tool).to_upper(), 20, Palette.CREAM)
	_hint_row_count = phase_rows.get_child_count()

func _process(_delta: float) -> void:
	if not is_instance_valid(game) or mode == &"" or game.get("paused") == true: return
	if _viewport_size != get_viewport().get_visible_rect().size: _layout()
	var p := clampf(float(game.get("boss_cinematic_progress")), 0, 1)
	var short := mode == &"intro_short"
	var intro := mode in [&"intro_full", &"intro_short"]
	var age := p * seconds
	var title_at := SHORT_TITLE_AT if short else TITLE_AT
	var title_age := (p - title_at) * seconds
	var out := 1.0 - smoothstep(0.92 if not short else 0.86, 1.0, p)
	lower_third.visible = not skipped and (p >= title_at if intro else p >= RESOLVED_AT)
	lower_third.modulate.a = out
	title_group.visible = intro and p >= title_at and not skipped
	title_group.scale = Vector2.ONE * lerpf(1.8, 1.0, 1.0 - pow(1.0 - clampf(title_age / 0.18, 0, 1), 3))
	title_group.modulate.a = out
	chyron.visible = intro and not short and not skipped
	review_header.visible = chyron.visible
	source_path.visible = chyron.visible
	review_header.modulate.a = smoothstep(0.03, 0.12, p) * out
	source_path.modulate.a = review_header.modulate.a * 0.8
	threat.visible = intro and not short and p >= TITLE_AT and not skipped
	threat.visible_characters = maxi(0, int((title_age - 0.18) * 40.0))
	threat.modulate.a = out
	var hint_advance := 0.25 / seconds if _hint_row_count > 1 else 0.0
	hints.visible = intro and not short and p >= 0.70 - hint_advance and not skipped
	hints.modulate.a = smoothstep(0.70 - hint_advance, 0.72 - hint_advance, p) * out
	# Only query the facade guard, which includes running, pause, skip arm and skip tail.
	skip_prompt.visible = intro and not skipped and game.has_method("can_skip_boss_cinematic") and bool(game.call("can_skip_boss_cinematic"))
	resolved.visible = not intro and p >= RESOLVED_AT
	var resolved_age := (p - RESOLVED_AT) * seconds
	resolved.scale = Vector2.ONE * lerpf(1.8, 1.0, 1.0 - pow(1.0 - clampf(resolved_age / 0.2, 0, 1), 3))
	resolved.modulate.a = out
	var flash_amount := maxf(0.0, 1.0 - title_age / 0.11) * 0.45 if intro and title_age >= 0 and not skipped else 0.0
	if not intro: flash_amount = maxf(0, 1 - age / 0.12) * 0.85
	flash.color.a = flash_amount

func _defeated(_kind: StringName, value: int) -> void:
	bonus = value

func _skipped(_mode: StringName) -> void:
	skipped = true
	_process(0.0)

func _ended(_mode: StringName) -> void:
	_reset()

func _run_started(_seed: int) -> void:
	bonus = 0
	_reset()

func _reset() -> void:
	if is_instance_valid(_gameplay_hud): _gameplay_hud.visible = _gameplay_was_visible
	_gameplay_hud = null
	mode = &""
	seconds = 0.0
	skipped = false
	if root != null: root.hide()

func _exit_tree() -> void:
	bind(null)
