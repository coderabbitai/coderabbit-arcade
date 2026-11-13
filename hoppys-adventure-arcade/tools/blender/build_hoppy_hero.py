"""Builds the runner's Hoppy from the artist's CodeRabbit hero rabbit, keeping every runner clip.

    Blender --background --factory-startup --python-exit-code 1 \
        --python tools/blender/build_hoppy_hero.py -- [--preview DIR]

Inputs (hoppys-adventure-arcade/):
  Assets/runner/hoppy_hero/source/rabbit_mesh.obj   handover neutral-pose mesh (cm, Y up, +Z forward)
  Assets/runner/hoppy_hero/source/<part>_*.png      prep_hoppy_hero_textures.py output
  Assets/runner/hoppy/hoppy.glb                      the procedural Hoppy: rig and the 13 runner clips
Output: Assets/runner/hoppy_hero/hoppy_hero.glb (+ hoppy_hero.build.json).

The handover mesh ships without a usable rig (its Maya rig cannot be exported here), so this script:
  1. scales the mesh to Hoppy's 1.8 m ear-tip height and turns it to face Blender +Y (Godot -Z);
  2. builds Hoppy's 33-bone skeleton (same names, hierarchy and bone rolls) on the new joints;
  3. skins each mesh part with bone-heat weights, limited to the bones that part may follow;
  4. retargets every clip from the procedural rig: each bone's local rotation is re-expressed in the
     new bone's rest frame, and root/hips travel scales with the shorter legs.
Brow and mouth-corner bones carry no geometry on this mesh; the eye bones carry the eyeballs, so the
runtime face rig still blinks and squints.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / 'Assets/runner/hoppy_hero/source'
CLIP_SOURCE = PROJECT / 'Assets/runner/hoppy/hoppy.glb'
OUT = PROJECT / 'Assets/runner/hoppy_hero/hoppy_hero.glb'
FPS = 120
HEIGHT = 1.8
TRIANGLE_CAP = 48000

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--preview', type=Path, help='also render front/side/run previews into this folder')
args = parser.parse_args(argv)


def require(ok, message):
    if not ok:
        raise RuntimeError('[hoppy_hero] ' + message)


def stage(message):
    print('[hoppy_hero] ' + message, flush=True)


# Joints in handover centimetres, already in the final frame: X right of the viewer (the rabbit's
# left is -X), Y forward, Z up. Measured from the neutral pose (front/side orthographic views and
# the per-part bounds). Each entry is (head, tail).
JOINTS = {
    'root': ((0, 0, 0), (0, 0, 25)),
    'hips': ((0, 0.5, 25), (0, 1, 27.5)),
    'leg_L': ((-4.7, 0.5, 25), (-4.9, 1.2, 15)),
    'shin_L': ((-4.9, 1.2, 15), (-5.0, 0.3, 5)),
    'foot_L': ((-5.0, 0.3, 5), (-5.0, 10, 1.2)),
    'spine': ((0, 1, 27.5), (0, 1.5, 33)),
    'chest': ((0, 1.5, 33), (0, 1.2, 38)),
    'cape': ((0, -4.5, 40), (0, -8.5, 26)),
    'cape_tip': ((0, -8.5, 26), (0, -13.5, 12)),
    'neck': ((0, 1, 39.5), (0, 1, 43)),
    'head': ((0, 1, 43), (0, 1, 56)),
    'brow_L': ((-5.5, 4, 58), (-5.5, 9, 58)),
    'ear_L': ((-6, -3.5, 62), (-10.5, -4, 70.5)),
    'ear_tip_L': ((-10.5, -4, 70.5), (-15.3, -6, 79)),
    'eye_L': ((-3.8, 2.3, 53.7), (-3.8, 7.3, 53.7)),
    'mouth_L': ((-2, 6, 46), (-2, 11, 46)),
    'shoulder_L': ((-2, 1, 38), (-9, 1, 38)),
    'arm_L': ((-9, 1, 38), (-14.5, 2, 32.5)),
    'forearm_L': ((-14.5, 2, 32.5), (-16, 5, 26.4)),
    'hand_L': ((-16, 5, 26.4), (-17, 8.5, 19.5)),
    'tail': ((0, -4, 25), (0, -7, 25)),
}
for name in [n for n in JOINTS if n.endswith('_L')]:
    (hx, hy, hz), (tx, ty, tz) = JOINTS[name]
    JOINTS[name[:-2] + '_R'] = ((-hx, hy, hz), (-tx, ty, tz))

# Mesh part (OBJ group) -> material and the bones its vertices may follow.
LEGS = ['hips', 'leg_L', 'shin_L', 'foot_L', 'leg_R', 'shin_R', 'foot_R']
ARMS = [b + s for s in ('_L', '_R') for b in ('shoulder', 'arm', 'forearm', 'hand')]
PARTS = {
    'Rabbit_head': ('head', ['neck', 'head', 'ear_L', 'ear_tip_L', 'ear_R', 'ear_tip_R']),
    'Upperteeth': ('head', ['head']),
    'Lowerteeth': ('head', ['head']),
    'Eye_Left': ('eyes', ['eye_L']),
    'Eye_Right': ('eyes', ['eye_R']),
    'Rabbit_body': ('body', LEGS + ['spine', 'chest', 'neck'] + ARMS),
    'Rabbit_Belt': ('body', ['hips', 'spine']),
    'Rabbit_Feet': ('body', ['foot_L', 'foot_R']),
    'Rabbit_ShinArmor': ('body', ['shin_L', 'shin_R']),
    'Rabbit_ShoulderPads': ('body', ['chest', 'shoulder_L', 'arm_L', 'shoulder_R', 'arm_R']),
    'Rabbit_WristArmor': ('body', ['forearm_L', 'hand_L', 'forearm_R', 'hand_R']),
    'Rabbit_Hands': ('body', ['forearm_L', 'hand_L', 'forearm_R', 'hand_R']),
    'Rabbit_Cape': ('body', ['chest', 'cape', 'cape_tip']),
}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
# glTF import converts seconds to frames at the scene rate: 120 Hz keeps every source key on a frame.
scene.render.fps = FPS

stage('import clip source ' + CLIP_SOURCE.name)
bpy.ops.import_scene.gltf(filepath=str(CLIP_SOURCE))
source = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for obj in [o for o in bpy.data.objects if o.type != 'ARMATURE']:
    bpy.data.objects.remove(obj)
source.name = 'HoppySource'
require(source.matrix_world == Matrix.Identity(4), 'source rig must sit at the origin')
source_rest = {b.name: b.matrix_local.copy() for b in source.data.bones}
source_parent = {b.name: (b.parent.name if b.parent else None) for b in source.data.bones}
require(set(source_rest) == set(JOINTS), 'joint table must cover the source rig: %s' % (set(source_rest) ^ set(JOINTS)))
clips = sorted(a.name for a in bpy.data.actions)
require(len(clips) == 13, 'expected 13 runner clips, found %s' % clips)
for action in list(bpy.data.actions):
    action.name = 'source_' + action.name

stage('import handover mesh')
bpy.ops.wm.obj_import(filepath=str(SOURCE / 'rabbit_mesh.obj'), use_split_groups=True)
parts = {}
for obj in [o for o in scene.objects if o.type == 'MESH']:
    key = next((p for p in PARTS if p in obj.name.split()), None)
    require(key is not None and key not in parts, 'unexpected OBJ group ' + obj.name)
    parts[key] = obj
require(set(parts) == set(PARTS), 'missing OBJ groups: %s' % (set(PARTS) - set(parts)))
low = min((o.matrix_world @ v.co).z for o in parts.values() for v in o.data.vertices)
high = max((o.matrix_world @ v.co).z for o in parts.values() for v in o.data.vertices)
cm_to_m = HEIGHT / (high - low)
# The OBJ importer turns Y-up/+Z-forward into Blender -Y forward; a half turn faces +Y like Hoppy.
place = Matrix.Scale(cm_to_m, 4) @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation((0, 0, -low))
for obj in parts.values():
    obj.data.transform(place @ obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    obj.data.update()
stage('scale %.5f m/cm, height %.3f m' % (cm_to_m, HEIGHT))


def joint(point):
    return Vector(point) * cm_to_m


stage('build rig on the new joints')
data = bpy.data.armatures.new('HoppyRig')
rig = bpy.data.objects.new('HoppyRig', data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
for name in source_rest:  # source order keeps parents first
    head, tail = JOINTS[name]
    bone = data.edit_bones.new(name)
    bone.head, bone.tail = joint(head), joint(tail)
    # Same roll as the source bone, as near as the new direction allows, so local bend axes match.
    bone.align_roll(source_rest[name].col[2].xyz)
for name, parent in source_parent.items():
    if parent:
        data.edit_bones[name].parent = data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
target_rest = {b.name: b.matrix_local.copy() for b in data.bones}
for bone in rig.pose.bones:
    bone.rotation_mode = 'QUATERNION'

stage('materials')


def pbr(part, name=None):
    material = bpy.data.materials.new('hero ' + (name or part))
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes.get('Principled BSDF')
    albedo = nodes.new('ShaderNodeTexImage')
    albedo.image = bpy.data.images.load(str(SOURCE / (part + '_albedo.png')), check_existing=True)
    links.new(albedo.outputs['Color'], shader.inputs['Base Color'])
    orm = nodes.new('ShaderNodeTexImage')
    orm.image = bpy.data.images.load(str(SOURCE / (part + '_orm.png')), check_existing=True)
    orm.image.colorspace_settings.name = 'Non-Color'
    split = nodes.new('ShaderNodeSeparateColor')
    links.new(orm.outputs['Color'], split.inputs['Color'])
    links.new(split.outputs['Green'], shader.inputs['Roughness'])
    links.new(split.outputs['Blue'], shader.inputs['Metallic'])
    normal_path = SOURCE / (part + '_normal.png')
    if normal_path.exists():
        normal = nodes.new('ShaderNodeTexImage')
        normal.image = bpy.data.images.load(str(normal_path), check_existing=True)
        normal.image.colorspace_settings.name = 'Non-Color'
        bump = nodes.new('ShaderNodeNormalMap')
        links.new(normal.outputs['Color'], bump.inputs['Color'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    return material


materials = {part: pbr(part) for part in ('body', 'head', 'eyes')}
# The cape is its own surface: only it carries the runtime LED mask (hoppy_runner_visual.gd flags
# every material whose surface has COLOR_0, and a surface without one would read as all LED).
materials['cape'] = pbr('body', 'cape')
for key, obj in parts.items():
    obj.data.materials.clear()
    obj.data.materials.append(materials['cape' if key == 'Rabbit_Cape' else PARTS[key][0]])
    for polygon in obj.data.polygons:
        polygon.material_index = 0

stage('skin each part')


def nearest_weights(obj, bones):
    """Fallback for a part bone heat cannot solve: inverse-distance to each allowed bone segment."""
    for name in bones:
        obj.vertex_groups.new(name=name)
    for vertex in obj.data.vertices:
        scores = []
        for name in bones:
            bone = data.bones[name]
            a, b = bone.head_local, bone.tail_local
            t = max(0.0, min(1.0, (vertex.co - a).dot(b - a) / max((b - a).length_squared, 1e-9)))
            scores.append((max((vertex.co - (a + (b - a) * t)).length, 1e-4) ** -4, name))
        scores.sort(reverse=True)
        total = sum(s for s, _ in scores[:2])
        for score, name in scores[:2]:
            obj.vertex_groups[name].add([vertex.index], score / total, 'REPLACE')


for key, obj in parts.items():
    bones = PARTS[key][1]
    if len(bones) == 1:
        obj.vertex_groups.new(name=bones[0]).add([v.index for v in obj.data.vertices], 1.0, 'REPLACE')
        continue
    for bone in data.bones:
        bone.use_deform = bone.name in bones
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    unweighted = [v for v in obj.data.vertices if not any(g.weight > 1e-4 for g in v.groups)]
    if len(unweighted) > len(obj.data.vertices) * 0.02:
        stage('bone heat left %d/%d vertices of %s unweighted: nearest-bone weights' %
              (len(unweighted), len(obj.data.vertices), key))
        obj.vertex_groups.clear()
        nearest_weights(obj, bones)
    elif unweighted:
        for vertex in unweighted:  # a few stray vertices: take the closest weighted neighbour's weights
            near = min((v for v in obj.data.vertices if v.groups and any(g.weight > 1e-4 for g in v.groups)),
                       key=lambda v: (v.co - vertex.co).length_squared)
            for group in near.groups:
                obj.vertex_groups[group.group].add([vertex.index], group.weight, 'REPLACE')
for bone in data.bones:
    bone.use_deform = True

# Hand-tuned cloth and ear weights. Bone heat pins too much of the cape to the chest and bends the
# ears at a hard crease; these gradients let the runtime spring rig (hifi/sway_rig.gd) swing the
# cape from the collar down and whip the ear tips. Heights and distances are handover centimetres.
stage('hand-tune cape and ear weights')


def smooth(edge0, edge1, value):
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def set_weights(obj, vertex, weights):
    for group in obj.vertex_groups:
        group.remove([vertex.index])
    for name, weight in weights.items():
        if weight > 1e-4:
            (obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)).add([vertex.index], weight, 'REPLACE')


CAPE_COLLAR = (41.0, 34.0)   # chest above, cape below
CAPE_FOLD = (30.0, 18.0)     # cape above, cape_tip below (wide, so the cloth curves)
cape_part = parts['Rabbit_Cape']
for vertex in cape_part.data.vertices:
    height = vertex.co.z / cm_to_m
    hang = smooth(CAPE_COLLAR[0], CAPE_COLLAR[1], height)
    tip = smooth(CAPE_FOLD[0], CAPE_FOLD[1], height)
    set_weights(cape_part, vertex, {'chest': 1.0 - hang, 'cape': hang * (1.0 - tip), 'cape_tip': hang * tip})

EAR_FLOOR = 60.0             # head-part vertices above this height belong to an ear
EAR_ROOT = (-1.5, 2.5)       # distance along the ear from its joint: head before, ear after
EAR_FOLD = (6.0, 13.0)       # ear before, ear_tip after (the joint sits at 9.6)
head_part = parts['Rabbit_head']
ear_vertices = 0
for vertex in head_part.data.vertices:
    if vertex.co.z / cm_to_m < EAR_FLOOR:
        continue
    side = '_L' if vertex.co.x < 0 else '_R'
    root, joint_end = (joint(p) for p in JOINTS['ear' + side])
    along = (vertex.co - root).dot((joint_end - root).normalized()) / cm_to_m
    lift = smooth(EAR_ROOT[0], EAR_ROOT[1], along)
    tip = smooth(EAR_FOLD[0], EAR_FOLD[1], along)
    set_weights(head_part, vertex, {'head': 1.0 - lift, 'ear' + side: lift * (1.0 - tip),
                                    'ear_tip' + side: lift * tip})
    ear_vertices += 1
require(ear_vertices > 40, 'ear vertices not found')

stage('join parts')
bpy.ops.object.select_all(action='DESELECT')
for obj in parts.values():
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    obj.parent = None
    obj.select_set(obj is not parts['Rabbit_Cape'])
body = parts['Rabbit_body']
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = body.data.name = 'Hoppy_hero'
cape = parts['Rabbit_Cape']
cape.name = cape.data.name = 'Hoppy_hero_cape'
meshes = [body, cape]
for obj in meshes:
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    obj.parent = rig
    modifier = obj.modifiers.new('Armature', 'ARMATURE')
    modifier.object = rig
    for vertex in obj.data.vertices:
        require(any(g.weight > 1e-4 for g in vertex.groups), 'unweighted vertex %d on %s' % (vertex.index, obj.name))

# Runtime LED meter (COLOR_0: R = LED, G = segment 0..1): a band across the cape above its tattered
# hem, in four segments from the rabbit's left to its right. Unlit it shows the plain cape.
LED_BAND = (0.16, 0.30)
LED_SEGMENTS = 4
zs = [v.co.z for v in cape.data.vertices]
xs = [v.co.x for v in cape.data.vertices]
bottom, top, left, right = min(zs), max(zs), min(xs), max(xs)
mask = cape.data.color_attributes.new('led_mask', 'FLOAT_COLOR', 'POINT')
led_vertices = 0
for vertex in cape.data.vertices:
    height = (vertex.co.z - bottom) / (top - bottom)
    lit = LED_BAND[0] <= height <= LED_BAND[1]
    segment = min(int((vertex.co.x - left) / (right - left) * LED_SEGMENTS), LED_SEGMENTS - 1)
    mask.data[vertex.index].color = (1.0 if lit else 0.0, segment / (LED_SEGMENTS - 1), 0.0, 1.0)
    led_vertices += lit
require(led_vertices > 0, 'empty LED band')
stage('cape LED band: %d vertices' % led_vertices)
triangles = sum(len(p.vertices) - 2 for obj in meshes for p in obj.data.polygons)
require(triangles <= TRIANGLE_CAP, 'triangle budget exceeded: %d' % triangles)

stage('retarget %d clips' % len(clips))
# Leg length ratio: root and hips travel (bob, crouch, slide) scales with it, so soles stay planted.
travel = target_rest['hips'].translation.z / source_rest['hips'].translation.z
change = {}
for name in source_rest:
    # Basis change from the source bone's rest frame to the new one: a local rotation q in the source
    # frame is the same armature-space motion as c^-1 q c in the new frame.
    c = (source_rest[name].to_3x3().normalized().inverted() @ target_rest[name].to_3x3().normalized())
    change[name] = c.to_quaternion()


def channelbag_curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def curves_by_channel(action):
    curves = {}
    for curve in channelbag_curves(action):
        require(curve.data_path.startswith('pose.bones["'), 'unexpected channel ' + curve.data_path)
        bone, prop = curve.data_path[len('pose.bones["'):].split('"].')
        curves.setdefault((bone, prop), {})[curve.array_index] = curve
    return curves


# The new head is far bigger than Hoppy's: arms raised beside Hoppy's head (victory, the run's
# fist pump) would put these hands over the face. An ellipsoid around the head (metres, chest
# frame) is kept clear by swinging the upper arm outward about the forward axis.
HEAD_CENTER = joint((0, 1.5, 52))
HEAD_RADII = Vector((0.30, 0.32, 0.27))
MAX_SWING = math.radians(80)
# The splayed ears already start 25 degrees out; Hoppy's full ear flops would lay them flat.
EAR_DAMP = 0.45
source_rot = {name: m.to_quaternion() for name, m in source_rest.items()}
target_rot = {name: m.to_quaternion() for name, m in target_rest.items()}


def inside_head(point):
    d = point - HEAD_CENTER
    return (d.x / HEAD_RADII.x) ** 2 + (d.y / HEAD_RADII.y) ** 2 + (d.z / HEAD_RADII.z) ** 2 < 1.0


def arm_swing(source_curves, side, frame):
    """Outward swing (radians, signed) that keeps this side's elbow, wrist and hand out of the head."""
    def delta(bone):
        axes = source_curves.get((bone, 'rotation_quaternion'))
        q = Quaternion([axes[i].evaluate(frame) for i in range(4)]) if axes else Quaternion()
        return source_rot[bone] @ q @ source_rot[bone].inverted()
    shoulder = delta('shoulder' + side)
    arm = shoulder @ delta('arm' + side)
    forearm = arm @ delta('forearm' + side)
    hand = forearm @ delta('hand' + side)
    bones = {n: data.bones[n + side] for n in ('shoulder', 'arm', 'forearm', 'hand')}
    pivot = bones['shoulder'].head_local + shoulder @ (bones['arm'].head_local - bones['shoulder'].head_local)
    elbow = arm @ (bones['forearm'].head_local - bones['arm'].head_local)
    wrist = elbow + forearm @ (bones['hand'].head_local - bones['forearm'].head_local)
    tip = wrist + hand @ (bones['hand'].tail_local - bones['hand'].head_local)
    sign = -1.0 if side == '_L' else 1.0
    steps = 32
    for step in range(steps + 1):
        angle = sign * MAX_SWING * step / steps
        swing = Quaternion((0, 1, 0), angle)
        points = [elbow, (elbow + wrist) / 2, wrist, (wrist + tip) / 2, tip]
        if not any(inside_head(pivot + swing @ p) for p in points):
            return angle, shoulder
    return sign * MAX_SWING, shoulder


lengths = {}
swings = {}
for clip in clips:
    source_curves = curves_by_channel(bpy.data.actions['source_' + clip])
    action = bpy.data.actions['source_' + clip].copy()
    action.name = clip
    curves = curves_by_channel(action)
    end = 0.0
    for (bone, prop), axes in curves.items():
        c = change[bone]
        if prop == 'rotation_quaternion':
            require(len(axes) == 4, 'partial quaternion on ' + bone)
            count = len(axes[0].keyframe_points)
            require(all(len(axes[i].keyframe_points) == count for i in range(4)), 'ragged quaternion keys ' + bone)
            for k in range(count):
                q = Quaternion([axes[i].keyframe_points[k].co.y for i in range(4)])
                r = c.inverted() @ q @ c
                if bone.startswith('ear'):
                    r = Quaternion().slerp(r, EAR_DAMP)
                elif bone in ('arm_L', 'arm_R'):
                    angle, shoulder = arm_swing(source_curves, bone[-2:], axes[0].keyframe_points[k].co.x)
                    if angle:
                        swings[clip] = max(swings.get(clip, 0.0), abs(math.degrees(angle)))
                        world = shoulder.inverted() @ Quaternion((0, 1, 0), angle) @ shoulder
                        r = target_rot[bone].inverted() @ world @ target_rot[bone] @ r
                for i in range(4):
                    axes[i].keyframe_points[k].co.y = r[i]
        elif prop == 'location':
            require(len(axes) == 3, 'partial location on ' + bone)
            count = len(axes[0].keyframe_points)
            for k in range(count):
                v = Vector([axes[i].keyframe_points[k].co.y for i in range(3)])
                v = c.inverted() @ v * travel
                for i in range(3):
                    axes[i].keyframe_points[k].co.y = v[i]
        else:
            require(prop == 'scale', 'unexpected channel %s on %s' % (prop, bone))
        for curve in axes.values():
            for key in curve.keyframe_points:
                key.interpolation = 'LINEAR'
                end = max(end, key.co.x)
            curve.update()
    lengths[clip] = end / FPS
    if rig.animation_data is None:
        rig.animation_data_create()
    track = rig.animation_data.nla_tracks.new()
    track.name = clip
    strip = track.strips.new(clip, 0, action)
    strip.action_slot = action.slots[0]
    track.mute = True

bpy.data.objects.remove(source)
for action in [a for a in bpy.data.actions if a.name.startswith('source_')]:
    bpy.data.actions.remove(action)


def pose(clip, frame):
    rig.animation_data.action = bpy.data.actions[clip]
    rig.animation_data.action_slot = bpy.data.actions[clip].slots[0]
    scene.frame_set(frame)


def bounds():
    deps = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in meshes:
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        try:
            points += [evaluated.matrix_world @ v.co for v in mesh.vertices]
        finally:
            evaluated.to_mesh_clear()
    return Vector([min(p[i] for p in points) for i in range(3)]), Vector([max(p[i] for p in points) for i in range(3)])


stage('arm swings clear of the head (deg): %s' % {k: round(v) for k, v in swings.items()})
# Shorter legs and a bigger head change where each pose touches the deck: lift the root on every
# key whose skinned mesh dips below the floor (lying down, the slide, crouched landings).
stage('ground every clip')
up_in_root = target_rest['root'].to_3x3().normalized().inverted() @ Vector((0, 0, 1))
lifts = {}
for clip in clips:
    location = curves_by_channel(bpy.data.actions[clip]).get(('root', 'location'))
    require(location is not None and len(location) == 3, 'root location keys missing on ' + clip)
    frames = [key.co.x for key in location[0].keyframe_points]
    corrections = []
    for k, frame in enumerate(frames):
        pose(clip, round(frame))
        dip = bounds()[0].z
        corrections.append(max(0.0, -dip))
    for k, lift in enumerate(corrections):
        for i in range(3):
            location[i].keyframe_points[k].co.y += up_in_root[i] * lift
    for curve in location.values():
        curve.update()
    lifts[clip] = round(max(corrections), 4)
stage('lifts (m): %s' % lifts)

stage('sample clip bounds')
clip_bounds = {}
for clip in clips:
    lows, highs = [], []
    for frame in range(0, round(lengths[clip] * FPS) + 1, 6):
        pose(clip, frame)
        lo, hi = bounds()
        lows.append(lo.z)
        highs.append(hi.z)
    clip_bounds[clip] = [round(min(lows), 4), round(max(highs), 4)]
    stage('%-16s %.2f s  z %.3f..%.3f' % (clip, lengths[clip], min(lows), max(highs)))
rig.animation_data.action = None
for bone in rig.pose.bones:
    bone.location, bone.rotation_quaternion, bone.scale = (0, 0, 0), (1, 0, 0, 0), (1, 1, 1)
scene.frame_set(0)

if args.preview:
    stage('previews')
    args.preview.mkdir(parents=True, exist_ok=True)
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 600, 800
    scene.render.film_transparent = True
    world = bpy.data.worlds.new('preview')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.5
    scene.world = world
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    camera = bpy.data.objects.new('camera', bpy.data.cameras.new('camera'))
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 2.1
    scene.collection.objects.link(camera)
    scene.camera = camera
    views = {'front': ((0, 4, 0.9), (math.pi / 2, 0, math.pi)), 'side': ((4, 0, 0.9), (math.pi / 2, 0, math.pi / 2)),
             'back34': ((-3, -3, 1.2), (math.radians(80), 0, math.radians(-45)))}
    shots = [('rest', None, 0)] + [(clip, clip, f) for clip, f in
                                   (('run', 0), ('run', 18), ('jump', 30), ('roll', 48), ('dead', 140), ('victory', 60))]
    for label, clip, frame in shots:
        if clip:
            pose(clip, frame)
        for view, (location, rotation) in views.items():
            if clip and view == 'back34':
                continue
            camera.location, camera.rotation_euler = location, rotation
            scene.render.filepath = str(args.preview / ('%s_%s_%d.png' % (view, label, frame)))
            bpy.ops.render.render(write_still=True)
    rig.animation_data.action = None
    scene.frame_set(0)
    # Weight check: the bends the spring rig applies (cape swung back and sideways, ears whipped).
    bends = {'cape': (-0.5, 0, 0.3), 'cape_tip': (-0.45, 0, 0.25), 'ear_L': (0.3, 0, 0.2), 'ear_tip_L': (0.4, 0, 0.2),
             'ear_R': (0.3, 0, 0.2), 'ear_tip_R': (0.4, 0, 0.2)}
    for name, angles in bends.items():
        rig.pose.bones[name].rotation_mode = 'XYZ'
        rig.pose.bones[name].rotation_euler = angles
    for view in ('front', 'side', 'back34'):
        camera.location, camera.rotation_euler = views[view]
        scene.render.filepath = str(args.preview / ('%s_sway.png' % view))
        bpy.ops.render.render(write_still=True)
    for name in bends:
        rig.pose.bones[name].rotation_euler = (0, 0, 0)
        rig.pose.bones[name].rotation_mode = 'QUATERNION'
    for obj in (sun, camera):
        bpy.data.objects.remove(obj)

stage('export GLB')
scene.render.fps = FPS
script_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
bpy.ops.object.select_all(action='DESELECT')
for obj in meshes:
    obj.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
OUT.parent.mkdir(parents=True, exist_ok=True)
result = bpy.ops.export_scene.gltf(filepath=str(OUT), export_format='GLB', use_selection=True,
                                   export_animations=True, export_animation_mode='ACTIONS',
                                   export_frame_range=False, export_force_sampling=True, export_yup=True,
                                   export_image_format='AUTO', export_extras=False,
                                   export_vertex_color='NAME', export_vertex_color_name='led_mask')
require('FINISHED' in result and OUT.is_file(), 'glTF export failed')

stage('share each ORM image as occlusion and stamp provenance')
raw = OUT.read_bytes()
magic, version, total = struct.unpack_from('<III', raw, 0)
require(magic == 0x46546C67 and version == 2 and total == len(raw), 'invalid GLB header')
json_length, json_type = struct.unpack_from('<II', raw, 12)
require(json_type == 0x4E4F534A, 'first GLB chunk must be JSON')
gltf = json.loads(raw[20:20 + json_length])
rest = raw[20 + json_length:]
for material in gltf['materials']:
    orm = material['pbrMetallicRoughness']['metallicRoughnessTexture']['index']
    material['occlusionTexture'] = {'index': orm, 'strength': 1.0}
gltf['asset']['generator'] = 'tools/blender/build_hoppy_hero.py'
gltf['asset']['extras'] = {'build_script_sha256': script_hash, 'clip_source': 'Assets/runner/hoppy/hoppy.glb'}
text = json.dumps(gltf, separators=(',', ':')).encode()
text += b' ' * (-len(text) % 4)
OUT.write_bytes(struct.pack('<III', magic, version, 12 + 8 + len(text) + len(rest)) +
                struct.pack('<II', len(text), 0x4E4F534A) + text + rest)
report = {
    'generator': 'tools/blender/build_hoppy_hero.py',
    'script_sha256': script_hash,
    'blender': bpy.app.version_string,
    'source_mesh': 'rabbit_mesh.obj',
    'clip_source': 'Assets/runner/hoppy/hoppy.glb',
    'height_m': HEIGHT,
    'cm_to_m': round(cm_to_m, 6),
    'travel_scale': round(travel, 4),
    'triangles': triangles,
    'triangle_cap': TRIANGLE_CAP,
    'animations': clips,
    'clip_seconds': {clip: round(lengths[clip], 4) for clip in clips},
    'clip_bounds_z': clip_bounds,
    'ground_lift_m': lifts,
    'arm_swing_deg': {k: round(v, 1) for k, v in swings.items()},
    'ear_damp': EAR_DAMP,
    'materials': [m['name'] for m in gltf['materials']],
    'led_band': list(LED_BAND),
    'led_segments': LED_SEGMENTS,
}
OUT.with_name('hoppy_hero.build.json').write_text(json.dumps(report, indent=2) + '\n')
stage('wrote %s (%d bytes, %d triangles)' % (OUT.name, OUT.stat().st_size, triangles))
