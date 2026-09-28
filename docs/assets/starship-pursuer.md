# Spaceship pursuer refresh

The death entity is the Unreviewed PR Backlog in `scenes/runner/pursuer`, separate from the end-of-stage bosses. The real runner mounts this visual and triggers its catch animation on the second damaging hit during pursuit.

The existing 20 panel modules now sit inside a continuous beveled security chassis. Vented side housings, painted corner guards, fasteners, horizontal rails, inset sensor sockets and a central brow provide solid geometry and a recognizable mechanical face. Armor, recesses and machined edges use vertex colors in one additional batched surface. Panel materials have more diffuse response and higher roughness so spaceship lights reveal their depth. The approach retains 80–100% height, replacing the old 35–100% squash, and high-frequency lateral vibration is reduced.

The six headlines, red sensor lenses, cables, particles and shockwave remain. Backend files, damage/collision rules, camera, capture trigger, 1.4-second visual lunge, 0.7-second retreat, result timing and retry routing are unchanged. All earlier spaceship, hazard, pickup and Hoppy work is preserved.

## Evidence

`docs/previews/pursuer/index.html` compares before/after images. Each set includes the actual runner's pursuit, four catch frames at approximately 0.3/0.6/0.9/1.2 seconds, results, and a staged three-quarter portrait using spaceship lighting. The fixture applies two damaging hazard reports through the real hit manager, asserts caught/finished states, and does not save a leaderboard entry. Captures use seed 12345 and the same camera; timing is wall-clock sampled, so minor scene/particle differences are expected.

Validation on installed Godot `4.7.stable.official.5b4e0cb0f`, macOS Apple M5 Max, OpenGL Compatibility:

- `ASSET A6: PASS (108 checks)`.
- Census: 14 draws, 9,080 triangles including particles/text, three cached 256-square maps. The stricter existing 14-draw smoke budget is retained.
- Threat motion envelope: 5.5303 × 2.103306 m, inside the 6 × 2.6 m envelope.
- Graphical before/after fixture: seven images per run, all saves return OK; no engine errors.
- Full visual smoke checks pursuit, catch, retreat, reuse, pause and the actual menu/play/hit/recovery/caught/results/retry/menu/hub loop. Final result: `RUNNER VISUAL SMOKE: PASS (0 failures)` and `RUNNER FULL LOOP: PASS`.

The repository-pinned Godot 4.7.1, export builds, controller play and sustained frame-rate profiling were not verified.

## Reproduce

From the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/assets/a6_check.gd --log-file /tmp/pursuer-a6.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path hoppys-adventure-arcade --script res://tests/runner_visual_smoke.gd --log-file /tmp/pursuer-smoke.log
/Applications/Godot.app/Contents/MacOS/Godot --path hoppys-adventure-arcade --script res://scenes/runner/pursuer/dev/capture_refresh.gd --log-file /tmp/pursuer-after.log -- --after
```

Always pass `--after` for the final command to preserve original before captures.

## Files touched in this follow-up

- `scenes/runner/pursuer/pursuer_visual.gd`: chassis mounting and cosmetic approach motion.
- `scenes/runner/pursuer/hifi/forge.gd`: batched chassis geometry.
- `scenes/runner/pursuer/hifi/plating.gdshader`: diffuse/roughness adjustments.
- `scenes/runner/pursuer/dev/capture_refresh.gd` and UID: real capture fixture.
- `tests/assets/a6_check.gd`: chassis checks and existing stricter draw cap.
- `tests/runner_visual_smoke.gd`: expected cosmetic approach height only, in addition to the prior pickup-yaw change.
- This report and `docs/previews/pursuer/` evidence.

Scene/test paths above are relative to `hoppys-adventure-arcade/`. Work remains uncommitted.
