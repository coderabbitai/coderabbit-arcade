# Integration cleanup verification (2026-09-22)

Worktree branch: `codex/endless-runner-stages`. The worktree was clean at task start. All Godot commands used the headless installed engine `4.7.stable.official.5b4e0cb0f`. No graphical scene, Blender process, commit or push was run. Draw/triangle/texture results are headless resource censuses, not GPU measurements. Pinned 4.7.1 acceptance remains separate.

Changes and touched files:

- `README.md:9`: current asset-pass status.
- `docs/endless-runner.md:62`: prewarm cleanup and fresh result; asset rows at lines 76, 77, 79 and 82; Blender pipeline and affordance rule at lines 88 and 96.
- `hoppys-adventure-arcade/scenes/runner/environment/hifi/prewarm.gd:55`: removed the player fur/cloth jobs and their player-only finalizer branch.
- `hoppys-adventure-arcade/tests/assets/prewarm_check.gd:32`: removed the unused player cache from repeated identity checks and the player census expectation at line 117.
- Deleted `hoppys-adventure-arcade/scenes/runner/player/hifi/forge.gd` and `forge.gd.uid`. Repository-wide text/UID search found no remaining project consumers after the prewarm edits. The earlier frontend-review report and transcript retain historical mentions.
- `docs/assets/integration-cleanup-verification.md`: this report and complete verification transcript.

Retained `scenes/runner/player/hifi/energy.gdshader` and its UID: `hoppy_runner_visual.gd:5` preloads it, and lines 101-112 use it for aura, shield and glyph materials. No asset, backend, preview, or package implementation files were changed.

Prewarm now passes 311 checks, down from the historical 326 because the removed player census contributed two checks and its removed cache population check ran thirteen times. The remaining worker, fallback, cache identity, pickup reuse and retry checks pass. Fresh A1/A2/A4/A7 results match their latest package reports: 226/425/6035/1245 checks. A1 is 9 draws / 38,480 triangles / 8 textures; A2 is 13 rest / 16 turn draws. Fresh A7 census is 217 CanvasItems, superseding the historical 192 in its package report.

Commands, combined stdout/stderr and exit codes follow. Output is verbatim except terminal ANSI style escapes and trailing progress whitespace removed from the import output. Raw output is also saved at `/tmp/runner-integration-cleanup/verbatim.txt`.

Import and both changed-script check-only commands exit 0. Import retains the macOS certificate diagnostic, ignored nested project warning and sandbox editor-settings save errors. Prewarm and A1/A2/A4/A7 exit 0. Visual smoke exits 2; backend smoke exits 3.

The full loop fails only on the two documented sandbox user:// persistence checks:
`Codex name persists` and `temporary board contains saved run`.
Backend smoke fails only on `the board write reported error 12`, `leaderboard_saved was never emitted`, and `this run is not on the leaderboard`. These sandbox-only results are separate from previously reported coordinator host PASS results.

```text
$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/import.log --import
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

[   0% ] update_scripts_classes | Started Registering global classes... (7 steps)
[   0% ] update_scripts_classes |
[  12% ] update_scripts_classes |
[  25% ] update_scripts_classes |
[  37% ] update_scripts_classes |
[  50% ] update_scripts_classes |
[  62% ] update_scripts_classes |
[  75% ] update_scripts_classes |
[ DONE ] update_scripts_classes

[   0% ] _update_scan_actions | Started Scanning actions... (9 steps)
[   0% ] _update_scan_actions | hoppy.glb
[  10% ] _update_scan_actions | hoppy_accessory_albedo.png
[  20% ] _update_scan_actions | hoppy_accessory_emissive.png
[  30% ] _update_scan_actions | hoppy_accessory_normal.png
[  40% ] _update_scan_actions | hoppy_accessory_orm.png
[  50% ] _update_scan_actions | hoppy_body_albedo.png
[  60% ] _update_scan_actions | hoppy_body_emissive.png
[  70% ] _update_scan_actions | hoppy_body_normal.png
[  80% ] _update_scan_actions | hoppy_body_orm.png
[ DONE ] _update_scan_actions

[   0% ] reimport | Started (Re)Importing Assets (9 steps)
[   0% ] reimport | Preparing files to reimport...
[  10% ] reimport | Preparing files to reimport...
[  20% ] reimport | Preparing files to reimport...
[  30% ] reimport | Preparing files to reimport...
[  40% ] reimport | Preparing files to reimport...
[  50% ] reimport | Preparing files to reimport...
[  60% ] reimport | Preparing files to reimport...
[  70% ] reimport | Preparing files to reimport...
[  80% ] reimport | Preparing files to reimport...
[   0% ] reimport | Executing pre-reimport operations...
[   0% ] preload_reimporting_scene | Started Preparing scenes for reload (1 steps)
[   0% ] preload_reimporting_scene | Analyzing scene [empty]
[  50% ] preload_reimporting_scene | Preparation done.
[ DONE ] preload_reimporting_scene

[   0% ] reimport | hoppy_accessory_albedo.png
[  10% ] reimport | hoppy_accessory_emissive.png
[  20% ] reimport | hoppy_accessory_normal.png
[  30% ] reimport | hoppy_accessory_orm.png
[  40% ] reimport | hoppy_body_albedo.png
[  50% ] reimport | hoppy_body_emissive.png
[  60% ] reimport | hoppy_body_normal.png
[  70% ] reimport | hoppy_body_orm.png
[  80% ] reimport | hoppy.glb
[   0% ] import | Started Import Scene (104 steps)
[   0% ] import | Importing Scene...
[   1% ] import | Running Custom Script...
[  99% ] import | Saving...
[ DONE ] import

[  90% ] reimport | Finalizing Asset Import...
[ DONE ] reimport

[   0% ] reimport | Started (Re)Importing Assets (9 steps)
[   0% ] reimport | Executing post-reimport operations...
[ DONE ] reimport

[   0% ] loading_editor_layout | Started Loading editor (5 steps)
[   0% ] loading_editor_layout | Loading editor layout...
[  16% ] loading_editor_layout | Loading docks...
[  33% ] loading_editor_layout | Reopening scenes...
[  50% ] loading_editor_layout | Loading central editor layout...
[  66% ] loading_editor_layout | Loading plugin window layout...
[  83% ] loading_editor_layout | Editor layout ready.
[ DONE ] loading_editor_layout

ERROR: Cannot save file '/Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres'.
   at: save (scene/resources/resource_format_text.cpp:1768)
ERROR: Error saving editor settings to /Users/jp/Library/Application Support/Godot/editor_settings-4.7.tres
   at: save (editor/settings/editor_settings.cpp:1525)

EXIT 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/check-prewarm.log --check-only --script res://scenes/runner/environment/hifi/prewarm.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org


EXIT 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/check-prewarm-test.log --check-only --script res://tests/assets/prewarm_check.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org


EXIT 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/prewarm.log --script res://tests/assets/prewarm_check.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
PREWARM cold corridor ready(): 804.826 ms
PREWARM cold warm(): 722.690 ms
PREWARM sync environment: 2.119 ms
PREWARM sync wall_atlas: 21.729 ms
PREWARM sync materials: 0.392 ms
PREWARM sync hazards: 168.247 ms
PREWARM sync hazard_meshes: 8.678 ms
PREWARM sync pickups: 156.904 ms
PREWARM sync pickup_templates: 1.009 ms
PREWARM sync ui: 10.026 ms
PREWARM sync audio: 294.604 ms
PREWARM sync footsteps: 1.144 ms
PREWARM sync whooshes: 53.199 ms
PREWARM pending repeat warm(): 0.002 ms
PREWARM GPU replacement: NOT VERIFIED (headless dummy retains initial pixel snapshot)
PREWARM async boss/textures[]: image=107.977 ms finalize=0.004 ms
PREWARM async pursuer/maps[]: image=140.168 ms finalize=0.007 ms
PREWARM async environment/floor_maps[]: image=487.349 ms finalize=0.019 ms
PREWARM async environment/maps[]: image=1623.767 ms finalize=0.025 ms
PREWARM deferred main audio: 441.786 ms
PREWARM deferred main boss: 11.748 ms
PREWARM deferred main boss_meshes: 44.031 ms
PREWARM deferred main boss_fx: 0.413 ms
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
PREWARM: PASS (311 checks)

EXIT 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/a1.log --script res://tests/assets/a1_check.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
A1 CENSUS: 9 draws, 38480 triangles, 8 textures; imported model 37088 triangles
A1 STANDING: [P: (-0.374, 0.000206, -0.311), S: (0.748, 1.799794, 0.673017)]
A1 CAPTURE POSE: arm delta 0.494622 rad, leg delta 0.518554 rad, centroid delta 0.043231 m
A1 ROLL: 12 sampled frames, y 0.129863 to 0.777745
ASSET A1: PASS (226 checks)

EXIT 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/a2.log --script res://tests/assets/a2_check.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
ASSET A2 WALLS: atlas=192x256 cell=24x32 layers=3 variants=4 max_emissive=0.367 texels=4046848 / 8388608
ASSET A2 R8 GLYPH PROJECTION: close_6m=27.02px gameplay_32m=5.07px (analytic, not GPU measured)
ASSET A2 R9: brush_autocorrelation_peak=0.0679 (<0.4); merged_batches=3; full_face=true
ASSET A2 R12: authored/softened/flat/smear guards checked; detail>=0.40 edge_density>=0.04 frame=45..70
ASSET A2 CENSUS: rest=13 turn=16 triangles=54846 textures=8 (7 maps + shared wall/particle atlas)
ASSET A2: PASS (425 checks)

EXIT 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/a4.log --script res://tests/assets/a4_check.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
A4 GLYPH approve_shield: 28.10 visible pixels at 60m
A4 EMISSIVE approve_shield: 39.40 percent sculpture area
A4 CENSUS approve_shield: 7 idle / 8 peak draws, 444 peak triangles
A4 GLYPH auto_fix: 25.64 visible pixels at 60m
A4 EMISSIVE auto_fix: 33.43 percent sculpture area
A4 CENSUS auto_fix: 7 idle / 8 peak draws, 544 peak triangles
A4 GLYPH lgtm: 26.73 visible pixels at 60m
A4 EMISSIVE lgtm: 37.18 percent sculpture area
A4 CENSUS lgtm: 7 idle / 8 peak draws, 508 peak triangles
A4 GLYPH nitro: 30.01 visible pixels at 60m
A4 EMISSIVE nitro: 36.18 percent sculpture area
A4 CENSUS nitro: 7 idle / 8 peak draws, 528 peak triangles
A4 GLYPH super_jump: 28.92 visible pixels at 60m
A4 EMISSIVE super_jump: 33.74 percent sculpture area
A4 CENSUS super_jump: 7 idle / 8 peak draws, 2012 peak triangles
A4 GLYPH code_review: 28.92 visible pixels at 60m
A4 EMISSIVE code_review: 36.13 percent sculpture area
A4 CENSUS code_review: 7 idle / 8 peak draws, 2196 peak triangles
A4 GLYPH review_comment: 27.83 visible pixels at 60m
A4 EMISSIVE review_comment: 38.38 percent sculpture area
A4 CENSUS review_comment: 7 idle / 8 peak draws, 460 peak triangles
A4 GLYPH lint_rule: 27.83 visible pixels at 60m
A4 EMISSIVE lint_rule: 34.85 percent sculpture area
A4 CENSUS lint_rule: 7 idle / 8 peak draws, 484 peak triangles
A4 GLYPH unit_test: 28.92 visible pixels at 60m
A4 EMISSIVE unit_test: 34.90 percent sculpture area
A4 CENSUS unit_test: 7 idle / 8 peak draws, 568 peak triangles
A4 GLYPH auto_fix_patch: 26.73 visible pixels at 60m
A4 EMISSIVE auto_fix_patch: 35.16 percent sculpture area
A4 CENSUS auto_fix_patch: 7 idle / 8 peak draws, 524 peak triangles
A4 SILHOUETTES: 10 unique; minimum pairwise difference 91 / 768 samples
ASSET A4: PASS (6035 checks)

EXIT 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/a7.log --script res://tests/assets/a7_check.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
A7 GET READY RECT (1280, 720): [P: (140.0, 530.0), S: (1000.0, 160.0)]
A7 GET READY RECT (1440, 900): [P: (220.0, 710.0), S: (1000.0, 160.0)]
A7 PORTRAIT RASTER: NOT VERIFIED (headless; coordinator capture performs pixel gate)
A7 HUD RECT (1280, 720) approvals: [P: (28.0, 28.0), S: (240.0, 394.0)]
A7 HUD RECT (1280, 720) timer: [P: (1052.0, 140.0), S: (200.0, 56.0)]
A7 HUD RECT (1280, 720) score: [P: (1000.0, 28.0), S: (252.0, 100.0)]
A7 HUD RECT (1280, 720) pursuit countdown: [P: (1000.0, 208.0), S: (252.0, 64.0)]
A7 HUD RECT (1280, 720) boss plate: [P: (300.0, 8.0), S: (680.0, 56.0)]
A7 HUD RECT (1280, 720) intro card: [P: (300.0, 48.0), S: (680.0, 80.0)]
A7 HUD RECT (1280, 720) turn plate: [P: (460.0, 536.0), S: (360.0, 76.0)]
A7 HUD RECT (1280, 720) toast: [P: (306.0, 172.0), S: (668.0, 38.0)]
A7 HUD RECT (1280, 720) speed: [P: (964.0, 620.0), S: (288.0, 72.0)]
A7 HUD RECT (1280, 720) pursuit alert: [P: (28.0, 484.0), S: (420.0, 196.0)]
A7 HUD RECT (1440, 900) approvals: [P: (28.0, 28.0), S: (240.0, 290.0)]
A7 HUD RECT (1440, 900) timer: [P: (1212.0, 140.0), S: (200.0, 56.0)]
A7 HUD RECT (1440, 900) score: [P: (1160.0, 28.0), S: (252.0, 100.0)]
A7 HUD RECT (1440, 900) pursuit countdown: [P: (1160.0, 208.0), S: (252.0, 64.0)]
A7 HUD RECT (1440, 900) boss plate: [P: (380.0, 8.0), S: (680.0, 56.0)]
A7 HUD RECT (1440, 900) intro card: [P: (380.0, 48.0), S: (680.0, 80.0)]
A7 HUD RECT (1440, 900) turn plate: [P: (540.0, 536.0), S: (360.0, 76.0)]
A7 HUD RECT (1440, 900) toast: [P: (386.0, 172.0), S: (668.0, 38.0)]
A7 HUD RECT (1440, 900) speed: [P: (1124.0, 800.0), S: (288.0, 72.0)]
A7 HUD RECT (1440, 900) pursuit alert: [P: (28.0, 664.0), S: (420.0, 196.0)]
A7 UI CENSUS: canvas_items=217; 3D draws=0; mesh triangles=0; procedural textures=0; portrait viewport=256x256; UI draw/triangle cap=n/a
ASSET A7: PASS (1245 checks)

EXIT 0

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/runner_visual_smoke.log --script res://tests/runner_visual_smoke.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
INTERPOLATION OPT-OUT: PASS (137 nodes)
SPIKE: renderer=gl_compatibility scale=0.5 glow_threshold=0.75 fog=22..88 particles=320
RUNNER DEV SCENES: PASS (12 scenes)
TURN CAMERA ALIGNMENT: direction=-1 p=0.3 angle=10.620 degrees
TURN CAMERA ALIGNMENT: direction=-1 p=0.5 angle=10.620 degrees
TURN CAMERA ALIGNMENT: direction=-1 p=0.7 angle=10.620 degrees
TURN CAMERA ALIGNMENT: direction=+1 p=0.3 angle=10.620 degrees
TURN CAMERA ALIGNMENT: direction=+1 p=0.5 angle=10.620 degrees
TURN CAMERA ALIGNMENT: direction=+1 p=0.7 angle=10.620 degrees
CORRIDOR DRAW CENSUS: rest=13; mid-turn=16 (headless geometry census; host GPU measurement pending)
TURN: PASS
TURN WARNING: PASS
BOSS INTRO: PASS
STAGE SEAM: PASS
BOSS DRAW CENSUS: flaky_test_swarm=11
BOSS DRAW CENSUS: merge_conflict_hydra=18
BOSS DRAW CENSUS: legacy_monolith=14
BOSS VISUALS: PASS (3 checked; peak draw census=18)
TOOLS AND PROJECTILES: PASS
HAZARD DRAW CENSUS: pr_backlog_low/ peak=7
HAZARD DRAW CENSUS: pr_backlog_high/ peak=7
HAZARD DRAW CENSUS: bug_swarm/ peak=9
HAZARD DRAW CENSUS: merge_conflict/ peak=11
HAZARD DRAW CENSUS: deprecated_pit/full peak=10
HAZARD DRAW CENSUS: deprecated_pit/two_lane peak=10
HAZARD DRAW CENSUS: laser_grid/ground peak=11
HAZARD DRAW CENSUS: laser_grid/mid peak=11
HAZARD DRAW CENSUS: laser_grid/high peak=11
HAZARD DRAW CENSUS: laser_grid/timed peak=11
HAZARD DRAW CENSUS: comment_flood/ peak=5
HAZARD DRAW CENSUS: build_shockwave/ peak=8
HAZARD CASES CHECKED: 12; summed peak draw census=111
POWER-UP VISUALS: 6 checked; reuse, collection and pause PASS
PURSUER WALL THREAT 1 MERGED VISIBLE AABB: [P: (-2.778117, 0.058948, -0.300199), S: (5.556236, 1.948992, 1.832372)]
PURSUER VISUAL: threat, catch, retreat, reuse and pause checked
HUD LEGIBILITY: PASS (60 labels checked)
PURSUIT ALERT: PASS
RUNNER UI MOCK: HUD, pursuit, pause, results, focus and save PASS
RUNNER UI REAL FACADE: autostart=false, start_run, autopilot 3s PASS
RUNNER AUDIO: 32 recipes/triggers; demo heartbeat starts=1; peak voices=10; AudioService players=2
WARNING: Runner leaderboard: this run was not written to user://test_runner_menu_leaderboard_24077.cfg (error 12); it keeps rank 0
     at: push_warning (core/variant/variant_utility.cpp:1033)
     GDScript backtrace (most recent call first):
         [0] _finish_run (res://scenes/runner/runner_game.gd:680)
         [1] _physics_process (res://scenes/runner/runner_game.gd:444)
WARNING: Runner leaderboard: cannot rename this run in user://test_runner_menu_leaderboard_24077.cfg (error 33)
     at: push_warning (core/variant/variant_utility.cpp:1033)
     GDScript backtrace (most recent call first):
         [0] submit_name (res://scenes/runner/runner_game.gd:323)
         [1] check_runner_full_loop (res://tests/runner_visual_smoke.gd:1221)
         [2] _wait_for (res://tests/runner_visual_smoke.gd:1157)
VISUAL CHECK FAILED: Codex name persists
VISUAL CHECK FAILED: temporary board contains saved run
RUNNER FULL LOOP: FAIL (menu, play, hit, pursuit, 18.0s timer recovery, hit, hit, caught, finished, game over, Codex, retry, menu, hub, default music; isolated board removed)
RUNNER VISUAL SMOKE: FAIL (2 failures)

EXIT 2

$ /Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --log-file /tmp/runner-integration-cleanup/runner_smoke.log --script res://tests/runner_smoke.gd
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: Condition "ret != noErr" is true. Returning: ""
   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)
WARNING: Runner leaderboard: this run was not written to user://smoke_leaderboard_85417.cfg (error 12); it keeps rank 0
     at: push_warning (core/variant/variant_utility.cpp:1033)
     GDScript backtrace (most recent call first):
         [0] _finish_run (res://scenes/runner/runner_game.gd:680)
         [1] _physics_process (res://scenes/runner/runner_game.gd:444)
ERROR: RUNNER SMOKE: the board write reported error 12
   at: push_error (core/variant/variant_utility.cpp:1023)
   GDScript backtrace (most recent call first):
       [0] check (res://tests/runner_smoke.gd:66)
       [1] _leaderboard_phase (res://tests/runner_smoke.gd:398)
       [2] run (res://tests/runner_smoke.gd:109)
       [3] _catch_phase (res://tests/runner_smoke.gd:385)
       [4] _wait_run_seconds (res://tests/runner_smoke.gd:801)
       [5] _wait_until (res://tests/runner_smoke.gd:820)
RUNNER SMOKE: seed 12345, elapsed 75.1 s, distance 1691 m, speed 0.0, state finished, hp 0, score 1921
  hit: t=54.15 v=25.1 deprecated_pit -> hp 1, lane 2/2 x=2.00 y=0.00 roll=false air=false reckless=0 [deprecated_pit z=-1.8 x=0.0 JUMP blocking=false]
  hit: t=73.70 v=25.3 projectile -> hp 1, lane 0/0 x=-2.00 y=0.00 roll=false air=false reckless=0 [projectile z=-0.9 x=-1.0 LANE blocking=false]
  hit: t=75.15 v=25.3 projectile -> hp 0, lane 0/0 x=-2.00 y=0.00 roll=false air=false reckless=0 [projectile z=-0.9 x=-2.0 JUMP_OR_LANE blocking=false] [projectile z=-0.9 x=2.0 JUMP_OR_LANE blocking=true]
  chunk: 0.0s d=0.00 chunk_t1_first_wall gap=0.3
  chunk: 0.0s d=0.00 chunk_t1_first_bar gap=0.0
  chunk: 0.0s d=0.00 chunk_breather_a gap=0.0
  chunk: 0.5s d=0.03 chunk_t1_first_bar gap=0.0
  chunk: 2.5s d=0.12 chunk_t1_wall_then_bar gap=0.0
  chunk: 5.6s d=0.28 chunk_t2_shockwave_rhythm gap=0.0
  chunk: 8.4s d=0.42 chunk_t2_laser_low_high gap=1.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=12.9
  chunk: 42.0s d=0.79 chunk_t4_laser_rhythm gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_pit_then_bar mirrored gap=5.4
  chunk: 42.0s d=0.79 chunk_t3_merge_swarm mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_timed_laser_intro gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_pit_run gap=5.4
  chunk: 42.0s d=0.79 chunk_t4_gauntlet mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_flood_laser mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t4_pit_run gap=14.8
  chunk: 42.0s d=0.79 chunk_t3_flood_laser mirrored gap=5.5
  chunk: 42.0s d=0.79 chunk_breather_a gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=0.0
  chunk: 43.8s d=0.88 chunk_t4_laser_rhythm gap=5.5
  chunk: 46.7s d=1.00 chunk_breather_a gap=0.0
  chunk: 47.4s d=1.00 chunk_t4_laser_rhythm gap=0.0
  chunk: 50.0s d=1.00 chunk_t4_pit_run gap=5.8
  chunk: 52.2s d=1.00 chunk_breather_a gap=0.0
  chunk: 52.9s d=1.00 chunk_t4_gauntlet gap=0.0
  chunk: 55.5s d=1.00 chunk_t4_pit_run gap=9.8
ERROR: RUNNER SMOKE: leaderboard_saved was never emitted
   at: push_error (core/variant/variant_utility.cpp:1023)
   GDScript backtrace (most recent call first):
       [0] check (res://tests/runner_smoke.gd:66)
       [1] _leaderboard_phase (res://tests/runner_smoke.gd:400)
       [2] run (res://tests/runner_smoke.gd:109)
       [3] _catch_phase (res://tests/runner_smoke.gd:385)
       [4] _wait_run_seconds (res://tests/runner_smoke.gd:801)
       [5] _wait_until (res://tests/runner_smoke.gd:820)
RUNNER SMOKE: seed 12345, elapsed 75.1 s, distance 1691 m, speed 0.0, state finished, hp 0, score 1921
  hit: t=54.15 v=25.1 deprecated_pit -> hp 1, lane 2/2 x=2.00 y=0.00 roll=false air=false reckless=0 [deprecated_pit z=-1.8 x=0.0 JUMP blocking=false]
  hit: t=73.70 v=25.3 projectile -> hp 1, lane 0/0 x=-2.00 y=0.00 roll=false air=false reckless=0 [projectile z=-0.9 x=-1.0 LANE blocking=false]
  hit: t=75.15 v=25.3 projectile -> hp 0, lane 0/0 x=-2.00 y=0.00 roll=false air=false reckless=0 [projectile z=-0.9 x=-2.0 JUMP_OR_LANE blocking=false] [projectile z=-0.9 x=2.0 JUMP_OR_LANE blocking=true]
  chunk: 0.0s d=0.00 chunk_t1_first_wall gap=0.3
  chunk: 0.0s d=0.00 chunk_t1_first_bar gap=0.0
  chunk: 0.0s d=0.00 chunk_breather_a gap=0.0
  chunk: 0.5s d=0.03 chunk_t1_first_bar gap=0.0
  chunk: 2.5s d=0.12 chunk_t1_wall_then_bar gap=0.0
  chunk: 5.6s d=0.28 chunk_t2_shockwave_rhythm gap=0.0
  chunk: 8.4s d=0.42 chunk_t2_laser_low_high gap=1.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=12.9
  chunk: 42.0s d=0.79 chunk_t4_laser_rhythm gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_pit_then_bar mirrored gap=5.4
  chunk: 42.0s d=0.79 chunk_t3_merge_swarm mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_timed_laser_intro gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_pit_run gap=5.4
  chunk: 42.0s d=0.79 chunk_t4_gauntlet mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_flood_laser mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t4_pit_run gap=14.8
  chunk: 42.0s d=0.79 chunk_t3_flood_laser mirrored gap=5.5
  chunk: 42.0s d=0.79 chunk_breather_a gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=0.0
  chunk: 43.8s d=0.88 chunk_t4_laser_rhythm gap=5.5
  chunk: 46.7s d=1.00 chunk_breather_a gap=0.0
  chunk: 47.4s d=1.00 chunk_t4_laser_rhythm gap=0.0
  chunk: 50.0s d=1.00 chunk_t4_pit_run gap=5.8
  chunk: 52.2s d=1.00 chunk_breather_a gap=0.0
  chunk: 52.9s d=1.00 chunk_t4_gauntlet gap=0.0
  chunk: 55.5s d=1.00 chunk_t4_pit_run gap=9.8
ERROR: RUNNER SMOKE: this run is not on the leaderboard
   at: push_error (core/variant/variant_utility.cpp:1023)
   GDScript backtrace (most recent call first):
       [0] check (res://tests/runner_smoke.gd:66)
       [1] _leaderboard_phase (res://tests/runner_smoke.gd:403)
       [2] run (res://tests/runner_smoke.gd:109)
       [3] _catch_phase (res://tests/runner_smoke.gd:385)
       [4] _wait_run_seconds (res://tests/runner_smoke.gd:801)
       [5] _wait_until (res://tests/runner_smoke.gd:820)
RUNNER SMOKE: seed 12345, elapsed 75.1 s, distance 1691 m, speed 0.0, state finished, hp 0, score 1921
  hit: t=54.15 v=25.1 deprecated_pit -> hp 1, lane 2/2 x=2.00 y=0.00 roll=false air=false reckless=0 [deprecated_pit z=-1.8 x=0.0 JUMP blocking=false]
  hit: t=73.70 v=25.3 projectile -> hp 1, lane 0/0 x=-2.00 y=0.00 roll=false air=false reckless=0 [projectile z=-0.9 x=-1.0 LANE blocking=false]
  hit: t=75.15 v=25.3 projectile -> hp 0, lane 0/0 x=-2.00 y=0.00 roll=false air=false reckless=0 [projectile z=-0.9 x=-2.0 JUMP_OR_LANE blocking=false] [projectile z=-0.9 x=2.0 JUMP_OR_LANE blocking=true]
  chunk: 0.0s d=0.00 chunk_t1_first_wall gap=0.3
  chunk: 0.0s d=0.00 chunk_t1_first_bar gap=0.0
  chunk: 0.0s d=0.00 chunk_breather_a gap=0.0
  chunk: 0.5s d=0.03 chunk_t1_first_bar gap=0.0
  chunk: 2.5s d=0.12 chunk_t1_wall_then_bar gap=0.0
  chunk: 5.6s d=0.28 chunk_t2_shockwave_rhythm gap=0.0
  chunk: 8.4s d=0.42 chunk_t2_laser_low_high gap=1.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=12.9
  chunk: 42.0s d=0.79 chunk_t4_laser_rhythm gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_pit_then_bar mirrored gap=5.4
  chunk: 42.0s d=0.79 chunk_t3_merge_swarm mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_timed_laser_intro gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_pit_run gap=5.4
  chunk: 42.0s d=0.79 chunk_t4_gauntlet mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t3_flood_laser mirrored gap=4.5
  chunk: 42.0s d=0.79 chunk_t4_pit_run gap=14.8
  chunk: 42.0s d=0.79 chunk_t3_flood_laser mirrored gap=5.5
  chunk: 42.0s d=0.79 chunk_breather_a gap=0.0
  chunk: 42.0s d=0.79 chunk_t4_gauntlet gap=0.0
  chunk: 43.8s d=0.88 chunk_t4_laser_rhythm gap=5.5
  chunk: 46.7s d=1.00 chunk_breather_a gap=0.0
  chunk: 47.4s d=1.00 chunk_t4_laser_rhythm gap=0.0
  chunk: 50.0s d=1.00 chunk_t4_pit_run gap=5.8
  chunk: 52.2s d=1.00 chunk_breather_a gap=0.0
  chunk: 52.9s d=1.00 chunk_t4_gauntlet gap=0.0
  chunk: 55.5s d=1.00 chunk_t4_pit_run gap=9.8
WARNING: Runner leaderboard: this run was not written to user://smoke_leaderboard_85417.cfg (error 12); it keeps rank 0
     at: push_warning (core/variant/variant_utility.cpp:1033)
     GDScript backtrace (most recent call first):
         [0] _finish_run (res://scenes/runner/runner_game.gd:680)
         [1] _physics_process (res://scenes/runner/runner_game.gd:444)
RUNNER SMOKE: FAIL (3 failures / 127 checks)

EXIT 3

```

```text
$ git diff --check
EXIT 0
```

```text
$ git status --short
 M README.md
 M docs/endless-runner.md
 M hoppys-adventure-arcade/scenes/runner/environment/hifi/prewarm.gd
 D hoppys-adventure-arcade/scenes/runner/player/hifi/forge.gd
 D hoppys-adventure-arcade/scenes/runner/player/hifi/forge.gd.uid
 M hoppys-adventure-arcade/tests/assets/prewarm_check.gd
?? docs/assets/integration-cleanup-verification.md
EXIT 0
```
