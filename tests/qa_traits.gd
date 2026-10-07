extends SceneTree

const Battle = preload("res://native/game.gd")
var failures: Array = []
var assertions: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func make_game(stage_rule: Dictionary = {}, theme: String = "forest") -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_seed(42)
	game.load_map({"id":"traits-test","theme":theme,"initialGold":2000,"totalWaves":10,"tierIndex":0,"level":1,"difficulty":1.0,"recruitCost":60,"unitLimit":14,"trait":stage_rule,"objectives":[{"id":"main","x":0.95,"y":0.5,"hp":30}],"paths":[{"points":[[0.01,0.5],[0.5,0.5],[0.95,0.5]],"objectiveId":"main"},{"points":[[0.01,0.7],[0.5,0.7],[0.95,0.5]],"objectiveId":"main"}],"buildZones":[{"x":0.4,"y":0.36,"r":0.1},{"x":0.7,"y":0.36,"r":0.1}]})
	return game

func run() -> void:
	var baseline: Node2D = make_game()
	check(baseline.recruit() and baseline.place_unit(0.4,0.36), "Baseline unit deploys")
	baseline.start_battle()
	baseline._spawn_enemy("raider")
	var original: Dictionary = baseline._stats(baseline.units[0])
	var base_hp: float = float(baseline.enemies[0].hp)
	var base_speed: float = float(baseline.enemies[0].speed)
	var boosted: Node2D = make_game({"nameKO":"병종 집중","unitBonuses":[{"type":"archer","damageFactor":1.2,"rangeFactor":1.1,"intervalFactor":0.8}],"enemyBonuses":[{"kind":"all","hpFactor":1.15,"speedFactor":1.1}]})
	check(boosted.recruit() and boosted.place_unit(0.4,0.36), "Boosted unit deploys")
	boosted.start_battle()
	boosted._spawn_enemy("raider")
	var actual: Dictionary = boosted.snapshot().selected
	check(is_equal_approx(float(actual.damage),float(original.damage)*1.2), "Unit damage bonus changes actual and public damage")
	check(is_equal_approx(float(actual.range),float(original.range)*1.1), "Unit range bonus changes actual and public range")
	check(is_equal_approx(float(actual.interval),float(original.interval)*0.8), "Unit interval bonus changes attack timing")
	check(is_equal_approx(float(boosted.enemies[0].hp),base_hp*1.15), "Enemy HP bonus changes spawned HP")
	check(is_equal_approx(float(boosted.enemies[0].speed),base_speed*1.1), "Enemy speed bonus changes spawned speed")
	check(boosted.snapshot().traitName == "병종 집중", "Stage operation name appears in state")
	var supply: Node2D = make_game({"waveGold":{"every":2,"amount":15},"reinforcements":{"every":2,"kind":"heavy","count":2},"cycleRoutes":true})
	supply.start_battle()
	check(supply.spawn_queue.size() == 4, "Small first patrol does not receive reinforcements before their specified wave")
	supply._spawn_enemy("raider")
	check(int(supply.enemies[0].pathIndex) == 0, "First wave uses first cycling route")
	supply.spawn_queue.clear()
	supply.enemies.clear()
	var gold_before: int = supply.gold
	supply.advance_simulation(0.01)
	check(supply.gold == gold_before+43, "Ordinary wave receives only standard wave reward")
	check(supply.between_waves, "Trait support preserves quiz break between waves")
	supply.advance_simulation(0.5)
	check(supply.gold == gold_before+43, "Intermission cannot duplicate wave reward")
	supply.continue_wave()
	check(supply.wave == 2 and supply.spawn_queue.size() == 8, "Specified second wave adds two heavy reinforcements to its six-soldier patrol")
	check(str(supply.spawn_queue[-1]) == "heavy" and str(supply.spawn_queue[-2]) == "heavy", "Reinforcements use the specified enemy kind")
	supply._spawn_enemy("raider")
	check(int(supply.enemies[-1].pathIndex) == 1, "Second wave rotates actual enemy route")
	supply.spawn_queue.clear()
	supply.enemies.clear()
	gold_before = supply.gold
	supply.advance_simulation(0.01)
	check(supply.gold == gold_before+46+15, "Periodic supply adds extra gold at the correct completed wave")
	var aura_rule: Dictionary = {"auras":[{"x":0.4,"y":0.36,"r":0.15,"period":10.0,"activeSeconds":3.0,"enemySpeedFactor":0.8,"unitDamageFactor":1.2,"unitRangeFactor":1.1,"unitIntervalFactor":0.8}]}
	var area: Node2D = make_game(aura_rule)
	check(area.recruit() and area.place_unit(0.4,0.36), "Aura fixture unit deploys")
	area.start_battle()
	area._spawn_enemy("raider")
	check(bool(area.snapshot().activeAuras[0].active), "Periodic aura starts active with zero offset")
	actual = area._stats(area.units[0])
	check(is_equal_approx(float(actual.damage),float(original.damage)*1.2), "Active position aura changes actual unit damage")
	check(is_equal_approx(float(actual.range),float(original.range)*1.1), "Active position aura changes actual unit range")
	check(is_equal_approx(float(actual.interval),float(original.interval)*0.8), "Active position aura changes actual unit interval")
	var outside: Dictionary = area.units[0].duplicate(true)
	outside.position = Vector2(0.8,0.2)
	check(is_equal_approx(float(area._stats(outside).damage),float(original.damage)), "Aura leaves units outside its location unchanged")
	var moving: Dictionary = area.enemies[0]
	moving.position = Vector2(0.4,0.5)
	moving.pathIndex = 0
	moving.pointIndex = 1
	var previous: Vector2 = moving.position
	var plain_moving: Dictionary = baseline.enemies[0]
	plain_moving.position=previous
	plain_moving.pathIndex=0
	plain_moving.pointIndex=1
	baseline._move_enemy(plain_moving,0.1)
	var unmodified_displacement: float=plain_moving.position.distance_to(previous)
	area._move_enemy(moving,0.1)
	check(is_equal_approx(moving.position.distance_to(previous),unmodified_displacement*0.8), "Active aura changes actual enemy displacement relative to unmodified marching")
	area.elapsed = 3.0
	check(not bool(area.active_auras()[0].active), "Aura turns off at active-window boundary")
	check(is_equal_approx(float(area._stats(area.units[0]).damage),float(original.damage)), "Inactive aura restores ordinary unit damage")
	area.elapsed = 10.0
	check(bool(area.active_auras()[0].active), "Aura cycles back on at next period")
	area.config.trait.auras[0].phaseOffset = 3.0
	area.elapsed = 0.0
	check(not bool(area.active_auras()[0].active), "Phase offset shifts actual active interval")
	var harbor: Node2D = make_game(aura_rule,"harbor")
	harbor.start_battle()
	harbor._spawn_enemy("raider")
	moving = harbor.enemies[0]
	moving.position = Vector2(0.4,0.5)
	moving.pathIndex = 0
	moving.pointIndex = 1
	previous = moving.position
	harbor._move_enemy(moving,0.1)
	check(is_equal_approx(moving.position.distance_to(previous),unmodified_displacement*0.8*1.6), "Aura speed composes with actual marching and harbor boat speed")
	var river: Node2D = make_game({"cycleRoutes":true},"river")
	river.start_battle()
	river._spawn_enemy("raider")
	check(river.bridge_index == 0 and river.enemies[0].pathIndex == 0, "River route cycle starts at first bridge")
	river.toggle_bridge()
	river._spawn_enemy("raider")
	check(river.enemies[-1].pathIndex == 1 and river.enemies[0].pathIndex == 0, "Manual bridge switch remains functional under route-cycle trait")
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check(maps.size() == 40, "Final catalog contains forty stages")
	var signatures: Dictionary = {}
	for map_data in maps:
		var stage_rule: Dictionary = map_data.get("trait", {})
		check(not stage_rule.is_empty() and str(stage_rule.get("stageId","")) == str(map_data.id), "%s contains its own matching stage rule" % map_data.id)
		check(not signatures.has(str(stage_rule.get("id",""))), "%s has a unique operation identity" % map_data.id)
		signatures[str(stage_rule.get("id",""))] = true
	for game in [baseline,boosted,supply,area,harbor,river]:
		game.queue_free()
	print("TRAITS_QA assertions=",assertions," unique_stages=",signatures.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
