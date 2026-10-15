# Booth runbook

This runbook is for the staff who run Hoppy’s Adventure Arcade unattended at a booth, such as booth 528 at re:Invent. It covers a Mac running the game, with a second Mac set up the same way as a spare. The watchdog also runs on Linux; Windows isn't covered.

## Pack list

- The booth Mac and a spare Mac, each set up and tested with the steps below.
- A USB stick with the macOS build zip from [Releases or Actions](builds.md#get-a-build) and a copy of this repository, which has the booth tools in `tools/booth/`.
- The controllers plus one spare, with their cables or wireless dongles, the display cable and a power strip.
- A keyboard and mouse for staff. Keep them out of players' reach.

## Set up a machine (once, about 20 minutes)

1. Sign in to the account the booth will use.
2. Unzip the build and move **Hoppy’s Adventure Arcade.app** to **Applications**.
3. In Terminal, from the copy of this repository, see what the setup will change:
   ```sh
   tools/booth/macos/setup.sh --app "/Applications/Hoppy’s Adventure Arcade.app" --route heroes_vs_villains
   ```
   Nothing changes yet. To apply it, run the same command with `--apply` and enter the administrator password when asked. The game starts. To give each player a retry or change the attract screen, add game flags after `--`, for example `-- --retries=1 --attract=beatem_up` ([booth flags](builds.md#run-it-at-a-booth)).
4. Do the manual steps the script lists at the end: automatic login, Do Not Disturb, the display, the volume and the controllers.
5. Restart the Mac. The game should start on its own within a minute.

The setup does the following:
- It installs the watchdog (`tools/booth/watchdog.sh`) as a login item. The watchdog starts the game in booth mode, relaunches it whenever it closes or crashes, and restarts it when it freezes.
- It removes the download quarantine, so Gatekeeper doesn't block the app.
- It keeps the Mac awake and turns it back on after a power cut.
- It turns off the screen saver, automatic updates and crash dialogs.

Booth mode itself runs fullscreen and ignores the menu's **Quit Game**. A game nobody has touched for 90 seconds goes back to the hub's attract screen, and so does a lost game, after a thank-you card for the player ([details](builds.md#run-it-at-a-booth)).

## Every morning

1. Turn the Mac on. It logs in, and the game appears within a minute.
2. Check that every controller moves Hoppy and that the volume suits the floor.
3. Play one short round.

## During the show

| What happens | What you'll see |
|---|---|
| A player walks away mid-game | After 90 seconds the game returns to the hub. |
| A player loses | A **GAME OVER** card thanks them and shows their score, and after six seconds the hub opens for the next player. |
| The game crashes or closes | The watchdog opens it again within a few seconds. |
| The game freezes | The watchdog restarts it within about a minute. |
| Someone presses Cmd+Q | The game closes, and the watchdog opens it again. |
| The player's controller disconnects | The game pauses and asks for the controller. Plug it back in, or press Start on another controller. |
| You want to clear the Endless Runner scores | **Endless Runner → Leaderboard → Reset scores**. |

## Stop the game for maintenance

```sh
touch ~/Library/Application\ Support/HoppyBooth/stop
```

Then press Cmd+Q. The game stays closed. To bring it back, restart the Mac or run:

```sh
launchctl kickstart gui/$(id -u)/ai.coderabbit.arcade.booth
```

The watchdog removes the stop file when it starts.

## Swap to the spare

1. Move the display cable and the controllers to the spare Mac and turn it on. It starts the game on its own.
2. Copy the session logs off the first Mac when there's time (see below).

## Collect the session logs

The game records each session's start and end in `~/Library/Application Support/Godot/app_userdata/Hoppy’s Adventure Arcade/booth/`, one file per run of the game. It records the game, the times and the length, and nothing about players. At the end of each day, copy the whole `booth` folder to the USB stick and leave the original in place. To summarize every machine's folder at once:

```sh
python3 tools/booth/sessions_report.py booth-a/ booth-b/ --csv sessions.csv
```

## Troubleshooting

The watchdog writes launches, exits and restarts to `~/Library/Logs/HoppyBooth/watchdog.log`, and the game's own output to `~/Library/Logs/HoppyBooth/game.log`.

| Problem | What to do |
|---|---|
| No game after login | Read `watchdog.log`. Run `launchctl print gui/$(id -u)/ai.coderabbit.arcade.booth` to see whether the login item is loaded. If it isn't, run the setup again with `--apply`. |
| macOS says the app can't be opened | Run `xattr -dr com.apple.quarantine "/Applications/Hoppy’s Adventure Arcade.app"`. |
| The game restarts every minute or two | If `watchdog.log` says the game "has not written a heartbeat", the build is older than the watchdog. Install a current build. |
| A controller does nothing | Reconnect it. Check **System Settings → Bluetooth** for wireless pads. |
| Black borders or the wrong size | Check the resolution in **System Settings → Displays**. |
| Notifications appear over the game | Turn on Do Not Disturb in **Control Center → Focus**. |
| Nothing helps | Restart the Mac. If the game still doesn't run, swap to the spare. |

## After the show

```sh
tools/booth/macos/setup.sh --undo           # see what it will change
tools/booth/macos/setup.sh --undo --apply
```

`--undo` puts back the settings the first setup recorded on that Mac. Then turn off automatic login and Do Not Disturb, and copy the session logs.
