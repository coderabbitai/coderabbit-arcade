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


def below_head(alpha: np.ndarray, cols: int, rows: int) -> np.ndarray:
    """Everything under the top 42% of each standing cell's figure (lying cells: nothing)."""
    mask = np.zeros(alpha.shape, bool)
    for cy in range(rows):
        for cx in range(cols):
            y0, x0 = cy * CELL, cx * CELL
            ys = np.nonzero((alpha[y0:y0 + CELL, x0:x0 + CELL] > 40).any(1))[0]
            if ys.size == 0 or ys[-1] - ys[0] < 60:
                continue
            mask[y0 + ys[0] + int(0.42 * (ys[-1] - ys[0])):y0 + CELL, x0:x0 + CELL] = True
    return mask


def boots_mask(alpha: np.ndarray, cols: int, rows: int) -> np.ndarray:
    """The bottom band of each standing cell, where Hoppy's boots are."""
    mask = np.zeros(alpha.shape, bool)
    for cy in range(rows):
        for cx in range(cols):
            y0, x0 = cy * CELL, cx * CELL
            cell = alpha[y0:y0 + CELL, x0:x0 + CELL] > 40
            ys = np.nonzero(cell.any(1))[0]
            if ys.size == 0:
                continue
            top, bottom = ys[0], ys[-1]
            if bottom - top < 60:  # lying down (defeat): no boots band
                continue
            mask[y0 + bottom - 13:y0 + bottom + 1, x0:x0 + CELL] = True
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


def effect_marks(warm: np.ndarray, ink: np.ndarray, boxes: dict) -> np.ndarray:
    """Warm pixels in an effect box and outside every ink-outlined shape (fur sits inside one)."""
    inside = ndimage.binary_fill_holes(ndimage.binary_dilation(ink, iterations=2))
    region = np.zeros(warm.shape, bool)
    cols = warm.shape[1] // CELL
    for index, (x0, y0, x1, y1) in boxes.items():
        ox, oy = (index % cols) * CELL, (index // cols) * CELL
        region[oy + y0:oy + y1, ox + x0:ox + x1] = True
    return warm & ~inside & region


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


def reskin(src: Path, cols: int, rows: int, fx_boxes: dict) -> Image.Image:
    a = np.array(Image.open(src).convert("RGBA")).astype(float)
    rgb, alpha = a[..., :3], a[..., 3]
    h, s, v = hsv(rgb)
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    out = rgb.copy()
    cls = classify(h, s, v, lum, alpha)

    warm = np.isin(cls, (FUR, EAR_IN)) & (v > 0.42)
    cls[effect_marks(warm, (lum < 40) & (alpha > 128), fx_boxes)] = FX_C
    cls[(cls == FUR) & (s >= 0.5) & boots_mask(alpha, cols, rows)] = BOOT

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
    blot = core & far & ((near_suit > 0.12) | below_head(alpha, cols, rows))
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


def retarget(source: Path, png: str, dest: Path) -> None:
    text = source.read_text()
    text, n = re.subn(r'(\[ext_resource type="Texture2D" path=")[^"]+(")', rf"\g<1>{RES}{png}\g<2>", text)
    assert n == 1, source
    dest.write_text(text)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    reskin(HOPPY / "hoppy.png", 4, 4, FX_BOXES).save(OUT / "coderabbit_hero.png", optimize=True)
    loco = remove_stub_ear(reskin(HOPPY / "hoppy_locomotion.png", 4, 6, {}), 4)
    loco.save(OUT / "coderabbit_hero_locomotion.png", optimize=True)
    retarget(HOPPY / "hoppy.tres", "coderabbit_hero.png", OUT / "coderabbit_hero.tres")
    retarget(HOPPY / "hoppy_locomotion.tres", "coderabbit_hero_locomotion.png",
             OUT / "coderabbit_hero_locomotion.tres")
    print("wrote", OUT)


main()
