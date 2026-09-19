extends CanvasLayer
const Style = preload("res://scenes/main_menu/menu_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Glyph = preload("res://scenes/runner/ui/hud_glyph.gd")
const Vignette = preload("res://scenes/runner/shaders/vignette.gdshader")
var game: Node
var screen: Control
var widgets: Control
var hp_row: HBoxContainer
var powerups: VBoxContainer
var score_label: Label
var time_label: Label
var multiplier_label: Label
var speed_label: Label
var speed_bar: ProgressBar
var pursuit_warning: HBoxContainer
var pursuit_label: Label
var pursuit_ring: Control
var get_ready: Label
var toast: Label
var nitro_banner: Label
var hit_flash: ColorRect
var vignette_material: ShaderMaterial
var chips := {}
var recovery_seconds := 0.0
var pursuit_remaining := 0.0
var displayed_score := 0.0
var score_tween: Tween
var flash_tween: Tween
var toast_queue: Array[String] = []
var toast_remaining := 0.0
var pulse_clock := 0.0

func _ready() -> void:
	screen = Control.new()
	screen.name = "Screen"
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = Style.theme()
	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	screen.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette_material = ShaderMaterial.new()
	vignette_material.shader = Vignette
	vignette.material = vignette_material
	widgets = Control.new()
	screen.add_child(widgets)
	widgets.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left := VBoxContainer.new()
	_place(left, Control.PRESET_TOP_LEFT, Vector2(28, 28), Vector2(240, 100))
	left.add_child(Style.label("APPROVALS", 14, Palette.MINT))
	hp_row = HBoxContainer.new()
	hp_row.name = "HpRow"
	left.add_child(hp_row)
	powerups = VBoxContainer.new()
	powerups.name = "PowerUps"
	left.add_child(powerups)
	var top := VBoxContainer.new()
	_place(top, Control.PRESET_CENTER_TOP, Vector2(-210, 28), Vector2(420, 120))
	time_label = Style.label("00:00.0", 24)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(time_label)
	pursuit_warning = HBoxContainer.new()
	pursuit_warning.name = "PursuitWarning"
	pursuit_warning.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(pursuit_warning)
	pursuit_ring = Glyph.new()
	pursuit_ring.ring = true
	pursuit_ring.custom_minimum_size = Vector2(36, 36)
	pursuit_warning.add_child(pursuit_ring)
	pursuit_label = Style.label("", 16, Palette.ROSE)
	pursuit_warning.add_child(pursuit_label)
	pursuit_warning.hide()
	var right := VBoxContainer.new()
	_place(right, Control.PRESET_TOP_RIGHT, Vector2(-288, 28), Vector2(260, 100))
	score_label = Style.label("00000000", 32, Palette.MINT)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(score_label)
	multiplier_label = Style.label("×1.0", 20, Palette.MINT)
	multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(multiplier_label)
	var bottom := VBoxContainer.new()
	_place(bottom, Control.PRESET_BOTTOM_RIGHT, Vector2(-268, -90), Vector2(240, 62))
	speed_label = Style.label("SPEED 0.0 m/s", 17)
	bottom.add_child(speed_label)
	speed_bar = _bar(Vector2(240, 8))
	bottom.add_child(speed_bar)
	toast = Style.label("", 24, Palette.MINT)
	_place(toast, Control.PRESET_CENTER, Vector2(-350, -80), Vector2(700, 40))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nitro_banner = Style.label("NITRO COMMIT!", 30, Palette.ORANGE)
	nitro_banner.name = "NitroBanner"
	_place(nitro_banner, Control.PRESET_CENTER_BOTTOM, Vector2(-250, -140), Vector2(500, 50))
	nitro_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nitro_banner.hide()
	get_ready = Style.label("GET READY\nA / D · ← / →  lane    SPACE / A  jump\nS / ↓ / B  roll    ESC / START  pause", 22)
	get_ready.name = "GetReady"
	_place(get_ready, Control.PRESET_CENTER, Vector2(-480, 0), Vector2(960, 120))
	get_ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hit_flash = ColorRect.new()
	hit_flash.name = "HitFlash"
	screen.add_child(hit_flash)
	hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_flash.color = Color(1, 1, 1, 0)
	_ignore_mouse(screen)

func _place(control: Control, preset: int, offset: Vector2, extent: Vector2) -> void:
	widgets.add_child(control)
	control.set_anchors_and_offsets_preset(preset)
	# Anchor-relative offsets, including expand viewports.
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + extent.x
	control.offset_bottom = offset.y + extent.y

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _bar(extent: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = extent
	bar.show_percentage = false
	bar.max_value = 1.0
	var background := StyleBoxFlat.new()
	background.bg_color = Palette.SLATE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.MINT
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func bind(runner: Node) -> void:
	game = runner
	game.health_changed.connect(_health)
	game.score_changed.connect(_score)
	game.speed_changed.connect(_speed)
	game.pursuit_started.connect(_pursuit_started)
	game.pursuit_progress.connect(_pursuit_progress)
	game.pursuit_recovered.connect(_recovered)
	game.caught.connect(_caught)
	game.state_changed.connect(_state)
	game.paused_changed.connect(_paused)
	game.damage_taken.connect(_damage)
	game.damage_blocked.connect(_blocked)
	game.power_up_collected.connect(_powerup)
	game.power_up_expired.connect(_expire)
	game.shield_changed.connect(_shield)
	game.hazards_blasted.connect(func(count: int) -> void: _toast("AUTO-FIX ×%d" % count))
	game.bonus_awarded.connect(func(points: int, _reason: StringName) -> void: _toast("+%d BONUS" % points))
	_health(game.hp, game.config.max_hp)
	_score(game.score, game.multiplier)
	_speed(game.speed, game.normalized_speed)
	_state(game.state)
	_paused(game.paused)

func _process(delta: float) -> void:
	if game == null or game.paused:
		return
	var seconds := float(game.elapsed)
	time_label.text = "%02d:%04.1f" % [int(seconds) / 60, fmod(seconds, 60)]
	for kind in chips:
		var chip: Dictionary = chips[kind]
		if chip.total > 0:
			chip.remaining = maxf(0, chip.remaining - delta)
			chip.bar.value = chip.remaining / chip.total
	if pursuit_warning.visible:
		pulse_clock += delta * lerpf(3, 12, 1 - pursuit_ring.fraction)
		pursuit_warning.modulate.a = 0.75 + 0.25 * sin(pulse_clock)
		vignette_material.set_shader_parameter("pulse", 0.5 + 0.5 * sin(pulse_clock))
	toast_remaining -= delta
	if toast_remaining <= 0:
		toast.text = ""
		if not toast_queue.is_empty():
			toast.text = toast_queue.pop_front()
			toast_remaining = 1.5

func _health(hp: int, maximum: int) -> void:
	for child in hp_row.get_children():
		child.free()
	for i in maximum:
		var pip := Glyph.new()
		pip.name = "HpPip%d" % i
		pip.custom_minimum_size = Vector2(42, 46)
		pip.filled = i < hp
		hp_row.add_child(pip)
		_ignore_mouse(pip)
		pip.modulate.a = 0.35
		create_tween().tween_property(pip, "modulate:a", 1.0, 0.18)

func _score(value: int, multiplier: float) -> void:
	if score_tween != null:
		score_tween.kill()
	score_tween = create_tween()
	score_tween.tween_method(_display_score, displayed_score, float(value), 0.16)
	multiplier_label.text = "×%.1f" % multiplier

func _display_score(value: float) -> void:
	displayed_score = value
	score_label.text = "%08d" % roundi(value)

func _speed(value: float, normalized: float) -> void:
	speed_label.text = "SPEED %.1f m/s" % value
	speed_bar.value = clampf(normalized, 0, 1)

func _pursuit_started(seconds: float) -> void:
	recovery_seconds = seconds
	pursuit_warning.show()
	_pursuit_progress(seconds, seconds)

func _pursuit_progress(remaining: float, total: float) -> void:
	pursuit_remaining = remaining
	recovery_seconds = total
	pursuit_ring.fraction = clampf(remaining / maxf(total, 0.001), 0, 1)
	pursuit_ring.queue_redraw()
	pursuit_label.text = "UNREVIEWED BACKLOG · %.1f" % remaining
	vignette_material.set_shader_parameter("strength", 0.85 * (1 - pursuit_ring.fraction))

func _recovered(_reason: StringName) -> void:
	pursuit_warning.hide()
	vignette_material.set_shader_parameter("strength", 0.0)
	_toast("RECOVERED +2 APPROVALS")

func _caught() -> void:
	widgets.hide()
	pursuit_warning.hide()
	vignette_material.set_shader_parameter("strength", 1.0)

func _state(value: StringName) -> void:
	get_ready.visible = value == &"ready"
	if value == &"running":
		widgets.show()
	elif value == &"caught" or value == &"finished":
		_caught()

func _paused(value: bool) -> void:
	widgets.modulate.a = 0.35 if value else 1.0

func _damage(_kind: StringName, _hp: int) -> void:
	_flash(Color(1, 1, 1, 0.55))

func _blocked(_kind: StringName, _reason: StringName) -> void:
	_flash(Color(Palette.MINT, 0.3))
	_toast("BLOCKED")

func _flash(color: Color) -> void:
	if flash_tween != null:
		flash_tween.kill()
	hit_flash.color = color
	flash_tween = create_tween()
	flash_tween.tween_property(hit_flash, "color:a", 0.0, 0.18)

func _toast(message: String) -> void:
	toast_queue.append(message)

func _powerup(kind: StringName, duration: float) -> void:
	if kind == &"auto_fix":
		return
	_expire(kind)
	var column := VBoxContainer.new()
	powerups.add_child(column)
	column.add_child(Style.label(String(kind).replace("_", " ").to_upper(), 14, Palette.MINT))
	var bar := _bar(Vector2(90, 6))
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(bar)
	bar.value = 1
	bar.visible = duration > 0
	chips[kind] = {"node": column, "bar": bar, "remaining": duration, "total": duration}
	_ignore_mouse(column)
	if kind == &"nitro":
		nitro_banner.show()
		multiplier_label.add_theme_color_override("font_color", Palette.ORANGE)

func _expire(kind: StringName) -> void:
	if chips.has(kind):
		chips[kind].node.free()
		chips.erase(kind)
	if kind == &"nitro":
		nitro_banner.hide()
		multiplier_label.add_theme_color_override("font_color", Palette.MINT)

func _shield(active: bool) -> void:
	if active:
		_powerup(&"approve_shield", 0)
		_toast("SHIELD READY")
	else:
		_expire(&"approve_shield")
