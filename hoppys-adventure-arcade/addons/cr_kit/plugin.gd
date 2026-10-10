@tool
extends EditorPlugin
## The kit is runtime code that games preload, so enabling the plugin is optional. When it is
## enabled, it warns about an engine older than the kit supports.

const Version := preload("version.gd")


func _enter_tree() -> void:
	if not Version.engine_supported():
		push_warning("CodeRabbit Kit %s needs Godot %s or newer; this editor is %s." % [
			Version.VERSION, Version.MIN_GODOT, Engine.get_version_info().string])
