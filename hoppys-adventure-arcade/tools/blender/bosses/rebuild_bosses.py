"""Blender entrypoint for the boss recipes, including the shared-kit fixture.

Blender --background --python-exit-code 1 --python tools/blender/bosses/rebuild_bosses.py --
    --kind kit_selftest|flaky_test_swarm|merge_conflict_hydra|legacy_monolith|all
    --out-dir Assets/runner/bosses [--quick]
Each recipe exports build(out_dir, quick=False). all requires every registered recipe.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
KINDS = json.loads((HERE / 'bosses_budget.json').read_text())['kinds']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=KINDS + ['all'], required=True)
    parser.add_argument('--out-dir', type=Path, default=Path('Assets/runner/bosses'))
    parser.add_argument('--quick', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    kinds = KINDS if args.kind == 'all' else [args.kind]
    paths = [HERE / ('build_' + kind + '.py') for kind in kinds]
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise RuntimeError('Boss recipes are not installed yet: ' + ', '.join(missing))
    sys.path.insert(0, str(HERE))
    for kind, path in zip(kinds, paths):
        spec = importlib.util.spec_from_file_location('boss_recipe_' + kind, path)
        recipe = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(recipe)
        recipe.build(args.out_dir, quick=args.quick)
    print('BOSSES BUILD: PASS (' + ', '.join(kinds) + ')', flush=True)


if __name__ == '__main__':
    main()
