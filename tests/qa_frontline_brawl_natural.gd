extends "res://tests/qa_frontline_brawl.gd"
## Bounded shipped-map economy/combat observation, without injected battle funds.

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(ProjectSettings.globalize_path("res://tests/profiles/frontline-brawl-01/").replace("\\","/").to_lower()): quit(2);return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var game: Node2D=Battle.new()
	root.add_child(game);game.set_process(false)
	game.configure_roster(catalog,["archer","spear"],{})
	game.load_map(maps[0],10);game.set_seed(9876)
	var receipts: Array=[]
	game.game_event.connect(func(event: Dictionary): receipts.append(event.duplicate(true)))
	var bows: int=0
	for zone in game.zones:
		if str(zone.get("placementRole",""))!="ranged" or bows>=2: continue
		var point: Vector2=game._zone_placement_hint(zone,"archer")
		if point.x>=0 and bool(game.submit_deployment("archer",point).ok): bows+=1
	game.start_battle()
	var costs: Array=[]
	var maximum_units: int=0
	var maximum_enemies: int=0
	var next_order: float=0
	var raid_targets: Dictionary={}
	while game.elapsed<120.0 and not game.finished:
		if game.between_waves: game.continue_wave()
		if game.elapsed>=next_order and game.gold>=game.recruit_cost("spear"):
			game.begin_placement("spear")
			next_order=game.elapsed+2.0
		var before: int=Time.get_ticks_usec()
		game.advance_simulation(.05)
		costs.append(float(Time.get_ticks_usec()-before)/1000.0)
		maximum_units=maxi(maximum_units,game.units.size())
		maximum_enemies=maxi(maximum_enemies,game.enemies.size())
		for enemy in game.enemies:
			var target: String=str(enemy.get("assaultZoneId",""))
			if not target.is_empty(): raid_targets[target]=true
	var queued: int=0
	var spent: int=0
	var refunded: int=0
	var income: int=0
	var casualties: int=0
	for event in receipts:
		match str(event.type):
			"recruitment_queued": queued+=1;spent+=int(event.cost)
			"recruitment_cancelled": refunded+=int(event.get("refund",0))
			"killed": income+=int(event.reward)
			"waveend": income+=40+int(event.wave)*3
			"trait-supply": income+=int(maps[0].trait.get("waveGold",{}).get("amount",0))
			"unit_fallen": casualties+=1
	check(game.gold==int(maps[0].initialGold)+income-spent+refunded,"Natural battle spending conserves real start/kill/wave supplies")
	check(bows==2 and queued>5,"Actual starter economy purchases towers and repeated expendable spears")
	check(casualties>0,"Natural front genuinely loses and replaces infantry")
	check(raid_targets.size()>=2,"Natural scheduled enemies include multiple simultaneous emplacement targets")
	costs.sort()
	var report: Dictionary={"checks":checks,"failures":failures,"elapsedCombatSeconds":game.elapsed,"finished":game.finished,"objectiveHp":game.snapshot().hp,"gold":game.gold,"orders":queued,"spent":spent,"income":income,"refunds":refunded,"casualties":casualties,"kills":game.kills,"maximumFriendlyActors":maximum_units,"maximumEnemyActors":maximum_enemies,"assaultTargetZones":raid_targets.keys(),"simulationStepP50Ms":costs[costs.size()/2],"simulationStepP95Ms":costs[mini(costs.size()-1,ceili(float(costs.size())*.95)-1)],"scope":"Up to120 natural combat seconds with original280gold, actual starterLv1, two paid archers and paid spear order every2s when affordable. CPU-only step cost excludes rendering; this is not FPS or full-campaign balance acceptance."}
	var output: FileAccess=FileAccess.open("res://tests/qa_frontline_brawl_natural.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("FRONTLINE_NATURAL ",JSON.stringify(report))
	game.free()
	quit(0 if failures.is_empty() else 1)
