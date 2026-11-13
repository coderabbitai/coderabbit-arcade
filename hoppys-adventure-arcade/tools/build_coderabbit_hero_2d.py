"""Re-skin Hoppy's Heroes vs. Villains sheets in the CodeRabbit hero rabbit's colours.

The artist handover (a low-poly 3D rabbit: white fur, orange-and-white ears, orange cape and
suit accents, black belt, orange boots) only changes how the hero looks, so this keeps every
pose of Hoppy's existing art and swaps its palette pixel by pixel, keeping each pixel's shading:

- orange fur and cream muzzle -> white fur with cool grey shadows
- pink inner ears -> orange
- charcoal suit and cape -> orange, bright to dark following the original value
- gold belt and buckle -> black belt
- orange in the bottom band of a standing pose (boots) -> stays orange
- near-black ink outline and eyes -> unchanged
- the stray third ear on the walk_down frames -> cut away and re-inked
- effect marks (swing arcs, shield, scanner, stars) -> unchanged: in the cells that have them,
  warm pixels outside the filled ink outline are left as drawn

Outputs `coderabbit_hero.png` / `coderabbit_hero_locomotion.png` plus SpriteFrames copied from
`hoppy.tres` / `hoppy_locomotion.tres` (same cells, clip names, fps and loop flags).

    uv run --python 3.12 --no-project --with pillow --with numpy --with scipy python tools/build_coderabbit_hero_2d.py
"""

import re
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
HOPPY = ROOT / "Assets/heroes-vs-villains-assets-only/heroes_villains"
OUT = ROOT / "Assets/Character/CodeRabbit/2D/heroes_villains"
RES = "res://Assets/Character/CodeRabbit/2D/heroes_villains/"
CELL = 128

FUR_DARK = np.array([138, 140, 160])
FUR_LIGHT = np.array([252, 250, 246])
CAPE_DARK = np.array([196, 70, 18])
CAPE_LIGHT = np.array([255, 150, 64])
EAR = np.array([246, 112, 34])
BELT = np.array([26, 24, 28])


def hsv(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    r, g, b = (rgb[..., i] / 255.0 for i in range(3))
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    d = mx - mn
    h = np.zeros_like(mx)
    safe = d > 1e-6
    rm, gm, bm = safe & (mx == r), safe & (mx == g) & (mx != r), safe & (mx == b) & (mx != r) & (mx != g)
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    return h * 60, s, mx


def lerp(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0, 1)[..., None]
    return a + (b - a) * t


def figure_rows(solid: np.ndarray, cell: tuple[int, int]):
    """(y0, x0, top, bottom) of the figure in each cell, cell-local; None for an empty cell."""
    cw, ch = cell
    for y0 in range(0, solid.shape[0], ch):
        for x0 in range(0, solid.shape[1], cw):
            ys = np.nonzero(solid[y0:y0 + ch, x0:x0 + cw].any(1))[0]
            yield y0, x0, (ys[0], ys[-1]) if ys.size else None


def below_head(solid: np.ndarray, cell: tuple[int, int]) -> np.ndarray:
    """Everything under the top 42% of each standing cell's figure (lying cells: nothing)."""
    cw, ch = cell
    mask = np.zeros(solid.shape, bool)
    for y0, x0, span in figure_rows(solid, cell):
        if span is None or span[1] - span[0] < 60:
            continue
        mask[y0 + span[0] + int(0.42 * (span[1] - span[0])):y0 + ch, x0:x0 + cw] = True
    return mask


def boots_mask(solid: np.ndarray, cell: tuple[int, int]) -> np.ndarray:
    """The bottom band of each standing cell, where Hoppy's boots are."""
    cw = cell[0]
    mask = np.zeros(solid.shape, bool)
    for y0, x0, span in figure_rows(solid, cell):
        if span is None or span[1] - span[0] < 60:  # lying down (defeat): no boots band
            continue
        mask[y0 + span[1] - 13:y0 + span[1] + 1, x0:x0 + cw] = True
    return mask


# Combat cells (index in hoppy.png's 4x4 grid) with baked effect marks, and the cell-local box
# (x0, y0, x1, y1) each mark sits in: swing arc, kick_warning swirl, kick arc, hurt stars,
# block shield, scanner card. The locomotion sheet has none.
FX_BOXES = {
    7: (74, 0, 128, 128),
    8: (0, 60, 70, 128),
    9: (64, 30, 128, 128),
    10: (74, 0, 128, 70),
    13: (78, 0, 128, 128),
    15: (80, 0, 128, 128),
}


def box_region(shape, boxes: dict, cell: tuple[int, int]) -> np.ndarray:
    """Cell-local (x0, y0, x1, y1) boxes, keyed by cell index (one box or a list of boxes)."""
    cw, ch = cell
    cols = shape[1] // cw
    region = np.zeros(shape, bool)
    for index, entry in boxes.items():
        ox, oy = (index % cols) * cw, (index // cols) * ch
        for x0, y0, x1, y1 in entry if isinstance(entry, list) else [entry]:
            region[oy + y0:oy + y1, ox + x0:ox + x1] = True
    return region


def effect_marks(warm: np.ndarray, ink: np.ndarray, boxes: dict, cell: tuple[int, int]) -> np.ndarray:
    """Warm pixels in an effect box and outside every ink-outlined shape (fur sits inside one)."""
    inside = ndimage.binary_fill_holes(ndimage.binary_dilation(ink, iterations=2))
    return warm & ~inside & box_region(warm.shape, boxes, cell)


def held_items(cls: np.ndarray, alpha: np.ndarray, boxes: dict, cell: tuple[int, int],
               hard: dict | None = None, skin: dict | None = None) -> np.ndarray:
    """A held weapon painted into the sheet: inside its box, every patch of one colour region
    (orange, dark, ...) that lies (almost) wholly in the box. Patches split at ink and at region
    changes, so the paw holding the weapon and the sleeve behind it reach out of the box and are
    still repainted; the ink bordering the kept patches is kept with them."""
    region = box_region(alpha.shape, boxes, cell)
    keep = np.zeros(alpha.shape, bool)
    for group in ((FUR, EAR_IN), (SUIT, BELT_C)):
        paint = (alpha > 40) & np.isin(cls, group)
        labels, count = ndimage.label(paint)  # 4-connected: one-pixel ink lines separate patches
        if count == 0:
            continue
        index = range(1, count + 1)
        total = ndimage.sum(np.ones_like(labels), labels, index)
        inside = ndimage.sum(region, labels, index)
        held = np.zeros(count + 1, bool)
        held[1:] = inside >= 0.8 * total
        keep |= held[labels]
    # Where the weapon touches the paw with no ink between them, a tight hard box around the weapon
    # part keeps everything in it.
    if hard:
        tight = box_region(alpha.shape, hard, cell)
        grab = tight & (alpha > 0)
        # The suit behind the weapon: a dark patch that mostly lies outside the tight box is body.
        suit = (alpha > 40) & np.isin(cls, (SUIT, BELT_C))
        labels, count = ndimage.label(suit)
        if count:
            index = range(1, count + 1)
            inside = ndimage.sum(tight, labels, index) / ndimage.sum(np.ones_like(labels), labels, index)
            body = np.zeros(count + 1, bool)
            body[1:] = inside < 0.6
            grab &= ~body[labels]
        keep |= grab
    keep |= region & (cls == INK) & ndimage.binary_dilation(keep, np.ones((3, 3)), iterations=2)
    # Paws gripping a weapon sit wholly inside its box; skin boxes hand them back to the rabbit.
    if skin:
        keep &= ~box_region(alpha.shape, skin, cell)
    return keep


NONE, INK, FUR, SUIT, EAR_IN, BELT_C, BOOT, FX_C = range(8)


def vote(cls: np.ndarray, open_: np.ndarray, size: int) -> np.ndarray:
    """For every pixel, the most common confident class among its size x size neighbours."""
    counts = np.stack([ndimage.uniform_filter((cls == c).astype(float), size) for c in (FUR, SUIT, EAR_IN, BELT_C)])
    best = np.array([FUR, SUIT, EAR_IN, BELT_C])[counts.argmax(0)]
    return np.where(open_ & (counts.max(0) > 0), best, cls)


def classify(h, s, v, lum, alpha) -> np.ndarray:
    """Region per pixel: confident colours first, then blended and stray pixels join their neighbours."""
    seen = alpha > 0
    cls = np.full(alpha.shape, NONE)
    ink = seen & (lum < 18)
    cls[ink] = INK
    body = seen & ~ink
    hue = np.where(h > 330, h - 360, h)
    cls[body & (hue >= 12) & (hue < 32) & (s >= 0.7) & (v >= 0.5)] = FUR
    cls[body & (hue >= 18) & (hue < 60) & (s < 0.42) & (v >= 0.72)] = FUR  # cream, eye shine
    cls[body & (hue >= -6) & (hue < 14) & (s >= 0.3) & (s < 0.68) & (v >= 0.6)] = EAR_IN
    cls[body & (hue >= 36) & (hue < 55) & (s >= 0.5) & (v >= 0.5)] = BELT_C
    cls[body & (s < 0.3) & (lum < 95)] = SUIT
    # Blends (fur fading into ink, the suit's brown sheen) take their neighbours' region.
    for size in (3, 5, 9, 17):
        cls = vote(cls, body & (cls == NONE), size)
    cls[body & (cls == NONE)] = SUIT
    # Despeckle: a lone pixel unlike almost all its body neighbours joins them.
    for _ in range(2):
        majority = vote(cls, body, 3)
        own = ndimage.uniform_filter((cls == majority).astype(float), 3) * 9
        same = np.zeros(cls.shape)
        for c in (FUR, SUIT, EAR_IN, BELT_C):
            same += (cls == c) * ndimage.uniform_filter((cls == c).astype(float), 3) * 9
        flip = body & (cls != majority) & (same <= 2) & (own >= 5)
        cls[flip] = majority[flip]
    return cls


def reskin(src: Path, cell: tuple[int, int], fx_boxes: dict, item_boxes: dict | None = None,
           item_hard: dict | None = None, item_skin: dict | None = None) -> Image.Image:
    a = np.array(Image.open(src).convert("RGBA")).astype(float)
    rgb, alpha = a[..., :3], a[..., 3]
    h, s, v = hsv(rgb)
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    out = rgb.copy()
    cls = classify(h, s, v, lum, alpha)
    item = held_items(cls, alpha, item_boxes, cell, item_hard, item_skin) if item_boxes else np.zeros(alpha.shape, bool)
    figure = (alpha > 40) & ~item  # head and boots are found on the rabbit, not on a raised weapon

    warm = np.isin(cls, (FUR, EAR_IN)) & (v > 0.42)
    cls[effect_marks(warm, (lum < 40) & (alpha > 128), fx_boxes, cell)] = FX_C
    cls[(cls == FUR) & (s >= 0.5) & boots_mask(figure, cell)] = BOOT

    fur = cls == FUR
    # Orange fur keeps its light and shade as white-to-grey; cream and blends follow luminance,
    # and anything darker than the shadow tone fades toward the ink instead of turning orange.
    t_orange = (v - 0.45) / 0.55
    t_pale = (lum - 70) / 150
    t_fur = np.where(s >= 0.42, t_orange, t_pale)
    fur_rgb = lerp(FUR_DARK, FUR_LIGHT, t_fur)
    to_ink = np.clip(np.where(s >= 0.42, v / 0.45, lum / 70), 0, 1)
    fur_rgb = np.where((to_ink < 1)[..., None], lerp(np.array([20, 18, 24]), FUR_DARK, to_ink), fur_rgb)
    out[fur] = fur_rgb[fur]
    ear = cls == EAR_IN
    out[ear] = (EAR * (0.72 + 0.28 * v[..., None]))[ear]
    suit = cls == SUIT
    out[suit] = lerp(CAPE_DARK, CAPE_LIGHT, (lum - 16) / 55)[suit]
    # Hoppy's deep shadows are solid ink blots inside the black cape; on an orange cape they read
    # as holes. The core of a thick blot touching the suit becomes deep orange (or shadow grey on
    # the white lining); its one-pixel rim stays ink.
    ink = cls == INK
    # "Thick" = six or more ink pixels in its 3x3, so two-pixel crease lines count; one-pixel
    # outlines (three or four) stay ink.
    core = ink & (ndimage.uniform_filter(ink.astype(float), 3) * 9 >= 5.5)
    far = ~ndimage.binary_dilation(alpha <= 40, np.ones((3, 3)))  # the outline touches transparency
    near_suit = ndimage.uniform_filter(suit.astype(float), 9)
    near_fur = ndimage.uniform_filter(fur.astype(float), 9)
    # Blots by the suit, or below the head on a standing figure, are shadows. The eyes are blots
    # too, but they sit in the head, away from the suit.
    blot = core & far & ((near_suit > 0.12) | below_head(figure, cell))
    lining = blot & (near_fur > near_suit)
    out[blot & ~lining] = CAPE_DARK * 0.62
    out[lining] = FUR_DARK * 0.72
    # Thin crease lines drawn inside the suit and cape: ink with only suit around it (no fur, not on
    # the silhouette) becomes a deep orange crease. Outlines against fur stay ink.
    no_fur = ~ndimage.binary_dilation(fur | ear, np.ones((3, 3)))
    edge = ndimage.binary_dilation(alpha <= 40, np.ones((3, 3)), iterations=2)
    crease = ink & no_fur & ~edge & (ndimage.uniform_filter(suit.astype(float), 3) > 0.2)
    out[crease & ~blot] = CAPE_DARK * 0.5
    belt = cls == BELT_C
    out[belt] = lerp(BELT, BELT + 60, (v - 0.45) / 0.55)[belt]
    out[item] = rgb[item]
    result = np.dstack([np.clip(out, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(result, "RGBA")


# hoppy_locomotion.png's walk_down cells (row 4-5) have a stray third ear: a stub on the head's
# top-right, behind the two real ears. Everything above this line (cell-local) right of the real
# ears is cut away, following the head's curve, and the cut edge is re-inked.
STUB_CELLS = range(16, 24)


def stub_cut(x: np.ndarray) -> np.ndarray:
    return 44.0 + (x - 79.0) * 0.95


def remove_stub_ear(img: Image.Image, cols: int) -> Image.Image:
    a = np.array(img)
    for index in STUB_CELLS:
        ox, oy = (index % cols) * CELL, (index // cols) * CELL
        cell = a[oy:oy + CELL, ox:ox + CELL]
        ys, xs = np.mgrid[0:CELL, 0:CELL]
        zone = (xs >= 79) & (xs <= 91) & (ys >= 20) & (ys <= 52)
        cell[zone & (ys < stub_cut(xs))] = 0
        # One-pixel-wide slivers of the stub's outline: clear on both sides, left or right.
        sliver = (xs >= 72) & (xs <= 92) & (ys >= 24) & (ys <= 50)
        for _ in range(3):
            solid = cell[..., 3] > 120  # half-transparent fringe does not anchor a line
            lone = solid.copy()
            lone[:, 1:-1] &= ~solid[:, :-2] & ~solid[:, 2:]
            lone[:, [0, -1]] = False
            cell[lone & sliver] = 0
            cell[sliver & (cell[..., 3] <= 120) & ~ndimage.binary_dilation(cell[..., 3] > 120, np.ones((3, 3)))] = 0
        # The stub's own left outline survives beside the real ear's tip; drop such leftover slivers.
        labels, count = ndimage.label(cell[..., 3] > 0, structure=np.ones((3, 3)))
        sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
        near = (xs >= 70) & (xs <= 95) & (ys >= 20) & (ys <= 56)
        for i, size in enumerate(sizes, start=1):
            piece = labels == i
            if size < 40 and (piece & near).any():
                cell[piece] = 0
        # Re-ink the head's new top edge: opaque zone pixels with nothing directly above.
        clear_above = np.zeros((CELL, CELL), bool)
        clear_above[1:] = cell[:-1, :, 3] == 0
        edge = zone & (ys >= stub_cut(xs)) & (ys < stub_cut(xs) + 2) & (cell[..., 3] > 0) & clear_above
        cell[edge] = (8, 6, 8, 255)
    return Image.fromarray(a, "RGBA")


# Armed sheets (Assets/hoppy-armed/heroes/<weapon>.png, 4x4 cells of 256x160): the weapon is painted
# in Hoppy's own orange and black, so colour cannot tell it apart. Each frame's box (cell-local
# x0, y0, x1, y1, traced from the sheet) bounds the weapon; held_items keeps what lies inside it.
ARMED = ROOT / "Assets/hoppy-armed/heroes"
ARMED_CELL = (256, 160)
WEAPON_BOXES = {
    "review_stamp": {
        0: (98, 92, 134, 139), 1: (100, 92, 140, 138), 2: (103, 92, 144, 138), 3: (108, 93, 144, 138),
        4: (112, 94, 144, 130), 5: (85, 52, 135, 98), 6: (103, 114, 136, 156), 7: (121, 102, 151, 150),
        8: (44, 78, 79, 108), 9: (126, 95, 160, 137), 10: (133, 95, 165, 138), 11: (70, 42, 104, 76),
        12: (105, 110, 141, 153), 13: (127, 110, 162, 153), 14: (111, 71, 145, 118), 15: (106, 81, 143, 122),
    },
    "triage_hammer": {
        0: (104, 92, 154, 134), 1: (96, 92, 142, 134), 2: (100, 90, 145, 133), 3: (100, 88, 140, 130),
        4: (98, 78, 146, 118), 5: [(78, 40, 116, 80), (110, 58, 134, 80)], 6: (140, 110, 186, 152),
        7: (152, 100, 194, 144), 8: (56, 76, 106, 112), 9: (156, 94, 206, 138), 10: (156, 90, 200, 134),
        11: [(74, 38, 116, 76), (112, 62, 130, 80)], 12: (152, 110, 196, 152), 13: (134, 70, 178, 116),
        14: [(52, 48, 88, 88), (84, 64, 94, 80)], 15: [(116, 66, 154, 106), (104, 96, 122, 114)],
    },
    "change_stack_baton": {
        0: (58, 108, 154, 130), 1: (54, 100, 140, 124), 2: (54, 100, 141, 124), 3: (54, 104, 138, 126),
        4: [(48, 90, 82, 104), (80, 96, 114, 112), (112, 104, 146, 126)], 5: (130, 108, 180, 126),
        6: (150, 98, 202, 118), 7: (144, 102, 184, 120), 8: [(74, 74, 100, 92), (98, 86, 130, 112)],
        9: (146, 122, 196, 138), 10: (146, 98, 194, 118), 11: (76, 96, 118, 112), 12: (150, 98, 216, 118),
        13: (136, 102, 174, 118), 14: (120, 104, 154, 120),
        15: [(54, 104, 82, 122), (80, 94, 108, 112), (106, 82, 132, 100)],
    },
    "security_scanner": {
        0: (112, 92, 139, 116), 1: (121, 80, 148, 107), 2: (121, 82, 150, 110), 3: (116, 88, 143, 112),
        4: (126, 82, 152, 108), 5: (77, 96, 106, 121), 6: (154, 84, 184, 108), 7: (161, 102, 189, 126),
        8: (146, 78, 176, 104), 9: (148, 70, 178, 97), 10: (142, 86, 171, 112), 11: (163, 97, 193, 123),
        12: (180, 88, 209, 116), 13: (146, 68, 173, 95), 14: (63, 42, 99, 75), 15: (108, 68, 131, 90),
    },
    "pr_merger": {
        0: (112, 100, 140, 134), 1: (75, 102, 102, 130), 2: (106, 98, 144, 129), 3: (100, 96, 139, 125),
        4: (116, 102, 146, 131), 5: (86, 96, 117, 128), 6: (144, 96, 181, 123), 7: (144, 98, 176, 126),
        8: (103, 96, 130, 126), 9: (146, 92, 178, 122), 10: (139, 92, 161, 122), 11: (103, 110, 133, 139),
        12: (125, 55, 156, 90), 13: (133, 106, 162, 136), 14: (96, 66, 130, 101), 15: (111, 106, 140, 136),
    },
}
# Tight boxes around weapon parts that touch the paw without ink between them (see held_items).
WEAPON_HARD = {
    "review_stamp": {
        0: (112, 97, 132, 115), 2: (116, 93, 137, 112), 5: (86, 51, 108, 72), 7: (126, 102, 146, 121),
        8: [(58, 78, 78, 96), (44, 84, 66, 110)], 10: (140, 97, 161, 117), 13: (134, 109, 156, 129),
    },
    "change_stack_baton": {4: (48, 90, 78, 104), 8: (74, 74, 100, 96)},
}
# The scanner's boxes hug the device, and its orange grip runs straight into the paw: keep it all.
WEAPON_HARD["security_scanner"] = WEAPON_BOXES["security_scanner"]
# The PR merger is a gauntlet worn over the fist: the whole box is the weapon.
WEAPON_HARD["pr_merger"] = WEAPON_BOXES["pr_merger"]
# Paws inside a weapon box (see held_items).
WEAPON_SKIN = {
    "change_stack_baton": {
        0: [(82, 108, 97, 123), (100, 108, 114, 122)], 1: [(79, 104, 93, 119), (99, 104, 112, 119)],
        2: [(78, 104, 92, 118), (97, 104, 110, 118)], 3: [(78, 108, 92, 122), (97, 108, 110, 122)],
        4: [(77, 98, 91, 112), (98, 106, 110, 119)], 5: [(125, 105, 139, 119), (142, 108, 155, 123)], 6: (147, 103, 162, 117),
        8: (97, 91, 111, 106),
    },
}


def retarget(source: Path, png: str, dest: Path) -> None:
    text = source.read_text()
    text, n = re.subn(r'(\[ext_resource type="Texture2D" path=")[^"]+(")', rf"\g<1>{RES}{png}\g<2>", text)
    assert n == 1, source
    dest.write_text(text)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    reskin(HOPPY / "hoppy.png", (CELL, CELL), FX_BOXES).save(OUT / "coderabbit_hero.png", optimize=True)
    loco = remove_stub_ear(reskin(HOPPY / "hoppy_locomotion.png", (CELL, CELL), {}), 4)
    loco.save(OUT / "coderabbit_hero_locomotion.png", optimize=True)
    retarget(HOPPY / "hoppy.tres", "coderabbit_hero.png", OUT / "coderabbit_hero.tres")
    retarget(HOPPY / "hoppy_locomotion.tres", "coderabbit_hero_locomotion.png",
             OUT / "coderabbit_hero_locomotion.tres")
    (OUT / "armed").mkdir(exist_ok=True)
    for weapon, boxes in WEAPON_BOXES.items():
        sheet = reskin(ARMED / f"{weapon}.png", ARMED_CELL, {}, boxes, WEAPON_HARD.get(weapon),
                       WEAPON_SKIN.get(weapon))
        sheet.save(OUT / "armed" / f"{weapon}.png", optimize=True)
        retarget(ARMED / f"{weapon}.tres", f"armed/{weapon}.png", OUT / "armed" / f"{weapon}.tres")
    print("wrote", OUT)


main()
