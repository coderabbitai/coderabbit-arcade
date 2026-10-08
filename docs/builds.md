# Builds

Playable builds come from `tools/build/export_game.py`, both locally and in the [Build workflow](../.github/workflows/build.yml). Each build is versioned and records its commit and engine. The workflow runs on Linux, so it smoke-tests the Linux build. Smoke-test the macOS and Windows builds by running `export_game.py --smoke` on those systems; each artifact's `smoke` field in `BUILD_MANIFEST.json` says which builds were checked.

## Get a build

| You want | Where |
|---|---|
| A specific release | **Releases**. Tag `v<version>` and the workflow publishes macOS, Windows and Linux zips as a prerelease. |
| The latest `main` | **Actions → Build →** the newest run on `main` → **Artifacts**. Kept for 30 days. |
| A pull request's build | Add the `preview-build` label to the PR; the run's artifacts are kept for 7 days. Every PR is export-checked either way. |

Each platform is its own artifact: `hoppys-adventure-arcade-macos`, `-windows` and `-linux`. Each includes `BUILD_MANIFEST.json` and `SHA256SUMS.txt`.

## Run it

- **macOS** (universal: Apple silicon and Intel): unzip, then open **Hoppy’s Adventure Arcade.app**. The app is ad-hoc signed, not notarized, so macOS blocks the first launch of a downloaded copy. Either choose **System Settings → Privacy & Security → Open Anyway**, or run:
  ```sh
  xattr -dr com.apple.quarantine "Hoppy’s Adventure Arcade.app"
  ```
- **Windows** (x86_64): unzip and run `HoppysAdventureArcade.exe`. SmartScreen may ask you to confirm (**More info → Run anyway**), because the build isn't code-signed.
- **Linux** (x86_64): unzip and run `./HoppysAdventureArcade.x86_64`.

## Run it at a booth

Launch with `--booth` to run an unattended kiosk. Arguments go after `--`; for a macOS app, use `open -a … --args …`.

```sh
./HoppysAdventureArcade.x86_64 -- --booth
./HoppysAdventureArcade.x86_64 -- --booth --route=heroes_vs_villains
open -a "Hoppy’s Adventure Arcade.app" --args -- --booth --route=heroes_vs_villains
```

- **Fullscreen.** The game starts fullscreen without changing the saved settings.
- **Idle reset.** After 90 seconds with no keyboard, mouse, touch or controller input, any game returns to the hub, whose rotating previews act as the attract screen.
- **No quitting from the menu.** The menu's **Quit Game** does nothing in booth mode; staff close the window (Cmd+Q, Alt+F4).
- **Launch route.** `--route=<name>` opens a route at launch (`heroes_vs_villains`, `code_city_brawl`, `bay_area_blitz`, `orbital_ops`, `enchanted_repo`, `runner`, `platformer`, `beatem_up`, `hub`), with or without `--booth`. An unknown name logs an error and opens the hub.

## Build locally

```sh
python3 tools/build/fetch_godot.py --templates          # pinned Godot 4.7.1 + export templates, SHA-512 verified
python3 tools/build/export_game.py --smoke               # all platforms into build/dist/
python3 tools/build/export_game.py --preset macOS --smoke
```

- `fetch_godot.py` downloads the editor for your OS and the export templates listed in [`tools/build/godot.lock.json`](../tools/build/godot.lock.json). It refuses anything whose SHA-512 doesn't match. It prints the editor path; `export_game.py` uses it automatically, or `$GODOT` / `--godot` if you set one.
- `export_game.py` checks the engine version and imports the project. It then exports each preset in `hoppys-adventure-arcade/export_presets.cfg` and zips the result as `hoppys-adventure-arcade-<version>-<commit>-<platform>.zip`.
- `--smoke` unzips the build for this machine's OS and launches it with `--headless -- --smoke-routes`. Builds for other systems are recorded as "not run on this host". That loads every `AppRouter` route from the packaged game and fails on any engine error, script error or leak. This catches files missing from the export, such as the art manifests the platformer and beat 'em ups read at runtime.

## Versions and releases

- The version is `application/config/version` in `project.godot`; the macOS bundle and Windows file version use it too.
- To release: bump the version in a PR, merge, then push tag `v<version>` from `main`. The workflow refuses a tag that doesn't match the project version.

## What the exports leave out

`tests/`, every `*/dev/*` preview scene and the `capture_*.gd` screenshot scripts. JSON manifests are included explicitly because the game reads them with `FileAccess`. Upgrading Godot means updating `godot.lock.json` (version, SHA-512 values from the release's `SHA512-SUMS.txt`) along with `project.godot`.
