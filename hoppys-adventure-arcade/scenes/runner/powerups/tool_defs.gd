extends RefCounted
## The four boss tools (contract §11.7). A tool is a pickup that auto-fires: collecting one deals
## `damage` to the boss straight away (0 when the boss's phase resists that kind) and pays
## `config.tool_bonus`. `weight` is the spawn roll; a resisting phase biases the roll toward the
## kinds it accepts. `jump_height` marks the kinds that spawn on the jump row instead of the run row
## (`config.pickup_height_jump` / `pickup_height_run`, 2.2 m / 1.0 m); `spawn_y` is the same height as
## a plain number, for tests and validators that have no RunConfig to hand.
## `kind` is also the visual scene id: powerups/visuals/<kind>_visual.tscn.

const DEFS := {
	&"review_comment": {
		"label": "Review Comment",
		"damage": 10,
		"weight": 35,
		"jump_height": false,
		"spawn_y": 1.0
	},
	&"lint_rule": {
		"label": "Lint",
		"damage": 12,
		"weight": 25,
		"jump_height": false,
		"spawn_y": 1.0
	},
	&"unit_test": {
		"label": "Unit Test",
		"damage": 15,
		"weight": 25,
		"jump_height": false,
		"spawn_y": 1.0
	},
	&"auto_fix_patch": {
		"label": "Auto-Fix",
		"damage": 20,
		"weight": 15,
		"jump_height": true,
		"spawn_y": 2.2
	}
}

static func kinds() -> Array:
	return DEFS.keys()

static func get_def(kind: StringName) -> Dictionary:
	return DEFS.get(kind, {})

static func has_kind(kind: StringName) -> bool:
	return DEFS.has(kind)

## Damage a collected tool deals to a boss phase that accepts it; 0 for an unknown kind.
static func damage(kind: StringName) -> int:
	return int(DEFS.get(kind, {}).get("damage", 0))

static func weight(kind: StringName) -> int:
	return int(DEFS.get(kind, {}).get("weight", 0))

## Display name for the HUD and the graybox tag.
static func label(kind: StringName) -> String:
	return String(DEFS.get(kind, {}).get("label", String(kind)))

## True for the kinds that spawn at jump height (contract §11.7 spawn y 2.2).
static func uses_jump_height(kind: StringName) -> bool:
	return bool(DEFS.get(kind, {}).get("jump_height", false))

## Spawn height in metres, straight off the table (contract §11.7).
static func spawn_y(kind: StringName) -> float:
	return float(DEFS.get(kind, {}).get("spawn_y", 1.0))
