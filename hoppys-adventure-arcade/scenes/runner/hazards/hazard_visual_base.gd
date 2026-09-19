extends Node3D
## Base for hazards/visuals/<kind>_visual.tscn (contract §5.2). The backend sets every var below
## before calling on_spawned(). Visuals never free themselves; the backend owns lifetime.
## Visual bounds must stay within 110 % of hitbox_size on every axis.
@warning_ignore_start("unused_parameter")

var kind: StringName = &""
var variant: StringName = &""
var hitbox_size := Vector3.ZERO
## Hitbox centre relative to the hazard root.
var hitbox_offset := Vector3.ZERO
## Bit 0 = lane x -2, bit 1 = lane x 0, bit 2 = lane x +2.
var lanes_mask := 0
var dodge_hint: StringName = &""

## After the vars above are set; reset every tween and particle (hazards may be reused).
func on_spawned() -> void:
	pass

## This hazard damaged the player, or the damage was blocked.
func on_hit_player() -> void:
	pass

## Auto-Fix removed it; the hitbox is already off.
func on_cleared() -> void:
	pass

## Timed laser only: 0 -> 1 over the 0.4 s before a state change, every physics tick.
func set_telegraph(t: float) -> void:
	pass

## Timed laser only: ground, high or off.
func set_laser_state(state: StringName) -> void:
	pass

@warning_ignore_restore("unused_parameter")
