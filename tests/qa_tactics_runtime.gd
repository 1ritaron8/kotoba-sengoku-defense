extends SceneTree
## Independent deployment and geographic-boundary checks against the actual game.
## Does not judge combat balance or infer walkable scenery from the background photo.

const Game = preload("res://native/game.gd")
const TYPES = ["archer","gunner","spear","samurai","naginata","monk","ninja","commander"]
const GROUND = ["spear","samurai","naginata","monk","ninja","commander"]
var game: Node2D
var checks: int = 0
var failures: Array = []
var failed_checks: int = 0
var observations: Array = []
var total_deployments: int = 0
var boundary_walks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed_checks += 1
		if not failures.has(message):
			failures.append(message)
			push_error("TACTICS RUNTIME QA "+message)

func role(unit_id: String) -> String:
	return "ground" if unit_id in GROUND else "ranged"

func hint() -> Vector2:
	for p in game.placement_hints:
		if p.x >= 0: return p
	return Vector2(-1,-1)

func on_route(p: Vector2, index: int) -> bool:
	var points: Array = game.paths[index].points
	for i in range(points.size()-1):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,points[i],points[i+1])) < 0.00002:
			return true
	return false

func water_rect(map: Dictionary) -> Rect2:
	var water: Dictionary = map.get("water",{})
	return Rect2(float(water.get("x",0)),float(water.get("y",0)),float(water.get("w",0)),float(water.get("h",0)))

func wrong_role_point(unit_id: String) -> Vector2:
	for zone in game.zones:
		if str(zone.placementRole) != role(unit_id) and game._eligible_zone(zone.position,unit_id).is_empty():
			return zone.position
	return Vector2(-1,-1)

func deploy(unit_id: String, context: String) -> Dictionary:
	var supply: int = game.gold
	check(game.recruit(unit_id),context+": selected class recruited")
	if game.pending.is_empty(): return {}
	var paid: int = int(game.pending.paid)
	check(str(game.pending.type)==unit_id,context+": class identity retained")
	check(supply-game.gold==paid,context+": recruitment debits supply once")
	var after_recruit: int = game.gold
	var wrong: Vector2 = wrong_role_point(unit_id)
	check(wrong.x>=0,context+": a separately classified incompatible position exists")
	if wrong.x>=0:
		check(not game.place_unit(wrong.x,wrong.y),context+": incompatible class position is rejected")
		check(game.gold==after_recruit and str(game.pending.get("type",""))==unit_id,context+": rejected click preserves supply and pending class")
	game._refresh_placement_hints()
	check(game.placement_hints.size()==game.zones.size(),context+": actual hint array preserves zone indexing")
	for i in range(game.placement_hints.size()):
		var p: Vector2 = game.placement_hints[i]
		if p.x>=0:
			check(str(game.zones[i].placementRole)==role(unit_id),context+": no hint enables an incompatible placement role")
	var p: Vector2 = hint()
	check(p.x>=0,context+": another physical deployment position exists")
	if p.x<0:
		game.cancel_recruit()
		return {}
	check(game.place_unit(p.x,p.y),context+": actual selected-class hint places successfully")
	if game.units.is_empty(): return {}
	var unit: Dictionary = game.units[-1]
	check(str(unit.type)==unit_id and game.pending.is_empty(),context+": placed class remains correct and pending is consumed")
	check(game.gold==after_recruit,context+": successful placement has no second debit")
	check(str(unit.get("combatRole",""))==("cavalry" if unit_id=="commander" else role(unit_id)),context+": field state exposes the correct combat role")
	if unit_id in GROUND:
		check(on_route(unit.position,int(unit.postPathIndex)),context+": ground position lies on its own actual route")
		check(float(unit.hp)>0 and float(unit.maxHp)>=float(unit.hp),context+": deployed defender has finite health")
		check(int(unit.elevation)==0,context+": ground deployment receives no ranged-wall elevation")
	total_deployments += 1
	return unit

func check_boundaries(map: Dictionary) -> void:
	if str(map.theme) not in ["harbor","convoy"]: return
	game.units.clear()
	for post in game.zones:
		if str(post.placementRole)!="ground": continue
		if str(map.theme)=="harbor":
			for ring in range(1,4):
				for step in range(24):
					var angle: float=TAU*float(step)/24.0
					var candidate: Vector2=post.position+Vector2(cos(angle),sin(angle))*float(post.r)*float(ring)/3.0
					var accepted: Dictionary=game._eligible_zone(candidate,"commander")
					if accepted.is_empty(): continue
					var final_point: Vector2=game._placement_position(candidate,accepted)
					check(not water_rect(map).has_point(final_point),str(map.id)+" "+str(post.id)+": accepted mounted placement circle remains outside mapped water")
		game.gold=100000
		check(game.recruit("commander"),str(map.id)+" "+str(post.id)+": mounted boundary fixture recruited")
		check(game.place_unit(post.position.x,post.position.y),str(map.id)+" "+str(post.id)+": actual authored post centre places")
		if game.units.is_empty(): continue
		var unit: Dictionary = game.units[-1]
		var home: Vector2 = unit.position
		for target in [-100.0,100.0]:
			game.ground_combat._walk(unit,target,1000.0)
			boundary_walks += 1
			check(on_route(unit.position,int(unit.postPathIndex)),str(map.id)+" "+str(post.id)+": movement extremum remains on its assigned route")
			if str(map.theme)=="harbor":
				check(not water_rect(map).has_point(unit.position),str(map.id)+" "+str(post.id)+": full guard movement remains outside mapped water")
			else:
				var path: Array = game.paths[int(unit.postPathIndex)].points
				var movable_begin: Vector2 = path[-2]
				var movable_end: Vector2 = path[-1]
				var distance: float = unit.position.distance_to(Geometry2D.get_closest_point_to_segment(unit.position,movable_begin,movable_end))
				check(distance>0.00001 or unit.position.distance_to(movable_begin)<0.00002,str(map.id)+" "+str(post.id)+": guard movement does not follow the moving-target segment")
		game.ground_combat._walk(unit,float(unit.homeDistance),1000.0)
		check(unit.position.distance_to(home)<0.00002,str(map.id)+" "+str(post.id)+": post home remains reachable after both movement bounds")
		game.units.clear()

func run() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var units: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	game=Game.new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.configure_roster(units.units,TYPES,{})
	for map in maps:
		game.load_map(map)
		game.gold=100000
		game.config.unitLimit=20
		check(game.zones.size()==map.buildZones.size()+map.tactics.groundPosts.size(),str(map.id)+": all original ranged zones and authored ground posts are loaded")
		for unit_id in TYPES:
			game.units.clear()
			game._refresh_placement_hints()
			deploy(unit_id,str(map.id)+" "+unit_id)
		check_boundaries(map)
	game.load_map(maps[0])
	game.gold=100000
	game.config.unitLimit=20
	for unit_id in TYPES:
		deploy(unit_id,"first-map simultaneous "+unit_id)
	check(game.units.size()==8,"First Basic forest physically accepts both ranged and all six ground classes simultaneously")
	for i in range(game.units.size()):
		for j in range(i+1,game.units.size()):
			check(game.units[i].position.distance_to(game.units[j].position)>=0.05199,"First-map actual eight-unit formation respects physical separation")
		observations.append({"unitId":str(game.units[i].type),"position":{"x":game.units[i].position.x,"y":game.units[i].position.y},"postId":game.units[i].get("postId","")})
	var result: Dictionary={"checks":checks,"failures":failures,"failedChecks":failed_checks,"maps":maps.size(),"deployments":total_deployments,"boundaryWalks":boundary_walks,"firstMap":observations,"resourceRoot":ProjectSettings.globalize_path("res://"),"limits":"Headless typed placement, supply preservation and geographic movement bounds only; combat balance and rendered legibility are verified separately."}
	var file=FileAccess.open("user://qa_tactics_runtime.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
