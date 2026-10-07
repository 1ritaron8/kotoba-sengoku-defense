extends SceneTree
## Check actual class-specific commits and matchlock movement/fire, not copied formulas.
const Battle = preload("res://native/game.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","ninja","commander"]
var checks: int = 0
var failures: Array[String] = []
var observations: Dictionary = {}
var maps: Array = []
var catalog: Array = []
var events: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures.append(message)
		if failures.size()<=35: push_error("DEPLOYMENT_ROLES "+message)

func fixture() -> Dictionary:
	return {"id":"deployment-role-fixture","initialGold":10000,"unitLimit":14,"totalWaves":2,"difficulty":1.0,"paths":[{"objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"wall","x":.5,"y":.7,"r":.09,"elevation":1}],"tactics":{"groundPosts":[{"id":"route","nameKo":"검증 전선","pathIndex":0,"segmentIndex":0,"t":.5,"r":.12,"guardRadius":.18,"mobilityFactor":1.0,"capacityBonus":0}]}}

func make_game(stage: Dictionary = {}) -> Node2D:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,TYPES,{})
	game.load_map(fixture() if stage.is_empty() else stage)
	game.set_seed(71)
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	return game

func legal_point(game: Node2D, id: String) -> Vector2:
	for zone in game.zones:
		var point: Vector2=game._zone_placement_hint(zone,id)
		if point.x>=0: return point
	return Vector2(-1,-1)

func deploy(game: Node2D, id: String, requested: Vector2 = Vector2(-1,-1)) -> Dictionary:
	check(game.begin_placement(id),"Direct selection enters preview: "+id)
	var point: Vector2=legal_point(game,id) if requested.x<0 else requested
	check(point.x>=0 and game.place_unit(point.x,point.y),"A typed legal click commits: "+id)
	return game.units[-1] if not game.units.is_empty() else {}

func hold_wave(game: Node2D) -> void:
	game.start_battle()
	game.spawn_queue=["raider"]
	game.spawn_source_waves=[1]
	game.spawn_clock=100000.0

func enemy_at(game: Node2D, position: Vector2, hp: float = 1000.0, path_index: int = 0) -> Dictionary:
	game._spawn_enemy("raider")
	var enemy: Dictionary=game.enemies[-1]
	enemy["pathIndex"]=path_index
	enemy["pointIndex"]=1
	enemy["position"]=position
	enemy["hp"]=hp
	enemy["maxHp"]=hp
	enemy["speed"]=0.0
	return enemy

func simulate(game: Node2D, seconds: float) -> void:
	for index in range(int(round(seconds/.025))): game.advance_simulation(.025)

func point_from(value) -> Vector2:
	return value if value is Vector2 else Vector2(float(value.x),float(value.y))

func test_all_map_commits() -> void:
	var game: Node2D=make_game()
	var committed: int=0
	var role_counts: Dictionary={"fixed_emplacement":0,"frontline_shooter":0,"ground_frontline":0}
	for stage in maps:
		var original: String=JSON.stringify(stage)
		for id in TYPES:
			game.load_map(stage)
			var before_gold: int=game.gold
			var before_next_id: int=game.next_id
			var context: String=str(stage.id)+" "+str(id)
			check(game.begin_placement(str(id)),context+" can select with shipped stage funds")
			check(game.gold==before_gold and game.next_id==before_next_id,context+" preview has no payment or id allocation")
			var role: String="ranged" if id=="archer" else "ground"
			var mode: String="fixed_emplacement" if id=="archer" else "frontline_shooter" if id=="gunner" else "ground_frontline"
			var contract: Dictionary=game.placement_contract(str(id))
			check(str(contract.placementRole)==role and str(contract.placementMode)==mode,context+" exposes the actual deployment contract")
			for index in range(game.zones.size()):
				var zone: Dictionary=game.zones[index]
				if str(zone.placementRole)!=role:
					check(game.placement_hints[index].x<0 and game._zone_placement_hint(zone,str(id)).x<0,context+" cannot advertise a wrong-role slot")
			var point: Vector2=legal_point(game,str(id))
			check(point.x>=0,context+" has at least one reachable typed slot")
			if point.x<0:
				game.cancel_recruit()
				continue
			var preview: Dictionary=game.placement_preview(point)
			check(bool(preview.valid) and str(preview.placementRole)==role and str(preview.placementMode)==mode,context+" legal preview agrees with the unit role")
			var off_field: Vector2=Vector2(.99,.99)
			var invalid: Dictionary=game.placement_preview(off_field)
			check(not bool(invalid.valid) and str(invalid.reason)==str(contract.placementHintKo),context+" illegal terrain explains this class's required role")
			check(not game.place_unit(off_field.x,off_field.y) and game.gold==before_gold and game.next_id==before_next_id,context+" denied commit cannot consume money or an id")
			check(game.place_unit(point.x,point.y),context+" legal deployment succeeds")
			if game.units.is_empty(): continue
			var unit: Dictionary=game.units[0]
			var public: Dictionary=game._unit_public(unit)
			check(game.gold==before_gold-int(game.recruit_catalog[id].cost) and game.next_id==before_next_id+1,context+" commit pays once")
			check(str(public.placementMode)==mode and str(public.placementRole)==role,context+" committed public data keeps the same role")
			check(point_from(preview.position).distance_to(unit.position)<.00001,context+" preview anchor is the committed anchor")
			if role=="ranged":
				check(not unit.has("postPathIndex") and not game._on_road(unit.position),context+" archer cannot take the road or mobile combat state")
			else:
				check(unit.has("postPathIndex") and float(unit.elevation)==0 and float(unit.maxHp)>0,context+" frontline has a land-route home, health and no wall elevation")
				check(unit.position.distance_to(game.ground_combat.route_point(int(unit.postPathIndex),float(unit.homeDistance)))<.00001,context+" frontline feet lie on the assigned enemy route")
			committed+=1
			role_counts[mode]=int(role_counts[mode])+1
		check(JSON.stringify(stage)==original,str(stage.id)+" load/placement preserves its unique map definition")
	game.free()
	check(committed==320,"All forty stages accept each of the eight classes at role-specific positions")
	observations["mapCommits"]=committed
	observations["placementModes"]=role_counts

func test_starting_army_and_eight_classes() -> void:
	var game: Node2D=make_game(maps[0])
	game.configure_roster(catalog,["archer","spear"],{})
	var shipped_gold: int=game.gold
	deploy(game,"archer")
	deploy(game,"spear")
	check(game.units.size()==2 and game.gold==shipped_gold-125,"First stage deploys its Lv1 starter archer and spear with shipped funds")
	check(not game.begin_placement("gunner"),"A fresh campaign still requires the gunner's real unlock")
	game.free()
	game=make_game(maps[0])
	game.gold=10000 # Space fixture only; this does not validate campaign economy.
	for id in TYPES: deploy(game,str(id))
	check(game.units.size()==8,"Eight classes fit the first map after the gunner moves to the frontline")
	for a in range(game.units.size()):
		for b in range(a):
			check(game._reserved_position(game.units[a]).distance_to(game._reserved_position(game.units[b]))>=.052,"Distinct role-specific deployment homes do not overlap")
	game.free()

func test_fixed_archer() -> void:
	var game: Node2D=make_game()
	var unit: Dictionary=deploy(game,"archer")
	var home: Vector2=unit.position
	hold_wave(game)
	var enemy: Dictionary=enemy_at(game,Vector2(.5,.5))
	simulate(game,4.0)
	check(unit.position==home,"Archer stays at its chosen emplacement throughout live fire")
	check(float(enemy.hp)<1000,"Fixed archer still launches real arrows and causes damage")
	check(not unit.has("routeDistance") and str(unit.combatRole)=="ranged","Archer never receives an enemy-route movement controller")
	game.free()

func test_frontline_matchlock() -> void:
	var game: Node2D=make_game()
	var unit: Dictionary=deploy(game,"gunner")
	var home: Vector2=unit.position
	hold_wave(game)
	var enemy: Dictionary=enemy_at(game,Vector2(.335,.5))
	var advancing_frames: int=0
	var planted_attacks: int=0
	var max_displacement: float=0.0
	var moving_shots: int=0
	var projectile_seen: bool=false
	events.clear()
	for index in range(160):
		var before: Vector2=unit.position
		var before_events: int=events.size()
		game.advance_simulation(.025)
		var moved: bool=unit.position.distance_to(before)>.000001
		max_displacement=maxf(max_displacement,unit.position.distance_to(home))
		if str(unit.animation)=="walk": advancing_frames+=1
		if str(unit.animation)=="attack":
			planted_attacks+=1
			check(not moved,"Matchlock plants its feet for every observed firing-animation frame")
		for event in events.slice(before_events):
			if str(event.get("action",""))=="shot" and str(event.get("unitType",""))=="gunner" and moved: moving_shots+=1
		if not game.projectiles.is_empty(): projectile_seen=true
		check(unit.position.distance_to(game.ground_combat.route_point(int(unit.postPathIndex),float(unit.routeDistance)))<.00001,"Matchlock approach/fire remains on its bounded enemy route")
	check(advancing_frames>0 and max_displacement>.025,"Matchlock actually approaches from its route home to close firing range")
	check(planted_attacks>0 and projectile_seen and float(enemy.hp)<1000,"Matchlock stops, plays its firing animation, launches a bullet and damages the target")
	check(moving_shots==0,"No matchlock shot is released during route movement")
	check(float(game._stats(unit).range)<float(game.recruit_catalog.archer.range),"Lv1 matchlock's live firing range is shorter than the archer's")
	check(str(game._unit_public(unit).combatRole)=="frontline_shooter","Public matchlock role is a frontline shooter")
	var before_pause: Dictionary=unit.duplicate(true)
	var shots_before: int=game.projectiles.size()
	game.paused=true
	game.advance_simulation(3.0)
	check(unit==before_pause and game.projectiles.size()==shots_before,"Pause freezes matchlock position, firing, recovery and projectiles")
	game.paused=false
	game.enemies.clear()
	game.projectiles.clear()
	simulate(game,3.0)
	check(unit.position.distance_to(home)<.0002 and str(unit.combatState)=="guard","Lost matchlock target causes physical return to the reserved home")
	observations["matchlock"]={"advanceFrames":advancing_frames,"plantedAttackFrames":planted_attacks,"movement":max_displacement,"projectileObserved":projectile_seen,"movingShots":moving_shots}
	game.free()

func test_support_and_counterattack() -> void:
	var game: Node2D=make_game()
	var spear: Dictionary=deploy(game,"spear",Vector2(.46,.5))
	var gunner: Dictionary=deploy(game,"gunner",Vector2(.54,.5))
	hold_wave(game)
	var enemy: Dictionary=enemy_at(game,Vector2(.445,.5))
	game.ground_combat.step(.001)
	check(int(enemy.blockedBy)==int(spear.id),"Spear physically holds an enemy on the same route")
	check(not game.ground_combat.attack_target(gunner).is_empty(),"Frontline gunner can support a target already blocked by allied infantry")
	events.clear()
	simulate(game,2.5)
	var gunner_shots: int=0
	for event in events:
		if str(event.get("action",""))=="shot" and str(event.get("unitType",""))=="gunner": gunner_shots+=1
	check(gunner_shots>0 and float(enemy.hp)<1000,"Gunner fires through its supported defender's close engagement")
	game.free()
	game=make_game()
	gunner=deploy(game,"gunner")
	var home: Vector2=gunner.homePosition
	hold_wave(game)
	enemy=enemy_at(game,Vector2(.52,.5))
	simulate(game,1.0)
	check(float(gunner.hp)<float(gunner.maxHp),"An enemy that reaches the gunner can counterattack its real frontline health")
	check(game.ground_combat.capacity(gunner)==1,"Matchlock last-line contact cannot inherit the spear's multi-enemy blocking")
	gunner.hp=1.0
	game.advance_simulation(.025)
	check(str(gunner.combatState)=="retreat" and int(enemy.blockedBy)<0 and gunner.attackPlan.is_empty(),"Wounded gunner retreats and releases pending fire and contact")
	game.enemies.clear()
	game.projectiles.clear()
	simulate(game,18.0)
	check(str(gunner.combatState)=="guard" and gunner.position.distance_to(home)<.0002,"Recovered gunner returns to its original frontline home")
	check(is_equal_approx(float(gunner.hp),float(gunner.maxHp)),"Gunfire unit recovery restores actual health")
	game.free()

func test_route_and_range_boundaries() -> void:
	var stage: Dictionary=fixture()
	stage.paths.append({"objectiveId":"main","points":[{"x":.05,"y":.51},{"x":.95,"y":.51}]})
	var game: Node2D=make_game(stage)
	var gunner: Dictionary=deploy(game,"gunner")
	hold_wave(game)
	var other: Dictionary=enemy_at(game,Vector2(.48,.51),1000,1)
	check(game.ground_combat.attack_target(gunner).is_empty(),"A gunner cannot capture a nearby parallel route assigned to another frontline")
	simulate(game,1.0)
	check(float(other.hp)==1000 and gunner.position==gunner.homePosition,"Wrong-route enemy does not trigger approach or gunfire")
	game.enemies.clear()
	var far: Dictionary=enemy_at(game,Vector2(.29,.5))
	simulate(game,1.0)
	check(float(far.hp)==1000 and gunner.position==gunner.homePosition,"Out-of-sector enemy cannot drag a gunner across the battlefield")
	game.enemies.clear()
	var target: Dictionary=enemy_at(game,Vector2(.40,.5))
	gunner["animation"]="attack"
	gunner["attackPlan"]={"targetId":int(target.id),"damage":63.0,"releaseTime":0.0}
	target["position"]=Vector2(.72,.5)
	game._advance_actor_animations(.025)
	check(game.projectiles.is_empty() and float(target.hp)==1000,"A target leaving firing range before release causes no stale long-range shot")
	game.free()
	var bounded_posts: int=0
	for map in maps:
		if str(map.theme) not in ["harbor","convoy"]: continue
		game=make_game(map)
		game.gold=10000
		for zone in game.zones:
			if str(zone.placementRole)!="ground": continue
			# Each route-boundary probe stands alone. A prior probe deliberately
			# ends at its route edge, which may occupy this next post's footprint.
			game.units.clear()
			var point: Vector2=game._zone_placement_hint(zone,"gunner")
			if point.x<0: continue
			gunner=deploy(game,"gunner",point)
			game.ground_combat._walk(gunner,-100.0,100.0)
			check(float(gunner.routeDistance)>=float(gunner.routeMin)-.00001,str(map.id)+" matchlock cannot pursue into landing water")
			game.ground_combat._walk(gunner,100.0,100.0)
			check(float(gunner.routeDistance)<=float(gunner.routeMax)+.00001,str(map.id)+" matchlock cannot chase the moving-objective segment")
			check(gunner.position.distance_to(game.ground_combat.route_point(int(gunner.postPathIndex),float(gunner.routeDistance)))<.00001,str(map.id)+" matchlock stays on its authored land route")
			bounded_posts+=1
		game.free()
	check(bounded_posts>0,"Marine and convoy tests exercise actual authored matchlock posts")
	observations["boundedMatchlockPosts"]=bounded_posts

func test_training_health() -> void:
	var game: Node2D=make_game()
	var gunner: Dictionary=deploy(game,"gunner")
	game.free()

func run() -> void:
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	check(maps.size()==40 and catalog.size()==8,"Shipped forty maps and eight classes remain available")
	test_all_map_commits()
	test_starting_army_and_eight_classes()
	test_fixed_archer()
	test_frontline_matchlock()
	test_support_and_counterattack()
	test_route_and_range_boundaries()
	test_training_health()
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"scope":"Observable selection, role-specific legal/denied placement, one payment and actor id per commit for all 40 maps and 8 classes; shipped starter affordability; archer fixed live firing; matchlock bounded approach, planted gunfire, real bullets, same-route infantry support, close counterattack, retreat/recovery/return, pause, range and parallel-route boundaries, upgrade and merge health."}
	var output_path: String="user://qa_deployment_roles.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_deployment_roles.json"
	var output: FileAccess=FileAccess.open(output_path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("DEPLOYMENT_ROLES_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
