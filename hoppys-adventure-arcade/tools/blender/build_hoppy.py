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
RECIPE_REVISION = 6
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
    l.new(height.outputs[0], bump.inputs['Height']); l.new(bump.outputs[0], p.inputs['Normal'])
    p.inputs['Roughness'].default_value = .84 if kind in ('fur', 'cloth') else .32
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Emission Color'].default_value = tuple(color) + (1,)
    p.inputs['Emission Strength'].default_value = glow
    recipes[m.name] = (ramp.name, p.inputs['Roughness'].default_value, metallic, tuple(c * glow for c in color) + (1,))
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

def loft(name, rows, mat, bone, sides=12, atlas='body', crease=0.0):
    """Continuous quad rings, Catmull-Clark subdivision, no overlapping limb balls.
    Rows: (centre_x, height_y, centre_z, radius_x, radius_z).
    """
    vertices, faces = [], []
    for row_index, (cx, y, cz, rx, rz) in enumerate(rows):
        for j in range(sides):
            a = j * math.tau / sides
            fold = 1 + crease * math.sin(row_index * 2.3 + a * 3)
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


def blend_joint(object_name, upper, lower, joint_y, width):
    obj = object_named(object_name, 'MESH')
    if obj.vertex_groups.get(lower) is None: obj.vertex_groups.new(name=lower)
    for vertex in obj.data.vertices:
        weight = max(0, min(1, (joint_y + width - vertex.co.z) / (2*width)))
        weight = weight * weight * (3-2*weight)
        obj.vertex_groups[upper].add([vertex.index], 1-weight, 'REPLACE')
        obj.vertex_groups[lower].add([vertex.index], weight, 'REPLACE')


stage('model geometry')
# Main sculpt: broad face, haunches, tapered runner torso, glove-like paws.
ellipsoid('Skull sculpt', (0, 1.255, -.025), (.257, .25, .223), cream, 'head', segments=32, rings=24)
loft('Hoodie tailored torso', [(0,y,z,rx,rz) for y,z,rx,rz in [
    (.51,.015,.17,.125),(.53,.015,.21,.16),(.56,.015,.22,.172),(.60,.015,.222,.172),
    (.69,.01,.235,.18),(.80,0,.237,.183),(.92,0,.226,.171),
    (1.015,0,.24,.135),(1.055,0,.19,.1),(1.075,0,.115,.075)]], orange, 'spine', sides=20, crease=.025)
loft('Ribbed hem band', [(0,y,.015,.223,.172) for y in (.525,.53,.565,.57)], slate, 'hips', sides=20)
# Deep folded hood shell around the neck, open at its upper edge.
loft('Sculpted hood shell', [(0,y,z,rx,rz) for y,z,rx,rz in [
    (.99,.18,.15,.10),(1.015,.18,.21,.17),(1.09,.17,.249,.20),
    (1.18,.16,.241,.20),(1.195,.15,.225,.18),(1.18,.15,.201,.15),
    (1.08,.16,.18,.12),(1.04,.17,.10,.045)]], orange, 'chest', sides=20, crease=.035)
tube('Hood mint seam', [(math.cos(a)*.225,1.188,.15+math.sin(a)*.18) for a in [i*math.tau/32 for i in range(33)]], .005, mint, 'chest', detail=1)

box('Kangaroo pocket', (0, .705, -.181), (.295, .145, .045), orange, 'spine', 'body')
tube('Pocket stitched welt', [(-.14,.76,-.206),(-.13,.655,-.206),(0,.644,-.208),(.13,.655,-.206),(.14,.76,-.206)], .003, cream, 'spine')
box('Embossed logo backing', (0,.878,-.191), (.151,.144,.026), slate,'spine')
box('Short collar placket', (0,1.002,-.137), (.024,.108,.018), slate,'chest')
box('Zip pull', (0,.966,-.152), (.033,.039,.015), mint,'chest')
ellipsoid('Tail tuft', (0, .65, .242), (.096, .106, .095), cream, 'tail')
for side, sign in [('L', -1), ('R', 1)]:
    x = sign
    ellipsoid('Cheek ' + side, (x*.107, 1.167, -.218), (.113, .082, .073), cream, 'head')
    ellipsoid('Ear ' + side, (x*.12, 1.574, .005), (.069, .226, .051), cream, 'ear_'+side)
    ellipsoid('Inner Ear ' + side, (x*.12, 1.586, -.042), (.039, .171, .012), inner, 'ear_'+side)
    ellipsoid('Sclera '+side, (x*.105, 1.296, -.221), (.09, .101, .043), white, 'head', 'accessory')
    ellipsoid('Iris '+side, (x*.1, 1.291, -.256), (.049, .06, .017), mint, 'eye_'+side, 'accessory')
    ellipsoid('Pupil '+side, (x*.1, 1.291, -.268), (.027, .039, .01), black, 'eye_'+side, 'accessory')
    ellipsoid('Catchlight '+side, (x*.1-.012, 1.31, -.276), (.008, .011, .004), white, 'eye_'+side, 'accessory', 12, 8)
    tube('Brow '+side, [(x*.044,1.402,-.206),(x*.10,1.419,-.22),(x*.166,1.397,-.199)], .014, slate, 'head', detail=1)
    tube('Upper eyelid '+side, [(x*.105-.085,1.304,-.23),(x*.105,1.388,-.239),(x*.105+.085,1.304,-.23)], .009, cream,'head')
    # Forehead goggles connect through side hinges to the wraparound strap.
    box('Goggle hinge '+side,(x*.23,1.415,-.123),(.041,.038,.042),slate,'head')
    tube('Goggle temple '+side,[(x*.206,1.422,-.169),(x*.244,1.415,-.10),(x*.248,1.4,-.015)],.01,slate,'head')
    points = [(x*.113+math.cos(a)*.094, 1.423+math.sin(a)*.064, -.169) for a in [i*math.tau/16 for i in range(17)]]
    tube('Goggle frame '+side, points, .012, slate, 'head')
    ellipsoid('Goggle lens '+side, (x*.113,1.423,-.171), (.081,.051,.009), glass, 'head', 'accessory')
    sleeve = loft('Continuous sleeve '+side, [(x*cx,y,z,rx,rz) for cx,y,z,rx,rz in [
        (.244,1.032,.012,.067,.066),(.257,1.015,.012,.084,.085),(.276,.95,.01,.083,.082),
        (.292,.85,0,.078,.077),(.30,.79,-.008,.074,.074),(.302,.75,-.019,.073,.075),
        (.30,.67,-.025,.066,.068),(.30,.606,-.029,.061,.061)]], orange,'arm_'+side,crease=.045)
    blend_joint(sleeve,'arm_'+side,'forearm_'+side,.78,.085)
    loft('Cuff '+side,[(x*.3,y,-.029,.066,.066) for y in (.59,.594,.63,.634)],slate,'forearm_'+side)
    tube('Sleeve piping '+side,[(x*.30,.97,-.064),(x*.327,.9,-.062),(x*.353,.83,-.025)],.004,mint,'arm_'+side)
    tube('Forearm piping '+side,[(x*.357,.77,-.025),(x*.358,.7,-.04),(x*.348,.633,-.05)],.004,mint,'forearm_'+side)
    ellipsoid('Palm '+side,(x*.3,.555,-.031),(.074,.065,.065),cream,'hand_'+side,segments=20,rings=12)
    ellipsoid('Thumb '+side,(x*.243,.55,-.069),(.028,.042,.031),cream,'hand_'+side,segments=16,rings=10)
    for finger in range(3):
        ellipsoid('Finger %s %d'%(side,finger),(x*(.264+finger*.033),.512,-.045),(.021,.043,.032),cream,'hand_'+side,segments=12,rings=10)
    leg = loft('Continuous leg '+side,[(x*cx,y,z,rx,rz) for cx,y,z,rx,rz in [
        (.126,.54,.015,.075,.085),(.126,.515,.015,.097,.104),(.128,.44,.01,.096,.1),
        (.129,.35,0,.078,.079),(.129,.31,-.012,.073,.075),(.13,.25,-.007,.072,.073),
        (.131,.16,0,.061,.064),(.131,.115,0,.058,.062)]],cream,'leg_'+side,crease=.012)
    leg_obj = object_named(leg, 'MESH')
    leg_obj.data.materials.append(slate)
    for polygon in leg_obj.data.polygons:
        if sum(leg_obj.data.vertices[i].co.z for i in polygon.vertices) / len(polygon.vertices) > .39:
            polygon.material_index = 1
    blend_joint(leg,'leg_'+side,'shin_'+side,.32,.065)
    loft('Shoe sole '+side, [(x*.131,y,-.064,SOLE_RADII[0],SOLE_RADII[1])
         for y in (0.0,.006,.052,.058)], mint, 'foot_'+side, sides=16, atlas='accessory')
    ellipsoid('Runner shoe '+side, (x*.131,.099,-.061), (.1,.074,.154), slate, 'foot_'+side, 'accessory')
    ellipsoid('Sneaker toe cap '+side,(x*.131,.091,-.159),(.094,.054,.064),slate,'foot_'+side,'accessory',20,12)
    tube('Sole emissive piping '+side,[(x*.131+math.cos(a)*.096,.05,-.064+math.sin(a)*.154) for a in [j*math.tau/24 for j in range(25)]],.004,mint,'foot_'+side,detail=1)
    box('Shoe heel tab '+side, (x*.131,.153,.056), (.056,.061,.024), orange, 'foot_'+side)
    for i in range(3):
        tube('Lace %s %d'%(side,i), [(x*.131-.047,.148-i*.009,-.055-i*.027),(x*.131,.16-i*.009,-.07-i*.027),(x*.131+.047,.148-i*.009,-.055-i*.027)], .005, cream, 'foot_'+side)
    tube('Drawcord '+side, [(x*.067,1.052,-.156),(x*.071,.959,-.19),(x*.087,.87,-.204)], .008, cream, 'chest')
    box('Aglet '+side, (x*.087,.861,-.204), (.02,.039,.022), mint, 'chest')
    for j in range(3):
        tube('Whisker %s %d'%(side,j), [(x*.157,1.165-j*.012,-.251),(x*.235,1.176-j*.024,-.257),(x*.305,1.192-j*.035,-.235)], .002, cream, 'head')
    # Braces are original curve geometry, not a system font asset.
    for rear in (False, True):
        z = .268 if rear else -.211  # Pack face ends at z=.2555.
        points = [(x*gx, .815+(gy-.876)*.65 if rear else gy, z) for gx,gy in BRACE_PROFILE]
        tube(('Back' if rear else 'Chest')+' brace '+side, points, .006, mint, 'chest' if rear else 'spine')
    for j in range(10):
        tube('Hem stitch %s %d'%(side,j), [(x*(.025+j*.019),.555,-.141),(x*(.031+j*.019),.563,-.143)], .0018, cream, 'spine')
ellipsoid('Nose', (0,1.185,-.29), (.038,.025,.021), inner, 'head', 'accessory')
tube('Muzzle smile', [(-.061,1.133,-.267),(0,1.122,-.281),(.061,1.133,-.267)], .003, slate, 'head')
tube('Goggle strap', [(math.sin(i*math.tau/24)*.253,1.4,math.cos(i*math.tau/24)*.179) for i in range(25)], .014, slate, 'head', detail=1)
box('Goggle bridge',(0,1.423,-.17),(.042,.017,.025),slate,'head')
box('Slim battery pack',(0,.879,.209),(.249,.243,.093),slate,'chest')
for led in range(4):
    box('Matrix battery LED '+str(led),(-.054+led*.036,.898,.26),(.021,.069,.009),matrix,'chest')
box('Wrist device',(-.3,.683,-.09),(.099,.086,.043),slate,'forearm_L')
box('Matrix wrist screen',(-.3,.689,-.114),(.07,.053,.006),matrix,'forearm_L')
box('Utility pouch',(.242,.659,.035),(.082,.142,.133),slate,'hips')
box('Pouch clasp',(.287,.687,.012),(.016,.033,.046),mint,'hips')
tube('Utility belt',[(math.sin(i*math.tau/24)*.231,.627,math.cos(i*math.tau/24)*.177) for i in range(25)],.016,slate,'hips',detail=1)

stage('geometry census before baking')
model_triangles = sum(sum(len(face.vertices)-2 for face in object_named(name, 'MESH').data.polygons)
                      for name, _atlas in parts)
print('[hoppy] model triangles=' + str(model_triangles), flush=True)
require(model_triangles <= 40000, 'Pre-bake triangle budget exceeded: ' + str(model_triangles))

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
        for material_name in material_names:
            m = bpy.data.materials[material_name]
            n, l = m.node_tree.nodes, m.node_tree.links
            target = n.new('ShaderNodeTexImage'); target.image = image; n.active = target
            emit_name = None
            if channel != 'normal':
                emit = n.new('ShaderNodeEmission'); emit_name = emit.name
                base, rough, metal, emission = recipes[material_name]
                if channel == 'albedo':
                    l.new(n[base].outputs[0], emit.inputs['Color'])
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
# Anatomical armature. Extra eye bones are reserved for runtime lane targeting.
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
    bone('shoulder_'+side,(s*.04,1.02,0),(s*.25,1.02,0),'chest')
    bone('arm_'+side,(s*.25,1.02,0),(s*.3,.78,0),'shoulder_'+side)
    bone('forearm_'+side,(s*.3,.78,0),(s*.3,.6,-.03),'arm_'+side)
    bone('hand_'+side,(s*.3,.6,-.03),(s*.3,.5,-.03),'forearm_'+side)
    bone('leg_'+side,(s*.126,.55,0),(s*.129,.32,0),'hips')
    bone('shin_'+side,(s*.129,.32,0),(s*.131,.11,0),'leg_'+side)
    bone('foot_'+side,(s*.131,.11,0),(s*.131,.07,-.2),'shin_'+side)
bpy.ops.object.mode_set(mode='OBJECT')
rig = object_named(rig_name, 'ARMATURE')
require(len(rig.data.bones) == 27, 'Unexpected rig bone count')
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
rig.animation_data_create()
lengths={'idle':48,'run':18,'jump':15,'fall':24,'roll':24,'hurt':18,'dead':36}
for name,duration in lengths.items():
    stage('action ' + name)
    action=bpy.data.actions.new(name);rig.animation_data.action=action
    for f in range(0,duration+1,3):
        t=f/duration;phase=t*math.tau
        for p in rig.pose.bones:
            p.rotation_mode='XYZ';p.location=(0,0,0);p.rotation_euler=(0,0,0);p.scale=(1,1,1)
        root=rig.pose.bones['root']
        if name=='idle':rig.pose.bones['chest'].scale=(1+.009*math.sin(phase),1+.012*math.sin(phase),1)
        if name=='run':
            rig.pose.bones['spine'].rotation_euler.x=-.12
            rig.pose.bones['chest'].rotation_euler.z=.075*math.sin(phase)
            root.location.z=.025*(1-math.cos(phase*2));root.scale=(1.012,1-.02*math.cos(phase*2),1.012)
        if name=='jump':root.scale=(1-.07*math.sin(math.pi*t),1+.06*math.sin(math.pi*t),1-.07*math.sin(math.pi*t))
        if name=='hurt':root.location.y=-.14*math.sin(math.pi*t);root.rotation_euler.x=-.22*math.sin(math.pi*t)
        if name=='dead':root.rotation_euler.x=-min(1,t*1.6)*math.pi/2;root.location.z=.22*min(1,t*1.6)
        for side,s in [('L',-1),('R',1)]:
            arm=rig.pose.bones['arm_'+side];leg=rig.pose.bones['leg_'+side]
            ear=rig.pose.bones['ear_'+side]
            rig.pose.bones['ear_tip_'+side].rotation_euler.x=.07*math.sin(phase+.4)
            if name=='idle':ear.rotation_euler.z=s*.04*math.sin(phase)
            if name=='run':
                leg.rotation_euler.x=s*.65*math.cos(phase);arm.rotation_euler.x=-s*.62*math.cos(phase)
                rig.pose.bones['forearm_'+side].rotation_euler.x=-.3
                rig.pose.bones['shin_'+side].rotation_euler.x=max(0,-s*math.cos(phase))*.6
                ear.rotation_euler.x=.16+.13*math.sin(phase*2)
            if name in ('jump','fall'):arm.rotation_euler.x=-.8;leg.rotation_euler.x=-.4;ear.rotation_euler.x=.18
            if name=='jump':
                ear.rotation_euler.x=.2+.48*math.sin(math.pi*t)
                rig.pose.bones['ear_tip_'+side].rotation_euler.x=-.25*math.sin(math.pi*t)
            if name=='roll':
                arm.rotation_euler.x=-1.42;leg.rotation_euler.x=-1.25
                rig.pose.bones['shin_'+side].rotation_euler.x=1.8
                ear.rotation_euler.x=2.5;rig.pose.bones['ear_tip_'+side].rotation_euler.x=.45
                rig.pose.bones['head'].rotation_euler.x=.4
        if name=='roll':
            # Uniform scale and a centred spin keep the entire tuck inside 90 cm.
            root.scale=(.47,.47,.47);root.rotation_euler.x=-phase
            centre=Vector((0,0,.84));rot=root.rotation_euler.to_matrix()
            root.location=Vector((0,0,.45))-rot@(centre*.47)
        # Pose locations are bone-local; root's local Y points along world Z.
        root.location = rig.data.bones['root'].matrix_local.to_3x3().inverted() @ root.location
        for p in rig.pose.bones:
            for prop in ('location','rotation_euler','scale'):p.keyframe_insert(prop,frame=f,group=p.name)
    require(len(action.slots) == 1, 'Expected one armature action slot: ' + name)
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new();track.name=name
    strip=track.strips.new(name,0,action);strip.action_frame_start=0;strip.action_frame_end=duration
    strip.action_slot = action.slots[0]
    track.mute=True
    action['loop']=name in ('idle','run','fall')

# Evaluate actual deformed vertices across the roll action, independent of exporter.
stage('validate sampled roll bounds')
rig = object_named(rig_name, 'ARMATURE')
rig.animation_data.action=bpy.data.actions['roll']
rig.animation_data.action_slot=bpy.data.actions['roll'].slots[0]
lo=1e9;hi=-1e9
for f in range(lengths['roll']+1):
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
require(triangles<=40000, 'Triangle budget exceeded: ' + str(triangles))
stage('export GLB; triangles=' + str(triangles))
script_hash=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
helper_hash=hashlib.sha256(Path(__file__).with_name('glb_atlas.py').read_bytes()).hexdigest()
rig['build_script_sha256']=script_hash;rig['generator']='tools/blender/build_hoppy.py'
bpy.ops.object.select_all(action='DESELECT')
for name in mesh_names + [rig_name]: object_named(name).select_set(True)
bpy.context.view_layer.objects.active=object_named(rig_name, 'ARMATURE')
export_result = bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,
    export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,
    export_force_sampling=True,export_extras=True,export_yup=True,export_image_format='AUTO')
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
exported_triangles = 0
for mesh in payload.get('meshes', []):
    for primitive in mesh.get('primitives', []):
        require(primitive.get('mode', 4) == 4, 'Non-triangle primitive in GLB')
        accessor = (primitive['indices'] if 'indices' in primitive else primitive['attributes']['POSITION'])
        count = payload['accessors'][accessor]['count']
        require(count % 3 == 0, 'Invalid triangle index count')
        exported_triangles += count // 3
require(0 < exported_triangles <= 40000, 'Exported triangle budget exceeded: ' + str(exported_triangles))
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
        'brace_profile':BRACE_PROFILE,'sole_radii':SOLE_RADII,'back_mark_z':.268,
        'script_sha256':script_hash,'atlas_helper_sha256':helper_hash,'blender':bpy.app.version_string,'seed':SEED,'triangles':triangles,
        'image_report':image_report,'textures':textures,'exported_texture_count':exported_texture_count,'quick':opts.quick,'animations':list(lengths),'bones':[b.name for b in object_named(rig_name, 'ARMATURE').data.bones],
        'roll_bounds_y':[lo,hi],'height':1.8,'forward':[0,0,-1],'generator':payload['asset']['generator']}
(out.parent/'hoppy.build.json').write_text(json.dumps(report,indent=2)+'\n')
print('HOPPY BUILD: '+json.dumps(report,sort_keys=True))
print('[hoppy] EXPORT OK tris=%d textures=%d actions=%s file=%s bytes=%d' %
      (triangles, exported_texture_count, ','.join(exported_actions), out, out.stat().st_size), flush=True)
