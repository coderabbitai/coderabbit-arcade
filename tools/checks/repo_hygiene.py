"""Keep local machine paths and internal links out of the repository.

Usage:
    python3 tools/checks/repo_hygiene.py --staged    # what is about to be committed (pre-commit hook)
    python3 tools/checks/repo_hygiene.py --all       # every tracked file (CI)

This repository is headed for a public release, and a pushed commit stays in history even if a
later commit removes it. So the same check runs locally before commit (`.githooks/pre-commit`)
and again in CI. It flags home-directory paths (macOS, Linux, Windows) and links to internal
documents and chats (Google Docs/Drive, Slack, Notion). Standard library only.
"""
from __future__ import annotations

import argparse
import fnmatch
import re
import subprocess
import sys
from dataclasses import dataclass

RULES = (
    ("local machine path", re.compile(
        r"/Users/[A-Za-z0-9._-]+/|/home/[a-z][a-z0-9._-]*/|[A-Za-z]:(?:\\{1,2}|/)Users(?:\\{1,2}|/)")),
    ("internal document link", re.compile(r"docs\.google\.com|drive\.google\.com|app\.notion\.com|notion\.so/")),
    ("internal chat link", re.compile(r"[a-z0-9-]+\.slack\.com/archives")),
)
# Paths that legitimately contain a match. Keep each entry justified.
ALLOWED = (
    # Vendored Sunny Land TexturePacker files keep their upstream author's export path.
    "hoppys-adventure-arcade/Assets/Backgrounds/Sunny-land-forest-files/demo/assets/atlas/*.tps",
    # This checker and its tests contain the patterns themselves.
    "tools/checks/*.py",
)


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str
    text: str


def scan(path: str, content: str) -> list[Finding]:
    if any(fnmatch.fnmatch(path, pattern) for pattern in ALLOWED):
        return []
    findings = []
    for number, line in enumerate(content.splitlines(), 1):
        for rule, pattern in RULES:
            if pattern.search(line):
                findings.append(Finding(path, number, rule, line.strip()[:160]))
    return findings


def git(*args: str) -> bytes:
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def text_or_none(blob: bytes) -> str | None:
    """Skip binary files the same way Git does: a NUL byte in the first 8 KB."""
    if b"\0" in blob[:8000]:
        return None
    return blob.decode("utf-8", errors="replace")


def staged_files() -> list[tuple[str, str]]:
    names = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").decode().split("\0")
    files = []
    for name in filter(None, names):
        content = text_or_none(git("show", f":{name}"))
        if content is not None:
            files.append((name, content))
    return files


def tracked_files() -> list[tuple[str, str]]:
    names = git("ls-files", "-z").decode().split("\0")
    files = []
    for name in filter(None, names):
        try:
            with open(name, "rb") as handle:
                content = text_or_none(handle.read())
        except FileNotFoundError:  # deleted in the working tree but still tracked
            continue
        if content is not None:
            files.append((name, content))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    scope = parser.add_mutually_exclusive_group(required=True)
    scope.add_argument("--staged", action="store_true", help="check the staged versions of changed files")
    scope.add_argument("--all", action="store_true", help="check every tracked file")
    args = parser.parse_args()

    files = staged_files() if args.staged else tracked_files()
    findings = [finding for path, content in files for finding in scan(path, content)]
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.rule}: {finding.text}", file=sys.stderr)
    if findings:
        print(f"\n{len(findings)} problem(s). Remove local paths and internal links before committing; "
              "describe sources in words instead (e.g. 'internal GDD').", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
