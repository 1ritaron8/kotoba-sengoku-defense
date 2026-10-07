extends SceneTree

const Troops = preload("res://native/troops_3d.gd")
const Fortification = preload("res://native/enemy_fortification_3d.gd")
var checks: int = 0
var failures: Array = []
var details: Array = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("Fortification QA: " + message)

func _initialize() -> void:
	call_deferred("run")

func sample(id_value: int, type_name: String, fortification: bool = false) -> Dictionary:
	return {"id": id_value, "type": type_name, "kind": type_name, "friendly": false, "hostile": true,
		"side": "enemy", "x": 0.40 + id_value * 0.006, "y": 0.51,
		"aimX": 0.0, "aimY": 1.0, "animation": "idle", "animationClock": 0.0,
		"motionTime": 0.0, "hp": 80.0, "maxHp": 80.0, "dead": false,
		"fortification": fortification, "stationaryEnemy": fortification, "sailing": false}

func run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower()
	check(profile.begins_with("c:/jp_df/tests/profiles/enemy-fortification/"), "isolated APPDATA is required")
	if not failures.is_empty():
		finish()
		return
	for type_name in ["enemy_archer", "enemy_gunner"]:
		for ruined in [false, true]:
			var mesh: ArrayMesh = Fortification.build_mesh(type_name, ruined)
			check(mesh == Fortification.build_mesh(type_name, ruined), type_name + " geometry cache misses")
			check(mesh.get_surface_count() == 1, type_name + " is not one combined draw surface")
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			check(not vertices.is_empty() and indices.size() > 100 and indices.size() < 3600, type_name + " implausible prop geometry cost")
			check(normals.size() == vertices.size() and uv.size() == vertices.size(), type_name + " lacks normals or UV")
			check(indices.size() % 3 == 0, type_name + " incomplete triangles")
			for index in indices:
				check(index >= 0 and index < vertices.size(), type_name + " invalid index")
			for index in range(vertices.size()):
				check(vertices[index].is_finite() and normals[index].is_finite() and uv[index].is_finite(), type_name + " nonfinite geometry")
				check(absf(normals[index].length() - 1.0) < 0.001, type_name + " nonunit normal")
				check(vertices[index].y >= -0.055 and vertices[index].y <= 1.34, type_name + " ground or height mismatch")
				check(absf(vertices[index].x) <= 1.0 and absf(vertices[index].z) <= 0.55, type_name + " excessive footprint")
			details.append({"kind": type_name, "ruined": ruined, "vertices": vertices.size(), "triangles": indices.size() / 3})
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var troops = Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(1100, 620))
	troops.set_stage(maps[0])
	var states: Array = [sample(11, "enemy_archer", true), sample(12, "enemy_gunner", true), sample(13, "enemy_cavalry"), sample(14, "enemy_archer")]
	var original: Array = states.duplicate(true)
	troops.sync_actor_states(states)
	check(states == original, "rendering mutates authoritative backend state")
	check(troops.actors.size() == 4 and troops.fortifications.size() == 2, "stationary and mobile enemy model routing")
	check(troops.actors["11:0"].unit_type == "archer" and troops.actors["12:0"].unit_type == "gunner", "ranged types lack original models")
	check(troops.actors["13:0"].unit_type == "commander" and troops.actors["13:0"].mount != null, "enemy cavalry lacks mount")
	for key in ["11:0", "12:0"]:
		var prop = troops.fortifications[key]
		var actor = troops.actors[key]
		check(actor.hostile and not actor.hero_detail, key + " hostile battlefield identity")
		check(prop.position == actor.position and prop.scale == actor.scale, key + " cover is detached from crew")
		check(prop.get_meta("render_only") and prop.get_child_count() == 1, key + " render-only contract or batching broken")
		check(prop.surface_material != actor.materials.combined, key + " local shader is shared with actor")
		check(prop.shell.layers == 3 and prop.shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, key + " lighting or shadow masks")
		check(is_equal_approx(float(prop.surface_material.get_shader_parameter("local_exposure")), float(actor.materials.combined.get_shader_parameter("local_exposure"))), key + " actor/cover local light disagree")
		check(prop.diagnostics().triangles < 1200, key + " draw cost unbounded")
	var first_prop = troops.fortifications["11:0"]
	var standing_mesh: ArrayMesh = first_prop.shell.mesh
	var fixed_yaw: float = first_prop.rotation.y
	states[0].aimX = 1.0
	states[0].aimY = 0.0
	states[0].motionTime = 0.25
	troops.sync_actor_states(states)
	check(troops.fortifications["11:0"] == first_prop and first_prop.shell.mesh == standing_mesh, "aim change rebuilds cover")
	check(is_equal_approx(first_prop.rotation.y, fixed_yaw), "cover turns with aiming soldier")
	states[0].dead = true
	states[0].animation = "death"
	states[0].animationClock = 0.35
	states[0].motionTime = 0.6
	states[0].hp = 0.0
	troops.sync_actor_states(states)
	check(first_prop.broken and first_prop.shell.mesh != standing_mesh, "destroyed firing position lacks broken boards")
	check(first_prop.position == troops.actors["11:0"].position, "death cover teleports from logical position")
	check(troops.side_markers.size() == 3, "destroyed cover keeps living faction marker")
	var earlier: Transform3D = first_prop.shell.transform
	troops.sync_actor_states(states)
	check(first_prop.shell.transform == earlier, "pause changes debris pose")
	states[0].dead = false
	states[0].animation = "idle"
	states[0].animationClock = 0.0
	states[0].motionTime = 0.0
	states[0].aimY = -1.0
	states[0].aimX = 0.0
	troops.sync_actor_states(states)
	check(not first_prop.broken and first_prop.shell.mesh == standing_mesh, "reused battle ID retains destroyed cover")
	check(is_equal_approx(first_prop.rotation.y, troops.actors["11:0"].rotation.y), "reused battle ID retains earlier ground orientation")
	states[1].sailing = true
	troops.sync_actor_states(states)
	check(not troops.fortifications.has("12:0"), "wooden land cover appears on a boat")
	states[1].sailing = false
	states[1].friendly = true
	troops.sync_actor_states(states)
	check(not troops.fortifications.has("12:0"), "friendly soldier inherits hostile fortification")
	states.remove_at(0)
	troops.sync_actor_states(states)
	check(not troops.fortifications.has("11:0"), "expired death actor leaves prop behind")
	troops.sync_placement_preview({"active": true, "visible": true, "type": "archer", "position": {"x": 0.6, "y": 0.6}, "evolution": 0})
	check(troops.fortifications.is_empty() and troops.actors.size() == 3, "placement ghost registers an enemy prop")
	troops.sync_actor_states([])
	check(troops.actors.is_empty() and troops.fortifications.is_empty() and troops.contact_shadows.is_empty(), "reset leaves actors, cover or contacts")
	if "--capture" in OS.get_cmdline_user_args():
		await capture_fixture(troops, maps)
	troops.queue_free()
	await process_frame
	finish()

func capture_fixture(troops: Node, maps: Array) -> void:
	# Optional GPU review performed by root. This is a render-only authored
	# fixture, not a gameplay density, spawn, health or combat-balance claim.
	troops.set_field_size(Vector2(1440, 900))
	var visual_states: Array = []
	for index in range(3):
		var type_name: String = ["enemy_archer", "enemy_gunner", "enemy_cavalry"][index]
		var state: Dictionary = sample(31 + index, type_name, index < 2)
		state.x = 0.32 + index * 0.17
		state.y = 0.48
		state.animation = "attack"
		state.animationClock = 0.25
		visual_states.append(state)
	for theme in ["forest", "night"]:
		var stage: Dictionary = maps[0] if theme == "forest" else maps[8]
		troops.set_stage(stage)
		troops.sync_actor_states(visual_states)
		troops.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for _frame in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		var image_value: Image = troops.viewport.get_texture().get_image()
		var image_path: String = "C:/JP_DF/dist/preview-enemy-fortifications-" + theme + ".png"
		check(image_value != null and not image_value.is_empty(), "GPU " + theme + " image missing")
		if image_value != null and not image_value.is_empty():
			check(image_value.save_png(image_path) == OK, "GPU " + theme + " save failed")
			details.append({"capture": image_path, "scope": "render-only original models + firing cover; no actual battle simulation"})
	visual_states[0].dead = true
	visual_states[0].animation = "death"
	visual_states[0].animationClock = 0.4
	visual_states[0].motionTime = 0.4
	troops.sync_actor_states(visual_states)
	for _frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var dead_image: Image = troops.viewport.get_texture().get_image()
	check(dead_image != null and not dead_image.is_empty(), "GPU destroyed firing cover image missing")
	if dead_image != null and not dead_image.is_empty():
		check(dead_image.save_png("C:/JP_DF/dist/preview-enemy-fortifications-destroyed.png") == OK, "GPU destroyed firing cover save failed")

func finish() -> void:
	var path: String = "user://qa_enemy_fortification_3d.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "QA report cannot be saved")
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "meshes": details, "scope": "CPU contract/geometry only; actual GPU image is reviewed separately by root", "report": ProjectSettings.globalize_path(path)}, "  "))
		file.close()
	print("ENEMY_FORTIFICATION_QA ", JSON.stringify({"checks": checks, "failures": failures, "report": ProjectSettings.globalize_path(path)}))
	quit(0 if failures.is_empty() else 1)
