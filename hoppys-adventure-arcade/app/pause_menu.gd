extends CanvasLayer
## The pause menu every game shows: Resume, Restart, How to Play, Main Menu, in the hub's style.
##
## A game creates one with create() and owns the pause state itself: it pauses the tree (or its own
## state machine), then calls open(); resume closes it. The menu never pauses or unpauses anything,
## and it binds neither `pause` nor `ui_cancel`: Esc is both, and every game already toggles its
## pause on the `pause` action (ControllerService synthesizes that action on a pad disconnect).
## Restart and Main Menu run the game's callables, which end in AppRouter.go(); the menu locks its
## buttons on that press so a second press during the router's fade does nothing.
## Every game also gets a Leaderboard button that opens its local top ten (app/leaderboards.gd
## maps the route to the board) over the menu; the runner points it at its own board. A game may
## add further buttons of its own before Main Menu with add_button().

const Style := preload("res://scenes/main_menu/menu_style.gd")
const Data := preload("res://app/how_to_play_data.gd")
const Prompts := preload("res://app/controller_prompts.gd")
const HowToPlay := preload("res://app/how_to_play.gd")
const Leaderboards := preload("res://app/leaderboards.gd")
const LeaderboardPanel := preload("res://app/leaderboard_panel.gd")

## Above every game's HUD, results and story layers (at most 22), below the how-to-play card (89),
## ControllerService's disconnect banner (90) and the router's fade (100).
const LAYER := 80
const DIM := Color(0.01, 0.02, 0.04, 0.86)
const PANEL := Color("142735")
const BUTTON_HEIGHT := 54

var route := ""
var ui: Control
var column: VBoxContainer
var eyebrow: Label
var title_label: Label
var detail_label: Label
var resume_button: Button
var restart_button: Button
var how_to_play_button: Button
var menu_button: Button
var leaderboard_button: Button
## The board file the Leaderboard button opens; set after setup() to point at another board
## (the runner's game owns its path, tests use scratch files).
var leaderboard_path := ""
## The open leaderboard panel, or null.
var leaderboard: Control
## Every button in focus order, Main Menu last.
var buttons: Array[Button] = []
var locked := false
var _on_resume: Callable
var _on_restart: Callable
var _on_leave: Callable
var _opening := false

## Builds a hidden menu for `game_route` under `host` and returns it.
static func create(host: Node, game_route: String, on_resume: Callable, on_restart: Callable, on_leave: Callable) -> Node:
	var menu: Node = load("res://app/pause_menu.gd").new()
	host.add_child(menu)
	menu.setup(game_route, on_resume, on_restart, on_leave)
	return menu

func _init() -> void:
	name = "PauseMenu"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _ready() -> void:
	if ui == null:
		_build()

func setup(game_route: String, on_resume: Callable, on_restart: Callable, on_leave: Callable) -> void:
	route = game_route
	_on_resume = on_resume
	_on_restart = on_restart
	_on_leave = on_leave
	if ui == null:
		_build()
	var title: String = Data.game(route).get("title", "") if Data.has_game(route) else ""
	eyebrow.text = title.to_upper()
	eyebrow.visible = not title.is_empty()
	leaderboard_path = Leaderboards.path_for(route)
	if leaderboard_button == null:
		leaderboard_button = add_button("Leaderboard", _open_leaderboard)

func _build() -> void:
	ui = Control.new()
	ui.name = "Screen"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = Style.theme()
	# Swallow clicks, so the HUD's own pause button under the menu can't be pressed through it.
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ui)
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(center)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.border_color = Style.MINT
	box.set_border_width_all(2)
	box.content_margin_left = 34
	box.content_margin_right = 34
	box.content_margin_top = 22
	box.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size.x = 520
	panel.add_child(column)
	eyebrow = _label("", 18, Style.MINT)
	column.add_child(eyebrow)
	title_label = _label("PAUSED", 40)
	column.add_child(title_label)
	detail_label = _label("", 18, Style.MINT)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size.x = 520
	detail_label.visible = false
	column.add_child(detail_label)
	resume_button = _add_button("Resume", _press_resume)
	restart_button = _add_button("Restart", _press.bind(func() -> void: _on_restart.call()))
	how_to_play_button = _add_button("How to Play", _show_how_to_play)
	menu_button = _add_button("Main Menu", _press.bind(func() -> void: _on_leave.call()))
	var hint := _label("", 18, Color("9baebc"))
	Prompts.track(hint, func() -> String:
		return "%s  RESUME     %s  SELECT     %s  CONFIRM" % [
			Prompts.either("ESC", &"pause", true),
			Prompts.keys_or_pad("↑ ↓", Prompts.if_pad("D-PAD")),
			Prompts.either("ENTER", &"ui_accept", true)])
	column.add_child(hint)
	_wire_focus()

## Adds a game-specific button before Main Menu and returns it. It does not lock the menu: the
## game decides what the press does (the runner opens its leaderboard over the menu).
func add_button(text: String, on_pressed: Callable) -> Button:
	var button := _add_button(text, func() -> void:
		if locked or _router_busy():
			return
		_play_ui(1)
		on_pressed.call())
	column.move_child(button, menu_button.get_index())
	buttons.erase(button)
	buttons.insert(buttons.find(menu_button), button)
	_wire_focus()
	return button

func _add_button(text: String, on_pressed: Callable) -> Button:
	var button := Style.button(text, BUTTON_HEIGHT)
	button.name = text.replace(" ", "") + "Button"
	column.add_child(button)
	buttons.append(button)
	button.pressed.connect(on_pressed)
	button.focus_entered.connect(_focus_sound)
	button.mouse_entered.connect(func() -> void:
		if visible and not button.disabled:
			button.grab_focus())
	return button

## Menu text with an outline: it sits over any game's screen, and the runner's legibility rules
## (18 px, 6 px outline) apply to every label a run can show.
static func _label(text: String, size: int, color: Color = Style.CREAM) -> Label:
	var label := Style.label(text, size, color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color("0b1620"))
	return label

func _wire_focus() -> void:
	for i in buttons.size():
		var above := buttons[(i - 1 + buttons.size()) % buttons.size()]
		var below := buttons[(i + 1) % buttons.size()]
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(above)
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(below)
		buttons[i].focus_previous = buttons[i].focus_neighbor_top
		buttons[i].focus_next = buttons[i].focus_neighbor_bottom

## Shows the menu with `detail` under the title ("" for none) and focuses Resume.
func open(detail := "") -> void:
	detail_label.text = detail
	detail_label.visible = not detail.is_empty()
	_set_locked(false)
	visible = true
	_opening = true
	resume_button.grab_focus()
	_opening = false

## Hides the menu. The game unpauses itself; this never touches the tree. Closing the menu
## (resume, pad reconnect, a route change) takes an open leaderboard with it.
func close() -> void:
	if is_instance_valid(leaderboard):
		leaderboard.closed.disconnect(_on_leaderboard_closed)
		leaderboard.queue_free()
		leaderboard = null
		_set_menu_enabled(true)
	visible = false

## Opens the game's top ten over the menu. The board owns the screen while it is up: the menu's
## own buttons can't be reached until it closes.
func _open_leaderboard() -> void:
	if leaderboard != null:
		return
	_set_menu_enabled(false)
	leaderboard = LeaderboardPanel.new()
	leaderboard.leaderboard_path = leaderboard_path
	var title: String = Data.game(route).get("title", "") if Data.has_game(route) else ""
	leaderboard.title = (title.to_upper() + "  ·  " if not title.is_empty() else "") + "LOCAL TOP 10"
	leaderboard.closed.connect(_on_leaderboard_closed)
	ui.add_child(leaderboard)

func _on_leaderboard_closed() -> void:
	leaderboard = null
	_set_menu_enabled(true)
	if visible:
		leaderboard_button.grab_focus()

func _set_menu_enabled(enabled: bool) -> void:
	for button in buttons:
		button.disabled = not enabled or locked
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func is_open() -> bool:
	return visible

## Disables every button: a route change is under way and a second press must do nothing.
func lock() -> void:
	_set_locked(true)

func _set_locked(value: bool) -> void:
	locked = value
	for button in buttons:
		button.disabled = value

## The autoloads are looked up at run time: runner scripts preload this one before the singletons
## exist, so naming AudioService or AppRouter here would not compile there.
func _play_ui(kind: int) -> void:
	var audio := get_tree().root.get_node_or_null(^"AudioService") if is_inside_tree() else null
	if audio != null and audio.has_method("play_ui"):
		audio.play_ui(kind)

func _router_busy() -> bool:
	var router := get_tree().root.get_node_or_null(^"AppRouter") if is_inside_tree() else null
	return router != null and bool(router.get(&"busy"))

func _press_resume() -> void:
	if locked or _router_busy():
		return
	_play_ui(1)
	_on_resume.call()

## Restart, Main Menu and game-specific buttons: one press, then the menu locks.
func _press(action: Callable) -> void:
	if locked or _router_busy():
		return
	lock()
	_play_ui(1)
	action.call()

## Opens the game's how-to-play card over this menu; the game stays paused under it and focus
## returns to the button when the card closes.
func _show_how_to_play() -> void:
	if not visible or locked or _router_busy():
		return
	_play_ui(1)
	HowToPlay.open(get_tree(), route, HowToPlay.Mode.PAUSE, how_to_play_button)

func _focus_sound() -> void:
	if visible and not _opening and not _router_busy():
		_play_ui(0)
