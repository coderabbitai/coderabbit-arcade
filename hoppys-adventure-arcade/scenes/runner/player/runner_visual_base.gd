extends Node3D
## Base for player/hoppy_runner_visual.tscn (contract §5.1). Every hook is a no-op here so a missing
## or partial frontend visual can never break the run. Hoppy faces -Z, feet at y = 0, height 1.8 m;
## the roll pose must fit inside 0.9 m.
@warning_ignore_start("unused_parameter")

## idle, run, jump, fall, roll, hurt, dead. Called on change only.
func set_anim_state(state: StringName) -> void:
	pass

## Normalized run speed, every physics tick.
func set_run_speed(normalized: float) -> void:
	pass

## -1..1 during a lane change, 0 otherwise.
func set_lane_lean(direction: float) -> void:
	pass

## Power-up aura for lgtm, nitro, code_review.
func show_aura(kind: StringName, on: bool) -> void:
	pass

## Approve Shield stored or consumed.
func show_shield(on: bool) -> void:
	pass

## Flash hook on an unblocked hit.
func on_hit() -> void:
	pass

@warning_ignore_restore("unused_parameter")
