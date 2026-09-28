# Frontend integration review, 2026-09-21

All six findings were checked against the current tree. Findings 1-5 are addressed; finding 6's scene-root claim is stale, with regression coverage added. No commits, pushes, graphical scenes, backend edits, README edits or preview edits were made. Branch: `codex/endless-runner-stages`.

## Findings

Paths below are relative to `hoppys-adventure-arcade/` unless prefixed with `docs/`.

| Finding | Disposition | Evidence |
| --- | --- | --- |
| 1. Hazard normal kernel | Fixed | `scenes/runner/hazards/visuals/hifi/texture_forge.gd:9` preallocates PackedFloat32 heights; line 40 uses wrapped array indices with the equivalent unrolled Sobel stencil. Full comparison with HEAD produced byte-identical albedo/normal/roughness including mipmaps. |
| 2. Round-5 file list | Fixed | `docs/assets/a5.md:170` includes `scenes/runner/boss/damage_number.gd`. |
| 3. Beam minimum alpha | Fixed | `tests/assets/a5_check.gd:377` reads the loaded Shader code; lines 379-382 lock vec4 alpha, scan minimum, final ALPHA factor, then evaluate the numeric threshold. No scalar lookup of a vec4. |
| 4. Detached border | Fixed | `scenes/runner/ui/boss_hud.gd:55` fetches the active StyleBoxFlat immediately after polish; `tests/assets/a9_check.gd:315` checks identity against the visible panel style. |
| 5. Turn-audio warmup | Fixed integration; duplicate synthesis skipped | Existing prewarm already covered both turn cues and every panned variant. `scenes/runner/audio/runner_audio.gd:68` now calls shared guarded prewarm; `tests/assets/prewarm_check.gd:74` onward asserts critical cues, every percussive, and all directional whooshes before gameplay. |
| 6. UI layer | Scene edit skipped: stale finding | All four `.tscn` roots already declare `Control` at line 5 and inherit production HUD layer 10 (`scenes/runner/runner_game.tscn:117`); post_fx remains 9. `tests/assets/a9_check.gd:282` reads every actual HUD/Overlays mount and asserts effective layer above post; card bounds stay outside full-height bars at 1280x720. Backend unchanged. |

The letterbox checks exercise geometry, layer ownership, and the existing opening/closing hooks. They do not verify rendered legibility. Graphical inspection remains outstanding under the requested no-graphical-runs constraint.

## Prewarm

Fresh baseline: **3318.868 ms**. Final cold warm: **712.276 ms**, cold corridor ready: **737.983 ms**. Repeat while pending: **0.002 ms**; repeat after completion: **0.001 ms**. The synchronous warm target of approximately 1000 ms is met on this machine. Godot is `4.7.stable.official.5b4e0cb0f`; this is not pinned-4.7.1 acceptance or a GPU timing.

Synchronous: hazard atlas/border, all projectile meshes, pickup maps and three templates, shared materials/theme/glyphs, percussives, jump, boss_intro, turn_warning, turn_whoosh, projectile_whoosh, six footsteps and 16 panned whooshes.

WorkerThreadPool Image jobs: player fur, player cloth, environment plating/circuit, environment floor, boss plating, pursuer plating. Only local Image generation runs on workers. Completed jobs are joined and ImageTextures finalized on the main thread, at most one image package or deferred package per frame. Boss glyphs and authored boss mesh/material preparation, plus nonurgent audio recipes, run later on the main thread. These deferred main-thread costs are spread across packages, not eliminated. Outstanding workers are joined on application shutdown.

The environment binds neutral 1x1 textures immediately; completed images replace their contents while preserving texture object identity. Player, boss and pursuer retain the synchronous lazy fallback if accessed before completion. The prewarm check forces an early boss and verifies that later worker completion preserves its textures. Existing instance-owned animated materials remain private.

The headless dummy renderer does not implement texture replacement/readback updates, as confirmed by a local minimal reproduction and [Godot 4.7 source](https://raw.githubusercontent.com/godotengine/godot/4.7-stable/servers/rendering/dummy/storage/texture_storage.h). A2's pixel/mipmap assertions use the complete lazy image path; prewarm checks the worker Images, main-thread finalization, texture metadata and identity. GPU replacement and temporary neutral-to-detail appearance are **not verified**. Graphical captures should wait for `Prewarm.is_complete()`. The worker/main-thread split follows [Godot thread-safety guidance](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html); tasks are joined per the [WorkerThreadPool contract](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html).

Verbatim timings and census:

```text
PREWARM cold corridor ready(): 737.983 ms
PREWARM cold warm(): 712.276 ms
PREWARM sync environment: 1.536 ms
PREWARM sync materials: 0.328 ms
PREWARM sync hazards: 162.553 ms
PREWARM sync hazard_meshes: 8.231 ms
PREWARM sync pickups: 151.688 ms
PREWARM sync pickup_templates: 0.648 ms
PREWARM sync ui: 8.840 ms
PREWARM sync audio: 316.935 ms
PREWARM sync footsteps: 1.074 ms
PREWARM sync whooshes: 52.330 ms
PREWARM pending repeat warm(): 0.002 ms
PREWARM GPU replacement: NOT VERIFIED (headless dummy retains initial pixel snapshot)
PREWARM async boss/textures[]: image=116.703 ms finalize=0.004 ms
PREWARM async player/maps["fur"]: image=221.396 ms finalize=0.036 ms
PREWARM async player/maps["cloth"]: image=225.839 ms finalize=0.011 ms
PREWARM async pursuer/maps[]: image=170.875 ms finalize=0.013 ms
PREWARM async environment/floor_maps[]: image=496.110 ms finalize=0.015 ms
PREWARM async environment/maps[]: image=1373.536 ms finalize=0.024 ms
PREWARM deferred main audio: 432.877 ms
PREWARM deferred main boss: 11.416 ms
PREWARM deferred main boss_meshes: 39.273 ms
PREWARM deferred main boss_fx: 0.369 ms
PREWARM census player: 6 resources
PREWARM census environment: 9 resources
PREWARM census materials: 11 resources
PREWARM census hazards: 4 resources
PREWARM census hazard_meshes: 16 resources
PREWARM census pickups: 4 resources
PREWARM census pickup_templates: 3 resources
PREWARM census boss: 4 resources
PREWARM census boss_meshes: 42 resources
PREWARM census boss_fx: 2 resources
PREWARM census pursuer: 3 resources
PREWARM census ui: 1 resources
PREWARM census audio: 32 resources
PREWARM census footsteps: 6 resources
PREWARM census whooshes: 16 resources
PREWARM repeat warm(): 0.001 ms
PREWARM: PASS (326 checks)
```

## Verification

[Full verbatim command/output/exit transcript](frontend-review-verification.txt). The raw transcript retains import ANSI sequences. Every requested command was executed. Import and all 14 changed/new GDScript check-only commands exited 0, including the pre-existing corridor change. The final prewarm and A2 edits were rechecked after their last change. `git diff --check` exited 0 with no output.

| Script | Exit | Verbatim final marker |
| --- | --- | --- |
| `prewarm_check.gd` | 0 | `PREWARM: PASS (326 checks)` |
| `a3_check.gd` | 0 | `ASSET A3: PASS (158393 checks)` |
| `a5_check.gd` | 0 | `ASSET A5: PASS (60339 checks)` |
| `a7_check.gd` | 0 | `ASSET A7: PASS (950 checks)` |
| `a8_check.gd` | 0 | `ASSET A8: PASS (2323 checks)` |
| `a9_check.gd` | 0 | `ASSET A9: PASS (147 checks)` |
| `runner_visual_smoke.gd` | 2 | `RUNNER VISUAL SMOKE: FAIL (2 failures)` |
| `runner_smoke.gd` | 3 | `RUNNER SMOKE: FAIL (3 failures / 127 checks)` |
| `a1_check.gd` | 0 | `ASSET A1: PASS (2950 checks)` |
| `a2_check.gd` | 0 | `ASSET A2: PASS (261 checks)` |
| `a6_check.gd` | 0 | `ASSET A6: PASS (102 checks)` |

The sandbox may fail only the two documented `user://` persistence checks: `Codex name persists` and `temporary board contains saved run`. This visual-smoke run failed exactly those two checks:

```text
VISUAL CHECK FAILED: Codex name persists
VISUAL CHECK FAILED: temporary board contains saved run
RUNNER FULL LOOP: FAIL (menu, play, hit, pursuit, 18.0s timer recovery, hit, hit, caught, finished, game over, Codex, retry, menu, hub, default music; isolated board removed)
RUNNER VISUAL SMOKE: FAIL (2 failures)
```

The backend smoke separately exited 3 for three leaderboard-persistence assertions:

```text
ERROR: RUNNER SMOKE: the board write reported error 12
ERROR: RUNNER SMOKE: leaderboard_saved was never emitted
ERROR: RUNNER SMOKE: this run is not on the leaderboard
RUNNER SMOKE: FAIL (3 failures / 127 checks)
```

These are local failures, not host PASS claims. Both smokes remain persistence-blocked in this sandbox. The macOS certificate-store diagnostic appears in runtime checks; import also reports the nested project folder and inability to save editor settings. No asset check reports script errors. A7 explicitly reports portrait raster NOT VERIFIED in headless mode. The auxiliary HEAD-atlas comparison reports byte equality and exit 0, followed by temporary-script resource cleanup warnings; those warnings did not occur in the requested asset checks.

## Files touched by this task

- [hoppys-adventure-arcade/scenes/runner/audio/runner_audio.gd](../../hoppys-adventure-arcade/scenes/runner/audio/runner_audio.gd)
- [hoppys-adventure-arcade/scenes/runner/boss/hifi/forge.gd](../../hoppys-adventure-arcade/scenes/runner/boss/hifi/forge.gd)
- [hoppys-adventure-arcade/scenes/runner/environment/hifi/texture_forge.gd](../../hoppys-adventure-arcade/scenes/runner/environment/hifi/texture_forge.gd)
- [hoppys-adventure-arcade/scenes/runner/hazards/visuals/hifi/texture_forge.gd](../../hoppys-adventure-arcade/scenes/runner/hazards/visuals/hifi/texture_forge.gd)
- [hoppys-adventure-arcade/scenes/runner/player/hifi/forge.gd](../../hoppys-adventure-arcade/scenes/runner/player/hifi/forge.gd)
- [hoppys-adventure-arcade/scenes/runner/pursuer/hifi/forge.gd](../../hoppys-adventure-arcade/scenes/runner/pursuer/hifi/forge.gd)
- [hoppys-adventure-arcade/scenes/runner/ui/boss_hud.gd](../../hoppys-adventure-arcade/scenes/runner/ui/boss_hud.gd)
- [hoppys-adventure-arcade/scenes/runner/environment/hifi/prewarm.gd](../../hoppys-adventure-arcade/scenes/runner/environment/hifi/prewarm.gd)
- [hoppys-adventure-arcade/scenes/runner/environment/hifi/image_warm_job.gd](../../hoppys-adventure-arcade/scenes/runner/environment/hifi/image_warm_job.gd)
- [hoppys-adventure-arcade/scenes/runner/environment/hifi/image_warm_job.gd.uid](../../hoppys-adventure-arcade/scenes/runner/environment/hifi/image_warm_job.gd.uid)
- [hoppys-adventure-arcade/tests/assets/a2_check.gd](../../hoppys-adventure-arcade/tests/assets/a2_check.gd)
- [hoppys-adventure-arcade/tests/assets/a5_check.gd](../../hoppys-adventure-arcade/tests/assets/a5_check.gd)
- [hoppys-adventure-arcade/tests/assets/a9_check.gd](../../hoppys-adventure-arcade/tests/assets/a9_check.gd)
- [hoppys-adventure-arcade/tests/assets/prewarm_check.gd](../../hoppys-adventure-arcade/tests/assets/prewarm_check.gd)
- [docs/endless-runner.md](../../docs/endless-runner.md)
- [docs/assets/a1.md](../../docs/assets/a1.md)
- [docs/assets/a2.md](../../docs/assets/a2.md)
- [docs/assets/a3.md](../../docs/assets/a3.md)
- [docs/assets/a5.md](../../docs/assets/a5.md)
- [docs/assets/a6.md](../../docs/assets/a6.md)
- [docs/assets/a7.md](../../docs/assets/a7.md)
- [docs/assets/a8.md](../../docs/assets/a8.md)
- [docs/assets/a9.md](../../docs/assets/a9.md)
- [docs/assets/frontend-review-verification.md](../../docs/assets/frontend-review-verification.md)
- [docs/assets/frontend-review-verification.txt](../../docs/assets/frontend-review-verification.txt)

Pre-existing changes preserved: `README.md`, all 14 modified `docs/previews/endless-runner-*.png` files, `scenes/runner/environment/corridor.gd`, and the pre-existing prewarm/test `.uid` files were not edited by this task. The existing `docs/endless-runner.md`, `prewarm.gd` and `prewarm_check.gd` work was extended in place. Earlier documentation-pass transcripts were retained as historical evidence; stale A3 absence claims in the current overview were updated from the now-present package and successful check.
