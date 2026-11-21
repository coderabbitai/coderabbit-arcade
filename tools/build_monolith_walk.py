"""Add a walk cycle to the Legacy Monolith sheets.

The generated Enchanted Repo pack (tools/build_enchanted_asset_pack.py) gave the boss no walking
frames, so it slid across the arena in its idle pose. This appends one row of four `walk` frames
to `legacy_monolith.png` and, for the two armor states, `cracked_walk` and `bare_walk` rows to
`monolith_armor.png`, then registers them in `manifest.json` and the SpriteFrames `.tres` files.

Each walk frame is the matching idle frame leaning a few degrees about the pivot (the feet) and
lifted a little on the off-steps, which reads as a heavy stone golem lumbering: lean left, rise,
lean right, rise. Rotation is nearest-neighbour about the pivot and the alpha is re-thresholded,
so the frames stay crisp pixel art. The build is deterministic and idempotent: a sheet that
already has its walk row is left alone.

Usage, from the repository root:
    python3 tools/build_monolith_walk.py
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

PACK = Path("hoppys-adventure-arcade/Assets/enchanted-repo-assets-only/enchanted_repo")
LEANS = (-3.0, 0.0, 3.0, 0.0)
LIFTS = (0, -5, 0, -5)
WALK_FPS = 6

# sheet -> list of (walk clip, idle clip to derive it from)
WALKS = {
    "legacy_monolith": [("walk", "idle")],
    "monolith_armor": [("cracked_walk", "cracked_idle"), ("bare_walk", "bare_idle")],
}


def clip_frames(atlas: dict, name: str) -> list[int]:
    for clip in atlas["clips"]:
        if clip["name"] == name:
            return list(clip["frames"])
    raise KeyError(name)


def walk_frame(
    cell: Image.Image, pivot: tuple[int, int], lean: float, lift: int
) -> Image.Image:
    """One walk frame: the idle cell leaned `lean` degrees about `pivot` and raised `lift` px."""
    turned = cell.rotate(lean, resample=Image.NEAREST, center=pivot)
    frame = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    frame.paste(turned, (0, lift))
    alpha = frame.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    frame.putalpha(alpha)
    return frame


def add_walks(sheet: str, manifest: dict) -> bool:
    atlas = manifest["atlases"][sheet]
    if all(any(c["name"] == walk for c in atlas["clips"]) for walk, _ in WALKS[sheet]):
        print(f"{sheet}: walk rows already present")
        return False
    cell = atlas["cell"][0]
    columns, rows = atlas["grid"]
    pivot = tuple(atlas["pivot"])
    png = PACK / atlas["file"]
    image = Image.open(png).convert("RGBA")
    new_rows = len(WALKS[sheet])
    grown = Image.new(
        "RGBA", (image.width, image.height + cell * new_rows), (0, 0, 0, 0)
    )
    grown.paste(image, (0, 0))
    for row_offset, (walk, idle) in enumerate(WALKS[sheet]):
        idle_frames = clip_frames(atlas, idle)
        indices = []
        for i in range(columns):
            source = atlas["frames"][idle_frames[i % len(idle_frames)]]
            x, y, w, h = source["rect"]
            frame = walk_frame(
                image.crop((x, y, x + w, y + h)), pivot, LEANS[i], LIFTS[i]
            )
            index = len(atlas["frames"])
            fx, fy = i * cell, (rows + row_offset) * cell
            grown.paste(frame, (fx, fy))
            left, top, right, bottom = frame.getbbox()
            atlas["frames"].append(
                {
                    "index": index,
                    "rect": [fx, fy, cell, cell],
                    "visible_bounds": [left, top, right, bottom],
                }
            )
            atlas["source_rects_ltrb"].append(
                list(atlas["source_rects_ltrb"][idle_frames[i % len(idle_frames)]])
            )
            indices.append(index)
        atlas["clips"].append(
            {"name": walk, "frames": indices, "fps": WALK_FPS, "loop": True}
        )
    atlas["grid"] = [columns, rows + new_rows]
    grown.save(png, optimize=True)
    write_tres(PACK / atlas["resource"], atlas, cell)
    print(
        f"{sheet}: added {new_rows * columns} walk frames ({image.size} -> {grown.size})"
    )
    return True


def write_tres(path: Path, atlas: dict, cell: int) -> None:
    """Rewrite the SpriteFrames resource from the manifest, in the pack builder's own format."""
    frames = atlas["frames"]
    text = [
        f'[gd_resource type="SpriteFrames" load_steps={len(frames) + 2} format=3]',
        f'\n[ext_resource type="Texture2D" path="{atlas["file"]}" id="1"]',
    ]
    for frame in frames:
        x, y, _, _ = frame["rect"]
        text += [
            f'\n[sub_resource type="AtlasTexture" id="F{frame["index"]}"]',
            'atlas = ExtResource("1")',
            f"region = Rect2({x}, {y}, {cell}, {cell})",
            "filter_clip = true",
        ]
    animations = []
    for clip in atlas["clips"]:
        refs = ", ".join(
            '{"duration": 1.0, "texture": SubResource("F%d")}' % i
            for i in clip["frames"]
        )
        loop = "true" if clip["loop"] else "false"
        animations.append(
            '{"frames": [%s], "loop": %s, "name": &"%s", "speed": %.1f}'
            % (refs, loop, clip["name"], clip["fps"])
        )
    text += ["\n[resource]", "animations = [\n" + ",\n".join(animations) + "\n]"]
    path.write_text("\n".join(text) + "\n")


def main() -> None:
    manifest_path = PACK / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    changed = False
    for sheet in WALKS:
        changed = add_walks(sheet, manifest) or changed
    if changed:
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    total_frames = sum(len(a["frames"]) for a in manifest["atlases"].values())
    total_clips = sum(len(a["clips"]) for a in manifest["atlases"].values())
    print(f"Pack now has {total_frames} frames and {total_clips} named clips.")


if __name__ == "__main__":
    main()
