# Endless Runner frontend

The Codebase Corridor, F0-F7. Godot 4.7.0 results are diagnostic, pending 4.7.1 acceptance.

## Run

Run all commands from the repository root. The project pins Godot 4.7.1; the installed 4.7.0 build is diagnostic only. Graphical commands below are for the coordinator, and were not run during F6.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/runner_menu.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/runner_game.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/renderer_spike.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/environment/dev/corridor_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/player/dev/hoppy_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/hazards/visuals/dev/hazard_gallery.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --scene res://scenes/runner/ui/dev/hud_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --script res://scenes/runner/environment/dev/capture_previews.gd
```

Development cameras use (0,4,8), looking at (0,1,-8), FOV 60. The menu camera uses (2.6,1.9,3.4), looking at (0,1,-2), FOV 55 with a slow drift. The `capture_previews.gd` runner_menu fixture writes `docs/previews/endless-runner-menu.png`; the coordinator recaptured it on the host with Hoppy at (0.7, 0, -0.3), and the preview is committed.

| Scene | Keys | Action |
| --- | --- | --- |
| HUD preview | H / P / Esc | Hit / collect Nitro / toggle pause; the 40 s demo runs automatically |
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

## Behavior and ownership

F0-F6 introduced the runner menu, routed full-loop integration, capture fixture and documentation. F7 adds the legibility and pursuit presentation described below.

The hub routes to `RunnerMenu`, a Node3D with Backdrop and Interface children. The backdrop mounts the existing corridor at 3.5 m/s and Hoppy in run at normalized speed 0.25. Hoppy stands at (0.7, 0, -0.3), facing -Z with feet at y=0, in the gap between the buttons and controls card. The camera remains at (2.6, 1.9, 3.4), looking at (0, 1, -2), with its existing slow drift. A shaded 1280x720 composition uses the hub Style helpers, mint eyebrow, cream title, numbered buttons, controls card and footer. It centers in larger viewports and scales to fit smaller ones. Play owns initial focus; Up/Down and Tab wrap through the four buttons. Leaderboard reads `runner_leaderboard.gd.load_entries()` without a game instance, shows ten rank/name/score/mm:ss rows with `---` placeholders, disables the other three menu buttons while keeping Leaderboard enabled and focusable, and initially focuses Close. Pressing Leaderboard again closes the panel. Closing restores Leaderboard focus. `ui_cancel` closes the panel first, otherwise returns to the hub.

The menu calls the AppRouter singleton directly: Play -> `go("runner_game")`, Return/cancel -> `go("hub")`, Quit -> `quit_game()`. Local singleton references allow standalone `--check-only`. In gameplay, overlays call only facade `pause()`, `resume()`, `retry()`, `go_to_menu()`, and `submit_name(name)`. Backend owns physics, collisions, recovery, score, persistence, routes and shared audio. The frontend milestones changed no backend files or project settings. The backend contract PR added the runner [input], [layer_names] and physics_interpolation entries to project.godot.

HUD is on layer 10, PauseMenu 21 and GameOver 22. HUD listens to facade signals, uses responsive margins, counts up score, displays effects and pursuit, dims on pause and hides gameplay widgets on caught. Backend owns damage camera shake. Pause has no ui_cancel handler. Game Over appears only on run_finished, shows result stats and the local top ten, and saves qualifying names through the facade. Save success locks the name field and focuses Retry; failure stays editable. Retry creates a fresh scene. The mock scene demonstrates the same signals in 40 seconds with in-memory persistence.

Hoppy supplies seven animations and every player visual hook, retains feet at y=0, stands 1.8 m and rolls within 0.9 m. Hurt returns to previous locomotion unless interrupted. Hazards implement all eight kinds and every variant; collision artwork stays within the 110% envelope, while ground projections use exact hitbox footprints. Power-ups supply six types with spin/bob/collection reactions. The pursuer uses threat-driven cards, a 1.4 s catch and 0.7 s retreat. Shared resources are duplicated before mutation. Cosmetic clocks and particles inherit pause.

The corridor scrolls shaders and recycles 24 pillars over 96 m. Its per-viewport ownership stack restores the previous 3D scale and scaling mode after overlapping menu/game corridors exit. The backend replaces its graybox environment with the mounted corridor. Standalone development fixtures are frontend-owned; tests other than runner_visual_smoke.gd remain backend-owned.

## Art direction and replacement points

The navy environment and dim MATRIX grid/rain reuse the hub preview palette and perspective motif. Lanes are centered at x -2/0/+2, bounded by lines at x +/-1 and +/-3. F3 hazards use hot DANGER/ORANGE accents; power-ups use MINT icons, rings, sparkles and billboard tags. The pursuer uses NAVY cards turning DANGER with threat. Material cache results must be duplicated before mutation.

| Visual | Source | Licence | Replace-by |
| --- | --- | --- | --- |
| Hoppy primitives, animations, and effects | scenes/runner/player/hoppy_runner_visual.gd; original project source. To swap the model, replace `_build_model()` under `Root/Model`, retain the feet origin, -Z facing and 1.8 m height, remap `_pose_clip()` tracks to the new rig, and preserve the scene root, six hooks, effects, and animation names. Re-run the smoke bounds checks and host preview, including the 0.9 m roll. | Original project source | Rigged glTF via the model-swap procedure below. |
| pr_backlog_low | `scenes/runner/hazards/visuals/pr_backlog_low_visual.gd` + shared `hazard_art.gd`: Three rows of navy PR cards, orange/red strips, wobble, hit scatter/fade and mint shrink; AUTO-FIXED. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| pr_backlog_high | `scenes/runner/hazards/visuals/pr_backlog_high_visual.gd` + shared `hazard_art.gd`: Rail and hanging stale/CI cards, sway, hit drop/bounce, mint shrink; exact red footprint plus inset green safe-gap quad. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| bug_swarm | `scenes/runner/hazards/visuals/bug_swarm_visual.gd` + shared `hazard_art.gd`: Red core, six legs, 36 atlas glyph particles, leg jitter and core pop; throw new Error(). | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| merge_conflict | `scenes/runner/hazards/visuals/merge_conflict_visual.gd` + shared `hazard_art.gd`: HEAD and feature slabs, matrix/lilac strips, pulsing zigzag seam, shake and merged mint box; MERGED. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| deprecated_pit | `scenes/runner/hazards/visuals/deprecated_pit_visual.gd` + shared `hazard_art.gd`: Full and two_lane widths, dark floor, striped rim, falling glyphs, flat deprecated/since labels, rim flash and REMOVED. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| laser_grid | `scenes/runner/hazards/visuals/laser_grid_visual.gd` + shared `hazard_art.gd`: Ground, mid, high and timed; short posts/caps, three additive beams, bounded mint scanner, hit sparks and beam retraction; SCAN PASSED. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| comment_flood | `scenes/runner/hazards/visuals/comment_flood_visual.gd` + shared `hazard_art.gd`: Scrolling speech cards, red translucent volume, burst/fade and fold; one BLOCKING // TODO hero label, RESOLVED. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| build_shockwave | `scenes/runner/hazards/visuals/build_shockwave_visual.gd` + shared `hazard_art.gd`: Elliptical flat torus, red core and shards, ring pulse, white impact and mint fixed reaction; BUILD FIXED. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| approve_shield | `scenes/runner/powerups/visuals/approve_shield_visual.gd` + shared `power_up_art.gd`: Hexagonal mint shield and cream check; APPROVED. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| auto_fix | `scenes/runner/powerups/visuals/auto_fix_visual.gd` + shared `power_up_art.gd`: Mint wrench and cream bolt; AUTO-FIX. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| lgtm | `scenes/runner/powerups/visuals/lgtm_visual.gd` + shared `power_up_art.gd`: Emissive LGTM TextMesh; 5s. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| nitro | `scenes/runner/powerups/visuals/nitro_visual.gd` + shared `power_up_art.gd`: Capsule commit, cream plus, mint flame stream; NITRO COMMIT. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| super_jump | `scenes/runner/powerups/visuals/super_jump_visual.gd` + shared `power_up_art.gd`: Mint coin and cream ^^; SUPER JUMP. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| code_review | `scenes/runner/powerups/visuals/code_review_visual.gd` + shared `power_up_art.gd`: Mint magnifier and cream handle; CODE REVIEW ×1.5. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| Power-up tags (all six) | Shared `power_up_art.gd`: tags are approximately 0.2 m tall and up to 1.3 m wide, extend beyond the r 0.35 pickup sphere by design, and stay inside the 2 m lane pitch. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| Unreviewed PR Backlog pursuer | `scenes/runner/pursuer/pursuer_visual.gd`: 5×4 MultiMesh cards, six cream headlines, two angry eye slits, one red light, glyph glitch particles and radial haze; threat, catch and retreat hooks. Headlines retain `label.scale.x = 0.65` (compressed to 65% width); the pixel-size increase applies to height only. The coordinator's host capture confirms legibility. | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| Corridor primitives and particles | scenes/runner/environment/corridor.gd | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| Glyph atlas | scenes/runner/shaders/glyph_atlas.gd | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| Grid, wall, hologram, radial glow, vignette | scenes/runner/shaders/*.gdshader | Original project source | Replace artwork within the existing visual root; retain contract hooks, bounds and pause behavior. |
| Labels | SystemFont fallback matching menu_style.gd | Installed font licences; no font redistribution | Licensed bundled font through Style.theme() and runner_materials.gd. |
| Runner menu, leaderboard and controls card | `scenes/runner/runner_menu.gd`, shared `menu_style.gd` | Original project source; installed font licences | Replace composition and Style resources; preserve RunnerMenu root, routes, focus loop and modal cancel behavior. |
| HUD, approval pips, pursuit ring, power-up bars and toasts | `scenes/runner/ui/runner_hud.gd`, `hud_glyph.gd` | Original project source | Replace cosmetic widgets; retain facade signals and responsive anchors. |
| Pause and game-over panels, local score rows and name entry | `scenes/runner/ui/pause_menu.gd`, `game_over.gd` | Original project source | Replace layout; preserve facade methods, focus, qualifying saves and run_finished timing. |
| F5 procedural SFX | `scenes/runner/audio/sfx_synth.gd` | Original project source | Replace cached PCM recipes; keep trigger mapping, SFX bus and ten-voice cap. |
| F5/F6 Cyberpunk Street BGM | `Assets/cyberpunk-street-files/Assets/music/cyberpunk-street.ogg`, bundled `public-license.pdf`, Luis Zuno / ansimuz package | CC0; PDF does not identify composer | Replace the shared menu/audio track together; retain AudioService music ownership and loop import. |

See `hoppys-adventure-arcade/Assets/runner/LICENSES.md` for the asset inventory.


Model swap procedure: import the licensed glTF under `Assets/runner/` and add its creator, source, licence and modifications to `Assets/runner/LICENSES.md`. Replace `_build_model()` contents under `Root/Model`, retaining the scene root, feet at y=0, facing -Z and standing height 1.8 m. Remap `_pose_clip()` animation tracks to the new rig with the same idle/run/jump/fall/roll/hurt/dead names. Keep the six visual hooks, independent shield/aura and material duplication rules. Sample the complete roll clip at y<=0.9 m, then rerun visual smoke and the coordinator's Hoppy/gameplay captures before accepting the swap.

## Audio

F5 audio is implemented and verified through visual smoke coverage of procedural synth cues and the hard polyphony cap of 10. `runner_audio.tscn` / `runner_audio.gd` provide `RunnerAudio`, a `Node` with `process_mode ALWAYS` and an idempotent `bind(game)` that disconnects its previous facade. The backend already mounts this scene. Pause signals suspend SFX playback, footstep timing and drone fades. Scene teardown disconnects signals, stops voices and restores music pitch to 1.0. The runner menu uses the same cached track through guarded AudioService.play_music(..., -12.0); menu to game preserves the stream, and AppRouter restores the default hub track. Focus and hover use play_ui(0); confirm and close use play_ui(1).

All SFX use cached, deterministic 16-bit 22050 Hz PCM built in `sfx_synth.gd`, following the shared service's tone synthesis pattern. Attack/decay envelopes bound every sample to at most 0.8 full scale. Lane sounds use stereo panning; other sounds are mono. These are original project recipes, with no downloads.

| SFX | Trigger | Recipe |
| --- | --- | --- |
| footstep | Running, grounded and not rolling | 70 ms noise/sine thud, 140 to 65 Hz |
| jump | jump or super_jump action | 220 ms square/sine rise, 240 to 880 Hz |
| land | land action | 130 ms noise/sine thump, 180 to 45 Hz |
| roll | roll action | 280 ms noise sweep, 320 to 80 Hz |
| lane_left / lane_right | Corresponding lane action | 120 ms saw/sine sweep; left/right channel gain 1.0 versus 0.2 |
| powerup | Every power_up_collected | 240 ms sine rise, 660 to 1320 Hz |
| nitro | Nitro pickup, after powerup | 650 ms saw rise, 110 to 880 Hz |
| lgtm | LGTM pickup, after powerup | 650 ms ascending major chord |
| auto_fix | Auto-Fix pickup, after powerup | 380 ms square descent, 1320 to 330 Hz |
| shield_block | damage_blocked, all contract reasons | 300 ms metallic major chord |
| hit | damage_taken | 300 ms noise/sine impact; also duck_music(-6, 0.4) |
| pursuit_start | pursuit_started | 750 ms descending square alarm |
| pursuit_drone | pursuit_started | Seamless 2 s loop, 55/57 Hz beating sine; fade in 0.4 s |
| heartbeat | First pursuit_progress with remaining/total below 0.35 | 1 s loop with two decaying 65 Hz pulses |
| retreat | pursuit_recovered | 500 ms descending saw |
| recovered_chime | pursuit_recovered, with retreat | 700 ms ascending major chord |
| caught | caught | 850 ms low noise/sine boom |
| game_over | run_finished | 1.2 s falling major chord |

All four players route to `SFX`: OneShots uses AudioStreamPolyphonic with exactly seven slots, plus one voice each for Footsteps, Drone and Heartbeat. Total runner SFX capacity is ten, excluding shared music/UI audio. When a start fails at capacity, the new cue enters a deduplicated pending queue. Important cues retry first and may evict the oldest ambient voice; ambient cues never evict voices. Slots released for important retries are reserved until those retries play or expire. Slots become reusable on a later audio mix; retries run at the top of processing. Ambient pending cues expire after 120 ms of unpaused game time and important cues after 300 ms. Identical sounds have a 40 ms game-time retrigger gate, advanced by unpaused process delta. Only successful starts update the gate and emit the playback signal. `sound_played(kind, stream)` fires only after a successful playback start; `active_voice_count()` supports verification.

Footstep cadence is `lerp(0.42, 0.20, clamp(normalized, 0, 1))` seconds. Jump/super_jump and land track grounded state; roll/roll_end suppress steps without falsely grounding an airborne player. Heartbeat has an explicit latch reset on pursuit_started, starts once below the threshold, and stops on recovery, catch or finish. Recovery/catch fade the drone out over 0.3 s; finish stops it immediately.

BGM is the existing `res://Assets/cyberpunk-street-files/Assets/music/cyberpunk-street.ogg`, loop enabled in its `.ogg.import` settings without runtime stream mutation, passed to `AudioService.play_music(stream, -12.0)` during bind. The shared player routes it to `Music`. Attribution: Luis Zuno / ansimuz, CC0 per `Assets/cyberpunk-street-files/public-license.pdf`, no modifications. The PDF does not name the music's composer. The exact asset row and caveat are in `Assets/runner/LICENSES.md`.

Pitch approaches `1.0 + 0.10 * normalized + (0.05 while Nitro)` with exponential smoothing `1 - exp(-5 * delta)` via `AudioService.set_music_pitch`. Normalized speed can exceed 1 during Nitro; only footstep cadence clamps it. Nitro expiry removes the extra 0.05. Calls to the shared service are guarded with `has_method`; it retains its existing two players.

## Renderer notes: gl_compatibility

The following gl_compatibility findings come from the coordinator's graphical capture and visual inspection on the installed Godot 4.7.0 stable (`4.7.stable.official.5b4e0cb0f`). They supersede the earlier headless-only findings. The project pins 4.7.1, where final acceptance must be re-run under the contract's engine version policy.

| Feature | Configuration | Observed result |
| --- | --- | --- |
| Glow | enabled; intensity 0.9, bloom 0.12, HDR threshold 0.75, HDR scale 2.0 | OK: bloom is visible on emissive objects in the spike. |
| Fog | depth mode, begin 22, end 88, NAVY_BG | OK: depth fog is visible. |
| scaling_3d_scale | bilinear, 0.5 | OK: the retro downscale is visible; ownership and restoration are covered by the environment check. |
| Particles | GPUParticles3D, 8x8 glyph billboard atlas, no trails/collision/subemitters | OK: glyph rain is visible. Pause inheritance is covered headlessly. |
| Corridor draw budget | `capture_previews.gd`, `corridor_preview` at 26 m/s; two lights, shadows off, preview UI hidden | PASS: 10 / 15 draw calls in the `CORRIDOR DRAW BUDGET` frame sample. |
| Corridor screenshot sample | `capture_previews.gd`, `corridor_preview` at its default 12 m/s with preview UI visible, before the 26 m/s budget check | 9 draw calls in the `CAPTURE: corridor` frame sample; this is the corridor figure in the host `PREVIEW CAPTURE` summary below. Neither frame sample is a measured peak. |
| Renderer diagnostic fixture | `capture_previews.gd`, separate `renderer_spike` scene | 23 draw calls in the `CAPTURE: spike` frame sample; separate from the corridor budget. |
| Previews | 1280x720 PNGs | Present: docs/previews/endless-runner-spike.png, docs/previews/endless-runner-corridor.png, docs/previews/endless-runner-hoppy.png, docs/previews/endless-runner-gallery.png, docs/previews/endless-runner-powerups.png, docs/previews/endless-runner-pursuer.png, and docs/previews/endless-runner-menu.png. All previews are captured on the host; the sandbox cannot render. |

The shaders provide their own grid/wall depth fading and additive halos. Unsupported renderer effects are not configured. The implementation avoids the Compatibility-ignored glow-level/normalized/strength/blend settings specified in the brief.

## Verification

The visual smoke gate exercises all five milestone dev scenes plus any additional `scenes/runner/**/dev/*.tscn` discovered at runtime headless, checks runtime errors and pause/viewport-scale restoration, and prints `RUNNER DEV SCENES: PASS (<n> scenes)` only when this section succeeds.

F0-F6 are implemented. The coordinator re-ran the unmodified tests on the host with this tree on Godot 4.7.0 (`4.7.stable.official.5b4e0cb0f`), 2026-09-19. These results supersede the earlier sandbox transcripts and remain diagnostic pending final acceptance on Godot 4.7.1.

Verbatim host result lines:

```text
RUNNER FULL LOOP: PASS (menu, play, hit, pursuit, 18s timer recovery, hit, hit, caught, finished, game over, Codex, retry, menu, hub, default music; isolated board removed)
RUNNER VISUAL SMOKE: PASS (0 failures)
RUNNER SMOKE: PASS (0 failures / 64 checks)
RUNNER SCAFFOLD: PASS (0 failures / 284 checks)
MENU SMOKE: FAIL (2 failures)
PREVIEW CAPTURE: PASS (spike 23 / corridor 9 / hoppy 33 / gallery 162 / menu 33 draw calls; hud, gameover captured)
```

The backend's scaffold update is complete: `runner_scaffold_check.gd` asserts `buttons.size() == 4`, including Leaderboard, and all 284 checks pass on this branch. The headless menu_smoke failures on Godot 4.7.0 are tracked as a non-blocking baseline: `Mouse hover overrides old gamepad focus` and `Pointer exit releases mode preview`.

The full-loop smoke attaches a node_added guard before routing, sets autostart=false and a per-process `user://test_runner_menu_leaderboard_%d.cfg` path before each RunnerGame._ready(), and starts each scene with autopilot. Retry receives the override again. It forces hits through the real hit manager, waits for the unchanged 18 s recovery timer and catch sequence, checks run_finished and visible game over, saves Codex, retries, returns through RunnerMenu to MainMenu, checks default music restoration, and deletes temporary board/backup files. The UI facade smoke uses a separate `user://test_runner_visual_smoke_%d.cfg` path with the same cleanup. Neither test writes the real `user://leaderboard.cfg`.

## Requests to backend

None outstanding for these findings. The scaffold now checks the F6 four-button menu, including Leaderboard, and accepts the mounted corridor (284 checks PASS).

## Known gaps

F0-F6 implementation is complete. The Hoppy menu recapture at (0.7, 0, -0.3) is committed, and the backend's scaffold four-button assertion is complete (284 checks PASS).

Required: final acceptance on the pinned Godot 4.7.1, which the briefs' acceptance scripts gate on.

Tracked non-blocking baseline: the two documented headless menu_smoke hover failures on Godot 4.7.0 listed above.

## F7: HUD legibility and pursuit transmission

F7 adds runner-owned `ui/hud_style.gd`, applying navy outlines of `max(6, round(size * 0.30))`, a hard two-unit navy shadow, and navy backing panels. The four UI scripts use it without changing the shared menu style. The original 14-unit labels rendered at 10.5 physical pixels at the 960x540 minimum window; the larger type and backing reduce interference from the moving corridor.

All sizes below are base units at 1280x720. Backing colours name the border; panel fill is NAVY_BG.

| Widget | Before | F7 | Backing |
| --- | --- | --- | --- |
| Approvals header / pips | 14 / 42x46 | 18 / 48x52, hex stroke 3 | MINT, alpha 0.82, shared cluster |
| Power-up name / bar | 14 / 90x6 | 18 / 112x9 | Inside approvals panel |
| Time | 24 | 30, monospace | SLATE, alpha 0.70, width 200 |
| Score / multiplier | 32 / 20 | 36 / 24 | MINT, alpha 0.82, width 300 |
| Speed label / bar | 17 / 240x8 | 20 / 260x12, 2-unit tick at 26 m/s | SLATE, alpha 0.70 |
| Pursuit label / ring | 16 / 36x36, strokes 3-4 | 22 / 56x56, radius 24, strokes 5/6/3, centre number 20 | DANGER panel; navy disc alpha 0.85 |
| Toast | 24 | 28, maximum 26 characters | Auto-width panel, border by message kind |
| Nitro | 30 | 34 | ORANGE panel |
| Get Ready | 22 throughout | Title 34, controls 22 | Centred NAVY_BG alpha 0.88 panel |
| Pause title / hint | 40 / 16 | 46 / 20; buttons retain theme size | Existing panel |
| Game over title / stats / rows / error | 30 / 18 / 16 / 14 | 34 / 22 / 19 / 17 | Existing panel, minimum 760x620 |

Integral multipliers omit decimals; fractional multipliers retain their value. Timed power-up names disappear after 0.6 seconds, leaving distinct compact symbols and bars. Get Ready holds for 2.5 seconds then fades over 0.25 seconds. Toasts fade in over 0.12 seconds, preserve preempted entries, and prioritize INCOMING/STAGE CLEAR above recovery/blocked and bonus messages. Nitro and Get Ready yield to an active toast. The toast sits above the lane-reading band. The alert retains the design's explicit bottom-left placement at (28, -236), size 420x196. The catch-rule caption at 17 and static game-over error at 17 are explicit design exemptions from the 18-unit critical-label floor; both retain outlines and backing.

`ui/pursuit_alert.tscn` is PAUSABLE and works standalone or as a child of HUD widgets. Its `bind(game)` returns immediately for the same game and disconnects the previous facade on a different binding. It conditionally connects the optional `pursuit_alert` signal, using the contract's `warn` kind as a hint; v1 pursuit_started/progress/recovered, damage_blocked and caught signals fully drive the presentation. The mock additionally emits `warn`, `critical`, and `clear` without making those events mandatory for the UI.

The panel uses a cubic ease-out slide from x=-440 to 28 over 0.28 seconds, an initial 0.08-second cream flash, a procedural 256x256 2D SubViewport portrait sharing the pursuer's HEADLINES, clock-driven scanlines/chromatic displacement/roll bar, 48 waveform bars, an 88x88 radar and a live countdown. The catch rule reads "ONE MORE HIT BEFORE RECOVERY AND IT HAS YOU". Recovery holds RECOVERED / BACKLOG REVIEWED / +2 APPROVALS for 1.2 seconds with MATRIX accents, then exits over 0.22 seconds. A blocked hit flashes MINT and BLOCKED for 0.6 seconds. Catch hides the gameplay siblings while the portrait fills the panel and grows to 1.35 over 0.45 seconds, then slides out. Both tree pause and the mock's facade pause freeze clocks and motion; no pause-sensitive shader uses TIME.

Accepted layout exception: the alert panel at (28, -236), sized 420×196, intrudes approximately 34 units into the design's no-new-widgets band. The coordinator accepts this because the bottom-left corner is outside the lane reading zone.

The pursuer gains one additive DANGER torus draw, repeating from scale 1 to 3.4 over 1.6 to 0.45 seconds by threat. Its maximum pulse radius is 2.6 m at y=1.2, retreat hides it, and catch runs three pulses in 0.35 seconds. The vignette now uses strength `0.25 + 0.6 * (1 - fraction)` and top/bottom danger bars advancing by `(1 - fraction) * 0.06` of viewport height; recovery/reset clears them.

Audio now has 21 deterministic cached PCM recipes. `alert_sting` is a high-priority 0.55-second 180 Hz square cue gated three times at 9 Hz. `radar_pulse` is a 0.5-second loop with a 40 ms 1200-to-900 Hz sine blip. It uses Heartbeat, with pitch 0.8 to 1.6 by threat, and switches that same player to heartbeat at fraction strictly below 0.35 with a pitch drop to 0.8. The alert samples RunnerAudio's sweep clock in either the direct mock mount or the backend Audio mount. The audio loop seeks at each visual revolution and silences the remainder after the blip so the specified sweep-rate and pitch curves do not create unsynchronized extra pulses. Without audio, the alert uses its own pause-frozen clock. Recovery retains the existing recovered_chime. Seven polyphonic one-shots plus three dedicated players still cap runner voices at ten; AudioService retains two players.

`ui/dev/pursuit_alert_preview.tscn` repeats a 28-second start/progress/blocked/recovered/caught sequence with audio. Space or the pause action pauses the running preview. It is included in automatic dev-scene discovery. No graphical scenes were launched or previews captured during this implementation.

### F7 verification

The installed engine is `4.7.stable.official.5b4e0cb0f`, so these are diagnostic results, not pinned 4.7.1 acceptance. The smoke adds a dynamic 39-label census including result rows, outline/backing checks, priority/toast/fade checks, an idempotent alert binding check, v1-only standalone fallback, radar-rate/countdown/pause checks, resolution beats, and audio stream handover/shared-phase/voice checks. The headless renderer verifies viewport size, 2D mode and texture wiring; actual portrait pixels, 960x540 legibility and draw batching require the coordinator's host capture.

Coordinator-supplied host results, verbatim (Godot 4.7.0, diagnostic):

```text
RUNNER DEV SCENES: PASS (6 scenes)
HUD LEGIBILITY: 39 labels checked
PURSUIT ALERT: PASS
RUNNER UI MOCK: HUD, pursuit, pause, results, focus and save PASS
RUNNER AUDIO: 21 recipes/triggers; demo heartbeat starts=1; peak voices=10; AudioService players=2
RUNNER FULL LOOP: PASS (...)
RUNNER VISUAL SMOKE: PASS (0 failures)
RUNNER SMOKE: PASS (0 failures / 74 checks)
```

These host results supersede the earlier sandbox persistence failures. They are supplied verification evidence, not a new run from this worktree. The portrait now uses UPDATE_ALWAYS and a viewport-wide BackBufferCopy between the art and scanline overlay; the smoke asserts the update mode and copy wiring. Its shader clock remains GDScript-driven and frozen on pause.

### F7 requests to backend and coordinator

No backend code change is required for F7. The optional future standalone alert mount may call bind(game) repeatedly. Keep emitting the existing v1 pursuit signals; the frontend guards the optional v2 signal. All changes remain within frontend-owned paths.

Coordinator: run final acceptance on Godot 4.7.1 and capture the pursuit alert plus refreshed HUD/gameplay at 960x540. The headless sandbox cannot provide that visual acceptance evidence.
