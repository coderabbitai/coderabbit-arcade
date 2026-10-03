# Hoppy sprite pack — first playable art pass

Based on the supplied orange-rabbit comics and the Platformer / Beat’em Up sections of Hoppy’s Adventure Arcade GDD, read September 19, 2026. The comics supplied character cues, not instructions. This pack has not been installed in coderabbit-arcade.

## Contents

- `hoppy/platformer.png`: transparent 576 × 576 atlas; 6 columns × 6 rows; 96 × 96 cells.
- `hoppy/brawler.png`: matching atlas format, 36 additional poses.
- `hoppy/*.tres`: Godot 4 SpriteFrames resources with frame order, speed, and loop flags.
- `hoppy/manifest.json`: engine-independent frame rectangles, animation metadata, and pivot.
- `animations/`: 12 animated GIF previews. These repeat for inspection, including death and attacks; gameplay resources correctly use one-shot flags.
- `preview.html`: standalone motion gallery with pause, speed and facing controls; embedded images work offline.
- `sources/`: untouched generated masters, with true alpha. Their spacing is irregular; use the normalized game atlases for import.
- `PROMPTS.md`: complete generation prompts and provenance.

## Animation map

Each authored row contains six frames, ordered left to right. Row numbers below are one-based.

| Row | Platformer | FPS | Brawler | FPS |
|---|---|---:|---|---:|
| 1 | idle | 8 | guard | 8 |
| 2 | run | 12 | walk | 10 |
| 3 | jump | 10 | jab | 16 |
| 4 | attack | 14 | overhead | 12 |
| 5 | hurt | 12 | spin_kick | 14 |
| 6 | death | 9 | pickup | 10 |

Only idle/run/guard/walk loop in Godot. Platformer also exposes jump_start, jump_rise, jump_apex, jump_fall and land so the controller can choose the pose from actual motion. The full jump animation is primarily a preview sequence; it should not determine physical jump duration.

## Godot import

1. Copy the entire `hoppy` folder into the Godot project. Keep each `.tres` beside its PNG so relative texture references resolve.
2. Assign `platformer.tres` or `brawler.tres` to an AnimatedSprite2D's Sprite Frames property.
3. Set Texture Filter to Nearest, Centered to true, and Offset to `(0, -40)`. This places the documented cell pivot `(48, 88)` at the actor's ground position. Use `flip_h` for left-facing movement.
4. Play the named animation from the gameplay state. Listen for animation_finished on one-shot actions. Use the shared platformer hurt/death/jump poses in the brawler as needed by switching SpriteFrames resources.
5. Keep collisions, attack windows, combo chaining, jump height and movement in the gameplay controller. The art contains no authoritative damage events. Suggested first tuning: jab impact around frame 3, overhead around frame 4, spin kick around frame 4 (one-based); verify against play feel.

The brawler should move on its ground plane and apply jump height to the visual child, keeping its ground sorting position stable, as proposed in the technical baseline. This pack uses right-facing side/three-quarter art for movement; it is not a complete eight-direction drawn animation set. Front/back walks, weapon variants and a dedicated brawler stagger are future art work. The platformer hurt animation is a stronger recoil/tumble, not a subtle stagger.

## Art direction and limits

Orange fur, cream muzzle/inner ears/tail, charcoal shirt, large readable eyes and long ears translate the references into a compact retro style. Shirt lettering was omitted to preserve legibility when small and allow mirroring. Both modes use the same scale; the brawler changes stance rather than body size. Character standing height is roughly 65–70 pixels inside each 96-pixel cell.

This is generated prototype artwork, ready for import and gameplay evaluation, not a claim of final hand-polished animation. Some frame-to-frame shape drift and edge speckling remain; a pixel cleanup pass and timing review are recommended before release. Grounded frames share a row baseline; airborne poses intentionally lift inside the frame. The original source is pixel-art styled rather than a strict hand-authored low-resolution palette.

## Verification

Both atlases preserve alpha and contain 36 populated frames. Mechanical slicing checks confirmed six separated poses per source row and no frame overflows during packing. Godot 4.7.1 successfully loaded both SpriteFrames resources and checked every referenced texture at 96 × 96. GIF metadata confirmed six-frame playback. The Godot editor import completed with sandbox-related user-settings warnings; the independent resource validation exited successfully. No game integration or combat playtest has been performed.

## Source documents

- GDD and technical baseline (internal design documents)
- User-supplied comic-p1.png through comic-p5.png; p1 and p3 used as generation inputs.
