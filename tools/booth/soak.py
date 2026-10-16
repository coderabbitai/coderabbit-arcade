"""Run a soak test of the game and watch its memory from outside.

Usage:
    python3 tools/booth/soak.py --minutes 480 -- "<game executable>" -- --booth   # a build, fullscreen
    python3 tools/booth/soak.py --minutes 10 --godot "$GODOT"                     # this checkout's project

The game runs with --soak=<minutes> (hoppys-adventure-arcade/app/booth_soak.gd). It visits every
route in turn, writes frame times and engine counts to a CSV, prints a frame-rate table per route
and a leak check, and exits 0 (steady) or 1 (counts kept growing). Release builds can't report
their own memory, so this wrapper samples the process's resident memory with `ps` into rss.csv.
The first pass over the routes loads everything once, so memory is compared from the start of the
second pass (the game prints "SOAK cycle 2") to the end, and only once a third pass has begun. The
run fails when it grew by more than --max-rss-growth percent. A run that outlasts --minutes by
--grace minutes is stopped and fails.
Everything lands in --out: the game's CSV and summary, game.log and rss.csv. macOS and Linux.
Standard library only.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2] / "hoppys-adventure-arcade"
CYCLE = re.compile(r"^SOAK cycle (\d+)\b")


def rss_mb(pid: int) -> float | None:
    """The process's resident memory in MB, or None when ps can't see it. Under 1 MB the process is
    still starting (forked, not yet the game), so that reading is skipped too."""
    try:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True, timeout=10).stdout
        kilobytes = int(out.strip())
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None
    return kilobytes / 1024.0 if kilobytes >= 1024 else None


def game_command(args: argparse.Namespace, out: Path) -> list[str]:
    """The game's command line, with the soak's user arguments after its "--"."""
    command = [args.godot, "--path", str(PROJECT)] if args.godot else list(args.command)
    if "--" not in command[1:]:
        command.append("--")
    command += [f"--soak={args.minutes:g}", f"--soak-dwell={args.dwell:g}", f"--soak-log={out.resolve()}"]
    return command


def rss_verdict(samples: list[tuple[float, float]], cycles: dict[int, float], limit: float) -> tuple[str, bool]:
    """Compare memory when the second pass began with the last sample: (message, grew too much).
    `cycles` maps each pass the game announced to the run time it began at."""
    if 3 not in cycles:
        return f"RSS: {len(cycles)} pass(es) over the routes, needs 3 to judge", False
    after = [rss for elapsed, rss in samples if elapsed >= cycles[2]]
    if len(after) < 2:
        return f"RSS: {len(after)} sample(s) after the first pass, too few to judge", False
    reference, last = after[0], after[-1]
    growth = 100.0 * (last - reference) / reference
    message = f"RSS: {reference:.0f} MB -> {last:.0f} MB ({growth:+.1f}%, limit {limit:g}%)"
    return message, growth > limit


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     usage="%(prog)s --minutes M [options] (--godot GODOT | -- GAME [ARGS ...])")
    parser.add_argument("--minutes", type=float, required=True, help="how long the game soaks")
    parser.add_argument("--dwell", type=float, default=30.0, help="seconds on each route (default 30)")
    parser.add_argument("--out", type=Path, default=Path("soak-results"), help="results folder (default soak-results)")
    parser.add_argument("--godot", help="run this checkout's project with this Godot instead of a build")
    parser.add_argument("--rss-every", type=float, default=30.0, help="seconds between memory samples (default 30)")
    parser.add_argument("--max-rss-growth", type=float, default=25.0, help="percent RSS growth that fails the run (default 25)")
    parser.add_argument("--grace", type=float, default=10.0, help="minutes past --minutes before the run is stopped (default 10)")
    # Everything after the first "--" is the game's command line, which can hold its own "--".
    argv = sys.argv[1:] if argv is None else argv
    split = argv.index("--") if "--" in argv else len(argv)
    args = parser.parse_args(argv[:split])
    args.command = argv[split + 1:]
    if args.minutes <= 0 or args.dwell <= 0 or args.rss_every <= 0:
        parser.error("--minutes, --dwell and --rss-every must be positive")
    if bool(args.godot) == bool(args.command):
        parser.error("pass either --godot or a game command after --")
    args.out.mkdir(parents=True, exist_ok=True)
    command = game_command(args, args.out)
    print("soak: " + " ".join(command))
    deadline = time.monotonic() + (args.minutes + args.grace) * 60.0
    samples: list[tuple[float, float]] = []
    cycles: dict[int, float] = {}
    pending = ""
    with (args.out / "game.log").open("w", encoding="utf-8") as log, (args.out / "rss.csv").open("w", encoding="utf-8") as rss, \
            (args.out / "game.log").open(encoding="utf-8", errors="replace") as tail:
        rss.write("elapsed_s,rss_mb\n")
        try:
            game = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        except OSError as error:
            print(f"soak: cannot start the game: {error}", file=sys.stderr)
            return 2
        started = time.monotonic()
        next_sample = started
        timed_out = False
        while game.poll() is None:
            now = time.monotonic()
            if now >= deadline:
                timed_out = True
                game.kill()
                game.wait()
                break
            # Whole lines only: a read can stop partway through one.
            pending += tail.read()
            *lines, pending = pending.split("\n")
            for line in lines:
                if match := CYCLE.match(line):
                    cycles.setdefault(int(match.group(1)), now - started)
            if now >= next_sample:
                memory = rss_mb(game.pid)
                if memory is not None:
                    samples.append((now - started, memory))
                    rss.write(f"{now - started:.1f},{memory:.1f}\n")
                    rss.flush()
                next_sample = now + args.rss_every
            time.sleep(min(0.2, args.rss_every))
    report = [line for line in (args.out / "game.log").read_text(encoding="utf-8", errors="replace").splitlines()
              if line.startswith("SOAK ")]
    print("\n".join(report) if report else "soak: the game printed no SOAK lines; see game.log")
    message, grew = rss_verdict(samples, cycles, args.max_rss_growth)
    print(f"soak: {message}")
    if timed_out:
        print(f"soak: the game ran past {args.minutes:g} + {args.grace:g} minutes and was stopped", file=sys.stderr)
        return 2
    if game.returncode != 0:
        print(f"soak: the game exited with status {game.returncode}", file=sys.stderr)
        return 1
    if grew:
        print("soak: resident memory kept growing", file=sys.stderr)
        return 1
    print(f"soak: passed; results in {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
