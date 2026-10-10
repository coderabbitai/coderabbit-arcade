"""Keep every vendored Godot add-on an exact, reviewable copy of a tagged upstream release.

Usage:
    python3 tools/vendor/vendor_lock.py --check                                 # CI and pre-commit; offline
    python3 tools/vendor/vendor_lock.py --verify-source cr_kit --source ../godot-kit
    python3 tools/vendor/vendor_lock.py --update cr_kit --tag v0.2.0 --source ../godot-kit

tools/vendor/vendor.lock.json records, for each add-on, its upstream repository, release tag and
commit, and the Git tree id of the add-on directory at that commit. A tree id hashes every file's
name, mode and bytes.

--check compares each staged add-on directory (what a commit will contain) with the staged lock,
and fails on any edited, added or removed file and on any directory under addons/ without an
entry. It proves the copy matches its lock entry; it cannot prove the entry describes a real
upstream release, because both live in this repository. That rests on --update, which writes the
entry from an upstream checkout, and on review; --verify-source re-derives the tag's commit and
tree from an upstream checkout and compares them with the entry.

--update copies the add-on blob by blob from the tag's tree (so upstream export attributes cannot
change it), checks that this repository would store identical blobs, refuses to touch a
destination with untracked or unstaged files, then replaces the copy and stages it with the
lock. Change an add-on upstream and update; never edit it in place. Standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = Path(__file__).with_name("vendor.lock.json")
ADDONS = "hoppys-adventure-arcade/addons"
# Variables that point Git at a repository or index. Hooks set some of them; they would redirect a
# command meant for another checkout, so commands against an upstream checkout run without them.
REPOSITORY_VARIABLES = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
                        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_NAMESPACE", "GIT_PREFIX")
FILE_MODES = {"100644": 0o644, "100755": 0o755}


def git(*args: str, cwd: Path = ROOT, data: bytes | None = None, foreign: bool = False) -> bytes:
    """Run Git in `cwd`. `foreign` marks a checkout other than the one a hook may be running in."""
    env = {k: v for k, v in os.environ.items() if k not in REPOSITORY_VARIABLES} if foreign else None
    completed = subprocess.run(["git", *args], cwd=cwd, input=data, capture_output=True, check=False, env=env)
    if completed.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {completed.stderr.decode().strip()}")
    return completed.stdout


def text(*args: str, cwd: Path = ROOT, data: bytes | None = None, foreign: bool = False) -> str:
    return git(*args, cwd=cwd, data=data, foreign=foreign).decode().strip()


def staged_tree(path: str, root: Path = ROOT) -> str | None:
    """The tree id of a directory as staged in the index, or None when nothing is staged there."""
    if not text("ls-files", "--", path, cwd=root):
        return None
    return text("write-tree", f"--prefix={path}/", cwd=root)


def load(lock: Path = LOCK, root: Path = ROOT, staged: bool = False) -> dict:
    """The lock from the working tree, or as staged (what a commit will contain)."""
    empty = {"version": 1, "addons": {}}
    if not staged:
        return json.loads(lock.read_text(encoding="utf-8")) if lock.exists() else empty
    relative = lock.relative_to(root).as_posix()
    if not text("ls-files", "--", relative, cwd=root):
        return empty
    return json.loads(git("show", f":{relative}", cwd=root))


def check(root: Path = ROOT, lock: Path = LOCK, addons: str = ADDONS) -> list[str]:
    data = load(lock, root, staged=True)
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
    vendored = {Path(line).parts[:3] for line in text("ls-files", "--", addons, cwd=root).splitlines()}
    for parts in sorted(vendored):
        if len(parts) == 3 and "/".join(parts) not in locked:
            problems.append(f"{'/'.join(parts)} is vendored but has no entry in {lock.name}")
    return problems


def resolve(source: Path, tag: str, upstream_path: str) -> tuple[str, str]:
    """(commit, tree id of upstream_path) for a tag in an upstream checkout."""
    commit = text("rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}", cwd=source, foreign=True)
    tree = text("rev-parse", "--verify", f"{commit}:{upstream_path}", cwd=source, foreign=True)
    return commit, tree


def verify_source(name: str, source: Path, root: Path = ROOT, lock: Path = LOCK) -> list[str]:
    entry = load(lock, root).get("addons", {}).get(name)
    if entry is None:
        return [f"{name} has no entry in {lock.name}"]
    commit, tree = resolve(source, entry["tag"], entry["upstream_path"])
    problems = []
    if commit != entry["commit"]:
        problems.append(f"{name}: {entry['tag']} is {commit} upstream, locked {entry['commit']}")
    if tree != entry["tree"]:
        problems.append(f"{name}: {entry['upstream_path']} at {entry['tag']} is tree {tree}, locked {entry['tree']}")
    return problems


def upstream_files(source: Path, commit: str, upstream_path: str) -> list[tuple[str, str, str]]:
    """(mode, blob id, path inside the add-on) for every file in the add-on's tree at a commit."""
    listing = git("ls-tree", "-r", "-z", "--full-tree", commit, "--", upstream_path, cwd=source, foreign=True)
    files = []
    for record in filter(None, listing.split(b"\0")):
        meta, path = record.split(b"\t", 1)
        mode, kind, blob = meta.decode().split()
        if kind != "blob" or mode not in FILE_MODES:
            raise SystemExit(f"{path.decode()} is a {kind} with mode {mode}; vendored add-ons hold regular files only.")
        files.append((mode, blob, Path(path.decode()).relative_to(upstream_path).as_posix()))
    return files


def update(name: str, tag: str, source: Path, root: Path = ROOT, lock: Path = LOCK,
           repository: str | None = None, upstream_path: str | None = None, path: str | None = None) -> dict:
    data = load(lock, root)
    entry = data["addons"].get(name, {})
    repository = repository or entry.get("source")
    upstream_path = upstream_path or entry.get("upstream_path") or f"addons/{name}"
    path = path or entry.get("path") or f"{ADDONS}/{name}"
    if not repository:
        raise SystemExit(f"{name} is new: pass --repository owner/name.")
    if Path(path).parent.as_posix() != ADDONS or Path(path).name != name:
        raise SystemExit(f"{path} must be {ADDONS}/{name}.")
    commit, tree = resolve(source, tag, upstream_path)
    files = upstream_files(source, commit, upstream_path)

    # Everything that can fail runs before the existing copy is touched.
    # Staged files are safe to replace (Git holds their blobs); untracked, ignored and unstaged
    # working-tree changes are not, because replacing the directory would delete them.
    status = git("status", "--porcelain", "--ignored", "--untracked-files=all", "--", path, cwd=root).decode()
    unsaved = [line for line in status.splitlines() if line[:2] in ("??", "!!") or line[1] != " "]
    if unsaved:
        listing = "\n".join(unsaved)
        raise SystemExit(f"{path} has untracked or unstaged files; commit, move or delete them first:\n{listing}")
    contents = {}
    for mode, blob, relative in files:
        contents[relative] = git("cat-file", "blob", blob, cwd=source, foreign=True)
        stored = text("hash-object", f"--path={path}/{relative}", "--stdin", cwd=root, data=contents[relative])
        if stored != blob:
            raise SystemExit(f"This repository would store {path}/{relative} as {stored}, not upstream's {blob}; "
                             "check .gitattributes filters for that path.")

    if (root / path).exists():
        # Every file left here matches the index (checked above), so nothing unsaved is deleted.
        git("rm", "-r", "-q", "--cached", "--ignore-unmatch", "--", path, cwd=root)
        shutil.rmtree(root / path)
    for mode, _blob, relative in files:
        target = root / path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(contents[relative])
        target.chmod(FILE_MODES[mode])
    git("add", "--", path, cwd=root)
    staged = staged_tree(path, root)
    if staged != tree:
        raise SystemExit(f"Staged {path} has tree {staged}, upstream {tag} has {tree}.")
    data["addons"][name] = {"source": repository, "tag": tag, "commit": commit,
                            "upstream_path": upstream_path, "path": path, "tree": tree}
    lock.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    git("add", "--", lock.relative_to(root).as_posix(), cwd=root)
    return data["addons"][name]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="verify every staged add-on against the staged lock")
    mode.add_argument("--verify-source", metavar="NAME", help="compare a lock entry with an upstream checkout")
    mode.add_argument("--update", metavar="NAME", help="vendor an add-on from --source at --tag")
    parser.add_argument("--tag", help="upstream release tag, e.g. v0.1.1")
    parser.add_argument("--source", type=Path, help="local checkout of the upstream repository")
    parser.add_argument("--repository", help="upstream owner/name (required the first time)")
    args = parser.parse_args()
    if args.check:
        problems = check()
    elif args.verify_source:
        if not args.source:
            parser.error("--verify-source needs --source")
        problems = verify_source(args.verify_source, args.source.resolve())
    else:
        if not args.tag or not args.source:
            parser.error("--update needs --tag and --source")
        entry = update(args.update, args.tag, args.source.resolve(), repository=args.repository)
        print(f"Vendored {args.update} {entry['tag']} ({entry['commit'][:12]}) into {entry['path']}; staged with the lock.")
        return 0
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
