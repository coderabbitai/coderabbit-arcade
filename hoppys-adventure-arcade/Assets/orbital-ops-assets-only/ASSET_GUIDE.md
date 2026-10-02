# Orbital Ops — asset guide

September 30, 2026 • Godot 4.7.1 • First production-oriented art pass

## Design references

Read the current GDD (internal), including Platformer Game and Main Menu, the Technical Implementation Baseline (internal), and Agent Context (internal). The repository's updated local baseline and Bay Area implementation were also reviewed. The live GDD reported modification September 30, 2026. Source prose was reviewed; embedded source artwork was not audited.

The GDD specifies a space station, satellite scaffolding, zero-gravity jumps, rogue AI bots, Security Vulnerability Drones, laser CI/CD checkpoints, vacuum vents, and a decaying Deprecated API robot cycling broken attacks. The Main Menu specifies far stars, mid station hull, near struts, and slow orbital rings. This pack supplies the visual parts for those requirements. Enemy appearance, precise attacks and animation timings below are creative proposals.

## Coverage

| Asset | Delivered |
|---|---|
| Deprecated API | 24 frames: idle, cannon warning/fire/recovery, stalled slam, glitch dash, overheat, exposed core, reboot, hurt, defeat |
| Rogue AI bot | 16 frames: idle, walking, ranged warning/fire/recovery, hurt, defeat |
| Security Vulnerability Drone | 16 frames: hovering, patrol, ambush warning, dive, recovery, hurt, breakup |
| CI/CD checkpoint | Projector off, amber warning, active capped laser, cooldown |
| Vacuum vent | Closed, amber opening warning, two active airflow frames; reverse warning to close |
| Zero-gravity section | Four-frame ring beacon; physics zone is separate |
| Attack effects | Two plasma-bolt frames, slam impact, dash trail |
| Station construction | Floor slab, left/right ledges, thin platform, hull panel, wall block, vertical/horizontal scaffolds, solar array, bulkhead door, terminal, crate, ring, foreground strut, warning lamp, service platform |
| Level/menu scenery | Separate 960×540 starfield and transparent station-hull plates; near strut and orbital ring in station kit |
| Shared platformer items | Reuse existing Hoppy, pickup, HUD and MERGE resources from `Assets/bay-area-blitz-assets-only/bay_area/`; no duplicate shared assets |

No additional Bug Bot is claimed: the GDD's level-specific Orbital enemies are the rogue AI and flying vulnerability drone. Audio is outside this art pack.

## Runtime atlas layout

All normalized atlases use true alpha, a regular row-major grid with no spacing, and nearest-neighbor sampling. `manifest.json` records exact rectangles, pivot, source slicing rectangles, core visible bounds, clips, FPS, and loop flags. Visible bounds are **left/top/right/bottom**, not width/height; they exclude alpha below 129 and are visual guidance, not colliders.

| Atlas | Cell | Grid | Frames | Named states | Pivot |
|---|---:|---:|---:|---:|---:|
| deprecated_api | 192×192 | 4×6 | 24 | 15 | (96,173) |
| rogue_ai | 96×96 | 4×4 | 16 | 7 | (48,86) |
| security_drone | 96×96 | 4×4 | 16 | 7 | (48,48) |
| hazards | 128×128 | 4×4 | 16 | 11 | (64,64) |
| station_kit | 128×128 | 4×4 | 16 | 16 | (64,64) |

88 frames and 56 named states total. Static states count as named entries, not full animations. Seven selected source PNGs are preserved at generated resolution; use normalized `orbital_ops/` assets at runtime.

Use `centered = true`, then offset = `(cell_width/2 - pivot_x, cell_height/2 - pivot_y)`. Boss offset is `(0,-77)`, rogue AI `(0,-38)`, other resources `(0,0)`. Actors face left; mirror for right. Ground anchors are approximate cell anchors, not tracked anatomical roots; slight pose drift and final timing refinement remain. Flying sprites are center anchored. The staging render uses enlarged actors to compare their silhouettes beside existing Hoppy.

## Deprecated API — proposed moveset

These sequences are art-supported proposals for the next implementation pass. SpriteFrames do not apply damage, move actors, set invulnerability, or create hitboxes. Controllers should hold poses for explicit warning/active/recovery timers and select the next clip. Suggested first-pass warnings are deliberately longer than active windows.

| Move | Readable sequence | Proposed gameplay interpretation |
|---|---|---|
| Legacy cannon | `cannon_warning` → `cannon_fire` → `cannon_recover` | 0.8s amber charge, one committed plasma shot, 0.6s droop. Aim before release; no homing. Use `plasma_bolt` as a separate projectile. |
| Stalled slam | `slam_warning` → `slam` → `slam_stalled` | 0.9s raised fist, 0.15s short-range impact, 0.8s stuck fist. Warn the ground area before impact; make it jumpable. `slam_impact` is separate visual feedback. |
| Glitch dash | `dash_warning` → `dash` → `dash_brake` | 0.7s crouch, 0.35s committed horizontal rush, 0.8s braking stumble. Lock direction on release, constrain travel to arena bounds. Trail is visual only. |
| Broken-cycle recovery | `overheat` → `vulnerable` → `reboot` → `idle` | After the three-move cycle, sputter 0.4s, expose cyan core 1.2s, reboot 0.5s. Exact vulnerability rules and HP remain open. |
| Reaction/end | `hurt`, `defeat` | Brief reaction; defeat is nonlooping and ends in a wreck. Later controller should cancel attacks/projectiles and unlock the shared MERGE exit. |

The core opening is an optional gameplay opportunity, not an approved immunity rule. Do not copy armor stripping or phase rules from other GDD bosses. Animation lengths are visual preview defaults and do not dictate combat tuning.

## Hazards and terrain integration

Laser and vent warnings should precede damage or suction. Active laser art is a short capped column, not a complete scalable checkpoint grid; a future controller can position paired emitters and draw/stretch a narrow beam separately to fit the checkpoint. Only the active state should damage. Vent airflow art suggests suction; actual direction/strength and overlap volumes belong to level logic. Beacons mark zero-gravity sections but do not change gravity themselves.

Station pieces are padded modular sprites, **not a seamless autotile set**. Crop visible art as needed, align walkable top edges, and place separate collision geometry. Endcaps include raised posts, so do not give their full bounding rectangles solid collision indiscriminately. No slopes, terrain connectivity, TileSet, or collision data is asserted. One-way and service platforms are static art awaiting controller-owned movement/collision. A bulkhead is a closed decorative door, not an opening animation.

For menu/level parallax, use stars far, station hull mid, and kit struts near. The baseline's relative 0.1/0.3/0.6 speeds are suitable starting points. Rotate the separate ring slowly around its visual center. Background plates are finite and not seamless: clamp, mask, or author extra coverage. The station image reaches the right edge. Keep menu labels as native controls and apply the existing readability overlay. `orbital-ops-preview.png` is a staged scale study, not an authored playable level or clean UI thumbnail.

## Review and reproducibility

`preview.html` works offline, embeds its manifest, and offers per-resource animation selection, pause and speed controls. One-shot clips repeat there for inspection. GIF previews also repeat intentionally. Gameplay loop flags remain correctly set in `.tres` resources.

Rebuild from preserved masters with `tools/build_orbital_asset_pack.py` using Python with Pillow and NumPy. Existing `sources/*.png` are authoritative; original generation paths are only fallback provenance. Source art is mechanically sliced through transparent gutters, resized with nearest-neighbor sampling, and placed in fixed cells. Alpha is preserved. Built-in image generation was used, with the Bay Area reviewer as a style reference. Prompts and correction prompts are in `PROMPTS.md`. No third-party stock-art license is asserted.

Validation command: `Godot --headless --path hoppys-adventure-arcade --script res://tests/orbital_assets.gd`. Omit `--headless` to render the staged preview. The test validates actual resource loads, animation names/counts/loop flags, atlas bounds, nonempty textures, and background dimensions. The build checks alpha and internal silhouette cuts. These checks do not prove gameplay balance or pixel-perfect animation registration. Generated art still has mild pose drift and edge speckling; final pixel cleanup and in-level motion review remain polish work.

Validation on September 30: all 88 frames, 56 named clips, five SpriteFrames resources and both background plates passed in Godot 4.7.1. A rendered 1280×720 staging image was produced and visually reviewed. The initial harness needed the existing AudioService shutdown to avoid audio resources lingering at exit; the final headless run exits cleanly. Editor import completed, with an existing nested-project warning for SynthCitiesGodot and sandbox restrictions on global editor settings. A diagnostic run without a writable log path crashed before validation; subsequent checks use `/tmp` log paths. The offline HTML gallery has not been interactively browser-tested. No gameplay tests or export builds are claimed for this asset-only pass.
