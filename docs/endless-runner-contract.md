# Endless Runner — Backend/Frontend Contract

Version 2.4 · 2026-09-28 · GDScript · v2 (stages, turns, bosses) is specified in §11 and overrides §2–§8 where they conflict

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
| Backend | `project.godot`, `app/*`, `scenes/runner/runner_game.{tscn,gd}`, `scenes/runner/runner_layers.gd`, `scenes/runner/systems/*`, `scenes/runner/player/runner_player.{tscn,gd}`, `scenes/runner/player/runner_visual_base.gd`, `scenes/runner/hazards/hazard.{tscn,gd}`, `scenes/runner/hazards/hazard_defs.gd`, `scenes/runner/hazards/hazard_visual_base.gd`, `scenes/runner/powerups/power_up.{tscn,gd}`, `scenes/runner/powerups/power_up_defs.gd`, `scenes/runner/powerups/power_up_visual_base.gd`, `scenes/runner/pursuer/pursuer.gd`, `scenes/runner/pursuer/pursuer_visual_base.gd`, `scenes/runner/chunks/*`, `scenes/runner/data/*`, `tests/*` except `tests/runner_visual_smoke.gd`, repo `docs/endless-runner-contract.md`, `docs/endless-runner-systems.md`, `docs/agent-briefs/*`, `scenes/runner/boss/boss_arena.tscn`, `scenes/runner/boss/boss_encounter.gd`, `scenes/runner/boss/boss_defs.gd`, `scenes/runner/boss/boss_visual_base.gd`, `scenes/runner/hazards/projectile.{tscn,gd}`, `scenes/runner/powerups/tool_pickup.{tscn,gd}`, `scenes/runner/powerups/tool_defs.gd` (v2) |
| Frontend | `scenes/runner/runner_menu.{tscn,gd}`, `scenes/runner/environment/**`, `scenes/runner/ui/**`, `scenes/runner/audio/**`, `scenes/runner/shaders/**`, `scenes/runner/player/hoppy_runner_visual.{tscn,gd}` and `scenes/runner/player/dev/**`, `scenes/runner/hazards/visuals/**`, `scenes/runner/powerups/visuals/**`, `scenes/runner/pursuer/pursuer_visual.{tscn,gd}`, `Assets/runner/**` (with `Assets/runner/LICENSES.md`), `tests/runner_visual_smoke.gd`, repo `docs/endless-runner.md`, `docs/previews/endless-runner-*.png`, `scenes/runner/boss/visuals/**`, `scenes/runner/boss/boss_fx.{tscn,gd}`, `scenes/runner/boss/boss_art.gd`, `scenes/runner/boss/tool_art.gd`, `scenes/runner/boss/telegraph.*`, `scenes/runner/boss/tool_tracer.gd`, `scenes/runner/boss/damage_number.gd`, `scenes/runner/boss/dev/**` (v2) |

Rules:

1. The backend ships **graybox placeholders** at four frontend paths in the contract PR
   (`runner_menu.tscn`, `ui/runner_hud.tscn`, `ui/pause_menu.tscn`, `ui/game_over.tscn`) so the game
   is playable with no art. The frontend may overwrite or delete them freely.
   `ui/runner_hud`, `ui/pause_menu` and `ui/game_over` are frozen from the end of that PR: the backend
   never edits them again. `scenes/runner/runner_menu.*` has exactly one further backend edit, in PR 2,
   bringing the graybox up to the §2 four-button set so `tests/runner_scaffold_check.gd` can assert the
   same structure (`RunnerMenu` root, `buttons.size() == 4`) against either scene. **Once the frontend's
   F6 `runner_menu` lands it is exclusively frontend-owned and the backend never edits it again**; any
   later backend scaffold need goes in `docs/endless-runner.md` under "Requests to backend" instead.
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

```text
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
- The runner menu offers exactly four buttons, in this order: **`01 Play`** → `AppRouter.go("runner_game")`,
  **`02 Leaderboard`** → toggles a panel showing the top 10 read with the static
  `runner_leaderboard.load_entries()` (no game instance needed; short boards pad with `---`),
  **`03 Return to Main Menu`** → `AppRouter.go("hub")`, **`04 Quit Game`** → `AppRouter.quit_game()`.
  It keeps the hub's return contract, and `ui_cancel` closes the leaderboard panel first, else → hub.
- Music: the runner menu and `runner_audio` call `AudioService.play_music(stream, -12.0)`; the call is a
  no-op if that stream is already playing, so menu → game does not restart the track. `AppRouter`
  restores the hub track when routing to `hub`.

## 3. `runner_game.tscn` structure

```text
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

Mounting: for each `MOUNT` path, the backend calls `ResourceLoader.exists(path)`, then
`load(path) as PackedScene`; only a non-null `PackedScene` is instantiated and added under the mount node
(a missing, failed or wrongly typed resource is logged with `push_warning` and the code-built graybox is
used instead). If the instance has `bind`, `bind(self)` is called **before** `run_started` is emitted.
Hazard, power-up, pursuer and player roots mount their own `Visual` with the same validation
(`<kind>_visual.tscn` if valid, else a code-built primitive).

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
| `difficulty_changed(difficulty: float)` | When difficulty moves by ≥ 0.01, plus the terminal 1.0 — that last step is always announced even though it is inside the 0.01 window, and 1.0 is never emitted twice |
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

`start_run(seed := 0)` (backend-initiated; the frontend restarts through `retry()`) unpauses first: it goes
through `resume()`, which is valid in every `state` and a no-op when the game is not paused (the "only while
running" rule applies to the frontend's pause toggle, not to this internal call), so `paused`, `get_tree().paused`
and `paused_changed(false)` all agree and a run started from a paused state never begins frozen. It also clears the player visual's power-up state — `show_aura(kind,
false)` for every aura kind and `show_shield(false)` — so a fresh run never opens wearing the last one's glow.

`result` fields: `run_id, mode ("runner"), outcome ("caught"), score:int, score_exact:float,
duration:float, distance:float, hazards_dodged:int, power_ups:int, hazards_blasted:int, hits_taken:int,
recoveries:int, blocked_hits:int, seed:int, max_speed_reached:float, best_multiplier:float,
chunks_spawned:int, score_rule_revision:int, submitted_at:int, rank:int (1–10, 0 = not placed),
qualifies:bool, leaderboard_error:int, player_name:String`.
`leaderboard_error` is always present and is `OK` (0) when the board was written. Any other value
means the write failed, and then `rank` is 0, `qualifies` is `false` and `leaderboard_saved` is not
emitted for that run.

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
| `show_aura(kind: StringName, on: bool)` | On power-up collect / expire for `lgtm`, `nitro`, `code_review`. Also `false` for every kind on `start_run` (the visual outlives a run) |
| `show_shield(on: bool)` | On `shield_changed`, and `false` on `start_run` |
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
This rule applies to the collision-volume artwork; flat ground-projection quads at y ≈ 0 whose x/z extents
equal the hitbox footprint (floor markers, safe-gap markers) are exempt on the y axis. Performance budget:
a hazard visual should produce at most ~14 draw calls (count `MeshInstance3D`, `MultiMeshInstance3D`,
`GPUParticles3D` and `Label3D`; a `Label3D` with an outline costs two) because up to six hazards are visible.

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
| `runner_menu.tscn` | root named **`RunnerMenu`** | See §2. Exposes `buttons: Array[Button]` with the four §2 entries (`01 Play`, `02 Leaderboard`, `03 Return to Main Menu`, `04 Quit Game`); `tests/runner_scaffold_check.gd` asserts `buttons.size() == 4` |

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

## 7. Authoritative tuning (`scenes/runner/data/run_config.gd` defaults; `run_config.tres` is the empty override resource)

| Group | Values |
|---|---|
| Lanes / body | `lane_width 2.0`, `lane_change_time 0.13`, capsule r 0.4, standing 1.8 m, rolling 0.9 m |
| Jump / roll | `gravity 28`, `jump_velocity 9.8` (apex 1.715 m, airtime 0.70 s), `super_jump_velocity 13.2` (apex 3.11 m), `jump_buffer 0.10`, `coyote_time 0.06`, `roll_duration 0.70`, `roll_cooldown 0.25`, fast-fall gravity ×2.5 |
| Speed | `base_speed 12`, `max_speed 24` at `time_to_max_speed 165` (smoothstep), then +1 m/s per 60 s to `hard_cap 26`; `nitro_speed_multiplier 1.25` applied after the curve and then clamped: `speed = min(curve_speed × 1.25, nitro_speed_cap 32)` |
| Health | `max_hp 2`, `recovery_seconds 18`, `hit_iframes 0.8`, `caught_sequence_seconds 1.6` |
| Score | `base_score_rate 10` pts/s × (Nitro ×2) × (Code Review ×1.5); `pickup_bonus 25`; `blast_bonus_per_hazard 10`; fractional accumulator, integer display |
| Effects | `lgtm_duration 5`, `nitro_duration 8` (+1 s ease-down with i-frames), Super Jump invulnerable in flight + 0.5 s, Code Review Bonus lost on unblocked hit only, refresh-not-stack |
| Spawner | `spawn_horizon_z −90`, `despawn_z 12`, `max_active_chunks 9`, `t_spacing(d) = lerp(1.2, 0.85, d)`, `gap = max(0, v × 1.02 × (t_spacing(d) + (0.15 if pursued else 0)) − prev.exit_clear − next.entry_clear)` (parenthesised: `t_spacing(d)` always applies, the 0.15 s relief is added only while pursued) — the pursuit relief is inside the time term, not distance added after it; `v` is `max(speed, base_speed)`, `min_hazard_depth 1.2` (pits 3.0), `blast_range_z 60`, 50 % chunk X-mirroring, no immediate repeats |
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
| `laser_grid` | `timed` | cycle of 3.0 s from the run clock: `ground` on 1.2 s → `off` 0.3 s → `high` on 1.2 s → `off` 0.3 s (hitbox off in both `off` states) | ground / high rows | all | `TIMED` | Sweeping scanner |
| `comment_flood` | – | 3.6 × 4.0 × 1.2 | 0 – 4.0 | 2 adjacent | `LANE` | Wall of nitpick comments; too tall to jump |
| `build_shockwave` | – | 5.6 × 0.5 × 1.2 | 0 – 0.5 | all | `JUMP` | Failed-build blast ring |

Power-up kinds: `approve_shield`, `auto_fix`, `lgtm`, `nitro`, `super_jump`, `code_review`.

## 9. Verification commands (run from the repo root)

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_logic.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_chunk_validator.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_boss_validator.gd   # v2, see §11.12
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/menu_smoke.gd
```

Per-file lint: `--headless --path hoppys-adventure-arcade --script res://<file>.gd --check-only`.
Baseline note (2026-09-19): on the installed Godot 4.7.0 the pre-existing `menu_smoke.gd` reports two
mouse-hover failures on a clean `main`; the docs validated it on 4.7.1. New runner tests must pass fully.

## 10. Change log

- 2.4 (2026-09-28): §11.4/§11.5/§11.6/§11.10/§11.12 — boss signature attacks. Beats may carry a `signature` (boss_defs.gd): Flaky Test Swarm `flaky` (the telegraph alternates two candidate lanes for `boss_flaky_candidate_seconds`, then commits at least `boss_commit_min` before fire) and `scatter` (a half-speed orb down the middle that splits into the two outer lanes at track z −`boss_scatter_split_distance`); Merge Conflict Hydra `branching` (staggered heads, each telegraphed up front on its own lane), `sweep` (the low rebase sweep sliding outer lane → outer lane in flight) and `force_push` (phase 2's fourth head: a fast `wide`, telegraphed 1.6× longer); Legacy Monolith `legacy_wall` (a slow wall of slabs with one gap that shifts once to the next lane), `quake` (full-width ground shockwave, jump only) and `debris` (slabs falling onto floor shadows in 1–2 lanes). New facade signals `boss_attack_planned(attack)` and `boss_attack_committed(lane_mask, kind, seconds)`; `boss_attack_telegraph` now carries the candidate mask for a flaky beat; six new projectile variants (`scatter`, `sweep`, `force_push`, `slab`, `quake`, `debris`), each mapped to a base look for visuals that do not opt in; projectiles expose `boss_kind`, `signature`, `motion`, `age` and the motion API `lane_mask_at(t)` / `y_range_at(t)` / `impact_lane_mask()` (boss/boss_attacks.gd); the autopilot and `runner_boss_validator.gd` plan against that API, and the validator gains **B6**. Beats without a `signature` behave exactly as in 2.3. The Hydra taunt now matches its head count (3 heads, 4 from phase 2).
- 2.3 (2026-09-22): §11.1/§11.8/§11.10 — the stage-entrance guarantee. The `STAGE n` banner covers the lanes, so for `stage_banner_clear_seconds` (3.5) after every `stage_started`, stage 1 included, no blocking hazard may reach the player, and when that window ends the nearest one is still `stage_banner_reaction_seconds` (1.0) × speed metres away. `chunk_spawner.gd` gains `begin_clear_road(seconds)`, which the StageManager calls immediately before switching placement back on: it clamps a frontier left stale by a drained corridor to at least 6 m ahead (so the first chunk of a stage is never parked at the player's feet), sweeps anything already inbound **silently** (no `hazard_cleared`, no `hazards_blasted`, no bonus, no score, no `hazards_dodged`), and restricts placement to hazard-free `breather` chunks until a hazard-bearing one would arrive late enough. `breather`-tagged chunks are now required to carry zero hazards. `ui/stage_banner.tscn` must be off screen within `stage_banner_clear_seconds − stage_banner_reaction_seconds`.
- 2.2 (2026-09-21): §11.3/§11.8 — `ui/post_fx.tscn` sanctioned as an optional HUD mount (CanvasLayer 9, PAUSABLE, idempotent `has_signal`-guarded `bind(game)`): one full-screen post pass for grade, grain, vignette, aberration, letterbox, speed streaks and Nitro lift, with the HUD keeping the pursuit vignette and corner bars unless the frontend hands them over via `post_fx.set_settings()`.
- 2.1 (2026-09-21): §11.4 — `turn_incoming(direction, seconds)` announces the corner `turn_warning_seconds` (3.0) ahead of the bend on the direction `turn_started` then repeats, with `next_turn_direction` on the facade; `boss_intro(kind, name, seconds)` opens the fight immediately before `boss_spawned`. §11.9/§11.10 — the camera swing becomes a ramp–hold–return envelope (`turn_swing_in_fraction` / `turn_swing_out_fraction` 0.3) and is retuned to `turn_camera_yaw_degrees` 55 / `turn_camera_bank_degrees` 12 / `turn_seconds` 2.4; `boss_intro_seconds` 1.2 → 3.0.
- 2.0 (2026-09-19): §11 v2 addendum — run phases (run → turn → boss → stage_clear), `StageManager`, `TurnRig`, boss encounters with telegraphed projectiles and auto-fire tool pickups, faster speed ramp (`time_to_max_speed` 100 s + per-stage bumps), pursuit alert signals, new facade signals/properties/result fields, boss visual hooks, projectile hitbox table, tool table, optional UI mounts (`pursuit_alert`, `boss_hud`, `stage_banner`, `stage_clear`), corridor `set_turn`, leaderboard `SCHEMA_VERSION` 2 with in-place migration of v1 boards.
- 1.0 (2026-09-19): initial contract reconciled from the backend, procgen/tuning and frontend design passes.
- 1.3 (2026-09-19): §4.3 — `result.leaderboard_error:int` added; a failed leaderboard write keeps `rank` 0 / `qualifies` false and emits no `leaderboard_saved`. A board whose `meta/version` is newer than the supported schema is one such failure: it reads as empty and `submit`/`rename` refuse to overwrite it, returning `ERR_FILE_UNRECOGNIZED`.
- 1.2 (2026-09-19): §5.2 — ground-projection quads exempt from the 110 % rule on y; per-hazard draw-call budget stated.
- 1.1 (2026-09-19): engine version policy (4.7.1 pin, 4.7.0 validation); AppRouter rule scoped to in-game overlays; routes wording clarified; leaderboard writes are atomic through a `.tmp` and a temporary `.bak` that is removed once the new board is in place, so a successful write leaves neither behind (a `.bak` survives only a crash mid-write, and `load_entries` falls back to it); Nitro cap arithmetic and viewport-scale restore semantics clarified; return-type rule generalised; mount resources validated as `PackedScene`; timed laser cycle spelled out.


## 11. v2 addendum — stages, turns, boss fights (contract 2.0)

Everything in §1–§10 stays in force unless a rule below replaces it. The user decisions behind v2: **endless
with escalating stages** (never a finite campaign), **automatic cinematic turns** (no turn input, no new way to
lose), **tools auto-fire on pickup** (no fire button). Frontend design detail lives in
`docs/agent-briefs/endless-runner-v2-frontend-design.md`; backend detail in `docs/endless-runner-systems.md` §10.

### 11.1 Run phases

`state` is unchanged (`ready → running → caught → finished`). A new orthogonal read-only property
`phase: StringName ∈ {idle, run, turn, boss, stage_clear}` is owned by `Systems/StageManager` and emitted through
`phase_changed(phase)`. `caught` aborts any phase to `idle`.

| Phase | Enters | Ends | Spawner | `run_clock` |
|---|---|---|---|---|
| `run` | `start_run()` or after `stage_clear` | `stage_distance` reached **and** no blocking hazard ahead of `stage_clear_line_z` (drain; hard timeout `stage_drain_timeout` then remaining hazards are cleared silently, no bonus) | places chunks until `target − stage_drain_distance`, then only moves/despawns | advances |
| `turn` | run drained | `turn_seconds` | idle | frozen |
| `boss` | turn finished | boss HP 0 (`boss_defeated`) or `boss_timeout_seconds` (`boss_retreated`), then `boss_outro_seconds` | idle | frozen |
| `stage_clear` | boss resolved | `stage_clear_seconds` | idle | frozen |

**Stage-entrance guarantee (v2.3).** The `STAGE n` banner covers the lanes, so the corridor is held clear across
it: for `stage_banner_clear_seconds` after **every** `stage_started` (stage 1 included) no blocking hazard may
reach the player, and when that window ends the nearest blocking hazard is still at least
`stage_banner_reaction_seconds × speed` metres away. The StageManager opens the window on `spawner
.begin_clear_road(stage_banner_clear_seconds)` immediately before it switches placement back on, so the first
chunks of the stage are already measured against it. Inside the window the spawner may only place a chunk whose
nearest hazard arrives after the window plus the reaction time; anything else is swapped for a hazard-free
`breather` chunk, and `breather`-tagged chunks therefore carry no hazards at all. The road still fills to
`spawn_horizon_z` — breathers and power-ups keep the pacing — it is never simply left empty. Anything already
inbound when the window opens (a leftover boss projectile included) is cleared **silently**: this is
housekeeping, not Auto-Fix, so no `hazard_cleared`, no `hazards_blasted`, no bonus, no score and no
`hazards_dodged`. The window counts down with the corridor, so a pause holds it.

`elapsed` still counts every unpaused second (result `duration`, timed-laser phase). `run_clock` counts RUN-phase
seconds only and drives speed and difficulty. Stage index starts at 1 and never resets; boss slot
`= (stage_index − 1) % 3`, cycle `c = (stage_index − 1) / 3` (integer division).

### 11.2 Speed and difficulty (replaces §7 Speed row)

`speed_at(run_clock) = lerp(base_speed + b, max_speed + b, smoothstep(0, 1, clamp(run_clock / time_to_max_speed, 0, 1)))`
with the tail `+ tail_speed_per_minute` (RunConfig, default 1.0 m/s) per 60 s of run_clock past `time_to_max_speed`,
capped at `hard_cap_speed + b` (RunConfig, default 26.0; §7's "hard_cap 26" and "+1 m/s per 60 s" name these two fields), where the stage bonus `b = min(stage_speed_step × (stage_index − 1), stage_speed_bonus_max)`.
Defaults: `time_to_max_speed 100` (was 165), `stage_speed_step 1.0`, `stage_speed_bonus_max 6.0`. Nitro still
multiplies by `nitro_speed_multiplier` and caps at `nitro_speed_cap` (raised to 38).
`difficulty = max(clamp(run_clock / time_to_max_speed, 0, 1), min(stage_difficulty_step × (stage_index − 1), 1))`
with `stage_difficulty_step 0.25`; chunk tiers, weights and the §8 hazard table are unchanged.

### 11.3 `runner_game.tscn` delta (extends §3)

```text
World
├─ Floor, Chunks                       unchanged, never rotated
└─ TurnRig (Node3D, systems/turn_rig.gd)
   ├─ GrayboxEnvironment                moved from World/
   ├─ Environment                       moved from World/; mount environment/corridor.tscn
   └─ BossArena (boss/boss_arena.tscn, boss/boss_encounter.gd)
      ├─ Boss (Node3D) └─ Visual        mount boss/visuals/<kind>_visual.tscn
      ├─ Projectiles (Node3D)           hazards/projectile.tscn instances
      ├─ Tools (Node3D)                 powerups/tool_pickup.tscn instances
      └─ (mount boss/boss_fx.tscn)      optional 3D fight effects, PAUSABLE, `bind(game)`
Systems
└─ StageManager (systems/stage_manager.gd), inserted after Spawner, before Autopilot
HUD mounts (optional, PAUSABLE, `bind(game)`): ui/pursuit_alert.tscn, ui/boss_hud.tscn,
                                              ui/stage_banner.tscn, ui/stage_clear.tscn,
                                              ui/post_fx.tscn (CanvasLayer 9, under the panels)
```

Gameplay never rotates: chunks, hazards, projectiles, tools and the player stay in the unrotated frame, so every
z-test (`despawn_z`, `blast_range_z`, dodge line, autopilot) is unchanged. `RunnerGame.track_z(node)` /
`track_aabb(node)` are the rig-local accessors backend code uses (identity when the rig is unrotated).

### 11.4 Facade additions (extends §4)

Signals (additive; §4.1 unchanged):

| Signal | Emitted by | Notes |
|---|---|---|
| `phase_changed(phase: StringName)` | StageManager | on change only |
| `stage_started(index: int, name: StringName, speed: float)` | StageManager | `name` is the stage's boss display name, e.g. `&"Flaky Test Swarm"`; `speed` = base speed for the stage |
| `stage_cleared(index: int, bonus: int)` | StageManager | after `boss_defeated`/`boss_retreated`; bonus already added to score |
| `turn_incoming(direction: int, seconds: float)` | StageManager | once per seam, `turn_warning_seconds` of travel before the bend (or at drain start when the drain is shorter than that); `seconds` = the estimated time to the turn; the direction is the one `turn_started` then repeats |
| `turn_started(direction: int, seconds: float)` / `turn_finished()` | StageManager | `direction` −1 left, +1 right, and always the direction `turn_incoming` announced; the seam is hazard-, pickup- and tool-free |
| `boss_intro(kind: StringName, name: String, seconds: float)` | BossEncounter | at the very start of the intro, immediately **before** `boss_spawned`; `seconds` = `boss_intro_seconds`, the entrance-card window in which no attack and no tool is spawned |
| `boss_spawned(kind: StringName, hp: int)` | BossEncounter | right after `boss_intro`: the moment the boss is visible and armed. Attacks begin `seconds` later, when the intro `boss_intro` announced has run down |
| `boss_health_changed(hp: int, max_hp: int)` | BossEncounter | |
| `boss_phase_changed(phase: int)` | BossEncounter | 1-based; at 100 % / 66 % / 33 % HP |
| `boss_attack_planned(attack: Dictionary)` | BossEncounter | v2.4: immediately **before** every `boss_attack_telegraph`, on the same tick: the full attack that telegraph announces (§11.6 attack dictionary). A branching volley sends one pair per head |
| `boss_attack_telegraph(lane_mask: int, kind: StringName, seconds: float)` | BossEncounter | `lane_mask` bit i = lane index i (§11.7); `kind` = projectile variant. v2.4: `lane_mask` is the *telegraphed* lanes — both candidates for a flaky beat, the whole path for a sweep, the first gap's slabs for a legacy wall, the middle for a scatter; `seconds` is the whole telegraph (candidates + commit for a flaky beat) |
| `boss_attack_committed(lane_mask: int, kind: StringName, seconds: float)` | BossEncounter | v2.4: a flaky telegraph stopped alternating and settled on `lane_mask` (one of its candidates); `seconds` = what is left before it fires, always ≥ `boss_commit_min`. Commits arrive in telegraph order |
| `boss_projectile_fired(projectile: Area3D, lane_mask: int, kind: StringName, speed: float)` | BossEncounter | at the end of the telegraph, once per projectile; `lane_mask` = the lanes that projectile starts in, `kind` = its variant, `speed` = its own closing speed (a signature beat may scale it) |
| `boss_defeated(kind: StringName, bonus: int)` / `boss_retreated(kind: StringName, bonus: int)` | BossEncounter | exactly one of the two per fight |
| `tool_collected(kind: StringName, damage: int)` | BossEncounter | `damage` 0 when the boss's phase resists the tool |
| `pursuit_alert(kind: StringName, seconds_to_catch: float)` | HitManager | `warn` at pursuit start, `critical` when `recovery_remaining ≤ pursuit_critical_seconds`, `clear` on recovery or catch |
| `pursuer_distance_changed(normalized: float)` | Pursuer | 0 retreated … 1 catching; epsilon-gated |

Read-only properties: `phase`, `stage_index: int`, `stage_name: StringName`, `stage_distance: float`,
`stage_distance_target: float`, `run_clock: float`, `next_turn_direction: int` (−1/+1 from the moment the drain
window picks the seam's direction — so already set when `turn_incoming` fires — back to 0 once the bend ends;
0 whenever no turn is pending), `boss: Node3D` (null outside a fight), `boss_kind`, `boss_hp`,
`boss_max_hp`, `boss_phase: int`. Methods: `get_stage_info() -> Dictionary`
(`index, name, phase, distance, target, speed_bonus, difficulty_floor`), `get_boss_info() -> Dictionary`
(`kind, name, hp, max_hp, phase, phase_count, accepted_tools, pending_attacks`; `phase_count` is the fight's own
phase count, 3 today, and 0 in the empty block; each `pending_attacks` row is `{lane_mask, kind, remaining}` plus,
v2.4, `{impact_mask, signature, committed, commit_remaining, attack}`, where `lane_mask` switches from the candidates
to the committed lanes at the commit). `result` gains `stages_cleared`,
`stage_reached`, `bosses_defeated`, `bosses_escaped`, `tools_used`, `boss_damage_dealt`, `turns_taken` (all int).
Projectiles count in `hazards_dodged` (it is a stat, not a score input). `camera_rig.shake(0.35)` fires on every
damaging tool hit (backend-owned, as in §4.2).

### 11.5 Boss visuals — `boss/visuals/<kind>_visual.tscn` extends `boss/boss_visual_base.gd`

Kinds: `flaky_test_swarm`, `merge_conflict_hydra`, `legacy_monolith`. Base vars set before `on_spawned()`:
`kind`, `boss_name: String`, `max_hp: int`, `phase_count: int`, `hover_z: float`, `sway_amplitude: float`,
`sway_period: float`. The visual sways itself in `_process` (PAUSABLE); the backend never moves it per tick.

| Hook | When |
|---|---|
| `on_spawned()` | once, after the vars are set; idempotent |
| `set_phase(phase: int)` | on `boss_phase_changed` |
| `set_health(hp: int, max_hp: int)` | on `boss_health_changed` |
| `play_telegraph(lane_mask: int, kind: StringName, seconds: float)` | on `boss_attack_telegraph` |
| `play_commit(lane_mask: int, kind: StringName, seconds: float)` | v2.4, optional (`has_method`-guarded): on `boss_attack_committed` |
| `play_attack(kind: StringName)` | at fire |
| `play_hit(tool_kind: StringName, damage: int)` | damaging tool |
| `play_resist(tool_kind: StringName)` | resisted tool (damage 0) |
| `play_defeat()` / `play_retreat()` | fight end; the backend frees the boss after `boss_outro_seconds` |

Envelope: a bounding box ≤ 7 m wide × 3 m deep with its vertical extent inside y ∈ [1.6, 6.1] (bottom edge never
below y 1.6; 4.5 m of headroom), core nominally centred around y 2.6 at `hover_z`; ≤ 40 draw calls at peak.
**Entrance exception (v2.1):** during the `boss_intro` window the visual may travel in from the far end, but at every
frame its bounds must still satisfy x ∈ [−3.5, 3.5] and y ∈ [1.6, 6.1]; only z may extend beyond the box, and only
toward the far end (never closer to the player than `hover_z + 3`). Nothing rises from under the floor. The boss has no hitbox. Graybox fallback: a tinted box with a Label3D name plate (backend).

### 11.6 Projectiles (extends §8) — `hazards/visuals/projectile_visual.tscn` extends `hazards/hazard_visual_base.gd`

`kind = &"projectile"`, `variant` selects the shape; the base also receives `closing_speed: float` before
`on_spawned()`. Projectiles are hit-once hazards in group `runner_hazards` (Auto-Fix clears them), spawned at the
boss and moving +Z at `closing_speed` relative to the player.

| variant | W × H × D (m) | y range | lanes | dodge_hint |
|---|---|---|---|---|
| `orb` | 1.6 × 0.9 × 1.2 | 0–0.9 | 1 | JUMP_OR_LANE |
| `low` | 5.6 × 0.9 × 1.2 | 0–0.9 | all | JUMP |
| `high` | 5.6 × 0.4 × 1.2 | 1.1–1.5 | all | ROLL |
| `wide` | 3.6 × 1.0 × 1.2 | 0–1.0 | 2 adjacent | LANE |

Visuals ≤ 110 % of the hitbox (ground-projection quads exempt on y as in §5.2). Reaction budget guaranteed by
`tests/runner_boss_validator.gd`: telegraph + travel ≥ 0.98 s at maximum escalation, jump reaction ≥ 0.35 s.

**Signature variants (v2.4).** Same rules as the four above; `look` is the base variant a visual that has not opted in
is handed as `variant` (so nothing is ever invisible), `boss` the boss that fires it:

| variant | W × H × D (m) | y range | lanes | dodge_hint | look | boss / signature |
|---|---|---|---|---|---|---|
| `scatter` | 1.6 × 0.7 × 1.2 | 0–0.7 | 1 | JUMP_OR_LANE | `orb` | Swarm `scatter` (half speed) |
| `sweep` | 1.6 × 0.6 × 1.2 | 0–0.6 | 1 (moving) | JUMP_OR_LANE | `orb` | Hydra `sweep` (0.55× speed) |
| `force_push` | 3.6 × 1.0 × 1.2 | 0–1.0 | 2 adjacent | LANE | `wide` | Hydra `force_push` (1.3× speed, 1.6× telegraph) |
| `slab` | 1.8 × 2.4 × 1.2 | 0–2.4 | 1 | LANE | `wide` | Monolith `legacy_wall` (0.4× speed) |
| `quake` | 5.6 × 0.5 × 1.2 | 0–0.5 | all | JUMP | `low` | Monolith `quake` |
| `debris` | 1.6 × 0.8 × 1.2 | 0–0.8 landed | 1 | JUMP_OR_LANE | `wide` | Monolith `debris` (0.55× speed) |

`flaky` and `branching` fire plain `orb`s. A signature beat's speed is the fight's projectile speed × its `speed_scale`,
capped at `boss_signature_speed_max`; its telegraph is the phase telegraph × `telegraph_scale`, floored at
`boss_telegraph_min`.

**Motion (v2.4).** `boss/boss_attacks.gd` is the single source (pure, static). A *shot* is one projectile's motion,
a function of `t` = seconds since that projectile was fired: `z(t) = from_z + speed·t` (every shot still flies +Z at a
constant speed; `from_z = boss_z`), `x(t)` piecewise linear through `x_keys` `[(t, x), …]`, and a y lift that only a
falling `debris` slab has (`drop_height·(1 − (t/land_at)²)` until `land_at`, 0 after). The projectile node exposes
`boss_kind: StringName`, `signature: StringName`, `motion: Dictionary` (the shot; empty for a straight shot, which
moves exactly as in 2.3), `age: float` (= t), and `lane_mask_at(t) -> int` (lanes its hitbox touches at t, by the
`occupies_lane` rule), `y_range_at(t) -> Vector2` (world y min/max at t) and `impact_lane_mask() -> int` (the lanes
it covers while its z range overlaps the player's, which is what a dodge and the §11.7 tool-lane rule answer). The
root follows the motion (x and y), so `get_world_aabb()` and the physics hitbox are always where the motion says.

**Attack dictionary** (`boss_attack_planned`, `pending_attacks[].attack`): `signature`, `variant`, `boss_kind`,
`telegraph_mask`, `mask` (the lanes at fire, the committed lanes for a flaky beat), `impact_mask`, `telegraph`,
`speed`, `from_z`, `shots` (Array of shot dictionaries: `variant, speed, from_z, lanes, x_keys, drop_height,
land_at, twin`), `enter` / `exit` (seconds after the telegraph during which it passes the player), `jumpable`,
`rollable`, `clear_height`, and per signature: flaky `commit_at` (seconds after the telegraph), `candidates`
(the two masks), `swap_seconds`; scatter `split_at` (seconds after fire), `split_mask`; branching `head`, `heads`,
`delay`; sweep `sweep_from`, `sweep_to` (lane indices), `sweep_end` (seconds after fire); legacy wall `gap_from`,
`gap_to`, `shift_at`; debris `drop_height`, `land_at`. A scatter's second half carries `twin: true` in its shot (it
flies inside the first until the split, so a visual may hide it until then). A visual that wants the real variant
declares `var signature_variants := true`; any visual declaring `projectile_variant`, `boss_kind`, `signature` or
`motion` receives them before `on_spawned()`.

### 11.7 Tools — `powerups/visuals/<kind>_visual.tscn` extends `powerups/power_up_visual_base.gd`

Tools are pickups (`powerups/tool_pickup.tscn`, extends `power_up.gd`, group `runner_tools`, layer Pickup) that
**auto-fire on pickup**: collecting one deals its damage to the boss immediately (or 0 if resisted) and adds
`tool_bonus` score. Lane indexing everywhere: index 0/1/2 ↔ x −2/0/+2; `lane_mask` bit i = lane index i.

| kind | display | damage | weight | spawn y |
|---|---|---|---|---|
| `review_comment` | Review Comment | 10 | 35 | 1.0 |
| `lint_rule` | Lint | 12 | 25 | 1.0 |
| `unit_test` | Unit Test | 15 | 25 | 1.0 |
| `auto_fix_patch` | Auto-Fix | 20 | 15 | 2.2 (jump height) |

Boss phases that resist all but specific tools: Hydra phase 2 accepts only `unit_test`, `lint_rule`; Monolith
phase 2 accepts only `auto_fix_patch`, `review_comment`; Monolith phase 3 accepts only `unit_test`. Everything
else accepts all four. Tools spawn only during `boss`, from `boss_tool_spawn_z`, in a lane with no live projectile
within `boss_tool_lane_clearance`, never the same lane twice in a row; a fight never goes more than
`boss_tool_guarantee_seconds` without a tool in flight. Existing power-ups keep working in fights (Auto-Fix clears
projectiles; Nitro/LGTM invulnerability applies; Shield blocks a projectile).

### 11.8 UI mounts (extends §5.6) — all optional, `bind(game: Node)`, PAUSABLE, no backend graybox

The one non-UI mount in this table is `boss/boss_fx.tscn`: it mounts under `World/TurnRig/BossArena` (§11.3) rather
than under `HUD`, and it is the sanctioned home for 3D fight effects, so no panel has to reach into `World`.

| Scene | Purpose | Reads |
|---|---|---|
| `ui/pursuit_alert.tscn` | Star Fox-style incoming-transmission panel with radar/pulse; states the catch rule | `pursuit_started`, `pursuit_progress`, `pursuit_alert`, `pursuit_recovered`, `damage_blocked`, `caught` |
| `ui/boss_hud.tscn` | boss name plate, HP bar, phase pips | `boss_*` signals, `get_boss_info()` |
| `ui/stage_banner.tscn` | `STAGE n / <boss name>` banner; deferred until `turn_finished`. It covers the lanes, so it must be **fully off screen** within `stage_banner_clear_seconds − stage_banner_reaction_seconds` (2.5 s at the defaults) of the `stage_started` that raised it — the backend only holds the corridor clear for `stage_banner_clear_seconds` (§11.1), and the reaction time is the player's, not the banner's | `stage_started`, `turn_*` |
| `ui/stage_clear.tscn` | stage-clear card (time, tools used, bonus) | `stage_cleared`, `boss_defeated`/`boss_retreated`, `get_stage_info()` |
| `ui/post_fx.tscn` | one full-screen post-processing pass: colour grade, film grain, vignette, chromatic aberration on damage and tool hits, letterbox for `boss_intro` and the stage-clear card, speed streaks, Nitro lift | `run_started`, `damage_taken`, `boss_intro`, the stage-clear signals, `power_up_collected`/`power_up_expired`, `pursuit_started`/`pursuit_progress`/`pursuit_recovered`, `speed_changed`, `paused_changed`, and the tool/boss hit signals when they exist |
| `boss/boss_fx.tscn` | 3D fight effects: telegraphs, tracers, damage numbers; never touches gameplay nodes | `boss_*` signals, `tool_collected`, `get_boss_info()` |

`ui/post_fx.tscn` is a `CanvasLayer` at **layer 9** — below `runner_hud.tscn` (10) and every other panel, so the
grade and the grain never wash out a gameplay-critical label — `PROCESS_MODE_PAUSABLE` like the rest, and its
`bind(game)` must be **idempotent** (a second `bind` rebinds nothing and doubles no effect) and connect **only**
signals it has confirmed with `game.has_signal(...)`, because the mount is sanctioned ahead of the signals some of
its effects want. It reads state and never calls a mutating facade method.

**Effect ownership.** The HUD keeps ownership of the pursuit vignette and the corner bars (§11.8 `pursuit_alert`
/ the F7 legibility pass): `post_fx` must not draw a second pursuit vignette or a second set of corner bars unless
the frontend explicitly hands them over through `post_fx.set_settings()` (the frontend-owned settings entry point;
the backend never calls it). Absent that hand-over, `post_fx`'s pursuit response is limited to the grade and the
aberration, so the two layers can never stack the same effect.

The `HUD` mount point may carry additional frontend-owned children beyond the scenes in this table; the backend
asserts only that its own contract mounts are present exactly once, never how many children the layer holds.

`ui/runner_hud.tscn`, `ui/pause_menu.tscn`, `ui/game_over.tscn` keep their v1 contract; the frontend may restyle
them for legibility (font ≥ 18 units, outline ≥ 6, panel-backed; see the v2 frontend design §1). The F3
`DebugOverlay` (backend) prints phase, stage, boss HP/phase and pending attacks so graybox play stays readable.

### 11.9 Corridor (extends §5.5)

Optional methods, all `has_method`-guarded by the backend: `set_turn(progress: float, direction: int)` (called every
physics tick during `turn`, `progress` 0→1; the frontend owns the visual bend and must make p = 1 visually identical
to p = 0), `set_phase(phase: StringName)`, `set_boss_arena(active: bool)`. When the mounted corridor lacks `set_turn`,
the backend `TurnRig` rotates **itself** by `turn_yaw_degrees × smoothstep(progress)` (fallback only), so whatever
environment is mounted under it turns with it — the frontend corridor when present, otherwise the graybox
environment. Mounting a corridor still frees `GrayboxEnvironment` (§3); nothing is retained for the fallback. The camera swing
(`turn_camera_yaw_degrees` 55, `turn_camera_bank_degrees` 12, returning to zero at p = 1) is backend-owned in
`camera_rig.gd` and always applies. Its envelope is **ramp–hold–return**, not a wave: the yaw and the bank
smoothstep up to the peak over the first `turn_swing_in_fraction` (0.3) of the bend, **hold** there through the
middle, and smoothstep back to zero over the last `turn_swing_out_fraction` (0.3). The profile is exactly 0 at
p = 0 and p = 1 for any fractions, so the camera is never left displaced. Gameplay is unaffected: the treadmill
frame stays unrotated, and the frontend corridor is expected to match the 55° with its own yaw so the bend and
the camera agree.

### 11.10 RunConfig additions (single tuning source: the `@export` defaults in `run_config.gd`; `run_config.tres` stays an empty resource that may override them and is never mutated at runtime — this supersedes the §7 heading's wording)

```text
Speed:     time_to_max_speed 100.0 (was 165), tail_speed_per_minute 1.0, hard_cap_speed 26.0 (unchanged v1 fields, named here
           because §11.2 and runner_boss_validator.gd use them), stage_speed_step 1.0, stage_speed_bonus_max 6.0, nitro_speed_cap 38.0
Stages:    stage_base_distance 900.0, stage_distance_step 250.0, stage_distance_max 2000.0, stage_difficulty_step 0.25
           stage_drain_distance 120.0, stage_drain_timeout 6.0, stage_clear_line_z 8.0, stage_clear_seconds 3.0
           stage_clear_bonus_base 400, stage_clear_bonus_per_stage 150
           stage_banner_clear_seconds 3.5   seconds after every stage_started in which no blocking hazard may reach
                                            the player, because the stage banner is covering the lanes (§11.1)
           stage_banner_reaction_seconds 1.0 seconds of travel the nearest blocking hazard is still away the moment
                                            that window ends; must stay below stage_banner_clear_seconds
Turn:      turn_seconds 2.4, turn_warning_seconds 3.0, turn_yaw_degrees 90.0 (graybox fallback)
           turn_camera_yaw_degrees 55.0, turn_camera_bank_degrees 12.0, turn_swing_in_fraction 0.3, turn_swing_out_fraction 0.3
Boss:      boss_z -14.0, boss_sway_amplitude 2.4, boss_sway_period 3.2, boss_intro_seconds 3.0, boss_outro_seconds 1.0
           boss_timeout_seconds 55.0, boss_phase_thresholds [1.0, 0.66, 0.33]
           boss_hp_growth 1.35, boss_hp_scale 1.0 (test/tuning multiplier on the base HP), boss_projectile_speed_growth 1.08, boss_projectile_speed_max 34.0
           boss_telegraph_growth 0.88, boss_telegraph_min 0.60, boss_attack_interval_growth 0.90, boss_attack_interval_min 0.55
           boss_kill_bonus_base 600, boss_kill_bonus_per_stage 200, boss_retreat_bonus_ratio 0.35
Tools:     boss_tool_spawn_z -55.0, boss_tool_interval_growth 0.93, boss_tool_interval_min 1.4
           boss_tool_guarantee_seconds 4.0, boss_tool_lane_clearance 3.0, boss_shield_tool_bias 0.7, tool_bonus 20
Pursuit:   pursuit_critical_seconds 5.0, pursuer_distance_epsilon 0.01
Autopilot: autopilot_telegraph_lead 0.12, autopilot_tool_greed 1.0
Signature (v2.4): boss_flaky_candidate_seconds 0.45, boss_flaky_swap_seconds 0.15 (cosmetic cadence),
           boss_commit_min 0.60 (a flaky commit is at least this long before fire), boss_scatter_split_distance 10.0 (m),
           boss_signature_speed_max 44.0, boss_signature_reaction_min 0.35 (the B6 floor)
```

Boss base table (slot → kind, HP, projectile speed, telegraph P1/P2/P3, attack interval P1/P2/P3, tool interval):
0 `flaky_test_swarm` 100 / 26 / 0.90-0.80-0.72 / 1.6-1.4-1.2 / 2.6; 1 `merge_conflict_hydra` 140 / 28 /
0.85-0.78-0.70 / 1.5-1.3-1.1 / 2.3; 2 `legacy_monolith` 180 / 30 / 0.80-0.72-0.65 / 1.4-1.2-1.0 / 2.0.
Escalation per cycle c: HP × 1.35^c, projectile speed × 1.08^c (≤ 34), telegraph × 0.88^c (≥ 0.60), attack
interval × 0.90^c (≥ 0.55), tool interval × 0.93^c (≥ 1.4). Attack patterns per phase are in the systems spec §10.

### 11.11 Leaderboard

`SCHEMA_VERSION` becomes 2. Entry fields are unchanged, so a version-1 board is **migrated in place**: its
entries are read normally and the next successful save rewrites the file as version 2 (players keep their v1
scores even though v2 scores also include stage and boss bonuses). The newer-schema refusal still applies to any
version > 2.

### 11.12 Verification (extends §9)

New: `tests/runner_boss_validator.gd` (every boss × phase × pattern × entry lane × cycle 0–4 is dodgeable by the
real autopilot planner from the telegraph; tools reachable within `boss_tool_guarantee_seconds`). v2.4: every beat is
resolved through `boss_attacks.gd` into every option it can draw, the bot hears `boss_attack_planned` /
`boss_attack_telegraph` / `boss_attack_committed` in the encounter's order, collisions use the motion API, B1/B3 are
measured from the commit for a flaky beat, and **B6** proves that every commit, split, sweep, gap shift, debris shadow
and landing, and every branching volley, leaves from each lane a survivable answer (final lane plus at most one jump
or roll against the impact geometry) whose latest start is ≥ `boss_signature_reaction_min` after the event.
`runner_smoke.gd`
proves stage 1 → turn → boss 1 → stage clear → stage 2 with zero projectile hits under a shortened config, and a
catch mid-fight ending the run once. `runner_visual_smoke.gd` gains `HUD LEGIBILITY`, `PURSUIT ALERT`,
`BOSS VISUALS`, `TOOLS AND PROJECTILES`, `TURN` sections and a 30-recipe audio census (voices ≤ 10); the full loop
must cross a stage seam, a turn, a boss and a stage-clear card.
