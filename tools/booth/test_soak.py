"""Tests for soak.py, run against a stand-in game. Run: python3 -m unittest discover -s tools/booth -v"""
from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import soak  # noqa: E402

# Records its arguments, then announces hub visits like the game, writing the visit number to a
# state file just before each announcement and holding it for longer than the wrapper's poll. The
# tests' memory sampler reads that file, so each hub visit gets a fixed memory value.
FAKE_GAME = r"""
import json, os, sys, time
mode, record, state = sys.argv[1], sys.argv[2], sys.argv[3]
with open(record, "w") as handle:
    json.dump(sys.argv[4:], handle)
with open(record + ".pid", "w") as handle:
    handle.write(str(os.getpid()))
def visit(n):
    with open(state, "w") as handle:
        handle.write(str(n))
    print(f"SOAK hub {n} at {n * 10.0:.1f} s", flush=True)
    time.sleep(0.6)
if mode == "hang":
    time.sleep(1000)
visits = 2 if mode == "short" else 3
for n in range(1, visits + 1):
    visit(n)
if mode != "silent":
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
        self.state = self.dir / "state"
        self.out = self.dir / "results"

    def sampler(self, by_visit: dict[int, float]):
        """Memory for the hub visit the fake game last announced (100 MB before the first)."""
        def sample(_pid: int) -> float:
            text = self.state.read_text() if self.state.exists() else ""
            return by_visit.get(int(text), 100.0) if text else 100.0
        return sample

    def run_soak(self, mode: str, *options: str, memory: dict[int, float] | None = None,
                 game_args: tuple[str, ...] = ("--", "--booth")) -> tuple[int, str, str]:
        argv = ["--minutes", "0.05", "--dwell", "2", "--out", str(self.out), "--rss-every", "0.1", *options,
                "--", sys.executable, str(self.fake), mode, str(self.args_file), str(self.state), *game_args]
        with redirect_stdout(io.StringIO()) as out, redirect_stderr(io.StringIO()) as err:
            code = soak.main(argv, sample=self.sampler(memory or {}))
        return code, out.getvalue(), err.getvalue()

    def run_folder(self) -> Path:
        folders = list(self.out.iterdir())
        self.assertEqual(len(folders), 1)
        return folders[0]

    def test_passes_the_soak_arguments_after_the_games_separator(self) -> None:
        code, out, _ = self.run_soak("steady", game_args=("--", "--booth", "--soak=999", "--soak-dwell=1"))
        self.assertEqual(code, 0, out)
        self.assertEqual(json.loads(self.args_file.read_text()),
                         ["--", "--booth", "--soak=0.05", "--soak-dwell=2", f"--soak-log={self.run_folder().resolve()}"],
                         "the wrapper's soak options replace any already in the command")
        self.assertIn("soak: passed", out)

    def test_adds_a_separator_when_the_game_has_none(self) -> None:
        self.run_soak("steady", game_args=())
        self.assertEqual(json.loads(self.args_file.read_text())[0], "--")

    def test_each_run_gets_its_own_folder(self) -> None:
        self.run_soak("steady")
        self.run_soak("steady")
        folders = sorted(self.out.iterdir())
        self.assertEqual(len(folders), 2)
        for folder in folders:
            self.assertTrue((folder / "game.log").is_file() and (folder / "rss.csv").is_file())

    def test_samples_resident_memory_with_ps(self) -> None:
        argv = ["--minutes", "0.05", "--out", str(self.out), "--rss-every", "0.1",
                "--", sys.executable, str(self.fake), "steady", str(self.args_file), str(self.state)]
        with redirect_stdout(io.StringIO()):
            soak.main(argv)  # the real sampler
        rows = (self.run_folder() / "rss.csv").read_text().splitlines()
        self.assertEqual(rows[0], "elapsed_s,rss_mb")
        self.assertGreaterEqual(len(rows), 4)
        self.assertTrue(all(float(row.split(",")[1]) > 0 for row in rows[1:]))

    def test_fails_when_memory_grows_between_hub_visits(self) -> None:
        code, out, err = self.run_soak("steady", "--max-rss-growth", "20", memory={1: 100.0, 2: 100.0, 3: 300.0})
        self.assertEqual(code, 1, out + err)
        self.assertIn("hub visits 2 -> 3", out)
        self.assertIn("resident memory kept growing", err)

    def test_growth_before_the_second_hub_visit_is_warm_up(self) -> None:
        code, out, err = self.run_soak("steady", "--max-rss-growth", "20", memory={1: 50.0, 2: 300.0, 3: 305.0})
        self.assertEqual(code, 0, out + err)
        self.assertIn("soak: passed", out)

    def test_needs_three_hub_visits_to_judge_memory(self) -> None:
        code, out, _ = self.run_soak("short", "--max-rss-growth", "20", memory={1: 100.0, 2: 900.0})
        self.assertEqual(code, 0)
        self.assertIn("needs 3 to judge", out)

    def test_fails_when_the_game_reports_growth(self) -> None:
        code, _, err = self.run_soak("leaky")
        self.assertEqual(code, 1)
        self.assertIn("exited with status 1", err)

    def test_fails_when_the_game_never_gives_a_verdict(self) -> None:
        code, _, err = self.run_soak("silent")
        self.assertEqual(code, 1)
        self.assertIn("without a soak verdict", err)

    def test_stops_a_game_that_outlasts_its_time(self) -> None:
        code, _, err = self.run_soak("hang", "--grace", "0.02")
        self.assertEqual(code, 2)
        self.assertIn("was stopped", err)

    def test_reaps_the_game_when_monitoring_fails(self) -> None:
        pid_file = Path(f"{self.args_file}.pid")

        def broken(_pid: int) -> float:
            if not pid_file.exists():
                return 100.0  # break only once the game is up and has said who it is
            raise RuntimeError("sampler broke")
        argv = ["--minutes", "0.05", "--out", str(self.out), "--rss-every", "0.1",
                "--", sys.executable, str(self.fake), "hang", str(self.args_file), str(self.state)]
        with redirect_stdout(io.StringIO()), self.assertRaises(RuntimeError):
            soak.main(argv, sample=broken)
        pid = int(pid_file.read_text())
        with self.assertRaises(ProcessLookupError, msg="the hanging game was killed and reaped"):
            os.kill(pid, 0)

    def test_godot_mode_runs_this_checkouts_project(self) -> None:
        args = soak.argparse.Namespace(godot="/opt/godot", command=[], minutes=480.0, dwell=30.0)
        self.assertEqual(soak.game_command(args, Path("out")),
                         ["/opt/godot", "--path", str(soak.PROJECT), "--", "--soak=480", "--soak-dwell=30",
                          f"--soak-log={Path('out').resolve()}"])

    def test_rss_verdict(self) -> None:
        self.assertFalse(soak.rss_verdict({1: 100.0, 2: 100.0}, 25)[1])
        self.assertFalse(soak.rss_verdict({1: 50.0, 2: 300.0, 3: 310.0}, 25)[1])
        message, grew = soak.rss_verdict({1: 100.0, 2: 100.0, 3: 120.0, 4: 200.0}, 25)
        self.assertTrue(grew)
        self.assertIn("hub visits 2 -> 4", message)
        self.assertIn("needs 3", soak.rss_verdict({1: 100.0, 3: 100.0, 4: 100.0}, 25)[0])

    def test_rejects_bad_usage(self) -> None:
        for argv in (["--minutes", "1"], ["--minutes", "0", "--", "game"],
                     ["--minutes", "1", "--godot", "g", "--", "game"],
                     ["--minutes", "inf", "--", "game"], ["--minutes", "1", "--grace", "nan", "--", "game"],
                     ["--minutes", "1", "--max-rss-growth", "-5", "--", "game"]):
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as stop:
                soak.main(argv)
            self.assertEqual(stop.exception.code, 2, argv)
        self.assertFalse(self.out.exists(), "a refused run creates no folder")

    def test_missing_game_is_an_error(self) -> None:
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as err:
            code = soak.main(["--minutes", "0.05", "--out", str(self.out), "--", str(self.dir / "nope")])
        self.assertEqual(code, 2)
        self.assertIn("cannot start the game", err.getvalue())


if __name__ == "__main__":
    unittest.main()
