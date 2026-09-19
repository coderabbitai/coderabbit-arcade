# Endless Runner frontend: F0-F3

Engine policy: the project pins Godot 4.7.1. The F0/F1 verification recorded here ran on the installed Godot 4.7.0 stable (`4.7.stable.official.5b4e0cb0f`). Final acceptance must re-run the contract §9 commands on 4.7.1; no 4.7.1 results are recorded here. Both versions are supported for development, and any behavioral differences must be recorded in contract §10.

The requested F0 and F1 source files and development scenes are present and verified as described in the renderer findings and verification sections below, with final acceptance on Godot 4.7.1 still pending. F2 now adds Hoppy, its preview, and the first visual smoke test. The backend mounts Hoppy and the corridor automatically. F3 is complete: hazards, power-ups and the pursuer are implemented and verified. F4-F6 remain deferred.

## Run

Run from the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/renderer_spike.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/corridor_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/player/dev/hoppy_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/hazards/visuals/dev/hazard_gallery.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/capture_previews.gd
```

The camera is at (0,4,8), looking at (0,1,-8), FOV 60.

| Scene | Keys | Action |
| --- | --- | --- |
| Hazard gallery | Left / Right | Move the contract camera through 19 fixtures (12 hazards, six pickups, pursuer) |
| Hazard gallery | H / C / R | Hit / clear hazards / reset all visuals |
| Hazard gallery | P / K / B | Collect pickups / catch / retreat |
| Hazard gallery | [ / ] or slider | Decrease / increase pursuer threat; slider spans 0..1 |
| Hazard gallery | Space | Pause or resume motion and particles |
| Hazard gallery | T / 1 / 2 / 3 | Toggle telegraph sweep / ground / high / off |
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

F3a hazard-only historical run: eight scene/script pairs extend the backend visual base directly and use `hazard_art.gd` for common primitives, bounded delta-driven animation, floor projections, and reactions. That gallery included 12 fixtures covering every kind and variant, a wireframe hitbox per fixture, and camera navigation along the corridor. The historical host capture reported `CAPTURE: gallery error=0 draw_calls=106`, below its 183-call budget. The current [19-fixture gallery](previews/endless-runner-gallery.png) includes the F3b additions.

Hero text uses the shared cream monospace label helper with navy outlines; tiny decorative labels omit outlines and per-card text is removed. Repeated boxes use material-grouped MultiMeshes with animated instance transforms. Glyph clouds use one pausable GPUParticles3D per applicable hazard, the shared 8x8 billboard atlas, a hitbox-sized visibility AABB, bounded lifetime trajectories, and no trails, collision, or sub-emitters. Headless checks verify configuration and bounds; GPU appearance requires host capture. Hit flashes and Auto-Fix mint reactions restore on spawn, including labels, geometry, clocks, beam state, scanner visibility, and per-instance materials.

The backend calls `_ready()` before assigning base vars. Each root attempts construction in `_ready()` and waits if the hitbox is zero; `on_spawned()` builds from the supplied vars. Repeated spawn calls hide and rename the old artwork, queue its deletion, and build the replacement as Artwork, including after hits and clears. No shared materials are mutated.

Bounds clarification for backend: floor-marker projections at y=0 cannot be enclosed in elevated collision volumes (high backlog and lasers). The smoke therefore checks the merged visible body AABB, including labels and glyph particles, against the contract hitbox_offset and 110% hitbox envelope, then verifies the exact floor-marker footprint and prescribed color/alpha separately. The high-backlog safe-gap quad uses full width and 60% depth. Cleared markers turn MINT at alpha 0.35; spawn restores DANGER. The hanging rail is at y=2.963 for the authoritative hitbox, just below the brief's rounded 3.0 m so it fits the 110% envelope. Timed laser geometry snaps between the contract ground and high volumes; its scanner sweeps only within the current volume. Full-height posts would contradict the laser bounds, so posts are confined to the beam height. The backend's timed state machine is still a PR 2 stub; the gallery drives the public hooks directly.

F3 completion: all six pickup roots extend the backend power-up base directly. `on_spawned()` calls the base `show()` first, builds only after `kind` is assigned, and resets the existing artwork without accumulating nodes. The Pivot spins at 1.6 rad/s and bobs ±0.08 m around the pickup root. Tags sit at y +0.75 and billboard toward the camera. The 0.25 s collection scales 1 → 1.45 → 0, expands/fades the ring, bursts the halo and hides the root. Repeated collection calls do not restart the reaction; spawning interrupts it and restores materials, particles, transforms and visibility. Pickup collision remains the backend's root-centered r 0.35 sphere.

The pursuer renders 20 cards with per-instance NAVY-to-DANGER color interpolated by threat squared. Threat drives Wall height, forward lean, jitter, headline flicker, particle amount and the sole extra light (range 6, energy 0..2.5). Catch is a delta-driven 1.4 s eased lunge toward the camera with ×2.6 scale, CAUGHT headlines and energy 6; retreat topples and shrinks over 0.7 s, turns the light off and hides. The normal threat-1 visible bounds include cards, labels, eyes, particle bounds and haze; catch deliberately exceeds the normal gameplay envelope. All animation clocks accumulate delta and inherit pause. No backend files were changed.

The gallery includes wire spheres at the exact pickup roots and contract camera placement for the pursuer, including z 12..4.5 relative to the implied player. Its corridor moves with the selected fixture so the later fixtures retain a floor and lighting. The coordinator captured [six pickups in the lanes](previews/endless-runner-powerups.png) and the [pursuer at threat 1](previews/endless-runner-pursuer.png). Gallery controls include Right, P, K, B and the threat slider; Codex did not attempt graphical runs.

The explicit leftover fix adds CPU pillar-z storage and a copy-returning accessor on the frontend corridor. `environment_check.gd` now checks all 24 stored positions against their wrap bounds and the expected post-wrap positions, without reading headless MultiMesh transforms.

## Behavior and ownership

Hoppy extends the backend visual base and implements all six contract methods. It faces -Z with standing mesh bounds y 0..1.8. `AnimationPlayer` drives the feet pivot `Root` and `Root/Model`; scene-root yaw and bank implement lane lean independently. Every clip supplies rest tracks to clear previous held poses. Run cadence is `lerp(0.85, 1.9, normalized)`, including values above 1; other clips retain real-time duration. Hurt flashes at 0.001/0.12/0.24 s, then returns to the preceding idle/run state unless another state interrupts it. Hit flashes clear after 0.06 s without mutating shared materials. Effects and animation inherit PAUSABLE behavior.

Roll enters immediately, holds its tucked pose after the 0.5 s somersault, and waits for the backend state change. A centered model, folded ears, 0.95 model scale, and Root scale (0.5, 0.55, 0.5) keep sampled bounds inside y 0..0.9. This adds centering and tucking to the brief's insufficient standalone 0.55 vertical scale. Aura is parented under Root, with standing center y 0.9 and radius 0.9; roll centers it at the pivot and scales it to 0.6 to stay within the tuck throughout rotation. Aura kinds are tracked independently with LGTM, Nitro, then Code Review display priority; expiring one preserves another. Shield is independent and preserves requests made before ready. No collision, gameplay timing, or backend files are changed.

`set_scroll_speed(speed: float)` drives the floor/ceiling/wall scroll and recycled pillars, rain drift, and speed-line activation. Normalized speed uses the contract base 12 and max 24; speed lines begin above 0.6. The 96 m wrapping period is shared by grid, wall column seeds, and pillars. Pillars remain 8 m apart and recycle beyond z +8. Shader clocks use script time, never TIME. The corridor explicitly processes as PAUSABLE, including when mounted below an ALWAYS parent. Particle AABBs cover global z -96 through +12.

`set_pursuit(t: float)` clamps to 0..1 and tints fog, sun, and distant glow toward danger red. Both setters work before ready. The corridor sets bilinear 3D scaling to exported `retro_scale` (default 0.5), records the prior viewport scale and mode on entry. A per-viewport ownership stack preserves the remaining corridor during overlap, supports either exit order, and restores the original settings when the last owner exits. Restoration is skipped if another viewport user has changed the applied settings.

Frontend implementation files were added only under frontend-owned paths. The branch also carries backend-owned documentation commits (`docs/endless-runner-contract.md`, `docs/endless-runner-systems.md`, and `docs/agent-briefs/*`) made by the coordinator, not by the frontend agent. The frontend left `project.godot`, `app/*`, backend code, and tests other than its owned `tests/runner_visual_smoke.gd` unchanged. The frontend agent performed no external asset downloads, commits, pushes, or stashes.

## Art direction and replacement points

The navy environment and dim MATRIX grid/rain reuse the hub preview palette and perspective motif. Lanes are centered at x -2/0/+2, bounded by lines at x +/-1 and +/-3. F3 hazards use hot DANGER/ORANGE accents; power-ups use MINT icons, rings, sparkles and billboard tags. The pursuer uses NAVY cards turning DANGER with threat. Material cache results must be duplicated before mutation.

| Visual | Source | Licence |
| --- | --- | --- |
| Hoppy primitives, animations, and effects | scenes/runner/player/hoppy_runner_visual.gd; original project source. To swap the model, replace `_build_model()` under `Root/Model`, retain the feet origin, -Z facing and 1.8 m height, remap `_pose_clip()` tracks to the new rig, and preserve the scene root, six hooks, effects, and animation names. Re-run the smoke bounds checks and host preview, including the 0.9 m roll. | Original project source |
| pr_backlog_low | `scenes/runner/hazards/visuals/pr_backlog_low_visual.gd` + shared `hazard_art.gd`: Three rows of navy PR cards, orange/red strips, wobble, hit scatter/fade and mint shrink; AUTO-FIXED. | Original project source |
| pr_backlog_high | `scenes/runner/hazards/visuals/pr_backlog_high_visual.gd` + shared `hazard_art.gd`: Rail and hanging stale/CI cards, sway, hit drop/bounce, mint shrink; exact red footprint plus inset green safe-gap quad. | Original project source |
| bug_swarm | `scenes/runner/hazards/visuals/bug_swarm_visual.gd` + shared `hazard_art.gd`: Red core, six legs, 36 atlas glyph particles, leg jitter and core pop; throw new Error(). | Original project source |
| merge_conflict | `scenes/runner/hazards/visuals/merge_conflict_visual.gd` + shared `hazard_art.gd`: HEAD and feature slabs, matrix/lilac strips, pulsing zigzag seam, shake and merged mint box; MERGED. | Original project source |
| deprecated_pit | `scenes/runner/hazards/visuals/deprecated_pit_visual.gd` + shared `hazard_art.gd`: Full and two_lane widths, dark floor, striped rim, falling glyphs, flat deprecated/since labels, rim flash and REMOVED. | Original project source |
| laser_grid | `scenes/runner/hazards/visuals/laser_grid_visual.gd` + shared `hazard_art.gd`: Ground, mid, high and timed; short posts/caps, three additive beams, bounded mint scanner, hit sparks and beam retraction; SCAN PASSED. | Original project source |
| comment_flood | `scenes/runner/hazards/visuals/comment_flood_visual.gd` + shared `hazard_art.gd`: Scrolling speech cards, red translucent volume, burst/fade and fold; one BLOCKING // TODO hero label, RESOLVED. | Original project source |
| build_shockwave | `scenes/runner/hazards/visuals/build_shockwave_visual.gd` + shared `hazard_art.gd`: Elliptical flat torus, red core and shards, ring pulse, white impact and mint fixed reaction; BUILD FIXED. | Original project source |
| approve_shield | `scenes/runner/powerups/visuals/approve_shield_visual.gd` + shared `power_up_art.gd`: Hexagonal mint shield and cream check; APPROVED. | Original project source |
| auto_fix | `scenes/runner/powerups/visuals/auto_fix_visual.gd` + shared `power_up_art.gd`: Mint wrench and cream bolt; AUTO-FIX. | Original project source |
| lgtm | `scenes/runner/powerups/visuals/lgtm_visual.gd` + shared `power_up_art.gd`: Emissive LGTM TextMesh; 5s. | Original project source |
| nitro | `scenes/runner/powerups/visuals/nitro_visual.gd` + shared `power_up_art.gd`: Capsule commit, cream plus, mint flame stream; NITRO COMMIT. | Original project source |
| super_jump | `scenes/runner/powerups/visuals/super_jump_visual.gd` + shared `power_up_art.gd`: Mint coin and cream ^^; SUPER JUMP. | Original project source |
| code_review | `scenes/runner/powerups/visuals/code_review_visual.gd` + shared `power_up_art.gd`: Mint magnifier and cream handle; CODE REVIEW ×1.5. | Original project source |
| Power-up tags (all six) | Shared `power_up_art.gd`: tags are approximately 0.2 m tall and up to 1.3 m wide, extend beyond the r 0.35 pickup sphere by design, and stay inside the 2 m lane pitch. | Original project source |
| Unreviewed PR Backlog pursuer | `scenes/runner/pursuer/pursuer_visual.gd`: 5×4 MultiMesh cards, six cream headlines, two angry eye slits, one red light, glyph glitch particles and radial haze; threat, catch and retreat hooks. Headlines retain `label.scale.x = 0.65` (compressed to 65% width); the pixel-size increase applies to height only. The coordinator's host capture confirms legibility. | Original project source |
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
| Previews | 1280x720 PNGs | Present: docs/previews/endless-runner-spike.png, docs/previews/endless-runner-corridor.png, docs/previews/endless-runner-hoppy.png, docs/previews/endless-runner-gallery.png, docs/previews/endless-runner-powerups.png, and docs/previews/endless-runner-pursuer.png. |

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

Validator follow-up: re-ran headless import, check-only for `hoppy_runner_visual.gd` and `capture_previews.gd`, the extended visual smoke, and the environment check on installed Godot 4.7.0. All exited 0; both runtime checks reported PASS with 0 failures. Import and runtime startup retain the sandbox diagnostics described above. The coordinator subsequently ran the capture_previews.gd Hoppy fixture graphically on the host (CAPTURE: hoppy error=0 draw_calls=33) and refreshed all three preview PNGs. Codex did not perform a graphical run.

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

`--headless --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/capture_previews.gd --check-only --log-file /tmp/hoppy-capture-check.log` (exit 0):

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

### F3 contract 1.2 feedback verification

All commands below ran headlessly from the repository root and exited 0. Output is verbatim with terminal ANSI styling and trailing spaces removed. Startup certificate and editor-settings diagnostics are preserved. All 11 check-only invocations passed. The smoke explicitly awaited all 12 hazard cases before audio shutdown and exit.

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --import --quit --log-file /tmp/f3-import.log`

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

[   0% ] update_scripts_classes | Started Registering global classes... (2 steps)
[   0% ] update_scripts_classes |
[  33% ] update_scripts_classes |
[ DONE ] update_scripts_classes

[   0% ] loading_editor_layout | Started Loading editor (5 steps)
[   0% ] loading_editor_layout | Loading editor layout...
[  16% ] loading_editor_layout | Loading docks...
[ DONE ] loading_editor_layout

ERROR: Cannot save file '/Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres'.
   at: save (scene/resources/resource_format_text.cpp:1768)
ERROR: Error saving editor settings to /Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres
   at: save (editor/settings/editor_settings.cpp:1525)
```

```text
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/hazard_art.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/bug_swarm_visual.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/build_shockwave_visual.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/comment_flood_visual.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/deprecated_pit_visual.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/laser_grid_visual.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/merge_conflict_visual.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/pr_backlog_high_visual.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/pr_backlog_low_visual.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/dev/hazard_gallery.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://tests/runner_visual_smoke.gd --log-file /tmp/f3-check-engine.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

exit=0
```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd --log-file /tmp/f3-smoke.log`

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
HAZARD DRAW CENSUS: pr_backlog_low/ peak=6
HAZARD DRAW CENSUS: pr_backlog_high/ peak=8
HAZARD DRAW CENSUS: bug_swarm/ peak=6
HAZARD DRAW CENSUS: merge_conflict/ peak=9
HAZARD DRAW CENSUS: deprecated_pit/full peak=8
HAZARD DRAW CENSUS: deprecated_pit/two_lane peak=8
HAZARD DRAW CENSUS: laser_grid/ground peak=8
HAZARD DRAW CENSUS: laser_grid/mid peak=8
HAZARD DRAW CENSUS: laser_grid/high peak=8
HAZARD DRAW CENSUS: laser_grid/timed peak=8
HAZARD DRAW CENSUS: comment_flood/ peak=7
HAZARD DRAW CENSUS: build_shockwave/ peak=6
HAZARD CASES CHECKED: 12; summed peak draw census=90
RUNNER VISUAL SMOKE: PASS (0 failures)
```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/environment_check.gd --log-file /tmp/f3-environment.log`

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
SPIKE: renderer=gl_compatibility scale=0.5 glow_threshold=0.75 fog=22..88 particles=320
ENV CHECK: PASS (0 failures)
```

### F3 hazard verification (2026-09-19)

F3 added eight hazard visual scenes and their scripts plus shared artwork and a gallery. Headless validation passed from the repository root on installed Godot 4.7.0. The coordinator performed the host graphical gallery capture. The frontend agent performed no graphical runs, downloads, commits, or pushes. The import uses `--quit` to finish the headless editor and `/tmp` log paths to avoid the known sandbox log-directory crash. Import and runtime startup retain the existing certificate/editor-settings diagnostics. The runtime smoke logger reported zero subsequent engine errors. Scaffold reports exactly the known GrayboxEnvironment failure.

The smoke covers all 12 contract cases, both backend vars-after-ready and fixture vars-before-ready ordering, all five hooks, 61 idle/hit/cleared animation samples each, visible meshes plus labels and glyph particles, floor footprint/color, approved safe-gap color, repeated spawn after reactions, text/color/material reset, node-count stability, pause, timed beam elevation/visibility, telegraph samples, gallery load, keys, and camera. Elevated floor projections are checked separately as explained above. The historical F3a hazard-only host capture after batching reports `CAPTURE: gallery error=0 draw_calls=106`. Expected new hazard-only census: 85 idle across all 12 fixtures, at most 90 summed tested peaks (6 to 9 per case). The node census is an estimate (outlined Label3D counts as 2, MultiMesh as 1), not an exact renderer total. The capture script independently fails PREVIEW CAPTURE above (Gallery.CASES.size() + Gallery.POWERUPS.size() + 1 pursuer) x 14 + 15 = (12 + 6 + 1) x 14 + 15 = 281 gallery draw calls, deriving fixture counts from `hazard_gallery.gd`.

Commands and outputs below preserve the terminal text with color escape sequences and trailing spaces removed.

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --import --quit --log-file /tmp/hazard-import-final.log` (exit 0):

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

[   0% ] update_scripts_classes | Started Registering global classes... (3 steps)
[   0% ] update_scripts_classes |
[  25% ] update_scripts_classes |
[  50% ] update_scripts_classes |
[ DONE ] update_scripts_classes

[   0% ] loading_editor_layout | Started Loading editor (5 steps)
[   0% ] loading_editor_layout | Loading editor layout...
[  16% ] loading_editor_layout | Loading docks...
[ DONE ] loading_editor_layout

ERROR: Cannot save file '/Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres'.
   at: save (scene/resources/resource_format_text.cpp:1768)
ERROR: Error saving editor settings to /Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres
   at: save (editor/settings/editor_settings.cpp:1525)
```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/bug_swarm_visual.gd --check-only --log-file /tmp/hazard-syntax-final-0.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/build_shockwave_visual.gd --check-only --log-file /tmp/hazard-syntax-final-1.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/comment_flood_visual.gd --check-only --log-file /tmp/hazard-syntax-final-2.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/deprecated_pit_visual.gd --check-only --log-file /tmp/hazard-syntax-final-3.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/dev/hazard_gallery.gd --check-only --log-file /tmp/hazard-syntax-final-4.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/hazard_art.gd --check-only --log-file /tmp/hazard-syntax-final-5.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/laser_grid_visual.gd --check-only --log-file /tmp/hazard-syntax-final-6.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/merge_conflict_visual.gd --check-only --log-file /tmp/hazard-syntax-final-7.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/pr_backlog_high_visual.gd --check-only --log-file /tmp/hazard-syntax-final-8.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/hazards/visuals/pr_backlog_low_visual.gd --check-only --log-file /tmp/hazard-syntax-final-9.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd --check-only --log-file /tmp/hazard-syntax-final-10.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/capture_previews.gd --check-only --log-file /tmp/hazard-syntax-final-11.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd --log-file /tmp/hazard-smoke-verified.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
RUNNER VISUAL SMOKE: PASS (0 failures)
```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_scaffold_check.gd --log-file /tmp/hazard-scaffold-verified.log` (exit 1):

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

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/environment_check.gd --log-file /tmp/hazard-environment-verified.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
SPIKE: renderer=gl_compatibility scale=0.5 glow_threshold=0.75 fog=22..88 particles=320
ENV CHECK: PASS (0 failures)
```

## Requests to backend

Please clarify the elevated floor-projection exception in contract section 5.2 and wire the existing PR 2 timed-laser state hooks. No backend files were edited. The backend's PR 2 relaxes `runner_scaffold_check.gd` to accept a mounted corridor in place of `World/GrayboxEnvironment`. On this branch the check will pass once PR 2 is merged; until then, the single failure is the documented lifecycle state, not a defect.

## Known gaps

No remaining F0/F1 renderer or preview gaps are reported by the coordinator on 4.7.0; final acceptance on the pinned 4.7.1 remains pending. F2 headless checks are complete. The coordinator ran graphical Godot on the host and captured Hoppy back-facing in the corridor; Codex itself did not run graphical Godot. The coordinator's F3b 19-fixture host gallery capture reports `CAPTURE: gallery error=0 draw_calls=168`; its pre-fix budget line was `GALLERY DRAW BUDGET: 168 / 183`. Hazards, power-ups and the pursuer have host capture and headless verification below. Runner audio and F4 menus remain outside this run's scope.

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

F3 hazard additions and updates:

- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/bug_swarm_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/bug_swarm_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/bug_swarm_visual.tscn`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/build_shockwave_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/build_shockwave_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/build_shockwave_visual.tscn`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/comment_flood_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/comment_flood_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/comment_flood_visual.tscn`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/deprecated_pit_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/deprecated_pit_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/deprecated_pit_visual.tscn`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/dev/hazard_gallery.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/dev/hazard_gallery.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/dev/hazard_gallery.tscn`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/hazard_art.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/hazard_art.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/laser_grid_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/laser_grid_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/laser_grid_visual.tscn`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/merge_conflict_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/merge_conflict_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/merge_conflict_visual.tscn`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/pr_backlog_high_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/pr_backlog_high_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/pr_backlog_high_visual.tscn`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/pr_backlog_low_visual.gd`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/pr_backlog_low_visual.gd.uid`
- `hoppys-adventure-arcade/scenes/runner/hazards/visuals/pr_backlog_low_visual.tscn`
- Updated `hoppys-adventure-arcade/tests/runner_visual_smoke.gd`.
- Updated `hoppys-adventure-arcade/scenes/runner/environment/dev/capture_previews.gd`.
- Updated `docs/endless-runner.md`, including both F2 validator corrections.

Coordinator verbatim F3a hazard-only historical host capture:

```text
CAPTURE: gallery error=0 draw_calls=106
GALLERY DRAW BUDGET: 106 / 183
PREVIEW CAPTURE: PASS
```

Coordinator verbatim F3b host capture of the 19-fixture gallery (pre-correction run, before the budget correction):

```text
CAPTURE: gallery error=0 draw_calls=168
GALLERY DRAW BUDGET: 168 / 183
```

Coordinator final verbatim host capture of the 19-fixture gallery after the budget correction:

```text
CAPTURE: gallery error=0 draw_calls=162
GALLERY DRAW BUDGET: 162 / 281
PREVIEW CAPTURE: PASS
```

## F3 completion touched files

- Six `.tscn` / `.gd` / generated `.gd.uid` pairs under `scenes/runner/powerups/visuals/`, plus `power_up_art.gd` and its UID.
- `scenes/runner/pursuer/pursuer_visual.tscn`, `.gd` and generated `.gd.uid`.
- `scenes/runner/hazards/visuals/dev/hazard_gallery.gd` and `.tscn`.
- `tests/runner_visual_smoke.gd`.
- `scenes/runner/environment/corridor.gd` and `scenes/runner/environment/dev/environment_check.gd`, the two files explicitly requested for the pillar-check leftover.
- `docs/endless-runner.md`.

Paths above are relative to `hoppys-adventure-arcade/`, except this document.

## Verification: F3 power-ups and pursuer

Run from the repository root on installed Godot 4.7.0. No graphical runs, downloads, commits or pushes were performed. Final 4.7.1 acceptance remains pending. The coordinator supplied the F3b host captures linked above; the coordinator's final post-correction host transcript is recorded above. All eight new scripts and four changed existing scripts pass `--check-only`. The visual smoke passes with zero captured runtime errors; its 121 threat-1 samples merge to 5.649928 m wide and 2.288509 m tall. The environment check passes with CPU pillar positions. The scaffold check retains the existing one-failure GrayboxEnvironment expectation; backend PR 2 still needs to accept the mounted Corridor. No new backend API is required by these visuals.

The engine's certificate diagnostic occurs before the smoke installs its runtime error logger. Import returns exit 0 but reports sandbox-blocked editor-settings saves. These host diagnostics are preserved below and are not represented as clean import output.

Plain-text engine log (progress-row trailing spaces trimmed) for `/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --import --log-file /tmp/f3-import.log` (exit 0):

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

[   0% ] update_scripts_classes | Started Registering global classes... (4 steps)
[   0% ] update_scripts_classes |
[  20% ] update_scripts_classes |
[  40% ] update_scripts_classes |
[  60% ] update_scripts_classes |
[ DONE ] update_scripts_classes

[   0% ] loading_editor_layout | Started Loading editor (5 steps)
[   0% ] loading_editor_layout | Loading editor layout...
[  16% ] loading_editor_layout | Loading docks...
[ DONE ] loading_editor_layout

ERROR: Cannot save file '/Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres'.
   at: save (scene/resources/resource_format_text.cpp:1768)
ERROR: Error saving editor settings to /Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres
   at: save (editor/settings/editor_settings.cpp:1525)
```

Verbatim syntax command transcripts (the `EXIT` lines record process exit codes):

```text
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/approve_shield_visual.gd --log-file /tmp/f3-check-0.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/auto_fix_visual.gd --log-file /tmp/f3-check-1.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/code_review_visual.gd --log-file /tmp/f3-check-2.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/lgtm_visual.gd --log-file /tmp/f3-check-3.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/nitro_visual.gd --log-file /tmp/f3-check-4.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/power_up_art.gd --log-file /tmp/f3-check-5.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/super_jump_visual.gd --log-file /tmp/f3-check-6.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/pursuer/pursuer_visual.gd --log-file /tmp/f3-check-7.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/dev/hazard_gallery.gd --log-file /tmp/f3-check-8.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/environment/corridor.gd --log-file /tmp/f3-check-9.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/environment/dev/environment_check.gd --log-file /tmp/f3-check-10.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://tests/runner_visual_smoke.gd --log-file /tmp/f3-check-11.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0
```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd --log-file /tmp/f3-smoke.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
HAZARD DRAW CENSUS: pr_backlog_low/ peak=6
HAZARD DRAW CENSUS: pr_backlog_high/ peak=8
HAZARD DRAW CENSUS: bug_swarm/ peak=6
HAZARD DRAW CENSUS: merge_conflict/ peak=9
HAZARD DRAW CENSUS: deprecated_pit/full peak=8
HAZARD DRAW CENSUS: deprecated_pit/two_lane peak=8
HAZARD DRAW CENSUS: laser_grid/ground peak=8
HAZARD DRAW CENSUS: laser_grid/mid peak=8
HAZARD DRAW CENSUS: laser_grid/high peak=8
HAZARD DRAW CENSUS: laser_grid/timed peak=8
HAZARD DRAW CENSUS: comment_flood/ peak=7
HAZARD DRAW CENSUS: build_shockwave/ peak=6
HAZARD CASES CHECKED: 12; summed peak draw census=90
POWER-UP VISUALS: 6 checked; reuse, collection and pause PASS
PURSUER THREAT 1 MERGED VISIBLE AABB: [P: (-2.824963, 0.013877, -0.408651), S: (5.649928, 2.288509, 0.587685)]
PURSUER VISUAL: threat, catch, retreat, reuse and pause checked
RUNNER VISUAL SMOKE: PASS (0 failures)
```

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_scaffold_check.gd --log-file /tmp/f3-scaffold.log` (exit 1):

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

`/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/environment_check.gd --log-file /tmp/f3-environment.log` (exit 0):

```text
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
SPIKE: renderer=gl_compatibility scale=0.5 glow_threshold=0.75 fog=22..88 particles=320
ENV CHECK: PASS (0 failures)
```

## F3b validator corrections verification

The gallery budget now derives from the 12 hazard cases, six power-ups and one pursuer: 281. Tags use 0.007 pixel size and wrap within 1.33 m; pursuer headlines use cream, 0.011 pixel size and no outlines, with horizontal fitting to avoid overlap. Cards are 0.92 x 0.40 m at 1.04 x 0.49 m spacing. Retreat restores the cached non-zero threat pose before toppling. Collection stops processing and resets the hidden ring scale; reuse enables processing. Smoke assertions include hidden draw-producing nodes, count outlined labels as two, and require each pickup and pursuer to remain within 14 draws plus exactly one pursuer light. All six pickup roots use PascalCase. F4-F6 remain deferred. No graphical runs, commits or pushes were performed.

Verbatim plain-text import log, run from repository root (exit 0):

```text
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --import --quit --log-file /tmp/f3b-import.log
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

[   0% ] update_scripts_classes | Started Registering global classes... (4 steps)
[   0% ] update_scripts_classes | 
[  20% ] update_scripts_classes | 
[  40% ] update_scripts_classes | 
[  60% ] update_scripts_classes | 
[ DONE ] update_scripts_classes

[   0% ] loading_editor_layout | Started Loading editor (5 steps)
[   0% ] loading_editor_layout | Loading editor layout...
[  16% ] loading_editor_layout | Loading docks...
[ DONE ] loading_editor_layout

ERROR: Cannot save file '/Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres'.
   at: save (scene/resources/resource_format_text.cpp:1768)
ERROR: Error saving editor settings to /Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres
   at: save (editor/settings/editor_settings.cpp:1525)
EXIT: 0
```

Verbatim command outputs for all 13 changed/new GDScript files and both runtime checks, run from repository root:

```text
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/environment/corridor.gd --log-file /tmp/f3b-verify-0.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/environment/dev/capture_previews.gd --log-file /tmp/f3b-verify-1.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/environment/dev/environment_check.gd --log-file /tmp/f3b-verify-2.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/hazards/visuals/dev/hazard_gallery.gd --log-file /tmp/f3b-verify-3.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/approve_shield_visual.gd --log-file /tmp/f3b-verify-4.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/auto_fix_visual.gd --log-file /tmp/f3b-verify-5.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/code_review_visual.gd --log-file /tmp/f3b-verify-6.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/lgtm_visual.gd --log-file /tmp/f3b-verify-7.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/nitro_visual.gd --log-file /tmp/f3b-verify-8.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/power_up_art.gd --log-file /tmp/f3b-verify-9.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/powerups/visuals/super_jump_visual.gd --log-file /tmp/f3b-verify-10.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://scenes/runner/pursuer/pursuer_visual.gd --log-file /tmp/f3b-verify-11.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --check-only --script res://tests/runner_visual_smoke.gd --log-file /tmp/f3b-verify-12.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd --log-file /tmp/f3b-verify-13.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
HAZARD DRAW CENSUS: pr_backlog_low/ peak=6
HAZARD DRAW CENSUS: pr_backlog_high/ peak=8
HAZARD DRAW CENSUS: bug_swarm/ peak=6
HAZARD DRAW CENSUS: merge_conflict/ peak=9
HAZARD DRAW CENSUS: deprecated_pit/full peak=8
HAZARD DRAW CENSUS: deprecated_pit/two_lane peak=8
HAZARD DRAW CENSUS: laser_grid/ground peak=8
HAZARD DRAW CENSUS: laser_grid/mid peak=8
HAZARD DRAW CENSUS: laser_grid/high peak=8
HAZARD DRAW CENSUS: laser_grid/timed peak=8
HAZARD DRAW CENSUS: comment_flood/ peak=7
HAZARD DRAW CENSUS: build_shockwave/ peak=6
HAZARD CASES CHECKED: 12; summed peak draw census=90
POWER-UP VISUALS: 6 checked; reuse, collection and pause PASS
PURSUER THREAT 1 MERGED VISIBLE AABB: [P: (-2.824963, 0.013877, -0.408651), S: (5.649928, 2.288509, 0.587685)]
PURSUER VISUAL: threat, catch, retreat, reuse and pause checked
RUNNER VISUAL SMOKE: PASS (0 failures)
EXIT: 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/environment_check.gd --log-file /tmp/f3b-verify-14.log
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
SPIKE: renderer=gl_compatibility scale=0.5 glow_threshold=0.75 fog=22..88 particles=320
ENV CHECK: PASS (0 failures)
EXIT: 0

```
