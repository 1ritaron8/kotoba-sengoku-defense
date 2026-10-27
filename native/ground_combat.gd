extends RefCounted
const UnitGrowth = preload("res://native/unit_growth.gd")
const CrowdMelee = preload("res://native/crowd_melee.gd")
## Authored-route marching, one local support brawl, bounded guards and assassins.
const GROUND_TYPES: Array = ["spear","samurai","naginata","monk","ninja","commander"]
const HEALTH: Dictionary = {"archer":105.0,"spear":140.0,"samurai":175.0,"naginata":135.0,"monk":125.0,"ninja":160.0,"commander":210.0,"gunner":105.0}
const CAPACITY: Dictionary = {"spear":2,"samurai":1,"naginata":2,"monk":1,"ninja":1,"commander":1,"gunner":1}
const REACH: Dictionary = {"spear":0.041,"samurai":0.034,"naginata":0.045,"monk":0.036,"ninja":0.031,"commander":0.042,"gunner":0.030}
# Original ninja meshes need about .100 of normalized head/weapon clearance
# at the widest actual Main field; retain perspective and edge tolerance.
const AMBUSH_MIN_FOOT_Y: float = .115
const MARCH_SUPPORT_DROP_RADIUS: float = .10
const SPEAR_GATHER_SECONDS: float = 3.0
const SPEAR_GATHER_TICKS: int = 3000000
# Per local encounter: [friendly attackers, enemy attackers]. Progress runs
# from the actual allied march base (0) to that path's enemy ingress (1).
const MELEE_TERRITORY_LIMITS: Dictionary={"home":[6,3],"middle":[3,5],"enemy":[2,6]}
const MELEE_HOME_END: float=.40
const MELEE_MIDDLE_END: float=.70
const MELEE_ENCOUNTER_RADIUS: float=.09
const PAINTED_ROAD_HALF_WIDTH_ART_PIXELS: float=70.0
var battle: Node2D
var cumulative: Array = []
var march_bases: Array = []
var march_path_cursor: int = 0
var ambush_sites: Array = []
var water_rects: Array[Rect2] = []
var structure_segment_clear: Callable
var structure_placement_clear: Callable
var crowd = CrowdMelee.new()
var crowd_generation: int = -1
var support_cohorts: Dictionary = {}
var support_generation: int = -1
var gather_groups: Dictionary = {}
var spear_gather_windows: Dictionary = {}
var spear_gather_generation: int = -1
var territorial_melee_enabled: bool=false
var melee_seats: Dictionary={}
var melee_waiters: Dictionary={}
var melee_last_served: Dictionary={}
var melee_components: Dictionary={}
var melee_members: Dictionary={}
var melee_limits: Dictionary={}
var melee_seat_groups: Dictionary={}
var melee_waiter_groups: Dictionary={}
var melee_query_clock: float=-INF
var melee_query_generation: int=-1
var melee_serial: int=0
var melee_pair_components: Dictionary={}
var melee_component_roots: Dictionary={}
var melee_pair_locations: Dictionary={}
var melee_wait_order: Dictionary={}
var crowd_clock: float=-INF
var crowd_units: Array=[]
var crowd_enemies: Array=[]
var crowd_unit_count: int=-1
var crowd_enemy_count: int=-1
var combat_query_revision: int=0
var navigation_query_revision: int=0
var _combat_query_scope: Dictionary={}
var _combat_query_clock: float=-INF
var _combat_query_generation: int=-1
var _combat_query_terrain: Callable
var _live_check_depth: int=0
var _land_queries: Dictionary={}
var _land_query_count: int=0
var _road_queries: Dictionary={}
var _road_query_count: int=0
var _guard_segments: Dictionary={}
var _guard_segment_count: int=0
var _guard_nodes: Dictionary={}
var _guard_routes: Dictionary={}
var _guard_route_count: int=0
var _strike_queries: Dictionary={}
var _ninja_routes: Dictionary={}
const COMBAT_SEGMENT_CACHE_LIMIT: int=4096
const COMBAT_ROUTE_CACHE_LIMIT: int=256

static func is_ground(type_name: String) -> bool:
	return type_name in GROUND_TYPES

static func is_frontline(type_name: String) -> bool:
	return is_ground(type_name) or type_name=="gunner"

static func is_marching(type_name: String) -> bool:
	return type_name in ["spear","samurai","commander"]

static func is_ambush(type_name: String) -> bool:
	return type_name=="ninja"

static func base_march_only(type_name: String, stage: Dictionary = {}) -> bool:
	if not is_marching(type_name): return false
	# Spears retain their road-only role in every mission. Defense and advance
	# missions share base recruitment for all marchers; other attacking modes
	# retain their existing tactical drops for samurai and cavalry.
	if type_name=="spear": return true
	var scenario: Dictionary=stage.get("scenario",{})
	var mode: String=str(scenario.get("missionMode",stage.get("missionMode",stage.get("mode",""))))
	return mode not in ["encirclement","assault","siege"]

static func placement_contract(type_name: String, stage: Dictionary = {}) -> Dictionary:
	if type_name=="archer":
		return {"deploymentKind":"placed","movementRoleKo":"배치형","placementRole":"ranged","placementMode":"fixed_emplacement","combatRole":"ranged","roleKo":"고정 진지 사격","placementHintKo":"궁병은 황금색 사격 진지에만 배치합니다."}
	if type_name=="gunner":
		return {"deploymentKind":"placed","movementRoleKo":"배치형","placementRole":"ground","acceptedPlacementRoles":["ground","ranged"],"placementMode":"frontline_shooter","combatRole":"frontline_shooter","roleKo":"전선 · 진지 고정 사격","placementHintKo":"철포병은 청록색 전선이나 사격 진지의 빈자리에 배치합니다."}
	if type_name=="ninja":
		return {"deploymentKind":"ambush","movementRoleKo":"기습형","placementRole":"ambush","placementMode":"concealed_ambush","combatRole":"ground","roleKo":"소모성 강적 · 진지 암살","placementHintKo":"닌자는 보라색 기습 지점에서 접근 가능한 강적이나 적 진지 하나를 암살합니다. 폭약 설치나 임무 종료 시 소모되며 재사용할 수 없습니다.","markerColor":"b997ff"}
	if type_name=="monk":
		return {"deploymentKind":"support","movementRoleKo":"지원형","placementRole":"ground","placementMode":"frontline_support","combatRole":"support","roleKo":"고정 치료 · 아군 지원","placementHintKo":"승병은 청록색 지원 지점에서 아군을 치료합니다. 봉으로 공격하지 않습니다.","markerColor":"73e5d2"}
	if type_name=="naginata":
		return {"deploymentKind":"guard","movementRoleKo":"호위형","placementRole":"ground","placementMode":"emplacement_guard","combatRole":"guard","roleKo":"사격 진지 호위 · 장도 쓸기","placementHintKo":"장도병은 아군 진지 방어 구역 안에서 기지 공격자를 저지합니다. 구역 밖으로 추격하지 않고 표적을 잃으면 원위치로 복귀합니다.","markerColor":"73e5d2"}
	var base_only: bool=base_march_only(type_name,stage)
	var hint: String="육지나 사격 진지 근처에 배치합니다. 진지 지원은 주변 적 무리와 한 번 교전한 뒤 전진로로 복귀합니다."
	if base_only: hint="병종 카드를 누를 때마다 선택한 아군 기지에서 소집합니다. 사격 진지나 빈 땅에 직접 배치하지 않습니다."
	return {"deploymentKind":"marching","movementRoleKo":"전진형","placementRole":"marching","placementMode":"base_march" if base_only else "field_march","baseOnly":base_only,"autoRecruitOnCard":base_only,"roadBoundMarch":base_only,"allowsFieldDeployment":not base_only,"allowsSupportDeployment":not base_only,"combatRole":"cavalry" if type_name=="commander" else "ground","roleKo":"기지 출진 · 기마 전진" if type_name=="commander" else "기지 출진 · 근접 전진","placementHintKo":hint}

func _road_bound_march(unit: Dictionary) -> bool:
	if unit.has("roadBoundMarch"): return bool(unit.roadBoundMarch)
	return base_march_only(str(unit.get("type","")),battle.config)

func bind(value: Node2D) -> void:
	battle=value

func reset() -> void:
	gather_groups.clear()
	_ensure_spear_gather_generation()
	melee_seats.clear()
	melee_waiters.clear()
	melee_last_served.clear()
	melee_components.clear()
	melee_members.clear()
	melee_limits.clear()
	melee_seat_groups.clear()
	melee_waiter_groups.clear()
	melee_query_clock=-INF
	melee_query_generation=int(battle.battle_generation)
	melee_serial=0
	_clear_melee_phase()
	territorial_melee_enabled=_territorial_defense_mode()
	if support_generation!=int(battle.battle_generation):
		support_cohorts.clear()
		support_generation=int(battle.battle_generation)
	crowd.clear()
	crowd_generation=-1
	cumulative.clear()
	march_bases.clear()
	ambush_sites.clear()
	water_rects.clear()
	march_path_cursor=0
	var primary: Dictionary=battle.config.get("water",{})
	if not primary.is_empty(): water_rects.append(Rect2(float(primary.get("x",0)),float(primary.get("y",0)),float(primary.get("w",0)),float(primary.get("h",0))))
	for feature in battle.config.get("historicalBattlefield",{}).get("waterFeatures",[]):
		var kind: String=str(feature.get("kind",""))
		if kind=="wetland" or not bool(feature.get("blocksMovement",kind in ["river","stream","lake","wetland_lake"])): continue
		var rect: Rect2=Rect2(float(feature.get("x",0)),float(feature.get("y",0)),float(feature.get("w",0)),float(feature.get("h",0)))
		if rect.size.x>0 and rect.size.y>0 and not water_rects.has(rect): water_rects.append(rect)
	for path in battle.paths:
		var lengths: Array = [0.0]
		for index in range(path.points.size()-1): lengths.append(float(lengths[-1])+path.points[index].distance_to(path.points[index+1]))
		cumulative.append(lengths)
	for path_index in range(battle.paths.size()):
		var base: Dictionary=_base_for_path(path_index)
		if not base.is_empty(): march_bases.append(base)

func _territorial_defense_mode() -> bool:
	var scenario: Dictionary=battle.config.get("scenario",{})
	var mode: String=str(scenario.get("missionMode","")).to_lower()
	if mode.is_empty(): mode=str(battle.config.get("missionMode","")).to_lower()
	# Stage01's old map navigation label is ambush; its authored mission is
	# withdrawal. Missing scenario decoration must not silently disable caps.
	if mode.is_empty() and str(battle.config.get("id",""))=="basic-forest": mode="withdrawal"
	if mode.is_empty(): mode=str(battle.config.get("mode","")).to_lower()
	var stage02_advance: bool=str(battle.config.get("id",""))=="basic-farm" and not battle.config.get("advanceMission",{}).is_empty()
	if mode not in ["defense","withdrawal","retreat","rearguard","interception","escort","convoy"] and not stage02_advance: return false
	for path in battle.paths:
		var objective: Dictionary=battle._objective(str(path.get("objectiveId","main")))
		if not objective.is_empty() and str(objective.get("side","friendly"))!="enemy" and float(objective.get("hp",0))>0: return true
	return false

func _territory_progress(path_index: int, point: Vector2) -> float:
	if path_index<0 or path_index>=battle.paths.size(): return .5
	var base: Dictionary=select_march_base(path_index)
	if base.is_empty(): return .5
	var nearest: float=INF
	var projected: float=float(base.baseDistance)
	var points: Array=battle.paths[path_index].points
	for segment in range(points.size()-1):
		var start: Vector2=points[segment]
		var span: Vector2=points[segment+1]-start
		var fraction: float=clampf((point-start).dot(span)/maxf(.00000001,span.length_squared()),0.0,1.0)
		var distance: float=float(cumulative[path_index][segment])+span.length()*fraction
		var bounded: float=clampf(distance,float(base.routeMin),float(base.baseDistance))
		var on_route: Vector2=start+span*fraction if bounded==distance else route_point(path_index,bounded)
		var separation: float=on_route.distance_squared_to(point)
		if separation<nearest: nearest=separation;projected=bounded
	return clampf((float(base.baseDistance)-projected)/maxf(.00001,float(base.baseDistance)-float(base.routeMin)),0.0,1.0)

func _encounter_sector(ally: Dictionary, enemy: Dictionary) -> Dictionary:
	var pair_key: String="%d:%d" % [int(ally.id),int(enemy.id)]
	var path_index: int=int(enemy.get("pathIndex",ally.get("postPathIndex",-1)))
	var cached: Dictionary=melee_pair_locations.get(pair_key,{})
	if not cached.is_empty() and int(cached.pathIndex)==path_index and cached.allyPosition==ally.position and cached.enemyPosition==enemy.position: return cached
	var progress: float=_territory_progress(path_index,(ally.position+enemy.position)*.5)
	var territory: String="home" if progress<MELEE_HOME_END else "middle" if progress<MELEE_MIDDLE_END else "enemy"
	var location: Dictionary={"bucket":"%d:%s" % [path_index,territory],"territory":territory,"pathIndex":path_index,"progress":progress,"allyPosition":ally.position,"enemyPosition":enemy.position}
	melee_pair_locations[pair_key]=location
	return location

func _clear_melee_phase() -> void:
	invalidate_combat_queries()
	melee_pair_components.clear();melee_component_roots.clear();melee_pair_locations.clear();melee_wait_order.clear()
	crowd_clock=-INF;crowd_unit_count=-1;crowd_enemy_count=-1
	crowd_units=[];crowd_enemies=[]

func invalidate_combat_queries(terrain_changed: bool = false) -> void:
	# HQ calls this after signal subscribers return. Callback-time queries run
	# without a mutation scope and always use authoritative live geometry.
	navigation_query_revision+=1
	_clear_combat_query_results()
	# Mutating callbacks may replace same-length rosters or move actors in
	# place. Presentation-only signals do not call this invalidator.
	crowd_unit_count=-1;crowd_enemy_count=-1
	if terrain_changed: melee_query_clock=-INF
	if is_instance_valid(battle) and not battle.unit_skills.membership_query_context().is_empty() and crowd_generation==int(battle.battle_generation): _ensure_crowd_index()

func _clear_combat_query_results() -> void:
	combat_query_revision+=1
	_land_queries.clear();_road_queries.clear();_guard_segments.clear();_guard_nodes.clear();_guard_routes.clear();_strike_queries.clear();_ninja_routes.clear()
	_land_query_count=0;_road_query_count=0;_guard_segment_count=0;_guard_route_count=0
	_combat_query_scope={};_combat_query_clock=-INF

func _combat_queries_ready() -> bool:
	if not is_instance_valid(battle) or _live_check_depth>0: return false
	var scope: Dictionary=battle.unit_skills.membership_query_context()
	if scope.is_empty() or bool(scope.get("readOnly",false)): return false
	if not is_same(_combat_query_scope,scope) or _combat_query_clock!=float(battle.elapsed) or _combat_query_generation!=int(battle.battle_generation) or _combat_query_terrain!=structure_segment_clear:
		_clear_combat_query_results()
		_combat_query_scope=scope;_combat_query_clock=float(battle.elapsed)
		_combat_query_generation=int(battle.battle_generation);_combat_query_terrain=structure_segment_clear
	return true

func combat_query_epoch() -> int:
	return combat_query_revision if _combat_queries_ready() else -1

func _pending_melee_target(unit: Dictionary) -> Dictionary:
	if not territorial_melee_enabled or str(unit.get("type","")) not in ["spear","samurai","commander","naginata"] or not can_fight(unit) or str(unit.get("animation",""))=="attack": return {}
	var record: Dictionary=melee_waiters.get(int(unit.id),{})
	if record.is_empty() and float(unit.get("cooldown",0.0))<=0.0:
		var reserved: Dictionary=melee_seats.get(int(unit.id),{})
		if not reserved.is_empty() and not bool(reserved.get("prepared",true)) and float(reserved.until)>float(battle.elapsed): record=reserved
	if record.is_empty() or not _melee_record_alive(record) or not is_same(record.actor,unit): return {}
	var target: Dictionary=record.target
	if str(unit.type)=="samurai":
		var counter: Dictionary=battle.unit_skills.actions.counter_target(unit)
		if not counter.is_empty() and int(counter.id)!=int(target.id): return {}
	# A new target is chosen by the normal caller. Keep the old waiter's
	# ticket until claim_melee_attack migrates it or normal pruning expires it.
	return target if _melee_pair_valid(unit,target,true) else {}

func melee_attack_waiting(unit: Dictionary) -> bool:
	if not territorial_melee_enabled or str(unit.get("type","")) not in ["spear","samurai","commander","naginata"] or not can_fight(unit) or str(unit.get("animation",""))=="attack": return false
	var actor_id: int=int(unit.get("id",-1))
	if not melee_waiters.has(actor_id): return false
	_refresh_melee_encounters()
	var target: Dictionary=_pending_melee_target(unit)
	var waiter: Dictionary=melee_waiters.get(actor_id,{})
	if target.is_empty() or waiter.is_empty(): return false
	# Refresh only this continuing request. Its original fairness ticket and
	# last-served order survive; no cooldown or artificial waiting time changes.
	waiter["requestedAt"]=float(battle.elapsed)
	var component: String=_melee_group_for_pair(unit,target)
	var key: String=component+":1"
	if str(waiter.get("groupKey",""))!=key:
		_drop_melee_record(melee_waiters,melee_waiter_groups,actor_id)
		melee_waiters[actor_id]=waiter
		_index_melee_record(melee_waiter_groups,waiter)
	_fill_melee_seats(component,true)
	return not melee_seats.has(actor_id) and melee_waiters.has(actor_id)

func _ensure_crowd_index() -> void:
	var now: float=float(battle.elapsed)
	var generation: int=int(battle.battle_generation)
	if crowd_generation==generation and crowd_clock==now and crowd_unit_count==battle.units.size() and crowd_enemy_count==battle.enemies.size() and is_same(crowd_units,battle.units) and is_same(crowd_enemies,battle.enemies): return
	var preserve_load: bool=crowd_generation==generation and crowd_clock==now
	crowd.rebuild(battle.units,battle.enemies,preserve_load)
	crowd_generation=generation;crowd_clock=now
	crowd_units=battle.units;crowd_enemies=battle.enemies
	crowd_unit_count=battle.units.size();crowd_enemy_count=battle.enemies.size()
	# A spawn/removal changes topology even when simulation time is unchanged.
	melee_query_clock=-INF
	melee_pair_locations.clear()

func _encounter_link_allowed(ally: Dictionary, enemy: Dictionary) -> bool:
	if not can_fight(ally) or enemy.is_empty() or float(enemy.get("hp",0.0))<=0.0 or bool(enemy.get("escaped",false)) or battle._sailing_visual(enemy) or bool(enemy.get("transportActive",false)): return false
	# Enemy eligibility is sufficient for the same undirected contact edge.
	# Check it before friendly skill/path predicates and before terrain work.
	if battle.can_enemy_engage_unit(enemy,ally,true): return land_segment_safe(ally.position,enemy.position,0.0)
	if not is_ground(str(ally.type)) or str(ally.type)=="monk" or not battle.can_friendly_target_enemy(ally,enemy): return false
	return shares_contact_front(ally,enemy) and primary_target_allowed(ally,enemy,"release") and land_segment_safe(ally.position,enemy.position,0.0)

func _melee_pair_valid(actor: Dictionary, target: Dictionary, friendly: bool, fresh: bool = false) -> bool:
	if fresh: _live_check_depth+=1
	var valid: bool=_melee_pair_valid_contents(actor,target,friendly)
	if fresh: _live_check_depth=maxi(0,_live_check_depth-1)
	return valid

func _melee_pair_valid_contents(actor: Dictionary, target: Dictionary, friendly: bool) -> bool:
	if actor.is_empty() or target.is_empty() or float(actor.get("hp",0.0))<=0.0 or float(target.get("hp",0.0))<=0.0: return false
	if not friendly: return _counter_target_valid(actor,target)
	return is_ground(str(actor.type)) and str(actor.type)!="monk" and can_fight(actor) and primary_target_allowed(actor,target,"release") and shares_contact_front(actor,target) and actor.position.distance_to(target.position)<=reach(actor)*1.1 and land_segment_safe(actor.position,target.position,0.0)

func _melee_record_alive(record: Dictionary) -> bool:
	var friendly: bool=bool(record.friendly)
	var actor: Dictionary=(crowd.friends if friendly else crowd.hostiles).get(int(record.actorId),{})
	var target: Dictionary=(crowd.hostiles if friendly else crowd.friends).get(int(record.targetId),{})
	if actor.is_empty() or target.is_empty() or float(actor.get("hp",0.0))<=0.0 or float(target.get("hp",0.0))<=0.0 or bool(actor.get("consumed",false)) or bool(target.get("consumed",false)) or bool(actor.get("escaped",false)) or bool(target.get("escaped",false)): return false
	record["actor"]=actor;record["target"]=target
	return true

func _melee_record_valid(record: Dictionary) -> bool:
	return _melee_record_alive(record) and _melee_pair_valid(record.actor,record.target,bool(record.friendly))

func _refresh_melee_encounters() -> void:
	if not territorial_melee_enabled: return
	_ensure_crowd_index()
	if melee_query_generation!=int(battle.battle_generation):
		melee_seats.clear();melee_waiters.clear();melee_last_served.clear()
		melee_query_generation=int(battle.battle_generation)
		melee_query_clock=-INF
	if melee_query_clock==float(battle.elapsed): return
	melee_query_clock=float(battle.elapsed)
	melee_pair_locations.clear()
	for actor_id in melee_seats.keys():
		var seat: Dictionary=melee_seats[actor_id]
		if float(seat.until)<=melee_query_clock or not _melee_record_valid(seat): melee_seats.erase(actor_id)
	for actor_id in melee_waiters.keys():
		var waiter: Dictionary=melee_waiters[actor_id]
		if melee_query_clock-float(waiter.requestedAt)>.30 or not _melee_record_alive(waiter): melee_waiters.erase(actor_id)
	var committed_links: Array=[]
	for seat in melee_seats.values():
		committed_links.append([int(seat.actorId),int(seat.targetId)] if bool(seat.friendly) else [int(seat.targetId),int(seat.actorId)])
	var graph: Dictionary=crowd.local_encounters(MELEE_ENCOUNTER_RADIUS,_encounter_link_allowed,committed_links,_encounter_sector)
	melee_components=graph.owners
	melee_members=graph.members
	melee_pair_components=graph.pairs
	melee_component_roots.clear()
	melee_limits.clear()
	for component in graph.territories: melee_limits[component]=MELEE_TERRITORY_LIMITS[str(graph.territories[component])]
	melee_seat_groups.clear();melee_waiter_groups.clear();melee_wait_order.clear()
	for seat in melee_seats.values(): _index_melee_record(melee_seat_groups,seat,false)
	for waiter in melee_waiters.values(): _index_melee_record(melee_waiter_groups,waiter,false)
	for key in melee_wait_order: melee_wait_order[key].sort_custom(_waiter_before)
	# History is retained only for living actors, never for the whole campaign.
	for actor_id in melee_last_served.keys():
		if not crowd.friends.has(int(actor_id)) and not crowd.hostiles.has(int(actor_id)): melee_last_served.erase(actor_id)

func _resolve_melee_component(component: String) -> String:
	var root: String=component
	while melee_component_roots.has(root): root=str(melee_component_roots[root])
	if root!=component: melee_component_roots[component]=root
	return root

func _merge_melee_components(first: String, second: String) -> String:
	var a: String=_resolve_melee_component(first)
	var b: String=_resolve_melee_component(second)
	if a==b: return a
	var keep: String=a if a<b else b
	var removed: String=b if keep==a else a
	for node in melee_members.get(removed,[]):
		melee_components[node]=keep
		melee_members[keep].append(node)
	melee_members.erase(removed)
	melee_component_roots[removed]=keep
	for friendly in [false,true]:
		var old_key: String=removed+(":1" if friendly else ":0")
		var new_key: String=keep+(":1" if friendly else ":0")
		for groups in [melee_seat_groups,melee_waiter_groups]:
			if not groups.has(old_key): continue
			if not groups.has(new_key): groups[new_key]={}
			for record in groups[old_key].values():
				record["groupKey"]=new_key;record["component"]=keep
				groups[new_key][int(record.actorId)]=record
			groups.erase(old_key)
		if melee_wait_order.has(old_key):
			if not melee_wait_order.has(new_key): melee_wait_order[new_key]=[]
			melee_wait_order[new_key].append_array(melee_wait_order[old_key])
			melee_wait_order.erase(old_key)
			melee_wait_order[new_key].sort_custom(_waiter_before)
	melee_limits.erase(removed)
	return keep

func _join_melee_pair(ally: Dictionary, enemy: Dictionary, location: Dictionary) -> String:
	var bucket: String=str(location.bucket)
	var ally_node: String=bucket+"|a"+str(ally.id)
	var enemy_node: String=bucket+"|e"+str(enemy.id)
	var first: String=str(melee_components.get(ally_node,""))
	var second: String=str(melee_components.get(enemy_node,""))
	var component: String=_resolve_melee_component(first if not first.is_empty() else second)
	if component.is_empty():
		component=ally_node
		melee_members[component]=[]
		melee_limits[component]=MELEE_TERRITORY_LIMITS[str(location.territory)]
	if not first.is_empty() and not second.is_empty(): component=_merge_melee_components(first,second)
	for node in [ally_node,enemy_node]:
		if not melee_components.has(node): melee_members[component].append(node)
		melee_components[node]=component
	melee_pair_components[bucket+"|%d:%d" % [int(ally.id),int(enemy.id)]]=component
	return component

func _melee_group_for_pair(ally: Dictionary, enemy: Dictionary) -> String:
	var location: Dictionary=_encounter_sector(ally,enemy)
	var pair_key: String=str(location.bucket)+"|%d:%d" % [int(ally.id),int(enemy.id)]
	if melee_pair_components.has(pair_key): return _resolve_melee_component(str(melee_pair_components[pair_key]))
	var component: String=_join_melee_pair(ally,enemy,location)
	# Movement is indexed live. A newly touching pair joins only its current
	# neighborhood/sector; it never requests another whole-roster graph.
	for other in crowd.nearby(ally.position,MELEE_ENCOUNTER_RADIUS,false):
		if int(other.id)==int(enemy.id): continue
		var other_location: Dictionary=_encounter_sector(ally,other)
		if str(other_location.bucket)==str(location.bucket) and _encounter_link_allowed(ally,other): component=_join_melee_pair(ally,other,other_location)
	for other in crowd.nearby(enemy.position,MELEE_ENCOUNTER_RADIUS,true):
		if int(other.id)==int(ally.id): continue
		var other_location: Dictionary=_encounter_sector(other,enemy)
		if str(other_location.bucket)==str(location.bucket) and _encounter_link_allowed(other,enemy): component=_join_melee_pair(other,enemy,other_location)
	return _resolve_melee_component(component)

func _waiter_before(first: int, second: int) -> bool:
	var a: float=float(melee_last_served.get(first,-INF))
	var b: float=float(melee_last_served.get(second,-INF))
	if a!=b: return a<b
	return int(melee_waiters.get(first,{}).get("ticket",0))<int(melee_waiters.get(second,{}).get("ticket",0))

func _index_melee_record(groups: Dictionary, record: Dictionary, ordered: bool = true) -> void:
	var ally: Dictionary=record.actor if bool(record.friendly) else record.target
	var enemy: Dictionary=record.target if bool(record.friendly) else record.actor
	var component: String=_melee_group_for_pair(ally,enemy)
	var key: String=component+(":1" if bool(record.friendly) else ":0")
	record["groupKey"]=key;record["component"]=component
	if not groups.has(key): groups[key]={}
	groups[key][int(record.actorId)]=record
	if not is_same(groups,melee_waiter_groups): return
	if not melee_wait_order.has(key): melee_wait_order[key]=[]
	var order: Array=melee_wait_order[key]
	var actor_id: int=int(record.actorId)
	if not ordered: order.append(actor_id);return
	var low: int=0
	var high: int=order.size()
	while low<high:
		var middle: int=(low+high)>>1
		if _waiter_before(actor_id,int(order[middle])): high=middle
		else: low=middle+1
	order.insert(low,actor_id)

func _drop_melee_record(records: Dictionary, groups: Dictionary, actor_id: int) -> void:
	var record: Dictionary=records.get(actor_id,{})
	var key: String=str(record.get("groupKey",""))
	if groups.has(key):
		groups[key].erase(actor_id)
		if groups[key].is_empty(): groups.erase(key)
	if is_same(records,melee_waiters) and melee_wait_order.has(key):
		melee_wait_order[key].erase(actor_id)
		if melee_wait_order[key].is_empty(): melee_wait_order.erase(key)
	records.erase(actor_id)

func _melee_waiter_ready(waiter: Dictionary) -> bool:
	var friendly: bool=bool(waiter.friendly)
	var actor: Dictionary=waiter.actor
	if str(actor.get("animation",""))=="attack" and (friendly or float(actor.get("animationClock",0.0))<.5): return false
	if not friendly: return float(actor.get("attackCooldown",0.0))<=0.0 and actor.get("rangedPlan",{}).is_empty() and actor.get("counterPlan",{}).is_empty()
	return float(actor.get("cooldown",0.0))<=0.0 or not actor.get("guardDashData",{}).is_empty() or (str(actor.type)=="commander" and float(actor.get("chargeCooldown",0.0))<=0.0 and battle.unit_skills.can_charge(actor))

func _fill_melee_seats(component: String, friendly: bool) -> void:
	component=_resolve_melee_component(component)
	var limit: int=int(melee_limits[component][0 if friendly else 1])
	var key: String=component+(":1" if friendly else ":0")
	var occupied: Array=[]
	# At most six holders normally: cheap liveness/expiry checks, no repeated
	# terrain, support-range or target searches on every rejected request.
	for seat in melee_seat_groups.get(key,{}).values():
		if float(seat.until)<=float(battle.elapsed) or not _melee_record_alive(seat): _drop_melee_record(melee_seats,melee_seat_groups,int(seat.actorId))
		else: occupied.append(seat)
	if occupied.size()>limit:
		occupied.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.token)<int(b.token))
		while occupied.size()>limit:
			var removed: Dictionary=occupied.pop_back()
			_drop_melee_record(melee_seats,melee_seat_groups,int(removed.actorId))
	if occupied.size()>=limit: return
	var order: Array=melee_wait_order.get(key,[])
	while occupied.size()<limit and not order.is_empty():
		var actor_id: int=int(order[0])
		var waiter: Dictionary=melee_waiters.get(actor_id,{})
		if waiter.is_empty() or str(waiter.get("groupKey",""))!=key: order.pop_front();continue
		# Only candidates for an actual vacancy pay full live validation.
		if float(battle.elapsed)-float(waiter.requestedAt)>.30 or not _melee_record_valid(waiter) or not _melee_waiter_ready(waiter):
			_drop_melee_record(melee_waiters,melee_waiter_groups,actor_id)
			continue
		var current_group: String=_melee_group_for_pair(waiter.actor if friendly else waiter.target,waiter.target if friendly else waiter.actor)
		var current_root: String=_resolve_melee_component(component)
		if current_root!=component:
			_fill_melee_seats(current_root,friendly)
			return
		if current_group!=component:
			_drop_melee_record(melee_waiters,melee_waiter_groups,actor_id)
			melee_waiters[actor_id]=waiter
			_index_melee_record(melee_waiter_groups,waiter)
			continue
		melee_serial+=1
		var seat: Dictionary={"actorId":actor_id,"targetId":int(waiter.targetId),"actor":waiter.actor,"target":waiter.target,"friendly":friendly,"prepared":false,"token":melee_serial,"until":float(battle.elapsed)+float(waiter.duration)}
		melee_seats[actor_id]=seat
		_index_melee_record(melee_seat_groups,seat)
		_drop_melee_record(melee_waiters,melee_waiter_groups,actor_id)
		melee_last_served[actor_id]=float(battle.elapsed)
		occupied.append(seat)

func claim_melee_attack(actor: Dictionary, target: Dictionary, friendly: bool, duration: float) -> int:
	if not territorial_melee_enabled or (friendly and (not is_ground(str(actor.type)) or str(actor.type)=="monk")): return 0
	_refresh_melee_encounters()
	if not _melee_pair_valid(actor,target,friendly): return -1
	var actor_id: int=int(actor.id)
	var component: String=_melee_group_for_pair(actor if friendly else target,target if friendly else actor)
	var key: String=component+(":1" if friendly else ":0")
	var seat: Dictionary=melee_seats.get(actor_id,{})
	if friendly and str(actor.get("type",""))=="ninja" and bool(seat.get("ninjaCommitted",false)) and actor.get("attackPlan",{}).is_empty() and str(actor.get("animation",""))!="attack" and float(actor.get("cooldown",0.0))<=0.0:
		_drop_melee_record(melee_seats,melee_seat_groups,actor_id)
		seat={}
	if not seat.is_empty() and int(seat.targetId)==int(target.id) and float(seat.until)>float(battle.elapsed):
		if str(seat.get("groupKey",""))!=key:
			_drop_melee_record(melee_seats,melee_seat_groups,actor_id)
			melee_seats[actor_id]=seat
			_index_melee_record(melee_seat_groups,seat)
		_fill_melee_seats(component,friendly)
		if not melee_seats.has(actor_id): return -1
		seat["prepared"]=true
		return int(seat.token)
	if not seat.is_empty(): _drop_melee_record(melee_seats,melee_seat_groups,actor_id)
	var waiter: Dictionary=melee_waiters.get(actor_id,{})
	var unchanged: bool=not waiter.is_empty() and int(waiter.targetId)==int(target.id) and str(waiter.get("groupKey",""))==key
	if not waiter.is_empty() and not unchanged: _drop_melee_record(melee_waiters,melee_waiter_groups,actor_id)
	if waiter.is_empty():
		melee_serial+=1
		waiter={"actorId":actor_id,"friendly":friendly,"ticket":melee_serial}
	var minimum_duration: float=.1 if friendly and str(actor.get("type",""))=="ninja" else .5
	waiter.merge({"targetId":int(target.id),"actor":actor,"target":target,"requestedAt":float(battle.elapsed),"duration":maxf(minimum_duration,duration)},true)
	melee_waiters[actor_id]=waiter
	if not unchanged: _index_melee_record(melee_waiter_groups,waiter)
	_fill_melee_seats(component,friendly)
	var granted: Dictionary=melee_seats.get(actor_id,{})
	if granted.is_empty(): return -1
	granted["prepared"]=true
	return int(granted.token)

func commit_ninja_melee_attack(unit: Dictionary, plan: Dictionary, interval: float) -> void:
	var seat: Dictionary=melee_seats.get(int(unit.id),{})
	if seat.is_empty() or int(seat.token)!=int(plan.get("meleeSeatToken",-1)): return
	# Start the lease at actual preparation, with one simulation-step margin
	# for a scheduled final impact sampled at the cooldown boundary.
	seat["until"]=float(battle.elapsed)+maxf(.1,interval)+.05
	seat["ninjaCommitted"]=true

func melee_release_allowed(actor: Dictionary, target: Dictionary, plan: Dictionary, friendly: bool) -> bool:
	return _melee_plan_allowed(actor,target,plan,friendly,true)

func melee_preparation_allowed(actor: Dictionary, target: Dictionary, plan: Dictionary, friendly: bool = true) -> bool:
	return _melee_plan_allowed(actor,target,plan,friendly,false)

func _melee_plan_allowed(actor: Dictionary, target: Dictionary, plan: Dictionary, friendly: bool, fresh: bool) -> bool:
	if friendly and (not is_ground(str(actor.type)) or str(actor.type)=="monk"): return true
	if not territorial_melee_enabled: return true
	_refresh_melee_encounters()
	if not _melee_pair_valid(actor,target,friendly,fresh):
		release_melee_seat(actor)
		return false
	var actor_id: int=int(actor.id)
	var seat: Dictionary=melee_seats.get(actor_id,{})
	if seat.is_empty() or int(seat.token)!=int(plan.get("meleeSeatToken",-1)) or int(seat.targetId)!=int(target.id): return false
	var component: String=_melee_group_for_pair(actor if friendly else target,target if friendly else actor)
	var key: String=component+(":1" if friendly else ":0")
	if str(seat.get("groupKey",""))!=key:
		_drop_melee_record(melee_seats,melee_seat_groups,actor_id)
		melee_seats[actor_id]=seat
		_index_melee_record(melee_seat_groups,seat)
	_fill_melee_seats(component,friendly)
	return melee_seats.has(actor_id) and int(melee_seats[actor_id].token)==int(plan.get("meleeSeatToken",-1))

func release_melee_seat(actor: Dictionary) -> void:
	_drop_melee_record(melee_seats,melee_seat_groups,int(actor.get("id",-1)))
	_drop_melee_record(melee_waiters,melee_waiter_groups,int(actor.get("id",-1)))

func land_segment_safe(start: Vector2, end: Vector2, margin: float = .008) -> bool:
	if not start.is_finite() or not end.is_finite(): return false
	if not _combat_queries_ready(): return _land_segment_safe_live(start,end,margin)
	var margins: Dictionary=_land_queries.get(margin,{})
	var ends: Dictionary=margins.get(start,{})
	if ends.has(end): return bool(ends[end])
	var clear: bool=_land_segment_safe_live(start,end,margin)
	if _land_query_count>=COMBAT_SEGMENT_CACHE_LIMIT: _land_queries.clear();_land_query_count=0;margins={};ends={}
	ends[end]=clear;margins[start]=ends;_land_queries[margin]=margins
	_land_query_count+=1
	return clear

func _land_segment_safe_live(start: Vector2, end: Vector2, margin: float) -> bool:
	if not start.is_finite() or not end.is_finite(): return false
	for water in water_rects:
		if _water_intersection(start,end,water.grow(margin)).x>=0: return false
	var lower: Vector2=start.min(end)
	var upper: Vector2=start.max(end)
	for obstacle in battle.config.get("obstacles",[]):
		if not bool(obstacle.get("blockPlacement",false)): continue
		var center: Vector2=battle._point(obstacle)
		var radius: float=float(obstacle.get("r",0))+margin
		# Conservative broad phase; the original distance test still decides
		# contact, including tangencies. Read live geometry on every query.
		var bounds_radius: float=maxf(0.0,radius)+.000001
		if center.x<lower.x-bounds_radius or center.x>upper.x+bounds_radius or center.y<lower.y-bounds_radius or center.y>upper.y+bounds_radius: continue
		if center.distance_to(Geometry2D.get_closest_point_to_segment(center,start,end))<=radius: return false
	return not structure_segment_clear.is_valid() or bool(structure_segment_clear.call(start,end,margin))

func _road_segment_rect_distance(start: Vector2, end: Vector2, bounds: Rect2) -> float:
	if bounds.has_point(start) or bounds.has_point(end): return 0.0
	var corners: Array=[bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]
	var distance: float=INF
	for index in range(4):
		var a: Vector2=corners[index]
		var b: Vector2=corners[(index+1)%4]
		if Geometry2D.segment_intersects_segment(start,end,a,b)!=null: return 0.0
		distance=minf(distance,a.distance_to(Geometry2D.get_closest_point_to_segment(a,start,end)))
		distance=minf(distance,minf(start.distance_to(Geometry2D.get_closest_point_to_segment(start,a,b)),end.distance_to(Geometry2D.get_closest_point_to_segment(end,a,b))))
	return distance

func road_body_clear(body_bounds: Rect2) -> bool:
	# Stage01's dirt is authored in the raster, much wider than the old .022
	# placement-center test. Use its art aspect ratio and conservative70px
	# half-width, including every curved segment and overlapping road lane.
	var painted: bool=bool(battle.config.get("paintedPresentation",false))
	var art: Dictionary=battle.config.get("paintedComposition",{}).get("artSize",{"width":1831,"height":859})
	var metric: Vector2=Vector2(float(art.get("width",1831)),float(art.get("height",859))) if painted else Vector2.ONE
	var bounds: Rect2=Rect2(body_bounds.position*metric,body_bounds.size*metric)
	for path in battle.paths:
		var half_width: float=float(path.get("paintedRoadHalfWidthPixels",PAINTED_ROAD_HALF_WIDTH_ART_PIXELS)) if painted else float(path.get("roadHalfWidth",float(path.get("roadWidth",.044))*.5))
		for segment in range(path.points.size()-1):
			if _road_segment_rect_distance(path.points[segment]*metric,path.points[segment+1]*metric,bounds)<=half_width: return false
	return true

func land_route_safe(path_index: int, start_distance: float, end_distance: float, margin: float = .008) -> bool:
	if path_index<0 or path_index>=cumulative.size() or cumulative[path_index].is_empty(): return false
	var lower: float=minf(start_distance,end_distance)
	var upper: float=maxf(start_distance,end_distance)
	var previous: Vector2=route_point(path_index,lower)
	for distance in cumulative[path_index]:
		if float(distance)<=lower or float(distance)>=upper: continue
		var next: Vector2=route_point(path_index,float(distance))
		if not land_segment_safe(previous,next,margin): return false
		previous=next
	return land_segment_safe(previous,route_point(path_index,upper),margin)

func ambush_position_legal(point: Vector2, entry: Vector2) -> bool:
	if point.x<.04 or point.x>.96 or point.y<AMBUSH_MIN_FOOT_Y or point.y>.94 or battle._on_road(point): return false
	if not land_segment_safe(point,point,.026) or not land_segment_safe(point,entry): return false
	if structure_placement_clear.is_valid() and not bool(structure_placement_clear.call(point,.012)): return false
	for zone in battle.zones:
		if str(zone.get("placementRole",""))=="ambush": continue
		if point.distance_to(zone.position)<=float(zone.get("r",.08))+.026: return false
	return true

func build_ambush_sites() -> Array:
	ambush_sites.clear()
	var terrain: String=str(battle.config.get("theme",""))
	var cover_name: String={"forest":"숲 그늘","farm":"밭둑 엄폐","town":"골목 측면","river":"강둑 엄폐","harbor":"부두 육지","convoy":"길 측면","temple":"산비탈","snow":"고개 엄폐","siege":"성벽 외곽"}.get(terrain,"길 측면")
	for path_index in range(battle.paths.size()):
		var total: float=float(cumulative[path_index][-1])
		var distances: Array=[]
		for fraction in [.18,.42,.68,.85]: distances.append(total*float(fraction))
		# Dense scenery can cover a preferred point. Search the actual authored
		# segments instead of inventing a map-specific bypass through water.
		for segment in range(cumulative[path_index].size()-1):
			for fraction in [.3,.65]: distances.append(marker_distance(path_index,segment,float(fraction)))
		var count: int=0
		for distance_value in distances:
			if count>=4: break
			var distance: float=float(distance_value)
			if str(battle.config.get("theme",""))=="harbor":
				var landing: int=clampi(int(battle.config.get("landingIndex",2)),0,cumulative[path_index].size()-1)
				if distance<float(cumulative[path_index][landing])+.012: continue
			var entry: Vector2=route_point(path_index,distance)
			var direction: Vector2=route_point(path_index,minf(total,distance+.003))-route_point(path_index,maxf(0,distance-.003))
			if direction.length_squared()<.000001 or not land_segment_safe(entry,entry): continue
			var normal: Vector2=direction.normalized().orthogonal()
			var accepted: bool=false
			for offset in [.065,.085,.105,.125,.145,.165]:
				if accepted: break
				for side in [1.0,-1.0]:
					var point: Vector2=entry+normal*float(offset)*float(side)
					if not ambush_position_legal(point,entry): continue
					var crowded: bool=false
					for site in ambush_sites:
						if point.distance_to(site.position)<.09: crowded=true;break
					if crowded: continue
					var segment: int=0
					for index in range(cumulative[path_index].size()-1):
						if distance<=float(cumulative[path_index][index+1]): segment=index;break
					var site: Dictionary={"id":str(battle.config.get("id","map"))+"-ambush-"+str(path_index)+"-"+str(count),"nameKo":cover_name+" · %d번길" % (path_index+1),"position":point,"entryPosition":entry,"pathIndex":path_index,"segmentIndex":segment,"homeDistance":distance,"placementRole":"ambush","r":.024,"elevation":0,"mobilityFactor":1.0,"capacityBonus":0,"terrain":terrain}
					ambush_sites.append(site)
					count+=1
					accepted=true
					break
	return ambush_sites

func _base_for_path(path_index: int) -> Dictionary:
	var path: Dictionary=battle.paths[path_index]
	if path.points.size()<2 or float(cumulative[path_index][-1])<=.02: return {}
	var route_max: float=float(cumulative[path_index][-1])
	var base_distance: float=maxf(0.0,route_max-.018)
	var route_min: float=0.0
	if str(battle.config.get("theme",""))=="harbor":
		var landing: int=clampi(int(battle.config.get("landingIndex",2)),0,cumulative[path_index].size()-1)
		route_min=float(cumulative[path_index][landing])
		var land: Vector2=_land_bounds(path_index,base_distance)
		route_min=maxf(route_min,land.x)
		route_max=minf(route_max,land.y)
		base_distance=minf(base_distance,route_max)
	if base_distance<route_min+.004: return {}
	var point: Vector2=route_point(path_index,base_distance)
	if not land_segment_safe(point,point,.002): return {}
	var water_data: Dictionary=battle.config.get("water",{})
	if str(battle.config.get("theme",""))=="harbor" and not water_data.is_empty():
		var water: Rect2=Rect2(float(water_data.get("x",0)),float(water_data.get("y",0)),float(water_data.get("w",0)),float(water_data.get("h",0)))
		if water.has_point(point): return {}
	return {"baseId":"base:"+str(path.get("id",path_index)),"baseNameKo":"아군 기지 · %d번 출진로" % (path_index+1),"pathIndex":path_index,"pathId":str(path.get("id",path_index)),"objectiveId":str(path.get("objectiveId","main")),"position":point,"baseDistance":base_distance,"routeMin":route_min,"routeMax":route_max}

func select_march_base(requested_path: int = -1) -> Dictionary:
	if requested_path>=0:
		for base in march_bases:
			if int(base.pathIndex)==requested_path: return base
		return {}
	if requested_path!=-1 or march_bases.is_empty(): return {}
	var selected: Dictionary={}
	var best_count: int=2147483647
	var best_pressure: float=-INF
	for offset in range(march_bases.size()):
		var base: Dictionary=march_bases[(march_path_cursor+offset)%march_bases.size()]
		var count: int=0
		var pressure: float=0.0
		for unit in battle.units:
			if is_marching(str(unit.type)) and float(unit.get("hp",0))>0 and int(unit.get("postPathIndex",-1))==int(base.pathIndex): count+=1
		for job in battle.recruitment_queue:
			if str(job.kind)=="marching" and int(job.pathIndex)==int(base.pathIndex): count+=int(job.quantity)
		for enemy in battle.enemies:
			if int(enemy.pathIndex)!=int(base.pathIndex) or float(enemy.hp)<=0: continue
			# A side hunter belongs to the emplacement guard, not to a marching
			# column. Only enemies actually advancing on this front attract it.
			if str(enemy.get("combatRole","path_assault"))=="emplacement_assault" or bool(enemy.get("fortification",false)): continue
			var progress: float=clampf(enemy_distance(enemy)/maxf(.01,float(base.routeMax)),0,1)
			pressure+=clampf(float(enemy.hp)/maxf(1.0,float(enemy.maxHp)),.1,1.0)*(1.0+progress*3.0)
		var uncovered: float=pressure-float(count)*2.0
		if uncovered>best_pressure+.001 or (is_equal_approx(uncovered,best_pressure) and count<best_count):
			selected=base
			best_count=count
			best_pressure=uncovered
	return selected

func commit_march_base(base: Dictionary) -> void:
	for index in range(march_bases.size()):
		if int(march_bases[index].pathIndex)==int(base.pathIndex):
			march_path_cursor=(index+1)%march_bases.size()
			return

func marching_support_areas(type_name: String, requested_path: int = -1) -> Array:
	# Shared read-only geometry for the overlay and the destination validator.
	# These circles are candidate areas; terrain and route checks still veto.
	var areas: Array=[]
	if base_march_only(type_name,battle.config) or not is_marching(type_name) or requested_path < -1: return areas
	for post in battle.zones:
		if not battle.deployment_zone_active(post): continue
		var role: String=str(post.get("placementRole",""))
		if role!="ranged" and role!="ground": continue
		var path_index: int=int(post.get("pathIndex",-1))
		if path_index<0:
			var nearest_path: float=INF
			for index in range(battle.paths.size()):
				for segment in range(battle.paths[index].points.size()-1):
					var distance: float=point_distance(index,segment,post.position)
					var separation: float=route_point(index,distance).distance_squared_to(post.position)
					if separation<nearest_path: nearest_path=separation;path_index=index
		if requested_path>=0 and requested_path!=path_index: continue
		var base: Dictionary=select_march_base(path_index)
		if base.is_empty(): continue
		# A ground marker counts only when it hosts an actual fixed shooter.
		if role=="ground":
			var occupied: bool=false
			for ally in battle.units:
				if str(ally.get("type",""))=="gunner" and float(ally.get("hp",0))>0 and str(ally.get("postId",""))==str(post.get("id","")): occupied=true;break
			if not occupied: continue
		var radius: float=clampf(float(post.get("guardRadius",maxf(.15,float(post.get("r",.08))+.05))),.07,.25)
		var zone: Dictionary=post.get("defenseZone",{"center":post.position,"radius":radius}).duplicate(true)
		areas.append({"postId":str(post.get("id","")),"postName":str(post.get("nameKo","사격 진지")),"center":post.position,"radius":maxf(MARCH_SUPPORT_DROP_RADIUS,float(post.get("r",.08))+.025),"pathIndex":path_index,"base":base.duplicate(true),"supportRadius":radius,"supportZone":zone})
	return areas

func marching_support_destination(type_name: String, point: Vector2, requested_path: int = -1) -> Dictionary:
	# A safe link back to the real advance route is required before payment;
	# neither a wall nor water may be crossed later.
	if base_march_only(type_name,battle.config) or not is_marching(type_name) or not point.is_finite() or requested_path < -1: return {}
	if point.x<0 or point.x>1 or point.y<0 or point.y>1 or not land_segment_safe(point,point,.008): return {}
	if structure_placement_clear.is_valid() and not bool(structure_placement_clear.call(point,.008)): return {}
	var best: Dictionary={}
	var closest: float=INF
	for area in marching_support_areas(type_name,requested_path):
		var distance_to_post: float=point.distance_to(area.center)
		if distance_to_post>float(area.radius) or distance_to_post>=closest: continue
		var path_index: int=int(area.pathIndex)
		var base: Dictionary=area.base
		var radius: float=float(area.supportRadius)
		var zone: Dictionary=area.supportZone
		var probe: Dictionary={"homePosition":point,"guardZone":zone,"guardRadius":radius,"guardTrail":[point],"occupancyRadius":.008}
		if not guard_point_inside(probe,point): continue
		var connection: Dictionary={}
		var nearest_connection: float=INF
		for segment in range(battle.paths[path_index].points.size()-1):
			var projected: float=clampf(point_distance(path_index,segment,point),float(base.routeMin),float(base.routeMax))
			for route_distance in [projected,clampf(float(cumulative[path_index][segment]),float(base.routeMin),float(base.routeMax)),clampf(float(cumulative[path_index][segment+1]),float(base.routeMin),float(base.routeMax))]:
				var join: Vector2=route_point(path_index,float(route_distance))
				var separation: float=point.distance_to(join)
				if separation>=nearest_connection or separation>radius*2.0 or not land_segment_safe(point,join,.008): continue
				connection={"supportReturnPosition":join,"supportReturnDistance":float(route_distance)}
				nearest_connection=separation
		if connection.is_empty(): continue
		best=base.duplicate(true)
		best.merge(connection,true)
		best.merge({"supportDeployment":true,"supportPosition":point,"supportAreaCenter":area.center,"supportPostId":str(area.postId),"supportPostName":str(area.postName),"supportZone":zone,"supportRadius":radius,"supportDropRadius":float(area.radius)},true)
		closest=distance_to_post
	return best

func marching_click_destination(point: Vector2, requested_path: int = -1, type_name: String = "") -> Dictionary:
	if not is_marching(type_name) or base_march_only(type_name,battle.config): return {}
	if not point.is_finite() or point.x<0 or point.x>1 or point.y<0 or point.y>1 or not land_segment_safe(point,point,.008): return {}
	if structure_placement_clear.is_valid() and not bool(structure_placement_clear.call(point,.008)): return {}
	var best: Dictionary={}
	var nearest: float=INF
	for base in march_bases:
		var path_index: int=int(base.pathIndex)
		if requested_path>=0 and requested_path!=path_index: continue
		for segment in range(battle.paths[path_index].points.size()-1):
			var distance: float=clampf(point_distance(path_index,segment,point),float(base.routeMin),float(base.routeMax))
			var join: Vector2=route_point(path_index,distance)
			var separation: float=point.distance_squared_to(join)
			if separation>=nearest or not land_segment_safe(point,join,.008): continue
			best=base.duplicate(true)
			best.merge({"clickPosition":point,"dispatchOrigin":point,"dispatchJoinPosition":join,"dispatchJoinDistance":distance,"dispatchJoinSegment":segment},true)
			nearest=separation
	return best

func initialize_marching_support(unit: Dictionary, destination: Dictionary) -> void:
	# Invalid direct callers cannot turn a base-only marcher into a field drop.
	# Production keeps the normal marching initialization for this role.
	if base_march_only(str(unit.get("type","")),battle.config): return
	unit["position"]=destination.supportPosition
	unit["spawnPosition"]=unit.position
	unit["homePosition"]=unit.position
	unit["postName"]=str(destination.get("supportPostName","사격 진지"))+" · 일회 지원"
	unit["supportPostId"]=str(destination.get("supportPostId",""))
	unit["guardRadius"]=float(destination.get("supportRadius",.15))
	unit["guardZone"]=destination.supportZone.duplicate(true)
	unit["guardTrail"]=[unit.position]
	unit["occupancyRadius"]=.008
	unit["routeDistance"]=float(destination.supportReturnDistance)
	var join: Vector2=_march_position(unit,float(unit.routeDistance))
	if not land_segment_safe(unit.position,join,float(unit.occupancyRadius)):
		unit["formationLane"]=0
		join=destination.supportReturnPosition
	unit["supportReturnPosition"]=join
	unit["supportReturnDistance"]=float(destination.supportReturnDistance)
	unit["supportPhase"]="waiting"
	unit["supportWaitClock"]=0.0
	unit["supportExcludedIds"]=[]
	unit["supportCohortKey"]="%d:%d:%s" % [battle.battle_generation,int(unit.get("productionJobId",unit.id)),str(unit.supportPostId)]
	unit["supportEnemyIds"]=[]
	unit["supportReturnViaHome"]=true
	unit["targetId"]=-1
	unit["gatherRemaining"]=0.0
	unit["gatherGroupId"]=0
	unit["combatState"]="support_advance"
	_set_animation(unit,"idle")
	# Production reserves the order; actual first contact locks its finite group.

func _march_position(unit: Dictionary, distance: float) -> Vector2:
	var path_index: int=int(unit.postPathIndex)
	var center: Vector2=route_point(path_index,distance)
	var next_point: Vector2=route_point(path_index,maxf(float(unit.routeMin),distance-.012))
	var forward: Vector2=next_point-center
	if forward.length_squared()<.0000001: forward=center-route_point(path_index,minf(float(unit.routeMax),distance+.012))
	# Preserve the reserved birth offset during the first real strides and
	# join the nearest formation side without crossing the central lane.
	var spread: float=clampf((float(unit.get("marchSpawnDistance",unit.get("homeDistance",distance)))-distance)/.030,0,1)
	var offset: float=lerpf(float(unit.get("marchSpawnOffset",0.0)),float(unit.get("formationLane",0))*.009,spread)
	var position: Vector2=center+forward.normalized().orthogonal()*offset
	if not land_segment_safe(position,position,.002): return center
	return position

func initialize_marching_unit(unit: Dictionary, base: Dictionary, reserved_position: Vector2 = Vector2(INF,INF)) -> void:
	unit.merge(placement_contract(str(unit.type),battle.config),true)
	unit["hp"]=max_health(unit)
	unit["maxHp"]=float(unit.hp)
	unit["blockCount"]=0
	var gathering: bool=str(unit.type)=="spear"
	unit["combatState"]="gather" if gathering else "march"
	unit["gatherRemaining"]=SPEAR_GATHER_SECONDS if gathering else 0.0
	unit["gatherGroupId"]=0
	unit["gatherWindowId"]=0
	unit["gatherDeadlineTick"]=0
	unit["gatherPendingBirth"]=gathering
	unit["gatherGeneration"]=int(battle.battle_generation)
	unit["recoverRemaining"]=0.0
	unit["chargeCooldown"]=0.0
	unit["deploying"]=false
	unit["postPathIndex"]=int(base.pathIndex)
	unit["postName"]=str(base.baseNameKo)
	unit["postId"]=str(base.baseId)
	unit["baseId"]=str(base.baseId)
	unit["pathId"]=str(base.pathId)
	unit["basePosition"]=base.position
	unit["homePosition"]=base.position
	unit["homeDistance"]=float(base.baseDistance)
	unit["routeDistance"]=float(base.baseDistance)
	unit["routeMin"]=float(base.routeMin)
	unit["routeMax"]=float(base.routeMax)
	battle.advance_mission.apply_marching_goal(unit)
	unit["mobilityFactor"]=1.0
	unit["capacityBonus"]=0
	unit["targetId"]=-1
	unit["formationLane"]=(int(unit.id)%5)-2
	# Production already validated each member's reserved birth position. Avoid
	# computing a temporary formation position only to overwrite it immediately.
	unit["position"]=reserved_position if reserved_position.is_finite() else _march_position(unit,float(unit.routeDistance))
	unit["spawnPosition"]=unit.position
	var direction: Vector2=route_point(int(unit.postPathIndex),maxf(float(unit.routeMin),float(unit.routeDistance)-.025))-base.position
	unit["aim"]=direction.normalized() if direction.length_squared()>.000001 else Vector2.LEFT
	unit["animation"]="idle" if gathering else "walk"

func _ensure_spear_gather_generation() -> void:
	# Spatial refreshes in this battle must not restart an open birth window.
	if spear_gather_generation==int(battle.battle_generation): return
	spear_gather_windows.clear()
	spear_gather_generation=int(battle.battle_generation)

func _spear_gather_clock() -> int:
	# One shared combat clock, quantized once for an exact equal-time boundary.
	return roundi(float(battle.elapsed)*1000000.0)

func register_spear_birth(unit: Dictionary) -> void:
	# Called only after the real actor is appended. A preview, paid order or
	# cancelled future recruit cannot start or extend the assembly window.
	if str(unit.get("type",""))!="spear" or str(unit.get("combatState",""))!="gather" or not bool(unit.get("gatherPendingBirth",false)): return
	if float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)): return
	var appended: bool=not battle.units.is_empty() and is_same(battle.units.back(),unit)
	if not appended and not is_same(_unit(int(unit.get("id",-1))),unit): return
	_ensure_spear_gather_generation()
	var key: String=_spear_gather_key(unit)
	var tick: int=_spear_gather_clock()
	var window: Dictionary=spear_gather_windows.get(key,{})
	# The interval is [first actual birth, deadline). A birth exactly at the
	# deadline opens the next window even before the old column is processed.
	if window.is_empty() or bool(window.get("closed",false)) or tick>=int(window.deadlineTick):
		window={"id":int(unit.id),"startedTick":tick,"deadlineTick":tick+SPEAR_GATHER_TICKS,"closed":false}
		spear_gather_windows[key]=window
	unit["gatherGroupId"]=int(window.id)
	unit["gatherWindowId"]=int(window.id)
	unit["gatherBaseKey"]=key
	unit["gatherStartedAt"]=float(window.startedTick)/1000000.0
	unit["gatherDeadlineTick"]=int(window.deadlineTick)
	unit["gatherDeadline"]=float(window.deadlineTick)/1000000.0
	unit["gatherRemaining"]=float(maxi(0,int(window.deadlineTick)-tick))/1000000.0
	unit["gatherGeneration"]=int(battle.battle_generation)
	unit["gatherPendingBirth"]=false

func initialize_march_departure(unit: Dictionary) -> void:
	# Keep the reserved birth position and its side of the road. Only the
	# route cursor changes here; the first actual stride moves the actor.
	var path_index: int=int(unit.postPathIndex)
	var distance: float=float(unit.routeMin)
	var nearest: float=INF
	for segment in range(battle.paths[path_index].points.size()-1):
		var projected: float=clampf(point_distance(path_index,segment,unit.position),float(unit.routeMin),float(unit.routeMax))
		var separation: float=route_point(path_index,projected).distance_squared_to(unit.position)
		if separation<nearest: nearest=separation;distance=projected
	var center: Vector2=route_point(path_index,distance)
	var forward: Vector2=route_point(path_index,maxf(float(unit.routeMin),distance-.012))-center
	if forward.length_squared()<.0000001: forward=center-route_point(path_index,minf(float(unit.routeMax),distance+.012))
	var offset: float=(unit.position-center).dot(forward.normalized().orthogonal())
	unit["routeDistance"]=distance
	unit["marchSpawnDistance"]=distance
	unit["marchSpawnOffset"]=offset
	unit["formationLane"]=clampi(roundi(offset/.009),-2,2)

func marker_distance(path_index: int, segment_index: int, fraction: float) -> float:
	if path_index<0 or path_index>=cumulative.size(): return 0.0
	var lengths: Array=cumulative[path_index]
	var segment: int=clampi(segment_index,0,maxi(0,lengths.size()-2))
	return lerpf(float(lengths[segment]),float(lengths[segment+1]),clampf(fraction,0,1))

func route_point(path_index: int, distance: float) -> Vector2:
	var path: Dictionary=battle.paths[path_index]
	var lengths: Array=cumulative[path_index]
	var position: float=clampf(distance,0,float(lengths[-1]))
	for index in range(lengths.size()-1):
		if position<=float(lengths[index+1]): return (path.points[index] as Vector2).lerp(path.points[index+1],(position-float(lengths[index]))/maxf(.000001,float(lengths[index+1])-float(lengths[index])))
	return path.points[-1]

func point_distance(path_index: int, segment_index: int, point: Vector2) -> float:
	var path: Dictionary=battle.paths[path_index]
	var segment: int=clampi(segment_index,0,maxi(0,path.points.size()-2))
	var start: Vector2=path.points[segment]
	var end: Vector2=path.points[segment+1]
	var nearest: Vector2=Geometry2D.get_closest_point_to_segment(point,start,end)
	return float(cumulative[path_index][segment])+start.distance_to(nearest)

func enemy_distance(enemy: Dictionary) -> float:
	return point_distance(int(enemy.pathIndex),int(enemy.pointIndex)-1,enemy.position)

func shares_contact_front(unit: Dictionary, enemy: Dictionary) -> bool:
	var own: int=int(unit.get("postPathIndex",-1))
	var other: int=int(enemy.get("pathIndex",-1))
	if own<0 or other<0 or own>=battle.paths.size() or other>=battle.paths.size(): return false
	if own==other: return true
	if not is_marching(str(unit.get("type",""))): return false
	if unit.position.distance_to(enemy.position)>reach(unit)*1.1 or not land_segment_safe(unit.position,enemy.position): return false
	var own_path: Dictionary=battle.paths[own]
	var other_path: Dictionary=battle.paths[other]
	if str(own_path.get("objectiveId","" )).is_empty() or str(own_path.get("objectiveId",""))!=str(other_path.get("objectiveId","")): return false
	# A shared segment must have a real collinear overlap. A crossing, nearby
	# parallel lane or merely shared objective does not grant cross-route combat.
	for i in range(own_path.points.size()-1):
		var start: Vector2=own_path.points[i]
		var direction: Vector2=own_path.points[i+1]-start
		var length: float=direction.length()
		if length<.00001: continue
		var axis: Vector2=direction/length
		for j in range(other_path.points.size()-1):
			var a: Vector2=other_path.points[j]
			var b: Vector2=other_path.points[j+1]
			if absf(axis.cross(a-start))>.00001 or absf(axis.cross(b-start))>.00001: continue
			var lower: float=maxf(0.0,minf((a-start).dot(axis),(b-start).dot(axis)))
			var upper: float=minf(length,maxf((a-start).dot(axis),(b-start).dot(axis)))
			if upper-lower<.012: continue
			var unit_distance: float=(unit.position-start).dot(axis)
			var enemy_distance_value: float=(enemy.position-start).dot(axis)
			if unit_distance<lower or unit_distance>upper or enemy_distance_value<lower or enemy_distance_value>upper: continue
			# The .009 marching formation offset stays on the same shared road.
			if absf(axis.cross(unit.position-start))<=.012 and absf(axis.cross(enemy.position-start))<=.012: return true
	return false

func enemy_distance_for_unit(unit: Dictionary, enemy: Dictionary) -> float:
	if int(unit.postPathIndex)==int(enemy.pathIndex): return enemy_distance(enemy)
	var path_index: int=int(unit.postPathIndex)
	var nearest: float=INF
	var distance: float=0.0
	for segment in range(battle.paths[path_index].points.size()-1):
		var projected: float=point_distance(path_index,segment,enemy.position)
		var offset: float=route_point(path_index,projected).distance_squared_to(enemy.position)
		if offset<nearest: nearest=offset;distance=projected
	return distance

func max_health(unit: Dictionary) -> float:
	return UnitGrowth.max_health(unit,battle._unit_definition(unit))

func capacity(unit: Dictionary) -> int:
	if str(unit.type)=="gunner": return 1
	return clampi(int(CAPACITY.get(str(unit.type),0))+int(unit.get("capacityBonus",0)),1,4) if is_ground(str(unit.type)) else 0

func reach(unit: Dictionary) -> float:
	var value: float=float(REACH.get(str(unit.type),0.0))
	if str(unit.type)=="spear": return battle.unit_skills.actions.effective_spear_reach(unit,value)
	return value*float(battle.unit_skills.stat_modifiers(unit).get("rangeFactor",1.0)) if str(unit.type)=="naginata" else value

func _water_intersection(start: Vector2, end: Vector2, water: Rect2) -> Vector2:
	var first: float=0.0
	var last: float=1.0
	var delta: Vector2=end-start
	for axis in range(2):
		var origin: float=start[axis]
		var direction: float=delta[axis]
		var lower: float=water.position[axis]
		var upper: float=water.end[axis]
		if absf(direction)<.000001:
			if origin<lower or origin>upper: return Vector2(-1,-1)
		else:
			var a: float=(lower-origin)/direction
			var b: float=(upper-origin)/direction
			first=maxf(first,minf(a,b))
			last=minf(last,maxf(a,b))
			if first>last: return Vector2(-1,-1)
	return Vector2(first,last)

func _land_bounds(path_index: int, home_distance: float) -> Vector2:
	var limits: Vector2=Vector2(0,float(cumulative[path_index][-1]))
	var points: Array=battle.paths[path_index].points
	for water in water_rects:
		for segment in range(points.size()-1):
			var interval: Vector2=_water_intersection(points[segment],points[segment+1],water)
			if interval.x<0: continue
			var begin: float=lerpf(float(cumulative[path_index][segment]),float(cumulative[path_index][segment+1]),interval.x)
			var end: float=lerpf(float(cumulative[path_index][segment]),float(cumulative[path_index][segment+1]),interval.y)
			if end<home_distance: limits.x=maxf(limits.x,minf(home_distance,end+.004))
			elif begin>home_distance: limits.y=minf(limits.y,maxf(home_distance,begin-.004))
	return limits

func initialize_unit(unit: Dictionary, post: Dictionary) -> void:
	unit.merge(placement_contract(str(unit.type),battle.config),true)
	unit["hp"]=max_health(unit)
	unit["maxHp"]=float(unit.hp)
	unit["blockCount"]=0
	unit["combatState"]="guard"
	unit["recoverRemaining"]=0.0
	unit["chargeCooldown"]=0.0
	unit["deploying"]=false
	unit["homePosition"]=unit.position
	unit["postName"]=str(post.get("nameKo","사격 진지"))
	unit["postId"]=str(post.get("id",""))
	# Fixed archers also belong to an authored firing lane. This identity is
	# needed by road ranged opponents; it does not give the archer movement.
	var post_path: int=int(post.get("pathIndex",-1))
	if post_path>=0 and post_path<battle.paths.size(): unit["postPathIndex"]=post_path
	if not is_frontline(str(unit.type)): return
	unit["postName"]=str(post.get("nameKo","길목 방어 지점"))
	unit["postId"]=str(post.get("id",""))
	unit["homeDistance"]=point_distance(int(post.pathIndex),int(post.segmentIndex),unit.position)
	unit["routeDistance"]=float(unit.homeDistance)
	unit["homePosition"]=unit.position
	unit["guardRadius"]=clampf(float(post.get("guardRadius",.15)),.07,.25)
	unit["mobilityFactor"]=clampf(float(post.get("mobilityFactor",1.0)),.4,1.5)
	unit["capacityBonus"]=clampi(int(post.get("capacityBonus",0)),0,2)
	unit["routeMin"]=0.0
	unit["routeMax"]=float(cumulative[int(unit.postPathIndex)][-1])
	if str(battle.config.get("theme",""))=="harbor":
		var landing: int=clampi(int(battle.config.get("landingIndex",2)),0,cumulative[int(unit.postPathIndex)].size()-1)
		unit["routeMin"]=float(cumulative[int(unit.postPathIndex)][landing])
		var land: Vector2=_land_bounds(int(unit.postPathIndex),float(unit.homeDistance))
		unit["routeMin"]=maxf(float(unit.routeMin),land.x)
		unit["routeMax"]=minf(float(unit.routeMax),land.y)
	if str(battle.config.get("theme",""))=="convoy":
		unit["routeMax"]=float(cumulative[int(unit.postPathIndex)][maxi(0,cumulative[int(unit.postPathIndex)].size()-2)])
	unit["routeMax"]=maxf(float(unit.homeDistance),float(unit.routeMax)-.03)
	unit["targetId"]=-1
	if str(unit.type)=="naginata":
		# The movement boundary is authored independently of recognition/range.
		unit["guardZone"]=post.get("defenseZone",{"center":unit.homePosition,"radius":float(unit.guardRadius)}).duplicate(true)
		unit["occupancyRadius"]=maxf(.001,float(post.get("occupancyRadius",.008)))
		unit["guardTrail"]=[unit.homePosition]
		unit["guardDashData"]={}
	if is_ambush(str(unit.type)):
		unit["homeDistance"]=float(post.homeDistance)
		unit["routeDistance"]=float(post.homeDistance)
		unit["entryPosition"]=post.entryPosition
		unit["spawnPosition"]=unit.position
		unit["guardRadius"]=float(battle._read_stats(unit).range)
		var land: Vector2=_land_bounds(int(unit.postPathIndex),float(unit.homeDistance))
		unit["routeMin"]=maxf(float(unit.routeMin),land.x)
		unit["routeMax"]=minf(float(unit.routeMax),land.y)
		unit["combatState"]="ambush_seek"
		unit["onAmbushRoute"]=false
		unit["ambushStrikeDone"]=false
		unit["priorityTargetId"]=-1
		unit["occupancyRadius"]=maxf(.001,float(post.get("occupancyRadius",.008)))
		unit["consumed"]=false

func refresh_health(unit: Dictionary) -> void:
	var ratio: float=float(unit.get("hp",max_health(unit)))/maxf(1.0,float(unit.get("maxHp",max_health(unit))))
	unit["maxHp"]=max_health(unit)
	unit["hp"]=float(unit.maxHp)*ratio

func can_fight(unit: Dictionary) -> bool:
	return float(unit.get("hp",0))>0 and str(unit.get("combatState","guard")) in ["guard","gather","march","front","advance","engaged","charge","impact","ambush_wait","ambush_approach","guard_advance","guard_engaged","guard_dash","support_advance","support_engaged","support_return"]

func active_support(unit: Dictionary) -> bool:
	return float(unit.get("hp",0))>0 and (not is_frontline(str(unit.type)) or can_fight(unit))

func _unit(id: int) -> Dictionary:
	if id<0: return {}
	if crowd_generation==int(battle.battle_generation) and crowd.friend_slots.has(id):
		var slot: int=int(crowd.friend_slots[id])
		if slot>=0 and slot<battle.units.size():
			var actor: Dictionary=battle.units[slot]
			if int(actor.get("id",-1))==id and not bool(actor.get("consumed",false)): return actor
	for unit in battle.units:
		if int(unit.id)==id: return unit
	return {}

func _nearest_enemy(unit: Dictionary) -> Dictionary:
	var counter: Dictionary=battle.unit_skills.actions.counter_target(unit)
	if not counter.is_empty(): return counter
	var pending: Dictionary=_pending_melee_target(unit)
	if not pending.is_empty(): return pending
	var best: Dictionary={}
	var score: float=INF
	var search_range: float=battle.movement_search_range(unit)
	var marching: bool=is_marching(str(unit.type))
	for enemy in crowd.nearby(unit.position,search_range,false):
		var candidate: float=unit.position.distance_to(enemy.position)
		var candidate_score: float=candidate+(0.0 if marching else crowd.target_penalty(int(enemy.id)))
		# Half a body gap absorbs tiny nearest-enemy fluctuations without
		# reserving the enemy or delaying any original validity check.
		if marching and int(enemy.id)==int(unit.get("targetId",-1)): candidate_score-=CrowdMelee.BODY_GAP*.5
		if candidate_score>=score: continue
		# Rejected scores cannot win. Avoid repeated route/road/skill geometry
		# for farther neighbors while preserving iteration order and exact ties.
		if not shares_contact_front(unit,enemy) or not battle._enemy_visible(enemy) or battle._sailing_visual(enemy): continue
		if not primary_target_allowed(unit,enemy,"prepare"): continue
		var route_distance: float=enemy_distance_for_unit(unit,enemy)
		if route_distance<float(unit.get("routeMin",0)) or route_distance>float(unit.routeMax): continue
		if marching:
			if route_distance>float(unit.routeDistance)+reach(unit)*1.6: continue
		elif absf(route_distance-float(unit.homeDistance))>float(unit.guardRadius): continue
		if not land_segment_safe(unit.position,enemy.position,.002): continue
		# Marchers may converge on an enemy already occupied by allies. A
		# selected enemy owns no seat; actual body spacing decides the approach.
		if candidate_score<score: score=candidate_score;best=enemy
	if not best.is_empty() and not marching: crowd.claim_target(int(best.id))
	return best

func _set_animation(unit: Dictionary, state: String) -> void:
	if str(unit.get("animation","idle"))!=state:
		unit["animation"]=state
		unit["animationClock"]=0.0

func _walk(unit: Dictionary, target_distance: float, delta: float, factor: float=1.0) -> bool:
	if not is_marching(str(unit.type)): return false
	var desired: float=clampf(minf(target_distance,float(unit.routeDistance)),float(unit.routeMin),float(unit.routeMax))
	var speed_value: float=(.065 if str(unit.type)=="commander" else .042)*float(unit.mobilityFactor)*factor
	var previous: Vector2=unit.position
	var distance: float=move_toward(float(unit.routeDistance),desired,speed_value*delta)
	var joining: bool=bool(unit.get("dispatchJoinPending",false))
	# Steer toward the road ahead, rather than repeatedly pulling sideways
	# toward one projected sub-step while neighbors apply spacing pressure.
	var lookahead: float=move_toward(float(unit.routeDistance),desired,maxf(speed_value*delta,CrowdMelee.BODY_GAP*2.0))
	var destination: Vector2=unit.dispatchJoinPosition if joining else _march_position(unit,lookahead)
	var next: Vector2=previous.move_toward(destination,speed_value*delta)
	var legal: Callable=func(a: Vector2,b: Vector2) -> bool: return land_segment_safe(a,b,.008) and (not _road_bound_march(unit) or _road_point_inside(b,int(unit.postPathIndex)))
	unit.position=crowd.move_point(unit,next,true,legal,destination)
	crowd.moved(unit,previous,true)
	if bool(unit.get("advanceMissionGoal",false)):
		unit.routeDistance=battle.advance_mission.marching_distance(unit)
	else:
		unit.routeDistance=clampf(point_distance(int(unit.postPathIndex),0,unit.position),float(unit.routeMin),float(unit.routeMax)) if battle.paths[int(unit.postPathIndex)].points.size()==2 else distance
	var direction: Vector2=unit.position-previous
	if direction.length_squared()>.000000001:
		unit.aim=direction.normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")
	if joining:
		if unit.position.distance_to(destination)<.0001:
			unit["dispatchJoinPending"]=false
			initialize_march_departure(unit)
		return false
	return absf(float(unit.routeDistance)-desired)<.0001

func _clear_melee_goal(unit: Dictionary) -> void:
	for key in ["meleeGoalTargetId","meleeGoalGeneration","meleeGoalBasis","meleeGoalOffset","meleeGoalPosition","meleeGoalSlot","meleeGoalRadius","meleeGoalEffort","meleeGoalProgress","meleeGoalReplan","meleeGoalRouteRemaining"]:
		unit.erase(key)

func _track_melee_progress(unit: Dictionary, previous: Vector2, goal: Vector2, effort: float) -> void:
	_record_melee_progress(unit,previous.distance_to(goal)-unit.position.distance_to(goal),effort)

func _record_melee_progress(unit: Dictionary, progress: float, effort: float) -> void:
	if int(unit.get("meleeGoalTargetId",-1))!=int(unit.get("targetId",-1)): return
	unit["meleeGoalEffort"]=float(unit.get("meleeGoalEffort",0.0))+effort
	unit["meleeGoalProgress"]=float(unit.get("meleeGoalProgress",0.0))+progress
	# Measure real net progress, not positive half-steps of an oscillation.
	# The budget is two existing body gaps, independent of frame rate/speed.
	if float(unit.meleeGoalProgress)>=CrowdMelee.BODY_GAP*.25:
		unit.meleeGoalEffort=0.0
		unit.meleeGoalProgress=0.0
	elif float(unit.meleeGoalEffort)>=CrowdMelee.BODY_GAP*2.0:
		unit["meleeGoalReplan"]=true

func _melee_point(unit: Dictionary, target: Dictionary, bounded: bool = false) -> Vector2:
	if target.is_empty() or float(target.get("hp",0.0))<=0:
		_clear_melee_goal(unit)
		return Vector2(INF,INF)
	if str(unit.type)=="spear":
		var rear_goal: Vector2=battle.unit_skills.actions.rear_rank_goal(unit,target)
		if rear_goal.is_finite() and _road_point_inside(rear_goal,int(unit.postPathIndex)) and battle.advance_mission.friendly_goal_allowed(unit,rear_goal): return rear_goal
	var radius: float=reach(unit)*.82
	# Include incoming approach points as well as bodies already at contact.
	var neighbors: Array=crowd.nearby(target.position,maxf(MELEE_ENCOUNTER_RADIUS,radius+CrowdMelee.BODY_GAP+.0000001),true)
	var same_target: bool=int(unit.get("meleeGoalTargetId",-1))==int(target.id) and int(unit.get("meleeGoalGeneration",-1))==int(battle.battle_generation) and is_equal_approx(float(unit.get("meleeGoalRadius",-1.0)),radius)
	var previous_slot: int=int(unit.get("meleeGoalSlot",-1)) if same_target else -1
	var replan: bool=bool(unit.get("meleeGoalReplan",false)) and same_target
	var toward: Vector2=unit.get("meleeGoalBasis",Vector2.ZERO) if same_target else (unit.position-target.position).normalized()
	if toward.length_squared()<.5: toward=Vector2.RIGHT.rotated(float(int(unit.id)%12)*TAU/12.0)
	var previous_point: Vector2=Vector2(INF,INF)
	if same_target and unit.has("meleeGoalOffset"):
		previous_point=target.position+unit.meleeGoalOffset
		var previous_legal: bool=(not bounded or _guard_segment_safe(unit,unit.position,previous_point)) and land_segment_safe(unit.position,previous_point,.008) and (not _road_bound_march(unit) or _road_point_inside(previous_point,int(unit.postPathIndex))) and battle.advance_mission.friendly_goal_allowed(unit,previous_point)
		if previous_legal and not replan and crowd.melee_goal_pressure(previous_point,int(unit.id),int(target.id),neighbors,target.position,true)<=.000001:
			unit["meleeGoalPosition"]=previous_point
			return previous_point
		if not previous_legal: previous_point=Vector2(INF,INF)
	var best: Vector2=Vector2(INF,INF)
	var score: float=INF
	var selected_slot: int=-1
	var open_goal: Vector2=Vector2(INF,INF)
	var open_distance: float=INF
	var open_slot: int=-1
	var pressure_points: Array[Vector2]=crowd.melee_goal_pressure_points(int(unit.id),int(target.id),neighbors,target.position,true)
	var pressure_revision: int=crowd.motion_revision
	for index in range(12):
		# A failed approach tries another actual point, without reserving a
		# target/seat or excluding any other soldier from this enemy.
		if replan and index==previous_slot: continue
		var candidate: Vector2=target.position+toward.rotated(float(index)*TAU/12.0)*radius
		if _road_bound_march(unit) and not _road_point_inside(candidate,int(unit.postPathIndex)): continue
		if not battle.advance_mission.friendly_goal_allowed(unit,candidate): continue
		var distance: float=unit.position.distance_to(candidate)
		if pressure_revision!=crowd.motion_revision:
			pressure_points=crowd.melee_goal_pressure_points(int(unit.id),int(target.id),neighbors,target.position,true)
			pressure_revision=crowd.motion_revision
		var pressure: float=crowd.pressure_at_points(candidate,pressure_points)
		var value: float=distance+pressure*5.0
		var open: bool=pressure<=.000001
		# Symmetric slots have equal costs; float roundoff must not swap them.
		if open and distance>=open_distance-.000001: continue
		if not open and (open_goal.is_finite() or value>=score-.000001): continue
		if bounded and not _guard_segment_safe(unit,unit.position,candidate): continue
		if not land_segment_safe(unit.position,candidate,.008): continue
		if open: open_goal=candidate;open_distance=distance;open_slot=index
		else: best=candidate;score=value;selected_slot=index
	# An occupied near point cannot beat a free physical flank on either side.
	if open_goal.is_finite(): best=open_goal;selected_slot=open_slot
	if not best.is_finite() and previous_point.is_finite(): best=previous_point;selected_slot=previous_slot
	if best.is_finite():
		unit.erase("meleeGoalRouteRemaining")
		unit.merge({"meleeGoalTargetId":int(target.id),"meleeGoalGeneration":int(battle.battle_generation),"meleeGoalBasis":toward,"meleeGoalOffset":best-target.position,"meleeGoalPosition":best,"meleeGoalSlot":selected_slot,"meleeGoalRadius":radius,"meleeGoalEffort":0.0,"meleeGoalProgress":0.0,"meleeGoalReplan":false},true)
	return best

func _melee_walk(unit: Dictionary, target: Dictionary, delta: float, factor: float=1.0) -> void:
	var point: Vector2=_melee_point(unit,target)
	if not point.is_finite(): _walk(unit,float(unit.routeMin),delta,factor);return
	var previous: Vector2=unit.position
	var speed_value: float=(.065 if str(unit.type)=="commander" else .042)*float(unit.mobilityFactor)*factor
	var desired: Vector2=previous.move_toward(point,speed_value*delta)
	var legal: Callable=func(a: Vector2,b: Vector2) -> bool: return land_segment_safe(a,b,.008) and (not _road_bound_march(unit) or _road_point_inside(b,int(unit.postPathIndex))) and battle.advance_mission.friendly_goal_allowed(unit,b)
	unit.position=crowd.move_point(unit,desired,true,legal,point,true)
	_track_melee_progress(unit,previous,point,speed_value*delta)
	crowd.moved(unit,previous,true)
	unit.routeDistance=battle.advance_mission.marching_distance(unit) if bool(unit.get("advanceMissionGoal",false)) else point_distance(int(unit.postPathIndex),maxi(0,int(target.pointIndex)-1),unit.position)
	if unit.position.distance_squared_to(previous)>.000000001:
		unit.aim=(unit.position-previous).normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")

func finish_enemy_step(enemy: Dictionary, previous: Vector2) -> void:
	crowd.moved(enemy,previous,false)

func _on_unit_injured(unit: Dictionary) -> void:
	if float(unit.get("hp",0))<=0:
		release_melee_seat(unit)
		if not unit.get("guardDashData",{}).is_empty(): battle.unit_skills.finish_guard_dash(unit,false);unit["guardDashData"]={}
		unit["combatState"]="dead"
		unit["attackPlan"]={}
		unit["targetId"]=-1
		unit["blockCount"]=0
		if str(unit.get("supportPhase","")) in ["waiting","brawl","return"]:
			unit["supportPhase"]="done"
			unit["supportEndReason"]="unit_fallen"

func step(delta: float) -> void:
	_ensure_crowd_index()
	gather_groups.clear()
	for ally in battle.units:
		if str(ally.type)=="spear" and float(ally.get("hp",0))>0 and not bool(ally.get("consumed",false)) and str(ally.get("combatState",""))=="gather":
			# Direct native spawners share the same actual-roster commit hook.
			if bool(ally.get("gatherPendingBirth",false)): register_spear_birth(ally)
			var key: int=int(ally.get("gatherWindowId",0))
			if not gather_groups.has(key): gather_groups[key]=[]
			gather_groups[key].append(ally)
	for unit in battle.units:
		if not is_frontline(str(unit.type)): continue
		unit["chargeCooldown"]=maxf(0,float(unit.get("chargeCooldown",0))-delta*battle.unit_skills.cavalry_charge_factor(unit))
		if is_ambush(str(unit.type)):
			if float(unit.hp)<=0: _on_unit_injured(unit);continue
			_ambush_step(unit,delta)
			continue
		if is_marching(str(unit.type)):
			if float(unit.hp)<=0: _on_unit_injured(unit);continue
			if str(unit.get("supportPhase","")) in ["waiting","brawl","return"]:
				_marching_support_step(unit,delta)
				continue
			if str(unit.get("combatState",""))=="gather":
				_gather_step(unit,delta)
				if str(unit.combatState)=="gather": continue
			_marching_step(unit,delta)
			continue
		if str(unit.type)=="monk":
			if float(unit.hp)<=0: _on_unit_injured(unit);continue
			unit.combatState="guard"
			unit.attackPlan={}
			if str(unit.get("animation","idle"))!="heal": _set_animation(unit,"idle")
			continue
		if str(unit.type)=="naginata":
			_guard_step(unit,delta)
			continue
		if float(unit.hp)<=0: _on_unit_injured(unit);continue
		_gunner_step(unit,delta)
	_assign_blocks()

func _spear_gather_key(unit: Dictionary) -> String:
	return "%d:%s" % [int(unit.get("postPathIndex",-1)),str(unit.get("baseId",unit.get("postId","")))]

func _gather_step(unit: Dictionary, _delta: float) -> void:
	var window_id: int=int(unit.get("gatherWindowId",0))
	# Veterans do not enter a fresh wait merely because an old serialized or
	# development state still says gather. Only actual new births own a window.
	if str(unit.get("type",""))!="spear" or window_id<=0 or int(unit.get("gatherGeneration",-1))!=int(battle.battle_generation):
		unit.merge({"combatState":"march","gatherRemaining":0.0,"gatherGroupId":0},true)
		unit["gatherPendingBirth"]=false
		_set_animation(unit,"walk")
		return
	var tick: int=_spear_gather_clock()
	var deadline: int=int(unit.gatherDeadlineTick)
	unit["gatherRemaining"]=float(maxi(0,deadline-tick))/1000000.0
	if tick<deadline:
		_set_animation(unit,"idle")
		return
	var group: Array=[]
	var key: String=_spear_gather_key(unit)
	for ally in gather_groups.get(window_id,[]):
		# Recheck the live roster. A departed/dead member, another type, or a
		# cohort released earlier in this step cannot satisfy a new departure.
		if str(ally.get("type",""))!="spear" or float(ally.get("hp",0))<=0 or bool(ally.get("consumed",false)) or str(ally.get("combatState",""))!="gather": continue
		if int(ally.get("gatherWindowId",0))!=window_id or int(ally.get("gatherGeneration",-1))!=int(battle.battle_generation) or _spear_gather_key(ally)!=key: continue
		if not is_same(_unit(int(ally.id)),ally): continue
		group.append(ally)
	if group.is_empty(): group.append(unit)
	var window: Dictionary=spear_gather_windows.get(str(unit.get("gatherBaseKey",key)),{})
	if int(window.get("id",0))==window_id: window["closed"]=true
	for ally in group:
		ally["gatherGroupId"]=window_id
		ally["gatherRemaining"]=0.0
		ally["combatState"]="march"
		_set_animation(ally,"walk")

func is_base_attacker(enemy: Dictionary) -> bool:
	if enemy.is_empty() or float(enemy.get("hp",0))<=0: return false
	return str(enemy.get("combatRole",battle.enemy_role_contract(str(enemy.get("kind","raider"))).combatRole))=="emplacement_assault"

func is_tower_attacker(enemy: Dictionary) -> bool:
	# Enemy kind and scenery alone never establish a fixed attackable tower.
	return is_base_attacker(enemy) and bool(enemy.get("fortification",false)) and bool(enemy.get("stationaryEnemy",false)) and not bool(enemy.get("ingressActive",false))

func _zone_point(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if value is Vector2: return value
	if value is Dictionary: return Vector2(float(value.get("x",fallback.x)),float(value.get("y",fallback.y)))
	return fallback

func _guard_polygon(unit: Dictionary) -> PackedVector2Array:
	var points: PackedVector2Array=[]
	for point in unit.get("guardZone",{}).get("polygon",[]): points.append(_zone_point(point))
	return points

func guard_point_inside(unit: Dictionary, point: Vector2) -> bool:
	if not point.is_finite(): return false
	var footprint: float=float(unit.get("occupancyRadius",.008))
	var zone: Dictionary=unit.get("guardZone",{})
	var polygon: PackedVector2Array=_guard_polygon(unit)
	if polygon.size()>=3:
		if not Geometry2D.is_point_in_polygon(point,polygon): return false
		for index in range(polygon.size()):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[index],polygon[(index+1)%polygon.size()]))<footprint-.000001: return false
		return true
	var center: Vector2=_zone_point(zone.get("center",unit.get("homePosition",Vector2.ZERO)))
	var radius: float=float(zone.get("radius",unit.get("guardRadius",.15)))
	return radius>=footprint and center.distance_to(point)<=radius-footprint+.000001

func _guard_segment_safe(unit: Dictionary, start: Vector2, end: Vector2) -> bool:
	if not _combat_queries_ready(): return _guard_segment_safe_live(unit,start,end)
	var actor_id: int=int(unit.get("id",-1))
	var zone: Dictionary=unit.get("guardZone",{})
	var radius: float=float(unit.get("occupancyRadius",.008))
	var cached: Dictionary=_guard_segments.get(actor_id,{})
	if cached.is_empty() or float(cached.radius)!=radius or cached.home!=unit.get("homePosition",Vector2.ZERO) or float(cached.guardRadius)!=float(unit.get("guardRadius",.15)) or cached.zone!=zone:
		cached={"radius":radius,"home":unit.get("homePosition",Vector2.ZERO),"zone":zone.duplicate(true),"guardRadius":float(unit.get("guardRadius",.15)),"segments":{}}
	var ends: Dictionary=cached.segments.get(start,{})
	if ends.has(end): return bool(ends[end])
	var clear: bool=_guard_segment_safe_live(unit,start,end)
	if _guard_segment_count>=COMBAT_SEGMENT_CACHE_LIMIT: _guard_segments.clear();_guard_segment_count=0;cached.segments={};ends={}
	ends[end]=clear;cached.segments[start]=ends;_guard_segments[actor_id]=cached
	_guard_segment_count+=1
	return clear

func _guard_segment_safe_live(unit: Dictionary, start: Vector2, end: Vector2) -> bool:
	if not guard_point_inside(unit,start) or not guard_point_inside(unit,end): return false
	var footprint: float=float(unit.get("occupancyRadius",.008))
	if not land_segment_safe(start,end,footprint): return false
	var polygon: PackedVector2Array=_guard_polygon(unit)
	# Endpoint containment is insufficient for a concave polygon or a body
	# passing close to its edge. Test the entire swept capsule against edges.
	for index in range(polygon.size()):
		var a: Vector2=polygon[index]
		var b: Vector2=polygon[(index+1)%polygon.size()]
		if Geometry2D.segment_intersects_segment(start,end,a,b)!=null: return false
		var clearance: float=minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a,start,end)),b.distance_to(Geometry2D.get_closest_point_to_segment(b,start,end)))
		clearance=minf(clearance,minf(start.distance_to(Geometry2D.get_closest_point_to_segment(start,a,b)),end.distance_to(Geometry2D.get_closest_point_to_segment(end,a,b))))
		if clearance<footprint-.000001: return false
	return true

func _guard_navigation_nodes(unit: Dictionary) -> Array:
	var cacheable: bool=_combat_queries_ready()
	var actor_id: int=int(unit.get("id",-1))
	var trail: Array=unit.get("guardTrail",[])
	var zone: Dictionary=unit.get("guardZone",{})
	var radius: float=float(unit.get("occupancyRadius",.008))
	var home: Vector2=unit.get("homePosition",Vector2.ZERO)
	var cached: Dictionary=_guard_nodes.get(actor_id,{}) if cacheable else {}
	if not cached.is_empty() and cached.trail==trail and cached.zone==zone and float(cached.radius)==radius and cached.home==home and float(cached.guardRadius)==float(unit.get("guardRadius",.15)): return cached.nodes
	var nodes: Array=[]
	for point in trail:
		var candidate: Vector2=_zone_point(point)
		if guard_point_inside(unit,candidate) and not nodes.has(candidate): nodes.append(candidate)
	for point in zone.get("waypoints",[]):
		var candidate: Vector2=_zone_point(point)
		if guard_point_inside(unit,candidate) and not nodes.has(candidate): nodes.append(candidate)
	var polygon: PackedVector2Array=_guard_polygon(unit)
	if polygon.size()>=3:
		for inset in Geometry2D.offset_polygon(polygon,-radius-.001):
			for point in inset:
				if guard_point_inside(unit,point) and not nodes.has(point): nodes.append(point)
	if cacheable: _guard_nodes[actor_id]={"trail":trail.duplicate(true),"zone":zone.duplicate(true),"radius":radius,"home":home,"guardRadius":float(unit.get("guardRadius",.15)),"nodes":nodes}
	return nodes

func guard_path(unit: Dictionary, start: Vector2, end: Vector2) -> Array:
	if _guard_segment_safe(unit,start,end): return [start,end]
	var nodes: Array=_guard_navigation_nodes(unit)
	var cacheable: bool=_combat_queries_ready()
	var actor_id: int=int(unit.get("id",-1))
	var starts: Dictionary=_guard_routes.get(actor_id,{}) if cacheable else {}
	var ends: Dictionary=starts.get(start,{})
	var cached: Dictionary=ends.get(end,{})
	if not cached.is_empty() and is_same(cached.nodes,nodes): return cached.route.duplicate()
	var route: Array=_build_guard_path(unit,start,end,nodes)
	if cacheable:
		if _guard_route_count>=COMBAT_ROUTE_CACHE_LIMIT: _guard_routes.clear();_guard_route_count=0;starts={};ends={}
		ends[end]={"nodes":nodes,"route":route.duplicate()};starts[start]=ends;_guard_routes[actor_id]=starts
		_guard_route_count+=1
	return route

func _build_guard_path(unit: Dictionary, start: Vector2, end: Vector2, interior: Array) -> Array:
	var nodes: Array=[start,end]
	for point in interior:
		if not nodes.has(point): nodes.append(point)
	var distances: Array=[]
	var previous: Array=[]
	var visited: Array=[]
	for index in range(nodes.size()): distances.append(INF);previous.append(-1);visited.append(false)
	distances[0]=0.0
	for iteration in range(nodes.size()):
		var current: int=-1
		var best: float=INF
		for index in range(nodes.size()):
			if not bool(visited[index]) and float(distances[index])<best: current=index;best=float(distances[index])
		if current<0: break
		if current==1:
			var result: Array=[end]
			while current!=0:
				current=int(previous[current])
				if current<0: return []
				result.push_front(nodes[current])
			return result
		visited[current]=true
		for next in range(nodes.size()):
			if bool(visited[next]) or next==current or not _guard_segment_safe(unit,nodes[current],nodes[next]): continue
			var cost: float=best+(nodes[current] as Vector2).distance_to(nodes[next])
			if cost<float(distances[next]): distances[next]=cost;previous[next]=current
	return []

func _guard_strike_point(unit: Dictionary, enemy: Dictionary) -> Vector2:
	var cacheable: bool=_combat_queries_ready()
	var actor_id: int=int(unit.get("id",-1))
	var radius: float=reach(unit)
	var signature: Array=[unit.position,enemy.position,int(enemy.id),radius,unit.get("homePosition",Vector2.ZERO),float(unit.get("occupancyRadius",.008)),int(unit.get("meleeGoalTargetId",-1)),unit.get("meleeGoalOffset",Vector2(INF,INF)),bool(unit.get("meleeGoalReplan",false)),float(unit.get("guardRadius",.15)),unit.get("guardTrail",[]),unit.get("guardZone",{})]
	var cached: Dictionary=_strike_queries.get(actor_id,{}) if cacheable else {}
	if not cached.is_empty() and cached.signature==signature: return cached.point
	var point: Vector2=_guard_strike_point_live(unit,enemy)
	if cacheable: _strike_queries[actor_id]={"signature":signature.duplicate(true),"point":point}
	return point

func _guard_strike_point_live(unit: Dictionary, enemy: Dictionary) -> Vector2:
	if unit.position.distance_to(enemy.position)<=reach(unit)*.95 and _guard_segment_safe(unit,unit.position,unit.position): return unit.position
	# A retained physical contact goal is also the goal used by support
	# movement. Its exact route can be reused by _guard_walk below.
	if int(unit.get("meleeGoalTargetId",-1))==int(enemy.id) and unit.has("meleeGoalOffset") and not bool(unit.get("meleeGoalReplan",false)):
		var retained: Vector2=enemy.position+unit.meleeGoalOffset
		if retained.distance_to(enemy.position)<=reach(unit)*1.1 and land_segment_safe(retained,enemy.position,0.0) and guard_path(unit,unit.position,retained).size()>=2: return retained
	var from_target: Vector2=(unit.position-enemy.position).normalized()
	if from_target.length_squared()<.5: from_target=(unit.homePosition-enemy.position).normalized()
	var best: Vector2=Vector2(INF,INF)
	var best_length: float=INF
	for factor in [.5,.9]:
		for angle in [0.0,PI*.25,-PI*.25,PI*.5,-PI*.5,PI*.75,-PI*.75,PI]:
			var point: Vector2=enemy.position+from_target.rotated(float(angle))*reach(unit)*float(factor)
			if not land_segment_safe(point,enemy.position,0.0): continue
			var route: Array=guard_path(unit,unit.position,point)
			if route.is_empty(): continue
			var length: float=0.0
			for index in range(route.size()-1): length+=(route[index] as Vector2).distance_to(route[index+1])
			if length<best_length: best=point;best_length=length
	return best

func guard_target_valid(unit: Dictionary, enemy: Dictionary, for_strike: bool = false) -> bool:
	if not is_base_attacker(enemy) or float(unit.get("hp",0))<=0 or battle._sailing_visual(enemy) or not battle._enemy_visible(enemy): return false
	if int(enemy.get("pathIndex",-1))!=int(unit.get("postPathIndex",-2)): return false
	if unit.homePosition.distance_to(enemy.position)>float(battle._read_stats(unit).range): return false
	if not guard_point_inside(unit,unit.position): return false
	if for_strike:
		return unit.position.distance_to(enemy.position)<=reach(unit)*1.1 and land_segment_safe(unit.position,enemy.position,0.0)
	var point: Vector2=_guard_strike_point(unit,enemy)
	return point.is_finite() and land_segment_safe(point,enemy.position,0.0)

func ninja_route_valid(unit: Dictionary, enemy: Dictionary) -> bool:
	var cacheable: bool=_combat_queries_ready()
	var signature: Array=[unit.get("homePosition",Vector2.ZERO),unit.get("entryPosition",Vector2.ZERO),int(unit.get("postPathIndex",-1)),float(unit.get("homeDistance",0.0)),float(unit.get("routeMin",0.0)),float(unit.get("routeMax",0.0)),float(unit.get("occupancyRadius",.008)),enemy.position,int(enemy.get("pathIndex",-1)),int(enemy.get("pointIndex",-1))]
	var plan: Dictionary=unit.get("attackPlan",{})
	var action_bound: bool=cacheable and not str(plan.get("ninjaAction","")).is_empty() and int(plan.get("ninjaBattleGeneration",-1))==int(battle.battle_generation)
	var cached: Dictionary={}
	if action_bound: cached=plan.get("ninjaRouteCertificate",{})
	elif cacheable: cached=_ninja_routes.get(int(unit.id),{})
	if not cached.is_empty() and int(cached.navigationRevision)==navigation_query_revision and cached.signature==signature: return bool(cached.valid)
	var valid: bool=_ninja_route_valid_live(unit,enemy)
	if cacheable:
		var certificate: Dictionary={"navigationRevision":navigation_query_revision,"signature":signature.duplicate(true),"valid":valid}
		if action_bound: plan["ninjaRouteCertificate"]=certificate
		else: _ninja_routes[int(unit.id)]=certificate
	return valid

func _ninja_route_valid_live(unit: Dictionary, enemy: Dictionary) -> bool:
	var path_index: int=int(unit.get("postPathIndex",-1))
	if path_index<0 or path_index>=battle.paths.size() or path_index>=cumulative.size(): return false
	var footprint: float=float(unit.get("occupancyRadius",.008))
	var distance: float=enemy_distance(enemy)
	if distance<float(unit.get("routeMin",0)) or distance>float(unit.get("routeMax",0)): return false
	if not land_segment_safe(unit.homePosition,unit.entryPosition,footprint): return false
	if not land_route_safe(path_index,float(unit.homeDistance),distance,footprint): return false
	return land_segment_safe(route_point(path_index,distance),enemy.position,footprint)

func ninja_mission_target_valid(unit: Dictionary, enemy: Dictionary, for_strike: bool = false, fresh: bool = false) -> bool:
	if fresh: _live_check_depth+=1
	var valid: bool=_ninja_mission_target_valid_contents(unit,enemy,for_strike)
	if fresh: _live_check_depth=maxi(0,_live_check_depth-1)
	return valid

func _ninja_mission_target_valid_contents(unit: Dictionary, enemy: Dictionary, for_strike: bool) -> bool:
	if bool(unit.get("consumed",false)) or enemy.is_empty() or float(enemy.get("hp",0))<=0 or bool(enemy.get("escaped",false)) or float(unit.get("hp",0))<=0: return false
	if not battle._enemy_visible(enemy) or battle._sailing_visual(enemy) or bool(enemy.get("transportActive",false)) or bool(enemy.get("ingressActive",false)): return false
	# Ninja-only ground/fortification eligibility; guards retain their own rules.
	if not is_tower_attacker(enemy) and bool(enemy.get("stationaryEnemy",false)): return false
	if int(unit.get("priorityTargetId",-1))>=0 and int(enemy.id)!=int(unit.priorityTargetId): return false
	if int(enemy.get("pathIndex",-1))!=int(unit.get("postPathIndex",-2)): return false
	if unit.homePosition.distance_to(enemy.position)>float(battle._read_stats(unit).range)*2.0 or not ninja_route_valid(unit,enemy): return false
	if for_strike: return unit.position.distance_to(enemy.position)<=reach(unit)*1.1 and land_segment_safe(unit.position,enemy.position,0.0)
	return true

func _road_point_inside(point: Vector2, path_index: int) -> bool:
	if not point.is_finite() or path_index<0 or path_index>=battle.paths.size(): return false
	if not _combat_queries_ready(): return _road_point_inside_live(point,path_index)
	var points: Dictionary=_road_queries.get(path_index,{})
	if points.has(point): return bool(points[point])
	var inside: bool=_road_point_inside_live(point,path_index)
	if _road_query_count>=COMBAT_SEGMENT_CACHE_LIMIT:
		_road_queries.clear();_road_query_count=0;points={}
	points[point]=inside
	_road_queries[path_index]=points
	_road_query_count+=1
	return inside

func _road_point_inside_live(point: Vector2, path_index: int) -> bool:
	# Reuse the authored road footprint used by road_body_clear. The old
	# placement-center tolerance (.022) is too narrow for painted melee flanks.
	# Same-step requests from many spears reuse this exact point result;
	# callbacks, terrain changes and fresh impact checks bypass/invalidate it.
	var painted: bool=bool(battle.config.get("paintedPresentation",false))
	var art: Dictionary=battle.config.get("paintedComposition",{}).get("artSize",{"width":1831,"height":859})
	var metric: Vector2=Vector2(float(art.get("width",1831)),float(art.get("height",859))) if painted else Vector2.ONE
	var path: Dictionary=battle.paths[path_index]
	var half_width: float=float(path.get("paintedRoadHalfWidthPixels",PAINTED_ROAD_HALF_WIDTH_ART_PIXELS)) if painted else float(path.get("roadHalfWidth",float(path.get("roadWidth",.044))*.5))
	var measured: Vector2=point*metric
	for segment in range(path.points.size()-1):
		var nearest: Vector2=Geometry2D.get_closest_point_to_segment(measured,path.points[segment]*metric,path.points[segment+1]*metric)
		if measured.distance_squared_to(nearest)<=half_width*half_width+.00000001: return true
	return false

func primary_target_allowed(unit: Dictionary, target: Dictionary, stage: String = "prepare") -> bool:
	if bool(unit.get("consumed",false)) or not battle.can_friendly_target_enemy(unit,target): return false
	if str(unit.get("type",""))=="spear":
		# Road archers/matchlocks remain valid opponents. Structures and rear
		# hunters never pull a marching spear away from its own contact front.
		if bool(target.get("fortification",false)) or bool(target.get("stationaryEnemy",false)) or not shares_contact_front(unit,target): return false
	if _road_bound_march(unit):
		if not _road_point_inside(target.position,int(target.get("pathIndex",-1))):
			# An opponent already touching the road edge can be fought in place.
			# It cannot become a distant pursuit destination or a reason to leave.
			var contact_reach: float=reach(unit)*(1.1 if stage=="release" else .95)
			if unit.position.distance_to(target.position)>contact_reach: return false
	if is_marching(str(unit.get("type",""))) and str(unit.get("supportPhase","")) in ["waiting","brawl","return"]:
		if str(unit.supportPhase)=="waiting": return false
		if str(unit.supportPhase)=="return": return _support_contact_defense(unit,target)
		if not unit.get("supportEnemyIds",[]).has(int(target.get("id",-1))): return false
		return _support_member_valid(unit,target,stage=="release")
	if str(unit.get("type",""))=="naginata": return guard_target_valid(unit,target,stage=="release")
	if is_ambush(str(unit.get("type",""))): return ninja_mission_target_valid(unit,target,stage=="release")
	return true

func mark_ninja_consumed(unit: Dictionary, reason: String) -> void:
	if bool(unit.get("consumed",false)): return
	unit["consumed"]=true
	unit["consumeReason"]=reason
	battle.unit_skills.on_ninja_consumed(unit,reason)
	release_melee_seat(unit)
	var mission_id: int=int(unit.get("priorityTargetId",-1))
	unit["consumedTargetId"]=mission_id if mission_id>=0 else int(unit.get("targetId",-1))
	unit["priorityTargetId"]=-1
	unit["targetId"]=-1
	unit["attackPlan"]={}
	unit["ambushStrikeDone"]=false
	unit["combatState"]="consumed"
	_set_animation(unit,"idle")

func _guard_target(unit: Dictionary) -> Dictionary:
	var candidates: Array=[]
	var radius: float=float(battle._read_stats(unit).range)
	for enemy in battle.enemies:
		if not is_base_attacker(enemy) or battle._sailing_visual(enemy) or not battle._enemy_visible(enemy) or int(enemy.get("pathIndex",-1))!=int(unit.get("postPathIndex",-2)) or unit.homePosition.distance_to(enemy.position)>radius: continue
		candidates.append({"enemy":enemy,"distance":unit.position.distance_squared_to(enemy.position),"order":candidates.size()})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.distance)<float(b.distance) if float(a.distance)!=float(b.distance) else int(a.order)<int(b.order))
	for candidate in candidates:
		if guard_target_valid(unit,candidate.enemy): return candidate.enemy
	return {}

func _guard_route_length(route: Array) -> float:
	if route.size()<2: return INF
	var length: float=0.0
	for index in range(route.size()-1): length+=(route[index] as Vector2).distance_to(route[index+1])
	return length

func _guard_walk(unit: Dictionary, destination: Vector2, delta: float, factor: float = 1.0) -> bool:
	var previous: Vector2=unit.position
	var returning: bool=str(unit.get("combatState",""))=="support_return"
	var route: Array=[]
	var desired: Vector2=Vector2(INF,INF)
	if returning:
		var retained: Vector2=unit.get("supportReturnWaypoint",Vector2(INF,INF))
		var retained_destination: Vector2=unit.get("supportReturnWaypointDestination",Vector2(INF,INF))
		var same_geometry: bool=int(unit.get("supportReturnNavigationRevision",-1))==navigation_query_revision and float(unit.get("supportReturnWaypointRadius",-1.0))==float(unit.get("occupancyRadius",.008)) and unit.get("supportReturnWaypointZone",{})==unit.get("guardZone",{})
		if retained_destination==destination and same_geometry and retained.is_finite() and previous.distance_squared_to(retained)>.00000001 and _guard_segment_safe(unit,previous,retained):
			desired=retained;route=[previous,retained]
	if route.is_empty():
		route=guard_path(unit,previous,destination)
		if route.size()<2: unit["movementBlocked"]=true;_set_animation(unit,"idle");return false
		desired=route[1]
	unit["movementBlocked"]=false
	if returning:
		unit["supportReturnWaypoint"]=desired
		unit["supportReturnWaypointDestination"]=destination
		unit["supportReturnNavigationRevision"]=navigation_query_revision
		unit["supportReturnWaypointRadius"]=float(unit.get("occupancyRadius",.008))
		unit["supportReturnWaypointZone"]=unit.get("guardZone",{}).duplicate(true)
		var arrival_radius: float=maxf(.0001,minf(float(unit.get("occupancyRadius",.008)),CrowdMelee.BODY_GAP*.5))
		if previous.distance_squared_to(destination)<=arrival_radius*arrival_radius and land_segment_safe(previous,unit.supportReturnPosition,float(unit.get("occupancyRadius",.008))): return true
	var pace_factor: float=1.0 if is_marching(str(unit.type)) else 1.4
	var effort: float=.042*pace_factor*float(unit.mobilityFactor)*factor*delta
	var next: Vector2=previous.move_toward(desired,effort)
	var legal: Callable=func(a: Vector2,b: Vector2) -> bool: return _guard_segment_safe(unit,a,b)
	if is_marching(str(unit.type)): next=crowd.move_point(unit,next,true,legal,desired if returning else Vector2(INF,INF),returning)
	if not _guard_segment_safe(unit,previous,next): unit["movementBlocked"]=true;_set_animation(unit,"idle");return false
	unit.position=next
	if str(unit.get("combatState",""))=="support_advance" and int(unit.get("meleeGoalTargetId",-1))==int(unit.get("targetId",-1)):
		# Compare complete valid paths to the same retained final contact.
		# Replanning to a longer waypoint route subtracts progress as well.
		var on_first_segment: Vector2=Geometry2D.get_closest_point_to_segment(next,previous,desired)
		var remaining: float
		if route.size()==2 and on_first_segment.distance_squared_to(next)<=.000000000001:
			# A direct segment is the distance minimum. Bent visibility-graph
			# routes or lateral crowd detours must be solved from the new point.
			remaining=maxf(0.0,_guard_route_length(route)-previous.distance_to(next))
		else: remaining=_guard_route_length(guard_path(unit,unit.position,destination))
		if is_finite(remaining):
			var previous_remaining: float=float(unit.get("meleeGoalRouteRemaining",_guard_route_length(route)))
			unit["meleeGoalRouteRemaining"]=remaining
			_record_melee_progress(unit,previous_remaining-remaining,effort)
		else:
			unit["meleeGoalReplan"]=true
	crowd.moved(unit,previous,true)
	if str(unit.get("combatState","")) not in ["guard_return","support_return"]:
		var trail: Array=unit.get("guardTrail",[unit.homePosition])
		if str(unit.get("supportPhase",""))=="brawl":
			# Compression must retain every required corner, including turns
			# shorter than .003. Each retained link was an actual safe stride.
			if trail.is_empty(): trail.append(previous)
			if not _guard_segment_safe(unit,trail[-1],next) and (trail[-1] as Vector2).distance_squared_to(previous)>.000000000001: trail.append(previous)
			if trail.size()>=2 and _guard_segment_safe(unit,trail[-2],next): trail[-1]=next
			elif (trail[-1] as Vector2).distance_squared_to(next)>.000000000001: trail.append(next)
		elif trail.size()>=2 and _guard_segment_safe(unit,trail[-2],next): trail[-1]=next
		elif trail.is_empty() or (trail[-1] as Vector2).distance_to(next)>.003: trail.append(next)
		unit["guardTrail"]=trail
	var direction: Vector2=next-previous
	if direction.length_squared()>.000000001:
		unit.aim=direction.normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")
	return next.distance_squared_to(destination)<.00000001

func _guard_step(unit: Dictionary, delta: float) -> void:
	if float(unit.get("hp",0))<=0: _on_unit_injured(unit);return
	var dash: Dictionary=unit.get("guardDashData",{})
	var target: Dictionary={}
	var returning: bool=str(unit.get("combatState","guard"))=="guard_return"
	var previous_target_id: int=int(unit.get("targetId",-1))
	if not returning and str(unit.get("animation","idle"))=="attack":
		var prepared: Dictionary=battle._enemy(int(unit.get("attackPlan",{}).get("targetId",previous_target_id)))
		var same_dash: bool=dash.is_empty() or int(prepared.get("id",-1))==int(unit.get("guardDashTargetId",-2))
		if same_dash and guard_target_valid(unit,prepared,true): return
	if previous_target_id>=0:
		target=battle._enemy(previous_target_id)
		if not guard_target_valid(unit,target): returning=true;target={}
	if not dash.is_empty():
		target=battle._enemy(int(unit.get("guardDashTargetId",-1)))
		if not guard_target_valid(unit,target):
			battle.unit_skills.finish_guard_dash(unit,false)
			unit.guardDashData={}
			dash={}
			target={}
			returning=true
	if str(unit.get("animation","idle"))=="attack":
		var prepared: Dictionary=battle._enemy(int(unit.get("attackPlan",{}).get("targetId",unit.get("targetId",-1))))
		if not returning and guard_target_valid(unit,prepared,true): return
		unit["attackPlan"]={}
		_set_animation(unit,"idle")
		if not dash.is_empty(): battle.unit_skills.finish_guard_dash(unit,false);unit.guardDashData={};dash={}
		returning=true
	if not returning and target.is_empty(): target=_guard_target(unit)
	if returning: target={}
	if target.is_empty():
		if not dash.is_empty(): battle.unit_skills.finish_guard_dash(unit,false);unit.guardDashData={}
		unit.targetId=-1
		unit.combatState="guard_return"
		if _guard_walk(unit,unit.homePosition,delta):
			unit.combatState="guard"
			unit["guardTrail"]=[unit.homePosition]
			_set_animation(unit,"idle")
		return
	unit.targetId=int(target.id)
	var distance: float=unit.position.distance_to(target.position)
	if dash.is_empty() and distance>reach(unit):
		dash=battle.unit_skills.guard_dash(unit,target)
		if bool(dash.get("active",false)): unit.guardDashData=dash
		else: dash={}
	if distance>reach(unit)*.95:
		unit.combatState="guard_dash" if not dash.is_empty() else "guard_advance"
		var desired: Vector2=_guard_strike_point(unit,target)
		_guard_walk(unit,desired,delta,float(dash.get("speedFactor",1.0)))
		return
	unit.aim=(target.position-unit.position).normalized()
	unit.combatState="guard_engaged"
	_set_animation(unit,"idle")
	if not dash.is_empty():
		var stats: Dictionary=battle._read_stats(unit)
		var melee_seat: int=claim_melee_attack(unit,target,true,maxf(float(stats.interval),battle._animation_duration("attack")))
		if melee_seat<0: return
		unit.animation="attack"
		unit.animationClock=0.0
		unit.attackDuration=battle._animation_duration("attack")
		unit.cooldown=float(stats.interval)
		var plan: Dictionary=battle.unit_skills.prepare_attack(unit,target,float(stats.damage)*float(dash.get("damageFactor",1.0)),battle._impact_time("naginata"))
		plan["guardDash"]=true
		plan["skillId"]=str(dash.get("skillId","naginata_mana_dash"))
		plan["effectKind"]="dash"
		unit.attackPlan=plan
		if melee_seat>0: plan["meleeSeatToken"]=melee_seat

func _ambush_enemy(unit: Dictionary) -> Dictionary:
	var priority: Dictionary=battle._enemy(int(unit.get("priorityTargetId",-1)))
	if ninja_mission_target_valid(unit,priority): return priority
	if int(unit.get("priorityTargetId",-1))>=0: return {}
	var best: Dictionary={}
	for enemy in battle.enemies:
		if not ninja_mission_target_valid(unit,enemy): continue
		if best.is_empty() or _ninja_stronger_target(unit,enemy,best): best=enemy
	return best

func _ninja_stronger_target(unit: Dictionary, candidate: Dictionary, current: Dictionary) -> bool:
	for key in ["damage","maxHp","armor"]:
		var first: float=float(candidate.get(key,0.0))
		var second: float=float(current.get(key,0.0))
		if first!=second: return first>second
	var first_distance: float=_ninja_approach_distance(unit,candidate)
	var second_distance: float=_ninja_approach_distance(unit,current)
	if not is_equal_approx(first_distance,second_distance): return first_distance<second_distance
	return int(candidate.id)<int(current.id)

func _ninja_approach_distance(unit: Dictionary, target: Dictionary) -> float:
	var distance: float=enemy_distance(target)
	return unit.homePosition.distance_to(unit.entryPosition)+absf(float(unit.homeDistance)-distance)+route_point(int(unit.postPathIndex),distance).distance_to(target.position)

func _ambush_walk_point(unit: Dictionary, target: Vector2, delta: float) -> bool:
	var previous: Vector2=unit.position
	var next: Vector2=previous.move_toward(target,.052*1.4*float(unit.mobilityFactor)*delta)
	if not land_segment_safe(previous,target,float(unit.get("occupancyRadius",.008))): unit["movementBlocked"]=true;_set_animation(unit,"idle");return false
	unit["movementBlocked"]=false
	unit["position"]=next
	if next.distance_squared_to(previous)>.000000001:
		unit["aim"]=(next-previous).normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")
	return next.distance_squared_to(target)<.00000001

func _ambush_walk_route(unit: Dictionary, target_distance: float, delta: float) -> bool:
	var desired: float=clampf(target_distance,float(unit.routeMin),float(unit.routeMax))
	var distance: float=move_toward(float(unit.routeDistance),desired,.052*1.4*float(unit.mobilityFactor)*delta)
	var previous: Vector2=unit.position
	var path_index: int=int(unit.postPathIndex)
	var next: Vector2=route_point(path_index,distance)
	var footprint: float=float(unit.get("occupancyRadius",.008))
	if not land_route_safe(path_index,float(unit.routeDistance),desired,footprint) or not land_segment_safe(previous,next,footprint): unit["movementBlocked"]=true;_set_animation(unit,"idle");return false
	unit["movementBlocked"]=false
	unit["routeDistance"]=distance
	unit["position"]=next
	if next.distance_squared_to(previous)>.000000001:
		unit["aim"]=(next-previous).normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")
	return absf(distance-desired)<.0001

func _ambush_step(unit: Dictionary, delta: float) -> void:
	if bool(unit.get("consumed",false)): return
	var target: Dictionary={}
	var mission_id: int=int(unit.get("priorityTargetId",-1))
	if mission_id>=0:
		target=battle._enemy(mission_id)
		if target.is_empty(): mark_ninja_consumed(unit,"target_lost");return
		if float(target.get("hp",0))<=0: mark_ninja_consumed(unit,"target_defeated");return
		if not ninja_mission_target_valid(unit,target):
			mark_ninja_consumed(unit,"unreachable" if not ninja_route_valid(unit,target) else "target_lost")
			return
	else:
		target=_ambush_enemy(unit)
		if target.is_empty():
			var failure_reason: String="no_target"
			for candidate in battle.enemies:
				if float(candidate.get("hp",0))<=0 or int(candidate.get("pathIndex",-1))!=int(unit.get("postPathIndex",-2)) or not battle._enemy_visible(candidate) or battle._sailing_visual(candidate): continue
				if unit.homePosition.distance_to(candidate.position)>float(battle._read_stats(unit).range)*2.0: continue
				if not ninja_route_valid(unit,candidate):
					failure_reason="unreachable"
					unit["priorityTargetId"]=int(candidate.id)
					break
			mark_ninja_consumed(unit,failure_reason)
			return
		unit["priorityTargetId"]=int(target.id)
	unit["targetId"]=int(target.id)
	if str(unit.get("animation","idle"))=="attack": return
	unit["combatState"]="ambush_approach"
	if not bool(unit.onAmbushRoute):
		if _ambush_walk_point(unit,unit.entryPosition,delta): unit["onAmbushRoute"]=true
		elif bool(unit.get("movementBlocked",false)): mark_ninja_consumed(unit,"unreachable")
		return
	if unit.position.distance_to(target.position)>reach(unit)*.95:
		var distance: float=enemy_distance(target)
		var road_point: Vector2=route_point(int(unit.postPathIndex),distance)
		if bool(unit.get("ninjaFinalApproach",false)) or unit.position.distance_to(road_point)<=reach(unit)*.5:
			unit["ninjaFinalApproach"]=true
			var direction: Vector2=(unit.position-target.position).normalized()
			if direction.length_squared()<.5: direction=Vector2.RIGHT
			_ambush_walk_point(unit,target.position+direction*reach(unit)*.80,delta)
		else: _ambush_walk_route(unit,distance,delta)
		if bool(unit.get("movementBlocked",false)): mark_ninja_consumed(unit,"unreachable")
		return
	unit["aim"]=(target.position-unit.position).normalized()
	unit["combatState"]="engaged"
	_set_animation(unit,"idle")

func _support_enemy_on_field(enemy: Dictionary) -> bool:
	if enemy.is_empty() or bool(enemy.get("transportActive",false)): return false
	var point: Vector2=enemy.get("position",Vector2(INF,INF))
	return point.is_finite() and point.x>=0 and point.x<=1 and point.y>=0 and point.y<=1 and battle._enemy_visible(enemy) and not battle._sailing_visual(enemy)

func _support_member_eligible(unit: Dictionary, enemy: Dictionary) -> bool:
	if enemy.is_empty() or float(enemy.get("hp",0))<=0 or float(unit.get("hp",0))<=0: return false
	if int(enemy.get("pathIndex",-1))!=int(unit.get("postPathIndex",-2)) or not _support_enemy_on_field(enemy): return false
	return guard_point_inside(unit,unit.position) and guard_point_inside(unit,enemy.position)

func _support_member_valid(unit: Dictionary, enemy: Dictionary, for_strike: bool = false) -> bool:
	if not _support_member_eligible(unit,enemy): return false
	if for_strike: return unit.position.distance_to(enemy.position)<=reach(unit)*1.1 and land_segment_safe(unit.position,enemy.position,0.0)
	var point: Vector2=_guard_strike_point(unit,enemy)
	return point.is_finite() and land_segment_safe(point,enemy.position,0.0)

func _support_contact_defense(unit: Dictionary, enemy: Dictionary) -> bool:
	# Returning troops do not seek a fresh fight. Only already established
	# physical contact can interrupt their return, without any pursuit.
	return _support_enemy_on_field(enemy) and float(enemy.get("hp",0))>0 and enemy.get("contactUnitIds",[]).has(int(unit.id)) and shares_contact_front(unit,enemy) and unit.position.distance_to(enemy.position)<=reach(unit)*1.05 and land_segment_safe(unit.position,enemy.position,0.0)

func _support_target(unit: Dictionary) -> Dictionary:
	var pending: Dictionary=_pending_melee_target(unit)
	if not pending.is_empty() and not unit.get("supportExcludedIds",[]).has(int(pending.id)): return pending
	var previous: Dictionary=battle._enemy(int(unit.get("targetId",-1)))
	if not unit.get("supportExcludedIds",[]).has(int(previous.get("id",-1))) and primary_target_allowed(unit,previous): return previous
	var candidates: Array=[]
	for enemy_id in unit.get("supportEnemyIds",[]):
		if unit.get("supportExcludedIds",[]).has(int(enemy_id)): continue
		var enemy: Dictionary=battle._enemy(int(enemy_id))
		if not _support_member_eligible(unit,enemy): continue
		candidates.append({"enemy":enemy,"score":unit.position.distance_to(enemy.position)+crowd.target_penalty(int(enemy.id)),"order":candidates.size()})
	# Same nearest reachable target and same tie order as the original full
	# scan, but reachability is evaluated only until that winner is found.
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.score)<float(b.score) if float(a.score)!=float(b.score) else int(a.order)<int(b.order))
	for candidate in candidates:
		var enemy: Dictionary=candidate.enemy
		if not primary_target_allowed(unit,enemy): continue
		crowd.claim_target(int(enemy.id))
		return enemy
	return {}

func _support_wait_step(unit: Dictionary, delta: float) -> void:
	var key: String=str(unit.supportCohortKey)
	if support_cohorts.has(key):
		var cohort: Dictionary=support_cohorts[key]
		unit.supportEnemyIds=cohort.enemyIds.duplicate()
		unit["supportLockedAt"]=float(cohort.lockedAt)
		unit.supportPhase="brawl"
		return
	unit.supportWaitClock=float(unit.get("supportWaitClock",0.0))+delta
	var nearby: Array=crowd.nearby(unit.position,float(unit.guardRadius)*2.0,false)
	var candidates: Array=[]
	var target: Dictionary={}
	var closest: float=INF
	for enemy in nearby:
		if not _support_member_valid(unit,enemy): continue
		candidates.append(int(enemy.id))
		var distance: float=unit.position.distance_to(enemy.position)
		if distance<closest: closest=distance;target=enemy
	if target.is_empty():
		_begin_support_return(unit,"no_local_group")
		var previous: Vector2=unit.position
		_support_return_step(unit,delta)
		if str(unit.supportPhase)=="done" and unit.position==previous: _marching_step(unit,delta)
		return
	if closest<=reach(unit)*1.05 and land_segment_safe(unit.position,target.position,0.0):
		var cohort: Dictionary={"enemyIds":candidates.duplicate(),"lockedAt":float(battle.elapsed)}
		support_cohorts[key]=cohort
		# One production order shares one snapshot, including members not stepped yet.
		for ally in battle.units:
			if str(ally.get("supportCohortKey",""))!=key or float(ally.get("hp",0))<=0 or str(ally.get("supportPhase",""))!="waiting": continue
			ally.supportPhase="brawl"
			ally.supportEnemyIds=candidates.duplicate()
			ally["supportLockedAt"]=float(battle.elapsed)
		battle._event("support_cohort_locked","진지 지원대가 주변 적 무리와 교전합니다.",{"cohortId":key,"enemyIds":candidates.duplicate(),"postId":str(unit.supportPostId)})
		return
	unit.targetId=int(target.id)
	unit.combatState="support_advance"
	var point: Vector2=_melee_point(unit,target,true)
	if not point.is_finite(): point=_guard_strike_point(unit,target)
	if point.is_finite():
		_guard_walk(unit,point,delta,(.065/.042) if str(unit.type)=="commander" else 1.0)
		if bool(unit.get("movementBlocked",false)): _begin_support_return(unit,"unreachable_local_group")
	else: _begin_support_return(unit,"unreachable_local_group")

func _begin_support_return(unit: Dictionary, reason: String) -> void:
	_clear_melee_goal(unit)
	unit.erase("supportReturnWaypoint")
	unit.erase("supportReturnWaypointDestination")
	unit["supportPhase"]="return"
	unit["supportEndReason"]=reason
	unit["combatState"]="support_return"
	unit["supportReturnViaHome"]=true
	unit["targetId"]=-1
	unit["attackPlan"]={}
	_set_animation(unit,"idle")

func _finish_support_return(unit: Dictionary) -> void:
	unit["supportPhase"]="done"
	# Keep the actual foot position. Project that position and preserve its
	# lateral offset for the next real march stride; never snap to the join.
	initialize_march_departure(unit)
	unit["combatState"]="march"
	unit["targetId"]=-1
	unit["attackPlan"]={}
	unit["blockCount"]=0
	_set_animation(unit,"walk")

func _support_return_step(unit: Dictionary, delta: float) -> void:
	unit["combatState"]="support_return"
	if str(unit.get("animation","idle"))=="attack":
		var defender_target: Dictionary=battle._enemy(int(unit.get("attackPlan",{}).get("targetId",unit.get("targetId",-1))))
		if _support_contact_defense(unit,defender_target): return
		unit["attackPlan"]={}
		unit["targetId"]=-1
		_set_animation(unit,"idle")
	if bool(unit.get("supportReturnViaHome",true)):
		var before_home: Vector2=unit.position
		if not _guard_walk(unit,unit.homePosition,delta,(.065/.042) if str(unit.type)=="commander" else 1.0): return
		unit["supportReturnViaHome"]=false
		# At its birth position the home leg costs no movement. Continue now;
		# a real home stride has already spent this frame's movement budget.
		if unit.position!=before_home: return
	var destination: Vector2=unit.supportReturnPosition
	var previous: Vector2=unit.position
	var footprint: float=float(unit.get("occupancyRadius",.008))
	if not land_segment_safe(previous,destination,footprint):
		unit["movementBlocked"]=true
		_set_animation(unit,"idle")
		return
	var arrival_radius: float=maxf(.0001,minf(footprint,CrowdMelee.BODY_GAP*.5))
	if previous.distance_squared_to(destination)<=arrival_radius*arrival_radius:
		unit["movementBlocked"]=false
		_finish_support_return(unit)
		return
	var stride: float=(.065 if str(unit.type)=="commander" else .042)*float(unit.mobilityFactor)*delta
	var next: Vector2=previous.move_toward(destination,stride)
	# Several independent support orders may share this join point. Apply
	# the same body spacing as marching; never merge them on one coordinate.
	var legal: Callable=func(a: Vector2,b: Vector2) -> bool: return land_segment_safe(a,b,footprint)
	next=crowd.move_point(unit,next,true,legal,destination,true)
	unit["position"]=next
	crowd.moved(unit,previous,true)
	unit["movementBlocked"]=false
	if next.distance_squared_to(previous)>.000000001:
		unit["aim"]=(next-previous).normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")
	if next.distance_squared_to(destination)>arrival_radius*arrival_radius: return
	_finish_support_return(unit)

func _marching_support_step(unit: Dictionary, delta: float) -> void:
	if str(unit.supportPhase)=="waiting": _support_wait_step(unit,delta);return
	if str(unit.supportPhase)=="return": _support_return_step(unit,delta);return
	if str(unit.get("animation","idle"))=="attack":
		var prepared: Dictionary=battle._enemy(int(unit.get("attackPlan",{}).get("targetId",unit.get("targetId",-1))))
		if not unit.get("supportExcludedIds",[]).has(int(prepared.get("id",-1))) and primary_target_allowed(unit,prepared,"release"): return
	var target: Dictionary=_support_target(unit)
	if target.is_empty():
		_begin_support_return(unit,"local_group_resolved")
		_support_return_step(unit,delta)
		return
	if str(unit.get("animation","idle"))=="attack":
		var prepared: Dictionary=battle._enemy(int(unit.get("attackPlan",{}).get("targetId",unit.get("targetId",-1))))
		if primary_target_allowed(unit,prepared,"release"): return
		unit["attackPlan"]={}
		_set_animation(unit,"idle")
	unit["targetId"]=int(target.id)
	var mounted: bool=str(unit.type)=="commander"
	var charging: bool=mounted and battle.unit_skills.can_charge(unit) and float(unit.chargeCooldown)<=0.0
	if unit.position.distance_to(target.position)>reach(unit)*.95:
		unit["combatState"]="support_advance"
		var point: Vector2=_melee_point(unit,target,true)
		if not point.is_finite(): point=_guard_strike_point(unit,target)
		if not point.is_finite():
			unit.supportExcludedIds.append(int(target.id))
			unit.targetId=-1
			return
		var factor: float=((.065/.042) if mounted else 1.0)*(1.35 if charging else 1.0)
		_guard_walk(unit,point,delta,factor)
		if bool(unit.get("movementBlocked",false)):
			unit.supportExcludedIds.append(int(target.id))
			unit.targetId=-1
		return
	unit["aim"]=(target.position-unit.position).normalized()
	unit["combatState"]="support_engaged"
	_set_animation(unit,"idle")
	if charging:
		var melee_seat: int=claim_melee_attack(unit,target,true,maxf(float(battle._read_stats(unit).interval),battle._animation_duration("attack")))
		if melee_seat<0: return
		unit["animation"]="attack"
		unit["animationClock"]=0.0
		unit["attackDuration"]=battle._animation_duration("attack")
		unit["chargeCooldown"]=float(battle._read_stats(unit).interval)*6.0
		unit["cooldown"]=float(battle._read_stats(unit).interval)
		unit["attackPlan"]=battle.unit_skills.prepare_attack(unit,target,float(battle._read_stats(unit).damage)*2.2,battle._impact_time("commander"),true)
		if melee_seat>0: unit.attackPlan["meleeSeatToken"]=melee_seat

func _marching_step(unit: Dictionary, delta: float) -> void:
	if str(unit.get("animation","idle"))=="attack":
		if str(unit.combatState)!="impact": unit["combatState"]="engaged"
		return
	var target: Dictionary=_nearest_enemy(unit)
	if target.is_empty():
		_clear_melee_goal(unit)
		unit["targetId"]=-1
		unit["combatState"]="march"
		_walk(unit,float(unit.routeMin),delta)
		if absf(float(unit.routeDistance)-float(unit.routeMin))<.0001: unit["combatState"]="front"
		return
	unit["targetId"]=int(target.id)
	var mounted: bool=str(unit.type)=="commander"
	var charging: bool=mounted and battle.unit_skills.can_charge(unit) and float(unit.chargeCooldown)<=0.0
	if unit.position.distance_to(target.position)>reach(unit)*.95:
		unit["combatState"]="charge" if charging else "advance"
		_melee_walk(unit,target,delta,1.35 if charging else 1.0)
		return
	unit["aim"]=(target.position-unit.position).normalized()
	if charging:
		var melee_seat: int=claim_melee_attack(unit,target,true,maxf(float(battle._read_stats(unit).interval),battle._animation_duration("attack")))
		if melee_seat<0: unit["combatState"]="engaged";_set_animation(unit,"idle");return
		unit["combatState"]="impact"
		unit["animation"]="attack"
		unit["animationClock"]=0.0
		unit["attackDuration"]=battle._animation_duration("attack")
		unit["chargeCooldown"]=float(battle._read_stats(unit).interval)*6.0
		unit["cooldown"]=float(battle._read_stats(unit).interval)
		unit["attackPlan"]=battle.unit_skills.prepare_attack(unit,target,float(battle._read_stats(unit).damage)*2.2,battle._impact_time("commander"),true)
		if melee_seat>0: unit.attackPlan["meleeSeatToken"]=melee_seat
	else:
		unit["combatState"]="engaged"
		_set_animation(unit,"idle")

func _gunner_step(unit: Dictionary, _delta: float) -> void:
	# Matchlocks are placed shooters. Recruitment never sends them on a march.
	if str(unit.get("animation","idle"))=="attack":
		unit["combatState"]="engaged"
		return
	var target: Dictionary=attack_target(unit)
	if target.is_empty():
		unit["targetId"]=-1
		unit["combatState"]="guard"
		_set_animation(unit,"idle")
		return
	unit["targetId"]=int(target.id)
	unit["combatState"]="engaged"
	_set_animation(unit,"idle")

func _frontline_contact_reach(unit: Dictionary) -> float:
	# Rear-rank spear reach grants an attack, not a distant physical block.
	return (float(REACH.spear) if str(unit.type)=="spear" else reach(unit))*1.05

func _enemy_counter_reach(enemy: Dictionary, unit: Dictionary) -> float:
	return maxf(float(enemy.get("attackRange",enemy.get("meleeRange",.032))),_frontline_contact_reach(unit) if is_marching(str(unit.type)) else 0.0)

func _enemy_contact_valid(enemy: Dictionary, unit: Dictionary) -> bool:
	if enemy.is_empty() or unit.is_empty() or float(enemy.get("hp",0.0))<=0.0 or not is_frontline(str(unit.get("type",""))) or not can_fight(unit): return false
	if not is_same(battle._enemy(int(enemy.id)),enemy) or not is_same(_unit(int(unit.get("id",-1))),unit) or not battle.can_enemy_engage_unit(enemy,unit,true) or not shares_contact_front(unit,enemy): return false
	var distance: float=maxf(_frontline_contact_reach(unit),float(enemy.get("meleeRange",.032)))
	return not battle._sailing_visual(enemy) and not bool(enemy.get("transportActive",false)) and enemy.position.distance_squared_to(unit.position)<=distance*distance and land_segment_safe(enemy.position,unit.position,0.0)

func _assign_blocks() -> void:
	var generation: int=int(battle.battle_generation)
	for unit in battle.units:
		unit["blockCount"]=0
		unit["contactEnemyIds"]=[]
		unit["hostileContactEnemyIds"]=[]
	for enemy in battle.enemies:
		var previous: Array=enemy.get("contactUnitIds",[])
		var previous_blocks: Array=enemy.get("blockerUnitIds",previous)
		var contacts: Array=[]
		var blockers: Array=[]
		if float(enemy.hp)>0 and not battle._sailing_visual(enemy):
			for defender in crowd.nearby(enemy.position,.06,true):
				if not _enemy_contact_valid(enemy,defender): continue
				# Enemy contact is independent of the defender's chosen mission,
				# support cohort and blocking capacity. Every real attacker may queue.
				contacts.append(int(defender.id))
				defender.hostileContactEnemyIds.append(int(enemy.id))
				if primary_target_allowed(defender,enemy,"release") and (is_marching(str(defender.type)) or previous_blocks.has(int(defender.id)) or int(defender.blockCount)<capacity(defender)):
					blockers.append(int(defender.id))
					defender.contactEnemyIds.append(int(enemy.id))
					defender.blockCount=int(defender.blockCount)+1
					if not previous_blocks.has(int(defender.id)): battle.unit_skills.actions.try_spear_brace(defender,enemy)
				if generation!=int(battle.battle_generation) or battle.battle_closed or battle.finished: return
		enemy["contactUnitIds"]=contacts
		enemy["blockerUnitIds"]=blockers
		enemy["blockedBy"]=int(blockers[0]) if not blockers.is_empty() else -1
		var plan: Dictionary=enemy.get("counterPlan",{})
		if not plan.is_empty() and not _counter_target_valid(enemy,_unit(int(plan.targetId))): cancel_counterattack(enemy)

func blocked(enemy: Dictionary) -> bool:
	for id in enemy.get("blockerUnitIds",enemy.get("contactUnitIds",[])):
		if _enemy_contact_valid(enemy,_unit(int(id))): return true
	return false

func enemy_contact(enemy: Dictionary) -> bool:
	for id in enemy.get("contactUnitIds",[]):
		if _enemy_contact_valid(enemy,_unit(int(id))): return true
	return false

func _counter_target_valid(enemy: Dictionary, unit: Dictionary) -> bool:
	if enemy.is_empty() or unit.is_empty() or bool(battle.battle_closed) or bool(battle.finished): return false
	if not battle.can_enemy_engage_unit(enemy,unit,true) or not is_same(battle._enemy(int(enemy.get("id",-1))),enemy) or not is_same(_unit(int(unit.get("id",-1))),unit): return false
	if not battle.emplacement_release_allowed(enemy,unit): return false
	var own_range: float=_enemy_counter_reach(enemy,unit)
	return float(enemy.get("hp",0))>0 and float(unit.get("hp",0))>0 and enemy.position.distance_to(unit.position)<=own_range and land_segment_safe(enemy.position,unit.position,0.0)

func counter_impact_allowed(enemy: Dictionary, unit: Dictionary, impact: Dictionary) -> bool:
	if territorial_melee_enabled: return melee_release_allowed(enemy,unit,impact,false)
	_live_check_depth+=1
	var valid: bool=_counter_target_valid(enemy,unit)
	_live_check_depth=maxi(0,_live_check_depth-1)
	return valid

func _active_enemy_melee(enemy: Dictionary) -> bool:
	return float(enemy.get("hp",0.0))>0.0 and not bool(enemy.get("stationaryEnemy",false)) and not bool(enemy.get("transportActive",false)) and not bool(enemy.get("ingressActive",false)) and not bool(enemy.get("hunterReturning",false)) and not enemy.has("attackRange") and not battle._sailing_visual(enemy)

func _unit_has_local_melee(unit: Dictionary, joining_id: int) -> bool:
	for id in unit.get("hostileContactEnemyIds",unit.get("contactEnemyIds",[])):
		if int(id)==joining_id: continue
		var front: Dictionary=battle._enemy(int(id))
		if not front.is_empty() and _counter_target_valid(front,unit): return true
	return false

func _enemy_approach_target_valid(enemy: Dictionary, unit: Dictionary) -> bool:
	if unit.is_empty() or not is_frontline(str(unit.get("type",""))) or not can_fight(unit) or bool(unit.get("consumed",false)): return false
	if int(unit.get("postPathIndex",-1))!=int(enemy.get("pathIndex",-2)) or not is_same(_unit(int(unit.id)),unit) or not battle.can_enemy_engage_unit(enemy,unit,true): return false
	# Territorial participation starts with any real nearby opponent. Requiring
	# some OTHER enemy to be in contact first leaves every new front waiting
	# for an existing 1:1 fight before it is even allowed to approach.
	if not territorial_melee_enabled and not _unit_has_local_melee(unit,int(enemy.id)): return false
	return enemy.position.distance_squared_to(unit.position)<=MELEE_ENCOUNTER_RADIUS*MELEE_ENCOUNTER_RADIUS and land_segment_safe(enemy.position,unit.position,0.0)

func _clear_enemy_melee_approach(enemy: Dictionary) -> void:
	enemy["meleeApproachTargetId"]=-1
	enemy["meleeApproachActive"]=false
	enemy.erase("meleeApproachOffset");enemy.erase("meleeApproachGoal")

func _enemy_melee_goal_legal(enemy: Dictionary, unit: Dictionary, point: Vector2, radius: float) -> bool:
	if not point.is_finite() or not Rect2(.008,.008,.984,.984).has_point(point) or point.distance_to(unit.position)>radius+.000001: return false
	var clearance: float=maxf(float(unit.get("occupancyRadius",.008)),CrowdMelee.BODY_GAP*.5)+CrowdMelee.BODY_GAP*.5
	if unit.position.distance_to(Geometry2D.get_closest_point_to_segment(unit.position,enemy.position,point))<clearance: return false
	return land_segment_safe(enemy.position,point,.008) and land_segment_safe(point,unit.position,0.0)

func _enemy_melee_goal(enemy: Dictionary, unit: Dictionary) -> Vector2:
	var radius: float=_enemy_counter_reach(enemy,unit)*.82
	var neighbors: Array=crowd.nearby(unit.position,MELEE_ENCOUNTER_RADIUS,false)
	var same: bool=int(enemy.get("meleeApproachTargetId",-1))==int(unit.id) and int(enemy.get("meleeApproachGeneration",-1))==int(battle.battle_generation) and is_equal_approx(float(enemy.get("meleeApproachRadius",-1.0)),radius)
	if same and enemy.has("meleeApproachOffset"):
		var retained: Vector2=unit.position+enemy.meleeApproachOffset
		if _enemy_melee_goal_legal(enemy,unit,retained,radius) and crowd.melee_goal_pressure(retained,int(enemy.id),int(unit.id),neighbors,unit.position)<=.000001:
			enemy["meleeApproachGoal"]=retained
			return retained
	var basis: Vector2=(enemy.position-unit.position).normalized()
	if basis.length_squared()<.5: basis=Vector2.RIGHT.rotated(float(int(enemy.id)%12)*TAU/12.0)
	var sign_value: float=-1.0 if int(enemy.id)%2==0 else 1.0
	var best: Vector2=Vector2(INF,INF)
	var score: float=INF
	var open_goal: Vector2=Vector2(INF,INF)
	var open_distance: float=INF
	var pressure_points: Array[Vector2]=crowd.melee_goal_pressure_points(int(enemy.id),int(unit.id),neighbors,unit.position)
	var pressure_revision: int=crowd.motion_revision
	for step in [0.0,1.0*sign_value,-1.0*sign_value,2.0*sign_value,-2.0*sign_value,3.0*sign_value,-3.0*sign_value,4.0*sign_value,-4.0*sign_value,5.0*sign_value,-5.0*sign_value,6.0]:
		var point: Vector2=unit.position+basis.rotated(float(step)*TAU/12.0)*radius
		var distance: float=enemy.position.distance_to(point)
		if pressure_revision!=crowd.motion_revision:
			pressure_points=crowd.melee_goal_pressure_points(int(enemy.id),int(unit.id),neighbors,unit.position)
			pressure_revision=crowd.motion_revision
		var pressure: float=crowd.pressure_at_points(point,pressure_points)
		var cost: float=distance+pressure*5.0
		var open: bool=pressure<=.000001
		if open and distance>=open_distance-.000001: continue
		if not open and (open_goal.is_finite() or cost>=score-.000001): continue
		if not _enemy_melee_goal_legal(enemy,unit,point,radius): continue
		if open: open_goal=point;open_distance=distance
		else: best=point;score=cost
	# A closer occupied front point must not beat an available flank. If no
	# open legal point exists, normal body spacing controls the fallback.
	if open_goal.is_finite(): best=open_goal
	if best.is_finite():
		enemy["meleeApproachTargetId"]=int(unit.id)
		enemy["meleeApproachGeneration"]=int(battle.battle_generation)
		enemy["meleeApproachRadius"]=radius
		enemy["meleeApproachOffset"]=best-unit.position
		enemy["meleeApproachGoal"]=best
	return best

func enemy_melee_step(enemy: Dictionary, delta: float) -> bool:
	# Approach an actual local front, including its first contact. Ingress,
	# hunters, stationary shooters and remote allies retain their controllers.
	if str(enemy.get("combatRole",""))!="path_assault" or not _active_enemy_melee(enemy): _clear_enemy_melee_approach(enemy);return false
	var unit: Dictionary=_unit(int(enemy.get("meleeApproachTargetId",-1)))
	if not _enemy_approach_target_valid(enemy,unit):
		unit={}
		var nearest: float=INF
		for candidate in crowd.nearby(enemy.position,MELEE_ENCOUNTER_RADIUS,true):
			var distance: float=enemy.position.distance_squared_to(candidate.position)
			if distance>=nearest or not _enemy_approach_target_valid(enemy,candidate): continue
			unit=candidate;nearest=distance
	if unit.is_empty(): _clear_enemy_melee_approach(enemy);return false
	if _counter_target_valid(enemy,unit):
		counterattack(enemy,delta,unit)
		return true
	var goal: Vector2=_enemy_melee_goal(enemy,unit)
	if not goal.is_finite(): _clear_enemy_melee_approach(enemy);return false
	enemy["meleeApproachActive"]=true
	var generation: int=int(battle.battle_generation)
	battle._enemy_threat_walk(enemy,goal,delta,.008,true)
	if generation!=int(battle.battle_generation) or battle.battle_closed or battle.finished or not is_same(battle._enemy(int(enemy.id)),enemy) or float(enemy.get("hp",0.0))<=0.0: return true
	enemy["routeProgress"]=maxf(float(enemy.get("routeProgress",0.0)),enemy_distance(enemy))
	if _counter_target_valid(enemy,unit): counterattack(enemy,delta,unit)
	else: enemy["attackCooldown"]=maxf(0.0,float(enemy.get("attackCooldown",0.0))-delta)
	return true

func cancel_counterattack(enemy: Dictionary, keep_seat: bool = false) -> void:
	# Cancellation spends no damage, but never resets an attacker's cooldown.
	if not keep_seat and not enemy.get("counterPlan",{}).is_empty(): release_melee_seat(enemy)
	_set_counter_plan(enemy,{})

func _set_counter_plan(enemy: Dictionary, plan: Dictionary) -> void:
	enemy["counterPlan"]=plan
	var mirror: Dictionary={}
	if not plan.is_empty(): mirror[int(plan.targetId)]=plan
	# Read-only compatibility view: zero or one committed target, not a budget
	# for every contact. Existing renderer and diagnostics can keep reading it.
	enemy["counterPlans"]=mirror
	enemy["contactCooldowns"]={}

func remove_contact(enemy: Dictionary, unit_id: int) -> void:
	var contacts: Array=enemy.get("contactUnitIds",[])
	contacts.erase(unit_id)
	enemy["contactUnitIds"]=contacts
	var blockers: Array=enemy.get("blockerUnitIds",contacts).duplicate()
	blockers.erase(unit_id)
	enemy["blockerUnitIds"]=blockers
	enemy["blockedBy"]=int(blockers[0]) if not blockers.is_empty() else -1
	if int(enemy.get("meleeApproachTargetId",-1))==unit_id: _clear_enemy_melee_approach(enemy)
	if int(enemy.get("counterPlan",{}).get("targetId",-1))==unit_id: cancel_counterattack(enemy)

func _next_counter_target(enemy: Dictionary, ids: Array) -> Dictionary:
	var waiting: Dictionary=melee_waiters.get(int(enemy.id),{})
	if not waiting.is_empty() and not bool(waiting.get("friendly",true)) and ids.has(int(waiting.targetId)):
		var committed: Dictionary=_unit(int(waiting.targetId))
		if _counter_target_valid(enemy,committed): return committed
	var living: Array=[]
	for id in ids:
		if living.has(int(id)): continue
		if _counter_target_valid(enemy,_unit(int(id))): living.append(int(id))
	if living.is_empty(): return {}
	living.sort()
	var previous: int=int(enemy.get("counterTargetCursor",-1))
	for id in living:
		if int(id)>previous: return _unit(int(id))
	return _unit(int(living[0]))

func _close_counter_gap(enemy: Dictionary, ids: Array, delta: float) -> void:
	# Already established physical contact retains the old ingress/return
	# interruption behavior. Only new local pursuit uses the stricter gate.
	if bool(enemy.get("stationaryEnemy",false)) or enemy.has("attackRange") or bool(enemy.get("transportActive",false)) or battle._sailing_visual(enemy): return
	var ordered: Array=[]
	var retained: int=int(enemy.get("meleeApproachTargetId",-1))
	if ids.has(retained): ordered.append(retained)
	for id in ids:
		if not ordered.has(int(id)): ordered.append(int(id))
	for id in ordered:
		var unit: Dictionary=_unit(int(id))
		if unit.is_empty() or not _enemy_contact_valid(enemy,unit) or _counter_target_valid(enemy,unit): continue
		var goal: Vector2=_enemy_melee_goal(enemy,unit)
		if not goal.is_finite(): continue
		enemy["meleeApproachActive"]=true
		battle._enemy_threat_walk(enemy,goal,delta,.008,true)
		return

func counterattack(enemy: Dictionary, delta: float, target: Dictionary = {}) -> void:
	if bool(enemy.get("counterReleaseInProgress",false)) or float(enemy.get("hp",0))<=0 or battle.finished or battle.battle_closed: return
	if not is_same(battle._enemy(int(enemy.get("id",-1))),enemy): return
	if not target.is_empty() and not is_same(_unit(int(target.get("id",-1))),target): return
	var generation: int=int(battle.battle_generation)
	var ids: Array=enemy.get("contactUnitIds",[]).duplicate() if target.is_empty() else [int(target.id)]
	# One ordinary attacker has one cadence regardless of its contact count.
	# Ranged and melee attacks share this same attacker-owned budget.
	enemy["attackCooldown"]=maxf(0.0,float(enemy.get("attackCooldown",0.0))-maxf(0.0,delta))
	if float(enemy.get("skillAttackDelayUntil",0.0))>float(battle.elapsed): return
	var plan: Dictionary=enemy.get("counterPlan",{})
	var unit: Dictionary=_unit(int(plan.get("targetId",-1)))
	if not plan.is_empty() and (not _counter_target_valid(enemy,unit) or not melee_release_allowed(enemy,unit,plan,false)):
		cancel_counterattack(enemy)
		plan={}
	if not plan.is_empty():
		# The target and facing belong to this preparation until release/cancel.
		battle._aim_enemy_attack(enemy,unit,delta)
		plan.age=float(plan.get("age",0.0))+maxf(0.0,delta)
		if maxf(float(plan.age),float(enemy.get("animationClock",0.0)))>=float(plan.releaseTime):
			cancel_counterattack(enemy,true)
			enemy["counterReleaseInProgress"]=true
			var impact: Dictionary={"attackId":str(plan.attackId),"impactId":str(plan.attackId)+":victim:"+str(unit.id),"contactCounter":true,"counterTargetLimit":1,"meleeSeatToken":int(plan.get("meleeSeatToken",-1))}
			battle._combat_event("shot",enemy,unit,impact)
			if generation==int(battle.battle_generation) and _counter_target_valid(enemy,unit) and melee_release_allowed(enemy,unit,plan,false): battle._damage_friendly(unit,float(plan.damage),enemy,impact)
			enemy["counterReleaseInProgress"]=false
			return
		return
	unit=_next_counter_target(enemy,ids)
	if unit.is_empty():
		_close_counter_gap(enemy,ids,delta)
		return
	if float(enemy.attackCooldown)<=0.0:
		var interval: float=1.1 if str(enemy.get("originKind",enemy.kind)) in ["heavy","commander"] else .95
		var melee_seat: int=claim_melee_attack(enemy,unit,false,maxf(.5,interval))
		if melee_seat<0:
			if str(enemy.get("animation",""))!="attack" or float(enemy.get("animationClock",0.0))>=.5:
				enemy["animation"]="idle"
			return
		var serial: int=int(enemy.get("contactAttackSerial",0))+1
		enemy["contactAttackSerial"]=serial
		enemy["counterTargetCursor"]=int(unit.id)
		plan={"targetId":int(unit.id),"age":0.0,"releaseTime":.25,"damage":(4.0+float(enemy.get("counterWave",battle.wave))*.6)*float(enemy.damage),"attackId":"%d:%d:%d:%d" % [generation,int(enemy.id),serial,int(unit.id)]}
		enemy["attackCooldown"]=interval
		enemy["rangedPlan"]={}
		_set_counter_plan(enemy,plan)
		enemy["meleeApproachActive"]=false
		if melee_seat>0: plan["meleeSeatToken"]=melee_seat
		enemy["attackFacingTargetId"]=int(unit.id)
		enemy["attackFacingIsRanged"]=false
		battle._aim_enemy_attack(enemy,unit,delta)
		enemy["animation"]="attack"
		enemy["animationClock"]=0.0
	elif str(enemy.get("animation",""))=="attack" and float(enemy.get("animationClock",0))>=.5:
		enemy.animation="idle"
		enemy.animationClock=0.0

func attack_target(unit: Dictionary) -> Dictionary:
	if str(unit.type)=="monk": return {}
	if not can_fight(unit): return {}
	var counter: Dictionary=battle.unit_skills.actions.counter_target(unit)
	if not counter.is_empty(): return counter
	var pending: Dictionary=_pending_melee_target(unit)
	if not pending.is_empty(): return pending
	if is_marching(str(unit.type)) and str(unit.get("supportPhase","")) in ["waiting","brawl","return"]:
		var support_target: Dictionary={}
		var nearest: float=INF
		for enemy in battle.enemies:
			if not primary_target_allowed(unit,enemy,"release"): continue
			var distance: float=unit.position.distance_squared_to(enemy.position)
			if distance<nearest: support_target=enemy;nearest=distance
		return support_target
	if is_ambush(str(unit.type)) and (str(unit.combatState)!="engaged" or bool(unit.get("ambushStrikeDone",false))): return {}
	if str(unit.type)=="naginata" or is_ambush(str(unit.type)):
		var primary: Dictionary=battle._enemy(int(unit.get("priorityTargetId",unit.get("targetId",-1))) if is_ambush(str(unit.type)) else int(unit.get("targetId",-1)))
		return primary if primary_target_allowed(unit,primary,"release") else {}
	var shooter: bool=str(unit.type)=="gunner"
	if shooter and str(unit.get("animation","idle"))=="walk": return {}
	var hit_range: float=float(battle._read_stats(unit).range) if shooter else reach(unit)
	if is_marching(str(unit.type)):
		var committed: Dictionary=battle._enemy(int(unit.get("targetId",-1)))
		if not committed.is_empty() and primary_target_allowed(unit,committed,"release") and shares_contact_front(unit,committed) and unit.position.distance_to(committed.position)<=hit_range and land_segment_safe(unit.position,committed.position,0.0): return committed
	var best: Dictionary={}
	var progress: float=-1
	for enemy in crowd.nearby(unit.position,hit_range,false):
		if float(enemy.hp)<=0 or not shares_contact_front(unit,enemy) or not battle._enemy_visible(enemy) or battle._sailing_visual(enemy): continue
		if not primary_target_allowed(unit,enemy,"release"): continue
		if not battle.can_friendly_target_enemy(unit,enemy) or unit.position.distance_to(enemy.position)>hit_range: continue
		if not land_segment_safe(unit.position,enemy.position): continue
		var distance: float=enemy_distance_for_unit(unit,enemy)
		if shooter and (distance<float(unit.get("routeMin",0)) or distance>float(unit.routeMax) or absf(distance-float(unit.homeDistance))>float(unit.guardRadius)): continue
		if distance>progress: best=enemy;progress=distance
	return best

func stance(unit: Dictionary) -> String:
	if is_ambush(str(unit.type)):
		return {"ambush_seek":"암살 표적 확인","ambush_approach":"적 고정 진지 접근","engaged":"단검 암살","consumed":"임무 종료 · 소모됨","dead":"전사"}.get(str(unit.get("combatState","ambush_seek")),"기습 준비")
	if str(unit.type)=="monk": return "고정 치료 · 아군 지원" if float(unit.get("hp",0))>0 else "전사"
	if str(unit.type)=="naginata":
		return {"guard":"사격 진지 호위 대기","guard_advance":"수비선 안 접근","guard_engaged":"호위선 쓸기","guard_dash":"마나 돌진","guard_return":"원래 호위점 복귀","dead":"전사"}.get(str(unit.get("combatState","guard")),"호위 준비")
	if str(unit.type)=="gunner":
		return {"guard":"전선 사격 대기","advance":"사격 거리 접근","engaged":"정지 사격","return":"방어 지점 복귀","retreat":"부상 후퇴","recover":"회복 중"}.get(str(unit.get("combatState","guard")),"대기")
	if not is_ground(str(unit.type)): return "고정 진지 사격"
	if str(unit.get("supportPhase","")) in ["waiting","brawl","return"]:
		return {"support_advance":"진지 주변 한 무리 접근","support_engaged":"진지 주변 무리와 교전","support_return":"일회 지원 종료 · 전진로 복귀"}.get(str(unit.get("combatState","")),"일회 진지 지원")
	return {"gather":"첫 창병 생성 후 3초 집결","march":"적 진입구로 진군","front":"전방 교전 대기","advance":"적에게 접근","engaged":"근접 교전","charge":"돌격 중","impact":"돌격 타격","dead":"전사"}.get(str(unit.get("combatState","march")),"진군 준비")

func cease_combat() -> void:
	melee_seats.clear()
	melee_waiters.clear()
	melee_last_served.clear()
	melee_components.clear()
	melee_members.clear()
	melee_limits.clear()
	melee_seat_groups.clear()
	melee_waiter_groups.clear()
	melee_query_clock=-INF
	_clear_melee_phase()
	crowd.clear()
	crowd_generation=-1
	for unit in battle.units:
		if not unit.get("guardDashData",{}).is_empty(): battle.unit_skills.finish_guard_dash(unit,false);unit.guardDashData={}
		unit["blockCount"]=0
		unit["targetId"]=-1
		unit["attackPlan"]={}
		unit["animation"]="idle"
		unit["animationClock"]=0.0
		unit["deploying"]=false
		if is_marching(str(unit.type)):
			unit["combatState"]="march" if float(unit.get("hp",0))>0 else "dead"
		elif is_ambush(str(unit.type)):
			mark_ninja_consumed(unit,"battle_ended")
		elif is_frontline(str(unit.type)) and str(unit.combatState)!="recover":
			unit["combatState"]="guard"
	for enemy in battle.enemies:
		enemy["blockedBy"]=-1
		enemy["contactUnitIds"]=[]
		enemy["blockerUnitIds"]=[]
		_clear_enemy_melee_approach(enemy)
		enemy["counterPlans"]={}
		enemy["contactCooldowns"]={}
		enemy["counterPlan"]={}
