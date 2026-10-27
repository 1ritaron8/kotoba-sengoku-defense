extends SceneTree
## Reproducible rendered combat, including the real map and HUD.
const Store=preload("res://native/progress.gd")
var app: Node
var label: String="after"

func _initialize() -> void: call_deferred("run")

func percentile(values: Array, fraction: float) -> Variant:
	if values.is_empty(): return null
	var ordered: Array=values.duplicate();ordered.sort()
	return ordered[clampi(ceili(float(ordered.size())*fraction)-1,0,ordered.size()-1)]

func summary(values: Array) -> Dictionary:
	return {"samples":values.size(),"p50Ms":percentile(values,.5),"p95Ms":percentile(values,.95),"over50ms":values.filter(func(value): return float(value)>50).size()}

func settle() -> void:
	for unused in range(8): await process_frame

func fingerprint(game: Node2D) -> String:
	var state: Array=[game.elapsed,game.kills,game.gold]
	for actor in game.units+game.enemies:
		state.append([int(actor.id),float(actor.hp),actor.position.x,actor.position.y,str(actor.get("animation",""))])
	return JSON.stringify(state).sha256_text()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(ProjectSettings.globalize_path("res://tests/profiles/frontline-performance-01/").replace("\\","/").to_lower()) or DisplayServer.get_name()=="headless": quit(2);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label=argument.trim_prefix("--label=")
	if label not in ["before","after"]: quit(2);return
	seed(93271)
	var setup_start: int=Time.get_ticks_usec()
	var phases: Dictionary={}
	root.size=Vector2i(1440,900);root.content_scale_size=root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var saved=Store.new();saved.save_path="user://frontline-performance-fixture.json"
	saved.data.settings={"music":false,"voice":false,"effects":false}
	saved.data.army.levels={"archer":5,"spear":8}
	if not saved.write_save(): quit(2);return
	app=load("res://native/main.tscn").instantiate();app.progress.save_path=saved.save_path
	root.add_child(app);await settle()
	phases["homeReadyMs"]=float(Time.get_ticks_usec()-setup_start)/1000.0
	print("FRONTLINE_PERF home ready ",phases.homeReadyMs)
	app._select_map(0);app._begin_battle()
	app.game.set_process(false);app.set_process(false);app.troops_3d.set_process(false)
	app.player.stop();app.battle_audio.set_enabled(false);await settle()
	phases["battleReadyMs"]=float(Time.get_ticks_usec()-setup_start)/1000.0
	print("FRONTLINE_PERF battlefield ready ",phases.battleReadyMs)
	var game: Node2D=app.game
	game.set_seed(93271)
	game.enemies.clear();game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=10000
	game.gold=10000
	for unused in range(8):
		if not game.begin_placement("spear",0): push_error("Performance fixture spear order failed");quit(2);return
	var shooting_posts: int=0
	for zone in game.zones:
		if str(zone.get("placementRole",""))=="ranged":
			if shooting_posts>=2: break
			var placed: bool=false
			for ring in range(5):
				if placed: break
				for sector in range(24):
					var point: Vector2=zone.position+Vector2.from_angle(float(sector)*TAU/24.0)*(float(zone.get("r",.08))*float(ring)/4.0)
					if bool(game.deployment_preview("archer",point).ok):
						placed=bool(game.submit_deployment("archer",point).ok)
						if placed: break
			if not placed: push_error("Performance fixture archer order failed "+str(zone.id));quit(2);return
			shooting_posts+=1
	game._advance_recruitment(2.2)
	var path_index: int=int(game.units[0].postPathIndex)
	var lengths: Array=game.ground_combat.cumulative[path_index]
	var length_value: float=float(lengths.back())
	var index: int=0
	for unit in game.units:
		if str(unit.type)!="spear": continue
		unit.routeDistance=clampf(length_value*.54+float(index/5)*.014,float(unit.routeMin),float(unit.routeMax))
		unit.position=game.ground_combat._march_position(unit,float(unit.routeDistance))
		unit.combatState="march";unit.gatherRemaining=0;unit.gatherGroupId=0
		index+=1
	for enemy_index in range(24):
		var distance: float=length_value*.49-float(enemy_index/3)*.012
		var enemy: Dictionary=game._spawn_enemy("raider",1,{"originKind":"raider","pathIndex":path_index,"mainIngressOnly":true})
		enemy.position=game.ground_combat.route_point(path_index,distance);enemy.routeProgress=distance
		enemy.pointIndex=1
		while int(enemy.pointIndex)<lengths.size()-1 and float(lengths[int(enemy.pointIndex)])<distance: enemy.pointIndex+=1
		enemy.ingressActive=false
	game._emit_state()
	phases["fixtureReadyMs"]=float(Time.get_ticks_usec()-setup_start)/1000.0
	print("FRONTLINE_PERF fixture ready units=",game.units.size()," enemies=",game.enemies.size())
	var rid: RID=app.troops_3d.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	var frames: Array=[];var simulations: Array=[];var presentations: Array=[];var gpu: Array=[];var calls: Array=[]
	var minimum_actors: int=100000;var maximum_actors: int=0
	var initial: String=fingerprint(game)
	var window_start: int=Time.get_ticks_usec()
	for frame in range(120):
		var start: int=Time.get_ticks_usec()
		game.advance_simulation(1.0/60.0)
		var simulated: int=Time.get_ticks_usec()
		if frame%15==0: game._emit_state()
		game.queue_redraw();app.troops_3d._process(1.0/60.0)
		var presented: int=Time.get_ticks_usec()
		await process_frame
		if frame%30==0: print("FRONTLINE_PERF frame ",frame)
		if frame<30: continue
		frames.append(float(Time.get_ticks_usec()-start)/1000.0)
		simulations.append(float(simulated-start)/1000.0);presentations.append(float(presented-simulated)/1000.0)
		var measured: float=RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if measured>0: gpu.append(measured)
		calls.append(RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		minimum_actors=mini(minimum_actors,app.troops_3d.actors.size());maximum_actors=maxi(maximum_actors,app.troops_3d.actors.size())
		if Time.get_ticks_usec()-window_start>45000000: break
	var capture: String="res://tests/profiles/frontline-performance-01/"+label+"-1440x900.png"
	await RenderingServer.frame_post_draw
	var capture_error: int=root.get_texture().get_image().save_png(capture)
	var actor_diagnostics: Array=[]
	for actor in app.troops_3d.actors.values(): actor_diagnostics.append(actor.diagnostics())
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;app._layout();game._emit_state();await settle()
	app.troops_3d._process(0);await RenderingServer.frame_post_draw
	var capture_small: String="res://tests/profiles/frontline-performance-01/"+label+"-1280x800.png"
	var small_error: int=root.get_texture().get_image().save_png(capture_small)
	var report: Dictionary={"label":label,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"resolution":"1440x900 measured;1280x800 second capture only","phases":phases,"viewport":str(app.troops_3d.viewport.size),"frames":summary(frames),"simulationCpu":summary(simulations),"presentationCpuIncludingPeriodicHud":summary(presentations),"viewportGpuAsync":summary(gpu),"drawCalls":{"p50":percentile(calls,.5),"p95":percentile(calls,.95)},"renderedActorRange":[minimum_actors,maximum_actors],"actorDiagnostics":actor_diagnostics,"initialStateHash":initial,"finalStateHash":fingerprint(game),"finalFriendly":game.units.size(),"finalEnemy":game.enemies.size(),"kills":game.kills,"capture":ProjectSettings.globalize_path(capture),"capture1280":ProjectSettings.globalize_path(capture_small),"captureError":capture_error,"capture1280Error":small_error,"scope":"Actual Stage01 map/HUD with newly authored characters, paid40 Lv8 spears+4 Lv5 archers at the two main shooting positions against24 raiders, synthetic combat arrangement with test-only10000gold. Fixed seed and1/60simulation steps;30warmup/up to90measured rendered frames,45second window limit. Vsync off. Screenshots/resize excluded. GPU is asynchronous battlefield viewport only. Prior actor run timed out without valid metrics; no improvementpercentage/full-game60FPS or natural-balance acceptance claim."}
	var output: FileAccess=FileAccess.open("res://tests/qa_frontline_performance_"+label+".json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("FRONTLINE_RENDER_PERF ",JSON.stringify(report))
	app._cancel_learning_transition();app.player.stop();app.player.stream=null;app.battle_audio.shutdown()
	app.queue_free();await process_frame;quit(0)
