extends Node3D
## One authored corridor slice (systems spec §5.1). The front edge is z = 0 and the back edge is
## z = -length; hazards sit at negative z offsets and lane x (-2 / 0 / +2).
## PR 1 scaffold: exports and the public API; the 19 authored chunks land in PR 2.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")

## Multiple of 6 metres.
@export var length := 18.0
@export var weight := 1.0
@export var min_difficulty := 0.0
@export var max_difficulty := 1.0
@export var mirror_x := true
@export var tags := PackedStringArray()

var game: RunnerGame
var mirrored := false

## Called once when the spawner places the chunk. Mirroring negates every child's x.
func setup(runner: RunnerGame, mirror: bool) -> void:
	game = runner
	mirrored = mirror
	for child in get_children():
		if child is Node3D:
			if mirror:
				(child as Node3D).position.x = -(child as Node3D).position.x
			if child.has_method("setup"):
				child.setup(runner)

func get_hazards() -> Array[Node]:
	var found: Array[Node] = []
	for child in get_children():
		if child.is_in_group(&"runner_hazards"):
			found.append(child)
	return found

## Marker3D power-up slots in group `pickup_slot`, meta `height` = run | jump.
func get_slots() -> Array[Node]:
	var found: Array[Node] = []
	for child in get_children():
		if child.is_in_group(&"pickup_slot"):
			found.append(child)
	return found

## Clear metres between the chunk front (local z = 0, the side the player meets first) and the
## nearest hazard edge.
func entry_clear() -> float:
	var nearest := length
	for hazard in get_hazards():
		nearest = minf(nearest, -_hazard_z_span(hazard).x)
	return maxf(nearest, 0.0)

## Clear metres between the furthest hazard edge and the chunk back edge (local z = -length).
func exit_clear() -> float:
	var nearest := length
	for hazard in get_hazards():
		nearest = minf(nearest, _hazard_z_span(hazard).y + length)
	return maxf(nearest, 0.0)

## World z of the trailing edge; the spawner despawns once this passes despawn_z.
func back_edge_z() -> float:
	return global_position.z - length

## Chunk-local z span of a hazard's actual hitbox as (front, back); front is the larger z, the
## edge the player meets first. Derived from the documented get_world_aabb() so the hitbox depth
## and its offset both count, which keeps consecutive hazards from being packed too closely.
func _hazard_z_span(hazard: Node) -> Vector2:
	var node := hazard as Node3D
	if node == null:
		return Vector2.ZERO
	if node.has_method("get_world_aabb"):
		var bounds: AABB = node.get_world_aabb()
		var near_z := to_local(bounds.end).z
		var far_z := to_local(bounds.position).z
		return Vector2(maxf(near_z, far_z), minf(near_z, far_z))
	# No hitbox accessor: treat the node origin as a zero-depth marker.
	return Vector2(node.position.z, node.position.z)
