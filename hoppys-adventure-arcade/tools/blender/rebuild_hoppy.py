"""Host entrypoint: original build recipe plus export-log and source-copy hygiene.
The recipe hash in hoppy.build.json remains the hash of build_hoppy.py, which
actually authored the accepted geometry. This wrapper does not change the model.
"""
import argparse
import json
import logging
from pathlib import Path
import runpy
import sys

SAMPLER_NOTE = ('More than one shader node tex image used for a texture. '
                'The resulting glTF sampler will behave like the first shader node tex image.')


class SharedORMSampler(logging.Filter):
    count = 0

    def filter(self, record):
        # Blender 5.2 tests socket count, not distinct image nodes. Our G and B
        # sockets come from one image node, so their sampler is identical.
        if record.getMessage() == SAMPLER_NOTE:
            self.count += 1
            return False
        return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--quick', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    logger = logging.getLogger('glTFImporter')
    shared_sampler = SharedORMSampler()
    logger.addFilter(shared_sampler)
    try:
        runpy.run_path(str(Path(__file__).with_name('build_hoppy.py')), run_name='__main__')
    finally:
        logger.removeFilter(shared_sampler)
    report = json.loads(args.out.with_name('hoppy.build.json').read_text())
    # GLB embeds these images; Godot extracts the runtime hoppy_*.png files.
    # Keep no third copy. Delete only the exact loose filenames from this bake.
    for name in report['textures']:
        (args.out.parent / name).unlink()
    print('[hoppy] redundant loose PNGs removed; shared-ORM sampler notices=%d' % shared_sampler.count,
          flush=True)


if __name__ == '__main__':
    main()
