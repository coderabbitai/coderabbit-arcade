# Endless Runner frontend: F0, F1, and F2

Engine policy: the project pins Godot 4.7.1. The F0/F1 verification recorded here ran on the installed Godot 4.7.0 stable (`4.7.stable.official.5b4e0cb0f`). Final acceptance must re-run the contract §9 commands on 4.7.1; no 4.7.1 results are recorded here. Both versions are supported for development, and any behavioral differences must be recorded in contract §10.

The requested F0 and F1 source files and development scenes are present and verified as described in the renderer findings and verification sections below, with final acceptance on Godot 4.7.1 still pending. F2 now adds Hoppy, its preview, and the first visual smoke test. The backend mounts Hoppy and the corridor automatically. F3-F6 remain deferred.

## Run

Run from the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/renderer_spike.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/corridor_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/player/dev/hoppy_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/capture_previews.gd
```

The camera is at (0,4,8), looking at (0,1,-8), FOV 60.

| Scene | Keys | Action |
| --- | --- | --- |
| Hoppy preview | 1-7 / Space | Select idle, run, jump, fall, roll, hurt, dead / cycle |
| Hoppy preview | [ / ] / A / D | Decrease or increase normalized speed / hold lane lean |
| Hoppy preview | L / N / C / S / H | Toggle LGTM / Nitro / Code Review / shield / hit flash |
| Corridor preview | 1 / 2 / 3 / 4 / 5 / 6 / 7 | 0 / 4 / 8 / 12 / 16 / 26 / 32 m/s |
| Corridor preview | P | Toggle pursuit tint |
| Corridor preview | Space | Toggle pause |
| Renderer spike | G / F / R | Toggle glow / fog / 50% or 100% 3D resolution |

Key 6 reaches the F1 26 m/s acceptance limit; key 7 exercises the Nitro cap. The capture script saves PNGs after `RenderingServer.frame_post_draw`, measures the corridor at 26 m/s with preview UI hidden, and reports failure above 15 draw calls. The capture script also saves the Hoppy fixture after 1.5 s to `docs/previews/endless-runner-hoppy.png`. The coordinator produced the 1280x720 environment previews: [renderer spike](previews/endless-runner-spike.png) and [corridor](previews/endless-runner-corridor.png).

## What was built

F0: exact palette constants; cached immutable lit/emissive/additive material helpers and monospace labels; an original white-on-transparent 64x64 ASCII 32..95 glyph atlas; five shaders, each under 40 lines; a standalone renderer spike exercising every shader, emissive spheres, fog-depth markers, and 320 glyph particles; an asset licence inventory. Shared Environment and particle factories return independent mutable resources.

F1: tiny Corridor scene with an imperative Node3D implementation, 8x100 floor, ceiling, two code walls, 24 MultiMesh pillars, under-player glow, distant radial glow, 320 rain particles, 80 speed lines, 60 dust particles, two shadowless lights, and a WorldEnvironment. The preview includes the specified controls and camera. The smoke script instantiates, exercises, and frees the corridor and spike, then checks preview controls.

F2: original primitive cream rabbit with an orange hoodie, rear code logo, forehead goggles, pink ear inserts, and seven code-built animations. The development scene is `res://scenes/runner/player/dev/hoppy_preview.tscn`. The coordinator captured the [1280x720 Hoppy preview](previews/endless-runner-hoppy.png) on the host with a small SceneTree capture script, showing Hoppy back-facing in the corridor.

## Behavior and ownership

Hoppy extends the backend visual base and implements all six contract methods. It faces -Z with standing mesh bounds y 0..1.8. `AnimationPlayer` drives the feet pivot `Root` and `Root/Model`; scene-root yaw and bank implement lane lean independently. Every clip supplies rest tracks to clear previous held poses. Run cadence is `lerp(0.85, 1.9, normalized)`, including values above 1; other clips retain real-time duration. Hurt flashes at 0.001/0.12/0.24 s, then returns to the preceding idle/run state unless another state interrupts it. Hit flashes clear after 0.06 s without mutating shared materials. Effects and animation inherit PAUSABLE behavior.

Roll enters immediately, holds its tucked pose after the 0.5 s somersault, and waits for the backend state change. A centered model, folded ears, 0.95 model scale, and Root scale (0.5, 0.55, 0.5) keep sampled bounds inside y 0..0.9. This adds centering and tucking to the brief's insufficient standalone 0.55 vertical scale. Aura is parented under Root, with standing center y 0.9 and radius 0.9; roll centers it at the pivot and scales it to 0.6 to stay within the tuck throughout rotation. Aura kinds are tracked independently with LGTM, Nitro, then Code Review display priority; expiring one preserves another. Shield is independent and preserves requests made before ready. No collision, gameplay timing, or backend files are changed.

`set_scroll_speed(speed: float)` drives the floor/ceiling/wall scroll and recycled pillars, rain drift, and speed-line activation. Normalized speed uses the contract base 12 and max 24; speed lines begin above 0.6. The 96 m wrapping period is shared by grid, wall column seeds, and pillars. Pillars remain 8 m apart and recycle beyond z +8. Shader clocks use script time, never TIME. The corridor explicitly processes as PAUSABLE, including when mounted below an ALWAYS parent. Particle AABBs cover global z -96 through +12.

`set_pursuit(t: float)` clamps to 0..1 and tints fog, sun, and distant glow toward danger red. Both setters work before ready. The corridor sets bilinear 3D scaling to exported `retro_scale` (default 0.5), records the prior viewport scale and mode on entry. A per-viewport ownership stack preserves the remaining corridor during overlap, supports either exit order, and restores the original settings when the last owner exits. Restoration is skipped if another viewport user has changed the applied settings.

Frontend implementation files were added only under frontend-owned paths. The branch also carries backend-owned documentation commits (`docs/endless-runner-contract.md`, `docs/endless-runner-systems.md`, and `docs/agent-briefs/*`) made by the coordinator, not by the frontend agent. The frontend left `project.godot`, `app/*`, backend code, and tests other than its owned `tests/runner_visual_smoke.gd` unchanged. The frontend agent performed no external asset downloads, commits, pushes, or stashes.

## Art direction and replacement points

The navy environment and dim MATRIX grid/rain reuse the hub preview palette and perspective motif. Lanes are centered at x -2/0/+2, bounded by lines at x +/-1 and +/-3. Hazards and power-ups are not part of this milestone. Material cache results must be duplicated before mutation.

| Visual | Source | Licence |
| --- | --- | --- |
| Hoppy primitives, animations, and effects | scenes/runner/player/hoppy_runner_visual.gd; original project source. To swap the model, replace `_build_model()` under `Root/Model`, retain the feet origin, -Z facing and 1.8 m height, remap `_pose_clip()` tracks to the new rig, and preserve the scene root, six hooks, effects, and animation names. Re-run the smoke bounds checks and host preview, including the 0.9 m roll. | Original project source |
| Corridor primitives and particles | scenes/runner/environment/corridor.gd | Original project source |
| Glyph atlas | scenes/runner/shaders/glyph_atlas.gd | Original project source |
| Grid, wall, hologram, radial glow, vignette | scenes/runner/shaders/*.gdshader | Original project source |
| Labels | SystemFont fallback matching menu_style.gd | Installed font licences; no font redistribution |

See `hoppys-adventure-arcade/Assets/runner/LICENSES.md` for the asset inventory.

## Audio

Deferred to F5. Procedural AudioStreamWAV SFX are planned. The CC0 `res://Assets/cyberpunk-street-files/Assets/music/cyberpunk-street.ogg` is the music candidate specified by the brief; its package licence and composer caveat must be reviewed and recorded in LICENSES.md before use. F0/F1 add no runner audio. The existing project autoload starts the hub track during dev runs.

## Renderer findings: gl_compatibility

The following gl_compatibility findings come from the coordinator's graphical capture and visual inspection on the installed Godot 4.7.0 stable (`4.7.stable.official.5b4e0cb0f`). They supersede the earlier headless-only findings. The project pins 4.7.1, where final acceptance must be re-run under the contract's engine version policy.

| Feature | Configuration | Observed result |
| --- | --- | --- |
| Glow | enabled; intensity 0.9, bloom 0.12, HDR threshold 0.75, HDR scale 2.0 | OK: bloom is visible on emissive objects in the spike. |
| Fog | depth mode, begin 22, end 88, NAVY_BG | OK: depth fog is visible. |
| scaling_3d_scale | bilinear, 0.5 | OK: the retro downscale is visible; ownership and restoration are covered by the environment check. |
| Particles | GPUParticles3D, 8x8 glyph billboard atlas, no trails/collision/subemitters | OK: glyph rain is visible. Pause inheritance is covered headlessly. |
| Draw budget | two lights, shadows off; measured at 26 m/s with preview UI hidden | PASS: 10 / 15 corridor draw calls. Capture frames reported spike 23 and corridor 9; the spike is a separate diagnostic fixture. |
| Previews | 1280x720 PNGs | Present: docs/previews/endless-runner-spike.png, docs/previews/endless-runner-corridor.png, and docs/previews/endless-runner-hoppy.png. |

The shaders provide their own grid/wall depth fading and additive halos. Unsupported renderer effects are not configured. The implementation avoids the Compatibility-ignored glow-level/normalized/strength/blend settings specified in the brief.

## Verification

The coordinator ran the following plain commands from the repository root on the host using Godot 4.7.0 stable:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://<file> --check-only
```

| `<file>` | Exit code | Output |
| --- | --- | --- |
| `scenes/runner/environment/runner_palette.gd` | 0 | Engine banner only; no diagnostics |
| `scenes/runner/environment/runner_materials.gd` | 0 | Engine banner only; no diagnostics |
| `scenes/runner/shaders/glyph_atlas.gd` | 0 | Engine banner only; no diagnostics |
| `scenes/runner/environment/corridor.gd` | 0 | Engine banner only; no diagnostics |
| `scenes/runner/environment/dev/renderer_spike.gd` | 0 | Engine banner only; no diagnostics |
| `scenes/runner/environment/dev/corridor_preview.gd` | 0 | Engine banner only; no diagnostics |
| `scenes/runner/environment/dev/environment_check.gd` | 0 | Engine banner only; no diagnostics |
| `scenes/runner/environment/dev/capture_previews.gd` | 0 | Engine banner only; no diagnostics |

The sole output line for each check was:

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org
```

The coordinator recorded this graphical capture output verbatim:

```text
SPIKE: renderer=gl_compatibility scale=0.5 glow_threshold=0.75 fog=22..88 particles=320
CAPTURE: spike error=0 draw_calls=23
CAPTURE: corridor error=0 draw_calls=9
CORRIDOR DRAW BUDGET: 10 / 15 (preview UI hidden)
PREVIEW CAPTURE: PASS
```

The follow-up environment check covers scene loads, speed samples through 32 m/s, wrapping, pause, all seven speed keys, pursuit, camera, overlapping corridor exit orders with different scales, restoration of a non-default baseline, and preservation of an external scaling change. The coordinator's plain host run of `environment_check.gd` on the same engine exited 0 and printed these result lines:

```text
SPIKE: renderer=gl_compatibility scale=0.5 glow_threshold=0.75 fog=22..88 particles=320
ENV CHECK: PASS (0 failures)
```

Earlier sandbox runs reportedly required `--log-file /tmp/...` because plain Godot runs crashed when writing `user://logs`; their output and exit codes are not verified here. Separate results from the two validators are not verified because their output is not recorded here. Results on the pinned Godot 4.7.1 are not verified.

### F2 verification (2026-09-19)

All commands ran from the repository root with `/Applications/Godot.app/Contents/MacOS/Godot` on 4.7.0. Codex performed no downloads, graphical Godot runs, commits, or pushes. The coordinator ran graphical Godot on the host and captured the Hoppy preview linked above. Import exited 0 but emitted sandbox certificate and editor-settings diagnostics. A plain smoke launch crashed opening `user://logs`; runtime commands were retried with `--log-file /tmp/...`. The certificate diagnostic occurs before SceneTree initialization. The smoke installs an OS Logger before runtime resource loads and counts every subsequent engine/script/shader error, including `push_error`, as a failure. No runtime errors were captured.

The smoke checks every method and state, speed 0/0.5/1.2, lean -1/0/1, all aura on/off pairs and overlapping expiry, shield on/off and pre-ready requests, hit-flash cleanup, all three standalone hurt pulses, hurt recovery and interruption, standing dimensions, 61 roll poses including Aura and a merged all-mesh mid-roll AABB check (min.y >= -0.02, max.y <= 0.95), cleanup, preview load and keyboard dispatch, and the camera offset. Headless checks do not establish rendered appearance.

Validator follow-up: re-ran headless import, check-only for `hoppy_runner_visual.gd` and `capture_previews.gd`, the extended visual smoke, and the environment check on installed Godot 4.7.0. All exited 0; both runtime checks reported PASS with 0 failures. Import and runtime startup retain the sandbox diagnostics described above. The coordinator PNG was preserved; the new capture fixture was syntax-checked without a graphical run.

Outputs below preserve command output text with terminal color escape sequences removed.

`--headless --path hoppys-adventure-arcade --import --quit --log-file /tmp/hoppy-import-final.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
[   0% ] first_scan_filesystem | Started Project initialization (5 steps)
[   0% ] first_scan_filesystem | Scanning file structure...
WARNING: Detected another project.godot at res://Assets/SynthCitiesGodot. The folder will be ignored.
     at: _should_skip_directory (editor/file_system/editor_file_system.cpp:3485)
[  16% ] first_scan_filesystem | Loading global class names...
[  33% ] first_scan_filesystem | Verifying GDExtensions...
[  50% ] first_scan_filesystem | Creating autoload scripts...
[  66% ] first_scan_filesystem | Initializing plugins...
[  83% ] first_scan_filesystem | Starting file scan...
[ DONE ] first_scan_filesystem

[   0% ] loading_editor_layout | Started Loading editor (5 steps)
[   0% ] loading_editor_layout | Loading editor layout...
[  16% ] loading_editor_layout | Loading docks...
[ DONE ] loading_editor_layout

ERROR: Cannot save file '/Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres'.
   at: save (scene/resources/resource_format_text.cpp:1768)
ERROR: Error saving editor settings to /Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres
   at: save (editor/settings/editor_settings.cpp:1525)
```

`--headless --path hoppys-adventure-arcade --script res://scenes/runner/player/hoppy_runner_visual.gd --check-only --log-file /tmp/hoppy-check-0.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`--headless --path hoppys-adventure-arcade --script res://scenes/runner/player/dev/hoppy_preview.gd --check-only --log-file /tmp/hoppy-check-1.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`--headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd --check-only --log-file /tmp/hoppy-check-2.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`--headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd --log-file /tmp/hoppy-smoke-engine.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
RUNNER VISUAL SMOKE: PASS (0 failures)
```

`--headless --path hoppys-adventure-arcade --script res://tests/runner_scaffold_check.gd --log-file /tmp/hoppy-scaffold-engine.log` (exit 1):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
ERROR: RUNNER SCAFFOLD: missing node: World/GrayboxEnvironment
   at: push_error (core/variant/variant_utility.cpp:1023)
   GDScript backtrace (most recent call first):
       [0] check (res://tests/runner_scaffold_check.gd:92)
       [1] run (res://tests/runner_scaffold_check.gd:120)
RUNNER SCAFFOLD: FAIL (1 failures / 276 checks)
```

`--headless --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/environment_check.gd --log-file /tmp/hoppy-env-engine.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
SPIKE: renderer=gl_compatibility scale=0.5 glow_threshold=0.75 fog=22..88 particles=320
ENV CHECK: PASS (0 failures)
```

## Requests to backend

No new backend requests. Apply the already planned PR 2 scaffold assertion change: `World/GrayboxEnvironment` is intentionally absent when the frontend corridor mounts. The F2 scaffold check reports exactly that one known failure.

## Known gaps

No remaining F0/F1 renderer or preview gaps are reported by the coordinator on 4.7.0; final acceptance on the pinned 4.7.1 remains pending. F2 headless checks are complete. The coordinator ran graphical Godot on the host and captured Hoppy back-facing in the corridor; Codex itself did not run graphical Godot. F3-F6, runner audio, hazard visuals, and menus remain outside this run's scope.

## Touched files

All added files, relative to the repository root:

- `hoppys-adventure-arcade/Assets/runner/LICENSES.md`
- `hoppys-adventure-arcade/scenes/runner/environment/corridor.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/corridor.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/corridor.tscn`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/capture_previews.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/capture_previews.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/corridor_preview.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/corridor_preview.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/corridor_preview.tscn`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/environment_check.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/environment_check.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/renderer_spike.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/renderer_spike.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/dev/renderer_spike.tscn`
- `hoppys-adventure-arcade/scenes/runner/environment/runner_materials.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/runner_materials.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/environment/runner_palette.gd`
- `hoppys-adventure-arcade/scenes/runner/environment/runner_palette.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/shaders/code_wall.gdshader`
- `hoppys-adventure-arcade/scenes/runner/shaders/code_wall.gdshader.uid`
- `hoppys-adventure-arcade/scenes/runner/shaders/far_glow.gdshader`
- `hoppys-adventure-arcade/scenes/runner/shaders/far_glow.gdshader.uid`
- `hoppys-adventure-arcade/scenes/runner/shaders/floor_grid.gdshader`
- `hoppys-adventure-arcade/scenes/runner/shaders/floor_grid.gdshader.uid`
- `hoppys-adventure-arcade/scenes/runner/shaders/glyph_atlas.gd`
- `hoppys-adventure-arcade/scenes/runner/shaders/glyph_atlas.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/shaders/hologram.gdshader`
- `hoppys-adventure-arcade/scenes/runner/shaders/hologram.gdshader.uid`
- `hoppys-adventure-arcade/scenes/runner/shaders/vignette.gdshader`
- `hoppys-adventure-arcade/scenes/runner/shaders/vignette.gdshader.uid`
- `docs/endless-runner.md`

F2 additions:

- `docs/previews/endless-runner-hoppy.png` (captured by the coordinator)

- `hoppys-adventure-arcade/scenes/runner/player/hoppy_runner_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/player/hoppy_runner_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/player/hoppy_runner_visual.tscn`
- `hoppys-adventure-arcade/scenes/runner/player/dev/hoppy_preview.gd`
- `hoppys-adventure-arcade/scenes/runner/player/dev/hoppy_preview.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/player/dev/hoppy_preview.tscn`
- `hoppys-adventure-arcade/tests/runner_visual_smoke.gd`
- `hoppys-adventure-arcade/tests/runner_visual_smoke.gd.uid`
- Updated `hoppys-adventure-arcade/scenes/runner/environment/dev/capture_previews.gd` with the Hoppy fixture.
- Updated this document.
