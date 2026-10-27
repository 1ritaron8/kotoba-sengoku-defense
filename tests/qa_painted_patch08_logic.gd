extends SceneTree
## Controlled component fixtures. No Main, rendered input, natural economy or saves.
const Battle = preload("res://native/game.gd")
const OUTPUT: String="res://tests/profiles/painted-patch-08/logic-report.json"
var catalog: Array=[]
var checks: Array=[]
var failures: Array=[]
var evidence: Dictionary={}
var sources: Dictionary={}
var started: int=0
var completed: bool=false

func _initialize() -> void: call_deferred("run")

func check(ok: bool, note: String) -> bool:
	checks.append({"pass":ok,"note":note})
	if not ok: failures.append(note);push_error("PATCH08_LOGIC "+note)
	return ok

func source_hashes() -> Dictionary:
	var result: Dictionary={}
	for path in ["res://native/game.gd","res://native/ground_combat.gd","res://native/crowd_melee.gd","res://native/painted_actor_renderer.gd","res://native/units.json","res://tests/qa_painted_patch08_logic.gd"]:
		result[path]=FileAccess.get_sha256(path)
	return result

func flat_map() -> Dictionary:
	return {"id":"patch08-flat-fixture","stageNumber":1,"theme":"forest","trainingOnly":true,"initialGold":10000,"totalWaves":20,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.10,"y":.5},{"x":.90,"y":.5}]}],"objectives":[{"id":"main","x":.90,"y":.5,"hp":1000}],"buildZones":[{"id":"post","x":.50,"y":.62,"r":.024,"guardRadius":.20,"slotCapacity":2,"slotPositions":[{"x":.487,"y":.62},{"x":.513,"y":.62}],"acceptedUnitTypes":["archer","gunner"]}],"tactics":{"groundPosts":[]}}

func make_game(levels: Dictionary={}) -> Node2D:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	var unlocked: Array=[]
	for definition in catalog:
		if bool(definition.get("active",true)): unlocked.append(str(definition.id))
	game.configure_roster(catalog,unlocked,levels)
	game.load_map(flat_map())
	game.set_seed(9876)
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear()
	game.spawn_clock=10000.0
	return game

func wallet_state(game: Node2D) -> Dictionary:
	return {"gold":game.gold,"actorId":game.next_id,"jobId":game.next_recruitment_id,"cursor":game.ground_combat.march_path_cursor,"pending":game.pending.duplicate(true),"queue":game.recruitment_queue.duplicate(true)}

func hostile(game: Node2D, point: Vector2, kind: String="raider") -> Dictionary:
	var enemy: Dictionary=game._spawn_enemy(kind,1,{"originKind":"raider","pathIndex":0})
	enemy.position=point
	enemy.pointIndex=1
	enemy.routeProgress=maxf(0.0,point.x-.1)
	enemy.ingressActive=false
	return enemy

func base_orders() -> void:
	var rows: Array=[]
	for level in [1,4,8]:
		var expected: int={1:1,4:3,8:5}[level]
		var game: Node2D=make_game({"spear":level})
		var base: Dictionary=game.ground_combat.select_march_base(0)
		var gold: int=game.gold
		if not check(game.begin_placement("spear",0),"Card backend queues one base order at spear level "+str(level)): game.free();continue
		check(game.recruitment_queue.size()==1 and game.gold==gold-game.recruit_cost("spear"),"One card action spends exactly one order")
		check(game.select_deployment("spear"),"Sticky selection restored after paid card action")
		var before: Dictionary=wallet_state(game)
		for unused in range(20):
			game.marching_support_areas("spear",0)
			game.deployment_preview("spear",Vector2(.22,.22),"lane")
		check(wallet_state(game)==before,"Repeated support geometry and previews do not mutate payment, IDs, queue, selection or route cursor")
		var job: Dictionary=game.recruitment_queue[0]
		check(job.position==base.position and not job.destination.has("dispatchOrigin"),"Card production origin is the actual selected base")
		game._advance_recruitment(10.0)
		check(game.units.size()==expected,"Completed spear order creates "+str(expected)+" independent members")
		var positions: Dictionary={}
		for unit in game.units:
			positions[int(unit.id)]=unit.position
			check(str(unit.combatState)=="march" and float(unit.get("gatherRemaining",0.0))==0.0 and str(unit.get("supportPhase",""))=="","Base spear has no support/gather wait")
		game.ground_combat.step(.025)
		for unit in game.units:
			check(unit.position.distance_to(positions[int(unit.id)])>.000001,"Each paid member actually moves on the first ground step")
		rows.append({"level":level,"quantity":game.units.size(),"base":base.position,"positionsBefore":positions})
		game.free()
	var field: Node2D=make_game()
	var requested: Vector2=Vector2(.22,.22)
	var result: Dictionary=field.submit_deployment("spear",requested,"lane")
	check(bool(result.get("ok",false)) and str(result.get("placementMode",""))=="base_march","Ordinary field spear click selects base production")
	if not field.recruitment_queue.is_empty():
		var job: Dictionary=field.recruitment_queue[0]
		check(job.position==field.ground_combat.select_march_base(0).position and job.position.distance_to(requested)>.1,"Ordinary field click cannot relocate the spear birth origin")
	check(str(field.deployment_preview("samurai",Vector2(.30,.50),"lane").get("placementMode",""))=="field_march","Samurai field-dispatch semantics remain available")
	evidence["baseOrders"]={"fixture":"Flat test map;10000gold;all-active catalog;direct production completion;no rendered card/input claim","cases":rows,"ordinaryFieldResult":result}
	field.free()

func support_geometry() -> void:
	var game: Node2D=make_game()
	var areas: Array=game.marching_support_areas("spear",0)
	if not check(areas.size()==1,"One actual ranged post exposes one support candidate circle"): game.free();return
	var area: Dictionary=areas[0]
	check(area.center==Vector2(.50,.62) and is_equal_approx(float(area.radius),.10),"Support overlay radius is .10 at the real post center")
	for offset in [.075,.0999]:
		var point: Vector2=area.center+Vector2(offset,0)
		var destination: Dictionary=game.ground_combat.marching_support_destination("spear",point,0)
		check(not destination.is_empty(),"Passable support drop accepts widened distance "+str(offset))
		if not destination.is_empty(): check(is_equal_approx(float(destination.supportDropRadius),float(area.radius)),"Validator radius exactly matches the shared overlay geometry")
	check(game.ground_combat.marching_support_destination("spear",area.center+Vector2(.1001,0),0).is_empty(),"Point beyond the displayed circle is not a support drop")
	check(game.marching_support_areas("spear",1).is_empty(),"A nonexistent selected march route exposes no support circle")
	var point: Vector2=Vector2(.50,.545)
	game.config["obstacles"]=[{"x":point.x,"y":point.y,"r":.01,"blockPlacement":true}]
	check(game.ground_combat.marching_support_destination("spear",point,0).is_empty(),"Obstacle collision vetoes a point inside the candidate circle")
	game.config["obstacles"]=[]
	game.ground_combat.water_rects.append(Rect2(.48,.53,.04,.04))
	check(game.ground_combat.marching_support_destination("spear",point,0).is_empty(),"Water vetoes an otherwise in-radius support origin")
	game.ground_combat.water_rects.clear()
	game.ground_combat.water_rects.append(Rect2(.05,.505,.90,.02))
	check(game.ground_combat.marching_support_destination("spear",Vector2(.50,.58),0).is_empty(),"Support drop is rejected when every join to its real route crosses water")
	game.ground_combat.water_rects.clear()
	if not check(bool(game.submit_deployment("spear",point,"lane").get("ok",false)),"Legal support drop pays through the normal recruitment transaction"): game.free();return
	var job: Dictionary=game.recruitment_queue[0]
	check(bool(job.destination.get("supportDeployment",false)) and job.position==point,"Support production origin remains the clicked legal point")
	for member in job.memberPositions:
		check(member.distance_to(area.center)<=float(area.radius) and game.ground_combat.land_segment_safe(member,job.destination.supportReturnPosition,.008),"Reserved member stays inside the shown area with a safe return segment")
	game._advance_recruitment(10.0)
	var unit: Dictionary=game.units[0]
	var before: Vector2=unit.position
	game.ground_combat.step(.025)
	check(unit.position.distance_to(before)>.000001 and str(unit.supportPhase)!="waiting","No-enemy support starts actual return movement on its first update")
	evidence["supportGeometry"]={"fixture":"Authored flat post and direct obstacle/water boundary fixtures;not shipped-stage visual acceptance","areas":areas,"firstStep":unit.position-before,"phase":unit.supportPhase}
	game.free()

func one_brawl_return() -> void:
	var game: Node2D=make_game()
	if not check(bool(game.submit_deployment("spear",Vector2(.50,.545),"lane").get("ok",false)),"One-brawl fixture buys a real support order"): game.free();return
	game._advance_recruitment(10.0)
	if not check(game.units.size()==1,"One support actor produced"): game.free();return
	var unit: Dictionary=game.units[0]
	var first: Dictionary=hostile(game,Vector2(.48,.54))
	game.ground_combat.step(.025)
	check(str(unit.supportPhase)=="brawl" and unit.supportEnemyIds==[int(first.id)],"First actual contact locks one finite enemy-group snapshot")
	var later: Dictionary=hostile(game,Vector2(.49,.55))
	game.ground_combat.step(.025)
	check(not unit.supportEnemyIds.has(int(later.id)),"A later enemy does not extend the locked support brawl")
	game._damage_enemy(first,10000.0,"spear",unit)
	var max_stride: float=0.0
	for unused in range(160):
		var previous: Vector2=unit.position
		game.ground_combat.step(.025)
		max_stride=maxf(max_stride,unit.position.distance_to(previous))
		if str(unit.supportPhase)=="done": break
	check(str(unit.supportPhase)=="done","Resolving the locked group returns the actor to normal marching")
	check(max_stride<=.042*.025+.00001,"Return and merge use real speed-bounded steps without teleporting")
	evidence["oneBrawl"]={"lockedIds":unit.supportEnemyIds.duplicate(),"laterId":later.id,"phase":unit.supportPhase,"endReason":unit.get("supportEndReason",""),"maxStride":max_stride,"fixture":"One original and one later controlled enemy;first killed through damage API to resolve only the locked group"}
	game.free()

func enemy_tick(game: Node2D, enemy: Dictionary, delta: float=.025) -> void:
	game.elapsed+=delta
	game._advance_actor_animations(delta)
	game._move_enemy(enemy,delta)

func faces(enemy: Dictionary, target: Dictionary) -> bool:
	var direction: Vector2=target.position-enemy.position
	return direction.length_squared()<.00000001 or (enemy.aim as Vector2).normalized().dot(direction.normalized())>.9999

func bow_ownership() -> void:
	var game: Node2D=make_game()
	check(bool(game.submit_deployment("archer",Vector2(.50,.62)).get("ok",false)) and game.begin_placement("spear",0),"Bow fixture uses paid allied shooter and spear orders")
	game._advance_recruitment(10.0)
	var archer: Dictionary={}
	var spear: Dictionary={}
	for unit in game.units:
		if str(unit.type)=="archer": archer=unit
		if str(unit.type)=="spear": spear=unit
	if not check(not archer.is_empty() and not spear.is_empty(),"Both controlled allied actors exist"): game.free();return
	archer.hp=1000.0;spear.hp=1000.0
	var enemy: Dictionary=hostile(game,Vector2(.50,.46),"enemy_archer")
	enemy.stationaryTargetId=int(archer.id)
	enemy.threatAnchor=enemy.position
	enemy.pursuitRouteDistance=game.ground_combat.enemy_distance(enemy)
	var events: Array=[]
	game.game_event.connect(func(row: Dictionary): events.append(row.duplicate(true)))
	game._move_enemy(enemy,.025)
	check(int(enemy.get("rangedPlan",{}).get("targetId",-1))==int(archer.id),"Actual bow windup commits the assigned emplacement shooter")
	# The actual renderer must retain that owner during idle/recovery too,
	# even when a different ally is physically closer on either side.
	var spear_position: Vector2=spear.position
	var saved_animation: String=str(enemy.animation)
	enemy.animation="idle"
	var visual_directions: Array=[]
	for index in range(12):
		spear.position=enemy.position+Vector2(.025 if index%2==0 else -.025,0)
		var direction: Vector2=game.painted_actors.visual_direction(enemy,false,game)
		visual_directions.append(direction)
		check(direction.y>0 and direction.normalized().dot((visual_directions[0] as Vector2).normalized())>.9999,"Enemy bow rendered idle faces the assigned lower emplacement, not alternating nearer allies")
	enemy.animation=saved_animation
	spear.position=spear_position
	evidence["renderedFacingOwner"]={"fixture":"Actual renderer direction query with assigned shooter below and alternating closer unrelated spear","directions":visual_directions}
	spear.position=Vector2(.515,.455)
	spear.routeDistance=.4
	game.ground_combat.crowd.rebuild(game.units,game.enemies)
	game.ground_combat._assign_blocks()
	check(enemy.get("contactUnitIds",[]).has(int(spear.id)),"A real physical spear contact appears during the bow windup")
	for unused in range(15):
		enemy_tick(game,enemy)
		check(faces(enemy,archer) and int(game.enemy_facing_target(enemy).get("id",-1))==int(archer.id),"Windup, release and recovery keep the same valid shooter-facing owner")
	var ranged_shots: Array=events.filter(func(row: Dictionary): return str(row.get("type",""))=="shot" and int(row.get("actorId",-1))==int(enemy.id) and not bool(row.get("contactCounter",false)))
	check(ranged_shots.size()==1 and game.projectiles.size()==1,"Contact interference cannot duplicate or cancel the one committed ranged release")
	for unused in range(60):
		enemy_tick(game,enemy)
		if not enemy.get("counterPlan",{}).is_empty(): break
	var counter: Dictionary=enemy.get("counterPlan",{})
	check(int(counter.get("targetId",-1))==int(spear.id) and enemy.get("rangedPlan",{}).is_empty(),"After its cooldown the same attacker can prepare one contact counter")
	for index in range(12):
		# Explicit contact-list boundary fixture, while target remains legally in range.
		enemy.contactUnitIds=[] if index%2==0 else [int(spear.id)]
		enemy_tick(game,enemy)
		check(faces(enemy,spear) and enemy.get("counterPlans",{}).size()<=1,"Intermittent contact preserves the prepared counter owner and single budget")
	var counters: Array=events.filter(func(row: Dictionary): return str(row.get("type",""))=="shot" and bool(row.get("contactCounter",false)))
	check(counters.size()==1,"Prepared contact counter releases exactly once")
	archer.hp=0.0
	enemy.contactUnitIds=[]
	for unused in range(160):
		enemy_tick(game,enemy)
		if int(enemy.get("stationaryTargetId",-1))==int(spear.id): break
	check(int(enemy.get("stationaryTargetId",-1))==int(spear.id),"Dead assigned shooter is released and a reachable living target is reacquired")
	var shots_before: int=game.projectiles.size()
	var midpoint: Vector2=(enemy.position+spear.position)*.5
	game.config["obstacles"]=[{"x":midpoint.x,"y":midpoint.y,"r":.01,"blockPlacement":true}]
	for unused in range(45): enemy_tick(game,enemy)
	check(int(enemy.get("stationaryTargetId",-1))!=int(spear.id) and game.enemy_facing_target(enemy).is_empty(),"Unreachable target is released under the existing lost-target grace")
	check(game.projectiles.size()==shots_before,"No new ranged release crosses the newly blocked segment")
	evidence["bowOwnership"]={"fixture":"Paid L1 allies with explicit1000HP durability;controlled bow location/assigned target;component animation/movement calls;contact-list alternation explicitly injected","rangedShots":ranged_shots,"counterShots":counters,"finalTarget":enemy.get("stationaryTargetId",-1),"hunterReturning":enemy.get("hunterReturning",false),"events":events}
	game.free()

func persist() -> void:
	var file: FileAccess=FileAccess.open(OUTPUT,FileAccess.WRITE)
	if file==null: push_error("PATCH08_LOGIC cannot write report");quit(2);return
	file.store_string(JSON.stringify({"status":("passed" if failures.is_empty() else "failed") if completed else "running","checks":checks,"failures":failures,"evidence":evidence,"sources":sources,"sourcesAtEnd":source_hashes(),"wallSeconds":float(Time.get_ticks_usec()-started)/1000000.0,"engine":Engine.get_version_info(),"scope":"Controlled non-rendered component fixtures only;10000gold,active catalog,stated injected positions/HP/contact lists. No player save access;not actual UI input, natural campaign survival or rendered performance acceptance."},"  "))
	file.close()

func run() -> void:
	started=Time.get_ticks_usec()
	sources=source_hashes()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	for method in ["base_orders","support_geometry","one_brawl_return","bow_ownership"]:
		call(method)
		persist()
	check(sources==source_hashes(),"Product and test sources remain unchanged during the controlled fixture run")
	completed=true
	persist()
	print("PATCH08_LOGIC ",ProjectSettings.globalize_path(OUTPUT)," checks=",checks.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
