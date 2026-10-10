extends Node
## Which controller the player is using, what its buttons are called, and what happens when it
## disconnects.
##
## Every pad binding answers every controller (device -1), so any pad on the table can play. The
## pad that last sent input is player one: prompts name its buttons ("Cross", "A" or "B" for the
## same bottom button). If that pad disconnects during a game, the game pauses through its own
## pause menu and a banner asks for it back; the game resumes when the pad reconnects. Start on
## another pad also resumes, because Start is the game's pause toggle, and that pad becomes player
## one. A disconnect anywhere else just frees player one for the next pad that is used.

## Prompts should be rebuilt: the player switched to a pad of another family, or the last pad left.
signal family_changed(family: String)

const CrInput := preload("res://addons/cr_kit/input.gd")
const MenuStyle := preload("res://scenes/main_menu/menu_style.gd")
const Labels := CrInput.Labels
const PLAYER := &"p1"
## AppRouter routes whose scene treats the `pause` action as its pause toggle. The rest are menus.
## tests/controller_service.gd fails when a route is in neither list.
const GAMEPLAY_ROUTES: Array[String] = [
	"heroes_vs_villains", "code_city_brawl", "enchanted_repo", "orbital_ops", "bay_area_blitz", "runner_game"]
const MENU_ROUTES: Array[String] = ["hub", "platformer", "runner", "beatem_up"]
## Godot ships ui_accept and ui_cancel without pad buttons, so a pad could not confirm or go back
## in menus. These match the prompts: the bottom face button confirms, the right one goes back.
const MENU_BINDINGS := {
	&"ui_accept": {"buttons": [JOY_BUTTON_A]},
	&"ui_cancel": {"buttons": [JOY_BUTTON_B]},
}
const STICK_THRESHOLD := 0.5

var roster: RefCounted
## The player's controller family, or "" when no controller is connected (keyboard prompts only).
var family := ""
var banner: CanvasLayer
var _banner_text: Label
var _paused_for_controller := false


func _ready() -> void:
	# Disconnect handling has to run while a game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	CrInput.Bindings.install(MENU_BINDINGS)
	CrInput.Bindings.widen_to_any_device()
	_build_banner()
	use_hardware(null)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Replaces the controller source; tests pass a fake with the kit roster's Hardware methods.
func use_hardware(hardware: RefCounted) -> void:
	roster = CrInput.Roster.new([PLAYER], hardware)
	roster.role_assigned.connect(_on_role_assigned)
	roster.role_lost.connect(_on_role_lost)
	roster.role_restored.connect(_on_role_restored)
	_set_paused_for_controller(false)
	roster.refresh()
	_update_family()


## The label of an action's first pad binding for the current controller, or "" without one.
func pad(action: StringName) -> String:
	return "" if family.is_empty() else Labels.action(action, family)


## Sets a label's text now and again whenever the controller family changes, for as long as the
## label exists.
func track(label: Label, build: Callable) -> void:
	label.text = build.call()
	var refresh := func(_family: String) -> void:
		if is_instance_valid(label): label.text = build.call()
	family_changed.connect(refresh)
	label.tree_exiting.connect(func() -> void:
		if family_changed.is_connected(refresh): family_changed.disconnect(refresh))


## True while a game is paused because its player's controller disconnected.
func is_paused_for_controller() -> bool:
	return _paused_for_controller


func _input(event: InputEvent) -> void:
	var device := _gameplay_device(event)
	if device < 0 or roster.role_of(device) == PLAYER:
		return
	if _paused_for_controller:
		# Only a deliberate Start takes over a game paused for its missing controller. Start is also
		# the pause toggle, so the same press resumes the game through its own pause menu.
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START and roster.claim(device):
			_set_paused_for_controller(false)
	elif roster.is_waiting(PLAYER):
		roster.claim(device)
	else:
		roster.assign(PLAYER, device)


func _process(_delta: float) -> void:
	# The player resumed (or left the game) another way: nothing is waiting on the pad any more.
	if _paused_for_controller and not get_tree().paused:
		_set_paused_for_controller(false)


func _gameplay_device(event: InputEvent) -> int:
	if event is InputEventJoypadButton and event.pressed:
		return event.device
	if event is InputEventJoypadMotion and absf(event.axis_value) >= STICK_THRESHOLD:
		return event.device
	return -1


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	roster.on_joy_connection_changed(device, connected)


func _on_role_assigned(_role: StringName, _device: int) -> void:
	_update_family()


func _on_role_lost(_role: StringName, _device: int) -> void:
	_update_family()
	if not _in_gameplay():
		roster.release(PLAYER)
	else:
		# Connection callbacks can arrive while Input is dispatching; pause once it is idle.
		_pause_for_controller.call_deferred()


func _on_role_restored(_role: StringName, _device: int) -> void:
	_update_family()
	_resume_for_controller.call_deferred()


func _pause_for_controller() -> void:
	# A game already paused by its player stays paused, and a reconnect won't resume it.
	if roster.is_waiting(PLAYER) and _in_gameplay() and not get_tree().paused:
		_toggle_pause()
		_set_paused_for_controller(get_tree().paused)


func _resume_for_controller() -> void:
	if _paused_for_controller and get_tree().paused:
		_toggle_pause()
	_set_paused_for_controller(false)


func _set_paused_for_controller(value: bool) -> void:
	_paused_for_controller = value
	banner.visible = value


func _update_family() -> void:
	var device: int = roster.device_for(PLAYER)
	var current: String = roster.family(device) if device >= 0 else ""
	if current != family:
		family = current
		family_changed.emit(family)


func _in_gameplay() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	for route in GAMEPLAY_ROUTES:
		if AppRouter.ROUTES[route] == scene.scene_file_path:
			return true
	return false


## Each game owns its pause menu and toggles it on the `pause` action, so send that action
## rather than pausing the tree underneath it.
func _toggle_pause() -> void:
	for pressed in [true, false]:
		var action := InputEventAction.new()
		action.action = &"pause"
		action.pressed = pressed
		Input.parse_input_event(action)
	Input.flush_buffered_events()


func _build_banner() -> void:
	banner = CanvasLayer.new()
	banner.layer = 90  # Above every game's pause menu, below the router's fade (100).
	banner.visible = false
	add_child(banner)
	var panel := PanelContainer.new()
	panel.theme = MenuStyle.theme()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.position.y = 24
	var box := StyleBoxFlat.new()
	box.bg_color = Color("142735")
	box.border_color = MenuStyle.MINT
	box.set_border_width_all(2)
	box.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", box)
	banner.add_child(panel)
	_banner_text = Label.new()
	_banner_text.text = "CONTROLLER DISCONNECTED\nReconnect it to resume, or press Start on another controller."
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text.add_theme_font_size_override("font_size", 18)
	_banner_text.add_theme_color_override("font_color", MenuStyle.CREAM)
	panel.add_child(_banner_text)
	panel.resized.connect(func() -> void: panel.position.x = (panel.get_viewport_rect().size.x - panel.size.x) / 2.0)
