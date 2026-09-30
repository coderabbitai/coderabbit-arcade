# Orbital Ops — assets only

Imported into the existing Hoppy’s Adventure Arcade Godot project on September 30, 2026.

Open `preview.html` for the animated gallery, or `orbital-ops-preview.png` for the staged Godot render. See `ASSET_GUIDE.md` for coverage, pivots, and the proposed Deprecated API moveset.

- `orbital_ops/`: five transparent PNG atlases, five ready-to-assign SpriteFrames `.tres` files, two background layers, and `manifest.json`.
- `frames/`: all 88 new individual frames.
- `individual/`: first-frame PNGs for all 56 named clips/states.
- `animations/`: 20 looping GIF previews of multi-frame clips. Preview looping does not change one-shot runtime clips.
- `sources/`: seven original selected generated masters.
- `PROMPTS.md`, `generation.json`: generation prompts and provenance.

In Godot, assign a `.tres` from `orbital_ops/` to an AnimatedSprite2D's Sprite Frames property, select a named animation, and use **Nearest** texture filtering. Keep each `.tres` beside its PNG. The pack has no nested Godot project, gameplay scenes, or gameplay scripts.

This is a first art pass. The level layout, enemy AI, collisions, damage, zero-gravity physics, boss behavior, and menu wiring are the next implementation step. Shared Hoppy, hearts, pickups, Commit Tokens, and MERGE exit already exist in the Bay Area pack and should be reused.
