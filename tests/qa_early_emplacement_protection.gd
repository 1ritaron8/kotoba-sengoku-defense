extends "res://tests/qa_guard_combat.gd"
## Target/HP fixtures isolate the unlock rule; only starter_dispatch uses the
## actual authored 280-gold map. No fixture is presented as a campaign victory.

const OUTPUT_DIRECTORY: String = "res://tests/profiles/early-emplacement-protection"
const FIXED_TYPES: Array = ["archer", "gunner", "monk", "naginata"]
var without_guard: Array = []
var early_rows: Array = []
var starter_observation: Dictionary = {}

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	var allowed: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY).replace("\\", "/").to_lower() + "/"
	var appdata: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var local_appdata: String = OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	if not profile.begins_with(allowed) or not appdata.begins_with(allowed) or appdata != local_appdata or not profile.begins_with(appdata + "/") or DisplayServer.get_name() != "headless":
		push_error("Early protection QA requires an isolated workspace headless profile")
		quit(2)
		return
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	for id in Types:
		if str(id) != "naginata": without_guard.append(id)
	unlock_rule()
	for unit_type in FIXED_TYPES:
		target_and_damage_contract(str(unit_type))
	stale_attack_contract()
	protected_route_contract()
	starter_dispatch()
	paired_spear_price()
	# Reuse the existing real guard fixture: all-eight training must
	# still permit ordinary melee/ranged deaths of each stationary troop.
	fixed_casualties()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	var report: FileAccess = FileAccess.open(OUTPUT_DIRECTORY + "/results.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"profile":{"userData":profile,"appData":appdata,"localAppData":local_appdata},"early":early_rows,"starter":starter_observation,"staleHunterReturn":observations.get("staleHunterReturn",{}),"pairedSpearPrice":observations.get("pairedSpearPrice",[]),"lateFixedCasualties":observations.get("fixedCasualties",[]),"scope":"CPU real Game production, native target acquisition/release/projectile impact and HP damage. Guard unlock comes from configure_roster, not stage number. Role fixtures use explicit isolated budgets and unlocks, preserving authored placement geometry; they do not claim campaign balance. Actual starter dispatch retains authored 280 combat gold, Lv1, archer/spear, original map geometry and 10-minute mode. Genuine hunters are spawned while unlocked before the fixture re-locks to exercise stale attack boundaries. Late casualties use actual emplacement hunters, rather than route attackers. The authorized Lv5+ two-spear price is 90, duration remains 2.275. No damage, spawn schedule, learning reward or duration change."}, "\t"))
	report.close()
	print("EARLY_EMPLACEMENT_QA checks=", checks, " failures=", failures.size(), " starter=", JSON.stringify(starter_observation))
	quit(0 if failures.is_empty() else 1)

func unlock_rule() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	maps.sort_custom(func(a,b): return int(a.stageNumber) < int(b.stageNumber))
	for stage_index in range(6):
		var unlocked: Array = []
		for definition in catalog:
			if int(definition.unlockClears) <= stage_index: unlocked.append(str(definition.id))
		var game: Node2D = game_for({}, maps[stage_index])
		game.configure_roster(catalog, unlocked, {})
		check(game.emplacement_protection_active() == (stage_index < 5), "Actual progression uses guard unlock at stage " + str(stage_index + 1))
		check(bool(game.snapshot().emplacementProtectionActive) == game.emplacement_protection_active(), "Public protection state matches the real roster")
		for unit_type in Types:
			var probe: Dictionary = {"type":str(unit_type),"hp":10.0}
			check(game.can_enemy_target_unit(probe) == (stage_index >= 5 or str(unit_type) not in FIXED_TYPES), "Shared eligibility applies consistently to " + str(unit_type))
		for requested_kind in ["enemy_archer", "enemy_gunner", "enemy_samurai"]:
			var origin_kind: String = {"enemy_archer":"raider", "enemy_gunner":"shield", "enemy_samurai":"heavy"}[requested_kind]
			var spawned: Dictionary = game._spawn_enemy(str(requested_kind), 1, {"pathIndex":0})
			var expected_kind: String = origin_kind if stage_index < 5 else str(requested_kind)
			check(str(spawned.kind) == expected_kind and int(spawned.pathIndex) == 0, "Actual protected/unlocked spawn preserves the chosen lane and applies the authored hunter conversion")
			check(str(spawned.combatRole) == (game.ENEMY_PATH_ROLE if stage_index < 5 else game.ENEMY_EMPLACEMENT_ROLE), "Actual spawned role agrees with the real guard unlock")
			if str(requested_kind) in ["enemy_archer", "enemy_gunner"]:
				check(spawned.has("rangedPlan") == (stage_index >= 5), "Only an actual unlocked ranged hunter owns its native ranged plan")
		game.free()
	var legacy: Node2D = Battle.new()
	root.add_child(legacy)
	legacy.set_process(false)
	legacy.load_map(fixture())
	check(not legacy.emplacement_protection_active() and legacy.can_enemy_target_unit({"type":"archer","hp":10.0}), "Unconfigured legacy fixtures retain their original stationary damage")
	check(not legacy.can_enemy_target_unit({}) and not legacy.can_enemy_target_unit({"type":"spear","hp":0.0}), "Empty and dead targets are always ineligible")
	legacy.configure_roster(catalog, ["archer", "spear"], {})
	check(legacy.emplacement_protection_active(), "An actual early roster protects even a late-numbered fixture")
	legacy.configure_roster(catalog, ["archer", "spear", "naginata"], {})
	check(not legacy.emplacement_protection_active(), "The guard unlock alone removes early protection")
	legacy.free()

func target_and_damage_contract(unit_type: String) -> void:
	var game: Node2D = game_for()
	var fixed: Dictionary = produce(game, unit_type)
	check(not fixed.is_empty(), "Actual stationary production completes: " + unit_type)
	if fixed.is_empty(): game.free();return
	# Spawn actual hunter dictionaries before re-locking the fixture. Spawning
	# these names while protected intentionally produces route attackers.
	var melee: Dictionary = enemy_at(game, fixed.position + Vector2(-.026, 0), "enemy_samurai")
	var ranged_enemies: Array = []
	check(str(melee.kind) == "enemy_samurai" and str(melee.combatRole) == game.ENEMY_EMPLACEMENT_ROLE, "The damage probe is a real native emplacement hunter")
	for kind in ["enemy_archer", "enemy_gunner"]:
		var ranged: Dictionary = enemy_at(game, fixed.position + Vector2(-.07, 0), str(kind))
		check(str(ranged.kind) == str(kind) and ranged.has("rangedPlan") and str(ranged.combatRole) == game.ENEMY_EMPLACEMENT_ROLE, "The ranged probe comes from the actual unlocked spawn API")
		ranged_enemies.append(ranged)
	game.configure_roster(catalog, without_guard, {})
	var initial_hp: float = float(fixed.hp)
	var events: Array = []
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	check(not game._enemy_stationary_threat(melee, .025) and not melee.has("threatAnchor"), "Early melee never begins a protected emplacement pursuit: " + unit_type)
	melee.counterPlan = {"targetId":int(fixed.id),"releaseTime":.25,"damage":9.0}
	melee.animationClock = .30
	game.ground_combat.counterattack(melee, .025, fixed)
	check(melee.counterPlan.is_empty() and float(fixed.hp) == initial_hp, "Last-signal direct counterattack rejects the protected target: " + unit_type)
	check(game._damage_friendly(fixed, 9.0, melee) == 0.0 and float(fixed.hp) == initial_hp, "The common HP boundary rejects protected stationary damage: " + unit_type)
	for ranged in ranged_enemies:
		var kind: String = str(ranged.kind)
		ranged.animation = "walk"
		game._enemy_ranged_step(ranged, .025)
		check(ranged.rangedPlan.is_empty(), "Early " + str(kind) + " does not select " + unit_type)
		ranged.rangedPlan = {"targetId":int(fixed.id),"releaseTime":.25,"damage":9.0}
		ranged.animationClock = .30
		game._enemy_ranged_step(ranged, .025)
		check(ranged.rangedPlan.is_empty() and game.projectiles.is_empty(), "Stored illegal ranged plans never release a projectile")
		game.projectiles.append({"position":fixed.position,"targetPos":fixed.position,"targetId":int(fixed.id),"damage":9.0,"type":str(kind),"victimSide":"friendly","sourceId":int(ranged.id),"sourceActor":ranged.duplicate(true),"speed":2.7,"age":0.0})
		game._update_projectiles(.025)
		check(game.projectiles.is_empty() and float(fixed.hp) == initial_hp, "Already-flying hostile projectiles discard protected targets at impact")
	var friendly_hits: int = 0
	for event in events:
		if str(event.type) in ["shot", "hit"] and str(event.get("victimSide", "")) == "friendly": friendly_hits += 1
	check(friendly_hits == 0, "Protected release/impact has no false friendly shot or hit event")
	game.configure_roster(catalog, Types, {})
	var actual_damage: float = game._damage_friendly(fixed, 9.0, melee)
	check(actual_damage > 0.0 and float(fixed.hp) < initial_hp, "Actual guard unlock restores native armor and HP damage: " + unit_type)
	early_rows.append({"type":unit_type,"initialHP":initial_hp,"protectedHP":initial_hp,"afterUnlockHP":float(fixed.hp),"nativeDamage":actual_damage,"falseHits":friendly_hits})
	game.free()

func paired_spear_price() -> void:
	var rows: Array = []
	for level in [4, 5, 8]:
		var data: Dictionary = fixture()
		data.paths.append({"id":"second","objectiveId":"main","points":[{"x":.05,"y":.35},{"x":.95,"y":.50}]})
		var game: Node2D = game_for({"spear":level}, data)
		var expected_cost: int = 65 if level < 5 else 90
		var expected_quantity: int = 1 if level < 5 else 2
		check(game.recruit_cost("spear") == expected_cost and int(game.snapshot().recruitCosts.spear) == expected_cost, "Actual campaign-level summon cost is exposed at spear Lv" + str(level))
		var initial_gold: int = game.gold
		check(game.begin_placement("spear", 0), "The normal summon API accepts the priced spear order")
		var job: Dictionary = game.recruitment_queue[0]
		check(int(job.cost) == expected_cost and int(job.quantity) == expected_quantity and game.gold == initial_gold - expected_cost, "The spear order pays once for its actual one/two-soldier quantity")
		check(is_equal_approx(float(job.totalSeconds), 2.275), "Spear recruitment remains 2.275 seconds independent of its new price")
		check(game.cancel_recruitment(int(job.id)) and game.gold == initial_gold, "Cancelling the actual spear order refunds its full 65/90 payment")
		check(game.begin_placement("spear", 0) and game.begin_placement("spear", 1), "Two paid spear orders run in parallel on their chosen bases")
		check(game.gold == initial_gold - expected_cost * 2, "Parallel orders deduct exactly two native order prices")
		hold(game)
		for index in range(89): game.advance_simulation(.025)
		check(game.units.is_empty() and game.recruitment_queue.size() == 2, "Spear actors are absent before 2.275 seconds")
		game.advance_simulation(.025)
		check(game.units.is_empty(), "Spear actors are still absent at 2.250 seconds")
		game.advance_simulation(.025)
		check(game.units.size() == expected_quantity * 2 and game.recruitment_queue.is_empty(), "Both native parallel orders really complete at 2.275 seconds")
		var path_counts: Dictionary = {}
		for unit in game.units:
			path_counts[int(unit.postPathIndex)] = int(path_counts.get(int(unit.postPathIndex), 0)) + 1
			var expected_state: String = "gather" if level < 5 else "march"
			check(int(unit.campaignLevel) == level and str(unit.combatState) == expected_state, "A lone spear gathers; the real paid pair groups and immediately starts marching")
			if level >= 5: check(int(unit.gatherGroupId) > 0 and float(unit.gatherRemaining) == 0.0, "The two-spear order really releases its completed gathering group")
		check(int(path_counts.get(0, 0)) == expected_quantity and int(path_counts.get(1, 0)) == expected_quantity, "Each selected path receives its exact paid quantity")
		rows.append({"level":level,"cost":expected_cost,"quantity":expected_quantity,"duration":float(job.totalSeconds),"parallelBorn":game.units.size(),"gold":game.gold})
		game.free()
	observations["pairedSpearPrice"] = rows

func stale_attack_contract() -> void:
	var game: Node2D = game_for()
	var fixed: Dictionary = produce(game, "gunner", Vector2(.50, .50))
	var spear: Dictionary = produce(game, "spear")
	if fixed.is_empty() or spear.is_empty(): check(false, "Native fixed and marching actors produced for stale-attack contracts");game.free();return
	spear.position = fixed.position + Vector2(.09, 0)
	var ranged: Dictionary = enemy_at(game, fixed.position + Vector2(.01, 0), "enemy_gunner")
	var hunter: Dictionary = enemy_at(game, fixed.position + Vector2(-.05, .08), "enemy_samurai")
	game._enemy_stationary_threat(hunter, .025)
	check(str(hunter.kind) == "enemy_samurai" and int(hunter.get("stationaryTargetId", -1)) == int(fixed.id) and hunter.has("threatAnchor"), "An actual unlocked melee hunter commits to the native stationary target")
	ranged.rangedPlan = {"targetId":int(fixed.id),"releaseTime":.25,"damage":9.0}
	ranged.animationClock = .30
	game.configure_roster(catalog, without_guard, {})
	game._enemy_ranged_step(ranged, .025)
	check(int(ranged.rangedPlan.get("targetId", -1)) == int(spear.id), "An invalid stored stationary target is replaced with a living marching target")
	ranged.animationClock = .30
	game._enemy_ranged_step(ranged, .025)
	check(game.projectiles.size() == 1 and int(game.projectiles[0].targetId) == int(spear.id), "The real ranged release aims only at the eligible marching soldier")
	var spear_before: float = float(spear.hp)
	game._update_projectiles(.20)
	check(float(spear.hp) < spear_before and float(fixed.hp) == float(fixed.maxHp), "Actual hostile impact hurts marching soldiers while the emplacement stays unharmed")
	var melee: Dictionary = enemy_at(game, fixed.position + Vector2(-.01, 0), "heavy")
	melee.blockedBy = int(fixed.id)
	melee.counterPlan = {"targetId":int(fixed.id),"releaseTime":.25,"damage":9.0}
	game.ground_combat._assign_blocks()
	check(int(melee.blockedBy) == -1 and melee.counterPlan.is_empty() and not game.ground_combat.blocked(melee), "A protected fixed soldier never becomes an immortal blocker")
	melee.position = spear.position + Vector2(-.01, 0)
	game.ground_combat._assign_blocks()
	check(int(melee.blockedBy) == int(spear.id) and game.ground_combat.blocked(melee), "Marching infantry still really block the same enemy")
	melee.counterPlan = {"targetId":int(spear.id),"releaseTime":.25,"damage":9.0}
	melee.animationClock = .30
	spear_before = float(spear.hp)
	game.ground_combat.counterattack(melee, .025)
	check(float(spear.hp) < spear_before, "The blocked enemy really retaliates against marching infantry")
	hunter.counterPlan = {"targetId":int(fixed.id),"releaseTime":.25,"damage":9.0}
	var pursuit_position: Vector2 = hunter.position
	game._move_enemy(hunter, .025)
	check(int(hunter.stationaryTargetId) == -1 and hunter.counterPlan.is_empty() and hunter.rangedPlan.is_empty() and bool(hunter.get("hunterReturning", false)), "The stale native hunter clears every protected target and starts a physical route return")
	check(hunter.position.distance_to(pursuit_position) <= float(hunter.speed) * game.ENGAGED_MARCH_FACTOR * .025 + .00001, "The first route-return step never teleports to its anchor")
	var resume_point: Vector2 = hunter.resumePoint
	var return_steps: Array = []
	for index in range(600):
		if not bool(hunter.get("hunterReturning", false)): break
		var previous: Vector2 = hunter.position
		game._move_enemy(hunter, .025)
		check(game.ground_combat.land_segment_safe(previous, hunter.position), "Stale hunter return remains on legal land")
		var native_step: float = float(hunter.speed) * game.ENGAGED_MARCH_FACTOR * .025
		# Native arrival snaps only after the remaining distance is below
		# 0.0001 (squared 0.00000001). Ongoing steps keep the strict speed cap.
		var arrival_snap: float = .0001 if not bool(hunter.get("hunterReturning", false)) else 0.0
		check(hunter.position.distance_to(previous) <= native_step + arrival_snap + .00001, "Stale hunter return keeps native speed, with only the defined final-arrival epsilon")
		return_steps.append({"from":game._normalized_position(previous),"to":game._normalized_position(hunter.position),"distance":hunter.position.distance_to(previous),"nativeSpeedStep":native_step,"arrivalEpsilon":arrival_snap})
	check(not bool(hunter.get("hunterReturning", false)) and int(hunter.stationaryTargetId) == -1 and hunter.counterPlan.is_empty() and not hunter.has("threatAnchor") and hunter.position.distance_to(resume_point) < .00001, "A stale emplacement pursuit physically rejoins its original route and removes the pursuit anchor")
	observations["staleHunterReturn"] = {"start":game._normalized_position(pursuit_position),"routeAnchor":game._normalized_position(resume_point),"end":game._normalized_position(hunter.position),"steps":return_steps}
	game.free()

func protected_route_contract() -> void:
	var game: Node2D = game_for()
	var bow: Dictionary = produce(game, "archer", Vector2(.50, .65))
	if bow.is_empty(): check(false, "Route protection bow really produced");game.free();return
	game.configure_roster(catalog, ["archer", "spear"], {})
	var enemy: Dictionary = enemy_at(game, Vector2(.50, .50), "raider")
	var before: Vector2 = enemy.position
	game._move_enemy(enemy, .10)
	check(enemy.position.x > before.x and is_equal_approx(enemy.position.y, before.y) and not enemy.has("threatAnchor"), "Protected bows do not divert or stop the enemy's authored route")
	var objective_before: int = int(game.objectives[0].hp)
	game._escape_enemy(enemy, "main")
	check(int(game.objectives[0].hp) == objective_before - int(enemy.damage), "Protected emplacements never protect the objective from a real escape")
	game.free()

func starter_dispatch() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	maps.sort_custom(func(a,b): return int(a.stageNumber) < int(b.stageNumber))
	var game: Node2D = game_for({}, maps[0])
	game.configure_roster(catalog, ["archer", "spear"], {})
	game.load_map(maps[0], 10)
	check(str(game.config.id) == "basic-forest" and game.gold == 280 and game.config == maps[0], "Starter dispatch uses the actual untouched first-map dictionary and wallet")
	check(game.begin_placement("spear", 0) and game.begin_placement("spear", mini(1,game.paths.size()-1)), "Two ordinary spear orders accept an actual paid base dispatch")
	check(game.pending.is_empty() and not game.placement_cursor_visible and game.recruitment_queue.size() == 2 and game.gold == 150, "Marching orders charge 65 each, show no placement cursor and create parallel production")
	check(game.units.is_empty(), "Marching actors are not fabricated before their production timers")
	game.start_battle()
	for index in range(100): game.advance_simulation(.025)
	check(game.units.size() == 2 and game.recruitment_queue.is_empty(), "Both real spear timers finish within 2.5 combat seconds")
	var spawn_rows: Array = []
	for unit in game.units:
		check(str(unit.type) == "spear" and int(unit.campaignLevel) == 1 and str(unit.combatState) in ["gather","march"], "A real level-one soldier uses its selected base and native gathering/departure state")
		check(unit.position.distance_to(unit.basePosition) < .04, "The produced marching model is at the real selected base")
		spawn_rows.append({"id":int(unit.id),"pathIndex":int(unit.postPathIndex),"birthRouteDistance":float(unit.routeDistance),"base":game._normalized_position(unit.basePosition),"state":str(unit.combatState)})
	for index in range(220): game.advance_simulation(.025)
	for row in spawn_rows:
		var unit: Dictionary = game.ground_combat._unit(int(row.id))
		check(not unit.is_empty() and float(unit.routeDistance) < float(row.birthRouteDistance), "Each actual soldier leaves its base after gathering and proceeds up its authored path")
		if not unit.is_empty(): row.merge({"routeDistance":float(unit.routeDistance),"stateAfter":str(unit.combatState),"animation":str(unit.animation),"position":game._normalized_position(unit.position)}, true)
	check(game.gold == 150 and game.emplacement_protection_active(), "Starter output receives no injected supply, costs or guard unlock")
	starter_observation = {"mapId":str(game.config.id),"modeMinutes":game.battle_minutes,"elapsed":game.elapsed,"initialGold":280,"paid":130,"gold":game.gold,"protectionActive":game.emplacement_protection_active(),"spawns":spawn_rows,"finished":game.finished,"scope":"Real first-map opening only; no battle-win claim and no enemy/HP/money injection"}
	game.free()
