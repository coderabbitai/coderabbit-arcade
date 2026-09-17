# Hoppy’s Adventure Arcade — Agent Context

Use alongside `Hoppys_Adventure_Arcade_Technical_Implementation.md` v0.1. This is compact context for future implementation tasks, not an automatic memory mechanism or evidence of implemented code.

## Authority

- User-specified engine: **Godot 4.7.1**, GDScript. Do not upgrade implicitly.
- [GDD](https://docs.google.com/document/d/1YCLWNykTNDglKGyuOWIMdTl9A8eEoEEgTR_INSOCdUo/edit) governs game design; source snapshot read on 2026-09-16.
- Baseline v0.1 contains engineering proposals and open decisions, not team-approved commitments. User instructions prevail; surface conflicts with source/repository behavior.
- [Repository named by GDD](https://github.com/coderabbitai/coderabbit-arcade) has not been inspected for the baseline. Read repository instructions and actual code before creating or changing architecture.

## Product

Single desktop arcade application for PC/macOS/Linux with keyboard/gamepad, shared Hoppy identity, central hub, and three modes. No networking is required.

- Platformer: 2D, 3 HP, coyote time/jump buffering, attack, i-frames, three selectable levels: Bay Area Blitz, Orbital Ops, Enchanted Repo. Bosses: Merge Conflict Monster, Deprecated API, Legacy Monolith. MERGE exit; death retries selected level.
- Runner: fixed-camera 3D corridor, automatic progress, lane shifts, jump/roll, weighted procedural chunks. First unblocked hit starts pursuit at 1 HP; second before recovery kills; 15–20 clean seconds restores 2 HP. Time-based score and local top 10 at `user://leaderboard.cfg`.
- Brawler: 2D belt scrolling, 8-way ground movement, 3 HP, jab/swing/kick combo, dedicated pickup, finite-durability weapons, status effects, allies, destructibles, enemy gates. CLI/IDE District → Security Sector → Git HQ; retry current stage. Grand Merge Conflict phase changes at 50%/25% HP, then MERGE finisher.

## Proposed architecture

- One project; separate mode scenes/controllers. Share assets, definition Resources, and suitable damage logic; do not force one movement controller across modes.
- AppRouter, SaveService, AudioService are initial Autoloads. HP, score, pursuit, statuses, HUD, and showcase controllers are scoped to their mode/scene.
- Runtime state is per instance. Never mutate shared Resource definitions for current HP, timers, or weapon durability.
- Navigation validates destinations and prevents duplicate transitions. Destroy old timers/tweens/session state; retry creates fresh state. Return to hub must not leak mode state.
- Damage is deduplicated by attack/target; i-frames and shields precede HP changes; death/result/score events fire once.
- Pause freezes gameplay, scoring, pursuit recovery, and effect durations consistently.

## Hub requirements

Seven previews: Bay Area, Orbital, Enchanted, Corridor, CLI/IDE, Security, Git HQ.
Idle cycles 0–6 every 8–10s with 1.2s fades. Platformer focus cycles 0/1/2 every 3s at 0.6s fades; runner holds 3 with 0.8s fade; brawler cycles 4/5/6 every 3s at 0.6s fades. Focus exit waits 2s then resumes preserved idle sequence. Gamepad focus mirrors hover.

Proposed implementation uses a scene-local controller, separate idle/focus state, at most two live preview instances, bounded/cancel-safe transitions, Parallax2D, and alpha crossfade first. UI includes logo/Hoppy, mode launch buttons, settings, quit, music and UI sounds. Hoppy reactions, CRT, dissolve, and adaptive audio are optional.

## Critical implementation cautions

- Runner GDD mentions both forward player motion and chunk scrolling: choose one longitudinal-motion model. Proposed baseline scrolls world past a near-stationary player. Never apply full forward speed to both.
- Runner generator must validate reachable routes across chunk seams at current/max speed; keep active chunks bounded. Seeded generation helps reproduce failures.
- Pursuer is presentation of damage state: elapsed clean time recovers, not kills. Initial 18s tuning is a proposal. Shield’s pursuit-reset trigger is unresolved.
- Brawler screen Y is ground depth: jump needs separate height, not platformer gravity. Melee requires depth filtering. Gates account for duplicates and resurrection.
- CanvasLayer is layering, not resolution control. Proposed UI reference is 1280×720; optional 320×180 integer scaling needs a crop/letterbox policy.
- Music and SFX buses each feed Master. Validate renderer-dependent effects on actual targets.
- Power-up suites remain draft design. Score rates, stacking, stage checkpoint carry-over, armor behavior, and AoE durability policy need explicit decisions.

## Work order and validation

Start with repository reconciliation, pinned-engine boot, then hub and safe mode portals. Next build one playable slice per mode before full content and polish. Placeholder gameplay must be labeled accurately.

Test state boundaries: hit deduplication, pursuit/recovery, combo expiry, durability, effect cleanup, bounded/feasible generation, save failures/top-10 ordering, retry/navigation cleanup, and boss transitions. Run rendered keyboard/gamepad and desktop-export smoke checks as well as headless import/logic checks. Do not claim tests or builds were run without evidence.

For exact mechanics/content catalogs, open the relevant full-baseline section: §6 hub, §8 platformer, §9 runner, §10 brawler, §11 persistence, §13 milestones, §14 validation, §15 decisions. Update both documents when decisions are accepted.

## Repository implementation update — 2026-09-17

The central main menu is now implemented in `hoppys-adventure-arcade/scenes/main_menu/`, with AppRouter, SaveService, and AudioService Autoloads. The three mode routes are explicitly labeled non-playable placeholders. The user approved a temporary rabbit; final Hoppy sprites and branding remain replaceable. See `docs/main-menu.md` for asset mapping, implementation choices, and validation scope. Gameplay systems described above remain proposals.
