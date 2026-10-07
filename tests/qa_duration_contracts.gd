extends SceneTree
## Independent duration boundary/clock/economy verification. Production is untouched.
const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
const MODES = [5, 10, 20]
const MAP_HASH = "22e40dad8175e20e3293a26a17bad478d9f927fa5d8d1dd8f3df972f158dffbf"
var checks: int = 0
var failures: Array = []
var observations: Array = []
var maps: Array = []
var app: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		if failures.size() <= 30: push_error("DURATION CONTRACT: " + note)

func argument(key: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if str(value).begins_with(key + "="): return str(value).get_slice("=", 1)
	return fallback

func digest(path: String) -> String:
	if not FileAccess.file_exists(path): return "packed-compiled-or-unavailable"
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()

func serialized_equal(left: Variant, right: Variant) -> bool:
	# Saved JSON numbers may read back as float rather than int. Compare the
	# complete round-tripped data, retaining every key, value and counter.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func make_battle(stage: Dictionary, minutes: int, durable: bool = false) -> Node2D:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_process(false)
	var config: Dictionary = stage.duplicate(true)
	if durable:
		for objective in config.objectives: objective.hp = 1000000
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var ids: Array = []
	for definition in catalog: ids.append(definition.id)
	battle.configure_roster(catalog, ids, {})
	battle.load_map(config, minutes)
	battle.set_seed(731)
	return battle

func signature(b: Node2D) -> Dictionary:
	# Cosmetic corpses may finish falling during intermission; live clocks cannot.
	return {"elapsed":b.elapsed, "animation":b.animation_time, "waveTime":b.wave_time, "wave":b.wave, "units":b.units.duplicate(true), "enemies":b.enemies.duplicate(true), "projectiles":b.projectiles.duplicate(true), "supports":b.learning_supports.duplicate(true), "attempts":b.learning_attempts.duplicate(true), "objectives":b.objectives.duplicate(true), "queue":b.spawn_queue.duplicate(true), "sources":b.spawn_source_waves.duplicate(true), "spawnClock":b.spawn_clock, "gold":b.gold, "kills":b.kills, "rng":b.rng.state, "storm":b.storm_clock, "escort":b.escort_distance, "refills":b.battle_refill_count, "refillClock":b.battle_refill_clock}

func frozen(battle: Node2D, note: String) -> void:
	var before: Dictionary = signature(battle)
	for unused in range(4):
		battle._process(0.25)
		battle.advance_simulation(5.0)
	check(signature(battle) == before, note)

func place_first(battle: Node2D, id: String) -> Dictionary:
	check(battle.begin_placement(id), "Selected paid recruitment begins: " + id)
	for hint in battle.placement_hints:
		if hint.x >= 0 and battle.place_unit(hint.x, hint.y): return battle.units.back()
	check(false, "Legal authored placement exists: " + id)
	return {}

func plans() -> void:
	check(digest("res://native/maps.json") == MAP_HASH and maps.size() == 40, "Modes preserve the exact authored forty-map file")
	var ids: Dictionary = {}
	var geometry: Dictionary = {}
	for stage in maps:
		ids[str(stage.id)] = true
		geometry[JSON.stringify({"paths":stage.paths, "objectives":stage.objectives, "zones":stage.buildZones, "tactics":stage.get("tactics", {}), "trait":stage.get("trait", {})}).sha256_text()] = true
		var original: Dictionary = stage.duplicate(true)
		var legacy: Node2D = make_battle(stage, 0)
		var base: Array = legacy._build_wave_schedule()
		check(legacy.snapshot().battleMode == "legacy_waves" and legacy.total_waves == int(stage.totalWaves), str(stage.id) + ": explicit legacy remains compatible")
		for minutes in MODES:
			var b: Node2D = make_battle(stage, minutes)
			var p: Dictionary = b.battle_plan
			check(stage == original and b.config == original, str(stage.id) + ": loading a mode preserves geometry and traits")
			check(float(p.targetSeconds) == minutes * 60.0 and int(p.totalWaves) == (11 if minutes == 5 else 21 if minutes == 10 else 41), str(stage.id) + ": target and virtual wave count match the mode")
			check(p.waves[0].entries == base[0] and p.waves[1].entries == base[1] and float(p.waves[0].endSeconds) == 20.0 and float(p.waves[1].endSeconds) == 45.0, str(stage.id) + ": original opening roster and time windows survive expansion")
			var end: float = 0.0
			var valid: bool = true
			for w in p.waves:
				valid = valid and absf(float(w.startSeconds) - end) < 0.000001 and float(w.endSeconds) > end and int(w.activeCap) <= 36 and int(w.activeCap) > 0 and int(w.refillCount) <= 8 and int(w.sourceWave) <= int(stage.totalWaves) and w.entries == base[int(w.baseIndex)]
				end = float(w.endSeconds)
				for entry in w.entries:
					valid = valid and int(entry.sourceWave) >= 1 and int(entry.sourceWave) <= int(stage.totalWaves)
			check(valid and absf(end - minutes * 60.0) < 0.000001, str(stage.id) + ": contiguous finite windows preserve bounded original source difficulty")
			check(int(p.waves[0].activeCap) == 8 and int(p.waves[1].activeCap) == 12 and int(p.waves[7].baseIndex) == base.size() - 1, str(stage.id) + ": opening stays small and dense late roster arrives by wave eight")
			b.free()
		legacy.free()
	check(ids.size() == 40 and geometry.size() == 40, "All forty identities and geometry/trait combinations stay distinct")
	for invalid in [-20, -1, 1, 7, 15, 1000]:
		var b: Node2D = make_battle(maps[0], invalid)
		check(int(b.snapshot().battleMinutes) == 5, "Invalid nonzero minutes fall back to five: " + str(invalid))
		b.free()
	observations.append({"probe":"plans", "maps":ids.size(), "uniqueGeometry":geometry.size(), "sha256":digest("res://native/maps.json")})

func boundaries() -> void:
	var b: Node2D = make_battle(maps[0], 5, true)
	var ended: Array = []
	b.wave_ended.connect(func(info: Dictionary): ended.append(info.duplicate(true)))
	var archer: Dictionary = place_first(b, "archer")
	var spear: Dictionary = place_first(b, "spear")
	b.start_battle()
	b._spawn_enemy("shield", 1)
	var enemy: Dictionary = b.enemies.back()
	enemy.hp = 1000.0
	enemy.maxHp = 1000.0
	enemy.speed = 0.0
	for unused in range(20):
		enemy.position = spear.position + Vector2(0.02, 0)
		b.advance_simulation(0.05)
		if int(enemy.get("blockedBy", -1)) == int(spear.id): break
	check(int(enemy.get("blockedBy", -1)) == int(spear.id), "Boundary fixture establishes a real frontline block")
	b._release_unit_attack(archer, {"targetId":enemy.id, "damage":float(b._stats(archer).damage)})
	check(not b.projectiles.is_empty(), "Boundary fixture contains an actual engine-created projectile")
	check(bool(b.apply_learning_support(archer.position, false, "duration-boundary-support").ok), "Boundary fixture registers actual learning support")
	var remaining: float = float(b.learning_supports[0].remaining)
	var wallet: int = b.gold
	b._complete_wave()
	check(b.gold == wallet and ended.is_empty() and not b.between_waves, "Early clears cannot finish a timed window or grant its stipend")
	b.elapsed = 19.999
	b.wave_time = 19.999
	b.advance_simulation(0.5)
	check(b.between_waves and absf(b.elapsed - 20.0) < 0.000001 and ended.size() == 1, "Large delta splits at the first deadline exactly once")
	check(not b.projectiles.is_empty() and int(b.projectiles[0].targetId) == int(enemy.id), "Learning preserves the actual in-flight attack")
	check(int(enemy.get("blockedBy", -1)) == int(spear.id) and not b.enemies.is_empty(), "Learning preserves live enemy identity and its engaged block")
	check(absf(float(b.learning_supports[0].remaining) - remaining + 0.001) < 0.00001, "Only consumed combat time reduces support across a split")
	wallet = b.gold
	for unused in range(4): b._complete_wave()
	check(b.gold == wallet and ended.size() == 1, "Duplicate completion cannot duplicate gold or learning")
	frozen(b, "Intermission freezes every live clock, target, projectile and support")
	b.continue_wave()
	check(b.wave == 2 and int(enemy.get("blockedBy", -1)) == int(spear.id), "Learning return retains the block and advances one window")
	b.continue_wave()
	check(b.wave == 2 and b.gold == wallet, "Repeated return cannot skip windows or grant another stipend")
	b.pause_battle()
	frozen(b, "Explicit pause freezes the full live simulation")
	b.pause_battle()
	for value in [0.0, -0.5]:
		var before: Dictionary = signature(b)
		b._process(value)
		b.advance_simulation(value)
		check(before == signature(b), "Zero/negative deltas cannot rewind or consume support")
	observations.append({"probe":"boundaries", "blockedEnemy":enemy.id, "waveSignals":ended.size(), "gold":wallet})
	b.free()
	for minutes in MODES:
		for defeat in [false, true]:
			var endpoint: Node2D = make_battle(maps[0], minutes, true)
			var ends: Array = []
			endpoint.battle_finished.connect(func(info: Dictionary): ends.append(info.duplicate(true)))
			endpoint.start_battle()
			endpoint.wave = endpoint.total_waves
			endpoint.elapsed = minutes * 60.0 - 0.001
			endpoint.wave_time = float(endpoint.battle_plan.waves.back().endSeconds) - float(endpoint.battle_plan.waves.back().startSeconds) - 0.001
			if defeat:
				endpoint._spawn_enemy("raider", 1)
				var escaping: Dictionary = endpoint.enemies.back()
				var route: Dictionary = endpoint.paths[int(escaping.pathIndex)]
				escaping.pointIndex = route.points.size() - 1
				escaping.position = route.points.back()
				endpoint._objective(str(route.objectiveId)).hp = 1
			endpoint.advance_simulation(5.0)
			check(endpoint.finished and endpoint.victory == (not defeat) and ends.size() == 1, str(minutes) + "m: objective death takes priority on the final combat step")
			check(absf(endpoint.elapsed - minutes * 60.0) < 0.000001, str(minutes) + "m: final time does not overshoot")
			var final: Dictionary = signature(endpoint)
			for unused in range(3):
				endpoint.advance_simulation(20.0)
				endpoint._complete_wave()
				endpoint.continue_wave()
				endpoint.start_battle()
			check(ends.size() == 1 and signature(endpoint) == final, str(minutes) + "m: repeated final inputs cannot restart or duplicate rewards")
			endpoint.free()

func cap_pressure() -> void:
	var b: Node2D = make_battle(maps[0], 20, true)
	b.start_battle()
	b.wave = 7
	b.elapsed = float(b.battle_plan.waves[7].startSeconds)
	b.spawn_queue.clear()
	b.spawn_source_waves.clear()
	b._begin_wave()
	var cap: int = int(b.battle_plan.waves[7].activeCap)
	for unused in range(cap):
		b._spawn_enemy("shield", 1)
		b.enemies.back().speed = 0.0
	var before_id: int = b.next_id
	b.advance_simulation(5.0)
	check(b.enemies.size() == cap and b.next_id == before_id and not b.spawn_queue.is_empty(), "Filled late cap blocks growth while retaining pending enemies")
	for index in range(cap / 2): b.enemies[index].hp = 0.0
	b.advance_simulation(0.05)
	var burst: int = b.next_id - before_id
	check(burst <= 1 and b.enemies.size() <= cap, "Opening slots after five capped seconds releases one paced spawn")
	b.elapsed = float(b.battle_plan.waves[7].endSeconds) - 0.001
	b.advance_simulation(0.5)
	var queue: Array = b.spawn_queue.duplicate()
	var sources: Array = b.spawn_source_waves.duplicate()
	var living: Array = []
	for enemy in b.enemies: living.append(enemy.id)
	b.continue_wave()
	var after: Array = []
	for enemy in b.enemies: after.append(enemy.id)
	check(b.spawn_queue.slice(0, queue.size()) == queue and b.spawn_source_waves.slice(0, sources.size()) == sources and living == after, "Learning return preserves living enemies and ordered source-wave backlog")
	observations.append({"probe":"cap-pressure", "cap":cap, "burst":burst, "pending":queue.size(), "carried":living.size()})
	b.free()

func clock(minutes: int, multiplier: float) -> void:
	var index: int = 0 if minutes == 5 else 10 if minutes == 10 else 30
	var b: Node2D = make_battle(maps[index], minutes, true)
	var ends: Array = []
	var windows: Array = []
	b.battle_finished.connect(func(info: Dictionary): ends.append(info.duplicate(true)))
	b.wave_ended.connect(func(info: Dictionary): windows.append({"wave":info.wave, "elapsed":b.elapsed}))
	b.set_speed(multiplier)
	b.start_battle()
	var active_wall: float = 0.0
	var pause_wall: float = 0.0
	var peak: int = 0
	var excessive: bool = false
	var invalid_source: bool = false
	var frames: int = 0
	var pause_checked: bool = false
	while not b.finished and frames < 10000:
		if b.between_waves:
			var elapsed: float = b.elapsed
			var gold: int = b.gold
			frozen(b, "Real learning intermission freezes the active clock")
			pause_wall += 1.0
			b.continue_wave()
			var wave: int = b.wave
			b.continue_wave()
			check(b.wave == wave and b.gold == gold and b.elapsed == elapsed, "Repeated continuation changes neither clock nor economy")
		if not pause_checked and b.elapsed >= 0.5:
			check(bool(b.apply_learning_support(Vector2(0.5, 0.5), false, "duration-clock-support").ok), "Clock fixture activates actual support")
			b.pause_battle()
			frozen(b, "Actual process pause freezes combat and support")
			pause_wall += 1.0
			b.pause_battle()
			pause_checked = true
		var deadline: float = float(b.battle_plan.waves[b.wave - 1].endSeconds)
		var delta: float = minf(0.25, maxf(0.000001, deadline - b.elapsed) / multiplier)
		b._process(delta)
		active_wall += delta
		frames += 1
		peak = maxi(peak, b.enemies.size())
		excessive = excessive or b.enemies.size() > int(b.battle_plan.waves[b.wave - 1].activeCap)
		for enemy in b.enemies:
			invalid_source = invalid_source or int(enemy.sourceWave) > int(maps[index].totalWaves) or int(enemy.sourceWave) < 1
	check(b.finished and b.victory and ends.size() == 1, str(minutes) + "m/" + str(multiplier) + "x: actual process reaches one surviving finish")
	check(absf(b.elapsed - minutes * 60.0) < 0.00001 and absf(active_wall - minutes * 60.0 / multiplier) < 0.0001, str(minutes) + "m/" + str(multiplier) + "x: promised frame time excludes pauses and learning")
	check(not excessive and not invalid_source and b.learning_supports.is_empty(), "Timed combat keeps population and source-wave HP bounded and expires support")
	check(windows.size() == b.total_waves - 1 and b.battle_refill_count > 0, "Pulse refills sustain combat without extra questions or final learning")
	observations.append({"probe":"actual-clock", "map":maps[index].id, "minutes":minutes, "speed":multiplier, "elapsed":b.elapsed, "activeFrameSeconds":active_wall, "excludedPausedFrameSeconds":pause_wall, "windows":windows.size(), "peak":peak, "refills":b.battle_refill_count, "spawns":b.next_id - 1, "frames":frames, "scope":"Actual _process/combat and authored routes/traits. Increased objective durability isolates timing; no campaign balance or real wall-clock waiting claim."})
	print("DURATION_CLOCK_QA ", JSON.stringify(observations.back()))
	b.free()

func difficulty_contact() -> void:
	var level: int = int(maps[0].totalWaves)
	var cases: Array = []
	var legacy: Node2D = make_battle(maps[0], 0)
	var timed: Node2D = make_battle(maps[0], 20)
	var legacy_unit: Dictionary = place_first(legacy, "spear")
	var timed_unit: Dictionary = place_first(timed, "spear")
	legacy.start_battle()
	timed.start_battle()
	legacy.advance_simulation(1.0)
	timed.advance_simulation(1.0)
	legacy.wave = level
	timed.wave = timed.total_waves
	for kind in ["raider", "shield", "runner", "heavy", "commander"]:
		legacy._spawn_enemy(kind, level)
		timed._spawn_enemy(kind, level)
		var old: Dictionary = legacy.enemies.back()
		var late: Dictionary = timed.enemies.back()
		var match_stats: bool = true
		for key in ["hp", "maxHp", "speed", "armor", "damage", "reward"]:
			match_stats = match_stats and late[key] == old[key]
		check(match_stats, "Virtual wave forty-one retains original source difficulty: " + kind)
		old.blockedBy = legacy_unit.id
		late.blockedBy = timed_unit.id
		legacy_unit.hp = legacy_unit.maxHp
		timed_unit.hp = timed_unit.maxHp
		legacy.ground_combat.counterattack(old, 0.0)
		timed.ground_combat.counterattack(late, 0.0)
		old.animationClock = 0.3
		late.animationClock = 0.3
		legacy.ground_combat.counterattack(old, 0.0)
		timed.ground_combat.counterattack(late, 0.0)
		var old_damage: float = float(legacy_unit.maxHp) - float(legacy_unit.hp)
		var late_damage: float = float(timed_unit.maxHp) - float(timed_unit.hp)
		check(old_damage > 0.0 and absf(late_damage - old_damage) < 0.000001, "Actual late counterattack damage follows source wave rather than virtual forty-one: " + kind)
		cases.append({"kind":kind, "hp":late.maxHp, "sourceWave":level, "virtualWave":timed.wave, "actualCounterDamage":late_damage})
	observations.append({"probe":"source-difficulty", "cases":cases})
	legacy.free()
	timed.free()

func settle_learning() -> void:
	for unused in range(12):
		if not app.learning_transition.is_busy(): break
		if app.learning_transition.animation != null and app.learning_transition.animation.is_valid():
			app.learning_transition.animation.custom_step(1.0)
		await process_frame
	check(not app.learning_transition.is_busy(), "Actual learning controller reaches its input-ready or returned state")

func main_integration() -> void:
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://duration-contracts-main-%d.json" % Time.get_ticks_msec()
	app.progress.data.settings.voice = false
	app.progress.data.settings.music = false
	check(app.progress.write_save(), "Fresh isolated app profile is persisted before startup")
	root.add_child(app)
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.player.stop()
	await process_frame
	check(app.progress.data.learning.attempts.is_empty() and app.progress.data.maps.is_empty(), "Isolated app starts without previous learning receipts or clear rewards")
	var completed: int = 0
	var task_ids: Dictionary = {}
	var cases: Array = []
	for minutes_arg in argument("--main-modes", "20,5,10").split(",", false):
		var minutes: int = int(minutes_arg)
		# Select five first to probe a later briefing change at the actual start.
		app._choose_battle_minutes(5 if completed == 0 else minutes)
		app._select_tier(0)
		app._select_map(0)
		app.game.set_process(false)
		if completed == 0:
			check(int(app.game.snapshot().battleMinutes) == 5, "Map preview initially loads the earlier five-minute selection")
			app._choose_battle_minutes(minutes)
		app._begin_battle()
		app.game.set_process(false)
		check(app.active_battle_minutes == minutes and int(app.game.snapshot().battleMinutes) == minutes and int(app.game.snapshot().battleTargetSeconds) == minutes * 60, "Actual sortie reloads a changed briefing selection: " + str(minutes))
		var locked: int = app.battle_minutes
		app._choose_battle_minutes(10 if minutes != 10 else 20)
		check(app.battle_minutes == locked, "An active sortie cannot change its timer setting")
		app.game._process(0.2)
		var elapsed: float = app.game.elapsed
		app._show_study()
		check(app.modal_context == "study" and app.game.paused, "Opening the actual dictionary pauses active timed combat")
		frozen(app.game, "Dictionary waiting excludes all live simulation and support time")
		app._return_from_study()
		check(not app.game.paused and app.game.elapsed == elapsed, "Dictionary return resumes the same elapsed combat time")
		app.game.elapsed = 19.999
		app.game.wave_time = 19.999
		app.game.advance_simulation(0.1)
		await settle_learning()
		var task: Dictionary = app.quiz_task.duplicate(true)
		check(not task.is_empty() and app.context_task_active, "A real timed deadline issues the authored first-wave context task")
		if task.is_empty(): break
		check(not task_ids.has(str(task.id)), "Retrying in another mode issues a unique learning transaction")
		task_ids[str(task.id)] = true
		frozen(app.game, "Actual context choice excludes learning waiting time")
		var gold: int = app.game.gold
		var receipts: int = app.progress.data.learning.attempts.size()
		app._answer_context(str(task.answerId))
		await settle_learning()
		check(app.quiz_resolved and app.answers_correct == 1 and app.game.gold == gold + 70, "An unhinted correct actual context answer grants one supply reward")
		check(app.progress.data.learning.attempts.size() > receipts and app.game.learning_supports.size() == 1, "Saved learning receipts precede one actual battlefield support")
		var rewarded: Dictionary = signature(app.game)
		var learned: Dictionary = app.progress.data.learning.duplicate(true)
		for unused in range(3): app._answer_context(str(task.answerId))
		check(signature(app.game) == rewarded and app.progress.data.learning == learned, "Repeated answer input cannot duplicate support, supplies or learning records")
		app._continue_battle()
		await settle_learning()
		check(app.quiz_task.is_empty() and app.game.wave == 2 and not app.game.between_waves and absf(app.game.elapsed - 20.0) < 0.000001, "Animated learning return resumes exactly one next window")
		var returned: Dictionary = signature(app.game)
		app._finish_continue_battle()
		check(signature(app.game) == returned, "Repeated return callback cannot consume another window or reward")
		var support_before: float = float(app.game.learning_supports[0].remaining)
		app.game._process(0.1)
		check(absf(float(app.game.learning_supports[0].remaining) - support_before + 0.1) < 0.000001, "Returned support consumes only actual resumed combat time")
		# Terminal fixture tests final signal / app receipts, not campaign balance.
		app.game.wave = app.game.total_waves
		app.game.elapsed = minutes * 60.0 - 0.001
		app.game.wave_time = float(app.game.battle_plan.waves.back().endSeconds) - float(app.game.battle_plan.waves.back().startSeconds) - 0.001
		var currency_before: int = int(app.progress.data.army.currency)
		app.game.advance_simulation(0.1)
		var reward: Dictionary = app.last_campaign_reward.duplicate(true)
		var map_id: String = str(app.current_map.id)
		var expected_reward: int = (140 + int(app.current_map.stageNumber) * 8 if completed == 0 else 40 + int(app.current_map.stageNumber) * 2) + 5
		completed += 1
		check(app.battle_finished and app.last_victory and app.modal_context == "result" and app.game.elapsed == minutes * 60.0, "Actual timed finish reaches the app result exactly: " + str(minutes))
		check(bool(reward.get("firstClear", false)) == (completed == 1) and int(reward.get("currency", -1)) == expected_reward and int(app.progress.data.army.currency) == currency_before + expected_reward, "First-clear funding is keyed by map and later modes receive the repeat amount")
		check(int(app.progress.data.maps[map_id].wins) == completed and app.progress.data.maps.size() == 1, "Changing mode records a new win under the original map identity")
		var saved: Dictionary = app.progress.data.duplicate(true)
		for unused in range(3):
			app.game._complete_wave()
			app.game.advance_simulation(10.0)
			app._on_battle_finished(app.game.snapshot())
		check(app.progress.data == saved, "Repeated finish signals and result callbacks cannot duplicate campaign funds or win counts")
		var restored = Store.new()
		restored.save_path = app.progress.save_path
		restored.read_save()
		check(restored.read_error.is_empty() and serialized_equal(restored.data.army, saved.army) and serialized_equal(restored.data.maps, saved.maps) and serialized_equal(restored.data.learning, saved.learning) and serialized_equal(restored.data.settings, saved.settings), "Reload preserves timer preference, funds, wins and learning receipts")
		cases.append({"minutes":minutes, "elapsed":app.game.elapsed, "reward":reward, "currency":app.progress.data.army.currency, "wins":completed, "task":str(task.id), "supportSeconds":support_before})
	app._select_map(0)
	app._begin_battle()
	app.game.set_process(false)
	var currency: int = int(app.progress.data.army.currency)
	var wins: Dictionary = app.progress.data.maps.duplicate(true)
	app.game._spawn_enemy("raider", 1)
	var escaping: Dictionary = app.game.enemies.back()
	var path: Dictionary = app.game.paths[int(escaping.pathIndex)]
	escaping.pointIndex = path.points.size() - 1
	escaping.position = path.points.back()
	app.game._objective(str(path.objectiveId)).hp = 1
	app.game.advance_simulation(0.05)
	check(app.battle_finished and not app.last_victory and app.progress.data.army.currency == currency and app.progress.data.maps == wins, "Actual escaped-enemy defeat gives no clear funding or win")
	app._on_battle_finished(app.game.snapshot())
	check(app.progress.data.army.currency == currency and app.progress.data.maps == wins, "Repeated defeat result gives no campaign reward")
	var failed_reload = Store.new()
	failed_reload.save_path = app.progress.save_path
	failed_reload.read_save()
	check(serialized_equal(failed_reload.data.maps, wins) and int(failed_reload.data.army.currency) == currency, "Defeat save preserves previous clears and funds")
	observations.append({"probe":"main-learning-economy-save", "cases":cases, "savedProfile":ProjectSettings.globalize_path(app.progress.save_path), "defeatElapsed":app.game.elapsed, "scope":"Real app callbacks, saved receipts, transition controller and actual escape/finish signals; terminal deadline fixtures do not prove campaign balance."})
	app._stop_narration()
	app.queue_free()
	await process_frame

func engine_errors() -> Dictionary:
	var path: String = argument("--qa-log", "")
	var messages: Array = []
	if path.is_empty(): return {"checked":false, "count":0}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var value: String = str(line).strip_edges()
		if value == "ERROR: Failed to read the root certificate store." or value.begins_with("ERROR: DURATION CONTRACT:"): continue
		if value.begins_with("ERROR:") or value.begins_with("SCRIPT ERROR:"): messages.append(value)
	return {"checked":true, "count":messages.size(), "messages":messages}

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().to_lower()
	var isolated: bool = profile.begins_with(qa_project_path("tests/profiles/duration-contracts/").to_lower()) or profile.begins_with(qa_project_path("tests/profiles/duration-contracts-pack/").to_lower())
	if DisplayServer.get_name() != "headless" or not isolated:
		push_error("Duration contracts require headless and their isolated workspace profile")
		quit(2)
		return
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var mode: String = argument("--probe", "all")
	if mode in ["all", "contracts"]:
		plans()
		boundaries()
		cap_pressure()
		difficulty_contact()
	if mode in ["all", "integration"]:
		await main_integration()
	if mode == "difficulty":
		difficulty_contact()
	if mode == "smoke":
		check(digest("res://native/maps.json") == MAP_HASH and maps.size() == 40, "Representative packaged checks preserve the authored forty-map file")
		boundaries()
		cap_pressure()
		difficulty_contact()
		clock(5, 3.0)
		await main_integration()
	if mode in ["all", "clock"]:
		for minutes in argument("--minutes", "5,10,20").split(",", false):
			for speed in argument("--speeds", "1,2,3").split(",", false):
				clock(int(minutes), float(speed))
	check(not observations.is_empty(), "At least one independent duration probe executes")
	var errors: Dictionary = engine_errors()
	check(int(errors.count) == 0, "Selected probes have no runtime or script errors")
	var path: String = ("user://qa_duration_contracts_" if OS.get_cmdline_user_args().has("--packed") else "res://tests/qa_duration_contracts_") + argument("--label", "current") + ".json"
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(output != null, "Duration report opens")
	if output != null:
		output.store_string(JSON.stringify({"checks":checks, "failures":failures, "observations":observations, "engineErrors":errors, "execution":{"packed":OS.get_cmdline_user_args().has("--packed"), "profile":ProjectSettings.globalize_path("user://")}, "sourceHashes":{"game":digest("res://native/game.gd"), "duration":digest("res://native/battle_duration.gd"), "main":digest("res://native/main.gd")}, "scope":"Independent observable time/state/economy contracts. Forty-map plans preserve geometry; clock durability fixtures do not establish campaign balance. No GPU/FPS or real-time waiting claim."}, "  "))
		output.close()
	print("DURATION_CONTRACTS_QA ", JSON.stringify({"checks":checks, "failures":failures, "probes":observations.size(), "report":path}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
