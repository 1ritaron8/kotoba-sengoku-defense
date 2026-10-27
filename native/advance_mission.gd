extends RefCounted
## Stage02 only: required road enemies, a contested hold, then real reinforcements.
## This controller never applies damage, changes a stat, or relocates an actor.
const GroundCombat = preload("res://native/ground_combat.gd")

var battle: Node2D
var enabled: bool=false
var generation: int=-1
var settings: Dictionary={}
var phase: String="guards"
var complete: bool=false
var failed: bool=false
var failure_reason: String=""
var captured: bool=false
var started: bool=false
var capture_point: Vector2=Vector2.ZERO
var capture_distance: float=0.0
var path_index: int=0
var capture_radius: float=.085
var contest_radius: float=.11
var hold_required: float=10.0
var hold_seconds: float=0.0
var guard_required: int=6
var followup_required: int=2
var arrival_radius: float=.075
var guards: Array=[]
var followups: Array=[]
var arrived: Dictionary={}
var guards_remaining: int=6
var occupied: bool=false
var contested: bool=false

func bind(value: Node2D) -> void:
	battle=value

func reset(config: Dictionary) -> void:
	generation=int(battle.battle_generation)
	settings=config.get("advanceMission",{}).duplicate(true)
	enabled=str(config.get("id",""))=="basic-farm" and not settings.is_empty() and not bool(config.get("trainingOnly",false))
	phase="guards";complete=false;failed=false;failure_reason="";captured=false;started=false
	hold_seconds=0.0;guards.clear();followups.clear();arrived.clear()
	occupied=false;contested=false
	if not enabled: return
	path_index=int(settings.get("pathIndex",0))
	capture_point=battle._point(settings.get("capturePoint",{}))
	capture_radius=maxf(.015,float(settings.get("captureRadius",.085)))
	contest_radius=maxf(capture_radius,float(settings.get("contestRadius",.11)))
	hold_required=maxf(.1,float(settings.get("holdSeconds",10.0)))
	guard_required=clampi(int(settings.get("requiredGuardCount",6)),1,12)
	followup_required=clampi(int(settings.get("followupCount",2)),1,4)
	arrival_radius=maxf(.015,float(settings.get("followupArrivalRadius",.075)))
	guards_remaining=guard_required
	if path_index<0 or path_index>=battle.paths.size() or not capture_point.is_finite() or not Rect2(0,0,1,1).has_point(capture_point):
		fail("configuration");return
	capture_distance=_project(capture_point)
	var base: Dictionary=battle.ground_combat.select_march_base(path_index)
	if base.is_empty() or capture_distance<.05 or capture_distance>=float(base.baseDistance)-capture_radius or battle.ground_combat.route_point(path_index,capture_distance).distance_to(capture_point)>capture_radius*.25:
		fail("configuration")

func _current() -> bool:
	return enabled and is_instance_valid(battle) and generation==int(battle.battle_generation)

func _project(point: Vector2) -> float:
	var best: float=INF
	var result: float=0.0
	var points: Array=battle.paths[path_index].points
	var lengths: Array=battle.ground_combat.cumulative[path_index]
	for segment in range(points.size()-1):
		var start: Vector2=points[segment]
		var span: Vector2=points[segment+1]-start
		var fraction: float=clampf((point-start).dot(span)/maxf(.00000001,span.length_squared()),0.0,1.0)
		var separation: float=(start+span*fraction).distance_squared_to(point)
		if separation<best: best=separation;result=lerpf(float(lengths[segment]),float(lengths[segment+1]),fraction)
	return result

func start() -> void:
	if not _current() or started or failed: return
	started=true
	# Six ordinary, separately attackable bodies enter at the real road start.
	# Their HP, speed, armor, reward and contact attacks remain the normal kind.
	var recipe: Array[String]=["shield","raider","raider","shield","raider","raider"]
	for index in range(guard_required):
		var guard: Dictionary=battle._spawn_enemy(recipe[index%recipe.size()],1,{"pathIndex":path_index,"formationPattern":"formation","formationGroup":"advance:required-guards","formationRank":index/3,"formationLane":index%3-1})
		if guard.is_empty(): fail("configuration");return
		guard["advanceGuard"]=true
		guards.append(guard)

func apply_marching_goal(unit: Dictionary) -> void:
	if not _current() or int(unit.get("postPathIndex",-1))!=path_index: return
	# The regular front stands inside the enemy-facing capture edge, where
	# actual contact can intercept reinforcements before they contest it.
	# Required followups approach the center instead of stopping outside their
	# smaller arrival radius. Both use normal physical movement and stats.
	var edge: float=minf(.025,capture_radius*.35) if bool(unit.get("advanceFollowup",false)) else capture_radius*.95
	unit["routeMin"]=minf(float(unit.routeMax),maxf(float(unit.get("routeMin",0.0)),capture_distance-edge))
	unit["advanceMissionGoal"]=true

func friendly_goal_allowed(unit: Dictionary, point: Vector2) -> bool:
	if not _current() or not bool(unit.get("advanceMissionGoal",false)): return true
	return _project(point)>=float(unit.routeMin)-.000001

func marching_distance(unit: Dictionary) -> float:
	# The bent Stage02 road needs the actual body projection, not a virtual
	# cursor which advances while crowd spacing or a wall blocks the stride.
	return clampf(_project(unit.position),float(unit.routeMin),float(unit.routeMax))

func fail(reason: String) -> void:
	if not enabled or failed: return
	complete=false
	failed=true
	phase="failed"
	failure_reason=reason

func step(delta: float) -> void:
	if not _current() or failed: return
	if not started: start()
	if failed: return
	for objective in battle.objectives:
		if float(objective.get("hp",0))<=0: fail("base_lost");return
	# Arrival can precede the last attack cycle. Required soldiers remain
	# mortal until the entire battle ends, even after the local goal is met.
	for unit in followups:
		if float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)) or not is_same(battle.ground_combat._unit(int(unit.id)),unit):
			fail("followup_lost");return
	if complete: return
	guards_remaining=0
	for guard in guards:
		if float(guard.get("hp",0))>0:
			if not is_same(battle._enemy(int(guard.id)),guard): fail("configuration");return
			guards_remaining+=1
		elif bool(guard.get("escaped",false)):
			fail("guard_escaped");return
	occupied=false;contested=false
	for unit in battle.units:
		if float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)) or not GroundCombat.is_marching(str(unit.get("type",""))) or int(unit.get("postPathIndex",-1))!=path_index: continue
		if unit.position.distance_squared_to(capture_point)<=capture_radius*capture_radius: occupied=true;break
	for enemy in battle.enemies:
		if float(enemy.get("hp",0))<=0 or bool(enemy.get("escaped",false)) or bool(enemy.get("transportActive",false)): continue
		if enemy.position.distance_squared_to(capture_point)<=contest_radius*contest_radius: contested=true;break
	if not captured:
		phase="guards" if guards_remaining>0 else "capture"
		if guards_remaining==0 and occupied and not contested:
			hold_seconds=minf(hold_required,hold_seconds+maxf(0.0,delta))
		else: hold_seconds=0.0
		if hold_seconds>=hold_required-.0000001:
			captured=true
			phase="followup"
			battle._refresh_placement_hints()
	if captured:
		if followups.is_empty(): followups=battle._spawn_advance_followups(path_index,followup_required)
		for unit in followups:
			# A departed/dead required soldier cannot silently disappear from the
			# arrival condition and leave the player waiting for an impossible win.
			if float(unit.get("hp",0))<=0 or bool(unit.get("consumed",false)) or not is_same(battle.ground_combat._unit(int(unit.id)),unit):
				fail("followup_lost");return
			if unit.position.distance_squared_to(capture_point)<=arrival_radius*arrival_radius: arrived[int(unit.id)]=true
		if followups.size()==followup_required and arrived.size()==followup_required:
			complete=true;phase="complete"

func snapshot() -> Dictionary:
	if not enabled: return {}
	var awaiting_cycles: bool=complete and not battle._attack_cycles_cleared()
	var public_phase: String="await_cycles" if awaiting_cycles else phase
	var phase_ko: String={"guards":"수비병 격파","capture":"진지 점유","followup":"후속 병력 도착","await_cycles":"진격 임무 완료","complete":"진격 성공","failed":"진격 실패"}.get(public_phase,public_phase)
	var reason_ko: String={"base_lost":"아군 기지가 함락되었습니다.","followup_lost":"필수 후속 병력이 전사했습니다.","guard_escaped":"격파해야 할 적 병력이 아군 기지에 도달했습니다.","mission_failed":"진격 임무를 완료하지 못했습니다.","configuration":"진격 임무의 경로 또는 필수 병력을 확인할 수 없습니다."}.get(failure_reason,"")
	var ids: Array=[]
	for guard in guards: ids.append(int(guard.id))
	var followup_ids: Array=[]
	for unit in followups: followup_ids.append(int(unit.id))
	return {"phase":public_phase,"phaseKo":phase_ko,"awaitingCycles":awaiting_cycles,"progress":hold_seconds/hold_required,"holdProgress":hold_seconds/hold_required,"holdSeconds":hold_seconds,"holdRequiredSeconds":hold_required,"guardsRemaining":guards_remaining,"guardsRequired":guard_required,"guardIds":ids,"followupArrived":arrived.size(),"followupRequired":followup_required,"followupIds":followup_ids,"followupArrivedIds":arrived.keys(),"followupPendingSpawn":captured and followups.is_empty(),"occupied":occupied,"contested":contested,"captured":captured,"capturePoint":{"x":capture_point.x,"y":capture_point.y},"captureRadius":capture_radius,"contestRadius":contest_radius,"complete":complete,"failed":failed,"failureReason":failure_reason,"failureReasonKo":reason_ko}
