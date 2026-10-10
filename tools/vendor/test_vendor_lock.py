"""Unit tests for vendor_lock.py, against throwaway upstream and game repositories."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import vendor_lock

ADDON = f"{vendor_lock.ADDONS}/demo"


def run(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def repository(path: Path) -> Path:
    path.mkdir(parents=True)
    run(path, "init", "-q", "-b", "main")
    run(path, "config", "user.email", "test@example.com")
    run(path, "config", "user.name", "Test")
    run(path, "config", "commit.gpgsign", "false")
    return path


class VendorLock(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        base = Path(self.scratch.name)
        self.upstream = repository(base / "upstream")
        for name, text in (("addons/demo/a.gd", "extends RefCounted\n"), ("addons/demo/sub/b.gd", "# b\n"),
                           ("addons/demo/LICENSE", "MIT\n"), ("tests/t.gd", "# not vendored\n")):
            (self.upstream / name).parent.mkdir(parents=True, exist_ok=True)
            (self.upstream / name).write_text(text)
        run(self.upstream, "add", ".")
        run(self.upstream, "commit", "-q", "-m", "v1")
        run(self.upstream, "tag", "v0.1.0")
        self.game = repository(base / "game")
        (self.game / "README.md").write_text("game\n")
        run(self.game, "add", ".")
        run(self.game, "commit", "-q", "-m", "init")
        self.lock = self.game / "tools/vendor/vendor.lock.json"
        self.lock.parent.mkdir(parents=True)

    def tearDown(self):
        self.scratch.cleanup()

    def vendor(self, tag="v0.1.0"):
        return vendor_lock.update("demo", tag, self.upstream, self.game, self.lock, repository="example/kit")

    def check(self):
        return vendor_lock.check(self.game, self.lock)

    def test_update_copies_only_the_addon_and_records_its_tree(self):
        entry = self.vendor()
        self.assertTrue((self.game / ADDON / "sub/b.gd").is_file())
        self.assertFalse((self.game / vendor_lock.ADDONS / "tests").exists())
        self.assertEqual(entry["tag"], "v0.1.0")
        self.assertEqual(entry["tree"], subprocess.run(["git", "rev-parse", "v0.1.0:addons/demo"], cwd=self.upstream,
                                                       capture_output=True, text=True, check=True).stdout.strip())
        self.assertEqual(json.loads(self.lock.read_text())["addons"]["demo"]["source"], "example/kit")
        self.assertEqual(self.check(), [])

    def test_an_edited_copy_fails(self):
        self.vendor()
        (self.game / ADDON / "a.gd").write_text("extends Node\n")
        run(self.game, "add", ADDON)
        self.assertIn("differs from example/kit v0.1.0", self.check()[0])

    def test_an_added_or_removed_file_fails(self):
        self.vendor()
        (self.game / ADDON / "extra.gd").write_text("# extra\n")
        run(self.game, "add", ADDON)
        self.assertEqual(len(self.check()), 1)
        run(self.game, "rm", "-q", "--cached", f"{ADDON}/extra.gd")
        self.assertEqual(self.check(), [])
        run(self.game, "rm", "-q", "--cached", f"{ADDON}/LICENSE")
        self.assertEqual(len(self.check()), 1)

    def test_unlocked_and_missing_addons_fail(self):
        self.vendor()
        other = self.game / vendor_lock.ADDONS / "other/x.gd"
        other.parent.mkdir(parents=True)
        other.write_text("# x\n")
        run(self.game, "add", str(other.relative_to(self.game)))
        self.assertIn("has no entry", self.check()[0])
        run(self.game, "rm", "-q", "-r", "--cached", vendor_lock.ADDONS)
        self.assertTrue(any("not in the repository" in problem for problem in self.check()))

    def test_updating_to_a_new_tag_replaces_the_copy(self):
        self.vendor()
        run(self.upstream, "rm", "-q", "addons/demo/sub/b.gd")
        (self.upstream / "addons/demo/c.gd").write_text("# c\n")
        run(self.upstream, "add", ".")
        run(self.upstream, "commit", "-q", "-m", "v2")
        run(self.upstream, "tag", "v0.2.0")
        entry = vendor_lock.update("demo", "v0.2.0", self.upstream, self.game, self.lock)
        self.assertEqual(entry["source"], "example/kit")
        self.assertFalse((self.game / ADDON / "sub/b.gd").exists())
        self.assertTrue((self.game / ADDON / "c.gd").is_file())
        self.assertEqual(self.check(), [])

    def test_unknown_tags_and_new_addons_without_a_repository_are_refused(self):
        with self.assertRaises(RuntimeError):
            vendor_lock.update("demo", "v9.9.9", self.upstream, self.game, self.lock, repository="example/kit")
        with self.assertRaises(SystemExit):
            vendor_lock.update("demo", "v0.1.0", self.upstream, self.game, self.lock)


if __name__ == "__main__":
    unittest.main()
