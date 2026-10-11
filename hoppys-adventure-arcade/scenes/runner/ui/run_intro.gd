extends CanvasLayer
## Clock-driven opening card and countdown. The facade owns playback, pause and skip.
const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Prompts = preload("res://app/controller_prompts.gd")
var game: Node
var connections: Dictionary = {}
var mode: StringName = &""
var seconds := 0.0
var skipped := false
var beat_index := -1
var beat_label := ""
var _beat_at := 0.0
var root: Control
var title_group: Control
var title: Label
var eyebrow: Label
var subtitle: Label
var header: Label
var footer: Label
var lower_third: TextureRect
var countdown: Control
var count_label: Label
var count_hint: Label
var burst: BeatBurst
var flash: ColorRect
var skip_button: Button
var skip_prompt: Label
var _viewport_size := Vector2.ZERO

class BeatBurst extends Control:
	var age := 0.0
	var go := false
	var tint := Color("f78949")
	func _draw() -> void:
		var center := size * 0.5
		var unit := minf(size.x, size.y)
		var expansion := 1.0 - pow(1.0 - clampf(age / 0.50, 0, 1), 3)
		var alpha := 1.0 - smoothstep(0.18, 0.58, age)
		if go:
			for i in 16:
				var direction := Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
				var inner := unit * lerpf(0.18, 0.38, expansion)
				var outer := inner + unit * (0.08 if i % 2 == 0 else 0.035)
				draw_line(center + direction * inner, center + direction * outer, Color(tint, alpha * 0.85), 3.0, true)
			draw_arc(center, unit * lerpf(0.17, 0.43, expansion), 0, TAU, 96, Color(tint, alpha * 0.55), 2.0, true)
		else:
			draw_circle(center, unit * 0.22, Color("08111cca"))
			for i in 4:
				var angle := PI * 0.25 + PI * 0.5 * i
				draw_arc(center, unit * 0.24, angle, angle + PI * 0.34, 24, Color(tint, 0.7 * alpha), 3.0, true)

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
	lower_third.name = "LowerThird"
	lower_third.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.48, 1])
	gradient.colors = PackedColorArray([Color(Palette.NAVY_BG, 0), Color(Palette.NAVY_BG, 0.88), Color(Palette.NAVY_BG, 0.98)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.DOWN
	lower_third.texture = texture
	root.add_child(lower_third)
	header = _label(root, "CODERABBIT ARCADE  /  ENDLESS RUNNER", 18, Palette.ORANGE)
	footer = _label(root, "RUN 001  /  THE NEXT COMMIT IS YOURS", 16, Palette.CREAM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_group = Control.new()
	title_group.name = "TitleCard"
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_group)
	eyebrow = _label(title_group, "A NEW RUN", 20, Palette.ORANGE)
	title = _label(title_group, "THE CODEBASE CORRIDOR", 54, Palette.CREAM)
	subtitle = _label(title_group, "KEEP MOVING. SHIP CLEAN.", 20, Palette.MINT)
	countdown = Control.new()
	countdown.name = "Countdown"
	countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(countdown)
	burst = BeatBurst.new()
	burst.name = "BeatBurst"
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown.add_child(burst)
	count_label = _label(countdown, "", 132, Palette.CREAM)
	count_hint = _label(countdown, "", 18, Palette.CREAM)
	flash = ColorRect.new()
	flash.name = "GoFlash"
	flash.color = Color(Palette.MINT, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skip_button = Button.new()
	skip_button.name = "SkipIntro"
	skip_button.flat = true
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	skip_button.pressed.connect(_request_skip)
	root.add_child(skip_button)
	skip_prompt = _label(skip_button, "", 18, Palette.CREAM)
	skip_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Prompts.track(skip_prompt, func() -> String: return "SKIP  [%s]" % Prompts.either("SPACE", &"jump", true))
	var font := FontVariation.new()
	font.base_font = Style.theme().default_font
	font.variation_embolden = 1.2
	font.spacing_glyph = 1
	for label in [title, count_label]:
		label.add_theme_font_override("font", font)
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
	var inset := maxf(18, w * 0.05)
	header.position = Vector2(inset, h * 0.007)
	header.size = Vector2(w - inset * 2, h * 0.05)
	header.add_theme_font_size_override("font_size", int(clampf(w * 0.014, 12, 20)))
	footer.position = Vector2(inset, h * 0.943)
	footer.size = Vector2(w * 0.57, h * 0.05)
	footer.add_theme_font_size_override("font_size", int(clampf(w * 0.0125, 10, 18)))
	lower_third.position = Vector2(0, h * 0.56)
	lower_third.size = Vector2(w, h * 0.38)
	title_group.position = Vector2(inset, h * 0.68)
	title_group.size = Vector2(w - inset * 2, h * 0.21)
	title_group.pivot_offset = title_group.size * Vector2(0.5, 0.4)
	eyebrow.size = Vector2(title_group.size.x, h * 0.037)
	title.position = Vector2(0, h * 0.035)
	title.size = Vector2(title_group.size.x, h * 0.095)
	title.add_theme_font_size_override("font_size", int(clampf(w * 0.040, 18, 64)))
	subtitle.position = Vector2(0, h * 0.135)
	subtitle.size = Vector2(title_group.size.x, h * 0.04)
	subtitle.add_theme_font_size_override("font_size", int(clampf(w * 0.016, 12, 22)))
	countdown.position = Vector2(w * 0.15, h * 0.005)
	countdown.size = Vector2(w * 0.70, h * 0.64)
	countdown.pivot_offset = countdown.size * 0.5
	burst.size = countdown.size
	count_label.size = countdown.size
	count_label.add_theme_font_size_override("font_size", int(clampf(minf(w * 0.12, h * 0.21), 40, 156)))
	count_hint.position = Vector2(0, countdown.size.y * 0.70)
	count_hint.size = Vector2(countdown.size.x, h * 0.05)
	skip_button.position = Vector2(w - inset - minf(290, w * 0.38), h * 0.934)
	skip_button.size = Vector2(minf(290, w * 0.38), h * 0.065)
	skip_prompt.add_theme_font_size_override("font_size", int(clampf(w * 0.014, 12, 20)))

func bind(value: Node) -> void:
	if game == value and not connections.is_empty(): return
	if is_instance_valid(game):
		for event: StringName in connections:
			if game.is_connected(event, connections[event]): game.disconnect(event, connections[event])
	game = value
	_reset()
	connections = {&"run_intro": _begin, &"run_intro_beat": _beat,
		&"run_intro_skipped": _skipped, &"run_intro_ended": _ended,
		&"phase_changed": _phase, &"run_started": _run_started,
		&"caught": _reset, &"run_finished": _finished, &"paused_changed": _paused}
	if not is_instance_valid(game):
		connections.clear()
		return
	for event: StringName in connections.keys():
		if game.has_signal(event): game.connect(event, connections[event])
		else: connections.erase(event)

func _begin(value: StringName, duration: float) -> void:
	_reset()
	if value not in [&"full", &"short"] or duration <= 0: return
	mode = value
	seconds = duration
	footer.text = "RUN 001  /  THE NEXT COMMIT IS YOURS" if mode == &"full" else "BACK IN THE CODEBASE"
	root.show()
	_process(0)

func _beat(index: int, label: String) -> void:
	if mode == &"" or (skipped and not label.to_upper().begins_with("GO")): return
	# Beat spacing and intro length are configurable; pop from the signal arrival.
	_beat_at = float(game.get("run_intro_progress")) * seconds
	beat_index = index
	beat_label = label
	_process(0)

func _process(_delta: float) -> void:
	if not is_instance_valid(game) or mode == &"" or game.get("paused") == true: return
	if _viewport_size != get_viewport().get_visible_rect().size: _layout()
	var p := clampf(float(game.get("run_intro_progress")), 0, 1)
	var age := p * seconds
	var normalized_age := p * (6.0 if mode == &"full" else 2.2)
	var out := 1.0 - smoothstep(0.93, 1, p)
	var title_age := normalized_age - 1.0
	var title_alpha := smoothstep(0, 0.12, title_age) * (1.0 - smoothstep(2.20, 2.65, normalized_age))
	title_group.visible = mode == &"full" and title_age >= 0 and normalized_age < 2.65 and not skipped
	lower_third.visible = title_group.visible
	title_group.modulate.a = title_alpha
	lower_third.modulate.a = title_alpha
	title_group.scale = Vector2.ONE * lerpf(1.10, 1.0, 1.0 - pow(1.0 - clampf(title_age / 0.28, 0, 1), 3))
	header.visible = mode == &"full" and not skipped
	header.modulate.a = smoothstep(0.16, 0.40, age) * out
	footer.visible = not skipped
	footer.modulate.a = smoothstep(0.16, 0.40, age) * out
	var is_count := beat_index >= 0 and beat_label.to_upper() in ["READY", "3", "2", "1", "GO!"]
	countdown.visible = is_count and (not skipped or beat_label.to_upper().begins_with("GO"))
	if is_count:
		var beat_age := maxf(0, age - _beat_at)
		var go := beat_label.to_upper().begins_with("GO")
		count_label.text = beat_label.to_upper()
		count_label.add_theme_color_override("font_color", Palette.MINT if go else Palette.CREAM)
		count_hint.text = "LET'S SHIP IT" if go else ("ONE MORE RUN" if mode == &"short" else "GET READY")
		countdown.scale = Vector2.ONE * lerpf(1.42 if go else 1.28, 1.0, 1.0 - pow(1.0 - clampf(beat_age / 0.20, 0, 1), 3))
		countdown.modulate.a = (1.0 - smoothstep(0.36, 0.60, beat_age)) if go else (1.0 - smoothstep(0.50, 0.74, beat_age))
		burst.age = beat_age
		burst.go = go
		burst.tint = Palette.MINT if go else Palette.ORANGE
		burst.queue_redraw()
		flash.color.a = maxf(0, 1.0 - beat_age / 0.12) * 0.20 if go else 0
	else:
		flash.color.a = 0
	skip_button.visible = not skipped and game.has_method("can_skip_run_intro") and bool(game.call("can_skip_run_intro"))
	skip_prompt.visible = skip_button.visible
	skip_button.disabled = not skip_button.visible

func _request_skip() -> void:
	if is_instance_valid(game) and game.has_method("can_skip_run_intro") and bool(game.call("can_skip_run_intro")) and game.has_method("skip_run_intro"):
		game.call("skip_run_intro")

func _skipped(_mode: StringName = &"") -> void:
	skipped = true
	# Clear immediately even if a pause notification arrives in the same frame.
	title_group.hide()
	lower_third.hide()
	countdown.hide()
	skip_button.hide()
	skip_prompt.hide()
	header.hide()
	footer.hide()
	flash.color.a = 0

func _ended(_mode: StringName = &"") -> void:
	_reset()

func _phase(value: StringName) -> void:
	if value != &"intro": _reset()

func _run_started(_seed: int) -> void:
	_reset()

func _finished(_result: Dictionary) -> void:
	_reset()

func _paused(value: bool) -> void:
	if value:
		skip_button.hide()
		skip_prompt.hide()
	else:
		_process(0)

func _reset() -> void:
	mode = &""
	seconds = 0
	skipped = false
	beat_index = -1
	beat_label = ""
	_beat_at = 0
	if root == null: return
	root.hide()
	title_group.hide()
	lower_third.hide()
	countdown.hide()
	skip_button.hide()
	skip_prompt.hide()
	flash.color.a = 0

func _exit_tree() -> void:
	bind(null)
