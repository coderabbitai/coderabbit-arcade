# Endless Runner v2 — Frontend design (stages, turns, bosses, legibility)

Design pass output (Opus 5, 2026-09-19) reconciled by the coordinator. Frontend agent: Codex (gpt-6-astra).
Branch `codex/endless-runner-stages` off `codex/endless-runner-frontend` @ d3e219b. All paths relative to
`hoppys-adventure-arcade/`. Milestones F7–F9 continue F0–F6. The v2 contract addendum
(`docs/endless-runner-contract.md` §11) is authoritative where the two disagree.

**Ownership note:** `scenes/main_menu/menu_style.gd` is hub-shared and outside the runner contract §1
frontend list. v2 must **not** edit it. Add `scenes/runner/ui/hud_style.gd` (frontend-owned) that wraps
`Style.label()` / `Style.button()` and layers runner legibility on top.

---

## 1. HUD legibility

### Audit (measured against `docs/previews/endless-runner-hud.png`, `endless-runner-gameplay.png`)

`window/stretch/mode="canvas_items"`, `aspect="expand"`, base 1280×720, `min_width/height` 960×540. Every size
below is a **base unit** that renders at **0.75×** physical at the minimum window. That is the root cause: a
14-unit label is ~10 physical px.

| Widget | Now (`runner_hud.gd`) | Problem |
|---|---|---|
| `APPROVALS` header | 14, MINT | 10.5px at min window; sits on the mint glyph wall, contrast ~1.5:1 |
| Power-up chip label / bar | 14 MINT / 90×6 | Same; 6-unit bar is 4.5px |
| Time | 24 CREAM | OK size, zero outline, floats over the vanishing point |
| Pursuit label | 16 ROSE | **Worst offender.** ROSE `ff7185` over the DANGER pursuit vignette ≈ 1.4:1 |
| Pursuit ring (`hud_glyph.gd`) | 36×36 ctl, r≈15.5, arc width 3–4 | 2.3px arc at min window; SLATE track invisible |
| Score / multiplier | 32 / 20 MINT | Readable; no outline |
| Speed label / bar | 17 CREAM / 240×8 | 12.75px; bar unlabelled at its ends |
| Toast / Nitro banner | 24 MINT / 30 ORANGE | Unbacked, centred over the brightest floor grid |
| Get Ready | 22, 3 lines | Thin, unbacked |
| Game over | title 30, stats 18, rows 16, error 14 | Panel-backed; 14/16 too small |
| Pause | title 40, hint 16 | Hint too small |

No `Label` sets `outline_size`, `outline_color` or shadow. `Style.theme()` sets `default_font_size = 19` only.

### Targets

- **Minimum contrast 7:1** for any text read while moving, against the *worst* pixel of its backing. Achieved by
  backing panels, not colour choice.
- **Minimum 18 base units** for gameplay-critical text (13.5 physical px at 960×540). Decorative text may go to 15.
- **Stroke ≥ 3 base units** for rings, bars and pips.

### `scenes/runner/ui/hud_style.gd`

```text
const Style   = preload("res://scenes/main_menu/menu_style.gd")
const Palette = preload("res://scenes/runner/environment/runner_palette.gd")
static func label(text, size, color, weight := &"body") -> Label
static func panel(border: Color, alpha := 0.82) -> StyleBoxFlat
static func backed(text, size, color, pad := Vector2(12, 6)) -> PanelContainer
static func bar(extent: Vector2, fill: Color, track := Palette.SLATE) -> ProgressBar
```

`hud_style.label()` calls `Style.label()` then applies on every label: `outline_size = max(6, roundi(size * 0.30))`,
`font_outline_color = Palette.NAVY_BG`; `shadow_offset = Vector2(0, 2)`, `font_shadow_color = Color(NAVY_BG, 0.75)`
(hard 2-unit drop shadow, no blur; canvas items are unaffected by the 0.5 retro 3D downscale).
`hud_style.panel()` returns a `StyleBoxFlat`: `bg_color = Color(NAVY_BG, alpha)`, 2-unit border in the caller's
accent, `corner_radius_all = 3`, content margins 14/14/8/8.

### HUD re-spec (base units at 1280×720)

| Widget | New | Backing |
|---|---|---|
| `APPROVALS` cluster | header **18** MINT; pips **48×52**, hex stroke 3 | one `PanelContainer`, MINT border α0.82 (header + pips + chips) |
| Power-up chip | label **18** MINT, bar **112×9** | inside the left panel |
| Time | **30** CREAM, tabular | `PanelContainer`, SLATE border α0.70, width 200 |
| Score | **36** MINT | `PanelContainer`, MINT border α0.82, right-aligned, width 300 |
| Multiplier | **24**, MINT → ORANGE under Nitro | same panel |
| Speed label | **20** CREAM, `"SPEED 16.7 m/s"` | `PanelContainer`, SLATE border α0.70 |
| Speed bar | **260×12**, track SLATE, fill MINT→ORANGE at Nitro, 2-unit CREAM tick at 26 m/s | inside that panel |
| Toast | **28** CREAM, ≤ 26 chars | auto-width `PanelContainer`, accent border by kind, fades in 0.12 s |
| Nitro banner | **34** ORANGE | ORANGE-border panel |
| Get Ready | title **34**, control lines **22** | NAVY_BG α0.88 panel, centred; fades after 2.5 s |
| Pause title / buttons / hint | **46** / theme default / **20** | existing panel |
| Game over title / stats / rows / error | **34** / **22** / **19** / **17** | existing panel; `custom_minimum_size` `Vector2(760, 620)` |

**3D labels read in motion** (stage banner, boss name plate, tool tags): `Label3D` with `font_size ≥ 40`,
`pixel_size` so on-screen height ≥ 26 base units at spawn depth, `outline_size = 10`, `outline_modulate = NAVY_BG`,
`texture_filter = NEAREST`, `billboard = ENABLED`. The 5×7 glyph atlas stays for rain/walls only; where an atlas
look is wanted use a `MultiMeshInstance3D` of atlas quads at ≥ 0.22 m per glyph.

### Pursuit ring

Rewrite `hud_glyph.gd`'s `ring` branch: control **56×56**, radius 24, filled `NAVY_BG` α0.85 disc first, SLATE track
arc width **5**, progress arc width **6** in CREAM with a DANGER inner arc at width 3; centre a **20**-unit
remaining-seconds number. Pursuit copy moves into the alert panel (§2); the inline label becomes `"BACKLOG  %.1fs"`
at **22** CREAM on a DANGER-border panel.

### Cut / keep at 24–32 m/s

- Keep: approvals pips, score, time, speed bar, pursuit ring + seconds, toasts, stage banner, boss HP bar.
- Cut: multiplier decimals (round unless fractional), the Get Ready control list after 2.5 s, the power-up *name*
  once its bar runs (icon + bar after 0.6 s).
- One centre-screen message at a time; the toast queue carries a priority so `STAGE CLEAR` / `INCOMING` pre-empt
  `+250 BONUS`.
- Nothing new in the band `y ∈ [0.30h, 0.72h]` (lane / telegraph reading zone).

---

## 2. Pursuit alert (Star Fox style)

New `scenes/runner/ui/pursuit_alert.gd` + `.tscn`, a `Control` child of the HUD's `widgets`, anchored `BOTTOM_LEFT`,
`offset (28, -236)`, size `420×196`.

- **Slide-in.** On `pursuit_started(seconds)`: `position.x = -440` → 28 over 0.28 s `TRANS_CUBIC/EASE_OUT`, 0.08 s
  CREAM border flash. On `pursuit_recovered` / `caught` it tweens out over 0.22 s.
- **Portrait.** Procedural, in a `SubViewport` (256×256, `UPDATE_WHEN_VISIBLE`, 2D only): a 5×4 grid of NAVY PR
  cards matching `pursuer_visual.gd`'s wall, two DANGER eye slits, three CREAM headlines from the same `HEADLINES`
  constant. A `ColorRect` carries `shaders/scanline_portrait.gdshader` (≤ 18 lines: scanlines driven by a `clock`
  uniform set from GDScript, chromatic x-offset scaled by `threat`, edge roll-bar). **Never `TIME`** (pause freezes it).
- **Waveform bar.** 380×26 `Control` whose `_draw()` calls `draw_multiline()`: 48 bars, heights from a deterministic
  `sin(i*0.7 + clock*6) * sin(i*0.31 + clock*2.3)` mix, amplitude by `1 - fraction`; MATRIX → DANGER with threat.
- **Copy** (CREAM 20, outline 6):
  ```text
  INCOMING TRANSMISSION
  UNREVIEWED PR BACKLOG
  CATCHES UP IN 18.0 s
  ONE MORE HIT BEFORE RECOVERY AND IT HAS YOU
  ```
  Line 3 counts down from `pursuit_progress`. Line 4 (17 CREAM α0.85) states the catch rule in-game.
- **Radar/pulse widget.** 88×88 top-right of the panel: SLATE rings, CREAM sweep at `lerpf(0.9, 4.2, 1 - fraction)`
  rev/s, DANGER blip at radius `lerpf(0.9, 0.12, fraction)`; a ring shockwave per revolution so the visual pulse and
  the `radar_pulse` SFX share one clock.
- **Pursuer "pulse".** `pursuer_visual.gd`: a `_shockwave` TorusMesh (`additive(DANGER, 0.5)`, +1 draw) parented to
  `_wall`, scaled 1 → 3.4 and faded over `lerpf(1.6, 0.45, _threat)` s, restarting; `play_retreat` hides it;
  `play_catch` fires three in 0.35 s. Torus radius peaks at 2.6 m at y 1.2 (inside the pursuer envelope).
- **Proximity vignette.** `strength = 0.25 + 0.6 * (1 - fraction)`; new `corner_bars` uniform slides two DANGER bars
  in from top and bottom by `(1 - fraction) * 0.06` of the screen height.
- **Resolution beats.** `pursuit_recovered` → MATRIX border/waveform, copy `RECOVERED — BACKLOG REVIEWED` +
  `+2 APPROVALS`, hold 1.2 s, slide out. `damage_blocked` during pursuit → MINT flash + `BLOCKED` 0.6 s, alert stays.
  `caught` → portrait fills the panel, scale 1 → 1.35 over 0.45 s while widgets hide.
- **Audio:** `alert_sting` on start, `radar_pulse` loop (see §5), `recovered_chime` on recovery.

---

## 3. Boss presentation

### 3.1 Base hooks — `scenes/runner/boss/boss_visual_base.gd` (backend-owned file; frontend consumes)

| Hook (contract §11.5 names) | When | Frontend behaviour |
|---|---|---|
| `on_spawned()` | after vars set | build once, reset tweens/particles, internal state `idle`, phase 1 |
| `set_phase(phase: int)` | 1-based, on `boss_phase_changed` | palette shift, extra limbs/rings, faster sway; internal `phase_change` beat 0.9 s |
| `set_health(hp, max_hp)` | on `boss_health_changed` | drives HP-dependent looks (cracks widen, wall intensity drops) |
| `play_hit(tool_kind, damage)` | damaging tool | `hurt` beat: flash + damage number + tool-coloured sparks, auto-returns after 0.25 s |
| `play_resist(tool_kind)` | resisted tool | dull grey flash, `RESISTED` tag, no damage number |
| `play_telegraph(lane_mask, kind, seconds)` | on `boss_attack_telegraph` | aim/charge pose toward the lanes in `lane_mask` (bit i = lane i, x = (i − 1) × 2) over `seconds` |
| `play_attack(kind)` | at fire | release pose + muzzle flash (the projectile node is backend-spawned) |
| `play_defeat()` / `play_retreat()` | fight end | 1.6 s break-up / fly-away, then the backend frees it |

Base vars (set before `on_spawned()`): `kind`, `boss_name`, `max_hp`, `phase_count`, `hover_z`, `sway_amplitude`,
`sway_period`. The visual sways itself in `_process` (PAUSABLE).



### 3.2 The three bosses (`scenes/runner/boss/visuals/`)

Shared builder `boss_art.gd` (mirrors `hazard_art.gd`): `box()`, `sphere()`, `torus()`, `label()`, `batch()`,
`flash()`, `shatter()`. Envelope: a bounding box **≤ 7 m wide × 3 m deep** whose vertical extent stays within **y ∈ [1.6, 6.1]** (4.5 m of
headroom above the y 1.6 floor, so lane decals stay visible); the core body is nominally centred around **y ≈ 2.6**
at z = hover_z (−14) and may rise within the box during phase changes. Sway ±2.2 m over 3.2 s (phase 0) → 2.2 s (phase 2).

| Boss | Build | Draws |
|---|---|---|
| **Flaky Test Swarm** (stage 1) | 24 test-tile cubes in one MultiMesh, colours flickering MATRIX↔DANGER on a deterministic noise clock; DANGER core sphere with `hologram` shell; two glyph particle clouds (`PASS`/`FAIL`); name plate. Phase 2: three orbiting sub-swarms. | **8** |
| **Merge Conflict Hydra** (stage 2) | Three necks (5 boxes each, one MultiMesh, 20 instances pre-allocated), heads: NAVY_2 wedge + LILAC eye + `<<<<<<< HEAD` / `=======` / `>>>>>>> theirs` Label3D; pulsing zigzag seam quad; heads track the telegraphed lane. Phase 2 grows a fourth neck. | **15** |
| **Legacy Monolith** (stage 3) | 6×4×2.4 slab of 9 plates (MultiMesh), SLATE→NAVY, 6 ORANGE "tech debt" cracks (second MultiMesh), a `code_wall` face quad, two DANGER vents, `@deprecated since 2011` label. Cracks widen per phase; wall `intensity` drops with HP. | **9** |

Steady-state ≤ 18 draws per boss, defeat peak ≤ 34 (< 40 cap). Palette: DANGER bodies, ORANGE accents, MATRIX only on
damageable highlights, LILAC for the Hydra's "theirs", CREAM text.

**Internal states** (driven by the §11.5 hooks): `idle` (sway + bob + slow rotation); `play_telegraph` → lean toward the
lanes, charge glow 0→1 over `seconds`, core scales 1→1.6; `play_attack` → 0.12 s recoil + muzzle flash; `play_hit` → 0.18 s
white flash via a *duplicated* material's `emission_energy_multiplier` + 0.06 m jolt; `set_phase` → 0.9 s rise 0.8 m,
strobe, ring expands, HP pips animate; `play_defeat` → instances scatter on a CPU ballistic curve, emissives fade, one
burst, toast `BUG FIXED`; `play_retreat` → fly-away over 1.6 s.

### 3.3 Boss HUD — `scenes/runner/ui/boss_hud.tscn/.gd` (contract §11.8 mount)

`CENTER_TOP`, offset `(-380, 92)`, size `760×74`, below the time panel. Name plate `BOSS · MERGE CONFLICT HYDRA` at
**26** CREAM on a DANGER-border panel; HP bar 720×22 (track NAVY_BG α0.9, DANGER fill, 3-unit CREAM edge, a chip bar
draining 0.35 s later); `phase_count` hex pips (26×28) flashing CREAM on `boss_phase_changed`; fill tweens 0.18 s;
border pulses below 25 %; slides in on `boss_spawned`, out on `boss_defeated`.

### 3.4 Telegraph, projectiles, tools, auto-fire

**Lane telegraph** — `scenes/runner/boss/telegraph.gd` (pooled ×3): floor decal `QuadMesh` 2.0 × 30 at `y = 0.008`,
`additive(DANGER, 0.35)` (the `hazard_art.gd` floor-marker convention) with an inset MATRIX quad shrinking to zero
over `seconds`; a billboarded 1.9 × 5 beam (`hologram`, alpha 0.15 → 0.55); a Label3D at y 2.4 naming the attack
(`GLOB` / `BEAM` / `SWEEP`), font 44, `pixel_size` 0.006, outline 10. **3 draws per lane.**

**Projectiles** — `scenes/runner/hazards/visuals/projectile_visual.tscn/.gd` (extends `hazards/hazard_visual_base.gd`;
`kind = projectile`, `variant` selects the look; `closing_speed` is provided); bounds ≤ 110 % of the §11.6 hitbox:

| Variant (§11.6) | Visual | Draws |
|---|---|---|
| `orb` (1 lane) | DANGER sphere + `hologram` shell + 12-particle trail | 3 |
| `low` (full width) | low stack-trace wave: DANGER additive box the exact hitbox size, CREAM core strip | 2 |
| `high` (full width, chest height) | diff-bar beam: thin box, `additive(DANGER, 0.6)`, CREAM core at 0.35 × height, grows over 0.1 s | 2 |
| `wide` (2 lanes) | fused-branches blade 3.6 m wide at y 0.5, ORANGE additive, 8 glyph tiles riding it | 2 |

**Tool items** — `scenes/runner/powerups/visuals/<kind>_visual.tscn/.gd` (extend `powerups/power_up_visual_base.gd`,
mounted by the backend `tool_pickup`) sharing `scenes/runner/boss/tool_art.gd`. Distinct from the six power-ups
(MINT, spinning, ring + halo + tag): tools are **MATRIX-cored, ORANGE-ringed, non-spinning, pulsing toward the boss**.

| Tool kind (§11.7) | Silhouette | Colour | Tag |
|---|---|---|---|
| `review_comment` | speech-bubble prism + tail, CREAM `//` | MATRIX body, ORANGE rim | `REVIEW COMMENT` |
| `auto_fix_patch` | double chevron `»` (two angled boxes; the power-up wrench is single) | MATRIX + CREAM bolt | `AUTO-FIX` |
| `lint_rule` | comb: 5 thin bars in one MultiMesh | ORANGE bars, MATRIX base | `LINT` |
| `unit_test` | open CREAM square frame + MATRIX tick | MATRIX tick | `UNIT TEST` |

Each ≤ 7 draws; pickup radius 0.35; bob ±0.06 m; 0.5 Hz scale pulse synced to the boss's vulnerability.

**Auto-fire** — `scenes/runner/boss/tool_tracer.gd` (pooled ×4) + `damage_number.gd` (pooled ×6): on
`tool_collected(kind, damage)` a tool-coloured additive tracer strip from Hoppy's chest (y 1.1) to the boss over
0.14 s (1 draw); at arrival the boss `play_hit` flash + 20-particle sparks (1 draw); a Label3D `"-%d"` at font 56
(CREAM, DANGER outline) rises 1.1 m over 0.7 s with random x (2 draws). Camera shake is backend-owned
(`camera_rig.shake` on tool hits, requested).

### 3.5 Stage banner and stage-clear card

**Stage banner** — `scenes/runner/ui/stage_banner.gd`, `CENTER`, on `stage_started(index, name, speed)`:
`STAGE 2` (30 MINT, letter-spaced) / `MERGE CONFLICT HYDRA` (52 CREAM) on a NAVY_BG α0.9 panel with MINT rules wiping
outward 0.35 s; hold 1.6 s, fade 0.4 s; deferred until `turn_finished` during a turn; suppressed if a boss is on screen.

**Stage clear card** — `scenes/runner/ui/stage_clear.gd`, on `stage_cleared(index, bonus)`:
```text
STAGE 2 CLEAR
MERGE CONFLICT HYDRA — FIXED
  TIME          00:48.2
  TOOLS USED    14
  BONUS        +2500
Fixing harder bugs ahead.
```
Title 44 MATRIX, subtitle 26 CREAM, rows 24 (CREAM labels, MINT values, 2-column `GridContainer`), bonus 28 ORANGE,
footer 22 MINT. Panel 640×360, MATRIX border, NAVY_BG α0.92; scale 0.92→1.0 + fade in 0.25 s; bonus counts up 0.5 s;
holds 2.2 s; exits 0.35 s; PAUSABLE (a gameplay beat, not an overlay).

---

## 4. Turns

**Constraint.** `camera_rig.gd` is backend-owned and holds the camera; gameplay objects live under `World/Chunks`.
The corridor sells the turn alone, with a fixed camera. This is safe because a turn is a hazard-free stage seam
(guaranteed by the backend contract).

**Hook:** `corridor.set_turn(progress: float, direction: int) -> void` — `progress` 0→1 across ~2.5 s, `direction`
−1/+1, idempotent, no internal clock (pause freezes it because the backend stops calling); `set_turn(0.0, 0)` resets.

Three layers:

- **(a) Curvature deformation.** Shared vertex displacement in `floor_grid`, `code_wall` and a `far_glow` copy:
  ```glsl
  uniform float bend = 0.0;        // signed curvature
  uniform float bend_start = 6.0;  // metres ahead of the player where the bend begins
  void vertex() {
      float d = max(0.0, -(MODEL_MATRIX * vec4(VERTEX,1.0)).z - bend_start);
      VERTEX.x += bend * d * d;
      world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
  }
  ```
  `PlaneMesh.subdivide_depth = 72` on Floor, Ceiling, WallL, WallR (zero extra draws, ~1.2 k verts). `bend` ramps
  `0 → ±0.0042 → 0` on `sin(progress * PI)`; at peak the far floor end (z = −90) displaces ≈ 30 m laterally.
- **(b) World yaw about the player.** `rotation.y = direction * deg_to_rad(11.0) * sin(progress * PI)` on the corridor
  root (origin at the player's z = 0 plane). Lane lines shift ≤ 0.2 m at the player's feet.
- **(c) Parallax glyph sweep.** New `code_wall` uniform `lateral_scroll = direction * progress * 14.0`.

Pillars: apply `x += bend * d * d` plus the local yaw to the 24 CPU instances. **Far glow / corner:** `FarGlow` fades out
over `progress 0 → 0.3` sliding along the bend, back in `0.7 → 1.0`; a `CornerWall` 12 × 7 quad at z −52, yawed
`direction * 55°`, `code_wall` duplicate at `intensity 0.4`, with a `TURN` chevron decal, fades in as FarGlow fades
out. Net **+1 draw at most**; corridor 10 → 12 of a documented budget raised to **14 / 18**. Pause: PAUSABLE, all
uniforms GDScript-driven, no `TIME`. `turn_whoosh` at `progress 0.05`; HUD dims non-essential widgets to α0.55;
stage banner waits for `turn_finished`.

**Dev scene** `scenes/runner/environment/dev/turn_preview.tscn/.gd`: corridor at 20 m/s, Left/Right play a 2.5 s
turn, `[`/`]` scrub, Space pauses, on-screen readout of `progress`, `direction`, `bend`, `yaw°`, draw calls.

**Renderer risks (gl_compatibility):** feed `fwidth` the post-displacement position and clamp `max(fwidth(p), 0.004)`;
widen the lane `smoothstep` to `0.02–0.075` while `bend != 0`; widen rain/dust `visibility_aabb` x to ±34 or drop
`amount_ratio` to 0.35 during turns; no `fwidth` in the vertex stage (none used).

---

## 5. Audio

Extend `sfx_synth.gd` `RECIPES` (deterministic cached 16-bit 22050 Hz PCM) with two new waveform cases `"fm"` and
`"burst"`, and `runner_audio.gd`'s trigger map:

| SFX | Trigger | Recipe |
|---|---|---|
| `alert_sting` | `pursuit_started` | 0.55 s 180 Hz square gated 3× by a 9 Hz envelope |
| `radar_pulse` | loop from the alert; pitch from `pursuit_progress` | 0.5 s loop, 1200→900 Hz sine 40 ms blip; `pitch_scale = lerpf(0.8, 1.6, 1 - fraction)` |
| `telegraph_tick` | `boss_attack_telegraph`, 3× accelerating | 0.06 s 1600 Hz square (ambient) |
| `projectile_whoosh` | projectile fire | 0.30 s 900→180 Hz noise band sweep, lane-panned |
| `tool_pickup` | `tool_collected` | 0.22 s 880→1760 Hz sine (a fifth above `powerup`) |
| `tool_fire` | `tool_collected` + 0.10 s | 0.18 s 2400→600 Hz saw |
| `boss_hit` | tracer arrival | 0.20 s 300→90 Hz fm |
| `boss_phase` | `boss_phase_changed` | 0.80 s 220→440 Hz chord, detuned second voice |
| `boss_defeat` | `boss_defeated` | 1.30 s burst: noise crunch then ascending chord 330→1320 Hz |
| `stage_clear` | `stage_cleared` | 1.00 s ascending major arpeggio |
| `turn_whoosh` | `turn_started` | 1.20 s noise 300→2400→300 Hz following `sin(progress*PI)`, panned toward `direction` |

**Voice budget stays at 10.** `radar_pulse` reuses the `Heartbeat` player: the radar is the pursuit loop and *becomes*
the heartbeat below `fraction < 0.35` (pitch drop + stream switch). Boss and stage cues go through `OneShots`.
`HIGH_PRIORITY` gains `boss_defeat`, `boss_phase`, `stage_clear`, `alert_sting`, `turn_whoosh`, `tool_fire`; ambient:
`telegraph_tick`, `projectile_whoosh`, `tool_pickup`, `boss_hit`. Per-kind retrigger gate table `GATE` (default 0.04,
`boss_hit` 0.09).

**Music:** pitch/duck only (AudioService keeps exactly two players). `boss_spawned` → `duck_music(-4, 0.6)` held for the
fight (target-offset variable in the existing `_pitch` smoothing) + pitch `+0.04`; `boss_phase_changed` →
`duck_music(-8, 0.35)`; `stage_cleared` → `duck_music(-10, 1.2)` and `_pitch` held at 1.0 for the card; `turn_started`
→ `duck_music(-5, 0.5)`, restored at `turn_finished`. All `has_method`-guarded.

---

## 6. Files and milestones

### New frontend files

```text
scenes/runner/ui/hud_style.gd
scenes/runner/ui/pursuit_alert.gd / .tscn
scenes/runner/ui/boss_hud.gd / .tscn
scenes/runner/ui/stage_banner.gd / .tscn
scenes/runner/ui/stage_clear.gd / .tscn
scenes/runner/ui/dev/pursuit_alert_preview.tscn/.gd
scenes/runner/ui/dev/boss_hud_preview.tscn/.gd
scenes/runner/boss/boss_art.gd
scenes/runner/boss/telegraph.gd / .tscn
scenes/runner/boss/tool_tracer.gd
scenes/runner/boss/damage_number.gd
scenes/runner/boss/visuals/flaky_test_swarm_visual.gd / .tscn
scenes/runner/boss/visuals/merge_conflict_hydra_visual.gd / .tscn
scenes/runner/boss/visuals/legacy_monolith_visual.gd / .tscn
scenes/runner/hazards/visuals/projectile_visual.gd / .tscn
scenes/runner/powerups/visuals/{review_comment,lint_rule,unit_test,auto_fix_patch}_visual.gd / .tscn
scenes/runner/boss/visuals/tool_art.gd
scenes/runner/boss/dev/boss_gallery.tscn / .gd
scenes/runner/environment/dev/turn_preview.tscn / .gd
scenes/runner/shaders/scanline_portrait.gdshader
```

Modified: `runner_hud.gd`, `hud_glyph.gd`, `pause_menu.gd`, `game_over.gd`, `corridor.gd`, `floor_grid` /
`code_wall` / `far_glow` / `vignette` shaders, `pursuer_visual.gd`, `runner_audio.gd`, `sfx_synth.gd`,
`ui/dev/mock_runner_game.gd` (emits the new signals on a scripted 90 s demo), `environment/dev/capture_previews.gd`,
`tests/runner_visual_smoke.gd`, `docs/endless-runner.md`.

Style rules unchanged: `snake_case`, **no `class_name`**, `const X = preload(...)`, `:=`, explicit return types, tabs,
UI built imperatively via `Style`/`hud_style`, cached materials duplicated before mutation, `.gd.uid` committed.

### `tests/runner_visual_smoke.gd` additions

- `check_hud_legibility()` — every `Label` under HUD, pause, game over, banner, card: `font_size >= 18` for the
  gameplay-critical set, `outline_size >= 6`, a `PanelContainer` ancestor or an explicit exemption. Prints
  `HUD LEGIBILITY: n labels checked`.
- `check_pursuit_alert()` — mock `pursuit_started → progress 1.0 → 0.0 → recovered`: panel visible, radar rate strictly
  increasing, copy contains the catch rule, portrait SubViewport renders, everything freezes under `paused`.
- `check_bosses()` — each boss: `on_spawned()` twice (idempotent), every state, all phases, `play_hit` per tool,
  `play_telegraph` per lane, `play_defeat`; merged AABB inside 7 × 4.5 × 3 m with bottom ≥ y 1.6; draw census ≤ 40.
  Prints `BOSS VISUALS: 3 checked; peak draw census=<n>`.
- `check_tools_and_projectiles()` — 4 tools reset/collect twice; all four projectile variants (`orb`, `low`, `high`,
  `wide`) ≤ 110 % of their hitbox; tracer and damage-number pools return to idle.
- `check_turn()` — `set_turn(p, ±1)` at p = 0, 0.25, 0.5, 0.75, 1: monotone bend to the peak and back, `rotation.y`
  returns to 0, CornerWall/FarGlow never both fully opaque, draws ≤ 18, pause mid-turn leaves the transform unchanged
  for 10 frames.
- `check_runner_audio()` — recipe census 19 → **30**, peak voices ≤ 10 under a boss burst (3 tools + 2 projectiles +
  phase change in one frame), radar→heartbeat handover on one player.

### Previews

Add `endless-runner-pursuit-alert.png`, `endless-runner-boss-swarm.png`, `endless-runner-boss-hydra.png`,
`endless-runner-boss-monolith.png`, `endless-runner-turn.png` (progress 0.5), `endless-runner-stage-clear.png`;
recapture `endless-runner-hud.png` and `endless-runner-gameplay.png`. Fixtures in `capture_previews.gd` with budgets
(boss gallery `(3 × 40) + (4 × 8) + (3 × 4) + 20 = 184`; turn preview 18).

### Milestones

| # | Deliverable | Done when |
|---|---|---|
| **F7** | `hud_style.gd`; re-spec of `runner_hud.gd`, `hud_glyph.gd`, `pause_menu.gd`, `game_over.gd`; `pursuit_alert`; `scanline_portrait.gdshader`; pursuer shockwave + vignette corner bars; `alert_sting` / `radar_pulse` with the radar→heartbeat handover; `ui/dev/pursuit_alert_preview.tscn`; mock emits `pursuit_*` richly | `HUD LEGIBILITY` and `PURSUIT ALERT` pass; every gameplay-critical label ≥ 18 units, outline ≥ 6, panel-backed; recaptured `endless-runner-hud.png` legible at 960×540; voices ≤ 10 |
| **F8** | `boss_art.gd`, three boss visuals on `boss_visual_base`, `boss_bar`, `telegraph`, 3 projectile visuals, 4 tool visuals + `tool_art.gd`, tracer + damage numbers, `boss/dev/boss_gallery.tscn`, boss/tool/projectile SFX | `BOSS VISUALS: 3 checked` with peak ≤ 40 draws each inside 7 × 4.5 × 3 m; tools distinct from power-ups; projectiles ≤ 110 % of hitbox; boss bar + pips animate from the mock |
| **F9** | `corridor.set_turn()` + shader bend + CornerWall + pillar bend, `turn_preview`, `stage_banner`, `stage_clear`, `turn_whoosh` / `stage_clear` SFX + music duck/pitch table, all previews, `docs/endless-runner.md` v2 | `TURN` passes (monotone bend, yaw returns to 0, ≤ 18 draws, pause freezes); `RUNNER VISUAL SMOKE: PASS` and `RUNNER FULL LOOP: PASS` including a stage seam, a turn, a boss and a stage-clear card; previews committed; audio census 30 with peak voices ≤ 10 |

### Draw-call budget

| Addition | Steady | Peak |
|---|---|---|
| Corridor turn | +0 | +1 |
| Boss visual (each) | ≤ 18 | ≤ 34 (defeat) |
| Lane telegraph (3 max) | 3 | 9 |
| Projectile (≤ 6 live) | 2–3 | 18 |
| Tool item (≤ 3 live) | ≤ 7 | 21 |
| Tracer + sparks + damage number | 0 | 4 |
| Boss bar / banner / card / alert (2D) | ≤ 10 | ≤ 14 |
| Pursuer shockwave | +1 | +1 |
| **Worst boss frame** | — | **≈ 135** (< the measured 162-draw gallery frame) |
