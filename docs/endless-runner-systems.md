# Endless Runner — Systems Specification (backend)

Version 1.0 · 2026-09-19 · Companion to `docs/endless-runner-contract.md` (the contract wins on any conflict).

This is the implementation specification for the backend of the Endless Runner. It is written so an
implementer can build each file without further design decisions, and so a validator can check the
result against it line by line. Paths are relative to `hoppys-adventure-arcade/`.

## 1. Frame of reference and motion

- World forward is −Z. The player stands at z = 0 and only moves in X (lanes) and Y (jump). Chunks
  (and every hazard/power-up inside them) move toward +Z at the authoritative `speed` owned by
  `SpeedController`. Distance travelled = ∫ speed dt.
- Lanes are **indices 0, 1, 2** everywhere in code and in the contract: `lane`, `target_lane`, and bit
  *i* of every lane mask all mean lane index *i*. World X is `lane_width × (index − 1)` — −2 / 0 / +2 at
  the default `lane_width` 2.0. Both `runner_player.gd::lane_x()` and `hazard.gd::lane_x()` are
  `(float(index) - 1.0) * lane_width`, and `hazard.gd::lanes_mask()` sets `1 << index` for every index
  `occupies_lane()` accepts, so bit 0 = x −2, bit 1 = x 0, bit 2 = x +2. Prose elsewhere that speaks of
  lane k ∈ {−1, 0, +1} names the same three lanes by their world offset; index = k + 1. The player's
  capsule radius is 0.4, so a hazard whose x-extent is ±0.8 around a lane centre (per-lane width 1.6)
  cannot touch a player in an adjacent lane.
- Physics 60 Hz. Jump apex 1.715 m, airtime 0.70 s. Per-tick travel at the v2 Nitro cap (38 m/s) is
  0.63 m; the minimum hazard depth of 1.2 m plus the 0.8 m capsule footprint (2.0 m) gives 3.16 overlapping
  ticks at the highest legal speed, so `Area3D` overlap detection cannot tunnel. `runner_logic.gd`
  (`_test_config_sanity`) asserts the tunnelling floor `(min_hazard_depth + 0.8) / (nitro_speed_cap / 60) ≥ 2.0`
  against the stage-adjusted caps — two overlapping ticks is the hard requirement for detection, and the
  defaults keep a full tick of margin above it.

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
16.8 m at 24 m/s, 22.4 m at 32 m/s (26.6 m at the 38 m/s Nitro cap); this drives spacing.

Reaction budget: 0.35 s choice reaction + 0.05 s input/render latency + 0.30 s worst-case manoeuvre
(two lane changes) = 0.70 s minimum. Heavy actions (jump, roll) occupy 0.70 s. Hence
`t_spacing(d) = lerp(1.2, 0.85, d)` seconds front-to-front between forced actions. The pursuit relief is
part of that **time** term, not a distance added afterwards, so the seam rule is exactly as
`chunk_spawner.gd::_gap_for()` implements it:

```text
gap = max(0, v_eff × gap_safety × (t_spacing(d) + (t_spacing_pursued_bonus if PURSUED else 0))
           − prev.exit_clear − next.entry_clear)
```

with `v_eff = max(game.speed, base_speed)` (never plan tighter than the base speed, so the catch
deceleration cannot pack chunks together), `gap_safety` 1.02 and `t_spacing_pursued_bonus` 0.15 s by
default. Equivalently: `prev.exit_clear + gap + next.entry_clear ≥ v_eff × gap_safety × t_total`.

### 1.2 Speed and difficulty curve (v2, see §10.2)

`difficulty = max(clamp(run_clock / time_to_max_speed, 0, 1), stage_difficulty_floor)` and
`speed = lerp(base_speed + b, max_speed + b, smoothstep(0, 1, clamp(run_clock / time_to_max_speed, 0, 1)))` with
`time_to_max_speed 100` (v1 used `elapsed / 165`), the per-stage bonus `b = min(stage_speed_step × (stage_index − 1),
stage_speed_bonus_max)`, then `+ tail_speed_per_minute` per 60 s of run_clock past the ramp, capped at
`hard_cap_speed + b`. `run_clock` counts RUN-phase seconds only and is frozen during `turn`, `boss` and
`stage_clear`, so a fight never advances the ramp or the chunk tier; the speed reached holds through those phases.
Difficulty stays 1.0 in the tail. Nitro multiplies the current speed by `nitro_speed_multiplier` (capped at
`nitro_speed_cap` 38) and does not advance `run_clock`.

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
| `scenes/runner/runner_game.gd` + `.tscn` | Node3D facade | Contract §3–4: states, signal forwarding, mounting, `start_run` (calls `resume()` first, so a restart from a paused state never begins frozen), pause, caught sequence, `_finish_run` once |
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
| `tests/runner_scaffold_check.gd`, `tests/runner_logic.gd`, `tests/runner_chunk_validator.gd`, `tests/runner_smoke.gd` | SceneTree scripts | §8 |
| `app/app_router.gd`, `app/audio_service.gd` | autoloads | Contract §2 / §5.6 additions |
| Graybox placeholders (frozen after PR 1): `scenes/runner/ui/runner_hud.tscn/.gd`, `scenes/runner/ui/pause_menu.tscn/.gd`, `scenes/runner/ui/game_over.tscn/.gd` | | Minimal `Style`-themed UI so the loop is playable |
| `scenes/runner/runner_menu.tscn/.gd` | Node3D | Backend fallback graybox only; the frontend's F6 menu replaces it. Brought up to the contract §2 four-button set in PR 2 — `01 Play`, `02 Leaderboard` (top-10 panel from the static `runner_leaderboard.load_entries()`), `03 Return to Main Menu`, `04 Quit Game` — so `runner_scaffold_check.gd` can assert `RunnerMenu` + `buttons.size() == 4` against either scene. That is the backend's **last** edit here: once the frontend menu lands the path is exclusively frontend-owned (contract §1 rule 1) |

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

`reset()` restores lane 1, the roll/jump timers, the standing hurtbox and the `idle` pose, **and** clears the
mounted visual's power-up state through the contract §5.1 hooks: `show_aura(kind, false)` for every
`AURA_KINDS` entry and `show_shield(false)` (the player's `apply_aura` / `apply_shield` wrappers). The visual is mounted once in `setup()` and outlives the run, so without that a new
run would open still wearing the previous run's aura or shield glow. Both calls are guarded by
`is_instance_valid(visual)` + `has_method(...)`, so a graybox or a missing visual is a no-op.

Visual mount: `player/hoppy_runner_visual.tscn` if it exists, else a code-built capsule + two ear boxes
whose material tint changes per anim state (so graybox testers see state changes).

## 4. HitManager state machine

`enum HitState { SAFE, PURSUED, DEAD }`. Vars: `hp`, `state`, `iframe_remaining`, `recovery_remaining`,
`shield`, `invuln_sources: Dictionary`, `consumed_ids: Dictionary`, counters.

`report_hit(hazard) -> StringName`, resolved synchronously in this order:

1. `DEAD` → `&"ignored"`.
2. Already in `consumed_ids` → `&"ignored"`; else record the instance id.
3. `iframe_remaining > 0` or any invulnerability source → `damage_blocked(kind, reason)`; return `&"blocked_invuln"`. The hazard is still consumed (LGTM smashes through).
4. `shield` → `shield = false`, `iframe_remaining = hit_iframes`, `shield_changed(false)`, `damage_blocked(kind, &"shield")`. **If PURSUED: state = SAFE, hp = max_hp, recovery_remaining = 0, `recoveries += 1`, `health_changed`, `pursuit_recovered(&"shield")`.** Return `&"blocked_shield"`. (`recoveries` therefore counts every exit from PURSUED back to SAFE, by timer or by shield. The shield block starts `hit_iframes` exactly like the damage path in step 5, so the next hazard overlapping in that window reports `&"iframes"`, not damage.)
5. Damage: `hp -= 1`, `iframe_remaining = hit_iframes`, `damage_taken(kind, hp)`, `health_changed`, notify `effect_manager.on_damage_applied()` (drops Code Review Bonus). `hp == 1` → PURSUED, `recovery_remaining = recovery_seconds`, `pursuit_started(recovery_seconds)`. `hp == 0` → DEAD, `caught()`.

`_physics_process` (only while the game is `running`): decrement `iframe_remaining`; if PURSUED,
decrement `recovery_remaining`, emit `pursuit_progress(remaining, total)`; at ≤ 0 → SAFE, hp = max,
`recoveries += 1`, `health_changed`, `pursuit_recovered(&"timer")`.

**Same-tick ordering.** When a hazard is touched on the very tick the recovery timer expires, the damage
must win — the runner dies rather than recovering. That holds without any queue, because of Godot's
physics frame order: the engine flushes physics queries (which is what emits `area_entered`) **before**
it runs any `_physics_process` in that frame. Measured on 4.7.0 with two overlapping `Area3D`s: an
overlap created during physics frame 1 is delivered at `physics_frame == 2`, ahead of frame 2's
`_physics_process`. So `hazard.gd::_on_area_entered` → `hit_player()` → `HitManager.report_hit()` always
resolves before `HitManager._physics_process` decrements `recovery_remaining` in the same frame, and
`report_hit` can stay fully synchronous. The order is deterministic (it is the engine's iteration order,
not node order or signal-connection order), but it *is* load-bearing, so it is pinned twice: This ordering was **measured on the installed Godot 4.7.0** (physics flush → `physics_frame` → `_physics_process`) and is pinned by the two tests named here; it is treated as a diagnostic result until the §9 commands are re-run on the pinned 4.7.1, and any difference must be recorded in the contract §10 change log.

- `runner_logic.gd` §3, out of tree: a hit delivered first kills and the expiring timer cannot revive
  it, while the reverse order only starts a fresh pursuit.
- `runner_smoke.gd` `_same_tick_phase()`, **in tree and through the real `Area3D` flow** — nothing
  calls `hit_player()` by hand. A dedicated `RunnerGame` (autostart off, `leaderboard_path` overridden
  before `add_child`, spawner frozen so no other hazard can interfere) is put in PURSUED, a real
  `hazard.tscn` is placed on the hurtbox, and the recovery timer is armed to expire on exactly the
  frame whose query flush reports that overlap. It asserts DEAD, `caught` exactly once and no
  `pursuit_recovered`; the converse trial, with no hazard, recovers to SAFE on that same tick.

The full order inside one engine iteration is: flush physics queries (this is where `area_entered` is
emitted) → emit `SceneTree.physics_frame` → node `_physics_process` → physics step. An
`await physics_frame` therefore resumes *after* that frame's overlap reports and *before* that frame's
HitManager tick, which is what lets the smoke test straddle the seam precisely. Measured on 4.7.0, a
hazard positioned on the hurtbox is reported in the flush two frames later: the first frame carries the
new transform to the physics server and its step finds the pair, and the signal is flushed at the top of
the frame after that. Moving hit resolution into a `_physics_process` that runs after the timer breaks
the guarantee and fails both checks.

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

The layout column reads **far end first**: the top row is the 6 m band the player reaches last and the
bottom row the one it reaches first. That is why #19 lists `b . b` above `_ _ _` even though the pit is
the first thing the player meets. Distances in the notes below are "m into the chunk" measured to a
hazard's **front** edge (the larger-z edge, reached first), the same edge the spacing rules use.

Note on #17: three forced actions 24 m apart — shockwave (jump) at 8.4 m, comment flood in lanes −2/0
(lane dodge to +2) at 32.4 m, full-width high wall (roll) at 56.4 m. Note on #19: the full-width pit
comes first with its front edge 7.5 m in; the two bug swarms flank the centre lane with their front edge
at 38.4 m, so the front-to-front distance the validator measures is **30.9 m**, just clear of the 30 m
pit rule. (The open floor between the pit's back edge and the swarms is 27.9 m — a different measurement,
not the one the rule uses.) Each swarm is 1.6 m wide and sits in lane −2 / lane +2, so the slice leaves
the centre lane free: it is a lane dodge or a jump, not a full-width forced action, and the pit rule
still applies to it because the validator measures pit → *any* next slice. Every hazard used in the
catalog is one of the kinds/variants in contract §8; no one-lane merge or one-lane wall variant exists.

Authoring rules (checked by the validator): length % 6 == 0; ≥ 6 m clear at entry and exit;
heavy→heavy slices ≥ 24 m apart, pit→anything ≥ 30 m — measured front-to-front like every other spacing
rule here, i.e. from the pit's own front edge (its larger-z edge, the one the player reaches first) to the
front of the next forced action, which is exactly what `runner_chunk_validator.gd` checks
(`front_z = position.z + size.z / 2`, slices sorted front-first, `gap = previous.front_z - slice.front_z`
against `PIT_SPACING`); passable from any entry lane; approach cost
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
- Power-ups: if `elapsed − last_powerup_time ≥ 10` and at least one chunk since the last pickup chunk and `powerup_rng.randf() < lerp(0.55, 0.35, d)`: choose one slot; choose kind by weight excluding the previous kind and kinds currently active/held; instantiate `power_up.tscn` at the slot (y 1.0 or 2.2); update `last_powerup_time`. A chunk without a `PowerUpSlot` skips placement and leaves `last_powerup_time` and the retry state untouched; if excluding active/held kinds empties the weighted set, fall back to any kind except `last_powerup_kind`; if that is empty too, skip placement without touching the retry state.
- `clear_hazards_in_range() -> int` (Auto-Fix): every hazard in group `runner_hazards` with `is_blocking()` and `RunnerGame.track_z(hazard) ∈ [−blast_range_z, 1.0]` (rig-local z through `TurnRig`, the single coordinate rule; identity while unrotated) → `hazard.clear()` (visual `on_cleared()`, emit `hazard_cleared`); return the count; caller emits `hazards_blasted`.

### 5.3 Hazard (`hazard.gd`, root Area3D)

`_ready`: layer `ENEMY_HITBOX`, mask `PLAYER_HURTBOX`, `monitoring = true`, `monitorable = false`;
build one `CollisionShape3D` with a new `BoxShape3D` sized from `hazard_defs` (kind + variant), offset to
the y range; `add_to_group(&"runner_hazards")`; `area_entered.connect(_on_area_entered)`.

Init order: the visual is mounted from `setup(game)`, not from `_ready()`. The spawner adds the chunk to
the tree and only then calls `chunk.setup()`, which negates the child x on a mirrored chunk and hands
each hazard the RunConfig, so a visual mounted in `_ready()` would receive `lanes_mask` computed from
the hazard.gd fallback `lane_width` / `hurtbox_radius` and an un-mirrored x. `_ready()` therefore mounts
only when `setup()` already ran (`config != null`) and otherwise defers `_mount_visual()` as an
end-of-frame fallback for a hazard that never gets a `setup()`; `setup()` mounts as soon as the node is
ready. `_mount_visual()` is idempotent (and a no-op once `clear()` has run), so a hazard can never carry
two visuals. Mounting means: instance `hazards/visuals/<kind>_visual.tscn` if it exists, set the base
vars, then `on_spawned()`, else build a tinted `BoxMesh` of hitbox size (graybox).
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
consumed = true; set_deferred("monitoring", false); game.effect_manager.apply(kind); visual.on_collected()`. The pickup is consumed **before** `EffectManager.apply()` decides acceptance on purpose: a refused kind (unknown, or a timed effect with a non-positive duration, see §6) is a configuration error, and a mis-configured pickup must disappear rather than linger in the lane; the run itself is unchanged in that case.
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
  until `on_damage_applied()`. Every pickup: `+pickup_bonus`, `power_up_collected(kind, duration)` —
  `duration` is `duration_for(kind)`, which is 0.0 for the instant kinds (shield, auto_fix, super_jump,
  code_review) and only a real countdown for LGTM and Nitro (contract §4.1).
  Timed effects refresh (`remaining = total`), never stack; `power_up_expired` fires once per activation.
  `get_active_effects()` snapshot.
- **Nothing is counted, paid or announced until the kind has been recognised and applied.** Two refusals,
  both of which leave the run exactly as it was — no `power_ups_collected` increment, no `pickup_bonus`,
  no `power_up_collected`:
  1. **Unknown kind** → `push_warning` naming the kind, and return. It must not fall through into the
     shared tail; a pickup that does not exist may not pay a bonus.
  2. **Timed kind with a non-positive `duration_for(kind)`** (LGTM, Nitro) → `push_warning` naming the
     kind and the duration, and return *before* `_start_timed` and before the invulnerability source,
     speed multiplier or score multiplier are switched on, so there is nothing to unwind. RunConfig
     ships 5 s / 8 s, so this only fires on a mis-edited config; without it a zero duration would
     register a timer that expires on its first tick while the invulnerability stayed on. `code_review`
     is *not* timed — it is held until an unblocked hit — so its 0.0 duration is not subject to this rule.

## 7. Leaderboard (`runner_leaderboard.gd`, static)

`DEFAULT_PATH "user://leaderboard.cfg"`, `SCHEMA_VERSION 2` (v1 boards migrate in place, §10.7), `MAX_ENTRIES 10`, `MAX_NAME 16`.
`load_entries(path)`, `save_entries(entries, path)`, `submit(entry, path) -> {rank, entries, error}`,
`rename(run_id, name, path) -> Error`, `sanitize_name(raw)`, `sort_entries(entries)`.
Storage: section `meta/version`; section `leaderboard/entries` (Array of Dictionary). Any version that is
not in `SUPPORTED_VERSIONS` ([1, 2]) reads as an empty board with `ERR_FILE_UNRECOGNIZED`; a version-1 board is the exception — its rows are read normally and the next successful save rewrites the file as version 2 (in-place migration). `read_board(path) -> {entries, version, error, used_backup}` is the
internal reader that also reports which case it hit (`OK`, `ERR_FILE_NOT_FOUND`, `ERR_FILE_CORRUPT`, or
`ERR_FILE_UNRECOGNIZED` for a version mismatch); `load_entries` is `read_board(...)["entries"]`.
**Backup fallback:** the reader tries `path`, and falls back to `path + ".bak"` in both directions of the
same crash window — when the primary is missing (the crash landed between the two renames of step 3/4
below) and when the primary exists but does not parse, since a crash can equally leave a half-written
primary beside an intact backup. A backup that parses is returned with `error = OK` and
`used_backup = true` (plus a `push_warning` when it stood in for a corrupt primary); the board is
otherwise handled normally, so the next successful save rewrites it into place through the steps below.
Only a corrupt primary with no readable backup is `ERR_FILE_CORRUPT`, and a path with neither file still
returns `ERR_FILE_NOT_FOUND`. Each parse attempt uses its own `ConfigFile`, so a failed one cannot leave
half a board behind for the next.
**Forward compatibility:** when the file declares a version *newer* than `SCHEMA_VERSION`, `submit` and
`rename` refuse to write — `push_warning` naming the file and both versions, `submit` returns
`error = ERR_FILE_UNRECOGNIZED` with `rank` 0, `rename` returns the same Error — because its rows cannot
be parsed and overwriting would replace a real board with a single run. A missing file, a corrupt file
with no readable backup, or an *older*/unrecognised-but-not-newer version keeps the old behaviour: read
empty, then write normally.
Validate each entry on load (types, finite, non-negative). Sort: score desc,
duration desc, insertion `order` asc (Godot's `sort_custom` is not stable). Dedupe by `run_id`
(replace). Sanitize: trim → drop controls (< 32, 127, and C1 controls 0x80–0x9F) → truncate to 16 → trim again → blank → `"Hoppy"`.
Atomic write with backup. Every step checks its own error and returns it; the destination is only ever
replaced by a rename that succeeded:
1. `DirAccess.make_dir_recursive_absolute(base_dir)` — returns OK when the directory already exists, so
   any other value is a real failure (`push_warning`, return it; nothing has been written).
2. `config.save(path + ".tmp")` — on error return it; the destination is untouched.
3. If the destination exists, `rename_absolute(path, path + ".bak")` — on error `push_warning` naming
   where the new board is left (`.tmp`) and return it. Set `backed_up` **only** here, so the code knows
   this save is what created the `.bak`.
4. `rename_absolute(tmp, path)` — on error restore `.bak` → `path` **only if `backed_up`** (a `.bak` from
   an earlier crash is never restored over the destination; a restore that itself fails is warned about),
   leave the `.tmp` in place, `push_warning` naming its location, and return the error.
5. On success remove the `.bak`.

The `.bak` is therefore temporary and must not remain after a successful write — neither must the `.tmp`
— and it is retained only when recovery is required. `load_entries` falls back to `.bak` when `path` is
missing but `.bak` exists (crash between the two renames).

## 8. Tests (all `extends SceneTree`, run headless, `quit(failures)`, print `NAME: PASS/FAIL (n failures)`)

Every test that instantiates `RunnerGame` must override `leaderboard_path` to a throwaway
`user://` file **before** `add_child()` — `_ready()` honours `autostart`, so a later assignment races
a live run — and must delete that file and its `.tmp`/`.bak` siblings on every exit path; otherwise a
run that reaches `caught` writes the player's real `user://leaderboard.cfg`.

**`tests/runner_logic.gd`** (systems instantiated as plain nodes under `root`, driven by direct
`_physics_process(1.0/60)` calls, config `duplicate()`d):
1. HitManager: fresh SAFE 2 hp; hit → PURSUED 1 hp, `pursuit_started` once; immediate second hit → blocked `iframes`; +0.9 s then hit → DEAD, `caught` once; further hits ignored.
2. Recovery: 17.99 s still PURSUED; 18.01 s → SAFE 2 hp, `pursuit_recovered("timer")`; new hit → new cycle.
3. Shared tick: `recovery_remaining = 0.005`, `report_hit`, one tick → DEAD.
4. Shield: SAFE + shield → blocked, stays SAFE; PURSUED + shield → SAFE 2 hp, `pursuit_recovered("shield")`. Either block starts `hit_iframes`: the hit straight after it is `blocked_invuln` / `iframes`, and only a hit past the window damages again.
5. Invulnerability sources add/remove; dedupe by instance id.
6. ScoreManager: 60 ticks → 10 points; Nitro ×2; Code Review ×1.5 composes to ×3; damage drops Code Review; `score_changed` only on integer change; `add_bonus`; 30 fps vs 60 fps equal totals.
7. EffectManager: refresh-not-stack; Nitro sets speed multiplier + invulnerability and clears both on expiry; Super Jump token consumed once.
8. Leaderboard on `user://test_leaderboard_<rand>.cfg` (deleted after): sanitize cases; 12 submits keep 10 in order; dedupe keeps count; rename; corrupt file → empty load then successful submit; no `.tmp` left; `meta/version` present.
9. RunConfig sanity: detection size rule; `jump_velocity² / (2 gravity) ≥ 1.6`; tuning values within contract ranges.

Beyond the authored list the same file carries: 10 autopilot planning; 11 a finished timed laser stops
advancing; 12 Super Jump invulnerability survives a re-launch; 13 dodges counted per crossing; 14 the
terminal `difficulty_changed(1.0)` is emitted exactly once and never repeated; 15 a hazard receives the
RunConfig before it mounts its visual, and mounts exactly one; 16 `reset()` clears the mounted visual's
auras and shield glow.

**`tests/runner_scaffold_check.gd`** additionally drives the pause facade on a real `runner_game.tscn`:
`toggle_pause()` both ways, then `pause()` → `start_run()` → the tree and the facade are both unpaused,
the state is `running` and `paused_changed(false)` was emitted; and it asserts the runner menu exposes
four buttons.

**`tests/runner_chunk_validator.gd`** loads every `chunks/chunk_*.tscn` and checks: V0 no hazard has
mounted a visual before `chunk.setup()` handed out the RunConfig, and every hazard afterwards has the
config, exactly one visual and lane geometry read from the RunConfig; V1 lane bounds
and declared lanes; V2 depth ≥ 1.2 (pits 3.0) and `dodge_hint` matches geometry; V3 clear zones;
V4 no overlapping hitboxes; V5 every z-slice has an escape (a free lane or a JUMP/ROLL/TIMED hazard);
V6 forced-action spacing ≥ `v_max(tier) × t_spacing`; V7 approach-cost caps and tier restrictions;
V8 slot placement; V9 bot path simulation from 3 entry lanes × {PREFER_LANE, PREFER_JUMP, GREEDY_PICKUP}
× {v_min, v_max} with a virtual preceding heavy action, zero hits; V10 mirrored copy passes V0–V9.
Also: at every difficulty 0..1 step 0.1 at least two eligible chunks exist.

**`tests/runner_smoke.gd`**: accelerated 6× with `Engine.time_scale = 6.0` **and** `Engine.physics_ticks_per_second = 360`
— on Godot 4.7 `time_scale` alone multiplies the physics delta instead of adding
ticks, which would break the 0.10 s jump buffer and let hazards tunnel; raising the tick rate keeps each tick at
1/60 s of game time. `Engine.max_physics_steps_per_frame = 32`. All three globals are captured before they
are changed and restored in `_report()`, which every exit path goes through — the early returns for a missing
or unloadable scene as well as a completed run — so a failing smoke test never leaks an accelerated engine
into whatever runs next;
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
- A CollisionObject may not leave the tree inside a physics callback either ("Removing a CollisionObject node
  during a physics callback is not allowed"): `queue_free()` (already end-of-frame) or
  `remove_child.call_deferred()`, never a synchronous `remove_child`.
- `Engine.time_scale` multiplies the physics delta (it does not add ticks); to accelerate a simulation without
  coarsening physics, raise `Engine.physics_ticks_per_second` by the same factor and `max_physics_steps_per_frame`.
- Injected key events must set `physical_keycode`; bindings are physical.
- `Array.sort_custom` is unstable; carry an explicit `order`.
- Camera follow in `_physics_process` (player moves there) to avoid jitter.
- Tween/Timer nodes under PAUSABLE parents freeze on pause; anything that must keep running lives under ALWAYS nodes.
- `change_scene_to_file` to the same path (Retry) yields a fresh instance; old scene freed at end of frame.
- The `AppRouter` veil tween must run while paused → `AppRouter.process_mode = ALWAYS` and unpause before switching scenes.


## 10. v2 systems — stages, turns, boss fights (systems spec 2.0)

Authoritative tuning and facade live in the contract §11; this section is the implementation spec. Style rules
unchanged. Two clocks: `elapsed` (total unpaused seconds) and `run_clock` (RUN-phase seconds; drives speed and
difficulty; frozen in `turn`, `boss`, `stage_clear`).

`runner_game.gd` `FRONTEND_MOUNTS` gains one v2 entry beyond the HUD panels: `World/TurnRig/BossArena` →
`boss/boss_fx.tscn`, the optional 3D fight effects (telegraphs, tracers, damage numbers). It follows the same rules
as every other mount — instantiated only when the file exists, `bind(self)` when it has `bind`, freed with the scene
— and is pinned to `PROCESS_MODE_PAUSABLE` on mount, because the arena inherits the facade's ALWAYS mode and effects
must freeze with the pause menu. Giving the effects a home inside the arena is what keeps `ui/boss_hud.tscn` out of
`World`.

### 10.1 `systems/stage_manager.gd` — phase state machine

Vars: `phase: StringName = &"idle"`, `stage_index := 0`, `stage_distance := 0.0`, `stage_distance_target := 0.0`,
`run_clock := 0.0`, `next_turn_direction := 0`, `_phase_timer := 0.0`, `_turn_direction := 0`,
`_turn_announced := false`, `stage_rng := RandomNumberGenerator.new()`
(seeded `seed ^ 0x5F356495` in `reset(seed)` so a run is reproducible). `reset(seed)` → `idle`; `begin()` (called by
`RunnerGame.start_run` after every system reset) → `_enter_run()` with `stage_index = 1`.

Per physics tick (only while `game.state == &"running"` and not paused), in this order:

1. `run`: `run_clock += delta`; `stage_distance += game.speed × delta`; `stage_distance_target =
   min(stage_base_distance + stage_distance_step × (stage_index − 1), stage_distance_max)`. When
   `stage_distance ≥ target − stage_drain_distance` the drain window opens: `spawner.set_spawning(false)`, and
   **the turn direction is drawn here**, `next_turn_direction = stage_rng.randi_range(0, 1) × 2 − 1` (mirrored onto
   the facade), so the warning and the bend can never disagree. Then, once per seam, when
   `stage_distance ≥ target − pace × turn_warning_seconds` with `pace = max(game.speed, base_for_stage())`, emit
   `turn_incoming(next_turn_direction, (target − stage_distance) / pace)` — a drain shorter than that window is
   already inside it when it opens, so the warning lands on the same tick as the drain gate. When `stage_distance ≥ target`
   and no node in `runner_hazards` with `is_blocking()` has `track_z < stage_clear_line_z`, or `_phase_timer ≥
   stage_drain_timeout` (then `clear()` every remaining blocking hazard silently, no dodge/bonus), enter `turn`.
2. `turn`: `_phase_timer += delta`; `progress = clamp(_phase_timer / turn_seconds, 0, 1)`; call
   `turn_rig.set_turn(progress, dir)` and `camera_rig.set_turn(progress, dir)`; at `progress ≥ 1` emit
   `turn_finished`, reset both to `(0, 0)`, enter `boss`.
3. `boss`: delegate to `boss_encounter.tick(delta)`; on `boss_encounter.finished` (defeated or retreated, after the
   outro) enter `stage_clear`.
4. `stage_clear`: `_phase_timer += delta`; at `stage_clear_seconds` → `stage_index += 1`, `_enter_run()`.

`_enter_run()`: `stage_distance = 0`, `spawner.set_spawning(true)`, `speed_controller.set_stage_bonus(b)` and
`speed_controller.set_difficulty_floor(StageDefs.difficulty_floor(stage_index, config))` (see 10.2), emit `stage_started(stage_index, StageDefs.boss_name(stage_index), speed_controller.base_for_stage())`.
Enter/exit helpers emit `phase_changed(phase)` on change only, and forward `set_phase` / `set_boss_arena` to the
corridor when present (`has_method`). `turn_started(dir, turn_seconds)` is emitted on entering `turn` with
`dir = next_turn_direction`, the value the drain drew (a seam that somehow reached the bend with none — a
zero-length stage, a hand-driven test — draws one there rather than turning by 0). `next_turn_direction` goes
back to 0 with the rig reset at the end of the bend, so it is non-zero exactly from the drain gate to
`turn_finished`. `stage_cleared(stage_index, bonus)` is emitted on entering
`stage_clear` with `bonus = stage_clear_bonus_base + stage_clear_bonus_per_stage × (stage_index − 1)` added to the
score first (`score_manager.add_bonus(bonus, &"stage_clear")`). `caught` → `phase = &"idle"` (emit), boss encounter
aborted (`boss_encounter.abort()` frees projectiles/tools and the boss without bonuses). The `result` fields
`stages_cleared`, `stage_reached`, `bosses_defeated`, `bosses_escaped`, `tools_used`, `boss_damage_dealt`,
`turns_taken` are read from StageManager/BossEncounter counters in `_finish_run`.

`data/stage_defs.gd`: static `boss_slot(i)`, `cycle(i)`, `boss_kind(i)`, `boss_name(i)`, `speed_bonus(i, config)`,
`difficulty_floor(i, config)`, `distance_target(i, config)`.

### 10.2 `systems/speed_controller.gd` v2

`speed_at(t)` is evaluated at `game.run_clock` (not `elapsed`). New `stage_bonus := 0.0` set by
`set_stage_bonus(b)`; `base`, `max` and `hard_cap` each add `stage_bonus` inside `speed_at()`; `normalized()` keeps
`(speed − base_eff) / (max_eff − base_eff)`. `difficulty_at(t) = max(clamp(t / time_to_max_speed, 0, 1),
difficulty_floor)` with `difficulty_floor` set by `set_difficulty_floor(f)` from StageDefs. During `turn`, `boss`
and `stage_clear` the speed holds at the value reached (the treadmill keeps moving at that speed for the corridor
and projectiles); Nitro still applies. Tests: section 14 re-expresses the terminal-1.0 rule on `run_clock`, adds
stage bonus cases (b = 0, 3, 6 → caps 26/29/32; Nitro ≤ 38) and the floor rule.

### 10.3 `boss/boss_encounter.gd` (+ `boss/boss_arena.tscn`, `boss/boss_defs.gd`)

`BossArena` root (Node3D, `boss_encounter.gd`) children `Boss` (Node3D) → `Visual` mount, `Projectiles`, `Tools`,
plus the optional `boss/boss_fx.tscn` frontend mount (contract §11.3, §11.8) that `runner_game.gd` adds here.
`start(stage_index)`: read defs (kind, name, base HP, speeds, telegraphs, intervals, patterns, accepted tools per
phase) scaled by the cycle escalation (contract §11.10), with `boss_hp_scale` multiplying the base HP before that
growth so a test config can shorten a fight without bending the curve; `hp = max_hp`; `phase = 1`; mount the visual
(`ResourceLoader.exists` → `load as PackedScene` → set base vars → `add_child` → `on_spawned()`; graybox fallback: a
DANGER box 4×2.4×1.5 with a Label3D name); position `Boss` at `(0, 2.6, boss_z)`; `_intro = boss_intro_seconds`;
emit `boss_intro(kind, name, _intro)` **first** (the entrance card, contract §11.4), then `boss_spawned(kind, hp)`
and `boss_health_changed(hp, max_hp)`; `_attack_timer = attack_interval(phase)`;
`_tool_timer = tool_interval × 0.5`.

`tick(delta)`: intro countdown (no attacks) → ACTIVE: `_attack_timer -= delta`; when ≤ 0 pick the next beat of the
current pattern (patterns cycle a fixed beat list; lanes from `stage_rng` where the pattern says "random", never
repeating the immediately previous lane mask), emit `boss_attack_telegraph(mask, variant, telegraph)`, call
`visual.play_telegraph(...)`, queue `{mask, variant, remaining: telegraph}`; when a queued telegraph reaches 0 spawn
`hazards/projectile.tscn` under `Projectiles` at the boss position projected to each lane centre of the mask (one
projectile per contiguous lane group: `orb` → one lane, `wide` → 2 adjacent, `low`/`high` → full width), set
`kind = &"projectile"`, `variant`, `closing_speed`, `setup(game)`, emit `boss_projectile_fired(...)`, call
`visual.play_attack(variant)`; `_attack_timer = attack_interval(phase)`. Tool spawning: `_tool_timer -= delta`; when
≤ 0, or when `boss_tool_guarantee_seconds` passed with no tool alive, spawn `powerups/tool_pickup.tscn` under `Tools`
at `(lane_x, y, boss_tool_spawn_z)`; kind rolled by weight, biased to the accepted set with `boss_shield_tool_bias`
during a resisting phase; `_tool_timer = tool_interval` and `_since_tool = 0` on **every** attempt, so a draw that
cannot place anything does not come back on the next tick. Timeout: `_fight_timer ≥ boss_timeout_seconds` →
`_retreat()`.

Tool lane (contract §11.7): a lane is **blocked** when a live projectile covers it (lane-mask intersection, the
projectile still short of `boss_tool_lane_clearance` metres past the player — past that the player can cross in
behind it) **or** a queued telegraph's mask covers it; a full-width mask blocks nothing, because that attack is
answered with a jump or a roll rather than with a lane change (the same rule `autopilot.pending_lane_mask()`
applies). The draw takes a random unblocked lane that differs from the last tool lane; when the no-repeat rule
leaves only blocked lanes it takes the one whose blocking projectile is furthest along (highest track z, so the
first lane to free up), and a lane held by a telegraph alone — nothing in flight yet — sorts last. The no-repeat
rule is never broken, so a tool is always placed and the guarantee holds.

Damage: `apply_tool(kind)` (called by `tool_pickup.collect`): `damage = ToolDefs.damage(kind) if accepted else 0`;
`hp = max(hp − damage, 0)`; `boss_damage_dealt += damage`; `tools_used += 1`; emit `tool_collected(kind, damage)`;
`visual.play_hit / play_resist`; `camera_rig.shake(0.35)` when damaging; `score.add_bonus(tool_bonus, &"tool")`;
`boss_health_changed`; phase thresholds crossed → `phase += 1`, emit `boss_phase_changed(phase)`,
`visual.set_phase(phase)`, `_attack_timer = min(_attack_timer, 0.6)`; `hp == 0` → `_defeat()`. `_defeat()`: bonus
`= boss_kill_bonus_base + boss_kill_bonus_per_stage × (stage_index − 1)` added to score, emit
`boss_defeated(kind, bonus)`, `visual.play_defeat()`, clear queued telegraphs, `clear()` live projectiles (no dodge
credit), free live tools, `_outro = boss_outro_seconds`; `_retreat()`: bonus `= kill_bonus × boss_retreat_bonus_ratio ×
(1 − hp / max_hp)`, emit `boss_retreated`, `visual.play_retreat()`, same cleanup. After the outro `finished` is
set (a plain bool the StageManager polls), the boss node is freed. `abort()` (on caught) frees everything without
signals or bonuses.

Both endings can be reached from inside a physics callback — the killing blow is a tool auto-firing in
`area_entered`, and a catch aborts the fight the same way — so the arena **never** takes a projectile or a tool out
of the tree by hand (§9): each one is marked `consumed`, has `monitoring` disabled with `set_deferred` and is
`queue_free()`d, which is already end-of-frame. `clear()` has removed the projectile from `runner_hazards`
synchronously, so nothing on the way out can score a dodge (tools are in `runner_tools`, which `_track_dodges`
never scans) or damage anything after the fight. `projectile_count()` / `tool_count()` skip queued nodes, so both
still read 0 on the tick the fight ends. `get_info()` returns the empty contract §11.4 block (`kind &""`, `name ""`,
`hp`/`max_hp`/`phase`/`phase_count` 0, empty arrays) whenever no fight is active — before the first one and from the
end of the outro — which is the same shape `RunnerGame.get_boss_info()` returns with no arena mounted. During a fight
`phase_count` is the fight's own phase count (`BossDefs.PHASE_COUNT`, 3 today), so a HUD can draw "2 / 3" from the one
dictionary; the facade mirror fills in the same constant when no arena is mounted.

Patterns (beat lists; `L` = random single lane, `Ladj` = two adjacent lanes leaving one free, `alt` = alternate):
Swarm P1 `orb L`; P2 `orb Ladj` (two orbs); P3 `high, low` alt. Hydra P1 `wide (one lane free)`; P2 `orb lane0 +
orb lane2`, every 3rd beat `high`; P3 `wide, low` alt. Monolith P1 `low`; P2 `wide alt sides`, every 3rd beat
`high`; P3 `low, high, orb L`. Accepted tools: all, except Hydra P2 {`unit_test`, `lint_rule`}, Monolith P2
{`auto_fix_patch`, `review_comment`}, Monolith P3 {`unit_test`}.

### 10.4 `hazards/projectile.gd/.tscn` and `powerups/tool_pickup.gd/.tscn`

`projectile.gd extends "res://scenes/runner/hazards/hazard.gd"`: `closing_speed: float`; `_ready` keeps hazard.gd's
layer/group setup; `_physics_process` (enabled while alive): `position.z += closing_speed × delta`; free past
`despawn_z`. `hazard_defs.gd` gains the four `projectile` variants (contract §11.6). Visual mount path
`hazards/visuals/projectile_visual.tscn` receives `closing_speed` as an extra base var (add it to
`hazard_visual_base.gd` with default 0.0). Consumed/cleared projectiles stop processing (existing rule).

`tool_pickup.gd extends "res://scenes/runner/powerups/power_up.gd"`: group `runner_tools` instead of
`runner_powerups`; `collect(player)` sets `consumed = true`, `set_deferred("monitoring", false)` (inside an area callback), calls
`game.boss_encounter.apply_tool(kind)` (guarded), plays the visual `on_collected()`, then `queue_free()` (never a
synchronous free); moves +Z at `game.speed` like chunks (so Nitro raises throughput); frees past
`despawn_z`. `powerups/tool_defs.gd`: kinds, display names, damage, weights, spawn y (contract §11.7). Visual mount
`powerups/visuals/<kind>_visual.tscn`; graybox fallback: an ORANGE sphere r 0.35 with a Label3D tag.

### 10.5 `systems/turn_rig.gd` and `camera_rig.set_turn`

`turn_rig.gd` (Node3D at `World/TurnRig`): `set_turn(progress, direction)`: if the mounted corridor
`has_method("set_turn")` → forward and keep `rotation.y = 0`; else (graybox) `rotation.y = direction ×
deg_to_rad(turn_yaw_degrees) × smoothstep(0, 1, progress)`; `(0, 0)` resets. `camera_rig.gd` gains
`set_turn(progress, direction)` (which only records the pair) and the **ramp–hold–return** envelope
`turn_swing_profile(p)`, replacing the v1 `sin(PI × p)` wave so the corner reads as a committed turn:

```text
p ≤ 0 or p ≥ 1                  -> 0                                    (endpoints first, so any fractions are safe)
p <  in                         -> smoothstep(0, 1, p / in)             ramp up
in ≤ p ≤ 1 − out                -> 1                                    hold at the peak
p >  1 − out                    -> smoothstep(0, 1, (1 − p) / out)      return
in = turn_swing_in_fraction, out = turn_swing_out_fraction, both clamped to 0..1 and scaled by 1/(in + out) when they overlap
```

`yaw = direction × deg_to_rad(turn_camera_yaw_degrees) × turn_swing_profile(progress)` and
`bank = direction × deg_to_rad(turn_camera_bank_degrees) × turn_swing_profile(progress)`, applied in
`_physics_process` on top of the follow/shake result (yaw about the player's position, so the camera ends exactly
where it started at p = 1). The profile is monotone over each ramp and exactly 0 at both ends, so the camera is
never left displaced; gameplay is untouched, because only the camera and the corridor bend.
`RunnerGame.track_z(node) = turn_rig.to_local(node.global_position).z` when the rig exists, else
`node.global_position.z` (identity today because chunks never sit under the rig); `_track_dodges`,
`clear_hazards_in_range` and the autopilot entry use it.

### 10.6 Spawner and autopilot

`chunk_spawner.gd`: `spawning := true`, `set_spawning(on)`; `_fill()` returns early when `not spawning or game.phase
!= &"run"`; movement/despawn continue in every phase; breather weighting/pursuit relief unchanged.
`clear_hazards_in_range()` also clears projectiles (they are in `runner_hazards`).

`autopilot.gd`: each planned slice carries `closing_v` (`closing_speed` when present, else `game.speed`) and its
trigger distance is computed from it; projectile entries never merge with chunk-hazard entries. While
`phase == &"boss"`: subscribe to `boss_attack_telegraph`, plan from the telegraph (arrival = telegraph + travel at
`closing_v`), act at `arrival − manoeuvre_cost − autopilot_telegraph_lead`; between attacks run the greedy pickup
over `runner_tools`, skipping lanes a pending attack will block, scaled by `autopilot_tool_greed`. Planning stays
pure so `runner_boss_validator.gd` can drive it offline.

### 10.7 HitManager, Pursuer, DebugOverlay, score

HitManager emits `pursuit_alert(&"warn", recovery_seconds)` with `pursuit_started`, `&"critical"` once when
`recovery_remaining ≤ pursuit_critical_seconds`, `&"clear"` on recovery or catch. Pursuer emits
`pursuer_distance_changed(normalized)` when it changes by more than `pursuer_distance_epsilon`. DebugOverlay adds
lines for phase, stage index/distance/target, boss kind/hp/phase, pending attacks and tool count. ScoreManager:
`add_bonus(points, reason)` reasons gain `&"tool"`, `&"boss_kill"`, `&"boss_retreat"`, `&"stage_clear"`.
Leaderboard `SCHEMA_VERSION = 2`: version-1 boards are read normally and rewritten as version 2 on the next successful save; only versions > 2 are refused (contract §11.11).

### 10.8 Tests (extends §8)

`runner_logic.gd` new sections: stage machine (targets, drain, timeout clear, phase ordering, one `stage_started`
per stage, `run_clock` frozen outside `run`); escalation formula at cycles 0–4 hitting floors/caps; boss HP/phase
transitions and one `boss_phase_changed` per crossing; tool damage incl. resisted phases (`tool_collected(kind, 0)`);
boss timeout → `boss_retreated` with the partial bonus and never `boss_defeated`; turn state (signals once, rig and
camera back at zero, no spawn during the bend) plus `turn_incoming` once per seam ahead of `turn_started`, on the
same direction and with `seconds ∈ [0, turn_warning_seconds + 0.5]`; the camera swing profile (0 at p = 0 and
p = 1, at the peak across the hold window, monotone through each ramp); `boss_intro` exactly once per fight,
before `boss_spawned`, carrying `boss_intro_seconds`, with no telegraph and no tool inside that window;
`pursuit_alert` ordering and the epsilon gate; caught mid-boss aborts
to `idle` with `run_finished` once and boss stats in the result; speed with stage bonus and difficulty floor.
`runner_smoke.gd`: duplicated config `stage_base_distance 260`, `time_to_max_speed 20`, `boss_hp_scale 0.4` (so the
stage-1 boss opens on 40 hp rather than its authored 100), at the
existing acceleration: stage 1 → `turn_incoming` ahead of `turn_started`/`turn_finished` → `boss_spawned` → tools damage → `boss_defeated` →
`stage_cleared` → `stage_started(2, …)` within a bounded wall clock with zero projectile hits; a second probe forcing
PURSUED plus a projectile mid-fight ends the run once with the boss stats present; the kill leaves the arena empty
(no `runner_tools` node and no blocking projectile two frames later) and raises no engine error.
`runner_chunk_validator.gd`: the spawner places nothing outside `run`; `BossArena` holds no chunk; tool spawns
respect the lane rule above (live projectile, queued telegraph, full-width exemption, furthest-along fallback),
no-repeat and y ∈ {1.0, 2.2}. New `runner_boss_validator.gd`: every boss × phase × pattern × entry lane × cycle 0–4 through the virtual
runner (gravity 28, jump 9.8/0.70 s, roll 0.70 s, lane tween 0.13 s) driven by the real autopilot planner from the
telegraph: zero hits; `telegraph + travel ≥ 0.98 s`; jump launch window leaves ≥ 0.35 s; every pattern leaves a free
lane or is jumpable/rollable; an accepted tool is reachable at least once per `boss_tool_guarantee_seconds`.
`runner_scaffold_check.gd`: new tree paths (`World/TurnRig/...`, `Systems/StageManager`), new signals/properties,
optional UI mounts tolerated when absent. Every test that instantiates RunnerGame keeps the `leaderboard_path`
override before `add_child`.
