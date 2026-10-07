extends SceneTree
## Private navigation fixtures are not evidence of real campaign victories.
const Store = preload("res://native/progress.gd")
const Gate = preload("res://native/learning_gate.gd")
const Portrait = preload("res://native/barracks_portrait.gd")
const WAIT_SECONDS: float = 8.0
const WATCHDOG_SECONDS: float = 150.0

var failures: Array[String] = []
var checks: int = 0
var app: Node
var ending: bool = false
var fixture_stages: int = 0
var profile: String = ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
	return condition

func _canonical(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func _inside(path: String, directory: String) -> bool:
	return not directory.is_empty() and (path == directory or path.begins_with(directory + "/"))

func _guard_profile() -> bool:
	var allowed: String = _canonical(ProjectSettings.globalize_path("res://tests/profiles/"))
	var roaming_raw: String = OS.get_environment("APPDATA")
	var local_raw: String = OS.get_environment("LOCALAPPDATA")
	var roaming: String = _canonical(roaming_raw)
	var local: String = _canonical(local_raw)
	profile = _canonical(ProjectSettings.globalize_path("user://"))
	return check(DisplayServer.get_name() == "headless" and roaming_raw.is_absolute_path() and local_raw.is_absolute_path() and _inside(roaming, allowed) and roaming != allowed and local == roaming and _inside(profile, roaming),
		"Headless APP QA requires matching absolute APPDATA/LOCALAPPDATA beneath this project's tests/profiles and user:// within that isolated directory")

func _watchdog() -> void:
	if ending:
		return
	ending = true
	check(false, "APP QA exceeded its wall-clock deadline; no indefinite wait is allowed")
	_stop_audio()
	print("APP QA: TIMEOUT (", checks, " checks; ", failures.size(), " failures)")
	quit(2)

func _wait_for(predicate: Callable, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while not ending and Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return check(true, message)
		await process_frame
	return check(false, message + " (timed out after %.0f seconds)" % WAIT_SECONDS)

func _stop_audio() -> void:
	if not is_instance_valid(app):
		return
	app._stop_narration()
	if is_instance_valid(app.player):
		app.player.stop()
		app.player.stream = null
	if is_instance_valid(app.battle_audio):
		app.battle_audio.shutdown()

func _finish() -> void:
	if ending:
		return
	ending = true
	print("APP QA: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks; ", failures.size(), " failures; ", fixture_stages, " private navigation fixtures)")
	print("APP QA scope: actual Main navigation, stage music, 10/20-minute selection, paid delayed production, learning/random support and duplicate protection. No full campaign victory, GPU pixels or native speech quality is asserted. Profile: ", profile)
	_stop_audio()
	if is_instance_valid(app):
		if is_instance_valid(app.game):
			app.game.close_battle()
		await create_timer(0.5).timeout
		app.queue_free()
		await process_frame
	quit(0 if failures.is_empty() else 1)

func _unlock_navigation_fixture() -> bool:
	var stages: Array = app.maps.duplicate()
	stages.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("stageNumber", 0)) < int(b.get("stageNumber", 0)))
	for stage in stages:
		var id: String = str(stage.get("id", ""))
		if not check(not id.is_empty() and app.progress.map_unlocked(id), "Navigation fixture advances through the real sequential unlock policy: " + id):
			return false
		var reward: Dictionary = app.progress.complete_map(id, {"seen":0, "correct":0, "attempts":0, "qaNavigationFixture":true})
		if not check(bool(reward.get("saved", true)) and app.progress.map_cleared(id), "Private clear fixture saves through Progress.complete_map: " + id):
			return false
		var lesson: Dictionary = app.progress.stage_lessons.get(id, {})
		var gate: RefCounted = Gate.new()
		var started: Dictionary = gate.start(lesson, id)
		if not check(bool(started.get("ok", false)) and gate._questions.size() > 0 and gate._questions.size() <= 64, "Navigation fixture has a finite real unlock assessment: " + id):
			return false
		# Test-only oracle; the production gate validates and saves its own receipt.
		# This creates neither fabricated receipts nor mastered vocabulary.
		for question in gate._questions:
			var verdict: Dictionary = gate.answer(str(question.get("answerId", "")))
			if not check(bool(verdict.get("accepted", false)) and bool(verdict.get("correct", false)), "Private assessment oracle is accepted: " + id):
				return false
		if not check(app.progress.record_assessment(gate) and app.progress.map_assessed(id), "Navigation fixture persists a current-scope gate receipt: " + id):
			return false
		fixture_stages += 1
	return true

func _check_portraits() -> void:
	for actor_type in app.progress.unlocked_units():
		var path: String = "DeployCard_%s/UnitPortrait_%s" % [actor_type, actor_type]
		var portrait: TextureRect = app.army_grid.get_node_or_null(path) as TextureRect
		var evolution: Dictionary = app.progress.army_evolution(str(actor_type))
		var source: Dictionary = Portrait.resolve_source(str(actor_type), int(evolution.get("stage", 0)))
		if not check(portrait != null and not source.is_empty(), "Approved army portrait binding exists: " + str(actor_type)):
			continue
		var atlas: AtlasTexture = portrait.texture as AtlasTexture
		var expected_path: String = str(source.get("path", ""))
		check(atlas != null and atlas.atlas != null and atlas.atlas.resource_path == expected_path and str(portrait.get_meta("source_path", "")) == expected_path and str(portrait.get_meta("unit_id", "")) == actor_type,
			"Army card uses its actual authored manifest source: " + str(actor_type))

func _key(keycode: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _exercise_learning(hinted: bool, correct: bool) -> bool:
	app._show_quiz()
	if not check(not app.quiz_task.is_empty() and not str(app.quiz_task.get("id", "")).is_empty(), "Learning issues an actual nonempty task"):
		return false
	var task: Dictionary = app.quiz_task.duplicate(true)
	var answer: String = str(task.get("answerId", ""))
	if not check(not answer.is_empty() and task.get("choices", []).size() >= 2, "Issued learning task has a valid answer and at least two choices"):
		return false
	var gold: int = app.game.gold
	var claims: int = app.game.battle_support.claims.size()
	var attempts: int = app.answers_total
	if app.context_task_active:
		app._answer_context(answer)
	else:
		app._answer_quiz(answer)
	check(app.answers_total == attempts and app.game.battle_support.claims.size() == claims, "Opening learning animation blocks early submissions")
	if not await _wait_for(func(): return app.learning_transition.accepts_answers(), "Learning screen reaches its actual answer phase"):
		return false
	check(not app.game.input_enabled, "Learning disables battlefield placement input")
	check(str(task.get("kind", "")) != "listening", "Voice-off fixture does not issue a fabricated listening task")
	if hinted:
		app._quiz_hint()
		check(app.quiz_hinted, "Hint is applied to the issued task")
	if not correct:
		for choice in task.get("choices", []):
			if str(choice.get("id", "")) != answer:
				answer = str(choice.get("id", ""))
				break
	if app.context_task_active:
		app._answer_context(answer)
	else:
		app._answer_quiz(answer)
	check(app.quiz_resolved and app.answers_total == attempts + 1, "A valid learning submission is recorded exactly once")
	check(app.game.gold == gold, "Learning never grants the retired 70/25 combat-gold reward")
	var task_id: String = str(task.get("id", ""))
	if correct:
		var receipt: Dictionary = app.game.battle_support.claims.get(task_id, {})
		check(app.game.battle_support.claims.size() == claims + 1 and bool(receipt.get("ok", false)), "Correct learning grants one battle-only random support receipt")
		check(str(receipt.get("kind", "")) in ["archer_cover", "march_drum", "supply_disruption", "rockfall", "mountain_matchlocks"], "Support is one of the five current kinds")
		check(str(receipt.get("kind", "")) in app.game.battle_support.eligible(int(receipt.get("pathIndex", -1))), "Random support respects the selected front's terrain eligibility")
		check(bool(receipt.get("hinted", false)) == hinted and str(receipt.get("state", "")) == "queued", "Support preserves its hint flag and waits for battle simulation")
		if hinted:
			check(float(receipt.get("strength", 0.0)) > 0.0 and float(receipt.get("strength", 0.0)) < app.game.battle_support.strength(false, str(task.get("kind", ""))), "Hinted support is weaker than the same skill's normal support")
	else:
		check(app.game.battle_support.claims.size() == claims and not app.game.battle_support.claims.has(task_id), "An incorrect answer grants no support")
	var resolved_claims: int = app.game.battle_support.claims.size()
	var recorded_attempts: int = app.progress.data.learning.get("attempts", {}).size()
	if app.context_task_active:
		app._answer_context(answer)
	else:
		app._answer_quiz(answer)
	check(app.answers_total == attempts + 1 and app.game.battle_support.claims.size() == resolved_claims and app.game.gold == gold and app.progress.data.learning.get("attempts", {}).size() == recorded_attempts,
		"A repeated submission cannot duplicate learning, support or currency")
	if not await _wait_for(func(): return app.learning_transition.phase == "result", "Learning feedback reaches the result phase"):
		return false
	app._continue_battle()
	return await _wait_for(func(): return app.quiz_task.is_empty() and app.learning_transition.phase == "idle", "Returning from learning completes and clears its task")

func run() -> void:
	if not _guard_profile():
		quit(2)
		return
	create_timer(WATCHDOG_SECONDS).timeout.connect(_watchdog)
	var scene: PackedScene = load("res://native/main.tscn") as PackedScene
	if not check(scene != null, "Main scene loads"):
		await _finish()
		return
	app = scene.instantiate()
	var fixture: RefCounted = Store.new()
	fixture.save_path = "user://qa-app-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode()
	fixture.data.settings.voice = false
	fixture.data.settings.effects = false
	if not check(fixture.write_save(), "Fresh private fixture saves before Main reads progress"):
		await _finish()
		return
	app.progress = fixture
	root.add_child(app)
	await process_frame
	if not check(app.game != null and app.front_end != null, "Actual Main initializes its battle and front end"):
		await _finish()
		return
	# Only gameplay is stepped manually. Real Main controls, transitions and
	# SceneTree clocks keep running; the test never skips production timers.
	app.game.set_process(false)
	check(app.maps.size() == 40, "App loads forty maps")
	check(app.words_by_id.size() == 900, "App loads nine hundred words")
	check(app.music_by_stage.size() == 40, "Forty stage-specific music assignments load")
	check(app.field_clip.clip_contents, "Battle rendering stays within its viewport")
	check(app.game.three_d_enabled == bool(ProjectSettings.get_setting("application/config/use_3d_units", false)) and app.troops_3d.visible == app.game.three_d_enabled, "Troop renderer follows the installed project setting")
	check(app.front_end.visible and app.front_end.view == "home", "Game starts on the Sengoku title screen")
	_check_portraits()
	var startup_map: String = str(app.game.config.get("id", ""))
	app._choose_stage(3, 9, true)
	check(app.catalog_study_lesson.is_empty() and str(app.game.config.get("id", "")) == startup_map, "A locked stage dictionary is rejected without empty-Dictionary access or battle reset")
	if not _unlock_navigation_fixture():
		await _finish()
		return
	for tier in range(4):
		app._select_tier(tier)
		await process_frame
		var candidates: Array = app.maps.filter(func(stage: Dictionary): return str(stage.get("tier", "")) == app.TIER_IDS[tier])
		if not check(candidates.size() == 10, "Each campaign tier has ten stages"):
			continue
		for index in range(10):
			app._select_map(index)
			await process_frame
			var id: String = str(candidates[index].get("id", ""))
			if not check(str(app.current_map.get("id", "")) == id, "Unlocked tier selection actually loads: " + id):
				continue
			check(str(app.current_map.get("tier", "")) == app.TIER_IDS[tier], "Selected tier matches its map")
			check(is_equal_approx(app.game.three_d_actor_scale, app.troops_3d.actor_base_scale()), "Map shares renderer scale with actor overlays")
			check(app.learning_words.size() >= 15 and not app.current_lesson.is_empty(), "Selected stage has real learning content")
			check(app.modal != null and app.modal_context == "briefing", "Selecting a stage opens its briefing")
			check(str(app.current_music.get("stageId", "")) == id, "Selected stage has its own music assignment")
			var track: AudioStream = app.player.stream
			check(track != null and track.get_length() > 20, "Selected stage track is decodable audio")
			check(track != null and track.resource_path == str(app.music_by_stage.get(id, {}).get("path", "")), "Actual stream matches the selected stage assignment")
	app._select_tier(0)
	app._choose_battle_minutes(20)
	app._select_map(0)
	check(app.battle_minutes == 20 and float(app.game.snapshot().get("battleTargetSeconds", 0)) == 1200.0, "Twenty-minute selection configures the actual battle plan")
	app._choose_battle_minutes(10)
	app._select_map(0)
	check(app.battle_minutes == 10 and float(app.game.snapshot().get("battleTargetSeconds", 0)) == 600.0, "Ten-minute selection configures the actual battle plan")
	_check_portraits()
	app._toggle_music()
	check(not app.player.playing and not bool(app.progress.data.settings.music), "Music-off preference stops playback")
	app._select_map(1)
	await process_frame
	check(not app.player.playing, "Changing stage preserves music-off preference")
	app._toggle_music()
	check(app.player.playing and bool(app.progress.data.settings.music), "Music-on preference starts the selected track")
	app._select_map(0)
	app._begin_battle()
	await process_frame
	check(app.battle_started and app.modal == null and app.game.running, "Briefing starts the real native battle")
	check(app.player.stream != null and app.player.stream.resource_path == str(app.current_music.get("path", "")), "Stage music continues during battle")
	app._show_pause_menu()
	check(app.modal_context == "pause" and app.game.paused, "Operations menu pauses battle")
	app._show_catalog()
	check(app.front_end.visible and app.front_end.battle_active and app.game.paused, "Map browser preserves a paused active battle")
	app._resume_from_navigation()
	app.recruit_button.grab_focus()
	var key_gold: int = app.game.gold
	await _key(KEY_SPACE, true)
	check(app.game.paused and app.game.pending.is_empty() and app.game.gold == key_gold, "Space pauses without activating the focused recruitment control")
	await _key(KEY_SPACE, false)
	await _key(KEY_SPACE, true)
	check(not app.game.paused and app.game.gold == key_gold, "Space resumes without spending supply")
	await _key(KEY_SPACE, false)
	app._show_pause_menu()
	app._show_home()
	check(app.front_end.visible and app.game.paused, "Title navigation pauses the existing battle")
	var original_map: String = str(app.game.config.get("id", ""))
	var original_wave: int = app.game.wave
	var original_gold: int = app.game.gold
	app.front_end.show_catalog(3, true)
	app._choose_stage(3, 9, true)
	check(str(app.game.config.get("id", "")) == original_map and app.game.wave == original_wave and app.game.gold == original_gold, "Browsing another stage's dictionary cannot reset the current battle")
	check(not app.catalog_study_lesson.is_empty() and str(app.catalog_study_lesson.get("id", "")) == str(app.curriculum.get("advanced", [])[9].get("id", "")), "Unlocked dictionary shows the requested stage's lesson")
	app._return_from_study()
	check(app.front_end.visible and app.front_end.study_mode, "Dictionary returns to its stage catalog")
	app._resume_from_navigation()
	check(not app.game.paused and str(app.game.config.get("id", "")) == original_map, "Dictionary navigation resumes the preserved battle")
	app._show_catalog()
	await _key(KEY_R, true)
	check(app.game.pending.is_empty() and app.game.recruitment_queue.is_empty() and app.game.gold == original_gold, "Recruitment shortcuts cannot spend or place behind a menu")
	await _key(KEY_R, false)
	app._resume_from_navigation()
	app._advance_word()
	var word: Dictionary = app.learning_words[app.learning_index]
	check(str(app.active_word.word.get("id", "")) == str(word.get("id", "")) and str(app.example_label.word.get("jp", "")) == str(word.get("example", {}).get("jp", "")), "Battle learning strip shows the actual word and its original example")
	app._choose_unit("archer")
	check(not app.game.pending.is_empty() and app.game.gold == original_gold, "Choosing an emplacement creates a free placement preview")
	app._recruit()
	check(app.game.pending.is_empty() and app.game.gold == original_gold, "Cancelling a preview spends and refunds nothing")
	app._recruit()
	var destination: Vector2 = Vector2(-1, -1)
	for hint in app.game.placement_hints:
		if hint is Vector2 and hint.x >= 0 and bool(app.game.placement_preview(hint).get("valid", false)):
			destination = hint
			break
	if check(destination.x >= 0, "Real archer placement has a legal advertised destination"):
		var cost: int = app.game.recruit_cost("archer")
		check(app.game.place_unit(destination.x, destination.y), "Actual placement commits the production order")
		check(app.game.gold == original_gold - cost and app.game.units.is_empty() and app.game.recruitment_queue.size() == 1 and app.game.pending.is_empty(), "Placement pays exactly once and queues delayed production")
		check(not app.game.place_unit(destination.x, destination.y) and app.game.gold == original_gold - cost, "Repeated placement without a preview cannot charge twice")
		for step in range(80):
			if not app.game.units.is_empty() or app.game.finished or app.game.between_waves:
				break
			app.game.advance_simulation(0.1)
		check(app.game.units.size() == 1 and app.game.recruitment_queue.is_empty() and str(app.game.units[0].get("type", "")) == "archer", "Paid production completes through actual simulation rather than an instant-unit fixture")
	app._on_state(app.game.snapshot())
	for scenario in [{"hinted":false, "correct":true}, {"hinted":true, "correct":true}, {"hinted":false, "correct":false}]:
		if not await _exercise_learning(bool(scenario.hinted), bool(scenario.correct)):
			await _finish()
			return
	app._show_study()
	check(app.modal != null and app.modal_context == "study", "Study opens during battle")
	app._return_from_study()
	# This synthetic result callback checks result-UI idempotency only.
	app._on_battle_finished({"victory":true, "qaResultFixture":true})
	var map_id: String = str(app.current_map.get("id", ""))
	var wins: int = int(app.progress.data.maps.get(map_id, {}).get("wins", 0))
	var army_currency: int = int(app.progress.data.army.currency)
	app._show_study()
	app._return_from_study()
	check(int(app.progress.data.maps.get(map_id, {}).get("wins", 0)) == wins, "Returning from result study cannot duplicate a fixture victory")
	check(int(app.progress.data.army.currency) == army_currency, "Returning from result study cannot duplicate permanent funds")
	app._show_home()
	app._show_barracks()
	check(app.barracks.visible and not app.front_end.visible and app.barracks.can_train, "Barracks opens with training available after the result fixture")
	for definition in app.progress.unit_catalog:
		check(app.barracks.find_child("ArmyCard_%s" % str(definition.get("id", "")), true, false) != null, "Barracks presents the actual roster slot: " + str(definition.get("id", "")))
	app.barracks.hide()
	app._return_from_barracks()
	check(app.front_end.visible and app.front_end.view == "home", "Barracks returns to the home screen")
	await _finish()
