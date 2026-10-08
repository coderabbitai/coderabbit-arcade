# code_city armed Hoppy pilot prompt

Built-in image generation, October 8, 2026. The source master preserves generated alpha unchanged. `tools/build_hoppy_armed.py` only crops, nearest-neighbour scales, registers, and packs it.

## Exact generation prompt

Create a NEW 16-bit pixel-art brawler animation sheet of EXACTLY the orange rabbit shown in the first reference: cream muzzle, long orange ears, black shirt, orange legs, small cream tail, friendly determined eyes. Have him visibly hold the blue cyan DEBUG STICK from the second reference image with BOTH paws wrapping its handle in every sprite. Preserve the debug stick's exact cyan-blue, dark navy, and gold colors and its baton shape. The weapon must be drawn at exactly the same chunky pixel density as the rabbit, not finer. Transparent alpha background. FOUR columns by FOUR rows, sixteen equally spaced complete sprites, large empty transparent gutters, 30px outer margin, no text, no borders, no ground, shadow, detached effects, duplicate character, or UI. Face RIGHT. Same character size, feet baseline, and weapon scale in every pose. Row-major: 1 ready idle at carry height below shoulder; 2 through 5 four-step sideways run cycle carrying stick; 6 through 8 thrust windup, thrust contact, thrust follow-through; 9 through 11 sweep windup, sweep contact, sweep follow-through; 12 through 14 sweep windup, sweep contact, sweep follow-through; 15 lifting stick after pickup; 16 stagger hurt while still holding stick. This is a clean in-game sprite sheet, not concept art.

## Refinements

Regenerations: 0. The first generated master was retained. After independent visual review, the deterministic packer was corrected to recover connected components across grid gutters, plant every frame's feet at its gameplay pivot, store per-frame hand and attack-tip anchors on solid painted pixels, and calibrate carry icons to the baked hold_idle weapon length. Ground-lined runtime clip strips were added for motion inspection. These were packing changes, not image regenerations.

Inspection note: The Code City thrust windup remains visually close to the carry pose. It was retained for pilot approval rather than regenerated.
