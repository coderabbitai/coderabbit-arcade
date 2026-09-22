extends CanvasLayer
const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Glyph = preload("res://scenes/runner/ui/hud_glyph.gd")
const Corridor = preload("res://scenes/runner/environment/corridor.gd")
const TurnFx = preload("res://scenes/runner/environment/turn_fx.gd")
const Vignette = preload("res://scenes/runner/shaders/vignette.gdshader")
var turn_fx: Node3D
var turn_panel: PanelContainer
var turn_label: Label
var turn_icon: Control
var warning_age := 0.0
var warning_seconds := 0.0
var warning_direction := 0
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
var toast_queue: Array[Dictionary] = []
var toast_priority := -1
var toast_accent := Palette.MINT
var toast_sequence := -1
var _next_toast_sequence := 0
var toast_age := 0.0
var ready_age := 0.0
var _gameplay_visible := true
var _ready_seen := false
var pursuit_alert: Control
var toast_panel: PanelContainer
var nitro_panel: PanelContainer
var ready_panel: PanelContainer
var pursuit_panel: PanelContainer
var toast_remaining := 0.0
var turn_alpha := 1.0
var pulse_clock := 0.0
var teaching_seen := {}
var teaching_pending: Array[Dictionary] = []
var teaching_block_seconds := 0.0
var teaching_phase: StringName = &"run"
var toast_duration := 1.5
var toast_teaching := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	_back(left, Control.PRESET_TOP_LEFT, Vector2(28, 28), Vector2(240, 100), Palette.MINT)
	left.add_child(Style.label("APPROVALS", 18, Palette.MINT))
	hp_row = HBoxContainer.new()
	hp_row.name = "HpRow"
	left.add_child(hp_row)
	powerups = VBoxContainer.new()
	powerups.name = "PowerUps"
	left.add_child(powerups)
	time_label = Style.label("00:00.0", 30)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back(time_label, Control.PRESET_TOP_RIGHT, Vector2(-228, 140), Vector2(200, 56), Palette.SLATE, 0.70)
	pursuit_warning = HBoxContainer.new()
	pursuit_warning.name = "PursuitWarning"
	pursuit_warning.alignment = BoxContainer.ALIGNMENT_CENTER
	pursuit_panel = _back(pursuit_warning, Control.PRESET_TOP_RIGHT, Vector2(-280, 208), Vector2(252, 64), Palette.DANGER)
	pursuit_ring = Glyph.new()
	pursuit_ring.ring = true
	pursuit_ring.custom_minimum_size = Vector2(36, 36)
	pursuit_warning.add_child(pursuit_ring)
	pursuit_label = Style.label("", 18)
	pursuit_warning.add_child(pursuit_label)
	pursuit_warning.hide()
	pursuit_panel.hide()
	var right := VBoxContainer.new()
	_back(right, Control.PRESET_TOP_RIGHT, Vector2(-280, 28), Vector2(252, 100), Palette.MINT)
	score_label = Style.label("00000000", 36, Palette.MINT)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(score_label)
	multiplier_label = Style.label("×1", 24, Palette.MINT)
	multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(multiplier_label)
	var bottom := VBoxContainer.new()
	_back(bottom, Control.PRESET_BOTTOM_RIGHT, Vector2(-316, -100), Vector2(288, 72), Palette.SLATE, 0.70)
	speed_label = Style.label("SPEED 0.0 m/s", 20)
	bottom.add_child(speed_label)
	speed_bar = _bar(Vector2(260, 12))
	bottom.add_child(speed_bar)
	var tick := ColorRect.new()
	tick.color = Palette.CREAM
	speed_bar.add_child(tick)
	tick.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tick.position = Vector2(260.0 * 26.0 / 32.0, 0)
	tick.size = Vector2(2, 12)
	toast = Style.label("", 28)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_panel = _back(toast, Control.PRESET_CENTER_TOP, Vector2(0, 172), Vector2.ZERO, Palette.MINT)
	toast_panel.hide()
	nitro_banner = Style.label("NITRO COMMIT!", 34, Palette.ORANGE)
	nitro_banner.name = "NitroBanner"
	nitro_panel = _back(nitro_banner, Control.PRESET_CENTER_BOTTOM, Vector2(-160, -100), Vector2(320, 64), Palette.ORANGE)
	nitro_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nitro_banner.hide()
	nitro_panel.hide()
	var ready_box := VBoxContainer.new()
	ready_panel = _back(ready_box, Control.PRESET_CENTER_BOTTOM, Vector2(-500, -190), Vector2(1000, 160), Palette.MINT, 0.88)
	get_ready = Style.label("GET READY", 34)
	get_ready.name = "GetReady"
	get_ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_box.add_child(get_ready)
	for line in ["A / D · ← / →  lane    SPACE / A  jump", "S / ↓ / B  roll    ESC / START  pause"]:
		var hint := Style.label(line, 22)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ready_box.add_child(hint)
	ready_box.add_child(Style.teaching_legend())
	ready_panel.visibility_changed.connect(_sync_ready_speed)
	_sync_ready_speed()
	hit_flash = ColorRect.new()
	hit_flash.name = "HitFlash"
	screen.add_child(hit_flash)
	hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_flash.color = Color(1, 1, 1, 0)
	turn_label = Style.label("", 34, Palette.ORANGE)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_panel = _back(turn_label, Control.PRESET_CENTER_TOP, Vector2(-180, 536), Vector2(360, 76), Palette.DANGER, 0.94)
	turn_panel.hide()
	turn_icon = Style.icon(&"arrow", Palette.ORANGE)
	turn_label.add_child(turn_icon)
	turn_icon.position = Vector2(4, 16)
	turn_icon.size = Vector2(30, 30)
	turn_icon.pivot_offset = Vector2(15, 15)
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

func _back(content: Control, preset: int, offset: Vector2, extent: Vector2, accent: Color, alpha: float = 0.82) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel(accent, alpha))
	Style.polish(panel, false)
	_place(panel, preset, offset, extent)
	panel.add_child(content)
	return panel

func _bar(extent: Vector2) -> ProgressBar:
	return Style.bar(extent, Palette.MINT)

func bind(runner: Node) -> void:
	if game == runner:
		return
	game = runner
	turn_fx = TurnFx.new()
	for node: Node in game.find_children("*", "Node3D", true, false):
		if node is Corridor:
			node.add_child(turn_fx)
			break
	if game.has_signal("turn_incoming"): game.turn_incoming.connect(_turn_incoming)
	if game.has_signal("turn_started"): game.turn_started.connect(_turn_started)
	if game.has_signal("turn_finished"): game.turn_finished.connect(_turn_finished)
	if game.has_signal("phase_changed"): game.phase_changed.connect(_turn_phase)
	if game.has_method("_mount_frontend"):
		# RunnerGame mounts the sibling alert after binding this HUD.
		_find_mounted_alert.call_deferred()
	else:
		# v1 facades and the standalone preview have no backend mount owner.
		var alert_scene := load("res://scenes/runner/ui/pursuit_alert.tscn") as PackedScene
		if alert_scene != null:
			pursuit_alert = alert_scene.instantiate() as Control
			widgets.add_child(pursuit_alert)
			pursuit_alert.bind(game)
	game.health_changed.connect(_health)
	game.score_changed.connect(_score)
	game.speed_changed.connect(_speed)
	game.pursuit_started.connect(_pursuit_started)
	game.pursuit_progress.connect(_pursuit_progress)
	game.pursuit_recovered.connect(_recovered)
	game.caught.connect(_caught)
	game.state_changed.connect(_state)
	game.paused_changed.connect(_paused)
	if game.has_signal("damage_taken"): game.damage_taken.connect(_damage)
	game.damage_blocked.connect(_blocked)
	if game.has_signal("power_up_collected"):
		game.power_up_collected.connect(_powerup)
		game.power_up_collected.connect(_first_powerup)
	if game.has_signal("tool_collected"): game.tool_collected.connect(_first_tool)
	if game.has_signal("run_started"): game.run_started.connect(_reset_teaching)
	if game.has_signal("boss_intro"): game.boss_intro.connect(_teaching_intro)
	if game.has_signal("stage_cleared"): game.stage_cleared.connect(_teaching_clear)
	game.power_up_expired.connect(_expire)
	game.shield_changed.connect(_shield)
	game.hazards_blasted.connect(func(count: int) -> void: _toast("AUTO-FIX ×%d" % count))
	game.bonus_awarded.connect(func(points: int, _reason: StringName) -> void: _toast("+%d BONUS" % points))
	_health(game.hp, game.config.max_hp)
	_score(game.score, game.multiplier)
	_speed(game.speed, game.normalized_speed)
	_state(game.state)
	_paused(game.paused)

func _find_mounted_alert() -> void:
	if not is_instance_valid(game):
		return
	pursuit_alert = game.get_node_or_null("HUD/PursuitAlert") as Control
	_paused(game.paused)

func _process(delta: float) -> void:
	if game == null or game.paused:
		return
	if not _gameplay_visible:
		return
	teaching_block_seconds = maxf(0.0, teaching_block_seconds - delta)
	if toast_remaining <= 0 and not _teaching_blocked() and not teaching_pending.is_empty():
		var hint: Dictionary = teaching_pending.pop_front()
		_toast(hint.text, 10, hint.accent, 2.4, true)
	if turn_panel.visible:
		warning_age += delta
		_update_turn_warning()
	var seconds := float(game.elapsed)
	time_label.text = "%02d:%04.1f" % [int(seconds) / 60, fmod(seconds, 60)]
	for kind in chips:
		var chip: Dictionary = chips[kind]
		if chip.total > 0:
			chip.remaining = maxf(0, chip.remaining - delta)
			chip.bar.value = chip.remaining / chip.total
			chip.label.visible = chip.total - chip.remaining < 0.6
	if pursuit_warning.visible:
		pulse_clock += delta * lerpf(3, 12, 1 - pursuit_ring.fraction)
		pursuit_warning.modulate.a = 0.75 + 0.25 * sin(pulse_clock)
		vignette_material.set_shader_parameter("pulse", 0.5 + 0.5 * sin(pulse_clock))
	var speed_panel: Control = speed_label.get_parent().get_parent()
	if speed_panel.visible:
		speed_panel.self_modulate.a = minf(1.0, speed_panel.self_modulate.a + delta / 0.18)
	ready_age += delta
	ready_panel.modulate.a = clampf(1.0 - (ready_age - 2.5) / 0.25, 0, 1)
	if ready_age >= 2.75:
		ready_panel.hide()
		get_ready.hide()
	toast_remaining -= delta
	toast_age += delta
	toast_panel.modulate.a = minf(1.0, toast_age / 0.12) * turn_alpha
	if toast_remaining <= 0:
		toast.text = ""
		toast_priority = -1
		toast_panel.hide()
		if not toast_queue.is_empty():
			_show_toast(toast_queue.pop_front())
	toast_panel.size = toast_panel.get_combined_minimum_size()
	toast_panel.position.x = widgets.size.x * 0.5 - toast_panel.size.x * 0.5
	nitro_panel.visible = nitro_banner.visible and toast.text.is_empty() and not ready_panel.visible

func _health(hp: int, maximum: int) -> void:
	for child in hp_row.get_children():
		child.free()
	for i in maximum:
		var pip := Glyph.new()
		pip.name = "HpPip%d" % i
		pip.custom_minimum_size = Vector2(48, 52)
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
	multiplier_label.text = "×%d" % roundi(multiplier) if is_equal_approx(multiplier, roundf(multiplier)) else "×%s" % str(snappedf(multiplier, 0.01))

func _display_score(value: float) -> void:
	displayed_score = value
	score_label.text = "%08d" % roundi(value)

func _speed(value: float, _normalized: float) -> void:
	speed_label.text = "SPEED %.1f m/s" % value
	speed_bar.value = clampf(value / 32.0, 0, 1)

func _pursuit_started(seconds: float) -> void:
	recovery_seconds = seconds
	pursuit_warning.show()
	pursuit_panel.show()
	ready_panel.hide()
	get_ready.hide()
	_pursuit_progress(seconds, seconds)

func _pursuit_progress(remaining: float, total: float) -> void:
	pursuit_remaining = remaining
	recovery_seconds = total
	pursuit_ring.fraction = clampf(remaining / maxf(total, 0.001), 0, 1)
	pursuit_ring.queue_redraw()
	pursuit_ring.seconds = remaining
	pursuit_label.text = "BACKLOG  %.1fs" % remaining
	vignette_material.set_shader_parameter("strength", 0.25 + 0.6 * (1 - pursuit_ring.fraction))

	vignette_material.set_shader_parameter("corner_bars", 1 - pursuit_ring.fraction)

func _recovered(_reason: StringName) -> void:
	pursuit_warning.hide()
	pursuit_panel.hide()
	vignette_material.set_shader_parameter("corner_bars", 0.0)
	vignette_material.set_shader_parameter("strength", 0.0)
	_toast("RECOVERED +2 APPROVALS")

func _caught() -> void:
	_gameplay_visible = false
	for child in widgets.get_children():
		if child != pursuit_alert:
			child.hide()
	pursuit_warning.hide()
	pursuit_panel.hide()
	vignette_material.set_shader_parameter("corner_bars", 0.0)
	vignette_material.set_shader_parameter("strength", 1.0)

func _state(value: StringName) -> void:
	if value != &"running": _turn_finished()
	var show_ready := value == &"ready" or (value == &"running" and _ready_seen and ready_age < 2.75)
	get_ready.visible = show_ready
	ready_panel.visible = show_ready
	if value == &"ready":
		_ready_seen = true
		ready_age = 0.0
		ready_panel.modulate.a = 1.0
	if value == &"ready" or value == &"running":
		_gameplay_visible = true
		widgets.show()
		for child in widgets.get_children():
			if child is PanelContainer and child not in [ready_panel, toast_panel, nitro_panel, pursuit_panel, turn_panel]:
				child.show()
		widgets.modulate.a = 1.0
		vignette_material.set_shader_parameter("strength", 0.0)
		vignette_material.set_shader_parameter("corner_bars", 0.0)
		if flash_tween != null:
			flash_tween.kill()
			flash_tween = null
		hit_flash.color.a = 0.0
		toast_queue.clear()
		toast.text = ""
		toast_remaining = 0.0
		toast_priority = -1
		toast_panel.hide()
	elif value == &"caught" or value == &"finished":
		_caught()
	_sync_ready_speed()

func _sync_ready_speed() -> void:
	# GET READY shares the lower band with SPEED, but never its visible surface.
	var panel: Control = speed_label.get_parent().get_parent()
	panel.visible = _gameplay_visible and not ready_panel.visible
	if not panel.visible: panel.self_modulate.a = 0.0

func _paused(value: bool) -> void:
	widgets.modulate.a = 0.35 if value else 1.0
	if is_instance_valid(pursuit_alert) and pursuit_alert.get_parent() != widgets:
		pursuit_alert.modulate.a = widgets.modulate.a

func _damage(_kind: StringName, _hp: int) -> void:
	_flash(Color(1, 1, 1, 0.55))
	_teach(&"damage", "RED = AVOID \u2014 jump or roll past hazards", Palette.DANGER)

func _blocked(_kind: StringName, _reason: StringName) -> void:
	_flash(Color(Palette.MINT, 0.3))
	_toast("BLOCKED")

func _flash(color: Color) -> void:
	if flash_tween != null:
		flash_tween.kill()
	hit_flash.color = color
	flash_tween = create_tween()
	flash_tween.tween_property(hit_flash, "color:a", 0.0, 0.18)

func _toast(message: String, priority: int = 0, accent: Color = Palette.MINT, duration: float = 1.5, teaching: bool = false) -> void:
	if message.begins_with("STAGE CLEAR") or message.begins_with("INCOMING"):
		priority = maxi(priority, 100)
		accent = Palette.DANGER if message.begins_with("INCOMING") else Palette.MATRIX
	elif message.begins_with("BLOCKED") or message.begins_with("RECOVERED"):
		priority = maxi(priority, 50)
		accent = Palette.MATRIX if message.begins_with("RECOVERED") else Palette.MINT
	var entry := {"text": message if teaching else message.left(26), "duration": duration, "teaching": teaching, "priority": priority, "accent": accent, "sequence": _next_toast_sequence}
	_next_toast_sequence += 1
	if toast_remaining > 0 and priority > toast_priority:
		toast_queue.append({"text": toast.text, "priority": toast_priority, "accent": toast_accent, "sequence": toast_sequence, "duration": toast_duration, "teaching": toast_teaching})
		_show_toast(entry)
	else:
		toast_queue.append(entry)
	toast_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.sequence < b.sequence if a.priority == b.priority else a.priority > b.priority)

func _show_toast(entry: Dictionary) -> void:
	toast.text = entry.text
	toast_priority = entry.priority
	toast_accent = entry.accent
	toast_sequence = entry.sequence
	toast_duration = entry.get("duration", 1.5)
	toast_teaching = entry.get("teaching", false)
	toast_remaining = toast_duration
	toast.add_theme_font_size_override("font_size", 18 if toast_teaching else 28)
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if toast_teaching else TextServer.AUTOWRAP_OFF
	toast.custom_minimum_size.x = 640 if toast_teaching else 0
	toast_age = 0.0
	toast_panel.add_theme_stylebox_override("panel", Style.panel(entry.accent))
	Style.polish(toast_panel, false)
	toast_panel.modulate.a = 0.0
	toast_panel.show()
	ready_panel.hide()
	get_ready.hide()

func _powerup(kind: StringName, duration: float) -> void:
	if kind == &"auto_fix":
		return
	_expire(kind)
	var column := VBoxContainer.new()
	powerups.add_child(column)
	var title := Style.label(String(kind).replace("_", " ").to_upper(), 18, Palette.MINT)
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	var icon := Style.icon(kind)
	icon.tooltip_text = String(kind).replace("_", " ")
	row.add_child(icon)
	var accessible := Style.label(String(kind).replace("_", " ").to_upper(), 18)
	accessible.name = "AccessiblePowerUpName"
	accessible.hide()
	icon.add_child(accessible)
	var bar := _bar(Vector2(112, 9))
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	bar.value = 1
	bar.visible = duration > 0
	chips[kind] = {"node": column, "label": title, "bar": bar, "remaining": duration, "total": duration}
	_ignore_mouse(column)
	if kind == &"nitro":
		nitro_banner.show()
		(speed_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Palette.ORANGE
		multiplier_label.add_theme_color_override("font_color", Palette.ORANGE)

func _expire(kind: StringName) -> void:
	if chips.has(kind):
		chips[kind].node.free()
		chips.erase(kind)
	if kind == &"nitro":
		nitro_banner.hide()
		nitro_panel.hide()
		(speed_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Palette.MINT
		multiplier_label.add_theme_color_override("font_color", Palette.MINT)

func _shield(active: bool) -> void:
	if active:
		_powerup(&"approve_shield", 0)
		_toast("SHIELD READY")
	else:
		_expire(&"approve_shield")

func _turn_started(_direction: int, _seconds: float) -> void:
	if is_instance_valid(turn_fx): turn_fx.clear()
	_dim_turn(0.55)

func _turn_finished() -> void:
	turn_panel.hide()
	if is_instance_valid(turn_fx): turn_fx.clear()
	_dim_turn(1.0)

func _turn_phase(value: StringName) -> void:
	teaching_phase = value
	if value in [&"boss_intro", &"stage_clear"]: _defer_teaching()
	if value in [&"idle", &"run"]: _turn_finished()
	if value != &"turn": _dim_turn(1.0)

func _dim_turn(alpha: float) -> void:
	turn_alpha = alpha
	for widget in [time_label.get_parent(), score_label.get_parent().get_parent(), speed_label.get_parent().get_parent(), powerups, toast_panel, nitro_panel]:
		widget.modulate.a = alpha

func _turn_incoming(direction: int, seconds: float) -> void:
	ready_panel.hide()
	get_ready.hide()
	warning_direction = direction
	warning_seconds = maxf(seconds, 0.001)
	warning_age = 0.0
	turn_fx.announce(direction)
	turn_panel.show()
	_update_turn_warning()

func _update_turn_warning() -> void:
	var tick := maxi(1, ceili(warning_seconds - warning_age))
	turn_label.text = ("TURN LEFT" if warning_direction < 0 else "TURN RIGHT") + " %d" % tick
	turn_icon.scale.x = -1.0 if warning_direction < 0 else 1.0
	turn_label.modulate.a = 0.65 + 0.35 * (1.0 - fposmod(warning_age, 1.0))

func _exit_tree() -> void:
	if is_instance_valid(turn_fx): turn_fx.queue_free()

func _reset_teaching(_seed: int = 0) -> void:
	toast_teaching = false
	teaching_seen.clear()
	teaching_pending.clear()
	teaching_block_seconds = 0.0
	teaching_phase = &"run"

func _first_powerup(kind: StringName, _duration: float) -> void:
	_teach(&"powerup", "GRABBED: %s \u2014 mint and orange items help you" % String(kind).replace("_", " ").to_upper(), Palette.MINT)

func _first_tool(kind: StringName, _damage: int) -> void:
	_teach(&"tool", "CODERABBIT TOOL: %s \u2014 auto-fires at the boss" % String(kind).replace("_", " ").to_upper(), Palette.ORANGE)

func _teach(category: StringName, message: String, accent: Color) -> void:
	if teaching_seen.has(category): return
	teaching_seen[category] = true
	teaching_pending.append({"text": message, "accent": accent})

func _teaching_blocked() -> bool:
	return teaching_block_seconds > 0 or teaching_phase in [&"boss_intro", &"stage_clear"]

func _teaching_intro(_kind: StringName, _name: String, seconds: float) -> void:
	teaching_block_seconds = maxf(teaching_block_seconds, seconds)
	_defer_teaching()

func _teaching_clear(_index: int, _bonus: int) -> void:
	teaching_block_seconds = maxf(teaching_block_seconds, 2.8)
	_defer_teaching()

func _defer_teaching() -> void:
	if toast_teaching and toast_remaining > 0:
		teaching_pending.push_front({"text": toast.text, "accent": toast_accent})
		toast_remaining = 0
		toast.text = ""
		toast_priority = -1
		toast_panel.hide()
	for entry in toast_queue:
		if entry.get("teaching", false): teaching_pending.append(entry)
	toast_queue = toast_queue.filter(func(entry: Dictionary) -> bool: return not entry.get("teaching", false))
