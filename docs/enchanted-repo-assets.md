# The Enchanted Repo — asset pass

Created October 1, 2026 after reviewing the live GDD, technical baseline, Agent Context, and existing Platformer asset packs.

Pack: `hoppys-adventure-arcade/Assets/enchanted-repo-assets-only/`. Start with `README.md`, `ASSET_GUIDE.md`, the offline animated `preview.html`, or `enchanted-repo-preview.png` rendered in Godot.

Delivered: 104 frames, 78 named states, six SpriteFrames resources, two parallax plates, individual PNGs, looping GIF previews, eight selected source masters, exact prompts, provenance, and a reproducible mechanical packer. Coverage includes forest/castle terrain and scenery, Nitpick Gnome, Bloat Troll, Spaghetti Code Vine, unstable branches, comment traps, attack effects, and the Legacy Monolith with armored/partly stripped/bare-core art.

The Monolith's slam, sweep, stomp, recovery, armor-break and defeat sequences support a proposed moveset documented in the pack guide. Attack timings, armor counts, and collision behavior are proposals for the gameplay pass. Single-pose states are not full animation cycles. The terrain kit is modular sprite art, not an autotile TileSet. Backgrounds are finite plates, not seamless loops.

Generation used the built-in image tool. Packing preserves alpha and finds transparent gutters around irregular source poses, then normalizes frames and pivots. Some fine pose registration and generated edge speckling remain suitable for later in-level polish. No stock art was downloaded. Shared Hoppy, pickups, HUD and MERGE exit are reused from existing assets.

Validation: Godot 4.7.1 loaded all frames, named states, six animation resources and both backgrounds; the harness checks frame counts, FPS, loop flags, nonempty textures, atlas bounds, dimensions, and complete inventory. A rendered staging preview was visually reviewed. Run `--headless --path hoppys-adventure-arcade --log-file /tmp/enchanted-assets.log --script res://tests/enchanted_assets.gd`; omit `--headless` to regenerate the preview. The editor import reports an existing nested SynthCitiesGodot project warning and cannot save global editor settings in the sandbox; project resources import successfully. No gameplay or export test is claimed.

Rebuild with `tools/build_enchanted_asset_pack.py` using Pillow and NumPy. This session does not activate Enchanted Repo in Level Select or change playable levels.
