extends SceneTree
## CPU spawn/production regression only; this does not establish campaign wins.
const Battle = preload("res://native/game.gd")
const OUTPUT_ROOT: String = "res://tests/profiles/first-stage-hp-patch/"
const ENEMY_KINDS: Array = ["raider","runner","shield","heavy","commander","enemy_archer","enemy_gunner","enemy_cavalry","enemy_samurai"]
const BASELINE_SPAWN_SOURCE_SHA256: String = "80c5b9d8da643dd3b24bfd17758ceab955341d544fe0a077ee8d2c36e6fec3d2"

# Frozen pre-patch spawning implementation. Both groups execute real native
# helpers, routes, RNG, traits and enemy creation; only the control's HP lacks
# the first-stage patch. The expected values are observed from this control.
class OriginalSpawnGame:
	extends "res://native/game.gd"
	func _spawn_enemy(kind: String, source_wave: int = -1, options: Dictionary = {}) -> Dictionary:
		if paths.is_empty():
			return {}
		var origin_kind: String=str(options.get("originKind",{"enemy_archer":"raider","enemy_gunner":"shield","enemy_cavalry":"runner","enemy_samurai":"heavy"}.get(kind,kind)))
		if emplacement_protection_active() and kind in EMPLACEMENT_ENEMY_KINDS: kind=origin_kind
		var path_index: int=_spawn_path_index(options)
		var path: Dictionary = paths[path_index]
		var difficulty: float = float(config.get("difficulty", 1.0))
		var difficulty_wave: int = wave if source_wave<0 else source_wave
		var base_hp: float = (32.0 + difficulty_wave * 10.0) * difficulty
		var move_speed: float = 0.020 + difficulty_wave * 0.00035
		var armor: float = 0.0
		var damage: int = 1
		var reward: int = 7
		match origin_kind:
			"runner":
				base_hp *= 0.7
				move_speed *= 1.5
			"shield":
				base_hp *= 1.65
				move_speed *= 0.78
				armor = 0.38
				reward = 11
				damage = 2
			"heavy":
				base_hp *= 2.2
				move_speed *= 0.72
				armor = 0.25
				damage = 3
				reward = 15
			"commander":
				base_hp *= 6.0
				move_speed *= 0.62
				armor = 0.3
				damage = 5
				reward = 45
		for bonus in _trait().get("enemyBonuses", []):
			if str(bonus.get("kind", "all")) in [kind,origin_kind,"all"]:
				base_hp *= float(bonus.get("hpFactor", 1.0))
				move_speed *= float(bonus.get("speedFactor", 1.0))
		var enemy: Dictionary = {"id":next_id,"kind":kind,"sourceWave":difficulty_wave,"hp":base_hp,"maxHp":base_hp,"speed":move_speed,"armor":armor,"damage":damage,"reward":reward,"pathIndex":path_index,"pointIndex":1,"position":path.points[0],"aim":Vector2.RIGHT,"escaped":false,"animation":"walk","animationClock":0.0,"animationPhase":fmod(float(next_id)*0.117,1.0),"hitClock":0.0}
		enemy.merge(enemy_role_contract(kind),true)
		enemy["spawnPathIndex"]=path_index
		enemy["routeProgress"]=0.0
		enemy.merge({"originKind":origin_kind,"formationPattern":str(options.get("formationPattern","skirmish")),"formationGroup":str(options.get("formationGroup","")),"formationRank":int(options.get("formationRank",0)),"formationLane":int(options.get("formationLane",0)),"stationaryEnemy":false,"fortification":false})
		if kind in ["enemy_archer","enemy_gunner"]:
			enemy["attackRange"]=.205 if kind=="enemy_archer" else .14
			enemy["attackInterval"]=.85 if kind=="enemy_archer" else 1.55
			enemy["rangedPlan"]={}
			enemy["attackCooldown"]=0.0
			if bool(options.get("fortification",false)) and int(config.get("stageNumber",1))>=_ninja_unlock_stage():
				var station: Dictionary=_fortification_position(path_index)
				if not station.is_empty():
					enemy.merge({"position":station.position,"pointIndex":int(station.pointIndex),"stationaryEnemy":true,"fortification":true,"animation":"idle","formationLane":0,"fortificationPosition":station.position},true)
		if kind=="commander":
			var story: Dictionary=campaign_story_index.get(str(config.get("id","")),{})
			if not story.is_empty() and bool(story.get("opponentOnField",true)) and story.get("opponent") is Dictionary:
				var commander: Dictionary=story.opponent.duplicate(true)
				commander.merge({"id":str(commander.get("id",story.get("battleEventId","opponent"))),"battleEventId":str(story.get("battleEventId","")),"year":int(story.get("year",0))},true)
				enemy["historicalCommander"]=commander
		if not bool(enemy.stationaryEnemy): enemy.position=_enemy_lane_point(enemy,0)
		if options.has("ambushEntry") and str(enemy.combatRole)==ENEMY_EMPLACEMENT_ROLE:
			var entry: Dictionary=options.ambushEntry
			var ingress: Array=entry.points.duplicate()
			var settles: bool=bool(enemy.stationaryEnemy)
			if settles:
				var station_distance: float=ground_combat.enemy_distance(enemy)
				var join_distance: float=float(entry.joinDistance)
				var stop_points: Array=[]
				var lengths: Array=ground_combat.cumulative[path_index]
				if station_distance>=join_distance:
					for index in range(lengths.size()):
						if float(lengths[index])>join_distance+.00001 and float(lengths[index])<station_distance-.00001: stop_points.append(path.points[index])
				else:
					for index in range(lengths.size()-1,-1,-1):
						if float(lengths[index])<join_distance-.00001 and float(lengths[index])>station_distance+.00001: stop_points.append(path.points[index])
				stop_points.append(enemy.position)
				var previous: Vector2=ingress[-1]
				for point in stop_points:
					if not ground_combat.land_segment_safe(previous,point,.002): settles=false;break
					previous=point
				if settles: ingress.append_array(stop_points)
			var final_index: int=int(enemy.pointIndex) if settles else int(entry.pointIndex)
			# Prepared cover is stationary. The crew walks in from the side; cover
			# must not become a moving bunker or an assassination target en route.
			enemy.merge({"position":ingress[0],"pointIndex":int(entry.pointIndex),"ingressPoints":ingress,"ingressIndex":1,"ingressActive":true,"ingressJoinDistance":float(entry.joinDistance),"ingressPointIndex":final_index,"stationaryAfterIngress":settles,"stationaryEnemy":false,"fortification":false,"ambushEntranceId":str(entry.id),"routeProgress":float(entry.joinDistance)},true)
			var transport: Array = []
			for point in entry.get("transportPoints",[]): transport.append(_point(point))
			if str(entry.get("transportKind",""))=="boat" and transport.size()>=2 and transport[-1].distance_to(ingress[0])<.00001:
				enemy.merge({"position":transport[0],"transportPoints":transport,"transportIndex":1,"transportKind":"boat","transportActive":true},true)
			_prepare_ingress_target(enemy)
		# Face the first real leg before the first render. Boat transport and
		# hidden ingress take precedence over the unrelated main-road heading.
		var first_destination: Vector2=_enemy_lane_point(enemy,int(enemy.pointIndex))
		if bool(enemy.get("transportActive",false)):
			first_destination=enemy.transportPoints[int(enemy.transportIndex)]
		elif bool(enemy.get("ingressActive",false)):
			first_destination=enemy.ingressPoints[int(enemy.ingressIndex)]
			if enemy.has("ingressTargetPoint") and int(enemy.ingressIndex)==int(enemy.ingressTargetIndex):
				first_destination=enemy.ingressTargetPoint
		var spawn_direction: Vector2=first_destination-enemy.position
		if spawn_direction.length_squared()>.000000001:
			enemy.aim=spawn_direction.normalized()
		else:
			var forward_index: int=clampi(int(enemy.pointIndex),1,path.points.size()-1)
			enemy.aim=(path.points[forward_index]-path.points[forward_index-1]).normalized()
		if _is_timed_battle(): enemy["counterWave"]=difficulty_wave
		next_id += 1
		enemies.append(enemy)
		return enemy

var checks: int = 0
var failures: Array = []
var compared_spawns: int = 0
var examples: Array = []
var production: Dictionary = {}
var catalog: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures.append(note)
		if failures.size() <= 30: push_error("FIRST_STAGE_HP " + note)

func normalized_path(value: String) -> String:
	return value.replace("\\","/").simplify_path().trim_suffix("/").to_lower() + "/"

func safe_profile() -> bool:
	var boundary: String = normalized_path(ProjectSettings.globalize_path(OUTPUT_ROOT))
	var appdata: String = OS.get_environment("APPDATA")
	var local_appdata: String = OS.get_environment("LOCALAPPDATA")
	if not appdata.is_absolute_path() or not local_appdata.is_absolute_path(): return false
	var app: String = normalized_path(appdata)
	var local: String = normalized_path(local_appdata)
	var profile: String = normalized_path(ProjectSettings.globalize_path("user://"))
	return DisplayServer.get_name() == "headless" and app == local and app.begins_with(boundary) and profile.begins_with(app)

func make_game(stage: Dictionary, minutes: int, original: bool = false) -> Node2D:
	var game: Node2D = OriginalSpawnGame.new() if original else Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.load_map(stage,minutes)
	game.set_seed(57391)
	game.wave = 3
	return game

func compare_spawn(actual_game: Node2D, control: Node2D, kind: String, source_wave: int, expected_factor: float, label: String) -> void:
	var before: Dictionary = control._spawn_enemy(kind,source_wave)
	var after: Dictionary = actual_game._spawn_enemy(kind,source_wave)
	check(not before.is_empty() and not after.is_empty(),label + " both actual spawn paths create an enemy")
	if before.is_empty() or after.is_empty(): return
	compared_spawns += 1
	check(absf(float(after.hp)-float(before.hp)*expected_factor) < .00000001,label + " current HP has exactly the authorized factor")
	check(absf(float(after.maxHp)-float(before.maxHp)*expected_factor) < .00000001,label + " max HP has exactly the authorized factor")
	var original_fields: Dictionary = before.duplicate(true)
	var current_fields: Dictionary = after.duplicate(true)
	for key in ["hp","maxHp"]:
		original_fields.erase(key)
		current_fields.erase(key)
	check(current_fields == original_fields,label + " every other enemy property is unchanged")
	if str(actual_game.config.id) == "basic-forest" and int(actual_game.config.stageNumber) == 1 and source_wave == 10 and kind in ["raider","shield","heavy","commander"]:
		examples.append({"minutes":actual_game.battle_minutes,"kind":kind,"sourceWave":source_wave,"beforeHp":before.hp,"afterHp":after.hp,"speed":after.speed,"armor":after.armor,"damage":after.damage,"reward":after.reward})

func campaign_spawns(maps: Array) -> void:
	check(maps.size() == 40,"Forty original stages are available")
	for stage in maps:
		var authored: String = JSON.stringify(stage)
		for minutes in [10,20]:
			var game: Node2D = make_game(stage,minutes)
			var control: Node2D = make_game(stage,minutes,true)
			var label: String = str(stage.id) + " " + str(minutes) + "min"
			var factor: float = .95 if str(stage.id) == "basic-forest" and int(stage.stageNumber) == 1 else 1.0
			check(game.config == stage and control.config == stage,label + " runtime setup does not tune authored difficulty")
			check(game.battle_plan == control.battle_plan and game.wave_spawn_schedule == control.wave_spawn_schedule,label + " duration/wave rosters and counters are unchanged")
			check(game.gold == control.gold and game.objectives == control.objectives and game.zones == control.zones,label + " economy/objectives/deployment are unchanged")
			for source_wave in range(1,int(stage.totalWaves)+1):
				for kind in ENEMY_KINDS:
					compare_spawn(game,control,str(kind),source_wave,factor,label + " " + str(kind) + " wave" + str(source_wave))
			for kind in ENEMY_KINDS:
				compare_spawn(game,control,str(kind),-1,factor,label + " " + str(kind) + " implicit wave3")
			check(game.config == stage and control.config == stage and JSON.stringify(stage) == authored,label + " repeated spawning leaves both config and original dictionary unchanged")
			game.free()
			control.free()

func reload_and_identity(first: Dictionary) -> void:
	var game: Node2D = make_game(first,10)
	var original: Node2D = make_game(first,10,true)
	var reference: Dictionary = original._spawn_enemy("raider",10)
	check(absf(float(reference.hp)-132.0)<.00000001,"Frozen first-stage final-wave raider is 132 HP")
	for minutes in [10,20,10,20]:
		game.load_map(first,minutes)
		game.set_seed(57391)
		var enemy: Dictionary = game._spawn_enemy("raider",10)
		check(absf(float(enemy.hp)-125.4)<.00000001,"Reload " + str(minutes) + "min applies one HP reduction without compounding")
		check(game.config == first,"Repeated first-stage load leaves difficulty/source config unchanged")
	for changed in ["id","stageNumber"]:
		var private_fixture: Dictionary = first.duplicate(true)
		private_fixture[changed] = "unrelated-stage" if changed == "id" else 2
		game.load_map(private_fixture,10)
		original.load_map(private_fixture,10)
		game.set_seed(57391)
		original.set_seed(57391)
		compare_spawn(game,original,"raider",10,1.0,"Identity boundary " + changed)
	game.free()
	original.free()

func queue_unit(game: Node2D, type_name: String) -> bool:
	var count: int = game.recruitment_queue.size()
	var actors: int = game.units.size()
	var wallet: int = game.gold
	var cost: int = game.recruit_cost(type_name)
	if not game.begin_placement(type_name,0): return false
	if str(game.placement_contract(type_name).deploymentKind) != "marching":
		var position: Vector2 = Vector2(-1,-1)
		for zone in game.zones:
			var hint: Vector2 = game._zone_placement_hint(zone,type_name)
			if hint.x >= 0 and bool(game.placement_preview(hint).valid):
				position = hint
				break
		if position.x < 0 or not game.place_unit(position.x,position.y):
			game.cancel_recruit()
			return false
	check(game.units.size() == actors and game.recruitment_queue.size() == count+1,"Paid " + type_name + " order queues before actor creation")
	check(game.gold == wallet-cost,"Paid " + type_name + " order deducts its exact real cost")
	return true

func production_contract(first: Dictionary) -> void:
	var game: Node2D = make_game(first,10)
	var control: Node2D = make_game(first,10,true)
	for current in [game,control]:
		current.configure_roster(catalog,["archer","spear"],{"archer":1,"spear":1})
		# Declared production-only wallet fixture, never campaign win evidence.
		current.gold = 10000
		for type_name in ["archer","spear","archer","spear","archer","spear","archer","spear","spear","spear"]:
			check(queue_unit(current,str(type_name)),"Real authored first-stage geometry accepts the mixed order")
		check(current.units.is_empty() and current.recruitment_queue.size() == 10,"Ten mixed paid orders remain independently queued")
		current._advance_recruitment(6.0)
		var archers: int = 0
		var spears: int = 0
		for unit in current.units:
			if str(unit.type) == "archer": archers += 1
			if str(unit.type) == "spear": spears += 1
		check(archers == 4 and spears == 6 and current.units.size() == 10,"Actual paid production creates ten mixed actors")
		for index in range(4): check(queue_unit(current,"spear"),"Four reserve production orders remain available")
		check(current.units.size() == 10 and current.recruitment_queue.size() == 4,"Ten deployed actors coexist with four paid reserve orders")
	check(game.gold == control.gold and game.units == control.units and game.recruitment_queue == control.recruitment_queue,"HP patch leaves all mixed/reserve production data identical to control")
	production = {"fixture":"Production-only wallet 10000, real level-one archer/spear APIs and original map geometry; no combat or victory conclusion","deployed":game.units.size(),"reserveOrders":game.recruitment_queue.size(),"unitLimit":game.config.unitLimit,"queueCapacity":game.RECRUITMENT_CAPACITY,"walletAfterOrders":game.gold}
	for current in [game,control]:
		current._advance_recruitment(6.0)
		check(current.units.size() == 14 and current.recruitment_queue.is_empty(),"Four reserve orders complete within the unchanged fourteen-actor limit")
		check(queue_unit(current,"spear"),"Full actor capacity retains paid reserve production")
		current._advance_recruitment(6.0)
		check(current.units.size() == 14 and current.recruitment_queue.size() == 1 and str(current.recruitment_queue[0].status) == "waiting_capacity","Finished reserve waits for actor capacity without changing the limit")
		check(current.config == first,"Mixed/reserve production leaves the original map contract unchanged")
	check(game.gold == control.gold and game.units == control.units and game.recruitment_queue == control.recruitment_queue,"Full-capacity reserve behavior remains identical to control")
	game.free()
	control.free()

func run() -> void:
	if not safe_profile():
		push_error("First-stage HP QA requires headless and identical APPDATA/LOCALAPPDATA inside its res://tests/profiles/first-stage-hp-patch/ boundary")
		quit(2)
		return
	var maps_sha_before: String = FileAccess.get_sha256("res://native/maps.json")
	var manifest_sha_before: String = FileAccess.get_sha256("res://assets/battlefields-rendered/manifest.json")
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	maps.sort_custom(func(a,b): return int(a.stageNumber)<int(b.stageNumber))
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	check(is_equal_approx(Battle.FIRST_STAGE_ENEMY_HP_FACTOR,.95),"Authorized runtime coefficient is 0.95")
	campaign_spawns(maps)
	reload_and_identity(maps[0])
	production_contract(maps[0])
	check(FileAccess.get_sha256("res://native/maps.json") == maps_sha_before,"Original maps bytes remain unchanged")
	check(FileAccess.get_sha256("res://assets/battlefields-rendered/manifest.json") == manifest_sha_before,"Artwork provenance manifest bytes remain unchanged")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefields-rendered/manifest.json"))
	check(str(manifest.sourceMapsSha256) == maps_sha_before,"Unchanged maps still match artwork provenance")
	var report: Dictionary = {"checks":checks,"failures":failures,"comparedSpawns":compared_spawns,"firstStageExamples":examples,"mixedReserveProduction":production,"mapsSha256":maps_sha_before,"artManifestSha256":manifest_sha_before,"gameSourceSha256":FileAccess.get_sha256("res://native/game.gd"),"frozenBaselineSpawnSha256":BASELINE_SPAWN_SOURCE_SHA256,"scope":"CPU actual spawning against the frozen pre-patch implementation: all forty stages, 10/20-minute modes, each authored source wave, nine enemy kinds and implicit-wave behavior. First-stage HP/maxHP only; all other enemy fields, plans/economy/map inputs, repeated loads and narrow stage identity. Production-only 10 mixed actors/4 paid reserves uses a declared wallet fixture. No GPU, player saves, installer or campaign victory/balance guarantee."}
	var output: FileAccess = FileAccess.open("user://qa_first_stage_hp_patch.json",FileAccess.WRITE)
	if output == null:
		push_error("Cannot write isolated first-stage HP QA report")
		quit(2)
		return
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("FIRST_STAGE_HP checks=",checks," failures=",failures.size()," comparedSpawns=",compared_spawns," report=",ProjectSettings.globalize_path("user://qa_first_stage_hp_patch.json"))
	quit(0 if failures.is_empty() else 1)
