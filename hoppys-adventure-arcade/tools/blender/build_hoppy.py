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
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glb_atlas import consolidate_atlases, inspect_images

SEED = 41027
RECIPE_REVISION = 7
JOINT_REVISION = 15
CONTACT_REVISION = 17
BUDGET = json.loads(Path(__file__).with_name("hoppy_budget.json").read_text())
EFFECT_TRIANGLES = int(BUDGET["effect_triangles"])
TRIANGLE_CAP = int(BUDGET["triangle_cap"])
assert EFFECT_TRIANGLES > 0 and TRIANGLE_CAP <= 48000
ACTION_SAMPLE_RATE = 4  # 120 Hz export, unchanged durations in seconds.
HOODIE_LINEAR = (0.930, 0.250, 0.067)
# Tips face inward; cusp faces outward: left { and right }.
BRACE_PROFILE = ((.020, .934), (.043, .922), (.044, .890), (.061, .876),
                 (.044, .862), (.043, .832), (.020, .821))
SOLE_RADII = (.108, .162)  # Shoe radii (.100, .154) plus 8 mm.
assert BRACE_PROFILE[3][0] > max(BRACE_PROFILE[0][0], BRACE_PROFILE[-1][0])
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


def surface_detail(kind, n, l, tex, ramp):
    """(height, bump strength, bump distance, AO socket or None, albedo socket or None).
    Object coordinates are Blender metres (X right, Y = -Godot Z, Z up) because every
    atlas object is joined and transform-applied at the origin before baking."""
    if kind not in ('fur', 'cloth', 'thread', 'tread'):
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
        # Chevron sole tread centred on each shoe (|x| = .131), 11 mm pitch.
        offset = node_math(n, l, 'ABSOLUTE', node_math(n, l, 'SUBTRACT', ax, .131))
        chevron = node_math(n, l, 'ADD', Y, node_math(n, l, 'MULTIPLY', offset, .9))
        pitch = node_math(n, l, 'FRACT', node_math(n, l, 'MULTIPLY', chevron, 90.))
        lug = node_band(n, l, pitch, .38, .5)
        groove = node_math(n, l, 'SUBTRACT', 1., lug)
        ao = node_math(n, l, 'SUBTRACT', 1., node_math(n, l, 'MULTIPLY', groove, .35))
        return lug, .9, .0018, ao, None
    # Hoodie: side/shoulder seam (Godot z=.012), centre-back seam, raglan seams.
    side = node_math(n, l, 'ABSOLUTE', node_math(n, l, 'ADD', Y, .012))
    front = node_math(n, l, 'GREATER_THAN', Y, -.04)
    back = node_math(n, l, 'ADD', ax, node_math(n, l, 'MULTIPLY', front, 10.))
    raglan_x = node_math(n, l, 'ADD', node_math(n, l, 'MULTIPLY', node_math(n, l, 'SUBTRACT', 1.07, Z), .64), .12)
    raglan = node_math(n, l, 'ABSOLUTE', node_math(n, l, 'SUBTRACT', ax, raglan_x))
    outside = node_math(n, l, 'ADD', node_math(n, l, 'LESS_THAN', Z, .92), node_math(n, l, 'GREATER_THAN', Z, 1.075))
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
    thread.inputs[2].default_value = (1.0, .56, .30, 1)  # Lighter orange topstitch, same hue family.
    l.new(node_math(n, l, 'MULTIPLY', stitch, .5), thread.inputs[0]); l.new(ramp.outputs[0], thread.inputs[1])
    return height, .7, .0007, ao, thread.outputs[0]


def material(name, color, kind='cloth', metallic=0.0, glow=0.0):
    m = bpy.data.materials.new(name)
    n, l = m.node_tree.nodes, m.node_tree.links
    p = n.get('Principled BSDF')
    require(p is not None, 'Default Principled BSDF missing: ' + name)
    if opts.quick:
        p.inputs['Base Color'].default_value = tuple(color) + (1,)
        p.inputs['Metallic'].default_value = metallic
        p.inputs['Roughness'].default_value = .84 if kind in ('fur', 'cloth') else .32
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
    height.inputs[0].default_value = .22 if kind == 'cloth' else 0
    l.new(mix.outputs[0], height.inputs[1]); l.new(folds.outputs['Color'], height.inputs[2])
    # A geometry attribute puts a faint baked crease at elbow/knee rings only.
    joint = n.new('ShaderNodeAttribute'); joint.attribute_name = 'joint_crease'
    crease_height = n.new('ShaderNodeMath'); crease_height.operation = 'ADD'
    l.new(height.outputs[0], crease_height.inputs[0]); l.new(joint.outputs['Fac'], crease_height.inputs[1])
    l.new(crease_height.outputs[0], bump.inputs['Height'])
    p.inputs['Roughness'].default_value = .84 if kind in ('fur', 'cloth') else .32
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Emission Color'].default_value = tuple(color) + (1,)
    p.inputs['Emission Strength'].default_value = glow
    # Round-7 detail: a second bump layer in real object-space millimetres, plus an
    # optional baked-occlusion term for grooves (ORM red; the rest of the atlas stays 1).
    detail = surface_detail(kind, n, l, tex, ramp)
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

cream = material('Cream microfur', (.88, .79, .61), 'fur')
orange = material('CodeRabbit orange woven shell', HOODIE_LINEAR)
inner = material('Warm inner ear', (.94, .43, .23), 'fur')
slate = material('Graphite equipment', (.025, .043, .065), 'metal', .65)
mint = material('Mint edge details', (.22, .85, .61), 'rubber', .15, .8)
matrix = material('Matrix screens only', (.06, .8, .23), 'screen', .05, 1.1)
white = material('Warm eye whites', (.98, .94, .83), 'eye')
black = material('Ink pupils', (.003, .007, .012), 'eye')
glass = material('Mint glass', (.21, .65, .49), 'glass', .15, .08)
glass.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value = .22
glass.surface_render_method = 'DITHERED'
# Same palette as the mint accents; only their baked normal/occlusion detail differs.
thread = material('Mint embroidery thread', (.22, .85, .61), 'thread', .15, .8)
tread = material('Mint tread rubber', (.22, .85, .61), 'tread', .15, .8)
if not opts.quick:
    nodes, links = inner.node_tree.nodes, inner.node_tree.links
    separate = nodes.new('ShaderNodeSeparateXYZ')
    links.new(nodes['Texture Coordinate'].outputs['Generated'], separate.inputs[0])
    gradient = nodes.new('ShaderNodeValToRGB')
    gradient.color_ramp.elements[0].color = (.95, .19, .025, 1)
    gradient.color_ramp.elements[1].color = (.88, .79, .61, 1)
    ear_range = nodes.new('ShaderNodeMapRange')
    ear_range.inputs['From Min'].default_value = .67
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


def ellipsoid(name, at, size, mat, bone, atlas='body', segments=24, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=xyz(at))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    # Sculpted asymmetric face and tapered leaf-shaped ears, with quad latitude loops.
    if 'Skull' in name:
        for v in obj.data.vertices:
            v.co.x *= 1 + .12 * (1 - v.co.z) * max(0, v.co.y)
    if 'Tail' in name:
        for v in obj.data.vertices:
            v.co *= 1 + .055 * math.sin(v.co.x * 11) * math.sin(v.co.z * 9)
    if 'Ear' in name:
        for v in obj.data.vertices:
            v.co.x *= .78 + .22 * (1 - v.co.z * v.co.z)
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

def loft(name, rows, mat, bone, sides=12, atlas='body', crease=0.0, ribs=0, rib=0.0):
    """Continuous quad rings with Catmull-Clark subdivision; joint cores fill bends.
    Rows: (centre_x, height_y, centre_z, radius_x, radius_z). ribs/rib add knit ribbing.
    """
    vertices, faces = [], []
    for row_index, (cx, y, cz, rx, rz) in enumerate(rows):
        for j in range(sides):
            a = j * math.tau / sides
            fold = 1 + crease * math.sin(row_index * 2.3 + a * 3)
            if ribs:
                fold *= 1 + rib * math.cos(a * ribs)
            vertices.append(xyz((cx + rx * math.cos(a) * fold, y, cz + rz * math.sin(a) * fold)))
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


def shoe_top(dx, z):
    # Height of the 'Runner shoe' upper ellipsoid (centre y .099, radii .1/.074/.154) at (dx, z).
    return .099 + .074 * math.sqrt(max(0.0, 1 - (dx / .1) ** 2 - ((z + .061) / .154) ** 2))


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
# Main sculpt: broad face, haunches, tapered runner torso, glove-like paws.
ellipsoid('Skull sculpt', (0, 1.255, -.025), (.257, .25, .223), cream, 'head', segments=32, rings=24)
loft('Hoodie tailored torso', [(0,y,z,rx,rz) for y,z,rx,rz in [
    (.51,.015,.17,.125),(.53,.015,.21,.16),(.56,.015,.22,.172),(.60,.015,.222,.172),
    (.69,.01,.235,.18),(.80,0,.237,.183),(.92,0,.226,.171),
    (1.015,0,.24,.135),(1.055,0,.19,.1),(1.075,0,.115,.075)]], orange, 'spine', sides=20, crease=.025)
loft('Ribbed hem band', [(0,y,.015,.223,.172) for y in (.525,.53,.565,.57)], slate, 'hips', sides=48, ribs=24, rib=.035)
# Deep folded hood shell around the neck, open at its upper edge.
loft('Sculpted hood shell', [(0,y,z,rx,rz) for y,z,rx,rz in [
    (.99,.18,.15,.10),(1.015,.18,.21,.17),(1.09,.17,.249,.20),
    (1.18,.16,.241,.20),(1.195,.15,.225,.18),(1.18,.15,.201,.15),
    (1.08,.16,.18,.12),(1.04,.17,.10,.045)]], orange, 'chest', sides=20, crease=.035)
tube('Hood mint seam', [(math.cos(a)*.225,1.188,.15+math.sin(a)*.18) for a in [i*math.tau/32 for i in range(33)]], .005, mint, 'chest', detail=1)

box('Kangaroo pocket', (0, .705, -.181), (.295, .145, .045), orange, 'spine', 'body')
tube('Pocket stitched welt', [(-.14,.76,-.206),(-.13,.655,-.206),(0,.644,-.208),(.13,.655,-.206),(.14,.76,-.206)], .003, cream, 'spine')
box('Embossed logo backing', (0,.878,-.191), (.151,.144,.026), slate,'spine')
# Embroidered patch: satin-stitch border around the { } badge (thread normal detail).
tube('Patch satin border', [(math.copysign(.071*abs(math.cos(a))**.35, math.cos(a)), .878+math.copysign(.067*abs(math.sin(a))**.35, math.sin(a)), -.205)
     for a in [i*math.tau/28 for i in range(29)]], .0045, thread, 'spine', detail=1)
box('Short collar placket', (0,1.002,-.137), (.024,.108,.018), slate,'chest')
box('Zip pull', (0,.966,-.152), (.033,.039,.015), mint,'chest')
ellipsoid('Tail tuft', (0, .65, .242), (.096, .106, .095), cream, 'tail')
# Fuller cotton tail: five overlapping lobes and outward wisps around the core tuft.
for i, (dx, dy, dz) in enumerate([(-.05,.045,.03),(.05,.045,.03),(-.052,-.04,.025),(.052,-.04,.025),(0,.0,.075)]):
    ellipsoid('Tail lobe %d' % i, (dx, .65+dy, .242+dz), (.058, .062, .056), cream, 'tail', segments=12, rings=8)
for i in range(6):
    a = i * math.tau / 6 + .3
    tuft('Tail wisp %d' % i, (math.cos(a)*.055, .65+math.sin(a)*.06, .29),
         (math.cos(a)*.09, .65+math.sin(a)*.095, .315), (math.cos(a)*.108, .65+math.sin(a)*.112, .305), .026, cream, 'tail')
for side, sign in [('L', -1), ('R', 1)]:
    x = sign
    ellipsoid('Cheek ' + side, (x*.107, 1.167, -.218), (.113, .082, .073), cream, 'head')
    ellipsoid('Ear ' + side, (x*.12, 1.574, .005), (.069, .226, .051), cream, 'ear_'+side)
    ellipsoid('Inner Ear ' + side, (x*.12, 1.586, -.042), (.039, .171, .012), inner, 'ear_'+side)
    # Round 7: sclera and lid line ride the eye bone, whose vertical scale squints/widens the eye.
    ellipsoid('Sclera '+side, (x*.105, 1.296, -.221), (.09, .101, .043), white, 'eye_'+side, 'accessory')
    ellipsoid('Iris '+side, (x*.1, 1.291, -.256), (.049, .06, .017), mint, 'eye_'+side, 'accessory')
    ellipsoid('Pupil '+side, (x*.1, 1.291, -.268), (.027, .039, .01), black, 'eye_'+side, 'accessory')
    ellipsoid('Catchlight '+side, (x*.1-.012, 1.31, -.276), (.008, .011, .004), white, 'eye_'+side, 'accessory', 12, 8)
    tube('Brow '+side, [(x*.044,1.402,-.206),(x*.10,1.419,-.22),(x*.166,1.397,-.199)], .014, slate, 'brow_'+side, detail=1)
    tube('Upper eyelid '+side, [(x*.105-.085,1.304,-.23),(x*.105,1.388,-.239),(x*.105+.085,1.304,-.23)], .009, cream,'eye_'+side)
    # Cheek fluff and ear-rim tufts: short tapered wisps, fur-direction baked like the body.
    for j, (by, tx, ty, tz) in enumerate([(1.15,.262,1.105,-.19),(1.175,.268,1.15,-.175),(1.128,.24,1.078,-.214)]):
        tuft('Cheek tuft %s %d' % (side, j), (x*.19, by, -.2), (x*(tx-.03), (by+ty)/2-.005, (tz-.2)/2), (x*tx, ty, tz), .02, cream, 'head')
    for j, (by, bz) in enumerate([(1.43,.01),(1.49,.004),(1.55,.0)]):
        tuft('Ear rim tuft %s %d' % (side, j), (x*.176, by, bz), (x*.192, by+.014, bz+.01), (x*.204, by+.032, bz+.016), .017, cream, 'ear_'+side)
    tuft('Inner ear tuft '+side, (x*.12, 1.40, -.03), (x*.125, 1.425, -.055), (x*.13, 1.455, -.066), .018, cream, 'ear_'+side)
    # Forehead goggles connect through side hinges to the wraparound strap.
    box('Goggle hinge '+side,(x*.23,1.415,-.123),(.041,.038,.042),slate,'head')
    tube('Goggle temple '+side,[(x*.206,1.422,-.169),(x*.244,1.415,-.10),(x*.248,1.4,-.015)],.01,slate,'head')
    points = [(x*.113+math.cos(a)*.094, 1.423+math.sin(a)*.064, -.169) for a in [i*math.tau/16 for i in range(17)]]
    tube('Goggle frame '+side, points, .012, slate, 'head')
    ellipsoid('Goggle lens '+side, (x*.113,1.423,-.171), (.081,.051,.009), glass, 'head', 'accessory')
    sleeve = loft('Continuous sleeve '+side, [(x*cx,y,z,rx,rz) for cx,y,z,rx,rz in [
        (.244,1.032,.012,.067,.066),(.257,1.015,.012,.084,.085),(.276,.95,.01,.083,.082),
        (.292,.85,0,.078,.077),(.30,.795,-.008,.077,.077),
        (.30,.78,-.008,.0792,.0792),(.301,.765,-.013,.077,.078),(.302,.75,-.019,.073,.075),
        (.30,.67,-.025,.066,.068),(.30,.606,-.029,.061,.061)]], orange,'arm_'+side,crease=.045)
    blend_joint(sleeve,'arm_'+side,'forearm_'+side,.78,.055)
    joint_crease(sleeve,.78)
    joint_core(side,'Elbow',(x*.3,.78,0),.075,orange,'arm_'+side,'forearm_'+side)
    loft('Cuff '+side,[(x*.3,y,-.029,.066,.066) for y in (.59,.594,.63,.634)],slate,'forearm_'+side,sides=32,ribs=16,rib=.06)
    tube('Sleeve piping '+side,[(x*.30,.97,-.064),(x*.327,.9,-.062),(x*.353,.83,-.025)],.004,mint,'arm_'+side)
    tube('Forearm piping '+side,[(x*.357,.77,-.025),(x*.358,.7,-.04),(x*.348,.633,-.05)],.004,mint,'forearm_'+side)
    ellipsoid('Palm '+side,(x*.3,.555,-.031),(.074,.065,.065),cream,'hand_'+side,segments=20,rings=12)
    ellipsoid('Thumb '+side,(x*.243,.55,-.069),(.028,.042,.031),cream,'hand_'+side,segments=16,rings=10)
    for finger in range(3):
        ellipsoid('Finger %s %d'%(side,finger),(x*(.264+finger*.033),.512,-.045),(.021,.043,.032),cream,'hand_'+side,segments=12,rings=10)
    leg = loft('Continuous leg '+side,[(x*cx,y,z,rx,rz) for cx,y,z,rx,rz in [
        (.126,.54,.015,.075,.085),(.126,.515,.015,.097,.104),(.128,.44,.01,.096,.1),
        (.129,.35,0,.078,.079),(.129,.335,-.004,.079,.08),
        (.129,.32,-.008,.0803,.0825),(.129,.31,-.012,.077,.079),(.13,.25,-.007,.072,.073),
        (.131,.16,0,.061,.064),(.131,.115,0,.058,.062)]],cream,'leg_'+side,crease=.012)
    leg_obj = object_named(leg, 'MESH')
    leg_obj.data.materials.append(slate)
    for polygon in leg_obj.data.polygons:
        if sum(leg_obj.data.vertices[i].co.z for i in polygon.vertices) / len(polygon.vertices) > .39:
            polygon.material_index = 1
    blend_joint(leg,'leg_'+side,'shin_'+side,.32,.05)
    joint_crease(leg,.32)
    joint_core(side,'Knee',(x*.129,.32,0),.079,cream,'leg_'+side,'shin_'+side)
    loft('Shoe sole '+side, [(x*.131,y,-.064,SOLE_RADII[0],SOLE_RADII[1])
         for y in (0.0,.006,.052,.058)], tread, 'foot_'+side, sides=16, atlas='accessory')
    ellipsoid('Runner shoe '+side, (x*.131,.099,-.061), (.1,.074,.154), slate, 'foot_'+side, 'accessory')
    ellipsoid('Sneaker toe cap '+side,(x*.131,.091,-.159),(.094,.054,.064),slate,'foot_'+side,'accessory',20,12)
    tube('Sole emissive piping '+side,[(x*.131+math.cos(a)*.096,.05,-.064+math.sin(a)*.154) for a in [j*math.tau/24 for j in range(25)]],.004,mint,'foot_'+side,detail=1)
    box('Shoe heel tab '+side, (x*.131,.153,.056), (.056,.061,.024), orange, 'foot_'+side)
    for i in range(3):
        # Round 7: laces and eyelets sit on the sneaker upper instead of inside it.
        lz, mz = -.055-i*.027, -.07-i*.027
        tube('Lace %s %d'%(side,i), [(x*.131-.047,shoe_top(.047,lz)+.003,lz),(x*.131,shoe_top(0,mz)+.004,mz),(x*.131+.047,shoe_top(.047,lz)+.003,lz)], .005, cream, 'foot_'+side)
        for end in (-1, 1):
            ellipsoid('Eyelet %s %d %d'%(side,i,end+1), (x*.131+end*.049,shoe_top(.049,lz)+.002,lz), (.011,.007,.011), mint, 'foot_'+side, 'accessory', 8, 6)
    # Bow on the top lace: two loops and two short tails.
    knot = (x*.131, shoe_top(0,-.07)+.006, -.07)
    for end in (-1, 1):
        tube('Lace loop %s %d'%(side,end+1), [knot,(knot[0]+end*.022,knot[1]+.022,knot[2]+.004),(knot[0]+end*.042,knot[1]+.012,knot[2]+.006),
             (knot[0]+end*.03,knot[1]-.002,knot[2]-.006),knot], .004, cream, 'foot_'+side, detail=1)
        tube('Lace tail %s %d'%(side,end+1), [knot,(knot[0]+end*.014,knot[1]-.006,knot[2]-.018),(knot[0]+end*.02,knot[1]-.016,knot[2]-.034)], .0035, cream, 'foot_'+side, detail=1)
    tube('Drawcord '+side, [(x*.067,1.052,-.156),(x*.071,.959,-.19),(x*.087,.87,-.204)], .008, cream, 'chest')
    box('Aglet '+side, (x*.087,.861,-.204), (.02,.039,.022), mint, 'chest')
    for j in range(3):
        tube('Whisker %s %d'%(side,j), [(x*.157,1.165-j*.012,-.251),(x*.235,1.176-j*.024,-.257),(x*.305,1.192-j*.035,-.235)], .002, cream, 'head')
    # Braces are original curve geometry, not a system font asset.
    for rear in (False, True):
        z = .268 if rear else -.211  # Pack face ends at z=.2555.
        points = [(x*gx, .815+(gy-.876)*.65 if rear else gy, z) for gx,gy in BRACE_PROFILE]
        tube(('Back' if rear else 'Chest')+' brace '+side, points, .006, mint if rear else thread, 'chest' if rear else 'spine')
    for j in range(10):
        tube('Hem stitch %s %d'%(side,j), [(x*(.025+j*.019),.555,-.141),(x*(.031+j*.019),.563,-.143)], .0018, cream, 'spine')
ellipsoid('Nose', (0,1.185,-.29), (.038,.025,.021), inner, 'head', 'accessory')
smile = tube('Muzzle smile', [(-.061,1.133,-.267),(0,1.122,-.281),(.061,1.133,-.267)], .003, slate, 'head')
blend_across(smile, 'head', 'mouth_L', 'mouth_R', .061)
tube('Goggle strap', [(math.sin(i*math.tau/24)*.253,1.4,math.cos(i*math.tau/24)*.179) for i in range(25)], .014, slate, 'head', detail=1)
box('Goggle bridge',(0,1.423,-.17),(.042,.017,.025),slate,'head')
# Strap buckle at the back of the head, plus two sliding keepers on the strap sides.
box('Goggle strap buckle',(0,1.4,.19),(.056,.04,.014),slate,'head')
box('Goggle buckle prong',(0,1.4,.198),(.036,.008,.005),mint,'head')
for side, sign in [('L', -1), ('R', 1)]:
    box('Goggle strap keeper '+side,(sign*.252,1.4,.035),(.012,.034,.042),mint,'head')
box('Slim battery pack',(0,.879,.209),(.249,.243,.093),slate,'chest')
for led in range(4):
    led_mask(box('Matrix battery LED '+str(led),(-.054+led*.036,.898,.26),(.021,.069,.009),matrix,'chest'), led, 4)
box('Wrist device',(-.3,.683,-.09),(.099,.086,.043),slate,'forearm_L')
box('Matrix wrist screen',(-.3,.689,-.114),(.07,.053,.006),matrix,'forearm_L')
box('Utility pouch',(.242,.659,.035),(.082,.142,.133),slate,'hips')
box('Pouch clasp',(.287,.687,.012),(.016,.033,.046),mint,'hips')
tube('Utility belt',[(math.sin(i*math.tau/24)*.231,.627,math.cos(i*math.tau/24)*.177) for i in range(25)],.016,slate,'hips',detail=1)

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
    glass_indices = {i for i, m in enumerate(obj.data.materials) if m.name == 'Mint glass'}

    def pbr(name, alpha=1):
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
        p.inputs['Alpha'].default_value = alpha
        if alpha < 1: m.surface_render_method = 'DITHERED'
        return m

    indices = [p.material_index in glass_indices for p in obj.data.polygons]
    obj.data.materials.clear(); obj.data.materials.append(pbr(atlas + ' baked PBR'))
    if glass_indices: obj.data.materials.append(pbr('Goggle alpha glass', .22))
    for polygon, isglass in zip(obj.data.polygons, indices): polygon.material_index = int(isglass)

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
bone('hips',(0,.57,0),(0,.72,0),'root')
bone('spine',(0,.72,0),(0,.92,0),'hips')
bone('chest',(0,.92,0),(0,1.06,0),'spine')
bone('neck',(0,1.06,0),(0,1.15,0),'chest')
bone('head',(0,1.15,0),(0,1.43,0),'neck')
bone('tail',(0,.65,.17),(0,.65,.32),'hips')
for side,s in [('L',-1),('R',1)]:
    bone('ear_'+side,(s*.12,1.38,0),(s*.12,1.59,0),'head')
    bone('ear_tip_'+side,(s*.12,1.59,0),(s*.12,1.8,0),'ear_'+side)
    bone('eye_'+side,(s*.1,1.291,-.24),(s*.1,1.291,-.28),'head')
    # Face rig (round 7): the runtime drives brows and mouth corners; eye bones squint.
    bone('brow_'+side,(s*.105,1.41,-.2),(s*.105,1.41,-.25),'head')
    bone('mouth_'+side,(s*.061,1.133,-.25),(s*.061,1.133,-.29),'head')
    bone('shoulder_'+side,(s*.04,1.02,0),(s*.25,1.02,0),'chest')
    bone('arm_'+side,(s*.25,1.02,0),(s*.3,.78,0),'shoulder_'+side)
    bone('forearm_'+side,(s*.3,.78,0),(s*.3,.6,-.03),'arm_'+side)
    bone('hand_'+side,(s*.3,.6,-.03),(s*.3,.5,-.03),'forearm_'+side)
    bone('leg_'+side,(s*.126,.55,0),(s*.129,.32,0),'hips')
    bone('shin_'+side,(s*.129,.32,0),(s*.131,.11,0),'leg_'+side)
    bone('foot_'+side,(s*.131,.11,0),(s*.131,.07,-.2),'shin_'+side)
bpy.ops.object.mode_set(mode='OBJECT')
rig = object_named(rig_name, 'ARMATURE')
require(len(rig.data.bones) == 31, 'Unexpected rig bone count')
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
                    w=max(0,min(1,(v.co.z-1.51)/.17))
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
            rig.pose.bones['spine'].rotation_euler.x=-.12
            rig.pose.bones['chest'].rotation_euler.z=.075*math.sin(phase)*(1-e if name.startswith('lane_dash') else 1)
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
            root.rotation_euler.z=-dash*.14*e
            spine.rotation_euler.z=-dash*.09*e
            chest.rotation_euler.y=dash*.1*e
            head.rotation_euler.z=dash*.1*e
        if name=='land':
            root.scale=(root.scale[0]+.05*e,root.scale[1]-.09*e,root.scale[2]+.05*e)
            spine.rotation_euler.x=-.12-.2*e;head.rotation_euler.x=.1*e
        if name=='shield_brace':
            spine.rotation_euler.x=-.12+.22*e;head.rotation_euler.x=-.15*e
            root.location.y=-.05*e
        if name=='powerup_react':
            spine.rotation_euler.x=-.12+.08*e;head.rotation_euler.x=.1*e
        if name=='victory':
            spine.rotation_euler.x=-.12+.14*e;head.rotation_euler.x=.15*e
            chest.scale=(1+.03*e,1+.02*e,1+.03*e)
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
                leg.rotation_euler.x=s*.65*math.cos(phase);arm.rotation_euler.x=-s*.62*math.cos(phase)
                elbow=1.2+.4*math.cos(phase)**2
                # Recovery peaks at frame 4.5 (L) / 13.5 (R); other leg supports.
                knee=.22+1.4*max(0,-s*math.sin(phase))**2
                # Smooth contact absorption at 0/pi. The recovery curve above
                # stays intact; this short overlay also smooths the handoff.
                contact_distance=abs((phase+math.pi/2) % math.pi-math.pi/2)
                if contact_distance < math.pi/6:
                    knee += .09*(1+math.cos(6*contact_distance))
                ear.rotation_euler.x=.16+.13*math.sin(phase*2)
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
                arm.rotation_euler.x=-1.0;leg.rotation_euler.x=1.25
                elbow=1.7;knee=1.85
                ear.rotation_euler.x=2.5;rig.pose.bones['ear_tip_'+side].rotation_euler.x=.45
                rig.pose.bones['head'].rotation_euler.x=.4
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
                arm.rotation_euler.x*=1-e;elbow=lerp(elbow,.55+.3*(1+pump)/2,e)
                ear.rotation_euler.x=lerp(ear.rotation_euler.x,-.05,e)
                ear_tip.rotation_euler.x+=.25*e*math.sin(6*math.pi*t)
            # Clamp signed bends; arm abduction gives the large paws torso clearance.
            forearm.rotation_euler.x=max(.0,min(1.75,elbow))
            shin.rotation_euler.x=-max(.0,min(1.9,knee))
            arm.rotation_euler.z=-s*.18
            if dash:
                arm.rotation_euler.z+=(-s*.45 if s==dash else s*.12)*e
                leg.rotation_euler.z=-s*(.08 if s==dash else .22)*e
                ear.rotation_euler.z+=dash*.3*e
            if name=='shield_brace':arm.rotation_euler.z+=s*.28*e
            if name=='powerup_react' and side=='R':arm.rotation_euler.z-=(2.6+.15*pump)*e
            if name=='victory':arm.rotation_euler.z-=s*(2.5+.2*pump)*e
            if gait in ('idle','run'):
                foot_pitch(side, -.3*max(0,(knee-.3)/1.32))
            elif name=='jump':foot_pitch(side,-.65)
            elif name=='fall':foot_pitch(side,-.35)
        if name=='roll':
            # Uniform scale and a centred spin keep the entire tuck inside 90 cm.
            root.scale=(.47,.47,.47);root.rotation_euler.x=-phase
            centre=Vector((0,0,.84));rot=root.rotation_euler.to_matrix()
            root.location=Vector((0,0,.45))-rot@(centre*.47)
        # Pose locations are bone-local; root's local Y points along world Z.
        root.location = rig.data.bones['root'].matrix_local.to_3x3().inverted() @ root.location
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
require(lo>=-.001 and hi<=.901, 'Roll bounds outside 0..0.9 m: ' + str((lo,hi)))
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
require(led_primitives >= 1, 'Backpack LED mask (COLOR_0) missing from export')
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
report={'recipe_revision':RECIPE_REVISION,'hoodie_linear':HOODIE_LINEAR,
        'stance_revision':17,'effect_triangles':EFFECT_TRIANGLES,
        'joint_revision':JOINT_REVISION,'contact_revision':CONTACT_REVISION,'sole_sweeps':sole_sweeps,'animation_sample_rate':scene.render.fps,'joint_bend_signs':{'forearm':1,'shin':-1},
        'brace_profile':BRACE_PROFILE,'sole_radii':SOLE_RADII,'back_mark_z':.268,
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
