extends Node3D
## One authored corridor slice (systems spec §5.1). The front edge is z = 0 and the back edge is
## z = -length; hazards sit at negative z offsets and lane x (-2 / 0 / +2).
## Layout convention: band i (counted from the entry) spans z in [-6(i+1), -6i]; a depth-1.2
## hazard occupies 2.4..3.6 m into its band and a pit 1.5..4.5 m, so every hazard node sits at
## z = -(6i + 3).

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const SLOT_GROUP: StringName = &"pickup_slot"
const HAZARD_GROUP: StringName = &"runner_hazards"
const HEIGHT_META := "height"
const HEIGHT_RUN := "run"
const HEIGHT_JUMP := "jump"

## Multiple of 6 metres.
@export var length := 18.0
@export var weight := 1.0
@export var min_difficulty := 0.0
@export var max_difficulty := 1.0
@export var mirror_x := true
@export var tags := PackedStringArray()

var game: RunnerGame
var mirrored := false

var _setup_done := false

## Called once when the spawner places the chunk. Mirroring negates every child's x.
func setup(runner: RunnerGame, mirror: bool) -> void:
	if _setup_done:
		return
	_setup_done = true
	game = runner
	mirrored = mirror
	for child in get_children():
		var node := child as Node3D
		if node == null:
			continue
		if mirror:
			node.position.x = -node.position.x
		if node.has_method("setup"):
			node.setup(runner)

func get_hazards() -> Array[Node]:
	var found: Array[Node] = []
	for child in get_children():
		if child.is_in_group(HAZARD_GROUP):
			found.append(child)
	return found

## Marker3D power-up slots in group `pickup_slot`, meta `height` = run | jump.
func get_slots() -> Array[Node]:
	var found: Array[Node] = []
	for child in get_children():
		if child.is_in_group(SLOT_GROUP):
			found.append(child)
	return found

## `run` (y 1.0) or `jump` (y 2.2); anything unset reads as `run`.
func slot_height(slot: Node) -> String:
	if slot != null and slot.has_meta(HEIGHT_META):
		var value := String(slot.get_meta(HEIGHT_META))
		if value == HEIGHT_JUMP:
			return HEIGHT_JUMP
	return HEIGHT_RUN

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
