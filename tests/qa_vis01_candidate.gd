extends SceneTree
## Isolated VIS-01 composition/capture only. No catalog/save unlock or fabricated actors.
const CANDIDATE_PATH: String = "res://assets/battlefields-remaster/stage01-candidate-v2.json"
const VisualScene = preload("res://native/remaster_visual_slice.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const REFERENCE_PATH: String = "res://docs/remaster-pilot-20261008/stage01-v2-approved-material-reference-r11.png"
const CHARACTER_REFERENCE_PATH: String = "res://docs/map-remaster-reference/01-period-war-materials.png"
var checks: int = 0
var failures: Array[String] = []
var images: Array[String] = []
var captures: Array = []
var app: Node
var source_before: Dictionary = {}
var started_usec: int = 0
var startup_msec: float = 0.0
var candidate_load_msec: float = 0.0
var observed_campaign_ids: Array = []

func _initialize() -> void:
	started_usec = Time.get_ticks_usec()
	call_deferred("run")

func check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures.append(message)
		push_error("VIS01 "+message)
	return value

func _hash_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file==null: return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position()<file.get_length():
		context.update(file.get_buffer(mini(1048576,file.get_length()-file.get_position())))
	return context.finish().hex_encode()

func _source_files(directory: String, result: Dictionary) -> void:
	var access: DirAccess = DirAccess.open(directory)
	if access==null: return
	for name in access.get_files():
		if name.ends_with(".import") or name.ends_with(".uid"): continue
		var path: String = directory.path_join(name)
		result[path] = _hash_file(path)
	for name in access.get_directories():
		_source_files(directory.path_join(name),result)

func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	if DisplayServer.get_name()=="headless":
		_source_files("res://native",result)
		for path in [CANDIDATE_PATH,"res://native/battlefield_world_adapter.gd","res://tests/qa_vis01_candidate.gd"]:
			result[path] = _hash_file(path)
		return result
	for directory in ["res://native","res://assets/battlefields-remaster","res://assets/materials/terrain","res://assets/models/battlefield"]:
		_source_files(directory,result)
	for path in [REFERENCE_PATH,CHARACTER_REFERENCE_PATH,"res://project.godot","res://native/sengoku_ui.gd","res://native/battlefield_hud.gd","res://tests/qa_vis01_candidate.gd"]:
		result[path] = _hash_file(path)
	return result

func isolated() -> bool:
	var profile: String = OS.get_environment("APPDATA").replace("\\","/").to_lower()
	var local: String = OS.get_environment("LOCALAPPDATA").replace("\\","/").to_lower()
	var root_profile: String = ProjectSettings.globalize_path("res://tests/profiles/").replace("\\","/").to_lower()
	var save: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	return check(profile.begins_with(root_profile+"vis01-candidate-") and profile==local and save.begins_with(profile+"/"),"Disposable VIS-01 profile required")

func _point(x: float,z: float,bounds: Dictionary) -> Vector2:
	return Vector2((x-float(bounds.x))/float(bounds.width),(z-float(bounds.z))/float(bounds.depth))

func _dict_point(p: Vector2) -> Dictionary:
	return {"x":p.x,"y":p.y}

func _running_state(value: Dictionary) -> bool:
	return bool(value.get("running",false)) and not bool(value.get("paused",true)) and not bool(value.get("finished",true)) and not bool(value.get("betweenWaves",true))

func _capture_ready() -> bool:
	return _running_state(app.game.snapshot()) and app.game.units.size()==4 and app.game.enemies.size()>0 and app.game.recruitment_queue.is_empty() and int(app.combat_feedback.event_counts.get("hit",0))>0

func _mechanical_signature() -> String:
	var state: Dictionary = app.game.snapshot()
	var values: Dictionary = {}
	for key in ["running","paused","finished","betweenWaves","elapsed","animationTime","wave","hp","maxHp","gold","kills","units","enemies","objectives","recruitmentQueue","remainingSpawns","deathActors"]:
		values[key] = state.get(key)
	return JSON.stringify(values).sha256_text()

func _candidate_outside_catalog(shell: Node) -> bool:
	if not shell.isolated_candidate: return false
	for entry in shell.maps:
		if str(entry.get("id",""))=="vis01-tactical-candidate-v2": return false
	return true

func _retreat_floor_checks(candidate: Dictionary, floor: Node3D) -> void:
	var data: Dictionary = candidate.visualComposition.get("retreatPresentation",{})
	if data.is_empty(): return
	var points: Array = candidate.visualComposition.retreatTrail
	var bounds: Dictionary = candidate.worldGeometry.simulationBounds
	var radius: float = float(data.widthWorld)*.5
	# The enclosing normalized circle is conservative for this non-square floor.
	var normalized_radius: float = radius/minf(float(bounds.width),float(bounds.depth))
	for index in range(points.size()-1):
		var a: Array = points[index]
		var b: Array = points[index+1]
		check(floor.segment_clear(_point(float(a[0]),float(a[1]),bounds),_point(float(b[0]),float(b[1]),bounds),.018),"Retreat story trail admits existing body envelope on sole floor")
		# Full WORLD-width strip: anisotropic normalized scaling cannot be replaced
		# with a larger circular radius; use actual border and center floor picks.
		var direction := Vector2(float(b[0])-float(a[0]),float(b[1])-float(a[1])).normalized()
		var side := Vector2(-direction.y,direction.x)*radius
		for step in range(9):
			var center: Vector2 = Vector2(float(a[0]),float(a[1])).lerp(Vector2(float(b[0]),float(b[1])),float(step)/8)
			for offset in [Vector2.ZERO,side,-side]:
				var p: Vector2 = _point(center.x+offset.x,center.y+offset.y,bounds)
				check(floor.world_point(p).is_finite() and floor.placement_clear(p,0.0),"Full-width retreat strip border uses unblocked canonical dry floor")
	check(normalized_radius>0.0 and not bool(data.get("evacuationRoute",true)),"Withdraw direction is presentation-only, without a new evacuation simulation rule")
	var rear: Array = candidate.visualComposition.fort.rearOpeningSegment
	var midpoint := Vector2((float(rear[0][0])+float(rear[1][0]))*.5,(float(rear[0][1])+float(rear[1][1]))*.5)
	check(floor.placement_clear(_point(midpoint.x,midpoint.y,bounds),.018),"Actual trimmed rear passage admits existing body envelope")
	for id in ["zone-09","zone-08","zone-11"]:
		var anchor: Dictionary = candidate.visualComposition.contextAnchors[id]
		var p := Vector2(float(anchor.normalized[0]),float(anchor.normalized[1]))
		var contact: Vector3 = floor.world_point(p)
		check(contact.is_finite() and contact.distance_to(Vector3(float(anchor.worldPosition[0]),float(anchor.worldPosition[1]),float(anchor.worldPosition[2])))<.00001,"New context landmark has exact provider display anchor "+id)
		var support: Array = anchor.supportRequestAnchor.normalized
		check(floor.placement_clear(Vector2(float(support[0]),float(support[1])),.017),"Existing support base remains on safe dry provider floor "+id)

func fixture(candidate: Dictionary) -> Dictionary:
	var stage: Dictionary = candidate.duplicate(true)
	stage["id"] = "vis01-tactical-candidate-v2"
	stage["title"] = "마루네 · 철수 엄호 후보"
	stage["candidateOnly"] = true
	stage["theme"] = "grass"
	var bounds: Dictionary = stage.worldGeometry.simulationBounds
	var points: Array = []
	for p in stage.visualComposition.route: points.append(_dict_point(_point(float(p[0]),float(p[1]),bounds)))
	var objective: Array = stage.visualComposition.objectiveStandingSample
	var target: Vector2 = _point(float(objective[0]),float(objective[1]),bounds)
	stage["paths"] = [{"id":"candidate-approach","objectiveId":"candidate-objective","points":points}]
	# 25 is the current Game.load_map objective fallback, explicitly required by
	# runtime snapshots. It is a labeled fixture, not an accepted map balance value.
	stage["objectives"] = [{"id":"candidate-objective","label":"철수 엄호 지점", "x":target.x,"y":target.y,"hp":25}]
	var zones: Array = []
	for i in range(stage.visualComposition.deploymentAreas.size()):
		var area: Dictionary = stage.visualComposition.deploymentAreas[i]
		var world: Array = area.center
		var p: Vector2 = _point(float(world[0]),float(world[1]),bounds)
		zones.append({"id":str(area.id),"x":p.x,"y":p.y,"r":float(area.radiusNormalized),"elevation":int(area.gameplayElevation),"terrain":"earth","label":"흙 진지"})
	stage["buildZones"] = zones
	return stage

func floor_checks(candidate: Dictionary) -> void:
	var script: Script = load("res://native/battlefield_world_adapter.gd")
	var floor: Node3D = script.new()
	root.add_child(floor)
	floor.configure(candidate)
	var details: Dictionary = floor.diagnostics()
	check(bool(details.get("ready",false)),"Actual candidate authored topology accepted")
	check(int(details.get("vertices",0))==candidate.worldGeometry.vertices.size() and int(details.get("triangles",0))==int(candidate.worldGeometry.triangles.size()/3),"Native provider consumed complete authored V2 surface")
	check(not bool(details.get("projectionShear",true)),"No painted-anchor height shear")
	if bool(details.get("ready",false)):
		_retreat_floor_checks(candidate,floor)
		for world in candidate.visualComposition.route:
			var p: Vector2 = _point(float(world[0]),float(world[1]),candidate.worldGeometry.simulationBounds)
			var actual: Vector3 = floor.world_point(p)
			check(actual.is_finite() and floor.world_to_normalized(actual).distance_to(p)<.000001,"Canonical world contact/inverse agrees")
			var hit: Dictionary = floor.ray_pick(actual+Vector3.UP*10,Vector3.DOWN)
			check(bool(hit.get("valid",false)) and hit.worldPosition.distance_to(actual)<.0001,"Pick and visible triangle contact agree")
			check(floor.placement_clear(p,.018),"Approach/objective floor admits existing footprint")
		var gate_world: Array = candidate.visualComposition.gate.center
		var gate: Vector2 = _point(float(gate_world[0]),float(gate_world[1]),candidate.worldGeometry.simulationBounds)
		check(floor.placement_clear(gate,.018),"Open gate admits a whole normalized footprint")
		var fence_data: Dictionary = candidate.visualComposition.fences[0]
		var fence: Vector2 = _point((float(fence_data.a[0])+float(fence_data.b[0]))*.5,(float(fence_data.a[1])+float(fence_data.b[1]))*.5,candidate.worldGeometry.simulationBounds)
		check(not floor.placement_clear(fence,.018),"Visible stockade classified blocking")
		for i in range(candidate.visualComposition.route.size()-1):
			var a: Array = candidate.visualComposition.route[i]
			var b: Array = candidate.visualComposition.route[i+1]
			check(floor.segment_clear(_point(float(a[0]),float(a[1]),candidate.worldGeometry.simulationBounds),_point(float(b[0]),float(b[1]),candidate.worldGeometry.simulationBounds),.018),"Whole-footprint gate approach segment clear")
	floor.queue_free()
	await process_frame

func settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func main_preflight(candidate: Dictionary) -> void:
	var scene: PackedScene = load("res://native/main.tscn")
	var shell: Node = scene.instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	var catalog_signature: String = JSON.stringify(shell.maps).sha256_text()
	var result: Dictionary = shell.configure_candidate(fixture(candidate))
	check(bool(result.get("ok",false)),"Headless actual Main candidate preflight")
	if bool(result.get("ok",false)):
		var state: Dictionary = shell.game.snapshot()
		check(not state.is_empty() and int(state.get("maxHp",0))==25 and int(state.get("hp",0))==25,"Actual objective fixture is complete")
		check(int(state.get("gold",-1))==280,"Current Game fallback initial gold displayed")
		check(_candidate_outside_catalog(shell) and JSON.stringify(shell.maps).sha256_text()==catalog_signature,"Isolated candidate remains outside unchanged campaign catalog")
		var visuals: Node3D = VisualScene.new()
		shell.troops_3d.world.add_child(visuals)
		visuals.configure(candidate,shell.troops_3d.battlefield)
		visuals.apply_lighting(shell.troops_3d)
		var art: Dictionary = visuals.diagnostics()
		check(int(art.get("staticScanTemplates",0))>=8 and int(art.get("staticScanTriangles",0))>0,"Actual scanned tactical prop templates load")
		check(bool(art.get("staticLodBudgetsMet",false)),"Actual selected static indices satisfy authored surface budgets")
		check(int(art.get("staticScanTriangles",0))<400000,"Actual instanced static scan count remains below400k; not a frame-time acceptance")
		check(int(art.get("peripheralSceneryTriangles",0))==int(candidate.visualComposition.landscapeScenery.triangles.size()/3) and int(art.get("peripheralSceneryHeightFailures",-1))==0,"Complete noninteractive scenery mesh and grounded static props")
		var peripheral_tree: Dictionary = {}
		for entry in candidate.visualComposition.landscapeScenery.get("props",candidate.visualComposition.landscapeScenery.get("trees",[])):
			if str(entry.get("kind","tree"))=="tree":
				peripheral_tree = entry
				break
		var outside := Vector3(float(peripheral_tree.get("x",-10.55)),float(peripheral_tree.get("sceneryFloorY",0.0)),float(peripheral_tree.get("z",-6.6667)))
		check(not is_finite(shell.troops_3d.battlefield.sample_world_height(outside)),"Peripheral scenery never becomes an authoritative game floor")
		check(not bool(shell.troops_3d.battlefield.ray_pick(outside+Vector3.UP*10,Vector3.DOWN).get("valid",false)),"Provider picking remains outside visual-only periphery")
		check(visuals.find_children("*","CollisionObject3D",true,false).is_empty() and visuals.find_children("*","CollisionShape3D",true,false).is_empty(),"Candidate presentation adds no second collision floor or bodies")
		var archer_orders: int = 0
		for zone in shell.game.zones:
			if str(zone.get("placementRole",""))!="ranged": continue
			var hint: Vector2 = shell.game._zone_placement_hint(zone,"archer")
			check(hint.x>=0 and int(zone.get("elevation",-1))==0,"Authored post offers actual legal archer placement without height bonus")
			if archer_orders<2:
				check(bool(shell.game.submit_deployment("archer",hint).get("ok",false)),"Actual paid side archer order accepted")
				archer_orders+=1
		check(archer_orders==2,"Only two side archers ordered; auxiliary post remains empty")
		for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
			root.size=dimensions
			root.content_scale_size=dimensions
			shell._layout()
			await process_frame
			check(shell.hud_health.text.contains("25 / 25"),"Live health HUD at "+str(dimensions))
			check(shell.troops_3d.uses_world_geometry(),"Actual world provider at "+str(dimensions))
		var base: Dictionary = shell.game.ground_combat.select_march_base(0)
		check(not base.is_empty(),"Marching recruit base derives from new route")
		if not base.is_empty():
			check(shell.troops_3d.battlefield.placement_clear(base.position,.017),"Derived base admits existing first-stride formation envelope")
			for i in range(2):
				check(bool(shell.game.submit_deployment("spear",base.position,str(base.pathId)).get("ok",false)),"Actual paid spear order uses derived base")
		check(shell.game.snapshot().recruitmentQueue.size()==4 and int(shell.game.snapshot().gold)==30,"Four paid orders consume actual 250 supply; no free actors")
		shell.game.field_markers()
		shell.game.actor_states()
	shell.queue_free()
	await process_frame
	await process_frame

func save_image(picture: Image,name_value: String) -> String:
	var path: String = ProjectSettings.globalize_path("user://"+name_value+".png")
	check(picture.save_png(path)==OK,"Save native evidence "+name_value)
	images.append(path)
	return path

func _native_crop(picture: Image,world: Vector2) -> Image:
	var ground: Vector3 = app.troops_3d.battlefield.world_point(world)
	var point: Vector2 = app.troops_3d.global_position+app.troops_3d.project_world_to_field(ground)
	var origin := Vector2i(roundi(point.x)-100,roundi(point.y)-90)
	origin.x = clampi(origin.x,0,picture.get_width()-200)
	origin.y = clampi(origin.y,0,picture.get_height()-180)
	return picture.get_region(Rect2i(origin,Vector2i(200,180)))

func reference_sheet(frame: Image,resolution: String) -> void:
	var reference: Image = Image.load_from_file(ProjectSettings.globalize_path(REFERENCE_PATH))
	check(reference!=null,"Original user material reference available")
	if reference==null: return
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("141819")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(backdrop)
	var header := Label.new()
	header.text = "VIS-01  |  REFERENCE / NATIVE  |  200 x 180 ORIGINAL PIXELS"
	header.position = Vector2(42,30)
	header.add_theme_font_size_override("font_size",24)
	overlay.add_child(header)
	var width: float = root.size.x
	var labels: Array[String] = ["TIMBER / GATE","COMPACTED EARTH","WEATHERED STONE"]
	var rects: Array[Rect2i] = [Rect2i(230,447,200,180),Rect2i(730,352,200,180),Rect2i(115,160,200,180)]
	var native_points: Array[Vector2] = [
		_point(float(app.current_map.visualComposition.gate.center[0]),float(app.current_map.visualComposition.gate.center[1]),app.current_map.worldGeometry.simulationBounds),
		_point(float(app.current_map.visualComposition.route[2][0]),float(app.current_map.visualComposition.route[2][1]),app.current_map.worldGeometry.simulationBounds),
		_point(float(app.current_map.visualComposition.rocks[0].x),float(app.current_map.visualComposition.rocks[0].z),app.current_map.worldGeometry.simulationBounds)]
	for i in range(3):
		var x: float = 40+float(i)*(width-80)/3
		var title := Label.new()
		title.text = labels[i]
		title.position = Vector2(x,98)
		title.add_theme_font_size_override("font_size",19)
		overlay.add_child(title)
		var original: Image = reference.get_region(rects[i])
		var native: Image = _native_crop(frame,native_points[i])
		save_image(original,resolution+"-reference-"+str(i))
		save_image(native,resolution+"-native-"+str(i))
		for row in range(2):
			var texture := TextureRect.new()
			texture.texture = ImageTexture.create_from_image(original if row==0 else native)
			texture.position = Vector2(x,144+row*236)
			texture.size = Vector2(200,180)
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			overlay.add_child(texture)
			var caption := Label.new()
			caption.text = "REFERENCE · original" if row==0 else "NATIVE · framebuffer"
			caption.position = texture.position+Vector2(0,184)
			caption.add_theme_font_size_override("font_size",17)
			overlay.add_child(caption)
	var note := Label.new()
	note.text = "Candidate only. Equal pixel scale; no enlargement, retouch or similarity score. G1 user review pending."
	note.position = Vector2(40,root.size.y-60)
	note.add_theme_font_size_override("font_size",17)
	overlay.add_child(note)
	app.ui.hide()
	app.field_clip.hide()
	root.add_child(overlay)
	await settle()
	save_image(root.get_texture().get_image(),resolution+"-material-comparison")
	overlay.queue_free()
	app.ui.show()
	app.field_clip.show()
	await process_frame

func percentile(values: Array[float],quantile: float) -> float:
	if values.is_empty(): return 0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size()-1,floori((sorted.size()-1)*quantile))]

func frame_metrics(seconds: float) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var last: int = start
	var intervals: Array[float] = []
	var stalls: int = 0
	var initial: Dictionary = app.game.snapshot()
	var interrupted_frames: int = 0
	var first_interruption: Dictionary = {}
	while float(Time.get_ticks_usec()-start)/1000000.0<seconds:
		await process_frame
		var state: Dictionary = app.game.snapshot()
		if not _running_state(state):
			interrupted_frames+=1
			if first_interruption.is_empty():
				for key in ["running","paused","finished","betweenWaves","elapsed","wave"]: first_interruption[key]=state.get(key)
		var now: int = Time.get_ticks_usec()
		var frame_ms: float = float(now-last)/1000.0
		last=now
		intervals.append(frame_ms)
		if frame_ms>50: stalls+=1
	var final_state: Dictionary = app.game.snapshot()
	var elapsed_delta: float = float(final_state.get("elapsed",0))-float(initial.get("elapsed",0))
	var continuous: bool = _running_state(initial) and _running_state(final_state) and interrupted_frames==0 and elapsed_delta>0.0
	check(continuous,"Performance window continuously samples live natural battle without intermission or finish")
	return {"measurementSeconds":float(last-start)/1000000.0,"frames":intervals.size(),
		"scope":"continuous-running-clock" if continuous else "interrupted-wall-frames",
		"continuousRunning":continuous,"nonRunningFrames":interrupted_frames,"firstInterruption":first_interruption,
		"gameElapsedStart":initial.get("elapsed",0),"gameElapsedEnd":final_state.get("elapsed",0),"gameElapsedDelta":elapsed_delta,
		"wallFrameP50Ms":percentile(intervals,.5),"wallFrameP95Ms":percentile(intervals,.95),
		"wallFrameP99Ms":percentile(intervals,.99),"stallsOver50Ms":stalls,
		"processStaticMemoryBytes":OS.get_static_memory_usage(),"trackedObjectCount":Performance.get_monitor(Performance.OBJECT_COUNT),
		"renderedObjects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"renderedPrimitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"actualGameActors":app.game.actor_states().size(),"actualTroopsActors":app.troops_3d.actors.size(),
		"engineFrameCpuSeconds":Performance.get_monitor(Performance.TIME_PROCESS)}

func presentation_readback(visuals: Node3D, candidate: Dictionary, resolution: String) -> Dictionary:
	var provider: Node3D = app.troops_3d.battlefield
	var ground: MeshInstance3D = provider.get("ground")
	var material: ShaderMaterial = ground.material_override as ShaderMaterial
	check(material!=null,"Actual floor retains remaster ShaderMaterial after layout "+resolution)
	var details: Dictionary = {"cameraSize":app.troops_3d.camera.size,"cameraPosition":str(app.troops_3d.camera.position),
		"cameraRotation":str(app.troops_3d.camera.rotation_degrees),"sunEnergy":app.troops_3d.sun.light_energy,
		"ambientEnergy":app.troops_3d.environment.ambient_light_energy,"actorFillEnergy":app.troops_3d.fill.light_energy}
	if material!=null:
		details["floorMaterialInstanceId"]=material.get_instance_id()
		details["storedMaterialInstanceId"]=provider.get("_material").get_instance_id()
		details["shaderCodeSha256"]=material.shader.code.sha256_text()
		for uniform in ["route_count","retreat_count","retreat_half_width","approach_base_color","retreat_base_color","has_rear_gate","normal_depth","roughness_floor"]:
			details[uniform]=str(material.get_shader_parameter(uniform))
		check(material==provider.get("_material"),"Stored provider and actual floor material identities agree "+resolution)
		var expected_retreat: Array = candidate.visualComposition.retreatTrail.duplicate()
		for point in candidate.visualComposition.retreatPresentation.outerContinuation.points:
			if expected_retreat.is_empty() or expected_retreat[-1]!=point: expected_retreat.append(point)
		check(int(material.get_shader_parameter("retreat_count"))==expected_retreat.size() and bool(material.get_shader_parameter("has_rear_gate")),"Actual material consumes complete authored retreat and rear opening "+resolution)
	var field: Rect2 = app.field_clip.get_global_rect()
	var transform: Transform2D = app.troops_3d.get_global_transform_with_canvas()
	var labels: Array = []
	for cue in visuals.diagnostics().get("directionCues",[]):
		var p: Array = cue.labelWorldPosition
		var screen: Vector2 = transform*app.troops_3d.project_world_to_field(Vector3(float(p[0]),float(p[1]),float(p[2])))
		var text_width: float = GameFonts.body().get_string_size(str(cue.label),HORIZONTAL_ALIGNMENT_LEFT,-1,32).x*float(cue.labelPixelSize)*float(app.troops_3d.field_size.x)/float(app.troops_3d.camera.size)
		var rect := Rect2(screen-Vector2(text_width*.5,12),Vector2(text_width,24))
		var covered: bool = app.army_panel.is_visible_in_tree() and app.army_panel.get_global_rect().intersects(rect)
		check(field.encloses(rect) and not covered,"Actual direction label stays inside HUD-safe field "+resolution+" "+str(cue.role))
		labels.append({"role":cue.role,"screen":str(screen),"bounds":str(rect),"coveredByInspector":covered})
	details["directionLabels"]=labels
	details["scope"]="Actual material IDs/uniforms and lighting after resize; raster appearance still requires original-image review"
	return details

func inspector_occlusion(candidate: Dictionary, resolution: String) -> Dictionary:
	var panel: Rect2 = app.army_panel.get_global_rect()
	var field: Rect2 = app.field_clip.get_global_rect()
	var transform: Transform2D = app.troops_3d.get_global_transform_with_canvas()
	var anchors: Array = []
	var actors: Array = []
	var critical: Array = candidate.visualComposition.route.duplicate()
	for point in [candidate.visualComposition.gate.center,candidate.visualComposition.objectiveStandingSample]:
		if not critical.has(point): critical.append(point)
	for world in critical:
		var normalized: Vector2 = _point(float(world[0]),float(world[1]),candidate.worldGeometry.simulationBounds)
		var screen: Vector2 = transform*app.troops_3d.model_to_field_point(normalized)
		var overlap: bool = app.army_panel.is_visible_in_tree() and panel.has_point(screen)
		check(screen.is_finite() and field.has_point(screen) and not overlap,"Actual inspector leaves route/gate/objective anchor visible "+resolution)
		anchors.append({"world":world,"screen":str(screen),"covered":overlap})
	for actor in app.game.actor_states():
		if bool(actor.get("dead",false)): continue
		var marker: Dictionary = app.troops_3d.health_anchor_for(int(actor.id))
		check(not marker.is_empty(),"Live actor has actual projected head/foot bounds "+resolution)
		if marker.is_empty(): continue
		var head: Vector2 = transform*marker.headPosition
		var foot: Vector2 = transform*marker.footPosition
		var body: Rect2 = Rect2(Vector2(minf(head.x,foot.x)-10,minf(head.y,foot.y)-4),Vector2(absf(head.x-foot.x)+20,absf(head.y-foot.y)+8))
		var overlap: bool = app.army_panel.is_visible_in_tree() and panel.intersects(body)
		check(head.is_finite() and foot.is_finite() and not overlap,"Actual inspector leaves live actor head/foot span visible "+resolution)
		actors.append({"id":int(actor.id),"friendly":bool(actor.get("friendly",false)),"projectedHeadFootBounds":str(body),"covered":overlap})
	return {"inspectorBounds":str(panel),"anchors":anchors,"actors":actors,"scope":"Same capture frame; projected head/foot span with10px lateral padding is not a full weapon/equipment silhouette measurement"}

func gpu_run(candidate: Dictionary) -> void:
	var scene: PackedScene = load("res://native/main.tscn")
	app=scene.instantiate()
	root.add_child(app)
	await settle()
	var catalog_signature: String = JSON.stringify(app.maps).sha256_text()
	for entry in app.maps: observed_campaign_ids.append(str(entry.get("id","")))
	startup_msec=float(Time.get_ticks_usec()-started_usec)/1000.0
	var load_start: int = Time.get_ticks_usec()
	var result: Dictionary = app.configure_candidate(fixture(candidate))
	candidate_load_msec=float(Time.get_ticks_usec()-load_start)/1000.0
	check(bool(result.get("ok",false)),"Real Main configures isolated candidate")
	if not bool(result.get("ok",false)): return
	var initial: Dictionary = app.game.snapshot()
	check(not initial.is_empty() and int(initial.get("maxHp",0))>0 and int(initial.get("gold",-1))>=0,"Complete actual-rule HUD snapshot before rendering")
	var visuals: Node3D = VisualScene.new()
	app.troops_3d.world.add_child(visuals)
	visuals.configure(candidate,app.troops_3d.battlefield)
	visuals.apply_lighting(app.troops_3d)
	app.game.set_input_enabled(true)
	app.game.set_speed(1)
	app.battle_started=true
	app.game.start_battle()
	var archer_orders: int = 0
	for zone in app.game.zones:
		if str(zone.get("placementRole",""))!="ranged": continue
		if archer_orders>=2: break
		var p: Vector2 = app.game._zone_placement_hint(zone,"archer")
		check(p.x>=0 and bool(app.game.submit_deployment("archer",p).get("ok",false)),"Actual unlocked archer queue request accepted")
		archer_orders+=1
	var base: Dictionary = app.game.ground_combat.select_march_base(0)
	check(not base.is_empty(),"Actual recruit base derived from new route")
	if not base.is_empty():
		for i in range(2):
			check(bool(app.game.submit_deployment("spear",base.position,str(base.pathId)).get("ok",false)),"Actual unlocked spear queue request accepted")
	# Real queues and autonomous waves advance under the runtime clock, never manual dt.
	var battle_wait_start: int = Time.get_ticks_msec()
	var contact_observed: bool = false
	while Time.get_ticks_msec()-battle_wait_start<35000:
		await create_timer(.25).timeout
		contact_observed = int(app.combat_feedback.event_counts.get("hit",0))>0
		if _capture_ready(): break
	check(_capture_ready(),"Four paid allies, empty queue and actual contact coexist in a live unfinished unpaused wave")
	check(contact_observed,"Actual committed attack contact observed under the natural clock before capture")
	if not failures.is_empty(): return
	app.game.pause_battle()
	var paused: Dictionary = app.game.snapshot()
	check(bool(paused.running) and bool(paused.paused) and not bool(paused.finished) and not bool(paused.betweenWaves),"Actual live battle pause succeeded before native comparison")
	if not failures.is_empty(): return
	var mechanical_signature: String = _mechanical_signature()
	# Freeze one real battle moment for both native-size visual comparisons.
	# Performance is sampled separately afterwards under the running clock.
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		app._layout()
		await settle()
		var resolution: String = str(dimensions.x)+"x"+str(dimensions.y)
		await settle()
		var picture: Image = root.get_texture().get_image()
		var occlusion: Dictionary = inspector_occlusion(candidate,resolution)
		var readback: Dictionary = presentation_readback(visuals,candidate,resolution)
		check(_mechanical_signature()==mechanical_signature,"Same paused gameplay state preserved across native-size comparison "+resolution)
		check(picture.get_size()==dimensions,"Native framebuffer "+resolution)
		check(_candidate_outside_catalog(app) and JSON.stringify(app.maps).sha256_text()==catalog_signature,"Candidate never registered in unchanged campaign catalog")
		check(app.troops_3d.uses_world_geometry(),"Actual Troops3D uses shared world provider")
		check(app.troops_3d.actors.size()>0,"Actual current-rule actors present")
		for world in [candidate.visualComposition.route[0],candidate.visualComposition.gate.center,candidate.visualComposition.objectiveStandingSample]:
			var p: Vector2 = _point(float(world[0]),float(world[1]),candidate.worldGeometry.simulationBounds)
			var screen: Vector2 = app.troops_3d.global_position+app.troops_3d.model_to_field_point(p)
			check(app.field_clip.get_global_rect().has_point(screen),"Entry/gate/objective inside actual HUD-safe viewport")
		var path: String = save_image(picture,resolution+"-native-candidate")
		captures.append({"resolution":resolution,"path":path,"snapshot":app.game.snapshot(),
			"inspectorOcclusion":occlusion,"presentationReadback":readback,"pausedMechanicalSignature":mechanical_signature,
			"visuals":visuals.diagnostics(),"world":app.troops_3d.battlefield.diagnostics(),
			"contactEventCounts":app.combat_feedback.event_counts.duplicate(),"canonicalStage01":false,"runtimeActorProfile":"default-alias",
			"clockManuallyAdvanced":false,"actorsInjected":false,"campaignMap":false})
		await reference_sheet(picture,resolution)
	app.game.pause_battle()
	check(_running_state(app.game.snapshot()),"Actual battle resumed for natural-clock performance samples")
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		root.size=dimensions
		root.content_scale_size=dimensions
		app._layout()
		await settle()
		var resolution: String = str(dimensions.x)+"x"+str(dimensions.y)
		var metrics: Dictionary = await frame_metrics(4.0)
		for capture in captures:
			if str(capture.resolution)==resolution:
				capture["metrics"]=metrics
				capture["performanceSnapshot"]=app.game.snapshot()
	if app.game.has_method("stop_battle"):
		app.game.stop_battle()
	else:
		app.game.set_process(false)
	app.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	if not isolated():
		quit(2)
		return
	source_before=source_hashes()
	var candidate: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_PATH))
	if not check(candidate is Dictionary,"Candidate JSON parses"):
		quit(1)
		return
	await floor_checks(candidate)
	if DisplayServer.get_name()=="headless" and failures.is_empty():
		await main_preflight(candidate)
	if DisplayServer.get_name()!="headless" and failures.is_empty():
		await gpu_run(candidate)
	var after: Dictionary = source_hashes()
	var frozen: bool = source_before==after
	check(frozen,"Capture sources remained frozen")
	var report: Dictionary = {
		"directiveId":"JP_DF-HQ-20261008-COMMON-FIRST-R1","taskId":"VIS-01","status":"PASS" if failures.is_empty() else "FAIL",
		"checks":checks,"failures":failures,"evidence":"STATIC_CHECK/AUTOMATED_TEST" if DisplayServer.get_name()=="headless" else "GPU_CAPTURE",
		"candidateOnly":true,"g1UserAccepted":false,"productionMapsRegistered":0,
		"productionMapsRegisteredScope":"This isolated candidate only; available canonical stages are separately listed",
		"availableCampaignStageIds":observed_campaign_ids,
		"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),
		"adapter":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),
		"startupToMainMsec":startup_msec,"candidateLoadMsec":candidate_load_msec,
		"warmupPolicy":"Natural recruitment until four paid allies, enemies and actual committed attack contact coexist; same paused real moment at both visual sizes; separate four-second running-clock samples after captures",
		"performanceScope":"Short candidate windows; process static memory is not Windows working set. Full load/select/exit and natural battle gate remain QA.",
		"sourcesFrozen":frozen,"sourceHashes":source_before,"images":images,"captures":captures}
	report["requiresCleanNativeProcessExit"] = true
	var path: String = ProjectSettings.globalize_path("user://qa-vis01-candidate.json")
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("VIS01_RESULT ",JSON.stringify({"status":report.status,"checks":checks,"failures":failures,"report":path,"images":images.size()}))
	quit(0 if failures.is_empty() else 1)
