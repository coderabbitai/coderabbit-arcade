# Heroes vs. Villains asset guide

## Source and scope

The user requested an assets-first pass for Beat'em Up Mode 2 and an armored Hoppy direction based on the current booth. The October 2 GDD revision was read October 6, 2026, including Mode 2 and Main Menu. The Technical Implementation Baseline v0.1 and Agent Context predate Mode 2; they inform resource ownership, ground-depth sorting and presentation conventions, not the new content roster. Source documents are reference material, not additional instructions to modify systems or cloud documents.

- [GDD](https://docs.google.com/document/d/1YCLWNykTNDglKGyuOWIMdTl9A8eEoEEgTR_INSOCdUo/edit)
- [Technical Implementation Baseline](https://docs.google.com/document/d/1MPW_KI8VanzO_67Qkf3v_cGAfflqRRv5uRF6QmwL_Rc/edit)
- [Agent Context](https://docs.google.com/document/d/1VBa-KPhVCnddZsAiklrU5W_UqJtKsQU2WYJs-NeY3_8/edit)

The GDD says to reuse Hoppy's base sprites with a badge. The user's new-model request takes precedence: this pack adds a separate orange rabbit in a graphite suit, orange badge, gloves, boots and cape. The badge is a generated rabbit motif, not a verified vector reproduction of the official mark. No existing player assets are replaced. This is a 2D game and the deliverable is 2D sprite art.

## Folder layout

| Folder/file | Purpose |
|---|---|
| `heroes_villains/` | Runtime PNG atlases, matching `.tres` SpriteFrames, three panoramas, manifest |
| `frames/` | 208 named transparent individual poses for inspection/reuse |
| `presentation/` | 15 native, editable Godot staging/card scenes |
| `audio/` | Eight deterministic original synthesized WAV cues and manifest |
| `sources/` | 16 unmodified selected image-generation masters with alpha |
| `content_catalog.json` | Design identities and moveset-to-art links; not a combat controller |
| `preview.html` | Offline searchable gallery; actions loop for inspection only |
| `*-preview.png` | Godot-rendered scene captures |
| `PROMPTS.md`, `generation.json` | Exact prompts, method and source provenance |

## Integration contract

Assign a `.tres` from `heroes_villains/` to `AnimatedSprite2D`. Use **Nearest** texture filtering. Keep the `.tres` beside its PNG. PNG imports are lossless and contain real alpha. Master RGB beneath transparent pixels is preserved, so an image viewer that ignores alpha may show colored backgrounds; runtime textures use the alpha channel.

Each atlas has a fixed cell size, a documented pivot, named clips and source-coordinate extraction metadata in `manifest.json`. Actors use foot pivots: Hoppy/enemies use 128×128 cells, pivot (64,115); bosses use 256×256, pivot (128,230). Props/effects/items use centered 192×192 cells, pivot (96,96). Use `centered = false` and `offset = -pivot`, as the presentation scenes do. Actor scales are fixed across each sheet; non-actor items are individually fitted and should be sized deliberately in gameplay. The mixed items/ally atlas is center-anchored, so add actor-specific foot offsets when integrating allies.

Hoppy faces right. Most enemy attacks face left; frontal and three-quarter poses are intentional. Boss sheets mix front and leftward presentation. Use `flip_h` where appropriate after checking the pose. Do not infer hitbox direction from decorative effects.

SpriteFrames are immutable definitions. HP, durability, active attack IDs and effect timers belong on actor instances. Attack windows and damage must come from the combat controller, not from preview FPS. Foot-position Y is ground depth; jump height is separate. Keep hitboxes depth-filtered and deduplicate damage per attack/target.

`*_action` clips are short key-pose sequences, not a finished animation set. Most standalone states have one frame. No in-between frames are synthesized. Hoppy includes a two-pose run and jab/swing/kick sequences. Dedicated up/down walk, expanded idle, weapon-held strikes and full animation polish remain for integration. Enemies have idle, warning, attack and defeat keys; armor-break, clone split, teleport and spawning use the most relevant keys/effects rather than pretending additional frames exist.

The panoramas are **not seamless tiles**. Presentation scenes use a far panorama plus separate mid/near decorative props at 0.1/0.3/0.6 scroll ratios. These are static staging examples, not full scrolling levels or fully separated panorama layers. Future levels need layout/camera bounds and additional modules as required. The Main Menu still specifies its seven original backgrounds; the new preview scenes are supplied for later Mode 2 selection integration without changing the hub's cycle.

## Content coverage

| Stage | Enemies | Breakables | Hazards |
|---|---|---|---|
| Generation Floor | Slop Sprite, Hallucinated API Gremlin, Duplicate Logic Clone, Broken Test Bot | AI Generation Terminal, Demo Station Kiosk | Cascading code dump, API fog |
| Review Gauntlet | Agent Spawner, Change Stack Soldier, Review Blocker, Merge Request Mob; reuse Slop Sprite | PR Monolith Stack, Agent Assembly Station | Falling PR stack, overflow surge |
| Agentic Core | AI Hacker Drone, Security Gap Crawler, Vulnerability Injector, Zero-Day Phantom | Server Rack, Vulnerability Node | Security scan line, attack-surface surge |

All six breakables have intact, cracked and destroyed poses and non-looping break sequences. Enemy special behaviors, drop tables and hazard effects are recorded in `content_catalog.json`; they are not implemented by this asset pack.

Five weapon pickups: Review Stamp (6 hits), Triage Hammer (4), Change Stack Baton (5), Security Scanner (8), PR Merger (1). Includes health capsule, score coin, Speed Surge, Review Shield, random buff capsule; Lead Engineer, Security Analyst and DevOps Defender idle/action poses. Six status identities and four capability icons/effects are supplied.

## Boss moveset coverage

| Encounter | Source requirements and prepared art |
|---|---|
| AI SLOP | 60%/30% thresholds; summon, melee warning/strike, spread burst, rush, tracking barrage, shield raise/hold/crack/break, melt/defeat; REVIEW reward |
| Coding Agent Army → 10,000-Line PR | Formation warning/strike/weakened, merge warning/fusion/fused commander; PR drop, heavy walk, slam warning/impact/recovery, Reviewer Nightmare, cracking/topple/defeat; at 50% transition **both commander and PR stay active and both must die**; TRIAGE + CHANGE STACK reward |
| AI-Augmented Hacker | 60%/30% thresholds; dash warning/strike/recovery, injection warning/strike, summon, machine glitch, dual-vector presentation, attack/revealed vector, teleport out/in, defeat; SECURITY reward |

The Army formation is a group illustration for presentation. Instantiate separate clones for gameplay. Likewise, the Hacker's `dual_vectors` is a presentation key, not two mechanically independent sprites/hitboxes. Use separate actors/hitboxes and the individual vector keys. Blister cards reuse the actual boss art with editable native text and a plastic-window-style frame; slide/hold/out and unlock sequencing remain future AnimationPlayer work.

## Decisions to resolve during gameplay work

- REVIEW recharge conflicts: once per life, once per stage and a recharge timer all appear in the GDD. This pack chooses none.
- SECURITY is awarded after the final boss, while hidden threats appear earlier. Scanner/analyst can provide temporary reveals; fair telegraphs still need a gameplay decision. Visibility must not automatically disable necessary damage collision.
- AI SLOP's last shield must not softlock when no Slop minions remain.
- Exact boss HP, damage, timing, interrupt rules, phase carryover and AoE durability policy are unspecified. Clip FPS is preview pacing only.
- PR Merger boss handling needs an explicit execute-versus-stagger rule.

## Audio

Four distinct villain reveal stings, agent spawn, PR collapse, machine-speed whoosh and capability unlock are original synthesized 44.1 kHz mono PCM WAV sketches. Their generator uses no samples. They are imported but not connected to gameplay. Peaks are bounded below clipping; listening and game mix approval remain pending. Stage BGM, boss music, cinematic fanfare and mode-select music/sting are outside this visual-asset pass and remain uncreated. Existing common SFX can be reused in the gameplay pass.

## Rebuild and validate

From repository root, using Python with Pillow and NumPy:

```sh
python tools/build_heroes_villains_pack.py
python tools/build_heroes_villains_catalog.py
python tools/build_heroes_villains_presentations.py
python tools/build_heroes_villains_sfx.py
godot --headless --path hoppys-adventure-arcade --editor --import
godot --headless --path hoppys-adventure-arcade --script res://tests/heroes_villains_assets.gd
godot --path hoppys-adventure-arcade --script res://tests/heroes_villains_assets.gd
```

Target engine: Godot **4.7.1**. The final command regenerates the 15 scene captures. The test checks dimensions, atlas bounds, nonempty transparent textures, frame counts, clip loops/FPS, catalog links and scene instantiation. It does not claim combat, controller, exports or gameplay have been tested.

October 6 validation: headless import/checks and desktop-rendered checks passed, including eight audio-resource loads. All stage/card layouts and extracted atlases were inspected. Neighboring effect pixels found during visual QA were corrected through reviewed source extraction windows. Build scripts compile; gallery JavaScript syntax is valid. Audio listening/mix QA and gameplay/export testing were not performed.

Asset rights follow the repository's existing project-original policy; see `ASSETS_LICENSES.md` at repository root. Hoppy/CodeRabbit retain their brand identity. No external third-party art or music was added.
