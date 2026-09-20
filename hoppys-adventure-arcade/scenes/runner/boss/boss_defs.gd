extends RefCounted
## The three bosses, their attack patterns and the per-cycle escalation (contract §11.5, §11.7,
## §11.10; systems spec §10.3). Stage n fights slot `(n - 1) % 3` in cycle `c = (n - 1) / 3`, so the
## roster never ends: every lap round the three makes them faster, tougher and tighter.
## `fight_def()` is the only entry point the encounter needs; everything else reads off its result.

const RunConfig = preload("res://scenes/runner/data/run_config.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")

## Lane masks: bit i = lane index i, i.e. x -2 / 0 / +2 (contract §11.7).
const LANE_LEFT := 0b001
const LANE_MIDDLE := 0b010
const LANE_RIGHT := 0b100
const LANE_ALL := 0b111
## Both outer lanes, leaving the middle free.
const LANE_OUTER := 0b101
const LANE_LEFT_PAIR := 0b011
const LANE_RIGHT_PAIR := 0b110
## Pools the random beats draw from; a beat never repeats the previous mask while it has a choice.
const SINGLE_LANE_MASKS: Array[int] = [LANE_LEFT, LANE_MIDDLE, LANE_RIGHT]
const ADJACENT_LANE_MASKS: Array[int] = [LANE_LEFT_PAIR, LANE_RIGHT_PAIR]

## How a beat picks its lanes: a fixed mask, one random lane, or a random adjacent pair.
const LANES_FIXED: StringName = &"fixed"
const LANES_RANDOM_SINGLE: StringName = &"random_single"
const LANES_RANDOM_ADJACENT: StringName = &"random_adjacent"

## Every boss runs three phases (contract §11.10 boss_phase_thresholds).
const PHASE_COUNT := 3
## An empty accepted row means the phase takes damage from all four tools (contract §11.7).
const ACCEPTS_ALL: Array[StringName] = []

## Slot order is the stage cycle order. `telegraph` / `attack_interval` are per phase (1, 2, 3);
## `patterns` holds one beat list per phase, cycled a beat at a time; `accepted` holds the tools a
## phase takes damage from. `color` is graybox only.
const SLOTS := [
	{
		"kind": &"flaky_test_swarm",
		"name": "Flaky Test Swarm",
		"hp": 100,
		"projectile_speed": 26.0,
		"telegraph": [0.90, 0.80, 0.72],
		"attack_interval": [1.6, 1.4, 1.2],
		"tool_interval": 2.6,
		"color": Color("8fd14f"),
		"patterns": [
			[{"variant": &"orb", "lanes": LANES_RANDOM_SINGLE}],
			[{"variant": &"orb", "lanes": LANES_RANDOM_ADJACENT}],
			[
				{"variant": &"high", "lanes": LANES_FIXED, "mask": LANE_ALL},
				{"variant": &"low", "lanes": LANES_FIXED, "mask": LANE_ALL}
			]
		],
		"accepted": [ACCEPTS_ALL, ACCEPTS_ALL, ACCEPTS_ALL]
	},
	{
		"kind": &"merge_conflict_hydra",
		"name": "Merge Conflict Hydra",
		"hp": 140,
		"projectile_speed": 28.0,
		"telegraph": [0.85, 0.78, 0.70],
		"attack_interval": [1.5, 1.3, 1.1],
		"tool_interval": 2.3,
		"color": Color("d46ad4"),
		"patterns": [
			[{"variant": &"wide", "lanes": LANES_RANDOM_ADJACENT}],
			[
				{"variant": &"orb", "lanes": LANES_FIXED, "mask": LANE_OUTER},
				{"variant": &"orb", "lanes": LANES_FIXED, "mask": LANE_OUTER},
				{"variant": &"high", "lanes": LANES_FIXED, "mask": LANE_ALL}
			],
			[
				{"variant": &"wide", "lanes": LANES_RANDOM_ADJACENT},
				{"variant": &"low", "lanes": LANES_FIXED, "mask": LANE_ALL}
			]
		],
		"accepted": [ACCEPTS_ALL, [&"unit_test", &"lint_rule"], ACCEPTS_ALL]
	},
	{
		"kind": &"legacy_monolith",
		"name": "Legacy Monolith",
		"hp": 180,
		"projectile_speed": 30.0,
		"telegraph": [0.80, 0.72, 0.65],
		"attack_interval": [1.4, 1.2, 1.0],
		"tool_interval": 2.0,
		"color": Color("6a7ba2"),
		"patterns": [
			[{"variant": &"low", "lanes": LANES_FIXED, "mask": LANE_ALL}],
			[
				{"variant": &"wide", "lanes": LANES_FIXED, "mask": LANE_LEFT_PAIR},
				{"variant": &"wide", "lanes": LANES_FIXED, "mask": LANE_RIGHT_PAIR},
				{"variant": &"high", "lanes": LANES_FIXED, "mask": LANE_ALL}
			],
			[
				{"variant": &"low", "lanes": LANES_FIXED, "mask": LANE_ALL},
				{"variant": &"high", "lanes": LANES_FIXED, "mask": LANE_ALL},
				{"variant": &"orb", "lanes": LANES_RANDOM_SINGLE}
			]
		],
		"accepted": [ACCEPTS_ALL, [&"auto_fix_patch", &"review_comment"], [&"unit_test"]]
	}
]

## Stage 1 is the first fight; the index never resets inside a run (contract §11.1).
static func slot(stage_index: int) -> int:
	return (maxi(stage_index, 1) - 1) % SLOTS.size()

## How many full laps of the roster this stage is on; every escalation is a power of the cycle.
static func cycle(stage_index: int) -> int:
	@warning_ignore("integer_division")
	return (maxi(stage_index, 1) - 1) / SLOTS.size()

## The unscaled table row for a stage.
static func base_def(stage_index: int) -> Dictionary:
	return SLOTS[slot(stage_index)]

static func boss_kind(stage_index: int) -> StringName:
	var value: StringName = base_def(stage_index).get("kind", &"")
	return value

static func boss_name(stage_index: int) -> String:
	return String(base_def(stage_index).get("name", ""))

static func color(kind: StringName) -> Color:
	for entry in SLOTS:
		if entry.get("kind", &"") == kind:
			return entry.get("color", Color("ffffff"))
	return Color("ffffff")

## The fight this stage runs: the table row with the cycle escalation of contract §11.10 applied
## (HP up, projectile speed up to a cap, telegraph / attack interval / tool interval down to floors).
## `config` supplies every growth factor and floor; the beat lists and accepted tools do not scale.
## A null config returns the unscaled cycle 0 row, which is what a bare table read should mean.
static func fight_def(stage_index: int, config: RunConfig) -> Dictionary:
	var index := maxi(stage_index, 1)
	var base := base_def(index)
	var c := cycle(index) if config != null else 0
	var hp_growth := float(config.boss_hp_growth) if config != null else 1.0
	var hp_scale := float(config.boss_hp_scale) if config != null and "boss_hp_scale" in config else 1.0
	var speed_growth := float(config.boss_projectile_speed_growth) if config != null else 1.0
	var speed_max := float(config.boss_projectile_speed_max) if config != null else INF
	var telegraph_growth := float(config.boss_telegraph_growth) if config != null else 1.0
	var telegraph_min := float(config.boss_telegraph_min) if config != null else 0.0
	var interval_growth := float(config.boss_attack_interval_growth) if config != null else 1.0
	var interval_min := float(config.boss_attack_interval_min) if config != null else 0.0
	var tool_growth := float(config.boss_tool_interval_growth) if config != null else 1.0
	var tool_min := float(config.boss_tool_interval_min) if config != null else 0.0
	var telegraphs: Array[float] = []
	for value in base.get("telegraph", []):
		telegraphs.append(maxf(float(value) * pow(telegraph_growth, c), telegraph_min))
	var intervals: Array[float] = []
	for value in base.get("attack_interval", []):
		intervals.append(maxf(float(value) * pow(interval_growth, c), interval_min))
	return {
		"kind": base.get("kind", &""),
		"name": base.get("name", ""),
		"stage_index": index,
		"slot": slot(index),
		"cycle": c,
		"phase_count": PHASE_COUNT,
		"hp": maxi(int(round(float(base.get("hp", 100)) * pow(hp_growth, c) * hp_scale)), 1),
		"projectile_speed": minf(float(base.get("projectile_speed", 26.0)) * pow(speed_growth, c), speed_max),
		"telegraph": telegraphs,
		"attack_interval": intervals,
		"tool_interval": maxf(float(base.get("tool_interval", 2.0)) * pow(tool_growth, c), tool_min),
		"color": base.get("color", Color("ffffff")),
		"patterns": base.get("patterns", []),
		"accepted": base.get("accepted", [])
	}

## Telegraph seconds for a 1-based phase, clamped to the rows the def carries.
static func telegraph_for(def: Dictionary, phase: int) -> float:
	return _phase_value(def, &"telegraph", phase, 0.8)

## Seconds between attacks for a 1-based phase.
static func attack_interval_for(def: Dictionary, phase: int) -> float:
	return _phase_value(def, &"attack_interval", phase, 1.5)

## The beat list a 1-based phase cycles; each beat is {variant, lanes[, mask]}.
static func pattern_for(def: Dictionary, phase: int) -> Array:
	var patterns: Array = def.get("patterns", [])
	if patterns.is_empty():
		return []
	var row: Array = patterns[clampi(phase - 1, 0, patterns.size() - 1)]
	return row

## The tools a 1-based phase takes damage from; an empty table row means all four (contract §11.7).
static func accepted_tools(def: Dictionary, phase: int) -> Array[StringName]:
	var accepted: Array = def.get("accepted", [])
	var row: Array = []
	if not accepted.is_empty():
		row = accepted[clampi(phase - 1, 0, accepted.size() - 1)]
	var out: Array[StringName] = []
	if row.is_empty():
		for kind in ToolDefs.kinds():
			var candidate: StringName = kind
			out.append(candidate)
		return out
	for kind in row:
		var candidate: StringName = kind
		out.append(candidate)
	return out

## Does this phase take damage from this tool? A resisting phase reports tool_collected(kind, 0).
static func accepts(def: Dictionary, phase: int, tool_kind: StringName) -> bool:
	return accepted_tools(def, phase).has(tool_kind)

static func _phase_value(def: Dictionary, key: StringName, phase: int, fallback: float) -> float:
	var values: Array = def.get(key, [])
	if values.is_empty():
		return fallback
	return float(values[clampi(phase - 1, 0, values.size() - 1)])
