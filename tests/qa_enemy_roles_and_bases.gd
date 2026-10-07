extends "res://tests/qa_guard_combat.gd"
## Real Game routes, targeting, paid production and renderer projection. The
## isolated long engagement amplifies HP only to observe commitment, not balance.
const Troops=preload("res://native/troops_3d.gd")
const CameraRig=preload("res://native/battle_camera.gd")
const OUTPUT: String="res://tests/profiles/enemy-roles-and-bases"
var maps: Array=[]
var original_map_sha: String=""

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if DisplayServer.get_name()!="headless" or not profile.begins_with(ProjectSettings.globalize_path(OUTPUT).replace("\\","/").to_lower()+"/"):
		push_error("Role QA requires its isolated headless profile");quit(2);return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var raw: String=FileAccess.get_file_as_string("res://native/maps.json")
	original_map_sha=raw.sha256_text()
	maps=JSON.parse_string(raw)
	print("ROLE_QA captured actual maps=",maps.size()," sha=",original_map_sha)
	if OS.get_cmdline_user_args().has("--camera-only"):
		await camera_and_projection()
		var camera_report: FileAccess=FileAccess.open(OUTPUT+"/camera-results.json",FileAccess.WRITE)
		camera_report.store_string(JSON.stringify({"checks":checks,"failures":failures,"mapsSHA256AtStart":original_map_sha,"observations":observations,"scope":"Bounded final camera.allowZoom and explicit clip, actual HP projection/label bounds at three resolutions."},"\t"));camera_report.close()
		print("ROLE_CAMERA_PATCH_QA checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1);return
	if OS.get_cmdline_user_args().has("--integration-only"):
		await final_integration_patch_contracts()
		var patch_report: FileAccess=FileAccess.open(OUTPUT+"/integration-results.json",FileAccess.WRITE)
		patch_report.store_string(JSON.stringify({"checks":checks,"failures":failures,"mapsSHA256AtStart":original_map_sha,"observations":observations,"scope":"Bounded follow-up after explicit clip binding and real prepared-cover arrival flags. Actual Game+Troops production APIs; no stat/map changes."},"\t"));patch_report.close()
		print("ROLE_INTEGRATION_PATCH_QA checks=",checks," failures=",failures.size())
		quit(0 if failures.is_empty() else 1)
		return
	all_maps_roles_routes_and_markers()
	print("ROLE_QA routes/markers completed checks=",checks," failures=",failures.size())
	actual_target_boundaries()
	normal_contact_120_seconds()
	long_commitment()
	hunter_returns_after_death()
	flank_clock_and_movement()
	water_and_cap_contracts()
	duration_and_dispatch()
	await camera_and_projection()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report: FileAccess=FileAccess.open(OUTPUT+"/results.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"mapsSHA256AtStart":original_map_sha,"observations":observations,"scope":"CPU actual native Game production/HP/movement, 40 captured map geometry, actual Camera3D projection and mesh provider. Long commitment fixture only amplifies HP to observe 120s and does not claim campaign balance. GPU appearance remains root-owned. No source maps/stat/rewards modified by QA."},"\t"));report.close()
	print("ENEMY_ROLES_BASES_QA checks=",checks," failures=",failures.size()," report=",ProjectSettings.globalize_path(OUTPUT+"/results.json"))
	quit(0 if failures.is_empty() else 1)

func dual_fixture() -> Dictionary:
	var data: Dictionary=fixture()
	data.id="enemy-role-commitment-fixture"
	data.cameraEnabled=true
	data.paths=[{"id":"lane0","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.30,"y":.5},{"x":.95,"y":.5}]},{"id":"lane1","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.30,"y":.5},{"x":.65,"y":.32},{"x":.95,"y":.5}]}]
	data.buildZones=[{"id":"wall","x":.50,"y":.65,"r":.16}]
	data.tactics.groundPosts[0].segmentIndex=1
	data.sideAmbushEntrances=[{"id":"south-flank","pathIndex":0,"point":{"x":.35,"y":.83},"connectionPoints":[{"x":.35,"y":.83},{"x":.35,"y":.64},{"x":.35,"y":.5}]}]
	return data

func new_paid_unit(game: Node2D, type_name: String, path_index: int=0, point: Vector2=Vector2(-1,-1)) -> Dictionary:
	if not game.begin_placement(type_name,path_index): check(false,"Native production accepts "+type_name);return {}
	if str(game.placement_contract(type_name).deploymentKind)!="marching":
		if point.x<0:
			for zone in game.zones:
				var hint: Vector2=game._zone_placement_hint(zone,type_name)
				if hint.x>=0 and bool(game.placement_preview(hint).valid): point=hint;break
		if point.x<0 or not game.place_unit(point.x,point.y): game.cancel_recruit();check(false,"Native legal position for "+type_name);return {}
	var job: int=int(game.recruitment_queue[-1].id)
	if not game.running: hold(game)
	for index in range(320):
		game.advance_simulation(.025)
		for unit in game.units:
			if int(unit.get("productionJobId",-1))==job: return unit
	check(false,"Native timer births "+type_name)
	return {}

func all_maps_roles_routes_and_markers() -> void:
	var rows: Array=[]
	check(maps.size()==40,"Exactly 40 authored maps are captured")
	for stage in maps:
		var game: Node2D=game_for({},stage)
		var shared: Vector2=game.paths[0].points[0]
		var branch: Vector2=game.paths[0].points[1]
		var entry_count: int=0
		for path_index in range(game.paths.size()):
			check(game.paths[path_index].points[0].is_equal_approx(shared) and game.paths[path_index].points[1].is_equal_approx(branch),str(stage.id)+" has one normal ingress before branching")
			var entry: Dictionary=game._prepared_ambush_entry(path_index)
			check(not entry.is_empty(),str(stage.id)+" actual side path is land-connected to lane "+str(path_index))
			if not entry.is_empty():
				entry_count+=1
				for index in range(entry.points.size()-1): check(game.ground_combat.land_segment_safe(entry.points[index],entry.points[index+1],.002),"Authored flank uses connected land")
				var flank: Dictionary=game._spawn_enemy("enemy_samurai",3,{"pathIndex":path_index,"ambushEntry":entry})
				check(flank.position.is_equal_approx(entry.points[0]),"Actual hunter births at the authored flank entrance")
				for step in range(1600):
					if not bool(flank.ingressActive): break
					var previous_position: Vector2=flank.position
					game._move_enemy(flank,.025)
					check(game.ground_combat.land_segment_safe(previous_position,flank.position,.002),"Actual all-map hunter moves along legal authored side connections")
					check(flank.position.distance_to(previous_position)<=float(flank.speed)*game._approach_march_factor()*1.6*.025+.00001,"All-map flank ingress never teleports")
				check(not bool(flank.ingressActive) and int(flank.pathIndex)==path_index,"All-map hunter physically completes its selected side route")
				game.enemies.clear()
			var route: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":path_index})
			# River/cyclic source mechanics intentionally choose their active lane.
			var actual_path: int=int(route.pathIndex)
			var previous: float=game.ground_combat.enemy_distance(route)
			var minimum_change: float=0.0
			for step in range(4800):
				if bool(route.escaped): break
				var previous_position: Vector2=route.position
				game._move_enemy(route,.025)
				check(game.ground_combat.land_segment_safe(previous_position,route.position,.002),"Actual ordinary authored route remains on legal land or bridge: "+str(stage.id))
				var current: float=game.ground_combat.enemy_distance(route)
				minimum_change=minf(minimum_change,current-previous)
				check(current>=previous-.00001,"Actual path assault distance never reverses: "+str(stage.id))
				check(int(route.pathIndex)==actual_path and not route.has("threatAnchor") and int(route.get("stationaryTargetId",-1))<0,"Path assault never changes branch or hunts a fixed emplacement")
				previous=current
			check(previous>.05 and str(route.combatRole)=="path_assault","Actual normal enemy advances on its lane")
			game.enemies.clear()
		for kind in ["enemy_archer","enemy_gunner","enemy_samurai"]:
			var early: Array=["archer","spear"]
			game.configure_roster(catalog,early,{})
			var underlying: String={"enemy_archer":"raider","enemy_gunner":"shield","enemy_samurai":"heavy"}[kind]
			var original: Dictionary=game._spawn_enemy(underlying,3,{"pathIndex":0})
			var converted: Dictionary=game._spawn_enemy(str(kind),3,{"pathIndex":0,"fortification":true})
			check(str(converted.kind)==underlying and str(converted.combatRole)=="path_assault" and not converted.fortification,"Guard-locked campaign never spawns a hunter role")
			for stat in ["hp","maxHp","speed","armor","damage","reward"]: check(converted[stat]==original[stat],"Hunter fallback preserves original "+stat)
			game.configure_roster(catalog,Types,{})
			var hunter: Dictionary=game._spawn_enemy(str(kind),3,{"pathIndex":0})
			check(str(hunter.combatRole)=="emplacement_assault" and str(hunter.roleMarker)=="target","Existing hunter kind has a visible distinct role")
			game.enemies.clear()
		for viewport_size in [Vector2(1280,650),Vector2(1440,750),Vector2(1920,920)]:
			game.set_field_rect(Rect2(Vector2.ZERO,viewport_size))
			var labels: Array=[]
			for layout in game.field_marker_layouts():
				var marker: Dictionary=layout.marker
				check(layout.center.is_equal_approx(Vector2(float(marker.x),float(marker.y))*viewport_size),"Base/objective visible center equals actual simulation anchor")
				check(game.field_rect.encloses(layout.labelRect) and int(layout.fontSize)>=18,"Marker actual label glyph rectangle stays in the battlefield")
				var footprint: Rect2=layout.labelRect
				if str(marker.markerKind)=="objective":
					check(float(layout.healthRect.size.y)==10 and game.field_rect.encloses(layout.healthRect),"Objective health has a readable 8px fill and a base name without HP numbers")
					footprint=footprint.merge(layout.healthRect)
				for occupied in labels: check(not footprint.intersects(occupied),str(stage.id)+" distinct anchor labels do not overlap")
				labels.append(footprint)
				check(str(marker.archetype) in ["castle_gate","barracks","command_post"],"Every actual base has a clear model archetype")
		rows.append({"id":stage.id,"lanes":game.paths.size(),"validFlanks":entry_count,"markerCount":game.field_markers().size()})
		game.free()
	observations["maps"]=rows

func actual_target_boundaries() -> void:
	var game: Node2D=game_for({},dual_fixture())
	var archer: Dictionary=new_paid_unit(game,"archer",0,Vector2(.46,.64))
	var gunner: Dictionary=new_paid_unit(game,"gunner",0,Vector2(.50,.50))
	var guard: Dictionary=new_paid_unit(game,"naginata",0,Vector2(.57,.50))
	var spear: Dictionary=new_paid_unit(game,"spear",0)
	if archer.is_empty() or gunner.is_empty() or guard.is_empty() or spear.is_empty(): game.free();return
	for unit in game.units: unit.cooldown=1000
	var path_enemy: Dictionary=enemy_at(game,spear.position+Vector2(-.02,0),"heavy",true)
	var before: float=float(spear.hp)
	check(game._damage_friendly(spear,10,path_enemy)>0 and float(spear.hp)<before,"Path assault causes actual native HP damage to same-lane marching troops")
	var other_lane: Dictionary=path_enemy.duplicate(true);other_lane.pathIndex=1
	check(game._damage_friendly(spear,10,other_lane)==0,"Path assault cannot hit another lane's marching troop")
	for unit in [archer,gunner]:
		var health: float=float(unit.hp)
		path_enemy.position=unit.position+Vector2(-.02,0)
		check(not game.can_enemy_engage_unit(path_enemy,unit,true) and game._damage_friendly(unit,10,path_enemy)==0 and float(unit.hp)==health,"Normal route enemies never acquire or damage fixed ranged emplacements")
	path_enemy.position=guard.position+Vector2(-.02,0)
	check(game.can_enemy_engage_unit(path_enemy,guard,true) and game._damage_friendly(guard,10,path_enemy)>0,"A physically contacting same-lane guard receives native retaliation")
	path_enemy.position=guard.position+Vector2(-.08,0)
	check(not game.can_enemy_engage_unit(path_enemy,guard,true),"A path enemy never follows a distant guard home")
	var hunter: Dictionary=enemy_at(game,archer.position+Vector2(-.08,0),"enemy_gunner",true)
	var fixed_health: float=float(archer.hp)
	check(game._damage_friendly(archer,10,hunter)>0 and float(archer.hp)<fixed_health,"Unlocked actual hunter damages the fixed emplacement")
	game.configure_roster(catalog,["archer","spear"],{})
	var protected_hp: float=float(archer.hp)
	hunter.rangedPlan={"targetId":int(archer.id),"releaseTime":.25,"damage":9};hunter.animationClock=.30
	game._enemy_ranged_step(hunter,.025)
	check(hunter.rangedPlan.is_empty() and game.projectiles.is_empty(),"Early safety is checked again at actual ranged release")
	game.projectiles.append({"position":archer.position,"targetPos":archer.position,"targetId":int(archer.id),"damage":9.0,"type":"enemy_gunner","victimSide":"friendly","sourceId":int(hunter.id),"sourceActor":hunter.duplicate(true),"speed":2.7,"age":0.0})
	game._update_projectiles(.025)
	check(game.projectiles.is_empty() and float(archer.hp)==protected_hp,"Early safety also holds at projectile impact and common HP boundary")
	game.free()

func normal_contact_120_seconds() -> void:
	var game: Node2D=game_for({},dual_fixture())
	var first: Dictionary=new_paid_unit(game,"archer",0,Vector2(.46,.64))
	var second: Dictionary=new_paid_unit(game,"archer",0,Vector2(.58,.64))
	var left: Dictionary=new_paid_unit(game,"spear",0)
	var right: Dictionary=new_paid_unit(game,"spear",1)
	if first.is_empty() or second.is_empty() or left.is_empty() or right.is_empty(): game.free();return
	for unit in game.units: unit.hp=20000;unit.maxHp=20000
	var sources: Array=[]
	for lane in [0,1]:
		var enemy: Dictionary=game._spawn_enemy("heavy",3,{"pathIndex":lane})
		enemy.position=game.ground_combat.route_point(lane,.5);enemy.pointIndex=2;enemy.hp=50000;enemy.maxHp=50000
		sources.append(enemy)
	var distances: Array=[game.ground_combat.enemy_distance(sources[0]),game.ground_combat.enemy_distance(sources[1])]
	var maximum_turn: float=0.0
	for index in range(4800):
		var previous_aims: Array=[sources[0].aim,sources[1].aim]
		game.advance_simulation(.025)
		for lane in [0,1]:
			var enemy: Dictionary=sources[lane]
			var progress: float=game.ground_combat.enemy_distance(enemy)
			check(progress>=float(distances[lane])-.00001 and int(enemy.pathIndex)==lane,"120s contact battle keeps the actual path assault progress and branch")
			distances[lane]=progress
			check(not enemy.has("threatAnchor") and int(enemy.get("stationaryTargetId",-1))<0,"120s path attackers never hunt the two visible towers")
			maximum_turn=maxf(maximum_turn,absf(previous_aims[lane].angle_to(enemy.aim)))
	check(float(first.hp)==20000 and float(second.hp)==20000,"Both actual fixed emplacements remain unharmed by normal enemies for 120s")
	check(float(left.hp)<20000 and float(right.hp)<20000,"The same normal enemies actually damage both same-path marching soldiers")
	check(maximum_turn<=.2001,"Normal contact combat also bounds its native yaw without 180-degree jitter")
	observations["normalContact120Seconds"]={"seconds":120,"towerHP":[first.hp,second.hp],"marchingHP":[left.hp,right.hp],"pathDistances":distances,"maximumPerTickTurn":maximum_turn}
	game.free()

func long_commitment() -> void:
	var rows: Array=[]
	for kind in ["enemy_samurai","enemy_archer","enemy_gunner"]:
		var game: Node2D=game_for({},dual_fixture())
		var first: Dictionary=new_paid_unit(game,"archer",0,Vector2(.46,.64))
		var second: Dictionary=new_paid_unit(game,"archer",0,Vector2(.58,.64))
		var left: Dictionary=new_paid_unit(game,"spear",0)
		var right: Dictionary=new_paid_unit(game,"spear",1)
		if first.is_empty() or second.is_empty() or left.is_empty() or right.is_empty(): game.free();continue
		for unit in game.units: unit.hp=20000;unit.maxHp=20000
		var enemy: Dictionary=enemy_at(game,Vector2(.49,.50),str(kind));enemy.hp=50000;enemy.maxHp=50000
		var commitments: Array=[]
		var target: int=-1
		var jitter: int=0
		var decreases: int=0
		var previous_progress: float=0
		var max_turn: float=0.0
		var initial_hp: float=float(first.hp)+float(second.hp)
		for index in range(4800):
			var previous_aim: Vector2=enemy.aim
			game.advance_simulation(.025)
			var angle: float=absf(previous_aim.angle_to(enemy.aim));max_turn=maxf(max_turn,angle)
			if angle>PI*.75: jitter+=1
			if float(enemy.routeProgress)<previous_progress-.00001: decreases+=1
			previous_progress=float(enemy.routeProgress)
			var current: int=int(enemy.get("stationaryTargetId",-1))
			if current!=target:
				commitments.append({"t":game.elapsed,"from":target,"to":current})
				if target>=0 and index<2400: check(false,"Living reachable tower commitment changed before 60s")
				target=current
			if index==2400:
				var current_unit: Dictionary=game.ground_combat._unit(current)
				if not current_unit.is_empty(): current_unit.hp=0
			check(game.ground_combat.land_segment_safe(enemy.position,enemy.position,0),"Actual hunter remains on legal land throughout 120s")
		check(jitter==0 and max_turn<=.2001,"Hunter facing cannot snap 180 degrees on consecutive native ticks")
		check(decreases==0,"Hunter's committed route progress never regresses")
		check(commitments.size()>=2 and commitments.size()<=5 and int(commitments[1].to)==-1,"Hunter keeps its living tower then releases it immediately after actual death, including while physically blocked")
		check(float(first.hp)+float(second.hp)<initial_hp,"Actual committed hunting produces real fixed-troop HP loss")
		rows.append({"kind":kind,"seconds":120,"commitments":commitments,"facing180Jitter":jitter,"maximumPerTickTurn":max_turn,"routeProgressDecreases":decreases,"friendlyHPAfter":[first.hp,second.hp],"movingFriendPositions":[game._normalized_position(left.position),game._normalized_position(right.position)]})
		game.free()
	observations["commitment120Seconds"]=rows

func hunter_returns_after_death() -> void:
	var game: Node2D=game_for({},dual_fixture())
	var first: Dictionary=new_paid_unit(game,"archer",0,Vector2(.46,.64))
	var second: Dictionary=new_paid_unit(game,"archer",0,Vector2(.58,.64))
	if first.is_empty() or second.is_empty(): game.free();return
	for unit in game.units: unit.hp=20000;unit.maxHp=20000
	var hunter: Dictionary=enemy_at(game,Vector2(.49,.50),"enemy_samurai");hunter.hp=50000;hunter.maxHp=50000
	tick(game,2)
	var target: Dictionary=game.ground_combat._unit(int(hunter.get("stationaryTargetId",-1)))
	check(not target.is_empty(),"Native unblocked hunter commits to a real tower")
	if target.is_empty(): game.free();return
	var lower: float=float(hunter.pursuitRouteDistance)
	game._damage_friendly(target,100000,hunter)
	var returned: bool=false
	for index in range(1200):
		game.advance_simulation(.025)
		if bool(hunter.get("hunterReturning",false)):
			returned=true
			check(float(hunter.resumeDistance)>=lower-.00001,"Hunter return connects to its existing forward route instead of previous waypoints")
		if int(hunter.get("stationaryTargetId",-1))==int(second.id): break
	check(returned and int(hunter.get("stationaryTargetId",-1))==int(second.id),"After real target death, unblocked hunter physically returns then acquires the surviving tower")
	game.free()

func flank_clock_and_movement() -> void:
	var game: Node2D=game_for({},dual_fixture());hold(game)
	var events: Array=[]
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	game._queue_enemy_spawn("enemy_samurai",3,{"pathIndex":0,"originKind":"heavy"})
	check(game.enemies.is_empty() and game.ambush_warnings.size()==1,"Actual hunter emits a warning before becoming a soldier")
	game.paused=true;game.advance_simulation(9)
	check(float(game.ambush_warnings[0].remainingSeconds)==2.0,"Pause freezes the two-second flank warning")
	game.paused=false;game.between_waves=true;game.advance_simulation(9)
	check(float(game.ambush_warnings[0].remainingSeconds)==2.0,"Study also freezes the flank warning")
	game.between_waves=false;tick(game,1.975)
	check(game.enemies.is_empty() and game.ambush_warnings.size()==1,"No flank soldier appears before the full 2s warning")
	game.advance_simulation(.025)
	check(game.enemies.size()==1 and game.ambush_warnings.is_empty(),"The warned hunter is created exactly once at 2s")
	if not game.enemies.is_empty():
		var enemy: Dictionary=game.enemies[0]
		check(bool(enemy.ingressActive) and str(enemy.ambushEntranceId)=="south-flank","Hunter begins at its visible authored side entrance")
		var start: Vector2=Vector2(.35,.83)
		check(enemy.position.distance_to(start)<=float(enemy.speed)*game._approach_march_factor()*1.6*.026,"The first ingress position moves from the entry rather than teleporting to a tower")
		var ingress_speed: float=0.0
		var previous: Vector2=enemy.position
		for index in range(700):
			if not bool(enemy.ingressActive): break
			game.advance_simulation(.025)
			var distance: float=enemy.position.distance_to(previous)
			ingress_speed=maxf(ingress_speed,distance/.025)
			check(distance<=float(enemy.speed)*game._approach_march_factor()*1.6*.025+.00001 and game.ground_combat.land_segment_safe(previous,enemy.position,.002),"Flank movement is continuous along legal authored land")
			previous=enemy.position
		check(not bool(enemy.ingressActive),"Actual hunter physically reaches its route connection")
		game.advance_simulation(.025)
		var ordinary_speed: float=enemy.position.distance_to(previous)/.025
		check(ingress_speed>ordinary_speed*1.4 and ordinary_speed<=float(enemy.speed)*game._approach_march_factor()+.0001,"Ingress speed boost ends at the route; combat speed is preserved")
		observations["flank"]={"warning":2,"birthClock":2,"ingressSpeed":ingress_speed,"routeSpeed":ordinary_speed,"position":game._normalized_position(enemy.position)}
	check(events.filter(func(e: Dictionary):return str(e.type)=="ambush_warning").size()==1,"The native warning event is emitted once")
	game.free()
	var blocked_data: Dictionary=dual_fixture();blocked_data.water={"x":.30,"y":.62,"w":.10,"h":.03}
	var blocked: Node2D=game_for({},blocked_data);hold(blocked)
	blocked._queue_enemy_spawn("enemy_samurai",3,{"pathIndex":0,"originKind":"heavy"})
	check(blocked.ambush_warnings.is_empty() and blocked.enemies.size()==1 and str(blocked.enemies[0].kind)=="heavy","Unsafe side geometry falls back to its original soldier instead of crossing water")
	blocked.free()

func water_and_cap_contracts() -> void:
	for kind in ["river","stream","lake","wetland_lake","wetland"]:
		var data: Dictionary=dual_fixture()
		data.historicalBattlefield={"waterFeatures":[{"kind":kind,"x":.30,"y":.62,"w":.1,"h":.03,"blocksMovement":kind!="wetland"}]}
		var game: Node2D=game_for({},data)
		check(game.ground_combat.land_segment_safe(Vector2(.35,.80),Vector2(.35,.50),.002)==(kind=="wetland"),"Actual visible "+kind+" obeys shared renderer/combat water semantics")
		check(game._prepared_ambush_entry(0).is_empty()==(kind!="wetland"),"A hunter cannot use an authored connection through actual "+kind)
		game.free()
	var cap_rows: Array=[]
	for window in [1,20]:
		var game: Node2D=game_for({},dual_fixture());game.load_map(dual_fixture(),10);hold(game)
		game.wave=window
		game.elapsed=float(game._timed_wave().startSeconds)
		var cap: int=int(game._timed_wave().activeCap)
		check(cap==(8 if window==1 else 36),"Actual first/late windows retain their small opening and 36-enemy maximum")
		for index in range(cap):
			var enemy: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":0});enemy.speed=0
		game._queue_enemy_spawn("enemy_samurai",3,{"pathIndex":0,"originKind":"heavy"})
		tick(game,2.5)
		check(game.enemies.size()==cap and game.ambush_warnings.size()==1 and float(game.ambush_warnings[0].remainingSeconds)==0,"Due flank spawn waits at its actual window cap")
		game.enemies[0].hp=0;tick(game,.05)
		check(game.enemies.size()==cap and game.ambush_warnings.is_empty(),"An actual removal frees exactly one capped flank birth without a spawn burst")
		cap_rows.append({"window":window,"activeCap":cap,"afterActualRemoval":game.enemies.size()})
		game.load_map(dual_fixture(),10)
		check(game.ambush_warnings.is_empty(),"Map/reset cannot retain old flank warnings")
		game.free()
	observations["flankCaps"]=cap_rows

func duration_and_dispatch() -> void:
	var stage: Dictionary=maps[0]
	var game: Node2D=game_for({},stage)
	game.configure_roster(catalog,["archer","spear"],{})
	game.load_map(stage,10)
	check(game.gold==280 and game.battle_minutes==10,"Actual first map starts at authored 280 combat gold in 10m mode")
	check(game.begin_placement("spear",0) and game.begin_placement("spear",1),"Actual first map card API creates paid parallel marching orders")
	check(game.pending.is_empty() and game.gold==150 and game.recruitment_queue.size()==2,"Marching recruitment needs no cursor and pays actual 65 twice")
	hold(game);tick(game,2.25)
	check(game.units.is_empty(),"Both actual spear timers remain pending before 2.275s")
	game.advance_simulation(.025)
	check(game.units.size()==2 and game.recruitment_queue.is_empty(),"Two real beginner spears appear when parallel production finishes")
	for unit in game.units:
		var spawn: Vector2=unit.spawnPosition
		var base: Dictionary=game.ground_combat._base_for_path(int(unit.postPathIndex))
		check(spawn.is_equal_approx(base.position),"Actual birth coordinates coincide with the marked marching base")
	tick(game,6)
	for unit in game.units: check(unit.position.distance_to(unit.spawnPosition)>.025 and str(unit.animation)=="walk","New troops physically leave their base after gathering")
	for requested in [1.0,2.0,3.0,-2.0]:
		game.set_speed(requested)
		check(game.speed==(2.0 if requested>=2 else 1.0),"Public speed API only exposes 1x or 2x")
		var before: float=game.elapsed;game._process(.1)
		check(absf(game.elapsed-before-.1*game.speed)<.00001,"Native frame clock respects the admitted speed")
	game.paused=true;var frozen: float=game.elapsed;game._process(.25);check(game.elapsed==frozen,"Pause excludes battle clock")
	game.paused=false;game.between_waves=true;game._process(.25);check(game.elapsed==frozen,"Study excludes battle clock")
	for minutes in [0,5,10,20]:
		game.load_map(stage,minutes)
		check(game.battle_minutes==(0 if minutes==0 else 20 if minutes==20 else 10),"10/20 public duration and explicit internal legacy0 are retained")
	observations["starterDispatch"]={"initialGold":280,"orderCostEach":65,"goldAfter":150,"born":2,"birthSeconds":2.275,"scope":"Production and movement only; no full-campaign victory claim."}
	game.free()

func camera_and_projection() -> void:
	var clip: Control=Control.new();clip.position=Vector2(70,90);clip.size=Vector2(1160,620);clip.clip_contents=true;root.add_child(clip)
	var content: Control=Control.new();clip.add_child(content);content.size=clip.size
	var rig: Node=CameraRig.new();root.add_child(rig);rig.configure(clip,content,dual_fixture())
	var game: Node2D=game_for({},dual_fixture());root.remove_child(game);content.add_child(game);game.set_field_rect(Rect2(Vector2.ZERO,clip.size))
	game.set_input_clip(clip)
	var renderer: Control=Troops.new();content.add_child(renderer);renderer.set_process(false);renderer.set_field_size(clip.size);renderer.set_stage(maps[0]);renderer.bind_battle(game);game.three_d_enabled=true
	await process_frame
	var far: Vector2=rig.clip_to_screen(clip.size*.5)
	check(rig.zoom_at(far,1.6) and absf(rig.zoom-1.6)<.00001,"Shared camera zoom is clamped to 1.6")
	rig.pan_by_clip_delta(Vector2(-9000,9000))
	check(rig.pan.x>=-clip.size.x*.6-.001 and rig.pan.y==0,"Camera cannot expose space beyond a map edge")
	for point in [Vector2(.1,.2),Vector2(.5,.5),Vector2(.8,.9)]:
		var screen: Vector2=game.field_point_to_screen(point)
		check(game.screen_to_field_point(screen).distance_to(point)<.000001,"Actual Game input reverses the shared camera transform")
		check(rig.screen_to_content(rig.content_to_screen(point*clip.size)).distance_to(point*clip.size)<.0001,"Camera coordinate API round-trips under pan/zoom")
	rig.reset();rig.set_zoom(1.35)
	check(game.begin_placement("archer"),"Camera placement uses the actual paid-card backend")
	var hint: Vector2=game._zone_placement_hint(game.zones[0],"archer")
	var click: InputEventMouseButton=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=game.field_point_to_screen(hint)
	game._unhandled_input(click)
	check(game.recruitment_queue.size()==1 and game.recruitment_queue[0].position.distance_to(hint)<.000001,"Zoomed actual click reserves the exact displayed firing point")
	check(game.begin_placement("archer"),"A second placement cursor starts normally")
	var previous_orders: int=game.recruitment_queue.size();click.position=clip.position+Vector2(-10,clip.size.y*.5)
	clip.clip_contents=false
	check(game.field_rect.has_point(game.screen_to_local_point(click.position)) and not game.screen_point_in_field(click.position),"Explicit fixed clip rejects an otherwise-valid logical point even without ancestor clipping")
	game._unhandled_input(click)
	clip.clip_contents=true
	check(game.recruitment_queue.size()==previous_orders and not game.pending.is_empty(),"Clipped outside-field pixels cannot recruit a soldier")
	game.cancel_recruit();hold(game);tick(game,3)
	game.selected_id=-1;click.position=game.field_point_to_screen(game.units[0].position);game._unhandled_input(click)
	check(game.selected_id==int(game.units[0].id),"Actual unit selection uses the same zoomed screen inverse as recruitment")
	var enemy: Dictionary=enemy_at(game,Vector2(.40,.40),"raider",true)
	for viewport_size in [Vector2(1280,650),Vector2(1440,750),Vector2(1920,920)]:
		rig.reset();clip.size=viewport_size;rig.configure(clip,content,dual_fixture());game.set_field_rect(Rect2(Vector2.ZERO,viewport_size));renderer.set_field_size(viewport_size)
		for point in [Vector2(.12,.20),Vector2(.40,.45),Vector2(.70,.58),Vector2(.90,.80)]:
			var world_point: Vector3=renderer.normalized_to_world(point)
			var actual: Vector2=renderer.camera.unproject_position(world_point)
			check(actual.distance_to(point*viewport_size)<.5,"Height-corrected native world feet project to the actual normalized gameplay point")
			check(absf(world_point.y-renderer.battlefield.height_at(point))<.000001,"Actor foot uses the provider's real terrain height")
		renderer.sync_actor_states(game.actor_states())
		for source in game.units+[enemy]:
			var anchor: Dictionary=renderer.health_anchor_for(int(source.id))
			var layout: Dictionary=game.healthbar_layout(source,source.has("type"))
			check(not anchor.is_empty() and bool(layout.projected),"Friendly and hostile health use actual 3D head projection")
			check(layout.anchor.distance_to(anchor.headPosition)<.001 and layout.fillRect.size.y==8 and str(layout.text).is_empty(),"Number-free HP bar center follows the rendered head")
			var key: String=str(source.id)+":0"
			var actor: Node3D=renderer.actors[key]
			var shadow: Node3D=renderer.contact_shadows[key]
			check(absf(shadow.position.y-actor.position.y-.002)<.00001,"Contact shadow uses the same terrain surface plus .002")
			check(actor.position.x==shadow.position.x and actor.position.z==shadow.position.z,"Actor and contact shadow have the same actual foot anchor")
			if source.has("type"):
				var name_layout: Dictionary=game.selected_unit_label_layout(source)
				var number_rect: Rect2=layout.rect.grow(2)
				check(game.visible_field_rect_local().encloses(name_layout.rect) and not name_layout.rect.intersects(number_rect),"Actual selected Japanese/ruby glyphs remain visible without covering the number-free HP bar")
				check(name_layout.fontSize==20 and name_layout.readingSize==16,"Japanese glyphs and reading retain their existing readable sizes")
		var rebuild: int=renderer.battlefield.rebuild_count;renderer.set_field_size(viewport_size);renderer.set_stage(maps[0]);check(renderer.battlefield.rebuild_count==rebuild,"Unchanged field size/stage does not duplicate terrain rebuilds")
		for stage in maps:
			var source: Dictionary={"id":9000,"kind":"raider","type":"enemy_light","friendly":false,"x":float(stage.paths[0].points[0].x),"y":float(stage.paths[0].points[0].y),"aimX":1.0,"aimY":0.0,"animation":"walk","animationClock":0.0,"motionTime":0.0,"hp":42.0,"maxHp":42.0}
			renderer.sync_actor_states([source])
			var raw_actor: Dictionary={"id":9000,"kind":"raider","position":Vector2(source.x,source.y),"hp":42.0,"maxHp":42.0}
			var bar: Dictionary=game.healthbar_layout(raw_actor,false)
			check(game.visible_field_rect_local().encloses(bar.rect),"All-map normal entry keeps its actual health bar inside the visible battlefield")
			check(str(bar.text).is_empty() and bar.fillRect.size.y==8,"All-map HP bars retain a readable fill without numeric captions")
			var name_probe: Dictionary=raw_actor.duplicate();name_probe.type="spear";name_probe.jp="槍兵";name_probe.reading="やりへい"
			var name_layout: Dictionary=game.selected_unit_label_layout(name_probe)
			var hp_bounds: Rect2=bar.rect.grow(2)
			check(game.visible_field_rect_local().encloses(name_layout.rect) and not name_layout.rect.intersects(hp_bounds),"Entry-edge selected Japanese text and HP occupy different readable rectangles")
	var diagnostics: Dictionary=renderer.diagnostics()
	check(is_equal_approx(renderer.sun.shadow_bias,.10) and is_equal_approx(renderer.sun.shadow_normal_bias,.80) and is_equal_approx(renderer.sun.directional_shadow_fade_start,1.0),"Actual native shared sun has the GPU-reviewed acne correction")
	var rendered: bool=str(renderer.render_layer.get("mode","native"))=="rendered"
	var chosen_lighting: Dictionary=renderer.render_layer.get("lighting",{})
	check(is_equal_approx(renderer.sun.light_energy,float(chosen_lighting.get("keyEnergy",1.45))) and is_equal_approx(renderer.environment.ambient_light_energy,float(chosen_lighting.get("ambientEnergy",.32))),"Actual terrain/actor lighting follows the approved artwork profile or native daylight fallback")
	check(bool(diagnostics.nativeBattlefield) and not bool(diagnostics.photoGround) and diagnostics.worldWidth==18.5 and bool(diagnostics.lightField.get("available",false))==rendered,"Real height terrain is preserved, with local artwork illumination only when a render exists")

	observations["renderer"]={"worldWidth":diagnostics.worldWidth,"photoGround":diagnostics.photoGround,"localLightUpdates":diagnostics.localLightUpdates,"terrain":diagnostics.terrain,"healthFillPixels":8,"testedViewports":[1280,1440,1920]}
	for stage in maps:
		rig.configure(clip,content,stage)
		check(rig.enabled==bool(stage.get("camera",{}).get("allowZoom",false)),"Every real authored map camera.allowZoom controls zoom availability")
	for stage in maps:
		if str(stage.historicalBattlefield.get("timeOfDay",""))=="night":
			renderer.set_stage(stage)
			check(is_equal_approx(renderer.sun.light_energy,.55) and is_equal_approx(renderer.environment.ambient_light_energy,.35),"Actual historical night changes the shared native lighting regardless of the legacy theme")
		elif str(stage.historicalBattlefield.get("weather",{}).get("key",""))=="rain_clouds_wet_ground_reported":
			renderer.set_stage(stage)
			check(is_equal_approx(renderer.sun.light_energy,1.45*.85) and is_equal_approx(renderer.environment.ambient_light_energy,.32*.85),"Recorded rain/clouds darkens actors and physical terrain together")
	var narrow: Dictionary=dual_fixture();narrow.cameraEnabled=false;rig.configure(clip,content,narrow)
	check(not rig.enabled and rig.zoom==1 and rig.pan==Vector2.ZERO and not rig.set_zoom(1.4),"Close battle maps remain at a fixed camera unless explicitly enabled")
	rig.free();clip.free()

func final_integration_patch_contracts() -> void:
	var rows: Array=[]
	for stage in maps:
		if int(stage.stageNumber)<15: continue
		var game: Node2D=Battle.new()
		game.three_d_enabled=true
		root.add_child(game);game.set_process(false);game.configure_roster(catalog,Types,{});game.load_map(stage)
		check(game.background==null,"Native 3D map load does not load an old background photograph")
		game.load_map(stage,10)
		check(game.background==null,"Explicit native map reload skips photograph resource lookup")
		var renderer: Control=Troops.new();root.add_child(renderer);renderer.set_process(false);renderer.set_stage(stage);renderer.bind_battle(game)
		await process_frame
		for lane in range(game.paths.size()):
			var entry: Dictionary=game._prepared_ambush_entry(lane)
			if entry.is_empty(): check(false,"Final captured lane has a real side connection");continue
			var enemy: Dictionary=game._spawn_enemy("enemy_archer",3,{"pathIndex":lane,"fortification":true,"ambushEntry":entry})
			var planned: bool=bool(enemy.get("stationaryAfterIngress",false))
			check(bool(enemy.ingressActive) and not bool(enemy.fortification) and not bool(enemy.stationaryEnemy),"Walking crew is not a moving firing cover or premature assassination target")
			renderer.sync_actor_states(game.actor_states())
			check(not renderer.fortifications.has(str(enemy.id)+":0"),"Actual renderer creates no sliding bunker during side ingress")
			for index in range(8000):
				if not bool(enemy.ingressActive): break
				var previous: Vector2=enemy.position
				game._enemy_ingress_step(enemy,.025)
				check(game.ground_combat.land_segment_safe(previous,enemy.position,.002),"Prepared-cover crew follows the actual connected side road and authored route")
				check(enemy.position.distance_to(previous)<=float(enemy.speed)*game._approach_march_factor()*1.6*.025+.00001,"Cover crew reaches its post without teleporting")
			check(not bool(enemy.ingressActive),"Actual crew finishes the connected arrival route")
			check(bool(enemy.fortification)==planned and bool(enemy.stationaryEnemy)==planned,"Stationary firing role becomes active only at the final paid-free enemy spawn position")
			if planned:
				check(enemy.position.is_equal_approx(enemy.fortificationPosition),"Prepared cover and arrived crew share their original stationary position")
				renderer.sync_actor_states(game.actor_states())
				var key: String=str(enemy.id)+":0"
				check(renderer.fortifications.has(key),"Actual 3D prepared cover appears after the crew arrives")
				if renderer.fortifications.has(key):
					var prop: Node3D=renderer.fortifications[key]
					check(prop.position.distance_to(renderer.normalized_to_world(enemy.position))<.0001,"The firing cover uses the same terrain foot height as its crew")
			rows.append({"map":stage.id,"lane":lane,"preparedCover":planned,"ingressComplete":not enemy.ingressActive})
			game.enemies.clear()
		renderer.free();game.free()
	observations["preparedCoverArrival"]=rows
	await camera_and_projection()
