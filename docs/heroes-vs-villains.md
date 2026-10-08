# Heroes vs. Villains — playable v1

Open `hoppys-adventure-arcade/project.godot` in Godot 4.7.1 and run **Beat’em Up → Play Heroes vs. Villains**. The direct scene is `res://scenes/beatem_up/reinvent/heroes_vs_villains.tscn`.

This mode uses the armored Hoppy and the [Mode 2 asset pack](heroes-vs-villains-assets.md). It has three stages, nine gated encounters, twelve enemy identities and four villains. Code City Brawl remains separately playable.

![Generation Floor](previews/heroes-villains/stage_1_room_1.png)

## Controls and run flow

| Action | Keyboard | Controller |
|---|---|---|
| Move along the ground plane | WASD / arrows | Left stick / D-pad |
| Jump | Space | A |
| Three-hit combo / weapon | J or X | X |
| Pick up weapon | E | Y |
| Charge REVIEW after unlock | Hold Q | Hold LB |
| Pause | Escape | Start |
| Advance presentation card | Enter / keypad Enter | View / Select |

The armored Hoppy uses eight-frame side, away and toward-camera locomotion cycles at 14 fps, with cadence scaled to analog movement and speed effects. Base travel speed is 264 pixels/second (10% above Code City Brawl).

Hoppy has three health points, jump avoidance, hit recovery and one shield on stage entry after REVIEW is unlocked. Attack presses can buffer the next combo strike. Clear ordinary rooms, then walk through the right gate. Boss encounters end with a short Hoppy victory hop, followed by the reward cards. Claiming the last reward opens Capability Deployed immediately; no walk to the exit is required. The final boss instead leads to the final victory cards and results. Break props for supplies; consumables collect on contact, while weapons require pickup input. Defeat retries the current stage with its entry score and capabilities, fresh health and cleared temporary effects. Pause and focus loss stop the run; return-to-menu is available through pause and results.

Capabilities persist within the run, not across application launches. REVIEW unlocks after AI SLOP; TRIAGE and CHANGE STACK unlock after defeating both the fused army commander and the PR; SECURITY completes the final victory. Cards slide in and remain until Enter or controller View / Select is pressed. Opening, boss, unlock and victory cards never advance on a timer; pause preserves the pending card. Combat, pickup and jump inputs cannot dismiss cards. Stage and result confirmations also use the dedicated advance action.

## Stages and bosses

| Stage | Enemy roster | Environment and encounter |
|---|---|---|
| The Generation Floor | Slop Sprite, Hallucinated API Gremlin, Duplicate Logic Clone, Broken Test Bot | Code dumps and fog; terminals and kiosks. AI SLOP progresses through minions/melee, rushing barrages and LGTM shielding. |
| The Review Gauntlet | Agent Spawner, Change Stack Soldier, Review Blocker, Merge Request Mob | Falling stacks and overflow; PR monoliths and assembly lines. Three army clones fuse at half combined health, bringing in the independently damageable 10,000-Line PR. Both must fall. |
| The Agentic Core | AI Hacker Drone, Security Gap Crawler, Vulnerability Injector, Zero-Day Phantom | Scan lines and damage-triggered surges; security racks and nodes. The Hacker escalates through three phases, ending with a separate hidden attack vector. |

Clones split once. Test bots lose armor and periodically damage themselves. Soldiers block frontal attacks except finishers; blockers resist knockback. Spawner-owned mobs disappear with their source. Hidden enemies remain faintly visible and expose their attack warnings; scanning reveals them fully. Wounded phantoms can dodge by teleporting. Three timed ally types provide healing, spawner removal or scanning support.

Boss phase transitions clamp damage at their thresholds so heavy weapons cannot skip required phases. AI SLOP's final shield only activates while its minions remain; clearing the last one breaks it, and entering the phase with none cannot lock the encounter. The Hacker's second vector has independent movement and collision geometry while sharing its health pool.

![Dual villain encounter](previews/heroes-villains/fight_ten_thousand_line_pr_phase_1.png)

## Capabilities and equipment

REVIEW requires a 0.45-second hold, grants a short invulnerability window and staggers nearby threats, then recharges for eight seconds. TRIAGE marks the highest-priority threat and adds one damage against it. CHANGE STACK finishers leave two-second damage zones. SECURITY is the concluding unlock and victory presentation.

| Weapon | Uses | Behavior |
|---|---:|---|
| Review Stamp | 6 | Wide stagger strike |
| Triage Hammer | 4 | Heavy single-target hit and temporary mark |
| Change Stack Baton | 5 | Long reach; destroys agent spawners immediately |
| Security Scanner | 8 | Reveals hidden enemies and the Hacker vector for ten seconds, including on a missed swing |
| PR Merger | 1 | Executes enemies below 25% health; staggers bosses on contact |

Health capsules, review shields, speed surges, score coins and randomized beneficial pickups supplement the weapons. Confusion and strength reduction come from enemy attacks; overload hazards apply an overwhelmed status. Durability, status timers, capabilities and boss health are displayed in the HUD.

The v1 resolves the source catalog's timing ambiguities with an eight-second REVIEW cooldown and ten-second scanner reveal. Health, wave sizes and timing live in mode-local scripts for subsequent playtest tuning.

## Audio

All requested tracks are wired from `Assets/Audio/Beat'em Up/Hero vs Villian/`:

| Encounter | File |
|---|---|
| The Generation Floor | `Hero Immortal.mp3` |
| AI SLOP | `8-bit_slay_the_evil.ogg` |
| The Review Gauntlet | `frivolous_hero.ogg` |
| Coding Agent Army / 10,000-Line PR | `Heavy Concept A Bass Master.wav` |
| The Agentic Core | `synth_type_mix2.ogg` |
| AI-Augmented Hacker | `Zodik - Lord of Zorg I.ogg` |

Each music stream is duplicated before enabling looping, including the WAV track. Music uses the Music bus; pooled impact/jump/pickup effects from Juhani Junkala's collection and the pack's eight original cues use SFX. Imported shared streams are never modified. Track provenance is recorded in `ASSETS_LICENSES.md`.

## Runtime and validation

The isolated runtime is in `modes/beatem_up/reinvent/`: `game.gd` manages rooms, hazards, props, cards, capabilities and cleanup; `player.gd`, `enemy.gd` and `boss.gd` manage actors; `catalog.gd` owns tuning/audio; `art.gd` caches read-only frames; `weapon_rig.gd` follows the attack clock. The mode uses ground-plane combat geometry with separate jump height and Y sorting. Normal spawns cap at twelve enemies, with two reserve slots for clone splitting; projectiles cap at 32, warnings at twelve, pickups at 24 and CHANGE STACK zones at six.

```sh
godot --headless --path hoppys-adventure-arcade --import
godot --headless --path hoppys-adventure-arcade --script res://tests/heroes_villains_assets.gd
godot --headless --path hoppys-adventure-arcade --script res://tests/heroes_villains_logic.gd
godot --headless --path hoppys-adventure-arcade --script res://tests/heroes_villains_motion.gd
godot --headless --path hoppys-adventure-arcade --script res://tests/heroes_villains_smoke.gd
```

The logic suite covers combat depth/deduplication, combo buffering, enemy defenses and special behaviors, all weapons, capability effects, hazards, pause, all boss transitions, independent PR defeat, shield edge cases, retry cleanup and all six music mappings. The smoke suite injects keyboard/controller events, traverses all nine encounters, checks bounded entity pools and capability retention, reaches one victory and returns to an unpaused menu. Run the smoke suite without `--headless` to capture rendered previews.

Godot 4.7.1 asset, logic and full-traversal checks passed, including a rendered traversal at 1280×720. Code City logic, motion and full-traversal regressions and menu-return layout checks also passed. The traversal bot uses invulnerability and accelerated navigation: it verifies reachability, not human difficulty balance. Physical controller feel, listening/mix QA, packaged exports and performance on target booth hardware remain playtest work. Locomotion uses the generated movement supplement; combat retains the original key poses. The motion suite verifies directional cycles, speed/cadence, transitions and manual-only advancement for every card.
