"""Export versioned, smoke-tested builds of Hoppy's Adventure Arcade.

Usage:
    python3 tools/build/export_game.py                      # every preset, into build/
    python3 tools/build/export_game.py --preset macOS       # one preset
    python3 tools/build/export_game.py --godot /path/to/Godot --smoke

Each artifact is named hoppys-adventure-arcade-<version>-<commit>-<platform>.zip, where
<version> is application/config/version in project.godot. With --smoke, every artifact this
host can run is unpacked and launched headless with `-- --smoke-routes`, which loads every
route of the packaged game (see app/app_router.gd). build/dist/BUILD_MANIFEST.json and
SHA256SUMS.txt record what was built, from which commit and engine, and what was verified.
Standard library only; the same script runs locally and in CI.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "hoppys-adventure-arcade"
LOCK = json.loads((Path(__file__).with_name("godot.lock.json")).read_text(encoding="utf-8"))
SLUG = "hoppys-adventure-arcade"
EXPORT_TIMEOUT = 900
SMOKE_TIMEOUT = 300
# A packaged build must load every route without engine or script errors and exit cleanly.
SMOKE_FAILURE = re.compile(r"^(ERROR:|SCRIPT ERROR|USER ERROR|Parse Error)|leaked at exit|still in use at exit", re.M)
ANSI = re.compile(r"\x1b\[[0-9;]*m")


@dataclass(frozen=True)
class Target:
    preset: str          # name in export_presets.cfg
    platform: str        # artifact suffix
    export_name: str     # file Godot writes
    host: str            # platform.system() that can launch it for the smoke check


TARGETS = (
    Target("macOS", "macos", "HoppysAdventureArcade.zip", "Darwin"),
    Target("Windows", "windows", "HoppysAdventureArcade.exe", "Windows"),
    Target("Linux", "linux", "HoppysAdventureArcade.x86_64", "Linux"),
)


def run(command: list[str], timeout: int, cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def fail(message: str, log: str = "") -> None:
    if log:
        print(ANSI.sub("", log)[-6000:], file=sys.stderr)
    raise SystemExit(f"error: {message}")


def godot_binary(explicit: str | None) -> str:
    if explicit:
        return explicit
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    fetched = run([sys.executable, str(Path(__file__).with_name("fetch_godot.py"))], timeout=1800)
    if fetched.returncode != 0:
        fail("could not fetch the pinned Godot editor", fetched.stderr)
    return fetched.stdout.strip().splitlines()[-1]


def check_engine(godot: str) -> str:
    version = run([godot, "--version"], timeout=60).stdout.strip()
    if not version.startswith(LOCK["template_version"] + "."):
        fail(f"{godot} reports {version or 'nothing'}; this project pins {LOCK['template_version']}.")
    return version


def project_version() -> str:
    match = re.search(r'^config/version="([^"]+)"', (PROJECT / "project.godot").read_text(encoding="utf-8"), re.M)
    if not match:
        fail("project.godot has no application/config/version.")
    return match.group(1)


def git(*args: str) -> str:
    return run(["git", *args], timeout=60, cwd=ROOT).stdout.strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def export(godot: str, target: Target, stage: Path) -> Path:
    stage.mkdir(parents=True, exist_ok=True)
    output = stage / target.export_name
    result = run([godot, "--headless", "--path", str(PROJECT), "--export-release", target.preset, str(output)],
                 timeout=EXPORT_TIMEOUT)
    log = ANSI.sub("", result.stdout + result.stderr)
    if result.returncode != 0 or not output.exists() or re.search(r"^ERROR:", log, re.M):
        fail(f"export of preset {target.preset!r} failed (exit {result.returncode})", log)
    return output


def package(target: Target, exported: Path, artifact: Path) -> None:
    """macOS exports are already a zip of the .app; wrap the single-file desktop binaries."""
    if target.platform == "macos":
        shutil.copyfile(exported, artifact)
        return
    with zipfile.ZipFile(artifact, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        info = zipfile.ZipInfo.from_file(exported, exported.name)
        info.external_attr = (stat.S_IFREG | 0o755) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        with exported.open("rb") as source, bundle.open(info, "w") as out:
            shutil.copyfileobj(source, out, 1 << 20)


def smoke(target: Target, artifact: Path, scratch: Path) -> str:
    if platform.system() != target.host:
        return "not run on this host"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    # `unzip`/`ditto` keep the app bundle's modes and symlinks; zipfile would not.
    extract = ["ditto", "-x", "-k", str(artifact), str(scratch)] if target.host == "Darwin" \
        else ["unzip", "-q", str(artifact), "-d", str(scratch)]
    if run(extract, timeout=300).returncode != 0:
        fail(f"could not unpack {artifact.name} for the smoke check")
    if target.host == "Darwin":
        binary = next(scratch.glob("*.app/Contents/MacOS/*"))
    else:
        binary = scratch / target.export_name
    result = run([str(binary), "--headless", "--", "--smoke-routes"], timeout=SMOKE_TIMEOUT)
    log = ANSI.sub("", result.stdout + result.stderr)
    if result.returncode != 0 or "SMOKE complete" not in log or SMOKE_FAILURE.search(log):
        fail(f"smoke check of {artifact.name} failed (exit {result.returncode})", log)
    shutil.rmtree(scratch, ignore_errors=True)
    return "passed: every route loaded headless"


def write_summary(manifest: dict) -> None:
    """Add a build table to the GitHub Actions job summary when running in CI."""
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary:
        return
    rows = "".join(f"| {a['platform']} | `{a['file']}` | {a['bytes'] / 1e6:.0f} MB | {a['smoke']} |\n"
                   for a in manifest["artifacts"])
    with open(summary, "a", encoding="utf-8") as handle:
        handle.write(f"### Hoppy's Adventure Arcade {manifest['version']} ({manifest['commit'][:12]})\n\n"
                     f"Engine {manifest['engine']}\n\n| Platform | File | Size | Smoke |\n| --- | --- | --- | --- |\n"
                     + rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", help="Godot editor binary (default: $GODOT, else fetch the pinned one)")
    parser.add_argument("--preset", action="append", choices=[t.preset for t in TARGETS],
                        help="export only these presets (repeatable; default: all)")
    parser.add_argument("--out", type=Path, default=ROOT / "build", help="output directory (default: build/)")
    parser.add_argument("--smoke", action="store_true", help="launch each artifact this host can run")
    args = parser.parse_args()

    godot = godot_binary(args.godot)
    engine = check_engine(godot)
    version = project_version()
    commit = git("rev-parse", "--short=12", "HEAD")
    tag = os.environ.get("GITHUB_REF_NAME") if os.environ.get("GITHUB_REF_TYPE") == "tag" else None
    if tag and tag != f"v{version}":
        fail(f"tag {tag} does not match project version {version}; tag releases as v{version}.")
    dirty = bool(git("status", "--porcelain", "--untracked-files=no"))

    out = args.out.resolve()
    shutil.rmtree(out / "stage", ignore_errors=True)
    shutil.rmtree(out / "dist", ignore_errors=True)
    (out / "dist").mkdir(parents=True)

    imported = run([godot, "--headless", "--path", str(PROJECT), "--import"], timeout=EXPORT_TIMEOUT)
    if imported.returncode != 0:
        fail("resource import failed", imported.stdout + imported.stderr)

    artifacts = []
    for target in [t for t in TARGETS if not args.preset or t.preset in args.preset]:
        print(f"Exporting {target.preset}…", file=sys.stderr)
        exported = export(godot, target, out / "stage" / target.platform)
        artifact = out / "dist" / f"{SLUG}-{version}-{commit}-{target.platform}.zip"
        package(target, exported, artifact)
        verified = "not requested"
        if args.smoke:
            verified = smoke(target, artifact, out / "stage" / f"{target.platform}-smoke")
        size = artifact.stat().st_size
        print(f"  {artifact.name}: {size / 1e6:.0f} MB, smoke {verified}", file=sys.stderr)
        artifacts.append({"platform": target.platform, "preset": target.preset, "file": artifact.name,
                          "bytes": size, "sha256": sha256(artifact), "smoke": verified})

    manifest = {
        "name": "Hoppy's Adventure Arcade",
        "version": version,
        "commit": git("rev-parse", "HEAD"),
        "dirty": dirty,
        "tag": tag,
        "engine": engine,
        "built_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "artifacts": artifacts,
    }
    (out / "dist" / "BUILD_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (out / "dist" / "SHA256SUMS.txt").write_text(
        "".join(f"{a['sha256']}  {a['file']}\n" for a in artifacts), encoding="utf-8")
    shutil.rmtree(out / "stage", ignore_errors=True)
    write_summary(manifest)
    print(f"Wrote {len(artifacts)} artifact(s) to {out / 'dist'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
