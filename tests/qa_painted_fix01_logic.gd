extends SceneTree
## Focused component fixtures only. No Main/account, no saved player data.
const Battle = preload("res://native/game.gd")
const Stage = preload("res://native/painted_stage.gd")
const Growth = preload("res://native/unit_growth.gd")
const Actors = preload("res://native/painted_actor_renderer.gd")
const OUTPUT: String = "res://tests/profiles/painted-game-fix-01"
var catalog: Array=[]
var shipped: Dictionary={}
var checks: Array=[]
var failures: Array=[]
var evidence: Dictionary={}
var output: String=""
var started: int=0
var source_hashes: Dictionary={}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, note: String) -> bool:
	checks.append({"pass":ok,"note":note})
	if not ok: failures.append(note);push_error("FIX01_LOGIC "+note)
	return ok

func hash_sources() -> Dictionary:
	var hashes: Dictionary={}
	for folder in ["res://native","res://assets/characters/painted-v1","res://assets/painted-battlefield"]:
		for filename in DirAccess.get_files_at(folder):
			if filename.get_extension() in ["gd","json","png"]:
				var path: String=folder.path_join(filename)
				hashes[path]=FileAccess.get_sha256(path)
	hashes["res://tests/qa_painted_fix01_logic.gd"]=FileAccess.get_sha256("res://tests/qa_painted_fix01_logic.gd")
	return hashes

func persist(reason: String) -> void:
	var file: FileAccess=FileAccess.open(output.path_join("logic-report.json"),FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"status":"passed" if reason=="complete" and failures.is_empty() else "partial_or_failed","reason":reason,"checks":checks,"failures":failures,"evidence":evidence,"sources":source_hashes,"sourcesAtEnd":hash_sources(),"wallSeconds":float(Time.get_ticks_usec()-started)/1000000.0,"engine":Engine.get_version_info(),"scope":"Explicit deterministic component fixtures; injected10000gold, all-active roster and stated positions/HP/clocks. NOT earned unlocks, natural economy, rendered performance or user-path acceptance. No player save access."},"  "))
		file.close()

func copy_damage_event(game: Node2D, rows: Array, row: Dictionary) -> void:
	var copied: Dictionary=row.duplicate(true)
	if str(row.get("type",""))=="hit":
		var victims: Array=game.enemies if str(row.get("victimSide",""))=="enemy" else game.units
		for victim in victims:
			if int(victim.id)==int(row.get("victimId",-1)):
				copied["observedVictimHpAtSignal"]=float(victim.hp)
				break
	rows.append(copied)

func flat_map() -> Dictionary:
	return {"id":"fix01-flat-fixture","stageNumber":1,"theme":"forest","trainingOnly":true,"initialGold":10000,"totalWaves":20,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.10,"y":.5},{"x":.90,"y":.5}]}],"objectives":[{"id":"main","x":.90,"y":.5,"hp":1000}],"buildZones":[{"id":"north","x":.50,"y":.64,"slotPositions":[{"x":.487,"y":.64},{"x":.513,"y":.64}],"r":.024,"guardRadius":.19,"slotCapacity":2,"placementRole":"ranged","acceptedUnitTypes":["archer","gunner"]},{"id":"south","x":.50,"y":.36,"slotPositions":[{"x":.487,"y":.36},{"x":.513,"y":.36}],"r":.024,"guardRadius":.19,"slotCapacity":2,"placementRole":"ranged","acceptedUnitTypes":["archer","gunner"]}],"tactics":{"groundPosts":[]}}

func make_game(levels: Dictionary={}, painted: bool=false, training: bool=true) -> Node2D:
	var map: Dictionary=Stage.apply(shipped) if painted else flat_map()
	map["initialGold"]=10000
	map["trainingOnly"]=training
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	var roster: Array=[]
	for definition in catalog:
		if bool(definition.get("active",true)): roster.append(str(definition.id))
	game.configure_roster(catalog,roster,levels)
	game.load_map(map,10)
	game.set_seed(9876)
	game.start_battle()
	# Suppress natural spawning ONLY in this explicitly labelled component fixture.
	game.enemies.clear()
	game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear()
	game.spawn_clock=10000
	return game

func tick(game: Node2D, seconds: float, delta: float=.025) -> void:
	for unused in range(ceili(seconds/delta)):
		if Time.get_ticks_usec()-started>90000000: persist("deadline");quit(2);return
		game.advance_simulation(delta*float(game.speed))

func hostile(game: Node2D, point: Vector2, kind: String="raider") -> Dictionary:
	var enemy: Dictionary=game._spawn_enemy(kind,1,{"originKind":"raider","pathIndex":0})
	enemy.position=point
	enemy.pointIndex=1
	enemy.routeProgress=maxf(0,point.x-.1)
	enemy.ingressActive=false
	return enemy

func paid_spears(game: Node2D, quantity: int) -> Array:
	for unused in range(quantity): check(game.begin_placement("spear",0),"Fixture pays a spear order")
	game._advance_recruitment(1.31)
	return game.units.filter(func(unit: Dictionary): return str(unit.type)=="spear")

func growth_and_slots() -> void:
	for level in [1,4,8]: check(Growth.recruit_quantity("spear",level)==({1:1,4:3,8:5}[level]),"Spear squad quantity at level "+str(level))
	check(Growth.recruit_quantity("archer",1)==1 and Growth.recruit_quantity("archer",5)==2,"Archer middle growth recruits two")
	var game: Node2D=make_game({"archer":5},true)
	var posts: Array=game.shooting_position_snapshot()
	check(posts.size()==8,"Shipped painted stage has eight posts")
	var high: int=0
	var low: int=0
	for post in posts:
		check(int(post.slotCapacity)==2 and int(post.available)==2 and post.acceptedUnitTypes.has("archer") and post.acceptedUnitTypes.has("gunner"),"Two shared shooter slots: "+str(post.id))
		if int(post.rangeBonusPercent)==24: high+=1
		if int(post.rangeBonusPercent)==12: low+=1
		check(bool(game.submit_deployment("archer",Vector2(post.x,post.y)).get("ok",false)),"Two-person archer reservation accepted: "+str(post.id))
	check(high==2 and low==6,"Two high +24% and six roadside +12% range posts")
	var reserved: int=0
	for post in game.shooting_position_snapshot(): reserved+=int(post.reserved)
	check(reserved==16,"All sixteen actual slots reserve without overlap")
	var previews: Array=game.production_preview_snapshot()
	var expected: Dictionary={}
	for preview in previews: expected[int(preview.jobId)]=preview.memberPositions.duplicate()
	if not previews.is_empty():
		var cancelled: int=int(previews[0].jobId)
		var wallet: int=game.gold
		check(game.cancel_recruitment(cancelled) and not game.cancel_recruitment(cancelled),"Reservation cancel succeeds once")
		check(game.gold==wallet+game.recruit_cost("archer"),"Cancellation refunds one order only")
		expected.erase(cancelled)
		check(game.production_preview_snapshot().size()==7,"Cancelled ghost disappears")
	var before_pause: Array=game.production_preview_snapshot()
	game.paused=true
	tick(game,.5)
	check(game.production_preview_snapshot().size()==before_pause.size(),"Pause retains queue size")
	for index in range(before_pause.size()): check(is_equal_approx(float(before_pause[index].progress),float(game.production_preview_snapshot()[index].progress)),"Pause freezes actual production progress")
	game.paused=false
	game.speed=2.0
	tick(game,.4)
	if not before_pause.is_empty() and not game.production_preview_snapshot().is_empty():
		check(absf(float(before_pause[0].remainingSeconds)-float(game.production_preview_snapshot()[0].remainingSeconds)-.8)<.055,"2x changes production by simulated time")
	tick(game,1.0)
	check(game.units.size()==14 and game.recruitment_queue.is_empty(),"Fourteen uncancelled paid members emerge")
	for unit in game.units:
		var points: Array=expected.get(int(unit.get("productionJobId",-1)),[])
		check(points.any(func(point: Vector2): return point.distance_to(unit.position)<.00001),"Ghost position equals real emergence position")
	evidence["slotsAndGhosts"]={"posts":posts,"reservedSlots":reserved,"previews":previews,"spawnedMembers":game.units.size(),"fixture":"painted stage;10000gold;archerLv5;cancel one2-member order;pause then2x"}
	game.free()
	var mixed: Node2D=make_game({},true)
	var post: Dictionary=mixed.shooting_position_snapshot()[0]
	check(bool(mixed.submit_deployment("archer",Vector2(post.x,post.y)).ok) and bool(mixed.submit_deployment("gunner",Vector2(post.x,post.y)).ok),"Archer and gunner share the same two-slot post")
	check(not bool(mixed.submit_deployment("archer",Vector2(post.x,post.y)).ok),"Third member cannot overbook a full post")
	mixed.free()

func crowd_participation() -> void:
	var game: Node2D=make_game()
	var units: Array=paid_spears(game,5)
	if not check(units.size()==5,"Crowd fixture produces five paid starters"): game.free();return
	for index in range(units.size()):
		var unit: Dictionary=units[index]
		unit.position=Vector2(.50,.476+float(index)*.012)
		unit.routeDistance=.4
		unit.gatherRemaining=0.0
		unit.combatState="march"
		unit.hp=1000.0;unit.maxHp=1000.0
	for index in range(4):
		var enemy: Dictionary=hostile(game,Vector2(.475,.482+float(index)*.012))
		enemy.hp=1000.0;enemy.maxHp=1000.0
	var events: Array=[]
	game.game_event.connect(func(row: Dictionary): copy_damage_event(game,events,row))
	tick(game,3.0)
	var friendly_attackers: Dictionary={}
	var enemy_attackers: Dictionary={}
	var counter_victims: Dictionary={}
	var impacts: Dictionary={}
	var duplicate_impacts: Array=[]
	for row in events:
		if str(row.get("type",""))!="hit" or float(row.get("damage",0))<=0: continue
		if str(row.get("side",""))=="friendly":
			friendly_attackers[int(row.actorId)]=true
			var impact: String=str(row.get("skillMeta",{}).get("impactId",""))
			if not impact.is_empty():
				var key: String=impact+":"+str(row.victimId)
				if impacts.has(key): duplicate_impacts.append(key)
				impacts[key]=true
		else:
			enemy_attackers[int(row.actorId)]=true
			counter_victims[int(row.victimId)]=true
	check(friendly_attackers.size()>=3 and enemy_attackers.size()>=2 and counter_victims.size()>=2,"Multiple actual allies/enemies deal damage to distributed participants")
	check(not impacts.is_empty() and duplicate_impacts.is_empty(),"Observed real impact IDs do not damage the same victim twice")
	var hits: Array=events.filter(func(row: Dictionary): return str(row.get("type",""))=="hit" and float(row.get("damage",0))>0)
	check(not hits.is_empty() and hits.all(func(row: Dictionary): return row.has("observedVictimHpAtSignal") and is_equal_approx(float(row.hpAfter),float(row.observedVictimHpAtSignal))),"Crowd hits reduce each live victim HP before each hit signal")
	var victim: Dictionary=game.enemies[0]
	victim.hp=1.0
	var gold_before: int=game.gold
	var victim_id: int=int(victim.id)
	var reward: int=int(victim.reward)
	game._damage_enemy(victim,100.0,"spear",units[0])
	game._damage_enemy(victim,100.0,"spear",units[0])
	# Death accounting belongs to the next actual simulation step.
	tick(game,.025)
	var gold_after: int=game.gold
	game._damage_enemy(victim,100.0,"spear",units[0])
	tick(game,.025)
	var kills: Array=events.filter(func(row: Dictionary): return str(row.get("type",""))=="killed" and int(row.get("victimId",-1))==victim_id)
	check(gold_after==gold_before+reward and game.gold==gold_after and bool(victim.get("deathRewardConsumed",false)) and kills.size()==1,"Duplicate lethal application grants one death reward")
	evidence["crowd"]={"fixture":"fiveL1spears/fourraiders;1000HP each;3simulatedseconds;no balance/performance claim","friendlyDamageActors":friendly_attackers.keys(),"enemyDamageActors":enemy_attackers.keys(),"counterVictims":counter_victims.keys(),"duplicateImpacts":duplicate_impacts,"events":events}
	game.free()

func counter_budget_case(count: int) -> Dictionary:
	var game: Node2D=make_game()
	var units: Array=paid_spears(game,count)
	var enemy: Dictionary=hostile(game,Vector2(.50,.50))
	var ids: Array=[]
	for index in range(units.size()):
		units[index].position=Vector2(.515,.49+float(index)*.004)
		units[index].routeDistance=.4
		units[index].gatherRemaining=0.0
		units[index].hp=1000.0;units[index].maxHp=1000.0
		ids.append(int(units[index].id))
	enemy["contactUnitIds"]=ids.duplicate()
	var events: Array=[]
	game.game_event.connect(func(row: Dictionary): copy_damage_event(game,events,row))
	var plan_samples: Array=[]
	for index in range(160):
		game.elapsed+=.025
		game.ground_combat.counterattack(enemy,.025)
		if index%10==0: plan_samples.append({"clock":game.elapsed,"preparedPlans":enemy.get("counterPlans",{}).duplicate(true)})
	var shots: Array=events.filter(func(row: Dictionary): return str(row.get("type",""))=="shot" and bool(row.get("contactCounter",false)))
	var hits: Array=events.filter(func(row: Dictionary): return str(row.get("type",""))=="hit")
	var damage: float=0.0
	for row in hits: damage+=float(row.get("damage",0))
	var result: Dictionary={"contacts":count,"seconds":4.0,"shots":shots.size(),"hits":hits.size(),"totalDamage":damage,"events":events,"preparations":plan_samples,"enemyContract":{"kind":enemy.kind,"originKind":enemy.get("originKind",""),"combatRole":enemy.get("combatRole",""),"aoe":enemy.get("aoe",null),"splashRadius":enemy.get("splashRadius",null),"targetLimit":enemy.get("targetLimit",null),"skillIds":enemy.get("skillIds",[]),"attackRange":enemy.get("attackRange",null)},"fixture":"Ordinary raider, no declared AoE skill/radius/limit. Direct counterattack step; all victims1000HP in legal physical contact; friendly attacks disabled"}
	game.free()
	return result

func bounded_enemy_attack_budget() -> void:
	var one: Dictionary=counter_budget_case(1)
	var five: Dictionary=counter_budget_case(5)
	check(int(one.shots)>0 and int(one.hits)>0,"Single-contact baseline really prepares/fires/damages")
	check(int(five.shots)<=int(one.shots)+1 and float(five.totalDamage)<=float(one.totalDamage)*1.15,"Ordinary non-AoE raider keeps one attack budget at five contacts; explicit area attacks are tested separately")
	evidence["counterAttackBudget"]={"oneContact":one,"fiveContacts":five,"shotRatio":float(five.shots)/maxf(1,float(one.shots)),"damageRatio":float(five.totalDamage)/maxf(.001,float(one.totalDamage)),"acceptance":"Distributed targets may rotate; contact count must not multiply one enemy's full-rate attack budget. Known suspected failure is preserved."}

func cancelled_counter_and_immediate_hit() -> void:
	var game: Node2D=make_game()
	var units: Array=paid_spears(game,1)
	if not check(units.size()==1,"Counter cancellation fixture has one paid victim"): game.free();return
	var unit: Dictionary=units[0]
	unit.position=Vector2(.515,.50);unit.hp=1000.0;unit.maxHp=1000.0
	var enemy: Dictionary=hostile(game,Vector2(.50,.50))
	enemy["contactUnitIds"]=[int(unit.id)]
	var rows: Array=[]
	game.game_event.connect(func(row: Dictionary):
		if str(row.get("type","")) not in ["shot","hit"]: return
		var copied: Dictionary=row.duplicate(true)
		copied["observedVictimHpAtSignal"]=float(unit.hp)
		rows.append(copied))
	game.ground_combat.counterattack(enemy,.025)
	var plans: Dictionary=enemy.get("counterPlans",{}).duplicate(true)
	check(not plans.is_empty(),"Counter windup prepares before any impact")
	var before: float=float(unit.hp)
	unit.position=Vector2(.80,.20)
	for unused in range(80): game.elapsed+=.025;game.ground_combat.counterattack(enemy,.025)
	check(is_equal_approx(float(unit.hp),before) and rows.is_empty(),"Target leaves contact during preparation: no release and no damage")
	unit.position=Vector2(.515,.50)
	for unused in range(160):
		game.elapsed+=.025;game.ground_combat.counterattack(enemy,.025)
		if rows.any(func(row: Dictionary): return str(row.type)=="hit"): break
	var hits: Array=rows.filter(func(row: Dictionary): return str(row.type)=="hit")
	check(not hits.is_empty(),"Restored contact produces a new actual hit")
	for hit in hits:
		check(float(hit.hpBefore)>float(hit.hpAfter) and is_equal_approx(float(hit.hpAfter),float(hit.observedVictimHpAtSignal)),"Every hit has already reduced live HP when its signal is observed")
	if not hits.is_empty():
		var hit: Dictionary=hits[0]
		var hp: float=float(unit.hp)
		var count: int=rows.size()
		var replay: float=game._damage_friendly(unit,100.0,enemy,{"impactId":str(hit.get("impactId","")),"attackId":str(hit.get("attackId","")),"contactCounter":true})
		check(not str(hit.get("impactId","")).is_empty() and is_zero_approx(replay) and is_equal_approx(float(unit.hp),hp) and rows.size()==count,"Same committed impact cannot damage or emit a hit twice")
	evidence["counterCancellationAndImmediateHP"]={"preparedBeforeLoss":plans,"events":rows,"hpBefore":before,"hpAfter":unit.hp,"scope":"Component windup, real contact loss, fresh release and impact replay. Per-hit signal-time HP is observed directly; no pooled damage acceptance."}
	game.free()

func explicit_area_attack() -> void:
	var game: Node2D=make_game({"archer":8})
	check(bool(game.submit_deployment("archer",Vector2(.5,.64)).ok),"Explicit barrage fixture pays Lv8 archers")
	game._advance_recruitment(2.11)
	if not check(not game.units.is_empty(),"Barrage fixture shooter exists"): game.free();return
	var shooter: Dictionary=game.units[0]
	var primary: Dictionary=hostile(game,Vector2(.5,.5))
	var outside: Dictionary=hostile(game,Vector2(.59,.5))
	var excluded: Dictionary=hostile(game,Vector2(.51,.5),"enemy_archer")
	excluded.combatRole=Battle.ENEMY_EMPLACEMENT_ROLE
	for index in range(12):
		var target: Dictionary=hostile(game,Vector2(.5,.5)+Vector2.from_angle(float(index)*TAU/12.0)*.020)
		target.hp=1.0
	var plan: Dictionary=game.unit_skills.prepare_attack(shooter,primary,100.0,.2)
	if not check(not plan.is_empty() and plan.get("skillIds",[]).has("archer_barrage"),"Area attack is explicitly declared by real Lv8 skill metadata"): game.free();return
	var meta: Dictionary=plan.skillMeta.duplicate(true)
	meta["impactId"]=str(meta.impactId)+":qa-arrow0"
	var shot: Dictionary={"type":"archer","sourceId":int(shooter.id),"sourcePosition":shooter.position,"campaignLevel":8,"skillMeta":meta,"targetId":int(primary.id),"targetPos":primary.position,"impactPosition":primary.position,"damage":100.0}
	var events: Array=[]
	game.game_event.connect(func(row: Dictionary): copy_damage_event(game,events,row))
	var outside_hp: float=float(outside.hp)
	var excluded_hp: float=float(excluded.hp)
	game.unit_skills.after_projectile_hit(shot,primary,0.0)
	var hit_ids: Array=[]
	for row in events:
		if str(row.get("type",""))=="skill_hit" and str(row.get("skillId",""))=="archer_barrage": hit_ids.append(int(row.victimId))
	check(hit_ids.size()>1 and hit_ids.size()<=game.unit_skills.SECONDARY_LIMIT,"Declared area attack may hit multiple targets within its actual target limit")
	var actual_hits: Array=events.filter(func(row: Dictionary): return str(row.get("type",""))=="hit" and float(row.get("damage",0))>0)
	check(actual_hits.size()==hit_ids.size() and actual_hits.all(func(row: Dictionary): return float(row.hpBefore)>float(row.hpAfter) and is_equal_approx(float(row.hpAfter),float(row.get("observedVictimHpAtSignal",-1)))),"Every area victim loses HP immediately at its own hit; no pooled delayed damage")
	check(is_equal_approx(float(outside.hp),outside_hp) and is_equal_approx(float(excluded.hp),excluded_hp),"Area damage respects real radius and fixed-shooter raid exclusion")
	var event_count: int=events.size()
	var gold: int=game.gold
	game.unit_skills.after_projectile_hit(shot.duplicate(true),primary,0.0)
	check(events.size()==event_count and game.gold==gold,"Same release/impact replay cannot duplicate splash hits or death rewards")
	evidence["explicitAreaAttack"]={"skill":"archer_barrage","radius":game.unit_skills.BARRAGE_RADIUS,"targetLimit":game.unit_skills.SECONDARY_LIMIT,"damagedIds":hit_ids,"events":events,"fixture":"One real declared Lv8 barrage impact;12 one-HP secondary enemies inside radius,one outside,one excluded raid;not natural unlock play"}
	game.free()

func support_cohort() -> void:
	var game: Node2D=make_game({"spear":4})
	var a: Dictionary=hostile(game,Vector2(.49,.60))
	var b: Dictionary=hostile(game,Vector2(.52,.60))
	var submitted: Dictionary=game.submit_deployment("spear",Vector2(.5,.63),"lane")
	if not check(bool(submitted.get("ok",false)),"Paid local support order accepted"): game.free();return
	game._advance_recruitment(1.31)
	if not check(game.units.size()==3,"Support produces three members"): game.free();return
	var unit: Dictionary=game.units[0]
	check(str(unit.get("supportPhase",""))=="waiting" and unit.get("supportEnemyIds",[]).is_empty(),"Cohort is not fixed before actual first contact")
	for unused in range(150):
		game.ground_combat.step(.025)
		if str(unit.get("supportPhase",""))=="brawl": break
	var locked: Array=unit.get("supportEnemyIds",[]).duplicate()
	check(locked.has(int(a.id)) and locked.has(int(b.id)),"First physical contact locks finite local group")
	var late: Dictionary=hostile(game,Vector2(.51,.61))
	game.ground_combat.step(.025)
	check(unit.get("supportEnemyIds",[])==locked and not game.ground_combat.primary_target_allowed(unit,late),"Late group is neither appended nor acquired")
	a.hp=0.0
	game.ground_combat.step(.025)
	check(str(unit.supportPhase)=="brawl","First death alone does not end the group")
	b.position=Vector2(.85,.2)
	game.ground_combat.step(.025)
	check(str(unit.supportPhase)=="return","Original member leaves region: survivors return despite late enemy")
	late.position=Vector2(.8,.3)
	var prior: Vector2=unit.position
	var max_stride: float=0.0
	for unused in range(900):
		game.ground_combat.step(.025)
		max_stride=maxf(max_stride,prior.distance_to(unit.position));prior=unit.position
		if str(unit.supportPhase)=="done": break
	check(str(unit.supportPhase)=="done" and max_stride<.008,"Support physically returns and rejoins; no teleport")
	evidence["finiteSupport"]={"locked":locked,"lateId":int(late.id),"finalPhase":unit.supportPhase,"maxReturnStride":max_stride}
	game.free()
	var empty: Node2D=make_game()
	check(bool(empty.submit_deployment("spear",Vector2(.5,.63),"lane").get("ok",false)),"Empty-group support order accepts")
	empty._advance_recruitment(1.31)
	for unused in range(100): empty.ground_combat.step(.025)
	if not empty.units.is_empty(): check(str(empty.units[0].get("supportPhase","")) in ["return","done"],"No local group does not wait forever")
	empty.free()

func tower_exclusion() -> void:
	var game: Node2D=make_game({},true)
	var post: Dictionary=game.shooting_position_snapshot()[0]
	check(bool(game.submit_deployment("archer",Vector2(post.x,post.y)).ok),"Fixture archer is normally paid")
	game._advance_recruitment(2.11)
	if not check(not game.units.is_empty(),"Fixture archer exists"): game.free();return
	var unit: Dictionary=game.units[0]
	var raider: Dictionary=hostile(game,unit.position+Vector2(.025,.01),"enemy_archer")
	raider["combatRole"]=Battle.ENEMY_EMPLACEMENT_ROLE
	raider["assaultZoneId"]=str(post.id)
	var hp: float=float(raider.hp)
	check(not game.can_friendly_target_enemy(unit,raider) and not game.ground_combat.primary_target_allowed(unit,raider,"prepare") and not game.ground_combat.primary_target_allowed(unit,raider,"release"),"Fixed shooter excludes raid at acquisition and release")
	check(is_zero_approx(game._damage_enemy(raider,100,"archer",unit)),"Fixed shooter cannot apply direct or secondary damage to raid")
	game.projectiles.append({"position":raider.position,"targetId":int(raider.id),"targetPos":raider.position,"damage":100.0,"type":"archer","sourceId":int(unit.id),"sourcePosition":unit.position,"sourceUnit":unit.duplicate(true),"speed":.65,"age":0.0})
	game._update_projectiles(.025)
	check(is_equal_approx(float(raider.hp),hp) and game.projectiles.is_empty(),"Already flying fixed-shooter projectile cannot hit a raid")
	var ordinary: Dictionary=hostile(game,raider.position,"raider")
	check(game.can_friendly_target_enemy(unit,ordinary),"Ordinary road enemy remains allowed")
	var facility: Dictionary=raider.duplicate(true)
	facility["stationaryEnemy"]=true;facility["fortification"]=true
	check(game.can_friendly_target_enemy(unit,facility),"Real fixed enemy facility remains allowed")
	evidence["towerExclusion"]={"raidHpBefore":hp,"raidHpAfter":raider.hp,"projectilesRemaining":game.projectiles.size()}
	game.free()

func reward_receipts() -> void:
	var game: Node2D=make_game()
	paid_spears(game,1)
	hostile(game,Vector2(.45,.5))
	var events: Array=[]
	game.game_event.connect(func(row: Dictionary):
		if str(row.get("type",""))=="learning-reward-receipt": events.append(row.duplicate(true)))
	var receipt: Dictionary=game.grant_learning_reward(false,"fix01-reward-1","context")
	check(bool(receipt.get("ok",false)) and str(receipt.get("state",""))=="queued" and not bool(receipt.get("actualDelivered",true)),"Claim queues reward without pretending delivery")
	var jobs: int=game.battle_support.jobs.size()
	var duplicate: Dictionary=game.grant_learning_reward(false,"fix01-reward-1","context")
	check(bool(duplicate.get("duplicate",false)) and game.battle_support.jobs.size()==jobs,"Duplicate claim does not enqueue another effect")
	game.paused=true
	game.battle_support.step(1.0)
	check(not bool(game.battle_support.receipt_snapshot()[0].actualDelivered),"Paused reward remains undelivered")
	game.paused=false
	for unused in range(120): game.battle_support.step(.05)
	var final: Dictionary=game.battle_support.receipt_snapshot()[0]
	check(bool(final.get("actualDelivered",false)) and int(final.get("deliveredCount",0))>0,"Effect progresses to actual delivered receipt")
	check(events.filter(func(row: Dictionary): return str(row.receiptPhase)=="delivered").size()==1,"One claim publishes one delivered transition")
	var count_before: int=int(final.get("deliveredCount",0))
	game.grant_learning_reward(false,"fix01-reward-1","context")
	check(int(game.battle_support.receipt_snapshot()[0].deliveredCount)==count_before,"Delivered replay cannot repeat the effect")
	evidence["rewardReceipts"]={"initial":receipt,"final":final,"events":events,"fixture":"One existing marcher and one eligible enemy, normal reward API; BattleSupport component stepped"}
	game.free()

func withdrawal_objectives() -> void:
	var game: Node2D=make_game({},true,false)
	var mission: RefCounted=game.withdrawal_mission
	check(mission.enabled and mission.validate_route(),"Shipped stage01 has a traversable rear exit avoiding all posts")
	check(mission.actors.size()==4 and mission.arrived_ids.is_empty(),"Three required groups plus distinct rearguard begin with zero arrivals")
	# Component phase fixture; no claim of naturally surviving the campaign.
	mission.phase="withdrawal"
	var paths: Array=[]
	for index in range(800):
		game.elapsed+=.1
		mission.step(.1)
		if index%20==0: paths.append(mission.snapshot())
		if mission.evaluate() in ["complete","failed"]: break
	var final: Dictionary=mission.snapshot()
	check(str(final.phase)=="complete" and int(final.arrivedCount)==4,"Actual sequential movement records all three plus rearguard arrivals")
	check(final.actors.all(func(actor: Dictionary): return int(actor.arrivalCount)==1 and str(actor.status)=="arrived"),"Every required ID is counted exactly once")
	mission.step(1.0)
	check(mission.arrived_ids.size()==4,"Extra steps cannot count arrivals twice")
	mission.actors[0].hp=0.0
	check(mission.evaluate()=="failed","Required loss wins over same-step four arrivals")
	mission.reset(game)
	check(mission.arrived_ids.is_empty() and mission.phase=="cover" and mission.actors.all(func(actor: Dictionary): return float(actor.hp)>0),"Retry resets arrivals, phase and required actors")
	game.elapsed=mission.deadline
	check(mission.evaluate()=="failed" and mission.arrived_ids.is_empty(),"Time alone cannot complete withdrawal")
	evidence["withdrawal"]={"componentPhaseInjected":"withdrawal","movementSamples":paths,"completed":final,"deadlineResult":mission.snapshot(),"naturalSurvivalVerified":false}
	game.free()
	var training: Node2D=make_game({},true,true)
	check(not training.withdrawal_mission.enabled and training.withdrawal_mission.actors.is_empty(),"trainingOnly excludes withdrawal targets")
	tick(training,2.0)
	check(training.enemies.is_empty() and training.spawn_queue.is_empty(),"trainingOnly has no natural assault")
	training.free()

func renderer_initialization() -> void:
	var renderer: RefCounted=Actors.new()
	var data: Dictionary=renderer.diagnostics()
	check(renderer.is_ready() and data.errors.is_empty(),"Current renderer initializes its real manifest/PNG/rig assets")
	check(int(data.get("uvRigSets",0))>=8,"Both spear factions register all four direction rigs")
	evidence["rendererInitialization"]=data
	# Pending roles/actions stay explicit; initialization is not visual acceptance.

func run() -> void:
	started=Time.get_ticks_usec()
	source_hashes=hash_sources()
	output=OUTPUT.path_join("logic-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if maps.is_empty(): check(false,"Shipped map exists");persist("setup_failed");quit(2);return
	shipped=maps[0]
	for method in ["renderer_initialization","growth_and_slots","crowd_participation","bounded_enemy_attack_budget","cancelled_counter_and_immediate_hit","explicit_area_attack","support_cohort","tower_exclusion","reward_receipts","withdrawal_objectives"]:
		call(method)
		persist("after_"+method)
	check(source_hashes==hash_sources(),"Source and real asset hashes remain unchanged during focused logic run")
	persist("complete")
	print("FIX01_LOGIC ",ProjectSettings.globalize_path(output.path_join("logic-report.json"))," checks=",checks.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
