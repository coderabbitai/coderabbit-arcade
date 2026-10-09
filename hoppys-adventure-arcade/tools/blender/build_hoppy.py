"""Deterministic original Hoppy asset. Run with Blender --background --python.
Coordinates in modelling helpers are Godot coordinates; converted to Blender Z-up.
No downloaded assets, fonts, boolean operations, or runtime procedural textures.
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
import mathutils
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glb_atlas import consolidate_atlases, inspect_images

SEED = 41027
# Recipe 10: the Heroes vs. Villains armored Hoppy as an action figure (beat 'em up Mode 2 hero:
# Assets/heroes-vs-villains-assets-only/frames/hoppy and Assets/beatemup-story/heroes/send_in_the_rabbit.png):
# a small rabbit head with a muzzle, long ears, a tall V-shaped torso and long limbs. Joint 17
# re-places every bone for those proportions; the cape chain arrived in joint 16. Recipe 11 makes
# him read badass rather than cute (fierce glowing eyes, smirk, cyber eyepiece, neon circuit trim)
# and gives the run an athletic lean, counter-twist and arm pump.
RECIPE_REVISION = 11
JOINT_REVISION = 17
CONTACT_REVISION = 17
BUDGET = json.loads(Path(__file__).with_name("hoppy_budget.json").read_text())
EFFECT_TRIANGLES = int(BUDGET["effect_triangles"])
TRIANGLE_CAP = int(BUDGET["triangle_cap"])
assert EFFECT_TRIANGLES > 0 and TRIANGLE_CAP <= 48000
ACTION_SAMPLE_RATE = 4  # 120 Hz export, unchanged durations in seconds.
ORANGE_LINEAR = (0.930, 0.250, 0.067)  # Fur, gloves, boots, badge and cape lining.
SOLE_RADII = (.083, .138)  # Boot foot radii (.075, .130) plus 8 mm.
ROUGHNESS = {'fur': .84, 'cloth': .84, 'suit': .78, 'satin': .45, 'leather': .5}
random.seed(SEED)
args = argparse.ArgumentParser()
args.add_argument('--out', required=True)
args.add_argument('--quick', action='store_true', help='Skip UV packing and baking; export flat PBR colours')
opts = args.parse_args(sys.argv[sys.argv.index('--') + 1:])
out = Path(opts.out).resolve()
out.parent.mkdir(parents=True, exist_ok=True)
def stage(message):
    print('[hoppy] stage: ' + message, flush=True)


def require(condition, message):
    if not condition:
        raise RuntimeError('[hoppy] ' + message)


def object_named(name, kind=None):
    obj = bpy.data.objects.get(name)
    require(obj is not None, 'Missing object: ' + name)
    require(kind is None or obj.type == kind, 'Unexpected object type: ' + name)
    return obj


def active_name():
    require(bpy.context.object is not None, 'Operator produced no active object')
    return bpy.context.object.name


stage('reset scene; mode=' + ('quick' if opts.quick else 'baked'))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.cycles.seed = SEED
scene.render.fps = 30
parts = []
recipes = {}
texture_files = []
stage("create procedural materials")

def xyz(v):
    return Vector((v[0], -v[2], v[1]))

def node_math(n, l, op, a, b=None):
    node = n.new('ShaderNodeMath'); node.operation = op
    for index, value in enumerate((a, b)):
        if value is None: continue
        if isinstance(value, (int, float)): node.inputs[index].default_value = value
        else: l.new(value, node.inputs[index])
    return node.outputs[0]


def node_band(n, l, value, low, high):
    """Smoothstep of value over [low, high], clamped to 0..1."""
    node = n.new('ShaderNodeMapRange'); node.interpolation_type = 'SMOOTHSTEP'; node.clamp = True
    node.inputs['From Min'].default_value = low; node.inputs['From Max'].default_value = high
    l.new(value, node.inputs['Value'])
    return node.outputs['Result']


def surface_detail(kind, n, l, tex, ramp, stitch_rgb):
    """(height, bump strength, bump distance, AO socket or None, albedo socket or None).
    Object coordinates are Blender metres (X right, Y = -Godot Z, Z up) because every
    atlas object is joined and transform-applied at the origin before baking."""
    if kind not in ('fur', 'cloth', 'suit', 'thread', 'tread'):
        return None
    split = n.new('ShaderNodeSeparateXYZ'); l.new(tex.outputs['Object'], split.inputs[0])
    X, Y, Z = split.outputs['X'], split.outputs['Y'], split.outputs['Z']
    ax = node_math(n, l, 'ABSOLUTE', X)
    if kind == 'fur':
        # Fur-direction strands: long vertical streaks, ~4 mm wide and ~4 cm long.
        stretch = n.new('ShaderNodeVectorMath'); stretch.operation = 'MULTIPLY'
        stretch.inputs[1].default_value = (230, 230, 24)
        l.new(tex.outputs['Object'], stretch.inputs[0])
        strands = n.new('ShaderNodeTexNoise'); strands.inputs['Scale'].default_value = 1
        strands.inputs['Detail'].default_value = 1
        l.new(stretch.outputs['Vector'], strands.inputs['Vector'])
        return strands.outputs['Fac'], .45, .0012, None, None
    if kind == 'thread':
        # Satin-stitch embroidery: diagonal raised thread bands, ~3 mm apart.
        satin = node_math(n, l, 'FRACT', node_math(n, l, 'MULTIPLY', node_math(n, l, 'ADD', X, Z), 330.))
        ridge = node_math(n, l, 'SINE', node_math(n, l, 'MULTIPLY', satin, math.pi))
        return ridge, .6, .0008, None, None
    if kind == 'tread':
        # Chevron sole tread centred on each boot (|x| = .11), 11 mm pitch.
        offset = node_math(n, l, 'ABSOLUTE', node_math(n, l, 'SUBTRACT', ax, .11))
        chevron = node_math(n, l, 'ADD', Y, node_math(n, l, 'MULTIPLY', offset, .9))
        pitch = node_math(n, l, 'FRACT', node_math(n, l, 'MULTIPLY', chevron, 90.))
        lug = node_band(n, l, pitch, .38, .5)
        groove = node_math(n, l, 'SUBTRACT', 1., lug)
        ao = node_math(n, l, 'SUBTRACT', 1., node_math(n, l, 'MULTIPLY', groove, .35))
        return lug, .9, .0018, ao, None
    # Suit: side/shoulder seam (Godot z=.012), centre-back seam, raglan seams.
    side = node_math(n, l, 'ABSOLUTE', node_math(n, l, 'ADD', Y, .012))
    front = node_math(n, l, 'GREATER_THAN', Y, -.04)
    back = node_math(n, l, 'ADD', ax, node_math(n, l, 'MULTIPLY', front, 10.))
    raglan_x = node_math(n, l, 'ADD', node_math(n, l, 'MULTIPLY', node_math(n, l, 'SUBTRACT', 1.19, Z), .55), .08)
    raglan = node_math(n, l, 'ABSOLUTE', node_math(n, l, 'SUBTRACT', ax, raglan_x))
    outside = node_math(n, l, 'ADD', node_math(n, l, 'LESS_THAN', Z, 1.05), node_math(n, l, 'GREATER_THAN', Z, 1.195))
    raglan = node_math(n, l, 'ADD', raglan, node_math(n, l, 'MULTIPLY', outside, 10.))
    seam = node_math(n, l, 'MINIMUM', node_math(n, l, 'MINIMUM', side, back), raglan)
    groove = node_math(n, l, 'SUBTRACT', 1., node_band(n, l, seam, .0008, .0028))
    row = node_math(n, l, 'SUBTRACT', 1., node_band(n, l, node_math(n, l, 'ABSOLUTE', node_math(n, l, 'SUBTRACT', seam, .0055)), .0006, .0015))
    along = node_math(n, l, 'ADD', Z, node_math(n, l, 'MULTIPLY', ax, .7))
    dash = node_math(n, l, 'GREATER_THAN', node_math(n, l, 'FRACT', node_math(n, l, 'MULTIPLY', along, 150.)), .42)
    stitch = node_math(n, l, 'MULTIPLY', row, dash)
    height = node_math(n, l, 'ADD', node_math(n, l, 'MULTIPLY', groove, -.9), node_math(n, l, 'MULTIPLY', stitch, .7))
    ao = node_math(n, l, 'SUBTRACT', 1., node_math(n, l, 'MULTIPLY', groove, .42))
    thread = n.new('ShaderNodeMixRGB'); thread.blend_type = 'MIX'
    thread.inputs[2].default_value = tuple(stitch_rgb) + (1,)  # Warm topstitch on the graphite suit.
    l.new(node_math(n, l, 'MULTIPLY', stitch, .5), thread.inputs[0]); l.new(ramp.outputs[0], thread.inputs[1])
    if kind == 'suit':
        # Sculpted muscle-suit panel lines on the chest front (Godot y = Z, front = +Y here):
        # the lower pec arcs, the sternum, the linea alba, three ab rows and the ab borders.
        def outside(value, low, high):
            return node_math(n, l, 'MULTIPLY', node_math(n, l, 'ADD', node_math(n, l, 'LESS_THAN', value, low),
                                                         node_math(n, l, 'GREATER_THAN', value, high)), 10.)
        def masked(distance, *penalties):
            for penalty in penalties:
                distance = node_math(n, l, 'ADD', distance, penalty)
            return distance
        back_side = node_math(n, l, 'MULTIPLY', node_math(n, l, 'LESS_THAN', Y, .05), 10.)
        pec_arc = node_math(n, l, 'SUBTRACT', 1.035, node_math(n, l, 'MULTIPLY', node_math(n, l, 'POWER',
                            node_math(n, l, 'SUBTRACT', ax, .085), 2.), 1.4))
        lines = [masked(node_math(n, l, 'ABSOLUTE', node_math(n, l, 'SUBTRACT', Z, pec_arc)), outside(ax, .02, .16)),
                 masked(ax, outside(Z, .9, 1.03)),
                 masked(node_math(n, l, 'ABSOLUTE', node_math(n, l, 'SUBTRACT', ax, .075)), outside(Z, .905, 1.025))]
        for row in (.94, .975, 1.01):
            lines.append(masked(node_math(n, l, 'ABSOLUTE', node_math(n, l, 'SUBTRACT', Z, row)), outside(ax, 0., .07)))
        muscle = lines[0]
        for line in lines[1:]:
            muscle = node_math(n, l, 'MINIMUM', muscle, line)
        muscle = node_math(n, l, 'ADD', muscle, back_side)
        panel = node_math(n, l, 'SUBTRACT', 1., node_band(n, l, muscle, .001, .0045))
        height = node_math(n, l, 'ADD', height, node_math(n, l, 'MULTIPLY', panel, -1.1))
        ao = node_math(n, l, 'MULTIPLY', ao, node_math(n, l, 'SUBTRACT', 1., node_math(n, l, 'MULTIPLY', panel, .5)))
    return height, .7, .0007, ao, thread.outputs[0]


def material(name, color, kind='cloth', metallic=0.0, glow=0.0, stitch=(1.0, .56, .30)):
    m = bpy.data.materials.new(name)
    n, l = m.node_tree.nodes, m.node_tree.links
    p = n.get('Principled BSDF')
    require(p is not None, 'Default Principled BSDF missing: ' + name)
    if opts.quick:
        p.inputs['Base Color'].default_value = tuple(color) + (1,)
        p.inputs['Metallic'].default_value = metallic
        p.inputs['Roughness'].default_value = ROUGHNESS.get(kind, .32)
        p.inputs['Emission Color'].default_value = tuple(color) + (1,)
        p.inputs['Emission Strength'].default_value = glow
        return m
    tex = n.new('ShaderNodeTexCoord')
    mapping = n.new('ShaderNodeVectorMath'); mapping.operation = 'MULTIPLY'
    mapping.inputs[1].default_value = (95, 95, 12) if kind == 'fur' else (100, 100, 100)
    l.new(tex.outputs['Generated'], mapping.inputs[0])
    noise = n.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 3
    noise.inputs['Detail'].default_value = 2
    l.new(mapping.outputs['Vector'], noise.inputs['Vector'])
    wave = n.new('ShaderNodeTexWave'); wave.wave_type = 'BANDS'; wave.bands_direction = 'DIAGONAL'
    wave.inputs['Scale'].default_value = 85; wave.inputs['Distortion'].default_value = 1.8
    l.new(tex.outputs['Generated'], wave.inputs['Vector'])
    mix = n.new('ShaderNodeMixRGB'); mix.blend_type = 'MULTIPLY'; mix.inputs[0].default_value = 0.3
    l.new(noise.outputs['Fac'], mix.inputs[1]); l.new(wave.outputs['Color'], mix.inputs[2])
    ramp = n.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = tuple(c * .83 for c in color) + (1,)
    ramp.color_ramp.elements[1].color = tuple(color) + (1,)
    l.new(mix.outputs[0], ramp.inputs[0]); l.new(ramp.outputs[0], p.inputs['Base Color'])
    bump = n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = .2
    bump.inputs['Distance'].default_value = .0015 if kind == 'fur' else .0006
    folds = n.new('ShaderNodeTexWave'); folds.wave_type = 'BANDS'; folds.bands_direction = 'Z'
    folds.inputs['Scale'].default_value = 7; folds.inputs['Distortion'].default_value = 3
    l.new(tex.outputs['Generated'], folds.inputs['Vector'])
    height = n.new('ShaderNodeMixRGB'); height.blend_type = 'ADD'
    height.inputs[0].default_value = {'cloth': .22, 'suit': .06}.get(kind, 0)
    l.new(mix.outputs[0], height.inputs[1]); l.new(folds.outputs['Color'], height.inputs[2])
    # A geometry attribute puts a faint baked crease at elbow/knee rings only.
    joint = n.new('ShaderNodeAttribute'); joint.attribute_name = 'joint_crease'
    crease_height = n.new('ShaderNodeMath'); crease_height.operation = 'ADD'
    l.new(height.outputs[0], crease_height.inputs[0]); l.new(joint.outputs['Fac'], crease_height.inputs[1])
    l.new(crease_height.outputs[0], bump.inputs['Height'])
    p.inputs['Roughness'].default_value = ROUGHNESS.get(kind, .32)
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Emission Color'].default_value = tuple(color) + (1,)
    p.inputs['Emission Strength'].default_value = glow
    # Round-7 detail: a second bump layer in real object-space millimetres, plus an
    # optional baked-occlusion term for grooves (ORM red; the rest of the atlas stays 1).
    detail = surface_detail(kind, n, l, tex, ramp, stitch)
    base_name, normal_out, ao_name = ramp.name, bump.outputs[0], None
    if detail is not None:
        height, strength, distance, ao, albedo = detail
        fine = n.new('ShaderNodeBump'); fine.inputs['Strength'].default_value = strength
        fine.inputs['Distance'].default_value = distance
        l.new(height, fine.inputs['Height']); l.new(bump.outputs[0], fine.inputs['Normal'])
        normal_out = fine.outputs[0]
        if albedo is not None:
            l.new(albedo, p.inputs['Base Color']); base_name = albedo.node.name
        if ao is not None:
            ao_name = ao.node.name
    l.new(normal_out, p.inputs['Normal'])
    recipes[m.name] = (base_name, p.inputs['Roughness'].default_value, metallic,
                       tuple(c * glow for c in color) + (1,), ao_name)
    return m

cream = material('Cream muzzle fur', (.88, .79, .61), 'fur')
fur = material('CodeRabbit orange fur', ORANGE_LINEAR, 'fur')
# Deep enough pink that the palette mask never counts the inner ears as cream fur.
inner = material('Pink inner ear', (.80, .30, .28), 'fur')
suit = material('Graphite tactical suit', (.032, .036, .046), 'suit', stitch=(.36, .12, .035))
cape_shell = material('Graphite cape satin', (.026, .03, .04), 'satin')
lining = material('Orange cape lining', ORANGE_LINEAR, 'satin')
glove = material('Orange hero leather', ORANGE_LINEAR, 'leather')
leather = material('Utility belt leather', (.20, .09, .035), 'leather')
gold = material('Gold buckle metal', (.85, .52, .14), 'metal', .85)
amber = material('Amber power LEDs', (.98, .42, .05), 'screen', .05, 1.0)
armour = material('Graphite armour plate', (.05, .056, .068), 'metal', .55)
white = material('Warm eye whites', (.98, .94, .83), 'eye')
black = material('Ink pupils', (.003, .007, .012), 'eye')
# Cybernetic irises glow amber; the neon trim is cyan against the orange-and-graphite suit.
iris = material('Glowing amber iris', (.98, .5, .06), 'screen', .05, .9)
neon = material('Neon cyan circuit', (.0, .78, 1.0), 'screen', .05, 1.3)
tread = material('Graphite tread rubber', (.03, .034, .042), 'tread', .1)
# Dark brows read against the orange fur.
brow_fur = material('Dark brow fur', (.09, .035, .015), 'fur')
if not opts.quick:
    nodes, links = inner.node_tree.nodes, inner.node_tree.links
    separate = nodes.new('ShaderNodeSeparateXYZ')
    links.new(nodes['Texture Coordinate'].outputs['Generated'], separate.inputs[0])
    gradient = nodes.new('ShaderNodeValToRGB')
    gradient.color_ramp.elements[0].color = (.62, .18, .16, 1)
    gradient.color_ramp.elements[1].color = (.80, .30, .28, 1)
    ear_range = nodes.new('ShaderNodeMapRange')
    ear_range.inputs['From Min'].default_value = .8
    ear_range.inputs['From Max'].default_value = 1.0
    links.new(separate.outputs['Z'], ear_range.inputs['Value'])
    links.new(ear_range.outputs['Result'], gradient.inputs[0])
    links.new(gradient.outputs[0], nodes['Principled BSDF'].inputs['Base Color'])
    old = recipes[inner.name]
    recipes[inner.name] = (gradient.name, *old[1:])



def finish(obj, name, mat, bone, atlas):
    obj.name = name
    bpy.context.view_layer.objects.active = obj
    object_name = obj.name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj = object_named(object_name, 'MESH')
    obj.data.materials.append(mat)
    for p in obj.data.polygons: p.use_smooth = True
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    obj['atlas'] = atlas
    parts.append((obj.name, atlas))
    return obj.name


def ellipsoid(name, at, size, mat, bone, atlas='body', segments=24, rings=16, yaw=0.0, pitch=0.0, roll=0.0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=xyz(at))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    # yaw: radians about the vertical axis, positive turns the front (-Z) face toward +x;
    # pitch: radians about x, positive tips the top back (+Z); roll: positive tips the top toward +x.
    obj.rotation_euler = (pitch, roll, -yaw)
    # Sculpted asymmetric face and tapered leaf-shaped ears, with quad latitude loops.
    if 'Skull' in name:
        # Rabbit skull, not a ball: narrower toward the brow and muzzle, flatter cheeks.
        for v in obj.data.vertices:
            v.co.x *= 1 - .16 * max(0, v.co.y) - .06 * max(0, -v.co.z)
            v.co.z *= 1 - .08 * max(0, v.co.y)
    if 'Tail' in name:
        for v in obj.data.vertices:
            v.co *= 1 + .055 * math.sin(v.co.x * 11) * math.sin(v.co.z * 9)
    if 'Boot foot' in name:
        # Sleeker boot: the instep stays high, the toe slopes down toward the sole.
        for v in obj.data.vertices:
            v.co.z *= 1 - .22 * max(0, v.co.y)
    if 'Ear' in name:
        for v in obj.data.vertices:
            # Round 8: a gentler leaf taper keeps the ear tips round rather than pointed.
            v.co.x *= .9 + .1 * (1 - v.co.z * v.co.z)
            v.co.y -= .48 * max(0, v.co.z) ** 2
    return finish(obj, name, mat, bone, atlas)


def tube(name, points, radius, mat, bone, atlas='accessory', detail=2):
    curve = bpy.data.curves.new(name, 'CURVE'); curve.dimensions = '3D'
    curve.resolution_u = 2; curve.bevel_depth = radius; curve.bevel_resolution = detail
    spline = curve.splines.new('BEZIER'); spline.bezier_points.add(len(points) - 1)
    for p, co in zip(spline.bezier_points, points):
        p.co = xyz(co); p.handle_left_type = 'AUTO'; p.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, curve); scene.collection.objects.link(obj)
    object_name = obj.name
    bpy.ops.object.select_all(action='DESELECT')
    obj = object_named(object_name)
    obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    return finish(object_named(object_name, 'MESH'), name, mat, bone, atlas)


def box(name, at, size, mat, bone, atlas='accessory'):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(at))
    obj = bpy.context.object; obj.scale = (size[0], size[2], size[1])
    object_name = obj.name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj = object_named(object_name, 'MESH')
    bevel = obj.modifiers.new('Tailored rounded edges', 'BEVEL'); bevel.width = min(size) * .22; bevel.segments = 3
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return finish(object_named(object_name, 'MESH'), name, mat, bone, atlas)

def loft(name, rows, mat, bone, sides=12, atlas='body', crease=0.0, ribs=0, rib=0.0, warp=None):
    """Continuous quad rings with Catmull-Clark subdivision; joint cores fill bends.
    Rows: (centre_x, height_y, centre_z, radius_x, radius_z). ribs/rib add knit ribbing.
    warp(row_index, y, a) -> (outward metres, lift metres) sculpts muscles, fins and cuts;
    ring angle a: cos(a) is +x, sin(a) is +z (the back), so the front is sin(a) = -1.
    """
    vertices, faces = [], []
    for row_index, (cx, y, cz, rx, rz) in enumerate(rows):
        for j in range(sides):
            a = j * math.tau / sides
            fold = 1 + crease * math.sin(row_index * 2.3 + a * 3)
            if ribs:
                fold *= 1 + rib * math.cos(a * ribs)
            out, lift = warp(row_index, y, a) if warp else (0.0, 0.0)
            vertices.append(xyz((cx + (rx * fold + out) * math.cos(a), y + lift, cz + (rz * fold + out) * math.sin(a))))
    for i in range(len(rows) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((i*sides+j, i*sides+k, (i+1)*sides+k, (i+1)*sides+j))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(rows)-1)*sides+j for j in range(sides)))
    if rows[1][1] > rows[0][1]:
        faces = [tuple(reversed(face)) for face in faces]
    data = bpy.data.meshes.new(name); data.from_pydata(vertices, [], faces); data.update()
    obj = bpy.data.objects.new(name, data); scene.collection.objects.link(obj)
    object_name = obj.name
    bpy.ops.object.select_all(action='DESELECT')
    obj = object_named(object_name, 'MESH')
    obj.select_set(True); bpy.context.view_layer.objects.active = obj
    sub = obj.modifiers.new('Continuous tailored subdivision', 'SUBSURF'); sub.levels = 1
    require('FINISHED' in bpy.ops.object.modifier_apply(modifier=sub.name), 'Subdivision failed: ' + name)
    return finish(object_named(object_name, 'MESH'), name, mat, bone, atlas)


def tuft(name, base, ctrl, tip, radius, mat, bone, sides=6, steps=4, atlas='body'):
    """Tapered fur tuft along a quadratic Bezier (Godot coordinates); rings follow the path."""
    p0, p1, p2 = Vector(base), Vector(ctrl), Vector(tip)
    vertices, faces = [], []
    for step in range(steps):
        u = step / steps
        at = (1-u)**2*p0 + 2*(1-u)*u*p1 + u*u*p2
        tangent = (2*(1-u)*(p1-p0) + 2*u*(p2-p1)).normalized()
        side_axis = tangent.cross(Vector((0, 0, 1)))
        if side_axis.length < 1e-4: side_axis = tangent.cross(Vector((1, 0, 0)))
        side_axis.normalize(); up_axis = side_axis.cross(tangent).normalized()
        r = radius * (1 - u) ** .8
        for j in range(sides):
            a = j * math.tau / sides
            vertices.append(xyz(at + (side_axis*math.cos(a) + up_axis*math.sin(a)) * r))
    vertices.append(xyz(p2))
    tip_index = len(vertices) - 1
    for i in range(steps - 1):
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((i*sides+j, i*sides+k, (i+1)*sides+k, (i+1)*sides+j))
    last = (steps - 1) * sides
    for j in range(sides):
        faces.append((last+j, last+(j+1) % sides, tip_index))
    faces.append(tuple(reversed(range(sides))))
    data = bpy.data.meshes.new(name); data.from_pydata(vertices, [], faces); data.update()
    # Outward winding: recalculated so back-face culling in Godot never hides a tuft.
    obj = bpy.data.objects.new(name, data); scene.collection.objects.link(obj)
    object_name = obj.name
    bpy.ops.object.select_all(action='DESELECT')
    obj = object_named(object_name, 'MESH'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
    return finish(object_named(object_name, 'MESH'), name, mat, bone, atlas)


def blend_across(object_name, centre, left, right, half_width):
    """Mouth corners: |x| blends the head-weighted centre into per-side corner bones."""
    obj = object_named(object_name, 'MESH')
    for group in (left, right):
        if obj.vertex_groups.get(group) is None: obj.vertex_groups.new(name=group)
    for vertex in obj.data.vertices:
        x = (obj.matrix_world @ vertex.co).x
        w = max(0, min(1, (abs(x) / half_width - .15) / .85)); w = w * w * (3 - 2 * w)
        obj.vertex_groups[centre].add([vertex.index], 1 - w, 'REPLACE')
        obj.vertex_groups[left if x < 0 else right].add([vertex.index], w, 'REPLACE')


def reassign(object_name, bone):
    obj = object_named(object_name, 'MESH')
    obj.vertex_groups.clear()
    obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1, 'REPLACE')


def led_mask(object_name, index, count):
    """Runtime LED mask exported as COLOR_0: R = LED, G = segment index along the strip."""
    obj = object_named(object_name, 'MESH')
    attribute = obj.data.color_attributes.new('led_mask', 'FLOAT_COLOR', 'POINT')
    for item in attribute.data:
        item.color = (1.0, index / (count - 1), 0.0, 1.0)


CAPE_TOP, CAPE_HEM = 1.20, .50
CAPE_THICKNESS = .012
CAPE_TEETH, CAPE_TOOTH = 5, .05  # Jagged hero hem: five points, 5 cm deep.


def ramp01(a, b, x):
    u = max(0.0, min(1.0, (x - a) / (b - a)))
    return u * u * (3 - 2 * u)


def dense(rows, step):
    """Linearly resample loft rows to at most `step` metres apart, so sculpting has rings to move."""
    out = [rows[0]]
    for r0, r1 in zip(rows, rows[1:]):
        count = max(1, math.ceil(abs(r1[1] - r0[1]) / step))
        out += [tuple(a + (b - a) * k / count for a, b in zip(r0, r1)) for k in range(1, count + 1)]
    return out


def gauss(x, mu, sigma):
    return math.exp(-.5 * ((x - mu) / sigma) ** 2)


def cape_point(u, v):
    """Outer cape surface and outward normal; u in [-1, 1] across the back, v 0 collar .. 1 hem.
    It hangs close under the shoulders, drapes over the tail, then falls nearly straight."""
    y = CAPE_TOP - (CAPE_TOP - CAPE_HEM) * v
    theta = u * (1.15 - .3 * v)
    rx = .17 + .18 * v
    cz = -.015 + .015 * v
    rz = .13 + .1 * ramp01(0, .8, v) + .03 * v - cz
    tooth = abs(((u + 1) / 2 * CAPE_TEETH) % 1 - .5) * 2  # 1 between points, 0 at each point.
    y -= CAPE_TOOTH * v ** 6 * (1 - tooth)
    normal = Vector((math.sin(theta) / rx, 0, math.cos(theta) / rz)).normalized()
    point = Vector((rx * math.sin(theta), y, cz + rz * math.cos(theta)))
    # Vertical folds deepen toward the hem.
    return point + normal * .02 * v ** 1.3 * math.sin(u * 6 * math.pi + .6), normal


def collar_point(u, v):
    """Stand-up collar behind the neck, flaring back as it rises (v 0 base .. 1 rim)."""
    theta = u * .95
    rx, cz = .12 + .02 * v, -.015
    rz = .12 + .035 * v - cz
    normal = Vector((math.sin(theta) / rx, 0, math.cos(theta) / rz)).normalized()
    return Vector((rx * math.sin(theta), 1.175 + .095 * v, cz + rz * math.cos(theta))), normal


def pauldron_point(side):
    """Spherical shoulder-armor cap over the deltoid, open on the body side."""
    centre, radius = Vector((side * .247, 1.17, 0)), .1
    axis = Vector((side * .447, .894, 0))
    out = Vector((side * .894, -.447, 0))
    def surface(u, v):
        theta, phi = u * 2.2, v * 1.05
        normal = axis * math.cos(phi) + (out * math.cos(theta) + Vector((0, 0, 1)) * math.sin(theta)) * math.sin(phi)
        return centre + normal * radius, normal
    return surface


def cape_weights(object_name):
    """Collar rides the chest; the body swings on cape and the lower cape flutters on cape_tip."""
    obj = object_named(object_name, 'MESH')
    obj.vertex_groups.clear()
    groups = [obj.vertex_groups.new(name=n) for n in ('chest', 'cape', 'cape_tip')]
    for vertex in obj.data.vertices:
        y = (obj.matrix_world @ vertex.co).z
        top = ramp01(1.10, 1.16, y); tip = 1 - ramp01(.78, .92, y)
        for group, weight in zip(groups, (top, max(0.0, 1 - top - tip), tip)):
            if weight > 0: group.add([vertex.index], weight, 'REPLACE')


def slab(name, surface, nu, nv, outer_mat, inner_mat, bone):
    """Closed cloth slab from surface(u, v) -> (point, outward normal): outer face, lining face
    toward the body (material 1) and a flat-shaded rim. Returns the object name."""
    def at(side, i, j):
        return side * (nu + 1) * (nv + 1) + j * (nu + 1) + i
    vertices = []
    for side in (0, 1):
        for j in range(nv + 1):
            for i in range(nu + 1):
                point, normal = surface(-1 + 2 * i / nu, j / nv)
                vertices.append(xyz(point - normal * CAPE_THICKNESS * side))
    outer, rim, inner = [], [], []
    for j in range(nv):
        for i in range(nu):
            outer.append((at(0, i, j), at(0, i+1, j), at(0, i+1, j+1), at(0, i, j+1)))
            inner.append((at(1, i, j+1), at(1, i+1, j+1), at(1, i+1, j), at(1, i, j)))
    for i in range(nu):
        for j in (0, nv):
            rim.append((at(0, i, j), at(1, i, j), at(1, i+1, j), at(0, i+1, j)))
    for j in range(nv):
        for i in (0, nu):
            rim.append((at(0, i, j), at(0, i, j+1), at(1, i, j+1), at(1, i, j)))
    data = bpy.data.meshes.new(name); data.from_pydata(vertices, [], outer + rim + inner); data.update()
    obj = bpy.data.objects.new(name, data); scene.collection.objects.link(obj)
    object_name = obj.name
    bpy.ops.object.select_all(action='DESELECT')
    obj = object_named(object_name, 'MESH'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
    object_name = finish(object_named(object_name, 'MESH'), name, outer_mat, bone, 'body')
    obj = object_named(object_name, 'MESH')
    obj.data.materials.append(inner_mat)
    for index, polygon in enumerate(obj.data.polygons):
        if index >= len(outer) + len(rim): polygon.material_index = 1
        elif index >= len(outer): polygon.use_smooth = False
    return object_name


def surface_hit(object_name, x, y, from_back):
    """(point, outward normal) in Godot coordinates where a ray along z meets the mesh.
    The normal is the hit face's smooth vertex normals interpolated at the hit, so emblems
    offset along it stay continuous across the target's facets. The torso and cape are built
    at the origin, so object space is world space."""
    obj = object_named(object_name, 'MESH')
    sign = 1 if from_back else -1
    ok, location, face_normal, index = obj.ray_cast(xyz((x, y, 2.0 * sign)), xyz((0, 0, -sign)))
    require(ok, 'Surface ray missed %s at (%.3f, %.3f)' % (object_name, x, y))
    corners = [obj.data.vertices[i] for i in obj.data.polygons[index].vertices]
    weights = mathutils.interpolate.poly_3d_calc([v.co for v in corners], location)
    normal = sum((v.normal * w for v, w in zip(corners, weights)), Vector())
    if normal.dot(face_normal) < 0: normal = -normal
    return Vector((location.x, location.z, -location.y)), Vector((normal.x, normal.z, -normal.y)).normalized()


def rabbit_field(px, py):
    """CodeRabbit-style badge: a round head with two upright ears, smooth-filleted where they meet."""
    def ellipse(cx, cy, ax, ay, roll):
        dx, dy = px - cx, py - cy
        u = dx * math.cos(roll) - dy * math.sin(roll); w = dx * math.sin(roll) + dy * math.cos(roll)
        return (math.hypot(u / ax, w / ay) - 1) * min(ax, ay)
    def smin(a, b, k):
        h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k / 4
    ears = min(ellipse(-.026, .08, .022, .06, -.14), ellipse(.026, .08, .022, .06, .14))
    return smin(ellipse(0, 0, .062, .052, 0), ears, .014)


def plate_field(corners, rounding):
    """Rounded convex plate: signed distance to a CCW convex polygon, grown by `rounding`."""
    def field(px, py):
        worst = -1e9
        for (x0, y0), (x1, y1) in zip(corners, corners[1:] + corners[:1]):
            ex, ey = x1 - x0, y1 - y0; length = math.hypot(ex, ey)
            worst = max(worst, ((px - x0) * ey - (py - y0) * ex) / length)
        return worst - rounding
    return field


def rabbit_outline(scale, inset=0.0, step=.0015, count=96, field=rabbit_field, box=(-.1, .1, -.07, .16)):
    """Closed contour of `field` (moved `inset` metres inward, before scaling): marching squares,
    resampled to `count` points (CCW) from the leftmost point."""
    xs = [box[0] + step * i for i in range(int((box[1] - box[0]) / step) + 1)]
    ys = [box[2] + step * j for j in range(int((box[3] - box[2]) / step) + 1)]
    grid = [[field(x, y) + inset for x in xs] for y in ys]
    def edge_point(i0, j0, i1, j1):
        a, b = grid[j0][i0], grid[j1][i1]; t = a / (a - b)
        return (round(xs[i0] + (xs[i1] - xs[i0]) * t, 7), round(ys[j0] + (ys[j1] - ys[j0]) * t, 7))
    links = {}
    for j in range(len(ys) - 1):
        for i in range(len(xs) - 1):
            corners = [(i, j), (i+1, j), (i+1, j+1), (i, j+1)]
            crossings = [edge_point(*corners[k], *corners[(k+1) % 4]) for k in range(4)
                         if (grid[corners[k][1]][corners[k][0]] < 0) != (grid[corners[(k+1) % 4][1]][corners[(k+1) % 4][0]] < 0)]
            require(len(crossings) in (0, 2), 'Ambiguous badge contour cell')
            if crossings:
                a_, b_ = crossings
                links.setdefault(a_, []).append(b_); links.setdefault(b_, []).append(a_)
    start = min(links); loop = [start]; previous = None
    while True:
        nxt = [q for q in links[loop[-1]] if q != previous][0]
        if nxt == start: break
        previous = loop[-1]; loop.append(nxt)
    require(len(loop) == len(links), 'Badge contour is not one closed loop')
    if sum(a_[0] * b_[1] - b_[0] * a_[1] for a_, b_ in zip(loop, loop[1:] + loop[:1])) < 0:
        loop.reverse()
    lengths = [0.0]
    for a_, b_ in zip(loop, loop[1:] + loop[:1]):
        lengths.append(lengths[-1] + math.dist(a_, b_))
    out, k = [], 0
    for n_ in range(count):
        target = lengths[-1] * n_ / count
        while lengths[k + 1] < target: k += 1
        a_, b_ = loop[k], loop[(k + 1) % len(loop)]
        t = (target - lengths[k]) / max(lengths[k + 1] - lengths[k], 1e-9)
        out.append(((a_[0] + (b_[0] - a_[0]) * t) * scale, (a_[1] + (b_[1] - a_[1]) * t) * scale))
    return out


def rounded_rect(width, height, radius, per_corner=4):
    points = []
    for cx, cy, start in ((width/2-radius, height/2-radius, 0), (-width/2+radius, height/2-radius, 90),
                          (-width/2+radius, -height/2+radius, 180), (width/2-radius, -height/2+radius, 270)):
        for k in range(per_corner + 1):
            a = math.radians(start + 90 * k / per_corner)
            points.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return points


def cap_mesh(outline, spacing):
    """Even triangles filling a CCW outline: constrained Delaunay over the outline plus an
    interior grid. Returns (points, triangles); points[:len(outline)] are the outline."""
    count = len(outline)
    def inside(px, py):
        crossings = False
        for (x0, y0), (x1, y1) in zip(outline, outline[1:] + outline[:1]):
            if (y0 > py) != (y1 > py) and px < x0 + (py - y0) * (x1 - x0) / (y1 - y0):
                crossings = not crossings
        return crossings
    def clearance(px, py):
        return min(math.dist((px, py), q) for q in outline)
    xs = [q[0] for q in outline]; ys = [q[1] for q in outline]
    interior = [(min(xs) + spacing * (i + .5 * (j % 2)), min(ys) + spacing * .87 * j)
                for j in range(int((max(ys) - min(ys)) / (spacing * .87)) + 2)
                for i in range(int((max(xs) - min(xs)) / spacing) + 2)]
    interior = [q for q in interior if inside(*q) and clearance(*q) > spacing * .6]
    points = list(outline) + interior
    result = mathutils.geometry.delaunay_2d_cdt([Vector(q) for q in points], [], [list(range(count))], 1, 1e-7)
    coords, _edges, faces, original = result[0], result[1], result[2], result[3]
    remap = {}
    for new, olds in enumerate(original):
        for old in olds: remap[new] = old
    require(len(coords) == len(points) and all(i in remap for i in range(len(coords))), 'Emblem triangulation added vertices')
    return points, [tuple(remap[i] for i in face) for face in faces]


def conformed(name, outer, inner, x, y, target, from_back, mat, bone, depth=.006, gap=.001, spacing=.008):
    """Chamfered flat emblem wrapped onto `target`'s surface by ray casts. `outer` is the base
    outline and `inner` the same outline inset by the chamfer (equal point counts, same start):
    a side wall rises `depth` along the local surface normal, then a 45-degree chamfer meets the face.
    The face is evenly triangulated so it follows the curved surface; the base is open against it."""
    require(len(outer) == len(inner), 'Emblem outlines differ in length: ' + name)
    count = len(outer)
    chamfer = sum(math.dist(a_, b_) for a_, b_ in zip(outer, inner)) / count
    rings = [(outer, 0.0), (outer, depth - chamfer), (inner, depth)]
    vertices = []
    for ring, height in rings:
        for px, py in ring:
            point, normal = surface_hit(target, x + px, y + py, from_back)
            vertices.append(xyz(point + normal * (height + gap)))
    faces = []
    for r in range(2):
        for i in range(count):
            j = (i + 1) % count
            faces.append((r*count + i, r*count + j, (r+1)*count + j, (r+1)*count + i))
    walls = len(faces)
    cap_points, cap_triangles = cap_mesh(inner, spacing)
    for px, py in cap_points[count:]:
        point, normal = surface_hit(target, x + px, y + py, from_back)
        vertices.append(xyz(point + normal * (depth + gap)))
    faces += [tuple(2*count + i for i in tri) for tri in cap_triangles]
    data = bpy.data.meshes.new(name); data.from_pydata(vertices, [], faces); data.update()
    obj = bpy.data.objects.new(name, data); scene.collection.objects.link(obj)
    object_name = obj.name
    bpy.ops.object.select_all(action='DESELECT')
    obj = object_named(object_name, 'MESH'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
    obj = object_named(object_name, 'MESH')
    # An open shell has no inside for normals_make_consistent: the face must point off the surface.
    probe_index = len(obj.data.polygons) - 1
    probe = obj.data.polygons[probe_index]
    _point, outward = surface_hit(target, x + cap_points[-1][0], y + cap_points[-1][1], from_back)
    if Vector((probe.normal.x, probe.normal.z, -probe.normal.y)).dot(outward) < 0:
        for polygon in obj.data.polygons: polygon.flip()
    object_name = finish(obj, name, mat, bone, 'accessory')
    # Crisp wall and chamfer; the caps stay smooth so they follow the curved surface.
    for index, polygon in enumerate(object_named(object_name, 'MESH').data.polygons):
        polygon.use_smooth = index >= walls
    return object_name


def blend_joint(object_name, upper, lower, joint_y, width):
    obj = object_named(object_name, 'MESH')
    if obj.vertex_groups.get(lower) is None: obj.vertex_groups.new(name=lower)
    for vertex in obj.data.vertices:
        weight = max(0, min(1, (joint_y + width - (obj.matrix_world @ vertex.co).z) / (2*width)))
        weight = weight * weight * (3-2*weight)
        obj.vertex_groups[upper].add([vertex.index], 1-weight, 'REPLACE')
        obj.vertex_groups[lower].add([vertex.index], weight, 'REPLACE')


def joint_crease(object_name, joint_y):
    obj = object_named(object_name, 'MESH')
    attribute = obj.data.attributes.new('joint_crease', 'FLOAT', 'POINT')
    for vertex in obj.data.vertices:
        y = (obj.matrix_world @ vertex.co).z
        attribute.data[vertex.index].value = -.18 * math.exp(-((y-joint_y)/.012)**2)


def joint_core(side, name, at, radius, mat, upper, lower):
    # 140 triangles each; reuse body atlas/material. No extra draw surfaces.
    object_name = ellipsoid(name+' joint core '+side, at, (radius, radius*.88, radius),
                            mat, upper, segments=10, rings=8)
    blend_joint(object_name, upper, lower, at[1], .035)
    joint_crease(object_name, at[1])


stage('model geometry')
# Action-figure proportions (Godot metres): ankle .10, knee .44, hip joint .80, waist .92,
# shoulder joint 1.15, neck 1.18-1.25, skull centre 1.335, ear tips 1.80.
ellipsoid('Skull sculpt', (0, 1.335, 0), (.135, .145, .14), fur, 'head', segments=28, rings=20)
ellipsoid('Muzzle', (0, 1.285, -.115), (.075, .06, .085), cream, 'head', segments=20, rings=14)
ellipsoid('Chin', (0, 1.245, -.09), (.06, .035, .06), cream, 'head', segments=16, rings=10)
loft('Neck', [(0,y,0,r,r) for y,r in [(1.165,.068),(1.22,.06),(1.275,.058)]], fur, 'neck', sides=16)
ellipsoid('Throat fluff', (0, 1.22, -.05), (.06, .05, .04), cream, 'neck', segments=16, rings=10)
# Heroic V taper with squared, plated cross-sections: rows (y, centre z, rx, rz).
TORSO_ROWS = [(.78,.01,.155,.112),(.81,.01,.18,.128),(.86,.01,.172,.122),(.92,.005,.16,.112),
              (.98,0,.182,.12),(1.04,-.005,.222,.132),(1.10,-.008,.242,.138),(1.15,-.004,.232,.122),
              (1.185,0,.168,.09),(1.21,0,.08,.062)]


def torso_muscle(_row, y, a):
    """Squared armour section (superellipse), two pecs, a six-pack and shoulder blades."""
    front, back, lateral = max(0.0, -math.sin(a)), max(0.0, math.sin(a)), math.cos(a)
    square = (abs(math.cos(a)) ** 2.8 + abs(math.sin(a)) ** 2.8) ** (-1 / 2.8) - 1
    pec_height = gauss(y, 1.085, .022 if y < 1.085 else .035)
    pecs = .02 * (gauss(lateral, -.34, .21) + gauss(lateral, .34, .21)) * pec_height * front ** 1.5
    six = .006 * front ** 2 * sum(gauss(lateral, c, .06) for c in (-.1, .1)) * sum(gauss(y, r, .013) for r in (.955, .99, 1.025))
    blades = .01 * back ** 2 * (gauss(lateral, -.45, .2) + gauss(lateral, .45, .2)) * gauss(y, 1.1, .045)
    return .13 * square * ramp01(.8, .9, y) * (1 - ramp01(1.16, 1.2, y)) + pecs + six + blades, 0.0


torso = loft('Suit tailored torso', [(0,y,z,rx,rz) for y,z,rx,rz in dense(TORSO_ROWS, .03)], suit, 'spine',
             sides=32, crease=.003, warp=torso_muscle)
loft('Suit hip band', [(0,y,.01,.178,.128) for y in (.79,.795,.835,.84)], suit, 'hips', sides=32)
# Armoured chest plate (Hero intro art) carrying the rabbit badge from the gameplay sprite.
PLATE = [(-.15, -.01), (0, -.10), (.15, -.01), (.14, .085), (-.14, .085)]
plate_box = (-.2, .2, -.15, .13)
chest_plate = conformed('Chest armour plate', rabbit_outline(1.0, 0.0, .002, 72, plate_field(PLATE, .012), plate_box),
                        rabbit_outline(1.0, .004, .002, 72, plate_field(PLATE, .012), plate_box),
                        0, 1.075, torso, False, armour, 'spine', depth=.01)
conformed('Chest badge', rabbit_outline(.75), rabbit_outline(.75, .0025), 0, 1.05, chest_plate, False, glove, 'spine', depth=.006)
# Hero cape: stand-up collar, drape over the shoulder blades and tail, deep folds, jagged hem.
# Its back carries the rabbit badge and, below it, the power-up LED strip the chase camera reads.
hero_cape = slab('Hero cape', cape_point, 30, 16, cape_shell, lining, 'cape')
cape_weights(hero_cape)
slab('Cape collar', collar_point, 16, 3, cape_shell, lining, 'chest')
cape_parts = [conformed('Cape badge', rabbit_outline(.8), rabbit_outline(.8, .0025), 0, 1.04, hero_cape, True, glove, 'cape')]
for led in range(4):
    name = conformed('Cape power LED ' + str(led), rounded_rect(.018, .042, .005), rounded_rect(.015, .039, .0035),
                     -.042 + led * .028, .95, hero_cape, True, amber, 'cape', depth=.005, spacing=.006)
    led_mask(name, led, 4)
    cape_parts.append(name)
for name in cape_parts:
    cape_weights(name)
# Cotton tail on the rump, under the cape; it is the slide's floor contact, so it stays shallow.
TAIL_Y = .83
ellipsoid('Tail tuft', (0, TAIL_Y, .12), (.06, .065, .055), cream, 'tail', segments=16, rings=10)
for i, (dx, dy, dz) in enumerate([(-.03,.028,.018),(.03,.028,.018),(-.032,-.025,.015),(.032,-.025,.015),(0,.0,.028)]):
    ellipsoid('Tail lobe %d' % i, (dx, TAIL_Y+dy, .12+dz), (.036, .038, .034), cream, 'tail', segments=12, rings=8)
for side, sign in [('L', -1), ('R', 1)]:
    x = sign
    ellipsoid('Cape clasp ' + side, (x*.15, 1.19, .06), (.026, .026, .014), gold, 'chest', 'accessory', 16, 10, yaw=x*.9)
    slab('Pauldron ' + side, pauldron_point(x), 14, 6, armour, suit, 'arm_'+side)
    ellipsoid('Cheek ' + side, (x*.055, 1.29, -.095), (.065, .055, .06), cream, 'head', segments=16, rings=12)
    # Long upright ears; tips exactly at the 1.8 m standing height.
    ellipsoid('Ear ' + side, (x*.072, 1.60, .015), (.052, .20, .03), fur, 'ear_'+side, segments=20, rings=14)
    ellipsoid('Inner Ear ' + side, (x*.072, 1.61, -.008), (.03, .155, .008), inner, 'ear_'+side, segments=16, rings=12)
    # Fierce almond eyes: narrow, outer corners swept up, a heavy black upper lid and glowing
    # amber irises. Sclera, iris and lid ride the eye bone (squint scale).
    eye_roll = -x * .3
    eye_c = Vector((x*.068, 1.362, -.114))
    def on_eye(px, py, depth):
        # Point in the eye's frontal plane (rolled, then yawed outward) plus depth along its facing.
        u = Vector((math.cos(.4), 0, x * math.sin(.4)))
        facing = Vector((x * math.sin(.4), 0, -math.cos(.4)))
        rx_, ry_ = px * math.cos(eye_roll) + py * math.sin(eye_roll), -px * math.sin(eye_roll) + py * math.cos(eye_roll)
        return tuple(eye_c + u * rx_ + Vector((0, 1, 0)) * ry_ + facing * depth)
    ellipsoid('Sclera '+side, tuple(eye_c), (.036, .024, .014), white, 'eye_'+side, 'accessory', 20, 12, yaw=x*.4, roll=eye_roll)
    ellipsoid('Iris '+side, on_eye(.003, -.002, .011), (.016, .019, .005), iris, 'eye_'+side, 'accessory', 16, 10, yaw=x*.4, roll=eye_roll)
    # Slit pupil: predatory, not cute.
    ellipsoid('Pupil '+side, on_eye(.003, -.002, .015), (.0035, .015, .003), black, 'eye_'+side, 'accessory', 12, 8, yaw=x*.4, roll=eye_roll)
    ellipsoid('Catchlight '+side, on_eye(-.004, .006, .017), (.004, .004, .002), white, 'eye_'+side, 'accessory', 10, 6, yaw=x*.4)
    tube('Upper eyelid '+side, [on_eye(-.038, -.002, .004), on_eye(-.012, .024, .008), on_eye(.016, .026, .008),
         on_eye(.04, .006, .004)], .0045, black, 'eye_'+side)
    # Low, straight brows angled down toward the nose: stern, never cartoon-arched.
    tube('Brow '+side, [(x*.028,1.392,-.128),(x*.07,1.41,-.124),(x*.112,1.42,-.098)], .0085, brow_fur, 'brow_'+side, detail=1)
    for j, (by, tx, ty) in enumerate([(1.27,.145,1.25),(1.29,.15,1.29),(1.25,.13,1.225)]):
        tuft('Cheek tuft %s %d' % (side, j), (x*.1, by, -.07), (x*(tx-.02), (by+ty)/2, -.06), (x*tx, ty, -.045), .014, cream, 'head')
    for j, by in enumerate((1.48, 1.54, 1.60)):
        tuft('Ear rim tuft %s %d' % (side, j), (x*.118, by, .015), (x*.13, by+.012, .02), (x*.138, by+.026, .025), .012, fur, 'ear_'+side)
    tuft('Inner ear tuft '+side, (x*.072, 1.47, -.012), (x*.075, 1.49, -.025), (x*.078, 1.515, -.03), .012, cream, 'ear_'+side)
    for j in range(2):
        tube('Whisker %s %d'%(side,j), [(x*.05,1.29-j*.012,-.175),(x*.11,1.293-j*.02,-.16),(x*.16,1.30-j*.032,-.13)], .0015, cream, 'head')
    # Long heroic arms: deltoid dome under the pauldron, biceps, forearm tapering into the gauntlet.
    sleeve = loft('Continuous sleeve '+side, dense([(x*cx,y,z,rx,rz) for cx,y,z,rx,rz in [
        (0.235,1.215,0,0.034,0.034),(0.239,1.205,0,0.063,0.063),(0.243,1.185,0,0.083,0.081),(0.250,1.15,0,0.090,0.085),(0.257,1.10,0,0.078,0.076),(0.263,1.04,-.005,0.076,0.074),(0.268,.98,-.008,0.067,0.066),(0.272,.93,-.01,0.063,0.063),(0.274,.90,-.012,0.062,0.062),(0.277,.86,-.014,0.064,0.063),(0.280,.80,-.016,0.060,0.057),(0.282,.74,-.018,0.052,0.051),(0.283,.70,-.018,0.046,0.046)]], .07), suit,'arm_'+side,sides=16,crease=.015,
        warp=lambda _r, y, a: (.01*max(0., -math.sin(a))**2*gauss(y,1.04,.035)
                               + .007*max(0., math.sin(a))**2*gauss(y,1.06,.04), 0.0))
    blend_joint(sleeve,'arm_'+side,'forearm_'+side,.90,.045)
    joint_crease(sleeve,.90)
    joint_core(side,'Elbow',(x*.275,.90,-.012),.063,suit,'arm_'+side,'forearm_'+side)
    # Flared orange gauntlets with a swept fin on the outside, over fisted gloves.
    loft('Glove cuff '+side,[(x*.284,y,-.018,r,r) for y,r in [(.69,.05),(.698,.06),(.765,.067),(.775,.058)]],
         glove,'forearm_'+side,sides=20,
         warp=lambda row, y, a, s=x: (0.0, 0.0) if row < 2 else (.008*max(0., math.cos(a)*s)**3, .04*max(0., math.cos(a)*s)**3))
    ellipsoid('Palm '+side,(x*.286,.645,-.02),(.053,.054,.05),glove,'hand_'+side,segments=18,rings=12)
    ellipsoid('Thumb '+side,(x*.248,.655,-.062),(.02,.018,.031),glove,'hand_'+side,segments=12,rings=8)
    for finger in range(4):
        ellipsoid('Knuckle %s %d'%(side,finger),(x*(.255+finger*.021),.612,-.054),(.014,.022,.02),glove,'hand_'+side,segments=10,rings=8)
    # Long legs: rounded quads, a defined knee and calf, then hero boots.
    leg = loft('Continuous leg '+side,dense([(x*cx,y,z,rx,rz) for cx,y,z,rx,rz in [
        (0.100,.83,.01,0.078,0.090),(0.100,.80,.01,0.095,0.103),(0.102,.74,.005,0.099,0.101),(0.103,.66,0,0.090,0.092),(0.104,.58,-.003,0.081,0.083),(0.105,.50,-.006,0.072,0.074),(0.105,.46,-.008,0.069,0.072),(0.105,.44,-.01,0.071,0.073),(0.106,.42,-.01,0.067,0.069),(0.107,.36,-.004,0.069,0.072),(0.108,.28,0,0.062,0.064),(0.109,.20,0,0.053,0.055),(0.110,.14,0,0.048,0.050),(0.110,.10,0,0.047,0.049)]], .08),suit,'leg_'+side,sides=14,crease=.006,
        warp=lambda _r, y, a: (.008*max(0., -math.sin(a))**2*gauss(y,.70,.06) + .006*max(0., math.sin(a))**2*gauss(y,.32,.05), 0.0))
    blend_joint(leg,'leg_'+side,'shin_'+side,.44,.05)
    joint_crease(leg,.44)
    joint_core(side,'Knee',(x*.105,.44,-.01),.071,suit,'leg_'+side,'shin_'+side)
    # Orange hero boots: shaft and a flared cuff rising to a point over the shin, below the knee blend.
    loft('Boot shaft '+side,[(x*.11,y,z,rx,rz) for y,z,rx,rz in [(.10,-.01,.06,.07),(.16,-.006,.06,.064),
         (.25,-.003,.067,.069),(.32,-.002,.075,.077),(.355,-.003,.077,.079)]],glove,'shin_'+side,sides=16)
    loft('Boot cuff '+side,[(x*.108,y,-.003,r,r) for y,r in [(.345,.079),(.35,.086),(.375,.088),(.382,.081)]],glove,'shin_'+side,sides=24,
         warp=lambda row, y, a: (0.0, 0.0) if row < 2 else (.005*max(0., -math.sin(a))**4, .012*max(0., -math.sin(a))**4))
    loft('Boot sole '+side, [(x*.11,y,-.05,SOLE_RADII[0],SOLE_RADII[1]) for y in (0.0,.005,.026,.031)],
         tread, 'foot_'+side, sides=16, atlas='accessory')
    ellipsoid('Boot foot '+side, (x*.11,.075,-.05), (.075,.06,.13), glove, 'foot_'+side, 'accessory', 20, 14)
    ellipsoid('Boot toe cap '+side,(x*.11,.065,-.13),(.068,.042,.055),glove,'foot_'+side,'accessory',20,12)
    # Belt pouches with gold snaps.
    box('Belt pouch '+side,(x*.115,.85,-.115),(.05,.055,.035),leather,'hips')
    box('Pouch snap '+side,(x*.115,.865,-.134),(.016,.013,.006),gold,'hips')
ellipsoid('Nose', (0,1.312,-.196), (.022,.015,.013), inner, 'head', 'accessory')
# A confident smirk: flat on the left, hooked up on the right.
smile = tube('Muzzle smirk', [(-.03,1.263,-.19),(-.015,1.261,-.195),(0,1.26,-.196),(.017,1.263,-.194),(.033,1.275,-.187)], .0022, black, 'head')
blend_across(smile, 'head', 'mouth_L', 'mouth_R', .032)
tube('Utility belt',[(math.sin(i*math.tau/24)*.175,.86,.01+math.cos(i*math.tau/24)*.125) for i in range(25)],.015,leather,'hips',detail=1)
ellipsoid('Belt buckle',(0,.86,-.13),(.034,.034,.012),gold,'hips','accessory',20,12)
box('Utility pouch',(.18,.875,.02),(.05,.09,.085),leather,'hips')
box('Pouch clasp',(.207,.89,.005),(.01,.022,.03),gold,'hips')

# --- Cyberpunk kit (recipe 11) ---
# Cyber HUD visor over the right eye: an angular shard swept back toward the temple, graphite
# frame around a glowing cyan lens, with a temple arm and status LED. It rides the head bone, so
# squints and blinks show on the left eye.
visor_c = Vector((.068, 1.362, -.114)); facing_r = Vector((math.sin(.4), 0, -math.cos(.4)))
across_r = Vector((math.cos(.4), 0, math.sin(.4)))
VISOR = [(-.034, -.016), (.028, -.024), (.074, -.006), (.066, .018), (.002, .032), (-.04, .014)]
def on_visor(px, py, depth):
    # Swept back: the temple end curves around the skull.
    return visor_c + across_r * px + Vector((0, py, 0)) + facing_r * (depth - 2.2 * max(0.0, px - .02) ** 2 * 10)
tube('Visor frame', [tuple(on_visor(px, py, .024)) for px, py in VISOR + VISOR[:1]], .005, armour, 'head', detail=1)
lens_points, lens_triangles = cap_mesh(VISOR, .012)
lens_vertices = [xyz(on_visor(px, py, .022)) for px, py in lens_points]
data = bpy.data.meshes.new('Visor lens'); data.from_pydata(lens_vertices, [], lens_triangles); data.update()
lens = bpy.data.objects.new('Visor lens', data); scene.collection.objects.link(lens)
if data.polygons[0].normal.dot(xyz(facing_r)) < 0:
    for polygon in data.polygons: polygon.flip()
finish(lens, 'Visor lens', neon, 'head', 'accessory')
tube('Visor temple', [tuple(on_visor(.074, -.006, .02)), (.134, 1.36, -.05), (.124, 1.40, .0)], .0045, armour, 'head', detail=1)
box('Visor LED', (.137, 1.362, -.045), (.008, .014, .012), neon, 'head')
# Two metal tags ringing the left ear.
for j, ring_y in enumerate((1.5, 1.545)):
    tube('Ear ring %d' % j, [(-.072 + .057 * math.cos(a), ring_y, .015 + .036 * math.sin(a)) for a in [i * math.tau / 12 for i in range(13)]],
         .0045, gold, 'ear_L', detail=1)
# Neon circuit trim: pauldron edges, gauntlet and boot bands, the chest plate rim and the cape hem.
for side, sign in [('L', -1), ('R', 1)]:
    rim = pauldron_point(sign)
    tube('Pauldron neon ' + side, [tuple(rim(-1 + 2 * i / 12, 1.0)[0] + rim(-1 + 2 * i / 12, 1.0)[1] * .004) for i in range(13)],
         .0035, neon, 'arm_'+side, detail=1)
    tube('Gauntlet neon ' + side, [(sign*.284 + .064 * math.cos(a), .735, -.018 + .064 * math.sin(a)) for a in [i * math.tau / 16 for i in range(17)]],
         .0035, neon, 'forearm_'+side, detail=1)
    tube('Boot neon ' + side, [(sign*.11 + .07 * math.cos(a), .30, -.002 + .072 * math.sin(a)) for a in [i * math.tau / 16 for i in range(17)]],
         .0035, neon, 'shin_'+side, detail=1)
plate_rim = rabbit_outline(1.0, -.003, .002, 40, plate_field(PLATE, .012), plate_box)
rim_points = []
for px, py in plate_rim + plate_rim[:1]:
    point, normal = surface_hit(torso, px, 1.075 + py, False)
    rim_points.append(tuple(point + normal * .006))
tube('Chest plate neon', rim_points, .003, neon, 'spine', detail=1)
hem = [cape_point(-1 + 2 * i / 30, 1.0) for i in range(31)]
cape_hem = tube('Cape hem neon', [tuple(point + normal * .009) for point, normal in hem], .0035, neon, 'cape', detail=1)
cape_weights(cape_hem)

stage('geometry census before baking')
model_triangles = sum(sum(len(face.vertices)-2 for face in object_named(name, 'MESH').data.polygons)
                      for name, _atlas in parts)
print('[hoppy] model triangles=' + str(model_triangles), flush=True)
require(model_triangles + EFFECT_TRIANGLES <= TRIANGLE_CAP, 'Whole-visual pre-bake triangle budget exceeded: ' + str(model_triangles + EFFECT_TRIANGLES))

# Store only names across destructive operators. Joining one atlas invalidates its
# source objects, so never inspect those objects while collecting the next atlas.
mesh_names = []
for atlas, resolution in [('body', 2048), ('accessory', 1024)]:
    stage('join ' + atlas)
    selected_names = [name for name, tag in parts if tag == atlas]
    require(bool(selected_names), 'Empty atlas: ' + atlas)
    bpy.ops.object.select_all(action='DESELECT')
    for name in selected_names:
        object_named(name, 'MESH').select_set(True)
    bpy.context.view_layer.objects.active = object_named(selected_names[0], 'MESH')
    require('FINISHED' in bpy.ops.object.join(), 'Join failed: ' + atlas)
    joined_name = active_name()
    object_named(joined_name, 'MESH').name = 'Hoppy_' + atlas
    joined_name = active_name()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    require(len(object_named(joined_name, 'MESH').data.vertices) > 0, 'Empty joined mesh: ' + atlas)
    if atlas == 'accessory':
        leds = object_named(joined_name, 'MESH').data.color_attributes.get('led_mask')
        require(leds is not None and sum(item.color[0] > .5 for item in leds.data) > 0, 'LED mask lost in join')
    mesh_names.append(joined_name)
    if opts.quick:
        stage('skip bake ' + atlas + '; flat PBR materials retained')
        continue
    stage('UV pack ' + atlas)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.008)
    bpy.ops.object.mode_set(mode='OBJECT')
    require(bool(object_named(joined_name, 'MESH').data.uv_layers), 'No UV layer: ' + atlas)
    baked = {}
    for channel in ('albedo', 'normal', 'orm', 'emissive'):
        stage('bake ' + atlas + '/' + channel)
        image_name = atlas + '_' + channel
        image = bpy.data.images.new(image_name, resolution, resolution, alpha=False)
        image_name = image.name
        image.colorspace_settings.name = 'sRGB' if channel in ('albedo', 'emissive') else 'Non-Color'
        material_names = [m.name for m in object_named(joined_name, 'MESH').data.materials]
        temporary = []
        temporary_nodes = []
        for material_name in material_names:
            m = bpy.data.materials[material_name]
            n, l = m.node_tree.nodes, m.node_tree.links
            target = n.new('ShaderNodeTexImage'); target.image = image; n.active = target
            emit_name = None
            if channel != 'normal':
                emit = n.new('ShaderNodeEmission'); emit_name = emit.name
                base, rough, metal, emission, ao = recipes[material_name]
                if channel == 'albedo':
                    l.new(n[base].outputs[0], emit.inputs['Color'])
                elif channel == 'orm' and ao is not None:
                    # Seam/tread grooves darken baked occlusion (R); G/B stay constant.
                    combine = n.new('ShaderNodeCombineColor')
                    l.new(n[ao].outputs[0], combine.inputs['Red'])
                    combine.inputs['Green'].default_value = rough; combine.inputs['Blue'].default_value = metal
                    l.new(combine.outputs[0], emit.inputs['Color'])
                    temporary_nodes.append((material_name, combine.name))
                else:
                    emit.inputs['Color'].default_value = (1, rough, metal, 1) if channel == 'orm' else emission
                l.new(emit.outputs[0], n['Material Output'].inputs['Surface'])
            temporary.append((material_name, target.name, emit_name))
        scene.render.bake.margin = 8
        scene.render.bake.use_selected_to_active = False
        require('FINISHED' in bpy.ops.object.bake(type='NORMAL' if channel == 'normal' else 'EMIT'),
                'Bake failed: ' + image_name)
        object_named(joined_name, 'MESH')
        image = bpy.data.images[image_name]
        filename = atlas + '_' + channel + '.png'
        image.filepath_raw = str(out.parent / filename)
        image.file_format = 'PNG'
        image.save()
        require((out.parent / filename).is_file() and (out.parent / filename).stat().st_size > 0,
                'PNG save failed: ' + filename)
        image.pack()
        require(image.packed_file is not None, 'PNG packing failed: ' + filename)
        texture_files.append(filename)
        baked[channel] = image_name
        stage('saved and packed ' + filename)
        for material_name, target_name, emit_name in temporary:
            m = bpy.data.materials[material_name]
            n, l = m.node_tree.nodes, m.node_tree.links
            l.new(n['Principled BSDF'].outputs[0], n['Material Output'].inputs['Surface'])
            n.remove(n[target_name])
            if emit_name is not None:
                n.remove(n[emit_name])
        for material_name, node_name in temporary_nodes:
            nodes = bpy.data.materials[material_name].node_tree.nodes
            nodes.remove(nodes[node_name])
    stage('bind baked PBR ' + atlas)
    obj = object_named(joined_name, 'MESH')

    def pbr(name):
        m = bpy.data.materials.new(name)
        n, l = m.node_tree.nodes, m.node_tree.links
        p = n.get('Principled BSDF')
        require(p is not None, 'Default Principled BSDF missing: ' + name)
        for ch, image_name in baked.items():
            t = n.new('ShaderNodeTexImage'); t.image = bpy.data.images[image_name]
            if ch == 'albedo': l.new(t.outputs['Color'], p.inputs['Base Color'])
            if ch == 'emissive':
                l.new(t.outputs['Color'], p.inputs['Emission Color']); p.inputs['Emission Strength'].default_value = 1
            if ch == 'normal':
                normal = n.new('ShaderNodeNormalMap')
                l.new(t.outputs['Color'], normal.inputs['Color']); l.new(normal.outputs[0], p.inputs['Normal'])
            if ch == 'orm':
                sep = n.new('ShaderNodeSeparateColor'); l.new(t.outputs[0], sep.inputs[0])
                l.new(sep.outputs['Green'], p.inputs['Roughness']); l.new(sep.outputs['Blue'], p.inputs['Metallic'])
        return m

    obj.data.materials.clear(); obj.data.materials.append(pbr(atlas + ' baked PBR'))
    for polygon in obj.data.polygons: polygon.material_index = 0

stage('armature')
# Anatomical armature. Eye bones carry sclera/lid (vertical scale squints); brow and
# mouth-corner bones are rest-pose in every clip and driven only by the runtime face rig.
bpy.ops.object.select_all(action='DESELECT')
data=bpy.data.armatures.new('HoppyRig');rig=bpy.data.objects.new('HoppyRig',data);scene.collection.objects.link(rig)
rig_name = rig.name
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
def bone(name,head,tail,parent=None):
    data = object_named(rig_name, 'ARMATURE').data
    b=data.edit_bones.new(name);b.head=xyz(head);b.tail=xyz(tail)
    if parent:b.parent=data.edit_bones[parent]
bone('root',(0,0,0),(0,.15,0))
bone('hips',(0,.80,0),(0,.90,0),'root')
bone('spine',(0,.90,0),(0,1.04,0),'hips')
bone('chest',(0,1.04,0),(0,1.18,0),'spine')
bone('neck',(0,1.18,0),(0,1.25,0),'chest')
bone('head',(0,1.25,0),(0,1.45,0),'neck')
bone('tail',(0,.83,.08),(0,.83,.2),'hips')
for side,s in [('L',-1),('R',1)]:
    bone('ear_'+side,(s*.072,1.43,.015),(s*.072,1.60,.015),'head')
    bone('ear_tip_'+side,(s*.072,1.60,.015),(s*.072,1.80,.015),'ear_'+side)
    bone('eye_'+side,(s*.068,1.36,-.11),(s*.068,1.36,-.15),'head')
    # Face rig (round 7): the runtime drives brows and mouth corners; eye bones squint.
    bone('brow_'+side,(s*.07,1.405,-.10),(s*.07,1.405,-.14),'head')
    bone('mouth_'+side,(s*.03,1.268,-.17),(s*.03,1.268,-.21),'head')
    bone('shoulder_'+side,(s*.03,1.15,0),(s*.235,1.15,0),'chest')
    bone('arm_'+side,(s*.235,1.15,0),(s*.275,.90,-.012),'shoulder_'+side)
    bone('forearm_'+side,(s*.275,.90,-.012),(s*.284,.70,-.018),'arm_'+side)
    bone('hand_'+side,(s*.284,.70,-.018),(s*.286,.58,-.02),'forearm_'+side)
    bone('leg_'+side,(s*.10,.80,0),(s*.105,.44,-.01),'hips')
    bone('shin_'+side,(s*.105,.44,-.01),(s*.11,.10,0),'leg_'+side)
    bone('foot_'+side,(s*.11,.10,0),(s*.11,.06,-.2),'shin_'+side)
# Cape chain hangs from the upper back; like the legs these are downward bones.
bone('cape',(0,1.17,.12),(0,.90,.2),'chest')
bone('cape_tip',(0,.90,.2),(0,.50,.3),'cape')
bpy.ops.object.mode_set(mode='OBJECT')
rig = object_named(rig_name, 'ARMATURE')
require(len(rig.data.bones) == 33, 'Unexpected rig bone count')
stage('skin weights')
for mesh_name in mesh_names:
    obj = object_named(mesh_name, 'MESH')
    # Blend ear tips across a continuous leaf mesh instead of disconnected segments.
    for side in ('L','R'):
        base=obj.vertex_groups.get('ear_'+side)
        if base:
            tip=obj.vertex_groups.new(name='ear_tip_'+side)
            base=obj.vertex_groups['ear_'+side]
            for v in obj.data.vertices:
                if any(g.group==base.index for g in v.groups):
                    w=max(0,min(1,(v.co.z-1.56)/.16))
                    base.add([v.index],1-w,'REPLACE');tip.add([v.index],w,'REPLACE')
    mod=obj.modifiers.new('Hoppy skin','ARMATURE');mod.object=rig;obj.parent=rig
# Names/indices survive evaluation; never retain evaluated mesh references.
foot_vertices = {}
for mesh_name in mesh_names:
    obj = object_named(mesh_name, 'MESH')
    groups = {obj.vertex_groups[n].index for n in ('foot_L','foot_R') if n in obj.vertex_groups}
    foot_vertices[mesh_name] = [v.index for v in obj.data.vertices
                               if any(g.group in groups and g.weight > .99 for g in v.groups)]


def sole_low():
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    low = float('inf')
    for mesh_name, indices in foot_vertices.items():
        if not indices: continue
        evaluated = object_named(mesh_name, 'MESH').evaluated_get(deps)
        mesh = evaluated.to_mesh()
        try:
            low = min(low, min((evaluated.matrix_world @ mesh.vertices[i].co).z for i in indices))
        finally:
            evaluated.to_mesh_clear()
        del mesh, evaluated
    require(math.isfinite(low), 'No weighted shoe vertices for grounding')
    return low


def foot_pitch(side, pitch):
    # Solve in the parent space so a contact sole keeps its authored world pitch.
    bpy.context.view_layer.update()
    rig = object_named(rig_name, 'ARMATURE')
    foot = rig.pose.bones['foot_'+side]
    parent = foot.parent
    pre = parent.matrix @ parent.bone.matrix_local.inverted() @ foot.bone.matrix_local
    from mathutils import Matrix
    desired = Matrix.Rotation(pitch, 3, 'X') @ foot.bone.matrix_local.to_3x3()
    foot.rotation_euler = (pre.to_3x3().normalized().inverted() @ desired).to_euler('XYZ')

rig.animation_data_create()
lengths={'idle':48,'run':18,'jump':15,'fall':24,'roll':24,'hurt':18,'dead':36,
         'lane_dash_left':8,'lane_dash_right':8,'land':6,'shield_brace':12,'powerup_react':15,'victory':36}
# Round-7 one-shots reuse the run gait over (start phase, phase span). Each window keeps the
# push-off leg (opposite the dash) in stance; the runtime resumes run at the exit phase
# (sidecar run_exit: 0 = run frame 0, .5 = frame 9), so the return never pops a stride.
RUN_GAIT={'lane_dash_left':(0.0,math.pi),'lane_dash_right':(math.pi,math.pi),'land':(0.0,0.0),
          'shield_brace':(2*math.pi/3,4*math.pi/3),'powerup_react':(math.pi/3,5*math.pi/3),
          'victory':(0.0,4*math.pi)}
GROUNDED=('idle','run')+tuple(RUN_GAIT)


# Athletic sprint (recipe 11): forward lean, hip/shoulder counter-twist with a stabilised head.
RUN_LEAN=-.22
RUN_STRIDE=.78
RUN_ARM_SWING=.8
VICTORY_ARM_RAISE=2.9
VICTORY_EAR_BACK=.3
VICTORY_EAR_SPLAY=1.3
# Roll = full-scale baseball slide. Radians; flexion is relative to the reclined torso
# (+X hip = thigh toward the body front). The builder seats every frame on the floor and
# requires the whole skinned pose to stay under SLIDE_CEILING (roll hurtbox is 0.9 m).
SLIDE_LEAN=1.4
SLIDE_BOB=.025
SLIDE_LEAD='L'
SLIDE_LEAD_HIP=.42
SLIDE_LEAD_KNEE=.08
SLIDE_TRAIL_HIP=.95
SLIDE_TRAIL_KNEE=1.75
SLIDE_TRAIL_SPLAY=.35
SLIDE_ARM_START=0
SLIDE_ARM_BACK=-.25
SLIDE_ARM_SPLAY=2.0
SLIDE_ELBOW=.8
SLIDE_EAR_BACK=1.25
SLIDE_EAR_TIP=.3
SLIDE_SPINE=-.05
SLIDE_CHEST=0
SLIDE_NECK=-.1
SLIDE_HEAD=-.25
SLIDE_FLOOR=.004
SLIDE_CEILING=.885


def skin_extent():
    """(min z, max z, min y, max y) of every evaluated skinned vertex, Blender metres."""
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    lo = hi = back = front = None
    for mesh_name in mesh_names:
        evaluated = object_named(mesh_name, 'MESH').evaluated_get(deps)
        mesh = evaluated.to_mesh()
        try:
            flat = [0.0] * (3 * len(mesh.vertices)); mesh.vertices.foreach_get('co', flat)
            m = evaluated.matrix_world
            points = [m @ Vector(flat[i:i+3]) for i in range(0, len(flat), 3)]
        finally:
            evaluated.to_mesh_clear()
        del mesh, evaluated
        zs = [p.z for p in points]; ys = [p.y for p in points]
        lo = min(zs) if lo is None else min(lo, min(zs)); hi = max(zs) if hi is None else max(hi, max(zs))
        back = min(ys) if back is None else min(back, min(ys)); front = max(ys) if front is None else max(front, max(ys))
    return lo, hi, back, front


def smooth(a, b, x):
    u = max(0.0, min(1.0, (x - a) / (b - a)))
    return u * u * (3 - 2 * u)


def envelope(name, t):
    # Overlay weight: zero at both ends of blendable clips; land starts fully squashed.
    if name.startswith('lane_dash'): return math.sin(math.pi * t)
    if name == 'land': return 1 - smooth(0, 1, t)
    if name == 'shield_brace': return smooth(0, .2, t) * (1 - smooth(.65, 1, t))
    if name == 'powerup_react': return smooth(0, .18, t) * (1 - smooth(.7, 1, t))
    if name == 'victory': return smooth(0, .15, t) * (1 - smooth(.78, 1, t))
    return 0.0


def lerp(a, b, w):
    return a + (b - a) * w
for name,duration in lengths.items():
    stage('action ' + name)
    action=bpy.data.actions.new(name);rig.animation_data.action=action
    for step in range(duration * ACTION_SAMPLE_RATE + 1):
        f = step / ACTION_SAMPLE_RATE
        scene.frame_set(math.floor(f), subframe=f % 1)
        t=f/duration;phase=t*math.tau
        gait=name;e=envelope(name,t)
        if name in RUN_GAIT:
            gait='run';phase=RUN_GAIT[name][0]+RUN_GAIT[name][1]*t
        for p in rig.pose.bones:
            p.rotation_mode='XYZ';p.location=(0,0,0);p.rotation_euler=(0,0,0);p.scale=(1,1,1)
        root=rig.pose.bones['root']
        if name=='idle':rig.pose.bones['chest'].scale=(1+.009*math.sin(phase),1+.012*math.sin(phase),1)
        if gait=='run':
            # The lean breathes with each footfall; hips swing with the legs, the shoulders counter
            # them with the arms, and neck/head undo the twist and lift the chin so the eyes stay on
            # the lane. Every term is a run-phase function, so one-shots still end on a run pose.
            pose=rig.pose.bones
            pose['spine'].rotation_euler.x=RUN_LEAN+.035*math.sin(phase*2)
            pose['chest'].rotation_euler.z=.075*math.sin(phase)*(1-e if name.startswith('lane_dash') else 1)
            pose['hips'].rotation_euler.y=.10*math.cos(phase)
            pose['chest'].rotation_euler.y=-.22*math.cos(phase)
            pose['neck'].rotation_euler.x=.12;pose['neck'].rotation_euler.y=.06*math.cos(phase)
            pose['head'].rotation_euler.y=.06*math.cos(phase);pose['head'].rotation_euler.x=.04*math.sin(phase*2)
            pose['tail'].rotation_euler.x=.25*math.sin(phase*2)
            root.location.z=.025*(1-math.cos(phase*2));root.scale=(1.012,1-.02*math.cos(phase*2),1.012)
        if name=='jump':root.scale=(1-.07*math.sin(math.pi*t),1+.06*math.sin(math.pi*t),1-.07*math.sin(math.pi*t))
        if name=='hurt':root.location.y=-.14*math.sin(math.pi*t);root.rotation_euler.x=-.22*math.sin(math.pi*t)
        if name=='dead':root.rotation_euler.x=-min(1,t*1.6)*math.pi/2;root.location.z=.22*min(1,t*1.6)
        # Body overlays run before the limbs so foot_pitch sees the final parent chain.
        # Bone conventions (probed): +X tips an upward bone back, a downward bone forward;
        # +Z tips an upward bone's top toward -x and swings a downward bone's end toward -x.
        spine=rig.pose.bones['spine'];chest=rig.pose.bones['chest'];head=rig.pose.bones['head']
        dash=(1 if name.endswith('right') else -1) if name.startswith('lane_dash') else 0
        if dash:
            # Art review r1: the lean must read from the rear chase camera (head >= 8 px off the
            # centreline at 1280x720); chest roll stays inside the 0.12..0.35 rad A1 band.
            root.rotation_euler.z=-dash*.19*e
            spine.rotation_euler.z=-dash*.1*e
            chest.rotation_euler.y+=dash*.1*e
            head.rotation_euler.z+=dash*.1*e
        if name=='land':
            root.scale=(root.scale[0]+.05*e,root.scale[1]-.09*e,root.scale[2]+.05*e)
            spine.rotation_euler.x+=-.2*e;head.rotation_euler.x+=.1*e
        if name=='shield_brace':
            spine.rotation_euler.x+=.22*e;head.rotation_euler.x+=-.15*e
            root.location.y=-.05*e
        if name=='powerup_react':
            spine.rotation_euler.x+=.08*e;head.rotation_euler.x+=.1*e
        if name=='victory':
            spine.rotation_euler.x+=.14*e;head.rotation_euler.x+=.22*e
            chest.scale=(1+.03*e,1+.02*e,1+.03*e)
        # Cape secondary motion. Downward bones: -X swings the hem back, away from the body;
        # +Z swings it toward -x. Gait one-shots add overlays scaled by their envelope only, so
        # each still ends on its run exit pose; the slide keeps the cape flat against the back.
        cape=rig.pose.bones['cape'];cape_tip=rig.pose.bones['cape_tip']
        flare=.06+.02*math.sin(phase);flutter=.03*math.sin(phase+1)
        if gait=='run':
            flare=.46+.1*math.sin(phase*2);flutter=.24+.2*math.sin(phase*2+1.2)
            cape.rotation_euler.z=.07*math.sin(phase)
        if name=='jump':flare=.3+.35*t;flutter=.2+.1*t
        if name=='fall':flare=.85+.05*math.sin(phase*2);flutter=.3+.1*math.sin(phase*2+.6)
        if name=='hurt':flare=.2+.25*math.sin(math.pi*t);flutter=.15
        if name=='dead':flare=.08;flutter=.04
        if name=='roll':flare=-.15;flutter=-.25  # Pinned under the reclined back, inside the tail.
        if name=='land':flare=lerp(flare,.7,e);flutter=lerp(flutter,.3,e)
        if name=='victory':flare+=.25*e;flutter+=.1*e*math.sin(6*math.pi*t)
        if name=='powerup_react':flare+=.15*e
        if name=='shield_brace':flare-=.15*e
        cape.rotation_euler.x=-flare;cape_tip.rotation_euler.x=-flutter
        if dash:cape.rotation_euler.z+=dash*.15*e
        if name=='roll':
            # Curl the reclined torso forward so the face keeps looking down the lane.
            spine.rotation_euler.x=SLIDE_SPINE;chest.rotation_euler.x=SLIDE_CHEST
            rig.pose.bones['neck'].rotation_euler.x=SLIDE_NECK
            head.rotation_euler.x=SLIDE_HEAD+.03*math.sin(phase*2+.8)
        for side,s in [('L',-1),('R',1)]:
            arm=rig.pose.bones['arm_'+side];leg=rig.pose.bones['leg_'+side]
            ear=rig.pose.bones['ear_'+side]
            ear_tip=rig.pose.bones['ear_tip_'+side]
            ear_tip.rotation_euler.x=.07*math.sin(phase+.4)
            forearm=rig.pose.bones['forearm_'+side];shin=rig.pose.bones['shin_'+side]
            # Positive flexion uses +X at elbows, -X at knees: no backwards knee.
            elbow=.35;knee=.45
            if name=='idle':
                ear.rotation_euler.z=s*.04*math.sin(phase)
                elbow=.32+.04*math.sin(phase);knee=.20+.02*math.sin(phase)
                leg.rotation_euler.x=knee*.5
            if gait=='run':
                leg.rotation_euler.x=s*RUN_STRIDE*math.cos(phase)
                # Arms pump hard and are carried slightly forward, like a sprinter's.
                arm.rotation_euler.x=-s*RUN_ARM_SWING*math.cos(phase)+.12
                elbow=1.2+.4*math.cos(phase)**2
                # Recovery peaks at frame 4.5 (L) / 13.5 (R); other leg supports.
                knee=.22+1.4*max(0,-s*math.sin(phase))**2
                # Smooth contact absorption at 0/pi. The recovery curve above
                # stays intact; this short overlay also smooths the handoff.
                contact_distance=abs((phase+math.pi/2) % math.pi-math.pi/2)
                if contact_distance < math.pi/6:
                    knee += .09*(1+math.cos(6*contact_distance))
                # Ears stream back and splay a little; the tips lag the bounce.
                ear.rotation_euler.x=.34+.12*math.sin(phase*2);ear.rotation_euler.z=-s*.08
                ear_tip.rotation_euler.x=.2+.12*math.sin(phase*2-.7)
            if name in ('jump','fall'):
                arm.rotation_euler.x=-.8;leg.rotation_euler.x=.4;ear.rotation_euler.x=.18
                elbow=.75;knee=.55
            if name=='jump':
                elbow=.95+.2*math.sin(math.pi*t);knee=1.2+.25*math.sin(math.pi*t)
                # Avoid cancelling the knee bend: heel folds backward/up, not vertically down.
                leg.rotation_euler.x=-.15
            if name=='jump':
                ear.rotation_euler.x=.2+.48*math.sin(math.pi*t)
                rig.pose.bones['ear_tip_'+side].rotation_euler.x=-.25*math.sin(math.pi*t)
            if name=='roll':
                # Baseball-style low slide (root pitched back by SLIDE_LEAN below): the lead
                # leg (L) reaches straight down the lane with its heel skimming the floor, the
                # trail leg folds under it, the arms sweep back for balance and the ears stream
                # flat behind. Flexion is relative to the reclined torso.
                lead=side==SLIDE_LEAD
                settle=smooth(0,.4,t)
                leg.rotation_euler.x=SLIDE_LEAD_HIP if lead else SLIDE_TRAIL_HIP
                knee=SLIDE_LEAD_KNEE if lead else SLIDE_TRAIL_KNEE
                if not lead:leg.rotation_euler.z=-s*SLIDE_TRAIL_SPLAY
                arm.rotation_euler.x=lerp(SLIDE_ARM_START,SLIDE_ARM_BACK,settle)+.05*math.sin(phase+s)
                elbow=SLIDE_ELBOW
                ear.rotation_euler.x=SLIDE_EAR_BACK+.06*math.sin(phase*2+.5)
                ear.rotation_euler.z=-s*.12
                ear_tip.rotation_euler.x=SLIDE_EAR_TIP+.08*math.sin(phase*2+1.2)
            if name=='hurt':
                elbow=1.1 if t <= 1/3 else .4+.7*(1-t)*1.5
                knee=.45
            if name=='dead':elbow=.4;knee=.45
            pump=math.sin(8*math.pi*t)
            if dash and s==-dash:knee*=1-.5*e  # Push-off leg extends.
            if name=='land':
                arm.rotation_euler.x=lerp(arm.rotation_euler.x,-.45,e);elbow=lerp(elbow,.8,e)
                leg.rotation_euler.x=lerp(leg.rotation_euler.x,.28,e);knee+=.6*e
                ear.rotation_euler.x=lerp(ear.rotation_euler.x,-.35,e);ear_tip.rotation_euler.x+=.35*e
            if name=='shield_brace':
                arm.rotation_euler.x=lerp(arm.rotation_euler.x,1.25,e);elbow=lerp(elbow,1.6,e)
                knee+=.3*e;ear.rotation_euler.x+=.9*e
            if name=='powerup_react':
                if side=='R':
                    arm.rotation_euler.x=lerp(arm.rotation_euler.x,.3,e);elbow=lerp(elbow,1.55+.12*pump,e)
                ear_tip.rotation_euler.x+=.6*e*math.sin(6*math.pi*t)
                ear.rotation_euler.z+=s*.12*e*math.sin(4*math.pi*t)
            if name=='victory':
                # Art review r1: from the rear chase camera both paws must clear the ear tips,
                # so the arms punch almost straight up and the ears sweep back and splay.
                arm.rotation_euler.x*=1-e;elbow=lerp(elbow,.22+.2*(1+pump)/2,e)
                ear.rotation_euler.x=lerp(ear.rotation_euler.x,VICTORY_EAR_BACK,e)
                ear.rotation_euler.z-=s*VICTORY_EAR_SPLAY*e
                ear_tip.rotation_euler.x+=(.35+.15*math.sin(6*math.pi*t))*e
            # Clamp signed bends; arm abduction gives the large paws torso clearance.
            forearm.rotation_euler.x=max(.0,min(1.75,elbow))
            shin.rotation_euler.x=-max(.0,min(1.9,knee))
            arm.rotation_euler.z=-s*.18
            if gait=='run':arm.rotation_euler.z-=s*.06
            if dash:
                arm.rotation_euler.z+=(-s*.45 if s==dash else s*.12)*e
                leg.rotation_euler.z=-s*(.08 if s==dash else .22)*e
                ear.rotation_euler.z+=dash*.3*e
            if name=='roll':arm.rotation_euler.z-=s*SLIDE_ARM_SPLAY
            if name=='shield_brace':arm.rotation_euler.z+=s*.28*e
            if name=='powerup_react' and side=='R':arm.rotation_euler.z-=(2.6+.15*pump)*e
            if name=='victory':arm.rotation_euler.z-=s*(VICTORY_ARM_RAISE+.1*pump)*e
            if gait in ('idle','run'):
                foot_pitch(side, -.3*max(0,(knee-.3)/1.32))
            elif name=='jump':foot_pitch(side,-.65)
            elif name=='fall':foot_pitch(side,-.35)
        if name=='roll':
            # Full-scale slide: no shrink, no spin. The whole body reclines about the feet and
            # is then re-seated on the floor below; a gentle bob rides on the lean.
            root.rotation_euler.x=SLIDE_LEAN+SLIDE_BOB*math.sin(phase*2)
        # Pose locations are bone-local; root's local Y points along world Z.
        root.location = rig.data.bones['root'].matrix_local.to_3x3().inverted() @ root.location
        if name=='roll':
            # Seat the evaluated skin on the floor (lowest vertex at SLIDE_FLOOR) and centre its
            # lane-axis extent on the origin; rotation is fixed, so one rigid shift is exact.
            lo,hi,back,front=skin_extent()
            shift=Vector((0,-(back+front)/2,SLIDE_FLOOR-lo))
            root.location += rig.data.bones['root'].matrix_local.to_3x3().inverted() @ shift
            lo,hi,back,front=skin_extent()
            require(abs(lo-SLIDE_FLOOR)<.0005 and hi<=SLIDE_CEILING,
                    'Slide envelope frame %s: y %.4f..%.4f' % (f,lo,hi))
        if name in GROUNDED:
            # Lower/raise the body by the evaluated lowest sole, including squash.
            bpy.context.view_layer.update()
            correction=Vector((0,0,-sole_low()))
            root.location += rig.data.bones['root'].matrix_local.to_3x3().inverted() @ correction
            require(abs(sole_low()) < .0005, 'Grounding failed '+name+' frame '+str(f))
        for p in rig.pose.bones:
            for prop in ('location','rotation_euler','scale'):p.keyframe_insert(prop,frame=f,group=p.name)
    # Dense linear keys avoid Bezier overshoot through the anatomical limits.
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    if name in GROUNDED:
        # Re-evaluate the completed action, rather than trust incremental authoring.
        # This also samples every time used by the 25-frame Godot guard.
        stage('final-curve sole grounding '+name+' at 120 Hz')
        for step in range(duration * ACTION_SAMPLE_RATE + 1):
            f = step / ACTION_SAMPLE_RATE
            scene.frame_set(math.floor(f), subframe=f % 1)
            low = sole_low()
            root = object_named(rig_name, 'ARMATURE').pose.bones['root']
            root.location += root.bone.matrix_local.to_3x3().inverted() @ Vector((0,0,-low))
            root.keyframe_insert('location', frame=f, group='root')
            scene.frame_set(math.floor(f), subframe=f % 1)
            require(abs(sole_low()) < .0005, 'Final-curve grounding failed '+name+' frame '+str(f))
        lows=[]
        for sample in range(25):
            f=duration*sample/24
            scene.frame_set(math.floor(f), subframe=f % 1)
            lows.append(sole_low())
        # idle/run keep the strict round-16 band; the short one-shots change support foot
        # between 120 Hz keys, so they use the exported 120 Hz sweep band [-.002, .007].
        band = (-.001, .001) if name in ('idle','run') else (-.002, .007)
        require(min(lows) >= band[0] and max(lows) <= band[1], 'Contact samples failed '+name+': '+str(lows))
        stage('contact samples '+name+' min/max='+str((min(lows),max(lows))))
    require(len(action.slots) == 1, 'Expected one armature action slot: ' + name)
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new();track.name=name
    strip=track.strips.new(name,0,action);strip.action_frame_start=0;strip.action_frame_end=duration
    strip.action_slot = action.slots[0]
    track.mute=True
    action['loop']=name in ('idle','run','fall')

# The glTF exporter force-samples integer scene frames. Retiming to 120 fps
# retains quarter-frame contact corrections while keeping every clip length.
stage('retime dense actions for 120 Hz glTF sampling')
for action_name in lengths:
    action=bpy.data.actions[action_name]
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.co.x *= ACTION_SAMPLE_RATE
                        key.handle_left.x *= ACTION_SAMPLE_RATE
                        key.handle_right.x *= ACTION_SAMPLE_RATE
                        key.interpolation='LINEAR'
                    curve.update()
for track in rig.animation_data.nla_tracks:
    for strip in track.strips:
        strip.action_frame_end=lengths[track.name]*ACTION_SAMPLE_RATE
        strip.frame_end=lengths[track.name]*ACTION_SAMPLE_RATE
scene.render.fps=30*ACTION_SAMPLE_RATE

# Verify the final retimed curves at every exported key, without changing poses.
# Godot must import at the same 120 Hz with optimizer/enabled=false; otherwise
# its default 30 Hz bake/key reduction discards these sole corrections.
sole_sweeps = {}
for action_name in GROUNDED:
    stage('verify final 120 Hz sole sweep '+action_name)
    rig = object_named(rig_name, 'ARMATURE')
    action = bpy.data.actions[action_name]
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    lows = []
    for frame in range(lengths[action_name]*ACTION_SAMPLE_RATE+1):
        scene.frame_set(frame)
        lows.append(sole_low())
    minimum, maximum = min(lows), max(lows)
    require(minimum >= -.002 and maximum <= .007,
            '120 Hz sole sweep outside [-.002,.007]: '+action_name+' '+str((minimum,maximum)))
    sole_sweeps[action_name] = {'hz':scene.render.fps, 'samples':len(lows),
                               'min_y':minimum, 'max_y':maximum}
    print('[hoppy] SOLE SWEEP %s: 120 Hz min_y=%.6f max_y=%.6f samples=%d' %
          (action_name, minimum, maximum, len(lows)), flush=True)
rig.animation_data.action = None

# Evaluate actual deformed vertices across the roll action, independent of exporter.
stage('validate sampled roll bounds')
rig = object_named(rig_name, 'ARMATURE')
rig.animation_data.action=bpy.data.actions['roll']
rig.animation_data.action_slot=bpy.data.actions['roll'].slots[0]
lo=1e9;hi=-1e9
for f in range(lengths['roll']*ACTION_SAMPLE_RATE+1):
    scene.frame_set(f);deps=bpy.context.evaluated_depsgraph_get()
    for mesh_name in mesh_names:
        evaluated=object_named(mesh_name, 'MESH').evaluated_get(deps)
        mesh=evaluated.to_mesh()
        try:
            require(mesh is not None and len(mesh.vertices) > 0, 'Empty evaluated mesh: ' + mesh_name)
            zs=[(evaluated.matrix_world@v.co).z for v in mesh.vertices]
            lo=min(lo,min(zs));hi=max(hi,max(zs))
        finally:
            evaluated.to_mesh_clear()
        del mesh, evaluated
require(lo>=-.001 and hi<=SLIDE_CEILING, 'Slide bounds outside 0..%.3f m: %s' % (SLIDE_CEILING, (lo,hi)))
stage('roll bounds y=' + str((lo,hi)))
rig = object_named(rig_name, 'ARMATURE')
rig.animation_data.action=None
for p in rig.pose.bones:p.location=(0,0,0);p.rotation_euler=(0,0,0);p.scale=(1,1,1)
scene.frame_set(0)
triangles=sum(sum(len(p.vertices)-2 for p in obj.data.polygons) for obj in (object_named(name, 'MESH') for name in mesh_names))
require(triangles<=TRIANGLE_CAP, 'Triangle budget exceeded: ' + str(triangles))
stage('export GLB; triangles=' + str(triangles))
script_hash=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
helper_hash=hashlib.sha256(Path(__file__).with_name('glb_atlas.py').read_bytes()).hexdigest()
rig['build_script_sha256']=script_hash;rig['generator']='tools/blender/build_hoppy.py'
bpy.ops.object.select_all(action='DESELECT')
for name in mesh_names + [rig_name]: object_named(name).select_set(True)
bpy.context.view_layer.objects.active=object_named(rig_name, 'ARMATURE')
export_result = bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,
    export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,
    export_force_sampling=True,export_extras=True,export_yup=True,export_image_format='AUTO',
    export_vertex_color='NAME',export_vertex_color_name='led_mask')
require('FINISHED' in export_result, 'glTF exporter did not finish')
require(out.is_file() and out.stat().st_size > 20, 'Missing or empty GLB')
object_named(rig_name, 'ARMATURE')
stage('verify exported GLB and write metadata')
# Embed reproducibility metadata into the GLB asset header, retaining binary chunks.
raw=out.read_bytes();chunks=[];pos=12
magic, version, total = struct.unpack_from('<III', raw, 0)
require(magic == 0x46546c67 and version == 2 and total == len(raw), 'Invalid GLB header')
while pos<len(raw):
    require(pos + 8 <= len(raw), 'Truncated GLB chunk header')
    length,kind=struct.unpack_from('<II',raw,pos)
    require(pos + 8 + length <= len(raw), 'Truncated GLB chunk')
    chunks.append((kind,raw[pos+8:pos+8+length]));pos+=8+length
require(bool(chunks) and chunks[0][0] == 0x4e4f534a, 'Missing GLB JSON chunk')
payload=json.loads(chunks[0][1])
binary = next((data for kind, data in chunks if kind == 0x004e4942), b'')
print('[hoppy] images before sharing: ' + json.dumps(inspect_images(payload, binary)), flush=True)
print('[hoppy] textures before sharing: ' + json.dumps(payload.get('textures', [])), flush=True)
image_report = consolidate_atlases(payload, binary)
print('[hoppy] images after sharing: ' + json.dumps(image_report), flush=True)
print('[hoppy] textures after sharing: ' + json.dumps(payload.get('textures', [])), flush=True)
require(len(image_report) <= 8, 'Image budget exceeded: ' + str(len(image_report)))
for info in image_report:
    cap = 2048 if info['name'].startswith('body_') else 1024
    require(info['width'] <= cap and info['height'] <= cap, 'Image dimensions exceed cap: ' + str(info))
exported_actions = [a.get('name') for a in payload.get('animations', [])]
require(len(exported_actions) == len(lengths) and set(exported_actions) == set(lengths),
        'Exported animation names differ: ' + str(exported_actions))
require(bool(payload.get('skins')), 'Export contains no skin')
led_primitives = sum('COLOR_0' in primitive['attributes'] for mesh in payload.get('meshes', []) for primitive in mesh['primitives'])
require(led_primitives >= 1, 'Cape LED mask (COLOR_0) missing from export')
exported_triangles = 0
for mesh in payload.get('meshes', []):
    for primitive in mesh.get('primitives', []):
        require(primitive.get('mode', 4) == 4, 'Non-triangle primitive in GLB')
        accessor = (primitive['indices'] if 'indices' in primitive else primitive['attributes']['POSITION'])
        count = payload['accessors'][accessor]['count']
        require(count % 3 == 0, 'Invalid triangle index count')
        exported_triangles += count // 3
require(0 < exported_triangles and exported_triangles + EFFECT_TRIANGLES <= TRIANGLE_CAP, 'Exported whole-visual triangle budget exceeded: ' + str(exported_triangles + EFFECT_TRIANGLES))
triangles = exported_triangles
exported_texture_count = len(payload.get('textures', []))
require(exported_texture_count == 0 if opts.quick else 0 < exported_texture_count <= 8,
        'Unexpected exported texture count: ' + str(exported_texture_count))
payload['asset']['extras']={'build_script_sha256':script_hash,'atlas_helper_sha256':helper_hash,'seed':SEED,'generator':'tools/blender/build_hoppy.py'}
encoded=json.dumps(payload,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);chunks[0]=(chunks[0][0],encoded)
body=b''.join(struct.pack('<II',len(data),kind)+data for kind,data in chunks)
out.write_bytes(struct.pack('<III',0x46546c67,2,len(body)+12)+body)
textures=sorted(texture_files)
report={'recipe_revision':RECIPE_REVISION,'orange_linear':ORANGE_LINEAR,
        'stance_revision':17,'effect_triangles':EFFECT_TRIANGLES,
        'joint_revision':JOINT_REVISION,'contact_revision':CONTACT_REVISION,'sole_sweeps':sole_sweeps,'animation_sample_rate':scene.render.fps,'joint_bend_signs':{'forearm':1,'shin':-1},
        'sole_radii':SOLE_RADII,'cape_bones':['cape','cape_tip'],
        'script_sha256':script_hash,'atlas_helper_sha256':helper_hash,'blender':bpy.app.version_string,'seed':SEED,'triangles':triangles,
        'image_report':image_report,'textures':textures,'exported_texture_count':exported_texture_count,'quick':opts.quick,'animations':list(lengths),'bones':[b.name for b in object_named(rig_name, 'ARMATURE').data.bones],
        'roll_bounds_y':[lo,hi],'triangle_cap':TRIANGLE_CAP,'led_segments':4,'led_primitives':led_primitives,
        'face_bones':['eye_L','eye_R','brow_L','brow_R','mouth_L','mouth_R'],
        'grounded_clips':list(GROUNDED),'clip_frames':lengths,
        'run_exit':{k:round(((a+b)/math.tau) % 1.0, 6) for k,(a,b) in RUN_GAIT.items()},'height':1.8,'forward':[0,0,-1],'generator':payload['asset']['generator']}
(out.parent/'hoppy.build.json').write_text(json.dumps(report,indent=2)+'\n')
print('HOPPY BUILD: '+json.dumps(report,sort_keys=True))
print('[hoppy] EXPORT OK tris=%d textures=%d actions=%s file=%s bytes=%d' %
      (triangles, exported_texture_count, ','.join(exported_actions), out, out.stat().st_size), flush=True)
