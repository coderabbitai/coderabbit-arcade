#!/usr/bin/env python3
"""Pack generated armed-Hoppy masters into deterministic Godot sprite assets.

This tool deliberately never paints or mutates masters.  It takes the two
generated 4x4 masters stored in ``Assets/hoppy-armed/*/sources`` and uses
nearest-neighbour sampling to make complete 4x4 atlases, SpriteFrames
resources, carry icons, manifests, and compact visual previews.

Run with:
    uvx --with pillow python tools/build_hoppy_armed.py
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "hoppys-adventure-arcade" / "Assets"
SMALL_FRAGMENT_PIXELS = 200
SMALL_FRAGMENT_MAX_DISTANCE = 10


@dataclass(frozen=True)
class Mode:
    directory: str
    cell: tuple[int, int]
    pivot: tuple[int, int]
    run_fps: int
    idle_height: int
    weapon_source: Path
    weapon_cell: int
    carry_frames: dict[str, int]
    hand_targets: tuple[tuple[int, int], ...]
    tip_targets: dict[int, tuple[int, int]]
    foot_source_rows: tuple[int, ...]
    pilot_weapon_bounds: tuple[int, int, int, int]
    pilot: str
    prompt: str
    reference: Path
    reference_cell: int
    reference_idle: int
    reference_pivot: tuple[int, int]


@dataclass(frozen=True)
class SourceComponent:
    """One full sprite recovered from a generated master, before packing."""

    cell: int
    bbox: tuple[int, int, int, int]
    pixels: tuple[tuple[int, int], ...]


@dataclass(frozen=True)
class FramePlacement:
    """A packed frame and its registration relative to the source table."""

    image: Image.Image
    offset: tuple[int, int]
    foot: tuple[int, int]


CODE_CITY_PROMPT = """Create a NEW 16-bit pixel-art brawler animation sheet of EXACTLY the orange rabbit shown in the first reference: cream muzzle, long orange ears, black shirt, orange legs, small cream tail, friendly determined eyes. Have him visibly hold the blue cyan DEBUG STICK from the second reference image with BOTH paws wrapping its handle in every sprite. Preserve the debug stick's exact cyan-blue, dark navy, and gold colors and its baton shape. The weapon must be drawn at exactly the same chunky pixel density as the rabbit, not finer. Transparent alpha background. FOUR columns by FOUR rows, sixteen equally spaced complete sprites, large empty transparent gutters, 30px outer margin, no text, no borders, no ground, shadow, detached effects, duplicate character, or UI. Face RIGHT. Same character size, feet baseline, and weapon scale in every pose. Row-major: 1 ready idle at carry height below shoulder; 2 through 5 four-step sideways run cycle carrying stick; 6 through 8 thrust windup, thrust contact, thrust follow-through; 9 through 11 sweep windup, sweep contact, sweep follow-through; 12 through 14 sweep windup, sweep contact, sweep follow-through; 15 lifting stick after pickup; 16 stagger hurt while still holding stick. This is a clean in-game sprite sheet, not concept art."""

HEROES_PROMPT = """Create a NEW 16-bit pixel-art brawler animation sheet of EXACTLY the armored orange rabbit shown in the first reference: cream muzzle, long orange ears, black and charcoal armored suit, orange chest crest, belt, dark cape, orange legs, friendly determined eyes. Have him visibly hold the orange REVIEW STAMP from the second reference image with both paws wrapping the stamp handle in every sprite. Preserve the stamp's exact orange, amber, white highlight, charcoal and steel-gray colors, rectangular stamping base, and rubber-stamp silhouette. The stamp must be drawn at exactly the same chunky pixel density as the rabbit, not finer. Transparent alpha background. FOUR columns by FOUR rows, sixteen equally spaced complete sprites, large empty transparent gutters, 30px outer margin, no text, no borders, no ground, shadow, detached effects, duplicate character, or UI. Face RIGHT. Same character size, feet baseline, and weapon scale in every pose. Row-major: 1 ready idle with stamp at carry height below shoulder; 2 through 5 four-step sideways run cycle carrying it; 6 through 8 stamp-down windup, contact, follow-through; 9 through 11 sweep windup, contact, follow-through; 12 through 14 slam windup, contact, follow-through; 15 lifting stamp after pickup; 16 stagger hurt while still holding stamp. This is a clean in-game sprite sheet, not concept art."""


MODES = (
    Mode(
        directory="code_city",
        cell=(192, 128),
        pivot=(72, 118),
        run_fps=12,
        idle_height=59,
        weapon_source=ASSETS / "code-city-brawl-assets-only" / "code_city" / "weapons.png",
        weapon_cell=128,
        carry_frames={
            "debug_stick": 0,
            "linter_staff": 2,
            "api_key_whip": 4,
            "git_branch": 7,
            "firewall_shield": 9,
            "refactor_hammer": 12,
        },
        hand_targets=(
            (94, 93), (97, 92), (96, 91), (98, 93),
            (94, 95), (94, 91), (104, 91), (100, 93),
            (82, 79), (100, 92), (105, 94), (94, 66),
            (103, 94), (96, 93), (94, 88), (95, 83),
        ),
        tip_targets={6: (124, 88), 9: (126, 91), 12: (130, 101)},
        foot_source_rows=(284, 284, 284, 284, 280, 280, 280, 280, 277, 277, 277, 277, 266, 266, 266, 266),
        # Measured from the baked hold_idle cell, not from the unarmed source
        # item. It encloses the visible stick beyond the paw. The generated
        # blade is shorter than the source cel, so no uniform scale matches
        # both the hidden grip and exposed blade.
        pilot_weapon_bounds=(89, 80, 29, 20),
        pilot="debug_stick",
        prompt=CODE_CITY_PROMPT,
        reference=ASSETS / "code-city-brawl-player" / "combat.png",
        reference_cell=96,
        reference_idle=15,
        reference_pivot=(48, 86),
    ),
    Mode(
        directory="heroes",
        cell=(256, 160),
        pivot=(96, 147),
        run_fps=7,
        idle_height=86,
        weapon_source=ASSETS / "heroes-vs-villains-assets-only" / "heroes_villains" / "items_allies.png",
        weapon_cell=192,
        carry_frames={
            "review_stamp": 0,
            "triage_hammer": 1,
            "change_stack_baton": 2,
            "security_scanner": 3,
            "pr_merger": 4,
        },
        hand_targets=(
            (130, 105), (135, 103), (136, 104), (139, 105),
            (132, 107), (136, 78), (150, 109), (147, 112),
            (95, 80), (145, 88), (150, 88), (145, 52),
            (128, 110), (139, 108), (148, 87), (135, 85),
        ),
        tip_targets={6: (151, 128), 9: (167, 85), 12: (153, 116)},
        foot_source_rows=(284, 284, 284, 284, 283, 283, 283, 283, 262, 262, 262, 262, 262, 262, 262, 262),
        # Measured from the baked hold_idle cell. Its longer dimension is the
        # stamp's complete handle-to-base length.
        pilot_weapon_bounds=(123, 77, 30, 44),
        pilot="review_stamp",
        prompt=HEROES_PROMPT,
        reference=ASSETS / "heroes-vs-villains-assets-only" / "heroes_villains" / "hoppy.png",
        reference_cell=128,
        reference_idle=0,
        reference_pivot=(64, 115),
    ),
)


CLIPS = {
    "hold_idle": ([0], 1, True),
    "run": ([1, 2, 3, 4], None, True),
    "step1": ([5, 6, 7], 9, False),
    "step2": ([8, 9, 10], 9, False),
    "step3": ([11, 12, 13], 9, False),
    "equip": ([14], 1, False),
    "hurt": ([15], 1, False),
}


def rect_for_grid(index: int, image_size: tuple[int, int], columns: int = 4) -> tuple[int, int, int, int]:
    """Return a stable rounded rectangle for an evenly-spaced generated grid."""
    width, height = image_size
    row, column = divmod(index, columns)
    left = round(column * width / columns)
    top = round(row * height / columns)
    right = round((column + 1) * width / columns)
    bottom = round((row + 1) * height / columns)
    return left, top, right, bottom


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError("transparent frame")
    return box


def visible_height(image: Image.Image) -> int:
    box = alpha_bbox(image)
    return box[3] - box[1]


def master_components(master: Image.Image) -> tuple[dict[int, SourceComponent], list[dict[str, object]]]:
    """Recover sprites across grid gutters without modifying the master.

    Generated poses sometimes overhang a nominal one-quarter boundary.  The
    master is therefore labelled as a whole and every major connected component
    is assigned to the quarter containing its centroid.  This is deliberately
    stricter than a crop: a missing component, a duplicate assignment, or an
    unexpected merge stops the build before it can silently cut a weapon.
    """
    alpha = master.getchannel("A")
    width, height = master.size
    alpha_pixels = alpha.load()
    threshold = 64
    seen: set[tuple[int, int]] = set()
    cores: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            if (x, y) in seen or alpha_pixels[x, y] <= threshold:
                continue
            component: list[tuple[int, int]] = []
            pending = [(x, y)]
            seen.add((x, y))
            while pending:
                current_x, current_y = pending.pop()
                component.append((current_x, current_y))
                for neighbor_y in range(max(0, current_y - 1), min(height, current_y + 2)):
                    for neighbor_x in range(max(0, current_x - 1), min(width, current_x + 2)):
                        if (neighbor_x, neighbor_y) not in seen and alpha_pixels[neighbor_x, neighbor_y] > threshold:
                            seen.add((neighbor_x, neighbor_y))
                            pending.append((neighbor_x, neighbor_y))
            cores.append(component)
    major_cores = [component for component in cores if len(component) >= SMALL_FRAGMENT_PIXELS]
    fragments = [component for component in cores if len(component) < SMALL_FRAGMENT_PIXELS]
    if len(major_cores) != 16:
        raise ValueError(
            f"expected exactly 16 major connected sprites, found {len(major_cores)} "
            f"(plus {len(fragments)} small fragments)"
        )

    owner: dict[tuple[int, int], int] = {}
    recovered: list[set[tuple[int, int]]] = []
    cell_for_component: list[int] = []
    for component_id, core in enumerate(major_cores):
        centroid_x = sum(x for x, _ in core) / len(core)
        centroid_y = sum(y for _, y in core) / len(core)
        column = min(3, int(centroid_x * 4 / width))
        row = min(3, int(centroid_y * 4 / height))
        cell_for_component.append(row * 4 + column)
        recovered.append(set(core))
        for point in core:
            owner[point] = component_id
    if len(set(cell_for_component)) != 16:
        raise ValueError(f"component centroid assignment is not one-per-cell: {cell_for_component}")
    # Keep this immutable map for fragment distance checks. An attached sliver
    # must not become a bridge that lets later specks creep away from the
    # original sprite art.
    core_owner = dict(owner)

    # A disconnected sliver, such as the thin end of a whip, is not grounds
    # for discarding an otherwise usable generated sheet. Preserve fragments
    # only when they lie within a small radius of real pixels in one full pose.
    # A distant speck, a 17th major component, or a merged pair still fails.
    attachments: list[dict[str, object]] = []
    for fragment in fragments:
        nearest: dict[int, int] = {}
        for source_x, source_y in fragment:
            for y in range(max(0, source_y - SMALL_FRAGMENT_MAX_DISTANCE), min(height, source_y + SMALL_FRAGMENT_MAX_DISTANCE + 1)):
                for x in range(max(0, source_x - SMALL_FRAGMENT_MAX_DISTANCE), min(width, source_x + SMALL_FRAGMENT_MAX_DISTANCE + 1)):
                    distance_squared = (x - source_x) ** 2 + (y - source_y) ** 2
                    if distance_squared > SMALL_FRAGMENT_MAX_DISTANCE ** 2:
                        continue
                    component_id = core_owner.get((x, y))
                    if component_id is not None:
                        nearest[component_id] = min(nearest.get(component_id, distance_squared), distance_squared)
        if not nearest:
            raise ValueError(
                f"small fragment ({len(fragment)}px) is farther than {SMALL_FRAGMENT_MAX_DISTANCE}px from every pose"
            )
        component_id, distance_squared = min(nearest.items(), key=lambda item: (item[1], item[0]))
        recovered[component_id].update(fragment)
        for point in fragment:
            owner[point] = component_id
        left = min(x for x, _ in fragment)
        top = min(y for _, y in fragment)
        right = max(x for x, _ in fragment) + 1
        bottom = max(y for _, y in fragment) + 1
        attachments.append({
            "cell": cell_for_component[component_id] + 1,
            "pixels": len(fragment),
            "distance": round(distance_squared ** 0.5, 3),
            "bounds": [left, top, right, bottom],
        })

    # Retain the low-alpha anti-alias fringe only when it has one unambiguous
    # adjacent opaque owner. This keeps outlines while refusing unrelated specks.
    for y in range(height):
        for x in range(width):
            if alpha_pixels[x, y] == 0 or (x, y) in owner:
                continue
            nearby = {
                owner[(neighbor_x, neighbor_y)]
                for neighbor_y in range(max(0, y - 2), min(height, y + 3))
                for neighbor_x in range(max(0, x - 2), min(width, x + 3))
                if (neighbor_x, neighbor_y) in owner
            }
            if len(nearby) == 1:
                recovered[nearby.pop()].add((x, y))

    result: dict[int, SourceComponent] = {}
    for component_id, pixels in enumerate(recovered):
        left = min(x for x, _ in pixels)
        top = min(y for _, y in pixels)
        right = max(x for x, _ in pixels) + 1
        bottom = max(y for _, y in pixels) + 1
        if left == 0 or top == 0 or right == width or bottom == height:
            raise ValueError(f"component {component_id + 1} touches the master crop edge")
        cell = cell_for_component[component_id]
        if cell in result:
            raise ValueError(f"duplicate component assigned to cell {cell + 1}")
        result[cell] = SourceComponent(cell, (left, top, right, bottom), tuple(sorted(pixels)))
    if set(result) != set(range(16)):
        raise ValueError(f"dropped generated components: cells present={sorted(result)}")
    return result, attachments


def component_image(master: Image.Image, component: SourceComponent) -> Image.Image:
    """Extract only one whole-master component, including its gutter overhang."""
    left, top, right, bottom = component.bbox
    image = Image.new("RGBA", (right - left, bottom - top))
    source_pixels = master.load()
    output_pixels = image.load()
    for x, y in component.pixels:
        output_pixels[x - left, y - top] = source_pixels[x, y]
    return image


def nearest_size(width: int, height: int, scale: float) -> tuple[int, int]:
    return max(1, round(width * scale)), max(1, round(height * scale))


def unregistered_frame(
    master: Image.Image, component: SourceComponent, mode: Mode, scale: float, foot_source_row: int
) -> tuple[Image.Image, int]:
    """Pack one component at its source-grid position before foot registration."""
    source_rect = rect_for_grid(component.cell, master.size)
    tile = component_image(master, component)
    alpha_bbox(tile)
    resized = tile.resize(nearest_size(tile.width, tile.height, scale), Image.Resampling.NEAREST)
    frame = Image.new("RGBA", mode.cell)
    grid_width = source_rect[2] - source_rect[0]
    grid_height = source_rect[3] - source_rect[1]
    # Generated masters use a shared grid baseline. Preserve each component's
    # original position relative to that grid, including any safe overhang.
    x = mode.pivot[0] - round(grid_width * scale * 0.36) + round((component.bbox[0] - source_rect[0]) * scale)
    y = mode.pivot[1] - round(grid_height * scale) + round((component.bbox[1] - source_rect[1]) * scale)
    if x < 0 or y < 0 or x + resized.width > mode.cell[0] or y + resized.height > mode.cell[1]:
        raise ValueError(f"frame {component.cell + 1} overflows {mode.directory}: {x=}, {y=}, {resized.size=}")
    frame.alpha_composite(resized, (x, y))
    expected_foot_y = y + round((foot_source_row - (component.bbox[1] - source_rect[1])) * scale)
    return frame, expected_foot_y


def opaque_span(frame: Image.Image, y: int) -> tuple[int, int] | None:
    """Find the overall high-alpha span of a potential planted-foot row."""
    pixels = frame.getchannel("A").load()
    xs = [x for x in range(frame.width) if pixels[x, y] >= 128]
    if not xs:
        return None
    return min(xs), max(xs)


def planted_foot_row(frame: Image.Image, expected_y: int, mode: Mode) -> tuple[int, tuple[int, int]]:
    """Resolve a hand-inspected source foot row to painted packed pixels."""
    choices: list[tuple[int, int, tuple[int, int]]] = []
    for y in range(max(0, expected_y - 4), min(frame.height, expected_y + 5)):
        span = opaque_span(frame, y)
        if span is not None:
            # Prefer the manually targeted row, then a substantial foot span.
            choices.append((abs(y - expected_y), -(span[1] - span[0]), (y, span)))
    if not choices:
        raise ValueError(f"no painted planted foot near y={expected_y} in {mode.directory}")
    _, _, result = min(choices)
    return result


def translate_frame(frame: Image.Image, offset: tuple[int, int], mode: Mode, index: int) -> Image.Image:
    """Shift a frame without losing any alpha at its contract cell edges."""
    dx, dy = offset
    bounds = alpha_bbox(frame)
    moved = (bounds[0] + dx, bounds[1] + dy, bounds[2] + dx, bounds[3] + dy)
    if moved[0] <= 0 or moved[1] <= 0 or moved[2] >= mode.cell[0] or moved[3] >= mode.cell[1]:
        raise ValueError(f"frame {index + 1} touches a packed cell edge in {mode.directory}")
    output = Image.new("RGBA", mode.cell)
    output.alpha_composite(frame, offset)
    return output


def register_frames(
    master: Image.Image, components: dict[int, SourceComponent], mode: Mode, scale: float
) -> list[FramePlacement]:
    """Plant every pose at the gameplay pivot while preserving its art offsets."""
    if len(mode.foot_source_rows) != 16:
        raise ValueError(f"{mode.directory}: expected 16 planted-foot source rows")
    preliminary = [
        unregistered_frame(master, components[index], mode, scale, mode.foot_source_rows[index])
        for index in range(16)
    ]
    measured_feet = [planted_foot_row(frame, expected_y, mode) for frame, expected_y in preliminary]
    idle_span = measured_feet[0][1]
    horizontal_offset = mode.pivot[0] - round((idle_span[0] + idle_span[1]) / 2)
    placements: list[FramePlacement] = []
    for index, ((frame, _), (foot_y, span)) in enumerate(zip(preliminary, measured_feet)):
        offset = (horizontal_offset, mode.pivot[1] - foot_y)
        registered = translate_frame(frame, offset, mode, index)
        foot_center = round((span[0] + span[1]) / 2) + horizontal_offset
        placements.append(FramePlacement(registered, offset, (foot_center, mode.pivot[1])))
    return placements


def pilot_scale(master: Image.Image, components: dict[int, SourceComponent], mode: Mode) -> float:
    """Calibrate one uniform sheet scale from the first, resting frame."""
    idle = component_image(master, components[0])
    height = visible_height(idle)
    scale = mode.idle_height / height
    # Every source cell must fit above the contract foot pivot. This preserves
    # uniformity even on the overhead attack poses.
    max_cell_height = max(
        visible_height(component_image(master, components[index])) for index in range(16)
    )
    return min(scale, mode.pivot[1] / max_cell_height)


def clip_metadata(mode: Mode) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for name, (frames, speed, loop) in CLIPS.items():
        result[name] = {"frames": frames, "fps": mode.run_fps if speed is None else speed, "loop": loop}
    return result


def snap_to_opaque(frame: Image.Image, target: tuple[int, int], label: str) -> list[int]:
    """Keep each art-directed anchor on its painted paw or weapon pixel."""
    alpha = frame.getchannel("A")
    pixels = alpha.load()
    best: tuple[int, int, int] | None = None
    for y in range(max(0, target[1] - 12), min(frame.height, target[1] + 13)):
        for x in range(max(0, target[0] - 12), min(frame.width, target[0] + 13)):
            if pixels[x, y] < 128:
                continue
            distance = (x - target[0]) ** 2 + (y - target[1]) ** 2
            candidate = (distance, x, y)
            if best is None or candidate < best:
                best = candidate
    if best is None:
        raise ValueError(f"no opaque pixel near the hand-picked {label} target {target}")
    return [best[1], best[2]]


def shifted_point(point: tuple[int, int], offset: tuple[int, int]) -> tuple[int, int]:
    return point[0] + offset[0], point[1] + offset[1]


def anchors(mode: Mode, placements: list[FramePlacement]) -> dict[str, dict[str, list[int]]]:
    """Record checked, per-frame grip and contact-tip anchors."""
    if len(mode.hand_targets) != 16:
        raise ValueError(f"{mode.directory}: expected 16 hand targets")
    hand = {
        str(index): snap_to_opaque(
            placement.image, shifted_point(mode.hand_targets[index], placement.offset), f"hand {index + 1}"
        )
        for index, placement in enumerate(placements)
    }
    tip = {
        str(index): snap_to_opaque(
            placements[index].image, shifted_point(target, placements[index].offset), f"tip {index + 1}"
        )
        for index, target in mode.tip_targets.items()
    }
    if set(mode.tip_targets) != {6, 9, 12}:
        raise ValueError(f"{mode.directory}: contact tips must be frames 7, 10, and 13")
    foot = {str(index): list(placement.foot) for index, placement in enumerate(placements)}
    return {"hand": hand, "tip": tip, "foot": foot}


def write_tres(output: Path, sheet_name: str, mode: Mode) -> None:
    lines = [
        "[gd_resource type=\"SpriteFrames\" load_steps=18 format=3]",
        "",
        f"[ext_resource type=\"Texture2D\" path=\"{sheet_name}.png\" id=\"1\"]",
    ]
    for index in range(16):
        x = (index % 4) * mode.cell[0]
        y = (index // 4) * mode.cell[1]
        lines.extend(
            (
                "",
                f"[sub_resource type=\"AtlasTexture\" id=\"Frame_{index}\"]",
                "atlas = ExtResource(\"1\")",
                f"region = Rect2({x}, {y}, {mode.cell[0]}, {mode.cell[1]})",
            )
        )
    animations = []
    for name, (indices, speed, loop) in CLIPS.items():
        refs = ", ".join(
            '{"duration": 1.0, "texture": SubResource("Frame_%d")}' % index for index in indices
        )
        resolved_speed = mode.run_fps if speed is None else speed
        animations.append(
            '{"frames": [%s], "loop": %s, "name": &"%s", "speed": %.1f}'
            % (refs, str(loop).lower(), name, resolved_speed)
        )
    lines.extend(("", "[resource]", "animations = [\n" + ",\n".join(animations) + "\n]", ""))
    output.write_text("\n".join(lines), encoding="utf-8")


def visible_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    """Return JSON-friendly alpha bounds with a useful error message."""
    return alpha_bbox(image)


def write_carry_icons(
    pack: Path, mode: Mode, hold_idle: Image.Image, pilot_weapon_bounds: tuple[int, int, int, int]
) -> dict[str, object]:
    """Build carries at the pilot's baked weapon-to-body calibration.

    A fixed half-size reduction made the unarmed carry overlay noticeably
    larger than the weapon held in an armed pose.  The pilot establishes the
    character-relative size. Every other source cel in the same mode keeps its
    own visible proportion but uses that same source-to-body conversion.
    """
    source = Image.open(mode.weapon_source).convert("RGBA")
    destination = pack / "carry"
    destination.mkdir(parents=True, exist_ok=True)

    hold_left, hold_top, hold_width, hold_height = pilot_weapon_bounds
    hold_bounds = (hold_left, hold_top, hold_left + hold_width, hold_top + hold_height)
    if hold_bounds[2] > hold_idle.width or hold_bounds[3] > hold_idle.height:
        raise ValueError(f"pilot weapon bounds overflow {mode.directory} hold_idle")
    if hold_idle.crop(hold_bounds).getchannel("A").getbbox() is None:
        raise ValueError(f"pilot weapon bounds contain no painted pixels: {mode.directory}")
    baked_length = max(hold_width, hold_height)

    pilot_source = source.crop(rect_for_grid(mode.carry_frames[mode.pilot], source.size))
    pilot_source_bounds = visible_bounds(pilot_source)
    pilot_source_length = max(
        pilot_source_bounds[2] - pilot_source_bounds[0],
        pilot_source_bounds[3] - pilot_source_bounds[1],
    )
    carry_scale = baked_length / pilot_source_length
    if not 0 < carry_scale <= 1:
        raise ValueError(f"invalid carry calibration for {mode.directory}: {carry_scale}")

    weapons: dict[str, dict[str, object]] = {}
    for weapon, index in mode.carry_frames.items():
        icon = source.crop(rect_for_grid(index, source.size))
        source_bounds = visible_bounds(icon)
        source_length = max(source_bounds[2] - source_bounds[0], source_bounds[3] - source_bounds[1])
        target_length = max(1, round(source_length * carry_scale))
        icon = icon.resize(nearest_size(icon.width, icon.height, carry_scale), Image.Resampling.NEAREST)
        icon_bounds = visible_bounds(icon)
        actual_length = max(icon_bounds[2] - icon_bounds[0], icon_bounds[3] - icon_bounds[1])
        if abs(actual_length - target_length) > max(1, round(target_length * 0.1)):
            raise ValueError(f"carry icon scale drift: {mode.directory}/{weapon}")
        if weapon == mode.pilot and abs(actual_length - baked_length) > max(1, round(baked_length * 0.1)):
            raise ValueError(f"pilot carry icon does not match baked weapon: {mode.directory}/{weapon}")
        if icon.getchannel("A").getbbox() is None:
            raise ValueError(f"empty carry icon: {mode.directory}/{weapon}")
        icon.save(destination / f"{weapon}.png")
        weapons[weapon] = {
            "source_visible_bounds": list(source_bounds),
            "source_length": source_length,
            "target_length": target_length,
        }
    return {
        "rule": (
            "Each target length preserves its source cel's visible proportion at the pilot's "
            "baked weapon-to-unarmed-body ratio: carry_scale = "
            "(pilot baked_length / body_height) * body_height / pilot source_length."
        ),
        "pilot": {
            "weapon": mode.pilot,
            "hold_idle_bounds": list(pilot_weapon_bounds),
            "baked_length": baked_length,
        },
        "carry_scale": carry_scale,
        "body_height": mode.idle_height,
        "weapons": weapons,
    }


def paste_with_checker(canvas: Image.Image, image: Image.Image, xy: tuple[int, int]) -> None:
    draw = ImageDraw.Draw(canvas)
    x, y = xy
    block = 8
    for row in range(0, image.height, block):
        for column in range(0, image.width, block):
            color = (37, 45, 62, 255) if (row // block + column // block) % 2 else (25, 31, 46, 255)
            draw.rectangle((x + column, y + row, x + column + block - 1, y + row + block - 1), fill=color)
    canvas.alpha_composite(image, xy)


def make_preview(pack: Path, mode: Mode, sheet: Image.Image) -> None:
    ref = Image.open(mode.reference).convert("RGBA")
    ref_rect = rect_for_grid(mode.reference_idle, ref.size)
    idle = ref.crop(ref_rect)
    scale = 2
    card_width = mode.cell[0] * scale
    card_height = mode.cell[1] * scale
    preview = Image.new("RGBA", (card_width * 4 + 28, card_height * 5 + 64), (12, 17, 28, 255))
    title = ImageDraw.Draw(preview)
    title.text((14, 14), f"{mode.directory}: {mode.pilot} pilot | unarmed idle + 16 armed cells", fill=(231, 238, 249, 255))
    # Unarmed idle first, at the same origin contract as the armed grid.
    idle_frame = Image.new("RGBA", mode.cell)
    idle_scale = mode.idle_height / max(1, visible_height(idle))
    idle_resized = idle.resize(nearest_size(idle.width, idle.height, idle_scale), Image.Resampling.NEAREST)
    reference_pivot_x, reference_pivot_y = mode.reference_pivot
    idle_frame.alpha_composite(
        idle_resized,
        (mode.pivot[0] - round(reference_pivot_x * idle_scale), mode.pivot[1] - round(reference_pivot_y * idle_scale)),
    )
    cells = [idle_frame] + [sheet.crop((index % 4 * mode.cell[0], index // 4 * mode.cell[1], (index % 4 + 1) * mode.cell[0], (index // 4 + 1) * mode.cell[1])) for index in range(16)]
    for index, cell in enumerate(cells):
        row, column = divmod(index, 4)
        enlarged = cell.resize((card_width, card_height), Image.Resampling.NEAREST)
        x, y = 14 + column * card_width, 48 + row * card_height
        paste_with_checker(preview, enlarged, (x, y))
        label = "unarmed idle" if index == 0 else f"{index:02d}"
        title.text((x + 4, y + 4), label, fill=(255, 202, 99, 255))
    preview.save(pack / "preview.png")


def make_clip_preview(pack: Path, mode: Mode, frames: list[Image.Image]) -> None:
    """Write a ground-lined frame strip for every runtime clip."""
    scale = 2
    max_frames = max(len(indices) for indices, _, _ in CLIPS.values())
    gutter = 92
    row_height = mode.cell[1] * scale + 34
    width = gutter + mode.cell[0] * scale * max_frames + 24
    height = 28 + row_height * len(CLIPS)
    preview = Image.new("RGBA", (width, height), (12, 17, 28, 255))
    draw = ImageDraw.Draw(preview)
    draw.text((12, 8), f"{mode.directory}: runtime clips | ground = foot pivot", fill=(231, 238, 249, 255))
    for row, (name, (indices, _, _)) in enumerate(CLIPS.items()):
        top = 28 + row * row_height
        draw.text((8, top + 8), name, fill=(255, 202, 99, 255))
        ground_y = top + mode.pivot[1] * scale
        draw.line((gutter, ground_y, width - 12, ground_y), fill=(93, 238, 176, 255), width=2)
        for column, frame_index in enumerate(indices):
            enlarged = frames[frame_index].resize(
                (mode.cell[0] * scale, mode.cell[1] * scale), Image.Resampling.NEAREST
            )
            x = gutter + column * mode.cell[0] * scale
            paste_with_checker(preview, enlarged, (x, top))
            draw.line((x, ground_y, x + mode.cell[0] * scale - 1, ground_y), fill=(93, 238, 176, 255), width=2)
    preview.save(pack / "clips.png")


def write_prompts(pack: Path, mode: Mode) -> None:
    mode_note = {
        "code_city": (
            "The Code City thrust windup remains visually close to the carry pose. "
            "It was retained for pilot approval rather than regenerated."
        ),
        "heroes": (
            "In step 2 contact/follow, the review stamp's rectangular base can read like a "
            "boxing glove or plunger. It was retained for pilot approval rather than regenerated."
        ),
    }[mode.directory]
    text = (
        f"# {mode.directory} armed Hoppy pilot prompt\n\n"
        "Built-in image generation, October 8, 2026. The source master preserves generated alpha unchanged. "
        "`tools/build_hoppy_armed.py` only crops, nearest-neighbour scales, registers, and packs it.\n\n"
        "## Exact generation prompt\n\n"
        f"{mode.prompt}\n\n"
        "## Refinements\n\n"
        "Regenerations: 0. The first generated master was retained. After independent visual review, "
        "the deterministic packer was corrected to recover connected components across grid gutters, "
        "plant every frame's feet at its gameplay pivot, store per-frame hand and attack-tip anchors "
        "on solid painted pixels, and calibrate carry icons to the baked hold_idle weapon length. "
        "Ground-lined runtime clip strips were added for motion inspection. These were packing changes, "
        "not image regenerations.\n\n"
        f"Inspection note: {mode_note}\n"
    )
    (pack / "PROMPTS.md").write_text(text, encoding="utf-8")


def pack_pilot(mode: Mode) -> None:
    pack = ASSETS / "hoppy-armed" / mode.directory
    source_path = pack / "sources" / f"{mode.pilot}.png"
    if not source_path.exists():
        raise FileNotFoundError(f"missing generated master: {source_path}")
    master = Image.open(source_path).convert("RGBA")
    if master.getchannel("A").getextrema()[0] != 0:
        raise ValueError(f"{source_path}: generated source does not preserve transparency")
    components, fragment_attachments = master_components(master)
    scale = pilot_scale(master, components, mode)
    placements = register_frames(master, components, mode, scale)
    frames = [placement.image for placement in placements]
    sheet = Image.new("RGBA", (mode.cell[0] * 4, mode.cell[1] * 4))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index % 4 * mode.cell[0], index // 4 * mode.cell[1]))
    sheet.save(pack / f"{mode.pilot}.png")
    write_tres(pack / f"{mode.pilot}.tres", mode.pilot, mode)
    idle_dx, idle_dy = placements[0].offset
    hold_left, hold_top, hold_width, hold_height = mode.pilot_weapon_bounds
    registered_hold_bounds = (hold_left + idle_dx, hold_top + idle_dy, hold_width, hold_height)
    carry_calibration = write_carry_icons(pack, mode, frames[0], registered_hold_bounds)
    entry = {
        "weapon": mode.pilot,
        "file": f"{mode.pilot}.png",
        "resource": f"{mode.pilot}.tres",
        "cell": list(mode.cell),
        "grid": [4, 4],
        "pivot": list(mode.pivot),
        "facing": "right",
        "body_height": visible_height(frames[0]),
        "unarmed_idle_height": mode.idle_height,
        "source_scale": scale,
        "source_component_bounds": [list(components[index].bbox) for index in range(16)],
        "fragment_attachments": fragment_attachments,
        "foot_anchor_semantics": "Ground midpoint for registration validation; it can lie between painted feet and is not an effect anchor.",
        "clips": clip_metadata(mode),
        "anchors": anchors(mode, placements),
    }
    manifest = {
        "version": 1,
        "mode": mode.directory,
        "filter": "nearest",
        "generated_from": "built-in image generation; see PROMPTS.md",
        "carry_calibration": carry_calibration,
        "weapons": {mode.pilot: entry},
    }
    (pack / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    write_prompts(pack, mode)
    make_preview(pack, mode, sheet)
    make_clip_preview(pack, mode, frames)
    print(f"packed {mode.directory}/{mode.pilot}: scale={scale:.6f}, body_height={entry['body_height']}")


def iter_modes(names: Iterable[str]) -> Iterable[Mode]:
    requested = set(names)
    for mode in MODES:
        if not requested or mode.directory in requested:
            yield mode


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=[mode.directory for mode in MODES], action="append", default=[])
    arguments = parser.parse_args()
    for mode in iter_modes(arguments.mode):
        pack_pilot(mode)


if __name__ == "__main__":
    main()
