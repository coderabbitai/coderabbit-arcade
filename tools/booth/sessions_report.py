"""Summarize the session logs that booth mode writes (hoppys-adventure-arcade/app/booth_log.gd).

Usage:
    python3 tools/booth/sessions_report.py booth/ [more folders or .jsonl files ...]
    python3 tools/booth/sessions_report.py booth/ --csv sessions.csv

The game writes one file per run (sessions-<time>-<process id>.jsonl) in its booth folder; pass
the folder, or single files. Each line is one event: "launch" (the game started), then "start"
and "end" for each game session. Starts and ends pair by file, launch and session number. A start
without an end means the game stopped without quitting (a crash, a power cut or a forced kill);
it is reported as unfinished. Pass every machine's folder at once to combine them. Standard
library only.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
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
                        # Check every field first, so a malformed end leaves the session as it was.
                        end, ended_by = event["time"], event["ended_by"]
                        if event["game"] != session.game:
                            raise ValueError(f"end for {event['game']!r} closes a {session.game!r} session")
                        if not (isinstance(end, str) and end and isinstance(ended_by, str) and ended_by):
                            raise ValueError("time and ended_by must be non-empty strings")
                        duration_s, retries = float(event["duration_s"]), int(event.get("retries", 0))
                        if not math.isfinite(duration_s) or duration_s < 0:
                            raise ValueError(f"duration_s must be a finite, non-negative number, not {duration_s}")
                        session.end, session.duration_s, session.ended_by, session.retries = end, duration_s, ended_by, retries
                    else:
                        skipped.append(f"{where}: unknown event {kind!r}")
                except (json.JSONDecodeError, KeyError, TypeError, ValueError, OverflowError) as error:
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
    if log.sessions:
        # Sessions and Unfinished count every visit; lengths and retries come from finished ones.
        lines += ["", f"{'Game':<20} {'Sessions':>8} {'Unfinished':>10} {'Median':>7} {'Mean':>7} {'P90':>7} {'Retries':>8}"]
        for game in sorted({s.game for s in log.sessions}):
            visits = [s for s in log.sessions if s.game == game]
            durations = [s.duration_s for s in visits if s.duration_s is not None]
            lengths = (clock(statistics.median(durations)), clock(statistics.fmean(durations)), clock(p90(durations))) \
                if durations else ("-", "-", "-")
            lines.append(
                f"{game:<20} {len(visits):>8} {len(visits) - len(durations):>10} {lengths[0]:>7} {lengths[1]:>7}"
                f" {lengths[2]:>7} {sum(s.retries for s in visits if s.duration_s is not None):>8}"
            )
    if finished:
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


def expand(paths: list[Path]) -> list[Path]:
    """The log files: each file as given, and every .jsonl file in each folder."""
    files: list[Path] = []
    for path in paths:
        files.extend(sorted(path.glob("*.jsonl")) if path.is_dir() else [path])
    return files


def same_file(a: Path, b: Path) -> bool:
    """True when both paths name one file, through a symlink, a hardlink or `..`."""
    try:
        return a.samefile(b)
    except OSError:
        return a.resolve() == b.resolve()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("logs", nargs="+", type=Path, help="booth folders or session log files (JSON Lines)")
    parser.add_argument("--csv", type=Path, help="also write one row per session to this CSV file")
    args = parser.parse_args(argv)
    missing = [str(path) for path in args.logs if not path.exists()]
    if missing:
        print("No such log or folder: " + ", ".join(missing), file=sys.stderr)
        return 2
    logs = expand(args.logs)
    if args.csv and any(same_file(args.csv, path) for path in logs):
        print(f"--csv {args.csv} is one of the logs; pick another file so the log isn't overwritten", file=sys.stderr)
        return 2
    log = read(logs)
    print(summary(log))
    if args.csv:
        write_csv(log, args.csv)
        print(f"\nWrote {len(log.sessions)} session(s) to {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
