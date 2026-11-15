# Reference-matched 2D hero

These are the active Heroes vs. Villains player assets: 16 combat cels, 24 directional movement cels and 16 cels for each of five weapons. The artist's CodeRabbit Handover renders supplied the anatomy and costume reference. `sources/combat.png` is the canonical 2D interpretation used to generate the remaining masters.

The white torso and thighs, dark gloves and joints, orange armor panels, black belt with orange buckle, orange cape and two tall ears are drawn into the masters. Walking away shows the white backs of the ears, without orange inner surfaces. This is authored artwork, not a palette conversion of the old Hoppy sheets.

## Rebuild

From the repository root:

```sh
uv run --no-project --with pillow --with numpy python hoppys-adventure-arcade/tools/build_coderabbit_hero_2d.py
uv run --no-project --with pillow python hoppys-adventure-arcade/tools/build_coderabbit_hero_story.py
uv run --no-project --with pillow --with numpy python tools/build_heroes_villains_presentations.py
uv run --no-project --with pillow python tools/preview_coderabbit_hero.py --baseline 27e2762
```

The sprite builder extracts, scales with nearest sampling, registers and packs immutable image-tool masters. It never paints costume details. `sources/layout.json` records body axes, hand and weapon-tip targets. The eight rear movement cels come from `locomotion-back-ears.png`; other directions retain the original master. `sources/provenance.json` retains exact generation and correction prompts. Source files are excluded from Godot's asset import.

`manifest.json` is generated hero-specific calibration. Runtime reads its hand/tip anchors and frame-specific carry gloves. Carry textures retain the existing item artwork, resized to match the new baked weapons. Base cells remain 128x128 with pivot (64,115); armed cells remain 256x160 with pivot (96,147). Clip names, durations, rates and attack clocks are unchanged. Never copy calibration from the legacy armed sheets onto these poses.

The selected story masters and prompts also appear in `Assets/beatemup-story/refinements.json`, so the general story builder reproduces the corrected opening and ending. The mode-select tile shares the opening illustration. Stage previews and victory use the active hero resource; tutorials already share the player sheets. Capability cards contain symbols, not rabbit artwork.

## Review and checks

`docs/previews/hero-reference/` contains numbered contact sheets, before/after comparisons at native and 2x scale, and movement/combo GIFs at native and 4x scale. Rendered gameplay captures are in `docs/previews/heroes-villains/`.

`tests/heroes_reference_assets.gd` checks the actual runtime hero sheets, all 120 cels, clip compatibility, transparency, clipping, painted anchors, resource routing and rear-ear orientation. The existing motion suite covers mirroring, carry grips, face clearance, weapon switching, attack phases and movement registration. Logic, smoke, story, knockout and tutorial suites cover integration.

The hero remains subject to the project's existing CodeRabbit trademark and asset terms. No third-party artwork was introduced.
