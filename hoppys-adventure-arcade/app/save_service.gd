extends Node
const PATH := "user://settings.cfg"
var values := {"Master": 0.8, "Music": 0.65, "SFX": 0.8, "fullscreen": false}
var last_error := OK
func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		for key in values:
			var value: Variant = config.get_value("settings", key, values[key])
			if key == "fullscreen":
				if value is bool:
					values[key] = value
			elif (value is float or value is int) and is_finite(float(value)):
				values[key] = clampf(float(value), 0, 1)
	apply_display()
func persist() -> Error:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("settings", key, values[key])
	last_error = config.save(PATH)
	return last_error
func apply_display() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
