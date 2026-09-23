# Endless Runner starship asset refresh

This document records the initial environment pass. The subsequent [object readability and Hoppy pass](starship-readability.md) adds the latest asset changes and previews. Scope statements below describe the initial pass.

The completed runner now mounts an original spaceship interior with octagonal pressure bulkheads, bevelled hull plates, recessed maintenance machinery, service grilles, mint light conduits, amber power trunks, riveted metal deck panels and observation windows showing stars and a planet. The existing boss encounter gains a segmented reactor dock behind its combat space. All geometry and material detail is generated locally and cached. No downloaded art is required.

## Baseline and scope

Worktree: `/Users/jp/.codex/worktrees/9fa5/coderabbit-arcade`

Branch: `codex/starship-assets`. Base: `d64d84d801c09bedd93b33ea07f97161a898171a`, exactly the inspected `endless-runner-complete` tip. Both `claude/endless-runner-playable` and `claude/endless-runner-stages` are ancestors. The latest Claude stage commit at inspection was `aea8047`. The separate active frontend worktree was read only and was not modified.

Only the corridor scene's script reference changes in existing source. The new script extends the original corridor, retaining its facade, turn profile, pause semantics, viewport ownership and scrolling. Existing environment geometry is hidden. Its resources remain allocated so the existing corridor implementation and fixtures stay available; removing that legacy allocation is a separate optimization. All new architecture is cosmetic. The player, collision geometry, hazards, tools, controls, stage progression, boss models and combat code are unchanged.

The viewport uses 0.85 render scale instead of 0.5, preserving the original ownership-based restore on scene exit. This gives the deck and engineered edges more detail. Frame-rate and export performance across target machines have not been benchmarked.

## View the build

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/jp/.codex/worktrees/9fa5/coderabbit-arcade/hoppys-adventure-arcade --scene res://scenes/runner/runner_menu.tscn
```

The existing menu starts the existing game. For the environment-only preview, use `--scene res://scenes/runner/environment/dev/corridor_preview.tscn`. Existing preview keys select speed, pursuit tint and pause.

## Rendered evidence

Captured and visually inspected on Godot `4.7.stable.official.5b4e0cb0f`, OpenGL 4.1 Metal, Compatibility renderer, Apple M5 Max, at 1440x900. The repository pins 4.7.1, which is not installed here. These are actual engine renders, not concept images.

- [Real gameplay with HUD and hazards](../previews/starship/starship-gameplay.png)
- [Running view](../previews/starship/starship-run.png)
- [Architecture and Hoppy](../previews/starship/starship-architecture.png)
- [Existing Hydra with reactor dock](../previews/starship/starship-boss.png)
- [Turn geometry](../previews/starship/starship-turn.png)

The real gameplay fixture uses seed 12345 and the existing autopilot without changing gameplay configuration. It captures at 14 seconds, while state is `running`, stage 1. The other fixture stages asset views and the existing Hydra for visual review; it is not evidence of a manually played boss fight. The turn fixture hides Hoppy to expose the architecture.

Graphical fixture results, exit 0:

```text
STARSHIP CAPTURE: run draws=11 save=0
STARSHIP CAPTURE: architecture draws=11 save=0
STARSHIP CAPTURE: boss draws=28 save=0
STARSHIP CAPTURE: turn draws=7 save=0
STARSHIP GAMEPLAY: save=0 state=running stage=1
```

These are viewport draw counts for their respective complete fixtures, including visible characters where present. They are not full gameplay frame-rate measurements. The new environment has seven visible surfaces in normal traversal and ten with the reactor dock. Its six repeating batches hold eight 12-metre modules across the existing 96-metre scroll cycle.

## Verification

Commands run from this worktree. Each command below exited 0:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/starship-import.log --editor --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/starship-check.log --script res://tests/assets/starship_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/starship-scaffold.log --script res://tests/runner_scaffold_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/starship-smoke.log --script res://tests/runner_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/starship-visual-smoke.log --script res://tests/runner_visual_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --log-file /tmp/starship-capture.log --script res://scenes/runner/environment/starship/capture_starship.gd
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --log-file /tmp/starship-gameplay.log --script res://scenes/runner/environment/starship/capture_gameplay.gd
git diff --check
```

```text
STARSHIP TOTAL: 55810 triangles including deck and reactor dock
STARSHIP GEOMETRY: repeated modules=54432 triangles; 6 batches; 1 shared 256x256 texture
STARSHIP CHECK: PASS (67 checks, 0 failures)
RUNNER SCAFFOLD: PASS (0 failures / 366 checks)
RUNNER SMOKE: PASS (0 failures / 138 checks)
RUNNER VISUAL SMOKE: PASS (0 failures)
```

The new regression check covers lane clearance, no added collision, bounded geometry, wrapping at maximum speed, bend propagation, boss-dock lifecycle, pause, shared immutable meshes, private materials and viewport restoration with overlapping instances. The existing visual smoke passes the full menu, play, pursuit recovery, defeat, retry and hub return loop. Those tests are headless; the PNGs provide separate graphical evidence. Import reports the existing nested `Assets/SynthCitiesGodot/project.godot` warning. Final capture and check logs contain no script or shader errors.

## Exact changed-file manifest

Paths below are relative to this worktree. `.uid` files accompany the new scripts and shader. Changes are uncommitted and have not been pushed.

- `docs/assets/starship-refresh.md`
- `docs/previews/starship/starship-architecture.png`
- `docs/previews/starship/starship-boss.png`
- `docs/previews/starship/starship-gameplay.png`
- `docs/previews/starship/starship-run.png`
- `docs/previews/starship/starship-turn.png`
- `hoppys-adventure-arcade/scenes/runner/environment/corridor.tscn`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/capture_gameplay.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/capture_gameplay.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/capture_starship.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/capture_starship.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/starship_assets.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/starship_assets.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/starship_corridor.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/starship_corridor.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/starship_surface.gdshader`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/starship_surface.gdshader.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/starship_world.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/starship/starship_world.gd.uid`
- `hoppys-adventure-arcade/tests/assets/starship_check.gd`
- `hoppys-adventure-arcade/tests/assets/starship_check.gd.uid`
