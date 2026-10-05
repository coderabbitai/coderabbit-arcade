# Code City Brawl — assets-only pass

**October 5 update:** [Playable v1](code-city-brawl.md) now uses this pack, adds Hoppy combat animations, and connects the mode menu, combat, progression and audio. The notes below describe the original October 2 asset delivery.

October 2, 2026. Based on the updated GDD's Beat'em Up Mode 1 and Main Menu sections, the linked engineering references and current repository conventions.

Pack: `hoppys-adventure-arcade/Assets/code-city-brawl-assets-only/`. Start with its `README.md`, `ASSET_GUIDE.md` and `preview.html`.

Includes 200 frames, 217 named states/cycles, 19 SpriteFrames resources and three panoramas. Covers all nine enemy identities, three Grand Merge Conflict phases, stage scenery and destructibles, hazards/projectiles, six weapons, six status icons, health/score pickups, three allies and Force Merge button/effects. Built-in image generation; exact prompts and selected source masters are included.

This is artwork preparation, not playable Code City Brawl. Hoppy's brawler animations, complete in-between animation, collisions, level assembly, combat/AI, audio and menu activation remain future work. Boss attack sequences/timings are proposals. Existing gameplay and hub routing are untouched; Mode 2 is outside this pack.

Rebuild with `tools/build_code_city_asset_pack.py` (Pillow/NumPy). Validate/import in Godot 4.7.1; `tests/code_city_assets.gd` checks resources, and its non-headless run writes the three stage preview PNGs. See pack guide for exact commands and technical limits.

Validation completed in Godot 4.7.1: headless import exited 0; headless and rendered resource checks both passed (200 frames, 217 states, 19 resources, three panoramas). All three rendered stage images were visually inspected. Import reported the pre-existing nested SynthCities project warning and a sandbox-restricted editor-preference save; neither prevented texture import or resource validation. No gameplay or desktop-export validation is claimed for this assets-only pass.
