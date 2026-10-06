"""Pack the reviewed 4x6 locomotion master without repainting sprite artwork.

Run with Pillow installed. Alpha and all 24 distinct source cels are preserved.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'hoppys-adventure-arcade/Assets/heroes-vs-villains-assets-only'
OUT = PACK / 'heroes_villains'
SOURCE = PACK / 'sources/hoppy_locomotion.png'


def main():
    source = Image.open(SOURCE).convert('RGBA')
    if source.getchannel('A').getextrema()[0] == 255:
        raise ValueError('The reviewed master must have genuine transparency')
    cuts = []
    # Reviewed transparent gutters: generated rows straddle a nominal 256px grid.
    rows = [0, 286, 550, 801, 1037, 1283, 1536]
    for i in range(24):
        x, y = i % 4, i // 4
        tile = source.crop((x * source.width // 4, rows[y],
                            (x + 1) * source.width // 4, rows[y + 1]))
        bounds = tile.getchannel('A').point(lambda a: 255 if a > 24 else 0).getbbox()
        if bounds is None:
            raise ValueError(f'Empty cell {i}')
        cuts.append(tile.crop(bounds))
    # Match the existing idle's 86-pixel silhouette height at the same foot pivot.
    scale = min(86 / max(c.height for c in cuts), 114 / max(c.width for c in cuts))
    atlas = Image.new('RGBA', (512, 768))
    for i, cut in enumerate(cuts):
        cut = cut.resize((round(cut.width * scale), round(cut.height * scale)), Image.Resampling.NEAREST)
        atlas.alpha_composite(cut, ((i % 4) * 128 + (128 - cut.width) // 2,
                                   (i // 4) * 128 + 29 + [0, 1, 0, -1, 0, 1, 0, -1][i % 8]))
    atlas.save(OUT / 'hoppy_locomotion.png')
    lines = ['[gd_resource type="SpriteFrames" load_steps=26 format=3]',
             '[ext_resource type="Texture2D" path="hoppy_locomotion.png" id="1"]']
    for i in range(24):
        lines += [f'[sub_resource type="AtlasTexture" id="F{i}"]',
                  'atlas = ExtResource("1")',
                  f'region = Rect2({i % 4 * 128}, {i // 4 * 128}, 128, 128)']
    clips = []
    for start, name in [(0, 'run'), (8, 'walk_up'), (16, 'walk_down')]:
        frames = ', '.join('{"duration": 1.0, "texture": SubResource("F%d")}' % i
                           for i in range(start, start + 8))
        clips.append('{"frames": [%s], "loop": true, "name": &"%s", "speed": 14.0}' % (frames, name))
    lines += ['[resource]', 'animations = [' + ',\n'.join(clips) + ']']
    (OUT / 'hoppy_locomotion.tres').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
