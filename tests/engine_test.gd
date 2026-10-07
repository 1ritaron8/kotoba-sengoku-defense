extends SceneTree

const Battle = preload("res://native/game.gd")
var failures: Array = []
var maps: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func make_game(map_data: Dictionary, seed_value: int = 1234) -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_seed(seed_value)
	game.load_map(map_data)
	return game

func run() -> void:
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check(maps.size() == 40, "There must be 40 maps")
	var game: Node2D = make_game(maps[0])
	var initial_gold: int = game.gold
	check(game.recruit(), "Initial recruit succeeds")
	check(game.gold == initial_gold - 60, "Recruit cost debited exactly once")
	check(not game.recruit(), "Cannot overwrite a pending recruit")
	check(not game.place_unit(0,0), "Out of zone placement rejected")
	check(game.gold == initial_gold - 60, "Invalid placement does not debit again")
	game.cancel_recruit()
	check(game.gold == initial_gold, "Cancel refunds pending recruit")
	check(game.recruit(), "Can recruit after cancel")
	check(place_best(game), "Valid deployment succeeds")
	var before: int = game.gold
	game.grant_reward("correct")
	check(game.gold == before + 70, "Correct reward is 70")
	game.grant_reward("hinted")
	check(game.gold == before + 95, "Hinted reward is 25")
	game.start_battle()
	game.pause_battle()
	game.advance_simulation(10)
	check(game.elapsed == 0, "Paused simulation does not advance")
	game.pause_battle()
	game.advance_simulation(1)
	check(game.elapsed == 1, "Resumed simulation advances")
	game.queue_free()
	test_map_modes()
	var defense: Node2D = make_game(maps[0])
	defense.start_battle()
	for i in range(5000):
		if defense.finished: break
		if defense.between_waves: defense.continue_wave()
		defense.advance_simulation(.25)
	check(defense.finished and not defense.victory, "Undefended map reaches defeat")
	defense.queue_free()
	var passed: int = 0
	var tested: int = 0
	var filter_theme: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var battle_maps: Array = maps
	if args.size() == 2 and args[0] == "--catalog":
		battle_maps = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	elif not args.is_empty():
		filter_theme = str(args[0])
	for map_data in battle_maps:
		if not filter_theme.is_empty() and str(map_data.theme) != filter_theme: continue
		tested += 1
		var current: Node2D = make_game(map_data, 9876)
		var steps: int = 0
		deploy_units(current)
		current.start_battle()
		while not current.finished and steps < 16000:
			if current.between_waves:
				current.grant_reward("correct")
				deploy_units(current)
				current.continue_wave()
			elif steps % 20 == 0:
				deploy_units(current)
			current.advance_simulation(.25)
			steps += 1
		check(current.finished, "Map completes within simulation limit: %s" % map_data.id)
		if current.victory: passed += 1
		print("BATTLE ", map_data.id, " victory=",current.victory," hp=",current.snapshot().hp," waves=",current.wave," kills=",current.kills," seconds=",int(current.elapsed))
		current.queue_free()
	print("ENGINE_TEST maps_won=",passed,"/",tested," failures=",failures.size())
	quit(0 if failures.is_empty() and passed == tested else 1)

func test_map_modes() -> void:
	var river: Node2D = make_game(maps[3])
	river.start_battle()
	river._spawn_enemy("raider")
	check(int(river.enemies[0].pathIndex) == 0, "Initial bridge uses upper route")
	river.toggle_bridge()
	river._spawn_enemy("raider")
	check(int(river.enemies[1].pathIndex) == 1, "Bridge switch changes incoming route")
	check(int(river.enemies[0].pathIndex) == 0, "Bridge switch preserves existing enemy path")
	river.toggle_bridge()
	check(river.bridge_index == 1, "Bridge cooldown prevents repeated switch")
	river.queue_free()
	var escort: Node2D = make_game(maps[5])
	check(escort.config.escortRoute[0] == escort.config.escortRoute[-1], "Escort route closes without teleport")
	escort.start_battle()
	var old_pos: Vector2 = escort.objectives[0].position
	escort.advance_simulation(10)
	check(escort.objectives[0].position != old_pos, "Escort objective moves")
	escort.queue_free()
	var temple: Node2D = make_game(maps[6])
	check(temple.recruit(), "Temple recruit")
	check(place_best(temple), "Temple deploy")
	var low: Dictionary = temple.units[0].duplicate(true)
	low.elevation = 0
	var high: Dictionary = low.duplicate(true)
	high.elevation = 2
	check(temple._stats(high).range > temple._stats(low).range, "Elevated terrain increases range")
	temple.queue_free()
	var snow: Node2D = make_game(maps[7])
	snow.start_battle()
	snow._update_map_mode(20)
	check(snow.storm_active, "Snow storm starts")
	snow._update_map_mode(7)
	check(not snow.storm_active, "Snow storm ends")
	snow.queue_free()
	var night: Node2D = make_game(maps[8])
	var shadow: Dictionary = {"position":Vector2(.02,.02)}
	var lit: Dictionary = {"position":night._point(night.config.torches[0])}
	check(not night._enemy_visible(shadow), "Unlit enemies are outside targeting visibility")
	check(night._enemy_visible(lit), "Torch reveals enemies")
	night.queue_free()
	var reset_game: Node2D = make_game(maps[0],22)
	reset_game.recruit()
	place_best(reset_game)
	reset_game.start_battle()
	reset_game.advance_simulation(5)
	reset_game.load_map(maps[0])
	check(reset_game.wave == 0 and reset_game.units.is_empty() and reset_game.enemies.is_empty() and reset_game.gold == int(maps[0].initialGold), "Reload resets full battle state")
	check(JSON.stringify(reset_game.snapshot()).length() > 10, "Snapshot is JSON serializable")
	reset_game.queue_free()

func deploy_units(game: Node2D) -> void:
	var guard: int = 0
	while game.gold >= 60 and game.units.size() < int(game.config.get("unitLimit",14)) and guard < 30:
		guard += 1
		if not game.recruit(): break
		if not place_best(game):
			game.cancel_recruit()
			break

func place_best(game: Node2D) -> bool:
	var best: Vector2 = Vector2(-1,-1)
	var score_best: float = -INF
	var samples: Array = []
	for route in game.paths:
		for i in range(route.points.size()-1):
			for j in range(8):
				samples.append(route.points[i].lerp(route.points[i+1],j/8.0))
	var attack_range: float = .205 if str(game.pending.get("type","")) == "archer" else .19 if str(game.pending.get("type","")) == "commander" else .145
	for build_zone in game.zones:
		for xx in range(-3,4):
			for yy in range(-3,4):
				var p: Vector2 = build_zone.position + Vector2(xx,yy) * .018
				if game._eligible_zone(p).is_empty(): continue
				var occupied: bool = false
				for unit in game.units:
					if p.distance_to(unit.position) < .055: occupied = true
				if occupied: continue
				var score: float = 0
				for sample in samples:
					if p.distance_to(sample) < attack_range:
						var covered: float = 1
						for unit in game.units:
							if unit.position.distance_to(sample) < .15: covered += .40
							score += 1/covered
				if score > score_best:
					score_best = score
					best = p
	if best.x < 0: return false
	return game.place_unit(best.x,best.y)
