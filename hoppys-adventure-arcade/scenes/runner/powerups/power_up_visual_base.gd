extends Node3D
## Base for powerups/visuals/<kind>_visual.tscn (contract §5.3). The pickup sphere is r 0.35,
## centred at the root. The backend sets `kind` before calling on_spawned().

var kind: StringName = &""

## After `kind` is set. show() first, so a visual that on_collected() hid comes back clean when the
## backend reuses it; an override must call super() before its own reset work.
func on_spawned() -> void:
	show()

## Default: vanish on pickup. Override without calling super() to play a collect animation
## instead; the backend never frees the visual itself.
func on_collected() -> void:
	hide()
