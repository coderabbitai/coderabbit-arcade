"""Tests for macos/setup.sh. Run: python3 -m unittest discover -s tools/booth -v

Only the plan (the default, which changes nothing) and the argument checks run here; --apply
changes system settings, so these tests never pass it on a Mac.
"""
from __future__ import annotations

import os
import plistlib
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

    def test_undo_plan_removes_the_agent_and_restores_settings(self) -> None:
        result = self.setup("--undo")
        self.assertEqual(result.returncode, 0, result.stderr)
        for command in ("launchctl bootout gui/", "rm -f", "sudo pmset restoredefaults",
                        "defaults -currentHost delete com.apple.screensaver idleTime",
                        "defaults delete com.apple.CrashReporter DialogType"):
            self.assertIn(command, result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_the_installed_watchdog_comes_from_this_folder(self) -> None:
        out = self.setup("--app", str(self.app)).stdout
        line = next(line for line in out.splitlines() if line.startswith("  $ cp "))
        source = Path(line.split()[2])
        self.assertTrue(source.is_file(), source)
        self.assertEqual(source.resolve(), (SETUP.parent.parent / "watchdog.sh").resolve())

    def test_rejects_bad_usage(self) -> None:
        for args, message in ((["--route", "hub"], "--app is required"),
                              (["--bogus"], "unknown option"),
                              (["--app"], "needs a value")):
            result = self.setup(*args)
            self.assertEqual(result.returncode, 2, args)
            self.assertIn(message, result.stderr, args)

    @unittest.skipIf(sys.platform == "darwin", "--apply would change this Mac's settings")
    def test_apply_refuses_off_macos(self) -> None:
        result = self.setup("--app", str(self.app), "--apply")
        self.assertEqual(result.returncode, 2)
        self.assertIn("only runs on macOS", result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
