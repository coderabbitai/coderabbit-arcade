extends RefCounted
## Boss attacks and shot motion (contract 2.4 §11.6, systems spec §10.3). This is the one place a
## pattern beat becomes the attacks it telegraphs and the shots those attacks fire, and the one
## place a shot's motion over time is defined. Everything here is pure and static, so
## boss_encounter.gd (fires them), projectile.gd (flies them), autopilot.gd (plans against them) and
## runner_boss_validator.gd (proves them fair) all read the same numbers.
##
## Vocabulary.
## - A *beat* is one row of boss_defs.gd SLOTS[..].patterns[phase]. A beat without a `signature`
##   key is a plain v2.0 beat and resolves exactly as it always has: one attack, straight shots.
## - An *option* is one way a beat can resolve (one random lane draw); it is an Array of attacks,
##   and only a `branching` volley ever holds more than one.
## - An *attack* is one telegraph: `boss_attack_planned(attack)`, then
##   `boss_attack_telegraph(attack.telegraph_mask, attack.variant, attack.telegraph)`, and when the
##   telegraph runs out one projectile per entry of `attack.shots`.
## - A *shot* is one projectile's motion, a function of t = seconds since that projectile was fired:
##   z(t) = from_z + speed × t (always straight along +Z at constant speed), x(t) piecewise linear
##   through `x_keys`, and a y lift that only a falling `debris` slab ever has.

const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const HazardDefs = preload("res://scenes/runner/hazards/hazard_defs.gd")

const LANE_COUNT := 3
const LANE_ALL := 0b111
## Half the player's footprint along z (contract §7 capsule radius 0.4).
const PLAYER_HALF_DEPTH := 0.4
## Contract §7 / §11.10 fallbacks for a null config.
const DEFAULT_BOSS_Z := -14.0
const DEFAULT_LANE_WIDTH := 2.0
const DEFAULT_HURTBOX_RADIUS := 0.4
## Same tolerance hazard.gd uses: a hitbox that only just reaches a lane boundary does not claim it.
const LANE_REACH_EPSILON := 0.01
## Sampling step for the lane / height unions over a pass window, in seconds.
const SAMPLE_STEP := 1.0 / 240.0

## Beat signatures (boss_defs.gd `signature`). SIG_PLAIN is every v2.0 beat.
const SIG_PLAIN: StringName = &""
const SIG_FLAKY: StringName = &"flaky"
const SIG_SCATTER: StringName = &"scatter"
const SIG_BRANCHING: StringName = &"branching"
const SIG_SWEEP: StringName = &"sweep"
const SIG_FORCE_PUSH: StringName = &"force_push"
const SIG_LEGACY_WALL: StringName = &"legacy_wall"
const SIG_QUAKE: StringName = &"quake"
const SIG_DEBRIS: StringName = &"debris"
const SIGNATURES: Array[StringName] = [
	SIG_FLAKY, SIG_SCATTER, SIG_BRANCHING, SIG_SWEEP, SIG_FORCE_PUSH, SIG_LEGACY_WALL, SIG_QUAKE, SIG_DEBRIS
]
## Seconds the scatter orb's two halves take to slide from the middle lane to the outer ones.
const SPLIT_SECONDS := 0.10
## Seconds the legacy wall's moving slab takes to slide across one lane when the gap shifts.
const SHIFT_SECONDS := 0.18
## Beat defaults for the fractions a signature beat may leave out.
const DEFAULT_SWEEP_FRACTION := 0.7
const DEFAULT_SHIFT_FRACTION := 0.3
const DEFAULT_LAND_FRACTION := 0.2
const DEFAULT_DROP_HEIGHT := 4.0

# --- beats -> options -> attacks ---

## Every way `beat` can resolve in this fight's `phase`, in a stable order: an Array of options,
## each an Array of finished attacks (see the header). The encounter draws one with pick_option();
## the validator walks all of them.
static func beat_options(beat: Dictionary, def: Dictionary, phase: int, config: RunConfig) -> Array:
	var signature: StringName = beat.get("signature", SIG_PLAIN)
	var ctx := _context(beat, def, phase, config)
	var options: Array = []
	match signature:
		SIG_FLAKY:
			for pair in _candidate_pairs(beat):
				for committed: int in pair:
					options.append([_flaky(ctx, pair, committed, config)])
		SIG_SCATTER:
			options.append([_scatter(ctx, config)])
		SIG_BRANCHING:
			for lanes in _head_lanes(beat):
				options.append(_branching(ctx, beat, lanes, config))
		SIG_SWEEP:
			for path in _sweep_paths(beat):
				options.append([_sweep(ctx, beat, path, config)])
		SIG_LEGACY_WALL:
			for gaps in _gap_shifts(beat):
				options.append([_legacy_wall(ctx, beat, gaps, config)])
		SIG_DEBRIS:
			for mask in lane_pool(beat):
				options.append([_debris(ctx, beat, mask, config)])
		_:
			# Plain, force push and quake: straight shots on a lane mask drawn from the pool.
			for mask in lane_pool(beat):
				options.append([_finish(_attack(ctx, mask, mask), config)])
	return options

## True when drawing an option for `beat` consumes a fight_rng roll. Plain fixed beats never have,
## and random ones always have, so a v2.0 beat replays the exact lane stream it always did.
static func draws_random(beat: Dictionary, options: Array) -> bool:
	var mode: StringName = beat.get("lanes", BossDefs.LANES_FIXED)
	return mode != BossDefs.LANES_FIXED or options.size() > 1

## Index of the option to fire: never a straight repeat of the previous beat's key while there is a
## choice (the v2.0 _pick_mask rule, now over options). `random` false returns 0 without a roll.
static func pick_option(options: Array, last_key: int, rng: RandomNumberGenerator, random: bool) -> int:
	if options.is_empty():
		return -1
	if not random or rng == null:
		return 0
	var choices: Array[int] = []
	for index in options.size():
		if option_key(options[index]) != last_key:
			choices.append(index)
	if choices.is_empty():
		for index in options.size():
			choices.append(index)
	return choices[rng.randi_range(0, choices.size() - 1)]

## The mask the no-repeat rule compares: the lanes an option blocks at impact (for a plain beat that
## is its lane mask, exactly as before), OR-ed over a branching volley's heads.
static func option_key(option: Array) -> int:
	var key := 0
	for attack: Dictionary in option:
		key |= int(attack.get("impact_mask", 0))
	return key

## The lane masks a beat's `lanes` mode draws from, in the order boss_defs lists them.
static func lane_pool(beat: Dictionary) -> Array[int]:
	var mode: StringName = beat.get("lanes", BossDefs.LANES_FIXED)
	if mode == BossDefs.LANES_RANDOM_SINGLE:
		return BossDefs.SINGLE_LANE_MASKS.duplicate()
	if mode == BossDefs.LANES_RANDOM_ADJACENT:
		return BossDefs.ADJACENT_LANE_MASKS.duplicate()
	if mode == BossDefs.LANES_RANDOM_SINGLE_OR_ADJACENT:
		var pool: Array[int] = BossDefs.SINGLE_LANE_MASKS.duplicate()
		pool.append_array(BossDefs.ADJACENT_LANE_MASKS)
		return pool
	var fixed: Array[int] = [int(beat.get("mask", BossDefs.LANE_ALL))]
	return fixed

## A plain v2.0 attack from nothing but what boss_attack_telegraph carries: the planner's fallback
## when no boss_attack_planned came with the telegraph (an older emitter, or a test).
static func plain_attack(mask: int, variant: StringName, telegraph: float, speed: float,
		config: RunConfig) -> Dictionary:
	var ctx := {
		"variant": variant, "telegraph": maxf(telegraph, 0.0), "speed": maxf(speed, 0.1),
		"from_z": _boss_z(config), "boss_kind": &"", "signature": SIG_PLAIN
	}
	return _finish(_attack(ctx, mask & LANE_ALL, mask & LANE_ALL), config)

# --- shots ---

## The projectiles one attack fires, one motion dictionary each:
## {variant, speed, from_z, lanes (lane group at fire), x_keys: PackedVector2Array of (t, x),
##  drop_height, land_at, twin}. `twin` marks the second half of a scatter orb, which flies inside the
## first until the split (a visual may hide it until then).
static func shots_for(attack: Dictionary, config: RunConfig) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var signature: StringName = attack.get("signature", SIG_PLAIN)
	var variant: StringName = attack.get("variant", &"orb")
	var width := _lane_width(config)
	match signature:
		SIG_SCATTER:
			var split := float(attack.get("split_at", 0.0))
			var from_x := _mask_center_x(int(attack.get("mask", BossDefs.LANE_MIDDLE)), config)
			for side: int in [-1, 1]:
				var keys := PackedVector2Array([
					Vector2(0.0, from_x), Vector2(split, from_x),
					Vector2(split + SPLIT_SECONDS, from_x + float(side) * width)
				])
				var shot := _shot(attack, BossDefs.LANE_MIDDLE, keys)
				shot["twin"] = side > 0
				shots.append(shot)
		SIG_SWEEP:
			var from_lane := int(attack.get("sweep_from", 0))
			var to_lane := int(attack.get("sweep_to", 2))
			var keys := PackedVector2Array([
				Vector2(0.0, _lane_x(from_lane, config)),
				Vector2(float(attack.get("sweep_end", 0.0)), _lane_x(to_lane, config))
			])
			shots.append(_shot(attack, 1 << from_lane, keys))
		SIG_LEGACY_WALL:
			var gap_from := int(attack.get("gap_from", 0))
			var gap_to := int(attack.get("gap_to", 1))
			var shift := float(attack.get("shift_at", 0.0))
			var travel := SHIFT_SECONDS * float(maxi(absi(gap_to - gap_from), 1))
			for lane in LANE_COUNT:
				if lane == gap_from:
					continue
				var x := _lane_x(lane, config)
				var keys := PackedVector2Array([Vector2(0.0, x)])
				# The slab standing in the lane that is about to open slides into the old gap.
				if lane == gap_to:
					keys.append(Vector2(shift, x))
					keys.append(Vector2(shift + travel, _lane_x(gap_from, config)))
				shots.append(_shot(attack, 1 << lane, keys))
		_:
			for group in lane_groups(int(attack.get("mask", 0)), variant):
				var x := _mask_center_x(group, config)
				var shot := _shot(attack, group, PackedVector2Array([Vector2(0.0, x)]))
				if signature == SIG_DEBRIS:
					shot["drop_height"] = float(attack.get("drop_height", DEFAULT_DROP_HEIGHT))
					shot["land_at"] = float(attack.get("land_at", 0.0))
				shots.append(shot)
	return shots

## boss_encounter v2.0 grouping: one projectile per contiguous run of at most `lanes_wide` lanes, so
## a two-lane orb beat fires two orbs and a two-lane wide beat fires one wall.
static func lane_groups(mask: int, variant: StringName) -> Array[int]:
	var width := HazardDefs.lanes_wide(HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, variant))
	var groups: Array[int] = []
	var run: Array[int] = []
	for lane in range(LANE_COUNT + 1):
		if lane < LANE_COUNT and (mask & (1 << lane)) != 0:
			run.append(lane)
			continue
		var index := 0
		while index < run.size():
			var group := 0
			for offset in range(index, mini(index + width, run.size())):
				group |= 1 << run[offset]
			groups.append(group)
			index += width
		run.clear()
	return groups

# --- the motion API (t = seconds since the shot was fired) ---

static func shot_def(shot: Dictionary) -> Dictionary:
	return HazardDefs.get_def(HazardDefs.PROJECTILE_KIND, StringName(shot.get("variant", &"orb")))

## Track z of the shot's centre.
static func z_at(shot: Dictionary, t: float) -> float:
	return float(shot.get("from_z", DEFAULT_BOSS_Z)) + float(shot.get("speed", 0.0)) * t

## World x of the shot's centre (lane-local; the arena never mirrors).
static func x_at(shot: Dictionary, t: float) -> float:
	var keys: PackedVector2Array = shot.get("x_keys", PackedVector2Array())
	if keys.is_empty():
		return 0.0
	if t <= keys[0].x:
		return keys[0].y
	for index in range(1, keys.size()):
		var a := keys[index - 1]
		var b := keys[index]
		if t <= b.x:
			var span := b.x - a.x
			if span <= 0.0:
				return b.y
			return lerpf(a.y, b.y, (t - a.x) / span)
	return keys[keys.size() - 1].y

## Metres the hitbox is lifted above its contract §11.6 y range: a debris slab falls from
## drop_height with a gravity-like ease-in and lands at land_at; every other shot is 0.
static func y_offset_at(shot: Dictionary, t: float) -> float:
	var height := float(shot.get("drop_height", 0.0))
	var land := float(shot.get("land_at", 0.0))
	if height <= 0.0 or land <= 0.0:
		return 0.0
	if t >= land:
		return 0.0
	var k := clampf(t / land, 0.0, 1.0)
	return height * (1.0 - k * k)

## World y range (min, max) the hitbox occupies at t.
static func y_range_at(shot: Dictionary, t: float) -> Vector2:
	var def := shot_def(shot)
	var lift := y_offset_at(shot, t)
	return Vector2(float(def.get("y_min", 0.0)) + lift, float(def.get("y_max", 0.0)) + lift)

## Lanes (bit i = lane i) the hitbox can touch at t: its x extent against the player's capsule
## radius, the rule hazard.gd occupies_lane() applies.
static func lane_mask_at(shot: Dictionary, t: float, config: RunConfig) -> int:
	var size: Vector3 = shot_def(shot).get("size", Vector3.ONE)
	var reach := size.x * 0.5 + _hurtbox_radius(config) - LANE_REACH_EPSILON
	var x := x_at(shot, t)
	var mask := 0
	for lane in LANE_COUNT:
		if absf(_lane_x(lane, config) - x) < reach:
			mask |= 1 << lane
	return mask

## (t_enter, t_exit): the seconds since fire during which the shot's z range overlaps the player's
## footprint at z 0. Everything a dodge has to answer happens inside this window.
static func pass_window(shot: Dictionary) -> Vector2:
	var speed := maxf(float(shot.get("speed", 0.0)), 0.1)
	var depth := maxf((shot_def(shot).get("size", Vector3.ONE) as Vector3).z, 0.0)
	var from_z := float(shot.get("from_z", DEFAULT_BOSS_Z))
	return Vector2((-PLAYER_HALF_DEPTH - depth * 0.5 - from_z) / speed,
		(PLAYER_HALF_DEPTH + depth * 0.5 - from_z) / speed)

## Lanes the shot touches at any moment of [t0, t1].
static func mask_over(shot: Dictionary, t0: float, t1: float, config: RunConfig) -> int:
	var mask := lane_mask_at(shot, t1, config)
	var t := t0
	while t < t1:
		mask |= lane_mask_at(shot, t, config)
		t += SAMPLE_STEP
	return mask

## Lowest y_min and highest y_max over [t0, t1].
static func y_over(shot: Dictionary, t0: float, t1: float) -> Vector2:
	var out := y_range_at(shot, t1)
	var t := t0
	while t < t1:
		var at := y_range_at(shot, t)
		out = Vector2(minf(out.x, at.x), maxf(out.y, at.y))
		t += SAMPLE_STEP
	return out

## Lanes the shot blocks while it passes the player.
static func impact_mask(shot: Dictionary, config: RunConfig) -> int:
	var window := pass_window(shot)
	return mask_over(shot, window.x, window.y, config)

## y range the shot occupies while it passes the player.
static func impact_y(shot: Dictionary) -> Vector2:
	var window := pass_window(shot)
	return y_over(shot, window.x, window.y)

## True when a jump answers the shot: its hint allows it and it is in its landed geometry for the
## whole pass (a slab still falling through the pass is not something to plan a jump over).
static func shot_jumpable(shot: Dictionary) -> bool:
	var def := shot_def(shot)
	if not HazardDefs.JUMP_HINTS.has(def.get("dodge_hint", &"")):
		return false
	return is_equal_approx(impact_y(shot).y, float(def.get("y_max", 0.0)))

static func shot_rollable(shot: Dictionary) -> bool:
	var def := shot_def(shot)
	if not HazardDefs.ROLL_HINTS.has(def.get("dodge_hint", &"")):
		return false
	return is_equal_approx(impact_y(shot).x, float(def.get("y_min", 0.0)))

# --- attack-level reads ---

## The moments a signature attack changes under the player's eyes, each {name, at} with `at` in
## seconds after the telegraph went out: the flaky commit, the scatter split, the start of the
## rebase sweep, the legacy gap shift, and the debris shadow plus its landing. Plain attacks have
## none; runner_boss_validator.gd B6 proves every one leaves a reaction window.
static func events(attack: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var telegraph := float(attack.get("telegraph", 0.0))
	match StringName(attack.get("signature", SIG_PLAIN)):
		SIG_FLAKY:
			out.append({"name": &"commit", "at": float(attack.get("commit_at", 0.0))})
		SIG_SCATTER:
			out.append({"name": &"split", "at": telegraph + float(attack.get("split_at", 0.0))})
		SIG_SWEEP:
			out.append({"name": &"sweep", "at": telegraph})
		SIG_LEGACY_WALL:
			out.append({"name": &"shift", "at": telegraph + float(attack.get("shift_at", 0.0))})
		SIG_DEBRIS:
			out.append({"name": &"shadow", "at": 0.0})
			out.append({"name": &"land", "at": telegraph + float(attack.get("land_at", 0.0))})
	return out

## Seconds from the moment the lanes are final to the telegraph running out: the whole telegraph for
## every attack except a flaky one, whose lanes only become final at the commit.
static func committed_telegraph(attack: Dictionary) -> float:
	var telegraph := float(attack.get("telegraph", 0.0))
	var commit := float(attack.get("commit_at", -1.0))
	if commit < 0.0:
		return telegraph
	return maxf(telegraph - commit, 0.0)

# --- construction ---

static func _context(beat: Dictionary, def: Dictionary, phase: int, config: RunConfig) -> Dictionary:
	var telegraph := BossDefs.telegraph_for(def, phase)
	var telegraph_scale := float(beat.get("telegraph_scale", 1.0))
	if not is_equal_approx(telegraph_scale, 1.0):
		var floor_seconds := float(config.boss_telegraph_min) if config != null else 0.0
		telegraph = maxf(telegraph * telegraph_scale, floor_seconds)
	var speed := float(def.get("projectile_speed", 26.0))
	var speed_scale := float(beat.get("speed_scale", 1.0))
	if not is_equal_approx(speed_scale, 1.0):
		speed *= speed_scale
		if config != null and "boss_signature_speed_max" in config:
			speed = minf(speed, float(config.boss_signature_speed_max))
	var signature: StringName = beat.get("signature", SIG_PLAIN)
	return {
		"variant": beat.get("variant", &"orb"),
		"telegraph": telegraph,
		"speed": maxf(speed, 0.1),
		"from_z": _boss_z(config),
		"boss_kind": def.get("kind", &""),
		"signature": signature
	}

static func _attack(ctx: Dictionary, fire_mask: int, telegraph_mask: int) -> Dictionary:
	var candidates: Array[int] = []
	return {
		"signature": ctx.get("signature", SIG_PLAIN),
		"variant": ctx.get("variant", &"orb"),
		"boss_kind": ctx.get("boss_kind", &""),
		"telegraph_mask": telegraph_mask & LANE_ALL,
		"mask": fire_mask & LANE_ALL,
		"telegraph": float(ctx.get("telegraph", 0.0)),
		"speed": float(ctx.get("speed", 0.1)),
		"from_z": float(ctx.get("from_z", DEFAULT_BOSS_Z)),
		"commit_at": -1.0,
		"candidates": candidates,
		"head": 0,
		"heads": 1,
		"delay": 0.0
	}

## Fill in the shots and the impact reads every consumer plans against:
## impact_mask, enter / exit (seconds after the telegraph), jumpable, rollable, clear_height.
static func _finish(attack: Dictionary, config: RunConfig) -> Dictionary:
	var shots := shots_for(attack, config)
	var telegraph := float(attack.get("telegraph", 0.0))
	var mask := 0
	var enter := INF
	var exit := -INF
	var jumpable := not shots.is_empty()
	var rollable := not shots.is_empty()
	var clear_height := 0.0
	var low := INF
	for shot in shots:
		var window := pass_window(shot)
		mask |= impact_mask(shot, config)
		enter = minf(enter, telegraph + window.x)
		exit = maxf(exit, telegraph + window.y)
		jumpable = jumpable and shot_jumpable(shot)
		rollable = rollable and shot_rollable(shot)
		var y := impact_y(shot)
		clear_height = maxf(clear_height, y.y)
		low = minf(low, y.x)
	attack["shots"] = shots
	attack["impact_mask"] = mask
	attack["enter"] = enter if enter < INF else telegraph
	attack["exit"] = exit if exit > -INF else telegraph
	attack["jumpable"] = jumpable
	attack["rollable"] = rollable
	attack["clear_height"] = clear_height
	attack["low_y"] = low if low < INF else 0.0
	return attack

static func _shot(attack: Dictionary, lanes: int, keys: PackedVector2Array) -> Dictionary:
	return {
		"variant": attack.get("variant", &"orb"),
		"speed": float(attack.get("speed", 0.1)),
		"from_z": float(attack.get("from_z", DEFAULT_BOSS_Z)),
		"lanes": lanes,
		"x_keys": keys,
		"drop_height": 0.0,
		"land_at": 0.0,
		"twin": false
	}

## Flaky Test Swarm: the telegraph alternates between the two candidates for
## boss_flaky_candidate_seconds, then commits; the commit is at least boss_commit_min before fire.
static func _flaky(ctx: Dictionary, pair: Array, committed: int, config: RunConfig) -> Dictionary:
	var candidate_seconds := float(config.boss_flaky_candidate_seconds) if config != null else 0.45
	var commit_min := float(config.boss_commit_min) if config != null else 0.6
	var commit_seconds := maxf(float(ctx.get("telegraph", 0.0)), commit_min)
	var both := 0
	var candidates: Array[int] = []
	for mask: int in pair:
		both |= mask
		candidates.append(mask)
	var attack := _attack(ctx, committed, both)
	attack["telegraph"] = candidate_seconds + commit_seconds
	attack["commit_at"] = candidate_seconds
	attack["candidates"] = candidates
	attack["swap_seconds"] = float(config.boss_flaky_swap_seconds) if config != null else 0.15
	return _finish(attack, config)

## Flaky Test Swarm P3: one orb down the middle that splits into the two outer lanes when its centre
## reaches track z = -boss_scatter_split_distance.
static func _scatter(ctx: Dictionary, config: RunConfig) -> Dictionary:
	var attack := _attack(ctx, BossDefs.LANE_MIDDLE, BossDefs.LANE_MIDDLE)
	var distance := float(config.boss_scatter_split_distance) if config != null else 10.0
	var split := (-distance - float(attack["from_z"])) / maxf(float(attack["speed"]), 0.1)
	attack["split_at"] = maxf(split, 0.0)
	attack["split_mask"] = BossDefs.LANE_OUTER
	return _finish(attack, config)

## Merge Conflict Hydra: one attack per head, every head telegraphed up front on its own lane, the
## later ones fired `delay` seconds after the first.
static func _branching(ctx: Dictionary, beat: Dictionary, lanes: Array, config: RunConfig) -> Array:
	var heads: Array = beat.get("heads", [])
	var out: Array = []
	for index in lanes.size():
		var head: Dictionary = heads[index] if index < heads.size() else {}
		var mask := 1 << int(lanes[index])
		var attack := _attack(ctx, mask, mask)
		var delay := float(head.get("delay", 0.0))
		attack["telegraph"] = float(attack["telegraph"]) + delay
		attack["delay"] = delay
		attack["head"] = index
		attack["heads"] = lanes.size()
		out.append(_finish(attack, config))
	return out

## Merge Conflict Hydra: the rebase sweep, a low shot sliding from one outer lane to the other over
## the first `sweep_fraction` of its travel. The telegraph shows the whole path.
static func _sweep(ctx: Dictionary, beat: Dictionary, path: Vector2i, config: RunConfig) -> Dictionary:
	var from_mask := 1 << path.x
	var span := 0
	for lane in range(mini(path.x, path.y), maxi(path.x, path.y) + 1):
		span |= 1 << lane
	var attack := _attack(ctx, from_mask, span)
	attack["sweep_from"] = path.x
	attack["sweep_to"] = path.y
	var probe := _shot(attack, from_mask, PackedVector2Array([Vector2.ZERO]))
	attack["sweep_end"] = pass_window(probe).x * clampf(float(beat.get("sweep_fraction", DEFAULT_SWEEP_FRACTION)), 0.0, 1.0)
	return _finish(attack, config)

## Legacy Monolith: a slow wall of slabs leaving exactly one gap, which shifts once to the lane next
## to it `shift_fraction` of the way in. The telegraph shows the first gap; the attack carries both.
static func _legacy_wall(ctx: Dictionary, beat: Dictionary, gaps: Vector2i, config: RunConfig) -> Dictionary:
	var blocked := LANE_ALL & ~(1 << gaps.x)
	var attack := _attack(ctx, blocked, blocked)
	attack["gap_from"] = gaps.x
	attack["gap_to"] = gaps.y
	var probe := _shot(attack, blocked, PackedVector2Array([Vector2.ZERO]))
	attack["shift_at"] = pass_window(probe).x * clampf(float(beat.get("shift_fraction", DEFAULT_SHIFT_FRACTION)), 0.0, 1.0)
	return _finish(attack, config)

## Legacy Monolith: cracked slabs dropping onto floor shadows in one or two lanes. The shadows are
## the telegraph; each slab lands `land_fraction` of the way in and rides its shadow from there.
static func _debris(ctx: Dictionary, beat: Dictionary, mask: int, config: RunConfig) -> Dictionary:
	var attack := _attack(ctx, mask, mask)
	attack["drop_height"] = float(beat.get("drop_height", DEFAULT_DROP_HEIGHT))
	var probe := _shot(attack, mask, PackedVector2Array([Vector2.ZERO]))
	attack["land_at"] = pass_window(probe).x * clampf(float(beat.get("land_fraction", DEFAULT_LAND_FRACTION)), 0.0, 1.0)
	return _finish(attack, config)

## Unordered candidate pairs a flaky beat alternates between.
static func _candidate_pairs(beat: Dictionary) -> Array:
	var mode: StringName = beat.get("candidates", BossDefs.LANES_RANDOM_SINGLE)
	var pool: Array[int] = BossDefs.ADJACENT_LANE_MASKS if mode == BossDefs.LANES_RANDOM_ADJACENT \
		else BossDefs.SINGLE_LANE_MASKS
	var pairs: Array = []
	for a in pool.size():
		for b in range(a + 1, pool.size()):
			pairs.append([pool[a], pool[b]])
	return pairs

## Ordered tuples of distinct lanes, one per head.
static func _head_lanes(beat: Dictionary) -> Array:
	var count := clampi((beat.get("heads", []) as Array).size(), 1, LANE_COUNT)
	var out: Array = []
	_permute([], count, out)
	return out

static func _permute(prefix: Array, count: int, out: Array) -> void:
	if prefix.size() == count:
		out.append(prefix.duplicate())
		return
	for lane in LANE_COUNT:
		if prefix.has(lane):
			continue
		prefix.append(lane)
		_permute(prefix, count, out)
		prefix.pop_back()

## (from, to) lane pairs of a sweep: outer lane to outer lane, both directions.
static func _sweep_paths(beat: Dictionary) -> Array[Vector2i]:
	var paths: Array[Vector2i] = []
	for pair: Array in beat.get("paths", [[0, 2], [2, 0]]):
		paths.append(Vector2i(int(pair[0]), int(pair[1])))
	return paths

## (gap_from, gap_to) of a legacy wall: the gap moves to a neighbouring lane.
static func _gap_shifts(_beat: Dictionary) -> Array[Vector2i]:
	var shifts: Array[Vector2i] = []
	for from in LANE_COUNT:
		for to in LANE_COUNT:
			if absi(from - to) == 1:
				shifts.append(Vector2i(from, to))
	return shifts

# --- config reads ---

static func _boss_z(config: RunConfig) -> float:
	return float(config.boss_z) if config != null else DEFAULT_BOSS_Z

static func _lane_width(config: RunConfig) -> float:
	return float(config.lane_width) if config != null else DEFAULT_LANE_WIDTH

static func _hurtbox_radius(config: RunConfig) -> float:
	return float(config.hurtbox_radius) if config != null else DEFAULT_HURTBOX_RADIUS

static func _lane_x(lane: int, config: RunConfig) -> float:
	return (float(clampi(lane, 0, LANE_COUNT - 1)) - 1.0) * _lane_width(config)

static func _mask_center_x(mask: int, config: RunConfig) -> float:
	var total := 0.0
	var count := 0
	for lane in LANE_COUNT:
		if (mask & (1 << lane)) == 0:
			continue
		total += _lane_x(lane, config)
		count += 1
	return total / float(count) if count > 0 else 0.0
