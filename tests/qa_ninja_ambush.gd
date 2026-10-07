extends SceneTree
## CPU-only actual land placement, paid sorties/casualties and class mechanics.
const Battle=preload("res://native/game.gd")
const Types: Array=["archer","spear","samurai","gunner","naginata","monk","ninja","commander"]
var checks: int=0
var failures: Array=[]
var observations: Dictionary={}
var maps: Array=[]
var catalog: Array=[]
var events: Array=[]

func _initialize() -> void: call_deferred("run")
func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<=30: push_error("NINJA "+note)

func fixture() -> Dictionary:
	return {"id":"ninja-ambush-fixture","stageNumber":15,"theme":"forest","initialGold":2400,"unitLimit":14,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"north","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"wall","x":.5,"y":.7,"r":.09,"elevation":1}],"tactics":{"groundPosts":[{"id":"post","nameKo":"전선 지원","pathIndex":0,"segmentIndex":0,"t":.55,"r":.08,"guardRadius":.18,"mobilityFactor":1.0,"capacityBonus":0}]}}

func make_game(stage: Dictionary = {}, minutes: int = 0) -> Node2D:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,Types,{})
	game.load_map(fixture() if stage.is_empty() else stage,minutes)
	game.set_seed(117)
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	return game

func unit_cost(id: String) -> int:
	for entry in catalog:
		if str(entry.id)==id: return int(entry.cost)
	return -1

func hold(game: Node2D) -> void:
	game.start_battle()
	game.spawn_queue=["raider"]
	game.spawn_source_waves=[1]
	game.spawn_metadata=[{}]
	game.spawn_clock=100000.0

func simulate(game: Node2D, seconds: float) -> void:
	for tick in range(ceili(seconds/.025)):
		if game.between_waves: break
		game.advance_simulation(.025)

func await_production(game: Node2D) -> void:
	if not game.running:
		hold(game)
		game.enemies.clear()
	for tick in range(300):
		if game.recruitment_queue.is_empty(): return
		game.advance_simulation(.025)
	check(false,"Actual paid production completes within the bounded duration")

func enemy_at(game: Node2D, unit: Dictionary, distance: float, kind: String = "raider", source: int = 1, stationary: bool = true) -> Dictionary:
	game._spawn_enemy(kind,source)
	var enemy: Dictionary=game.enemies[-1]
	var path_index: int=int(unit.postPathIndex)
	enemy.pathIndex=path_index
	enemy.position=game.ground_combat.route_point(path_index,distance)
	for index in range(1,game.ground_combat.cumulative[path_index].size()):
		if distance<=float(game.ground_combat.cumulative[path_index][index]): enemy.pointIndex=index;break
	if stationary: enemy.speed=0.0
	return enemy

func place_ninja(game: Node2D, site_index: int = 0) -> Dictionary:
	var wallet: int=game.gold
	var actors: int=game.units.size()
	check(game.begin_placement("ninja") and game.gold==wallet and game.units.size()==actors,"Ninja selection creates an unpaid ambush preview")
	if game.ground_combat.ambush_sites.is_empty(): return {}
	var site: Dictionary=game.ground_combat.ambush_sites[site_index]
	check(game.place_unit(site.position.x,site.position.y),"Typed ambush click commits the actual ninja")
	await_production(game)
	return game.units[-1] if not game.units.is_empty() else {}

func map_contracts() -> void:
	var rows: Array=[]
	for stage in maps:
		var original: String=JSON.stringify(stage)
		var game: Node2D=make_game(stage)
		var wallet: int=game.gold
		var actor_id: int=game.next_id
		check(game.begin_placement("ninja"),str(stage.id)+" can select the real unlocked ninja")
		var contract: Dictionary=game.placement_contract("ninja")
		check(contract.deploymentKind=="ambush" and contract.movementRoleKo=="기습형" and contract.placementRole=="ambush",str(stage.id)+" separates ambush from marching and towers")
		var sites: Array=game.ground_combat.ambush_sites
		check(not sites.is_empty() and game.snapshot().ambushSites.size()==sites.size(),str(stage.id)+" exposes legal special land sites")
		var paths: Dictionary={}
		for site in sites:
			paths[int(site.pathIndex)]=true
			check(not game._on_road(site.position) and game.ground_combat.land_segment_safe(site.position,site.entryPosition),str(stage.id)+" ambush cover and its approach are land outside the road")
			for zone in game.zones:
				if str(zone.placementRole)!="ambush": check(site.position.distance_to(zone.position)>float(zone.r)+float(site.r),str(stage.id)+" special cover cannot overlap normal bow/frontline deployment")
			var preview: Dictionary=game.placement_preview(site.position)
			check(preview.valid and preview.placementMode=="concealed_ambush" and preview.ambushSiteId==site.id,str(stage.id)+" actual cursor/preview names the discrete ambush site")
			check(Vector2(float(preview.position.x),float(preview.position.y))==site.position,str(stage.id)+" preview snaps to the same reserved home")
		check(paths.size()==game.paths.size(),str(stage.id)+" each authored enemy lane has an independent special site")
		for zone in game.zones:
			if str(zone.placementRole)=="ambush": continue
			check(not game.placement_preview(zone.position).valid and not game.place_unit(zone.position.x,zone.position.y),str(stage.id)+" ninja rejects a normal tower/frontline click")
		check(not game.place_unit(.99,.99) and not game.place_unit(NAN,.5),str(stage.id)+" invalid field/nonfinite clicks cannot commit")
		if stage.has("water"):
			var water: Dictionary=stage.water
			check(not game.place_unit(float(water.x)+float(water.w)*.5,float(water.y)+float(water.h)*.5),str(stage.id)+" water cannot be used for ambush deployment")
		check(game.gold==wallet and game.next_id==actor_id and game.recruits==0,str(stage.id)+" every denied preview/click preserves money and actor IDs")
		if not sites.is_empty():
			var site: Dictionary=sites[0]
			check(game.place_unit(site.position.x,site.position.y),str(stage.id)+" legal click commits exactly once")
			check(game.gold==wallet-unit_cost("ninja") and game.next_id==actor_id and game.recruits==1 and game.recruitment_queue.size()==1,str(stage.id)+" real catalog cost is charged only on the reserved production order")
			check(not game.place_unit(site.position.x,site.position.y) and game.gold==wallet-unit_cost("ninja"),str(stage.id)+" duplicate commit cannot charge again")
			await_production(game)
			var unit: Dictionary=game.units[0]
			check(unit.homePosition==site.position and unit.position==site.position and unit.combatState=="ambush_wait",str(stage.id)+" ninja starts concealed at its selected home")
			check(game.begin_placement("archer") and not game.placement_preview(site.position).valid,str(stage.id)+" archer cannot steal ninja cover")
			check(game.begin_placement("gunner") and not game.placement_preview(site.position).valid,str(stage.id)+" gunner cannot steal ninja cover")
			check(game.begin_placement("monk") and not game.placement_preview(site.position).valid,str(stage.id)+" supporting monk cannot steal ninja cover")
			game.cancel_recruit()
		check(JSON.stringify(stage)==original,str(stage.id)+" generation never changes authored map terrain/coordinates")
		rows.append({"id":stage.id,"sites":sites.size(),"lanes":paths.size()})
		game.free()
	observations["maps"]=rows

func sorties_and_casualties() -> void:
	var game: Node2D=make_game()
	var unit: Dictionary=place_ninja(game)
	if unit.is_empty(): game.free();return
	var home: Vector2=unit.homePosition
	game.advance_simulation(2.0)
	check(unit.position==home,"Concealed ninja remains still before battle")
	hold(game)
	simulate(game,1.0)
	check(unit.position==home and unit.combatState=="ambush_wait","No nearby enemy leaves the ninja concealed and waiting")
	var enemy: Dictionary=enemy_at(game,unit,float(unit.homeDistance))
	var health: float=float(enemy.hp)
	var states: Dictionary={}
	var hits: int=0
	var returned: bool=false
	for tick in range(700):
		var previous: Vector2=unit.position
		game.advance_simulation(.025)
		states[str(unit.combatState)]=true
		check(unit.position.distance_to(previous)<=.052*1.4*.025+.00002,"Every sortie/return frame is real bounded movement, without teleportation")
		check(game.ground_combat.land_segment_safe(previous,unit.position),"Every observed sortie/return step stays on land")
		if float(enemy.hp)<health: hits=1
		if hits>0 and unit.combatState=="ambush_wait" and unit.position==home: returned=true;break
	check(hits==1 and returned and states.has("ambush_approach") and states.has("engaged") and states.has("ambush_return"),"Actual native enemy loses HP during a visible approach/hit/cover return cycle")
	check(unit.position==home and float(unit.hp)<=float(unit.maxHp),"Ninja returns to the exact selected cover without recovering wounds")
	var attack_events: int=0
	for event in events:
		if str(event.type)=="hit" and str(event.get("unitType",""))=="ninja": attack_events+=1
	check(attack_events==1,"A completed ambush sortie delivers one actual paid soldier attack")
	observations["sortie"]={"states":states.keys(),"enemyHpBefore":health,"enemyHpAfter":enemy.hp,"home":str(home),"hp":unit.hp,"hits":attack_events}
	game.free()
	game=make_game()
	unit=place_ninja(game)
	hold(game)
	enemy=enemy_at(game,unit,float(unit.homeDistance)-.11,"raider",1,false)
	health=float(enemy.hp)
	for tick in range(600):
		game.advance_simulation(.025)
		if float(enemy.hp)<health: break
	check(float(enemy.hp)<health,"An actual approaching mobile enemy, with its native speed, can be ambushed")
	game.free()
	game=make_game()
	unit=place_ninja(game)
	hold(game)
	enemy=enemy_at(game,unit,float(unit.homeDistance),"heavy",10)
	var wallet: int=game.gold
	for tick in range(3600):
		game.advance_simulation(.025)
		if game.units.is_empty(): break
	check(game.units.is_empty() and float(unit.hp)<=0,"Native heavy counterattacks can permanently kill an ambushing ninja")
	var corpse: Dictionary={}
	for actor in game.actor_states():
		if int(actor.id)==int(unit.id): corpse=actor
	check(not corpse.is_empty() and corpse.friendly and corpse.dead and corpse.type=="ninja" and corpse.animation=="death","Ninja death retains its actual model and shared death animation")
	simulate(game,9.0)
	check(game.units.is_empty() and game.gold==wallet,"Death grants no free revival, healing, cash or refund")
	var old_id: int=int(unit.id)
	check(game.recruit("ninja") and game.gold==wallet and not game.pending.is_empty(),"Replacement ninja is another unpaid special placement preview")
	var site: Dictionary=game.ground_combat.ambush_sites[0]
	check(game.place_unit(site.position.x,site.position.y) and game.gold==wallet-unit_cost("ninja"),"Replacement production pays the exact ninja price once")
	await_production(game)
	check(not game.units.is_empty() and int(game.units[0].id)!=old_id,"Replacement is a newly produced actor with a unique ID")
	game.free()

func clocks_and_support() -> void:
	for speed in [1.0,2.0,3.0]:
		var game: Node2D=make_game({},5)
		var unit: Dictionary=place_ninja(game)
		hold(game)
		var enemy: Dictionary=enemy_at(game,unit,float(unit.homeDistance))
		game.set_speed(float(speed))
		var production_clock: float=game.elapsed
		game._process(.05)
		check(absf(game.elapsed-production_clock-.05*float(speed))<.000001,"Ambush clock follows the requested 1/2/3 speed")
		game.pause_battle()
		var frozen: Dictionary=unit.duplicate(true)
		var enemy_frozen: Dictionary=enemy.duplicate(true)
		game._process(.25)
		game.advance_simulation(3.0)
		check(unit==frozen and enemy==enemy_frozen,"Explicit pause freezes ninja motion, HP, animation, plans and its enemy")
		game.pause_battle()
		game.elapsed=19.975
		game.advance_simulation(.025)
		check(game.between_waves and absf(game.elapsed-20.0)<.000001,"Timed learning boundary remains exact with a live ambush")
		frozen=unit.duplicate(true)
		enemy_frozen=enemy.duplicate(true)
		game._process(.25)
		game.advance_simulation(5.0)
		check(unit==frozen and enemy==enemy_frozen,"Study excludes ambush simulation and preserves a pending attack/return")
		game.continue_wave()
		check(unit==frozen and enemy==enemy_frozen,"Resume does not reset or relocate the live ninja sortie")
		game.free()
	var game: Node2D=make_game()
	check(game.begin_placement("monk") and game.pending.type=="monk","Monk selection creates a support placement preview instead of base dispatch")
	var post: Dictionary={}
	for zone in game.zones:
		if str(zone.placementRole)=="ground": post=zone;break
	check(game.place_unit(post.position.x,post.position.y),"Monk commits a real teal support point")
	await_production(game)
	var monk: Dictionary=game.units[0]
	var home: Vector2=monk.position
	check(game.snapshot().units[0].deploymentKind=="support" and game.placement_contract("monk").placementMode=="frontline_support","Monk public contract identifies fixed support")
	check(game.begin_placement("spear",0),"Passing spear orders real production at its friendly base")
	await_production(game)
	var spear: Dictionary=game.units[-1]
	hold(game)
	var passed_near_support: bool=false
	for tick in range(600):
		game.advance_simulation(.025)
		check(float(spear.get("supportArmor",0))==0 and int(spear.get("supportedBy",-1))==-1,"Unapproved allied support armor is inactive during actual play")
		if spear.position.distance_to(monk.position)<float(game._stats(monk).range): passed_near_support=true;break
	check(passed_near_support and monk.position==home,"A marching soldier passes the stationary monk without an unapproved allied buff")
	var enemy: Dictionary=enemy_at(game,monk,float(monk.homeDistance))
	var health: float=float(enemy.hp)
	enemy.attackCooldown=1000
	spear.cooldown=1000
	spear.hp=float(spear.maxHp)-20
	var wounded: float=float(spear.hp)
	for tick in range(120):
		game.advance_simulation(.025)
		if float(spear.hp)>wounded: break
	check(monk.position==home and float(enemy.hp)==health and float(spear.hp)>wounded and monk.attackPlan.is_empty(),"Stationary monk now heals the passing wounded ally and never attacks with the staff")
	game.free()

func fortification_and_story_maps() -> void:
	var rows: Array=[]
	for stage in maps:
		var game: Node2D=make_game(stage)
		hold(game)
		var fort: Dictionary=game._spawn_enemy("enemy_archer",1,{"fortification":true,"pathIndex":0})
		var enabled: bool=int(stage.stageNumber)>=15
		check(bool(fort.fortification)==enabled and bool(fort.stationaryEnemy)==enabled,str(stage.id)+" fortifications start only after the real ninja unlock stage")
		var reachable: int=0
		if enabled:
			check(game.ground_combat.land_segment_safe(fort.position,fort.position,.015) and not game._sailing_visual(fort),str(stage.id)+" real fortification is stationary on legal land")
			var stations: Array=[]
			for path_index in range(game.paths.size()):
				var station: Dictionary=game._fortification_position(path_index)
				if int(fort.pathIndex)==path_index: station={"position":fort.position,"distance":game.ground_combat.enemy_distance(fort)}
				check(not station.is_empty(),str(stage.id)+" every authored route supports a legal land fortification")
				if station.is_empty(): continue
				var nearby: bool=false
				for site in game.ground_combat.ambush_sites:
					if int(site.pathIndex)!=path_index or site.position.distance_to(station.position)>.30: continue
					var bounds: Vector2=game.ground_combat._land_bounds(path_index,float(site.homeDistance))
					if float(station.distance)>=bounds.x and float(station.distance)<=bounds.y: nearby=true;break
				check(nearby,str(stage.id)+" a legal off-road ninja cover can reach its route's fort within the bounded assassination radius")
				if nearby: reachable+=1
				stations.append({"path":path_index,"position":str(station.position),"reachable":nearby})
			var actor: Dictionary={}
			for entry in game.actor_states():
				if int(entry.id)==int(fort.id): actor=entry;break
			if game._enemy_visible(fort):
				check(not actor.is_empty() and actor.type=="enemy_archer" and actor.hostile and actor.fortification and actor.stationaryEnemy and float(actor.hp)==float(fort.hp),str(stage.id)+" renderer receives the actual visible hostile fortification actor and HP")
			else: check(actor.is_empty(),str(stage.id)+" the existing night visibility rule also hides an unrevealed fortification")
			rows.append({"mapId":stage.id,"stations":stations})
		var commander: Dictionary=game._spawn_enemy("commander",5)
		var normal: Dictionary=game._spawn_enemy("raider",5)
		var story: Dictionary=game.campaign_story_index.get(str(stage.id),{})
		var on_field: bool=not story.is_empty() and bool(story.get("opponentOnField",true))
		check(commander.has("historicalCommander")==on_field,str(stage.id)+" historical names belong only to a commander actually on this battlefield")
		check(not normal.has("historicalCommander") and not fort.has("historicalCommander"),str(stage.id)+" normal troops and towers never impersonate historical commanders")
		if on_field:
			var boss: Dictionary={}
			for entry in game.snapshot().enemies:
				if int(entry.id)==int(commander.id): boss=entry;break
			check(boss.historicalCommander.nameKo==story.opponent.nameKo and float(boss.historicalCommander.hp)==float(commander.hp) and float(boss.historicalCommander.maxHp)==float(commander.maxHp),str(stage.id)+" named commander HP is the live native HP rather than a story number")
			game._damage_enemy(commander,12.0,"spear")
			for entry in game.snapshot().enemies:
				if int(entry.id)==int(commander.id): check(float(entry.historicalCommander.hp)==float(commander.hp),str(stage.id)+" historical HP follows actual combat damage")
		game.free()
	observations["fortificationMaps"]=rows

func spawn_patterns_and_budgets() -> void:
	var patterns: Dictionary={}
	var kinds: Dictionary={}
	var budgets: Array=[]
	for stage in maps:
		for minutes in [5,10,20]:
			var game: Node2D=make_game(stage,minutes)
			var total: int=0
			for wave_index in range(game.total_waves):
				game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear()
				game._begin_wave()
				var expected: Dictionary={}
				for entry in game.wave_spawn_schedule[wave_index]:
					var key: String=str(entry.kind)+":"+str(entry.sourceWave)
					expected[key]=int(expected.get(key,0))+1
				if game.wave%5==0 or game.wave==game.total_waves:
					var key: String="commander:"+str(game._combat_wave_level())
					expected[key]=int(expected.get(key,0))+1
				var extra: Dictionary=game._trait().get("reinforcements",{})
				if not extra.is_empty() and game.wave%maxi(1,int(extra.get("every",1)))==0 and str(extra.get("kind","raider")) in ["raider","runner","shield","heavy","commander"]:
					var key: String=str(extra.get("kind","raider"))+":"+str(game._combat_wave_level())
					expected[key]=int(expected.get(key,0))+clampi(int(extra.get("count",1)),0,8)
				var actual: Dictionary={}
				var lanes: Dictionary={}
				check(game.spawn_queue.size()==game.spawn_metadata.size() and game.spawn_queue.size()==game.spawn_source_waves.size(),str(stage.id)+" class/formation metadata stays aligned with the existing budget")
				for index in range(game.spawn_queue.size()):
					var meta: Dictionary=game.spawn_metadata[index]
					var key: String=str(meta.originKind)+":"+str(game.spawn_source_waves[index])
					actual[key]=int(actual.get(key,0))+1
					kinds[str(game.spawn_queue[index])]=true
					lanes[int(meta.formationLane)]=true
					if bool(meta.fortification): check(int(stage.stageNumber)>=15 and game.wave>=3,"No fortification enters an earlier stage/opening wave")
				check(actual==expected,str(stage.id)+" "+str(minutes)+"min wave "+str(game.wave)+" preserves every native HP/reward family, source wave and spawn count")
				patterns[game.attack_pattern]=true
				if game.wave<=2: check(game.attack_pattern=="skirmish" and lanes.size()==1 and lanes.has(0),"Opening waves keep their small original approach")
				elif game.attack_pattern=="formation": check(lanes.size()==3,"Formation entry uses three actual columns")
				elif game.attack_pattern=="rush": check(lanes.size()>=3,"Rush entry distributes the native budget across distinct lanes")
				total+=game.spawn_queue.size()
			check(absf(float(game.battle_plan.targetSeconds)-float(minutes)*60.0)<.000001 and game.elapsed==0,"Formation construction never adds combat time or simulates the battle")
			budgets.append({"mapId":stage.id,"minutes":minutes,"waves":game.wave,"scheduled":total})
			game.free()
	check(patterns.has("formation") and patterns.has("mounted_vanguard") and patterns.has("rush") and kinds.has("enemy_archer") and kinds.has("enemy_gunner") and kinds.has("enemy_cavalry"),"Real schedules expose distinct formations and all three mobile enemy silhouettes")
	observations["spawnBudgets"]=budgets

func actual_forts_and_assassination() -> void:
	var game: Node2D=make_game()
	check(game.begin_placement("spear",0),"Wrong-class order fixture produces a normal soldier before the fort appears")
	await_production(game)
	var spear: Dictionary=game.units[0]
	var unit: Dictionary=place_ninja(game)
	hold(game)
	var fort: Dictionary=game._spawn_enemy("enemy_archer",1,{"fortification":true,"pathIndex":0})
	var home: Vector2=unit.homePosition
	var station: Vector2=fort.position
	var wallet: int=game.gold
	var first_event: int=events.size()
	game.select_unit(int(unit.id))
	game.input_enabled=false
	check(not game.order_assassination(int(fort.id)).accepted,"Input lock rejects an assassination order")
	game.input_enabled=true
	game.pause_battle()
	check(not game.order_assassination(int(fort.id)).accepted,"Paused battle rejects an assassination order")
	game.pause_battle()
	game.between_waves=true
	check(not game.order_assassination(int(fort.id)).accepted,"Study cannot start a ninja sortie")
	game.between_waves=false
	var normal: Dictionary=game._spawn_enemy("raider",1)
	check(not game.order_assassination(int(normal.id)).accepted,"Priority assassination requires a real fortification")
	game.enemies.erase(normal)
	var original_station: Vector2=fort.position
	fort.position=game.ground_combat.route_point(0,.8)
	check(not game.order_assassination(int(fort.id)).accepted,"A distant fortification cannot exceed the explicit home-based assassination limit")
	fort.position=original_station
	check(not game.order_assassination(int(fort.id),int(spear.id)).accepted,"A normal marching soldier cannot receive a ninja assassination order")
	game.units.erase(spear)
	wallet=game.gold
	game.select_unit(int(unit.id))
	check(game.order_assassination(int(fort.id)).accepted,"Selecting a ninja and its native nearby fortification starts the actual assassination")
	check(not game.order_assassination(int(fort.id)).accepted,"Repeated clicks cannot restart or duplicate an assassination")
	check(game.gold==wallet,"Target orders spend no extra money or grant supply")
	var states: Dictionary={}
	var killed: bool=false
	var returned: bool=false
	var saw_dead_prop: bool=false
	var saw_hostile_projectile: bool=false
	for tick in range(1200):
		var previous: Vector2=unit.position
		game.advance_simulation(.025)
		states[str(unit.combatState)]=true
		check(unit.position.distance_to(previous)<=.052*1.4*.025+.00002 and game.ground_combat.land_segment_safe(previous,unit.position),"Commanded assassination uses bounded real land movement on every frame")
		check(fort.position==station,"A real enemy fortification never marches or teleports")
		for projectile in game.projectiles:
			if projectile.get("victimSide","")=="friendly": saw_hostile_projectile=true
		if float(fort.hp)<=0:
			killed=true
			for actor in game.actor_states():
				if int(actor.id)==int(fort.id) and actor.dead and actor.fortification and actor.stationaryEnemy and actor.type=="enemy_archer": saw_dead_prop=true
		if killed and unit.combatState=="ambush_wait" and unit.position==home: returned=true;break
	check(killed and returned and states.has("engaged") and states.has("ambush_return"),"The actual ninja destroys a native fortification, then returns to the same selected cover")
	check(saw_dead_prop,"Real fort death keeps its type/station metadata for renderer wreck cleanup")
	var orders: int=0
	var kills: int=0
	var hostile_hits: int=0
	for event in events.slice(first_event):
		if event.type=="assassination_ordered": orders+=1
		if event.type=="killed" and int(event.get("victimId",-1))==int(fort.id): kills+=1
		if event.type=="hit" and event.get("side","")=="enemy" and int(event.get("victimId",-1))==int(unit.id): hostile_hits+=1
	check(orders==1 and kills==1 and game.gold==wallet+int(fort.reward),"One commanded fort kill pays its original reward once")
	check(saw_hostile_projectile and hostile_hits>0,"The live enemy bow station actually shoots and damages the approaching ninja")
	check(not game.order_assassination(int(fort.id)).accepted,"Destroyed fortifications cannot be commanded again")
	simulate(game,.8)
	var remains: bool=false
	for actor in game.actor_states():
		if int(actor.id)==int(fort.id): remains=true
	check(not remains,"Destroyed fort actor and wreck metadata expire on the common death clock")
	observations["assassination"]={"states":states.keys(),"orders":orders,"kills":kills,"hostileHits":hostile_hits,"hpAfter":unit.hp,"reward":fort.reward,"returned":returned}
	game.free()
	# Native archer/gunner projectiles damage a stationary support troop at
	# shooting distance. Fixture geometry chooses the post, not enemy damage.
	for kind in ["enemy_archer","enemy_gunner"]:
		game=make_game()
		var post: Dictionary={}
		for zone in game.zones:
			if str(zone.placementRole)=="ground": post=zone;break
		check(game.begin_placement("monk") and game.place_unit(post.position.x,post.position.y),"Shooter fixture commits a real fixed monk")
		await_production(game)
		var monk: Dictionary=game.units[0]
		hold(game)
		var enemy: Dictionary=enemy_at(game,monk,float(monk.homeDistance)-.1,str(kind),1,false)
		var before: float=float(monk.hp)
		var old_position: Vector2=monk.position
		var firing_position: Vector2=enemy.position
		var shot_seen: bool=false
		for tick in range(120):
			game.advance_simulation(.025)
			for shot in game.projectiles:
				if int(shot.get("sourceId",-1))==int(enemy.id) and shot.get("victimSide","")=="friendly": shot_seen=true
			if float(monk.hp)<before: break
		check(shot_seen and float(monk.hp)<before and monk.position==old_position and enemy.position==firing_position,"Native mobile "+str(kind)+" stops, shoots and actually damages a fixed support troop with its own projectile")
		game.free()

func observed_formation_and_harbor_projectiles() -> void:
	var formation_stage: Dictionary=fixture()
	formation_stage.stageNumber=14
	var game: Node2D=make_game(formation_stage)
	hold(game)
	game.wave=2
	game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear()
	game._begin_wave()
	var formation: Array=[]
	for index in range(mini(6,game.spawn_queue.size())):
		var options: Dictionary=game.spawn_metadata[index].duplicate(true)
		formation.append(game._spawn_enemy(str(game.spawn_queue[index]),int(game.spawn_source_waves[index]),options))
	game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=100000.0
	check(formation.size()==6,"Actual wave schedule creates a six-soldier formation fixture")
	var positions: Dictionary={}
	for enemy in formation:
		positions[str(enemy.position)]=true
		if str(enemy.kind) in ["enemy_archer","enemy_gunner"]: check(int(enemy.formationRank)>0,"Mobile ranged formation soldiers stand behind the native front row")
	check(positions.size()==3,"Formation enters through three visible columns, rather than one random pile")
	for tick in range(160):
		game.advance_simulation(.025)
		for enemy in formation:
			if int(enemy.formationRank)==0: continue
			for leader in formation:
				if int(leader.formationRank)!=0 or int(leader.formationLane)!=int(enemy.formationLane): continue
				var front: float=game.ground_combat.enemy_distance(leader)
				var rear: float=game.ground_combat.enemy_distance(enemy)
				check(rear<=maxf(0,front-.032)+.0001,"Actual rear soldiers preserve their column spacing behind the advancing native front")
	observations["formation"]=formation.map(func(enemy):return {"kind":enemy.kind,"rank":enemy.formationRank,"lane":enemy.formationLane,"position":str(enemy.position),"armor":enemy.armor})
	game.free()
	var harbor: Dictionary={}
	for stage in maps:
		if str(stage.theme)=="harbor": harbor=stage;break
	check(not harbor.is_empty(),"Actual authored harbor is available for landing projectile regression")
	game=make_game(harbor)
	var post: Dictionary={}
	for zone in game.zones:
		if str(zone.placementRole)=="ground": post=zone;break
	check(game.begin_placement("monk") and game.place_unit(post.position.x,post.position.y),"Harbor regression commits a real on-land support troop")
	await_production(game)
	var monk: Dictionary=game.units[0]
	hold(game)
	var enemy: Dictionary=enemy_at(game,monk,float(monk.homeDistance)-.08,"enemy_archer",1,false)
	var before: float=float(monk.hp)
	var event_start: int=events.size()
	for tick in range(120):
		game.advance_simulation(.025)
		if float(monk.hp)<before: break
	var actual_hit: Dictionary={}
	for event in events.slice(event_start):
		if event.type=="hit" and event.get("side","")=="enemy" and int(event.get("victimId",-1))==int(monk.id): actual_hit=event;break
	check(float(monk.hp)<before and not actual_hit.is_empty() and actual_hit.has("sailing") and not bool(actual_hit.sailing),"Actual harbor projectile landing preserves enemy route metadata and produces a nonsailing damage event")
	game.free()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/ninja-ambush/").to_lower()): push_error("Ninja QA refuses the player's profile");quit(2);return
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	map_contracts()
	sorties_and_casualties()
	clocks_and_support()
	fortification_and_story_maps()
	spawn_patterns_and_budgets()
	actual_forts_and_assassination()
	observed_formation_and_harbor_projectiles()
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"scope":"CPU-only real40-map special land/road/tower rejection, paid parallel production/duplicate/casualties, actual native enemy damage and bounded nonteleport cover return, 1/2/3 speed/pause/study preservation and stationary zero-attack healing support. Fixture budgets/unlocks/speed isolate mechanics; no campaign or GPU claim."}
	var path: String="user://qa_ninja_ambush_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_ninja_ambush.json"
	var output: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("NINJA_AMBUSH ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path(path))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
