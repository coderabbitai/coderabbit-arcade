extends Node
## Fair / reckless bot used by tests and the F7 debug toggle (systems spec §8, §10.6, Autopilot).
## The planning half (slices_for / plan_for / attack_slice / the trigger distances and times) is
## pure: it takes hazard nodes, a lane mask or a telegraph and returns an action, so the chunk
## validator and the boss validator can simulate the same bot offline.

const RunnerGame = preload("res://scenes/runner/runner_game.gd")
const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")
## Only for the projectile speed of the fight in progress: boss_attack_telegraph carries the lane
## mask, the variant and the telegraph, but not how fast the shot will close (contract §11.4).
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
## Contract 2.4: the attack / shot motion API every boss plan is made against, so a split, a sweep,
## a shifting gap or a falling slab is answered where it will be, not where it was telegraphed.
const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")

enum Mode { PREFER_LANE, PREFER_JUMP, GREEDY_PICKUP }

const ACTION_NONE: StringName = &"none"
const ACTION_JUMP: StringName = &"jump"
const ACTION_ROLL: StringName = &"roll"
const ACTION_LANE: StringName = &"lane"
const HINT_TIMED: StringName = &"TIMED"
const LANE_COUNT := 3
## Every lane at once: a full-width attack is answered with the body, never with a lane change.
const LANE_ALL := 0b111
## Hazards whose z ranges are within this of each other are one slice (systems spec §8).
const SLICE_TOLERANCE := 0.8
## Half the player's footprint along z (contract §7 capsule radius 0.4).
const PLAYER_HALF_DEPTH := 0.4
## Sampling step for the timed-laser pass window, in seconds.
const TIMED_SAMPLE_STEP := 0.04
## A pickup is worth a jump only when it hangs above running height.
const HIGH_PICKUP_Y := 1.6
## Contract §11.10 fallbacks, used only when no config has been supplied yet.
const DEFAULT_BOSS_Z := -14.0
const DEFAULT_TELEGRAPH_LEAD := 0.12
const DEFAULT_TOOL_GREED := 1.0
const DEFAULT_JUMP_PEAK_TIME := 0.35
const DEFAULT_ROLL_DURATION := 0.70
## Contract §11.1 phase this bot plans telegraphs in.
const PHASE_BOSS: StringName = &"boss"
## Seconds an answered telegraph is kept after its projectile lands, so a shot that is still in
## flight is never re-planned as a brand new attack.
const ATTACK_GRACE := 0.5
## Slack on "this telegraph has run out", in seconds: the fire signal and the last countdown tick
## land in the same frame, so the two clocks can differ by one physics step.
const FIRE_MATCH_SLACK := 1.0 / 30.0
## Attacks whose pass windows come within this many seconds of each other are planned as one group
## (contract 2.4): a staggered volley or a slow wall overlapping a fast shot needs one answer that
## survives all of them, not a lane change into the next one.
const GROUP_WINDOW := 0.6
## Safety margin on the body-action windows, in seconds.
const BODY_MARGIN := 0.02

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
## Telegraphed boss attacks still worth planning, oldest first (systems spec §10.6):
## {key, mask, variant, telegraph, closing_v, arrival, exit, jumpable, rollable, clear_height,
## committed, telegraph_mask, attack, elapsed}. `mask` is what the attack blocks while it passes
## the player (both candidates while a flaky one is uncommitted); `arrival` / `exit` bound that pass
## in seconds after the telegraph. `key` is a serial rather than an instance id, because a telegraph
## has no node until it fires; it shares the `_done` / `_pending` bookkeeping with the slice keys,
## which is what lets one plan span several ticks.
var _attacks: Array[Dictionary] = []
var _attack_serial := 0
## boss_attack_planned details waiting for the boss_attack_telegraph they announce (contract 2.4).
var _planned: Array[Dictionary] = []

func setup(runner: RunnerGame) -> void:
	game = runner
	config = runner.config
	_connect(runner)
	reset()

## The boss branch plans from the facade's own signals, so the bot hears a telegraph on the tick it
## goes out. Every connection is guarded: a facade that predates v2 simply has no boss to plan for.
func _connect(runner: RunnerGame) -> void:
	if runner == null or not is_instance_valid(runner):
		return
	if runner.has_signal(&"boss_attack_telegraph") \
			and not runner.boss_attack_telegraph.is_connected(_on_boss_attack_telegraph):
		runner.boss_attack_telegraph.connect(_on_boss_attack_telegraph)
	if runner.has_signal(&"boss_projectile_fired") \
			and not runner.boss_projectile_fired.is_connected(_on_boss_projectile_fired):
		runner.boss_projectile_fired.connect(_on_boss_projectile_fired)
	if runner.has_signal(&"boss_attack_planned") \
			and not runner.is_connected(&"boss_attack_planned", _on_boss_attack_planned):
		runner.connect(&"boss_attack_planned", _on_boss_attack_planned)
	if runner.has_signal(&"boss_attack_committed") \
			and not runner.is_connected(&"boss_attack_committed", _on_boss_attack_committed):
		runner.connect(&"boss_attack_committed", _on_boss_attack_committed)
	if runner.has_signal(&"phase_changed") and not runner.phase_changed.is_connected(_on_phase_changed):
		runner.phase_changed.connect(_on_phase_changed)

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
	_attacks.clear()
	_attack_serial = 0
	_planned.clear()

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
## Slice: {key, front_z, back_z, blocked (lane bitmask), jumpable, rollable, closing_v, projectile,
## hazards}. `closing_v` is the speed the slice closes on the player at — the corridor speed for a
## chunk hazard, the projectile's own `closing_speed` for a boss shot — and every trigger distance
## for that slice is computed from it (systems spec §10.6).
func slices_for(hazards: Array, v: float, now: float) -> Array[Dictionary]:
	var speed := maxf(v, 0.1)
	var entries: Array[Dictionary] = []
	for hazard in hazards:
		var entry := _hazard_entry(hazard, speed, now)
		if entry.is_empty():
			continue
		# Each entry is scanned out to its own closing speed: a shot bearing down at 34 m/s has to be
		# seen further out than a chunk hazard drifting in at the corridor speed.
		if float(entry["front_z"]) <= -scan_range(float(entry["closing_v"])) \
				or float(entry["front_z"]) > 0.5:
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
			# Expanded z ranges overlap (systems spec §8): one manoeuvre answers both hazards. A
			# projectile never merges with a chunk hazard (systems spec §10.6): the two close at
			# different speeds, so one trigger distance cannot answer both.
			if float(entry["front_z"]) >= float(last["back_z"]) - SLICE_TOLERANCE \
					and bool(entry["projectile"]) == bool(last["projectile"]):
				last["back_z"] = minf(float(last["back_z"]), float(entry["back_z"]))
				last["blocked"] = int(last["blocked"]) | int(entry["blocked"])
				last["jumpable"] = bool(last["jumpable"]) and bool(entry["jumpable"])
				last["rollable"] = bool(last["rollable"]) and bool(entry["rollable"])
				# The fastest member sets the trigger, so the slice is answered in time for all of it.
				last["closing_v"] = maxf(float(last["closing_v"]), float(entry["closing_v"]))
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
			"closing_v": entry["closing_v"],
			"projectile": entry["projectile"],
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

# --- boss fights (systems spec §10.6) ---

## The slice one telegraphed attack presents, so the same plan_for() answers a boss shot and a
## chunk hazard. Pure: runner_boss_validator.gd builds these with no fight in progress.
func attack_slice(mask: int, variant: StringName, closing_v: float) -> Dictionary:
	var def := HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, variant)
	var hint: StringName = def.get("dodge_hint", &"")
	var half_depth := projectile_depth(variant) * 0.5
	return {
		"key": 0,
		"front_z": half_depth,
		"back_z": -half_depth,
		"blocked": mask & LANE_ALL,
		"jumpable": HazardDefs.JUMP_HINTS.has(hint),
		"rollable": HazardDefs.ROLL_HINTS.has(hint),
		"closing_v": maxf(closing_v, 0.1),
		"projectile": true,
		"hazards": []
	}

## Depth along z of a projectile variant (contract §11.6); 1.2 m for all four.
func projectile_depth(variant: StringName) -> float:
	var def := HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, variant)
	var size: Vector3 = def.get("size", Vector3.ONE)
	return maxf(size.z, 0.0)

## Seconds a shot spends travelling from the boss to the player's hurtbox: the gap between
## `boss_z` and the player at z 0, less the half depths that touch first (contract §11.6).
func projectile_travel_seconds(closing_v: float, variant: StringName) -> float:
	var from_z := absf(_float_config(&"boss_z", DEFAULT_BOSS_Z))
	var gap := maxf(from_z - projectile_depth(variant) * 0.5 - PLAYER_HALF_DEPTH, 0.0)
	return gap / maxf(closing_v, 0.1)

## Seconds from a telegraph going out to its shot reaching the player: the telegraph itself plus
## the travel at the closing speed (systems spec §10.6).
func telegraph_arrival(telegraph: float, closing_v: float, variant: StringName) -> float:
	return maxf(telegraph, 0.0) + projectile_travel_seconds(closing_v, variant)

## Seconds a manoeuvre needs before it answers the shot: one lane tween per step, or half an arc /
## half a roll for the body actions. Both body halves are 0.35 s at the contract §7 tuning — the
## jump arc is symmetric, so the middle of the window the feet spend above *any* clearable height
## is always the apex, jump_velocity / gravity (systems spec §1.1).
func manoeuvre_cost(action: StringName, steps: int) -> float:
	match action:
		ACTION_LANE:
			return lane_change_time() * float(maxi(steps, 1))
		ACTION_JUMP:
			return jump_peak_time()
		ACTION_ROLL:
			return roll_duration() * 0.5
	return 0.0

## Seconds after the telegraph at which a plan has to start: late enough that the manoeuvre is
## fresh at impact, early enough that it has finished before it (systems spec §10.6).
func telegraph_act_at(arrival: float, action: StringName, steps: int) -> float:
	return arrival - manoeuvre_cost(action, steps) - telegraph_lead()

## Lanes a telegraph still in flight will block, as a lane bitmask. A full-width attack is answered
## with the body rather than with a lane change, so it never rules a tool lane out.
## Entries may be this bot's own (`mask`) or the facade's get_boss_info() rows (`lane_mask`).
func pending_lane_mask(attacks: Array) -> int:
	var mask := 0
	for item in attacks:
		var entry: Dictionary = item
		var lanes := int(entry.get("mask", entry.get("impact_mask", entry.get("lane_mask", 0)))) & LANE_ALL
		if lanes == LANE_ALL:
			continue
		mask |= lanes
	return mask

## The greedy tool pass inside a fight: plan_pickup over the tools this bot is willing to reach for
## — nothing a pending attack will block, and nothing further than config.autopilot_tool_greed
## allows (systems spec §10.6).
func plan_tool(targets: Array, slices: Array, blocked_lanes: int, lane: int, v: float) -> Dictionary:
	var idle := {"action": ACTION_NONE, "lane": lane, "steps": 0}
	var reach := tool_reach()
	if reach <= 0:
		return idle
	var allowed: Array[Dictionary] = []
	for item in targets:
		var target: Dictionary = item
		var target_lane := int(target["lane"])
		if (blocked_lanes & (1 << target_lane)) != 0:
			continue
		if absi(target_lane - lane) > reach:
			continue
		allowed.append(target)
	if allowed.is_empty():
		return idle
	return plan_pickup(allowed, slices, lane, v)

## Lane steps the bot will spend on a tool: none at greed 0, both lanes at greed 1 (contract §11.10
## "0 ignores tools, 1 takes every safe tool").
func tool_reach() -> int:
	var greed := _float_config(&"autopilot_tool_greed", DEFAULT_TOOL_GREED)
	if greed <= 0.0:
		return 0
	return clampi(int(ceilf(greed * float(LANE_COUNT - 1))), 1, LANE_COUNT - 1)

## Extra seconds the bot acts ahead of a telegraphed arrival (contract §11.10).
func telegraph_lead() -> float:
	return maxf(_float_config(&"autopilot_telegraph_lead", DEFAULT_TELEGRAPH_LEAD), 0.0)

## Time from launch to the apex of y(t) = jump_velocity t - gravity t^2 / 2, which is also the
## middle of the window the feet spend above any clearable height (systems spec §1.1): 0.35 s at
## the contract §7 tuning, and exactly half the 0.70 s airtime.
func jump_peak_time() -> float:
	if config == null:
		return DEFAULT_JUMP_PEAK_TIME
	var gravity := float(config.gravity)
	if gravity <= 0.0:
		return DEFAULT_JUMP_PEAK_TIME
	return float(config.jump_velocity) / gravity

func roll_duration() -> float:
	return _float_config(&"roll_duration", DEFAULT_ROLL_DURATION)

## Projectile speed of the fight in progress (contract §11.10 escalation), or the corridor speed
## when there is no stage to read it off.
func boss_closing_speed(fallback: float) -> float:
	if config == null or game == null or not is_instance_valid(game) or not (&"stage_index" in game):
		return maxf(fallback, 0.1)
	var def := BossDefs.fight_def(int(game.get(&"stage_index")), config)
	return maxf(float(def.get("projectile_speed", fallback)), 0.1)

## Telegraphs still worth planning, oldest first. Read-only; the DebugOverlay and the tests use it.
func pending_attacks() -> Array[Dictionary]:
	return _attacks

## Contract 2.4: the full attack arrives just ahead of its telegraph; keep it for that telegraph.
func _on_boss_attack_planned(attack: Dictionary) -> void:
	_planned.append(attack)

func _on_boss_attack_telegraph(lane_mask: int, kind: StringName, seconds: float) -> void:
	var attack := _take_planned(lane_mask, kind)
	if attack.is_empty():
		# An older emitter (or a test) only sends the telegraph: a straight shot at this fight's speed.
		var closing := boss_closing_speed(float(game.speed) if game != null else 0.1)
		attack = BossAttacks.plain_attack(lane_mask, kind, seconds, closing, config)
	_attack_serial += 1
	var entry := attack_entry(attack, maxf(seconds, 0.0))
	entry["key"] = _attack_serial
	_attacks.append(entry)

## The planned attack this telegraph announces, or {} when none came with it.
func _take_planned(lane_mask: int, kind: StringName) -> Dictionary:
	for index in _planned.size():
		var attack: Dictionary = _planned[index]
		if StringName(attack.get("variant", &"")) == kind \
				and int(attack.get("telegraph_mask", -1)) == (lane_mask & LANE_ALL):
			# Anything queued ahead of the match was never telegraphed; drop it with the match.
			var found := attack
			_planned = _planned.slice(index + 1)
			return found
	_planned.clear()
	return {}

## The planning row for one attack: pure, so the validator can read what the bot will plan against.
## An uncommitted flaky attack blocks both candidates until boss_attack_committed narrows it.
func attack_entry(attack: Dictionary, telegraph: float) -> Dictionary:
	var committed := float(attack.get("commit_at", -1.0)) < 0.0
	var impact := int(attack.get("impact_mask", attack.get("mask", 0))) & LANE_ALL
	var shown := int(attack.get("telegraph_mask", impact)) & LANE_ALL
	return {
		"key": 0,
		"mask": impact if committed else (impact | shown),
		"telegraph_mask": shown,
		"variant": attack.get("variant", &"orb"),
		"telegraph": telegraph,
		"closing_v": maxf(float(attack.get("speed", 0.1)), 0.1),
		"arrival": float(attack.get("enter", telegraph)),
		"exit": float(attack.get("exit", telegraph)),
		"jumpable": bool(attack.get("jumpable", false)),
		"rollable": bool(attack.get("rollable", false)),
		"clear_height": float(attack.get("clear_height", 0.0)),
		"committed": committed,
		"attack": attack,
		"elapsed": 0.0
	}

## A flaky telegraph settled: the oldest uncommitted attack of this kind whose candidates hold the
## committed lanes now blocks only those, and whatever the bot had planned for it is planned again.
func _on_boss_attack_committed(lane_mask: int, kind: StringName, _seconds: float) -> void:
	var lanes := lane_mask & LANE_ALL
	for entry in _attacks:
		if bool(entry.get("committed", true)) or StringName(entry.get("variant", &"")) != kind:
			continue
		if (int(entry.get("telegraph_mask", 0)) & lanes) != lanes:
			continue
		var attack: Dictionary = entry.get("attack", {})
		entry["committed"] = true
		entry["mask"] = int(attack.get("impact_mask", lanes)) & LANE_ALL
		var key := StringName(str(entry["key"]))
		_done.erase(key)
		_pending.erase(key)
		return

## The shot the bot already stepped aside for must not earn a second manoeuvre once it exists as a
## real hazard, so the projectile inherits the telegraph's answered flag. A mask that fires more
## than one projectile sends this signal once per group, and each of them is claimed by the same
## telegraph — nothing is consumed here.
func _on_boss_projectile_fired(projectile: Area3D, _lane_mask: int, kind: StringName, _speed: float) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	for item in _attacks:
		var entry: Dictionary = item
		if StringName(entry.get("variant", &"")) != kind:
			continue
		if float(entry["elapsed"]) + FIRE_MATCH_SLACK < float(entry["telegraph"]):
			continue
		if _done.has(StringName(str(entry["key"]))):
			_done[StringName(str(projectile.get_instance_id()))] = true
		return

## Leaving the fight drops every telegraph: the arena frees its shots, so nothing is left to dodge.
func _on_phase_changed(value: StringName) -> void:
	if value != PHASE_BOSS:
		_attacks.clear()

func _is_boss_phase() -> bool:
	return game != null and is_instance_valid(game) and &"phase" in game \
		and StringName(game.get(&"phase")) == PHASE_BOSS

## Age every telegraph and forget the ones whose shot has come and gone.
func _age_attacks(delta: float) -> void:
	for index in range(_attacks.size() - 1, -1, -1):
		var entry := _attacks[index]
		entry["elapsed"] = float(entry["elapsed"]) + delta
		if float(entry["elapsed"]) > float(entry["arrival"]) + ATTACK_GRACE:
			_attacks.remove_at(index)

## The unanswered telegraph that reaches the player first (oldest first on a tie). With one speed
## per fight that is simply the oldest; a slow wall telegraphed before a fast shot is not.
func _next_attack() -> Dictionary:
	var best := {}
	var best_in := INF
	for item in _attacks:
		var entry: Dictionary = item
		var key := StringName(str(entry["key"]))
		if _done.has(key) or _ignored.has(key):
			continue
		if _seconds_to_exit(entry) <= 0.0:
			continue
		var t_in := _seconds_to_arrival(entry)
		if t_in < best_in - 0.0001:
			best = entry
			best_in = t_in
	return best

func _seconds_to_arrival(entry: Dictionary) -> float:
	return float(entry["arrival"]) - float(entry["elapsed"])

func _seconds_to_exit(entry: Dictionary) -> float:
	return float(entry.get("exit", entry["arrival"])) - float(entry["elapsed"])

## Every unanswered attack still to pass whose window comes within GROUP_WINDOW of `target`'s,
## target first. Answered ones are out: their answer is already under way.
func _attack_group(target: Dictionary) -> Array[Dictionary]:
	var group: Array[Dictionary] = [target]
	var t_in := _seconds_to_arrival(target)
	var t_out := _seconds_to_exit(target)
	for item in _attacks:
		var entry: Dictionary = item
		var entry_key := StringName(str(entry["key"]))
		if int(entry["key"]) == int(target["key"]) or _ignored.has(entry_key) or _done.has(entry_key):
			continue
		if _seconds_to_exit(entry) <= 0.0:
			continue
		if _seconds_to_arrival(entry) > t_out + GROUP_WINDOW or _seconds_to_exit(entry) < t_in - GROUP_WINDOW:
			continue
		group.append(entry)
	return group

## The answered attacks inside the same window. They are planned alongside the group — a new answer
## must not undo theirs (step into a lane one of them was dodged by leaving) — except where the body
## action already under way is what clears them (_body_clears).
func _attack_obstacles(target: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t_in := _seconds_to_arrival(target)
	var t_out := _seconds_to_exit(target)
	for item in _attacks:
		var entry: Dictionary = item
		var entry_key := StringName(str(entry["key"]))
		if int(entry["key"]) == int(target["key"]) or not _done.has(entry_key) or _ignored.has(entry_key):
			continue
		if _seconds_to_exit(entry) <= 0.0:
			continue
		if _seconds_to_arrival(entry) > t_out + GROUP_WINDOW or _seconds_to_exit(entry) < t_in - GROUP_WINDOW:
			continue
		out.append(entry)
	return out

## The player's body action in progress (set per tick by _plan_next_attack): a shot it clears is
## not in the way of a lane move made from under it.
var _airborne_now := false
var _rolling_now := false

func _body_clears(entry: Dictionary) -> bool:
	return (_airborne_now and bool(entry.get("jumpable", false))) \
		or (_rolling_now and bool(entry.get("rollable", false)))


## The slice one planning row presents, from its impact geometry.
func entry_slice(entry: Dictionary) -> Dictionary:
	var half_depth := projectile_depth(StringName(entry.get("variant", &"orb"))) * 0.5
	return {
		"key": entry.get("key", 0),
		"front_z": half_depth,
		"back_z": -half_depth,
		"blocked": int(entry.get("mask", 0)) & LANE_ALL,
		"jumpable": bool(entry.get("jumpable", false)),
		"rollable": bool(entry.get("rollable", false)),
		"closing_v": maxf(float(entry.get("closing_v", 0.1)), 0.1),
		"projectile": true,
		"hazards": []
	}

## The answer to a group of attacks from `lane`: {action, lane, steps}. One attack is plan_for()
## exactly as before; several are searched for one final lane plus at most one body action that
## survives every member, in the mode's order of preference. A lane plan comes back first even when
## a body action has to follow it: the next tick re-plans from the new lane and finds the body half.
## No common answer falls back to plan_for() on the target alone, flagged `solo`, and is then timed
## and booked against the target alone.
func plan_group(group: Array, lane: int) -> Dictionary:
	var target: Dictionary = group[0]
	if group.size() == 1:
		return plan_for(entry_slice(target), lane)
	var bodies: Array[StringName] = [ACTION_NONE, ACTION_JUMP, ACTION_ROLL]
	var lanes := _lanes_by_distance(lane)
	var order: Array = []
	if mode == Mode.PREFER_JUMP:
		order.append([lane, ACTION_NONE])
		order.append([lane, ACTION_JUMP])
		order.append([lane, ACTION_ROLL])
		for candidate in lanes:
			for body in bodies:
				order.append([candidate, body])
	else:
		for candidate in [lane] + lanes:
			order.append([candidate, ACTION_NONE])
		for candidate in [lane] + lanes:
			order.append([candidate, ACTION_JUMP])
			order.append([candidate, ACTION_ROLL])
	for pair in order:
		var goal := int(pair[0])
		var body := StringName(pair[1])
		if not _group_answer_works(group, goal, body, lane):
			continue
		if goal != lane:
			return {"action": ACTION_LANE, "lane": goal, "steps": absi(goal - lane)}
		return {"action": body, "lane": lane, "steps": 0}
	var solo := plan_for(entry_slice(target), lane)
	solo["solo"] = true
	return solo

## True when ending in `goal` with `body` survives every member, and the members the body has to
## clear fit inside one jump arc / one roll. Staying in `lane` keeps whatever the body action under
## way is clearing.
func _group_answer_works(group: Array, goal: int, body: StringName, lane: int) -> bool:
	var body_in := INF
	var body_out := -INF
	var height := 0.0
	for item in group:
		var entry: Dictionary = item
		if not _lane_blocked(int(entry.get("mask", 0)), goal):
			continue
		if goal == lane and _body_clears(entry):
			continue
		if body == ACTION_JUMP and bool(entry.get("jumpable", false)):
			pass
		elif body == ACTION_ROLL and bool(entry.get("rollable", false)):
			pass
		else:
			return false
		body_in = minf(body_in, _seconds_to_arrival(entry))
		body_out = maxf(body_out, _seconds_to_exit(entry))
		height = maxf(height, float(entry.get("clear_height", 0.0)))
	if body == ACTION_NONE or body_in == INF:
		return true
	if body == ACTION_JUMP:
		var span := jump_clear_span(height)
		return span.y - span.x >= body_out - body_in + BODY_MARGIN * 2.0
	return roll_duration() >= body_out - body_in + BODY_MARGIN * 2.0

## Seconds from now at which `plan` has to start to answer `group` (systems spec §10.6): a lane plan
## finishes a lead before the first member that blocks a lane on its way; a body action is centred
## on the members it clears, and never so early or so late that the arc / roll misses one of them.
## For a single fast shot this is exactly telegraph_act_at(): the clamp only moves a slow shot's jump.
func group_act_in(group: Array, plan: Dictionary, lane: int) -> float:
	var action := StringName(plan.get("action", ACTION_NONE))
	var goal := int(plan.get("lane", lane))
	if action == ACTION_LANE:
		var first := INF
		for item in group:
			var entry: Dictionary = item
			var blocked := int(entry.get("mask", 0))
			for crossed in range(mini(lane, goal), maxi(lane, goal) + 1):
				if not _lane_blocked(blocked, crossed):
					continue
				# The lane it is standing in does not hurry the move while the body clears that shot.
				if crossed == lane and _body_clears(entry):
					continue
				first = minf(first, _seconds_to_arrival(entry))
				break
		if first == INF:
			first = _seconds_to_arrival(group[0])
		return first - manoeuvre_cost(action, int(plan.get("steps", 0))) - telegraph_lead()
	var body_in := INF
	var body_out := -INF
	var height := 0.0
	for item in group:
		var entry: Dictionary = item
		if not _lane_blocked(int(entry.get("mask", 0)), lane) or _body_clears(entry):
			continue
		body_in = minf(body_in, _seconds_to_arrival(entry))
		body_out = maxf(body_out, _seconds_to_exit(entry))
		height = maxf(height, float(entry.get("clear_height", 0.0)))
	if body_in == INF:
		body_in = _seconds_to_arrival(group[0])
		body_out = _seconds_to_exit(group[0])
	var preferred := body_in - manoeuvre_cost(action, 0) - telegraph_lead()
	var earliest := -INF
	var latest := INF
	if action == ACTION_JUMP:
		var span := jump_clear_span(height)
		earliest = body_out - span.y + BODY_MARGIN
		latest = body_in - span.x - BODY_MARGIN
	elif action == ACTION_ROLL:
		earliest = body_out - roll_duration() + BODY_MARGIN
		latest = body_in - BODY_MARGIN
	if earliest > latest:
		return preferred
	return clampf(preferred, earliest, latest)

## The window (t_low, t_high) after a launch in which the feet are above `height`, from the contract
## §7 arc y(t) = jump_velocity t - gravity t^2 / 2; (0, 0) when the arc never gets there.
func jump_clear_span(height: float) -> Vector2:
	var v := _float_config(&"jump_velocity", 9.8)
	var g := _float_config(&"gravity", 28.0)
	var disc := v * v - 2.0 * g * maxf(height, 0.0)
	if disc <= 0.0 or g <= 0.0:
		return Vector2.ZERO
	var root := sqrt(disc)
	return Vector2((v - root) / g, (v + root) / g)

## Lanes other than `lane`, nearest first, left before right on a tie (plan_for's order).
func _lanes_by_distance(lane: int) -> Array[int]:
	var out: Array[int] = []
	for distance: int in [1, 2]:
		for direction: int in [-1, 1]:
			var candidate := lane + direction * distance
			if candidate >= 0 and candidate < LANE_COUNT:
				out.append(candidate)
	return out

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

func _physics_process(delta: float) -> void:
	if not enabled or game == null or game.state != &"running":
		return
	var player: Node = game.player
	if player == null or not is_instance_valid(player):
		return
	var tree := get_tree()
	if tree == null:
		return
	_age_attacks(delta)
	var v := maxf(float(game.speed), 0.1)
	if _is_boss_phase():
		_drive_fight(player, v, tree)
		return
	_drive_corridor(player, v, tree)

## The v1 loop: answer the nearest unresolved slice, then go shopping if the mode says so.
func _drive_corridor(player: Node, v: float, tree: SceneTree) -> void:
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
	_execute(plan, float(slice["front_z"]), float(slice["closing_v"]), player, key)

## The boss loop (systems spec §10.6): plan the next telegraph on its own clock, fall back to the
## live shots for anything that was not answered ahead of time, and spend the gaps between attacks
## reaching for tools the pending telegraphs do not rule out.
func _drive_fight(player: Node, v: float, tree: SceneTree) -> void:
	var slices := slices_for(tree.get_nodes_in_group(&"runner_hazards"), v, float(game.elapsed))
	var tools := pickup_targets(tree.get_nodes_in_group(&"runner_tools"), v)
	_prune(slices, tools)
	var lane := _player_lane(player)
	if _plan_next_attack(player, lane):
		return
	var slice := _next_slice(slices)
	if not slice.is_empty():
		var key := StringName(str(slice["key"]))
		var plan := _pending_plan(key, slice, lane)
		_execute(plan, float(slice["front_z"]), float(slice["closing_v"]), player, key)
		return
	var greed := plan_tool(tools, slices, pending_lane_mask(_attacks), lane, v)
	_execute(greed, float(greed.get("front_z", 0.0)), v, player, StringName(str(greed.get("key", ""))))

## Answer the oldest unanswered telegraph. Returns true when this tick belongs to that attack —
## either because the manoeuvre was run, or because it is still too early to run it and the bot
## must not wander off after a tool in the meantime.
func _plan_next_attack(player: Node, lane: int) -> bool:
	var attack := _next_attack()
	if attack.is_empty():
		return false
	var key := StringName(str(attack["key"]))
	_airborne_now = _is_airborne(player)
	_rolling_now = _is_rolling(player)
	var group := _attack_group(attack)
	group.append_array(_attack_obstacles(attack))
	var plan := _pending_group_plan(key, group, lane)
	if bool(plan.get("solo", false)):
		group = [attack]
	var action := StringName(plan.get("action", ACTION_NONE))
	if action == ACTION_NONE:
		# This lane is already safe (or nothing answers the target at all): nothing to do, and the
		# tool pass may have the tick.
		_done[key] = true
		_mark_answered(group, lane, ACTION_NONE)
		return false
	var act_in := group_act_in(group, plan, lane)
	if act_in <= 0.0:
		if action != ACTION_LANE and _is_airborne(player):
			# Still in the air from the previous answer: a jump or roll asked for now would only sit
			# in a buffer that may run out before touchdown, so hold it and fire it on landing.
			return true
		_perform(plan, player, key)
		if _done.has(key):
			# _perform() calls a finished lane change done; a member still blocking the lane it ended
			# in (the half of a group answer a body action has to finish) is not, yet.
			_done.erase(key)
			_mark_answered(group, _player_lane(player), action)
		return true
	# Still early. Hold the tick — and with it the lane — once the attack is close enough that a
	# tool detour could not be walked back in time; before that the greedy pass owns the gap.
	return act_in <= lane_change_time() * float(LANE_COUNT - 1)

## _pending_plan() for a group: a lane change under way is carried on while its goal lane stays
## clear of every member, and planned again from scratch the moment it is not.
func _pending_group_plan(key: StringName, group: Array, lane: int) -> Dictionary:
	if not _pending.has(key):
		return plan_group(group, lane)
	var plan: Dictionary = _pending[key]
	var goal := clampi(int(plan.get("lane", lane)), 0, LANE_COUNT - 1)
	var blocked := 0
	for item in group:
		blocked |= int((item as Dictionary).get("mask", 0))
	if goal == lane or not _lane_blocked(blocked, goal):
		return plan
	# A body action can still answer what blocks the goal: keep heading there.
	if group.size() > 1 and (_group_answer_works(group, goal, ACTION_JUMP, lane) \
			or _group_answer_works(group, goal, ACTION_ROLL, lane)):
		return plan
	_pending.erase(key)
	return plan_group(group, lane)

## After a plan ran (or turned out unnecessary), every member it answers is done: those that do not
## block the lane the bot ends in, and those the body action just taken clears. A lane change is
## also the one thing that can undo an earlier answer, so after one every member that blocks the new
## lane — an answered one included — is open again, and gets its body action on a later tick.
func _mark_answered(group: Array, lane: int, action: StringName) -> void:
	for item in group:
		var entry: Dictionary = item
		var key := StringName(str(entry["key"]))
		var blocked := _lane_blocked(int(entry.get("mask", 0)), lane)
		var cleared := (action == ACTION_JUMP and bool(entry.get("jumpable", false))) \
			or (action == ACTION_ROLL and bool(entry.get("rollable", false)))
		if not blocked or cleared:
			_done[key] = true
		elif action == ACTION_LANE and not _body_clears(entry):
			_done.erase(key)

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

## Run the plan once its trigger distance is reached (systems spec §8). `v` is the slice's own
## closing speed, so a shot bearing down at 34 m/s is answered further out than a chunk hazard.
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
	_perform(plan, player, key)

## Run the plan now, whatever the distance: the boss branch triggers on the telegraph clock rather
## than on a z line, so it commits here directly (systems spec §10.6).
func _perform(plan: Dictionary, player: Node, key: StringName) -> void:
	match StringName(plan.get("action", ACTION_NONE)):
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

## True while the player is in a roll (runner_player.is_rolling, or a stand-in's `rolling`).
func _is_rolling(player: Node) -> bool:
	if &"is_rolling" in player:
		return bool(player.get(&"is_rolling"))
	if &"rolling" in player:
		return bool(player.get(&"rolling"))
	return false

## True while the player is off the floor (runner_player.is_airborne, or a stand-in's `airborne`).
func _is_airborne(player: Node) -> bool:
	if &"is_airborne" in player:
		return bool(player.get(&"is_airborne"))
	if &"airborne" in player:
		return bool(player.get(&"airborne"))
	return false

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
	if node.has_method("impact_lane_mask"):
		# Contract 2.4: a moving shot is answered in the lanes it will pass the player in.
		blocked = int(node.impact_lane_mask()) & LANE_ALL
	else:
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
		"closing_v": _closing_speed_of(node, v),
		"projectile": _is_projectile(node),
		"hazard": node
	}

## A boss shot closes at its own `closing_speed`; everything else rides the corridor at `v`
## (systems spec §10.6). A projectile whose speed has not been set yet falls back to the corridor.
func _closing_speed_of(node: Node3D, v: float) -> float:
	if &"closing_speed" in node:
		var own := absf(float(node.get(&"closing_speed")))
		if own > 0.0:
			return own
	return maxf(v, 0.1)

## True for the one hazard kind that moves on its own (contract §11.6). `closing_speed` is the
## projectile script's own marker, so a hazard stand-in in a test is recognised as well.
func _is_projectile(node: Node3D) -> bool:
	if &"kind" in node and HazardDefs.is_projectile(StringName(node.get(&"kind"))):
		return true
	return &"closing_speed" in node

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

## Keep only the keys still in range, so instance ids can never pile up across a long run. A
## telegraph still in flight counts as live: its key is a serial, not a node, so nothing else would
## keep an answered attack from being planned all over again on the next tick.
func _prune(slices: Array, targets: Array) -> void:
	var live := {}
	for item in slices:
		live[StringName(str((item as Dictionary)["key"]))] = true
	for item in targets:
		live[StringName(str((item as Dictionary).get("key", "")))] = true
	for item in _attacks:
		live[StringName(str((item as Dictionary)["key"]))] = true
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

## A named number off a config that may be null or an older resource.
func _float_config(property: StringName, fallback: float) -> float:
	if config == null or not (property in config):
		return fallback
	var value: Variant = config.get(property)
	if value is int or value is float:
		return float(value)
	return fallback
