# Hoppy’s Adventure Arcade

A Godot 4.7.1 arcade collection with a reactive main menu, playable Platformer levels **Bay Area Blitz**, **Orbital Ops**, and **The Enchanted Repo**, plus the **Endless Runner** (The Codebase Corridor). Beat’em Up remains a labeled placeholder.

Open `hoppys-adventure-arcade/project.godot` and press **F5**. Choose **Platformer Game → Level Select**, then choose any of the three levels.

Move with A/D or arrows, jump with Space, swipe with J/X, and pause with Escape. Controller movement, A/Cross jump, X/Square attack, and Start pause are also mapped.

See [Bay Area Blitz notes](docs/bay-area-blitz.md), [Orbital Ops notes](docs/orbital-ops.md), and [Enchanted Repo notes](docs/enchanted-repo.md) for gameplay, tuning, implementation limits, and tests; see [main menu notes](docs/main-menu.md) for the arcade hub. In Orbital's zero-gravity bay, hold Jump/Up to rise, Down to descend, and release to brake.

Endless Runner frontend: F0-F10, high-fidelity A1–A9 asset pass with Blender-authored Hoppy, revised walls, pickup visibility, grab-vs-avoid legend/toasts, and contract 2.2 post-processing. [Run, asset budgets/checks, ownership, and verification caveats](docs/endless-runner.md). Godot 4.7.0 diagnostics; acceptance pinned to 4.7.1.

Beat'em Up Mode 1 now has a [Code City Brawl asset pack](docs/code-city-brawl-assets.md): three stage panoramas, nine enemies, the Grand Merge Conflict, hazards, breakables, weapons, pickups and allies. Gameplay assembly follows this assets-only pass.
