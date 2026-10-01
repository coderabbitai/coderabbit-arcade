# Hoppy’s Adventure Arcade

A Godot 4.7.1 arcade collection with a reactive main menu, playable Platformer levels **Bay Area Blitz** and **Orbital Ops**, plus the **Endless Runner** (The Codebase Corridor). Beat’em Up and Enchanted Repo remain labeled placeholders.

Open `hoppys-adventure-arcade/project.godot` and press **F5**. Choose **Platformer Game → Level Select**, then play Bay Area Blitz or Orbital Ops.

Move with A/D or arrows, jump with Space, swipe with J/X, and pause with Escape. Controller movement, A/Cross jump, X/Square attack, and Start pause are also mapped.

See [Bay Area Blitz notes](docs/bay-area-blitz.md) and [Orbital Ops notes](docs/orbital-ops.md) for gameplay, tuning, implementation limits, and tests; see [main menu notes](docs/main-menu.md) for the arcade hub. In Orbital's zero-gravity bay, hold Jump/Up to rise, Down to descend, and release to brake.

Endless Runner frontend: F0-F10, high-fidelity A1–A9 asset pass with Blender-authored Hoppy, revised walls, pickup visibility, grab-vs-avoid legend/toasts, and contract 2.2 post-processing. [Run, asset budgets/checks, ownership, and verification caveats](docs/endless-runner.md). Godot 4.7.0 diagnostics; acceptance pinned to 4.7.1.
