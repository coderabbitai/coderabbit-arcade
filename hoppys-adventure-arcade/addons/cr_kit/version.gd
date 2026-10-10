extends RefCounted
## The add-on's release identity. tools/check_release.py keeps these equal to plugin.cfg and the
## newest CHANGELOG.md entry, and a release tag must match VERSION.

const VERSION := "0.1.0"
## The oldest Godot release the add-on supports and CI tests.
const MIN_GODOT := "4.5"


## True when the running engine (or the given Engine.get_version_info() dictionary) is supported.
static func engine_supported(info: Dictionary = {}) -> bool:
	var engine := info if not info.is_empty() else Engine.get_version_info()
	var minimum := MIN_GODOT.split(".")
	var major := int(engine.get("major", 0))
	var minor := int(engine.get("minor", 0))
	return major > int(minimum[0]) or (major == int(minimum[0]) and minor >= int(minimum[1]))
