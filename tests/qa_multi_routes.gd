extends SceneTree
## Observes actual queued production and walking; never edits campaign data.
const Battle = preload("res://native/game.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var movement_rows: Array = []
var side_rows: Array = []
var maps: Array = []
var catalog: Array = []
var baseline: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		if failures.size()<=20: push_error("MULTI_ROUTE " + note)

func count_into(counts: Dictionary, value: Variant) -> void:
	var key: String = str(value)
	counts[key] = int(counts.get(key,0)) + 1

func point(value: Dictionary) -> Vector2: return Vector2(float(value.x),float(value.y))

func observe_wave(game: Node2D, wave_number: int) -> Dictionary:
	game.wave = wave_number-1
	game.enemies.clear(); game.ambush_warnings.clear()
	game.spawn_queue.clear(); game.spawn_source_waves.clear(); game.spawn_metadata.clear()
	game._begin_wave()
	var actual_counts: Dictionary = {}
	var planned_counts: Dictionary = {}
	var roles: Dictionary = {}
	var kinds: Dictionary = {}
	var expected_groups: Dictionary = {}
	var actual_groups: Dictionary = {}
	var successful: int = 0
	var planned: int = game.spawn_queue.size()
	for index in range(planned):
		var options: Dictionary = game.spawn_metadata[index]
		var expected: int = int(options.pathIndex)
		var group: String = str(options.formationGroup)
		if expected>=0:
			count_into(planned_counts,expected)
			if not expected_groups.has(group): expected_groups[group]=expected
			check(int(expected_groups[group])==expected,"Every routed cohort keeps one planned road: "+str(game.config.id)+" "+group)
		var size_before: int = game.enemies.size()
		var kind: String = str(game.spawn_queue[index])
		var source_wave: int = int(game.spawn_source_waves[index])
		var options_before: Dictionary = options.duplicate(true)
		game._queue_enemy_spawn(kind,source_wave,options)
		game._advance_ambush_warnings(2.01)
		check(options==options_before,"Queue resolution does not rewrite the caller's formation metadata")
		check(game.enemies.size()==size_before+1,"One actual queued entry yields one actual enemy")
		if game.enemies.size()!=size_before+1: continue
		var enemy: Dictionary = game.enemies[-1]
		successful += 1
		count_into(actual_counts,int(enemy.pathIndex)); count_into(kinds,str(enemy.kind)); count_into(roles,str(enemy.combatRole))
		check(expected<0 or int(enemy.pathIndex)==expected,"A queue-assigned road survives actual spawning: "+str(game.config.id)+" wave"+str(wave_number))
		check(int(enemy.spawnPathIndex)==int(enemy.pathIndex) and int(enemy.sourceWave)==source_wave,"Spawn route identity and HP source wave are preserved")
		# A prepared fort has always centered its stationary crew at lane0.
		# Its unchanged ingress contract preserves that lane while arriving.
		var expected_lane: int=0 if bool(enemy.get("stationaryAfterIngress",false)) or bool(enemy.get("stationaryEnemy",false)) else int(options.formationLane)
		check(str(enemy.formationPattern)==str(options.formationPattern) and str(enemy.formationGroup)==group and int(enemy.formationRank)==int(options.formationRank) and int(enemy.formationLane)==expected_lane,"Formation pattern, group, rank and native moving/stationary lane contract survive spawning")
		check(str(enemy.combatRole)==str(game.enemy_role_contract(str(enemy.kind)).combatRole),"Route fighter and emplacement hunter remain distinct native roles")
		if expected>=0:
			if not actual_groups.has(group): actual_groups[group]=int(enemy.pathIndex)
			check(int(actual_groups[group])==int(enemy.pathIndex),"Every explicit cohort walks on its one planned road")
	check(successful==planned and game.ambush_warnings.is_empty(),"Wave roster is spawned once without retained warning")
	if str(game.attack_pattern)=="formation" or bool(game.config.get("trait",{}).get("cycleRoutes",false)):
		check(actual_counts==planned_counts,"Actual cohort distribution matches the queued parallel route distribution")
		if planned>=6*game.paths.size(): check(actual_counts.size()==game.paths.size(),"A large cohort wave uses all authored roads together")
		if bool(game.config.get("trait",{}).get("cycleRoutes",false)):
			check(int(game.spawn_metadata[0].pathIndex)==(wave_number-1)%game.paths.size(),"Cycle trait rotates the first cohort only, once per wave")
	var key: String = str(game.config.id)+":"+str(wave_number)
	if baseline.has(key):
		check(planned==int(baseline[key].enemyCount),"Arrival repartition preserves the previously observed actual roster size")
		check(str(game.attack_pattern)==str(baseline[key].attackPattern),"Parallel routes preserve the previously observed attack-pattern sequence")
	return {"wave":wave_number,"pattern":str(game.attack_pattern),"queued":planned,"plannedPaths":planned_counts,"actualPaths":actual_counts,"roles":roles,"kinds":kinds,"groups":actual_groups}

func route_walk_and_entries(game: Node2D) -> void:
	game.enemies.clear(); game.ambush_warnings.clear(); game.wave=6
	for path_index in range(game.paths.size()):
		game.enemies.clear()
		var enemy: Dictionary = game._spawn_enemy("raider",2,{"pathIndex":path_index})
		check(int(enemy.pathIndex)==path_index,"Explicit requested road overrides visual theme and cycle trait")
		var birth: Vector2 = enemy.position
		var progress: float = 0.0
		var samples: int = 0
		var maximum_rail_error: float = 0.0
		for frame in range(400):
			if bool(enemy.escaped) or game.finished: break
			game._move_enemy(enemy,.05)
			check(int(enemy.pathIndex)==path_index,"An actual route fighter never switches roads while moving")
			var distance: float = game.ground_combat.enemy_distance(enemy)
			check(distance+.00005>=progress,"Actual fixed-path walking makes monotone forward progress")
			progress=distance
			maximum_rail_error=maxf(maximum_rail_error,enemy.position.distance_to(game.ground_combat.route_point(path_index,distance)))
			samples+=1
		check(progress>0.0 and enemy.position.distance_to(birth)>.01,"The route fighter actually advances from the unchanged common entrance")
		check(maximum_rail_error<.0001,"Fixed path fighter stays on its authored polyline")
		movement_rows.append({"stageId":str(game.config.id),"pathIndex":path_index,"samples":samples,"progress":progress,"maximumRailError":maximum_rail_error})
		var entry: Dictionary = game._prepared_ambush_entry(path_index)
		if entry.is_empty(): continue
		game.enemies.clear()
		var hunter: Dictionary = game._spawn_enemy("enemy_archer",2,{"pathIndex":(path_index+1)%game.paths.size(),"ambushEntry":entry})
		check(int(hunter.pathIndex)==path_index and int(hunter.spawnPathIndex)==path_index,"Actual side-entry join route overrides a conflicting cohort request")
		check(str(hunter.combatRole)==game.ENEMY_EMPLACEMENT_ROLE and bool(hunter.ingressActive),"Side entrant remains an emplacement hunter with a real walking ingress")
		check(hunter.position.distance_to(entry.points[0])<.00001,"Side entrant starts at the authored entrance, not at a target or teleported join")
		var previous: Vector2 = hunter.position
		var largest_step: float = 0.0
		for frame in range(1200):
			if not bool(hunter.ingressActive): break
			game._enemy_ingress_step(hunter,.025)
			largest_step=maxf(largest_step,hunter.position.distance_to(previous))
			previous=hunter.position
			check(int(hunter.pathIndex)==path_index,"Side hunter retains its join route throughout walking ingress")
		check(not bool(hunter.ingressActive),"Actual side-entry walking reaches its authored road join")
		check(largest_step<.01,"Actual hunter ingress has continuous small steps without teleport")
		side_rows.append({"stageId":str(game.config.id),"pathIndex":path_index,"entranceId":entry.id,"maxStep":largest_step})
		game.enemies.clear(); game.ambush_warnings.clear()
		var queued_options: Dictionary={"pathIndex":(path_index+1)%game.paths.size(),"ambushEntry":entry,"originKind":"raider"}
		var queued_before: Dictionary=queued_options.duplicate(true)
		game._queue_enemy_spawn("enemy_archer",2,queued_options)
		check(queued_options==queued_before,"Resolving an already-authored flank does not mutate its caller")
		check(game.ambush_warnings.size()==1 and game.ambush_warnings[0].options.ambushEntry==entry,"An already-authored flank survives the actual warning queue without reroll")
		game._advance_ambush_warnings(2.01)
		check(game.enemies.size()==1 and int(game.enemies[0].pathIndex)==path_index and str(game.enemies[0].ambushEntranceId)==str(entry.id),"Warning resolution preserves the supplied flank and its owning join road")
	var original_entries: Array=game.config.get("sideAmbushEntrances",[])
	game.config["sideAmbushEntrances"]=[]
	game.enemies.clear(); game.ambush_warnings.clear(); game.set_seed(49371)
	var reference_rng: RandomNumberGenerator=RandomNumberGenerator.new()
	reference_rng.seed=49371
	var once_selected: int=reference_rng.randi_range(0,game.paths.size()-1)
	game._queue_enemy_spawn("enemy_archer",2,{"originKind":"raider"})
	check(game.enemies.size()==1 and game.ambush_warnings.is_empty(),"A unavailable flank produces exactly one ordinary route fighter instead of teleporting")
	check(int(game.enemies[0].pathIndex)==once_selected and game.rng.state==reference_rng.state,"Random missing-flank fallback selects its road exactly once")
	check(str(game.enemies[0].combatRole)==game.ENEMY_PATH_ROLE,"Missing-flank fallback retains the ordinary route-fighter role")
	game.config["sideAmbushEntrances"]=original_entries

func same_stats_on_parallel_roads(game: Node2D) -> void:
	for kind in ["raider","runner","shield","heavy","commander","enemy_archer","enemy_gunner","enemy_cavalry","enemy_samurai"]:
		var reference: Dictionary = {}
		game.enemies.clear()
		for path_index in range(game.paths.size()):
			var enemy: Dictionary = game._spawn_enemy(kind,4,{"pathIndex":path_index})
			var stats: Dictionary = {}
			for key in ["kind","originKind","combatRole","hp","maxHp","speed","armor","damage","reward","sourceWave"]: stats[key]=enemy[key]
			if reference.is_empty(): reference=stats
			else: check(reference==stats,"Parallel roads do not change any actual enemy stat or role: "+str(game.config.id)+" "+kind)

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/route-selection/").to_lower()) or DisplayServer.get_name()!="headless": quit(2);return
	var raw_maps: String=FileAccess.get_file_as_string("res://native/maps.json")
	maps=JSON.parse_string(raw_maps)
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var before: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/profiles/route-selection/inspect_route_selection_before.json"))
	for row in before.observations:
		for sample in row.waves: baseline[str(row.id)+":"+str(sample.wave)]=sample
	var game: Node2D=Battle.new()
	game.three_d_enabled=true
	root.add_child(game); game.set_process(false)
	for config in maps:
		game.set_seed(20261007)
		game.load_map(config)
		var paths_before: Array=game.paths.duplicate(true)
		var row: Dictionary={"stageId":str(config.id),"paths":game.paths.size(),"theme":str(config.theme),"cycleRoutes":bool(config.get("trait",{}).get("cycleRoutes",false)),"waves":[]}
		for path in game.paths:
			check(path.points[0].distance_to(game.paths[0].points[0])<.00001 and path.points[1].distance_to(game.paths[0].points[1])<.00001,"Original common entrance and first segment remain intact")
		for wave_number in range(1,game.total_waves+1): row.waves.append(observe_wave(game,wave_number))
		same_stats_on_parallel_roads(game)
		route_walk_and_entries(game)
		check(game.paths==paths_before and game.config==config,"Route policy never edits the loaded map, paths, terrain or tactic geometry")
		observations.append(row)
	# Actual early roster conversion is observed through the same queued path.
	game.configure_roster(catalog,["archer","spear"],{})
	game.load_map(maps[0])
	for wave_number in range(1,game.total_waves+1):
		observe_wave(game,wave_number)
		for enemy in game.enemies:
			check(str(enemy.combatRole)==game.ENEMY_PATH_ROLE,"Starter campaign still contains no emplacement hunters")
			check(str(enemy.kind) not in game.EMPLACEMENT_ENEMY_KINDS and not bool(enemy.get("fortification",false)),"Early protection still converts hunters and removes enemy prepared cover")
	game.free()
	check(FileAccess.get_file_as_string("res://native/maps.json")==raw_maps,"CPU route verification does not rewrite stage data")
	var report: Dictionary={"checks":checks,"failures":failures,"stages":observations,"movement":movement_rows,"sideIngress":side_rows,"mapsSHA256":raw_maps.sha256_text(),"scope":"All forty unmodified authored stage configs and every actual wave queued through production spawning; cohort path/rank/lane, original entry, continuous fixed-road and side-join walking, equal stats across roads, starter hunter protection. Seeded CPU mechanics only; no campaign victory or visual/art claim."}
	var file: FileAccess=FileAccess.open("user://qa_multi_routes.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("MULTI_ROUTES ",JSON.stringify({"checks":checks,"failures":failures,"stages":observations.size(),"walkedRoutes":movement_rows.size(),"sideEntrances":side_rows.size()}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
