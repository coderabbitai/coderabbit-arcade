# Beat'em-up story illustration prompts

Built-in image generation, October 8, 2026. Each scene has exactly one provenance record in `refinements.json`; selected and superseded masters remain untouched in `sources/`. `tools/build_story_scenes.py` only cover-crops, scales, packs and previews that artwork.

## code_city: under_siege

Selected master: `code_city/sources/under_siege-generation0.png`. Retained masters: `code_city/sources/under_siege-generation0.png`.

### Exact generation prompt history

#### Generation 0

Use case: illustration-story
Asset type: full-screen in-game cinematic scene, to be cover-cropped to 16:9
Primary request: A 16-bit painted pixel-art cinematic illustration titled only by its visual story, not by any written text. Night skyline of Code City under siege. A ruptured glowing cyan review pipeline runs across the middle distance and breaks open, spilling several distinct rogue-code monsters and dark orange slop-code creatures into the rain-slick streets. City terminals and building lights visibly flicker and go dark, while a few emergency red and cyan lights remain. The story must read immediately as a software city being invaded.
Scene/backdrop: dense futuristic cyberpunk city at night, elevated transit rails, angular server towers, wet reflective rooftop and street surfaces.
Subject: the broken luminous pipeline and invasion, with clear villain silhouettes in the central 80 percent of the frame.
Style/medium: polished 16-bit painted pixel art, chunky pixels, crisp dark outlines, detailed but game-readable, deliberately coherent perspective.
Composition/framing: cinematic 16:9 wide shot; low rooftop foreground, ruptured pipeline centered slightly above midline, invading creatures grouped at center and center-right; leave no UI or caption panel inside the artwork.
Lighting/mood: urgent stormy night, teal and cyan neon with small sickly green terminal light, contrasting crimson danger sparks.
Color palette: deep navy, charcoal black, teal, cyan, electric green, small orange-red alert accents.
Materials/textures: wet metal, glowing terminal glass, pixel rain, fractured energy conduit.
Text (verbatim): ""
Constraints: no readable text, no words, no logos, no watermark, no UI, no typography, no letterforms, no human faces, no duplicated focal creature, no malformed limbs; keep every key subject in the central 80 percent because the game pans and zooms; illustration only, not a sprite sheet or comic panel.
Avoid: photorealism, smooth vector art, blurry pixels, collage, text signs, branded symbols.

### Refinements

Regenerations: 0. The first generated master was retained. The ruptured cyan review pipeline, flickering terminals, rogue-code silhouettes and orange slop creatures all remain inside the runtime-safe central composition.

## code_city: pipeline_breached

Selected master: `code_city/sources/pipeline_breached-generation0.png`. Retained masters: `code_city/sources/pipeline_breached-generation0.png`.

### Exact generation prompt history

#### Generation 0

Use case: illustration-story
Asset type: full-screen in-game cinematic scene, to be cover-cropped to 16:9
Primary request: A 16-bit painted pixel-art cinematic illustration of Git HQ breached by a colossal grand merge conflict. A futuristic cathedral-like source-control headquarters of dark navy metal and cyan servers is strangled by tangled glowing branch cables, with a fractured crimson firewall wall splitting behind it. The Grand Merge Conflict is a huge broad-shouldered two-toned blue-and-crimson cyber brute with black armor and a bright split-color diamond core in its chest, looming from the central distance. It must clearly threaten the headquarters.
Scene/backdrop: night Code City Git HQ, monumental server chamber opening toward a neon city skyline, elevated rails and server columns.
Subject: the single looming merge-conflict boss amid a storm of tangled branch cables and a cracking red firewall, all inside the central 80 percent of frame.
Style/medium: polished 16-bit painted pixel art, chunky pixels, crisp dark outlines, detailed but game-readable, coherent perspective.
Composition/framing: cinematic 16:9 wide shot from a low central viewpoint; boss centered in the middle-distance, cables twist from foreground into the scene, split firewall glow behind, clean edges for runtime crop.
Lighting/mood: catastrophic cyberpunk alarm, dark teal and cyan ambient light with hot crimson fracture light and magenta sparks.
Color palette: deep navy, near-black steel, teal, cyan, cobalt blue, crimson, magenta, limited bright white highlights.
Materials/textures: wet metal floor, coiled energy cables, broken glowing firewall lattice, server glass.
Text (verbatim): ""
Constraints: no readable text, no words, no logos, no watermark, no UI, no typography, no letterforms, no other major character, no duplicated boss, no malformed anatomy; keep key subjects central because the game pans and zooms; illustration only, not a sprite sheet or comic panel.
Avoid: photorealism, smooth vector art, blurry pixels, collage, text signs, branded symbols.

### Refinements

Regenerations: 0. The first generated master was retained. The split blue-and-crimson Grand Merge Conflict, branch cables and cracked firewall make the breach legible without in-image copy.

## code_city: hoppy_clocks_in

Selected master: `code_city/sources/hoppy_clocks_in-generation1.png`. Retained masters: `code_city/sources/hoppy_clocks_in-generation0.png`, `code_city/sources/hoppy_clocks_in-generation1.png`.

### Exact generation prompt history

#### Generation 0

Use case: illustration-story
Asset type: full-screen in-game cinematic scene, to be cover-cropped to 16:9
Primary request: A 16-bit painted pixel-art cinematic illustration of Hoppy answering the call in Code City. Hoppy is a single unarmored orange rabbit hero with a cream muzzle and belly, two long orange ears, determined friendly eyes, a plain black short-sleeve shirt, charcoal pants, orange legs and a small cream tail. He stands confidently on a rain-slick rooftop, seen three-quarter from behind and side so his orange rabbit face is unmistakable. He holds a short cyan-blue debug baton in one paw, pointed down in a ready stance. Far below, the Code City districts are under teal neon threat and storm clouds.
Scene/backdrop: wide night cyberpunk skyline with layered server towers, elevated rails, teal and cyan terminal lights, wet industrial roof.
Subject: Hoppy, large enough to read clearly and placed in the center-lower portion of the central 80 percent, facing toward the crisis.
Style/medium: polished 16-bit painted pixel art, chunky pixels, crisp dark outlines, detailed but game-readable, coherent anatomy.
Composition/framing: cinematic 16:9 wide frame, Hoppy near center on a rooftop ledge, skyline fills background, a clean silhouette around ears and baton; leave no UI or caption panel inside artwork.
Lighting/mood: determined calm before action; moonlit navy shadows, cyan rim light on Hoppy, small orange edge light.
Color palette: deep navy, charcoal, teal, cyan, emerald terminal lights, restrained orange fur and crimson distant alerts.
Materials/textures: wet metal roof, lit windows, soft pixel rain, luminous debug baton.
Text (verbatim): ""
Constraints: no readable text, no words, no logos, no watermark, no UI, no typography, no letterforms, no armor, no cape, no human character, exactly one Hoppy, no extra limbs, no malformed paws; keep key subject inside central 80 percent because game pans and zooms; illustration only, not a sprite sheet or comic panel.
Avoid: photorealism, smooth vector art, blurry pixels, collage, text signs, branded symbols.

#### Generation 1

Use case: precise-object-edit
Asset type: full-screen in-game cinematic scene, cover-cropped to 16:9
Input images: Image 1 is the edit target whose composition, rooftop, skyline, palette, rain, ready stance, camera angle, cyan debug stick, and unarmored Hoppy identity must be preserved. Image 2 is the authoritative in-game Code City Hoppy character reference.
Primary request: Change only Hoppy's lower-body clothing in Image 1 so Hoppy exactly matches the unarmored Code City sprite in Image 2: he is an orange rabbit with a cream muzzle, two long orange ears, a plain black short-sleeve t-shirt, a small cream tail, completely bare orange legs, and completely bare orange rabbit feet. Remove all dark cargo pants, trousers, leg armor, knee pads, waistband, utility pockets, belt, buckle, holster, or any other lower-body clothing or accessory. The orange legs must visibly continue directly from the hem of the black t-shirt down to bare orange feet, like the sprite reference.
Scene/backdrop: preserve the rainy Code City rooftop at night with the teal/cyan cyberpunk skyline and distant threatened district.
Subject: the single unarmored Hoppy remains in the original center-lower ready stance with the short cyan debug baton in his paw.
Style/medium: preserve the polished 16-bit painted pixel art, chunky pixels and crisp outlines of Image 1 while matching Image 2's unarmored rabbit identity.
Composition/framing: preserve Image 1's cinematic 16:9 composition and Hoppy placement. Keep Hoppy's face, torso, baton and villains-free skyline inside the safe y approximately 12 to 78 percent of the frame and central 80 percent horizontally.
Lighting/mood: preserve moonlit navy shadows, cyan rim light, orange fur edge light, teal/cyan skyline and pixel rain.
Text (verbatim): ""
Constraints: change only the character's pants and belt area; keep all other scene content and overall framing unchanged; no readable text, words, logos, watermark, UI, typography, letterforms, armor, cape, human character, additional Hoppy, extra limbs, malformed paws, pants, belt, belt buckle, cargo pockets, trousers or footwear.
Avoid: photorealism, smooth vector art, blurry pixels, collage, text signs, branded symbols.

### Refinements

Regenerations: 1. Generation zero dressed Hoppy in dark cargo pants and a belt, which did not match the in-game Code City sprite. Generation one keeps the rooftop, teal/cyan skyline, ready stance and cyan debug baton while replacing every lower-body garment with bare orange rabbit legs and feet under the black T-shirt.

## heroes: situation

Selected master: `heroes/sources/situation-generation1.png`. Retained masters: `heroes/sources/situation-generation0.png`, `heroes/sources/situation-generation1.png`.

### Exact generation prompt history

#### Generation 0

Use case: illustration-story
Asset type: full-screen in-game cinematic scene, to be cover-cropped to 16:9
Primary request: A 16-bit painted pixel-art cinematic illustration of the Heroes versus Villains situation. A monumental re:Invent-style Generation Floor, warm orange and white expo architecture with blue holographic cube light, is buried beneath endless blank vertical code-review scrolls and stacks of glowing screens. Several tiny developer silhouettes in dark casual clothing are overwhelmed in the center, dwarfed by paperwork screens and the expo hall. The scene must read as a huge review backlog crushing the human team.
Scene/backdrop: sleek bright technology expo hall, orange trusses and signage panels with absolutely no text, white polished floor, glass high-rise view, floating blue cube holograms, balconies and orange accents.
Subject: blank review scrolls, massive screen stacks and the small overwhelmed developers inside the central 80 percent.
Style/medium: polished 16-bit painted pixel art, chunky pixels, crisp dark outlines, detailed but game-readable, coherent perspective.
Composition/framing: cinematic 16:9 wide shot from a slightly low frontal view; keep the expo hall symmetrical enough to feel grand, use layered blank scrolls and screens to frame the central team; leave no UI or caption panel inside artwork.
Lighting/mood: bright but anxious; warm orange key lights reflect in the white floor, cool blue holographic highlights.
Color palette: white, warm orange, charcoal, cobalt and cyan blue, pale glass gray, touches of greenery.
Materials/textures: polished reflective expo floor, truss metal, acrylic screens, glowing cube holograms, stacked blank review pages.
Text (verbatim): ""
Constraints: no readable text, no words, no logos, no watermark, no UI, no typography, no letterforms, no legible code, no human face closeups, no monsters, no Hoppy, no malformed hands or limbs; keep key subjects central because the game pans and zooms; illustration only, not a sprite sheet or comic panel.
Avoid: photorealism, smooth vector art, blurry pixels, collage, text signs, branded symbols.

#### Generation 1

Use case: illustration-story
Asset type: full-screen in-game cinematic scene, to be cover-cropped to 16:9
Primary request: Regenerate a 16-bit painted pixel-art cinematic illustration of the Heroes versus Villains situation with one precise correction: show the overloaded Generation Floor using gigantic completely BLANK ivory review-scroll slabs and stacks of completely BLANK paper, with absolutely no printed lines, marks, glyphs, symbols, text, code, icons, or writing anywhere. Keep the intended scene: a monumental warm orange-and-white re:Invent-style expo hall with blue holographic cubes, several tiny overwhelmed developer silhouettes, blank glowing monitors, and the visual feeling of endless review backlog.
Scene/backdrop: sleek bright technology expo hall, orange trusses, white polished floor, glass high-rise view, floating blue cube holograms, balconies and orange accents.
Subject: smooth blank review-scroll slabs, smooth blank paper stacks, blank lit screen rectangles and small overwhelmed developers, within central 80 percent.
Style/medium: polished 16-bit painted pixel art, chunky pixels, crisp dark outlines, detailed but game-readable, coherent perspective.
Composition/framing: cinematic 16:9 wide shot from a slightly low frontal view; layered blank slabs frame the central team; leave no UI or caption panel inside artwork.
Lighting/mood: bright but anxious; warm orange key lights reflect in white floor, cool blue holographic highlights.
Color palette: white, warm orange, charcoal, cobalt and cyan blue, pale glass gray, small greenery.
Materials/textures: polished reflective expo floor, truss metal, acrylic blank screen panels, glowing cube holograms, smooth unmarked blank paper.
Text (verbatim): ""
Constraints: no readable text, no pseudo-text, no words, no lines on paper, no logos, no watermark, no UI, no typography, no letterforms, no legible code, no human face closeups, no monsters, no Hoppy, no malformed hands or limbs; key subjects inside central 80 percent because game pans and zooms; illustration only, not a sprite sheet or comic panel.
Avoid: photorealism, smooth vector art, blurry pixels, collage, text signs, branded symbols.

### Refinements

Regenerations: 1. Generation zero left faint document-like marks on the backlog props. Generation one retains the same overwhelmed Generation Floor composition while replacing them with completely blank ivory review-scroll slabs and paper stacks.

## heroes: complication

Selected master: `heroes/sources/complication-generation0.png`. Retained masters: `heroes/sources/complication-generation0.png`.

### Exact generation prompt history

#### Generation 0

Use case: illustration-story
Asset type: full-screen in-game cinematic scene, to be cover-cropped to 16:9
Primary request: A 16-bit painted pixel-art cinematic illustration of the Heroes versus Villains complication. The bright orange-and-white expo generation floor is overrun by three readable threats: a huge orange AI Slop monster oozing across the polished floor, with dark tangled cables and blank paper scraps embedded in it; an orderly multiplying formation of white and charcoal humanoid agent robots with orange chest lights; and a tall ominous AI-Augmented Hacker, a hooded black cyber figure with a long dark red-lined coat, green-lit mask and green data energy, appearing on a large blank screen and in the distance. This must tell the story of villains multiplying in the expo hall.
Scene/backdrop: re:Invent-style Generation Floor with orange trusses, white levels, blue holographic cubes, polished white floor, screens that contain no text.
Subject: orange slop in center foreground, agent army ranks center-right, hooded hacker visually distinct in center-rear, all inside central 80 percent of frame.
Style/medium: polished 16-bit painted pixel art, chunky pixels, crisp dark outlines, detailed but game-readable, coherent anatomy.
Composition/framing: cinematic 16:9 wide shot with the slop monster closest, robot army encircling it, the hacker looming behind; use clear silhouettes and leave no UI or caption panel inside artwork.
Lighting/mood: alarming takeover, hot orange reflections against cold blue holograms and sickly green hacker light.
Color palette: warm orange, white, charcoal, cobalt/cyan blue, toxic neon green, a restrained dark crimson coat lining.
Materials/textures: glossy expo floor, goo, cable bundles, acrylic holographic screens, metal robots.
Text (verbatim): ""
Constraints: no readable text, no words, no logos, no watermark, no UI, no typography, no letterforms, no legible code, no Hoppy, no duplicated main villain, no malformed limbs or hands; keep key subjects central because the game pans and zooms; illustration only, not a sprite sheet or comic panel.
Avoid: photorealism, smooth vector art, blurry pixels, collage, text signs, branded symbols.

### Refinements

Regenerations: 0. The first generated master was retained. Orange AI Slop, the white-orange agent army and the green-lit AI-Augmented Hacker occupy distinct visual layers in the same expo hall.

## heroes: send_in_the_rabbit

Selected master: `heroes/sources/send_in_the_rabbit-generation0.png`. Retained masters: `heroes/sources/send_in_the_rabbit-generation0.png`.

### Exact generation prompt history

#### Generation 0

Use case: illustration-story
Asset type: full-screen in-game cinematic scene, to be cover-cropped to 16:9
Primary request: A 16-bit painted pixel-art cinematic hero-arrival illustration for Heroes versus Villains. A single armored Hoppy arrives under a bright orange emergency alert beacon in a futuristic expo hall. Hoppy is unmistakably an orange rabbit with cream muzzle and belly, two long orange ears, friendly determined eyes, black and charcoal armored suit with an orange chest crest and belt, orange legs, and a flowing dark charcoal cape with warm orange lining. He lands in a strong ready stance, cape swept backward, one raised paw, no weapon. Behind him but secondary are the threatening silhouettes of orange AI slop, white-orange agent robots, and a distant hooded black-and-red hacker with green glow. The story must clearly say: send in the rabbit.
Scene/backdrop: bright re:Invent-style Generation Floor with orange trusses, white architecture, blue holographic cubes, polished floor, no text anywhere.
Subject: armored caped Hoppy centered in the central 80 percent, large and silhouette-readable under the beacon, villains held in the middle-distance behind him.
Style/medium: polished 16-bit painted pixel art, chunky pixels, crisp dark outlines, detailed but game-readable, coherent anatomy.
Composition/framing: cinematic 16:9 wide shot from a slightly low heroic angle; beacon high and centered, Hoppy center foreground, cape visible, villains recede behind; leave no UI or caption panel inside artwork.
Lighting/mood: urgent heroic arrival; orange beacon rim lights Hoppy and floor, cool blue expo holograms, small sinister green glow behind.
Color palette: orange, amber, white, charcoal black, cobalt/cyan blue, restrained green and dark crimson accents.
Materials/textures: glossy floor reflections, metal trusses, pixel smoke, holographic light, flowing fabric cape.
Text (verbatim): ""
Constraints: no readable text, no words, no logos, no watermark, no UI, no typography, no letterforms, exactly one Hoppy, no unarmored shirt, no extra limbs, no malformed paws; keep key subject inside central 80 percent because the game pans and zooms; illustration only, not a sprite sheet or comic panel.
Avoid: photorealism, smooth vector art, blurry pixels, collage, text signs, branded symbols.

### Refinements

Regenerations: 0. The first generated master was retained. Armored, caped Hoppy lands under an orange alert beacon with the slop, agent army and hacker held behind as secondary threats.
