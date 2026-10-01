# The Enchanted Repo — assets only

Original fantasy pixel art for Hoppy’s Adventure Arcade, October 1, 2026.

Open `preview.html` for the animated gallery and `enchanted-repo-preview.png` for the Godot staging render. See `ASSET_GUIDE.md` for the proposed boss moveset and integration notes.

- `enchanted_repo/`: transparent runtime atlases, ready-to-assign Godot SpriteFrames resources, two background layers, and manifest.
- `frames/`: individual animation frames; `individual/`: first frame of each named state.
- `animations/`: looping GIF previews; runtime one-shot states remain nonlooping.
- `sources/`: selected generated masters, preserved at their original resolution.
- `PROMPTS.md`, `generation.json`: exact generation prompts and provenance.

Assign a `.tres` to an AnimatedSprite2D's Sprite Frames property and select a named animation. Use Nearest filtering and the documented pivot offset. Keep each resource beside its PNG. No nested Godot project is included.

This pack provides artwork and proposed attack sequences. Level layout, collision, AI, damage, armor rules, audio selection, and route activation belong to the next gameplay pass. Reuse the existing Hoppy, pickups, HUD, Commit Tokens, and MERGE exit.
