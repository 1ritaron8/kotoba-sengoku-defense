extends SceneTree
## Paid parallel production through real Game APIs; no GPU, save or installed files.
const Battle=preload("res://native/game.gd")
const Types: Array=["archer","spear","samurai","gunner","naginata","monk","ninja","commander"]
var catalog: Array=[]
var maps: Array=[]
var checks: int=0
var failures: Array=[]
var observations: Dictionary={}

func _initialize() -> void: call_deferred("run")
func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<=30: push_error("QUEUE "+note)

func fixture() -> Dictionary:
	return {"id":"recruitment-queue-fixture","stageNumber":15,"theme":"forest","initialGold":10000,"unitLimit":32,"totalWaves":100,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":1000}],"buildZones":[{"id":"bow","x":.5,"y":.65,"r":.11}],"tactics":{"groundPosts":[{"id":"support","pathIndex":0,"segmentIndex":0,"t":.52,"r":.13,"guardRadius":.22,"mobilityFactor":1.0}]}}

func make_game(stage: Dictionary = {}, levels: Dictionary = {}) -> Node2D:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,Types,levels)
	game.load_map(fixture() if stage.is_empty() else stage,0)
	game.set_seed(391)
	return game

func hold(game: Node2D) -> void:
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=100000.0

func tick(game: Node2D, seconds: float) -> void:
	for index in range(ceili(seconds/.025)): game.advance_simulation(.025)

func cost(id: String) -> int:
	for entry in catalog:
		if str(entry.id)==id: return int(entry.cost)
	return -1

func queue(game: Node2D, id: String, path: int = 0) -> Dictionary:
	var wallet: int=game.gold
	var actors: int=game.units.size()
	var jobs: int=game.recruitment_queue.size()
	if not game.begin_placement(id,path): return {}
	var contract: Dictionary=game.placement_contract(id)
	if str(contract.deploymentKind)!="marching":
		check(game.gold==wallet and game.units.size()==actors and game.recruitment_queue.size()==jobs,id+" selection is a free preview")
		var point: Vector2=Vector2(-1,-1)
		for zone in game.zones:
			var hint: Vector2=game._zone_placement_hint(zone,id)
			if hint.x>=0 and bool(game.placement_preview(hint).valid): point=hint;break
		if point.x<0 or not game.place_unit(point.x,point.y): return {}
	check(game.gold==wallet-cost(id) and game.units.size()==actors and game.recruitment_queue.size()==jobs+1,id+" commits one paid order before any actor appears")
	return game.recruitment_queue.back().duplicate(true)

func all_maps() -> void:
	var rows: Array=[]
	for original in maps:
		var before: String=JSON.stringify(original)
		var game: Node2D=make_game(original)
		game.gold=10000
		var events: Array=[]
		game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
		var jobs: Array=[]
		var total_time: float=0
		var paid: int=0
		for id in Types:
			var job: Dictionary=queue(game,str(id))
			check(not job.is_empty(),str(original.id)+" has a legal production destination for "+str(id))
			if job.is_empty(): continue
			var legal: bool=game.ground_combat.land_segment_safe(job.position,job.position,0) if str(job.kind) in ["marching","ambush"] else not game._eligible_zone(job.position,str(id)).is_empty()
			check(legal,str(original.id)+" reserves its legal authored deployment destination for "+str(id))
			check(float(job.totalSeconds)>=2.0 and float(job.totalSeconds)<=5.5,str(original.id)+" production delay is bounded")
			jobs.append(job);total_time=maxf(total_time,float(job.totalSeconds));paid+=int(job.cost)
		check(game.units.is_empty() and game.gold==10000-paid,str(original.id)+" all eight orders are paid without instant troops")
		var untouched: String=JSON.stringify(game.snapshot().recruitmentQueue)
		game.advance_simulation(20)
		check(JSON.stringify(game.snapshot().recruitmentQueue)==untouched,str(original.id)+" briefing freezes production")
		hold(game)
		tick(game,total_time+.05)
		check(game.recruitment_queue.is_empty() and game.units.size()==jobs.size(),str(original.id)+" parallel production completes every ordered level-one unit within the longest timer")
		jobs.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.id)<int(b.id) if is_equal_approx(float(a.totalSeconds),float(b.totalSeconds)) else float(a.totalSeconds)<float(b.totalSeconds))
		var created_ids: Dictionary={}
		var completed: Array=[]
		for event in events:
			if str(event.type) in ["recruited","placed"]: completed.append(int(event.jobId))
		for index in range(game.units.size()):
			var unit: Dictionary=game.units[index]
			created_ids[int(unit.id)]=true
			check(float(unit.hp)>0 and int(unit.productionJobId)==int(jobs[index].id),str(original.id)+" real actor/HP comes from its independent production receipt")
			if str(unit.type) in ["archer","gunner","monk","naginata","ninja"]:
				check(unit.position==jobs[index].position,str(original.id)+" no-danger placed/guard/support/ambush stays at its reserved home")
		check(created_ids.size()==game.units.size() and completed==jobs.map(func(job: Dictionary): return int(job.id)),str(original.id)+" completion events and actor IDs are unique and ordered")
		var stable: String=JSON.stringify(game.snapshot())
		for index in range(4):
			var public: Dictionary=game.snapshot()
			if not public.units.is_empty(): public.units[0].flags["qa_mutation"]=true
		check(JSON.stringify(game.snapshot())==stable,str(original.id)+" public snapshots do not mutate production or skills")
		check(JSON.stringify(original)==before,str(original.id)+" common production keeps authored map data unchanged")
		rows.append({"id":original.id,"orders":jobs.size(),"productionSeconds":total_time,"paid":paid})
		game.free()
	observations["maps"]=rows

func money_capacity_and_reservations() -> void:
	var game: Node2D=make_game()
	game.gold=0
	check(not game.begin_placement("spear",0) and game.recruitment_queue.is_empty(),"No gold creates no marching job")
	check(not game.begin_placement("archer") and not game.place_unit(.5,.65) and game.recruitment_queue.is_empty() and game.gold==0,"Placed selection without enough money cannot create an unpaid job")
	game.cancel_recruit();game.gold=10000
	var first: Dictionary=queue(game,"monk")
	check(game.begin_placement("gunner") and not game.placement_preview(first.position).valid and not game.place_unit(first.position.x,first.position.y),"An unfinished order reserves the same support/frontline point against other classes")
	game.cancel_recruit()
	var public: Dictionary=game.snapshot()
	public.recruitmentQueue[0].remainingSeconds=0;public.recruitmentQueue[0].cost=1
	check(float(game.recruitment_queue[0].remainingSeconds)==float(first.totalSeconds) and int(game.recruitment_queue[0].cost)==cost("monk"),"UI queue snapshots cannot edit the private timer or refund")
	check(game.cancel_recruitment(int(first.id)) and game.gold==10000 and game.recruitment_queue.is_empty(),"Queued cancellation refunds the exact original amount")
	check(not game.cancel_recruitment(int(first.id)) and game.gold==10000,"Duplicate or stale cancellation never refunds twice")
	check(game.begin_placement("gunner") and game.placement_preview(first.position).valid,"Cancellation releases the reserved location")
	game.cancel_recruit()
	var ids: Array=[]
	for index in range(24):
		var job: Dictionary=queue(game,"spear")
		if not job.is_empty(): ids.append(int(job.id))
	var wallet: int=game.gold
	check(ids.size()==24 and not game.begin_placement("spear") and game.gold==wallet,"Capacity24 rejects the25th paid order atomically")
	game.close_battle()
	check(game.gold==10000 and game.recruitment_queue.is_empty(),"Actual battle close refunds all unfinished parallel jobs")
	game.close_battle();game.start_battle();game.continue_wave()
	check(game.gold==10000 and not game.running and not game.begin_placement("spear"),"Repeated close and resume cannot reopen or refund a closed battle")
	game.free()

func clocks_and_parallel() -> void:
	var rows: Array=[]
	for speed in [1.0,2.0,3.0]:
		var game: Node2D=make_game()
		var first: Dictionary=queue(game,"spear")
		var second: Dictionary=queue(game,"samurai")
		hold(game);game.set_speed(float(speed))
		var start: float=game.elapsed
		game._process(.2)
		check(absf(game.elapsed-start-.2*float(speed))<.00001,"World speed multiplies production simulation "+str(speed))
		check(absf(float(game.recruitment_queue[0].remainingSeconds)-(float(first.totalSeconds)-.2*float(speed)))<.00001,"Head remaining follows the scaled world delta")
		check(absf(float(game.recruitment_queue[1].remainingSeconds)-(float(second.totalSeconds)-.2*float(speed)))<.00001,"Every later order progresses concurrently with exactly the same world delta")
		game.pause_battle()
		var frozen: String=JSON.stringify(game.snapshot().recruitmentQueue)
		game._process(.2);game.advance_simulation(10)
		check(JSON.stringify(game.snapshot().recruitmentQueue)==frozen,"Explicit pause/menu-resume boundary preserves orders and their remaining time")
		game.paused=false;game.between_waves=true
		game._process(.2);game.advance_simulation(10)
		check(JSON.stringify(game.snapshot().recruitmentQueue)==frozen,"Study freezes every production timer")
		game.between_waves=false
		tick(game,.15)
		var wallet: int=game.gold
		check(game.cancel_recruitment(int(first.id)) and game.gold==wallet+cost("spear"),"Cancellation during partial production refunds the full incomplete order")
		tick(game,float(second.totalSeconds)+.05)
		check(game.units.size()==1 and str(game.units[0].type)=="samurai" and game.recruitment_queue.is_empty(),"Other production completes exactly once after an independent job cancellation")
		check(not game.cancel_recruitment(int(second.id)),"A completed order cannot be refunded")
		rows.append({"speed":speed,"elapsed":game.elapsed,"firstCancelled":first.id,"completed":second.id})
		game.free()
	observations["clocks"]=rows
	var independent: Node2D=make_game()
	var long_job: Dictionary=queue(independent,"commander")
	var short_job: Dictionary=queue(independent,"spear")
	hold(independent);tick(independent,float(short_job.totalSeconds)+.025)
	check(independent.units.size()==1 and str(independent.units[0].type)=="spear" and independent.recruitment_queue.size()==1 and int(independent.recruitment_queue[0].id)==int(long_job.id),"A later short order appears while the first long order is still producing")
	check(float(independent.recruitment_queue[0].remainingSeconds)>0 and float(independent.recruitment_queue[0].remainingSeconds)<float(long_job.totalSeconds),"Out-of-order completion preserves the earlier order's independently elapsed timer")
	independent.free()

func pair_gather_and_capacity() -> void:
	for level in [4,5,8]:
		var game: Node2D=make_game({}, {"spear":level})
		var job: Dictionary=queue(game,"spear")
		var expected: int=2 if level>=5 else 1
		check(int(job.quantity)==expected,"Permanent spear level "+str(level)+" fixes order quantity before payment")
		hold(game)
		tick(game,float(job.totalSeconds))
		check(game.units.size()==expected and game.recruitment_queue.is_empty(),"Paid production creates the committed spear quantity")
		var total_paid: int=0
		for unit in game.units: total_paid+=int(unit.paid)
		check(total_paid==cost("spear") and game.gold==10000-cost("spear"),"Two actors preserve one exact paid order cost")
		if expected==1:
			var unit: Dictionary=game.units[0]
			var home: Vector2=unit.position
			check(str(unit.combatState)=="gather","Solo output initially waits at its own base")
			tick(game,2.4)
			check(unit.position==home,"A solo soldier waits up to2.5 world seconds")
			tick(game,.15)
			check(str(unit.combatState)!="gather" and unit.position.distance_to(home)<.02 and unit.position!=home,"Solo release walks away after the bounded gather wait")
		else:
			check(int(game.units[0].id)!=int(game.units[1].id) and int(game.units[0].gatherGroupId)==int(game.units[1].gatherGroupId) and int(game.units[0].gatherGroupId)>0,"Spear pair gathers together and owns unique actor IDs")
			var previous: Array=game.units.map(func(unit: Dictionary): return unit.position)
			tick(game,.1)
			for index in range(game.units.size()): check(game.units[index].position.distance_to(previous[index])<=.011,"Gathered members move at actual bounded walking speed")
		game.free()
	var limited: Node2D=make_game({}, {"spear":5})
	limited.config.unitLimit=1
	var pair: Dictionary=queue(limited,"spear")
	var single: Dictionary=queue(limited,"samurai")
	hold(limited);tick(limited,float(pair.totalSeconds)+.025)
	check(limited.units.is_empty() and str(limited.recruitment_queue[0].status)=="waiting_capacity" and float(limited.recruitment_queue[0].remainingSeconds)==0.0,"A completed pair waits atomically at0 seconds instead of generating one missing actor")
	check(float(limited.recruitment_queue[1].remainingSeconds)<float(single.totalSeconds),"An unfinished job progresses even when the completed pair cannot fit")
	tick(limited,2)
	check(limited.units.size()==1 and str(limited.units[0].type)=="samurai" and limited.recruitment_queue.size()==1,"A capacity-blocked pair cannot block a different completed single order")
	check(limited.cancel_recruitment(int(pair.id)) and limited.gold==10000-cost("samurai"),"Capacity-wait cancellation refunds exactly its own incomplete order")
	limited.free()

func end_and_reentrance() -> void:
	for won in [false,true]:
		var game: Node2D=make_game()
		var first: Dictionary=queue(game,"spear")
		queue(game,"archer")
		hold(game);tick(game,.2)
		var results: Array=[]
		game.battle_finished.connect(func(result: Dictionary): results.append(result.duplicate(true)))
		game._finish(bool(won));game._finish(bool(won))
		check(game.gold==10000 and game.recruitment_queue.is_empty() and results.size()==1 and results[0].recruitmentQueue.is_empty(),"Win/fail ends with one result and refunds only incomplete orders")
		check(not game.cancel_recruitment(int(first.id)),"Post-result cancellation is stale")
		game.free()
	var game: Node2D=make_game()
	var old: Dictionary=queue(game,"spear")
	game.load_map(fixture())
	var fresh: Dictionary=queue(game,"spear")
	check(int(fresh.id)!=int(old.id) and not game.cancel_recruitment(int(old.id)) and game.recruitment_queue.size()==1,"New map resets wallet/production but keeps job IDs safe from old UI cancellation")
	game.free()
	var reentrant: Node2D=make_game()
	var initial: Dictionary=queue(reentrant,"spear")
	queue(reentrant,"samurai")
	hold(reentrant)
	var completions: Array=[]
	reentrant.game_event.connect(func(event: Dictionary):
		if str(event.type)=="recruited":
			completions.append(int(event.jobId))
			if completions.size()==1:
				reentrant.load_map(fixture())
				queue(reentrant,"spear")
	)
	tick(reentrant,float(initial.totalSeconds)+1)
	check(completions.size()==1 and reentrant.units.is_empty() and reentrant.recruitment_queue.size()==1 and reentrant.elapsed==0,"Completion callback changing map cannot spend old-world delta on a new production job")
	reentrant.free()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/recruitment-queue/"): push_error("Queue QA refuses the player's profile");quit(2);return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	all_maps()
	money_capacity_and_reservations()
	clocks_and_parallel()
	pair_gather_and_capacity()
	end_and_reentrance()
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"scope":"CPU-only real40map/all8 independent parallel production/out-of-order completion, authored deployment reservation, cost/refund/capacity0sec waiting, level5 spear pair, scaled/pause/study clocks, actual gather walking, pure snapshots and finish/load/reentrant callbacks. Main menu UI and GPU are verified separately."}
	var path: String="user://qa_recruitment_queue_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_recruitment_queue.json"
	var output: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("RECRUITMENT_QUEUE ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path(path))
	quit(0 if failures.is_empty() else 1)
