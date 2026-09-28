"""Host Eevee turntables of the exported hero props with their baked atlases bound.

  Blender --background --python-exit-code 1 --python tools/blender/props/render_props.py -- \
      --glb Assets/runner/props/hazard_props.glb --out ../docs/previews/assets --prefix a3

Every root (HZ_<kind> / PU_<kind>) is rendered on its own from a three-quarter and a front view:
<prefix>-blender-<kind>-threequarter.png and -front.png. The GLB carries geometry only, so this script
binds the same four maps the runtime samples (albedo, normal, ORM, emission). Pickup emission is a grey
mask tinted MINT (power-ups) or ORANGE (tools), as the runtime shader does.
"""
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--glb', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--prefix', required=True)
parser.add_argument('--only', default='')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
if not args.glb.is_file():
    raise RuntimeError('[render] Missing GLB: ' + str(args.glb))
args.out.mkdir(parents=True, exist_ok=True)
family = args.glb.stem
atlases = {c: args.glb.with_name('%s_%s.png' % (family, c)) for c in ('albedo', 'normal', 'orm', 'emission')}
for channel, path in atlases.items():
    if not path.is_file():
        raise RuntimeError('[render] Missing atlas: ' + str(path))
TOOLS = ('review_comment', 'lint_rule', 'unit_test', 'auto_fix_patch')


def linear(hex_colour):
    out = []
    for i in range(3):
        c = int(hex_colour[i * 2:i * 2 + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out) + (1.0,)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(args.glb.resolve()))
scene = bpy.context.scene
for engine in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
else:
    raise RuntimeError('[render] Eevee is unavailable')
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'Standard'
world = bpy.data.worlds.new('props navy studio')
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs[0].default_value = (0.012, 0.02, 0.035, 1)
bg.inputs[1].default_value = 0.6


def image(channel):
    img = bpy.data.images.load(str(atlases[channel].resolve()))
    img.colorspace_settings.name = 'sRGB' if channel in ('albedo', 'emission') else 'Non-Color'
    return img


IMAGES = {c: image(c) for c in atlases}


def baked_material(name, tint=None):
    m = bpy.data.materials.new(name)
    n, l = m.node_tree.nodes, m.node_tree.links
    p = n['Principled BSDF']
    tex = {c: n.new('ShaderNodeTexImage') for c in IMAGES}
    for c, node in tex.items():
        node.image = IMAGES[c]
    orm = n.new('ShaderNodeSeparateColor')
    l.new(tex['orm'].outputs['Color'], orm.inputs[0])
    ao = n.new('ShaderNodeMixRGB')
    ao.blend_type = 'MULTIPLY'
    ao.inputs['Factor'].default_value = 1.0
    l.new(tex['albedo'].outputs['Color'], ao.inputs['Color1'])
    grey = n.new('ShaderNodeCombineColor')
    for ch in ('Red', 'Green', 'Blue'):
        l.new(orm.outputs['Red'], grey.inputs[ch])
    l.new(grey.outputs[0], ao.inputs['Color2'])
    l.new(ao.outputs['Color'], p.inputs['Base Color'])
    l.new(orm.outputs['Green'], p.inputs['Roughness'])
    l.new(orm.outputs['Blue'], p.inputs['Metallic'])
    normal = n.new('ShaderNodeNormalMap')
    l.new(tex['normal'].outputs['Color'], normal.inputs['Color'])
    l.new(normal.outputs['Normal'], p.inputs['Normal'])
    emission = tex['emission'].outputs['Color']
    if tint is not None:
        tinted = n.new('ShaderNodeMixRGB')
        tinted.blend_type = 'MULTIPLY'
        tinted.inputs['Factor'].default_value = 1.0
        l.new(emission, tinted.inputs['Color1'])
        tinted.inputs['Color2'].default_value = tint
        emission = tinted.outputs['Color']
    l.new(emission, p.inputs['Emission Color'])
    p.inputs['Emission Strength'].default_value = 1.6
    return m


roots = sorted((o for o in bpy.data.objects if o.name.startswith(('HZ_', 'PU_'))), key=lambda o: o.name)
if not roots:
    raise RuntimeError('[render] No HZ_/PU_ roots in ' + str(args.glb))


def descendants(obj):
    out = []
    for child in obj.children:
        out.append(child)
        out.extend(descendants(child))
    return out


hazard_material = baked_material('hazard baked PBR')
for root in roots:
    kind = root.name.split('_', 1)[1]
    material = hazard_material
    if root.name.startswith('PU_'):
        material = baked_material('pickup ' + kind, linear('f78949') if kind in TOOLS else linear('73e6bf'))
    for obj in descendants(root):
        if obj.type == 'MESH':
            obj.data.materials.clear()
            obj.data.materials.append(material)


def light(name, loc, target, energy, colour, size=4.0):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.color, data.size = energy, colour, size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (target - obj.location).to_track_quat('-Z', 'Y').to_euler()
    return obj


cam_data = bpy.data.cameras.new('props camera')
cam_data.lens = 50
camera = bpy.data.objects.new('props camera', cam_data)
scene.collection.objects.link(camera)
scene.camera = camera
saved = []
bpy.context.view_layer.update()
for root in roots:
    kind = root.name.split('_', 1)[1]
    if args.only and kind != args.only:
        continue
    for other in roots:
        visible = other == root
        for obj in [other] + descendants(other):
            obj.hide_render = not visible
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in descendants(root):
        if obj.type != 'MESH':
            continue
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    centre = (lo + hi) / 2
    extent = max((hi - lo).length, 0.5)
    pickup = root.name.startswith('PU_')
    scene.render.resolution_x = 800 if pickup else 1200
    scene.render.resolution_y = 800 if pickup else 700
    # Blender -Y faces the player: key from front-right-above, cool fill, teal rim from behind.
    lights = [light('key', centre + Vector((extent * 0.9, -extent * 1.2, extent * 1.1)), centre, 26 * extent ** 2, (1, .97, .92)),
              light('fill', centre + Vector((-extent * 1.2, -extent * 0.6, extent * 0.5)), centre, 8 * extent ** 2, (.6, .85, .95)),
              light('rim', centre + Vector((0, extent * 1.3, extent * 0.9)), centre, 20 * extent ** 2, (.55, .9, .85))]
    # Blender -Y is Godot +Z (the side facing the player).
    for view, direction in (('threequarter', Vector((0.55, -1.0, 0.55))), ('front', Vector((0.0, -1.0, 0.18)))):
        distance = extent * (1.7 if pickup else 1.25)
        camera.location = centre + direction.normalized() * distance
        camera.rotation_euler = (centre - camera.location).to_track_quat('-Z', 'Y').to_euler()
        path = args.out.resolve() / ('%s-blender-%s-%s.png' % (args.prefix, kind, view))
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        if not path.is_file():
            raise RuntimeError('[render] Missing render: ' + str(path))
        saved.append(path.name)
    for obj in lights:
        bpy.data.objects.remove(obj)
print('[render] done %d images: %s' % (len(saved), ', '.join(saved)), flush=True)
