extends "res://tests/qa_campaign_balance.gd"
## Actual starter mixed army. No gold/HP/training/unlock/map or win injection.
var observed_events: Array=[]
var balance_game: Node2D

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"): quit(2);return
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	maps.sort_custom(func(a,b): return int(a.stageNumber)<int(b.stageNumber))
	store=Store.new()
	check(store.unlocked_units()==["archer","spear"] and store.army_level("archer")==1 and store.army_level("spear")==1,"Actual mixed battle uses only the real untrained starter unlocks")
	var results: Array=[]
	for strategy in range(3):
		var game: Node2D=Battle.new()
		balance_game=game
		root.add_child(game)
		game.set_process(false)
		game.configure_roster(store.unit_catalog,store.unlocked_units(),store.data.army.levels)
		game.load_map(maps[0],5)
		game.set_seed(9876+strategy*997)
		observed_events.clear()
		game.game_event.connect(func(event: Dictionary): observed_events.append(event.duplicate(true)))
		prepare_geometry(game,strategy)
		var composition: Dictionary={}
		var steps: int=0
		var last_deploy: float=-5.0
		deploy_mixed(game,composition,strategy)
		game.start_battle()
		while not game.finished and steps<MAX_STEPS:
			if game.between_waves:
				# Skip every question: only actual kills and the shipped wave
				# supplies may pay for replacement troops.
				deploy_mixed(game,composition,strategy)
				game.continue_wave()
			elif game.elapsed-last_deploy>=5.0-.000001:
				deploy_mixed(game,composition,strategy)
				last_deploy=game.elapsed
			game.advance_simulation(STEP)
			steps+=1
		var incomes: int=0
		var spending: int=0
		var casualties: int=0
		var march_purchases: int=0
		for event in observed_events:
			if event.type=="killed": incomes+=int(event.reward)
			if event.type=="waveend": incomes+=40+int(event.wave)*3
			if event.type=="trait-supply": incomes+=int(maps[0].trait.get("waveGold",{}).get("amount",0))
			if event.type=="unit_fallen": casualties+=1
			if event.type=="recruited" and event.get("deploymentKind","")=="marching":
				march_purchases+=1
				spending+=int(event.cost)
			if event.type in ["placed"]: spending+=int(event.cost)
		check(game.gold==int(maps[0].initialGold)+incomes-spending,"Every unit, casualty replacement is paid by the actual conserved combat wallet")
		check(game.finished,"Actual mixed battle terminates")
		check(int(composition.get("archer",0))>0 and int(composition.get("spear",0))>0,"Actual battle recruits both placed bows and marching spears")
		check(game.learning_supports.is_empty(),"Mixed battle receives no hidden learning damage support")
		var result: Dictionary={"victory":game.victory,"seconds":game.elapsed,"hp":game.snapshot().hp,"kills":game.kills,"gold":game.gold,"income":incomes,"spent":spending,"casualties":casualties,"marchPurchases":march_purchases,"composition":composition,"initialGold":maps[0].initialGold,"strategy":strategy,"learningGold":0}
		results.append(result)
		print("MARCHING_BALANCE ",JSON.stringify(result))
		var won: bool=game.victory
		if won:
			check(absf(game.elapsed-300.0)<.000001,"Actual mixed starter army survives exactly five pure-combat minutes")
			check(casualties>0 and march_purchases>game.paths.size(),"Native frontline casualties cause paid new soldiers to leave the base")
		game.free()
		if won: break
	check(not results.is_empty() and bool(results[-1].victory),"An actual mixed starter strategy survives the shipped first-stage economy")
	var output: FileAccess=FileAccess.open("res://tests/qa_marching_balance.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results,"scope":"Actual first-stage 5-minute mixed archer/spear army, permanent Lv1, original 280 starting gold, native kills/wave supplies only, zero learning rewards, real casualties and paid replacements. Greedy strategies are not human enjoyability proof."},"  "))
	output.close()
	print("MARCHING_BALANCE_QA checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func sample_covered(unit: Dictionary, sample: Dictionary, attack_range: float) -> bool:
	if Battle.GroundCombat.is_marching(str(unit.type)):
		var actual_range: float=balance_game.ground_combat.reach(unit)
		return int(sample.path)==int(unit.postPathIndex) and unit.position.distance_squared_to(sample.point)<actual_range*actual_range
	return super.sample_covered(unit,sample,attack_range)

func deploy_mixed(game: Node2D, composition: Dictionary, strategy: int) -> void:
	var archers: int=0
	var marching: Dictionary={}
	for unit in game.units:
		if str(unit.type)=="archer": archers+=1
		else: marching[int(unit.postPathIndex)]=int(marching.get(int(unit.postPathIndex),0))+1
	# Production is parallel but delayed. Reservations count toward the intended
	# composition, while only completed living soldiers contribute real damage.
	for job in game.recruitment_queue:
		if str(job.type)=="archer": archers+=int(job.quantity)
		elif str(job.kind)=="marching": marching[int(job.pathIndex)]=int(marching.get(int(job.pathIndex),0))+int(job.quantity)
	# Place two bows first, then maintain a paid infantry front for every lane.
	if archers<2:
		while archers<2 and place_best_bow(game,composition,strategy): archers+=1
	var target: int=2 if game.elapsed>=120.0 else 1
	for path_index in range(game.paths.size()):
		while int(marching.get(path_index,0))<target and reserved_army_size(game)<int(game.config.unitLimit) and game.gold>=int(store.unit_definition("spear").cost):
			if not game.begin_placement("spear",path_index): break
			composition["spear"]=int(composition.get("spear",0))+1
			marching[path_index]=int(marching.get(path_index,0))+1
	while archers<10 and place_best_bow(game,composition,strategy): archers+=1

func place_best_bow(game: Node2D, composition: Dictionary, strategy: int) -> bool:
	if game.gold<int(store.unit_definition("archer").cost) or reserved_army_size(game)>=int(game.config.unitLimit): return false
	var cover: Array[float]=current_cover(game)
	var ranked: Array=[]
	for option in options:
		if str(option.type)!="archer": continue
		var occupied: bool=false
		for unit in game.units:
			if str(unit.type)!="archer": continue
			if unit.position.distance_to(option.position)<.0521: occupied=true;break
		for job in game.recruitment_queue:
			if str(job.kind)!="marching" and job.position.distance_to(option.position)<.0521: occupied=true;break
		if occupied: continue
		var score: float=0.0
		for index in option.covers: score+=float(samples[index].weight)/(1.0+cover[index]/(26.0 if strategy!=2 else 45.0))
		ranked.append({"option":option,"score":score})
	ranked.sort_custom(func(a,b): return float(a.score)>float(b.score))
	for candidate in ranked:
		var option: Dictionary=candidate.option
		if not game.begin_placement("archer"): return false
		var preview: Dictionary=game.placement_preview(option.requestedPosition)
		if not bool(preview.valid): game.cancel_recruit();continue
		var before: int=game.gold
		if not game.place_unit(option.requestedPosition.x,option.requestedPosition.y): game.cancel_recruit();continue
		check(game.gold==before-int(store.unit_definition("archer").cost),"A bow commit spends the actual class cost once")
		composition["archer"]=int(composition.get("archer",0))+1
		return true
	return false

func reserved_army_size(game: Node2D) -> int:
	var count: int=game.units.size()
	for job in game.recruitment_queue: count+=int(job.quantity)
	return count
