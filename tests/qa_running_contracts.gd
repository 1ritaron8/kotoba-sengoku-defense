extends SceneTree
## Observes real rendered feet, knees and body endpoints through the renderer.
## Probe speeds are inputs; no animation formula is copied into the assertions.

const Troops = preload("res://native/troops_3d.gd")
const Game = preload("res://native/game.gd")
const HUMAN_TYPES = ["archer", "spear", "samurai", "gunner", "naginata", "monk", "ninja", "enemy_light", "enemy_heavy"]
var checks: int = 0
var failures: Array = []
var observations: Array = []
var human_speed: float = 0.0
var horse_speed: float = 0.0

class FlatGround extends Node3D:
	var width: float=18.5
	var depth: float=13.0
	func configure(_stage: Dictionary, world_width: float, world_depth: float, _elevation: float) -> void:
		width=world_width;depth=world_depth
	func world_point(point: Vector2) -> Vector3:
		return Vector3((point.x-.5)*width,0,(point.y-.5)*depth)
	func height_at(_point: Vector2) -> float: return 0.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		if failures.size() <= 30:
			push_error("RUNNING QA: " + note)

func argument(name_value: String, fallback: float) -> float:
	for value in OS.get_cmdline_user_args():
		if str(value).begins_with(name_value + "="):
			return float(str(value).get_slice("=", 1))
	return fallback

func string_argument(name_value: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if str(value).begins_with(name_value + "="):
			return str(value).get_slice("=", 1)
	return fallback

func scan_engine_errors() -> Dictionary:
	var path: String = string_argument("--qa-log", "")
	var args: PackedStringArray = OS.get_cmdline_args()
	for index in range(args.size() - 1):
		if path.is_empty() and str(args[index]) == "--log-file":
			path = str(args[index + 1])
	if path.is_empty():
		return {"checked":false, "count":0, "examples":[], "reason":"Supply --qa-log in user arguments to scan the current --log-file"}
	var count: int = 0
	var examples: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var value: String = str(line).strip_edges()
		if value == "ERROR: Failed to read the root certificate store.":
			continue
		if value.begins_with("ERROR: RUNNING QA:"):
			continue
		if value.begins_with("ERROR:") or value.begins_with("SCRIPT ERROR:"):
			count += 1
			if examples.size() < 3:
				examples.append(value)
	return {"checked":true, "count":count, "examples":examples, "ignoredEnvironmentError":"Windows root certificate store warning"}

func source(type_name: String, clock: float, point: Vector2, direction: Vector2, animation: String = "walk") -> Dictionary:
	return {"id":19, "type":type_name, "friendly":not type_name.begins_with("enemy"), "x":point.x, "y":point.y, "aimX":direction.x, "aimY":direction.y, "animation":animation, "animationClock":clock, "animationPhase":0.0, "motionTime":clock, "sailing":false, "hitClock":0.0}

func make_troops(flat_ground: bool=false) -> Control:
	var troops: Control = Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(1100, 620))
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	troops.set_stage(maps[0])
	# Steady/rate formulas describe a measured constant speed on a plane.
	# Turn/stop probes retain the actual map and its sampled terrain contact.
	if flat_ground: troops.set_terrain_provider(FlatGround.new())
	return troops

func render(troops: Control, data: Dictionary) -> Node3D:
	troops.manual_states = [data]
	troops.sync_actor_states([data])
	return troops.actors["19:0"]

func soles(actor: Node3D) -> Array:
	var feet: Array = ["horse_calf0", "horse_calf1", "horse_calf2", "horse_calf3"] if actor.unit_type == "commander" else ["footL", "footR"]
	var result: Array = []
	for name_value in feet:
		var pieces: Array = []
		for mesh in actor.meshes:
			if str(mesh.get_parent().name) != name_value:
				continue
			for surface in range(mesh.mesh.get_surface_count()):
				pieces.append({"instance":mesh, "vertices":mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]})
		result.append({"name":name_value, "pieces":pieces})
	return result

func sole_height(pieces: Array) -> float:
	var result: float = INF
	for piece in pieces:
		for vertex in piece.vertices:
			result = minf(result, (piece.instance.global_transform * vertex).y)
	return result

func sole_ground_clearance(actor: Node3D, pieces: Array) -> float:
	var sampler: Callable=actor.current_state.get("groundHeightSampler",Callable())
	if not sampler.is_valid(): return sole_height(pieces)-actor.global_position.y
	var result: float=INF
	for piece in pieces:
		for vertex in piece.vertices:
			var point: Vector3=piece.instance.global_transform*vertex
			result=minf(result,point.y-float(sampler.call(point)))
	return result

func snapshot(actor: Node3D) -> Dictionary:
	var result: Dictionary = {"root":actor.global_transform, "joints":{}}
	for name_value in actor.bones:
		var node: Node3D = actor.bones[name_value]
		result.joints[name_value] = {"point":node.global_position, "basis":node.global_basis, "relative":actor.to_local(node.global_position)}
	return result

func pose_difference(a: Dictionary, b: Dictionary) -> float:
	var result: float = a.root.origin.distance_to(b.root.origin)
	for name_value in a.joints:
		result = maxf(result, a.joints[name_value].point.distance_to(b.joints[name_value].point))
		for axis in range(3):
			result = maxf(result, a.joints[name_value].basis[axis].distance_to(b.joints[name_value].basis[axis]))
	return result

func knee_angle(actor: Node3D, index: int) -> float:
	if actor.unit_type == "commander":
		var upper: Node3D = actor.bones["horse_leg%d" % index]
		var lower: Node3D = actor.bones["horse_calf%d" % index]
		var hoof: Vector3 = lower.global_transform * Vector3(0, -0.376, 0)
		return (lower.global_position - upper.global_position).angle_to(hoof - lower.global_position)
	var suffix: String = "L" if index == 0 else "R"
	var thigh: Node3D = actor.bones["thigh" + suffix]
	var shin: Node3D = actor.bones["shin" + suffix]
	var foot: Node3D = actor.bones["foot" + suffix]
	return (shin.global_position - thigh.global_position).angle_to(foot.global_position - shin.global_position)

func metrics(samples: Array, scale_value: float, dt: float) -> Dictionary:
	var minimum_sole: float = INF
	var maximum_clearance: float = -INF
	var flight_frames: int = 0
	var contact_frames: int = 0
	var contact_distance: float = 0.0
	var contact_seconds: float = 0.0
	var body_min: float = INF
	var body_max: float = -INF
	var rider_min: float = INF
	var rider_max: float = -INF
	var maximum_knee: float = 0.0
	var minimum_knee: float = INF
	var landings: Array = []
	var heights: Array = []
	var knees: Array = []
	for unused in samples[0].feet:
		landings.append([])
		heights.append({"minimum":INF, "maximum":-INF})
		knees.append({"minimum":INF, "maximum":-INF})
	for index in range(samples.size()):
		var frame: Dictionary = samples[index]
		var lowest: float = INF
		body_min = minf(body_min, float(frame.bodyHeight))
		body_max = maxf(body_max, float(frame.bodyHeight))
		rider_min = minf(rider_min, float(frame.riderHeight))
		rider_max = maxf(rider_max, float(frame.riderHeight))
		for leg in range(frame.feet.size()):
			var foot: Dictionary = frame.feet[leg]
			minimum_sole = minf(minimum_sole, float(foot.height))
			lowest = minf(lowest, float(foot.height))
			heights[leg].minimum = minf(float(heights[leg].minimum), float(foot.height))
			heights[leg].maximum = maxf(float(heights[leg].maximum), float(foot.height))
			maximum_knee = maxf(maximum_knee, float(foot.knee))
			minimum_knee = minf(minimum_knee, float(foot.knee))
			knees[leg].minimum = minf(float(knees[leg].minimum), float(foot.knee))
			knees[leg].maximum = maxf(float(knees[leg].maximum), float(foot.knee))
			if index > 0:
				var previous: Dictionary = samples[index - 1].feet[leg]
				if bool(foot.contact) and not bool(previous.contact):
					landings[leg].append(float(frame.time))
				if bool(foot.contact) and bool(previous.contact):
					var displacement: Vector3 = foot.point - previous.point
					contact_distance += Vector2(displacement.x, displacement.z).length()
					contact_seconds += dt
		maximum_clearance = maxf(maximum_clearance, lowest)
		if lowest > 0.012 * scale_value:
			flight_frames += 1
		else:
			contact_frames += 1
	var result: Dictionary = {"samples":samples.size(), "minimumSoleWorldMeters":minimum_sole, "allFeetClearanceModelMeters":maximum_clearance / scale_value, "flightFrameRatio":float(flight_frames) / samples.size(), "contactFrameRatio":float(contact_frames) / samples.size(), "bodyVerticalSpanModelMeters":body_max - body_min, "riderVerticalSpanModelMeters":rider_max - rider_min, "kneeMaximumRadians":maximum_knee, "kneeSpanRadians":maximum_knee - minimum_knee, "kneeRanges":knees, "meanPlantedEndpointSpeedWorldMetersPerSecond":contact_distance / maxf(contact_seconds, 0.00001), "contactPairSeconds":contact_seconds, "landingTimes":landings, "footHeightRanges":heights, "scale":scale_value}
	return result

func observe(actor: Node3D, pieces: Array, clock: float) -> Dictionary:
	var feet: Array = []
	var scale_value: float = actor.global_basis.get_scale().y
	var finite: bool = actor.global_transform.is_finite()
	for name_value in actor.bones:
		finite = finite and actor.bones[name_value].global_transform.is_finite()
	check(finite, actor.unit_type + ": all joint transforms remain finite")
	for index in range(pieces.size()):
		var info: Dictionary = pieces[index]
		var height: float = sole_ground_clearance(actor,info.pieces)
		var point: Vector3 = actor.bones[info.name].global_position
		if actor.unit_type == "commander":
			point = actor.bones[info.name].global_transform * Vector3(0, -0.376, 0)
		feet.append({"point":point, "height":height, "contact":absf(height) <= 0.012 * scale_value, "knee":knee_angle(actor, index)})
	var body: String = "mount" if actor.unit_type == "commander" else "pelvis"
	return {"time":clock, "root":actor.global_position, "feet":feet, "bodyHeight":actor.to_local(actor.bones[body].global_position).y, "riderHeight":actor.to_local(actor.rig.global_position).y}

func steady_probe(type_name: String, model_speed: float, animation: String = "walk", world_speed_input: bool = false) -> Dictionary:
	var troops: Control = make_troops(true)
	var point: Vector2 = Vector2(0.12, 0.58)
	var direction: Vector2 = Vector2.RIGHT
	var actor: Node3D = render(troops, source(type_name, 0.0, point, direction, animation))
	var scale_value: float = actor.scale.y
	if world_speed_input:
		model_speed /= scale_value
	var pieces: Array = soles(actor)
	var samples: Array = []
	var dt: float = 1.0 / 120.0
	for index in range(721):
		var clock: float = float(index) * dt
		if index > 0:
			point.x += model_speed * scale_value * dt / troops.world_width
		actor = render(troops, source(type_name, clock, point, direction, animation))
		if index >= 120:
			samples.append(observe(actor, pieces, clock))
	var result: Dictionary = metrics(samples, scale_value, dt)
	result["type"] = type_name
	result["animation"] = animation
	result["requestedModelSpeed"] = model_speed
	result["rootSpeedWorldMetersPerSecond"] = model_speed * scale_value
	result["observedPhase"] = float(actor.current_state.get("locomotionPhase", 0.0))
	result["motionDebug"] = actor.motion_debug.duplicate(true)
	result["runBlend"] = actor.current_state.get("runBlend", -1.0)
	result["localTravelSpeed"] = actor.current_state.get("localTravelSpeed", -1.0)
	result["locomotionCadence"] = actor.current_state.get("locomotionCadence", -1.0)
	result["strideLength"] = actor.current_state.get("strideLength", -1.0)
	result["travelVelocity"] = str(actor.current_state.get("travelVelocity", Vector3.ZERO))
	check(float(result.minimumSoleWorldMeters) >= -0.015, type_name + ": actual soles stay above the flat ground within 15mm")
	troops.free()
	return result

func check_running(result: Dictionary) -> void:
	var type_name: String = result.type
	var mounted: bool = type_name == "commander"
	var flight: float = float(result.flightFrameRatio)
	check(flight > 0.035 and flight < 0.45, type_name + ": the real soles include both supported and airborne running frames")
	check(float(result.allFeetClearanceModelMeters) > 0.025, type_name + ": suspension visibly clears every shoe or hoof above the ground")
	check(float(result.bodyVerticalSpanModelMeters) > 0.035 and float(result.bodyVerticalSpanModelMeters) < 0.15, type_name + ": the moving pelvis or horse has a readable vertical running impulse")
	check(float(result.meanPlantedEndpointSpeedWorldMetersPerSecond) < float(result.rootSpeedWorldMetersPerSecond) * 0.35, type_name + ": supported feet move substantially less than the advancing body")
	check(float(result.runBlend) > 0.99 and absf(float(result.localTravelSpeed) - float(result.requestedModelSpeed)) < 0.02, type_name + ": renderer delivers steady run intensity and size-normalized speed")
	check(float(result.locomotionCadence) > 1.2 and float(result.strideLength) > 0.25, type_name + ": the renderer delivers a finite cadence and a useful stride length")
	for leg in range(result.landingTimes.size()):
		var times: Array = result.landingTimes[leg]
		var height: Dictionary = result.footHeightRanges[leg]
		var knee: Dictionary = result.kneeRanges[leg]
		check(times.size() >= 5, type_name + ": leg " + str(leg) + " repeatedly plants after its recovery swing")
		check((float(height.maximum) - float(height.minimum)) / float(result.scale) > 0.09, type_name + ": leg " + str(leg) + " actually lifts its rendered foot")
		check(float(knee.maximum) - float(knee.minimum) > 0.25, type_name + ": leg " + str(leg) + " flexes through a running cycle")
		if times.size() > 1:
			var observed_cadence: float = float(times.size() - 1) / (float(times[-1]) - float(times[0]))
			check(observed_cadence > 1.2 and observed_cadence < 2.35, type_name + ": observed landing cycles run at a readable normal-speed cadence")
			result["observedCadenceLeg" + str(leg)] = observed_cadence
	if mounted:
		check(float(result.riderVerticalSpanModelMeters) > 0.045 and float(result.riderVerticalSpanModelMeters) < 0.17, "commander: the rider rises and settles with the horse")
		var events: Array = []
		for leg in range(result.landingTimes.size()):
			for time_value in result.landingTimes[leg]:
				events.append({"time":time_value, "leg":leg})
		events.sort_custom(func(a, b): return float(a.time) < float(b.time))
		var wrong_order: int = 0
		var next_leg: Dictionary = {2:3, 3:0, 0:1, 1:2}
		for index in range(1, events.size()):
			if int(events[index].leg) != int(next_leg[int(events[index - 1].leg)]):
				wrong_order += 1
		check(events.size() >= 20 and wrong_order == 0, "commander: real hoof landings follow hind-left, hind-right, front-left, front-right")
		result["observedLandingEvents"] = events
		result["landingOrderViolations"] = wrong_order

func frozen_probe(type_name: String, model_speed: float) -> Dictionary:
	var troops: Control = make_troops()
	var point: Vector2 = Vector2(0.18, 0.58)
	var actor: Node3D = render(troops, source(type_name, 0.0, point, Vector2.RIGHT))
	var scale_value: float = actor.scale.y
	var data: Dictionary = {}
	for index in range(1, 122):
		point.x += model_speed * scale_value / 120.0 / troops.world_width
		data = source(type_name, float(index) / 120.0, point, Vector2.RIGHT)
		actor = render(troops, data)
	var before: Dictionary = snapshot(actor)
	var before_state: Dictionary = actor.current_state.duplicate(true)
	var largest_difference: float = 0.0
	for unused in range(8):
		await process_frame
		actor = render(troops, data)
		largest_difference = maxf(largest_difference, pose_difference(before, snapshot(actor)))
	check(largest_difference < 0.00005, type_name + ": frozen running time preserves endpoints and bases on repeated renderer calls")
	for field in ["runBlend", "localTravelSpeed", "locomotionCadence", "strideLength", "travelVelocity", "locomotionPhase", "travelSpeed"]:
		check(before_state.has(field) and actor.current_state.get(field) == before_state.get(field), type_name + ": frozen renderer calls preserve " + field)
	var result: Dictionary = {"probe":"running-pause", "type":type_name, "largestWorldPoseDifference":largest_difference, "phaseBefore":before_state.get("locomotionPhase", -1.0), "phaseAfter":actor.current_state.get("locomotionPhase", -1.0), "speedBefore":before_state.get("travelSpeed", -1.0), "speedAfter":actor.current_state.get("travelSpeed", -1.0), "debugBefore":before_state.get("runBlend", -1.0), "debugAfter":actor.current_state.get("runBlend", -1.0)}
	troops.free()
	return result

func stop_probe(type_name: String, model_speed: float, instantaneous: bool = false) -> Dictionary:
	var troops: Control = make_troops()
	var point: Vector2 = Vector2(0.12, 0.58)
	var initial_animation: String = "idle" if instantaneous else "walk"
	var actor: Node3D = render(troops, source(type_name, 0.0, point, Vector2.RIGHT, initial_animation))
	var scale_value: float = actor.scale.y
	var pieces: Array = soles(actor)
	var previous: Dictionary = snapshot(actor)
	var largest_step: float = 0.0
	var largest_step_detail: Dictionary = {}
	var minimum_sole: float = INF
	var records: Array = []
	for index in range(1, 361):
		var clock: float = float(index) / 120.0
		var speed_value: float = model_speed
		var animation: String = "walk"
		var animation_clock: float = clock
		if instantaneous:
			if clock < 0.5 or clock >= 1.5:
				speed_value = 0.0
				animation = "idle"
			animation_clock = clock - 1.5 if clock >= 1.5 else clock - 0.5 if clock >= 0.5 else clock
		else:
			if clock < 0.4:
				speed_value *= clock / 0.4
			elif clock >= 1.5:
				speed_value *= maxf(0.0, 1.0 - (clock - 1.5) / 0.35)
			if clock >= 1.85:
				animation = "idle"
				animation_clock = clock - 1.85
		point.x += speed_value * scale_value / 120.0 / troops.world_width
		var data: Dictionary = source(type_name, clock, point, Vector2.RIGHT, animation)
		data.animationClock = animation_clock
		actor = render(troops, data)
		var current: Dictionary = snapshot(actor)
		for name_value in current.joints:
			var joint_step: float = current.joints[name_value].relative.distance_to(previous.joints[name_value].relative)
			if joint_step > largest_step:
				largest_step = joint_step
				largest_step_detail = {"time":clock, "joint":name_value, "animation":animation, "requestedSpeed":speed_value, "runBlend":actor.current_state.get("runBlend", -1.0), "phase":actor.current_state.get("locomotionPhase", -1.0), "beforeLocal":str(previous.joints[name_value].relative), "afterLocal":str(current.joints[name_value].relative)}
		previous = current
		var frame: Dictionary = observe(actor, pieces, clock)
		for foot in frame.feet:
			minimum_sole = minf(minimum_sole, float(foot.height))
		if index % 30 == 0:
			records.append({"time":clock, "requestedSpeed":speed_value, "animation":animation, "deliveredSpeed":actor.current_state.get("travelSpeed", -1.0), "phase":actor.current_state.get("locomotionPhase", -1.0), "motionDebug":actor.motion_debug.duplicate(true)})
	check(minimum_sole >= -0.015, type_name + ": accelerating and stopping do not penetrate the flat ground")
	check(largest_step < 0.13, type_name + ": acceleration and stopping do not snap a joint by more than 13cm at 120 simulation samples per second")
	var stopped: Dictionary = snapshot(actor)
	var final_data: Dictionary = source(type_name, 3.0, point, Vector2.RIGHT, "idle")
	final_data.animationClock = 3.0 - (1.5 if instantaneous else 1.85)
	actor = render(troops, final_data)
	check(pose_difference(stopped, snapshot(actor)) < 0.00005, type_name + ": a stopped frozen pose remains deterministic")
	var result: Dictionary = {"probe":"instantaneous-movement-start-stop" if instantaneous else "acceleration-stop", "type":type_name, "largestRelativeJointStepModelMeters":largest_step, "largestStepDetail":largest_step_detail, "minimumSoleWorldMeters":minimum_sole, "records":records}
	troops.free()
	return result

func turn_probe(type_name: String, model_speed: float, multiplier: float=1.0) -> Dictionary:
	var troops: Control = make_troops()
	var point: Vector2 = Vector2(0.35, 0.50)
	var direction: Vector2 = Vector2.RIGHT
	var actor: Node3D = render(troops, source(type_name, 0.0, point, direction))
	var scale_value: float = actor.scale.y
	var pieces: Array = soles(actor)
	var previous_yaw: float = actor.rotation.y
	var largest_yaw_step: float = 0.0
	var minimum_sole: float = INF
	var minimum_detail: Dictionary={}
	var contact_frames: int=0
	var samples: Array = []
	for index in range(1,roundi(360.0/multiplier)+1):
		var clock: float = float(index)*multiplier / 120.0
		if clock >= 2.2:
			direction = Vector2(0.015, 1.0).normalized()
		elif clock >= 1.8:
			direction = Vector2(-0.015, 1.0).normalized()
		elif clock >= 1.0:
			direction = Vector2.DOWN
		point += Vector2(direction.x / troops.world_width, direction.y / troops.world_depth) * model_speed * scale_value * multiplier / 120.0
		actor = render(troops, source(type_name, clock, point, direction))
		largest_yaw_step = maxf(largest_yaw_step, absf(wrapf(actor.rotation.y - previous_yaw, -PI, PI)))
		previous_yaw = actor.rotation.y
		var frame: Dictionary = observe(actor, pieces, clock)
		var supported: bool=false
		for foot in frame.feet:
			supported=supported or bool(foot.contact)
			if float(foot.height)<minimum_sole: minimum_detail={"time":clock,"normalizedRoot":str(point),"worldRoot":str(actor.position),"footPoint":str(foot.point),"terrainPitch":actor.current_state.get("terrainPitch",0),"terrainRoll":actor.current_state.get("terrainRoll",0),"sampler":actor.current_state.get("groundHeightSampler",Callable()).is_valid()}
			minimum_sole = minf(minimum_sole, float(foot.height))
		if supported: contact_frames+=1
		if index % 30 == 0:
			samples.append({"time":clock, "yaw":actor.rotation.y, "aim":str(direction), "phase":actor.current_state.get("locomotionPhase", -1.0)})
	check(minimum_sole >= -0.015, type_name + ": a ninety-degree turn at "+str(multiplier)+"x keeps real soles above sampled ground (root plane when no sampler)")
	check(largest_yaw_step < 0.30, type_name + ": visual facing at "+str(multiplier)+"x turns continuously across the yaw wrap")
	var contact_ratio: float=float(contact_frames)/roundi(360.0/multiplier)
	check(contact_ratio>.15,type_name+": actual soles repeatedly plant during terrain turns rather than floating above conservative supports")
	var result: Dictionary = {"probe":"turn-and-negative-wrap", "type":type_name, "multiplier":multiplier, "largestYawStepRadians":largest_yaw_step, "minimumSoleWorldMeters":minimum_sole, "groundContactFrameRatio":contact_ratio, "minimumSoleDetail":minimum_detail, "samples":samples}
	troops.free()
	return result

func render_rate(type_name: String, model_speed: float, multiplier: float) -> Dictionary:
	var troops: Control = make_troops(true)
	var point: Vector2 = Vector2(0.12, 0.58)
	var actor: Node3D = render(troops, source(type_name, 0.0, point, Vector2.RIGHT))
	var scale_value: float = actor.scale.y
	var dt: float = multiplier / 60.0
	var frame_count: int = roundi(3.0 / dt)
	for index in range(1, frame_count + 1):
		point.x += model_speed * scale_value * dt / troops.world_width
		actor = render(troops, source(type_name, float(index) * dt, point, Vector2.RIGHT))
	var result: Dictionary = {"multiplier":multiplier, "pose":snapshot(actor), "phase":float(actor.current_state.get("locomotionPhase", -1.0)), "travelSpeed":float(actor.current_state.get("travelSpeed", -1.0)), "scale":scale_value}
	troops.free()
	return result

func rate_probe(type_name: String, model_speed: float) -> Dictionary:
	var baseline: Dictionary = render_rate(type_name, model_speed, 1.0)
	var comparisons: Array = []
	for multiplier in [2.0, 3.0]:
		var current: Dictionary = render_rate(type_name, model_speed, multiplier)
		var root_delta: float = baseline.pose.root.origin.distance_to(current.pose.root.origin)
		var phase_delta: float = absf(float(baseline.phase) - float(current.phase))
		var pose_delta: float = pose_difference(baseline.pose, current.pose)
		check(root_delta < 0.00005, type_name + ": equal simulation time gives the same root position at " + str(multiplier) + "x")
		check(phase_delta < 0.00005, type_name + ": equal simulation distance gives the same gait phase at " + str(multiplier) + "x")
		comparisons.append({"multiplier":multiplier, "rootDifferenceWorldMeters":root_delta, "phaseDifference":phase_delta, "maximumWorldPoseDifference":pose_delta, "maximumPoseDifferencePerScale":pose_delta / float(baseline.scale)})
	return {"probe":"renderer-speed-multipliers", "type":type_name, "simulationSeconds":3.0, "comparisons":comparisons}

func game_rate(multiplier: float) -> Dictionary:
	var game: Node2D = Game.new()
	root.add_child(game)
	game.set_process(false)
	game.load_map({"id":"running-contract-fixture", "initialGold":280, "unitLimit":14, "totalWaves":10, "difficulty":1.0, "paths":[{"objectiveId":"main", "points":[{"x":0.05, "y":0.5}, {"x":0.95, "y":0.5}]}], "objectives":[{"id":"main", "x":0.95, "y":0.5, "hp":10000}], "buildZones":[]})
	game.set_seed(19)
	game.set_speed(multiplier)
	game.start_battle()
	game.spawn_queue = ["raider"]
	game.spawn_source_waves = [1]
	game.spawn_clock = 100000.0
	game._spawn_enemy("runner", 1)
	game.enemies[0].position = Vector2(0.10, 0.5)
	var troops: Control = make_troops()
	troops.battle = game
	troops.sync_actor_states(game.actor_states())
	for unused in range(roundi(3.0 / multiplier * 60.0)):
		game._process(1.0 / 60.0)
		troops.sync_actor_states(game.actor_states())
	var actor: Node3D = troops.actors[str(game.enemies[0].id) + ":0"]
	var final_pose: Dictionary = snapshot(actor)
	var final_state: Dictionary = actor.current_state.duplicate(true)
	var before_enemies: Array = game.enemies.duplicate(true)
	var before_time: float = game.elapsed
	game.paused = true
	var pause_delta: float = 0.0
	for unused in range(5):
		game._process(0.1)
		troops.sync_actor_states(game.actor_states())
		pause_delta = maxf(pause_delta, pose_difference(final_pose, snapshot(actor)))
	check(game.enemies == before_enemies and game.elapsed == before_time, "Actual game pause freezes movement and its simulation clock at " + str(multiplier) + "x")
	check(pause_delta < 0.00005, "Actual game pause preserves the rendered running pose at " + str(multiplier) + "x")
	var result: Dictionary = {"multiplier":multiplier, "simulationSeconds":game.elapsed, "position":game.enemies[0].position, "phase":final_state.get("locomotionPhase", -1.0), "pose":final_pose, "pausePoseDifference":pause_delta, "scale":actor.scale.y}
	troops.free()
	game.free()
	return result

func game_rate_probe() -> Dictionary:
	var baseline: Dictionary = game_rate(1.0)
	var comparisons: Array = []
	for multiplier in [2.0, 3.0]:
		var current: Dictionary = game_rate(multiplier)
		var position_delta: float = (baseline.position as Vector2).distance_to(current.position)
		var phase_delta: float = absf(float(baseline.phase) - float(current.phase))
		var pose_delta: float = pose_difference(baseline.pose, current.pose)
		check(absf(float(current.simulationSeconds) - 3.0) < 0.00005, "Real _process delta applies the chosen " + str(multiplier) + "x speed")
		check(position_delta < 0.00005 and phase_delta < 0.00005, "Actual simulation and renderer agree at equal time at " + str(multiplier) + "x")
		comparisons.append({"multiplier":multiplier, "simulationSeconds":current.simulationSeconds, "normalizedPositionDifference":position_delta, "phaseDifference":phase_delta, "maximumWorldPoseDifference":pose_delta, "maximumPoseDifferencePerScale":pose_delta / float(current.scale), "pausePoseDifference":current.pausePoseDifference})
	return {"probe":"actual-game-process-speed-multipliers", "simulationSeconds":baseline.simulationSeconds, "normalPausePoseDifference":baseline.pausePoseDifference, "comparisons":comparisons}

func run() -> void:
	human_speed = argument("--human-speed", 1.55)
	horse_speed = argument("--horse-speed", 3.4)
	if human_speed <= 0.0 or horse_speed <= 0.0:
		push_error("Supply explicitly chosen probe inputs: -- --human-speed=<model m/s> --horse-speed=<model m/s>")
		quit(2)
		return
	var mode: String = string_argument("--probe", "all")
	var only: Array = Array(string_argument("--types", "").split(",", false))
	if mode in ["all", "steady"]:
		for type_name in HUMAN_TYPES + ["commander"]:
			if not only.is_empty() and type_name not in only:
				continue
			var result: Dictionary = steady_probe(type_name, horse_speed if type_name == "commander" else human_speed)
			check_running(result)
			observations.append(result)
	if mode in ["all", "walk"]:
		for type_name in ["spear", "commander"]:
			if not only.is_empty() and type_name not in only:
				continue
			var low_speed: Dictionary = steady_probe(type_name, 0.4, "walk", true)
			low_speed["probe"] = "slow-walk"
			check(float(low_speed.flightFrameRatio) < 0.05 and float(low_speed.contactFrameRatio) > 0.90, type_name + ": low world speed keeps a supported walking gait")
			observations.append(low_speed)
	for type_name in ["spear", "ninja", "enemy_light", "commander"]:
		if not only.is_empty() and type_name not in only:
			continue
		var model_speed: float = horse_speed if type_name == "commander" else human_speed
		if mode in ["all", "freeze"]:
			observations.append(await frozen_probe(type_name, model_speed))
		if mode in ["all", "stop"]:
			observations.append(stop_probe(type_name, model_speed))
		if mode in ["all", "instant"]:
			observations.append(stop_probe(type_name, model_speed, true))
		if mode in ["all", "turn"]:
			observations.append(turn_probe(type_name, model_speed))
			observations.append(turn_probe(type_name, model_speed,2.0))
		if mode in ["all", "rate"]:
			observations.append(rate_probe(type_name, model_speed))
	if mode in ["all", "game"]:
		observations.append(game_rate_probe())
	check(not observations.is_empty(), "At least one selected running probe executes")
	var engine_errors: Dictionary = scan_engine_errors()
	check(int(engine_errors.count) == 0, "Godot reports no runtime or script errors during the selected probes")
	var suffix: String = "final" if mode == "all" else mode
	var packed: bool = OS.get_cmdline_user_args().has("--packed")
	var report_path: String = ("user://qa_running_contracts_" if packed else "res://tests/qa_running_contracts_") + suffix + ".json"
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	check(file != null, "Running report opens")
	if file != null:
		file.store_string(JSON.stringify({"checks":checks, "failures":failures, "observations":observations, "engineErrors":engine_errors, "scope":"Real shoe/hoof vertices and joints through troops.sync_actor_states; explicit probe speeds. Steady/rate use a flat fixture; turn/stop retain the actual map and compare shoe vertices with delivered ground sampler, or the existing root plane when absent. Numerical properties alone do not establish visual realism.", "godot":Engine.get_version_info().string}, "  "))
		file.close()
	print("RUNNING_CONTRACTS_QA ", JSON.stringify({"checks":checks, "failures":failures, "probes":observations.size()}))
	quit(0 if failures.is_empty() else 1)
