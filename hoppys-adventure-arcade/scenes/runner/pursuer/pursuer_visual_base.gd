extends Node3D
## Base for pursuer/pursuer_visual.tscn (contract §5.4). The backend positions the pursuer root at
## y = 0 with z = lerp(retreat_z, approach_z, threat). Keep the visual <= 6 m wide and <= 2.6 m tall
## at threat 1 so it looms without hiding hazards.
@warning_ignore_start("unused_parameter")

## 0 retreated .. 1 about to catch, every tick while pursued.
func set_threat(t: float) -> void:
	pass

## On `caught`. It plays over the caught sequence and holds until a zero threat (the next run).
func play_catch() -> void:
	pass

## On `pursuit_recovered`.
func play_retreat() -> void:
	pass

@warning_ignore_restore("unused_parameter")
