extends SceneTree
## Continuous controlled GPU motion + native-wave fixture, never final-map QA.
const Troops = preload("res://native/troops_3d.gd")
const Battle = preload("res://native/game.gd")
const WorldSurface = preload("res://native/battlefield_world_adapter.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const ENEMIES: Array = ["enemy_archer","enemy_light","enemy_samurai","enemy_gunner","enemy_heavy","enemy_light","enemy_cavalry","enemy_heavy"]
var checks: int = 0
var failures: Array = []
var captures: Array = []
var observations: Array = []
var renderer: Control
var heading: Label
var labels: Array = []

const SOURCES: Array = ["native/troops_3d.gd","native/troop_action_presentation.gd","native/sengoku_actor_3d.gd","native/sengoku_skinned_renderer.gd","native/sengoku_equipment_geometry.gd","native/actor_materials.gd","native/battlefield_world_adapter.gd","native/game.gd","native/ground_combat.gd","native/unit_skills.gd","native/units.json","tests/qa_troop_motion_gpu.gd"]

func source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path in SOURCES: hashes[path] = FileAccess.get_sha256("res://"+str(path))
	return hashes

func authored_geometry(grade: float) -> Dictionary:
	var vertices: Array = []
	for p in [Vector2.ZERO,Vector2(0,1),Vector2(1,0),Vector2.ONE]:
		vertices.append({"x":(p.x-.5)*18.5,"y":.35+(p.x-.5)*grade,"z":(p.y-.5)*13.5})
	return {"schemaVersion":1,"simulationBounds":{"x":-9.25,"z":-6.75,"width":18.5,"depth":13.5},"vertices":vertices,"triangles":[0,1,2,2,1,3],"blockedPolygons":[],"camera":{"elevationDegrees":58}}

func use_surface(stage: Dictionary, grade: float) -> void:
	var supplied: Dictionary = stage.duplicate(true)
	supplied["worldGeometry"] = authored_geometry(grade)
	renderer.set_stage(supplied)
	var terrain: Node3D = WorldSurface.new()
	renderer.set_terrain_provider(terrain)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("565b51")
	material.roughness = 1
	terrain.set_surface_material(material)
	check(renderer.uses_world_geometry() and bool(terrain.diagnostics().ready),"Actual authored world provider binds the actual Troops renderer")

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		if failures.size()<25: push_error("TROOP GPU "+message)

func setup_renderer(stage: Dictionary) -> void:
	renderer=Troops.new();root.add_child(renderer);renderer.set_process(false)
	renderer.position=Vector2(0,48);renderer.set_field_size(Vector2(1280,736));renderer.set_stage(stage)
	heading=Label.new();heading.position=Vector2(18,10);heading.add_theme_font_size_override("font_size",20);root.add_child(heading)

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image=root.get_texture().get_image()
	var path: String=ProjectSettings.globalize_path("user://"+name+".png")
	check(frame!=null and frame.get_width()==root.size.x,"Actual GPU framebuffer exists: "+name)
	check(frame.save_png(path)==OK,"GPU frame saves: "+name)
	captures.append(path)
	print("TROOP_GPU_CAPTURE ",path)

func state_at(index: int,clock: float) -> Dictionary:
	var friendly: bool=index<8
	var slot: int=index%8
	var home: Vector2=Vector2(.13+(slot%4)*.245,.22+(slot/4)*.22+(.44 if not friendly else 0))
	var point: Vector2=home
	var animation: String="idle"
	var action_clock: float=clock
	var direction: Vector2=Vector2(0,-1)
	if clock>=3.0: point+=Vector2(.014*1.2,.019*1.2)
	if clock>=.6 and clock<3.0:
		animation="walk";action_clock=clock-.6
		var travel: float=minf(action_clock,2.4)
		point+=Vector2(.014*minf(travel,1.2),.019*maxf(0,travel-1.2))
		direction=Vector2(1,0) if travel<1.2 else Vector2(0,1)
	elif clock>=3.0 and clock<3.5:
		animation="attack";action_clock=clock-3.0;direction=Vector2(-.4,-1).normalized()
	elif clock>=4.8:
		animation="death";action_clock=clock-4.8
	var type_name: String=str(TYPES[slot]) if friendly else str(ENEMIES[slot])
	var release: float=1.0/3.0 if type_name in ["archer","enemy_archer","samurai","enemy_samurai"] else .25
	var data: Dictionary={"id":index+1,"type":type_name,"friendly":friendly,"hostile":not friendly,"x":point.x,"y":point.y,"aimX":direction.x,"aimY":direction.y,"animation":animation,"animationClock":action_clock,"animationPhase":slot*.11,"motionTime":clock,"attackDuration":.5,"releaseTime":release,"attackReleased":animation=="attack" and action_clock>=release,"attackCancelled":false,"hp":100,"maxHp":100,"hitClock":.09 if clock>=4.4 and clock<4.52 else 0,"dead":animation=="death"}
	if type_name in ["gunner","enemy_gunner"] and clock>=3.5 and clock<4.4:
		data.merge({"motionPhase":"reload","reloadActive":true,"reloadProgress":(clock-3.5)/.9},true)
	if type_name=="monk" and animation=="attack":
		data.merge({"animation":"heal","healing":true,"healDuration":.55,"healCommittedAt":3.0,"healAmount":6,"healingTargetId":2},true)
	return data

func sample_motion(grade: float,label: String) -> void:
	use_surface(fixture(),grade)
	heading.text="통제 모션 검증 · "+label+" · 아군 8종 / 적군 · 최종 전장 아님"
	var largest_error: float=0
	var largest_yaw: float=0
	var frame_count: int=0
	var penetration: float=0
	var contact_gap: float=0
	var hoof_error: float=0
	for frame in range(163):
		var clock: float=frame/30.0
		var states: Array=[]
		for index in range(16): states.append(state_at(index,clock))
		renderer.sync_actor_states(states)
		for actor in renderer.actors.values():
			check(actor.position.is_finite() and actor.bones.weapon.global_transform.is_finite(),"Continuous root/weapon transforms remain finite")
			if str(actor.current_state.animation)!="death":
				var logical: Vector2=Vector2(actor.current_state.x,actor.current_state.y)
				largest_error=maxf(largest_error,actor.position.distance_to(renderer.normalized_to_world(logical)))
				if actor.unit_type!="commander":
					for side in ["L","R"]:
						var nearest: float=INF
						for vertex in actor.terrain_sole_supports:
							var support: Vector3=actor.bones["foot"+side].global_transform*vertex
							nearest=minf(nearest,support.y-renderer._ground_contact_height(support))
						penetration=maxf(penetration,-nearest)
						if str(actor.current_state.animation)!="walk" or bool(actor.motion_debug.get("leftStance" if side=="L" else "rightStance",true)):
							contact_gap=maxf(contact_gap,nearest)
				else:
					for leg in range(4):
						var key: String="horse_calf%d"%leg
						var nearest: float=INF
						for vertex in actor.terrain_hoof_supports.get(key,[]):
							var support: Vector3=actor.bones[key].global_transform*vertex
							nearest=minf(nearest,support.y-renderer._ground_contact_height(support))
						var expected: float=(.005+actor.hoof_lifts[leg])*actor.global_basis.get_scale().y
						hoof_error=maxf(hoof_error,absf(nearest-expected))
				if str(actor.current_state.animation)=="attack" and bool(actor.current_state.attackReleased):
					var forward: Vector3=renderer._world_heading(logical,Vector2(actor.current_state.aimX,actor.current_state.aimY)).normalized()
					largest_yaw=maxf(largest_yaw,acos(clampf((-actor.global_basis.z).normalized().dot(forward),-1,1)))
		if frame in [0,18,30,48,66,84,90,96,100,105,114,132,135,144,156,162]:
			await capture("motion-"+label+"-%03d"%frame)
		else: await process_frame
		frame_count+=1
	check(largest_error<.00001,"Presentation never offsets a moving/attacking root from logical ground")
	check(largest_yaw<.075,"By committed attack, body facing matches actual target direction")
	check(penetration<.004 and contact_gap<.004,"Live field skin foot supports stay on actual authored floor during standing/stance")
	check(hoof_error<.004,"Live mounted hoof undersides preserve actual gait lift above authored floor")
	observations.append({"scenario":label,"frames":frame_count,"resolution":[root.size.x,root.size.y],"slope":grade,"maxRootError":largest_error,"maxReleaseYawRadians":largest_yaw,"maxFootPenetration":penetration,"maxStanceGroundGap":contact_gap,"maxHoofLiftError":hoof_error,"scope":"Supplied continuous uncommitted poses through actual Troops/world/field skin, including stops, turns, all friendly/enemy poses. Does not prove final-map behavior or functional release semantics."})

func fixture() -> Dictionary:
	return {"id":"troop-motion-wave-fixture","stageNumber":15,"theme":"farm","initialGold":5000,"unitLimit":20,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.07,"y":.5},{"x":.44,"y":.5},{"x":.44,"y":.64},{"x":.90,"y":.64}]}],"objectives":[{"id":"main","x":.9,"y":.64,"hp":500}],"buildZones":[{"id":"ranged","x":.5,"y":.32,"r":.2}],"tactics":{"groundPosts":[{"id":"front","pathIndex":0,"segmentIndex":2,"t":.45,"r":.21,"guardRadius":.18}]}}

func mission_game(levels: Dictionary) -> Node2D:
	var supplied: Dictionary={"id":"troop-motion-controlled-mission","stageNumber":15,"theme":"forest","initialGold":6000,"unitLimit":24,"totalWaves":100,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":1000}],"buildZones":[{"id":"wall","x":.5,"y":.65,"r":.08}],"tactics":{"groundPosts":[{"id":"defense","pathIndex":0,"segmentIndex":0,"t":.5,"r":.22,"guardRadius":.22}]},"worldGeometry":authored_geometry(1.2)}
	var game: Node2D=Battle.new();root.add_child(game);game.set_process(false)
	game.configure_roster(JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units,TYPES,levels)
	game.load_map(supplied);game.set_seed(887);game.three_d_enabled=true
	game.set_field_rect(Rect2(renderer.position,renderer.field_size))
	renderer.bind_battle(game);use_surface(supplied,1.2)
	game.start_battle();game.enemies.clear()
	game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=100000.0
	return game

func mission_step(game: Node2D) -> void:
	game.advance_simulation(.025)
	var before: String=JSON.stringify({"units":game.units,"enemies":game.enemies,"gold":game.gold,"projectiles":game.projectiles,"elapsed":game.elapsed})
	renderer.sync_actor_states(game.actor_states())
	check(before==JSON.stringify({"units":game.units,"enemies":game.enemies,"gold":game.gold,"projectiles":game.projectiles,"elapsed":game.elapsed}),"Controlled native GPU render preserves actual simulation")

func mission_produce(game: Node2D,type_name: String,point: Vector2) -> Dictionary:
	var wallet: int=game.gold
	var cost: int=game.recruit_cost(type_name)
	check(game.begin_placement(type_name,0) and game.place_unit(point.x,point.y),"Controlled GPU mission submits legal actual paid "+type_name)
	check(game.gold==wallet-cost,"Controlled GPU mission uses native catalog charge")
	for tick in range(320):
		mission_step(game)
		if tick%4==0: await process_frame
		for unit in game.units:
			if str(unit.type)==type_name: return unit
	check(false,"Controlled GPU production finishes: "+type_name)
	return {}

func native_missions() -> void:
	heading.text="실제 기능 사건·지형·모션 연결 · 통제 임무 / 최종 전장 아님"
	var game: Node2D=mission_game({"naginata":8})
	var guard: Dictionary=await mission_produce(game,"naginata",Vector2(.5,.5))
	if not guard.is_empty():
		for tick in range(320):
			mission_step(game)
			if tick%4==0: await process_frame
		var targets: Array=[]
		for offset in [Vector2(-.12,0),Vector2(-.13,.01)]:
			var target: Dictionary=game._spawn_enemy("enemy_samurai",20,{"pathIndex":0})
			target.position=guard.homePosition+offset;target.pointIndex=1;target.ingressActive=false;target.speed=0.0;target.hp=500.0;target.maxHp=500.0
			targets.append(target)
		var phases: Dictionary={}
		var dash: bool=false
		var released: bool=false
		for tick in range(800):
			mission_step(game)
			await process_frame
			dash=dash or bool(guard.get("guardDashActive",false)) or str(guard.combatState)=="guard_dash"
			check(guard.position.distance_to(guard.homePosition)<=float(guard.guardRadius)+.00002,"Actual GPU guard approach/dash stays inside defense boundary")
			var actor: Node3D=renderer.actors.get(str(guard.id)+":0")
			if is_instance_valid(actor):
				var phase: String=str(actor.current_state.get("motionPhase",""))
				if not phases.has(phase): phases[phase]=true;await capture("native-guard-"+phase)
				released=released or bool(actor.current_state.get("attackReleased",false))
			if float(targets[0].hp)<500.0: break
		check(dash and released and float(targets[0].hp)<500.0,"GPU guard existing level-8 dash reaches actual native damage/release")
		for target in targets: game.enemies.erase(target)
		var returning: bool=false
		for tick in range(600):
			mission_step(game);await process_frame
			if str(guard.combatState)=="guard_return" and not returning: returning=true;await capture("native-guard-return")
			if str(guard.combatState)=="guard" and guard.position.distance_to(guard.homePosition)<.00001: break
		check(returning and guard.position.distance_to(guard.homePosition)<.00001,"GPU guard returns to actual paid home after fixture target removal")
		await capture("native-guard-home")
		observations.append({"scenario":"native-guard-controlled","dash":dash,"released":released,"returning":returning,"phases":phases.keys(),"targetHpAfter":targets[0].hp,"scope":"Paid existing level-8 guard, actual native emplacement-assault pair. Initial positions/speed/HP are controlled fixture conditions; pair removed for return transition; manual native clock advances. Not natural-wave evidence."})
	renderer.bind_battle(null);game.free()
	game=mission_game({"ninja":1})
	var target: Dictionary=game._spawn_enemy("enemy_gunner",20,{"pathIndex":0,"fortification":true})
	check(not target.is_empty() and game.ground_combat.is_tower_attacker(target),"GPU ninja uses actual native spawned fortification")
	if not target.is_empty() and game.ground_combat.is_tower_attacker(target):
		target.hp=60.0;target.maxHp=60.0
		var point: Vector2=Vector2.ZERO
		var nearest: float=INF
		for site in game.ground_combat.ambush_sites:
			if int(site.pathIndex)!=int(target.pathIndex): continue
			var distance: float=site.position.distance_to(target.position)
			if distance<nearest: nearest=distance;point=site.position
		check(is_finite(nearest),"GPU ninja has a real same-path legal placement site")
		var events: Array=[]
		game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
		var ninja: Dictionary=await mission_produce(game,"ninja",point)
		if not ninja.is_empty():
			var key: String=str(ninja.id)+":0"
			await capture("native-ninja-approach")
			var captured_attack: bool=false
			for tick in range(1000):
				mission_step(game);await process_frame
				if str(ninja.animation)=="attack" and not captured_attack: captured_attack=true;await capture("native-ninja-strike")
				if game.ground_combat._unit(int(ninja.id)).is_empty(): break
			var consumed: Dictionary={}
			for event in events:
				if str(event.type)=="unit_consumed" and int(event.get("actorId",-1))==int(ninja.id): consumed=event
			check(str(consumed.get("consumeReason",""))=="target_defeated","GPU level-1 ninja actually defeats its assigned tower and receives native consumption")
			await capture("native-ninja-departure-start")
			for tick in range(16):
				mission_step(game);await process_frame
				if tick==5: await capture("native-ninja-departure-mid")
			check(not renderer.actors.has(key) and game.ground_combat._unit(int(ninja.id)).is_empty(),"GPU receipt-driven departure removes actual ninja model without reuse")
			await capture("native-ninja-departure-end")
			observations.append({"scenario":"native-ninja-controlled","consumeReason":consumed.get("consumeReason","missing"),"renderModelRemoved":not renderer.actors.has(key),"scope":"Paid level-1 ninja and actual native fortification station; initial tower HP60; actual event bridge plus shader departure. Manual native clock advance, not natural wave or unapproved ninja effect."})
	renderer.bind_battle(null);game.free()

func native_wave() -> void:
	var game: Node2D=Battle.new();root.add_child(game);game.set_process(false)
	var catalog: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	game.configure_roster(catalog,TYPES,{})
	var supplied: Dictionary=fixture()
	supplied["worldGeometry"]=authored_geometry(1.2)
	game.load_map(supplied);game.set_seed(404)
	game.three_d_enabled=true
	game.set_field_rect(Rect2(renderer.position,renderer.field_size))
	renderer.bind_battle(game);use_surface(game.config,1.2)
	var total_shots: int=0
	var events: Array=[]
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	for type_name in TYPES:
		check(game.begin_placement(str(type_name)),"Native fixture uses actual paid recruit: "+str(type_name))
		if str(game.placement_contract(str(type_name)).deploymentKind)=="marching": continue
		var placed: bool=false
		for hint in game.placement_hints:
			for offset in [Vector2.ZERO,Vector2(.06,0),Vector2(-.06,0),Vector2(0,.06),Vector2(0,-.06),Vector2(.06,.06),Vector2(-.06,.06)]:
				var point: Vector2=Vector2(hint.x,hint.y)+offset
				if game.placement_preview(point).get("valid",false):
					placed=game.place_unit(point.x,point.y)
					if placed: break
			if placed: break
		check(placed,"Native fixture reserves legal terrain placement: "+str(type_name))
		if not placed: game.cancel_recruit()
	game.start_battle()
	game.set_speed(2.0)
	game.set_process(true)
	heading.text="실시간 전투·실제 Troops3D · 격리 시험 표면 / 최종 Stage 01 아님"
	var observed_states: Dictionary={}
	var start: int=Time.get_ticks_usec()
	var end: int=start+30000000
	var frame: int=0
	var next_capture: int=0
	while Time.get_ticks_usec()<end:
		await process_frame
		if game.between_waves and not game.finished: game.continue_wave()
		var states: Array=game.actor_states()
		renderer.sync_actor_states(states)
		for data in states:
			observed_states[str(data.animation)]=true
			if bool(data.get("friendly",false)): observed_states[str(data.type)]=true
		var frozen: String=JSON.stringify({"units":game.units,"enemies":game.enemies,"projectiles":game.projectiles,"gold":game.gold})
		renderer.sync_actor_states(states)
		check(JSON.stringify({"units":game.units,"enemies":game.enemies,"projectiles":game.projectiles,"gold":game.gold})==frozen,"GPU presentation cannot change simulation health/movement/projectiles/cost")
		if game.elapsed>=float(next_capture+1)*15:
			await capture("native-wave-%02d"%next_capture)
			next_capture+=1
		frame+=1
	game.set_process(false)
	for event in events:
		if str(event.type)=="shot": total_shots+=1
	check(total_shots>0 and observed_states.has("walk") and observed_states.has("attack"),"Natural native fixture wave actually walks and attacks")
	observations.append({"scenario":"native-wave","wallSeconds":float(Time.get_ticks_usec()-start)/1000000,"simulationSeconds":game.elapsed,"renderFrames":frame,"states":observed_states.keys(),"shots":total_shots,"events":events.size(),"manualTimeAdvance":false,"enemyInjection":false,"scope":"Native realtime process at existing 2x speed, paid recruitment and automatic wave spawning through actual Troops/triangle surface on isolated QA fixture. No adopted campaign/complete battle claim."})
	renderer.action_presentation.unbind();renderer.battle=null;game.free()

func run() -> void:
	if OS.get_cmdline_user_args().has("--v2-posed"):
		await v2_run()
		return
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if DisplayServer.get_name()=="headless" or not profile.contains("/tests/profiles/troop-motion-gpu/"):
		push_error("GPU motion QA requires isolated troop-motion-gpu profile and GPU renderer");quit(2);return
	root.size=Vector2i(1280,800)
	var before: Dictionary=source_hashes()
	setup_renderer(fixture())
	await sample_motion(0,"flat")
	await sample_motion(2.0,"slope")
	root.size=Vector2i(1440,900)
	renderer.set_field_size(Vector2(1440,836))
	await sample_motion(2.0,"slope-1440")
	await native_missions()
	await native_wave()
	var after: Dictionary=source_hashes()
	check(before==after,"Relevant sources stay unchanged throughout the serialized GPU run")
	var report: Dictionary={"checks":checks,"failures":failures,"gpu":RenderingServer.get_video_adapter_name(),"captures":captures,"observations":observations,"sourceHashesBefore":before,"sourceHashesAfter":after,"finalStage01NaturalWaveVerified":false,"directiveId":"JP_DF-HQ-20261008-COMMON-FIRST-R1"}
	var output: FileAccess=FileAccess.open("user://qa_troop_motion_gpu.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("TROOP_MOTION_GPU_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"gpu":report.gpu,"report":ProjectSettings.globalize_path("user://qa_troop_motion_gpu.json")}))
	renderer.queue_free();heading.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)

# V2 is a separate, naturally clocked Game/Troops observation. The legacy supplied-pose
# and controlled-mission sequence above is deliberately not entered by this flag.
const V2_CANDIDATE: String = "res://assets/battlefields-remaster/stage01-candidate-v2.json"
const V2_SHA: String = "305b0970444a1099cb0bffd0755333b0c246a2fb2d53c117919b21413f50ff84"
# Measurement epsilon only: no Game/provider collision margin is changed.
const V2_PLANE_EPS: float = .0000001
const V2_AREA_EPS: float = .00000000000001
var v2_mesh_cache: Dictionary = {}
var v2_coverage: Dictionary = {}
var v2_previous: Dictionary = {}
var v2_shots: Dictionary = {}
var v2_events: Array = []
var v2_event_counts: Dictionary = {}
var v2_contacts: Array = []
var v2_clock: Array = []
var v2_contact_count: int = 0
var v2_touch_count: int = 0
var v2_collapsed: int = 0
var v2_triangle_count: int = 0
var v2_samples: int = 0
var v2_min_sole_gap: float = INF
var v2_invalid_supports: int = 0
var v2_nonwalkable_supports: int = 0
var v2_support_witnesses: Array = []
var v2_truncated_batches: int = 0

func v2_point(p: Vector3) -> Array:
	return [p.x,p.y,p.z]

func v2_basis(b: Basis) -> Array:
	return [v2_point(b.x),v2_point(b.y),v2_point(b.z)]

func v2_signature(game: Node) -> String:
	return JSON.stringify({
		"units":game.units,"enemies":game.enemies,"objectives":game.objectives,"projectiles":game.projectiles,"effects":game.effects,
		"deathActors":game.death_actors,"gold":game.gold,"kills":game.kills,"elapsed":game.elapsed,"animationTime":game.animation_time,
		"generation":game.battle_generation,"nextEventID":game.next_event_id,"nextID":game.next_id,
		"nextRecruitmentID":game.next_recruitment_id,"recruits":game.recruits,"pending":game.pending,"recruitmentQueue":game.recruitment_queue,
		"spawnQueue":game.spawn_queue,"spawnSourceWaves":game.spawn_source_waves,"spawnMetadata":game.spawn_metadata,"spawnClock":game.spawn_clock,
		"skillClock":game.unit_skills.clock,"skillReleases":game.unit_skills._seen_releases,
		"paused":game.paused,"running":game.running,"betweenWaves":game.between_waves,"finished":game.finished
	})

func v2_pose_signature(troops: Node) -> String:
	var poses: Dictionary = {}
	for key in troops.actors:
		var actor: Node3D = troops.actors[key]
		var palette: Array = []
		for pose in actor.skinned_renderer.joint_poses: palette.append(str(pose))
		var groups: Dictionary = {}
		for name in actor.skinned_renderer.groups:
			var group: MeshInstance3D = actor.skinned_renderer.groups[name]
			groups[str(name)]={"visible":group.is_visible_in_tree(),"transform":str(group.global_transform)}
		poses[str(key)]={"transform":str(actor.global_transform),"palette":palette,"groups":groups,"motionTime":actor.current_state.get("motionTime",0)}
	return JSON.stringify(poses)

func v2_hash_tree(path: String, hashes: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir==null: return
	for file_name in dir.get_files():
		if file_name.ends_with(".uid") or file_name.ends_with(".import"): continue
		var file_path: String = path.path_join(file_name)
		hashes[file_path] = FileAccess.get_sha256(file_path)
	for child in dir.get_directories(): v2_hash_tree(path.path_join(child),hashes)

func v2_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for directory in ["res://native","res://assets/battlefields-remaster","res://assets/models/battlefield","res://assets/materials/terrain","res://assets/materials/sengoku","res://assets/materials/metal_plate_02","res://assets/materials/denim_fabric","res://assets/materials/brown_leather","res://assets/units-animated","res://assets/fonts"]:
		v2_hash_tree(str(directory),hashes)
	for path in [V2_CANDIDATE,"res://assets/units-atlas.png","res://tests/qa_troop_motion_gpu.gd","res://tools/run.ps1","res://project.godot"]:
		hashes[str(path)] = FileAccess.get_sha256(str(path))
	return hashes

func v2_fixture(candidate: Dictionary, stage_profile: String) -> Dictionary:
	# Current candidate geometry, objective fallback and paid deployment areas.
	# Canonical profile is primary; alias is an explicit comparison only.
	var stage: Dictionary = candidate.duplicate(true)
	stage.merge({"id":"basic-forest" if stage_profile=="canonical" else "vis01-tactical-candidate-v2","title":"마루네 · 철수 엄호 후보","candidateOnly":true,"theme":"grass"},true)
	if stage_profile=="canonical": stage["stageNumber"]=1
	var bounds: Dictionary = stage.worldGeometry.simulationBounds
	var points: Array = []
	for p in stage.visualComposition.route:
		points.append({"x":(float(p[0])-float(bounds.x))/float(bounds.width),"y":(float(p[1])-float(bounds.z))/float(bounds.depth)})
	stage["paths"] = [{"id":"candidate-approach","objectiveId":"candidate-objective","points":points}]
	var objective: Array = stage.visualComposition.objectiveStandingSample
	stage["objectives"] = [{"id":"candidate-objective","label":"철수 엄호 지점","x":(float(objective[0])-float(bounds.x))/float(bounds.width),"y":(float(objective[1])-float(bounds.z))/float(bounds.depth),"hp":25}]
	var zones: Array = []
	for area in stage.visualComposition.deploymentAreas:
		zones.append({"id":str(area.id),"x":(float(area.center[0])-float(bounds.x))/float(bounds.width),"y":(float(area.center[1])-float(bounds.z))/float(bounds.depth),"r":float(area.radiusNormalized),"elevation":int(area.gameplayElevation),"terrain":"earth","label":"흙 진지"})
	stage["buildZones"] = zones
	return stage

func v2_settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func v2_convex(instance: MeshInstance3D, role: String) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var triangles: Array = []
	for surface in range(instance.mesh.get_surface_count()):
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var local: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var offset: int = vertices.size()
		for p in local: vertices.append(instance.global_transform*p)
		for corner in range(0,indices.size(),3): triangles.append([offset+indices[corner],offset+indices[corner+1],offset+indices[corner+2]])
	check(not vertices.is_empty() and not triangles.is_empty(),"V2 actual gate indexed mesh exists: "+role)
	if vertices.is_empty(): return {}
	var centroid: Vector3 = Vector3.ZERO
	var bounds: AABB = AABB(vertices[0],Vector3.ZERO)
	for p in vertices: centroid+=p;bounds=bounds.expand(p)
	centroid/=float(vertices.size())
	var planes: Array = []
	for triangle in triangles:
		var a: Vector3 = vertices[int(triangle[0])]
		var cross: Vector3 = (vertices[int(triangle[1])]-a).cross(vertices[int(triangle[2])]-a)
		if cross.length_squared()<=V2_AREA_EPS: continue
		var normal: Vector3 = cross.normalized()
		var distance: float = normal.dot(a)
		if normal.dot(centroid)>distance: normal=-normal;distance=-distance
		var duplicate: bool = false
		for plane in planes:
			if normal.distance_to(plane.normal)<.00001 and absf(distance-float(plane.distance))<.00001: duplicate=true;break
		if not duplicate: planes.append({"normal":normal,"distance":distance})
	check(planes.size()==(6 if role=="beam" else 12),"Actual gate closed convex face count: "+role)
	var oriented: bool = true
	for p in vertices:
		for plane in planes:
			if plane.normal.dot(p)-float(plane.distance)>.00001: oriented=false
	check(oriented,"Actual gate plane orientation encloses its own transformed vertices: "+role)
	var side_planes: Array = []
	for plane in planes:
		if absf(plane.normal.y)<.1: side_planes.append(plane)
	return {"role":role,"planes":planes,"sidePlanes":side_planes,"bounds":bounds,"centroid":centroid,"nodePath":str(instance.get_path()),"worldBasis":v2_basis(instance.global_basis),"worldPosition":v2_point(instance.global_position)}

func v2_gate(visuals: Node3D, provider: Node, candidate: Dictionary) -> Array:
	var gate: Dictionary = candidate.visualComposition.gate
	var feet: Array = []
	for center in gate.jambCenters:
		var p: Vector3 = Vector3(float(center[0]),0,float(center[1]))
		p.y=provider.sample_world_height(p)
		check(p.is_finite(),"V2 actual jamb ground is finite")
		feet.append(p)
	var height: float = float(gate.clearHeight)
	var beam_origin: Vector3 = (feet[0]+feet[1])*.5+Vector3.UP*(height+.10)
	var beam_size: Vector3 = Vector3(float(gate.width)+.32,.18,.20)
	var beam_basis: Basis = Basis(Vector3.UP,deg_to_rad(float(gate.rotationDegrees)))
	var matches: Dictionary = {"beam":[],"jamb0":[],"jamb1":[]}
	for node in visuals.get_children():
		if not node is MeshInstance3D: continue
		var mesh: Mesh = node.mesh
		if mesh is BoxMesh and mesh.size.distance_to(beam_size)<.000001 and node.position.distance_to(beam_origin)<.000001 and node.basis.is_equal_approx(beam_basis):
			matches.beam.append(node)
		elif mesh is CylinderMesh and absf(mesh.height-(height+.205))<.000001 and absf(mesh.bottom_radius-.105)<.000001 and absf(mesh.top_radius-.0987)<.000001 and mesh.radial_segments==10:
			for index in range(2):
				if node.position.distance_to(feet[index]+Vector3.UP*(height+.155)*.5)<.000001 and node.basis.is_equal_approx(Basis.IDENTITY): matches["jamb%d"%index].append(node)
	var volumes: Array = []
	for role in ["beam","jamb0","jamb1"]:
		check(matches[role].size()==1,"Exactly one actual scene mesh matches candidate "+role)
		if matches[role].size()==1:
			var volume: Dictionary = v2_convex(matches[role][0],str(role))
			if not volume.is_empty(): volumes.append(volume)
	return volumes

func v2_clip(input: Array, planes: Array) -> Array:
	var polygon: Array = input
	for plane in planes:
		if polygon.is_empty(): break
		var clipped: Array = []
		var previous: Vector3 = polygon.back()
		var previous_depth: float = float(plane.distance)-plane.normal.dot(previous)
		for point in polygon:
			var depth: float = float(plane.distance)-plane.normal.dot(point)
			var inside: bool = depth>=-V2_PLANE_EPS
			var previous_inside: bool = previous_depth>=-V2_PLANE_EPS
			if inside!=previous_inside:
				var denominator: float = previous_depth-depth
				if absf(denominator)>0: clipped.append(previous.lerp(point,clampf(previous_depth/denominator,0,1)))
			if inside: clipped.append(point)
			previous=point;previous_depth=depth
		polygon=clipped
	return polygon

func v2_area(polygon: Array) -> float:
	var area: float = 0
	for index in range(1,polygon.size()-1): area+=(polygon[index]-polygon[0]).cross(polygon[index+1]-polygon[0]).length()*.5
	return area

func v2_surface(mesh: Mesh, surface: int, names: Array) -> Dictionary:
	var key: String = str(mesh.get_instance_id())+":"+str(surface)+":"+str(names.hash())
	if v2_mesh_cache.has(key): return v2_mesh_cache[key]
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride: int = int(bones.size()/maxi(1,vertices.size()))
	var valid: bool = not indices.is_empty() and indices.size()%3==0 and stride in [4,8] and weights.size()==bones.size()
	check(valid,"Actual V2 field surface has indexed vertices and joint weights")
	if not valid: return {}
	var joint_ids: PackedInt32Array = PackedInt32Array()
	var supports: Array = []
	for index in range(vertices.size()):
		var joint: int = -1
		var weight: float = -1
		for slot in range(stride):
			if weights[index*stride+slot]>weight: joint=bones[index*stride+slot];weight=weights[index*stride+slot]
		joint_ids.append(joint)
		if joint>=0 and joint<names.size() and str(names[joint]) in ["footL","footR","horse_calf0","horse_calf1","horse_calf2","horse_calf3"]:
			supports.append(index)
	var result: Dictionary = {"vertices":vertices,"indices":indices,"bones":bones,"weights":weights,"stride":stride,"joints":joint_ids,"supports":supports}
	v2_mesh_cache[key]=result
	return result

func v2_category(name: String) -> String:
	if name=="weapon" or name.begins_with("bowString") or name=="nockedArrow": return "equipment"
	if name=="head" or name=="horse_head": return "head"
	return "body"

func v2_actor_record(actor: Node3D, game: Node) -> Dictionary:
	var state: Dictionary = actor.current_state
	var source_wave: Variant = null
	if not bool(state.get("friendly",false)):
		for enemy in game.enemies:
			if int(enemy.id)==int(state.get("id",-1)): source_wave=enemy.get("sourceWave",null);break
	var bone_flags: Dictionary = {}
	for name in ["weapon","bowStringLower","bowStringUpper","nockedArrow"]:
		if actor.bones.has(name): bone_flags[name]={"visible":actor.bones[name].visible,"scale":v2_point(actor.bones[name].scale),"worldBasis":v2_basis(actor.bones[name].global_basis)}
	return {"id":int(state.get("id",-1)),"type":str(state.get("type",actor.unit_type)),"kind":str(state.get("kind","")),"friendly":bool(state.get("friendly",false)),"evolution":actor.evolution_stage,"stageID":str(game.config.id),"sourceWave":source_wave,"nativeElapsed":game.elapsed,"poseMotionTime":state.get("motionTime",0),"animation":state.get("animation",""),"phase":state.get("motionPhase",""),"animationClock":state.get("animationClock",0),"attackReleased":state.get("attackReleased",false),"attackCancelled":state.get("attackCancelled",false),"dead":state.get("dead",false),"sailing":state.get("sailing",false),"normalizedPosition":[state.get("x",0),state.get("y",0)],"worldPosition":v2_point(actor.global_position),"actorScale":v2_point(actor.scale),"bodyWorldBasis":v2_basis(actor.global_basis),"weaponWorldBasis":v2_basis(actor.bones.weapon.global_basis),"boneFlagsDiagnosticOnly":bone_flags}

func v2_probe_actor(actor: Node3D, provider: Node, volumes: Array, record: Dictionary, deadline: int) -> Dictionary:
	if Time.get_ticks_usec()>=deadline: v2_truncated_batches+=1;return {"status":"TRUNCATED_DEADLINE","geometryComplete":false}
	var skin: Node3D = actor.skinned_renderer
	var gate_projection: bool = false
	var categories: Dictionary = {"body":0,"head":0,"equipment":0}
	var sole_samples: Dictionary = {}
	var finite_pose: bool = actor.global_transform.is_finite()
	for group_name in skin.groups:
		var instance: MeshInstance3D = skin.groups[group_name]
		if not instance.is_visible_in_tree(): continue
		# Flat field groups do not inherit each source bone's visibility. Tiny
		# arrow/string palette scales remain measured until actually degenerate.
		for surface in range(instance.mesh.get_surface_count()):
			if Time.get_ticks_usec()>=deadline: v2_truncated_batches+=1;return {"status":"TRUNCATED_DEADLINE","geometryComplete":false}
			var cache: Dictionary = v2_surface(instance.mesh,surface,skin.joint_names)
			if cache.is_empty(): continue
			var world: PackedVector3Array = PackedVector3Array()
			for index in range(cache.vertices.size()):
				if index%128==0 and Time.get_ticks_usec()>=deadline: v2_truncated_batches+=1;return {"status":"TRUNCATED_DEADLINE","geometryComplete":false}
				var posed: Vector3 = Vector3.ZERO
				for slot in range(int(cache.stride)):
					var weight: float = cache.weights[index*cache.stride+slot]
					if weight==0: continue
					var joint: int = cache.bones[index*cache.stride+slot]
					posed+=(skin.joint_poses[joint]*cache.vertices[index])*weight
				var point: Vector3 = instance.global_transform*posed
				finite_pose=finite_pose and point.is_finite()
				world.append(point)
			if not finite_pose:
				check(false,"Actual field joint palette has nonfinite posed vertices")
				return {"status":"INVALID_POSE"}
			for index in cache.supports:
				if Time.get_ticks_usec()>=deadline: v2_truncated_batches+=1;return {"status":"TRUNCATED_DEADLINE","geometryComplete":false}
				var support: Vector3 = world[int(index)]
				var height: float = provider.sample_world_height(support)
				var finite: bool = is_finite(height)
				var walkable: bool = finite and provider.placement_clear(provider.world_to_normalized(support),0.0)
				if not finite: v2_invalid_supports+=1
				elif not walkable: v2_nonwalkable_supports+=1
				elif not bool(record.dead) and not bool(record.sailing): v2_min_sole_gap=minf(v2_min_sole_gap,support.y-height)
				var joint_name: String = str(skin.joint_names[cache.joints[int(index)]])
				if not sole_samples.has(joint_name) or (finite and (not bool(sole_samples[joint_name].finite) or support.y-height<float(sole_samples[joint_name].gap))):
					sole_samples[joint_name]={"world":v2_point(support),"floorHeight":height if finite else null,"finite":finite,"walkable":walkable,"gap":support.y-height if finite else null,"selection":"minimum vertex/floor gap among all field vertices weighted to this foot/hoof joint"}
			for corner in range(0,cache.indices.size(),3):
				if corner%96==0 and Time.get_ticks_usec()>=deadline: v2_truncated_batches+=1;return {"status":"TRUNCATED_DEADLINE","geometryComplete":false}
				var a: Vector3 = world[cache.indices[corner]]
				var b: Vector3 = world[cache.indices[corner+1]]
				var c: Vector3 = world[cache.indices[corner+2]]
				v2_triangle_count+=1
				if (b-a).cross(c-a).length()*.5<=V2_AREA_EPS: v2_collapsed+=1;continue
				var triangle: Array = [a,b,c]
				var tri_bounds: AABB = AABB(a,Vector3.ZERO).expand(b).expand(c)
				var joint_name: String = str(skin.joint_names[cache.joints[cache.indices[corner]]])
				var category: String = v2_category(joint_name)
				for volume in volumes:
					var broad: AABB = volume.bounds
					if str(volume.role)=="beam" and tri_bounds.position.x<=broad.end.x+V2_PLANE_EPS and tri_bounds.end.x>=broad.position.x-V2_PLANE_EPS and tri_bounds.position.z<=broad.end.z+V2_PLANE_EPS and tri_bounds.end.z>=broad.position.z-V2_PLANE_EPS:
						if v2_area(v2_clip(triangle,volume.sidePlanes))>V2_AREA_EPS: gate_projection=true
					# AABB is a broad phase only. Final classification clips the
					# whole indexed posed triangle against actual convex faces.
					if not tri_bounds.grow(V2_PLANE_EPS).intersects(volume.bounds.grow(V2_PLANE_EPS)): continue
					var clipped: Array = v2_clip(triangle,volume.planes)
					if clipped.is_empty(): continue
					var witness: Vector3 = Vector3.ZERO
					for p in clipped: witness+=p
					witness/=float(clipped.size())
					var depths: Array = []
					var depth: float = INF
					for plane in volume.planes:
						var signed_depth: float = float(plane.distance)-plane.normal.dot(witness)
						depths.append(signed_depth);depth=minf(depth,signed_depth)
					var area: float = v2_area(clipped)
					if area<=V2_AREA_EPS or depth<=V2_PLANE_EPS: v2_touch_count+=1;continue
					v2_contact_count+=1;categories[category]+=1
					var contact: Dictionary = {"classification":"BASE_MESH_CONTACT","actor":record,"group":str(group_name),"category":category,"joint":joint_name,"surface":surface,"baseTriangle":int(corner/3),"volume":volume.role,"witness":v2_point(witness),"signedPlaneDepths":depths,"minimumDepth":depth,"clippedArea":area}
					if v2_contacts.size()<24: v2_contacts.append(contact)
					elif depth>float(v2_contacts.back().minimumDepth): v2_contacts[v2_contacts.size()-1]=contact
	check(finite_pose,"Actual field joint palette produces finite posed vertices")
	var support_record: Dictionary = {"actor":record,"samples":sole_samples}
	if v2_support_witnesses.size()<24: v2_support_witnesses.append(support_record)
	return {"geometryComplete":true,"gateBeamHorizontalProjection":gate_projection,"contactsByCategory":categories,"soleSamples":sole_samples}

func v2_receipt(event: Dictionary, game: Node) -> void:
	var type_name: String = str(event.get("type",""))
	v2_event_counts[type_name]=int(v2_event_counts.get(type_name,0))+1
	var receipt: Dictionary = {"event":event.duplicate(true),"observedElapsed":game.elapsed,"observedAnimationTime":game.animation_time}
	if v2_events.size()<64: v2_events.append(receipt)
	if type_name=="shot" and str(event.get("side",""))=="friendly": v2_shots[int(event.get("actorId",-1))]=receipt

func v2_observe(actor: Node3D, game: Node, probe: Dictionary) -> void:
	var state: Dictionary = actor.current_state
	var record: Dictionary = v2_actor_record(actor,game)
	var key: String = str(actor.get_instance_id())
	var previous: Dictionary = v2_previous.get(key,{})
	if not previous.is_empty() and float(previous.motionTime)==float(state.get("motionTime",0)): return
	var phases: Array = [str(state.get("motionPhase","unknown"))]
	var animation: String = str(state.get("animation","idle"))
	if animation=="idle" and not bool(state.get("deploying",false)): phases.append("standing")
	if animation=="walk": phases.append("walk")
	if not previous.is_empty() and str(previous.animation)=="walk" and animation!="walk" and actor.global_position.distance_to(previous.position)<.03 and (-actor.global_basis.z).normalized().distance_to(previous.forward)>.01: phases.append("stop_turn")
	var id: int = int(state.get("id",-1))
	if bool(state.get("attackReleased",false)):
		if actor.unit_type=="spear": phases.append("native_thrust")
		if actor.unit_type=="archer" and v2_shots.has(id): phases.append("native_bow_release")
	if animation=="idle" and not bool(state.get("deploying",false)) and actor.unit_type=="archer" and v2_shots.has(id) and float(state.get("motionTime",0))>float(v2_shots[id].observedAnimationTime):
		phases.append("post_attack_idle");record["nativeShotReceipt"]=v2_shots[id]
	for phase in phases:
		var coverage_key: String = ("friendly/" if bool(state.get("friendly",false)) else "enemy/")+actor.unit_type+"/"+str(phase)
		if not v2_coverage.has(coverage_key): v2_coverage[coverage_key]={"samples":0,"first":record,"gateProjectionSamples":0}
		v2_coverage[coverage_key].samples+=1
		if bool(probe.get("gateBeamHorizontalProjection",false)):
			v2_coverage[coverage_key].gateProjectionSamples+=1
			if not v2_coverage[coverage_key].has("firstAtGate"): v2_coverage[coverage_key]["firstAtGate"]={"actor":record,"probe":probe}
	v2_previous[key]={"animation":animation,"position":actor.global_position,"forward":(-actor.global_basis.z).normalized(),"motionTime":state.get("motionTime",0)}

func v2_clock_state(game: Node, start: int) -> Dictionary:
	return {"wallSeconds":float(Time.get_ticks_usec()-start)/1000000,"elapsed":game.elapsed,"animationTime":game.animation_time,"running":game.running,"paused":game.paused,"betweenWave":game.between_waves,"finished":game.finished,"wave":game.wave,"battleMinutes":game.battle_minutes,"units":game.units.size(),"enemies":game.enemies.size(),"queued":game.recruitment_queue.size()}

func v2_run() -> void:
	var args: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		if str(argument).contains("="): args[str(argument).get_slice("=",0)]=str(argument).get_slice("=",1)
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var profile_root: String = ProjectSettings.globalize_path("res://tests/profiles/troop-motion-gpu-v2-posed/").replace("\\","/").to_lower()
	var appdata: String = OS.get_environment("APPDATA").replace("\\","/").to_lower()
	var local_appdata: String = OS.get_environment("LOCALAPPDATA").replace("\\","/").to_lower()
	if DisplayServer.get_name()=="headless" or not appdata.begins_with(profile_root) or appdata!=local_appdata or not profile.begins_with(appdata+"/"):
		push_error("V2 posed probe requires its isolated GPU profile");quit(2);return
	var candidate_path: String = str(args.get("--candidate",V2_CANDIDATE))
	var expected_sha: String = str(args.get("--candidate-sha",V2_SHA))
	check(candidate_path==V2_CANDIDATE and expected_sha==V2_SHA and FileAccess.get_sha256(candidate_path)==V2_SHA,"Approved exact V2 preparation input SHA before native construction")
	var candidate_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate_path))
	check(candidate_value is Dictionary,"Approved V2 candidate is a JSON object")
	if not failures.is_empty(): quit(2);return
	var candidate: Dictionary = candidate_value
	check(int(candidate.get("version",0))==2 and str(candidate.get("candidateId",""))=="marune-stage01-fresh-tactical-v2","Approved V2 identity before native construction")
	if not failures.is_empty(): quit(2);return
	var seconds_text: String = str(args.get("--observe-seconds","60"))
	check(seconds_text.is_valid_float(),"Observation duration is numeric before native construction")
	var seconds: float = float(seconds_text) if seconds_text.is_valid_float() else 0
	check(is_finite(seconds) and seconds>0 and seconds<=60,"Observation duration is finite and within 0<seconds<=60 before native construction")
	var stage_profile: String = str(args.get("--stage-profile","canonical"))
	check(stage_profile in ["canonical","alias"],"V2 pose-only profile is canonical or explicit alias comparison")
	check(not FileAccess.file_exists("user://progress.json") and not FileAccess.file_exists("user://progress.json.bak"),"Disposable profile starts with no progress save or backup")
	if not failures.is_empty(): quit(2);return
	var before: Dictionary = v2_hashes()
	root.size=Vector2i(1440,900)
	root.content_scale_size=root.size;root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var progress_script: Script = load("res://native/progress.gd")
	var progress: RefCounted = progress_script.new()
	var starter: Dictionary = {"unlocked":progress.unlocked_units(),"levels":progress.data.army.levels.duplicate(true),"mapsCleared":progress.data.maps.size(),"battleMinutesSetting":progress.data.settings.battleMinutes,"saveRead":false,"saveWritten":false}
	var shell: Node = Node.new()
	root.add_child(shell)
	var game: Node2D = Battle.new()
	shell.add_child(game)
	game.configure_roster(progress.unit_catalog,progress.unlocked_units(),progress.data.army.levels)
	var stage: Dictionary = v2_fixture(candidate,stage_profile)
	game.load_map(stage,int(progress.data.settings.battleMinutes))
	starter["catalogPaidCosts"]={"archer":game.recruit_cost("archer"),"spear":game.recruit_cost("spear")}
	starter["goldAtLoad"]=game.gold
	game.three_d_enabled=true;game.hide()
	var troops: Control = Troops.new()
	shell.add_child(troops)
	troops.set_field_size(Vector2(root.size))
	troops.set_stage(stage)
	var provider: Node3D = WorldSurface.new()
	troops.set_terrain_provider(provider)
	troops.bind_battle(game)
	game.set_field_rect(Rect2(Vector2.ZERO,Vector2(root.size)))
	game.three_d_actor_scale=troops.actor_base_scale()
	var visual_script: Script = load("res://native/remaster_visual_slice.gd")
	var visuals: Node3D = visual_script.new()
	troops.world.add_child(visuals)
	visuals.configure(stage,provider);visuals.apply_lighting(troops)
	check(troops.uses_world_geometry() and bool(provider.diagnostics().get("ready",false)) and str(game.config.id)==str(troops.stage.id),"Actual pose-only Game/Troops share canonical/alias identity and authored provider")
	check(game.is_processing() and troops.is_processing(),"Actual Game and Troops retain native realtime processing")
	var volumes: Array = v2_gate(visuals,provider,candidate)
	game.game_event.connect(func(event: Dictionary): v2_receipt(event,game))
	game.set_input_enabled(true);game.set_speed(1)
	var started: int = Time.get_ticks_usec()
	game.start_battle()
	var start_elapsed: float = game.elapsed
	var orders: Array = []
	var archer_orders: int = 0
	for zone in game.zones:
		if str(zone.get("placementRole",""))!="ranged" or archer_orders>=2: continue
		var point: Vector2 = game._zone_placement_hint(zone,"archer")
		var wallet: int = game.gold
		var order: Dictionary = game.submit_deployment("archer",point)
		orders.append({"type":"archer","result":order,"goldBefore":wallet,"goldAfter":game.gold,"position":[point.x,point.y]})
		check(point.x>=0 and bool(order.get("ok",false)),"Actual paid side-post archer order accepted")
		archer_orders+=1
	var base: Dictionary = game.ground_combat.select_march_base(0)
	check(archer_orders==2 and not base.is_empty(),"Current roster supplies two side posts and native marching base")
	if not base.is_empty():
		for index in range(2):
			var wallet: int = game.gold
			var order: Dictionary = game.submit_deployment("spear",base.position,str(base.pathId))
			orders.append({"type":"spear","result":order,"goldBefore":wallet,"goldAfter":game.gold,"position":[base.position.x,base.position.y]})
			check(bool(order.get("ok",false)),"Actual paid spear order accepted")
	var previous_elapsed: float = -1
	var next_probe: int = 0
	var next_clock: int = 0
	var deadline: int = started+int(seconds*1000000)
	while Time.get_ticks_usec()<deadline and failures.is_empty():
		await process_frame
		var now: int = Time.get_ticks_usec()
		if now>=deadline: break
		if now>=next_clock:
			v2_clock.append(v2_clock_state(game,started));next_clock=now+500000
		# Same paused/finished clock never creates additional pose coverage.
		if game.elapsed==previous_elapsed: continue
		previous_elapsed=game.elapsed
		var frozen: String = v2_signature(game)
		var native_states: Array = game.actor_states()
		check(frozen==v2_signature(game),"Read-only native actor-state query preserves signed combat/queue/skill fields")
		var measure: bool = now>=next_probe
		for actor in troops.actors.values():
			if Time.get_ticks_usec()>=deadline: break
			if not actor.is_visible_in_tree(): continue
			var probe: Dictionary = {}
			if measure:
				probe=v2_probe_actor(actor,provider,volumes,v2_actor_record(actor,game),deadline)
				if not bool(probe.get("geometryComplete",false)): continue
			v2_observe(actor,game,probe)
		if measure: v2_samples+=1;next_probe=now+100000
		check(frozen==v2_signature(game),"Actual palette/mesh/provider observation preserves signed combat/queue/skill fields")
		# Kept only as evidence that the query was performed against actual Game;
		# source states are never supplied to Troops by this branch.
		if native_states.is_empty() and game.units.size()>0: check(false,"Native units remain observable")
	var observed_wall: float = float(Time.get_ticks_usec()-started)/1000000
	var end_elapsed: float = game.elapsed
	var finalizing_started: int = Time.get_ticks_usec()
	var previous_process: bool = game.is_processing()
	if game.running and not game.paused and not game.finished and not game.between_waves: game.pause_battle()
	# Capture-only freeze after natural observation. Finished/between-wave Game
	# can still age death actors, even when pause_battle deliberately rejects.
	game.set_process(false)
	await v2_settle()
	var capture_signature: String = v2_signature(game)
	var capture_pose: String = v2_pose_signature(troops)
	var pause_context: Dictionary = v2_clock_state(game,started)
	pause_context["captureFreeze"]={"method":"Game.set_process(false) after natural observation","previouslyProcessing":previous_process,"processingDuringCapture":game.is_processing()}
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		root.size=dimensions;root.content_scale_size=dimensions;troops.set_field_size(Vector2(dimensions))
		game.set_field_rect(Rect2(Vector2.ZERO,Vector2(dimensions)))
		await v2_settle()
		check(capture_signature==v2_signature(game),"Both actual native-size frames preserve the same paused Game moment")
		check(capture_pose==v2_pose_signature(troops),"Both actual native-size frames preserve the same final joint palette and actor world transforms")
		var picture: Image = root.get_texture().get_image()
		var path: String = ProjectSettings.globalize_path("user://v2-posed-end-%dx%d.png"%[dimensions.x,dimensions.y])
		check(picture!=null and picture.get_size()==dimensions,"Actual V2 native-size framebuffer")
		if picture!=null: check(picture.save_png(path)==OK,"Actual V2 paused capture saves")
		var actors: Array = []
		for actor in troops.actors.values(): actors.append(v2_actor_record(actor,game))
		captures.append({"path":path,"size":[dimensions.x,dimensions.y],"nativeMoment":pause_context,"poseSignatureSHA256":capture_pose.sha256_text(),"actors":actors})
	var missing: Array = []
	for required in ["friendly/archer/standing","friendly/archer/native_bow_release","friendly/archer/recovery","friendly/archer/post_attack_idle","friendly/spear/standing","friendly/spear/walk","friendly/spear/stop_turn","friendly/spear/native_thrust","friendly/spear/recovery"]:
		if not v2_coverage.has(required): missing.append({"phase":required,"status":"UNOBSERVED"})
	var gate_missing: Array = []
	for phase in ["walk","stop_turn","native_thrust","recovery"]:
		var key: String = "friendly/spear/"+str(phase)
		if int(v2_coverage.get(key,{}).get("gateProjectionSamples",0))==0: gate_missing.append({"phase":key,"status":"UNOBSERVED_AT_GATE"})
	var after: Dictionary = v2_hashes()
	check(before==after,"All consumed V2 source/assets and runner hashes stay unchanged")
	check(not FileAccess.file_exists("user://progress.json") and not FileAccess.file_exists("user://progress.json.bak"),"Pose-only native probe writes no progress save or backup")
	var render_profile: Dictionary = troops.visual_profiles.get(str(game.config.id),{})
	var perspective: Dictionary = render_profile.get("perspective",{})
	var runtime_identity: Dictionary = {"stageProfile":stage_profile,"stageID":str(game.config.id),"troopsStageID":str(troops.stage.id),"storedStageNumber":game.config.get("stageNumber",null),"stageNumberFallback":int(game.config.get("stageNumber",1)),"candidateOnly":bool(game.config.get("candidateOnly",false)),"actualTroopsProfile":render_profile,"effectiveTroopsPerspective":{"farScale":float(perspective.get("farScale",.90)),"nearScale":float(perspective.get("nearScale",1.10))},"gameVisualProfile":game.visual_profile(),"battleMinutes":game.battle_minutes,"poseOnly":true,"completeCampaignStage01":false,"MainConstructed":false,"starter":starter}
	var measured_status: String = "FAIL_PROBE" if not failures.is_empty() else "NO_MEASURED_SAMPLES" if v2_samples==0 or v2_triangle_count==0 else "FAIL_MEASURED_BASE_CONTACT" if v2_contact_count>0 else "NO_BASE_CONTACT_IN_OBSERVED_SAMPLES"
	var volume_records: Array = []
	for volume in volumes:
		var planes: Array = []
		for plane in volume.planes: planes.append({"normal":v2_point(plane.normal),"distance":plane.distance})
		volume_records.append({"role":volume.role,"actualNode":volume.nodePath,"centroid":v2_point(volume.centroid),"worldBasis":volume.worldBasis,"worldPosition":volume.worldPosition,"planes":planes})
	var report: Dictionary = {
		"directive":"MOT-V2-POSED-PROBE-AUTHOR",
		"status":"FAIL_PROBE" if not failures.is_empty() else "INCOMPLETE_FULL_PASSAGE",
		"measuredBaseScopeStatus":measured_status,"checks":checks,"failures":failures,
		"candidateSHA":V2_SHA,"runtimeIdentity":runtime_identity,"gpu":RenderingServer.get_video_adapter_name(),
		"orders":orders,"requestedObservationWallSeconds":seconds,"wallSeconds":observed_wall,"finalizationWallSeconds":float(Time.get_ticks_usec()-finalizing_started)/1000000,
		"nativeElapsedInterval":[start_elapsed,end_elapsed],"clockSamples":v2_clock,"pauseContext":pause_context,
		"coverage":v2_coverage,"missingPhases":missing,"missingGatePhases":gate_missing,
		"eventCounts":v2_event_counts,"firstNativeEvents":v2_events,"geometrySamples":v2_samples,"truncatedGeometryBatches":v2_truncated_batches,
		"baseIndexedTrianglesMeasured":v2_triangle_count,"collapsedDegenerateTriangles":v2_collapsed,
		"measurementEpsilon":{"plane":V2_PLANE_EPS,"area":V2_AREA_EPS},"contactsFound":v2_contact_count>0,
		"baseContacts":v2_contact_count,"touches":v2_touch_count,"contactWitnesses":v2_contacts,"actualGateVolumes":volume_records,
		"dryWalkableMinimumSoleGap":v2_min_sole_gap if is_finite(v2_min_sole_gap) else null,
		"invalidFloorSupportSamples":v2_invalid_supports,"finiteNonwalkableSupportSamples":v2_nonwalkable_supports,
		"firstSupportWitnesses":v2_support_witnesses,"captures":captures,"sourceHashesBefore":before,"sourceHashesAfter":after,
		"limitations":[
			"Only the current visible field groups' authored base indexed surfaces are measured; selected raster LOD indices are not proven. BASE_MESH_CONTACT is a measured geometric witness, not a proven rendered-LOD production defect.",
			"Natural poses only. The two fixed side-post archers are not route-walking or gate-passage evidence. Missing natural phases are UNOBSERVED, not mechanic failures.",
			"Discrete geometry samples at approximately 0.1 wall seconds; no swept-volume or continuous inter-frame clearance claim.",
			"Head includes worn head gear; body includes worn armour; weapon/bow strings/nocked arrow are equipment. Source bone visibility is diagnostic only; actual merged-group visibility and final palette scales govern measurement.",
			"All actual foot/hoof-joint field vertices are sampled and minimum vertex/floor gaps retained per foot. This is a vertex-contact measurement, not complete foot-triangle/floor clearance. The dry minimum excludes dead/sailing actors; lifted gait feet need not contact floor. Finite nonwalkable ditch floor is reported separately.",
			"Direct native Game/Troops pose-only candidate trace. Canonical profile is primary; alias is optional comparison. Main/HUD/story/learning flow is not constructed or verified. Isolated fresh Progress starter roster and current paid orders only; no campaign registration, player save, manual time advances, injected actors, forced learning close, or automatic resume."
		]
	}
	var output: FileAccess = FileAccess.open("user://qa_troop_v2_posed.json",FileAccess.WRITE)
	check(output!=null,"V2 measured report can be opened in isolated user profile")
	if output==null: shell.queue_free();quit(2);return
	report["checks"]=checks
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("TROOP_V2_POSED_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"status":report.status,"measuredBaseScopeStatus":measured_status,"contacts":v2_contact_count,"report":ProjectSettings.globalize_path("user://qa_troop_v2_posed.json")}))
	shell.queue_free();await process_frame
	quit(0 if failures.is_empty() and v2_contact_count==0 else 1)
