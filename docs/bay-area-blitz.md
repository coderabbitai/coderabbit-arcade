# Bay Area Blitz — first playable

Implemented September 20, 2026 against Godot 4.7.1. Design references: the shared GDD (Platformer Game and Main Menu), Technical Implementation Baseline §8, Agent Context, and the local Bay Area asset guide. This is an initial playable slice, not a shipping-complete platformer.

## Play

Run the project normally: **Platformer Game → Level Select → Play Bay Area Blitz**. For direct iteration, run `res://scenes/platformer/bay_area_blitz.tscn`.

- Move: A/D, left/right arrows, controller left stick or D-pad.
- Jump: Space/W/up arrow, controller A/Cross. Release early for a shorter jump.
- Swipe: J/X, controller X/Square. Landing on an enemy also deals damage and bounces Hoppy.
- Pause/resume: Escape or controller Start. Focus loss pauses the game.
- Defeat the Merge Conflict Monster, then swipe the MERGE button to finish.
- Pause and results provide fresh retry, platformer menu, and arcade return.

## Implemented

A 5,300-pixel authored city route with two jumpable gaps, optional raised token routes, two moving cable-car platforms, parallax buildings/fog, supplied Golden Gate scenery, animated Hoppy, glitch critters, Request Changes Reviewers, broken pipelines, a moving conflict zone, and a three-headed boss. The safe lower route does not require waiting for a cable car.

Three-heart health, damage knockback, post-hit protection, variable jump height, coyote time, jump buffering, swipe hit deduplication, stomping, per-run score, boss-gated completion, pause/focus handling, death/retry, level selection, and the Bay Area music track are connected. The existing menu audio/background paths were repaired to match the reorganized Assets folder. Other levels remain explicitly unavailable.

All art comes from `Assets/bay-area-blitz-assets-only`; Hoppy uses that pack's existing platformer SpriteFrames. Sound uses existing project assets. No assets were generated or downloaded.

## Initial tuning (proposals)

| Setting | Value |
| --- | --- |
| Run speed / gravity / jump impulse | 310 / 1,600 / 620 pixels per second (gravity in px/s²) |
| Coyote time / jump buffer | 120 / 140 ms |
| Post-hit protection | 1.2 seconds |
| Swipe cycle | 360 ms; one hit per target |
| Critter / reviewer / boss HP | 1 / 2 / 8 |
| Token / ordinary enemy / boss score | 25 / 100 / 1,000 |
| Boss cycle | 1.7 s idle, 0.8 s warning, slam, recovery; 3.4 s total |
| Shield | Blocks one hit; does not stack |
| LGTM | 5 seconds, 1.35× speed and invulnerability; refresh on pickup |
| Auto-Fix | Defeats ordinary enemies within 350 pixels; excludes boss |
| Coffee / Full Review | Restore 1 / all HP, capped at 3 |

These choices are local to this first pass and do not settle the GDD's open balance questions. No progression or scores are persisted. Falling into a gap ends the run; retries reset the whole level.

## Structure and limits

`modes/platformer/player.gd` owns movement, damage and swipe state; `enemy.gd` owns patrols and the initial boss pattern; `art.gd` constructs shared sprite/collider resources. `scenes/platformer/bay_area_blitz.gd` owns the authored layout, pickups, hazards, moving platforms, HUD and run lifecycle. Navigation remains in AppRouter. All run state is scene-local.

Terrain uses cropped existing street sprites with matching static solids. This follows the supplied asset guide's manual-assembly option because the pack has transparent padding and no TileSet; an editor-authored TileMapLayer is a future content-authoring improvement. The distant flattened backdrop stays fixed while building and fog layers provide depth. The conflict vortex moves horizontally; randomized conflict-platform arrangements are deferred. The boss has one telegraphed slam pattern; further patterns, encounter balance, richer feedback and pixel cleanup remain polish work. Future level cards use dimmed placeholder art and are disabled.

## Validation

Run `Godot --headless --path hoppys-adventure-arcade --script res://tests/platformer_smoke.gd` (or omit `--headless` for screenshots in `/tmp/hoppy-*.png`). The suite covers spawn collision, jumping, buffering/coyote time, damage protection, capped healing, shield/boost, pause input, moving cable-car support, melee deduplication, enemy scoring, boss unlock, completion, fresh retry, whole-ground-route traversal, death, and music restoration.

The existing `tests/menu_smoke.gd` should run with a rendered display for its mouse-hover assertions; headless mouse dispatch does not reproduce those assertions reliably. Keyboard/gamepad action definitions are present; physical-controller feel and packaged exports still need human/device testing.
