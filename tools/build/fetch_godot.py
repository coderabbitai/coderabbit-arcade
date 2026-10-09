"""Download the pinned Godot editor and export templates, verified against godot.lock.json.

Usage:
    python3 tools/build/fetch_godot.py               # editor for this host; prints its path
    python3 tools/build/fetch_godot.py --templates   # also install the export templates

Downloads are cached under ~/.cache/coderabbit-arcade/godot/<version> (override with
--cache-dir) and every archive is checked against the committed SHA-512 before use.
Standard library only, so it runs the same on a laptop and in CI.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import stat
import sys
import urllib.request
import zipfile
from pathlib import Path

LOCK_PATH = Path(__file__).with_name("godot.lock.json")
CHUNK = 1 << 20


def load_lock() -> dict:
    return json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def host_editor(version: str) -> tuple[str, str]:
    """Return (archive name, editor path inside the extracted archive) for this host."""
    system = platform.system()
    if system == "Darwin":
        return f"Godot_v{version}_macos.universal.zip", "Godot.app/Contents/MacOS/Godot"
    if system == "Linux" and platform.machine() in ("x86_64", "AMD64"):
        return f"Godot_v{version}_linux.x86_64.zip", f"Godot_v{version}_linux.x86_64"
    if system == "Windows":
        return f"Godot_v{version}_win64.exe.zip", f"Godot_v{version}_win64.exe"
    raise SystemExit(f"No pinned Godot editor for {system}/{platform.machine()}.")


def templates_dir(template_version: str) -> Path:
    """Godot's per-user export template directory for this host."""
    system = platform.system()
    if system == "Darwin":
        base = Path.home() / "Library/Application Support/Godot"
    elif system == "Windows":
        base = Path(os.environ["APPDATA"]) / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "godot"
    return base / "export_templates" / template_version


def sha512(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as handle:
        while chunk := handle.read(CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(lock: dict, name: str, cache: Path) -> Path:
    """Download an archive once and refuse it unless its SHA-512 matches the lock."""
    expected = lock["sha512"].get(name)
    if not expected:
        raise SystemExit(f"{name} has no pinned SHA-512 in {LOCK_PATH.name}.")
    target = cache / name
    if target.exists() and sha512(target) == expected:
        return target
    partial = target.with_suffix(target.suffix + ".part")
    url = f"{lock['release_url']}/{name}"
    print(f"Downloading {url}", file=sys.stderr)
    with urllib.request.urlopen(url) as response, partial.open("wb") as handle:
        shutil.copyfileobj(response, handle, CHUNK)
    actual = sha512(partial)
    if actual != expected:
        partial.unlink()
        raise SystemExit(f"SHA-512 mismatch for {name}: expected {expected}, got {actual}.")
    partial.replace(target)
    return target


def install_editor(lock: dict, cache: Path) -> Path:
    archive_name, inner = host_editor(lock["version"])
    editor = cache / "editor" / inner
    marker = cache / "editor" / ".verified"
    if editor.exists() and marker.exists() and marker.read_text() == lock["sha512"][archive_name]:
        return editor
    archive = fetch(lock, archive_name, cache)
    shutil.rmtree(cache / "editor", ignore_errors=True)
    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(cache / "editor")
        # zipfile drops Unix modes; restore the ones the archive recorded (app bundles need them).
        for info in bundle.infolist():
            mode = info.external_attr >> 16
            if mode:
                (cache / "editor" / info.filename).chmod(stat.S_IMODE(mode))
    editor.chmod(editor.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    marker.write_text(lock["sha512"][archive_name])
    return editor


def install_templates(lock: dict, cache: Path, destination: Path) -> Path:
    name = f"Godot_v{lock['version']}_export_templates.tpz"
    marker = destination / ".verified"
    if (marker.exists() and marker.read_text() == lock["sha512"][name]
            and all((destination / template).is_file() for template in lock["templates"])):
        return destination
    archive = fetch(lock, name, cache)
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        for template in lock["templates"]:
            with bundle.open(f"templates/{template}") as source, (destination / template).open("wb") as out:
                shutil.copyfileobj(source, out, CHUNK)
            if not template.endswith((".zip", ".txt")):
                (destination / template).chmod(0o755)
    marker.write_text(lock["sha512"][name])
    return destination


def main() -> int:
    lock = load_lock()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cache-dir", type=Path,
                        default=Path.home() / ".cache/coderabbit-arcade/godot" / lock["version"])
    parser.add_argument("--templates", action="store_true", help="also install the pinned export templates")
    parser.add_argument("--templates-dir", type=Path, default=templates_dir(lock["template_version"]))
    parser.add_argument("--keep-archives", action="store_true",
                        help="keep downloaded archives after extraction (CI caches them)")
    args = parser.parse_args()
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    editor = install_editor(lock, args.cache_dir)
    if args.templates:
        print(f"Export templates: {install_templates(lock, args.cache_dir, args.templates_dir)}", file=sys.stderr)
    if not args.keep_archives:
        for archive in args.cache_dir.glob("*.zip"):
            archive.unlink()
        for archive in args.cache_dir.glob("*.tpz"):
            archive.unlink()
    print(editor)
    return 0


if __name__ == "__main__":
    sys.exit(main())
