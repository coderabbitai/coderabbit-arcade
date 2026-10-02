# Code City Brawl — assets only

Original 16-bit-style artwork for Hoppy's Adventure Arcade, October 2, 2026.

Open `preview.html` for the searchable pose/animation gallery. `district-preview.png`, `security-preview.png`, and `hq-preview.png` show the artwork staged in Godot. See `ASSET_GUIDE.md` for coverage, the proposed boss moveset, source requirements, and integration limits.

- `code_city/`: 19 transparent atlases and matching Godot SpriteFrames resources, three 1280×720 panoramas, and `manifest.json`.
- `frames/`: all 200 individually registered frames.
- `individual/`: a PNG for each of 217 named states/cycles.
- `animations/`: short GIF cycle previews. These loop for inspection; runtime death/break clips do not.
- `sources/`: 16 selected generated masters, preserved at original resolution and alpha.
- `PROMPTS.md`, `generation.json`: built-in image generation prompts and source provenance.

Assign a `.tres` to an AnimatedSprite2D, select a named state, and use Nearest texture filtering. Keep each resource beside its PNG. There is no nested Godot project.

This is an initial pose library and environment kit, not implemented gameplay or a finished full-animation set. Most attack, hazard, item and ally entries are single key poses. Walking/drifting, boss idle and break/defeat sequences have short cycles. Level layouts, collision, AI, Hoppy's expanded brawler animation set, combat timing, audio and route activation belong to subsequent work.

Rebuild: `python tools/build_code_city_asset_pack.py` from repository root using Pillow and NumPy. Validate: Godot 4.7.1 `--headless --path hoppys-adventure-arcade --log-file /tmp/code-city-assets.log --script res://tests/code_city_assets.gd`. Omit `--headless` to regenerate the three staging images.
