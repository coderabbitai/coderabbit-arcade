"""Flaky Test Swarm: a CI queen and six reversible test-result worker drones.

Original geometry, four source finishes, one baked skin. Godot metres, facing +Z.
The plate glyphs are geometry so face flips never swap a material at runtime.
"""
import argparse
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_kit import BossBuilder, Part, xform

RECIPE_REVISION = 4
TAU = math.tau
CENTRE_Y = 1.02
DRONES = [(2.16, 1.28, .27), (.90, 2.36, -.31),
          (-1.30, 2.25, .33), (-2.16, .81, -.32),
          (-1.35, -.35, .18), (1.30, -.12, -.18)]
DRONE_SCALES = [.95, 1.07, .93, 1.05, .92, 1.10]


def smooth(a, b, t):
    u = min(1.0, max(0.0, (t - a) / (b - a)))
    return u * u * (3 - 2 * u)


def stroke(part, finish, a, b, width, depth=0.025, matrix=None):
    mid = tuple((a[i] + b[i]) / 2 for i in range(3))
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    transform = xform(mid, (0, 0, math.atan2(b[1] - a[1], b[0] - a[0])))
    part.box(finish, (length + width * .45, width, depth),
             transform if matrix is None else matrix @ transform, bevel=width * .16, segments=1)


def lettering(part, text, centre, height, finish):
    # Hand-drawn industrial stroke letters, no external font dependency.
    glyphs = {
        'R': [[(0, 0), (0, 1), (.6, 1), (.7, .7), (.55, .5), (0, .5)], [( .38, .5), (.75, 0)]],
        'E': [[(.7, 1), (0, 1), (0, 0), (.7, 0)], [(0, .5), (.55, .5)]],
        'T': [[(0, 1), (.8, 1)], [(.4, 1), (.4, 0)]],
        'Y': [[(0, 1), (.4, .5), (.8, 1)], [(.4, .5), (.4, 0)]],
        'C': [[(.75, .95), (.1, .95), (0, .8), (0, .2), (.1, .05), (.75, .05)]],
        'I': [[(0, 1), (.7, 1)], [(.35, 1), (.35, 0)], [(0, 0), (.7, 0)]],
    }
    start = centre[0] - (len(text) - .25) * height * .5
    for i, char in enumerate(text):
        for path in glyphs[char]:
            for a, b in zip(path, path[1:]):
                stroke(part, finish,
                       (start + (i + a[0]) * height, centre[1] + (a[1] - .5) * height, centre[2]),
                       (start + (i + b[0]) * height, centre[1] + (b[1] - .5) * height, centre[2]),
                       height * .13, .018)


def build_core(kit):
    kit.bone('core', (0, CENTRE_Y, 0), (0, CENTRE_Y + .5, 0), 'root')
    kit.bone('lens', (0, 1.20, .43), (0, 1.45, .43), 'core')
    body = Part('CI_queen_chassis')
    outline = [(-.64, -.86), (.64, -.86), (1.01, -.35), (.91, .55),
               (.50, .92), (-.50, .92), (-.91, .55), (-1.01, -.35)]
    body.prism('navy', outline, .91, xform((0, CENTRE_Y, -.02)), bevel=.11, segments=3)
    body.tube('green', [(x, y + CENTRE_Y, .445) for x, y in outline + [outline[0]]], .017, sides=6)
    body.box('shell', (1.26, .20, 1.02), xform((0, .28, -.02)), bevel=.06)
    # Queen crown: a pair of swept antennae, repeated by the workers.
    for side in [-1, 1]:
        body.tube('navy', [(side * .43, 1.82, 0), (side * .65, 2.17, -.02),
                          (side * .58, 2.43, -.02)], .045, sides=8)
        body.ellipsoid('green', (.092, .11, .075), xform((side * .58, 2.43, -.02)), u=12, v=6)
        # Forward hooked mandibles frame the label instead of reading as a mouth.
        body.prism('shell', [(side * .68, .69), (side * .94, .47),
                            (side * .88, -.17), (side * .55, -.37),
                            (side * .37, -.22), (side * .63, -.15),
                            (side * .67, .22), (side * .56, .35)], .14,
                   xform((0, 0, .46)), bevel=.027, segments=3)
        stroke(body, 'red', (side * .80, -.16, .54), (side * .56, -.28, .54), .038, .018)
        for j in range(3):
            body.box('green', (.09, .16, .025), xform((side * (.61 + .115 * j), .74, .455)), bevel=.012)
    body.cylinder('shell', .60, .10, xform((0, 1.22, .445), (math.pi / 2, 0, 0)), segments=24, bevel=.025)
    body.cylinder('navy', .515, .035, xform((0, 1.22, .508), (math.pi / 2, 0, 0)), segments=24)
    body.ring('green', .465, .037, xform((0, 1.22, .54), (math.pi / 2, 0, 0)), segments=24, sides=6)
    # A cream label plate and dark engraved-looking strokes read in the close-up.
    body.box('shell', (1.05, .28, .065), xform((0, .47, .477)), bevel=.025)
    lettering(body, 'RETRY', (0, .47, .52), .174, 'navy')
    body.box('navy', (.44, .21, .05), xform((0, 2.21, .49)), bevel=.025)
    lettering(body, 'CI', (0, 2.21, .526), .16, 'green')
    # Hidden behind the paired crown covers until the runtime phase split opens.
    crack = [(-.02, 2.035, .465), (.055, 1.95, .465), (-.045, 1.87, .465), (.025, 1.77, .465)]
    for a, b in zip(crack, crack[1:]): stroke(body, 'red', a, b, .073, .023)
    kit.add_part(body, 'core')
    lens = Part('opening_status_lens')
    lens.ellipsoid('green', (.41, .41, .09), xform((0, 1.22, .51)), u=24, v=12)
    lens.prism('navy', [(-.115, -.25), (.115, -.25), (.115, .25), (-.115, .25)], .027,
               xform((0, 1.22, .606)), bevel=.025, segments=3)
    lens.prism('red', [(-.012, -.22), (.040, -.14), (.035, .18), (0, .24), (-.04, .14), (-.035, -.18)], .021,
               xform((0, 1.22, .628)), bevel=.008)
    kit.add_part(lens, 'lens')
    for side, suffix in [(-1, 'L'), (1, 'R')]:
        bone = 'carapace_' + suffix
        kit.bone(bone, (side * .54, 1.24, 0), (side * .54, 1.7, 0), 'core')
        armor = Part('split_carapace_' + suffix)
        armor.prism('shell', [(side * .13, 1.84), (side * .49, 2.02),
                             (side * .93, 1.66), (side * 1.03, 1.03),
                             (side * .74, .79), (side * .61, 1.59)], .28,
                    xform((0, 0, .27)), bevel=.06, segments=3)
        armor.prism('shell', [(side * .005, 1.49), (side * .61, 1.71),
                             (side * .55, 1.89), (side * .015, 1.66)], .15,
                    xform((0, 0, .59)), bevel=.024, segments=3)
        armor.box('shell', (.245, .38, .11), xform((side * .1225, 1.90, .49)), bevel=.012, segments=3)
        stroke(armor, 'green', (side * .04, 1.655, .68), (side * .54, 1.835, .68), .024, .016)
        stroke(armor, 'navy', (side * .65, 1.44, .422), (side * .76, 1.13, .422), .023, .018)
        # One crisp status stripe on the shoulder, dark inset behind it.
        stroke(armor, 'navy', (side * .64, 1.78, .425), (side * .82, 1.56, .425), .14, .03)
        stroke(armor, 'green', (side * .66, 1.77, .447), (side * .79, 1.60, .447), .04, .025)
        kit.add_part(armor, bone)


def build_drone(kit, index, centre):
    bone = 'drone_%d' % index
    kit.bone(bone, centre, (centre[0], centre[1] + .3, centre[2]), 'root')
    part = Part('two_faced_worker_%d' % index)
    size = DRONE_SCALES[index]
    m = xform(centre, scale=(size,) * 3)
    shell = [(-.34, -.34), (.34, -.34), (.47, -.14), (.40, .27),
             (.22, .39), (-.22, .39), (-.40, .27), (-.47, -.14)]
    part.prism('shell', shell, .40, m, bevel=.055, segments=3)
    for side in [-1, 1]:
        stroke(part, 'navy', (side * .20, .335, .23), (side * .35, .265, .23), .023, .018, m)
    part.cylinder('navy', .095, .38, m @ xform((0, -.495, .107), (2.8, 0, 0)),
                  radius_top=0, segments=10)
    part.cylinder('red', .033, .12, m @ xform((0, -.630, .155), (2.8, 0, 0)),
                  radius_top=0, segments=8)
    part.box('navy', (.87, .10, .44), m @ xform((0, -.18, 0)), bevel=.025)
    for side in [-1, 1]:
        part.tube('navy', [(side * .18, .34, 0), (side * .28, .58, -.025)],
                  .024, matrix=m, sides=6)
        part.cylinder('navy', .05, .10, m @ xform((side * .28, .625, -.025)),
                      radius_top=0, segments=6)
    for front in [1, -1]:
        face = m @ xform((0, 0, front * .23), (0, 0 if front == 1 else math.pi, 0))
        part.box('navy', (.70, .54, .04), face, bevel=.035)
        # Large raised luminous glyph, with a thin matching status strip.
        if front == 1:
            stroke(part, 'green', (-.23, .00, .035), (-.065, -.15, .035), .093, .035, face)
            stroke(part, 'green', (-.065, -.15, .035), (.23, .18, .035), .093, .035, face)
        else:
            stroke(part, 'red', (-.19, -.17, .035), (.19, .17, .035), .097, .035, face)
            stroke(part, 'red', (-.19, .17, .035), (.19, -.17, .035), .097, .035, face)
        part.box('green' if front == 1 else 'red', (.28, .026, .02), face @ xform((0, -.23, .03)), bevel=.005)
        # Two un-bevelled visor wedges cost 24 triangles per face. Replacing
        # antenna bobbles with six-sided spikes pays for this scowling brow.
        for side in [-1, 1]:
            part.prism('navy', [(side * .34, .24), (side * .025, .17),
                                (side * .025, .23), (side * .34, .30)], .038,
                       face @ xform((0, 0, .059)))
    kit.add_part(part, bone)
    for side, label in [(-1, 'L'), (1, 'R')]:
        wing_bone = 'wing_%d_%s' % (index, label)
        pivot = (centre[0] + side * .34 * size, centre[1] + .13 * size, centre[2] - .06 * size)
        kit.bone(wing_bone, pivot, (pivot[0] + side * .3, pivot[1], pivot[2]), bone)
        wing = Part(wing_bone)
        # Rotate around the shoulder: down in the screen plane, swept back in Z.
        swept = (m @ xform((side * .34, .13, -.04),
                           (0, side * math.radians(35), -side * math.radians(25)))
                 @ xform((-side * .34, -.13, 0)))
        wing.prism('shell', [(side * .31, .08), (side * .88, .43),
                             (side * .78, -.11), (side * .66, -.17),
                             (side * .70, .07), (side * .40, -.07)], .065,
                   swept, bevel=.012, segments=2)
        wing.prism('navy', [(side * .45, .11), (side * .77, .33),
                            (side * .71, .07), (side * .47, -.005)], .014,
                   swept @ xform((0, 0, .041)), bevel=.006)
        stroke(wing, 'red', (side * .37, .13, .047), (side * .82, .395, .047), .033, .02, swept)
        kit.add_part(wing, wing_bone)
    kit.socket('fx_%d' % index, bone, (centre[0], centre[1], centre[2] + .29))


def pose(kit, action, t):
    pulse = math.sin(math.pi * t)
    if action == 'intro':
        kit.pose('core', location=(0, -.26 * (1 - smooth(.1, .7, t)), -.45 * (1 - t)),
                 rotation=(0, -.30 * (1 - t), 0))
        opened = .02 + .98 * smooth(.58, .85, t)
        kit.pose('lens', scale=(opened, opened, 1))
    elif action == 'idle':
        kit.pose('core', location=(0, .04 * math.sin(TAU * t), 0), rotation=(0, .06 * math.sin(TAU * t), 0))
    elif action == 'telegraph':
        kit.pose('core', rotation=(0, .05 * math.sin(t * TAU * 3) * pulse, 0))
        kit.pose('lens', scale=(1, 1 - .20 * pulse, 1))
    elif action == 'attack':
        wind = smooth(0, .20, t) * (1 - smooth(.20, .36, t))
        strike = smooth(.22, .36, t) * (1 - smooth(.50, 1, t))
        kit.pose('core', location=(0, .15 * wind - .10 * strike, -.18 * strike), rotation=(.30 * strike, 0, 0))
    elif action == 'hurt':
        kit.pose('core', location=(.12 * math.sin(t * TAU * 2) * pulse, 0, -.20 * pulse), rotation=(.17 * pulse, 0, 0))
    elif action == 'phase_change':
        kit.pose('core', rotation=(0, .10 * math.sin(t * TAU * 2) * pulse, .05 * math.sin(TAU * t)))
        for side, label in [(-1, 'L'), (1, 'R')]:
            kit.pose('carapace_' + label, location=(side * .11 * pulse, 0, 0), rotation=(0, side * .15 * pulse, 0))
    elif action == 'defeat':
        drop = smooth(.05, .55, t)
        kit.pose('core', location=(0, -.34 * drop, -.30 * (1 - drop)), rotation=(-.25 + .41 * drop, 0, -.24 * drop))
        kit.pose('lens', scale=(1, max(.04, .6 * (1 - drop)), 1))
        for side, label in [(-1, 'L'), (1, 'R')]:
            kit.pose('carapace_' + label, location=(side * .16 * drop, -.12 * drop, 0), rotation=(0, 0, -side * .2 * drop))
    elif action == 'retreat':
        kit.pose('root', location=(0, 2.2 * t * t, -4 * t * t), scale=(1 - .7 * t,) * 3)
    for i, (x, y, z) in enumerate(DRONES):
        phase = i * TAU / 6
        location = (0, 0, 0)
        yaw = math.pi if i % 3 == 2 else 0
        roll = 0
        if action == 'intro':
            assembly = 1 - smooth(.02 + i * .035, .63 + i * .025, t)
            # Own-side radial starts avoid crossing through the queen. The
            # envelope clamp below keeps every wing tip inside the corridor.
            location = (x * .50 * assembly, (y - CENTRE_Y) * .50 * assembly, -.80 * assembly)
            yaw = yaw * (1 - assembly) + TAU * assembly
            hold_face = math.pi if i in [0, 2, 3, 5] else 0
            hold_lock = smooth(.80, 1.0, t)
            yaw = yaw * (1 - hold_lock) + hold_face * hold_lock
            roll = -.32 * assembly
        elif action == 'idle':
            a = .10 * math.sin(TAU * t)
            location = (x * (math.cos(a) - 1) - (y - CENTRE_Y) * math.sin(a),
                        x * math.sin(a) + (y - CENTRE_Y) * (math.cos(a) - 1) + .035 * math.sin(TAU * t + phase),
                        .12 * math.sin(TAU * t + phase))
            # Two eased half-turns per loop, with a stable face between flips.
            f = (t + i / 6) % 1
            yaw += math.pi * (smooth(.12, .20, f) + smooth(.64, .72, f))
            roll = .045 * math.sin(TAU * t + phase)
        elif action == 'telegraph':
            lock = smooth(.70, .92, t)
            yaw = (TAU * 3 * smooth(0, .8, t) + math.pi) * (1 - lock) + 7 * math.pi * lock
            location = (-x * .10 * t, -(y - CENTRE_Y) * .10 * t, .035 * pulse)
        elif action == 'attack':
            wind = smooth(0, .20, t) * (1 - smooth(.20, .36, t))
            strike = smooth(.22, .36 + .012 * i, t) * (1 - smooth(.50, 1, t))
            location = (x * .20 * wind - math.copysign(.46 * strike, x),
                        .15 * wind - .32 * strike, .22 * strike)
            yaw = math.pi
            roll = -.18 * math.copysign(strike, x)
        elif action == 'hurt':
            location = (x * .13 * pulse, (y - CENTRE_Y) * .14 * pulse, -.18 * pulse)
            roll = math.copysign(.45 * pulse, x)
        elif action == 'phase_change':
            location = (-x * .15 * pulse, -(y - CENTRE_Y) * .12 * pulse, .08 * pulse)
            yaw += TAU * smooth(.15, .85, t)
        elif action == 'defeat':
            fall = smooth(.05 + i * .008, .55, t)
            a = 1.6 * fall
            heap = [(2.48, .26, .23), (1.49, .34, -.28), (.50, .40, -.50),
                    (-2.48, .26, -.25), (-1.49, .34, .24), (-.50, .40, -.50)]
            # The hit-stop starts in a struck pose; the staggered spiral then
            # settles into six distinct slots before the radial burn consumes it.
            target_x = (x * math.cos(a) - (y - CENTRE_Y) * math.sin(a)) * (1 - fall) + heap[i][0] * fall
            target_y = (CENTRE_Y + x * math.sin(a) + (y - CENTRE_Y) * math.cos(a)) * (1 - fall) + heap[i][1] * fall
            target_x += x * .25 * (1 - fall)
            target_y += (y - CENTRE_Y) * .14 * (1 - fall)
            location = (target_x - x, target_y - y, (heap[i][2] - z) * fall - .12 * (1 - fall))
            yaw = math.pi
            roll = math.copysign(.50 + .70 * fall, x)
        # Keep every posed worker within the shared corridor XY envelope and
        # the coordinator's old-front + 0.4 m limit, including edge-on flips.
        size = DRONE_SCALES[i]
        ex = size * (.90 * abs(math.cos(roll)) + .64 * abs(math.sin(roll)))
        ey = size * (.90 * abs(math.sin(roll)) + .70 * abs(math.cos(roll)))
        # Swept wings project behind the body, so a red-facing half-turn puts
        # their full rear reach in front. Bound both faces, not only the plates.
        ez = size * (.90 * abs(math.sin(yaw)) + .64 * abs(math.cos(yaw)))
        edge = 3.48 if action == 'intro' else 3.26
        location = (min(edge - ex, max(-edge + ex, x + location[0])) - x,
                    min(3.38 - ey, max(-1.10 + ey, y + location[1])) - y,
                    min(location[2], .84 - z - ez))
        kit.pose('drone_%d' % i, location=location, rotation=(0, yaw, roll))
        wing_beat = .14 * math.sin(TAU * (8 * t) + phase) if action not in ['defeat', 'retreat'] else -.30 * t
        for side, label in [(-1, 'L'), (1, 'R')]:
            kit.pose('wing_%d_%s' % (i, label), rotation=(0, side * wing_beat, 0))


def build(out_dir, quick=False):
    kit = BossBuilder('flaky_test_swarm', __file__, revision=RECIPE_REVISION, quick=quick)
    kit.material('shell', 'fff0d3', roughness=.43, metallic=.15, grunge=.12)
    kit.material('navy', '142735', finish='rubber', roughness=.47, metallic=.24)
    kit.material('green', '63f9b2', finish='plain', roughness=.26, metallic=.12,
                 emission='63f9b2', emission_energy=.75, grunge=0)
    kit.material('red', 'ff4d3d', finish='plain', roughness=.30, metallic=.10,
                 emission='ff4d3d', emission_energy=.85, grunge=0)
    kit.bone('root', (0, 0, 0), (0, .3, 0))
    build_core(kit)
    for index, centre in enumerate(DRONES):
        build_drone(kit, index, centre)
    kit.socket('fx_core', 'core', (0, 1.22, .53))
    for i, x in enumerate([-.38, 0, .38]):
        kit.socket('muzzle_%d' % i, 'core', (x, .17, .55))
    kit.bake_actions(dict(intro=2.4, idle=4.0, telegraph=.8, attack=.55,
                          hurt=.4, phase_change=1.2, defeat=2.0, retreat=1.0), pose)
    return kit.export(out_dir)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', type=Path, default=Path('Assets/runner/bosses'))
    parser.add_argument('--quick', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    build(args.out_dir, args.quick)
