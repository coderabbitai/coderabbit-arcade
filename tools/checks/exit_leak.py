"""Quit the game from screens with audio playing and fail if Godot reports leaks at exit.

Usage:
    python3 tools/checks/exit_leak.py --godot /path/to/Godot              # every scenario, headless
    python3 tools/checks/exit_leak.py --godot /path/to/Godot --rendered celebration

Each scenario of hoppys-adventure-arcade/tests/exit_leak.gd runs in its own Godot process,
because the "ObjectDB instances were leaked at exit" and "resources still in use at exit" lines
only appear once that script is gone. A voice the mixer still holds at shutdown prints both, so
quitting from a fight, the Code City celebration or the runner intro is a regression check for
AudioService's exit. Needs an imported project (`godot --headless --path ... --import`).
--rendered opens a window instead of running headless (kept on top on macOS, so a covered
window doesn't stall). Standard library only.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2] / "hoppys-adventure-arcade"
SCENARIOS = ("hub", "hub_quit", "code_city", "mini_boss", "celebration", "heroes_knockout", "runner_intro")
# The same exit lines tools/build/export_game.py's smoke check rejects, plus script failures.
FAILURE = re.compile(r"leaked at exit|still in use at exit|SCRIPT ERROR|^FAIL:", re.M)
TIMEOUT = 180


def check(godot: str, scenario: str, rendered: bool) -> str | None:
    """Runs one scenario; returns why it failed, or None when the exit was clean."""
    window = ["--always-on-top"] if rendered and sys.platform == "darwin" else []
    command = [godot, *(window if rendered else ["--headless"]), "--path", str(PROJECT),
               "--script", "res://tests/exit_leak.gd", "--", f"--scenario={scenario}"]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return f"timed out after {TIMEOUT} s"
    log = result.stdout + result.stderr
    problems = sorted({match.group(0) for match in FAILURE.finditer(log)})
    if f"EXIT_LEAK reached {scenario}" not in log:
        problems.append("never reached the screen")
    if result.returncode != 0:
        problems.append(f"exit {result.returncode}")
    if not problems:
        return None
    detail = "\n".join(line for line in log.splitlines() if FAILURE.search(line) or "Leaked instance" in line)
    return ", ".join(problems) + ("\n" + detail if detail else "")


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
        problem = check(args.godot, scenario, args.rendered)
        print(f"{'FAIL' if problem else 'PASS'}: exit from {scenario}" + (f": {problem}" if problem else ""))
        failed += problem is not None
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
