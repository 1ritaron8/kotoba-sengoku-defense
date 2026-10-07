extends "res://tests/qa_queue_campaign_balance.gd"
## Drive native Main answers and an actual five-minute starter battle.
## Only the player's ordinary placement, production APIs are used.
var app: Node
var learned_inputs: Array = []
var replay_inputs: Array = []
var outcomes: Array = []
var learner_policy: String = "correct"
var learning_probe_radius: float = 0.0
var learning_probe_hp_growth: float = -1.0
var starter_policies: Array = [
	{"name":"learning_crossfire_eight","bows":8,"front":1,"lateFront":2,"cluster":true,"initialBows":2},
	{"name":"learning_lane_screen","bows":6,"front":2,"lateFront":4,"cluster":false,"balanced":true,"initialBows":2}
]

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/") or DisplayServer.get_name()!="headless":
		push_error("Starter balance QA requires a workspace-only headless profile")
		quit(2)
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index]=="--learner": learner_policy=str(args[index+1])
		if args[index]=="--policy": starter_policies=[starter_policies[clampi(int(args[index+1]),0,starter_policies.size()-1)]]
		if args[index]=="--diagnostic-radius": learning_probe_radius=float(args[index+1])
		if args[index]=="--diagnostic-hp-growth": learning_probe_hp_growth=float(args[index+1])
	if learner_policy not in ["correct","hinted"]:
		push_error("Learner must be correct or hinted")
		quit(2)
		return
	if learning_probe_hp_growth>=0 and (not is_equal_approx(learning_probe_hp_growth,8.0) or not is_equal_approx(learning_probe_radius,.16)):
		push_error("The approved HP growth probe is eight, combined with radius .16")
		quit(2)
		return
	if learning_probe_radius!=0.0 and not is_equal_approx(learning_probe_radius,.16):
		push_error("Only the previously approved .16 acquisition probe may be run")
		quit(2)
		return
	if learning_probe_radius>0:
		starter_policies=[{"name":"learning_safe_crossfire_ten","bows":10,"front":1,"lateFront":2,"cluster":true,"initialBows":2,"safeGap":.17}]
	first_stage_bytes=FileAccess.get_file_as_string("res://native/maps.json")
	for policy in starter_policies:
		active_policy=policy
		var result: Dictionary=await play_learning_policy()
		outcomes.append(result)
		print("STARTER_LEARNING_BATTLE ",JSON.stringify(result))
		write_learning_report()
		if bool(result.victory): break
	check(not outcomes.is_empty() and bool(outcomes[-1].victory),"Actual starter input policy survives five minutes with legal answered-task rewards")
	check(FileAccess.get_file_as_string("res://native/maps.json")==first_stage_bytes,"All forty authored map configurations remain unchanged")
	write_learning_report()
	print("STARTER_LEARNING_QA checks=",checks," failures=",failures.size()," strategies=",outcomes.size())
	quit(0 if failures.is_empty() else 1)

func settle_transition() -> void:
	for unused in range(16):
		if not app.learning_transition.is_busy(): break
		var tween: Tween=app.learning_transition.animation
		if tween!=null and tween.is_valid(): tween.custom_step(1.0)
		await process_frame
	check(not app.learning_transition.is_busy(),"Native learning transition finishes before input")

func answer_native_task(game: Node2D) -> void:
	await settle_transition()
	var task: Dictionary=app.quiz_task.duplicate(true)
	check(not task.is_empty() and game.between_waves,"A real completed time window issues a native Main task")
	if task.is_empty(): return
	var before_time: float=game.elapsed
	var before_gold: int=game.gold
	var answer: String=str(task.answerId)
	var is_context: bool=bool(app.context_task_active)
	var valid_choice: bool=false
	for choice in task.get("choices",[]):
		if str(choice.id)==answer: valid_choice=true
	check(valid_choice,"The automated input selects an actually visible choice")
	if learner_policy=="hinted": app._quiz_hint()
	if is_context: app._answer_context(answer)
	else: app._answer_quiz(answer)
	check(bool(app.quiz_resolved) and bool(app.quiz_outcome_correct),"Native Main accepts and persists the answer")
	var reward: int=25 if learner_policy=="hinted" else 70
	check(game.gold==before_gold+reward,"Only the native correct or helped answer supply is credited")
	var support: Dictionary={}
	if is_context:
		for aura in game.learning_supports:
			if str(aura.attemptId)==str(task.id): support=aura.duplicate(true)
		check(not support.is_empty(),"Correct native location task creates its authored local support")
	var row: Dictionary={"seconds":before_time,"wave":game.wave,"taskId":str(task.id),"kind":str(task.kind),"itemId":str(task.itemId),"question":task.get("questionItem",{}),"choices":task.get("choices",[]),"selectedId":answer,"correct":bool(app.quiz_outcome_correct),"hinted":bool(app.quiz_hinted),"goldBefore":before_gold,"goldAfter":game.gold,"supply":reward,"support":support}
	learned_inputs.append(row)
	await settle_transition()
	var after_gold: int=game.gold
	if is_context: app._answer_context(answer)
	else: app._answer_quiz(answer)
	check(game.gold==after_gold,"A repeated result click cannot credit a second supply")
	check(absf(game.elapsed-before_time)<.000001,"Learning presentation and actual answer do not consume combat time")
	app._continue_battle()
	await settle_transition()
	check(app.quiz_task.is_empty() and not game.between_waves and game.input_enabled,"Native return action resumes battle and recruitment input")

func play_learning_policy() -> Dictionary:
	app=load("res://native/main.tscn").instantiate()
	if learning_probe_radius>0:
		# The entire native Main remains intact. Its Game construction is the
		# single substituted operation, allowing a test-only acquisition probe.
		var source: String=FileAccess.get_file_as_string("res://native/main.gd")
		check(source.count("game = Battle.new()")==1,"Diagnostic replaces exactly one native Game constructor")
		var probe_main: GDScript=GDScript.new()
		probe_main.source_code=source.replace("game = Battle.new()","game = qa_game_factory.new()")+"\nvar qa_game_factory: Script\n"
		check(probe_main.reload()==OK,"The otherwise unchanged native Main compiles with its diagnostic factory")
		app.set_script(probe_main)
		app.qa_game_factory=RadiusDiagnostic
	app.progress.save_path="user://starter-learning-%s-%s-%d.json" % [learner_policy,active_policy.name,Time.get_ticks_usec()]
	root.add_child(app)
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.atmosphere.set_process(false)
	app.combat_feedback.set_process(false)
	await process_frame
	app.progress.data.settings.voice=false
	app.progress.data.settings.music=false
	app.progress.data.settings.effects=false
	app.player.stop()
	app.battle_audio.set_enabled(false)
	app._stop_narration()
	app.battle_minutes=5
	app._select_map(0)
	await process_frame
	var game: Node2D=app.game
	if learning_probe_radius>0:
		game.intrusion_radius=learning_probe_radius
		game.basic_hp_growth=learning_probe_hp_growth
	game.set_process(false)
	game.set_seed(9876)
	app.lesson_session.rng.seed=9876
	store=app.progress
	maps=app.maps
	balance_game=game
	check(store.data.maps.is_empty() and store.unlocked_units()==["archer","spear"],"Fresh account offers only the genuine two starter classes")
	check(store.army_level("archer")==1 and store.army_level("spear")==1,"Starter permanent levels are untrained level one")
	check(game.gold==280 and int(game.config.initialGold)==280,"First battle starts with its original combat wallet")
	check(str(game.config.id)=="basic-forest" and game.battle_minutes==5,"The actual Main launches the first authored map in five-minute mode")
	var levels_before: Dictionary=store.data.army.levels.duplicate(true)
	var funds_before: int=int(store.data.army.currency)
	observed_events.clear()
	learned_inputs.clear()
	replay_inputs.clear()
	bow_order_lanes.clear()
	game.game_event.connect(func(event: Dictionary): capture_learning_event(game,event))
	prepare_geometry(game,1 if bool(active_policy.cluster) else 0)
	var composition: Dictionary={}
	app._begin_battle()
	check(app.battle_started and not game.finished,"Actual Main start action begins the battle")
	policy_orders(game,composition)
	check(game.units.is_empty() and not game.recruitment_queue.is_empty(),"Paid initial orders await native production timers")
	var steps: int=0
	var last_order: float=game.elapsed
	var peak_units: int=0
	var peak_enemies: int=0
	var last_hp: int=objective_health(game)
	var objective_hits: Array=[]
	while not game.finished and steps<4000:
		if game.between_waves:
			await answer_native_task(game)
			policy_orders(game,composition)
			last_order=game.elapsed
		elif game.elapsed-last_order>=.75-.000001:
			policy_orders(game,composition)
			last_order=game.elapsed
		var before: float=game.elapsed
		game.advance_simulation(STEP)
		app._process(game.elapsed-before)
		steps+=1
		peak_units=maxi(peak_units,game.units.size())
		peak_enemies=maxi(peak_enemies,game.enemies.size())
		var hp: int=objective_health(game)
		if hp<last_hp: objective_hits.append({"seconds":game.elapsed,"wave":game.wave,"hp":hp,"gold":game.gold,"living":game.units.size(),"producing":game.recruitment_queue.size()})
		last_hp=hp
		# Flush native UI deferred deletions; it never advances disabled Game.
		if steps%10==0: await process_frame
	var result: Dictionary=summarize_learning_battle(game,composition,objective_hits)
	result.merge({"policy":active_policy.name,"learnerPolicy":learner_policy,"initialGold":280,"permanentLevel":1,"peakUnits":peak_units,"peakEnemies":peak_enemies,"answers":learned_inputs.duplicate(true),"inputs":replay_inputs.duplicate(true),"wordsSeen":app.seen_this_run.size(),"firstClearReward":app.last_campaign_reward.duplicate(true),"diagnosticOnly":learning_probe_radius>0,"intrusionRadius":learning_probe_radius if learning_probe_radius>0 else .23,"hpGrowthOverride":learning_probe_hp_growth>=0,"hpGrowthFromWave3":learning_probe_hp_growth if learning_probe_hp_growth>=0 else 10.0},true)
	check(game.finished,"Native combat reaches an actual outcome without a forced finish")
	check(int(result.learningGold)==(25 if learner_policy=="hinted" else 70)*learned_inputs.size(),"Total answer supply equals the accepted native task receipts")
	check(store.data.army.levels==levels_before,"Battlefield purchases cannot change campaign permanent levels")
	check(int(composition.get("archer",0))>0 and int(composition.get("spear",0))>0,"Actual starter combat uses stationary bows and marching infantry")
	check(peak_units<=14 and peak_enemies<=36,"Actual production and enemies respect native caps")
	if game.victory:
		check(absf(game.elapsed-300.0)<.000001 and objective_health(game)>0,"Actual army defends the authored objective for exactly five combat minutes")
		check(bool(app.last_campaign_reward.get("firstClear",false)),"Native Main records its real first-clear receipt")
		check(int(store.data.army.currency)==funds_before+int(app.last_campaign_reward.get("currency",0)),"Only the actual campaign clear credits permanent army funds")
	else:
		check(store.data.maps.is_empty() and int(store.data.army.currency)==funds_before,"A failed battle cannot add campaign clearance or army money")
	app.player.stop()
	app.player.stream=null
	app.battle_audio.shutdown()
	app.queue_free()
	await process_frame
	app=null
	return result

func capture_learning_event(game: Node2D, event: Dictionary) -> void:
	collect_event(game,event)
	if str(event.type) in ["recruitment_queued","recruitment_cancelled"]:
		replay_inputs.append(event.duplicate(true))

func summarize_learning_battle(game: Node2D, composition: Dictionary, objective_hits: Array) -> Dictionary:
	var income: int=0
	var paid: int=0
	var refunds: int=0
	var born: Dictionary={}
	var casualties: Dictionary={}
	var emplacements: Dictionary={}
	var waves: Dictionary={}
	var objective_by_path: Dictionary={}
	for event in observed_events:
		var wave_key: int=int(event.wave)
		if not waves.has(wave_key): waves[wave_key]={"kills":0,"casualties":0,"damageDealt":0.0,"damageTaken":0.0,"objectiveDamage":0}
		var row: Dictionary=waves[wave_key]
		match str(event.type):
			"killed":
				income+=int(event.reward)
				row.kills=int(row.kills)+1
				if emplacements.has(int(event.actorId)): emplacements[int(event.actorId)].kills=int(emplacements[int(event.actorId)].kills)+1
			"waveend": income+=40+int(event.wave)*3
			"trait-supply": income+=int(game.config.trait.get("waveGold",{}).get("amount",0))
			"recruitment_queued": paid+=int(event.cost)
			"recruitment_cancelled": refunds+=int(event.get("refund",0))
			"placed","recruited":
				born[str(event.unitType)]=int(born.get(str(event.unitType),0))+int(event.get("quantity",1))
				if str(event.unitType)=="archer": emplacements[int(event.actorId)]={"id":int(event.actorId),"position":event.position,"damageDealt":0.0,"damageTaken":0.0,"kills":0,"deathTime":-1.0}
			"unit_fallen":
				casualties[str(event.unitType)]=int(casualties.get(str(event.unitType),0))+1
				row.casualties=int(row.casualties)+1
				if emplacements.has(int(event.actorId)): emplacements[int(event.actorId)].deathTime=float(event.time)
			"hit":
				var friendly: bool=str(event.get("victimSide",""))=="friendly"
				var damage: float=float(event.get("damage",0))
				var key: String="damageTaken" if friendly else "damageDealt"
				row[key]=float(row[key])+damage
				var owner_id: int=int(event.get("victimId",-1)) if friendly else int(event.get("actorId",-1))
				if emplacements.has(owner_id): emplacements[owner_id][key]=float(emplacements[owner_id][key])+damage
			"objective_hit":
				row.objectiveDamage=int(row.objectiveDamage)+int(event.damage)
				var route: int=int(event.get("qaActorPath",-1))
				objective_by_path[route]=int(objective_by_path.get(route,0))+int(event.damage)
	var learning_gold: int=0
	for answer in learned_inputs: learning_gold+=int(answer.supply)
	for unit in game.units:
		check(int(unit.campaignLevel)==1,"Every surviving actor retains its native permanent starter level")
	var conserved: bool=game.gold==280+income+learning_gold-paid+refunds
	check(conserved,"Actual queue, replacement, answered supply and cancellation receipts conserve the wallet")
	return {"mapId":str(game.config.id),"modeMinutes":5,"victory":game.victory,"seconds":game.elapsed,"hp":objective_health(game),"kills":game.kills,"gold":game.gold,"income":income,"learningGold":learning_gold,"spending":paid,"refunds":refunds,"walletConserved":conserved,"ordered":composition.duplicate(true),"born":born,"casualties":casualties,"waves":waves,"objectiveDamageByPath":objective_by_path,"emplacements":emplacements.values(),"objectiveHits":objective_hits}

func write_learning_report() -> void:
	var suffix: String="_radius16" if learning_probe_radius>0 else ""
	if learning_probe_hp_growth>=0: suffix+="_hp8"
	var output: FileAccess=FileAccess.open("res://tests/qa_starter_learning_balance_"+learner_policy+suffix+".json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":outcomes,"scope":"CPU native Main issued answers and native five-minute starter combat: actual 280 wallet, archer/spear unlocks, permanent Lv1, parallel production delays and actual casualties. Scripted correct input does not prove human enjoyment or language ability. DiagnosticOnly uses a test-only Game factory with radius .16; HP growth changes to eight after the first two waves only when hpGrowthOverride is true. Native damage, rewards, paths, production files and 10/20-minute modes remain unchanged."},"\t"))
	output.close()
