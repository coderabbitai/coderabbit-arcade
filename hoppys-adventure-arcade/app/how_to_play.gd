extends CanvasLayer
## The how-to-play card: a few pages per game (the goal, the controls with keyboard and controller
## side by side, tips), most acted out by a little looping scene (app/how_to_play_demo.gd). Its
## text comes from app/how_to_play_data.gd.
##
## Paging: a confirm, jump or attack press, a click or a touch turns to the next page, and on the
## last page closes the card; left/right flip back and forth without closing; pause (Esc / Start)
## skips straight to the game.
##
## Two ways in:
## - AppRouter opens it in START mode when a visitor first enters a game (see AppRouter.go()). It
##   pauses the game and ignores presses for its first ARM_SECONDS. Each page turns by itself after
##   PAGE_SECONDS and the last one closes the card, so an unattended booth never waits on it.
##   Closing unpauses the game unless the game paused itself meanwhile (focus loss shows its own
##   pause menu; see `is_player_paused()` on the game scenes).
## - A game's pause menu opens it in PAUSE mode: no countdown, Back closes it too, the game stays
##   paused and focus returns to the button that opened it.
##
## The card is added as the root's last child, so its _input sees every event before the game
## does. While it is up it swallows every press (the game would otherwise toggle pause or skip its
## intro underneath), after handing the press to AppRouter (booth idle timer) and ControllerService
## (which pad is player one), which would otherwise never see it.

signal closed

const Data := preload("res://app/how_to_play_data.gd")
const Style := preload("res://scenes/main_menu/menu_style.gd")
const Prompts := preload("res://app/controller_prompts.gd")
const Labels := preload("res://addons/cr_kit/input.gd").Labels
const Demo := preload("res://app/how_to_play_demo.gd")

enum Mode { START, PAUSE }

## Above every game's pause menu, below ControllerService's disconnect banner (90) and the
## router's fade (100).
const LAYER := 89
const ARM_SECONDS := 0.5
## How long a START card stays on each page before turning it.
const PAGE_SECONDS := 7.0
## Room for the tallest page, so the panel doesn't jump between pages.
const BODY_HEIGHT := 330.0
const DIM := Color(0.01, 0.02, 0.04, 0.86)
const PANEL := Color("142735")
const MUTED := Color("afbdc9")
## Turn to the next page, or close the card on the last one.
const NEXT_ACTIONS: Array[StringName] = [
	&"ui_accept", &"jump", &"attack", &"brawl_jump", &"brawl_attack", &"heroes_popup_advance"]
## Close the card from any page.
const SKIP_ACTIONS: Array[StringName] = [&"pause"]
const BACK_ACTIONS: Array[StringName] = [&"ui_left", &"move_left"]
const FORWARD_ACTIONS: Array[StringName] = [&"ui_right", &"move_right"]
## Each family's face-button names when no controller is connected: Xbox first, then PlayStation.
const ANY_PAD := ["xbox", "playstation"]
const KEY_CAPS := {
	KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓", KEY_ESCAPE: "Esc", KEY_ENTER: "Enter",
}
const STICK_TEXT := {Data.STICK: "Left stick", Data.STICK_UP: "Stick ↑", Data.STICK_DOWN: "Stick ↓"}

var route := ""
var mode := Mode.START
var age := 0.0
var page := 0
var countdown := PAGE_SECONDS
var return_focus: Control
var _focus_lost := false
var _closing := false
## Still swallowing input for the few frames a START card takes to hand the game back.
var _closing_input := false
var _controls: GridContainer
var _heading: Label
var _body: VBoxContainer
var _dots: Label
var _footer: Label
## The stick's last left/right push (-1, 0, 1), so holding it flips one page, not one per event.
var _stick := 0
var _bar: ColorRect
var _bar_track: Control


## Shows the card for `route` over the current scene and returns it, or null when the route has no
## card. START pauses the tree; PAUSE expects the game to be paused already.
static func open(tree: SceneTree, game_route: String, card_mode: Mode, focus_after: Control = null) -> Node:
	if not Data.has_game(game_route):
		return null
	var card: Node = load("res://app/how_to_play.gd").new()
	card.route = game_route
	card.mode = card_mode
	card.return_focus = focus_after
	tree.root.add_child(card)
	if card_mode == Mode.START:
		tree.paused = true
	return card


func _ready() -> void:
	name = "HowToPlay"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	var controllers := Prompts.service()
	if controllers:
		controllers.family_changed.connect(_on_family_changed)


func _exit_tree() -> void:
	var controllers := Prompts.service()
	if controllers and controllers.family_changed.is_connected(_on_family_changed):
		controllers.family_changed.disconnect(_on_family_changed)


func _process(delta: float) -> void:
	if _closing:
		return
	age += delta
	if mode != Mode.START:
		return
	# The countdown waits while the window is in the background; nobody can be reading it.
	if not _focus_lost:
		countdown -= delta
	_bar.size.x = _bar_track.size.x * clampf(countdown / PAGE_SECONDS, 0.0, 1.0)
	if countdown <= 0.0:
		next_page()


func _input(event: InputEvent) -> void:
	if not _is_press_or_motion(event) or (_closing and not _closing_input):
		return
	_share(event)
	get_viewport().set_input_as_handled()
	if _closing or age < ARM_SECONDS:
		_track_stick(event)
		return
	var flip := _flip_of(event)
	if flip != 0:
		show_page(page + flip)
	elif is_dismiss(event):
		close()
	elif is_next(event):
		next_page()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_lost = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_lost = false


## True for a press that closes the card from any page: pause, or Back on a reopened card.
func is_dismiss(event: InputEvent) -> bool:
	if _pressed(event, SKIP_ACTIONS):
		return true
	return mode == Mode.PAUSE and _pressed(event, [&"ui_cancel"])


## True for a press that turns to the next page (or closes the card on the last one).
func is_next(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	# Only a left click or a real touch: no wheel or right button, and no mouse click Godot emulates
	# from a touch (on by default), so one tap turns one page.
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION
	if event is InputEventScreenTouch:
		return event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION
	return _pressed(event, NEXT_ACTIONS)


func _pressed(event: InputEvent, actions: Array[StringName]) -> bool:
	if event.is_echo() or event is InputEventJoypadMotion:
		return false
	for action in actions:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true
	return false


## -1 or 1 for a press that flips back or forward a page, else 0. The stick flips once per push.
func _flip_of(event: InputEvent) -> int:
	if event is InputEventJoypadMotion:
		var before := _stick
		_track_stick(event)
		return _stick if event.axis == JOY_AXIS_LEFT_X and _stick != before else 0
	if _pressed(event, BACK_ACTIONS):
		return -1
	if _pressed(event, FORWARD_ACTIONS):
		return 1
	return 0


func _track_stick(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		_stick = 0 if absf(event.axis_value) < 0.5 else signi(int(signf(event.axis_value)))


func page_count() -> int:
	return Data.pages(route).size()


func is_last_page() -> bool:
	return page >= page_count() - 1


## Turns to the next page, or closes the card from the last one.
func next_page() -> void:
	if is_last_page():
		close()
	else:
		show_page(page + 1)


## Shows page `index` (clamped) and restarts its countdown.
func show_page(index: int) -> void:
	page = clampi(index, 0, page_count() - 1)
	countdown = PAGE_SECONDS
	var entry: Dictionary = Data.pages(route)[page]
	_heading.text = str(entry.heading).to_upper()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_controls = null
	if entry.get("controls", false):
		_controls = GridContainer.new()
		_controls.columns = 4
		_controls.add_theme_constant_override("h_separation", 22)
		_controls.add_theme_constant_override("v_separation", 4)
		_body.add_child(_controls)
		_fill_controls()
	else:
		_body.add_child(Demo.build(entry.scene))
		var text := Style.label(str(entry.text), 20, Style.CREAM)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = Demo.SIZE.x
		_body.add_child(text)
	var dots: PackedStringArray = []
	for each in page_count():
		dots.append("●" if each == page else "○")
	_dots.text = "  ".join(dots)
	_update_footer()


## Hides the card and hands the game back: in START mode it unpauses the tree unless the game has
## since paused itself; in PAUSE mode focus returns to the pause menu.
func close() -> void:
	if _closing:
		return
	_closing = true
	hide()
	var tree := get_tree()
	if mode == Mode.START:
		# The press that closed the card is still "just pressed" this frame: unpausing now would let
		# it jump or swipe in the game too. Swallow input until it has gone stale.
		_closing_input = true
		var scene := tree.current_scene
		for frame in 2:
			await tree.physics_frame
		await tree.process_frame
		var router := tree.root.get_node_or_null(^"AppRouter")
		var leaving: bool = router != null and router.busy
		var self_paused: bool = scene != null and scene.has_method("is_player_paused") and scene.is_player_paused()
		if tree.current_scene == scene and not leaving and not self_paused:
			tree.paused = false
	elif is_instance_valid(return_focus) and return_focus.is_visible_in_tree():
		return_focus.grab_focus()
	closed.emit()
	queue_free()


## Frees the card without touching pause, for a route change that is replacing the game anyway.
func discard() -> void:
	hide()
	if _closing_input:
		return # close() is mid-handover; it sees the route change, leaves pause alone and frees the card.
	_closing = true
	queue_free()


## The keyboard column's text for a row: "Space / W / ↑", "WASD / Arrows".
static func keys_text(keys: Array) -> String:
	var parts: PackedStringArray = []
	var wasd := [KEY_W, KEY_A, KEY_S, KEY_D].all(func(key: int) -> bool: return key in keys)
	var arrows := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN].filter(func(key: int) -> bool: return key in keys)
	var arrows_done := false
	for key: int in keys:
		if wasd and key in [KEY_W, KEY_A, KEY_S, KEY_D]:
			if key == KEY_W:
				parts.append("WASD")
			continue
		if key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			if not arrows_done:
				arrows_done = true
				parts.append("Arrows" if arrows.size() == 4 else " ".join(arrows.map(func(arrow: int) -> String: return KEY_CAPS[arrow])))
			continue
		parts.append(KEY_CAPS.get(key, OS.get_keycode_string(key)))
	return " / ".join(parts)


## The controller column's text for a row, for `family` ("" = no controller: name each button for
## Xbox and PlayStation, "A / Cross"). D-pad directions fold into one "D-pad" when the row also
## uses the stick that way.
static func pad_text(pads: Array, family: String) -> String:
	var parts: PackedStringArray = []
	var dpad := pads.filter(func(pad: int) -> bool: return Labels.DPAD.has(pad))
	var dpad_done := false
	for pad: int in pads:
		if STICK_TEXT.has(pad):
			parts.append(STICK_TEXT[pad])
		elif Labels.DPAD.has(pad):
			if dpad_done:
				continue
			dpad_done = true
			parts.append("D-pad" if dpad.size() > 1 else str(Labels.DPAD[pad]).replace(" up", " ↑").replace(" down", " ↓").replace(" left", " ←").replace(" right", " →"))
		else:
			parts.append(button_text(pad, family))
	return " / ".join(parts)


static func button_text(pad: int, family: String) -> String:
	if not family.is_empty():
		return Labels.button(pad, family)
	if pad == JOY_BUTTON_START:
		return "Start"
	var names: PackedStringArray = []
	for each in ANY_PAD:
		var label := Labels.button(pad, each)
		if label not in names:
			names.append(label)
	return " / ".join(names)


## The face button (JOY_BUTTON_A..Y) a row's controller column leads with, or -1.
static func face_button(pads: Array) -> int:
	for pad: int in pads:
		if pad in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
			return pad
	return -1


func _family() -> String:
	var controllers := Prompts.service()
	return controllers.family if controllers else ""


func _build() -> void:
	var game := Data.game(route)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = Style.theme()
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
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size.x = 820
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	top.add_child(Style.label("HOW TO PLAY", 16, Style.MINT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_dots = Style.label("", 16, Style.MINT)
	top.add_child(_dots)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 18)
	column.add_child(heading)
	heading.add_child(Style.label(str(game.title), 36))
	_heading = Style.label("", 20, Style.MINT)
	_heading.size_flags_vertical = Control.SIZE_SHRINK_END
	heading.add_child(_heading)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.custom_minimum_size.y = BODY_HEIGHT
	column.add_child(_body)
	_footer = Style.label("", 18, Style.MINT)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_footer)
	_bar_track = ColorRect.new()
	(_bar_track as ColorRect).color = Color("244447")
	_bar_track.custom_minimum_size = Vector2(0, 4)
	column.add_child(_bar_track)
	_bar = ColorRect.new()
	_bar.color = Style.MINT
	_bar.size = Vector2(0, 4)
	_bar_track.add_child(_bar)
	_bar_track.visible = mode == Mode.START
	show_page(0)


func _fill_controls() -> void:
	if _controls == null:
		return
	for child in _controls.get_children():
		_controls.remove_child(child)
		child.queue_free()
	var family := _family()
	var poses: Dictionary = Data.game(route).get("poses", {})
	for heading in ["", "", "KEYBOARD", "CONTROLLER"]:
		_controls.add_child(Style.label(heading, 14, Style.MINT))
	for row: Dictionary in Data.game(route).rows:
		if poses.has(row.get("icon", "")):
			_controls.add_child(Demo.icon(poses[row.icon]))
		else:
			var blank := Control.new()
			blank.custom_minimum_size = Demo.ICON_SIZE
			_controls.add_child(blank)
		var action := HBoxContainer.new()
		action.add_theme_constant_override("separation", 10)
		action.add_child(Style.label(str(row.label), 20))
		if row.has("hint"):
			var hint := Style.label("(%s)" % row.hint, 15, MUTED)
			hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			action.add_child(hint)
		_controls.add_child(action)
		_controls.add_child(Style.label(keys_text(row.keys), 20))
		var pad := HBoxContainer.new()
		pad.add_theme_constant_override("separation", 8)
		var face := face_button(row.pad)
		if face >= 0:
			var glyph := FaceGlyph.new()
			glyph.button = face
			pad.add_child(glyph)
		pad.add_child(Style.label(pad_text(row.pad, family), 20))
		_controls.add_child(pad)


func _update_footer() -> void:
	var family := _family()
	var next := "Space / %s" % button_text(JOY_BUTTON_A, family)
	if is_last_page():
		_footer.text = ("%s to play" if mode == Mode.START else "%s to go back") % next
	elif mode == Mode.START:
		_footer.text = "%s next     ← →  pages     Esc / %s  play now" % [next, button_text(JOY_BUTTON_START, family)]
	else:
		_footer.text = "%s next     ← →  pages     Esc / %s  back" % [next, button_text(JOY_BUTTON_B, family)]


func _on_family_changed(_family_name: String) -> void:
	_fill_controls()
	_update_footer()


func _is_press_or_motion(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion \
		or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag \
		or event is InputEventAction


## The card swallows input, so the autoloads that watch every press get it from here instead.
func _share(event: InputEvent) -> void:
	var root := get_tree().root
	var router := root.get_node_or_null(^"AppRouter")
	if router and router.has_method("note_input"):
		router.note_input(event)
	var controllers := root.get_node_or_null(^"ControllerService")
	if controllers and controllers.has_method("observe"):
		controllers.observe(event)


## Four face buttons in a diamond with the one to press filled in: readable on any pad, whatever
## its letters say.
class FaceGlyph extends Control:
	const SPOTS := {
		JOY_BUTTON_Y: Vector2(0, -1), JOY_BUTTON_A: Vector2(0, 1),
		JOY_BUTTON_X: Vector2(-1, 0), JOY_BUTTON_B: Vector2(1, 0),
	}
	var button := JOY_BUTTON_A

	func _init() -> void:
		custom_minimum_size = Vector2(26, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var middle := size / 2.0
		for spot: int in SPOTS:
			var at: Vector2 = middle + SPOTS[spot] * 8.0
			if spot == button:
				draw_circle(at, 4.5, Color("79e0c4"))
			else:
				draw_circle(at, 3.5, Color("5b6d7c"), false, 1.5, true)
