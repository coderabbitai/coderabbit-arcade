"""Downsizes the artist handover textures for the CodeRabbit hero rabbit into game PNGs.

    uv run --python 3.12 --no-project --with pillow python tools/blender/prep_hoppy_hero_textures.py HANDOVER_TEXTURES_DIR

Writes Assets/runner/hoppy_hero/source/*.png, the inputs of build_hoppy_hero.py:
  - <part>_albedo.png  sRGB base colour (the handover albedo already carries its faceted shading)
  - <part>_normal.png  tangent-space normal map (RGB)
  - <part>_orm.png     glTF ORM: R occlusion (none baked: white), G roughness (handover mixmap G),
                       B metallic (handover mixmap B, all zero)
The eyes ship albedo only, so their ORM is a flat glossy dielectric and they have no normal map.
"""
import argparse
from pathlib import Path

from PIL import Image

Image.MAX_IMAGE_PIXELS = None
OUT = Path(__file__).resolve().parents[2] / 'Assets/runner/hoppy_hero/source'
SIZES = {'head': 1024, 'body': 1024, 'eyes': 512}
EYE_ROUGHNESS = 0.18


def fit(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('textures', type=Path, help='handover Textures/ folder (Rabbit_<part>_<map>.tga)')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for part, size in SIZES.items():
        albedo = Image.open(args.textures / f'Rabbit_{part}_albedo.tga').convert('RGB')
        fit(albedo, size).save(OUT / f'{part}_albedo.png', optimize=True)
        mix_path = args.textures / f'Rabbit_{part}_mixmap.tga'
        if mix_path.exists():
            _, rough, metal = fit(Image.open(mix_path).convert('RGB'), size).split()
            white = Image.new('L', (size, size), 255)
            Image.merge('RGB', (white, rough, metal)).save(OUT / f'{part}_orm.png', optimize=True)
            normal = Image.open(args.textures / f'Rabbit_{part}_normal.tga').convert('RGB')
            fit(normal, size).save(OUT / f'{part}_normal.png', optimize=True)
        else:
            flat = Image.new('RGB', (64, 64), (255, round(EYE_ROUGHNESS * 255), 0))
            flat.save(OUT / f'{part}_orm.png', optimize=True)
        print('[hoppy_hero] textures', part, size)


if __name__ == '__main__':
    main()
