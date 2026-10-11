"""Pack Hoppy's combat and victory masters without changing the original sixteen cells."""

import json
from pathlib import Path

from PIL import Image


ROOT = (
    Path(__file__).resolve().parents[1]
    / "hoppys-adventure-arcade/Assets/code-city-brawl-player"
)
CELL = 96
PIVOT = (48, 86)
CLIPS = {
    "walk_up": ([0, 1], 8, True),
    "walk_down": ([2, 3], 8, True),
    "jab": ([4, 5], 12, False),
    "swing": ([6, 7], 9, False),
    "kick": ([8, 9, 10], 10, False),
    "pickup": ([11, 12], 8, False),
    "hurt": ([13], 1, False),
    "jump": ([14], 1, False),
    "idle": ([15], 1, True),
    "victory": ([16, 17, 18], 5, True),
}


def cut_cells(image: Image.Image, columns: int, rows: int) -> list[Image.Image]:
    cuts = []
    for i in range(columns * rows):
        cell = image.crop(
            (
                round(i % columns * image.width / columns),
                round(i // columns * image.height / rows),
                round((i % columns + 1) * image.width / columns),
                round((i // columns + 1) * image.height / rows),
            )
        )
        bounds = cell.getchannel("A").point(lambda x: 255 if x > 32 else 0).getbbox()
        if bounds is None:
            raise ValueError(f"Empty source cell {i}")
        cuts.append(cell.crop(bounds))
    return cuts


def pack() -> None:
    with Image.open(ROOT / "source.png") as source:
        cuts = cut_cells(source.convert("RGBA"), 4, 4)
    with Image.open(ROOT / "victory-source.png") as source:
        victory = cut_cells(source.convert("RGBA"), 3, 1)
    atlas = Image.new("RGBA", (CELL * 4, CELL * 5))
    for frames, first in [(cuts, 0), (victory, 16)]:
        # One scale per master preserves the pose variation. Feet remain at the old pivot.
        scale = 68 / max(cell.height for cell in frames)
        for index, cell in enumerate(frames, first):
            cell = cell.resize(
                (round(cell.width * scale), round(cell.height * scale)),
                Image.Resampling.NEAREST,
            )
            atlas.alpha_composite(
                cell,
                (
                    index % 4 * CELL + (CELL - cell.width) // 2,
                    index // 4 * CELL + PIVOT[1] - cell.height,
                ),
            )
    atlas.save(ROOT / "combat.png")
    lines = [
        '[gd_resource type="SpriteFrames" load_steps=21 format=3]',
        '[ext_resource type="Texture2D" path="combat.png" id="1"]',
    ]
    for index in range(19):
        lines.extend(
            [
                f'[sub_resource type="AtlasTexture" id="F{index}"]',
                'atlas = ExtResource("1")',
                f"region = Rect2({index % 4 * CELL}, {index // 4 * CELL}, {CELL}, {CELL})",
            ]
        )
    animations = []
    for name, (ids, fps, loop) in CLIPS.items():
        refs = ", ".join(
            '{"duration":1.0,"texture":SubResource("F%d")}' % index for index in ids
        )
        animations.append(
            '{"frames":[%s],"loop":%s,"name":&"%s","speed":%s}'
            % (refs, str(loop).lower(), name, float(fps))
        )
    lines.extend(["[resource]", "animations = [" + ",\n".join(animations) + "]"])
    (ROOT / "combat.tres").write_text("\n".join(lines) + "\n")
    (ROOT / "manifest.json").write_text(
        json.dumps(
            {
                "cell": [CELL, CELL],
                "pivot": list(PIVOT),
                "facing": "right",
                "clips": CLIPS,
            },
            indent=2,
        )
        + "\n"
    )
    print("Built 19 combat cells including the three-frame victory loop")


if __name__ == "__main__":
    pack()
