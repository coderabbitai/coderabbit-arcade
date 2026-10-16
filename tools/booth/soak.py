"""Run a soak test of the game and watch its memory from outside.

Usage:
    python3 tools/booth/soak.py --minutes 480 -- "<game executable>" -- --booth   # a build, fullscreen
    python3 tools/booth/soak.py --minutes 10 --godot "$GODOT"                     # this checkout's project

The game runs with --soak=<minutes> (hoppys-adventure-arcade/app/booth_soak.gd). It visits every
route in turn, writes frame times and engine counts to a CSV, prints a frame-rate table per route
and a leak check, and exits 0 (steady), 1 (counts kept growing) or 2 (a route or its results
failed). Release builds can't report their own memory, so this wrapper samples the process's
resident memory with `ps`: every --rss-every seconds into rss.csv, and each time the game prints
"SOAK hub <n>", the same point of every pass over the routes. The first pass loads everything
once, so the check compares the second hub visit with the last, needs three, and fails the run
above --max-rss-growth percent. A run that outlasts --minutes by --grace minutes is stopped, and a
game that never prints its verdict fails. Each run gets its own folder under --out, holding the
game's CSV and summary, game.log and rss.csv. macOS and Linux. Standard library only.
"""
from __future__ import annotations

import argparse
import math
import os
import re
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2] / "hoppys-adventure-arcade"
HUB = re.compile(r"^SOAK hub (\d+)\b")
VERDICT = "SOAK verdict: "
# The soak options the wrapper sets; any already in a game command are dropped.
OWN_OPTIONS = ("--soak=", "--soak-dwell=", "--soak-log=")


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
    """The game's command line, with the wrapper's soak options after its "--"."""
    command = [args.godot, "--path", str(PROJECT)] if args.godot else list(args.command)
    command = [arg for arg in command if not arg.startswith(OWN_OPTIONS)]
    if "--" not in command[1:]:
        command.append("--")
    command += [f"--soak={args.minutes:g}", f"--soak-dwell={args.dwell:g}", f"--soak-log={out.resolve()}"]
    return command


def rss_verdict(hub_rss: dict[int, float], limit: float) -> tuple[str, bool]:
    """Compare memory at the second hub visit with the last: (message, grew too much)."""
    if len(hub_rss) < 3 or 2 not in hub_rss:
        return f"RSS: {len(hub_rss)} hub visit(s) measured, needs 3 to judge", False
    reference, last = hub_rss[2], hub_rss[max(hub_rss)]
    growth = 100.0 * (last - reference) / reference
    message = f"RSS: {reference:.0f} MB -> {last:.0f} MB (hub visits 2 -> {max(hub_rss)}, {growth:+.1f}%, limit {limit:g}%)"
    return message, growth > limit


def run_folder(out: Path) -> Path:
    """A new folder for this run under `out`, so two runs never share files."""
    folder = out / f"{time.strftime('%Y-%m-%dT%H-%M-%S')}-{os.getpid()}"
    folder.mkdir(parents=True, exist_ok=False)
    return folder


def main(argv: list[str] | None = None, sample: Callable[[int], float | None] = rss_mb) -> int:
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
    numbers = {"--minutes": args.minutes, "--dwell": args.dwell, "--rss-every": args.rss_every,
               "--max-rss-growth": args.max_rss_growth, "--grace": args.grace}
    for name, value in numbers.items():
        if not math.isfinite(value):
            parser.error(f"{name} must be a finite number")
    if args.minutes <= 0 or args.dwell <= 0 or args.rss_every <= 0:
        parser.error("--minutes, --dwell and --rss-every must be positive")
    if args.grace < 0 or args.max_rss_growth < 0:
        parser.error("--grace and --max-rss-growth can't be negative")
    if bool(args.godot) == bool(args.command):
        parser.error("pass either --godot or a game command after --")

    out = run_folder(args.out)
    command = game_command(args, out)
    print("soak: " + " ".join(command))
    deadline = time.monotonic() + (args.minutes + args.grace) * 60.0
    hub_rss: dict[int, float] = {}
    pending = ""
    timed_out = False

    def read_new(tail) -> None:
        """Take in the game's new whole lines; measure memory at each hub visit it announces."""
        nonlocal pending
        pending += tail.read()
        *lines, pending = pending.split("\n")
        for line in lines:
            match = HUB.match(line)
            if match and game.poll() is None:
                memory = sample(game.pid)
                if memory is not None:
                    hub_rss.setdefault(int(match.group(1)), memory)

    with (out / "game.log").open("w", encoding="utf-8") as log, (out / "rss.csv").open("w", encoding="utf-8") as rss, \
            (out / "game.log").open(encoding="utf-8", errors="replace") as tail:
        rss.write("elapsed_s,rss_mb\n")
        try:
            game = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        except OSError as error:
            print(f"soak: cannot start the game: {error}", file=sys.stderr)
            return 2
        try:
            started = time.monotonic()
            next_sample = started
            while game.poll() is None:
                now = time.monotonic()
                if now >= deadline:
                    timed_out = True
                    break
                read_new(tail)
                if now >= next_sample:
                    memory = sample(game.pid)
                    if memory is not None:
                        rss.write(f"{now - started:.1f},{memory:.1f}\n")
                        rss.flush()
                    next_sample = now + args.rss_every
                time.sleep(min(0.2, args.rss_every))
        finally:
            # Whatever happened above, never leave the game running behind the wrapper.
            if game.poll() is None:
                game.kill()
            game.wait()
        read_new(tail)
    log_text = (out / "game.log").read_text(encoding="utf-8", errors="replace")
    report = [line for line in log_text.splitlines() if line.startswith("SOAK ")]
    print("\n".join(report) if report else "soak: the game printed no SOAK lines; see game.log")
    message, grew = rss_verdict(hub_rss, args.max_rss_growth)
    print(f"soak: {message}")
    if timed_out:
        print(f"soak: the game ran past {args.minutes:g} + {args.grace:g} minutes and was stopped", file=sys.stderr)
        return 2
    if game.returncode != 0:
        print(f"soak: the game exited with status {game.returncode}", file=sys.stderr)
        return 1
    if not any(line.startswith(VERDICT) for line in report):
        print("soak: the game exited without a soak verdict; is it a build that knows --soak?", file=sys.stderr)
        return 1
    if grew:
        print("soak: resident memory kept growing", file=sys.stderr)
        return 1
    print(f"soak: passed; results in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
