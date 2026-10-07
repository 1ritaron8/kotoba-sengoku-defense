extends "res://tests/qa_marching_contracts.gd"
## Read-only critic fixture: observation, not a claim that cross-front combat passes.
func run() -> void:
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var stage: Dictionary=fixture()
	stage.paths[0].points=[{"x":.05,"y":.5},{"x":.65,"y":.5},{"x":.95,"y":.5}]
	stage.paths[1].points=[{"x":.05,"y":.2},{"x":.65,"y":.5},{"x":.95,"y":.5}]
	var game: Node2D=make_game(stage,10)
	game.begin_placement("spear",0)
	await_production(game)
	var unit: Dictionary=game.units[0]
	unit.position=Vector2(.85,.5)
	unit.routeDistance=game.ground_combat.point_distance(0,1,unit.position)
	unit.combatState="march"
	var enemy: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":1})
	enemy.position=Vector2(.845,.5)
	enemy.pointIndex=2
	game.enemies=[enemy]
	var results: Array=[]
	for path_index in [1,0]:
		enemy.pathIndex=path_index
		enemy.blockedBy=-1
		game.ground_combat._assign_blocks()
		results.append({"enemyPath":path_index,"unitPath":unit.postPathIndex,"physicalDistance":enemy.position.distance_to(unit.position),"landSafe":game.ground_combat.land_segment_safe(unit.position,enemy.position),"nearestFound":not game.ground_combat._nearest_enemy(unit).is_empty(),"attackFound":not game.ground_combat.attack_target(unit).is_empty(),"assignedBlock":int(enemy.get("blockedBy",-1)),"blocked":game.ground_combat.blocked(enemy),"enemyCanContact":game.can_enemy_engage_unit(enemy,unit,true)})
	print("SHARED_FRONT_PROBE ",JSON.stringify(results))
	var output: FileAccess=FileAccess.open("user://qa_shared_front_probe.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(results,"  "))
	output.close()
	game.free()
	quit(0)
