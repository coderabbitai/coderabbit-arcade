extends RefCounted
## The six Endless Runner power-ups (contract §7 weights, §8 kind list).
## `duration` is 0.0 for one-shot kinds (contract §4.1: power_up_collected duration 0).
## `color` is only used by the code-built graybox pickup when no frontend visual exists.

const DEFS := {
	&"approve_shield": {
		"weight": 25,
		"duration": 0.0,
		"color": Color("79e0c4"),
		"label": "Approve Shield"
	},
	&"code_review": {
		"weight": 25,
		"duration": 0.0,
		"color": Color("ff7185"),
		"label": "Code Review Bonus"
	},
	&"super_jump": {
		"weight": 15,
		"duration": 0.0,
		"color": Color("c08bff"),
		"label": "Super Jump"
	},
	&"nitro": {
		"weight": 15,
		"duration": 8.0,
		"color": Color("6ab7ff"),
		"label": "Nitro"
	},
	&"auto_fix": {
		"weight": 10,
		"duration": 0.0,
		"color": Color("f5a568"),
		"label": "Auto-Fix"
	},
	&"lgtm": {
		"weight": 10,
		"duration": 5.0,
		"color": Color("ffd75e"),
		"label": "LGTM"
	}
}

## Kinds whose effect runs on a timer (refresh-not-stack).
const TIMED_KINDS := [&"nitro", &"lgtm"]

static func kinds() -> Array:
	return DEFS.keys()

static func get_def(kind: StringName) -> Dictionary:
	return DEFS.get(kind, {})

static func weight(kind: StringName) -> int:
	return int(DEFS.get(kind, {}).get("weight", 0))

static func duration(kind: StringName) -> float:
	return float(DEFS.get(kind, {}).get("duration", 0.0))

static func color(kind: StringName) -> Color:
	return DEFS.get(kind, {}).get("color", Color("ffffff"))
