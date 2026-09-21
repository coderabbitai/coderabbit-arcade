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
## Contract §11.2 lowered this from 165 s so the v2 ramp reaches the cap inside a first stage.
@export var time_to_max_speed := 100.0
@export var hard_cap_speed := 26.0
@export var tail_speed_per_minute := 1.0
@export var nitro_speed_multiplier := 1.25
@export var nitro_speed_cap := 38.0
## Metres per second added to base/max/hard cap per stage beyond the first (contract §11.2).
@export var stage_speed_step := 1.0
@export var stage_speed_bonus_max := 6.0

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

@export_group("Stages")
## Metres of RUN phase in stage 1; every later stage adds the step, capped at the max (§11.10).
@export var stage_base_distance := 900.0
@export var stage_distance_step := 250.0
@export var stage_distance_max := 2000.0
## Difficulty floor added per stage beyond the first, clamped to 1.0 (contract §11.2).
@export var stage_difficulty_step := 0.25
## Metres before the target where the spawner stops placing new chunks and the corridor drains.
@export var stage_drain_distance := 120.0
## Hard stop on the drain: remaining blocking hazards are cleared silently, with no dodge or bonus.
@export var stage_drain_timeout := 6.0
## A blocking hazard nearer than this (track z) still holds the drain open.
@export var stage_clear_line_z := 8.0
@export var stage_clear_seconds := 3.0
@export var stage_clear_bonus_base := 400
@export var stage_clear_bonus_per_stage := 150

@export_group("Turn")
@export var turn_seconds := 2.4
## Seconds of warning turn_incoming gives before the bend is expected to start (contract §11.4).
@export var turn_warning_seconds := 3.0
## Graybox fallback only: the yaw the TurnRig sweeps when the corridor has no set_turn (§11.9).
@export var turn_yaw_degrees := 90.0
@export var turn_camera_yaw_degrees := 55.0
@export var turn_camera_bank_degrees := 12.0
## Fractions of the bend the camera swing spends ramping to the peak and returning from it; it
## holds at the peak in between (contract §11.9).
@export var turn_swing_in_fraction := 0.3
@export var turn_swing_out_fraction := 0.3

@export_group("Boss")
@export var boss_z := -14.0
@export var boss_sway_amplitude := 2.4
@export var boss_sway_period := 3.2
@export var boss_intro_seconds := 3.0
@export var boss_outro_seconds := 1.0
@export var boss_timeout_seconds := 55.0
## HP fractions that open phases 1, 2 and 3 (contract §11.10).
@export var boss_phase_thresholds: Array[float] = [1.0, 0.66, 0.33]
## Per-cycle escalation, where cycle c = (stage_index - 1) / 3 (contract §11.10).
@export var boss_hp_growth := 1.35
## Test/tuning multiplier applied to every boss's base HP before the cycle growth; 1.0 in play.
@export var boss_hp_scale := 1.0
@export var boss_projectile_speed_growth := 1.08
@export var boss_projectile_speed_max := 34.0
@export var boss_telegraph_growth := 0.88
@export var boss_telegraph_min := 0.60
@export var boss_attack_interval_growth := 0.90
@export var boss_attack_interval_min := 0.55
@export var boss_kill_bonus_base := 600
@export var boss_kill_bonus_per_stage := 200
## A timed-out boss pays the kill bonus times this ratio, scaled by the damage it took.
@export var boss_retreat_bonus_ratio := 0.35

@export_group("Tools")
@export var boss_tool_spawn_z := -55.0
@export var boss_tool_interval_growth := 0.93
@export var boss_tool_interval_min := 1.4
## A fight never goes longer than this without a tool in flight.
@export var boss_tool_guarantee_seconds := 4.0
## A tool lane needs this much clear z to the nearest live projectile.
@export var boss_tool_lane_clearance := 3.0
## Share of the tool roll pushed onto the kinds the current boss phase accepts.
@export var boss_shield_tool_bias := 0.7
@export var tool_bonus := 20

@export_group("Pursuit")
## pursuit_alert switches to &"critical" once the recovery timer drops below this (contract §11.4).
@export var pursuit_critical_seconds := 5.0
@export var pursuer_distance_epsilon := 0.01

@export_group("Autopilot")
@export var autopilot_jump_lead := 0.22
@export var autopilot_roll_lead := 0.15
@export var autopilot_plan_lead := 0.6
## Extra seconds the bot acts ahead of a telegraphed projectile arrival (contract §11.10).
@export var autopilot_telegraph_lead := 0.12
## 0 ignores tools, 1 takes every safe tool (contract §11.10).
@export var autopilot_tool_greed := 1.0

## Seconds between forced actions at the given difficulty (contract §7).
func t_spacing(difficulty: float) -> float:
	return lerpf(t_spacing_easy, t_spacing_hard, clampf(difficulty, 0.0, 1.0))

## Chance that a chunk carries a power-up at the given difficulty (contract §7).
func powerup_chance(difficulty: float) -> float:
	return lerpf(powerup_chance_max, powerup_chance_min, clampf(difficulty, 0.0, 1.0))

## Lane index 0/1/2 -> world x (-2, 0, +2).
func lane_x(lane: int) -> float:
	return (float(lane) - 1.0) * lane_width
