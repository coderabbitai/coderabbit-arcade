# The Enchanted Repo — asset guide

## Design grounding

Reviewed October 1, 2026: the live GDD (internal), Technical Implementation Baseline (internal), and Agent Context (internal), together with the repository's newer implementation notes and Orbital Ops pack. Source prose was read; embedded document artwork was not audited.

The GDD specifies enchanted forest/castle code-magic, Nitpick Gnomes, Bloat Trolls, Spaghetti Code Vines, crumbling branch platforms, enchanted comment traps, and a slow stone Legacy Monolith whose technical-debt armor must be stripped away. The menu calls for rune trees, floating code-scroll banners, a distant spire, and sky/treeline/foreground flora layers. Exact attacks, armor counts, and timings below are creative proposals, not additional GDD requirements.

## Coverage

| Resource | Contents |
|---|---|
| `legacy_monolith` | 24 frames: armored idle, overhead slam, low sweep, stomp, armor hit/crack/break, exposed core, core hurt, collapse and final rubble |
| `monolith_armor` | 16 poses: partly stripped and bare-core variants, each with idle, three attack warnings, three impacts, and exposed recovery |
| `nitpick_gnome` | 16 frames: idle, walk, quill-jab warning/strike/recovery, hurt, defeat |
| `bloat_troll` | 16 frames: idle, lumbering walk, club warning/strike/recovery, hurt, defeat |
| `hazards` | 16 states/effects: branch intact/warning/break/fall; comment dormant/warning/burst/spent; vine idle/warning/whip/cut; ground warning, slam burst, shockwave, armor fragment |
| `forest_kit` | 16 pieces: ground slab, two ledge caps, root platform, castle wall/pillar/arch, arena slab, rune tree, spire, scroll banner, root bridge, flora, foreground trunk, rune lantern, rubble |
| Backgrounds | Separate 960×540 twilight sky and transparent treeline plates |

104 frames total. Single-pose states are deliberately named states, not claims of full animation cycles. Shared player, collectible, UI and exit resources remain in the existing packs. No new audio is included.

## Legacy Monolith — proposed moveset

Slow, committed attacks should create readable opportunities to strip the armor. The artwork supports two armor breaks: full armor → partly stripped → bare core. Armor progress should persist through the encounter. The number of hits per layer and core HP remain tuning decisions.

| Move | Sequence | Suggested first implementation |
|---|---|---|
| Debt Slam | `slam_warning` → `slam` → `slam_recover` | 1.0 s overhead warning, 0.15 s impact, 1.0 s stuck-fist recovery; local ground strike with a clearly marked range. |
| Dependency Sweep | `sweep_warning` → `sweep` → `sweep_recover` | 0.85 s drawn-back fist, 0.25 s low sweep, 0.9 s recovery. A jumpable close-range horizontal attack. |
| Regression Stomp | `stomp_warning` → `stomp` → `stomp_recover` | 0.95 s raised foot, 0.15 s stomp, 1.0 s recovery. Optionally release one slow, jumpable ground shockwave; use the separate effect sprite. |
| Refactor opening | `armor_hit` → `armor_crack` → `armor_break` → next armor tier | Let successful melee hits during recovery chip armor. Make the breaking layer visibly burst, cancel any pending attack, and switch to the next tier. |
| Core/end | tier `exposed` → `core_hurt` → `defeat` | Bare-core recovery is a damage opportunity. Defeat is nonlooping and ends in inert rubble; controller cancels hazards and unlocks the shared MERGE exit. |

For partial/bare stages, use `cracked_`/`bare_` state names from `monolith_armor`. Use the tier's `exposed` pose during attack recovery so lost armor does not reappear. Use a brief runtime tint for tier-preserving hurt feedback; the base `armor_hit` is fully armored and `core_hurt` is bare. The base `defeat` is bare-core art. The partly stripped tier keeps one dominant shell; the bare tier loses that shell and exposes the chest, but retains some small wrist bindings.

Animation playback does not apply damage, move the boss, or manage armor. Controllers should own explicit warning/active/recovery timers; preview FPS is presentation only. Keep the GDD's ordinary damage at 1 HP and make attacks feel devastating through reach, animation, and knockback rather than silently changing damage. No difficulty escalation or invulnerability rule is assumed.

## Enemy and hazard proposals

Gnome: small patrol enemy with a short quill jab; show `jab_warning` before the strike. Troll: slow patrol enemy with a longer club tell and recovery. Retain ordinary enemies' GDD 1–2-hit defeat envelope when tuning. Appearance and attacks are original interpretations.

Vine: fixed rooted hazard, warning coil before a leftward whip; mirror for rightward attacks. The root position varies across poses, so align it deliberately when building the hazard. `vine_cut` supports a destructible interpretation without requiring it. Comment trap: dormant parchment, amber warning, violet burst, then spent state. Damage only during the active interval. Branch: intact → warning → break → falling pieces. Collision removal and any respawn timer belong to the controller; the falling debris is visual. Telegraph lengths must leave a feasible escape route.

## Godot integration

All atlases use regular row-major grids with four columns and no spacing. `manifest.json` records frame rectangles, source slice rectangles, source scale, visible bounds, pivots, clip FPS, and loop flags. Bounds are left/top/right/bottom, not width/height, and are visual guidance rather than collision boxes.

| Atlas | Cell | Pivot |
|---|---:|---:|
| Legacy Monolith | 192×192 | (96,173) |
| Monolith armor variants | 256×256 | (128,230) |
| Nitpick Gnome | 96×96 | (48,86) |
| Bloat Troll | 144×144 | (72,130) |
| Hazards / forest kit | 128×128 | (64,64) |

For centered AnimatedSprite2D, set `offset = cell_size / 2 - pivot`. Actor sheets face left. Preserve actor scale across states; the two Monolith sheets use similar neutral standing heights (141 and 134 visible pixels) and different cell sizes to contain wide sweeps. Fixed cell foot anchors reduce drift but are not anatomical root tracking. Fine animation registration remains polish work.

Terrain pieces are padded modular sprites, not a seamless autotile set. Crop to visible art as appropriate, align walkable top edges, and author separate collision. Root bridges and thin platforms can support one-way collision later. Walls, arches, banners, flora, and lamps are decorative until gameplay explicitly assigns behavior. No TileSet terrain connectivity or collision is claimed.

Use sky far, treeline mid, and kit flora/trunk near. Relative parallax speeds 0.1/0.3/0.6 are baseline proposals. Plates are finite, not seamless: clamp or mask edges, or extend coverage in the level pass. Keep background values subdued behind hazards. The staging image demonstrates scale and layering; it is not a playable layout.

## Provenance and rebuild

Created with the built-in image generation tool, with exact prompts in `PROMPTS.md`. The supplementary armor sheet references the generated boss master. Generated alpha is preserved. No external stock art was downloaded and no third-party stock license is asserted. Existing source images are authoritative; generation paths are provenance fallbacks.

Rebuild using `tools/build_enchanted_asset_pack.py` with Pillow and NumPy. The script finds transparent gutters (including curved gutters around overlapping grid extents), slices without crossing solid silhouettes, scales with nearest-neighbor sampling, packs, and emits resources/previews; it does not paint new artwork. Preview GIFs and the HTML gallery loop one-shot clips for inspection without changing runtime loop flags.

Validation: run Godot 4.7.1 with `--headless --path hoppys-adventure-arcade --log-file /tmp/enchanted-assets.log --script res://tests/enchanted_assets.gd`. Omit `--headless` to regenerate the staging image. Resource validation does not establish gameplay balance, collision correctness, or export compatibility.
