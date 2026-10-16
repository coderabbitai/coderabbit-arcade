"""Unit tests for sessions_report.py. Run: python3 -m unittest discover -s tools/booth -v"""
from __future__ import annotations

import csv
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sessions_report  # noqa: E402

LAUNCH = "2026-11-30T09:58:12"


def event(kind: str, **fields: object) -> str:
    return json.dumps({"event": kind, "launch": LAUNCH, **fields})


def start(session: int, game: str, time: str) -> str:
    return event("start", session=session, game=game, time=time)


def end(session: int, game: str, time: str, duration: float, ended_by: str, retries: int = 0, game_overs: int = 0) -> str:
    return event("end", session=session, game=game, time=time, duration_s=duration, ended_by=ended_by, retries=retries,
                 game_overs=game_overs)


class SessionsReportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)

    def write(self, name: str, lines: list[str]) -> Path:
        path = Path(self.folder.name) / name
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    def sample(self) -> Path:
        return self.write("booth.jsonl", [
            event("launch", time=LAUNCH, version="0.1.0"),
            start(1, "heroes_vs_villains", "2026-11-30T10:02:03"),
            end(1, "heroes_vs_villains", "2026-11-30T10:04:26", 143.2, "idle"),
            start(2, "heroes_vs_villains", "2026-11-30T10:05:00"),
            end(2, "heroes_vs_villains", "2026-11-30T10:08:00", 180.0, "menu", retries=2, game_overs=3),
            start(3, "runner_game", "2026-11-30T11:00:00"),
            end(3, "runner_game", "2026-11-30T11:01:00", 60.0, "quit"),
            start(4, "code_city_brawl", "2026-11-30T11:30:00"),
            start(5, "code_city_brawl", "2026-11-30T11:45:00"),
            end(5, "code_city_brawl", "2026-11-30T11:46:30", 90.0, "menu"),
        ])

    def test_pairs_starts_and_ends_and_keeps_unfinished_sessions(self) -> None:
        log = sessions_report.read([self.sample()])
        self.assertEqual(log.launches, 1)
        self.assertEqual([s.game for s in log.sessions],
                         ["heroes_vs_villains", "heroes_vs_villains", "runner_game", "code_city_brawl", "code_city_brawl"])
        self.assertEqual(log.sessions[1].retries, 2)
        self.assertEqual(log.sessions[0].ended_by, "idle")
        self.assertIsNone(log.sessions[3].duration_s, "a start without an end is unfinished")
        self.assertEqual(log.skipped, [])

    def test_summary_reports_games_reasons_and_hours(self) -> None:
        text = sessions_report.summary(sessions_report.read([self.sample()]))
        self.assertIn("Sessions: 5 (4 finished, 1 unfinished)", text)
        rows = {line.split()[0]: line.split() for line in text.splitlines() if line.split() and "_" in line.split()[0]}
        # Two sessions: 143.2 s and 180 s. Median and mean 161.6 s; P90 interpolates to 176.3 s.
        self.assertEqual(rows["heroes_vs_villains"], ["heroes_vs_villains", "2", "0", "2:42", "2:42", "2:56", "2", "3"])
        # One finished (90 s) and one unfinished visit: both count, the lengths come from the finished one.
        self.assertEqual(rows["code_city_brawl"], ["code_city_brawl", "2", "1", "1:30", "1:30", "1:30", "0", "0"])
        self.assertIn("Ended by: idle 1, menu 2, quit 1", text)
        self.assertIn("Starts by hour: 10:00 2, 11:00 3", text)

    def test_a_game_with_only_unfinished_sessions_is_listed(self) -> None:
        path = self.write("crash.jsonl", [start(1, "orbital_ops", "2026-11-30T10:00:00")])
        rows = [line.split() for line in sessions_report.summary(sessions_report.read([path])).splitlines()]
        self.assertIn(["orbital_ops", "1", "1", "-", "-", "-", "0", "0"], rows)

    def test_same_launch_in_two_files_stays_separate(self) -> None:
        first = self.write("a.jsonl", [start(1, "runner_game", "2026-11-30T10:00:00"), end(1, "runner_game", "2026-11-30T10:01:00", 60, "menu")])
        second = self.write("b.jsonl", [start(1, "orbital_ops", "2026-11-30T10:00:30")])
        log = sessions_report.read([first, second])
        self.assertEqual([(s.game, s.duration_s) for s in log.sessions], [("runner_game", 60.0), ("orbital_ops", None)])

    def test_bad_lines_are_skipped_and_named(self) -> None:
        path = self.write("bad.jsonl", [
            "not json",
            json.dumps({"event": "start", "launch": LAUNCH}),
            end(9, "runner_game", "2026-11-30T10:01:00", 60, "menu"),
            event("mystery"),
            "",
            start(1, "runner_game", "2026-11-30T10:00:00"),
        ])
        log = sessions_report.read([path])
        self.assertEqual(len(log.sessions), 1)
        self.assertEqual(len(log.skipped), 4)
        self.assertIn("bad.jsonl:3: end without a start", log.skipped[2])
        self.assertIn("Skipped 4 line(s):", sessions_report.summary(log))

    def test_a_rejected_end_leaves_its_session_unfinished(self) -> None:
        path = self.write("rejected.jsonl", [
            start(1, "runner_game", "2026-11-30T10:00:00"),
            end(1, "runner_game", "2026-11-30T10:01:00", "soon", "menu"),  # type: ignore[arg-type]
            event("end", session=1, game="runner_game", time="2026-11-30T10:01:00", duration_s=float("nan"), ended_by="menu"),
            event("end", session=1, game="runner_game", time="2026-11-30T10:01:00", duration_s=1e400, ended_by="menu"),
            event("end", session=1, game="runner_game", time="2026-11-30T10:01:00", duration_s=-5, ended_by="menu"),
            end(1, "orbital_ops", "2026-11-30T10:01:00", 60.0, "menu"),
            event("end", session=1, game="runner_game", time=None, duration_s=60.0, ended_by="menu"),
            event("end", session=1, game="runner_game", time="2026-11-30T10:01:00", duration_s=60.0, ended_by=None),
            event("end", session=1, time="2026-11-30T10:01:00", duration_s=60.0, ended_by="menu"),
        ])
        log = sessions_report.read([path])
        session = log.sessions[0]
        self.assertEqual((session.end, session.duration_s, session.ended_by, session.retries), ("", None, "", 0))
        self.assertEqual(len(log.skipped), 8)
        self.assertIn("closes a 'runner_game' session", log.skipped[4])
        self.assertIn("Sessions: 1 (0 finished, 1 unfinished)", sessions_report.summary(log))

    def test_reads_every_run_file_in_a_folder(self) -> None:
        folder = Path(self.folder.name) / "booth"
        folder.mkdir()
        (folder / "sessions-a.jsonl").write_text(start(1, "runner_game", "2026-11-30T10:00:00") + "\n", encoding="utf-8")
        (folder / "sessions-b.jsonl").write_text(start(1, "orbital_ops", "2026-11-30T11:00:00") + "\n", encoding="utf-8")
        (folder / "notes.txt").write_text("not a log", encoding="utf-8")
        with redirect_stdout(io.StringIO()) as out:
            self.assertEqual(sessions_report.main([str(folder)]), 0)
        self.assertIn("Sessions: 2 (0 finished, 2 unfinished)", out.getvalue())
        # The folder and a file inside it, and the same file again: each file is read once.
        with redirect_stdout(io.StringIO()) as out:
            self.assertEqual(sessions_report.main([str(folder), str(folder / "sessions-a.jsonl"),
                                                   str(folder / "." / "sessions-a.jsonl")]), 0)
        self.assertIn("Sessions: 2 (0 finished, 2 unfinished)", out.getvalue())

    def test_csv_target_cannot_be_a_hardlink_to_a_log(self) -> None:
        log = self.sample()
        alias = log.parent / "alias.csv"
        os.link(log, alias)
        original = log.read_bytes()
        with redirect_stderr(io.StringIO()) as err:
            self.assertEqual(sessions_report.main([str(log), "--csv", str(alias)]), 2)
        self.assertIn("is one of the logs", err.getvalue())
        self.assertEqual(log.read_bytes(), original)

    def test_csv_target_cannot_be_a_log(self) -> None:
        log = self.sample()
        original = log.read_bytes()
        with redirect_stderr(io.StringIO()) as err:
            self.assertEqual(sessions_report.main([str(log), "--csv", str(log.parent / "." / log.name)]), 2)
        self.assertIn("is one of the logs", err.getvalue())
        self.assertEqual(log.read_bytes(), original)

    def test_csv_has_one_row_per_session(self) -> None:
        target = Path(self.folder.name) / "out.csv"
        with redirect_stdout(io.StringIO()):
            self.assertEqual(sessions_report.main([str(self.sample()), "--csv", str(target)]), 0)
        with target.open(encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 5)
        self.assertEqual(rows[0]["duration_s"], "143.2")
        self.assertEqual(rows[3]["ended_by"], "unfinished")
        self.assertEqual(rows[3]["duration_s"], "")
        self.assertEqual(rows[1]["game_overs"], "3")

    def test_missing_log_is_an_error(self) -> None:
        with redirect_stderr(io.StringIO()) as err:
            self.assertEqual(sessions_report.main([str(Path(self.folder.name) / "nope.jsonl")]), 2)
        self.assertIn("No such log", err.getvalue())

    def test_empty_log_prints_counts_only(self) -> None:
        text = sessions_report.summary(sessions_report.read([self.write("empty.jsonl", [])]))
        self.assertEqual(text, "Launches: 0\nSessions: 0 (0 finished, 0 unfinished)")

    def test_clock(self) -> None:
        self.assertEqual(sessions_report.clock(143.2), "2:23")
        self.assertEqual(sessions_report.clock(59.6), "1:00")


if __name__ == "__main__":
    unittest.main()
