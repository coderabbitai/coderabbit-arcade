# Reference hero validation

Validated locally on 2026-11-14 with Godot 4.7.stable.official.5b4e0cb0f.

## Automated checks

All nine hero/integration suites passed in the final run: `heroes_reference_assets`, `heroes_villains_assets`, `heroes_villains_motion`, `heroes_villains_logic`, `heroes_villains_smoke`, `hoppy_armed_assets`, `beatemup_story`, `beatemup_knockout`, and `how_to_play`.

The additional Enchanted Repo transparency change passed `enchanted_assets`, `enchanted_boundaries`, and `enchanted_repo_smoke`. Collision geometry is unchanged; only the solid Polygon2D backing of raised one-way platforms was removed.

Reproduction command for the hero checks:

```sh
uv run --python 3.12 --no-project python tools/tests/run_tests.py --godot /Applications/Godot.app/Contents/MacOS/Godot -k heroes_reference_assets -k heroes_villains -k hoppy_armed_assets -k beatemup_story -k beatemup_knockout -k how_to_play -j 2
```

## Visual evidence

The numbered sheets cover 120 gameplay cels across combat, three movement directions, and five weapons. Before/after comparisons use baseline `27e2762`, at native and 2x size. Movement and armed combo GIFs are supplied at native and 4x size. The rear movement frames show white outer ears; a pixel regression check covers all eight frames.

Rendered Heroes motion and smoke suites also passed. Captures in `../heroes-villains/` show the movement cycles, mirrored combat poses, weapon contact phases, story cards, stages, victory and ending. Runtime motion checks cover both facings, weapon switching, carrying, jumping, defeat and face clearance.

`../enchanted-repo/transparent-platforms.png` shows the actual rendered platform silhouettes against the forest. The windowed Enchanted end-to-end test failed after its pause checks, consistent with the level's automatic focus-loss pause; it is not counted as a passing rendered run. Its complete headless smoke suite passed, including traversal and collision checks. The saved spawn capture directly verifies the visual transparency change.

## Rebuild and scope

Re-running the sprite, story and presentation builders produced identical SHA-256 hashes for all 26 runtime outputs: seven atlases, seven SpriteFrames resources, five carry textures, the manifest, two story images and four presentation scenes. The final assets still matched these hashes after producing the additional native-size previews.

Gameplay clocks, clip names/counts/durations, attack contact phases, reach, damage and collisions retain their original definitions. Changed runtime code is confined to Heroes art/weapon registration and the separately requested Enchanted platform backing. Other game mode resources were not changed.
