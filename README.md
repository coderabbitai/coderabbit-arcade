# Hoppy’s Adventure Arcade

[![CI](https://github.com/coderabbitai/coderabbit-arcade/actions/workflows/ci.yml/badge.svg)](https://github.com/coderabbitai/coderabbit-arcade/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![Godot 4.7.1](https://img.shields.io/badge/Godot-4.7.1-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)

A Godot 4 arcade collection starring Hoppy, the CodeRabbit mascot. It has a reactive main menu, three Platformer levels (**Bay Area Blitz**, **Orbital Ops** and **The Enchanted Repo**) and the **Endless Runner** (The Codebase Corridor). The Beat’em Up mode is still a labeled placeholder; its [Code City Brawl asset pack](docs/code-city-brawl-assets.md) has landed ahead of gameplay.

![Main menu](docs/previews/main-menu.png)

## Play

1. Install [Godot **4.7.1**](https://godotengine.org/download/archive/) (standard build).
2. Open `hoppys-adventure-arcade/project.godot` and press **F5**, or run:
   ```sh
   godot --path hoppys-adventure-arcade
   ```
3. Choose **Platformer Game → Level Select**, or **Endless Runner**.

| Action | Keyboard | Controller |
|---|---|---|
| Move | A/D or arrow keys | Left stick / D-pad |
| Jump | Space | A / Cross |
| Attack | J / X | X / Square |
| Pause | Escape | Start |

In Orbital Ops' zero-gravity bay, hold Jump or Up to rise, hold Down to descend, and release to brake.

## Docs

- Platformer: [Bay Area Blitz](docs/bay-area-blitz.md), [Orbital Ops](docs/orbital-ops.md), [The Enchanted Repo](docs/enchanted-repo.md)
- [Endless Runner](docs/endless-runner.md): how to run it, asset budgets, verification. See also its [contract](docs/endless-runner-contract.md) and [systems](docs/endless-runner-systems.md).
- [Main menu / arcade hub](docs/main-menu.md)

## Tests

```sh
godot --headless --path hoppys-adventure-arcade --import
godot --headless --path hoppys-adventure-arcade --script res://tests/runner_logic.gd
```

Each file in `hoppys-adventure-arcade/tests/` is a standalone script that exits nonzero on failure. CI runs the headless suites on every PR. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and our [Code of Conduct](CODE_OF_CONDUCT.md). To report a security issue, see [SECURITY.md](SECURITY.md).

## License

- Code: [MIT](LICENSE)
- Assets: individual licenses; see [ASSETS_LICENSES.md](ASSETS_LICENSES.md)
- The CodeRabbit name and the Hoppy mascot are trademarks; see [TRADEMARKS.md](TRADEMARKS.md)
