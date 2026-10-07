extends SceneTree
## Observes real joint positions, weapon direction and mesh soles.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja","enemy_light","enemy_heavy"]
var checks: int = 0
var failures: Array = []
var observations: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		if failures.size()<30: push_error("WEIGHTY MOTION: "+message)

func state(animation: String, clock: float, duration: float=.5) -> Dictionary:
	return {"animation":animation,"animationClock":clock,"attackDuration":duration,"animationPhase":0.0,"aimX":0.0,"aimY":-1.0,"sailing":false,"hitClock":0.0}

func snapshot(actor: Node3D) -> Dictionary:
	var result: Dictionary={}
	for key in actor.bones:
		result[key]={"position":actor.bones[key].global_position,"rotation":actor.bones[key].global_basis.get_rotation_quaternion()}
	return result

func max_joint_delta(a: Dictionary,b: Dictionary) -> float:
	var result: float=0.0
	for key in a: result=maxf(result,a[key].position.distance_to(b[key].position))
	return result

func soles(actor: Node3D) -> Array:
	var result: Array=[]
	for mesh in actor.meshes:
		if str(mesh.get_parent().name) not in ["footL","footR"]: continue
		for surface in range(mesh.mesh.get_surface_count()):
			result.append({"instance":mesh,"vertices":mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]})
	return result

func floor_height(pieces: Array) -> float:
	var result: float=INF
	for piece in pieces:
		for vertex in piece.vertices: result=minf(result,(piece.instance.global_transform*vertex).y)
	return result

func test_actor(id: String, evolution: int) -> void:
	var actor: Node3D=Actor.new()
	root.add_child(actor)
	actor.configure(id,id.begins_with("enemy"),19,false,evolution)
	var prefix: String=id+" evo"+str(evolution)
	var pieces: Array=soles(actor)
	var idle_min: Vector3=Vector3(INF,INF,INF)
	var idle_max: Vector3=Vector3(-INF,-INF,-INF)
	for frame in range(61):
		actor.apply_state(state("idle",frame/20.0))
		idle_min=idle_min.min(actor.rig.position)
		idle_max=idle_max.max(actor.rig.position)
	check(idle_max.x-idle_min.x<=.007,prefix+": standing lateral sway stays under 7mm")
	check(idle_max.y-idle_min.y<=.004,prefix+": idle vertical breathing stays under 4mm")
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/units-animated/manifest.json"))
	var impact: float=float(manifest.impactFrames.get(id,4 if id in ["archer","samurai"] else 3))/float(manifest.animations.attack.frames)
	for duration in ([.5,.24] if id=="ninja" else [.5]):
		actor.apply_state(state("idle",0))
		var guard: Dictionary=snapshot(actor)
		var before: Dictionary={}
		var largest_step: float=0
		var lowest_sole: float=INF
		var lowest_body: float=INF
		var highest_body: float=-INF
		var largest_grip_gap: float=0
		var earliest_forward: float=0
		for frame in range(61):
			var normalized: float=frame/60.0
			actor.apply_state(state("attack",normalized*duration,duration))
			var current: Dictionary=snapshot(actor)
			if frame==0: check(max_joint_delta(guard,current)<.035,prefix+": attack enters its guard pose without a joint jump")
			if not before.is_empty(): largest_step=maxf(largest_step,max_joint_delta(before,current))
			before=current
			lowest_body=minf(lowest_body,actor.rig.position.y)
			highest_body=maxf(highest_body,actor.rig.position.y)
			if id!="commander": lowest_sole=minf(lowest_sole,floor_height(pieces))
			if id in ["spear","samurai","naginata","enemy_light","gunner"]:
				var desired: Vector3=actor.bones.weapon.global_transform*Vector3(0,.14 if id=="gunner" else .065 if id=="samurai" else .13,0)
				var palm: Vector3=actor.bones.handL.global_transform*Vector3(0,-.03,-.005)
				largest_grip_gap=maxf(largest_grip_gap,palm.distance_to(desired))
			if normalized<impact*.40 and id not in ["archer","gunner"]:
				earliest_forward=maxf(earliest_forward,-actor.bones.weapon.global_basis.y.normalized().z)
			for key in actor.bones:
				check(actor.bones[key].global_position.is_finite() and actor.bones[key].global_basis.is_finite(),prefix+": finite joint transforms")
		check(largest_step<.105,prefix+": per-frame joint motion has no discontinuous swing")
		check(highest_body-lowest_body<.025,prefix+": attack body does not bounce more than 25mm")
		if id!="commander": check(lowest_sole>=-.015,prefix+": real shoe mesh stays on the ground")
		if id in ["spear","samurai","naginata","enemy_light","gunner"]: check(largest_grip_gap<.04,prefix+": both hands remain attached to the actual weapon")
		var recovered: Dictionary=snapshot(actor)
		check(max_joint_delta(guard,recovered)<.035,prefix+": recovery returns to the same guard pose")
		actor.apply_state(state("attack",impact*duration,duration))
		if id=="monk":
			check(str(actor.motion_debug.mode)=="idle" and float(actor.motion_debug.get("supportGesture",0))==0,prefix+": legacy attack remains a passive support stance without a fake strike")
		else:
			check(is_equal_approx(float(actor._attack_phases(state("attack",impact*duration,duration),impact*duration).drive),1.0),prefix+": physical strike peaks at the engine release frame")
		if id not in ["archer","gunner","monk"]:
			check((-actor.bones.weapon.global_basis.y.normalized().z)>.86,prefix+": blade or pole faces the enemy at damage release")
		var frozen: Dictionary=snapshot(actor)
		actor.apply_state(state("attack",impact*duration,duration))
		check(max_joint_delta(frozen,snapshot(actor))<.00001,prefix+": repeated frozen phase leaves every endpoint unchanged")
		observations.append({"type":id,"evolution":evolution,"duration":duration,"releasePhase":impact,"maxJointStepMeters":largest_step,"bodyVerticalSpanMeters":highest_body-lowest_body,"minimumSoleY":lowest_sole if id!="commander" else 0.0,"maxGripGapMeters":largest_grip_gap})
	for yaw in [-TAU-.01,-PI+.01,PI-.01,TAU+.01]:
		var data: Dictionary=state("walk",.23)
		data.visualYaw=yaw
		actor.apply_state(data)
		check(actor.global_basis.is_finite(),prefix+": negative and wrapped yaw remains finite")
		check(absf(actor.rotation.y)<=PI+.001,prefix+": facing is normalized through the negative wrap boundary")
	if id!="commander":
		for frame in range(13):
			actor.position=Vector3(0,0,-float(frame)*.004)
			var moving: Dictionary=state("walk",.12+float(frame)/60.0)
			moving.groundMotion=true
			moving.visualYaw=-.2
			actor.apply_state(moving)
		var planted: Dictionary={"L":actor.bones.footL.global_position,"R":actor.bones.footR.global_position}
		var planted_drift: float=0.0
		for frame in range(31):
			var attack: Dictionary=state("attack",float(frame)/60.0)
			attack.groundMotion=true
			attack.visualYaw=-.2
			actor.apply_state(attack)
			for side in ["L","R"]:
				var foot: Vector3=actor.bones["foot"+side].global_position
				planted_drift=maxf(planted_drift,Vector2(foot.x,foot.z).distance_to(Vector2(planted[side].x,planted[side].z)))
		check(planted_drift<.01,prefix+": stopping from real walking preserves world-space foot placement during the strike")
	actor.free()

func capture_sheet() -> void:
	if DisplayServer.get_name()=="headless": return
	var viewport=SubViewport.new()
	viewport.size=Vector2i(1600,1900)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_2X
	root.add_child(viewport)
	var world=Node3D.new()
	viewport.add_child(world)
	var environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("282b28")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("c5c5b9")
	environment.ambient_light_energy=.58
	var node=WorldEnvironment.new()
	node.environment=environment
	world.add_child(node)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-46,130,0)
	sun.light_energy=1.1
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=60
	world.add_child(sun)
	var floor_mesh=MeshInstance3D.new()
	var plane=PlaneMesh.new()
	plane.size=Vector2(20,31)
	floor_mesh.mesh=plane
	var material=StandardMaterial3D.new()
	material.albedo_color=Color("696d63")
	material.roughness=1
	floor_mesh.material_override=material
	world.add_child(floor_mesh)
	var camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=18.7
	camera.position=Vector3(0,28,-20)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	var canvas=CanvasLayer.new()
	viewport.add_child(canvas)
	var heading=Label.new()
	heading.text="GUARD  /  PREPARATION  /  DAMAGE RELEASE  /  RECOVERY  /  GUARD"
	heading.position=Vector2(18,12)
	heading.add_theme_font_size_override("font_size",22)
	canvas.add_child(heading)
	for row in range(8):
		var id: String=TYPES[row]
		var impact: float=2.0/3.0 if id in ["archer","samurai"] else .5
		var clocks: Array=[0.0,impact*.45,impact,impact+(1-impact)*.50,1.0]
		for column in range(5):
			var actor=Actor.new()
			world.add_child(actor)
			actor.configure(id,false,19,false,1)
			actor.position=Vector3(6.8-column*3.4,0,11.55-row*3.3)
			actor.apply_state(state("attack",float(clocks[column])*.5))
		var label=Label.new()
		label.text=id
		label.position=Vector2(12,camera.unproject_position(Vector3(0,0,11.55-row*3.3)).y+18)
		label.add_theme_font_size_override("font_size",18)
		canvas.add_child(label)
	for unused in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var path: String="user://preview-weighty-motion-attack.png" if OS.get_cmdline_user_args().has("--packed") else "res://dist/preview-weighty-motion-attack.png"
	check(viewport.get_texture().get_image().save_png(path)==OK,"Actual GPU attack phase contact sheet saves")
	print("WEIGHTY_MOTION_CAPTURE ",path," ",RenderingServer.get_video_adapter_name())
	viewport.queue_free()
	await process_frame

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/weighty-motion/"):
		push_error("Weighty motion QA refuses a player profile")
		quit(2)
		return
	for id in TYPES:
		for evolution in ([0,1,2] if not id.begins_with("enemy") else [0]): test_actor(id,evolution)
	if OS.get_cmdline_user_args().has("--capture"): await capture_sheet()
	var report_path: String="user://qa_weighty_motion.json" if OS.get_cmdline_user_args().has("--packed") else "res://tests/qa_weighty_motion.json"
	var output=FileAccess.open(report_path,FileAccess.WRITE)
	check(output!=null,"QA report opens")
	if output!=null:
		output.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"Observed real joints, weapon grip/forward direction at engine release, real shoe contact, reduced idle/body movement, normalized ninja time, recovery continuity and negative yaw; no claim of motion capture."},"  "))
		output.close()
	print("WEIGHTY_MOTION_QA ",JSON.stringify({"checks":checks,"failures":failures,"samples":observations.size()}))
	quit(0 if failures.is_empty() else 1)
