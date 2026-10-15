"""Quit the game from screens with audio playing and fail if Godot reports leaks at exit.

Usage:
    python3 tools/checks/exit_leak.py --godot /path/to/Godot              # every scenario, headless
    python3 tools/checks/exit_leak.py --godot /path/to/Godot --rendered celebration

Each scenario of hoppys-adventure-arcade/tests/exit_leak.gd runs in its own Godot process,
because the "ObjectDB instances were leaked at exit" and "resources still in use at exit" lines
only appear once that script is gone. A voice the mixer still holds at shutdown prints both, so
quitting from a fight, the Code City celebration or the runner intro is a regression check for
AudioService's exit. route_leaving / route_arriving close the window mid-transition, while
AppRouter is busy and quits at once. Every scenario must also exit within EXIT_LIMIT seconds of
the close: no hang in the router or in teardown. Where the environment has no running mixer,
stopped voices can't be released, so the leak lines are reported but not failed on.
Needs an imported project (`godot --headless --path ... --import`).
--rendered opens a window instead of running headless (kept on top on macOS, so a covered
window doesn't stall). Standard library only.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2] / "hoppys-adventure-arcade"
SCENARIOS = ("hub", "hub_quit", "code_city", "mini_boss", "celebration", "heroes_knockout", "runner_intro",
             "route_leaving", "route_arriving", "platformer_knockout", "platformer_results")
# The same exit lines tools/build/export_game.py's smoke check rejects.
LEAK = re.compile(r"leaked at exit|still in use at exit")
FAILURE = re.compile(r"SCRIPT ERROR|^FAIL:", re.M)
CLOSING = "EXIT_LEAK closing"
# Seconds from the close to the process ending: AppRouter's 1 s fade, AudioService's wait for the
# mixer (at most 0.5 s) and teardown, with room for a loaded CI runner.
EXIT_LIMIT = 5.0
TIMEOUT = 180
# Lines of the log shown for a failure that printed no leak or FAIL line.
TAIL = 25


def run(command: list[str]) -> tuple[str, int | None, float | None]:
    """The log, the exit code (None when killed at TIMEOUT) and the seconds from CLOSING to exit."""
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    watchdog = threading.Timer(TIMEOUT, process.kill)
    watchdog.start()
    lines: list[str] = []
    closed = None
    try:
        for line in process.stdout:
            lines.append(line)
            if closed is None and line.startswith(CLOSING):
                closed = time.monotonic()
        code = process.wait()
    finally:
        killed = not watchdog.is_alive()
        watchdog.cancel()
    exit_seconds = time.monotonic() - closed if closed is not None else None
    return "".join(lines), None if killed else code, exit_seconds


def check(godot: str, scenario: str, rendered: bool) -> tuple[str | None, str]:
    """Runs one scenario; returns why it failed (None when the exit was clean) and a note."""
    window = ["--always-on-top"] if rendered and sys.platform == "darwin" else []
    command = [godot, *(window if rendered else ["--headless"]), "--path", str(PROJECT),
               "--script", "res://tests/exit_leak.gd", "--", f"--scenario={scenario}"]
    log, code, exit_seconds = run(command)
    if code is None:
        return f"killed after {TIMEOUT} s", ""
    problems = sorted({match.group(0) for match in FAILURE.finditer(log)})
    leaks = sorted({match.group(0) for match in LEAK.finditer(log)})
    idle = "EXIT_LEAK mixer idle" in log
    if not idle:
        problems += leaks
    if f"EXIT_LEAK reached {scenario}" not in log:
        problems.append("never reached the screen")
    if exit_seconds is None:
        problems.append("never closed")
    elif exit_seconds > EXIT_LIMIT:
        problems.append(f"exited {exit_seconds:.1f} s after the close (limit {EXIT_LIMIT:.0f} s)")
    if code != 0:
        problems.append(f"exit {code}")
    note = f"exit {exit_seconds:.2f} s after the close" if exit_seconds is not None else ""
    if idle:
        note += f"; no running mixer, so leaks not checked ({', '.join(leaks) or 'none printed'})"
    if not problems:
        return None, note
    detail = "\n".join(line for line in log.splitlines()
                       if FAILURE.search(line) or LEAK.search(line) or "Leaked instance" in line)
    # A crash or a stall has no such lines; its backtrace or last output is at the end of the log.
    detail = detail or "\n".join(log.splitlines()[-TAIL:])
    return ", ".join(problems) + ("\n" + detail if detail else ""), note


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", required=True, help="Godot 4.7 binary")
    parser.add_argument("--rendered", action="store_true", help="open a window instead of --headless")
    parser.add_argument("scenarios", nargs="*", metavar="scenario", help=f"default: all of {', '.join(SCENARIOS)}")
    args = parser.parse_args()
    unknown = sorted(set(args.scenarios) - set(SCENARIOS))
    if unknown:
        parser.error(f"unknown scenario {', '.join(unknown)}; expected one of {', '.join(SCENARIOS)}")
    failed = 0
    for scenario in args.scenarios or SCENARIOS:
        problem, note = check(args.godot, scenario, args.rendered)
        print(f"{'FAIL' if problem else 'PASS'}: exit from {scenario}" + (f" ({note})" if note else "")
              + (f": {problem}" if problem else ""))
        failed += problem is not None
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
