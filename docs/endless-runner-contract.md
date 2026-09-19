# Endless Runner — Backend/Frontend Contract

Version 1.1 · 2026-09-19 · GDScript

**Engine version policy.** The project pins **Godot 4.7.1** (GDD). The editor installed on the build
machine during this cycle is **4.7.0 stable** (`4.7.stable.official.5b4e0cb0f`), so every verification
result recorded in the runner docs was produced on 4.7.0 unless it says otherwise. Both are supported
for development; any behavioural difference found between 4.7.0 and 4.7.1 must be recorded in §10, and
final acceptance of the runner re-runs the §9 commands on 4.7.1.

This document is the single source of truth shared by the two agents building the Endless Runner
("The Codebase Corridor"):

- **Backend (Claude)** owns gameplay logic, project configuration, autoload additions, graybox
  fallbacks, tests, and this contract.
- **Frontend (Codex)** owns everything the player sees and hears: Hoppy's model and animation, hazard,
  power-up and pursuer visuals, the corridor environment, HUD, runner menu, game over, pause, audio, shaders.

Neither side edits the other's files. Changes to this contract are made by the backend and announced
in the PR description. Design authority: the GDD Endless Runner section and
`Hoppys_Adventure_Arcade_Technical_Implementation.md` §9.

## 1. Ownership

| Owner | Paths (relative to `hoppys-adventure-arcade/` unless noted) |
|---|---|
| Backend | `project.godot`, `app/*`, `scenes/runner/runner_game.{tscn,gd}`, `scenes/runner/runner_layers.gd`, `scenes/runner/systems/*`, `scenes/runner/player/runner_player.{tscn,gd}`, `scenes/runner/player/runner_visual_base.gd`, `scenes/runner/hazards/hazard.{tscn,gd}`, `scenes/runner/hazards/hazard_defs.gd`, `scenes/runner/hazards/hazard_visual_base.gd`, `scenes/runner/powerups/power_up.{tscn,gd}`, `scenes/runner/powerups/power_up_defs.gd`, `scenes/runner/powerups/power_up_visual_base.gd`, `scenes/runner/pursuer/pursuer.gd`, `scenes/runner/pursuer/pursuer_visual_base.gd`, `scenes/runner/chunks/*`, `scenes/runner/data/*`, `tests/*` except `tests/runner_visual_smoke.gd`, repo `docs/endless-runner-contract.md`, `docs/endless-runner-systems.md`, `docs/agent-briefs/*` |
| Frontend | `scenes/runner/runner_menu.{tscn,gd}`, `scenes/runner/environment/**`, `scenes/runner/ui/**`, `scenes/runner/audio/**`, `scenes/runner/shaders/**`, `scenes/runner/player/hoppy_runner_visual.{tscn,gd}` and `scenes/runner/player/dev/**`, `scenes/runner/hazards/visuals/**`, `scenes/runner/powerups/visuals/**`, `scenes/runner/pursuer/pursuer_visual.{tscn,gd}`, `Assets/runner/**` (with `Assets/runner/LICENSES.md`), `tests/runner_visual_smoke.gd`, repo `docs/endless-runner.md`, `docs/previews/endless-runner-*.png` |

Rules:

1. The backend ships **graybox placeholders** at four frontend paths in the contract PR
   (`runner_menu.tscn`, `ui/runner_hud.tscn`, `ui/pause_menu.tscn`, `ui/game_over.tscn`) so the game
   is playable with no art. After that PR the backend never edits them again; the frontend may
   overwrite or delete them freely.
2. Every other frontend scene is **optional at runtime**. Backend code mounts a frontend scene only if
   `ResourceLoader.exists(path)`; otherwise it builds a primitive graybox in code. A missing or broken
   frontend file must never stop `runner_game.tscn` from loading.
3. All backend → frontend calls are guarded with `has_method`. The frontend never needs to implement
   a hook it does not use.
4. Code style for both sides (matches the repo): `snake_case` files, **no `class_name`**,
   `const X = preload("res://...")`, typed GDScript with `:=`, tabs, an explicit return type on every
   function (`-> void` for procedures), UI built
   imperatively in `_ready()` using `scenes/main_menu/menu_style.gd` (`Style.theme()`, `Style.label()`,
   `Style.button()`). Commit generated `.gd.uid` files. Never mutate shared `.tres` resources at runtime.

## 2. Scene flow and routes

```
hub ──AppRouter.go("runner")──▶ runner_menu.tscn (RunnerMenu)
        ▲                            │ Play → AppRouter.go("runner_game")
        │ Return / ui_cancel         ▼
        └──────────────────── runner_game.tscn (RunnerGame) ──▶ GameOver overlay (inside runner_game)
                                     ▲                               │ Retry → game.retry()  (AppRouter.go("runner_game"))
                                     └───────────────────────────────┘ Menu  → game.go_to_menu() (AppRouter.go("runner"))
```

- `AppRouter.ROUTES` already maps `"runner"` to `res://scenes/runner/runner_menu.tscn`; it gains
  `"runner_game": "res://scenes/runner/runner_game.tscn"`.
- Inside `runner_game.tscn` (pause menu, game over), frontend buttons call `game.retry()` /
  `game.go_to_menu()` rather than `AppRouter` directly, so the tree is never left paused. The runner
  menu scene, which has no game instance, calls `AppRouter.go(...)` / `AppRouter.quit_game()` itself.
- The runner menu keeps the hub's return contract: a "Return to Main Menu" button → `AppRouter.go("hub")`
  and `ui_cancel` → hub. Quit → `AppRouter.quit_game()`.
- Music: the runner menu and `runner_audio` call `AudioService.play_music(stream, -12.0)`; the call is a
  no-op if that stream is already playing, so menu → game does not restart the track. `AppRouter`
  restores the hub track when routing to `hub`.

## 3. `runner_game.tscn` structure

```
RunnerGame (Node3D, runner_game.gd, process_mode ALWAYS)            backend
├─ Systems (Node, PAUSABLE)
│  ├─ SpeedController  ├─ HitManager  ├─ ScoreManager  ├─ EffectManager
│  ├─ Spawner          └─ Autopilot (disabled unless tests / F7)
├─ World (Node3D, PAUSABLE)
│  ├─ Floor (StaticBody3D, BoxShape3D 12×1×400 with top at y = 0, layer World)   backend, invisible when a corridor is mounted
│  ├─ Chunks (Node3D)               spawner parents live chunks here
│  ├─ GrayboxEnvironment (Node3D)   backend lighting + grid; freed when a corridor mounts
│  └─ Environment (Node3D)          MOUNT: environment/corridor.tscn
├─ Player (runner_player.tscn root CharacterBody3D, PAUSABLE)      backend
│  ├─ BodyShape (CapsuleShape3D r 0.4, h 1.8, centre y 0.9)
│  ├─ Hurtbox (Area3D, layer PlayerHurtbox, monitorable only)
│  │  ├─ StandShape (CapsuleShape3D r 0.4 h 1.8)  └─ RollShape (CapsuleShape3D r 0.4 h 0.9, disabled)
│  └─ Visual (Node3D)               MOUNT: player/hoppy_runner_visual.tscn
├─ Pursuer (Node3D, pursuer.gd)                                     backend
│  └─ Visual (Node3D)               MOUNT: pursuer/pursuer_visual.tscn
├─ CameraRig (Node3D, camera_rig.gd) └─ Camera (Camera3D)          backend, exports tunable by frontend
├─ HUD (CanvasLayer 10, PAUSABLE)   MOUNT: ui/runner_hud.tscn
├─ Overlays (CanvasLayer 20, ALWAYS) MOUNT: ui/pause_menu.tscn, ui/game_over.tscn
├─ Audio (Node, ALWAYS)             MOUNT: audio/runner_audio.tscn
└─ DebugOverlay (CanvasLayer 90, ALWAYS, debug_overlay.gd)          backend; F3 toggles
```

Mounting: for each `MOUNT` path that exists, `load(path).instantiate()` is added under the mount node
and, if it has `bind`, `bind(self)` is called **before** `run_started` is emitted. Hazard, power-up,
pursuer and player roots mount their own `Visual` the same way (`<kind>_visual.tscn` if it exists,
else a code-built primitive).

Physics: 60 Hz, Jolt, `physics/common/physics_interpolation = true`. World forward is −Z. The player
never moves in Z (`axis_lock_linear_z`); chunks move toward +Z at the authoritative speed.

## 4. The facade: `RunnerGame`

### 4.1 Signals (frontend connects to these; nothing else)

| Signal | When |
|---|---|
| `run_started(seed: int)` | After every system is reset and the first chunks are placed |
| `state_changed(state: StringName)` | `ready` → `running` → `caught` → `finished` |
| `health_changed(hp: int, max_hp: int)` | Initial emission after `run_started`, then on every change |
| `damage_taken(kind: StringName, hp: int)` | An unblocked hit landed (`kind` = hazard kind) |
| `damage_blocked(kind: StringName, reason: StringName)` | `reason` ∈ `iframes`, `shield`, `lgtm`, `nitro`, `super_jump` |
| `shield_changed(active: bool)` | Approve Shield stored / consumed |
| `pursuit_started(recovery_seconds: float)` | First hit while SAFE |
| `pursuit_progress(remaining: float, total: float)` | Every physics tick while PURSUED |
| `pursuit_recovered(reason: StringName)` | `timer` (clean 18 s) or `shield` (shield absorbed a hit while pursued) |
| `caught()` | Second hit while PURSUED; the catch cinematic starts (world decelerates, controls lock) |
| `run_finished(result: Dictionary)` | `caught_sequence_seconds` (1.6 s) after `caught`; leaderboard already written. Show Game Over here. Emitted exactly once per run |
| `leaderboard_saved(entries: Array, rank: int)` | Just before `run_finished`, and again after a successful `submit_name` |
| `score_changed(score: int, multiplier: float)` | Only when the integer score or the multiplier changes |
| `bonus_awarded(points: int, reason: StringName)` | Pickup or blast bonus |
| `speed_changed(speed: float, normalized: float)` | Every physics tick; `normalized = (speed − base_speed) / (max_speed − base_speed)`, may exceed 1.0 during Nitro |
| `difficulty_changed(difficulty: float)` | When difficulty moves by ≥ 0.01 |
| `power_up_collected(kind: StringName, duration: float)` | `duration` 0 for one-shot kinds |
| `power_up_expired(kind: StringName)` | Timed effect ended, Code Review Bonus lost, or Super Jump consumed |
| `hazard_cleared(hazard: Area3D)` | Auto-Fix removed one hazard (its visual already received `on_cleared()`) |
| `hazards_blasted(count: int)` | Once per Auto-Fix, after all `hazard_cleared` |
| `player_action(action: StringName)` | `jump`, `super_jump`, `land`, `roll`, `roll_end`, `lane_left`, `lane_right`, `lane_blocked`, `hurt`, `dead` |
| `chunk_spawned(chunk: Node3D)` | Debug / cosmetic use |
| `paused_changed(paused: bool)` | Pause menu shows on `true` |

### 4.2 Read-only properties

`config` (RunConfig), `state: StringName`, `paused: bool`, `seed: int`, `run_id: String`,
`elapsed: float` (unpaused running seconds), `distance: float` (metres), `speed: float`,
`normalized_speed: float`, `difficulty: float` (0–1), `hp: int`, `score: int`, `multiplier: float`,
`player: CharacterBody3D`, `camera_rig: Node3D`, `cosmetic_rng: RandomNumberGenerator` (seeded per run;
frontend may use it for deterministic cosmetics).

### 4.3 Methods the frontend may call

| Method | Behaviour |
|---|---|
| `pause()` / `resume()` / `toggle_pause()` | Only while `running`. `resume()` re-syncs held input so nothing fires on unpause |
| `retry()` | Unpauses and routes to `runner_game` (fresh session) |
| `go_to_menu()` | Unpauses and routes to `runner` |
| `hit_stop(seconds: float)` | Brief `Engine.time_scale` dip owned by the backend (max 0.12 s) |
| `submit_name(name: String) -> bool` | Sanitises (trim, strip control chars, ≤ 16, blank → `Hoppy`) and renames this run's leaderboard entry. Returns `true` if persisted. Never adds a second entry |
| `get_leaderboard() -> Array[Dictionary]` | Current top 10 |
| `get_result() -> Dictionary` | Empty until `finished` |
| `get_active_effects() -> Dictionary` | `kind → {remaining, total}` snapshot for HUD polling |
| `camera_rig.shake(strength: float, duration := 0.35)` / `camera_rig.punch_fov(degrees: float, seconds: float)` | Camera juice |

`result` fields: `run_id, mode ("runner"), outcome ("caught"), score:int, score_exact:float,
duration:float, distance:float, hazards_dodged:int, power_ups:int, hazards_blasted:int, hits_taken:int,
recoveries:int, blocked_hits:int, seed:int, max_speed_reached:float, best_multiplier:float,
chunks_spawned:int, score_rule_revision:int, submitted_at:int, rank:int (1–10, 0 = not placed),
qualifies:bool, player_name:String`.

Leaderboard entry fields: `run_id, name, score:int, duration:float, seed:int, submitted_at:int`.
The runner menu reads the board without a game instance via the static
`preload("res://scenes/runner/systems/runner_leaderboard.gd").load_entries()`.

### 4.4 Input

The backend owns the `pause` action (Esc, P, gamepad Start): it toggles pause only while `running`.
Gameplay input is read only while `running` and controls are enabled, so Space on a focused Game Over
button never jumps. The pause menu must **not** bind `ui_cancel`; Game Over binds `ui_cancel` →
`go_to_menu()` only while visible.

## 5. Frontend scene contracts

Every visual root is a `Node3D` whose script `extends` the backend base script named below. Backend
sets base vars **before** calling `on_spawned()`. Visuals never free themselves; the backend owns lifetime.

### 5.1 `player/hoppy_runner_visual.tscn` — extends `player/runner_visual_base.gd`

| Method | Notes |
|---|---|
| `set_anim_state(state: StringName)` | `idle`, `run`, `jump`, `fall`, `roll`, `hurt`, `dead`. Called on change only. After `hurt` the visual auto-returns to `run` (or `idle`) unless a new state arrived; the backend also sends `run` after `land` / `roll_end` |
| `set_run_speed(normalized: float)` | Every physics tick; scale run cycle speed |
| `set_lane_lean(direction: float)` | −1..1 during a lane change, 0 otherwise |
| `show_aura(kind: StringName, on: bool)` | On power-up collect / expire for `lgtm`, `nitro`, `code_review` |
| `show_shield(on: bool)` | On `shield_changed` |
| `on_hit()` | Flash hook on unblocked hit |

Hoppy faces −Z, feet at y = 0, total height 1.8 m; the roll pose must fit inside 0.9 m.

### 5.2 `hazards/visuals/<kind>_visual.tscn` — extends `hazards/hazard_visual_base.gd`

Base vars set by the backend: `kind: StringName`, `variant: StringName`, `hitbox_size: Vector3`,
`hitbox_offset: Vector3` (centre relative to the hazard root), `lanes_mask: int` (bit 0 = x −2, bit 1 = x 0,
bit 2 = x +2), `dodge_hint: StringName`.

| Hook | When |
|---|---|
| `on_spawned()` | After vars are set; reset all tweens/particles (hazards may be reused later) |
| `on_hit_player()` | This hazard damaged (or was blocked by) the player |
| `on_cleared()` | Auto-Fix removed it; play a "fixed" reaction, the hitbox is already off |
| `set_telegraph(t: float)` | Timed laser only: 0 → 1 during the 0.4 s before a state change, every physics tick |
| `set_laser_state(state: StringName)` | Timed laser only: `ground`, `high`, `off` |

Visual bounds must stay within 110 % of `hitbox_size` on every axis so what you see is what hits you.

### 5.3 `powerups/visuals/<kind>_visual.tscn` — extends `powerups/power_up_visual_base.gd`

Base var `kind`. Hooks `on_spawned()`, `on_collected()`. Pickup sphere radius 0.35, centred at the root.

### 5.4 `pursuer/pursuer_visual.tscn` — extends `pursuer/pursuer_visual_base.gd`

`set_threat(t: float)` (0 retreated … 1 about to catch, every tick while pursued), `play_catch()`
(on `caught`, ~1.4 s), `play_retreat()` (on `pursuit_recovered`). The backend positions the pursuer root
at y = 0 between the camera and the player: z = lerp(12, 4.5, threat). Keep the visual ≤ 6 m wide and
≤ 2.6 m tall at threat 1 so it looms in the lower third of the frame without hiding hazards.

### 5.5 `environment/corridor.tscn` — root `Node3D`

`set_scroll_speed(speed: float)` every physics tick (m/s); optional `set_pursuit(t: float)` (0–1).
Visual floor top at y = 0, lanes at x = −2, 0, +2, corridor ≈ 8 m wide, visible depth to z ≈ −90.
The physical floor is backend-owned and invisible once a corridor mounts. The corridor may set
`get_viewport().scaling_3d_scale` for a retro look; in `_exit_tree` it must restore the value it replaced
(two corridors can coexist briefly, e.g. menu backdrop and game, so track ownership rather than resetting to 1.0).

### 5.6 UI and audio — `bind(game: Node)`

| Scene | Root | Extra API |
|---|---|---|
| `ui/runner_hud.tscn` | CanvasLayer | — |
| `ui/pause_menu.tscn` | CanvasLayer, `process_mode ALWAYS` | Shows on `paused_changed(true)`; buttons → `game.resume()`, `game.retry()`, `game.go_to_menu()` |
| `ui/game_over.tscn` | CanvasLayer, `process_mode ALWAYS`, hidden | `show_result(result: Dictionary, leaderboard: Array)` is called by the frontend itself from `run_finished`; name entry → `game.submit_name()`; Retry / Menu as above |
| `audio/runner_audio.tscn` | Node, `process_mode ALWAYS` | SFX on bus `SFX`; BGM via `AudioService.play_music` |
| `runner_menu.tscn` | root named **`RunnerMenu`** | See §2 |

`AudioService` API available to the frontend: `play_music(stream: AudioStream, volume_db := -10.0)`,
`play_default_music()`, `set_music_pitch(scale: float)`, `duck_music(db: float, seconds: float)`,
`play_ui(kind: int)` (existing: 0 hover, 1 confirm, 2 route). `AudioService.music` is the shared
`AudioStreamPlayer` on bus `Music`.

## 6. Physics layers and input map (`project.godot`, backend-owned)

`layer_names/3d_physics`: 1 `World`, 2 `PlayerBody`, 3 `EnemyHitbox`, 4 `PlayerHurtbox`, 5 `Pickup`.

| Node | layer | mask | monitoring / monitorable |
|---|---|---|---|
| `World/Floor` | 1 | 2 | — |
| `Player` body | 2 | 1 | — |
| `Player/Hurtbox` | 8 (4) | 0 | false / true |
| Hazard root Area3D | 4 (3) | 8 | true / false |
| Power-up root Area3D | 16 (5) | 8 | true / false |

Actions: `move_left` (A, ←, D-pad ←, left stick −X), `move_right` (D, →, D-pad →, +X), `move_up`
(W, ↑, D-pad ↑, stick −Y), `move_down` (S, ↓, D-pad ↓, +Y), `jump` (Space, W, ↑, gamepad A/0),
`roll` (Ctrl, S, ↓, gamepad B/1), `pause` (Esc, P, gamepad Start/6). Keys are bound by
`physical_keycode`. Stick deadzone 0.5 on the four `move_*` actions.

## 7. Authoritative tuning (`scenes/runner/data/run_config.tres`)

| Group | Values |
|---|---|
| Lanes / body | `lane_width 2.0`, `lane_change_time 0.13`, capsule r 0.4, standing 1.8 m, rolling 0.9 m |
| Jump / roll | `gravity 28`, `jump_velocity 9.8` (apex 1.715 m, airtime 0.70 s), `super_jump_velocity 13.2` (apex 3.11 m), `jump_buffer 0.10`, `coyote_time 0.06`, `roll_duration 0.70`, `roll_cooldown 0.25`, fast-fall gravity ×2.5 |
| Speed | `base_speed 12`, `max_speed 24` at `time_to_max_speed 165` (smoothstep), then +1 m/s per 60 s to `hard_cap 26`; `nitro_speed_multiplier 1.25` applied after the curve and then clamped: `speed = min(curve_speed × 1.25, nitro_speed_cap 32)` |
| Health | `max_hp 2`, `recovery_seconds 18`, `hit_iframes 0.8`, `caught_sequence_seconds 1.6` |
| Score | `base_score_rate 10` pts/s × (Nitro ×2) × (Code Review ×1.5); `pickup_bonus 25`; `blast_bonus_per_hazard 10`; fractional accumulator, integer display |
| Effects | `lgtm_duration 5`, `nitro_duration 8` (+1 s ease-down with i-frames), Super Jump invulnerable in flight + 0.5 s, Code Review Bonus lost on unblocked hit only, refresh-not-stack |
| Spawner | `spawn_horizon_z −90`, `despawn_z 12`, `max_active_chunks 9`, `t_spacing(d) = lerp(1.2, 0.85, d)` (+0.15 s while pursued), `gap = max(0, v × 1.02 × t_spacing − prev.exit_clear − next.entry_clear)`, `min_hazard_depth 1.2` (pits 3.0), `blast_range_z 60`, 50 % chunk X-mirroring, no immediate repeats |
| Power-ups | chance per chunk `lerp(0.55, 0.35, d)`; cooldown 10 s + one chunk; weights shield 25, code_review 25, super_jump 15, nitro 15, auto_fix 10, lgtm 10; no same-kind repeat; sphere r 0.35 at y 1.0 (run) or 2.2 (jump) |
| Camera | position (0, 4, 8), look at (0, 1, −8), `fov 60`, lateral follow 0.4, follows in `_physics_process` |
| Pursuer | `retreat_z 12`, `approach_z 4.5`; threat = 0.7 · min(t_since_hit / 1.5, 1) + 0.3 · (1 − remaining / total) |
| Difficulty | `difficulty = clamp(elapsed / 165, 0, 1)`; driven by unpaused time only |

## 8. Authoritative hazard table

`kind` is the visual scene id (`hazards/visuals/<kind>_visual.tscn`); `variant` is passed to the visual.
Per-lane hitbox width 1.6 m (x ± 0.8 around the lane centre); full width 5.6 m; two adjacent lanes 3.6 m.
Every hitbox is a `BoxShape3D`; depth is along Z. Hitboxes are static from spawn (slams and sweeps are
visual), except the timed laser, which switches between discrete states with the hitbox off in between.

| kind | variant | W × H × D (m) | y range | lanes | dodge_hint | CodeRabbit story |
|---|---|---|---|---|---|---|
| `pr_backlog_low` | – | 5.6 × 1.0 × 1.2 | 0 – 1.0 | all | `JUMP` | Stacked unreviewed PR cards blocking the corridor |
| `pr_backlog_high` | – | 5.6 × 1.8 × 1.2 | 1.1 – 2.9 | all | `ROLL` | Hanging PR cards; roll under |
| `bug_swarm` | – | 1.6 × 0.9 × 1.2 | 0 – 0.9 | 1 | `JUMP_OR_LANE` | Glowing bug icons at ground level |
| `merge_conflict` | – | 3.6 × 1.0 × 1.2 | 0 – 1.0 | 2 adjacent | `JUMP_OR_LANE` | Two branches slammed together (`<<<<<<< HEAD` / `>>>>>>>`) |
| `deprecated_pit` | `full` / `two_lane` | 5.6 or 3.6 × 0.4 × 3.0 | −0.2 – 0.2 | all / 2 | `JUMP` / `JUMP_OR_LANE` | Crumbled `@deprecated` floor |
| `laser_grid` | `ground` | 5.6 × 0.4 × 1.2 | 0.1 – 0.5 | all | `JUMP` | CI security scan beam |
| `laser_grid` | `mid` | 5.6 × 0.3 × 1.2 | 1.0 – 1.3 | all | `ROLL_OR_JUMP` | Roll is safe, jump is expert |
| `laser_grid` | `high` | 5.6 × 0.4 × 1.2 | 1.1 – 1.5 | all | `ROLL` | Chest-height beam |
| `laser_grid` | `timed` | ground ⇄ high: 1.2 s on, 0.3 s off (period 3.0 s, phase from the run clock) | | all | `TIMED` | Sweeping scanner |
| `comment_flood` | – | 3.6 × 4.0 × 1.2 | 0 – 4.0 | 2 adjacent | `LANE` | Wall of nitpick comments; too tall to jump |
| `build_shockwave` | – | 5.6 × 0.5 × 1.2 | 0 – 0.5 | all | `JUMP` | Failed-build blast ring |

Power-up kinds: `approve_shield`, `auto_fix`, `lgtm`, `nitro`, `super_jump`, `code_review`.

## 9. Verification commands (run from the repo root)

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_logic.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_chunk_validator.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/menu_smoke.gd
```

Per-file lint: `--headless --path hoppys-adventure-arcade --script res://<file>.gd --check-only`.
Baseline note (2026-09-19): on the installed Godot 4.7.0 the pre-existing `menu_smoke.gd` reports two
mouse-hover failures on a clean `main`; the docs validated it on 4.7.1. New runner tests must pass fully.

## 10. Change log

- 1.0 (2026-09-19): initial contract reconciled from the backend, procgen/tuning and frontend design passes.
- 1.1 (2026-09-19): engine version policy (4.7.1 pin, 4.7.0 validation); AppRouter rule scoped to in-game overlays; routes wording clarified; leaderboard writes keep a `.bak`; Nitro cap arithmetic and viewport-scale restore semantics clarified; return-type rule generalised.
