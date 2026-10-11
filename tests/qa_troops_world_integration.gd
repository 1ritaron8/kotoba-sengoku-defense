extends SceneTree
## COMMON-FIRST-R1: actual Troops3D + authored adapter, numeric/headless only.
## Supplied pose traces are separate from paid native Game/event scenarios.
const Troops = preload("res://native/troops_3d.gd")
const Battle = preload("res://native/game.gd")
const WorldSurface = preload("res://native/battlefield_world_adapter.gd")
const FRIENDLY = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const ENEMY_KINDS = ["raider","heavy","enemy_archer","enemy_gunner","enemy_samurai","enemy_cavalry"]
const ENEMY_MODELS = ["enemy_light","enemy_heavy","archer","gunner","samurai","commander"]
const SOURCE_PATHS = ["native/troops_3d.gd","native/battlefield_world_adapter.gd","native/sengoku_actor_3d.gd","native/sengoku_equipment_geometry.gd","native/sengoku_skinned_renderer.gd","native/actor_materials.gd","native/troop_action_presentation.gd","native/game.gd","native/ground_combat.gd","native/unit_skills.gd","native/unit_growth.gd","native/ruby_label.gd","native/ruby_readings.gd","native/ruby_readings.json","native/units.json","tests/qa_troops_world_integration.gd"]
var checks: int = 0
var failures: Array[String] = []
var observations: Dictionary = {}
var catalog: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size()<=25:
			push_error("TROOPS WORLD INTEGRATION: "+note)

func stage_fixture(origin: Vector2 = Vector2(7,-11), grade: Vector2 = Vector2(.08,.06), stage_id: String = "qa-common-first-world") -> Dictionary:
	var bounds: Dictionary = {"x":origin.x,"z":origin.y,"width":20.0,"depth":14.0}
	var vertices: Array = []
	for corner in [Vector2.ZERO,Vector2(1,0),Vector2(0,1),Vector2.ONE]:
		vertices.append({"x":origin.x+corner.x*20.0,"y":.4+corner.x*20.0*grade.x+corner.y*14.0*grade.y,"z":origin.y+corner.y*14.0})
	# This standalone fixture is never registered in maps/campaign or a save.
	return {"id":stage_id,"stageNumber":15,"theme":"forest","initialGold":6000,"unitLimit":24,"totalWaves":100,"difficulty":1.0,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":1000}],"buildZones":[{"id":"wall","x":.5,"y":.65,"r":.08}],"tactics":{"groundPosts":[{"id":"defense","pathIndex":0,"segmentIndex":0,"t":.5,"r":.22,"guardRadius":.22,"mobilityFactor":1.0}]},"worldGeometry":{"schemaVersion":1,"simulationBounds":bounds,"vertices":vertices,"triangles":[0,2,1,1,2,3],"blockedPolygons":[]},"_qaPlaneGrade":grade}

func expected_world(stage: Dictionary, point: Vector2) -> Vector3:
	var bounds: Dictionary = stage.worldGeometry.simulationBounds
	var grade: Vector2 = stage._qaPlaneGrade
	return Vector3(float(bounds.x)+point.x*float(bounds.width),.4+point.x*float(bounds.width)*grade.x+point.y*float(bounds.depth)*grade.y,float(bounds.z)+point.y*float(bounds.depth))

func renderer_for(stage: Dictionary) -> Control:
	var troops: Control = Troops.new()
	troops.stage = stage.duplicate(true)
	root.add_child(troops)
	troops.set_process(false)
	troops.position = Vector2(83,47)
	troops.friendly_formation_count = 1
	troops.set_field_size(Vector2(1100,620))
	var provider: Node3D = WorldSurface.new()
	troops.set_terrain_provider(provider)
	troops.set_stage(stage)
	check(troops.uses_world_geometry(),"Actual authored adapter activates the actual Troops world branch")
	check(provider.errors.is_empty(),"Fixture authored triangles are accepted by the actual adapter")
	check(bool(provider.diagnostics().get("ready",false)),"Actual adapter has a valid authored floor, beyond its capability flag")
	return troops

func make_game(stage: Dictionary, levels: Dictionary = {}) -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,FRIENDLY,levels)
	game.load_map(stage)
	game.set_seed(887)
	return game

func pose_state(id: int, type_name: String, friendly: bool, point: Vector2, animation: String, clock: float, action_clock: float = 0.0) -> Dictionary:
	return {"id":id,"type":type_name,"friendly":friendly,"hostile":not friendly,"x":point.x,"y":point.y,"aimX":0.0,"aimY":-1.0,"animation":animation,"animationClock":action_clock,"animationPhase":0.0,"motionTime":clock,"sailing":false,"dead":false,"attackDuration":.5,"releaseTime":.25,"attackReleased":false,"attackCancelled":false,"hitClock":0.0,"hp":100.0,"maxHp":100.0,"_qaSource":"supplied_pose_fixture"}

func snapshot_joints(troops: Control) -> Dictionary:
	var result: Dictionary = {}
	for key in troops.actors:
		var actor: Node3D = troops.actors[key]
		var bones: Dictionary = {}
		for name_value in actor.bones:
			bones[name_value] = actor.bones[name_value].global_transform
		result[key] = {"root":actor.global_transform,"bones":bones}
	return result

func same_joints(a: Dictionary, b: Dictionary, epsilon: float = .00005) -> bool:
	if a.size()!=b.size(): return false
	for key in a:
		if not b.has(key): return false
		if (a[key].root as Transform3D).origin.distance_to((b[key].root as Transform3D).origin)>epsilon: return false
		for bone in a[key].bones:
			var first: Transform3D = a[key].bones[bone]
			var second: Transform3D = b[key].bones[bone]
			if first.origin.distance_to(second.origin)>epsilon: return false
			for axis in range(3):
				if first.basis[axis].distance_to(second.basis[axis])>epsilon: return false
	return true

func contact_keys(actor: Node3D) -> Array:
	return ["horse_calf0","horse_calf1","horse_calf2","horse_calf3"] if actor.unit_type=="commander" else ["footL","footR"]

func actual_contact_clearance(actor: Node3D, provider: Node3D, key: String) -> float:
	var lowest: float = INF
	for source in actor.meshes:
		if source.get_parent()!=actor.bones[key]: continue
		for surface in range(source.mesh.get_surface_count()):
			for vertex in source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if key.begins_with("horse") and vertex.y>-.352: continue
				var point: Vector3 = source.global_transform*vertex
				var height: float = float(provider.sample_world_height(point))
				if not is_finite(height): return NAN
				lowest = minf(lowest,point.y-height)
	return lowest

func check_actor_contact(troops: Control, source: Dictionary, label: String, require_planted: bool) -> Dictionary:
	var key: String = str(source.id)+":0"
	check(troops.actors.has(key),label+": source has an actual rendered model")
	if not troops.actors.has(key): return {}
	var actor: Node3D = troops.actors[key]
	var expected: Vector3 = troops.battlefield.world_point(Vector2(float(source.x),float(source.y)))
	var root_error: float = actor.position.distance_to(expected)
	check(actor.visible and root_error<.00005,label+": actual actor root follows the geometry surface without a height shear")
	check(actor.current_state.get("groundHeightSampler",Callable()).is_valid(),label+": actual renderer delivers terrain sampling in this action")
	var lowest: float = INF
	var highest: float = -INF
	for contact in contact_keys(actor):
		var clearance: float = actual_contact_clearance(actor,troops.battlefield,str(contact))
		lowest = minf(lowest,clearance)
		highest = maxf(highest,clearance)
		check(is_finite(clearance) and clearance>=-.012*actor.scale.y,label+"/"+str(contact)+": real sole or hoof does not penetrate the actual triangles; gap="+str(clearance))
		if require_planted:
			check(clearance<.020*actor.scale.y,label+"/"+str(contact)+": stopped real sole or hoof is supported by the actual triangles; gap="+str(clearance))
	return {"rootError":root_error,"minimumClearance":lowest,"maximumClearance":highest}

func test_fixed_mapping_and_input() -> void:
	var stage: Dictionary = stage_fixture()
	var troops: Control = renderer_for(stage)
	await process_frame
	var samples: Array = []
	for field in [Vector2(1100,620),Vector2(760,980),Vector2(1200,460)]:
		troops.set_field_size(field)
		check(is_equal_approx(troops.world_width,20.0) and is_equal_approx(troops.world_depth,14.0),"Resize preserves the authored physical width/depth")
		for point in [Vector2(.15,.18),Vector2(.5,.5),Vector2(.81,.76)]:
			var expected: Vector3 = expected_world(stage,point)
			check(troops.normalized_to_world(point).distance_to(expected)<.00002,"Actual provider mapping uses translated fixed X/Z and triangle Y")
			var legacy_z: float = (point.y-.5)*troops.world_depth+expected.y/tan(deg_to_rad(troops.elevation_degrees))
			check(absf(expected.z-legacy_z)>.20,"Translated fixture exposes the retired height/tan coordinate assumption")
			for lift in [-2.0,0.0,.8,4.0]:
				var lifted: Vector3 = expected+Vector3.UP*lift
				check(troops.world_to_normalized(lifted).distance_to(point)<.00002,"Actual inverse ignores a lifted soldier/foot Y")
				check(absf(troops._ground_contact_height(lifted)-expected.y)<.00002,"Actual Troops contact selects the provider surface independently of query Y")
			for mirrored in [false,true]:
				troops.presentation_mirrored = mirrored
				troops.output.flip_h = mirrored
				var local: Vector2 = troops.model_to_field_point(point)
				var global: Vector2 = troops.get_global_transform_with_canvas()*local
				var picked: Dictionary = troops.screen_to_model_point(global)
				check(bool(picked.get("valid",false)) and (picked.get("position",Vector2(INF,INF)) as Vector2).distance_to(point)<.0001,"Actual camera/Control/mirror ray round-trip selects the same canonical point")
				samples.append({"field":str(field),"mirrored":mirrored,"model":str(point),"local":str(local),"picked":str(picked.get("position",Vector2.ZERO))})
		var center: Vector2 = troops.model_to_field_point(Vector2(.5,.5))
		check(center.distance_to(field*.5)<2.0,"Camera follows the translated authored surface center after resize")
	var outside: Vector3 = Vector3(6.0,99,-5.0)
	check(is_nan(troops._ground_contact_height(outside)),"Authored outside-surface NAN is preserved instead of invoking legacy terrain")
	var miss: Dictionary = troops.screen_to_model_point(troops.global_position-Vector2(40,40))
	check(not bool(miss.get("valid",false)),"Outside the actual Control does not produce a valid terrain selection")
	observations.mapping = {"provider":"native/battlefield_world_adapter.gd","samples":samples,"cameraUsesFixedBounds":true}
	troops.free()

func pose_roster(stage: Dictionary) -> Array:
	var records: Array = []
	for index in range(FRIENDLY.size()):
		records.append(pose_state(100+index,FRIENDLY[index],true,Vector2(.17+.085*index,.72),"idle",0))
	# Enemy identities/model types come from actual Game.actor_states(), then
	# animation/coordinates are explicitly supplied test poses, not gameplay.
	var game: Node2D = make_game(stage)
	for kind in ENEMY_KINDS:
		game._spawn_enemy(str(kind),20,{"pathIndex":0})
	var enemies: Array = game.actor_states()
	check(enemies.size()==ENEMY_KINDS.size(),"Six actual native enemy identities provide the pose prototypes")
	for index in range(enemies.size()):
		var data: Dictionary = enemies[index].duplicate(true)
		data.id = 200+index
		data.x = .20+.11*index
		data.y = .44
		data.animationPhase = 0.0
		data._qaSource = "native_enemy_identity_supplied_pose"
		records.append(data)
	game.free()
	return records

func test_continuous_pose_trace() -> void:
	var rows: Array = []
	for grade in [Vector2.ZERO,Vector2(.08,.06)]:
		var stage: Dictionary = stage_fixture(Vector2(7,-11),grade)
		var troops: Control = renderer_for(stage)
		var prototypes: Array = pose_roster(stage)
		var metrics: Dictionary = {}
		var last_states: Array = []
		for frame in range(127):
			var clock: float = frame*.03
			var moving: bool = frame>=5 and frame<85
			var walk_clock: float = clampf((frame-5)*.03,0,2.37)
			var animation: String = "walk" if moving else "attack" if frame>=85 and frame<103 else "heal" if frame>=103 and frame<117 else "idle"
			var states: Array = []
			for index in range(prototypes.size()):
				var data: Dictionary = prototypes[index].duplicate(true)
				data.x = float(prototypes[index].x)+.008*sin(walk_clock*.85)
				data.y = float(prototypes[index].y)-.025*walk_clock
				data.animation = "heal" if animation=="heal" and str(data.type)=="monk" else "idle" if animation=="heal" else animation
				data.animationClock = clock if moving else (frame-85)*.03 if animation=="attack" else (frame-103)*.03 if animation=="heal" else clock
				data.motionTime = clock
				data.aimX = .008*.85*cos(walk_clock*.85) if moving else 0.0
				data.aimY = -.025 if moving else -1.0
				data.attackDuration = .5
				data.releaseTime = .25
				data.attackReleased = false
				data.attackCancelled = false
				data.hitClock = .06 if frame in [3,25,90,107] else 0.0
				data.healing = str(data.animation)=="heal"
				data.healDuration = .6
				data.healAmount = 0.0
				data.deploying = false
				data.fortification = false
				data.stationaryEnemy = false
				data.ingressActive = false
				data.combatRole = "path_assault"
				data.hunterState = "route"
				states.append(data)
			var encoded: String = JSON.stringify(states)
			troops.sync_actor_states(states)
			check(JSON.stringify(states)==encoded,"Supplied pose trace input is never mutated by the actual renderer")
			for index in range(states.size()):
				var source: Dictionary = states[index]
				var label: String = str(source.type)+"/"+str(grade)+"/"+str(frame)+"/"+str(source.animation)
				var result: Dictionary = check_actor_contact(troops,source,label,frame<5 or frame>=122)
				if result.is_empty(): continue
				var actor: Node3D = troops.actors[str(source.id)+":0"]
				var expected_model: String = FRIENDLY[index] if index<FRIENDLY.size() else ENEMY_MODELS[index-FRIENDLY.size()]
				check(actor.unit_type==expected_model and actor.hostile!=bool(source.friendly),label+": actual enemy/friendly model and faction are preserved")
				if not metrics.has(str(source.id)):
					metrics[str(source.id)] = {"type":actor.unit_type,"friendly":bool(source.friendly),"minimumClearance":INF,"maxRootError":0.0,"swingObserved":false,"phases":{},"maxHit":0.0}
				var metric: Dictionary = metrics[str(source.id)]
				metric.minimumClearance = minf(float(metric.minimumClearance),float(result.minimumClearance))
				metric.maxRootError = maxf(float(metric.maxRootError),float(result.rootError))
				metric.swingObserved = bool(metric.swingObserved) or moving and float(result.maximumClearance)>.025*actor.scale.y
				metric.phases[str(source.animation)] = true
				metric.maxHit = maxf(float(metric.maxHit),float(actor.motion_debug.get("hitReaction",0)))
				check(not bool(actor.motion_debug.get("healCommitted",false)),label+": supplied pose has no fabricated committed heal")
			last_states = states
		for id in metrics:
			check(bool(metrics[id].swingObserved),str(metrics[id].type)+": continuous actual renderer movement retains a foot/hoof swing")
			check(float(metrics[id].maxHit)>.9,str(metrics[id].type)+": continuous trace observes a visible hit response")
		var frozen: Dictionary = snapshot_joints(troops)
		for repeat in range(3):
			troops.sync_actor_states(last_states)
			check(same_joints(frozen,snapshot_joints(troops)),"Repeated frozen-time sync preserves every real root and joint on the authored surface")
		rows.append({"grade":str(grade),"frames":127,"source":"Supplied uncommitted pose trace; six enemy identities from native Game. No shot/hit/heal event was emitted.","actors":metrics})
		troops.free()
	observations.poseTraces = rows

func test_provider_revision_and_replacement() -> void:
	var first: Dictionary = stage_fixture()
	var troops: Control = renderer_for(first)
	var source: Dictionary = pose_state(901,"commander",true,Vector2(.48,.51),"idle",3.0,3.0)
	troops.sync_actor_states([source])
	var old_root: Vector3 = troops.actors["901:0"].position
	var revised: Dictionary = stage_fixture(Vector2(-18,9),Vector2(.04,-.03),str(first.id))
	troops.set_stage(revised)
	troops.sync_actor_states([source])
	var result: Dictionary = check_actor_contact(troops,source,"same-stage-ID geometry revision",true)
	check(troops.actors["901:0"].position.distance_to(old_root)>10,"Same stage ID at the same time is reprojected to its new physical surface")
	check(troops.actors["901:0"].position.distance_to(expected_world(revised,Vector2(.48,.51)))<.00005,"Same-ID authored revision uses its new bounds/height")
	var replacement: Node3D = WorldSurface.new()
	troops.set_terrain_provider(replacement)
	troops.sync_actor_states([source])
	check_actor_contact(troops,source,"provider instance replacement at unchanged stage/time",true)
	var frozen: Dictionary = snapshot_joints(troops)
	troops.set_field_size(Vector2(760,980))
	troops.sync_actor_states([source])
	check(same_joints(frozen,snapshot_joints(troops)),"Authored viewport resize preserves actual roots, gait and contact pose")
	observations.providerLifecycle = {"sameStageId":str(first.id),"sameMotionTime":3.0,"revisionContact":result,"replacement":"Actual new native adapter instance","resizeFrozenPose":true}
	troops.free()

func game_signature(game: Node2D) -> String:
	return JSON.stringify({"units":game.units,"enemies":game.enemies,"projectiles":game.projectiles,"deathActors":game.death_actors,"gold":game.gold,"kills":game.kills,"elapsed":game.elapsed,"animationTime":game.animation_time,"generation":game.battle_generation})

func sync_native(game: Node2D, troops: Control) -> Array:
	var before_query: String = game_signature(game)
	var states: Array = game.actor_states()
	check(before_query==game_signature(game),"Actual Game.actor_states query changes no HP, money, projectile, position or clock")
	var encoded: String = JSON.stringify(states)
	var before_sync: String = game_signature(game)
	troops.sync_actor_states(states)
	check(encoded==JSON.stringify(states),"Actual render sync preserves its supplied Game.actor_states input")
	check(before_sync==game_signature(game),"Actual event rendering changes no HP, money, projectile, position or clock")
	return states

func hold(game: Node2D) -> void:
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue = ["raider"]
	game.spawn_source_waves = [1]
	game.spawn_metadata = [{}]
	game.spawn_clock = 100000.0

func produce(game: Node2D, troops: Control, type_name: String, position: Vector2) -> Dictionary:
	var wallet: int = game.gold
	var cost: int = game.recruit_cost(type_name)
	check(game.begin_placement(type_name,0) and game.place_unit(position.x,position.y),type_name+": actual paid production is submitted at a legal native position")
	check(game.gold==wallet-cost and game.recruitment_queue.size()==1,type_name+": native catalog cost is charged exactly at submission")
	for tick in range(320):
		game.advance_simulation(.025)
		sync_native(game,troops)
		for unit in game.units:
			if str(unit.type)==type_name:
				return unit
	check(false,type_name+": bounded native production completed and survived its first simulation step")
	return {}

func native_target(game: Node2D, point: Vector2, kind: String, hp: float) -> Dictionary:
	var target: Dictionary = game._spawn_enemy(kind,20,{"pathIndex":0})
	# Initial conditions isolate a deterministic real native engagement.
	target.position = point
	target.pointIndex = 1
	target.ingressActive = false
	target.speed = 0.0
	target.hp = hp
	target.maxHp = hp
	return target

func test_native_guard_dash_return() -> void:
	var stage: Dictionary = stage_fixture()
	var game: Node2D = make_game(stage,{"naginata":8})
	var troops: Control = renderer_for(stage)
	troops.bind_battle(game)
	hold(game)
	var events: Array = []
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	var guard: Dictionary = produce(game,troops,"naginata",Vector2(.5,.5))
	if guard.is_empty(): troops.free();game.free();return
	for tick in range(320):
		game.advance_simulation(.025)
		sync_native(game,troops)
	var home: Vector2 = guard.homePosition
	# Native guard acquisition requires the actual emplacement-assault role.
	# Its existing charge also requires two nearby enemies; ordinary raiders
	# are route attackers and cannot establish this authorized skill fixture.
	var target: Dictionary = native_target(game,home+Vector2(-.12,0),"enemy_samurai",500.0)
	var cluster_target: Dictionary = native_target(game,home+Vector2(-.13,.01),"enemy_samurai",500.0)
	check(game.ground_combat.is_base_attacker(target) and game.ground_combat.is_base_attacker(cluster_target),"Guard charge fixture uses two actual native emplacement-assault identities")
	check(game.ground_combat.guard_target_valid(guard,target) and game.ground_combat.guard_target_valid(guard,cluster_target),"Native guard accepts both isolated attackers before the charge trace")
	check(game.unit_skills.has_skill(guard,"naginata_guard_charge") and float(guard.get("skillMana",0))>=float(guard.get("maxSkillMana",100)),"Approved native level-8 guard charge was earned by actual idle simulation")
	var health: float = target.hp
	var dash: bool = false
	var windup: bool = false
	var released: bool = false
	var previous: Vector2 = guard.position
	for tick in range(800):
		game.advance_simulation(.025)
		var states: Array = sync_native(game,troops)
		check(guard.position.distance_to(home)<=float(guard.guardRadius)+.00002,"Paid native guard stays inside its actual defense boundary during dash/attack")
		check(guard.position.distance_to(previous)<=.008,"Paid native guard approaches through bounded real movement")
		previous = guard.position
		dash = dash or str(guard.combatState)=="guard_dash" or bool(guard.get("guardDashActive",false))
		var actor: Node3D = troops.actors.get(str(guard.id)+":0")
		if is_instance_valid(actor):
			windup = windup or str(actor.current_state.get("motionPhase",""))=="windup"
			released = released or bool(actor.current_state.get("attackReleased",false))
		for state in states:
			if int(state.id)==int(guard.id): check_actor_contact(troops,state,"native paid guard trace",false)
		if float(target.hp)<health: break
	check(dash and windup and released and float(target.hp)<health,"Existing approved level-8 native guard dash/windup/release reaches an actual damaged target through the event bridge")
	var hits: int = 0
	for event in events:
		if str(event.type)=="hit" and int(event.get("actorId",-1))==int(guard.id):
			hits += 1
			check(absf(float(event.hpBefore)-float(event.hpAfter)-float(event.damage))<.00001,"Native guard hit receipt equals actual committed HP loss")
	check(hits>0,"Native guard integration contains actual hit receipts")
	var before_return_context: Dictionary = {"hp":float(guard.hp),"maxHp":float(guard.maxHp),"combatState":str(guard.combatState),"movementBlocked":bool(guard.get("movementBlocked",false)),"home":str(guard.homePosition),"position":str(guard.position),"targetId":int(guard.get("targetId",-1)),"guardDashActive":bool(guard.get("guardDashActive",false)),"guardDashData":guard.get("guardDashData",{}).duplicate(true),"guardTrail":guard.get("guardTrail",[]).duplicate(true),"animation":str(guard.animation),"animationClock":float(guard.animationClock),"attackPlan":guard.get("attackPlan",{}).duplicate(true),"enemyCount":game.enemies.size(),"elapsed":game.elapsed,"finished":game.finished,"battleClosed":game.battle_closed}
	# Remove both isolated targets as a fixture transition; no fabricated hit,
	# kill/reward or HP mutation is used to cause the real guard return.
	game.enemies.erase(target)
	game.enemies.erase(cluster_target)
	var returning: bool = false
	for tick in range(600):
		game.advance_simulation(.025)
		sync_native(game,troops)
		returning = returning or str(guard.combatState)=="guard_return"
		if guard.position.distance_to(home)<.00001 and str(guard.combatState)=="guard": break
	# Retain the live failed context before the generation test reloads Game.
	var enemy_ids: Array = []
	for enemy in game.enemies: enemy_ids.append(int(enemy.id))
	var native_units: Array = []
	var group_count: int = 0
	for unit in game.units:
		if int(unit.get("productionJobId",-1))==int(guard.get("productionJobId",-2)): group_count += 1
		native_units.append({"id":int(unit.id),"type":str(unit.type),"hp":float(unit.hp),"position":str(unit.position),"homePosition":str(unit.get("homePosition",unit.position)),"productionJobId":int(unit.get("productionJobId",-1))})
	var return_path: Array = []
	for point in game.ground_combat.guard_path(guard,guard.position,home): return_path.append(str(point))
	var owned_segment: Callable = Callable(troops.battlefield,"segment_clear")
	var owned_placement: Callable = Callable(troops.battlefield,"placement_clear")
	var return_context: Dictionary = {
		"hp":float(guard.hp),"maxHp":float(guard.maxHp),"combatState":str(guard.combatState),
		"movementBlocked":bool(guard.get("movementBlocked",false)),"home":str(home),
		"liveHomePosition":str(guard.homePosition),"position":str(guard.position),
		"returningObserved":returning,"homeReturnError":guard.position.distance_to(home),
		"targetId":int(guard.get("targetId",-1)),"guardDashTargetId":int(guard.get("guardDashTargetId",-1)),
		"guardDashActive":bool(guard.get("guardDashActive",false)),"guardTrail":guard.get("guardTrail",[]).duplicate(true),
		"guardRadius":float(guard.guardRadius),"occupancyRadius":float(guard.get("occupancyRadius",.008)),
		"guardZone":guard.get("guardZone",{}).duplicate(true),"unitCount":game.units.size(),
		"productionGroupCount":group_count,"units":native_units,"enemyCount":game.enemies.size(),
		"enemyIds":enemy_ids,"spawnQueue":game.spawn_queue.duplicate(true),"guardPathToHome":return_path,
		"guardSegmentSafe":game.ground_combat._guard_segment_safe(guard,guard.position,home),
		"landSegmentSafe":game.ground_combat.land_segment_safe(guard.position,home,float(guard.get("occupancyRadius",.008))),
		"providerSegmentClear":troops.battlefield.segment_clear(guard.position,home,float(guard.get("occupancyRadius",.008))),
		"ownedNavigationActive":game.ground_combat.structure_segment_clear.is_valid() and game.ground_combat.structure_segment_clear==owned_segment and troops.navigation_segment_binding==owned_segment,
		"ownedPlacementActive":game.structure_placement_clear.is_valid() and game.structure_placement_clear==owned_placement,
		"navigationGeneration":troops.navigation_battle_generation,"battleGeneration":game.battle_generation,
		"animation":str(guard.animation),"animationClock":float(guard.animationClock),
		"attackPlan":guard.get("attackPlan",{}).duplicate(true),"elapsed":game.elapsed,
		"animationTime":game.animation_time,"running":game.running,"finished":game.finished,
		"battleClosed":game.battle_closed,"betweenWaves":game.between_waves,"paused":game.paused
	}
	check(float(guard.hp)>0.0,"Native guard remains alive throughout the return fixture")
	check(returning and guard.position.distance_to(home)<.00001 and str(guard.combatState)=="guard","Native paid guard physically returns to the paid home after fixture target removal")
	observations.nativeGuard = {"source":"Paid actual Game; approved existing level-8 dash only; two native emplacement-assault targets","dash":dash,"windup":windup,"committedRelease":released,"hits":hits,"targetKind":str(target.kind),"targetCombatRole":str(target.combatRole),"targetHpBefore":health,"targetHpAfter":target.hp,"targetsRemovedByFixtureForReturn":2,"beforeReturnContext":before_return_context,"returnContext":return_context,"homeReturnError":guard.position.distance_to(home)}
	var frozen: Dictionary = snapshot_joints(troops)
	var native_frozen: String = game_signature(game)
	game.paused = true
	game.advance_simulation(1.0)
	for repeat in range(3): sync_native(game,troops)
	check(native_frozen==game_signature(game) and same_joints(frozen,snapshot_joints(troops)),"Paused actual Game and repeated render sync freeze guard/world joint state")
	var previous_generation: int = game.battle_generation
	game.load_map(stage)
	check(game.battle_generation>previous_generation,"Native same-ID stage reload advances its real battle generation")
	hold(game)
	var fresh: Dictionary = produce(game,troops,"naginata",Vector2(.5,.5))
	if not fresh.is_empty():
		var fresh_actor: Node3D = troops.actors[str(fresh.id)+":0"]
		# Headless material queries can return null for an unset shader default.
		# An explicit override must still be zero, and departure metadata absent.
		var fade_value: Variant = fresh_actor.materials.combined.get_shader_parameter("departure_fade")
		var fade_clear: bool = fade_value==null or ((fade_value is float or fade_value is int) and is_zero_approx(float(fade_value)))
		check(not bool(fresh_actor.current_state.get("attackReleased",false)) and not fresh_actor.has_meta("departure") and fade_clear,"Fresh native generation inherits neither a committed attack nor departure fade")
	observations.nativeGuard.generationReload = game.battle_generation
	troops.free()
	game.free()

func test_native_ninja_consumption() -> void:
	var stage: Dictionary = stage_fixture()
	var game: Node2D = make_game(stage,{"ninja":1})
	var troops: Control = renderer_for(stage)
	troops.bind_battle(game)
	hold(game)
	var events: Array = []
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	check(not game.ground_combat.ambush_sites.is_empty(),"Native isolated Game exposes a legal ninja deployment site")
	if game.ground_combat.ambush_sites.is_empty(): troops.free();game.free();return
	# Fortification is a native spawn option, not a role inferred from a model.
	# Keep the actual station produced by Game rather than relocating its tower.
	var target: Dictionary = game._spawn_enemy("enemy_gunner",20,{"pathIndex":0,"fortification":true})
	check(not target.is_empty() and game.ground_combat.is_tower_attacker(target),"Native spawn creates an actual stationary, completed emplacement tower")
	if target.is_empty() or not game.ground_combat.is_tower_attacker(target): troops.free();game.free();return
	check((target.position as Vector2).distance_to(target.fortificationPosition)<.00001,"Ninja fixture retains its real native fortification station")
	# HP is an initial fixture condition; all subsequent loss must be committed
	# by the real attack/event path below.
	target.hp = 60.0
	target.maxHp = 60.0
	var site: Dictionary = {}
	var nearest: float = INF
	for candidate in game.ground_combat.ambush_sites:
		if int(candidate.pathIndex)!=int(target.pathIndex): continue
		var distance: float = (candidate.position as Vector2).distance_to(target.position)
		if distance<nearest: nearest=distance;site=candidate
	check(not site.is_empty(),"Native tower has an actual same-path ninja deployment site")
	if site.is_empty(): troops.free();game.free();return
	var ninja: Dictionary = produce(game,troops,"ninja",site.position)
	if ninja.is_empty(): troops.free();game.free();return
	var id: int = int(ninja.id)
	var rendered_before: bool = troops.actors.has(str(id)+":0")
	for tick in range(1000):
		game.advance_simulation(.025)
		sync_native(game,troops)
		if game.ground_combat._unit(id).is_empty(): break
	var consumed: Dictionary = {}
	var hits: int = 0
	for event in events:
		if str(event.type)=="unit_consumed" and int(event.get("actorId",-1))==id: consumed=event
		if str(event.type)=="hit" and int(event.get("actorId",-1))==id:
			hits += 1
			check(absf(float(event.hpBefore)-float(event.hpAfter)-float(event.damage))<.00001,"Native level-1 ninja receipt equals its actual target HP loss")
	check(rendered_before and not consumed.is_empty() and hits>0,"Actual paid level-1 ninja approaches/strikes and emits a native consumption receipt")
	check(str(consumed.get("consumeReason","missing"))=="target_defeated" and float(target.hp)<=0.0,"Native successful assassination consumes the ninja only after its actual tower target is defeated")
	check(game.ground_combat._unit(id).is_empty() and not game.actor_states().any(func(value: Dictionary): return int(value.id)==id),"Consumed native ninja is absent from actual simulation and actor_states")
	check(not game.death_actors.any(func(value: Dictionary): return int(value.id)==id),"Native consumption creates no ninja corpse")
	check(not troops.side_markers.any(func(value: Dictionary): return int(value.id)==id),"Consumed ninja has no rendered health/side marker")
	var departure_key: String = str(id)+":0"
	if troops.actors.has(departure_key):
		var departing: Node3D = troops.actors[departure_key]
		check(departing.has_meta("departure") and str(departing.current_state.animation)!="death","Only the existing upright model is retained for a receipt-driven departure")
		var frozen: Dictionary = snapshot_joints(troops)
		game.paused = true
		game.advance_simulation(1.0)
		for repeat in range(3): sync_native(game,troops)
		check(same_joints(frozen,snapshot_joints(troops)),"Actual pause also freezes the receipt-driven departure pose")
		game.paused = false
	var wallet: int = game.gold
	for tick in range(16):
		game.advance_simulation(.025)
		sync_native(game,troops)
	check(not troops.actors.has(departure_key) and game.ground_combat._unit(id).is_empty(),"Completed native consumption fade removes the render model without reviving the paid unit")
	check(game.gold==wallet,"Consumption completion adds no refund or extra reward")
	observations.nativeNinja = {"source":"Paid actual Game; level 1 only, native spawned fortification station; no unapproved L2/L5/L8 effects","consumeReason":str(consumed.get("consumeReason","missing")),"nativeHits":hits,"targetId":int(target.id),"targetKind":str(target.kind),"targetCombatRole":str(target.combatRole),"nativeTowerPosition":str(target.fortificationPosition),"targetHpAfter":target.hp,"rendererRemoved":not troops.actors.has(departure_key)}
	troops.free()
	game.free()

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.contains("/tests/profiles/troops-world-integration/"):
		push_error("Troops world integration QA refuses a player profile")
		quit(2)
		return
	check(DisplayServer.get_name()=="headless","Integration runs under the headless display server, without a GPU visual claim")
	var hashes_before: Dictionary = {}
	for relative in SOURCE_PATHS:
		hashes_before[relative] = FileAccess.get_sha256("res://"+relative)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	catalog = data.get("units",[]) if data is Dictionary else []
	check(not catalog.is_empty(),"Native paid roster catalog is loaded without a player save")
	await test_fixed_mapping_and_input()
	test_continuous_pose_trace()
	test_provider_revision_and_replacement()
	test_native_guard_dash_return()
	test_native_ninja_consumption()
	var hashes: Dictionary = {}
	for relative in SOURCE_PATHS:
		hashes[relative] = FileAccess.get_sha256("res://"+relative)
		check(hashes[relative]==hashes_before[relative],"Observed integration source stayed stable through this run: "+relative)
	var output: FileAccess = FileAccess.open("user://qa_troops_world_integration.json",FileAccess.WRITE)
	check(output!=null,"Evidence report opens only in this isolated QA profile")
	if output!=null:
		output.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"sourceHashesBefore":hashes_before,"sourceHashesAfter":hashes,"scope":"COMMON-FIRST-R1 actual authored triangle adapter and actual Troops mapping/picking/continuous contacts/provider lifecycle, supplied uncommitted poses separated from paid native Game guard/ninja receipts","limitations":["Headless numeric joint/vertex observations cannot verify high-angle visual readability, clipping, image quality, GPU cost or final art.","The triangle plane fixtures are not accepted Stage01 or authored combat waves and are not registered in production maps.","Raw pose fixtures emit no committed shot/hit/heal events; native scenarios isolate paid level-8 guard and level-1 ninja only.","No new ninja L2/L5/L8 effects, dependency installation, production modification or player-save access."]},"  "))
		output.close()
	print("TROOPS_WORLD_INTEGRATION_QA ",JSON.stringify({"checks":checks,"failures":failures,"report":ProjectSettings.globalize_path("user://qa_troops_world_integration.json"),"sourceHashes":hashes}))
	quit(0 if failures.is_empty() else 1)
