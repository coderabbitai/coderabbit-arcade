extends Control
const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Pursuer = preload("res://scenes/runner/pursuer/pursuer_visual.gd")
const Scanline = preload("res://scenes/runner/shaders/scanline_portrait.gdshader")
var game: Node
var panel: PanelContainer
var portrait_viewport: SubViewport
var portrait: TextureRect
var portrait_material: ShaderMaterial
var copy: Label
var countdown: Label
var catch_rule: Label
var heading: Label
var waveform: Control
var radar: Control
var clock := 0.0
var fraction := 1.0
var radar_rate := 0.9
var radar_phase := 0.0
var state := &"hidden"
var beat_time := 0.0
var blocked_time := 0.0
var _connections := {}
var _audio: Node

class PortraitArt extends Control:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 256, 256), Palette.NAVY_BG)
		for row in 4:
			for column in 5:
				draw_rect(Rect2(5 + column * 50, 16 + row * 54, 46, 48), Palette.NAVY)
		for side in [-1, 1]:
			draw_line(Vector2(128 + side * 20, 66), Vector2(128 + side * 78, 53), Palette.DANGER, 9)
		var font := Style.theme().default_font
		for i in 3:
			draw_string(font, Vector2(12, 128 + i * 38), Pursuer.HEADLINES[i], HORIZONTAL_ALIGNMENT_LEFT, 236, 18, Palette.CREAM)

class Waveform extends Control:
	var clock := 0.0
	var fraction := 1.0
	var tint := Palette.MATRIX
	func _draw() -> void:
		var points := PackedVector2Array()
		for i in 48:
			var amplitude := absf(sin(i * 0.7 + clock * 6) * sin(i * 0.31 + clock * 2.3))
			var height := 2 + amplitude * 11 * (1.0 - fraction)
			points.append(Vector2(i * 8, 13 - height))
			points.append(Vector2(i * 8, 13 + height))
		draw_multiline(points, tint, 3, true)

class Radar extends Control:
	var phase := 0.0
	var fraction := 1.0
	func _draw() -> void:
		var center := Vector2(44, 44)
		for radius in [14, 27, 40]:
			draw_arc(center, radius, 0, TAU, 48, Palette.SLATE, 3, true)
		draw_line(center, center + Vector2.from_angle(phase * TAU) * 40, Palette.CREAM, 3, true)
		draw_circle(center + Vector2.from_angle(-0.7) * 40 * lerpf(0.9, 0.12, fraction), 4, Palette.DANGER)
		draw_arc(center, 4 + phase * 36, 0, TAU, 48, Color(Palette.DANGER, 1 - phase), 3, true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	theme = Style.theme()
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 28
	offset_top = -236
	offset_right = 448
	offset_bottom = -40
	panel = PanelContainer.new()
	panel.clip_contents = true
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Style.panel(Palette.DANGER, 0.96))
	# A plain Control preserves the exact 420 x 196 composition inside the backing.
	var content := Control.new()
	panel.add_child(content)
	portrait_viewport = SubViewport.new()
	portrait_viewport.name = "PortraitViewport"
	portrait_viewport.size = Vector2i(256, 256)
	portrait_viewport.disable_3d = true
	portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(portrait_viewport)
	portrait_viewport.add_child(PortraitArt.new())
	var back_buffer := BackBufferCopy.new()
	back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	portrait_viewport.add_child(back_buffer)
	var scan := ColorRect.new()
	scan.size = Vector2(256, 256)
	portrait_material = ShaderMaterial.new()
	portrait_material.shader = Scanline
	scan.material = portrait_material
	portrait_viewport.add_child(scan)
	portrait = TextureRect.new()
	portrait.texture = portrait_viewport.get_texture()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	content.add_child(portrait)
	portrait.position = Vector2(0, 30)
	portrait.size = Vector2(76, 76)
	heading = _label(content, "INCOMING TRANSMISSION", 20, Vector2.ZERO, Vector2(390, 26))
	copy = _label(content, "UNREVIEWED PR\nBACKLOG", 20, Vector2(84, 28), Vector2(218, 54))
	countdown = _label(content, "CATCHES UP IN 18.0 s", 20, Vector2(84, 82), Vector2(308, 26))
	catch_rule = _label(content, "ONE MORE HIT BEFORE RECOVERY\nAND IT HAS YOU", 17, Vector2(0, 110), Vector2(392, 42))
	catch_rule.add_theme_color_override("font_color", Color(Palette.CREAM, 0.85))
	catch_rule.set_meta("legibility_exemption", "Design section 2: catch-rule caption at 17 units")
	waveform = Waveform.new()
	content.add_child(waveform)
	waveform.position = Vector2(6, 154)
	waveform.size = Vector2(380, 26)
	radar = Radar.new()
	content.add_child(radar)
	radar.position = Vector2(304, 0)
	radar.size = Vector2(88, 88)
	_mouse_ignore(self)
	hide()

func _label(parent: Node, text: String, size_units: int, at: Vector2, extent: Vector2) -> Label:
	var label := Style.label(text, size_units)
	parent.add_child(label)
	label.position = at
	label.size = extent
	return label

func _mouse_ignore(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_mouse_ignore(child)

func bind(runner: Node) -> void:
	if game == runner:
		return
	if is_instance_valid(game):
		for event in _connections:
			if game.is_connected(event, _connections[event]):
				game.disconnect(event, _connections[event])
	game = runner
	_audio = null
	_connections = {&"pursuit_started": _started, &"pursuit_progress": _progress,
		&"pursuit_recovered": _recovered, &"damage_blocked": _blocked, &"caught": _caught,
		&"state_changed": _state_changed}
	if game.has_signal("pursuit_alert"):
		_connections[&"pursuit_alert"] = _alert
	for event in _connections:
		if game.has_signal(event):
			game.connect(event, _connections[event])

func _started(seconds: float) -> void:
	state = &"incoming"
	clock = 0.0
	beat_time = 0.0
	blocked_time = 0.0
	radar_phase = 0.0
	position.x = -440
	portrait.position = Vector2(0, 30)
	portrait.size = Vector2(76, 76)
	portrait.scale = Vector2.ONE
	portrait.pivot_offset = Vector2.ZERO
	for node in [heading, copy, countdown, catch_rule, waveform, radar]:
		node.show()
	copy.text = "UNREVIEWED PR\nBACKLOG"
	heading.text = "INCOMING TRANSMISSION"
	_progress(seconds, seconds)
	show()

func _progress(remaining: float, total: float) -> void:
	fraction = clampf(remaining / maxf(total, 0.001), 0, 1)
	radar_rate = lerpf(0.9, 4.2, 1 - fraction)
	countdown.text = "CATCHES UP IN %.1f s" % remaining

func _alert(kind: StringName, seconds: float) -> void:
	# Optional v2 hint. Existing v1 events own lifecycle, avoiding duplicate starts.
	if kind == &"warn" and state == &"hidden":
		_started(seconds)

func _recovered(_reason: StringName) -> void:
	if state not in [&"incoming", &"pursuit"]:
		return
	state = &"recovered"
	beat_time = 0.0
	blocked_time = 0.0
	heading.text = "RECOVERED"
	copy.text = "BACKLOG REVIEWED"
	countdown.text = "+2 APPROVALS"
	catch_rule.hide()
	radar.hide()

func _blocked(_kind: StringName, _reason: StringName) -> void:
	if state in [&"incoming", &"pursuit"]:
		blocked_time = 0.6
		heading.text = "BLOCKED"

func _caught() -> void:
	if state == &"caught":
		return
	state = &"caught"
	beat_time = 0.0
	show()
	position.x = 28
	portrait.position = Vector2.ZERO
	portrait.size = Vector2(392, 180)
	portrait.pivot_offset = portrait.size * 0.5
	for node in [heading, copy, countdown, catch_rule, waveform, radar]:
		node.hide()

func _state_changed(value: StringName) -> void:
	if value in [&"ready", &"running", &"finished"]:
		state = &"hidden"
		hide()

func _process(delta: float) -> void:
	if not visible or (is_instance_valid(game) and bool(game.get("paused"))):
		return
	clock += delta
	beat_time += delta
	blocked_time = maxf(0, blocked_time - delta)
	if state == &"incoming":
		position.x = lerpf(-440, 28, 1 - pow(1 - minf(beat_time / 0.28, 1), 3))
		if beat_time >= 0.28:
			state = &"pursuit"
	if state == &"pursuit" and blocked_time <= 0:
		heading.text = "INCOMING TRANSMISSION"
	var accent := Palette.MATRIX if state == &"recovered" else Palette.DANGER
	if blocked_time > 0:
		accent = Palette.MINT
	elif state == &"incoming" and beat_time < 0.08:
		accent = Palette.CREAM
	(panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = accent
	portrait_material.set_shader_parameter("clock", clock)
	portrait_material.set_shader_parameter("threat", 1 - fraction)
	radar_phase = fposmod(radar_phase + delta * radar_rate, 1.0)
	if not is_instance_valid(_audio) and is_instance_valid(game):
		var candidate := game.find_child("RunnerAudio", true, false)
		if candidate != null and candidate.has_method("pursuit_radar_phase"):
			_audio = candidate
	if is_instance_valid(_audio) and state in [&"incoming", &"pursuit"]:
		radar_phase = _audio.pursuit_radar_phase()
	radar.phase = radar_phase
	radar.fraction = fraction
	radar.queue_redraw()
	waveform.clock = clock
	waveform.fraction = fraction
	waveform.tint = Palette.MATRIX if state == &"recovered" else Palette.MATRIX.lerp(Palette.DANGER, 1 - fraction)
	waveform.queue_redraw()
	if state == &"recovered" and beat_time > 1.2:
		_slide_out((beat_time - 1.2) / 0.22)
	elif state == &"caught":
		portrait.scale = Vector2.ONE * lerpf(1, 1.35, minf(beat_time / 0.45, 1))
		if beat_time > 0.45:
			_slide_out((beat_time - 0.45) / 0.22)

func _slide_out(progress: float) -> void:
	position.x = lerpf(28, -440, minf(progress, 1))
	if progress >= 1:
		state = &"hidden"
		hide()
