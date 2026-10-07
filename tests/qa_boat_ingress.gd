extends "res://tests/qa_hunter_ingress.gd"
## Inland boat arrival is transport, followed by the existing ground ingress.

func _init() -> void:
	for kind in ["enemy_samurai","enemy_archer","enemy_gunner"]: _boat_case(kind)
	_invalid_transport()
	_actual_inland_maps()
	_actual_departure_contracts()
	_phase_visibility()
	for failure in failures: push_error(failure)
	print("Boat ingress QA: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _boat_game() -> Node2D:
	var game: Node2D = _game()
	game.config.theme = "river"
	game.running = true
	game.config.water = {"x":.02,"y":.19,"w":.22,"h":.10}
	game.config.sideAmbushEntrances = [{"id":"enemy-river-dock","pathIndex":0,"point":{"x":.28,"y":.25},"connectionPoints":[{"x":.4,"y":.25},{"x":.4,"y":.55},{"x":.65,"y":.55}],"transportKind":"boat","transportPoints":[{"x":.06,"y":.25},{"x":.18,"y":.25},{"x":.28,"y":.25}]}]
	game.ground_combat.reset()
	return game

func _boat_case(kind: String) -> void:
	var game: Node2D = _boat_game()
	var shooter: Dictionary = _shooter(101,Vector2(.38,.38))
	game.units = [shooter]
	var entry: Dictionary = game._prepared_ambush_entry(0)
	check(not entry.is_empty() and str(entry.get("transportKind","")) == "boat",kind+": real prepared entry retains boat contract")
	check(entry.get("transportPoints",[]).size() == 3,kind+": transport dictionaries normalize into three route points")
	var enemy: Dictionary = game._spawn_enemy(kind,1,{"ambushEntry":entry})
	check(enemy.position.distance_to(Vector2(.06,.25)) < .00001,kind+": appears at authored enemy dock")
	check(bool(enemy.get("transportActive",false)) and game._sailing_visual(enemy),kind+": inland river boat renders without legacy harbor theme")
	check(int(enemy.get("stationaryTargetId",-1)) == -1,kind+": boat crew cannot acquire a ground emplacement at spawn")
	var state: Dictionary = {}
	game.units.clear()
	for record in game.snapshot().enemies:
		if int(record.id) == int(enemy.id): state = record
	check(bool(state.get("transportActive",false)) and str(state.get("transportKind","")) == "boat" and str(state.get("hunterState","")) == "transport",kind+": public snapshot exposes transport phase")
	var actor: Dictionary = game.actor_states()[0]
	check(bool(actor.sailing) and bool(actor.get("transportActive",false)),kind+": renderer receives active boat flag")
	game.units = [shooter]
	var guard: Dictionary = _shooter(102,enemy.position,"naginata")
	game.units.append(guard)
	enemy["blockedBy"] = 102
	var boat_origin: Vector2 = enemy.position
	_tick(game,enemy)
	check(enemy.position != boat_origin and int(enemy.blockedBy) == -1,kind+": ground guard cannot block a boat route")
	check(enemy.get("counterPlan",{}).is_empty() and enemy.get("rangedPlan",{}).is_empty(),kind+": boat crew cannot retaliate or shoot ground troops")
	check(game._hunter_target(enemy,.05).is_empty(),kind+": boat crew cannot acquire ground target mid-crossing")
	# A real archer can choose and hit the crew; ground gunners and melee
	# retain their existing sailing exclusions. Transport grants no immunity.
	var archer: Dictionary = _shooter(103,Vector2(.14,.16))
	archer.merge({"name":"궁병","jp":"弓兵","reading":"きゅうへい","cooldown":0.0,"attackPlan":{}},true)
	game.units = [archer]
	game._update_units(.05)
	check(int(archer.get("attackPlan",{}).get("targetId",-1)) == int(enemy.id),kind+": archer acquires a sailing crew at actual range")
	if not archer.attackPlan.is_empty(): game._release_unit_attack(archer,archer.attackPlan)
	check(not game.projectiles.is_empty(),kind+": archer releases actual projectile toward boat")
	var before_hp: float = float(enemy.hp)
	for i in range(20): game._update_projectiles(.05)
	check(float(enemy.hp) < before_hp,kind+": projectile applies real damage during transport")
	var gunner: Dictionary = _shooter(104,Vector2(.14,.16),"gunner")
	game.units = [gunner]
	check(game.ground_combat.attack_target(gunner).is_empty(),kind+": ground-line gunner retains sailing exclusion")
	game.units = [shooter]
	var transport_indices: int = int(enemy.transportIndex)
	for i in range(500):
		_tick(game,enemy)
		check(int(enemy.transportIndex) >= transport_indices,kind+": transport points advance monotonically")
		transport_indices = int(enemy.transportIndex)
		check(not bool(enemy.get("escaped",false)),kind+": boat phase cannot escape through the main objective")
		if not bool(enemy.transportActive): break
	check(not bool(enemy.transportActive),kind+": transport completes within finite time")
	check(enemy.position.distance_to(Vector2(.28,.25)) < .00001 and bool(enemy.ingressActive),kind+": landing preserves the separate ground ingress")
	check(not game._sailing_visual(enemy),kind+": inland boat rendering ends exactly at landing")
	check(game.ground_combat.land_segment_safe(enemy.position,enemy.position,.002),kind+": crew disembarks on actual safe ground")
	var attacked: bool = false
	for i in range(800):
		var previous: Vector2 = enemy.position
		_tick(game,enemy)
		check(game.ground_combat.land_segment_safe(previous,enemy.position,.002),kind+": post-landing ingress respects actual land geometry")
		if not enemy.get("counterPlan",{}).is_empty() or not enemy.get("rangedPlan",{}).is_empty(): attacked = true;break
	check(attacked,kind+": crew resumes actual emplacement attack after landing")
	game.free()

func _invalid_transport() -> void:
	var game: Node2D = _boat_game()
	game.config.sideAmbushEntrances[0].transportPoints[-1] = {"x":.3,"y":.25}
	check(game._prepared_ambush_entry(0).is_empty(),"Boat candidate with disconnected landing cannot enter production")
	game.config.sideAmbushEntrances[0].transportPoints = [{"x":.06,"y":.25},{"x":-1,"y":.25},{"x":.28,"y":.25}]
	check(game._prepared_ambush_entry(0).is_empty(),"Non-normalized transport point cannot enter production")
	game.free()

func _actual_inland_maps() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	for number in [9,12,39]:
		var stage: Dictionary = maps[number-1]
		var game: Node2D = Game.new()
		root.add_child(game)
		game.set_process(false)
		game.load_map(stage)
		game.units.clear()
		game.enemies.clear()
		var entry: Dictionary = game._prepared_ambush_entry(0)
		check(not entry.is_empty() and str(entry.get("transportKind","")) == "boat","actual stage %d prepares its authored boat route" % number)
		if entry.is_empty(): game.free();continue
		var points: Array = entry.transportPoints
		check(points.size() == 4,"actual stage %d preserves four transport points" % number)
		var authored: Dictionary = stage.sideAmbushEntrances[0]
		check(points[0].distance_to(game._point(authored.enemyDeparturePoint)) < .00001,"actual stage %d starts at authored enemy river dock" % number)
		game._queue_enemy_spawn("enemy_samurai",1,{"pathIndex":0,"ambushEntry":entry})
		check(game.ambush_warnings.size() == 1 and game.ambush_warnings[0].position.distance_to(points[0]) < .00001,"actual stage %d warns at departure rather than landing" % number)
		game._advance_ambush_warnings(2.01)
		check(game.enemies.size() == 1,"actual stage %d produces one boat crew after actual departure delay" % number)
		if game.enemies.is_empty(): game.free();continue
		var enemy: Dictionary = game.enemies[0]
		check(bool(enemy.get("transportActive",false)),"actual stage %d starts in transport phase" % number)
		for i in range(1600):
			_tick(game,enemy)
			check(not bool(enemy.get("escaped",false)),"actual stage %d boat does not enter main-route escape" % number)
			if not bool(enemy.transportActive): break
		check(not bool(enemy.transportActive) and enemy.position.distance_to(entry.points[0]) < .00001,"actual stage %d lands exactly at connected ingress start" % number)
		check(game.ground_combat.land_segment_safe(enemy.position,enemy.position,.002),"actual stage %d landing is actually land-safe" % number)
		for i in range(2200):
			var previous: Vector2 = enemy.position
			_tick(game,enemy)
			check(game.ground_combat.land_segment_safe(previous,enemy.position,.002),"actual stage %d ground ingress never crosses water/obstacles" % number)
			if not bool(enemy.ingressActive): break
		check(not bool(enemy.ingressActive),"actual stage %d ground ingress completes within bounded time" % number)
		check(enemy.position.distance_to(entry.points[-1]) < .00001,"actual stage %d no-target crew joins authored main-route point" % number)
		game.free()

func _actual_departure_contracts() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var entries: int = 0
	for stage in maps:
		var game: Node2D = Game.new()
		root.add_child(game)
		game.set_process(false)
		game.load_map(stage)
		for authored in stage.sideAmbushEntrances:
			var entry: Dictionary = game._prepared_ambush_entry(int(authored.pathIndex))
			check(not entry.is_empty(),str(stage.id)+" prepares its real enemy-departure route "+str(authored.id))
			if entry.is_empty(): continue
			entries += 1
			for i in range(entry.points.size()-1):
				check(game.ground_combat.land_segment_safe(entry.points[i],entry.points[i+1],.002),str(stage.id)+" departure corridor segment remains actual land-safe")
			if str(entry.get("transportKind","")) != "boat":
				check(entry.points[0].distance_to(game.paths[int(entry.pathIndex)].points[0]) < .00001,str(stage.id)+" land detachment starts at its main enemy camp")
			else:
				check(entry.transportPoints[-1].distance_to(entry.points[0]) < .00001,str(stage.id)+" boat landing connects to actual ground corridor")
		game.free()
	check(entries == 103,"All 103 actual enemy-departure approaches prepare successfully")
	print("Actual enemy-departure corridors verified: ",entries)

func _phase_visibility() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	for number in [9,15,20,36,39]:
		var game: Node2D = _game()
		game.config = maps[number-1].duplicate(true)
		game.units.clear()
		game.objectives.clear()
		game.config["torches"] = []
		var enemy: Dictionary = {"position":Vector2(.5,.1)}
		var is_night: bool = number in [15,20,36]
		check(game._enemy_visible(enemy) != is_night,"Actual stage %d visibility uses selected day/night phase" % number)
		if is_night:
			game.config.torches = [{"x":.5,"y":.1}]
			check(game._enemy_visible(enemy),"Actual stage %d torch still reveals a night opponent" % number)
			game.config.torches.clear()
			game.units = [_shooter(201,Vector2(.5,.15))]
			check(game._enemy_visible(enemy),"Actual stage %d nearby troops still reveal a night opponent" % number)
		game.free()
	var fallback: Node2D = _game()
	fallback.objectives.clear()
	fallback.config.historicalBattlefield = {"timeOfDay":"night"}
	check(not fallback._enemy_visible({"position":Vector2(.5,.1)}),"Historical time-of-day fallback keeps explicit night visibility")
	fallback.config.historicalBattlefield.presentationWeather = {"timeOfDay":"day"}
	check(fallback._enemy_visible({"position":Vector2(.5,.1)}),"Explicit selected daytime overrides an older night theme/phase")
	fallback.free()
