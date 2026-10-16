"""Tests for soak.py, run against a stand-in game. Run: python3 -m unittest discover -s tools/booth -v"""
from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import soak  # noqa: E402

# Records its arguments, announces passes over the routes like the game, then behaves as its first
# argument says. "grow" and "warmup" add 8 MB at a time, touched so it counts as resident memory.
FAKE_GAME = r"""
import json, sys, time
mode = sys.argv[1]
with open(sys.argv[2], "w") as record:
    json.dump(sys.argv[3:], record)
hold = []
def grow(blocks):
    for _ in range(blocks):
        hold.append(bytearray(8 * 1024 * 1024))
        hold[-1][::4096] = b"x" * len(hold[-1][::4096])
        time.sleep(0.05)
if mode == "hang":
    time.sleep(1000)
print("SOAK cycle 1 at 0.0 s", flush=True)
if mode == "short":
    grow(12)
    time.sleep(0.6)
    sys.exit(0)
grow(12 if mode == "warmup" else 0)  # loading everything once is not a leak
time.sleep(0.4)
print("SOAK cycle 2 at 30.0 s", flush=True)
time.sleep(0.4)
print("SOAK cycle 3 at 60.0", end="", flush=True)  # a line split across reads
time.sleep(0.3)
print(" s", flush=True)
grow(12 if mode == "grow" else 0)
time.sleep(0.6)
print("SOAK verdict: steady", flush=True)
sys.exit(1 if mode == "leaky" else 0)
"""


class SoakTest(unittest.TestCase):
    def setUp(self) -> None:
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.dir = Path(folder.name)
        self.fake = self.dir / "fake_game.py"
        self.fake.write_text(FAKE_GAME, encoding="utf-8")
        self.args_file = self.dir / "args.json"
        self.out = self.dir / "results"

    def run_soak(self, mode: str, *options: str, game_args: tuple[str, ...] = ("--", "--booth")) -> tuple[int, str, str]:
        argv = ["--minutes", "0.05", "--dwell", "2", "--out", str(self.out), "--rss-every", "0.1", *options,
                "--", sys.executable, str(self.fake), mode, str(self.args_file), *game_args]
        with redirect_stdout(io.StringIO()) as out, redirect_stderr(io.StringIO()) as err:
            code = soak.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_passes_the_soak_arguments_after_the_games_separator(self) -> None:
        code, out, _ = self.run_soak("steady")
        self.assertEqual(code, 0, out)
        self.assertEqual(json.loads(self.args_file.read_text()),
                         ["--", "--booth", "--soak=0.05", "--soak-dwell=2", f"--soak-log={self.out.resolve()}"])
        self.assertIn("SOAK verdict: steady", out)
        self.assertIn("soak: passed", out)

    def test_adds_a_separator_when_the_game_has_none(self) -> None:
        self.run_soak("steady", game_args=())
        self.assertEqual(json.loads(self.args_file.read_text())[0], "--")

    def test_samples_resident_memory(self) -> None:
        self.run_soak("steady")
        rows = (self.out / "rss.csv").read_text().splitlines()
        self.assertEqual(rows[0], "elapsed_s,rss_mb")
        self.assertGreaterEqual(len(rows), 4)
        self.assertTrue(all(float(row.split(",")[1]) > 0 for row in rows[1:]))
        self.assertIn("SOAK verdict: steady", (self.out / "game.log").read_text())

    def test_fails_when_resident_memory_keeps_growing(self) -> None:
        code, out, err = self.run_soak("grow", "--max-rss-growth", "20")
        self.assertEqual(code, 1, out + err)
        self.assertIn("resident memory kept growing", err)

    def test_growth_during_the_first_pass_is_warm_up(self) -> None:
        code, out, err = self.run_soak("warmup", "--max-rss-growth", "20")
        self.assertEqual(code, 0, out + err)
        self.assertIn("soak: passed", out)

    def test_needs_three_passes_to_judge_memory(self) -> None:
        code, out, _ = self.run_soak("short", "--max-rss-growth", "20")
        self.assertEqual(code, 0)
        self.assertIn("needs 3 to judge", out)

    def test_fails_when_the_game_reports_growth(self) -> None:
        code, _, err = self.run_soak("leaky")
        self.assertEqual(code, 1)
        self.assertIn("exited with status 1", err)

    def test_stops_a_game_that_outlasts_its_time(self) -> None:
        code, _, err = self.run_soak("hang", "--grace", "0.02")
        self.assertEqual(code, 2)
        self.assertIn("was stopped", err)

    def test_godot_mode_runs_this_checkouts_project(self) -> None:
        args = soak.argparse.Namespace(godot="/opt/godot", command=[], minutes=480.0, dwell=30.0)
        self.assertEqual(soak.game_command(args, Path("out")),
                         ["/opt/godot", "--path", str(soak.PROJECT), "--", "--soak=480", "--soak-dwell=30",
                          f"--soak-log={Path('out').resolve()}"])

    def test_rss_verdict(self) -> None:
        passes = {1: 0.0, 2: 100.0, 3: 200.0}
        self.assertFalse(soak.rss_verdict([(0, 100.0)], {1: 0.0, 2: 100.0}, 25)[1])
        warmup_then_steady = [(t, 100.0 if t < 100 else 300.0 + t / 100) for t in range(0, 400, 40)]
        self.assertFalse(soak.rss_verdict(warmup_then_steady, passes, 25)[1])
        growing = [(t, 100.0 + t) for t in range(0, 400, 40)]
        message, grew = soak.rss_verdict(growing, passes, 25)
        self.assertTrue(grew)
        self.assertIn("limit 25%", message)
        self.assertIn("too few", soak.rss_verdict([(10, 100.0), (150, 120.0)], passes, 25)[0])

    def test_rejects_bad_usage(self) -> None:
        for argv in (["--minutes", "1"], ["--minutes", "0", "--", "game"],
                     ["--minutes", "1", "--godot", "g", "--", "game"]):
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as stop:
                soak.main(argv)
            self.assertEqual(stop.exception.code, 2, argv)

    def test_missing_game_is_an_error(self) -> None:
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as err:
            code = soak.main(["--minutes", "0.05", "--out", str(self.out), "--", str(self.dir / "nope")])
        self.assertEqual(code, 2)
        self.assertIn("cannot start the game", err.getvalue())


if __name__ == "__main__":
    unittest.main()
