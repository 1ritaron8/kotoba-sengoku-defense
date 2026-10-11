"""Offline asset-authoring bridge. Does not install tools or change game sources.
Commands: doctor, prepare, bootstrap, export. Python 3.10+; Blender is optional
until bootstrap/export. This prepares an editable workshop, NOT finished artwork.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
from datetime import datetime, timezone
import uuid

BASE = Path(__file__).resolve().parent
WORK = BASE / 'work'
STAGE = 'tests/profiles/r8-lag-01/candidate/assets/battlefields-remaster/reference-scene-01.json'
REF = 'docs/map-remaster-reference/10-stage01-approved-composition.png'
REF_SHA = '1beb10363b3e396eb581f6625b31be32bffb960f3d77ec785bbacef342e5d2cc'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, data: object) -> None:
    # Exclusive create prevents overwriting source/evidence from another run.
    with path.open('x', encoding='utf-8', newline='\n') as f:
        json.dump(data, f, ensure_ascii=False, indent=2, allow_nan=False)


def inside_work(path: Path) -> Path:
    resolved = path.resolve()
    if resolved == WORK.resolve() or not resolved.is_relative_to(WORK.resolve()):
        raise ValueError('Output/run must be a child of this kit/work, not game or arbitrary paths.')
    return resolved


def godot_to_blender(point: list[float]) -> tuple[float, float, float]:
    x, y, z = point
    return (x, -z, y)


def validated_surface(stage: dict) -> tuple[list, list]:
    g = stage['worldGeometry']
    vertices = [[float(v[k]) for k in ('x', 'y', 'z')] for v in g['vertices']]
    flat = g['triangles']
    if not vertices or not flat or len(flat) % 3:
        raise ValueError('Empty or malformed authored surface.')
    if not all(math.isfinite(x) for v in vertices for x in v):
        raise ValueError('Surface contains non-finite coordinates.')
    if not all(type(i) is int and 0 <= i < len(vertices) for i in flat):
        raise ValueError('Invalid triangle index.')
    # Source uses Godot clockwise frontfaces; Blender uses counterclockwise.
    faces = [(flat[i], flat[i + 2], flat[i + 1]) for i in range(0, len(flat), 3)]
    if any(len(set(f)) != 3 for f in faces):
        raise ValueError('Degenerate triangle indices.')
    return vertices, faces


def blender_path(explicit: str | None) -> Path | None:
    candidates = [explicit, os.environ.get('BLENDER_PATH'), shutil.which('blender')]
    for root in (Path('C:/Program Files/Blender Foundation'), Path.home() / 'AppData/Local/Programs/Blender Foundation'):
        if root.is_dir():
            candidates += [str(p) for p in root.glob('Blender */blender.exe')]
    for raw in candidates:
        if raw and Path(raw).is_file():
            return Path(raw).resolve()
    return None


def doctor(workspace: Path, explicit: str | None = None) -> dict:
    blender = blender_path(explicit)
    stage = workspace / STAGE
    reference = workspace / REF
    return {
        'status': 'TOOLS_FOUND_RUNTIME_UNTESTED' if blender else 'BLENDER_NOT_FOUND_IN_CHECKED_LOCATIONS',
        'blender': str(blender) if blender else None,
        'python': sys.version.split()[0],
        'stage_exists': stage.is_file(),
        'reference_exists': reference.is_file(),
        'reference_matches': digest(reference) == REF_SHA if reference.is_file() else False,
        'network_requests': 0, 'installations': 0, 'game_writes': 0,
        'checked_scope': 'explicit path, BLENDER_PATH, PATH, common Blender Foundation directories; not a full disk scan',
    }


def prepare(workspace: Path) -> Path:
    stage_path, ref_path = workspace / STAGE, workspace / REF
    stage_bytes = stage_path.read_bytes()
    stage = json.loads(stage_bytes.decode('utf-8-sig'))
    vertices, faces = validated_surface(stage)
    if digest(ref_path) != REF_SHA:
        raise ValueError('Reference mismatch. Resolve the approved reference instead of substituting.')
    WORK.mkdir(parents=True, exist_ok=True)
    run = inside_work(WORK / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]))
    run.mkdir()
    (run / '.gdignore').touch(exist_ok=False)
    (run / 'source_stage.json').write_bytes(stage_bytes)
    shutil.copyfile(ref_path, run / 'reference.png')
    with (run / 'context_terrain.obj').open('x', encoding='ascii', newline='\n') as f:
        f.write('# CONTEXT ONLY. Current surface, not approved replacement artwork or collision.\n')
        for v in vertices:
            f.write('v %.9f %.9f %.9f\n' % godot_to_blender(v))
        for a, b, c in faces:
            f.write(f'f {a+1} {b+1} {c+1}\n')
    dump(run / 'manifest.json', {
        'status': 'INPUTS_PREPARED_NOT_ART_PRODUCED',
        'stage_source': str(stage_path), 'stage_sha256': hashlib.sha256(stage_bytes).hexdigest(),
        'reference_source': str(ref_path), 'reference_sha256': REF_SHA,
        'vertices': len(vertices), 'triangles': len(faces),
        'coordinate_map': 'Godot(x,y,z) -> Blender(x,-z,y); inverse(x,z,-y)',
        'context_only': True, 'blender_runtime_verified': False,
        'game_modified': False, 'art_approval': 'NOT_REVIEWED',
    })
    return run


def inspect_glb(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError('GLB too short.')
    magic, version, total = struct.unpack_from('<4sII', data)
    if magic != b'glTF' or version != 2 or total != len(data):
        raise ValueError('Invalid GLB header or length.')
    offset, document, chunks = 12, None, []
    while offset < total:
        if offset + 8 > total:
            raise ValueError('Truncated GLB chunk header.')
        length, kind = struct.unpack_from('<I4s', data, offset)
        offset += 8
        if length % 4 or offset + length > total:
            raise ValueError('Invalid GLB chunk.')
        if not chunks and kind != b'JSON':
            raise ValueError('First GLB chunk must be JSON.')
        if kind == b'JSON':
            if document is not None:
                raise ValueError('Duplicate JSON chunk.')
            document = json.loads(data[offset:offset+length].decode('utf-8').rstrip(' \x00'))
        chunks.append(kind.decode('ascii'))
        offset += length
    if not document or not document.get('meshes'):
        raise ValueError('No exported mesh.')
    if any('uri' in x for group in ('images', 'buffers') for x in document.get(group, [])):
        raise ValueError('Pilot requires a self-contained GLB without external references.')
    accessors, triangles = document.get('accessors', []), 0
    for mesh in document['meshes']:
        for primitive in mesh.get('primitives', []):
            if primitive.get('mode', 4) != 4 or 'POSITION' not in primitive.get('attributes', {}):
                raise ValueError('Expected triangle primitive with positions.')
            position = accessors[primitive['attributes']['POSITION']]
            count = accessors[primitive['indices']]['count'] if 'indices' in primitive else position['count']
            if type(count) is not int or count <= 0 or count % 3:
                raise ValueError('Malformed triangle count.')
            triangles += count // 3
    if triangles == 0:
        raise ValueError('No triangles exported.')
    return {'meshes': len(document['meshes']), 'triangles': triangles,
            'materials': len(document.get('materials', [])), 'images': len(document.get('images', [])),
            'bytes': len(data), 'sha256': digest(path),
            'validation': 'structural preflight only, not full glTF conformance, visual or engine acceptance'}


def invoke_blender(executable: Path, action: str, run: Path, blend: Path | None) -> None:
    output = run / ('bootstrap-' + uuid.uuid4().hex[:8] if action == 'bootstrap' else 'export-' + uuid.uuid4().hex[:8])
    output.mkdir()
    command = [str(executable), '--background', '--factory-startup', '--disable-autoexec',
               '--python-exit-code', '2', '--python', str(Path(__file__).resolve()), '--',
               '_worker', action, str(run), str(output)]
    if blend:
        command.append(str(blend))
    with (output / 'blender.log').open('x', encoding='utf-8') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180, check=False)
    if result.returncode != 0:
        raise RuntimeError(f'Blender exit {result.returncode}; inspect {output / "blender.log"}. No automatic retry.')
    if action == 'export':
        dump(output / 'glb_preflight.json', inspect_glb(output / 'asset.glb'))
    print(json.dumps({'action': action, 'output': str(output), 'game_writes': 0}))


def worker(action: str, run_arg: str, output_arg: str, blend_arg: str | None = None) -> None:
    import bpy
    from mathutils import Vector
    run, output = inside_work(Path(run_arg)), inside_work(Path(output_arg))
    if action == 'bootstrap':
        stage = json.loads((run / 'source_stage.json').read_text(encoding='utf-8-sig'))
        verts, faces = validated_surface(stage)
        # Only the fresh --factory-startup process is cleared; never a user's open scene.
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        scene = bpy.context.scene
        scene.unit_settings.system = 'METRIC'
        scene.unit_settings.scale_length = 1.0
        context = bpy.data.collections.new('CONTEXT_NO_EXPORT')
        scene.collection.children.link(context)
        mesh = bpy.data.meshes.new('CurrentSurfaceContext')
        mesh.from_pydata([godot_to_blender(v) for v in verts], [], faces)
        mesh.update()
        obj = bpy.data.objects.new('CurrentTerrain_REFERENCE_ONLY', mesh)
        context.objects.link(obj)
        obj['not_final_art'] = True
        obj['not_collision_export'] = True
        obj.hide_select = True
        export = bpy.data.collections.new('ASSET_EXPORT')
        scene.collection.children.link(export)
        image = bpy.data.images.load(str(run / 'reference.png'), check_existing=False)
        # A scene custom property only stores the image name, not an ID user.
        # Retain the packed reference when saving the otherwise unused datablock.
        image.use_fake_user = True
        image.pack()
        scene['approved_reference_image'] = image.name
        scene['status'] = 'WORKSHOP_ONLY_NO_NEW_ART'
        camera_info = stage['worldGeometry'].get('camera', {})
        target = camera_info.get('worldTarget', [-.25, .45, -.25])
        elevation = math.radians(float(camera_info.get('elevationDegrees', 44)))
        azimuth = math.radians(float(camera_info.get('azimuthDegrees', 0)))
        radius = 45.0
        eye = [target[0] + radius * math.cos(elevation) * math.sin(azimuth),
               target[1] + radius * math.sin(elevation),
               target[2] + radius * math.cos(elevation) * math.cos(azimuth)]
        camdata = bpy.data.cameras.new('ContextCamera')
        camdata.type, camdata.ortho_scale = 'ORTHO', float(camera_info.get('size', 23.5))
        cam = bpy.data.objects.new('ContextCamera_NOT_GAME_CAMERA', camdata)
        scene.collection.objects.link(cam)
        cam.location = godot_to_blender(eye)
        direction = Vector(godot_to_blender(target)) - cam.location
        cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
        scene.camera = cam
        scene.render.resolution_x, scene.render.resolution_y = 1416, 630
        scene.render.resolution_percentage = 100
        text = bpy.data.texts.new('READ_ME_ASSET_WORKSHOP')
        text.write('Reference image is packed. Terrain is context only. Create actual new assets in ASSET_EXPORT.\n'
                   'No flat whole-canopy photograph substitution. Use real branching/leaf-scale assets.\n'
                   'Bake unsupported procedural materials to image textures before GLB export.\n'
                   'No finished artwork, lighting parity, gameplay or collision acceptance is implied.\n')
        bpy.ops.wm.save_as_mainfile(filepath=str(output / 'workshop.blend'))
        dump(output / 'result.json', {'status': 'WORKSHOP_CREATED_NOT_ART', 'blender': bpy.app.version_string})
    elif action == 'export':
        blend = inside_work(Path(blend_arg or ''))
        if not blend.is_file() or blend.suffix.lower() != '.blend':
            raise ValueError('Supply an authored .blend inside this kit/work.')
        bpy.ops.wm.open_mainfile(filepath=str(blend), load_ui=False, use_scripts=False)
        collection = bpy.data.collections.get('ASSET_EXPORT')
        if collection is None:
            raise ValueError('ASSET_EXPORT collection missing.')
        objects = [o for o in collection.all_objects if o.type == 'MESH']
        if not objects:
            raise ValueError('No new artwork: empty ASSET_EXPORT must not pass.')
        if any(o.get('not_final_art') or o.get('not_collision_export') for o in objects):
            raise ValueError('Context geometry is not an exportable finished asset.')
        procedural = {'ShaderNodeTexNoise', 'ShaderNodeTexVoronoi', 'ShaderNodeTexWave',
                      'ShaderNodeTexMusgrave', 'ShaderNodeTexBrick', 'ShaderNodeTexGradient'}
        for obj in objects:
            if not obj.data.uv_layers:
                raise ValueError(f'{obj.name}: UVs required for this textured asset pilot.')
            for slot in obj.material_slots:
                mat = slot.material
                if mat and mat.use_nodes:
                    if any(n.bl_idname in procedural for n in mat.node_tree.nodes):
                        raise ValueError(f'{mat.name}: bake/remove procedural nodes before export; not auto-baked.')
                    for node in mat.node_tree.nodes:
                        if node.type == 'TEX_IMAGE' and node.image:
                            im = node.image
                            if not im.packed_file and im.source == 'FILE' and not Path(bpy.path.abspath(im.filepath)).is_file():
                                raise ValueError(f'Missing texture: {im.name}')
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.export_scene.gltf(filepath=str(output / 'asset.glb'), export_format='GLB',
                                  use_selection=True, export_yup=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
        dump(output / 'result.json', {'status': 'EXPORTED_ENGINE_REVIEW_REQUIRED',
                                     'source_blend': str(blend), 'source_sha256': digest(blend),
                                     'blender': bpy.app.version_string, 'objects': [o.name for o in objects],
                                     'art_approval': 'NOT_REVIEWED', 'game_writes': 0})
    else:
        raise ValueError('Unknown worker action.')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['doctor', 'prepare', 'bootstrap', 'export'])
    parser.add_argument('--workspace', type=Path, default=Path('C:/JP_DF'))
    parser.add_argument('--blender', help='Existing executable only; never installed automatically.')
    parser.add_argument('--run', type=Path)
    parser.add_argument('--blend', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'doctor':
            print(json.dumps(doctor(args.workspace, args.blender), indent=2))
        elif args.command == 'prepare':
            print(json.dumps({'prepared_run': str(prepare(args.workspace)), 'status': 'CONTEXT_ONLY'}))
        else:
            exe = blender_path(args.blender)
            if not exe:
                raise FileNotFoundError('Blender missing. Installation needs explicit permission; no download attempted.')
            if not args.run:
                raise ValueError('--run is required.')
            run = inside_work(args.run)
            if not (run / 'manifest.json').is_file():
                raise ValueError('Prepared run manifest missing.')
            invoke_blender(exe, args.command, run, inside_work(args.blend) if args.blend else None)
        return 0
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({'status': 'BLOCKED_OR_FAILED', 'reason': str(exc), 'automatic_retry': False}), file=sys.stderr)
        return 2


if __name__ == '__main__':
    if '--' in sys.argv and sys.argv[sys.argv.index('--') + 1:][:1] == ['_worker']:
        values = sys.argv[sys.argv.index('--') + 2:]
        worker(*values)
    else:
        raise SystemExit(main())
