# Endless Runner — Art Bible for the high-fidelity asset pass (A1–A9)

Purpose: nine Codex (gpt-6-astra) agents build high-fidelity, **procedural** assets in parallel, one asset package
each, on their own branch/worktree. Everything is generated in code at load time (meshes via `SurfaceTool` /
`ArrayMesh`, textures via `Image` → `ImageTexture`, shaders, particles, synthesized audio). No downloads, no
binary art, no external tools. An Opus 5 reviewer judges every package against this bible from host-rendered
captures before it is accepted; CodeRabbit runs on the integrated result.

## 1. The world and its mood

"The Codebase Corridor": Hoppy the CodeRabbit sprints through a living codebase at night. Everything is built
from code: walls are server racks and scrolling glyph screens, the floor is a lit grid, hazards are the pathologies
of a bad repository (PR backlogs, bug swarms, merge conflicts, deprecated pits, laser linters, comment floods,
build shockwaves), pickups are CodeRabbit's tools. It must read as a **premium, coherent sci-fi product** — think
a AAA neon-tech runner: crisp silhouettes, deep blacks, controlled emissive accents, everything slightly glossy and
industrial, never cartoon-flat and never noisy.

## 2. Palette (unchanged, `scenes/runner/environment/runner_palette.gd`)

| Token | Use |
|---|---|
| `NAVY_BG` / `NAVY_2` | base metals, panels, darkness |
| `SLATE` | secondary metal, tracks, frames |
| `MINT` | friendly UI, safe emissive, Hoppy accents |
| `MATRIX` | code glyphs, data streams, damageable highlights |
| `DANGER` (`ff4d3d`) | every hazard, projectile, boss aggression, alerts |
| `ORANGE` | tools, Nitro, warnings, "energy" |
| `LILAC` | the "theirs" side of merge conflicts only |
| `CREAM` | text, highlights, Hoppy fur |

Rule: **one accent hue per object** plus neutrals. Emissive never exceeds ~40 % of an object's surface.

## 3. Material language (gl_compatibility)

- Every surface is a `StandardMaterial3D` or `ShaderMaterial` with **albedo, roughness, metallic, normal** —
  no flat unlit colour except deliberate holograms. Metallic 0.6–0.9 with roughness 0.25–0.45 for panels; matte
  0.8+ roughness for fur/cloth/rubber.
- **Procedural textures** are generated at load into `ImageTexture` (256²–1024², cached by key in a shared
  cache script so identical maps are built once): panel plating with bevelled seams, rivets, hazard stripes,
  brushed metal anisotropy noise, cloth weave, fur streaks, circuit traces. Normal maps derived from the height
  field (Sobel). Roughness maps from the same height with wear on edges.
- **Silhouettes are bevelled** — no raw cubes. Chamfer every box (SurfaceTool with 45° bevel strips or a shared
  `bevel_box()` helper). Cylinders ≥ 24 radial segments; spheres ≥ 32 rings.
- **Emissive**: masked (glyph screens, seams, edge lights, eyes), animated in intensity through a `clock`
  uniform set from GDScript (never `TIME`), pulsing 0.7–1.3× at 0.5–2 Hz depending on threat.
- **Fresnel rim** on glass, energy and holograms; **parallax-style depth** for screens (a two-layer glyph shader).
- Lighting: one `DirectionalLight3D` key already exists in the corridor; assets add at most one `OmniLight3D`
  each, no shadows. Bake lighting into emissive/occlusion detail instead.
- Shaders: no SDFGI/SSR/volumetrics/decals (unsupported). Depth fog, glow (threshold 0.75), 0.5 3D scale stay.

## 4. Motion and effects

- Idle motion on everything organic (breathe, sway, flicker); mechanical things click into positions.
- Particles: `GPUParticles3D` with glyph atlas quads, additive, ≤ 64 per emitter, `visibility_aabb` sized; sparks,
  dust, data motes, exhaust; never obscure lanes.
- Transitions squash-and-stretch (Hoppy), snap-then-settle (mechanical), fade-in-then-lock (holograms).
- All animation driven by `_process` with `PROCESS_MODE_PAUSABLE`; nothing keeps moving while paused.

## 5. Budgets (hard caps the reviewer checks)

| Asset | Draw calls (peak) | Triangles | Textures |
|---|---|---|---|
| Hoppy | 40 | 20 k | ≤ 6 × 512² |
| Corridor (whole environment) | 24 | 60 k | ≤ 8 × 1024² |
| Each hazard | 16 | 6 k | shared atlas |
| Each pickup/tool | 8 | 3 k | shared |
| Each boss | 48 | 30 k | ≤ 4 × 1024² |
| Pursuer | 28 | 20 k | ≤ 3 × 1024² |
| UI | n/a (2D) | | vector-drawn |
| Post-process | 1 fullscreen pass | | |

MultiMesh for anything repeated; `physics_interpolation_mode = OFF` on cosmetic nodes driven from `_process`.
Gameplay contracts are untouched: hitboxes, envelopes (§11.5), lane geometry, hooks and signals stay exactly as
`docs/endless-runner-contract.md` states; visuals stay ≤ 110 % of hitboxes.

## 6. Consistency checklist (what the Opus reviewer scores 1–5 on each; ≥ 4 everywhere to accept)

1. **Theme fit** — reads as part of the same codebase-corridor world; CodeRabbit story is legible.
2. **Fidelity** — bevels, materials, texture detail, lighting response; no flat primitives visible.
3. **Palette discipline** — one accent per object, emissive ≤ 40 %, colours from the palette only.
4. **Readability in motion** — silhouette and colour communicate the gameplay meaning at 24–32 m/s.
5. **Motion quality** — idle life, transitions, no popping, pause-safe.
6. **Technical** — within budget, Compatibility-safe, no `TIME`, no warnings/errors in a graphical run, tests pass.

## 7. Working rules for every asset agent

- Your own worktree and branch; touch **only** the files listed in your brief plus new files under your asset's
  folder. Do not edit `tests/runner_visual_smoke.gd`, `capture_previews.gd`, `docs/endless-runner.md`,
  `runner_palette.gd`, `runner_materials.gd`, or any backend file — add new files instead (`tests/assets/<asset>_check.gd`
  for your headless checks, `scenes/runner/<area>/dev/capture_<asset>.gd` for your graphical capture writing
  `docs/previews/assets/<asset>-*.png`, `docs/assets/<asset>.md` for notes). The integrator wires them in.
- Shared helpers you may **create** (new files): `scenes/runner/environment/hifi/*.gd` (`texture_forge.gd` for
  procedural maps with a cache, `mesh_forge.gd` for bevelled/segmented primitives). If another asset needs the
  same helper, duplicate the minimal function into your own folder rather than editing theirs; the integrator
  dedupes.
- Keep every contract hook and every existing test green: run `--import`, `--check-only` on your scripts, your
  own `tests/assets/<asset>_check.gd`, and `tests/runner_visual_smoke.gd` + `tests/runner_smoke.gd` (the sandbox
  may fail only the two documented `user://` persistence checks — say so verbatim).
- Style: snake_case, no `class_name`, `const X = preload(...)`, typed `:=`, tabs, explicit return types, `.gd.uid`
  for new scripts, cached materials duplicated before mutation.
- Report: what you built, fidelity techniques used, budgets measured (headless census), verification output,
  the capture fixture path, files touched. Do not commit or push.
