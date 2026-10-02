# Code City Brawl — asset and moveset guide

## Source authority

Read October 2, 2026: live [GDD](https://docs.google.com/document/d/1YCLWNykTNDglKGyuOWIMdTl9A8eEoEEgTR_INSOCdUo/edit), [Technical Implementation Baseline](https://docs.google.com/document/d/1MPW_KI8VanzO_67Qkf3v_cGAfflqRRv5uRF6QmwL_Rc/edit), and [Agent Context](https://docs.google.com/document/d/1VBa-KPhVCnddZsAiklrU5W_UqJtKsQU2WYJs-NeY3_8/edit), plus the repository's newer implementation notes. Source text was reviewed; embedded document illustrations were not visually audited.

The current GDD separates Code City Brawl (Mode 1) from Heroes vs. Villains (Mode 2). This pack is exclusively Mode 1. The three-stage sequence, enemy identities, weapons, effects, allies and boss phase thresholds below come from the GDD. Visual character designs, individual attack poses and suggested timings are creative proposals for review during gameplay implementation.

## Inventory

200 unique frames, 217 named states/cycles, 19 SpriteFrames resources and three finite 1280×720 panoramas. All paths below are relative to `code_city/`.

| Stage | Enemy resources | Stage kit |
|---|---|---|
| CLI/IDE District — cyan/green | `cli_gremlin`, `syntax_error_sprite`, `linter_enforcer` | `district_kit`: pavement, tower, floating IDE cluster, lamp; Terminal Kiosk and IDE Window intact/damaged/break/rubble; injection bomb, warning, blast, encounter gate |
| Security Sector — red/black | `cve_crawler`, `injection_attack_drone`, `dependency_bot` | `security_kit`: floor, corridor arch, beacon, barrier; Server Rack and Security Crate intact/damaged/break/rubble; scan laser dormant/warning/active and breach shockwave |
| Git Repository HQ — gold/purple | `merge_conflict_soldier`, `force_push_bandit`, `stale_branch_zombie` | `hq_kit`: floor, column, commit tree, foreground arch; Commit Pillar and Branch Scaffolding intact/damaged/break/rubble; rebase projectile and Detached HEAD dormant/warning/active |

Each enemy has eight source poses. Regular enemies include idle, short movement cycles, attack tells/strikes and defeat; special allocations supply Linter armor break/bare states, Crawler dodge, Soldier duplication and Zombie resurrection. Nine enemies × eight = 72 frames, plus eight supplemental bare-Linter poses. Three stage kits × sixteen = 48 frames.

| Other resource | Coverage |
|---|---|
| `conflict_spawner` | Eight boss poses: idle pair, summon warning/release, hammerfist warning/slam, sweep, exposed recovery |
| `split_screen` | Eight boss poses: split transition/idle, cyan left warning/strike, red right warning/strike, dual impact/recovery |
| `merge_chaos` | Eight boss poses: enraged idle, storm warning/release, clone summon, hurt, collapse, rubble, resolved core |
| `weapons` | Six weapon identities, broken variants, shield crack, extended whip, sweep arc and hammer impact — sixteen frames |
| `items_allies` | Six buff/debuff icons, health coffee, score token, CR Bot idle/gift, Linting Fairy hover/gift, Senior Dev idle/walk/gift, blank Force Merge button — sixteen frames |
| `combat_fx` | Syntax/injection projectiles, duplicate spawn, resurrection, slam marker/impact, left/right shockwaves, split seam, two conflict projectiles, clone portal, chaos warning, glitch burst, merge radiance and press effect — sixteen frames |

`manifest.json` is the exact machine-readable frame/state inventory. Individual files have semantic names; raw numbered frames retain source order.

## Grand Merge Conflict — proposed moveset

GDD requirements: summon Merge Conflict Soldiers in Phase 1; vulnerability to combo finishers between spawn waves; split-screen attacks from both sides at 50% HP; projectile storms, clones and glitches at 25%; Force Merge finisher after defeat. Numerical timings, wave caps, vulnerability windows and hit counts remain proposals, not accepted balance.

| Phase / move | Asset sequence | First-pass gameplay proposal |
|---|---|---|
| 1 — Conflict Summon | `conflict_spawner`: `summon_warning` → `summon` → `recover`; FX `duplicate_spawn` | 1.0 s raised-arm tell; spawn at bounded marked positions; 1.2 s exposed window after a wave. Limit living summons before tuning difficulty. |
| 1 — Conflict Slam | `slam_warning` → `slam` → `recover`; FX `slam_warning`, `slam_impact` | 0.9 s overhead tell, 0.15 s impact, 1.0 s recovery. Oval ground marker defines the threatened depth lane. |
| 1 — Branch Sweep | `idle` → `sweep` → `recover`; separate amber ground tell | Use a 0.8 s ground telegraph while holding idle; the sheet has a strike pose, not a dedicated sweep windup. A slow local sweep offers a jump or depth dodge. |
| 2 — Split Screen | `split_screen`: `transition` → `idle`; FX `split_seam` | Trigger once at ≤50% HP. The illustration supports two halves; the actual screen split still needs a shader/view composition. |
| 2 — Opposing Strikes | `left_warning` → `left_strike`; `right_warning` → `right_strike`; then `recover` | Both sides telegraph for 0.8 s. Keep a visible safe depth lane; never require dodging into another unavoidable hitbox. Cyan/right-red direction cues also have distinct shapes. |
| 2 — Dual Impact | `dual_impact` → `recover`; two slam markers | Telegraph both regions first, 0.15 s impact and 1.1 s recovery. The combined pose is presentation; two independently positioned threats need independent hitboxes. |
| 3 — Rebase Barrage | `merge_chaos`: `storm_warning` → `storm` → `idle`; cyan/red projectiles | Trigger phase once at ≤25% HP. 0.7 s charge, then a short bounded burst with readable lane gaps. Keep gameplay positions stable during screen distortion. |
| 3 — Clone Surge | `clone_summon` → `idle`; `clone_portal`, `chaos_warning` | Hold the summon pose through a 0.9 s portal warning before enabling clones; cap active clones. Use recovery after a short attack cycle. |
| Defeat / Force Merge | `hurt` → `collapse` → `rubble`, then `resolved_core`; button and merge FX | Disable pending attacks/projectiles before the finisher. Hoppy's button slam/camera sequence is future animation work. Add the exact word MERGE with the shared font in Godot; the new button's top is intentionally blank. |

The `defeat` clip previews collapse→rubble→core. Gameplay should hold rubble until the Force Merge action and reveal the core only when resolved. Do not let automatic animation playback decide the finisher state. The phase sheets share matched neutral heights; the resolved core deliberately retains cyan/red inside a gold casing, with green resolution radiance provided separately.

## Enemy and pickup contracts

Preserve GDD HP: Gremlin 1; Syntax Sprite 2; Linter 3 (first hit breaks armor); Crawler 2; Drone 2; Dependency Bot 1; Soldier 3; Bandit 2; Zombie 2 with one resurrection. Gates must count living duplicates and pending resurrections. These art resources do not enforce HP or spawns.

The Linter has armored movement/attack poses and a separate `linter_bare` resource with eight unarmored idle/walk/warning/strike/recovery/hurt/defeat poses. Switch resources after `armor_break`; do not restore armored art. Its standing height is registered to the original bare pose. The Zombie has first-fall/resurrection/final-defeat states; use a runtime tint on its current pose for hurt. The Crawler's pounce and Dependency Bot's plug lash interpret their GDD melee behavior; exact AI is not prescribed by the sheet. Ally entries are key poses, not complete entrance/exit cycles.

| Weapon | GDD durability / role |
|---|---|
| Debug Stick | 5 hits; enhanced short-range melee |
| Linter Staff | 8 hits; front-arc AoE |
| API Key Whip | 6 hits; extended reach |
| Git Branch | 4 hits; heavy knockback |
| Firewall Shield | Blocks 3 hits; defense |
| Refactor Hammer | 3 hits; slow, heavy single-target strike |

Weapon PNGs are pickup/equipped-object art, not complete hand-synchronized swing animations. Configure grip points and weapon attachment transforms against the final Hoppy poses during gameplay. Durability belongs to each equipped instance, never to the shared SpriteFrames.

Buffs: Speed Boost, Attack Up, one-hit Damage Shield. Debuffs: Slow, Confused (inverted controls), Strength Down. Coffee restores 1 HP, clamped to Hoppy's 3 HP maximum. CR Bot supplies Damage Shield, Fairy Speed Boost, Senior Dev health. The coin is a score marker for Commit Pillar drops; exact value, durations, stacking, loot weights and cooldowns remain tuning decisions.

## Level and menu assembly

The GDD hub uses previews 4/5/6 for these stages. The panoramas and separate kit sprites support those previews without running combat scenes. Suggested layer mapping follows the technical baseline:

| Stage | Far (0.1) | Mid (0.3) | Near (0.6) |
|---|---|---|---|
| CLI/IDE | `district_background.png` | `ide_cluster`, optional `tower_facade` | `street_slab`, `street_lamp` |
| Security | `security_background.png` | `alert_beacon`, `corridor_arch` | `barrier`, `floor_slab` |
| Git HQ | `hq_background.png` | `hall_column`, optional `commit_tree` | `foreground_arch`, `floor_slab` |

The backgrounds are complete finite panoramas, not three pre-separated full-screen plates. Add kit sprites as independently scrolling layers. No seamless repeat, autotile connectivity, TileSet collision, assembled level or active menu replacement is claimed. For long levels, connect bounded rooms or extend the art during the layout pass; avoid repeating the central HQ tree as if it were a seamless tile. Slabs are decorative modular pieces, not platformer ledges; the brawler needs a broad ground-depth area.

Opening cinematic can initially reuse the city panorama, IDE panels, warning icon and existing Hoppy artwork. Final Force Merge can reuse the HQ panorama and new button/merge effects. Cinematic direction and Hoppy's new poses remain implementation work. Shared Hoppy, hearts, font and common SFX stay in their existing project locations. No new music or SFX is included in this visual pack.

## Godot coordinates and validation

Enemy cells: 128×128, foot pivot (64,115). Boss cells: 256×256, foot pivot (128,230). Stage kit cells: 192×192, center pivot (96,96). Weapon/item/FX cells: 128×128, center pivot (64,64). Four atlas columns, no padding between cells. All sprites have internal transparent margins. For centered AnimatedSprite2D, use `offset = cell_size / 2 - pivot`. Enemies face left; the boss contains frontal and directional half poses, so do not globally mirror its color-coded phase states.

Use `y_sort_enabled` on the ground actor parent, keep a ground anchor, and offset only the visual body for jumps. Melee needs a ground-depth tolerance as well as horizontal reach. Visual bounds are not collision shapes. Crop prop texture regions to the manifest's `visible_bounds` (left/top/right/bottom) for placement if desired; preserve consistent scale for intact/broken sequences. Weapon/ally grips and anatomical root alignment require further polish; fixed foot registration is not root-motion tracking.

Resource validation checks frame counts, state names, loop/FPS data, texture bounds, nonempty pixels and alpha in Godot 4.7.1. Rendered staging images inspect composition and approximate scale, not combat balance, collision or export compatibility. Single-pose entries must not be represented as full animations. The current game/menu routes remain unchanged.

## Provenance and rebuild

Generated with the built-in image generation tool; exact selected prompts are in `PROMPTS.md`. No third-party stock art was downloaded and no external stock license is asserted. Sixteen selected master PNGs are authoritative; provenance paths outside the project are fallbacks only. The initial crowded boss sheets were discarded in favor of three spacious phase masters.

`tools/build_code_city_asset_pack.py` uses Pillow/NumPy for mechanical extraction, scaling, registration and atlas/resource output. Curved low-alpha gutters and a small explicit table of reviewed source bounds avoid neighboring poses; generated alpha inside each selected cutout is preserved. Sources are never painted over. These generated pixel-art assets include semi-transparent glow and are a visual first pass, not palette-indexed hand animation. The gallery template is `tools/code_city_gallery.html`.
