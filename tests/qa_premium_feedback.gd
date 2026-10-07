extends SceneTree
## Observe real battle releases/HP changes, then stress only the presentation queue.
const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
const Feedback = preload("res://native/combat_feedback.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
class MainHealthControlFixture:
	extends "res://native/main.gd"
	func _ready() -> void: pass
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var hunter_display_report: Array = []
var hunter_captures: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok: failures.append(note); push_error(note)

func count(fx: Node2D, kind: String) -> int:
	return int(fx.diagnostics().activeKinds.get(kind,0))

func event_fixture(id: int, action: String = "hit") -> Dictionary:
	return {"eventId":id,"mapId":"fx-stress","action":action,"side":"friendly","unitType":"samurai","actorId":7,"weapon":"katana","victimSide":"enemy","victimId":100+id,"victimType":"shield","damage":42.0,"armor":0.30,"position":{"x":0.5,"y":0.55},"sourcePosition":{"x":0.49,"y":0.55},"victimPosition":{"x":0.5,"y":0.55},"reward":9}

func create_battle(map: Dictionary) -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	var store: RefCounted = Store.new()
	game.configure_roster(store.unit_catalog,store.unit_catalog.map(func(unit):return unit.id),{})
	game.load_map(map)
	game.set_field_rect(Rect2(0,0,1100,620))
	game.gold = 10000
	return game

func create_fx(game: Node2D) -> Node2D:
	var fx: Node2D = Feedback.new()
	fx.battle=game
	root.add_child(fx)
	fx.set_process(false)
	game.game_event.connect(fx.consume_event)
	return fx

func run() -> void:
	if "--healthbars-only" in OS.get_cmdline_user_args():
		await run_healthbars()
		return
	if "--hunter-clearance-only" in OS.get_cmdline_user_args():
		await run_hunter_clearance()
		return
	if "--hunter-alerts-only" in OS.get_cmdline_user_args():
		await run_hunter_alerts()
		return
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"): quit(2); return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	for type_name in ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]:
		var game: Node2D = create_battle(maps[0])
		var fx: Node2D = create_fx(game)
		check(game.begin_placement(type_name),"Actual free placement preview begins "+type_name)
		check(fx.marks.is_empty(),"Preview creates no successful deployment effect "+type_name)
		var placed: bool = false
		for hint in game.placement_hints:
			if hint.x>=0: placed=game.place_unit(hint.x,hint.y); break
		check(placed and count(fx,"deploy")==1,"Paid successful placement creates one grounded effect "+type_name)
		var unit: Dictionary = game.units[-1]
		game.start_battle()
		game.spawn_queue.clear()
		game._spawn_enemy("shield")
		var enemy: Dictionary = game.enemies[-1]
		if type_name not in ["archer","gunner"]:
			enemy.pathIndex=unit.postPathIndex
			enemy.position=game.ground_combat.route_point(int(unit.postPathIndex),float(unit.homeDistance)+0.005)
			for zone in game.zones:
				if str(zone.get("id",""))==str(unit.postId): enemy.pointIndex=int(zone.segmentIndex)+1; break
			game.ground_combat.step(0.001)
		else: enemy.position=unit.position+Vector2(0.025,0)
		fx.reset()
		var emitted: Array = []
		game.game_event.connect(func(event):emitted.append(event.duplicate(true)))
		game._update_units(0.01)
		check(fx.marks.is_empty(),"No muzzle/contact before genuine release "+type_name)
		check(not unit.attackPlan.is_empty(),"Actual attack has scheduled release "+type_name)
		var release_time: float = float(unit.attackPlan.get("releaseTime",0.25))
		var previous_hp: float = float(enemy.hp)
		game._advance_actor_animations(release_time-0.001)
		check(fx.marks.is_empty(),"Windup stays visually quiet until release "+type_name)
		game._advance_actor_animations(0.002)
		if type_name in ["archer","gunner"]:
			check(count(fx,"release" if type_name=="archer" else "muzzle")==1,"Actual projectile release creates one source effect "+type_name)
			check(count(fx,"steel")==0,"Projectile release never fabricates a hit "+type_name)
			game._update_projectiles(0.2)
		else:
			check(count(fx,"charge" if type_name=="commander" else "thrust" if type_name in ["spear","monk"] else "cut")==1,"Actual release produces weapon-appropriate feedback "+type_name)
		check(float(enemy.hp)<previous_hp,"Feedback comes from actual reduced enemy HP "+type_name)
		check(count(fx,"steel")==1,"Actual armored contact creates one impact, including charge deduplication "+type_name)
		check(count(fx,"number")==1,"Selected real combat retains a small damage figure "+type_name)
		for mark in fx.marks:
			check(fx._direction(mark,fx._body(mark.point,mark.get("meta",{}))).is_finite(),"Every actual draw mark has finite source handling, including text "+type_name)
		var payload: Dictionary = {}
		for event in emitted:
			if str(event.action)==("charge_impact" if type_name=="commander" else "hit"): payload=event
		check(not payload.is_empty() and is_equal_approx(float(payload.damage),previous_hp-maxf(0,float(enemy.hp))),"Number is tied to actual HP loss "+type_name)
		var before: String = JSON.stringify(game.snapshot())
		var old_count: int = fx.marks.size()
		fx.consume_event(payload)
		check(fx.marks.size()==old_count and fx.duplicate_events==1,"Re-delivered committed event cannot duplicate feedback "+type_name)
		check(JSON.stringify(game.snapshot())==before,"Feedback never changes units, economy, paths or HP "+type_name)
		observations.append({"type":type_name,"actualDamage":payload.get("damage",0),"releaseTime":release_time,"feedback":fx.diagnostics()})
		fx.free(); game.free()
	# Real enemy counter damage is visibly distinct and selection-aware.
	var game: Node2D = create_battle(maps[0])
	var fx: Node2D = create_fx(game)
	game.begin_placement("spear")
	for hint in game.placement_hints:
		if hint.x>=0: game.place_unit(hint.x,hint.y); break
	var defender: Dictionary = game.units[-1]
	game.start_battle(); game.spawn_queue.clear(); game._spawn_enemy("raider")
	var hostile: Dictionary = game.enemies[-1]
	hostile.blockedBy=defender.id
	hostile.position=defender.position+Vector2(0.002,0)
	hostile.animationClock=0.3
	hostile.counterPlan={"releaseTime":0.25,"damage":20.0}
	fx.reset()
	game.ground_combat.counterattack(hostile,0.01)
	check(count(fx,"number")==1 and not bool(fx.marks[-1].enemyVictim),"Actual selected defender HP loss retains allied damage feedback")
	# Presentation-only load fixture: no invented enemies or battle balance claims.
	fx.reset(); game.selected_id=-1
	fx.consume_event(event_fixture(1))
	fx._process(0.01)
	var age_before: float = float(fx.marks[0].age)
	game.speed=1.0; fx._process(0.1)
	var age_one: float = float(fx.marks[0].age)-age_before
	fx.reset(); fx.consume_event(event_fixture(2)); fx._process(0.01)
	game.speed=2.0; fx._process(0.05)
	check(is_equal_approx(float(fx.marks[0].age),age_one),"One- and two-speed real-time intervals advance the same simulation FX age")
	var frozen: String = JSON.stringify(fx.marks)
	var frozen_clock: float = fx.feedback_clock
	game.paused=true; fx._process(0.25)
	check(JSON.stringify(fx.marks)==frozen and fx.feedback_clock==frozen_clock,"Immediate engine pause freezes particles, numbers and throttles without state-signal delay")
	game.paused=false; fx.paused=true; fx._process(0.25)
	check(JSON.stringify(fx.marks)==frozen,"Explicit learning/menu pause also freezes feedback")
	fx.paused=false; game.speed=3; fx.reset()
	var gun: Dictionary = event_fixture(3,"shot"); gun.weapon="matchlock"
	fx.consume_event(gun); fx._process(0.25)
	check(count(fx,"muzzle")==1 and float(fx.marks[0].age)==0,"A long 3x release frame retains its flash for one GPU presentation")
	fx._process(0.25)
	check(fx.marks.is_empty(),"Accelerated feedback expires instead of accumulating stale flashes")
	fx.reset(); game.speed=1; game.selected_id=-1
	var small: Dictionary = event_fixture(4); small.damage=12; small.victimType="raider"; small.armor=0
	fx.consume_event(small)
	check(count(fx,"contact")==1 and count(fx,"number")==0,"Unselected small hits remain audible/visible contacts without text clutter")
	for index in range(5,25): fx.consume_event(event_fixture(index))
	check(count(fx,"number")==4,"Large-hit text is capped globally at four targets")
	fx.reset()
	var repeated: Dictionary = event_fixture(30)
	fx.consume_event(repeated); repeated.eventId=31; fx.consume_event(repeated)
	check(count(fx,"number")==1,"Repeated target text is throttled even when real hit events differ")
	fx._process(0.01); fx._process(0.25); fx._process(0.25); fx._process(0.06)
	repeated.eventId=32; fx.consume_event(repeated)
	check(count(fx,"number")==1,"A target number renews after the gate without overlapping its previous figure")
	fx.reset()
	for index in range(40,48): fx.consume_event(event_fixture(index,"killed"))
	check(count(fx,"reward")==1,"Mass kills show only one aggregated supply label")
	for mark in fx.marks:
		if mark.kind=="reward": check(int(mark.amount)==72,"Visual reward aggregation retains the eight actual reward amounts")
	fx.reset()
	var sailing: Dictionary = event_fixture(48,"killed"); sailing.victimSailing=true
	fx.consume_event(sailing)
	check(count(fx,"fall")==0,"Sailing deaths cannot create land dust on water")
	fx.reset()
	for invalid in [Vector2(NAN,0.5),Vector2(INF,0.5),Vector2(-0.01,0.5),Vector2(1.01,0.5),Vector2(0.5,1.01)]:
		var value: Dictionary = event_fixture(100+checks)
		value.victimPosition=invalid
		fx.consume_event(value)
	check(fx.marks.is_empty(),"Malformed/out-of-field normalized impacts do not get clamped into fake edge combat")
	for dimensions in [Vector2(1248,636),Vector2(1408,736),Vector2(1888,916)]:
		game.set_field_rect(Rect2(Vector2.ZERO,dimensions))
		for point in [Vector2.ZERO,Vector2.ONE,Vector2(0.5,0.5)]:
			var clipped: Vector2 = fx._clip_point(fx._body(point))
			check(Rect2(Vector2.ZERO,dimensions).has_point(clipped),"Line endpoints are contained at battle-field corners / "+str(dimensions))
	var state_before: String = JSON.stringify(game.snapshot())
	var tick: int = Time.get_ticks_usec()
	for index in range(10000): fx.consume_event(event_fixture(1000+index))
	var stress_ms: float = float(Time.get_ticks_usec()-tick)/1000
	check(fx.marks.size()<=96 and count(fx,"number")<=4,"Ten-thousand-event burst keeps a fixed particle/text drawing workload")
	check(fx._seen_events.size()<=512 and fx.last_number.size()<=256,"Deduplication and number throttle history are bounded in a single burst")
	check(JSON.stringify(game.snapshot())==state_before,"Stress rendering does not spend supplies or mutate real battle state")
	fx._process(0.01)
	for step in range(6): fx._process(0.25)
	check(fx.marks.is_empty(),"Burst workload drains completely after cosmetic lifetimes")
	fx.hide(); var hidden_clock: float=fx.feedback_clock; fx._process(0.1)
	check(fx.feedback_clock==hidden_clock,"Hidden battlefield stops particle simulation")
	fx.show(); fx.reset()
	check(fx.diagnostics().events.is_empty() and fx.duplicate_events==0,"New battle clears presentation history")
	fx.free(); game.free()
	var report: Dictionary = {"checks":checks,"failures":failures,"realReleases":observations,"burstEvents":10000,"burstCpuMs":stress_ms,"scope":"Eight actual engine windup/release/projectile-or-melee HP losses and an enemy counterattack; selected/large-hit text, real event redelivery, burst bound, clock/speed/pause/hidden behavior, finite field positions and unmodified battle snapshots. Headless clipping checks cover endpoints; actual pixels are verified separately with a GPU capture."}
	var output: String = "user://qa_premium_feedback.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_premium_feedback.json"
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("PREMIUM_FEEDBACK_QA ",JSON.stringify({"checks":checks,"failures":failures,"burstCpuMs":stress_ms}))
	quit(0 if failures.is_empty() else 1)

func prepare_physical_builder(script: Script, stage: Dictionary) -> Node3D:
	var builder: Node3D = script.new()
	builder.stage = stage.duplicate(true)
	builder.history = builder.stage.get("historicalBattlefield", {})
	builder.width = 18.5
	builder.elevation = 50.0
	builder.depth = 18.5 / (1280.0 / 720.0) / sin(deg_to_rad(50.0))
	builder.seed_value = absi(str(stage.id).hash())
	builder._collect_geometry()
	return builder

func check_hunter_surface(maps: Array) -> void:
	var baseline_path: String = OS.get_environment("QA_HUNTER_RENDER_BASELINE").replace("\\", "/")
	check(baseline_path.to_lower().begins_with("c:/jp_df/tests/profiles/hunter-route-alerts/") and FileAccess.file_exists(baseline_path), "Previous renderer is an isolated preserved source snapshot")
	if failures.size() > 0: return
	var previous_script: Script = load(baseline_path)
	check(previous_script != null, "The actual previous renderer source parses")
	if previous_script == null: return
	var visible_weight_reductions: int = 0
	var ingress_count: int = 0
	for stage in maps:
		var previous: Node3D = prepare_physical_builder(previous_script, stage)
		var current: Node3D = prepare_physical_builder(Battlefield, stage)
		check(current.road_segments == previous.road_segments, "Actual road/side metadata remains byte-equivalent: " + str(stage.id))
		check(JSON.stringify(current._physical_contract(stage)) == JSON.stringify(previous._physical_contract(stage)), "Physical geometry fingerprint stays unchanged: " + str(stage.id))
		var height_samples: Array[Vector2] = [Vector2(.1,.1),Vector2(.5,.5),Vector2(.9,.9)]
		for zone in stage.get("buildZones", []): height_samples.append(Vector2(float(zone.x),float(zone.y)))
		for entry in stage.get("sideAmbushEntrances", []):
			ingress_count += 1
			var points: Array = entry.get("connectionPoints", [])
			for value in points: height_samples.append(Vector2(float(value.x),float(value.y)))
			for index in range(points.size()-1):
				var a: Vector2 = Vector2(float(points[index].x),float(points[index].y))
				var b: Vector2 = Vector2(float(points[index+1].x),float(points[index+1].y))
				var point: Vector2 = a.lerp(b,.5)
				height_samples.append(point)
				var old_colour: Color = previous._ground_colour(point)
				var new_colour: Color = current._ground_colour(point)
				check(new_colour.r <= old_colour.r + .000001, "Hiding a hunter corridor cannot add ground-road pigment")
				if new_colour.r < old_colour.r - .01: visible_weight_reductions += 1
		for point in height_samples:
			check(current._road_projection(point) == previous._road_projection(point), "Default projection retains actual hunter navigation metadata")
			check(is_equal_approx(current._raw_height(point),previous._raw_height(point)), "Actual physical height stays unchanged at authored/sample coordinates")
			var visible: Dictionary = current._road_projection(point, true)
			check(not bool(visible.side), "Visual road query never selects a hunter-only corridor")
			var independently_nearest: float = 1000.0
			for segment in current.road_segments:
				if bool(segment.side): continue
				var scale: Vector2 = Vector2(current.width,current.depth)
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point*scale,Vector2(segment.a)*scale,Vector2(segment.b)*scale)
				independently_nearest = minf(independently_nearest,(point*scale).distance_to(closest))
			check(absf(float(visible.distance)-independently_nearest)<.0001, "Visible query matches independently measured primary road distance")
		hunter_display_report.append({"stageId":stage.id,"physicalFingerprint":JSON.stringify(current._physical_contract(stage)).sha256_text(),"heightSamples":height_samples.size(),"hunterEntrances":stage.get("sideAmbushEntrances",[]).size(),"roadMetadataPreserved":current.road_segments == previous.road_segments})
		previous.free()
		current.free()
	check(ingress_count == 103 and hunter_display_report.size() == 40, "All forty actual stages and 103 hunter ingress records were checked")
	check(visible_weight_reductions > 0, "Actual hunter centreline samples lose their previous visible dirt weight")
	# Observe actual mesh construction, rather than only a diagnostic count.
	var previous: Node3D = prepare_physical_builder(previous_script, maps[0])
	var current: Node3D = prepare_physical_builder(Battlefield, maps[0])
	for builder in [previous,current]:
		builder.stats = {"meshNodes":0,"roadTriangles":0,"renderTrianglesUpperBound":0}
		builder._build_height_grid()
		builder._build_ground()
		builder._build_roads()
	var old_arrays: Array = previous.ground_mesh.mesh.surface_get_arrays(0)
	var new_arrays: Array = current.ground_mesh.mesh.surface_get_arrays(0)
	check(old_arrays[Mesh.ARRAY_VERTEX] == new_arrays[Mesh.ARRAY_VERTEX] and old_arrays[Mesh.ARRAY_INDEX] == new_arrays[Mesh.ARRAY_INDEX], "Actual complete indexed terrain geometry is unchanged")
	var lowered_vertices: int = 0
	for index in range(old_arrays[Mesh.ARRAY_COLOR].size()):
		if new_arrays[Mesh.ARRAY_COLOR][index].r < old_arrays[Mesh.ARRAY_COLOR][index].r - .01: lowered_vertices += 1
	check(lowered_vertices > 0, "Actual terrain vertex colours remove the baked hunter dirt strip")
	check(int(current.stats.roadTriangles) > 0 and int(current.stats.roadTriangles) < int(previous.stats.roadTriangles), "Actual road mesh keeps primary roads while omitting hunter strips/junctions")
	observations.append({"kind":"actualNativeRoadMesh","oldTriangles":previous.stats.roadTriangles,"newTriangles":current.stats.roadTriangles,"loweredTerrainVertices":lowered_vertices,"heightVertices":new_arrays[Mesh.ARRAY_VERTEX].size()})
	previous.free()
	current.free()

func produce_alert_target(game: Node2D, type_name: String) -> Dictionary:
	var jobs_before: int = game.recruitment_queue.size()
	if not game.begin_placement(type_name,0): return {}
	# Marching classes commit a real base/route job at begin_placement.
	# Stationary classes commit only after the actual valid pocket click.
	var accepted: bool = game.recruitment_queue.size()>jobs_before
	if not accepted:
		for zone in game.zones:
			var hint: Vector2 = game._zone_placement_hint(zone,type_name)
			if hint.x >= 0 and bool(game.placement_preview(hint).valid):
				accepted = game.place_unit(hint.x,hint.y)
				if accepted: break
	if not accepted: game.cancel_recruit(); return {}
	var job_id: int = int(game.recruitment_queue[-1].id)
	if not game.running: game.start_battle()
	game.spawn_queue = ["raider"]
	game.spawn_source_waves = [1]
	game.spawn_metadata = [{}]
	game.spawn_clock = 100000.0
	for tick in range(300):
		game.advance_simulation(.025)
		for unit in game.units:
			if int(unit.get("productionJobId",-1)) == job_id: return unit
	return {}

func hunter_image(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("user://hunter-" + label + ".png")
	check(image != null and not image.is_empty() and image.save_png(path) == OK, "Actual hunter warning GPU pixels save in the private profile")
	hunter_captures.append(path)
	return image

func run_hunter_alerts() -> void:
	var appdata: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var localdata: String = OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	var capture: bool = "--capture" in OS.get_cmdline_user_args()
	if not appdata.begins_with("c:/jp_df/tests/profiles/hunter-route-alerts/") or appdata != localdata or not user_path.begins_with(appdata+"/") or (DisplayServer.get_name()=="headless") == capture:
		push_error("Hunter presentation QA requires its isolated CPU/GPU profile")
		quit(2); return
	var maps_hash: String = FileAccess.get_sha256("res://native/maps.json")
	var plans_hash: String = FileAccess.get_sha256("res://native/learning_plans.json")
	check(maps_hash == "ea5a85f32c4a8962a1c19734f36ac58ec22301c17b1ba36a966408429df8e252", "Hunter display uses exactly the frozen v6 maps")
	check(plans_hash == "e60ddf1728fdf1a81439d0058a08b1dec87a2cabb8fa7fedf8cadbd8fbbb01ab", "Hunter display uses exactly the frozen v6 learning plans")
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check_hunter_surface(maps)
	var game: Node2D = create_battle(maps[5])
	var fx: Node2D = create_fx(game)
	game.set_field_rect(Rect2(40,60,1200,650))
	fx.position = game.field_rect.position
	var alerts: Array = []
	fx.emplacement_alerted.connect(func(event: Dictionary): alerts.append(event.duplicate(true)))
	var targets: Array = []
	for type_name in ["archer","gunner","monk","naginata"]:
		var target: Dictionary = produce_alert_target(game,str(type_name))
		check(not target.is_empty(), "Actual queued production yields the alert target: " + str(type_name))
		if not target.is_empty(): targets.append(target)
	fx.reset()
	root.size = Vector2i(1280,760)
	root.content_scale_size = root.size
	var before_image: Image
	if capture: before_image = await hunter_image("before-hit")
	game._queue_enemy_spawn("enemy_samurai",1,{"pathIndex":0})
	game.queue_redraw()
	if game.actor_overlay!=null: game.actor_overlay.queue_redraw()
	check(game.ambush_warnings.size()==1, "Actual hunter scheduling retains its existing two-second warning")
	if not game.ambush_warnings.is_empty():
		var warning: Dictionary = game.ambush_warnings[0]
		var marker: Dictionary = game.ambush_warning_geometry(warning)
		check(str(marker.shape)=="pulse" and not marker.has("direction") and Vector2(marker.center)==game._screen(warning.position), "An actual scheduled warning displays only its departure pulse")
		if capture:
			var warning_image: Image = await hunter_image("departure-pulse")
			var centre: Vector2 = marker.center
			var local_marker: Rect2 = Rect2(centre-Vector2(65,45),Vector2(130,70))
			var changed_local: int = 0
			var changed_outside: int = 0
			for y in range(before_image.get_height()):
				for x in range(before_image.get_width()):
					var a: Color = before_image.get_pixel(x,y)
					var b: Color = warning_image.get_pixel(x,y)
					if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.02:
						if local_marker.has_point(Vector2(x,y)): changed_local+=1
						else: changed_outside+=1
			check(changed_local>0 and changed_outside==0, "Actual scheduling adds only the local warning pixels, with no remote route/arrow")
			observations.append({"kind":"actualScheduledWarning","localChangedPixels":changed_local,"outsideChangedPixels":changed_outside,"departure":warning.position,"centre":centre})
	game.ambush_warnings.clear()
	game.queue_redraw()
	if game.actor_overlay!=null: game.actor_overlay.queue_redraw()
	var hunter: Dictionary = game._spawn_enemy("enemy_samurai",1,{"pathIndex":0})
	check(str(hunter.combatRole)==game.ENEMY_EMPLACEMENT_ROLE, "Actual unlocked spawn supplies an emplacement attacker")
	for target in targets:
		var hp: float = float(target.hp)
		var damage: float = game._damage_friendly(target,9.0,hunter)
		check(damage > 0 and float(target.hp) < hp, "Actual native HP damage commits before the location warning")
		check(fx.marks.any(func(mark):return str(mark.kind)=="emplacement_alert" and Vector2(mark.point)==Vector2(target.position)), "Actual victim location owns a nondirectional pulse")
	check(alerts.size()==1 and count(fx,"emplacement_alert")==targets.size() and fx.danger_clock>0 and fx.banner=="진지가 공격받고 있습니다", "Concurrent real hits retain per-location pulses, one notice and the red edge warning")
	if capture:
		var after_image: Image = await hunter_image("after-hit")
		var edge_changes: int = 0
		for x in range(42,1238):
			var a: Color = before_image.get_pixel(x,62)
			var b: Color = after_image.get_pixel(x,62)
			if b.r > a.r + .03 and b.r > b.g * 1.3: edge_changes += 1
		check(edge_changes > 100, "Actual field-edge pixels acquire the red attack warning")
		observations.append({"kind":"actualGpuWarning","redEdgeChangedPixels":edge_changes})
	var committed: Dictionary = alerts[0] if not alerts.is_empty() else {}
	var frozen_game: String = JSON.stringify(game.snapshot())
	var pulse_count: int = count(fx,"emplacement_alert")
	fx.consume_event(committed)
	check(alerts.size()==1 and count(fx,"emplacement_alert")==pulse_count, "Duplicate event delivery cannot replay a location pulse or notice")
	check(JSON.stringify(game.snapshot())==frozen_game, "Redraw/notice delivery never changes combat or rewards")
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	game.configure_roster(catalog,["archer","spear"],{})
	for target in targets:
		var hp: float = float(target.hp)
		check(game._damage_friendly(target,9.0,hunter)==0 and float(target.hp)==hp, "Early protection rejects damage even after a late-map fixture is re-locked")
	check(alerts.size()==1 and count(fx,"emplacement_alert")==pulse_count, "Protected targets do not fabricate a committed-hit warning")
	fx.reset()
	for index in range(10000):
		var value: Dictionary = event_fixture(1000+index)
		value.victimSide="friendly"; value.victimType="archer"; value.hpBefore=100.0; value.hpAfter=91.0; value.damage=9.0
		fx.consume_event(value)
	check(fx.marks.size()<=fx.MAX_MARKS and fx._emplacement_pulses.size()<=128, "Mass repeated warnings keep bounded particles and per-target history")
	var frozen_alerts: String = JSON.stringify(fx.marks)
	game.paused=true; fx._process(.25)
	check(JSON.stringify(fx.marks)==frozen_alerts, "Explicit pause freezes location-warning clocks")
	game.paused=false
	fx.reset()
	for value in [{"damage":0.0,"hpBefore":100.0,"hpAfter":100.0},{"damage":9.0,"hpBefore":100.0,"hpAfter":100.0},{"damage":NAN,"hpBefore":100.0,"hpAfter":91.0}]:
		var invalid: Dictionary = event_fixture(20000+checks)
		invalid.victimSide="friendly"; invalid.victimType="archer"; invalid.merge(value,true)
		fx.consume_event(invalid)
	check(count(fx,"emplacement_alert")==0 and fx.danger_clock==0, "Missing, zero and nonfinite HP losses cannot create danger warnings")
	for stage in maps:
		game.load_map(stage)
		var route_snapshot: String = JSON.stringify(game.paths)
		for entry in stage.get("sideAmbushEntrances", []):
			var position: Vector2 = Vector2(float(entry.point.x),float(entry.point.y))
			var marker: Dictionary = game.ambush_warning_geometry({"position":position,"remainingSeconds":1.5})
			check(str(marker.shape)=="pulse" and not marker.has("direction") and Vector2(marker.center)==game._screen(position), "Actual warning display retains the entrance location without revealing a route/direction")
		check(JSON.stringify(game.paths)==route_snapshot, "Rendering preserves every authored main/escort movement route")
	fx.free(); game.free()
	Battlefield.release_shared_resources()
	for frame in range(4): await process_frame
	check(FileAccess.get_sha256("res://native/maps.json")==maps_hash and FileAccess.get_sha256("res://native/learning_plans.json")==plans_hash, "QA leaves actual maps and learning plans frozen")
	var report: Dictionary = {"checks":checks,"failures":failures,"pass":failures.is_empty(),"mapsSha256":maps_hash,"plansSha256":plans_hash,"appData":appdata,"localAppData":localdata,"userData":user_path,"gpu":capture,"stages":hunter_display_report,"observations":observations,"captures":hunter_captures,"scope":"Actual previous/current native surface, physical metadata and height samples for all forty stages; real indexed terrain/road meshes; actual paid/queued fixed-role production and native HP commit, protection, signal/duplicate/pause/burst bounds. GPU mode additionally captures real Game/feedback pixels. Isolated funds/full roster and held waves are fixtures, not campaign balance or natural victory evidence. Existing hit sounds and Korean danger text are reused; voice resources and speech queues are unchanged."}
	var output: FileAccess = FileAccess.open("user://qa_hunter_alerts.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")); output.close()
	print("HUNTER_PRESENTATION_QA checks=",checks," failures=",failures.size()," gpu=",capture)
	quit(0 if failures.is_empty() else 1)

func hunter_function_source(path: String, function_name: String) -> String:
	var source: String = FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	var start: int = source.find("\nfunc " + function_name + "(")
	if start < 0: return ""
	var end: int = source.find("\nfunc ", start+1)
	return source.substr(start, end-start if end>=0 else -1)

func run_hunter_clearance() -> void:
	var appdata: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var localdata: String = OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	if not appdata.begins_with("c:/jp_df/tests/profiles/hunter-route-alerts/") or appdata!=localdata or not user_path.begins_with(appdata+"/") or DisplayServer.get_name()!="headless":
		push_error("Hunter clearance QA requires an isolated CPU profile")
		quit(2); return
	var baseline_path: String = OS.get_environment("QA_HUNTER_RENDER_BASELINE").replace("\\", "/")
	var bad_path: String = OS.get_environment("QA_HUNTER_CLEARANCE_BASELINE").replace("\\", "/")
	for path in [baseline_path,bad_path]:
		check(path.to_lower().begins_with("c:/jp_df/tests/profiles/hunter-route-alerts/") and FileAccess.file_exists(path), "Actual preserved clearance sources stay in the private profile")
	if not failures.is_empty(): quit(2); return
	var original_script: Script = load(baseline_path)
	var rejected_script: Script = load(bad_path)
	var source_path: String = "res://native/battlefield_3d.gd"
	for method in ["_build_roads","_ground_colour","_raw_height","_build_height_grid","_physical_contract"]:
		var current_source: String = hunter_function_source(source_path,method)
		check(not current_source.is_empty() and current_source==hunter_function_source(bad_path,method), "The clearance correction leaves hidden road rendering and physical geometry code unchanged: "+method)
	for method in ["_scatter_clear","_tree_view_clear","_weather_detail_clear","_build_obstacles"]:
		var current_source: String = hunter_function_source(source_path,method)
		check(not current_source.is_empty() and current_source==hunter_function_source(baseline_path,method), "Actual decoration clearance returns exactly to the original all-side behavior: "+method)
	var before: Dictionary = {}
	for path in ["res://native/maps.json","res://native/learning_plans.json","res://native/game.gd","res://native/combat_feedback.gd","res://native/main.gd"]:
		before[path]=FileAccess.get_sha256(path)
	check(before["res://native/maps.json"]=="ea5a85f32c4a8962a1c19734f36ac58ec22301c17b1ba36a966408429df8e252", "The approved source map is fixed")
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var scatter_fixes: int = 0
	var tree_fixes: int = 0
	var permitted_trees: int = 0
	var counterexamples: Array = []
	for stage in maps:
		var original: Node3D = prepare_physical_builder(original_script,stage)
		var rejected: Node3D = prepare_physical_builder(rejected_script,stage)
		var current: Node3D = prepare_physical_builder(Battlefield,stage)
		check(original.road_segments==current.road_segments and original._physical_contract(stage)==current._physical_contract(stage), "Actual side Nav metadata and physical fingerprint remain unchanged: "+str(stage.id))
		var samples: Array[Vector2] = []
		for segment in current.road_segments:
			if not bool(segment.side): continue
			for fraction in [.2,.5,.8]:
				var point: Vector2 = Vector2(segment.a).lerp(Vector2(segment.b),float(fraction))
				samples.append(point)
				check(not current._scatter_clear(point,1.0), "Actual side centreline excludes tree/rock scattering without painting a road")
				if rejected._scatter_clear(point,1.0):
					scatter_fixes+=1
					if counterexamples.size()<8: counterexamples.append({"kind":"scatter","stageId":stage.id,"point":point,"oldVisibleOnlyAccepted":true,"allSideAccepted":false})
				for height in [2.2,2.9,3.6]:
					# Use the actual production tree size and its middle crown tier.
					var root_point: Vector2 = point+Vector2(0,float(height)*.65/tan(deg_to_rad(current.elevation))/current.depth)
					if not current._inside(root_point): continue
					check(not current._tree_view_clear(root_point,float(height)), "Actual scaled tree crown cannot cover a hidden walking lane")
					if rejected._tree_view_clear(root_point,float(height)):
						tree_fixes+=1
						if counterexamples.size()<24: counterexamples.append({"kind":"projectedTreeCrown","stageId":stage.id,"treeRoot":root_point,"heightWorld":height,"projectedCrown":point,"oldVisibleOnlyAccepted":true,"allSideAccepted":false})
		for grid_y in range(1,10):
			for grid_x in range(1,10): samples.append(Vector2(grid_x*.1,grid_y*.1))
		for point in samples:
			check(is_equal_approx(current._raw_height(point),original._raw_height(point)), "Tree clearance never changes actual ground height")
			check(current._scatter_clear(point,.46)==original._scatter_clear(point,.46) and current._scatter_clear(point,1.0)==original._scatter_clear(point,1.0), "Actual grass/boulder/tree clearance matches the original at route and control samples")
			check(current._weather_detail_clear(point)==original._weather_detail_clear(point), "Weather decoration cannot occupy an original hidden lane")
			for height in [2.2,2.9,3.6]:
				var clear: bool = current._tree_view_clear(point,float(height))
				check(clear==original._tree_view_clear(point,float(height)), "Actual size-dependent crown clearance matches the original")
				if not clear: continue
				permitted_trees+=1
				for tier in [.42,.65,.86]:
					var projected: Vector2 = point-Vector2(0,float(height)*float(tier)/tan(deg_to_rad(current.elevation))/current.depth)
					check(float(current._road_projection(projected).distance)>=current.ROAD_HALF_WIDTH+float(height)*.40, "Every accepted scaled crown tier stays outside all actual walking lanes")
		original.free(); rejected.free(); current.free()
	check(maps.size()==40 and scatter_fixes>0 and tree_fixes>0 and permitted_trees>0, "Real forty-stage counterexamples reject hidden-lane decoration while safe trees remain possible")
	var after: Dictionary = {}
	for path in before: after[path]=FileAccess.get_sha256(path)
	check(before==after, "The narrow clearance QA is read-only for map, plans and the other three production sources")
	Battlefield.release_shared_resources()
	for frame in range(4): await process_frame
	var report: Dictionary = {"checks":checks,"failures":failures,"pass":failures.is_empty(),"stageCount":maps.size(),"scatterCounterexamples":scatter_fixes,"treeCrownCounterexamples":tree_fixes,"acceptedTreeControls":permitted_trees,"examples":counterexamples,"sourceHashesBefore":before,"sourceHashesAfter":after,"rendererSha256":FileAccess.get_sha256(source_path),"userData":user_path,"scope":"Only the actual native decoration clearance correction. Actual side-route centres and 2.2/2.9/3.6 world-height tree crown tiers versus original/rejected sources; no geometry or movement change, no full content/voice rerun and no new GPU claim."}
	var output: FileAccess = FileAccess.open("user://qa_hunter_clearance.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")); output.close()
	print("HUNTER_CLEARANCE_QA checks=",checks," failures=",failures.size()," scatterCounterexamples=",scatter_fixes," treeCounterexamples=",tree_fixes)
	quit(0 if failures.is_empty() else 1)

func run_healthbars() -> void:
	var appdata: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var localdata: String = OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	var capture: bool = "--capture" in OS.get_cmdline_user_args()
	if not appdata.begins_with("c:/jp_df/tests/profiles/healthbar-presentation/") or appdata!=localdata or not user_path.begins_with(appdata+"/") or (DisplayServer.get_name()=="headless")==capture:
		push_error("Health bar QA requires its isolated CPU/GPU profile")
		quit(2); return
	var previous_path: String = OS.get_environment("QA_HEALTHBAR_BASELINE").replace("\\", "/")
	check(previous_path.to_lower().begins_with("c:/jp_df/tests/profiles/healthbar-presentation/") and FileAccess.file_exists(previous_path), "Previous actual Game drawing source is preserved inside the test profile")
	if not failures.is_empty(): quit(2); return
	var source_before: Dictionary = {}
	for path in ["res://native/game.gd","res://native/main.gd","res://native/maps.json","res://native/learning_plans.json","res://native/troops_3d.gd","res://native/battlefield_3d.gd","res://native/ground_combat.gd","res://native/units.json"]: source_before[path]=FileAccess.get_sha256(path)
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var actor_drawing: String = hunter_function_source("res://native/game.gd","_draw_actor_health")
	var base_drawing: String = hunter_function_source("res://native/game.gd","_draw_field_markers")
	check(not actor_drawing.contains("rect.grow(") and not actor_drawing.contains("canvas.draw_rect(rect,Color(\"f3f6ee\")") and not base_drawing.contains("canvas.draw_rect(health,Color(\"f3f6ee\")"), "Actual actor/base drawing has no outer health-bar rectangle or white outline")
	var game: Node2D = create_battle(maps[5])
	var previous: Node2D = load(previous_path).new()
	root.add_child(previous); previous.set_process(false); previous.hide()
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	previous.configure_roster(catalog,catalog.map(func(unit):return unit.id),{})
	var actual_actors: Array = []
	for type_name in ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]:
		var unit: Dictionary = produce_alert_target(game,str(type_name))
		check(not unit.is_empty(), "Actual paid queued production supplies a friendly HP bar: "+str(type_name))
		if not unit.is_empty(): actual_actors.append({"actor":unit,"friendly":true})
	for kind in ["raider","runner","shield","heavy","enemy_archer","enemy_gunner","enemy_samurai","enemy_cavalry"]:
		var enemy: Dictionary = game._spawn_enemy(str(kind),1,{"pathIndex":0})
		check(not enemy.is_empty(), "Actual native spawning supplies a hostile HP bar: "+str(kind))
		if not enemy.is_empty(): actual_actors.append({"actor":enemy,"friendly":false})
	var compared_bases: int = 0
	for stage in maps:
		game.load_map(stage); previous.load_map(stage)
		for dimensions in [Vector2(1200,620),Vector2(1360,700),Vector2(1840,900)]:
			game.set_field_rect(Rect2(Vector2(40,60),dimensions)); previous.set_field_rect(game.field_rect)
			for entry in actual_actors:
				var actor: Dictionary = entry.actor
				var before: Dictionary = previous.healthbar_layout(actor,bool(entry.friendly))
				var after: Dictionary = game.healthbar_layout(actor,bool(entry.friendly))
				var fill: Color = Color(str(after.color))
				var background: Color = Color(str(after.backgroundColor))
				check(after.anchor==before.anchor and after.rect.get_center()==before.rect.get_center() and is_equal_approx(float(after.ratio),float(before.ratio)) and after.rect.size.x==before.rect.size.x and after.fillRect.size.x==before.fillRect.size.x and str(after.text).is_empty(), "Actual line preserves health ratio, head anchor, bar centre, widths and no digits")
				check(is_equal_approx(after.rect.size.y,2.0) and is_equal_approx(after.fillRect.size.y,2.0), "Actual common actor HP is a two-pixel solid line")
				check(fill.a==1.0 and background.a==1.0 and maxf(background.r,maxf(background.g,background.b))<.2, "Actual bar fill and dark track are fully opaque")
				check((fill.g>fill.r*1.5 and fill.g>fill.b*1.5) if entry.friendly else (fill.r>fill.g*1.5 and fill.r>fill.b*1.5), "Actual friendly/hostile bars are green/red")
				if entry.friendly: check(game.selected_unit_label_layout(actor)==previous.selected_unit_label_layout(actor), "Slimming the line preserves the actual selected troop name/readings position")
				else: check(game.enemy_role_marker_geometry(actor)==previous.enemy_role_marker_geometry(actor), "Slimming the line preserves the actual enemy role marker anchor")
			var old_bases: Dictionary = {}
			for layout in previous.field_marker_layouts():
				if str(layout.marker.markerKind)=="objective": old_bases[str(layout.marker.id)]=layout
			for layout in game.field_marker_layouts():
				if str(layout.marker.markerKind)!="objective": continue
				compared_bases+=1
				check(is_equal_approx(layout.healthRect.size.y,2.0) and Color(game.HEALTHBAR_FRIENDLY_COLOR).a==1.0 and Color(game.HEALTHBAR_BACKGROUND_COLOR).a==1.0, "Every actual friendly base uses an opaque two-pixel green HP line")
				var prior: Dictionary = old_bases[str(layout.marker.id)]
				check(layout.healthRect.get_center()==prior.healthRect.get_center() and layout.healthRect.size.x==prior.healthRect.size.x and layout.labelRect==prior.labelRect, "The actual base label and health-line centre/length retain their previous anchors")
	var app: Node = MainHealthControlFixture.new()
	root.add_child(app); app.set_process(false); app.game=game
	app.progress.read_save()
	app.font=load("res://native/game_fonts.gd").body()
	app._build_ui()
	app.ui.hide()
	var selected: ProgressBar = app.army_health
	var fill_style: StyleBoxFlat = selected.get_theme_stylebox("fill")
	var background_style: StyleBoxFlat = selected.get_theme_stylebox("background")
	check(not selected.show_percentage and fill_style.bg_color.a==1.0 and background_style.bg_color.a==1.0 and fill_style.bg_color.g>fill_style.bg_color.r*1.5, "Actual Main-built selected-friendly bar has opaque green/dark styles and no percentage")
	check(hunter_function_source("res://native/main.gd","_layout").contains("_place(army_health,14,tactics_y+tactics_height+2,inspector_width-28,2)"), "Actual Main layout assigns a two-pixel solid health line")
	check(fill_style.border_width_top==0 and fill_style.border_width_bottom==0 and fill_style.border_width_left==0 and fill_style.border_width_right==0 and background_style.border_width_top==0 and background_style.border_width_bottom==0, "Actual Main-built health styles have no border")
	selected.reparent(root)
	selected.position=Vector2(40,24); selected.size=Vector2(220,2); selected.max_value=100; selected.value=75; selected.show()
	check(selected.size.y==2.0, "The actual Main ProgressBar control accepts its two-pixel height")
	game.load_map(maps[5]); game.set_field_rect(Rect2(40,60,1200,650))
	game.units=actual_actors.filter(func(entry):return bool(entry.friendly)).map(func(entry):return entry.actor)
	game.enemies=actual_actors.filter(func(entry):return not bool(entry.friendly)).map(func(entry):return entry.actor)
	game.running=true; game.between_waves=false
	# Spread hostile diagnostic markers for sampling; this is a drawing fixture.
	for index in range(game.enemies.size()): game.enemies[index].position=Vector2(.14+index*.10,.13)
	# Commit real partial HP losses before observing the read-only line renderer.
	if not game.units.is_empty() and not game.enemies.is_empty():
		var attackers: Array = game.enemies.filter(func(enemy):return str(enemy.get("combatRole",""))==game.ENEMY_EMPLACEMENT_ROLE)
		check(not attackers.is_empty(), "A real emplacement attacker remains the authorized source of fixed-troop HP damage")
		if not attackers.is_empty(): check(game._damage_friendly(game.units[0],float(game.units[0].maxHp)*.25,attackers[0])>0, "Native friendly HP loss supplies a real empty-line remainder")
		check(game._damage_enemy(game.enemies[0],float(game.enemies[0].maxHp)*.25,str(game.units[0].type),game.units[0])>0, "Native hostile HP loss supplies a real empty-line remainder")
	root.size=Vector2i(1280,760); root.content_scale_size=root.size
	var frozen: String = JSON.stringify(game.snapshot())
	var pixel_samples: Array = []
	var capture_path: String = ""
	if capture:
		game.queue_redraw(); game.actor_overlay.queue_redraw()
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		capture_path=ProjectSettings.globalize_path("user://healthbars-final.png")
		check(image!=null and image.save_png(capture_path)==OK, "Actual health bar GPU pixels save in the isolated profile")
		for entry in actual_actors:
			var layout: Dictionary = game.healthbar_layout(entry.actor,bool(entry.friendly))
			var sample: Vector2i = Vector2i(layout.fillRect.get_center().floor())
			var actual: Color = image.get_pixelv(sample)
			var expected: Color = Color(str(layout.color))
			check(absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)<.03, "Actual rendered actor HP centre is an opaque green/red fill")
			pixel_samples.append({"friendly":entry.friendly,"type":entry.actor.get("type",entry.actor.get("kind","")),"position":sample,"actualColour":actual.to_html(),"expectedColour":expected.to_html()})
			if float(layout.ratio)<.9:
				var empty_sample: Vector2i=Vector2i(Vector2(layout.rect.end.x-4,layout.rect.get_center().y).floor())
				var empty_actual: Color=image.get_pixelv(empty_sample)
				var empty_expected: Color=Color(str(layout.backgroundColor))
				check(absf(empty_actual.r-empty_expected.r)+absf(empty_actual.g-empty_expected.g)+absf(empty_actual.b-empty_expected.b)<.03, "Actual missing friendly/hostile HP is an opaque dark two-pixel remainder")
		for layout in game.field_marker_layouts():
			if str(layout.marker.markerKind)!="objective": continue
			var actual: Color=image.get_pixelv(Vector2i(layout.healthRect.get_center().floor()))
			check(actual.g>actual.r*1.5 and actual.g>actual.b*1.5, "Actual rendered friendly base HP centre is green")
		var selected_pixel: Color=image.get_pixel(100,25)
		check(absf(selected_pixel.g-fill_style.bg_color.g)<.02 and selected_pixel.g>selected_pixel.r*1.5, "Actual Main-built selected control renders an opaque green pixel")
		var selected_empty: Color=image.get_pixel(245,25)
		check(absf(selected_empty.r-background_style.bg_color.r)+absf(selected_empty.g-background_style.bg_color.g)+absf(selected_empty.b-background_style.bg_color.b)<.03, "Actual selected missing HP is an opaque dark two-pixel remainder")
	check(JSON.stringify(game.snapshot())==frozen, "Actual HP layout/drawing never changes combat state, health or balance")
	selected.free(); app.free(); previous.free(); game.free()
	Battlefield.release_shared_resources()
	for frame in range(4): await process_frame
	var source_after: Dictionary = {}
	for path in source_before: source_after[path]=FileAccess.get_sha256(path)
	check(source_before==source_after, "Health bar QA does not edit any production source/data")
	var report: Dictionary = {"checks":checks,"failures":failures,"pass":failures.is_empty(),"maps":maps.size(),"actualFriendlyTypes":8,"actualHostileTypes":8,"resolutions":3,"baseLayouts":compared_bases,"gpu":capture,"capture":capture_path,"actualFillPixels":pixel_samples,"sourceHashesBefore":source_before,"sourceHashesAfter":source_after,"userData":user_path,"scope":"Actual previous/current common Game HP layouts, actual production/spawned actor states, all forty stage base bars and three resolutions; actual Main-built selected health control styles. GPU mode samples drawing-fixture actor/base/selected pixels. Hostile drawing positions and full unlocked roster are private fixtures. It does not claim a natural battle, final casual-v6 art review or packed execution."}
	var output: FileAccess = FileAccess.open("user://qa_healthbars.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")); output.close()
	print("HEALTHBARS_QA checks=",checks," failures=",failures.size()," gpu=",capture)
	quit(0 if failures.is_empty() else 1)
