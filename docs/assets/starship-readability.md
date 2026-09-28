# Starship asset readability pass

The spaceship environment is preserved. This follow-up improves the existing collision objects, pickups and Hoppy without changing collision definitions, controls, damage, movement, progression or boss behavior. Work is uncommitted on `codex/starship-assets`, based on the verified completed runner at `d64d84d`.

[Open the before/after viewer](../previews/readability/index.html). It contains 28 paired engine renders covering all 16 hazard/projectile variants, all ten pickup/tool types, a three-distance bug comparison and Hoppy's close-up. The viewer also links six actual gameplay captures.

## Visible changes

- **All hazards:** brighter diffuse metal and reduced metallic response separate solid objects from the dark deck. Outlined short labels survive the moving camera better. Bounded floor outlines identify occupied lane positions without filling the whole lane. Cleared markers change both their surface and emission to mint.
- **Bugs:** larger red shell and head geometry, pale articulated legs, larger cream eyes and red wing membranes. The friendly green wing treatment is removed. Three beetles, six legs per beetle and their existing motion remain. Enlarged parts stay inside the original 110% visual envelope.
- **Low and overhead backlog barriers:** thicker red edge bands, a continuous collision silhouette, and larger `JUMP` / `ROLL` plates. The overhead opening remains visible.
- **Pits:** thin red geometry follows the mouth perimeter, below the existing 0.0201-metre rim-height limit. The dark shaft and depth-tested opening stay intact.
- **Lasers:** brighter emitter housings and labels matching the current height: `JUMP`, `ROLL`, or `DUCK / JUMP`. Timed lasers retain `CHARGING` and show `OFF` when inactive. Beam geometry, timing and collision heights are unchanged.
- **Merge conflict, comment flood, shockwave and all four projectile shapes:** the shared diffuse material lift preserves their existing distinctive shapes and hostile colors. Shorter labels clarify the conflict and blocking forms. The low shockwave carries a jump cue.
- **All ten pickups/tools:** the sculpture material receives a neutral diffuse response and clearer inlays. Power-ups gently rock within 0.28 radians instead of rotating edge-on. Boss tools remain facing forward. Each type keeps its own silhouette, mint/orange category, hologram, ground ring, collection effect and original pickup radius.
- **Hoppy:** improved directional shading retains more orange and cream shape detail. A distance-filtered weave is limited to orange fabric. A small procedural contact shadow stays on the deck and softens with jump height. The imported model, textures, face, ears, goggles, outfit, skeleton and all animation clips are unchanged.

## Representative PNGs

- [Gameplay with visible bugs, barriers and pickup](../previews/readability/gameplay-22.png)
- [24 m/s gameplay stress view](../previews/readability/speed24-14.png)
- [Bugs before](../previews/readability/before/bugs-range.png) / [bugs after](../previews/readability/after/bugs-range.png)
- [Low barrier before](../previews/readability/before/hazard-pr_backlog_low.png) / [low barrier after](../previews/readability/after/hazard-pr_backlog_low.png)
- [Pickup before](../previews/readability/before/pickup-approve_shield.png) / [pickup after](../previews/readability/after/pickup-approve_shield.png)
- [Hoppy before](../previews/readability/before/hoppy-detail.png) / [Hoppy after](../previews/readability/after/hoppy-detail.png)
- [Cropped hazard overview](../previews/readability/hazard-overview.png) / [cropped pickup overview](../previews/readability/pickup-overview.png)

Paired views use the same 1440x900 viewport, camera, spaceship phase and object placement. Individual hazards are 12 metres ahead of the player. Bug and pickup range views use 8, 16 and 28 metres. These are staged shipping assets, not screenshots of procedural gameplay. The separate `gameplay-08/14/22/32.png` files use the actual game with seed 12345 and its existing autopilot. The `speed24-08/14.png` files use an isolated configuration copy with initial speed set to the existing 24 m/s maximum. No shipping configuration is changed.

For two fixed object regions, 90th-percentile pixel luminance increased from 0.223 to 0.436 for nearby bugs and from 0.173 to 0.476 for the low barrier. These are image-space spot measurements, not a universal accessibility score. Regions are respectively `(585,454)-(658,491)` and `(616,424)-(825,463)` in the paired 1440x900 frames, using RGB weights 0.2126/0.7152/0.0722.

## Validation

Engine: `4.7.stable.official.5b4e0cb0f`, Compatibility, OpenGL 4.1 Metal on Apple M5 Max. The repository's pinned 4.7.1 is not installed. All revised hazard and pickup families were inspected in overview sheets, along with representative full-frame before/after comparisons and gameplay captures. No script or shader errors appeared in the final graphical capture logs. Import has the existing warning about the nested SynthCitiesGodot project.

```text
ASSET A1: PASS (404 checks)
ASSET A3: PASS (163150 checks)
ASSET A4: PASS (6435 checks)
RUNNER SMOKE: PASS (0 failures / 138 checks)
RUNNER VISUAL SMOKE: PASS (0 failures)
READABILITY GAMEPLAY: time=8 save=0 state=running stage=1 speed=24.0
READABILITY GAMEPLAY: time=14 save=0 state=running stage=1 speed=24.0
```

The headless checks retain collision-envelope, animation, pause, reuse, renderer-budget and full-loop coverage. New assertions cover contact-shadow grounding and height response, front-readable pickup motion throughout the idle cycle, hostile bug colors, and friendly cleared-marker emission. Three previous style expectations were intentionally updated: green bug wings, dark bug legs and continuously spinning power-ups. No collision or budget threshold was relaxed. The shared Blender effects budget increases by exactly two triangles for the new shadow plane.

Headless resource census: Hoppy is 10 draws / 39,810 triangles / 8 textures, within its existing caps. Bug swarm is 10 draws / 5,142 triangles. Maximum hazard draw census is 14 for merge conflict; maximum hazard/projectile geometry remains the existing orb at 5,968 triangles. Pickups remain 7 idle / 8 peak draws. These are resource censuses, not GPU frame-time measurements.

Manual keyboard/controller acceptance, a desktop export and sustained frame-rate profiling were not performed. The captures show readability at the actual running camera and include a 24 m/s diagnostic run; they do not prove readability for every possible overlap or display size.

## Reproduce

From `/Users/jp/.codex/worktrees/9fa5/coderabbit-arcade`:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/runner_menu.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --log-file /tmp/readability-after.log --script res://scenes/runner/environment/starship/capture_readability.gd -- --after
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --log-file /tmp/readability-gameplay.log --script res://scenes/runner/environment/starship/capture_readability_gameplay.gd
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --log-file /tmp/readability-speed24.log --script res://scenes/runner/environment/starship/capture_readability_gameplay.gd -- --max-speed
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/readability-a1.log --script res://tests/assets/a1_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/readability-a3.log --script res://tests/assets/a3_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/readability-a4.log --script res://tests/assets/a4_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/readability-smoke.log --script res://tests/runner_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/readability-visual-smoke.log --script res://tests/runner_visual_smoke.gd
```

The saved `before/` images preserve the original comparison. Running the paired fixture without `--after` would overwrite them with whatever assets are currently installed. Use `--after` when reviewing this version.

[Exact files touched by this follow-up](starship-readability-files.txt). The earlier environment files and previews remain in place. No other worktree was modified. No commits or pushes were made.
