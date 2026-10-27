extends RefCounted
## Per-step spatial candidates and soft spacing. No pairing owns an enemy.
const CELL: float = .08
const BODY_GAP: float = .014
var friends: Dictionary = {}
var hostiles: Dictionary = {}
var friend_cells: Dictionary = {}
var enemy_cells: Dictionary = {}
var target_load: Dictionary = {}
var profiling_enabled: bool = false
var profile: Dictionary = {}
var friend_slots: Dictionary={}
var enemy_slots: Dictionary={}
var friend_actor_cells: Dictionary={}
var enemy_actor_cells: Dictionary={}
var motion_revision: int=0
var _cell_candidates: Dictionary={}
const CELL_CANDIDATE_CACHE_LIMIT: int=256

func set_profiling_enabled(value: bool) -> void:
	profiling_enabled=value
	profile.clear()

func performance_snapshot(reset_counts: bool = false) -> Dictionary:
	var result: Dictionary=profile.duplicate()
	if reset_counts: profile.clear()
	return result

func _count(key: String, amount: int = 1) -> void:
	if profiling_enabled: profile[key]=int(profile.get(key,0))+amount

func clear() -> void:
	friends.clear()
	hostiles.clear()
	friend_cells.clear()
	enemy_cells.clear()
	target_load.clear()
	friend_slots.clear();enemy_slots.clear();friend_actor_cells.clear();enemy_actor_cells.clear();_cell_candidates.clear()
	motion_revision+=1

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/CELL),floori(point.y/CELL))

func _insert(actor: Dictionary, index: Dictionary, cells: Dictionary) -> void:
	var id: int = int(actor.id)
	index[id] = actor
	var key: Vector2i = _cell(actor.position)
	if is_same(index,friends): friend_actor_cells[id]=key
	else: enemy_actor_cells[id]=key
	if not cells.has(key): cells[key] = []
	cells[key].append(id)

func rebuild(allies: Array, enemies: Array, preserve_target_load: bool = false) -> void:
	var previous_load: Dictionary=target_load.duplicate() if preserve_target_load else {}
	clear()
	target_load=previous_load
	for slot in range(allies.size()):
		var actor: Dictionary=allies[slot]
		if float(actor.get("hp",0))>0 and not bool(actor.get("consumed",false)):
			_insert(actor,friends,friend_cells);friend_slots[int(actor.id)]=slot
	for slot in range(enemies.size()):
		var actor: Dictionary=enemies[slot]
		if float(actor.get("hp",0))>0:
			_insert(actor,hostiles,enemy_cells);enemy_slots[int(actor.id)]=slot

func nearby(point: Vector2, radius: float, friendly: bool, include_inactive: bool = false) -> Array:
	if profiling_enabled: _count("nearbyQueries")
	var cells: Dictionary=friend_cells if friendly else enemy_cells
	var index: Dictionary=friends if friendly else hostiles
	var first: Vector2i=_cell(point-Vector2.ONE*radius)
	var last: Vector2i=_cell(point+Vector2.ONE*radius)
	var key: String="%d:%d:%d:%d:%d" % [1 if friendly else 0,first.x,first.y,last.x,last.y]
	var candidates: Array=_cell_candidates.get(key,[])
	if not _cell_candidates.has(key):
		for x in range(first.x,last.x+1):
			for y in range(first.y,last.y+1): candidates.append_array(cells.get(Vector2i(x,y),[]))
		if _cell_candidates.size()>=CELL_CANDIDATE_CACHE_LIMIT: _cell_candidates.clear()
		_cell_candidates[key]=candidates
	var found: Array=[]
	var radius_squared: float=radius*radius
	if profiling_enabled: _count("candidateChecks",candidates.size())
	# Only cell membership is cached. HP, consumption and exact positions are
	# read on every query, including moves which remain inside one cell.
	for id in candidates:
		var actor: Dictionary=index.get(int(id),{})
		if not actor.is_empty() and (include_inactive or (float(actor.get("hp",0))>0 and not bool(actor.get("consumed",false)))) and point.distance_squared_to(actor.position)<=radius_squared: found.append(actor)
	return found

func moved(actor: Dictionary, previous: Vector2, friendly: bool) -> void:
	if actor.position!=previous: motion_revision+=1
	var cells: Dictionary = friend_cells if friendly else enemy_cells
	var index: Dictionary = friends if friendly else hostiles
	if not index.has(int(actor.id)): return
	var actor_cells: Dictionary=friend_actor_cells if friendly else enemy_actor_cells
	# A mutating callback may already have rebuilt this actor at its new
	# position before the outer movement caller finishes the same stride.
	var old_key: Vector2i=actor_cells.get(int(actor.id),_cell(previous))
	var key: Vector2i = _cell(actor.position)
	if old_key==key: return
	_cell_candidates.clear()
	actor_cells[int(actor.id)]=key
	if cells.has(old_key):
		cells[old_key].erase(int(actor.id))
		if cells[old_key].is_empty(): cells.erase(old_key)
	if not cells.has(key): cells[key] = []
	cells[key].append(int(actor.id))

func pressure(point: Vector2, actor_id: int, friendly: bool) -> float:
	return pressure_from(point,actor_id,nearby(point,BODY_GAP*1.8,friendly))

func pressure_from(point: Vector2, actor_id: int, candidates: Array) -> float:
	if profiling_enabled: _count("pressureEvaluations")
	var value: float=0.0
	for other in candidates:
		if int(other.id)==actor_id or float(other.get("hp",0.0))<=0.0 or bool(other.get("consumed",false)): continue
		var distance_squared: float=point.distance_squared_to(other.position)
		if distance_squared<BODY_GAP*BODY_GAP: value+=BODY_GAP-sqrt(distance_squared)
	return value

func _encounter_root(parents: Dictionary, node: String) -> String:
	var root: String=node
	while str(parents[root])!=root: root=str(parents[root])
	while str(parents[node])!=node:
		var next: String=str(parents[node])
		parents[node]=root
		node=next
	return root

func _encounter_join(parents: Dictionary, first: String, second: String) -> void:
	if not parents.has(first): parents[first]=first
	if not parents.has(second): parents[second]=second
	var a: String=_encounter_root(parents,first)
	var b: String=_encounter_root(parents,second)
	if a!=b:
		if a<b: parents[b]=a
		else: parents[a]=b

func _encounter_pair(parents: Dictionary, pairs: Dictionary, territories: Dictionary, checked: Dictionary, ally: Dictionary, enemy: Dictionary, allowed: Callable, sector: Callable) -> void:
	var contact: String="%d:%d" % [int(ally.id),int(enemy.id)]
	if checked.has(contact): return
	checked[contact]=true
	# No movement or signals occur while this graph is built. Reject cheap
	# role/state failures before projecting a pair onto its territorial route.
	if not bool(allowed.call(ally,enemy)): return
	var location: Dictionary=sector.call(ally,enemy)
	var bucket: String=str(location.bucket)
	var pair_key: String=bucket+"|%d:%d" % [int(ally.id),int(enemy.id)]
	if pairs.has(pair_key): return
	var ally_node: String=bucket+"|a"+str(ally.id)
	var enemy_node: String=bucket+"|e"+str(enemy.id)
	_encounter_join(parents,ally_node,enemy_node)
	pairs[pair_key]=ally_node
	territories[bucket]=str(location.territory)

func local_encounters(radius: float, allowed: Callable, committed_links: Array, sector: Callable) -> Dictionary:
	# A soldier may border two sectors, but each real attack pair has exactly
	# one sector. Nodes in different sectors never union through a long column.
	var parents: Dictionary={}
	var pairs: Dictionary={}
	var territories: Dictionary={}
	var checked: Dictionary={}
	for enemy in hostiles.values():
		if float(enemy.get("hp",0.0))<=0.0 or bool(enemy.get("escaped",false)): continue
		for ally in nearby(enemy.position,radius,true):
			_encounter_pair(parents,pairs,territories,checked,ally,enemy,allowed,sector)
	for link in committed_links:
		var ally: Dictionary=friends.get(int(link[0]),{})
		var enemy: Dictionary=hostiles.get(int(link[1]),{})
		if not ally.is_empty() and not enemy.is_empty(): _encounter_pair(parents,pairs,territories,checked,ally,enemy,allowed,sector)
	var owners: Dictionary={}
	var members: Dictionary={}
	var group_territories: Dictionary={}
	for node in parents:
		var root: String=_encounter_root(parents,str(node))
		owners[node]=root
		if not members.has(root): members[root]=[]
		members[root].append(node)
		group_territories[root]=territories[str(node).get_slice("|",0)]
	for pair_key in pairs: pairs[pair_key]=owners[pairs[pair_key]]
	return {"owners":owners,"members":members,"pairs":pairs,"territories":group_territories}

func melee_goal_pressure(point: Vector2, actor_id: int, target_id: int, candidates: Array, target_position: Vector2, friendly: bool = false) -> float:
	var value: float=pressure_from(point,actor_id,candidates)
	# These are spatial approach points, never exclusive victims or attack
	# rights. Both sides must see an approaching neighbor's intended contact
	# point before its body arrives, or a whole column chooses the same gap.
	# Existing stationary attackers contribute their actual bodies above.
	for other in candidates:
		if int(other.id)==actor_id or float(other.get("hp",0.0))<=0.0 or bool(other.get("consumed",false)) or str(other.get("animation",""))=="attack": continue
		var offset: Vector2
		if friendly:
			if str(other.get("combatState","")) not in ["advance","charge","guard_advance","support_advance"] or int(other.get("targetId",-1))!=target_id or int(other.get("meleeGoalTargetId",-1))!=target_id or not other.has("meleeGoalOffset"): continue
			offset=other.meleeGoalOffset
		else:
			if not bool(other.get("meleeApproachActive",false)) or int(other.get("meleeApproachTargetId",-1))!=target_id or not other.has("meleeApproachOffset"): continue
			offset=other.meleeApproachOffset
		var goal: Vector2=target_position+offset
		if other.position.distance_squared_to(goal)<=BODY_GAP*BODY_GAP*.25: continue
		var distance_squared: float=point.distance_squared_to(goal)
		if distance_squared<BODY_GAP*BODY_GAP: value+=BODY_GAP-sqrt(distance_squared)
	return value

func melee_goal_pressure_points(actor_id: int, target_id: int, candidates: Array, target_position: Vector2, friendly: bool = false) -> Array[Vector2]:
	# One synchronous twelve-slot search reads the same bodies and intended
	# goals repeatedly. Copy only those positions once, in the original sum
	# order (all bodies, then all goals); never retain them across searches.
	var points: Array[Vector2]=[]
	for other in candidates:
		if int(other.id)==actor_id or float(other.get("hp",0.0))<=0.0 or bool(other.get("consumed",false)): continue
		points.append(other.position)
	for other in candidates:
		if int(other.id)==actor_id or float(other.get("hp",0.0))<=0.0 or bool(other.get("consumed",false)) or str(other.get("animation",""))=="attack": continue
		var offset: Vector2
		if friendly:
			if str(other.get("combatState","")) not in ["advance","charge","guard_advance","support_advance"] or int(other.get("targetId",-1))!=target_id or int(other.get("meleeGoalTargetId",-1))!=target_id or not other.has("meleeGoalOffset"): continue
			offset=other.meleeGoalOffset
		else:
			if not bool(other.get("meleeApproachActive",false)) or int(other.get("meleeApproachTargetId",-1))!=target_id or not other.has("meleeApproachOffset"): continue
			offset=other.meleeApproachOffset
		var goal: Vector2=target_position+offset
		if other.position.distance_squared_to(goal)<=BODY_GAP*BODY_GAP*.25: continue
		points.append(goal)
	return points

func pressure_at_points(point: Vector2, points: Array[Vector2]) -> float:
	if profiling_enabled: _count("pressureEvaluations")
	var value: float=0.0
	for occupied in points:
		var distance_squared: float=point.distance_squared_to(occupied)
		if distance_squared<BODY_GAP*BODY_GAP: value+=BODY_GAP-sqrt(distance_squared)
	return value

func _remember_steer(actor: Dictionary, goal: Vector2, side: float, heading: Vector2) -> void:
	actor["crowdSteerGoal"]=goal
	actor["crowdSteerTargetId"]=int(actor.get("meleeApproachTargetId",-1)) if bool(actor.get("meleeApproachActive",false)) else int(actor.get("targetId",-1))
	actor["crowdSteerHeading"]=heading
	if absf(side)>.5: actor["crowdSteerSide"]=side

func move_point(actor: Dictionary, desired: Vector2, friendly: bool, legal: Callable, approach_goal: Vector2 = Vector2(INF,INF), allow_detour: bool = false) -> Vector2:
	var contact: bool=not friendly and allow_detour and approach_goal.is_finite() and bool(actor.get("meleeApproachActive",false))
	var steer: bool=friendly or contact
	var target_id: int=int(actor.get("meleeApproachTargetId",-1)) if contact else int(actor.get("targetId",-1))
	var origin: Vector2 = actor.position
	var stride: float = origin.distance_to(desired)
	if stride<.0000001: return origin
	if profiling_enabled: _count("movementQueries")
	# Every candidate is at most stride from origin. Actors outside this
	# single neighborhood cannot contribute pressure at any candidate.
	var neighbors: Array=nearby(origin,BODY_GAP+stride+.0000001,friendly)
	var direction: Vector2 = (desired-origin).normalized()
	var best: Vector2 = origin
	var goal: Vector2=approach_goal if approach_goal.is_finite() else desired
	var goal_distance: float=origin.distance_to(goal)
	var return_checkpoint: bool=friendly and approach_goal.is_finite() and str(actor.get("combatState",""))=="support_return" and goal_distance<=BODY_GAP*2.0
	var current_pressure: float=pressure_from(origin,int(actor.id),neighbors)
	var score: float = origin.distance_to(goal)+current_pressure*4.0
	var detour: Vector2=origin
	var detour_score: float=INF
	var best_side: float=0.0
	var detour_side: float=0.0
	# At an exact shared spawn, deterministic side steps make room gradually.
	var sign_value: float = -1.0 if int(actor.id)%2==0 else 1.0
	var previous_heading: Vector2=Vector2.ZERO
	if steer and int(actor.get("crowdSteerTargetId",-2))==target_id and (actor.get("crowdSteerGoal",goal) as Vector2).distance_to(goal)<=BODY_GAP:
		sign_value=float(actor.get("crowdSteerSide",sign_value))
		previous_heading=actor.get("crowdSteerHeading",Vector2.ZERO)
	for angle in [0.0,.55*sign_value,-.55*sign_value,1.1*sign_value,-1.1*sign_value,1.65*sign_value,-1.65*sign_value]:
		var candidate: Vector2 = origin+direction.rotated(float(angle))*stride
		# Continue an actual avoidance turn through intermediate directions.
		# A genuinely reversed destination may still request an immediate turn.
		var heading: Vector2=(candidate-origin).normalized()
		if previous_heading.length_squared()>.5 and previous_heading.dot(direction)>-.5 and previous_heading.dot(heading)<-.2: continue
		var candidate_distance: float=candidate.distance_to(goal)
		# Near a fixed return checkpoint, keep converging even when pressure
		# comes from neighbors beside the goal. Farther away retain detours.
		if return_checkpoint and candidate_distance>=goal_distance-.00000001: continue
		var candidate_pressure: float=pressure_from(candidate,int(actor.id),neighbors)
		var candidate_score: float = candidate_distance+candidate_pressure*4.0
		var side: float=signf(float(angle))
		# Keep an already chosen avoidance side through tiny pressure changes.
		# A clearly better/legal opposite side still wins. Scale by this actual
		# stride, not frame count or a movement pause/cooldown.
		if steer and side*sign_value<0.0: candidate_score+=stride*.25
		var improves: bool=candidate_score<score-.00000001
		var improves_detour: bool=allow_detour and candidate_pressure<=current_pressure+.00000001 and candidate_score<detour_score
		if not improves and not improves_detour: continue
		if profiling_enabled: _count("movementLegalityChecks")
		if not bool(legal.call(origin,candidate)): continue
		if improves:
			best=candidate;score=candidate_score;best_side=side
			# With no body pressure, a legal step directly toward the goal is
			# already the distance minimum among every equal-length candidate.
			if float(angle)==0.0 and candidate_pressure<=.00000001 and direction.dot((goal-origin).normalized())>.999999:
				if steer: _remember_steer(actor,goal,sign_value,heading)
				return candidate
		if improves_detour:
			detour=candidate
			detour_score=candidate_score
			detour_side=side
	# A rear marcher may need a short lateral/backward step to go around a
	# stopped ally. The step keeps the same speed and must not worsen crowding.
	if allow_detour and best==origin and detour!=origin:
		# A contact destination occupied by an ally has no usable last step.
		# Retrying sideways/backwards here produces a perpetual orbit. Wait at
		# the physical spacing boundary; a new/free goal resumes immediately.
		var occupied_goal: bool=steer and approach_goal.is_finite() and goal_distance<=BODY_GAP*2.0 and pressure(goal,int(actor.id),friendly)>.00000001
		if occupied_goal or return_checkpoint:
			if profiling_enabled: _count("occupiedGoalWaits")
			return origin
		if profiling_enabled: _count("detourSteps")
		if steer: _remember_steer(actor,goal,detour_side if absf(detour_side)>.5 else sign_value,(detour-origin).normalized())
		return detour
	if steer and best!=origin: _remember_steer(actor,goal,best_side if absf(best_side)>.5 else sign_value,(best-origin).normalized())
	return best

func claim_target(enemy_id: int) -> void:
	target_load[enemy_id] = int(target_load.get(enemy_id,0))+1

func target_penalty(enemy_id: int) -> float:
	return minf(.08,float(target_load.get(enemy_id,0))*.012)
