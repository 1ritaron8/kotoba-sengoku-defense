extends SceneTree
## Real campaign economy and selected recruitment; no injected funds, levels or wins.
## Run with APPDATA redirected inside this workspace. Profile guard rejects user data.

const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
const GroundCombat = preload("res://native/ground_combat.gd")
const STEP = 0.10
const MAX_STEPS = 40000
var failures: Array = []
var checks: int = 0
var maps: Array = []
var store: RefCounted
var campaign_results: Array = []
var training_log: Array = []
var army_usage: Dictionary = {}
var options: Array = []
var samples: Array = []
var candidate_positions: Array = []
var attempts_limit: int = 3
var stage_limit: int = 40
var started_at: int = 0
var learning_mode: String = "all"
var report_path: String = ""
var role_effect_checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	started_at = Time.get_ticks_msec()
	var workspace: String = ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(workspace):
		push_error("Campaign QA requires workspace-isolated APPDATA; refusing user profile: "+profile)
		quit(2)
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index]=="--limit": stage_limit = clampi(int(args[index+1]),1,40)
		if args[index]=="--attempts": attempts_limit = clampi(int(args[index+1]),1,3)
		if args[index]=="--learning-mode": learning_mode = str(args[index+1])
	if learning_mode not in ["all","mixed","none"]:
		push_error("--learning-mode must be all, mixed or none")
		quit(2)
		return
	report_path = "res://tests/qa_campaign_balance_%s.json" % learning_mode
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	maps.sort_custom(func(a,b): return int(a.stageNumber)<int(b.stageNumber))
	store = Store.new()
	store.save_path = "user://campaign-balance-%s-progress.json" % learning_mode
	if "--effects-only" in args:
		store.read_save()
		check(store.data.maps.size()==40,"Support-role checks reuse an actually completed campaign profile")
		check("monk" in store.unlocked_units() and "ninja" in store.unlocked_units(),"Both support roles were unlocked by real campaign clears")
		var effect_results: Array = []
		for id in ["monk","ninja"]:
			effect_results.append(probe_attack_effect(id))
		var report_data = JSON.parse_string(FileAccess.get_file_as_string(report_path))
		if report_data is Dictionary:
			report_data["roleEffectChecks"] = {"checks":checks,"failures":failures,"results":effect_results,"scope":"Real selected placement and live attacks after earned campaign progression; shipped initial combat wallet and legal per-wave rewards only."}
			var output: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
			output.store_string(JSON.stringify(report_data,"  "))
			output.close()
		print("CAMPAIGN_ROLE_EFFECTS ",JSON.stringify({"checks":checks,"failures":failures,"results":effect_results}))
		quit(0 if failures.is_empty() else 1)
		return
	# A fresh Store starts from shipped data, even on a repeated QA invocation.
	check(maps.size()==40,"Forty distinct campaign stages are available")
	check(store.unit_catalog.size()==8,"Eight shipped class definitions are configured")
	check(store.unlocked_units()==["archer","spear"],"Fresh campaign begins with two starter classes")
	check(store.army_level("archer")==1 and store.army_level("spear")==1,"First battle uses untrained starters")
	check(int(store.data.army.currency)==180,"Initial army wallet is the shipped 180 funds")
	for stage_index in range(mini(stage_limit,maps.size())):
		var stage: Dictionary = maps[stage_index]
		var before_levels: Dictionary = store.data.army.levels.duplicate(true)
		var before_unlocked: Array = store.unlocked_units().duplicate()
		var before_funds: int = int(store.data.army.currency)
		var attempts: Array = []
		var final_result: Dictionary = {}
		for attempt in range(attempts_limit):
			var result: Dictionary = play_stage(stage,attempt)
			attempts.append(result)
			final_result = result
			print("CAMPAIGN_BATTLE ",stage.id," attempt=",attempt+1," victory=",result.victory," wave=",result.wave," hp=",result.hp," kills=",result.kills," roles=",result.composition," permanent=",before_levels)
			if bool(result.victory): break
		if not bool(final_result.get("victory",false)):
			check(false,"Bot could not clear "+str(stage.id)+"; this is not proof that the map is impossible")
			campaign_results.append({"stageId":stage.id,"stageNumber":stage.stageNumber,"won":false,"attempts":attempts,"unlockedBefore":before_unlocked,"levelsBefore":before_levels,"fundsBefore":before_funds})
			write_report(profile)
			break
		check(stage_index!=0 or final_result.starterLevelOne,"Starter-only Lv1 victory is mandatory")
		var reward: Dictionary = store.complete_map(str(stage.id),{"seen":final_result.seen,"correct":final_result.correct,"attempts":final_result.answerAttempts})
		check(bool(reward.firstClear),"Each stage earns exactly one first-clear reward")
		check(int(store.data.army.currency)==before_funds+int(reward.currency),"Actual clear reward credits the army wallet")
		check(int(reward.currency)==140+int(stage.stageNumber)*8+mini(20,int(final_result.correct))*5,"Reward formula uses real correct answers only")
		for id in final_result.composition:
			army_usage[id] = int(army_usage.get(id,0))+int(final_result.composition[id])
		train_with_earned_funds(str(stage.id))
		campaign_results.append({"stageId":stage.id,"stageNumber":stage.stageNumber,"won":true,"attempts":attempts,"unlockedBefore":before_unlocked,"levelsBefore":before_levels,"fundsBefore":before_funds,"reward":reward,"fundsAfterTraining":store.data.army.currency,"levelsAfterTraining":store.data.army.levels.duplicate(true)})
		if stage_index%5==4:
			print("CAMPAIGN_CHECKPOINT stages=",stage_index+1," funds=",store.data.army.currency," levels=",store.data.army.levels)
		write_report(profile)
	var reopened = Store.new()
	reopened.save_path = store.save_path
	reopened.read_save()
	check(reopened.data.maps.size()==store.data.maps.size(),"Campaign clear count survives a real save reload")
	check(reopened.data.army==store.data.army,"Earned wallet, training levels and selection survive reload")
	if stage_limit==40 and failures.is_empty():
		check(store.data.maps.size()==40,"Actual forty-stage campaign is complete")
		check(store.unlocked_units().size()==8,"All eight classes unlock through earned clears")
		var effect_results: Array = []
		for id in ["monk","ninja"]:
			effect_results.append(probe_attack_effect(id))
		role_effect_checks = {"results":effect_results,"scope":"Actual live support-role effects after earned progression in this learning mode."}
	write_report(profile)
	print("CAMPAIGN_BALANCE mode=",learning_mode," maps_won=",store.data.maps.size(),"/",stage_limit," checks=",checks," failures=",failures.size()," seconds=",float(Time.get_ticks_msec()-started_at)/1000.0)
	quit(0 if failures.is_empty() else 1)

func play_stage(stage: Dictionary, attempt: int) -> Dictionary:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_seed(9876+attempt*997)
	game.configure_roster(store.unit_catalog,store.unlocked_units(),store.data.army.levels)
	game.load_map(stage)
	prepare_geometry(game,attempt)
	var composition: Dictionary = {}
	var correct: int = 0
	var unhinted: int = 0
	var hinted: int = 0
	var incorrect: int = 0
	var answer_attempts: int = 0
	var quiz_gold: int = 0
	var steps: int = 0
	var damage_log: Array = []
	var previous_hp: int = int(game.snapshot().hp)
	var starter_level_one: bool = store.unlocked_units()==["archer","spear"] and store.army_level("archer")==1 and store.army_level("spear")==1
	deploy_units(game,composition,attempt)
	game.start_battle()
	while not game.finished and steps<MAX_STEPS:
		if game.between_waves:
			var outcome: String = learning_outcome(game.wave)
			if outcome in ["correct","hinted"]:
				var before_reward: int = game.gold
				game.grant_reward(outcome)
				var amount: int = 70 if outcome=="correct" else 25
				check(game.gold==before_reward+amount,"The chosen answer outcome issues exactly its shipped reward")
				quiz_gold += amount
				correct += 1
				if outcome=="correct": unhinted += 1
				else: hinted += 1
			elif outcome=="wrong":
				incorrect += 1
			if outcome!="skip": answer_attempts += 1
			deploy_units(game,composition,attempt)
			game.continue_wave()
		elif steps%50==0:
			deploy_units(game,composition,attempt)
		game.advance_simulation(STEP)
		steps += 1
		var hp: int = 0
		for objective in game.objectives: hp += int(objective.hp)
		if hp<previous_hp:
			damage_log.append({"wave":game.wave,"seconds":game.elapsed,"hp":hp,"units":game.units.size(),"gold":game.gold})
		previous_hp = hp
	check(game.finished,"Battle completes within simulation limit: "+str(stage.id))
	check(correct<=game.total_waves-1,"One legal quiz reward per completed non-final wave")
	check(quiz_gold==unhinted*70+hinted*25,"Combat wallet only receives its actual correct or hinted answer gold")
	check(game.learning_supports.is_empty(),"Campaign baseline receives no injected learning-support damage aura")
	if learning_mode=="none":
		check(correct==0 and quiz_gold==0 and answer_attempts==0,"None mode proceeds with zero learning reward and no answer assumptions")
	for unit in game.units:
		check(str(unit.type) in store.unlocked_units(),"Every selected deployment is actually unlocked")
		check(int(unit.campaignLevel)==store.army_level(str(unit.type)),"Deployment retains its real permanent level")
		check(int(unit.evolution)==int(store.army_evolution(str(unit.type)).stage),"Deployment evolution comes from permanent training")
	var result: Dictionary = {"victory":game.victory,"finished":game.finished,"wave":game.wave,"hp":game.snapshot().hp,"kills":game.kills,"seconds":game.elapsed,"gold":game.gold,"units":game.units.size(),"composition":composition,"correct":correct,"unhintedCorrect":unhinted,"hintedCorrect":hinted,"incorrect":incorrect,"answerAttempts":answer_attempts,"quizGold":quiz_gold,"learningMode":learning_mode,"seen":0,"starterLevelOne":starter_level_one,"damageLog":damage_log,"strategy":attempt,"objectives":[]}
	for objective in game.objectives:
		result.objectives.append({"id":objective.id,"hp":objective.hp,"maxHp":objective.maxHp})
	if not game.victory:
		result["diagnostics"] = coverage_diagnostics(game)
	game.free()
	return result

func learning_outcome(completed_wave: int) -> String:
	if learning_mode=="none": return "skip"
	if learning_mode=="all": return "correct"
	# A deterministic middle-accuracy run: unhinted / wrong / hinted / wrong.
	return "correct" if completed_wave%4==1 else "hinted" if completed_wave%4==3 else "wrong"

func prepare_geometry(game: Node2D, strategy: int) -> void:
	samples.clear()
	candidate_positions.clear()
	options.clear()
	for path_index in range(game.paths.size()):
		var path: Dictionary = game.paths[path_index]
		var length: float = 0.0
		for index in range(path.points.size()-1): length += path.points[index].distance_to(path.points[index+1])
		var distance_before: float = 0.0
		for index in range(path.points.size()-1):
			var start: Vector2 = path.points[index]
			var end: Vector2 = path.points[index+1]
			var segment: float = start.distance_to(end)
			var count: int = maxi(1,ceili(segment/0.023))
			for step in range(count):
				var t: float = (float(step)+0.5)/count
				var progress: float = (distance_before+segment*t)/maxf(length,0.001)
				var weight: float = (segment/count)/maxf(length,0.001)
				weight *= 1.0+(0.4 if strategy==0 else 1.4 if strategy==1 else 0.1)*progress
				samples.append({"point":start.lerp(end,t),"weight":weight,"path":path_index,"progress":progress,"routeDistance":distance_before+segment*t})
			distance_before += segment
	for zone in game.zones:
		var radius: float = float(zone.get("r",0.08))
		candidate_positions.append(zone.position)
		for ring in range(1,4):
			for index in range(12):
				var angle: float = TAU*float(index)/12
				candidate_positions.append(zone.position+Vector2(cos(angle),sin(angle))*radius*float(ring)/3)
	var seen_options: Dictionary = {}
	for id in store.unlocked_units():
		var definition: Dictionary=store.unit_definition(id)
		var preview: Dictionary={"type":id,"definition":definition,"campaignLevel":store.army_level(id),"elevation":0}
		var stats: Dictionary=game._stats(preview)
		for requested in candidate_positions:
			var saved_pending: Dictionary=game.pending
			game.pending=preview.duplicate(true)
			game.pending.cost=game.recruit_cost(id)
			game.pending.preview=true
			var placement: Dictionary=game.placement_preview(requested)
			game.pending=saved_pending
			if not bool(placement.get("valid",false)): continue
			var position: Vector2=game._point(placement.position)
			var key: String="%s/%.4f/%.4f" % [id,position.x,position.y]
			if seen_options.has(key): continue
			seen_options[key]=true
			var actor: Dictionary=preview.duplicate(true)
			actor.merge(placement,true)
			actor.position=position
			var covers: Array=[]
			for index in range(samples.size()):
				if sample_covered(actor,samples[index],float(stats.range)): covers.append(index)
			options.append({"type":id,"position":position,"requestedPosition":requested,"covers":covers,"cost":game.recruit_cost(id),"dps":effective_dps(actor,stats,game)})

func sample_covered(unit: Dictionary, sample: Dictionary, attack_range: float) -> bool:
	if GroundCombat.is_ground(str(unit.type)):
		return int(unit.get("postPathIndex",sample.path))==int(sample.path) and unit.position.distance_to(sample.point)<=maxf(attack_range,.09)
	return unit.position.distance_to(sample.point)<=attack_range

func effective_dps(unit: Dictionary, stats: Dictionary, _game: Node2D) -> float:
	return float(stats.damage)/float(stats.interval)

func deploy_units(game: Node2D, composition: Dictionary, _strategy: int) -> void:
	for attempt in range(24):
		var cover: Array[float]=current_cover(game)
		var ranked: Array=[]
		for option in options:
			if game.gold<int(option.cost): continue
			var value: float=0.0
			for index in option.covers: value+=float(samples[index].weight)/(1.0+cover[index]/35.0)
			ranked.append({"option":option,"score":value*float(option.dps)/maxf(1.0,float(option.cost))})
		ranked.sort_custom(func(a,b): return float(a.score)>float(b.score))
		var placed: bool=false
		for candidate in ranked:
			var option: Dictionary=candidate.option
			if not game.begin_placement(str(option.type)): continue
			if game.pending.is_empty(): placed=true
			elif bool(game.placement_preview(option.requestedPosition).get("valid",false)):
				placed=game.place_unit(option.requestedPosition.x,option.requestedPosition.y)
			if placed:
				composition[str(option.type)]=int(composition.get(str(option.type),0))+1
				break
			game.cancel_recruit()
		if not placed: break


func current_cover(game: Node2D) -> Array[float]:
	var result: Array[float] = []
	result.resize(samples.size())
	result.fill(0.0)
	for unit in game.units:
		if not game.ground_combat.active_support(unit): continue
		var stats: Dictionary = game._stats(unit)
		var dps: float = effective_dps(unit,stats,game)
		for index in range(samples.size()):
			if sample_covered(unit,samples[index],float(stats.range)): result[index] += dps
	return result

func train_with_earned_funds(stage_id: String) -> void:
	var guard: int = 0
	while guard<40:
		guard += 1
		var best: String = ""
		var best_score: float = -INF
		for id in store.unlocked_units():
			var level: int = store.army_level(id)
			var cost: int = store.army_upgrade_cost(id)
			if level>=Store.MAX_ARMY_LEVEL or cost>int(store.data.army.currency): continue
			var before: Dictionary = store.army_stats(id)
			var after: Dictionary = store.army_stats(id,level+1)
			var gain: float = float(after.damage)/float(after.interval)-float(before.damage)/float(before.interval)
			var usage: float = sqrt(float(army_usage.get(id,0))+3.0)
			var score: float = gain*usage/cost
			if score>best_score:
				best_score = score
				best = id
		if best.is_empty(): break
		var before_funds: int = int(store.data.army.currency)
		var cost: int = store.army_upgrade_cost(best)
		var result: Dictionary = store.upgrade_army_unit(best)
		check(bool(result.ok),"Earned-fund permanent training succeeds")
		if not bool(result.ok): break
		check(int(store.data.army.currency)==before_funds-cost,"Permanent training spends actual army funds exactly once")
		training_log.append({"afterStage":stage_id,"type":best,"level":store.army_level(best),"cost":cost,"funds":store.data.army.currency,"evolved":result.evolved})

func coverage_diagnostics(game: Node2D) -> Dictionary:
	var cover: Array[float] = current_cover(game)
	var by_path: Array = []
	for path_index in range(game.paths.size()):
		var uncovered: int = 0
		var terminal_uncovered: int = 0
		var count: int = 0
		var mean_dps: float = 0.0
		for index in range(samples.size()):
			if int(samples[index].path)!=path_index: continue
			count += 1
			mean_dps += cover[index]
			if cover[index]<0.001:
				uncovered += 1
				if float(samples[index].progress)>0.70: terminal_uncovered += 1
		by_path.append({"path":path_index,"samples":count,"uncovered":uncovered,"terminalUncovered":terminal_uncovered,"meanEffectiveDps":mean_dps/maxi(1,count)})
	var units: Array = []
	for unit in game.units:
		var stats: Dictionary = game._stats(unit)
		units.append({"type":unit.type,"campaignLevel":unit.campaignLevel,"evolution":unit.evolution,"x":unit.position.x,"y":unit.position.y,"range":stats.range,"dps":float(stats.damage)/float(stats.interval)})
	return {"coverage":by_path,"units":units,"legalOptions":options.size(),"strategyLimitation":"Greedy sampled lane coverage and role scoring; bot failure is not a player-impossibility proof."}

func probe_attack_effect(id: String) -> Dictionary:
	var stage: Dictionary = maps[9]
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_seed(9876)
	game.configure_roster(store.unit_catalog,store.unlocked_units(),store.data.army.levels)
	game.load_map(stage)
	prepare_geometry(game,1)
	var best: Dictionary = {}
	var best_score: float = -INF
	for option in options:
		if str(option.type)!=id: continue
		var score: float = 0.0
		for index in option.covers: score += float(samples[index].weight)
		if score>best_score:
			best_score = score
			best = option
	var initial_funds: int = game.gold
	check(not best.is_empty(),id+" has a legal real-range placement")
	check(game.recruit(id),id+" can be explicitly recruited after earned unlock")
	check(game.gold==initial_funds-int(store.unit_definition(id).cost),id+" pays its actual shipped recruitment cost")
	check(game.place_unit(float(best.position.x),float(best.position.y)),id+" is deployed through the public placement API")
	var unit: Dictionary = game.units[0]
	check(int(unit.campaignLevel)==store.army_level(id),id+" uses earned campaign training")
	var observed: Dictionary = {}
	var legal_rewards: int = 0
	var legal_reward_gold: int = 0
	var steps: int = 0
	game.start_battle()
	while observed.is_empty() and not game.finished and steps<12000:
		if game.between_waves:
			var outcome: String = learning_outcome(game.wave)
			if outcome in ["correct","hinted"]:
				game.grant_reward(outcome)
				legal_rewards += 1
				legal_reward_gold += 70 if outcome=="correct" else 25
			game.continue_wave()
		var prior: Array = []
		for enemy in game.enemies:
			if float(enemy.hp)>0:
				prior.append({"reference":enemy,"before":float(enemy.hp),"maxHp":float(enemy.maxHp),"armor":float(enemy.armor),"kind":enemy.kind})
		var attack_plan: Dictionary = unit.get("attackPlan",{})
		var planned_damage: float = float(attack_plan.get("damage",game._stats(unit).damage))
		game.advance_simulation(0.025)
		steps += 1
		for before in prior:
			var enemy: Dictionary = before.reference
			if bool(enemy.get("escaped",false)) or float(enemy.hp)>=float(before.before): continue
			var damage: float = float(before.before)-float(enemy.hp)
			if id=="monk" and float(enemy.get("slowClock",0.0))>0.0:
				check(is_equal_approx(float(enemy.slowFactor),0.75),"Live monk hit applies 25 percent enemy slowing")
				check(absf(float(enemy.slowClock)-1.5)<0.026,"Live monk hit starts the actual 1.5-second slow duration")
				observed = {"type":id,"kind":before.kind,"wave":game.wave,"seconds":game.elapsed,"campaignLevel":unit.campaignLevel,"evolution":unit.evolution,"paid":initial_funds-game.gold+legal_reward_gold,"legalQuizRewards":legal_rewards,"legalQuizGold":legal_reward_gold,"hpBefore":before.before,"hpAfter":enemy.hp,"damage":damage,"slowFactor":enemy.slowFactor,"slowSeconds":enemy.slowClock}
			elif id=="ninja" and float(before.before)<=float(before.maxHp)*0.30:
				var expected: float = planned_damage*1.5*(1.0-float(before.armor))
				check(absf(damage-expected)<0.001,"Live ninja attack applies the actual 50 percent finisher bonus")
				observed = {"type":id,"kind":before.kind,"wave":game.wave,"seconds":game.elapsed,"campaignLevel":unit.campaignLevel,"evolution":unit.evolution,"paid":int(store.unit_definition(id).cost),"legalQuizRewards":legal_rewards,"hpBefore":before.before,"maxHp":before.maxHp,"hpAfter":enemy.hp,"baseAttackDamage":planned_damage,"armor":before.armor,"damage":damage,"expectedDamage":expected}
	check(not observed.is_empty(),id+" live attack effect is observed without currency or enemy-stat injection")
	if observed.is_empty():
		observed = {"type":id,"observed":false,"wave":game.wave,"seconds":game.elapsed,"finished":game.finished,"hp":game.snapshot().hp,"placement":{"x":best.position.x,"y":best.position.y}}
	game.free()
	return observed

func write_report(profile: String) -> void:
	var report: Dictionary = {"checks":checks,"failures":failures,"learningMode":learning_mode,"mapsWon":store.data.maps.size(),"requestedMaps":stage_limit,"profile":profile,"savePath":store.save_path,"startArmyFunds":180,"actualArmyFunds":store.data.army.currency,"unlocked":store.unlocked_units(),"levels":store.data.army.levels,"armyUsage":army_usage,"training":training_log,"stages":campaign_results,"roleEffectChecks":role_effect_checks,"elapsedSeconds":float(Time.get_ticks_msec()-started_at)/1000.0,"scope":"Selected eight-class deployment with real shipped economy. Modes: all correct; mixed correct/wrong/hinted/wrong; none no answer gold. No funds/levels/map wins or learning auras injected.","limitations":["Greedy automated strategy cannot prove that a lost map is impossible.","This checks a deterministic strategy and answer pattern, not the enjoyment or learning retention of human users.","No repeated clears are farmed for training funds."]}
	var file: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	if learning_mode=="all":
		file = FileAccess.open("res://tests/qa_campaign_balance.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
		file.close()
