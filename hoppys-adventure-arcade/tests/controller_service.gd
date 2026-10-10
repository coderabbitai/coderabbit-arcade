extends SceneTree
## ControllerService with fake pads: prompts follow the pad in use, a game pauses through its own
## pause menu when that pad disconnects and resumes when it returns, and every pad binding answers
## every controller. No real devices are read.
const CrInput := preload("res://addons/cr_kit/input.gd")
const FakePads := preload("res://tests/support/fake_pads.gd")
const Prompts := preload("res://app/controller_prompts.gd")
const XBOX := ["Xbox Series X Controller", "xbox-guid", 0x045e]
const DUALSENSE := ["DualSense Wireless Controller", "sony-guid", 0x054c]
const SWITCH_PRO := ["Nintendo Switch Pro Controller", "nintendo-guid", 0x057e]
var failures := 0
var service: Node
var pads: RefCounted


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func frames(count: int) -> void:
	for i in count: await physics_frame


## Connection changes reach the service the way Input reports them; it pauses or resumes a game on
## the next idle step, so callers await the frame.
func plug(device: int, pad: Array) -> void:
	pads.plug(device, pad[0], pad[1], pad[2])
	service._on_joy_connection_changed(device, true)
	await process_frame


func unplug(device: int) -> void:
	pads.unplug(device)
	service._on_joy_connection_changed(device, false)
	await process_frame


func press(device: int, button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func fresh_pads() -> void:
	pads = FakePads.new()
	service.use_hardware(pads)


func run() -> void:
	service = root.get_node("ControllerService")
	routes_are_classified()
	every_pad_binding_answers_every_controller()
	await menus_accept_any_pad()
	await prompts_follow_the_pad_in_use()
	await platformer_pauses_and_resumes()
	await brawler_hands_over_to_another_pad()
	await runner_pauses_and_resumes()
	await menu_disconnect_frees_player_one()
	print("CONTROLLER SERVICE: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	current_scene.queue_free()
	await frames(5)
	var audio := root.get_node("AudioService")
	if audio.has_method("settle"):
		await audio.settle()
	else:
		audio.shutdown()
		await create_timer(0.3).timeout
	quit(failures)


func routes_are_classified() -> void:
	var classified: Array[String] = service.GAMEPLAY_ROUTES + service.MENU_ROUTES
	classified.sort()
	var routes: Array = root.get_node("AppRouter").ROUTES.keys()
	routes.sort()
	check(classified == routes, "Every AppRouter route is gameplay or menu: %s vs %s" % [classified, routes])


func every_pad_binding_answers_every_controller() -> void:
	# The modes install their own actions on first use; include them.
	preload("res://modes/beatem_up/reinvent/catalog.gd").install_input()
	var found: PackedStringArray = CrInput.Bindings.single_device_pad_events()
	check(found.is_empty(), "Pad bindings that answer one controller only: %s" % [found])


func menus_accept_any_pad() -> void:
	fresh_pads()
	await plug(3, XBOX)
	var button := Button.new()
	root.add_child(button)
	var presses := [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	button.grab_focus()
	await frames(1)
	press(3, JOY_BUTTON_A)
	await frames(1)
	check(presses[0] == 1, "The bottom face button on pad 3 presses a focused menu button")
	button.queue_free()
	check(service.pad(&"ui_cancel") == "B", "The right face button goes back")


func prompts_follow_the_pad_in_use() -> void:
	fresh_pads()
	check(service.family == "" and service.pad(&"jump") == "", "No controller: no pad prompt")
	check(Prompts.either("Space", &"jump") == "Space", "Keyboard-only prompt")
	var label := Label.new()
	root.add_child(label)
	service.track(label, func() -> String: return Prompts.either("Space", &"jump"))
	await plug(0, XBOX)
	check(service.family == "xbox" and label.text == "Space / A", "Xbox prompt, got %s" % label.text)
	await plug(1, DUALSENSE)
	check(service.family == "xbox", "Connecting a second pad does not switch the prompts")
	press(1, JOY_BUTTON_X)
	check(service.family == "playstation" and label.text == "Space / Cross",
		"The pad last used drives the prompts, got %s" % label.text)
	await plug(2, SWITCH_PRO)
	press(2, JOY_BUTTON_DPAD_DOWN)
	check(label.text == "Space / B", "Nintendo's bottom button reads B, got %s" % label.text)
	check(service.pad(&"roll") == "A" and service.pad(&"attack") == "Y" and service.pad(&"pause") == "+",
		"Nintendo labels for the right, left and Start buttons")
	await unplug(2)
	await unplug(1)
	await unplug(0)
	check(service.family == "" and label.text == "Space", "Prompts drop pad labels with no pad left")
	label.free()
	check(service.family_changed.get_connections().is_empty(), "A freed label stops tracking")


func platformer_pauses_and_resumes() -> void:
	change_scene_to_file("res://scenes/platformer/bay_area_blitz.tscn")
	await frames(30)
	var level := current_scene
	level._resume()
	fresh_pads()
	await plug(0, XBOX)
	await frames(5)
	await unplug(0)
	check(paused and level.overlay.visible, "A disconnect pauses the platformer through its pause menu")
	check(service.is_paused_for_controller() and service.banner.visible, "The banner asks for the controller")
	await plug(4, XBOX)  # The same pad returns under a new id.
	check(not paused and not level.overlay.visible, "Reconnecting resumes the platformer")
	check(not service.banner.visible and service.family == "xbox", "Banner hidden, prompts back")
	await frames(5)
	# A game the player paused stays paused through a disconnect and reconnect.
	level._pause()
	await unplug(4)
	check(paused and not service.is_paused_for_controller(), "A player-paused game is left alone")
	await plug(5, XBOX)
	check(paused and level.overlay.visible, "Reconnecting does not resume a game the player paused")
	level._resume()
	await frames(5)


func brawler_hands_over_to_another_pad() -> void:
	change_scene_to_file("res://scenes/beatem_up/code_city_brawl.tscn")
	await frames(3)
	var game := current_scene
	game.test_mode = true
	game.begin_play()
	await frames(5)
	fresh_pads()
	await plug(0, XBOX)
	await plug(1, DUALSENSE)
	press(0, JOY_BUTTON_A)
	await unplug(0)
	check(paused and game.state == "paused", "A disconnect pauses the beat 'em up (state %s)" % game.state)
	press(1, JOY_BUTTON_START)
	check(not paused and game.state != "paused", "Start on another pad resumes (state %s)" % game.state)
	check(service.family == "playstation" and not service.banner.visible, "That pad is now player one")
	await frames(5)
	# The pause menu itself answers every pad: the focused Resume button takes the bottom button.
	await plug(2, SWITCH_PRO)
	await unplug(1)
	check(paused and service.banner.visible, "Player one's pad leaves again")
	press(2, JOY_BUTTON_A)
	await frames(2)
	check(not paused and not service.banner.visible, "Another pad can press Resume")
	press(2, JOY_BUTTON_DPAD_LEFT)
	check(service.family == "nintendo", "and becomes player one on its next press")
	await frames(5)


func runner_pauses_and_resumes() -> void:
	change_scene_to_file("res://scenes/runner/runner_game.tscn")
	await frames(5)
	var game := current_scene
	game.start_run(7)
	await frames(5)
	fresh_pads()
	await plug(0, SWITCH_PRO)
	await unplug(0)
	check(game.paused and paused, "A disconnect pauses the runner")
	await plug(1, SWITCH_PRO)
	check(not game.paused and not paused, "Reconnecting resumes the runner")
	await frames(5)


func menu_disconnect_frees_player_one() -> void:
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await frames(10)
	fresh_pads()
	await plug(0, XBOX)
	await plug(1, DUALSENSE)
	await unplug(0)
	check(not paused and not service.banner.visible, "A disconnect in a menu does not pause")
	check(not service.roster.is_waiting(&"p1"), "Player one is free for the next pad")
	press(1, JOY_BUTTON_DPAD_DOWN)
	check(service.family == "playstation", "The next pad used becomes player one")
