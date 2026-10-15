"""Run every Godot test suite headless and fail on anything the engine reports.

Usage:
    python3 tools/tests/run_tests.py                     # all suites, in parallel
    python3 tools/tests/run_tests.py -k runner -j 2      # suites whose name contains "runner"
    python3 tools/tests/run_tests.py --list              # what would run, and what is skipped

Every .gd file under hoppys-adventure-arcade/tests/ that extends SceneTree (or MainLoop) is a
suite and runs by default; new tests need no registration. Other scripts there are helpers.
tools/tests/suites.toml is the only way to keep a suite out, and each skip carries a reason.
A suite fails if it exits nonzero, times out, or prints an engine/script error or an exit-time
leak. Errors a suite provokes on purpose are allowed only through its expected_errors patterns,
and every listed pattern must still match. Suites listed under [serial] (timing budgets) run one
at a time after the parallel batch.

Each suite gets its own HOME, so user:// writes (settings, leaderboards) never touch the
developer's real files or another suite running in parallel. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "hoppys-adventure-arcade"
TESTS = PROJECT / "tests"
CONFIG = Path(__file__).with_name("suites.toml")
TIMEOUT = 600
ANSI = re.compile(r"\x1b\[[0-9;]*m")
# Lines that mean something went wrong even when a suite's own checks all passed.
PROBLEM = re.compile(
    r"^(?:ERROR:|SCRIPT ERROR|USER ERROR|Parse Error)"
    r"|Failed to load script|leaked at exit|still in use at exit"
)


@dataclass
class Result:
    name: str
    seconds: float
    exit_code: int | None
    problems: list[str] = field(default_factory=list)
    log: str = ""
    notes: list[str] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        """A clean exit with nothing in the log that fails a suite."""
        return self.exit_code == 0 and not self.problems


# Godot can only run a script that extends SceneTree or MainLoop with --script; anything else
# under tests/ (shared helpers, fixtures) is support code, and running it pops a modal alert.
SUITE_BASE = re.compile(r"^extends\s+(?:SceneTree|MainLoop)\b", re.M)


def discover() -> list[str]:
    """Suite names are paths under tests/ without .gd, e.g. "runner_logic" or "assets/a1_check"."""
    return sorted(
        path.relative_to(TESTS).with_suffix("").as_posix()
        for path in TESTS.rglob("*.gd")
        if SUITE_BASE.search(path.read_text(encoding="utf-8", errors="replace"))
    )


@dataclass
class Config:
    skip: dict[str, str]
    serial: dict[str, str]
    expected: dict[str, list[re.Pattern[str]]]
    errors: list[str]


def load_config(suites: list[str], text: str | None = None) -> Config:
    """Read suites.toml (or `text`); every entry must name a suite, and skips and serials need a reason."""
    raw = tomllib.loads(CONFIG.read_text(encoding="utf-8") if text is None else text)
    skip: dict[str, str] = raw.get("skip", {})
    serial: dict[str, str] = raw.get("serial", {})
    expected = {name: [re.compile(p) for p in patterns] for name, patterns in raw.get("expected_errors", {}).items()}
    errors = [f"{CONFIG.name}: [{section}] names {name!r}, which is not a suite"
              for section, names in (("skip", skip), ("serial", serial), ("expected_errors", expected))
              for name in names if name not in suites]
    errors += [f"{CONFIG.name}: [{section}] entry {name!r} needs a reason"
               for section, table in (("skip", skip), ("serial", serial))
               for name, reason in table.items() if not reason.strip()]
    return Config(skip, serial, expected, errors)


def isolated_env(home: str) -> dict[str, str]:
    """Point every platform's user-data root (user://) at a private directory."""
    return {**os.environ, "HOME": home, "USERPROFILE": home,
            "XDG_DATA_HOME": f"{home}/.local/share", "XDG_CONFIG_HOME": f"{home}/.config",
            "XDG_CACHE_HOME": f"{home}/.cache",
            "APPDATA": str(Path(home, "AppData", "Roaming")), "LOCALAPPDATA": str(Path(home, "AppData", "Local"))}


def check_isolation(godot: str) -> str | None:
    """Ask Godot where user:// resolves under the isolated environment; None when it is private."""
    home = tempfile.mkdtemp(prefix="arcade-test-probe-")
    try:
        probe = Path(home, "probe.gd")
        probe.write_text('extends SceneTree\nfunc _init() -> void:\n\tprint("USER_DIR=", OS.get_user_data_dir())\n'
                         '\tquit()\n', encoding="utf-8")
        output = subprocess.run([godot, "--headless", "--path", str(PROJECT), "--script", str(probe)],
                                env=isolated_env(home), capture_output=True, text=True, timeout=120).stdout
        match = re.search(r"^USER_DIR=(.+)$", ANSI.sub("", output), re.M)
        user_dir = Path(match.group(1).strip()).resolve() if match else None
        if user_dir is None or Path(home).resolve() not in user_dir.parents:
            return f"user:// resolved to {user_dir or 'nothing'}, outside the isolated home {home}"
        return None
    finally:
        shutil.rmtree(home, ignore_errors=True)


LEAK = re.compile(r"leaked at exit|still in use at exit")
# The engine's two summary lines whose --verbose detail lines classify_leaks() reads. Any other exit
# leak report (RID allocations, for one) has no such detail and is never tolerated.
LEAK_SUMMARY = re.compile(r"ObjectDB instances were leaked at exit|resources still in use at exit")
LEAKED_INSTANCE = re.compile(r"^Leaked instance: (\w+):", re.M)
RESOURCE_IN_USE = re.compile(r"^Resource still in use: (.+) \((\w+)\)$", re.M)
# The engine releases audio playbacks on its audio thread. When a suite quits while that thread
# is starved (parallel 3D suites on a small CI runner), the shared music and UI voices are
# reported as leaked even after AudioService.settle(). Only that exact shape is tolerated:
# audio stream classes (AudioStream*, and Ogg Vorbis's internal OggPacketSequence*) and audio
# files still in use. Any other leaked object fails the suite.
AUDIO_CLASS = re.compile(r"^(?:AudioStream\w*|OggPacketSequence\w*)$")
VERBOSE_NOISE = re.compile(r"^(?:Loading resource:|Completed load for:|Loaded builtin|Loading |  ->|ResourceFormat)")


def classify_leaks(log: str) -> tuple[bool, list[str]]:
    """(is the audio-teardown race, detail lines naming what leaked) from a --verbose log."""
    instances = LEAKED_INSTANCE.findall(log)
    resources = RESOURCE_IN_USE.findall(log)
    unclassified = [line.strip() for line in log.splitlines() if LEAK.search(line) and not LEAK_SUMMARY.search(line)]
    details = [f"leaked: {name}" for name in instances] + [f"still in use: {path} ({kind})" for path, kind in resources]
    audio_only = bool(details) and not unclassified and all(AUDIO_CLASS.match(name) for name in instances) \
        and all(AUDIO_CLASS.match(kind) for _, kind in resources)
    return audio_only, details + unclassified


def run_suite(godot: str, name: str, expected: list[re.Pattern[str]]) -> Result:
    """Run one suite and classify any exit leak: only the audio-teardown race becomes a note."""
    result = run_once(godot, name, expected)
    if any(LEAK.search(problem) for problem in result.problems):
        audio_only, details = classify_leaks(result.log)
        if audio_only:
            result.problems = [problem for problem in result.problems if not LEAK_SUMMARY.search(problem)]
            result.notes.append("engine audio-teardown race tolerated: " + ", ".join(details))
        else:
            result.problems += details[:20] or ["leak with no --verbose detail"]
    result.log = "\n".join(line for line in result.log.splitlines() if not VERBOSE_NOISE.match(line))
    return result


def run_once(godot: str, name: str, expected: list[re.Pattern[str]]) -> Result:
    """One headless, --verbose run of res://tests/<name>.gd with a private user-data root."""
    home = tempfile.mkdtemp(prefix="arcade-test-home-")
    env = isolated_env(home)
    # --verbose makes Godot name what leaked in the same run, so a leak can be classified.
    command = [godot, "--headless", "--verbose", "--path", str(PROJECT), "--script", f"res://tests/{name}.gd"]
    started = time.monotonic()
    try:
        completed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=TIMEOUT)
        exit_code, log = completed.returncode, ANSI.sub("", completed.stdout + completed.stderr)
    except subprocess.TimeoutExpired as timeout:
        output = timeout.stdout or b""
        exit_code, log = None, ANSI.sub("", output.decode() if isinstance(output, bytes) else output)
    finally:
        shutil.rmtree(home, ignore_errors=True)
    return Result(name, time.monotonic() - started, exit_code, find_problems(log, exit_code, expected), log)


def find_problems(log: str, exit_code: int | None, expected: list[re.Pattern[str]]) -> list[str]:
    """Everything that fails a suite besides its exit code: engine errors, leaks, stale expectations."""
    problems = [] if exit_code is not None else [f"timed out after {TIMEOUT}s"]
    lines = log.splitlines()
    problems += [line.strip() for line in lines
                 if PROBLEM.search(line) and not any(pattern.search(line) for pattern in expected)]
    problems += [f"expected error no longer occurs; remove it from {CONFIG.name}: {pattern.pattern}"
                 for pattern in expected if not any(pattern.search(line) for line in lines)]
    return problems


def annotate(result: Result) -> None:
    """Report a failed suite as a GitHub Actions error annotation (no-op outside Actions)."""
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return
    detail = "%0A".join(dict.fromkeys(result.problems))[:4000] or f"exit {result.exit_code}"
    print(f"::error title=tests/{result.name}.gd::{detail}")


def write_summary(path: Path, seconds: float, skipped: dict[str, str], results: list[Result],
                  setup_error: str | None = None) -> None:
    """Write the JSON results summary. A setup failure (isolation, import) is recorded with no suites."""
    summary: dict[str, object] = {
        "seconds": round(seconds, 1),
        "skipped": skipped,
        "suites": [{"name": r.name, "passed": r.passed, "exit_code": r.exit_code, "seconds": round(r.seconds, 1),
                    "problems": list(dict.fromkeys(r.problems)), "notes": r.notes}
                   for r in sorted(results, key=lambda r: r.name)],
    }
    if setup_error is not None:
        summary["setup_error"] = setup_error
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    """Discover, filter and run the suites; returns 0 if all pass, 1 on a failure, 2 on a usage or setup error."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"),
                        help="Godot 4.7.1 binary (default: $GODOT or godot)")
    parser.add_argument("-k", dest="match", action="append", default=[],
                        help="run suites whose name contains this text")
    parser.add_argument("-j", "--jobs", type=int, default=min(4, os.cpu_count() or 1), help="suites to run at once")
    parser.add_argument("--no-import", action="store_true", help="skip the resource import step")
    parser.add_argument("--list", action="store_true", help="print the plan and exit")
    parser.add_argument("--results", type=Path, default=ROOT / "build/test-results/summary.json")
    args = parser.parse_args()

    suites = discover()
    config = load_config(suites)
    if config.errors:
        print("\n".join(config.errors), file=sys.stderr)
        return 2
    skips, expected = config.skip, config.expected
    selected = [s for s in suites if not args.match or any(m in s for m in args.match)]
    planned = [s for s in selected if s not in skips]
    if args.list:
        for suite in selected:
            if suite in skips:
                print(f"skip    {suite}: {skips[suite]}")
            elif suite in config.serial:
                print(f"serial  {suite}: {config.serial[suite]}")
            else:
                print(f"run     {suite}")
        return 0
    if not planned:
        print("No suites selected.", file=sys.stderr)
        return 2
    skipped = {name: skips[name] for name in selected if name in skips}

    leak = check_isolation(args.godot)
    if leak:
        print(f"Refusing to run: {leak}. Suites would touch real settings and leaderboards.", file=sys.stderr)
        write_summary(args.results, 0.0, skipped, [], f"user:// isolation: {leak}")
        return 2

    if not args.no_import:
        home = tempfile.mkdtemp(prefix="arcade-test-import-")
        try:
            imported = subprocess.run([args.godot, "--headless", "--path", str(PROJECT), "--import"],
                                      env=isolated_env(home), capture_output=True, text=True, timeout=TIMEOUT)
        finally:
            shutil.rmtree(home, ignore_errors=True)
        import_log = ANSI.sub("", imported.stdout + imported.stderr)
        import_problems = find_problems(import_log, imported.returncode, [])
        if imported.returncode != 0 or import_problems:
            print(import_log[-4000:], file=sys.stderr)
            print("Resource import failed:", *dict.fromkeys(import_problems), sep="\n  ", file=sys.stderr)
            reasons = list(dict.fromkeys(import_problems)) or [f"exit {imported.returncode}"]
            write_summary(args.results, 0.0, skipped, [], "resource import failed: " + "; ".join(reasons))
            return 1

    parallel = [s for s in planned if s not in config.serial]
    serial = [s for s in planned if s in config.serial]
    print(f"Running {len(planned)} suites ({len(selected) - len(planned)} skipped): "
          f"{len(parallel)} at {args.jobs} a time, then {len(serial)} alone.")
    started = time.monotonic()
    results: list[Result] = []

    def record(result: Result) -> None:
        results.append(result)
        note = f"  [{result.notes[0][:120]}]" if result.notes else ""
        print(f"{'PASS' if result.passed else 'FAIL'}  {result.name}  ({result.seconds:.0f}s){note}", flush=True)

    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = [pool.submit(run_suite, args.godot, s, expected.get(s, [])) for s in parallel]
        for future in as_completed(futures):
            record(future.result())
    # Suites with timing budgets run on an otherwise idle machine.
    for suite in serial:
        record(run_suite(args.godot, suite, expected.get(suite, [])))

    failed = sorted((r for r in results if not r.passed), key=lambda r: r.name)
    for result in failed:
        print(f"\n--- {result.name}: exit {result.exit_code}")
        for problem in dict.fromkeys(result.problems):
            print(f"    {problem}")
        print("    last output:\n" + "\n".join(f"      {line}" for line in result.log.splitlines()[-25:]))
        annotate(result)

    write_summary(args.results, time.monotonic() - started, skipped, results)
    print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed, "
          f"{len(selected) - len(planned)} skipped in {time.monotonic() - started:.0f}s")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
