extends SceneTree
## Headless script CPU observations and cache/culling behaviour contracts.
## The parent task owns GPU/frame profiling; this script never creates a window.

const Troops = preload("res://native/troops_3d.gd")
const Game = preload("res://native/game.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
const FRIENDLY_TYPES = ["archer", "spear", "samurai", "gunner", "naginata", "monk", "commander", "ninja"]

class AuthoredRestActor extends "res://native/sengoku_actor_3d.gd":
	# configure normally applies an idle pose after constructing the authored
	# rig. Retain that construction pose for ImporterMesh's public LOD API.
	func apply_state(_data: Dictionary) -> void:
		pass

class ObservedActor extends "res://native/sengoku_actor_3d.gd":
	var qa_pose_calls: int = 0
	var qa_stages: Dictionary = {}

	func record_stage(stage: String, start: int) -> void:
		var bucket: Dictionary = qa_stages.get(stage, {"calls":0, "microseconds":0})
		bucket.calls += 1
		bucket.microseconds += Time.get_ticks_usec() - start
		qa_stages[stage] = bucket

	func apply_state(data: Dictionary) -> void:
		qa_pose_calls += 1
		var start: int = Time.get_ticks_usec()
		super.apply_state(data)
		record_stage("apply_state_total", start)

	func _animate_full_body(data: Dictionary, animation: String, clock: float, phase_offset_value: float, sailing: bool) -> void:
		var start: int = Time.get_ticks_usec()
		super._animate_full_body(data, animation, clock, phase_offset_value, sailing)
		record_stage("full_body_including_leg_IK", start)

	func _pose_braced_weapon(data: Dictionary, clock: float) -> void:
		var start: int = Time.get_ticks_usec()
		super._pose_braced_weapon(data, clock)
		record_stage("braced_weapon_including_arm_IK", start)

	func _pose_matchlock(progress: float) -> void:
		var start: int = Time.get_ticks_usec()
		super._pose_matchlock(progress)
		record_stage("matchlock_including_arm_IK", start)

	func _solve_leg(suffix: String, foot_target: Vector3, pitch: float, yaw_offset: float = 0.0) -> void:
		var start: int = Time.get_ticks_usec()
		super._solve_leg(suffix, foot_target, pitch, yaw_offset)
		record_stage("human_leg_IK_nested", start)

	func _solve_arm(suffix: String, palm_target: Vector3, wrist_basis: Basis) -> void:
		var start: int = Time.get_ticks_usec()
		super._solve_arm(suffix, palm_target, wrist_basis)
		record_stage("arm_IK_nested", start)

	func _solve_horse_leg(leg: int, target: Vector3, wanted_floor: float = -INF) -> void:
		var start: int = Time.get_ticks_usec()
		super._solve_horse_leg(leg, target, wanted_floor)
		record_stage("horse_leg_IK_nested", start)

	func _blend_motion_pose(data: Dictionary) -> void:
		var start: int = Time.get_ticks_usec()
		super._blend_motion_pose(data)
		record_stage("motion_transition_including_IK", start)

	func _walk_foot(suffix: String, cycle: float, data: Dictionary) -> Dictionary:
		var start: int = Time.get_ticks_usec()
		var value: Dictionary = super._walk_foot(suffix, cycle, data)
		record_stage("human_foot_anchor_and_recovery_nested", start)
		return value

	func _animate_mount(cycle: float, clock: float, phase_offset_value: float, animation: String, data: Dictionary) -> void:
		var start: int = Time.get_ticks_usec()
		super._animate_mount(cycle, clock, phase_offset_value, animation, data)
		record_stage("mount_gait_including_hoof_IK_nested", start)

	func _horse_contact(leg: int, cycle: float, data: Dictionary) -> Vector3:
		var start: int = Time.get_ticks_usec()
		var value: Vector3 = super._horse_contact(leg, cycle, data)
		record_stage("horse_foot_anchor_and_recovery_nested", start)
		return value

	func _contact_minimum(key: String) -> float:
		var start: int = Time.get_ticks_usec()
		var value: float = super._contact_minimum(key)
		record_stage("real_sole_minimum_nested", start)
		return value

	func _settle_feet_on_terrain(data: Dictionary) -> void:
		var start: int = Time.get_ticks_usec()
		super._settle_feet_on_terrain(data)
		record_stage("terrain_sole_contact", start)

class ObservedSkinRenderer extends "res://native/sengoku_skinned_renderer.gd":
	var qa_calls: int = 0
	var qa_microseconds: int = 0

	func sync_pose(actor: Node3D) -> void:
		var start: int = Time.get_ticks_usec()
		super.sync_pose(actor)
		qa_calls += 1
		qa_microseconds += Time.get_ticks_usec() - start

var checks: int = 0
var failures: Array = []
var observations: Array = []
var require_cache: bool = false
var require_culling: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		if failures.size() <= 20:
			push_error("PERFORMANCE CONTRACT: " + note)

func argument(name_value: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if str(value).begins_with(name_value + "="):
			return str(value).get_slice("=", 1)
	return fallback

func scan_engine_errors() -> Dictionary:
	var path: String = argument("--qa-log", "")
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"checked":false, "count":0, "messages":[], "reason":"Supply --qa-log=<the same Godot --log-file path> to inspect engine diagnostics."}
	var messages: Array = []
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = str(raw_line).strip_edges()
		if not line.begins_with("ERROR:") and not line.begins_with("SCRIPT ERROR:"):
			continue
		if line == "ERROR: Failed to read the root certificate store." or line.begins_with("ERROR: PERFORMANCE CONTRACT:"):
			continue
		messages.append(line)
	return {"checked":true, "count":messages.size(), "messages":messages.slice(0, 10)}

func make_troops() -> Control:
	var troops: Control = Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(1100, 620))
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	troops.set_stage(maps[0])
	return troops

func states_for(count: int) -> Array:
	var result: Array = []
	for index in range(count):
		var friendly: bool = index < 14
		result.append({"id":10000 + index, "type":FRIENDLY_TYPES[index % FRIENDLY_TYPES.size()] if friendly else "enemy_heavy" if index % 4 == 0 else "enemy_light", "friendly":friendly, "evolution":0, "x":0.12 + float(index % 12) * 0.056, "y":0.18 + float(index / 12) * 0.055, "aimX":1.0, "aimY":0.0, "animation":"walk", "animationClock":0.0, "motionTime":0.0, "animationPhase":float(index % 11) * 0.071, "hitClock":0.0, "sailing":false, "hp":100.0, "maxHp":100.0})
	return result

func instrument(troops: Control, states: Array) -> void:
	troops.sync_actor_states(states)
	for source in states:
		var key: String = str(source.id) + ":0"
		var previous: Node3D = troops.actors[key]
		var actor: ObservedActor = ObservedActor.new()
		troops.world.add_child(actor)
		actor.configure(str(source.type), not bool(source.friendly), int(source.id), false, int(source.evolution))
		actor.transform = previous.transform
		if actor.skinned_renderer != null:
			var previous_skin: Node3D = actor.skinned_renderer
			var observed_skin: ObservedSkinRenderer = ObservedSkinRenderer.new()
			actor.add_child(observed_skin)
			observed_skin.joint_names = previous_skin.joint_names
			observed_skin.joint_nodes = previous_skin.joint_nodes
			observed_skin.joint_parents = previous_skin.joint_parents
			observed_skin.joint_poses = previous_skin.joint_poses
			observed_skin.groups = previous_skin.groups
			observed_skin.skeleton = previous_skin.skeleton
			for child in previous_skin.get_children():
				child.reparent(observed_skin)
			actor.skinned_renderer = observed_skin
			previous_skin.free()
		troops.actors[key] = actor
		troops.motion_tracks.erase(key)
		troops.local_light_tracks.erase(key)
		previous.free()
	troops.sync_actor_states(states)
	# motionReset changes from true to false on the first unchanged redraw.
	# Measure stable repeated states after that expected initialization step.
	troops.sync_actor_states(states)
	for actor in troops.actors.values():
		if actor is ObservedActor:
			actor.qa_pose_calls = 0
			actor.qa_stages.clear()
			if actor.skinned_renderer is ObservedSkinRenderer:
				actor.skinned_renderer.qa_calls = 0
				actor.skinned_renderer.qa_microseconds = 0

func pose_calls(troops: Control) -> int:
	var result: int = 0
	for actor in troops.actors.values():
		if actor is ObservedActor:
			result += actor.qa_pose_calls
	return result

func stages(troops: Control) -> Dictionary:
	var result: Dictionary = {}
	for actor in troops.actors.values():
		if not actor is ObservedActor:
			continue
		for stage in actor.qa_stages:
			if not result.has(stage):
				result[stage] = {"calls":0, "microseconds":0}
			result[stage].calls += int(actor.qa_stages[stage].calls)
			result[stage].microseconds += int(actor.qa_stages[stage].microseconds)
		if actor.skinned_renderer is ObservedSkinRenderer:
			if not result.has("skinned_palette_and_visibility"):
				result["skinned_palette_and_visibility"] = {"calls":0, "microseconds":0}
			result.skinned_palette_and_visibility.calls += actor.skinned_renderer.qa_calls
			result.skinned_palette_and_visibility.microseconds += actor.skinned_renderer.qa_microseconds
	return result

func stage_difference(before: Dictionary, after: Dictionary, frames: int) -> Dictionary:
	var result: Dictionary = {}
	for stage in after:
		var old: Dictionary = before.get(stage, {"calls":0, "microseconds":0})
		var calls: int = int(after[stage].calls) - int(old.calls)
		var microseconds: int = int(after[stage].microseconds) - int(old.microseconds)
		result[stage] = {"calls":calls, "meanMicrosecondsPerFrame":float(microseconds) / frames, "meanMicrosecondsPerCall":float(microseconds) / maxi(1, calls)}
	return result

func benchmark_states(count: int) -> Array:
	var states: Array = states_for(count)
	var types: Array = FRIENDLY_TYPES + ["enemy_light", "enemy_heavy"]
	for index in range(count):
		states[index].type = types[index % types.size()]
		states[index].evolution = 2 if index < 14 else 0
	return states

func advance_states(troops: Control, states: Array, dt: float) -> void:
	for source in states:
		source.motionTime = float(source.motionTime) + dt
		source.animationClock = float(source.animationClock) + dt
		var normalized_speed: float = 0.10 if str(source.type) == "commander" else 0.045
		source.x = float(source.x) + normalized_speed * dt

func aggregate(values: Array) -> Dictionary:
	var ordered: Array = values.duplicate()
	ordered.sort()
	var total: float = 0.0
	for value in ordered:
		total += float(value)
	return {"samples":ordered.size(), "meanMicroseconds":total / maxi(1, ordered.size()), "medianMicroseconds":ordered[ordered.size() / 2], "p95Microseconds":ordered[mini(ordered.size() - 1, int(ordered.size() * 0.95))]}

func snapshot(actor: Node3D) -> Dictionary:
	var result: Dictionary = {"root":actor.global_transform, "joints":{}}
	for name_value in actor.bones:
		result.joints[name_value] = actor.bones[name_value].global_transform
	return result

func pose_difference(a: Dictionary, b: Dictionary) -> float:
	var result: float = a.root.origin.distance_to(b.root.origin)
	for name_value in a.joints:
		result = maxf(result, a.joints[name_value].origin.distance_to(b.joints[name_value].origin))
		for axis in range(3):
			result = maxf(result, a.joints[name_value].basis[axis].distance_to(b.joints[name_value].basis[axis]))
	return result

func finite_actors(troops: Control, note: String) -> void:
	for actor in troops.actors.values():
		var valid: bool = actor.global_transform.is_finite()
		for name_value in actor.bones:
			valid = valid and actor.bones[name_value].global_transform.is_finite()
		check(valid, note + ": finite actor and joint transforms")

func geometry_group(bone_name: String) -> String:
	if bone_name in ["boat", "oarL", "oarR"]:
		return "boat"
	if bone_name == "mount" or bone_name.begins_with("horse"):
		return "mount"
	return "weapon" if bone_name == "weapon" else "body"

func vertex_key(bone_index: int, point: Vector3) -> String:
	return "%d|%d,%d,%d" % [bone_index, roundi(point.x * 1000000.0), roundi(point.y * 1000000.0), roundi(point.z * 1000000.0)]

func triangle_key(a: String, b: String, c: String) -> String:
	# Cyclic rotation leaves the oriented face unchanged; reversal does not.
	var choices: Array = [a + ";" + b + ";" + c, b + ";" + c + ";" + a, c + ";" + a + ";" + b]
	choices.sort()
	return choices[0]

func material_attribute(arrays: Array, index: int) -> Vector4:
	if arrays[Mesh.ARRAY_CUSTOM0] == null:
		return Vector4.ZERO
	var values: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	return Vector4(values[index * 4], values[index * 4 + 1], values[index * 4 + 2], values[index * 4 + 3])

func tangent_attribute(arrays: Array, index: int) -> Vector4:
	if arrays[Mesh.ARRAY_TANGENT] == null:
		return Vector4.ZERO
	var values: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	return Vector4(values[index * 4], values[index * 4 + 1], values[index * 4 + 2], values[index * 4 + 3])

func vertex_attributes(arrays: Array, index: int, transform_value: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangent: Vector4 = tangent_attribute(arrays, index)
	var tangent_direction: Vector3 = transform_value.basis * Vector3(tangent.x, tangent.y, tangent.z)
	if tangent_direction.length_squared() > 0.0:
		tangent_direction = tangent_direction.normalized()
	return {"normal":(transform_value.basis.inverse().transposed() * normals[index]).normalized(), "uv":uvs[index], "color":Vector4(colors[index].r, colors[index].g, colors[index].b, colors[index].a), "recipe":material_attribute(arrays, index), "tangent":Vector4(tangent_direction.x, tangent_direction.y, tangent_direction.z, tangent.w)}

func attribute_errors(expected: Dictionary, actual: Dictionary) -> Dictionary:
	return {"normal":(expected.normal as Vector3).distance_to(actual.normal), "uv":(expected.uv as Vector2).distance_to(actual.uv), "color":(expected.color as Vector4).distance_to(actual.color), "recipe":(expected.recipe as Vector4).distance_to(actual.recipe), "tangent":(expected.tangent as Vector4).distance_to(actual.tangent)}

func faces_for_indices(arrays: Array, indices: PackedInt32Array, contacts_only: bool = false, names: Array = []) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var faces: Dictionary = {}
	for cursor in range(0, indices.size(), 3):
		var bone: int = bones[indices[cursor] * 4]
		if contacts_only and not contact_bone(names[bone]):
			continue
		var a: String = vertex_key(bone, vertices[indices[cursor]])
		var b: String = vertex_key(bones[indices[cursor + 1] * 4], vertices[indices[cursor + 1]])
		var c: String = vertex_key(bones[indices[cursor + 2] * 4], vertices[indices[cursor + 2]])
		var key: String = triangle_key(a, b, c)
		faces[key] = int(faces.get(key, 0)) + 1
	return faces

func retain_reference_contacts(indices: PackedInt32Array, arrays: Array, names: Array) -> PackedInt32Array:
	# Independently retain authored contact triangles while admitting the
	# public ImporterMesh simplifier's fine non-contact faces.
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var retained: PackedInt32Array = PackedInt32Array()
	for cursor in range(0, indices.size(), 3):
		if not contact_bone(names[bones[indices[cursor] * 4]]):
			retained.append_array(PackedInt32Array([indices[cursor], indices[cursor + 1], indices[cursor + 2]]))
	for cursor in range(0, full.size(), 3):
		if contact_bone(names[bones[full[cursor] * 4]]):
			retained.append_array(PackedInt32Array([full[cursor], full[cursor + 1], full[cursor + 2]]))
	return retained

func authored_lod_reference(actor: Node3D) -> Dictionary:
	# Regenerate the allowed fine topology from the retained original joint
	# meshes and the public Godot importer, never renderer compact/remap code.
	var rest: Node3D = AuthoredRestActor.new()
	root.add_child(rest)
	rest.configure(actor.unit_type, actor.hostile, 19, false, actor.evolution_stage)
	var names: Array = actor.skinned_renderer.joint_names
	var rest_palette: Array = []
	for name_value in names:
		rest_palette.append(rest.global_transform.affine_inverse() * rest.bones[name_value].global_transform)
	var builders: Dictionary = {}
	for source in actor.meshes:
		var name_value: String = str(source.get_parent().name)
		var group: String = geometry_group(name_value)
		if not builders.has(group):
			var builder: SurfaceTool = SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builder.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
			builders[group] = builder
		for surface in range(source.mesh.get_surface_count()):
			var arrays: Array = source.mesh.surface_get_arrays(surface)
			var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var bones: PackedInt32Array = PackedInt32Array()
			var weights: PackedFloat32Array = PackedFloat32Array()
			bones.resize(count * 4)
			weights.resize(count * 4)
			for vertex in range(count):
				bones[vertex * 4] = names.find(name_value)
				weights[vertex * 4] = 1.0
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			var weighted: ArrayMesh = ArrayMesh.new()
			weighted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, source.mesh.surface_get_format(surface))
			builders[group].append_from(weighted, 0, source.transform)
	var references: Dictionary = {}
	for group in builders:
		builders[group].index()
		var combined: ArrayMesh = builders[group].commit()
		var arrays: Array = combined.surface_get_arrays(0)
		var importer: ImporterMesh = ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", combined.surface_get_format(0))
		importer.generate_lods(60, 25, rest_palette)
		var base: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base_error: float = 0.0
		var levels: Array = []
		for level in range(importer.get_surface_lod_count(0)):
			var error: float = importer.get_surface_lod_size(0, level)
			if error <= 0.12:
				var indices: PackedInt32Array = retain_reference_contacts(importer.get_surface_lod_indices(0, level), arrays, names)
				levels.append({"edgeLength":error, "indices":indices, "faces":faces_for_indices(arrays, indices)})
		levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.edgeLength) < float(b.edgeLength))
		if not levels.is_empty() and float(levels[0].edgeLength) <= 0.025:
			base = levels[0].indices
			base_error = float(levels[0].edgeLength)
			levels.pop_front()
		references[group] = {"arrays":arrays, "authoredVertices":(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "authoredTriangles":(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, "baseError":base_error, "baseIndices":base, "baseFaces":faces_for_indices(arrays, base), "levels":levels}
	rest.free()
	return references

func inspect_lod_indices(actor: Node3D, group: String, instance: MeshInstance3D, arrays: Array) -> Dictionary:
	var surface: Dictionary = RenderingServer.mesh_get_surface(instance.mesh.get_rid(), 0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var original_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var original_contact_faces: Dictionary = {}
	for cursor in range(0, original_indices.size(), 3):
		var first: int = original_indices[cursor]
		var name_value: String = actor.skinned_renderer.joint_names[bones[first * 4]]
		if contact_bone(name_value):
			var key: String = triangle_key(str(first), str(original_indices[cursor + 1]), str(original_indices[cursor + 2]))
			original_contact_faces[key] = int(original_contact_faces.get(key, 0)) + 1
	var stride: int = RenderingServer.mesh_surface_get_format_index_stride(instance.mesh.surface_get_format(0), vertices.size())
	var result: Dictionary = {"group":group, "instance":instance, "vertices":vertices, "bones":bones, "baseIndices":original_indices, "baseError":instance.mesh.get_meta("base_lod_error", 0.0), "levels":[], "summary":[]}
	var number: int = 0
	for lod in surface.get("lods", []):
		var bytes: PackedByteArray = lod.index_data
		var indices: PackedInt32Array = PackedInt32Array()
		indices.resize(bytes.size() / stride)
		for cursor in range(indices.size()):
			indices[cursor] = bytes.decode_u16(cursor * stride) if stride == 2 else bytes.decode_u32(cursor * stride)
		var invalid_indices: int = 0
		for index in indices:
			if index < 0 or index >= vertices.size():
				invalid_indices += 1
		var mixed_bones: int = 0
		var contact_faces: Dictionary = {}
		if invalid_indices == 0 and indices.size() % 3 == 0:
			for cursor in range(0, indices.size(), 3):
				var first: int = bones[indices[cursor] * 4]
				if bones[indices[cursor + 1] * 4] != first or bones[indices[cursor + 2] * 4] != first:
					mixed_bones += 1
				var name_value: String = actor.skinned_renderer.joint_names[first]
				if contact_bone(name_value):
					var key: String = triangle_key(str(indices[cursor]), str(indices[cursor + 1]), str(indices[cursor + 2]))
					contact_faces[key] = int(contact_faces.get(key, 0)) + 1
		check(invalid_indices == 0 and indices.size() % 3 == 0, actor.unit_type + "/" + group + ": valid render LOD triangle indices at level " + str(number))
		check(mixed_bones == 0, actor.unit_type + "/" + group + ": render LOD never stitches independently moving rigid joints at level " + str(number))
		check(contact_faces == original_contact_faces, actor.unit_type + "/" + group + ": retained LOD preserves every original foot/hoof triangle and winding at level " + str(number))
		var summary: Dictionary = {"level":number, "edgeLength":lod.edge_length, "triangles":indices.size() / 3, "mixedBoneTriangles":mixed_bones, "invalidIndices":invalid_indices, "fullContactTriangleTopologyPreserved":contact_faces == original_contact_faces}
		check(float(lod.edge_length) <= 0.12, actor.unit_type + "/" + group + ": coarse silhouette-changing LODs stay outside the retained render mesh")
		result.summary.append(summary)
		if invalid_indices == 0:
			result.levels.append({"level":number, "edgeLength":lod.edge_length, "indices":indices})
		number += 1
	return result

func contact_bone(name_value: String) -> bool:
	return name_value in ["footL", "footR"] or name_value.begins_with("horse_calf")

func compare_lod_silhouette(actor: Node3D, lod_data: Array, palette: Array, note: String, authored_groups: Dictionary) -> Array:
	var renderer: Node3D = actor.skinned_renderer
	var result: Array = []
	for data in lod_data:
		var points: PackedVector3Array = PackedVector3Array()
		points.resize(data.vertices.size())
		for index in range(points.size()):
			var bind: int = data.bones[index * 4]
			var bone: int = data.instance.skin.get_bind_bone(bind)
			points[index] = palette[bone] * (data.instance.skin.get_bind_pose(bind) * (data.vertices[index] as Vector3))
		# The compact stream excludes some authored vertices. Compare visible
		# base and LOD silhouettes against those original sources, not only the
		# compact union (which would hide losses in the selected base itself).
		var full_bounds: AABB
		var full_contact_minima: Dictionary = {}
		var first_authored: bool = true
		for source in authored_groups[data.group]:
			var transform_value: Transform3D = source.instance.global_transform
			for local_point in source.vertices:
				var point: Vector3 = transform_value * local_point
				full_bounds = AABB(point, Vector3.ZERO) if first_authored else full_bounds.expand(point)
				first_authored = false
				if contact_bone(source.bone):
					full_contact_minima[source.bone] = minf(float(full_contact_minima.get(source.bone, INF)), point.y)
		var levels: Array = [{"level":"base", "edgeLength":data.baseError, "indices":data.baseIndices}]
		levels.append_array(data.levels)
		for level in levels:
			var referenced: Dictionary = {}
			for index in level.indices:
				referenced[index] = true
			var bounds: AABB
			var contact_minima: Dictionary = {}
			var first: bool = true
			for index in referenced:
				bounds = AABB(points[index], Vector3.ZERO) if first else bounds.expand(points[index])
				first = false
				var bone: int = data.instance.skin.get_bind_bone(data.bones[index * 4])
				var name_value: String = renderer.joint_names[bone]
				if contact_bone(name_value):
					contact_minima[name_value] = minf(float(contact_minima.get(name_value, INF)), points[index].y)
			var maximum_silhouette_change: float = 0.0
			for axis in range(3):
				maximum_silhouette_change = maxf(maximum_silhouette_change, absf(full_bounds.position[axis] - bounds.position[axis]))
				maximum_silhouette_change = maxf(maximum_silhouette_change, absf(full_bounds.end[axis] - bounds.end[axis]))
			var sole_loss: Dictionary = {}
			var missing_feet: Array = []
			var maximum_sole_loss: float = 0.0
			for name_value in full_contact_minima:
				if not contact_minima.has(name_value):
					missing_feet.append(name_value)
					continue
				var loss: float = (float(contact_minima[name_value]) - float(full_contact_minima[name_value])) / actor.scale.y
				sole_loss[name_value] = loss
				maximum_sole_loss = maxf(maximum_sole_loss, loss)
			var world_sole_loss: float = maximum_sole_loss * actor.scale.y
			if not full_contact_minima.is_empty():
				check(missing_feet.is_empty(), actor.unit_type + "/" + note + "/" + data.group + ": retained LOD preserves every real foot/hoof bone at level " + str(level.level))
				check(world_sole_loss < 0.001, actor.unit_type + "/" + note + "/" + data.group + ": retained LOD preserves the actual sole silhouette within 1mm at level " + str(level.level))
			result.append({"group":data.group, "level":level.level, "edgeLength":level.edgeLength, "triangles":level.indices.size() / 3, "maximumWorldEnvelopeChange":maximum_silhouette_change, "maximumActorLocalEnvelopeChange":maximum_silhouette_change / actor.scale.y, "maximumActorLocalSoleLoss":maximum_sole_loss, "maximumWorldSoleLoss":world_sole_loss, "soleLossByBone":sole_loss, "contactBonesAbsentFromLod":missing_feet, "visibleGroup":data.instance.is_visible_in_tree()})
	return result

func compare_skin_geometry(actor: Node3D) -> Dictionary:
	var renderer: Node3D = actor.skinned_renderer
	var references: Dictionary = authored_lod_reference(actor)
	var expected: Dictionary = {}
	var authored_groups: Dictionary = {}
	for source in actor.meshes:
		var bone_name: String = str(source.get_parent().name)
		var group: String = geometry_group(bone_name)
		var bone_index: int = renderer.joint_names.find(bone_name)
		if not expected.has(group):
			expected[group] = {"vertices":{}, "faces":{}, "contactFaces":{}, "corners":0}
			authored_groups[group] = []
		for surface in range(source.mesh.get_surface_count()):
			var arrays: Array = source.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			authored_groups[group].append({"instance":source, "vertices":vertices, "bone":bone_name})
			var keys: Array = []
			for index in range(vertices.size()):
				var point: Vector3 = source.transform * vertices[index]
				var key: String = vertex_key(bone_index, point)
				keys.append(key)
				var attributes: Dictionary = vertex_attributes(arrays, index, source.transform)
				attributes["instance"] = source
				attributes["sourcePoint"] = vertices[index]
				attributes["sourceNormal"] = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[index]
				if not expected[group].vertices.has(key):
					expected[group].vertices[key] = []
				expected[group].vertices[key].append(attributes)
			var corners: int = indices.size() if not indices.is_empty() else vertices.size()
			expected[group].corners += corners
			for cursor in range(0, corners, 3):
				var a: int = indices[cursor] if not indices.is_empty() else cursor
				var b: int = indices[cursor + 1] if not indices.is_empty() else cursor + 1
				var c: int = indices[cursor + 2] if not indices.is_empty() else cursor + 2
				var face_key: String = triangle_key(keys[a], keys[b], keys[c])
				expected[group].faces[face_key] = int(expected[group].faces.get(face_key, 0)) + 1
				if contact_bone(bone_name):
					expected[group].contactFaces[face_key] = int(expected[group].contactFaces.get(face_key, 0)) + 1
	check(renderer.groups.size() == expected.size(), actor.unit_type + ": visibility groups retain every source joint mesh")
	var matches: Array = []
	var report: Dictionary = {"vertices":0, "triangles":0, "authoredVertices":0, "authoredTriangles":0, "unusedVertices":0, "badWeights":0, "missingVertices":0, "maxErrors":{"normal":0.0, "uv":0.0, "color":0.0, "recipe":0.0, "tangent":0.0}, "groups":renderer.groups.size(), "matches":matches, "lodData":[], "renderLods":[], "baseTopology":[], "authoredGroups":authored_groups}
	for group in renderer.groups:
		var instance: MeshInstance3D = renderer.groups[group]
		var reference: Dictionary = references[group]
		report.authoredVertices += int(reference.authoredVertices)
		report.authoredTriangles += int(reference.authoredTriangles)
		check(instance.mesh.get_surface_count() == 1, actor.unit_type + ": one skinned surface for " + group)
		check(int(instance.mesh.get_meta("authored_vertex_count", -1)) == int(reference.authoredVertices) and int(instance.mesh.get_meta("authored_triangle_count", -1)) == int(reference.authoredTriangles), actor.unit_type + "/" + group + ": independent authored counts match the compact mesh metadata")
		check(absf(float(instance.mesh.get_meta("base_lod_error", -1.0)) - float(reference.baseError)) < 0.000001, actor.unit_type + "/" + group + ": base selection matches the finest allowed importer LOD below 0.025m")
		check(instance.skin.get_bind_count() == actor.bones.size(), actor.unit_type + ": complete bind palette for " + group)
		for bind in range(instance.skin.get_bind_count()):
			var bone_index: int = instance.skin.get_bind_bone(bind)
			check(bone_index >= 0 and bone_index < renderer.joint_names.size() and instance.skin.get_bind_pose(bind).is_equal_approx(Transform3D.IDENTITY), actor.unit_type + ": valid rigid joint bind " + str(bind))
		var actual_faces: Dictionary = {}
		var actual_contact_faces: Dictionary = {}
		var mixed_base_bones: int = 0
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var lods: Dictionary = inspect_lod_indices(actor, group, instance, arrays)
			report.lodData.append(lods)
			report.renderLods.append({"group":group, "levels":lods.summary})
			check(lods.levels.size() == reference.levels.size(), actor.unit_type + "/" + group + ": all remaining allowed fine LODs survive compaction")
			var referenced: Dictionary = {}
			for index in indices:
				referenced[index] = true
			for level in lods.levels:
				for index in level.indices:
					referenced[index] = true
				var expected_faces: Dictionary = {}
				var reference_found: bool = false
				for expected_level in reference.levels:
					if absf(float(level.edgeLength) - float(expected_level.edgeLength)) < 0.000001:
						expected_faces = expected_level.faces
						reference_found = true
						break
				check(reference_found and faces_for_indices(arrays, level.indices) == expected_faces, actor.unit_type + "/" + group + ": remapped LOD keeps the independently generated fine topology at level " + str(level.level))
			var unused: int = vertices.size() - referenced.size()
			report.unusedVertices += unused
			check(unused == 0, actor.unit_type + "/" + group + ": GPU base stream contains only the union referenced by its base and retained LODs")
			check(bones.size() == vertices.size() * 4 and weights.size() == vertices.size() * 4, actor.unit_type + ": every skinned vertex has four joint slots")
			var keys: Array = []
			for index in range(vertices.size()):
				report.vertices += 1
				var bone_index: int = bones[index * 4]
				var rigid: bool = bone_index >= 0 and bone_index < instance.skin.get_bind_count() and absf(weights[index * 4] - 1.0) < 0.00002
				for slot in range(1, 4):
					rigid = rigid and absf(weights[index * 4 + slot]) < 0.00002
				if not rigid:
					report.badWeights += 1
				var key: String = vertex_key(bone_index, vertices[index])
				keys.append(key)
				if not expected[group].vertices.has(key):
					report.missingVertices += 1
					continue
				var attributes: Dictionary = vertex_attributes(arrays, index)
				var best: Dictionary = {}
				var best_errors: Dictionary = {}
				var best_distance: float = INF
				for candidate in expected[group].vertices[key]:
					var errors: Dictionary = attribute_errors(candidate, attributes)
					var distance: float = 0.0
					for value in errors.values():
						distance += float(value)
					if distance < best_distance:
						best = candidate
						best_errors = errors
						best_distance = distance
				for attribute in best_errors:
					report.maxErrors[attribute] = maxf(float(report.maxErrors[attribute]), float(best_errors[attribute]))
				matches.append({"groupInstance":instance, "point":vertices[index], "bone":bone_index, "sourceInstance":best.instance, "sourcePoint":best.sourcePoint, "sourceNormal":best.sourceNormal, "skinNormal":(arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[index]})
			var corners: int = indices.size() if not indices.is_empty() else vertices.size()
			report.triangles += corners / 3
			check(corners == reference.baseIndices.size(), actor.unit_type + ": selected fine base retains the independently permitted triangle count for " + group)
			report.baseTopology.append({"group":group, "baseError":reference.baseError, "authoredVertices":reference.authoredVertices, "renderVertices":vertices.size(), "authoredTriangles":reference.authoredTriangles, "baseTriangles":corners / 3, "unusedVertices":unused})
			for cursor in range(0, corners, 3):
				var a: int = indices[cursor] if not indices.is_empty() else cursor
				var b: int = indices[cursor + 1] if not indices.is_empty() else cursor + 1
				var c: int = indices[cursor + 2] if not indices.is_empty() else cursor + 2
				var face_key: String = triangle_key(keys[a], keys[b], keys[c])
				actual_faces[face_key] = int(actual_faces.get(face_key, 0)) + 1
				if bones[a * 4] != bones[b * 4] or bones[a * 4] != bones[c * 4]:
					mixed_base_bones += 1
				if contact_bone(renderer.joint_names[bones[a * 4]]):
					actual_contact_faces[face_key] = int(actual_contact_faces.get(face_key, 0)) + 1
		check(actual_faces == reference.baseFaces, actor.unit_type + ": base indices and winding match the independently regenerated allowed finest LOD for " + group)
		check(actual_contact_faces == expected[group].contactFaces, actor.unit_type + ": base retains every authored foot/hoof triangle and winding for " + group)
		check(mixed_base_bones == 0, actor.unit_type + ": base triangles never stitch independently moving joints for " + group)
	check(report.badWeights == 0 and report.missingVertices == 0, actor.unit_type + ": every rigid skinned vertex corresponds to its real source joint")
	for attribute in report.maxErrors:
		# Godot repacks normal/tangent directions into its compressed mesh
		# format. 0.001 bounds that roundtrip below 0.06 degrees; UV/color/
		# material recipes retain the stricter source comparison.
		var tolerance: float = 0.001 if attribute in ["normal", "tangent"] else 0.00025
		check(float(report.maxErrors[attribute]) < tolerance, actor.unit_type + ": original " + attribute + " survives surface consolidation")
	return report

func compare_skin_pose(actor: Node3D, geometry: Dictionary, note: String) -> Dictionary:
	var renderer: Node3D = actor.skinned_renderer
	var palette: Array = []
	var maximum_palette_error: float = 0.0
	for index in range(renderer.joint_names.size()):
		var actual: Transform3D = renderer.skeleton.get_bone_global_pose(index)
		palette.append(renderer.skeleton.global_transform * actual)
		var expected: Transform3D = actor.bones[renderer.joint_names[index]].global_transform
		maximum_palette_error = maxf(maximum_palette_error, palette[index].origin.distance_to(expected.origin))
		for axis in range(3):
			maximum_palette_error = maxf(maximum_palette_error, palette[index].basis[axis].distance_to(expected.basis[axis]))
	var maximum_vertex_error: float = 0.0
	var maximum_skin_normal_angle: float = 0.0
	var outside_bounds: int = 0
	for item in geometry.matches:
		var bind: int = item.groupInstance.skin.get_bind_bone(item.bone)
		var deformed: Vector3 = palette[bind] * (item.groupInstance.skin.get_bind_pose(item.bone) * (item.point as Vector3))
		var expected: Vector3 = item.sourceInstance.global_transform * (item.sourcePoint as Vector3)
		maximum_vertex_error = maxf(maximum_vertex_error, deformed.distance_to(expected))
		# GLES3's skeleton shader multiplies the normal by the joint basis;
		# the rendered instance subsequently applies its world normal matrix.
		var skin_matrix: Basis = renderer.skeleton.get_bone_global_pose(bind).basis * item.groupInstance.skin.get_bind_pose(item.bone).basis
		var skin_normal: Vector3 = (item.groupInstance.global_basis.inverse().transposed() * (skin_matrix * (item.skinNormal as Vector3))).normalized()
		var original_normal: Vector3 = (item.sourceInstance.global_basis.inverse().transposed() * (item.sourceNormal as Vector3)).normalized()
		maximum_skin_normal_angle = maxf(maximum_skin_normal_angle, acos(clampf(skin_normal.dot(original_normal), -1.0, 1.0)))
		if item.groupInstance.is_visible_in_tree():
			var bounds: AABB = item.groupInstance.custom_aabb.grow(0.002)
			if not bounds.has_point(item.groupInstance.global_transform.affine_inverse() * deformed):
				outside_bounds += 1
	check(maximum_palette_error < 0.00004, actor.unit_type + "/" + note + ": actual skeleton palette reproduces all live procedural joint transforms")
	check(maximum_vertex_error < 0.00005, actor.unit_type + "/" + note + ": every skinned vertex follows the original geometry through IK and parent scale")
	check(outside_bounds == 0, actor.unit_type + "/" + note + ": every visible deformed vertex remains inside its render culling bounds")
	var sailing: bool = bool(actor.current_state.get("sailing", false))
	check(renderer.groups.body.visible == actor.rig.visible and renderer.groups.weapon.visible == (not sailing) and renderer.groups.boat.visible == sailing, actor.unit_type + "/" + note + ": body, weapon and hull visibility agree with the real stance")
	if renderer.groups.has("mount"):
		check(renderer.groups.mount.visible == (not sailing), actor.unit_type + "/" + note + ": horse visibility agrees with sailing/landing")
	for instance in renderer.groups.values():
		check(instance.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if sailing else GeometryInstance3D.SHADOW_CASTING_SETTING_ON), actor.unit_type + "/" + note + ": sailing shadow policy reaches the real rendered surfaces")
	return {"state":note, "maximumPaletteError":maximum_palette_error, "maximumWorldVertexError":maximum_vertex_error, "maximumSkinNormalAngularDifferenceRadians":maximum_skin_normal_angle, "verticesOutsideCullingBounds":outside_bounds, "lodSilhouette":compare_lod_silhouette(actor, geometry.lodData, palette, note, geometry.authoredGroups)}

func skin_probe() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var variants: Array = []
	for type_name in FRIENDLY_TYPES + ["enemy_light", "enemy_heavy"]:
		variants.append({"type":type_name, "evolution":0})
	for type_name in ["spear", "gunner", "commander", "ninja", "enemy_heavy"]:
		variants.append({"type":type_name, "evolution":2})
	for variant in variants:
		var actor: Node3D = Actor.new()
		world.add_child(actor)
		actor.configure(variant.type, str(variant.type).begins_with("enemy"), 19, false, variant.evolution)
		actor.position = Vector3(2.3, 0.02, -1.5)
		actor.scale = Vector3.ONE * 0.70
		check(actor.skinned_renderer != null, str(variant.type) + ": actual battlefield actor renders through a skeleton palette")
		if actor.skinned_renderer == null:
			actor.free()
			continue
		var geometry: Dictionary = compare_skin_geometry(actor)
		var poses: Array = []
		var state: Dictionary = {"animation":"idle", "animationClock":0.22, "aimX":0.8, "aimY":0.6, "animationPhase":0.14}
		actor.apply_state(state)
		poses.append(compare_skin_pose(actor, geometry, "idle"))
		state.animation = "walk"
		state.runBlend = 1.0
		state.localTravelSpeed = 3.4 if actor.unit_type == "commander" else 1.55
		state.strideLength = 1.845 if actor.unit_type == "commander" else 0.877
		state.locomotionCadence = 1.842 if actor.unit_type == "commander" else 1.767
		for phase in [0.12, 0.38, 0.64, 0.92]:
			state.locomotionPhase = phase
			state.animationClock = phase
			actor.apply_state(state)
			poses.append(compare_skin_pose(actor, geometry, "run-" + str(phase)))
		state.animation = "attack"
		state.attackDuration = 0.5
		state.animationClock = 0.25
		actor.apply_state(state)
		poses.append(compare_skin_pose(actor, geometry, "attack-drive"))
		state.animation = "death"
		state.animationClock = 0.50
		actor.apply_state(state)
		poses.append(compare_skin_pose(actor, geometry, "land-death"))
		state.animation = "walk"
		state.sailing = true
		state.animationClock = 0.4
		actor.apply_state(state)
		poses.append(compare_skin_pose(actor, geometry, "rowing"))
		state.animation = "death"
		state.animationClock = 0.4
		actor.apply_state(state)
		poses.append(compare_skin_pose(actor, geometry, "water-death"))
		state.animation = "idle"
		state.sailing = false
		actor.apply_state(state)
		poses.append(compare_skin_pose(actor, geometry, "landed"))
		geometry.erase("matches")
		geometry.erase("lodData")
		geometry.erase("authoredGroups")
		observations.append({"probe":"skinned-geometry-and-pose", "type":actor.unit_type, "hostile":actor.hostile, "evolution":actor.evolution_stage, "geometry":geometry, "poses":poses, "scope":"Every remaining display vertex corresponds to original UV/color/normal/tangent/material recipe and rigid source joint. Base indices use the finest permitted public importer LOD; every original contact triangle survives base and retained LODs. Silhouette differences are measured against full authored geometry. Actual Skeleton3D pose plus Skin bind transforms; GPU shader output is separately measured by the parent."})
		print("SKIN_VARIANT_QA ", JSON.stringify({"type":actor.unit_type, "evolution":actor.evolution_stage, "checks":checks, "failures":failures.size(), "vertices":geometry.vertices, "authoredVertices":geometry.authoredVertices}))
		actor.free()
	var first: Node3D = Actor.new()
	var second: Node3D = Actor.new()
	world.add_child(first)
	world.add_child(second)
	first.configure("commander", false, 21, false, 2)
	second.configure("commander", false, 35, false, 2)
	first.set_local_light(0.62, Color(0.7, 0.8, 1.0))
	second.set_local_light(1.24, Color(1.0, 0.9, 0.8))
	check(first.materials.combined != second.materials.combined and is_equal_approx(first.materials.combined.get_shader_parameter("local_exposure"), 0.62) and is_equal_approx(second.materials.combined.get_shader_parameter("local_exposure"), 1.24), "Cached skinned geometry retains independent local terrain lighting per soldier")
	var second_poses: Array = []
	for index in range(second.skinned_renderer.joint_names.size()):
		second_poses.append(second.skinned_renderer.skeleton.get_bone_global_pose(index))
	first.apply_state({"animation":"attack", "animationClock":0.25, "attackDuration":0.5, "aimX":-1.0, "aimY":0.0})
	for group in first.skinned_renderer.groups:
		check(first.skinned_renderer.groups[group].mesh == second.skinned_renderer.groups[group].mesh and first.skinned_renderer.groups[group].skin != second.skinned_renderer.groups[group].skin, "Cached " + group + " mesh is shared while each actual actor owns its bind palette")
	for index in range(second_poses.size()):
		check(second_poses[index].is_equal_approx(second.skinned_renderer.skeleton.get_bone_global_pose(index)), "Updating one skinned actor leaves another actor's actual joint palette unchanged")
	observations.append({"probe":"skinned-shared-geometry-isolation", "type":"commander", "evolution":2})
	world.free()
	var troops: Control = make_troops()
	for type_name in FRIENDLY_TYPES:
		troops.sync_placement_preview({"active":true, "visible":true, "valid":true, "type":type_name, "evolution":2, "position":{"x":0.5, "y":0.5}}, 0.1)
		var ghost: Node3D = troops.placement_actor
		check(ghost.visible and ghost.skinned_renderer != null, type_name + ": placement ghost uses the real consolidated actor")
		for group in ghost.skinned_renderer.groups:
			var instance: MeshInstance3D = ghost.skinned_renderer.groups[group]
			check(instance.material_override == ghost.materials.combined and instance.material_override.shader.code.contains("ALPHA = 0.75"), type_name + ": visible skinned placement group retains its private translucent preview material")
			check(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, type_name + ": real skinned placement group never casts an active-unit shadow")
		check(troops.actors.is_empty() and troops.contact_shadows.is_empty() and troops.side_markers.is_empty(), type_name + ": skinned preview stays outside combat identity and contact shadow dictionaries")
	for mode in ["cancel", "modal-or-cursor-hidden", "outside-field"]:
		var active: Dictionary = {"active":true, "visible":true, "valid":true, "type":"spear", "evolution":2, "position":{"x":0.5, "y":0.5}}
		troops.sync_placement_preview(active, 0.1)
		# UPDATE_ONCE becomes disabled after a real rendered frame. Simulate
		# that state while verifying the redraw request independently of GPU.
		troops.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var hidden: Dictionary = active.duplicate(true)
		if mode == "cancel":
			hidden = {}
		elif mode == "modal-or-cursor-hidden":
			hidden.visible = false
		else:
			hidden.position.x = 1.5
		troops.sync_placement_preview(hidden)
		check(not troops.placement_actor.visible and troops.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, mode + ": hiding a visible ghost invalidates the cached viewport texture without simulation time")
		troops.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		troops.sync_placement_preview(hidden)
		check(troops.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, mode + ": an already hidden unchanged ghost reuses the cached viewport")
	observations.append({"probe":"skinned-placement-material-and-shadow", "types":FRIENDLY_TYPES.size(), "evolution":2})
	troops.free()

func cpu_probe(count: int) -> void:
	var troops: Control = make_troops()
	var states: Array = benchmark_states(count)
	instrument(troops, states)
	for unused in range(15):
		advance_states(troops, states, 1.0 / 60.0)
		troops.sync_actor_states(states)
	var summary: Dictionary = {"probe":"script-cpu-sync", "actors":count, "friendly":mini(count, 14), "samples":[]}
	for mode in ["moving", "paused", "offscreen"]:
		if mode == "offscreen":
			for source in states:
				source.x = float(source.x) + 1.25
			troops.sync_actor_states(states)
		var before_calls: int = pose_calls(troops)
		var before_stages: Dictionary = stages(troops)
		var timings: Array = []
		for unused in range(120):
			if mode != "paused":
				advance_states(troops, states, 1.0 / 60.0)
			var start: int = Time.get_ticks_usec()
			troops.sync_actor_states(states)
			timings.append(float(Time.get_ticks_usec() - start))
		var measurement: Dictionary = aggregate(timings)
		measurement["mode"] = mode
		measurement["poseCalls"] = pose_calls(troops) - before_calls
		measurement["stages"] = stage_difference(before_stages, stages(troops), timings.size())
		measurement["actualActorCount"] = troops.actors.size()
		if require_cache and mode == "paused":
			check(int(measurement.poseCalls) == 0, "Paused repeated states skip full-body pose updates for " + str(count) + " actors")
		if require_culling and mode == "offscreen":
			check(int(measurement.poseCalls) == 0, "Fully offscreen actors skip full-body pose updates for " + str(count) + " actors")
		summary.samples.append(measurement)
	summary["instrumentation"] = "Actual super method calls measured by QA subclasses; nested IK belongs to enclosing body/weapon/transition stages, so stage totals must not be added. Timer overrides add overhead. Composition matches the parent's synthetic GPU mix; this is not actual play population."
	finite_actors(troops, "CPU population " + str(count))
	observations.append(summary)
	troops.free()

func mutation_probe() -> void:
	var troops: Control = make_troops()
	var states: Array = states_for(2)
	states[0].animation = "idle"
	states[1].friendly = false
	states[1].type = "enemy_light"
	instrument(troops, states)
	var actor: Node3D = troops.actors["10000:0"]
	var frozen: Dictionary = snapshot(actor)
	var before_calls: int = pose_calls(troops)
	for unused in range(20):
		troops.sync_actor_states(states)
	var repeated_calls: int = pose_calls(troops) - before_calls
	check(pose_difference(frozen, snapshot(actor)) < 0.00005, "Unchanged same-clock states preserve the pose")
	if require_cache:
		check(repeated_calls == 0, "Unchanged same-clock states do not invoke actor.apply_state")
	states[0].x = float(states[0].x) + 0.10
	troops.sync_actor_states(states)
	check(actor.position.distance_to(troops.normalized_to_world(Vector2(states[0].x, states[0].y))) < 0.00005, "Same-clock root movement invalidates the render cache")
	troops.set_field_size(Vector2(1440, 736))
	troops.sync_actor_states(states)
	check(actor.position.distance_to(troops.normalized_to_world(Vector2(states[0].x, states[0].y))) < 0.00005, "Resizing updates the world projection without advancing time")
	var before_hit: Quaternion = actor.bones.torso.global_basis.get_rotation_quaternion()
	states[0].hitClock = 0.06
	troops.sync_actor_states(states)
	check(before_hit.angle_to(actor.bones.torso.global_basis.get_rotation_quaternion()) > 0.01, "Same-clock hit feedback invalidates a cached idle pose")
	states[0].sailing = true
	troops.sync_actor_states(states)
	check(not actor.boat.visible, "A sailing flag alone cannot drag a hull across the fixture's actual land")
	var previous_water: Dictionary=troops.stage.get("water",{}).duplicate(true)
	troops.stage["water"]={"x":float(states[0].x)-.04,"y":float(states[0].y)-.04,"w":.08,"h":.08}
	troops.sync_actor_states(states)
	check(actor.boat.visible, "Same-clock sailing on fixture water changes the visible stance")
	troops.stage["water"]=previous_water
	states[0].sailing = false
	states[0].evolution = 2
	troops.sync_actor_states(states)
	actor = troops.actors["10000:0"]
	check(actor.evolution_stage == 2 and not actor.boat.visible, "Same-clock evolution and landing refresh the real actor")
	states[1].dead = true
	states[1].animation = "death"
	states[1].animationClock = 0.20
	troops.sync_actor_states(states)
	var head_before: Vector3 = troops.actors["10001:0"].bones.head.global_position
	var death_before: Dictionary = snapshot(troops.actors["10001:0"])
	states[1].animationClock = 0.45
	troops.sync_actor_states(states)
	var head_after: Vector3 = troops.actors["10001:0"].bones.head.global_position
	var death_pose_change: float = pose_difference(death_before, snapshot(troops.actors["10001:0"]))
	check(death_pose_change > 0.01, "A corpse continues its actual fall pose when animationClock advances at frozen motionTime")
	states.remove_at(1)
	troops.sync_actor_states(states)
	check(not troops.actors.has("10001:0") and not troops.motion_tracks.has("10001:0") and not troops.contact_shadows.has("10001:0"), "Same-clock death removal cleans actor, motion and contact shadow caches")
	var newcomer: Dictionary = states_for(1)[0].duplicate(true)
	newcomer.id = 99999
	newcomer.type = "samurai"
	states.append(newcomer)
	troops.sync_actor_states(states)
	check(troops.actors.has("99999:0"), "Same-clock deployment adds the requested actual actor")
	var hidden_calls: int = pose_calls(troops)
	troops.manual_states = states
	troops.hide()
	for unused in range(20):
		troops._process(1.0 / 60.0)
	check(pose_calls(troops) == hidden_calls, "A hidden troop renderer performs no full-body pose updates")
	newcomer.evolution = 1
	troops.show()
	troops._process(1.0 / 60.0)
	check(troops.actors["99999:0"].evolution_stage == 1, "Showing the renderer applies source changes made while hidden")
	troops._process(0.0)
	troops._process(0.0)
	var before_cull: int=pose_calls(troops)
	var home_x: float=float(newcomer.x)
	newcomer.x=home_x+1.25
	newcomer.motionTime=float(newcomer.motionTime)+.1
	troops.sync_actor_states([newcomer])
	check(pose_calls(troops)==before_cull and not troops.actors["99999:0"].visible,"Far-offscreen actor keeps its logical record without a pose update")
	check(troops.actors["99999:0"].position.distance_to(troops.normalized_to_world(Vector2(newcomer.x,newcomer.y)))<.00005,"Culling still updates the exact logical root anchor")
	newcomer.x=home_x
	newcomer.motionTime=float(newcomer.motionTime)+.1
	troops.sync_actor_states([newcomer])
	check(troops.actors["99999:0"].visible and bool(troops.actors["99999:0"].current_state.motionReset),"Visible reentry resets stale motion contacts at the current root")
	troops.manual_states=[newcomer]
	troops._process(0.0)
	var same_pose: Dictionary = snapshot(troops.actors["99999:0"])
	troops.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	troops.hide()
	troops._process(0.0)
	troops.show()
	troops._process(0.0)
	check(troops.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "Showing an unchanged paused renderer refreshes its cached viewport after hidden state")
	check(pose_difference(same_pose, snapshot(troops.actors["99999:0"])) < 0.00005, "Refreshing a shown paused viewport preserves the actual cached pose")
	finite_actors(troops, "Mutation and resume")
	observations.append({"probe":"same-clock-invalidation", "unchangedPoseCalls":repeated_calls, "cosmeticDeathPoseChange":death_pose_change, "cosmeticDeathHeadHeightChange":head_before.y - head_after.y, "cases":"repeat, root movement, resize, hit, sailing, evolution, cosmetic death clock, remove, deploy, hidden/resume"})
	troops.free()

func make_battle() -> Node2D:
	var game: Node2D = Game.new()
	root.add_child(game)
	game.set_process(false)
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var ids: Array = []
	for definition in catalog:
		ids.append(definition.id)
	game.configure_roster(catalog, ids, {})
	game.load_map({"id":"performance-contract-fixture", "initialGold":10000, "unitLimit":14, "totalWaves":10, "difficulty":1.0, "paths":[{"objectiveId":"main", "points":[{"x":0.05, "y":0.5}, {"x":0.95, "y":0.5}]}], "objectives":[{"id":"main", "x":0.95, "y":0.5, "hp":100}], "buildZones":[{"x":0.50, "y":0.68, "r":0.08}], "tactics":{"groundPosts":[{"id":"fixture-post", "pathIndex":0, "segmentIndex":0, "t":0.5, "r":0.07, "guardRadius":0.16, "mobilityFactor":1.0, "capacityBonus":0}]}, "trait":{"auras":[{"x":0.50, "y":0.5, "r":0.10, "period":1.2, "activeSeconds":0.4, "unitDamageFactor":1.1, "unitRangeFactor":1.2, "enemySpeedFactor":0.9}]}})
	game.set_seed(19)
	for type_name in ["spear", "archer"]:
		check(game.recruit(type_name), "Fixture recruits " + type_name)
		if str(game.placement_contract(type_name).deploymentKind)=="marching":
			check(not game.recruitment_queue.is_empty(),"Fixture queues marching recruitment at its authored base")
			continue
		for point in game.placement_hints:
			if point.x >= 0.0:
				check(game.place_unit(point.x, point.y), "Fixture legally places " + type_name)
				break
	game._advance_recruitment(10.0)
	game.start_battle()
	game.spawn_queue = ["raider"]
	game.spawn_source_waves = [1]
	game.spawn_clock = 100000.0
	for index in range(8):
		game._spawn_enemy("raider", 1)
		game.enemies[-1].position = Vector2(0.38 + float(index) * 0.012, 0.5)
		game.enemies[-1].hp = 1000.0
		game.enemies[-1].maxHp = 1000.0
	game.learning_supports.append({"attemptId":"fixture-support", "mapId":"performance-contract-fixture", "wave":1, "x":0.50, "y":0.50, "r":0.17, "hinted":false, "duration":0.75, "remaining":0.75, "unitDamageFactor":1.15})
	return game

func game_signature(game: Node2D) -> Dictionary:
	return {"public":game.snapshot(), "units":game.units.duplicate(true), "enemies":game.enemies.duplicate(true), "projectiles":game.projectiles.duplicate(true), "effects":game.effects.duplicate(true), "deathActors":game.death_actors.duplicate(true), "learningSupports":game.learning_supports.duplicate(true), "spawnQueue":game.spawn_queue.duplicate(true), "spawnSourceWaves":game.spawn_source_waves.duplicate(true), "spawnClock":game.spawn_clock, "waveTime":game.wave_time, "rngState":game.rng.state}

func simulation_probe() -> void:
	var plain: Node2D = make_battle()
	var rendered: Node2D = make_battle()
	var troops: Control = make_troops()
	troops.battle = rendered
	var initial_enemy_hp: float = 0.0
	for enemy in rendered.enemies:
		initial_enemy_hp += float(enemy.hp)
	var aura_counts_seen: Dictionary = {}
	for index in range(240):
		plain._process(1.0 / 60.0)
		rendered._process(1.0 / 60.0)
		troops.sync_actor_states(rendered.actor_states())
		# active_auras returns both active and inactive definitions with an
		# explicit flag. Observe activation rather than the array's length.
		var active_aura_count: int = 0
		for aura in rendered.active_auras():
			if bool(aura.active):
				active_aura_count += 1
		aura_counts_seen[str(active_aura_count)] = true
		check(game_signature(plain) == game_signature(rendered), "Rendering preserves actual battle, targeting, damage, support expiration and random state at tick " + str(index))
	var remaining_enemy_hp: float = 0.0
	for enemy in rendered.enemies:
		remaining_enemy_hp += float(enemy.hp)
	var inflicted_damage: float = initial_enemy_hp - remaining_enemy_hp
	check(inflicted_damage > 0.0, "Simulation equivalence fixture exercises real attacks and enemy HP changes")
	check(aura_counts_seen.size() >= 2, "Simulation equivalence fixture crosses actual timed aura activation boundaries")
	check(rendered.learning_supports.is_empty(), "Simulation equivalence fixture exercises the actual earned learning support expiration")
	var frozen_game: Dictionary = game_signature(rendered)
	plain.paused = true
	rendered.paused = true
	frozen_game = game_signature(rendered)
	for unused in range(20):
		plain._process(1.0 / 60.0)
		rendered._process(1.0 / 60.0)
		troops.sync_actor_states(rendered.actor_states())
	check(game_signature(plain) == game_signature(rendered) and game_signature(rendered) == frozen_game, "Pause/render caching preserves every actual simulation value")
	observations.append({"probe":"simulation-equivalence", "simulationSeconds":rendered.elapsed, "enemies":rendered.enemies.size(), "kills":rendered.kills, "enemyHpRemoved":inflicted_damage, "auraActivationStatesSeen":aura_counts_seen.keys(), "expiredLearningSupport":rendered.learning_supports.is_empty(), "scope":"Identical deterministic battles with/without renderer calls, timed aura switches and earned-support expiration; fixture funds isolate behaviour."})
	troops.free()
	plain.free()
	rendered.free()

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Performance contracts only run with --headless; the parent owns GPU measurement")
		quit(2)
		return
	require_cache = OS.get_cmdline_user_args().has("--require-cache")
	require_culling = OS.get_cmdline_user_args().has("--require-culling")
	var mode: String = argument("--probe", "all")
	if mode in ["all", "cpu"]:
		for value in argument("--counts", "24,56,80").split(",", false):
			cpu_probe(maxi(1, int(value)))
	if mode in ["all", "strict", "mutation"]:
		mutation_probe()
	if mode in ["all", "strict", "simulation"]:
		simulation_probe()
	if mode in ["all", "strict", "skin"]:
		skin_probe()
	check(not observations.is_empty(), "At least one selected performance contract executes")
	var engine_errors: Dictionary = scan_engine_errors()
	check(int(engine_errors.count) == 0, "Godot reports no runtime or script errors during the selected performance contracts")
	var label: String = argument("--label", "current")
	var packed: bool = OS.get_cmdline_user_args().has("--packed")
	var path: String = ("user://qa_performance_contracts_" if packed else "res://tests/qa_performance_contracts_") + label + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Performance contract report opens")
	if file != null:
		file.store_string(JSON.stringify({"checks":checks, "failures":failures, "observations":observations, "engineErrors":engine_errors, "strictPauseCache":require_cache, "strictOffscreenCulling":require_culling, "scope":"Headless script sync CPU timing and actual observable pose/caching/simulation/skinned geometry contracts. CPU geometry is prewarmed. GPU time, draw calls, displayed FPS and actual play population are outside this probe.", "godot":Engine.get_version_info().string}, "  "))
		file.close()
	print("PERFORMANCE_CONTRACTS_QA ", JSON.stringify({"checks":checks, "failures":failures, "probes":observations.size(), "report":path}))
	quit(0 if failures.is_empty() else 1)
