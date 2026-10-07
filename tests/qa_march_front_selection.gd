extends "res://tests/qa_marching_contracts.gd"
## Reuse actual production and all forty-map marching checks. No GPU/UI input.

func _pressure_enemy(game: Node2D, path_index: int, progress: float, role: String = "path_assault", fortified: bool = false) -> Dictionary:
	var total: float = float(game.ground_combat.cumulative[path_index][-1])
	var distance: float = total*progress
	var lengths: Array = game.ground_combat.cumulative[path_index]
	var index: int = 1
	for i in range(1,lengths.size()):
		index = i
		if distance <= float(lengths[i]): break
	return {"id":100+path_index,"kind":"raider","pathIndex":path_index,"pointIndex":index,"position":game.ground_combat.route_point(path_index,distance),"hp":100.0,"maxHp":100.0,"combatRole":role,"fortification":fortified}

func front_selection() -> void:
	var game: Node2D = make_game()
	game.enemies = [_pressure_enemy(game,0,.1),_pressure_enemy(game,1,.9)]
	check(int(game.ground_combat.select_march_base().pathIndex) == 1,"Near-base enemy front wins over distant equally healthy enemy")
	game.enemies = [_pressure_enemy(game,0,.1),_pressure_enemy(game,1,.9),_pressure_enemy(game,0,.1)]
	check(int(game.ground_combat.select_march_base().pathIndex) == 1,"Immediate near-base risk beats two remote enemies")
	game.recruitment_queue = [{"kind":"marching","pathIndex":1,"quantity":2}]
	check(int(game.ground_combat.select_march_base().pathIndex) == 0,"Two already-paid queued soldiers prevent excess dispatch to dangerous front")
	game.recruitment_queue.clear()
	game.units = [{"id":1,"type":"spear","hp":140.0,"postPathIndex":1},{"id":2,"type":"samurai","hp":175.0,"postPathIndex":1}]
	check(int(game.ground_combat.select_march_base().pathIndex) == 0,"Two living marching soldiers count toward front coverage")
	game.units[0].hp = 0.0
	game.units[1].hp = 0.0
	check(int(game.ground_combat.select_march_base().pathIndex) == 1,"Dead marching soldiers do not suppress reinforcement")
	game.units.clear()
	game.enemies = [_pressure_enemy(game,0,.1),_pressure_enemy(game,1,.99,"emplacement_assault"),_pressure_enemy(game,1,.99,"path_assault",true)]
	check(int(game.ground_combat.select_march_base().pathIndex) == 0,"Emplacement hunters and prepared fortifications cannot draw marching reinforcements")
	game.enemies = [_pressure_enemy(game,1,.99)]
	check(int(game.ground_combat.select_march_base(0).pathIndex) == 0,"Manual path selection retains its front despite higher threat elsewhere")
	check(game.ground_combat.select_march_base(99).is_empty(),"Invalid manual path remains rejected")
	game.units.clear()
	game.enemies.clear()
	game.recruitment_queue.clear()
	game.gold = 10000
	var reserved: Array = [0,0]
	for i in range(8):
		check(game.begin_placement("spear"),"Parallel paid automatic reservation accepted")
		reserved[int(game.recruitment_queue[-1].pathIndex)] += 1
	check(absi(int(reserved[0])-int(reserved[1])) <= 1,"Parallel paid reservations spread idle fronts before soldiers are born")
	game.free()

func land_and_path_lock() -> void:
	var samples: int = 0
	var commits: int = 0
	for stage in maps:
		var game: Node2D = make_game(stage)
		game.gold = 100000
		game.config.unitLimit = 100
		for path_index in range(game.paths.size()):
			for type_name in Marching:
				check(game.begin_placement(type_name,path_index),str(stage.id)+" actual multi-front order accepts "+str(type_name)+" on "+str(path_index))
		await_production(game)
		check(game.units.size() == game.paths.size()*3,str(stage.id)+" all three types finish actual parallel production on every front")
		commits += game.units.size()
		hold(game)
		simulate(game,3.0)
		var routes: Dictionary = {}
		var origins: Dictionary = {}
		for unit in game.units:
			routes[int(unit.id)] = int(unit.postPathIndex)
			origins[int(unit.id)] = float(unit.routeDistance)
		for tick in range(80):
			var prior: Dictionary = {}
			for unit in game.units: prior[int(unit.id)] = float(unit.routeDistance)
			game.advance_simulation(.025)
			for unit in game.units:
				var label: String = str(stage.id)+"/"+str(unit.type)+"/"+str(unit.postPathIndex)
				check(int(unit.postPathIndex) == int(routes[int(unit.id)]),label+" remains locked to its dispatched front")
				check(game.ground_combat.land_segment_safe(unit.position,unit.position,0),label+" physical feet remain on land outside blocking water")
				check(float(unit.routeDistance) <= float(prior[int(unit.id)])+.000001,label+" never reverses toward its friendly origin")
				check(str(unit.combatState) not in ["return","retreat","recover","charge_return"],label+" contains no retreat/repeated-return state")
				samples += 1
		for unit in game.units:
			check(float(unit.routeDistance) < float(origins[int(unit.id)])-.001,str(stage.id)+"/"+str(unit.type)+" genuinely progresses beyond its gathered base")
		game.free()
	observations["allFrontProductionCommits"] = commits
	observations["physicalLandAndPathSamples"] = samples

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if DisplayServer.get_name() != "headless" or not profile.begins_with(qa_project_path("tests/profiles/").to_lower()):
		quit(2)
		return
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	front_selection()
	role_and_routes()
	land_and_path_lock()
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"mapsSHA256":FileAccess.get_sha256("res://native/maps.json"),"groundSHA256":FileAccess.get_sha256("res://native/ground_combat.gd"),"scope":"CPU actual front selection/parallel paid reservations and all forty maps, every route and spear/samurai/commander: real production, locked front, land-safe feet, monotonic advance, no retreat or repeated return. No battle completion/GPU claim."}
	var output: FileAccess = FileAccess.open("user://qa_march_front_selection.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("MARCH_FRONT_SELECTION %d checks / %d failures; commits=%d; land/path samples=%d" % [checks,failures.size(),int(observations.get("allFrontProductionCommits",0)),int(observations.get("physicalLandAndPathSamples",0))])
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
