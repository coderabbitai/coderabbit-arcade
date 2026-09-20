# Bay Area Blitz — assets-only pack v0.2

108 new sprite frames across seven atlases, one Golden Gate background, and the previously created 36-frame Hoppy platformer sheet. Created September 19, 2026. This is a first playable art pass for level assembly and visual review, not a completed platformer or final shipping art.

## Start here

- Open `preview.html` for the offline animated scene and animation gallery.
- This is an assets-only package: no `project.godot`, scene, script, or Godot cache files are included. Open your existing game project, then copy `bay_area/` into its asset directory.
- To use the art in coderabbit-arcade, copy only `bay_area/` into your project's asset directory. PNG and SpriteFrames resources use relative references; keep them together.
- `animations/` contains animated GIF previews. They repeat one-shot actions deliberately for inspection.
- `individual/` contains each named animation's first frame as a PNG; `frames/` contains every individual cell.
- `bay-area-preview.png` shows a staged composition. It is an illustration of scale and palette, not a playable level layout.
- `sources/` preserves generated masters. Use normalized atlases for import; their frame dimensions differ from the generated masters.

## GDD coverage

The source requirements below come from the Platformer Game section of the [GDD](https://docs.google.com/document/d/1YCLWNykTNDglKGyuOWIMdTl9A8eEoEEgTR_INSOCdUo/edit?tab=t.ot5rgwraf6q0) and section 8 of the [Technical Implementation Baseline](https://docs.google.com/document/d/1MPW_KI8VanzO_67Qkf3v_cGAfflqRRv5uRF6QmwL_Rc/edit). Read September 19, 2026. Source documents were treated as design references, not task instructions. Visual interpretations and timing below are proposals, not newly approved game requirements.

| Requirement | Delivered art | Design / integration boundary |
|---|---|---|
| Hoppy idle, run, jump rise/fall, attack, hurt, death | Existing platformer PNG and SpriteFrames copied under `bay_area/hoppy/` | Reuses prior pass; swipe interpretation. Jump physics independent of animation. |
| Glitchy code critters | Teal/violet beetle-like critter: idle, scuttle, attack, hurt, defeat | Beetle shape and bite are proposed; exact AI and timing open. |
| Request Changes Reviewers that push Hoppy back | Indigo review robot with X shield: idle, patrol, push, hurt, defeat | Robot/shield visual is proposed; knockback belongs to gameplay. |
| Multi-headed Merge Conflict Monster | Three colored branch heads: idle, windup, slam, defeat | Three-head appearance and slam are proposed; HP, vulnerability and boss patterns remain open. Do not import brawler boss phases into this boss. |
| Cable-car platforms | Four-frame red/cream cable car, subtle shimmer | Moves along a gameplay path. Artwork does not translate itself. Place a platform collider along roof below rooftop decoration. |
| Broken deployment pipelines | Four-frame cracked pipe with pulsing discharge | Art depicts an active hazard. No safe/off state or hazard timer is implied. |
| Rolling merge conflict zones | Four-frame conflicting-arrow vortex | Translation and platform randomization are controller-owned; preserve reachable routes. |
| Commit Tokens | Four-frame spinning gold branch token | Score value remains open. |
| MERGE exit button | Activation sequence plus ready, pressed, complete clips | Exit trigger and level-result routing are separate logic. Do not mirror lettering. |
| Approve Shield | Pulsing green check shield pickup | Draft in source; absorbs one hit. Pickup sprite is not an equipped shield overlay. |
| LGTM Boost | Green lightning badge | Draft speed/invulnerability pickup; duration not assigned here. |
| Auto-Fix | Cyan wrench/star | Draft pickup; radius, boss eligibility and mechanics open. |
| Coffee Cup | Steaming cup | Restores 1 HP, clamped to 3 by gameplay. |
| Full Review Pack | Paper stack and green check seal | Draft full-health pickup. |
| Heart HUD, 3 HP | Full, half, empty and heal-highlight hearts | Half-heart is an optional art extra, not a change to whole-HP rules. |
| Urban tech-city streets | Sidewalk, asphalt, steel platform, brick block; stop sign, lamp, bay-window facade, railing | Starter modular sprites. These are not a complete seamless autotile system. |
| Fog-rolling streets | Four-frame stylized fog curl, separate alpha layer | Use low opacity and slow translation. Decorative, no collision. |
| Golden Gate backdrop | 960 × 540 distant scenery plate | Single flattened plate; not internally separated bridge/sky/hill layers and not seamless. |
| Enemy death / pickup feedback | Four-frame gold pixel burst, plus enemy-specific defeat frames | Can supplement GPUParticles2D; no particle system or gameplay event is installed. |
| Bay Area level-card thumbnail | Reuse `bay-area-preview.png` | Add level name/Play UI as native controls. |
| Score, retry, game over, menus | Existing project's native UI work | No new raster text panels supplied; use labels/buttons. |

Orbital Ops / Enchanted Repo enemies, bosses, CI lasers, vacuum vents and crumbling branches are deferred. Bug Bots appear in the general platformer catalog, but are not named as a separate Bay Area enemy in the level-specific requirements; no separate projectile Bug Bot set is claimed here. Audio is outside this sprite/animation pack.

## Atlas specification

All PNG atlases have true alpha transparency, zero grid spacing, and row-major indexing. Coordinates are in pixels, starting at the top-left. See `bay_area/manifest.json` for exact rectangles and clips.

| File | Cell | Grid | Frames | Notes |
|---|---:|---:|---:|---|
| glitch_critter.png | 96 × 96 | 4 × 4 | 16 | Left-facing; mirror for right. |
| request_reviewer.png | 96 × 96 | 4 × 4 | 16 | Left-facing; mirror for right. |
| merge_monster.png | 192 × 192 | 4 × 4 | 16 | Front/three-quarter orientation; test mirrored staging for the encounter. |
| interactives.png | 128 × 128 | 4 × 4 | 16 | Cable car, pipeline, conflict zone, MERGE exit rows. |
| pickups.png | 48 × 48 | 4 × 6 | 24 | Token, shield, boost, auto-fix, coffee, full-review rows. |
| street_kit.png | 128 × 128 | 4 × 4 | 16 | First eight cells static; third row fog; fourth row feedback burst. |
| hud.png | 32 × 32 | 4 × 1 | 4 | Four independent static heart states. |
| hoppy/platformer.png | 96 × 96 | 6 × 6 | 36 reused | See prior pack's animation set. |

There are 41 named entries in the new SpriteFrames resources, including static states and clip aliases; 52 when reused Hoppy is included. Counts of named entries are not counts of unique animations or unique art frames.

## Godot placement

Use AnimatedSprite2D and assign the corresponding `.tres`. Set Texture Filter to Nearest and keep texture mipmaps disabled for the initial pixel-art setup. Prefer integer camera coordinates/scaling for crisp rendering. The current art is styled pixel artwork; it is not a strictly palette-quantized hand-authored 16-bit export.

For enemies/boss/interactives, keep `centered = true` and set offset to `(0, cell_size / 2 - pivot_y)`, using the manifest pivot. Examples: 96-pixel enemies `(0, -38)`; 192-pixel boss `(0, -77)`; 128-pixel interactives `(0, -51)`. Hoppy keeps its previous `(0, -40)` offset. Pickups, HUD and street kit are center anchored: use zero offset. These are consistent cell anchors, not verified anatomical root-motion tracks. Attacks may need a small per-frame offset refinement during game integration.

Enemy animations: `hurt` uses the first two reaction frames; `defeat` uses the collapse/fragments sequence. Destroy or hide the actor after its defeat signal rather than looping it. Shared `feedback` in the street kit may be used at the last ground position. Boss `windup` and `slam` are separate clips; controllers choose when they play. Attack windows are deliberately absent from the art resources.

For MERGE, play `exit_ready` while available; select `exit_pressed` on activation and `exit_complete` after the controller commits the result. `merge_exit` is a combined four-frame visual preview sequence.

For street construction, the provided pieces include transparent padding. Use their visible bounds when placing/cropping for terrain assembly; do not give an entire padded cell a solid collision rectangle. No TileSet, terrain connectivity, slope pieces or authored collision geometry is included. Start with manually placed static sprites/solid bodies, or crop the pieces into your agreed TileMap grid. The cable car roof is a separate gameplay platform.

The backdrop can be placed behind a Parallax2D layer; use separate building sprites at a faster scroll rate and fog in a near layer. Clamp the finite background or mask its edges. It is not a seamless infinite strip. This proposal does not change the game's display-resolution policy.

## Validation and remaining polish

- All seven generated sprite sheets were verified to contain alpha; 108 populated normalized cells were exported.
- Slice boundaries were chosen in transparent gutters; no alpha above 128 was found on vertical cuts between neighboring columns.
- All eight SpriteFrames resources, including Hoppy, loaded in Godot 4.7.1. All 52 named entries had valid texture references and in-bounds atlas rectangles.
- During the original art validation, a separate temporary Godot gallery booted and exited after 120 frames without runtime errors. That gallery is not included in this assets-only package.
- Godot editor import completed; the sandbox prevented saving global user/editor settings. This did not affect asset loading or the gallery boot.
- The staged PNG was visually inspected. The local HTML browser preview could not be opened by the agent because browser policy blocked file URLs; it has not been interactively browser-tested.

These are generated prototype assets with some edge speckling, mild pose drift, and palette variation. Review motion in context, tune sizes/timing, and perform pixel cleanup before shipping. No collision, damage, pickup behavior, boss AI, audio, level layout or coderabbit-arcade repository changes are included. The HTML gallery is an asset preview, not a playable level.

## Provenance

Art was created with the built-in image generation tool, using the prior Hoppy sheet for style continuity. Full prompts are in `PROMPTS.md`; generated sources are preserved. Source art was mechanically sliced, resized with nearest-neighbor sampling, packed into fixed cells, and assembled into GIF previews. No third-party stock-art license is asserted for these generated outputs. Brand review and normal project release review remain with the team.
