"""Unit tests for repo_hygiene.py."""
import unittest

import repo_hygiene


def rules(path, text):
    return [finding.rule for finding in repo_hygiene.scan(path, text)]


class Scan(unittest.TestCase):
    def test_home_directory_paths(self):
        for text in ("/Users/alex/.codex/out.png", "/home/alex/game/build", r"C:\Users\alex\Desktop",
                     r'"C:\\Users\\alex\\x"', "C:/Users/alex/x"):
            self.assertEqual(rules("notes.md", text), ["local machine path"], text)

    def test_internal_links(self):
        self.assertEqual(rules("a.md", "https://docs.google.com/document/d/abc/edit"), ["internal document link"])
        self.assertEqual(rules("a.md", "https://drive.google.com/file/d/abc"), ["internal document link"])
        self.assertEqual(rules("a.md", "https://app.notion.com/p/abc"), ["internal document link"])
        self.assertEqual(rules("a.md", "https://acme.slack.com/archives/C123/p456"), ["internal chat link"])

    def test_ordinary_text_passes(self):
        for text in ("res://Assets/Audio/Main Menu/track.ogg", "See the internal GDD.", "users/guide.md",
                     "https://github.com/coderabbitai/coderabbit-arcade", "https://docs.godotengine.org/en/stable/"):
            self.assertEqual(rules("a.md", text), [], text)

    def test_line_numbers_and_allowed_paths(self):
        findings = repo_hygiene.scan("a.md", "ok\nsee /Users/alex/x\n")
        self.assertEqual([(f.line, f.rule) for f in findings], [(2, "local machine path")])
        vendored = "hoppys-adventure-arcade/Assets/Backgrounds/Sunny-land-forest-files/demo/assets/atlas/x.tps"
        self.assertEqual(rules(vendored, "/Users/author/x"), [])

    def test_binary_content_is_skipped(self):
        self.assertIsNone(repo_hygiene.text_or_none(b"PNG\0/Users/alex/"))
        self.assertEqual(repo_hygiene.text_or_none(b"plain"), "plain")


if __name__ == "__main__":
    unittest.main()
