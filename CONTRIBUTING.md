# Contributing to Hoppy's Adventure Arcade

Thanks for helping out! This guide covers setup, workflow, testing and the asset rules.

## Setup

1. Install **Godot 4.7.1** (standard build, not .NET). Other versions are not supported; please don't upgrade the project file.
2. Clone the repo and open `hoppys-adventure-arcade/project.godot`, or run it from the command line:
   ```sh
   godot --path hoppys-adventure-arcade
   ```
3. Turn on the local commit checks once per clone:
   ```sh
   git config core.hooksPath .githooks
   ```
   Before each commit, `.githooks/pre-commit` blocks local machine paths and links to internal documents or chats (`tools/checks/repo_hygiene.py`). It also scans staged changes for secrets with [gitleaks](https://github.com/gitleaks/gitleaks) and lints staged Python with ruff, when those are installed. CI runs the same checks, but only the local hook stops a problem before it reaches the remote's history.
4. Before running the test scripts for the first time, import the resources:
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

The tests are standalone `SceneTree` scripts. Each one exits nonzero on failure:

```sh
godot --headless --path hoppys-adventure-arcade --script res://tests/runner_logic.gd
godot --headless --path hoppys-adventure-arcade --script res://tests/platformer_smoke.gd
```

CI runs every headless suite listed in `.github/workflows/ci.yml`. Add a focused regression test when you change behavior. Some suites capture screenshots when run without `--headless`; include those in the PR for visual changes. On macOS, pass `--always-on-top` for graphical runs so the capture doesn't stall when the window is covered.

Per-mode notes and test details live in [`docs/`](docs/).

## Code style

- GDScript: follow the [Godot style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html), with typed variables and tabs. `.editorconfig` covers the basics.
- Python tools (`tools/`): keep them dependency-light and reproducible.
- Keep runtime state per instance. Never mutate shared `Resource` definitions at runtime.
- Add-ons under `hoppys-adventure-arcade/addons/` are vendored, unchanged copies of a tagged upstream release, recorded in `tools/vendor/vendor.lock.json`. CI and the pre-commit hook fail if a copy differs from its lock. Change an add-on upstream, then refresh it with `python3 tools/vendor/vendor_lock.py --update <name> --tag <tag> --source <upstream checkout>`.

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
