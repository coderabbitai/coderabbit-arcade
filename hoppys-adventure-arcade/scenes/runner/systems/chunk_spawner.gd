extends Node
## Seeded chunk selection, the seam gap rule, despawn and power-up placement (systems spec §5.2).

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const ChunkLibrary = preload("res://scenes/runner/data/chunk_library.gd")
const PowerUpDefs = preload("res://scenes/runner/powerups/power_up_defs.gd")
## Typed so `kind` is a checked property access and not a dynamic one (power_up.gd never
## preloads the spawner, so this adds no cycle).
const PowerUp = preload("res://scenes/runner/powerups/power_up.gd")
const POWER_UP_SCENE := "res://scenes/runner/powerups/power_up.tscn"
const LIBRARY_PATH := "res://scenes/runner/data/chunk_library.tres"
const CHUNKS_PATH := "World/Chunks"
## Chunks tagged this way are the rest beats the spawner leans on while the pursuer is close.
const BREATHER_TAG := "breather"
## Chunk slot meta value that asks for the jump-height pickup row (chunk.gd HEIGHT_JUMP).
const SLOT_HEIGHT_JUMP := "jump"
const BREATHER_PURSUED_WEIGHT := 2.0
## Difficulty ranges are authored to two decimals; compare with a little slack.
const DIFFICULTY_EPSILON := 0.0001
## Auto-Fix clears hazards from just behind the player out to blast_range_z ahead.
const BLAST_NEAR_Z := 1.0
## Hard stop so a degenerate library (zero-length chunks) can never spin _fill().
const FILL_GUARD := 64
## The authored entry clearance every chunk carries (systems spec §5.1, the validator's MIN_CLEAR).
## A stale frontier is clamped no closer to the player than this, so a stage that opens on an empty
## corridor can never park its first chunk underfoot.
const ENTRY_CLEAR_DISTANCE := 6.0
## Contract §11.10 fallback, used only when the config predates the stage-entrance fields. The
## window's own length is not one: begin_clear_road() is always told how long it is.
const DEFAULT_STAGE_BANNER_REACTION_SECONDS := 1.0
## Newest-first cap on the debug log the smoke test prints when it fails.
const CHUNK_LOG_LIMIT := 256

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
## False while the stage drains, and through turn, boss and stage_clear (systems spec §10.6).
## Movement and despawn carry on regardless; only new placements stop.
var spawning := true
## Seconds left in the stage-entrance window opened by begin_clear_road() (contract §11.1). While it
## is above zero the corridor may only take chunks whose hazards arrive after it, plus the reaction
## time; it counts down with the scroll, so a paused game never burns it.
var _clear_road_remaining := 0.0

var _chunk_log := PackedStringArray()
var _power_up_scene: PackedScene
var _power_up_scene_checked := false
## One warning per spawner when the library holds no breather to fall back on.
var _breather_warned := false

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	metas.clear()
	if ResourceLoader.exists(LIBRARY_PATH):
		library = load(LIBRARY_PATH) as ChunkLibrary
	if library == null:
		push_warning("Runner chunk library missing at %s; the spawner has nothing to place" % LIBRARY_PATH)
		return
	for scene in library.scenes:
		var meta := _read_meta(scene)
		if not meta.is_empty():
			metas.append(meta)
	if metas.is_empty():
		push_warning("Runner chunk library at %s holds no usable chunks" % LIBRARY_PATH)

func reset(run_seed: int) -> void:
	# Leave the tree before freeing, so no stale hazard is left in runner_hazards this frame.
	for chunk in active:
		if not is_instance_valid(chunk):
			continue
		var parent := chunk.get_parent()
		if parent != null:
			parent.remove_child(chunk)
		chunk.queue_free()
	active.clear()
	var root := _chunks_root()
	if root != null:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()
	_chunk_log.clear()
	spawning = true
	# start_run() resets the spawner before the StageManager opens stage 1, so the window the first
	# stage_started asks for is always opened after this line, never wiped by it.
	_clear_road_remaining = 0.0
	spawn_rng.seed = run_seed
	powerup_rng.seed = run_seed ^ 0x9E3779B9
	last_index = -1
	last_powerup_time = -999.0
	last_powerup_kind = &""
	chunks_since_powerup = 0
	chunks_spawned = 0
	# Clean run-in: the first chunk starts 2.5 s of travel ahead of the player.
	frontier_z = -(float(config.base_speed) * 2.5) if config != null else 0.0
	_fill()

func get_active_chunks() -> Array[Node3D]:
	return active

## The StageManager gates placement: off a drain's worth of metres before the stage target, back on
## when the next stage begins. Switching it on tops the corridor straight back up, so the first
## chunks of a stage are in place on the same tick the stage starts.
func set_spawning(on: bool) -> void:
	spawning = on
	if not spawning:
		return
	_fill()

## Open the stage-entrance window (contract §11.1): for `seconds` the stage banner is covering the
## lanes, so nothing the player would have to dodge may reach them. The StageManager calls this on
## every stage entry, stage 1 included, immediately before it switches placement back on.
##
## Three things happen here. The window itself starts counting down in _physics_process, which also
## re-runs the sweep below on every tick of it, at the speed of that tick. A corridor
## that has already emptied has a stale `frontier_z` — it is only ever re-read from the last active
## chunk, so after a drain, a turn, a boss and a stage-clear card it has scrolled to somewhere at or
## behind the player — and is clamped back to at least ENTRY_CLEAR_DISTANCE ahead, so the first
## chunk of the stage can never be parked underfoot. Finally anything already inbound inside the
## window is swept away.
##
## Re-entering while a window is still open keeps the longer of the two.
func begin_clear_road(seconds: float) -> void:
	var window := maxf(seconds, 0.0)
	if window <= 0.0:
		return
	_clear_road_remaining = maxf(_clear_road_remaining, window)
	if active.is_empty():
		frontier_z = minf(frontier_z, -ENTRY_CLEAR_DISTANCE)
	_sweep_clear_road(_clear_road_remaining + _reaction_seconds())

## Seconds left in the stage-entrance window; 0 when none is open.
func clear_road_remaining() -> float:
	return _clear_road_remaining

## Newest-last log of every placement: "%.1fs d=%.2f <name>[ mirrored] gap=%.1f".
func get_chunk_log() -> PackedStringArray:
	return _chunk_log

## Auto-Fix: clear every blocking hazard within blast_range_z ahead of the player. Emits
## hazard_cleared per hazard; the caller emits hazards_blasted with the returned count.
## Boss projectiles are in runner_hazards too, so Auto-Fix clears them as well (contract §11.6);
## the z test goes through the rig-local accessor so a bent corridor cannot skew it.
func clear_hazards_in_range() -> int:
	var tree := get_tree()
	if tree == null or config == null:
		return 0
	var far_z := -absf(float(config.blast_range_z))
	var count := 0
	for node in tree.get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Area3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		# A hazard on its way out is nobody's to clear, and reading a global transform off one that
		# has already left the tree only earns an engine error (see _discard_chunk).
		if hazard.is_queued_for_deletion() or not hazard.is_inside_tree():
			continue
		if not hazard.has_method("is_blocking") or not hazard.is_blocking():
			continue
		var z := game.track_z(hazard) if game != null else hazard.global_position.z
		if z < far_z or z > BLAST_NEAR_Z:
			continue
		hazard.clear()
		count += 1
		if game != null:
			game.hazard_cleared.emit(hazard)
	return count

## Housekeeping, not Auto-Fix: every blocking hazard that could still reach the player inside the
## stage-entrance window is removed silently. No hazard_cleared, no hazards_blasted, no score and no
## result field moves — the player neither dodged these nor blasted them, they were simply never
## theirs to meet. Boss projectiles left over from the fight are in runner_hazards too, so they go
## the same way (contract §11.6); the z test uses the rig-local accessor, like Auto-Fix does.
##
## Called on entry by begin_clear_road() and again on every tick of the window by _physics_process,
## because `reach_seconds` is measured at the speed of the moment: the same hazard is outside the
## reach at the base speed and inside it once Nitro lands. Straight-line work over a group that
## holds at most the corridor's own hazards, and no await — the physics step must not yield.
func _sweep_clear_road(reach_seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var far_z := -absf(_clear_road_speed() * maxf(reach_seconds, 0.0))
	for node in tree.get_nodes_in_group(&"runner_hazards"):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		# Same guard as Auto-Fix: a hazard that has left the tree, or is only waiting to be deleted,
		# is swept by nothing and read by nothing (see _discard_chunk).
		if hazard.is_queued_for_deletion() or not hazard.is_inside_tree():
			continue
		if not hazard.has_method("is_blocking") or not hazard.is_blocking():
			continue
		if not hazard.has_method("clear"):
			continue
		var z := game.track_z(hazard) if game != null else hazard.global_position.z
		if z < far_z or z > BLAST_NEAR_Z:
			continue
		hazard.clear()

## Scroll the corridor, despawn what is behind the player, top the frontier back up — and, while a
## stage-entrance window is open, count it down and re-validate its promise (contract §11.1).
## Admission is measured once, at the speed of the tick that placed the chunk, so a mid-window
## speed increase — Nitro's ×1.25 or the difficulty ramp — shortens every arrival already in the
## corridor and can pull a hazard that was admitted back inside the window. Re-sweeping each tick
## at the current speed is what keeps the promise true rather than true-when-made.
func _physics_process(delta: float) -> void:
	if game == null or config == null:
		return
	if game.state != &"running" and game.state != &"caught":
		return
	# The window rides the same delta the corridor scrolls on. The Systems node is PAUSABLE, so this
	# never runs while the tree is frozen; the explicit guard keeps a hand-driven rig honest too.
	if bool(game.paused):
		return
	if _clear_road_remaining > 0.0:
		_clear_road_remaining = maxf(_clear_road_remaining - delta, 0.0)
		# Both sides of the admission test fall at one second per second while the speed holds, so
		# this clears nothing on a steady corridor; it only bites when the speed went up under it.
		if _clear_road_remaining > 0.0:
			_sweep_clear_road(_clear_road_remaining + _reaction_seconds())
	var dz := float(game.speed) * delta
	frontier_z += dz
	for chunk in active:
		if is_instance_valid(chunk):
			chunk.position.z += dz
	_despawn()
	_fill()

# --- placement ---

## Top up the active set. frontier_z is re-read from the last chunk first, because chunks have
## moved since the previous call.
func _fill() -> void:
	if game == null or config == null or metas.is_empty():
		return
	if not spawning or not _phase_allows_placement():
		return
	var root := _chunks_root()
	if root == null:
		return
	if not active.is_empty():
		var last := active[active.size() - 1]
		if is_instance_valid(last):
			frontier_z = last.back_edge_z()
	var placed := 0
	while active.size() < int(config.max_active_chunks) and frontier_z > float(config.spawn_horizon_z):
		placed += 1
		if placed > FILL_GUARD:
			push_warning("Runner spawner hit the fill guard; check chunk lengths")
			return
		if not _place_next(root):
			return

func _place_next(root: Node3D) -> bool:
	var index := _pick_index(float(game.difficulty), false)
	if index < 0:
		return false
	var chunk := _build_chunk(index, root)
	if chunk == null:
		return false
	var gap := _gap_for(chunk)
	chunk.position.z = frontier_z - gap
	# Stage-entrance window (contract §11.1): a chunk whose first hazard could arrive while the
	# banner is still up — or inside the reaction time the player is owed straight after it — is
	# swapped for a hazard-free breather. The measurement needs the instance, so the draw is made,
	# measured and only then rejected; the reject leaves the tree before its hazards are ever seen.
	if not _clear_road_admits(chunk):
		var breather := _pick_index(float(game.difficulty), true)
		_discard_chunk(chunk)
		if breather < 0:
			_warn_missing_breather()
			return false
		index = breather
		chunk = _build_chunk(index, root)
		if chunk == null:
			return false
		gap = _gap_for(chunk)
		chunk.position.z = frontier_z - gap
	var meta := metas[index]
	last_index = index
	var mirrored := bool(meta["mirror_x"]) and spawn_rng.randf() < float(config.chunk_mirror_chance)
	chunk.setup(game, mirrored)
	active.append(chunk)
	chunks_spawned += 1
	chunks_since_powerup += 1
	frontier_z = chunk.back_edge_z()
	_log_placement(meta, mirrored, gap)
	_maybe_place_power_up(chunk)
	if game != null:
		game.chunk_spawned.emit(chunk)
	return true

## Seam rule (contract §7): the player always gets v x 1.02 x t_spacing seconds between the last
## forced action of the previous chunk and the first of the next one.
func _gap_for(chunk: Node3D) -> float:
	var spacing := config.t_spacing(float(game.difficulty))
	if _is_pursued():
		spacing += float(config.t_spacing_pursued_bonus)
	# game.speed already carries the Nitro multiplier; never plan tighter than the base speed, so
	# the catch deceleration cannot pack chunks together.
	var v_eff := maxf(float(game.speed), float(config.base_speed))
	var previous_exit := 0.0
	if not active.is_empty():
		var previous := active[active.size() - 1]
		if is_instance_valid(previous):
			previous_exit = previous.exit_clear()
	return maxf(0.0, v_eff * float(config.gap_safety) * spacing - previous_exit - chunk.entry_clear())

## Instantiate one library chunk and park it on the frontier, inside the tree. The exact z follows
## once entry_clear() can be measured, so its hazards never spend a frame at the origin.
func _build_chunk(index: int, root: Node3D) -> Node3D:
	var meta := metas[index]
	var scene: PackedScene = meta["scene"]
	var chunk := scene.instantiate() as Node3D
	if chunk == null:
		push_warning("Runner chunk %s did not instantiate as a Node3D" % meta["name"])
		return null
	chunk.position = Vector3(0.0, 0.0, frontier_z)
	root.add_child(chunk)
	return chunk

## Drop a chunk that was drawn, measured and rejected: out of the tree, then freed on the spot.
##
## Not `queue_free()`. A queued chunk stays alive, and out of the tree, until the end of the frame,
## and its hazards ran `_ready()` the moment they were added — which, for a hazard whose config has
## not arrived yet, leaves a deferred `_mount_visual()` in the message queue. That callable is
## flushed at the end of the frame, on a node that is by then parentless, and everything it touches
## (`lanes_mask()` -> `global_position`, a frontend visual's `on_spawned()`) reads a global transform
## off a node that is no longer in the tree: `Condition "!is_inside_tree()" is true`. The same window
## is open to anything else that walks `runner_hazards` before the frame ends, and the accelerated
## visual smoke runs several physics ticks per rendered frame, so the window is hundreds of reads
## wide, not one.
##
## Freeing immediately closes it: the instance is destroyed here, so the pending deferred call is
## dropped with it. That is safe because this chunk was instantiated a few lines ago in this same
## `_place_next()` — `setup()` never ran, it was never appended to `active`, nothing in the run
## holds a reference to it, and we are not inside one of its own callbacks.
func _discard_chunk(chunk: Node3D) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	var parent := chunk.get_parent()
	if parent != null:
		parent.remove_child(chunk)
	chunk.free()

## May this chunk be placed where it now stands? Outside the stage-entrance window everything may;
## inside it, only a chunk whose nearest hazard cannot reach the player before the window and the
## reaction time have both run out. A chunk with no hazards always may.
func _clear_road_admits(chunk: Node3D) -> bool:
	if _clear_road_remaining <= 0.0:
		return true
	if chunk.get_hazards().is_empty():
		return true
	# The player sits at z = 0 and the corridor closes on them, so the nearest hazard's leading edge
	# is entry_clear() beyond the chunk front and its arrival is that distance over the speed.
	var nearest_z := chunk.global_position.z - float(chunk.entry_clear())
	var arrival := -nearest_z / _clear_road_speed()
	return arrival >= _clear_road_remaining + _reaction_seconds()

## The speed the window's arithmetic is done at: the corridor's own, floored at the base speed (as
## the seam rule floors it) and never zero, so a stalled facade cannot promise an infinite lead.
func _clear_road_speed() -> float:
	var current := float(game.speed) if game != null else 0.0
	var base := float(config.base_speed) if config != null else 0.0
	return maxf(maxf(current, base), 1.0)

func _reaction_seconds() -> float:
	if config == null or not (&"stage_banner_reaction_seconds" in config):
		return DEFAULT_STAGE_BANNER_REACTION_SECONDS
	return maxf(float(config.stage_banner_reaction_seconds), 0.0)

## Said once per spawner: a library with no breather has nothing safe to lay down while the banner
## is up, so the corridor stays empty until the window closes rather than risk a blind hit.
func _warn_missing_breather() -> void:
	if _breather_warned:
		return
	_breather_warned = true
	push_warning("Runner chunk library has no `%s` chunk; the stage-entrance window has nothing safe to place"
		% BREATHER_TAG)

## Weighted pick among the chunks whose difficulty range covers `d`, never repeating the previous
## chunk while an alternative exists. Breathers double their weight while the pursuer is close.
## `breathers_only` is the stage-entrance window's fallback: it narrows the draw to the rest beats,
## and because the no-repeat rule only bites while an alternative is left, two breathers alternate
## and a library with one simply repeats it rather than coming back empty-handed.
func _pick_index(d: float, breathers_only: bool) -> int:
	var candidates: Array[int] = []
	for i in metas.size():
		var meta := metas[i]
		if breathers_only and not bool(meta["breather"]):
			continue
		if d >= float(meta["min_difficulty"]) - DIFFICULTY_EPSILON \
				and d <= float(meta["max_difficulty"]) + DIFFICULTY_EPSILON:
			candidates.append(i)
	if candidates.is_empty() and breathers_only:
		# Out-of-range breathers still beat a hazard while the banner is up.
		for i in metas.size():
			if bool(metas[i]["breather"]):
				candidates.append(i)
		if candidates.is_empty():
			return -1
	if candidates.is_empty():
		push_warning("Runner spawner found no chunk for difficulty %.2f; falling back to the whole library" % d)
		for i in metas.size():
			candidates.append(i)
	if candidates.size() > 1 and last_index >= 0:
		candidates.erase(last_index)
	if candidates.is_empty():
		return -1
	var pursued := _is_pursued()
	var weights := PackedFloat32Array()
	for i in candidates:
		var weight := maxf(float(metas[i]["weight"]), 0.0)
		if pursued and bool(metas[i]["breather"]):
			weight *= BREATHER_PURSUED_WEIGHT
		weights.append(weight)
	var pick := spawn_rng.rand_weighted(weights)
	if pick < 0 or pick >= candidates.size():
		pick = spawn_rng.randi_range(0, candidates.size() - 1)
	return candidates[pick]

func _log_placement(meta: Dictionary, mirrored: bool, gap: float) -> void:
	var line := "%.1fs d=%.2f %s%s gap=%.1f" % [
		float(game.elapsed), float(game.difficulty), meta["name"],
		" mirrored" if mirrored else "", gap
	]
	_chunk_log.append(line)
	if _chunk_log.size() > CHUNK_LOG_LIMIT:
		_chunk_log.remove_at(0)

# --- power-ups ---

## Contract §7: a pickup needs a 10 s cooldown, at least one chunk since the last one, and a
## difficulty-scaled roll. The roll is only consumed once the first two gates pass, so the stream
## stays deterministic per seed.
func _maybe_place_power_up(chunk: Node3D) -> void:
	if game.elapsed - last_powerup_time < float(config.powerup_cooldown_seconds):
		return
	if chunks_since_powerup < 1:
		return
	if powerup_rng.randf() >= config.powerup_chance(float(game.difficulty)):
		return
	var slots: Array = chunk.get_slots()
	if slots.is_empty():
		return
	var slot := slots[powerup_rng.randi_range(0, slots.size() - 1)] as Node3D
	if slot == null:
		return
	var kind := _pick_power_up_kind()
	if kind == &"":
		return
	var scene := _power_up_packed_scene()
	if scene == null:
		return
	var pickup := scene.instantiate() as PowerUp
	if pickup == null:
		push_warning("Runner power-up scene did not instantiate as a power_up.gd Area3D")
		return
	pickup.kind = kind
	var height := float(config.pickup_height_run)
	if String(chunk.slot_height(slot)) == SLOT_HEIGHT_JUMP:
		height = float(config.pickup_height_jump)
	pickup.position = Vector3(slot.position.x, height, slot.position.z)
	chunk.add_child(pickup)
	pickup.setup(game)
	last_powerup_time = game.elapsed
	last_powerup_kind = kind
	chunks_since_powerup = 0

## Weighted over power_up_defs, skipping the previous kind and anything the player already holds.
func _pick_power_up_kind() -> StringName:
	var held := _held_power_ups()
	var kinds: Array[StringName] = []
	var weights := PackedFloat32Array()
	for kind in PowerUpDefs.kinds():
		var candidate: StringName = kind
		if candidate == last_powerup_kind or held.has(candidate):
			continue
		kinds.append(candidate)
		weights.append(float(PowerUpDefs.weight(candidate)))
	if kinds.is_empty():
		# Everything is on cooldown or held: fall back to anything but a straight repeat.
		for kind in PowerUpDefs.kinds():
			var candidate: StringName = kind
			if candidate == last_powerup_kind:
				continue
			kinds.append(candidate)
			weights.append(float(PowerUpDefs.weight(candidate)))
	if kinds.is_empty():
		return &""
	var pick := powerup_rng.rand_weighted(weights)
	if pick < 0 or pick >= kinds.size():
		pick = powerup_rng.randi_range(0, kinds.size() - 1)
	return kinds[pick]

## Kinds whose effect is already running or stored, asked for defensively: the managers are
## siblings that may still be stubs.
func _held_power_ups() -> Dictionary:
	var held := {}
	if game == null:
		return held
	var effects := game.effect_manager
	if effects != null and is_instance_valid(effects):
		if effects.has_method("get_active_effects"):
			for kind in effects.get_active_effects():
				held[kind] = true
		if effects.has_method("has_super_jump") and effects.has_super_jump():
			held[&"super_jump"] = true
		if "code_review_held" in effects and bool(effects.get(&"code_review_held")):
			held[&"code_review"] = true
	var hits := game.hit_manager
	if hits != null and is_instance_valid(hits) and "shield" in hits and bool(hits.get(&"shield")):
		held[&"approve_shield"] = true
	return held

func _power_up_packed_scene() -> PackedScene:
	if _power_up_scene_checked:
		return _power_up_scene
	_power_up_scene_checked = true
	if ResourceLoader.exists(POWER_UP_SCENE):
		_power_up_scene = load(POWER_UP_SCENE) as PackedScene
	if _power_up_scene == null:
		push_warning("Runner power-up scene missing at %s; no pickups will spawn" % POWER_UP_SCENE)
	return _power_up_scene

# --- housekeeping ---

func _despawn() -> void:
	var despawn_z := float(config.despawn_z)
	for i in range(active.size() - 1, -1, -1):
		var chunk := active[i]
		if not is_instance_valid(chunk):
			active.remove_at(i)
			continue
		if chunk.back_edge_z() <= despawn_z:
			continue
		active.remove_at(i)
		# Leave the tree first, so the hazards drop out of runner_hazards this frame.
		var parent := chunk.get_parent()
		if parent != null:
			parent.remove_child(chunk)
		chunk.queue_free()

func _chunks_root() -> Node3D:
	if game == null:
		return null
	var root := game.chunks
	if root != null and is_instance_valid(root):
		return root
	return game.get_node_or_null(NodePath(CHUNKS_PATH)) as Node3D

## Chunks are only ever placed inside the RUN phase (systems spec §10.6). A facade with no
## StageManager has no phases to gate on — a hand-built unit-test rig keeps the v1 behaviour.
func _phase_allows_placement() -> bool:
	if game == null:
		return false
	var manager: Node = game.stage_manager
	if manager == null or not is_instance_valid(manager):
		return true
	return game.phase == &"run"

func _is_pursued() -> bool:
	if game == null:
		return false
	var hits := game.hit_manager
	if hits == null or not is_instance_valid(hits) or not hits.has_method("is_pursued"):
		return false
	return bool(hits.is_pursued())

## Read one chunk's exports off a throwaway instance; the prototype never enters the tree.
func _read_meta(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {}
	var proto := scene.instantiate() as Node3D
	if proto == null:
		push_warning("Runner chunk library holds a scene whose root is not a Node3D")
		return {}
	var tags: PackedStringArray = proto.get(&"tags")
	var meta := {
		"scene": scene,
		"name": scene.resource_path.get_file().get_basename(),
		"length": float(proto.get(&"length")),
		"weight": float(proto.get(&"weight")),
		"min_difficulty": float(proto.get(&"min_difficulty")),
		"max_difficulty": float(proto.get(&"max_difficulty")),
		"mirror_x": bool(proto.get(&"mirror_x")),
		"breather": tags.has(BREATHER_TAG)
	}
	proto.free()
	return meta
