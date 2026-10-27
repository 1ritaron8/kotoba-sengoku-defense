extends RefCounted
## Presentation only. Combat plans and committed events own every skill.
## The cage moves shoulders, hands and weapons independently; feet stay fixed.
const PROFILES: Dictionary = {
	"archer_fire":[.22,-.17,.16,.025],
	"archer_barrage":[-.32,.30,-.28,.045],
	"archer_double_shot":[-.34,.36,-.24,.040],
	"spear_pierce":[-.08,.06,-.04,.075],
	"spear_brace":[-.18,.16,-.10,-.025],
	"spear_rear_rank":[-.12,.10,-.035,.110],
	"samurai_parry":[-.28,.30,.20,-.025],
	"samurai_counter":[.30,-.26,.36,.045],
	"samurai_counter_combo":[.34,-.30,.42,.055],
	"samurai_isshin":[.44,-.38,.58,.075],
	"gunner_pierce":[-.07,.11,-.05,.020],
	"gunner_armor_break":[-.15,.20,-.13,.035],
	"gunner_braced_shot":[-.20,.24,-.12,-.030],
	"monk_talisman":[-.25,.10,-.06,.020],
	"monk_ward":[-.30,.34,-.10,.025],
	"monk_victory_prayer":[-.35,.35,-.12,.035],
	"commander_charge":[-.12,.14,-.16,.045],
	"commander_impact":[.24,-.18,.30,.045],
	"commander_rally":[-.32,.26,-.24,.020],
	"ninja_timed_charge":[.34,-.18,.12,.060],
	"ninja_opening_combo":[.26,-.24,.34,.055],
	"ninja_charge_shrapnel":[.34,-.18,.12,.060],
}
var _attacks: Dictionary = {}
var _reactions: Dictionary = {}
var _commits: Dictionary = {}
var _next_prune: float = 0.0
var _meshes: Dictionary = {}
var _next_mesh_prune: float = 0.0
## Source arrays and anatomical weights are immutable after preparation.
## Every actor still owns its dynamic ArrayMesh and writable vertex buffer.
class SourceGeometry extends RefCounted:
	var arrays: Array = []
	var vertices: PackedVector3Array = PackedVector3Array()
	var root_arm_weights: PackedVector2Array = PackedVector2Array()
	var left_arm: PackedVector2Array = PackedVector2Array()
	var right_arm: PackedVector2Array = PackedVector2Array()
	var weapon_positive: PackedVector2Array = PackedVector2Array()
	var weapon_negative: PackedVector2Array = PackedVector2Array()
	var banner: PackedVector2Array = PackedVector2Array()
	var bounds: AABB

static var _geometry_templates: Dictionary = {}

func reset() -> void:
	_attacks.clear(); _reactions.clear(); _commits.clear()
	_meshes.clear(); _next_prune=0.0
	_next_mesh_prune=0.0

func prune_actor_meshes(live_units: Dictionary, now: float, force: bool = false) -> void:
	if not force and now<_next_mesh_prune: return
	_next_mesh_prune=now+.50
	for key in _meshes.keys():
		var actor_key: String=str(_meshes[key].get("actorKey",""))
		if not actor_key.begins_with("friendly/"): continue
		var id: int=int(actor_key.get_slice("/",1))
		if id<0: continue # Dedicated previews own their own renderer lifetime.
		var unit: Dictionary=live_units.get(id,{})
		if unit.is_empty() or float(unit.get("hp",0))<=0.0 or bool(unit.get("consumed",false)): _meshes.erase(key)

func prepare_draw(motion: Dictionary, direction: Vector2, mounted: bool) -> Dictionary:
	if motion.is_empty() or not PROFILES.has(str(motion.get("skillId",""))): return motion
	var result: Dictionary=motion.duplicate(false)
	var values: Dictionary=_pose_values(motion)
	values["facing"]=1.0 if direction.x>=0 else -1.0
	values["mounted"]=mounted
	result["_paintedPoseValues"]=values
	return result

func _key(actor: Dictionary) -> String:
	return str(actor.get("id",-1))

func _token(plan: Dictionary) -> String:
	var meta: Dictionary=plan.get("skillMeta",{})
	var motion_token: String=str(meta.get("motionToken",""))
	return motion_token if not motion_token.is_empty() else str(meta.get("attackId",""))

func _reaction(id: int, skill_id: String, now: float, duration: float, token: String = "") -> void:
	if id<0 or not PROFILES.has(skill_id): return
	var priority: Dictionary={"monk_talisman":1,"monk_ward":2,"monk_victory_prayer":3}
	var previous: Dictionary=_reactions.get(str(id),{})
	if not previous.is_empty() and now<float(previous.startedAt)+float(previous.duration) and int(priority.get(str(previous.skillId),2))>int(priority.get(skill_id,2)): return
	_reactions[str(id)]={"skillId":skill_id,"startedAt":now,"duration":duration,"token":token,"committed":true,"reaction":true}

func consume_event(event: Dictionary, battle: Node2D) -> void:
	var action: String=str(event.get("action",event.get("type","")))
	var id: int=int(event.get("actorId",-1))
	var skill_id: String=str(event.get("skillId",""))
	var effect: String=str(event.get("effectKind",""))
	var now: float=float(event.get("time",battle.elapsed))
	var meta: Dictionary=event.get("skillMeta",{})
	var token: String=_token({"skillMeta":meta})
	if str(event.get("side",""))=="friendly" and action in ["shot","hit","skill_hit","skill"]:
		var actor: Dictionary=battle.ground_combat._unit(id)
		if not actor.is_empty():
			var plan: Dictionary=actor.get("attackPlan",{})
			if not plan.is_empty(): _remember_attack(actor,plan,now)
		var saved: Dictionary=_attacks.get(str(id),{})
		# Delayed projectile impacts cannot replace a newer attack's receipts.
		if not token.is_empty() and not saved.is_empty() and _token(saved.plan)==token:
			var previous: Dictionary=_commits.get(str(id),{})
			var count: int=int(previous.get("hits",0)) if str(previous.get("token",""))==token else 0
			var releases: int=int(previous.get("releases",0)) if str(previous.get("token",""))==token else 0
			var hit_index: int=int(event.get("hitIndex",meta.get("hitIndex",-1)))
			var release_index: int=int(event.get("releaseIndex",meta.get("releaseIndex",-1)))
			if action in ["hit","skill_hit"]: count=maxi(count,hit_index+1 if hit_index>=0 else 1)
			if action=="shot" or release_index>=0: releases=maxi(releases,release_index+1 if release_index>=0 else 1)
			_commits[str(id)]={"token":token,"hits":count,"releases":releases,"time":now,"committed":true}
	if str(event.get("side",""))=="friendly" and action in ["skill_cast","skill","status","parry"]:
		if skill_id=="samurai_parry": _reaction(id,skill_id,now,.30,token)
		elif skill_id=="spear_brace": _reaction(id,skill_id,now,.32,token)
		elif skill_id=="monk_ward" and effect in ["ward","ward_grant"]: _reaction(id,skill_id,now,.42,token)
		elif skill_id=="commander_rally": _reaction(id,skill_id,now,.58,token)
	if effect=="charge_plant":
		_reaction(id,"ninja_timed_charge",now,.20,token)
	elif action=="heal" and effect=="heal":
		var healer: Dictionary=battle.ground_combat._unit(id)
		if not healer.is_empty() and battle.unit_skills.has_skill(healer,"monk_talisman"):
			_reaction(id,"monk_talisman",now,.55)
	elif action in ["skill","skill_cast"] and skill_id=="monk_victory_prayer":
		_reaction(id,skill_id,now,.55)

func _remember_attack(actor: Dictionary, plan: Dictionary, now: float) -> void:
	var key: String=_key(actor)
	var old: Dictionary=_attacks.get(key,{})
	if not old.is_empty() and _token(old.plan)==_token(plan): return
	_attacks[key]={"plan":plan.duplicate(true),"duration":maxf(.01,float(actor.get("attackDuration",.5))),"startedAt":now-maxf(0.0,float(actor.get("animationClock",0)))}

func _prune_receipts(now: float) -> void:
	if now<_next_prune: return
	_next_prune=now+.50
	for key in _attacks.keys():
		if now-float(_attacks[key].startedAt)>8.0:
			_attacks.erase(key); _commits.erase(key); _reactions.erase(key)
	for key in _reactions.keys():
		var reaction: Dictionary=_reactions[key]
		if now>float(reaction.startedAt)+float(reaction.duration)+1.0: _reactions.erase(key)

func request(actor: Dictionary, friendly: bool, battle: Node2D) -> Dictionary:
	if not friendly or str(actor.get("animation","")) in ["death","hit"]: return {}
	var explicit: Dictionary=actor.get("paintedSkillMotion",{})
	if not explicit.is_empty() and PROFILES.has(str(explicit.get("skillId",""))): return explicit.duplicate(false)
	if battle==null: return {}
	var key: String=_key(actor)
	var now: float=float(battle.elapsed)
	_prune_receipts(now)
	var reaction: Dictionary=_reactions.get(key,{})
	if not reaction.is_empty() and now<float(reaction.startedAt)+float(reaction.duration):
		var result: Dictionary=reaction.duplicate(false)
		result["clock"]=maxf(0.0,now-float(reaction.startedAt))
		return result
	if bool(actor.get("consumed",false)): return {}
	var plan: Dictionary=actor.get("attackPlan",{})
	var live_plan_present: bool=not plan.is_empty()
	if not plan.is_empty(): _remember_attack(actor,plan,now)
	if str(actor.get("animation","idle"))!="attack":
		if str(actor.get("type",""))=="commander" and str(actor.get("combatState",""))=="charge" and battle.unit_skills.can_charge(actor):
			return {"skillId":"commander_charge","clock":.15,"duration":.45,"releaseTime":.30,"committed":false,"token":"charge_approach"}
		return {}
	var saved: Dictionary=_attacks.get(key,{})
	if saved.is_empty(): return {}
	plan=saved.plan
	# A canceled attack cannot inherit an older attack's committed recovery.
	var clock: float=maxf(0.0,float(actor.get("animationClock",0)))
	if absf((now-clock)-float(saved.startedAt))>.0001: return {}
	var id: String=str(plan.get("skillId",""))
	if str(plan.get("skillAction",""))=="samurai_counter": id="samurai_counter"
	elif str(plan.get("ninjaAction",""))=="combo": id="ninja_opening_combo"
	elif str(plan.get("ninjaAction",""))=="plant": id="ninja_timed_charge"
	var commit: Dictionary=_commits.get(key,{})
	var committed: bool=str(commit.get("token",""))==_token(plan) and bool(commit.get("committed",false))
	if not live_plan_present and not committed: return {}
	var release: float=maxf(.001,float(plan.get("releaseTime",.25)))
	if not PROFILES.has(id): return {}
	return {"skillId":id,"clock":clock,"duration":float(saved.duration),"releaseTime":release,"releaseTimes":plan.get("releaseTimes",[]),"committed":committed,"token":_token(plan),"hitCount":int(commit.get("hits",0)) if committed else 0,"releaseCount":int(commit.get("releases",0)) if committed else 0,"impactTimes":plan.get("counterImpactTimes",plan.get("impactTimes",plan.get("ninjaImpactTimes",[])))}

func _staged_stroke(clock: float, duration: float, times: Array, count: int, alternate: bool) -> Dictionary:
	count=clampi(count,0,times.size())
	if count==0: return {"preparation":smoothstep(0.0,float(times[0]),minf(clock,float(times[0]))),"stroke":0.0}
	var index: int=count-1
	var start: float=float(times[index])
	var end: float=duration if index==times.size()-1 else float(times[index+1])
	var sign_value: float=-1.0 if alternate and index%2==1 else 1.0
	return {"preparation":smoothstep(start,end,clock) if index<times.size()-1 else 0.0,"stroke":sign_value*(1.0-smoothstep(start,lerpf(start,end,.70),clock))}

func _pose_values(motion: Dictionary) -> Dictionary:
	var id: String=str(motion.skillId)
	var duration: float=maxf(.001,float(motion.get("duration",.5)))
	var clock: float=clampf(float(motion.get("clock",0)),0,duration)
	var release: float=clampf(float(motion.get("releaseTime",duration*.45)),.001,duration*.95)
	var committed: bool=bool(motion.get("committed",false))
	var preparation: float=smoothstep(0.0,release,minf(clock,release))
	var stroke: float=0.0
	var recovery: float=0.0
	if bool(motion.get("reaction",false)):
		stroke=sin(clampf(clock/duration,0,1)*PI); preparation=0.0
	elif id in ["ninja_opening_combo","samurai_counter_combo","archer_double_shot"]:
		var times: Array=motion.get("impactTimes",[])
		if times.is_empty(): times=motion.get("releaseTimes",[])
		if times.is_empty(): times=[duration*.25,duration*.55,duration*.85] if id=="ninja_opening_combo" else [duration*.40,duration*.76]
		var count: int=int(motion.get("releaseCount",0)) if id=="archer_double_shot" else int(motion.get("hitCount",0))
		var staged: Dictionary=_staged_stroke(clock,duration,times,count,id!="archer_double_shot")
		preparation=float(staged.preparation); stroke=float(staged.stroke)
	else:
		if committed and clock>=release:
			recovery=smoothstep(release,duration,clock)
			stroke=sin((1.0-recovery)*PI*.5)
			preparation*=1.0-recovery
	var profile: Array=PROFILES[id]
	var drive: float=stroke-preparation*.45
	var planting: bool=id in ["ninja_timed_charge","ninja_charge_shrapnel"]
	if planting and not bool(motion.get("reaction",false)): drive=preparation
	var crouch: float=0.0
	var lower_hands: float=0.0
	if planting: crouch=.045*preparation+.02*stroke; lower_hands=.07*preparation
	elif id=="gunner_braced_shot": crouch=.025*preparation; lower_hands=.012*preparation
	elif id=="spear_brace": crouch=.020*absf(stroke)
	elif id in ["samurai_parry","samurai_isshin","monk_victory_prayer"]: crouch=.015*absf(stroke)
	return {"left":float(profile[0])*drive,"right":float(profile[1])*drive,"weapon":float(profile[2])*drive,"reach":float(profile[3])*drive,"crouch":crouch,"lowerHands":lower_hands,"flag":.16*stroke if id=="commander_rally" else 0.0}

func _split_triangle(a: Vector2, b: Vector2, c: Vector2, depth: int, points: PackedVector2Array) -> void:
	if depth<=0:
		points.append(a); points.append(b); points.append(c); return
	var ab: Vector2=(a+b)*.5
	var bc: Vector2=(b+c)*.5
	var ca: Vector2=(c+a)*.5
	_split_triangle(a,ab,ca,depth-1,points); _split_triangle(ab,b,bc,depth-1,points)
	_split_triangle(ca,bc,c,depth-1,points); _split_triangle(ab,bc,ca,depth-1,points)

func _source_geometry(key: String, polygon: PackedVector2Array, region: Rect2, texture: Texture2D, origin: Vector2, anchor: Vector2, height: float, mounted: bool) -> SourceGeometry:
	if _geometry_templates.has(key): return _geometry_templates[key]
	var indices: PackedInt32Array=Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty(): return null
	var corners: PackedVector2Array=PackedVector2Array()
	for index in range(0,indices.size(),3): _split_triangle(polygon[indices[index]],polygon[indices[index+1]],polygon[indices[index+2]],2,corners)
	var points: PackedVector2Array=PackedVector2Array()
	var unique: Dictionary={}
	var triangles: PackedInt32Array=PackedInt32Array()
	# Exact duplicates share one vertex; retain every original triangle/UV.
	for point in corners:
		if not unique.has(point):
			unique[point]=points.size()
			points.append(point)
		triangles.append(int(unique[point]))
	var geometry: SourceGeometry=SourceGeometry.new()
	var uv: PackedVector2Array=PackedVector2Array()
	var root: Vector2=anchor-Vector2(0,height*(.56 if mounted else .34))
	var shoulders: Vector2=anchor-Vector2(0,height*(.79 if mounted else .56))
	var left_shoulder: Vector2=shoulders-Vector2(height*.10,0)
	var right_shoulder: Vector2=shoulders+Vector2(height*.10,0)
	var positive_grip: Vector2=shoulders+Vector2(height*.25,height*.14)
	var negative_grip: Vector2=shoulders+Vector2(-height*.25,height*.14)
	var banner_root: Vector2=anchor-Vector2(0,height*.90)
	for point in points:
		geometry.vertices.append(Vector3(point.x-origin.x,point.y-origin.y,0))
		# Clamp the atlas edge to texel centers to avoid neighboring frames.
		uv.append((region.position+point.clamp(Vector2.ONE*.5,region.size-Vector2.ONE*.5))/texture.get_size())
		var waist: float=1.0-smoothstep(root.y-height*.04,root.y+height*.17,point.y)
		var central: float=1.0-smoothstep(height*.10,height*.30,absf(point.x-root.x))
		var head_mask: float=smoothstep(shoulders.y-height*.12,shoulders.y+height*.02,point.y)
		var left_weight: float=smoothstep(-height*.015,height*.22,left_shoulder.x-point.x)*waist*head_mask
		var right_weight: float=smoothstep(-height*.015,height*.22,point.x-right_shoulder.x)*waist*head_mask
		geometry.root_arm_weights.append(Vector2(waist*central,left_weight+right_weight))
		geometry.left_arm.append((point-left_shoulder)*left_weight)
		geometry.right_arm.append((point-right_shoulder)*right_weight)
		var lower_mask: float=1.0-smoothstep(anchor.y-height*.23,anchor.y-height*.08,point.y)
		var positive_weight: float=smoothstep(height*.20,height*.38,point.x-shoulders.x)*lower_mask
		var negative_weight: float=smoothstep(height*.20,height*.38,shoulders.x-point.x)*lower_mask
		geometry.weapon_positive.append((point-positive_grip)*positive_weight)
		geometry.weapon_negative.append((point-negative_grip)*negative_weight)
		var banner_mask: float=1.0-smoothstep(banner_root.y-height*.12,banner_root.y,point.y) if mounted else 0.0
		geometry.banner.append((point-banner_root)*banner_mask)
	geometry.arrays.resize(Mesh.ARRAY_MAX)
	geometry.arrays[Mesh.ARRAY_VERTEX]=geometry.vertices
	geometry.arrays[Mesh.ARRAY_TEX_UV]=uv
	geometry.arrays[Mesh.ARRAY_INDEX]=triangles
	geometry.arrays.make_read_only()
	geometry.bounds=AABB(Vector3(-origin.x-region.size.x*.20,-origin.y-region.size.y*.20,-.01),Vector3(region.size.x*1.40,region.size.y*1.40,.02))
	if _geometry_templates.size()>=384: _geometry_templates.erase(_geometry_templates.keys()[0])
	_geometry_templates[key]=geometry
	return geometry

func _mesh(key: String, source_key: String, polygon: PackedVector2Array, region: Rect2, texture: Texture2D, origin: Vector2, anchor: Vector2, body_height: float, mounted: bool, actor_key: String) -> Dictionary:
	if _meshes.has(key):
		var cached: Dictionary=_meshes[key]
		cached["lastUsedFrame"]=Engine.get_process_frames()
		return cached
	var geometry: SourceGeometry=_source_geometry(source_key,polygon,region,texture,origin,anchor,body_height,mounted)
	if geometry==null: return {}
	# Explicit copies keep actor writes out of the shared source template.
	var vertices: PackedVector3Array=geometry.vertices.duplicate()
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=geometry.arrays[Mesh.ARRAY_TEX_UV]
	arrays[Mesh.ARRAY_INDEX]=geometry.arrays[Mesh.ARRAY_INDEX]
	var mesh: ArrayMesh=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh.custom_aabb=geometry.bounds
	var result: Dictionary={"mesh":mesh,"geometry":geometry,"vertices":vertices,"values":{},"actorKey":actor_key,"lastUsedFrame":Engine.get_process_frames()}
	if _meshes.size()>=384:
		var oldest_key: String=""
		var oldest_frame: int=9223372036854775807
		for candidate in _meshes:
			var used: int=int(_meshes[candidate].get("lastUsedFrame",-1))
			if used<oldest_frame: oldest_frame=used; oldest_key=str(candidate)
		if not oldest_key.is_empty(): _meshes.erase(oldest_key)
	_meshes[key]=result
	return result

func _rotation_delta(angle: float) -> Transform2D:
	var cosine: float=cos(angle)-1.0
	var sine: float=sin(angle)
	return Transform2D(Vector2(cosine,sine),Vector2(-sine,cosine),Vector2.ZERO)

func draw(canvas: CanvasItem, texture: Texture2D, region: Rect2, anchor: Vector2, origin: Vector2, polygon: PackedVector2Array, start: Vector2, height: float, body_height: float, tint: Color, motion: Dictionary, actor_key: String, direction: Vector2, mounted: bool = false, rotation_value: float = 0.0, geometry_key: String = "") -> bool:
	if motion.is_empty() or not PROFILES.has(str(motion.get("skillId",""))) or body_height<=0: return false
	var source_key: String=geometry_key
	if source_key.is_empty(): source_key=str(texture.get_instance_id())+":"+str(region)+":"+str(origin)+":"+str(anchor)+":"+str(body_height)+":"+str(polygon)
	source_key+="/mounted" if mounted else "/standing"
	var key: String=actor_key+":"+source_key
	var entry: Dictionary=_mesh(key,source_key,polygon,region,texture,origin,anchor,body_height,mounted,actor_key)
	if entry.is_empty(): return false
	var facing: float=1.0 if direction.x>=0 else -1.0
	var values: Dictionary=motion.get("_paintedPoseValues",{})
	if values.is_empty() or float(values.get("facing",0))!=facing or bool(values.get("mounted",false))!=mounted:
		values=_pose_values(motion)
		values["facing"]=facing; values["mounted"]=mounted
	if entry.values!=values:
		var geometry: SourceGeometry=entry.geometry
		var vertices: PackedVector3Array=entry.vertices
		var source_vertices: PackedVector3Array=geometry.vertices
		var root_weights: PackedVector2Array=geometry.root_arm_weights
		var left_arm: PackedVector2Array=geometry.left_arm
		var right_arm: PackedVector2Array=geometry.right_arm
		var weapon: PackedVector2Array=geometry.weapon_positive if facing>0 else geometry.weapon_negative
		var banner: PackedVector2Array=geometry.banner
		var reach: float=facing*float(values.reach)*body_height
		var root_shift: Vector2=Vector2(reach*.22,float(values.crouch)*body_height)
		var hand_shift: Vector2=Vector2(reach,float(values.lowerHands)*body_height)
		var left_rotation: Transform2D=_rotation_delta(float(values.left)*facing)
		var right_rotation: Transform2D=_rotation_delta(float(values.right)*facing)
		var weapon_rotation: Transform2D=_rotation_delta(float(values.weapon)*facing)
		var flag_active: bool=mounted and absf(float(values.get("flag",0.0)))>.0001
		var flag_rotation: Transform2D=_rotation_delta(float(values.get("flag",0.0))*facing) if flag_active else Transform2D.IDENTITY
		for index in range(vertices.size()):
			var source: Vector3=source_vertices[index]
			var weights: Vector2=root_weights[index]
			var point: Vector2=Vector2(source.x,source.y)+root_shift*weights.x+hand_shift*weights.y
			point+=left_rotation*left_arm[index]+right_rotation*right_arm[index]+weapon_rotation*weapon[index]
			if flag_active: point+=flag_rotation*banner[index]
			vertices[index]=Vector3(point.x,point.y,0)
		entry.vertices=vertices; entry.values=values
		entry.mesh.surface_update_vertex_region(0,0,vertices.to_byte_array())
	var mesh_transform: Transform2D=Transform2D(rotation_value,Vector2.ONE*(height/body_height),0.0,start)
	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_mesh(entry.mesh,texture,mesh_transform,tint)
	return true
