# heroes armed Hoppy generation prompts

Built-in image generation, October 8, 2026. Source masters preserve generated alpha unchanged. `tools/build_hoppy_armed.py` only crops, nearest-neighbour scales, registers, and packs artwork.

## review_stamp

### Exact generation prompt

Use case: precise-object-edit
Asset type: 4x4 transparent pixel-art brawler sprite-sheet source master
Input image: the provided 4x4 armored orange rabbit sprite sheet is the edit target.
Primary request: Change only row 3, columns 1 through 3, frames 9, 10, and 11, the three step-2 sweep poses. Preserve frames 1-8 and 12-16 exactly as provided: their pixels, pose, palette, transparent background, grid spacing, margins, and complete sprites.
Subject: the exact same armored orange rabbit, cream muzzle, long orange ears, black and charcoal suit, orange chest crest, belt, dark cape, orange legs, facing right.
Critical correction: In EACH of frames 9, 10, and 11, Hoppy holds a complete orange review-stamp with the rounded orange knob clearly enclosed by the near paw AND the full rectangular orange-and-black stamp base visibly attached below it. The rectangular base must be visible, chunky, opaque, and unmistakable, matching the base silhouette, orange, amber highlight, charcoal, white highlight, and steel-gray colours already visible in frames 6-8 and 12-14. It must not resemble a boxing glove, plunger, floating knob, club, or hammer.
Pose detail: Frame 9 sweep windup has stamp raised/back with complete base; frame 10 sweep contact projects the stamp forward with its complete rectangular base visible; frame 11 sweep follow-through has the complete base visibly attached and readable. Keep the knob in a rabbit paw in all three.
Style/medium: crisp 16-bit pixel art at the same chunky pixel density as every unchanged rabbit and stamp frame. Exact 4 columns x 4 rows, equal cell spacing, generous transparent gutters, no grid lines, no text, no shadows, no detached effects, no new characters, no backgrounds.
Constraints: change only frames 9-11; retain transparent alpha; every frame remains a single complete connected sprite fully inside its own cell; preserve rabbit identity and feet baseline.

### Refinements

Regenerations: 1. Regenerated and merged only the step 2 sweep sprites so each pose shows a complete orange-and-black rectangular stamp base beneath a rounded knob held in Hoppy's paw. The other thirteen approved source sprites remain unchanged.

## triage_hammer

### Exact generation prompt

Use case: stylized-concept
Asset type: project-bound 4 by 4 transparent source master for a Godot pixel-art brawler animation sheet.
Primary request: Create a NEW 16-bit pixel-art brawler animation sheet of the armored orange Hoppy holding the black, charcoal, orange, amber, and steel-gray triage hammer. In every sprite the full hammer head remains visibly attached to its handle and the paws visibly wrap the handle, never the head.
Animation layout: 1 carry idle; 2-5 run; 6-8 overhead hammer windup/contact/follow; 9-11 side hammer windup/contact/follow; 12-14 heavy downward slam windup/contact/follow; 15 equip; 16 hurt.
Constraints: transparent alpha, exactly four columns by four rows, one complete connected Hoppy-plus-hammer sprite per cell, large gutters, same identity, scale and foot baseline, no detached effects or clipped parts.

### Refinements

Regenerations: 0. The first generated master was retained. Hoppy holds the triage hammer by its handle in every cell, including overhead, side, and heavy-slam attacks.

## change_stack_baton

### Exact generation prompt

Use case: stylized-concept
Asset type: regenerated transparent 4 by 4 pixel-art source master for a Godot brawler.
Primary request: Create the armored orange Hoppy holding the long change-stack baton: a straight orange shaft with black segmented bands, silver-gray ring joints and orange end caps. Both paws visibly wrap the central grip in every cell.
Critical source-gate contract: exactly one opaque connected component per cell and exactly 16 major components in a strict four by four grid. Keep 50px transparent gutters, 30px outer margins, and do not leave any cell empty.
Animation layout: 1 carry idle; 2-5 run; 6-8 long thrust windup/contact/follow; 9-11 sweep windup/contact/follow; 12-14 long thrust windup/contact/follow; 15 equip; 16 hurt.
Constraints: transparent alpha; no text, border, ground, UI, background, detached effects, duplicate characters, or clipped baton ends.

### Refinements

Regenerations: 1. Generation zero had duplicate grid-cell component centroids. A full-sheet regeneration retained the two-paw central baton grip and enforced exactly one fully connected Hoppy-plus-baton sprite in each source cell.

## security_scanner

### Exact generation prompt

Use case: stylized-concept
Asset type: project-bound 4 by 4 transparent source master for a Godot pixel-art brawler animation sheet.
Primary request: Create the armored orange Hoppy carrying the handheld security scanner, preserving its orange casing, charcoal scan head, gray details, neon-green square radar screen and orange pistol-style handle. The near paw visibly wraps the handle in every sprite.
Animation layout: 1 carry idle; 2-5 run; 6-8 scan sweep windup/contact/follow; 9-11 focused scan windup/contact/follow; 12-14 scanner pulse windup/contact/follow; 15 equip; 16 hurt.
Constraints: transparent alpha, exactly four columns by four rows, one complete connected Hoppy-plus-scanner per cell, large gutters, same identity, scale and foot baseline, no detached beams, HUD shapes, effects or clipped parts.

### Refinements

Regenerations: 0. The first generated master was retained. It uses the unused scanner pose in hoppy.tres as the style anchor and keeps the complete scanner attached to its orange handle in every cell.

## pr_merger

### Exact generation prompt

Use case: stylized-concept
Asset type: regenerated transparent 4 by 4 pixel-art source master for a Godot brawler.
Primary request: Create the armored orange Hoppy with a pr_merger powered gauntlet worn on the forward paw in every sprite. The wrist, paw and cuff must be one continuous opaque connected silhouette with no transparent gap, floating gauntlet, handle, or held prop.
Critical source-gate contract: exactly one opaque connected component per cell and exactly 16 major components in a strict four by four grid.
Animation layout: 1 ready; 2-5 run; 6-8 jab windup/contact/follow; 9-11 hook windup/contact/follow; 12-14 uppercut windup/contact/follow; 15 equip flex; 16 hurt.
Constraints: transparent alpha, same Hoppy identity, scale and foot baseline; no text, background, effects, detached alpha, duplicate character or clipped parts.

### Refinements

Regenerations: 2. Generation zero visually read as a worn gauntlet but separated four gauntlets from Hoppy in alpha. Generation one joined the cuff but placed frame 14 too far above its source grid for safe registration. The second full-sheet regeneration retains the solid wrist-to-cuff connection while fitting the packed frame inside its cell.
