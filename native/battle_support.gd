extends RefCounted
## Battle-only learning rewards. Claims never change account data or recruitment.
const DEFINITIONS={
		"archer_cover":{"nameKo":"궁병 일제 엄호","effectKo":"적이 나타나면 지원 화살 세 발로 선택 전선을 엄호합니다."},
	"march_drum":{"nameKo":"진군 북소리","effectKo":"전진 병력의 보폭을 잠시 재촉합니다."},
	"supply_disruption":{"nameKo":"적 보급선 교란","effectKo":"아직 출발하지 않은 적 공세를 잠시 늦춥니다."},
	"rockfall":{"nameKo":"낙석 지원","effectKo":"산비탈의 돌 세 개가 가까운 적 전선으로 굴러옵니다."},
	"mountain_matchlocks":{"nameKo":"산악 조총대 엄호","effectKo":"산쪽 조총대가 나와 한 번 일제사격하고 철수합니다."}
}
var battle: Node2D
var claims: Dictionary={}
var jobs: Array=[]
var mobility_bases: Dictionary={}
var serial: int=0
var departure_delay: float=0.0

func bind(value: Node2D) -> void: battle=value
func reset() -> void:
	cease()
	claims.clear()
	serial=0

func cease() -> void:
	if is_instance_valid(battle):
		for unit in battle.units:
			if mobility_bases.has(int(unit.id)): unit.mobilityFactor=mobility_bases[int(unit.id)]
	mobility_bases.clear()
	jobs.clear()
	departure_delay=0.0

func strength(hinted: bool, skill: String) -> float:
	var total: float=0.0
	var count: int=0
	for level in battle.campaign_levels.values(): total+=clampf(float(level),1.0,10.0);count+=1
	var average: float=total/float(count) if count>0 else 1.0
	var band: int=clampi((int(battle.config.get("stageNumber",1))-1)/10,0,3)
	var value: float=minf(1.5,1.0+float(band)*.10+(average-1.0)*.025)
	if skill in ["grammar","cloze","form"]: value*=.85
	return value*(.55 if hinted else 1.0)

func terrain_plan(path_index: int) -> Dictionary:
	var history: Dictionary=battle.config.get("historicalBattlefield",{})
	var biome: String=str(history.get("sceneBiome",""))
	if not ("mountain" in biome or "ridge" in biome or "hill" in biome or "foothill" in biome): return {}
	for feature in history.get("heightFeatures",[]):
		if absf(float(feature.get("amplitudeWorld",0)))<.35 or str(feature.get("kind","")) not in ["hill","ridge","mountain","plateau","slope"]: continue
		var center: Vector2=Vector2(float(feature.get("x",0)),float(feature.get("y",0)))
		var extent: Vector2=Vector2(maxf(.03,float(feature.get("w",.1))*.6),maxf(.03,float(feature.get("h",.1))*.6))
		for segment in range(battle.paths[path_index].points.size()-1):
			var distance: float=battle.ground_combat.point_distance(path_index,segment,center)
			var fire: Vector2=battle.ground_combat.route_point(path_index,distance)
			if ((fire-center)/extent).length()>1.25: continue
			var toward: Vector2=(center-fire).normalized()
			if toward.length_squared()<.5: toward=(battle.paths[path_index].points[segment+1]-battle.paths[path_index].points[segment]).normalized().orthogonal()
			var origin: Vector2=fire+toward*.028
			var across: Vector2=toward.orthogonal()
			var origins: Array=[]
			var firing: Array=[]
			var safe: bool=true
			for member in range(3):
				var offset: Vector2=across*float(member-1)*.009
				var a: Vector2=origin+offset
				var b: Vector2=fire+offset
				if a.x<.015 or a.x>.985 or a.y<.015 or a.y>.985 or b.x<.015 or b.x>.985 or b.y<.015 or b.y>.985 or not battle.ground_combat.land_segment_safe(a,b,.005): safe=false;break
				origins.append(a);firing.append(b)
			if safe: return {"origin":origin,"fire":fire,"origins":origins,"firing":firing}
	return {}

func eligible(path_index: int) -> Array:
	var pool: Array=["archer_cover","march_drum","supply_disruption"]
	if path_index<0 or path_index>=battle.paths.size(): return pool
	var plan: Dictionary=terrain_plan(path_index)
	if not plan.is_empty():
		pool.append("rockfall")
		var biome: String=str(battle.config.get("historicalBattlefield",{}).get("sceneBiome",""))
		if "mountain" in biome or "ridge" in biome or "foothill" in biome: pool.append("mountain_matchlocks")
	return pool

func claim(attempt_id: String, hinted: bool, skill: String, anchor: Vector2=Vector2(-1,-1)) -> Dictionary:
	if claims.has(attempt_id):
		var existing: Dictionary=claims[attempt_id].duplicate(true)
		existing["duplicate"]=true
		return existing
	if attempt_id.strip_edges().is_empty() or not is_instance_valid(battle) or battle.config.is_empty() or not battle.running or battle.finished or battle.battle_closed: return {"ok":false,"reason":"battle_inactive"}
	var base: Dictionary=battle.ground_combat.select_march_base()
	if base.is_empty(): return {"ok":false,"reason":"no_safe_front"}
	var path_index: int=int(base.pathIndex)
	if anchor.is_finite() and anchor.x>=0 and anchor.x<=1 and anchor.y>=0 and anchor.y<=1:
		var nearest: float=INF
		for index in range(battle.paths.size()):
			for segment in range(battle.paths[index].points.size()-1):
				var projection: float=battle.ground_combat.point_distance(index,segment,anchor)
				var offset: float=battle.ground_combat.route_point(index,projection).distance_squared_to(anchor)
				if offset<nearest: nearest=offset;path_index=index
		base=battle.ground_combat.select_march_base(path_index)
		if base.is_empty(): return {"ok":false,"reason":"no_safe_front"}
	var pool: Array=eligible(path_index)
	# A separate draw does not perturb the enemy-spawn RNG or get rerolled on replay.
	var reward_rng: RandomNumberGenerator=RandomNumberGenerator.new()
	reward_rng.seed=absi((str(battle.config.get("id",""))+":"+attempt_id).hash())
	var kind: String=str(pool[reward_rng.randi_range(0,pool.size()-1)])
	serial+=1
	var receipt: Dictionary={"ok":true,"attemptId":attempt_id,"kind":kind,"nameKo":DEFINITIONS[kind].nameKo,"effectKo":DEFINITIONS[kind].effectKo,"hinted":hinted,"strength":strength(hinted,skill),"pathIndex":path_index,"state":"queued","serial":serial}
	if anchor.is_finite() and anchor.x>=0 and anchor.x<=1 and anchor.y>=0 and anchor.y<=1: receipt["requestedAnchor"]={"x":anchor.x,"y":anchor.y}
	claims[attempt_id]=receipt.duplicate(true)
	jobs.append({"receipt":receipt.duplicate(true),"age":0.0,"started":false,"released":false,"origin":base.position,"terrain":terrain_plan(path_index),"duration":(4.5 if hinted else 8.0) if kind=="march_drum" else 4.0})
	return receipt

func _targets(path_index: int, origin: Vector2, limit: int, max_range: float, land_only: bool) -> Array:
	var found: Array=[]
	for enemy in battle.enemies:
		if float(enemy.hp)<=0 or int(enemy.pathIndex)!=path_index or not battle._enemy_visible(enemy) or origin.distance_to(enemy.position)>max_range: continue
		if land_only and (battle._sailing_visual(enemy) or not battle.ground_combat.land_segment_safe(origin,enemy.position,.002)): continue
		found.append(enemy)
	found.sort_custom(func(a,b): return origin.distance_squared_to(a.position)<origin.distance_squared_to(b.position))
	if found.size()>limit: found.resize(limit)
	return found

func _volley(job: Dictionary, type_name: String, origin: Vector2, damage: float, max_range: float) -> void:
	var receipt: Dictionary=job.receipt
	var targets: Array=_targets(int(receipt.pathIndex),origin,3,max_range,type_name=="gunner")
	if targets.is_empty(): return
	for member in range(3):
		var position: Vector2=job.terrain.firing[member] if type_name=="gunner" else origin
		var member_targets: Array=_targets(int(receipt.pathIndex),position,3,max_range,true) if type_name=="gunner" else targets
		if member_targets.is_empty(): continue
		var enemy: Dictionary=member_targets[member%member_targets.size()]
		var source: Dictionary={"id":-20000-int(receipt.serial)*3-member,"type":type_name,"position":position,"campaignLevel":1,"learningSupport":true}
		battle.projectiles.append({"position":position,"targetId":int(enemy.id),"targetPos":enemy.position,"damage":damage*float(receipt.strength),"type":type_name,"sourceId":int(source.id),"sourcePosition":position,"speed":2.7 if type_name=="gunner" else 1.1,"age":0.0,"learningSupport":true})
		battle._combat_event("shot",source,enemy,{"learningSupport":true})

func step(delta: float) -> void:
	if not is_instance_valid(battle) or not battle.running or battle.paused or battle.between_waves or battle.finished or battle.battle_closed: return
	departure_delay=maxf(0.0,departure_delay-delta)
	var active: Array=[]
	for job in jobs:
		var receipt: Dictionary=job.receipt
		var kind: String=str(receipt.kind)
		if not bool(job.started):
			if kind in ["archer_cover","rockfall","mountain_matchlocks"]:
				var origin: Vector2=job.origin if kind=="archer_cover" else job.terrain.fire
				var max_range: float=1.45 if kind=="archer_cover" else .055 if kind=="rockfall" else .28
				if _targets(int(receipt.pathIndex),origin,1,max_range,kind!="archer_cover").is_empty():
					job["waitClock"]=float(job.get("waitClock",0.0))+delta
					if float(job.waitClock)<20.0: active.append(job)
					else: claims[str(receipt.attemptId)].state="complete"
					continue
			job.started=true
			claims[str(receipt.attemptId)].state="active"
			battle._event("learning-support",str(receipt.nameKo)+" · 지원 시작",{"supportKind":kind,"pathIndex":int(receipt.pathIndex)})
			if kind=="supply_disruption":
				departure_delay=maxf(departure_delay,2.8*float(receipt.strength))
				job.released=true
		job.age=float(job.age)+maxf(0.0,delta)
		if kind=="archer_cover" and not bool(job.released):
			var candidates: Array=_targets(int(receipt.pathIndex),job.origin,1,1.45,false)
			if not candidates.is_empty():
				_volley(job,"archer",job.origin,14.0,1.45)
				job.released=true
		if kind=="mountain_matchlocks" and float(job.age)>=.80 and not bool(job.released):
			_volley(job,"gunner",job.terrain.fire,20.0,.28)
			job.released=true
		if kind=="rockfall" and float(job.age)>=.75 and not bool(job.released):
			for enemy in _targets(int(receipt.pathIndex),job.terrain.fire,3,.055,true):
				battle._damage_enemy(enemy,30.0*float(receipt.strength),"rockfall",{"id":-30000-int(receipt.serial),"type":"rockfall","position":job.terrain.origin,"learningSupport":true})
			job.released=true
		var duration: float=1.65 if kind=="mountain_matchlocks" else 1.05 if kind=="rockfall" else float(job.duration)
		if float(job.age)<duration: active.append(job)
		else: claims[str(receipt.attemptId)].state="complete"
	jobs=active
	var drum: float=1.0
	for job in jobs:
		if bool(job.started) and str(job.receipt.kind)=="march_drum": drum=maxf(drum,1.0+.14*float(job.receipt.strength))
	for unit in battle.units:
		if not battle.ground_combat.is_marching(str(unit.type)): continue
		var id: int=int(unit.id)
		if drum>1.0:
			if not mobility_bases.has(id): mobility_bases[id]=float(unit.get("mobilityFactor",1.0))
			unit.mobilityFactor=float(mobility_bases[id])*drum
		elif mobility_bases.has(id):
			unit.mobilityFactor=mobility_bases[id]
			mobility_bases.erase(id)

func actor_states() -> Array:
	var records: Array=[]
	for job in jobs:
		if not bool(job.started) or str(job.receipt.kind)!="mountain_matchlocks": continue
		var age: float=float(job.age)
		for member in range(3):
			var origin: Vector2=job.terrain.origins[member]
			var fire: Vector2=job.terrain.firing[member]
			var approach: bool=age<.55
			var firing: bool=age>=.55 and age<1.05
			var point: Vector2=origin.lerp(fire,clampf(age/.55,0.0,1.0)) if approach else fire if firing else fire.lerp(origin,clampf((age-1.05)/.60,0.0,1.0))
			var targets: Array=_targets(int(job.receipt.pathIndex),fire,1,.28,true)
			var aim: Vector2=(targets[0].position-fire).normalized() if not targets.is_empty() else (fire-origin).normalized()
			if not firing: aim=(fire-origin).normalized() if approach else (origin-fire).normalized()
			records.append({"id":-20000-int(job.receipt.serial)*3-member,"type":"gunner","friendly":true,"dead":false,"x":point.x,"y":point.y,"aimX":aim.x,"aimY":aim.y,"animation":"attack" if firing else "walk","animationClock":age-.55 if firing else age if approach else age-1.05,"motionTime":battle.animation_time,"animationPhase":float(member)*.18,"attackDuration":.5,"sailing":false,"transientSupport":true,"supportPathIndex":int(job.receipt.pathIndex),"campaignLevel":1,"hp":1.0,"maxHp":1.0})
	return records

func rock_states() -> Array:
	var records: Array=[]
	for job in jobs:
		if not bool(job.started) or str(job.receipt.kind)!="rockfall" or float(job.age)>.75: continue
		for member in range(3):
			var progress: float=clampf((float(job.age)-float(member)*.07)/.60,0.0,1.0)
			var point: Vector2=(job.terrain.origin as Vector2).lerp(job.terrain.fire,progress)
			records.append({"id":str(job.receipt.serial)+":"+str(member),"point":point,"height":(1.0-progress)*.45+sin(progress*PI)*.14,"angle":progress*TAU*2.0+float(member),"radius":.10+float(member)*.014})
	return records

func snapshot() -> Array:
	var records: Array=[]
	for job in jobs:
		var value: Dictionary=job.receipt.duplicate(true)
		value.merge({"state":"active" if bool(job.started) else "queued","age":float(job.age)},true)
		records.append(value)
	return records
