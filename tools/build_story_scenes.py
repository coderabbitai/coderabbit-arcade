#!/usr/bin/env python3
"""Pack generated cinematic story masters into deterministic beat'em-up scene PNGs.

The builder never alters a generated master. It cover-crops each selected master
from ``Assets/beatemup-story/*/sources`` to the runtime's 1600 by 900 canvas,
then emits the six scene images, one text-free contact sheet, and provenance
documents rendered from ``refinements.json``.

Run with:
    uvx --with pillow python tools/build_story_scenes.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import tempfile
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
STORY = ROOT / "hoppys-adventure-arcade" / "Assets" / "beatemup-story"
SCENE_SIZE = (1600, 900)
PREVIEW_CELL = (800, 450)
PREVIEW_GUTTER = 16


@dataclass(frozen=True)
class Scene:
    """A runtime story image and its stable output location."""

    mode: str
    scene: str


SCENES = (
    Scene("code_city", "under_siege"),
    Scene("code_city", "pipeline_breached"),
    Scene("code_city", "hoppy_clocks_in"),
    Scene("heroes", "situation"),
    Scene("heroes", "complication"),
    Scene("heroes", "send_in_the_rabbit"),
)


def expected_scene_ids() -> list[tuple[str, str]]:
    return [(scene.mode, scene.scene) for scene in SCENES]


def checked_relative_path(value: object, label: str) -> Path:
    """Accept only a non-empty repository-relative provenance path."""
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label}: expected a non-empty path string")
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{label}: path must stay inside beatemup-story")
    return path


def checked_source_path(value: object, label: str, mode: str) -> Path:
    """Accept only a generated master below this scene mode's sources directory."""
    path = checked_relative_path(value, label)
    source_dir = Path(mode) / "sources"
    if path.parts[: len(source_dir.parts)] != source_dir.parts or len(path.parts) == len(
        source_dir.parts
    ):
        raise ValueError(f"{label}: path must name a file inside {source_dir.as_posix()}/")
    return path


def read_records() -> dict[tuple[str, str], dict[str, object]]:
    """Read one complete, data-owned provenance record for every scene."""
    source = STORY / "refinements.json"
    if not source.exists():
        raise FileNotFoundError(f"missing generation history: {source}")
    payload = json.loads(source.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError(f"{source}: expected a list")

    expected = expected_scene_ids()
    actual: list[tuple[str, str]] = []
    records: dict[tuple[str, str], dict[str, object]] = {}
    for index, record in enumerate(payload):
        label = f"{source} record {index}"
        if not isinstance(record, dict):
            raise ValueError(f"{label}: expected an object")
        mode, scene = record.get("mode"), record.get("scene")
        if not isinstance(mode, str) or not isinstance(scene, str):
            raise ValueError(f"{label}: records require string mode and scene")
        scene_id = (mode, scene)
        actual.append(scene_id)
        if scene_id in records:
            raise ValueError(f"{source}: duplicate provenance record for {mode}/{scene}")
        records[scene_id] = record

    missing = [f"{mode}/{scene}" for mode, scene in expected if (mode, scene) not in records]
    unknown = [f"{mode}/{scene}" for mode, scene in actual if (mode, scene) not in expected]
    if missing or unknown or len(records) != len(expected):
        raise ValueError(
            f"{source}: needs exactly one record per scene; missing {missing}, unknown {unknown}"
        )

    for scene_id in expected:
        validate_record(records[scene_id], f"{source}: {scene_id[0]}/{scene_id[1]}", scene_id[0])
    return records


def validate_record(record: dict[str, object], label: str, mode: str) -> None:
    """Validate enough provenance to keep source choice and prompt history auditable."""
    selected_paths = {
        key: checked_source_path(record.get(key), f"{label} {key}", mode)
        for key in ("master", "original_master")
    }
    for key in ("change", "prompt"):
        if not isinstance(record.get(key), str) or not record[key]:
            raise ValueError(f"{label}: {key} must be a non-empty string")
    regenerations = record.get("regenerations")
    if not isinstance(regenerations, int) or isinstance(regenerations, bool) or regenerations < 0:
        raise ValueError(f"{label}: regenerations must be a non-negative integer")
    masters = record.get("retained_masters")
    if not isinstance(masters, list) or not masters:
        raise ValueError(f"{label}: retained_masters must be a non-empty list")
    master_names = [
        checked_source_path(value, f"{label} retained_masters", mode) for value in masters
    ]
    if len(set(master_names)) != len(master_names):
        raise ValueError(f"{label}: retained_masters must not repeat paths")
    if selected_paths["master"] not in master_names:
        raise ValueError(f"{label}: selected master must be retained")
    if selected_paths["original_master"] not in master_names:
        raise ValueError(f"{label}: original master must be retained")

    history = record.get("prompt_history")
    if not isinstance(history, list) or len(history) != regenerations + 1:
        raise ValueError(f"{label}: prompt_history must have generation zero through regeneration count")
    for generation, entry in enumerate(history):
        if not isinstance(entry, dict) or entry.get("generation") != generation:
            raise ValueError(f"{label}: prompt_history must use consecutive generation numbers")
        prompt = entry.get("prompt")
        if not isinstance(prompt, str) or not prompt:
            raise ValueError(f"{label}: each prompt_history entry needs an exact prompt")
    if record["prompt"] != history[-1]["prompt"]:
        raise ValueError(f"{label}: prompt must match the selected generation's exact prompt")


def cover_crop(master: Image.Image) -> Image.Image:
    """Scale a master down or up to cover the runtime frame, then center-crop it."""
    source = master.convert("RGBA")
    if source.width < 2 or source.height < 2:
        raise ValueError("generated master must be at least 2 by 2 pixels")
    scale = max(SCENE_SIZE[0] / source.width, SCENE_SIZE[1] / source.height)
    resized_size = (
        max(SCENE_SIZE[0], math.ceil(source.width * scale)),
        max(SCENE_SIZE[1], math.ceil(source.height * scale)),
    )
    resized = source.resize(resized_size, Image.Resampling.LANCZOS)
    left = (resized.width - SCENE_SIZE[0]) // 2
    top = (resized.height - SCENE_SIZE[1]) // 2
    return resized.crop((left, top, left + SCENE_SIZE[0], top + SCENE_SIZE[1]))


def render_preview(packed: dict[tuple[str, str], Image.Image]) -> Image.Image:
    """Render a text-free 3 by 2 review contact sheet in the story order."""
    columns, rows = 3, 2
    width = columns * PREVIEW_CELL[0] + (columns + 1) * PREVIEW_GUTTER
    height = rows * PREVIEW_CELL[1] + (rows + 1) * PREVIEW_GUTTER
    preview = Image.new("RGBA", (width, height), (10, 16, 26, 255))
    for index, scene in enumerate(SCENES):
        column, row = index % columns, index // columns
        thumbnail = packed[(scene.mode, scene.scene)].resize(PREVIEW_CELL, Image.Resampling.LANCZOS)
        x = PREVIEW_GUTTER + column * (PREVIEW_CELL[0] + PREVIEW_GUTTER)
        y = PREVIEW_GUTTER + row * (PREVIEW_CELL[1] + PREVIEW_GUTTER)
        preview.alpha_composite(thumbnail, (x, y))
    return preview


def prompts_text(records: dict[tuple[str, str], dict[str, object]]) -> str:
    """Render the committed prompt history without inventing or omitting a scene."""
    sections = [
        "# Beat'em-up story illustration prompts\n\n",
        "Built-in image generation, October 8, 2026. Each scene has exactly one provenance record in "
        "`refinements.json`; selected and superseded masters remain untouched in `sources/`. "
        "`tools/build_story_scenes.py` only cover-crops, scales, packs and previews that artwork.\n",
    ]
    for scene in SCENES:
        record = records[(scene.mode, scene.scene)]
        selected = record["master"]
        retained = ", ".join(f"`{path}`" for path in record["retained_masters"])
        sections.extend(
            (
                f"\n## {scene.mode}: {scene.scene}\n\n",
                f"Selected master: `{selected}`. Retained masters: {retained}.\n\n",
                "### Exact generation prompt history\n",
            )
        )
        for entry in record["prompt_history"]:
            sections.extend((f"\n#### Generation {entry['generation']}\n\n", f"{entry['prompt']}\n"))
        sections.extend(
            (
                "\n### Refinements\n\n",
                f"Regenerations: {record['regenerations']}. {record['change']}\n",
            )
        )
    return "".join(sections)


def readme_text() -> str:
    """Document the isolated runtime package and its reproducible build contract."""
    return """# Beat'em-up story illustrations

Six painted 16-bit cinematic scenes used by the Code City Brawl and Heroes versus Villains intros. The runtime uses the packed 1600 × 900 PNGs for a slow pan and zoom; key action is intentionally composed in the central 80 percent of each frame.

| Mode | Scenes |
|---|---|
| Code City Brawl | `code_city/under_siege.png`, `code_city/pipeline_breached.png`, `code_city/hoppy_clocks_in.png` |
| Heroes versus Villains | `heroes/situation.png`, `heroes/complication.png`, `heroes/send_in_the_rabbit.png` |

## Provenance

The untouched generated masters live under each mode's `sources/` directory. `refinements.json` holds exactly one complete record per scene: selected and retained master paths, every exact generation prompt, regeneration count and the reason for any refinement. `PROMPTS.md` is rendered from that record by the builder and must not be edited by hand.

The scenes were made with built-in image generation and need brand sign-off plus the project asset terms. Source masters are excluded from game exports. Licensing is recorded in the repository's `ASSETS_LICENSES.md`.

## Rebuild

```sh
uvx --with pillow python tools/build_story_scenes.py
```

The builder validates all six provenance records before writing anything. It center cover-crops and scales only the selected masters, then atomically replaces the six runtime PNGs, `preview.png`, `PROMPTS.md`, and this README. Re-running it from the same sources produces byte-identical output.

`preview.png` is the text-free contact sheet, in story order: Code City on the top row, Heroes versus Villains on the bottom row.
"""


def png_bytes(image: Image.Image) -> bytes:
    """Encode deterministic PNG bytes once all artwork is already validated in memory."""
    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def atomic_write(path: Path, payload: bytes) -> None:
    """Replace one generated output without exposing a partially-written file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def build() -> None:
    """Validate every source and compose every result before writing final files."""
    records = read_records()
    packed: dict[tuple[str, str], Image.Image] = {}
    outputs: list[tuple[Path, bytes]] = []
    for scene in SCENES:
        record = records[(scene.mode, scene.scene)]
        master = STORY / checked_relative_path(record["master"], f"{scene.mode}/{scene.scene} master")
        if not master.exists():
            raise FileNotFoundError(f"missing selected generated master: {master}")
        for retained in record["retained_masters"]:
            retained_path = STORY / checked_relative_path(retained, f"{scene.mode}/{scene.scene} retained master")
            if not retained_path.exists():
                raise FileNotFoundError(f"missing retained generated master: {retained_path}")
        with Image.open(master) as source:
            packed[(scene.mode, scene.scene)] = cover_crop(source)

    for scene in SCENES:
        path = STORY / scene.mode / f"{scene.scene}.png"
        outputs.append((path, png_bytes(packed[(scene.mode, scene.scene)])))
    outputs.append((STORY / "preview.png", png_bytes(render_preview(packed))))
    outputs.append((STORY / "PROMPTS.md", prompts_text(records).encode("utf-8")))
    outputs.append((STORY / "README.md", readme_text().encode("utf-8")))

    for path, payload in outputs:
        atomic_write(path, payload)
        print(f"packed {path.relative_to(STORY)} sha256={hashlib.sha256(payload).hexdigest()}")


def main() -> None:
    argparse.ArgumentParser(description=__doc__).parse_args()
    build()


if __name__ == "__main__":
    main()
