"""Small mechanical test dummy proving skinning, actions, sockets and baked ORM.

Blender --background --python-exit-code 1 --python tools/blender/bosses/build_kit_selftest.py --
    --out-dir Assets/runner/bosses [--quick]
This is a pipeline fixture, not a final boss design.
"""
import argparse
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_kit import BossBuilder, Part, SOCKETS, xform

RECIPE_REVISION = 2


def pose(kit, action, t):
    pulse = math.sin(t * math.pi)
    if action == 'idle':
        kit.pose('core', location=(0, math.sin(t * math.tau) * 0.06, 0))
        kit.pose('arm', rotation=(0, 0, math.sin(t * math.tau) * 0.16))
    elif action == 'intro':
        kit.pose('root', scale=(0.65 + 0.35 * t,) * 3, rotation=(0, (1 - t) * 0.8, 0))
    elif action == 'telegraph':
        kit.pose('arm', rotation=(0, 0, -t * 0.8))
    elif action == 'attack':
        kit.pose('arm', rotation=(0, 0, -0.8 + pulse * 1.5))
    elif action == 'hurt':
        kit.pose('core', rotation=(pulse * 0.2, 0, pulse * 0.18))
    elif action == 'phase_change':
        kit.pose('core', rotation=(0, t * math.tau, 0), scale=(1 + pulse * 0.15,) * 3)
    elif action == 'defeat':
        # Collapse into fx_core. A matching orthographic camera can undo only the
        # projection change, proving the dissolve mask is invariant under skinning.
        shrink = 1 - t * 0.75
        kit.pose('root', location=(0, 0.78 * (1 - shrink), 0.4 * (1 - shrink)),
                 scale=(shrink,) * 3)
    elif action == 'retreat':
        kit.pose('root', location=(0, t * 0.4, -t * 1.0), scale=(1 - t * 0.4,) * 3)


def build(out_dir, quick=False):
    kit = BossBuilder('kit_selftest', __file__, revision=RECIPE_REVISION, quick=quick, atlas_resolution=256)
    kit.material('shell', '435464', roughness=0.42, metallic=0.65)
    kit.material('core', '79e0c4', finish='plain', roughness=0.3, metallic=0.1,
                 emission='79e0c4', emission_energy=0.8, grunge=0.0)
    kit.material('trim', 'fff0d3', roughness=0.55, metallic=0.15)
    kit.bone('root', (0, 0, 0), (0, 0.2, 0))
    kit.bone('core', (0, 0.2, 0), (0, 1.1, 0), 'root')
    kit.bone('arm', (0.5, 0.7, 0), (1.1, 0.7, 0), 'core')
    body = Part('dummy_core')
    body.box('shell', (1.0, 1.15, 0.65), xform((0, 0.65, 0)), bevel=0.10)
    body.ellipsoid('core', (0.29, 0.29, 0.1), xform((0, 0.78, 0.34)), u=16, v=8)
    body.box('trim', (0.6, 0.08, 0.04), xform((0, 0.30, 0.34)), bevel=0.02)
    kit.add_part(body, 'core')
    arm = Part('dummy_arm')
    arm.box('trim', (0.72, 0.18, 0.22), xform((0.87, 0.7, 0)), bevel=0.04)
    arm.ellipsoid('core', (0.13, 0.13, 0.13), xform((1.24, 0.7, 0)), u=12, v=6)
    kit.add_part(arm, 'arm')
    for i, name in enumerate(SOCKETS):
        position = (0, 0.78, 0.4) if name == 'fx_core' else ((i % 3 - 1) * 0.38, 0.28 + (i // 3) * 0.27, 0.4)
        kit.socket(name, 'arm' if name.startswith('muzzle') else 'core',
                   (1.24, 0.7, (i - 8) * 0.08) if name.startswith('muzzle') else position)
    kit.bake_actions(dict(intro=1.0, idle=2.0, telegraph=0.6, attack=0.5, hurt=0.3,
                          phase_change=1.0, defeat=1.5, retreat=1.0), pose)
    return kit.export(out_dir)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', type=Path, default=Path('Assets/runner/bosses'))
    parser.add_argument('--quick', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    build(args.out_dir, args.quick)
