# Main menu — implementation notes

Implemented 2026-09-17 from the Main Menu section of the GDD and §6 of the technical baseline. Engine verified: Godot 4.7.1.stable.official.a13da4feb. Scope is the central menu only.

## Run

Open `hoppys-adventure-arcade/project.godot` in Godot 4.7.1 and press F6 from the menu scene, or F5 from anywhere. The main scene is `scenes/main_menu/main_menu.tscn`.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade
```

Arrow keys, Tab, D-pad, or left stick navigate; Enter / gamepad A activates; Escape / B closes overlays. Mouse hover takes preview control from keyboard/gamepad until the next intentional keyboard/gamepad input.

## Behavior and ownership

- Scene-local showcase: idle previews 0–6 every 9 seconds; 1.2-second fades. Platformer and brawler focus cycle their three themes every 3 seconds with 0.6-second fades. Runner holds the corridor with a 0.8-second fade.
- Focus exit waits 2 seconds, then restores the idle index and remaining dwell. Modals pause showcase timing. Parallax continues behind overlays.
- At most two preview nodes exist. During a fade, requests coalesce to the latest selection; the outgoing node is freed before another fade begins.
- The UI uses a 1280×720 reference with expanding viewport coverage and centered composition. Backgrounds fill taller and wider windows. Pixel scenery uses nearest filtering.
- AppRouter validates known routes and prevents duplicate transitions. Each mode currently opens an explicit “not playable yet” endpoint with a return button. No gameplay was added.
- AudioService owns a single looping music player and one UI sound player. Music and SFX independently feed Master. Supplied `Assets/Audio/happy_adveture.mp3` is used unchanged; synthesized UI blips are generated in code. MP3 repeat is enabled; musical seamlessness at the track boundary still needs listening review.
- SaveService stores validated volume and fullscreen values in `user://settings.cfg`. Sliders apply immediately; closing settings persists them. Save failures appear in the UI.
- Quit asks for confirmation and fades to black for 1 second.

## Art and replacement points

The user approved a temporary rabbit for this session. `hoppy.gd` draws and animates that placeholder, with idle blinking and mode reactions. Replace the `Interface/Hoppy` node with final character art when available. The title uses a system monospace fallback; no final pixel font or logo was supplied.

| Preview | Source |
| --- | --- |
| Bay Area Blitz | `Assets/CityBackground` layered pixel skyline |
| Orbital Ops | `Assets/space_background_pack/layers` |
| Enchanted Repo | `Assets/parallax_forest_pack/layers` |
| Codebase Corridor | Code-drawn tunnel and falling marks |
| CLI / IDE District | `Assets/cyberpunk-street-files/Assets/Version 2/Layers` |
| Security Sector | Code-drawn racks, scanner, and tunnel |
| Git Repository HQ | Code-drawn branching nodes and hall |

These are theme previews, not final level art. Supplied asset files and accompanying licenses remain in place. The nested `Assets/SynthCitiesGodot` project is ignored by Godot's importer; this menu does not depend on it. Optional CRT, shader dissolve, adaptive music, and final branding are deferred.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --script res://tests/menu_smoke.gd
```

The behavioral smoke test covers preview timing and preservation, rapid input coalescing, bounded preview count, all seven themes, modal focus restoration, invalid routes, duplicate navigation, all three mode round trips, and audio player counts. It also dispatches keyboard, simulated gamepad, and mouse events. A rendered run writes menu/settings screenshots to `/tmp` for layout inspection. It uses the normal settings path, so run against a disposable user profile if preserving settings during tests matters.

Physical controller feel, audio loop quality, and Windows/Linux exports require later hands-on checks; no export presets or platform builds were added.
