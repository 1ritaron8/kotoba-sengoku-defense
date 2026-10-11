extends SceneTree
## Stage 01 common UI and explicit deployment contract, in a disposable profile.
## Mechanic fixtures do not represent GPU terrain QA or natural campaign play.
const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
const TYPES: Array = ["archer", "spear", "samurai", "gunner", "naginata", "monk", "commander", "ninja"]
const SOURCE_PATHS: Array = ["native/main.gd", "native/game.gd", "native/progress.gd", "native/troops_3d.gd", "native/deployment_drag_overlay.gd", "native/battlefield_hud.gd", "native/sengoku_ui.gd", "native/maps.json", "native/units.json", "tests/qa_ui_pilot.gd"]
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var maps: Array = []
var catalog: Array = []
var app: Node
var ending: bool = false

func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for relative in SOURCE_PATHS:
		result[relative] = FileAccess.get_sha256("res://" + relative) if FileAccess.file_exists("res://" + relative) else "missing"
	return result

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> bool:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size() <= 30: push_error("UI_PILOT " + note)
	return value

func canonical(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func guarded_profile() -> bool:
	var allowed: String = canonical(ProjectSettings.globalize_path("res://tests/profiles/"))
	var roaming: String = canonical(OS.get_environment("APPDATA"))
	var local: String = canonical(OS.get_environment("LOCALAPPDATA"))
	var user_path: String = canonical(ProjectSettings.globalize_path("user://"))
	return check(DisplayServer.get_name() == "headless" and roaming.is_absolute_path() and roaming.begins_with(allowed + "/ui-pilot-") and local == roaming and user_path.begins_with(roaming + "/"), "Headless verifier refuses every profile outside isolated ui-pilot-* runs")

func mechanics(game: Node) -> Dictionary:
	return {"gold":game.gold, "nextActorId":game.next_id, "nextJobId":game.next_recruitment_id, "nextEventId":game.next_event_id, "recruits":game.recruits, "selected":game.selected_id, "pending":game.pending.duplicate(true), "jobs":game.recruitment_queue.duplicate(true), "actors":game.units.duplicate(true), "marchCursor":game.ground_combat.march_path_cursor, "cursor":game.placement_cursor, "cursorVisible":game.placement_cursor_visible}

func make_game(unlocked: Array = ["archer", "spear"], levels: Dictionary = {}, capacity: int = 14) -> Node:
	var game: Node = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog, unlocked, levels)
	var stage: Dictionary = maps[0].duplicate(true)
	stage.unitLimit = capacity
	game.load_map(stage, 10)
	game.set_seed(20261008)
	return game

func point(value) -> Vector2:
	return value if value is Vector2 else Vector2(float(value.get("x", -1)), float(value.get("y", -1)))

func legal(game: Node, id: String) -> Vector2:
	if str(game.placement_contract(id).deploymentKind) == "marching":
		var base: Dictionary = game.ground_combat.select_march_base()
		return point(base.position) if not base.is_empty() else Vector2(-1, -1)
	for zone in game.zones:
		var hint: Vector2 = game._zone_placement_hint(zone, id)
		if hint.x >= 0 and bool(game.deployment_preview(id, hint).get("valid", false)): return hint
	return Vector2(-1, -1)

func held_simulation(game: Node) -> void:
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue = ["raider"]
	game.spawn_source_waves = [1]
	game.spawn_metadata = [{}]
	game.spawn_clock = 100000.0

func tick(game: Node, seconds: float) -> void:
	for step in range(ceili(seconds / .025)): game.advance_simulation(.025)

func expect_reject(game: Node, id: String, target: Vector2, route: String, note: String) -> void:
	var before: Dictionary = mechanics(game)
	var preview: Dictionary = game.deployment_preview(id, target, route)
	check(not bool(preview.get("valid", false)) and mechanics(game) == before, note + ": preview is invalid and pure")
	var commit: Dictionary = game.submit_deployment(id, target, route)
	check(not bool(commit.get("ok", false)) and mechanics(game) == before, note + ": rejection leaves money, jobs, actors, IDs and existing preview unchanged")

func backend_contract() -> void:
	var game: Node = make_game()
	if not check(game.has_method("deployment_preview") and game.has_method("submit_deployment"), "Game provides explicit pure preview and atomic submission APIs"):
		game.free()
		return
	var bow: Vector2 = legal(game, "archer")
	var base: Vector2 = legal(game, "spear")
	check(bow.x >= 0 and base.x >= 0, "Actual Stage 01 supplies both a legal ranged site and authored friendly origin")
	game.begin_placement("archer")
	var before: Dictionary = mechanics(game)
	for id in ["archer", "spear"]:
		var destination: Vector2 = bow if id == "archer" else base
		for repeat in range(6):
			var preview: Dictionary = game.deployment_preview(id, destination)
			check(bool(preview.get("valid", false)) and str(preview.get("type", "")) == id and mechanics(game) == before, id + " explicit hover preserves legacy preview and every transaction counter")
	for destination in [Vector2(-.01, .5), Vector2(1.01, .5), Vector2(.5, -1), Vector2(NAN, .5), Vector2(INF, .5)]:
		expect_reject(game, "archer", destination, "", "Off-map/nonfinite destination " + str(destination))
	expect_reject(game, "gunner", bow, "", "Fresh profile locked gunner")
	expect_reject(game, "unknown", bow, "", "Unknown roster ID")
	expect_reject(game, "spear", base, "missing-path", "Unknown authored route ID")
	expect_reject(game, "spear", bow, "", "Marcher cannot be stationed on a ranged site")
	game.gold = 0
	expect_reject(game, "archer", bow, "", "Current balance cannot fund the drop")
	game.gold = 280
	game.set_input_enabled(false)
	expect_reject(game, "spear", base, "", "Disabled battlefield input")
	game.set_input_enabled(true)
	var cost: int = game.recruit_cost("archer")
	before = mechanics(game)
	var accepted: Dictionary = game.submit_deployment("archer", bow)
	check(bool(accepted.get("ok", false)) and game.gold == before.gold - cost and game.recruitment_queue.size() == 1 and game.units.is_empty() and game.next_id == before.nextActorId and game.next_recruitment_id == before.nextJobId + 1, "One explicit drop pays for one delayed job and allocates no actor ID")
	expect_reject(game, "archer", bow, "", "Accepted job reserves its destination against duplicate drops")
	var job: Dictionary = game.recruitment_queue[0].duplicate(true)
	held_simulation(game)
	tick(game, float(job.totalSeconds) + .025)
	check(game.units.size() == 1 and game.recruitment_queue.is_empty(), "Accepted ranged order produces through actual simulation")
	expect_reject(game, "archer", bow, "", "Produced stationary unit occupies its reserved position")
	game.free()

func capacity_and_refunds() -> void:
	var game: Node = make_game(["archer", "spear"], {}, 1)
	game.gold = 10000
	var base: Vector2 = legal(game, "spear")
	var route: String = str(game.ground_combat.select_march_base().pathId)
	var first: Dictionary = game.submit_deployment("spear", base, route)
	check(bool(first.get("ok", false)), "Explicit authored route accepts one marching order")
	var job: Dictionary = game.recruitment_queue[0].duplicate(true)
	held_simulation(game)
	tick(game, float(job.totalSeconds) + .025)
	check(game.units.size() == 1 and str(game.units[0].pathId) == route and game.units[0].basePosition == base, "Production retains the authored origin and route")
	var wallet: int = game.gold
	var next_actor: int = game.next_id
	var second: Dictionary = game.submit_deployment("spear", base, route)
	check(bool(second.get("ok", false)) and game.gold == wallet - game.recruit_cost("spear"), "Full active-unit capacity accepts a funded order while queue capacity remains")
	tick(game, float(job.totalSeconds) + .025)
	check(game.units.size() == 1 and game.next_id == next_actor and game.recruitment_queue.size() == 1 and str(game.recruitment_queue[0].status) == "waiting_capacity", "Finished production waits for capacity without reserving or partially creating actors")
	var pending_job: int = int(game.recruitment_queue[0].id)
	check(game.cancel_recruitment(pending_job) and game.gold == wallet and game.recruitment_queue.is_empty(), "Capacity-wait cancellation refunds the complete original order")
	check(not game.cancel_recruitment(pending_job) and game.gold == wallet, "Repeated cancellation does not refund twice")
	game.free()
	game = make_game(["archer", "spear"], {"spear":5}, 1)
	game.gold = 10000
	base = legal(game, "spear")
	var pair: Dictionary = game.submit_deployment("spear", base)
	check(bool(pair.get("ok", false)) and game.gold == 9910 and game.recruitment_queue.size() == 1 and int(game.recruitment_queue[0].quantity) == 2, "Permanent spear level 5 creates one 90-gold order for two actors")
	job = game.recruitment_queue[0].duplicate(true)
	held_simulation(game)
	tick(game, float(job.totalSeconds) + .025)
	check(game.units.is_empty() and str(game.recruitment_queue[0].status) == "waiting_capacity", "One remaining slot does not split a two-actor order")
	game.config.unitLimit = 2
	tick(game, .025)
	check(game.units.size() == 2 and int(game.units[0].id) != int(game.units[1].id) and game.recruitment_queue.is_empty() and int(game.units[0].paid) + int(game.units[1].paid) == 90, "Two free slots release the complete pair with unique IDs and one exact payment")
	game.free()
	game = make_game()
	game.gold = 10000
	base = legal(game, "spear")
	for index in range(24):
		check(bool(game.submit_deployment("spear", base).get("ok", false)), "Queue accepts funded order %d of 24" % (index + 1))
	check(game.recruitment_queue.size() == 24, "Recruitment queue capacity counts jobs rather than actor quantity")
	expect_reject(game, "spear", base, "", "The 25th queue job")
	game.close_battle()
	check(game.recruitment_queue.is_empty() and game.gold == 10000, "Battle close refunds the unfinished 24-order queue once")
	game.close_battle()
	check(game.gold == 10000, "Duplicate close cannot refund again")
	game.free()

func parallel_and_latest_state() -> void:
	var game: Node = make_game(TYPES)
	game.gold = 10000
	var base: Vector2 = legal(game, "spear")
	var slow: Dictionary = game.submit_deployment("commander", base)
	var fast: Dictionary = game.submit_deployment("spear", base)
	check(bool(slow.get("ok", false)) and bool(fast.get("ok", false)), "Isolated progressed-roster fixture accepts different-duration orders")
	var first: Dictionary = game.recruitment_queue[0].duplicate(true)
	var second: Dictionary = game.recruitment_queue[1].duplicate(true)
	held_simulation(game)
	tick(game, .25)
	check(absf(float(game.recruitment_queue[0].remainingSeconds) - (float(first.totalSeconds) - .25)) < .00001 and absf(float(game.recruitment_queue[1].remainingSeconds) - (float(second.totalSeconds) - .25)) < .00001, "Both queued orders progress concurrently through the same simulation time")
	game.pause_battle()
	var before: Dictionary = mechanics(game)
	game.advance_simulation(1)
	check(mechanics(game) == before, "Paused simulation freezes production and transactions")
	game.paused = false
	tick(game, float(second.totalSeconds) - .25 + .025)
	check(game.units.size() == 1 and str(game.units[0].type) == "spear" and game.recruitment_queue.size() == 1 and int(game.recruitment_queue[0].id) == int(slow.jobId), "Later short order completes while earlier long order continues")
	var wallet: int = game.gold
	check(game.cancel_recruitment(int(slow.jobId)) and game.gold == wallet + int(first.cost), "Cancellation during production refunds the entire original cost")
	game.free()
	game = make_game()
	var bow: Vector2 = legal(game, "archer")
	check(bool(game.deployment_preview("archer", bow).get("valid", false)), "Pre-drop preview can be valid")
	game.gold = game.recruit_cost("archer") - 1
	expect_reject(game, "archer", bow, "", "Balance changes after preview but before drop")
	game.gold = 280
	game.unlocked_roster.erase("archer")
	expect_reject(game, "archer", bow, "", "Unlock state changes after preview but before drop")
	game.free()

func timing_boundaries() -> void:
	for minutes in [10, 20]:
		for defeat in [false, true]:
			var game: Node = make_game()
			if minutes != 10: game.load_map(maps[0], minutes)
			var results: Array = []
			game.battle_finished.connect(func(result: Dictionary): results.append(result.duplicate(true)))
			var base: Vector2 = legal(game, "spear")
			check(bool(game.submit_deployment("spear", base).get("ok", false)), "Timed-boundary fixture queues one real refundable unfinished order")
			held_simulation(game)
			game.wave = game.total_waves
			var target: float = float(game.battle_plan.targetSeconds)
			game.elapsed = target - .1
			var wallet: int = game.gold
			game._complete_wave()
			check(not game.finished and results.is_empty() and game.gold == wallet, "%dm final window cannot end or grant rewards before its deadline" % minutes)
			game.elapsed = target - .001
			game.wave_time = float(game.battle_plan.waves.back().endSeconds) - float(game.battle_plan.waves.back().startSeconds) - .001
			var enemy: Dictionary = game._spawn_enemy("raider", 1)
			if defeat:
				var route: Dictionary = game.paths[int(enemy.pathIndex)]
				enemy.pointIndex = route.points.size() - 1
				enemy.position = route.points.back()
				game._objective(str(route.objectiveId)).hp = 1
			else:
				enemy.speed = 0.0
			game.advance_simulation(1.0)
			check(game.finished and game.victory == (not defeat) and results.size() == 1 and absf(game.elapsed - target) < .000001, "%dm final-step goal destruction takes precedence over the exact holdout deadline" % minutes)
			if not defeat:
				check(not game.enemies.is_empty() and float(game.enemies[0].hp) > 0, "%dm existing holdout victory does not require exterminating remaining live enemies" % minutes)
			var expected_gold: int = 280 if defeat else 280 + 40 + game.total_waves * 3
			check(game.recruitment_queue.is_empty() and game.pending.is_empty() and game.gold == expected_gold, "%dm result refunds the exact unfinished order, preserves its current stipend policy and clears free preview" % minutes)
			var final: Dictionary = mechanics(game)
			game.advance_simulation(20)
			game._complete_wave()
			game.continue_wave()
			game.start_battle()
			check(results.size() == 1 and mechanics(game) == final, "%dm repeated end/resume input cannot restart battle or duplicate its result/refund" % minutes)
			observations.append({"case":"timed-final-boundary", "minutes":minutes, "victory":game.victory, "elapsed":game.elapsed, "goalHp":game.snapshot().hp, "remainingEnemies":game.enemies.size(), "results":results.size()})
			game.free()

func settle(frames: int = 3) -> void:
	for unused in range(frames): await process_frame

func motion(destination: Vector2, held: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = destination
	event.global_position = destination
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	await settle(1)

func mouse(destination: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = destination
	event.global_position = destination
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await settle(1)

func touch(destination: Vector2, pressed: bool, index: int = 0) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.position = destination
	event.pressed = pressed
	event.index = index
	Input.parse_input_event(event)
	await settle(1)

func touch_motion(destination: Vector2, index: int = 0) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.position = destination
	event.index = index
	Input.parse_input_event(event)
	await settle(1)

func emulated_mouse(destination: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = destination
	event.global_position = destination
	event.pressed = pressed
	event.button_index = MOUSE_BUTTON_LEFT
	event.device = -1
	Input.parse_input_event(event)
	await settle(1)

func emulated_motion(destination: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = destination
	event.global_position = destination
	event.device = -1
	Input.parse_input_event(event)
	await settle(1)

func input_trace(note: String) -> Dictionary:
	var hovered: Control = root.gui_get_hovered_control()
	return {"event":note, "modal":app.modal_context, "inputEnabled":app.game.input_enabled, "paused":app.game.paused, "releasePending":app.deployment_release_pending, "touchMouseSuppressed":app.deployment_touch_mouse_suppressed, "hovered":str(hovered.name) if hovered != null else ""}

func key(code: Key, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await settle(1)
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await settle(1)

func ui_snapshot() -> Dictionary:
	return {"mechanics":mechanics(app.game),"chosen":app.chosen_unit_id,"save":FileAccess.get_file_as_bytes(app.progress.save_path),"progress":app.progress.data.duplicate(true)}

func drag_clear() -> bool:
	return app.deployment_drag.is_empty() and str(app.deployment_press_unit_id).is_empty() and app.deployment_overlay.preview.is_empty() and app.troops_3d.ui_deployment_preview.is_empty()

func released_clear() -> bool:
	return drag_clear() and not app.game.ui_deployment_active and app.game.pending.is_empty() and (not is_instance_valid(app.troops_3d.placement_actor) or not app.troops_3d.placement_actor.visible)

func card(id: String) -> Button:
	return app.army_grid.get_node_or_null("DeployCard_" + id) as Button

func start_drag(id: String) -> Dictionary:
	var control: Button = card(id)
	if not check(control != null and not control.disabled, "Actual roster card can start " + id): return {}
	var center: Vector2 = control.get_global_rect().get_center()
	await motion(center)
	# An unowned hover may move/hide a previously prepared legacy cursor.
	# Freeze after that ordinary motion, immediately before the candidate press.
	var before: Dictionary = ui_snapshot()
	await mouse(center, true)
	check(ui_snapshot() == before, id + " candidate press does not save, select, spend, start production or reserve IDs")
	await motion(center + Vector2(12, -24), true)
	check(not app.deployment_drag.is_empty() and str(app.deployment_drag.get("unitId", "")) == id, id + " real held pointer motion crosses the threshold into a drag")
	var expected: Dictionary = before.duplicate(true)
	if bool(expected.mechanics.pending.get("preview", false)) and int(expected.mechanics.pending.get("paid", 0)) == 0:
		expected.mechanics.pending.clear()
		expected.mechanics.cursorVisible = false
	check(ui_snapshot() == expected, id + " drag start preserves saved selection/economy and may retire only a prior unpaid click preview")
	return before

func ui_point(id: String) -> Vector2:
	if str(app.game.placement_contract(id).deploymentKind) == "marching":
		return app.game.field_point_to_screen(legal(app.game, id))
	for zone in app.game.zones:
		var hint: Vector2 = app.game._zone_placement_hint(zone, id)
		if hint.x < 0 or not bool(app.game.deployment_preview(id, hint).get("valid", false)): continue
		var screen: Vector2 = app.game.field_point_to_screen(hint)
		if not app._deployment_surface_point(screen).is_empty(): return screen
	return Vector2(-1, -1)

func new_app(fixture: RefCounted) -> void:
	app = load("res://native/main.tscn").instantiate()
	app.progress = fixture
	root.add_child(app)
	app.set_process(false)
	app.game.set_process(false)
	app.atmosphere.set_process(false)
	app.troops_3d.set_process(false)
	await settle()
	app._select_map(0)
	app._begin_battle()
	app.game.set_process(false)
	await settle()

func cleanup_app() -> void:
	if not is_instance_valid(app): return
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	app.game.close_battle()
	app.queue_free()
	await settle()
	app = null

func learning_readout() -> void:
	check(not app.learning_readout_expanded and app.active_word.is_visible_in_tree() and not app.example_label.visible and not app.learning_caption.visible, "Compact learning readout shows the current word and keeps examples/grammar collapsed")
	app._sync_announcement_reading()
	check(not app.example_label.visible and not app.learning_caption.visible, "Announcement visibility synchronization preserves the collapsed learning choice")
	var clock: float = app.learning_clock
	app._process(.25)
	check(absf(app.learning_clock - clock - .25) < .00001, "Visible compact learning word advances its existing dwell clock even while examples are collapsed")
	var button: Vector2 = app.learning_readout_button.get_global_rect().get_center()
	await mouse(button, true)
	await mouse(button, false)
	check(app.learning_readout_expanded and app.example_label.is_visible_in_tree() and app.learning_caption.is_visible_in_tree(), "Actual learning expand button reveals the existing example and grammar readout")
	app.announcement_subtitle.set_word({"jp":"進め", "reading":"すすめ", "ko":"전진"}, 26, true)
	app.announcement_caption_remaining = 99.0
	app.announcement_subtitle.show()
	app._sync_announcement_reading()
	clock = app.learning_clock
	app._process(.25)
	check(not app.active_word.visible and not app.example_label.visible and not app.learning_caption.visible and app.learning_clock == clock, "Actual announcement visibility hides the readout and preserves its established dwell-clock pause")
	app.announcement_subtitle.hide()
	app._sync_announcement_reading()
	check(app.active_word.is_visible_in_tree() and app.example_label.is_visible_in_tree() and app.learning_caption.is_visible_in_tree(), "Announcement completion restores the expanded readout chosen before it")
	button = app.learning_readout_button.get_global_rect().get_center()
	await mouse(button, true)
	await mouse(button, false)
	check(not app.learning_readout_expanded and not app.example_label.visible and not app.learning_caption.visible, "Actual learning collapse button restores the compact readout")
	var previous: int = app.learning_index
	app.learning_clock = app._word_dwell_seconds() - .05
	app._process(.1)
	check(app.learning_index != previous and str(app.active_word.word.get("jp", "")) == str(app.learning_words[app.learning_index].get("jp", "")), "Compact readout cycles to the real next lesson word through the original dwell flow")

func field_report_blocking() -> void:
	var mission: Dictionary = app.stage_learning.get("missions", [])[0]
	app.learning_field.show_report(mission, false)
	app._process(0)
	var banner: Rect2 = app.learning_field.report_card.get_global_rect()
	check(app.learning_field.report_card.is_visible_in_tree() and not app.learning_panel.visible and app._deployment_surface_point(banner.get_center()).is_empty(), "Actual field report hides overlapping readout and excludes its visible rectangle from drop targets")
	var center: Vector2 = card("archer").get_global_rect().get_center()
	await mouse(center, true)
	await mouse(center, false)
	check(not app.game.pending.is_empty(), "Report input-boundary fixture uses a deliberate native stationary card preview")
	var before: Dictionary = mechanics(app.game)
	await mouse(banner.get_center(), true)
	await mouse(banner.get_center(), false)
	check(mechanics(app.game) == before, "Plain click on the visible report cannot charge or place an older pending legacy unit through it")
	await key(KEY_ESCAPE)
	before = await start_drag("archer")
	await motion(banner.get_center(), true)
	check(not bool(app.deployment_drag.get("preview", {}).get("valid", false)), "Native dragged preview rejects the visible field-report surface")
	await mouse(banner.get_center(), false)
	check(released_clear() and ui_snapshot() == before, "Report-covered drop cancels its unpaid gesture without spending or saving")
	app.learning_field._process(app.learning_field.report_clock + .01)
	app._process(0)
	check(not app.learning_field.report_card.visible and app.learning_panel.is_visible_in_tree(), "Natural report timeout restores the chosen word readout without a new game-start phase")

func fresh_ui() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	var fixture: RefCounted = Store.new()
	fixture.save_path = "user://ui-pilot-fresh.json"
	fixture.data.settings.music = false
	fixture.data.settings.voice = false
	fixture.data.settings.effects = false
	check(fixture.write_save(), "Fresh isolated profile saves before actual Main reads it")
	await new_app(fixture)
	if not check(app.has_method("_begin_deployment_drag") and app.has_method("_deployment_surface_point"), "Main exposes the implemented drag lifecycle for native-input verification"):
		await cleanup_app()
		return
	check(app.progress.unlocked_units() == ["archer", "spear"] and app.progress.data.maps.is_empty() and card("gunner").disabled and not card("archer").disabled and not card("spear").disabled, "Fresh Stage 01 retains only the actual two unlocked starter classes")
	check(app.game.gold == 280 and int(app.game.config.unitLimit) == 14 and int(app.game.snapshot().hp) == 26 and app.game.total_waves == 21, "Actual Stage 01 HUD source is 280 gold, 14 active slots, 26 goal HP and 21 timed waves")
	check(app.hud_gold.text.contains("280") and app.hud_health.text.contains("26") and app.hud_wave.text.contains("21") and app.hud_capacity.text.contains("14"), "Shared HUD displays current balance, active capacity, goal health and runtime wave count")
	for dimensions in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		app._layout()
		await settle()
		for control in [app.hud_gold, app.hud_capacity, app.hud_health, app.hud_wave, app.pause_button, app.speed_button, app.battle_menu_button]:
			check(root.get_visible_rect().encloses(control.get_global_rect()), "Shared HUD/control geometry fits " + str(dimensions) + ": " + str(control.name))
	await field_report_blocking()
	await learning_readout()
	var target: Vector2 = ui_point("archer")
	check(target.x >= 0, "Actual Stage 01 contains an unobstructed legal archer drop target")
	var before: Dictionary = await start_drag("archer")
	await motion(target, true)
	check(bool(app.deployment_drag.get("preview", {}).get("valid", false)) and ui_snapshot() == before, "Native hover shows a legal archer preview without transaction/save side effects")
	await key(KEY_R)
	check(ui_snapshot() == before and not app.deployment_drag.is_empty(), "R during an active drag cannot create a second action")
	var cost: int = app.game.recruit_cost("archer")
	await mouse(target, false)
	await settle()
	check(released_clear() and app.game.gold == int(before.mechanics.gold) - cost and app.game.recruitment_queue.size() == 1 and app.game.units.is_empty() and app.game.next_id == int(before.mechanics.nextActorId), "One real native drop submits exactly one delayed archer order and clears every drag state")
	var committed: Dictionary = mechanics(app.game)
	await mouse(target, false)
	check(mechanics(app.game) == committed, "Duplicate native release without an active gesture cannot charge or enqueue twice")
	card("archer").pressed.emit()
	check(mechanics(app.game) == committed, "Delayed native card pressed signal after consumed drag cannot prepare or submit another action")
	check(app.production_panel.visible and app.production_title.text.contains("1 / 24") and app.production_cards.get_child_count() == 1, "Common production UI reads one actual queued job against the separate 24-job capacity")
	before = await start_drag("archer")
	await motion(target, true)
	check(not bool(app.deployment_drag.get("preview", {}).get("valid", false)), "Native hover rejects a reserved stationary destination")
	await mouse(target, false)
	check(released_clear() and ui_snapshot() == before, "Reserved-point drop cancels only its unpaid gesture and preserves the existing paid order")
	# All cancellation cases retain the accepted earlier job.
	for cause in ["escape", "right-click", "modal", "focus", "off-map", "HUD", "learning"]:
		before = await start_drag("spear")
		var base: Vector2 = ui_point("spear")
		await motion(base, true)
		match cause:
			"escape": await key(KEY_ESCAPE)
			"right-click": await mouse(base, true, MOUSE_BUTTON_RIGHT)
			"modal": app._show_pause_menu()
			"focus": app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"off-map": await mouse(Vector2(-20, -20), false)
			"HUD": await mouse(app.hud_gold.get_global_rect().get_center(), false)
			"learning":
				app.game.between_waves = true
				app.game._emit_state()
				app._show_quiz()
		await settle()
		check(drag_clear() and app.game.gold == int(before.mechanics.gold) and app.game.recruitment_queue == before.mechanics.jobs and app.game.next_id == int(before.mechanics.nextActorId), cause + " cancels drag without spending, IDs, leaked preview or cancellation of the earlier paid order")
		await mouse(base, false)
		if cause == "right-click": await mouse(base, false, MOUSE_BUTTON_RIGHT)
		check(released_clear(), cause + " matching pointer release clears canceled-gesture input ownership")
		if cause == "modal":
			check(app.modal_context == "pause" and not app.game.input_enabled, "Actual menu owns placement input while open")
			app._close_modal(true)
		if cause == "learning":
			check(not app.quiz_task.is_empty() and not app.game.input_enabled, "Actual learning task/transition owns placement input after drag cancellation")
			app._cancel_learning_transition()
			app.context_task_active = false
			app._close_modal(false)
			app.quiz_task.clear()
			app.learning_field.clear()
			app.game.between_waves = false
			app.game._emit_state()
		if cause == "focus": app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
		await settle()
	# A truly locked native card cannot become a deployment gesture.
	var locked: Button = card("gunner")
	before = ui_snapshot()
	var center: Vector2 = locked.get_global_rect().get_center()
	await mouse(center, true)
	await motion(target, true)
	await mouse(target, false)
	check(released_clear() and ui_snapshot() == before, "Locked native card movement/drop cannot save, select or recruit")
	app.game.gold = 0
	app.game._emit_state()
	if card("spear").disabled:
		before = ui_snapshot()
		await mouse(card("spear").get_global_rect().get_center(), true)
		await motion(ui_point("spear"), true)
	else:
		before = await start_drag("spear")
		await motion(ui_point("spear"), true)
		check(not bool(app.deployment_drag.get("preview", {}).get("valid", false)), "Insufficient balance is revalidated in native drag preview")
	await mouse(ui_point("spear"), false)
	check(released_clear() and ui_snapshot() == before, "Unaffordable native drop has no transaction/save effects")
	# Restore test-only funds; deliberate clicks and R retain their prior contract.
	app.game.gold = 1000
	app.game._emit_state()
	# Touch has one owning finger. Its emulated mouse stream cannot duplicate it.
	before = ui_snapshot()
	center = card("spear").get_global_rect().get_center()
	var touch_base: Vector2 = ui_point("spear")
	await touch(center, true, 0)
	await emulated_mouse(center, true)
	await touch_motion(touch_base, 0)
	check(not app.deployment_drag.is_empty() and ui_snapshot() == before, "Touch press/motion with an emulated mouse press remains one pure drag")
	await touch(touch_base, true, 1)
	await touch(touch_base, false, 1)
	check(not app.deployment_drag.is_empty() and ui_snapshot() == before, "A second finger's release cannot commit the owning finger's order")
	await touch(touch_base, false, 0)
	committed = mechanics(app.game)
	check(released_clear() and app.game.recruitment_queue.size() == before.mechanics.jobs.size() + 1 and app.game.gold == int(before.mechanics.gold) - app.game.recruit_cost("spear"), "Owning touch release accepts exactly one production order")
	await emulated_mouse(touch_base, false)
	await touch(touch_base, false, 0)
	check(mechanics(app.game) == committed, "Emulated mouse release and duplicate touch release cannot replay the consumed touch order")
	card("spear").pressed.emit()
	check(mechanics(app.game) == committed, "Delayed marching-card pressed signal cannot replay a completed touch order")
	# Focus loss may omit a native release; a new press must recover safely.
	before = await start_drag("spear")
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(drag_clear() and ui_snapshot() == before, "Focus cancellation clears preview without mutating the accepted queue or save")
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	before = await start_drag("spear")
	await motion(ui_point("spear"), true)
	await mouse(ui_point("spear"), false)
	check(released_clear() and app.game.recruitment_queue.size() == before.mechanics.jobs.size() + 1 and app.game.gold == int(before.mechanics.gold) - app.game.recruit_cost("spear"), "New press after a lost focus release recovers and commits one new gesture")
	center = card("archer").get_global_rect().get_center()
	await mouse(center, true)
	await mouse(center, false)
	check(not app.game.pending.is_empty() and str(app.game.pending.type) == "archer", "Deliberate short stationary-card click retains the legacy unpaid placement flow")
	await key(KEY_R)
	check(app.game.pending.is_empty(), "R cancels the deliberately prepared legacy stationary preview")
	await key(KEY_R)
	check(not app.game.pending.is_empty(), "R reopens one legacy stationary preview")
	await key(KEY_ESCAPE)
	check(app.game.pending.is_empty(), "Escape cancels legacy keyboard placement")
	# Retiring an older unpaid click preview must not let its ghost return after
	# an owned drag is canceled; the already accepted production jobs survive.
	center = card("archer").get_global_rect().get_center()
	await mouse(center, true)
	await mouse(center, false)
	check(not app.game.pending.is_empty(), "Legacy-preview cancellation fixture starts from an actual stationary short click")
	before = await start_drag("spear")
	await motion(ui_point("spear"), true)
	await key(KEY_ESCAPE)
	await mouse(ui_point("spear"), false)
	check(released_clear() and app.game.gold == int(before.mechanics.gold) and app.game.recruitment_queue == before.mechanics.jobs and app.game.next_id == int(before.mechanics.nextActorId), "Canceling a drag retires the old free click preview/ghost while preserving every accepted job and payment")
	var wallet_after_cancel: int = app.game.gold
	var jobs_after_cancel: int = app.game.recruitment_queue.size()
	await mouse(target, true)
	await mouse(target, false)
	check(app.game.gold == wallet_after_cancel and app.game.recruitment_queue.size() == jobs_after_cancel and app.game.pending.is_empty(), "Later plain field click cannot submit a canceled older placement preview")
	center = card("spear").get_global_rect().get_center()
	var jobs: int = app.game.recruitment_queue.size()
	var wallet: int = app.game.gold
	await mouse(center, true)
	check(app.game.gold == wallet and app.game.recruitment_queue.size() == jobs, "Deliberate marching click still waits for release")
	await mouse(center, false)
	check(app.game.recruitment_queue.size() == jobs + 1 and app.game.gold == wallet - app.game.recruit_cost("spear"), "Deliberate marching-card release retains one existing dispatch")
	await key(KEY_R)
	check(app.game.recruitment_queue.size() == jobs + 2, "A separate R key action recruits one additional selected marcher")
	await key(KEY_R, true)
	check(app.game.recruitment_queue.size() == jobs + 2, "Repeated key echo cannot recruit again")
	var elapsed: float = app.game.elapsed
	await mouse(app.pause_button.get_global_rect().get_center(), true)
	await mouse(app.pause_button.get_global_rect().get_center(), false)
	app.game.advance_simulation(.2)
	check(app.game.paused and app.game.elapsed == elapsed, "Actual pause UI freezes the shared battle and production clock")
	await mouse(app.pause_button.get_global_rect().get_center(), true)
	await mouse(app.pause_button.get_global_rect().get_center(), false)
	await mouse(app.speed_button.get_global_rect().get_center(), true)
	await mouse(app.speed_button.get_global_rect().get_center(), false)
	check(app.game.speed == 2.0 and app.speed_button.text.contains("2"), "Actual speed UI changes the shared simulation state and label")
	var menu_center: Vector2 = app.battle_menu_button.get_global_rect().get_center()
	await motion(menu_center)
	await mouse(menu_center, true)
	await mouse(menu_center, false)
	check(app.modal_context == "pause" and not app.game.input_enabled, "Actual mouse menu click reaches the button above common HUD presentation")
	if app.modal != null: app._close_modal(true)
	await settle()
	var trace: Array = [input_trace("before")]
	await touch(menu_center, true)
	trace.append(input_trace("touch-down"))
	await emulated_motion(menu_center)
	await emulated_mouse(menu_center, true)
	trace.append(input_trace("emulated-down"))
	await touch(menu_center, false)
	trace.append(input_trace("touch-up"))
	await emulated_mouse(menu_center, false)
	trace.append(input_trace("emulated-up"))
	observations.append({"case":"ordinary-GUI-touch-menu", "trace":trace})
	check(app.modal_context == "pause" and not app.game.input_enabled, "Ordinary GUI touch/emulated mouse tap remains available when no deployment gesture owns it")
	if app.modal != null: app._close_modal(true)
	await settle()
	# A true map selection consumes the pending gesture and resets the battle.
	before = await start_drag("spear")
	app._select_map(0)
	await settle()
	check(drag_clear() and not app.battle_started and app.game.gold == 280 and app.game.recruitment_queue.is_empty(), "Actual map selection cancels a gesture before loading a fresh battle")
	observations.append({"case":"fresh-native-input", "profile":app.progress.save_path, "unlocked":app.progress.unlocked_units(), "runtimeWaves":app.game.total_waves, "sizes":[[1280,800],[1440,900]], "scope":"Native press/motion/release, keyboard, modal/learning transition and simulated focus notification; no OS mouse control or GPU pixels."})
	await cleanup_app()

func progressed_revisit() -> void:
	var fixture: RefCounted = Store.new()
	fixture.save_path = "user://ui-pilot-progressed-fixture.json"
	fixture.data.settings.music = false
	fixture.data.settings.voice = false
	fixture.data.settings.effects = false
	# Private saved-progress fixture, explicitly not a campaign-victory claim.
	for index in range(14):
		check(bool(fixture.complete_map(str(maps[index].id), {"qaFixture":true}).get("saved", true)), "Private progressed fixture records recognized prior stage " + str(index + 1))
	fixture.data.army.levels.spear = 5
	fixture.data.army.levels.gunner = 7
	fixture.data.army.selected = "spear"
	fixture.data.settings.battleMinutes = 20
	check(fixture.write_save(), "Progressed fixture saves permanent levels and 20-minute selection")
	await new_app(fixture)
	# Progress.read_save legitimately normalizes JSON numeric types. Freeze the
	# actual reloaded state before input, rather than pre-serialization fixture types.
	var saved: Dictionary = app.progress.data.duplicate(true)
	check(app.progress.data.maps.size() == 14 and app.progress.unlocked_units().size() == 8 and app.game.unlocked_roster.size() == 8 and not card("ninja").disabled, "Revisiting Stage 01 preserves all prior profile unlocks")
	check(app.progress.army_level("spear") == 5 and app.progress.army_level("gunner") == 7 and int(app.game.campaign_levels.spear) == 5 and app.game.recruit_cost("spear") == 90 and card("spear").get_node("RecruitPrice_spear").text == "90", "Revisit cards and recruitment use retained permanent growth")
	check(app.game.total_waves == 41 and app.hud_wave.text.contains("41") and app.active_battle_minutes == 20, "Revisit shared HUD reads 41 runtime waves from the actual 20-minute plan")
	var before: Dictionary = await start_drag("spear")
	var base: Vector2 = ui_point("spear")
	await motion(base, true)
	await mouse(base, false)
	check(released_clear() and app.game.recruitment_queue.size() == 1 and int(app.game.recruitment_queue[0].quantity) == 2 and app.game.gold == 190, "Native progressed Stage 01 drop creates one 90-gold order for the retained spear pair")
	var job: Dictionary = app.game.recruitment_queue[0].duplicate(true)
	# Test-only insufficient-slot condition, applied to this disposable runtime;
	# the real map file, unlocks and save schema remain unchanged.
	app.game.config.unitLimit = 1
	held_simulation(app.game)
	tick(app.game, float(job.totalSeconds) + .025)
	app.game._emit_state()
	var queue_card: Button = app.production_cards.get_child(0) as Button
	check(app.game.units.is_empty() and str(app.game.recruitment_queue[0].status) == "waiting_capacity" and queue_card.text.contains("정원 대기") and app.hud_capacity.text.contains("0 / 1"), "Actual shared queue/HUD show completed pair waiting for two simultaneous active slots")
	check(is_equal_approx(float(queue_card.get_node("ProductionGauge").value), 100.0) and app.production_title.text.contains("1 / 24"), "Completed waiting order displays a finished gauge while retaining its one queue job")
	app.game.config.unitLimit = 2
	tick(app.game, .05)
	app.game._emit_state()
	check(app.game.units.size() == 2 and app.game.recruitment_queue.is_empty() and not app.production_panel.visible and app.hud_capacity.text.contains("2 / 2"), "Shared HUD reflects atomic pair arrival and hides the empty production queue")
	check(app.progress.data.maps == saved.maps and app.progress.data.army.levels == saved.army.levels, "Native revisit deployment preserves conquered maps and permanent levels")
	observations.append({"case":"progressed-native-revisit", "profile":app.progress.save_path,"unlocked":app.progress.unlocked_units(),"spearLevel":app.progress.army_level("spear"),"runtimeWaves":app.game.total_waves,"jobQuantity":job.quantity,"producedActors":app.game.units.size()})
	await cleanup_app()

func main_terminal_results() -> void:
	# Finite private terminal fixtures: cross the last simulated combat step and
	# observe the real Game signal -> Main result/save flow, not a natural victory.
	for defeat in [false, true]:
		var fixture: RefCounted = Store.new()
		fixture.save_path = "user://ui-pilot-terminal-%s.json" % ("loss" if defeat else "win")
		fixture.data.settings.music = false
		fixture.data.settings.voice = false
		fixture.data.settings.effects = false
		check(fixture.write_save(), "Private terminal fixture persists its isolated audio preferences")
		await new_app(fixture)
		var map_id: String = str(app.current_map.id)
		check(map_id == "basic-forest" and app.progress.data.maps.is_empty() and app.active_battle_minutes == 10, "Actual Main terminal fixture starts fresh Stage 01 in its existing 10-minute mode")
		var currency: int = int(app.progress.data.army.currency)
		var results: Array = []
		app.game.battle_finished.connect(func(result: Dictionary): results.append(result.duplicate(true)))
		await start_drag("spear")
		var base: Vector2 = ui_point("spear")
		await motion(base, true)
		await mouse(base, false)
		check(app.game.recruitment_queue.size() == 1 and app.game.gold == 215, "Actual terminal fixture retains one previously paid unfinished native order")
		await start_drag("archer")
		var destination: Vector2 = ui_point("archer")
		await motion(destination, true)
		check(not app.deployment_drag.is_empty(), "A second unpaid native drag remains active at the result boundary")
		app.game.enemies.clear()
		app.game.spawn_queue = ["raider"]
		app.game.spawn_source_waves = [1]
		app.game.spawn_metadata = [{}]
		app.game.spawn_clock = 100000.0
		app.game.wave = app.game.total_waves
		var target: float = float(app.game.battle_plan.targetSeconds)
		app.game.elapsed = target - .001
		app.game.wave_time = float(app.game.battle_plan.waves.back().endSeconds) - float(app.game.battle_plan.waves.back().startSeconds) - .001
		var enemy: Dictionary = app.game._spawn_enemy("raider", 1)
		if defeat:
			var route: Dictionary = app.game.paths[int(enemy.pathIndex)]
			enemy.pointIndex = route.points.size() - 1
			enemy.position = route.points.back()
			app.game._objective(str(route.objectiveId)).hp = 1
		else:
			enemy.speed = 0.0
		app.game.advance_simulation(1.0)
		await settle()
		check(results.size() == 1 and app.game.finished and app.battle_finished and app.last_victory == (not defeat) and app.modal_context == "result", "Actual final combat step reaches Main's matching win/loss result modal once")
		var text: String = ""
		for label in app.modal_body.find_children("*", "Label", true, false): text += label.text + "\n"
		check(text.contains("거점 함락" if defeat else "방어 성공"), "Actual result labels describe the preserved battle outcome")
		var timing: Label = app.modal_body.find_child("BattleModeResult", true, false) as Label
		check(timing != null and timing.text.contains("10분 모드") and timing.text.contains("10:00 / 10:00"), "Actual result readout reports the exact existing 10-minute deadline")
		var expected_gold: int = 280 if defeat else 280 + 40 + app.game.total_waves * 3
		check(drag_clear() and app.game.pending.is_empty() and app.game.recruitment_queue.is_empty() and app.game.gold == expected_gold, "Main result cancels the unpaid drag and refunds the accepted unfinished order exactly once")
		await mouse(destination, false)
		check(released_clear(), "Matching native release after the result clears gesture ownership without another order")
		var expected_currency: int = currency if defeat else currency + 148
		check(int(app.progress.data.army.currency) == expected_currency and (app.progress.data.maps.is_empty() if defeat else app.progress.data.maps.size() == 1 and int(app.progress.data.maps.get(map_id, {}).get("wins", 0)) == 1), "Fresh Stage 01 progression and first-clear permanent reward are recorded only on actual victory")
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(app.progress.save_path))
		check(int(saved.army.currency) == expected_currency and (saved.maps.is_empty() if defeat else int(saved.maps.get(map_id, {}).get("wins", 0)) == 1), "The real result flow persists the matching win/loss state in the isolated profile")
		var final_progress: Dictionary = app.progress.data.duplicate(true)
		var final_bytes: PackedByteArray = FileAccess.get_file_as_bytes(app.progress.save_path)
		app._on_battle_finished(app.game.snapshot())
		app._on_battle_finished({"victory":defeat})
		app.game.advance_simulation(20)
		await settle()
		check(results.size() == 1 and app.progress.data == final_progress and FileAccess.get_file_as_bytes(app.progress.save_path) == final_bytes and app.game.gold == expected_gold and app.game.recruitment_queue.is_empty() and app.last_victory == (not defeat), "Repeated result callbacks and further ticks preserve the first outcome without duplicated progress, reward, save or refund")
		observations.append({"case":"main-terminal-result-fixture", "profile":app.progress.save_path, "mapId":map_id, "victory":app.last_victory, "elapsed":app.game.elapsed, "modal":app.modal_context, "permanentCurrency":app.progress.data.army.currency, "maps":app.progress.data.maps.size(), "results":results.size(), "scope":"Bounded last-step simulation and actual Main callback/result/save; not natural battle completion."})
		await cleanup_app()

func run() -> void:
	if not guarded_profile(): quit(2); return
	var frozen_sources: Dictionary = source_hashes()
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).get("units", [])
	backend_contract()
	if failures.is_empty():
		capacity_and_refunds()
		parallel_and_latest_state()
		timing_boundaries()
	if "--backend-only" not in OS.get_cmdline_user_args() and failures.is_empty():
		await fresh_ui()
		if failures.is_empty(): await progressed_revisit()
		if failures.is_empty(): await main_terminal_results()
	var current_sources: Dictionary = source_hashes()
	var frozen: bool = current_sources == frozen_sources
	check(frozen, "Relevant source files remain unchanged while this verifier runs")
	var scope: String = "Explicit Game deployment APIs, atomic revalidation and isolated paid delayed-production/capacity/refund fixtures"
	if "--backend-only" not in OS.get_cmdline_user_args(): scope += " plus actual Main native input and fresh/progressed Stage01 UI"
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"profile":ProjectSettings.globalize_path("user://"),"driver":DisplayServer.get_name(),"sourceFreezeUnchanged":frozen,"sourceHashes":frozen_sources,"finalSourceHashes":current_sources,"scope":scope + "; no GPU terrain or natural battle completion claim."}
	var output: FileAccess = FileAccess.open("user://qa-ui-pilot.json", FileAccess.WRITE)
	if output == null: quit(2); return
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("UI_PILOT ", checks, " checks / ", failures.size(), " failures; report=", ProjectSettings.globalize_path("user://qa-ui-pilot.json"))
	quit(0 if failures.is_empty() else 1)
