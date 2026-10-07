extends RefCounted
const UnitGrowth = preload("res://native/unit_growth.gd")
## Authored-route marching, stationary support and short land-only ambush sorties.
const GROUND_TYPES: Array = ["spear","samurai","naginata","monk","ninja","commander"]
const HEALTH: Dictionary = {"archer":105.0,"spear":140.0,"samurai":175.0,"naginata":135.0,"monk":125.0,"ninja":100.0,"commander":210.0,"gunner":105.0}
const CAPACITY: Dictionary = {"spear":2,"samurai":1,"naginata":2,"monk":1,"ninja":1,"commander":1,"gunner":1}
const REACH: Dictionary = {"spear":0.041,"samurai":0.034,"naginata":0.045,"monk":0.036,"ninja":0.031,"commander":0.042,"gunner":0.030}
# Original ninja meshes need about .100 of normalized head/weapon clearance
# at the widest actual Main field; retain perspective and edge tolerance.
const AMBUSH_MIN_FOOT_Y: float = .115
var battle: Node2D
var cumulative: Array = []
var march_bases: Array = []
var march_path_cursor: int = 0
var ambush_sites: Array = []
var water_rects: Array[Rect2] = []
var structure_segment_clear: Callable
var structure_placement_clear: Callable

static func is_ground(type_name: String) -> bool:
	return type_name in GROUND_TYPES

static func is_frontline(type_name: String) -> bool:
	return is_ground(type_name) or type_name=="gunner"

static func is_marching(type_name: String) -> bool:
	return type_name in ["spear","samurai","commander"]

static func is_ambush(type_name: String) -> bool:
	return type_name=="ninja"

static func placement_contract(type_name: String) -> Dictionary:
	if type_name=="archer":
		return {"deploymentKind":"placed","movementRoleKo":"배치형","placementRole":"ranged","placementMode":"fixed_emplacement","combatRole":"ranged","roleKo":"고정 진지 사격","placementHintKo":"궁병은 황금색 사격 진지에만 배치합니다."}
	if type_name=="gunner":
		return {"deploymentKind":"placed","movementRoleKo":"배치형","placementRole":"ground","placementMode":"frontline_shooter","combatRole":"frontline_shooter","roleKo":"전선 고정 사격","placementHintKo":"철포병은 청록색 전선에 배치해 짧은 거리에서 고정 사격합니다."}
	if type_name=="ninja":
		return {"deploymentKind":"ambush","movementRoleKo":"기습형","placementRole":"ambush","placementMode":"concealed_ambush","combatRole":"ground","roleKo":"외곽 엄폐 · 근접 기습","placementHintKo":"닌자는 보라색 외곽 엄폐 지점에 배치합니다. 가까운 적을 기습한 뒤 원래 자리로 돌아옵니다.","markerColor":"b997ff"}
	if type_name=="monk":
		return {"deploymentKind":"support","movementRoleKo":"지원형","placementRole":"ground","placementMode":"frontline_support","combatRole":"support","roleKo":"고정 치료 · 아군 지원","placementHintKo":"승병은 청록색 지원 지점에서 아군을 치료합니다. 봉으로 공격하지 않습니다.","markerColor":"73e5d2"}
	if type_name=="naginata":
		return {"deploymentKind":"guard","movementRoleKo":"호위형","placementRole":"ground","placementMode":"emplacement_guard","combatRole":"guard","roleKo":"사격 진지 호위 · 장도 쓸기","placementHintKo":"장도병은 청록색 수비선에 배치합니다. 가까운 궁병·조총병을 호위하고 위험이 사라지면 원래 자리로 돌아옵니다.","markerColor":"73e5d2"}
	return {"deploymentKind":"marching","movementRoleKo":"전진형","placementRole":"marching","placementMode":"base_march","combatRole":"cavalry" if type_name=="commander" else "ground","roleKo":"기지 출진 · 기마 전진" if type_name=="commander" else "기지 출진 · 근접 전진","placementHintKo":"소집 주문 후 아군 기지에서 생산합니다. 짧게 집결한 뒤 적 진입구 방향으로 전진합니다."}

func bind(value: Node2D) -> void:
	battle=value

func reset() -> void:
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

func land_segment_safe(start: Vector2, end: Vector2, margin: float = .008) -> bool:
	if not start.is_finite() or not end.is_finite(): return false
	for water in water_rects:
		if _water_intersection(start,end,water.grow(margin)).x>=0: return false
	for obstacle in battle.config.get("obstacles",[]):
		if not bool(obstacle.get("blockPlacement",false)): continue
		var center: Vector2=battle._point(obstacle)
		if center.distance_to(Geometry2D.get_closest_point_to_segment(center,start,end))<=float(obstacle.get("r",0))+margin: return false
	return not structure_segment_clear.is_valid() or bool(structure_segment_clear.call(start,end,margin))

func land_route_safe(path_index: int, start_distance: float, end_distance: float) -> bool:
	var lower: float=minf(start_distance,end_distance)
	var upper: float=maxf(start_distance,end_distance)
	var previous: Vector2=route_point(path_index,lower)
	for distance in cumulative[path_index]:
		if float(distance)<=lower or float(distance)>=upper: continue
		var next: Vector2=route_point(path_index,float(distance))
		if not land_segment_safe(previous,next): return false
		previous=next
	return land_segment_safe(previous,route_point(path_index,upper))

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

func _march_position(unit: Dictionary, distance: float) -> Vector2:
	var path_index: int=int(unit.postPathIndex)
	var center: Vector2=route_point(path_index,distance)
	var next_point: Vector2=route_point(path_index,maxf(float(unit.routeMin),distance-.012))
	var forward: Vector2=next_point-center
	if forward.length_squared()<.0000001: forward=center-route_point(path_index,minf(float(unit.routeMax),distance+.012))
	# Every recruit appears at the exact visible base. Formation separation
	# grows only during its actual first strides, without a sideways birth jump.
	var spread: float=clampf((float(unit.get("homeDistance",distance))-distance)/.030,0,1)
	var position: Vector2=center+forward.normalized().orthogonal()*float(unit.get("formationLane",0))*.009*spread
	if not land_segment_safe(position,position,.002): return center
	return position

func initialize_marching_unit(unit: Dictionary, base: Dictionary) -> void:
	unit.merge(placement_contract(str(unit.type)),true)
	unit["hp"]=max_health(unit)
	unit["maxHp"]=float(unit.hp)
	unit["blockCount"]=0
	unit["combatState"]="march"
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
	unit["mobilityFactor"]=1.0
	unit["capacityBonus"]=0
	unit["targetId"]=-1
	unit["formationLane"]=(int(unit.id)%3)-1
	unit["position"]=_march_position(unit,float(unit.routeDistance))
	unit["spawnPosition"]=unit.position
	var direction: Vector2=route_point(int(unit.postPathIndex),maxf(float(unit.routeMin),float(unit.routeDistance)-.025))-base.position
	unit["aim"]=direction.normalized() if direction.length_squared()>.000001 else Vector2.LEFT
	unit["animation"]="walk"

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
	unit.merge(placement_contract(str(unit.type)),true)
	unit["hp"]=max_health(unit)
	unit["maxHp"]=float(unit.hp)
	unit["blockCount"]=0
	unit["combatState"]="guard"
	unit["recoverRemaining"]=0.0
	unit["chargeCooldown"]=0.0
	unit["deploying"]=false
	unit["homePosition"]=unit.position
	if not is_frontline(str(unit.type)): return
	unit["postPathIndex"]=int(post.pathIndex)
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
	if is_ambush(str(unit.type)):
		unit["homeDistance"]=float(post.homeDistance)
		unit["routeDistance"]=float(post.homeDistance)
		unit["entryPosition"]=post.entryPosition
		unit["spawnPosition"]=unit.position
		unit["guardRadius"]=float(battle._stats(unit).range)
		var land: Vector2=_land_bounds(int(unit.postPathIndex),float(unit.homeDistance))
		unit["routeMin"]=maxf(float(unit.routeMin),land.x)
		unit["routeMax"]=minf(float(unit.routeMax),land.y)
		unit["combatState"]="ambush_wait"
		unit["onAmbushRoute"]=false
		unit["ambushStrikeDone"]=false
		unit["priorityTargetId"]=-1

func refresh_health(unit: Dictionary) -> void:
	var ratio: float=float(unit.get("hp",max_health(unit)))/maxf(1.0,float(unit.get("maxHp",max_health(unit))))
	unit["maxHp"]=max_health(unit)
	unit["hp"]=float(unit.maxHp)*ratio

func can_fight(unit: Dictionary) -> bool:
	return float(unit.get("hp",0))>0 and str(unit.get("combatState","guard")) in ["guard","gather","march","front","advance","engaged","charge","impact","ambush_wait","ambush_approach","guard_advance","guard_engaged","guard_dash"]

func active_support(unit: Dictionary) -> bool:
	return float(unit.get("hp",0))>0 and (not is_frontline(str(unit.type)) or can_fight(unit))

func _unit(id: int) -> Dictionary:
	for unit in battle.units:
		if int(unit.id)==id: return unit
	return {}

func _nearest_enemy(unit: Dictionary) -> Dictionary:
	var best: Dictionary={}
	var distance: float=INF
	var shooter: bool=str(unit.type)=="gunner"
	var search_range: float=float(battle._stats(unit).range)
	var marching: bool=is_marching(str(unit.type))
	for enemy in battle.enemies:
		if float(enemy.hp)<=0 or not shares_contact_front(unit,enemy) or not battle._enemy_visible(enemy) or battle._sailing_visual(enemy): continue
		if not shooter and not marching and int(enemy.get("blockedBy",-1))>=0 and int(enemy.blockedBy)!=int(unit.id): continue
		var route_distance: float=enemy_distance_for_unit(unit,enemy)
		if route_distance<float(unit.get("routeMin",0)) or route_distance>float(unit.routeMax): continue
		if marching:
			if route_distance>float(unit.routeDistance)+reach(unit): continue
		elif absf(route_distance-float(unit.homeDistance))>float(unit.guardRadius): continue
		var candidate: float=unit.position.distance_to(enemy.position)
		if candidate<=search_range and candidate<distance: distance=candidate;best=enemy
	return best

func _set_animation(unit: Dictionary, state: String) -> void:
	if str(unit.get("animation","idle"))!=state:
		unit["animation"]=state
		unit["animationClock"]=0.0

func _walk(unit: Dictionary, target_distance: float, delta: float, factor: float=1.0) -> bool:
	if not is_marching(str(unit.type)): return false
	var desired: float=clampf(minf(target_distance,float(unit.routeDistance)),float(unit.routeMin),float(unit.routeMax))
	# Three narrow columns follow the same authored route. Same-column
	# arrivals queue at the base rather than pinning each other in place.
	for ally in battle.units:
		if int(ally.id)==int(unit.id) or not is_marching(str(ally.type)) or float(ally.get("hp",0))<=0 or int(ally.postPathIndex)!=int(unit.postPathIndex) or int(ally.get("formationLane",0))!=int(unit.get("formationLane",0)): continue
		if str(unit.type)=="commander" and str(ally.get("animation","idle"))=="walk": continue
		var gap: float=float(unit.routeDistance)-float(ally.routeDistance)
		if gap<-.000001 or (absf(gap)<.000001 and int(ally.id)>int(unit.id)): continue
		desired=minf(float(unit.routeDistance),maxf(desired,float(ally.routeDistance)+.026))
	var speed_value: float=(.065 if str(unit.type)=="commander" else .052 if str(unit.type)=="ninja" else .042)*float(unit.mobilityFactor)*factor*1.4
	if str(unit.get("combatState",""))=="march" and int(unit.get("gatherGroupId",0))>0:
		for ally in battle.units:
			if int(ally.get("gatherGroupId",0))==int(unit.gatherGroupId) and str(ally.get("combatState",""))=="march" and float(ally.get("hp",0))>0:
				speed_value=minf(speed_value,(.065 if str(ally.type)=="commander" else .042)*float(ally.mobilityFactor)*1.4)
	var previous: Vector2=unit.position
	unit["routeDistance"]=move_toward(float(unit.routeDistance),desired,speed_value*delta)
	unit["position"]=_march_position(unit,float(unit.routeDistance))
	var direction: Vector2=unit.position-previous
	if direction.length_squared()>.000000001:
		unit["aim"]=direction.normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")
	return absf(float(unit.routeDistance)-desired)<.0001

func _on_unit_injured(unit: Dictionary) -> void:
	if float(unit.get("hp",0))<=0:
		unit["combatState"]="dead"
		unit["attackPlan"]={}
		unit["targetId"]=-1
		unit["blockCount"]=0

func step(delta: float) -> void:
	for unit in battle.units:
		if not is_frontline(str(unit.type)): continue
		unit["chargeCooldown"]=maxf(0,float(unit.get("chargeCooldown",0))-delta*battle.unit_skills.cavalry_charge_factor(unit))
		if is_ambush(str(unit.type)):
			if float(unit.hp)<=0: _on_unit_injured(unit);continue
			_ambush_step(unit,delta)
			continue
		if is_marching(str(unit.type)):
			if float(unit.hp)<=0: _on_unit_injured(unit);continue
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

func _gather_step(unit: Dictionary, delta: float) -> void:
	unit["gatherRemaining"]=maxf(0,float(unit.get("gatherRemaining",2.5))-delta)
	var group: Array=[]
	for ally in battle.units:
		if is_marching(str(ally.type)) and float(ally.get("hp",0))>0 and str(ally.get("combatState",""))=="gather" and int(ally.postPathIndex)==int(unit.postPathIndex): group.append(ally)
	if group.size()<2 and float(unit.gatherRemaining)>0 and _nearest_enemy(unit).is_empty(): return
	var group_id: int=int(unit.id)
	for ally in group: group_id=mini(group_id,int(ally.id))
	for ally in group:
		ally["gatherGroupId"]=group_id
		ally["gatherRemaining"]=0.0
		ally["combatState"]="march"
		_set_animation(ally,"walk")

func _guard_target(unit: Dictionary) -> Dictionary:
	var best: Dictionary={}
	var nearest: float=INF
	var radius: float=maxf(float(unit.guardRadius),float(battle._stats(unit).range))
	for enemy in battle.enemies:
		if float(enemy.hp)<=0 or int(enemy.pathIndex)!=int(unit.postPathIndex) or battle._sailing_visual(enemy) or not battle._enemy_visible(enemy): continue
		if unit.homePosition.distance_to(enemy.position)>radius or not land_segment_safe(unit.homePosition,enemy.position): continue
		var distance: float=unit.position.distance_to(enemy.position)
		if distance<nearest: nearest=distance;best=enemy
	return best

func _guard_walk(unit: Dictionary, destination: Vector2, delta: float, factor: float = 1.0) -> bool:
	var radius: float=maxf(float(unit.guardRadius),float(battle._stats(unit).range))
	var offset: Vector2=destination-unit.homePosition
	var desired: Vector2=unit.homePosition+offset.limit_length(radius)
	var previous: Vector2=unit.position
	var next: Vector2=previous.move_toward(desired,.042*1.4*float(unit.mobilityFactor)*factor*delta)
	if not land_segment_safe(previous,next): return false
	unit.position=next
	var direction: Vector2=next-previous
	if direction.length_squared()>.000000001:
		unit.aim=direction.normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")
	return next.distance_squared_to(desired)<.00000001

func _guard_step(unit: Dictionary, delta: float) -> void:
	if float(unit.get("hp",0))<=0: _on_unit_injured(unit);return
	if str(unit.get("animation","idle"))=="attack": return
	var target: Dictionary=_guard_target(unit)
	var dash: Dictionary=unit.get("guardDashData",{})
	if target.is_empty():
		if not dash.is_empty(): battle.unit_skills.finish_guard_dash(unit,false);unit.guardDashData={}
		unit.targetId=-1
		unit.combatState="guard_return"
		if _guard_walk(unit,unit.homePosition,delta): unit.combatState="guard";_set_animation(unit,"idle")
		return
	unit.targetId=int(target.id)
	var distance: float=unit.position.distance_to(target.position)
	if dash.is_empty() and distance>reach(unit):
		dash=battle.unit_skills.guard_dash(unit,target)
		if bool(dash.get("active",false)): unit.guardDashData=dash
		else: dash={}
	if distance>reach(unit)*.95:
		unit.combatState="guard_dash" if not dash.is_empty() else "guard_advance"
		var desired: Vector2=target.position+(unit.position-target.position).normalized()*reach(unit)*.5
		_guard_walk(unit,desired,delta,float(dash.get("speedFactor",1.0)))
		return
	unit.aim=(target.position-unit.position).normalized()
	unit.combatState="guard_engaged"
	_set_animation(unit,"idle")
	if not dash.is_empty():
		var stats: Dictionary=battle._stats(unit)
		unit.animation="attack"
		unit.animationClock=0.0
		unit.attackDuration=battle._animation_duration("attack")
		unit.cooldown=float(stats.interval)
		var plan: Dictionary=battle.unit_skills.prepare_attack(unit,target,float(stats.damage)*float(dash.get("damageFactor",1.0)),battle._impact_time("naginata"))
		plan["guardDash"]=true
		plan["skillId"]=str(dash.get("skillId","naginata_mana_dash"))
		plan["effectKind"]="dash"
		unit.attackPlan=plan

func _ambush_enemy(unit: Dictionary) -> Dictionary:
	var priority: Dictionary=battle._enemy(int(unit.get("priorityTargetId",-1)))
	if not priority.is_empty() and float(priority.hp)>0 and bool(priority.get("fortification",false)) and int(priority.pathIndex)==int(unit.postPathIndex) and unit.homePosition.distance_to(priority.position)<=float(battle._stats(unit).range)*2.0:
		var distance: float=enemy_distance(priority)
		if distance>=float(unit.routeMin) and distance<=float(unit.routeMax): return priority
	if int(unit.get("priorityTargetId",-1))>=0: return {}
	var best: Dictionary={}
	var nearest: float=INF
	for enemy in battle.enemies:
		if float(enemy.hp)<=0 or int(enemy.pathIndex)!=int(unit.postPathIndex) or not battle._enemy_visible(enemy) or battle._sailing_visual(enemy): continue
		var distance: float=enemy_distance(enemy)
		if distance<float(unit.routeMin) or distance>float(unit.routeMax): continue
		var from_home: float=unit.homePosition.distance_to(enemy.position)
		if from_home>float(unit.guardRadius): continue
		if from_home<nearest: nearest=from_home;best=enemy
	return best

func _ambush_walk_point(unit: Dictionary, target: Vector2, delta: float) -> bool:
	var previous: Vector2=unit.position
	var next: Vector2=previous.move_toward(target,.052*1.4*float(unit.mobilityFactor)*delta)
	if not land_segment_safe(previous,next): return false
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
	var next: Vector2=route_point(int(unit.postPathIndex),distance)
	if not land_segment_safe(previous,next): return false
	unit["routeDistance"]=distance
	unit["position"]=next
	if next.distance_squared_to(previous)>.000000001:
		unit["aim"]=(next-previous).normalized()
		_set_animation(unit,"walk")
		battle._track_footstep(unit,previous,"friendly")
	else: _set_animation(unit,"idle")
	return absf(distance-desired)<.0001

func _ambush_step(unit: Dictionary, delta: float) -> void:
	if str(unit.get("animation","idle"))=="attack": return
	if bool(unit.get("ambushStrikeDone",false)): unit["combatState"]="ambush_return"
	if str(unit.combatState)=="ambush_return":
		unit["targetId"]=-1
		unit["attackPlan"]={}
		if bool(unit.onAmbushRoute):
			if _ambush_walk_route(unit,float(unit.homeDistance),delta): unit["onAmbushRoute"]=false
			return
		if _ambush_walk_point(unit,unit.homePosition,delta):
			unit["combatState"]="ambush_wait"
			unit["ambushStrikeDone"]=false
			unit["priorityTargetId"]=-1
			unit["routeDistance"]=float(unit.homeDistance)
			_set_animation(unit,"idle")
		return
	var target: Dictionary=_ambush_enemy(unit)
	if target.is_empty():
		unit["targetId"]=-1
		if unit.position.distance_squared_to(unit.homePosition)>.00000001: unit["combatState"]="ambush_return"
		else: unit["combatState"]="ambush_wait";_set_animation(unit,"idle")
		return
	unit["targetId"]=int(target.id)
	unit["combatState"]="ambush_approach"
	if not bool(unit.onAmbushRoute):
		if _ambush_walk_point(unit,unit.entryPosition,delta): unit["onAmbushRoute"]=true
		return
	if unit.position.distance_to(target.position)>reach(unit)*.95:
		var distance: float=enemy_distance(target)
		var desired: float=distance+reach(unit)*.5 if float(unit.routeDistance)>=distance else distance-reach(unit)*.5
		_ambush_walk_route(unit,desired,delta)
		return
	unit["aim"]=(target.position-unit.position).normalized()
	unit["combatState"]="engaged"
	_set_animation(unit,"idle")

func _marching_step(unit: Dictionary, delta: float) -> void:
	if str(unit.get("animation","idle"))=="attack":
		if str(unit.combatState)!="impact": unit["combatState"]="engaged"
		return
	var target: Dictionary=_nearest_enemy(unit)
	if target.is_empty():
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
		_walk(unit,enemy_distance_for_unit(unit,target)+reach(unit)*.4,delta,1.35 if charging else 1.0)
		return
	unit["aim"]=(target.position-unit.position).normalized()
	if charging:
		unit["combatState"]="impact"
		unit["animation"]="attack"
		unit["animationClock"]=0.0
		unit["attackDuration"]=battle._animation_duration("attack")
		unit["chargeCooldown"]=float(battle._stats(unit).interval)*6.0
		unit["cooldown"]=float(battle._stats(unit).interval)
		unit["attackPlan"]=battle.unit_skills.prepare_attack(unit,target,float(battle._stats(unit).damage)*2.2,battle._impact_time("commander"),true)
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

func _assign_blocks() -> void:
	for unit in battle.units: unit["blockCount"]=0
	for enemy in battle.enemies:
		var previous_blocker: int=int(enemy.get("blockedBy",-1))
		var defender: Dictionary=_unit(previous_blocker)
		if defender.is_empty() or not can_fight(defender) or not battle.can_enemy_engage_unit(enemy,defender,true) or float(enemy.hp)<=0 or battle._sailing_visual(enemy) or not shares_contact_front(defender,enemy) or defender.position.distance_to(enemy.position)>reach(defender)*1.05:
			enemy["blockedBy"]=-1
			if previous_blocker>=0: enemy["counterPlan"]={}
		else: defender["blockCount"]=int(defender.blockCount)+1
	for enemy in battle.enemies:
		if int(enemy.get("blockedBy",-1))>=0 or float(enemy.hp)<=0 or battle._sailing_visual(enemy): continue
		for defender in battle.units:
			if not is_frontline(str(defender.type)) or not can_fight(defender) or not battle.can_enemy_engage_unit(enemy,defender,true) or int(defender.blockCount)>=capacity(defender): continue
			if not shares_contact_front(defender,enemy) or enemy.position.distance_to(defender.position)>reach(defender): continue
			enemy["blockedBy"]=int(defender.id)
			defender["blockCount"]=int(defender.blockCount)+1
			break

func blocked(enemy: Dictionary) -> bool:
	var unit: Dictionary=_unit(int(enemy.get("blockedBy",-1)))
	return not unit.is_empty() and can_fight(unit) and battle.can_enemy_engage_unit(enemy,unit,true) and shares_contact_front(unit,enemy) and unit.position.distance_to(enemy.position)<=reach(unit)*1.05

func counterattack(enemy: Dictionary, delta: float, target: Dictionary = {}) -> void:
	var unit: Dictionary=target if not target.is_empty() else _unit(int(enemy.get("blockedBy",-1)))
	if not battle.can_enemy_engage_unit(enemy,unit,true):
		enemy["counterPlan"]={}
		return
	battle._turn_enemy(enemy,unit.position-enemy.position,delta)
	enemy["attackCooldown"]=maxf(0,float(enemy.get("attackCooldown",0))-delta)
	var plan: Dictionary=enemy.get("counterPlan",{})
	if not plan.is_empty() and int(plan.get("targetId",int(unit.id)))!=int(unit.id): enemy.counterPlan={};plan={}
	if not plan.is_empty() and float(enemy.animationClock)>=float(plan.releaseTime):
		battle._combat_event("shot",enemy,unit)
		battle._damage_friendly(unit,float(plan.damage),enemy)
		enemy["counterPlan"]={}
	if float(unit.get("hp",0))<=0: return
	if float(enemy.attackCooldown)<=0:
		enemy["animation"]="attack"
		enemy["animationClock"]=0.0
		enemy["attackCooldown"]=1.1 if str(enemy.get("originKind",enemy.kind)) in ["heavy","commander"] else .95
		enemy["counterPlan"]={"targetId":int(unit.id),"releaseTime":.25,"damage":(4.0+float(enemy.get("counterWave",battle.wave))*.6)*float(enemy.damage)}
	elif str(enemy.animation)=="attack" and float(enemy.animationClock)>=.5:
		enemy["animation"]="idle"
		enemy["animationClock"]=0.0

func attack_target(unit: Dictionary) -> Dictionary:
	if str(unit.type)=="monk": return {}
	if not can_fight(unit): return {}
	if is_ambush(str(unit.type)) and (str(unit.combatState)!="engaged" or bool(unit.get("ambushStrikeDone",false))): return {}
	var shooter: bool=str(unit.type)=="gunner"
	if shooter and str(unit.get("animation","idle"))=="walk": return {}
	var hit_range: float=float(battle._stats(unit).range) if shooter else reach(unit)
	var best: Dictionary={}
	var progress: float=-1
	for enemy in battle.enemies:
		if float(enemy.hp)<=0 or not shares_contact_front(unit,enemy) or not battle._enemy_visible(enemy) or battle._sailing_visual(enemy): continue
		if unit.position.distance_to(enemy.position)>hit_range: continue
		if not land_segment_safe(unit.position,enemy.position): continue
		var distance: float=enemy_distance_for_unit(unit,enemy)
		if shooter and (distance<float(unit.get("routeMin",0)) or distance>float(unit.routeMax) or absf(distance-float(unit.homeDistance))>float(unit.guardRadius)): continue
		if distance>progress: best=enemy;progress=distance
	return best

func stance(unit: Dictionary) -> String:
	if is_ambush(str(unit.type)):
		return {"ambush_wait":"엄폐 기습 대기","ambush_approach":"엄폐에서 기습 접근","engaged":"단검 기습","ambush_return":"원래 엄폐 지점 복귀","dead":"전사"}.get(str(unit.get("combatState","ambush_wait")),"기습 준비")
	if str(unit.type)=="monk": return "고정 치료 · 아군 지원" if float(unit.get("hp",0))>0 else "전사"
	if str(unit.type)=="naginata":
		return {"guard":"사격 진지 호위 대기","guard_advance":"수비선 안 접근","guard_engaged":"호위선 쓸기","guard_dash":"마나 돌진","guard_return":"원래 호위점 복귀","dead":"전사"}.get(str(unit.get("combatState","guard")),"호위 준비")
	if str(unit.type)=="gunner":
		return {"guard":"전선 사격 대기","advance":"사격 거리 접근","engaged":"정지 사격","return":"방어 지점 복귀","retreat":"부상 후퇴","recover":"회복 중"}.get(str(unit.get("combatState","guard")),"대기")
	if not is_ground(str(unit.type)): return "고정 진지 사격"
	return {"gather":"기지 집결 · 최대 2.5초","march":"적 진입구로 진군","front":"전방 교전 대기","advance":"적에게 접근","engaged":"근접 교전","charge":"돌격 중","impact":"돌격 타격","dead":"전사"}.get(str(unit.get("combatState","march")),"진군 준비")

func cease_combat() -> void:
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
			unit["combatState"]="ambush_return" if unit.position.distance_squared_to(unit.homePosition)>.00000001 else "ambush_wait"
		elif is_frontline(str(unit.type)) and str(unit.combatState)!="recover":
			unit["combatState"]="guard"
	for enemy in battle.enemies:
		enemy["blockedBy"]=-1
		enemy["counterPlan"]={}
