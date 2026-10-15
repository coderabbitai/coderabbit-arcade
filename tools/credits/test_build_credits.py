"""Unit tests for build_credits.py. Run: python3 -m unittest discover -s tools/credits -v"""
from __future__ import annotations

import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_credits  # noqa: E402

SAMPLE = """# Asset licenses

## Third-party

| Asset | Path | Creator | License | Used by | Status |
|---|---|---|---|---|---|
| Retro SFX | `Audio/SFX pack/` | Juhani Junkala | CC0 (`INFO.txt`) | SFX | ✅ |
| Forest | `Backgrounds/forest/` | Luis Zuno (@ansimuz); music by Pascal Belisle | Art: public domain. Music: free with credit (`license.txt`). The bundled demo is MIT. | Platformer jump/hurt SFX | ✅ |
| Skyline | `Backgrounds/skyline/` | Fábio | CC0 (`Read.txt`) | Not referenced | ✅ |
| Street | `Backgrounds/street/` | Luis Zuno ([ansimuz.com](https://ansimuz.itch.io/street)) | CC0 (bundled `license.pdf`). Older listing says CC BY 3.0. | Main menu preview | ✅ |
| Valor of Heroes | `Audio/Orbital/Valor of Heroes.mp3` | Trevor Lentz | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) ([OpenGameArt](https://opengameart.org/content/valor-of-heroes), byte-identical). Credit: "Valor of Heroes" by Trevor Lentz. Preserve ShareAlike terms. | Orbital Ops: boss | ⚠️ |
| Frivolous Hero | `Audio/HvV/frivolous_hero.ogg` | Alexandr Zhelanov | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) ([OpenGameArt](https://opengameart.org/content/frivolous-hero)). Credit: "Frivolous Hero" by Alexandr Zhelanov; retain the creator link. | Heroes vs. Villains | ✅ |

### Notes

Not a table.

## Project-original

| Asset | Path | Notes | Status |
|---|---|---|---|
| Hoppy | `Character/` | Made here | ⚠️ |
"""


class BuildCreditsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.data = build_credits.build(SAMPLE)
        self.by_asset = {c["asset"]: c for s in self.data["sections"] for c in s["credits"]}

    def section_of(self, asset: str) -> str:
        return next(s["title"] for s in self.data["sections"] if any(c["asset"] == asset for c in s["credits"]))

    def test_groups_rows_and_skips_unused_assets(self) -> None:
        self.assertEqual([s["title"] for s in self.data["sections"]], ["Music", "Sound effects", "Art"])
        self.assertNotIn("Skyline", self.by_asset)
        self.assertNotIn("Hoppy", self.by_asset, "only the Third-party table is read")
        self.assertEqual(self.section_of("Retro SFX"), "Sound effects")
        self.assertEqual(self.section_of("Forest"), "Sound effects")
        self.assertEqual(self.section_of("Valor of Heroes"), "Music")
        self.assertEqual(self.section_of("Street"), "Art")

    def test_uses_the_stated_credit_line_and_links(self) -> None:
        valor = self.by_asset["Valor of Heroes"]
        self.assertEqual(valor["credit"], '"Valor of Heroes" by Trevor Lentz')
        self.assertEqual(valor["license"], "CC BY-SA 3.0")
        self.assertEqual(valor["license_url"], "https://creativecommons.org/licenses/by-sa/3.0/")
        self.assertEqual(valor["source_url"], "https://opengameart.org/content/valor-of-heroes")
        self.assertEqual(self.by_asset["Frivolous Hero"]["credit"], '"Frivolous Hero" by Alexandr Zhelanov')

    def test_composes_a_credit_and_a_short_license_otherwise(self) -> None:
        sfx = self.by_asset["Retro SFX"]
        self.assertEqual(sfx["credit"], '"Retro SFX" by Juhani Junkala')
        self.assertEqual(sfx["license"], "CC0")
        self.assertEqual(self.by_asset["Forest"]["license"], "Art: public domain. Music: free with credit")
        street = self.by_asset["Street"]
        self.assertEqual(street["license"], "CC0")
        self.assertEqual(street["creator"], "Luis Zuno (ansimuz.com)")
        self.assertEqual(street["source_url"], "https://ansimuz.itch.io/street", "falls back to the creator's link")

    def test_missing_section_or_table_is_an_error(self) -> None:
        with self.assertRaisesRegex(ValueError, "no '## Third-party' section"):
            build_credits.build("# Asset licenses\n")
        with self.assertRaisesRegex(ValueError, "no table"):
            build_credits.build("## Third-party\n\nNothing yet.\n")

    def test_the_real_file_credits_every_cc_by_track(self) -> None:
        markdown = build_credits.LICENSES.read_text(encoding="utf-8")
        credits = {c["asset"]: c for s in build_credits.build(markdown)["sections"] for c in s["credits"]}
        attributed = [row for row in build_credits.table(markdown, "Third-party")
                      if "CC BY" in build_credits.license_name(row["License"])
                      and build_credits.plain(row["Used by"]).lower() != "not referenced"]
        for row in attributed:
            asset = build_credits.plain(row["Asset"])
            self.assertIn(asset, credits, "every CC BY asset in use is credited")
            self.assertIn("CC BY", credits[asset]["license"], asset)
            self.assertIn(" by ", credits[asset]["credit"], asset)

    def test_committed_data_is_current(self) -> None:
        with redirect_stdout(io.StringIO()):
            self.assertEqual(build_credits.main(["--check"]), 0, "run python3 tools/credits/build_credits.py")

    def test_check_reports_stale_data(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            stale = Path(folder) / "asset_credits.json"
            stale.write_text("{}\n", encoding="utf-8")
            with mock.patch.object(build_credits, "OUTPUT", stale), mock.patch.object(build_credits, "ROOT", Path(folder)), \
                    redirect_stderr(io.StringIO()) as err:
                self.assertEqual(build_credits.main(["--check"]), 1)
            self.assertIn("out of date", err.getvalue())
            with mock.patch.object(build_credits, "OUTPUT", stale), mock.patch.object(build_credits, "ROOT", Path(folder)), \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(build_credits.main([]), 0)
                self.assertEqual(build_credits.main(["--check"]), 0)


if __name__ == "__main__":
    unittest.main()
