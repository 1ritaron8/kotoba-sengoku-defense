extends SceneTree
const Adapter = preload("res://native/battlefield_world_adapter.gd")
const Game = preload("res://native/game.gd")
var checks: int=0
var failures: Array=[]
var observations: Dictionary={}
var surface: Node3D
var source_start: String=""
var game_source_start: String=""

class RangeProjection extends Control:
	var surface: Node3D
	func uses_world_geometry() -> bool: return true
	func model_to_field_point(point: Vector2) -> Vector2:
		var height: float=surface.height_at(point)
		return Vector2(point.x*1100,point.y*600-height*30) if is_finite(height) else Vector2(INF,INF)

func _initialize() -> void: call_deferred("run")
func check(value: bool, note: String) -> void:
	checks+=1
	if not value: failures.append(note); push_error("WORLD_ADAPTER "+note)

func quad() -> Dictionary:
	return {"schemaVersion":1,"simulationBounds":{"x":3,"z":-2,"width":10,"depth":6},"vertices":[{"x":3,"y":0,"z":-2},{"x":13,"y":1,"z":-2},{"x":13,"y":1,"z":4},{"x":3,"y":0,"z":4}],"triangles":[0,1,2,0,2,3]}

func normalized_mesh(points: Array, triangles: Array) -> Dictionary:
	var data: Dictionary=quad(); data.vertices=[]; data.triangles=triangles
	for point in points: data.vertices.append({"x":3+point.x*10,"y":point.x,"z":-2+point.y*6})
	return data

func reject(data: Dictionary, note: String) -> void:
	check(surface.load_geometry(quad()),"Valid floor before rejection: "+note)
	check(not surface.load_geometry(data),"Reject "+note)
	check(surface.surface_mesh()==null and surface.collision_body==null and not is_finite(surface.height_at(Vector2(.5,.5))),"Rejection clears stale visible/collision/query floor: "+note)

func check_tangents(note: String) -> void:
	var arrays: Array=surface.surface_mesh().surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
	check(normals.size()==vertices.size() and tangents.size()==vertices.size()*4,"Complete material tangent basis: "+note)
	var frames_valid: bool=normals.size()==vertices.size() and tangents.size()==vertices.size()*4
	if frames_valid:
		for id in range(vertices.size()):
			var tangent: Vector3=Vector3(tangents[id*4],tangents[id*4+1],tangents[id*4+2])
			if not tangent.is_finite() or absf(tangent.length()-1)>.0001 or absf(tangent.dot(normals[id]))>.0001 or absf(absf(tangents[id*4+3])-1)>.0001:
				frames_valid=false
				break
	check(frames_valid,"Finite orthonormal material frames: "+note)

func check_internal_seam_routes() -> void:
	var floors: Array=[quad(),normalized_mesh([Vector2.ZERO,Vector2(1,0),Vector2(0,1),Vector2.ONE],[0,2,1,1,2,3])]
	var home: Vector2=Vector2(.5,.5)
	for floor_index in range(floors.size()):
		check(surface.load_geometry(floors[floor_index]),"Both diagonal triangulations load for seam return regression")
		var clear: bool=true
		var first_failure: Dictionary={}
		for index in range(1024):
			var coordinate: float=.42+float(index)*.079/1023.0
			for point in [Vector2(coordinate,.5),Vector2(.5,coordinate)]:
				if not surface.segment_clear(point,home,.008) or not surface.segment_clear(home,point,.008):
					clear=false
					if first_failure.is_empty(): first_failure={"point":str(point),"home":str(home),"floor":floor_index}
		check(clear,"Continuous body-safe routes to/from an internal seam remain legal across nearby positions (diagonal %d)" % floor_index)
		if not first_failure.is_empty(): observations["seamFailure%d" % floor_index]=first_failure

func polygon_area(points: PackedVector2Array) -> float:
	var area: float=0
	for index in range(points.size()):
		var a: Vector2=points[index]; var b: Vector2=points[(index+1)%points.size()]
		area+=float(a.x)*float(b.y)-float(a.y)*float(b.x)
	return absf(area)*.5

func check_range_case(game: Node2D, data: Dictionary, center: Vector2, radius: float, note: String, expected_fraction: float = -1) -> Dictionary:
	check(surface.load_geometry(data),"Range display uses a validated original floor: "+note)
	game.config={"worldGeometry":data.duplicate(true)}
	var config_before: String=JSON.stringify(game.config)
	var geometry_before: String=surface.source_hash
	game._cache_circle_floor()
	var layout: Dictionary=game._world_circle_surface_layout(center,radius)
	var area: float=0; var arc_length: float=0
	var finite: bool=true; var floor_only: bool=true; var outline_only: bool=true
	var unsupported: Array=[]
	for polygon in layout.fills:
		area+=polygon_area(polygon)
		finite=finite and game._project_circle_points(polygon).size()==polygon.size()
		for index in range(polygon.size()):
			if not is_finite(surface.height_at(polygon[index])): unsupported.append({"kind":"fill","x":polygon[index].x,"y":polygon[index].y})
			for fraction in [0.0,.25,.5,.75]:
				floor_only=floor_only and is_finite(surface.height_at(polygon[index].lerp(polygon[(index+1)%polygon.size()],fraction)))
	for arc in layout.arcs:
		finite=finite and game._project_circle_points(arc).size()==arc.size()
		for point in arc:
			if not is_finite(surface.height_at(point)): unsupported.append({"kind":"arc","x":point.x,"y":point.y})
		for index in range(arc.size()-1):
			arc_length+=arc[index].distance_to(arc[index+1])
			for fraction in [0.0,.25,.5,.75,1.0]:
				var point: Vector2=arc[index].lerp(arc[index+1],fraction)
				floor_only=floor_only and is_finite(surface.height_at(point))
				var distance: float=point.distance_to(center)
				outline_only=outline_only and distance>=radius*cos(PI/48)-.000015 and distance<=radius+.000015
	check(area>0 and arc_length>0,"Legal partial fill and circumference remain visible: "+note)
	check(finite and floor_only,"Every displayed piece projects through the original height query, without missing-floor bridges: "+note)
	check(outline_only,"Only original circumference segments are outlined, without floor-edge or diagonal closures: "+note)
	if expected_fraction>=0:
		var disk_area: float=24*radius*radius*sin(TAU/48)
		var disk_length: float=96*radius*sin(PI/48)
		check(absf(area-disk_area*expected_fraction)<.000003 and absf(arc_length-disk_length*expected_fraction)<.0002,"Clipped fill area and open-arc length preserve the expected disk fraction: "+note)
	var outline: Dictionary=game._world_circle_surface_layout(center,radius,false)
	check(outline.fills.is_empty() and outline.arcs==layout.arcs,"Transparent range display keeps identical legal arcs without unnecessary fill: "+note)
	check(JSON.stringify(game.config)==config_before and surface.source_hash==geometry_before,"Range layout cannot modify authored geometry or game state: "+note)
	return {"case":note,"fillPieces":layout.fills.size(),"arcPieces":layout.arcs.size(),"area":area,"arcLength":arc_length,"finite":finite,"floorOnly":floor_only,"outlineOnly":outline_only,"unsupportedPoints":unsupported}

func check_range_circles() -> void:
	var game: Node2D=Game.new()
	var projection: RangeProjection=RangeProjection.new(); projection.surface=surface
	root.add_child(projection); root.add_child(game); game.set_process(false)
	game.render_projection_provider=projection
	var tiny_pixel_triangle: PackedVector2Array=PackedVector2Array([Vector2(351.5182,280.0805),Vector2(351.4608,280.0808),Vector2(351.5321,280.0187)])
	var local_triangle: PackedVector2Array=game._prepare_circle_fill(tiny_pixel_triangle)
	check(local_triangle.size()==3 and not Geometry2D.triangulate_polygon(local_triangle).is_empty(),"Positive-area screen triangle survives large-coordinate triangulation cancellation")
	check(absf(polygon_area(local_triangle)-polygon_area(tiny_pixel_triangle))<.000001,"Local tessellation preserves the legal tiny fill area")
	var restored_pixels: bool=local_triangle.size()==tiny_pixel_triangle.size()
	for index in range(local_triangle.size()): restored_pixels=restored_pixels and (local_triangle[index]+tiny_pixel_triangle[0]).distance_to(tiny_pixel_triangle[index])<.000001
	check(restored_pixels,"Canvas origin restoration preserves each original projected position")
	var cases: Array=[]
	cases.append(check_range_case(game,quad(),Vector2(.5,.5),.2,"full sloped disk across indexed diagonal",1))
	cases.append(check_range_case(game,quad(),Vector2(1,.5),.2,"half disk at eastern floor boundary",.5))
	cases.append(check_range_case(game,quad(),Vector2(1,1),.2,"quarter disk at floor corner",.25))
	var l_floor: Dictionary=normalized_mesh([Vector2(0,0),Vector2(1,0),Vector2(1,.4),Vector2(.4,.4),Vector2(.4,1),Vector2(0,1)],[0,1,3,1,2,3,0,3,5,3,4,5])
	cases.append(check_range_case(game,l_floor,Vector2(.4,.4),.2,"concave corner",.75))
	var hole: Dictionary=normalized_mesh([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1),Vector2(.4,.4),Vector2(.6,.4),Vector2(.6,.6),Vector2(.4,.6)],[0,1,4,1,5,4,1,2,5,2,6,5,2,3,6,3,7,6,3,0,7,0,4,7])
	cases.append(check_range_case(game,hole,Vector2(.35,.5),.18,"authored hole intersects range disk"))
	var precision: Dictionary={"schemaVersion":1,"simulationBounds":{"x":0,"z":0,"width":1,"depth":1},"vertices":[{"x":.000004,"y":0,"z":.2},{"x":.8,"y":.8,"z":.2},{"x":.000004,"y":0,"z":.8}],"triangles":[0,1,2]}
	cases.append(check_range_case(game,precision,Vector2(.04,.4),.08,"non-grid authored triangle boundary"))
	var thin: Dictionary=precision.duplicate(true)
	thin.vertices=[{"x":0,"y":0,"z":0},{"x":1,"y":1,"z":0},{"x":1,"y":1,"z":.000026}]
	cases.append(check_range_case(game,thin,Vector2(.5,.00001),.08,"thin original face retains local edge projection"))
	thin.simulationBounds={"x":0,"z":0,"width":10,"depth":10}
	thin.vertices=[{"x":0,"y":0,"z":0},{"x":10,"y":1,"z":0},{"x":10,"y":1,"z":.00000002}]
	cases.append(check_range_case(game,thin,Vector2(.5,.0000000005),.08,"accepted face below native clipping grid"))
	var diagonal: Dictionary=precision.duplicate(true)
	diagonal.vertices=[{"x":0,"y":0,"z":0},{"x":1,"y":1,"z":1},{"x":.9999998807907104,"y":1,"z":1}]
	cases.append(check_range_case(game,diagonal,Vector2(.5,.5),.08,"thin diagonal face with float32 boundary rounding"))
	var near_edge: Vector2=Vector2(.1,.100000015)
	var repaired: PackedVector2Array=game._circle_points_on_face(PackedVector2Array([near_edge]),game.circle_floor_faces[0].polygon)
	check(repaired.size()==1 and is_finite(surface.height_at(repaired[0])) and repaired[0].distance_to(near_edge)<.000001,"Float32 nearest-edge reconstruction remains locally supported by the original face")
	var candidate_path: String="res://assets/battlefields-remaster/stage01-candidate.json"
	if FileAccess.file_exists(candidate_path):
		var candidate: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(candidate_path))
		var data: Dictionary=candidate.worldGeometry
		check(surface.load_geometry(data),"Reachable authored candidate entry floor loads")
		var entry: Vector2=surface.world_to_normalized(Vector3(8.8,0,4.3))
		var outside: int=0
		for index in range(49):
			if not is_finite(surface.height_at(entry+Vector2(cos(TAU*index/48),sin(TAU*index/48))*.145)): outside+=1
		check(outside>0,"Reachable authored entry reproduces missing-floor perimeter samples; no assertion about saved capture coordinates")
		cases.append(check_range_case(game,data,entry,.145,"actual candidate route-entry boundary"))
		observations.rangeEntry={"world":{"x":8.8,"z":4.3},"normalized":{"x":entry.x,"y":entry.y},"radius":.145,"oldOutsideSamples":outside,"candidateHash":FileAccess.get_sha256(candidate_path)}
	game.config={"worldGeometry":{"simulationBounds":[],"vertices":[],"triangles":[]}}
	game._cache_circle_floor()
	check(game.circle_floor_faces.is_empty() and game._world_circle_surface_layout(Vector2(.5,.5),.2).fills.is_empty(),"Malformed/map-changed floor cannot retain stale range pieces")
	game.config={"worldGeometry":quad()}; game._cache_circle_floor()
	for radius in [0.0,-1.0,INF,NAN]:
		var rejected: Dictionary=game._world_circle_surface_layout(Vector2(.5,.5),radius)
		check(rejected.fills.is_empty() and rejected.arcs.is_empty(),"Invalid radius fails without invalid projection")
	observations.rangeCases=cases
	game.free(); projection.free()

func check_native_circle_and_quiz() -> void:
	var candidate: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefields-remaster/stage01-candidate.json"))
	var bounds: Dictionary=candidate.worldGeometry.simulationBounds
	var fixture: Dictionary=candidate.duplicate(true)
	fixture.id="vis01-material-candidate"; fixture.candidateOnly=true; fixture.theme="grass"
	var route: Array=[]
	for world in candidate.visualComposition.route:
		route.append({"x":(float(world[0])-float(bounds.x))/float(bounds.width),"y":(float(world[1])-float(bounds.z))/float(bounds.depth)})
	var objective: Array=candidate.visualComposition.objectiveStandingSample
	fixture.paths=[{"id":"candidate-approach","objectiveId":"candidate-objective","points":route}]
	fixture.objectives=[{"id":"candidate-objective","label":"철수 엄호 지점","x":(float(objective[0])-float(bounds.x))/float(bounds.width),"y":(float(objective[1])-float(bounds.z))/float(bounds.depth),"hp":25}]
	fixture.buildZones=[]
	for index in range(1,3):
		var world: Array=candidate.visualComposition.infantryStandingSamples[index]
		fixture.buildZones.append({"id":"candidate-standing-"+str(index),"x":(float(world[0])-float(bounds.x))/float(bounds.width),"y":(float(world[1])-float(bounds.z))/float(bounds.depth),"r":.058,"elevation":1,"terrain":"hill","label":"흙 진지"})
	var app: Node=load("res://native/main.tscn").instantiate()
	root.add_child(app); await process_frame; await process_frame
	var details: Array=[]
	for resolution in [Vector2i(1440,900),Vector2i(1280,800)]:
		root.size=resolution; root.content_scale_size=resolution; root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		app._layout(); await process_frame
		var configured: Dictionary=app.configure_candidate(fixture)
		check(bool(configured.ok),"Native diagnostic binds existing rejected candidate only inside disposable profile")
		await process_frame; await process_frame
		var source_before: String=JSON.stringify(app.game.config)
		for zone in app.game.zones:
			var layout: Dictionary=app.game._world_circle_surface_layout(zone.position,float(zone.r))
			var invalid: Array=[]; var raw_invalid: Array=[]; var total_area: float=0; var retained_area: float=0
			for polygon in layout.fills:
				var projected: PackedVector2Array=app.game._project_circle_points(polygon)
				var area: float=polygon_area(projected)
				total_area+=area
				if projected.size()>=3 and Geometry2D.triangulate_polygon(projected).is_empty():
					raw_invalid.append({"areaPixels":area,"normalized":str(polygon),"projected":str(projected),"points":Array(projected).map(func(point: Vector2) -> Dictionary: return {"x":point.x,"y":point.y})})
				var prepared: PackedVector2Array=app.game._prepare_circle_fill(projected) if app.game.has_method("_prepare_circle_fill") else projected
				if prepared.size()>=3:
					retained_area+=polygon_area(prepared)
					if Geometry2D.triangulate_polygon(prepared).is_empty(): invalid.append(str(prepared))
			check(invalid.is_empty(),"Native authored floor/camera range pieces triangulate before canvas submission "+str(resolution))
			check(total_area>0 and absf(retained_area-total_area)<.05,"Native clipped legal fill area remains visible without dropping the entire range "+str(resolution))
			details.append({"resolution":str(resolution),"field":str(app.game.field_rect),"zone":str(zone.id),"rawInvalid":raw_invalid,"invalidPrepared":invalid,"totalAreaPixels":total_area,"retainedAreaPixels":retained_area})
		check(JSON.stringify(app.game.config)==source_before,"Native render layout keeps game/map configuration unchanged")
		check(not app.current_map.has("background") and app.troops_3d.uses_world_geometry(),"New indexed battlefield supplies no retired painted background")
		var seen: Array=[]
		for word in app.lesson_session.words: seen.append(str(word.id))
		app.quiz_task=app.lesson_session.next_task(seen,2,false)
		var task: Dictionary=app.quiz_task.duplicate(true)
		var progress_before: String=JSON.stringify(app.progress.data)
		check(not task.is_empty() and str(task.get("kind",""))!="context","Native lesson supplies a nonspatial quiz through its existing task rules")
		app._show_quiz()
		check(app.modal_context=="quiz" and app.quiz_choices.size()==task.get("choices",[]).size() and is_instance_valid(app.modal_footer),"Native quiz builds actual choices and footer without a painted map background "+str(resolution))
		check(JSON.stringify(app.quiz_task)==JSON.stringify(task) and JSON.stringify(app.progress.data)==progress_before,"Quiz display keeps answers, task IDs and account data unchanged")
		app._cancel_learning_transition(); app._close_modal(false)
	observations.nativeCircleProjection=details
	observations.nativeQuiz={"resolutions":["1440x900","1280x800"],"scope":"Native Main/Troops floor/camera and quiz construction in headless isolated profile; rejected candidate is diagnostic geometry, not accepted Stage01 or natural battle."}
	app.free(); await process_frame

func finish_report(scope: String) -> void:
	check(source_start==FileAccess.get_sha256("res://native/battlefield_world_adapter.gd"),"Adapter source stays unchanged during verification")
	check(game_source_start==FileAccess.get_sha256("res://native/game.gd"),"Game source stays unchanged during verification")
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"sourceHash":source_start,"gameSourceHash":game_source_start,"scope":scope}
	var file: FileAccess=FileAccess.open("user://qa_battlefield_world_adapter.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ")); file.close()
	print("WORLD_ADAPTER ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path("user://qa_battlefield_world_adapter.json"))
	surface.free(); quit(0 if failures.is_empty() else 1)

func run() -> void:
	var user_path: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var boundary: String=ProjectSettings.globalize_path("res://tests/profiles/world-adapter").replace("\\","/").to_lower()
	if not user_path.begins_with(boundary): push_error("World adapter QA refuses player profiles"); quit(2); return
	source_start=FileAccess.get_sha256("res://native/battlefield_world_adapter.gd")
	game_source_start=FileAccess.get_sha256("res://native/game.gd")
	surface=Adapter.new(); root.add_child(surface)
	if "--range-overlay-only" in OS.get_cmdline_user_args():
		check_range_circles()
		if "--native-overlay-check" in OS.get_cmdline_user_args(): await check_native_circle_and_quiz()
		finish_report("Focused render-only range clipping/finite projection against the original floor query. CPU-only isolated projection; no AI, actual Troops/GPU, natural battle, map registration or acceptance claimed.")
		return
	var data: Dictionary=quad()
	check(surface.load_geometry(data),"Authored indexed slope loads")
	check_tangents("sloped floor")
	var mesh_arrays: Array=surface.surface_mesh().surface_get_arrays(0)
	var expected_vertices: PackedVector3Array=[Vector3(3,0,-2),Vector3(13,1,-2),Vector3(13,1,4),Vector3(3,0,4)]
	check(mesh_arrays[Mesh.ARRAY_VERTEX]==expected_vertices and mesh_arrays[Mesh.ARRAY_INDEX]==PackedInt32Array([0,1,2,0,2,3]),"Shading preserves exact authored vertices and upward triangle indices")
	check(mesh_arrays[Mesh.ARRAY_TEX_UV]==PackedVector2Array([Vector2(3,-2),Vector2(13,-2),Vector2(13,4),Vector2(3,4)]),"Shading preserves world XZ material UVs")
	check(surface.diagnostics().boundaryEdges==4,"Internal triangle seam is not a navigation wall")
	for x in [.001,.2,.5,.8,.999]:
		for y in [.001,.2,.5,.8,.999]:
			var point: Vector2=Vector2(x,y)
			var world: Vector3=surface.world_point(point)
			check(absf(world.y-x)<.00001 and surface.world_to_normalized(world).distance_to(point)<.00001,"Unequal fixed extents preserve exact slope and normalized roundtrip")
			check(absf(surface.sample_world_height(world+Vector3(0,10,0))-x)<.00001,"Contact ignores lifted-foot Y")
			var hit: Dictionary=surface.ray_pick(world+Vector3(0,10,0),Vector3.DOWN)
			check(bool(hit.valid) and hit.worldPosition.distance_to(world)<.0001 and hit.normal.y>0,"Visible triangle ray agrees with height including seam")
	check(surface.segment_clear(Vector2(.2,.3),Vector2(.8,.6),.02),"Full capsule crosses internal seams legally")
	check(not surface.placement_clear(Vector2(.005,.5),.012),"Center inside but body outside floor is rejected")
	check(not surface.segment_clear(Vector2(.005,.2),Vector2(.005,.8),.012),"Whole segment footprint respects floor edge")
	check(surface.segment_clear(Vector2(0,.2),Vector2(0,.8),0),"Zero-width boundary centerline is supported")
	check(not is_finite(surface.height_at(Vector2(-.01,.5))) and not bool(surface.ray_pick(Vector3(0,10,0),Vector3.DOWN).valid),"Missing floor never becomes a flat fallback")
	var before: Vector3=surface.world_point(Vector2(.3,.4))
	surface.configure({"worldGeometry":data},999,888,37)
	check(surface.world_point(Vector2(.3,.4))==before,"Legacy viewport/camera configure cannot resize authored extents")
	data.vertices[0].y=100
	check(absf(surface.height_at(Vector2(.1,.1))-.1)<.00001,"Caller mutation cannot change loaded mesh/query independently")
	surface.position.x=1
	check(not is_finite(surface.height_at(Vector2(.5,.5))) and not bool(surface.ray_pick(Vector3(8,10,1),Vector3.DOWN).valid),"Unsupported provider transform fails closed")
	surface.position=Vector3.ZERO
	check_internal_seam_routes()
	var l_floor: Dictionary=normalized_mesh([Vector2(0,0),Vector2(1,0),Vector2(1,.4),Vector2(.4,.4),Vector2(.4,1),Vector2(0,1)],[0,1,3,1,2,3,0,3,5,3,4,5])
	check(surface.load_geometry(l_floor),"Continuous concave floor loads")
	check(not surface.segment_clear(Vector2(.9,.3),Vector2(.3,.9),0),"Endpoints inside floor do not permit leaving concave floor")
	check(surface.segment_clear(Vector2(.9,.2),Vector2(.2,.2),.02),"Valid concave floor corridor remains traversable")
	var hole: Dictionary=normalized_mesh([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1),Vector2(.4,.4),Vector2(.6,.4),Vector2(.6,.6),Vector2(.4,.6)],[0,1,4,1,5,4,1,2,5,2,6,5,2,3,6,3,7,6,3,0,7,0,4,7])
	check(surface.load_geometry(hole),"Explicit floor hole loads")
	check(not surface.segment_clear(Vector2(.2,.5),Vector2(.8,.5),0) and not is_finite(surface.height_at(Vector2(.5,.5))),"Hole is unsupported even when both segment endpoints have floor")
	check(not surface.segment_clear(Vector2(.2,.39),Vector2(.8,.39),.02),"Footprint cannot graze a hole boundary")
	var masked: Dictionary=quad(); masked.triangleWalkable=[true,false]
	check(surface.load_geometry(masked) and is_finite(surface.height_at(Vector2(.2,.8))) and not surface.placement_clear(Vector2(.2,.8)),"Visible nonwalkable floor remains separate from movement permission")
	var flags: Dictionary=quad()
	flags.blockedPolygons=[{"id":"prop","points":[{"x":7,"z":0},{"x":9,"z":0},{"x":9,"z":2},{"x":7,"z":2}],"blocksMovement":true,"blocksPlacement":false}]
	check(surface.load_geometry(flags),"Explicit blocker loads")
	check(not surface.segment_clear(Vector2(.2,.5),Vector2(.8,.5),0),"Whole path sees a blocker between legal endpoints")
	check(not surface.segment_clear(Vector2(.2,.32),Vector2(.8,.32),.02),"Body-only blocker contact is rejected")
	check(surface.placement_clear(Vector2(.5,.5),.01),"Independent placement flag is preserved")
	flags.blockedPolygons[0].blocksMovement=false; flags.blockedPolygons[0].blocksPlacement=true
	check(surface.load_geometry(flags) and surface.segment_clear(Vector2(.2,.5),Vector2(.8,.5),.01) and not surface.placement_clear(Vector2(.5,.5),.01),"Independent navigation/placement roles retain meanings")
	var bad: Dictionary=quad(); bad.schemaVersion="1"; reject(bad,"coerced version")
	bad=quad(); bad.simulationBounds=[]; reject(bad,"wrong bounds type")
	bad=quad(); bad.vertices[0].x="3"; reject(bad,"coerced coordinates")
	bad=quad(); bad.triangles[0]=1.5; reject(bad,"fractional index")
	bad=quad(); bad.vertices.append({"x":3,"y":2,"z":-2}); reject(bad,"stacked X/Z vertex")
	bad=quad(); bad.triangles.append_array([0,1,2]); reject(bad,"positive-area duplicate floor")
	bad=quad(); bad.blockedPolygons=[{"points":[{"x":3,"z":-2},{"x":13,"z":-2},{"x":8,"z":-2},{"x":12,"z":-2},{"x":12,"z":4},{"x":3,"z":4}]}]; reject(bad,"collinear backtracking blocker")
	bad=quad(); bad.blockedPolygons=flags.blockedPolygons.duplicate(true); bad.blockedPolygons[0].blocksMovement="false"; reject(bad,"coerced blocker flag")
	bad=quad(); bad.blockedPolygons=[{}]; reject(bad,"missing blocker points")
	bad=quad(); bad.simulationBounds={"x":0,"z":0,"width":1e20,"depth":1e20}; bad.vertices=[{"x":0,"y":0,"z":0},{"x":1e20,"y":0,"z":0},{"x":1e20,"y":0,"z":1e20},{"x":0,"y":0,"z":1e20}]; reject(bad,"computed normal overflow")
	bad=normalized_mesh([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1),Vector2(.5,.5),Vector2(.8,.6),Vector2(.8,.8)],[0,1,2,0,2,3,4,5,6]); reject(bad,"positive area overlap")
	bad=normalized_mesh([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1),Vector2(.5,.5)],[0,1,2,0,4,3,4,2,3]); reject(bad,"partial triangle T-junction")
	surface.configure({"worldGeometry":[]})
	check(not surface.diagnostics().ready,"Malformed worldGeometry fails without script exception")
	check(surface.load_geometry(quad()),"Valid floor restores after rejection")
	await physics_frame; await physics_frame
	var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(Vector3(8,5,1),Vector3(8,-5,1))
	var collision: Dictionary=surface.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not collision.is_empty() and collision.position.distance_to(Vector3(8,.5,1))<.0001,"Actual static ground collision uses the exact authored slope")
	var candidate_path: String="res://assets/battlefields-remaster/stage01-candidate.json"
	if FileAccess.file_exists(candidate_path):
		var candidate: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(candidate_path))
		var candidate_data: Dictionary=candidate.get("worldGeometry",{})
		var started: int=Time.get_ticks_usec()
		check(surface.load_geometry(candidate_data),"Newly authored UX candidate floor validates without map registration")
		var load_usec: int=Time.get_ticks_usec()-started
		check_tangents("actual authored candidate")
		started=Time.get_ticks_usec()
		for index in range(1000): surface.height_at(Vector2(float(index%37+.5)/37,float(index%27+.5)/27))
		observations.candidate={"loadUsec":load_usec,"height1000Usec":Time.get_ticks_usec()-started,"geometryHash":surface.source_hash,"surface":surface.diagnostics()}
	check_range_circles()
	finish_report("Exact indexed floor/height/ray/static collision, normalized capsule navigation and range-display clipping; CPU-only. Candidate floor is not a registered or accepted map; no real Troops/HUD/GPU/art acceptance claimed.")
