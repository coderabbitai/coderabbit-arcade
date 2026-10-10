extends RefCounted
## Decides which button labels a controller wears, from the name and USB vendor id the OS reports.
##
## Godot's JoyButton constants name positions, not labels: JOY_BUTTON_A is always the bottom face
## button, whatever is printed on it. This script only decides how to name those positions for a
## player. Labels live in button_labels.gd.

const PLAYSTATION := "playstation"
const XBOX := "xbox"
const NINTENDO := "nintendo"
## Position names (South, East...) for pads we cannot identify.
const NEUTRAL := "neutral"
const ALL: PackedStringArray = [PLAYSTATION, XBOX, NINTENDO, NEUTRAL]

## First-party USB vendor ids. A genuine pad is unambiguous, so the vendor wins over the name.
const VENDORS := {0x054c: PLAYSTATION, 0x045e: XBOX, 0x057e: NINTENDO}
## Lowercase name fragments for licensed third-party pads and for transports that hide the vendor.
## Brand names are checked first, so "PowerA Pro Controller for Xbox" stays Xbox; the generic
## fragments in the second pass ("pro controller", "switch") only decide when no brand appears.
const NAME_TOKENS := [
	["playstation", ["dualsense", "dualshock", "playstation", "sony"]],
	["xbox", ["xbox", "x-box", "xinput", "microsoft"]],
	["nintendo", ["nintendo", "joy-con", "joycon"]],
]
const GENERIC_TOKENS := [
	["playstation", ["ps5", "ps4", "ps3"]],
	["nintendo", ["switch", "pro controller"]],
]


## The family for a pad's reported name and vendor id (0 when unknown).
static func detect(device_name: String, vendor: int = 0) -> String:
	if VENDORS.has(vendor):
		return VENDORS[vendor]
	var lowered := device_name.to_lower()
	for tokens: Array in [NAME_TOKENS, GENERIC_TOKENS]:
		for entry: Array in tokens:
			for token: String in entry[1]:
				if lowered.contains(token):
					return entry[0]
	return NEUTRAL


## The vendor id from an Input.get_joy_info() dictionary, or 0. SDL-backed platforms report it as
## a decimal string; other drivers may report an int or nothing at all.
static func vendor_id(info: Dictionary) -> int:
	var raw: Variant = info.get("vendor_id", 0)
	if raw is int:
		return raw
	if raw is String and raw.is_valid_int():
		return raw.to_int()
	return 0


static func is_family(value: String) -> bool:
	return value in ALL
