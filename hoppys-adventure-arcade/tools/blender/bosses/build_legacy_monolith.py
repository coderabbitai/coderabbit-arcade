"""Legacy Monolith: a load-bearing stack of obsolete server racks, cast as a golem.
Original geometry in Godot metres. Four finish classes bake to one skinned surface.
"""
import argparse
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_kit import BossBuilder, Part, xform, require

RECIPE_REVISION = 2
RACK_Y = (-0.47, 0.34, 1.32, 2.68)
STATUS_Y = (-0.14, 0.68, 2.105, 3.29)
STATUS_Z = (0.86, 0.84, 0.845, 0.78)
DURATIONS = dict(intro=2.4, idle=4.0, telegraph=0.8, attack=0.8, hurt=0.4,
                 phase_change=1.2, defeat=2.4, retreat=1.6)
# Original 5x7 stencil cells, extruded with the plate, no font or downloaded artwork.
GLYPHS = {
    '@': ['01110','10001','10111','10101','10111','10000','01110'],
    'd': ['00001','00001','01101','10011','10001','10011','01101'],
    'e': ['00000','00000','01110','10001','11111','10000','01110'],
    'p': ['00000','00000','11110','10001','10001','11110','10000','10000','10000'],
    'r': ['00000','00000','10110','11001','10000','10000','10000'],
    'c': ['00000','00000','01111','10000','10000','10000','01111'],
    'a': ['00000','00000','01110','00001','01111','10001','01111'],
    't': ['00100','00100','11111','00100','00100','00101','00010'],
    's': ['00000','00000','01111','10000','01110','00001','11110'],
    'i': ['00100','00000','01100','00100','00100','00100','01110'],
    'n': ['00000','00000','11110','10001','10001','10001','10001'],
    ' ': ['000','000','000','000','000','000','000'],
    '2': ['01110','10001','00001','00110','01000','10000','11111'],
    '0': ['01110','10011','10101','10101','11001','10001','01110'],
    '1': ['00100','01100','00100','00100','00100','00100','01110'],
}


def text(part, words, center, cell, finish='dark'):
    glyphs = []
    for char in words:
        rows = GLYPHS[char]
        columns = [i for i in range(len(rows[0])) if any(row[i] == '1' for row in rows)]
        first, last = (min(columns), max(columns)) if columns else (0, 2)
        glyphs.append([row[first:last + 1] for row in rows])
    width = (sum(len(rows[0]) + 1 for rows in glyphs) - 1) * cell
    cursor = center[0] - width / 2
    for rows in glyphs:
        for row, cells in enumerate(rows):
            # Join contiguous pixels per row into one stencil stroke.
            start = None
            for col in range(len(cells) + 1):
                on = col < len(cells) and cells[col] == '1'
                if on and start is None:
                    start = col
                if not on and start is not None:
                    count = col - start
                    part.box(finish, (count * cell * 0.94, cell * 0.89, 0.008),
                             xform((cursor + (start + count / 2) * cell,
                                    center[1] + (3 - row) * cell, center[2])))
                    start = None
        cursor += (len(rows[0]) + 1) * cell


def box(p, finish, at, size, bevel=0.04, rot=(0, 0, 0)):
    p.box(finish, size, xform(at, rot), bevel=bevel, segments=2)


def bolt(p, at, radius=0.045):
    p.cylinder('dark', radius, 0.035, xform(at, (math.pi / 2, 0, 0)), segments=8)


def panel(kit, name, bone, center, width, height, depth):
    p = Part(name)
    box(p, 'slate', center, (width, height, depth), 0.075)
    box(p, 'beige', (center[0], center[1], center[2] + depth / 2 - 0.035),
        (width - 0.17, height - 0.16, 0.13), 0.035)
    for sx in [-1, 1]:
        for sy in [-1, 1]:
            bolt(p, (center[0] + sx * (width / 2 - 0.14), center[1] + sy * (height / 2 - 0.13), center[2] + depth / 2 + 0.055))
    return p


def smooth(a, b, t):
    x = max(0.0, min(1.0, (t - a) / (b - a)))
    return x * x * (3 - 2 * x)


def pose(kit, action, t):
    pulse = math.sin(math.pi * t)
    if action == 'idle':
        kit.pose('tower', location=(0, math.sin(t * math.tau) * 0.038, 0),
                 rotation=(0, math.sin(t * math.tau) * 0.012, 0))
        for side, sign in [('L', -1), ('R', 1)]:
            kit.pose('cables_' + side, rotation=(0, 0, math.sin(t * math.tau + sign) * 0.035))
            kit.pose('fan_' + side, rotation=(0, 0, sign * t * math.tau * 2))
    elif action == 'intro':
        rise = smooth(0, 0.45, t)
        kit.pose('root', location=(0, -1.6 * (1 - rise), -1.8 * (1 - rise)))
        stance = smooth(0.80, 1.0, t)
        kit.pose('tower', rotation=(0.08 * stance, 0, 0))
        for side, sign in [('L', -1), ('R', 1)]:
            kit.pose('arm_' + side, location=(0, 0.11 * stance, 0),
                     rotation=(-0.22 * stance, 0, sign * 0.21 * stance))
            kit.pose('hand_' + side, rotation=(-0.12 * stance, 0, 0))
        for i in range(4):
            u = smooth(0.18 + i * 0.12, 0.29 + i * 0.12, t)
            kit.pose('rack_%d' % i, location=(0, -0.12 * math.sin(math.pi * u), 0),
                     rotation=(0, (1 - u) * (0.06 if i % 2 else -0.06), 0))
            kit.pose('led_%d' % i, scale=(max(u, 0.001),) * 3)
        for side in ['L', 'R']:
            light = max(smooth(0.64, 0.82, t), 0.001)
            kit.pose('eye_' + side, scale=(light, light, 1))
    elif action == 'telegraph':
        lift = smooth(0, 0.85, t)
        kit.pose('tower', location=(0, 0.18 * lift, 0), rotation=(-0.025 * lift, 0, 0))
        for side, sign in [('L', -1), ('R', 1)]:
            kit.pose('arm_' + side, location=(0, 0.16 * lift, 0), rotation=(-0.32 * lift, 0, sign * 0.30 * lift))
            kit.pose('hand_' + side, rotation=(-0.18 * lift, 0, 0))
        kit.pose('reactor', scale=(1 + 0.09 * lift,) * 3)
    elif action == 'attack':
        lift = 1 - smooth(0.06, 0.28, t)
        # 0.30..0.42 holds impact for 66 ms at the runtime's 0.55 s quake duration.
        impact = smooth(0.14, 0.30, t) * (1 - smooth(0.42, 1.0, t))
        kit.pose('tower', location=(0, 0.18 * lift - 0.20 * impact, 0), rotation=(0.10 * impact, 0, 0))
        for side, sign in [('L', -1), ('R', 1)]:
            # Tower dip plus arm drop puts the fists at least 0.45 m below rest.
            kit.pose('arm_' + side, location=(0, 0.16 * lift - 0.25 * impact, 0.30 * impact),
                     rotation=(-0.32 * lift + 0.10 * impact, 0, sign * (0.30 * lift - 0.08 * impact)))
            kit.pose('hand_' + side, rotation=(-0.18 * lift, 0, 0))
    elif action == 'hurt':
        kick = smooth(0, 0.25, t) * (1 - smooth(0.5, 1, t))
        kit.pose('rack_1', location=(kick * 0.35, 0, 0), rotation=(0, kick * 0.08, 0))
        kit.pose('rack_3', rotation=(-pulse * 0.035, 0, -pulse * 0.04))
    elif action == 'phase_change':
        for side, sign in [('L', -1), ('R', 1)]:
            kit.pose('shell_' + side, location=(sign * 0.20 * pulse, 0, 0.08 * pulse), rotation=(0, sign * 0.12 * pulse, 0))
        for i in range(3):
            kit.pose('debris_%d' % i, location=((i - 1) * pulse * 0.12, pulse * 0.18, pulse * 0.06),
                     rotation=(pulse * 0.12, 0, (i - 1) * pulse * 0.10))
    elif action == 'defeat':
        # Four independently rigged modules topple from top to bottom, never one scaled cube.
        for i in range(4):
            fall = smooth((3 - i) * 0.13, 0.62 + (3 - i) * 0.11, t)
            kit.pose('rack_%d' % i, location=((1 if i % 2 else -1) * fall * (0.5 if i == 2 else 0.26),
                     -fall * (1.2 if i == 3 else 0.10 + i * 0.08), fall * 0.10),
                     rotation=(fall * (0.9 if i == 3 else 0.12 + 0.10 * i),
                     (i - 1.5) * fall * 0.045, (1 if i % 2 else -1) * fall * 0.15))
            kit.pose('led_%d' % i, scale=(max(1 - smooth(0.12 + (3 - i) * 0.1, 0.42 + (3 - i) * 0.1, t), 0.001),) * 3)
        for side, sign in [('L', -1), ('R', 1)]:
            kit.pose('arm_' + side, rotation=(0.15 * t, 0, sign * -0.18 * t))
            kit.pose('eye_' + side, scale=(max(1 - smooth(0.20, 0.36, t), 0.001),
                                          max(1 - smooth(0.03, 0.20, t), 0.001), 1))
            kit.pose('shell_' + side, location=(sign * t * 0.30, -t * 0.15, t * 0.08), rotation=(0, sign * t * 0.3, 0))
        for i in range(3):
            kit.pose('debris_%d' % i, location=((i - 1) * t * 0.32, -t * 0.7, t * 0.25), rotation=(t * 0.5, 0, (i - 1) * t * 0.45))
    elif action == 'retreat':
        kit.pose('root', location=(0, -smooth(0.15, 1, t) * 0.65, -smooth(0.35, 1, t) * 2.5))
        for i in range(4):
            lit = max(1 - smooth((3 - i) * 0.1, 0.35 + (3 - i) * 0.1, t), 0.001)
            kit.pose('led_%d' % i, scale=(lit,) * 3)
        for side in ['L', 'R']:
            kit.pose('eye_' + side, scale=(max(1 - smooth(0, 0.35, t), 0.001), 0.04, 1))


def build(out_dir, quick=False):
    kit = BossBuilder('legacy_monolith', __file__, revision=RECIPE_REVISION, quick=quick)
    kit.material('beige', 'c5b79c', finish='shell', roughness=0.48, metallic=0.45,
                 period=0.9, grunge=0.08, wear=0.30, bump=0.22)
    kit.material('slate', '6a7ba2', roughness=0.38, metallic=0.60, period=0.8, grunge=0.08, wear=0.20)
    kit.material('dark', '182632', finish='rubber', roughness=0.68, metallic=0.12, grunge=0.12, tread=32)
    kit.material('glow', 'f78949', finish='plain', roughness=0.3, metallic=0.08,
                 emission='f78949', emission_energy=0.9, grunge=0.0, bump=0.0)
    kit.bone('root', (0, 0, 0), (0, 0.15, 0))
    kit.bone('tower', (0, 0, 0), (0, 1, 0), 'root')
    for i, y in enumerate(RACK_Y):
        kit.bone('rack_%d' % i, (0, y - 0.3, 0), (0, y + 0.3, 0), 'tower')
        kit.bone('led_%d' % i, (0, STATUS_Y[i], STATUS_Z[i]),
                 (0, STATUS_Y[i] + 0.1, STATUS_Z[i]), 'rack_%d' % i)
    for side, sign in [('L', -1), ('R', 1)]:
        kit.bone('arm_' + side, (sign * 1.58, 1.7, 0), (sign * 2.28, 0.80, 0.1), 'tower')
        kit.bone('hand_' + side, (sign * 2.40, 0.7, 0.1), (sign * 2.40, 0.1, 0.1), 'arm_' + side)
        kit.bone('shell_' + side, (sign * 0.75, 1.3, 0.60), (sign * 0.75, 1.8, 0.60), 'rack_2')
        kit.bone('eye_' + side, (sign * 0.63, 2.76, 0.82), (sign * 0.63, 2.90, 0.82), 'rack_3')
        kit.bone('fan_' + side, (sign * 1.02, 0.33, 0.80), (sign * 1.02, 0.33, 0.93), 'rack_1')
        kit.bone('cables_' + side, (sign * 1.12, 3.02, -0.30), (sign * 1.50, 1.7, -0.45), 'rack_3')
    kit.bone('reactor', (0, 1.34, 0.78), (0, 1.55, 0.78), 'rack_2')
    for i in range(3):
        kit.bone('wall_%d' % i, ((i - 1) * 1.05, -0.45, 0.70), ((i - 1) * 1.05, -0.2, 0.70), 'rack_0')
        kit.bone('debris_%d' % i, ((i - 1) * 1.40, 2.02 + (0.35 if i == 1 else 0), -0.35),
                 ((i - 1) * 1.40, 2.2 + (0.35 if i == 1 else 0), -0.35), 'tower')

    base = Part('LoadBearingBase')
    box(base, 'dark', (0, -0.50, -0.05), (3.22, 0.74, 1.60), 0.10)
    box(base, 'slate', (0, -0.82, -0.06), (3.48, 0.16, 1.64), 0.04)
    kit.add_part(base, 'rack_0')
    for i in range(3):
        p = panel(kit, 'WallShutter%d' % i, 'wall_%d' % i, ((i - 1) * 1.05, -0.44, 0.71), 0.96, 0.59, 0.22)
        for j in range(4):
            box(p, 'dark', ((i - 1) * 1.05, -0.61 + j * 0.11, 0.84), (0.57, 0.035, 0.015), 0)
        kit.add_part(p, 'wall_%d' % i)

    utility = panel(kit, 'PunchCardModule', 'rack_1', (0, 0.34, 0), 3.20, 0.80, 1.54)
    for y in [0.02, 0.30, 0.59]:
        box(utility, 'dark', (0, y, 0.829), (3.02, 0.018, 0.015), 0)
    box(utility, 'dark', (0, 0.32, 0.81), (1.14, 0.50, 0.08), 0.035)
    box(utility, 'beige', (0, 0.32, 0.875), (0.98, 0.34, 0.025), 0.015)
    for row in range(3):
        for col in range(8):
            if (col * 3 + row * 7) % 5 != 1:
                box(utility, 'dark', (-0.4 + col * 0.112, 0.215 + row * 0.104, 0.893), (0.044, 0.056, 0.012), 0)
    kit.add_part(utility, 'rack_1')
    for side, sign in [('L', -1), ('R', 1)]:
        fan = Part('CoolingFan' + side)
        fan.ring('slate', 0.225, 0.035, xform((sign * 1.02, 0.33, 0.81), (math.pi / 2, 0, 0)), segments=20, sides=6)
        fan.cylinder('dark', 0.19, 0.055, xform((sign * 1.02, 0.33, 0.81), (math.pi / 2, 0, 0)), segments=20)
        for i in range(5):
            a = i * math.tau / 5
            box(fan, 'beige', (sign * 1.02 + math.sin(a) * 0.095, 0.33 + math.cos(a) * 0.095, 0.85),
                (0.075, 0.19, 0.03), 0.015, (0, 0, -a + 0.4))
        bolt(fan, (sign * 1.02, 0.33, 0.885), 0.06)
        kit.add_part(fan, 'fan_' + side)

    chassis = Part('ReactorChassis')
    box(chassis, 'dark', (0, 1.41, -0.05), (3.24, 1.27, 1.50), 0.09)
    for sign in [-1, 1]:
        box(chassis, 'slate', (sign * 1.50, 1.41, 0.64), (0.21, 1.12, 0.27), 0.04)
        box(chassis, 'beige', (sign * 1.54, 1.78, 0.01), (0.30, 0.46, 1.52), 0.06)
    box(chassis, 'slate', (0, 2.07, -0.05), (2.58, 0.27, 1.36), 0.055)
    # Old machine identity is physically stencilled into its own nameplate.
    box(chassis, 'beige', (0, 1.94, 0.79), (3.30, 0.36, 0.07), 0.035)
    text(chassis, '@deprecated since 2011', (0, 1.94, 0.834), 0.025)
    kit.add_part(chassis, 'rack_2')
    for side, sign in [('L', -1), ('R', 1)]:
        p = Part('CrackedChest' + side)
        outline = [(0.18, 0.0), (0.37, 0.22), (0.14, 0.39), (0.34, 0.56), (0.16, 0.79),
                   (1.27, 0.79), (1.27, 0.0)]
        outline = [(sign * x, y + 0.89) for x, y in outline]
        p.prism('beige', outline, 0.22, xform((0, 0, 0.83)), bevel=0.025, segments=2)
        for y in [1.02, 1.53]:
            bolt(p, (sign * 1.12, y, 0.96))
        for y in [1.02, 1.29, 1.56]:
            box(p, 'dark', (sign * 1.08, y, 0.958), (0.33, 0.04, 0.012), 0)
            for j in range(2):
                box(p, 'glow', (sign * (0.80 + j * 0.055), y, 0.960), (0.025, 0.025, 0.014), 0)
        # Three distinct fractures, two descending, avoid a mirrored second face.
        fractures = ([(-0.32, 1.48), (-0.52, 1.28), (-0.69, 1.36), (-0.78, 1.06), (-1.05, 0.97)],) if sign < 0 else (
            [(0.30, 1.28), (0.54, 1.20), (0.59, 1.04), (0.91, 0.95)],
            [(0.36, 1.52), (0.60, 1.60), (0.77, 1.53), (1.06, 1.62)])
        for points in fractures:
            p.tube('glow', [(x, y, 0.974) for x, y in points], 0.03, sides=5, radius_end=0.01)
        kit.add_part(p, 'shell_' + side)
    reactor = Part('OrangeReactor')
    reactor.cylinder('glow', 0.40, 0.19, xform((0, 1.30, 0.82), (math.pi / 2, 0, 0)), segments=24)
    reactor.ring('slate', 0.47, 0.075, xform((0, 1.30, 0.87), (math.pi / 2, 0, 0)), segments=24, sides=6)
    for sign in [-1, 1]:
        box(reactor, 'dark', (sign * 0.115, 1.30, 0.94), (0.05, 0.58, 0.03), 0.01)
    kit.add_part(reactor, 'reactor')

    head = panel(kit, 'CRTHead', 'rack_3', (0, 2.68, -0.06), 2.90, 1.22, 1.53)
    box(head, 'slate', (0, 3.25, -0.06), (3.04, 0.20, 1.60), 0.06)
    for side, sign in [('L', -1), ('R', 1)]:
        box(head, 'dark', (sign * 0.64, 2.79, 0.775), (1.01, 0.62, 0.12), 0.09)
        # Heavy slanted brow rims turn two obsolete CRT terminals into a stern golem face.
        box(head, 'beige', (sign * 0.63, 3.08, 0.85), (1.07, 0.17, 0.24), 0.04, (0, 0, sign * 0.24))
        eyes = Part('CRTPhosphor' + side)
        box(eyes, 'glow', (sign * 0.64, 2.78, 0.851), (0.70, 0.27, 0.035), 0.055)
        for j in range(3):
            box(eyes, 'dark', (sign * 0.64, 2.69 + j * 0.08, 0.874), (0.65, 0.014, 0.008), 0)
        kit.add_part(eyes, 'eye_' + side)
    box(head, 'dark', (0, 2.35, 0.78), (1.32, 0.22, 0.10), 0.03)
    for i in range(7):
        box(head, 'beige', (-0.54 + i * 0.18, 2.35, 0.845), (0.06, 0.15, 0.03), 0.01)
    kit.add_part(head, 'rack_3')

    for side, sign in [('L', -1), ('R', 1)]:
        shoulder = Part('CastShoulder' + side)
        box(shoulder, 'slate', (sign * 1.98, 1.62, -0.01), (0.95, 0.74, 1.42), 0.14, (0, 0, sign * 0.10))
        box(shoulder, 'beige', (sign * 2.07, 1.66, 0.58), (0.78, 0.57, 0.28), 0.07)
        shoulder.cylinder('dark', 0.27, 0.66, xform((sign * 2.11, 1.10, 0.0), (0, 0, math.pi / 2)), segments=16)
        kit.add_part(shoulder, 'arm_' + side)
        hand = Part('SlabFist' + side)
        box(hand, 'beige', (sign * 2.46, 0.48, 0.04), (1.12, 1.30, 1.45), 0.13, (0, 0, -sign * 0.05))
        box(hand, 'slate', (sign * 2.48, -0.12, 0.12), (1.16, 0.26, 1.50), 0.065)
        for i in range(3):
            box(hand, 'slate', (sign * 2.46, 0.12 + i * 0.33, 0.80), (0.87, 0.08, 0.17), 0.025)
        for x in [-0.36, 0.36]:
            bolt(hand, (sign * 2.46 + x, 0.94, 0.79), 0.055)
        kit.add_part(hand, 'hand_' + side)
        cables = Part('CableDreadlocks' + side)
        for i in range(4):
            x = sign * (0.86 + i * 0.18)
            cables.tube('dark' if i % 2 else 'slate',
                        [(x, 3.17, -0.30), (x + sign * 0.23, 3.32 + 0.04 * i, -0.44),
                         (x + sign * 0.44, 2.73, -0.72), (x + sign * 0.42, 2.01, -0.77),
                         (x + sign * 0.28, 1.22 + i * 0.12, -0.65)], 0.065, sides=7)
        kit.add_part(cables, 'cables_' + side)
    for i in range(4):
        led = Part('RackStatus%d' % i)
        box(led, 'glow', (0, STATUS_Y[i], STATUS_Z[i]), (2.4, 0.05, 0.02), 0.008)
        for j in range(3):
            box(led, 'glow', (1.21, RACK_Y[i] - 0.16 + j * 0.12, 0.80), (0.065, 0.042, 0.035), 0.008)
        kit.add_part(led, 'led_%d' % i)
    for i in range(3):
        debris = Part('LooseSlab%d' % i)
        x, y = (i - 1) * 1.40, 2.02 + (0.35 if i == 1 else 0)
        box(debris, 'slate', (x, y, -0.45), (0.82, 0.32, 0.86), 0.045, (0.12, (i - 1) * 0.12, (i - 1) * -0.08))
        kit.add_part(debris, 'debris_%d' % i)

    kit.socket('fx_core', 'reactor', (0, 1.30, 1.0))
    for i in range(6):
        kit.socket('fx_%d' % i, 'rack_%d' % min(i // 2, 3), ((-1 if i % 2 else 1) * 1.05, RACK_Y[min(i // 2, 3)], 0.85))
    kit.socket('muzzle_0', 'reactor', (0, 1.3, 1.05))
    kit.socket('muzzle_1', 'hand_L', (-2.46, 0.22, 0.92))
    kit.socket('muzzle_2', 'hand_R', (2.46, 0.22, 0.92))
    triangles = sum(part.data.polygons.__len__() for part in kit.objects)
    print('[legacy-monolith] parts=%d polygons=%d bones=%d' % (len(kit.objects), triangles, len(kit.rig.data.bones)), flush=True)
    kit.bake_actions(DURATIONS, pose)
    return kit.export(out_dir)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', type=Path, default=Path('Assets/runner/bosses'))
    parser.add_argument('--quick', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    build(args.out_dir, args.quick)
