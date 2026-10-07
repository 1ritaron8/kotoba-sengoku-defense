extends SceneTree
## CPU-only role mechanics. Fixture gold/unlocks isolate contracts; no campaign win is claimed.
const Battle=preload("res://native/game.gd")
const Marching: Array=["spear","samurai","commander"]
const Types: Array=["archer","spear","samurai","gunner","naginata","monk","ninja","commander"]
var checks: int=0
var failures: Array[String]=[]
var observations: Dictionary={}
var maps: Array=[]
var catalog: Array=[]
var events: Array=[]

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures.append(message)
		if failures.size()<=25: push_error("MARCHING "+message)

func fixture() -> Dictionary:
	return {"id":"marching-fixture","initialGold":2400,"unitLimit":14,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"north","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]},{"id":"south","objectiveId":"main","points":[{"x":.05,"y":.35},{"x":.5,"y":.4},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"wall","x":.5,"y":.68,"r":.09,"elevation":1}],"tactics":{"groundPosts":[{"id":"road","nameKo":"전선 사격","pathIndex":0,"segmentIndex":0,"t":.55,"r":.1,"guardRadius":.18,"mobilityFactor":1.0,"capacityBonus":0}]}}

func make_game(stage: Dictionary = {}, minutes: int = 5) -> Node2D:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,Types,{})
	game.load_map(fixture() if stage.is_empty() else stage,minutes)
	game.set_seed(77)
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	return game

func cost(id: String) -> int:
	for entry in catalog:
		if str(entry.id)==id: return int(entry.cost)
	return -1

func hold(game: Node2D) -> void:
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue=["raider"]
	game.spawn_source_waves=[1]
	game.spawn_metadata=[{}]
	game.spawn_clock=100000.0

func await_production(game: Node2D) -> void:
	if not game.running: hold(game)
	for tick in range(300):
		if game.recruitment_queue.is_empty(): return
		game.advance_simulation(.025)
	check(false,"Actual production completes within the bounded duration")

func simulate(game: Node2D, seconds: float) -> void:
	for index in range(ceili(seconds/.025)):
		if game.between_waves: game.continue_wave()
		game.advance_simulation(.025)

func enemy_at(game: Node2D, unit: Dictionary, gap: float, kind: String = "raider", source: int = 1) -> Dictionary:
	game._spawn_enemy(kind,source)
	var enemy: Dictionary=game.enemies[-1]
	var path_index: int=int(unit.postPathIndex)
	var distance: float=clampf(float(unit.routeDistance)-gap,float(unit.routeMin),float(unit.routeMax))
	enemy["pathIndex"]=path_index
	enemy["position"]=game.ground_combat.route_point(path_index,distance)
	var lengths: Array=game.ground_combat.cumulative[path_index]
	for index in range(1,lengths.size()):
		if distance<=float(lengths[index]): enemy["pointIndex"]=index;break
	return enemy

func role_and_routes() -> void:
	var commits: int=0
	var harbor_samples: int=0
	for stage in maps:
		var original: String=JSON.stringify(stage)
		for path_index in range(stage.paths.size()):
			for id in Marching:
				var game: Node2D=make_game(stage)
				var label: String=str(stage.id)+"/"+str(path_index)+"/"+str(id)
				var wallet: int=game.gold
				check(game.snapshot().marchBases.size()==stage.paths.size(),label+" has a safe base per authored route")
				check(game.begin_placement(id,path_index),label+" orders production on its chosen path")
				check(game.units.is_empty() and game.recruitment_queue.size()==1,label+" queues one paid order before producing its actor")
				game.advance_simulation(2.0)
				check(game.units.is_empty(),label+" production freezes before battle starts")
				await_production(game)
				if game.units.is_empty(): game.free();continue
				commits+=1
				var unit: Dictionary=game.units[0]
				check(game.gold==wallet-cost(id) and game.recruits==1,label+" spends the real class cost once")
				check(game.pending.is_empty() and not game.placement_cursor_visible,label+" leaves no placement cursor")
				var public: Dictionary=game.snapshot().units[0]
				check(public.deploymentKind=="marching" and public.movementRoleKo=="전진형" and int(public.pathIndex)==path_index,label+" exposes its deployment and route")
				check(not str(public.baseId).is_empty() and public.basePosition!=null and public.spawnPosition!=null,label+" exposes base and spawn positions")
				var initial: float=float(unit.routeDistance)
				check(initial>float(unit.routeMin) and absf(initial-float(game.ground_combat.cumulative[path_index][-1]))<.031,label+" starts next to the friendly end of the route")
				var position: Vector2=unit.position
				game.advance_simulation(2.0)
				check(unit.position==position,label+" solo actor first waits at its paid base to gather")
				hold(game)
				simulate(game,.6)
				for tick in range(80):
					var before: float=float(unit.routeDistance)
					game.advance_simulation(.025)
					check(float(unit.routeDistance)<=before+.000001 and float(unit.routeDistance)>=float(unit.routeMin)-.000001,label+" advances only toward the enemy along safe route bounds")
					check(str(unit.combatState) not in ["guard","return","retreat","recover","charge_return"],label+" contains no regional defence/return state")
					if str(stage.theme)=="harbor":
						var data: Dictionary=stage.water
						var water: Rect2=Rect2(float(data.x),float(data.y),float(data.w),float(data.h))
						check(not water.has_point(unit.position),label+" never steps into harbor water")
						harbor_samples+=1
				check(float(unit.routeDistance)<initial-.001,label+" really moves forward after dispatch")
				var actor: Dictionary=game.actor_states()[0]
				check(actor.type==id and actor.friendly and actor.motionTime>0 and not actor.deploying,label+" retains real running animation metadata")
				game.free()
		check(JSON.stringify(stage)==original,str(stage.id)+" preserves every authored map/path/trait")
	observations["routeCommits"]=commits
	observations["harborSamples"]=harbor_samples

func economic_contracts() -> void:
	var game: Node2D=make_game()
	var wallet: int=game.gold
	var cursor: int=game.ground_combat.march_path_cursor
	check(not game.begin_placement("spear",99),"Invalid explicit path rejects a dispatch")
	check(game.gold==wallet and game.units.is_empty() and game.next_id==1 and game.recruits==0 and game.ground_combat.march_path_cursor==cursor,"Invalid route cannot charge money, consume actor IDs, reserve slots or rotate automatic routing")
	game.gold=0
	check(not game.recruit("spear") and game.gold==0 and game.units.is_empty(),"Unaffordable recruitment cannot dispatch or charge")
	game.gold=wallet
	game.configure_roster(catalog,["archer","spear"],{})
	check(not game.begin_placement("samurai") and game.gold==wallet,"Locked marching classes cannot spend funds")
	check(game.recruit("archer"),"Paid legacy archer preview is available")
	var preview: Dictionary=game.pending.duplicate(true)
	var before: int=game.gold
	check(not game.begin_placement("spear",99) and game.pending==preview and game.gold==before,"Failed dispatch preserves an already paid placement preview")
	check(game.begin_placement("spear",0),"Valid dispatch replaces an old paid preview")
	check(game.gold==wallet-cost("spear") and game.pending.is_empty(),"Replacing the paid archer preview refunds it before paying the marching class once")
	await_production(game)
	before=game.gold
	game.cancel_recruit()
	check(game.gold==before and game.units.size()==1,"Cancel cannot refund a dispatched living soldier")
	check(not game.place_unit(.5,.5) and game.gold==before,"Marching recruitment never requires a second map click")
	game.config.unitLimit=1
	check(game.recruit("spear") and game.gold==before-cost("spear") and game.recruitment_queue.size()==1,"Full actor capacity still accepts an independently paid production order")
	check(game.cancel_recruitment(int(game.recruitment_queue[0].id)) and game.gold==before,"A waiting production order can be cancelled with exact refund")
	game.free()
	game=make_game()
	var counts: Array=[0,0]
	for index in range(8):
		check(game.recruit("spear"),"Automatic routing dispatch succeeds")
		counts[int(game.recruitment_queue[-1].pathIndex)]+=1
	check(absi(int(counts[0])-int(counts[1]))<=1,"Automatic dispatch balances friendly troop numbers across routes")
	await_production(game)
	var pressure: Dictionary=enemy_at(game,game.units[-1],.1)
	pressure.pathIndex=1
	check(game.begin_placement("spear") and int(game.recruitment_queue[-1].pathIndex)==1,"Equal-friendly-count routing prioritizes actual enemy pressure")
	await_production(game)
	hold(game)
	simulate(game,2.0)
	var distinct: Dictionary={}
	for unit in game.units:
		var key: String=str(unit.postPathIndex)+":"+str(roundi(unit.position.x*10000))+":"+str(roundi(unit.position.y*10000))
		distinct[key]=true
	check(distinct.size()>=6,"A shared base emits visible moving columns instead of permanent same-point stacks")
	game.free()

func combat_and_casualties() -> void:
	var combat: Array=[]
	for id in Marching:
		var game: Node2D=make_game()
		check(game.begin_placement(id,0),id+" is dispatched for actual melee combat")
		await_production(game)
		var unit: Dictionary=game.units[0]
		hold(game)
		simulate(game,.5)
		var enemy: Dictionary=enemy_at(game,unit,.10)
		var start: float=float(unit.routeDistance)
		var states: Dictionary={}
		var blocked: bool=false
		var gold_before: int=game.gold
		for tick in range(500):
			game.advance_simulation(.025)
			states[str(unit.combatState)]=true
			blocked=blocked or int(enemy.get("blockedBy",-1))==int(unit.id)
			if game.kills>=1: break
		check(game.kills==1 and float(enemy.hp)<=0,id+" lands real attacks and kills the actual source-wave-one enemy")
		check(blocked,id+" participates in live route blocking")
		check(game.gold==gold_before+int(enemy.reward),id+" receives one actual enemy kill reward")
		check(not states.has("return") and not states.has("charge_return") and not states.has("recover"),id+" does not return to a placement post after combat")
		if id=="commander": check(not states.has("charge") and not states.has("impact"),"Permanent level1 mounted soldiers use ordinary melee before charge unlocks")
		var after_kill: float=float(unit.routeDistance)
		simulate(game,2.0)
		check(float(unit.routeDistance)<after_kill-.025 and float(unit.routeDistance)<start,id+" resumes advancement after the kill")
		check(unit.attackPlan.is_empty(),id+" clears the completed attack plan")
		unit.hp=float(unit.maxHp)*.10
		var wounded: float=float(unit.routeDistance)
		simulate(game,.5)
		check(float(unit.routeDistance)<wounded and float(unit.hp)==float(unit.maxHp)*.10,id+" continues at low HP without retreat or free recovery")
		combat.append({"type":id,"states":states.keys(),"hp":unit.hp,"distanceTravelled":start-float(unit.routeDistance)})
		game.free()
	observations["combat"]=combat
	var game: Node2D=make_game()
	check(game.recruit("spear",0),"Casualty soldier pays for its first dispatch")
	await_production(game)
	var soldier: Dictionary=game.units[0]
	hold(game)
	var attacker: Dictionary=enemy_at(game,soldier,.035,"heavy",10)
	var before: int=game.gold
	var deaths_before: int=0
	for event in events:
		if str(event.type)=="unit_fallen": deaths_before+=1
	for tick in range(600):
		game.advance_simulation(.025)
		if game.units.is_empty(): break
	check(game.units.is_empty() and float(soldier.hp)<=0,"Native heavy counterattacks actually kill and remove a marching soldier")
	check(game.gold==before and game.kills==0,"An allied casualty grants no enemy-kill gold or score")
	check(int(attacker.get("blockedBy",-1))<0 and attacker.get("counterPlan",{}).is_empty(),"Death releases enemy blocks and stale counterattack plans")
	var corpse: Dictionary={}
	for actor in game.actor_states():
		if int(actor.id)==int(soldier.id): corpse=actor
	check(not corpse.is_empty() and corpse.friendly and corpse.dead and corpse.type=="spear" and corpse.animation=="death","The renderer receives a friendly spear death with its actual model identity")
	simulate(game,9.0)
	check(game.units.is_empty() and game.gold==before,"No free recovery, respawn or refund follows an allied casualty")
	var deaths_after: int=0
	for event in events:
		if str(event.type)=="unit_fallen": deaths_after+=1
	check(deaths_after==deaths_before+1,"One casualty emits one death event")
	check(game.begin_placement("spear",0) and game.gold==before-cost("spear"),"A new post-casualty dispatch consumes the actual class cost again")
	await_production(game)
	var replacement: Dictionary=game.units[0]
	var base: Dictionary=game.ground_combat.march_bases[0]
	check(int(replacement.id)!=int(soldier.id) and replacement.position==replacement.spawnPosition and replacement.homePosition==base.position and replacement.position.distance_to(base.position)<=.0101,"The replacement is a new paid soldier starting in its column at the actual friendly base")
	game.free()

func placed_and_clock() -> void:
	for id in ["archer","gunner"]:
		var game: Node2D=make_game()
		var before: int=game.gold
		check(game.begin_placement(id) and not game.pending.is_empty() and game.gold==before,id+" retains unpaid map placement preview")
		var point: Vector2=Vector2(-1,-1)
		for zone in game.zones:
			point=game._zone_placement_hint(zone,id)
			if point.x>=0: break
		check(point.x>=0 and game.place_unit(point.x,point.y),id+" can commit its assigned placement zone")
		await_production(game)
		var unit: Dictionary=game.units[0]
		var position: Vector2=unit.position
		check(game.snapshot().units[0].deploymentKind=="placed",id+" exposes the placed role")
		hold(game)
		game._spawn_enemy("raider",1)
		var enemy: Dictionary=game.enemies[-1]
		enemy.pathIndex=0
		enemy.pointIndex=1
		enemy.position=Vector2(.5,.5)
		simulate(game,5.0)
		check(unit.position==position,id+" fires and waits at the exact placed position")
		check(float(enemy.hp)<float(enemy.maxHp),id+" delivers actual ranged damage")
		game.free()
	for minutes in [5,10,20]:
		for speed_value in [1.0,2.0,3.0]:
			var game: Node2D=make_game({},minutes)
			check(game.begin_placement("spear",0),"Clock fixture dispatches a real marching actor")
			await_production(game)
			var unit: Dictionary=game.units[0]
			hold(game)
			game.set_speed(speed_value)
			var production_clock: float=game.elapsed
			game._process(.05)
			check(absf(game.elapsed-production_clock-.05*speed_value)<.000001,"Marching battle uses the requested speed on the combat clock")
			game.pause_battle()
			var paused_unit: Dictionary=unit.duplicate(true)
			var clock: float=game.elapsed
			game._process(.25)
			game.advance_simulation(9.0)
			check(game.elapsed==clock and unit==paused_unit,"Pause freezes a marching actor's position, HP, plans and phase")
			game.pause_battle()
			game.advance_simulation(19.80-game.elapsed)
			var enemy: Dictionary=enemy_at(game,unit,0.0,"heavy",1)
			game.advance_simulation(.20)
			check(game.between_waves and absf(game.elapsed-20.0)<.000001,"First timed boundary still enters study at the fixed combat time")
			var frozen_unit: Dictionary=unit.duplicate(true)
			var frozen_enemy: Dictionary=enemy.duplicate(true)
			var gold: int=game.gold
			game._process(.25)
			game.advance_simulation(50.0)
			check(unit==frozen_unit and enemy==frozen_enemy and game.gold==gold,"Study preserves the live marching fight and cannot grant duplicate supplies")
			game.continue_wave()
			check(unit==frozen_unit and enemy==frozen_enemy,"Resuming study does not relocate a marching soldier or clear its combat state")
			game.advance_simulation(.50)
			check(float(enemy.hp)<float(frozen_enemy.hp),"The preserved melee fight continues after study")
			var final_calls: Array=[]
			game.battle_finished.connect(func(result): final_calls.append(result))
			game.wave=game.total_waves
			game.elapsed=float(minutes)*60.0-.025
			game.advance_simulation(100.0)
			check(game.finished and game.victory and absf(game.elapsed-float(minutes)*60.0)<.000001 and final_calls.size()==1,"Marching keeps exact 5/10/20 deadlines and one final signal")
			gold=game.gold
			game._complete_wave()
			game.continue_wave()
			game.advance_simulation(100.0)
			check(game.gold==gold and final_calls.size()==1,"Repeated terminal callbacks cannot create marching troops or duplicate rewards")
			game.free()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("").to_lower()+"/"): quit(2);return
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	role_and_routes()
	economic_contracts()
	combat_and_casualties()
	placed_and_clock()
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"scope":"CPU-only actual authored-route dispatch/advance, finite mechanic fixture budgets, native enemy stats, blocking/hits/kill cash/casualties, fixed shooting, 40-map land bounds, 5/10/20 clocks at 1/2/3 speed and real study/pause preservation. No full-campaign or GPU claim."}
	var output: FileAccess=FileAccess.open("res://tests/qa_marching_contracts.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("MARCHING_CONTRACTS ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
