# CodeRabbit space equipment and quarantine hunter

This pass supersedes the earlier barrier/pickup readability adjustments and the armored-wall pursuer. It preserves the spaceship environment, recognizable Hoppy model and polish, gameplay systems, scoring, boss behavior, item effects, collisions, death timing and retry routing. No backend files were edited.

## New asset concepts

| Asset | New physical design |
|---|---|
| Jump barrier | Jammed merge conduit: two branch pipes converge into a raised lock, with a low occupied silhouette and central jump crest. |
| Roll barrier | Suspended merge scanner: overhead bridge, hanging sensors and red underside, leaving the actual roll clearance open. |
| Approve Shield | Rabbit-eared shield emitter with an inset approval check. |
| Auto Fix | Repair welder with a rubber grip, power cell and twin contact tips. |
| LGTM | Rabbit-handled approval stamp with an octagonal face. |
| Nitro | Twin booster pods with exhaust nozzles and retaining bands. |
| Super Jump | Paired powered boots with spring contacts and dark soles. |
| Code Review | Binocular inspection scanner with two recessed lenses and a grip. |
| Review Comment | Handheld communicator with antenna, waveform display and speaker slots. |
| Lint Rule | Filter cartridge with three raised conductive prongs. |
| Unit Test | Armored test module with a check window and side connectors. |
| Auto Fix Patch | Plug-in repair cassette with a raised patch cross and service seams. |
| Death pursuer | Compact rabbit-eared quarantine drone, twin spinning ducted fans, code-bracket cheeks, sensor eyes and articulated pincers. No wall, grid, floating headlines or giant catch scaling. |

Collectibles have cream hardware shells, mint power-up inlays or CodeRabbit-orange boss-tool inlays. Their locator badges shrink from the previous near-camera 96-pixel target to 32 pixels, with a 24-pixel distant target. Physical equipment remains within the original pickup footprint. Barrier labels are secondary to occupied shape and clearance.

The hunter banks and bobs in pursuit, its receiver ears move independently, fans accelerate with threat, claws deploy during the 1.4-second capture, and recovery turns it away over the existing 0.7 seconds. The backend still owns pursuit position and capture timing. Its alert HUD retains existing status copy.

## Preview evidence

Open `docs/previews/overhaul/index.html` for:

- Before/after normal-camera images of both barriers and all ten collectibles at 8, 16 and 28 metres.
- Ten detail views of the actual equipment meshes, with locator badges hidden only in that fixture.
- Actual seeded gameplay at 8, 14, 22 and 32 seconds, plus jump and roll action frames.
- Actual gameplay at 24 m/s, using a fixture-only base-speed override. Shipping RunConfig is unchanged.
- Before/after real capture-sequence frames, results, and a staged three-quarter hunter portrait.

Before images come from the preceding spaceship implementation already captured in this worktree. Actual-game captures use the same seed and camera; frame timing and particles vary slightly. The gameplay fixture uses the real autopilot. The death fixture applies two damaging reports through the real hit manager and asserts caught/finished state. It does not save a leaderboard entry.

## Verification

Installed engine: `4.7.stable.official.5b4e0cb0f` (4.7.0). Graphical captures: macOS Apple M5 Max, OpenGL Compatibility.

- `ASSET A3: PASS (149811 checks)`.
- `ASSET A4: PASS (6946 checks)`, including original footprint, pause, collection/reuse, depth ordering, distinct silhouette and performance checks. Ten distinct projected silhouettes, minimum pairwise difference 56/768 samples.
- `ASSET A6: PASS (205 checks)`, including compact motion envelope, rotating propulsion, deployed claws, catch/retreat idempotence, reuse and pause.
- `RUNNER SMOKE: PASS (0 failures / 138 checks)`.
- `RUNNER VISUAL SMOKE: PASS (0 failures)`.
- `RUNNER FULL LOOP: PASS`, including menu, play, hit, pursuit, full 18-second recovery, second-hit death, results, retry, menu and hub.
- Graphical fixtures saved successfully without engine errors. Import retains the existing nested SynthCitiesGodot project warning.
- `git diff --check` passes.

Headless asset census, not a frame-rate measurement:

| Asset | Draws | Triangles |
|---|---:|---:|
| Jump barrier | 9 | 750 |
| Roll barrier | 9 | 552 |
| Each collectible | 7 idle / 8 peak | 484–708 peak |
| Hunter | 11 | 3,560 |

Hunter motion envelope is 2.221297 m wide × 1.816306 m tall, with zero textures and one shadowless light. Catch retains unit scale. Existing 14-draw pursuer and 8-draw pickup limits remain enforced. Old sculpture/wall-specific assertions were replaced with assertions for the new equipment depth, palette and hunter geometry; behavioral checks remain.

Not verified: repository-pinned Godot 4.7.1, export builds, controller play or sustained FPS profiling.

## Scope and reproduction

Changed in this pass:

- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/hazard_art.gd`
- `hoppys-adventure-arcade/scenes/runner/powerups/visuals/power_up_art.gd`
- `hoppys-adventure-arcade/scenes/runner/pursuer/pursuer_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/pursuer/dev/capture_refresh.gd`
- `hoppys-adventure-arcade/tests/assets/a4_check.gd`
- `hoppys-adventure-arcade/tests/assets/a6_check.gd`
- `hoppys-adventure-arcade/tests/runner_visual_smoke.gd`

Added: `capture_overhaul.gd` and `capture_overhaul_gameplay.gd` plus UIDs under `scenes/runner/environment/starship/`, this report and `docs/previews/overhaul/`. Other uncommitted environment, Hoppy, material, fixture and documentation changes predate this pass and remain preserved. No commits or pushes.

From repository root, use `/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade` with:

```text
--headless --script res://tests/assets/a3_check.gd --log-file /tmp/overhaul-a3.log
--headless --script res://tests/assets/a4_check.gd --log-file /tmp/overhaul-a4.log
--headless --script res://tests/assets/a6_check.gd --log-file /tmp/overhaul-a6.log
--headless --script res://tests/runner_smoke.gd --log-file /tmp/overhaul-backend.log
--headless --script res://tests/runner_visual_smoke.gd --log-file /tmp/overhaul-smoke.log
--script res://scenes/runner/environment/starship/capture_overhaul.gd --log-file /tmp/overhaul-capture.log -- --after
--script res://scenes/runner/environment/starship/capture_overhaul_gameplay.gd --log-file /tmp/overhaul-gameplay.log
--script res://scenes/runner/environment/starship/capture_overhaul_gameplay.gd --log-file /tmp/overhaul-fast.log -- --max-speed
--script res://scenes/runner/pursuer/dev/capture_refresh.gd --log-file /tmp/overhaul-hunter.log -- --after
```

Use `--after` where shown to preserve before evidence.
