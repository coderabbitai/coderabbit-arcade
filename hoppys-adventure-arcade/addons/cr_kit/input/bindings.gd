extends RefCounted
## InputMap bindings made in code that answer every controller.
##
## A new InputEventJoypadButton or InputEventJoypadMotion defaults to device 0, so a binding made
## in code answers only the first pad. Booths, second players and reconnected controllers get
## other device ids. Everything here binds pads to ANY_DEVICE (-1), the id the editor's
## "All Devices" choice writes, and audit helpers find bindings that still name one device.

## InputMap's "any device" id.
const ANY_DEVICE := -1


## A pad button event that answers every controller.
static func joy_button(index: int) -> InputEventJoypadButton:
	var input := InputEventJoypadButton.new()
	input.device = ANY_DEVICE
	input.button_index = index as JoyButton
	return input


## A stick or trigger event that answers every controller. The sign of `direction` picks the
## side: negative is left/up, positive is right/down; triggers use a positive direction.
static func joy_axis(index: int, direction: float) -> InputEventJoypadMotion:
	var input := InputEventJoypadMotion.new()
	input.device = ANY_DEVICE
	input.axis = index as JoyAxis
	input.axis_value = -1.0 if direction < 0.0 else 1.0
	return input


## A key event matched by physical position, so WASD stays WASD on every keyboard layout.
static func key(physical_keycode: int) -> InputEventKey:
	var input := InputEventKey.new()
	input.physical_keycode = physical_keycode as Key
	return input


## Adds the action if it is missing. An existing action keeps its deadzone.
static func ensure_action(action_name: StringName, deadzone: float = 0.5) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, deadzone)


## Adds each event the action does not already answer. Returns how many were added.
static func bind(action_name: StringName, events: Array, deadzone: float = 0.5) -> int:
	ensure_action(action_name, deadzone)
	var added := 0
	for input: InputEvent in events:
		if not InputMap.action_has_event(action_name, input):
			InputMap.action_add_event(action_name, input)
			added += 1
	return added


## Binds several actions at once. `map` is {action: {"keys": [Key], "buttons": [JoyButton],
## "axes": [[JoyAxis, direction]]}}; every part is optional. Returns how many events were added.
static func install(map: Dictionary, deadzone: float = 0.5) -> int:
	var added := 0
	for action_name: StringName in map:
		var spec: Dictionary = map[action_name]
		var events: Array[InputEvent] = []
		for physical: int in spec.get("keys", []):
			events.append(key(physical))
		for index: int in spec.get("buttons", []):
			events.append(joy_button(index))
		for pair: Array in spec.get("axes", []):
			events.append(joy_axis(int(pair[0]), float(pair[1])))
		added += bind(action_name, events, deadzone)
	return added


## Every pad binding that answers only one device, as "action: event (device N)". Empty means
## every pad binding in the given actions (default: all of them) answers every controller.
static func single_device_pad_events(actions: Array = []) -> PackedStringArray:
	var found := PackedStringArray()
	for action_name: StringName in _actions(actions):
		for input: InputEvent in InputMap.action_get_events(action_name):
			if _is_pad(input) and input.device != ANY_DEVICE:
				found.append("%s: %s (device %d)" % [action_name, input.as_text(), input.device])
	return found


## Rebinds every single-device pad event in the given actions (default: all) to ANY_DEVICE.
## Returns how many events changed.
static func widen_to_any_device(actions: Array = []) -> int:
	var changed := 0
	for action_name: StringName in _actions(actions):
		for input: InputEvent in InputMap.action_get_events(action_name):
			if _is_pad(input) and input.device != ANY_DEVICE:
				input.device = ANY_DEVICE
				changed += 1
	return changed


static func _actions(actions: Array) -> Array[StringName]:
	var names: Array[StringName] = []
	for action_name: StringName in (InputMap.get_actions() if actions.is_empty() else actions):
		if InputMap.has_action(action_name):
			names.append(action_name)
	return names


static func _is_pad(input: InputEvent) -> bool:
	return input is InputEventJoypadButton or input is InputEventJoypadMotion
