# The Enchanted Repo — v1 playable

Implemented in Godot 4.7.1 from the current shared GDD's Platformer section, the technical baseline, Agent Context, Enchanted Repo asset guide, and Orbital Ops' shared session and testing lessons.

## Play

Choose **Platformer Game → Level Select → Play Enchanted Repo**. Direct scene: `res://scenes/platformer/enchanted_repo.tscn`.

Move with A/D or arrows, jump with Space/W/up, swipe with J/X, pause with Escape. Existing gamepad mappings remain stick/D-pad movement, A/Cross jump, X/Square attack, and Start pause. Release Jump early for a short hop. Descending onto an enemy bounces Hoppy; the Monolith takes damage only in its recovery windows.

Cross the forest and ruined castle, defeat the Legacy Monolith, then land on or swipe the unlocked MERGE button. Standing beside it or rising through it does not finish the level. Retry starts a completely fresh Enchanted Repo run.

## Route and hazards

The 5,300-pixel route has three gaps (160–170 px), six solid raised root platforms, five crumbling branches, six ordinary enemies, five timed hazards, 25 Commit Tokens, and the existing shield, healing, boost and Auto-Fix pickups. Upper routes offer rewards; gaps are also jumpable without waiting for branch regrowth. A full-heal pickup precedes the boss arena.

Branches support Hoppy until 0.7 seconds after landing, then remove collision, show breaking/falling art, and regrow after a 0.25-second break plus 3.5-second absence. Regrowth waits if Hoppy occupies the future platform shape. Pause freezes all timers. Branches over gaps provide stepping stones; falling into a pit still kills Hoppy through the normal retry flow.

Comment traps and Spaghetti Code Vines use 2.0 seconds dormant, 0.9 seconds amber warning, 0.45 seconds active, and 1.55 seconds recovery. Only active intervals damage. Comment traps mark a 64×130 vertical region. Vines mark a 155×48 low horizontal region on their fixed attack side; jump over it or wait. Rectangular cues show actual damage extents. Vines are environmental hazards in v1, not destructible enemies.

Nitpick Gnomes have 1 HP, a short patrol, a 0.6-second jab tell and 0.65-second recovery. Bloat Trolls have 2 HP, slower patrols, a 0.95-second club tell and 1.0-second recovery. Both attacks stay committed to the warned side, have a 0.22-second active interval, and disable contact damage during recovery. Ordinary kills award 100 points and tokens award 25. Auto-Fix defeats nearby ordinary enemies but excludes the boss. Shared shields, 1.2-second post-hit invulnerability, player movement, jump buffering, coyote time, pause, and results are unchanged.

## Legacy Monolith

Crossing x=4300 while grounded starts the inherited protected 1.8-second intro. Gates close at x=4180/4970, the camera pans to a fixed arena view, player movement pauses, and traversal enemies/hazards stop. The boss cannot attack or take damage during the intro. Music transitions and intro timing respect pause.

The Monolith has **3 outer-armor hits + 3 inner-armor hits + 6 core hits**. Ordinary swipes or stomps deal one hit only during recovery. The HUD names the current layer and remaining hits. Each armor break interrupts combat for one second, scatters stone fragments, and switches permanently to the next art tier; further hits during that transition are ignored. Recovery contact is safe. Bare-core art remains bare during all subsequent attacks.

| Routine | Warning / active / recovery |
|---|---|
| Debt Slam | 1.0s overhead tell, 0.18s ground impact within 175px, 1.4s recovery |
| Dependency Sweep | 0.9s committed direction tell, 0.25s low sweep reaching 215px, 1.4s recovery |
| Regression Stomp | 1.0s raised-foot tell, 0.2s local impact within 95px, one 260px/s ground shockwave, 1.6s recovery |

Slow tracking intervals separate attacks. The boss stays between x=4350 and 4810, and stops advancing within 160px of Hoppy. Jumping clears the low attacks. Damage remains one heart; reach, commitment and knockback provide the heavy impact. The wave uses Orbital's terrain/player collision and swept movement ray, expires after four seconds, and respects shields/i-frames. The independently generated armor sheets use adjusted offsets/scales to keep feet and approximate body height consistent.

Defeat awards 1,000 points once, leaves the final rubble pose, clears projectiles, opens the gates, restores the following camera, resumes traversal music, and unlocks MERGE. HP, armor and timers are per-instance; SpriteFrames resources are never mutated.

These numerical timings, armor counts and patterns are v1 implementation choices, not final balance commitments or retroactive GDD requirements.

## Music and implementation

The requested files are used directly from `Assets/Audio/Platformer/The Enchanted Repo/`:

- `04 - Silent Forest.mp3`: traversal, fresh retry and after boss defeat.
- `05 - Battle 1.mp3`: begins during the intro and continues through the fight.

The shared scene-local Music-bus player loops through its finished signal, changes tracks with pause-aware fades, suspends arcade music while playing and restores it on leaving. Shared imported streams are not changed. Existing Platformer jump/hurt/UI sounds are reused.

`scenes/platformer/enchanted_repo.gd` extends the existing `modes/platformer/level.gd`. New local scripts provide art crops, enemies, branch lifecycle, timed hazards, Monolith combat, and a ground-wave subclass of Orbital's projectile. The shared player and level lifecycle are unchanged. The router and Level Select now expose the new level with its own layered artwork. Background plates are finite scenery overlapped for coverage, not seamless textures. Terrain combines cropped kit sprites with separate collision solids, as in Orbital Ops; no editor-painted TileSet is claimed.

## Validation and limits

Run Godot with `--headless --path hoppys-adventure-arcade --log-file /tmp/enchanted-smoke.log --script res://tests/enchanted_repo_smoke.gd`. Omit `--headless` for captures at `/tmp/enchanted-{spawn,boss,core,complete,level-select}.png`.

The smoke suite passes headless and rendered: spawn, real platform/branch boarding, crumble collision and regrowth, pause, comment/vine damage phases, shields/i-frames, two-hit troll combat, complete three-gap route using movement input, safe intro, arena camera/gates, both music transitions, committed sweep, slam avoidance/damage, wave collision/pause, actual recovery swipe, both armor transitions, one-time score, defeat cleanup, MERGE, retry, pit death, and menu/audio restoration. The route uses combat invulnerability to isolate reachability. Boss boundary checks manipulate states to isolate mechanics; this is not a claim of a no-hit or fully autonomous boss playthrough.

`tests/enchanted_boundaries.gd` checks occupied branch regrowth, safe quill warning/recovery, committed jab side, Auto-Fix boss exclusion, retained bare attack art, and fresh-instance armor. Orbital's complete smoke suite and Bay Area's smoke suite pass as regressions. Rendered spawn, boss, core, results and Level Select captures were reviewed.

The macOS sandbox aborts graphical launches before engine output; the rendered suite ran with approved graphical access. Headless import reports existing global-editor-settings/certificate sandbox warnings. No packaged exports or physical-controller session were tested. Fine animation registration, background joins, enemy death effects and longer hands-on balance testing remain polish work. No checkpoint saving or new audio assets were added.
