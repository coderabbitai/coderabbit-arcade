extends Node
## Seeded chunk selection, the seam gap rule, despawn and power-up placement (systems spec §5.2).
## PR 1 scaffold: state and the public API; the algorithm lands in PR 2.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const ChunkLibrary = preload("res://scenes/runner/data/chunk_library.gd")
const POWER_UP_SCENE := "res://scenes/runner/powerups/power_up.tscn"
const LIBRARY_PATH := "res://scenes/runner/data/chunk_library.tres"

var game: RunnerGame
var config: RunConfig
var library: ChunkLibrary
## One entry per library scene: the exports read off a throwaway prototype.
var metas: Array[Dictionary] = []
var active: Array[Node3D] = []
var spawn_rng := RandomNumberGenerator.new()
var powerup_rng := RandomNumberGenerator.new()
## Back edge of the last placed chunk, in world z.
var frontier_z := 0.0
var last_index := -1
var last_powerup_time := -999.0
var last_powerup_kind: StringName = &""
var chunks_since_powerup := 0
var chunks_spawned := 0

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	if ResourceLoader.exists(LIBRARY_PATH):
		library = load(LIBRARY_PATH) as ChunkLibrary
	metas.clear() # PR 2: instantiate each scene once to read exports, then free the prototypes.

func reset(run_seed: int) -> void:
	for chunk in active:
		if is_instance_valid(chunk):
			chunk.queue_free()
	active.clear()
	spawn_rng.seed = run_seed
	powerup_rng.seed = run_seed ^ 0x9E3779B9
	last_index = -1
	last_powerup_time = -999.0
	last_powerup_kind = &""
	chunks_since_powerup = 0
	chunks_spawned = 0
	frontier_z = -(float(config.base_speed) * 2.5) if config != null else 0.0

## Auto-Fix: clear every blocking hazard within blast_range_z ahead of the player.
func clear_hazards_in_range() -> int:
	return 0 # PR 2.

func get_active_chunks() -> Array[Node3D]:
	return active

func _physics_process(_delta: float) -> void:
	pass # PR 2: advance chunks toward +Z, despawn past despawn_z, refill to max_active_chunks.
