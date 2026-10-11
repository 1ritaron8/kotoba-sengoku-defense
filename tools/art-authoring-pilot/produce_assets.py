"""Blender-only bounded asset production. HQ executes; no install/game writes.

blender --background --disable-autoexec --python-exit-code 2 --python produce_assets.py
    -- --workshop PATH --run EXISTING_PREPARED_RUN [--correction]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import shutil
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

KIT = Path(__file__).resolve().parent
WORK = KIT / 'work'
PROJECT = KIT.parent.parent
REFERENCE_SHA = '1beb10363b3e396eb581f6625b31be32bffb960f3d77ec785bbacef342e5d2cc'
ROOT_NAMES = ['Broadleaf_A', 'Broadleaf_B', 'Broadleaf_C', 'Shrub_A', 'Shrub_B',
              'FiringPad', 'Palisade', 'GroundSample']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    with Path(path).open('x', encoding='utf-8', newline='\n') as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, allow_nan=False)


def contained(path, parent):
    path, parent = Path(path).resolve(), Path(parent).resolve()
    if path == parent or not path.is_relative_to(parent):
        raise ValueError(f'Expected child of {parent}: {path}')
    return path


class Geometry:
    """Shared vertices, per-loop UVs and material faces; no object-per-leaf cost."""
    def __init__(self):
        self.vertices, self.faces, self.uvs, self.materials = [], [], [], []

    def vertex(self, point):
        self.vertices.append(tuple(point))
        return len(self.vertices) - 1

    def face(self, indices, uvs, material=0):
        self.faces.append(tuple(indices))
        self.uvs.append(uvs)
        self.materials.append(material)

    def tube(self, points, radii, sides=6, material=0):
        points = [Vector(p) for p in points]
        rings, distances = [], [0.0]
        for i, point in enumerate(points):
            tangent = points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]
            tangent.normalize()
            helper = Vector((0, 0, 1)) if abs(tangent.z) < .93 else Vector((1, 0, 0))
            right = tangent.cross(helper).normalized()
            up = tangent.cross(right).normalized()
            rings.append([self.vertex(point + radii[i] * (math.cos(a * math.tau / sides) * right + math.sin(a * math.tau / sides) * up)) for a in range(sides)])
            if i:
                distances.append(distances[-1] + (points[i] - points[i - 1]).length)
        for i in range(len(rings) - 1):
            for j in range(sides):
                k = (j + 1) % sides
                self.face((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]),
                          ((j / sides, distances[i]), ((j + 1) / sides, distances[i]),
                           ((j + 1) / sides, distances[i + 1]), (j / sides, distances[i + 1])), material)
        self.face(tuple(reversed(rings[0])), [(0.5 + .5 * math.cos(j * math.tau / sides), .5 + .5 * math.sin(j * math.tau / sides)) for j in reversed(range(sides))], material)
        self.face(rings[-1], [(0.5 + .5 * math.cos(j * math.tau / sides), .5 + .5 * math.sin(j * math.tau / sides)) for j in range(sides)], material)

    def leaf(self, center, direction, length, width, tilt, tile):
        long = Vector(direction).normalized()
        helper = Vector((0, 0, 1))
        across = long.cross(helper)
        if across.length < .001:
            across = Vector((1, 0, 0))
        across.normalize()
        normal = across.cross(long).normalized()
        across = across * math.cos(tilt) + normal * math.sin(tilt)
        normal = long.cross(across).normalized()
        center = Vector(center)
        points = [center - long * length * .5, center - across * width * .5,
                  center + long * length * .5, center + across * width * .5,
                  center + normal * width * .11]
        ids = [self.vertex(p) for p in points]
        # Actual folded diamond leaf geometry; opaque texture, double-sided PBR.
        coords = [(0.5, .04), (.04, .48), (.5, .96), (.96, .48), (.5, .5)]
        offset = ((tile % 2) * .5, (tile // 2) * .5)
        uv = [(offset[0] + x * .5, offset[1] + y * .5) for x, y in coords]
        for i in range(4):
            self.face((ids[i], ids[(i + 1) % 4], ids[4]), (uv[i], uv[(i + 1) % 4], uv[4]), 1)

    def mesh(self, name, collection, materials, parent=None):
        mesh = bpy.data.meshes.new(name + '_Mesh')
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        uv = mesh.uv_layers.new(name='UVMap')
        for face, coordinates, material in zip(mesh.polygons, self.uvs, self.materials):
            face.material_index = material
            face.use_smooth = material == 0 and len(face.vertices) == 4
            for loop, point in zip(face.loop_indices, coordinates):
                uv.data[loop].uv = point
        for material in materials:
            mesh.materials.append(material)
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        obj.parent = parent
        obj['collision_policy'] = 'VISUAL_ONLY_NO_AUTOMATIC_COLLISION'
        return obj


def collection(name):
    existing = bpy.data.collections.get(name)
    if existing:
        return existing
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


def empty(name, owner):
    obj = bpy.data.objects.new(name, None)
    owner.objects.link(obj)
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = .18
    obj['origin_contract'] = 'LOCAL_BASE;BlenderZup;GLBGodotYup;metres;identityscale'
    obj['collision_policy'] = 'VISUAL_ONLY;retain_authoritative_gameplay_provider'
    return obj


def triangulate_export(obj):
    """Triangulate only export data; authoring masters retain their original faces/UVs."""
    work = bmesh.new()
    try:
        work.from_mesh(obj.data)
        bmesh.ops.triangulate(work, faces=list(work.faces), quad_method='BEAUTY', ngon_method='BEAUTY')
        work.to_mesh(obj.data)
    finally:
        work.free()
    obj.data.update()
    if any(len(face.vertices) != 3 for face in obj.data.polygons):
        raise ValueError('Export triangulation incomplete: ' + obj.name)
    obj['export_triangulated'] = True


def load_texture(source, destination, noncolor=False):
    source, destination = Path(source), Path(destination)
    if not source.is_file():
        raise FileNotFoundError(source)
    shutil.copyfile(source, destination)
    image = bpy.data.images.load(str(destination), check_existing=False)
    if noncolor:
        image.colorspace_settings.name = 'Non-Color'
    image.pack()
    return image


def pbr(name, color, normal=None, rough=None, double_sided=False):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = not double_sided
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = .94
    bsdf.inputs['Metallic'].default_value = 0.0
    if bsdf.inputs.get('Specular IOR Level'):
        bsdf.inputs['Specular IOR Level'].default_value = .16
    base = nodes.new('ShaderNodeTexImage')
    base.image, base.label = color, 'Portable image base color'
    links.new(base.outputs['Color'], bsdf.inputs['Base Color'])
    if normal:
        texture = nodes.new('ShaderNodeTexImage'); texture.image = normal
        mapping = nodes.new('ShaderNodeNormalMap')
        mapping.inputs['Strength'].default_value = .22
        links.new(texture.outputs['Color'], mapping.inputs['Color'])
        links.new(mapping.outputs['Normal'], bsdf.inputs['Normal'])
    if rough:
        texture = nodes.new('ShaderNodeTexImage'); texture.image = rough
        links.new(texture.outputs['Color'], bsdf.inputs['Roughness'])
    material['portable_pbr'] = 'Image BaseColor/Normal/Roughness;no unsupported procedural export nodes'
    return material


def bake_image(name, output, setup, size=512):
    """Bake explicit source-image/material relationships to portable PNG, not light."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 1
    helper = collection('BAKE_HELPERS_NO_EXPORT')
    geometry = Geometry()
    geometry.vertices = [(-1, -1, -40), (1, -1, -40), (1, 1, -40), (-1, 1, -40)]
    geometry.face((0, 1, 2, 3), ((0, 0), (1, 0), (1, 1), (0, 1)))
    material = bpy.data.materials.new(name + '_BAKE_SOURCE'); material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    out = nodes.new('ShaderNodeOutputMaterial')
    emit = nodes.new('ShaderNodeEmission')
    links.new(emit.outputs[0], out.inputs['Surface'])
    setup(nodes, links, emit)
    image = bpy.data.images.new(name, width=size, height=size, alpha=False)
    image.colorspace_settings.name = 'sRGB'
    target = nodes.new('ShaderNodeTexImage'); target.image = image
    nodes.active = target; target.select = True
    obj = geometry.mesh(name + '_BakePlane', helper, [material])
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type='EMIT', margin=8, use_clear=True)
    image.filepath_raw = str(output); image.file_format = 'PNG'; image.save(); image.pack()
    bpy.data.objects.remove(obj, do_unlink=True)
    return image


def leaf_recipe(nodes, links, emit):
    uv = nodes.new('ShaderNodeTexCoord')
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 30
    noise.inputs['Detail'].default_value = 2
    links.new(uv.outputs['UV'], noise.inputs['Vector'])
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = .20
    ramp.color_ramp.elements[0].color = (.075, .108, .040, 1)
    ramp.color_ramp.elements[1].position = .80
    ramp.color_ramp.elements[1].color = (.19, .245, .092, 1)
    links.new(noise.outputs['Fac'], ramp.inputs[0])
    # A narrow midrib in the leaf's UV direction;no photograph or baked illumination.
    separate = nodes.new('ShaderNodeSeparateXYZ'); links.new(uv.outputs['UV'], separate.inputs[0])
    mul = nodes.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = 2
    links.new(separate.outputs['X'], mul.inputs[0])
    fract = nodes.new('ShaderNodeMath'); fract.operation = 'FRACT'; links.new(mul.outputs[0], fract.inputs[0])
    sub = nodes.new('ShaderNodeMath'); sub.operation = 'SUBTRACT'; sub.inputs[1].default_value = .5; links.new(fract.outputs[0], sub.inputs[0])
    absolute = nodes.new('ShaderNodeMath'); absolute.operation = 'ABSOLUTE'; links.new(sub.outputs[0], absolute.inputs[0])
    vein = nodes.new('ShaderNodeMath'); vein.operation = 'LESS_THAN'; vein.inputs[1].default_value = .018; links.new(absolute.outputs[0], vein.inputs[0])
    mix = nodes.new('ShaderNodeMixRGB'); mix.blend_type = 'MIX'; mix.inputs[2].default_value = (.20, .245, .105, 1)
    links.new(vein.outputs[0], mix.inputs[0]); links.new(ramp.outputs[0], mix.inputs[1]); links.new(mix.outputs[0], emit.inputs['Color'])


def dirt_recipe(soil, litter):
    def setup(nodes, links, emit):
        uv = nodes.new('ShaderNodeTexCoord')
        noise = nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 4.8; noise.inputs['Detail'].default_value = 2
        links.new(uv.outputs['UV'], noise.inputs['Vector'])
        source = nodes.new('ShaderNodeTexImage'); source.image = soil
        leaves = nodes.new('ShaderNodeTexImage'); leaves.image = litter
        links.new(uv.outputs['UV'], source.inputs['Vector']); links.new(uv.outputs['UV'], leaves.inputs['Vector'])
        amount = nodes.new('ShaderNodeMath'); amount.operation = 'MULTIPLY'; amount.inputs[1].default_value = .24; links.new(noise.outputs['Fac'], amount.inputs[0])
        mix = nodes.new('ShaderNodeMixRGB'); links.new(amount.outputs[0], mix.inputs[0]); links.new(source.outputs['Color'], mix.inputs[1]); links.new(leaves.outputs['Color'], mix.inputs[2]); links.new(mix.outputs[0], emit.inputs['Color'])
    return setup


def ground_recipe(soil, litter):
    def setup(nodes, links, emit):
        uv = nodes.new('ShaderNodeTexCoord')
        noise = nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value = 5.2; noise.inputs['Detail'].default_value = 3
        links.new(uv.outputs['UV'], noise.inputs['Vector'])
        source = nodes.new('ShaderNodeTexImage'); source.image = soil
        leaves = nodes.new('ShaderNodeTexImage'); leaves.image = litter
        links.new(uv.outputs['UV'], source.inputs['Vector']); links.new(uv.outputs['UV'], leaves.inputs['Vector'])
        leafmix = nodes.new('ShaderNodeMixRGB'); leafmix.inputs[0].default_value = .30
        links.new(source.outputs['Color'], leafmix.inputs[1]); links.new(leaves.outputs['Color'], leafmix.inputs[2])
        grass = nodes.new('ShaderNodeMixRGB'); grass.blend_type = 'MULTIPLY'; grass.inputs[0].default_value = .47; grass.inputs[2].default_value = (.44, .54, .29, 1)
        links.new(leafmix.outputs[0], grass.inputs[1])
        separate = nodes.new('ShaderNodeSeparateXYZ'); links.new(uv.outputs['UV'], separate.inputs[0])
        wave = nodes.new('ShaderNodeMath'); wave.operation = 'MULTIPLY'; wave.inputs[1].default_value = 8.3; links.new(separate.outputs['X'], wave.inputs[0])
        sine = nodes.new('ShaderNodeMath'); sine.operation = 'SINE'; links.new(wave.outputs[0], sine.inputs[0])
        amount = nodes.new('ShaderNodeMath'); amount.operation = 'MULTIPLY_ADD'; amount.inputs[1].default_value = .12; amount.inputs[2].default_value = .50; links.new(sine.outputs[0], amount.inputs[0])
        distance = nodes.new('ShaderNodeMath'); distance.operation = 'SUBTRACT'; links.new(separate.outputs['Y'], distance.inputs[0]); links.new(amount.outputs[0], distance.inputs[1])
        absolute = nodes.new('ShaderNodeMath'); absolute.operation = 'ABSOLUTE'; links.new(distance.outputs[0], absolute.inputs[0])
        edge = nodes.new('ShaderNodeMath'); edge.operation = 'MULTIPLY_ADD'; edge.inputs[1].default_value = .055; edge.inputs[2].default_value = .09; links.new(noise.outputs['Fac'], edge.inputs[0])
        mask = nodes.new('ShaderNodeMath'); mask.operation = 'LESS_THAN'; links.new(absolute.outputs[0], mask.inputs[0]); links.new(edge.outputs[0], mask.inputs[1])
        road = nodes.new('ShaderNodeMixRGB'); road.blend_type = 'MULTIPLY'; road.inputs[0].default_value = .32; road.inputs[2].default_value = (.72, .64, .49, 1); links.new(source.outputs[0], road.inputs[1])
        distance_to_edge = nodes.new('ShaderNodeMath'); distance_to_edge.operation = 'SUBTRACT'; links.new(edge.outputs[0], distance_to_edge.inputs[0]); links.new(absolute.outputs[0], distance_to_edge.inputs[1])
        soften = nodes.new('ShaderNodeMath'); soften.operation = 'MULTIPLY_ADD'; soften.use_clamp = True; soften.inputs[1].default_value = 20.; soften.inputs[2].default_value = .5; links.new(distance_to_edge.outputs[0], soften.inputs[0])
        final = nodes.new('ShaderNodeMixRGB')
        links.new(soften.outputs[0], final.inputs[0]); links.new(grass.outputs[0], final.inputs[1]); links.new(road.outputs[0], final.inputs[2]); links.new(final.outputs[0], emit.inputs['Color'])
    return setup


def foliage(name, seed, height, radius, shrub=False):
    rng = random.Random(seed)
    geometry = Geometry()
    trunk = [(0, 0, 0), (.025, -.015, height * .17), (-.045, .035, height * .36), (.08, .015, height * .55), (.07, -.045, height * .72)]
    base = .045 if shrub else .13
    geometry.tube(trunk, [base, base * .87, base * .67, base * .40, base * .12], 7 if not shrub else 5)
    if not shrub:
        for i in range(5):
            angle = i * math.tau / 5 + .3
            geometry.tube([(0, 0, .09), (math.cos(angle) * .34, math.sin(angle) * .34, .018)], [base * .52, .015], 5)
    clusters, middle_clusters = [], []
    limbs = 5 if shrub else 6
    for i in range(limbs):
        angle = i * math.tau / limbs + rng.uniform(-.26, .26) + seed * .17
        reach = radius * rng.uniform(.53, .78)
        start = Vector(trunk[1 if shrub else 2])
        end = Vector((math.cos(angle) * reach, math.sin(angle) * reach, height * rng.uniform(.57, .77)))
        middle = start.lerp(end, .54) + Vector((0, 0, height * .06))
        geometry.tube([start, middle, end], [base * .65, base * .33, base * .08], 5)
        for fork in range(2 if shrub else 3):
            theta = angle + (fork - 1) * .43 + rng.uniform(-.13, .13)
            center = end + Vector((math.cos(theta) * radius * .18, math.sin(theta) * radius * .18, height * (.04 + fork * .045)))
            join = middle.lerp(end, .60)
            geometry.tube([join, end.lerp(center, .55), center], [base * .22, base * .10, .006], 4)
            clusters.append(center)
        # Leaf-bearing interior growth connects the trunk crown to terminal forks.
        # Vary both position and breadth so adjoining masses overlap asymmetrically.
        inner = middle.lerp(end, rng.uniform(.20, .48)) + Vector((
            -math.sin(angle) * radius * rng.uniform(-.10, .10),
            math.cos(angle) * radius * rng.uniform(-.10, .10),
            height * rng.uniform(.07, .13)))
        geometry.tube([middle, middle.lerp(inner, .58), inner], [base * .19, base * .09, .005], 4)
        middle_clusters.append(inner)
    for offset in [(-.20, .02, .83), (.08, -.09, .88), (.27, .18, .77)]:
        center = Vector((offset[0] * radius, offset[1] * radius, offset[2] * height))
        geometry.tube([Vector(trunk[-2]), center], [base * .22, .006], 4)
        clusters.append(center)
    outer_cluster_count = len(clusters)
    clusters.extend(middle_clusters)
    leaf_count = 0
    for cluster_index, center in enumerate(clusters):
        inner = cluster_index >= outer_cluster_count
        count = rng.randint(45, 52) if shrub else rng.randint(54, 62)
        if inner and not shrub:
            count = rng.randint(72, 80)
        spread = radius * (.35 if shrub else (.43 if inner else .34)) * rng.uniform(.88, 1.12)
        # Elliptical, differently oriented growth avoids separate uniform leaf balls.
        elongation = rng.uniform(.87, 1.18)
        leaf_count += count
        for j in range(count):
            azimuth = rng.random() * math.tau
            polar = math.acos(rng.uniform(-1, 1))
            r = rng.random() ** (1 / 3)
            delta = Vector((math.cos(azimuth) * math.sin(polar) * spread * r * elongation,
                            math.sin(azimuth) * math.sin(polar) * spread * r / elongation,
                            math.cos(polar) * spread * (.78 if inner else .70) * r))
            point = center + delta
            direction = (math.cos(azimuth + .4), math.sin(azimuth + .4), rng.uniform(-.22, .35))
            length = rng.uniform(.20, .31) * (.70 if shrub else 1.)
            geometry.leaf(point, direction, length, length * rng.uniform(.53, .72), rng.uniform(-.8, .8), (cluster_index + j) % 4)
    actual_radius = max(math.hypot(x, y) for x, y, z in geometry.vertices)
    actual_top = max(z for x, y, z in geometry.vertices)
    geometry.vertices = [(x * radius / actual_radius, y * radius / actual_radius, z * height / actual_top) for x, y, z in geometry.vertices]
    recipe = {'id': name, 'seed': seed, 'height_target_m': height, 'crown_radius_target_m': radius,
              'structural_limb_count': limbs, 'leaf_cluster_count': len(clusters),
              'middle_crown_clusters': len(middle_clusters), 'individual_leaf_count': leaf_count,
              'leaf_scale_m': [.140, .217] if shrub else [.20, .31],
              'crown_form': 'Overlapping irregular terminal and interior growth on connected branches;single authorized correction',
              'full_canopy_images': 0, 'alpha_cards': 0, 'geometry': 'connected tapered trunk/limbs/forks + individual folded opaque leaves',
              'variant_source': 'One deterministic editable generator/master recipe;different seed/proportions'}
    return geometry, recipe


def source_pad(stage):
    pad = stage['visualComposition']['deploymentAreas'][0]
    e = pad['earthworkPresentation']
    x, z = pad['center']
    verts = stage['worldGeometry']['vertices']; triangles = stage['worldGeometry']['triangles']
    def sample(px, pz):
        for i in range(0, len(triangles), 3):
            a, b, c = [verts[triangles[i + j]] for j in range(3)]
            den = (b['z'] - c['z']) * (a['x'] - c['x']) + (c['x'] - b['x']) * (a['z'] - c['z'])
            if abs(den) < 1e-12: continue
            u = ((b['z'] - c['z']) * (px - c['x']) + (c['x'] - b['x']) * (pz - c['z'])) / den
            w = ((c['z'] - a['z']) * (px - c['x']) + (a['x'] - c['x']) * (pz - c['z'])) / den
            if u >= -1e-6 and w >= -1e-6 and u + w <= 1 + 1e-6:
                return u * a['y'] + w * b['y'] + (1 - u - w) * c['y']
        raise ValueError('Pad rim is outside authoritative source floor')
    rim = [sample(x + math.cos(i * math.tau / 24) * e['bankRadiiWorld'][0], z + math.sin(i * math.tau / 24) * e['bankRadiiWorld'][1]) for i in range(24)]
    base = sum(rim) / len(rim)
    crest = sample(x, z)
    return {'top_radii_m': e['topRadiiWorld'], 'terrain_foot_radii_m': e['bankRadiiWorld'],
            'stake_arc_radii_m': [.96, .70], 'absolute_source_crest_y': crest,
            'required_root_world_y_at_source_pad': base, 'local_rise_m': crest - base,
            'rim_y_min_max': [min(rim), max(rim)], 'source_id': pad['id'],
            'opening_degrees': 90, 'opening_direction_godot': '+Z;rotate module to existing route entrance',
            'integration': 'Standalone visual prototype. Existing provider stays sole floor/collision/picking/navigation;do not place a second support plane over current raised floor. To adopt bank mesh,match/mask the visible provider and preserve exact placement/nav contracts.'}


def pad_geometry(contract):
    g = Geometry(); rx, ry = contract['top_radii_m']; bx, by = contract['terrain_foot_radii_m']; rise = contract['local_rise_m']
    rings = []; n = 48
    for t in [0., .30, .65, 1.]:
        ring = []
        h = rise * (1 - t * t * (3 - 2 * t))
        for i in range(n):
            angle = i * math.tau / n
            irregular = 1 + .018 * math.sin(angle * 7 + .8) * t
            ring.append(g.vertex((math.cos(angle) * (rx + (bx - rx) * t) * irregular,
                                  math.sin(angle) * (ry + (by - ry) * t) * irregular, h)))
        rings.append(ring)
    center = g.vertex((0, 0, rise))
    for i in range(n):
        k = (i + 1) % n
        g.face((center, rings[0][i], rings[0][k]), ((.5, .5), (.5 + math.cos(i * math.tau / n) * .30, .5 + math.sin(i * math.tau / n) * .30), (.5 + math.cos(k * math.tau / n) * .30, .5 + math.sin(k * math.tau / n) * .30)), 0)
    for j in range(len(rings) - 1):
        for i in range(n):
            k = (i + 1) % n
            ids = (rings[j][i], rings[j + 1][i], rings[j + 1][k], rings[j][k])
            g.face(ids, [(.5 + g.vertices[q][0] / (bx * 2), .5 + g.vertices[q][1] / (by * 2)) for q in ids], 0)
    # Sparse embedded stones interrupt the dirt bank, never form a continuous ring.
    stone_rng = random.Random(73)
    for angle in [.08, .61, 1.28, 2.05, 2.62, 3.28, 4.05, 5.72]:
        t = stone_rng.uniform(.70, .89)
        cx = math.cos(angle) * (rx + (bx - rx) * t)
        cy = math.sin(angle) * (ry + (by - ry) * t)
        h = rise * (1 - t * t * (3 - 2 * t))
        sx, sy = stone_rng.uniform(.11, .17), stone_rng.uniform(.09, .14)
        stone_rings = []
        for z, scale in [(-.055, .65), (.025, 1.), (.12, .48)]:
            ring = []
            for i in range(6):
                a = i * math.tau / 6 + angle
                wobble = stone_rng.uniform(.85, 1.14)
                ring.append(g.vertex((cx + math.cos(a) * sx * scale * wobble,
                                      cy + math.sin(a) * sy * scale * wobble,
                                      h + z + stone_rng.uniform(-.012, .012))))
            stone_rings.append(ring)
        for bottom, top in zip(stone_rings, stone_rings[1:]):
            for i in range(6):
                k = (i + 1) % 6
                g.face((bottom[i], bottom[k], top[k], top[i]), ((0, 0), (1, 0), (1, 1), (0, 1)), 1)
        g.face(stone_rings[-1], [(.5 + math.cos(i * math.tau / 6) * .5, .5 + math.sin(i * math.tau / 6) * .5) for i in range(6)], 1)
    points = []
    for i in range(19):
        a = -math.pi / 4 + i * math.pi * 1.5 / 18
        x, y = math.cos(a) * .96, math.sin(a) * .70
        # Stakes are grounded to the modeled bank,not an invisible extra plane.
        t = max(0., min(1., ((x / rx) ** 2 + (y / ry) ** 2) ** .5 - 1)) / 1.9
        h = rise * (1 - t * t * (3 - 2 * t))
        points.append(Vector((x, y, h)))
        g.tube([(x, y, h - .02), (x, y, h + .31), (x - .015, y, h + .36)], [.032, .028, .006], 6, 2)
    for a, b in zip(points, points[1:]):
        for h in [.12, .24]: g.tube([a + Vector((0, 0, h)), b + Vector((0, 0, h))], [.018, .018], 4, 2)
    return g


def palisade_geometry():
    g = Geometry()
    for left, right in [(-1.6, -.5), (.5, 1.6)]:
        for i in range(9):
            x = left + (right - left) * i / 8
            h = .91 + .045 * math.sin(i * 1.7)
            g.tube([(x, 0, 0), (x, .012, h), (x + .012, .014, h + .09)], [.053, .045, .006], 7)
        for h in [.24, .62]: g.tube([(left, .055, h), (right, .055, h)], [.032, .032], 6)
    return g


def ground_geometry():
    g = Geometry(); nx, ny = 24, 16
    for y in range(ny + 1):
        for x in range(nx + 1): g.vertex((-3 + 6 * x / nx, -2 + 4 * y / ny, .008 * math.sin(x * .73) * math.sin(y * .61)))
    for y in range(ny):
        for x in range(nx):
            a = y * (nx + 1) + x; ids = (a, a + 1, a + nx + 2, a + nx + 1)
            g.face(ids, [((g.vertices[q][0] + 3) / 6, (g.vertices[q][1] + 2) / 4) for q in ids])
    return g


def validate_workshop(scene, stage):
    context = bpy.data.objects.get('CurrentTerrain_REFERENCE_ONLY')
    if context is None or context.type != 'MESH': raise ValueError('Bootstrap context terrain missing')
    if len(context.data.vertices) != 4217 or len(context.data.polygons) != 8144:
        raise ValueError('Expected actual4217vertex8144triangle workshop terrain')
    for actual, original in zip(context.data.vertices, stage['worldGeometry']['vertices']):
        expected = Vector((original['x'], -original['z'], original['y']))
        if (actual.co - expected).length > .00002: raise ValueError('Context coordinate map differs from source(x,-z,y)')
    camera = scene.camera
    if camera is None or camera.data.type != 'ORTHO' or abs(camera.data.ortho_scale - 23.5) > .00001:
        raise ValueError('Bootstrap camera is not actualORTHO23.5')
    direction = camera.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    elevation = math.degrees(math.asin(abs(direction.z)))
    if abs(elevation - 44) > .0001: raise ValueError('Bootstrap camera elevation differs from44')
    name = scene.get('approved_reference_image')
    image = bpy.data.images.get(name) if name else None
    if image is None or image.packed_file is None: raise ValueError('Approved reference not packed in workshop')
    packed_hash = hashlib.sha256(image.packed_file.data).hexdigest()
    if packed_hash != REFERENCE_SHA: raise ValueError('Actual packed reference bytes differ from approvedhash')
    return {'terrain_vertices': 4217, 'terrain_triangles': 8144, 'all_vertex_coordinates_match': True,
            'coordinate_map': 'Godot(x,y,z)->Blender(x,-z,y)', 'camera_projection': 'ORTHO',
            'camera_width': camera.data.ortho_scale, 'camera_elevation': elevation,
            'packed_reference_sha256': packed_hash, 'context_excluded_from_export': True}


def inspect_glb(path):
    content = path.read_bytes(); magic, version, total = struct.unpack_from('<4sII', content)
    if magic != b'glTF' or version != 2 or total != len(content): raise ValueError('Invalid GLB header')
    length, kind = struct.unpack_from('<I4s', content, 12)
    if kind != b'JSON': raise ValueError('GLB JSON first chunk missing')
    doc = json.loads(content[20:20 + length].decode('utf-8').rstrip(' \x00'))
    if any('uri' in x for key in ['images', 'buffers'] for x in doc.get(key, [])): raise ValueError('GLB is not self-contained')
    names = {n.get('name') for n in doc.get('nodes', [])}
    if not set(ROOT_NAMES).issubset(names): raise ValueError('Named export roots missing')
    accessors = doc['accessors']; triangles = 0; primitives = 0
    for mesh in doc.get('meshes', []):
        for p in mesh['primitives']:
            if 'NORMAL' not in p['attributes'] or 'TEXCOORD_0' not in p['attributes']: raise ValueError('Normal/UV missing')
            triangles += accessors[p['indices']]['count'] // 3; primitives += 1
    return {'bytes': len(content), 'sha256': sha(path), 'meshes': len(doc['meshes']), 'triangles': triangles,
            'material_primitives': primitives, 'images': len(doc.get('images', [])), 'self_contained': True,
            'named_roots': ROOT_NAMES, 'scope': 'GLB structural preflight;Godot/visual/performance acceptance pending HQ'}


def presentation(roots, meshes, ground_material):
    scene = bpy.context.scene; owner = collection('PRESENTATION_NO_EXPORT')
    locations = [(-4.5, 2.1, 0), (-.6, 2.3, 0), (3.3, 2.1, 0),
                 (-4.5, -1.25, 0), (-2.6, -1.25, 0), (.5, -1.4, 0), (4.2, -1.4, 0), (0, -5., 0)]
    for root, obj, loc in zip(roots, meshes, locations):
        display = bpy.data.objects.new('Preview_' + root.name, obj.data); owner.objects.link(display); display.location = loc
        label_data = bpy.data.curves.new('Label_' + root.name, type='FONT'); label_data.body = root.name; label_data.size = .22; label_data.align_x = 'CENTER'
        label = bpy.data.objects.new('Label_' + root.name, label_data); owner.objects.link(label); label.location = (loc[0], loc[1] - .9, .025)
    # Display floor is excluded from ASSET_EXPORT and never a gameplay floor.
    g = Geometry(); g.vertices = [(-8, -8, -.05), (8, -8, -.05), (8, 6, -.05), (-8, 6, -.05)]; g.face((0, 1, 2, 3), ((0, 0), (2, 0), (2, 2), (0, 2)))
    g.mesh('StudioFloor_NOT_GAME', owner, [ground_material])
    camdata = bpy.data.cameras.new('AssetReviewCamera'); camdata.type = 'ORTHO'; camdata.ortho_scale = 16.5
    cam = bpy.data.objects.new('AssetReviewCamera_NOT_GAME', camdata); owner.objects.link(cam)
    target = Vector((0, -.6, 1.1)); angle = math.radians(44)
    cam.location = target + Vector((0, -20 * math.cos(angle), 20 * math.sin(angle)))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler(); scene.camera = cam
    sun_data = bpy.data.lights.new('ReviewSun', 'SUN'); sun_data.energy = 2.0; sun_data.angle = math.radians(4)
    sun = bpy.data.objects.new('ReviewSun_NOT_GAME', sun_data); owner.objects.link(sun); sun.rotation_euler = (math.radians(28), math.radians(-24), math.radians(-32))
    world = bpy.data.worlds.new('AssetReviewWorld'); world.use_nodes = True
    world.node_tree.nodes.get('Background').inputs['Color'].default_value = (.40, .45, .47, 1)
    world.node_tree.nodes.get('Background').inputs['Strength'].default_value = .45; scene.world = world
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1440; scene.render.resolution_y = 900; scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    return {'scope': 'Actual Blender asset bench render;not native game/camera/light parity', 'camera_elevation': 44, 'camera_width_m': 16.5, 'engine': 'CYCLES_CPU_24', 'preview_translations_only': True}


def run_production(args):
    run = contained(args.run, WORK)
    workshop = contained(args.workshop, run)
    if not workshop.is_file() or workshop.suffix.lower() != '.blend': raise ValueError('Actual bootstrap workshop.blend required')
    if sha(run / 'reference.png') != REFERENCE_SHA: raise ValueError('Approved reference hash mismatch')
    stage = json.loads((run / 'source_stage.json').read_text(encoding='utf-8-sig'))
    out = run / 'assets' / 'correction' if args.correction else run / 'assets'
    tex = run / 'textures' / 'correction' if args.correction else run / 'textures'
    out.mkdir(parents=True, exist_ok=True); tex.mkdir(parents=True, exist_ok=True)
    if (out / 'authored_assets.blend').exists() or (out / 'stage01_assets.glb').exists():
        raise FileExistsError('Preserve existing production;one explicit --correction allowed,never overwrite first-pass assets')
    bpy.ops.wm.open_mainfile(filepath=str(workshop), load_ui=False, use_scripts=False)
    scene = bpy.context.scene; scene.unit_settings.system = 'METRIC'; scene.unit_settings.scale_length = 1.0
    workshop_check = validate_workshop(scene, stage)
    export = collection('ASSET_EXPORT')
    if list(export.all_objects): raise ValueError('Expected empty bootstrap ASSET_EXPORT;refusing to replace existing artwork')
    context = bpy.data.collections.get('CONTEXT_NO_EXPORT')
    if context: context.hide_render = True
    source = collection('AUTHORING_SOURCE_EDITABLE'); source.hide_render = True
    texture_sources = {}
    soilbase = PROJECT / 'assets/battlefields-remaster/materials'
    terrain = PROJECT / 'assets/materials/terrain'
    bark = PROJECT / 'assets/models/battlefield/pine_sapling_small/textures'
    def texture(path, noncolor=False):
        result = load_texture(path, tex / Path(path).name, noncolor)
        texture_sources[Path(path).name] = {'source': str(path), 'source_sha256': sha(path), 'copy': str(tex / Path(path).name)}
        return result
    soil = texture(soilbase / 'dirt_diff_1k.jpg'); soilnormal = texture(soilbase / 'dirt_nor_gl_1k.jpg', True); soilrough = texture(soilbase / 'dirt_rough_1k.jpg', True)
    litter = texture(terrain / 'brown_mud_leaves_01_diff_1k.jpg')
    barkcolor = texture(bark / 'pine_sapling_small_bark_diff_1k.jpg'); barknormal = texture(bark / 'pine_sapling_small_bark_nor_gl_1k.jpg', True)
    stone = texture(terrain / 'rock_boulder_dry_diff_1k.jpg'); stonenormal = texture(terrain / 'rock_boulder_dry_nor_gl_1k.jpg', True)
    wood = texture(terrain / 'weathered_brown_planks_diff_1k.jpg'); woodnormal = texture(terrain / 'weathered_brown_planks_nor_gl_1k.jpg', True)
    leaf_image = bake_image('BroadleafLeafScaleAtlas_BAKED', tex / 'broadleaf-leafscale-albedo.png', leaf_recipe, 256)
    dirt_image = bake_image('CompactedDirtLitterTile_BAKED', tex / 'compacted-dirt-litter-albedo.png', dirt_recipe(soil, litter), 512)
    ground_image = bake_image('DirtGrassLitterTransition_BAKED', tex / 'dirt-grass-litter-albedo.png', ground_recipe(soil, litter), 1024)
    barkmat = pbr('Broadleaf_Bark_ImagePBR', barkcolor, barknormal)
    leafmat = pbr('Broadleaf_LeafScale_ImagePBR_OPAQUE', leaf_image, double_sided=True)
    soilmat = pbr('CompactedDirt_ImagePBR', dirt_image, soilnormal, soilrough)
    stonemat = pbr('DryStone_ImagePBR', stone, stonenormal)
    woodmat = pbr('WeatheredPalisade_ImagePBR', wood, woodnormal)
    groundmat = pbr('BakedDirtGrassLitter_ImagePBR', ground_image, soilnormal, soilrough)
    roots, meshes, recipes, records = [], [], [], []
    specifications = [('Broadleaf_A', 11, 3.10, 1.60, False), ('Broadleaf_B', 23, 2.72, 1.72, False), ('Broadleaf_C', 37, 3.35, 1.45, False), ('Shrub_A', 41, .86, .68, True), ('Shrub_B', 53, 1.08, .80, True)]
    pad_contract = source_pad(stage)
    pad_contract['bank_surface'] = 'Raised compacted dirt;8 sparse embedded irregular stones;no continuous stone annulus'
    pad_contract['embedded_rim_stone_count'] = 8
    for name, seed, height, radius, shrub in specifications:
        geometry, recipe = foliage(name, seed, height, radius, shrub)
        root = empty(name, export); root['master_recipe_json'] = json.dumps(recipe)
        obj = geometry.mesh(name + '_Surfaces', export, [barkmat, leafmat], root)
        # Editable source copy is retained,while export has one joined mesh/two surfaces.
        edit = bpy.data.objects.new(name + '_EditableMaster', obj.data.copy()); source.objects.link(edit)
        edit['recipe_json'] = json.dumps(recipe); edit.hide_set(True)
        roots.append(root); meshes.append(obj); recipes.append(recipe)
    for name, geometry, materials, contract in [
        ('FiringPad', pad_geometry(pad_contract), [soilmat, stonemat, woodmat], pad_contract),
        ('Palisade', palisade_geometry(), [woodmat], {'width_m': 3.2, 'open_entrance_m': 1., 'height_m': 1., 'rails_cross_opening': False}),
        ('GroundSample', ground_geometry(), [groundmat], {'dimensions_m': [6, 4], 'showcase_only': True, 'material': 'Baked full soil/grass/litter curved-road transition;never tile this road patch over gamefloor', 'game_soil_source': 'FiringPad CompactedDirt_ImagePBR uses separate compacted-dirt-litter-albedo.png WITHOUT grass/roadshape', 'gameplay_route_change': False})]:
        root = empty(name, export); root['contract_json'] = json.dumps(contract)
        obj = geometry.mesh(name + '_Surfaces', export, materials, root)
        edit = bpy.data.objects.new(name + '_EditableMaster', obj.data.copy()); source.objects.link(edit)
        edit['contract_json'] = json.dumps(contract); edit.hide_set(True)
        roots.append(root); meshes.append(obj)
    for root, obj in zip(roots, meshes):
        triangulate_export(obj)
        obj.data.calc_loop_triangles()
        minimum = [min(v.co[i] for v in obj.data.vertices) for i in range(3)]
        maximum = [max(v.co[i] for v in obj.data.vertices) for i in range(3)]
        records.append({'root': root.name, 'mesh': obj.name, 'triangles': len(obj.data.loop_triangles), 'vertices': len(obj.data.vertices), 'material_surfaces': len({p.material_index for p in obj.data.polygons}), 'blender_bounds': [minimum, maximum], 'local_root': [0, 0, 0], 'scale': [1, 1, 1], 'export_triangulated': True, 'editable_master_preserved': True})
        if len(obj.data.loop_triangles) > 8500: raise ValueError('Per-asset triangle budget exceeded: ' + root.name)
    text = bpy.data.texts.new('EDITABLE_MASTER_RECIPES_AND_CONTRACTS')
    text.write(json.dumps({'recipes': recipes, 'pad': pad_contract, 'coordinate': 'Blender(x,y,z)->Godot(x,z,-y);GLTF export_yup=True performs conversion', 'edit': 'ASSET_EXPORT joined meshes and AUTHORING_SOURCE_EDITABLE masters are real editable geometry. Individual leaves are mesh islands. No wholecanopy photographs.'}, indent=2))
    # Only canonical identity-root assets selected;context/bench/source/camera are excluded.
    bpy.ops.object.select_all(action='DESELECT')
    for obj in roots + meshes: obj.hide_set(False); obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    glb = out / 'stage01_assets.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', use_selection=True,
                              export_yup=True, export_animations=False, export_cameras=False,
                              export_lights=False, export_extras=True, export_texcoords=True,
                              export_normals=True, export_tangents=True, export_materials='EXPORT')
    glb_result = inspect_glb(glb)
    for obj in meshes: obj.hide_render = True
    for obj in roots + meshes: obj.hide_set(True)
    preview = presentation(roots, meshes, groundmat)
    scene['asset_production'] = 'EDITABLE_REAL_GEOMETRY_AND_BAKED_IMAGE_PBR;Godot review pending'
    blend = out / 'authored_assets.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    scene.render.filepath = str(out / 'prototypes-render.png')
    bpy.ops.render.render(write_still=True)
    result = {'task': 'BLENDER-ASSET-PRODUCTION-01', 'status': 'ACTUAL_BLEND_GLB_RENDER_CREATED_PENDING_GODOT_AND_ART_REVIEW', 'created_utc': datetime.now(timezone.utc).isoformat(), 'blender_version': bpy.app.version_string, 'workshop': str(workshop), 'workshop_sha256': sha(workshop), 'workshop_validation': workshop_check, 'script_sha256': sha(__file__), 'source_stage_sha256': sha(run / 'source_stage.json'), 'reference_sha256': REFERENCE_SHA, 'correction': int(args.correction), 'blend': str(blend), 'blend_sha256': sha(blend), 'glb': str(glb), 'glb_preflight': glb_result, 'render': str(out / 'prototypes-render.png'), 'render_sha256': sha(out / 'prototypes-render.png'), 'assets': records, 'textures': texture_sources, 'baked_images': [str(tex / 'broadleaf-leafscale-albedo.png'), str(tex / 'dirt-grass-litter-albedo.png')], 'pad_contract': pad_contract, 'preview': preview, 'game_writes': 0, 'downloads': 0, 'whole_canopy_images': 0, 'Godot_import': 'NOT_EXECUTED_BY_UX;HQ_ONLY', 'art_approval': 'NOT_REVIEWED;actualrender/nativecomparison required;finalreferenceapproval belongs to user', 'performance': 'Actual exported triangle/material counts only;no GPU/FPS claim.'}
    write_json(out / 'PRODUCTION_RESULT.json', result)
    print(json.dumps({'status': result['status'], 'blend': str(blend), 'glb': str(glb), 'render': result['render'], 'result': str(out / 'PRODUCTION_RESULT.json')}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workshop', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--correction', action='store_true', help='Single explicit HQ correction;preserves first-pass assets')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    try:
        run_production(args)
    except Exception as exc:
        run = contained(args.run, WORK)
        output = run / 'assets' / 'correction' if args.correction else run / 'assets'
        output.mkdir(parents=True, exist_ok=True)
        failure = output / 'PRODUCTION_ERROR.json'
        if not failure.exists(): write_json(failure, {'status': 'PRODUCTION_FAILED_NO_AUTO_RETRY', 'type': type(exc).__name__, 'reason': str(exc), 'blender': bpy.app.version_string, 'game_writes': 0})
        raise


if __name__ == '__main__':
    main()
