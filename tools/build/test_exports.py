"""Regression checks for release packaging and template cache upgrades."""
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import export_game
import fetch_godot


class Packaging(unittest.TestCase):
    def test_web_archive_contains_every_runtime_file(self):
        target = next(t for t in export_game.TARGETS if t.platform == "web")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stage = root / "stage"
            stage.mkdir()
            names = ["index.html", "index.js", "index.wasm", "index.pck", "index.audio.worklet.js"]
            for name in names:
                (stage / name).write_text(name)
            artifact = root / "web.zip"
            export_game.package(target, stage / "index.html", artifact)
            with zipfile.ZipFile(artifact) as bundle:
                self.assertEqual(set(bundle.namelist()), set(names + ["README.txt"]))
                self.assertIn(b"localhost:8000", bundle.read("README.txt"))
            (stage / "index.wasm").unlink()
            with self.assertRaisesRegex(SystemExit, "index.wasm"):
                export_game.package(target, stage / "index.html", artifact)

    def test_desktop_companion_files_and_executable_mode(self):
        target = next(t for t in export_game.TARGETS if t.platform == "linux")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stage = root / "stage"
            stage.mkdir()
            (stage / target.export_name).write_bytes(b"binary")
            (stage / "game.pck").write_bytes(b"resources")
            artifact = root / "linux.zip"
            export_game.package(target, stage / target.export_name, artifact)
            with zipfile.ZipFile(artifact) as bundle:
                self.assertEqual(set(bundle.namelist()), {target.export_name, "game.pck"})
                self.assertEqual((bundle.getinfo(target.export_name).external_attr >> 16) & 0o777, 0o755)


class TemplateCache(unittest.TestCase):
    def test_existing_marker_does_not_skip_newly_required_templates(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            destination = root / "installed"
            destination.mkdir()
            name = "Godot_vtest_export_templates.tpz"
            lock = {"version": "test", "sha512": {name: "verified"},
                    "templates": ["web_nothreads_release.zip"]}
            (destination / ".verified").write_text("verified")
            archive = root / name
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("templates/web_nothreads_release.zip", b"template")
            with patch.object(fetch_godot, "fetch", return_value=archive) as fetch:
                fetch_godot.install_templates(lock, root, destination)
                fetch.assert_called_once()
            self.assertEqual((destination / "web_nothreads_release.zip").read_bytes(), b"template")
            with patch.object(fetch_godot, "fetch") as fetch:
                fetch_godot.install_templates(lock, root, destination)
                fetch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
