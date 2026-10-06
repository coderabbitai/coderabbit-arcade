# Heroes vs. Villains — assets only

An orange-and-black action-figure collection for Hoppy's Adventure Arcade, created October 6, 2026 from the updated GDD and the supplied booth reference.

Open **`preview.html`** to browse sprites and key-pose action sequences. Open any scene in **`presentation/`** in Godot and press F6 to inspect it. Start with `generation_floor.tscn` or `boss_ai_slop.tscn`.

- Armored CodeRabbit Hoppy variant; 12 enemy identities; four villains across three encounters.
- 208 transparent poses, 247 named clips, 22 SpriteFrames resources.
- Three 1280×720 stage panoramas and staged Parallax2D examples.
- Six breakables with intact/damaged/destroyed states, hazards, five weapons, pickups, three allies, status/capability effects.
- Four editable blister-pack intro cards, four capability cards, three opening panels and a victory panel.
- Eight original synthesized WAV cue sketches.
- `content_catalog.json`: source-grounded enemy behavior, boss phases, moveset-to-art links, item effects and unresolved design decisions.

This pack is **asset preparation**, not playable Mode 2. Action sequences use a few key poses, not full in-between animation. Hoppy is a new **2D sprite variant**, not a rigged 3D model. Combat, collision, AI, progression, presentation sequencing and menu activation belong to the gameplay pass.

See [ASSET_GUIDE.md](ASSET_GUIDE.md) for use, coverage, limitations and rebuild commands. Source masters and exact built-in image-generation prompts are preserved in `sources/`, `generation.json` and [PROMPTS.md](PROMPTS.md). No nested Godot project is included.
