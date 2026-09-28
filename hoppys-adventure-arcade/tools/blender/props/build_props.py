"""Deterministic hero props for every runner barrier and item. Run from hoppys-adventure-arcade/:

  /Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 \
      --python tools/blender/props/build_props.py -- --out-dir Assets/runner/props [--set hazards|pickups|all] [--quick]

Writes hazard_props.glb / pickup_props.glb (geometry + node layout only; the runtime binds its own
clock-driven shaders), one shared atlas set per family (<set>_albedo / _normal / _orm / _emission .png,
1024 square) and props.build.json (census, bounds, emission share, hashes).

Modelling is in Godot coordinates relative to each hitbox centre, in metres, so the runtime mounts the
props at unit scale. Node naming: `<kind>__<Role>__<index>`; the runtime maps Role to an idle style.
No downloads, fonts or boolean operations; the only randomness is random.Random(SEED).
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import sys

import bpy
import numpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import props_kit as K  # noqa: E402
from props_kit import Part, linear, xform  # noqa: E402

SEED = 52019
REVISION = 1
HERE = Path(__file__).resolve().parent
BUDGET = json.loads((HERE / 'props_budget.json').read_text())
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument('--out-dir', required=True)
parser.add_argument('--set', choices=('hazards', 'pickups', 'all'), default='all')
parser.add_argument('--quick', action='store_true', help='Skip UV packing and baking (geometry iteration only)')
opts = parser.parse_args(argv)
OUT = Path(opts.out_dir).resolve()
OUT.mkdir(parents=True, exist_ok=True)
RNG = random.Random(SEED)
PI = math.pi


def log(message):
    print('[props] ' + message, flush=True)


# --- palette (runner_palette.gd) -----------------------------------------------------------------
NAVY_BG, NAVY, NAVY_2, SLATE = linear('08111c'), linear('101d2d'), linear('142735'), linear('435464')
CREAM, MINT, MATRIX, ORANGE = linear('fff0d3'), linear('79e0c4'), linear('63f9b2'), linear('f78949')
DANGER, LILAC = linear('ff4d3d'), linear('a99bff')
BODY_MINT = linear('73e6bf')  # MINT.lerp(MATRIX, 0.25), power_up_art.gd BODY_MINT
WHITE = (1.0, 1.0, 1.0)


def scaled(colour, k):
    return tuple(c * k for c in colour)


# Hazard finishes: dark industrial neutrals + DANGER as the single accent (LILAC only on "theirs").
# Pickup finishes: CREAM shells, dark grips, MINT or ORANGE inlays; their emission bakes as a grey mask
# that the runtime tints with the family colour, so a pickup can never glow red.
FINISHES = {
    'hz_hull': dict(base=linear('2b3f52'), rough=0.42, metal=0.62, kind='paint', period=0.55),
    'hz_steel': dict(base=linear('8b9ca9'), rough=0.30, metal=0.88, kind='paint', period=0.35, wear=0.25),
    'hz_dark': dict(base=linear('17232f'), rough=0.52, metal=0.45, kind='paint', period=0.45),
    'hz_rubber': dict(base=linear('15181c'), rough=0.86, metal=0.0, kind='rubber', tread=46.0, grunge=0.1),
    'hz_stripe': dict(base=linear('1b2129'), stripe_colour=scaled(DANGER, 0.75), rough=0.48, metal=0.3,
                      kind='stripe', stripes=4.0),
    'hz_red': dict(base=scaled(DANGER, 0.55), rough=0.38, metal=0.35, kind='paint', period=0.4, wear=0.2),
    'hz_glow': dict(base=DANGER, rough=0.3, metal=0.0, kind='plain', emit=DANGER, emit_strength=1.0,
                    grunge=0.05),
    'hz_scan': dict(base=scaled(DANGER, 0.35), rough=0.25, metal=0.0, kind='plain', emit=DANGER,
                    emit_strength=0.9, emit_mask='scan', scan_rows=70.0, grunge=0.05),
    'hz_crate': dict(base=linear('2c3b4b'), rough=0.46, metal=0.5, kind='paint', period=0.21, wear=0.3),
    'hz_label': dict(base=linear('131d28'), rough=0.5, metal=0.2, kind='lines', rows=22.0, dash=11.0,
                     ink=scaled(CREAM, 0.42), period=2.0),
    'hz_card': dict(base=linear('0f1924'), rough=0.5, metal=0.2, kind='lines', rows=24.0, dash=7.0,
                    ink=scaled(CREAM, 0.34), period=3.0, segment_scale=4.0, wear=0.15),
    'hz_avatar': dict(base=scaled(CREAM, 0.85), rough=0.4, metal=0.05, kind='plain', grunge=0.08),
    'hz_lilac_body': dict(base=linear('3a3462'), rough=0.40, metal=0.6, kind='paint', period=0.55),
    'hz_lilac_label': dict(base=linear('1d1a36'), rough=0.5, metal=0.2, kind='lines', rows=22.0, dash=11.0,
                           ink=scaled(LILAC, 0.6), period=2.0),
    'hz_lilac_glow': dict(base=LILAC, rough=0.3, metal=0.0, kind='plain', emit=LILAC, emit_strength=0.8,
                          grunge=0.05),
    'hz_shell': dict(base=linear('161b26'), rough=0.18, metal=0.65, kind='plain', grunge=0.25,
                     grunge_scale=18.0),
    'hz_elytra': dict(base=linear('b02a1d'), rough=0.16, metal=0.35, kind='plain', emit=DANGER,
                      emit_strength=0.45, emit_mask='veins', vein_colour=linear('ff6a55'), grunge=0.12),
    'hz_wing': dict(base=linear('4c1410'), rough=0.3, metal=0.1, kind='plain', emit=DANGER,
                    emit_strength=0.55, emit_mask='veins', vein_colour=linear('d8402f'), grunge=0.1),
    'hz_legacy': dict(base=linear('3d4148'), rough=0.82, metal=0.05, kind='legacy', period=0.9,
                      grunge=0.3, grunge_height=0.6),
    'hz_crest': dict(base=linear('5a1a14'), rough=0.3, metal=0.2, kind='plain', emit=DANGER, emit_strength=1.0,
                     emit_mask='rise', rise_from=0.07, rise_to=0.22, grunge=0.1),
    'hz_lens': dict(base=linear('06080b'), rough=0.08, metal=0.3, kind='plain', grunge=0.02),
    'pk_shell': dict(base=scaled(CREAM, 0.26), rough=0.45, metal=0.06, kind='shell', period=0.34, wear=0.0,
                     wear_colour=scaled(CREAM, 0.42), grunge=0.08, grunge_scale=20.0),
    'pk_grip': dict(base=linear('1f2830'), rough=0.8, metal=0.0, kind='rubber', tread=140.0, grunge=0.1),
    'pk_chrome': dict(base=linear('7d8a95'), rough=0.28, metal=0.85, kind='paint', period=0.12, wear=0.15),
    'pk_mint': dict(base=BODY_MINT, rough=0.28, metal=0.1, kind='plain', emit=WHITE, emit_strength=0.9,
                    grunge=0.05),
    'pk_mint_paint': dict(base=BODY_MINT, rough=0.35, metal=0.1, kind='plain', grunge=0.08),
    'pk_orange_paint': dict(base=ORANGE, rough=0.35, metal=0.1, kind='plain', grunge=0.08),
    'pk_mint_core': dict(base=MINT, rough=0.25, metal=0.05, kind='plain', emit=WHITE, emit_strength=1.0,
                         grunge=0.04),
    'pk_mint_glass': dict(base=linear('2b6f63'), rough=0.06, metal=0.2, kind='plain', emit=WHITE,
                          emit_strength=0.6, grunge=0.03),
    'pk_orange': dict(base=ORANGE, rough=0.3, metal=0.1, kind='plain', emit=WHITE, emit_strength=0.9,
                      grunge=0.05),
    'pk_orange_core': dict(base=ORANGE, rough=0.26, metal=0.05, kind='plain', emit=WHITE,
                           emit_strength=1.0, grunge=0.04),
    'pk_orange_glass': dict(base=linear('7a4424'), rough=0.06, metal=0.2, kind='plain', emit=WHITE,
                            emit_strength=0.55, grunge=0.03),
}
MATERIALS = {}


def materials_for(names):
    for name in names:
        if name not in MATERIALS:
            MATERIALS[name] = K.make_finish(name, FINISHES[name])
    return MATERIALS


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 4
scene.cycles.seed = SEED
if scene.world is None:
    scene.world = bpy.data.worlds.new('props world')
scene.world.light_settings.distance = 0.35
COLLECTION = scene.collection


class Family:
    """One GLB + atlas set. Roots are spread along X so each kind bakes its own occlusion."""

    def __init__(self, name, spacing):
        self.name = name
        self.spacing = spacing
        self.roots = []
        self.templates = []  # one object per unique mesh (UV + bake representatives)
        self.parts = {}

    def root(self, name):
        obj = K.empty(COLLECTION, name, xform((len(self.roots) * self.spacing, 0, 0)))
        self.roots.append(obj)
        return obj

    def mesh(self, part, parent, matrix=None, name=None):
        tris = part.triangles()
        obj = part.to_object(COLLECTION, materials_for(part.finishes))
        K.place(obj, matrix, parent)
        if name:
            obj.name = name
        obj['triangles'] = tris
        self.templates.append(obj)
        return obj

    def inst(self, template, name, matrix, parent):
        return K.instance(COLLECTION, name, template, matrix, parent)


def descendants(obj):
    out = []
    for child in obj.children:
        out.append(child)
        out.extend(descendants(child))
    return out


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def jitter(amount):
    return (RNG.random() * 2.0 - 1.0) * amount


def bolts(part, finish, a, b, count, radius=0.016, depth=0.012, rot=(PI / 2, 0, 0)):
    for i in range(count):
        part.cylinder(finish, radius, depth, xform(lerp(a, b, i / max(1, count - 1)), rot), segments=6)


def outline_scale(points, k, dx=0.0, dy=0.0):
    return [(x * k + dx, y * k + dy) for x, y in points]


# ================================================================================================
# Hazards (hitbox-centred metres; see hazard_defs.gd sizes)
# ================================================================================================
def pr_backlog_low(fam):
    """Jammed merge-queue conveyor of stacked PR crates (JUMP). 5.6 x 1.0 x 1.2."""
    root = fam.root('HZ_pr_backlog_low')
    bed = Part('pr_backlog_low__Conveyor')
    for z in (-0.5, 0.5):
        bed.box('hz_steel', (5.5, 0.12, 0.09), xform((0, -0.385, z)), bevel=0.018)
        bed.box('hz_glow', (4.9, 0.016, 0.01), xform((0, -0.36, z + 0.047 * (1 if z > 0 else -1))))
    bed.box('hz_rubber', (5.32, 0.05, 0.92), xform((0, -0.315, 0)), bevel=0.012)
    bed.box('hz_hull', (5.4, 0.10, 0.86), xform((0, -0.40, 0)), bevel=0.01)
    for x in (-2.68, 2.68):
        bed.cylinder('hz_steel', 0.085, 1.02, xform((x, -0.33, 0), (PI / 2, 0, 0)), segments=14, bevel=0.01)
    for x in (-2.3, -0.8, 0.8, 2.3):
        for z in (-0.46, 0.46):
            bed.box('hz_dark', (0.12, 0.08, 0.12), xform((x, -0.46, z)), bevel=0.01)
    # Merge-queue gates at both ends: striped crossbar, red beacon, rivets.
    for side in (-1, 1):
        x = side * 2.86
        for z in (-0.42, 0.42):
            bed.box('hz_hull', (0.20, 0.92, 0.26), xform((x, -0.04, z)), bevel=0.025)
        bed.box('hz_stripe', (0.24, 0.13, 1.12), xform((x, 0.38, 0)), bevel=0.02)
        bed.cylinder('hz_dark', 0.075, 0.05, xform((x, 0.465, 0)), segments=12)
        bed.cylinder('hz_glow', 0.055, 0.07, xform((x, 0.51, 0)), segments=12, bevel=0.01)
        bolts(bed, 'hz_steel', (x, -0.35, 0.555), (x, 0.25, 0.555), 4)
    bed.box('hz_stripe', (5.3, 0.10, 0.03), xform((0, -0.44, 0.56)), bevel=0.008)
    conveyor = fam.mesh(bed, root, name='pr_backlog_low__Conveyor__0')
    crate = Part('pr_backlog_low__Crate')
    crate.box('hz_crate', (0.64, 0.40, 0.62), bevel=0.035, segments=1)
    crate.box('hz_dark', (0.67, 0.05, 0.65), xform((0, 0.175, 0)), bevel=0.014, segments=1)
    crate.box('hz_label', (0.42, 0.21, 0.02), xform((-0.03, -0.02, 0.315)), bevel=0.006, segments=1)
    for x in (-0.25, 0.25):
        crate.box('hz_red', (0.05, 0.405, 0.63), xform((x, 0, 0)))
    crate.box('hz_glow', (0.07, 0.03, 0.012), xform((0.19, 0.12, 0.317)))
    crate.box('hz_glow', (0.03, 0.03, 0.012), xform((0.19, 0.06, 0.317)))
    template = None
    layout = [(-2.24, -0.09, 0.05, 0.10, 0.0), (-1.55, -0.09, -0.06, -0.08, 0.0), (-0.84, -0.075, 0.02, 0.16, 0.07),
              (-0.10, -0.09, -0.04, -0.05, 0.0), (0.62, -0.09, 0.07, 0.12, 0.0), (1.36, -0.09, -0.02, -0.14, 0.0),
              (2.12, -0.09, 0.03, 0.06, 0.0), (-1.9, 0.315, 0.0, 0.22, 0.0), (-0.46, 0.315, -0.05, -0.12, 0.0),
              (0.98, 0.315, 0.04, 0.09, 0.0), (1.72, 0.315, -0.08, -0.25, 0.0)]
    for i, (x, y, z, yaw, tilt) in enumerate(layout):
        matrix = xform((x, y, z), (0, yaw, tilt))
        if template is None:
            template = fam.mesh(crate, root, matrix, name='pr_backlog_low__Crate__0')
        else:
            fam.inst(template, 'pr_backlog_low__Crate__%d' % i, matrix, root)
    del conveyor


def pr_backlog_high(fam):
    """Hanging review-scanner gantry (ROLL). 5.6 x 1.8 x 1.2, underside at world y 1.1."""
    root = fam.root('HZ_pr_backlog_high')
    g = Part('pr_backlog_high__Gantry')
    for z in (-0.40, 0.40):
        g.box('hz_steel', (5.44, 0.14, 0.14), xform((0, 0.80, z)), bevel=0.02)
        g.box('hz_steel', (5.44, 0.11, 0.11), xform((0, 0.34, z)), bevel=0.016)
        for i in range(10):
            x0 = -2.5 + i * 0.5
            a, b = ((x0, 0.34, z), (x0 + 0.5, 0.80, z)) if i % 2 == 0 else ((x0, 0.80, z), (x0 + 0.5, 0.34, z))
            g.tube('hz_steel', [a, b], 0.026, sides=6)
    for x in (-2.2, -1.1, 0.0, 1.1, 2.2):
        g.box('hz_dark', (0.08, 0.08, 0.84), xform((x, 0.80, 0)), bevel=0.01)
    # Side towers: the gantry hangs from them; striped bands mark the hazard ends.
    for side in (-1, 1):
        x = side * 2.80
        for z in (-0.36, 0.36):
            g.box('hz_hull', (0.20, 1.74, 0.24), xform((x, 0.0, z)), bevel=0.03)
            g.box('hz_stripe', (0.22, 0.32, 0.26), xform((x, -0.58, z)), bevel=0.02)
        g.box('hz_dark', (0.16, 0.14, 0.60), xform((x, 0.10, 0)), bevel=0.015)
        g.tube('hz_steel', [(x, -0.75, -0.30), (x, 0.70, 0.30)], 0.024, sides=6)
    # Review fascia: a red scanline "REVIEW REQUIRED" band behind the ROLL tag.
    g.box('hz_dark', (4.9, 0.34, 0.07), xform((0, 0.56, 0.48)), bevel=0.012)
    g.box('hz_scan', (4.7, 0.05, 0.012), xform((0, 0.69, 0.52)))
    g.box('hz_scan', (4.7, 0.05, 0.012), xform((0, 0.43, 0.52)))
    # Scanner rail, hangers and the underside sensor bar (the edge you roll beneath).
    g.box('hz_steel', (5.2, 0.08, 0.10), xform((0, -0.50, 0.18)), bevel=0.012)
    for x in (-2.0, -0.7, 0.7, 2.0):
        g.cylinder('hz_steel', 0.024, 0.84, xform((x, -0.08, 0.18)), segments=8)
    for x in (-1.3, 1.3):
        g.box('hz_dark', (0.06, 0.30, 0.06), xform((x, -0.68, 0.30)))
    g.box('hz_dark', (5.3, 0.07, 0.14), xform((0, -0.84, 0.30)), bevel=0.012)
    g.box('hz_glow', (5.1, 0.02, 0.02), xform((0, -0.873, 0.372)))
    for z, sag in ((-0.20, -0.30), (-0.05, -0.22)):
        pts = [(-2.0 + 0.4 * k, 0.30 + sag * math.sin(PI * k / 10.0), z) for k in range(11)]
        g.tube('hz_rubber', pts, 0.022, sides=6)
    fam.mesh(g, root, name='pr_backlog_high__Gantry__0')
    head = Part('pr_backlog_high__ScanHead')
    head.box('hz_hull', (0.50, 0.20, 0.30), bevel=0.03)
    head.box('hz_stripe', (0.52, 0.05, 0.31), xform((0, 0.06, 0)), bevel=0.01)
    for x in (-0.16, 0.16):
        head.cylinder('hz_steel', 0.04, 0.05, xform((x, 0.11, -0.06), (PI / 2, 0, 0)), segments=10)
    head.cylinder('hz_lens', 0.075, 0.06, xform((0, -0.12, 0.02)), segments=16)
    head.ring('hz_glow', 0.08, 0.012, xform((0, -0.15, 0.02)), segments=20, sides=5)
    head.ellipsoid('hz_glow', (0.05, 0.03, 0.02), xform((0, 0.0, 0.155)), u=10, v=6)
    first = fam.mesh(head, root, xform((-1.2, -0.62, 0.18)), name='pr_backlog_high__ScanHead__0')
    fam.inst(first, 'pr_backlog_high__ScanHead__1', xform((1.2, -0.62, 0.18)), root)
    ticket = Part('pr_backlog_high__Ticket')
    ticket.tube('hz_steel', [(0, 0, 0), (0, -0.08, 0)], 0.006, sides=4)
    ticket.box('hz_steel', (0.06, 0.03, 0.03), xform((0, -0.085, 0)))
    ticket.box('hz_label', (0.26, 0.32, 0.018), xform((0, -0.26, 0)), bevel=0.006, segments=1)
    ticket.box('hz_red', (0.26, 0.04, 0.02), xform((0, -0.13, 0)))
    first = None
    for i, x in enumerate((-2.2, -1.5, -0.85, 0.8, 1.45, 2.15)):
        matrix = xform((x, 0.28, 0.42), (0, jitter(0.2), jitter(0.05)))
        if first is None:
            first = fam.mesh(ticket, root, matrix, name='pr_backlog_high__Ticket__0')
        else:
            fam.inst(first, 'pr_backlog_high__Ticket__%d' % i, matrix, root)


def bug_body():
    b = Part('bug_swarm__BugBody')
    # Flattened (not clamped) underside: no coincident vertices, so no order-dependent weld.
    flat = lambda co: (co.x, co.y if co.y > 0 else co.y * 0.45, co.z)  # noqa: E731
    for side in (-1, 1):
        b.ellipsoid('hz_elytra', (0.10, 0.085, 0.21), xform((side * 0.072, 0.03, -0.05), (0, 0, side * -0.10)),
                    u=12, v=8, shape=flat)
    b.tube('hz_glow', [(0, 0.118, 0.12), (0, 0.122, -0.04), (0, 0.07, -0.24)], 0.008, sides=5)
    b.ellipsoid('hz_shell', (0.135, 0.07, 0.20), xform((0, -0.03, -0.04)), u=10, v=6)
    b.ellipsoid('hz_shell', (0.13, 0.075, 0.10), xform((0, 0.035, 0.15)), u=12, v=7)
    b.ellipsoid('hz_shell', (0.075, 0.055, 0.065), xform((0, 0.0, 0.25)), u=10, v=6)
    for side in (-1, 1):
        b.ellipsoid('hz_glow', (0.026, 0.026, 0.026), xform((side * 0.048, 0.022, 0.285)), u=6, v=4)
        b.tube('hz_steel', [(side * 0.03, -0.02, 0.30), (side * 0.065, -0.03, 0.35), (side * 0.024, -0.035, 0.39)],
               0.012, sides=5, radius_end=0.003)
        b.tube('hz_dark', [(side * 0.03, 0.04, 0.29), (side * 0.09, 0.12, 0.35), (side * 0.15, 0.15, 0.33)],
               0.006, sides=4, radius_end=0.003)
        for z0, dz in ((0.12, 0.06), (0.02, 0.0), (-0.10, -0.07)):
            b.tube('hz_dark', [(side * 0.10, -0.04, z0), (side * 0.22, 0.035, z0 + dz),
                               (side * 0.30, -0.205, z0 + dz * 1.6)], 0.016, sides=5, radius_end=0.007)
            b.ellipsoid('hz_steel', (0.02, 0.02, 0.02), xform((side * 0.22, 0.035, z0 + dz)), u=6, v=4)
    return b


def bug_swarm(fam):
    """Three armoured beetle bugs with red wing covers (JUMP or change lane). 1.6 x 0.9 x 1.2."""
    root = fam.root('HZ_bug_swarm')
    body = bug_body()
    wing = Part('bug_swarm__Wing')
    teardrop = [(0.0, 0.0)] + [(0.055 * math.sin(PI * t / 8.0) * (1.0 - 0.35 * t / 8.0), -0.30 * t / 8.0)
                               for t in range(1, 9)]
    teardrop += [(-x, y) for x, y in reversed(teardrop[1:-1])]
    wing.prism('hz_wing', teardrop, 0.006, xform((0, 0, 0), (PI / 2, 0, 0)))
    wing.tube('hz_dark', [(0, 0, 0), (0.0, 0.0, -0.26)], 0.005, sides=4, radius_end=0.002)
    body_template = None
    wing_template = None
    layout = [(-0.44, -0.24, 0.10, 0.16, 0.35), (0.0, 0.12, -0.12, -0.05, 0.75), (0.44, -0.24, 0.05, -0.18, 0.35)]
    for i, (x, y, z, yaw, spread) in enumerate(layout):
        bug = K.empty(COLLECTION, 'bug_swarm__Bug__%d' % i, xform((x, y, z), (0, yaw, 0)), root)
        if body_template is None:
            body_template = fam.mesh(body, bug, name='bug_swarm__BugBody__%d' % i)
        else:
            fam.inst(body_template, 'bug_swarm__BugBody__%d' % i, None, bug)
        for side, tag in ((-1, 'L'), (1, 'R')):
            matrix = xform((side * 0.06, 0.10, 0.03), (0.0, -side * (0.35 + spread * 0.3), side * spread * 0.5))
            name = 'bug_swarm__Wing__%d%s' % (i, tag)
            if wing_template is None:
                wing_template = fam.mesh(wing, bug, matrix, name=name)
            else:
                fam.inst(wing_template, name, matrix, bug)


def merge_half(side, finishes):
    body, label, glow = finishes
    part = Part('merge_conflict__' + ('Ours' if side < 0 else 'Theirs'))
    # Jagged inner fracture on the +x side of the local slab (mirrored for "theirs").
    edge = [(0.80, 0.47), (0.72, 0.31), (0.84, 0.13), (0.70, -0.04), (0.83, -0.21), (0.73, -0.36), (0.80, -0.47)]
    outline = [(-0.84, -0.47)] + list(reversed(edge)) + [(-0.84, 0.47)]
    outline = [(x, y) for x, y in reversed(outline)]
    s = -side  # local +x points at the fracture
    mirrored = [(x * s, y) for x, y in outline]
    part.prism(body, mirrored, 0.44, bevel=0.018, segments=2)
    part.box(label, (1.36, 0.60, 0.02), xform((-0.06 * s, 0.02, 0.228)), bevel=0.006, segments=1)
    part.box('hz_dark', (1.50, 0.12, 0.03), xform((-0.04 * s, 0.39, 0.232)), bevel=0.008, segments=1)
    for k in range(3):
        cx = (-0.62 + k * 0.10) * s
        pts = [(cx + 0.03 * s, 0.43, 0.0), (cx - 0.02 * s, 0.39, 0.0), (cx + 0.03 * s, 0.35, 0.0)]
        part.tube('hz_steel', pts, 0.009, xform((0, 0, 0.25)), sides=4)
    # Diff gutter: - markers on "ours", + markers on "theirs".
    part.box('hz_dark', (0.07, 0.60, 0.024), xform((-0.76 * s, 0.02, 0.230)))
    for k in range(4):
        y = 0.22 - k * 0.15
        part.box(glow, (0.045, 0.014, 0.01), xform((-0.76 * s, y, 0.244)))
        if side > 0:
            part.box(glow, (0.014, 0.045, 0.01), xform((-0.76 * s, y, 0.244)))
    # Fracture glow along the front lip of the jagged edge.
    part.tube(glow, [(x * s - 0.012 * s, y, 0.222) for x, y in edge], 0.011, sides=5)
    part.box('hz_hull' if side < 0 else body, (1.72, 0.08, 0.52), xform((-0.02 * s, -0.47, 0)), bevel=0.012)
    # Conflict warning: striped kick plate along the base and a red header band on both halves.
    part.box('hz_stripe', (1.60, 0.07, 0.02), xform((-0.02 * s, -0.47, 0.262)))
    part.box('hz_red', (1.50, 0.02, 0.032), xform((-0.04 * s, 0.315, 0.232)))
    part.box('hz_red', (0.02, 0.86, 0.46), xform((-0.845 * s, 0.0, 0.0)))
    bolts(part, 'hz_steel', (-0.80 * s, -0.40, 0.235), (-0.80 * s, 0.30, 0.235), 5)
    bolts(part, 'hz_steel', (-0.45 * s, -0.40, 0.235), (0.45 * s, -0.40, 0.235), 5)
    return part


def merge_conflict(fam):
    """Split diff slab: <<<<<<< ours | >>>>>>> theirs (LILAC only on theirs). 3.6 x 1.0 x 1.2."""
    root = fam.root('HZ_merge_conflict')
    ours = merge_half(-1, ('hz_hull', 'hz_label', 'hz_glow'))
    theirs = merge_half(1, ('hz_lilac_body', 'hz_lilac_label', 'hz_lilac_glow'))
    fam.mesh(ours, root, xform((-0.90, 0.0, 0.0), (0, 0.035, 0)), name='merge_conflict__Ours__0')
    fam.mesh(theirs, root, xform((0.90, 0.0, 0.0), (0, -0.035, 0)), name='merge_conflict__Theirs__0')


def pit_rim(fam, variant, width, depth=3.0):
    """Crumbling legacy-code trench rim at floor level (top <= 0.02 m) with @deprecated plates."""
    root = fam.root('HZ_deprecated_pit_' + variant)
    rim = Part('deprecated_pit__Rim' + ('Full' if variant == 'full' else 'TwoLane'))
    mx, mz = width * 0.44, depth * 0.42
    ox, oz = width * 0.53, depth * 0.535

    def ring_band(inner_x, inner_z, outer_x, outer_z, step, fn):
        # Walk the four sides of the rectangular band and emit tiles.
        for axis in ('x', 'z'):
            for sign in (-1, 1):
                length = 2 * (outer_x if axis == 'x' else outer_z)
                count = max(2, int(length / step))
                for k in range(count):
                    t0, t1 = -length / 2 + k * length / count, -length / 2 + (k + 1) * length / count
                    fn(axis, sign, t0, t1, inner_x, inner_z, outer_x, outer_z)

    def tile(axis, sign, t0, t1, ix, iz, ox_, oz_):
        gap = 0.012
        top = 0.011 + RNG.random() * 0.006
        if axis == 'x':
            # Front/back bands run along x between the inner and outer z edges.
            if t1 < -ox_ + 0.001 or t0 > ox_ - 0.001:
                return
            r0, r1 = iz, oz_
            centre = ((t0 + t1) / 2, top - 0.025, sign * (r0 + r1) / 2)
            size = (t1 - t0 - gap, 0.05, r1 - r0 - gap)
        else:
            if abs((t0 + t1) / 2) > iz:
                return
            r0, r1 = ix, ox_
            centre = (sign * (r0 + r1) / 2, top - 0.025, (t0 + t1) / 2)
            size = (r1 - r0 - gap, 0.05, t1 - t0 - gap)
        rim.box('hz_legacy', size, xform(centre, (jitter(0.004), 0, jitter(0.004))), bevel=0.008, segments=1)

    ring_band(mx + 0.02, mz + 0.02, width * 0.505, depth * 0.505, 0.62, tile)
    # Hazard-striped outer frame, flush with the floor.
    for sign in (-1, 1):
        rim.box('hz_stripe', (2 * ox - 0.02, 0.012, oz - depth * 0.505 - 0.005), xform((0, 0.004, sign * (oz + depth * 0.505) / 2)))
        rim.box('hz_stripe', (ox - width * 0.505 - 0.005, 0.012, 2 * depth * 0.505), xform((sign * (ox + width * 0.505) / 2, 0.004, 0)))
    # Crumbling lip: broken chunks sag into the well over the mouth edge; a broken red lip marks it.
    for axis in ('x', 'z'):
        for sign in (-1, 1):
            length = 2 * (mx if axis == 'x' else mz)
            count = int(length / 0.26)
            for k in range(count):
                t = -length / 2 + (k + 0.5) * length / count + jitter(0.03)
                along = 0.16 + RNG.random() * 0.08
                radial = 0.07 + RNG.random() * 0.06
                sag = 0.10 + RNG.random() * 0.25
                # Outer edge stays at the floor; the inner edge sags into the well.
                cy = 0.014 - (0.02 * math.cos(sag) + radial * 0.5 * math.sin(sag)) - 0.004
                if axis == 'x':
                    centre = (t, cy, sign * (mz + 0.02 - radial * 0.3))
                    rot = (-sign * sag, 0, 0)
                    size = (along, 0.04, radial)
                else:
                    centre = (sign * (mx + 0.02 - radial * 0.3), cy, t)
                    rot = (0, 0, sign * sag)
                    size = (radial, 0.04, along)
                rim.box('hz_legacy', size, xform(centre, rot), bevel=0.006, segments=1)
                if k % 3 != 1:
                    lip = (along * 0.8, 0.008, 0.016) if axis == 'x' else (0.016, 0.008, along * 0.8)
                    lx = t if axis == 'x' else sign * (mx + 0.025)
                    lz = sign * (mz + 0.025) if axis == 'x' else t
                    rim.box('hz_glow', lip, xform((lx, 0.009, lz)))
    # @deprecated plaques on the far and side rims (the readable tag lies on the near rim).
    plaques = [((-width * 0.22, -(mz + oz) / 2 + 0.02), 0.0), ((width * 0.22, -(mz + oz) / 2 + 0.02), 0.0)]
    if variant == 'full':
        plaques += [((-(mx + ox) / 2 + 0.03, 0.0), PI / 2), (((mx + ox) / 2 - 0.03, 0.0), PI / 2)]
    for (px, pz), yaw in plaques:
        rim.box('hz_label', (0.86, 0.02, 0.20), xform((px, 0.008, pz), (0, yaw, 0)), bevel=0.006, segments=1)
        strike = (0.70, 0.004, 0.016) if yaw == 0 else (0.016, 0.004, 0.70)
        rim.box('hz_glow', strike, xform((px, 0.017, pz)))
        for dx in (-0.39, 0.39):
            bx, bz = (px + dx, pz) if yaw == 0 else (px, pz + dx)
            rim.cylinder('hz_steel', 0.014, 0.008, xform((bx, 0.0145, bz)), segments=6)
    lo, hi = rim.bounds()
    K.require(hi.y <= 0.0201, 'pit rim rises above the floor: %.4f' % hi.y)
    fam.mesh(rim, root, name='deprecated_pit_%s__Rim__0' % variant)


def laser_grid(fam):
    """CI linter emitter pods (all four variants share them; mid scales y by 0.75). 5.6 x 0.4 x 1.2."""
    root = fam.root('HZ_laser_grid')
    pod = Part('laser_grid__Emitter')
    pod.box('hz_hull', (0.30, 0.40, 0.60), bevel=0.035, segments=2)
    pod.box('hz_dark', (0.03, 0.34, 0.50), xform((0.155, 0, 0)), bevel=0.008, segments=1)
    for y in (-0.112, 0.0, 0.112):
        pod.cylinder('hz_lens', 0.045, 0.05, xform((0.172, y, 0), (0, 0, -PI / 2)), segments=14)
        pod.ring('hz_glow', 0.05, 0.008, xform((0.198, y, 0), (0, 0, PI / 2)), segments=16, sides=4)
    for z in (-0.20, -0.10, 0.0, 0.10, 0.20):
        pod.box('hz_steel', (0.05, 0.34, 0.022), xform((-0.170, 0, z)))
    pod.box('hz_glow', (0.16, 0.012, 0.30), xform((0.0, 0.204, 0)))
    pod.box('hz_stripe', (0.305, 0.10, 0.02), xform((0, -0.12, 0.302)))
    pod.box('hz_stripe', (0.305, 0.10, 0.02), xform((0, -0.12, -0.302)))
    bolts(pod, 'hz_steel', (-0.10, 0.12, 0.303), (0.10, 0.12, 0.303), 3)
    first = fam.mesh(pod, root, xform((-2.62, 0, 0)), name='laser_grid__Emitter__0')
    fam.inst(first, 'laser_grid__Emitter__1', xform((2.62, 0, 0), (0, PI, 0)), root)


def comment_flood(fam):
    """A wall of stacked review-thread cards (change lane). 3.6 x 4.0 x 1.2."""
    root = fam.root('HZ_comment_flood')
    spine = Part('comment_flood__Spine')
    for x in (-1.2, 0.0, 1.2):
        spine.cylinder('hz_steel', 0.014, 3.86, xform((x - 0.30, 0.0, -0.12)), segments=8)
        for k in range(8):
            spine.box('hz_dark', (0.05, 0.05, 0.08), xform((x - 0.30, -1.62 + k * 0.46 - 0.18, -0.08)))
    spine.box('hz_dark', (3.5, 0.10, 0.22), xform((0, 1.93, -0.12)), bevel=0.015)
    spine.box('hz_hull', (3.5, 0.12, 0.52), xform((0, -1.94, 0)), bevel=0.02)
    spine.box('hz_stripe', (3.52, 0.05, 0.53), xform((0, -1.865, 0)), bevel=0.008)
    fam.mesh(spine, root, name='comment_flood__Spine__0')
    card = Part('comment_flood__Card')
    card.box('hz_card', (0.92, 0.32, 0.06), bevel=0.022, segments=1)
    card.cylinder('hz_avatar', 0.07, 0.02, xform((-0.35, 0.05, 0.035), (PI / 2, 0, 0)), segments=12)
    card.box('hz_glow', (0.04, 0.26, 0.02), xform((0.435, 0, 0.022)))
    card.box('hz_card', (0.10, 0.07, 0.04), xform((-0.30, -0.18, -0.01)))
    first = None
    index = 0
    for column, x in enumerate((-1.2, 0.0, 1.2)):
        for row in range(8):
            y = -1.62 + row * 0.46 + jitter(0.03)
            z = 0.14 if (row + column) % 2 == 0 else 0.0
            matrix = xform((x + jitter(0.05), y, z), (jitter(0.05), jitter(0.12), jitter(0.06)))
            name = 'comment_flood__Card__%d' % index
            if first is None:
                first = fam.mesh(card, root, matrix, name=name)
            else:
                fam.inst(first, name, matrix, root)
            index += 1


def build_shockwave(fam):
    """Cracked build-pipeline ring rolling down the corridor (JUMP). 5.6 x 0.5 x 1.2."""
    root = fam.root('HZ_build_shockwave')
    pipe = Part('build_shockwave__Pipe')
    radius, zc, y0, r = 6.0, 0.36 - 6.0, -0.09, 0.15
    limit = math.asin(2.92 / radius)
    cracks = [-limit, -0.30, -0.105, 0.09, 0.29, limit]
    for k in range(5):
        a0, a1 = cracks[k] + (0.0 if k == 0 else 0.018), cracks[k + 1] - (0.0 if k == 4 else 0.018)
        drop = 0.0 if k % 2 == 0 else -0.012
        pts = [(radius * math.sin(a0 + (a1 - a0) * s / 11), y0 + drop, zc + radius * math.cos(a0 + (a1 - a0) * s / 11))
               for s in range(12)]
        pipe.tube('hz_steel' if k % 2 == 0 else 'hz_hull', pts, r, sides=10)
        for a in (a0, a1):
            # Flange discs: cylinder axis (Godot Y) turned onto the arc tangent (cos a, 0, -sin a).
            centre = (radius * math.sin(a), y0 + drop, zc + radius * math.cos(a))
            pipe.cylinder('hz_dark', 0.172, 0.045, xform(centre, (0, a, -PI / 2), order='ZYX'), segments=14, bevel=0.008)
        mid = (a0 + a1) / 2
        centre = (radius * math.sin(mid), y0 + drop, zc + radius * math.cos(mid))
        pipe.cylinder('hz_stripe', r + 0.006, 0.16, xform(centre, (0, mid, -PI / 2), order='ZYX'), segments=12)
    # Fractures: red energy leaks through every crack, jagged fins rise along the crest.
    for a in cracks[1:-1]:
        for j in range(4):
            ang = a + jitter(0.008)
            cx, cz = radius * math.sin(ang), zc + radius * math.cos(ang)
            shard = [(0, 0.0), (0.025, 0.07 + j * 0.02), (-0.02, 0.12 + j * 0.015)]
            pipe.prism('hz_glow', shard, 0.02, xform((cx, y0 - 0.06 + j * 0.03, cz), (0, ang + j * 0.8, jitter(0.4))))
        pipe.ring('hz_glow', r + 0.004, 0.012, xform((radius * math.sin(a), y0, zc + radius * math.cos(a)),
                                                     (0, a, -PI / 2), order='ZYX'), segments=16, sides=4)
    # Shock crest: a jagged glowing ribbon riding the ring, brightest at its broken top edge.
    for k in range(5):
        a0, a1 = cracks[k] + 0.03, cracks[k + 1] - 0.03
        steps = 16
        path = [(radius * math.sin(a0 + (a1 - a0) * s / steps), y0 + r * 0.55,
                 zc + radius * math.cos(a0 + (a1 - a0) * s / steps) + 0.02) for s in range(steps + 1)]
        heights = [0.07 + 0.075 * (1.0 if s % 2 else 0.35) * (0.7 + 0.3 * math.sin(k * 3.1 + s)) for s in range(steps + 1)]
        pipe.ribbon('hz_crest', path, heights, 0.018)
    fam.mesh(pipe, root, name='build_shockwave__Pipe__0')
    shard = Part('build_shockwave__Shard')
    outline = [(0.0, 0.05), (0.035, 0.02), (0.03, -0.035), (-0.01, -0.05), (-0.04, 0.0)]
    shard.prism('hz_dark', outline, 0.03, bevel=0.004)
    shard.box('hz_glow', (0.012, 0.06, 0.034), xform((0.0, 0.0, 0.0), (0, 0, 0.4)))
    first = None
    for k in range(14):
        a = -limit + 0.1 + (2 * limit - 0.2) * k / 13
        cx, cz = radius * math.sin(a), zc + radius * math.cos(a) + jitter(0.12)
        matrix = xform((cx, 0.10 + jitter(0.04), cz), (jitter(PI), jitter(PI), jitter(PI)))
        name = 'build_shockwave__Shard__%d' % k
        if first is None:
            first = fam.mesh(shard, root, matrix, name=name)
        else:
            fam.inst(first, name, matrix, root)


# ================================================================================================
# Pickups (pickup sphere r 0.35 at the origin; sculpture inside r 0.37 in XZ and |y| <= 0.44)
# ================================================================================================
def pickup(fam, kind, shell, core, core_origin):
    root = fam.root('PU_' + kind)
    fam.mesh(shell, root, name=kind + '__Ring__0')
    fam.mesh(core, root, xform(core_origin), name=kind + '__InnerCore__0')


def paint(inlay):
    """Non-emissive family-colour panels: large accent areas without raising the glow share."""
    return inlay + '_paint'


def check_mark(part, finish, centre, scale=1.0, depth=0.03):
    cx, cy, cz = centre
    part.box(finish, (0.10 * scale, 0.034 * scale, depth), xform((cx - 0.050 * scale, cy - 0.016 * scale, cz), (0, 0, -0.75)),
             bevel=0.006, segments=1)
    part.box(finish, (0.20 * scale, 0.034 * scale, depth), xform((cx + 0.038 * scale, cy + 0.020 * scale, cz), (0, 0, 0.85)),
             bevel=0.006, segments=1)


def approve_shield(fam, inlay, core_finish):
    shell = Part('approve_shield__Ring')
    outline = [(-0.27, 0.20), (-0.10, 0.225), (0.0, 0.20), (0.10, 0.225), (0.27, 0.20), (0.262, -0.02),
               (0.19, -0.19), (0.0, -0.33), (-0.19, -0.19), (-0.262, -0.02)]
    shell.prism('pk_shell', outline, 0.10, xform((0, 0, 0.02)), bevel=0.02, segments=2)
    shell.prism(paint(inlay), outline_scale(outline, 0.78, 0, 0.01), 0.012, xform((0, 0, 0.074)))
    loop = outline_scale(outline, 0.84, 0, 0.005)
    shell.tube(inlay, [(x, y, 0.078) for x, y in loop + loop[:1]], 0.011, sides=5, caps=False)
    ear = [(0.0, 0.0), (0.045, 0.05), (0.05, 0.15), (0.025, 0.225), (0.0, 0.24), (-0.025, 0.225), (-0.05, 0.15),
           (-0.045, 0.05)]
    for side in (-1, 1):
        shell.prism('pk_shell', ear, 0.05, xform((side * 0.11, 0.19, -0.01), (0, 0, -side * 0.2)), bevel=0.012)
        shell.prism(inlay, outline_scale(ear, 0.6, 0, 0.04), 0.02, xform((side * 0.11, 0.19, 0.022), (0, 0, -side * 0.2)))
    shell.cylinder('pk_chrome', 0.13, 0.12, xform((0, -0.02, -0.09), (PI / 2, 0, 0)), segments=20, bevel=0.012)
    shell.cylinder('pk_grip', 0.09, 0.04, xform((0, -0.02, -0.165), (PI / 2, 0, 0)), segments=16)
    core = Part('approve_shield__InnerCore')
    check_mark(core, core_finish, (0.0, -0.01, 0.0), 1.45, 0.035)
    pickup(fam, 'approve_shield', shell, core, (0, -0.02, 0.09))


def code_review(fam, inlay, core_finish):
    shell = Part('code_review__Ring')
    for side in (-1, 1):
        x = side * 0.135
        shell.cylinder('pk_shell', 0.105, 0.30, xform((x, 0, 0), (PI / 2, 0, 0)), segments=20, bevel=0.012)
        shell.cylinder(paint(inlay), 0.12, 0.07, xform((x, 0, 0.14), (PI / 2, 0, 0)), segments=20, bevel=0.01)
        shell.cylinder('pk_grip', 0.075, 0.07, xform((x, 0, -0.18), (PI / 2, 0, 0)), segments=16)
        shell.cylinder('pk_grip', 0.108, 0.05, xform((x, 0, -0.05), (PI / 2, 0, 0)), segments=20)
        shell.tube(inlay, [(x + 0.109 * math.cos(a * PI / 10), 0.109 * math.sin(a * PI / 10), 0.05) for a in range(21)],
                   0.009, sides=5, caps=False)
    shell.box('pk_chrome', (0.14, 0.08, 0.18), xform((0, 0.03, 0)), bevel=0.015)
    shell.cylinder('pk_grip', 0.045, 0.07, xform((0, 0.10, 0.0), (0, 0, PI / 2)), segments=14)
    shell.tube('pk_grip', [(-0.23, 0.06, -0.08), (-0.18, 0.22, -0.08), (0.0, 0.30, -0.08), (0.18, 0.22, -0.08),
                           (0.23, 0.06, -0.08)], 0.014, sides=6)
    core = Part('code_review__InnerCore')
    for side in (-1, 1):
        core.cylinder(core_finish, 0.092, 0.014, xform((side * 0.135, 0, 0), (PI / 2, 0, 0)), segments=20)
    pickup(fam, 'code_review', shell, core, (0, 0, 0.178))


def super_jump(fam, inlay, core_finish):
    shell = Part('super_jump__Ring')
    for side in (-1, 1):
        x = side * 0.15
        shell.box('pk_shell', (0.15, 0.27, 0.17), xform((x, 0.06, -0.03)), bevel=0.035, segments=2)
        shell.box('pk_grip', (0.17, 0.05, 0.19), xform((x, 0.205, -0.03)), bevel=0.012)
        shell.box('pk_shell', (0.16, 0.11, 0.26), xform((x, -0.13, 0.04)), bevel=0.04, segments=2)
        shell.ellipsoid('pk_shell', (0.08, 0.06, 0.07), xform((x, -0.12, 0.155)), u=12, v=7)
        shell.box('pk_grip', (0.17, 0.035, 0.30), xform((x, -0.20, 0.045)), bevel=0.01)
        shell.box(paint(inlay), (0.12, 0.20, 0.012), xform((x, 0.07, 0.057)), bevel=0.004, segments=1)
        shell.box(inlay, (0.02, 0.035, 0.16), xform((x + side * 0.077, 0.08, -0.03)))
        shell.box(inlay, (0.02, 0.035, 0.16), xform((x + side * 0.077, 0.00, -0.03)))
        shell.prism('pk_chrome', [(0.0, 0.0), (0.10, 0.02), (0.0, 0.10)], 0.02,
                    xform((x, -0.05, -0.12), (0, PI / 2, 0)))
    core = Part('super_jump__InnerCore')
    for side in (-1, 1):
        x = side * 0.15
        pts = [(x + 0.05 * math.cos(t * PI / 6), -0.012 - 0.15 * t / 36, 0.045 * 0 + 0.05 * math.sin(t * PI / 6))
               for t in range(37)]
        core.tube(core_finish, pts, 0.011, sides=5)
        core.cylinder(core_finish, 0.065, 0.016, xform((x, -0.17, 0)), segments=16)
    pickup(fam, 'super_jump', shell, core, (0, -0.215, 0.045))


def nitro(fam, inlay, core_finish):
    shell = Part('nitro__Ring')
    profile = [(0.0, -0.27), (0.06, -0.26), (0.09, -0.22), (0.095, 0.17), (0.08, 0.23), (0.04, 0.27), (0.0, 0.28)]
    for side in (-1, 1):
        x = side * 0.12
        shell.lathe(paint(inlay), profile, xform((x, 0.02, 0)), segments=18, cap_top=False, cap_bottom=False)
        shell.cylinder('pk_chrome', 0.045, 0.06, xform((x, -0.28, 0)), segments=14, radius_top=0.06)
        shell.cylinder('pk_shell', 0.0975, 0.10, xform((x, -0.01, 0)), segments=18)
        shell.box(inlay, (0.05, 0.22, 0.03), xform((x, 0.03, 0.082)), bevel=0.008)
        for fin in range(3):
            yaw = fin * 2 * PI / 3 + side * 0.4
            shell.prism('pk_shell', [(0.0, 0.0), (0.06, -0.02), (0.0, 0.10)], 0.018,
                        xform((x + 0.085 * math.sin(yaw), -0.20, 0.085 * math.cos(yaw)), (0, yaw + PI / 2, 0)))
    for y in (0.12, -0.12):
        shell.box('pk_chrome', (0.30, 0.05, 0.10), xform((0, y, 0)), bevel=0.012)
        for side in (-1, 1):
            shell.cylinder('pk_grip', 0.1, 0.045, xform((side * 0.12, y, 0)), segments=18)
    shell.box('pk_grip', (0.34, 0.32, 0.05), xform((0, 0.0, -0.13)), bevel=0.015)
    core = Part('nitro__InnerCore')
    for side in (-1, 1):
        core.cylinder(core_finish, 0.0, 0.11, xform((side * 0.12, -0.055, 0)), segments=12, radius_top=0.05)
        core.cylinder(core_finish, 0.0, 0.13, xform((side * 0.12, -0.065, 0.0)), segments=10, radius_top=0.03)
    pickup(fam, 'nitro', shell, core, (0, -0.295, 0))


def auto_fix(fam, inlay, core_finish):
    shell = Part('auto_fix__Ring')
    shell.box('pk_shell', (0.085, 0.50, 0.07), xform((-0.02, -0.06, 0), (0, 0, -0.62)), bevel=0.02)
    jaw = []
    for k in range(13):
        a = math.radians(40 + k * 280 / 12)
        jaw.append((0.115 * math.cos(a), 0.115 * math.sin(a)))
    for k in range(13):
        a = math.radians(320 - k * 280 / 12)
        jaw.append((0.055 * math.cos(a), 0.055 * math.sin(a)))
    shell.prism(paint(inlay), jaw, 0.07, xform((0.15, 0.16, 0), (0, 0, -0.1)), bevel=0.012)
    shell.cylinder('pk_shell', 0.075, 0.07, xform((-0.19, -0.28, 0), (PI / 2, 0, 0)), segments=18, bevel=0.012)
    shell.cylinder('pk_grip', 0.035, 0.08, xform((-0.19, -0.28, 0), (PI / 2, 0, 0)), segments=12)
    for k in range(3):
        shell.box('pk_grip', (0.09, 0.02, 0.075), xform((-0.02 - 0.05 * k, -0.10 - 0.07 * k, 0), (0, 0, -0.62)))
    shell.ellipsoid(paint(inlay), (0.10, 0.07, 0.10), xform((0, 0.06, 0.03)), u=16, v=9)
    shell.ellipsoid(inlay, (0.05, 0.022, 0.02), xform((0, 0.07, 0.125)), u=10, v=6)
    shell.box('pk_grip', (0.14, 0.12, 0.08), xform((0, 0.03, -0.12)), bevel=0.02)
    shell.cylinder('pk_chrome', 0.014, 0.25, xform((0, 0.25, 0.0)), segments=8)
    core = Part('auto_fix__InnerCore')
    core.ring(core_finish, 0.155, 0.017, segments=28, sides=6)
    for k in range(3):
        core.box(core_finish, (0.30, 0.008, 0.035), xform((0, 0, 0), (0, k * PI / 3, 0.12)))
    core.cylinder('pk_chrome', 0.03, 0.03, segments=12)
    pickup(fam, 'auto_fix', shell, core, (0, 0.385, 0))


def lgtm(fam, inlay, core_finish):
    shell = Part('lgtm__Ring')
    shell.ellipsoid(paint(inlay), (0.09, 0.075, 0.09), xform((0, 0.335, 0)), u=16, v=9)
    shell.lathe('pk_chrome', [(0.03, 0.10), (0.036, 0.14), (0.03, 0.20), (0.05, 0.25), (0.035, 0.28)],
                segments=14, cap_top=False, cap_bottom=False)
    shell.cylinder('pk_grip', 0.075, 0.04, xform((0, 0.12, 0)), segments=18, bevel=0.008)
    shell.box('pk_shell', (0.46, 0.15, 0.30), xform((0, 0.02, 0)), bevel=0.03, segments=2)
    shell.box(inlay, (0.465, 0.025, 0.305), xform((0, 0.07, 0)))
    for z in (0.152, -0.152):
        shell.box(paint(inlay), (0.40, 0.07, 0.012), xform((0, 0.015, z)), bevel=0.004, segments=1)
    shell.box('pk_grip', (0.44, 0.05, 0.28), xform((0, -0.08, 0)), bevel=0.01)
    core = Part('lgtm__InnerCore')
    core.box(core_finish, (0.30, 0.016, 0.16), xform((0, -0.02, 0)))
    check_mark(core, core_finish, (0.0, 0.10, 0.14), 1.05, 0.02)
    core.box(core_finish, (0.30, 0.012, 0.02), xform((0, 0.04, 0.14)))
    pickup(fam, 'lgtm', shell, core, (0, -0.10, 0.015))


def review_comment(fam, inlay, core_finish):
    shell = Part('review_comment__Ring')
    bubble = []
    for k in range(9):
        a = k * PI / 16
        bubble.append((0.21 + 0.05 * math.cos(a), 0.12 + 0.05 * math.sin(a)))
    for k in range(9):
        a = PI / 2 + k * PI / 16
        bubble.append((-0.21 + 0.05 * math.cos(a), 0.12 + 0.05 * math.sin(a)))
    bubble += [(-0.26, -0.11), (-0.20, -0.16), (-0.19, -0.27), (-0.10, -0.16), (0.21, -0.16), (0.26, -0.11)]
    shell.prism('pk_shell', bubble, 0.05, xform((0, 0.02, 0)), bevel=0.014)
    shell.box(paint(inlay), (0.44, 0.05, 0.012), xform((0, 0.155, 0.026)), bevel=0.004, segments=1)
    for y in (0.215, -0.165):
        shell.cylinder(paint(inlay), 0.042, 0.56, xform((0, y, -0.01), (0, 0, PI / 2)), segments=16)
        for side in (-1, 1):
            shell.cylinder(inlay, 0.05, 0.03, xform((side * 0.29, y, -0.01), (0, 0, PI / 2)), segments=16, bevel=0.006)
    shell.box('pk_grip', (0.16, 0.20, 0.20), xform((0, 0.02, -0.12)), bevel=0.03)
    core = Part('review_comment__InnerCore')
    for y, w in ((0.07, 0.34), (0.01, 0.28), (-0.05, 0.20)):
        core.box(core_finish, (w, 0.03, 0.014), xform((-0.02 - (0.34 - w) / 2, y, 0)), bevel=0.004, segments=1)
    pickup(fam, 'review_comment', shell, core, (0, 0.02, 0.031))


def lint_rule(fam, inlay, core_finish):
    shell = Part('lint_rule__Ring')
    shell.lathe('pk_shell', [(0.045, -0.34), (0.06, -0.30), (0.10, -0.22), (0.20, -0.07), (0.215, 0.20),
                             (0.235, 0.24), (0.235, 0.30), (0.20, 0.305)], segments=22, cap_top=False, cap_bottom=True)
    shell.ring('pk_grip', 0.22, 0.02, xform((0, 0.305, 0)), segments=28, sides=6)
    shell.cylinder(paint(inlay), 0.2195, 0.12, xform((0, 0.03, 0)), segments=22)
    shell.cylinder(inlay, 0.222, 0.02, xform((0, 0.10, 0)), segments=22)
    shell.cylinder('pk_chrome', 0.04, 0.08, xform((0, -0.37, 0)), segments=12)
    shell.cylinder('pk_grip', 0.205, 0.02, xform((0, 0.25, 0)), segments=22)
    core = Part('lint_rule__InnerCore')
    for k in range(5):
        z = -0.14 + k * 0.07
        w = 2 * math.sqrt(max(0.0, 0.19 ** 2 - z ** 2))
        core.box(core_finish, (w, 0.02, 0.028), xform((0, 0, z)), bevel=0.004, segments=1)
    core.box(core_finish, (0.028, 0.02, 0.36), bevel=0.004, segments=1)
    pickup(fam, 'lint_rule', shell, core, (0, 0.275, 0))


def unit_test(fam, inlay, core_finish):
    shell = Part('unit_test__Ring')
    for y in (0.30, -0.30):
        shell.cylinder(paint(inlay), 0.20, 0.06, xform((0, y, 0), (0, PI / 6, 0)), segments=6, bevel=0.012)
        shell.cylinder(inlay, 0.205, 0.015, xform((0, y + (0.02 if y < 0 else -0.02), 0), (0, PI / 6, 0)), segments=6)
    for k in range(3):
        a = PI / 6 + k * 2 * PI / 3
        shell.cylinder('pk_chrome', 0.02, 0.56, xform((0.16 * math.sin(a), 0, 0.16 * math.cos(a))), segments=8)
    shell.cylinder('pk_grip', 0.09, 0.05, xform((0, 0.245, 0)), segments=18)
    core = Part('unit_test__InnerCore')
    core.lathe(core_finish, [(0.0, -0.23), (0.045, -0.22), (0.066, -0.18), (0.068, -0.13), (0.068, -0.06)],
               segments=18, cap_top=True, cap_bottom=False)
    shell.lathe('pk_shell', [(0.0705, -0.07), (0.0705, 0.20), (0.05, 0.23)], segments=18, cap_top=True, cap_bottom=False)
    check_mark(core, core_finish, (0.0, 0.20, 0.18), 0.8, 0.02)
    pickup(fam, 'unit_test', shell, core, (0, 0.0, 0))


def auto_fix_patch(fam, inlay, core_finish):
    shell = Part('auto_fix_patch__Ring')
    shell.box('pk_shell', (0.54, 0.34, 0.09), xform((0, 0.03, 0.03)), bevel=0.022, segments=2)
    shell.box(inlay, (0.44, 0.10, 0.012), xform((0, 0.12, 0.078)))
    shell.box('pk_grip', (0.28, 0.12, 0.012), xform((0, -0.02, 0.078)), bevel=0.004, segments=1)
    shell.prism('pk_grip', [(-0.18, 0.0), (0.18, 0.0), (0.14, 0.07), (-0.14, 0.07)], 0.02, xform((0, -0.14, 0.07)))
    for x in (-0.23, 0.23):
        for y in (-0.10, 0.16):
            shell.cylinder('pk_chrome', 0.012, 0.01, xform((x, y, 0.078), (PI / 2, 0, 0)), segments=6)
    shell.box('pk_chrome', (0.48, 0.24, 0.16), xform((0, -0.06, -0.10)), bevel=0.02)
    shell.box('pk_grip', (0.40, 0.03, 0.10), xform((0, -0.19, -0.10)))
    core = Part('auto_fix_patch__InnerCore')
    for x in (-0.085, 0.085):
        core.cylinder(core_finish, 0.042, 0.014, xform((x, 0, 0), (PI / 2, 0, 0)), segments=12)
        for k in range(3):
            core.box(core_finish, (0.012, 0.05, 0.02), xform((x, 0, 0.004), (0, 0, k * PI / 3)))
    core.box(core_finish, (0.10, 0.022, 0.012), xform((0, 0.0, 0.0)))
    core.box(core_finish, (0.022, 0.07, 0.012), xform((0, 0.0, 0.0)))
    pickup(fam, 'auto_fix_patch', shell, core, (0, -0.02, 0.08))


POWER_UPS = [('approve_shield', approve_shield), ('code_review', code_review), ('super_jump', super_jump),
             ('nitro', nitro), ('auto_fix', auto_fix), ('lgtm', lgtm)]
TOOLS = [('review_comment', review_comment), ('lint_rule', lint_rule), ('unit_test', unit_test),
         ('auto_fix_patch', auto_fix_patch)]
# Relative texel density per template: hero surfaces read up close; long structure reads from afar.
TEXEL_WEIGHTS = {'pr_backlog_low__Crate': 2.2, 'pr_backlog_high__Ticket': 2.0, 'comment_flood__Card': 2.6,
                 'bug_swarm__BugBody': 1.8, 'bug_swarm__Wing': 1.5, 'pr_backlog_high__ScanHead': 1.6,
                 'laser_grid__Emitter': 1.7, 'merge_conflict__Ours': 1.5, 'merge_conflict__Theirs': 1.5,
                 'build_shockwave__Shard': 1.2, 'pr_backlog_low__Conveyor': 0.8, 'pr_backlog_high__Gantry': 0.7,
                 'build_shockwave__Pipe': 0.85, 'deprecated_pit__RimFull': 0.75, 'deprecated_pit__RimTwoLane': 0.75,
                 'comment_flood__Spine': 0.6}
HAZARD_SIZES = {'pr_backlog_low': (5.6, 1.0, 1.2), 'pr_backlog_high': (5.6, 1.8, 1.2), 'bug_swarm': (1.6, 0.9, 1.2),
                'merge_conflict': (3.6, 1.0, 1.2), 'deprecated_pit_full': (5.6, 0.4, 3.0),
                'deprecated_pit_two_lane': (3.6, 0.4, 3.0), 'laser_grid': (5.6, 0.4, 1.2),
                'comment_flood': (3.6, 4.0, 1.2), 'build_shockwave': (5.6, 0.5, 1.2)}


def census(fam):
    """Per-root triangles (instances counted), unique meshes and root-local bounds (Godot frame)."""
    report = {}
    bpy.context.view_layer.update()
    for obj in fam.templates:
        log('mesh %s tris=%d' % (obj.data.name, K.mesh_triangles(obj)))
    for root in fam.roots:
        inv = root.matrix_world.inverted()
        tris, meshes = 0, set()
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for obj in descendants(root):
            if obj.type != 'MESH':
                continue
            tris += K.mesh_triangles(obj)
            meshes.add(obj.data.name)
            local = K.B2G @ inv @ obj.matrix_world
            for v in obj.data.vertices:
                p = local @ v.co
                lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
                hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
        report[root.name] = {'triangles': tris, 'meshes': sorted(meshes), 'bounds': [list(lo), list(hi)]}
    return report


def check_budgets(fam, report):
    problems = []
    for name, entry in report.items():
        lo, hi = Vector(entry['bounds'][0]), Vector(entry['bounds'][1])
        log('census %s tris=%d meshes=%d bounds=%s..%s' % (name, entry['triangles'], len(entry['meshes']),
                                                          tuple(round(c, 3) for c in lo), tuple(round(c, 3) for c in hi)))
        if name.startswith('HZ_'):
            size = Vector(HAZARD_SIZES[name[3:]])
            half = size * (BUDGET['envelope'] / 2.0)
            if entry['triangles'] > BUDGET['hazard_prop_triangles']:
                problems.append('%s triangles %d' % (name, entry['triangles']))
            for axis in range(3):
                if lo[axis] < -half[axis] - 1e-4 or hi[axis] > half[axis] + 1e-4:
                    problems.append('%s outside 110%% hitbox on axis %d (half %.3f)' % (name, axis, half[axis]))
        else:
            if entry['triangles'] > BUDGET['pickup_prop_triangles']:
                problems.append('%s triangles %d' % (name, entry['triangles']))
            if lo.y < -BUDGET['pickup_half_height'] or hi.y > BUDGET['pickup_half_height']:
                problems.append('%s vertical bound %.3f %.3f' % (name, lo.y, hi.y))
    K.require(not problems, '; '.join(problems))


def pickup_radius(fam):
    for root in fam.roots:
        inv = root.matrix_world.inverted()
        radius = 0.0
        for obj in descendants(root):
            if obj.type != 'MESH':
                continue
            local = K.B2G @ inv @ obj.matrix_world
            for v in obj.data.vertices:
                p = local @ v.co
                radius = max(radius, math.hypot(p.x, p.z))
        K.require(radius <= BUDGET['pickup_radius'] - 0.012, '%s horizontal radius %.3f' % (root.name, radius))
        log('radius %s %.3f' % (root.name, radius))


def emission_share(fam, emission_image, resolution):
    """Area-weighted share of each root's surface whose baked emission is lit (instances counted)."""
    data = numpy.empty(resolution * resolution * 4, dtype=numpy.float32)
    emission_image.pixels.foreach_get(data)
    data = data.reshape(resolution, resolution, 4)
    out = {}
    for root in fam.roots:
        lit, total = 0.0, 0.0
        for obj in descendants(root):
            if obj.type != 'MESH':
                continue
            mesh = obj.data
            mesh.calc_loop_triangles()
            uv = mesh.uv_layers.active.data
            scale = obj.matrix_world.to_3x3()
            for tri in mesh.loop_triangles:
                a, b, c = (scale @ mesh.vertices[i].co for i in tri.vertices)
                area = (b - a).cross(c - a).length * 0.5
                samples = 0
                for w in ((1 / 3, 1 / 3, 1 / 3), (0.6, 0.2, 0.2), (0.2, 0.6, 0.2), (0.2, 0.2, 0.6)):
                    u = sum(uv[tri.loops[k]].uv.x * w[k] for k in range(3))
                    v = sum(uv[tri.loops[k]].uv.y * w[k] for k in range(3))
                    px = data[min(resolution - 1, max(0, int(v * resolution))), min(resolution - 1, max(0, int(u * resolution)))]
                    samples += 1 if max(px[0], px[1], px[2]) > 0.02 else 0
                lit += area * samples / 4.0
                total += area
        out[root.name] = lit / max(total, 1e-9)
        log('emission share %s %.3f' % (root.name, out[root.name]))
        K.require(out[root.name] <= BUDGET['emission_share_max'], 'emission share %s %.3f' % (root.name, out[root.name]))
    return out


def export(fam, path):
    bpy.ops.object.select_all(action='DESELECT')
    for root in fam.roots:
        root.select_set(True)
        for obj in descendants(root):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = fam.roots[0]
    result = bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                                       export_materials='NONE', export_yup=True, export_apply=False,
                                       export_extras=False, export_animations=False, export_texcoords=True,
                                       export_normals=True, export_tangents=False)
    K.require('FINISHED' in result and path.is_file(), 'GLB export failed: ' + str(path))
    raw = path.read_bytes()
    magic, version, total = struct.unpack_from('<III', raw, 0)
    K.require(magic == 0x46546c67 and version == 2 and total == len(raw), 'Invalid GLB header')
    length, _kind = struct.unpack_from('<II', raw, 12)
    payload = json.loads(raw[20:20 + length])
    meshes = [m['name'] for m in payload.get('meshes', [])]
    K.require(len(meshes) == len(fam.templates), 'glTF mesh sharing lost: %d meshes for %d templates' %
              (len(meshes), len(fam.templates)))
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(), 'meshes': meshes,
            'nodes': len(payload.get('nodes', []))}


def build_family(name, builders, spacing):
    fam = Family(name, spacing)
    for builder in builders:
        builder(fam)
    report = census(fam)
    check_budgets(fam, report)
    if name == 'pickup_props':
        pickup_radius(fam)
    result = {'census': report}
    if not opts.quick:
        K.pack_uvs(fam.templates, TEXEL_WEIGHTS)
        written, images = K.bake_channels(scene, fam.templates, name, BUDGET['atlas_resolution'], OUT, log,
                                          0.35 if name == 'hazard_props' else 0.6)
        result['emission_share'] = emission_share(fam, images['emission'], BUDGET['atlas_resolution'])
        result['atlases'] = {channel: {'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                             for channel, path in written.items()}
    result['glb'] = export(fam, OUT / (name + '.glb'))
    return result


def hazards():
    return build_family('hazard_props', [pr_backlog_low, pr_backlog_high, bug_swarm, merge_conflict,
                                         lambda f: pit_rim(f, 'full', 5.6), lambda f: pit_rim(f, 'two_lane', 3.6),
                                         laser_grid, comment_flood, build_shockwave], 14.0)


def pickups():
    builders = [lambda f, b=b: b(f, 'pk_mint', 'pk_mint_core') for _k, b in POWER_UPS]
    builders += [lambda f, b=b: b(f, 'pk_orange', 'pk_orange_core') for _k, b in TOOLS]
    return build_family('pickup_props', builders, 2.0)


log('revision %d seed %d set=%s quick=%s blender=%s' % (REVISION, SEED, opts.set, opts.quick, bpy.app.version_string))
build = {'generator': 'tools/blender/props/build_props.py', 'revision': REVISION, 'seed': SEED,
         'blender': bpy.app.version_string, 'quick': opts.quick, 'budget': BUDGET,
         'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
         'kit_sha256': hashlib.sha256((HERE / 'props_kit.py').read_bytes()).hexdigest()}
report_path = OUT / 'props.build.json'
previous = json.loads(report_path.read_text()) if report_path.is_file() else {}
if opts.set in ('hazards', 'all'):
    build['hazards'] = hazards()
    # A later family must not see this family's objects in its occlusion bake.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
elif 'hazards' in previous:
    build['hazards'] = previous['hazards']
if opts.set in ('pickups', 'all'):
    RNG.seed(SEED + 1)
    build['pickups'] = pickups()
elif 'pickups' in previous:
    build['pickups'] = previous['pickups']
if not opts.quick:
    report_path.write_text(json.dumps(build, indent=2, sort_keys=True) + '\n')
print('PROPS BUILD: ' + json.dumps({k: v for k, v in build.items() if k in ('revision', 'seed', 'quick')}))
log('done')
