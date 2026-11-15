"""Compatibility entry point for the retained reference-matched story masters.

Uses the same packing and provenance as tools/build_story_scenes.py. No palette
replacement, segmentation or repainting is performed. Only the two hero images
are written; the general story builder can reproduce them too.
"""
from pathlib import Path
import runpy
from PIL import Image


def main():
    repo = Path(__file__).resolve().parents[2]
    builder = runpy.run_path(str(repo / 'tools/build_story_scenes.py'))
    records = builder['read_records']()
    story = builder['STORY']
    for name in ('send_in_the_rabbit', 'rabbit_stands'):
        record = records[('heroes', name)]
        image = builder['cover_crop'](Image.open(story / record['master']))
        builder['atomic_write'](story / 'heroes' / (name + '.png'), builder['png_bytes'](image))


if __name__ == '__main__':
    main()
