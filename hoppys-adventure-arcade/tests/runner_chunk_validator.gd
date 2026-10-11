extends SceneTree
## Endless Runner chunk validator (systems spec §8, V1-V10). Loads every
## res://scenes/runner/chunks/chunk_*.tscn and checks the authoring rules in systems spec §5.1
## against the hazard table in contract §8, then drives the real autopilot planner through each
## chunk from every entry lane, policy and speed.
## Run with --path <project> --script res://tests/runner_chunk_validator.gd.

## Only scripts that never reach runner_game.gd can be preloaded: under --script this test is
## compiled before the autoloads exist (see tests/runner_logic.gd).
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const CONFIG_PATH := "res://scenes/runner/data/run_config.tres"
const LIBRARY_PATH := "res://scenes/runner/data/chunk_library.tres"
const GAME_SCENE := "res://scenes/runner/runner_game.tscn"
const ARENA_SCENE := "res://scenes/runner/boss/boss_arena.tscn"
const PROJECTILE_SCENE := "res://scenes/runner/hazards/projectile.tscn"
const CHUNK_DIR := "res://scenes/runner/chunks/"
const TICK := 1.0 / 60.0
const LANE_COUNT := 3
## Seed for the placement checks; any fixed value makes the run reproducible.
const SPAWN_SEED := 4242
## Phases the spawner must stay quiet in (contract §11.1, systems spec §10.6). The drain is still
## inside `run` and is closed by set_spawning(false), which the block below checks on its own.
const IDLE_PHASES: Array[StringName] = [&"boss", &"stage_clear", &"idle"]
## chunk_spawner.gd's BREATHER_TAG: the rest beats it falls back to when nothing may block.
const BREATHER_TAG := "breather"
## Tool draws the no-repeat / height rules are sampled over.
const TOOL_DRAWS := 40
## Where the lane checks park a live projectile: well down the corridor, between the boss and the
## player, which is exactly where one rules its lane out for a tool.
const MID_CORRIDOR_Z := -20.0
## Every lane at once (contract §11.7 lane_mask).
const ALL_LANES := 0b111
## Board every facade here points at. Nothing in this validator finishes a run, so the file is
## never created; the override exists so no code path can ever reach the real board.
const SCRATCH_BOARD := "user://chunk_validator_leaderboard.cfg"
## Systems spec §5.1 authoring rules.
const BAND := 6.0
const MIN_CLEAR := 6.0
const HEAVY_SPACING := 24.0
const PIT_SPACING := 30.0
## Geometry thresholds derived from the §1.1 jump table.
const JUMP_TOP := 1.3
const JUMP_FLOOR := 0.25
const ROLL_FLOOR := 1.0
const EPS := 0.001
## Timed-laser phases the bot is tested against, so no chunk can pass by luck of the clock.
const TIMED_PHASES := [0.0, 0.75, 1.5, 2.25]

var failures := 0
var checks := 0
var config: RunConfig
var bot: Node
var game: Node3D
var junk: Array[Node] = []
## Per-chunk log lines, printed when that chunk fails anything.
var chunk_log: Array[String] = []
## hazard.tscn backs the virtual seam wall; every simulation pass builds one, so cache it and
## report a broken scene once instead of once per pass.
var wall_scene: PackedScene
var wall_scene_broken := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNNER CHUNKS: " + message)

func run() -> void:
	config = (load(CONFIG_PATH) as RunConfig).duplicate()
	var game_script := load("res://scenes/runner/runner_game.gd") as GDScript
	var bot_script := load("res://scenes/runner/systems/autopilot.gd") as GDScript
	if game_script == null or bot_script == null:
		check(false, "the runner scripts could not be loaded")
		_report()
		return
	game = game_script.new()
	game.config = config
	# Nothing here ever calls start_run(), but the facade keeps the board rule anyway: a throwaway
	# path means no code path in this validator can reach the player's user://leaderboard.cfg.
	game.leaderboard_path = SCRATCH_BOARD
	game.state = &"running"
	junk.append(game)
	bot = bot_script.new()
	bot.setup(game)
	junk.append(bot)

	var paths := _chunk_paths()
	check(not paths.is_empty(),
		"no chunk_*.tscn found in %s: the chunk catalog (systems spec §5.1) is not authored yet" % CHUNK_DIR)
	if paths.is_empty():
		_report()
		return
	print("RUNNER CHUNKS: validating %d chunks" % paths.size())
	_check_library(paths)
	var metas: Array[Dictionary] = []
	for path in paths:
		var meta := _validate(path, false)
		if meta.is_empty():
			continue
		metas.append(meta)
		# V10: the spawner mirrors half the chunks, so the mirrored copy faces the same rules.
		if bool(meta["mirror_x"]):
			_validate(path, true)
	_check_difficulty_coverage(metas)
	_check_phase_gate()
	_check_arena_is_chunk_free()
	_check_tool_placement()
	_report()

# --- V11: the spawner only places inside the RUN phase (systems spec §10.6) ---

## Chunks belong to the corridor, not to the bend or the arena: `_fill()` returns early outside
## `run`, while movement and despawn carry on in every phase so the corridor still drains.
func _check_phase_gate() -> void:
	var rig := _spawner_rig()
	if rig.is_empty():
		return
	var facade: Node3D = rig["game"]
	var spawner: Node = rig["spawner"]
	facade.phase = &"idle"
	spawner.reset(SPAWN_SEED)
	check(spawner.get_active_chunks().is_empty(),
		"the spawner placed %d chunks while the phase was idle" % spawner.get_active_chunks().size())
	check(int(spawner.chunks_spawned) == 0,
		"reset() spawned %d chunks outside the run phase" % int(spawner.chunks_spawned))

	facade.phase = &"run"
	spawner.set_spawning(true)
	var placed: int = int(spawner.chunks_spawned)
	check(placed > 0, "the spawner placed nothing once the run phase opened")
	check(not spawner.get_active_chunks().is_empty(), "the run phase left the corridor empty")

	for phase in IDLE_PHASES:
		facade.phase = phase
		var before := int(spawner.chunks_spawned)
		var tracked: Node3D = _first_chunk(spawner)
		var from_z := tracked.position.z if tracked != null else 0.0
		for i in 120:
			spawner._physics_process(TICK)
		check(int(spawner.chunks_spawned) == before,
			"the spawner placed %d chunks during the %s phase" % [int(spawner.chunks_spawned) - before, phase])
		if tracked != null and is_instance_valid(tracked):
			check(tracked.position.z > from_z + 1.0,
				"chunks stopped moving during the %s phase (z %.1f -> %.1f)" % [phase, from_z, tracked.position.z])
		elif tracked != null:
			check(true, "the tracked chunk despawned during the %s phase, which is the other half of the rule" % phase)

	# Back in the run phase the corridor tops up again, and the drain gate still closes it by hand.
	facade.phase = &"run"
	spawner.set_spawning(true)
	check(int(spawner.chunks_spawned) > placed, "the run phase did not top the corridor back up")
	spawner.set_spawning(false)
	var drained := int(spawner.chunks_spawned)
	for i in 120:
		spawner._physics_process(TICK)
	check(int(spawner.chunks_spawned) == drained,
		"set_spawning(false) still placed %d chunks inside the run phase" % [int(spawner.chunks_spawned) - drained])
	_free_rig(rig)

# --- V12: the boss arena carries no chunk (contract §11.3) ---

## The TurnRig is a static mount, so `World/Chunks` stays outside it and the arena holds only the
## boss, its projectiles and its tools. A chunk parked under the arena would share the rig's
## transform, and every z test in the backend would drift with it.
func _check_arena_is_chunk_free() -> void:
	var packed := load(ARENA_SCENE) as PackedScene
	check(packed != null, "boss_arena.tscn failed to load")
	if packed == null:
		return
	var arena := packed.instantiate() as Node3D
	check(arena != null, "boss_arena.tscn root is not a Node3D")
	if arena == null:
		return
	root.add_child(arena)
	for name in ["Boss", "Projectiles", "Tools"]:
		check(arena.get_node_or_null(NodePath(name)) != null,
			"the boss arena has no %s mount (contract §11.3)" % name)
	for child in _descendants(arena):
		check(not child.has_method("get_hazards"),
			"the boss arena holds a chunk at %s" % arena.get_path_to(child))
		check(not child.is_in_group(&"runner_hazards"),
			"the boss arena ships a live hazard at %s" % arena.get_path_to(child))
		check(not child.is_in_group(&"pickup_slot"),
			"the boss arena ships a chunk power-up slot at %s" % arena.get_path_to(child))
	for name in ["Projectiles", "Tools"]:
		var mount := arena.get_node_or_null(NodePath(name))
		if mount != null:
			check(mount.get_child_count() == 0,
				"the boss arena ships %d node(s) under %s" % [mount.get_child_count(), name])
	arena.free()

	# The other half of the rule, read off runner_game.tscn without instantiating it: Chunks hangs
	# under World, never under the static TurnRig.
	var game_packed := load(GAME_SCENE) as PackedScene
	check(game_packed != null, "runner_game.tscn failed to load")
	if game_packed == null:
		return
	# SceneState reports every path relative to the scene root, as "./World/Chunks".
	var state := game_packed.get_state()
	var paths := PackedStringArray()
	for index in state.get_node_count():
		paths.append(String(state.get_node_path(index)).trim_prefix("./"))
	check(paths.has("World/Chunks"), "runner_game.tscn has no World/Chunks")
	check(paths.has("World/TurnRig/BossArena"), "runner_game.tscn has no World/TurnRig/BossArena")
	for path in paths:
		if not path.begins_with("World/TurnRig"):
			continue
		check(not path.ends_with("/Chunks"), "runner_game.tscn parks %s under the TurnRig" % path)

# --- V13: tool spawns (contract §11.7, systems spec §10.3) ---

## Tools drop on a run row or a jump row, never twice into the same lane, and never into a lane a
## live projectile is still sweeping or a queued telegraph is about to. A full-width attack is
## answered with the body, so it rules out no lane; when every lane the no-repeat rule leaves is
## blocked the draw takes the one whose shot is furthest along.
func _check_tool_placement() -> void:
	var rig := _arena_rig()
	if rig.is_empty():
		return
	var facade: Node3D = rig["game"]
	var arena: Node3D = rig["arena"]
	arena.start(1)
	var heights := [float(config.pickup_height_run), float(config.pickup_height_jump)]
	var previous := -1
	for draw in TOOL_DRAWS:
		var before: int = arena.tool_count()
		arena._spawn_tool()
		var tools: Array[Node] = _live_tools(arena)
		check(tools.size() == before + 1, "draw %d spawned %d tools" % [draw, tools.size() - before])
		if tools.size() != before + 1:
			break
		var pickup := tools[tools.size() - 1] as Node3D
		var lane := _lane_from_x(pickup.position.x)
		check(is_equal_approx(pickup.position.x, _lane_x(lane)),
			"a tool sits at x %.2f, off every lane centre" % pickup.position.x)
		check(lane != previous, "two tools in a row landed in lane %d" % lane)
		previous = lane
		var kind: StringName = pickup.kind
		check(ToolDefs.has_kind(kind), "a tool spawned as the unknown kind %s" % kind)
		var expected := float(config.pickup_height_jump) if ToolDefs.uses_jump_height(kind) \
			else float(config.pickup_height_run)
		check(is_equal_approx(pickup.position.y, expected),
			"the %s tool spawned at y %.2f, expected %.2f" % [kind, pickup.position.y, expected])
		check(heights.any(func(value: float) -> bool: return is_equal_approx(pickup.position.y, value)),
			"the %s tool spawned at y %.2f, outside the contract §11.7 rows" % [kind, pickup.position.y])
		check(is_equal_approx(pickup.position.z, float(config.boss_tool_spawn_z)),
			"the %s tool spawned at z %.2f, expected boss_tool_spawn_z %.2f"
				% [kind, pickup.position.z, float(config.boss_tool_spawn_z)])
		check(pickup.is_in_group(&"runner_tools") and not pickup.is_in_group(&"runner_pickups"),
			"the %s tool is not in runner_tools alone" % kind)

	# Clearance: block one lane with a live projectile mid-corridor and rule the previous lane out by
	# the no-repeat rule, and the one lane left is the only one the draw may return. The same goes
	# for a telegraph that has not fired yet — the lane is spoken for before the shot exists.
	var clearance := absf(float(config.boss_tool_lane_clearance))
	for blocked in LANE_COUNT:
		for repeated in LANE_COUNT:
			if repeated == blocked:
				continue
			var expected := 3 - blocked - repeated
			arena._clear_projectiles()
			arena._pending.clear()
			var shot := _spawn_test_projectile(facade, arena, blocked, MID_CORRIDOR_Z)
			if shot == null:
				return
			arena._last_tool_lane = repeated
			var picked: int = arena._pick_tool_lane()
			check(picked == expected,
				"a tool drew lane %d with lane %d swept and lane %d just used; only lane %d is legal"
					% [picked, blocked, repeated, expected])
			# Past the player by the clearance and the swept lane opens back up: the player can cross
			# in behind the shot, so the rule is a clearance and not a ban.
			shot.position.z = clearance + 1.0
			var reopened: int = arena._pick_tool_lane()
			check(reopened != repeated,
				"a tool drew the lane it had just used (%d)" % reopened)
			arena._clear_projectiles()

			arena._pending.append({"mask": 1 << blocked, "variant": &"orb", "remaining": 0.5})
			arena._last_tool_lane = repeated
			var telegraphed: int = arena._pick_tool_lane()
			check(telegraphed == expected,
				"a tool drew lane %d with lane %d telegraphed and lane %d just used; only lane %d is legal"
					% [telegraphed, blocked, repeated, expected])
			arena._pending.clear()

	# A full-width attack is jumped or rolled rather than dodged sideways, so it rules out no lane at
	# all: both lanes the no-repeat rule leaves are still fair game.
	arena._pending.append({"mask": ALL_LANES, "variant": &"low", "remaining": 0.5})
	arena._last_tool_lane = 1
	var wide_draws := {}
	for draw in TOOL_DRAWS:
		wide_draws[arena._pick_tool_lane()] = true
	check(wide_draws.size() == 2 and not wide_draws.has(1),
		"a full-width telegraph left the draw with lanes %s, expected 0 and 2" % [wide_draws.keys()])
	arena._pending.clear()

	# Every lane swept at once: the draw takes the lane whose shot is furthest along, which is the
	# first lane to free up again.
	var progress := [MID_CORRIDOR_Z - 10.0, MID_CORRIDOR_Z + 8.0, MID_CORRIDOR_Z - 1.0]
	for lane in LANE_COUNT:
		if _spawn_test_projectile(facade, arena, lane, float(progress[lane])) == null:
			return
	arena._last_tool_lane = -1
	var crowded: int = arena._pick_tool_lane()
	check(crowded == 1,
		"with every lane swept the draw took lane %d, expected the furthest-along lane 1" % crowded)
	arena._clear_projectiles()
	_free_rig(rig)

func _spawn_test_projectile(facade: Node3D, arena: Node3D, lane: int, at_z: float) -> Node3D:
	var packed := load(PROJECTILE_SCENE) as PackedScene
	check(packed != null, "projectile.tscn failed to load")
	if packed == null:
		return null
	var shot := packed.instantiate() as Node3D
	check(shot != null, "projectile.tscn root is not a Node3D")
	if shot == null:
		return null
	shot.kind = HazardDefs.PROJECTILE_KIND
	shot.variant = &"orb"
	shot.closing_speed = 0.0
	shot.position = Vector3(_lane_x(lane), 0.0, at_z)
	arena.get_node(^"Projectiles").add_child(shot)
	shot.setup(facade)
	# The validator owns the clock here; a projectile that moved itself would drift off the line.
	shot.set_physics_process(false)
	return shot

func _live_tools(arena: Node3D) -> Array[Node]:
	var live: Array[Node] = []
	for child in arena.get_node(^"Tools").get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			live.append(child)
	return live

## Every authored chunk has to be in the library, or the spawner will never draw it.
func _check_library(paths: Array[String]) -> void:
	var library: Resource = load(LIBRARY_PATH)
	check(library != null, "chunk_library.tres failed to load")
	if library == null:
		return
	var registered := {}
	for scene in library.scenes:
		if scene != null:
			registered[scene.resource_path] = true
	for path in paths:
		check(registered.has(path), "%s is not registered in chunk_library.tres" % path.get_file())

## Systems spec §8: at every difficulty 0..1 in steps of 0.1 at least two chunks are eligible.
func _check_difficulty_coverage(metas: Array[Dictionary]) -> void:
	for step in 11:
		var difficulty := float(step) * 0.1
		var eligible := 0
		for meta in metas:
			if float(meta["min_difficulty"]) <= difficulty + EPS \
					and float(meta["max_difficulty"]) >= difficulty - EPS:
				eligible += 1
		check(eligible >= 2, "difficulty %.1f has only %d eligible chunks, need 2" % [difficulty, eligible])

func _chunk_paths() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(CHUNK_DIR)
	if dir == null:
		return found
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if name.begins_with("chunk_") and name.ends_with(".tscn"):
			found.append(CHUNK_DIR + name)
	found.sort()
	return found

## One chunk, straight or mirrored. Returns its metadata (empty when the scene failed to load).
func _validate(path: String, mirrored: bool) -> Dictionary:
	var packed := load(path) as PackedScene
	check(packed != null, "%s failed to load" % path.get_file())
	if packed == null:
		return {}
	var chunk := packed.instantiate() as Node3D
	check(chunk != null, "%s root is not a Node3D" % path.get_file())
	if chunk == null:
		return {}
	root.add_child(chunk)
	chunk.position = Vector3.ZERO
	# The spawner adds the chunk to the tree and only then calls setup(), so this is the real order.
	var mounted_before_setup := _mounted_visuals(chunk)
	if chunk.has_method("setup"):
		chunk.setup(game, mirrored)
	var tag := path.get_file().trim_suffix(".tscn")
	if mirrored:
		tag += " (mirrored)"
	chunk_log.clear()
	var before := failures
	_check_visual_mount(tag, chunk, mounted_before_setup)
	var infos := _hazard_infos(chunk)
	var meta := {
		"name": tag,
		"length": float(chunk.length),
		"weight": float(chunk.weight),
		"min_difficulty": float(chunk.min_difficulty),
		"max_difficulty": float(chunk.max_difficulty),
		"mirror_x": bool(chunk.mirror_x),
		"hazards": infos.size(),
		"breather": (chunk.tags as PackedStringArray).has(BREATHER_TAG)
	}
	_check_exports(tag, chunk, meta)
	_check_hazards(tag, infos, meta)
	_check_clearance(tag, chunk, infos)
	_check_slices(tag, infos, meta)
	_check_slots(tag, chunk, infos)
	_simulate_all(tag, chunk, infos, meta)
	if failures > before:
		print("RUNNER CHUNKS: log for %s" % tag)
		for line in chunk_log:
			print("  " + line)
	chunk.free()
	return meta

# --- V0: hazards are configured before they mount their visuals ---

## Hazards mounted in a chunk see the RunConfig before `_apply_visual_vars()` runs. The visual is fed
## `lanes_mask`, which is computed from `config.lane_width` and `config.hurtbox_radius`, and
## `chunk.setup()` negates the child x on a mirrored chunk; both only arrive with `setup()`, which the
## spawner calls after `add_child`. A visual mounted straight from `_ready()` would therefore be
## configured from the hazard.gd fallbacks and an un-mirrored lane, so nothing may be mounted before
## `setup()` and exactly one visual may exist after it.
func _check_visual_mount(tag: String, chunk: Node3D, mounted_before_setup: int) -> void:
	check(mounted_before_setup == 0,
		"%s: %d hazard visuals were mounted before chunk.setup() handed out the RunConfig"
			% [tag, mounted_before_setup])
	for hazard in chunk.get_hazards():
		var node := hazard as Node3D
		if node == null:
			continue
		check(node.config != null, "%s: %s never received the RunConfig" % [tag, node.name])
		check(is_instance_valid(node.visual), "%s: %s mounted no visual" % [tag, node.name])
		check(node.get_child_count() == 2,
			"%s: %s holds %d children, expected one collision shape and one visual"
				% [tag, node.name, node.get_child_count()])
		# The lane geometry `_apply_visual_vars()` reads comes from the RunConfig, not the fallbacks.
		check(is_equal_approx(node.lane_x(2), float(config.lane_width)),
			"%s: %s puts lane 2 at %.2f, expected the RunConfig lane width %.2f"
				% [tag, node.name, node.lane_x(2), float(config.lane_width)])

func _mounted_visuals(chunk: Node3D) -> int:
	var mounted := 0
	for hazard in chunk.get_hazards():
		var node := hazard as Node3D
		if node != null and is_instance_valid(node.visual):
			mounted += 1
	return mounted

# --- V1 / V2: hazard geometry against the contract §8 table ---

func _hazard_infos(chunk: Node3D) -> Array[Dictionary]:
	var infos: Array[Dictionary] = []
	for hazard in chunk.get_hazards():
		var node := hazard as Node3D
		if node == null:
			continue
		var def: Dictionary = HazardDefs.get_def(node.kind, node.variant)
		var timed: bool = HazardDefs.is_timed(def)
		if timed:
			# The validator owns the clock: the live state machine would race the simulation.
			node.set_physics_process(false)
		var size: Vector3 = def.get("size", Vector3.ONE)
		infos.append({
			"node": node,
			"kind": node.kind,
			"variant": node.variant,
			"hint": node.dodge_hint,
			"def": def,
			"timed": timed,
			"size": size,
			"y_min": float(def.get("y_min", 0.0)),
			"y_max": float(def.get("y_max", 0.0)),
			"lanes_wide": int(def.get("lanes_wide", 3)),
			"lanes": int(node.lanes_mask()),
			"x": node.global_position.x,
			"front_z": node.global_position.z + size.z * 0.5,
			"back_z": node.global_position.z - size.z * 0.5,
			"jumpable": float(def.get("y_min", 0.0)) <= JUMP_FLOOR and float(def.get("y_max", 0.0)) <= JUMP_TOP,
			"rollable": float(def.get("y_min", 0.0)) >= ROLL_FLOOR,
			"is_pit": StringName(node.kind) == &"deprecated_pit"
		})
	infos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["front_z"]) > float(b["front_z"]))
	return infos

func _check_exports(tag: String, chunk: Node3D, meta: Dictionary) -> void:
	var length := float(meta["length"])
	check(absf(fmod(length, BAND)) < EPS, "%s: length %.1f is not a multiple of 6" % [tag, length])
	check(length >= 18.0, "%s: length %.1f is shorter than three bands" % [tag, length])
	check(float(meta["weight"]) > 0.0, "%s: weight must be positive" % tag)
	var low := float(meta["min_difficulty"])
	var high := float(meta["max_difficulty"])
	check(low >= 0.0 and high <= 1.0 and low <= high,
		"%s: difficulty range %.2f..%.2f is not inside 0..1" % [tag, low, high])
	check(chunk.get_hazards().size() > 0 or String(chunk.name).to_lower().contains("breather"),
		"%s: only breathers may be empty" % tag)
	# The spawner falls back to a `breather`-tagged chunk whenever it may not lay down a hazard —
	# the stage-entrance window most of all (systems spec §10.6) — so the tag is a promise that the
	# chunk carries nothing the player has to dodge. A tagged chunk with a hazard would let one
	# through the stage banner.
	check(not bool(meta["breather"]) or int(meta["hazards"]) == 0,
		"%s: tagged `%s` but carries %d hazard(s); the spawner places breathers where nothing may block"
			% [tag, BREATHER_TAG, int(meta["hazards"])])
	chunk_log.append("len %.0f d %.2f-%.2f w %.1f hazards %d" % [length, low, high, float(meta["weight"]), int(meta["hazards"])])

## V1 lane bounds and declared lanes, V2 depth and dodge_hint against geometry.
func _check_hazards(tag: String, infos: Array, meta: Dictionary) -> void:
	var low := float(meta["min_difficulty"])
	for item in infos:
		var info: Dictionary = item
		var id := "%s/%s@z%.1f" % [info["kind"], info["variant"], float(info["front_z"])]
		chunk_log.append("hazard %s x %.1f lanes %d hint %s" % [id, float(info["x"]), int(info["lanes"]), info["hint"]])
		check(not (info["def"] as Dictionary).is_empty(),
			"%s: %s is not in the contract §8 hazard table" % [tag, id])
		var size: Vector3 = info["size"]
		var half := size.x * 0.5
		# V1: inside the corridor and centred on the lanes its width implies.
		check(absf(float(info["x"])) + half <= 2.8 + EPS,
			"%s: %s reaches x %.2f, outside the 5.6 m corridor" % [tag, id, absf(float(info["x"])) + half])
		var lanes_wide := int(info["lanes_wide"])
		var expected_x := 0.0
		if lanes_wide == 1:
			expected_x = absf(float(info["x"]))
			check(is_equal_approx(expected_x, 0.0) or is_equal_approx(expected_x, 2.0),
				"%s: %s is one lane wide but sits at x %.2f" % [tag, id, float(info["x"])])
		elif lanes_wide == 2:
			check(is_equal_approx(absf(float(info["x"])), 1.0),
				"%s: %s covers two lanes but sits at x %.2f" % [tag, id, float(info["x"])])
		else:
			check(absf(float(info["x"])) < EPS,
				"%s: %s covers the corridor but sits at x %.2f" % [tag, id, float(info["x"])])
		check(_popcount(int(info["lanes"])) == lanes_wide,
			"%s: %s touches %d lanes, the table says %d" % [tag, id, _popcount(int(info["lanes"])), lanes_wide])
		# V2: depth and the dodge hint the geometry actually supports.
		var min_depth := float(config.pit_depth) if bool(info["is_pit"]) else float(config.min_hazard_depth)
		check(size.z >= min_depth - EPS,
			"%s: %s is %.2f m deep, needs %.2f" % [tag, id, size.z, min_depth])
		check(_hint_matches(info), "%s: %s claims %s but its geometry says otherwise" % [tag, id, info["hint"]])
		# V7 tier restrictions.
		if StringName(info["kind"]) == &"comment_flood":
			check(low >= 0.2 - EPS, "%s: comment_flood is not allowed below difficulty 0.2" % tag)
		if bool(info["timed"]):
			check(low >= 0.45 - EPS, "%s: the timed laser is not allowed below difficulty 0.45" % tag)

func _hint_matches(info: Dictionary) -> bool:
	var jumpable := bool(info["jumpable"])
	var rollable := bool(info["rollable"])
	var lanes_wide := int(info["lanes_wide"])
	match StringName(info["hint"]):
		&"JUMP":
			return jumpable and lanes_wide == LANE_COUNT
		&"JUMP_OR_LANE":
			return jumpable and lanes_wide < LANE_COUNT
		&"ROLL":
			return rollable
		&"ROLL_OR_JUMP":
			return rollable and float(info["y_max"]) <= JUMP_TOP + EPS
		&"LANE":
			return not jumpable and not rollable and lanes_wide < LANE_COUNT
		&"TIMED":
			return bool(info["timed"])
	return false

## V3 clear zones and V4 no overlapping hitboxes.
func _check_clearance(tag: String, chunk: Node3D, infos: Array) -> void:
	check(float(chunk.entry_clear()) >= MIN_CLEAR - EPS,
		"%s: only %.2f m clear at the entry, needs 6" % [tag, float(chunk.entry_clear())])
	check(float(chunk.exit_clear()) >= MIN_CLEAR - EPS,
		"%s: only %.2f m clear at the exit, needs 6" % [tag, float(chunk.exit_clear())])
	for i in infos.size():
		for j in range(i + 1, infos.size()):
			var a: Dictionary = infos[i]
			var b: Dictionary = infos[j]
			if _static_box(a).intersects(_static_box(b)):
				check(false, "%s: %s and %s overlap" % [tag, a["kind"], b["kind"]])

## V5 escapes, V6 forced-action spacing, V7 approach cost.
func _check_slices(tag: String, infos: Array, meta: Dictionary) -> void:
	var slices := _slices(infos)
	var cap := _tier_cap(float(meta["max_difficulty"]))
	var v_max := _speed_at(float(meta["max_difficulty"]))
	var spacing := maxf(HEAVY_SPACING, v_max * float(config.gap_safety) * config.t_spacing(float(meta["max_difficulty"])))
	var previous := {}
	for item in slices:
		var slice: Dictionary = item
		var free_lanes := _free_lanes(int(slice["blocked"]))
		# V5: every slice has an answer.
		var escapable: bool = not free_lanes.is_empty() or bool(slice["jumpable"]) \
			or bool(slice["rollable"]) or bool(slice["timed"])
		check(escapable, "%s: the slice at z %.1f has no escape" % [tag, float(slice["front_z"])])
		# V7: the manoeuvre budget for the tier.
		var cost := _approach_cost(slice)
		check(cost <= cap,
			"%s: the slice at z %.1f costs %d moves, the tier allows %d" % [tag, float(slice["front_z"]), cost, cap])
		if not previous.is_empty():
			var gap := float(previous["front_z"]) - float(slice["front_z"])
			# V6: two heavy actions never land closer than the reaction budget allows.
			if bool(previous["heavy"]) and bool(slice["heavy"]):
				check(gap >= spacing - EPS,
					"%s: heavy actions %.1f m apart at z %.1f, need %.1f" % [tag, gap, float(slice["front_z"]), spacing])
			if bool(previous["pit"]):
				check(gap >= PIT_SPACING - EPS,
					"%s: only %.1f m after a pit at z %.1f, need %.0f" % [tag, gap, float(slice["front_z"]), PIT_SPACING])
		previous = slice

## V8 slot placement (systems spec §5.1).
func _check_slots(tag: String, chunk: Node3D, infos: Array) -> void:
	for slot in chunk.get_slots():
		var node := slot as Node3D
		if node == null:
			continue
		var at := node.global_position
		var height: String = chunk.slot_height(node) if chunk.has_method("slot_height") else "run"
		var lane := _lane_from_x(at.x)
		check(absf(at.x - _lane_x(lane)) < EPS, "%s: slot at x %.2f is not on a lane centre" % [tag, at.x])
		var expected_y := float(config.pickup_height_jump) if height == "jump" else float(config.pickup_height_run)
		check(is_equal_approx(at.y, expected_y),
			"%s: the %s slot sits at y %.2f, expected %.2f" % [tag, height, at.y, expected_y])
		if height == "jump":
			# A breather carries its high slot as a standalone reward (catalog chunk 2): there is
			# no hazard to hang it over, and the greedy bot jumps for the pickup itself.
			if infos.is_empty():
				continue
			var nearest := 1000.0
			for item in infos:
				var info: Dictionary = item
				if not HazardDefs.JUMP_HINTS.has(StringName(info["hint"])):
					continue
				nearest = minf(nearest, absf(float(info["front_z"]) - at.z))
			check(nearest <= 0.6 + EPS,
				"%s: the jump slot at z %.1f is %.2f m from the nearest jumped hazard, allow 0.6" % [tag, at.z, nearest])
			continue
		for item in infos:
			var info: Dictionary = item
			if (int(info["lanes"]) & (1 << lane)) == 0:
				continue
			var distance := minf(absf(float(info["front_z"]) - at.z), absf(float(info["back_z"]) - at.z))
			check(distance >= MIN_CLEAR - EPS,
				"%s: the run slot at z %.1f is %.2f m from %s in its lane, need 6" % [tag, at.z, distance, info["kind"]])

# --- V9: the real planner drives a virtual runner through the chunk ---

func _simulate_all(tag: String, chunk: Node3D, infos: Array, meta: Dictionary) -> void:
	if infos.is_empty():
		return
	var speeds := [_speed_at(float(meta["min_difficulty"])), _speed_at(float(meta["max_difficulty"]))]
	var phases := [0.0]
	for item in infos:
		if bool((item as Dictionary)["timed"]):
			phases = TIMED_PHASES
			break
	for policy in [0, 1, 2]:
		for lane in LANE_COUNT:
			for speed in speeds:
				for phase in phases:
					var result := _simulate(chunk, infos, meta, lane, int(policy), float(speed), float(phase))
					check(not bool(result["hit"]),
						"%s: the %s bot was hit from lane %d at %.1f m/s (phase %.2f): %s"
							% [tag, _policy_name(int(policy)), lane, float(speed), float(phase), result["detail"]])

## One pass: the chunk (preceded by a virtual heavy action at the legal seam distance) travels past
## a virtual runner driven by autopilot.gd's planner and the contract §7 jump / roll / lane physics.
func _simulate(chunk: Node3D, infos: Array, meta: Dictionary, entry_lane: int, policy: int,
		v: float, phase: float) -> Dictionary:
	bot.reset()
	bot.set_mode(policy)
	var difficulty := float(meta["max_difficulty"])
	var seam := v * float(config.gap_safety) * config.t_spacing(difficulty)
	# The previous chunk's last forced action, exactly t_spacing before this chunk's first hazard.
	var wall := _make_wall()
	var first_front := float((infos[0] as Dictionary)["front_z"])
	var lead: float = float(bot.scan_range(v)) + 8.0
	var start_z: float = -(lead - first_front)
	chunk.position.z = start_z
	if wall != null:
		wall.position.z = start_z + first_front + seam - 0.6
	var player := _make_player(entry_lane)
	var time := phase
	var resolved := {}
	var slots: Array[Node] = chunk.get_slots()
	var guard := int((float(meta["length"]) + lead + seam + 8.0) / (v * TICK)) + 120
	var detail := ""
	var hit := false
	for step in guard:
		var dz := v * TICK
		chunk.position.z += dz
		if wall != null:
			wall.position.z += dz
		time += TICK
		var hazards: Array[Node] = []
		if wall != null and wall.global_position.z < 1.0:
			hazards.append(wall)
		for item in infos:
			hazards.append((item as Dictionary)["node"])
		_plan(player, hazards, slots, resolved, v, time, policy)
		_step_player(player, hazards, v)
		detail = _collision(player, hazards, time)
		if detail != "":
			hit = true
			break
		if chunk.position.z - float(meta["length"]) > 2.0 \
				and (wall == null or wall.global_position.z > 2.0):
			break
	if wall != null:
		wall.free()
	return {"hit": hit, "detail": detail}

## Ask autopilot.gd what to do and fire it at the same trigger distance the live bot uses.
func _plan(player: Dictionary, hazards: Array, slots: Array, resolved: Dictionary, v: float,
		time: float, policy: int) -> void:
	var slices: Array = bot.slices_for(hazards, v, time)
	var target := {}
	for item in slices:
		var slice: Dictionary = item
		if resolved.has(int(slice["key"])):
			continue
		target = slice
		break
	var plan := {}
	var front_z := 0.0
	var key := 0
	# The trigger distance is read off the slice's own closing speed (systems spec §10.6). Every
	# hazard in a chunk rides the corridor, so it is `v` here; a boss shot is what makes the two
	# differ, and runner_boss_validator.gd is where that case is driven.
	var closing := v
	if target.is_empty():
		if policy != 2:
			return
		var targets: Array = bot.pickup_targets(slots, v)
		plan = bot.plan_pickup(targets, slices, int(player["target_lane"]), v)
		front_z = float(plan.get("front_z", 0.0))
		key = int(plan.get("key", 0))
	else:
		plan = bot.plan_for(target, int(player["target_lane"]))
		front_z = float(target["front_z"])
		key = int(target["key"])
		closing = float(target.get("closing_v", v))
	var action := StringName(plan.get("action", &"none"))
	if action == &"none":
		return
	var trigger := float(bot.plan_trigger_z(closing))
	if action == &"jump":
		trigger = float(bot.jump_trigger_z(closing))
	elif action == &"roll":
		trigger = float(bot.roll_trigger_z(closing))
	if front_z < trigger:
		return
	match action:
		&"jump":
			_request_jump(player)
		&"roll":
			_request_roll(player)
		&"lane":
			var steps := maxi(int(plan.get("steps", 1)), 1)
			var direction := signi(int(plan.get("lane", 1)) - int(player["target_lane"]))
			for i in steps:
				_request_lane(player, direction)
	if key != 0:
		resolved[key] = true

func _make_player(entry_lane: int) -> Dictionary:
	return {
		"lane": entry_lane,
		"target_lane": entry_lane,
		"x": _lane_x(entry_lane),
		"lane_from_x": _lane_x(entry_lane),
		"lane_t": 1.0,
		"queued": 0,
		"y": 0.0,
		"vy": 0.0,
		"airborne": false,
		"jump_buffer": 0.0,
		"rolling": false,
		"roll_remaining": 0.0,
		"roll_cooldown": 0.0,
		"roll_buffer": 0.0
	}

func _request_jump(player: Dictionary) -> void:
	player["jump_buffer"] = float(config.jump_buffer)

func _request_roll(player: Dictionary) -> void:
	if bool(player["airborne"]):
		player["roll_buffer"] = float(config.jump_buffer)
		return
	if bool(player["rolling"]) or float(player["roll_cooldown"]) > 0.0:
		return
	player["rolling"] = true
	player["roll_remaining"] = float(config.roll_duration)

func _request_lane(player: Dictionary, direction: int) -> void:
	if direction == 0:
		return
	if float(player["lane_t"]) < 1.0:
		player["queued"] = direction
		return
	var target := clampi(int(player["lane"]) + direction, 0, LANE_COUNT - 1)
	if target == int(player["lane"]):
		return
	player["target_lane"] = target
	player["lane_from_x"] = float(player["x"])
	player["lane_t"] = 0.0

## Contract §7 physics: gravity 28, jump 9.8, lane tween 0.13 s ease-out, roll 0.70 s.
func _step_player(player: Dictionary, hazards: Array, v: float) -> void:
	# Same order as runner_player._update_jump: the buffer is tested before it is aged, and the
	# launch tick takes a half step of gravity, so the bot flies the player's own arc
	# y(t) = 9.8 t - 14 t^2 (apex 1.715 m, airtime 0.70 s).
	var launched := false
	if float(player["jump_buffer"]) > 0.0 and not bool(player["airborne"]) and not bool(player["rolling"]):
		player["airborne"] = true
		player["vy"] = float(config.jump_velocity) - float(config.gravity) * TICK * 0.5
		player["jump_buffer"] = 0.0
		launched = true
	else:
		player["jump_buffer"] = maxf(float(player["jump_buffer"]) - TICK, 0.0)
	if bool(player["airborne"]):
		if not launched:
			player["vy"] = float(player["vy"]) - float(config.gravity) * TICK
		player["y"] = maxf(float(player["y"]) + float(player["vy"]) * TICK, 0.0)
		if float(player["y"]) <= 0.0:
			player["airborne"] = false
			player["vy"] = 0.0
			if float(player["roll_buffer"]) > 0.0:
				player["roll_buffer"] = 0.0
				_request_roll(player)
	if float(player["roll_buffer"]) > 0.0:
		player["roll_buffer"] = float(player["roll_buffer"]) - TICK
	if bool(player["rolling"]):
		player["roll_remaining"] = float(player["roll_remaining"]) - TICK
		if float(player["roll_remaining"]) <= 0.0:
			# Systems spec §3: stay crouched while something overhead still needs rolling under.
			if _has_standing_clearance(player, hazards, v):
				player["rolling"] = false
				player["roll_cooldown"] = float(config.roll_cooldown)
			else:
				player["roll_remaining"] = TICK
	elif float(player["roll_cooldown"]) > 0.0:
		player["roll_cooldown"] = float(player["roll_cooldown"]) - TICK
	if float(player["lane_t"]) < 1.0:
		player["lane_t"] = minf(float(player["lane_t"]) + TICK / float(config.lane_change_time), 1.0)
		# The player's own ease-out (runner_player._update_lane), not Godot's ease() curve.
		var eased := 1.0 - pow(1.0 - float(player["lane_t"]), 3.0)
		player["x"] = lerpf(float(player["lane_from_x"]), _lane_x(int(player["target_lane"])), eased)
		if float(player["lane_t"]) >= 1.0:
			player["lane"] = int(player["target_lane"])
			player["x"] = _lane_x(int(player["lane"]))
			var queued := int(player["queued"])
			player["queued"] = 0
			if queued != 0:
				_request_lane(player, queued)

func _has_standing_clearance(player: Dictionary, hazards: Array, v: float) -> bool:
	var standing := _player_box(player, true)
	standing.position.z -= v * 2.0 * TICK + 0.3
	standing.size.z += v * 2.0 * TICK + 0.3
	for hazard in hazards:
		var node := hazard as Node3D
		if node == null or not node.is_blocking():
			continue
		if not HazardDefs.ROLL_HINTS.has(StringName(node.dodge_hint)):
			continue
		if standing.intersects(node.get_world_aabb()):
			return false
	return true

## The first hazard the runner is inside this tick, or "" when the pass is still clean.
func _collision(player: Dictionary, hazards: Array, time: float) -> String:
	var body := _player_box(player, not bool(player["rolling"]))
	for hazard in hazards:
		var node := hazard as Node3D
		if node == null or not node.is_blocking():
			continue
		var box := _live_box(node, time)
		if box.size == Vector3.ZERO:
			continue
		if box.intersects(body):
			return "%s at z %.1f (player x %.2f y %.2f%s)" % [node.kind, node.global_position.z,
				float(player["x"]), float(player["y"]), ", rolling" if bool(player["rolling"]) else ""]
	return ""

func _player_box(player: Dictionary, standing: bool) -> AABB:
	var height := float(config.stand_height) if standing else float(config.roll_height)
	var radius := float(config.hurtbox_radius)
	return AABB(
		Vector3(float(player["x"]) - radius + EPS, float(player["y"]) + EPS, -radius + EPS),
		Vector3(radius * 2.0 - EPS * 2.0, height - EPS * 2.0, radius * 2.0 - EPS * 2.0))

## The box a hazard occupies right now. The timed laser follows the same cycle the bot predicts,
## so the simulation and the plan share one clock.
func _live_box(node: Node3D, time: float) -> AABB:
	var def: Dictionary = HazardDefs.get_def(node.kind, node.variant)
	var size: Vector3 = def.get("size", Vector3.ONE)
	var y_min := float(def.get("y_min", 0.0))
	var y_max := float(def.get("y_max", 0.0))
	if HazardDefs.is_timed(def):
		var state: StringName = bot.timed_state_at(time)
		var bounds: Dictionary = def.get("state_bounds", {})
		if not bounds.has(state):
			return AABB()
		var row: Vector2 = bounds[state]
		y_min = row.x
		y_max = row.y
	var at := node.global_position
	return AABB(
		Vector3(at.x - size.x * 0.5, y_min, at.z - size.z * 0.5),
		Vector3(size.x, maxf(y_max - y_min, 0.01), size.z))

## A full-width low wall: the virtual heavy action the runner is still recovering from.
## Returns null when hazard.tscn cannot be loaded or does not instantiate a Node3D; callers run
## the pass without the seam wall rather than dereferencing null.
func _make_wall() -> Node3D:
	if wall_scene == null and not wall_scene_broken:
		wall_scene = load("res://scenes/runner/hazards/hazard.tscn") as PackedScene
		if wall_scene == null:
			wall_scene_broken = true
			check(false, "hazards/hazard.tscn did not load as a PackedScene: "
				+ "the V9 simulation cannot place the virtual seam wall")
	if wall_scene == null:
		return null
	var instance := wall_scene.instantiate()
	var wall := instance as Node3D
	if wall == null:
		wall_scene_broken = true
		wall_scene = null
		if instance != null:
			instance.free()
		check(false, "hazards/hazard.tscn did not instantiate a Node3D: "
			+ "the V9 simulation cannot place the virtual seam wall")
		return null
	wall.kind = &"pr_backlog_low"
	wall.variant = &""
	root.add_child(wall)
	if wall.has_method("setup"):
		wall.setup(game)
	return wall

# --- rigs for the placement checks ---

## A facade inside the tree with just the nodes the spawner and the arena reach for. The script is
## set *after* add_child on purpose: runner_game.gd's _ready() would go looking for the scene's own
## children, and skipping it leaves get_tree() answering, which is all these checks need.
## A non-null `stage_manager` is what arms the phase gate — a hand-built v1 rig has no phases.
func _tree_facade() -> Node3D:
	var facade := Node3D.new()
	root.add_child(facade)
	facade.set_script(load("res://scenes/runner/runner_game.gd") as GDScript)
	# Straight after set_script rather than before add_child: the script is what carries the
	# property, and skipping _ready() is also what keeps `autostart` from ever opening a run.
	facade.leaderboard_path = SCRATCH_BOARD
	facade.config = config
	facade.state = &"running"
	facade.speed = float(config.base_speed)
	facade.difficulty = 0.0
	facade.phase = &"idle"
	var world := Node3D.new()
	world.name = "World"
	facade.add_child(world)
	var chunks := Node3D.new()
	chunks.name = "Chunks"
	world.add_child(chunks)
	facade.chunks = chunks
	facade.world = world
	facade.stage_manager = Node.new()
	facade.add_child(facade.stage_manager)
	return facade

## The facade plus a live chunk_spawner.gd. The spawner never ticks itself: the engine runs no
## frames inside run(), and every advance below is a hand-driven _physics_process.
func _spawner_rig() -> Dictionary:
	var facade := _tree_facade()
	var spawner_script := load("res://scenes/runner/systems/chunk_spawner.gd") as GDScript
	check(spawner_script != null, "chunk_spawner.gd could not be loaded")
	if spawner_script == null:
		facade.free()
		return {}
	var spawner: Node = spawner_script.new()
	facade.add_child(spawner)
	spawner.set_physics_process(false)
	spawner.setup(facade)
	facade.spawner = spawner
	return {"game": facade, "spawner": spawner}

## The facade plus a real boss_arena.tscn, mounted where runner_game.tscn mounts it so the tools it
## spawns resolve their encounter through the contract §11.3 path.
func _arena_rig() -> Dictionary:
	var facade := _tree_facade()
	var packed := load(ARENA_SCENE) as PackedScene
	check(packed != null, "boss_arena.tscn failed to load for the tool checks")
	if packed == null:
		facade.free()
		return {}
	var rig := Node3D.new()
	rig.name = "TurnRig"
	facade.get_node(^"World").add_child(rig)
	var arena := packed.instantiate() as Node3D
	check(arena != null, "boss_arena.tscn root is not a Node3D")
	if arena == null:
		facade.free()
		return {}
	arena.name = "BossArena"
	rig.add_child(arena)
	facade.boss_encounter = arena
	arena.setup(facade)
	return {"game": facade, "arena": arena}

func _free_rig(rig: Dictionary) -> void:
	var facade: Node3D = rig.get("game", null)
	if facade != null and is_instance_valid(facade):
		root.remove_child(facade)
		facade.free()

func _first_chunk(spawner: Node) -> Node3D:
	for chunk in spawner.get_active_chunks():
		if is_instance_valid(chunk):
			return chunk
	return null

func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found

# --- helpers ---

func _static_box(info: Dictionary) -> AABB:
	var size: Vector3 = info["size"]
	return AABB(
		Vector3(float(info["x"]) - size.x * 0.5 + EPS, float(info["y_min"]) + EPS, float(info["back_z"]) + EPS),
		Vector3(size.x - EPS * 2.0, maxf(float(info["y_max"]) - float(info["y_min"]), 0.01) - EPS * 2.0,
			size.z - EPS * 2.0))

## Hazards whose z ranges overlap within 0.8 m answer to one manoeuvre (systems spec §8).
func _slices(infos: Array) -> Array[Dictionary]:
	var slices: Array[Dictionary] = []
	for item in infos:
		var info: Dictionary = item
		if not slices.is_empty():
			var last: Dictionary = slices[slices.size() - 1]
			if float(info["front_z"]) >= float(last["back_z"]) - 0.8:
				last["back_z"] = minf(float(last["back_z"]), float(info["back_z"]))
				last["blocked"] = int(last["blocked"]) | int(info["lanes"])
				last["jumpable"] = bool(last["jumpable"]) and bool(info["jumpable"])
				last["rollable"] = bool(last["rollable"]) and bool(info["rollable"])
				last["timed"] = bool(last["timed"]) or bool(info["timed"])
				last["pit"] = bool(last["pit"]) or bool(info["is_pit"])
				continue
		slices.append({
			"front_z": info["front_z"],
			"back_z": info["back_z"],
			"blocked": info["lanes"],
			"jumpable": info["jumpable"],
			"rollable": info["rollable"],
			"timed": info["timed"],
			"pit": info["is_pit"]
		})
	for item in slices:
		var slice: Dictionary = item
		slice["heavy"] = _free_lanes(int(slice["blocked"])).is_empty()
	return slices

func _free_lanes(blocked: int) -> Array[int]:
	var free: Array[int] = []
	for lane in LANE_COUNT:
		if (blocked & (1 << lane)) == 0:
			free.append(lane)
	return free

## Lane changes, or one move for a jump / roll; the worst entry lane decides (systems spec §5.1).
func _approach_cost(slice: Dictionary) -> int:
	var worst := 0
	for lane in LANE_COUNT:
		if (int(slice["blocked"]) & (1 << lane)) == 0:
			continue
		var best := 99
		for free in _free_lanes(int(slice["blocked"])):
			best = mini(best, absi(free - lane))
		if bool(slice["jumpable"]) or bool(slice["rollable"]) or bool(slice["timed"]):
			best = mini(best, 1)
		worst = maxi(worst, best)
	return worst

func _tier_cap(max_difficulty: float) -> int:
	if max_difficulty <= 0.3 + EPS:
		return 1
	if max_difficulty <= 0.6 + EPS:
		return 2
	return 3

## Systems spec §1.2 speed curve, without the tail: the fastest a chunk of this tier ever moves.
func _speed_at(difficulty: float) -> float:
	var d := clampf(difficulty, 0.0, 1.0)
	return lerpf(float(config.base_speed), float(config.max_speed), smoothstep(0.0, 1.0, d))

func _lane_x(lane: int) -> float:
	return (float(clampi(lane, 0, LANE_COUNT - 1)) - 1.0) * float(config.lane_width)

func _lane_from_x(x: float) -> int:
	return clampi(int(roundf(x / float(config.lane_width))) + 1, 0, LANE_COUNT - 1)

func _popcount(mask: int) -> int:
	var count := 0
	for lane in LANE_COUNT:
		if (mask & (1 << lane)) != 0:
			count += 1
	return count

func _policy_name(policy: int) -> String:
	match policy:
		0:
			return "PREFER_LANE"
		1:
			return "PREFER_JUMP"
		2:
			return "GREEDY_PICKUP"
	return "UNKNOWN"

func _report() -> void:
	for node in junk:
		if is_instance_valid(node):
			node.free()
	junk.clear()
	wall_scene = null
	print("RUNNER CHUNKS: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures / ", checks, " checks)")
	quit(failures)
