# Main menu — implementation notes

Implemented 2026-09-17 from the Main Menu section of the GDD and §6 of the technical baseline. Engine verified: Godot 4.7.1.stable.official.a13da4feb. Scope is the central menu only.

## Run

Open `hoppys-adventure-arcade/project.godot` in Godot 4.7.1 and press F6 from the menu scene, or F5 from anywhere. The main scene is `scenes/main_menu/main_menu.tscn`.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade
```

Arrow keys, Tab, D-pad, or left stick navigate; Enter / gamepad A activates; Escape / B closes overlays. Mouse hover takes preview control from keyboard/gamepad until the next intentional keyboard/gamepad input.

## Behavior and ownership

- Scene-local showcase: idle previews 0–9 every 9 seconds; 1.2-second fades. Focusing a mode cycles its previews every 3 seconds with 0.6-second fades: Platformer and brawler cycle three themes, and the Endless Runner cycles four in-game stills (corridor, power-ups, sharp turn, boss).
- Focus exit waits 2 seconds, then restores the idle index and remaining dwell. Modals pause showcase timing. Parallax continues behind overlays.
- At most two preview nodes exist. During a fade, requests coalesce to the latest selection; the outgoing node is freed before another fade begins. Each preview is a `CanvasGroup`, so a fade blends the flattened scene instead of letting its parallax layers show through each other. Preview textures are loaded once and kept, so transitions never read from disk.
- Layout recenters on viewport resize (not every frame). Menu buttons grow 5% around their centre on hover/focus and keep that scale when their container re-sorts.
- The UI uses a 1280×720 reference with expanding viewport coverage and centered composition. Backgrounds fill taller and wider windows. Pixel scenery uses nearest filtering.
- AppRouter validates known routes and prevents duplicate transitions. Each mode currently opens an explicit “not playable yet” endpoint with a return button. No gameplay was added.
- AudioService owns a single looping music player and one UI sound player. Music and SFX independently feed Master. Supplied `Assets/Audio/happy_adveture.mp3` is used unchanged; synthesized UI blips are generated in code. MP3 repeat is enabled; musical seamlessness at the track boundary still needs listening review.
- SaveService stores validated volume and fullscreen values in `user://settings.cfg`. Sliders apply immediately; closing settings persists them. Save failures appear in the UI.
- Quit asks for confirmation and fades to black for 1 second.

## Art and replacement points

As of 2026-09-30, `hoppy.gd` uses the supplied `Assets/Character/Hoppy/2D/hoppy-sprite-pack/hoppy` SpriteFrames: idle by default, one jump on Platformer selection, and one jab then the default idle on Beat’em Up selection. Endless Runner hover or keyboard/gamepad focus crossfades to the existing `hoppy_runner_visual.tscn` rig running in place, rendered through a transparent, isolated 512×512 SubViewport. Leaving that selection restores 2D immediately through a 0.22-second fade; idle background cycling does not switch the character. Hidden 3D rendering and rig processing are disabled. Both versions face toward the buttons and share a ground anchor. `sprite_scale` and `transition_seconds` are exposed on the Hoppy node for iteration. The title uses a system monospace fallback; no final pixel font or logo was supplied.

| Preview | Source |
| --- | --- |
| Bay Area Blitz | `Assets/CityBackground` layered pixel skyline |
| Orbital Ops | `Assets/space_background_pack/layers` |
| Enchanted Repo | `Assets/parallax_forest_pack/layers` |
| Codebase Corridor, Power-ups, Sharp Turns, Boss Fights | `Assets/runner/menu_previews/runner_*.png`, captured from an autopilot run by `tests/capture_runner_menu_previews.gd` (graphical: `Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/capture_runner_menu_previews.gd`) |
| CLI / IDE District | `Assets/Backgrounds/cyberpunk-street-files/Assets/Version 2/Layers` |
| Security Sector | Code-drawn racks, scanner, and tunnel |
| Git Repository HQ | Code-drawn branching nodes and hall |

These are theme previews, not final level art. Supplied asset files and accompanying licenses remain in place. Optional CRT, shader dissolve, adaptive music, and final branding are deferred.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --script res://tests/menu_smoke.gd
```

The behavioral smoke test covers preview timing and preservation, rapid input coalescing, bounded preview count, all ten previews, modal focus restoration, invalid routes, duplicate navigation, all three mode round trips, and audio player counts. It also dispatches keyboard, simulated gamepad, and mouse events. A rendered run writes menu/settings screenshots to `/tmp` for layout inspection. It uses the normal settings path, so run against a disposable user profile if preserving settings during tests matters.

Physical controller feel, audio loop quality, and Windows/Linux exports require later hands-on checks; no export presets or platform builds were added.

Character-specific check: run `--script res://tests/menu_hoppy_smoke.gd` to verify default idle, mouse-triggered 3D, keyboard-triggered brawler reaction, one-shot completion, rapid switching, and hidden-rig suspension. Graphical runs save both character states and modal coverage to `/tmp/menu-hoppy-*.png`.
