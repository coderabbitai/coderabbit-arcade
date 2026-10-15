"""Generate the in-game asset credits from ASSETS_LICENSES.md, so the two can't drift.

Usage:
    python3 tools/credits/build_credits.py           # rewrite the credits data
    python3 tools/credits/build_credits.py --check   # exit 1 if it is out of date (CI)

Every row of the "Third-party" table becomes one credit, except assets the game doesn't use
("Not referenced"). A credit carries the asset's title, creator and license, a source and license
link, and the attribution line the table asks for ("Credit: ..."), or "<title>" by <creator>.
Rows are grouped into Music, Sound effects and Art. The credits screen
(hoppys-adventure-arcade/scenes/credits/) shows these after the hand-written sections in
credits.json. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LICENSES = ROOT / "ASSETS_LICENSES.md"
OUTPUT = ROOT / "hoppys-adventure-arcade" / "scenes" / "credits" / "asset_credits.json"
SECTIONS = ("Music", "Sound effects", "Art")

LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
PARENTHESES = re.compile(r"\s*\([^()]*\)")
LABELLED = re.compile(r"^[A-Z][A-Za-z ]*: ")
CREDIT = re.compile(r"Credit: (.+?)(?:;|\.(?:\s|$))")


def plain(text: str) -> str:
    """Markdown cell text without links, code spans or bold."""
    return LINK.sub(r"\1", text).replace("`", "").replace("**", "").strip()


def table(markdown: str, heading: str) -> list[dict[str, str]]:
    """The rows of the first table under `## <heading>`, keyed by column name (raw cell text)."""
    lines = markdown.splitlines()
    try:
        start = lines.index(f"## {heading}")
    except ValueError:
        raise ValueError(f"no '## {heading}' section") from None
    rows: list[list[str]] = []
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        if line.startswith("|"):
            rows.append([cell.strip() for cell in line.strip().strip("|").split("|")])
        elif rows:
            break
    if len(rows) < 2:
        raise ValueError(f"no table under '## {heading}'")
    header, body = rows[0], rows[2:]
    return [dict(zip(header, row)) for row in body if len(row) == len(header)]


def license_name(cell: str) -> str:
    """The license in a License cell: its first sentence, without parenthetical notes. Sentences
    shaped "Label: value" stay together, as in "Art: public domain. Music: free with credit"."""
    sentences = PARENTHESES.sub("", plain(cell)).split(". ")
    name = sentences[0]
    if LABELLED.match(name):
        for sentence in sentences[1:]:
            if not LABELLED.match(sentence):
                break
            name += ". " + sentence
    return name.rstrip(".").strip()


def credit(row: dict[str, str]) -> dict[str, str]:
    asset, creator, cell = plain(row["Asset"]), plain(row["Creator"]), row["License"]
    links = [url for _, url in LINK.findall(cell)]
    license_url = next((url for url in links if "creativecommons.org" in url), "")
    source_url = next((url for url in links if "creativecommons.org" not in url), "")
    if not source_url:
        source_url = next((url for _, url in LINK.findall(row["Creator"])), "")
    stated = CREDIT.search(plain(cell))
    return {
        "asset": asset,
        "credit": stated.group(1).strip() if stated else f"\"{asset}\" by {creator}",
        "creator": creator,
        "license": license_name(cell),
        "license_url": license_url,
        "source_url": source_url,
        "used_by": plain(row["Used by"]),
    }


def section(row: dict[str, str]) -> str:
    path, used_by = plain(row["Path"]), plain(row["Used by"])
    if "SFX" in used_by.split() or used_by.endswith("SFX"):
        return "Sound effects"
    return "Music" if path.startswith("Audio/") else "Art"


def build(markdown: str) -> dict:
    grouped: dict[str, list[dict[str, str]]] = {name: [] for name in SECTIONS}
    for row in table(markdown, "Third-party"):
        if plain(row["Used by"]).lower() == "not referenced":
            continue
        grouped[section(row)].append(credit(row))
    return {
        "generated_by": "tools/credits/build_credits.py from ASSETS_LICENSES.md; do not edit by hand",
        "sections": [{"title": name, "credits": grouped[name]} for name in SECTIONS if grouped[name]],
    }


def render(data: dict) -> str:
    return json.dumps(data, indent=1, ensure_ascii=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if the credits data is out of date")
    args = parser.parse_args(argv)
    expected = render(build(LICENSES.read_text(encoding="utf-8")))
    current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
    if args.check:
        if current != expected:
            print(f"{OUTPUT.relative_to(ROOT)} is out of date with ASSETS_LICENSES.md; "
                  "run python3 tools/credits/build_credits.py", file=sys.stderr)
            return 1
        print("Credits match ASSETS_LICENSES.md.")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(expected, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
