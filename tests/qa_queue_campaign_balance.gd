extends "res://tests/qa_marching_balance.gd"
## Actual first-stage strategies. Native production, casualties and economy only.
class RadiusDiagnostic:
	extends "res://native/game.gd"
	var intrusion_radius: float=.16
	var basic_hp_growth: float=-1.0
	func _spawn_enemy(kind: String, source_wave: int = -1, options: Dictionary = {}) -> Dictionary:
		var actor: Dictionary=super._spawn_enemy(kind,source_wave,options)
		if basic_hp_growth>=0 and str(config.get("tier",""))=="basic" and wave>=3 and not actor.is_empty():
			var source: int=int(actor.sourceWave)
			var ratio: float=(32.0+float(source)*basic_hp_growth)/(32.0+float(source)*10.0)
			actor["hp"]=float(actor.hp)*ratio
			actor["maxHp"]=float(actor.maxHp)*ratio
		return actor
	func _enemy_stationary_threat(enemy: Dictionary, delta: float) -> bool:
		# Diagnostic changes only acquisition distance. Once a unit is acquired,
		# native approach, attacks, path return, HP and rewards remain unchanged.
		if int(enemy.get("stationaryTargetId",-1))>=0 or enemy.has("threatAnchor"):
			return super._enemy_stationary_threat(enemy,delta)
		for ally in units:
			if str(ally.type) not in ["archer","gunner","monk","naginata"] or float(ally.get("hp",0))<=0: continue
			if enemy.position.distance_to(ally.position)<=intrusion_radius and ground_combat.land_segment_safe(enemy.position,ally.position):
				return super._enemy_stationary_threat(enemy,delta)
		enemy["stationThreatClock"]=maxf(0,float(enemy.get("stationThreatClock",0))-delta)
		if float(enemy.stationThreatClock)<=0: enemy.stationThreatClock=.35
		return false
var policies: Array = [
	{"name":"four_bows_screen","bows":4,"front":1,"lateFront":2,"cluster":false,"initialBows":2},
	{"name":"junction_bows_screen","bows":5,"front":1,"lateFront":2,"cluster":true,"initialBows":2},
	{"name":"infantry_screen","bows":5,"front":2,"lateFront":3,"cluster":true,"initialBows":2},
	{"name":"three_bows_front","bows":6,"front":1,"lateFront":2,"cluster":true,"initialBows":3},
	{"name":"dense_junction_fire","bows":8,"front":1,"lateFront":2,"cluster":true,"initialBows":2},
	{"name":"land_cover_and_crossfire","bows":10,"front":1,"lateFront":2,"cluster":true,"initialBows":2,"safeGap":.17},
	{"name":"safe_four_screen","bows":4,"front":1,"lateFront":1,"cluster":true,"initialBows":2,"safeGap":.17},
	{"name":"safe_six_screen","bows":6,"front":1,"lateFront":1,"cluster":true,"initialBows":2,"safeGap":.17},
	{"name":"balanced_forest_lines","bows":8,"front":1,"lateFront":2,"cluster":false,"balanced":true,"initialBows":2}
]
var active_policy: Dictionary = {}
var records: Array=[]
var first_stage_bytes: String=""
var modes: Array = [5,10,20]
var diagnostic_radius: float=0.0
var diagnostic_hp_growth: float=-1.0
var report_name: String="qa_queue_campaign_balance"
var clock_records: Array=[]
var bow_order_lanes: Dictionary={}

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"): quit(2);return
	first_stage_bytes=FileAccess.get_file_as_string("res://native/maps.json")
	maps=JSON.parse_string(first_stage_bytes)
	maps.sort_custom(func(a,b): return int(a.stageNumber)<int(b.stageNumber))
	store=Store.new()
	check(store.unlocked_units()==["archer","spear"] and store.army_level("archer")==1 and store.army_level("spear")==1,"Fresh account supplies only permanently level-one starter classes")
	check(int(maps[0].initialGold)==280,"First map uses its original 280 combat gold")
	var args: PackedStringArray=OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index]=="--minutes": modes=[int(args[index+1])]
		if args[index]=="--policy": policies=[policies[clampi(int(args[index+1]),0,policies.size()-1)]]
		if args[index]=="--intrusion-radius": diagnostic_radius=clampf(float(args[index+1]),.05,.23);report_name="qa_queue_campaign_balance_radius_"+str(roundi(diagnostic_radius*100))
		if args[index]=="--basic-hp-growth":
			if int(args[index+1])!=8: push_error("Only the parent-approved growth of eight may be diagnosed");quit(2);return
			diagnostic_hp_growth=8.0
	if diagnostic_hp_growth>=0: report_name+="_hp8"
	if "--clock-only" in args:
		report_name="qa_queue_campaign_balance_clocks"
		early_clock_contracts()
		write_results()
		print("QUEUE_CAMPAIGN_CLOCK_QA checks=",checks," failures=",failures.size()," outcomes=",JSON.stringify(clock_records))
		quit(0 if failures.is_empty() else 1)
		return
	var winning: Dictionary={}
	for minutes in modes:
		var tries: Array=[winning] if not winning.is_empty() else policies
		var mode_result: Dictionary={}
		for policy in tries:
			active_policy=policy
			mode_result=play_policy(minutes)
			records.append(mode_result)
			print("QUEUE_CAMPAIGN_BATTLE ",JSON.stringify(mode_result))
			if bool(mode_result.victory): winning=policy;break
		check(not mode_result.is_empty() and bool(mode_result.get("victory",false)),"An actual starter-only mixed army can defend "+str(minutes)+" minutes without learning rewards")
		write_results()
		if not bool(mode_result.get("victory",false)): break
	check(FileAccess.get_file_as_string("res://native/maps.json")==first_stage_bytes,"All forty authored historical maps remain unchanged")
	write_results()
	print("QUEUE_CAMPAIGN_QA checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func play_policy(minutes: int) -> Dictionary:
	var diagnostic: bool=diagnostic_radius>0 or diagnostic_hp_growth>=0
	var game: Node2D=RadiusDiagnostic.new() if diagnostic else Battle.new()
	if diagnostic:
		game.intrusion_radius=diagnostic_radius if diagnostic_radius>0 else .23
		game.basic_hp_growth=diagnostic_hp_growth
	balance_game=game
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(store.unit_catalog,store.unlocked_units(),store.data.army.levels)
	game.load_map(maps[0],minutes)
	game.set_seed(9876)
	observed_events.clear()
	bow_order_lanes.clear()
	game.game_event.connect(func(event: Dictionary): collect_event(game,event))
	prepare_geometry(game,1 if bool(active_policy.cluster) else 0)
	var composition: Dictionary={}
	policy_orders(game,composition)
	check(game.units.is_empty() and not game.recruitment_queue.is_empty(),"Paid starting orders wait for actual parallel production")
	var birth_times: Array=[]
	var last_deploy: float=-2.0
	var steps: int=0
	var peak_units: int=0
	var peak_enemies: int=0
	var objective_hits: Array=[]
	var last_hp: int=objective_health(game)
	var last_event: int=0
	game.start_battle()
	while not game.finished and steps<MAX_STEPS:
		if game.between_waves:
			policy_orders(game,composition)
			game.continue_wave()
		elif game.elapsed-last_deploy>=.75-.000001:
			policy_orders(game,composition)
			last_deploy=game.elapsed
		game.advance_simulation(STEP)
		steps+=1
		peak_units=maxi(peak_units,game.units.size())
		peak_enemies=maxi(peak_enemies,game.enemies.size())
		var hp: int=objective_health(game)
		if hp<last_hp: objective_hits.append({"seconds":game.elapsed,"wave":game.wave,"hp":hp,"gold":game.gold,"living":game.units.size(),"producing":game.recruitment_queue.size()})
		last_hp=hp
		for index in range(last_event,observed_events.size()):
			var event: Dictionary=observed_events[index]
			if str(event.type) in ["recruited","placed"] and birth_times.size()<4: birth_times.append({"seconds":event.time,"type":event.unitType})
		last_event=observed_events.size()
	var income: int=0
	var committed_spend: int=0
	var refunds: int=0
	var casualties: Dictionary={}
	var damage_by_enemy: Dictionary={}
	var born: Dictionary={}
	var learning_income: int=0
	var emplacement_rows: Dictionary={}
	var by_wave: Dictionary={}
	var escaped_by_path: Dictionary={}
	for event in observed_events:
		var wave_key: int=int(event.wave)
		if not by_wave.has(wave_key): by_wave[wave_key]={"kills":0,"casualties":0,"objectiveDamage":0,"damageDealt":0.0,"damageTaken":0.0}
		var wave_row: Dictionary=by_wave[wave_key]
		match str(event.type):
			"killed":
				income+=int(event.reward)
				wave_row.kills=int(wave_row.kills)+1
				if emplacement_rows.has(int(event.actorId)): emplacement_rows[int(event.actorId)].kills=int(emplacement_rows[int(event.actorId)].kills)+1
			"waveend": income+=40+int(event.wave)*3
			"trait-supply": income+=int(maps[0].trait.get("waveGold",{}).get("amount",0))
			"recruitment_queued": committed_spend+=int(event.cost)
			"recruitment_cancelled": refunds+=int(event.get("refund",0))
			"unit_fallen":
				casualties[str(event.unitType)]=int(casualties.get(str(event.unitType),0))+1
				wave_row.casualties=int(wave_row.casualties)+1
				if emplacement_rows.has(int(event.actorId)): emplacement_rows[int(event.actorId)].deathTime=float(event.time)
			"placed","recruited":
				born[str(event.unitType)]=int(born.get(str(event.unitType),0))+int(event.get("quantity",1))
				if str(event.unitType)=="archer": emplacement_rows[int(event.actorId)]={"id":int(event.actorId),"position":event.position,"damageDealt":0.0,"damageTaken":0.0,"kills":0,"deathTime":-1.0}
			"hit":
				if str(event.get("victimSide",""))=="friendly":
					damage_by_enemy[str(event.get("unitType","unknown"))]=float(damage_by_enemy.get(str(event.get("unitType","unknown")),0))+float(event.get("damage",0))
					wave_row.damageTaken=float(wave_row.damageTaken)+float(event.get("damage",0))
					if emplacement_rows.has(int(event.victimId)): emplacement_rows[int(event.victimId)].damageTaken=float(emplacement_rows[int(event.victimId)].damageTaken)+float(event.get("damage",0))
				else:
					wave_row.damageDealt=float(wave_row.damageDealt)+float(event.get("damage",0))
					if emplacement_rows.has(int(event.actorId)): emplacement_rows[int(event.actorId)].damageDealt=float(emplacement_rows[int(event.actorId)].damageDealt)+float(event.get("damage",0))
			"objective_hit":
				wave_row.objectiveDamage=int(wave_row.objectiveDamage)+int(event.damage)
				var path_index: int=int(event.get("qaActorPath",-1))
				escaped_by_path[path_index]=int(escaped_by_path.get(path_index,0))+int(event.damage)
			"reward": learning_income+=int(event.get("amount",0))
	check(game.gold==280+income-committed_spend+refunds,"Native queue debits, casualty replacements and cancellation refunds conserve the original combat wallet")
	check(game.learning_supports.is_empty() and learning_income==0,"No learning gold or damage support is injected")
	check(game.finished,"Actual timed battle finishes without a forced win")
	check(int(composition.get("archer",0))>0 and int(composition.get("spear",0))>0,"Actual play uses both stationary bows and marching infantry")
	check(peak_units<=14 and peak_enemies<=36,"Real army and enemy caps remain bounded")
	for unit in game.units:
		check(int(unit.campaignLevel)==1,"Living actor keeps the genuine starter permanent level")
	if game.victory: check(absf(game.elapsed-float(minutes)*60)<.000001,"Victory occurs at the selected pure-combat clock deadline")
	var result: Dictionary={"modeMinutes":minutes,"policy":active_policy.name,"intrusionRadius":diagnostic_radius if diagnostic_radius>0 else .23,"diagnosticHpGrowth":diagnostic_hp_growth,"diagnosticOnly":diagnostic,"victory":game.victory,"seconds":game.elapsed,"hp":game.snapshot().hp,"kills":game.kills,"gold":game.gold,"initialGold":280,"permanentLevel":1,"learningGold":0,"income":income,"spending":committed_spend,"refunds":refunds,"ordered":composition,"born":born,"casualties":casualties,"enemyDamage":damage_by_enemy,"initialBirths":birth_times,"peakUnits":peak_units,"peakEnemies":peak_enemies,"objectiveHits":objective_hits}
	result.merge({"emplacements":emplacement_rows.values(),"waves":by_wave,"objectiveDamageByPath":escaped_by_path},true)
	game.free()
	return result

func collect_event(game: Node2D, event: Dictionary) -> void:
	var copy: Dictionary=event.duplicate(true)
	if str(event.get("side",""))=="enemy":
		var actor: Dictionary=game._enemy(int(event.get("actorId",-1)))
		if not actor.is_empty(): copy["qaActorPath"]=int(actor.pathIndex)
	observed_events.append(copy)

func policy_orders(game: Node2D, composition: Dictionary) -> void:
	var bows: int=0
	var fronts: Dictionary={}
	for unit in game.units:
		if str(unit.type)=="archer": bows+=1
		else: fronts[int(unit.postPathIndex)]=int(fronts.get(int(unit.postPathIndex),0))+1
	for job in game.recruitment_queue:
		if str(job.type)=="archer": bows+=int(job.quantity)
		else: fronts[int(job.pathIndex)]=int(fronts.get(int(job.pathIndex),0))+int(job.quantity)
	while bows<int(active_policy.initialBows) and policy_bow(game,composition): bows+=1
	var target: int=int(active_policy.lateFront) if game.elapsed>=90 else int(active_policy.front)
	for path_index in range(game.paths.size()):
		while int(fronts.get(path_index,0))<target and reserved_army_size(game)<14 and game.gold>=65:
			if not game.begin_placement("spear",path_index): break
			composition["spear"]=int(composition.get("spear",0))+1
			fronts[path_index]=int(fronts.get(path_index,0))+1
	while bows<int(active_policy.bows) and policy_bow(game,composition): bows+=1

func policy_bow(game: Node2D, composition: Dictionary) -> bool:
	if bool(active_policy.get("balanced",false)): return balanced_bow(game,composition)
	if not bool(active_policy.cluster): return place_best_bow(game,composition,0)
	if game.gold<60 or reserved_army_size(game)>=14: return false
	var ranked: Array=[]
	var cover: Array[float]=current_cover(game)
	for option in options:
		if str(option.type)!="archer": continue
		if active_policy.has("safeGap"):
			if not option.has("threatDistance"): option["threatDistance"]=nearest_connected_route(game,option.position)
			if float(option.threatDistance)<float(active_policy.safeGap): continue
		var score: float=0.0
		var per_path: Dictionary={}
		for index in option.covers:
			var sample: Dictionary=samples[index]
			if float(sample.progress)<.35: continue
			score+=float(sample.weight)*(1.0+float(sample.progress))/(1.0+cover[index]/65.0)
			per_path[int(sample.path)]=true
		if per_path.size()==game.paths.size(): score*=2.25
		# Crossfire at the shared end of the authored lanes protects both exits.
		for objective in game.objectives: score*=1.0+maxf(0.0,.5-option.position.distance_to(objective.position))
		ranked.append({"option":option,"score":score})
	ranked.sort_custom(func(a,b): return float(a.score)>float(b.score))
	for candidate in ranked:
		var option: Dictionary=candidate.option
		if not game.begin_placement("archer"): return false
		var preview: Dictionary=game.placement_preview(option.requestedPosition)
		if not bool(preview.valid): game.cancel_recruit(); continue
		if game.place_unit(option.requestedPosition.x,option.requestedPosition.y):
			composition["archer"]=int(composition.get("archer",0))+1
			return true
		game.cancel_recruit()
	return false

func balanced_bow(game: Node2D, composition: Dictionary) -> bool:
	if game.gold<60 or reserved_army_size(game)>=14: return false
	var counts: Array=[0,0]
	for unit in game.units:
		if str(unit.type)!="archer": continue
		var intended: int=int(bow_order_lanes.get(int(unit.get("productionJobId",-1)),0))
		counts[intended]=int(counts[intended])+1
	for job in game.recruitment_queue:
		if str(job.type)=="archer":
			var intended: int=int(bow_order_lanes.get(int(job.id),0))
			counts[intended]=int(counts[intended])+int(job.quantity)
	var lane: int=0 if int(counts[0])<=int(counts[1]) else 1
	var ranked: Array=[]
	var cover: Array[float]=current_cover(game)
	for option in options:
		if str(option.type)!="archer": continue
		var score: float=0.0
		for index in option.covers:
			if int(samples[index].path)==lane: score+=float(samples[index].weight)/(1.0+cover[index]/35.0)
		if score>0: ranked.append({"option":option,"score":score})
	ranked.sort_custom(func(a,b): return float(a.score)>float(b.score))
	for candidate in ranked:
		var option: Dictionary=candidate.option
		if not game.begin_placement("archer"): return false
		var preview: Dictionary=game.placement_preview(option.requestedPosition)
		if not bool(preview.valid): game.cancel_recruit();continue
		if game.place_unit(option.requestedPosition.x,option.requestedPosition.y):
			bow_order_lanes[int(game.recruitment_queue[-1].id)]=lane
			composition["archer"]=int(composition.get("archer",0))+1
			return true
		game.cancel_recruit()
	return false

func nearest_connected_route(game: Node2D, position: Vector2) -> float:
	var closest: float=INF
	for path in game.paths:
		for index in range(path.points.size()-1):
			var point: Vector2=Geometry2D.get_closest_point_to_segment(position,path.points[index],path.points[index+1])
			if game.ground_combat.land_segment_safe(position,point): closest=minf(closest,position.distance_to(point))
	for sample in samples:
		if game.ground_combat.land_segment_safe(position,sample.point): closest=minf(closest,position.distance_to(sample.point))
	return closest

func write_results() -> void:
	var file: FileAccess=FileAccess.open("res://tests/"+report_name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":records,"clockResults":clock_records,"scope":"Actual original first-map clock/economy with parallel production, real casualties and paid recruitment; starter unlocks Lv1, 280 gold, zero learning rewards; deterministic policy failures do not prove impossibility."},"\t"))

func objective_health(game: Node2D) -> int:
	var value: int=0
	for objective in game.objectives: value+=int(objective.hp)
	return value

func early_clock_contracts() -> void:
	var baseline: Dictionary={}
	for minutes in [5,10,20]:
		var game: Node2D=Battle.new()
		balance_game=game
		root.add_child(game)
		game.set_process(false)
		game.configure_roster(store.unit_catalog,store.unlocked_units(),store.data.army.levels)
		game.load_map(maps[0],minutes)
		game.set_seed(9876)
		active_policy=policies[0]
		prepare_geometry(game,0)
		var composition: Dictionary={}
		policy_orders(game,composition)
		check(game.units.is_empty() and game.recruitment_queue.size()==4,"Mode "+str(minutes)+" starts four actual parallel jobs without instant actors")
		check(float(game.snapshot().battleTargetSeconds)==float(minutes)*60,"Mode "+str(minutes)+" exposes the correct pure-combat deadline")
		game.start_battle()
		game.advance_simulation(1.0)
		var jobs: String=JSON.stringify(game.recruitment_queue)
		var clock: float=float(game.elapsed)
		game.paused=true
		for tick in range(10): game._process(.1)
		check(absf(game.elapsed-clock)<.000001 and JSON.stringify(game.recruitment_queue)==jobs,"Native pause freezes every parallel timer and the selected battle clock")
		game.paused=false
		game.speed=2
		for tick in range(15): game._process(.1)
		check(absf(game.elapsed-4.0)<.000001 and game.units.size()==4 and game.recruitment_queue.is_empty(),"Native 2x resumes four delayed births on the correct pure-combat time")
		game.advance_simulation(16.0)
		check(game.between_waves and absf(game.elapsed-20.0)<.000001,"Every mode reaches the same small first learning checkpoint")
		var actors: String=JSON.stringify({"units":game.units,"enemies":game.enemies,"projectiles":game.projectiles})
		for tick in range(10): game._process(.1)
		check(absf(game.elapsed-20.0)<.000001 and JSON.stringify({"units":game.units,"enemies":game.enemies,"projectiles":game.projectiles})==actors,"Learning pauses live troops, enemies and committed missiles for every duration")
		game.continue_wave()
		game.advance_simulation(25.0)
		check(game.between_waves and absf(game.elapsed-45.0)<.000001 and not game.finished,"Every mode reaches the same second checkpoint without shortening the selected match")
		var outcome: Dictionary={"modeMinutes":minutes,"seconds":game.elapsed,"hp":objective_health(game),"kills":game.kills,"gold":game.gold,"units":game.units.size(),"enemies":game.enemies.size(),"waves":game.total_waves,"targetSeconds":game.snapshot().battleTargetSeconds,"openingWave1":game.battle_plan.waves[0].entries,"openingWave2":game.battle_plan.waves[1].entries}
		if baseline.is_empty(): baseline=outcome.duplicate(true)
		else:
			for key in ["seconds","hp","kills","gold","units","enemies","openingWave1","openingWave2"]: check(outcome[key]==baseline[key],"Duration modes share the actual opening state: "+str(key))
		clock_records.append(outcome)
		game.close_battle()
		game.free()
