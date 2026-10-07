extends SceneTree

const Battle = preload("res://native/game.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
var checks: int = 0
var failures: Array = []
var catalog: Array = []
var maps: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func make_game(stage: Dictionary) -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_seed(9831)
	game.load_map(stage)
	return game

func deploy_hint(game: Node2D) -> bool:
	game._refresh_placement_hints()
	for point in game.placement_hints:
		if game.place_unit(point.x,point.y):
			return true
	return false

func run() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check(catalog.size()==8,"Catalog has eight base classes")
	var ids: Array = []
	for definition in catalog: ids.append(str(definition.id))
	var plain: Dictionary = maps[0].duplicate(true)
	plain["trait"] = {}
	for definition in catalog:
		for permanent_level in [1,4,8,10]:
			var game: Node2D = make_game(plain)
			game.gold = 1000
			game.configure_roster(catalog,ids,{str(definition.id):permanent_level})
			var before: int = game.gold
			check(game.recruit(str(definition.id)),"Selected recruit succeeds: %s Lv%d" % [definition.id,permanent_level])
			check(game.pending.type==definition.id and game.gold==before-int(definition.cost),"Selected class and exact cost retained")
			var pending_stats: Dictionary = game.snapshot().pending
			var evo: int = 2 if permanent_level>=8 else 1 if permanent_level>=4 else 0
			var damage_multi: float = 1.30 if evo==2 else 1.12 if evo==1 else 1.0
			var range_multi: float = 1.08 if evo==2 else 1.04 if evo==1 else 1.0
			var interval_multi: float = 0.92 if evo==2 else 0.96 if evo==1 else 1.0
			check(is_equal_approx(float(pending_stats.damage),float(definition.damage)*(1+.08*(permanent_level-1))*damage_multi),"Permanent damage formula")
			check(is_equal_approx(float(pending_stats.range),float(definition.range)*(1+.012*(permanent_level-1))*range_multi),"Permanent range formula")
			check(is_equal_approx(float(pending_stats.interval),float(definition.interval)/(1+.015*(permanent_level-1))*interval_multi),"Permanent interval formula")
			check(int(pending_stats.evolution)==evo,"Evolution unlock boundary")
			check(deploy_hint(game),"Each selected class can deploy")
			var actor: Dictionary = game.actor_states()[0]
			check(actor.type==definition.id and int(actor.campaignLevel)==permanent_level and int(actor.evolution)==evo,"Renderer retains class, training and evolution")
			var frozen: Dictionary = game._stats(game.units[0])
			game.configure_roster(catalog,ids,{str(definition.id):10})
			check(is_equal_approx(float(game._stats(game.units[0]).damage),float(frozen.damage)),"Roster changes cannot retroactively modify deployed stats")
			game.free()
	var guard: Node2D = make_game(plain)
	guard.configure_roster(catalog,["archer","spear"],{})
	var gold_before: int = guard.gold
	var id_before: int = guard.next_id
	check(not guard.recruit("samurai") and not guard.recruit("unknown"),"Locked and unknown classes rejected")
	check(guard.gold==gold_before and guard.next_id==id_before and guard.pending.is_empty(),"Rejected selection has no monetary or identity side effects")
	guard.gold=59
	check(not guard.recruit("archer") and guard.gold==59,"Insufficient funds are rejected")
	guard.gold=100
	check(guard.recruit("spear"),"Starter spear selection succeeds")
	guard.cancel_recruit()
	check(guard.gold==100,"Cancellation refunds selected class cost")
	guard.free()
	test_attacks(plain,ids)
	test_matchlock_grip()
	test_landing_visual()
	test_starter_battle()
	var result: Dictionary = {"checks":checks,"failures":failures}
	var file: FileAccess = FileAccess.open("res://tests/qa_roster.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("ROSTER_QA ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func test_attacks(plain: Dictionary, ids: Array) -> void:
	for type_name in ids:
		var game: Node2D = make_game(plain)
		game.gold=1000
		game.configure_roster(catalog,ids,{type_name:10})
		game.recruit(type_name)
		deploy_hint(game)
		game.start_battle()
		game._spawn_enemy("shield")
		game._spawn_enemy("raider")
		var unit: Dictionary = game.units[0]
		var target: Dictionary = game.enemies[0]
		var nearby: Dictionary = game.enemies[1]
		target.position=unit.position+Vector2(.02,0)
		nearby.position=target.position+Vector2(.02,0)
		target.hp=1000.0
		target.maxHp=1000.0
		nearby.hp=1000.0
		nearby.maxHp=1000.0
		game._release_unit_attack(unit,{"targetId":target.id,"damage":100.0})
		if type_name in ["archer","gunner","commander"]:
			check(game.projectiles.size()==1,"Ranged class launches one real projectile: "+type_name)
			game._update_projectiles(.1)
		check(float(target.hp)<1000,"Each selected class damages enemies: "+type_name)
		if type_name=="gunner":
			check(is_equal_approx(float(target.hp),1000-100*(1-.38*.3)),"Matchlock ignores seventy percent of target armor")
		if type_name=="naginata":
			check(is_equal_approx(float(nearby.hp),945.0),"Naginata delivers fifty-five percent damage to nearby enemy")
		if type_name=="spear":
			check(is_equal_approx(float(nearby.hp),975.0),"Spear delivers twenty-five percent piercing splash")
		if type_name=="ninja":
			target.hp=300.0
			game._damage_enemy(target,100.0,"ninja")
			check(is_equal_approx(float(target.hp),300-150*(1-.38)),"Ninja executes targets at thirty percent health")
			unit.animation="idle"
			unit.cooldown=0.0
			game._update_units(0)
			var duration: float = float(unit.attackDuration)
			var release: float = float(unit.attackPlan.releaseTime)
			check(duration<float(game._stats(unit).interval) and release<duration,"Ninja completes recovery before next trained attack")
			game._advance_actor_animations(release+.001)
			check(unit.attackPlan.is_empty(),"Ninja impact releases exactly once")
			game._advance_actor_animations(duration-release+.001)
			check(unit.animation=="idle","Ninja attack reaches its recovered pose")
		if type_name=="monk":
			check(is_equal_approx(float(target.slowClock),1.5) and is_equal_approx(float(target.slowFactor),.75),"Monk applies a timed twenty-five percent slow")
			var normal: Dictionary = target.duplicate(true)
			normal["slowClock"]=0.0
			var position_before: Vector2 = target.position
			game._move_enemy(target,.1)
			game._move_enemy(normal,.1)
			check(is_equal_approx(position_before.distance_to(target.position)/position_before.distance_to(normal.position),.75),"Slow affects actual path movement")
			game._advance_actor_animations(1.6)
			check(float(target.slowClock)==0.0,"Slow expires without changing permanent movement speed")
		game.free()

func test_matchlock_grip() -> void:
	var actor: Node3D = Actor.new()
	root.add_child(actor)
	actor.configure("gunner",false,88,false,2)
	for scale_value in [.9,1.0,1.1]:
		actor.scale=Vector3.ONE*scale_value
		for clock in [.0,.1,.25,.40,.50]:
			actor.apply_state({"animation":"attack","animationClock":clock,"aimX":0.0,"aimY":1.0})
			var palm: Vector3 = actor.bones.handL.global_transform*Vector3(0,-.03,-.005)
			var grip: Vector3 = actor.bones.weapon.global_transform*Vector3(0,.14,0)
			check(palm.distance_to(grip)<.035,"Matchlock support hand remains on the barrel throughout preparation/impact/recovery at each perspective scale")
			check(is_equal_approx(actor.bones.weapon.global_basis.get_scale().x,scale_value),"Matchlock weapon preserves perspective scale through world-space aiming")
	actor.free()

func test_landing_visual() -> void:
	for stage in maps:
		if str(stage.theme)!="harbor": continue
		var game: Node2D = make_game(stage)
		game._spawn_enemy("raider")
		var enemy: Dictionary = game.enemies[0]
		var landing: int = int(stage.landingIndex)
		var route: Array = game.paths[int(enemy.pathIndex)].points
		enemy.pointIndex=landing
		enemy.position=route[landing-1].lerp(route[landing],.5)
		check(bool(game.actor_states()[0].sailing),"Harbor approach uses the rowboat on water: "+str(stage.id))
		enemy.position=route[landing-1].lerp(route[landing],.90)
		check(not bool(game.actor_states()[0].sailing),"Rowboat disappears during the pier disembarkation segment: "+str(stage.id))
		game.free()

func test_starter_battle() -> void:
	var game: Node2D = make_game(maps[0])
	game.configure_roster(catalog,["archer","spear"],{})
	var steps: int = 0
	deploy_starters(game)
	game.start_battle()
	while not game.finished and steps<16000:
		if game.between_waves:
			game.grant_reward("correct")
			deploy_starters(game)
			game.continue_wave()
		elif steps%20==0:
			deploy_starters(game)
		game.advance_simulation(.25)
		steps+=1
	check(game.finished and game.victory,"First stage is winnable with only the two starter classes at training level one")
	print("STARTER_BATTLE victory=",game.victory," hp=",game.snapshot().hp," waves=",game.wave," kills=",game.kills," seconds=",game.elapsed)
	game.free()

func deploy_starters(game: Node2D) -> void:
	var guard: int = 0
	while game.gold>=60 and game.units.size()<int(game.config.get("unitLimit",14)) and guard<30:
		guard+=1
		var type_name: String = "spear" if game.units.size()%4==3 and game.gold>=65 else "archer"
		if not game.recruit(type_name): break
		var samples: Array = []
		for route in game.paths:
			for segment in range(route.points.size()-1):
				for fraction in range(8):
					samples.append(route.points[segment].lerp(route.points[segment+1],fraction/8.0))
		var best: Vector2 = Vector2(-1,-1)
		var best_score: float = -INF
		var attack_range: float = float(game.snapshot().pending.range)
		for zone in game.zones:
			for ring in range(5):
				for spoke in range(20):
					var point: Vector2 = zone.position+Vector2.from_angle(TAU*spoke/20.0)*float(zone.r)*ring/5.0
					if game._eligible_zone(point).is_empty(): continue
					var occupied: bool = false
					for placed in game.units:
						if placed.position.distance_to(point)<.052: occupied=true
					if occupied: continue
					var score: float = 0.0
					for sample in samples:
						var distance: float = point.distance_to(sample)
						if distance<attack_range: score+=1.0+(attack_range-distance)/attack_range
					if score>best_score:
						best_score=score
						best=point
		if best.x<0 or not game.place_unit(best.x,best.y):
			game.cancel_recruit()
			break
