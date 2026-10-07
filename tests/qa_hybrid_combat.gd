extends SceneTree
## Observable combat, legal placement and renderer bridge, not campaign balance.
const Game = preload("res://native/game.gd")
const Troops = preload("res://native/troops_3d.gd")
var checks: int = 0
var failures: Array = []
var observations: Dictionary = {}
var catalog: Array = []
var maps: Array = []
var ground_ids: Array = ["spear","samurai","naginata","monk","ninja","commander"]

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error(message)

func make_game(stage: Dictionary = {}) -> Node2D:
	var game: Node2D=Game.new()
	root.add_child(game)
	game.set_process(false)
	var ids: Array=[]
	for entry in catalog: ids.append(entry.id)
	game.configure_roster(catalog,ids,{})
	var test_stage: Dictionary={"id":"hybrid-mechanics-fixture","initialGold":10000,"unitLimit":14,"totalWaves":1,"difficulty":1.0,"paths":[{"objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"x":.50,"y":.68,"r":.08}],"tactics":{"nameKo":"실험 길목","groundPosts":[{"id":"test-post","nameKo":"검증 진지","pathIndex":0,"segmentIndex":0,"t":.5,"r":.07,"guardRadius":.16,"mobilityFactor":1.0,"capacityBonus":0}]}}
	game.load_map(stage if not stage.is_empty() else test_stage)
	game.set_seed(19)
	return game

func deploy(game: Node2D, id: String, requested: Vector2=Vector2(-1,-1)) -> Dictionary:
	check(game.recruit(id),"Recruit "+id)
	var point: Vector2=requested
	if point.x<0:
		for zone in game.zones:
			point=game._zone_placement_hint(zone,id)
			if point.x>=0: break
	check(point.x>=0 and game.place_unit(point.x,point.y),"Actual legal placement "+id)
	return game.units[-1] if not game.units.is_empty() else {}

func hold_wave(game: Node2D) -> void:
	game.start_battle()
	game.spawn_queue=["raider"]
	game.spawn_clock=100000.0

func enemy_at(game: Node2D, x: float, hp: float=1000.0, route_index: int=0) -> Dictionary:
	game._spawn_enemy("raider")
	var enemy: Dictionary=game.enemies[-1]
	enemy["pathIndex"]=route_index
	enemy["pointIndex"]=1
	enemy["position"]=Vector2(x,.5)
	enemy["hp"]=hp
	enemy["maxHp"]=hp
	return enemy

func simulate(game: Node2D, seconds: float) -> void:
	for step in range(int(round(seconds/.025))): game.advance_simulation(.025)

func test_deployment() -> void:
	for stage in maps:
		var game: Node2D=make_game(stage)
		var original_count: int=stage.buildZones.size()
		check(game.zones.size()==original_count+stage.tactics.groundPosts.size(),str(stage.id)+" zones append original supports and posts")
		for index in range(game.zones.size()):
			var zone: Dictionary=game.zones[index]
			var role: String="ranged" if index<original_count else "ground"
			check(str(zone.placementRole)==role,str(stage.id)+" zone role "+str(index))
			var id: String="archer" if role=="ranged" else "spear"
			var point: Vector2=game._zone_placement_hint(zone,id)
			if role=="ground": check(point.x>=0,str(stage.id)+" ground post has a legal slot "+str(index))
			if point.x>=0:
				check(not game._eligible_zone(point,id).is_empty(),str(stage.id)+" hint is eligible for matching class")
				var other_zone: Dictionary=game._eligible_zone(point,"spear" if role=="ranged" else "archer")
				check(other_zone.is_empty() or str(other_zone.placementRole)!="ranged" if role=="ranged" else other_zone.is_empty() or str(other_zone.placementRole)!="ground",str(stage.id)+" other type never returns wrong-role zone")
		game.free()
	var first: Node2D=make_game(maps[0])
	first.gold=10000
	for id in ["archer","gunner"]+ground_ids:
		var unit: Dictionary=deploy(first,id)
		check(str(unit.combatRole)==("cavalry" if id=="commander" else "frontline_shooter" if id=="gunner" else "ground" if id in ground_ids else "ranged"),id+" public role")
	check(first.units.size()==8,"All eight classes fit actual first map without point collision")
	for a in range(first.units.size()):
		for b in range(a): check(first._reserved_position(first.units[a]).distance_to(first._reserved_position(first.units[b]))>=.052,"Reserved home positions stay separated")
	first.recruit("spear")
	for index in range(first.zones.size()):
		if str(first.zones[index].placementRole)=="ranged": check(first.placement_hints[index].x<0,"Melee recruitment does not advertise wall deployment")
	first.cancel_recruit()
	for index in range(first.zones.size()):
		if str(first.zones[index].placementRole)=="ground": check(first.placement_hints[index].x<0,"Cancel restores default ranged hints")
	first.free()

func test_block_and_damage() -> void:
	var game: Node2D=make_game()
	var unit: Dictionary=deploy(game,"spear")
	hold_wave(game)
	var enemy: Dictionary=enemy_at(game,.535)
	var home: Vector2=unit.homePosition
	var enemy_start: Vector2=enemy.position
	simulate(game,.8)
	check(int(enemy.get("blockedBy",-1))==int(unit.id),"Spear actually blocks a nearby route enemy")
	check(enemy.position.distance_to(enemy_start)<.001,"Blocked enemy stops route progress")
	check(float(enemy.hp)<1000,"Spear deals a timed close strike")
	check(float(unit.hp)<float(unit.maxHp),"Blocked enemy visibly counterattacks allied health")
	check(game.projectiles.is_empty(),"Infantry uses close strikes, no fake ranged projectile")
	var start_hp: float=float(unit.hp)
	unit.hp=1.0
	simulate(game,.05)
	check(str(unit.combatState)=="retreat","Low health starts actual retreat")
	check(int(enemy.get("blockedBy",-1))<0,"Wounded defender releases the enemy")
	var after_release: Vector2=enemy.position
	simulate(game,.5)
	check(enemy.position.distance_to(after_release)>.001,"Released enemy resumes objective progress")
	check(unit.position.distance_to(home)>.01,"Wounded infantry moves along its route to reserve")
	game.enemies.clear()
	simulate(game,18)
	check(str(unit.combatState)=="guard" and unit.position.distance_to(home)<.0002,"Recovered infantry physically returns to its own home")
	check(is_equal_approx(float(unit.hp),float(unit.maxHp)),"Local recovery restores full health")
	observations["counterattackHealthLoss"]=float(unit.maxHp)-start_hp
	game.free()

func test_capacity_and_routes() -> void:
	var game: Node2D=make_game()
	var unit: Dictionary=deploy(game,"spear")
	hold_wave(game)
	for index in range(4): enemy_at(game,.52+index*.001)
	game.ground_combat.step(.001)
	var stopped: int=0
	for enemy in game.enemies:
		if game.ground_combat.blocked(enemy): stopped+=1
	check(stopped==2 and int(unit.blockCount)==2,"Finite spear capacity blocks two of four enemies")
	game.paths.append({"points":[Vector2(.05,.51),Vector2(.95,.51)],"objectiveId":"main"})
	game.ground_combat.reset()
	var other: Dictionary=enemy_at(game,.51,1000,1)
	game.ground_combat.step(.001)
	check(int(other.get("blockedBy",-1))<0,"Nearby parallel route is not captured by another post")
	game.free()

func test_charge() -> void:
	var game: Node2D=make_game()
	var unit: Dictionary=deploy(game,"commander")
	hold_wave(game)
	var enemy: Dictionary=enemy_at(game,.40,1000)
	var start: Vector2=unit.position
	var strike_damage: float=0
	var prior_hp: float=float(enemy.hp)
	var states: Dictionary={}
	for step in range(240):
		game.advance_simulation(.025)
		states[str(unit.combatState)]=true
		if float(enemy.hp)<prior_hp and strike_damage==0: strike_damage=prior_hp-float(enemy.hp)
		prior_hp=float(enemy.hp)
	check(states.has("charge") and states.has("impact") and states.has("charge_return"),"Cavalry performs charge, impact and actual return")
	check(strike_damage>float(game._stats(unit).damage)*2.0,"Cavalry burst exceeds ordinary close damage")
	check(game.projectiles.is_empty(),"Cavalry does not fire a tower projectile")
	check(unit.position.distance_to(start)<.001,"Cavalry comes back to reserved home")
	check(float(unit.chargeCooldown)>0,"Cavalry cooldown prevents indefinite repeated charge")
	observations["cavalryStates"]=states.keys()
	observations["cavalryFirstHit"]=strike_damage
	game.paused=true
	var before: Dictionary=unit.duplicate(true)
	game.advance_simulation(2)
	check(unit==before,"Pause freezes cavalry, cooldown, health and position")
	game.free()

func test_safe_bounds() -> void:
	for stage in maps:
		if str(stage.theme) not in ["harbor","convoy"]: continue
		var game: Node2D=make_game(stage)
		game.gold=10000
		for zone in game.zones:
			if str(zone.placementRole)!="ground": continue
			var unit: Dictionary=deploy(game,"commander",zone.position)
			var path_index: int=int(unit.postPathIndex)
			game.ground_combat._walk(unit,-100.0,100.0)
			check(float(unit.routeDistance)>=float(unit.routeMin)-.00001,str(stage.id)+" approach stays on land")
			game.ground_combat._walk(unit,100.0,100.0)
			check(float(unit.routeDistance)<=float(unit.routeMax)+.00001,str(stage.id)+" does not chase moving objective segment")
			check(unit.position.distance_to(game.ground_combat.route_point(path_index,float(unit.routeDistance)))<.00001,"Actual ground actor remains on assigned route")
		game.free()

func test_renderer() -> void:
	var game: Node2D=make_game()
	var unit: Dictionary=deploy(game,"samurai")
	hold_wave(game)
	enemy_at(game,.375)
	simulate(game,.4)
	check(str(unit.animation)=="walk" and not bool(unit.deploying),"Approach is actual walking, not recruitment settling")
	var troops: Control=Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(1050,622))
	troops.manual_states=game.actor_states()
	troops.sync_actor_states(troops.manual_states)
	var actor: Node3D=troops.actors[str(unit.id)+":0"]
	check(actor.position.distance_to(troops.normalized_to_world(unit.position))<.00001,"Actual movement anchor has no fake deploy offset")
	var first_clock: float=float(unit.animationClock)
	simulate(game,.5)
	check(str(unit.animation)=="walk" and float(unit.animationClock)>first_clock,"Real walk survives the old .35 second deployment timeout")
	troops.sync_actor_states(game.actor_states())
	check(float(troops.actors[str(unit.id)+":0"].current_state.locomotionPhase)>float(unit.animationPhase),"Moving ground actor drives whole-body distance-based gait")
	troops.free()
	game.free()

func test_wave_boundaries() -> void:
	for final_wave in [false,true]:
		var game: Node2D=make_game()
		game.total_waves=1 if final_wave else 2
		var unit: Dictionary=deploy(game,"commander")
		hold_wave(game)
		var enemy: Dictionary=enemy_at(game,.515,1)
		game.spawn_queue.clear()
		var gold_before: int=game.gold
		var finished_calls: Array=[]
		game.battle_finished.connect(func(result): finished_calls.append(result))
		for step in range(100):
			game.advance_simulation(.025)
			if game.finished or game.between_waves: break
		check(game.finished if final_wave else game.between_waves,"Last close enemy completes the appropriate wave boundary")
		check(int(unit.blockCount)==0 and unit.attackPlan.is_empty() and int(unit.targetId)<0,"Wave boundary clears stale block/target/attack plan")
		check(float(unit.chargeCooldown)>0,"Last enemy charge still reserves its cooldown")
		check(game.gold==gold_before+int(enemy.reward)+43,"One kill and one wave payout only")
		var before: Dictionary=unit.duplicate(true)
		var frozen_gold: int=game.gold
		game.advance_simulation(30)
		check(unit==before and game.gold==frozen_gold,"Between-wave/finished boundary freezes health, position and cooldown")
		check(finished_calls.size()==(1 if final_wave else 0),"Final completion emits exactly once")
		game.free()
	var game: Node2D=make_game()
	var unit: Dictionary=deploy(game,"samurai")
	hold_wave(game)
	game.objectives[0].hp=1
	var escaping: Dictionary=enemy_at(game,.9499)
	var other: Dictionary=enemy_at(game,.15)
	var other_position: Vector2=other.position
	var gold_before: int=game.gold
	game.advance_simulation(.05)
	check(game.finished and not game.victory,"Lethal objective loss finishes immediately")
	check(other.position==other_position and game.gold==gold_before,"No later enemy movement/reward occurs after lethal objective loss")
	var before: Dictionary=unit.duplicate(true)
	game.advance_simulation(50)
	check(unit==before,"Defeat freezes ally movement and recovery")
	game.free()

func test_charge_target_loss() -> void:
	var game: Node2D=make_game()
	var unit: Dictionary=deploy(game,"commander")
	hold_wave(game)
	var target: Dictionary=enemy_at(game,.37,1000)
	simulate(game,.5)
	check(str(unit.combatState)=="charge","Mounted target-loss test begins during movement")
	target.hp=0.0
	simulate(game,3)
	check(unit.position.distance_to(unit.homePosition)<.0002 and str(unit.combatState)=="guard","Dead charge target causes bounded physical return")
	check(unit.attackPlan.is_empty() and game.projectiles.is_empty(),"Cancelled charge does not inflict a ghost strike")
	game.free()

func test_cosmetic_death_boundaries() -> void:
	var harbor: Dictionary={}
	for stage in maps:
		if str(stage.id)=="basic-harbor": harbor=stage;break
	check(not harbor.is_empty(),"Marine death fixture uses an actual shipped harbor")
	for final_wave in [false,true]:
		var game: Node2D=make_game(harbor)
		game.total_waves=1 if final_wave else 2
		var unit: Dictionary=deploy(game,"spear")
		hold_wave(game)
		game.apply_learning_support(unit.position,false,"cosmetic-death-support")
		unit.combatState="recover"
		unit.recoverRemaining=4.0
		unit.hp=float(unit.maxHp)*.4
		game._spawn_enemy("raider")
		var enemy: Dictionary=game.enemies[-1]
		enemy.pathIndex=0
		enemy.pointIndex=1
		enemy.position=game.paths[0].points[0]
		check(game._sailing_visual(enemy),"Actual harbor enemy is afloat before death")
		enemy.hp=0.0
		game.spawn_queue.clear()
		var gold_before: int=game.gold
		game.advance_simulation(.025)
		check(game.finished if final_wave else game.between_waves,"Marine death ends the appropriate battle boundary")
		check(game.death_actors.size()==1 and bool(game.death_actors[0].get("sailing",false)),"Marine death actor retains its actual sailing state")
		var delivered: bool=false
		for state in game.actor_states():
			if bool(state.dead): delivered=bool(state.sailing)
		check(delivered,"Actual renderer bridge receives sailing plus death together")
		check(bool(game.snapshot().deathActors[0].sailing),"Marine state is visible in the public death snapshot")
		check(game.gold==gold_before+int(enemy.reward)+43,"Cosmetic marine death receives only one kill and wave reward")
		var before_unit: Dictionary=unit.duplicate(true)
		var before_supports: Array=game.learning_supports.duplicate(true)
		var before_elapsed: float=float(game.elapsed)
		var before_animation: float=float(game.animation_time)
		var before_hp: int=int(game.snapshot().hp)
		var before_gold: int=game.gold
		var before_clock: float=float(game.death_actors[0].animationClock)
		game.paused=true
		game._process(.15)
		check(is_equal_approx(float(game.death_actors[0].animationClock),before_clock),"Explicit pause freezes a cosmetic death at both boundaries")
		game.paused=false
		game._process(.1)
		check(float(game.death_actors[0].animationClock)>before_clock,"Study/result boundary lets already-defeated bodies finish their fall")
		for frame in range(8): game._process(.1)
		check(game.death_actors.is_empty(),"Cosmetic death finishes and removes the actor during the study/result boundary")
		check(game.gold==before_gold and int(game.snapshot().hp)==before_hp,"Cosmetic death gives no repeated rewards or objective damage")
		check(unit==before_unit,"Cosmetic death does not heal, move or advance allied recovery/cooldown")
		check(game.learning_supports==before_supports,"Cosmetic death does not consume the earned support duration")
		check(is_equal_approx(float(game.elapsed),before_elapsed) and is_equal_approx(float(game.animation_time),before_animation),"Gameplay time stays frozen while only death time advances")
		check(game.finished if final_wave else game.between_waves,"Cosmetic cleanup cannot begin another wave")
		game.free()

func test_click_event_coordinates() -> void:
	var viewport: Viewport=root.get_viewport()
	var original_canvas: Transform2D=viewport.canvas_transform
	for three_d in [false,true]:
		for transformed_canvas in [false,true]:
			var game: Node2D=make_game()
			game.three_d_enabled=three_d
			game.set_field_rect(Rect2(130,190,800,500))
			check(game.global_transform==Transform2D.IDENTITY,"Click fixture matches production game canvas-origin layout")
			viewport.canvas_transform=Transform2D(Vector2(1.25,0),Vector2(0,1.25),Vector2(40,30)) if transformed_canvas else Transform2D.IDENTITY
			check(game.recruit("spear"),"Ground pending is established for event-coordinate placement")
			var hint: Vector2=Vector2(-1,-1)
			for point in game.placement_hints:
				if point.x>=0: hint=point;break
			check(hint.x>=0,"Ground pending advertises a typed legal plus marker")
			var click_canvas: Vector2=game._screen(hint)
			check(game.get_global_mouse_position().distance_to(click_canvas)>50,"Recorded click is deliberately different from current pointer position")
			var click: InputEventMouseButton=InputEventMouseButton.new()
			click.button_index=MOUSE_BUTTON_LEFT
			click.pressed=true
			click.position=viewport.canvas_transform*click_canvas
			click.global_position=Vector2(-800,-800)
			game._unhandled_input(click)
			check(game.units.size()==1 and game.pending.is_empty(),"Click event places ground unit despite unrelated current pointer/global event position")
			if not game.units.is_empty():
				check(game.units[0].position.distance_to(hint)<.00002,"Event-position deployment lands at its advertised actual ground anchor")
				var first: Dictionary=game.units[0]
				var second: Dictionary=deploy(game,"archer")
				click.position=viewport.canvas_transform*game._screen(first.position)
				game._unhandled_input(click)
				check(game.selected_id==int(first.id) and game.selected_id!=int(second.id),"Selection uses recorded click instead of restored mouse pointer")
				game.recruit("spear")
				var before_count: int=game.units.size()
				game.set_input_enabled(false)
				game._unhandled_input(click)
				check(game.units.size()==before_count and not game.pending.is_empty(),"Overlay input lock still prevents recorded clicks from placing behind UI")
			game.free()
	viewport.canvas_transform=original_canvas

func run() -> void:
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	test_deployment()
	test_block_and_damage()
	test_capacity_and_routes()
	test_charge()
	test_safe_bounds()
	test_renderer()
	test_wave_boundaries()
	test_charge_target_loss()
	test_cosmetic_death_boundaries()
	test_click_event_coordinates()
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"scope":"Actual simulation and renderer state: all forty maps' typed deployment, first-stage eight classes, finite blocking, counterattacks, close strike, wound retreat/recovery/return, cavalry burst, pause, merge cleanup, harbor/convoy route bounds, real distance-driven walking, marine death delivery and cosmetic study/result cleanup without advancing gameplay. Fixture funds only for isolated mechanics; campaign balance is separately tested."}
	var report_path: String = "user://qa_hybrid_combat.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_hybrid_combat.json"
	var output: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("HYBRID_COMBAT_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
