extends SceneTree

const Battlefield = preload("res://native/battlefield_3d.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
const FIELD_WIDTH: float = 18.5
const ELEVATION: float = 50.0
var checks: int = 0
var failures: Array[String] = []
var render: bool = false
var reports: Array = []

func _initialize() -> void:
	Engine.max_fps = 60
	render = "--gpu" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures.append(note)
		push_error("NATIVE_BATTLEFIELD: " + note)

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/native-battlefield-"):
		push_error("An isolated native-battlefield profile is required.")
		quit(2)
		return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check(maps.size() == 40, "All 40 authored historical maps are available")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.mesh_lod_threshold = 3.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if render else SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("777f73")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b1bfd0")
	environment.environment.ambient_light_energy = 0.32
	world.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.light_color = Color("fff0d0")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.shadow_bias = .10
	sun.shadow_normal_bias = .80
	sun.directional_shadow_fade_start = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45
	world.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = FIELD_WIDTH
	camera.near = .1
	camera.far = 45.0
	camera.current = true
	camera.position = Vector3(0,30,30/tan(deg_to_rad(ELEVATION)))
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var battlefield: Node3D = Battlefield.new()
	# This verifies the authored native source geometry, independently of the
	# current rendered-art rollout. The hybrid presentation has its own GPU QA.
	battlefield.art_manifest_path = "user://native-geometry-only-manifest.json"
	world.add_child(battlefield)
	var fingerprints: Dictionary = {}
	var chosen: Array = [0] if "--smoke" in OS.get_cmdline_user_args() else ([0,3,8,18,39] if render else range(40))
	for map_index in chosen:
		var config: Dictionary = maps[map_index]
		var start_time: int = Time.get_ticks_msec()
		var depth: float = FIELD_WIDTH / (1280.0 / 720.0) / sin(deg_to_rad(ELEVATION))
		battlefield.configure(config,FIELD_WIDTH,depth,ELEVATION)
		var info: Dictionary = battlefield.diagnostics()
		info["buildMilliseconds"] = Time.get_ticks_msec() - start_time
		reports.append(info)
		check(info.sourceDataContractValid, "Valid source geometry: " + str(config.id))
		check(not info.photoFloor, "No photo floor: " + str(config.id))
		check(info.terrainTriangles == 12288, "Real 96 by 64 terrain: " + str(config.id))
		check(info.roadSegmentCount > 0 and info.roadTriangles > 0, "Real authored road meshes: " + str(config.id))
		var expected_gates: int = 0
		for objective in config.objectives:
			if battlefield.objective_presentation(objective) == "castle_gate": expected_gates += 1
		check(info.gateCount == expected_gates, "Only actual castle-gate objectives build fixed gates: " + str(config.id))
		check(info.heightMaximum - info.heightMinimum > 0.025, "Physical relief: " + str(config.id))
		check(info.scannedModels > 0, "Real PBR natural model meshes: " + str(config.id))
		check(not fingerprints.has(info.physicalGeometryFingerprint), "Distinct actual geometry, ignoring all identifiers: " + str(config.id))
		fingerprints[info.physicalGeometryFingerprint] = true
		check(info.roofSlopeNormalUp, "Roof slopes have upward-facing normals: " + str(config.id))
		var rebuilds: int = battlefield.rebuild_count
		battlefield.configure(config,FIELD_WIDTH,depth,ELEVATION)
		check(battlefield.rebuild_count == rebuilds, "Unchanged configure does not rebuild: " + str(config.id))
		for path in config.paths:
			for point in path.points:
				var p: Vector2 = Vector2(float(point.x),float(point.y))
				var elevated: Vector3 = battlefield.world_point(p)
				var planar: Vector3 = Vector3((p.x-.5)*FIELD_WIDTH,0,(p.y-.5)*depth)
				var difference: Vector3 = elevated - planar
				var projection_error: float = difference.z * sin(deg_to_rad(ELEVATION)) - difference.y * cos(deg_to_rad(ELEVATION))
				check(absf(projection_error) < 0.0001, "Exact elevated path projection: " + str(config.id))
		_validate_navigation(config,battlefield,camera)
		_validate_draped_roads(config,battlefield)
		if render:
			var demo_actors: Array[Node] = []
			var points: Array = config.paths[0].points
			for index in range(4):
				var actor: Node3D = Actor.new()
				world.add_child(actor)
				actor.configure("spear" if index < 2 else "archer", index < 2, 1)
				actor.scale = Vector3.ONE * .70
				var original: Dictionary = points[mini(index+1,points.size()-1)]
				actor.position = battlefield.world_point(Vector2(float(original.x),float(original.y)))
				demo_actors.append(actor)
			if map_index == 18:
				sun.light_energy = .43
				sun.light_color = Color("adbfda")
				environment.environment.ambient_light_energy = .26
			else:
				sun.light_energy = 1.45
				sun.light_color = Color("fff0d0")
				environment.environment.ambient_light_energy = .32
			for unused in range(16):
				await process_frame
			await RenderingServer.frame_post_draw
			info["visibleDrawCalls"] = viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			info["shadowDrawCalls"] = viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			info["renderedPrimitiveCount"] = viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
			var frame_start: int = Time.get_ticks_usec()
			for unused in range(30): await process_frame
			info["observedFrameMilliseconds"] = (Time.get_ticks_usec()-frame_start)/30000.0
			info["perfSceneActorCount"] = demo_actors.size()
			var image: Image = viewport.get_texture().get_image()
			check(image != null and not image.is_empty(), "Real GPU rendered image: " + str(config.id))
			if image != null:
				var target: String = "user://stage-%02d-%s.png" % [map_index+1,str(config.id)]
				image.save_png(ProjectSettings.globalize_path(target))
			if map_index == 0 and image != null:
				sun.shadow_enabled = false
				for unused in range(4): await process_frame
				await RenderingServer.frame_post_draw
				var no_shadow: Image = viewport.get_texture().get_image()
				no_shadow.save_png(ProjectSettings.globalize_path("user://stage-01-shadow-off.png"))
				var changed: int = 0
				for y in range(0,image.get_height(),3):
					for x in range(0,image.get_width(),3):
						var a: Color = image.get_pixel(x,y)
						var b: Color = no_shadow.get_pixel(x,y)
						if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > .06:
							changed += 1
				info["shadowDifferenceSampledPixels"] = changed
				check(changed > 1200,"Real shadows change the actually rendered ground")
				sun.shadow_enabled = true
			for actor in demo_actors:
				actor.free()
		await process_frame
	_validate_cached_models()
	var cache_before_release: Dictionary = Battlefield.shared_cache_diagnostics()
	world.free()
	viewport.free()
	Battlefield.release_shared_resources()
	check(Battlefield.shared_cache_diagnostics().modelVariantGroups == 0,"Model resources released at shutdown")
	check(Battlefield.shared_cache_diagnostics().primitiveMeshes == 0,"Primitive resources released at shutdown")
	check(Battlefield.shared_cache_diagnostics().materials.textureCount == 0,"Terrain texture resources released at shutdown")
	check(Battlefield.shared_cache_diagnostics().materials.materialCount == 0,"Terrain material resources released at shutdown")
	var out: FileAccess = FileAccess.open("user://report.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"render":render,"stages":reports,"sharedCachesBeforeShutdown":cache_before_release},"\t"))
	print("NATIVE_BATTLEFIELD checks=%d failures=%d render=%s" % [checks,failures.size(),str(render)])
	quit(0 if failures.is_empty() else 1)

func _validate_navigation(config: Dictionary,battlefield: Node3D,camera: Camera3D) -> void:
	var route_samples: int = 0
	var wet_route_samples: Array = []
	var worst_projection_error: float = 0.0
	var routes: Array = []
	for path in config.paths:
		routes.append(path.points)
	for entry in config.get("sideAmbushEntrances",[]):
		var points: Array = entry.get("connectionPoints",[]).duplicate(true)
		points.push_front(entry.point)
		routes.append(points)
	for points in routes:
		for index in range(points.size()-1):
			var a: Vector2 = Vector2(float(points[index].x),float(points[index].y))
			var b: Vector2 = Vector2(float(points[index+1].x),float(points[index+1].y))
			var steps: int = maxi(2,ceili(((b-a)*Vector2(battlefield.width,battlefield.depth)).length()/.10))
			for step in range(steps+1):
				var p: Vector2 = a.lerp(b,float(step)/steps)
				route_samples += 1
				if battlefield._is_water(p):
					wet_route_samples.append({"x":p.x,"y":p.y})
				var projected: Vector2 = camera.unproject_position(battlefield.world_point(p))
				worst_projection_error = maxf(worst_projection_error,projected.distance_to(p*Vector2(1280,720)))
	check(wet_route_samples.is_empty(),"Every actual route stays on ground or a physical crossing: "+str(config.id)+" "+JSON.stringify(wet_route_samples.slice(0,4)))
	check(worst_projection_error < .2,"Actual camera projection aligns with all navigation samples: "+str(config.id))
	var blocked_zones: Array = []
	for zone in config.get("buildZones",[]):
		var p: Vector2 = Vector2(float(zone.x),float(zone.y))
		if battlefield._is_water(p):
			blocked_zones.append({"x":p.x,"y":p.y})
	check(blocked_zones.is_empty(),"Every tower zone stands on actual ground: "+str(config.id)+" "+JSON.stringify(blocked_zones))
	check(route_samples > 20,"Routes sampled across real terrain: "+str(config.id))
	if int(config.get("stageNumber",0)) == 39:
		var fake_inundation: bool = false
		for region in battlefield.water_regions:
			fake_inundation = fake_inundation or str(region.kind) == "wetland"
		check(not fake_inundation,"Oshi failed inundation stays wet soil; documented natural water remains")
	if int(config.get("stageNumber",0)) == 23:
		var trace_objects: Array = []
		for object in battlefield.objects:
			if str(object.kind).begins_with("trace:"):
				trace_objects.append(object)
		check(trace_objects.size() >= 2,"Later Miki actually renders old earthworks and depleted camp traces")

func _validate_cached_models() -> void:
	var unused_vertices: int = 0
	var mismatched_attributes: int = 0
	for variants in Battlefield.model_cache.values():
		for variant in variants:
			var mesh: Mesh = variant.mesh
			for surface in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var referenced: Dictionary = {}
				for index in indices:
					referenced[index] = true
				unused_vertices += vertices.size()-referenced.size()
				for slot in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV]:
					if arrays[slot] != null and arrays[slot].size() != vertices.size():
						mismatched_attributes += 1
				if arrays[Mesh.ARRAY_TANGENT] != null and arrays[Mesh.ARRAY_TANGENT].size() != vertices.size()*4:
					mismatched_attributes += 1
	check(unused_vertices == 0,"Real optimized mesh buffers contain no unused source-scan vertices")
	check(mismatched_attributes == 0,"Normals, UVs and tangents remain aligned after optimization")

func _validate_draped_roads(config: Dictionary,battlefield: Node3D) -> void:
	var road: MeshInstance3D = battlefield.get_node("AuthoredRoads")
	var arrays: Array = road.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var worst_height_error: float = 0.0
	for index in range(0,indices.size(),3):
		var ia: int = indices[index]
		var ib: int = indices[index+1]
		var ic: int = indices[index+2]
		var norm: Vector2 = (uvs[ia]+uvs[ib]+uvs[ic])/3.0/Vector2(battlefield.width,battlefield.depth)
		var actual_height: float = (vertices[ia].y+vertices[ib].y+vertices[ic].y)/3.0
		var desired_height: float = battlefield.height_at(norm)+Battlefield.ROAD_SURFACE_OFFSET
		worst_height_error = maxf(worst_height_error,absf(actual_height-desired_height))
	check(worst_height_error < .001,"Every road triangle follows the actual terrain surface: "+str(config.id)+" max="+str(worst_height_error))
