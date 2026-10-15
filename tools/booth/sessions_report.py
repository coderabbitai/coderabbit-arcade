"""Summarize the session logs that booth mode writes (hoppys-adventure-arcade/app/booth_log.gd).

Usage:
    python3 tools/booth/sessions_report.py sessions.jsonl [more.jsonl ...]
    python3 tools/booth/sessions_report.py sessions.jsonl --csv sessions.csv

Each line of a log is one event: "launch" (the game started), then "start" and "end" for each
game session. Starts and ends pair by file, launch and session number. A start without an end
means the game stopped without quitting (a crash, a power cut or a forced kill); it is reported
as unfinished. Pass every machine's log at once to combine them. Standard library only.
"""
from __future__ import annotations

import argparse
import csv
import json
import statistics
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Session:
    source: str
    launch: str
    number: int
    game: str
    start: str
    end: str = ""
    duration_s: float | None = None
    ended_by: str = ""
    retries: int = 0


@dataclass
class Log:
    sessions: list[Session]
    launches: int
    skipped: list[str]


def read(paths: list[Path]) -> Log:
    """Pair the start and end events in these files. Lines that don't parse are skipped and named."""
    sessions: dict[tuple[str, str, int], Session] = {}
    launches = 0
    skipped: list[str] = []
    for path in paths:
        with path.open(encoding="utf-8") as handle:
            for number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                where = f"{path}:{number}"
                try:
                    event = json.loads(line)
                    kind = event["event"]
                    if kind == "launch":
                        launches += 1
                        continue
                    key = (str(path), str(event["launch"]), int(event["session"]))
                    if kind == "start":
                        sessions[key] = Session(key[0], key[1], key[2], str(event["game"]), str(event["time"]))
                    elif kind == "end":
                        session = sessions.get(key)
                        if session is None:
                            skipped.append(f"{where}: end without a start")
                            continue
                        session.end = str(event["time"])
                        session.duration_s = float(event["duration_s"])
                        session.ended_by = str(event["ended_by"])
                        session.retries = int(event.get("retries", 0))
                    else:
                        skipped.append(f"{where}: unknown event {kind!r}")
                except (json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
                    skipped.append(f"{where}: {type(error).__name__}: {error}")
    ordered = sorted(sessions.values(), key=lambda s: (s.start, s.source, s.launch, s.number))
    return Log(ordered, launches, skipped)


def clock(seconds: float) -> str:
    """143.2 -> '2:23'."""
    whole = int(round(seconds))
    return f"{whole // 60}:{whole % 60:02d}"


def p90(values: list[float]) -> float:
    """The 90th percentile, or the largest value when there are too few to interpolate."""
    if len(values) < 2:
        return max(values)
    return statistics.quantiles(values, n=10, method="inclusive")[-1]


def summary(log: Log) -> str:
    finished = [s for s in log.sessions if s.duration_s is not None]
    unfinished = len(log.sessions) - len(finished)
    lines = [
        f"Launches: {log.launches}",
        f"Sessions: {len(log.sessions)} ({len(finished)} finished, {unfinished} unfinished)",
    ]
    if finished:
        lines += ["", f"{'Game':<20} {'Sessions':>8} {'Median':>7} {'Mean':>7} {'P90':>7} {'Retries':>8}"]
        for game in sorted({s.game for s in finished}):
            durations = [s.duration_s for s in finished if s.game == game]
            retries = sum(s.retries for s in finished if s.game == game)
            lines.append(
                f"{game:<20} {len(durations):>8} {clock(statistics.median(durations)):>7}"
                f" {clock(statistics.fmean(durations)):>7} {clock(p90(durations)):>7} {retries:>8}"
            )
        ended = Counter(s.ended_by for s in finished)
        lines += ["", "Ended by: " + ", ".join(f"{reason} {count}" for reason, count in sorted(ended.items()))]
    if log.sessions:
        hours = Counter(s.start[11:13] for s in log.sessions if len(s.start) >= 13)
        lines.append("Starts by hour: " + ", ".join(f"{hour}:00 {count}" for hour, count in sorted(hours.items())))
    if log.skipped:
        lines += ["", f"Skipped {len(log.skipped)} line(s):"] + [f"  {entry}" for entry in log.skipped]
    return "\n".join(lines)


def write_csv(log: Log, target: Path) -> None:
    """One row per session, for spreadsheets and the post-event report."""
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["source", "launch", "session", "game", "start", "end", "duration_s", "ended_by", "retries"])
        for s in log.sessions:
            duration = "" if s.duration_s is None else f"{s.duration_s:.1f}"
            writer.writerow([s.source, s.launch, s.number, s.game, s.start, s.end, duration, s.ended_by or "unfinished", s.retries])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("logs", nargs="+", type=Path, help="session logs (JSON Lines)")
    parser.add_argument("--csv", type=Path, help="also write one row per session to this CSV file")
    args = parser.parse_args(argv)
    missing = [str(path) for path in args.logs if not path.is_file()]
    if missing:
        print("No such log: " + ", ".join(missing), file=sys.stderr)
        return 2
    log = read(args.logs)
    print(summary(log))
    if args.csv:
        write_csv(log, args.csv)
        print(f"\nWrote {len(log.sessions)} session(s) to {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
