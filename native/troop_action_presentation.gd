extends RefCounted
## Read-only adapter. Combat plans and committed receipts own all decisions.
var battle: Node2D
var generation: int = -1
var attacks: Dictionary = {}
var heals: Dictionary = {}
var departures: Dictionary = {}
var seen_events: Dictionary = {}
var actor_lookups: Dictionary = {}
var event_order: Array[int] = []
var event_order_cursor: int = 0
var next_departure_prune: float = 0.0
const DEPARTURE_SECONDS: float = .30
const PHASE_LABELS: Dictionary = {
	"guard":"경계 중", "gather":"집결 중", "march":"행군 중",
	"approach":"목표 접근 중", "charge":"돌격 중", "windup":"공격 준비 중",
	"release":"발사·타격", "recovery":"공격 회수 중", "reload":"재장전 중",
	"heal":"치료 시전 중", "return":"복귀 중", "no_target":"대상 없음",
	"unreachable":"접근 불가", "cancelled":"공격 취소", "engaged":"정지·대치 중",
	"depart":"임무 종료 · 퇴장", "dead":"전사"
}

func bind(value: Node2D) -> void:
	unbind()
	battle = value
	if is_instance_valid(battle): battle.presentation_event.connect(consume_event)

func unbind() -> void:
	if is_instance_valid(battle) and battle.presentation_event.is_connected(consume_event):
		battle.presentation_event.disconnect(consume_event)
	battle = null
	reset()

func reset() -> void:
	attacks.clear()
	heals.clear()
	departures.clear()
	seen_events.clear()
	actor_lookups.clear()
	event_order.clear()
	event_order_cursor=0
	next_departure_prune=0.0
	generation = -1

func _sync_generation() -> void:
	if not is_instance_valid(battle): return
	if generation != int(battle.battle_generation):
		reset()
		generation = int(battle.battle_generation)
	var now: float=float(battle.animation_time)
	if now>=next_departure_prune:
		next_departure_prune=now+1.0
		for id in departures.keys():
			if now-float(departures[id].time)>=DEPARTURE_SECONDS: departures.erase(id)

func _unit(id: int) -> Dictionary:
	if is_instance_valid(battle): return _actor_from_roster(id,battle.units,"friendly")
	return {}

func _index_roster(roster: Array, side: String) -> Dictionary:
	var by_id: Dictionary={}
	var slots: Dictionary={}
	for index in range(roster.size()):
		var actor: Dictionary=roster[index]
		var id: int=int(actor.get("id",-1))
		if id<0 or by_id.has(id): continue
		by_id[id]=actor
		slots[id]=index
	var result: Dictionary={"roster":roster,"count":roster.size(),"actors":by_id,"slots":slots}
	actor_lookups[side]=result
	return result

func _actor_from_roster(id: int, roster: Array, side: String) -> Dictionary:
	if id<0: return {}
	var index: Dictionary=actor_lookups.get(side,{})
	if index.is_empty() or int(index.count)!=roster.size() or not is_same(index.roster,roster): index=_index_roster(roster,side)
	var actor: Dictionary=index.actors.get(id,{})
	if not actor.is_empty():
		var slot: int=int(index.slots.get(id,-1))
		if slot>=0 and slot<roster.size() and is_same(roster[slot],actor) and int(actor.get("id",-1))==id: return actor
		return _index_roster(roster,side).actors.get(id,{})
	# Preserve callers that replace an entry in place without changing count.
	for member in roster:
		if int(member.get("id",-1))==id: return _index_roster(roster,side).actors.get(id,{})
	return {}

func _combatant(id: int) -> Dictionary:
	if id<0: return {}
	var unit: Dictionary = _unit(id)
	if not unit.is_empty(): return unit
	if is_instance_valid(battle): return _actor_from_roster(id,battle.enemies,"enemy")
	return {}

func _attack_plan(actor: Dictionary) -> Dictionary:
	for key in ["attackPlan","rangedPlan","counterPlan"]:
		var plan: Dictionary = actor.get(key,{})
		if not plan.is_empty(): return plan
	return {}

func consume_event(event: Dictionary) -> void:
	_sync_generation()
	if not is_instance_valid(battle): return
	# Footsteps, damage and other cosmetic events never contribute to this
	# adapter. Reject them before ID bookkeeping or any roster lookup.
	var type_name: String=str(event.get("type",""))
	if type_name in ["killed","unit_fallen"]:
		var retired_id: int=int(event.get("victimId",-1) if type_name=="killed" else event.get("actorId",-1))
		attacks.erase(retired_id)
		heals.erase(retired_id)
		return
	if type_name not in ["shot","heal","unit_consumed"]: return
	if event.has("eventId"):
		var event_id: int = int(event.eventId)
		if seen_events.has(event_id): return
		seen_events[event_id] = true
		if event_order.size()<512:
			event_order.append(event_id)
		else:
			seen_events.erase(event_order[event_order_cursor])
			event_order[event_order_cursor]=event_id
			event_order_cursor=(event_order_cursor+1)%512
	var id: int = int(event.get("actorId",-1))
	if id < 0: return
	var now: float = float(battle.animation_time)
	match type_name:
		"shot":
			var side: String=str(event.get("side",""))
			var unit: Dictionary=_actor_from_roster(id,battle.units,"friendly") if side=="friendly" else _actor_from_roster(id,battle.enemies,"enemy") if side=="enemy" else _combatant(id)
			if unit.is_empty(): return
			var clock: float = float(unit.get("animationClock",0))
			var plan: Dictionary = _attack_plan(unit)
			var start: float = now-clock
			var previous: Dictionary = attacks.get(id,{})
			var release_time: float = float(plan.get("releaseTime",clock))
			# Some native counterattacks clear their plan before notifying. Keep
			# that same attack's observed deadline instead of the overshot clock.
			if plan.is_empty() and not previous.is_empty() and absf(float(previous.start)-start) < .001:
				release_time = float(previous.releaseTime)
			attacks[id] = {
				"start":start, "releaseTime":release_time,
				"releasedAt":now, "targetId":int(event.get("victimId",-1)),
				"reloadRemaining":float(unit.get("cooldown",unit.get("attackCooldown",0))), "released":true
			}
		"heal":
			if float(event.get("healAmount",0)) <= 0: return
			heals[id] = {"healCommittedAt":now,"healAmount":float(event.healAmount),"healingTargetId":int(event.get("victimId",-1)),"healingTargetPosition":event.get("victimPosition",{}).duplicate(true)}
		"unit_consumed":
			# The renderer may keep an existing model for a short fade only. It
			# never inserts a corpse or a simulated unit back into the battle.
			departures[id] = {"time":now,"reason":str(event.get("consumeReason","mission_complete")),"targetId":int(event.get("targetId",-1)),"position":event.get("position",{}).duplicate(true)}
			attacks.erase(id)
			heals.erase(id)

func state_for_id(id: int) -> Dictionary:
	return state_for(_combatant(id))

func state_for(unit: Dictionary) -> Dictionary:
	_sync_generation()
	if unit.is_empty() or not is_instance_valid(battle): return {}
	var id: int = int(unit.get("id",-1))
	var now: float = float(battle.animation_time)
	var animation: String = str(unit.get("animation","idle"))
	var combat: String = str(unit.get("combatState","guard"))
	var type_name: String = str(unit.get("type",unit.get("kind","")))
	var clock: float = float(unit.get("animationClock",0))
	var duration: float = maxf(.05,float(unit.get("attackDuration",battle._animation_duration("attack"))))
	var phase: String = "guard"
	var result: Dictionary = {"attackReleased":false,"attackCancelled":false,"reloadActive":false,"reloadProgress":0.0,"targetId":int(unit.get("targetId",-1)),"movementBlocked":bool(unit.get("movementBlocked",false)),"releaseTime":battle._impact_time(type_name)*duration/battle._animation_duration("attack")}
	if float(unit.get("hp",1)) <= 0:
		phase = "dead"
	elif bool(unit.get("consumed",false)) or combat == "consumed":
		phase = "depart"
	elif animation == "attack":
		var start: float = now-clock
		var plan: Dictionary = _attack_plan(unit)
		var receipt: Dictionary = attacks.get(id,{})
		var same_attack: bool = not receipt.is_empty() and absf(float(receipt.start)-start) < .001
		if not plan.is_empty():
			result.releaseTime = float(plan.get("releaseTime",result.releaseTime))
			result.targetId = int(plan.get("targetId",result.targetId))
			if not same_attack:
				attacks[id] = {"start":start,"releaseTime":result.releaseTime,"targetId":result.targetId,"released":false}
		elif same_attack:
			result.releaseTime = float(receipt.releaseTime)
			result.targetId = int(receipt.targetId)
		result.attackReleased = same_attack and bool(receipt.get("released",false))
		result.attackCancelled = plan.is_empty() and not result.attackReleased and clock >= float(result.releaseTime)
		phase = "cancelled" if result.attackCancelled else "windup" if not result.attackReleased else "release" if now-float(receipt.releasedAt) < .055 else "recovery"
	elif animation == "heal" and bool(battle.unit_skills.public_state(unit).get("healing",false)):
		phase = "heal"
		if heals.has(id): result.merge(heals[id],true)
	elif combat in ["guard_return","ambush_return","return"]:
		phase = "unreachable" if result.movementBlocked else "return"
	elif result.movementBlocked and combat in ["guard_advance","guard_dash","ambush_approach","advance"]:
		phase = "unreachable"
	elif combat == "gather": phase = "gather"
	elif combat in ["charge","guard_dash"]: phase = "charge"
	elif combat in ["advance","guard_advance","ambush_approach"]: phase = "approach"
	elif animation == "walk": phase = "march"
	elif type_name in ["gunner","enemy_gunner"] and bool(attacks.get(id,{}).get("released",false)) and float(unit.get("cooldown",unit.get("attackCooldown",0))) > 0:
		var receipt: Dictionary = attacks[id]
		var remaining: float = float(unit.get("cooldown",unit.get("attackCooldown",0)))
		var total: float = maxf(.001,float(receipt.reloadRemaining))
		result.reloadActive = true
		result.reloadProgress = clampf(1.0-remaining/total,0,1)
		phase = "reload"
	elif combat in ["engaged","guard_engaged","impact","front"]: phase = "engaged"
	elif type_name == "ninja" and int(unit.get("targetId",-1)) < 0:
		# This only describes an actual transitional state; it does not choose
		# a waiting or consumption policy for the functionality team.
		phase = "no_target"
	result["motionPhase"] = phase
	result["actionLabelKo"] = str(PHASE_LABELS.get(phase,"경계 중"))
	result["hitActive"] = float(unit.get("hitClock",0)) > 0
	result["combatState"] = combat
	if result.hitActive: result.actionLabelKo += " · 피격"
	return result

func departure_state(id: int) -> Dictionary:
	_sync_generation()
	if not departures.has(id) or not is_instance_valid(battle): return {}
	var value: Dictionary = departures[id].duplicate()
	value["progress"] = clampf((float(battle.animation_time)-float(value.time))/DEPARTURE_SECONDS,0,1)
	return value

func prune(live_ids: Dictionary) -> void:
	for cache in [attacks,heals]:
		for id in cache.keys():
			if not live_ids.has(int(id)): cache.erase(id)
	for id in departures.keys():
		if float(departure_state(int(id)).get("progress",1)) >= 1: departures.erase(id)

static func consumed_label(reason: String) -> String:
	return {"target_defeated":"표적 처치 · 닌자 퇴장", "target_killed":"표적 처치 · 닌자 퇴장", "target_destroyed":"표적 처치 · 닌자 퇴장", "target_lost":"표적 소멸 · 닌자 퇴장", "target_invalid":"표적 무효 · 닌자 퇴장", "unreachable":"접근 불가 · 닌자 퇴장", "no_target":"대상 없음 · 닌자 퇴장"}.get(reason,"임무 종료 · 닌자 퇴장")
