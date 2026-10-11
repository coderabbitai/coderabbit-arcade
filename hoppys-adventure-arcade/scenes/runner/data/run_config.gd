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
@export var caught_sequence_seconds := 3.0
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
## Seconds after every `stage_started` in which no blocking hazard may reach the player, because the
## stage banner is covering the lanes (contract §11.1). The banner itself must be gone by
## `stage_banner_clear_seconds − stage_banner_reaction_seconds`.
@export var stage_banner_clear_seconds := 3.5
## Seconds of reaction the player is owed the moment the window above ends: the nearest blocking
## hazard is still this much travel away (contract §11.1).
@export var stage_banner_reaction_seconds := 1.0

@export_group("Boss")
@export var boss_z := -14.0
@export var boss_sway_amplitude := 2.4
@export var boss_sway_period := 3.2
## The full boss intro cinematic, played the first time a run meets each boss (contract 2.6 §11.14).
@export var boss_intro_seconds := 5.0
## The intro on every later meeting in the run, a checkpoint retry included; played as
## min(boss_intro_short_seconds, boss_intro_seconds).
@export var boss_intro_short_seconds := 2.5
## The defeat cinematic the first time a run beats each boss, and on every later defeat (played as
## min(short, full)). It holds the boss phase open, so stage_clear waits it out.
@export var boss_defeat_seconds := 3.6
@export var boss_defeat_short_seconds := 2.0
## An intro can be skipped once it has played this long (a defeat never can); a skip jumps to the
## last boss_cinematic_skip_tail seconds, so the camera return still plays.
@export var boss_cinematic_skip_after := 0.5
@export var boss_cinematic_skip_tail := 0.3
## The corridor eases to this fraction of its speed while a cinematic holds the player.
@export var boss_cinematic_speed_scale := 0.25
## The defeat's time factor (boss_time_factor, never Engine.time_scale): a 0.05 hit-stop for
## boss_hitstop_seconds, then slow-mo from boss_slowmo_factor eased back to 1 over boss_slowmo_seconds.
@export var boss_hitstop_seconds := 0.12
@export var boss_slowmo_seconds := 0.8
@export var boss_slowmo_factor := 0.4
## The retreat outro only; a defeat holds for its cinematic instead (contract 2.6 §11.14).
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
## Signature attacks (contract 2.4 §11.6, §11.10). A flaky telegraph alternates between two candidate
## lanes for this long before it commits to one of them.
@export var boss_flaky_candidate_seconds := 0.45
## Seconds per candidate while a flaky telegraph alternates (cosmetic cadence, carried to the visuals).
@export var boss_flaky_swap_seconds := 0.15
## A flaky telegraph commits at least this long before it fires, so the telegraph-plus-travel and the
## jump-launch budgets of runner_boss_validator.gd B1 / B3 hold measured from the commit.
@export var boss_commit_min := 0.60
## The scatter orb splits when its centre is this many metres ahead of the player (track z).
@export var boss_scatter_split_distance := 10.0
## Cap on a signature beat's own speed after its speed_scale (the force push runs above the
## projectile cap on purpose, and pays for it with a longer telegraph).
@export var boss_signature_speed_max := 44.0
## Reaction floor every commit, split, gap shift, sweep and debris drop must leave before the latest
## moment its cheapest answer can start (runner_boss_validator.gd B6).
@export var boss_signature_reaction_min := 0.35

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
