"""Unit tests for vendor_lock.py, against throwaway upstream and game repositories."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import vendor_lock

ADDON = f"{vendor_lock.ADDONS}/demo"


def run(cwd: Path, *args: str) -> None:
    # Throwaway repositories must not inherit a hook's GIT_DIR or GIT_INDEX_FILE.
    env = {k: v for k, v in os.environ.items() if k not in vendor_lock.REPOSITORY_VARIABLES}
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, env=env)


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

    def test_check_reads_the_staged_lock(self):
        self.vendor()
        locked = json.loads(self.lock.read_text())
        locked["addons"]["demo"]["tree"] = "0" * 40
        self.lock.write_text(json.dumps(locked))
        self.assertEqual(self.check(), [], "an unstaged lock edit is not what the commit contains")
        run(self.game, "add", str(self.lock.relative_to(self.game)))
        self.assertEqual(len(self.check()), 1, "once staged, the edited lock fails")

    def test_verify_source_catches_a_lock_rewritten_to_match_an_edit(self):
        self.vendor()
        self.assertEqual(vendor_lock.verify_source("demo", self.upstream, self.game, self.lock), [])
        (self.game / ADDON / "a.gd").write_text("extends Node\n")
        run(self.game, "add", ADDON)
        locked = json.loads(self.lock.read_text())
        locked["addons"]["demo"]["tree"] = vendor_lock.staged_tree(ADDON, self.game)
        self.lock.write_text(json.dumps(locked))
        run(self.game, "add", str(self.lock.relative_to(self.game)))
        self.assertEqual(self.check(), [], "the offline check only proves the copy matches its entry")
        problems = vendor_lock.verify_source("demo", self.upstream, self.game, self.lock)
        self.assertTrue(any("is tree" in problem for problem in problems), problems)
        # Restoring an honest lock in the working tree does not hide the staged one.
        honest = json.loads(self.lock.read_text())
        honest["addons"]["demo"]["tree"] = vendor_lock.resolve(self.upstream, "v0.1.0", "addons/demo")[1]
        self.lock.write_text(json.dumps(honest))
        self.assertTrue(vendor_lock.verify_source("demo", self.upstream, self.game, self.lock),
                        "verify_source reads the staged lock")

    def test_export_attributes_upstream_do_not_change_the_copy(self):
        (self.upstream / ".gitattributes").write_text("addons/demo/LICENSE export-ignore\n")
        run(self.upstream, "add", ".")
        run(self.upstream, "commit", "-q", "-m", "attributes")
        run(self.upstream, "tag", "v0.1.1")
        self.vendor("v0.1.1")
        self.assertTrue((self.game / ADDON / "LICENSE").is_file())
        self.assertEqual(self.check(), [])

    def test_a_repository_that_would_rewrite_a_file_is_refused_before_changes(self):
        self.vendor()
        (self.upstream / "addons/demo/a.gd").write_bytes(b"extends RefCounted\r\n")
        run(self.upstream, "add", ".")
        run(self.upstream, "commit", "-q", "-m", "crlf")
        run(self.upstream, "tag", "v0.2.0")
        (self.game / ".gitattributes").write_text("* text=auto eol=lf\n")
        run(self.game, "add", ".gitattributes")
        run(self.game, "commit", "-q", "-m", "attributes")
        with self.assertRaises(SystemExit) as raised:
            vendor_lock.update("demo", "v0.2.0", self.upstream, self.game, self.lock)
        self.assertIn("would store", str(raised.exception.code))
        self.assertEqual((self.game / ADDON / "a.gd").read_text(), "extends RefCounted\n", "the old copy is intact")
        self.assertEqual(self.check(), [])

    def test_untracked_files_in_the_destination_are_never_deleted(self):
        self.vendor()
        run(self.game, "commit", "-q", "-m", "vendor")
        notes = self.game / ADDON / "notes.txt"
        notes.write_text("mine\n")
        with self.assertRaises(SystemExit) as raised:
            self.vendor()
        self.assertIn("untracked or unstaged", str(raised.exception.code))
        self.assertTrue(notes.is_file())
        notes.unlink()
        (self.game / ADDON / "a.gd").write_text("# local edit\n")
        with self.assertRaises(SystemExit):
            self.vendor()
        self.assertEqual((self.game / ADDON / "a.gd").read_text(), "# local edit\n", "unstaged edits survive")

    def test_hook_variables_do_not_redirect_the_upstream(self):
        previous = os.environ.get("GIT_DIR")
        os.environ["GIT_DIR"] = str(self.game / ".git")
        try:
            commit, _ = vendor_lock.resolve(self.upstream, "v0.1.0", "addons/demo")
        finally:
            if previous is None:
                os.environ.pop("GIT_DIR")
            else:
                os.environ["GIT_DIR"] = previous
        self.assertEqual(commit, subprocess.run(["git", "rev-parse", "v0.1.0^{commit}"], cwd=self.upstream,
                                                capture_output=True, text=True, check=True).stdout.strip())

    def test_unknown_tags_and_new_addons_without_a_repository_are_refused(self):
        with self.assertRaises(RuntimeError):
            vendor_lock.update("demo", "v9.9.9", self.upstream, self.game, self.lock, repository="example/kit")
        with self.assertRaises(SystemExit):
            vendor_lock.update("demo", "v0.1.0", self.upstream, self.game, self.lock)


if __name__ == "__main__":
    unittest.main()
