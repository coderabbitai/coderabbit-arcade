# Builds

Playable builds come from `tools/build/export_game.py`, both locally and in the [Build workflow](../.github/workflows/build.yml). Each build is versioned and records its commit and engine. The workflow runs on Linux, so it smoke-tests the Linux build. Smoke-test the macOS and Windows builds by running `export_game.py --smoke` on those systems; each artifact's `smoke` field in `BUILD_MANIFEST.json` says which builds were checked.

## Get a build

| You want | Where |
|---|---|
| A specific release | **Releases**. Tag `v<version>` and the workflow publishes macOS, Windows, Linux and Web zips as a prerelease. |
| The latest `main` | **Actions → Build →** the newest run on `main` → **Artifacts**. Kept for 30 days. |
| A pull request's build | Add the `preview-build` label to the PR; the run's artifacts are kept for 7 days. Every PR is export-checked either way. |

Each platform is its own artifact: `hoppys-adventure-arcade-macos`, `-windows`, `-linux` and `-web`. Each includes `BUILD_MANIFEST.json` and `SHA256SUMS.txt`.

## Run it

- **macOS** (universal: Apple silicon and Intel): unzip, then open **Hoppy’s Adventure Arcade.app**. The app is ad-hoc signed, not notarized, so macOS blocks the first launch of a downloaded copy. Either choose **System Settings → Privacy & Security → Open Anyway**, or run:
  ```sh
  xattr -dr com.apple.quarantine "Hoppy’s Adventure Arcade.app"
  ```
- **Windows** (x86_64): unzip and run `HoppysAdventureArcade.exe`. SmartScreen may ask you to confirm (**More info → Run anyway**), because the build isn't code-signed.
- **Linux** (x86_64): unzip and run `./HoppysAdventureArcade.x86_64` (use `chmod +x HoppysAdventureArcade.x86_64` if your unzip tool drops executable permissions).
- **Web**: extract the whole zip, run `python3 -m http.server 8000 --bind 127.0.0.1` in that folder, and open `http://localhost:8000`. Opening `index.html` directly will not work. For shared hosting, serve the entire folder over HTTPS. This is a single-threaded WebGL 2 build, so it does not need cross-origin isolation headers. Click the game to enable audio. See [Godot's Web export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

## Run it at a booth

Launch with `--booth` to run an unattended kiosk. Arguments go after `--`; for a macOS app, use `open -a … --args …`.

```sh
./HoppysAdventureArcade.x86_64 -- --booth
./HoppysAdventureArcade.x86_64 -- --booth --route=heroes_vs_villains
open -a "Hoppy’s Adventure Arcade.app" --args -- --booth --route=heroes_vs_villains
```

- **Fullscreen.** The game starts fullscreen without changing the saved settings.
- **Idle reset.** After 90 seconds with no keyboard, mouse, touch or controller input, any game returns to the attract route. That is the hub, whose rotating previews act as the attract screen, unless `--attract=` names `beatem_up` or `runner`, the other menus that start their own music.
- **Game over.** A lost game doesn't offer unlimited retries. A player gets `--retries=<n>` retries (default 0); after that, the game shows no retry screen. Instead a **GAME OVER** card thanks the player, shows their score and counts down six seconds, then the attract route opens for the next player. The count starts again whenever the attract route opens. Every game takes part: Heroes vs. Villains, Code City Brawl, the platformer levels and the Endless Runner. Without `--booth`, every game keeps its own retry screen.
- **No quitting from the menu.** The menu's **Quit Game** does nothing in booth mode; staff close the window (Cmd+Q, Alt+F4).
- **Launch route.** `--route=<name>` opens a route at launch (`heroes_vs_villains`, `code_city_brawl`, `bay_area_blitz`, `orbital_ops`, `enchanted_repo`, `runner`, `platformer`, `beatem_up`, `hub`), with or without `--booth`. An unknown name logs an error and opens the hub.
- **Keep it running.** `tools/booth/watchdog.sh` relaunches the game whenever it exits and restarts it when it hangs. The watchdog passes `--heartbeat=<path>`, which makes the game rewrite that file with the current time every two seconds; a file that stops changing means the game is stuck. On a Mac, `tools/booth/macos/setup.sh` installs the watchdog as a login item and applies the kiosk settings. The [booth runbook](booth-runbook.md) walks staff through setup, the show days and recovery.
- **Session log.** Booth mode records each game session's start and end in `user://booth/`, one file per run of the game (`sessions-<date and time>-<process id>.jsonl`). Each entry records the game, the local start and end times, the duration, how the session ended (`menu`, `idle`, `game_over` or `quit`), how many times the player re-entered the game, and how many times they lost (`game_overs`, stage retries included). It records nothing about players and never uses the network. A start with no end means the game stopped without quitting: a crash, a power cut or a forced kill. The game prints its file's full path at startup. `--session-log=<folder>` writes to another folder and works without `--booth`, for playtests.

`user://` is `~/Library/Application Support/Godot/app_userdata/Hoppy’s Adventure Arcade/` on macOS, `%APPDATA%\Godot\app_userdata\Hoppy’s Adventure Arcade\` on Windows and `~/.local/share/godot/app_userdata/Hoppy’s Adventure Arcade/` on Linux. To summarize the logs, copy each machine's `booth` folder and run:

```sh
python3 tools/booth/sessions_report.py booth/                               # sessions per game, durations, end reasons, starts by hour
python3 tools/booth/sessions_report.py booth-a/ booth-b/ --csv sessions.csv # combine machines; one CSV row per session
```

## Soak test and frame rate

Before a show, let the build run unattended on the booth machine for a full show day:

```sh
python3 tools/booth/soak.py --minutes 600 -- "/Applications/Hoppy’s Adventure Arcade.app/Contents/MacOS/<executable>" -- --booth
python3 tools/booth/soak.py --minutes 10 --godot "$GODOT"     # a quick run of this checkout's project
```

- **The soak.** The game runs with `--soak=<minutes>` (wall-clock time). It visits every route in turn and stays `--soak-dwell=<seconds>` (default 30) on each with nobody playing, counted from when the route has opened. `--soak-routes=hub,heroes_vs_villains` keeps it to those routes; the hub is always included. `--soak-cycles=<n>` ends it after n full passes, if that comes first: `--soak=30 --soak-cycles=1` is a quick frame-rate probe of every route. A soak turns off the idle return and the game-over card, ignores `--route`, and writes no session log, so its visits never count as booth sessions.
- **Frame rate.** Every 5 seconds the game appends a CSV row for the current route: frames per second, median, 99th-percentile and worst frame times, and the engine's memory and object counts. At the end it prints a table per route: the share of frames slower than 16.7 ms (60 fps) and 33.3 ms (30 fps), percentiles capped at the worst frame, and the worst loading hitch. Run it fullscreen (`--booth`) on the booth hardware to measure at the booth resolution; headless frame times mean nothing.
- **Leak check.** At the end of each hub visit the game records its object, node, orphan-node and resource counts and prints `SOAK hub <n>`. It compares the second visit with the last, since the first warms caches. Debug builds also compare static memory, which release builds don't report. Growth beyond small limits makes the game exit 1. A route that won't open, or results that can't be written, make it exit 2.
- **Resident memory.** `soak.py` samples the process's memory with `ps` every 30 seconds (`--rss-every`) into `rss.csv`, and again at each `SOAK hub <n>` line. It compares the second hub visit with the last, once there are three, and fails above 25% growth (`--max-rss-growth`). It also fails a game that exits without a verdict, and stops a run that outlasts its time by 10 minutes (`--grace`). Each run gets its own folder under `soak-results/` (`--out`), holding the game's CSV and summary, `game.log` and `rss.csv`. macOS and Linux.

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

- The version is `application/config/version` in `project.godot`; it controls artifact filenames and the manifest. Blank macOS version fields inherit it. Windows resource modification is disabled for portable Linux CI exports, so the executable retains the template metadata; its zip and manifest carry the game version.
- To release: bump the version in a PR, merge, then push tag `v<version>` from `main`. The workflow refuses a tag that doesn't match the project version. For the current `0.1.0`:
  ```sh
  git switch main
  git pull --ff-only
  git tag v0.1.0
  git push origin v0.1.0
  ```
- The workflow verifies all four zip checksums, creates a draft, uploads all assets, then publishes a **prerelease** in the repository's **Releases** section. Failed draft uploads can be retried with **Re-run failed jobs**. Published releases are not overwritten: make a new version/tag for the next playtest.
- **Actions → Build → Run workflow** on a branch creates downloadable Actions artifacts only. Select an existing `v*` tag to build and release that tag. The workflow must be present on the default branch for the manual button to appear.
- No custom repository secrets or variables are required. The release job uses the automatic `GITHUB_TOKEN` with `contents: write`; repository/organization policy must allow GitHub Actions and that permission. Signing certificates and Apple notarization credentials are intentionally not configured for these playtest builds.
- Blank `export_path` fields are intentional: the build script supplies absolute staging paths. Preset names must remain `macOS`, `Windows Desktop`, `Linux`, and `Web`.
- CI smoke-tests the packaged Linux game. Web packaging checks that HTML, JavaScript, WebAssembly, and PCK files are present, but browser gameplay is not automated. Playtest each platform before promoting a prerelease.

## What the exports leave out

`tests/`, every `*/dev/*` preview scene and the `capture_*.gd` screenshot scripts. JSON manifests are included explicitly because the game reads them with `FileAccess`. Upgrading Godot means updating `godot.lock.json` (version, SHA-512 values from the release's `SHA512-SUMS.txt`) along with `project.godot`.
