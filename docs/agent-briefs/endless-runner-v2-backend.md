# Agent brief — Endless Runner v2 backend (Claude / Opus 5)

Second iteration of the Endless Runner: **faster ramp, stages with automatic cinematic turns, boss fights with
telegraphed projectiles and auto-fire tool pickups, a pursuit alert, endless escalation.** Branch
`claude/endless-runner-stages` (off `claude/endless-runner-playable` @ c85159e); PR into `endless-runner`. Read, in
order: `docs/endless-runner-contract.md` §11 (authoritative tuning, facade, hooks), `docs/endless-runner-systems.md`
§10 (implementation spec), the v1 sections they extend, and the v1 brief `docs/agent-briefs/endless-runner-claude-backend.md`
(ground rules, style, `--check-only` gate, `run_test` acceptance script, the leaderboard_path rule).

## Ground rules (unchanged from v1)

- Godot project root `hoppys-adventure-arcade/`; binary `/Applications/Godot.app/Contents/MacOS/Godot` (4.7.0
  installed, 4.7.1 pinned → results are diagnostic). Style: snake_case, **no `class_name`**, `const X = preload(...)`,
  typed `:=`, tabs, explicit return types, `##` doc comments, `.gd.uid` committed.
- Backend never edits frontend-owned paths (contract §1 + §11.5–§11.9). Graybox fallbacks for every new visual
  mount (boss, projectile, tool) ship with the backend; the optional UI mounts have **no** graybox (DebugOverlay
  covers them).
- No new autoloads. Every backend → frontend call is `has_method`/`is_instance_valid`-guarded. Never mutate
  `run_config.tres`; all new fields have defaults in `run_config.gd`.
- Every test that instantiates `RunnerGame` sets `leaderboard_path` **before** `add_child`. Never write the real
  `user://leaderboard.cfg`.
- Do not commit; the coordinator commits after the validator and CodeRabbit loops.

## Work packages

Three Opus workstreams, disjoint files. A and B run in parallel; C starts when both report.

### WS-A — Stage director, speed, turn, facade (owns `run_config.gd`)

Files: `data/run_config.gd` (every §11.10 field, land this first), `data/stage_defs.gd`, `systems/stage_manager.gd`,
`systems/turn_rig.gd`, `systems/speed_controller.gd` (run_clock, stage bonus, difficulty floor),
`systems/camera_rig.gd` (`set_turn`), `systems/chunk_spawner.gd` (`set_spawning`, phase gate),
`systems/hit_manager.gd` (`pursuit_alert`), `pursuer/pursuer.gd` (`pursuer_distance_changed`),
`systems/debug_overlay.gd` (phase/stage/boss lines), `systems/runner_leaderboard.gd` (`SCHEMA_VERSION = 2`),
`runner_game.gd` + `runner_game.tscn` (tree delta §11.3, `StageManager` node, all §11.4 signals/properties/methods,
result fields, `run_clock`, `track_z`/`track_aabb`, HUD mounts for the four optional UI scenes, `begin()` call after
resets, caught → abort), `tests/runner_scaffold_check.gd` (new paths, signals, properties; optional mounts tolerated
when absent). Wire `Systems/StageManager` to a `BossArena` reference by path (`World/TurnRig/BossArena`) and call
`boss_encounter.start/tick/abort/finished` through `has_method` guards so WS-A runs green before WS-B lands (a
missing arena means the `boss` phase ends immediately with `boss_retreated` skipped — document this fallback).

### WS-B — Boss encounter, projectiles, tools (never touches `run_config.gd`; codes against §11.10 names)

Files: `boss/boss_arena.tscn`, `boss/boss_encounter.gd`, `boss/boss_defs.gd`, `boss/boss_visual_base.gd` (+ graybox
boss), `hazards/projectile.gd/.tscn`, `hazards/hazard_defs.gd` (four `projectile` variants), `hazards/hazard_visual_base.gd`
(`closing_speed` var, default 0.0), `powerups/tool_pickup.gd/.tscn`, `powerups/tool_defs.gd`, graybox tool visual
fallback, `systems/score_manager.gd` (bonus reasons). Read `config.<field>` exactly as §11.10 names them; if a field is
missing at your test time because WS-A has not landed it yet, say so in the report rather than adding it.

### WS-C — Autopilot and tests (after A and B)

Files: `systems/autopilot.gd` (closing speed per slice, telegraph planning, tool greed), `tests/runner_logic.gd`,
`tests/runner_smoke.gd`, `tests/runner_chunk_validator.gd`, new `tests/runner_boss_validator.gd`; per systems §10.8.
Integration fixes discovered here go back to A/B files only through the coordinator (report them; do not edit).

## Definition of done

Use the v1 brief's acceptance gate (`docs/agent-briefs/endless-runner-claude-backend.md`: version check, `check_only()`,
`run_test <file> <marker>` with the noise filter, `DIAGNOSTIC=1` for other 4.7.x builds) and add the v2 suite:

```sh
run_test runner_scaffold_check.gd 'RUNNER SCAFFOLD: PASS'
run_test runner_logic.gd 'RUNNER LOGIC: PASS'
run_test runner_chunk_validator.gd 'RUNNER CHUNKS: PASS'
run_test runner_boss_validator.gd 'RUNNER BOSS: PASS'
run_test runner_smoke.gd 'RUNNER SMOKE: PASS'
# menu_smoke.gd through the documented DIAGNOSTIC tolerance block (exactly the two 4.7.0 hover failures)
```

Every runner test prints its marker with 0 failures; each `run_test` fails closed on a non-zero exit, a missing marker
or engine error lines, so a later test cannot mask an earlier failure. `--check-only` on every new or modified `.gd`
shows no unexpected diagnostics (only the documented `AppRouter` cascade from `runner_game.gd` / `runner_menu.gd`).
`runner_game.tscn` loads headless with no `push_error` with and without the frontend visuals present. A 60 s graybox
autopilot run reaches `boss_spawned` under the shortened smoke config. Report exactly what you ran and the output;
never claim a pass without evidence.

## Orchestration (coordinator, Fable 5.1)

1. WS-A ∥ WS-B → coordinator sanity → WS-C → read-only Opus validator against contract §11 + systems §10 → fixer
   rounds until clean.
2. CodeRabbit loop (`coderabbit review --agent --include-untracked --base endless-runner`) → Opus fixers → repeat to
   zero findings (verify "duplicated block" reports with `grep '^func ' | sort | uniq -d` and the passing tests
   before acting; they have all been false so far).
3. Commit, push, open the PR into `endless-runner`; merge into `codex/endless-runner-stages` so Codex F8/F9 build
   against the real facade.
