# Agent brief — Endless Runner backend (Claude / Opus 5)

You are implementing the **backend** of the Endless Runner microgame in Hoppy's Adventure Arcade
(Godot **4.7.1** pinned, GDScript; the build machine currently has 4.7.0 stable, so results produced on
4.7.0 are diagnostic and final acceptance re-runs on 4.7.1 per the contract's engine version policy). A separate agent (Codex) builds the frontend in parallel against a shared
contract. Read these first, in order:

1. `docs/endless-runner-contract.md` — the contract. Paths, node names, signals, hitbox table, tuning.
2. `docs/endless-runner-systems.md` — the implementation spec for every backend file, chunk catalog, tests.
3. `Hoppys_Adventure_Arcade_Technical_Implementation.md` §3, §4, §9, §11, §14 — architecture rules.
4. `hoppys-adventure-arcade/scenes/main_menu/main_menu.gd`, `menu_style.gd`, `mode_portal.gd`,
   `app/app_router.gd`, `app/audio_service.gd`, `tests/menu_smoke.gd` — code style and the only test pattern.

## Ground rules

- Godot project root is `hoppys-adventure-arcade/`. Editor binary: `/Applications/Godot.app/Contents/MacOS/Godot`.
- Style: `snake_case` files, **no `class_name`**, `const X = preload(...)`, typed GDScript with `:=`,
  tabs, an explicit return type on every func (`-> void` for procedures), UI built in `_ready()` with `Style.theme()/label()/button()`. Commit `.gd.uid` files.
- You own only the backend paths listed in the contract §1. Never create or edit frontend-owned files
  except the four graybox placeholders in the contract PR (`runner_menu`, `ui/runner_hud`, `ui/pause_menu`,
  `ui/game_over`), and never touch them again afterwards.
- No new autoloads. Managers are children of `RunnerGame`.
- Never mutate `run_config.tres` at runtime. Balance values come from the contract §7; do not invent others.
- Every backend → frontend call is defensive: fetch the frontend node with `get_node_or_null()` (or keep the
  reference returned by the mount), check `is_instance_valid()`, then `has_method()` before invoking. A missing,
  failed or freed frontend node must never break `runner_game.tscn`.
- Follow the Godot 4.7 pitfalls list in the systems spec §9.

## Work packages

**PR 1 — Contract scaffold** (single agent): `project.godot` `[input]` + `[layer_names]` +
`physics_interpolation`; `app/app_router.gd` (route `runner_game`, `process_mode ALWAYS`, unpause before
`change_scene_to_file`, `AudioService.play_default_music()` on `hub`); `app/audio_service.gd`
(`play_music`, `play_default_music`, `set_music_pitch`, `duck_music`); `tests/menu_smoke.gd` lines 60–68
→ assert `current_scene.scene_file_path == router.ROUTES[route]`; `runner_layers.gd`;
`data/run_config.gd` + `.tres`; `hazards/hazard_defs.gd`; `powerups/power_up_defs.gd`; the four
`*_visual_base.gd`; `runner_game.gd` with every signal/enum/facade method (stubs allowed) and
`runner_game.tscn` with the full tree; loadable stubs of every systems script, `hazard.gd/.tscn`,
`power_up.gd/.tscn`, `chunk.gd`, `runner_player.gd/.tscn`; the four graybox UI placeholders. Exit:
`--import` clean, `--check-only` clean on every new `.gd`, `runner_game.tscn` loads headless, `menu_smoke.gd`
has no new failures.

**PR 2 — Playable graybox** (three parallel agents, disjoint files):

| Workstream 1: world + player | Workstream 2: content | Workstream 3: rules + tests |
|---|---|---|
| `player/runner_player.gd/.tscn`, `systems/speed_controller.gd`, `systems/camera_rig.gd`, `systems/debug_overlay.gd`, `pursuer/pursuer.gd`, `World/Floor` + graybox environment nodes, final `runner_game.gd` orchestration | `hazards/hazard.gd/.tscn`, `powerups/power_up.gd/.tscn`, `chunks/chunk.gd` + 19 `chunk_*.tscn`, `data/chunk_library.gd/.tres`, `systems/chunk_spawner.gd` | `systems/hit_manager.gd`, `score_manager.gd`, `effect_manager.gd`, `runner_leaderboard.gd`, `autopilot.gd`, `tests/runner_logic.gd`, `tests/runner_chunk_validator.gd`, `tests/runner_smoke.gd` |

Only Workstream 1 edits `runner_game.tscn` / `runner_game.gd` after PR 1.

## Definition of done

**PR 1 (contract scaffold):**

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_scaffold_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/menu_smoke.gd
```

Plus `--check-only` on every new or modified `.gd` (errors naming the autoload singletons `AppRouter`,
`AudioService`, `SaveService` are a known limitation of `--check-only`, not defects). `runner_game.tscn`
and `runner_menu.tscn` load headless with no `push_error`.

**PR 2 (playable graybox):** everything above, plus

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_logic.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_chunk_validator.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_smoke.gd
```

All runner tests print `PASS`. `menu_smoke.gd` has two pre-existing mouse-hover failures when run on the
installed 4.7.0 (diagnostic baseline, recorded in the contract §9); it must not gain new ones, and is
expected to pass fully on the pinned 4.7.1. Report what you ran and the exact output; never claim a test
passed without evidence.

## Orchestration loops (run by the coordinator, Fable 5.1)

1. **Implementation validator**: after each work package, a read-only Opus agent compares the
   implementation against `docs/endless-runner-contract.md` and `docs/endless-runner-systems.md`
   and lists every missing or divergent item with file:line evidence. For each gap a fixer Opus
   agent applies the fix; the validator runs again. Repeat until the validator reports no gaps, then
   move to the next package.
2. **CodeRabbit loop**: `coderabbit review --agent --base endless-runner` (and `--include-untracked`
   while uncommitted) on the branch; a fixer Opus agent implements every finding; re-run CodeRabbit;
   repeat until there are no findings. Then commit and open the PR into `endless-runner`.
