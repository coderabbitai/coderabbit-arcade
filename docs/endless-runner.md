# Endless Runner frontend: F0 and F1

Engine policy: the project pins Godot 4.7.1. The F0/F1 verification recorded here ran on the installed Godot 4.7.0 stable (`4.7.stable.official.5b4e0cb0f`). Final acceptance must re-run the contract §9 commands on 4.7.1; no 4.7.1 results are recorded here. Both versions are supported for development, and any behavioral differences must be recorded in contract §10.

The requested F0 and F1 source files and development scenes are present and verified as described in the renderer findings and verification sections below, with final acceptance on Godot 4.7.1 still pending. F2-F6 (Hoppy visual, hazard/power-up/pursuer visuals, HUD, pause, game over, audio, runner menu, and visual smoke test) and gameplay integration have not started.

## Run

Run from the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/renderer_spike.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/corridor_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/capture_previews.gd
```

The camera is at (0,4,8), looking at (0,1,-8), FOV 60.

| Scene | Keys | Action |
| --- | --- | --- |
| Corridor preview | 1 / 2 / 3 / 4 / 5 / 6 / 7 | 0 / 4 / 8 / 12 / 16 / 26 / 32 m/s |
| Corridor preview | P | Toggle pursuit tint |
| Corridor preview | Space | Toggle pause |
| Renderer spike | G / F / R | Toggle glow / fog / 50% or 100% 3D resolution |

Key 6 reaches the F1 26 m/s acceptance limit; key 7 exercises the Nitro cap. The capture script saves PNGs after `RenderingServer.frame_post_draw`, measures the corridor at 26 m/s with preview UI hidden, and reports failure above 15 draw calls. The coordinator produced both 1280x720 previews: [renderer spike](previews/endless-runner-spike.png) and [corridor](previews/endless-runner-corridor.png).

## What was built

F0: exact palette constants; cached immutable lit/emissive/additive material helpers and monospace labels; an original white-on-transparent 64x64 ASCII 32..95 glyph atlas; five shaders, each under 40 lines; a standalone renderer spike exercising every shader, emissive spheres, fog-depth markers, and 320 glyph particles; an asset licence inventory. Shared Environment and particle factories return independent mutable resources.

F1: tiny Corridor scene with an imperative Node3D implementation, 8x100 floor, ceiling, two code walls, 24 MultiMesh pillars, under-player glow, distant radial glow, 320 rain particles, 80 speed lines, 60 dust particles, two shadowless lights, and a WorldEnvironment. The preview includes the specified controls and camera. The smoke script instantiates, exercises, and frees the corridor and spike, then checks preview controls.

## Behavior and ownership

`set_scroll_speed(speed: float)` drives the floor/ceiling/wall scroll and recycled pillars, rain drift, and speed-line activation. Normalized speed uses the contract base 12 and max 24; speed lines begin above 0.6. The 96 m wrapping period is shared by grid, wall column seeds, and pillars. Pillars remain 8 m apart and recycle beyond z +8. Shader clocks use script time, never TIME. The corridor explicitly processes as PAUSABLE, including when mounted below an ALWAYS parent. Particle AABBs cover global z -96 through +12.

`set_pursuit(t: float)` clamps to 0..1 and tints fog, sun, and distant glow toward danger red. Both setters work before ready. The corridor sets bilinear 3D scaling to exported `retro_scale` (default 0.5), records the prior viewport scale and mode on entry. A per-viewport ownership stack preserves the remaining corridor during overlap, supports either exit order, and restores the original settings when the last owner exits. Restoration is skipped if another viewport user has changed the applied settings.

Frontend implementation files were added only under frontend-owned paths. The branch also carries backend-owned documentation commits (`docs/endless-runner-contract.md`, `docs/endless-runner-systems.md`, and `docs/agent-briefs/*`) made by the coordinator, not by the frontend agent. The frontend left `project.godot`, `app/*`, backend code, and `tests/*` unchanged. The frontend agent performed no external asset downloads, commits, pushes, or stashes.

## Art direction and replacement points

The navy environment and dim MATRIX grid/rain reuse the hub preview palette and perspective motif. Lanes are centered at x -2/0/+2, bounded by lines at x +/-1 and +/-3. Hazards and power-ups are not part of this milestone. Material cache results must be duplicated before mutation.

| Visual | Source | Licence |
| --- | --- | --- |
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
| Previews | 1280x720 PNGs | Present: docs/previews/endless-runner-spike.png and docs/previews/endless-runner-corridor.png. |

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

## Requests to backend

None for F0/F1. Mount Corridor under the contract PAUSABLE World and call its contract setters as planned. Backend base scripts and facade integration remain prerequisites for F2 through F6, not dependencies of these fixtures.

## Known gaps

No remaining F0/F1 renderer or preview gaps are reported by the coordinator on 4.7.0; final acceptance on the pinned 4.7.1 remains pending. Gameplay integration, F2-F6 visual smoke, runner audio, hazard/player visuals, and menus remain outside this run's scope. F2 has not started.

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
