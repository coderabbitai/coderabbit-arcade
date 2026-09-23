extends RefCounted
## Authoritative hazard table (contract §8). `kind` is also the visual scene id
## (hazards/visuals/<kind>_visual.tscn); `variant` selects the per-variant overrides below.
## `size` is the BoxShape3D W x H x D in metres (depth along Z); `y_min`/`y_max` is the world y range
## the hitbox occupies; `lanes_wide` is 1, 2 or 3 lanes.

const DEFS := {
	&"pr_backlog_low": {
		"size": Vector3(5.6, 1.0, 1.2),
		"y_min": 0.0,
		"y_max": 1.0,
		"lanes_wide": 3,
		"dodge_hint": &"JUMP"
	},
	&"pr_backlog_high": {
		"size": Vector3(5.6, 1.8, 1.2),
		"y_min": 1.1,
		"y_max": 2.9,
		"lanes_wide": 3,
		"dodge_hint": &"ROLL"
	},
	&"bug_swarm": {
		"size": Vector3(1.6, 0.9, 1.2),
		"y_min": 0.0,
		"y_max": 0.9,
		"lanes_wide": 1,
		"dodge_hint": &"JUMP_OR_LANE"
	},
	&"merge_conflict": {
		"size": Vector3(3.6, 1.0, 1.2),
		"y_min": 0.0,
		"y_max": 1.0,
		"lanes_wide": 2,
		"dodge_hint": &"JUMP_OR_LANE"
	},
	&"deprecated_pit": {
		"size": Vector3(5.6, 0.4, 3.0),
		"y_min": -0.2,
		"y_max": 0.2,
		"lanes_wide": 3,
		"dodge_hint": &"JUMP",
		"variants": {
			&"full": {},
			&"two_lane": {
				"size": Vector3(3.6, 0.4, 3.0),
				"lanes_wide": 2,
				"dodge_hint": &"JUMP_OR_LANE"
			}
		}
	},
	&"laser_grid": {
		"size": Vector3(5.6, 0.4, 1.2),
		"y_min": 0.1,
		"y_max": 0.5,
		"lanes_wide": 3,
		"dodge_hint": &"JUMP",
		"variants": {
			&"ground": {},
			&"mid": {
				"size": Vector3(5.6, 0.3, 1.2),
				"y_min": 1.0,
				"y_max": 1.3,
				"dodge_hint": &"ROLL_OR_JUMP"
			},
			&"high": {
				"size": Vector3(5.6, 0.4, 1.2),
				"y_min": 1.1,
				"y_max": 1.5,
				"dodge_hint": &"ROLL"
			},
			&"timed": {
				"dodge_hint": &"TIMED",
				"timed": true,
				"on_seconds": 1.2,
				"off_seconds": 0.3,
				"period": 3.0,
				"states": [&"ground", &"off", &"high", &"off"],
				"telegraph_seconds": 0.4,
				"state_bounds": {
					&"ground": Vector2(0.1, 0.5),
					&"high": Vector2(1.1, 1.5)
				}
			}
		}
	},
	&"comment_flood": {
		"size": Vector3(3.6, 4.0, 1.2),
		"y_min": 0.0,
		"y_max": 4.0,
		"lanes_wide": 2,
		"dodge_hint": &"LANE"
	},
	&"build_shockwave": {
		"size": Vector3(5.6, 0.5, 1.2),
		"y_min": 0.0,
		"y_max": 0.5,
		"lanes_wide": 3,
		"dodge_hint": &"JUMP"
	},
	## Boss projectiles (contract §11.6). One kind, four variants; hazards/projectile.gd adds the
	## +Z motion and the `closing_speed` the visual reads. The base entry is the `orb` shape, so a
	## projectile spawned without a variant is still a legal single-lane hazard.
	&"projectile": {
		"size": Vector3(1.6, 0.9, 1.2),
		"y_min": 0.0,
		"y_max": 0.9,
		"lanes_wide": 1,
		"dodge_hint": &"JUMP_OR_LANE",
		"variants": {
			&"orb": {},
			&"low": {
				"size": Vector3(5.6, 0.9, 1.2),
				"lanes_wide": 3,
				"dodge_hint": &"JUMP"
			},
			&"high": {
				"size": Vector3(5.6, 0.4, 1.2),
				"y_min": 1.1,
				"y_max": 1.5,
				"lanes_wide": 3,
				"dodge_hint": &"ROLL"
			},
			&"wide": {
				"size": Vector3(3.6, 1.0, 1.2),
				"y_min": 0.0,
				"y_max": 1.0,
				"lanes_wide": 2,
				"dodge_hint": &"LANE"
			}
		}
	}
}

## The boss projectile kind and its variants (contract §11.6), in table order.
const PROJECTILE_KIND: StringName = &"projectile"
const PROJECTILE_VARIANTS: Array[StringName] = [&"orb", &"low", &"high", &"wide"]

## Dodge hints whose only safe answer is rolling (used for standing clearance and the bot).
const ROLL_HINTS := [&"ROLL", &"ROLL_OR_JUMP"]
## Dodge hints a jump clears.
const JUMP_HINTS := [&"JUMP", &"JUMP_OR_LANE", &"ROLL_OR_JUMP"]

## Base entry plus variant overrides flattened into one dictionary. Unknown kinds return {}.
static func get_def(kind: StringName, variant: StringName = &"") -> Dictionary:
	if not DEFS.has(kind):
		return {}
	var base: Dictionary = DEFS[kind]
	var merged := base.duplicate(true)
	merged.erase("variants")
	if variant != &"" and base.has("variants") and base["variants"].has(variant):
		var overrides: Dictionary = base["variants"][variant]
		for key in overrides:
			merged[key] = overrides[key]
	merged["kind"] = kind
	merged["variant"] = variant
	return merged

## Hitbox centre offset (y) relative to the hazard root, derived from the y range.
static func center_y(def: Dictionary) -> float:
	return (float(def.get("y_min", 0.0)) + float(def.get("y_max", 0.0))) * 0.5

static func is_timed(def: Dictionary) -> bool:
	return bool(def.get("timed", false))

## True for the boss projectile kind, whatever its variant.
static func is_projectile(kind: StringName) -> bool:
	return kind == PROJECTILE_KIND

## How many lanes one hitbox of this def covers (1, 2 or 3); the boss encounter groups a lane mask
## into that many lanes per projectile.
static func lanes_wide(def: Dictionary) -> int:
	return maxi(int(def.get("lanes_wide", 1)), 1)

static func kinds() -> Array:
	return DEFS.keys()
