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


def reskin(src: Path, cols: int, rows: int, fx_boxes: dict) -> Image.Image:
    a = np.array(Image.open(src).convert("RGBA")).astype(float)
    rgb, alpha = a[..., :3], a[..., 3]
    h, s, v = hsv(rgb)
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    out = rgb.copy()
    seen = alpha > 0

    ink = lum < 16
    pink = seen & ~ink & ((h >= 300) | (h < 12)) & (s > 0.15) & (s < 0.6) & (v > 0.55)
    gold = seen & ~ink & (h >= 34) & (h < 60) & (s > 0.45) & (v > 0.45)
    orange = seen & ~ink & ~pink & ~gold & (h >= 8) & (h < 34) & (s >= 0.5) & (v > 0.42)
    cream = seen & ~ink & ~pink & ~gold & ~orange & (s < 0.5) & (v > 0.6) & (h < 60)
    dark = seen & ~ink & ~pink & ~gold & ~orange & ~cream & (lum < 120)

    warm = orange | cream | pink
    fx = effect_marks(warm, (lum < 40) & (alpha > 128), fx_boxes)
    orange, cream, pink = orange & ~fx, cream & ~fx, pink & ~fx
    boots = orange & boots_mask(alpha, cols, rows)
    fur = (orange & ~boots) | cream
    # Fur value: the brightest orange and cream read white, shadowed orange reads cool grey.
    t_fur = np.where(cream, 0.9 + 0.1 * v, (v - 0.45) / 0.55)
    out[fur] = lerp(FUR_DARK, FUR_LIGHT, t_fur)[fur]
    out[pink] = (EAR * (0.75 + 0.25 * v[..., None]))[pink]
    t_dark = (lum - 16) / 55
    out[dark] = lerp(CAPE_DARK, CAPE_LIGHT, t_dark)[dark]
    out[gold] = lerp(BELT, BELT + 60, (v - 0.45) / 0.55)[gold]
    result = np.dstack([np.clip(out, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(result, "RGBA")


def retarget(source: Path, png: str, dest: Path) -> None:
    text = source.read_text()
    text, n = re.subn(r'(\[ext_resource type="Texture2D" path=")[^"]+(")', rf"\g<1>{RES}{png}\g<2>", text)
    assert n == 1, source
    dest.write_text(text)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    reskin(HOPPY / "hoppy.png", 4, 4, FX_BOXES).save(OUT / "coderabbit_hero.png", optimize=True)
    reskin(HOPPY / "hoppy_locomotion.png", 4, 6, {}).save(OUT / "coderabbit_hero_locomotion.png", optimize=True)
    retarget(HOPPY / "hoppy.tres", "coderabbit_hero.png", OUT / "coderabbit_hero.tres")
    retarget(HOPPY / "hoppy_locomotion.tres", "coderabbit_hero_locomotion.png",
             OUT / "coderabbit_hero_locomotion.tres")
    print("wrote", OUT)


main()
