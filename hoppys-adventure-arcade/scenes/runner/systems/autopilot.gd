extends Node
## Fair / reckless bot used by tests and the F7 debug toggle (systems spec §8, Autopilot).
## The planning half (slices_for / plan_for / the trigger distances) is pure: it takes hazard nodes
## and a lane and returns an action, so the chunk validator can simulate the same bot offline.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")

enum Mode { PREFER_LANE, PREFER_JUMP, GREEDY_PICKUP }

const ACTION_NONE: StringName = &"none"
const ACTION_JUMP: StringName = &"jump"
const ACTION_ROLL: StringName = &"roll"
const ACTION_LANE: StringName = &"lane"
const HINT_TIMED: StringName = &"TIMED"
const LANE_COUNT := 3
## Hazards whose z ranges are within this of each other are one slice (systems spec §8).
const SLICE_TOLERANCE := 0.8
## Half the player's footprint along z (contract §7 capsule radius 0.4).
const PLAYER_HALF_DEPTH := 0.4
## Sampling step for the timed-laser pass window, in seconds.
const TIMED_SAMPLE_STEP := 0.04
## A pickup is worth a jump only when it hangs above running height.
const HIGH_PICKUP_Y := 1.6

var game: RunnerGame
var config: RunConfig
var enabled := false
var mode := Mode.PREFER_LANE
## Reckless mode: deliberately ignore this many upcoming slices.
var reckless_slices := 0

## Slice key -> true for slices already acted on, ignored, or merely seen. Rebuilt every tick from
## the slices in range, so a freed hazard never leaks a key.
var _done := {}
var _ignored := {}
var _seen := {}
## Slice key -> the lane plan still being carried out, so a multi-step lane change keeps its goal
## instead of being re-planned from the lane it is only passing through. Pruned with the key sets.
var _pending := {}
## Hazard instance id -> the key of the slice it belongs to, carried across ticks so a merged slice
## keeps one key for its whole life. Without it the key would follow the membership, and an
## already-answered slice would come back under a new key the moment that hazard is cleared,
## consumed, or falls out of the scan range.
var _slice_keys := {}

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	reset()

## `new_config` lets a test swap in a duplicated RunConfig; the shared .tres is never mutated.
## The bot never switches itself on: only set_autopilot() / F7 / a test does that.
func reset(new_config: RunConfig = null) -> void:
	if new_config != null:
		config = new_config
	enabled = false
	mode = Mode.PREFER_LANE
	reckless_slices = 0
	_done = {}
	_ignored = {}
	_seen = {}
	_pending = {}
	_slice_keys = {}

func set_enabled(on: bool) -> void:
	enabled = on

func set_mode(value: int) -> void:
	mode = value as Mode

func set_reckless(slices: int) -> void:
	reckless_slices = maxi(slices, 0)

## Distance ahead the bot commits to a plan, in metres.
func lookahead() -> float:
	if config == null or game == null:
		return 0.0
	return float(game.speed) * float(config.autopilot_plan_lead) + 0.4

## Distance ahead the bot looks at all. Wider than the plan lead so lane moves can be prepared and
## greedy pickups can be checked against the hazards between here and there.
func scan_range(v: float) -> float:
	var lead := float(config.autopilot_plan_lead) if config != null else 0.6
	return maxf(v * (lead + 0.9) + 0.4, 24.0)

## z at which the plan is committed / the jump starts / the roll starts (systems spec §8).
func plan_trigger_z(v: float) -> float:
	var lead := float(config.autopilot_plan_lead) if config != null else 0.6
	return -(v * lead + 0.4)

func jump_trigger_z(v: float) -> float:
	var lead := float(config.autopilot_jump_lead) if config != null else 0.22
	return -(v * lead + 0.4)

## Seconds one lane transition takes (contract §7), the cost of every step of a lane plan.
func lane_change_time() -> float:
	return float(config.lane_change_time) if config != null else 0.13

func roll_trigger_z(v: float) -> float:
	var lead := float(config.autopilot_roll_lead) if config != null else 0.15
	return -(v * lead + 0.4)

## Group the blocking hazards ahead into slices, nearest first. `now` is the run clock, used to
## predict the timed laser across each hazard's pass window.
## Slice: {key, front_z, back_z, blocked (lane bitmask), jumpable, rollable, hazards}.
func slices_for(hazards: Array, v: float, now: float) -> Array[Dictionary]:
	var speed := maxf(v, 0.1)
	var range_z := -scan_range(speed)
	var entries: Array[Dictionary] = []
	for hazard in hazards:
		var entry := _hazard_entry(hazard, speed, now)
		if entry.is_empty():
			continue
		if float(entry["front_z"]) <= range_z or float(entry["front_z"]) > 0.5:
			continue
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["front_z"]) > float(b["front_z"]))
	var slices: Array[Dictionary] = []
	# Member instance ids per slice, head first, in the same order as `slices`.
	var members: Array[Array] = []
	for entry in entries:
		var merged := false
		if not slices.is_empty():
			var last: Dictionary = slices[slices.size() - 1]
			# Expanded z ranges overlap (systems spec §8): one manoeuvre answers both hazards.
			if float(entry["front_z"]) >= float(last["back_z"]) - SLICE_TOLERANCE:
				last["back_z"] = minf(float(last["back_z"]), float(entry["back_z"]))
				last["blocked"] = int(last["blocked"]) | int(entry["blocked"])
				last["jumpable"] = bool(last["jumpable"]) and bool(entry["jumpable"])
				last["rollable"] = bool(last["rollable"]) and bool(entry["rollable"])
				(last["hazards"] as Array).append(entry["hazard"])
				(members[members.size() - 1] as Array).append(int(entry["key"]))
				merged = true
		if merged:
			continue
		slices.append({
			"key": entry["key"],
			"front_z": entry["front_z"],
			"back_z": entry["back_z"],
			"blocked": entry["blocked"],
			"jumpable": entry["jumpable"],
			"rollable": entry["rollable"],
			"hazards": [entry["hazard"]]
		})
		members.append([int(entry["key"])])
	_stabilise_keys(slices, members)
	return slices

## Give every slice the one key it keeps for its whole life. A brand new slice is keyed by its head
## (nearest) hazard, since `entries` is sorted nearest-first; a slice that already existed keeps the
## key any of its members carried last tick, so losing the hazard the key came from does not turn an
## answered slice into a fresh one and earn it a second manoeuvre.
func _stabilise_keys(slices: Array[Dictionary], members: Array[Array]) -> void:
	var next_keys := {}
	var taken := {}
	for index in slices.size():
		var slice: Dictionary = slices[index]
		var ids: Array = members[index]
		var key := _slice_key(ids, taken)
		slice["key"] = key
		taken[key] = true
		for id: int in ids:
			next_keys[id] = key
	_slice_keys = next_keys

## The key one slice inherits: the key a member already carried, else the head hazard's own id.
## `taken` keeps a slice that has split in two from handing the same key to both halves.
func _slice_key(ids: Array, taken: Dictionary) -> int:
	for id: int in ids:
		if not _slice_keys.has(id):
			continue
		var previous := int(_slice_keys[id])
		if not taken.has(previous):
			return previous
	for id: int in ids:
		if not taken.has(id):
			return id
	return int(ids[0])

## The action that answers one slice from `lane`: {action, lane, steps}.
func plan_for(slice: Dictionary, lane: int) -> Dictionary:
	var blocked := int(slice.get("blocked", 0))
	var jumpable := bool(slice.get("jumpable", false))
	var rollable := bool(slice.get("rollable", false))
	if not _lane_blocked(blocked, lane):
		return {"action": ACTION_NONE, "lane": lane, "steps": 0}
	var target := _nearest_free_lane(blocked, lane)
	if mode == Mode.PREFER_JUMP:
		# Answer with the body first: jump what can be jumped, roll what must be rolled.
		if jumpable:
			return {"action": ACTION_JUMP, "lane": lane, "steps": 0}
		if rollable:
			return {"action": ACTION_ROLL, "lane": lane, "steps": 0}
		if target >= 0:
			return {"action": ACTION_LANE, "lane": target, "steps": absi(target - lane)}
		return {"action": ACTION_NONE, "lane": lane, "steps": 0}
	# PREFER_LANE and GREEDY_PICKUP: step aside when a lane is free, otherwise act by hint.
	if target >= 0:
		return {"action": ACTION_LANE, "lane": target, "steps": absi(target - lane)}
	if jumpable:
		return {"action": ACTION_JUMP, "lane": lane, "steps": 0}
	if rollable:
		return {"action": ACTION_ROLL, "lane": lane, "steps": 0}
	return {"action": ACTION_NONE, "lane": lane, "steps": 0}

## Pickup targets ahead of the player, nearest first: {lane, front_z, high}.
## Accepts live power-ups (group runner_pickups) or the chunks' PowerUpSlot markers.
func pickup_targets(nodes: Array, v: float) -> Array[Dictionary]:
	var range_z := -scan_range(maxf(v, 0.1))
	var targets: Array[Dictionary] = []
	for node in nodes:
		var pickup := node as Node3D
		if pickup == null or not is_instance_valid(pickup):
			continue
		var at := pickup.global_position
		if at.z <= range_z or at.z > 0.5:
			continue
		targets.append({
			"key": pickup.get_instance_id(),
			"lane": lane_from_x(at.x),
			"front_z": at.z,
			"high": at.y >= HIGH_PICKUP_Y
		})
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["front_z"]) > float(b["front_z"]))
	return targets

## GREEDY_PICKUP detour, only taken when no hazard needs answering first.
func plan_pickup(targets: Array, slices: Array, lane: int, v: float) -> Dictionary:
	var idle := {"action": ACTION_NONE, "lane": lane, "steps": 0}
	for item in targets:
		var target: Dictionary = item
		var front_z := float(target["front_z"])
		var target_lane := int(target["lane"])
		if _lane_blocked_before(slices, target_lane, front_z):
			continue
		var key: Variant = target.get("key", 0)
		if bool(target["high"]):
			# Only leave the ground when nothing else is close enough to land into.
			if _slice_within(slices, v * 0.8):
				continue
			# A jump only reaches a high pickup hanging over the lane the player is already in:
			# take the lane first and jump on a later tick, once it is the lane underneath.
			if target_lane != lane:
				var steps := absi(target_lane - lane)
				# Only while the detour still fits in front of it: one lane tween per step and
				# then a jump lead. A pickup that is already level with the player cannot be
				# collected any more, and diving at it lands in whatever it is hanging over.
				if front_z > jump_trigger_z(v) - v * lane_change_time() * float(steps):
					continue
				return {
					"action": ACTION_LANE,
					"lane": target_lane,
					"steps": steps,
					"front_z": front_z,
					"key": key
				}
			return {"action": ACTION_JUMP, "lane": lane, "steps": 0, "front_z": front_z, "key": key}
		if target_lane != lane:
			return {
				"action": ACTION_LANE,
				"lane": target_lane,
				"steps": absi(target_lane - lane),
				"front_z": front_z,
				"key": key
			}
		return idle
	return idle

## Lane index 0/1/2 nearest to a world x.
func lane_from_x(x: float) -> int:
	var width := float(config.lane_width) if config != null else 2.0
	if width <= 0.0:
		return 1
	return clampi(int(roundf(x / width)) + 1, 0, LANE_COUNT - 1)

## Timed laser state at an absolute run time, derived from the contract §8 cycle so the bot and the
## hazard agree: ground 1.2 s -> off 0.3 s -> high 1.2 s -> off 0.3 s.
static func timed_state_at(time: float) -> StringName:
	var def := HazardDefs.get_def(&"laser_grid", &"timed")
	var period := float(def.get("period", 3.0))
	if period <= 0.0:
		return &"off"
	var on_seconds := float(def.get("on_seconds", 1.2))
	var off_seconds := float(def.get("off_seconds", 0.3))
	var states: Array = def.get("states", [&"ground", &"off", &"high", &"off"])
	var phase := fposmod(time, period)
	var cursor := 0.0
	for state in states:
		var span := off_seconds if StringName(state) == &"off" else on_seconds
		if phase < cursor + span:
			return StringName(state)
		cursor += span
	return &"off"

func _physics_process(_delta: float) -> void:
	if not enabled or game == null or game.state != &"running":
		return
	var player: Node = game.player
	if player == null or not is_instance_valid(player):
		return
	var tree := get_tree()
	if tree == null:
		return
	var v := maxf(float(game.speed), 0.1)
	var slices := slices_for(tree.get_nodes_in_group(&"runner_hazards"), v, float(game.elapsed))
	var targets: Array[Dictionary] = []
	if mode == Mode.GREEDY_PICKUP:
		targets = pickup_targets(tree.get_nodes_in_group(&"runner_pickups"), v)
	_prune(slices, targets)
	var lane := _player_lane(player)
	var slice := _next_slice(slices)
	if slice.is_empty():
		if mode == Mode.GREEDY_PICKUP:
			var greed := plan_pickup(targets, slices, lane, v)
			_execute(greed, float(greed.get("front_z", 0.0)), v, player,
				StringName(str(greed.get("key", ""))))
		return
	var key := StringName(str(slice["key"]))
	var plan := _pending_plan(key, slice, lane)
	_execute(plan, float(slice["front_z"]), v, player, key)

## The plan for this slice: a lane change already under way is carried on rather than re-planned
## from the lane the player is only passing through (which would read as "this lane is free" and
## abandon the move half-way). The plan is dropped as soon as the slice blocks the lane it aims at.
func _pending_plan(key: StringName, slice: Dictionary, lane: int) -> Dictionary:
	if not _pending.has(key):
		return plan_for(slice, lane)
	var plan: Dictionary = _pending[key]
	var goal := clampi(int(plan.get("lane", lane)), 0, LANE_COUNT - 1)
	if goal == lane or not _lane_blocked(int(slice.get("blocked", 0)), goal):
		return plan
	_pending.erase(key)
	return plan_for(slice, lane)

## Run the plan once its trigger distance is reached (systems spec §8).
func _execute(plan: Dictionary, front_z: float, v: float, player: Node, key: StringName) -> void:
	var action := StringName(plan.get("action", ACTION_NONE))
	if action == ACTION_NONE:
		return
	var trigger := plan_trigger_z(v)
	if action == ACTION_JUMP:
		trigger = jump_trigger_z(v)
	elif action == ACTION_ROLL:
		trigger = roll_trigger_z(v)
	if front_z < trigger:
		return
	match action:
		ACTION_JUMP:
			if player.has_method("request_jump"):
				player.request_jump()
		ACTION_ROLL:
			if player.has_method("request_roll"):
				player.request_roll()
		ACTION_LANE:
			# A lane plan is answered by arrival, not by one request: a two-step move needs a
			# second transition, and the player only accepts one queued change at a time, so the
			# plan stays pending and is re-issued across ticks until the target lane is reached.
			var goal := clampi(int(plan.get("lane", 1)), 0, LANE_COUNT - 1)
			var direction := signi(goal - _player_lane(player))
			if direction != 0 and player.has_method("request_lane"):
				if not _lane_change_queued(player):
					player.request_lane(direction)
				if _player_lane(player) != goal:
					if key != &"":
						_pending[key] = plan
					return
			_pending.erase(key)
	if key != &"":
		_done[key] = true

## True when the player already has a change queued behind a running tween: it only keeps one, so a
## further request_lane would overwrite it and every later tick would repeat the same request.
func _lane_change_queued(player: Node) -> bool:
	if &"queued_lane_dir" in player:
		return int(player.get(&"queued_lane_dir")) != 0
	# Unknown player model: only ask while nothing is moving.
	if &"lane_t" in player:
		return float(player.get(&"lane_t")) < 1.0
	return false

## One entry per blocking hazard, or {} when it cannot hurt the player on this pass.
func _hazard_entry(hazard: Variant, v: float, now: float) -> Dictionary:
	var node := hazard as Node3D
	if node == null or not is_instance_valid(node):
		return {}
	if not node.has_method("is_blocking") or not node.is_blocking():
		return {}
	if not node.has_method("get_world_aabb"):
		return {}
	var bounds: AABB = node.get_world_aabb()
	var hint: StringName = node.get(&"dodge_hint") if &"dodge_hint" in node else &""
	if hint == HINT_TIMED:
		hint = _timed_hint(bounds, v, now)
		if hint == &"":
			return {}
	var blocked := 0
	for lane in LANE_COUNT:
		if node.has_method("occupies_lane"):
			if node.occupies_lane(lane):
				blocked |= 1 << lane
		elif absf(_lane_x(lane) - bounds.get_center().x) < bounds.size.x * 0.5 + 0.4:
			blocked |= 1 << lane
	return {
		"key": node.get_instance_id(),
		"front_z": bounds.end.z,
		"back_z": bounds.position.z,
		"blocked": blocked,
		"jumpable": HazardDefs.JUMP_HINTS.has(hint),
		"rollable": HazardDefs.ROLL_HINTS.has(hint),
		"hazard": node
	}

## The dodge hint a timed laser demands across the window the player is inside it: ground beam
## means jump, high beam means roll, off means it is not there at all.
func _timed_hint(bounds: AABB, v: float, now: float) -> StringName:
	var speed := maxf(v, 0.1)
	var enter := (-PLAYER_HALF_DEPTH - bounds.end.z) / speed
	var exit := (PLAYER_HALF_DEPTH - bounds.position.z) / speed
	enter = maxf(enter, 0.0)
	exit = maxf(exit, enter)
	var t := enter
	var saw_high := false
	while t <= exit + 0.0001:
		var state := timed_state_at(now + t)
		if state == &"ground":
			return &"JUMP"
		if state == &"high":
			saw_high = true
		t += TIMED_SAMPLE_STEP
	return &"ROLL" if saw_high else &""

## The nearest slice the bot has not already answered or deliberately ignored. Newly seen slices
## are burned here while reckless_slices is positive.
func _next_slice(slices: Array) -> Dictionary:
	for item in slices:
		var slice: Dictionary = item
		var key := StringName(str(slice["key"]))
		if not _seen.has(key):
			_seen[key] = true
			if reckless_slices > 0:
				reckless_slices -= 1
				_ignored[key] = true
		if _ignored.has(key) or _done.has(key):
			continue
		return slice
	return {}

## Keep only the keys still in range, so instance ids can never pile up across a long run.
func _prune(slices: Array, targets: Array) -> void:
	var live := {}
	for item in slices:
		live[StringName(str((item as Dictionary)["key"]))] = true
	for item in targets:
		live[StringName(str((item as Dictionary).get("key", "")))] = true
	_done = _intersect(_done, live)
	_ignored = _intersect(_ignored, live)
	_seen = _intersect(_seen, live)
	_pending = _intersect_plans(_pending, live)

func _intersect(source: Dictionary, live: Dictionary) -> Dictionary:
	var kept := {}
	for key in source:
		if live.has(key):
			kept[key] = true
	return kept

## _intersect for the pending plans, which carry the plan itself rather than a flag.
func _intersect_plans(source: Dictionary, live: Dictionary) -> Dictionary:
	var kept := {}
	for key in source:
		if live.has(key):
			kept[key] = source[key]
	return kept

func _player_lane(player: Node) -> int:
	if player == null or not is_instance_valid(player):
		return 1
	if &"target_lane" in player:
		return clampi(int(player.get(&"target_lane")), 0, LANE_COUNT - 1)
	if player is Node3D:
		return lane_from_x((player as Node3D).global_position.x)
	return 1

func _lane_x(lane: int) -> float:
	var width := float(config.lane_width) if config != null else 2.0
	return (float(lane) - 1.0) * width

func _lane_blocked(blocked: int, lane: int) -> bool:
	return (blocked & (1 << lane)) != 0

## The free lane closest to `lane`, or -1 when the slice blocks all three.
func _nearest_free_lane(blocked: int, lane: int) -> int:
	for distance: int in [1, 2]:
		for direction: int in [-1, 1]:
			var candidate := lane + direction * distance
			if candidate < 0 or candidate >= LANE_COUNT:
				continue
			if not _lane_blocked(blocked, candidate):
				return candidate
	return -1

## True when something between here and `front_z` blocks `lane`, so the detour is not worth it.
func _lane_blocked_before(slices: Array, lane: int, front_z: float) -> bool:
	for item in slices:
		var slice: Dictionary = item
		if float(slice["front_z"]) < front_z - 0.01:
			continue
		if _lane_blocked(int(slice["blocked"]), lane):
			return true
	return false

func _slice_within(slices: Array, distance: float) -> bool:
	for item in slices:
		if float((item as Dictionary)["front_z"]) >= -absf(distance):
			return true
	return false
