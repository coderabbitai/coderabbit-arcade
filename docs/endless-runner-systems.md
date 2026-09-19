# Endless Runner — Systems Specification (backend)

Version 1.0 · 2026-09-19 · Companion to `docs/endless-runner-contract.md` (the contract wins on any conflict).

This is the implementation specification for the backend of the Endless Runner. It is written so an
implementer can build each file without further design decisions, and so a validator can check the
result against it line by line. Paths are relative to `hoppys-adventure-arcade/`.

## 1. Frame of reference and motion

- World forward is −Z. The player stands at z = 0 and only moves in X (lanes) and Y (jump). Chunks
  (and every hazard/power-up inside them) move toward +Z at the authoritative `speed` owned by
  `SpeedController`. Distance travelled = ∫ speed dt.
- Lane k ∈ {−1, 0, +1} is centred at x = 2k. The player's capsule radius is 0.4, so a hazard whose
  x-extent is ±0.8 around a lane centre (per-lane width 1.6) cannot touch a player in an adjacent lane.
- Physics 60 Hz. Jump apex 1.715 m, airtime 0.70 s. Per-tick travel at the Nitro cap (32 m/s) is
  0.53 m; the minimum hazard depth of 1.2 m plus the 0.8 m capsule footprint gives ≥ 3 overlapping
  ticks at any legal speed, so `Area3D` overlap detection cannot tunnel. `runner_logic.gd` asserts
  `(min_hazard_depth + 0.8) / (hard_cap × nitro_multiplier / 60) ≥ 2.0`.

### 1.1 Physics derivations (feet height y(t) = 9.8 t − 14 t²)

| Hazard top h | Feet above h for | Used by |
|---|---|---|
| 0.2 m | 0.021 – 0.679 s (0.658 s) | pit |
| 0.5 m | 0.055 – 0.645 s (0.590 s) | shockwave, ground laser |
| 0.9 m | 0.109 – 0.591 s (0.482 s) | bug swarm |
| 1.0 m | 0.124 – 0.576 s (0.452 s) | low wall, merge conflict |
| 1.3 m | 0.178 – 0.522 s (0.344 s) | mid laser (jump is the expert option) |
| 1.5 m | 0.226 – 0.474 s (0.248 s) | high laser — not counted as jumpable |

Pass time over a hazard of depth d is (d + 0.8) / v. Slack = window − pass time grows with speed, so
reaction time, not timing precision, is the limiter at high speed. A jump covers 8.4 m at 12 m/s,
16.8 m at 24 m/s, 22.4 m at 32 m/s; this drives spacing.

Reaction budget: 0.35 s choice reaction + 0.05 s input/render latency + 0.30 s worst-case manoeuvre
(two lane changes) = 0.70 s minimum. Heavy actions (jump, roll) occupy 0.70 s. Hence
`t_spacing(d) = lerp(1.2, 0.85, d)` seconds front-to-front between forced actions, and the seam rule
`prev.exit_clear + gap + next.entry_clear ≥ v × 1.02 × t_spacing(d)` (+0.15 s while PURSUED).

### 1.2 Speed and difficulty curve

`difficulty = clamp(elapsed / 165, 0, 1)`; `speed = lerp(12, 24, smoothstep(0, 1, difficulty))`; after
165 s `speed += 1.0 m/s per 60 s` until `hard_cap 26` (reached at 285 s). Difficulty stays 1.0 in the
tail. Nitro multiplies the current speed by 1.25 (capped at 32) and does not advance `elapsed`.

| t (s) | 0 | 33 | 50 | 83 | 116 | 140 | 165 | 285 |
|---|---|---|---|---|---|---|---|---|
| d | 0 | 0.20 | 0.30 | 0.50 | 0.70 | 0.85 | 1.0 | 1.0 |
| speed | 12.0 | 13.2 | 14.6 | 18.0 | 21.5 | 23.3 | 24.0 | 26.0 |

### 1.3 Camera

Camera at (0, 4, 8) looking at (0, 1, −8), vertical FOV 60° (horizontal ≈ 91.5° at 16:9), pitch
10.6° down. Nearest visible ground is z ≈ +3.3, so the player's feet are visible and a pursuer at
z = 4.5 shows head/torso only (intended). A 1 m object at z = −40 is ≈ 14 px tall at 720p: readable
range ≈ 45 m, which is 1.9 s of look-ahead at 24 m/s (≫ 0.70 s). Spawn horizon z = −90, despawn when
a chunk's back edge passes z = +12. Lateral follow `camera.x = lerp(camera.x, player.x × 0.4, 1 − exp(−8 dt))`.

## 2. File map and responsibilities

| File | Type | Responsibility |
|---|---|---|
| `scenes/runner/runner_layers.gd` | RefCounted consts | `WORLD 1, PLAYER_BODY 2, ENEMY_HITBOX 4, PLAYER_HURTBOX 8, PICKUP 16` |
| `scenes/runner/data/run_config.gd` + `run_config.tres` | Resource | Every tunable in contract §7 as `@export`; `score_rule_revision := 1` |
| `scenes/runner/runner_game.gd` + `.tscn` | Node3D facade | Contract §3–4: states, signal forwarding, mounting, `start_run`, pause, caught sequence, `_finish_run` once |
| `scenes/runner/systems/speed_controller.gd` | Node | Single speed owner; difficulty; Nitro multiplier; `begin_stop(seconds)` for the catch |
| `scenes/runner/systems/hit_manager.gd` | Node | SAFE / PURSUED / DEAD state machine (§4) |
| `scenes/runner/systems/score_manager.gd` | Node | Fractional score, multiplier composition, bonuses |
| `scenes/runner/systems/effect_manager.gd` | Node | Six power-ups, refresh-not-stack, invulnerability sources |
| `scenes/runner/systems/chunk_spawner.gd` | Node | Seeded selection, gap rule, bounded active set, despawn, power-up placement, Auto-Fix clear |
| `scenes/runner/systems/autopilot.gd` | Node | Fair / reckless bot for tests and F7 |
| `scenes/runner/systems/camera_rig.gd` | Node3D | Follow, `shake`, `punch_fov`, speed FOV boost |
| `scenes/runner/systems/debug_overlay.gd` | CanvasLayer | F3 overlay; F5 retry, F6 menu, F7 autopilot, F8 random power-up |
| `scenes/runner/systems/runner_leaderboard.gd` | RefCounted statics | ConfigFile persistence (§7) |
| `scenes/runner/player/runner_player.gd` + `.tscn` | CharacterBody3D | Lanes, jump, roll, hurtbox shapes, anim state, visual mount |
| `scenes/runner/player/runner_visual_base.gd` | Node3D base | Contract §5.1 no-op hooks |
| `scenes/runner/hazards/hazard_defs.gd` | RefCounted consts | Contract §8 table as `DEFS: Dictionary` keyed by kind, with per-variant overrides |
| `scenes/runner/hazards/hazard.gd` + `hazard.tscn` | Area3D | Hit-once hitbox, visual mount, timed states, `get_world_aabb` |
| `scenes/runner/hazards/hazard_visual_base.gd` | Node3D base | Contract §5.2 |
| `scenes/runner/powerups/power_up_defs.gd`, `power_up.gd` + `.tscn`, `power_up_visual_base.gd` | Area3D | Pickup sphere r 0.35, `collect(player)`, visual mount |
| `scenes/runner/pursuer/pursuer.gd`, `pursuer_visual_base.gd` | Node3D | Threat → z position, visual hooks |
| `scenes/runner/chunks/chunk.gd` + 19 `chunk_*.tscn` | Node3D | Authored hazard layouts (§5) |
| `scenes/runner/data/chunk_library.gd` + `chunk_library.tres` | Resource | `scenes: Array[PackedScene]` |
| `tests/runner_logic.gd`, `tests/runner_chunk_validator.gd`, `tests/runner_smoke.gd` | SceneTree scripts | §8 |
| `app/app_router.gd`, `app/audio_service.gd` | autoloads | Contract §2 / §5.6 additions |
| Graybox placeholders (frozen after PR 1): `scenes/runner/runner_menu.tscn/.gd`, `scenes/runner/ui/runner_hud.tscn/.gd`, `ui/pause_menu.tscn/.gd`, `ui/game_over.tscn/.gd` | | Minimal `Style`-themed UI so the loop is playable |

## 3. Player (`runner_player.gd`)

Per physics tick, in this order:

1. **Input** (only if `controls_enabled and game.state == &"running"`): manual press-edge detection —
   `var p := Input.is_action_pressed("jump") or Input.is_action_pressed("move_up"); if p and not held.jump: request_jump(); held.jump = p`
   and the same for roll (`roll` / `move_down`), left, right. Do not use `is_action_just_pressed`
   (fragile with injected test input). `sync_input_state()` copies current pressed state into `held`
   on resume so nothing fires on unpause.
2. **Lane tween**: `request_lane(dir)` sets `target_lane = clamp(lane + dir, 0, 2)`; if already tweening,
   queue one extra change. Interpolate `lane_t` over `lane_change_time` with ease-out; set
   `velocity.x = (desired_x − position.x) / delta`. Emit `lane_left` / `lane_right`, or `lane_blocked`
   at the edge. Call `visual.set_lane_lean(dir)` during the tween, 0 after.
3. **Gravity / jump**: `velocity.y -= gravity × delta` when airborne (×2.5 while fast-falling). Jump if
   on floor or within coyote time, or buffered within `jump_buffer`: `velocity.y = jump_velocity`
   (or `super_jump_velocity` if `effect_manager.consume_super_jump()` returns true → emit `super_jump`
   and grant invulnerability until landing + 0.5 s). One jump per airtime. Pressing roll while
   airborne = fast-fall and buffers a roll on landing.
4. **Roll**: on floor and cooldown elapsed → `rolling = true`, `roll_remaining = roll_duration`,
   `StandShape.set_deferred("disabled", true)`, `RollShape.set_deferred("disabled", false)`, emit `roll`.
   When `roll_remaining ≤ 0`: stand only if `_has_standing_clearance()`, otherwise stay crouched and
   retry each tick. Standing → swap shapes back, start cooldown, emit `roll_end`.
   `_has_standing_clearance()`: build the standing AABB grown toward −Z by `speed × 2/60 + 0.3` and
   test `intersects` against every `get_tree().get_nodes_in_group(&"runner_hazards")` that
   `is_blocking()` and whose `dodge_hint` requires rolling (`ROLL`, `ROLL_OR_JUMP`, timed in `high`).
5. `velocity.z = 0; move_and_slide()`; landing edge (`was_on_floor → is_on_floor()`) emits `land`.
6. **Animation**: choose `run` / `jump` (rising) / `fall` / `roll` / `hurt` / `dead`; call
   `visual.set_anim_state` on change only; `visual.set_run_speed(game.normalized_speed)` every tick.

Public: `setup(game)`, `set_controls_enabled(bool)`, `request_jump()`, `request_roll()`,
`request_lane(dir)`, `sync_input_state()`, `play_hurt()`, `play_dead()`, `get_hurtbox_aabb(standing) -> AABB`,
`lane`, `target_lane`, `is_rolling`, `is_airborne`.

Visual mount: `player/hoppy_runner_visual.tscn` if it exists, else a code-built capsule + two ear boxes
whose material tint changes per anim state (so graybox testers see state changes).

## 4. HitManager state machine

`enum HitState { SAFE, PURSUED, DEAD }`. Vars: `hp`, `state`, `iframe_remaining`, `recovery_remaining`,
`shield`, `invuln_sources: Dictionary`, `consumed_ids: Dictionary`, counters.

`report_hit(hazard) -> StringName`, resolved synchronously in this order:

1. `DEAD` → `&"ignored"`.
2. Already in `consumed_ids` → `&"ignored"`; else record the instance id.
3. `iframe_remaining > 0` or any invulnerability source → `damage_blocked(kind, reason)`; return `&"blocked_invuln"`. The hazard is still consumed (LGTM smashes through).
4. `shield` → `shield = false`, `shield_changed(false)`, `damage_blocked(kind, &"shield")`. **If PURSUED: state = SAFE, hp = max_hp, recovery_remaining = 0, `recoveries += 1`, `health_changed`, `pursuit_recovered(&"shield")`.** Return `&"blocked_shield"`. (`recoveries` therefore counts every exit from PURSUED back to SAFE, by timer or by shield.)
5. Damage: `hp -= 1`, `iframe_remaining = hit_iframes`, `damage_taken(kind, hp)`, `health_changed`, notify `effect_manager.on_damage_applied()` (drops Code Review Bonus). `hp == 1` → PURSUED, `recovery_remaining = recovery_seconds`, `pursuit_started(recovery_seconds)`. `hp == 0` → DEAD, `caught()`.

`_physics_process` (only while the game is `running`): decrement `iframe_remaining`; if PURSUED,
decrement `recovery_remaining`, emit `pursuit_progress(remaining, total)`; at ≤ 0 → SAFE, hp = max,
`recoveries += 1`, `health_changed`, `pursuit_recovered(&"timer")`.

Ordering guarantee: Area3D overlap signals are delivered at the start of a physics tick, before any
`_physics_process`, and `report_hit` never grants *timer* recovery (the shield exception in step 4 — a blocked hit
while PURSUED restores SAFE/full hp, clears the timer, counts a recovery and emits `pursuit_recovered(&"shield")` —
is the only path by which `report_hit` ends a pursuit). A hit on the same tick the timer would
expire therefore kills (baseline §9: "resolve queued damage before recovery"). `runner_logic.gd`
models this with `recovery_remaining = 0.005`, `report_hit()`, then one tick.

`RunnerGame._on_caught()`: state `caught`, `player.set_controls_enabled(false)`, `player.play_dead()`,
`speed_controller.begin_stop(0.4)`, `camera_rig.shake(1.0)`, `pursuer.catch()`, emit `caught`.
After `caught_sequence_seconds` (1.6): `_finish_run(&"caught")` builds `result`, calls
`RunnerLeaderboard.submit(entry)` exactly once, sets `rank`/`qualifies`, emits `leaderboard_saved`,
`state_changed(&"finished")`, `run_finished(result)`. Guarded so it can never run twice.

## 5. Chunks and spawner

### 5.1 Chunk scene contract (`chunk.gd`, root Node3D)

Exports: `length: float` (multiple of 6), `weight: float`, `min_difficulty`, `max_difficulty`,
`mirror_x := true`, `tags: PackedStringArray`. Children: instances of `hazards/hazard.tscn` with
`kind`/`variant` overrides positioned at lane x and negative z offsets (0 = chunk front, −length = back),
and `Marker3D` nodes named `PowerUpSlot*` in group `pickup_slot` with meta `height` = `run` | `jump`.
`setup(game, mirrored: bool)`: if mirrored, negate every child's x. `get_hazards()`, `get_slots()`,
`entry_clear()` / `exit_clear()` (computed from hazard AABBs), `back_edge_z()`.

Diagram legend: columns = lanes −2 / 0 / +2; rows = 6 m bands from entry (bottom) to exit (top).
Hazard fronts sit 2.4 m into a band (depth 1.2 → occupies +2.4..+3.6); pits at +1.5..+4.5.
`W` low wall · `^` high wall · `b` swarm · `M` merge block · `_` pit · `L` ground laser · `l` mid laser ·
`H` high laser · `T` timed laser · `F` comment flood · `S` shockwave · `o` slot y 1.0 · `O` slot y 2.2 · `.` clear.

| # | Name | Len | d range | Wt | Layout (exit at top) |
|---|---|---|---|---|---|
| 1 | `chunk_breather_a` | 18 | 0.0–1.0 | 2 (×2 pursued) | `. . .` / `. o .` / `. . .` |
| 2 | `chunk_breather_b` | 24 | 0.0–1.0 | 1.5 (×2 pursued) | `. . .` / `. . .` / `. . O` / `. . .` |
| 3 | `chunk_t1_first_wall` | 24 | 0.00–0.30 | 4 | `. . .` / `W W W` / `. . .` / `. . .` |
| 4 | `chunk_t1_first_bar` | 24 | 0.00–0.30 | 4 | `. . .` / `^ ^ ^` / `. . .` / `. . .` |
| 5 | `chunk_t1_swarm_side` | 30 | 0.00–0.30 | 3 | `. . .` / `. . b` / `. o .` / `b . .` / `. . .` |
| 6 | `chunk_t1_pit_intro` | 30 | 0.05–0.30 | 3 | `. . .` / `. . .` / `_ _ _` (+`O` centre above the pit) / `. . .` / `. . .` |
| 7 | `chunk_t1_wall_then_bar` | 42 | 0.10–0.30 | 3 | `. . .` / `^ ^ ^` / `. . .` / `. o .` / `. . .` / `W W W` / `. . .` |
| 8 | `chunk_t2_merge_conflict` | 36 | 0.20–0.60 | 4 | `. . .` / `. . o` / `. . .` / `M M .` / `. . .` / `. . .` |
| 9 | `chunk_t2_flood_hold` | 36 | 0.25–0.60 | 3 | `. . .` / `. . o` / `F F .` / `. . .` / `F F .` / `. . .` |
| 10 | `chunk_t2_laser_low_high` | 42 | 0.20–0.60 | 3 | `. . .` / `l l l` / `. . .` / `. . .` / `. . .` / `L L L` (+`O` centre) / `. . .` |
| 11 | `chunk_t2_swarm_pair` | 48 | 0.25–0.60 | 3 | `. . .` / `b b .` / `. . .` / `. . .` / `. o .` / `b . b` / `. . .` / `. . .` |
| 12 | `chunk_t2_shockwave_rhythm` | 42 | 0.25–0.60 | 3 | `. . .` / `S S S` (+`O` centre) / `. . .` / `. . .` / `. . .` / `S S S` / `. . .` |
| 13 | `chunk_t3_pit_then_bar` | 48 | 0.45–0.85 | 3 | `. . .` / `^ ^ ^` / `. . .` / `. . .` / `. . o` / `. . .` / `_ _ .` (+`O` lane 0) / `. . .` |
| 14 | `chunk_t3_flood_laser` | 48 | 0.45–0.85 | 3 | `. . .` / `. . .` / `L L L` (+`O` centre) / `. . .` / `. . .` / `. . .` / `F F .` / `. . .` |
| 15 | `chunk_t3_merge_swarm` | 48 | 0.45–0.85 | 3 | `. . .` / `. . .` / `b . .` (+`O` lane −2) / `. . .` / `. o .` / `. . .` / `. M M` / `. . .` |
| 16 | `chunk_t3_timed_laser_intro` | 42 | 0.50–0.85 | 2 | `. . .` / `. o .` / `. . .` / `T T T` / `. . .` / `. . .` / `. . .` |
| 17 | `chunk_t4_gauntlet` | 66 | 0.70–1.00 | 3 | `. . .` / `^ ^ ^` / `. . .` / `. . .` / `. . .` / `F F .` / `. . .` / `. . .` / `. . .` / `S S S` / `. . .` |
| 18 | `chunk_t4_laser_rhythm` | 66 | 0.70–1.00 | 2 | `. . .` / `T T T` / `. . .` / `. . .` / `. . .` / `l l l` / `. o .` / `. . .` / `. . .` / `L L L` (+`O`) / `. . .` |
| 19 | `chunk_t4_pit_run` | 48 | 0.70–1.00 | 3 | `. . .` / `b . b` / `. . .` / `. . .` / `. . .` / `. . .` / `_ _ _` (+`O` centre) / `. . .` |

Note on #17: three forced actions 24 m apart — shockwave (jump) at 8.4 m, comment flood in lanes −2/0
(lane dodge to +2) at 32.4 m, full-width high wall (roll) at 56.4 m. Note on #19: two bug swarms flank the
centre lane 27.9 m after the pit — hold the centre or jump. Every hazard used in the catalog is one of the
kinds/variants in contract §8; no one-lane merge or one-lane wall variant exists.

Authoring rules (checked by the validator): length % 6 == 0; ≥ 6 m clear at entry and exit;
heavy→heavy slices ≥ 24 m apart, pit→anything ≥ 30 m; passable from any entry lane; approach cost
(lane changes + 1 if jump/roll) ≤ 1 for T1, ≤ 2 for T2, ≤ 3 for T3/T4; no `comment_flood` below d 0.2,
no timed laser below 0.45; slots ≥ 6 m from hazards in their lane (`run`) or within 0.6 m of a
JUMP-type hazard's front (`jump`).

### 5.2 Spawner algorithm (`chunk_spawner.gd`)

- `setup(game)`: load `chunk_library.tres`; instantiate each scene once to read exports into `metas`; free prototypes.
- `reset(seed)`: free `World/Chunks` children; `spawn_rng.seed = seed`, `powerup_rng.seed = seed ^ 0x9E3779B9`; `frontier_z = −(base_speed × 2.5)` (clean run-in); `_fill()`.
- `_physics_process(delta)` while `running` or `caught`: `dz = speed × delta`; `distance += dz`; move every active chunk by `+dz`; despawn chunks whose `back_edge_z() > despawn_z` (`queue_free`); `_fill()`.
- `_fill()`: while `active.size() < max_active_chunks` and `frontier_z > spawn_horizon_z`: pick and place the next chunk, then **advance `frontier_z = chunk.back_edge_z()`** so the next iteration and the horizon check use the new frontier. `frontier_z` is recomputed from the last active chunk's back edge at the start of every `_fill()` call, because chunks move between calls.
- Pick: candidates with `min_difficulty ≤ difficulty ≤ max_difficulty`, excluding the last index when more than one candidate; breather weights ×2 while PURSUED; `spawn_rng.rand_weighted(weights)`. If no candidate, fall back to all metas and `push_warning`.
- Place: `gap = max(0, v_eff × 1.02 × (t_spacing(d) + (0.15 if pursued else 0)) − prev.exit_clear − next.entry_clear)` where `v_eff` includes the Nitro multiplier while active; `chunk.position.z = frontier_z − gap`; `mirrored = mirror_x and spawn_rng.randf() < 0.5`; `chunk.setup(game, mirrored)`; log `"%.1fs d=%.2f %s%s gap=%.1f"`; emit `chunk_spawned`.
- Power-ups: if `elapsed − last_powerup_time ≥ 10` and at least one chunk since the last pickup chunk and `powerup_rng.randf() < lerp(0.55, 0.35, d)`: choose one slot; choose kind by weight excluding the previous kind and kinds currently active/held; instantiate `power_up.tscn` at the slot (y 1.0 or 2.2); update `last_powerup_time`.
- `clear_hazards_in_range() -> int` (Auto-Fix): every hazard in group `runner_hazards` with `is_blocking()` and `global_position.z ∈ [−blast_range_z, 1.0]` → `hazard.clear()` (visual `on_cleared()`, emit `hazard_cleared`); return the count; caller emits `hazards_blasted`.

### 5.3 Hazard (`hazard.gd`, root Area3D)

`_ready`: layer `ENEMY_HITBOX`, mask `PLAYER_HURTBOX`, `monitoring = true`, `monitorable = false`;
build one `CollisionShape3D` with a new `BoxShape3D` sized from `hazard_defs` (kind + variant), offset to
the y range; `add_to_group(&"runner_hazards")`; `area_entered.connect(_on_area_entered)`; mount the
visual (set base vars, then `on_spawned()`) or build a red-tinted `BoxMesh` of hitbox size.
`_on_area_entered(area)`: if `area.get_parent().is_in_group(&"runner_player")` → `hit_player(player)`.
`hit_player`: `if consumed or not active: return; consumed = true; set_deferred("monitoring", false);
game.hit_manager.report_hit(self); visual.on_hit_player()`. `clear()`: `consumed = true; active = false;
set_deferred("monitoring", false); remove_from_group; visual.on_cleared()`. Timed laser: state machine
`ground 1.2 s → off 0.3 s → high 1.2 s → off 0.3 s`, phase = `fmod(game.elapsed, 3.0)` so it is
deterministic per seed; `monitoring` follows state ≠ off (set from `_physics_process`, never inside a
callback); update the shape's y offset per state; call `set_laser_state` on change and `set_telegraph(t)`
during the 0.4 s before a change. `is_blocking()`, `occupies_lane(i)`, `get_world_aabb()`, `dodge_hint`.

Godot 4.7 rules: never toggle `monitoring`/`monitorable` directly inside an area callback (use
`set_deferred`); `queue_free()` in callbacks is fine, `free()` is not.

### 5.4 Power-up (`power_up.gd`, root Area3D)

Layer `PICKUP`, mask `PLAYER_HURTBOX`, `SphereShape3D` r 0.35. `collect(player)`: `if consumed: return;
consumed = true; set_deferred("monitoring", false); game.effect_manager.apply(kind); visual.on_collected()`.
Graybox: coloured `SphereMesh` per kind.

## 6. Score and effects

- `ScoreManager._physics_process` while running: `multiplier = nitro_mult × code_review_mult`;
  `exact += base_score_rate × multiplier × delta`; emit `score_changed(floori(exact), multiplier)` only
  when the integer or the multiplier changes. `add_bonus(points, reason)` → `bonus_awarded`.
- `EffectManager.apply(kind)`: `approve_shield` → `hit_manager.set_shield(true)`; `auto_fix` →
  `spawner.clear_hazards_in_range()` + bonus; `lgtm` → timed 5 s + invulnerability source `lgtm`;
  `nitro` → timed 8 s, `speed_controller.multiplier = 1.25`, `score.set_nitro(true)`, invulnerability
  source `nitro` (kept 1 s into the ease-down); `super_jump` → token, consumed by the player when a
  jump starts (`power_up_expired(&"super_jump")` then); `code_review` → `score.set_code_review(true)`
  until `on_damage_applied()`. Every pickup: `+pickup_bonus`, `power_up_collected(kind, duration)`.
  Timed effects refresh (`remaining = total`), never stack; `power_up_expired` fires once per activation.
  `get_active_effects()` snapshot.

## 7. Leaderboard (`runner_leaderboard.gd`, static)

`DEFAULT_PATH "user://leaderboard.cfg"`, `SCHEMA_VERSION 1`, `MAX_ENTRIES 10`, `MAX_NAME 16`.
`load_entries(path)`, `save_entries(entries, path)`, `submit(entry, path) -> {rank, entries, error}`,
`rename(run_id, name, path) -> Error`, `sanitize_name(raw)`, `sort_entries(entries)`.
Storage: section `meta/version`; section `leaderboard/entries` (Array of Dictionary). Unknown or newer
version → treat as empty. Validate each entry on load (types, finite, non-negative). Sort: score desc,
duration desc, insertion `order` asc (Godot's `sort_custom` is not stable). Dedupe by `run_id`
(replace). Sanitize: trim → drop controls (< 32, 127, and C1 controls 0x80–0x9F) → truncate to 16 → trim again → blank → `"Hoppy"`.
Atomic write with backup: `DirAccess.make_dir_recursive_absolute(base_dir)`; `config.save(path + ".tmp")`
(on error return it — the destination is untouched); if the destination exists, `rename_absolute(path,
path + ".bak")`; `rename_absolute(tmp, path)`; on success remove `.bak`; on failure restore `.bak` → `path`,
leave the `.tmp` in place, `push_warning` with its location, and return the error. `load_entries` falls
back to `.bak` when `path` is missing but `.bak` exists (crash between the two renames).

## 8. Tests (all `extends SceneTree`, run headless, `quit(failures)`, print `NAME: PASS/FAIL (n failures)`)

**`tests/runner_logic.gd`** (systems instantiated as plain nodes under `root`, driven by direct
`_physics_process(1.0/60)` calls, config `duplicate()`d):
1. HitManager: fresh SAFE 2 hp; hit → PURSUED 1 hp, `pursuit_started` once; immediate second hit → blocked `iframes`; +0.9 s then hit → DEAD, `caught` once; further hits ignored.
2. Recovery: 17.99 s still PURSUED; 18.01 s → SAFE 2 hp, `pursuit_recovered("timer")`; new hit → new cycle.
3. Shared tick: `recovery_remaining = 0.005`, `report_hit`, one tick → DEAD.
4. Shield: SAFE + shield → blocked, stays SAFE; PURSUED + shield → SAFE 2 hp, `pursuit_recovered("shield")`.
5. Invulnerability sources add/remove; dedupe by instance id.
6. ScoreManager: 60 ticks → 10 points; Nitro ×2; Code Review ×1.5 composes to ×3; damage drops Code Review; `score_changed` only on integer change; `add_bonus`; 30 fps vs 60 fps equal totals.
7. EffectManager: refresh-not-stack; Nitro sets speed multiplier + invulnerability and clears both on expiry; Super Jump token consumed once.
8. Leaderboard on `user://test_leaderboard_<rand>.cfg` (deleted after): sanitize cases; 12 submits keep 10 in order; dedupe keeps count; rename; corrupt file → empty load then successful submit; no `.tmp` left; `meta/version` present.
9. RunConfig sanity: detection size rule; `jump_velocity² / (2 gravity) ≥ 1.6`; tuning values within contract ranges.

**`tests/runner_chunk_validator.gd`** loads every `chunks/chunk_*.tscn` and checks: V1 lane bounds
and declared lanes; V2 depth ≥ 1.2 (pits 3.0) and `dodge_hint` matches geometry; V3 clear zones;
V4 no overlapping hitboxes; V5 every z-slice has an escape (a free lane or a JUMP/ROLL/TIMED hazard);
V6 forced-action spacing ≥ `v_max(tier) × t_spacing`; V7 approach-cost caps and tier restrictions;
V8 slot placement; V9 bot path simulation from 3 entry lanes × {PREFER_LANE, PREFER_JUMP, GREEDY_PICKUP}
× {v_min, v_max} with a virtual preceding heavy action, zero hits; V10 mirrored copy passes V1–V9.
Also: at every difficulty 0..1 step 0.1 at least two eligible chunks exist.

**`tests/runner_smoke.gd`**: accelerated 6× with `Engine.time_scale = 6.0` **and** `Engine.physics_ticks_per_second = 360`
(both restored at the end) — on Godot 4.7 `time_scale` alone multiplies the physics delta instead of adding
ticks, which would break the 0.10 s jump buffer and let hazards tunnel; raising the tick rate keeps each tick at
1/60 s of game time. `Engine.max_physics_steps_per_frame = 32`;
instantiate `runner_game.tscn` with `autostart = false`, `config` duplicate with `time_to_max_speed = 20`;
`start_run(12345)`; `set_autopilot(true)`; after 45 s game-time assert hp 2, `hits_taken == 0`, speed ≈
max, active chunks ≤ 9, score > 0, ≥ 1 power-up collected (print seed + chunk log on failure). Then
autopilot off → within 8 s `damage_taken` → PURSUED; autopilot on for `recovery_seconds + 1` → SAFE;
off → hit → hit → `caught`, `run_finished` exactly once ≈ 1.6 s later; leaderboard has this `run_id`;
`submit_name("  Test  ")` → name `Test`, count unchanged. `auto_fix` mid-run → cleared > 0 and no
hit for 2 s. `pause()` for 1 s → score unchanged, `paused_changed` seen; `resume()`. Real input:
`InputEventKey` with `physical_keycode = KEY_SPACE` → `player_action("jump")`. Routing:
`AppRouter.go("runner_game")` twice, then `runner`, then `hub`: `not busy`, tree unpaused, AudioService
still has 2 children. Reset `time_scale` before quitting.

**Boot check** (`--scene res://scenes/runner/runner_game.tscn --quit-after <frames>`): this plays a real
autopilot-free run to its game over and submits the score to the real `user://leaderboard.cfg`, so point
`runner_game.leaderboard_path` at a throwaway file (as `runner_smoke.gd` does) before running it unattended.

**Autopilot** (`systems/autopilot.gd`): each tick while running, group hazards ahead
(`z ∈ (−lookahead, 0.5]`, z-ranges expanded ±0.8) into slices; plan the nearest unresolved slice at
`front_z ≥ −(v × 0.6 + 0.4)`: PREFER_LANE → stay if free, else adjacent free lane, else two-step, else
act by hint; PREFER_JUMP → jump for JUMP/JUMP_OR_LANE/ROLL_OR_JUMP, roll for ROLL, lane for LANE;
GREEDY_PICKUP → PREFER_LANE plus lane toward `run` slots when safe, and for a `jump` slot the lane it
hangs over first (only while the tween plus a jump lead still fit in front of it), then the jump once
it is overhead. A slice keeps one key for its whole life, and a lane plan is re-issued across ticks —
one request per queued change — until the player reaches its lane, so a two-step move is never
abandoned half-way and an answered slice never earns a second manoeuvre. Timed
laser: predict state over the pass window `[t_arr, t_arr + (depth + 0.8)/v]`; ground active → jump, high
active → roll, off → nothing. Jump trigger `front_z ≥ −(v × 0.22 + 0.4)`; roll trigger
`front_z ≥ −(v × 0.15 + 0.4)`. Reckless mode: ignore the next N slices.

## 9. Godot 4.7 pitfalls (apply everywhere)

- Never mutate the shared `run_config.tres`; tests `duplicate()` it.
- `set_deferred` for `monitoring`/`monitorable`/`disabled` when inside physics callbacks.
- `Engine.time_scale` multiplies the physics delta (it does not add ticks); to accelerate a simulation without
  coarsening physics, raise `Engine.physics_ticks_per_second` by the same factor and `max_physics_steps_per_frame`.
- Injected key events must set `physical_keycode`; bindings are physical.
- `Array.sort_custom` is unstable; carry an explicit `order`.
- Camera follow in `_physics_process` (player moves there) to avoid jitter.
- Tween/Timer nodes under PAUSABLE parents freeze on pause; anything that must keep running lives under ALWAYS nodes.
- `change_scene_to_file` to the same path (Retry) yields a fresh instance; old scene freed at end of frame.
- The `AppRouter` veil tween must run while paused → `AppRouter.process_mode = ALWAYS` and unpause before switching scenes.
