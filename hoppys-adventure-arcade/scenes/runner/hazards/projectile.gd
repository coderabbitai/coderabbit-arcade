extends "res://scenes/runner/hazards/hazard.gd"
## A boss projectile (contract §11.6, systems spec §10.4): the one hazard that moves on its own.
## Everything else — the BoxShape3D from hazard_defs, the runner_hazards group, the hit-once rule,
## the visual mount and Auto-Fix's clear() — comes straight from hazard.gd. The boss encounter sets
## `kind`, `variant` and `closing_speed` before add_child, so the visual receives all three with the
## other contract §5.2 base vars, before on_spawned().
##
## Contract 2.4: a signature shot also carries `motion` (a boss_attacks.gd shot dictionary), and its
## x and y then follow that motion over `age`, the seconds since it was fired. z always advances at
## `closing_speed`, so every straight v2.0 shot flies exactly as before; `lane_mask_at(t)` /
## `y_range_at(t)` / `impact_lane_mask()` are the motion API the planner and the validator share.

const BossAttacks = preload("res://scenes/runner/boss/boss_attacks.gd")

## Fallback until setup() supplies the config (contract §7 despawn_z).
const DEFAULT_DESPAWN_Z := 12.0

## Metres per second toward the player, along +Z. The player stands at z = 0 and the corridor is a
## treadmill, so this is also the closing speed the autopilot and the visual plan against.
var closing_speed := 0.0
## Contract 2.4 §11.6: which boss fired this shot (&"" for one spawned outside a fight), and the
## attack signature it belongs to (&"" for a plain beat), so a visual can give each its own look.
var boss_kind: StringName = &""
var signature: StringName = &""
## The boss_attacks.gd shot this projectile flies: {variant, speed, from_z, lanes, x_keys,
## drop_height, land_at, twin}. Empty for a plain straight shot (and for any hand-made one).
var motion := {}
## Seconds since fire, advanced on the same physics delta as the z travel.
var age := 0.0

func _ready() -> void:
	super()
	# hazard.gd only ticks the timed laser (set_physics_process(_timed)); a projectile always moves.
	set_physics_process(true)

## Travel and despawn. This replaces hazard.gd's timed-laser tick rather than extending it: a
## projectile is never a timed hazard, so there is no state machine to run here.
func _physics_process(delta: float) -> void:
	age += delta
	position.z += closing_speed * delta
	if not motion.is_empty():
		position.x = BossAttacks.x_at(motion, age)
		position.y = BossAttacks.y_offset_at(motion, age)
	if position.z > despawn_z():
		queue_free()

## config.despawn_z once setup() has run, the contract default before that.
func despawn_z() -> float:
	return float(config.despawn_z) if config != null else DEFAULT_DESPAWN_Z

## Lanes (bit i = lane i) the hitbox covers `t` seconds after fire. A straight shot never changes
## lanes, so it answers with where it is now.
func lane_mask_at(t: float) -> int:
	if motion.is_empty():
		return lanes_mask()
	return BossAttacks.lane_mask_at(motion, t, config)

## World y range (min, max) of the hitbox `t` seconds after fire.
func y_range_at(t: float) -> Vector2:
	if motion.is_empty():
		var def_range := Vector2(float(def.get("y_min", 0.0)), float(def.get("y_max", 0.0)))
		return def_range + Vector2(position.y, position.y)
	return BossAttacks.y_range_at(motion, t)

## The lanes this shot will cover while it passes the player: what a dodge has to answer, and what
## the tool-lane rule treats as blocked (a sweep or a split shot is not where it will hit yet).
func impact_lane_mask() -> int:
	if motion.is_empty():
		return lanes_mask()
	return BossAttacks.impact_mask(motion, config)

## The player took the hit. hazard.gd stops the hitbox and the motion (hit-once), and a projectile
## has no chunk to carry it off screen, so it goes at the end of the frame — after on_hit_player().
func hit_player(player: Node) -> void:
	var was_blocking := is_blocking()
	super(player)
	if was_blocking and not is_blocking():
		queue_free()

## Auto-Fix cleared it, or the fight ended. Same reasoning as hit_player(): a cleared projectile
## stops processing, so nothing else would ever despawn it.
func clear() -> void:
	var was_active := active
	super()
	if was_active:
		queue_free()

## hazard.gd's contract §5.2 base vars plus `closing_speed` (contract §11.6), all set before
## on_spawned() because hazard.gd mounts, applies, then calls the hook. Contract 2.4: a visual gets
## the real variant only when it declares `signature_variants := true`; any other visual is handed
## the base look the variant maps to (hazard_defs.projectile_look), so a signature shot is never
## invisible. `projectile_variant`, `boss_kind`, `signature` and `motion` go to whoever declares them.
func _apply_visual_vars() -> void:
	super()
	if not is_instance_valid(visual):
		return
	if &"closing_speed" in visual:
		visual.set(&"closing_speed", closing_speed)
	var opted_in := &"signature_variants" in visual and bool(visual.get(&"signature_variants"))
	if not opted_in and &"variant" in visual:
		visual.set(&"variant", HazardDefs.projectile_look(variant))
	var extras := {
		&"projectile_variant": variant,
		&"boss_kind": boss_kind,
		&"signature": signature,
		&"motion": motion
	}
	for key in extras:
		if key in visual:
			visual.set(key, extras[key])
