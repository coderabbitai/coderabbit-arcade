# Orbital Ops — v1 playable

Implemented October 1, 2026 in Godot 4.7.1. Source references: the current shared GDD's Platformer Game and Main Menu sections, Technical Implementation Baseline §8, Agent Context, the Orbital asset guide, and Bay Area Blitz's traversal and boss playtest fixes.

## Play

Launch the project, choose **Platformer Game → Level Select → Play Orbital Ops**. Direct scene: `res://scenes/platformer/orbital_ops.tscn`.

- Move: A/D, left/right arrows, gamepad stick or D-pad.
- Jump: Space/W/up, gamepad A/Cross. Release early for a shorter normal-gravity jump.
- Swipe: J/X, gamepad X/Square. Descending onto an enemy also damages it and bounces Hoppy.
- Zero-gravity bay: hold Jump/Up to rise, Down/S or stick/D-pad down to descend, release vertical input to brake. Normal gravity resumes outside the cyan boundaries.
- Pause: Escape/Start or the Pause button. Focus loss also pauses.
- Defeat the Deprecated API, then land on or swipe the green MERGE button. Retry always starts a fresh Orbital Ops run; return buttons lead to the platformer menu or arcade.

## Level and combat

A 5,300-pixel station route includes upper one-way decks, two gaps, a service shuttle, six ordinary enemies, three timed CI lasers, three vacuum vents, a marked zero-gravity bay, pickups, and a gated boss arena. The shuttle uses Bay Area's ten-second round-trip timetable with one-second endpoint stops, dedicated moving-platform collision layer, and upward/horizontal dismount velocity inheritance. The main route does not require riding it.

Lasers cycle through 2.0s off, 0.9s amber warning, 1.6s red active, and 0.7s cooldown. Wait for a safe phase before crossing; only active beams damage. Vents use the same phase lengths with different offsets, pull nearby Hoppy down and toward the grille, and damage on contact with the active grille. Their amber warnings are safe. Damage respects the same shields and invulnerability as Bay Area.

Rogue AI bots have 2 HP, patrol locally, warn for 0.75s, and fire one non-homing plasma shot. Security Vulnerability Drones have 1 HP and visibly mark a target before committing to a dive, then return to their patrol origin. Ordinary enemies award 100 points; Commit Tokens award 25. Existing shared pickups retain Bay Area behavior, including Auto-Fix excluding the boss.

The zero-gravity bay is a bounded region at x=2280–3230 with a ceiling. It uses zero gravity plus assisted vertical thrust/braking: ±230 px/s target speed, 700 px/s² thrust acceleration, 260 px/s² braking. This is a first-pass accessibility/tuning choice, not an unassisted orbital-physics simulation. Normal movement remains 310 px/s, 1,600 px/s² gravity, and a −740 px/s jump, with 120ms coyote time and 140ms buffering.

## Deprecated API

Crossing x=4300 on the ground starts the inherited 1.8s intro. Hoppy is held, the camera pans into a fixed arena, gates close at x=4180/4970, and traversal enemies/projectiles are suspended or cleared. The boss is inactive and invulnerable until the intro ends. Pause freezes intro, camera pan, music fade, projectiles, hazards and attack timing.

The boss has 10 HP and a repeating sequence:

| Routine | Warning / action / recovery |
|---|---|
| Track | 1.0s of slow approach, maintaining distance |
| Legacy cannon | 0.85s aim warning, one committed plasma shot, 0.7s recovery |
| Stalled slam | 0.9s floor warning, 0.2s impact within 190px, 0.9s stuck fist; jump to clear it |
| Glitch dash | 0.8s direction warning, 0.55s rush at 480px/s, 0.8s braking; travel stays inside the arena |
| Broken-cycle recovery | 0.4s overheat, 1.5s exposed core, 0.5s reboot |

Ordinary swipes/stomps deal one damage throughout the active fight; the exposed core is a safe opening, not an armor gate. Recovery poses disable contact damage. Projectiles sweep their movement segments, hit terrain or Hoppy, and expire after four seconds. Boss defeat awards 1,000 points once, clears projectiles, opens gates, restores the following camera and enables MERGE. Merely standing near MERGE or rising through it never finishes the level.

## Music

Original music by Erik Thorelli lives in the existing folder, whose spelling is `Assets/Audio/Platformer/Obital Ops/` (prompts and loop points in its `PROMPTS.md`):

- `orbital_ops_level.ogg` ("Zero-G Deploy"): traversal, fresh retries, and post-boss cleanup.
- `orbital_ops_boss.ogg` ("The Deprecated API"): begins during the boss intro and continues through the fight.

Each `.import` loops its track after an intro, so scene-local Music-bus playback never reaches the finished signal; imported shared streams are not mutated. A pause-aware fade switches tracks. The arcade music is suspended while playing and restored when leaving. Existing jump/hurt/UI sounds are reused.

## Implementation

`modes/platformer/level.gd` now owns the shared HUD, pickups, pause/results/retry, music transitions, encounter gates/camera, service-platform timetable and MERGE behavior formerly embedded in Bay Area Blitz. Each level owns its authored layout and art. Bay Area's geometry, tuning, boss and music remain unchanged.

Orbital-specific files: `orbital_ops.gd` owns the level and gravity region; `orbital_enemy.gd`, `orbital_hazard.gd`, `orbital_projectile.gd` and `deprecated_api.gd` own their local state; `orbital_art.gd` caches atlas crops from the asset manifest. Player gravity/force inputs default to normal Bay Area behavior and are reset each Orbital physics tick. Retry creates fresh nodes and does not mutate shared resource definitions.

## Validation and limits

Run `Godot --headless --path hoppys-adventure-arcade --script res://tests/orbital_ops_smoke.gd --log-file /tmp/orbital-smoke.log`. Omit `--headless` for screenshots under `/tmp/orbital-*.png`.

The suite covers spawn collision, deck and shuttle boarding through inputs, shuttle transport/pause, zero-g rise/braking/descent/exit, laser warning/active/i-frames, vent forces, projectile shield/damage, melee deduplication, drone warnings/committed targeting, whole-route traversal, safe intro/pause, both music switches, arena bounds/camera, cannon/slam/dash, boss melee and one-time scoring, MERGE activation/lock, fresh retry, fall death, and menu/audio restoration. Route reachability is tested with combat invulnerability; it does not establish a no-hit difficulty rating. Most boss attack checks isolate states rather than simulate an expert player's complete fight.

The first vacuum vent was moved back from x=960 to x=840 after expanded traversal checks exposed suction interfering with the first gap's takeoff. The final route check includes the resulting vent force and crosses both gaps without teleporting.

Bay Area regression suites: `platformer_smoke.gd`, `platformer_traversal.gd`, and `platformer_boss.gd` all pass after lifecycle extraction. Orbital's rendered suite passes, and spawn, zero-g, arena and level-select captures were visually reviewed. The macOS editor importer reports existing certificate/global-settings sandbox warnings; runtime validation uses writable `/tmp` logs. One initial rendered launch aborted before engine output; the subsequent rendered run completed cleanly.

This is a playable v1. Terrain is assembled from cropped sprites and separate collision solids, not an editor-painted TileMapLayer; the asset pack is not a seamless autotile set. No checkpoint saves, new sound design, packaged-export testing or physical-controller playtest is claimed. Final encounter balance, animation registration/pixel cleanup and longer hands-on playtesting remain polish work. The shared baseline's broader open design choices remain open.
