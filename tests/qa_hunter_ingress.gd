extends SceneTree
## CPU-only state-transition checks against the actual game movement methods.
const Game = preload("res://native/game.gd")
var checks: int = 0
var failures: Array[String] = []

func _init() -> void:
	_spawn_heading()
	_direct_attack_and_return()
	_removed_during_ingress()
	_blocked_return()
	_safe_connection()
	_stationary_ingress()
	_protected_early_stage()
	_forward_route_return()
	_ranged_ingress()
	_moved_target_grace()
	_snow_phase_gate()
	for failure in failures:
		push_error(failure)
	print("Hunter ingress QA: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _game() -> Node2D:
	var game: Node2D = Game.new()
	game.config = {"id":"hunter-test","theme":"forest","stageNumber":20,"obstacles":[]}
	game.paths = [{"points":[Vector2(.65,.15),Vector2(.65,.85)],"objectiveId":"main"}]
	game.objectives = [{"id":"main","position":Vector2(.65,.85),"hp":100,"maxHp":100}]
	game.wave = 1
	game.ground_combat.bind(game)
	game.ground_combat.reset()
	game.unit_skills.bind(game)
	return game

func _shooter(id: int, point: Vector2, kind: String = "archer") -> Dictionary:
	return {"id":id,"type":kind,"position":point,"hp":105.0,"maxHp":105.0,"postPathIndex":0,"combatState":"guard","aim":Vector2.RIGHT,"animation":"idle","animationClock":0.0}

func _hunter(game: Node2D, kind: String = "enemy_samurai", settles: bool = false) -> Dictionary:
	var entry: Dictionary = {"id":"side","pathIndex":0,"points":[Vector2(.15,.25),Vector2(.40,.25),Vector2(.40,.55),Vector2(.65,.55)],"joinDistance":.4,"pointIndex":1}
	var enemy: Dictionary = game._spawn_enemy(kind,1,{"ambushEntry":entry})
	if settles:
		enemy["stationaryAfterIngress"] = true
		enemy["stationaryTargetId"] = -1
		enemy.erase("ingressTargetPoint")
		enemy.erase("ingressTargetIndex")
	return enemy

func _tick(game: Node2D, enemy: Dictionary, delta: float = .05) -> void:
	game.elapsed += delta
	game._move_enemy(enemy,delta)
	enemy.animationClock = float(enemy.animationClock)+delta

func _spawn_heading() -> void:
	for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2(-1,1).normalized()]:
		var game: Node2D=_game()
		var start: Vector2=Vector2(.5,.5)
		game.paths=[{"points":[start,start+direction*.3],"objectiveId":"main"}]
		game.ground_combat.reset()
		var enemy: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":0,"formationLane":1})
		var destination: Vector2=game._enemy_lane_point(enemy,1)
		check((enemy.aim as Vector2).dot((destination-enemy.position).normalized())>.9999,"First render faces its real formation lane, including reversed and diagonal entries")
		check(enemy.position==game._enemy_lane_point(enemy,0) and int(enemy.pathIndex)==0,"Initial facing does not move a spawn or change its route")
		game.free()
	var game: Node2D=_game()
	game.units=[_shooter(101,Vector2(.38,.38))]
	var hunter: Dictionary=_hunter(game)
	check((hunter.aim as Vector2).dot(Vector2.RIGHT)>.9999,"Hidden hunter departure faces its first terrain leg instead of the main road")
	game.units.clear()
	var entry: Dictionary={"id":"landing","pathIndex":0,"points":[Vector2(.15,.25),Vector2(.40,.25),Vector2(.65,.55)],"joinDistance":.4,"pointIndex":1,"transportKind":"boat","transportPoints":[{"x":.15,"y":.05},{"x":.15,"y":.25}]}
	var sailor: Dictionary=game._spawn_enemy("enemy_samurai",1,{"ambushEntry":entry})
	check(bool(sailor.get("transportActive",false)) and (sailor.aim as Vector2).dot(Vector2.DOWN)>.9999,"Boat departure initially faces the landing before the sideways land approach")
	check(sailor.position==Vector2(.15,.05),"Initial boat heading does not teleport it to shore")
	game.free()

func _direct_attack_and_return() -> void:
	var game: Node2D = _game()
	var shooter: Dictionary = _shooter(101,Vector2(.38,.38))
	game.units = [shooter,_shooter(102,Vector2(.52,.55),"gunner")]
	var enemy: Dictionary = _hunter(game)
	check(int(enemy.get("stationaryTargetId",-1)) == 101,"corridor picks nearer archer")
	var attacks: bool = false
	var left_at: Vector2 = Vector2.ZERO
	for i in range(1000):
		var was_ingress: bool = bool(enemy.ingressActive)
		_tick(game,enemy)
		if was_ingress and not bool(enemy.ingressActive): left_at = enemy.position
		check(int(enemy.get("stationaryTargetId",-1)) == 101,"target commitment stays stable")
		if not enemy.get("counterPlan",{}).is_empty(): attacks = true;break
	check(attacks,"hunter approaches and schedules melee attack")
	check(left_at.distance_to(Vector2(.38,.25)) < .005,"hunter exits corridor before main-road join")
	check(enemy.position.distance_to(shooter.position) <= .033,"direct approach reaches attack range")
	game.units.clear()
	_tick(game,enemy)
	check(bool(enemy.get("hunterReturning",false)),"missing target begins finite return")
	var walked: float = 0.0
	var return_complete: bool = false
	for i in range(1200):
		var previous: Vector2 = enemy.position
		_tick(game,enemy)
		walked += previous.distance_to(enemy.position)
		if not bool(enemy.get("hunterReturning",false)): return_complete = true;break
	check(return_complete,"unused corridor finishes within bounded time")
	check(enemy.position.distance_to(Vector2(.65,.55)) < .001,"return joins authored main-road point")
	check(walked < .9,"return does not retrace entry or loop")
	check(not enemy.has("ingressTargetPoint") and not enemy.has("threatAnchor"),"return clears pursuit anchors")
	var joined_y: float = enemy.position.y
	for i in range(20): _tick(game,enemy)
	check(enemy.position.y > joined_y,"resumed main-route march advances toward objective")
	game.free()

func _removed_during_ingress() -> void:
	var game: Node2D = _game()
	game.units = [_shooter(101,Vector2(.38,.38))]
	var enemy: Dictionary = _hunter(game)
	game.units.clear()
	_tick(game,enemy)
	check(bool(enemy.ingressActive) and not enemy.has("ingressTargetPoint"),"removed target resumes corridor before arriving")
	check(not bool(enemy.get("hunterReturning",false)),"early target removal does not retrace ingress")
	for i in range(500):
		_tick(game,enemy)
		if not bool(enemy.ingressActive): break
	check(not bool(enemy.ingressActive),"target-free corridor completes")
	game.free()

func _blocked_return() -> void:
	var game: Node2D = _game()
	var shooter: Dictionary = _shooter(101,Vector2(.38,.38))
	game.units = [shooter]
	var enemy: Dictionary = _hunter(game)
	for i in range(700):
		_tick(game,enemy)
		if not bool(enemy.ingressActive): break
	var guard: Dictionary = _shooter(102,enemy.position,"naginata")
	game.units.append(guard)
	enemy["blockedBy"] = 102
	var previous: Vector2 = enemy.position
	_tick(game,enemy)
	check(enemy.position == previous,"naginata physically blocks direct hunter approach")
	check(int(enemy.get("counterPlan",{}).get("targetId",-1)) == 102,"hunter retaliates against blocking guard")
	shooter.hp = 0.0
	_tick(game,enemy)
	check(int(enemy.stationaryTargetId) == -1,"destroyed commitment cleared even while guard blocks")
	check(bool(enemy.get("hunterReturning",false)),"return queued while blocked")
	game.units.clear()
	for i in range(1000):
		_tick(game,enemy)
		if not bool(enemy.get("hunterReturning",false)): break
	check(not bool(enemy.get("hunterReturning",false)),"guard removal permits finite corridor return")
	game.free()

func _safe_connection() -> void:
	var game: Node2D = _game()
	game.config.obstacles = [{"x":.46,"y":.335,"r":.055,"blockPlacement":true}]
	var shooter: Dictionary = _shooter(101,Vector2(.46,.42))
	game.units = [shooter]
	var enemy: Dictionary = _hunter(game)
	check(enemy.has("ingressTargetPoint"),"corridor finds alternate safe target connection")
	if enemy.has("ingressTargetPoint"):
		check(game.ground_combat.land_segment_safe(enemy.ingressTargetPoint,shooter.position),"chosen connection avoids obstacle")
		check(int(enemy.ingressTargetIndex) >= 2,"blocked shortcut cannot override authored corridor")
	var attack: bool = false
	for i in range(1200):
		var previous: Vector2 = enemy.position
		_tick(game,enemy)
		check(game.ground_combat.land_segment_safe(previous,enemy.position,.002),"every ingress/approach step remains land-safe")
		if not enemy.get("counterPlan",{}).is_empty(): attack = true;break
	check(attack,"safe alternate corridor reaches actual attack")
	game.free()

func _stationary_ingress() -> void:
	var game: Node2D = _game()
	game.units = [_shooter(101,Vector2(.38,.38))]
	var enemy: Dictionary = _hunter(game,"enemy_archer",true)
	for i in range(1000):
		_tick(game,enemy)
		check(not enemy.has("ingressTargetPoint"),"stationary crew does not divert toward emplacement")
		if not bool(enemy.ingressActive): break
	check(bool(enemy.stationaryEnemy) and bool(enemy.fortification),"stationary crew settles into fortification")
	var settled: Vector2 = enemy.position
	game.units.clear()
	game._begin_hunter_return(enemy)
	for i in range(20): _tick(game,enemy)
	check(enemy.position == settled and not bool(enemy.get("hunterReturning",false)),"stationary crew stays at prepared position without target")
	game.free()

func _protected_early_stage() -> void:
	var game: Node2D = _game()
	game.roster_configured = true
	game.unlocked_roster = {"archer":true}
	game.units = [_shooter(101,Vector2(.38,.38))]
	var enemy: Dictionary = _hunter(game)
	check(str(enemy.combatRole) == Game.ENEMY_PATH_ROLE,"early roster protection converts emplacement attacker")
	check(not bool(enemy.get("ingressActive",false)),"protected hunter retains main route")
	check(game._hunter_target(enemy,.05).is_empty(),"protected shooter cannot be acquired")
	game.free()

func _forward_route_return() -> void:
	var game: Node2D = _game()
	var enemy: Dictionary = game._spawn_enemy("enemy_samurai",1)
	enemy.position = Vector2(.5,.5)
	enemy["threatAnchor"] = Vector2(.65,.5)
	enemy["pursuitRouteDistance"] = .35
	enemy["routeProgress"] = .35
	game._begin_hunter_return(enemy)
	check(float(enemy.resumeDistance) >= .35,"main-route return never chooses earlier route progress")
	for i in range(400):
		_tick(game,enemy)
		if not bool(enemy.hunterReturning): break
	check(not bool(enemy.hunterReturning),"ordinary route hunter rejoins in bounded time")
	check(float(enemy.routeProgress) >= .35,"main-route progress remains monotonic after return")
	game.free()

func _snow_phase_gate() -> void:
	var game: Node2D = _game()
	game.config.theme = "snow"
	game.config.historicalBattlefield = {"presentationWeather":{"snowCoverage":0}}
	game.storm_active = true
	for i in range(700): game._update_map_mode(.05)
	check(not game.storm_active and game.storm_clock == 0,"legacy snow theme cannot trigger spring/summer blizzard")
	game.config.historicalBattlefield.presentationWeather.snowCoverage = .5
	game._update_map_mode(20.0)
	check(game.storm_active,"explicit snow coverage retains existing storm mechanic")
	game.free()

func _ranged_ingress() -> void:
	for kind in ["enemy_archer","enemy_gunner"]:
		var game: Node2D = _game()
		game.units = [_shooter(101,Vector2(.38,.42),"gunner")]
		var enemy: Dictionary = _hunter(game,kind)
		var attacks: bool = false
		for i in range(1200):
			_tick(game,enemy)
			if not enemy.get("rangedPlan",{}).is_empty(): attacks = true;break
		check(attacks,kind+": corridor attack reaches shot preparation")
		check(enemy.position.distance_to(game.units[0].position) <= float(enemy.attackRange),kind+": actual firing range respected")
		game.units.clear()
		_tick(game,enemy)
		check(enemy.get("rangedPlan",{}).is_empty(),kind+": removed target clears pending projectile")
		for i in range(1000):
			_tick(game,enemy)
			if not bool(enemy.get("hunterReturning",false)): break
		check(not bool(enemy.get("hunterReturning",false)),kind+": ranged hunter returns without waiting on attack animation")
		game.free()

func _moved_target_grace() -> void:
	var game: Node2D = _game()
	var shooter: Dictionary = _shooter(101,Vector2(.38,.38))
	game.units = [shooter]
	var enemy: Dictionary = _hunter(game)
	for i in range(800):
		_tick(game,enemy)
		if not bool(enemy.ingressActive): break
	shooter.position = Vector2(.9,.9)
	for i in range(10): game._hunter_target(enemy,.05)
	check(not bool(enemy.get("hunterReturning",false)),"brief unreachable target preserves commitment grace")
	for i in range(10): game._hunter_target(enemy,.05)
	check(bool(enemy.get("hunterReturning",false)),"persistent out-of-leash target releases after finite grace")
	for i in range(1000):
		_tick(game,enemy)
		if not bool(enemy.get("hunterReturning",false)): break
	check(not bool(enemy.get("hunterReturning",false)),"moving target release still finishes authored return")
	game.free()
