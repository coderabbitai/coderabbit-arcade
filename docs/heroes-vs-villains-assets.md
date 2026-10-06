# Heroes vs. Villains — assets-only pass

October 6, 2026. Pack: `hoppys-adventure-arcade/Assets/heroes-vs-villains-assets-only/`.

Read the pack's `README.md`, `ASSET_GUIDE.md` and `content_catalog.json`; open `preview.html` for inspection. `presentation/` contains three stage staging scenes, four editable villain blister cards, four capability cards, three opening panels and a victory panel.

Includes armored 2D Hoppy, all 12 Mode 2 enemy identities, four villains across three encounters, 208 poses / 247 clips / 22 SpriteFrames, three panoramas, six breakables, hazards, five weapons, pickups, allies and capability/status art. Eight original synthesized cue sketches accompany the visual pack. Sixteen generated masters and exact prompts are retained.

The updated GDD's Mode 2/Main Menu sections govern content. The baseline/context predate Mode 2; repository conventions and the user's Assets-folder request determine the destination. Hoppy's separate armored variant follows the user's request over the GDD's shared-base-sprite suggestion. The source Mode 2 text is saved in `heroes-vs-villains-source.txt` for traceability.

This is not a playable mode. Existing Code City gameplay and hub routing are unchanged. Full animation in-betweens, combat/AI, stage assembly/collisions, capability persistence, menu wiring, presentation sequencing and music remain future work. The catalog records design conflicts rather than silently resolving REVIEW recharge, hidden-enemy reveal timing or AI SLOP's zero-minion shield edge case.

Validation: Godot 4.7.1 headless import and asset checks passed; desktop-rendered checks passed and produced all 15 scene captures. The three stage scenes, all card layouts and all extracted atlases were visually inspected; reviewed source windows correct neighboring-particle extraction issues. Audio resources load; listening/mix QA remains pending. Python build scripts compile, gallery JavaScript syntax checks pass, and `git diff --check` passes. No gameplay or export validation is claimed.
