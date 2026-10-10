extends RefCounted
## Controller-aware prompt text for UI scripts. Preload this instead of naming the ControllerService
## autoload: suites preload UI scripts before autoloads exist, and a bare autoload name does not
## compile then. Without the service (or a controller), prompts show the keys alone.


static func service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"ControllerService") if tree else null


## The label of an action's first pad binding for the player's controller, or "".
static func pad(action: StringName) -> String:
	var controllers := service()
	return controllers.pad(action) if controllers else ""


## "Space / Cross" with a controller connected, "Space" without one.
static func keys_or_pad(keys: String, pad_label: String) -> String:
	return keys if pad_label.is_empty() else "%s / %s" % [keys, pad_label]


## `text` while a controller is connected, "" otherwise: `keys_or_pad("WASD", if_pad("stick"))`.
static func if_pad(text: String) -> String:
	var controllers := service()
	return text if controllers and not controllers.family.is_empty() else ""


## keys_or_pad() for an action: `either("Space", &"jump")`.
static func either(keys: String, action: StringName, upper: bool = false) -> String:
	var label := pad(action)
	return keys_or_pad(keys, label.to_upper() if upper else label)


## Sets a label's text now and whenever the player's controller family changes.
static func track(label: Label, build: Callable) -> void:
	var controllers := service()
	if controllers:
		controllers.track(label, build)
	else:
		label.text = build.call()
