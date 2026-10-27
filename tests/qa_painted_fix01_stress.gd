extends SceneTree
## Explicit independent render/combat fixture. HQ alone runs this script.
## No Main, account, learning UI, player save, repeated benchmark or balance claim.
const Battle = preload("res://native/game.gd")
const Stage = preload("res://native/painted_stage.gd")
const HUD = preload("res://native/battlefield_hud.gd")
const OUTPUT: String = "res://tests/profiles/painted-game-fix-01"
const VIEW_SIZE: Vector2i = Vector2i(1440,900)
const TARGET_SECONDS: float = 12.0
const MAX_SECONDS: float = 60.0
const FRIENDS: int = 72
const INITIAL_ENEMIES: int = 30
const QUEUED_ENEMIES: int = 6
const INJECTED_HP: float = 10000.0
const INITIAL_GOLD: int = 10000
const SEED: int = 98760
var game: Node2D
var started: int = 0
var stopped: bool = false
var measuring: bool = false
var phase: String = "setup"
var output_dir: String = ""
var checks: Array = []
var failures: Array = []
var source_hashes: Dictionary = {}
var fixture: Dictionary = {}
var frame_rows: Array = []
var buckets: Array = []
var event_counts: Dictionary = {"friendlyShots":0,"enemyShots":0,"friendlyHits":0,"enemyHits":0,"friendlyDamage":0.0,"enemyDamage":0.0,"kills":0,"friendlyFallen":0}
var damage_actors: Dictionary = {}
var damage_victims: Dictionary = {}
var first_events: Array = []
var last_events: Array = []
var seen_enemies: Dictionary = {}
var spawn_observations: Array = []
var excluded_intervals: Array = []
var measure_started: int = 0
var measure_end: int = 0
var measure_clock_start: float = 0.0
var measure_clock_end: float = 0.0
var capture_row: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func bounded() -> bool:
	return not stopped and Time.get_ticks_usec()-started<int(MAX_SECONDS*1000000.0)

func alive() -> bool:
	return bounded() and is_instance_valid(game)

func live() -> bool:
	return alive() and game.running and not game.paused and not game.finished and not game.between_waves and not game.battle_closed and root.size==VIEW_SIZE

func check(ok: bool, note: String) -> bool:
	checks.append({"pass":ok,"note":note})
	if not ok: failures.append(note);push_error("FIX01_STRESS "+note)
	return ok

func canonical(value: String) -> String:
	return value.replace("\\","/").simplify_path().trim_suffix("/").to_lower()

func hash_folder(folder: String, hashes: Dictionary) -> void:
	for filename in DirAccess.get_files_at(folder):
		if filename.get_extension() in ["gd","json","png","ttf","otf"]:
			var path: String=folder.path_join(filename)
			hashes[path]=FileAccess.get_sha256(path)
	for directory in DirAccess.get_directories_at(folder):
		if not directory.begins_with("."): hash_folder(folder.path_join(directory),hashes)

func hash_sources() -> Dictionary:
	var hashes: Dictionary={}
	for folder in ["res://native","res://assets/characters/painted-v1","res://assets/painted-battlefield","res://assets/fonts"]:
		hash_folder(folder,hashes)
	for path in ["res://project.godot","res://tests/qa_painted_fix01_stress.gd"]:
		hashes[path]=FileAccess.get_sha256(path)
	return hashes

func actor_state(actor: Dictionary, friendly: bool) -> Dictionary:
	return {"id":int(actor.id),"friendly":friendly,"type":str(actor.get("type",actor.get("kind",""))),"position":str(actor.position),"routeDistance":actor.get("routeDistance",actor.get("routeProgress",null)),"hp":actor.hp,"maxHp":actor.maxHp,"animation":str(actor.animation),"combatState":actor.get("combatState",null),"campaignLevel":actor.get("campaignLevel",null),"formationLane":actor.get("formationLane",null)}

func setup_fixture() -> bool:
	var catalog_data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	var maps: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if not check(catalog_data is Dictionary and maps is Array and not maps.is_empty(),"Real unit catalog and shipped first stage are available"): return false
	var map: Dictionary=Stage.apply(maps[0])
	map["initialGold"]=INITIAL_GOLD
	map["trainingOnly"]=true
	for objective in map.get("objectives",[]): objective["hp"]=100000
	game=Battle.new()
	game.name="IndependentPaintedStressBattle"
	game.three_d_enabled=false
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.input_enabled=false
	game.configure_roster(catalog_data.units,["spear"],{"spear":1})
	game.load_map(map,0)
	game.set_seed(SEED)
	# Only this process's independent layout selection; no actual HUD is built.
	HUD.painted_mode=true
	var geometry: Dictionary=HUD.layout(Vector2(VIEW_SIZE))
	game.set_field_rect(geometry.field)
	game.painted_field.attach_to(game)
	game.start_battle()
	fixture={"kind":"injected_independent_stress_fixture","naturalProgression":false,"earnedUnlocks":false,"MainOrAccountInstantiated":false,"playerSaveAccess":false,"sourceMapId":str(maps[0].id),"runtimeMapId":str(game.config.id),"seed":SEED,"viewport":[VIEW_SIZE.x,VIEW_SIZE.y],"fieldRect":str(game.field_rect),"fieldLayout":"Actual BattlefieldHUD.layout with painted_mode=true; HUD panels/tooltip/learning/feedback/audio absent","trainingOnly":true,"durationMinutes":0,"speed":float(game.speed),"initialGold":INITIAL_GOLD,"objectiveHPInjected":100000,"friendlyLevel":1,"initialFriendlyTarget":FRIENDS,"initialEnemyTarget":INITIAL_ENEMIES,"queuedEnemyTarget":QUEUED_ENEMIES,"hpInjectedIntoInitialActors":INJECTED_HP,"setupOnlyRecruitmentAdvanceSeconds":1.31,"setupOnlyActorPositionInjection":true,"measurementMutations":"None: Game._process drives normal simulation; no scripted healing, respawn, reposition, time advance or input during the window","queuePolicy":"Six explicit fixture raiders through the real spawn queue, sourceWave1/path0/mainIngressOnly; clock2.0 and current real spawn interval; new queued enemies retain normal HP/stats","limits":"High HP suppresses attrition. Homogeneous L1 spears/raiders, trainingOnly, no campaign/UI/audio/feedback cost. Does not validate disposable-unit economy or all unit types."}
	for unused in range(FRIENDS):
		if not check(game.begin_placement("spear",0),"Fixture paid spear order accepted: "+str(unused)): return false
	fixture["paidOrderCost"]=INITIAL_GOLD-int(game.gold)
	fixture["goldAfterOrders"]=int(game.gold)
	fixture["queuedPaidOrders"]=game.recruitment_queue.size()
	game._advance_recruitment(1.31)
	if not check(game.units.size()==FRIENDS and game.recruitment_queue.is_empty(),"Exactly seventy-two actual paid L1 spear actors are produced"): return false
	var route: Dictionary=game.paths[0]
	var forward: Vector2=(route.points[-1]-route.points[0]).normalized()
	var normal: Vector2=Vector2(-forward.y,forward.x)
	var center: float=float(game.ground_combat.cumulative[0][-1])*.56
	var rows: Array=[]
	for index in range(game.units.size()):
		var unit: Dictionary=game.units[index]
		var lane: float=float(index%9)-4.0
		var distance: float=center+float(index/9)*.017
		unit.position=game.ground_combat.route_point(0,distance)+normal*lane*.016
		unit.routeDistance=distance
		unit.formationLane=lane*.016/.009
		unit.spawnPosition=unit.position
		unit.hp=INJECTED_HP;unit.maxHp=INJECTED_HP
		unit.gatherRemaining=0.0;unit.combatState="march";unit.animation="walk"
		if not check(game.ground_combat.land_segment_safe(unit.position,unit.position,.008),"Injected friendly footprint is legal land: "+str(unit.id)): return false
		rows.append(actor_state(unit,true))
	for index in range(INITIAL_ENEMIES):
		var enemy: Dictionary=game._spawn_enemy("raider",1,{"originKind":"raider","pathIndex":0,"formationPattern":"skirmish","mainIngressOnly":true})
		if not check(not enemy.is_empty(),"Real fixture enemy spawn accepted: "+str(index)): return false
		var lane: float=float(index%6)-2.5
		var distance: float=center-.018-float(index/6)*.017
		enemy.position=game.ground_combat.route_point(0,distance)+normal*lane*.016
		enemy.pointIndex=1;enemy.routeProgress=distance
		enemy.formationLane=lane
		enemy.ingressActive=false;enemy.transportActive=false
		enemy.hp=INJECTED_HP;enemy.maxHp=INJECTED_HP
		if not check(game.ground_combat.land_segment_safe(enemy.position,enemy.position,.008),"Injected enemy footprint is legal land: "+str(enemy.id)): return false
		seen_enemies[int(enemy.id)]=true
		rows.append(actor_state(enemy,false))
	for unused in range(QUEUED_ENEMIES):
		game.spawn_queue.append("raider")
		game.spawn_source_waves.append(1)
		game.spawn_metadata.append({"originKind":"raider","pathIndex":0,"mainIngressOnly":true})
	game.spawn_clock=2.0
	fixture["spawnIntervalAtSetup"]=game._spawn_interval()
	fixture["initialActors"]=rows
	fixture["formation"]={"routeCenterFraction":.56,"friendlyColumns":9,"enemyColumns":6,"lateralSpacing":.016,"rowSpacing":.017,"initialFrontGap":.018}
	fixture["setupSimulationClock"]=float(game.elapsed)
	check(bool(game.config.get("paintedPresentation",false)) and game.painted_field.is_ready() and game.painted_actors.is_ready(),"Actual current painted stage and actor renderer are mounted")
	check(not game.three_d_enabled and root.find_children("*","Node3D",true,false).is_empty(),"Independent fixture creates no 3D world")
	game.game_event.connect(on_event)
	return failures.is_empty()

func on_event(row: Dictionary) -> void:
	if not measuring: return
	var kind: String=str(row.get("type",""))
	if kind not in ["shot","hit","killed","unit_fallen"]: return
	var bucket_index: int=clampi(int(float(Time.get_ticks_usec()-measure_started)/1000000.0),0,buckets.size()-1)
	var bucket: Dictionary=buckets[bucket_index]
	var side: String="enemy" if str(row.get("side",""))=="enemy" else "friendly"
	if kind=="shot":
		event_counts[side+"Shots"]=int(event_counts[side+"Shots"])+1
		bucket[side+"Shots"]=int(bucket[side+"Shots"])+1
	elif kind=="hit" and float(row.get("damage",0))>0 and float(row.get("hpBefore",0))>float(row.get("hpAfter",0)):
		event_counts[side+"Hits"]=int(event_counts[side+"Hits"])+1
		event_counts[side+"Damage"]=float(event_counts[side+"Damage"])+float(row.damage)
		bucket[side+"Hits"]=int(bucket[side+"Hits"])+1
		damage_actors[side+":"+str(row.get("actorId",-1))]=true
		damage_victims[str(row.get("victimSide",""))+":"+str(row.get("victimId",-1))]=true
	elif kind=="killed": event_counts.kills=int(event_counts.kills)+1
	elif kind=="unit_fallen": event_counts.friendlyFallen=int(event_counts.friendlyFallen)+1
	var copied: Dictionary=row.duplicate(true)
	copied["qaWindowWallSeconds"]=float(Time.get_ticks_usec()-measure_started)/1000000.0
	if first_events.size()<32: first_events.append(copied)
	last_events.append(copied)
	if last_events.size()>32: last_events.pop_front()

func counts() -> Dictionary:
	var result: Dictionary={"friendlyAlive":0,"enemyAlive":0,"friendlySlots":game.units.size(),"enemySlots":game.enemies.size(),"movingFriends":0,"movingEnemies":0,"contactPairs":0,"contactEnemies":0,"drawnActors":int(game.painted_actors.last_draw_count),"renderActorItems":int(game.painted_actors.last_actor_count),"skippedActors":int(game.painted_actors.last_skipped_count),"queuedSpawns":game.spawn_queue.size()}
	for unit in game.units:
		if float(unit.hp)>0:
			result.friendlyAlive=int(result.friendlyAlive)+1
			if str(unit.animation)=="walk": result.movingFriends=int(result.movingFriends)+1
	for enemy in game.enemies:
		if float(enemy.hp)>0:
			result.enemyAlive=int(result.enemyAlive)+1
			if str(enemy.animation)=="walk": result.movingEnemies=int(result.movingEnemies)+1
			var contacts: Array=enemy.get("contactUnitIds",[])
			result.contactPairs=int(result.contactPairs)+contacts.size()
			if not contacts.is_empty(): result.contactEnemies=int(result.contactEnemies)+1
		if not seen_enemies.has(int(enemy.id)):
			seen_enemies[int(enemy.id)]=true
			spawn_observations.append({"id":int(enemy.id),"kind":str(enemy.kind),"firstObservedClock":float(game.elapsed),"firstObservedWindowWallSeconds":float(Time.get_ticks_usec()-measure_started)/1000000.0 if measuring else null,"duringMeasurement":measuring,"position":str(enemy.position),"hp":enemy.hp,"maxHp":enemy.maxHp,"insideNormalizedMap":Rect2(Vector2.ZERO,Vector2.ONE).has_point(enemy.position)})
	return result

func percentile(values: Array, fraction: float) -> Variant:
	if values.is_empty(): return null
	var sorted: Array=values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size())*fraction)-1,0,sorted.size()-1)]

func performance_summary() -> Dictionary:
	var times: Array=[]
	var draw_calls: Array=[]
	var viewport_calls: Array=[]
	var gpu: Array=[]
	var cpu: Array=[]
	var friends: Array=[]
	var enemies: Array=[]
	var rendered: Array=[]
	var seconds: float=0.0
	for row in frame_rows:
		times.append(row.frameMs);draw_calls.append(row.totalDrawCalls);viewport_calls.append(row.viewportDrawCalls)
		friends.append(row.friendlyAlive);enemies.append(row.enemyAlive);rendered.append(row.drawnActors)
		seconds+=float(row.frameMs)/1000.0
		if row.gpuMs!=null: gpu.append(row.gpuMs)
		if row.renderCpuMs!=null: cpu.append(row.renderCpuMs)
	var stalls: Array=frame_rows.duplicate()
	stalls.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.frameMs)>float(b.frameMs))
	return {"targetWallSeconds":TARGET_SECONDS,"eligibleWallSeconds":seconds,"windowBoundaryWallSeconds":float(measure_end-measure_started)/1000000.0 if measure_started>0 and measure_end>0 else 0.0,"simulationClockStart":measure_clock_start,"simulationClockEnd":measure_clock_end,"simulationClockDelta":measure_clock_end-measure_clock_start,"intervals":times.size(),"realAverageFps":float(times.size())/seconds if seconds>0 else null,"fpsDefinition":"Completed eligible rendered intervals / their actual monotonic wall seconds; no average of instantaneous reciprocals","frameP50Ms":percentile(times,.5),"frameP95Ms":percentile(times,.95),"frameMaxMs":times.max() if not times.is_empty() else null,"over50ms":times.filter(func(value): return float(value)>50.0).size(),"largestStalls":stalls.slice(0,mini(10,stalls.size())),"totalDrawCallsP50":percentile(draw_calls,.5),"totalDrawCallsP95":percentile(draw_calls,.95),"viewportDrawCallsP50":percentile(viewport_calls,.5),"viewportDrawCallsP95":percentile(viewport_calls,.95),"friendlyAliveMin":friends.min() if not friends.is_empty() else null,"friendlyAliveMax":friends.max() if not friends.is_empty() else null,"enemyAliveMin":enemies.min() if not enemies.is_empty() else null,"enemyAliveMax":enemies.max() if not enemies.is_empty() else null,"mainPassDrawnActorsMin":rendered.min() if not rendered.is_empty() else null,"mainPassDrawnActorsMax":rendered.max() if not rendered.is_empty() else null,"gpuStatus":"positive_root_viewport_API_samples" if not gpu.is_empty() else "unavailable_no_positive_API_samples","gpuPositiveSamples":gpu.size(),"gpuP50Ms":percentile(gpu,.5),"gpuP95Ms":percentile(gpu,.95),"renderCpuP50Ms":percentile(cpu,.5),"renderCpuP95Ms":percentile(cpu,.95),"excludedIntervals":excluded_intervals,"limits":"One continuous nominal12s window ending at a complete frame boundary. Existing VSync/maxFPS retained. Game caps input delta at.25s; wall stalls can exceed simulation advance. Render CPU/GPU API values are not whole-engine CPU or frame latency and may have backend latency. Small in-memory QA counters/scans remain in the measured process. No capture/readback/save/hash/resize/setup/pause or resumed fragmented window included. No historical improvement, full-game60FPS or unlimited-army acceptance."}

func finish(reason: String) -> void:
	if stopped: return
	measuring=false
	if measure_started>0 and measure_end==0: measure_end=Time.get_ticks_usec()
	if is_instance_valid(game): game.set_process(false);measure_clock_end=float(game.elapsed)
	stopped=true
	var end_hashes: Dictionary=hash_sources()
	check(source_hashes==end_hashes,"Exact source/asset hashes remain unchanged during the independent run")
	var report: Dictionary={"kind":"painted-fix01-independent-render-stress","status":"evidence_collected" if reason=="complete" and failures.is_empty() else "partial_or_failed","reason":reason,"phase":phase,"wallSeconds":float(Time.get_ticks_usec()-started)/1000000.0,"checks":checks,"failures":failures,"fixture":fixture,"performance":performance_summary(),"frameRows":frame_rows,"perSecondActivity":buckets,"eventCounts":event_counts,"damageActors":damage_actors.keys(),"damageVictims":damage_victims.keys(),"firstCombatEvents":first_events,"lastCombatEvents":last_events,"spawnObservations":spawn_observations,"capture":capture_row,"sources":source_hashes,"sourcesAtEnd":end_hashes,"engine":Engine.get_version_info(),"displayServer":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"vsyncMode":DisplayServer.window_get_vsync_mode(),"engineMaxFps":Engine.max_fps,"engineLaunchesThisScript":1,"visualAcceptance":"pending_HQ_original_PNG_review","performanceBudgetAcceptance":"not_evaluated","reference":"https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu"}
	if is_instance_valid(game):
		report["finalActors"]=game.units.map(func(actor: Dictionary): return actor_state(actor,true))+game.enemies.map(func(actor: Dictionary): return actor_state(actor,false))
		report["rendererDiagnostics"]=game.painted_actors.diagnostics()
		report["fieldDiagnostics"]=game.painted_field.diagnostics()
	var file: FileAccess=FileAccess.open(output_dir.path_join("stress-report.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  "));file.close()
	else: push_error("Cannot save independent stress report");quit(2);return
	print("FIX01_STRESS ",JSON.stringify({"report":ProjectSettings.globalize_path(output_dir.path_join("stress-report.json")),"status":report.status,"reason":reason,"failures":failures,"performance":report.performance}))
	if is_instance_valid(game): game.queue_free()
	quit(0 if report.status=="evidence_collected" else 1)

func run() -> void:
	started=Time.get_ticks_usec()
	output_dir=OUTPUT.path_join("stress-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	source_hashes=hash_sources()
	create_timer(MAX_SECONDS).timeout.connect(func(): finish("deadline") if not stopped else null)
	if not check(DisplayServer.get_name()!="headless" and canonical(ProjectSettings.globalize_path("user://")).begins_with(canonical(ProjectSettings.globalize_path(OUTPUT))+"/"),"Stress uses an isolated rendered FIX01 profile"):
		finish("profile_rejected");return
	root.size=VIEW_SIZE;root.content_scale_size=VIEW_SIZE
	if not setup_fixture(): finish("setup_failed");return
	if not alive(): finish("deadline");return
	var rid: RID=root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	phase="warmup_excluded"
	game.set_process(true)
	var warm_started: int=Time.get_ticks_usec()
	while live() and Time.get_ticks_usec()-warm_started<1000000:
		await RenderingServer.frame_post_draw
	if not live(): finish("warmup_not_live");return
	fixture["warmupWallSeconds"]=float(Time.get_ticks_usec()-warm_started)/1000000.0
	fixture["warmupSimulationClock"]=float(game.elapsed)
	fixture["countsBeforeMeasurement"]=counts()
	for index in range(int(TARGET_SECONDS)):
		buckets.append({"wallSecond":index,"friendlyShots":0,"enemyShots":0,"friendlyHits":0,"enemyHits":0,"frames":0,"contactFrames":0,"maxContactPairs":0,"movingFrames":0})
	phase="continuous_measurement"
	measure_started=Time.get_ticks_usec()
	measure_clock_start=float(game.elapsed)
	var previous_time: int=measure_started
	var previous_clock: float=measure_clock_start
	var previous_drawn: int=Engine.get_frames_drawn()
	measuring=true
	while bounded() and Time.get_ticks_usec()-measure_started<int(TARGET_SECONDS*1000000.0):
		await RenderingServer.frame_post_draw
		if stopped: return
		var now: int=Time.get_ticks_usec()
		if not live() or float(game.elapsed)<=previous_clock or Engine.get_frames_drawn()<=previous_drawn:
			excluded_intervals.append({"wallOffset":float(now-measure_started)/1000000.0,"reason":"non_live_or_nonadvancing_or_duplicate_render_frame","intervalMs":float(now-previous_time)/1000.0})
			finish("measurement_interrupted");return
		var row: Dictionary=counts()
		row.merge({"frame":Engine.get_frames_drawn(),"frameMs":float(now-previous_time)/1000.0,"windowWallSeconds":float(now-measure_started)/1000000.0,"clock":float(game.elapsed),"clockDelta":float(game.elapsed)-previous_clock,"totalDrawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"viewportDrawCalls":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)},true)
		var gpu: float=RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var cpu: float=RenderingServer.viewport_get_measured_render_time_cpu(rid)
		row["gpuMs"]=gpu if gpu>0 else null
		row["renderCpuMs"]=cpu if cpu>0 else null
		frame_rows.append(row)
		var index: int=clampi(int(float(now-measure_started)/1000000.0),0,buckets.size()-1)
		buckets[index].frames=int(buckets[index].frames)+1
		if int(row.contactPairs)>0: buckets[index].contactFrames=int(buckets[index].contactFrames)+1
		buckets[index].maxContactPairs=maxi(int(buckets[index].maxContactPairs),int(row.contactPairs))
		if int(row.movingFriends)+int(row.movingEnemies)>0: buckets[index].movingFrames=int(buckets[index].movingFrames)+1
		previous_time=now;previous_clock=float(game.elapsed);previous_drawn=Engine.get_frames_drawn()
	measuring=false
	measure_end=previous_time;measure_clock_end=previous_clock
	if not alive(): finish("deadline");return
	game.set_process(false)
	phase="post_measurement_capture_excluded"
	var stats: Dictionary=performance_summary()
	check(float(stats.eligibleWallSeconds)>=TARGET_SECONDS,"One continuous12second live advancing-clock rendered window is collected")
	check(int(stats.get("friendlyAliveMin",0))>=60 and int(stats.get("enemyAliveMin",0))>=24 and int(stats.get("mainPassDrawnActorsMin",0))>=84,"Large actual live armies and at least84 main-pass actors persist throughout measurement")
	check(int(event_counts.friendlyHits)>0 and int(event_counts.enemyHits)>0,"Both sides inflict real individual HP loss during measurement")
	var active_buckets: Array=buckets.filter(func(row: Dictionary): return int(row.contactFrames)>0 and int(row.friendlyHits)+int(row.enemyHits)>0)
	check(active_buckets.size()>=8 and int(buckets[-1].friendlyHits)+int(buckets[-1].enemyHits)>0,"Actual contacts and HP-loss hits persist across the window, including its last second")
	check(spawn_observations.any(func(row: Dictionary): return bool(row.duringMeasurement)),"The real queued spawn pipeline creates additional enemy IDs during measurement")
	await RenderingServer.frame_post_draw
	if not alive(): return
	var image: Image=root.get_texture().get_image()
	var path: String=output_dir.path_join("stress-final-1440x900.png")
	var error: int=image.save_png(path)
	capture_row={"path":ProjectSettings.globalize_path(path),"width":image.get_width(),"height":image.get_height(),"saveError":error,"clock":float(game.elapsed),"fullViewport":true,"analysisOverlay":false,"simulationProcessFrozenAfterMeasurement":true,"readbackAndSaveExcludedFromMeasurement":true,"visualAcceptance":"pending"}
	check(error==OK and image.get_width()==VIEW_SIZE.x and image.get_height()==VIEW_SIZE.y,"One uncropped original1440x900 final PNG saves after measurement")
	finish("complete")
