# Agent brief — Endless Runner frontend (Codex)

<task>
Implement the complete frontend (visuals, UI, audio) of the Endless Runner microgame in Hoppy's
Adventure Arcade, a Godot **4.7.1**-pinned GDScript project at `hoppys-adventure-arcade/` inside this repository
(the build machine currently has 4.7.0 stable; results on 4.7.0 are diagnostic and final acceptance re-runs on
4.7.1 per the contract's engine version policy).
The backend (player controller, hazards, spawner, pursuit, score, leaderboard) is built by another agent
against a shared contract. Your work must plug into that contract exactly and must look and sound like
the CodeRabbit story it tells: Hoppy sprints through a live codebase while the Unreviewed PR Backlog chases.
Done means: every file listed in §4 exists at its exact path, implements its contract methods, passes
`tests/runner_visual_smoke.gd`, the full loop (hub → runner menu → run → caught → game over → save → retry
→ menu → hub) works with the backend, and `docs/endless-runner.md` documents it.
</task>

<default_follow_through_policy>
Default to the most reasonable low-risk interpretation and keep going. The contract
(`docs/endless-runner-contract.md`) resolves naming and API questions; the art direction below
resolves visual questions. Only stop when a missing detail would change correctness or require editing
a backend-owned file.
</default_follow_through_policy>

<completeness_contract>
Work milestone by milestone (F0 → F6). Do not stop after the first scene works. Each milestone has a
definition of done; verify it before moving on. Finish all six.
</completeness_contract>

<verification_loop>
After each milestone run the headless load check and the milestone's dev scene. Before finalizing, run
`tests/runner_visual_smoke.gd` and `tests/menu_smoke.gd` and include their output verbatim in your report.
Never report a check as passed without its output.
</verification_loop>

<action_safety>
Edit only frontend-owned paths (§1). Never edit `project.godot`, `app/*`, any backend `.gd`, hazard /
power-up / chunk / player ROOT scenes, or `tests/*` other than `tests/runner_visual_smoke.gd`. If you need a
backend change, write it under "Requests to backend" in `docs/endless-runner.md` and continue with a
`has_method`-guarded fallback. No external downloads: every visual is built from primitives, Label3D,
particles and small shaders; every audio asset is synthesised in code or is the CC0 track already in the
repo. Record any asset you use in `Assets/runner/LICENSES.md`.
</action_safety>

<structured_output_contract>
Final report: 1) milestones completed with the verification output for each, 2) touched files,
3) requests to backend (if any), 4) known gaps.
</structured_output_contract>

---

## 1. Read first, then ground rules

Read in this order: `docs/endless-runner-contract.md` (authoritative API, paths, hitbox sizes,
tuning), `docs/endless-runner.md` if it exists, `hoppys-adventure-arcade/scenes/main_menu/menu_style.gd`,
`main_menu.gd`, `mode_portal.gd`, `hoppy.gd`, `preview.gd` (lines 53–66 draw the existing "Codebase
Corridor" preview — reuse that look), `app/audio_service.gd`, `app/app_router.gd`, `tests/menu_smoke.gd`,
`docs/main-menu.md`.

- Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot`. Project root: `hoppys-adventure-arcade/`.
- Renderer is **gl_compatibility** (hard constraint). Supported and used: emissive `StandardMaterial3D`,
  `WorldEnvironment` glow (Compatibility ignores `glow_levels`, `glow_normalized`, `glow_strength`,
  `glow_blend_mode`; use `glow_enabled`, `glow_intensity`, `glow_bloom`, `glow_hdr_threshold` ≈ 0.75,
  `glow_hdr_scale`), depth fog, `GPUParticles3D` (no trails, no collision, no sub-emitters), `Label3D`,
  spatial and canvas `.gdshader`, `Viewport.scaling_3d_scale`. Not supported: SDFGI, volumetric fog,
  SSR, SSAO, decals, DOF. Max 8 lights per mesh; use at most 3 lights in the whole scene; no shadows.
- Code style: `snake_case` files, **no `class_name`**, `const Style = preload("res://scenes/main_menu/menu_style.gd")`,
  typed GDScript with `:=`, tabs, an explicit return type on every function (`-> void` for procedures), UI built imperatively in `_ready()` with `Style.theme()`,
  `Style.label()`, `Style.button()`. Scenes stay tiny (root + script + a few instanced children). Commit
  `.gd.uid` files (run `--import` once after adding scripts).
- Ownership (yours): `scenes/runner/runner_menu.{tscn,gd}`, `scenes/runner/environment/**`,
  `scenes/runner/ui/**`, `scenes/runner/audio/**`, `scenes/runner/shaders/**`,
  `scenes/runner/player/hoppy_runner_visual.{tscn,gd}` + `scenes/runner/player/dev/**`,
  `scenes/runner/hazards/visuals/**`, `scenes/runner/powerups/visuals/**`,
  `scenes/runner/pursuer/pursuer_visual.{tscn,gd}`, `Assets/runner/**`, `tests/runner_visual_smoke.gd`,
  `docs/endless-runner.md`, `docs/previews/endless-runner-*.png`. The backend left graybox placeholders
  at `runner_menu.tscn`, `ui/runner_hud.tscn`, `ui/pause_menu.tscn`, `ui/game_over.tscn`; overwrite them.
- Branch: `codex/endless-runner-frontend`, PR into `endless-runner`.

## 2. Art direction

Palette (`scenes/runner/environment/runner_palette.gd`, `extends RefCounted`, constants):
`NAVY_BG 08111c` (background/fog), `NAVY 101d2d`, `NAVY_2 142735`, `SLATE 435464`, `CREAM fff0d3`
(text, Hoppy fur), `MINT 79e0c4` (UI accent, power-ups), `MATRIX 63f9b2` (corridor grid, code rain —
matches `preview.gd` COLORS[3]), `ORANGE f78949` (Hoppy hoodie, CodeRabbit accent), `DANGER ff4d3d`
(hazards, lasers, pursuer), `ROSE ff7185` (pursuit HUD), `LILAC a99bff` (merge "theirs" side),
`EAR_PINK ecaca0`, `EYE 202b40`.

Readability rules: hazards are **hot** (`DANGER` glow, `ORANGE` accents, cream monospace text);
power-ups are **cool** (`MINT`/`MATRIX` glow, floating, slow spin); the pursuer is red only; the
environment stays desaturated navy with dim `MATRIX` so gameplay objects pop. Every hazard has a flat
floor-marker quad (`DANGER` α 0.35) exactly the size of its hitbox footprint. Visual bounds ≤ 110 % of the
contract hitbox on every axis. Code motifs via `Label3D` (monospace `SystemFont` recipe from
`menu_style.gd` lines 6–8: Menlo / Consolas / DejaVu Sans Mono, weight 700): `PR #4821`, `MERGE CONFLICT`,
`<<<<<<< HEAD`, `@deprecated`, `// TODO`, `LGTM`, `nit: rename this`. Outline 8 px `NAVY_BG` on every label.
`texture_filter = NEAREST` everywhere. Materials built once in `scenes/runner/environment/runner_materials.gd`
(`static func glow(color, energy := 1.2)`, `additive(color, alpha)`, `lit(color)`, `label(parent, text, size, color)`,
`font()`), cached in `static var` dictionaries.

Retro look: `corridor.gd` applies `get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR` and
`scaling_3d_scale = 0.5` (export) with **shared per-viewport ownership**: a static registry keyed by viewport
records the original mode and scale when the first corridor enters, each corridor pushes its own settings as
the current owner, and the original values are restored only when the last owner exits (any exit order; an
external change to the viewport settings is left alone). Two corridors can coexist briefly (menu backdrop and
game). Verify in F0 that Compatibility honours the scale.

Zero-download toolkit: `BoxMesh`, `CapsuleMesh`, `CylinderMesh`, `SphereMesh`, `TorusMesh`, `PlaneMesh`,
`QuadMesh`, `PrismMesh`, `TextMesh`; `Label3D`; `GradientTexture1D/2D`; a code-drawn 5×7 glyph atlas
(`scenes/runner/shaders/glyph_atlas.gd`: 64 glyphs in 8×8 cells of a 64×64 `Image`, white on transparent,
cached `ImageTexture`) used by the rain particles (`BILLBOARD_PARTICLES`, `particles_anim_h_frames 8`,
`v_frames 8`, `anim_offset 0–1`, `anim_speed 1–4`) and the wall shader. Shaders (≤ 40 lines each) in
`scenes/runner/shaders/`: `floor_grid.gdshader` (world-space scrolling neon grid with lane edge lines at
x = ±1, ±3; uniforms `scroll`, `cell`, `intensity`, `beat`, `fade_start/end`), `code_wall.gdshader` (tiled
glyph atlas, per-column falling speed, scanlines, depth fade), `hologram.gdshader` (additive scanlines +
rim), `far_glow.gdshader` (additive radial gradient), `vignette.gdshader` (canvas_item radial red vignette
+ scanlines; uniforms `strength`, `color`, `pulse`, `scanlines`). Never use `TIME` for anything that must
freeze on pause; drive uniforms from GDScript.

## 3. Contract essentials (full detail in `docs/endless-runner-contract.md`)

The backend root `RunnerGame` mounts your scenes at runtime if they exist and calls `bind(game)` on
UI/audio scenes before `run_started`. Signals you consume (exact names):
`run_started(seed)`, `state_changed(state)` (ready/running/caught/finished), `health_changed(hp, max_hp)`,
`damage_taken(kind, hp)`, `damage_blocked(kind, reason)`, `shield_changed(active)`,
`pursuit_started(recovery_seconds)`, `pursuit_progress(remaining, total)`, `pursuit_recovered(reason)`,
`caught()`, `run_finished(result)`, `leaderboard_saved(entries, rank)`, `score_changed(score, multiplier)`,
`bonus_awarded(points, reason)`, `speed_changed(speed, normalized)`, `difficulty_changed(d)`,
`power_up_collected(kind, duration)`, `power_up_expired(kind)`, `hazard_cleared(hazard)`,
`hazards_blasted(count)`, `player_action(action)`, `paused_changed(paused)`.
Properties: `config`, `state`, `paused`, `elapsed`, `distance`, `speed`, `normalized_speed`, `difficulty`,
`hp`, `score`, `multiplier`, `player`, `camera_rig` (`shake(strength)`, `punch_fov(deg, s)`), `cosmetic_rng`.
Methods: `pause()`, `resume()`, `retry()`, `go_to_menu()`, `hit_stop(s)`, `submit_name(name) -> bool`,
`get_leaderboard()`, `get_result()`, `get_active_effects()`. Static leaderboard reader for the menu:
`preload("res://scenes/runner/systems/runner_leaderboard.gd").load_entries()`.
Audio: `AudioService.play_music(stream, volume_db)`, `play_default_music()`, `set_music_pitch(scale)`,
`duck_music(db, seconds)`, `play_ui(kind)`; SFX players on bus `"SFX"`.
Camera: position (0, 4, 8), look at (0, 1, −8), FOV 60. Lanes x = −2, 0, +2. Hoppy faces −Z, feet y = 0,
1.8 m tall, roll pose ≤ 0.9 m. Pursuer root at y = 0, z from +12 (retreated) to +4.5 (threat 1); keep it
≤ 6 m wide, ≤ 2.6 m tall.

## 4. Deliverables and specs

### 4.1 `scenes/runner/player/hoppy_runner_visual.tscn` + `.gd` — `extends "res://scenes/runner/player/runner_visual_base.gd"`

Primitive rabbit (≈ 22 meshes, 5 shared materials) under a `Root` pivot at the feet:
`Body` CapsuleMesh r 0.28 h 0.80 at y 0.78 (`ORANGE` lit hoodie) with a `Logo` quad; `Head` at y 1.28
(`Skull` sphere r 0.27 `CREAM`, `Muzzle`, `Nose` `EAR_PINK`, `EyeL/R` `EYE`, `Goggles` two TorusMesh
`ORANGE` glow pushed up on the forehead, `EarL/R` pivots with CapsuleMesh r 0.07 h 0.58 + pink inner),
`ArmL/R` and `LegL/R` pivots with capsules and feet boxes, `Tail` sphere. Extra: `Aura` sphere r 0.95
(hologram shader, hidden), `ShieldRing` torus at the feet (hidden), `HitSparks` one-shot particles,
`AuraSparkles`, `AnimationPlayer`. Build all animations in code (`Animation.TYPE_VALUE` tracks for properties, linear, step 1/30,
`playback_default_blend_time 0.08`; the `hurt` clip's `flash()` calls use an `Animation.TYPE_METHOD` track): `idle` 1.6 s loop (breathe, ear twitch), `run` 0.5 s loop
(two bobs, leg/arm swing, ears flap back, head lean), `jump` 0.35 s hold (stretch then settle, limbs tuck),
`fall` 0.6 s loop (flail, ears up), `roll` 0.5 s (forward somersault about X on `Root`, `Root.scale.y`
0.55 so it fits 0.9 m; key rotation back to 0 at the end), `hurt` 0.45 s (knock-back lean, ear splay,
`flash()` method track at 0 / 0.12 / 0.24 s), `dead` 0.9 s hold (tip onto back, limbs limp).
Contract methods: `set_anim_state` (play on change; `run` speed_scale from `set_run_speed`:
`lerp(0.85, 1.9, normalized)`; `hurt` auto-returns to `run`/`idle` via `animation_finished`),
`set_run_speed`, `set_lane_lean` (lean/look applied to the scene root, not `Root`, so it never fights
animation), `show_aura(kind, on)` (colour per kind: `lgtm` MINT strong, `nitro` ORANGE, `code_review` MATRIX faint),
`show_shield(on)`, `on_hit()` (white material flash 0.06 s + `HitSparks.restart()`).
Dev scene `player/dev/hoppy_preview.tscn` cycles states with keys.

### 4.2 Hazard visuals — `scenes/runner/hazards/visuals/<kind>_visual.tscn`, `extends "res://scenes/runner/hazards/hazard_visual_base.gd"`

Base vars are set before `on_spawned()`: `kind`, `variant`, `hitbox_size`, `hitbox_offset`, `lanes_mask`,
`dodge_hint`. Size everything from `hitbox_size`. Hooks: `on_spawned()` (reset; may be reused),
`on_hit_player()`, `on_cleared()` (Auto-Fix "fixed" reaction in `MINT`), `set_telegraph(t)` and
`set_laser_state(state)` (timed laser only). Idle motion in `_process` from an accumulated `_t` so it
freezes on pause. No lights.

| kind | Composition | Idle | Hit / cleared | Text |
|---|---|---|---|---|
| `pr_backlog_low` (5.6×1.0×1.2) | three rows of stacked `NAVY` PR cards spanning the corridor, `ORANGE`/`DANGER` glow edge strips | cards wobble | cards fly apart and fade / cards shrink to 0 with `MINT` flash, tag `AUTO-FIXED` | `PR #4821 +1,204 −38`, `needs review`, `47 files` |
| `pr_backlog_high` (5.6×1.8×1.2, y 1.1–2.9) | rail at y 3.0 with hanging cards; the standard `DANGER` α 0.35 floor marker covers the hitbox footprint, **plus** (approved exception to the marker rule) a second `MATRIX` α 0.25 quad drawn just above it that reads as the safe roll gap | cards sway | cards drop and bounce / as above | `STALE · 47 DAYS`, `CI FAILING` |
| `bug_swarm` (1.6×0.9×1.2) | `DANGER` core sphere with six legs + 36-particle glyph swarm (`#`, `*`) | jitter | burst / particles turn `MINT`, core pops | `throw new Error()` |
| `merge_conflict` (3.6×1.0×1.2) | two slabs `<<<<<<< HEAD` (`MATRIX` strip) and `>>>>>>> feature/x` (`LILAC` strip) with a zigzag `DANGER` seam and `=======` | slabs slide in antiphase, seam pulses | seam flashes, slabs shake / slabs merge into one `MINT` box `MERGED` | as listed + `MERGE CONFLICT` tag |
| `deprecated_pit` (5.6 or 3.6 × 0.4 × 3.0) | near-black quad at y 0.015 as the hole, `ORANGE`/`NAVY` striped rim boxes, glyph particles falling in, flat `@deprecated` label | label flicker | rim flash / rim `MINT`, label `REMOVED` | `@deprecated`, `since v0.9` |
| `laser_grid` (5.6 × 0.3–0.4 × 1.2 at ground / mid / high; `timed` alternates ground ⇄ high) | two posts with `DANGER` cap spheres, three additive beams at the hitbox y-range; a `MINT` scanner slab for telegraphs | beam flicker | white flash + sparks / beams retract, caps `MINT`, tag `SCAN PASSED` | `SECURITY SCAN` |
| `comment_flood` (3.6×4.0×1.2) | column of `ORANGE` speech-bubble cards scrolling downward, wrapped in a `DANGER` hologram slab so it reads as filling the lane | cards scroll and wrap | burst / cards fold, tag `RESOLVED` | `nit: rename this`, `// TODO`, `pls fix`, `blocking` |
| `build_shockwave` (5.6×0.5×1.2) | flat torus ring across the corridor + `DANGER` core sphere + shards | ring pulses | white flash, shards burst / ring `MINT`, tag `BUILD FIXED` | `BUILD FAILED  x` |

Dev scene `hazards/visuals/dev/hazard_gallery.tscn`: instances all hazards and power-ups over the
corridor with wireframe boxes of the contract hitboxes; keys trigger hooks.

### 4.3 Power-up visuals — `scenes/runner/powerups/visuals/<kind>_visual.tscn`, `extends "res://scenes/runner/powerups/power_up_visual_base.gd"`

All: `Pivot` at the root spinning 1.6 rad/s, bob ± 0.08 m, `MINT` additive `Ring` torus, `Halo` sparkles,
`MINT` billboard tag at +0.75 m. `on_collected()`: pop scale 1 → 1.45 → 0 in 0.25 s, ring expands and fades,
halo burst. Icons: `approve_shield` hex shield + cream check (`APPROVED`); `auto_fix` wrench + bolt
(`AUTO-FIX`); `lgtm` TextMesh `LGTM` (`5s`); `nitro` capsule commit with `MINT` flame stream (`NITRO COMMIT`);
`super_jump` coin with `^^` (`SUPER JUMP`); `code_review` magnifier (`CODE REVIEW ×1.5`).

### 4.4 `scenes/runner/pursuer/pursuer_visual.tscn` + `.gd` — `extends "res://scenes/runner/pursuer/pursuer_visual_base.gd"`

"The Unreviewed PR Backlog": `Wall` of 5 × 4 PR cards (`MultiMeshInstance3D`, per-instance colour
`NAVY` → `DANGER` by threat²) with `Label3D`s `PR #3312 UNREVIEWED`, `CHANGES REQUESTED`, `STALE`,
`NEEDS REBASE`, `DO NOT MERGE`, `0 approvals`; two angry `DANGER` eye slits; one `RedLight` OmniLight3D
(range 6, energy 0 → 2.5 by threat — the only extra light); `Glitch` glyph particles; `Haze` far-glow
quad. `set_threat(t)`: `Wall.scale.y = lerp(0.35, 1.0, t)`, lean toward the player, jitter amplitude and
label flicker rise with t, `Glitch.amount_ratio = t`, hidden when t ≈ 0 after a retreat.
`play_catch()`: 1.4 s tween — wall scales ×2.6 and lunges toward the camera, light 6, labels `CAUGHT`.
`play_retreat()`: 0.7 s topple backward, shrink, light 0, then hide. Max size at threat 1: 6 m × 2.6 m.

### 4.5 `scenes/runner/environment/corridor.tscn` + `.gd` (root `Corridor`, Node3D)

`set_scroll_speed(speed)` stores metres per second; `_process(delta)` integrates `_offset += speed * delta`
and writes it to the floor / ceiling / wall shader `scroll` uniforms, and moves the recycled `Pillars`
(MultiMesh, 12 per side every 8 m, wrap at z > +8) by the same `speed * delta`, so motion is frame-rate
independent. Rain is different: it is a `GPUParticles3D` with `fixed_fps 30`, so give it a +Z particle
velocity proportional to speed (m/s) via its process material and never multiply it by `delta` yourself. Optional `set_pursuit(t)`: fog and sun tint
toward red. Nodes: `Env` WorldEnvironment (BG colour `NAVY_BG`, ambient `142735` ×1.2, filmic tonemap,
glow enabled intensity 0.9 bloom 0.12 hdr_threshold 0.75, depth fog `NAVY_BG` begin 22 end 88, saturation
1.15), `Sun` DirectionalLight3D (`MATRIX`, 0.35, no shadows), `KeyLight` OmniLight3D near the player
(`CREAM`, 1.6, range 9), `Floor` PlaneMesh 8×100 at z −40 with `floor_grid.gdshader`, `WallL/R` PlaneMesh
100×6 at x ∓4 with `code_wall.gdshader`, `Ceiling` at y 6 (floor shader at 15 %), `LaneGlow` additive
quad under the player, `FarGlow` quad at z −88, `Rain` GPUParticles3D (320, lifetime 4, box (3.9, 0.2, 45)
at (0, 6.2, −44), glyph billboard material, `fixed_fps 30`), `SpeedLines` (80, emitting when
normalized > 0.6), `Dust` (60). `visibility_aabb` covers z −96..+12 on all particles. Budget: ≤ 15 draw
calls for the environment, 3 lights, no shadows. Dev scene `environment/dev/corridor_preview.tscn` with a
camera at the contract offset and keys 1–5 for speed.

### 4.6 `scenes/runner/ui/runner_hud.tscn` + `.gd` (root `RunnerHud`, CanvasLayer 10 — matches the contract's HUD mount) — `bind(game)`

Full-rect `Screen` Control (`mouse_filter IGNORE`, `Style.theme()`), anchored layout (viewport is
1280×720 with `expand` aspect; use anchors and 28 px margins, not fixed offsets):
top-left `HpRow` two `HpPip` controls (hex outline + check, `MINT` filled / `SLATE` hollow, pop on change)
+ `APPROVALS` caption, `PowerUps` chip column (name + 90×6 progress bar counting `duration → 0` from a
local timer; shield chip has no bar); top-centre `Time` `mm:ss.d` from `game.elapsed` and
`PursuitWarning` (arc ring counting `remaining/total`, text `UNREVIEWED BACKLOG · 18.0`, pulsing `ROSE`,
rate rising as remaining → 0; shown on `pursuit_started`, hidden on `pursuit_recovered` and on `caught`); top-right `Score` `%08d` with count-up tween and `Multiplier` `×2.0`
(`MINT`, `ORANGE` during nitro); bottom-right `Speed` bar + `SPEED 14.2 m/s`; centre `Toast` queue
(`RECOVERED +2 APPROVALS`, `BLOCKED`, `AUTO-FIX ×3`, `SHIELD READY`), `NitroBanner` `NITRO COMMIT!`,
`GetReady` with controls legend until `running`; overlays `Vignette` ColorRect (`vignette.gdshader`,
strength 0 → 0.85 while pursued, back to 0 on `pursuit_recovered`, 1.0 on `caught`, scanlines 0.06 always) and `HitFlash` (white 0.55 → 0 in
0.18 s on `damage_taken`, `MINT` 0.3 on `damage_blocked`). On `damage_taken` also
`game.camera_rig.shake(0.7)`. Hide gameplay widgets on `caught`; dim on pause.

### 4.7 `scenes/runner/ui/pause_menu.tscn` (root `PauseMenu`, CanvasLayer 21 — above the HUD's 10 and the contract's Overlays mount at 20, `process_mode ALWAYS`, hidden) — `bind(game)`

Shows on `paused_changed(true)`: dim + panel `PAUSED`, buttons `Resume` → `game.resume()`, `Restart` →
`game.retry()`, `Runner Menu` → `game.go_to_menu()`; focus loop; footer `ESC / START  resume`. Do **not**
bind `ui_cancel` (the backend owns the pause key). Never touch `get_tree().paused`.

### 4.8 `scenes/runner/ui/game_over.tscn` (root `GameOver`, CanvasLayer 22 — above the pause menu, `process_mode ALWAYS`, hidden) — `bind(game)`

On `run_finished(result)`: call your own `show_result(result, game.get_leaderboard())`. Dim fade, panel
680×560: heading `CAUGHT BY THE BACKLOG` (`ROSE`), stats grid (`SCORE %08d` `MINT`, `TIME mm:ss.d`,
`DISTANCE %d m`, `DODGED %d`, `POWER-UPS %d`), `NameRow` (`LineEdit` `max_length 16`, placeholder `Hoppy`,
`Save` button) shown when `result.qualifies`, `TOP 10` list (rank, name padded to 16, `%8d` score, `mm:ss`)
with the new run's row (`result.run_id`) highlighted `MINT`, buttons `Retry` → `game.retry()` and
`Runner Menu` → `game.go_to_menu()`. Save: `game.submit_name(name)`; on `true` disable Save (`SAVED`),
lock the LineEdit, re-render from `game.get_leaderboard()`, focus Retry; on `false` show
`Could not save to disk.` in `ROSE`. `text_submitted` also saves. Focus chain NameEdit → Save → Retry →
Menu (wrap); `ui_down` from the LineEdit moves to Save. `ui_cancel` → `game.go_to_menu()` only while visible.

### 4.9 `scenes/runner/audio/runner_audio.tscn` + `.gd` + `sfx_synth.gd` (root `RunnerAudio`, Node, `process_mode ALWAYS`) — `bind(game)`

`sfx_synth.gd` (`extends RefCounted`, static, cached): 16-bit mono 22050 Hz `AudioStreamWAV` recipes
built from sine/square/saw/noise with attack-decay envelopes, following `audio_service.gd::_tone`:
`footstep`, `jump`, `land`, `roll`, `lane_left`/`lane_right` (stereo, panned), `powerup`, `nitro`, `lgtm`,
`auto_fix`, `shield_block`, `hit`, `pursuit_start`, `pursuit_drone` (2 s loop), `heartbeat` (1 s loop),
`retreat`, `recovered_chime`, `caught`, `game_over`. Peak ≤ 0.8 full scale. Players: `OneShots`
(`AudioStreamPolyphonic`, polyphony 7, bus `SFX`), `Footsteps`, `Drone`, `Heartbeat` — 7 + 3 = a hard total of
10 simultaneous voices even during pursuit. Same sound not re-triggered within 40 ms. Footstep cadence `lerp(0.42, 0.20, normalized)` while running and grounded.
Triggers: `player_action` → jump/land/roll/lane; `power_up_collected` → powerup (+ kind sting);
`damage_blocked` → shield_block; `damage_taken` → hit + `AudioService.duck_music(-6, 0.4)` +
`hit_stop` is backend-owned (do not call unless you want it); `pursuit_started` → alarm + drone fade in;
`pursuit_progress` → start the `Heartbeat` loop **once** when `remaining/total` first drops below 0.35 (keep
an explicit `_heartbeat_on` flag; reset it on `pursuit_started`; stop the loop on `pursuit_recovered`, `caught`
and `run_finished`); `pursuit_recovered` → retreat + chime, drone
out; `caught` → boom, drone out; `run_finished` → game_over sting. BGM: load
`res://Assets/cyberpunk-street-files/Assets/music/cyberpunk-street.ogg` (CC0 per the package licence PDF;
record the composer caveat in `LICENSES.md`), `loop = true`, `AudioService.play_music(stream, -12.0)` from
both `runner_menu.gd` and `bind()`. `play_music`, `play_default_music`, `set_music_pitch` and `duck_music`
are added to `app/audio_service.gd` by the backend's contract PR (PR 1); merge `endless-runner` after that PR
lands before starting F5, and guard every call with `AudioService.has_method(...)` so the frontend never
breaks if it runs against an older `app/`; pitch `1.0 + 0.10 × normalized (+0.05 nitro)` via
`AudioService.set_music_pitch`, smoothed. Menus reuse `AudioService.play_ui(0/1)`.

### 4.10 `scenes/runner/runner_menu.tscn` + `.gd` (root **`RunnerMenu`**, Node3D)

`Backdrop`: instance `corridor.tscn` (`set_scroll_speed(3.5)`), `hoppy_runner_visual.tscn` in a warm-up
jog (`set_anim_state(&"run")`, `set_run_speed(0.25)`), a menu `Camera3D` at (2.6, 1.9, 3.4) looking at
(0, 1.0, −2) FOV 55 with a slow drift. `Interface` CanvasLayer mirroring `main_menu.gd` composition:
eyebrow `C O D E R A B B I T / E N D L E S S R U N N E R` 14 px `MINT`, title `THE CODEBASE` / `CORRIDOR`
60 px, subtitle `Outrun the unreviewed backlog.`, `Style.button`s `01 Play` → `AppRouter.go("runner_game")`,
`02 Leaderboard` (toggles a panel listing `runner_leaderboard.load_entries()` as rank / name / score / mm:ss,
`---` for empty rows, `Close` button), `03 Return to Main Menu` → `AppRouter.go("hub")`, `04 Quit Game` →
`AppRouter.quit_game()`; controls card (`A / D · ← →  Change lane`, `W / SPACE / ↑  Jump`,
`S / CTRL / ↓  Roll`, `ESC / START  Pause`, `Two hits without recovery and the backlog catches you.`);
footer hints. Focus loop like `main_menu.gd` lines 74–76; `Play.grab_focus()`; `AudioService.play_ui(1)`
on confirm; `_unhandled_input` `ui_cancel` closes the panel first, else `AppRouter.go("hub")`.

### 4.11 Tests and docs

`tests/runner_visual_smoke.gd` (`extends SceneTree`, same shape as `tests/menu_smoke.gd`): instantiate
every frontend scene, set base vars where relevant, call every contract method with sample arguments,
wait two frames, free, print `RUNNER VISUAL SMOKE: PASS/FAIL (n failures)`, `quit(failures)`.
`scenes/runner/ui/dev/mock_runner_game.gd` + `hud_preview.tscn`: a Node3D exposing every facade signal /
property / method with a scripted 40 s demo (speed ramp, power-ups, hit → pursuit → recovered, second hit →
caught → `run_finished` with a fake top-10) so HUD, overlays and audio are testable before the backend merges.
`docs/endless-runner.md` mirrors `docs/main-menu.md`: Run, Behavior and ownership, Art direction and
replacement points (with a Visual → Source → Licence table and the model-swap procedure for a future glTF
rabbit), Audio, Renderer notes (what Compatibility did and did not honour), Verification, Requests to backend,
Known gaps. `Assets/runner/LICENSES.md` columns: Asset · Path · Creator · Source · Licence · Modifications.
Screenshots to `docs/previews/endless-runner-{spike,corridor,gallery,hud,gameover}.png`.

## 5. Milestones

| # | Deliverable | Done when |
|---|---|---|
| F0 | palette, materials, glyph atlas, five shaders, `environment/dev/renderer_spike.tscn`, `LICENSES.md` | spike shows glow, fog, glyph particles and `scaling_3d_scale` working on Compatibility; findings noted for the docs |
| F1 | `corridor.tscn/gd` + `dev/corridor_preview.tscn` | seamless scroll at 0–26 m/s, ≤ 15 draw calls, freezes when `get_tree().paused` |
| F2 | `hoppy_runner_visual.tscn/gd` + `dev/hoppy_preview.tscn` | every state plays and blends; roll ≤ 0.9 m; feet at y 0; faces −Z |
| F3 | 8 hazard + 6 power-up visuals, `pursuer_visual`, `dev/hazard_gallery.tscn` | every visual ≤ 110 % of its hitbox; hooks idempotent after two `on_spawned()`; telegraphs readable |
| F4 | HUD, pause, game over, `mock_runner_game.gd`, `hud_preview.tscn` | whole demo works from the mock with keyboard and simulated gamepad; anchors hold at 1440×900 and 1000×720 |
| F5 | `sfx_synth.gd`, `runner_audio.tscn/gd` | every trigger audible in the mock; ≤ 10 voices; pitch ramp audible |
| F6 | `runner_menu.tscn/gd`, `tests/runner_visual_smoke.gd`, `docs/endless-runner.md`, previews | full loop with the backend: hub → menu → play → hit → pursuit → 18 s clean recovery → hit (new pursuit) → second hit during pursuit → caught → game over → save → retry → menu → hub |

Check commands (repo root):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/<file>.gd --check-only
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/menu_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/corridor_preview.tscn
```

`menu_smoke.gd` has two pre-existing mouse-hover failures on the installed Godot 4.7.0 (diagnostic baseline per
contract §9); do not add new ones.
