extends "res://tests/qa_marching_contracts.gd"
## Contact may cross a route ID only on a physically shared land segment.
func shared_fixture(variant: String) -> Dictionary:
	var stage: Dictionary=fixture()
	stage.paths[0].points=[{"x":.05,"y":.5},{"x":.65,"y":.5},{"x":.95,"y":.5}]
	stage.paths[1].points=[{"x":.05,"y":.2},{"x":.65,"y":.5},{"x":.80,"y":.5},{"x":.95,"y":.5}]
	if variant=="crossing": stage.paths[1].points=[{"x":.835,"y":.1},{"x":.835,"y":.7},{"x":.95,"y":.5}]
	if variant=="parallel": stage.paths[1].points=[{"x":.05,"y":.506},{"x":.90,"y":.506},{"x":.95,"y":.5}]
	if variant=="other_objective":
		stage.paths[1].objectiveId="second"
		stage.objectives.append({"id":"second","x":.95,"y":.5,"hp":100})
	return stage

func contact_case(kind: String, variant: String) -> void:
	var game: Node2D=make_game(shared_fixture(variant),10)
	check(game.begin_placement(kind,0),kind+" "+variant+" production succeeds")
	await_production(game)
	var unit: Dictionary=game.units[0]
	unit.position=Vector2(.85,.5)
	unit.routeDistance=game.ground_combat.point_distance(0,1,unit.position)
	unit.combatState="march"
	unit.animation="idle"
	var own_path: int=int(unit.postPathIndex)
	var enemy: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":0 if variant=="same_route" else 1})
	enemy.position=Vector2(.835,.506 if variant=="parallel" else .5)
	enemy.pointIndex=2 if variant=="same_route" else 3 if variant in ["shared","water","other_objective"] else 1
	game.enemies=[enemy]
	if variant=="water": game.ground_combat.water_rects.append(Rect2(.841,.48,.004,.04))
	var allowed: bool=variant in ["shared","same_route"]
	var label: String=kind+" "+variant
	check(game.ground_combat.shares_contact_front(unit,enemy)==allowed,label+" physical front predicate")
	check(not game.ground_combat._nearest_enemy(unit).is_empty()==allowed,label+" acquisition")
	check(not game.ground_combat.attack_target(unit).is_empty()==allowed,label+" attack target")
	game.ground_combat._assign_blocks()
	check((int(enemy.get("blockedBy",-1))==int(unit.id))==allowed,label+" block assignment")
	check(game.ground_combat.blocked(enemy)==allowed,label+" persistent block")
	check(game.can_enemy_engage_unit(enemy,unit,true)==allowed,label+" enemy contact")
	if allowed:
		check(absf(game.ground_combat.enemy_distance_for_unit(unit,enemy)-.785)<.00001,label+" progress uses defender route despite different source length")
	var hp: float=float(enemy.hp)
	var plan: Dictionary=game.unit_skills.prepare_attack(unit,enemy,20.0,.1)
	game._release_unit_attack(unit,plan)
	check((float(enemy.hp)<hp)==allowed,label+" actual attack release applies or rejects damage")
	hp=float(unit.hp)
	game._damage_friendly(unit,7.0,enemy)
	check((float(unit.hp)<hp)==allowed,label+" enemy contact damage applies or rejects")
	for tick in range(20):
		var previous: float=float(unit.routeDistance)
		game.ground_combat._marching_step(unit,.025)
		check(int(unit.postPathIndex)==own_path and float(unit.routeDistance)<=previous+.000001,label+" route lock and monotonic forward movement")
	game.free()

func chase_case(kind: String) -> void:
	var game: Node2D=make_game(shared_fixture("shared"),10)
	game.begin_placement(kind,0)
	await_production(game)
	var unit: Dictionary=game.units[0]
	unit.campaignLevel=3 if kind=="commander" else 1
	unit.formationLane=1
	unit.position=Vector2(.85,.5)
	unit.routeDistance=.8
	unit.combatState="march"
	unit.animation="idle"
	var enemy: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":1})
	enemy.position=Vector2(.85-game.ground_combat.reach(unit)*1.02,.5)
	enemy.pointIndex=3
	game.enemies=[enemy]
	var origin: float=float(unit.routeDistance)
	var saw_charge: bool=false
	var saw_impact: bool=false
	for tick in range(40):
		var before: float=float(unit.routeDistance)
		game.ground_combat._marching_step(unit,.025)
		var center: Vector2=game.ground_combat.route_point(0,float(unit.routeDistance))
		check(int(unit.postPathIndex)==0 and float(unit.routeDistance)<=before+.000001,kind+" shared chase remains monotonic on its assigned route")
		check(unit.position.distance_to(center)<=.00901 and absf(unit.position.y-.5)<=.00901,kind+" chase/charge retains own-route formation position")
		saw_charge=saw_charge or str(unit.combatState)=="charge"
		saw_impact=saw_impact or str(unit.combatState)=="impact"
	check(float(unit.routeDistance)<origin-.0001,kind+" actually approaches the shared enemy using its own route projection")
	if kind=="commander": check(saw_charge and saw_impact and bool(unit.get("attackPlan",{}).get("charge",false)),"Actual unlocked cavalry charge/impact stays on its assigned shared route")
	# Once the enemy leaves the overlap, no chase continues into its branch.
	enemy.position=Vector2(.63,.49)
	enemy.pointIndex=1
	unit.animation="idle"
	unit.attackPlan={}
	game.ground_combat._marching_step(unit,.025)
	check(int(unit.targetId)==-1 and int(unit.postPathIndex)==0 and absf(unit.position.y-.5)<=.00901,kind+" target leaving shared section is released without branch chase")
	game.free()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/"):
		push_error("Shared-front QA requires isolated APPDATA")
		quit(2);return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	for kind in Marching:
		for variant in ["shared","crossing","parallel","water","other_objective","same_route"]: contact_case(kind,variant)
		chase_case(kind)
	combat_and_casualties()
	var report: Dictionary={"checks":checks,"failures":failures,"scope":"Three marching types × shared/point-crossing/near-parallel/water/different-objective/same-route; actual acquire, block, attack release, enemy damage and path-locked forward movement."}
	var output: FileAccess=FileAccess.open("user://qa_shared_front_contact.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("SHARED_FRONT_CONTACT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
