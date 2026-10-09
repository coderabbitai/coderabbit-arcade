#!/usr/bin/env python3
"""Pack generated armed-Hoppy masters into deterministic Godot sprite assets.

This tool deliberately never paints or mutates masters.  It takes the
generated 4x4 master of each weapon stored in ``Assets/hoppy-armed/*/sources``
and uses nearest-neighbour sampling to make complete 4x4 atlases, SpriteFrames
resources, carry icons, manifests, and compact visual previews.  See
``Assets/hoppy-armed/README.md`` for the layout and the per-weapon options.

Run with:
    uvx --with pillow python tools/build_hoppy_armed.py [--mode code_city|heroes]
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "hoppys-adventure-arcade" / "Assets"
SMALL_FRAGMENT_PIXELS = 200
SMALL_FRAGMENT_MAX_DISTANCE = 10
CARRY_ORIENTATIONS = {
    "flip_h": Image.Transpose.FLIP_LEFT_RIGHT,
    "flip_v": Image.Transpose.FLIP_TOP_BOTTOM,
    "rotate_180": Image.Transpose.ROTATE_180,
}


@dataclass(frozen=True)
class Weapon:
    """Art-directed pack inputs for one generated armed-Hoppy master."""

    weapon: str
    hand_targets: tuple[tuple[int, int], ...]
    tip_targets: dict[int, tuple[int, int]]
    foot_source_rows: tuple[int, ...]
    hold_idle_weapon_bounds: tuple[int, int, int, int]
    motion: str
    per_frame_foot_pivot: bool = False
    foot_plant_overrides: dict[int, str] = field(default_factory=dict)
    foot_plant_note: str = ""
    # Optional source-space spans for poses where a loose weapon otherwise
    # occupies the row used to find the character's planted feet.
    body_foot_targets: tuple[tuple[int, int] | None, ...] = ()
    # Optional packed-frame -> generated-source-cell mapping. An empty tuple
    # retains the source's row-major order exactly.
    source_order: tuple[int, ...] = ()
    # Optional carry-icon transpose (a CARRY_ORIENTATIONS key) for a weapon the
    # baked sheet holds by the other end. It needs carry_grip: the oriented
    # icon's texel the paw holds, written to the manifest for the runtime.
    carry_orientation: str = ""
    carry_grip: tuple[int, int] | None = None


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
    extra_weapons: tuple[Weapon, ...] = ()


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
    selected_foot_before_registration: tuple[int, int]
    lowest_sole_row: int
    same_foot_x: int


@dataclass(frozen=True)
class PackedWeapon:
    """The deterministic outputs kept in memory until the mode manifest is written."""

    spec: Weapon
    components: dict[int, SourceComponent]
    frames: list[FramePlacement]
    scale: float
    hold_idle_bounds: tuple[int, int, int, int]


CODE_CITY_PROMPT = """Create a NEW 16-bit pixel-art brawler animation sheet of EXACTLY the orange rabbit shown in the first reference: cream muzzle, long orange ears, black shirt, orange legs, small cream tail, friendly determined eyes. Have him visibly hold the blue cyan DEBUG STICK from the second reference image with BOTH paws wrapping its handle in every sprite. Preserve the debug stick's exact cyan-blue, dark navy, and gold colors and its baton shape. The weapon must be drawn at exactly the same chunky pixel density as the rabbit, not finer. Transparent alpha background. FOUR columns by FOUR rows, sixteen equally spaced complete sprites, large empty transparent gutters, 30px outer margin, no text, no borders, no ground, shadow, detached effects, duplicate character, or UI. Face RIGHT. Same character size, feet baseline, and weapon scale in every pose. Row-major: 1 ready idle at carry height below shoulder; 2 through 5 four-step sideways run cycle carrying stick; 6 through 8 thrust windup, thrust contact, thrust follow-through; 9 through 11 sweep windup, sweep contact, sweep follow-through; 12 through 14 sweep windup, sweep contact, sweep follow-through; 15 lifting stick after pickup; 16 stagger hurt while still holding stick. This is a clean in-game sprite sheet, not concept art."""

HEROES_PROMPT = """Create a NEW 16-bit pixel-art brawler animation sheet of EXACTLY the armored orange rabbit shown in the first reference: cream muzzle, long orange ears, black and charcoal armored suit, orange chest crest, belt, dark cape, orange legs, friendly determined eyes. Have him visibly hold the orange REVIEW STAMP from the second reference image with both paws wrapping the stamp handle in every sprite. Preserve the stamp's exact orange, amber, white highlight, charcoal and steel-gray colors, rectangular stamping base, and rubber-stamp silhouette. The stamp must be drawn at exactly the same chunky pixel density as the rabbit, not finer. Transparent alpha background. FOUR columns by FOUR rows, sixteen equally spaced complete sprites, large empty transparent gutters, 30px outer margin, no text, no borders, no ground, shadow, detached effects, duplicate character, or UI. Face RIGHT. Same character size, feet baseline, and weapon scale in every pose. Row-major: 1 ready idle with stamp at carry height below shoulder; 2 through 5 four-step sideways run cycle carrying it; 6 through 8 stamp-down windup, contact, follow-through; 9 through 11 sweep windup, contact, follow-through; 12 through 14 slam windup, contact, follow-through; 15 lifting stamp after pickup; 16 stagger hurt while still holding stamp. This is a clean in-game sprite sheet, not concept art."""

CODE_CITY_HAND_TARGETS = (
    (94, 93), (97, 92), (96, 91), (98, 93),
    (94, 95), (94, 91), (104, 91), (100, 93),
    (82, 79), (100, 92), (105, 94), (94, 66),
    (103, 94), (96, 93), (94, 88), (95, 83),
)


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
        hand_targets=CODE_CITY_HAND_TARGETS,
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
        extra_weapons=(
            Weapon(
                weapon="linter_staff",
                hand_targets=(
                    (88, 99), (85, 101), (84, 102), (82, 101),
                    (82, 99), (78, 76), (95, 86), (97, 89),
                    (85, 83), (92, 90), (104, 89), (104, 69),
                    (101, 68), (103, 76), (98, 68), (87, 86),
                ),
                tip_targets={6: (128, 85), 9: (127, 89), 12: (135, 64)},
                foot_source_rows=(290, 288, 300, 290, 281, 280, 280, 280, 271, 269, 269, 272, 240, 226, 240, 240),
                hold_idle_weapon_bounds=(61, 77, 63, 31),
                motion="wide sweep / back sweep / spin",
                per_frame_foot_pivot=True,
            ),
            Weapon(
                weapon="api_key_whip",
                hand_targets=(
                    (99, 91), (120, 103), (121, 103), (115, 108),
                    (131, 102), (74, 72), (86, 92), (92, 92),
                    (87, 96), (91, 89), (94, 88), (97, 70),
                    (97, 83), (92, 92), (112, 83), (114, 77),
                ),
                tip_targets={6: (132, 85), 9: (138, 79), 12: (139, 79)},
                foot_source_rows=(278, 282, 276, 281, 274, 279, 279, 279, 264, 266, 265, 266, 248, 279, 250, 249),
                hold_idle_weapon_bounds=(97, 83, 33, 31),
                motion="crack / extended lash / recoil",
                per_frame_foot_pivot=True,
                foot_plant_note="Frames 13 and 14 use the rear planted foot; the corrected contact keeps it planted through the extended lash.",
                body_foot_targets=(
                    (75, 95), (67, 93), (64, 94), (57, 87),
                    (74, 104), None, None, None,
                    None, None, None, None,
                    None, None, (64, 89), None,
                ),
                source_order=(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 7, 14, 15),
                # The sheet grips the cord with the key at the striking end; the
                # cel holds the key. Mirror the carry and hold the coil's left side.
                carry_orientation="flip_h",
                carry_grip=(8, 24),
            ),
            Weapon(
                weapon="git_branch",
                hand_targets=(
                    (90, 93), (97, 87), (92, 94), (93, 92),
                    (101, 89), (74, 78), (71, 91), (80, 89),
                    (87, 90), (89, 89), (101, 78), (96, 84),
                    (88, 86), (88, 84), (99, 68), (87, 82),
                ),
                tip_targets={6: (125, 88), 9: (134, 94), 12: (133, 82)},
                foot_source_rows=(290, 288, 289, 293, 282, 282, 280, 279, 270, 267, 268, 270, 259, 254, 259, 259),
                hold_idle_weapon_bounds=(82, 76, 40, 30),
                motion="thrust / sweep / heavy shove",
                per_frame_foot_pivot=True,
            ),
            Weapon(
                weapon="refactor_hammer",
                hand_targets=(
                    (93, 86), (95, 84), (104, 85), (103, 85),
                    (112, 86), (94, 74), (93, 89), (91, 92),
                    (98, 91), (94, 90), (95, 90), (85, 68),
                    (94, 89), (96, 86), (98, 72), (106, 78),
                ),
                tip_targets={6: (128, 103), 9: (141, 81), 12: (140, 90)},
                foot_source_rows=(216, 215, 216, 216, 224, 232, 232, 224, 224, 223, 222, 226, 215, 212, 210, 212),
                hold_idle_weapon_bounds=(82, 70, 44, 35),
                motion="overhead / side / overhead slam",
                per_frame_foot_pivot=True,
                foot_plant_note="All attack frames, including human frames 7, 8, 14, and 15, use the rear planted foot.",
            ),
            Weapon(
                weapon="firewall_shield",
                hand_targets=CODE_CITY_HAND_TARGETS,
                tip_targets={6: (134, 84), 9: (132, 83), 12: (118, 74)},
                foot_source_rows=(291, 291, 291, 291, 277, 277, 277, 277, 258, 257, 258, 258, 237, 237, 237, 237),
                hold_idle_weapon_bounds=(88, 66, 32, 38),
                motion="shield-up jab / guarded swing / guarded kick; slot 16 block recoil",
                per_frame_foot_pivot=True,
            ),
        ),
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
        tip_targets={6: (151, 128), 9: (184, 95), 12: (153, 116)},
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
        extra_weapons=(
            Weapon(
                weapon="triage_hammer",
                hand_targets=(
                    (130, 105), (135, 103), (136, 104), (139, 105),
                    (132, 107), (136, 78), (150, 109), (147, 112),
                    (95, 80), (145, 88), (150, 88), (128, 110),
                    (134, 90), (145, 52), (148, 87), (135, 85),
                ),
                tip_targets={6: (155, 122), 9: (170, 95), 12: (152, 116)},
                foot_source_rows=(300, 302, 302, 307, 295, 297, 296, 298, 263, 268, 268, 256, 252, 268, 256, 256),
                hold_idle_weapon_bounds=(120, 80, 52, 36),
                motion="overhead / side / heavy slam",
                per_frame_foot_pivot=True,
                source_order=(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 11, 14, 15),
                foot_plant_note="Attack frames plant the rear foot; frame 14 uses the lower planted rear-foot row that excludes the hammer head. Idle, run, equip, and hurt use the foot centre.",
            ),
            Weapon(
                weapon="change_stack_baton",
                hand_targets=(
                    (130, 105), (135, 103), (136, 104), (139, 105),
                    (132, 107), (136, 78), (150, 109), (147, 112),
                    (95, 80), (145, 88), (150, 88), (100, 55),
                    (141, 58), (145, 52), (148, 87), (135, 85),
                ),
                tip_targets={6: (178, 86), 9: (175, 77), 12: (196, 52)},
                foot_source_rows=(294, 302, 301, 295, 256, 253, 258, 258, 180, 186, 190, 173, 172, 191, 162, 183),
                hold_idle_weapon_bounds=(62, 94, 105, 24),
                motion="long thrust / sweep / thrust",
                per_frame_foot_pivot=True,
                source_order=(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 11, 14, 15),
                foot_plant_note="Attack frames plant the rear foot; frame 15 uses its lower equip-foot row. Idle, run, equip, and hurt use the foot centre.",
            ),
            Weapon(
                weapon="security_scanner",
                hand_targets=(
                    (130, 105), (135, 103), (136, 104), (139, 105),
                    (132, 107), (136, 78), (150, 109), (147, 112),
                    (95, 80), (145, 88), (150, 88), (128, 110),
                    (146, 88), (145, 52), (148, 87), (135, 85),
                ),
                tip_targets={6: (156, 100), 9: (162, 67), 12: (166, 84)},
                foot_source_rows=(294, 296, 296, 296, 294, 294, 294, 294, 277, 279, 276, 273, 273, 278, 276, 276),
                hold_idle_weapon_bounds=(126, 76, 33, 38),
                motion="scan sweep / scan / pulse",
                per_frame_foot_pivot=True,
                foot_plant_overrides={4: "rear"},
                source_order=(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 11, 14, 15),
                foot_plant_note="Attack frames plant the rear foot. Frame 5 uses its one visible planted rear foot; the other run frames and idle, equip, and hurt use the foot centre.",
            ),
            Weapon(
                weapon="pr_merger",
                hand_targets=(
                    (130, 105), (135, 103), (136, 104), (139, 105),
                    (132, 107), (136, 78), (150, 109), (147, 112),
                    (95, 80), (145, 88), (150, 88), (128, 110),
                    (153, 35), (145, 52), (148, 87), (135, 85),
                ),
                tip_targets={6: (158, 105), 9: (162, 65), 12: (155, 29)},
                foot_source_rows=(292, 292, 293, 297, 262, 261, 262, 262, 235, 235, 235, 211, 212, 236, 214, 214),
                hold_idle_weapon_bounds=(120, 80, 52, 44),
                motion="jab / hook / uppercut punches",
                per_frame_foot_pivot=True,
                foot_plant_overrides={4: "rear"},
                source_order=(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 11, 14, 15),
                foot_plant_note="Attack frames plant the rear foot. Frame 5 uses its one visible planted rear foot; the other run frames and idle, equip, and hurt use the foot centre.",
            ),
        ),
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


def pilot_weapon(mode: Mode) -> Weapon:
    """Expose the historic one-pilot fields through the additive weapon model."""
    return Weapon(
        weapon=mode.pilot,
        hand_targets=mode.hand_targets,
        tip_targets=mode.tip_targets,
        foot_source_rows=mode.foot_source_rows,
        hold_idle_weapon_bounds=mode.pilot_weapon_bounds,
        motion="pilot",
    )


def weapons_for_mode(mode: Mode) -> tuple[Weapon, ...]:
    return (pilot_weapon(mode), *mode.extra_weapons)


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


def opaque_runs(frame: Image.Image, y: int) -> list[tuple[int, int]]:
    """Return contiguous high-alpha runs for choosing a planted foot."""
    pixels = frame.getchannel("A").load()
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for x in range(frame.width + 1):
        opaque = x < frame.width and pixels[x, y] >= 128
        if opaque and start is None:
            start = x
        elif not opaque and start is not None:
            runs.append((start, x - 1))
            start = None
    return runs


def planted_foot_x(frame: Image.Image, foot_y: int, span: tuple[int, int], policy: str) -> int:
    """Choose an art-directed planted foot without centring a lunge on both feet."""
    if policy == "center":
        return round((span[0] + span[1]) / 2)
    runs = opaque_runs(frame, foot_y)
    if not runs:
        raise ValueError(f"no painted foot runs at y={foot_y}")
    run = runs[0] if policy == "rear" else runs[-1] if policy == "front" else None
    if run is None:
        raise ValueError(f"unknown foot planting policy: {policy}")
    return round((run[0] + run[1]) / 2)


def lowest_sole_row(frame: Image.Image, foot_x: int) -> int:
    """Return the bottom painted sole near the selected weight-bearing foot."""
    pixels = frame.getchannel("A").load()
    left = max(0, foot_x - 14)
    right = min(frame.width, foot_x + 15)
    lower_body_top = round(frame.height * 0.55)
    for y in range(frame.height - 1, lower_body_top - 1, -1):
        if any(pixels[x, y] >= 128 for x in range(left, right)):
            return y
    raise ValueError(f"no painted sole near foot x={foot_x}")


def rear_foot_x(frame: Image.Image, sole_y: int) -> int:
    """Measure one consistent physical foot after per-frame registration."""
    runs = opaque_runs(frame, sole_y)
    if not runs:
        raise ValueError(f"no painted foot run at sole row y={sole_y}")
    left, right = runs[0]
    return round((left + right) / 2)


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


def resolved_source_order(source_order: tuple[int, ...], mode: Mode, weapon: str) -> tuple[int, ...]:
    """Resolve an opt-in source-cell remap without changing the normal path."""
    if not source_order:
        return tuple(range(16))
    if len(source_order) != 16 or any(cell not in range(16) for cell in source_order):
        raise ValueError(f"{mode.directory}/{weapon}: source_order must contain 16 source cells in range 0..15")
    return source_order


def register_frames(
    master: Image.Image,
    components: dict[int, SourceComponent],
    mode: Mode,
    scale: float,
    foot_source_rows: tuple[int, ...] | None = None,
    per_frame_foot_pivot: bool = False,
    foot_plant_overrides: dict[int, str] | None = None,
    body_foot_targets: tuple[tuple[int, int] | None, ...] = (),
    source_order: tuple[int, ...] = (),
) -> list[FramePlacement]:
    """Plant every pose at the gameplay pivot while preserving its art offsets."""
    rows = mode.foot_source_rows if foot_source_rows is None else foot_source_rows
    if len(rows) != 16:
        raise ValueError(f"{mode.directory}: expected 16 planted-foot source rows")
    order = resolved_source_order(source_order, mode, "armed sheet")
    preliminary = [
        unregistered_frame(master, components[order[index]], mode, scale, rows[index])
        for index in range(16)
    ]
    measured_feet = [planted_foot_row(frame, expected_y, mode) for frame, expected_y in preliminary]
    idle_span = measured_feet[0][1]
    horizontal_offset = mode.pivot[0] - round((idle_span[0] + idle_span[1]) / 2)
    overrides = {} if foot_plant_overrides is None else foot_plant_overrides
    if any(index not in range(16) or policy not in {"center", "rear", "front"} for index, policy in overrides.items()):
        raise ValueError(f"invalid foot planting overrides for {mode.directory}: {overrides}")
    if body_foot_targets and len(body_foot_targets) != 16:
        raise ValueError(f"{mode.directory}: expected 16 optional body-foot targets")
    targets = body_foot_targets or (None,) * 16
    for index, target in enumerate(targets):
        if target is None:
            continue
        left, right = target
        if left < 0 or right >= mode.cell[0] or left > right:
            raise ValueError(f"{mode.directory}: invalid body-foot target at frame {index + 1}: {target}")
    placements: list[FramePlacement] = []
    for index, ((frame, _), (foot_y, span)) in enumerate(zip(preliminary, measured_feet)):
        policy = overrides.get(index, "rear" if 5 <= index <= 13 else "center")
        target = targets[index]
        if target is not None:
            target_runs = opaque_runs(frame, foot_y)
            left, right = target
            if not any(run_left <= right and left <= run_right for run_left, run_right in target_runs):
                raise ValueError(
                    f"{mode.directory}: body-foot target misses painted feet at frame {index + 1}: {target}"
                )
            planted_x = round((left + right) / 2)
        else:
            planted_x = planted_foot_x(frame, foot_y, span, policy) if per_frame_foot_pivot else round((span[0] + span[1]) / 2)
        frame_offset_x = mode.pivot[0] - planted_x if per_frame_foot_pivot else horizontal_offset
        offset = (frame_offset_x, mode.pivot[1] - foot_y)
        registered = translate_frame(frame, offset, mode, index)
        sole_y = lowest_sole_row(registered, planted_x + frame_offset_x)
        if target is not None and abs(sole_y - mode.pivot[1]) > 1:
            raise ValueError(
                f"{mode.directory}: body-foot sole misses the pivot at frame {index + 1}: {sole_y}"
            )
        same_x = rear_foot_x(registered, sole_y) if policy != "center" else planted_x + frame_offset_x
        placements.append(
            FramePlacement(
                registered,
                offset,
                (planted_x + frame_offset_x, mode.pivot[1]),
                (planted_x, foot_y),
                sole_y,
                same_x,
            )
        )
    if per_frame_foot_pivot:
        for name, (indices, _, _) in CLIPS.items():
            planted = [placements[index].same_foot_x for index in indices]
            if any(abs(right - left) > 3 for left, right in zip(planted, planted[1:])):
                source = [placements[index].selected_foot_before_registration[0] for index in indices]
                raise ValueError(
                    f"{mode.directory}: same foot pops in {name}: packed={planted}, source={source}"
                )
            soles = [placements[index].lowest_sole_row for index in indices]
            if any(abs(sole - mode.pivot[1]) > 1 for sole in soles):
                source = [placements[index].selected_foot_before_registration[1] for index in indices]
                raise ValueError(
                    f"{mode.directory}: soles miss the pivot in {name}: packed={soles}, source={source}"
                )
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


def anchors(mode: Mode, weapon: Weapon, placements: list[FramePlacement]) -> dict[str, dict[str, list[int]]]:
    """Record checked, per-frame grip and contact-tip anchors."""
    if len(weapon.hand_targets) != 16:
        raise ValueError(f"{mode.directory}/{weapon.weapon}: expected 16 hand targets")
    hand = {
        str(index): snap_to_opaque(
            placement.image, shifted_point(weapon.hand_targets[index], placement.offset), f"hand {index + 1}"
        )
        for index, placement in enumerate(placements)
    }
    tip = {
        str(index): snap_to_opaque(
            placements[index].image, shifted_point(target, placements[index].offset), f"tip {index + 1}"
        )
        for index, target in weapon.tip_targets.items()
    }
    if set(weapon.tip_targets) != {6, 9, 12}:
        raise ValueError(f"{mode.directory}/{weapon.weapon}: contact tips must be frames 7, 10, and 13")
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


def orient_carry(icon: Image.Image, spec: Weapon | None, label: str) -> tuple[Image.Image, dict[str, object]]:
    """Apply a weapon's opt-in carry transpose and validate the paw texel it declares."""
    if spec is None or not spec.carry_orientation:
        if spec is not None and spec.carry_grip is not None:
            raise ValueError(f"{label}: carry_grip needs a carry_orientation")
        return icon, {}
    if spec.carry_orientation not in CARRY_ORIENTATIONS:
        raise ValueError(f"{label}: unknown carry_orientation {spec.carry_orientation!r}")
    if spec.carry_grip is None:
        raise ValueError(f"{label}: carry_orientation needs a carry_grip")
    icon = icon.transpose(CARRY_ORIENTATIONS[spec.carry_orientation])
    x, y = spec.carry_grip
    if not (0 <= x < icon.width and 0 <= y < icon.height) or icon.getpixel((x, y))[3] < 128:
        raise ValueError(f"{label}: carry_grip {spec.carry_grip} is not an opaque texel of the oriented icon")
    return icon, {"orientation": spec.carry_orientation, "grip": [x, y]}


def check_hold_bounds(frame: Image.Image, bounds: tuple[int, int, int, int], label: str) -> None:
    """Fail unless a registered (left, top, width, height) weapon box fits the hold_idle cell
    and covers painted (alpha >= 128) pixels; carry calibration measures the weapon from it."""
    left, top, width, height = bounds
    if width <= 0 or height <= 0 or left < 0 or top < 0 or left + width > frame.width or top + height > frame.height:
        raise ValueError(f"{label}: hold_idle weapon bounds {bounds} fall outside the {frame.width}x{frame.height} cell")
    painted = frame.crop((left, top, left + width, top + height)).getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0)
    if painted.getbbox() is None:
        raise ValueError(f"{label}: hold_idle weapon bounds {bounds} contain no painted pixels")


def write_carry_icons(pack: Path, mode: Mode, packed: dict[str, PackedWeapon]) -> dict[str, object]:
    """Build carries from each baked hold_idle sheet when one is available."""
    source = Image.open(mode.weapon_source).convert("RGBA")
    destination = pack / "carry"
    destination.mkdir(parents=True, exist_ok=True)

    pilot = packed[mode.pilot]
    _, _, hold_width, hold_height = pilot.hold_idle_bounds
    check_hold_bounds(pilot.frames[0].image, pilot.hold_idle_bounds, f"{mode.directory} pilot")
    pilot_baked_length = max(hold_width, hold_height)

    pilot_source = source.crop(rect_for_grid(mode.carry_frames[mode.pilot], source.size))
    pilot_source_bounds = visible_bounds(pilot_source)
    pilot_source_length = max(
        pilot_source_bounds[2] - pilot_source_bounds[0],
        pilot_source_bounds[3] - pilot_source_bounds[1],
    )
    carry_scale = pilot_baked_length / pilot_source_length
    if not 0 < carry_scale <= 1:
        raise ValueError(f"invalid carry calibration for {mode.directory}: {carry_scale}")

    weapons: dict[str, dict[str, object]] = {}
    for weapon, index in mode.carry_frames.items():
        icon = source.crop(rect_for_grid(index, source.size))
        source_bounds = visible_bounds(icon)
        source_length = max(source_bounds[2] - source_bounds[0], source_bounds[3] - source_bounds[1])
        baked = packed.get(weapon)
        weapon_scale = carry_scale
        baked_bounds: tuple[int, int, int, int] | None = None
        if baked is not None:
            baked_bounds = baked.hold_idle_bounds
            weapon_baked_length = max(baked_bounds[2], baked_bounds[3])
            weapon_scale = weapon_baked_length / source_length
        target_length = max(1, round(source_length * weapon_scale))
        icon = icon.resize(nearest_size(icon.width, icon.height, weapon_scale), Image.Resampling.NEAREST)
        icon, orientation = orient_carry(icon, baked.spec if baked is not None else None, f"{mode.directory}/{weapon}")
        icon_bounds = visible_bounds(icon)
        actual_length = max(icon_bounds[2] - icon_bounds[0], icon_bounds[3] - icon_bounds[1])
        if abs(actual_length - target_length) > max(1, round(target_length * 0.1)):
            raise ValueError(f"carry icon scale drift: {mode.directory}/{weapon}")
        if weapon == mode.pilot and abs(actual_length - pilot_baked_length) > max(1, round(pilot_baked_length * 0.1)):
            raise ValueError(f"pilot carry icon does not match baked weapon: {mode.directory}/{weapon}")
        if icon.getchannel("A").getbbox() is None:
            raise ValueError(f"empty carry icon: {mode.directory}/{weapon}")
        icon.save(destination / f"{weapon}.png")
        entry: dict[str, object] = {
            "source_visible_bounds": list(source_bounds),
            "source_length": source_length,
            "target_length": target_length,
        }
        if baked is not None and weapon != mode.pilot:
            entry.update({
                "rule": "Baked hold_idle visible weapon bounds for this armed sheet.",
                "carry_scale": weapon_scale,
                "hold_idle_bounds": list(baked_bounds),
                "baked_length": weapon_baked_length,
            })
        entry.update(orientation)
        weapons[weapon] = entry
    return {
        "rule": (
            "Each target length preserves its source cel's visible proportion at the pilot's "
            "baked weapon-to-unarmed-body ratio: carry_scale = "
            "(pilot baked_length / body_height) * body_height / pilot source_length."
        ),
        "pilot": {
            "weapon": mode.pilot,
            "hold_idle_bounds": list(pilot.hold_idle_bounds),
            "baked_length": pilot_baked_length,
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


def make_preview(pack: Path, mode: Mode, sheet: Image.Image, weapon: str | None = None, output: str = "preview.png") -> None:
    ref = Image.open(mode.reference).convert("RGBA")
    ref_rect = rect_for_grid(mode.reference_idle, ref.size)
    idle = ref.crop(ref_rect)
    scale = 2
    card_width = mode.cell[0] * scale
    card_height = mode.cell[1] * scale
    preview = Image.new("RGBA", (card_width * 4 + 28, card_height * 5 + 64), (12, 17, 28, 255))
    title = ImageDraw.Draw(preview)
    weapon_name = mode.pilot if weapon is None else weapon
    title.text((14, 14), f"{mode.directory}: {weapon_name} pilot | unarmed idle + 16 armed cells", fill=(231, 238, 249, 255))
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
    preview.save(pack / output)


def make_clip_preview(pack: Path, mode: Mode, frames: list[Image.Image], output: str = "clips.png") -> None:
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
    preview.save(pack / output)


def write_prompts(pack: Path, mode: Mode) -> None:
    """Render data-owned generation and refinement history without guessing it."""
    source = pack / "refinements.json"
    if not source.exists():
        raise FileNotFoundError(f"missing generation history: {source}")
    records = json.loads(source.read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError(f"{source}: expected a list")
    sections = [
        f"# {mode.directory} armed Hoppy generation prompts\n\n",
        "Built-in image generation, October 8, 2026. Source masters preserve generated alpha unchanged. "
        "`tools/build_hoppy_armed.py` only crops, nearest-neighbour scales, registers, and packs artwork.\n",
    ]
    for record in records:
        if not isinstance(record, dict):
            raise ValueError(f"{source}: each refinement record must be an object")
        weapon = record.get("weapon")
        prompt = record.get("prompt")
        change = record.get("change")
        regenerations = record.get("regenerations")
        if not isinstance(weapon, str) or not isinstance(prompt, str) or not isinstance(change, str) or not isinstance(regenerations, int):
            raise ValueError(f"{source}: records require weapon, regenerations, change, and prompt")
        sections.extend((
            f"\n## {weapon}\n\n",
            "### Exact generation prompt\n\n",
            f"{prompt}\n\n",
            "### Refinements\n\n",
            f"Regenerations: {regenerations}. {change}\n",
        ))
    (pack / "PROMPTS.md").write_text("".join(sections), encoding="utf-8")


def pack_mode(mode: Mode) -> None:
    pack = ASSETS / "hoppy-armed" / mode.directory
    packed: dict[str, PackedWeapon] = {}
    sheets: dict[str, Image.Image] = {}
    entries: dict[str, dict[str, object]] = {}
    for weapon in weapons_for_mode(mode):
        source_path = pack / "sources" / f"{weapon.weapon}.png"
        if not source_path.exists():
            raise FileNotFoundError(f"missing generated master: {source_path}")
        master = Image.open(source_path).convert("RGBA")
        if master.getchannel("A").getextrema()[0] != 0:
            raise ValueError(f"{source_path}: generated source does not preserve transparency")
        components, fragment_attachments = master_components(master)
        scale = pilot_scale(master, components, mode)
        source_order = resolved_source_order(weapon.source_order, mode, weapon.weapon)
        placements = register_frames(
            master,
            components,
            mode,
            scale,
            weapon.foot_source_rows,
            weapon.per_frame_foot_pivot,
            weapon.foot_plant_overrides,
            weapon.body_foot_targets,
            weapon.source_order,
        )
        frames = [placement.image for placement in placements]
        sheet = Image.new("RGBA", (mode.cell[0] * 4, mode.cell[1] * 4))
        for index, frame in enumerate(frames):
            sheet.alpha_composite(frame, (index % 4 * mode.cell[0], index // 4 * mode.cell[1]))
        sheet.save(pack / f"{weapon.weapon}.png")
        write_tres(pack / f"{weapon.weapon}.tres", weapon.weapon, mode)
        idle_dx, idle_dy = placements[0].offset
        hold_left, hold_top, hold_width, hold_height = weapon.hold_idle_weapon_bounds
        registered_hold_bounds = (hold_left + idle_dx, hold_top + idle_dy, hold_width, hold_height)
        check_hold_bounds(frames[0], registered_hold_bounds, f"{mode.directory}/{weapon.weapon}")
        packed[weapon.weapon] = PackedWeapon(weapon, components, placements, scale, registered_hold_bounds)
        sheets[weapon.weapon] = sheet
        entries[weapon.weapon] = {
            "weapon": weapon.weapon,
            "file": f"{weapon.weapon}.png",
            "resource": f"{weapon.weapon}.tres",
            "cell": list(mode.cell),
            "grid": [4, 4],
            "pivot": list(mode.pivot),
            "facing": "right",
            "body_height": visible_height(frames[0]),
            "unarmed_idle_height": mode.idle_height,
            "source_scale": scale,
            "source_component_bounds": [list(components[source_order[index]].bbox) for index in range(16)],
            "fragment_attachments": fragment_attachments,
            "foot_anchor_semantics": (
                "Per-frame planted foot for registration validation; attacks use the rear foot unless overridden."
                if weapon.per_frame_foot_pivot
                else "Ground midpoint for registration validation; it can lie between painted feet and is not an effect anchor."
            ),
            "clips": clip_metadata(mode),
            "anchors": anchors(mode, weapon, placements),
        }
        if weapon.source_order:
            entries[weapon.weapon]["source_order"] = list(source_order)
        if weapon.per_frame_foot_pivot:
            entries[weapon.weapon]["foot_planting"] = {
                "default": "idle, run, equip, and hurt use the foot centre; attack frames use the rear foot.",
                "overrides": {str(index): policy for index, policy in weapon.foot_plant_overrides.items()},
                "note": weapon.foot_plant_note,
            }
            if weapon.body_foot_targets:
                entries[weapon.weapon]["foot_planting"]["body_foot_targets"] = {
                    str(index): list(target)
                    for index, target in enumerate(weapon.body_foot_targets)
                    if target is not None
                }
    carry_calibration = write_carry_icons(pack, mode, packed)
    manifest = {
        "version": 1,
        "mode": mode.directory,
        "filter": "nearest",
        "generated_from": "built-in image generation; see PROMPTS.md",
        "carry_calibration": carry_calibration,
        "weapons": entries,
    }
    (pack / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    write_prompts(pack, mode)
    pilot = packed[mode.pilot]
    make_preview(pack, mode, sheets[mode.pilot])
    make_clip_preview(pack, mode, [placement.image for placement in pilot.frames])
    if mode.extra_weapons:
        for weapon in weapons_for_mode(mode):
            item = packed[weapon.weapon]
            make_preview(pack, mode, sheets[weapon.weapon], weapon.weapon, f"{weapon.weapon}_preview.png")
            make_clip_preview(pack, mode, [placement.image for placement in item.frames], f"{weapon.weapon}_clips.png")
    for weapon in weapons_for_mode(mode):
        entry = entries[weapon.weapon]
        print(f"packed {mode.directory}/{weapon.weapon}: scale={entry['source_scale']:.6f}, body_height={entry['body_height']}")


def pack_pilot(mode: Mode) -> None:
    """Compatibility entry point for scripts that still call the pilot packer."""
    pack_mode(mode)


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
        pack_mode(mode)


if __name__ == "__main__":
    main()
