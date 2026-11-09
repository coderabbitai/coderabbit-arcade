# Main menu — implementation notes

Implemented 2026-09-17 from the Main Menu section of the GDD and §6 of the technical baseline. Engine verified: Godot 4.7.1.stable.official.a13da4feb. Scope is the central menu only.

## Run

Open `hoppys-adventure-arcade/project.godot` in Godot 4.7.1 and press F6 from the menu scene, or F5 from anywhere. The main scene is `scenes/main_menu/main_menu.tscn`.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade
```

Arrow keys, Tab, D-pad, or left stick navigate; Enter / gamepad A activates; Escape / B closes overlays. Mouse hover takes preview control from keyboard/gamepad until the next intentional keyboard/gamepad input.

## Behavior and ownership

- Scene-local showcase: idle previews 0–12 every 9 seconds; 1.2-second fades. Focusing a mode cycles its previews every 3 seconds with 0.6-second fades: Platformer cycles three themes; Beat’em Up cycles all three Code City Brawl stages followed by all three Heroes vs. Villains stages, and the Endless Runner cycles four in-game stills (corridor, power-ups, a jump over a hazard, boss).
- Focus exit waits 2 seconds, then restores the idle index and remaining dwell. Modals pause showcase timing. Parallax continues behind overlays.
- At most two preview nodes exist. During a fade, requests coalesce to the latest selection; the outgoing node is freed before another fade begins. Each preview is a `CanvasGroup`, so a fade blends the flattened scene instead of letting its parallax layers show through each other. Preview textures are loaded once and kept, so transitions never read from disk.
- Layout recenters on viewport resize (not every frame). Menu buttons grow 5% around their centre on hover/focus and keep that scale when their container re-sorts.
- The UI uses a 1280×720 reference with expanding viewport coverage and centered composition. Backgrounds fill taller and wider windows. Pixel scenery uses nearest filtering.
- AppRouter validates known routes and prevents duplicate transitions. Mode buttons open their existing game menus. This graphics pass does not modify gameplay.
- AudioService owns a single looping music player and one UI sound player. Music and SFX independently feed Master. The hub plays a calm lo-fi 8-bit loop (`Assets/Audio/Main Menu/hub_chiptune_loop.wav`, built by `tools/build_hub_chiptune.py`), whose `.import` loops the whole file. It plays at `AudioService.HUB_MUSIC_DB` (−15 dB), below the games' −10 dB, so a booth screen can run it all day. Booth mode (`AppRouter.set_booth` → `AudioService.set_attract`) keeps the same track. Synthesized UI blips are generated in code. Design and loop notes are in that folder's `PROMPTS.md`.
- SaveService stores validated volume and fullscreen values in `user://settings.cfg`. Sliders apply immediately; closing settings persists them. Save failures appear in the UI.
- Quit asks for confirmation and fades to black for 1 second.
- At exit, however the app quits, AudioService stops every audio player, the current scene's included, and waits up to 0.5 s for two audio mixes (about 25 ms with a sound card). Godot frees a stopped voice only after the mixer has run, and reports any voice it still holds at shutdown as "ObjectDB instances were leaked" / "resources still in use". `tools/checks/exit_leak.py` covers this in CI.

## Credits

The **Credits** button, after Settings and Quit Game, opens `scenes/credits/credits.tscn` (route `credits`). It shows the hand-written sections in `scenes/credits/credits.json` first. Then come the asset credits from the Third-party table of `ASSETS_LICENSES.md`, grouped into Music, Sound effects and Art, each with its license and, where the table gives them, its source and license links. An art pack whose music the game also uses appears under Art and Music; assets marked "Not referenced" are left out. The list scrolls by itself. Up and Down (held, for continuous scrolling) or the mouse wheel scroll it by hand, and Esc, B or **Return to Main Menu** go back to the hub.

- **Asset credits** are generated. `tools/credits/build_credits.py` writes `scenes/credits/asset_credits.json` from `ASSETS_LICENSES.md`. After changing that table, run `python3 tools/credits/build_credits.py`; CI fails if the two differ.
- **Hand-written credits** live in `credits.json`: a list of sections, each with a `title`, optional `lines` and optional `tracks` (`{"title": …, "used_by": …}`). Original music goes in the "Original music" section. To credit something else, add a track there or add a section.

## How-to-play cards

The first time a visitor enters a game, `AppRouter.go()` opens that game's how-to-play card (`app/how_to_play.gd`) over it. A visitor starts whenever the hub or the booth's attract route opens, so retries and returns from a game's own menu skip the card. `--route=` launches show it too.

- **Pages.** Each card is three or four pages: **Your goal**, **Controls**, **Tips**, and for Orbital Ops a **Zero gravity** page. Dots in the corner show where you are.
- **Scenes.** Each page except Controls plays a short looping scene with a line of text under it (`app/how_to_play_demo.gd`). The scenes reuse the game's own sprite sheets: Hoppy swiping the level boss down and landing on MERGE, swiping a glitch critter, rising and sinking in the zero-G bay, crossing a laser while it's off, hopping across crumbling branches, combos against Code City soldiers and AI Slop sprites, and a REVIEW burst. The runner is 3D, so its pages pan across its menu screenshots. Captions on the scene repeat the key moment ("Off: go!", "Hold Q / LB: REVIEW"). A scene is one looping Tween bound to the page, so it runs while the game is paused and stops when the page changes. Each scene is a scaled-down window onto the game's own screen: the floor line sits where the game puts it (y 600), actors keep their in-game scale and are anchored at the feet by the same pivots the game uses, the platformer scenes draw the level's sky and ground tiles, and the beat 'em up scenes draw the room panorama so actors stand on its painted floor. Bosses stand where the game places them (y 565 in the beat 'em ups).
- **Controls.** `app/how_to_play_data.gd` holds one entry per gameplay route: title, pages, control rows and `poses`. Each row names its input actions, the keys it shows and the pad inputs it shows, plus an `icon`: a small Hoppy acting out the move (running, jumping, swiping, rolling, rising, sinking). The keyboard text ("Space / W / ↑", "WASD / Arrows") and controller text are built from those. With a controller connected, buttons use that pad's names (Cross, A or B for the bottom button); without one they read "A / Cross". Face buttons also get a four-dot glyph with the one to press filled in. Orbital Ops adds its zero-G rise and sink rows; Heroes vs. Villains adds REVIEW and Skip card.
- **Holding the game.** The card pauses the tree and is the root's last child, so its `_input` sees every press first and swallows it. It passes each press to `AppRouter.note_input()` (booth idle timer) and `ControllerService.observe()` (player one's pad).
- **Paging and closing.** Presses in the first 0.5 s are ignored, so the press that picked the game can't skip a page. After that, a confirm, jump or attack press, a left click or a touch turns to the next page, and on the last page starts the game. Left/right (arrows, A/D, D-pad, one flip per stick push) go back and forth without closing. Pause (Esc, P, Start) skips straight to the game. Each page turns by itself after 7 s while its bar drains, so a whole card is at most 28 s. The game unpauses two physics frames after the card closes, so the closing press never also jumps or swipes. The countdown waits while the window is unfocused. If the game paused itself under the card (focus loss), it stays in its pause menu: games answer `is_player_paused()`.
- **Booth.** The 90 s idle timer keeps counting under the card, and a route change removes it.
- **Pause menus.** The platformer levels, the runner and both beat 'em ups have a **How to Play** button in their pause menu. It opens the same card without a countdown; its pages turn the same way, Back or Pause closes it from any page, the game stays paused and focus returns to the button.
- **Tests.** `tests/how_to_play.gd` checks that every gameplay route has a card with a controls page, that every key and pad input a card shows is bound to its row's actions, that every sprite clip and image a page or icon uses exists, that every page builds and plays, the label text, the once-per-visitor rule, paging and closing, auto-advance, booth idle, focus loss and the pause-menu buttons. Suites run with `--script` and get no cards unless they set `AppRouter.how_to_play_enabled`.

## Art and replacement points

As of 2026-09-30, `hoppy.gd` uses the supplied `Assets/Character/Hoppy/2D/hoppy-sprite-pack/hoppy` SpriteFrames: idle by default, one jump on Platformer selection, and one jab then the default idle on Beat’em Up selection. Endless Runner hover or keyboard/gamepad focus crossfades to the existing `hoppy_runner_visual.tscn` rig running in place, rendered through a transparent, isolated 512×512 SubViewport. Leaving that selection restores 2D immediately through a 0.22-second fade; idle background cycling does not switch the character. Hidden 3D rendering and rig processing are disabled. Both versions face toward the buttons and share a ground anchor. `sprite_scale` and `transition_seconds` are exposed on the Hoppy node for iteration. The title uses a system monospace fallback; no final pixel font or logo was supplied.

| Preview | Source |
| --- | --- |
| Bay Area Blitz | `Assets/bay-area-blitz-assets-only/bay_area/backdrop.png` |
| Orbital Ops | `Assets/orbital-ops-assets-only/orbital_ops/` starfield and station hull |
| Enchanted Repo | `Assets/enchanted-repo-assets-only/enchanted_repo/` sky and treeline |
| Codebase Corridor, Power-ups, Jump/Roll/Dodge, Boss Fights | `Assets/runner/menu_previews/runner_*.png`, captured from an autopilot run by `tests/capture_runner_menu_previews.gd` (graphical: `Godot --always-on-top --path hoppys-adventure-arcade --script res://tests/capture_runner_menu_previews.gd`) |
| CLI / IDE District | `Assets/code-city-brawl-assets-only/code_city/district_background.png` |
| Security Sector | `Assets/code-city-brawl-assets-only/code_city/security_background.png` |
| Git Repository HQ | `Assets/code-city-brawl-assets-only/code_city/hq_background.png` |
| Generation Floor, Review Gauntlet, Agentic Core | `Assets/heroes-vs-villains-assets-only/heroes_villains/` stage panoramas |

Updated 2026-10-08: all menu previews now use current stage artwork or captured runner gameplay. Finite panoramas use cover scaling, overscan, and bounded camera drift, with independent depth motion for layered platformer art; none are tiled across a seam. Stage captions identify the campaign, and a lower gradient preserves readability on bright floors. Existing crossfade durations, input behavior, and Hoppy reactions remain intact. Supplied asset files and accompanying licenses remain in place. Optional CRT, shader dissolve, adaptive music, and final branding are deferred.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --script res://tests/menu_smoke.gd
```

The behavioral smoke test covers preview timing and preservation, rapid input coalescing, bounded preview count, all thirteen previews, modal focus restoration, invalid routes, duplicate navigation, all three mode round trips, and audio player counts. It also dispatches keyboard, simulated gamepad, and mouse events. Mouse hover goes through `tests/support/pointer.gd`, so it and the character check below run headless in CI. A rendered run writes menu/settings screenshots to `/tmp` for layout inspection. It uses the normal settings path, so run against a disposable user profile if preserving settings during tests matters.

Physical controller feel, audio loop quality, and Windows/Linux exports require later hands-on checks; no export presets or platform builds were added.

Character-specific check: run `--script res://tests/menu_hoppy_smoke.gd` to verify default idle, mouse-triggered 3D, keyboard-triggered brawler reaction, one-shot completion, rapid switching, and hidden-rig suspension. Graphical runs save both character states and modal coverage to `/tmp/menu-hoppy-*.png`.
