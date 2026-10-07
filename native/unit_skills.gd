extends RefCounted
const UnitGrowth = preload("res://native/unit_growth.gd")
## Campaign-level abilities; the owning Game still applies HP, deaths and rewards.
const UNLOCKS: Dictionary = {
	"archer_volley":{"type":"archer","level":3},"archer_fire":{"type":"archer","level":5},"archer_barrage":{"type":"archer","level":8},
	"samurai_armor":{"type":"samurai","level":3},"samurai_spear_aura":{"type":"samurai","level":5},"samurai_flash":{"type":"samurai","level":8},
	"spear_pierce":{"type":"spear","level":3},"spear_pair":{"type":"spear","level":5},"spear_poison":{"type":"spear","level":8},
	"gunner_pierce":{"type":"gunner","level":3},"gunner_reload":{"type":"gunner","level":5},"gunner_armor_break":{"type":"gunner","level":8},
	"naginata_sweep":{"type":"naginata","level":3},"naginata_guard_charge":{"type":"naginata","level":5},"naginata_charge_guard":{"type":"naginata","level":8},
	"commander_charge":{"type":"commander","level":3},"commander_formation":{"type":"commander","level":5},"commander_break":{"type":"commander","level":8},
	"monk_talisman":{"type":"monk","level":3},"monk_mantra":{"type":"monk","level":5},"monk_victory_prayer":{"type":"monk","level":8}
}
const VOLLEY_DAMAGE_FACTOR: float = 1.08
const VOLLEY_WINDOW: float = .10
const BARRAGE_ARROWS: int = 3
const BARRAGE_ARROW_FACTOR: float = .45
const BARRAGE_RADIUS: float = .045
const BARRAGE_SPLASH_FACTOR: float = .28
const SECONDARY_LIMIT: int = 4
const BURN_DURATION: float = 3.0
const BURN_DPS_FACTOR: float = .07
const POISON_DURATION: float = 4.0
const POISON_DPS_FACTOR: float = .06
const DOT_DPS_CAP: float = 20.0
const DOT_TICK_SECONDS: float = .5
const SAMURAI_ARMOR_BONUS: float = .12
const SPEAR_AURA_RANGE: float = .17
const SPEAR_AURA_FACTOR: float = 1.15
const FLASH_CHANCE: float = .04
const SPEAR_PIERCE_LENGTH: float = .085
const SPEAR_PIERCE_WIDTH: float = .016
const SPEAR_PIERCE_FACTOR: float = .55
const GUNNER_PIERCE_LENGTH: float = .16
const GUNNER_PIERCE_WIDTH: float = .014
const GUNNER_PIERCE_FACTOR: float = .65
const RELOAD_FACTOR: float = .92
const ARMOR_BREAK_FACTOR: float = .65
const ARMOR_BREAK_DURATION: float = 2.4
const SWEEP_RADIUS: float = .055
const SWEEP_UPGRADED_RADIUS: float = .070
const SWEEP_FACTOR: float = .55
const GUARD_MANA_MAX: float = 100.0
const GUARD_MANA_PER_SECOND: float = 14.0
const GUARD_DASH_SPEED: float = 1.4
const GUARD_DASH_DAMAGE: float = 1.45
const GUARD_CLUSTER_RADIUS: float = .10
const GUARD_INVULNERABLE_SECONDS: float = 1.1
const FORMATION_RADIUS: float = .14
const FORMATION_DAMAGE_FACTOR: float = 1.12
const DISRUPT_RADIUS: float = .10
const DISRUPT_DURATION: float = 3.0
const BASIC_HEAL_AMOUNT: float = 6.0
const BASIC_HEAL_INTERVAL: float = 1.0
const HEAL_POSE_SECONDS: float = .55
const TALISMAN_DURATION: float = 4.0
const TALISMAN_PER_SECOND: float = 2.0
const MANTRA_RESOURCE_FACTOR: float = 1.12
const PRAYER_REQUIRED: int = 6
const PRAYER_COOLDOWN: float = 12.0
const PRAYER_HEAL_AMOUNT: float = 18.0
const PRAYER_MANA_AMOUNT: float = 20.0
const PRAYER_CHARGE_SECONDS: float = 2.0

var battle: Node2D
var generation: int = 0
var clock: float = 0.0
var _last_step_elapsed: float = -1.0
var _attack_serial: int = 0
var _volley_serial: int = 0
var _volley_until: float = -1.0
var _next_volley_at: float = 0.0
var _next_heal_at: float = BASIC_HEAL_INTERVAL
var _seen_damage: Dictionary = {}
var _seen_releases: Dictionary = {}
var _seen_impacts: Dictionary = {}
var _seen_kills: Dictionary = {}
var _registered_units: Dictionary = {}
var _prayer_target_ready: Dictionary = {}

func bind(value: Node2D) -> void:
	battle=value

func reset() -> void:
	generation+=1
	clock=0.0
	_last_step_elapsed=-1.0
	_attack_serial=0
	_volley_serial=0
	_volley_until=-1.0
	_next_volley_at=0.0
	_next_heal_at=BASIC_HEAL_INTERVAL
	_seen_damage.clear()
	_seen_releases.clear()
	_seen_impacts.clear()
	_seen_kills.clear()
	_registered_units.clear()
	_prayer_target_ready.clear()
	if is_instance_valid(battle):
		for unit in battle.units: initialize_unit(unit)
		for enemy in battle.enemies: enemy["skillStatuses"]={}

func initialize_unit(unit: Dictionary) -> void:
	unit.merge({"skillMana":0.0,"maxSkillMana":GUARD_MANA_MAX,"guardDashActive":false,"guardDashTargetId":-1,"invulnerableUntil":0.0,"lastVolleySerial":-1,"skillActiveUntil":0.0,"activeSkillIds":[],"skillMeta":{},"healingUntil":0.0,"healingTargetId":-1,"healDuration":HEAL_POSE_SECONDS,"prayerCount":0,"prayerReadyAt":0.0,"friendlySkillStatuses":{}},true)
	_registered_units[int(unit.get("id",-1))]={"type":str(unit.get("type","")),"campaignLevel":_level(unit)}

func _level(unit: Dictionary) -> int:
	return clampi(int(unit.get("campaignLevel",1)),1,10)

func has_skill(unit: Dictionary, id: String) -> bool:
	var definition: Dictionary=UNLOCKS.get(id,{})
	return not definition.is_empty() and str(unit.get("type",""))==str(definition.type) and _level(unit)>=int(definition.level)

func skill_ids(unit: Dictionary) -> Array:
	var result: Array=[]
	for id in UNLOCKS:
		if has_skill(unit,str(id)): result.append(str(id))
	return result

func recruit_quantity(type_name: String, campaign_level: int) -> int:
	return 2 if type_name=="spear" and campaign_level>=5 else 1

func _alive(unit: Dictionary) -> bool:
	return not unit.is_empty() and (not unit.has("hp") or float(unit.hp)>0) and not bool(unit.get("dead",false))

func _position(actor: Dictionary) -> Vector2:
	var value: Variant=actor.get("position",Vector2.ZERO)
	return value if value is Vector2 else Vector2(float(value.get("x",0)),float(value.get("y",0))) if value is Dictionary else Vector2.ZERO

func _connected(first: Dictionary, second: Dictionary, radius: float) -> bool:
	if not first.has("position") or not second.has("position") or _position(first).distance_to(_position(second))>radius: return false
	return is_instance_valid(battle) and battle.ground_combat.land_segment_safe(_position(first),_position(second),0.0)

func _formation_members(commander: Dictionary) -> Array:
	if not _alive(commander) or not has_skill(commander,"commander_formation") or not commander.has("position"): return []
	var members: Array=[commander]
	var lanes: Array=[int(commander.get("formationLane",0))]
	var direction: Vector2=commander.get("aim",Vector2.ZERO)
	if direction.length_squared()<.001: return []
	for ally in battle.units:
		if int(ally.id)==int(commander.id) or not _alive(ally) or str(ally.type) not in ["spear","samurai","commander"]: continue
		if int(ally.get("postPathIndex",-1))!=int(commander.get("postPathIndex",-2)) or not _connected(commander,ally,FORMATION_RADIUS): continue
		var aim: Vector2=ally.get("aim",Vector2.ZERO)
		var lane: int=int(ally.get("formationLane",0))
		if aim.length_squared()<.001 or direction.normalized().dot(aim.normalized())<.8 or lane in lanes: continue
		members.append(ally)
		lanes.append(lane)
	return members if members.size()>=3 else []

func _formation_commander(unit: Dictionary) -> Dictionary:
	if not is_instance_valid(battle) or not unit.has("position"): return {}
	for commander in battle.units:
		if not has_skill(commander,"commander_formation"): continue
		for member in _formation_members(commander):
			if int(member.id)==int(unit.get("id",-1)): return commander
	return {}

func _spear_support(unit: Dictionary) -> Dictionary:
	if not is_instance_valid(battle) or str(unit.get("type",""))!="spear" or not unit.has("position"): return {}
	for samurai in battle.units:
		if _alive(samurai) and has_skill(samurai,"samurai_spear_aura") and _connected(samurai,unit,SPEAR_AURA_RANGE): return samurai
	return {}

func stat_modifiers(unit: Dictionary) -> Dictionary:
	# This method never calls Game._stats; it is safe from that method's hook.
	var damage_factor: float=0.0 if str(unit.get("type",""))=="monk" else VOLLEY_DAMAGE_FACTOR if has_skill(unit,"archer_volley") else 1.0
	if not _spear_support(unit).is_empty(): damage_factor*=SPEAR_AURA_FACTOR
	if not _formation_commander(unit).is_empty(): damage_factor*=FORMATION_DAMAGE_FACTOR
	return {"damageFactor":damage_factor,"rangeFactor":1.08 if has_skill(unit,"naginata_sweep") else 1.0,"intervalFactor":RELOAD_FACTOR if has_skill(unit,"gunner_reload") else 1.0}

func attack_ready(unit: Dictionary) -> bool:
	if str(unit.get("type",""))=="monk" or not _alive(unit): return false
	if not has_skill(unit,"archer_volley"): return true
	return _volley_serial>0 and clock<=_volley_until+.0000001 and int(unit.get("lastVolleySerial",-1))<_volley_serial

func _active_battle() -> bool:
	return is_instance_valid(battle) and battle.running and not battle.paused and not battle.between_waves and not battle.finished

func step(delta: float) -> void:
	if not _active_battle() or not is_finite(delta) or delta<=0: return
	var now: float=float(battle.elapsed)
	if not is_finite(now) or now<=_last_step_elapsed+.0000001: return
	var effective_delta: float=minf(delta,maxf(0.0,now-clock))
	clock=now
	_last_step_elapsed=now
	for unit in battle.units:
		if not _alive(unit): continue
		if has_skill(unit,"naginata_guard_charge"):
			unit["skillMana"]=clampf(float(unit.get("skillMana",0))+effective_delta*GUARD_MANA_PER_SECOND*mana_charge_factor(unit),0,GUARD_MANA_MAX)
		if float(unit.get("healingUntil",0))<=clock and str(unit.get("animation",""))=="heal": unit["animation"]="idle"
		_tick_talisman(unit)
	for enemy in battle.enemies:
		_tick_enemy_statuses(enemy)
	if clock>=_next_volley_at:
		var period: float=0.0
		for unit in battle.units:
			if _alive(unit) and has_skill(unit,"archer_volley"): period=maxf(period,float(battle._stats(unit).interval))
		if period>0:
			_volley_serial+=1
			_volley_until=clock+VOLLEY_WINDOW
			_next_volley_at=clock+maxf(.25,period)
	if clock>=_next_heal_at:
		_heal_pulse()
		_next_heal_at=clock+BASIC_HEAL_INTERVAL
	for unit in battle.units:
		if _alive(unit) and has_skill(unit,"monk_victory_prayer") and int(unit.get("prayerCount",0))>=PRAYER_REQUIRED: _cast_prayer(unit)
	_prune_history(_seen_damage)
	_prune_history(_seen_releases)
	_prune_history(_seen_impacts)

func _prune_history(history: Dictionary) -> void:
	if history.size()<512: return
	for key in history.keys():
		if clock-float(history[key])>8.0: history.erase(key)

func prepare_attack(unit: Dictionary, target: Dictionary, damage: float, release_time: float, charge: bool = false) -> Dictionary:
	if not _active_battle() or not _alive(unit) or target.is_empty() or float(target.get("hp",0))<=0 or str(unit.get("type",""))=="monk" or not is_finite(damage) or damage<=0: return {}
	_attack_serial+=1
	var ids: Array=skill_ids(unit)
	var flags: Dictionary={"volley":has_skill(unit,"archer_volley"),"fireArrow":has_skill(unit,"archer_fire"),"barrage":has_skill(unit,"archer_barrage"),"poisonTip":has_skill(unit,"spear_poison"),"pierce":has_skill(unit,"spear_pierce") or has_skill(unit,"gunner_pierce"),"guardCharge":bool(unit.get("guardDashActive",false))}
	var id: String=_attack_effect_skill(unit,charge)
	var token: String="g%d:a%d" % [generation,_attack_serial]
	var meta: Dictionary={"generation":generation,"attackId":token,"impactId":token+":primary","sourceId":int(unit.get("id",-1)),"sourceType":str(unit.type),"campaignLevel":_level(unit),"skillIds":ids,"flags":flags.duplicate(true),"proc":true,"committed":false,"baseDamage":maxf(0,damage)}
	var plan: Dictionary={"targetId":int(target.get("id",-1)),"damage":damage*BARRAGE_ARROW_FACTOR if has_skill(unit,"archer_barrage") else damage,"releaseTime":release_time,"charge":charge,"guardDash":bool(unit.get("guardDashActive",false)),"skillMeta":meta,"skillId":id,"skillIds":ids,"flags":flags,"effectKind":_effect_kind(id)}
	unit["skillMeta"]=meta.duplicate(true)
	unit["skillActiveUntil"]=clock+.65
	unit["activeSkillIds"]=_attack_active_skills(unit,charge)
	if has_skill(unit,"archer_volley"): unit["lastVolleySerial"]=_volley_serial
	return plan

func _attack_effect_skill(unit: Dictionary, charge: bool) -> String:
	if bool(unit.get("guardDashActive",false)): return "naginata_guard_charge"
	for id in ["archer_barrage","archer_fire","archer_volley","spear_poison","spear_pierce","gunner_pierce","naginata_sweep"]:
		if has_skill(unit,str(id)): return str(id)
	return "commander_charge" if charge and has_skill(unit,"commander_charge") else ""

func _attack_active_skills(unit: Dictionary, charge: bool) -> Array:
	var active: Array=[]
	for id in ["archer_volley","archer_fire","archer_barrage","spear_pierce","spear_poison","gunner_pierce","naginata_sweep"]:
		if has_skill(unit,str(id)): active.append(str(id))
	if bool(unit.get("guardDashActive",false)): active.append("naginata_guard_charge")
	if charge and has_skill(unit,"commander_charge"): active.append("commander_charge")
	return active

func _effect_kind(id: String) -> String:
	return {"archer_volley":"volley","archer_fire":"fire_arrow","archer_barrage":"barrage","samurai_flash":"flash","spear_pierce":"pierce","spear_poison":"poison_tip","gunner_pierce":"pierce","gunner_armor_break":"armor_break","naginata_sweep":"sweep","naginata_guard_charge":"guard_charge","commander_charge":"charge","commander_break":"disrupt","monk_talisman":"talisman_tick","monk_mantra":"mantra","monk_victory_prayer":"victory_prayer","monk_heal":"heal"}.get(id,"")

func decorate_projectile(shot: Dictionary, unit: Dictionary, plan: Dictionary) -> Dictionary:
	var meta: Dictionary=plan.get("skillMeta",{}).duplicate(true)
	meta["committed"]=true
	meta["impactId"]=str(meta.get("attackId",""))+":arrow0"
	shot.merge({"skillMeta":meta,"skillId":str(plan.get("skillId","")),"skillIds":plan.get("skillIds",[]).duplicate(),"flags":plan.get("flags",{}).duplicate(true),"effectKind":str(plan.get("effectKind","")),"campaignLevel":_level(unit),"impactOffset":Vector2.ZERO},true)
	return shot

func after_release(unit: Dictionary, target: Dictionary, plan: Dictionary) -> void:
	if not _alive(unit) or target.is_empty() or not _valid_meta(plan.get("skillMeta",{})): return
	var key: String=str(plan.skillMeta.attackId)
	if bool(plan.get("skillsReleaseConsumed",false)) or _seen_releases.has(key): return
	plan["skillsReleaseConsumed"]=true
	_seen_releases[key]=clock
	var damage: float=float(plan.get("damage",0))
	if has_skill(unit,"archer_barrage"):
		var direction: Vector2=(_position(target)-_position(unit)).normalized()
		for index in range(1,BARRAGE_ARROWS):
			var side: float=-1.0 if index==1 else 1.0
			var shot: Dictionary={"position":_position(unit)+direction.orthogonal()*side*.008,"targetId":int(target.id),"targetPos":_position(target),"damage":damage,"type":str(unit.type),"sourceId":int(unit.id),"sourcePosition":_position(unit),"speed":.65,"age":0.0}
			decorate_projectile(shot,unit,plan)
			shot["impactOffset"]=direction.orthogonal()*side*.024
			shot.skillMeta["impactId"]=key+":arrow"+str(index)
			battle.projectiles.append(shot)
			_event("shot",unit,target,{"skillId":"archer_barrage","skillIds":plan.skillIds,"effectKind":"barrage","flags":shot.flags,"projectileIndex":index,"campaignLevel":_level(unit)})
	if has_skill(unit,"spear_pierce"): _pierce(unit,target,damage,SPEAR_PIERCE_LENGTH,SPEAR_PIERCE_WIDTH,SPEAR_PIERCE_FACTOR,plan.skillMeta,"spear_pierce")
	if str(unit.get("type",""))=="naginata":
		var radius: float=SWEEP_UPGRADED_RADIUS if has_skill(unit,"naginata_sweep") else SWEEP_RADIUS
		_area_damage(unit,_position(target),int(target.id),damage*SWEEP_FACTOR,radius,plan.skillMeta,"naginata_sweep" if has_skill(unit,"naginata_sweep") else "","sweep",int(target.get("pathIndex",-1)))
	if bool(plan.get("charge",false)) and has_skill(unit,"commander_break"): _disrupt(unit,target)
	if bool(plan.get("guardDash",false)): finish_guard_dash(unit,true)

func after_projectile_hit(shot: Dictionary, target: Dictionary, _actual_damage: float) -> void:
	var meta: Dictionary=shot.get("skillMeta",{})
	if not _valid_meta(meta): return
	var key: String=str(meta.get("impactId",""))
	if bool(shot.get("skillsImpactConsumed",false)) or _seen_impacts.has(key): return
	shot["skillsImpactConsumed"]=true
	_seen_impacts[key]=clock
	var source: Dictionary=_projectile_source(shot)
	var position: Vector2=shot.get("impactPosition",shot.get("targetPos",shot.get("position",Vector2.ZERO)))
	if "archer_barrage" in meta.get("skillIds",[]):
		_area_damage(source,position,int(shot.get("targetId",-1)),float(shot.damage)*BARRAGE_SPLASH_FACTOR,BARRAGE_RADIUS,meta,"archer_barrage","barrage")
	if not target.is_empty() and "gunner_pierce" in meta.get("skillIds",[]):
		_pierce(source,target,float(shot.damage),GUNNER_PIERCE_LENGTH,GUNNER_PIERCE_WIDTH,GUNNER_PIERCE_FACTOR,meta,"gunner_pierce")

func _projectile_source(shot: Dictionary) -> Dictionary:
	return {"id":int(shot.get("sourceId",-1)),"type":str(shot.get("type","")),"position":shot.get("sourcePosition",Vector2.ZERO),"campaignLevel":int(shot.get("campaignLevel",1)),"skillMeta":shot.get("skillMeta",{}).duplicate(true)}

func _valid_meta(meta: Dictionary) -> bool:
	return not meta.is_empty() and int(meta.get("generation",-1))==generation

func _proc_source(source: Dictionary) -> Dictionary:
	var meta: Dictionary=source.get("skillMeta",{})
	if not meta.is_empty() and (not _valid_meta(meta) or not bool(meta.get("proc",true))): return {}
	if bool(meta.get("committed",false)):
		return {"id":int(meta.get("sourceId",source.get("id",-1))),"type":str(meta.get("sourceType",source.get("type",""))),"campaignLevel":int(meta.get("campaignLevel",1)),"position":source.get("position",Vector2.ZERO)}
	if is_instance_valid(battle):
		for unit in battle.units:
			if int(unit.id)==int(source.get("id",-1)) and _alive(unit): return unit
	return {}

func modify_outgoing(enemy: Dictionary, amount: float, unit_type: String, source: Dictionary) -> Dictionary:
	var result: Dictionary={"amount":maxf(0,amount) if is_finite(amount) else 0.0,"instant":false,"skillId":"","flags":{}}
	var meta: Dictionary=source.get("skillMeta",{})
	if not meta.is_empty():
		if not _valid_meta(meta): result.amount=0.0;result["stale"]=true;return result
		var key: String=str(meta.get("impactId",meta.get("attackId","")))+":enemy"+str(enemy.get("id",-1))
		var damaged: Dictionary=meta.get("damagedTargets",{})
		if damaged.has(int(enemy.get("id",-1))) or _seen_damage.has(key): result.amount=0.0;result["duplicate"]=true;return result
		damaged[int(enemy.get("id",-1))]=true
		meta["damagedTargets"]=damaged
		_seen_damage[key]=clock
	var actor: Dictionary=_proc_source(source)
	if result.amount>0 and unit_type=="samurai" and has_skill(actor,"samurai_flash") and str(enemy.get("kind",""))=="enemy_samurai" and enemy.get("historicalCommander",{}).is_empty() and not bool(enemy.get("boss",false)) and not bool(meta.get("secondary",false)):
		if battle.rng.randf()<FLASH_CHANCE:
			result.merge({"instant":true,"skillId":"samurai_flash","effectKind":"flash","flags":{"flash":true}},true)
			actor["skillActiveUntil"]=clock+.5
			actor["activeSkillIds"]=["samurai_flash"]
	return result

func modify_enemy_armor(enemy: Dictionary, base_armor: float) -> float:
	var status: Dictionary=enemy.get("skillStatuses",{}).get("armor_break",{})
	return base_armor*ARMOR_BREAK_FACTOR if not status.is_empty() and float(status.get("endAt",0))>clock else base_armor

func modify_incoming(unit: Dictionary, amount: float, base_armor: float) -> Dictionary:
	var bonus: float=UnitGrowth.armor(unit,false)-UnitGrowth.base_armor(str(unit.get("type","")))
	var armor: float=clampf(base_armor+bonus+(SAMURAI_ARMOR_BONUS if has_skill(unit,"samurai_armor") else 0),0,UnitGrowth.MAX_ARMOR)
	var blocked: bool=float(unit.get("invulnerableUntil",0))>clock
	return {"amount":0.0 if blocked or not is_finite(amount) else maxf(0,amount)*(1.0-armor),"armor":armor,"blocked":blocked,"skillId":"naginata_charge_guard" if blocked else "samurai_armor" if has_skill(unit,"samurai_armor") else "","flags":{"invulnerable":blocked}}

func after_enemy_hit(enemy: Dictionary, actual_damage: float, unit_type: String, source: Dictionary) -> void:
	if actual_damage<=0 or float(enemy.get("hp",0))<=0: return
	var actor: Dictionary=_proc_source(source)
	if actor.is_empty(): return
	var meta: Dictionary=source.get("skillMeta",{})
	var base_damage: float=float(meta.get("baseDamage",actual_damage))
	if unit_type=="archer" and has_skill(actor,"archer_fire"): _apply_dot(enemy,"burn",source,minf(DOT_DPS_CAP,maxf(0,base_damage)*BURN_DPS_FACTOR),BURN_DURATION,"archer_fire")
	if unit_type=="spear" and has_skill(actor,"spear_poison"): _apply_dot(enemy,"poison",source,minf(DOT_DPS_CAP,maxf(0,base_damage)*POISON_DPS_FACTOR),POISON_DURATION,"spear_poison")
	if unit_type=="gunner" and has_skill(actor,"gunner_armor_break"):
		var statuses: Dictionary=enemy.get("skillStatuses",{})
		statuses["armor_break"]={"endAt":clock+ARMOR_BREAK_DURATION,"skillId":"gunner_armor_break"}
		enemy["skillStatuses"]=statuses
		actor["skillActiveUntil"]=clock+.5
		actor["activeSkillIds"]=["gunner_armor_break"]
		_event("status",source,enemy,{"skillId":"gunner_armor_break","effectKind":"armor_break","duration":ARMOR_BREAK_DURATION,"flags":{"armorWeakened":true}})

func _apply_dot(enemy: Dictionary, kind: String, source: Dictionary, dps: float, duration: float, id: String) -> void:
	if dps<=0: return
	var statuses: Dictionary=enemy.get("skillStatuses",{})
	var previous: Dictionary=statuses.get(kind,{})
	var stronger: bool=previous.is_empty() or dps>=float(previous.get("dps",0))
	var snapshot: Dictionary={"id":source.get("id",-1),"type":source.get("type",""),"position":source.get("position",Vector2.ZERO),"campaignLevel":source.get("campaignLevel",1),"skillMeta":source.get("skillMeta",{}).duplicate(true)}
	statuses[kind]={"endAt":clock+duration,"nextTickAt":float(previous.get("nextTickAt",clock+DOT_TICK_SECONDS)),"dps":maxf(dps,float(previous.get("dps",0))),"source":snapshot if stronger else previous.source,"skillId":id,"tickSerial":int(previous.get("tickSerial",0))}
	if not statuses[kind].source.skillMeta is Dictionary: statuses[kind].source.skillMeta={}
	# A committed status has independent impacts; the original hit's victim
	# marker must not suppress every later burn/poison tick on that same victim.
	statuses[kind].source.skillMeta.erase("damagedTargets")
	statuses[kind].source.skillMeta.merge({"generation":generation,"proc":false,"committed":true},true)
	enemy["skillStatuses"]=statuses
	_event("status",source,enemy,{"skillId":id,"effectKind":"burn" if kind=="burn" else "poison","duration":duration,"flags":{"burning":kind=="burn","poisoned":kind=="poison"}})

func _tick_enemy_statuses(enemy: Dictionary) -> void:
	var statuses: Dictionary=enemy.get("skillStatuses",{})
	if statuses.is_empty(): return
	for kind in statuses.keys():
		var status: Dictionary=statuses[kind]
		if kind in ["burn","poison"]:
			while float(enemy.get("hp",0))>0 and float(status.nextTickAt)<=minf(clock,float(status.endAt))+.0000001:
				status.tickSerial=int(status.tickSerial)+1
				var source: Dictionary=status.source.duplicate(true)
				source.skillMeta.merge({"generation":generation,"proc":false,"impactId":"g%d:dot:%d:%s:%d" % [generation,int(enemy.id),str(kind),int(status.tickSerial)]},true)
				var actual: float=battle._damage_enemy(enemy,float(status.dps)*DOT_TICK_SECONDS,str(source.type),source)
				if actual>0: _event("status_tick",source,enemy,{"skillId":str(status.skillId),"effectKind":"burn_tick" if kind=="burn" else "poison_tick","damage":actual,"flags":{"burning":kind=="burn","poisoned":kind=="poison"}})
				status.nextTickAt=float(status.nextTickAt)+DOT_TICK_SECONDS
		if clock>=float(status.get("endAt",0))-.0000001:
			if kind=="disrupt":
				for key in ["formationPattern","formationGroup","formationLane","formationRank"]:
					enemy[key]=status.original.get(key,enemy.get(key))
			statuses.erase(kind)

func _secondary_source(source: Dictionary, meta: Dictionary, suffix: String, id: String) -> Dictionary:
	var result: Dictionary={"id":source.get("id",-1),"type":source.get("type",""),"position":source.get("position",Vector2.ZERO),"campaignLevel":source.get("campaignLevel",1),"skillMeta":meta.duplicate(true)}
	result.skillMeta.merge({"impactId":str(meta.get("impactId",meta.get("attackId","")))+suffix,"secondary":true},true)
	result["skillId"]=id
	return result

func _pierce(source: Dictionary, primary: Dictionary, damage: float, length: float, width: float, factor: float, meta: Dictionary, id: String) -> void:
	var start: Vector2=_position(source)
	var impact: Vector2=_position(primary)
	var direction: Vector2=(impact-start).normalized()
	if direction.length_squared()<.5: return
	var candidates: Array=[]
	for enemy in battle.enemies:
		if int(enemy.id)==int(primary.id) or float(enemy.hp)<=0 or int(enemy.pathIndex)!=int(primary.pathIndex): continue
		var offset: Vector2=_position(enemy)-impact
		var behind: float=offset.dot(direction)
		if behind<=.004 or behind>length or absf(offset.cross(direction))>width: continue
		if not battle.ground_combat.land_segment_safe(impact,_position(enemy),0.0): continue
		candidates.append({"enemy":enemy,"distance":behind})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.distance)<float(b.distance))
	for index in range(mini(SECONDARY_LIMIT,candidates.size())):
		var enemy: Dictionary=candidates[index].enemy
		var actor: Dictionary=_secondary_source(source,meta,":pierce"+str(enemy.id),id)
		var actual: float=battle._damage_enemy(enemy,damage*factor,str(source.type),actor)
		if actual>0: _event("skill_hit",actor,enemy,{"skillId":id,"effectKind":"pierce","damage":actual,"flags":{"pierce":true}})

func _area_damage(source: Dictionary, position: Vector2, excluded_id: int, damage: float, radius: float, meta: Dictionary, id: String, effect: String, path_index: int = -1) -> void:
	var count: int=0
	for enemy in battle.enemies:
		if count>=SECONDARY_LIMIT: break
		if int(enemy.id)==excluded_id or float(enemy.hp)<=0 or (path_index>=0 and int(enemy.pathIndex)!=path_index) or _position(enemy).distance_to(position)>radius: continue
		var actor: Dictionary=_secondary_source(source,meta,":area"+str(enemy.id),id)
		var actual: float=battle._damage_enemy(enemy,damage,str(source.type),actor)
		if actual>0:
			count+=1
			_event("skill_hit",actor,enemy,{"skillId":id,"effectKind":effect,"damage":actual,"position":battle._normalized_position(position),"radius":radius,"flags":{"barrage":effect=="barrage","sweep":effect=="sweep"}})

func can_charge(unit: Dictionary) -> bool:
	return _alive(unit) and has_skill(unit,"commander_charge")

func guard_dash(unit: Dictionary, target: Dictionary) -> Dictionary:
	var result: Dictionary={"active":false,"speedFactor":1.0,"damageFactor":1.0,"skillId":""}
	if not _active_battle() or not _alive(unit) or not has_skill(unit,"naginata_guard_charge") or target.is_empty() or float(target.get("hp",0))<=0 or bool(unit.get("guardDashActive",false)) or float(unit.get("skillMana",0))<GUARD_MANA_MAX: return result
	var home: Dictionary={"position":unit.get("homePosition",unit.get("position",Vector2.ZERO))}
	if int(target.get("pathIndex",-1))!=int(unit.get("postPathIndex",-2)) or not _connected(home,target,float(unit.get("guardRadius",.18))): return result
	var cluster: int=0
	for enemy in battle.enemies:
		if float(enemy.hp)>0 and int(enemy.pathIndex)==int(target.pathIndex) and _position(enemy).distance_to(_position(target))<=GUARD_CLUSTER_RADIUS: cluster+=1
	if cluster<2: return result
	unit["skillMana"]=0.0
	unit["guardDashActive"]=true
	unit["guardDashTargetId"]=int(target.id)
	unit["skillActiveUntil"]=clock+.8
	unit["activeSkillIds"]=["naginata_guard_charge"]
	result.merge({"active":true,"speedFactor":GUARD_DASH_SPEED,"damageFactor":GUARD_DASH_DAMAGE,"skillId":"naginata_guard_charge"},true)
	_event("skill",unit,target,{"skillId":"naginata_guard_charge","effectKind":"guard_charge","flags":{"guardCharge":true},"mana":0.0,"maxMana":GUARD_MANA_MAX})
	return result

func finish_guard_dash(unit: Dictionary, impact: bool = false) -> void:
	if not bool(unit.get("guardDashActive",false)): return
	unit["guardDashActive"]=false
	unit["guardDashTargetId"]=-1
	if impact and _alive(unit) and has_skill(unit,"naginata_charge_guard"):
		unit["invulnerableUntil"]=clock+GUARD_INVULNERABLE_SECONDS
		_event("status",unit,{}, {"skillId":"naginata_charge_guard","effectKind":"invulnerable","duration":GUARD_INVULNERABLE_SECONDS,"flags":{"invulnerable":true}})

func _disrupt(unit: Dictionary, target: Dictionary) -> void:
	var group: String=str(target.get("formationGroup",""))
	if group.is_empty() or str(target.get("formationPattern",""))!="formation": return
	for enemy in battle.enemies:
		if float(enemy.hp)<=0 or int(enemy.pathIndex)!=int(target.pathIndex) or str(enemy.get("formationGroup",""))!=group or _position(enemy).distance_to(_position(target))>DISRUPT_RADIUS: continue
		var statuses: Dictionary=enemy.get("skillStatuses",{})
		var original: Dictionary={}
		for key in ["formationPattern","formationGroup","formationLane","formationRank"]: original[key]=enemy.get(key)
		statuses["disrupt"]={"endAt":clock+DISRUPT_DURATION,"skillId":"commander_break","original":original}
		enemy["skillStatuses"]=statuses
		enemy["formationPattern"]="disrupted"
		enemy["formationGroup"]=""
		enemy["formationLane"]=2 if int(enemy.id)%2==0 else -2
		_event("status",unit,enemy,{"skillId":"commander_break","effectKind":"disrupt","duration":DISRUPT_DURATION,"flags":{"formationBroken":true}})

func _support_radius(unit: Dictionary) -> float:
	return float(battle._stats(unit).range) if is_instance_valid(battle) else .16

func _mantra_source(unit: Dictionary) -> Dictionary:
	if not is_instance_valid(battle) or str(unit.get("type","")) not in ["naginata","commander"]: return {}
	var best: Dictionary={}
	var best_factor: float=1.0
	for monk in battle.units:
		if _alive(monk) and has_skill(monk,"monk_mantra") and _connected(monk,unit,_support_radius(monk)):
			var factor: float=float(support_stats(monk).mantraResourceFactor)
			if factor>best_factor: best=monk;best_factor=factor
	return best

func mana_charge_factor(unit: Dictionary) -> float:
	var source: Dictionary=_mantra_source(unit)
	return float(support_stats(source).mantraResourceFactor) if not source.is_empty() else 1.0

func support_stats(unit: Dictionary) -> Dictionary:
	var definition: Dictionary=battle._unit_definition(unit) if is_instance_valid(battle) else unit.get("definition",{})
	var growth: Dictionary=UnitGrowth.factors(unit,definition)
	var healing: float=float(growth.healing)
	var resources: float=float(growth.supportResource)
	return {"healingFactor":healing,"resourceFactor":resources,"healAmount":BASIC_HEAL_AMOUNT*healing,"healInterval":BASIC_HEAL_INTERVAL,"talismanPerSecond":TALISMAN_PER_SECOND*healing,"prayerHealAmount":PRAYER_HEAL_AMOUNT*healing,"prayerManaAmount":minf(GUARD_MANA_MAX,PRAYER_MANA_AMOUNT*resources),"prayerChargeSeconds":PRAYER_CHARGE_SECONDS*resources,"mantraResourceFactor":1.0+(MANTRA_RESOURCE_FACTOR-1.0)*resources}

func cavalry_charge_factor(unit: Dictionary) -> float:
	return mana_charge_factor(unit)

func _healers(skill_id: String = "") -> Array:
	var result: Array=[]
	for monk in battle.units:
		if _alive(monk) and str(monk.type)=="monk" and (skill_id.is_empty() or has_skill(monk,skill_id)): result.append(monk)
	result.sort_custom(func(first: Dictionary,second: Dictionary):
		var first_power: float=float(support_stats(first).healingFactor)
		var second_power: float=float(support_stats(second).healingFactor)
		return int(first.id)<int(second.id) if is_equal_approx(first_power,second_power) else first_power>second_power
	)
	return result

func _heal_pulse() -> void:
	var claimed: Dictionary={}
	for monk in _healers():
		var best: Dictionary={}
		var ratio: float=1.0
		for target in battle.units:
			if int(target.id)==int(monk.id) or not _alive(target) or not target.has("hp") or float(target.get("maxHp",0))<=0 or claimed.has(int(target.id)): continue
			if not _connected(monk,target,_support_radius(monk)): continue
			var health: float=float(target.hp)/float(target.maxHp)
			if health<ratio: best=target;ratio=health
		if best.is_empty(): continue
		claimed[int(best.id)]=true
		var support: Dictionary=support_stats(monk)
		var actual: float=_heal(monk,best,float(support.healAmount),"monk_heal","heal")
		if actual>0 and has_skill(monk,"monk_talisman"):
			var statuses: Dictionary=best.get("friendlySkillStatuses",{})
			var old: Dictionary=statuses.get("talisman",{})
			var old_amount: float=float(old.get("amountPerSecond",0)) if float(old.get("endAt",0))>clock else 0.0
			var stronger: bool=float(support.talismanPerSecond)>=old_amount
			statuses["talisman"]={"endAt":clock+TALISMAN_DURATION,"nextTickAt":float(old.get("nextTickAt",clock+1.0)),"amountPerSecond":maxf(float(support.talismanPerSecond),old_amount),"source":{"id":monk.id,"type":"monk","position":monk.position} if stronger else old.get("source",{}),"skillId":"monk_talisman"}
			best["friendlySkillStatuses"]=statuses

func _heal(source: Dictionary, target: Dictionary, amount: float, id: String, effect: String) -> float:
	if not _alive(target) or not target.has("hp") or float(target.get("maxHp",0))<=0: return 0.0
	var before: float=float(target.hp)
	var healed: float=maxf(0.0,minf(float(target.maxHp),before+maxf(0,amount))-before)
	if healed<=0: return 0.0
	target["hp"]=before+healed
	if _alive(source) and str(source.get("type",""))=="monk" and source.has("healingUntil"):
		source["healingUntil"]=clock+HEAL_POSE_SECONDS
		source["healingTargetId"]=int(target.id)
		source["animation"]="heal"
		source["animationClock"]=0.0
	_event("heal",source,target,{"skillId":id,"effectKind":effect,"healAmount":healed,"hpBefore":before,"hpAfter":before+healed,"flags":{"healing":true,"talisman":effect=="talisman_tick","prayer":effect=="victory_prayer"}})
	return healed

func _tick_talisman(unit: Dictionary) -> void:
	var statuses: Dictionary=unit.get("friendlySkillStatuses",{})
	var status: Dictionary=statuses.get("talisman",{})
	if status.is_empty(): return
	while float(status.nextTickAt)<=minf(clock,float(status.endAt))+.0000001:
		_heal(status.source,unit,float(status.get("amountPerSecond",TALISMAN_PER_SECOND)),"monk_talisman","talisman_tick")
		status.nextTickAt=float(status.nextTickAt)+1.0
	if clock>=float(status.endAt)-.0000001: statuses.erase("talisman")

func on_enemy_killed(enemy: Dictionary, killer: Dictionary) -> void:
	var enemy_id: int=int(enemy.get("id",-1))
	var killer_id: int=int(killer.get("id",killer.get("actorId",-1)))
	if not _active_battle() or float(enemy.get("hp",1))>0 or bool(enemy.get("escaped",false)) or enemy_id<0 or _seen_kills.has(enemy_id) or not _registered_units.has(killer_id): return
	_seen_kills[enemy_id]=true
	for monk in _healers("monk_victory_prayer"):
		if not _connected(monk,enemy,_support_radius(monk)): continue
		monk["prayerCount"]=mini(PRAYER_REQUIRED,int(monk.get("prayerCount",0))+1)
		if int(monk.prayerCount)>=PRAYER_REQUIRED: _cast_prayer(monk)

func _cast_prayer(monk: Dictionary) -> void:
	if clock<float(monk.get("prayerReadyAt",0)) or int(monk.get("prayerCount",0))<PRAYER_REQUIRED: return
	var affected: Array=[]
	for ally in battle.units:
		if not _alive(ally) or not _connected(monk,ally,_support_radius(monk)) or clock<float(_prayer_target_ready.get(int(ally.id),0)): continue
		var missing_health: bool=ally.has("hp") and float(ally.get("maxHp",0))>float(ally.hp)
		var need_mana: bool=has_skill(ally,"naginata_guard_charge") and float(ally.get("skillMana",0))<GUARD_MANA_MAX
		var need_charge: bool=can_charge(ally) and float(ally.get("chargeCooldown",0))>0
		if missing_health or need_mana or need_charge: affected.append(ally)
	if affected.is_empty(): return
	monk["prayerCount"]=0
	monk["prayerReadyAt"]=clock+PRAYER_COOLDOWN
	var support: Dictionary=support_stats(monk)
	for ally in affected:
		_prayer_target_ready[int(ally.id)]=clock+PRAYER_COOLDOWN
		_heal(monk,ally,float(support.prayerHealAmount),"monk_victory_prayer","victory_prayer")
		if has_skill(ally,"naginata_guard_charge"): ally["skillMana"]=minf(GUARD_MANA_MAX,float(ally.get("skillMana",0))+float(support.prayerManaAmount))
		if can_charge(ally): ally["chargeCooldown"]=maxf(0,float(ally.get("chargeCooldown",0))-float(support.prayerChargeSeconds))
	_event("skill",monk,{}, {"skillId":"monk_victory_prayer","effectKind":"victory_prayer","affectedIds":affected.map(func(unit: Dictionary): return int(unit.id)),"flags":{"prayer":true}})

func public_state(unit: Dictionary) -> Dictionary:
	var ids: Array=skill_ids(unit)
	var alive: bool=_alive(unit)
	var active: Array=unit.get("activeSkillIds",[]).duplicate() if alive and float(unit.get("skillActiveUntil",0))>clock else []
	var formation: bool=alive and not _formation_commander(unit).is_empty()
	var aura: bool=alive and not _spear_support(unit).is_empty()
	var healing: bool=alive and float(unit.get("healingUntil",0))>clock
	var talisman: Dictionary=unit.get("friendlySkillStatuses",{}).get("talisman",{})
	var guard: bool=str(unit.get("type",""))=="naginata" and alive
	var invulnerable: bool=alive and float(unit.get("invulnerableUntil",0))>clock
	var mantra: bool=alive and not _mantra_source(unit).is_empty()
	if formation and not "commander_formation" in active: active.append("commander_formation")
	if invulnerable and not "naginata_charge_guard" in active: active.append("naginata_charge_guard")
	if healing: active.append("monk_heal")
	if not talisman.is_empty(): active.append("monk_talisman")
	var flags: Dictionary={"volley":alive and "archer_volley" in active,"fireArrow":alive and "archer_fire" in active,"barrage":alive and "archer_barrage" in active,"poisonTip":alive and has_skill(unit,"spear_poison"),"invulnerable":invulnerable,"formation":formation,"spearAura":aura,"guard":guard,"guardCharge":alive and bool(unit.get("guardDashActive",false)),"healing":healing,"talisman":not talisman.is_empty(),"mantra":mantra,"prayerReady":alive and int(unit.get("prayerCount",0))>=PRAYER_REQUIRED}
	return {"skillIds":ids,"activeSkillIds":active,"flags":flags,"mana":float(unit.get("skillMana",0)),"maxMana":GUARD_MANA_MAX,"supportState":"heal" if healing else "guard" if guard else "idle","healing":healing,"healingTargetId":int(unit.get("healingTargetId",-1)) if healing else -1,"healDuration":HEAL_POSE_SECONDS,"prayerCount":int(unit.get("prayerCount",0)),"prayerRequired":PRAYER_REQUIRED,"manaChargeFactor":mana_charge_factor(unit),"chargeReadinessFactor":cavalry_charge_factor(unit)}

func enemy_state(enemy: Dictionary) -> Dictionary:
	var statuses: Dictionary=enemy.get("skillStatuses",{})
	var ids: Array=[]
	var public_statuses: Array=[]
	for kind in statuses:
		var status: Dictionary=statuses[kind]
		var remaining: float=maxf(0,float(status.get("endAt",0))-clock)
		if remaining<=0: continue
		ids.append(str(status.get("skillId","")))
		public_statuses.append({"kind":str(kind),"skillId":str(status.get("skillId","")),"remaining":remaining,"dps":float(status.get("dps",0))})
	return {"activeSkillIds":ids,"statuses":public_statuses,"flags":{"burning":_status_active(statuses,"burn"),"poisoned":_status_active(statuses,"poison"),"armorWeakened":_status_active(statuses,"armor_break"),"formationBroken":_status_active(statuses,"disrupt")}}

func _status_active(statuses: Dictionary, kind: String) -> bool:
	return statuses.has(kind) and float(statuses[kind].get("endAt",0))>clock

func _event(type_name: String, actor: Dictionary, victim: Dictionary, extra: Dictionary) -> void:
	if is_instance_valid(battle): battle._combat_event(type_name,actor,victim,extra)
