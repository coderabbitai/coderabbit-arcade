"""Coordinator host Eevee turntable, including imported action/frame selection.
Blender --background --python-exit-code 1 --python tools/blender/render_hoppy.py -- MODEL OUT [--action run --frame 6]
"""
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('glb', type=Path)
parser.add_argument('out', type=Path)
parser.add_argument('--action', choices=('idle', 'run', 'jump', 'fall', 'roll', 'hurt', 'dead'))
parser.add_argument('--frame', type=float, default=0, help='30 fps action-relative frame, including subframes')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
if not args.glb.is_file():
    raise RuntimeError('[render] Missing GLB: ' + str(args.glb))
args.out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
# glTF import converts seconds to frames using the current scene rate.
# Set it before import, so --frame is truly a 30 fps action-relative frame.
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=str(args.glb.resolve()))
scene = bpy.context.scene
scene.render.fps = 30
# Imported actions can receive a rig suffix; the NLA track preserves glTF names.
if args.action:
    matches = []
    for obj in bpy.data.objects:
        if obj.type != 'ARMATURE' or not obj.animation_data:
            continue
        for track in obj.animation_data.nla_tracks:
            for strip in track.strips:
                if strip.action and (track.name == args.action or strip.action.name == args.action):
                    matches.append((obj.name, strip.action.name, strip.action_slot.handle))
            track.mute = True
    if len(matches) != 1:
        raise RuntimeError('[render] Expected one action binding for %s, got %s; actions=%s' %
                           (args.action, matches, list(bpy.data.actions.keys())))
    rig_name, action_name, slot_handle = matches[0]
    rig = bpy.data.objects[rig_name]
    action = bpy.data.actions[action_name]
    rig.animation_data.action = action
    rig.animation_data.action_slot = next(slot for slot in action.slots if slot.handle == slot_handle)
    if not 0 <= args.frame <= action.frame_range[1] - action.frame_range[0]:
        raise RuntimeError('[render] Frame outside action range: ' + str(tuple(action.frame_range)))
    frame = action.frame_range[0] + args.frame
    scene.frame_set(math.floor(frame), subframe=frame % 1)
    print('[render] pose action=%s frame=%s binding=%s' % (args.action, args.frame, action_name), flush=True)
else:
    if args.frame != 0:
        raise RuntimeError('[render] --frame requires --action')
    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE' and obj.animation_data:
            obj.animation_data.action = None
            for track in obj.animation_data.nla_tracks: track.mute = True
            for bone in obj.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
    scene.frame_set(0)
    print('[render] rest pose', flush=True)

# Never silently fall back to Workbench, which hides the baked PBR result.
for engine in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
else:
    raise RuntimeError('[render] Eevee is unavailable')
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
world = bpy.data.worlds.new('Hoppy navy studio'); scene.world = world
if world.node_tree is None: world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs[0].default_value = (.02, .03, .06, 1)
bg.inputs[1].default_value = .45

def light(name, loc, energy, color):
    data = bpy.data.lights.new(name, 'AREA'); data.energy = energy; data.color = color; data.size = 3
    obj = bpy.data.objects.new(name, data); scene.collection.objects.link(obj); obj.location = loc
    obj.rotation_euler = (Vector((0, 0, .95)) - obj.location).to_track_quat('-Z', 'Y').to_euler()

# Blender +Y is Godot -Z (the face). Previous fixture's front/rear were reversed.
light('key', (2.5, 3, 3.5), 500, (1, .98, .92))
light('fill', (-3, 2, 2), 180, (.6, .9, .85))
light('rim', (0, -3, 2.5), 350, (.5, .95, .8))
cam = bpy.data.cameras.new('Hoppy camera'); cam.lens = 60
co = bpy.data.objects.new('Hoppy camera', cam); scene.collection.objects.link(co); scene.camera = co
views = {'front': (0, 3.9, 1.3), 'threequarter': (2.6, 2.9, 1.5), 'rear': (0, -3.9, 1.3)}
target = Vector((0, 0, .45 if args.action == 'roll' else .92))
for name, loc in views.items():
    co = bpy.data.objects['Hoppy camera']
    co.location = loc
    co.rotation_euler = (target - co.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(args.out.resolve() / ('hoppy_' + name + '.png'))
    bpy.ops.render.render(write_still=True)
    if not Path(scene.render.filepath).is_file():
        raise RuntimeError('[render] Missing render: ' + scene.render.filepath)
print('[render] done ' + str(list(views)), flush=True)
