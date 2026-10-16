"""Tests for macos/setup.sh. Run: python3 -m unittest discover -s tools/booth -v

The plan (the default, which changes nothing) and the argument checks run everywhere. The --apply
tests replace every command that changes settings (sudo, pmset, defaults, launchctl, xattr) and
uname with logging stand-ins, and still run only off macOS, so a missed stand-in can never change
a real Mac.
"""
from __future__ import annotations

import os
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SETUP = Path(__file__).resolve().parent / "macos" / "setup.sh"
INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleExecutable</key>
\t<string>Fake Arcade</string>
</dict>
</plist>
"""


# Stand-ins: each logs its arguments. `defaults` keeps values as files under $STUB_STORE and fails
# writes to a key named in $STUB_FAIL; `pmset -g` reports fixed power settings.
STUBS = {
    "uname": 'echo Darwin',
    "sudo": '[ "$1" = -v ] && exit 0; exec "$@"',
    "launchctl": 'echo "launchctl $*" >> "$STUB_LOG"',
    "xattr": 'echo "xattr $*" >> "$STUB_LOG"',
    "pmset": """echo "pmset $*" >> "$STUB_LOG"
if [ "$1" = -g ]; then printf ' sleep                10\n displaysleep         5\n autorestart          0\n'; fi""",
    "defaults": """echo "defaults $*" >> "$STUB_LOG"
host=""; [ "$1" = -currentHost ] && { host="host-"; shift; }
verb="$1"; key_file="$STUB_STORE/$host$(printf '%s' "$2" | tr '/' '_')-$3"
case "$verb" in
  read) [ -f "$key_file" ] && cut -d' ' -f2- "$key_file" ;;
  read-type) [ -f "$key_file" ] && echo "Type is $(cut -d' ' -f1 "$key_file")" ;;
  write) [ "$3" = "${STUB_FAIL:-}" ] && exit 1; echo "$4 $5" > "$key_file" ;;
  delete) [ -f "$key_file" ] && rm "$key_file" ;;
esac""",
}


class MacSetupTest(unittest.TestCase):
    def setUp(self) -> None:
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.dir = Path(folder.name)
        self.home = self.dir / "home"
        self.home.mkdir()
        self.app = self.dir / "Fake & Co’s Arcade.app"
        (self.app / "Contents" / "MacOS").mkdir(parents=True)
        (self.app / "Contents" / "Info.plist").write_text(INFO_PLIST, encoding="utf-8")

    def setup(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = dict(os.environ, HOME=str(self.home))
        return subprocess.run(["bash", str(SETUP), *args], capture_output=True, text=True, env=env, timeout=30)

    def agent(self, output: str) -> dict:
        """The LaunchAgent the plan would write."""
        lines = output.splitlines()
        start = lines.index("  would write:") + 1
        end = next(i for i in range(start, len(lines)) if lines[i].startswith("  $ launchctl bootstrap"))
        return plistlib.loads("\n".join(line[4:] for line in lines[start:end]).encode("utf-8"))

    def test_plan_lists_every_change_and_touches_nothing(self) -> None:
        result = self.setup("--app", str(self.app), "--route", "heroes_vs_villains")
        self.assertEqual(result.returncode, 0, result.stderr)
        out = result.stdout
        self.assertTrue(out.startswith("Plan only: nothing will change."))
        for command in ("sudo pmset -a sleep 0 displaysleep 0 disksleep 0 powernap 0",
                        "sudo pmset -a autorestart 1",
                        "defaults -currentHost write com.apple.screensaver idleTime -int 0",
                        "AutomaticallyInstallMacOSUpdates -bool false",
                        "defaults write com.apple.CrashReporter DialogType -string none",
                        f'xattr -dr com.apple.quarantine "{self.app}"',
                        "launchctl bootstrap gui/"):
            self.assertIn(command, out)
        self.assertIn("Automatically log in as", out)
        self.assertEqual(list(self.home.iterdir()), [], "the plan must not write anything")

    def test_agent_runs_the_watchdog_and_the_game_in_booth_mode(self) -> None:
        agent = self.agent(self.setup("--app", str(self.app), "--route", "heroes_vs_villains").stdout)
        support = f"{self.home}/Library/Application Support/HoppyBooth"
        self.assertEqual(agent["Label"], "ai.coderabbit.arcade.booth")
        self.assertEqual(agent["ProgramArguments"], [
            "/bin/bash", f"{support}/watchdog.sh",
            "--log", f"{self.home}/Library/Logs/HoppyBooth/watchdog.log",
            "--heartbeat", f"{support}/heartbeat",
            "--stop-file", f"{support}/stop",
            "--", f"{self.app}/Contents/MacOS/Fake Arcade", "--", "--booth", "--route=heroes_vs_villains",
        ])
        self.assertTrue(agent["RunAtLoad"])
        self.assertEqual(agent["KeepAlive"], {"SuccessfulExit": False})
        self.assertEqual(agent["LimitLoadToSessionType"], "Aqua")

    def test_route_is_optional(self) -> None:
        agent = self.agent(self.setup("--app", str(self.app)).stdout)
        self.assertEqual(agent["ProgramArguments"][-2:], ["--", "--booth"])

    def test_unreadable_app_gets_a_placeholder_in_the_plan(self) -> None:
        result = self.setup("--app", str(self.dir / "Missing.app"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("placeholder", result.stdout)
        self.assertIn(f"{self.dir}/Missing.app/Contents/MacOS/<executable>", self.agent(result.stdout)["ProgramArguments"])

    def test_undo_without_a_record_changes_no_setting(self) -> None:
        result = self.setup("--undo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("launchctl bootout gui/", result.stdout)
        self.assertIn("No record of this Mac's settings before setup", result.stdout)
        self.assertNotIn("pmset", result.stdout.split("No record")[0])
        self.assertNotIn("restoredefaults", result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_undo_plan_restores_the_recorded_settings(self) -> None:
        record = self.home / "Library" / "Application Support" / "HoppyBooth" / "settings-before.tsv"
        record.parent.mkdir(parents=True)
        record.write_text("defaults\thost\tcom.apple.screensaver\tidleTime\tint\t300\n"
                          "defaults\tsystem\t/Library/Preferences/com.apple.SoftwareUpdate\tAutomaticDownload\tbool\t1\n"
                          "defaults\tuser\tcom.apple.CrashReporter\tDialogType\tabsent\t\n"
                          "pmset\tsleep\t10\n", encoding="utf-8")
        out = self.setup("--undo").stdout
        for command in ("defaults -currentHost write com.apple.screensaver idleTime -int 300",
                        "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true",
                        "defaults delete com.apple.CrashReporter DialogType", "sudo pmset -a sleep 10"):
            self.assertIn(command, out)
        self.assertTrue(record.exists(), "the plan must leave the record alone")

    def test_a_relative_app_becomes_an_absolute_path_for_launchd(self) -> None:
        env = dict(os.environ, HOME=str(self.home))
        result = subprocess.run(["bash", str(SETUP), "--app", self.app.name], capture_output=True, text=True,
                                env=env, cwd=self.dir, timeout=30)
        executable = self.agent(result.stdout)["ProgramArguments"][-3]
        self.assertEqual(Path(executable), self.app.resolve() / "Contents" / "MacOS" / "Fake Arcade")

    def test_the_installed_watchdog_comes_from_this_folder(self) -> None:
        out = self.setup("--app", str(self.app)).stdout
        line = next(line for line in out.splitlines() if line.startswith("  $ cp "))
        source = Path(shlex.split(line)[2])
        self.assertTrue(source.is_file(), source)
        self.assertEqual(source.resolve(), (SETUP.parent.parent / "watchdog.sh").resolve())

    def test_rejects_bad_usage(self) -> None:
        for args, message in ((["--route", "hub"], "--app is required"),
                              (["--bogus"], "unknown option"),
                              (["--app"], "needs a value")):
            result = self.setup(*args)
            self.assertEqual(result.returncode, 2, args)
            self.assertIn(message, result.stderr, args)

    def stubbed(self, *args: str, fail: str = "") -> tuple[subprocess.CompletedProcess[str], list[str]]:
        """Run setup.sh with the stand-ins first on PATH; return the result and the commands they saw."""
        stubs, store, log = self.dir / "stubs", self.dir / "store", self.dir / "stub.log"
        if not stubs.exists():
            stubs.mkdir()
            store.mkdir()
            for name, body in STUBS.items():
                (stubs / name).write_text(f"#!/usr/bin/env bash\n{body}\n", encoding="utf-8")
                (stubs / name).chmod(0o755)
            (self.app / "Contents" / "MacOS" / "Fake Arcade").write_text("", encoding="utf-8")
            (self.app / "Contents" / "MacOS" / "Fake Arcade").chmod(0o755)
        path = f"{stubs}{os.pathsep}{os.environ['PATH']}"
        for name in STUBS:
            self.assertEqual(shutil.which(name, path=path), str(stubs / name), f"{name} must be a stand-in")
        log.write_text("", encoding="utf-8")
        env = dict(os.environ, HOME=str(self.home), PATH=path, STUB_STORE=str(store), STUB_LOG=str(log),
                   STUB_FAIL=fail)
        result = subprocess.run(["bash", str(SETUP), *args], capture_output=True, text=True, env=env, timeout=60)
        return result, log.read_text(encoding="utf-8").splitlines()

    @unittest.skipIf(sys.platform == "darwin", "stand-ins only: never run --apply on a Mac")
    def test_apply_records_settings_and_undo_puts_them_back(self) -> None:
        store = self.dir / "store"
        result, _ = self.stubbed("--app", str(self.app), "--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        agent = self.home / "Library" / "LaunchAgents" / "ai.coderabbit.arcade.booth.plist"
        record = self.home / "Library" / "Application Support" / "HoppyBooth" / "settings-before.tsv"
        self.assertTrue(agent.is_file())
        rows = [line.split("\t") for line in record.read_text(encoding="utf-8").splitlines()]
        self.assertIn(["defaults", "host", "com.apple.screensaver", "idleTime", "absent", ""], rows)
        self.assertIn(["pmset", "sleep", "10"], rows)
        self.assertEqual((store / "host-com.apple.screensaver-idleTime").read_text().split(), ["-int", "0"])

        result, seen = self.stubbed("--undo", "--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("defaults -currentHost delete com.apple.screensaver idleTime", seen)
        self.assertIn("pmset -a sleep 10", seen)
        self.assertNotIn("pmset restoredefaults", " ".join(seen))
        self.assertFalse(agent.exists())
        self.assertFalse(record.exists(), "a complete undo removes the record")
        self.assertEqual(list(store.iterdir()), [], "every preference setup added is gone again")

    @unittest.skipIf(sys.platform == "darwin", "stand-ins only: never run --apply on a Mac")
    def test_undo_restores_a_value_that_was_there_before(self) -> None:
        store = self.dir / "store"
        self.stubbed("--undo")  # creates the stand-ins and the store
        (store / "host-com.apple.screensaver-idleTime").write_text("integer 300\n", encoding="utf-8")
        self.stubbed("--app", str(self.app), "--apply")
        _, seen = self.stubbed("--undo", "--apply")
        self.assertIn("defaults -currentHost write com.apple.screensaver idleTime -int 300", seen)

    @unittest.skipIf(sys.platform == "darwin", "stand-ins only: never run --apply on a Mac")
    def test_undo_without_a_record_fails_and_changes_nothing(self) -> None:
        result, seen = self.stubbed("--undo", "--apply")
        self.assertEqual(result.returncode, 1)
        self.assertIn("restoring by hand", result.stdout)
        self.assertFalse([command for command in seen if command.startswith(("defaults", "pmset"))])

    @unittest.skipIf(sys.platform == "darwin", "stand-ins only: never run --apply on a Mac")
    def test_a_failed_restore_fails_the_undo(self) -> None:
        self.stubbed("--app", str(self.app), "--apply")
        (self.dir / "store" / "host-com.apple.screensaver-idleTime").unlink()
        record = self.home / "Library" / "Application Support" / "HoppyBooth" / "settings-before.tsv"
        record.write_text("defaults\tuser\tcom.apple.CrashReporter\tDialogType\tstring\tbasic\n", encoding="utf-8")
        result, _ = self.stubbed("--undo", "--apply", fail="DialogType")
        self.assertEqual(result.returncode, 1)
        self.assertIn("1 step(s) failed", result.stdout)
        self.assertTrue(record.exists(), "a failed undo keeps the record for another try")

    @unittest.skipIf(sys.platform == "darwin", "--apply would change this Mac's settings")
    def test_apply_refuses_off_macos(self) -> None:
        result = self.setup("--app", str(self.app), "--apply")
        self.assertEqual(result.returncode, 2)
        self.assertIn("only runs on macOS", result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
