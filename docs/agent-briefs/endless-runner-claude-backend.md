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
  except the four graybox placeholders you created in PR 1 (`runner_menu`, `ui/runner_hud`,
  `ui/pause_menu`, `ui/game_over`). `ui/runner_hud`, `ui/pause_menu` and `ui/game_over` are frozen from
  the end of PR 1. `runner_menu` has exactly one further edit, in PR 2: bring the graybox up to the
  contract §2 four-button set so `runner_scaffold_check.gd` can assert the same structure (`RunnerMenu`
  root, `buttons.size() == 4`) against the graybox or the frontend's scene. **From the moment the
  frontend's F6 `runner_menu` lands, `scenes/runner/runner_menu.*` is exclusively frontend-owned and the
  backend never edits it again** — a later scaffold need is raised as an entry under "Requests to
  backend" in `docs/endless-runner.md`, never by editing the scene.
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
`power_up.gd/.tscn`, `chunk.gd`, `runner_player.gd/.tscn`; the four graybox UI placeholders;
`tests/runner_scaffold_check.gd` (the structural check invoked by the PR 1 acceptance commands). Exit:
`--import` clean, `--check-only` with no unexpected diagnostics on every new `.gd` (see the Definition of
done below for the two permitted ones), `runner_game.tscn` loads headless, `menu_smoke.gd`
has no new failures.

**PR 2 — Playable graybox** (three parallel agents, disjoint files):

| Workstream 1: world + player | Workstream 2: content | Workstream 3: rules + tests |
|---|---|---|
| `player/runner_player.gd/.tscn`, `systems/speed_controller.gd`, `systems/camera_rig.gd`, `systems/debug_overlay.gd`, `pursuer/pursuer.gd`, `World/Floor` + graybox environment nodes, final `runner_game.gd` orchestration | `hazards/hazard.gd/.tscn`, `powerups/power_up.gd/.tscn`, `chunks/chunk.gd` + 19 `chunk_*.tscn`, `data/chunk_library.gd/.tres`, `systems/chunk_spawner.gd` | `systems/hit_manager.gd`, `score_manager.gd`, `effect_manager.gd`, `runner_leaderboard.gd`, `autopilot.gd`, `tests/runner_logic.gd`, `tests/runner_chunk_validator.gd`, `tests/runner_smoke.gd` |

Only Workstream 1 edits `runner_game.tscn` / `runner_game.gd` after PR 1.

## Definition of done

**PR 1 (contract scaffold):**

```sh
#!/usr/bin/env bash
# Fails fast on any error and refuses engines other than 4.7.1.stable. Set DIAGNOSTIC=1 to allow
# another 4.7.x build; such a run is diagnostic only and must be labelled as such when reported.
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
version="$("$GODOT_BIN" --version)"
if [[ "$version" != 4.7.1.stable* ]]; then
  if [[ "${DIAGNOSTIC:-0}" == "1" && "$version" == 4.7.* ]]; then
    echo "DIAGNOSTIC RUN on $version (another 4.7.x build; not acceptance)"
  else
    echo "Acceptance requires Godot 4.7.1.stable (DIAGNOSTIC=1 allows other 4.7.x only), found $version" >&2; exit 1
  fi
fi
"$GODOT_BIN" --headless --path hoppys-adventure-arcade --import

# Godot exits 0 when a --script cannot be loaded, and a test that crashes part-way exits 0 without
# ever printing its verdict, so neither the exit status nor the file's existence proves anything on
# its own: the run has to say, in its own words, that it passed. `marker` is that sentence. The
# captured output stays in $RUN_TEST_LOG for the two callers that need to look closer.
RUN_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$RUN_TEST_DIR"' EXIT
RUN_TEST_LOG=""
# Engine-level errors that invalidate a result however green the test's own verdict line looks.
# Single source of truth: run_test enforces it, and the menu_smoke tolerance below reuses it so a
# tolerated run can never hide one.
RUN_TEST_NOISE='SCRIPT ERROR|Parse Error|Failed to load script|Failed to compile depended scripts|Identifier not found'
run_test() {
  local f="hoppys-adventure-arcade/tests/$1" marker="$2" code noise
  [[ -f "$f" ]] || { echo "missing test script: $f" >&2; exit 1; }
  RUN_TEST_LOG="$RUN_TEST_DIR/$1.log"
  # tee keeps the output streaming while it is captured; PIPESTATUS[0] is the test's own status.
  set +e
  "$GODOT_BIN" --headless --path hoppys-adventure-arcade --script "res://tests/$1" 2>&1 | tee "$RUN_TEST_LOG"
  code=${PIPESTATUS[0]}
  set -e
  if [[ $code -ne 0 ]]; then
    printf 'run_test: %s exited %d\n' "$1" "$code" >&2
    return 1
  fi
  if ! grep -qF "$marker" "$RUN_TEST_LOG"; then
    printf 'run_test: %s exited 0 but never printed %s\n' "$1" "$marker" >&2
    return 1
  fi
  # A test can print its PASS line and still have been degraded by engine errors along the way.
  # grep exits 1 when it matches nothing, which is the good case here, so its status is deliberately
  # dropped: under `set -euo pipefail` an unguarded assignment from it would abort the whole gate.
  set +e
  noise="$(grep -nE "$RUN_TEST_NOISE" "$RUN_TEST_LOG" | head -3)"
  set -e
  if [[ -n "$noise" ]]; then
    printf 'run_test: %s printed %s but the engine reported errors:\n%s\n' "$1" "$marker" "$noise" >&2
    return 1
  fi
}

run_test runner_scaffold_check.gd 'RUNNER SCAFFOLD: PASS'

# menu_smoke has exactly two documented mouse-hover failures on 4.7.0 (contract §9). A DIAGNOSTIC run
# tolerates only that precise signature and must say so in the report; a different failure count, a
# new message, a parse error or a missing scene exits 1 even under DIAGNOSTIC, and a real 4.7.1
# acceptance run fails on any menu_smoke failure at all. Every runner test stays strict either way.
# The two hover failures are a 4.7.0 artefact, so the tolerance needs the baseline engine as well as
# DIAGNOSTIC=1: on any other 4.7.x build menu_smoke stays strict. Godot 4.7.0 reports itself as
# `4.7.stable.official.<hash>` — there is no `.0` in the string — so `4.7.stable*` is the pattern that
# actually matches it and `4.7.0.stable*` would never fire.
# `if ! run_test ...` is what keeps `set -e` from aborting here, and the tolerance reads the log
# run_test already captured.
if ! run_test menu_smoke.gd 'MENU SMOKE: PASS'; then
  if [[ "${DIAGNOSTIC:-0}" == "1" ]] \
      && [[ "$version" == 4.7.stable* ]] \
      && ! grep -qE "$RUN_TEST_NOISE" "$RUN_TEST_LOG" \
      && grep -qF 'MENU SMOKE: FAIL (2 failures)' "$RUN_TEST_LOG" \
      && grep -qF 'Mouse hover overrides old gamepad focus' "$RUN_TEST_LOG" \
      && grep -qF 'Pointer exit releases mode preview' "$RUN_TEST_LOG"; then
    echo "DIAGNOSTIC: tolerating the two documented 4.7.0 menu_smoke hover failures; label them as diagnostic in the report (frontend: also in docs/endless-runner.md)"
  else
    echo "menu_smoke failed with something other than the documented 4.7.0 hover baseline on this engine" >&2
    exit 1
  fi
fi
```

Plus `--check-only` on every runner `.gd`, tracked **and** untracked, with `"$GODOT_BIN"` and the same
version preamble. That gate passes when the run shows **no unexpected diagnostics**, not when it is silent.
Exactly two diagnostics are permitted, both known limitations of running `--check-only` without autoloads:
`Identifier not found: AppRouter` in the scripts that use that autoload (`runner_game.gd`,
`runner_menu.gd`), and the cascade it causes — `Failed to compile depended scripts` plus its
`Failed to load script ... with error "Compilation failed"` — in every script that preloads one of them
(all systems, hazard, power-up, pursuer, player, chunk, and the tests that load them). Every other parse
or analysis error is real and must be fixed; they are reported ahead of that compile-stage noise, so the
gate stays useful. Run it as a filter rather than reading the output by eye:

```sh
#!/usr/bin/env bash
# --check-only gate: fails on anything that is not one of the two documented autoload diagnostics.
# Use the same GODOT_BIN / version preamble as the blocks above.
set -uo pipefail
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

# The AppRouter suppression is scoped by the `at:` line that follows the diagnostic, which names the
# script the identifier is in: only runner_game.gd and runner_menu.gd are excused. The same error in
# any other script is printed and fails the gate. The cascade lines are scoped the same way: they are
# excused only under res://scenes/runner/ or res://tests/, the roots that preload those two scripts.
grep -q '^AppRouter=' hoppys-adventure-arcade/project.godot \
  || { echo "AppRouter autoload missing from project.godot" >&2; exit 1; }
check_only() {
  local f="$1" raw out code documented=0
  set +e
  raw="$("$GODOT_BIN" --headless --path hoppys-adventure-arcade --check-only --script "res://$f" 2>&1)"
  code=$?
  set -e
  # Stateful, exact suppression. An `Identifier not found: AppRouter` is excused only when the line
  # immediately after it locates the error in runner_game.gd or runner_menu.gd by full res:// path,
  # and the compile cascade is excused only once such a diagnostic has been accepted in THIS script's
  # output — Godot always emits the root cause first, so a cascade without it is a different failure —
  # AND the cascade itself names a script under res://scenes/runner/ or res://tests/, the two roots
  # whose scripts legitimately preload runner_game.gd / runner_menu.gd. A cascade from anywhere else
  # is a real failure wearing the same words, so it is printed and fails the gate.
  # The trailing __DOCUMENTED_CASCADE__ tells the shell an excused diagnostic was actually seen.
  out="$(printf '%s\n' "$raw" | awk '
    /^Godot Engine/ { next }
    /Compile Error: Identifier not found: AppRouter/ { pending = $0; next }
    pending != "" && /^[[:space:]]*at: / {
      if ($0 ~ /res:\/\/scenes\/runner\/runner_(game|menu)\.gd:[0-9]+\)/) {
        accepted = 1; pending = ""; next
      }
      print pending; print; pending = ""; next
    }
    pending != "" && NF { print pending; pending = "" }
    # The depended-scripts line carries no path of its own, so its following `at:` line is what gets
    # scoped; a "Failed to load script" line names the script in quotes, which is scoped directly.
    /Compile Error: Failed to compile depended scripts\./ { cascade = $0; cascade_path = ""; next }
    /Failed to load script .* with error "Compilation failed"\./ {
      cascade = $0
      cascade_path = $0
      sub(/^.*Failed to load script "/, "", cascade_path)
      sub(/".*$/, "", cascade_path)
      next
    }
    cascade != "" && /^[[:space:]]*at: / {
      excused = 0
      if (accepted) {
        if (cascade_path != "") {
          if (cascade_path ~ /^res:\/\/(scenes\/runner|tests)\//) excused = 1
        } else if ($0 ~ /res:\/\/(scenes\/runner|tests)\//) excused = 1
      }
      if (excused) { cascade = ""; cascade_path = ""; next }
      print cascade; print; cascade = ""; cascade_path = ""; next
    }
    cascade != "" && NF { print cascade; cascade = ""; cascade_path = "" }
    NF { print }
    END {
      if (pending != "") print pending
      if (cascade != "") print cascade
      if (accepted) print "__DOCUMENTED_CASCADE__"
    }
  ')"
  case "$out" in
    *__DOCUMENTED_CASCADE__)
      documented=1
      out="${out%__DOCUMENTED_CASCADE__}"
      out="${out%$'\n'}"
      ;;
  esac
  if [[ -n "$out" ]]; then
    printf 'check-only: unexpected diagnostics in %s\n%s\n' "$f" "$out" >&2
    return 1
  fi
  # Godot's own exit status, no longer masked by `|| true`. Measured on 4.7.0 it is 0 even for the
  # documented AppRouter compile failure, so this branch fires on the harder failures the filter
  # cannot see — a missing binary, a project that will not open — while still tolerating a future
  # engine that reports the documented cascade the awk just accepted through a non-zero exit.
  if [[ $code -ne 0 && $documented -eq 0 ]]; then
    printf 'check-only: %s exited %d with no documented diagnostic\n' "$f" "$code" >&2
    return 1
  fi
}

status=0
while IFS= read -r f; do
  check_only "${f#hoppys-adventure-arcade/}" || status=1
# Both runner pathspecs on purpose (same as the frontend brief): git's `*` already crosses `/`, but the
# `**/` form says so explicitly; `sort -u` drops the duplicates the overlap produces.
done < <(git ls-files --cached --others --exclude-standard \
  -- 'hoppys-adventure-arcade/scenes/runner/*.gd' \
     'hoppys-adventure-arcade/scenes/runner/**/*.gd' \
     'hoppys-adventure-arcade/tests/*.gd' | sort -u)
[[ $status -eq 0 ]] && echo "check-only: no unexpected diagnostics"
exit $status
```

`--cached --others --exclude-standard` is what puts a not-yet-committed script inside the gate; a git
pathspec `*` already crosses `/`, so those two patterns cover the whole runner tree. The `at:` line that
follows a permitted diagnostic is dropped with it, while the one under a real error is kept, so a failure
still reports its file and line. `runner_game.tscn` and `runner_menu.tscn` load headless with no
`push_error`.

**PR 2 (playable graybox):** everything above, plus

```sh
#!/usr/bin/env bash
# Same gate as PR 1: fail fast, and refuse engines other than 4.7.1.stable unless DIAGNOSTIC=1
# admits another 4.7.x, in which case the run is diagnostic only and must be labelled as such.
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
version="$("$GODOT_BIN" --version)"
if [[ "$version" != 4.7.1.stable* ]]; then
  if [[ "${DIAGNOSTIC:-0}" == "1" && "$version" == 4.7.* ]]; then
    echo "DIAGNOSTIC RUN on $version (another 4.7.x build; not acceptance)"
  else
    echo "Acceptance requires Godot 4.7.1.stable (DIAGNOSTIC=1 allows other 4.7.x only), found $version" >&2; exit 1
  fi
fi
"$GODOT_BIN" --headless --path hoppys-adventure-arcade --import

# Godot exits 0 when a --script cannot be loaded, and a test that crashes part-way exits 0 without
# ever printing its verdict, so neither the exit status nor the file's existence proves anything on
# its own: the run has to say, in its own words, that it passed. `marker` is that sentence. The
# captured output stays in $RUN_TEST_LOG for the two callers that need to look closer.
RUN_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$RUN_TEST_DIR"' EXIT
RUN_TEST_LOG=""
# Engine-level errors that invalidate a result however green the test's own verdict line looks.
# Single source of truth: run_test enforces it, and the menu_smoke tolerance below reuses it so a
# tolerated run can never hide one.
RUN_TEST_NOISE='SCRIPT ERROR|Parse Error|Failed to load script|Failed to compile depended scripts|Identifier not found'
run_test() {
  local f="hoppys-adventure-arcade/tests/$1" marker="$2" code noise
  [[ -f "$f" ]] || { echo "missing test script: $f" >&2; exit 1; }
  RUN_TEST_LOG="$RUN_TEST_DIR/$1.log"
  # tee keeps the output streaming while it is captured; PIPESTATUS[0] is the test's own status.
  set +e
  "$GODOT_BIN" --headless --path hoppys-adventure-arcade --script "res://tests/$1" 2>&1 | tee "$RUN_TEST_LOG"
  code=${PIPESTATUS[0]}
  set -e
  if [[ $code -ne 0 ]]; then
    printf 'run_test: %s exited %d\n' "$1" "$code" >&2
    return 1
  fi
  if ! grep -qF "$marker" "$RUN_TEST_LOG"; then
    printf 'run_test: %s exited 0 but never printed %s\n' "$1" "$marker" >&2
    return 1
  fi
  # A test can print its PASS line and still have been degraded by engine errors along the way.
  # grep exits 1 when it matches nothing, which is the good case here, so its status is deliberately
  # dropped: under `set -euo pipefail` an unguarded assignment from it would abort the whole gate.
  set +e
  noise="$(grep -nE "$RUN_TEST_NOISE" "$RUN_TEST_LOG" | head -3)"
  set -e
  if [[ -n "$noise" ]]; then
    printf 'run_test: %s printed %s but the engine reported errors:\n%s\n' "$1" "$marker" "$noise" >&2
    return 1
  fi
}

# Every runner test is strict: no tolerance, DIAGNOSTIC or not. PR 2 is "everything above, plus",
# so the PR 1 scaffold check runs here too and this block stands on its own.
run_test runner_scaffold_check.gd 'RUNNER SCAFFOLD: PASS'
run_test runner_logic.gd 'RUNNER LOGIC: PASS'
run_test runner_chunk_validator.gd 'RUNNER CHUNKS: PASS'
run_test runner_smoke.gd 'RUNNER SMOKE: PASS'
```

`tests/runner_visual_smoke.gd` is frontend-owned and gates the frontend branch, not a backend-only PR: run
it too whenever the checkout actually contains frontend visuals, but a backend PR with no frontend art in
the tree is not blocked by it.

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
