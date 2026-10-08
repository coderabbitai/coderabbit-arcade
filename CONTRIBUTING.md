# Contributing to Hoppy's Adventure Arcade

Thanks for helping out! This guide covers setup, workflow, testing and the asset rules.

## Setup

1. Install **Godot 4.7.1** (standard build, not .NET). Other versions are not supported; please don't upgrade the project file.
2. Clone the repo and open `hoppys-adventure-arcade/project.godot`, or run it from the command line:
   ```sh
   godot --path hoppys-adventure-arcade
   ```
3. Before running the test scripts for the first time, import the resources:
   ```sh
   godot --headless --path hoppys-adventure-arcade --import
   ```

## Workflow

- `main` is the only long-lived branch and is protected. Work on a short-lived branch such as `feat/runner-magnet`, `fix/orbital-boss-hitbox` or `docs/controls`.
- Open a pull request against `main`. PRs are **squash-merged**, so the PR title becomes the commit message. Please use [Conventional Commits](https://www.conventionalcommits.org/) style for the title, e.g. `feat(runner): add magnet power-up`.
- For anything larger than a small fix, open an issue first so we can agree on the approach.
- Every PR gets an automated review from [CodeRabbit](https://coderabbit.ai). Address or reply to its comments, as you would for a human reviewer. All conversations must be resolved before merging.
- CI must pass, and a code owner must approve.

## Tests

The tests are standalone `SceneTree` scripts under `hoppys-adventure-arcade/tests/`. Run them all the way CI does:

```sh
python3 tools/tests/run_tests.py --godot /path/to/Godot      # or set $GODOT
python3 tools/tests/run_tests.py -k runner                   # suites whose name contains "runner"
python3 tools/tests/run_tests.py --list                      # what runs and what is skipped
```

- **Every new `.gd` file under `tests/` runs automatically.** There's no list to update. To keep a suite out of CI (it needs a GPU, a window or pointer hover), add it to `[skip]` in [`tools/tests/suites.toml`](tools/tests/suites.toml) with the reason.
- **A suite fails if it exits nonzero, times out, or prints an engine or script error or an exit-time leak.** That includes `ERROR:`, `SCRIPT ERROR`, parse errors and "leaked at exit". If a test provokes an engine error on purpose, list a pattern for it under `[expected_errors]`; the runner fails if that pattern stops matching.
- **Finish a suite with `await root.get_node("AudioService").settle()` before `quit()`.** It stops the shared music and waits until the audio thread has released it. A fixed delay is not enough under parallel load.
- Each suite runs with its own `HOME`, so `user://` files (settings, leaderboards) never touch your real ones. Results are written to `build/test-results/summary.json`.

To run a single suite directly:

```sh
godot --headless --path hoppys-adventure-arcade --script res://tests/runner_logic.gd
```

Add a focused regression test when you change behavior. Some suites capture screenshots when run without `--headless`; include those in the PR for visual changes. On macOS, pass `--always-on-top` for graphical runs so the capture doesn't stall when the window is covered.

Per-mode notes and test details live in [`docs/`](docs/).

## Code style

- GDScript: follow the [Godot style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html), with typed variables and tabs. `.editorconfig` covers the basics.
- Python tools (`tools/`): keep them dependency-light and reproducible.
- Keep runtime state per instance. Never mutate shared `Resource` definitions at runtime.

## Assets

Every new asset must be redistributable in a public repository.

- Accepted: third-party assets under **CC0** or **CC BY 4.0**.
- Original art, audio or models made for the project: please **open an issue first**. The license for project-original assets hasn't been finalized yet (see [`ASSETS_LICENSES.md`](ASSETS_LICENSES.md#project-original)), so we can't merge original-art contributions until it is. Procedural assets generated in GDScript count as code and fall under the MIT license.
- Not accepted: "free for use but no redistribution" packs, which covers most free marketplace packs. Also not accepted: NC/ND licenses, and assets of unknown origin.
- Add a row to [`ASSETS_LICENSES.md`](ASSETS_LICENSES.md) in the same PR, and include the upstream license file next to the asset.
- AI-generated assets: record the tool and prompts, following the existing `PROMPTS.md` / `generation.json` convention. Don't record local machine paths.

## Reporting bugs and security issues

Use the issue templates for bugs and feature requests. For security issues, see [SECURITY.md](SECURITY.md); please don't open a public issue.

By participating, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).
