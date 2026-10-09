"""Shared runner boss pipeline. Geometry and poses use Godot metres (x, y up, z).

Recipes construct BossBuilder, add bones and weighted Parts, attach all sockets,
bake_actions(durations, pose_callback), then export(out_dir). See build_kit_selftest.py.
Part / xform / linear and procedural finishes reuse the props kit; GLB images and
ORM use glb_atlas. Seeded recipes are stable, but Blender's UV solver can vary bytes.
"""
import hashlib
import json
import math
from pathlib import Path
import random
import re
import struct
import sys

import bpy
from mathutils import Euler, Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / 'props'))
import props_kit as P
from props_kit import Part, linear, xform, G2B, B2G
from glb_atlas import consolidate_atlases

SEED = 73019
RECIPE_REVISION = 2
BUDGET = json.loads((HERE / 'bosses_budget.json').read_text())
ACTIONS = tuple(BUDGET['actions'])
SOCKETS = tuple(BUDGET['sockets'])
FPS = BUDGET['animation_sample_rate']
PALETTE = {name: linear(value) for name, value in {
    'navy': '101d2d', 'slate': '435464', 'cream': 'fff0d3', 'mint': '79e0c4',
    'matrix': '63f9b2', 'orange': 'f78949', 'danger': 'ff4d3d', 'lilac': 'a99bff'}.items()}


def log(message):
    print('[boss-kit] ' + message, flush=True)


def require(condition, message):
    if not condition:
        raise RuntimeError('[boss-kit] ' + message)


def xyz(value):
    return Vector((value[0], -value[2], value[1]))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_glb(path):
    raw = Path(path).read_bytes()
    require(len(raw) >= 20, 'Empty GLB')
    magic, version, total = struct.unpack_from('<III', raw)
    require(magic == 0x46546c67 and version == 2 and total == len(raw), 'Invalid GLB header')
    chunks, offset = [], 12
    while offset < len(raw):
        require(offset + 8 <= len(raw), 'Truncated GLB chunk')
        length, kind = struct.unpack_from('<II', raw, offset)
        require(offset + 8 + length <= len(raw), 'Truncated GLB data')
        chunks.append((kind, raw[offset + 8:offset + 8 + length]))
        offset += 8 + length
    require(chunks[0][0] == 0x4e4f534a, 'Missing GLB JSON')
    return json.loads(chunks[0][1]), chunks


def write_glb(path, payload, chunks):
    encoded = json.dumps(payload, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    chunks[0] = (0x4e4f534a, encoded)
    body = b''.join(struct.pack('<II', len(data), kind) + data for kind, data in chunks)
    Path(path).write_bytes(struct.pack('<III', 0x46546c67, 2, len(body) + 12) + body)


def encode_rest_positions(payload, chunks):
    """Kit v2 ABI: UV2.xy = rest xy; CUSTOM0.xy (UV3) = rest z, version 1.

    Copy exported POSITION after all Blender geometry/UV work, so split vertices match
    exactly. Extra UVs survive glTF/Godot without skinning or COLOR's 8-bit conversion.
    These channels are reserved for the boss shader, not lightmap UVs.
    """
    binary_index = next(i for i, (kind, _) in enumerate(chunks) if kind == 0x004e4942)
    binary = bytearray(chunks[binary_index][1])
    cache = {}
    for mesh in payload['meshes']:
        for primitive in mesh['primitives']:
            attributes = primitive['attributes']
            require('TEXCOORD_1' not in attributes and 'TEXCOORD_2' not in attributes,
                    'Boss rest-position channels are already occupied')
            index = attributes['POSITION']
            if index not in cache:
                source = payload['accessors'][index]
                require(source['componentType'] == 5126 and source['type'] == 'VEC3'
                        and 'sparse' not in source, 'Expected dense float rest positions')
                view = payload['bufferViews'][source['bufferView']]
                require(view.get('buffer', 0) == 0, 'Expected one GLB buffer')
                start = view.get('byteOffset', 0) + source.get('byteOffset', 0)
                stride = view.get('byteStride', 12)
                values = [struct.unpack_from('<3f', binary, start + i * stride)
                          for i in range(source['count'])]
                binary.extend(b'\0' * (-len(binary) % 4))
                offset = len(binary)
                for x, y, z in values:
                    binary.extend(struct.pack('<4f', x, y, z, 1.0))
                view_index = len(payload['bufferViews'])
                payload['bufferViews'].append(dict(buffer=0, byteOffset=offset,
                    byteLength=len(values) * 16, byteStride=16, target=34962))
                accessors = []
                for component_offset in (0, 8):
                    accessors.append(len(payload['accessors']))
                    payload['accessors'].append(dict(bufferView=view_index,
                        byteOffset=component_offset, componentType=5126,
                        count=len(values), type='VEC2'))
                cache[index] = accessors
            attributes['TEXCOORD_1'], attributes['TEXCOORD_2'] = cache[index]
    payload['buffers'][0]['byteLength'] = len(binary)
    chunks[binary_index] = (0x004e4942, bytes(binary))


class BossBuilder:
    def __init__(self, kind, recipe_path, revision=1, seed=SEED, quick=False, atlas_resolution=None):
        require(kind in BUDGET['kinds'], 'Unknown boss kind: ' + kind)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        P.RECIPES.clear()
        self.kind, self.recipe_path, self.revision = kind, Path(recipe_path).resolve(), revision
        self.seed, self.quick, self.rng = seed, quick, random.Random(seed)
        self.resolution = atlas_resolution or BUDGET['atlas_resolution']
        require(0 < self.resolution <= BUDGET['atlas_resolution'], 'Atlas exceeds budget')
        self.scene = bpy.context.scene
        self.scene.render.engine = 'CYCLES'
        self.scene.cycles.device = 'CPU'
        self.scene.cycles.seed = seed
        self.scene.render.fps = FPS
        self.scene.render.fps_base = 1.0
        self.finishes, self.objects, self.sockets, self.durations = {}, [], {}, {}
        data = bpy.data.armatures.new(kind + '_rig')
        self.rig = bpy.data.objects.new(kind + '_rig', data)
        self.scene.collection.objects.link(self.rig)
        self.rig.animation_data_create()
        self.rig.show_in_front = True
        log('recipe=%s revision=%s seed=%s quick=%s' % (kind, revision, seed, quick))

    def material(self, name, color, finish='paint', roughness=0.45, metallic=0.5,
                 emission=None, emission_energy=0.0, **detail):
        """Finish classes: paint, shell, legacy, rubber, stripe, lines, plain (props kit)."""
        spec = dict(base=linear(color) if isinstance(color, str) else color,
                    kind=finish, rough=roughness, metal=metallic, **detail)
        if emission is not None:
            spec.update(emit=linear(emission) if isinstance(emission, str) else emission,
                        emit_strength=emission_energy)
        require(name not in self.finishes, 'Duplicate finish: ' + name)
        if self.quick:
            mat = bpy.data.materials.new(self.kind + '_' + name)
            p = mat.node_tree.nodes.get('Principled BSDF')
            p.inputs['Base Color'].default_value = (*spec['base'], 1.0)
            p.inputs['Roughness'].default_value = roughness
            p.inputs['Metallic'].default_value = metallic
            p.inputs['Emission Color'].default_value = (*spec.get('emit', (0, 0, 0)), 1.0)
            p.inputs['Emission Strength'].default_value = emission_energy
        else:
            mat = P.make_finish(self.kind + '_' + name, spec)
        self.finishes[name] = mat
        return name

    def bone(self, name, head, tail, parent=None):
        require(name not in self.rig.data.bones, 'Duplicate bone: ' + name)
        require((Vector(tail) - Vector(head)).length > 1e-5, 'Zero-length bone: ' + name)
        bpy.ops.object.select_all(action='DESELECT')
        self.rig.select_set(True)
        bpy.context.view_layer.objects.active = self.rig
        bpy.ops.object.mode_set(mode='EDIT')
        b = self.rig.data.edit_bones.new(name)
        b.head, b.tail = xyz(head), xyz(tail)
        if parent:
            require(parent in self.rig.data.edit_bones, 'Missing parent bone: ' + parent)
            b.parent = self.rig.data.edit_bones[parent]
        bpy.ops.object.mode_set(mode='OBJECT')
        return name

    def add_part(self, part, bone):
        """Rigid weight by default. Refine obj.vertex_groups before export for soft joints."""
        require(bone in self.rig.data.bones, 'Missing part bone: ' + bone)
        obj = part.to_object(self.scene.collection, self.finishes)
        obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
        obj.parent = self.rig
        mod = obj.modifiers.new('Boss skin', 'ARMATURE')
        mod.object = self.rig
        self.objects.append(obj)
        return obj

    def socket(self, name, bone, position):
        """Attach at a Godot-frame rest position, then follow the named animated bone."""
        require(name in SOCKETS and name not in self.sockets, 'Invalid/duplicate socket: ' + name)
        require(bone in self.rig.data.bones, 'Missing socket bone: ' + bone)
        obj = bpy.data.objects.new(name, None)
        self.scene.collection.objects.link(obj)
        obj.empty_display_type = 'PLAIN_AXES'
        obj.empty_display_size = 0.12
        obj.parent, obj.parent_type, obj.parent_bone = self.rig, 'BONE', bone
        bpy.context.view_layer.update()
        obj.matrix_world = Matrix.Translation(xyz(position))
        self.sockets[name] = obj
        return obj

    def pose(self, bone, location=(0, 0, 0), rotation=(0, 0, 0), scale=(1, 1, 1)):
        """Rest-relative pose using Godot axes; rotation in radians, scale in Godot axes."""
        p = self.rig.pose.bones[bone]
        rest = p.bone.matrix_local.to_3x3().to_4x4()
        delta = G2B @ xform(location, rotation, scale) @ B2G
        p.matrix_basis = rest.inverted() @ delta @ rest

    def bake_actions(self, durations, pose_callback):
        """Call pose_callback(builder, action, normalized_time) at every 120 Hz key."""
        require(set(durations) == set(ACTIONS), 'All eight standard actions are required')
        self.durations = dict(durations)
        for name in ACTIONS:
            frames = round(durations[name] * FPS)
            require(frames > 0 and abs(frames / FPS - durations[name]) < 1e-6,
                    'Action duration must land on a 120 Hz frame: ' + name)
            action = bpy.data.actions.new(name)
            self.rig.animation_data.action = action
            for frame in range(frames + 1):
                self.scene.frame_set(frame)
                for p in self.rig.pose.bones:
                    p.rotation_mode = 'QUATERNION'
                    p.matrix_basis = Matrix.Identity(4)
                pose_callback(self, name, frame / frames)
                for p in self.rig.pose.bones:
                    p.keyframe_insert('location', frame=frame, group=p.name)
                    p.keyframe_insert('rotation_quaternion', frame=frame, group=p.name)
                    p.keyframe_insert('scale', frame=frame, group=p.name)
            for layer in action.layers:
                for strip in layer.strips:
                    for bag in strip.channelbags:
                        for curve in bag.fcurves:
                            for key in curve.keyframe_points:
                                key.interpolation = 'LINEAR'
            require(len(action.slots) == 1, 'Expected one rig action slot: ' + name)
            self.rig.animation_data.action = None
            track = self.rig.animation_data.nla_tracks.new()
            track.name = name
            strip = track.strips.new(name, 0, action)
            strip.action_slot = action.slots[0]
            strip.action_frame_start, strip.action_frame_end = 0, frames
            track.mute = True
            action['loop'] = name == 'idle'
        self.reset_pose()

    def reset_pose(self):
        self.rig.animation_data.action = None
        for p in self.rig.pose.bones:
            p.matrix_basis = Matrix.Identity(4)
        self.scene.frame_set(0)
        bpy.context.view_layer.update()

    def _join(self):
        require(bool(self.objects), 'Boss has no geometry')
        bpy.ops.object.select_all(action='DESELECT')
        for obj in self.objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = self.objects[0]
        bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = self.kind + '__Body'
        obj.data.name = obj.name
        self.objects = [obj]
        return obj

    def _bake(self, obj, out_dir):
        P.pack_uvs([obj])
        written, _images = P.bake_channels(self.scene, [obj], self.kind, self.resolution, out_dir, log)
        mat = bpy.data.materials.new(self.kind + '_pbr')
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        p = nodes.get('Principled BSDF')
        for channel, path in written.items():
            image = bpy.data.images.get(self.kind + '_' + channel)
            if image is None:
                image = bpy.data.images.load(str(path), check_existing=False)
            # Godot prefixes extracted images with the GLB basename. Match it once,
            # so importing reuses these maps instead of creating a second loose set.
            image.name = 'surface_' + channel
            target = out_dir / (self.kind + '_surface_' + channel + '.png')
            path.replace(target)
            written[channel] = target
            image.filepath_raw = str(target)
            image.colorspace_settings.name = 'sRGB' if channel in ('albedo', 'emission') else 'Non-Color'
            image.pack()
            tex = nodes.new('ShaderNodeTexImage')
            tex.image = image
            if channel == 'albedo':
                links.new(tex.outputs['Color'], p.inputs['Base Color'])
            elif channel == 'emission':
                links.new(tex.outputs['Color'], p.inputs['Emission Color'])
                p.inputs['Emission Strength'].default_value = 1.0
            elif channel == 'normal':
                normal = nodes.new('ShaderNodeNormalMap')
                links.new(tex.outputs['Color'], normal.inputs['Color'])
                links.new(normal.outputs[0], p.inputs['Normal'])
            else:
                sep = nodes.new('ShaderNodeSeparateColor')
                links.new(tex.outputs['Color'], sep.inputs[0])
                links.new(sep.outputs['Green'], p.inputs['Roughness'])
                links.new(sep.outputs['Blue'], p.inputs['Metallic'])
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        for polygon in obj.data.polygons:
            polygon.material_index = 0
        return written

    def export(self, out_dir):
        """out_dir is the family root; writes <out_dir>/<kind>/<kind>.*."""
        require(set(self.sockets) == set(SOCKETS), 'All ten sockets are required')
        require(set(self.durations) == set(ACTIONS), 'Bake actions before exporting')
        self.reset_pose()
        obj = self._join()
        out_dir = Path(out_dir).resolve() / self.kind
        out_dir.mkdir(parents=True, exist_ok=True)
        textures = {} if self.quick else self._bake(obj, out_dir)
        path = out_dir / (self.kind + '.glb')
        bpy.ops.object.select_all(action='DESELECT')
        for item in [self.rig, obj, *self.sockets.values()]:
            item.select_set(True)
        bpy.context.view_layer.objects.active = self.rig
        result = bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
            export_animations=True, export_animation_mode='ACTIONS', export_frame_range=False,
            export_force_sampling=True, export_extras=True, export_yup=True, export_image_format='AUTO')
        require('FINISHED' in result and path.is_file(), 'GLB export failed')
        payload, chunks = read_glb(path)
        # Blender names embedded images from their filepath, ignoring datablock names.
        # Godot adds the model basename on extraction, so keep only the atlas suffix.
        for image in payload.get('images', []):
            prefix = self.kind + '_'
            if image.get('name', '').startswith(prefix):
                image['name'] = image['name'][len(prefix):]
        binary = next(data for kind, data in chunks if kind == 0x004e4942)
        images = consolidate_atlases(payload, binary)
        encode_rest_positions(payload, chunks)
        animations = [a.get('name') for a in payload.get('animations', [])]
        require(len(animations) == len(ACTIONS) and set(animations) == set(ACTIONS),
                'Exported actions differ: ' + str(animations))
        require(len(payload.get('skins', [])) == 1, 'Expected one skin')
        require(len(payload.get('meshes', [])) == 1, 'Expected one merged skinned mesh')
        nodes = payload['nodes']
        for name in SOCKETS:
            require(sum(node.get('name') == name for node in nodes) == 1, 'Missing/duplicate socket: ' + name)
        primitives = [p for mesh in payload['meshes'] for p in mesh['primitives']]
        triangles = 0
        for primitive in primitives:
            require(primitive.get('mode', 4) == 4, 'Expected triangles')
            require('JOINTS_0' in primitive['attributes'] and 'WEIGHTS_0' in primitive['attributes'],
                    'Unskinned primitive')
            count = payload['accessors'][primitive['indices']]['count']
            require(count % 3 == 0, 'Invalid index count')
            triangles += count // 3
        census = dict(triangles=triangles, materials=len(payload.get('materials', [])),
                      bones=len(payload['skins'][0]['joints']), surfaces=len(primitives))
        for key, cap in BUDGET['limits'].items():
            require(0 < census[key] <= cap, '%s budget exceeded: %s > %s' % (key, census[key], cap))
        require(self.quick or len(images) == 4, 'Baked GLB must carry albedo, ORM, normal, emission')
        # Include every shared source that can change geometry, shading or the export census.
        sources = [self.recipe_path, Path(__file__), HERE / 'bosses_budget.json',
                   HERE.parent / 'glb_atlas.py', HERE.parent / 'props' / 'props_kit.py']
        hashes = {str(p.relative_to(HERE.parent.parent.parent)): sha(p) for p in sources}
        provenance = dict(seed=self.seed, recipe_revision=self.revision, kit_revision=RECIPE_REVISION,
                          source_hashes=hashes, kind=self.kind,
                          rest_position_encoding='TEXCOORD_1.xy,TEXCOORD_2.x;TEXCOORD_2.y=1')
        payload['asset']['extras'] = provenance
        write_glb(path, payload, chunks)
        report = dict(**provenance, **census, blender=bpy.app.version_string,
                      quick=self.quick, animation_sample_rate=FPS, actions=list(ACTIONS),
                      sockets=list(SOCKETS), bone_names=[b.name for b in self.rig.data.bones],
                      action_seconds=self.durations, budget=BUDGET['limits'], image_report=images,
                      textures={k: {'file': p.name, 'sha256': sha(p)} for k, p in textures.items()},
                      glb={'file': path.name, 'sha256': sha(path), 'bytes': path.stat().st_size})
        path.with_suffix('.build.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
        # Supply import settings before the editor's first scan. Existing imports keep their UID.
        import_path = Path(str(path) + '.import')
        if not import_path.exists():
            import_path.write_text('[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
                'animation/import=true\nanimation/fps=120\nanimation/trimming=false\n'
                'animation/remove_immutable_tracks=true\nanimation/import_rest_as_RESET=false\n'
                'skins/use_named_skins=true\n_subresources={"nodes": {"PATH:AnimationPlayer": {"optimizer/enabled": false}}}\n')
        # Float rest coordinates must not be quantized by Godot's mesh compression.
        import_text = import_path.read_text()
        setting = 'meshes/force_disable_compression=true'
        if re.search(r'^meshes/force_disable_compression=.*$', import_text, flags=re.MULTILINE):
            import_text = re.sub(r'^meshes/force_disable_compression=.*$', setting, import_text, flags=re.MULTILINE)
        else:
            import_text += setting + '\n'
        import_path.write_text(import_text)
        for texture_path in textures.values():
            texture_import = Path(str(texture_path) + '.import')
            text = texture_import.read_text() if texture_import.exists() else (
                '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n')
            # Compatibility uses lossless atlases, including after the 3D-detection pass.
            for key, value in {'compress/mode': '0', 'detect_3d/compress_to': '0',
                               'mipmaps/generate': 'true'}.items():
                pattern = r'^' + re.escape(key) + r'=.*$'
                if re.search(pattern, text, flags=re.MULTILINE):
                    text = re.sub(pattern, key + '=' + value, text, flags=re.MULTILINE)
                else:
                    text += key + '=' + value + '\n'
            texture_import.write_text(text)
        log('EXPORT OK kind=%s tris=%d materials=%d bones=%d surfaces=%d actions=%d sockets=%d' %
            (self.kind, triangles, census['materials'], census['bones'], census['surfaces'], len(animations), len(SOCKETS)))
        return report
