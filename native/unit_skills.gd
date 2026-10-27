extends RefCounted
const UnitSkillActions = preload("res://native/unit_skill_actions.gd")
const UnitGrowth = preload("res://native/unit_growth.gd")
## Campaign-level abilities; the owning Game still applies HP, deaths and rewards.
const UNLOCKS: Dictionary = {
	"archer_fire":{"type":"archer","level":3},"archer_barrage":{"type":"archer","level":5},"archer_pair":{"type":"archer","level":5},"archer_double_shot":{"type":"archer","level":8},
	"spear_pierce":{"type":"spear","level":3},"spear_pair":{"type":"spear","level":4},"spear_company":{"type":"spear","level":8},"spear_brace":{"type":"spear","level":5},"spear_rear_rank":{"type":"spear","level":8},
	"samurai_parry":{"type":"samurai","level":3},"samurai_counter_combo":{"type":"samurai","level":5},"samurai_isshin":{"type":"samurai","level":8},
	"gunner_pierce":{"type":"gunner","level":3},"gunner_armor_break":{"type":"gunner","level":5},"gunner_braced_shot":{"type":"gunner","level":8},
	"naginata_sweep":{"type":"naginata","level":3},"naginata_guard_charge":{"type":"naginata","level":5},"naginata_charge_guard":{"type":"naginata","level":8},
	"monk_talisman":{"type":"monk","level":3},"monk_ward":{"type":"monk","level":5},"monk_victory_prayer":{"type":"monk","level":8},
	"commander_charge":{"type":"commander","level":3},"commander_impact":{"type":"commander","level":5},"commander_rally":{"type":"commander","level":8},
	"ninja_timed_charge":{"type":"ninja","level":3},"ninja_opening_combo":{"type":"ninja","level":5},"ninja_charge_shrapnel":{"type":"ninja","level":8}
}
const VOLLEY_DAMAGE_FACTOR: float = 1.08
const VOLLEY_WINDOW: float = .10
const BARRAGE_ARROWS: int = 3
const BARRAGE_ARROW_FACTOR: float = .45
const BARRAGE_RADIUS: float = .045
const BARRAGE_SPLASH_FACTOR: float = .28
const SECONDARY_LIMIT: int = 4
const ENEMY_QUERY_CELL: float = .08
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
const NINJA_FUSE_SECONDS: float=.75
const NINJA_CHARGE_FACTOR: float=4.0
const NINJA_SHRAPNEL_RADIUS: float=.065
const NINJA_SHRAPNEL_FACTOR: float=.60
const NINJA_SHRAPNEL_LIMIT: int=4

var battle: Node2D
var actions = UnitSkillActions.new()
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
var _history_prune_cache: Dictionary = {}
var _seen_kills: Dictionary = {}
var _registered_units: Dictionary = {}
var _ninja_charges: Dictionary={}
var _ninja_commits: Dictionary={}
var _prayer_target_ready: Dictionary = {}
var _unlock_levels_by_type: Dictionary = {}
var _query_scopes: Array = []
var _provider_roster: Dictionary = {}
var _provider_units: Array = []
var _provider_roster_size: int = -1
var _provider_generation: int = -1
var _provider_roster_dirty: bool = true

func begin_query_scope(read_only: bool = false) -> Dictionary:
	# A scope owns only classification. HP, positions, aim and current level
	# remain live throughout simulation; derived values are cached only in
	# synchronous read-only snapshot/render calls.
	var scope: Dictionary={"readOnly":read_only,"generation":generation,"stats":{},"publicStates":{}}
	if is_instance_valid(battle):
		scope["unitRoster"]=battle.units
		scope["unitRosterSize"]=battle.units.size()
	_query_scopes.append(scope)
	_provider_roster_dirty=true
	return scope

func end_query_scope(scope: Dictionary) -> void:
	if not _query_scopes.is_empty() and is_same(_query_scopes.back(),scope): _query_scopes.pop_back()
	_provider_roster_dirty=true

func suspend_query_scopes() -> Dictionary:
	# Signal subscribers may replace roles/actors in place and query again
	# before returning. They must observe a fresh, uncached live roster.
	var suspended: Dictionary={"scopes":_query_scopes,"generation":generation,"battle":battle}
	_query_scopes=[]
	return suspended

func resume_query_scopes(suspended: Dictionary) -> void:
	if int(suspended.generation)!=generation or not is_same(suspended.battle,battle): return
	_query_scopes=suspended.scopes
	invalidate_roster_index()
	if is_instance_valid(battle):
		battle.ground_combat.invalidate_combat_queries()
		battle.painted_actors.invalidate_display_frame()

func invalidate_roster_index() -> void:
	_provider_roster_dirty=true
	for scope in _query_scopes:
		scope["stats"]={}
		scope["publicStates"]={}
		for key in ["formationLookup","visibleFieldRect","healthLayouts","enemyAreaIndex","movementQueryRadius","movementQueryClock","activeAuraQuery"]: scope.erase(key)
		# Game validates ID-index slots against the live array on every lookup.
		# Only classification needs rebuilding after arbitrary signal callbacks.
		var enemies: Dictionary=scope.get("enemyLookup",{})
		if not enemies.is_empty():
			enemies["cohorts"]={}
			enemies["cohortsReady"]=false

func invalidate_layout_queries() -> void:
	for scope in _query_scopes:
		scope.erase("visibleFieldRect")
		scope.erase("healthLayouts")

func _ensure_provider_roster() -> void:
	if not is_instance_valid(battle): return
	if not _provider_roster_dirty and _provider_generation==generation and _provider_roster_size==battle.units.size() and is_same(_provider_units,battle.units): return
	var started: int=Time.get_ticks_usec() if bool(battle.performance_profiling_enabled) else 0
	invalidate_roster_index()
	_provider_roster={"samurai":[],"commander":[],"monk":[],"marching":[]}
	for unit in battle.units:
		var type_name: String=str(unit.get("type",""))
		if type_name in ["samurai","commander","monk"]: _provider_roster[type_name].append(unit)
		if type_name in ["spear","samurai","commander"]: _provider_roster.marching.append(unit)
	_provider_units=battle.units
	_provider_roster_size=battle.units.size()
	_provider_generation=generation
	_provider_roster_dirty=false
	if bool(battle.performance_profiling_enabled): battle._profile_elapsed("skillRosterIndex",started,battle.units.size())

func _providers(type_name: String) -> Array:
	# Direct calls outside a declared batch use the authoritative live roster,
	# including arbitrary test/editor replacements with unchanged length.
	if _query_scopes.is_empty(): return battle.units
	_ensure_provider_roster()
	return _provider_roster.get(type_name,[])

func membership_query_context() -> Dictionary:
	# Membership may be indexed during mutation, but actor fields stay live.
	# Signal suspension and roster invalidation clear this batch-local index.
	if _query_scopes.is_empty(): return {}
	var scope: Dictionary=_query_scopes.back()
	return scope if int(scope.generation)==generation else {}

func stationary_enemy_queries(enabled: bool) -> void:
	# Only enabled around damage/animation phases that never move enemies.
	# Movement and external calls retain live linear-query semantics.
	var context: Dictionary=membership_query_context()
	if context.is_empty(): return
	context["stationaryEnemyQueries"]=enabled
	context.erase("enemyAreaIndex")

func enemy_area_candidates(position: Vector2, radius: float) -> Array:
	return _enemy_area_candidates(position,radius)

func _enemy_area_candidates(position: Vector2, radius: float) -> Array:
	var context: Dictionary=membership_query_context()
	if context.is_empty() or not bool(context.get("stationaryEnemyQueries",false)):
		return battle.enemies
	# An arbitrary observer may move/replace/append enemies during a hit.
	# Preserve the original live-array iteration contract in that case.
	if not battle.game_event.get_connections().is_empty(): return battle.enemies
	var index: Dictionary=context.get("enemyAreaIndex",{})
	if index.is_empty() or int(index.count)!=battle.enemies.size() or not is_same(index.roster,battle.enemies):
		var cells: Dictionary={}
		for slot in range(battle.enemies.size()):
			var point: Vector2=_position(battle.enemies[slot])
			var cell: Vector2i=Vector2i(floori(point.x/ENEMY_QUERY_CELL),floori(point.y/ENEMY_QUERY_CELL))
			if not cells.has(cell): cells[cell]=[]
			cells[cell].append(slot)
		index={"roster":battle.enemies,"count":battle.enemies.size(),"cells":cells}
		context["enemyAreaIndex"]=index
	var first: Vector2i=Vector2i(floori((position.x-radius)/ENEMY_QUERY_CELL),floori((position.y-radius)/ENEMY_QUERY_CELL))
	var last: Vector2i=Vector2i(floori((position.x+radius)/ENEMY_QUERY_CELL),floori((position.y+radius)/ENEMY_QUERY_CELL))
	var slots: Array=[]
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			slots.append_array(index.cells.get(Vector2i(x,y),[]))
	# Area attacks keep roster order; piercing retains its existing distance
	# sort and tie input order. Exact distance/terrain checks remain below.
	slots.sort()
	var result: Array=[]
	for slot in slots: result.append(battle.enemies[int(slot)])
	return result

func freeze_query_snapshot(value: Variant) -> void:
	# Only newly built query results belong here, never live actor/config data.
	# The engine freezes one container at a time, so protect owned children too.
	if value is Dictionary:
		if value.is_read_only(): return
		for child in value.values(): freeze_query_snapshot(child)
		value.make_read_only()
	elif value is Array:
		if value.is_read_only(): return
		for child in value: freeze_query_snapshot(child)
		value.make_read_only()

func read_query_context() -> Dictionary:
	if _query_scopes.is_empty(): return {}
	var scope: Dictionary=_query_scopes.back()
	if not bool(scope.readOnly) or int(scope.generation)!=generation: return {}
	# Stats and current public flags no longer depend on the retired provider
	# auras. Build the provider lists only when _providers actually needs them.
	# Still invalidate derived values after a roster replacement in a batch.
	if is_instance_valid(battle) and (int(scope.get("unitRosterSize",-1))!=battle.units.size() or not is_same(scope.get("unitRoster",[]),battle.units)):
		invalidate_roster_index()
		scope["unitRoster"]=battle.units
		scope["unitRosterSize"]=battle.units.size()
	return scope

func _unlock_levels(type_name: String) -> Dictionary:
	if _unlock_levels_by_type.is_empty():
		for id in UNLOCKS:
			var definition: Dictionary=UNLOCKS[id]
			var owner_type: String=str(definition.type)
			if not _unlock_levels_by_type.has(owner_type): _unlock_levels_by_type[owner_type]={}
			_unlock_levels_by_type[owner_type][str(id)]=int(definition.level)
	return _unlock_levels_by_type.get(type_name,{})

func bind(value: Node2D) -> void:
	battle=value
	actions.bind(self)

func reset() -> void:
	generation+=1
	actions.reset()
	_query_scopes.clear()
	_provider_roster.clear()
	_provider_units=[]
	invalidate_roster_index()
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
	_history_prune_cache.clear()
	_seen_kills.clear()
	_ninja_charges.clear()
	_ninja_commits.clear()
	_registered_units.clear()
	_prayer_target_ready.clear()
	if is_instance_valid(battle):
		for unit in battle.units: initialize_unit(unit)
		for enemy in battle.enemies: enemy["skillStatuses"]={}

func initialize_unit(unit: Dictionary) -> void:
	invalidate_roster_index()
	actions.initialize_unit(unit)
	unit.merge({"skillMana":0.0,"maxSkillMana":GUARD_MANA_MAX,"guardDashActive":false,"guardDashTargetId":-1,"invulnerableUntil":0.0,"lastVolleySerial":-1,"skillActiveUntil":0.0,"activeSkillIds":[],"skillMeta":{},"healingUntil":0.0,"healingTargetId":-1,"healDuration":HEAL_POSE_SECONDS,"prayerCount":0,"prayerReadyAt":0.0,"friendlySkillStatuses":{}},true)
	_registered_units[int(unit.get("id",-1))]={"type":str(unit.get("type","")),"campaignLevel":_level(unit)}
	if str(unit.get("type",""))=="ninja": unit["ninjaComboComplete"]=false;unit["ninjaFinalApproach"]=false

func _level(unit: Dictionary) -> int:
	return clampi(int(unit.get("campaignLevel",1)),1,10)

func has_skill(unit: Dictionary, id: String) -> bool:
	var levels: Dictionary=_unlock_levels(str(unit.get("type","")))
	return levels.has(id) and _level(unit)>=int(levels[id])

func skill_ids(unit: Dictionary) -> Array:
	var result: Array=[]
	for id in _unlock_levels(str(unit.get("type",""))):
		if has_skill(unit,str(id)): result.append(str(id))
	return result

func recruit_quantity(type_name: String, campaign_level: int) -> int:
	var definition: Dictionary = battle.recruit_catalog.get(type_name,{}) if is_instance_valid(battle) else {}
	return UnitGrowth.recruit_quantity(type_name,campaign_level,definition)

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
	for ally in _providers("marching"):
		if int(ally.id)==int(commander.id) or not _alive(ally) or str(ally.type) not in ["spear","samurai","commander"]: continue
		if int(ally.get("postPathIndex",-1))!=int(commander.get("postPathIndex",-2)) or not _connected(commander,ally,FORMATION_RADIUS): continue
		var aim: Vector2=ally.get("aim",Vector2.ZERO)
		var lane: int=int(ally.get("formationLane",0))
		if aim.length_squared()<.001 or direction.normalized().dot(aim.normalized())<.8 or lane in lanes: continue
		members.append(ally)
		lanes.append(lane)
	return members if members.size()>=3 else []

func _formation_commander(unit: Dictionary) -> Dictionary:
	if not is_instance_valid(battle) or not unit.has("position") or str(unit.get("type","")) not in ["spear","samurai","commander"]: return {}
	var context: Dictionary=read_query_context()
	if not context.is_empty():
		if not context.has("formationLookup"):
			var lookup: Dictionary={}
			for commander in _providers("commander"):
				if not has_skill(commander,"commander_formation"): continue
				for member in _formation_members(commander):
					if not lookup.has(int(member.id)): lookup[int(member.id)]=commander
			context["formationLookup"]=lookup
		return context.formationLookup.get(int(unit.get("id",-1)),{})
	for commander in _providers("commander"):
		if not has_skill(commander,"commander_formation"): continue
		for member in _formation_members(commander):
			if int(member.id)==int(unit.get("id",-1)): return commander
	return {}

func _spear_support(unit: Dictionary) -> Dictionary:
	if not is_instance_valid(battle) or str(unit.get("type",""))!="spear" or not unit.has("position"): return {}
	for samurai in _providers("samurai"):
		if _alive(samurai) and has_skill(samurai,"samurai_spear_aura") and _connected(samurai,unit,SPEAR_AURA_RANGE): return samurai
	return {}

func stat_modifiers(unit: Dictionary) -> Dictionary:
	return {"damageFactor":0.0 if str(unit.get("type",""))=="monk" else 1.0,"rangeFactor":1.08 if has_skill(unit,"naginata_sweep") else 1.0,"intervalFactor":1.0}

func attack_ready(unit: Dictionary) -> bool:
	return str(unit.get("type",""))!="monk" and _alive(unit) and not bool(unit.get("consumed",false))

func _active_battle() -> bool:
	return is_instance_valid(battle) and battle.running and not battle.paused and not battle.between_waves and not battle.finished

func step(delta: float) -> void:
	if not _active_battle() or not is_finite(delta) or delta<=0: return
	var step_generation: int=generation
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
	if step_generation!=generation: return
	_tick_ninja_charges()
	if step_generation!=generation or not _active_battle() or bool(battle.battle_closed): return
	if clock>=_next_heal_at:
		_heal_pulse()
		if step_generation!=generation or not _active_battle() or battle.battle_closed: return
		_next_heal_at=clock+BASIC_HEAL_INTERVAL
	for unit in battle.units:
		if step_generation!=generation or not _active_battle() or battle.battle_closed: return
		if _alive(unit) and has_skill(unit,"monk_victory_prayer") and int(unit.get("prayerCount",0))>=PRAYER_REQUIRED: _cast_prayer(unit)
	_prune_history(_seen_damage,"damage")
	_prune_history(_seen_releases,"releases")
	_prune_history(_seen_impacts,"impacts")

func _record_history(history: Dictionary, key: String, cache_key: String) -> void:
	var previous_count: int=history.size()
	var replacing: bool=history.has(key)
	history[key]=clock
	var cached: Dictionary=_history_prune_cache.get(cache_key,{})
	if cached.is_empty(): return
	# A new monotonic receipt cannot make an existing receipt expire earlier.
	# Refresh the bound on every write; replacement/rollback invalidates it.
	if replacing or not is_same(cached.history,history) or int(cached.count)!=previous_count or clock<float(cached.lastClock):
		_history_prune_cache.erase(cache_key)
		return
	cached["count"]=history.size()
	cached["oldest"]=minf(float(cached.oldest),clock)
	cached["lastClock"]=clock

func _prune_history(history: Dictionary, cache_key: String = "") -> void:
	if history.size()<512:
		_history_prune_cache.erase(cache_key)
		return
	var cached: Dictionary=_history_prune_cache.get(cache_key,{})
	if not cached.is_empty() and is_same(cached.history,history) and int(cached.count)==history.size() and clock>=float(cached.lastClock) and clock-float(cached.oldest)<=8.0:
		cached["lastClock"]=clock
		return
	var oldest: float=INF
	for key in history.keys():
		var timestamp: float=float(history[key])
		if clock-timestamp>8.0: history.erase(key)
		else: oldest=minf(oldest,timestamp)
	# Use the same subtraction and strict expiry boundary as the old loop.
	# Unnamed direct calls retain the uncached helper's original behavior.
	if cache_key.is_empty(): return
	if history.size()<512:
		_history_prune_cache.erase(cache_key)
	else:
		_history_prune_cache[cache_key]={"history":history,"count":history.size(),"oldest":oldest,"lastClock":clock}

func prepare_attack(unit: Dictionary, target: Dictionary, damage: float, release_time: float, charge: bool = false) -> Dictionary:
	if not _active_battle() or not _alive(unit) or target.is_empty() or float(target.get("hp",0))<=0 or str(unit.get("type",""))=="monk" or not is_finite(damage) or damage<=0: return {}
	if not battle.ground_combat.primary_target_allowed(unit,target,"prepare"): return {}
	if bool(unit.get("guardDashActive",false)) and int(unit.get("guardDashTargetId",-1))!=int(target.get("id",-2)): return {}
	_attack_serial+=1
	var ids: Array=skill_ids(unit)
	var flags: Dictionary={"volley":false,"fireArrow":has_skill(unit,"archer_fire"),"barrage":has_skill(unit,"archer_barrage"),"poisonTip":false,"pierce":has_skill(unit,"spear_pierce") or has_skill(unit,"gunner_pierce"),"guardCharge":bool(unit.get("guardDashActive",false))}
	var id: String=_attack_effect_skill(unit,charge)
	var token: String="g%d:a%d" % [generation,_attack_serial]
	var meta: Dictionary={"generation":generation,"attackId":token,"impactId":token+":primary","motionToken":token,"sourceId":int(unit.get("id",-1)),"sourceType":str(unit.type),"campaignLevel":_level(unit),"skillIds":ids,"flags":flags.duplicate(true),"proc":true,"committed":false,"baseDamage":maxf(0,damage)}
	var plan: Dictionary={"targetId":int(target.get("id",-1)),"damage":damage*BARRAGE_ARROW_FACTOR if has_skill(unit,"archer_barrage") else damage,"releaseTime":release_time,"charge":charge,"guardDash":bool(unit.get("guardDashActive",false)),"skillMeta":meta,"skillId":id,"skillIds":ids,"flags":flags,"effectKind":_effect_kind(id)}
	if str(unit.type)=="ninja" and has_skill(unit,"ninja_timed_charge"):
		# Use the actual prepared action duration. It already fits the existing
		# interval; display motion cannot create a separate combat clock.
		var duration: float=float(unit.get("attackDuration",minf(battle._animation_duration("attack"),float(battle._read_stats(unit).interval)*.95)))
		var combo: bool=has_skill(unit,"ninja_opening_combo") and not bool(unit.get("ninjaComboComplete",false))
		plan["ninjaAction"]="combo" if combo else "plant"
		plan["ninjaImpactTimes"]=[duration*.25,duration*.55,duration*.85] if combo else [duration*.50]
		plan["ninjaNextImpact"]=0
		plan["ninjaBattleGeneration"]=int(battle.battle_generation)
		plan["releaseTime"]=duration*.85 if combo else duration*.50
		plan["skillId"]="ninja_opening_combo" if combo else "ninja_timed_charge"
		plan["effectKind"]="combo" if combo else "charge_plant"
		unit["activeSkillIds"]=[str(plan.skillId)]
	unit["skillMeta"]=meta.duplicate(true)
	unit["skillActiveUntil"]=clock+.65
	unit["activeSkillIds"]=_attack_active_skills(unit,charge)
	if plan.has("ninjaAction"): unit["activeSkillIds"]=[str(plan.skillId)]
	if not plan.has("ninjaAction"): actions.configure_plan(unit,target,plan)
	return plan

func _attack_effect_skill(unit: Dictionary, charge: bool) -> String:
	if bool(unit.get("guardDashActive",false)): return "naginata_guard_charge"
	for id in ["archer_barrage","archer_fire","spear_pierce","gunner_armor_break","gunner_pierce","naginata_sweep"]:
		if has_skill(unit,str(id)): return str(id)
	return "commander_charge" if charge and has_skill(unit,"commander_charge") else ""

func _attack_active_skills(unit: Dictionary, charge: bool) -> Array:
	var active: Array=[]
	for id in ["archer_fire","archer_barrage","spear_pierce","gunner_pierce","gunner_armor_break","naginata_sweep"]:
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
	shot.merge({"skillMeta":meta,"skillId":str(plan.get("skillId","")),"skillIds":plan.get("skillIds",[]).duplicate(),"flags":plan.get("flags",{}).duplicate(true),"effectKind":str(plan.get("effectKind","")),"campaignLevel":_level(unit),"releaseIndex":int(plan.get("releaseIndex",0)),"hitIndex":int(plan.get("hitIndex",0)),"releaseTime":float(plan.get("releaseTime",0.0)),"skillAction":str(plan.get("skillAction","")),"impactOffset":Vector2.ZERO},true)
	return shot

func after_release(unit: Dictionary, target: Dictionary, plan: Dictionary) -> void:
	if not _alive(unit) or target.is_empty() or not _valid_meta(plan.get("skillMeta",{})): return
	var operation_generation: int=generation
	var key: String=str(plan.skillMeta.attackId)
	if bool(plan.get("skillsReleaseConsumed",false)) or _seen_releases.has(key): return
	plan["skillsReleaseConsumed"]=true
	_record_history(_seen_releases,key,"releases")
	var damage: float=float(plan.get("damage",0))
	if has_skill(unit,"archer_barrage"):
		var direction: Vector2=(_position(target)-_position(unit)).normalized()
		for index in range(1,BARRAGE_ARROWS):
			if operation_generation!=generation or not _active_battle() or not _alive(unit): return
			var side: float=-1.0 if index==1 else 1.0
			var shot: Dictionary={"position":_position(unit)+direction.orthogonal()*side*.008,"targetId":int(target.id),"targetPos":_position(target),"damage":damage,"type":str(unit.type),"sourceId":int(unit.id),"sourcePosition":_position(unit),"speed":.65,"age":0.0}
			decorate_projectile(shot,unit,plan)
			shot["impactOffset"]=direction.orthogonal()*side*.024
			shot.skillMeta["impactId"]=key+":arrow"+str(index)
			battle.projectiles.append(shot)
			_event("shot",unit,target,{"skillId":"archer_barrage","skillIds":plan.skillIds,"effectKind":"barrage","flags":shot.flags,"projectileIndex":index,"releaseIndex":int(plan.get("releaseIndex",0)),"hitIndex":int(plan.get("hitIndex",0)),"releaseTime":float(plan.get("releaseTime",0.0)),"skillAction":str(plan.get("skillAction","")),"skillMeta":shot.skillMeta.duplicate(true),"campaignLevel":_level(unit)})
	if operation_generation!=generation or not _active_battle() or not _alive(unit): return
	if has_skill(unit,"spear_pierce"): _pierce(unit,target,damage,SPEAR_PIERCE_LENGTH,SPEAR_PIERCE_WIDTH,SPEAR_PIERCE_FACTOR,plan.skillMeta,"spear_pierce")
	if str(unit.get("type",""))=="naginata":
		var radius: float=SWEEP_UPGRADED_RADIUS if has_skill(unit,"naginata_sweep") else SWEEP_RADIUS
		_area_damage(unit,_position(target),int(target.id),damage*SWEEP_FACTOR,radius,plan.skillMeta,"naginata_sweep" if has_skill(unit,"naginata_sweep") else "","sweep",int(target.get("pathIndex",-1)))
	if bool(plan.get("guardDash",false)): finish_guard_dash(unit,true)

func after_projectile_hit(shot: Dictionary, target: Dictionary, _actual_damage: float) -> void:
	var meta: Dictionary=shot.get("skillMeta",{})
	if not _valid_meta(meta): return
	var key: String=str(meta.get("impactId",""))
	if bool(shot.get("skillsImpactConsumed",false)) or _seen_impacts.has(key): return
	shot["skillsImpactConsumed"]=true
	_record_history(_seen_impacts,key,"impacts")
	var source: Dictionary=_projectile_source(shot)
	var position: Vector2=shot.get("impactPosition",shot.get("targetPos",shot.get("position",Vector2.ZERO)))
	if "archer_barrage" in meta.get("skillIds",[]):
		_area_damage(source,position,int(shot.get("targetId",-1)),float(shot.damage)*BARRAGE_SPLASH_FACTOR,BARRAGE_RADIUS,meta,"archer_barrage","barrage")
	if not target.is_empty() and "gunner_pierce" in meta.get("skillIds",[]):
		_pierce(source,target,float(shot.damage),GUNNER_PIERCE_LENGTH,GUNNER_PIERCE_WIDTH,GUNNER_PIERCE_FACTOR,meta,"gunner_pierce")

func _projectile_source(shot: Dictionary) -> Dictionary:
	return {"id":int(shot.get("sourceId",-1)),"type":str(shot.get("type","")),"position":shot.get("sourcePosition",Vector2.ZERO),"campaignLevel":int(shot.get("campaignLevel",1)),"skillIds":shot.get("skillIds",[]).duplicate(),"releaseIndex":int(shot.get("releaseIndex",0)),"hitIndex":int(shot.get("hitIndex",0)),"releaseTime":float(shot.get("releaseTime",0.0)),"skillAction":str(shot.get("skillAction","")),"skillMeta":shot.get("skillMeta",{}).duplicate(true)}

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
		_record_history(_seen_damage,key,"damage")
	result["amount"]=actions.outgoing_bonus(enemy,float(result.amount),source)
	return result


func modify_enemy_armor(enemy: Dictionary, base_armor: float) -> float:
	var status: Dictionary=enemy.get("skillStatuses",{}).get("armor_break",{})
	return base_armor*ARMOR_BREAK_FACTOR if not status.is_empty() and float(status.get("endAt",0))>clock else base_armor

func modify_incoming(unit: Dictionary, amount: float, base_armor: float, attacker: Dictionary = {}, impact: Dictionary = {}) -> Dictionary:
	var bonus: float=UnitGrowth.armor(unit,false)-UnitGrowth.base_armor(str(unit.get("type","")))
	var armor: float=clampf(base_armor+bonus,0,UnitGrowth.MAX_ARMOR)
	var blocked: bool=float(unit.get("invulnerableUntil",0))>clock
	var result: Dictionary={"amount":0.0 if blocked or not is_finite(amount) else maxf(0,amount)*(1.0-armor),"armor":armor,"blocked":blocked,"skillId":"naginata_charge_guard" if blocked else "","flags":{"invulnerable":blocked}}
	return actions.modify_incoming(unit,result,attacker,impact)

func after_enemy_hit(enemy: Dictionary, actual_damage: float, unit_type: String, source: Dictionary) -> void:
	if actual_damage<=0 or float(enemy.get("hp",0))<=0: return
	var actor: Dictionary=_proc_source(source)
	if actor.is_empty(): return
	var meta: Dictionary=source.get("skillMeta",{})
	var base_damage: float=float(meta.get("baseDamage",actual_damage))
	if unit_type=="archer" and has_skill(actor,"archer_fire"): _apply_dot(enemy,"burn",source,minf(DOT_DPS_CAP,maxf(0,base_damage)*BURN_DPS_FACTOR),BURN_DURATION,"archer_fire")
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
	var result: Dictionary={"id":source.get("id",-1),"type":source.get("type",""),"position":source.get("position",Vector2.ZERO),"campaignLevel":source.get("campaignLevel",1),"skillIds":source.get("skillIds",meta.get("skillIds",[])).duplicate(),"releaseIndex":int(source.get("releaseIndex",meta.get("releaseIndex",0))),"hitIndex":int(source.get("hitIndex",meta.get("hitIndex",0))),"releaseTime":float(source.get("releaseTime",meta.get("releaseTime",0.0))),"skillMeta":meta.duplicate(true)}
	result.skillMeta.merge({"impactId":str(meta.get("impactId",meta.get("attackId","")))+suffix,"secondary":true},true)
	result["skillId"]=id
	return result

func _pierce(source: Dictionary, primary: Dictionary, damage: float, length: float, width: float, factor: float, meta: Dictionary, id: String) -> void:
	var operation_generation: int=generation
	var start: Vector2=_position(source)
	var impact: Vector2=_position(primary)
	var direction: Vector2=(impact-start).normalized()
	if direction.length_squared()<.5: return
	var candidates: Array=[]
	for enemy in _enemy_area_candidates(impact,sqrt(length*length+width*width)+.000001):
		if int(enemy.id)==int(primary.id) or float(enemy.hp)<=0 or int(enemy.pathIndex)!=int(primary.pathIndex): continue
		var offset: Vector2=_position(enemy)-impact
		var behind: float=offset.dot(direction)
		if behind<=.004 or behind>length or absf(offset.cross(direction))>width: continue
		if not battle.ground_combat.land_segment_safe(impact,_position(enemy),0.0): continue
		candidates.append({"enemy":enemy,"distance":behind})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.distance)<float(b.distance))
	for index in range(mini(SECONDARY_LIMIT,candidates.size())):
		if operation_generation!=generation: return
		var enemy: Dictionary=candidates[index].enemy
		var actor: Dictionary=_secondary_source(source,meta,":pierce"+str(enemy.id),id)
		var actual: float=battle._damage_enemy(enemy,damage*factor,str(source.type),actor)
		if operation_generation!=generation: return
		if actual>0: _event("skill_hit",actor,enemy,{"skillId":id,"effectKind":"pierce","damage":actual,"flags":{"pierce":true}})

func _area_damage(source: Dictionary, position: Vector2, excluded_id: int, damage: float, radius: float, meta: Dictionary, id: String, effect: String, path_index: int = -1) -> void:
	var operation_generation: int=generation
	var count: int=0
	for enemy in _enemy_area_candidates(position,radius):
		if operation_generation!=generation: return
		if count>=SECONDARY_LIMIT: break
		if int(enemy.id)==excluded_id or float(enemy.hp)<=0 or (path_index>=0 and int(enemy.pathIndex)!=path_index) or _position(enemy).distance_to(position)>radius: continue
		var actor: Dictionary=_secondary_source(source,meta,":area"+str(enemy.id),id)
		var actual: float=battle._damage_enemy(enemy,damage,str(source.type),actor)
		if operation_generation!=generation: return
		if actual>0:
			count+=1
			_event("skill_hit",actor,enemy,{"skillId":id,"effectKind":effect,"damage":actual,"position":battle._normalized_position(position),"radius":radius,"flags":{"barrage":effect=="barrage","sweep":effect=="sweep"}})

func can_charge(unit: Dictionary) -> bool:
	return _alive(unit) and has_skill(unit,"commander_charge")

func guard_dash(unit: Dictionary, target: Dictionary) -> Dictionary:
	var result: Dictionary={"active":false,"speedFactor":1.0,"damageFactor":1.0,"skillId":""}
	if not _active_battle() or not _alive(unit) or not has_skill(unit,"naginata_guard_charge") or target.is_empty() or float(target.get("hp",0))<=0 or bool(unit.get("guardDashActive",false)) or float(unit.get("skillMana",0))<GUARD_MANA_MAX: return result
	if not battle.ground_combat.guard_target_valid(unit,target,false): return result
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
	return float(battle._read_stats(unit).range) if is_instance_valid(battle) else .16

func _mantra_source(_unit: Dictionary) -> Dictionary:
	return {}

func mana_charge_factor(_unit: Dictionary) -> float:
	return 1.0

func support_stats(unit: Dictionary) -> Dictionary:
	var definition: Dictionary=battle._unit_definition(unit) if is_instance_valid(battle) else unit.get("definition",{})
	var growth: Dictionary=UnitGrowth.factors(unit,definition)
	var healing: float=float(growth.healing)
	var resources: float=float(growth.supportResource)
	return {"healingFactor":healing,"resourceFactor":resources,"healAmount":BASIC_HEAL_AMOUNT*healing,"healInterval":BASIC_HEAL_INTERVAL,"talismanPerSecond":TALISMAN_PER_SECOND*healing,"prayerHealAmount":PRAYER_HEAL_AMOUNT*healing,"prayerManaAmount":0.0,"prayerChargeSeconds":0.0,"mantraResourceFactor":1.0}

func cavalry_charge_factor(unit: Dictionary) -> float:
	return mana_charge_factor(unit)

func _healers(skill_id: String = "") -> Array:
	var result: Array=[]
	for monk in _providers("monk"):
		if _alive(monk) and str(monk.type)=="monk" and (skill_id.is_empty() or has_skill(monk,skill_id)): result.append(monk)
	result.sort_custom(func(first: Dictionary,second: Dictionary):
		var first_power: float=float(support_stats(first).healingFactor)
		var second_power: float=float(support_stats(second).healingFactor)
		return int(first.id)<int(second.id) if is_equal_approx(first_power,second_power) else first_power>second_power
	)
	return result

func _heal_pulse() -> void:
	var operation_generation: int=generation
	var claimed: Dictionary={}
	for monk in _healers():
		if operation_generation!=generation or not _active_battle(): return
		if not _alive(monk): continue
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
		if operation_generation!=generation or not _active_battle(): return
		if actual>0 and _alive(monk) and _alive(best) and is_same(battle.ground_combat._unit(int(monk.id)),monk) and is_same(battle.ground_combat._unit(int(best.id)),best) and has_skill(monk,"monk_talisman"):
			var statuses: Dictionary=best.get("friendlySkillStatuses",{})
			var old: Dictionary=statuses.get("talisman",{})
			var old_amount: float=float(old.get("amountPerSecond",0)) if float(old.get("endAt",0))>clock else 0.0
			var stronger: bool=float(support.talismanPerSecond)>=old_amount
			statuses["talisman"]={"endAt":clock+TALISMAN_DURATION,"nextTickAt":float(old.get("nextTickAt",clock+1.0)),"amountPerSecond":maxf(float(support.talismanPerSecond),old_amount),"source":{"id":monk.id,"type":"monk","position":monk.position,"campaignLevel":_level(monk),"skillIds":skill_ids(monk)} if stronger else old.get("source",{}),"skillId":"monk_talisman"}
			best["friendlySkillStatuses"]=statuses

func _heal(source: Dictionary, target: Dictionary, amount: float, id: String, effect: String) -> float:
	if not _alive(target) or not target.has("hp") or float(target.get("maxHp",0))<=0: return 0.0
	var before: float=float(target.hp)
	var healed: float=maxf(0.0,minf(float(target.maxHp),before+maxf(0,amount))-before)
	if healed<=0: return 0.0
	target["hp"]=before+healed
	var operation_generation: int=generation
	actions.after_heal(source,target,healed,effect)
	if operation_generation!=generation or not _active_battle() or battle.battle_closed or not _alive(target) or not is_same(battle.ground_combat._unit(int(target.id)),target): return healed
	if source.has("healingUntil") and (not _alive(source) or not is_same(battle.ground_combat._unit(int(source.id)),source)): return healed
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
	var operation_generation: int=generation
	for monk in _healers("monk_victory_prayer"):
		if operation_generation!=generation or not _active_battle() or battle.battle_closed: return
		if not _connected(monk,enemy,_support_radius(monk)): continue
		monk["prayerCount"]=mini(PRAYER_REQUIRED,int(monk.get("prayerCount",0))+1)
		if int(monk.prayerCount)>=PRAYER_REQUIRED: _cast_prayer(monk)

func _cast_prayer(monk: Dictionary) -> void:
	if not _active_battle() or not _alive(monk) or not has_skill(monk,"monk_victory_prayer") or clock<float(monk.get("prayerReadyAt",0)) or int(monk.get("prayerCount",0))<PRAYER_REQUIRED: return
	var affected: Array=[]
	for ally in battle.units:
		if not _alive(ally) or not ally.has("hp") or float(ally.get("maxHp",0))<=float(ally.hp) or not _connected(monk,ally,_support_radius(monk)) or clock<float(_prayer_target_ready.get(int(ally.id),0)): continue
		affected.append(ally)
	if affected.is_empty(): return
	monk["prayerCount"]=0
	monk["prayerReadyAt"]=clock+PRAYER_COOLDOWN
	var support: Dictionary=support_stats(monk)
	var operation_generation: int=generation
	var affected_ids: Array=[]
	for ally in affected:
		if operation_generation!=generation or not _active_battle() or not _alive(monk): return
		if not _alive(ally) or not is_same(battle.ground_combat._unit(int(ally.id)),ally) or float(ally.get("hp",0.0))>=float(ally.get("maxHp",0.0)): continue
		_prayer_target_ready[int(ally.id)]=clock+PRAYER_COOLDOWN
		if _heal(monk,ally,float(support.prayerHealAmount),"monk_victory_prayer","victory_prayer")>0: affected_ids.append(int(ally.id))
	if operation_generation==generation and _active_battle() and not battle.battle_closed and _alive(monk) and is_same(battle.ground_combat._unit(int(monk.id)),monk) and not affected_ids.is_empty(): _event("skill_cast",monk,{}, {"skillId":"monk_victory_prayer","skillIds":skill_ids(monk),"skillMeta":actions._event_meta(monk),"campaignLevel":_level(monk),"effectKind":"victory_prayer","duration":HEAL_POSE_SECONDS,"affectedIds":affected_ids,"flags":{"prayer":true}})

func public_state(unit: Dictionary) -> Dictionary:
	var context: Dictionary=read_query_context()
	var actor_id: int=int(unit.get("id",-1))
	if not context.is_empty() and actor_id>=0 and context.publicStates.has(actor_id):
		var cached: Dictionary=context.publicStates[actor_id]
		if is_same(cached.actor,unit): return cached.state.duplicate(true)
	var result: Dictionary=_build_public_state(unit)
	if not context.is_empty() and actor_id>=0: context.publicStates[actor_id]={"actor":unit,"state":result.duplicate(true)}
	return result

func _build_public_state(unit: Dictionary) -> Dictionary:
	var alive: bool=_alive(unit) and not bool(unit.get("consumed",false))
	var active: Array=unit.get("activeSkillIds",[]).duplicate() if alive and float(unit.get("skillActiveUntil",0))>clock else []
	var healing: bool=alive and float(unit.get("healingUntil",0))>clock
	var talisman: Dictionary=unit.get("friendlySkillStatuses",{}).get("talisman",{})
	var invulnerable: bool=alive and float(unit.get("invulnerableUntil",0))>clock
	if invulnerable and not "naginata_charge_guard" in active: active.append("naginata_charge_guard")
	if healing: active.append("monk_heal")
	if not talisman.is_empty(): active.append("monk_talisman")
	var flags: Dictionary={"volley":false,"fireArrow":alive and "archer_fire" in active,"barrage":alive and "archer_barrage" in active,"poisonTip":false,"invulnerable":invulnerable,"formation":false,"spearAura":false,"guard":str(unit.get("type",""))=="naginata" and alive,"guardCharge":alive and bool(unit.get("guardDashActive",false)),"healing":healing,"talisman":not talisman.is_empty(),"mantra":false,"prayerReady":alive and int(unit.get("prayerCount",0))>=PRAYER_REQUIRED,"ward":alive and float(unit.get("wardHp",0))>0.0,"rally":alive and float(unit.get("rallyUntil",0))>clock}
	var result: Dictionary={"skillIds":skill_ids(unit),"activeSkillIds":active,"flags":flags,"mana":float(unit.get("skillMana",0)),"maxMana":GUARD_MANA_MAX,"supportState":"heal" if healing else "guard" if bool(flags.guard) else "idle","healing":healing,"healingTargetId":int(unit.get("healingTargetId",-1)) if healing else -1,"healDuration":HEAL_POSE_SECONDS,"prayerCount":int(unit.get("prayerCount",0)),"prayerRequired":PRAYER_REQUIRED,"manaChargeFactor":1.0,"chargeReadinessFactor":1.0}
	result.merge(actions.public_state(unit),true)
	return result

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

func cancel_ninja_charges() -> void:
	_ninja_charges.clear()

func on_ninja_consumed(unit: Dictionary, reason: String) -> void:
	if reason=="charge_planted": return
	for charge_id in _ninja_charges.keys():
		if int(_ninja_charges[charge_id].source.id)==int(unit.get("id",-1)): _ninja_charges.erase(charge_id)

func cancel_ninja_target_charges(target: Dictionary) -> void:
	for charge_id in _ninja_charges.keys():
		var payload: Dictionary=_ninja_charges[charge_id]
		if int(payload.targetId)==int(target.get("id",-1)) and is_same(payload.target,target): _ninja_charges.erase(charge_id)

func _ninja_contact_valid(unit: Dictionary, target: Dictionary, plan: Dictionary) -> bool:
	return _active_battle() and not bool(battle.battle_closed) and _valid_meta(plan.get("skillMeta",{})) and int(plan.get("ninjaBattleGeneration",-1))==int(battle.battle_generation) and _alive(unit) and not bool(unit.get("consumed",false)) and is_same(battle.ground_combat._unit(int(unit.id)),unit) and is_same(unit.get("attackPlan",{}),plan) and not target.is_empty() and is_same(battle._enemy(int(target.id)),target) and battle.ground_combat.ninja_mission_target_valid(unit,target,true,true) and battle.ground_combat.melee_release_allowed(unit,target,plan,true)

func _abort_ninja_attack(unit: Dictionary, plan: Dictionary, reason: String) -> bool:
	plan["ninjaCancelled"]=true
	plan["nativeReleaseConsumed"]=true
	unit["ninjaComboComplete"]=false
	if float(unit.get("hp",0))>0 and not bool(unit.get("consumed",false)): battle.ground_combat.mark_ninja_consumed(unit,reason)
	return true

func _ninja_context_live(operation_generation: int, battle_generation: int) -> bool:
	return generation==operation_generation and is_instance_valid(battle) and int(battle.battle_generation)==battle_generation and _active_battle() and not bool(battle.battle_closed)

func advance_ninja_attack(unit: Dictionary, plan: Dictionary, animation_clock: float) -> bool:
	if bool(plan.get("ninjaReleaseInProgress",false)): return false
	if bool(plan.get("ninjaCancelled",false)) or bool(plan.get("nativeReleaseConsumed",false)): return true
	plan["ninjaReleaseInProgress"]=true
	var complete: bool=_advance_ninja_attack_contents(unit,plan,animation_clock)
	plan["ninjaReleaseInProgress"]=false
	return complete

func _advance_ninja_attack_contents(unit: Dictionary, plan: Dictionary, animation_clock: float) -> bool:
	var target: Dictionary=battle._enemy(int(plan.get("targetId",-1)))
	if not actions.ninja_preparation_valid(unit,target,plan): return _abort_ninja_attack(unit,plan,"target_lost")
	var operation_generation: int=generation
	var battle_generation: int=int(battle.battle_generation)
	var times: Array=plan.get("ninjaImpactTimes",[])
	var index: int=int(plan.get("ninjaNextImpact",0))
	while index<times.size() and animation_clock>=float(times[index]):
		if not _ninja_contact_valid(unit,target,plan): return _abort_ninja_attack(unit,plan,"target_lost")
		var receipt: String=str(plan.skillMeta.attackId)+":ninja:"+str(index)
		plan["ninjaNextImpact"]=index+1
		if _ninja_commits.has(receipt): index+=1;continue
		_ninja_commits[receipt]=true
		if str(plan.ninjaAction)=="plant": return _plant_ninja_charge(unit,target,plan)
		var source: Dictionary=battle._attack_source(unit,plan)
		source["campaignLevel"]=int(plan.skillMeta.get("campaignLevel",_level(unit)))
		source["skillMeta"]=plan.skillMeta.duplicate(true)
		source.skillMeta.erase("damagedTargets")
		source.skillMeta["impactId"]=receipt
		source["hitIndex"]=index
		source["ninjaAction"]="combo"
		unit["aim"]=(target.position-unit.position).normalized()
		var actual: float=battle._damage_enemy(target,float(plan.damage)*(1.0 if index==0 else .5),"ninja",source)
		if not _ninja_context_live(operation_generation,battle_generation): return true
		if actual<=0.0: return _abort_ninja_attack(unit,plan,"interrupted")
		plan["ninjaLandedHits"]=int(plan.get("ninjaLandedHits",0))+1
		var fields: Dictionary={"skillId":"ninja_opening_combo","skillIds":plan.skillIds.duplicate(),"skillMeta":source.skillMeta.duplicate(true),"campaignLevel":int(source.campaignLevel),"effectKind":"combo","hitIndex":index,"ninjaAction":"combo","damage":actual,"targetId":int(target.id)}
		_event("skill_hit",source,target,fields)
		if not _ninja_context_live(operation_generation,battle_generation): return true
		if not _ninja_contact_valid(unit,target,plan): return _abort_ninja_attack(unit,plan,"target_defeated" if float(target.get("hp",0))<=0 else "target_lost")
		index=int(plan.ninjaNextImpact)
	if index>=times.size():
		if int(plan.get("ninjaLandedHits",0))!=3: return _abort_ninja_attack(unit,plan,"interrupted")
		unit["ninjaComboComplete"]=true
		plan["nativeReleaseConsumed"]=true
		return true
	return false

func _plant_ninja_charge(unit: Dictionary, target: Dictionary, plan: Dictionary) -> bool:
	if not _ninja_contact_valid(unit,target,plan): return _abort_ninja_attack(unit,plan,"target_lost")
	if has_skill(unit,"ninja_opening_combo") and not bool(unit.get("ninjaComboComplete",false)): return _abort_ninja_attack(unit,plan,"interrupted")
	var charge_id: String=str(plan.skillMeta.attackId)+":charge:"+str(unit.id)
	if _ninja_commits.has(charge_id): return true
	_ninja_commits[charge_id]=true
	plan["nativeReleaseConsumed"]=true
	var source: Dictionary=battle._attack_source(unit,plan)
	source["campaignLevel"]=int(plan.skillMeta.get("campaignLevel",_level(unit)))
	source["skillMeta"]=plan.skillMeta.duplicate(true)
	source.skillMeta.erase("damagedTargets")
	source.skillMeta.merge({"committed":true,"proc":false,"impactId":charge_id+":main"},true)
	source["ninjaPayload"]=true
	source.erase("ninjaAction")
	source["chargeId"]=charge_id
	source["skillId"]="ninja_timed_charge"
	source["effectKind"]="charge_explosion"
	var payload: Dictionary={"id":charge_id,"generation":generation,"battleGeneration":int(battle.battle_generation),"targetId":int(target.id),"target":target,"source":source.duplicate(true),"baseDamage":float(plan.damage),"plantedAt":float(battle.elapsed),"detonateAt":float(battle.elapsed)+NINJA_FUSE_SECONDS,"shrapnel":has_skill(unit,"ninja_charge_shrapnel")}
	battle.ground_combat.mark_ninja_consumed(unit,"charge_planted")
	if not bool(unit.get("consumed",false)) or str(unit.get("consumeReason",""))!="charge_planted": return true
	_ninja_charges[charge_id]=payload
	var plant_meta: Dictionary=source.skillMeta.duplicate(true)
	plant_meta["impactId"]=charge_id+":plant"
	_event("skill_cast",source,target,{"skillId":"ninja_timed_charge","skillIds":source.get("skillIds",[]).duplicate(),"skillMeta":plant_meta,"campaignLevel":int(source.campaignLevel),"effectKind":"charge_plant","chargeId":charge_id,"targetId":int(target.id),"position":battle._normalized_position(target.position),"victimPosition":battle._normalized_position(target.position),"duration":NINJA_FUSE_SECONDS,"fuseSeconds":NINJA_FUSE_SECONDS,"plantedAt":payload.plantedAt})
	return true

func _ninja_payload_target_live(payload: Dictionary, target: Dictionary) -> bool:
	return int(payload.generation)==generation and int(payload.battleGeneration)==int(battle.battle_generation) and not target.is_empty() and is_same(payload.target,target) and float(target.get("hp",0))>0.0 and not bool(target.get("escaped",false)) and not battle._sailing_visual(target) and not bool(target.get("transportActive",false)) and not bool(target.get("ingressActive",false)) and (battle.ground_combat.is_tower_attacker(target) or not bool(target.get("stationaryEnemy",false)))

func _tick_ninja_charges() -> void:
	var operation_generation: int=generation
	var battle_generation: int=int(battle.battle_generation)
	var charge_ids: Array=_ninja_charges.keys()
	charge_ids.sort_custom(func(first: String,second: String) -> bool:
		var a: Dictionary=_ninja_charges[first]
		var b: Dictionary=_ninja_charges[second]
		if float(a.detonateAt)!=float(b.detonateAt): return float(a.detonateAt)<float(b.detonateAt)
		if int(a.source.id)!=int(b.source.id): return int(a.source.id)<int(b.source.id)
		return first<second
	)
	for charge_id in charge_ids:
		if not _ninja_context_live(operation_generation,battle_generation): return
		if not _ninja_charges.has(charge_id): continue
		var payload: Dictionary=_ninja_charges[charge_id]
		var target: Dictionary=battle._enemy(int(payload.targetId))
		if not _ninja_payload_target_live(payload,target): _ninja_charges.erase(charge_id);continue
		if float(battle.elapsed)<float(payload.detonateAt): continue
		_ninja_charges.erase(charge_id)
		var receipt: String=str(charge_id)+":explosion"
		if _ninja_commits.has(receipt): continue
		_ninja_commits[receipt]=true
		var origin: Vector2=target.position
		var source: Dictionary=payload.source.duplicate(true)
		source.position=origin
		battle._damage_enemy(target,float(payload.baseDamage)*NINJA_CHARGE_FACTOR,"ninja",source)
		if not _ninja_context_live(operation_generation,battle_generation): return
		var own_kill: bool=float(target.get("hp",0))<=0.0 and str(target.get("lastHit",{}).get("impactId",""))==str(source.skillMeta.impactId)
		if (not is_same(battle._enemy(int(payload.targetId)),target) and not own_kill) or (float(target.get("hp",0))<=0.0 and not own_kill): continue
		_event("skill_cast",source,target,{"skillId":"ninja_timed_charge","skillIds":source.get("skillIds",[]).duplicate(),"skillMeta":source.skillMeta.duplicate(true),"campaignLevel":int(source.campaignLevel),"effectKind":"charge_explosion","chargeId":str(charge_id),"targetId":int(payload.targetId),"position":battle._normalized_position(origin),"victimPosition":battle._normalized_position(origin),"duration":0.0,"radius":NINJA_SHRAPNEL_RADIUS if bool(payload.shrapnel) else 0.0})
		if not _ninja_context_live(operation_generation,battle_generation): return
		if bool(payload.shrapnel) and (float(target.get("hp",0))>0.0 or own_kill): _ninja_shrapnel(payload,origin,source)

func _ninja_fragment_valid(enemy: Dictionary, origin: Vector2, primary_id: int) -> bool:
	return not enemy.is_empty() and int(enemy.get("id",-1))!=primary_id and float(enemy.get("hp",0))>0.0 and not bool(enemy.get("escaped",false)) and str(enemy.get("combatRole",""))=="path_assault" and not bool(enemy.get("stationaryEnemy",false)) and not bool(enemy.get("fortification",false)) and not bool(enemy.get("transportActive",false)) and not bool(enemy.get("ingressActive",false)) and not battle._sailing_visual(enemy) and battle._enemy_visible(enemy) and enemy.position.distance_to(origin)<=NINJA_SHRAPNEL_RADIUS and battle.ground_combat.land_segment_safe(origin,enemy.position,.008)

func _ninja_shrapnel(payload: Dictionary, origin: Vector2, source: Dictionary) -> void:
	var operation_generation: int=generation
	var battle_generation: int=int(battle.battle_generation)
	var candidates: Array=[]
	for enemy in _enemy_area_candidates(origin,NINJA_SHRAPNEL_RADIUS):
		if _ninja_fragment_valid(enemy,origin,int(payload.targetId)): candidates.append(enemy)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var first: float=a.position.distance_squared_to(origin)
		var second: float=b.position.distance_squared_to(origin)
		return int(a.id)<int(b.id) if is_equal_approx(first,second) else first<second
	)
	# Pin the nearest eligible IDs once. A vanished candidate is not replaced
	# by a farther enemy after a reentrant impact callback.
	for index in range(mini(NINJA_SHRAPNEL_LIMIT,candidates.size())):
		var enemy: Dictionary=candidates[index]
		if not _ninja_context_live(operation_generation,battle_generation): return
		var primary: Dictionary=payload.target
		var own_primary_kill: bool=float(primary.get("hp",0))<=0.0 and str(primary.get("lastHit",{}).get("impactId",""))==str(source.skillMeta.impactId)
		if not own_primary_kill and (float(primary.get("hp",0))<=0.0 or not is_same(battle._enemy(int(payload.targetId)),primary)): return
		if not is_same(battle._enemy(int(enemy.id)),enemy) or not _ninja_fragment_valid(enemy,origin,int(payload.targetId)): continue
		var receipt: String=str(payload.id)+":fragment:"+str(enemy.id)
		if _ninja_commits.has(receipt): continue
		_ninja_commits[receipt]=true
		var actor: Dictionary=source.duplicate(true)
		actor.skillMeta.erase("damagedTargets")
		actor.skillMeta.merge({"impactId":receipt,"secondary":true,"committed":true,"proc":false},true)
		actor["skillId"]="ninja_charge_shrapnel"
		actor["effectKind"]="shrapnel"
		var actual: float=battle._damage_enemy(enemy,float(payload.baseDamage)*NINJA_SHRAPNEL_FACTOR,"ninja",actor)
		if not _ninja_context_live(operation_generation,battle_generation): return
		if actual>0: _event("skill_hit",actor,enemy,{"skillId":"ninja_charge_shrapnel","skillIds":actor.get("skillIds",[]).duplicate(),"skillMeta":actor.skillMeta.duplicate(true),"campaignLevel":int(actor.campaignLevel),"effectKind":"shrapnel","chargeId":str(payload.id),"targetId":int(enemy.id),"position":battle._normalized_position(origin),"radius":NINJA_SHRAPNEL_RADIUS,"damage":actual})

func _event(type_name: String, actor: Dictionary, victim: Dictionary, extra: Dictionary) -> void:
	if not is_instance_valid(battle): return
	var fields: Dictionary=battle._skill_event_fields(actor)
	fields["campaignLevel"]=_level(actor)
	fields["skillIds"]=actor.get("skillIds",actor.get("skillMeta",{}).get("skillIds",skill_ids(actor))).duplicate()
	fields.merge(extra,true)
	battle._combat_event(type_name,actor,victim,fields)
