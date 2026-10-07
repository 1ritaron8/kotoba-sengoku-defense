extends SceneTree
const Game = preload("res://native/game.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const MARCHING: Array = ["spear","samurai","commander"]
const SIZES: Array = [Vector2(1280,800),Vector2(1440,900),Vector2(1920,1080)]
const ROOT_PROFILE: String = "C:/JP_DF/tests/profiles/lower-layout-design/"
var checks: int=0
var failures: Array[String]=[]
var rows: Array=[]
var enrichments: Array=[]
var deployments: int=0
var source_sha: String=""
var movement_rows: Array=[]

func _initialize() -> void: call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:
		failures.append(note)
		if failures.size()<=30: push_error("LOWER_LAYOUT_RUNTIME "+note)

func allowed(point: Vector2,aspect: float) -> bool:
	var dx: float=(point.x-.5)*aspect
	var dy: float=point.y-.5
	return dy>0 and dx>=-sqrt(3.0)*dy-.000001 and dx<=dy/sqrt(3.0)+.000001

func plain(point: Vector2) -> Dictionary: return {"x":point.x,"y":point.y}

func minimum_hint(game: Node2D,type_name: String) -> Vector2:
	for zone in game.zones:
		var hint: Vector2=game._zone_placement_hint(zone,type_name)
		if hint.x>=0: return hint
	return Vector2(-1,-1)

func check_stage(game: Node2D,stage: Dictionary,baseline: Dictionary) -> void:
	game.load_map(stage)
	var tag: String=str(stage.id)
	check(not game.presentation_mirrored,tag+" no old display reflection is needed")
	for size in SIZES:
		var field: Rect2=Rect2(16,64,size.x-32,size.y-180)
		game.set_field_rect(field)
		for objective in game.objectives:
			check(allowed(objective.position,field.size.x/field.size.y),tag+" fixed/initial-mobile goal is inside actual 8-to-5 lower screen sector "+str(size))
		for base in game.ground_combat.march_bases:
			check(allowed(base.position,field.size.x/field.size.y),tag+" exact public marching spawn is inside lower screen sector "+str(size))
	check(game.ground_combat.march_bases.size()==stage.paths.size(),tag+" every fixed road retains a valid land-only recruiting base")
	var source_entry: Vector2=game._point(stage.commonEnemyEntry)
	var source_fork: Vector2=game._point(stage.commonEnemyEntry.branchPoint)
	check(source_entry.y<=.28 or (source_entry.x<=.07 or source_entry.x>=.93) and source_entry.y<=.60,tag+" common entry is an upper or side land inlet")
	var max_turn: float=0.0
	var length_array: Array=[]
	for index in range(game.paths.size()):
		var path: Dictionary=game.paths[index]
		check(path.id==baseline.paths[index].id and path.objectiveId==baseline.paths[index].objectiveId,tag+" path/objective routing identity preserved")
		check(path.points[0].distance_to(source_entry)<.000005 and path.points[1].distance_to(source_fork)<.000005,tag+" actual common inlet/fork is shared by every formation route")
		for segment in range(path.points.size()-1):
			check(game.ground_combat.land_segment_safe(path.points[segment],path.points[segment+1],.002),tag+" actual ground rules accept every sampled road segment "+str(index)+":"+str(segment))
		for vertex in range(1,path.points.size()-1):
			var previous: Vector2=path.points[vertex]-path.points[vertex-1]
			var following: Vector2=path.points[vertex+1]-path.points[vertex]
			if previous.length_squared()<=.00000001 or following.length_squared()<=.00000001: continue
			var angle: float=absf(rad_to_deg(previous.angle_to(following)))
			max_turn=maxf(max_turn,angle)
			check(angle<60.0,tag+" sampled route has no abrupt 60-degree navigation turn "+str(index)+":"+str(vertex)+" "+str(angle))
		length_array.append(float(game.ground_combat.cumulative[index][-1]))
	for zone in game.zones:
		var role: String=str(zone.placementRole)
		var type_name: String="archer" if role=="ranged" else "ninja" if role=="ambush" else "gunner"
		var hint: Vector2=game._zone_placement_hint(zone,type_name)
		check(hint.x>=0,tag+" every advertised "+role+" zone retains a real compatible placement hint "+str(zone.id))
		if hint.x>=0:
			check(not game._eligible_zone(hint,type_name).is_empty(),tag+" advertised candidate passes actual placement policy")
	var ambush_count: int=game.ground_combat.ambush_sites.size()
	check(ambush_count>=1,tag+" ninja retains at least one actual land-safe concealed site")
	var clearings: Array=[]
	for site in game.ground_combat.ambush_sites:
		clearings.append({"id":site.id,"pathIndex":site.pathIndex,"x":site.position.x,"y":site.position.y,"entry":plain(site.entryPosition),"r":site.r,"role":"external_ambush_cover"})
	enrichments.append({"stageId":stage.id,"ambushClearings":clearings})
	for index in range(game.paths.size()):
		if not stage.get("sideAmbushEntrances",[]).is_empty():
			var flank: Dictionary=game._prepared_ambush_entry(index)
			check(not flank.is_empty(),tag+" actual side-ingress preparation accepts authored own-route connection "+str(index))
			if not flank.is_empty():
				check(int(flank.pathIndex)==index,tag+" side hunter never joins a different fixed road")
				for segment in range(flank.points.size()-1): check(game.ground_combat.land_segment_safe(flank.points[segment],flank.points[segment+1],.002),tag+" real prepared side ingress stays on dry terrain")
		var enemy: Dictionary=game._spawn_enemy("raider",2,{"pathIndex":index,"formationGroup":"layout-proof"})
		check(enemy.pathIndex==index and enemy.spawnPathIndex==index and enemy.position.distance_to(source_entry)<.000005,tag+" actual cohort spawns at common entry on requested fixed path")
		check(not game._sailing_visual(enemy),tag+" newly authored dry historical route never renders as a boat")
		if int(stage.stageNumber)==1:
			var saved_roster: Dictionary=game.unlocked_roster.duplicate()
			game.unlocked_roster.erase("naginata")
			var protected_enemy: Dictionary=game._spawn_enemy("enemy_archer",1,{"pathIndex":index})
			check(str(protected_enemy.kind)=="raider",tag+" starter emplacement protection still converts locked tower hunter")
			game.unlocked_roster=saved_roster
	for zone in stage.buildZones:
		var point: Vector2=game._point(zone)
		var nearest_road: float=INF
		for index in range(game.paths.size()):
			for segment in range(game.paths[index].points.size()-1):
				var distance: float=game.ground_combat.point_distance(index,segment,point)
				nearest_road=minf(nearest_road,point.distance_to(game.ground_combat.route_point(index,distance)))
		check(nearest_road<=.206,tag+" every ranged support emplacement can cover an actual road with base archer range")
	if not stage.get("escortRoute",[]).is_empty():
		var escort: Array=stage.escortRoute
		check(game._point(escort[0]).distance_to(game._point(escort[-1]))<.000005,tag+" supply circulation closes without teleport")
		for segment in range(escort.size()-1): check(game.ground_combat.land_segment_safe(game._point(escort[segment]),game._point(escort[segment+1]),.002),tag+" actual cart route remains on land")
		for vertex in range(escort.size()-1):
			var a: Vector2=game._point(escort[posmod(vertex-1,escort.size()-1)])
			var b: Vector2=game._point(escort[vertex])
			var c: Vector2=game._point(escort[(vertex+1)%(escort.size()-1)])
			check(absf(rad_to_deg((b-a).angle_to(c-b)))<60,tag+" circulating cart has no abrupt reversal, including loop seam")
	rows.append({"stageId":stage.id,"stageNumber":stage.stageNumber,"pathCount":game.paths.size(),"routeLengths":length_array,"maxSampledTurnDegrees":max_turn,"baseCount":game.ground_combat.march_bases.size(),"ambushCount":ambush_count,"zoneCount":game.zones.size()})
	for key in ["id","stageNumber","theme","tier","difficulty","totalWaves","initialGold","recruitCost","unitLimit","music"]:
		check(stage.get(key)==baseline.get(key),tag+" preserves nongeometric game field "+key)
	for i in range(stage.objectives.size()): check(stage.objectives[i].hp==baseline.objectives[i].hp and stage.objectives[i].id==baseline.objectives[i].id,tag+" preserves objective identity and HP")
	for key in ["eventId","locationId","sourceUrls","season","weatherKnown","weather","historySummaryKo","timeOfDay","timeOfDayKnown"]:
		check(stage.historicalBattlefield.get(key)==baseline.historicalBattlefield.get(key),tag+" preserves historical record "+key)

func public_deployments(game: Node2D,stage: Dictionary) -> void:
	for type_name in TYPES:
		game.load_map(stage)
		game.gold=10000
		var before: int=game.gold
		check(game.begin_placement(type_name),str(stage.id)+" real class selection/order available "+type_name)
		if type_name in MARCHING:
			check(game.recruitment_queue.size()==1,str(stage.id)+" public marching class owns a valid route/base order")
			game._advance_recruitment(100)
		else:
			var hint: Vector2=minimum_hint(game,type_name)
			check(hint.x>=0,str(stage.id)+" public chosen class has real terrain "+type_name)
			if hint.x>=0: check(game.place_unit(hint.x,hint.y),str(stage.id)+" actual public placement succeeds "+type_name)
			game._advance_recruitment(100)
		check(not game.units.is_empty() and str(game.units[-1].type)==type_name,str(stage.id)+" requested class actually exists after production "+type_name)
		check(game.gold==before-game.recruit_cost(type_name),str(stage.id)+" deployment spends the same class cost exactly once "+type_name)
		if not game.units.is_empty():
			check(game.ground_combat.land_segment_safe(game.units[-1].position,game.units[-1].position,.001),str(stage.id)+" actual soldier appears on safe land "+type_name)
			deployments+=1

func observe_corner_movement(game: Node2D,stage: Dictionary) -> void:
	if int(stage.stageNumber) not in [28,33,40]: return
	game.load_map(stage)
	for index in range(game.paths.size()):
		var enemy: Dictionary=game._spawn_enemy("raider",2,{"pathIndex":index})
		var maximum_heading_change: float=0.0
		var samples: int=0
		var prior_progress: float=0.0
		for step in range(2500):
			var previous: Vector2=enemy.position
			var previous_aim: Vector2=enemy.aim
			game._move_enemy(enemy,.05)
			samples+=1
			check(game.ground_combat.land_segment_safe(previous,enemy.position,0.0),str(stage.id)+" real enemy movement follows dry road through corner")
			check(float(enemy.routeProgress)>=prior_progress-.000001,str(stage.id)+" real route progress does not reset or reverse after a bend")
			prior_progress=float(enemy.routeProgress)
			var heading_change: float=absf(rad_to_deg(previous_aim.angle_to(enemy.aim)))
			maximum_heading_change=maxf(maximum_heading_change,heading_change)
			check(heading_change<=rad_to_deg(.4)+.0001,str(stage.id)+" real enemy body turns within existing continuous yaw rate")
			if bool(enemy.escaped): break
		check(bool(enemy.escaped),str(stage.id)+" real navigation completes assigned route without stuck corner")
		movement_rows.append({"stageId":stage.id,"pathIndex":index,"samples":samples,"maxHeadingChangePer50msDegrees":maximum_heading_change,"escapedThroughOwnGoal":bool(enemy.escaped)})

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/")
	check(profile.begins_with(ROOT_PROFILE) and OS.get_environment("LOCALAPPDATA").replace("\\","/")==profile,"Private CPU profile only")
	if not failures.is_empty(): quit(2);return
	var draft_path: String=ROOT_PROFILE+"maps-lower-draft.json"
	var draft_sha: String=FileAccess.get_sha256(draft_path)
	source_sha=FileAccess.get_sha256("res://native/maps.json")
	var stages: Array=JSON.parse_string(FileAccess.get_file_as_string(draft_path))
	var originals: Array=JSON.parse_string(FileAccess.get_file_as_string(ROOT_PROFILE+"source-maps-baseline.json"))
	check(stages.size()==40 and originals.size()==40,"Complete forty-stage source candidate")
	var catalog: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var game: Node2D=Game.new()
	root.add_child(game)
	game.set_process(false)
	game.three_d_enabled=true
	game.configure_roster(catalog,TYPES,{})
	for i in range(stages.size()):
		check_stage(game,stages[i],originals[i])
		public_deployments(game,stages[i])
		observe_corner_movement(game,stages[i])
	check(FileAccess.get_sha256("res://native/maps.json")==source_sha,"CPU test never writes the production map")
	game.free()
	var report: Dictionary={"scope":"Actual Game lower-base/land/path/placement and selected corner movement checks, not final art or balance certification","checks":checks,"failures":failures,"passed":failures.is_empty(),"draftSha256":draft_sha,"sourceMapsSha256":source_sha,"stageCount":stages.size(),"publicSingleClassDeployments":deployments,"rows":rows,"actualCornerMovement":movement_rows,"ambushEnrichments":enrichments}
	var file: FileAccess=FileAccess.open(ROOT_PROFILE+"runtime-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("LOWER_LAYOUT_RUNTIME ",checks," checks, ",failures.size()," failures, public deployments ",deployments)
	quit(0 if failures.is_empty() else 1)
