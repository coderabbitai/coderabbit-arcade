extends RefCounted
## Player-facing names for controller buttons, sticks and triggers, per controller family.
##
## Godot reports positions (JOY_BUTTON_A is the bottom face button on every pad), so the same
## button reads "A" on Xbox, "Cross" on PlayStation and "B" on Nintendo. Use these labels in
## prompts instead of hard-coding one family's names.

const Family := preload("controller_family.gd")

## Where to read an action's binding from: a controller, or the keyboard.
enum Source { PAD, KEYBOARD }

const FACE_POSITIONS := {
	JOY_BUTTON_A: "south", JOY_BUTTON_B: "east", JOY_BUTTON_X: "west", JOY_BUTTON_Y: "north",
}

const DPAD := {
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}

const BUTTONS := {
	"playstation": {
		JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
		# DualShock 4 prints Share here; DualSense prints Create. A family covers both.
		JOY_BUTTON_BACK: "Share / Create", JOY_BUTTON_GUIDE: "PS", JOY_BUTTON_START: "Options",
		JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
		JOY_BUTTON_MISC1: "Mute", JOY_BUTTON_TOUCHPAD: "Touchpad",
	},
	"xbox": {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Xbox", JOY_BUTTON_START: "Menu",
		JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_MISC1: "Share",
		JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2", JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4",
	},
	# Nintendo prints B on the bottom button and A on the right, the mirror of Xbox.
	"nintendo": {
		JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
		JOY_BUTTON_BACK: "-", JOY_BUTTON_GUIDE: "Home", JOY_BUTTON_START: "+",
		JOY_BUTTON_LEFT_STICK: "L stick", JOY_BUTTON_RIGHT_STICK: "R stick",
		JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R",
		JOY_BUTTON_MISC1: "Capture",
	},
	"neutral": {
		JOY_BUTTON_A: "South", JOY_BUTTON_B: "East", JOY_BUTTON_X: "West", JOY_BUTTON_Y: "North",
		JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
		JOY_BUTTON_LEFT_STICK: "Left stick", JOY_BUTTON_RIGHT_STICK: "Right stick",
		JOY_BUTTON_LEFT_SHOULDER: "Left shoulder", JOY_BUTTON_RIGHT_SHOULDER: "Right shoulder",
		JOY_BUTTON_MISC1: "Misc", JOY_BUTTON_TOUCHPAD: "Touchpad",
		JOY_BUTTON_PADDLE1: "Paddle 1", JOY_BUTTON_PADDLE2: "Paddle 2",
		JOY_BUTTON_PADDLE3: "Paddle 3", JOY_BUTTON_PADDLE4: "Paddle 4",
	},
}

const TRIGGERS := {
	"playstation": ["L2", "R2"], "xbox": ["LT", "RT"], "nintendo": ["ZL", "ZR"],
	"neutral": ["Left trigger", "Right trigger"],
}


## The label printed on a button, e.g. JOY_BUTTON_A is "Cross", "A", "B" or "South".
## An unknown family falls back to position names.
static func button(index: int, family: String) -> String:
	if DPAD.has(index):
		return DPAD[index]
	var labels: Dictionary = BUTTONS.get(family, BUTTONS[Family.NEUTRAL])
	if labels.has(index):
		return labels[index]
	return BUTTONS[Family.NEUTRAL].get(index, "Button %d" % index)


## "south", "east", "west" or "north" for a face button; "" for anything else.
static func position(index: int) -> String:
	return FACE_POSITIONS.get(index, "")


## The label for a stick direction or trigger. A negative direction is left/up, positive is
## right/down (Godot's axis convention); 0 names the whole stick.
static func axis(index: int, family: String, direction: float = 0.0) -> String:
	if index == JOY_AXIS_TRIGGER_LEFT or index == JOY_AXIS_TRIGGER_RIGHT:
		var names: Array = TRIGGERS.get(family, TRIGGERS[Family.NEUTRAL])
		return names[0 if index == JOY_AXIS_TRIGGER_LEFT else 1]
	var stick := ""
	var ways: Array = []
	match index:
		JOY_AXIS_LEFT_X:
			stick = "Left stick"
			ways = ["left", "right"]
		JOY_AXIS_LEFT_Y:
			stick = "Left stick"
			ways = ["up", "down"]
		JOY_AXIS_RIGHT_X:
			stick = "Right stick"
			ways = ["left", "right"]
		JOY_AXIS_RIGHT_Y:
			stick = "Right stick"
			ways = ["up", "down"]
		_:
			return "Axis %d" % index
	if is_zero_approx(direction):
		return stick
	return "%s %s" % [stick, ways[0 if direction < 0.0 else 1]]


## The label for one bound event: a pad button or axis, or a key; "" for anything else.
static func event(input: InputEvent, family: String) -> String:
	if input is InputEventJoypadButton:
		return button(input.button_index, family)
	if input is InputEventJoypadMotion:
		return axis(input.axis, family, input.axis_value)
	if input is InputEventKey:
		return key(input)
	return ""


## A key event's label, with modifiers ("Ctrl+S"). Physical bindings name the key in the US
## QWERTY position Godot stores.
static func key(input: InputEventKey) -> String:
	if input.keycode != KEY_NONE:
		return input.as_text_keycode()
	if input.physical_keycode != KEY_NONE:
		return input.as_text_physical_keycode()
	return input.as_text_key_label()


## Labels for every event of one source bound to an action, in InputMap order, without repeats.
## Empty when the action does not exist or has no binding of that source.
static func action_labels(action_name: StringName, family: String, source: Source = Source.PAD) -> PackedStringArray:
	var labels := PackedStringArray()
	if not InputMap.has_action(action_name):
		return labels
	for input: InputEvent in InputMap.action_get_events(action_name):
		var is_pad := input is InputEventJoypadButton or input is InputEventJoypadMotion
		var wanted := is_pad if source == Source.PAD else input is InputEventKey
		var label := event(input, family) if wanted else ""
		if not label.is_empty() and not labels.has(label):
			labels.append(label)
	return labels


## The first label of one source bound to an action, or "" when it has none.
static func action(action_name: StringName, family: String, source: Source = Source.PAD) -> String:
	var labels := action_labels(action_name, family, source)
	return labels[0] if not labels.is_empty() else ""
