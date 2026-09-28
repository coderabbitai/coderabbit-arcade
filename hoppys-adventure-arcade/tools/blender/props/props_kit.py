"""Shared modelling, material and bake helpers for the runner hero props.

Adapted from tools/blender/build_hoppy.py (ellipsoid / tube / box / loft helpers and its channel
bake), which stays owned by the Hoppy build. Deterministic: no randomness except the caller's seeded
`random.Random`, no downloaded assets, no fonts, no boolean operations.

Modelling coordinates are Godot coordinates (x right, y up, z towards the camera). Each primitive is
built in its own temporary bmesh, transformed in that frame and appended to its Part; a Part is
converted to Blender's Z-up frame once, when it becomes a mesh object.
"""
import math

import bmesh
import bpy
import numpy
from mathutils import Euler, Matrix, Vector

# Godot (x, y, z) -> Blender (x, -z, y): a proper rotation (+90 degrees about X).
G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
B2G = G2B.inverted()


def require(condition, message):
    if not condition:
        raise RuntimeError('[props] ' + message)


def linear(hex_colour):
    """Palette sRGB hex -> linear RGB (Blender colour sockets are linear)."""
    hex_colour = hex_colour.lstrip('#')
    out = []
    for i in range(3):
        c = int(hex_colour[i * 2:i * 2 + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def xform(pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), order='XYZ'):
    """Godot-frame 4x4: translate * rotate (euler, radians; 'XYZ' applies X first) * scale."""
    if isinstance(scale, (int, float)):
        scale = (scale, scale, scale)
    s = Matrix.Diagonal(Vector((scale[0], scale[1], scale[2], 1.0)))
    return Matrix.Translation(Vector(pos)) @ Euler(rot, order).to_matrix().to_4x4() @ s


def to_blender(matrix):
    return G2B @ matrix @ B2G


def _bevel(bm, width, segments):
    edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0.0) > 0.6]
    if edges and width > 0:
        bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segments, profile=0.5,
                        affect='EDGES', clamp_overlap=True)


class Part:
    """One output mesh (a merged static body or an instancing template) with material slots."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.finishes = []

    def slot(self, finish):
        if finish not in self.finishes:
            self.finishes.append(finish)
        return self.finishes.index(finish)

    def _merge(self, tmp, finish, matrix):
        if matrix is not None:
            bmesh.ops.transform(tmp, matrix=matrix, verts=tmp.verts)
            if matrix.to_3x3().determinant() < 0:
                bmesh.ops.reverse_faces(tmp, faces=tmp.faces)
        index = self.slot(finish)
        for f in tmp.faces:
            f.material_index = index
        mesh = bpy.data.meshes.new('props_tmp')
        tmp.to_mesh(mesh)
        tmp.free()
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)

    # --- primitives (all centred on the origin before `matrix`) ---------------------------------
    def box(self, finish, size, matrix=None, bevel=0.0, segments=2):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        _bevel(tmp, min(bevel, min(size) * 0.45), segments)
        self._merge(tmp, finish, matrix)

    def cylinder(self, finish, radius, depth, matrix=None, segments=16, radius_top=None, bevel=0.0):
        """Axis along Godot +Y."""
        tmp = bmesh.new()
        top = radius if radius_top is None else radius_top
        bmesh.ops.create_cone(tmp, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=radius, radius2=top, depth=depth)
        bmesh.ops.rotate(tmp, verts=tmp.verts, cent=Vector(), matrix=Matrix.Rotation(-math.pi / 2, 3, 'X'))
        _bevel(tmp, min(bevel, depth * 0.4, radius * 0.4), 1)
        self._merge(tmp, finish, matrix)

    def ellipsoid(self, finish, radii, matrix=None, u=16, v=10, shape=None):
        tmp = bmesh.new()
        bmesh.ops.create_uvsphere(tmp, u_segments=u, v_segments=v, radius=1.0)
        bmesh.ops.rotate(tmp, verts=tmp.verts, cent=Vector(), matrix=Matrix.Rotation(-math.pi / 2, 3, 'X'))
        for vert in tmp.verts:
            co = vert.co.copy()
            if shape is not None:
                co = Vector(shape(co))
            vert.co = Vector((co.x * radii[0], co.y * radii[1], co.z * radii[2]))
        self._merge(tmp, finish, matrix)

    def prism(self, finish, outline, depth, matrix=None, bevel=0.0, segments=1):
        """Extrude an XY outline (any winding) along Z, centred on z = 0."""
        area = sum(outline[i][0] * outline[(i + 1) % len(outline)][1] -
                   outline[(i + 1) % len(outline)][0] * outline[i][1] for i in range(len(outline)))
        if area < 0:
            outline = list(reversed(outline))
        tmp = bmesh.new()
        front = [tmp.verts.new((x, y, depth / 2)) for x, y in outline]
        back = [tmp.verts.new((x, y, -depth / 2)) for x, y in outline]
        n = len(outline)
        tmp.faces.new(front)
        tmp.faces.new(list(reversed(back)))
        for i in range(n):
            j = (i + 1) % n
            tmp.faces.new((back[i], back[j], front[j], front[i]))
        bmesh.ops.triangulate(tmp, faces=[f for f in tmp.faces if len(f.verts) > 4], quad_method='BEAUTY',
                              ngon_method='EAR_CLIP')
        _bevel(tmp, bevel, segments)
        self._merge(tmp, finish, matrix)

    def tube(self, finish, points, radius, matrix=None, sides=8, radius_end=None, caps=True):
        """Ring swept along a polyline with parallel transport (Hoppy tube(), meshed directly)."""
        tmp = bmesh.new()
        pts = [Vector(p) for p in points]
        radius_end = radius if radius_end is None else radius_end
        tangent = (pts[1] - pts[0]).normalized()
        normal = tangent.orthogonal().normalized()
        rings = []
        for k, p in enumerate(pts):
            nxt = pts[min(k + 1, len(pts) - 1)]
            prv = pts[max(k - 1, 0)]
            t_new = (nxt - prv).normalized()
            axis = tangent.cross(t_new)
            if axis.length > 1e-7:
                normal = Matrix.Rotation(tangent.angle(t_new), 3, axis.normalized()) @ normal
            tangent = t_new
            binormal = tangent.cross(normal).normalized()
            r = radius + (radius_end - radius) * (k / max(1, len(pts) - 1))
            rings.append([tmp.verts.new(p + (normal * math.cos(math.tau * s / sides) +
                                             binormal * math.sin(math.tau * s / sides)) * r)
                          for s in range(sides)])
        for a, b in zip(rings, rings[1:]):
            for s in range(sides):
                t = (s + 1) % sides
                tmp.faces.new((a[s], a[t], b[t], b[s]))
        if caps and radius > 1e-5:
            tmp.faces.new(list(reversed(rings[0])))
        if caps and radius_end > 1e-5:
            tmp.faces.new(rings[-1])
        bmesh.ops.remove_doubles(tmp, verts=tmp.verts, dist=1e-6)
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
        self._merge(tmp, finish, matrix)

    def lathe(self, finish, profile, matrix=None, segments=16, cap_top=True, cap_bottom=True):
        """Revolve (radius, y) rows about Godot Y (a rotational Hoppy loft())."""
        tmp = bmesh.new()
        rings = []
        for r, y in profile:
            rings.append([tmp.verts.new((r * math.cos(math.tau * s / segments), y,
                                         -r * math.sin(math.tau * s / segments)))
                          for s in range(segments)])
        for a, b in zip(rings, rings[1:]):
            for s in range(segments):
                t = (s + 1) % segments
                tmp.faces.new((a[s], a[t], b[t], b[s]))
        if cap_bottom:
            tmp.faces.new(list(reversed(rings[0])))
        if cap_top:
            tmp.faces.new(rings[-1])
        bmesh.ops.remove_doubles(tmp, verts=tmp.verts, dist=1e-6)
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
        self._merge(tmp, finish, matrix)

    def arc_points(self, major, start, end, segments):
        return [(major * math.sin(start + (end - start) * k / segments), 0.0,
                 major * math.cos(start + (end - start) * k / segments)) for k in range(segments + 1)]

    def ribbon(self, finish, path, heights, thickness, matrix=None):
        """Upright band along a Godot-frame path (bottom edge on the path); per-point top heights."""
        tmp = bmesh.new()
        pts = [Vector(p) for p in path]
        loops = []
        for k, p in enumerate(pts):
            tangent = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
            side = tangent.cross(Vector((0, 1, 0))).normalized() * (thickness / 2)
            h = Vector((0, heights[k], 0))
            loops.append([tmp.verts.new(p - side), tmp.verts.new(p + side),
                          tmp.verts.new(p + side + h), tmp.verts.new(p - side + h)])
        for a, b in zip(loops, loops[1:]):
            for i in range(4):
                j = (i + 1) % 4
                tmp.faces.new((a[i], b[i], b[j], a[j]))
        tmp.faces.new(list(reversed(loops[0])))
        tmp.faces.new(loops[-1])
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
        self._merge(tmp, finish, matrix)

    def ring(self, finish, major, minor, matrix=None, segments=24, sides=6):
        """Closed torus in the Godot XZ plane."""
        tmp = bmesh.new()
        rings = []
        for k in range(segments):
            a = math.tau * k / segments
            centre = Vector((major * math.sin(a), 0, major * math.cos(a)))
            radial = centre.normalized()
            rings.append([tmp.verts.new(centre + (radial * math.cos(math.tau * s / sides) +
                                                  Vector((0, 1, 0)) * math.sin(math.tau * s / sides)) * minor)
                          for s in range(sides)])
        for k in range(segments):
            a, b = rings[k], rings[(k + 1) % segments]
            for s in range(sides):
                t = (s + 1) % sides
                tmp.faces.new((a[s], a[t], b[t], b[s]))
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
        self._merge(tmp, finish, matrix)

    # --- finishing -----------------------------------------------------------------------------
    def triangles(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def bounds(self):
        xs = [v.co for v in self.bm.verts]
        lo = Vector((min(c.x for c in xs), min(c.y for c in xs), min(c.z for c in xs)))
        hi = Vector((max(c.x for c in xs), max(c.y for c in xs), max(c.z for c in xs)))
        return lo, hi

    def to_object(self, collection, materials, sharp_angle=0.62):
        bm = self.bm
        # Cone tips and lathe poles collapse to points: weld them and drop zero-area faces.
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method='BEAUTY',
                              ngon_method='EAR_CLIP')
        # Collinear outline points can leave zero-area slivers (no UV area): remove them.
        slivers = [f for f in bm.faces if f.calc_area() < 1e-7]
        if slivers:
            bmesh.ops.delete(bm, geom=slivers, context='FACES_ONLY')
        bmesh.ops.transform(bm, matrix=G2B, verts=bm.verts)
        for f in bm.faces:
            f.smooth = True
        for e in bm.edges:
            e.smooth = e.is_manifold and e.calc_face_angle(0.0) <= sharp_angle
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for finish in self.finishes:
            mesh.materials.append(materials[finish])
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        return obj


def empty(collection, name, matrix=None, parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_basis = to_blender(matrix or Matrix.Identity(4))
    return obj


def instance(collection, name, template, matrix=None, parent=None):
    """Linked duplicate: shares the template's mesh datablock (one glTF mesh, many nodes)."""
    obj = bpy.data.objects.new(name, template.data)
    collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_basis = to_blender(matrix or Matrix.Identity(4))
    return obj


def place(obj, matrix=None, parent=None):
    obj.parent = parent
    obj.matrix_basis = to_blender(matrix or Matrix.Identity(4))
    return obj


def mesh_triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# --- procedural node materials ----------------------------------------------------------------
class Nodes:
    def __init__(self, material):
        self.n = material.node_tree.nodes
        self.l = material.node_tree.links

    def _in(self, socket, value):
        if isinstance(value, (int, float)):
            socket.default_value = value
        elif isinstance(value, tuple):
            socket.default_value = tuple(value) + (1.0,) if len(value) == 3 else value
        else:
            self.l.new(value, socket)

    def math(self, op, a, b=None, clamp=False):
        node = self.n.new('ShaderNodeMath')
        node.operation = op
        node.use_clamp = clamp
        self._in(node.inputs[0], a)
        if b is not None:
            self._in(node.inputs[1], b)
        return node.outputs[0]

    def band(self, value, low, high):
        node = self.n.new('ShaderNodeMapRange')
        node.interpolation_type = 'SMOOTHSTEP'
        node.clamp = True
        node.inputs['From Min'].default_value = low
        node.inputs['From Max'].default_value = high
        self._in(node.inputs['Value'], value)
        return node.outputs['Result']

    def coords(self):
        tex = self.n.new('ShaderNodeTexCoord')
        split = self.n.new('ShaderNodeSeparateXYZ')
        self.l.new(tex.outputs['Object'], split.inputs[0])
        # Godot frame: x = X, y = Blender Z, z = -Blender Y.
        return (tex.outputs['Object'], split.outputs['X'], split.outputs['Z'],
                self.math('MULTIPLY', split.outputs['Y'], -1.0))

    def noise(self, vector, scale, detail=3.0, roughness=0.55):
        node = self.n.new('ShaderNodeTexNoise')
        node.inputs['Scale'].default_value = scale
        node.inputs['Detail'].default_value = detail
        node.inputs['Roughness'].default_value = roughness
        self.l.new(vector, node.inputs['Vector'])
        return node.outputs['Fac']

    def voronoi_edge(self, vector, scale):
        node = self.n.new('ShaderNodeTexVoronoi')
        node.feature = 'DISTANCE_TO_EDGE'
        node.inputs['Scale'].default_value = scale
        self.l.new(vector, node.inputs['Vector'])
        return node.outputs['Distance']

    def mix(self, fac, a, b):
        node = self.n.new('ShaderNodeMixRGB')
        node.blend_type = 'MIX'
        self._in(node.inputs['Factor'], fac)
        self._in(node.inputs['Color1'], a)
        self._in(node.inputs['Color2'], b)
        return node.outputs['Color']

    def scale_colour(self, colour, factor):
        node = self.n.new('ShaderNodeMixRGB')
        node.blend_type = 'MULTIPLY'
        node.inputs['Factor'].default_value = 1.0
        self._in(node.inputs['Color1'], colour)
        if isinstance(factor, (int, float)):
            node.inputs['Color2'].default_value = (factor, factor, factor, 1.0)
        else:
            grey = self.n.new('ShaderNodeCombineColor')
            for channel in ('Red', 'Green', 'Blue'):
                self.l.new(factor, grey.inputs[channel])
            self.l.new(grey.outputs[0], node.inputs['Color2'])
        return node.outputs['Color']

    def pointiness(self):
        return self.n.new('ShaderNodeNewGeometry').outputs['Pointiness']

    def seams(self, axis_value, period, width=0.006):
        """1 inside a panel, falling to 0 along a seam every `period` metres."""
        cell = self.math('FRACT', self.math('DIVIDE', axis_value, period))
        dist = self.math('MULTIPLY', self.math('ABSOLUTE', self.math('SUBTRACT', cell, 0.5)), period)
        return self.band(self.math('SUBTRACT', period * 0.5, dist), width * 0.4, width)


RECIPES = {}


def make_finish(name, spec):
    """Procedural finish. spec keys: base, rough, metal, kind, emit, emit_strength, bump, ...
    Returns the material; RECIPES[name] records the albedo/emission sockets for the channel bakes."""
    material = bpy.data.materials.new(name)
    nodes = Nodes(material)
    p = nodes.n.get('Principled BSDF')
    require(p is not None, 'Default Principled BSDF missing: ' + name)
    vector, x, y, z = nodes.coords()
    base = spec['base']
    kind = spec.get('kind', 'paint')
    grunge = nodes.noise(vector, spec.get('grunge_scale', 7.0), 4.0)
    height = nodes.math('MULTIPLY', grunge, spec.get('grunge_height', 0.25))
    colour = nodes.scale_colour(base, nodes.math('ADD', 1.0 - spec.get('grunge', 0.18),
                                                  nodes.math('MULTIPLY', grunge, spec.get('grunge', 0.18) * 1.6)))
    if kind in ('paint', 'shell', 'legacy', 'lines'):
        period = spec.get('period', 0.6)
        panel = nodes.math('MULTIPLY', nodes.seams(x, period), nodes.seams(y, period * 0.62))
        panel = nodes.math('MULTIPLY', panel, nodes.seams(z, period * 1.3))
        height = nodes.math('ADD', height, nodes.math('MULTIPLY', panel, 0.9))
        colour = nodes.mix(nodes.math('SUBTRACT', 1.0, panel), colour, nodes.scale_colour(base, 0.35))
    if kind in ('paint', 'shell', 'lines'):
        wear = nodes.band(nodes.pointiness(), 0.53, 0.62)
        colour = nodes.mix(nodes.math('MULTIPLY', wear, spec.get('wear', 0.4)), colour,
                           spec.get('wear_colour', (0.55, 0.60, 0.64)))
    if kind == 'legacy':
        crack = nodes.math('SUBTRACT', 1.0, nodes.band(nodes.voronoi_edge(vector, 4.0), 0.0, 0.035))
        height = nodes.math('SUBTRACT', height, nodes.math('MULTIPLY', crack, 0.8))
        colour = nodes.mix(crack, colour, nodes.scale_colour(base, 0.22))
    if kind == 'stripe':
        diag = nodes.math('FRACT', nodes.math('MULTIPLY', nodes.math('ADD', x, nodes.math('ADD', y, z)),
                                              spec.get('stripes', 5.0)))
        on = nodes.band(nodes.math('ABSOLUTE', nodes.math('SUBTRACT', diag, 0.5)), 0.23, 0.27)
        colour = nodes.mix(on, spec['stripe_colour'], colour)
    if kind == 'rubber':
        tread = nodes.math('SINE', nodes.math('MULTIPLY', x, spec.get('tread', 40.0)))
        height = nodes.math('ADD', height, nodes.math('MULTIPLY', tread, 0.5))
    if kind == 'lines':
        axis = {'x': x, 'y': y, 'z': z}[spec.get('line_axis', 'y')]
        across = {'x': x, 'y': y, 'z': z}[spec.get('along_axis', 'x')]
        row = nodes.math('FRACT', nodes.math('MULTIPLY', axis, spec.get('rows', 14.0)))
        on_row = nodes.band(nodes.math('SUBTRACT', 0.5, nodes.math('ABSOLUTE', nodes.math('SUBTRACT', row, 0.5))),
                            0.28, 0.34)
        seg = nodes.noise(vector, spec.get('segment_scale', 2.5), 0.0)
        cut = nodes.band(nodes.math('SINE', nodes.math('MULTIPLY', across, spec.get('dash', 9.0))), -0.4, -0.3)
        ink = nodes.math('MULTIPLY', nodes.math('MULTIPLY', on_row, nodes.band(seg, 0.38, 0.42)), cut)
        colour = nodes.mix(ink, colour, spec.get('ink', (0.9, 0.78, 0.6)))
        height = nodes.math('ADD', height, nodes.math('MULTIPLY', ink, 0.5))
    emit = spec.get('emit', (0.0, 0.0, 0.0))
    emission = nodes.scale_colour(emit, spec.get('emit_strength', 0.0))
    if spec.get('emit_mask') == 'scan':
        scan = nodes.band(nodes.math('SINE', nodes.math('MULTIPLY', y, spec.get('scan_rows', 60.0))), 0.1, 0.8)
        emission = nodes.scale_colour(emission, scan)
    if spec.get('emit_mask') == 'rise':
        emission = nodes.scale_colour(emission, nodes.band(y, spec.get('rise_from', 0.0), spec.get('rise_to', 0.2)))
    if spec.get('emit_mask') == 'veins':
        veins = nodes.math('SUBTRACT', 1.0, nodes.band(nodes.voronoi_edge(vector, 9.0), 0.0, 0.05))
        emission = nodes.scale_colour(emission, veins)
        colour = nodes.mix(nodes.math('MULTIPLY', veins, 0.6), colour, spec.get('vein_colour', base))
    nodes.l.new(colour, p.inputs['Base Color'])
    p.inputs['Roughness'].default_value = spec.get('rough', 0.45)
    p.inputs['Metallic'].default_value = spec.get('metal', 0.5)
    nodes.l.new(emission, p.inputs['Emission Color'])
    p.inputs['Emission Strength'].default_value = 1.0
    bump = nodes.n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = spec.get('bump', 0.35)
    bump.inputs['Distance'].default_value = spec.get('bump_distance', 0.003)
    nodes.l.new(height, bump.inputs['Height'])
    bevel = nodes.n.new('ShaderNodeBevel')
    bevel.samples = 4
    bevel.inputs['Radius'].default_value = spec.get('bevel', 0.006)
    nodes.l.new(bevel.outputs['Normal'], bump.inputs['Normal'])
    nodes.l.new(bump.outputs['Normal'], p.inputs['Normal'])
    RECIPES[material.name] = {'albedo': colour, 'emission': emission,
                              'rough': float(spec.get('rough', 0.45)), 'metal': float(spec.get('metal', 0.5))}
    return material


# --- UV packing and channel bakes --------------------------------------------------------------
def pack_uvs(objects, weights=None, margin=0.003):
    """Joint smart projection of every template, then one shared pack. `weights` scales an object's
    texel density (hero surfaces seen up close get more of the atlas than long structural members)."""
    # Unwrap one object at a time, then pack jointly. Geometry, layout and recipes are
    # bit-reproducible; Blender's unwrap / pack solvers are not (measured: UV coordinates drift
    # between identical runs), so atlas bytes may differ per rebuild. Checks pin properties.
    for obj in objects:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=margin, area_weight=0.0,
                                 scale_to_bounds=False)
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    for obj in objects:
        w = (weights or {}).get(obj.data.name, 1.0)
        if w != 1.0:
            for item in obj.data.uv_layers.active.data:
                item.uv = item.uv * w
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(rotate=True, margin=margin, shape_method='CONCAVE')
    bpy.ops.object.mode_set(mode='OBJECT')
    for obj in objects:
        require(bool(obj.data.uv_layers), 'No UV layer: ' + obj.name)


def bake_channels(scene, objects, prefix, resolution, out_dir, log, ao_floor=0.35):
    """Bake albedo / emission / roughness-metal / normal / AO for `objects` into shared atlases.
    Returns {channel: Path}. ORM = (baked AO, roughness, metallic)."""
    materials = []
    for obj in objects:
        for m in obj.data.materials:
            if m not in materials:
                materials.append(m)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    images = {}
    for channel in ('albedo', 'emission', 'rm', 'normal', 'ao'):
        log('bake %s/%s' % (prefix, channel))
        image = bpy.data.images.new(prefix + '_' + channel, resolution, resolution, alpha=False)
        image.colorspace_settings.name = 'sRGB' if channel in ('albedo', 'emission') else 'Non-Color'
        undo = []
        for m in materials:
            n, l = m.node_tree.nodes, m.node_tree.links
            target = n.new('ShaderNodeTexImage')
            target.image = image
            n.active = target
            emit = None
            if channel in ('albedo', 'emission', 'rm'):
                recipe = RECIPES[m.name]
                emit = n.new('ShaderNodeEmission')
                if channel == 'albedo':
                    l.new(recipe['albedo'], emit.inputs['Color'])
                elif channel == 'emission':
                    l.new(recipe['emission'], emit.inputs['Color'])
                else:
                    emit.inputs['Color'].default_value = (0.0, recipe['rough'], recipe['metal'], 1.0)
                l.new(emit.outputs[0], n['Material Output'].inputs['Surface'])
            undo.append((m, target, emit))
        scene.cycles.samples = 24 if channel == 'ao' else (8 if channel == 'normal' else 2)
        scene.render.bake.margin = 6
        scene.render.bake.margin_type = 'EXTEND'
        scene.render.bake.use_selected_to_active = False
        kind = {'normal': 'NORMAL', 'ao': 'AO'}.get(channel, 'EMIT')
        require('FINISHED' in bpy.ops.object.bake(type=kind), 'Bake failed: %s/%s' % (prefix, channel))
        for m, target, emit in undo:
            n, l = m.node_tree.nodes, m.node_tree.links
            l.new(n['Principled BSDF'].outputs[0], n['Material Output'].inputs['Surface'])
            n.remove(target)
            if emit is not None:
                n.remove(emit)
        images[channel] = image
    size = resolution * resolution * 4
    def pixels(image):
        data = numpy.empty(size, dtype=numpy.float32)
        image.pixels.foreach_get(data)
        return data.reshape(resolution, resolution, 4)
    rm = pixels(images['rm'])
    ao = pixels(images['ao'])
    orm = numpy.ones_like(rm)
    # Soft occlusion: keeps contact darkening without crushing the dark hazard hulls.
    orm[..., 0] = ao_floor + (1.0 - ao_floor) * ao[..., 0]
    orm[..., 1] = rm[..., 1]
    orm[..., 2] = rm[..., 2]
    covered = rm[..., 1] > 0.0
    orm[..., 1][~covered] = 0.5
    orm[..., 2][~covered] = 0.0
    orm[..., 0][~covered] = 1.0
    orm_image = bpy.data.images.new(prefix + '_orm', resolution, resolution, alpha=False)
    orm_image.colorspace_settings.name = 'Non-Color'
    orm_image.pixels.foreach_set(orm.ravel())
    written = {}
    for channel, image in (('albedo', images['albedo']), ('emission', images['emission']),
                           ('normal', images['normal']), ('orm', orm_image)):
        path = out_dir / ('%s_%s.png' % (prefix, channel))
        image.filepath_raw = str(path)
        image.file_format = 'PNG'
        image.save()
        require(path.is_file() and path.stat().st_size > 0, 'PNG save failed: ' + str(path))
        written[channel] = path
    return written, images
