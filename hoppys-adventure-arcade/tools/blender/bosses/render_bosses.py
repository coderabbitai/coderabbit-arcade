"""Eevee turntable and contact sheets from the exported GLB, all eight actions.

Blender --background --python-exit-code 1 --python tools/blender/bosses/render_bosses.py --
    --kind kit_selftest --asset-dir Assets/runner/bosses --out-dir /tmp/boss-renders
    [--size 512 --views 8 --frames 6]
Each PNG sheet reads left to right in time/angle; captures.json records exact poses.
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
BUDGET = json.loads((HERE / 'bosses_budget.json').read_text())


def require(ok, message):
    if not ok:
        raise RuntimeError('[boss-render] ' + message)


def bind(rig, name):
    matches = []
    for track in rig.animation_data.nla_tracks:
        track.mute = True
        for strip in track.strips:
            if track.name == name and strip.action:
                matches.append((strip.action, strip.action_slot))
    require(len(matches) == 1, 'Expected one action binding: ' + name)
    rig.animation_data.action, rig.animation_data.action_slot = matches[0]
    return matches[0][0]


def bounds(meshes):
    points = []
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in meshes:
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        try:
            points.extend(evaluated.matrix_world @ v.co for v in mesh.vertices)
        finally:
            evaluated.to_mesh_clear()
    return points


def sheet(files, path, size):
    # Assemble rendered PNGs using Blender's image API; no Pillow dependency on the host.
    pixels = np.zeros((size, size * len(files), 4), dtype=np.float32)
    for index, file in enumerate(files):
        image = bpy.data.images.load(str(file), check_existing=False)
        tile = np.empty(size * size * 4, dtype=np.float32)
        image.pixels.foreach_get(tile)
        pixels[:, index * size:(index + 1) * size, :] = tile.reshape(size, size, 4)
        bpy.data.images.remove(image)
    image = bpy.data.images.new(path.stem, width=size * len(files), height=size, alpha=True)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw, image.file_format = str(path), 'PNG'
    image.save()
    bpy.data.images.remove(image)


def render(kind, args):
    glb = args.asset_dir.resolve() / kind / (kind + '.glb')
    require(glb.is_file(), 'Missing GLB: ' + str(glb))
    out = args.out_dir.resolve() / kind
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 120
    bpy.ops.import_scene.gltf(filepath=str(glb))
    rigs = [o for o in bpy.data.objects if o.type == 'ARMATURE']
    require(len(rigs) == 1, 'Expected one rig')
    rig = rigs[0]
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    scene.frame_set(0)
    rest = bounds(meshes)
    for engine in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    else:
        raise RuntimeError('Eevee is unavailable')
    scene.render.resolution_x = scene.render.resolution_y = args.size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.world = bpy.data.worlds.new('Boss navy studio')
    bg = scene.world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value, bg.inputs[1].default_value = (0.02, 0.03, 0.06, 1), 0.45
    lo = Vector(tuple(min(p[i] for p in rest) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in rest) for i in range(3)))
    centre = (lo + hi) * 0.5
    span = max(hi - lo)
    for name, offset, energy, color in [('key', (1.5, -2, 2), 500, (1, 0.98, 0.92)),
            ('fill', (-2, -1, 1), 180, (0.6, 0.9, 0.85)), ('rim', (0, 2, 2), 350, (0.5, 0.95, 0.8))]:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.color, data.size = energy * span * span, color, span * 2
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = centre + Vector(offset) * span
        light.rotation_euler = (centre - light.location).to_track_quat('-Z', 'Y').to_euler()
    data = bpy.data.cameras.new('Boss camera')
    data.type = 'ORTHO'
    camera = bpy.data.objects.new('Boss camera', data)
    scene.collection.objects.link(camera)
    scene.camera = camera

    def camera_at(points, angle):
        low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
        high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
        target = (low + high) * 0.5
        diameter = (high - low).length
        data.ortho_scale = max(diameter * 1.15, 0.5)
        camera.location = target + Vector((math.sin(angle), -math.cos(angle), 0.35)) * diameter * 3
        camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()

    def capture(name):
        path = out / (name + '.png')
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        require(path.is_file(), 'Missing PNG: ' + str(path))
        return path

    views = []
    for i in range(args.views):
        camera_at(rest, math.tau * i / args.views)
        views.append(capture('turntable_%02d' % i))
    sheet(views, out / 'turntable.png', args.size)
    manifest = {'kind': kind, 'fps': 120, 'turntable_degrees': [360 * i / args.views for i in range(args.views)], 'actions': {}}
    for name in BUDGET['actions']:
        action = bind(rig, name)
        first, last = action.frame_range
        frames = [first + (last - first) * i / (args.frames - 1) for i in range(args.frames)]
        points = []
        for frame in frames:
            scene.frame_set(math.floor(frame), subframe=frame % 1)
            points.extend(bounds(meshes))
        camera_at(points, 0.35)
        files = []
        for i, frame in enumerate(frames):
            scene.frame_set(math.floor(frame), subframe=frame % 1)
            files.append(capture(name + '_%02d' % i))
        sheet(files, out / (name + '.png'), args.size)
        manifest['actions'][name] = {'frames': frames, 'seconds': [(f - first) / 120 for f in frames]}
    (out / 'captures.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('BOSS RENDER: PASS ' + str(out), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=BUDGET['kinds'] + ['all'], required=True)
    parser.add_argument('--asset-dir', type=Path, default=Path('Assets/runner/bosses'))
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--size', type=int, default=512)
    parser.add_argument('--views', type=int, default=8)
    parser.add_argument('--frames', type=int, default=6)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    require(args.size >= 64 and 1 <= args.views <= 32 and 2 <= args.frames <= 24, 'Invalid render dimensions')
    for kind in BUDGET['kinds'] if args.kind == 'all' else [args.kind]:
        render(kind, args)
