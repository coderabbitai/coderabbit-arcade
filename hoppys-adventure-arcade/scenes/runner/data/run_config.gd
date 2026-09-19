extends Resource
## Authoritative Endless Runner tuning (contract §7). Never mutate the shared .tres at runtime;
## tests and overrides call duplicate() first.

@export_group("Lanes and body")
@export var lane_width := 2.0
@export var lane_change_time := 0.13
@export var hurtbox_radius := 0.4
@export var stand_height := 1.8
@export var roll_height := 0.9

@export_group("Jump and roll")
@export var gravity := 28.0
@export var jump_velocity := 9.8
@export var super_jump_velocity := 13.2
@export var jump_buffer := 0.10
@export var coyote_time := 0.06
@export var roll_duration := 0.70
@export var roll_cooldown := 0.25
@export var fast_fall_multiplier := 2.5

@export_group("Speed")
@export var base_speed := 12.0
@export var max_speed := 24.0
@export var time_to_max_speed := 165.0
@export var hard_cap_speed := 26.0
@export var tail_speed_per_minute := 1.0
@export var nitro_speed_multiplier := 1.25
@export var nitro_speed_cap := 32.0

@export_group("Health")
@export var max_hp := 2
@export var recovery_seconds := 18.0
@export var hit_iframes := 0.8
@export var caught_sequence_seconds := 1.6
@export var hit_stop_max := 0.12

@export_group("Score")
@export var base_score_rate := 10.0
@export var nitro_score_multiplier := 2.0
@export var code_review_score_multiplier := 1.5
@export var pickup_bonus := 25
@export var blast_bonus_per_hazard := 10
@export var score_rule_revision := 1

@export_group("Effects")
@export var lgtm_duration := 5.0
@export var nitro_duration := 8.0
@export var nitro_ease_down := 1.0
@export var super_jump_landing_invuln := 0.5

@export_group("Spawner")
@export var spawn_horizon_z := -90.0
@export var despawn_z := 12.0
@export var max_active_chunks := 9
@export var t_spacing_easy := 1.2
@export var t_spacing_hard := 0.85
@export var t_spacing_pursued_bonus := 0.15
@export var gap_safety := 1.02
@export var min_hazard_depth := 1.2
@export var pit_depth := 3.0
@export var blast_range_z := 60.0
@export var chunk_mirror_chance := 0.5

@export_group("Power-ups")
@export var powerup_cooldown_seconds := 10.0
@export var powerup_chance_min := 0.35
@export var powerup_chance_max := 0.55
@export var powerup_weights := {
	&"approve_shield": 25,
	&"code_review": 25,
	&"super_jump": 15,
	&"nitro": 15,
	&"auto_fix": 10,
	&"lgtm": 10
}
@export var pickup_radius := 0.35
@export var pickup_height_run := 1.0
@export var pickup_height_jump := 2.2

@export_group("Camera")
@export var camera_position := Vector3(0, 4, 8)
@export var camera_look_at := Vector3(0, 1, -8)
@export var camera_fov := 60.0
@export var camera_lateral_follow := 0.4

@export_group("Pursuer")
@export var retreat_z := 12.0
@export var approach_z := 4.5
@export var threat_ramp_seconds := 1.5

@export_group("Autopilot")
@export var autopilot_jump_lead := 0.22
@export var autopilot_roll_lead := 0.15
@export var autopilot_plan_lead := 0.6

## Seconds between forced actions at the given difficulty (contract §7).
func t_spacing(difficulty: float) -> float:
	return lerpf(t_spacing_easy, t_spacing_hard, clampf(difficulty, 0.0, 1.0))

## Chance that a chunk carries a power-up at the given difficulty (contract §7).
func powerup_chance(difficulty: float) -> float:
	return lerpf(powerup_chance_max, powerup_chance_min, clampf(difficulty, 0.0, 1.0))

## Lane index 0/1/2 -> world x (-2, 0, +2).
func lane_x(lane: int) -> float:
	return (float(lane) - 1.0) * lane_width
