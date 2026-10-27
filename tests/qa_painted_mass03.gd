extends SceneTree
## Explicit density fixture: injected funds/levels/enemies; never a player save.
const Battle=preload("res://native/game.gd")
const Stage=preload("res://native/painted_stage.gd")
const OUTPUT: String="res://tests/profiles/painted-click-03"
var game: Node2D
var rows: Array=[]
var attacks: Array=[]
var births: Array=[]
var output: String
var previous_usec: int=0
var previous_count: int=0
var sampling: bool=false
var rid: RID

func _initialize() -> void: call_deferred("run")

func on_event(row: Dictionary) -> void:
	if str(row.get("type",""))=="recruited": births.append(row.duplicate(true))
	if str(row.get("type",""))=="hit" and attacks.size()<3000: attacks.append(row.duplicate(true))

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	values.sort()
	return float(values[clampi(int(ceil(values.size()*fraction))-1,0,values.size()-1)])

func summary(values: Array) -> Dictionary:
	var frame_ms: Array=[]
	var draw_calls: Array=[]
	var gpu_ms: Array=[]
	for row in values:
		frame_ms.append(row.ms);draw_calls.append(row.drawCalls)
		if row.gpuMs>0: gpu_ms.append(row.gpuMs)
	return {"frames":values.size(),"frameP50Ms":percentile(frame_ms,.5),"frameP95Ms":percentile(frame_ms,.95),"frameMaxMs":frame_ms.max() if not frame_ms.is_empty() else 0,"over50ms":frame_ms.filter(func(value):return value>50).size(),"drawCallsP50":percentile(draw_calls,.5),"drawCallsP95":percentile(draw_calls,.95),"gpuP50Ms":percentile(gpu_ms,.5),"gpuP95Ms":percentile(gpu_ms,.95)}

func observe() -> void:
	previous_usec=Time.get_ticks_usec()
	while sampling:
		await RenderingServer.frame_post_draw
		if not sampling: break
		var now: int=Time.get_ticks_usec()
		rows.append({"ms":float(now-previous_usec)/1000.0,"clock":game.elapsed,"friendly":game.units.size(),"enemies":game.enemies.size(),"bornSincePrior":maxi(0,game.units.size()-previous_count),"drawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"gpuMs":RenderingServer.viewport_get_measured_render_time_gpu(rid)})
		previous_usec=now;previous_count=game.units.size()

func run() -> void:
	output=OUTPUT.path_join("mass-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if DisplayServer.get_name()=="headless": quit(2);return
	root.size=Vector2i(1440,900);root.content_scale_size=root.size
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var stage: Dictionary=Stage.apply(maps[0])
	stage["initialGold"]=100000
	stage["trainingOnly"]=true
	game=Battle.new()
	root.add_child(game)
	var catalog: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	game.configure_roster(catalog,["spear","archer"],{"spear":8,"archer":5})
	game.load_map(stage,10)
	game.field_rect=Rect2(0,60,1440,780)
	game.start_battle()
	game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear();game.spawn_clock=10000
	game.game_event.connect(on_event)
	game.set_performance_profiling_enabled(true)
	var gate: Vector2=Stage.GATE
	var tangent: Vector2=(Stage.INGRESS-gate).normalized()
	var normal: Vector2=Vector2(-tangent.y,tangent.x)
	var admission: Array=[]
	var setup_started: int=Time.get_ticks_usec()
	for index in range(40):
		if game.recruitment_queue.size()>=20: break
		var anchor: Vector2=gate.lerp(Stage.INGRESS,.12+float(index%10)*.038)+normal*(.024 if index%2 else -.024)
		var before: int=Time.get_ticks_usec()
		var result: Dictionary=game.submit_deployment("spear",anchor)
		admission.append({"index":index,"ok":bool(result.get("ok",false)),"usec":Time.get_ticks_usec()-before,"position":str(anchor),"reason":result.get("reason","")})
	var orders: int=game.recruitment_queue.size()
	for index in range(80):
		var hostile: Dictionary=game._spawn_enemy("raider",1,{"originKind":"raider","pathIndex":0})
		var point: Vector2=gate.lerp(Stage.INGRESS,.50+float(index/8)*.014)+normal*float(index%8-4)*.014
		hostile.position=point
		hostile.pointIndex=1
		hostile.routeProgress=game.paths[0].points[0].distance_to(point)
		hostile.ingressActive=false
		# High HP makes density reproducible for this fixture only.
		hostile.hp=1000;hostile.maxHp=1000
	var setup_ms: float=float(Time.get_ticks_usec()-setup_started)/1000.0
	for unused in range(3): await RenderingServer.frame_post_draw
	var caption: Label=Label.new()
	caption.text="QA DENSITY FIXTURE · injected Lv.8 / funds / 80 enemies · not natural gameplay"
	caption.position=Vector2(16,12);caption.add_theme_font_size_override("font_size",22)
	root.add_child(caption)
	rid=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(rid,true)
	sampling=true;observe()
	await create_timer(10).timeout
	sampling=false
	var image_path: String=output.path_join("mass-1440x900.png")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(image_path)
	var born: int=0
	var unique: Dictionary={}
	for birth in births: born+=birth.get("actorIds",[]).size()
	for birth in births:
		for id_value in birth.get("actorIds",[]): unique[id_value]=true
	var failures: Array=[]
	if orders!=20: failures.append("Expected20 accepted orders; observed "+str(orders))
	if born!=orders*5 or unique.size()!=born: failures.append("Expected independent five-member births for every order")
	if births.size()!=orders: failures.append("Each accepted order must complete exactly once")
	var shared: Dictionary={}
	for hit in attacks:
		if str(hit.get("side",""))!="friendly" or str(hit.get("unitType",""))!="spear": continue
		var key: String=str(hit.get("victimId",-1))
		if not shared.has(key): shared[key]=[]
		if not shared[key].has(hit.actorId): shared[key].append(hit.actorId)
	var report: Dictionary={"scope":"Injected rendered density fixture, not natural economy or normal-user-path acceptance. 20 Lv8 five-member orders attempted, 80 injected 1000HP raiders; current real movement/hits/production/rendering; no player save access.","orders":orders,"born":born,"admission":admission,"setupMs":setup_ms,"birthFrames":rows.filter(func(row):return row.bornSincePrior>0),"productionWindow":summary(rows.filter(func(row):return row.clock<3)),"steadyCombat":summary(rows.filter(func(row):return row.clock>=3)),"rows":rows,"attacks":attacks,"sharedVictims":shared,"profiling":game.performance_snapshot(),"renderer":game.painted_actors.diagnostics(),"capture":ProjectSettings.globalize_path(image_path),"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"fpsLimitsUnchanged":true}
	var file: FileAccess=FileAccess.open(output.path_join("mass03-report.json"),FileAccess.WRITE)
	report["status"]="fixture_passed" if failures.is_empty() else "partial_or_failed"
	report["failures"]=failures
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("MASS03 ",ProjectSettings.globalize_path(output.path_join("mass03-report.json")))
	game.queue_free();quit(0 if failures.is_empty() else 1)
