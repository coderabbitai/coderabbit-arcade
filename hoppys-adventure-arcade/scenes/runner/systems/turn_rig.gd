extends Node3D
## World/TurnRig: the only node the cinematic turn ever rotates (contract §11.3, systems §10.5).
##
## Gameplay never turns. Chunks, hazards, projectiles, tools and the player all stay in the
## unrotated frame, so every z test in the backend keeps working; only the corridor dressing and the
## boss arena hang under this rig. When the mounted frontend corridor implements `set_turn` it owns
## the bend and the rig stays at yaw 0; otherwise the rig yaws the graybox environment itself
## (contract §11.9, fallback only).

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
## Contract §11.10 fallback, used only when no config has been supplied yet.
const DEFAULT_TURN_YAW_DEGREES := 90.0

var game: RunnerGame
var config: RunConfig
## 0 at the start of the bend, 1 when it is visually back where it began.
var turn_progress := 0.0
## -1 left, +1 right, 0 outside a turn.
var turn_direction := 0
## The mounted frontend corridor, when one exists; null while the graybox is in place.
var corridor: Node = null

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

## RunnerGame hands the mounted corridor over so the rig can offer it the bend first.
func set_corridor(node: Node) -> void:
	corridor = node

func reset() -> void:
	set_turn(0.0, 0)

## Called every physics tick of the `turn` phase, and once with (0, 0) at both ends of it.
func set_turn(progress: float, direction: int) -> void:
	turn_progress = clampf(progress, 0.0, 1.0)
	turn_direction = signi(direction)
	if corridor != null and is_instance_valid(corridor) and corridor.has_method("set_turn"):
		# The frontend owns the visual bend; the rig must stay square or the two would compound.
		rotation.y = 0.0
		corridor.set_turn(turn_progress, turn_direction)
		return
	rotation.y = float(turn_direction) * deg_to_rad(turn_yaw_degrees()) * smoothstep(0.0, 1.0, turn_progress)

func turn_yaw_degrees() -> float:
	return float(config.turn_yaw_degrees) if config != null else DEFAULT_TURN_YAW_DEGREES
