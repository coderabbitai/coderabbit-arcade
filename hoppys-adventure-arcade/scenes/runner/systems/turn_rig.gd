extends Node3D
## World/TurnRig: the static mount the corridor dressing and the boss arena hang under (contract
## §11.3, systems §10.5). The corridor no longer turns, so the rig never rotates; it keeps its name
## because every mount path, fixture and capture tool addresses World/TurnRig.
##
## Gameplay stays in the World frame: chunks, hazards, projectiles, tools and the player are not
## children of this rig, and RunnerGame.track_z() measures through it so a z test never assumes
## where it sits.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")

var game: RunnerGame
## The mounted frontend corridor, when one exists; null while the graybox is in place. The
## StageManager forwards phases and the boss arena to it through this reference.
var corridor: Node = null

func setup(runner: RunnerGame) -> void:
	game = runner
	reset()

## RunnerGame hands the mounted corridor over once it exists.
func set_corridor(node: Node) -> void:
	corridor = node

## Square and at rest: nothing ever turns this rig, so a restart only has to clear stray rotation.
func reset() -> void:
	rotation = Vector3.ZERO
