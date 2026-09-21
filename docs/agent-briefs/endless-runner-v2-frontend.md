# Agent brief — Endless Runner v2 frontend (Codex / gpt-6-astra)

Second iteration: **HUD legibility, a Star Fox-style pursuit alert, boss/projectile/tool visuals, cinematic turns,
stage banners and stage-clear cards, new audio.** Branch `codex/endless-runner-stages` (off
`codex/endless-runner-frontend` @ d3e219b); PR into `endless-runner`. Read, in order:
`docs/endless-runner-contract.md` §11 (authoritative facade, hooks, tables), `docs/agent-briefs/endless-runner-v2-frontend-design.md`
(the full visual/audio design you implement), the v1 brief `docs/agent-briefs/endless-runner-codex-frontend.md`
(ground rules, style, acceptance script), and `docs/endless-runner.md` (your own docs, to be extended).

## Ground rules (unchanged)

- Edit only frontend-owned paths (contract §1 + §11.5–§11.9 + the new `scenes/runner/boss/**` visual paths,
  `scenes/runner/ui/**`, `scenes/runner/environment/**`, `scenes/runner/audio/**`, `scenes/runner/shaders/**`,
  `tests/runner_visual_smoke.gd`, `docs/endless-runner.md`, `docs/previews/*`, `Assets/runner/**`). Never edit
  `scenes/main_menu/menu_style.gd`, backend files, `project.godot`, or any `*_visual_base.gd` (all of them are
  backend-owned, including `boss/boss_visual_base.gd`; F8 *extends* it from `boss/visuals/*_visual.gd`, it does not
  edit it).
- Style: snake_case, **no `class_name`**, `const X = preload(...)`, typed `:=`, tabs, explicit return types, UI built
  imperatively with `Style` / the new `hud_style.gd`, cached materials duplicated before mutation, `.gd.uid` committed,
  no `TIME` in shaders that must freeze on pause (drive `clock` uniforms from GDScript).
- Keep `gl_compatibility`; respect the draw budgets in the design §6; the audio voice cap stays 10.
- Do not commit or push; do not run graphical scenes (the coordinator captures previews on the host).
- Where the design and contract §11 disagree, §11 wins (hook names `on_spawned / set_phase / set_health /
  play_telegraph / play_attack / play_hit / play_resist / play_defeat / play_retreat`; tool kinds `review_comment,
  lint_rule, unit_test, auto_fix_patch` at `powerups/visuals/<kind>_visual.tscn`; projectile variants `orb, low,
  high, wide` at `hazards/visuals/projectile_visual.tscn`; `lane_mask` bits; UI scenes `ui/pursuit_alert.tscn`,
  `ui/boss_hud.tscn`, `ui/stage_banner.tscn`, `ui/stage_clear.tscn`).

## Milestones

| # | Deliverable | Depends on | Done when |
|---|---|---|---|
| **F7** | `ui/hud_style.gd`; legibility re-spec of `runner_hud.gd`, `hud_glyph.gd`, `pause_menu.gd`, `game_over.gd` (design §1); `ui/pursuit_alert.tscn/.gd` + `shaders/scanline_portrait.gdshader` (design §2); pursuer shockwave + vignette corner bars; `alert_sting`/`radar_pulse` with the radar→heartbeat handover; `ui/dev/pursuit_alert_preview.tscn`; mock emits `pursuit_alert` too | v1 facade only | `runner_visual_smoke.gd` prints exactly `HUD LEGIBILITY: PASS (n labels checked)` and `PURSUIT ALERT: PASS` (the acceptance gate greps these strings); every gameplay-critical label ≥ 18 units, outline ≥ 6, panel-backed; voices ≤ 10; the coordinator's recaptured `endless-runner-hud.png` is legible at 960×540 |
| **F8** | `boss/boss_art.gd`; three boss visuals on `boss/boss_visual_base.gd`; `ui/boss_hud.tscn/.gd`; `boss/telegraph.gd`; `hazards/visuals/projectile_visual.tscn/.gd` (4 variants); four tool visuals + `boss/tool_art.gd`; `boss/tool_tracer.gd` + `boss/damage_number.gd`; `boss/dev/boss_gallery.tscn`; boss/tool/projectile SFX (design §3, §5) | backend v2 merged (hooks, `boss_*`/`tool_collected` signals) | `BOSS VISUALS: PASS (3 checked; peak draw census=<n>)` with n ≤ 40 per boss inside the §11.5 envelope and `TOOLS AND PROJECTILES: PASS` (exact gate strings); tools visually distinct from the six power-ups; projectiles ≤ 110 % of hitbox; boss HUD and pips animate from the mock and from a real fight |
| **F9** | `corridor.set_turn()` + shader bend + CornerWall + pillar bend + `set_phase`/`set_boss_arena`; `environment/dev/turn_preview.tscn`; `ui/stage_banner.tscn`, `ui/stage_clear.tscn`; `turn_whoosh`/`stage_clear` SFX + music duck/pitch table; `capture_previews.gd` fixtures; `docs/endless-runner.md` v2 (design §4–§6) | backend v2 merged (`turn_*`, `stage_*`) | `TURN: PASS` (monotone bend, yaw back to 0, ≤ 18 corridor draws, pause freezes) and `STAGE SEAM: PASS` (a real seam under the shortened smoke config: turn, banner, boss, clear card) alongside `RUNNER FULL LOOP: PASS`; `RUNNER AUDIO: 30 recipes/triggers` with peak voices ≤ 10; previews committed by the coordinator |

## Acceptance (the v1 acceptance script in the v1 brief, unchanged in shape)

`run_test runner_smoke.gd 'RUNNER SMOKE: PASS'`, then `run_test runner_visual_smoke.gd 'RUNNER VISUAL SMOKE: PASS'`
whose captured log must also contain every milestone marker the gate greps for: `RUNNER FULL LOOP: PASS`,
`RUNNER DEV SCENES: PASS`, `HUD LEGIBILITY: PASS`, `PURSUIT ALERT: PASS` (F7), `BOSS VISUALS: PASS`,
`TOOLS AND PROJECTILES: PASS` (F8), `TURN: PASS`, `STAGE SEAM: PASS` (F9), `TURN WARNING: PASS`, `BOSS INTRO: PASS`
(F10), plus the audio census line `RUNNER AUDIO: <n> recipes/triggers` with `peak voices=10` (n = 30 after F9, 32 after
F10); `run_test menu_smoke.gd 'MENU SMOKE: PASS'` with the documented 4.7.0 tolerance. Use `--log-file /tmp/...` when
the sandbox blocks `user://logs`; if the full loop fails only on the two sandbox `user://` persistence checks, say so
verbatim (the coordinator re-runs on the host).

## Report format

1) what was built, 2) verification output verbatim, 3) requests to backend (file them in `docs/endless-runner.md`
too), 4) touched files.
