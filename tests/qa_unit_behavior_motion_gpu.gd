extends SceneTree
## Actual combat clocks drive existing 3D actors on an isolated plain test plane.
## This is not a replacement map, authored terrain, or complete Troops3D QA.
const Battle = preload("res://native/game.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
const FILES: Array=["native/game.gd","native/ground_combat.gd","native/unit_skills.gd","native/units.json","native/unit_growth.gd","native/unit_training.gd","native/sengoku_actor_3d.gd","native/troop_action_presentation.gd","native/troops_3d.gd","native/actor_materials.gd","native/sengoku_skinned_renderer.gd","native/human_face_3d.gd","native/human_body_geometry.gd","native/sengoku_armor_geometry.gd","native/sengoku_equipment_geometry.gd","tests/qa_unit_behavior_motion_gpu.gd"]
var game: Node2D
var world: Node3D
var actors: Dictionary={}
var receipts: Array=[]
var captures: Array=[]
var motion: Dictionary={}
var natural: Dictionary={}
var checks: int=0
var failures: Array=[]
var label: Label
var phase: String="initialize"
var catalog: Array=[]
var initial_hashes: Dictionary={}

func _initialize() -> void: call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<=20: push_error("UNIT_BEHAVIOR_GPU "+note)

func hashes() -> Dictionary:
	var result: Dictionary={}
	for path in FILES: result[path]=FileAccess.get_sha256("res://"+str(path))
	return result

func fixture() -> Dictionary:
	return {"id":"unit-behavior-gpu-synthetic-plane","stageNumber":20,"theme":"forest","initialGold":10000,"unitLimit":24,"totalWaves":100,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":1000}],"buildZones":[{"id":"firing","x":.5,"y":.65,"r":.13}],"tactics":{"groundPosts":[{"id":"defense","pathIndex":0,"segmentIndex":0,"t":.5,"r":.14,"guardRadius":.2,"mobilityFactor":1.0}]}}

func setup_world() -> void:
	root.size=Vector2i(1280,800)
	root.content_scale_size=Vector2i(1280,800)
	world=Node3D.new();root.add_child(world)
	var camera: Camera3D=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20.0
	world.add_child(camera);camera.position=Vector3(0,13,10);camera.look_at(Vector3.ZERO);camera.current=true
	var light: DirectionalLight3D=DirectionalLight3D.new()
	light.light_energy=1.8;light.rotation_degrees=Vector3(-65,-30,0);world.add_child(light)
	var env_node: WorldEnvironment=WorldEnvironment.new()
	var environment: Environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("20292d")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("d4d6da");environment.ambient_light_energy=.7
	env_node.environment=environment;world.add_child(env_node)
	var floor: MeshInstance3D=MeshInstance3D.new()
	var mesh: PlaneMesh=PlaneMesh.new();mesh.size=Vector2(18.0,10.0);floor.mesh=mesh
	var material: StandardMaterial3D=StandardMaterial3D.new();material.albedo_color=Color("74796d");material.roughness=1.0
	floor.material_override=material;world.add_child(floor)
	label=Label.new();label.position=Vector2(20,18);label.add_theme_font_size_override("font_size",22)
	root.add_child(label)

func new_game(held: bool) -> void:
	if is_instance_valid(game): game.free()
	for actor in actors.values(): actor.free()
	actors.clear();motion.clear();receipts.clear()
	game=Battle.new();root.add_child(game)
	game.three_d_enabled=true
	game.configure_roster(catalog,["archer","gunner","spear","samurai","commander","naginata","monk","ninja"],{"naginata":8})
	game.load_map(fixture());game.set_seed(197);game.start_battle()
	if held:
		game.enemies.clear();game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=100000
	game.game_event.connect(func(event: Dictionary): receipts.append(event.duplicate(true)))

func order(type_name: String, point: Vector2=Vector2(-1,-1)) -> bool:
	if not game.begin_placement(type_name,0): check(false,"GPU actual recruitment accepts "+type_name);return false
	if str(game.placement_contract(type_name).deploymentKind)=="marching": return true
	var destination: Vector2=point
	if destination.x<0:
		var nearest: float=INF
		for zone in game.zones:
			var candidate: Vector2=zone.position if type_name=="ninja" and str(zone.get("placementRole",""))=="ambush" else game._zone_placement_hint(zone,type_name)
			if candidate.x>=0 and game.placement_preview(candidate).valid and candidate.distance_to(Vector2(.5,.565))<nearest:
				nearest=candidate.distance_to(Vector2(.5,.565));destination=candidate
	var accepted: bool=destination.x>=0 and game.place_unit(destination.x,destination.y)
	check(accepted,"GPU actual recruitment commits "+type_name)
	return accepted

func controlled_enemy(position: Vector2, tower: bool=false) -> Dictionary:
	var enemy: Dictionary=game._spawn_enemy("enemy_gunner",1,{"pathIndex":0})
	enemy.merge({"position":position,"pointIndex":1,"speed":0.0,"hp":5000.0,"maxHp":5000.0,"armor":0.0,"attackCooldown":10000.0,"stationThreatClock":10000.0,"stationaryEnemy":tower,"fortification":tower},true)
	return enemy

func sync() -> void:
	var states: Array=game.actor_states()
	var alive: Dictionary={}
	var before: String=JSON.stringify(game.snapshot())
	for state in states:
		var key: String=str(state.id)+":"+str(state.get("dead",false))
		alive[key]=true
		if not actors.has(key):
			var actor: Node3D=Actor.new();world.add_child(actor)
			actor.configure(str(state.type),not bool(state.friendly),int(state.id),false,int(state.get("evolution",0)))
			actor.scale=Vector3.ONE*.8;actors[key]=actor
		var actor: Node3D=actors[key]
		actor.position=Vector3((float(state.x)-.5)*18.0,0,(float(state.y)-.5)*10.0)
		actor.rotation.y=atan2(float(state.aimX),float(state.aimY))
		var visual: Dictionary=state.duplicate(true)
		visual["groundMotion"]=true
		actor.apply_state(visual)
		if not motion.has(key): motion[key]={"positions":[],"animations":{},"friendly":bool(state.friendly),"type":str(state.type),"travel":0.0,"last":Vector2(state.x,state.y)}
		var row: Dictionary=motion[key]
		var position: Vector2=Vector2(state.x,state.y)
		row.travel=float(row.travel)+position.distance_to(row.last);row.last=position
		row.animations[str(state.animation)]=true
		if row.positions.is_empty() or str(row.positions[-1].animation)!=str(state.animation) or game.elapsed-float(row.positions[-1].elapsed)>=.20:
			row.positions.append({"elapsed":game.elapsed,"x":state.x,"y":state.y,"animation":state.animation,"clock":state.animationClock,"renderMode":str(actor.motion_debug.get("mode",state.animation))})
			if row.positions.size()>256: row.positions.pop_front()
	for key in actors.keys():
		if not alive.has(key): actors[key].free();actors.erase(key)
	if before!=JSON.stringify(game.snapshot()): check(false,"3D motion presentation cannot mutate the combat snapshot")
	label.text="격리 기능 검증 · 합성 평면 (실제 맵 아님)\n%s · %.2f초 · 웨이브 %d · 보급 %d · 아군 %d · 적 %d" % [phase,game.elapsed,game.wave,game.gold,game.units.size(),game.enemies.size()]

func frames(seconds: float) -> void:
	var end: int=Time.get_ticks_usec()+int(seconds*1000000)
	while Time.get_ticks_usec()<end:
		await process_frame
		if game.between_waves: game.continue_wave()
		sync()

func capture(name: String) -> void:
	sync();await process_frame;await RenderingServer.frame_post_draw
	var path: String="user://unit-behavior-"+name+".png"
	var result: Error=root.get_texture().get_image().save_png(path)
	check(result==OK,"Actual GPU frame is saved: "+name)
	captures.append({"name":name,"path":ProjectSettings.globalize_path(path),"elapsed":game.elapsed,"wave":game.wave,"actors":actors.size(),"states":game.actor_states()})

func controlled_motion() -> void:
	phase="장도병 실제 접근·공격·복귀";new_game(true)
	order("naginata",Vector2(.5,.5));await frames(4.0)
	var guard: Dictionary={}
	for unit in game.units:
		if str(unit.type)=="naginata": guard=unit
	check(not guard.is_empty(),"Paid guard completes live GPU production")
	await capture("guard-idle")
	var first: Dictionary=controlled_enemy(Vector2(.62,.5));var second: Dictionary=controlled_enemy(Vector2(.635,.508))
	await frames(.35);await capture("guard-approach")
	await frames(1.6);await capture("guard-attack")
	check(float(first.hp)<5000 and float(second.hp)<5000,"Controlled GPU observation includes actual guard strike and sweep HP loss")
	first.hp=0;second.hp=0
	await frames(1.8);await capture("guard-returned")
	if not guard.is_empty(): check(guard.position.distance_to(guard.homePosition)<.00001,"Live GPU guard physically finishes its return")
	natural["controlledGuardReceipts"]=receipts.duplicate(true)
	natural["controlledGuardMotion"]=motion.duplicate(true)
	phase="닌자 실제 접근·암살·소모";new_game(true)
	var tower: Dictionary=controlled_enemy(Vector2(.5,.5),true)
	order("ninja");await frames(4.1);await capture("ninja-approach")
	await frames(3.3);await capture("ninja-attack")
	check(float(tower.hp)<5000,"Live GPU ninja motion corresponds to actual tower HP loss")
	tower.hp=1
	await frames(1.0);await capture("ninja-consumed")
	check(game.units.is_empty() and receipts.any(func(event: Dictionary): return str(event.type)=="unit_consumed"),"Consumed ninja is absent from actual GPU actor feed")
	check(not actors.keys().any(func(key: String): return bool(actors[key].current_state.get("friendly",false))),"Consumed friendly has no lingering 3D actor")
	observations_controlled()

func observations_controlled() -> void:
	natural["controlledReceipts"]=receipts.duplicate(true)

func natural_observation() -> void:
	phase="자동 웨이브 30초 · 실시간 전투";new_game(false)
	game.set_speed(2.0)
	order("archer");order("spear");order("naginata",Vector2(.5,.5));order("monk",Vector2(.57,.5));order("ninja")
	var start: int=Time.get_ticks_usec()
	# No enemy injection, pose injection, manual advance_simulation, or frozen
	# clocks during this interval. Native _process and normal spawns run live.
	await frames(10.0);await capture("natural-10s")
	await frames(10.0);await capture("natural-20s")
	await frames(10.0);await capture("natural-30s")
	var moved_enemies: int=0
	for row in motion.values():
		if not bool(row.friendly) and float(row.travel)>.01: moved_enemies+=1
	check(moved_enemies>=3,"Naturally spawned enemies visibly move under native battle processing")
	check(receipts.any(func(event: Dictionary): return str(event.type)=="hit"),"Natural fixture waves include actual native combat damage")
	check(receipts.any(func(event: Dictionary): return str(event.type)=="unit_consumed"),"Natural no-tower ninja production follows real consumption policy")
	natural.merge({"wallSeconds":float(Time.get_ticks_usec()-start)/1000000.0,"elapsed":game.elapsed,"wave":game.wave,"finished":game.finished,"movedEnemies":moved_enemies,"motion":motion,"receipts":receipts,"enemyInjectedDuringObservation":false,"manuallyAdvancedDuringObservation":false},true)

func run() -> void:
	var user_path: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var boundary: String=ProjectSettings.globalize_path("res://tests/profiles/unit-behavior-gpu").replace("\\","/").to_lower()
	if DisplayServer.get_name()=="headless" or not user_path.begins_with(boundary): push_error("GPU behavior QA refuses player profiles and headless render claims");quit(2);return
	initial_hashes=hashes()
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	setup_world()
	await controlled_motion()
	await natural_observation()
	check(hashes()==initial_hashes,"Behavior/actor source files stay unchanged throughout final GPU verification")
	var report: Dictionary={"checks":checks,"failures":failures,"captures":captures,"natural":natural,"sourceHashes":initial_hashes,"sourceFreezeUnchanged":hashes()==initial_hashes,"scope":"GPU-only existing SengokuActor3D meshes fed real Game.actor_states, controlled paid guard approach/strike/return and ninja tower damage/consumption; 30 wall seconds native synthetic fixture waves. Plain QA plane is not an accepted remaster map. No Troops3D terrain/contact/camera HUD integration or real-stage all-wave victory is claimed."}
	var file: FileAccess=FileAccess.open("user://qa_unit_behavior_motion_gpu.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("UNIT_BEHAVIOR_GPU ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path("user://qa_unit_behavior_motion_gpu.json"))
	quit(0 if failures.is_empty() else 1)
