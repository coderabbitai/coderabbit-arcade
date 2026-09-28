extends "res://scenes/runner/hazards/hazard.gd"
## A boss projectile (contract §11.6, systems spec §10.4): the one hazard that moves on its own.
## Everything else — the BoxShape3D from hazard_defs, the runner_hazards group, the hit-once rule,
## the visual mount and Auto-Fix's clear() — comes straight from hazard.gd. The boss encounter sets
## `kind`, `variant` and `closing_speed` before add_child, so the visual receives all three with the
## other contract §5.2 base vars, before on_spawned().

## Fallback until setup() supplies the config (contract §7 despawn_z).
const DEFAULT_DESPAWN_Z := 12.0

## Metres per second toward the player, along +Z. The player stands at z = 0 and the corridor is a
## treadmill, so this is also the closing speed the autopilot and the visual plan against.
var closing_speed := 0.0

func _ready() -> void:
	super()
	# hazard.gd only ticks the timed laser (set_physics_process(_timed)); a projectile always moves.
	set_physics_process(true)

## Travel and despawn. This replaces hazard.gd's timed-laser tick rather than extending it: a
## projectile is never a timed hazard, so there is no state machine to run here.
func _physics_process(delta: float) -> void:
	position.z += closing_speed * delta
	if position.z > despawn_z():
		queue_free()

## config.despawn_z once setup() has run, the contract default before that.
func despawn_z() -> float:
	return float(config.despawn_z) if config != null else DEFAULT_DESPAWN_Z

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
## on_spawned() because hazard.gd mounts, applies, then calls the hook.
func _apply_visual_vars() -> void:
	super()
	if is_instance_valid(visual) and &"closing_speed" in visual:
		visual.set(&"closing_speed", closing_speed)
