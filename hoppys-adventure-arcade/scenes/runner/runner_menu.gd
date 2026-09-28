extends Node3D
## Scene-local entry point. Gameplay and persistence remain backend-owned.
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
const Style = preload("res://scenes/runner/ui/hud_style.gd")
const Leaderboard = preload("res://scenes/runner/systems/runner_leaderboard.gd")
const Music = preload("res://Assets/Backgrounds/cyberpunk-street-files/Assets/music/cyberpunk-street.ogg")

var buttons: Array[Button] = []
var ui: Control
var shade: TextureRect
var modal: Control
var board: VBoxContainer
var elapsed := 0.0
var title_label: Label
@onready var audio_service: Node = get_node("/root/AudioService")
@onready var router: Node = get_node("/root/AppRouter")
@onready var camera: Camera3D = $Backdrop/Camera

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	$Backdrop/Corridor.set_scroll_speed(3.5)
	$Backdrop/Hoppy.set_anim_state(&"run")
	$Backdrop/Hoppy.set_run_speed(0.25)
	camera.look_at(Vector3(0, 1.0, -2))
	if audio_service.has_method("play_music"):
		audio_service.play_music(Music, -12.0)
	ui = Control.new()
	ui.theme = Style.theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Interface.add_child(ui)
	shade = TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.025, 0.045, 0.08, 0.97))
	gradient.set_color(1, Color(0.025, 0.045, 0.08, 0.12))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(1, 0.1)
	shade.texture = texture
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	_label("C O D E R A B B I T / E N D L E S S R U N N E R", 14, Vector2(76, 39), Style.MINT)
	_label("THE CODEBASE\nCORRIDOR", 60, Vector2(72, 96))
	_label("Outrun the unreviewed backlog.", 17, Vector2(77, 260))
	var column := VBoxContainer.new()
	column.position = Vector2(76, 310)
	column.add_theme_constant_override("separation", 12)
	ui.add_child(column)
	for text in ["01   Play", "02   Leaderboard", "03   Return to Main Menu", "04   Quit Game"]:
		var button := Style.button(text)
		column.add_child(button)
		buttons.append(button)
		button.focus_entered.connect(_focus_sound)
		button.mouse_entered.connect(_focus_sound)
	buttons[0].pressed.connect(_route.bind("runner_game"))
	buttons[1].pressed.connect(_toggle_leaderboard)
	buttons[2].pressed.connect(_route.bind("hub"))
	buttons[3].pressed.connect(_quit)
	for i in buttons.size():
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
		buttons[i].focus_previous = buttons[i].focus_neighbor_top
		buttons[i].focus_next = buttons[i].focus_neighbor_bottom
	var card := PanelContainer.new()
	card.position = Vector2(714, 384)
	card.custom_minimum_size = Vector2(490, 210)
	card.add_theme_stylebox_override("panel", _panel_style())
	Style.polish(card, true)
	ui.add_child(card)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	card.add_child(controls)
	controls.add_child(Style.label("KEEP THE BUILD MOVING", 26, Style.MINT))
	controls.add_child(Style.label("A / D · ← →  Change lane\nW / SPACE / ↑  Jump\nS / CTRL / ↓  Roll\nESC / START  Pause", 22))
	controls.add_child(Style.teaching_legend(true))
	controls.add_child(Style.label("Two hits without recovery\nand the backlog catches you.", 18))
	_label("↑ ↓ / D-PAD  SELECT    ENTER / A  CONFIRM    ESC / B  BACK", 12, Vector2(76, 670), Color("9baebc"))
	buttons[0].grab_focus()
	_process(0.0)

func _label(text: String, size: int, position_2d: Vector2, color: Color = Style.CREAM) -> void:
	var label := Style.label(text, size, color)
	var backing := PanelContainer.new()
	backing.position = position_2d - Vector2(14, 8)
	backing.add_theme_stylebox_override("panel", Style.panel(Style.MINT if size == 60 else Palette.SLATE, 0.88))
	Style.polish(backing, size == 60)
	ui.add_child(backing)
	backing.add_child(label)
	if size == 60: title_label = label

func _panel_style() -> StyleBoxFlat:
	var box := Style.panel(Style.MINT, 0.96)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 20
	box.content_margin_bottom = 20
	return box

func _process(delta: float) -> void:
	elapsed += delta
	if title_label != null:
		title_label.add_theme_color_override("font_color", Style.CREAM.lerp(Style.MINT, 0.08 + 0.06 * sin(elapsed * 1.4)))
	camera.position = Vector3(2.6 + sin(elapsed * 0.18) * 0.12, 1.9 + sin(elapsed * 0.23) * 0.04, 3.4)
	camera.look_at(Vector3(0, 1.0, -2))
	var viewport_size := get_viewport().get_visible_rect().size
	var fit := minf(1.0, minf(viewport_size.x / 1280.0, viewport_size.y / 720.0))
	ui.scale = Vector2.ONE * fit
	ui.size = Vector2(1280, 720)
	ui.position = (viewport_size - ui.size * fit) * 0.5
	shade.position = -ui.position / fit
	shade.size = viewport_size / fit
	if modal:
		modal.get_child(0).position = shade.position
		modal.get_child(0).size = shade.size

func _focus_sound() -> void:
	if not router.busy:
		audio_service.play_ui(0)

func _route(route: String) -> void:
	if modal or router.busy:
		return
	audio_service.play_ui(1)
	router.go(route)

func _quit() -> void:
	if modal or router.busy:
		return
	audio_service.play_ui(1)
	router.quit_game()

func _toggle_leaderboard() -> void:
	if router.busy:
		return
	if modal:
		_close_leaderboard()
		return
	audio_service.play_ui(1)
	for button in buttons:
		if button == buttons[1]:
			continue
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = true
	modal = Control.new()
	modal.name = "Leaderboard"
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.9)
	modal.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(280, 70)
	panel.custom_minimum_size = Vector2(720, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	Style.polish(panel, true)
	modal.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(Style.label("LOCAL LEADERBOARD", 28))
	column.add_child(Style.label("RANK  NAME                 SCORE     TIME", 18, Style.MINT))
	board = VBoxContainer.new()
	board.add_theme_constant_override("separation", 8)
	column.add_child(board)
	var entries := Leaderboard.load_entries()
	for i in 10:
		var text := "%02d    ---                  ---       ---" % (i + 1)
		if i < entries.size():
			var entry: Dictionary = entries[i]
			var seconds := maxi(0, int(entry.duration))
			text = "%02d    %-16s  %8d     %02d:%02d" % [i + 1, entry.name, entry.score, seconds / 60, seconds % 60]
		var row := HBoxContainer.new()
		row.add_child(rank_marker(i, i < entries.size()))
		row.add_child(Style.label(text, 18))
		board.add_child(row)
	var close := Style.button("Close", 46)
	column.add_child(close)
	close.pressed.connect(_close_leaderboard)
	close.focus_entered.connect(_focus_sound)
	close.mouse_entered.connect(_focus_sound)
	for direction in ["focus_neighbor_top", "focus_neighbor_bottom", "focus_next", "focus_previous"]:
		close.set(direction, close.get_path_to(close))
	close.grab_focus()
	_process(0.0)

func _close_leaderboard() -> void:
	if not modal or router.busy:
		return
	modal.queue_free()
	modal = null
	board = null
	for button in buttons:
		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL
	buttons[1].grab_focus()
	audio_service.play_ui(1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not router.busy:
		if modal:
			_close_leaderboard()
		else:
			_route("hub")
		get_viewport().set_input_as_handled()

static func rank_marker(index: int, occupied: bool) -> Control:
	if occupied and index < 3:
		return Style.icon(&"medal", [Palette.CREAM.lerp(Palette.ORANGE, 0.35), Palette.SLATE.lerp(Palette.CREAM, 0.65), Palette.ORANGE.lerp(Palette.NAVY_2, 0.3)][index], Vector2(24,24))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24,24)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
