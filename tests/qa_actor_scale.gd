extends SceneTree
## Visual-only sizing uses real articulated models and the production renderer.
## This is a headless geometry/projection regression; GPU appearance is reviewed separately.
const Troops = preload("res://native/troops_3d.gd")
const Game = preload("res://native/game.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja","enemy_light","enemy_heavy"]
var checks: int = 0
var failures: Array = []
var observations: Array = []
var context: String = ""
var troops: Control
var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		var message: String = context+" · "+description
		failures.append(message)
		if failures.size()<=25: push_error(message)

func sample(id: int, type_name: String, point: Vector2) -> Dictionary:
	return {"id":id,"type":type_name,"friendly":not type_name.begins_with("enemy"),"x":point.x,"y":point.y,"aimX":0.0,"aimY":-1.0,"animation":"idle","animationClock":0.2,"motionTime":0.2,"animationPhase":0.0,"sailing":false,"kind":"heavy" if type_name=="enemy_heavy" else "light"}

func projected_bounds(actor: Node3D) -> Rect2:
	var minimum: Vector2 = Vector2(INF,INF)
	var maximum: Vector2 = Vector2(-INF,-INF)
	for instance in actor.meshes:
		if not instance.is_visible_in_tree(): continue
		var box: AABB = instance.mesh.get_aabb()
		for corner in range(8):
			var local_point: Vector3 = box.position+box.size*Vector3(1 if corner&1 else 0,1 if corner&2 else 0,1 if corner&4 else 0)
			var projected: Vector2 = troops.camera.unproject_position(instance.global_transform*local_point)
			minimum = minimum.min(projected)
			maximum = maximum.max(projected)
	return Rect2(minimum,maximum-minimum)

func verify_walk(type_name: String, id: int) -> void:
	var actor: Node3D
	var before_phase: float = 0
	var before_point: Vector3
	var before_scale: float = 0
	var first_body: Transform3D
	for frame in range(31):
		var clock: float = float(frame)*0.03
		var state: Dictionary = sample(id,type_name,Vector2(.35,.65-.4*clock/troops.world_depth))
		state.friendly=false
		state.animation="walk"
		state.animationClock=clock
		state.motionTime=clock
		troops.manual_states=[state]
		troops.sync_actor_states([state])
		actor=troops.actors["%d:0" % id]
		if frame>0:
			var actual: float = float(actor.current_state.locomotionPhase)-before_phase
			var stride: float = (1.25 if type_name=="commander" else .90)*actor.scale.x
			var expected: float = actor.position.distance_to(before_point)/stride
			check(absf(actual-expected)<0.000001,"Reduced model stride is synchronized to actual ground travel")
			check(absf(float(actor.current_state.travelSpeed)-.4)<0.0001,"Visual resize does not change source travel speed")
		before_phase=float(actor.current_state.locomotionPhase)
		before_point=actor.position
		before_scale=actor.scale.x
		if frame==0: first_body=actor.bones.torso.global_transform
	check(first_body.origin.distance_to(actor.bones.torso.global_position)>.02,"Shrunk actor still has whole-body walking motion")
	var planted_pose: Transform3D = actor.bones.footL.global_transform
	var clock_phase: float = float(actor.current_state.locomotionPhase)
	troops.sync_actor_states(troops.manual_states)
	check(actor.bones.footL.global_position.distance_to(planted_pose.origin)<0.00001,"Unchanged simulation input keeps the planted foot fixed")
	check(float(actor.current_state.locomotionPhase)==clock_phase,"Paused input does not advance the shortened stride")
	check(is_equal_approx(actor.scale.x,before_scale),"Paused input preserves visual size")

func run() -> void:
	var workspace: String = ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	var profile_path: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile_path.begins_with(workspace):
		push_error("Scale QA requires workspace-isolated APPDATA")
		quit(2)
		return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check(maps.size()==40,"Forty original stage configs remain available")
	troops=Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	game=Game.new()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var original_profiles: Dictionary = troops.visual_profiles.duplicate(true)
	for window_size in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=window_size
		var field: Vector2 = Vector2(window_size.x-390,window_size.y-278)
		troops.set_field_size(field)
		await process_frame
		for stage in maps:
			context="%dx%d %s" % [window_size.x,window_size.y,str(stage.id)]
			troops.set_stage(stage)
			check(is_equal_approx(troops.actor_base_scale(),.70),"All stages default to 30 percent smaller models")
			var states: Array = []
			for index in range(TYPES.size()): states.append(sample(1000+index,TYPES[index],Vector2(.13+index*.073,[.2,.5,.8][index%3])))
			troops.manual_states=states
			troops.motion_tracks.clear()
			troops.sync_actor_states(states)
			for state in states:
				var actor: Node3D=troops.actors["%d:0" % int(state.id)]
				var point: Vector2=Vector2(state.x,state.y)
				check(troops.camera.unproject_position(actor.position).distance_to(point*field)<.01,"Friendly/enemy ground anchor retains the exact hit coordinate")
				var shadow: MeshInstance3D=troops.contact_shadows["%d:0" % int(state.id)]
				check(shadow.scale.distance_to(actor.scale)<.000001,"Ground shadow shares the reduced soldier/mount size")
				check(Vector2(shadow.position.x,shadow.position.z).distance_to(Vector2(actor.position.x,actor.position.z))<.000001,"Ground shadow stays attached to the foot anchor")
			# Compare actual projected mesh bounds with the same source poses at
			# the former 1.0 base scale, without changing any production files.
			var profile: Dictionary=troops.visual_profiles.get(str(stage.id),{}).duplicate(true)
			profile["actorBaseScale"]=1.0
			troops.visual_profiles[str(stage.id)]=profile
			troops.motion_tracks.clear()
			troops.sync_actor_states(states)
			var former_bounds: Dictionary={}
			for state in states: former_bounds[str(state.id)]=projected_bounds(troops.actors["%d:0" % int(state.id)])
			troops.visual_profiles=original_profiles.duplicate(true)
			troops.motion_tracks.clear()
			troops.sync_actor_states(states)
			for state in states:
				var actual: Rect2=projected_bounds(troops.actors["%d:0" % int(state.id)])
				var former: Rect2=former_bounds[str(state.id)]
				check(absf(actual.size.x/former.size.x-.70)<.0001 and absf(actual.size.y/former.size.y-.70)<.0001,"Real projected full-body and weapon bounds shrink by 30 percent")
				if str(stage.id)=="basic-forest" and state.type in ["samurai","commander"]: observations.append({"windowWidth":window_size.x,"windowHeight":window_size.y,"type":state.type,"formerWidth":former.size.x,"formerHeight":former.size.y,"width":actual.size.x,"height":actual.size.y})
			game.load_map(stage)
			game.set_field_rect(Rect2(Vector2.ZERO,field))
			game.start_battle()
			var hint: Vector2=game.placement_hints[0]
			check(game.recruit() and game.place_unit(hint.x,hint.y),"Real game still accepts its legal army placement")
			var snapshot_before: String=JSON.stringify(game.snapshot())
			var game_states: Array=game.actor_states()
			# Newly deployed walking animation has a short visual approach; use
			# its exact settled idle anchor to check hit-map invariance.
			for state in game_states:
				state.animation="idle"
				state.animationClock=1.0
				state.motionTime=1.0
			troops.motion_tracks.clear()
			troops.sync_actor_states(game_states)
			for state in game_states:
				var actor: Node3D=troops.actors["%d:0" % int(state.id)]
				check(troops.camera.unproject_position(actor.position).distance_to(game._screen(Vector2(state.x,state.y)))<.01,"Actual placed army headless camera aligns with the game's click/hit map")
			check(JSON.stringify(game.snapshot())==snapshot_before,"Rendering never mutates battle gold, stats, range or army position")
	context="movement/mount/boat/death/formation"
	troops.set_stage(maps[0])
	troops.set_field_size(Vector2(1050,622))
	await process_frame
	for index in range(TYPES.size()): verify_walk(TYPES[index],2000+index)
	for animation in ["idle","attack","death"]:
		var states: Array=[sample(3100,"commander",Vector2(.4,.6)),sample(3101,"enemy_heavy",Vector2(.6,.6))]
		for state in states: state.animation=animation;state.animationClock=.35
		troops.sync_actor_states(states)
		for actor in troops.actors.values(): check(actor.scale.x<.8,"Mounted and dying actors use the same smaller parent model")
	var boat: Dictionary=sample(3300,"enemy_light",Vector2(.5,.5))
	boat.animation="walk";boat.sailing=true
	troops.sync_actor_states([boat])
	var actor: Node3D=troops.actors["3300:0"]
	check(actor.boat.visible and actor.motion_debug.mode=="rowing","Shrunk waterborne unit still rows in its boat")
	check(actor.boat.global_basis.get_scale().distance_to(actor.scale)<.00001,"Boat hull uses the soldier's reduced world scale")
	check(not troops.contact_shadows["3300:0"].visible,"No land shadow appears beneath the smaller boat")
	troops.friendly_formation_count=3
	var formation: Dictionary=sample(3400,"spear",Vector2(.5,.5))
	troops.sync_actor_states([formation])
	var a: Vector3=troops.actors["3400:0"].position
	var b: Vector3=troops.actors["3400:1"].position
	check(absf(a.distance_to(b)-Vector2(.48,.05).length()*troops.actor_base_scale()*.99)<.003,"Optional formation spacing shrinks with the actual soldiers")
	var report: Dictionary={"checks":checks,"failures":failures,"stages":40,"windowSizes":3,"defaultActorBaseScale":Troops.DEFAULT_ACTOR_BASE_SCALE,"projectionObservations":observations,"scope":"Real articulated meshes, camera-projected bounds, all forty existing maps and three window sizes; actual army placement/snapshot invariance; distance-based stride, pause, mounted/boat/death states, contact shadows and optional formation spacing. GPU appearance is verified separately."}
	var file: FileAccess=FileAccess.open("res://tests/qa_actor_scale.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ACTOR_SCALE_QA "+JSON.stringify({"checks":checks,"failures":failures.size(),"stages":40,"windowSizes":3,"observations":observations}))
	game.queue_free();troops.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
