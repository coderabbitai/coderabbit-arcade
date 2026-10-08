# heroes armed Hoppy pilot prompt

Built-in image generation, October 8, 2026. The source master preserves generated alpha unchanged. `tools/build_hoppy_armed.py` only crops, nearest-neighbour scales, registers, and packs it.

## Exact generation prompt

Create a NEW 16-bit pixel-art brawler animation sheet of EXACTLY the armored orange rabbit shown in the first reference: cream muzzle, long orange ears, black and charcoal armored suit, orange chest crest, belt, dark cape, orange legs, friendly determined eyes. Have him visibly hold the orange REVIEW STAMP from the second reference image with both paws wrapping the stamp handle in every sprite. Preserve the stamp's exact orange, amber, white highlight, charcoal and steel-gray colors, rectangular stamping base, and rubber-stamp silhouette. The stamp must be drawn at exactly the same chunky pixel density as the rabbit, not finer. Transparent alpha background. FOUR columns by FOUR rows, sixteen equally spaced complete sprites, large empty transparent gutters, 30px outer margin, no text, no borders, no ground, shadow, detached effects, duplicate character, or UI. Face RIGHT. Same character size, feet baseline, and weapon scale in every pose. Row-major: 1 ready idle with stamp at carry height below shoulder; 2 through 5 four-step sideways run cycle carrying it; 6 through 8 stamp-down windup, contact, follow-through; 9 through 11 sweep windup, contact, follow-through; 12 through 14 slam windup, contact, follow-through; 15 lifting stamp after pickup; 16 stagger hurt while still holding stamp. This is a clean in-game sprite sheet, not concept art.

## Refinements

Regenerations: 1. Juan approved the pilot style and requested one targeted redo of the step 2 sweep frames. The generation-zero master is retained in `sources/review_stamp-generation0.png`. Only regenerated connected sprites 9, 10, and 11 were merged into the approved master; the other thirteen source sprites remain unchanged. The deterministic packer then recovered components across grid gutters, planted every frame's feet at its gameplay pivot, stored per-frame hand and attack-tip anchors on solid painted pixels, and calibrated carry icons to the baked hold_idle weapon length.

### Regeneration 1 refinement prompt

Use case: precise-object-edit
Asset type: 4x4 transparent pixel-art brawler sprite-sheet source master
Input image: the provided 4x4 armored orange rabbit sprite sheet is the edit target.
Primary request: Change only row 3, columns 1 through 3, frames 9, 10, and 11, the three step-2 sweep poses. Preserve frames 1-8 and 12-16 exactly as provided: their pixels, pose, palette, transparent background, grid spacing, margins, and complete sprites.
Subject: the exact same armored orange rabbit, cream muzzle, long orange ears, black and charcoal suit, orange chest crest, belt, dark cape, orange legs, facing right.
Critical correction: In EACH of frames 9, 10, and 11, Hoppy holds a complete orange review-stamp with the rounded orange knob clearly enclosed by the near paw AND the full rectangular orange-and-black stamp base visibly attached below it. The rectangular base must be visible, chunky, opaque, and unmistakable, matching the base silhouette, orange, amber highlight, charcoal, white highlight, and steel-gray colours already visible in frames 6-8 and 12-14. It must not resemble a boxing glove, plunger, floating knob, club, or hammer.
Pose detail: Frame 9 sweep windup has stamp raised/back with complete base; frame 10 sweep contact projects the stamp forward with its complete rectangular base visible; frame 11 sweep follow-through has the complete base visibly attached and readable. Keep the knob in a rabbit paw in all three.
Style/medium: crisp 16-bit pixel art at the same chunky pixel density as every unchanged rabbit and stamp frame. Exact 4 columns x 4 rows, equal cell spacing, generous transparent gutters, no grid lines, no text, no shadows, no detached effects, no new characters, no backgrounds.
Constraints: change only frames 9-11; retain transparent alpha; every frame remains a single complete connected sprite fully inside its own cell; preserve rabbit identity and feet baseline.

Inspection result: Frames 9-11 now show the complete rectangular stamp base, with the rounded knob held in Hoppy's paw. This was a targeted art regeneration; registration, anchors, carries, previews, and clip strips were rebuilt afterward.
