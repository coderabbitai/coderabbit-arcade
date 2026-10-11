# Armed Hoppy supplement

Baked sprite sheets of Hoppy holding each beat'em up weapon. The weapon is drawn into Hoppy's frames, so the grip, pixel density and layering match the body in every pose. There are eleven sheets: six for Code City Brawl (`code_city/`) and five for Heroes vs. Villains (`heroes/`).

The masters come from built-in image generation. `tools/build_hoppy_armed.py` never paints or edits a master. It finds the generated sprites, scales them with nearest-neighbour sampling, plants their feet on the pivot and packs the outputs, so the same masters always rebuild the same files.

## Cells and pivots

| Mode | Directory | Cell | Foot pivot | Unarmed idle height | `run` speed | Weapons |
|---|---|---|---|---:|---:|---|
| Code City Brawl | `code_city/` | 192 × 128 | (72, 118) | 59 px | 13 fps | `debug_stick`, `linter_staff`, `api_key_whip`, `git_branch`, `refactor_hammer`, `firewall_shield` |
| Heroes vs. Villains | `heroes/` | 256 × 160 | (96, 147) | 86 px | 7 fps | `review_stamp`, `triage_hammer`, `change_stack_baton`, `security_scanner`, `pr_merger` |

Every sheet faces right and is mirrored at runtime. The cells are wider than the body so a whip lash or an overhead hammer fits; the pivot sits left of centre to leave forward room. Each sheet uses one uniform scale, chosen so that the body in `hold_idle` matches the mode's unarmed idle height to within 2 px. The scale shrinks only if the tallest pose wouldn't otherwise fit above the pivot.

## Sheet layout

Heroes `<weapon>.png` sheets remain 4 × 4 atlases. Code City sheets are 4 × 8, with 30 populated cells and two transparent padding cells. The original cells retain their indices:

| Frames | Clip | Content |
|---|---|---|
| 0 | `hold_idle` | Ready stance, weapon at carry height (1 frame, loops) |
| 1–4 | Heroes `run` | Original sideways run; retained but unused in Code City |
| 5–7 | `step1` | Combo step 1: windup, contact, follow-through |
| 8–10 | `step2` | Combo step 2: windup, contact, follow-through |
| 11–13 | `step3` | Combo step 3: windup, contact, follow-through |
| 14 | `equip` | Lifting the weapon after a pickup |
| 15 | `hurt` | Stagger while holding it (the Firewall Shield's block recoil) |

Code City appends six `run` frames at cells 16-21 (13 fps), four `walk_up` frames at 22-25 and four `walk_down` frames at 26-29 (9 fps). All locomotion clips loop. These are separately generated full-body poses holding the weapon. The six run frames alternate open contacts and bent-knee passing poses. Their soles register to x = 84, 72, 60, 84, 72, 60 at y = 118. Each stance moves 12 sprite pixels backward per frame, matching 241.8 world px/s at the runtime scale 1.55, within 1% of the normal speed 240.

The `locomotion` manifest object records source filenames, source cell indices, extraction bounds, per-source scale adjustments, paw and foot anchors, stance positions and cadence. Git branch combines corrected back views with two complete front views from generation zero. Earlier, clipped rightmost source poses are never packed. Every source is preserved unchanged.

The attack steps are SpriteFrames clips at 9 fps, but the game picks their frame from attack progress: windup before 30%, contact until 64%, follow-through after that. Damage still lands at 44%, inside the contact frame.

## Files in each mode directory

| File | Purpose |
|---|---|
| `<weapon>.png`, `<weapon>.tres` | Packed atlas and its SpriteFrames resource |
| `manifest.json` | Per weapon: cell, pivot, facing, body height, source scale, clips, source component bounds, fragment attachments, and per-frame `hand`, `foot` and contact-frame `tip` anchors. `carry_calibration` records how every carry icon was scaled. |
| `carry/<weapon>.png` | The weapon cel, scaled to the weapon's length in the baked `hold_idle` so it has the sheet's pixel density. On poses with no armed frame, the runtime draws it at the paw, at the body's scale: jumping and, in Heroes vs. Villains, vertical walking, defeat and victory. Code City vertical walking uses the new baked clips when player routing enables them. Each mode's weapon rig draws it behind the body wherever it would otherwise cover Hoppy's face (`carry_behind`). |
| `<weapon>_preview.png` | Contact sheet of all populated cells next to the unarmed idle, at 2× |
| `<weapon>_clips.png` | Each runtime clip on a ground line drawn at the foot pivot, for motion review |
| `preview.png`, `clips.png` | The same views for the mode's first (pilot) weapon |
| `sources/<weapon>.png` | The retained generated master, untouched. Earlier generations kept for the record are named `sources/<weapon>-generation<N>.png`; the builder only reads `sources/<weapon>.png`. |
| `locomotion_contact.png`, `<weapon>_locomotion.png` | Four directional walking strips, including runtime horizontal mirroring |
| `sources/<weapon>-locomotion.png`, `locomotion.json` | Code City locomotion masters and exact generation prompts |
| `refinements.json` | Per weapon: the exact generation prompt, the number of regenerations and what changed |
| `PROMPTS.md` | Rendered by the builder from `refinements.json`, the Code City locomotion/refinement prompts, plus the pilot's generation-zero prompt (`Mode.prompt`) when no record already holds it; don't edit it by hand |

## Rebuilding

```sh
uvx --with pillow python tools/build_hoppy_armed.py --mode code_city
uvx --with pillow python tools/build_hoppy_armed.py --mode heroes
```

Leave out `--mode` to rebuild both. Run it from the repository root, then reimport the project (`godot --headless --path hoppys-adventure-arcade --import`). The build stops with an error rather than writing a suspect sheet when, for example:

- a master doesn't have exactly sixteen major sprites, one per grid quarter, or a sprite touches the master's edge;
- a small fragment (such as the thin end of a whip) lies more than 10 source pixels from every sprite;
- a packed frame touches its cell edge;
- with `per_frame_foot_pivot`, the planted foot (the painted run at each frame's registered planted x) moves more than about 3 px between frames of a clip, or a sole misses the pivot row. Run clips are exempt from the planted-foot check, since a run alternates its feet by design;
- for the original Heroes and preserved legacy Code City cells, the body moves more than 3 px between consecutive run frames, the loop seam included. The body is measured weapon-free, from the opaque pixels behind the paw, and the builder prints each weapon's run body x;
- a hand or tip anchor has no opaque pixel near its hand-picked target;
- a weapon's `hold_idle_weapon_bounds` fall outside the `hold_idle` cell or cover no opaque pixels;
- a carry icon drifts more than 10% from its calibrated length;
- the mode's `refinements.json` is missing or malformed, since `PROMPTS.md` is generated from it.

`tests/hoppy_armed_assets.gd` checks the packed result: all eleven sheets must be present with their resources, manifest entries, masters and carry icons, and each one's frames, clips, pivot, anchors, body height and carry calibration must match the contract.

## Per-weapon configuration

Each weapon is a `Weapon` entry in the mode's `extra_weapons` in `tools/build_hoppy_armed.py`. The pilot weapon uses the mode-level fields instead. Required fields:

- `hand_targets`: 16 hand-picked paw points in unregistered frame space. Each is snapped to the nearest opaque pixel and recorded as the `hand` anchor.
- `tip_targets`: weapon tips for the contact frames 6, 9 and 12, recorded as the `tip` anchor. Swing and miss effects and the contact trail start there.
- `foot_source_rows`: 16 hand-inspected rows, in master pixels from the top of each sprite's grid cell, where the planted foot meets the ground.
- `hold_idle_weapon_bounds`: the visible weapon's box in the `hold_idle` cell, used to size the carry icon.
- `motion`: a short note on the three combo steps.

Opt-in fields. Leaving one out keeps the default behaviour, and turning one on for a weapon changes no other weapon's output:

| Field | Effect |
|---|---|
| `per_frame_foot_pivot` | Registers each frame horizontally on its planted foot instead of using one sheet-wide offset. Idle, run, equip and hurt use the centre of the feet; attack frames use the rear foot. The build fails if that foot moves more than about 3 px between frames of a clip, so Hoppy doesn't skate. |
| `foot_plant_overrides`, `foot_plant_note` | Per-frame `center` / `rear` / `front` choice for the planted foot, and a note explaining it in the manifest. |
| `body_foot_targets` | 16 optional `(left, right)` x spans, in packed-cell pixels before registration, that name the foot to plant for frames where a low weapon shares the foot row. |
| `run_register` | `"body"` registers each run frame so the weapon-free body holds still over the cycle while the feet stay on the pivot row and the legs cycle. Frames with a `body_foot_target` keep it. Heroes and the preserved original Code City cells use it; new Code City locomotion uses foot registration instead; without it, run frames are registered on the foot centre and the body can surge 25 px or more between frames. |
| `source_order` | Maps each packed frame to a source cell, for masters whose poses came out in a different order, or to reuse a cell. Four Heroes vs. Villains sheets reorder their step-3 cells this way. `api_key_whip` reuses its step-1 follow-through (source cell 7) as the step-3 follow-through (frame 13). |
| `carry_orientation`, `carry_grip` | Flips or rotates the carry icon (`flip_h`, `flip_v` or `rotate_180`) for a weapon whose sheet holds it by the other end from its cel. `carry_grip` is required with it: the oriented icon's texel held in the paw, which must be opaque. Both are written to `carry_calibration` in the manifest; Code City's weapon rig uses that grip in place of its cel grip. `api_key_whip` and `refactor_hammer` use `flip_h`, so their carries put the key or the hammer head at the far end, as on the sheet. (Heroes vs. Villains turns its scanner carry in the rig instead, so the screen stays clear of Hoppy's face.) |

## Adding a weapon

1. Generate a 4 × 4 master with transparent alpha, following the prompt pattern in the mode's `refinements.json`. Use the mode's Hoppy combat sheet and the weapon cel as references. Keep large empty gutters and the 16-pose order above.
2. Save the retained master as `<mode>/sources/<weapon>.png` and add a `refinements.json` record with its exact prompt, the regeneration count and a description of what changed.
3. Add the weapon to the mode's `carry_frames` (its cel index in the weapon atlas) and add a `Weapon(...)` entry to `extra_weapons`. Pick the hand, tip and foot rows from the unregistered frames, and turn on an opt-in field only where a frame needs it.
4. Rebuild the mode, check `git status` to confirm the other weapons' files didn't change, and review `<weapon>_preview.png` and `<weapon>_clips.png`.
5. Add the weapon id to `EXPECTED` in `tests/hoppy_armed_assets.gd`. Then run that suite and the mode's motion suite, both headless and rendered with `--always-on-top`.

Licensing and brand status are recorded in [`ASSETS_LICENSES.md`](../../../ASSETS_LICENSES.md).
