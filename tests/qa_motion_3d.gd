extends SceneTree
## Checks observable world-space poses, rather than copying the animation formula.

const Actor = preload("res://native/sengoku_actor_3d.gd")
const Troops = preload("res://native/troops_3d.gd")
const TYPES = ["archer","spear","samurai","commander","enemy_light","enemy_heavy"]
var checks = 0
var failures: Array = []
var reports: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, context: String, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(context+": "+message)
		push_error("MOTION QA "+context+": "+message)

func _state(animation: String, clock: float, sailing: bool = false, aim: Vector2 = Vector2(0,-1)) -> Dictionary:
	return {"animation":animation,"animationClock":clock,"animationPhase":0.0,"aimX":aim.x,"aimY":aim.y,"hitClock":0.0,"sailing":sailing}

func _point(actor: Node3D, name_value: String) -> Vector3:
	return actor.bones[name_value].global_position

func _sole_vertices(actor: Node3D, bone_name: String) -> Array:
	var result: Array = []
	for instance in actor.meshes:
		if str(instance.get_parent().name)==bone_name:
			for surface in range(instance.mesh.get_surface_count()):
				result.append({"instance":instance,"vertices":instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]})
	return result

func _sole_height(pieces: Array) -> float:
	var height = INF
	for piece in pieces:
		for vertex in piece.vertices:
			height = minf(height,(piece.instance.global_transform*vertex).y)
	return height

func _snapshot(actor: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for key in actor.bones:
		var node: Node3D = actor.bones[key]
		result[key] = {"point":node.global_position,"localRotation":node.quaternion,"worldRotation":node.global_basis.get_rotation_quaternion(),"worldBasis":node.global_basis}
	return result

func _distance_span(samples: Array, key: String) -> float:
	var largest = 0.0
	for a in samples:
		for b in samples:
			largest = maxf(largest,a[key].point.distance_to(b[key].point))
	return largest

func _angle_span(samples: Array, key: String, world: bool = false) -> float:
	var largest = 0.0
	var rotation_key = "worldRotation" if world else "localRotation"
	for a in samples:
		for b in samples:
			largest = maxf(largest,a[key][rotation_key].angle_to(b[key][rotation_key]))
	return largest

func _axis_span(samples: Array, key: String, axis: Vector3) -> float:
	var smallest = INF
	var largest = -INF
	for sample in samples:
		var projected: float = sample[key].point.dot(axis)
		smallest = minf(smallest,projected)
		largest = maxf(largest,projected)
	return largest-smallest

func _max_pose_difference(a: Dictionary, b: Dictionary) -> float:
	var difference = 0.0
	for key in a:
		difference = maxf(difference,a[key].point.distance_to(b[key].point))
		for axis in [0,1,2]:
			difference = maxf(difference,a[key].worldBasis[axis].distance_to(b[key].worldBasis[axis]))
	return difference

func _run() -> void:
	for type_name in TYPES:
		var actor = Actor.new()
		root.add_child(actor)
		actor.configure(type_name,type_name.begins_with("enemy"),23,false)
		var info = {"type":type_name,"walk":_walk(actor,type_name),"attack":_attack(actor,type_name),"rowing":_rowing(actor,type_name),"death":_death(actor,type_name)}
		for animation in ["idle","walk","attack","death"]:
			var data = _state(animation,0.19)
			actor.apply_state(data)
			var frozen = _snapshot(actor)
			for unused in range(3):
				await process_frame
				actor.apply_state(data)
			_check(_max_pose_difference(frozen,_snapshot(actor))<0.00005,type_name+"/"+animation,"Frozen simulation time preserves every joint and endpoint")
		for aim in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(0.6,-0.8)]:
			actor.apply_state(_state("walk",0.23,false,aim))
			var forward = -actor.global_basis.z.normalized()
			var desired = Vector3(aim.x,0,aim.y).normalized()
			_check(forward.dot(desired)>0.999,type_name+"/aim","The model's actual -Z forward follows the world movement direction")
		reports.append(info)
		actor.queue_free()
		await process_frame
	var live_plant = await _live_ground_walk()
	var report = {"checks":checks,"failures":failures,"types":reports,"liveGroundMotion":live_plant,"scope":"Actual joint world endpoints, shoe/hoof vertices, pause determinism, facing, full-body pose variation. Procedural pose verification does not establish motion-capture realism.","limitations":["Treadmill foot sliding is separately reported at .4m/s; the real renderer world-anchor path is validated through sync_actor_states.","Terrain is a flat plane. Uneven-ground IK, cloth simulation and inter-character collision are outside this probe."],"godot":Engine.get_version_info().string}
	var file = FileAccess.open("res://tests/qa_motion_3d.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("QA_MOTION_3D ",JSON.stringify({"checks":checks,"failures":failures,"types":reports.size()}))
	quit(0 if failures.is_empty() else 1)

func _walk(actor: Node3D, context: String) -> Dictionary:
	var mounted = context=="commander"
	var soles: Array = []
	var feet: Array = ["horse_calf0","horse_calf1","horse_calf2","horse_calf3"] if mounted else ["footL","footR"]
	for key in feet: soles.append(_sole_vertices(actor,key))
	var samples: Array = []
	var lowest = INF
	var largest_lowest = -INF
	var contact_frames = 0
	var signed_sole_heights: Array = []
	for frame in range(41):
		actor.apply_state(_state("walk",float(frame)*1.2/40.0))
		samples.append(_snapshot(actor))
		var lowest_this_frame = INF
		var frame_heights: Array = []
		for pieces in soles:
			var y = _sole_height(pieces)
			lowest = minf(lowest,y)
			lowest_this_frame = minf(lowest_this_frame,y)
			frame_heights.append(y)
		largest_lowest = maxf(largest_lowest,lowest_this_frame)
		if absf(lowest_this_frame)<0.035: contact_frames+=1
		signed_sole_heights.append(frame_heights)
	var thigh_key = "horse_leg0" if mounted else "thighL"
	var shin_key = "horse_calf0" if mounted else "shinL"
	var body_key = "mount" if mounted else "pelvis"
	var foot_span = _axis_span(samples,feet[0],Vector3.FORWARD)
	var lateral_span = _axis_span(samples,feet[0],Vector3.RIGHT)
	var hip_travel = _distance_span(samples,body_key)
	var hip_angle = _angle_span(samples,body_key)
	var metrics = {"thighRadians":_angle_span(samples,thigh_key),"kneeRadians":_angle_span(samples,shin_key),"footForwardMeters":foot_span,"footLiftMeters":_axis_span(samples,feet[0],Vector3.UP),"bodyTravelMeters":hip_travel,"bodyRotationRadians":hip_angle,"spineWorldRadians":_angle_span(samples,"torso",true),"shoulderTravelMeters":_distance_span(samples,"armL"),"lowestSoleY":lowest,"maxLowestSoleY":largest_lowest,"contactFrameRatio":float(contact_frames)/41.0}
	_check(metrics.thighRadians>0.15,context+"/walk","The hip/upper-leg changes through a stride")
	_check(metrics.kneeRadians>0.08,context+"/walk","The knee bends through a stride")
	_check(foot_span>0.06 and foot_span>lateral_span*1.5,context+"/walk","Foot endpoints stride forward rather than only sideways")
	_check(metrics.footLiftMeters>0.015,context+"/walk","A swing foot actually lifts")
	_check(hip_travel>0.008 or hip_angle>0.025,context+"/walk","The pelvis/horse body participates instead of a stationary body with moving arms")
	_check(metrics.spineWorldRadians>0.025,context+"/walk","The trunk changes its world-space pose with the gait")
	_check(metrics.shoulderTravelMeters>0.008,context+"/walk","Shoulder endpoints move with the body")
	_check(lowest>=-0.015,context+"/walk","The real shoe/hoof mesh stays above the ground within 15mm")
	_check(float(contact_frames)/41.0>0.75,context+"/walk","At least one real sole remains near the ground in most walking poses")
	if mounted:
		for leg in range(4):
			_check(_distance_span(samples,"horse_calf%d" % leg)>0.06,context+"/walk","Every horse leg participates in the gait")
		_check(_distance_span(samples,"pelvis")>0.01,context+"/mounted","Rider reacts to the moving horse")
	# Observe, but do not prescribe an unknown live-game velocity.
	var diagnostic_slide = 0.0
	var contact_pairs = 0
	for frame in range(1,samples.size()):
		for foot in range(feet.size()):
			if absf(float(signed_sole_heights[frame-1][foot]))<0.035 and absf(float(signed_sole_heights[frame][foot]))<0.035:
				var delta: Vector3 = samples[frame][feet[foot]].point-samples[frame-1][feet[foot]].point+Vector3(0,0,-0.4*1.2/40.0)
				diagnostic_slide += Vector2(delta.x,delta.z).length()
				contact_pairs+=1
	metrics["diagnosticPlantSpeedMetersPerSecond"] = diagnostic_slide/maxi(1,contact_pairs)/(1.2/40.0)
	metrics["diagnosticRootSpeedMetersPerSecond"] = 0.4
	return metrics

func _attack(actor: Node3D, context: String) -> Dictionary:
	var samples: Array = []
	for frame in range(21):
		actor.apply_state(_state("attack",float(frame)*0.5/20.0))
		samples.append(_snapshot(actor))
	var stance_angle = maxf(_angle_span(samples,"thighL"),maxf(_angle_span(samples,"thighR"),maxf(_angle_span(samples,"shinL"),_angle_span(samples,"shinR"))))
	if context=="commander":
		stance_angle = maxf(stance_angle,maxf(_angle_span(samples,"thighL",true),_angle_span(samples,"thighR",true)))
	var metrics = {"handTravelMeters":maxf(_distance_span(samples,"handL"),_distance_span(samples,"handR")),"spineRadians":_angle_span(samples,"torso"),"pelvisTravelMeters":_distance_span(samples,"pelvis"),"pelvisRadians":_angle_span(samples,"pelvis"),"lowerBodyRadians":stance_angle,"shoulderTravelMeters":_distance_span(samples,"armR")}
	_check(metrics.handTravelMeters>0.08,context+"/attack","The actual weapon-hand endpoint traverses an attack arc")
	_check(metrics.spineRadians>0.04,context+"/attack","The trunk participates in attack rotation")
	_check(metrics.pelvisTravelMeters>0.005 or metrics.pelvisRadians>0.015,context+"/attack","An attack visibly transfers body weight")
	_check(stance_angle>0.025,context+"/attack","Attack posture flexes a knee or hip, not only its arms")
	_check(metrics.shoulderTravelMeters>0.015,context+"/attack","Attack follows through at the shoulder")
	return metrics

func _rowing(actor: Node3D, context: String) -> Dictionary:
	var samples: Array = []
	var oar_tips: Array = []
	var maximum_grip_gap = 0.0
	for frame in range(25):
		actor.apply_state(_state("walk",float(frame)*2.1/24.0,true))
		samples.append(_snapshot(actor))
		oar_tips.append(actor.bones.oarL.global_transform*Vector3(-0.32,-0.06,0.30))
		for side in [-1,1]:
			var suffix = "L" if side<0 else "R"
			var oar: Node3D = actor.bones["oar"+suffix]
			var start = oar.global_position
			var end = oar.global_transform*Vector3(float(side)*0.32,-0.06,0.30)
			var hand = actor.bones["hand"+suffix].global_position
			var t = clampf((hand-start).dot(end-start)/(end-start).length_squared(),0.0,1.0)
			maximum_grip_gap = maxf(maximum_grip_gap,hand.distance_to(start.lerp(end,t)))
	var tip_span = 0.0
	for a in oar_tips:
		for b in oar_tips: tip_span=maxf(tip_span,a.distance_to(b))
	var metrics = {"oarTipMeters":tip_span,"handMeters":maxf(_distance_span(samples,"handL"),_distance_span(samples,"handR")),"trunkRadians":_angle_span(samples,"torso"),"legRadians":_angle_span(samples,"thighL"),"footDeckTravelMeters":_distance_span(samples,"footL"),"boatShown":actor.boat.visible,"maxHandToOarSegmentMeters":maximum_grip_gap}
	_check(actor.boat.visible,context+"/rowing","Sailing shows the actual boat")
	_check(tip_span>0.05,context+"/rowing","The actual oar blade endpoint moves through water")
	_check(metrics.handMeters>0.025,context+"/rowing","Hands participate in the rowing stroke")
	_check(metrics.trunkRadians>0.045,context+"/rowing","The trunk leans with rowing, instead of moving only separate oars")
	_check(metrics.footDeckTravelMeters<0.04,context+"/rowing","Rowing braces feet on the boat instead of a walking foot cycle")
	actor.apply_state(_state("walk",0.2,false))
	_check(not actor.boat.visible,context+"/landing","A land pose hides the sailing boat")
	return metrics

func _death(actor: Node3D, context: String) -> Dictionary:
	var samples: Array = []
	for frame in range(21):
		actor.apply_state(_state("death",float(frame)*0.72/20.0))
		samples.append(_snapshot(actor))
	var head_drop: float = samples[0].head.point.y-samples[-1].head.point.y
	var trunk_angle = _angle_span(samples,"torso",true)
	var metrics = {"headDropMeters":head_drop,"trunkWorldRadians":trunk_angle,"kneeRadians":maxf(_angle_span(samples,"shinL"),_angle_span(samples,"shinR"))}
	_check(head_drop>0.50,context+"/death","The actual head descends as the full body falls")
	_check(trunk_angle>0.70,context+"/death","The trunk falls toward the ground")
	_check(metrics.kneeRadians>0.08,context+"/death","Knees participate in collapse")
	return metrics

func _live_ground_walk() -> Array:
	var troops = Troops.new()
	root.add_child(troops)
	troops.set_field_size(Vector2(1100,620))
	var maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	troops.set_stage(maps[0])
	# This existing probe explicitly measures a flat treadmill. Historical
	# stage one now has hill relief; use a flat test height grid, not world Y=0
	# against actual hills. Uneven ground has its separate terrain-motion QA.
	troops.battlefield.heights.fill(0.0)
	await process_frame
	var samples: Dictionary = {}
	var sole_cache: Dictionary = {}
	var statistics: Dictionary = {}
	var last_sources: Array = []
	for type_name in TYPES:
		samples[type_name] = []
		statistics[type_name] = {"contactPairs":0,"travelDuringContact":0.0,"contactTime":0.0,"lowestSoleY":INF,"clockDelivered":true}
	for frame in range(61):
		var clock = float(frame)*1.8/60.0
		var sources: Array = []
		for index in range(TYPES.size()):
			sources.append({"id":index+1,"type":TYPES[index],"friendly":false,"x":0.18+0.12*index,"y":0.60-0.4*clock/troops.world_depth,"animation":"walk","animationClock":clock,"animationPhase":0.0,"motionTime":clock,"aimX":0.0,"aimY":-1.0,"sailing":false,"hitClock":0.0})
		troops.manual_states = sources
		troops.sync_actor_states(sources)
		last_sources = sources
		for index in range(TYPES.size()):
			var type_name = TYPES[index]
			var actor: Node3D = troops.actors["%d:0" % (index+1)]
			var feet: Array = ["horse_calf0","horse_calf1","horse_calf2","horse_calf3"] if type_name=="commander" else ["footL","footR"]
			if not sole_cache.has(type_name):
				var pieces: Array = []
				for key in feet: pieces.append(_sole_vertices(actor,key))
				sole_cache[type_name] = pieces
			var frame_data: Array = []
			for foot in range(feet.size()):
				var y = _sole_height(sole_cache[type_name][foot])
				statistics[type_name].lowestSoleY = minf(statistics[type_name].lowestSoleY,y)
				var endpoint: Vector3 = actor.bones[feet[foot]].global_transform*Vector3(0,-0.376,-0.014) if type_name=="commander" else actor.bones[feet[foot]].global_position
				frame_data.append({"point":endpoint,"height":y})
				if frame>0:
					var previous: Dictionary = samples[type_name][-1][foot]
					if absf(y)<0.020 and absf(float(previous.height))<0.020:
						var displacement: Vector3 = frame_data[-1].point-previous.point
						statistics[type_name].travelDuringContact += Vector2(displacement.x,displacement.z).length()
						statistics[type_name].contactTime += 1.8/60.0
						statistics[type_name].contactPairs += 1
			samples[type_name].append(frame_data)
			statistics[type_name].clockDelivered = bool(statistics[type_name].clockDelivered) and bool(actor.current_state.get("groundMotion",false)) and actor.current_state.has("locomotionPhase") and actor.current_state.has("travelSpeed")
	var paused_poses: Dictionary = {}
	for index in range(TYPES.size()): paused_poses[TYPES[index]] = _snapshot(troops.actors["%d:0" % (index+1)])
	for unused in range(3):
		await process_frame
		troops.sync_actor_states(last_sources)
	for index in range(TYPES.size()):
		_check(_max_pose_difference(paused_poses[TYPES[index]],_snapshot(troops.actors["%d:0" % (index+1)]))<0.00005,TYPES[index]+"/renderer","Pausing the real renderer does not alter its planted pose")
	var result: Array = []
	for type_name in TYPES:
		var info: Dictionary = statistics[type_name]
		info["type"] = type_name
		info["rootSpeedMetersPerSecond"] = 0.4
		info["meanPlantedFootSpeedMetersPerSecond"] = float(info.travelDuringContact)/maxf(float(info.contactTime),0.0001)
		_check(bool(info.clockDelivered),type_name+"/renderer","Renderer delivers world-motion data to the actor")
		_check(int(info.contactPairs)>12,type_name+"/renderer","Real translating actors have measurable stance intervals")
		_check(float(info.lowestSoleY)>=-0.015,type_name+"/renderer","World-motion IK avoids shoe/hoof ground penetration")
		_check(float(info.meanPlantedFootSpeedMetersPerSecond)<0.20,type_name+"/renderer","Planted feet travel less than half the .4m/s body velocity")
		result.append(info)
	troops.queue_free()
	await process_frame
	return result
