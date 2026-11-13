"""Re-skin the CodeRabbit hero in the two Heroes vs. Villains story paintings.

`send_in_the_rabbit.png` (third intro card) and `rabbit_stands.png` (last ending card) show orange
Hoppy. This repaints only the rabbit in the same colours as the in-game sheets
(`tools/build_coderabbit_hero_2d.py`): white fur and cape lining, orange inner ears, orange armour
and cape. Ink, eyes and the background are untouched.

The rabbit is cut out with OpenCV GrabCut, seeded by the hand-traced polygons below (outside =
background, eroded inside = rabbit, plus "sure" polygons for the pale ears that look like stage
light). Edges are feathered by a pixel.

It reads the selected masters (never its own output), so it is safe to re-run. Run it after
`tools/build_story_scenes.py`, which rebuilds these PNGs from the untouched masters:

    uv run --python 3.12 --no-project --with pillow --with numpy --with opencv-python-headless \\
        python tools/build_coderabbit_hero_story.py
"""

import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
STORY_ROOT = ROOT / "Assets/beatemup-story"
STORY = STORY_ROOT / "heroes"
SCENE_SIZE = (1600, 900)

FUR_DARK = np.array([150, 152, 172])
FUR_LIGHT = np.array([252, 250, 246])
CAPE_DARK = np.array([200, 76, 20])
CAPE_LIGHT = np.array([255, 160, 74])
EAR = np.array([246, 112, 34])

SCENES = {
    "send_in_the_rabbit": {
        "outline": [(195, 365), (330, 240), (450, 222), (600, 262), (700, 296), (792, 296), (742, 92),
                    (746, 72), (805, 72), (872, 212), (908, 232), (958, 132), (1012, 136), (1022, 200),
                    (988, 290), (982, 378), (995, 455), (1060, 520), (1140, 640), (1132, 682), (1060, 662),
                    (1062, 792), (912, 792), (905, 722), (860, 690), (805, 642), (700, 640), (640, 652),
                    (622, 700), (614, 800), (444, 800), (455, 700), (560, 642), (605, 580), (600, 568),
                    (490, 568), (480, 520), (380, 505), (300, 470), (240, 420)],
        "sure": [],
    },
    "rabbit_stands": {
        "outline": [(296, 418), (450, 378), (600, 355), (700, 328), (704, 280), (655, 58), (702, 60),
                    (792, 190), (843, 168), (858, 98), (918, 108), (918, 222), (906, 300), (906, 338),
                    (944, 378), (955, 450), (995, 560), (1010, 622), (965, 652), (952, 700), (1034, 800),
                    (1034, 842), (852, 842), (858, 700), (836, 694), (790, 694), (754, 706), (746, 780), (714, 842),
                    (566, 842), (588, 760), (640, 702), (600, 692), (548, 652), (450, 642), (380, 592),
                    (328, 582), (296, 522)],
        "sure": [[(668, 72), (698, 74), (785, 195), (760, 240), (725, 230), (700, 160)],
                 [(862, 108), (910, 116), (908, 215), (880, 240), (850, 190)],
                 [(792, 604), (834, 612), (832, 686), (794, 686)]],  # cape lining between the legs
    },
}


def selected_master(name: str) -> Image.Image:
    """The scene's selected master, cover-cropped exactly as tools/build_story_scenes.py does, so
    this always repaints the original art and running it twice changes nothing."""
    records = json.loads((STORY_ROOT / "refinements.json").read_text())
    record = next(r for r in records if r["mode"] == "heroes" and r["scene"] == name)
    source = Image.open(STORY_ROOT / record["master"]).convert("RGBA")
    scale = max(SCENE_SIZE[0] / source.width, SCENE_SIZE[1] / source.height)
    size = (max(SCENE_SIZE[0], math.ceil(source.width * scale)), max(SCENE_SIZE[1], math.ceil(source.height * scale)))
    resized = source.resize(size, Image.Resampling.LANCZOS)
    left, top = (resized.width - SCENE_SIZE[0]) // 2, (resized.height - SCENE_SIZE[1]) // 2
    return resized.crop((left, top, left + SCENE_SIZE[0], top + SCENE_SIZE[1])).convert("RGB")


def polygon_mask(size: tuple[int, int], polygons: list) -> np.ndarray:
    canvas = Image.new("L", size, 0)
    for poly in polygons:
        ImageDraw.Draw(canvas).polygon(poly, fill=1)
    return np.asarray(canvas).astype(bool)


def rabbit_mask(rgb: np.ndarray, spec: dict) -> np.ndarray:
    size = (rgb.shape[1], rgb.shape[0])
    inside = polygon_mask(size, [spec["outline"]])
    core = cv2.erode(inside.astype(np.uint8), np.ones((3, 3), np.uint8), iterations=28).astype(bool)
    mask = np.full(inside.shape, cv2.GC_BGD, np.uint8)
    mask[inside] = cv2.GC_PR_FGD
    mask[core] = cv2.GC_FGD
    if spec["sure"]:
        mask[polygon_mask(size, spec["sure"]) & inside] = cv2.GC_FGD
    bgd, fgd = np.zeros((1, 65)), np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), mask, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
    return (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)


def hsv(rgb: np.ndarray):
    out = cv2.cvtColor(rgb.astype(np.uint8), cv2.COLOR_RGB2HSV_FULL).astype(float)
    return out[..., 0] * 360 / 256, out[..., 1] / 255, out[..., 2] / 255


def lerp(a, b, t):
    return a + (b - a) * np.clip(t, 0, 1)[..., None]


def repaint(rgb: np.ndarray) -> np.ndarray:
    h, s, v = hsv(rgb)
    lum = rgb.astype(float) @ np.array([0.299, 0.587, 0.114])
    out = rgb.astype(float).copy()
    ink = lum < 28
    eyes = (h >= 70) & (h < 170) & (s > 0.25)
    keep = ink | eyes
    # Region labels ordered so a median of neighbours lands on a sensible one.
    KEEP, DARK, ORANGE, CREAM, PINK, OTHER = 0, 1, 2, 3, 4, 5
    cls = np.full(lum.shape, OTHER, np.uint8)
    pink = ((h >= 340) | (h < 18)) & (s >= 0.15) & (s < 0.6) & (v > 0.6)
    cream = ~pink & (h >= 15) & (h < 55) & (s < 0.38) & (v > 0.7)
    orange = ~pink & ~cream & (h >= 8) & (h < 48) & (s >= 0.4) & (v >= 0.3)
    dark = ~pink & ~cream & ~orange & (lum < 125)
    cls[dark], cls[orange], cls[cream], cls[pink] = DARK, ORANGE, CREAM, PINK
    # Painted texture speckles single pixels across regions (pink flecks in an ear); a 5x5 median
    # of the labels settles each pixel into its surroundings. Ink and eyes stay exact.
    smooth = cv2.medianBlur(cls, 5)
    cls = np.where(keep, KEEP, np.where(cls == OTHER, OTHER, smooth))
    orange, cream, pink, dark = cls == ORANGE, cls == CREAM, cls == PINK, cls == DARK
    out[orange] = lerp(FUR_DARK, FUR_LIGHT, (v - 0.35) / 0.6)[orange]
    out[cream] = lerp(FUR_DARK, FUR_LIGHT, 0.75 + 0.25 * v)[cream]
    out[pink] = (EAR * (0.7 + 0.3 * v[..., None]))[pink]
    out[dark] = lerp(CAPE_DARK, CAPE_LIGHT, (lum - 28) / 65)[dark]
    return np.clip(out, 0, 255)


def main() -> None:
    for name, spec in SCENES.items():
        path = STORY / f"{name}.png"
        rgb = np.asarray(selected_master(name))
        mask = rabbit_mask(rgb, spec)
        soft = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)))
        alpha = (soft / 255.0)[..., None]
        result = rgb * (1 - alpha) + repaint(rgb) * alpha
        Image.fromarray(result.astype(np.uint8)).save(path, optimize=True)
        print("repainted", path.relative_to(ROOT))


main()
