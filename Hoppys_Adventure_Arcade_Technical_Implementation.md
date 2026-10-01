# Hoppy’s Adventure Arcade — Technical Implementation Baseline

Version: 0.1 • Prepared: 2026-09-16 • Target: Godot 4.7.1, GDScript

Status: source-grounded implementation proposal. This document defines a starting architecture, not a claim that these systems already exist or that the team has approved every proposed choice.

## 1. Authority and use

The [Game Design Document](https://docs.google.com/document/d/1YCLWNykTNDglKGyuOWIMdTl9A8eEoEEgTR_INSOCdUo/edit) is the authority for game design. This baseline was derived from the connector-readable Overview, Assets Links, Platformer Game, Endless Runner, Beat’em Up, and Main Menu sections; the retrieved source reports modification at 2026-09-16 20:59:36 UTC. Text was reviewed; embedded art and native document layout were not visually audited.

The repository named in the GDD is [coderabbitai/coderabbit-arcade](https://github.com/coderabbitai/coderabbit-arcade). Its contents were not inspected for this document. All paths, class names, schemas, milestones, and implementation interfaces below are proposals until reconciled with that repository.

Labels used throughout:

- **Design requirement:** explicitly specified by the GDD or the user.
- **Proposed baseline:** engineering recommendation suitable for the first implementation; not an additional design commitment.
- **Open decision:** ambiguous, optional, or unspecified behavior that must not silently become an approved requirement.

Use this file as the durable technical reference. Use the companion `Hoppys_Adventure_Arcade_Agent_Context.md` as compact injected context, then load the relevant sections here before implementing a system. Neither file becomes automatic cross-chat memory merely by being created. Add both to the project’s documentation and explicitly attach or reference them in future implementation tasks.

When design changes, update the GDD first, record the affected baseline sections, and revise the compact context. When implementation differs from this proposal, record the decision and evidence here. User direction takes precedence; unresolved conflicts between documents and repository behavior must be surfaced.

## 2. Product scope

**Design requirements:** a single retro arcade application for desktop PC, macOS, and Linux; Hoppy as the shared protagonist; keyboard and gamepad; three independently accessible modes; fast return to the central hub. Godot **4.7.1** is the pinned project version. GDScript is the implementation language.

| Mode | Required experience | State and progression |
|---|---|---|
| Hub | Reactive seven-background showcase, Hoppy animation, three mode buttons, settings, quit | Idle/focus preview cycle; no gameplay run state |
| Platformer | Three selectable 2D levels, platforming, melee or stomp, enemies, hazards, bosses, pickups | 3 HP; death retries selected level or returns to its menu |
| Runner | Infinite 3D corridor with a fixed camera, lane changes, jump, roll, procedural hazards, pursuit recovery | 2-hit health; recovery after 15–20 clean seconds; local top-10 leaderboard |
| Beat’em up | Three sequential belt-scrolling 2D stages, combos, weapons, destructibles, status effects, allies, final boss | 3 HP; death retries current stage or returns to its menu |

The GDD’s power-up suites are explicitly discussion stubs. Preserve their identities and proposed effects in content data, but do not describe their balance as final. Shader dissolve, CRT, menu reactions, adaptive music, aerial combos, and continue tokens have optional/polish status. Online leaderboards, multiplayer, accounts, and backend services are not baseline scope.

## 3. Project architecture and ownership

**Proposed baseline:** one Godot project, independently owned mode scenes, and a small application service layer. Share assets and domain logic where useful; retain separate movement controllers for platforming, belt scrolling, and 3D running.

```text
res://
  project.godot
  app/                    # AppRouter, SaveService, AudioService
  scenes/main_menu/       # main_menu.tscn and local showcase controller
  scenes/platformer/      # platformer_menu.tscn, level select, levels
  scenes/runner/          # runner_menu.tscn, run scene, chunk scenes
  scenes/beatem_up/       # beatem_menu.tscn, stages, cinematics
  shared/                 # UI, damage interfaces, definition resources
  modes/platformer/       # controller, enemies, hazards, level logic
  modes/runner/           # lane controller, pursuit, spawner, score
  modes/beatem_up/        # combat, waves, weapons, statuses, boss
  data/                   # definitions, balance profiles, content catalogs
  assets/                 # shared art, fonts, audio, models, licenses
  tests/                  # behavioral tests and focused test scenes
  docs/                   # baseline, agent context, decision history
```

Autoloads are limited initially to `AppRouter`, `SaveService`, and `AudioService`. Add a settings service only if its responsibilities outgrow save/settings storage. Mode-local controllers own HP, score, timers, HUD, status effects, and active entities. Background previews belong to the hub scene, rather than an Autoload holding references to destroyed menu nodes.

This intentionally revises the GDD’s illustrative global `HitManager`, `HUDManager`, `ScoreManager`, `StatusEffectManager`, and `BackgroundManager` suggestions. It preserves behavior while preventing a runner’s 2-HP policy or pursuit timer from surviving entry into a 3-HP mode.

| Owner | Responsibilities | Lifetime |
|---|---|---|
| AppRouter | Validated destinations, transition overlay, input lock, fresh run creation | Application |
| AudioService | Shared buses, music handoff, UI sounds | Application |
| SaveService | Validated settings and local score reads/writes | Application |
| Mode session | Current level/stage, HP, score, seed, run result | One run or defined stage sequence |
| Actor components | Health, attacks, effects, animation state | Actor instance |
| HUD | Observes the active session; displays state | Mode scene |
| ShowcaseController | Preview selection, timers, crossfades, Hoppy reactions | Hub scene |

Use explicit typed references and signals. Avoid a universal event bus for ordinary parent-child communication. Physics movement and authoritative damage run on physics ticks; visual transitions may run per frame. Animation requests follow authoritative gameplay state, rather than independently deciding death or score.

## 4. Lifecycle and interfaces

Proposed scene route identifiers: `hub`, `platformer_menu`, `platformer_level_select`, `runner_menu`, `beatem_menu`, plus validated content IDs for actual runs. Preserve the GDD’s menu scene paths where practical. All navigation passes through the router, which may internally use `SceneTree.change_scene_to_file()`.

Transition sequence: validate destination → prevent duplicate activation → fade out → dispose old session/scene → load destination → initialize context → restore input/focus → fade in. A failed load clears the lock and returns to a usable menu with an error message. Kill obsolete tweens and disconnect external signal subscriptions when their owner exits.

Proposed contracts, expressed as data shapes rather than tested engine code:

| Contract | Fields / behavior |
|---|---|
| RunContext | `mode_id`, `content_id`, `seed`, `balance_revision`, `entry_reason` |
| RunResult | `run_id`, `mode_id`, `content_id`, `score`, `duration_seconds`, `outcome`, `seed` |
| DamageEvent | `source_id`, `target_id`, `attack_id`, `amount`, `knockback`, `damage_kind` |
| DamageResult | Accepted, blocked, or ignored; actual HP loss; whether fatal |
| Mode session | Start once, pause/resume, emit result once, dispose safely |
| UI signals | `health_changed`, `score_changed`, `pursuit_changed`, `run_finished` |

Runtime state never mutates shared definition Resources. Keep durability, timers, health, and consumed-item state on per-instance objects. Shared `.tres` data defines maximums, durations, effects, scenes, and tuning.

On retry, create a fresh session. On hub/menu exit, destroy the old session. Runner retries reset pursuit, score, elapsed time, generator state, and effects. Platformer retries reset the selected level. Brawler stage retry restores a deliberate checkpoint policy; the carry-over/reset details remain an open decision in §15.

**Proposed pause policy:** stop gameplay, recovery timers, effect durations, and scoring together; keep pause/menu navigation active. Pause on application focus loss for desktop play. Resume must not execute a stored attack or immediately trigger a menu confirmation.

## 5. Input, display, and audio

Define semantic Input Map actions: `move_left`, `move_right`, `move_up`, `move_down`, `jump`, `attack`, `roll`, `interact`, `pause`; use UI navigation/accept/cancel actions for menus. Resolve actions within the active mode. A runner W/up mapping must not cause both a jump and a menu action on the same press.

| Context | Keyboard baseline | Gamepad baseline |
|---|---|---|
| Menus | Arrows/WASD, accept/cancel | D-pad or left stick, accept/cancel face buttons |
| Platformer | A/D or arrows, jump, attack | Horizontal stick/D-pad, two action buttons |
| Runner | A/D or arrows; W/Space/Up jump; S/Ctrl/Down roll | Left/right stick or D-pad; A/Cross jump; B/Circle roll |
| Brawler | WASD/arrows; jump, attack, dedicated pickup | 8-way stick/D-pad; jump, attack, pickup face buttons |

Platformer/brawler action keys and brawler button assignments need final mapping. The brawler’s dedicated pickup action is an explicit exception to the overview’s two-button ideal. Normalize brawler diagonal ground movement. Runner lane commands are discrete presses, with stick threshold/hysteresis so holding the stick does not involuntarily skip every lane.

**Display proposal:** use a 1280×720 reference layout for menus with responsive anchors and safe UI margins. Backgrounds fill the window, expanding or cropping decorative edges without clipping controls. Pixel-art textures use nearest filtering where appropriate. A 320×180 game-art viewport is a separate retro presentation option; strict integer scaling and borderless fill at arbitrary aspect ratios cannot both be guaranteed. Decide the retro-mode crop/letterbox policy before declaring it complete. A `CanvasLayer` controls draw layering; viewport/stretch configuration controls resolution. See Godot’s multiple-resolution guidance.

Use `CharacterBody2D`, `CharacterBody3D`, `TileMapLayer`, and a fixed-camera runner scene as described by the GDD. Prefer `Parallax2D` for new 2D backgrounds; its scrolling/repeat controls support the required preview motion. This is a proposed modernization of the GDD’s `ParallaxBackground`/`ParallaxLayer` examples, not a visual design change. See Parallax2D reference.

**Audio proposal:** Music, SFX, and optional UI buses each feed Master. Music must not feed through SFX; this clarifies the GDD’s ambiguous bus-chain notation. Global music uses `AudioStreamPlayer`; spatial game sounds use 2D/3D players. Save bus volumes, use bounded sound concurrency, and prevent overlapping menu tracks after repeated navigation. Source: Godot audio buses.

Pin editor and export templates to 4.7.1; the [official maintenance release](https://godotengine.org/article/maintenance-release-godot-4-7-1/) provides version context. Stable documentation URLs can change over time: validate APIs in the installed 4.7.1 editor before implementation. Renderer selection remains open until the runner’s effects and target machines are profiled; do not promise GPU glow or particle behavior across renderers without testing.

## 6. Main menu implementation

Design requirements include logo, foreground Hoppy, dark readability overlay, three mode buttons, Settings, Quit, controller focus styling, a menu music loop, and hover/confirm sounds. Settings begins with volume/display/control information; CRT is optional.

| Preview ID | Theme | Focus group |
|---|---|---|
| 0 | Bay Area Blitz: skyline, fog, street | Platformer |
| 1 | Orbital Ops: starfield, station, struts | Platformer |
| 2 | Enchanted Repo: sky, trees, flora | Platformer |
| 3 | Codebase Corridor: tunnel, code rain, walls | Runner |
| 4 | CLI/IDE District: buildings, IDE panels, street | Brawler |
| 5 | Security Sector: corridor, alerts, barriers | Brawler |
| 6 | Git Repository HQ: branch tree, columns, pillars | Brawler |

Maintain separate `idle_index`, active preview, focus group, idle remaining time, and transition generation. Never reuse one index for both idle and focused cycling.

- Idle order is 0→1→2→3→4→5→6→0, with an 8–10-second dwell and 1.2-second crossfade. Proposed initial dwell: 9 seconds.
- Platformer focus cycles 0/1/2 every 3 seconds with 0.6-second fades. Brawler focus cycles 4/5/6 identically. Runner focus holds 3 with a 0.8-second fade.
- On leaving mode focus, wait 2 seconds, then resume the preserved idle sequence. Proposal: preserve the remaining idle dwell as well as its index. Settings/modal pause behavior is proposed, not specified by the GDD.
- Parallax layer speeds follow 0.1/0.3/0.6 relative factors; absolute speed is tuneable.
- Pointer hover and keyboard/gamepad focus use the same selection function. Proposed arbitration: most recent intentional input source wins; an old keyboard focus must not override a fresh pointer hover.
- Rapid selection cancels obsolete transitions. Use a generation token so stale callbacks cannot hide the newest preview. Initially coalesce requests to the latest pending selection during a fade; never allocate an unbounded series of backgrounds.
- Optional Hoppy reactions: jump for platformer, running loop for runner, short attack for brawler, shrug for quit. Ending a reaction returns to idle unless the selected reaction loops.

Proposal: keep seven lightweight background definitions and at most two live preview instances during a transition. Only visible previews process. Do not instantiate live levels or seven continuously rendering viewports to make a menu preview. Use two viewports only if isolated rendering/retro scaling actually needs them.

Alpha crossfade is the first implementation. Noise dissolve and CRT are later polish. Decorative overlays ignore mouse input. Modals capture focus and restore it to their invoking button. Quit uses a confirmation dialog or direct deliberate activation followed by the GDD’s 1-second fade; navigation fades may use approximately 0.5 seconds.

Acceptance: all routes work and return; all seven previews appear; controller and mouse behavior agree; rapid focus changes leave one settled preview; focus exit resumes the idle sequence; opening settings does not trigger a mode; repeated navigation does not accumulate music, timers, or preview nodes.

## 7. Shared combat and content data

Use named collision layers with a documented matrix, initially World, PlayerBody, EnemyBody, PlayerHitbox, EnemyHitbox, PlayerHurtbox, EnemyHurtbox, Pickup, and Trigger. Physics bodies collide with intended solid geometry. Hitboxes monitor opposing hurtboxes, and pickups monitor the player collector. Define 2D and 3D masks separately.

Each attack activation gets an `attack_id` and a target-hit set. An overlapping hitbox damages a target at most once per attack unless a definition explicitly permits repeated ticks. Dead actors reject damage. Disable active hitboxes on hurt/death/cancel. Resolve invulnerability and shields before HP loss; emit score/death exactly once.

Proposed data types:

| Definition | Important fields |
|---|---|
| ModeDefinition | Stable ID, menu scene, default content, preview group |
| Level/StageDefinition | ID, scene, music, bounds, encounters, exit |
| AttackDefinition | Damage, active window, recovery, knockback, hit limits |
| EnemyDefinition | HP, scene, AI tuning, attacks, score reward |
| ItemDefinition | Effect ID, pickup scene, duration/charges, mode applicability |
| WeaponDefinition | Damage/attack profile, max durability, reach |
| StatusEffectDefinition | Duration, modifiers, stacking policy, icon |
| RunnerChunkDefinition | Scene, length, lane occupancy, entry/exit constraints, weight |
| BalanceProfile | Movement, timing, scoring, difficulty curves, revision |

Do not force similarly named pickups to share behavior across modes. Platformer Approve Shield and runner Approve Shield may share art and a definition family while using different pursuit/health rules.

## 8. Platformer

Asset update, October 1, 2026: Enchanted Repo artwork is imported in `Assets/enchanted-repo-assets-only/`. See `docs/enchanted-repo-assets.md` for the 104-frame pack and its guide for proposed Monolith moves. This is an asset-only delivery; Enchanted Repo gameplay and route activation remain pending.

Implementation update, October 1, 2026: Bay Area Blitz and Orbital Ops are playable. Shared lifecycle resides in `modes/platformer/level.gd`; each level owns its layout and actors. Orbital has bounded assisted zero-gravity controls, phased CI lasers/vacuum vents, ranged rogue AI, diving drones and a 10-HP Deprecated API. The user selected `tipa16.mp3` for traversal and `Valor of Heroes.mp3` for boss combat. See `docs/orbital-ops.md` for actual v1 timings and validation; the source design requirements and unaccepted proposals below retain their original status.

**Design requirements:** 3 HP, one damage per player attack and ordinary enemy/hazard contact, common enemies defeated in 1–2 hits, post-hit invulnerability, coyote time, jump buffering, level score, heart HUD, MERGE-button exit, and death/retry UI. Boss HP is separately tuned.

Implement `CharacterBody2D` horizontal movement and vertical gravity. Keep grounded/coyote/jump-buffer timers explicit. One buffered jump is consumed once. State set: Idle, Run, Jump, Attack, Hurt, Dead; animation selection can distinguish jump rise/fall. A `Camera2D` follows with level bounds. Place solid terrain in `TileMapLayer`; separate visual decoration from collision.

| Level | Required content |
|---|---|
| Bay Area Blitz | Cable-car platforms, fog/city theme; glitch critters and Request Changes Reviewers; deployment/merge-conflict hazards; Merge Conflict Monster with branch heads |
| Orbital Ops | Space station, zero-gravity jump sections; rogue AI and Security Vulnerability Drones; CI lasers and vacuum vents; Deprecated API boss |
| Enchanted Repo | Forest/castle; Nitpick Gnomes, Bloat Trolls, Spaghetti Code Vines; crumbling branches and comment traps; armored Legacy Monolith |

Use local gravity-zone data for zero-gravity sections. Randomized conflict platforms must retain a reachable route. Implement patrol/chase with simple local sensing first; add navigation only when the level geometry requires it. Commit Tokens are collectible score items; exact values, attack selection (swipe/stomp), boss patterns, level completion destination, and numerical movement timings remain open.

Draft pickups: Approve Shield absorbs one hit; LGTM Boost grants temporary speed/invulnerability; Auto-Fix defeats nearby enemies; Coffee restores 1 HP; Full Review Pack restores max HP. Clamp healing to 3. Auto-Fix radius, boss eligibility, durations, and stacking need explicit tuning.

Acceptance: buffered/coyote jumps occur once; sustained contact cannot bypass i-frames; healing clamps; death disables movement/attack; retry clears items and enemy state; camera remains within bounds; each level can reach its MERGE exit and completion result.

## 9. Runner

**Design requirements:** 3D Hoppy with rigged Run/Jump/Roll/Hurt/Dead animations; automatic forward progress; X-axis lane shifting; one jump per airtime; roll reduces collider height for a duration and cooldown; chunk generation with weighted variety and increasing difficulty; fixed camera behind/above Hoppy with lateral tracking.

**Motion proposal:** hold the player near the longitudinal origin and move corridor chunks/hazards backward at one authoritative run speed. Track distance separately. This provides the GDD’s visual forward motion without unbounded coordinates. Do not also move Hoppy forward by that same speed: the GDD mentions both mechanisms and implementing both naively doubles closing speed. Lateral/vertical movement remains on `CharacterBody3D`; collision sweeps must account for moving hazards at maximum speed. Start with three lanes as an explicit proposal; lane count is not specified by the GDD.

On roll exit, check standing clearance. Proposed behavior is to remain crouched until safe rather than expand the collider into an overhead obstacle. Lane shifts have a tunable duration and reject out-of-range destinations. Fixed seed plus a balance revision supports reproducing chunk selections, not a promise of cross-platform deterministic physics.

### Pursuit state machine

| Current state | Accepted event | Next state / result |
|---|---|---|
| Safe, 2 HP | Unblocked damage | Pursued, 1 HP; show pursuer, start clean timer |
| Pursued, 1 HP | Unblocked damage before recovery | Caught, 0 HP; one game-over result |
| Pursued, 1 HP | Recovery deadline reached | Safe, 2 HP; retreat pursuer, remove warning |
| Safe after recovery | New unblocked damage | New pursuit cycle |
| Any living state | Invulnerable overlap | No health/pursuit damage transition |

Recovery window is 15–20 seconds in the GDD; proposed initial tuning is 18 seconds of unpaused gameplay. First-hit i-frames and per-attack deduplication are proposed safeguards against one obstacle consuming both hits. At a deadline shared with a damage tick, use an explicit deterministic order; proposal: resolve queued damage before recovery. The visual pursuer approaches a capped warning position and never kills the player purely because time elapsed—the source grants recovery after clean survival.

Runner power-ups remain draft content:

| Item | GDD effect | Implementation issue |
|---|---|---|
| Approve Shield | One damage block; negates first hit or resets active pursuit | Decide whether reset happens on pickup or blocked hit |
| Auto-Fix Blast | Clears onscreen hazards | Specify pits/structural terrain and offscreen boundary behavior |
| LGTM Invincibility | Invulnerability for 5 seconds | Decide refresh/stack policy |
| Nitro Commit | Speed boost and 2× score for 8 seconds | Preserve feasible reaction windows at boosted speed |
| Super Jump Token | One enhanced jump | Consume only when a jump actually begins |
| Code Review Bonus | Multiplier until next damage | Magnitude and stacking remain TBD |

### Generator and score

Chunks declare longitudinal length, connectors, hazards, lane occupancy, and feasible entry/exit movement states. Selection uses weighted candidates filtered by reachable routes and current speed. Validate across chunk seams, not only within each chunk. Ensure enough lookahead for reaction plus maneuver time. Speed and hazard density rise along bounded curves; they do not increase without a feasible maximum.

Hazard catalog: PR Backlog Wall (jump/roll variant), Bug Swarm (jump/lane dodge), Merge Conflict Barrier (jump plus lane dodge), Deprecated Code Pitfall (jump), timed Security Scan Laser Grid (jump/roll), Comment Flood (lane dodge), Failing Build Shockwave (jump). Each variant needs visible telegraphing and a feasible escape path.

Use bounded spawning/despawning first. Add pooling after profiling; reset collision, timers, effects, and collected flags on reuse. Keep spawning RNG separate from cosmetic randomness. Record seed and selected chunk sequence on generator failures.

Score derives from unpaused survival time at a configurable base rate, active multipliers, and explicit bonuses; do not use frame count. Keep fractional accumulation internally and display an integer. Score rates, multiplier composition, caps, and tie-break policy are open. Proposed tie-break is score descending, then duration descending, then stable insertion order.

Store local top 10 at `user://leaderboard.cfg`; optional name entry, final score, duration, retry, and mode-menu return appear on game over. No networking.

Acceptance: first/second hit and clean recovery match the table; paused time grants no recovery/score; generator remains bounded and traversable at speed cap; roll cannot clip ceilings; boosted speed cannot tunnel through hazards; a completed run saves once; retry clears all pursuit and generator state.

## 10. Beat’em up

Use `CharacterBody2D` for 8-direction movement on the ground plane. **Proposed jump model:** store separate jump height/vertical velocity and offset the visual body above its ground position. Keep the ground shadow/sort position stable; determine airborne hit eligibility explicitly. Do not reuse platformer screen-Y gravity, because screen Y is also the brawler’s depth axis.

Use foot-position sorting and a tunable depth tolerance for melee: characters far apart along the belt must not hit merely because their sprites overlap. Combat state owns attack windows; AnimationPlayer/AnimationTree presents those states. Combo sequence is jab → overhead swing → spinning kick/knockback. Inputs inside the chain window queue the next hit; expiry resets to hit 1. Hurt/death interrupts attacks. Exact window durations and aerial combos remain open.

Stages progress CLI/IDE District → Security Sector → Git Repository HQ. Camera gates register enemies for each encounter and reopen after all required combatants are permanently defeated. Spawned duplicates and pending zombie resurrection count toward the gate; despawning must not silently masquerade as a kill.

| Enemy | GDD HP | Distinct behavior |
|---|---:|---|
| CLI Gremlin | 1 | Melee rush |
| Syntax Error Sprite | 2 | Ranged error projectiles |
| Linter Enforcer | 3 | Armored; first hit breaks armor; slow/heavy attack |
| CVE Crawler | 2 | Flank and dodge roll |
| Injection Attack Drone | 2 | Projectile bursts |
| Dependency Bot | 1 | Swarms of 3–5 |
| Merge Conflict Soldier | 3 | Duplicate on first hit |
| Force Push Bandit | 2 | Charge and strong knockback |
| Stale Branch Zombie | 2 | Resurrect once |

Armor’s relation to listed HP is ambiguous; decide whether its first hit also removes HP. Prevent duplicates from recursively duplicating without a configured cap. Track zombie resurrection count per instance and distinguish temporary defeat from final death.

Stage 1 has Terminal Kiosks (health/weapons), IDE Windows (buffs), and falling injection bombs. Stage 2 has Server Racks (high-tier weapons), Security Crates (buff/debuff), scan lasers, and breach shockwaves. Stage 3 has Commit Pillars (score/buff), Branch Scaffolding (weapons), rebase projectile storms, and control-inverting Detached HEAD traps.

Weapons replace standard attacks: Debug Stick 5 hits, Linter Staff 8, API Key Whip 6, Git Branch 4, Refactor Hammer 3, Firewall Shield 3 blocked hits. Effects are respectively stronger melee, frontal AoE, reach, knockback, slow heavy damage, and defense. Runtime durability is separate from the shared Resource. Whether AoE consumes durability per target or per successful swing is open; propose one charge per successful swing to preserve usable AoE lifetime. Breaking returns to unarmed attacks.

Effects: Speed Boost, Attack Up, one-use Damage Shield, Slow, Confused (inverted controls), Strength Down. Use an actor-local effect controller. Proposed same-effect refresh instead of unlimited stacking; compute modifiers from base values rather than permanently modifying stats. Damage values and durations remain tuneable. Healing restores 1 HP, clamped to 3.

Allies: CR Bot drops a shield, Linting Fairy drops speed, Senior Dev heals 1 HP. Weighted event scheduling must cap concurrent allies and clean up on stage exit.

Opening cinematic precedes stage 1; proposal: skippable illustrated panels, with skip and completion invoking the same once-only start transition. Brawler menu cycles stage panoramas. Game over retries the current stage. One continue token is a stretch feature.

### Grand Merge Conflict

- Phase 1: soldier waves and slow strong attacks; vulnerability between waves to combo finishers.
- At 50% HP: conflicting screen halves and attacks from both sides.
- At 25% HP: projectile storms, clones, glitch effects.
- At defeat: Force Merge cinematic and completion.

Use descending HP-ratio threshold checks, each transition once. A large hit crossing both thresholds reaches the correct lowest phase without replaying lower-priority intros. Proposal: render the split as a presentation effect over one authoritative world; do not simulate duplicate players or damage sources. Boss HP, attack schedules, clone caps, and vulnerability details require tuning.

Acceptance: depth filtering works; one swing cannot repeat-hit accidentally; combo timeout/cancel works; weapons break at the defined policy; status expiry restores base behavior; gates wait for duplicates/resurrection; boss phase changes and finisher happen once; death at any stage offers that stage’s retry.

## 11. Persistence and settings

Proposed files: `user://settings.cfg` and GDD-required `user://leaderboard.cfg`, each with a schema version. Store only user data under `user://`; do not write into packaged resources. Validate type/range on load and recover to defaults when missing or malformed.

Settings schema: master/music/SFX volume in [0,1], window mode, optional CRT flag, input overrides when rebinding is implemented. Leaderboard entry: run ID, validated display name, nonnegative finite score, duration, mode, optional seed, and score-rule revision. Proposed name limit: 16 characters; trim whitespace/control characters, use “Hoppy” for blank, render names as plain text. Name policy is a proposal, not a GDD constraint.

Write through a temporary file and replace the destination on successful completion; retain or restore a backup on failure. Display a nonblocking save error while leaving retry/menu available. Deduplicate result submission by run ID. Resetting leaderboard data requires a deliberate user-facing action. Persistence does not imply mid-run save/resume or cross-device sync.

## 12. Asset pipeline and performance

The GDD’s asset directories are candidate sources, not verified licenses. Record each actual asset’s creator, source, license, attribution, modifications, and redistribution terms before shipping it. Keep required license text with the assets. Do not assume a marketplace collection, Mixamo-derived model, font, or music search result has uniform licensing.

2D assets use agreed frame sizes/origins and named animations; platformer Hoppy supplies idle/run/jump/attack/hurt/death, brawler adds directional movement, combo, stagger, pickup. Runner needs a separate rigged 3D Hoppy, consistent scale/orientation, collision proxy, and tested animation retargeting. Prefer a documented glTF import workflow; verify root motion is not added on top of scripted movement. Share fonts, UI hearts, appropriate SFX, and source artwork without forcing incompatible animation controllers together.

Use looping OGG music and short WAV/OGG effects as appropriate. Track distinct hub music, platformer level tracks, runner synthwave, brawler stage/boss/cinematic music. AI-music comments in the GDD are not a finalized asset decision. Add-ons such as state-machine or dialogue packages are candidates, not prerequisites; choose dependencies only after testing their 4.7.1 compatibility.

Proposed performance target is a stable 60 fps on agreed minimum machines; those machines and memory/load budgets remain undefined. Measure hub transitions, worst-case brawler waves/boss, and a long high-speed runner session. Track frame time, active entity count, memory growth, and loading pauses. Use placeholders for initial functional slices, bounded particle/projectile counts, and reduced-effects options when profiling supports them.

## 13. Implementation sequence

This sequence is proposed work ordering, not a dated delivery commitment. It reflects the GDD’s immediate menu/portal priority.

| Milestone | Deliverable | Exit condition |
|---|---|---|
| M0: Reconcile and initialize | Inspect repo/instructions, verify 4.7.1, establish project/input/audio/routes | Clean checkout imports and boots; intended export targets identified |
| M1: Hub and portals | Seven placeholder themes, reactive cycles, keyboard/gamepad focus, settings, three mode menus | Navigation and showcase acceptance checks pass; incomplete gameplay explicitly marked |
| M2: Platformer slice | One playable Bay Area segment, damage, one enemy/hazard, token, MERGE exit, retry | Complete playable loop with responsive movement |
| M3: Runner slice | Corridor chunks, lane/jump/roll, pursuit, time score, local top 10 | Clean-recovery and two-hit loop work; generation remains feasible |
| M4: Brawler slice | Stage-1 encounter, three-hit combo, weapon, destructible, gate, retry | Combat/gate/weapon loop works and cleans up |
| M5: Content completion | Remaining levels/stages/enemies/bosses, agreed pickups/effects, final art/audio | All three modes meet their full GDD core loops |
| M6: Polish and release validation | Optional effects selected by team, accessibility/display polish, desktop exports | Target-platform smoke tests and performance checks pass |

First implementation task: reconcile repository structure and build M1 on the smallest required M0 foundation. Do not implement all gameplay systems merely to make the hub launch safe placeholder destinations.

## 14. Verification strategy

Behavioral checks should target lifecycle and state boundaries, rather than mirror individual functions. A test framework is not selected yet. Use focused Godot test scenes or an agreed compatible framework; pin dependencies if adopted.

- Automated candidates: damage deduplication/i-frames; pursuit deadline and repeated recovery; combo expiry; weapon durability; effect refresh/expiry; score accumulation across frame rates; save validation/top-10 ordering; duplicate result rejection; generator seam feasibility; one-time boss transitions.
- Integration checks: all route/retry sequences, scene-load failures, pause/unpause, modal focus restoration, 50 rapid hub preview changes, repeated mode switching, brawler stage gates with summoned/resurrecting enemies.
- Soak proposal: a 30-minute accelerated runner simulation over multiple recorded seeds, inspecting active counts/memory and invalid chunk seams. Follow with actual interactive collision testing at maximum speed.
- Manual checks: jump feel, telegraphs, lane response, brawler depth clarity, input devices, readable UI, audio levels, aspect ratios, optional effects, actual desktop exports.

Potential commands once a repository and executable are available: `godot --version`, `godot --headless --path . --editor --quit`, and a bounded headless boot via `godot --headless --path . --quit-after 120`. These are suggested import/boot checks, not substitutes for gameplay assertions or rendered validation. They were not run for this document. Match the executable and export templates to 4.7.1 and verify command behavior locally.

## 15. Open decisions and intentional clarifications

| Decision | Proposed default / boundary | Resolve before |
|---|---|---|
| Renderer/minimum hardware | Profile a representative runner scene; no assumed GPU feature parity | Final asset/shader commitment |
| Pixel mode vs fill | Responsive 1280×720 UI; explicit policy for optional 320×180 content | Display feature completion |
| Runner movement frame | Stationary longitudinal player + scrolling world; one speed owner | Runner controller implementation |
| Runner lanes/projection | Three lanes, perspective fixed camera as prototype choices | Runner slice signoff |
| Pursuit/shield interaction | Clarify pickup vs blocked-hit reset; do not silently finalize | Shield implementation |
| Recovery boundary/i-frames | 18-second recovery; damage-before-recovery on a shared tick; tuned i-frames | Pursuit slice signoff |
| Platformer attack and bosses | Swipe/stomp selection, boss HP/patterns, exit routing TBD | Platformer content completion |
| Brawler armor/durability | Define armor HP cost; one durability per successful swing proposal | Combat balancing |
| Brawler stage checkpoint | Decide carried HP/score/weapon/effects and exact retry snapshot | Stage progression |
| Brawler jump/air attacks | Ground-plane position + visual height; aerial combos optional | Combat slice |
| Scores and pickups | Rates, rewards, multipliers, durations, stacking and boss eligibility TBD | Score/content balancing |
| Settings scope | Working volume/display basics; full rebinding separate agreed scope | Hub milestone completion |
| Optional polish/dependencies | Explicit selection; no required third-party addon assumed | Polish planning |

These decisions do not block creating the hub and portal foundation. They do block treating the affected gameplay details as final.

## 16. Maintenance record

v0.1 establishes source requirements, proposed ownership/interfaces, per-mode mechanics, open decisions, sequencing, and verification. No game code, repository changes, playable builds, or approved technical decisions are implied by this document’s creation.

For each later revision record: changed requirement, source/decision, affected systems, migration impact, and verification evidence. Keep the compact agent context synchronized with accepted changes.

## Repository implementation update — 2026-09-17

Main menu work reconciled this baseline against the initially empty Godot project and the current GDD. Godot 4.7.1 is installed and used for validation. The hub now uses scene-local two-preview alpha crossfades, Parallax2D, separate idle/focus state, input-source arbitration, settings with local persistence, shared audio buses, and validated navigation. Mode routes lead to explicitly labeled placeholders. User approved temporary rabbit art. Supplied music remains MP3 with looping enabled; title typography uses a system fallback. Corridor, Security, and Git HQ preview art is procedural pending final assets. See `docs/main-menu.md` for detailed implementation and verification; all non-menu gameplay sections remain proposals.
