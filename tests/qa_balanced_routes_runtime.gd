extends SceneTree
## Private candidate verification. Real game production/movement; fixture gold only.
const Game=preload("res://native/game.gd")
const PROFILE="C:/JP_DF/tests/profiles/balanced-route-design-20261007/"
var candidate_profile=PROFILE
var obstacle_comparisons: Array=[]
const TYPES=["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const MARCHING=["spear","samurai","commander"]
var checks=0
var failures: Array[String]=[]
var catalog: Array=[]
var rows: Array=[]
var maps_sha=""
var expected_sha=""
var samples=0
var hunters=0
var boats=0
var contact_only=false
var contact_pairs=0

func _initialize() -> void: call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:
		failures.append(note)
		if failures.size()<=30: push_error("BALANCED_ROUTES "+note)
func sha(path: String) -> String:
	var context=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()
func safe_candidate_directory(path: String) -> bool:
	var current=path.trim_suffix("/")
	while current.to_lower()!="c:/jp_df":
		var parent=current.get_base_dir()
		var directory=DirAccess.open(parent)
		if directory==null or directory.is_link(current.get_file()): return false
		if parent==current: return false
		current=parent
	return true
func make_game(stage: Dictionary) -> Node2D:
	var game: Node2D=Game.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,TYPES,{})
	game.load_map(stage)
	game.set_seed(77)
	return game
func hold(game: Node2D) -> void:
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue=["raider"]
	game.spawn_source_waves=[1]
	game.spawn_metadata=[{}]
	game.spawn_clock=100000.0
func lower(point: Vector2,aspect: float) -> bool:
	var dx=(point.x-.5)*aspect
	var dy=point.y-.5
	return dy>0 and dx>=-sqrt(3.0)*dy-.000001 and dx<=dy/sqrt(3.0)+.000001
func hint(game: Node2D,kind: String) -> Vector2:
	for zone in game.zones:
		var center: Vector2=game._zone_placement_hint(zone,kind)
		if center.x<0: continue
		if game.placement_preview(center).valid: return center
		for dx in [-.06,-.03,0.0,.03,.06]:
			for dy in [-.06,-.03,0.0,.03,.06]:
				var point=center+Vector2(dx,dy)
				if game.placement_preview(point).valid: return point
	return Vector2(-1,-1)
func geometry(game: Node2D,stage: Dictionary,original: Dictionary) -> void:
	var tag=str(stage.id)
	check(game.paths.size()==original.paths.size(),tag+" preserves route count")
	for size in [Vector2(1280,800),Vector2(1440,900),Vector2(1920,1080)]:
		var field=Rect2(16,64,size.x-32,size.y-180)
		game.set_field_rect(field)
		for objective in game.objectives: check(lower(objective.position,field.size.x/field.size.y),tag+" objective lower 8-to-5 "+str(size))
		for base in game.ground_combat.march_bases: check(lower(base.position,field.size.x/field.size.y),tag+" own recruiting base lower 8-to-5 "+str(size))
	check(game.ground_combat.march_bases.size()==game.paths.size(),tag+" every route has a land recruiting base")
	for index in range(game.paths.size()):
		var path: Dictionary=game.paths[index]
		check(path.id==original.paths[index].id and path.objectiveId==original.paths[index].objectiveId,tag+" route identity "+str(index))
		for segment in range(path.points.size()-1): check(game.ground_combat.land_segment_safe(path.points[segment],path.points[segment+1],.002),tag+" own route land/wall safe "+str(index)+":"+str(segment))
		var enemy: Dictionary=game._spawn_enemy("raider",2,{"pathIndex":index})
		check(enemy.position.distance_to(path.points[0])<.000005 and int(enemy.pathIndex)==index and int(enemy.spawnPathIndex)==index,tag+" starts at OWN route entry "+str(index))
		check(not game._sailing_visual(enemy),tag+" dry ordinary route has no boat")
	game.enemies.clear()
	for zone in game.zones:
		var role=str(zone.placementRole)
		var kind="archer" if role=="ranged" else "ninja" if role=="ambush" else "gunner"
		var center: Vector2=zone.position
		check(not game._eligible_zone(center,kind).is_empty(),tag+" advertised zone CENTER eligible "+str(zone.id))
		check(game._zone_placement_hint(zone,kind).x>=0,tag+" advertised zone has real placement "+str(zone.id))
	for key in ["id","stageNumber","theme","tier","difficulty","totalWaves","initialGold","recruitCost","unitLimit","music","escortRoute","water","waterPolygons"]:
		check(stage.get(key)==original.get(key),tag+" preserves non-route field "+key)
	# Obstacle relocation is a separate root review, not implied by runtime success.
	var old_obstacles: Array=original.get("obstacles",[])
	var new_obstacles: Array=stage.get("obstacles",[])
	if old_obstacles!=new_obstacles:
		var normalized: Array=old_obstacles.duplicate(true)
		if normalized.size()==new_obstacles.size():
			for n in range(normalized.size()):
				for coordinate in ["x","y"]: normalized[n][coordinate]=new_obstacles[n].get(coordinate)
		obstacle_comparisons.append({"stageId":tag,"stageNumber":stage.stageNumber,"coordinatesOnly":normalized==new_obstacles,"baseline":old_obstacles,"candidate":new_obstacles,"status":"ROOT_REVIEW_REQUIRED"})
	for key in ["eventId","locationId","sourceUrls","season","weatherKnown","weather","historySummaryKo","timeOfDay","timeOfDayKnown"]:
		check(stage.historicalBattlefield.get(key)==original.historicalBattlefield.get(key),tag+" preserves history "+key)
func parallel_production(stage: Dictionary) -> void:
	var game=make_game(stage)
	game.gold=10000
	var tag=str(stage.id)
	var cost=0
	for kind in TYPES:
		check(game.begin_placement(kind,0),tag+" public class order "+kind)
		if kind not in MARCHING:
			var point=hint(game,kind)
			check(point.x>=0,tag+" reservable public terrain "+kind)
			if point.x>=0: check(game.place_unit(point.x,point.y),tag+" public placement order "+kind)
		if not game.recruitment_queue.is_empty(): cost+=int(game.recruitment_queue[-1].cost)
	check(game.recruitment_queue.size()==8 and game.units.is_empty(),tag+" all eight public classes parallel queued")
	check(game.gold==10000-cost,tag+" exact real class costs paid once")
	game.advance_simulation(20)
	check(game.units.is_empty() and game.recruitment_queue.size()==8,tag+" production remains frozen before battle")
	hold(game)
	for tick in range(320):
		if game.recruitment_queue.is_empty(): break
		game.advance_simulation(.025)
	check(game.recruitment_queue.is_empty() and game.units.size()==8,tag+" eight real parallel actors complete on simulation clock")
	var seen={}
	for unit in game.units:
		seen[unit.type]=true
		check(game.ground_combat.land_segment_safe(unit.position,unit.position,.002),tag+" produced actor on land "+str(unit.type))
	check(seen.size()==8,tag+" all eight original classes produced")
	game.free()
func march_every_route(stage: Dictionary) -> void:
	for index in range(stage.paths.size()):
		var game=make_game(stage)
		game.gold=10000
		for kind in MARCHING: check(game.begin_placement(kind,index),str(stage.id)+" dispatch "+kind+" own route "+str(index))
		hold(game)
		for tick in range(320):
			if game.recruitment_queue.is_empty(): break
			game.advance_simulation(.025)
		check(game.units.size()==3,str(stage.id)+" own route produces all marching classes")
		var reached=false
		for tick in range(3200):
			var before=[]
			for unit in game.units: before.append({"distance":float(unit.routeDistance),"position":unit.position})
			game.ground_combat.step(.025)
			reached=true
			for n in range(game.units.size()):
				var unit: Dictionary=game.units[n]
				var label=str(stage.id)+"/"+str(index)+"/"+str(unit.type)
				check(int(unit.postPathIndex)==index and float(unit.routeDistance)<=before[n].distance+.000001,label+" route locked without backward trip")
				check(game.ground_combat.land_segment_safe(before[n].position,unit.position,.002),label+" actual frame land/wall safe")
				var center: Vector2=game.ground_combat.route_point(index,float(unit.routeDistance))
				check(center.distance_to(unit.position)<=.00901,label+" own route only, no cross-route chase")
				if float(unit.routeDistance)>float(unit.routeMin)+.0001: reached=false
				samples+=1
			if reached: break
		check(reached,str(stage.id)+" all three march to their own enemy end within bounded time "+str(index))
		game.free()
func ingress(game: Node2D,stage: Dictionary,original: Dictionary) -> void:
	for authored in stage.get("sideAmbushEntrances",[]):
		var index=int(authored.pathIndex)
		# Isolate each authored entrance so random selection cannot hide a bad candidate.
		var saved: Array=game.config.sideAmbushEntrances
		game.config.sideAmbushEntrances=[authored]
		var entry: Dictionary=game._prepared_ambush_entry(index)
		game.config.sideAmbushEntrances=saved
		var tag=str(stage.id)+"/"+str(authored.id)
		check(not entry.is_empty(),tag+" actual prepared ingress accepts authored route")
		if entry.is_empty(): continue
		hunters+=1
		var waterborne=str(entry.get("transportKind",""))=="boat"
		var enemy: Dictionary=game._spawn_enemy("enemy_samurai",2,{"pathIndex":index,"ambushEntry":entry})
		var departure: Vector2=entry.transportPoints[0] if waterborne else entry.points[0]
		check(enemy.position.distance_to(departure)<.000005 and int(enemy.pathIndex)==index,tag+" hunter departs its enemy camp/dock without teleport")
		if waterborne:
			boats+=1
			var old={}
			for value in original.get("sideAmbushEntrances",[]):
				if value.id==authored.id: old=value
			check(authored.transportPoints==old.get("transportPoints") and authored.get("enemyDeparturePoint")==old.get("enemyDeparturePoint"),tag+" original boat transit/dock preserved")
			check(entry.transportPoints[-1].distance_to(entry.points[0])<.000005,tag+" boat lands exactly at dry ingress start")
		else: check(entry.points[0].distance_to(game.paths[index].points[0])<.000005,tag+" land detachment starts at OWN main enemy camp")
		var joined=false
		var landed=not waterborne
		for tick in range(3200):
			var before: Vector2=enemy.position
			var transporting=bool(enemy.get("transportActive",false))
			game.elapsed+=.05
			game._move_enemy(enemy,.05)
			check(int(enemy.pathIndex)==index and not bool(enemy.get("escaped",false)),tag+" ingress route fixed, no premature escape")
			check(before.distance_to(enemy.position)<.02,tag+" finite physical step without teleport")
			if not transporting: check(game.ground_combat.land_segment_safe(before,enemy.position,.002),tag+" ingress actual movement land/wall safe")
			if transporting and not bool(enemy.get("transportActive",false)):
				landed=true
				check(enemy.position.distance_to(entry.points[0])<.000005,tag+" actual transport finishes at authored landing")
			if not bool(enemy.get("transportActive",false)) and not bool(enemy.get("ingressActive",false)):
				joined=true
				break
		check(joined and landed,tag+" finite transport/ingress reaches its own main road")
		check(enemy.position.distance_to(game.ground_combat.route_point(index,float(entry.joinDistance)))<.001,tag+" actual join is on own route")
		game.enemies.clear()
func learning(game: Node2D,stage: Dictionary,draft: Dictionary,original: Dictionary) -> void:
	var normalized=original.duplicate(true)
	for i in range(draft.missions.size()):
		var mission: Dictionary=draft.missions[i]
		for n in range(mission.targets.size()):
			var target: Dictionary=mission.targets[n]
			normalized.missions[i].targets[n].position=target.position
			var zone={}
			for value in stage.buildZones:
				if game._point(value).distance_to(game._point(target.position))<.000005: zone=value
			check(not zone.is_empty() and game._point(zone).distance_to(game._point(target.position))<.000005,str(mission.id)+" target coordinate bound to actual B zone "+str(target.id))
			check(game.ground_combat.land_segment_safe(game._point(target.position),game._point(target.position),.002),str(mission.id)+" support point is dry and outside walls")
		if mission.action.has("position"):
			normalized.missions[i].action.position=mission.action.position
			var anchor=stage.historicalBattlefield.get("learningSupportAnchors",{}).get(mission.id,mission.action.position)
			check(game._point(anchor).distance_to(game._point(mission.action.position))<.000005,str(mission.id)+" historical support anchor bound to action")
	check(normalized==draft,str(stage.id)+" learning content/answers/voice/report unchanged except coordinates")
func shared_contact(game: Node2D,stage: Dictionary) -> void:
	for own in range(game.paths.size()):
		for other in range(own+1,game.paths.size()):
			var found=false
			for i in range(game.paths[own].points.size()-1):
				var start: Vector2=game.paths[own].points[i]
				var end: Vector2=game.paths[own].points[i+1]
				if start.distance_to(end)<.014: continue
				var axis=(end-start).normalized()
				for j in range(game.paths[other].points.size()-1):
					var a: Vector2=game.paths[other].points[j]
					var b: Vector2=game.paths[other].points[j+1]
					if absf(axis.cross(a-start))>.000001 or absf(axis.cross(b-start))>.000001: continue
					var lo=maxf(0,minf((a-start).dot(axis),(b-start).dot(axis)))
					var hi=minf(start.distance_to(end),maxf((a-start).dot(axis),(b-start).dot(axis)))
					if hi-lo<.014: continue
					var mid=start+axis*(lo+hi)*.5
					var unit={"type":"spear","postPathIndex":own,"position":mid}
					var enemy={"pathIndex":other,"position":mid+axis*.001}
					var same_goal=game.paths[own].objectiveId==game.paths[other].objectiveId
					var dry=game.ground_combat.land_segment_safe(unit.position,enemy.position)
					check(game.ground_combat.shares_contact_front(unit,enemy)==(same_goal and dry),str(stage.id)+" actual shared road contact uses same objective and dry geometry "+str(own)+":"+str(other))
					contact_pairs+=1
					found=true
					break
				if found: break
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expected-maps-sha="): expected_sha=arg.trim_prefix("--expected-maps-sha=").to_lower()
		if arg=="--contact-only": contact_only=true
		if arg.begins_with("--candidate-profile="): candidate_profile=arg.trim_prefix("--candidate-profile=")
	var supplied_profile=candidate_profile.replace("\\","/")
	var normalized_profile=supplied_profile.simplify_path().trim_suffix("/")+"/"
	if not supplied_profile.is_absolute_path() or not normalized_profile.to_lower().begins_with("c:/jp_df/tests/profiles/") or not DirAccess.dir_exists_absolute(normalized_profile) or not safe_candidate_directory(normalized_profile):
		push_error("Candidate profile must be an existing absolute directory within C:/JP_DF/tests/profiles/")
		quit(2)
		return
	candidate_profile=normalized_profile
	var user_path=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not user_path.begins_with("c:/jp_df/tests/profiles/") or expected_sha.is_empty():
		push_error("Requires isolated profile and frozen --expected-maps-sha")
		quit(2)
		return
	var baseline_path=candidate_profile+"source-maps-baseline.json"
	if not FileAccess.file_exists(baseline_path): baseline_path=PROFILE+"source-maps-baseline.json"
	for input in [candidate_profile+"maps-balanced-draft.json",candidate_profile+"learning-plans-draft.json",baseline_path]:
		if not FileAccess.file_exists(input):
			push_error("Missing candidate input: "+input)
			quit(2)
			return
	maps_sha=sha(candidate_profile+"maps-balanced-draft.json")
	if maps_sha!=expected_sha:
		push_error("Candidate SHA mismatch; runtime not executed")
		quit(2)
		return
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string(candidate_profile+"maps-balanced-draft.json"))
	var baseline: Array=JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	var draft: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(candidate_profile+"learning-plans-draft.json"))
	var plans: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	check(maps.size()==40,"exact forty candidate stages")
	for i in range(maps.size()):
		var stage: Dictionary=maps[i]
		var game=make_game(stage)
		if contact_only:
			shared_contact(game,stage)
			game.free()
			continue
		geometry(game,stage,baseline[i])
		ingress(game,stage,baseline[i])
		learning(game,stage,draft.stages[stage.id],plans.stages[stage.id])
		game.free()
		parallel_production(stage)
		march_every_route(stage)
		rows.append({"stageId":stage.id,"pathCount":stage.paths.size()})
		print("BALANCED_STAGE ",str(stage.stageNumber)," checks=",checks," failures=",failures.size())
	if not contact_only: check(hunters==103 and boats==3,"all 103 authored hunters and three original boat routes exercised")
	check(sha(candidate_profile+"maps-balanced-draft.json")==maps_sha,"candidate unchanged during test")
	var report={"checks":checks,"failures":failures,"candidateProfile":candidate_profile,"candidateStatus":"NOT_ADOPTED","baselinePath":baseline_path,"mapsSha":maps_sha,"learningPlansSha":sha(candidate_profile+"learning-plans-draft.json"),"gameSha":sha("res://native/game.gd"),"groundSha":sha("res://native/ground_combat.gd"),"stages":rows,"marchSamples":samples,"hunterEntrances":hunters,"boatRoutes":boats,"actualSharedContactPairs":contact_pairs,"obstacleReview":{"changedStageCount":obstacle_comparisons.size(),"requiresRootReview":not obstacle_comparisons.is_empty(),"changes":obstacle_comparisons},"scope":"CPU game contracts only. Obstacle relocation and road artwork naturalness require separate review. No common inlet/fork requirement; all movement uses each own authored route."}
	var output=FileAccess.open(candidate_profile+("balanced-contact-report.json" if contact_only else "balanced-runtime-report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("BALANCED_ROUTES_RESULT checks=",checks," failures=",failures.size()," sha=",maps_sha)
	quit(0 if failures.is_empty() else 1)
