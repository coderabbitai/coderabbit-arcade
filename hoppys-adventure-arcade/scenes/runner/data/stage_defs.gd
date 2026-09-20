extends RefCounted
## Stage -> boss slot, cycle, kind and name, plus the three per-stage curves the StageManager and
## the SpeedController read (contract §11.1, §11.2, §11.10). Static only: tests and the boss
## encounter ask for a stage's shape without a live StageManager.
##
## Stage index is 1-based and never resets. Slot = (index - 1) % 3 picks the boss, cycle
## = (index - 1) / 3 (integer division) drives the escalation the boss defs apply.

const RunConfig = preload("res://scenes/runner/data/run_config.gd")

## Boss rotation, in slot order (contract §11.5).
const BOSS_KINDS: Array[StringName] = [
	&"flaky_test_swarm",
	&"merge_conflict_hydra",
	&"legacy_monolith"
]

## kind -> the display name `stage_started` carries (contract §11.4).
const BOSS_NAMES := {
	&"flaky_test_swarm": &"Flaky Test Swarm",
	&"merge_conflict_hydra": &"Merge Conflict Hydra",
	&"legacy_monolith": &"Legacy Monolith"
}

## Contract §7 fallbacks, used only when a caller has no config yet.
const DEFAULT_STAGE_BASE_DISTANCE := 900.0
const DEFAULT_STAGE_DISTANCE_STEP := 250.0
const DEFAULT_STAGE_DISTANCE_MAX := 2000.0
const DEFAULT_STAGE_SPEED_STEP := 1.0
const DEFAULT_STAGE_SPEED_BONUS_MAX := 6.0
const DEFAULT_STAGE_DIFFICULTY_STEP := 0.25

## Stages below 1 are read as stage 1, so a caller that asks before begin() still gets slot 0.
static func normalize_index(index: int) -> int:
	return maxi(index, 1)

static func boss_slot(index: int) -> int:
	return (normalize_index(index) - 1) % BOSS_KINDS.size()

static func cycle(index: int) -> int:
	@warning_ignore("integer_division")
	var c := (normalize_index(index) - 1) / BOSS_KINDS.size()
	return c

static func boss_kind(index: int) -> StringName:
	return BOSS_KINDS[boss_slot(index)]

static func boss_name(index: int) -> StringName:
	return StringName(BOSS_NAMES.get(boss_kind(index), &""))

## Metres per second added to base, max and hard cap for this stage (contract §11.2).
static func speed_bonus(index: int, config: RunConfig) -> float:
	var step := _number(config, &"stage_speed_step", DEFAULT_STAGE_SPEED_STEP)
	var cap := _number(config, &"stage_speed_bonus_max", DEFAULT_STAGE_SPEED_BONUS_MAX)
	return clampf(step * float(normalize_index(index) - 1), 0.0, maxf(cap, 0.0))

## The lower bound the difficulty curve can never fall below on this stage (contract §11.2).
static func difficulty_floor(index: int, config: RunConfig) -> float:
	var step := _number(config, &"stage_difficulty_step", DEFAULT_STAGE_DIFFICULTY_STEP)
	return clampf(step * float(normalize_index(index) - 1), 0.0, 1.0)

## Metres of RUN phase this stage asks for before the drain begins (contract §11.10).
static func distance_target(index: int, config: RunConfig) -> float:
	var base := _number(config, &"stage_base_distance", DEFAULT_STAGE_BASE_DISTANCE)
	var step := _number(config, &"stage_distance_step", DEFAULT_STAGE_DISTANCE_STEP)
	var cap := _number(config, &"stage_distance_max", DEFAULT_STAGE_DISTANCE_MAX)
	return minf(base + step * float(normalize_index(index) - 1), cap)

## A named float off a config that may be null or an older resource.
static func _number(config: RunConfig, property: StringName, fallback: float) -> float:
	if config == null or not (property in config):
		return fallback
	var value: Variant = config.get(property)
	if value is int or value is float:
		return float(value)
	return fallback
