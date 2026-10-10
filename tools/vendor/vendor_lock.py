"""Prove every vendored Godot add-on is an unchanged copy of a tagged upstream release.

Usage:
    python3 tools/vendor/vendor_lock.py --check       # CI and the pre-commit hook; no network
    python3 tools/vendor/vendor_lock.py --update cr_kit --tag v0.2.0 --source ../godot-kit

tools/vendor/vendor.lock.json records, for each add-on, its upstream repository, release tag and
commit, and the Git tree id of the add-on directory at that commit. A tree id hashes every file's
name, mode and bytes, so the vendored directory is an exact copy exactly when the tree id of what
is staged (what a commit will contain) equals the recorded one. --update copies the directory
from a local checkout of the upstream repository at a tag and rewrites the lock entry; edit the
add-on upstream and update, never in place. Every directory under the game's addons/ must be
locked. Standard library only.
"""

from __future__ import annotations

import argparse
import io
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = Path(__file__).with_name("vendor.lock.json")
ADDONS = "hoppys-adventure-arcade/addons"


def git(*args: str, cwd: Path = ROOT, data: bytes | None = None) -> str:
    completed = subprocess.run(["git", *args], cwd=cwd, input=data, capture_output=True, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {completed.stderr.decode().strip()}")
    return completed.stdout.decode().strip()


def staged_tree(path: str, root: Path = ROOT) -> str | None:
    """The tree id of a directory as staged in the index, or None when nothing is staged there."""
    if not git("ls-files", "--", path, cwd=root):
        return None
    return git("write-tree", f"--prefix={path}/", cwd=root)


def load(lock: Path = LOCK) -> dict:
    return json.loads(lock.read_text(encoding="utf-8")) if lock.exists() else {"version": 1, "addons": {}}


def check(root: Path = ROOT, lock: Path = LOCK, addons: str = ADDONS) -> list[str]:
    data = load(lock)
    problems = []
    for name, entry in data["addons"].items():
        actual = staged_tree(entry["path"], root)
        if actual is None:
            problems.append(f"{name}: {entry['path']} is locked but not in the repository")
        elif actual != entry["tree"]:
            problems.append(f"{name}: {entry['path']} differs from {entry['source']} {entry['tag']} "
                            f"(tree {actual}, locked {entry['tree']}). Change the add-on upstream, "
                            f"then run --update.")
    locked = {Path(entry["path"]).as_posix() for entry in data["addons"].values()}
    vendored = {Path(line).parts[:3] for line in git("ls-files", "--", addons, cwd=root).splitlines()}
    for parts in sorted(vendored):
        if len(parts) == 3 and "/".join(parts) not in locked:
            problems.append(f"{'/'.join(parts)} is vendored but has no entry in {lock.name}")
    return problems


def update(name: str, tag: str, source: Path, root: Path = ROOT, lock: Path = LOCK,
           repository: str | None = None, upstream_path: str | None = None, path: str | None = None) -> dict:
    data = load(lock)
    entry = data["addons"].get(name, {})
    repository = repository or entry.get("source")
    upstream_path = upstream_path or entry.get("upstream_path") or f"addons/{name}"
    path = path or entry.get("path") or f"{ADDONS}/{name}"
    if not repository:
        raise SystemExit(f"{name} is new: pass --repository owner/name.")
    if Path(path).parent.as_posix() != ADDONS or Path(path).name != name:
        raise SystemExit(f"{path} must be {ADDONS}/{name}.")
    commit = git("rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}", cwd=source)
    tree = git("rev-parse", "--verify", f"{commit}:{upstream_path}", cwd=source)
    archive = subprocess.run(["git", "archive", "--format=tar", commit, upstream_path], cwd=source,
                             capture_output=True, check=True).stdout
    destination = root / path
    with tempfile.TemporaryDirectory() as scratch:
        with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
            bundle.extractall(scratch, filter="data")
        if destination.exists():
            git("rm", "-r", "-q", "--cached", "--ignore-unmatch", "--", path, cwd=root)
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(Path(scratch, upstream_path), destination)
    git("add", "--", path, cwd=root)
    staged = staged_tree(path, root)
    if staged != tree:
        raise SystemExit(f"Staged {path} has tree {staged}, upstream {tag} has {tree}; check .gitattributes filters.")
    data["addons"][name] = {"source": repository, "tag": tag, "commit": commit,
                            "upstream_path": upstream_path, "path": path, "tree": tree}
    lock.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    git("add", "--", str(lock.relative_to(root)), cwd=root)
    return data["addons"][name]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="verify every vendored add-on against the lock")
    mode.add_argument("--update", metavar="NAME", help="vendor an add-on from --source at --tag")
    parser.add_argument("--tag", help="upstream release tag, e.g. v0.1.0")
    parser.add_argument("--source", type=Path, help="local checkout of the upstream repository")
    parser.add_argument("--repository", help="upstream owner/name (required the first time)")
    args = parser.parse_args()
    if args.check:
        problems = check()
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1 if problems else 0
    if not args.tag or not args.source:
        parser.error("--update needs --tag and --source")
    entry = update(args.update, args.tag, args.source.resolve(), repository=args.repository)
    print(f"Vendored {args.update} {entry['tag']} ({entry['commit'][:12]}) into {entry['path']}; staged with the lock.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
