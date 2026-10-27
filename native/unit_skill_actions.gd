extends RefCounted
## Stateful actions and defensive/support commitments. No rendering or timers.
var skills: RefCounted
var battle: Node2D
var committed_actions: Dictionary={}
var successful_counters: Dictionary={}
var impact_actions: Dictionary={}
var cast_serial: int=0
const RECEIPT_LIMIT: int=2048
var receipt_rings: Dictionary={}
var receipt_heads: Dictionary={}
var rear_geometry_queries: Dictionary={}
var rear_query_epoch: int=-1

func bind(owner: RefCounted) -> void:
	skills=owner
	battle=owner.battle

func reset() -> void:
	committed_actions.clear();successful_counters.clear();impact_actions.clear();cast_serial=0
	receipt_rings.clear();receipt_heads.clear();rear_geometry_queries.clear();rear_query_epoch=-1

func initialize_unit(unit: Dictionary) -> void:
	unit.merge({"skillAttackActions":0,"braceReadyAt":0.0,"parryReadyAt":0.0,"counterTargetId":-1,"counterExpiresAt":0.0,"counterCharge":0,"wardHp":0.0,"wardReadyAt":0.0,"wardSource":{},"prayerHealProgress":0.0,"rallyBonus":0.0,"rallyUntil":0.0,"rallyToken":""},true)

func _live(unit: Dictionary) -> bool:
	return not unit.is_empty() and float(unit.get("hp",0.0))>0.0 and not bool(unit.get("consumed",false))

func _context(skill_generation: int, battle_generation: int) -> bool:
	return skills.generation==skill_generation and battle.battle_generation==battle_generation and skills._active_battle() and not battle.battle_closed

func _cast(source: Dictionary, target: Dictionary, id: String, effect: String, seconds: float, affected: Array, extra: Dictionary = {}) -> void:
	var meta: Dictionary=extra.get("skillMeta",{}).duplicate(true)
	if meta.is_empty(): meta=_event_meta(source)
	var fields: Dictionary={"skillId":id,"skillIds":source.get("skillIds",skills.skill_ids(source)).duplicate(),"campaignLevel":skills._level(source),"skillMeta":meta,"effectKind":effect,"affectedIds":affected.duplicate(),"duration":seconds,"startedAt":float(battle.elapsed)}
	fields.merge(extra,true)
	skills._event("skill_cast",source,target,fields)

func _event_meta(source: Dictionary) -> Dictionary:
	cast_serial+=1
	var token: String="g%d:cast%d" % [skills.generation,cast_serial]
	return {"generation":skills.generation,"attackId":token,"impactId":token+":effect","motionToken":token,"sourceId":int(source.get("id",-1)),"sourceType":str(source.get("type","")),"campaignLevel":skills._level(source),"skillIds":source.get("skillIds",skills.skill_ids(source)).duplicate(),"proc":false,"committed":true}

func _remember(history: Dictionary, token: String) -> void:
	if history.has(token): return
	var key: String="release" if is_same(history,committed_actions) else "counter" if is_same(history,successful_counters) else "impact"
	var ring: Array=receipt_rings.get(key,[])
	if ring.size()<RECEIPT_LIMIT: ring.append(token)
	else:
		var head: int=int(receipt_heads.get(key,0))
		history.erase(str(ring[head]));ring[head]=token
		receipt_heads[key]=(head+1)%RECEIPT_LIMIT
	receipt_rings[key]=ring
	history[token]=true

func ninja_preparation_valid(unit: Dictionary, target: Dictionary, plan: Dictionary) -> bool:
	# For animation steps between impacts only. HQ keeps the original full
	# live validator immediately before/after each actual impact and plant.
	if not _context(skills.generation,int(plan.get("ninjaBattleGeneration",-1))) or not _live(unit) or not skills._valid_meta(plan.get("skillMeta",{})) or not is_same(battle.ground_combat._unit(int(unit.get("id",-1))),unit) or not is_same(unit.get("attackPlan",{}),plan) or target.is_empty() or not is_same(battle._enemy(int(target.get("id",-1))),target): return false
	if battle.ground_combat.territorial_melee_enabled: return battle.ground_combat.melee_preparation_allowed(unit,target,plan,true)
	return battle.ground_combat.ninja_mission_target_valid(unit,target,true)

func counter_target(unit: Dictionary) -> Dictionary:
	if str(unit.get("type",""))!="samurai" or int(unit.get("counterTargetId",-1))<0: return {}
	var target: Dictionary=battle._enemy(int(unit.counterTargetId))
	if float(unit.get("counterExpiresAt",0.0))<=skills.clock or not _live(unit) or target.is_empty() or float(target.get("hp",0.0))<=0.0 or not battle.ground_combat.shares_contact_front(unit,target) or not battle.ground_combat.primary_target_allowed(unit,target,"release") or unit.position.distance_to(target.position)>battle.ground_combat.reach(unit)*1.1 or not battle.ground_combat.land_segment_safe(unit.position,target.position,0.0):
		unit["counterTargetId"]=-1
		return {}
	return target

func configure_plan(unit: Dictionary, target: Dictionary, plan: Dictionary) -> void:
	var type_name: String=str(unit.type)
	var duration: float=float(unit.get("attackDuration",battle._animation_duration("attack")))
	var action: String=""
	var times: Array=[]
	var factors: Array=[]
	if type_name=="archer" and skills.has_skill(unit,"archer_double_shot") and (int(unit.get("skillAttackActions",0))+1)%4==0:
		action="archer_double_shot";times=[duration*.42,duration*.76];factors=[1.0,.65]
	elif type_name=="gunner" and skills.has_skill(unit,"gunner_braced_shot") and (int(unit.get("skillAttackActions",0))+1)%4==0:
		action="gunner_braced_shot";times=[duration*.72];factors=[1.8]
	elif type_name=="samurai":
		var counter: Dictionary=counter_target(unit)
		if skills.has_skill(unit,"samurai_isshin") and int(unit.get("counterCharge",0))>=3:
			action="samurai_isshin";times=[duration*.65];factors=[2.0]
		elif not counter.is_empty() and int(counter.id)==int(target.id):
			action="samurai_counter_combo" if skills.has_skill(unit,"samurai_counter_combo") else "samurai_counter"
			times=[duration*.35,duration*.72] if action=="samurai_counter_combo" else [duration*.50]
			factors=[.75,.65] if action=="samurai_counter_combo" else [1.15]
	if action.is_empty():
		if type_name=="spear" and effective_spear_reach(unit,.041)>.041:
			plan["skillId"]="spear_rear_rank";plan["effectKind"]="rear_rank";plan.flags["rearRank"]=true;plan.skillMeta["flags"]=plan.flags.duplicate(true)
		return
	plan.merge({"skillAction":action,"releaseTimes":times,"releaseTime":float(times[0]),"releaseDamageFactors":factors,"stagedBaseDamage":float(plan.damage),"nextReleaseIndex":0,"committedReleaseIndices":[],"actionBattleGeneration":int(battle.battle_generation)},true)
	plan["skillId"]="samurai_parry" if action=="samurai_counter" else action
	plan["effectKind"]={"archer_double_shot":"double_shot","gunner_braced_shot":"braced_shot","samurai_counter":"counter","samurai_counter_combo":"counter_combo","samurai_isshin":"isshin"}[action]
	unit["activeSkillIds"]=[str(plan.skillId)]

func advance(unit: Dictionary, plan: Dictionary, animation_clock: float) -> bool:
	if bool(plan.get("actionInProgress",false)): return false
	if bool(plan.get("actionCancelled",false)): return true
	plan["actionInProgress"]=true
	var result: bool=_advance_contents(unit,plan,animation_clock)
	plan["actionInProgress"]=false
	return result

func _advance_contents(unit: Dictionary, plan: Dictionary, animation_clock: float) -> bool:
	var skill_generation: int=skills.generation
	var battle_generation: int=int(plan.get("actionBattleGeneration",-1))
	if not _context(skill_generation,battle_generation) or not _live(unit) or not is_same(battle.ground_combat._unit(int(unit.id)),unit) or not is_same(unit.get("attackPlan",{}),plan) or not skills._valid_meta(plan.get("skillMeta",{})): return true
	var times: Array=plan.releaseTimes
	var index: int=int(plan.get("nextReleaseIndex",0))
	while index<times.size() and animation_clock>=float(times[index]):
		if not _context(skill_generation,battle_generation) or not _live(unit) or not is_same(unit.get("attackPlan",{}),plan): return true
		var target: Dictionary=battle._enemy(int(plan.targetId))
		if str(unit.type)=="archer":
			var radius: float=float(battle._stats(unit).range)
			if target.is_empty() or not battle.can_friendly_target_enemy(unit,target) or not battle._enemy_visible(target) or unit.position.distance_to(target.position)>radius:
				target={}
				for candidate in battle.enemies:
					if battle.can_friendly_target_enemy(unit,candidate) and battle._enemy_visible(candidate) and unit.position.distance_to(candidate.position)<=radius: target=candidate;break
				if not target.is_empty(): plan["targetId"]=int(target.id)
		if target.is_empty() or not battle.ground_combat.primary_target_allowed(unit,target,"release"):
			plan["actionCancelled"]=true;return true
		if str(unit.type)=="samurai" and (unit.position.distance_to(target.position)>battle.ground_combat.reach(unit)*1.1 or not battle.ground_combat.land_segment_safe(unit.position,target.position,0.0)):
			plan["actionCancelled"]=true;unit["counterTargetId"]=-1;return true
		plan["nextReleaseIndex"]=index+1
		var child: Dictionary=plan.duplicate(true)
		child.erase("releaseTimes")
		child["nativeReleaseConsumed"]=false
		child["skillsReleaseConsumed"]=false
		child["releaseTime"]=float(times[index])
		child["actualReleaseCommitted"]=false
		child["releaseIndex"]=index
		child["hitIndex"]=index
		child["damage"]=float(plan.stagedBaseDamage)*float(plan.releaseDamageFactors[index])
		var token: String=str(plan.skillMeta.get("motionToken",plan.skillMeta.attackId))
		child.skillMeta.erase("damagedTargets")
		child.skillMeta.merge({"attackId":token+":batch:"+str(index),"impactId":token+":batch:"+str(index)+":primary","motionToken":token,"releaseTime":float(times[index]),"releaseIndex":index,"hitIndex":index,"baseDamage":float(plan.skillMeta.get("baseDamage",plan.stagedBaseDamage))*float(plan.releaseDamageFactors[index])},true)
		battle._release_unit_attack(unit,child)
		if not _context(skill_generation,battle_generation): return true
		if bool(child.get("actualReleaseCommitted",false)): plan.committedReleaseIndices.append(index)
		else: plan["actionCancelled"]=true;return true
		index=int(plan.nextReleaseIndex)
	return index>=times.size()

func on_release(unit: Dictionary, plan: Dictionary) -> void:
	var token: String=str(plan.get("skillMeta",{}).get("motionToken",plan.get("skillMeta",{}).get("attackId","")))
	if token.is_empty() or committed_actions.has(token): return
	_remember(committed_actions,token)
	if str(unit.type) in ["archer","gunner"]: unit["skillAttackActions"]=int(unit.get("skillAttackActions",0))+1

func on_primary_impact(unit: Dictionary, target: Dictionary, plan: Dictionary, actual: float) -> void:
	if actual<=0.0: return
	on_release(unit,plan)
	var token: String=str(plan.skillMeta.get("motionToken",plan.skillMeta.attackId))
	var action: String=str(plan.get("skillAction",""))
	if action in ["samurai_counter","samurai_counter_combo"] and not successful_counters.has(token):
		_remember(successful_counters,token)
		unit["counterCharge"]=mini(3,int(unit.get("counterCharge",0))+1)
		unit["counterTargetId"]=-1
	if action=="samurai_isshin" and not successful_counters.has(token):
		_remember(successful_counters,token);unit["counterCharge"]=0;unit["counterTargetId"]=-1
	if bool(plan.get("charge",false)) and not impact_actions.has(token):
		_remember(impact_actions,token)
		var skill_generation: int=skills.generation
		var battle_generation: int=battle.battle_generation
		if not _live(unit) or not is_same(battle.ground_combat._unit(int(unit.id)),unit): return
		if skills.has_skill(unit,"commander_impact"): commander_impact(unit,target)
		if not _context(skill_generation,battle_generation) or not _live(unit) or not is_same(battle.ground_combat._unit(int(unit.id)),unit): return
		if skills.has_skill(unit,"commander_rally"): commander_rally(unit,plan.skillMeta)

func _delay_enemy(source: Dictionary, enemy: Dictionary, id: String, seconds: float, stop_move: bool) -> bool:
	if not skills._active_battle() or battle.battle_closed or not _live(source) or not is_same(battle.ground_combat._unit(int(source.get("id",-1))),source) or enemy.is_empty() or not is_same(battle._enemy(int(enemy.get("id",-1))),enemy) or float(enemy.get("hp",0))<=0.0 or float(enemy.get("skillDisruptImmuneUntil",0.0))>skills.clock: return false
	enemy["skillDisruptImmuneUntil"]=skills.clock+2.5
	enemy["skillAttackDelayUntil"]=maxf(float(enemy.get("skillAttackDelayUntil",0.0)),skills.clock+seconds)
	if stop_move: enemy["skillMoveStopUntil"]=maxf(float(enemy.get("skillMoveStopUntil",0.0)),skills.clock+seconds)
	_cast(source,enemy,id,"brace" if stop_move else "impact",seconds,[int(enemy.id)])
	return true

func try_spear_brace(unit: Dictionary, enemy: Dictionary) -> void:
	if not skills.has_skill(unit,"spear_brace") or not _live(unit) or enemy.is_empty() or float(enemy.get("hp",0.0))<=0.0 or float(unit.get("braceReadyAt",0.0))>skills.clock or float(enemy.get("skillDisruptImmuneUntil",0.0))>skills.clock: return
	if not skills._active_battle() or battle.battle_closed or not is_same(battle.ground_combat._unit(int(unit.id)),unit) or not is_same(battle._enemy(int(enemy.id)),enemy): return
	unit["braceReadyAt"]=skills.clock+4.0
	_delay_enemy(unit,enemy,"spear_brace",.30,true)

func commander_impact(unit: Dictionary, target: Dictionary) -> void:
	var candidates: Array=battle.ground_combat.crowd.nearby(target.position,.10,false)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.position.distance_squared_to(target.position)<b.position.distance_squared_to(target.position))
	var count: int=0
	var skill_generation: int=skills.generation
	var battle_generation: int=battle.battle_generation
	for enemy in candidates:
		if count>=4 or not _context(skill_generation,battle_generation) or not _live(unit): return
		if int(enemy.pathIndex)!=int(unit.postPathIndex) or not battle.ground_combat.land_segment_safe(unit.position,enemy.position,0.0): continue
		if _delay_enemy(unit,enemy,"commander_impact",.35,false): count+=1

func commander_rally(unit: Dictionary, motion_meta: Dictionary) -> void:
	var token: String=str(motion_meta.get("motionToken",motion_meta.get("attackId","")))
	var affected: Array=[]
	for ally in battle.ground_combat.crowd.nearby(unit.position,.14,true):
		if not _live(ally) or str(ally.type) not in ["spear","samurai","naginata","commander","gunner"] or int(ally.get("postPathIndex",-1))!=int(unit.postPathIndex) or not skills._connected(unit,ally,.14): continue
		ally["rallyBonus"]=maxf(.25,float(ally.get("rallyBonus",0.0)) if float(ally.get("rallyUntil",0.0))>skills.clock else 0.0)
		ally["rallyUntil"]=skills.clock+3.0
		ally["rallyToken"]=token
		affected.append(int(ally.id))
	if not affected.is_empty(): _cast(unit,{},"commander_rally","rally",3.0,affected,{"skillMeta":motion_meta.duplicate(true)})

func modify_incoming(unit: Dictionary, result: Dictionary, attacker: Dictionary, impact: Dictionary) -> Dictionary:
	var amount: float=float(result.amount)
	if amount<=0.0: return result
	var skill_generation: int=skills.generation
	var battle_generation: int=battle.battle_generation
	var direct_melee: bool=not attacker.is_empty() and str(attacker.get("kind","")) not in ["enemy_archer","enemy_gunner"] and bool(impact.get("contactCounter",false))
	if direct_melee and skills.has_skill(unit,"samurai_parry") and float(unit.get("parryReadyAt",0.0))<=skills.clock:
		unit["parryReadyAt"]=skills.clock+4.0
		unit["counterTargetId"]=int(attacker.id)
		unit["counterExpiresAt"]=skills.clock+4.0
		amount*=.30
		result.flags["parry"]=true
		result["skillId"]="samurai_parry"
		_cast(unit,attacker,"samurai_parry","parry",.30,[int(unit.id)],{"attackerId":int(attacker.id),"incomingImpactId":str(impact.get("impactId",""))})
		if not _context(skill_generation,battle_generation) or not _live(unit) or not is_same(battle.ground_combat._unit(int(unit.id)),unit) or not is_same(battle._enemy(int(attacker.id)),attacker) or float(attacker.get("hp",0.0))<=0.0:
			result["amount"]=0.0;return result
	var ward: float=float(unit.get("wardHp",0.0))
	if ward>0.0:
		var caster: Dictionary=unit.get("wardSource",{}).duplicate(true)
		unit["wardHp"]=0.0;unit["wardSource"]={}
		var absorbed: float=minf(ward,amount)
		amount=maxf(0.0,amount-absorbed)
		result.flags["ward"]=true
		_cast(caster,unit,"monk_ward","ward_absorb",0.0,[int(unit.id)],{"absorbedHp":absorbed,"skillIds":caster.get("skillIds",[]).duplicate(),"campaignLevel":int(caster.get("campaignLevel",1)),"skillMeta":caster.get("skillMeta",{}).duplicate(true)})
		if not _context(skill_generation,battle_generation) or not _live(unit) or not is_same(battle.ground_combat._unit(int(unit.id)),unit):
			result["amount"]=0.0;return result
	result["amount"]=amount
	return result

func outgoing_bonus(enemy: Dictionary, amount: float, source: Dictionary) -> float:
	var meta: Dictionary=source.get("skillMeta",{})
	var impact_id: String=str(meta.get("impactId",""))
	if amount<=0.0 or bool(meta.get("secondary",false)) or not bool(meta.get("proc",true)) or not (impact_id.ends_with(":primary") or impact_id.ends_with(":arrow0")): return amount
	var unit: Dictionary=battle.ground_combat._unit(int(source.get("id",-1)))
	if not _live(unit) or float(unit.get("rallyUntil",0.0))<=skills.clock or float(unit.get("rallyBonus",0.0))<=0.0: return amount
	source["rallyCommitToken"]=str(unit.rallyToken)
	return amount*(1.0+float(unit.rallyBonus))

func after_enemy_damage(source: Dictionary, actual: float) -> void:
	if actual<=0.0 or not source.has("rallyCommitToken"): return
	var unit: Dictionary=battle.ground_combat._unit(int(source.get("id",-1)))
	if unit.is_empty() or str(unit.get("rallyToken",""))!=str(source.rallyCommitToken): return
	unit["rallyBonus"]=0.0;unit["rallyUntil"]=0.0;unit["rallyToken"]=""

func after_heal(source: Dictionary, target: Dictionary, healed: float, effect: String) -> void:
	if healed<=0.0 or not _live(target) or not is_same(battle.ground_combat._unit(int(target.get("id",-1))),target): return
	var monk: Dictionary=battle.ground_combat._unit(int(source.get("id",-1)))
	if not _live(monk) or str(monk.type)!="monk": return
	if effect!="victory_prayer" and skills.has_skill(monk,"monk_victory_prayer") and int(monk.get("prayerCount",0))<6:
		monk["prayerHealProgress"]=float(monk.get("prayerHealProgress",0.0))+healed
		while float(monk.prayerHealProgress)>=30.0 and int(monk.prayerCount)<6:
			monk.prayerHealProgress=float(monk.prayerHealProgress)-30.0
			monk.prayerCount=int(monk.prayerCount)+1
		if int(monk.prayerCount)>=6: monk.prayerHealProgress=minf(float(monk.prayerHealProgress),29.999)
	if effect not in ["heal","victory_prayer"] or not skills.has_skill(monk,"monk_ward") or float(target.get("wardReadyAt",0.0))>skills.clock or float(target.get("wardHp",0.0))>0.0: return
	var strength: float=minf(18.0,8.0*float(skills.support_stats(monk).healingFactor))
	var skill_generation: int=skills.generation
	var battle_generation: int=battle.battle_generation
	var caster: Dictionary={"id":int(monk.id),"type":"monk","position":monk.position,"campaignLevel":skills._level(monk),"skillIds":skills.skill_ids(monk),"skillMeta":_event_meta(monk)}
	target["wardHp"]=strength
	target["wardReadyAt"]=skills.clock+6.0
	target["wardSource"]=caster.duplicate(true)
	_cast(caster,target,"monk_ward","ward",0.0,[int(target.id)],{"wardHp":strength,"grantCooldown":6.0,"skillMeta":caster.skillMeta.duplicate(true)})
	if not _context(skill_generation,battle_generation) or not _live(monk) or not _live(target) or not is_same(battle.ground_combat._unit(int(monk.id)),monk) or not is_same(battle.ground_combat._unit(int(target.id)),target): return

func _rear_geometry(unit: Dictionary, front: Dictionary, target: Dictionary, gap: float) -> bool:
	if not _live(unit) or not _live(front) or not battle.ground_combat.can_fight(front) or target.is_empty() or float(target.get("hp",0))<=0.0 or int(front.get("postPathIndex",-1))!=int(unit.get("postPathIndex",-2)): return false
	if int(unit.get("postPathIndex",-1))!=int(target.get("pathIndex",-2)) or not battle.can_friendly_target_enemy(unit,target): return false
	# Reach is queried by primary-target checks; keep this geometry predicate
	# independent of reach to avoid recursion through the support brawl.
	for ally in [unit,front]:
		var phase: String=str(ally.get("supportPhase",""))
		if phase in ["waiting","return"]: return false
		if phase=="brawl" and (not battle.ground_combat._support_enemy_on_field(target) or not ally.get("supportEnemyIds",[]).has(int(target.id)) or not battle.ground_combat.guard_point_inside(ally,ally.position) or not battle.ground_combat.guard_point_inside(ally,target.position)): return false
	if int(front.get("targetId",-1))!=int(target.id) and not front.get("contactEnemyIds",[]).has(int(target.id)): return false
	var front_reach: float=float(battle.ground_combat.REACH.get(str(front.type),0.0))
	if front.position.distance_to(target.position)>front_reach*1.1: return false
	var epoch: int=battle.ground_combat.combat_query_epoch()
	if epoch>=0 and epoch!=rear_query_epoch: rear_geometry_queries.clear();rear_query_epoch=epoch
	var signature: Array=[unit.position,front.position,target.position,gap]
	var cached: Dictionary=rear_geometry_queries.get(int(unit.id),{}) if epoch>=0 else {}
	if not cached.is_empty() and cached.signature==signature: return bool(cached.valid)
	var axis: Vector2=(front.position-target.position).normalized()
	var offset: Vector2=unit.position-front.position
	var valid: bool=offset.dot(axis)>=gap*.60 and offset.dot(axis)<=gap*2.20 and absf(offset.cross(axis))<=gap*.8 and battle.ground_combat.land_segment_safe(unit.position,target.position,0.0)
	if epoch>=0: rear_geometry_queries[int(unit.id)]={"signature":signature,"valid":valid}
	return valid

func effective_spear_reach(unit: Dictionary, base: float) -> float:
	if str(unit.get("type",""))!="spear" or not skills.has_skill(unit,"spear_rear_rank"): return base
	var front: Dictionary=battle.ground_combat._unit(int(unit.get("rearRankFrontId",-1)))
	var target: Dictionary=battle._enemy(int(unit.get("rearRankTargetId",-1)))
	if int(unit.get("targetId",-1))!=int(unit.get("rearRankTargetId",-2)): return base
	return base+.014*1.5 if _rear_geometry(unit,front,target,.014) else base

func rear_rank_goal(unit: Dictionary, target: Dictionary) -> Vector2:
	if str(unit.type)!="spear" or not skills.has_skill(unit,"spear_rear_rank") or target.is_empty() or int(target.get("pathIndex",-1))!=int(unit.get("postPathIndex",-2)): return Vector2(INF,INF)
	var best: Dictionary={}
	var goal: Vector2=Vector2(INF,INF)
	var cost: float=INF
	for front in battle.ground_combat.crowd.nearby(unit.position,.075,true):
		if int(front.id)==int(unit.id) or str(front.type) not in ["spear","samurai","naginata"] or not _live(front) or not battle.ground_combat.can_fight(front) or int(front.get("postPathIndex",-1))!=int(unit.postPathIndex): continue
		if int(front.get("targetId",-1))!=int(target.id) and not front.get("contactEnemyIds",[]).has(int(target.id)): continue
		if front.position.distance_to(target.position)>float(battle.ground_combat.REACH.get(str(front.type),0.0))*1.1: continue
		var axis: Vector2=(front.position-target.position).normalized()
		if (unit.position-front.position).dot(axis)<-.014*.25: continue
		var point: Vector2=front.position+axis*.014*1.25
		var distance: float=unit.position.distance_squared_to(point)
		if str(unit.get("supportPhase",""))=="brawl" and not battle.ground_combat.guard_point_inside(unit,point): continue
		if distance>=cost or not battle.ground_combat.land_segment_safe(unit.position,point,.008) or not battle.ground_combat.land_segment_safe(point,target.position,0.0): continue
		if battle.ground_combat.crowd.pressure(point,int(unit.id),true)>.001: continue
		best=front;goal=point;cost=distance
	if not best.is_empty(): unit["rearRankFrontId"]=int(best.id);unit["rearRankTargetId"]=int(target.id)
	else: unit["rearRankFrontId"]=-1;unit["rearRankTargetId"]=-1
	return goal

func public_state(unit: Dictionary) -> Dictionary:
	return {"wardHp":float(unit.get("wardHp",0.0)),"wardReadyAt":float(unit.get("wardReadyAt",0.0)),"parryReadyAt":float(unit.get("parryReadyAt",0.0)),"counterTargetId":int(unit.get("counterTargetId",-1)),"counterCharge":int(unit.get("counterCharge",0)),"rallyActive":float(unit.get("rallyUntil",0.0))>skills.clock and float(unit.get("rallyBonus",0.0))>0.0,"rallyUntil":float(unit.get("rallyUntil",0.0)),"braceReadyAt":float(unit.get("braceReadyAt",0.0)),"rearRankActive":effective_spear_reach(unit,.041)>.041}
