extends Node3D
## Base for boss/visuals/<kind>_visual.tscn (contract §11.5). The backend sets every var below
## before calling on_spawned(), mounts the visual under BossArena/Boss at (0, 2.6, hover_z) and
## frees it after boss_outro_seconds; the visual never frees itself and never moves the Boss node.
## The boss has no hitbox: nothing here can damage the player, so the envelope is a drawing budget,
## not a collision one — <= 7 m wide x 4.5 m tall x 3 m deep, bottom edge never below y 1.6,
## <= 40 draw calls at peak. The hover sway is the visual's own job, in _process (PAUSABLE).
@warning_ignore_start("unused_parameter")

## flaky_test_swarm, merge_conflict_hydra or legacy_monolith.
var kind: StringName = &""
## Display name for a name plate, e.g. "Flaky Test Swarm".
var boss_name := ""
var max_hp := 0
## How many phases this fight has (3 today, contract §11.10 boss_phase_thresholds).
var phase_count := 3
## World z the Boss node hovers at (config.boss_z, -14 by default).
var hover_z := 0.0
## Suggested sway for the idle hover, in metres and seconds (config.boss_sway_*).
var sway_amplitude := 0.0
var sway_period := 1.0

## After the vars above are set, once per fight; reset every tween and particle.
func on_spawned() -> void:
	pass

## On boss_phase_changed: 1-based, raised at the 66 % and 33 % HP thresholds.
func set_phase(phase: int) -> void:
	pass

## On boss_health_changed, including the first one at full HP.
func set_health(hp: int, max_health: int) -> void:
	pass

## On boss_attack_telegraph, `seconds` before the projectiles are fired. `lane_mask` bit i = lane
## index i (x -2 / 0 / +2); `kind` is the projectile variant (orb, low, high, wide).
func play_telegraph(lane_mask: int, projectile_kind: StringName, seconds: float) -> void:
	pass

## At the end of the telegraph, once per beat however many projectiles it fired.
func play_attack(projectile_kind: StringName) -> void:
	pass

## A tool landed for `damage` points.
func play_hit(tool_kind: StringName, damage: int) -> void:
	pass

## A tool this phase resists was collected (damage 0).
func play_resist(tool_kind: StringName) -> void:
	pass

## HP reached 0; the backend frees this node after boss_outro_seconds.
func play_defeat() -> void:
	pass

## The fight timed out; same lifetime as play_defeat().
func play_retreat() -> void:
	pass

@warning_ignore_restore("unused_parameter")
