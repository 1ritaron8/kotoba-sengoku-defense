extends SceneTree
## Deliberately injected layout diagnostics; never evidence of natural gameplay.

const Battlefield = preload("res://native/battlefield_3d.gd")
const RenderedArt = preload("res://native/rendered_battlefield_helpers.gd")
const Materials = preload("res://native/battlefield_materials.gd")
const Game = preload("res://native/game.gd")
const Troops = preload("res://native/troops_3d.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
const ActorMaterials = preload("res://native/actor_materials.gd")
const TerrainLightField = preload("res://native/terrain_light_field.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
const SkinnedRenderer = preload("res://native/sengoku_skinned_renderer.gd")
const SIZE: Vector2i = Vector2i(1280,720)
const WIDTH: float = 18.5
const ELEVATION: float = 50.0
const DEPTH: float = WIDTH/(1280.0/720.0)/sin(deg_to_rad(ELEVATION))
const UNIT_IDS: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const SOURCE_PATHS: Array[String] = ["res://native/maps.json","res://native/battlefield_3d.gd","res://native/battlefield_materials.gd","res://native/rendered_battlefield_helpers.gd","res://native/troops_3d.gd","res://native/sengoku_actor_3d.gd","res://native/sengoku_skinned_renderer.gd","res://native/actor_materials.gd","res://native/terrain_light_field.gd","res://native/mobile_objective_cart_3d.gd","res://native/game.gd","res://native/battle_support.gd","res://native/battlefield_presentation.gd"]
var checks: int = 0
var failures: Array[String] = []
var reports: Array = []
var gpu: bool = false
var source_hashes: Dictionary = {}
var runtime_manifest_hash: String = ""
var game: Node2D
var output_folder: String = "user://campaign-layouts"
var max_art_cache: int = 0

func _initialize() -> void:
	Engine.max_fps = 60
	gpu = "--gpu" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures.append(note)
		if failures.size()<=30: push_error("CAMPAIGN_LAYOUTS: "+note)

func point(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x",0)),float(value.get("y",0)))

func coordinates(value: Vector2) -> Dictionary:
	return {"x":value.x,"y":value.y}

func collect_source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in SOURCE_PATHS: result[path] = FileAccess.get_sha256(path)
	return result

func prepare_geometry(builder: Node3D, config: Dictionary) -> void:
	# Resolve exactly the shared height grid, without creating native props or
	# silently rendering fallback geometry while the artwork is incomplete.
	builder.stage = config
	builder.history = config.get("historicalBattlefield",{})
	builder.width = WIDTH
	builder.depth = DEPTH
	builder.elevation = ELEVATION
	builder.seed_value = absi(str(config.id).hash())
	builder._collect_geometry()
	builder._build_height_grid()

func placement_record(builder: Node3D, zone: Dictionary, type_name: String, label: String, identifier: int) -> Dictionary:
	var authored: Vector2 = zone.get("position",point(zone))
	var preview: Dictionary = game.placement_preview(authored)
	var actual: Vector2 = point(preview.get("position",coordinates(authored)))
	var suggestion: Vector2 = authored
	if not bool(preview.get("valid",false)):
		suggestion = game._zone_placement_hint(zone,type_name)
	var world: Vector3 = builder.world_point(actual)
	var mirrored: bool = Presentation.mirror_for_stage(builder.stage)
	var displayed: Vector2 = Presentation.to_view(actual,mirrored)
	return {"label":label,"zoneId":str(zone.get("id","")),"type":type_name,"actorId":identifier,"authoredPosition":coordinates(authored),"actualPosition":coordinates(actual),"canonicalPosition":coordinates(actual),"displayedPosition":coordinates(displayed),"independentlyPlaceable":bool(preview.get("valid",false)),"previewReason":str(preview.get("reason","")),"fallbackHint":coordinates(suggestion),"heightWorld":world.y,"worldPosition":{"x":world.x,"y":world.y,"z":world.z},"inBlockedWater":builder._is_water(actual),"expectedCanonicalPixel":coordinates(actual*Vector2(SIZE)),"expectedDisplayedPixel":coordinates(displayed*Vector2(SIZE))}

func prepare_stage(builder: Node3D, config: Dictionary) -> Dictionary:
	prepare_geometry(builder,config)
	game.load_map(config)
	check(game.begin_placement("archer"),"Archer preview opens for independent diagnostic: "+str(config.id))
	var placements: Array = []
	var index: int = 0
	var invalid: int = 0
	for zone in game.zones:
		if str(zone.get("placementRole",""))!="ranged": continue
		index += 1
		var record: Dictionary = placement_record(builder,zone,"archer","B%d" % index,1000+index)
		placements.append(record)
		if not bool(record.independentlyPlaceable): invalid += 1
		check(not bool(record.inBlockedWater),"Authored archer center avoids blocked water: "+str(config.id)+" "+str(record.label))
	check(index == config.get("buildZones",[]).size(),"Every authored ranged center is included: "+str(config.id))
	check(game.begin_placement("monk"),"Support preview opens for independent diagnostic: "+str(config.id))
	var support_index: int = 0
	for zone in game.zones:
		if str(zone.get("placementRole",""))!="ground": continue
		support_index += 1
		var record: Dictionary = placement_record(builder,zone,"monk","S%d" % support_index,2000+support_index)
		placements.append(record)
		if not bool(record.independentlyPlaceable): invalid += 1
		check(not bool(record.inBlockedWater),"Authored support center avoids blocked water: "+str(config.id)+" "+str(record.label))
	check(support_index == config.get("tactics",{}).get("groundPosts",[]).size(),"Every authored ground/support post is included: "+str(config.id))
	var routes: Array = []
	var route_samples: int = 0
	var wet_samples: int = 0
	var projection_error: float = 0.0
	for route in config.get("paths",[]):
		var points: Array = route.get("points",[])
		for segment in range(points.size()-1):
			var start: Vector2 = point(points[segment])
			var end: Vector2 = point(points[segment+1])
			for step in range(25):
				var sample: Vector2 = start.lerp(end,float(step)/24.0)
				var world: Vector3 = builder.world_point(sample)
				var projected: Vector2 = Vector2(world.x/WIDTH+.5,(world.z-world.y/tan(deg_to_rad(ELEVATION)))/DEPTH+.5)*Vector2(SIZE)
				projection_error = maxf(projection_error,projected.distance_to(sample*Vector2(SIZE)))
				route_samples += 1
				if builder._is_water(sample): wet_samples += 1
		routes.append({"id":route.get("id",""),"objectiveId":route.get("objectiveId",""),"points":points.duplicate(true)})
	check(wet_samples == 0,"Every authored walking route avoids blocked deep water: "+str(config.id))
	check(projection_error < .025,"Shared terrain height keeps every path sample at the artwork coordinate: "+str(config.id))
	var actual_objectives: Array = []
	for marker in game.field_markers():
		if str(marker.get("markerKind",""))=="objective": actual_objectives.append(marker.duplicate(true))
	var physical: String = JSON.stringify(builder._physical_contract(config)).sha256_text()
	var art: Dictionary = RenderedArt.resolve(config,physical)
	var history: Dictionary = config.get("historicalBattlefield",{})
	var decision: Dictionary = Presentation.decision(config)
	check(bool(decision.satisfiable),"Every friendly initial objective can be presented at the left or lower screen: "+str(config.id))
	for objective in actual_objectives:
		var displayed: Vector2 = Presentation.to_view(point(objective),bool(decision.mirrored))
		objective["displayedPosition"] = coordinates(displayed)
		check(Presentation.allows_friendly(displayed),"The actual objective follows the approved display orientation: "+str(config.id))
	return {"stageId":config.id,"stageNumber":int(config.stageNumber),"title":config.get("title",""),"presentationMirrored":decision.mirrored,"coordinateSpace":"canonical","captureCoordinateSpace":"displayed_pixels","physicalGeometryFingerprint":physical,"sourceMapSha256":source_hashes["res://native/maps.json"],"artPath":art.get("artPath",""),"artSha256":art.get("artSha256",""),"preparedArtMode":art.get("mode","native"),"preparedArtCoverage":art.get("coverage",0),"distributionReadyAtPreparation":art.get("distributionReady",false),"placements":placements,"invalidAuthoredCentres":invalid,"rangedCentres":index,"supportCentres":support_index,"commonEnemyEntry":config.get("commonEnemyEntry",{}),"routes":routes,"routeSamples":route_samples,"blockedWaterRouteSamples":wet_samples,"pathProjectionErrorPixels":projection_error,"sideAmbushEntrances":config.get("sideAmbushEntrances",[]),"liveObjectivesAtStart":actual_objectives,"escortRoute":config.get("escortRoute",[]),"historicalTerrain":history.get("terrain",{}),"historicalLandmarks":history.get("sceneLandmarks",[]),"historicalWeather":history.get("weather",{}),"historicalTimeOfDay":history.get("timeOfDay",""),"waterFeatures":history.get("waterFeatures",[]),"bridges":config.get("bridges",[])}

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/native-battlefield-hybrid-campaign-layouts-").to_lower()):
		push_error("An isolated native-battlefield-hybrid-campaign-layouts profile is required")
		quit(2)
		return
	if gpu and DisplayServer.get_name()=="headless":
		push_error("GPU captures require the real rendering device")
		quit(2)
		return
	source_hashes = collect_source_hashes()
	runtime_manifest_hash = FileAccess.get_sha256(RenderedArt.MANIFEST_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_folder))
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check(maps.size() == 40,"Exactly forty source stages are available")
	game = Game.new()
	game.three_d_enabled = true
	root.add_child(game)
	game.hide()
	game.set_process(false)
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	game.configure_roster(catalog,UNIT_IDS,{})
	var builder: Node3D = Battlefield.new()
	var fingerprints: Dictionary = {}
	var all_rendered_ready: bool = true
	for config in maps:
		var record: Dictionary = prepare_stage(builder,config)
		check(not fingerprints.has(str(record.physicalGeometryFingerprint)),"Actual physical geometry is unique: "+str(config.id))
		fingerprints[str(record.physicalGeometryFingerprint)] = true
		reports.append(record)
		if str(record.preparedArtMode)!="rendered" or not bool(record.distributionReadyAtPreparation): all_rendered_ready = false
	builder.free()
	if gpu:
		check(all_rendered_ready,"All forty images must be registered and verified before any diagnostic GPU capture; fallback is forbidden")
		if all_rendered_ready:
			await capture_campaign(maps)
	check(collect_source_hashes() == source_hashes,"The diagnostic did not change source, navigation, actor or map files")
	check(game.units.is_empty() and game.recruitment_queue.is_empty() and game.enemies.is_empty(),"Injected layout diagnostics did not create a real army or advance natural gameplay")
	game.free()
	Battlefield.release_shared_resources()
	var caches: Dictionary = Battlefield.shared_cache_diagnostics()
	check(int(caches.materials.renderedArtTextureCount) == 0,"All full-resolution artwork textures are released at diagnostic exit")
	var png_count: int = 0
	var fallback_count: int = 0
	var invalid_count: int = 0
	var mirrored_count: int = 0
	for record in reports:
		if record.has("capturePath"): png_count += 1
		if record.has("actualRenderMode") and str(record.actualRenderMode)!="rendered": fallback_count += 1
		invalid_count += int(record.invalidAuthoredCentres)
		if bool(record.presentationMirrored): mirrored_count += 1
	check(reports.size()==40,"Every current lower-base battlefield has an individually checked display orientation")
	check(invalid_count==0,"Every authored deployment center is independently legal")
	if gpu:
		check(png_count==40 and fallback_count==0,"Final GPU evidence contains forty actual images without fallback terrain")
	var manifest: Dictionary = {"version":2,"captureKind":"injected_authored_layout_diagnostic","naturalGameplay":false,"armyWasRecruited":false,"deploymentValidation":"Every authored center is checked independently against real Game.placement_preview with an empty army; the combined display is deliberately injected.","coordinateContract":{"sourceGeometry":"canonical normalized x/y and world positions","capture":"Actual root viewport, including TextureRect.flip_h; upright diagnostic CanvasLayer in displayed pixels","artImage":"Registered original canonical artwork; PNG was not postprocessed or flipped","bodyBounds":"Projected source joint mesh AABBs; include weapons, conservative proxy","occlusion":"Artwork has no semantic depth mask. Source landmark overlap candidates require manual image review; they are not automatic confirmed occlusion."},"phase":"gpu_captured" if gpu else "cpu_prepared_gpu_pending","sourceHashes":source_hashes,"runtimeArtManifestSha256":runtime_manifest_hash,"camera":{"elevation":ELEVATION,"worldWidth":WIDTH,"width":SIZE.x,"height":SIZE.y,"projection":"orthographic"},"legend":{"B":"Authored ranged center with a real original archer","S":"Authored ground/support center with a real original monk","cyanLine":"Shared movement route","orangeLine":"Authored side ingress","redPin":"Independently invalid authored position","objective":"Live initial objective position, including mobile carts"},"stageCount":reports.size(),"pngCount":png_count,"fallbackCount":fallback_count if gpu else null,"artCoverageComplete":all_rendered_ready,"mirroredStageCount":mirrored_count,"originalOrientationStageCount":reports.size()-mirrored_count,"maxArtTextureCacheCount":max_art_cache if gpu else null,"invalidAuthoredCentres":invalid_count,"checks":checks,"failures":failures,"stages":reports}
	var file: FileAccess = FileAccess.open(output_folder+"/manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	file.close()
	print("CAMPAIGN_LAYOUTS checks=%d failures=%d gpu=%s stages=%d pngs=%d invalidCentres=%d" % [checks,failures.size(),str(gpu),reports.size(),png_count,invalid_count])
	quit(0 if failures.is_empty() else 1)

func capture_campaign(maps: Array) -> void:
	root.min_size = Vector2i(640,360)
	root.size = SIZE
	root.content_scale_size = SIZE
	var troops: Control = Troops.new()
	troops.stage = maps[0]
	troops.field_size = Vector2(SIZE)
	troops.friendly_formation_count = 1
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(SIZE))
	var image_hashes: Dictionary = {}
	for index in range(maps.size()):
		var config: Dictionary = maps[index]
		var record: Dictionary = reports[index]
		troops.set_stage(config)
		check(troops.presentation_mirrored==bool(record.presentationMirrored) and troops.output.flip_h==bool(record.presentationMirrored),"Actual TextureRect orientation follows the shared presentation decision: "+str(config.id))
		var layer: Dictionary = troops.battlefield.render_layer_contract()
		check(str(layer.mode)=="rendered" and bool(layer.distributionReady) and int(layer.coverage)==40,"The actual diagnostic viewport uses verified forty-stage artwork: "+str(config.id))
		check(bool(layer.rawArtHashVerified) and bool(layer.sourceDataVerified),"Actual runtime artwork and source SHA are verified: "+str(config.id))
		check(not image_hashes.has(str(layer.artSha256)),"Every capture uses distinct actual artwork: "+str(config.id))
		image_hashes[str(layer.artSha256)] = true
		var states: Array = []
		var entry: Vector2 = point(config.paths[0].points[0])
		for placement in record.placements:
			var position: Vector2 = point(placement.actualPosition)
			var aim: Vector2 = (entry-position).normalized()
			states.append({"id":placement.actorId,"type":placement.type,"friendly":true,"dead":false,"x":position.x,"y":position.y,"aimX":aim.x,"aimY":aim.y,"animation":"idle","animationClock":0.75,"animationPhase":0.0,"motionTime":0.75,"campaignLevel":1,"evolution":0,"hp":100.0,"maxHp":100.0,"flags":{}})
		troops.sync_actor_states(states)
		troops.sync_field_markers(record.liveObjectivesAtStart,0.0)
		for actor in troops.actors.values(): actor.set_process(false)
		var overlay: CanvasLayer = CanvasLayer.new()
		overlay.layer = 1
		root.add_child(overlay)
		draw_layout(overlay,troops,record)
		var worst_projection: float = 0.0
		var worst_canonical_projection: float = 0.0
		var initial_feet: Dictionary = {}
		var landmark_bounds: Array = architecture_bounds(troops,record.historicalLandmarks)
		for placement in record.placements:
			var key: String = "%d:0" % int(placement.actorId)
			check(troops.actors.has(key),"The authored center has an actual original 3D actor: "+str(config.id)+" "+str(placement.label))
			if not troops.actors.has(key): continue
			var actor: Node3D = troops.actors[key]
			var canonical_pixel: Vector2 = troops.camera.unproject_position(actor.position)
			var pixel: Vector2 = troops.project_world_to_field(actor.position)
			var expected: Vector2 = point(placement.expectedDisplayedPixel)
			worst_projection = maxf(worst_projection,pixel.distance_to(expected))
			worst_canonical_projection = maxf(worst_canonical_projection,canonical_pixel.distance_to(point(placement.expectedCanonicalPixel)))
			initial_feet[key] = pixel
			placement["actualActorDisplayedPixel"] = coordinates(pixel)
			placement["actualActorCanonicalPixel"] = coordinates(canonical_pixel)
			placement["actualActorHeightWorld"] = actor.position.y
			placement["actualActorScale"] = actor.scale.x
			var body_bounds: Rect2 = projected_actor_bounds(troops,actor)
			placement["projectedBodyBoundsDisplayedPixels"] = rectangle(body_bounds)
			var candidates: Array = []
			for landmark in landmark_bounds:
				var bounds: Rect2 = Rect2(point(landmark.pixelBounds.position),point(landmark.pixelBounds.size))
				if bounds.intersects(body_bounds):
					candidates.append({"id":landmark.id,"kind":landmark.kind,"labelKo":landmark.labelKo,"footInsideProxy":bounds.has_point(pixel),"pixelBounds":landmark.pixelBounds,"status":"source_volume_candidate_manual_art_review_required"})
			placement["architectureOverlapCandidates"] = candidates
		check(worst_projection < .025,"All real actor feet use the accepted authored surface coordinate: "+str(config.id))
		check(worst_canonical_projection < .025,"The canonical world foot anchors are unchanged by presentation: "+str(config.id))
		var arrays: Array = troops.battlefield.ground_mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var uv_error: float = 0.0
		for vertex_index in range(vertices.size()): uv_error = maxf(uv_error,vertices[vertex_index].distance_to(troops.battlefield.world_point(uvs[vertex_index])))
		check(vertices.size()==6305 and uv_error < .0001,"The rendered image remains aligned across all raised terrain vertices: "+str(config.id))
		troops.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for unused in range(8): await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(image.get_width()==SIZE.x and image.get_height()==SIZE.y,"The actual displayed root capture uses the diagnostic size: "+str(config.id))
		var first_bytes: PackedByteArray = image.get_data()
		troops.sync_actor_states(states)
		for actor in troops.actors.values(): actor.set_process(false)
		for unused in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var second_image: Image = root.get_texture().get_image()
		var stable_pixels: bool = first_bytes==second_image.get_data()
		var worst_jitter: float = 0.0
		for placement in record.placements:
			var key: String = "%d:0" % int(placement.actorId)
			if not troops.actors.has(key): continue
			var after_pixel: Vector2 = troops.project_world_to_field(troops.actors[key].position)
			var jitter: float = after_pixel.distance_to(initial_feet[key])
			worst_jitter = maxf(worst_jitter,jitter)
			placement["repeatSyncFootJitterPixels"] = jitter
		check(worst_jitter < .025,"Repeated fixed-state display has no actor foot or camera anchor jitter: "+str(config.id))
		var filename: String = "stage-%02d-%s-layout.png" % [int(config.stageNumber),str(config.id)]
		var capture_path: String = output_folder+"/"+filename
		check(image.save_png(ProjectSettings.globalize_path(capture_path))==OK,"The actual diagnostic image is saved: "+str(config.id))
		var cache: Dictionary = Materials.cache_diagnostics()
		check(int(cache.renderedArtTextureCount)<=3,"Full-resolution artwork uses the bounded three-image LRU: "+str(config.id))
		max_art_cache = maxi(max_art_cache,int(cache.renderedArtTextureCount))
		record.merge({"capturePath":ProjectSettings.globalize_path(capture_path),"captureSha256":FileAccess.get_sha256(capture_path),"actualRenderMode":layer.mode,"artPath":layer.artPath,"artSha256":layer.artSha256,"sourceDataVerified":layer.sourceDataVerified,"actualPixelSize":{"x":image.get_width(),"y":image.get_height()},"worstActorFootProjectionErrorPixels":worst_projection,"worstCanonicalFootProjectionErrorPixels":worst_canonical_projection,"repeatSyncFootJitterPixels":worst_jitter,"fixedStateDisplayedImageByteIdentical":stable_pixels,"occlusionReviewStatus":"manual_review_pending","sourceArchitectureProxies":landmark_bounds,"normalizedUvHeightVertexError":uv_error,"heightVertices":vertices.size(),"terrainTriangles":troops.battlefield.diagnostics().terrainTriangles,"artTextureCacheCount":cache.renderedArtTextureCount,"realShadowCasting":troops.sun.shadow_enabled,"visibleDrawCalls":troops.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)},true)
		overlay.free()
		troops.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if (index+1)%5==0: print("CAMPAIGN_LAYOUTS captured=%d/40" % (index+1))
	check(FileAccess.get_sha256(RenderedArt.MANIFEST_PATH)==runtime_manifest_hash,"The runtime artwork manifest remained frozen during all forty captures")
	troops.free()
	await process_frame
	Actor.material_cache.clear()
	Actor.geometry_cache.clear()
	SkinnedRenderer.cache.clear()
	ActorMaterials.shared_material = null
	ActorMaterials.shared_contact_material = null
	ActorMaterials.shared_preview_material = null
	TerrainLightField._cache.clear()

func rectangle(value: Rect2) -> Dictionary:
	return {"position":coordinates(value.position),"size":coordinates(value.size)}

func projected_actor_bounds(troops: Control,actor: Node3D) -> Rect2:
	var result: Rect2 = Rect2(troops.project_world_to_field(actor.position),Vector2.ZERO)
	for source in actor.meshes:
		if source.mesh==null or not source.get_parent().is_visible_in_tree(): continue
		var box: AABB = source.mesh.get_aabb()
		for endpoint in range(8):
			result = result.expand(troops.project_world_to_field(source.global_transform*box.get_endpoint(endpoint)))
	return result

func architecture_bounds(troops: Control,landmarks: Array) -> Array:
	var result: Array = []
	for landmark in landmarks:
		var kind: String = str(landmark.get("kind",""))
		if not ("fort" in kind or "gate" in kind or "camp" in kind or kind in ["castle","temple","city","town","village"]): continue
		var centre: Vector2 = point(landmark)
		var scale: Dictionary = landmark.get("scale",{})
		var half_size: Vector2 = Vector2(float(scale.get("w",.10)),float(scale.get("h",.07)))*.5
		var height: float = float(landmark.get("heightWorld",.8))
		var bounds: Rect2 = Rect2(troops.project_world_to_field(troops.normalized_to_world(centre)),Vector2.ZERO)
		for x in [-1.0,1.0]:
			for y in [-1.0,1.0]:
				var base: Vector3 = troops.normalized_to_world(centre+half_size*Vector2(x,y))
				bounds = bounds.expand(troops.project_world_to_field(base))
				bounds = bounds.expand(troops.project_world_to_field(base+Vector3.UP*height))
		result.append({"id":landmark.get("id",""),"kind":kind,"labelKo":landmark.get("labelKo",""),"pixelBounds":rectangle(bounds),"representation":"Conservative source landmark height/footprint proxy; artwork silhouette may differ"})
	return result

func draw_layout(overlay: CanvasLayer,troops: Control,record: Dictionary) -> void:
	for route in record.routes: add_route(overlay,troops,route.points,Color(.18,.92,.95,.8),2.0)
	for side in record.sideAmbushEntrances: add_route(overlay,troops,side.get("connectionPoints",[]),Color(1.0,.57,.25,.65),1.5)
	if not record.escortRoute.is_empty(): add_route(overlay,troops,record.escortRoute,Color(.83,.70,.97,.7),1.5)
	for placement in record.placements:
		var colour: Color = Color("ffe676") if str(placement.type)=="archer" else Color("6ce4ce")
		if not bool(placement.independentlyPlaceable): colour = Color("ff5874")
		add_pin(overlay,troops.project_world_to_field(troops.normalized_to_world(point(placement.actualPosition))),str(placement.label),colour)
	add_pin(overlay,troops.project_world_to_field(troops.normalized_to_world(point(record.commonEnemyEntry))),"ENTRY",Color("ff8587"))
	for objective in record.liveObjectivesAtStart:
		add_pin(overlay,troops.project_world_to_field(troops.normalized_to_world(point(objective))),"CART" if bool(objective.get("mobile",false)) else "BASE",Color("67dcff"))
	var caption: Label = Label.new()
	caption.text = "진단 배치 · %02d %s · 자연 플레이 화면 아님" % [int(record.stageNumber),str(record.title)]
	caption.position = Vector2(10,7)
	caption.add_theme_font_size_override("font_size",18)
	caption.add_theme_color_override("font_color",Color.WHITE)
	caption.add_theme_color_override("font_outline_color",Color.BLACK)
	caption.add_theme_constant_override("outline_size",6)
	overlay.add_child(caption)

func add_route(overlay: CanvasLayer,troops: Control,points: Array,colour: Color,width: float) -> void:
	var line: Line2D = Line2D.new()
	line.width = width
	line.default_color = colour
	for value in points: line.add_point(troops.project_world_to_field(troops.normalized_to_world(point(value))))
	overlay.add_child(line)

func add_pin(overlay: CanvasLayer,pixel: Vector2,value: String,colour: Color) -> void:
	var pin: ColorRect = ColorRect.new()
	pin.position = pixel-Vector2(3,3)
	pin.size = Vector2(6,6)
	pin.color = colour
	overlay.add_child(pin)
	var label: Label = Label.new()
	label.text = value
	label.position = pixel+Vector2(7,-14)
	label.add_theme_font_size_override("font_size",17)
	label.add_theme_color_override("font_color",colour)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_constant_override("outline_size",5)
	overlay.add_child(label)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
