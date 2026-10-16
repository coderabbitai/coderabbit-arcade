"""Tests for watchdog.sh, run against a stand-in game. Run: python3 -m unittest discover -s tools/booth -v

Each test starts the real script under bash with short timings and a fake game that exits, hangs
or stays healthy, then checks what the watchdog did. The waits are generous for slow CI runners;
the assertions count launches with lower bounds.
"""
from __future__ import annotations

import os
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

WATCHDOG = Path(__file__).resolve().parent / "watchdog.sh"

# Records each launch's arguments and pid, then behaves as FAKE_MODE says.
FAKE_GAME = r"""#!/usr/bin/env bash
echo "$*" >> "$FAKE_RUNS"
echo $$ > "$FAKE_PID"
heartbeat=""
for arg in "$@"; do  # the first non-empty one, as AppRouter.heartbeat_path() reads it
  case "$arg" in --heartbeat=?*) [ -n "$heartbeat" ] || heartbeat="${arg#--heartbeat=}" ;; esac
done
beat() {  # write and rename, as the game does, so the watchdog never reads a half-written number
  [ -z "$heartbeat" ] || { date +%s > "$heartbeat.tmp" && mv -f "$heartbeat.tmp" "$heartbeat"; }
}
case "$FAKE_MODE" in
  exit) exit 3 ;;
  hang) beat; exec sleep 1000 ;;
  healthy) while :; do beat; sleep 0.2; done ;;
esac
"""


class WatchdogTest(unittest.TestCase):
    def setUp(self) -> None:
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.dir = Path(folder.name)
        self.game = self.dir / "fake-game"
        self.game.write_text(FAKE_GAME, encoding="utf-8")
        self.game.chmod(0o755)
        self.runs = self.dir / "runs"
        self.pid = self.dir / "pid"
        self.log = self.dir / "watchdog.log"
        self.heartbeat = self.dir / "beat" / "heartbeat"
        self.process: subprocess.Popen[bytes] | None = None

    def tearDown(self) -> None:
        if self.process and self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        if self.pid.exists():
            try:
                os.kill(int(self.pid.read_text()), signal.SIGKILL)
            except (ProcessLookupError, ValueError):
                pass

    def start(self, mode: str, *options: str, game_args: tuple[str, ...] = ("--", "--booth"),
              heartbeat: bool = True) -> None:
        env = dict(os.environ, FAKE_RUNS=str(self.runs), FAKE_PID=str(self.pid), FAKE_MODE=mode, TMPDIR=str(self.dir))
        own = ["--heartbeat", str(self.heartbeat)] if heartbeat else []
        command = ["bash", str(WATCHDOG), "--log", str(self.log), *own,
                   "--poll", "0.2", *options, "--", str(self.game), *game_args]
        # The watchdog writes its events to --log; the fake game's own output is discarded.
        self.process = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def stop(self) -> int:
        assert self.process is not None
        self.process.send_signal(signal.SIGTERM)
        return self.process.wait(timeout=20)

    def launches(self) -> list[str]:
        return self.runs.read_text(encoding="utf-8").splitlines() if self.runs.exists() else []

    def events(self) -> str:
        return self.log.read_text(encoding="utf-8") if self.log.exists() else ""

    def wait_for(self, condition, seconds: float) -> bool:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if condition():
                return True
            time.sleep(0.1)
        return condition()

    def test_relaunches_a_game_that_exits(self) -> None:
        self.start("exit", "--hang", "0", "--backoff", "1", "--max-backoff", "1")
        self.assertTrue(self.wait_for(lambda: len(self.launches()) >= 3, 15), self.events())
        self.assertEqual(self.stop(), 0)
        self.assertIn("the game exited after", self.events())
        self.assertIn("(status 3)", self.events())
        self.assertIn("relaunching in 1 s", self.events())

    def test_waits_longer_after_each_quick_exit(self) -> None:
        self.start("exit", "--hang", "0", "--backoff", "1", "--max-backoff", "2")
        self.assertTrue(self.wait_for(lambda: "relaunching in 2 s" in self.events(), 15), self.events())
        self.assertTrue(self.wait_for(lambda: self.events().count("relaunching in 2 s") >= 2, 15), self.events())
        self.stop()
        self.assertNotIn("relaunching in 4 s", self.events(), "the wait is capped at --max-backoff")

    def test_restarts_a_hung_game(self) -> None:
        self.start("hang", "--hang", "1", "--grace", "0", "--backoff", "1", "--term-wait", "2")
        self.assertTrue(self.wait_for(lambda: len(self.launches()) >= 2, 20), self.events())
        self.stop()
        self.assertIn("has not written a heartbeat for", self.events())
        self.assertIn("(signal 15)", self.events())

    def test_leaves_a_healthy_game_alone_and_stops_it_on_sigterm(self) -> None:
        self.start("healthy", "--hang", "2", "--grace", "0")
        time.sleep(5)
        self.assertEqual(len(self.launches()), 1, self.events())
        game = int(self.pid.read_text())
        self.assertEqual(self.stop(), 0)
        self.assertIn("stopping the game", self.events())
        with self.assertRaises(ProcessLookupError):
            os.kill(game, 0)

    def test_gives_the_game_its_heartbeat_after_the_separator(self) -> None:
        self.start("exit", "--backoff", "1")
        self.assertTrue(self.wait_for(lambda: self.launches(), 10))
        self.stop()
        self.assertEqual(self.launches()[0], f"-- --booth --heartbeat={self.heartbeat}")

    def test_adds_a_separator_when_the_game_has_none(self) -> None:
        self.start("exit", "--backoff", "1", game_args=())
        self.assertTrue(self.wait_for(lambda: self.launches(), 10))
        self.stop()
        self.assertEqual(self.launches()[0], f"-- --heartbeat={self.heartbeat}")

    def test_hang_zero_passes_no_heartbeat(self) -> None:
        self.start("exit", "--hang", "0", "--backoff", "1")
        self.assertTrue(self.wait_for(lambda: self.launches(), 10))
        self.stop()
        self.assertEqual(self.launches()[0], "-- --booth")

    def test_stop_file_ends_the_watch_when_the_game_exits(self) -> None:
        stop_file = self.dir / "stop"
        stop_file.write_text("left from yesterday", encoding="utf-8")
        self.start("healthy", "--hang", "0", "--stop-file", str(stop_file))
        self.assertTrue(self.wait_for(lambda: self.launches(), 10))
        self.assertIn("removed the stop file left from before", self.events())
        self.assertFalse(stop_file.exists())
        stop_file.touch()
        os.kill(int(self.pid.read_text()), signal.SIGTERM)  # staff close the game
        assert self.process is not None
        self.assertEqual(self.process.wait(timeout=10), 0)
        self.assertIn("not relaunching", self.events())
        self.assertEqual(len(self.launches()), 1)

    def test_default_heartbeat_is_private_to_each_watchdog(self) -> None:
        self.start("healthy", "--hang", "2", "--grace", "0", heartbeat=False)
        self.assertTrue(self.wait_for(lambda: self.launches(), 10))
        path = Path(self.launches()[0].split("--heartbeat=")[1])
        self.assertEqual(path.parent.parent.resolve(), self.dir.resolve())
        self.assertTrue(path.parent.name.startswith("hoppy-booth."))
        self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
        time.sleep(3)
        self.assertEqual(len(self.launches()), 1, "a healthy game on the private heartbeat is left alone")
        self.stop()
        self.assertFalse(path.parent.exists(), "the private folder goes when the watchdog stops")

    def test_rejects_a_game_command_that_sets_its_own_heartbeat(self) -> None:
        result = subprocess.run(["bash", str(WATCHDOG), "--", "game", "--", "--heartbeat=/elsewhere"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn("passes its own --heartbeat", result.stderr)

    def test_reads_numbers_with_leading_zeros_as_decimal(self) -> None:
        self.start("exit", "--hang", "0", "--backoff", "01", "--max-backoff", "08")
        self.assertTrue(self.wait_for(lambda: "relaunching in 2 s" in self.events(), 15), self.events())
        self.stop()
        self.assertNotIn("value too great", self.events())

    def test_rejects_bad_usage(self) -> None:
        for args, message in (
            ([], "no game command"),
            (["--bogus", "--", "true"], "unknown option"),
            (["--hang", "soon", "--", "true"], "whole number"),
            (["--backoff", "0", "--", "true"], "at least 1"),
            (["--poll", "0", "--", "true"], "more than 0"),
            (["--log"], "needs a value"),
        ):
            result = subprocess.run(["bash", str(WATCHDOG), *args], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2, args)
            self.assertIn(message, result.stderr, args)

    def test_help_prints_the_usage(self) -> None:
        result = subprocess.run(["bash", str(WATCHDOG), "--help"], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout)
        self.assertIn("--stop-file", result.stdout)


if __name__ == "__main__":
    unittest.main()
