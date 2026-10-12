# Bay Area Blitz — first playable

Implemented September 20, 2026 against Godot 4.7.1. Design references: the shared GDD (Platformer Game and Main Menu), Technical Implementation Baseline §8, Agent Context, and the local Bay Area asset guide. This is an initial playable slice, not a shipping-complete platformer.

## Play

Run the project normally: **Platformer Game → Level Select → Play Bay Area Blitz**. For direct iteration, run `res://scenes/platformer/bay_area_blitz.tscn`.

- Move: A/D, left/right arrows, controller left stick or D-pad.
- Jump: Space/W/up arrow, controller A/Cross. Release early for a shorter jump.
- Swipe: J/X, controller X/Square. Landing on an enemy also deals damage and bounces Hoppy.
- Pause/resume: Escape or controller Start. Focus loss pauses the game.
- Defeat the Merge Conflict Monster, then swipe or land on the MERGE button to finish.
- Pause and results provide fresh retry, platformer menu, and arcade return.

## Implemented

A 5,300-pixel authored city route with two jumpable gaps, optional raised token routes, two moving cable-car platforms, parallax buildings/fog, supplied Golden Gate scenery, animated Hoppy, glitch critters, Request Changes Reviewers, broken pipelines, a moving conflict zone, and a three-headed boss. The safe lower route does not require waiting for a cable car.

Three-heart health, damage knockback, post-hit protection, variable jump height, coyote time, jump buffering, swipe hit deduplication, stomping, per-run score, boss-gated completion, pause/focus handling, death/retry, level selection, and the Bay Area music track are connected. The existing menu audio/background paths were repaired to match the reorganized Assets folder. Other levels remain explicitly unavailable.

All art comes from `Assets/bay-area-blitz-assets-only`; Hoppy uses that pack's existing platformer SpriteFrames. Sound uses existing project assets. No assets were generated or downloaded.

## Initial tuning (proposals)

| Setting | Value |
| --- | --- |
| Run speed / gravity / jump impulse | 310 / 1,600 / 740 pixels per second (gravity in px/s²) |
| Coyote time / jump buffer | 120 / 140 ms |
| Post-hit protection | 1.2 seconds |
| Swipe cycle | 360 ms; one hit per target |
| Critter / reviewer / boss HP | 1 / 2 / 8 |
| Token / ordinary enemy / boss score | 25 / 100 / 1,000 |
| Boss cycle | 1.6 s tracking, 0.8 s slam warning, 0.4 s slam, 0.8 s recovery, 0.7 s volley warning, volley and recovery; 6 s total |
| Shield | Blocks one hit; does not stack |
| LGTM | 5 seconds, 1.35× speed and invulnerability; refresh on pickup |
| Auto-Fix | Defeats ordinary enemies within 350 pixels; excludes boss |
| Coffee / Full Review | Restore 1 / all HP, capped at 3 |

These choices are local to this first pass and do not settle the GDD's open balance questions. No progression or scores are persisted. Falling into a gap ends the run; retries reset the whole level.

## Structure and limits

`modes/platformer/player.gd` owns movement, damage and swipe state; `enemy.gd` owns ordinary patrols; `merge_monster.gd` owns boss pursuit and attack timing; `branch_projectile.gd` owns projectile flight and hits; `art.gd` constructs shared sprite/collider resources. `scenes/platformer/bay_area_blitz.gd` owns the authored layout, pickups, hazards, moving platforms, HUD and run lifecycle. Navigation remains in AppRouter. All run state is scene-local.

Terrain uses cropped existing street sprites with matching static solids. This follows the supplied asset guide's manual-assembly option because the pack has transparent padding and no TileSet; an editor-authored TileMapLayer is a future content-authoring improvement. The distant flattened backdrop stays fixed while building and fog layers provide depth. The conflict vortex moves horizontally; randomized conflict-platform arrangements are deferred. The boss alternates tracking movement, a telegraphed slam, and an aimed three-projectile volley. Encounter balance, richer feedback and pixel cleanup remain polish work. Future level cards use dimmed placeholder art and are disabled.

## Validation

Run `Godot --headless --path hoppys-adventure-arcade --script res://tests/platformer_smoke.gd` (or omit `--headless` for screenshots in `/tmp/hoppy-*.png`). The suite covers spawn collision, jumping, buffering/coyote time, damage protection, capped healing, shield/boost, pause input, moving cable-car support, melee deduplication, enemy scoring, boss unlock, completion, fresh retry, whole-ground-route traversal, death, and music restoration.

The existing `tests/menu_smoke.gd` should run with a rendered display for its mouse-hover assertions; headless mouse dispatch does not reproduce those assertions reliably. Keyboard/gamepad action definitions are present; physical-controller feel and packaged exports still need human/device testing.

## September 21 playtest fixes

The original full jump rose only about 115 pixels in the physics simulation, below the 125-pixel street-to-platform rise near the first cable car. Jump impulse is now 740 px/s (roughly 165 pixels of usable rise), retaining variable height, coyote time and buffering. Elevated steel platforms permit jumping through from below and catch Hoppy on descent.

Both cable cars now stop at reachable low boarding positions, pause for one second at each end of a ten-second round trip, and finish near the destination ledges with room to jump off. Their roof colliders match the visible roof width; a dedicated MovingPlatform layer explicitly supplies platform velocity to Hoppy. Jumping off preserves upward/horizontal momentum without inheriting a downward pull. An in-world sign explains roof boarding.

`tests/platformer_traversal.gd` verifies street-to-platform jumps, each of the three ascending platform pairs, street-to-roof boarding of both cars, a complete round trip without input, pause, and jumping from each car onto its destination platform. It resets Hoppy to each starting street/ledge and resets the timetable to the boarding stop; boarding and disembarking use actual jump/movement inputs rather than placing Hoppy on a roof. The earlier smoke test only dropped Hoppy onto a roof and did not establish boardability.

## September 30 boss encounter

Crossing x=4300 on the ground triggers a 1.8-second intro: movement is held, the camera pans into a fixed arena, visible collision gates close at x=4180/4970, and a title banner introduces the monster. Pause freezes the intro and music fade. The boss remains inactive and invulnerable until the intro ends.

The monster tracks Hoppy at 100 px/s within x=4360–4840, committing to its attacks in place. The slam retains its ground warning and jumpable range. A second warning shows the direction of a three-shot branch volley, aimed at Hoppy at release and traveling at 320 px/s; projectiles do not home afterward. Existing conflict-zone art supplies the projectile sprites. Hits respect shields and invulnerability. Projectiles expire after four seconds or on terrain/contact, and are cleared on defeat, death, retry or scene exit.

Summer Sunday plays during normal traversal. The intro fades to c64_uptempo_chiptune, and defeating the boss restores Summer Sunday, opens the gates, and returns camera following. Music streams loop through the player's finished signal without altering shared imported resources.

The MERGE button has a one-way top aligned to its green cap. After boss defeat, either a nearby swipe or a descending landing completes the level. Standing nearby, rising through it, and landing before the boss is defeated do not complete the level.

`tests/platformer_boss.gd` covers encounter entry, inactive boss protection, intro pause, fixed camera, arena boundaries, pursuit, volley creation/damage/pause, defeat cleanup, both music transitions, landing activation, locked-exit rejection and fresh retry. Run without `--headless` for intro/volley/result screenshots under `/tmp/hoppy-boss-*.png`. Pause/resume calls in this harness are issued from a process frame, outside the physics-frame signal, to avoid the engine's documented physics-query ordering issue ([Godot issue #122378](https://github.com/godotengine/godot/issues/122378)).

### Knockout cutaway

All three platformer levels share a 3.5-second knockout cutaway for fatal hits and pit falls.
The level freezes and its HUD disappears while an enlarged Hoppy tumbles, lands, and sees
stars beneath a K.O. callout. The current level or boss music keeps playing, ducked by 12 dB,
through the existing results menu. Retry creates a fresh run; leaving restores menu audio.
Gameplay inputs cannot skip the cutaway, but can still finish the results fade once it appears.

Run `godot --headless --path hoppys-adventure-arcade --script res://tests/platformer_knockout.gd`
for all three levels, pit falls, audio continuity, retry and early-exit cleanup. Omit `--headless`
for screenshots under `/tmp/platformer-ko-*.png`. The `platformer_knockout` and
`platformer_results` scenarios in `tools/checks/exit_leak.py` cover audio shutdown during both phases.
