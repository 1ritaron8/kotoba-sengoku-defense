extends SceneTree
## Native terrain references with an isolated current-source guide revision.
const SNAPSHOT_ROOT: String="res://tests/profiles/map-render-blueprints/export-73323cb9/source-snapshot/"
var PROFILE_ROOT: String=qa_project_path("tests/profiles/map-render-blueprints/export-73323cb9")
var Battlefield: GDScript
const CurrentBattlefield=preload("res://native/battlefield_3d.gd")
const CurrentNavigation=preload("res://native/battlefield_navigation.gd")
const Gameplay=preload("res://native/game.gd")
const Actor=preload("res://native/sengoku_actor_3d.gd")
const Troops=preload("res://native/troops_3d.gd")
const ActorMaterials=preload("res://native/actor_materials.gd")
const SkinnedRenderer=preload("res://native/sengoku_skinned_renderer.gd")
const IMAGE_SIZE: Vector2i=Vector2i(1280,720)
const WORLD_WIDTH: float=18.5
const ELEVATION: float=50.0

class CurrentReferenceTerrain:
	extends "res://native/battlefield_3d.gd"
	var protected_reference_instances: Dictionary={}
	var reference_structure_kind: String=""

	func _collect_geometry() -> void:
		# Clear classification only on a real rebuild. An identical configure()
		# reuses the existing MultiMeshes and must retain their protected indices.
		protected_reference_instances.clear()
		reference_structure_kind=""
		super._collect_geometry()

	func _build_wall(point: Vector2,footprint: Vector2,yaw: float,kind: String) -> void:
		reference_structure_kind=kind
		super._build_wall(point,footprint,yaw,kind)
		reference_structure_kind=""

	func _build_moat_edges(point: Vector2,footprint: Vector2,yaw: float,kind: String) -> void:
		reference_structure_kind=kind
		super._build_moat_edges(point,footprint,yaw,kind)
		reference_structure_kind=""

	func _build_fort(point: Vector2,footprint: Vector2,yaw: float,kind: String) -> void:
		reference_structure_kind=kind
		super._build_fort(point,footprint,yaw,kind)
		reference_structure_kind=""

	func _build_bridges() -> void:
		reference_structure_kind="crossing"
		super._build_bridges()
		reference_structure_kind=""

	func _add_batch(key: String,mesh: Mesh,material: Material,transform_value: Transform3D) -> void:
		var index: int=batches.get(key,{"transforms":[]}).transforms.size()
		super._add_batch(key,mesh,material,transform_value)
		# A ground/body projection is not permission to erase historical relief
		# or a walkable deck. Tall palisades/roofs remain separately filterable.
		var structural: bool=key=="earth_bank" and not reference_structure_kind.is_empty()
		var bridge_deck: bool=reference_structure_kind=="crossing" and key.begins_with("box:wood:") and transform_value.basis.get_scale().y<.1
		if structural or bridge_deck:
			if not protected_reference_instances.has(key): protected_reference_instances[key]={}
			protected_reference_instances[key][index]=reference_structure_kind

	func is_protected_reference_instance(key: String,index: int,transform_value: Transform3D) -> bool:
		if protected_reference_instances.get(key,{}).has(index): return true
		if key!="box:wood:ffffffff": return false
		# The seven dock floor planks share a material with unrelated houses.
		# Match their real landmark positions and complete transforms instead.
		for source in objects:
			if str(source.get("kind",""))!="enemy_dock": continue
			var base: Vector3=world_point(source.point)
			for plank in range(7):
				var expected: Transform3D=Transform3D(Basis.from_scale(Vector3(.12,.07,.42)),base+Vector3(float(plank-3)*.13,.02,0))
				if transform_value.is_equal_approx(expected): return true
		return false

	func _build_objectives() -> void:
		# Use the same explicit gate/camp/line/cart presentation as gameplay.
		# The guide must not turn a shared camp HP anchor into a new gate.
		super._build_objectives()

var checks: int=0
var failures: Array[String]=[]
var stages: Array=[]
var output_folder: String=PROFILE_ROOT+"/blueprints"
var manifest_path: String=PROFILE_ROOT+"/map_render_blueprints_manifest.json"
var camera_report: Dictionary={}
var renderer: String=""
var guides: bool=false
var export_profile: String=PROFILE_ROOT
var guide_data: Dictionary={}
var guide_font: Font
var current_source: bool=false
var prepare_only: bool=false
var source_maps_path: String=SNAPSHOT_ROOT+"maps.json"
var source_maps_sha: String=""
var private_candidate: bool=false
var validated_cpu: Dictionary={}
var validated_cpu_path: String=""
var source_hashes: Dictionary={}
var body_offsets: Dictionary={}
var measured_placement_roles: Dictionary={}
var scale_provider: Control
var guide_navigation: RefCounted = CurrentNavigation.new()
var clean_output_folder: String=""
var clean_stages: Array=[]
const BODY_MARGIN: float=10.0
const ACTUAL_MAIN_WINDOWS: Array[Vector2i]=[Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]
const ACTUAL_MAIN_FIELDS: Array[Vector2]=[Vector2(1248,620),Vector2(1408,720),Vector2(1888,900)]
const BODY_VERTICAL_ASPECT_MARGIN: float=(1888.0/900.0)/(1280.0/720.0)
const SOURCE_FILES: Array[String]=["res://tests/export_map_render_blueprints.gd","res://native/maps.json","res://native/units.json","res://native/main.gd","res://native/battle_camera.gd","res://native/battlefield_presentation.gd","res://native/game.gd","res://native/battle_support.gd","res://native/ground_combat.gd","res://native/troops_3d.gd","res://native/battlefield_3d.gd","res://native/battlefield_navigation.gd","res://native/battlefield_weather.gd","res://native/battlefield_materials.gd","res://native/rendered_battlefield_helpers.gd","res://native/visual_profiles.json","res://native/sengoku_actor_3d.gd","res://native/sengoku_skinned_renderer.gd","res://native/actor_materials.gd","res://native/human_body_geometry.gd","res://native/human_face_3d.gd","res://native/sengoku_armor_geometry.gd","res://native/sengoku_equipment_geometry.gd"]

func _initialize() -> void:
	Engine.max_fps=60
	# This is an isolated offscreen exporter, not the player application.
	# A window-close event must not turn an incomplete batch into exit 0.
	set_auto_accept_quit(false)
	root.close_requested.connect(func(): print("MAP_RENDER_OFFSCREEN_CLOSE_REQUEST batch remains incomplete until explicit exporter exit"))
	guides="--guides" in OS.get_cmdline_user_args()
	current_source="--current-source" in OS.get_cmdline_user_args()
	prepare_only="--prepare-only" in OS.get_cmdline_user_args()
	if current_source: source_maps_path="res://native/maps.json"
	var candidate_path: String=OS.get_environment("JP_DF_GUIDE_CANDIDATE").replace("\\","/")
	if current_source and not candidate_path.is_empty():
		private_candidate=true
		source_maps_path=candidate_path.simplify_path()
	if guides:
		export_profile=OS.get_environment("APPDATA").replace("\\","/").simplify_path().trim_suffix("/")
		output_folder=export_profile+"/guides"
		manifest_path=export_profile+"/map_render_guidance_manifest.json"
		clean_output_folder=export_profile+"/blueprints"
	call_deferred("run_self_checks" if "--self-check" in OS.get_cmdline_user_args() else "run")

func check(value: bool,note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		push_error("MAP_RENDER_BLUEPRINT: "+note)

func require_historical_inputs(require_renderer: bool) -> bool:
	var required: Array[String]=["maps.json"]
	if require_renderer: required.append_array(["battlefield_3d.gd","battlefield_materials.gd","visual_profiles.json"])
	for name in required:
		var path: String=SNAPSHOT_ROOT+name
		if not FileAccess.file_exists(path):
			push_error("MAP_RENDER_BLUEPRINT historical blueprint-only input is missing: "+ProjectSettings.globalize_path(path)+"; restore the preserved source snapshot. Current Native is not a replacement.")
			quit(2)
			return false
	if require_renderer:
		var renderer_path: String=SNAPSHOT_ROOT+"battlefield_3d.gd"
		var preserved: GDScript=load(renderer_path) as GDScript
		if preserved==null or not preserved.can_instantiate() or preserved.resource_path!=renderer_path:
			push_error("MAP_RENDER_BLUEPRINT cannot bind the preserved historical renderer: "+renderer_path)
			quit(2)
			return false
		Battlefield=preserved as GDScript
	return true

func settle(frames: int) -> void:
	for index in range(frames): await process_frame

func descendants(parent: Node) -> Array:
	var result: Array=[]
	for child in parent.get_children():
		result.append(child)
		result.append_array(descendants(child))
	return result

func write_manifest(complete: bool) -> void:
	var report: Dictionary={"complete":complete,"checks":checks,"failures":failures,"stageCount":stages.size(),"stages":stages,"camera":camera_report,"imageSize":{"width":IMAGE_SIZE.x,"height":IMAGE_SIZE.y},"renderer":renderer,"sourceSnapshot":ProjectSettings.globalize_path(SNAPSHOT_ROOT),"mapsSha256":source_maps_sha if current_source else FileAccess.get_sha256(SNAPSHOT_ROOT+"maps.json"),"snapshotRendererSha256":source_hashes.get("res://native/battlefield_3d.gd","") if current_source else FileAccess.get_sha256(SNAPSHOT_ROOT+"battlefield_3d.gd"),"snapshotMaterialsSha256":source_hashes.get("res://native/battlefield_materials.gd","") if current_source else FileAccess.get_sha256(SNAPSHOT_ROOT+"battlefield_materials.gd"),"snapshotManifest":PROFILE_ROOT+"/source_snapshot_manifest.json","originalBlueprintManifest":PROFILE_ROOT+"/map_render_blueprints_manifest.json","actualUserDataDir":OS.get_user_data_dir(),"appData":OS.get_environment("APPDATA"),"localAppData":OS.get_environment("LOCALAPPDATA"),"cleanTerrainOnly":not guides,"guidanceOnly":guides,"notFinalArtwork":true,"originalImagesPreserved":guides,"actors":0,"productionUi":0,"ui":0 if not guides else "QA coordinate annotation layer only","labels":0 if not guides else "P/O/B/S/N/X/h reference markers and legend","guideGameplaySourceSha256":FileAccess.get_sha256("res://native/game.gd") if guides else "","guideCoordinates":"Actual camera.unproject_position(snapshot.world_point(normalized source)). h markers are actual legal Game placement hints; marker colours/text are reference-only and must not enter final art.","artLookup":"Absent from frozen native renderer snapshot; future production hybrid changes do not enter this export","scope":"Frozen native terrain with actual normalized path, objective floor, archer/support/ninja/side-entry coordinate guides for image generation. All annotation is reference-only; this is not finished game artwork or a user-facing game capture." if guides else "Native terrain, authored roads/water/bridges/buildings/vegetation rendered by real GPU. Blueprint source for high quality image rendering, not the final hybrid artwork."}
	var file: FileAccess=FileAccess.open(manifest_path,FileAccess.WRITE)
	if current_source:
		report.merge({"version":2,"mapsSha256":source_maps_sha,"sourceMode":"current_actual_gameplay_geometry","sourceHashes":source_hashes,"sourceSnapshot":export_profile+"/source_maps.json","snapshotManifest":"","snapshotRendererSha256":source_hashes.get("res://native/battlefield_3d.gd",""),"snapshotMaterialsSha256":source_hashes.get("res://native/battlefield_materials.gd",""),"originalBlueprintManifest":"","guideGameplaySourceSha256":source_hashes.get("res://native/game.gd",""),"exporterSourceSha256":FileAccess.get_sha256("res://tests/export_map_render_blueprints.gd"),"phase":"cpu_geometry_preparation" if prepare_only else "gpu_guidance_export","guideCoordinates":"Canonical actual Game legal placement floors and actual camera.unproject_position(CurrentBattlefield.world_point()). Fresh upright geometry; no image rotation or previous art lookup.","artLookup":"Explicit missing reference-only manifest forces real current native terrain. Registered artwork is never used as guide geometry.","referenceViewOverrides":["Mobile O is the actual moving-cart floor in both gameplay and reference; camps retain their authored separate contact floors."],"bodyClearanceContract":{"measurement":"Original articulated mesh AABBs, evolution0..2, idle/attack, eight headings, actual Troops scale at each floor","marginPixels":BODY_MARGIN,"standingCoreMinimumHeightPixels":82,"legalPocket":"Separate swept body bounds from actual Game legal samples; no coordinate guessing","roadCorridor":"Filled physical native road width, not just a centreline","priority":"Clear floor/body and road corridor overrule conflicting roofs, walls, poles and foliage in the sketch. Violet O architecture region is a placement exclusion candidate; O green floor/route stays open."},"oldReferencesPreserved":true,"cleanTerrainOnly":false,"notFinalArtwork":true},true)
		report["measuredPlacementRoles"]=measured_placement_roles
		report["originalModelBoundsAtReferenceCamera"]=body_offsets
		report["actualMainWindows"]=[{"width":1280,"height":800},{"width":1440,"height":900},{"width":1920,"height":1080}]
		if private_candidate:
			report.merge({"sourceMode":"private_candidate_geometry_review","candidatePath":source_maps_path,"candidateSha256":source_maps_sha,"productionMapsSha256":source_hashes.get("res://native/maps.json",""),"phase":"cpu_private_candidate_review","notApprovedForImageGeneration":true},true)
		if not validated_cpu.is_empty():
			report["validatedCpuGuidance"]={"path":validated_cpu_path,"sha256":FileAccess.get_sha256(validated_cpu_path),"checks":validated_cpu.checks,"mapsSha256":validated_cpu.mapsSha256,"reuse":"Approved original-model and full legal-edge CPU evidence reused by exact map and runtime source hashes. Every cached marker is reprojected through the actual GPU terrain and camera; legal-edge CPU sweeps are not repeated."}
	check(file!=null,"Export manifest writes within the guarded workspace profile")
	if file==null: return
	report["checks"]=checks
	report["complete"]=complete and failures.is_empty()
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	if current_source and not prepare_only:
		var clean_report: Dictionary=report.duplicate(true)
		clean_report["stages"]=clean_stages
		clean_report["stageCount"]=clean_stages.size()
		clean_report["cleanTerrainOnly"]=true
		clean_report["guidanceOnly"]=false
		clean_report["ui"]=0
		clean_report["labels"]=0
		clean_report["scope"]="Fresh current-source upright native geometry. No actors, UI, annotations, rendered art lookup, image mirroring or pixel rotation. Paired with the separately exported mandatory placement/corridor guides."
		var clean_manifest: FileAccess=FileAccess.open(export_profile+"/map_render_blueprints_manifest.json",FileAccess.WRITE)
		check(clean_manifest!=null,"New clean blueprint manifest writes in its separate profile")
		if clean_manifest!=null:
			clean_report["checks"]=checks
			clean_report["complete"]=complete and clean_stages.size()==40 and failures.is_empty()
			clean_manifest.store_string(JSON.stringify(clean_report,"\t"))
			clean_manifest.close()

func xy(point: Vector2) -> Dictionary:
	return {"x":point.x,"y":point.y}

func rect_data(value: Rect2) -> Dictionary:
	return {"position":xy(value.position),"size":xy(value.size)}

func rect_value(value: Dictionary) -> Rect2:
	return Rect2(screen_xy(value.position),screen_xy(value.size))

func current_hashes() -> Dictionary:
	var result: Dictionary={}
	for path in SOURCE_FILES: result[path]=FileAccess.get_sha256(path)
	return result

func load_validated_cpu() -> void:
	var path: String=OS.get_environment("JP_DF_GUIDE_VALIDATED_CPU").replace("\\","/")
	if path.is_empty(): return
	validated_cpu_path=path.simplify_path()
	check(current_source and guides and not prepare_only and not private_candidate,"Approved CPU guidance is reused only by the final current-source GPU export")
	check(validated_cpu_path.to_lower().begins_with(qa_project_path("tests/profiles/map-render-blueprints/guided-").to_lower()),"Approved CPU guidance remains within the isolated test profiles")
	var expected: String=OS.get_environment("JP_DF_GUIDE_VALIDATED_CPU_SHA").to_lower()
	check(expected.length()==64 and FileAccess.get_sha256(validated_cpu_path)==expected,"Approved CPU guidance file matches its explicit evidence hash")
	if not failures.is_empty(): return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(validated_cpu_path))
	check(parsed is Dictionary,"Approved CPU guidance decodes as a report")
	if not parsed is Dictionary: return
	validated_cpu=parsed
	check(bool(validated_cpu.get("complete",false)) and validated_cpu.get("failures",[]).is_empty() and validated_cpu.get("stages",[]).size()==40,"The reused CPU run completed all forty maps without failures")
	check(str(validated_cpu.get("mapsSha256",""))==source_maps_sha,"CPU candidate and final production map bytes are identical")
	check(FileAccess.get_sha256(str(validated_cpu.get("sourceSnapshot","")))==source_maps_sha,"The approved CPU source snapshot still has the exact final map bytes")
	for source in SOURCE_FILES:
		# Only this exporter's new cache-reading path and the former production
		# maps differ. The candidate map hash above replaces that old-map proof.
		if source in ["res://tests/export_map_render_blueprints.gd","res://native/maps.json"]: continue
		check(str(validated_cpu.get("sourceHashes",{}).get(source,""))==str(source_hashes.get(source,"")),"Validated gameplay/model/terrain source remains unchanged: "+source)
	check(validated_cpu.get("originalModelBoundsAtReferenceCamera",{}).size()==8,"CPU evidence contains the original eight model bounds")
	if failures.is_empty():
		body_offsets=validated_cpu.originalModelBoundsAtReferenceCamera.duplicate(true)
		measured_placement_roles=validated_cpu.measuredPlacementRoles.duplicate(true)

func reuse_guides(index: int,config: Dictionary,game: Node2D,battlefield: Node3D,camera: Camera3D,info: Dictionary) -> Dictionary:
	var record: Dictionary=validated_cpu.stages[index]
	check(str(record.stageId)==str(config.id) and int(record.stageNumber)==index+1,"Reused CPU stage ID and order match final production")
	check(str(record.geometry.physicalGeometryFingerprint)==str(info.physicalGeometryFingerprint),"Actual GPU physical terrain equals the approved CPU terrain")
	check(absf(float(record.geometry.heightMinimum)-float(info.heightMinimum))<.00001 and absf(float(record.geometry.heightMaximum)-float(info.heightMaximum))<.00001,"Actual GPU relief equals the approved CPU height source")
	game.load_map(config,0)
	bind_guide_navigation(game,battlefield)
	var cached: Dictionary=record.guidance.duplicate(true)
	check(int(cached.zoneCounts.ranged)==config.get("buildZones",[]).size() and int(cached.zoneCounts.ground)==config.get("tactics",{}).get("groundPosts",[]).size() and int(cached.zoneCounts.ambush)==game.ground_combat.ambush_sites.size(),"Actual GPU source includes every approved B/S/N zone")
	for marker in cached.points:
		var actual: Vector2=projected(screen_xy(marker.normalized),battlefield,camera)
		check(actual.distance_to(screen_xy(marker.screen))<.025,"Cached marker matches its real current GPU projection: "+str(config.id)+" "+str(marker.label))
	return cached

func verify_cached_camera() -> void:
	if validated_cpu.is_empty(): return
	var cached: Dictionary=validated_cpu.camera
	var maximum_delta: float=0.0
	for key in ["projection","keepAspect","msaa","ambientSource","skyRadiance"]:
		check(camera_report.get(key)==cached.get(key),"Actual GPU camera categorical contract: "+str(key))
	for key in ["worldWidth","worldDepth","elevationDegrees","near","far","meshLodThreshold"]:
		var delta: float=absf(float(camera_report.get(key,INF))-float(cached.get(key,-INF)))
		maximum_delta=maxf(maximum_delta,delta)
		check(delta<.00001,"Actual GPU camera numeric contract: "+str(key))
	for key in ["position","lookAt"]:
		for axis in ["x","y","z"]:
			var delta: float=absf(float(camera_report.get(key,{}).get(axis,INF))-float(cached.get(key,{}).get(axis,-INF)))
			maximum_delta=maxf(maximum_delta,delta)
			check(delta<.00001,"Actual GPU camera vector contract: "+str(key)+"."+str(axis))
	camera_report["validatedCpuCameraTolerance"]=.00001
	camera_report["validatedCpuCameraMaximumDelta"]=maximum_delta

func measure_model_clearance(camera: Camera3D) -> void:
	# Measurement actors are outside the exported SubViewport/world and never
	# become pixels in a clean blueprint. Cache only orthographic offsets.
	var probe_root: Node3D=Node3D.new()
	root.add_child(probe_root)
	var origin: Vector2=camera.unproject_position(Vector3.ZERO)
	var role_provider: Node2D=Gameplay.new()
	var catalog: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).get("units",[])
	for definition in catalog:
		var type_name: String=str(definition.id)
		measured_placement_roles[type_name]=str(role_provider.placement_contract(type_name).placementRole)
		var bounds: Rect2=Rect2(Vector2.ZERO,Vector2.ZERO)
		for evolution in range(3):
			var actor: Node3D=Actor.new()
			probe_root.add_child(actor)
			actor.configure(type_name,false,701,false,evolution)
			actor.set_process(false)
			for heading in range(8):
				var yaw: float=TAU*float(heading)/8.0
				for pose in ["idle","attack"]:
					actor.apply_state({"animation":pose,"animationClock":.30,"animationPhase":0.0,"aimX":-sin(yaw),"aimY":-cos(yaw),"visualYaw":yaw,"motionReset":true,"groundMotion":true,"motionTime":.30,"dead":false})
					for source in actor.meshes:
						if source.mesh==null or not source.get_parent().is_visible_in_tree(): continue
						var box: AABB=source.mesh.get_aabb()
						for corner in range(8): bounds=bounds.expand(camera.unproject_position(source.global_transform*box.get_endpoint(corner))-origin)
			actor.free()
		body_offsets[type_name]=rect_data(bounds)
	role_provider.free()
	probe_root.free()

func types_for_role(role: String) -> Array:
	var result: Array=[]
	for type_name in measured_placement_roles:
		if str(measured_placement_roles[type_name])==role: result.append(type_name)
	return result

func body_rect(floor: Vector2,type_names: Array,battlefield: Node3D,camera: Camera3D) -> Rect2:
	var foot: Vector2=projected(floor,battlefield,camera)
	var bounds: Rect2=Rect2(foot,Vector2.ZERO)
	for type_name in type_names:
		var local: Rect2=rect_value(body_offsets[str(type_name)])
		var render_scale: float=scale_provider.render_scale_for(floor,{"type":type_name,"kind":type_name})
		# The reference is16:9, while actual Main reserves180px for its UI.
		# Preserve fixed normalized feet, and reserve the largest body height
		# observed at the three actual Main field ratios rather than clipping the tall weapon.
		local.position.y*=BODY_VERTICAL_ASPECT_MARGIN
		local.size.y*=BODY_VERTICAL_ASPECT_MARGIN
		bounds=bounds.merge(Rect2(foot+local.position*render_scale,local.size*render_scale))
	# A readable standing core includes the tall staff/weapon and avoids the
	# previous fifty-pixel text-only clearance even on the farthest small actor.
	bounds=bounds.merge(Rect2(foot+Vector2(-25,-82*BODY_VERTICAL_ASPECT_MARGIN),Vector2(50,92*BODY_VERTICAL_ASPECT_MARGIN)))
	return bounds.grow(BODY_MARGIN)

func floor_geometry(floor: Vector2,battlefield: Node3D) -> Dictionary:
	# Hidden tactical ingress is traversable grass, never a painted road.
	var road: Dictionary=battlefield._road_projection(floor,true)
	var half_width: float=CurrentBattlefield.ROAD_HALF_WIDTH
	return {"deepWater":battlefield._is_water(floor),"heightWorld":battlefield.height_at(floor),"physicalRoadDistanceWorld":float(road.distance),"physicalRoadHalfWidthWorld":half_width,"insidePhysicalRoad":float(road.distance)<half_width}

func original_model_clipping(floor: Vector2,type_names: Array) -> Array:
	var result: Array=[]
	for type_name in type_names:
		var raw_bounds: Rect2=rect_value(body_offsets[str(type_name)])
		var actor_scale: float=scale_provider.render_scale_for(floor,{"type":type_name,"kind":type_name})
		for index in range(ACTUAL_MAIN_FIELDS.size()):
			var field_size: Vector2=ACTUAL_MAIN_FIELDS[index]
			var pixel_scale: float=field_size.x/float(IMAGE_SIZE.x)*actor_scale
			var bounds: Rect2=Rect2(floor+raw_bounds.position*pixel_scale/field_size,raw_bounds.size*pixel_scale/field_size)
			if Rect2(Vector2.ZERO,Vector2.ONE).encloses(bounds): continue
			result.append({"unitType":type_name,"windowSize":{"width":ACTUAL_MAIN_WINDOWS[index].x,"height":ACTUAL_MAIN_WINDOWS[index].y},"fieldSize":xy(field_size),"boundsNormalized":rect_data(bounds),"left":bounds.position.x<0,"top":bounds.position.y<0,"right":bounds.end.x>1,"bottom":bounds.end.y>1,"measurement":"Original articulated source-mesh bounds over three evolutions, both poses and eight headings; no extra82px standing core or padding. Conservative bound, not raster silhouette segmentation."})
	return result

func add_body_patch(marker: Dictionary,zone: Dictionary,game: Node2D,battlefield: Node3D,camera: Camera3D) -> void:
	var role: String=str(marker.placementRole)
	var types: Array=types_for_role(role)
	var floor: Vector2=screen_xy(marker.normalized)
	var core: Rect2=body_rect(floor,types,battlefield,camera)
	var swept: Rect2=core
	var legal_samples: int=0
	var legal_floors: Array=[xy(floor)]
	var source_floor_conflicts: Array=[]
	var clipped_legal_floors: Array=[]
	var original_model_clipped_samples: Array=[]
	var initial_geometry: Dictionary=floor_geometry(floor,battlefield)
	if bool(initial_geometry.deepWater) or role=="ranged" and bool(initial_geometry.insidePhysicalRoad): source_floor_conflicts.append({"normalized":xy(floor),"geometry":initial_geometry,"sample":"centre"})
	for ring in range(1,4):
		for direction in range(24):
			var angle: float=TAU*float(direction)/24.0
			var sample: Vector2=zone.position+Vector2(cos(angle),sin(angle))*float(zone.get("r",.024))*float(ring)/3.0
			if not game._hint_position_legal(sample,zone,str(marker.typeUsedForHint)): continue
			var actual: Vector2=game._placement_position(sample,zone)
			var actual_body: Rect2=body_rect(actual,types,battlefield,camera)
			swept=swept.merge(actual_body)
			if not Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)).encloses(actual_body): clipped_legal_floors.append({"normalized":xy(actual),"clearBodyRectPixels":rect_data(actual_body),"inputSampleNormalized":xy(sample)})
			legal_floors.append(xy(actual))
			var geometry: Dictionary=floor_geometry(actual,battlefield)
			if bool(geometry.deepWater) or role=="ranged" and bool(geometry.insidePhysicalRoad): source_floor_conflicts.append({"normalized":xy(actual),"geometry":geometry,"sample":"legal_pocket"})
			var original_clipping: Array=original_model_clipping(actual,types)
			if not original_clipping.is_empty(): original_model_clipped_samples.append({"normalized":xy(actual),"inputSampleNormalized":xy(sample),"clipping":original_clipping})
			legal_samples+=1
	marker["bodyTypes"]=types
	marker["actualFloorGeometry"]=initial_geometry
	marker["legalFloorSourceConflicts"]=source_floor_conflicts
	marker["legalPocketClippedBodySamples"]=clipped_legal_floors
	marker["originalModelClippingAtCentre"]=original_model_clipping(floor,types)
	marker["originalModelClippedLegalSamples"]=original_model_clipped_samples
	marker["actualMainBodyViewportContract"]={"windowSizes":[{"width":1280,"height":800},{"width":1440,"height":900},{"width":1920,"height":1080}],"fieldSizes":[xy(ACTUAL_MAIN_FIELDS[0]),xy(ACTUAL_MAIN_FIELDS[1]),xy(ACTUAL_MAIN_FIELDS[2])],"verticalAspectMargin":BODY_VERTICAL_ASPECT_MARGIN,"source":"native/main.gd _layout: field=(windowWidth-32,windowHeight-180)"}
	marker["clearBodyRectPixels"]=rect_data(core)
	marker["legalPocketSweptBodyRectPixels"]=rect_data(swept)
	marker["legalPocketSampleCount"]=legal_samples
	marker["legalPocketSampleFloorsNormalized"]=legal_floors
	marker["legalPocketSweptBodyRectNormalized"]=rect_data(Rect2(swept.position/Vector2(IMAGE_SIZE),swept.size/Vector2(IMAGE_SIZE)))
	marker["legalPocketPartiallyOutsideFrame"]=not Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)).encloses(swept)
	marker["bodyCoreClipped"]=not Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)).encloses(core)
	marker["clearBodyRectNormalized"]=rect_data(Rect2(core.position/Vector2(IMAGE_SIZE),core.size/Vector2(IMAGE_SIZE)))

func gate_architecture(objective: Dictionary,battlefield: Node3D,camera: Camera3D) -> Dictionary:
	var floor: Vector2=screen_xy(objective.normalized)
	var base: Vector3=battlefield.world_point(floor)
	var yaw: float=battlefield._objective_yaw(floor)
	var footprint: AABB=AABB(Vector3(-1.03,0,-.46),Vector3(2.06,2.23,.92))
	var transform_value: Transform3D=Transform3D(Basis(Vector3.UP,yaw),base)
	var bounds: Rect2=Rect2(projected(floor,battlefield,camera),Vector2.ZERO)
	var vertices: Array=[]
	for corner in range(8):
		var pixel: Vector2=camera.unproject_position(transform_value*footprint.get_endpoint(corner))
		vertices.append(xy(pixel))
		bounds=bounds.expand(pixel)
	return {"objective":objective.label,"kind":"reference_gate_face_and_roof","heightWorld":2.23,"openingFloorNormalized":objective.normalized,"openingFloorPixel":objective.screen,"projectedSourceVolume":rect_data(bounds),"projectedCorners":vertices,"mobility":"fixed","bodyPatchConflicts":[]}

func rectangle_union_area(rectangles: Array) -> float:
	var columns: Array=[]
	for value in rectangles:
		var rect: Rect2=rect_value(value).intersection(Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)))
		if rect.has_area(): columns.append(rect.position.x);columns.append(rect.end.x)
	columns.sort()
	var area: float=0.0
	for index in range(columns.size()-1):
		var left: float=float(columns[index])
		var right: float=float(columns[index+1])
		if right-left<.001: continue
		var intervals: Array=[]
		for value in rectangles:
			var rect: Rect2=rect_value(value).intersection(Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)))
			if rect.position.x<right and rect.end.x>left and rect.has_area(): intervals.append(Vector2(rect.position.y,rect.end.y))
		intervals.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x<b.x)
		var end_y: float=-1.0
		var covered_y: float=0.0
		for interval in intervals:
			covered_y+=maxf(0.0,interval.y-maxf(interval.x,end_y))
			end_y=maxf(end_y,interval.y)
		area+=(right-left)*covered_y
	return area

func pocket_metrics(points: Array) -> Dictionary:
	var floors: Array=[]
	var core_rects: Array=[]
	var swept_rects: Array=[]
	var large: Array=[]
	var overlaps: Array=[]
	var area: float=float(IMAGE_SIZE.x*IMAGE_SIZE.y)
	for marker in points:
		if str(marker.kind) not in ["build","support"] or not marker.has("clearBodyRectPixels"): continue
		floors.append(marker)
		core_rects.append(marker.clearBodyRectPixels)
		swept_rects.append(marker.legalPocketSweptBodyRectPixels)
		var rect: Rect2=rect_value(marker.legalPocketSweptBodyRectPixels)
		if rect.get_area()/area>.035:
			large.append({"label":marker.label,"radius":marker.radius,"areaPixels":rect.get_area(),"frameFraction":rect.get_area()/area,"sizePixels":xy(rect.size),"authoredNormalized":marker.authoredNormalized,"actualNormalized":marker.normalized})
	for first in range(floors.size()):
		var a: Rect2=rect_value(floors[first].legalPocketSweptBodyRectPixels)
		for second in range(first+1,floors.size()):
			var b: Rect2=rect_value(floors[second].legalPocketSweptBodyRectPixels)
			var intersection: Rect2=a.intersection(b)
			if not intersection.has_area(): continue
			var ratio: float=intersection.get_area()/minf(a.get_area(),b.get_area())
			overlaps.append({"a":floors[first].label,"b":floors[second].label,"overlapAreaPixels":intersection.get_area(),"fractionOfSmallerPatch":ratio,"substantial":ratio>.45})
	var core_area: float=rectangle_union_area(core_rects)
	var swept_area: float=rectangle_union_area(swept_rects)
	return {"buildSupportCentreCount":floors.size(),"coreBodyUnionAreaPixels":core_area,"coreBodyFrameFraction":core_area/area,"legalPocketSweepUnionAreaPixels":swept_area,"legalPocketSweepFrameFraction":swept_area/area,"largePocketThresholdFrameFraction":.035,"largePockets":large,"pocketOverlapPairs":overlaps,"excessiveSweepReview":swept_area/area>.55,"measurement":"Conservative actual-body rectangles swept over Game-legal placement samples; exact rectangle-union area clipped to frame. This is guide pressure, not a measured painted roof segmentation."}

func projected(point: Vector2,battlefield: Node3D,camera: Camera3D) -> Vector2:
	var result: Vector2=camera.unproject_position(battlefield.world_point(point))
	check(result.is_finite() and result.distance_to(point*Vector2(IMAGE_SIZE))<.025,"Reference marker uses the actual camera/height projection")
	return result

func physical_corridor(points: Array,half_width: float,battlefield: Node3D,camera: Camera3D) -> Dictionary:
	# Use the renderer's world-space transverse width, not an isotropic screen
	# stroke: oblique projection compresses some road orientations differently.
	var result: Dictionary={"halfWidthWorld":half_width,"segmentPolygons":[],"junctionPolygons":[]}
	var world_scale: Vector2=Vector2(battlefield.width,battlefield.depth)
	for index in range(points.size()-1):
		var a: Vector2=screen_xy(points[index].normalized)
		var b: Vector2=screen_xy(points[index+1].normalized)
		var axis: Vector2=(b-a)*world_scale
		var offset: Vector2=Vector2(-axis.y,axis.x).normalized()*half_width/world_scale
		var polygon: Array=[]
		for point in [a-offset,b-offset,b+offset,a+offset]: polygon.append(xy(projected(point,battlefield,camera)))
		result.segmentPolygons.append(polygon)
	for marker in points:
		var center: Vector2=screen_xy(marker.normalized)
		var polygon: Array=[]
		for index in range(20):
			var angle: float=TAU*float(index)/20.0
			var point: Vector2=center+Vector2(cos(angle),sin(angle))*half_width/world_scale
			polygon.append(xy(projected(point,battlefield,camera)))
		result.junctionPolygons.append(polygon)
	return result

func guide_point(kind: String,label: String,point: Vector2,battlefield: Node3D,camera: Camera3D,details: Dictionary={}) -> Dictionary:
	var screen: Vector2=projected(point,battlefield,camera)
	var value: Dictionary={"kind":kind,"label":label,"normalized":xy(point),"screen":xy(screen),"visible":Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)).has_point(screen)}
	value.merge(details)
	return value

func collect_guides(config: Dictionary,game: Node2D,battlefield: Node3D,camera: Camera3D) -> Dictionary:
	game.load_map(config,0)
	bind_guide_navigation(game,battlefield)
	check(game.paths.size()==config.paths.size() and game.units.is_empty() and game.enemies.is_empty(),"Guidance reads actual gameplay geometry without spawning actors")
	var result: Dictionary={"stageId":str(config.id),"paths":[],"points":[],"sideConnections":[],"gateArchitecture":[],"gateBodyPatchConflicts":[],"legend":{"P":"filled cyan actual MAIN physical road corridor; centreline stays exact","O":"green live objective floor; violet fixed gate face/roof exclusion candidate","B":"gold actual legal archer floor and measured clear-body patch","S":"teal actual groundPosts legal floor and measured support/gunner/guard body patch","N":"purple legal ninja site and measured body patch","X":"neutral departure body clearance ONLY; hidden approach is NOT a visible road","E":"common enemy ingress full-body safe floor patch","h":"small white actual legal placement hint"}}
	for path_index in range(game.paths.size()):
		var route: Dictionary=game.paths[path_index]
		var points: Array=[]
		for vertex in range(route.points.size()):
			var point: Vector2=route.points[vertex]
			var marker: Dictionary=guide_point("path","P%d.%d"%[path_index+1,vertex+1],point,battlefield,camera)
			marker["drawLabel"]=not current_source or vertex in [0,1,route.points.size()-1]
			points.append(marker)
			result.points.append(marker)
		var path: Dictionary={"id":str(route.get("id",path_index)),"pathNumber":path_index+1,"points":points,"physicalCorridorWidthPixels":2.0*.43*float(IMAGE_SIZE.x)/WORLD_WIDTH}
		if current_source: path["physicalCorridor"]=physical_corridor(points,CurrentBattlefield.ROAD_HALF_WIDTH,battlefield,camera)
		result.paths.append(path)
	var objective_index: int=0
	for source in game.field_markers():
		if str(source.get("markerKind",""))!="objective": continue
		objective_index+=1
		var objective: Dictionary=guide_point("objective","O%d"%objective_index,game._point(source),battlefield,camera,{"sourceId":str(source.id),"floorAnchor":true,"mobile":bool(source.get("mobile",false)),"presentation":str(source.get("presentation","castle_gate"))})
		result.points.append(objective)
		if current_source and not bool(objective.mobile) and str(objective.presentation)=="castle_gate": result.gateArchitecture.append(gate_architecture(objective,battlefield,camera))
	var counts: Dictionary={"ranged":0,"ground":0,"ambush":0}
	for zone in game.zones:
		var role: String=str(zone.get("placementRole",""))
		if not counts.has(role): continue
		counts[role]+=1
		var kind: String={"ranged":"build","ground":"support","ambush":"ninja"}[role]
		var prefix: String={"ranged":"B","ground":"S","ambush":"N"}[role]
		var label: String=prefix+str(counts[role])
		var unit_type: String={"ranged":"archer","ground":"gunner","ambush":"ninja"}[role]
		var details: Dictionary={"sourceId":str(zone.get("id","")),"placementRole":role,"radius":float(zone.get("r",.024)),"typeUsedForHint":unit_type}
		var hint: Vector2=game._zone_placement_hint(zone,unit_type)
		check(hint.x>=0 and hint.is_finite(),"Actual legal placement hint exists for "+str(config.id)+" "+label)
		if hint.x>=0:
			details["legalHintNormalized"]=xy(hint)
			details["legalHintScreen"]=xy(projected(hint,battlefield,camera))
		if role=="ambush":
			details["entryNormalized"]=xy(zone.entryPosition)
			details["entryScreen"]=xy(projected(zone.entryPosition,battlefield,camera))
		details["authoredNormalized"]=xy(zone.position)
		var actual: Vector2=hint if current_source and hint.x>=0 else zone.position
		var marker: Dictionary=guide_point(kind,label,actual,battlefield,camera,details)
		if current_source and hint.x>=0: add_body_patch(marker,zone,game,battlefield,camera)
		result.points.append(marker)
	check(int(counts.ranged)==config.get("buildZones",[]).size(),"Guidance includes every authored archer emplacement")
	check(int(counts.ground)==config.get("tactics",{}).get("groundPosts",[]).size(),"Guidance includes every actual frontline/support post")
	check(int(counts.ambush)==game.ground_combat.ambush_sites.size(),"Guidance includes every actual generated ninja site")
	for index in range(config.get("sideAmbushEntrances",[]).size()):
		var entry: Dictionary=config.sideAmbushEntrances[index]
		var start: Vector2=game._point(entry.get("point",{}))
		var marker: Dictionary=guide_point("side","X%d"%[index+1],start,battlefield,camera,{"sourceId":str(entry.get("id",""))})
		if current_source:
			var body: Rect2=body_rect(start,body_offsets.keys(),battlefield,camera)
			marker["clearBodyRectPixels"]=rect_data(body)
			marker["bodyTypes"]=body_offsets.keys()
			marker["bodyCoreClipped"]=not Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)).encloses(body)
		result.points.append(marker)
		var chain: Array=[guide_point("side_connection","",start,battlefield,camera)]
		for point in entry.get("connectionPoints",[]): chain.append(guide_point("side_connection","",game._point(point),battlefield,camera))
		var connection: Dictionary={"entryNumber":index+1,"points":chain,"corridorWidthPixels":36.0,"renderAsRoad":false,"visualSurface":"natural_grass_slope_or_shore_without_road_markings"}
		if current_source: connection["physicalCorridor"]=physical_corridor(chain,CurrentBattlefield.ROAD_HALF_WIDTH*.66,battlefield,camera)
		result.sideConnections.append(connection)
	if current_source:
		var entry: Vector2=game._point(config.get("commonEnemyEntry",{}))
		var marker: Dictionary=guide_point("entry","E",entry,battlefield,camera,{"sourceId":"commonEnemyEntry","clearBodyRectPixels":rect_data(body_rect(entry,body_offsets.keys(),battlefield,camera)),"bodyTypes":body_offsets.keys()})
		marker["bodyCoreClipped"]=not Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)).encloses(rect_value(marker.clearBodyRectPixels))
		result.points.append(marker)
		for gate in result.gateArchitecture:
			var architecture: Rect2=rect_value(gate.projectedSourceVolume)
			for candidate in result.points:
				if str(candidate.kind) not in ["build","support"] or not candidate.has("clearBodyRectPixels"): continue
				var overlap: bool=architecture.intersects(rect_value(candidate.clearBodyRectPixels))
				var swept_overlap: bool=architecture.intersects(rect_value(candidate.legalPocketSweptBodyRectPixels))
				if overlap or swept_overlap:
					var conflict: Dictionary={"objective":gate.objective,"placement":candidate.label,"centreBodyOverlap":overlap,"legalPocketBodyOverlap":swept_overlap,"status":"reference_architecture_conflict_clear_patch_has_priority"}
					gate.bodyPatchConflicts.append(conflict)
					result.gateBodyPatchConflicts.append(conflict)
	result["zoneCounts"]=counts
	result["annotationPointCount"]=result.points.size()
	if current_source: result["pocketCoverage"]=pocket_metrics(result.points)
	return result

func screen_xy(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x",0)),float(value.get("y",0)))

func clear_reference_scenery(world: Node3D,camera: Camera3D,data: Dictionary) -> Dictionary:
	# Filter decorative native scaffolding before image generation. This never
	# changes terrain heights, walking geometry, source objects or runtime art.
	var exclusions: Array[Rect2]=[]
	for marker in data.points:
		if marker.has("legalPocketSweptBodyRectPixels"):
			exclusions.append(rect_value(marker.legalPocketSweptBodyRectPixels))
		elif marker.has("clearBodyRectPixels"):
			exclusions.append(rect_value(marker.clearBodyRectPixels))
	var removed: int=0
	var preserved: int=0
	for node in descendants(world):
		if not node is MultiMeshInstance3D: continue
		var batch: MultiMesh=node.multimesh
		if batch==null or batch.mesh==null: continue
		var bounds: AABB=batch.mesh.get_aabb()
		var terrain: Node3D=node.get_parent()
		var key: String=""
		if terrain is CurrentReferenceTerrain:
			for batch_key in terrain.batches:
				if str(batch_key).validate_node_name()==str(node.name): key=str(batch_key);break
		for index in range(batch.instance_count):
			var local_transform: Transform3D=batch.get_instance_transform(index)
			var transform_value: Transform3D=node.global_transform*local_transform
			var first: bool=true
			var projected_bounds: Rect2
			for corner in range(8):
				var local: Vector3=bounds.position+Vector3(bounds.size.x if corner&1 else 0.0,bounds.size.y if corner&2 else 0.0,bounds.size.z if corner&4 else 0.0)
				var pixel: Vector2=camera.unproject_position(transform_value*local)
				if first: projected_bounds=Rect2(pixel,Vector2.ZERO);first=false
				else: projected_bounds=projected_bounds.expand(pixel)
			var overlap: bool=false
			for patch in exclusions:
				if projected_bounds.intersects(patch): overlap=true;break
			if overlap:
				if terrain is CurrentReferenceTerrain and terrain.is_protected_reference_instance(key,index,local_transform):
					preserved+=1
					continue
				batch.set_instance_transform(index,Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO))
				removed+=1
	return {"removedDecorationInstances":removed,"preservedStructuralInstancesInBodyWindows":preserved,"exclusionCount":exclusions.size(),"scope":"Reference-only filtering of tall/conflicting decoration. Authored earthworks, levees, moat edges and walkable bridge/dock floors remain; source navigation, heights, objective floors and main roads unchanged."}

func guide_text(canvas: Node2D,text_value: String,position_value: Vector2,color: Color,font_size: int=14) -> void:
	var length: float=guide_font.get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var anchor: Vector2=Vector2(clampf(position_value.x,3,float(IMAGE_SIZE.x)-length-3),clampf(position_value.y,16,float(IMAGE_SIZE.y)-5))
	canvas.draw_string_outline(guide_font,anchor,text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,Color(.015,.025,.02,.96))
	canvas.draw_string(guide_font,anchor,text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func draw_corridor(canvas: Node2D,contract: Dictionary,color: Color) -> void:
	for polygon_source in contract.segmentPolygons+contract.junctionPolygons:
		var polygon: PackedVector2Array=PackedVector2Array()
		for point in polygon_source: polygon.append(screen_xy(point))
		if polygon.size()>=3: canvas.draw_colored_polygon(polygon,color)

func draw_guidance(canvas: Node2D) -> void:
	if guide_data.is_empty(): return
	for route in guide_data.paths:
		var line: PackedVector2Array=PackedVector2Array()
		for marker in route.points: line.append(screen_xy(marker.screen))
		if line.size()>=2:
			if current_source:
				draw_corridor(canvas,route.physicalCorridor,Color(.08,.70,.73,.88))
			canvas.draw_polyline(line,Color(.01,.05,.05,.94),7.0,true)
			canvas.draw_polyline(line,Color("41f6ff"),3.5,true)
	# Emplacement attackers navigate internally across natural terrain. Neither
	# the final map nor its image-generation guide may paint a separate road.
	if current_source:
		for gate in guide_data.gateArchitecture:
			var gate_rect: Rect2=rect_value(gate.projectedSourceVolume)
			canvas.draw_rect(gate_rect,Color(.61,.29,.81,.13))
			canvas.draw_rect(gate_rect,Color(.82,.43,.94,.85),false,2.0)
			guide_text(canvas,str(gate.objective)+" ROOF/FACE",gate_rect.position+Vector2(3,17),Color("df9dff"),12)
		# Fill body clearance, not just circles or prose. White/ivory patches
		# intentionally cover a crude roof if it violates the authoritative floor.
		for marker in guide_data.points:
			if not marker.has("clearBodyRectPixels"): continue
			var patch: Rect2=rect_value(marker.clearBodyRectPixels).intersection(Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)))
			var edge: Color=Color("ffdc6e") if str(marker.kind)=="build" else Color("79f5c5") if str(marker.kind)=="support" else Color("d1a1ff") if str(marker.kind)=="ninja" else Color("ff9860")
			if marker.has("legalPocketSweptBodyRectPixels"):
				var sweep: Rect2=rect_value(marker.legalPocketSweptBodyRectPixels).intersection(Rect2(Vector2.ZERO,Vector2(IMAGE_SIZE)))
				canvas.draw_rect(sweep,Color(.93,.91,.82,.82))
				canvas.draw_rect(sweep,Color(edge,.90),false,1.5)
				guide_text(canvas,str(marker.label)+" LEGAL POCKET",sweep.position+Vector2(3,14),edge.darkened(.68),10)
			canvas.draw_rect(patch,Color(.95,.92,.80,.93))
			canvas.draw_rect(patch,edge,false,2.0)
			guide_text(canvas,str(marker.label)+" CLEAR BODY",patch.position+Vector2(4,15),edge.darkened(.62),11)
		# Preserve visible physical road WIDTH after the opaque body patches.
		# A thin spine alone let the previous image generator leave the actual
		# walkable corridor. This translucent floor fill never permits a roof
		# inside the surrounding standing/weapon clearance.
		for route in guide_data.paths:
			draw_corridor(canvas,route.physicalCorridor,Color(.05,.77,.82,.61))
			var line: PackedVector2Array=PackedVector2Array()
			for marker in route.points: line.append(screen_xy(marker.screen))
			if line.size()>=2: canvas.draw_polyline(line,Color("41f6ff"),3.5,true)
	for marker in guide_data.points:
		if not bool(marker.visible): continue
		if str(marker.kind)=="side": continue
		var point: Vector2=screen_xy(marker.screen)
		var color: Color=Color({"path":"41f6ff","objective":"86ff9f","build":"ffdc6e","support":"79f5c5","ninja":"d1a1ff","side":"ff9860"}.get(str(marker.kind),"ffffff"))
		if marker.has("radius"):
			var ring: PackedVector2Array=PackedVector2Array()
			var circle_center: Vector2=screen_xy(marker.authoredNormalized)*Vector2(IMAGE_SIZE) if current_source else point
			for segment in range(37):
				var angle: float=TAU*float(segment)/36.0
				ring.append(circle_center+Vector2(cos(angle),sin(angle))*Vector2(IMAGE_SIZE)*float(marker.radius))
			canvas.draw_polyline(ring,Color(color,.65),1.4,true)
		if marker.has("entryScreen"):
			canvas.draw_line(point,screen_xy(marker.entryScreen),Color(color,.80),1.7,true)
		if marker.has("legalHintScreen"):
			var hint: Vector2=screen_xy(marker.legalHintScreen)
			canvas.draw_line(point,hint,Color.WHITE,1.0,true)
			canvas.draw_circle(hint,3.0,Color(.015,.025,.02,.95))
			canvas.draw_circle(hint,1.8,Color.WHITE)
			if hint.distance_to(point)>5: guide_text(canvas,"h"+str(marker.label),hint+Vector2(5,14),Color.WHITE,12)
		canvas.draw_circle(point,6.0 if str(marker.kind)!="path" else 4.0,Color(.015,.025,.02,.95))
		canvas.draw_circle(point,4.0 if str(marker.kind)!="path" else 2.2,color)
		if bool(marker.get("drawLabel",true)): guide_text(canvas,str(marker.label),point+Vector2(7,-7),color)
	canvas.draw_rect(Rect2(0,0,1280,28),Color(.015,.025,.02,.83))
	guide_text(canvas,"REFERENCE GUIDES ONLY  |  "+str(guide_data.stageId)+"  |  REMOVE ALL MARKS AND TEXT IN FINAL ART",Vector2(10,20),Color("f3eddf"),14)
	canvas.draw_rect(Rect2(0,690,1280,30),Color(.015,.025,.02,.83))
	guide_text(canvas,"CYAN: MAIN ROADS ONLY   IVORY: CLEAR BODY/GROUND   B/S/N: LEGAL FLOORS   NO VISIBLE EMPLACEMENT APPROACH",Vector2(10,711),Color("f3eddf"),13)

func prepare_terrain(config: Dictionary,battlefield: Node3D,depth: float) -> void:
	# CPU preparation needs the genuine height substrate and Game placement
	# tests, without building every expensive decorative tree/rock batch.
	for child in battlefield.get_children(): child.free()
	battlefield.stage=config.duplicate(true)
	battlefield.history=config.get("historicalBattlefield",{})
	battlefield.width=WORLD_WIDTH
	battlefield.depth=depth
	battlefield.elevation=ELEVATION
	battlefield.seed_value=absi(str(config.get("historicalBattlefield",{}).get("terrainLayout",{}).get("seed",config.id)).hash())
	battlefield.render_record={"mode":"native","reason":"reference-only current-source preparation"}
	battlefield.geometry_fingerprint=(JSON.stringify(battlefield._geometry_contract(config))+":%.5f:%.5f:%.4f"%[WORLD_WIDTH,depth,ELEVATION]).sha256_text()
	battlefield.batches.clear()
	battlefield.structural_parts.clear()
	battlefield.structure_owner=""
	battlefield.structure_phase="structure"
	battlefield.objects.clear()
	battlefield.stats={"stageId":str(config.id),"terrainTriangles":12288,"roadTriangles":0,"waterTriangles":0,"meshNodes":0,"batches":0,"instances":0,"scannedModels":0,"modelBaseTriangles":0,"renderTrianglesUpperBound":0,"bridgeCount":0,"gateCount":0,"treeCount":0,"photoFloor":false}
	battlefield._collect_geometry()
	battlefield._build_height_grid()
	battlefield._build_ground()
	# Legal floors must use the same walls, roofs and camps as the game.
	# No MultiMesh upload or decorative scatter is needed for CPU preparation.
	battlefield._build_water_banks()
	battlefield._build_landmarks()
	battlefield._build_objectives()
	battlefield.stats["sourceDataContractValid"]=battlefield._validate_contract()
	battlefield.stats["geometryFingerprint"]=battlefield.geometry_fingerprint
	battlefield.stats["physicalGeometryFingerprint"]=JSON.stringify(battlefield._physical_contract()).sha256_text()
	battlefield.stats["preparationOnly"]=true
	battlefield.stats["decorativeMeshesBuilt"]=false
	battlefield.stats["physicalStructurePartsBuilt"]=true

func bind_guide_navigation(game: Node2D,battlefield: Node3D) -> void:
	if not current_source:
		return
	guide_navigation.capture_current(battlefield.structural_parts,Callable(battlefield,"world_point"),battlefield.width,battlefield.depth)
	game.bind_terrain_navigation(Callable(guide_navigation,"segment_clear"),Callable(guide_navigation,"placement_clear"))

func capture_image(viewport: SubViewport,path: String,id: String) -> Dictionary:
	await settle(8)
	await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image()
	check(image!=null and not image.is_empty() and image.get_size()==IMAGE_SIZE,"Actual GPU image is1280x720: "+id)
	if image==null or image.is_empty(): return {}
	check(not FileAccess.file_exists(path) if guides else true,"New PNG never overwrites an existing reference: "+path)
	if guides and FileAccess.file_exists(path): return {}
	check(image.save_png(path)==OK,"PNG saves successfully: "+id)
	check(FileAccess.file_exists(path),"PNG exists on disk: "+id)
	return {"path":path,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height()}

func run_self_checks() -> void:
	if not require_historical_inputs(false): return
	var private_root: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().trim_suffix("/")
	check(current_source and guides and private_root.to_lower().begins_with(qa_project_path("tests/profiles/map-render-blueprints/guided-").to_lower()),"Self-check requires the private current-source tool profile")
	check(OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().trim_suffix("/").to_lower()==private_root.to_lower(),"Self-check environment isolation")
	if not failures.is_empty(): quit(2);return
	var a: Dictionary=rect_data(Rect2(0,0,10,10))
	var b: Dictionary=rect_data(Rect2(5,0,10,10))
	check(is_equal_approx(rectangle_union_area([a,b]),150.0),"Overlap contributes once to clear-patch union area")
	check(is_zero_approx(rectangle_union_area([])),"Empty clear-patch union has zero area")
	check(is_equal_approx(rectangle_union_area([rect_data(Rect2(-5,-5,10,10))]),25.0),"Patch area clips to the actual frame")
	var viewport: SubViewport=SubViewport.new()
	viewport.size=IMAGE_SIZE
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	viewport.own_world_3d=true
	root.add_child(viewport)
	var world: Node3D=Node3D.new()
	viewport.add_child(world)
	var camera: Camera3D=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=WORLD_WIDTH
	camera.position=Vector3(0,30,30/tan(deg_to_rad(ELEVATION)))
	world.add_child(camera)
	camera.look_at(Vector3.ZERO,Vector3.UP)
	var battlefield: Node3D=CurrentReferenceTerrain.new()
	world.add_child(battlefield)
	var depth: float=WORLD_WIDTH/(float(IMAGE_SIZE.x)/float(IMAGE_SIZE.y))/sin(deg_to_rad(ELEVATION))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT_ROOT+"maps.json"))[0]
	prepare_terrain(fixture,battlefield,depth)
	var mobile_fixture: Dictionary=fixture.duplicate(true)
	mobile_fixture.objectives[0]["mobile"]=true
	prepare_terrain(mobile_fixture,battlefield,depth)
	var physical_before: String=JSON.stringify(battlefield._physical_contract()).sha256_text()
	battlefield._build_objectives()
	check(int(battlefield.stats.gateCount)==0,"Moving-cart guide floor has no false fixed gate")
	check(battlefield.objects.size()==1 and str(battlefield.objects[0].kind)=="moving_supply_cart_floor","Moving-cart guide records its actual empty floor")
	check(JSON.stringify(battlefield._physical_contract()).sha256_text()==physical_before,"Reference display override preserves the actual physical source contract")
	prepare_terrain(fixture,battlefield,depth)
	scale_provider=Troops.new()
	scale_provider.stage=fixture
	await settle(1)
	measure_model_clearance(camera)
	check(body_offsets.size()==8,"All eight original model types are measured without rendered test actors")
	check(types_for_role("ranged")==["archer"] and "gunner" in types_for_role("ground"),"Role measurement follows actual Game placement_contract, not the combat GROUND_TYPES list")
	check(types_for_role("marching").size()==3 and "commander" in types_for_role("marching"),"Mounted and melee marching models are measured for ingress/road safety")
	for type_name in body_offsets:
		var bounds: Rect2=rect_value(body_offsets[type_name])
		check(bounds.has_area() and bounds.position.is_finite() and bounds.size.is_finite(),"Finite original articulated mesh bounds: "+str(type_name))
	var game: Node2D=Gameplay.new()
	game.three_d_enabled=true
	game.set_process(false)
	game.set_input_enabled(false)
	var guidance: Dictionary=collect_guides(fixture,game,battlefield,camera)
	var checked_pockets: int=0
	for marker in guidance.points:
		if not marker.has("legalPocketSweptBodyRectPixels"): continue
		var core: Rect2=rect_value(marker.clearBodyRectPixels)
		var swept: Rect2=rect_value(marker.legalPocketSweptBodyRectPixels)
		check(swept.encloses(core),"Sweep includes the standing core: "+str(marker.label))
		check(core.size.y>=102.0,"Standing core has at least82px above floor plus lower and edge margins: "+str(marker.label))
		var floor: Vector2=screen_xy(marker.normalized)
		var normalized_clear: Rect2=Rect2(core.position/Vector2(IMAGE_SIZE),core.size/Vector2(IMAGE_SIZE))
		for type_name in marker.bodyTypes:
			var raw_bounds: Rect2=rect_value(body_offsets[str(type_name)])
			var actual_scale: float=scale_provider.render_scale_for(floor,{"type":type_name,"kind":type_name})
			for field_size in ACTUAL_MAIN_FIELDS:
				var pixel_scale: float=field_size.x/float(IMAGE_SIZE.x)*actual_scale
				var actual_body: Rect2=Rect2(floor+raw_bounds.position*pixel_scale/field_size,raw_bounds.size*pixel_scale/field_size)
				check(normalized_clear.grow(.00001).encloses(actual_body),"Clear patch encloses original model at all three actual Main field ratios: "+str(marker.label)+" "+str(type_name))
		for sample in marker.legalPocketSampleFloorsNormalized:
			var sample_floor: Vector2=screen_xy(sample)
			check(swept.grow(.001).encloses(body_rect(sample_floor,marker.bodyTypes,battlefield,camera)),"Actual legal sample's full body stays in the displayed sweep (subpixel tolerance .001): "+str(marker.label))
		checked_pockets+=1
	check(checked_pockets>14,"Tool covers actual build, support and ambush placement roles")
	check(float(guidance.pocketCoverage.legalPocketSweepFrameFraction)>=float(guidance.pocketCoverage.coreBodyFrameFraction),"Legal-pocket union includes all centre-body coverage")
	var frame_area: float=float(IMAGE_SIZE.x*IMAGE_SIZE.y)
	check(float(guidance.pocketCoverage.legalPocketSweepUnionAreaPixels)<=frame_area,"Clear-patch union cannot exceed the frame")
	check(not original_model_clipping(Vector2(.5,.03),["monk"]).is_empty(),"Original model clipping detects a legal-looking floor whose head is above the frame")
	check(original_model_clipping(Vector2(.5,.5),["archer","monk","naginata"]).is_empty(),"A central floor preserves original models at all three actual window ratios")
	for path in guidance.paths:
		check(path.physicalCorridor.segmentPolygons.size()==path.points.size()-1,"Every exact road segment has a physical-width filled guide")
		for polygon in path.physicalCorridor.segmentPolygons:
			check(polygon.size()==4,"A projected road corridor preserves its four world-width corners")
	for approach in guidance.sideConnections:
		check(not bool(approach.renderAsRoad),"Emplacement approach metadata never permits a visible art road")
		check(approach.points.size()>=2 and approach.has("physicalCorridor"),"Hidden approach still preserves internal navigation/clearance coordinates")
	game.free()
	scale_provider.free()
	world.free()
	viewport.free()
	CurrentBattlefield.release_shared_resources()
	Actor.material_cache.clear()
	Actor.geometry_cache.clear()
	SkinnedRenderer.cache.clear()
	ActorMaterials.shared_material=null
	ActorMaterials.shared_preview_material=null
	ActorMaterials.shared_contact_material=null
	var out: FileAccess=FileAccess.open(private_root+"/guide_tool_selfcheck.json",FileAccess.WRITE)
	check(out!=null,"Tool self-check report stays within its private profile")
	if out!=null: out.store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"Immutable old first-stage data for exporter-only algorithm checks; not new lower-home guides","gpuUsed":false,"bodyOffsets":body_offsets,"measuredPlacementRoles":measured_placement_roles,"actualMainFields":[xy(ACTUAL_MAIN_FIELDS[0]),xy(ACTUAL_MAIN_FIELDS[1]),xy(ACTUAL_MAIN_FIELDS[2])],"guidance":guidance},"\t"));out.close()
	print("MAP_RENDER_GUIDE_TOOL_SELF_CHECK checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	if not current_source and not require_historical_inputs(true): return
	var appdata: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	var localdata: String=OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	check(appdata==export_profile.to_lower() and localdata==appdata,"Both environment paths equal this isolated export profile")
	check(appdata.begins_with(qa_project_path("tests/profiles/map-render-blueprints/guided-").to_lower()) if guides else appdata==PROFILE_ROOT.to_lower(),"Guided export uses a new separate profile and preserves original images")
	check(OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower().begins_with(appdata+"/"),"Actual user data directory remains inside the export profile")
	check(FileAccess.file_exists(export_profile+"/profile_guard.json"),"Profile guard exists")
	check(not current_source or guides,"Current source uses the isolated paired clean/guided export")
	check(not prepare_only or current_source,"Preparation is available only for current source")
	check(not private_candidate or prepare_only and source_maps_path.to_lower().begins_with(qa_project_path("tests/profiles/").to_lower()),"Private candidates are workspace test JSON inputs for CPU review only")
	check(prepare_only or DisplayServer.get_name()!="headless","Blueprint image export uses the actual GPU display server")
	if current_source:
		source_maps_sha=FileAccess.get_sha256(source_maps_path)
		source_hashes=current_hashes()
		var expected_sha: String=OS.get_environment("JP_DF_GUIDE_MAPS_SHA").to_lower()
		check(expected_sha.length()==64 and expected_sha==source_maps_sha,"Input maps equal the explicitly specified source or candidate SHA")
		load_validated_cpu()
	if not failures.is_empty(): quit(2); return
	check(DirAccess.make_dir_recursive_absolute(output_folder)==OK,"Blueprint output directory is created inside tests")
	if current_source:
		check(DirAccess.make_dir_recursive_absolute(clean_output_folder)==OK,"Separate clean reference output exists")
		var snapshot_path: String=export_profile+"/source_maps.json"
		check(not FileAccess.file_exists(snapshot_path) or FileAccess.get_sha256(snapshot_path)==source_maps_sha,"Existing new source snapshot is unchanged")
		if not failures.is_empty(): quit(2); return
		var snapshot: FileAccess=FileAccess.open(snapshot_path,FileAccess.WRITE)
		check(snapshot!=null,"Current maps snapshot writes only inside the export profile")
		if snapshot!=null:
			snapshot.store_buffer(FileAccess.get_file_as_bytes(source_maps_path))
			snapshot.close()
		check(FileAccess.get_sha256(snapshot_path)==source_maps_sha,"Exact bytes of the new source maps are recorded")
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string(source_maps_path))
	var original: Dictionary={}
	if guides and not current_source:
		original=JSON.parse_string(FileAccess.get_file_as_string(PROFILE_ROOT+"/map_render_blueprints_manifest.json"))
		check(bool(original.get("complete",false)) and original.get("stages",[]).size()==40,"All40 original clean blueprint references are available")
		check(FileAccess.get_sha256("res://native/maps.json")==FileAccess.get_sha256(SNAPSHOT_ROOT+"maps.json"),"Actual current gameplay geometry bytes still equal the frozen40stage source")
		check(str(original.get("snapshotRendererSha256",""))==FileAccess.get_sha256(SNAPSHOT_ROOT+"battlefield_3d.gd") and str(original.get("snapshotMaterialsSha256",""))==FileAccess.get_sha256(SNAPSHOT_ROOT+"battlefield_materials.gd"),"Frozen renderer/material source bytes remain exactly the original export")
	var profiles: Dictionary={}
	var profile_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/visual_profiles.json" if current_source else SNAPSHOT_ROOT+"visual_profiles.json"))
	for entry in profile_data.get("profiles",[]): profiles[str(entry.stageId)]=entry
	check(maps.size()==40,"Exactly40 authored stages are prepared in order")
	if not failures.is_empty(): quit(2); return
	renderer=RenderingServer.get_video_adapter_name()
	var viewport: SubViewport=SubViewport.new()
	viewport.size=IMAGE_SIZE
	viewport.own_world_3d=true
	viewport.transparent_bg=false
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.mesh_lod_threshold=3.0
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED if prepare_only else SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: Node3D=Node3D.new()
	viewport.add_child(world)
	var lighting: WorldEnvironment=WorldEnvironment.new()
	var environment: Environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("19221e")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	lighting.environment=environment
	world.add_child(lighting)
	var sun: DirectionalLight3D=DirectionalLight3D.new()
	sun.shadow_enabled=true
	sun.shadow_bias=.10
	sun.shadow_normal_bias=.80
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=50.0
	sun.directional_shadow_fade_start=1.0
	world.add_child(sun)
	var camera: Camera3D=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=WORLD_WIDTH
	camera.near=.1
	camera.far=45.0
	camera.current=true
	camera.position=Vector3(0,30.0,30.0/tan(deg_to_rad(ELEVATION)))
	world.add_child(camera)
	camera.look_at(Vector3.ZERO,Vector3.UP)
	var depth: float=WORLD_WIDTH/(float(IMAGE_SIZE.x)/float(IMAGE_SIZE.y))/sin(deg_to_rad(ELEVATION))
	camera_report={"projection":"orthographic","keepAspect":"KEEP_WIDTH","worldWidth":WORLD_WIDTH,"worldDepth":depth,"elevationDegrees":ELEVATION,"near":camera.near,"far":camera.far,"position":{"x":camera.position.x,"y":camera.position.y,"z":camera.position.z},"lookAt":{"x":0,"y":0,"z":0},"msaa":"2x","meshLodThreshold":3.0,"ambientSource":"color","skyRadiance":false}
	verify_cached_camera()
	if not failures.is_empty():
		world.free()
		viewport.free()
		quit(2)
		return
	var battlefield: Node3D=CurrentReferenceTerrain.new() if current_source else Battlefield.new()
	if current_source: battlefield.art_manifest_path=export_profile+"/reference-only-no-art-manifest.json"
	world.add_child(battlefield)
	var guide_canvas: Node2D
	var game: Node2D
	if guides:
		guide_canvas=Node2D.new()
		guide_canvas.name="ReferenceCoordinatesOnly"
		viewport.add_child(guide_canvas)
		guide_canvas.draw.connect(draw_guidance.bind(guide_canvas))
		guide_font=load("res://assets/fonts/NotoSansCJKjp-Regular.otf") as Font
		check(guide_font!=null,"Reference annotation font loads")
		game=Gameplay.new()
		game.three_d_enabled=true
		game.set_process(false)
		game.set_input_enabled(false)
		if current_source:
			var catalog: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).get("units",[])
			var unlocked: Array=[]
			for definition in catalog: unlocked.append(str(definition.id))
			game.configure_roster(catalog,unlocked,{})
			scale_provider=Troops.new()
			scale_provider.visual_profiles=profiles
			await settle(1)
			if validated_cpu.is_empty(): measure_model_clearance(camera)
			check(body_offsets.size()==8,"Actual original eight-unit model bounds are measured")
	var seen_ids: Dictionary={}
	for index in range(maps.size()):
		var config: Dictionary=maps[index]
		var id: String=str(config.id)
		check(int(config.stageNumber)==index+1 and not seen_ids.has(id),"Distinct authored stage ID/order: "+id)
		seen_ids[id]=true
		if prepare_only: prepare_terrain(config,battlefield,depth)
		else: battlefield.configure(config,WORLD_WIDTH,depth,ELEVATION)
		var info: Dictionary=battlefield.diagnostics()
		check(info.stageId==id and info.sourceDataContractValid,"Correct physical source geometry: "+id)
		check(not info.photoFloor and info.terrainTriangles>0 and (prepare_only or info.roadTriangles>0),"Terrain and roads use actual source geometry: "+id)
		if current_source:
			check(not bool(info.renderLayerContract.get("renderedArtwork",false)),"Old artwork cannot enter the new native reference: "+id)
			scale_provider.stage=config
		var reference: Dictionary={}
		var clearance_overrides: Dictionary={}
		if guides:
			if not current_source:
				reference=original.stages[index]
				check(str(reference.stageId)==id and int(reference.stageNumber)==index+1,"Guidance has the original40stage ordering")
				check(str(reference.geometry.geometryFingerprint)==str(info.geometryFingerprint) and str(reference.geometry.physicalGeometryFingerprint)==str(info.physicalGeometryFingerprint),"Coordinate overlay leaves original snapshot geometry fingerprints unchanged: "+id)
				check(absf(float(reference.geometry.heightMinimum)-float(info.heightMinimum))<.00001 and absf(float(reference.geometry.heightMaximum)-float(info.heightMaximum))<.00001,"Coordinate overlay leaves original physical relief unchanged: "+id)
				check(FileAccess.get_sha256(str(reference.path))==str(reference.sha256),"Original clean PNG remains unchanged: "+id)
			guide_data=collect_guides(config,game,battlefield,camera) if validated_cpu.is_empty() else reuse_guides(index,config,game,battlefield,camera,info)
			if current_source and not prepare_only:
				clearance_overrides={"removedDecorationInstances":0,"scope":"Actual gameplay scenery preserved. Conflicts must be repaired in source, never hidden only in a guide."}
			guide_canvas.queue_redraw()
		var unwanted: int=0
		for node in descendants(world):
			if node is CanvasItem or str(node.get_script()).contains("sengoku_actor") or node is AnimationPlayer: unwanted+=1
		check(unwanted==0,"No actors, UI, health bars, labels or test soldiers: "+id)
		var history: Dictionary=config.get("historicalBattlefield",{})
		var time_data: Variant=history.get("timeOfDay","day")
		var actual_time: String=str(time_data.get("key",time_data.get("value","day"))) if time_data is Dictionary else str(time_data)
		var weather_data: Variant=history.get("weather",{})
		var actual_weather: String=str(weather_data.get("kind",weather_data.get("key","unknown"))) if weather_data is Dictionary else str(weather_data)
		var brightness: float=.85 if actual_weather in ["rain","cloudy","overcast"] else 1.0
		var ambient: Color=Color("dce6e2")
		var direction: Dictionary=profiles.get(id,{}).get("shadowDirection",{"x":-.65,"y":.4})
		var axis: Vector2=Vector2(float(direction.x),float(direction.y)).normalized()
		sun.position=Vector3(-axis.x*18,30,-axis.y*18/sin(deg_to_rad(ELEVATION)))
		sun.look_at(Vector3.ZERO,Vector3.UP)
		sun.light_color=ambient.lerp(Color.WHITE,.25)
		sun.light_energy=.55 if actual_time=="night" else 1.45*brightness
		environment.ambient_light_color=ambient
		environment.ambient_light_energy=.35 if actual_time=="night" else .32*brightness
		var row: Dictionary={"stageNumber":index+1,"stageId":id,"title":str(config.title),"geometry":info,"lighting":{"timeKey":actual_time,"weatherKey":actual_weather,"sunEnergy":sun.light_energy,"ambientEnergy":environment.ambient_light_energy,"shadowDirection":direction},"unwantedNodes":unwanted,"guidance":guide_data.duplicate(true) if guides else {},"referenceSceneryClearance":clearance_overrides}
		if prepare_only:
			row.merge({"path":"","sha256":"","preparationOnly":true})
		else:
			if current_source:
				guide_canvas.hide()
				var clean_path: String=clean_output_folder+"/stage-%02d-%s.png"%[index+1,id]
				var clean_record: Dictionary=await capture_image(viewport,clean_path,id+" clean")
				reference=row.duplicate(true)
				reference.erase("guidance")
				reference.merge(clean_record)
				clean_stages.append(reference)
				guide_canvas.show()
				guide_canvas.queue_redraw()
			var path: String=output_folder+("/guidance-stage-%02d-%s.png" if guides else "/stage-%02d-%s.png")%[index+1,id]
			row.merge(await capture_image(viewport,path,id))
			row["originalBlueprintPath"]=reference.get("path","") if guides else path
			row["originalBlueprintSha256"]=reference.get("sha256","") if guides else FileAccess.get_sha256(path)
		stages.append(row)
		write_manifest(false)
		print("MAP_RENDER_BLUEPRINT_%s stage=%02d id=%s path=%s"%["PREPARED" if prepare_only else "SAVED",index+1,id,str(row.get("path",""))])
	check(stages.size()==40,"All40 guidance images are recorded" if guides else "All40 clean blueprint images are recorded")
	if not prepare_only:
		for record in stages+clean_stages:
			check(FileAccess.file_exists(str(record.get("path",""))),"Final disk existence: "+str(record.stageId))
			var decoded: Image=Image.load_from_file(str(record.get("path","")))
			check(decoded!=null and decoded.get_size()==IMAGE_SIZE,"Final PNG decodes at1280x720: "+str(record.stageId))
	if current_source:
		check(source_hashes==current_hashes(),"Maps, placement rules, actor geometry and renderer remained frozen throughout export")
		check(source_maps_sha==FileAccess.get_sha256(source_maps_path),"The exact input map source remained frozen throughout review or export")
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if guides:
		game.free()
		guide_canvas.free()
	if is_instance_valid(scale_provider): scale_provider.free()
	world.free()
	viewport.free()
	if current_source: CurrentBattlefield.release_shared_resources()
	else: Battlefield.release_shared_resources()
	Actor.material_cache.clear()
	Actor.geometry_cache.clear()
	SkinnedRenderer.cache.clear()
	ActorMaterials.shared_material=null
	ActorMaterials.shared_preview_material=null
	ActorMaterials.shared_contact_material=null
	await settle(24)
	var cache_diagnostics: Dictionary=CurrentBattlefield.shared_cache_diagnostics() if current_source else Battlefield.shared_cache_diagnostics()
	check(cache_diagnostics.materials.textureCount==0,"Shared terrain resources are released")
	write_manifest(failures.is_empty())
	print("MAP_RENDER_BLUEPRINT_DONE stages=%d checks=%d failures=%d manifest=%s"%[stages.size(),checks,failures.size(),manifest_path])
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
