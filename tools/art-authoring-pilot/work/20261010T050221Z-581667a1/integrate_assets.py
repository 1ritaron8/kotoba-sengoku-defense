"""HQ-only isolated import integration. No Blender/Godot invocation or live writes.

Run: python integrate_assets.py --asset <self-contained exported asset.glb>
The first destination must not exist. Explicit --update-asset permits one guarded
GLB/bindings-only correction, with first-pass backups, after all Godot exits.
No full recopy, automatic retry, deletion, or promotion to current/live R8.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
from datetime import datetime, timezone

RUN = Path(__file__).resolve().parent
KIT = RUN.parent.parent
WORKSPACE = KIT.parent.parent
SOURCE = WORKSPACE / "tests/profiles/r8-lag-01/candidate"
DESTINATION = RUN / "godot-candidate"
SLICE = "native/remaster_visual_slice.gd"
STAGE = "assets/battlefields-remaster/reference-scene-01.json"
ROOTS = ("Broadleaf_A", "Broadleaf_B", "Broadleaf_C", "Shrub_A", "Shrub_B", "FiringPad", "Palisade", "GroundSample")
TREES = tuple(f"woodland-trunk-{i:02d}" for i in range(7, 13))
SHRUBS = ("grouped-understory-02", "grouped-understory-03", "grouped-understory-04")
EXCLUDED = {".godot", ".git", ".codex", ".aws", ".agents", "__pycache__", "saves", "save", "user-data", "userdata", "app_userdata", "runtime-user", "runtime-saves"}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def identity() -> list[list[float]]:
    return [[float(row == col) for col in range(4)] for row in range(4)]


def multiply(a: list, b: list) -> list:
    return [[sum(a[row][i] * b[i][col] for i in range(4)) for col in range(4)] for row in range(4)]


def matrix(node: dict) -> list:
    if "matrix" in node:
        value = node["matrix"]
        if len(value) != 16:
            raise ValueError("Malformed node matrix")
        result = [[float(value[col * 4 + row]) for col in range(4)] for row in range(4)]
    else:
        x, y, z, w = [float(v) for v in node.get("rotation", [0, 0, 0, 1])]
        sx, sy, sz = [float(v) for v in node.get("scale", [1, 1, 1])]
        tx, ty, tz = [float(v) for v in node.get("translation", [0, 0, 0])]
        result = [[(1-2*(y*y+z*z))*sx, 2*(x*y-z*w)*sy, 2*(x*z+y*w)*sz, tx],
                  [2*(x*y+z*w)*sx, (1-2*(x*x+z*z))*sy, 2*(y*z-x*w)*sz, ty],
                  [2*(x*z-y*w)*sx, 2*(y*z+x*w)*sy, (1-2*(x*x+y*y))*sz, tz], [0, 0, 0, 1]]
    if not all(math.isfinite(v) for row in result for v in row):
        raise ValueError("Non-finite node transform")
    return result


def inspect_asset(path: Path) -> dict:
    # Reuse the kit's existing GLB header/chunk/embedded-resource checks.
    spec = importlib.util.spec_from_file_location("existing_authoring", KIT / "authoring.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    summary = module.inspect_glb(path)
    data = path.read_bytes()
    length, kind = struct.unpack_from("<I4s", data, 12)
    if kind != b"JSON":
        raise ValueError("Missing GLB JSON")
    document = json.loads(data[20:20+length].decode("utf-8").rstrip(" \x00"))
    if document.get("animations") or document.get("cameras") or "KHR_lights_punctual" in document.get("extensions", {}):
        raise ValueError("Only static asset geometry/materials may be exported")
    nodes = document.get("nodes", [])
    parents = {}
    for parent, node in enumerate(nodes):
        for child in node.get("children", []):
            if child in parents:
                raise ValueError("Multiple parents in export")
            parents[child] = parent
    def world_transform(index: int, visiting: frozenset = frozenset()) -> list:
        if index in visiting:
            raise ValueError("Cyclic GLB node hierarchy")
        local = matrix(nodes[index])
        return multiply(world_transform(parents[index], visiting | {index}), local) if index in parents else local
    result = {}
    for name in ROOTS:
        matches = [i for i, node in enumerate(nodes) if node.get("name") == name]
        if len(matches) != 1:
            raise ValueError(f"Exactly one named asset root required: {name}; got {len(matches)}")
        root = matches[0]
        transform = world_transform(root)
        if any(abs(transform[i][3]) > 0.002 for i in range(3)):
            raise ValueError(f"{name}: root must export at local origin, not workshop layout offset")
        low, high, triangles, meshes = [math.inf]*3, [-math.inf]*3, 0, 0
        uv_low, uv_high = [math.inf]*2, [-math.inf]*2
        material_names = set()
        stack = [root]
        visited = set()
        while stack:
            index = stack.pop()
            if index in visited:
                raise ValueError("Duplicate or cyclic asset descendants")
            visited.add(index)
            node = nodes[index]
            if node.get("name") in ROOTS and index != root:
                raise ValueError("Independent asset roots must not contain each other")
            stack.extend(node.get("children", []))
            if "mesh" not in node:
                continue
            meshes += 1
            transform = world_transform(index)
            for primitive in document["meshes"][node["mesh"]]["primitives"]:
                attributes = primitive["attributes"]
                if not {"POSITION", "NORMAL", "TEXCOORD_0"}.issubset(attributes):
                    raise ValueError(f"{name}: positions, normals and UV0 required")
                if "material" not in primitive:
                    raise ValueError(f"{name}: explicit material required")
                material_names.add(document["materials"][primitive["material"]].get("name", ""))
                accessor = document["accessors"][attributes["POSITION"]]
                if name == "GroundSample":
                    uv = document["accessors"][attributes["TEXCOORD_0"]]
                    if uv.get("componentType") != 5126 or uv.get("type") != "VEC2" or "sparse" in uv:
                        raise ValueError("GroundSample UV density requires ordinary float VEC2 UV0")
                    view = document["bufferViews"][uv["bufferView"]]
                    binary_start = 20 + length + 8
                    base = binary_start + view.get("byteOffset", 0) + uv.get("byteOffset", 0)
                    stride = view.get("byteStride", 8)
                    for vertex in range(uv["count"]):
                        value = struct.unpack_from("<ff", data, base + vertex*stride)
                        uv_low = [min(uv_low[i], value[i]) for i in range(2)]
                        uv_high = [max(uv_high[i], value[i]) for i in range(2)]
                if "min" not in accessor or "max" not in accessor:
                    raise ValueError(f"{name}: POSITION bounds required")
                for corner in range(8):
                    point = [float(accessor["max" if corner & (1 << i) else "min"][i]) for i in range(3)] + [1]
                    transformed = [sum(transform[row][i]*point[i] for i in range(4)) for row in range(3)]
                    if not all(math.isfinite(v) for v in transformed):
                        raise ValueError("Non-finite bounds")
                    low = [min(low[i], transformed[i]) for i in range(3)]
                    high = [max(high[i], transformed[i]) for i in range(3)]
                count = document["accessors"][primitive["indices"]]["count"] if "indices" in primitive else accessor["count"]
                triangles += count // 3
        if not meshes or not triangles or any(not math.isfinite(v) for v in low+high):
            raise ValueError(f"{name}: no usable geometry")
        result[name] = {"min":low, "max":high, "size":[high[i]-low[i] for i in range(3)], "triangles":triangles, "mesh_nodes":meshes, "material_names":sorted(material_names)}
        if name == "GroundSample":
            span = [uv_high[i]-uv_low[i] for i in range(2)]
            if min(span) <= 0 or min(result[name]["size"][0], result[name]["size"][2]) <= .05:
                raise ValueError("GroundSample needs nonzero UV area and an XZ ground footprint")
            result[name]["uv_span"] = span
            result[name]["uv_cycles_per_world_unit"] = [span[0]/result[name]["size"][0], span[1]/result[name]["size"][2]]
        if name.startswith(("Broadleaf", "Shrub")) and (abs(low[1]) > .06 or high[1] <= .1):
            raise ValueError(f"{name}: floor-contact origin/Y-up contract failed")
    ground_name = "CompactedDirt_ImagePBR"
    ground_materials = [material for material in document.get("materials", []) if material.get("name") == ground_name]
    if len(ground_materials) != 1 or ground_name not in result["FiringPad"]["material_names"]:
        raise ValueError("FiringPad must use exactly named CompactedDirt_ImagePBR;GroundSample road stripe is showcase-only")
    if "baseColorTexture" not in ground_materials[0].get("pbrMetallicRoughness", {}):
        raise ValueError("CompactedDirt_ImagePBR must contain baked base image, not a flat color")
    summary["ground_base_material"] = ground_name
    summary["roots"] = result
    return summary


GODOT_BRIDGE = r'''
# BLENDER-ASSET-PRODUCTION-01: isolated imported render assets only.
var _pilot_templates: Dictionary = {}
var _pilot_bindings: Dictionary = {}
var _pilot_library: Node3D
var _pilot_diagnostics: Dictionary = {}

func _pilot_prepare() -> void:
	_pilot_templates.clear()
	_pilot_bindings.clear()
	_pilot_diagnostics={"treeInstances":0,"shrubInstances":0,"palisadeInstances":0,"importedTriangles":0,"floorGeometryChanged":false,"firingPad":"showcase-only;provider floor and exact entrance retained","errors":[]}
	var path: String="res://assets/blender-pilot/asset.glb"
	var binding_path: String="res://assets/blender-pilot/bindings.json"
	if not FileAccess.file_exists(binding_path) or not ResourceLoader.exists(path):
		_pilot_diagnostics.errors.append("Asset GLB/bindings missing or not imported;old render assets retained")
		return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding_path))
	if not parsed is Dictionary: return
	_pilot_bindings=parsed
	var packed: PackedScene=load(path) as PackedScene
	if packed==null: return
	_pilot_library=packed.instantiate() as Node3D
	if _pilot_library==null: return
	_pilot_library.name="BlenderPilotHiddenTemplateLibrary"
	add_child(_pilot_library)
	_pilot_library.hide()
	for name_value in _pilot_bindings.roots:
		var node: Node3D=_pilot_library.find_child(str(name_value),true,false) as Node3D
		if node==null:
			_pilot_diagnostics.errors.append("Imported named root missing: "+str(name_value))
			continue
		_pilot_templates[str(name_value)]=node

func _pilot_relative_transform(node: Node3D) -> Transform3D:
	var result:=Transform3D.IDENTITY
	var cursor: Node=node
	while cursor is Node3D:
		result=(cursor as Node3D).transform*result
		if cursor==_pilot_library: break
		cursor=cursor.get_parent()
	return result

func _pilot_render_only(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Light3D or child is Camera3D:
			node.remove_child(child)
			child.queue_free()
		else: _pilot_render_only(child)
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers=1
		(node as MeshInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _pilot_instance(asset: String, position_value: Vector3, scale_value: Vector3, yaw: float, identifier: String) -> Node3D:
	if not _pilot_templates.has(asset): return null
	var source: Node3D=_pilot_templates[asset]
	var model: Node3D=source.duplicate() as Node3D
	if model==null: return null
	model.transform=_pilot_relative_transform(source)
	model.show()
	_pilot_render_only(model)
	var wrapper:=Node3D.new()
	wrapper.name="BlenderPilot_"+identifier.replace("-","_")
	wrapper.position=position_value
	wrapper.rotation.y=yaw
	wrapper.scale=scale_value
	wrapper.set_meta("scenery_only",true)
	wrapper.set_meta("authoritative_floor",false)
	wrapper.set_meta("source_anchor_id",identifier)
	add_child(wrapper)
	wrapper.add_child(model)
	_pilot_diagnostics.importedTriangles+=int(_pilot_bindings.roots[asset].triangles)
	return wrapper

func _pilot_vegetation(entry: Dictionary, tree: bool) -> bool:
	var records: Dictionary=_pilot_bindings.get("trees" if tree else "shrubs",{})
	var identifier: String=str(entry.get("id",""))
	if not records.has(identifier): return false
	var record: Dictionary=records[identifier]
	var p: Vector3=_ground(float(entry.x),float(entry.z))
	if not is_finite(p.y): return false
	var model: Node3D=_pilot_instance(str(record.asset),p,Vector3.ONE*float(record.scale),deg_to_rad(float(record.yaw_degrees)),identifier)
	if model==null: return false
	_pilot_diagnostics["treeInstances" if tree else "shrubInstances"]+=1
	prop_count+=1
	if tree: canopy_tree_count+=1
	else: understory_cluster_count+=1
	return true

func _pilot_fence(fence: Dictionary) -> bool:
	if str(fence.get("id",""))!=str(_pilot_bindings.get("fence_id","")): return false
	var a: Vector3=_ground(float(fence.a[0]),float(fence.a[1]))
	var b: Vector3=_ground(float(fence.b[0]),float(fence.b[1]))
	if absf(a.y-b.y)>.12:
		_pilot_diagnostics.errors.append("Palisade base terrain differs >.12;old segment retained")
		return false
	var bounds: Dictionary=_pilot_bindings.roots.Palisade
	var dimensions: Array=bounds.size
	var direction:=Vector2(b.x-a.x,b.z-a.z)
	var position_value: Vector3=_ground((a.x+b.x)*.5,(a.z+b.z)*.5)
	var model: Node3D=_pilot_instance("Palisade",position_value,Vector3(direction.length()/float(dimensions[0]),float(fence.height)/float(dimensions[1]),1),-atan2(direction.y,direction.x),str(fence.id))
	if model==null: return false
	_pilot_diagnostics.palisadeInstances+=1
	return true

func _pilot_ground_source(node: Node, material_name: String) -> BaseMaterial3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null:
		var mesh_node:=node as MeshInstance3D
		for index in range(mesh_node.mesh.get_surface_count()):
			var source: BaseMaterial3D=mesh_node.get_active_material(index) as BaseMaterial3D
			if source!=null and source.resource_name==material_name and source.albedo_texture!=null: return source
	for child in node.get_children():
		var found: BaseMaterial3D=_pilot_ground_source(child,material_name)
		if found!=null: return found
	return null

func _pilot_ground_material(existing: ShaderMaterial) -> ShaderMaterial:
	if not _pilot_templates.has("FiringPad"): return existing
	var material_name: String="CompactedDirt_ImagePBR"
	var source: BaseMaterial3D=_pilot_ground_source(_pilot_templates.FiringPad,material_name)
	if source==null:
		_pilot_diagnostics.errors.append("FiringPad CompactedDirt_ImagePBR image material missing;existing ground retained")
		return existing
	var material: ShaderMaterial=existing.duplicate(false)
	_pilot_diagnostics["groundSourceMaterial"]=material_name
	_pilot_diagnostics["groundSourceRoot"]="FiringPad"
	_pilot_diagnostics["groundUVScale"]="Existing soil_uv p*.31 for map-camera finish or p*.40 otherwise;no GroundSample UV/layout reuse"
	material.set_shader_parameter("soil_albedo",source.albedo_texture)
	_pilot_diagnostics["groundAlbedoBound"]=true
	_pilot_diagnostics["groundUV"]="existing world XZ;no mesh/UV/route-mask edits"
	if source.normal_enabled and source.normal_texture!=null:
		material.set_shader_parameter("soil_normal",source.normal_texture)
		_pilot_diagnostics["groundNormalBound"]=true
	if source.roughness_texture!=null and source.roughness_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_RED:
		material.set_shader_parameter("soil_rough",source.roughness_texture)
		_pilot_diagnostics["groundRoughnessBound"]=true
	else: _pilot_diagnostics["groundRoughness"]="Existing roughness retained;packed imported G-channel not misread as R"
	return material
'''


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"Source integration anchor changed: {old[:90]!r}")
    return text.replace(old, new, 1)


def patched_source(text: str) -> str:
    if "BLENDER-ASSET-PRODUCTION-01: isolated" in text:
        raise ValueError("Already integrated; no automatic double patch")
    text = replace_once(text, '\tcomposition["materialPadHeightSamples"] = _material_pad_height_samples()', '\t_pilot_prepare()\n\tcomposition["materialPadHeightSamples"] = _material_pad_height_samples()')
    text = replace_once(text, '\tprovider.set_surface_material(SurfaceMaterials.ground(composition))', '\tprovider.set_surface_material(_pilot_ground_material(SurfaceMaterials.ground(composition)))')
    text = replace_once(text, '\tfor fence in composition.get("fences",[]):', '\tfor fence in composition.get("fences",[]):\n\t\tif _pilot_fence(fence): continue')
    text = replace_once(text, '\t\tvar tree_id: String=str(tree.get("id",""))', '\t\tvar tree_id: String=str(tree.get("id",""))\n\t\tif _pilot_vegetation(tree,true): continue')
    text = replace_once(text, '\t\tvar bush_id: String=str(bush.get("id",""))', '\t\tvar bush_id: String=str(bush.get("id",""))\n\t\tif _pilot_vegetation(bush,false): continue')
    text = replace_once(text, '\treturn {"candidate":true,"providerOwnsFloor":true', '\treturn {"blenderPilot":_pilot_diagnostics.duplicate(true),"candidate":true,"providerOwnsFloor":true')
    return text + '\n' + GODOT_BRIDGE


def bindings(stage: dict, asset: dict) -> dict:
    composition = stage["visualComposition"]
    tree_index = {entry["id"]:entry for entry in composition["trees"]}
    shrub_index = {entry["id"]:entry for entry in composition["bushes"]}
    representative = composition.get("artCoherence", {}).get("woodlandRepresentative", {})
    result = {"roots":asset["roots"], "trees":{}, "shrubs":{}, "fence_id":"aligned-stockade-03", "firing_pad":"showcase-only;no provider floor overlay", "ground_material_source":{"root":"FiringPad", "name":"CompactedDirt_ImagePBR", "requirement":"baked compacted soil/litter base with no road stripe", "uv":"existing soil_uv .31/.40 cycles/world unit;GroundSample transition remains showcase-only"}}
    for index, identifier in enumerate(TREES):
        entry = tree_index[identifier]
        name = ("Broadleaf_A", "Broadleaf_B", "Broadleaf_C")[index % 3]
        target = float(entry["treeHeightWorld"]) * float(representative.get("trees", {}).get(identifier, {}).get("heightFactor", 1))
        height = asset["roots"][name]["size"][1]
        scale = target / height
        if not .25 <= scale <= 2.5:
            raise ValueError(f"Unreasonable tree fit scale: {identifier} {scale}")
        result["trees"][identifier] = {"asset":name, "scale":scale, "yaw_degrees":float(entry.get("rotationDegrees", index*57)), "anchor_xz":[entry["x"],entry["z"]], "target_height":target}
    for index, identifier in enumerate(SHRUBS):
        entry = shrub_index[identifier]
        name = ("Shrub_A", "Shrub_B")[index % 2]
        old_profile = representative.get("bushes", {}).get(identifier, {})
        target = float(old_profile.get("halfHeightWorld", float(entry.get("scale", .44))*.44)) * 2
        scale = target / asset["roots"][name]["size"][1]
        if not .15 <= scale <= 2.5:
            raise ValueError(f"Unreasonable shrub fit scale: {identifier} {scale}")
        result["shrubs"][identifier] = {"asset":name, "scale":scale, "yaw_degrees":index*41, "anchor_xz":[entry["x"],entry["z"]]}
    fence = next(entry for entry in composition["fences"] if entry["id"] == result["fence_id"])
    bounds = asset["roots"]["Palisade"]
    if min(bounds["size"][0:2]) <= .05 or abs(bounds["min"][1]) > .06 or abs(bounds["min"][0]+bounds["max"][0]) > .1:
        raise ValueError("Palisade must be local-X centered, Y-up with midpoint floor-contact origin")
    result["fence_source"] = fence
    return result


def source_files() -> dict:
    files = {}
    def visit(directory: Path) -> None:
        for entry in directory.iterdir():
            if entry.name in EXCLUDED or entry.suffix.lower() in {".log", ".tmp", ".bak"}:
                continue
            if entry.is_symlink() or (hasattr(entry, "is_junction") and entry.is_junction()):
                raise ValueError(f"Source links/junctions are not copied: {entry}")
            if entry.is_dir():
                visit(entry)
            elif entry.is_file():
                files[entry.relative_to(SOURCE).as_posix()] = sha(entry)
    visit(SOURCE)
    return files


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def changed_keys(before: dict, after: dict, allowed: set[str] = frozenset()) -> list[str]:
    return sorted(key for key in set(before) | set(after) if before.get(key) != after.get(key) and key not in allowed)


def protected_live_guard() -> dict:
    live = load_json(WORKSPACE / "tests/profiles/common-overlay-01/evidence/baseline-source.json")
    prepared = load_json(WORKSPACE / "tests/profiles/common-overlay-01/evidence/FUN_SOURCE_MANIFEST.json")
    checked = {}
    for label, root, entries in [("live137", WORKSPACE, live["sources"]), ("prepared4", Path(prepared["preparedRoot"]), {key:value["sha256"] for key,value in prepared["runtimeFiles"].items()})]:
        for key, expected in entries.items():
            path = (root / key.removeprefix("res://")).resolve()
            if not path.is_relative_to(root.resolve()) or not path.is_file() or sha(path) != expected:
                raise ValueError(f"Protected {label} changed: {key}")
            checked[str(path)] = expected
    return checked


def frozen_isolated_snapshot(frozen: dict) -> dict:
    expected = frozen.get("all_isolated_sources", {})
    if len(expected) < 100 or Path(frozen.get("candidate", "")).resolve() != DESTINATION.resolve():
        raise ValueError("HQ full isolated-source freeze missing or wrong destination")
    current = {}
    for relative in expected:
        path = (DESTINATION / relative).resolve()
        if not path.is_relative_to(DESTINATION.resolve()) or path.is_symlink() or not path.is_file():
            raise ValueError(f"Frozen source missing/escaped/linked: {relative}")
        current[relative] = sha(path)
    # Detect added source files as well as changed/missing frozen files. Imported
    # cache and .import metadata are separate from the HQ full source freeze.
    for directory, folders, filenames in os.walk(DESTINATION, followlinks=False):
        folders[:] = [name for name in folders if name not in EXCLUDED]
        for name in folders:
            path = Path(directory) / name
            if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
                raise ValueError("Isolated source junction/symlink is not permitted")
        for name in filenames:
            if name.endswith(".import") or Path(name).suffix.lower() in {".log", ".tmp", ".bak"}:
                continue
            path = Path(directory) / name
            relative = path.relative_to(DESTINATION).as_posix()
            if relative not in current:
                current[relative] = sha(path)
    return current


def update_asset(asset_path: Path, asset: dict, mapping: dict, validate_only: bool) -> int:
    """Only HQ executes this; one correction, no candidate/source recopy."""
    correction_root = (RUN / "assets/correction").resolve()
    if not asset_path.is_relative_to(correction_root):
        raise ValueError("--update-asset requires the corrected GLB under assets/correction")
    if not DESTINATION.is_dir() or DESTINATION.is_symlink() or (hasattr(DESTINATION, "is_junction") and DESTINATION.is_junction()):
        raise ValueError("Existing exact isolated candidate required, without links/junctions")
    gate = load_json(RUN / "BLENDER_PRODUCTION_GATE.json")
    if gate.get("task") != "BLENDER-ASSET-PRODUCTION-01" or datetime.now(timezone.utc) >= datetime.fromisoformat(gate["hard_stop_utc"].replace("Z", "+00:00")):
        raise ValueError("Wrong production gate or hard stop reached")
    first = load_json(RUN / "integration_result.json")
    frozen = load_json(RUN / "GAME_SOURCE_FREEZE.json")
    game_receipt = load_json(RUN / "game-receipt.json")
    if game_receipt.get("exit_code") != 0 or not game_receipt.get("accepted"):
        raise ValueError("Completed accepted first-pass game exit required")
    process_check = subprocess.run(["powershell.exe", "-NoProfile", "-Command", "if(@(Get-Process -Name '*Godot*' -ErrorAction SilentlyContinue).Count){exit 7}"], capture_output=True, timeout=15, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    if process_check.returncode != 0:
        raise ValueError("Godot is still running; no correction writes allowed")
    target_asset = DESTINATION / "assets/blender-pilot/asset.glb"
    target_bindings = DESTINATION / "assets/blender-pilot/bindings.json"
    permitted = {"assets/blender-pilot/asset.glb", "assets/blender-pilot/bindings.json"}
    if sha(target_asset) != first["asset"]["sha256"] or sha(DESTINATION / SLICE) != first["isolated_slice_sha256"]:
        raise ValueError("First-pass asset or isolated bridge already changed")
    if load_json(target_bindings) != first["bindings"]:
        raise ValueError("First-pass bindings changed before correction")
    protected_before = protected_live_guard()
    current_before = source_files()
    if current_before != first["current_source_hashes_before"]:
        raise ValueError("Original current candidate changed; correction stopped")
    isolated_before = frozen_isolated_snapshot(frozen)
    if changed_keys(frozen["all_isolated_sources"], isolated_before):
        raise ValueError("Full isolated source freeze does not match before correction")
    # The first full-stage JSON is an explicit guard even though it is also in
    # the complete source freeze. Camera/terrain/anchors are never patched.
    if sha(SOURCE / STAGE) != sha(DESTINATION / STAGE):
        raise ValueError("World/visual/camera JSON is not exact original candidate")
    backup = RUN / "first-pass-before-asset-correction"
    staging = RUN / "asset-correction-staging"
    receipt_path = RUN / "integration_update_result.json"
    if any(path.exists() for path in [backup, staging, receipt_path]):
        raise ValueError("Correction evidence already exists; no overwrite or automatic second update")
    if validate_only:
        print(json.dumps({"status":"CORRECTION_GUARDS_VALID_NO_WRITES", "current_count":len(current_before), "isolated_count":len(isolated_before), "changed_files_allowed":sorted(permitted)}))
        return 0
    backup.mkdir()
    staging.mkdir()
    # Preserve original source/evidence/freeze files without changing them.
    preserve = [RUN/name for name in ["integration_result.json", "GAME_SOURCE_FREEZE.json", "ASSET_SOURCE_FREEZE.json", "BLENDER_PRODUCTION_GATE.json", "game-receipt.json", "QA_BLENDER_RESULT.json"] if (RUN/name).is_file()]
    for path in preserve:
        shutil.copy2(path, backup / path.name)
    for path in (DESTINATION / "assets/blender-pilot").iterdir():
        if path.is_file():
            target = backup / "first-imported-assets" / path.name
            target.parent.mkdir(exist_ok=True)
            shutil.copy2(path, target)
    for raw_path in frozen["sources"]:
        path = Path(raw_path).resolve()
        if path.is_relative_to(DESTINATION.resolve()) and path.is_file():
            target = backup / "isolated-critical-sources" / path.relative_to(DESTINATION)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    staged_asset = staging / "asset.glb"
    staged_bindings = staging / "bindings.json"
    shutil.copyfile(asset_path, staged_asset)
    dump(staged_bindings, mapping)
    if sha(staged_asset) != asset["sha256"]:
        raise ValueError("Corrected GLB changed after structural validation")
    if source_files() != current_before or frozen_isolated_snapshot(frozen) != isolated_before or protected_live_guard() != protected_before:
        raise ValueError("A protected source changed while preparing backup; no product writes occurred")
    receipt = {"round":"BLENDER-ASSET-PRODUCTION-01", "mode":"EXPLICIT_UPDATE_ASSET", "backup":str(backup), "asset_source":str(asset_path), "asset":asset, "bindings":mapping, "permitted_changes":sorted(permitted), "source_freezes_preserved":True, "full_candidate_recopied":False, "original_integration_result_preserved":True, "before":{"isolated":isolated_before,"current":current_before,"protected":protected_before}, "engine_launches":0}
    try:
        os.replace(staged_asset, target_asset)
        os.replace(staged_bindings, target_bindings)
        current_after = source_files()
        isolated_after = frozen_isolated_snapshot(frozen)
        protected_after = protected_live_guard()
        unexpected = changed_keys(isolated_before, isolated_after, permitted)
        if unexpected or current_after != current_before or protected_after != protected_before:
            raise RuntimeError(f"Unexpected source changes after asset update: {unexpected}")
        if sha(target_asset) != asset["sha256"] or load_json(target_bindings) != mapping:
            raise RuntimeError("Corrected GLB/bindings readback mismatch")
        receipt.update({"status":"UPDATED_TWO_ASSET_FILES_PENDING_HQ_FREEZE_IMPORT_REVIEW", "recorded_utc":datetime.now(timezone.utc).isoformat(), "after":{"isolated":isolated_after,"current":current_after,"protected":protected_after}, "changed_files":changed_keys(isolated_before,isolated_after), "unexpected_changes":[], "world_visual_JSON_byte_exact":sha(SOURCE/STAGE)==sha(DESTINATION/STAGE), "bridge_byte_exact":sha(DESTINATION/SLICE)==first["isolated_slice_sha256"], "next":"HQ records correction source freeze;reimports GLB;records importer-generated extracted-image changes then refreshes full isolated freeze before syntax/native QA. First-pass freezes/evidence/GLB remain in backup. No material/color fix included."})
        dump(receipt_path, receipt)
    except (OSError, ValueError, RuntimeError) as error:
        receipt.update({"status":"UPDATE_FAILED_PRESERVED_BACKUP_DO_NOT_LAUNCH", "reason":str(error), "automatic_retry":False})
        dump(receipt_path, receipt)
        raise
    print(json.dumps({key:receipt[key] for key in ["status", "backup", "changed_files", "world_visual_JSON_byte_exact", "bridge_byte_exact"]}))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", type=Path, required=True)
    parser.add_argument("--validate-only", action="store_true", help="No copy or product source write")
    parser.add_argument("--update-asset", action="store_true", help="HQ-only one correction:guard/back up first pass,replace isolated GLB/bindings only;never recopy candidate")
    args = parser.parse_args()
    asset_path = args.asset.resolve()
    if not asset_path.is_relative_to(RUN.resolve()) or asset_path.is_relative_to(DESTINATION.resolve()) or not asset_path.is_file():
        raise ValueError("Exported GLB must be a real file inside this prepared work, outside godot-candidate")
    if RUN.parent.name != "work" or KIT.name != "art-authoring-pilot" or SOURCE.resolve() == DESTINATION.resolve():
        raise ValueError("Unexpected workspace/source/destination")
    if DESTINATION.exists() and not args.validate_only and not args.update_asset:
        raise ValueError("Isolated destination already exists; preserve it, no overwrite or deletion")
    asset = inspect_asset(asset_path)
    stage = json.loads((SOURCE / STAGE).read_text(encoding="utf-8-sig"))
    mapping = bindings(stage, asset)
    if args.update_asset:
        return update_asset(asset_path, asset, mapping, args.validate_only)
    old = (SOURCE / SLICE).read_text(encoding="utf-8-sig")
    patched = patched_source(old)
    if args.validate_only:
        print(json.dumps({"status":"CONTRACT_VALID_COPY_NOT_RUN", "asset":asset, "bindings":mapping}, ensure_ascii=False))
        return 0
    before = source_files()
    shutil.copytree(SOURCE, DESTINATION, ignore=lambda directory, names: [name for name in names if name in EXCLUDED or Path(name).suffix.lower() in {".log", ".tmp", ".bak"}])
    target_assets = DESTINATION / "assets/blender-pilot"
    target_assets.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(asset_path, target_assets / "asset.glb")
    dump(target_assets / "bindings.json", mapping)
    (DESTINATION / SLICE).write_text(patched, encoding="utf-8", newline="\n")
    after = source_files()
    if before != after:
        raise RuntimeError("Current candidate changed during copy; isolated result not frozen")
    expected_changed = [SLICE, "assets/blender-pilot/asset.glb", "assets/blender-pilot/bindings.json"]
    differences = [rel for rel, digest in before.items() if sha(DESTINATION / rel) != digest]
    if differences != [SLICE]:
        raise RuntimeError(f"Unexpected copied source changes: {differences}")
    result = {"round":"BLENDER-ASSET-PRODUCTION-01", "status":"ISOLATED_INTEGRATED_PENDING_HQ_GODOT_IMPORT_AND_GAMEPLAY", "recorded_utc":datetime.now(timezone.utc).isoformat(), "source":str(SOURCE), "isolated_candidate":str(DESTINATION), "asset_source":str(asset_path), "asset":asset, "bindings":mapping, "changed_or_added_files":expected_changed, "current_source_hashes_before":before, "current_source_hashes_after":after, "current_source_unchanged":before == after, "isolated_slice_sha256":sha(DESTINATION / SLICE), "world_stage_byte_exact":sha(SOURCE / STAGE) == sha(DESTINATION / STAGE), "runtime_saves_copied":False, "engine_launches":0, "actual_import":"PENDING_HQ", "normal_gameplay":"PENDING_HQ", "art_approval":"NOT_CLAIMED", "firing_pad":"Full prototype retained in GLB/library/showcase;no duplicate floor or changed entrance in gameplay"}
    dump(RUN / "integration_result.json", result)
    print(json.dumps({key:result[key] for key in ["status", "isolated_candidate", "changed_or_added_files", "isolated_slice_sha256"]}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(json.dumps({"status":"INTEGRATION_BLOCKED", "reason":str(error), "automatic_retry":False}), file=sys.stderr)
        raise SystemExit(2)
