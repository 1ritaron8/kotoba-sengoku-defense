extends SceneTree
## Empty playable-map startup and save preservation in disposable profiles.
## Historical receipts are fixtures, not campaign-victory or GPU evidence.
const Store = preload("res://native/progress.gd")
const Gate = preload("res://native/learning_gate.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var app: Node
var capture_requested: bool = false
var captures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> bool:
	checks += 1
	if not value:
		failures.append(note)
		push_error("MAP_RESET " + note)
	return value

func canonical(value: String) -> String:
	return value.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func guarded_profile() -> bool:
	var boundary: String = canonical(ProjectSettings.globalize_path("res://tests/profiles/"))
	var roaming: String = canonical(OS.get_environment("APPDATA"))
	var local: String = canonical(OS.get_environment("LOCALAPPDATA"))
	var save: String = canonical(ProjectSettings.globalize_path("user://"))
	var display_allowed: bool = DisplayServer.get_name() != "headless" if capture_requested else DisplayServer.get_name() == "headless"
	return check(display_allowed and roaming.begins_with(boundary + "/map-reset-") and local == roaming and save.begins_with(roaming + "/"), "Verifier refuses player profiles and requires an explicit capture flag for GPU runs")

func settle(count: int = 3) -> void:
	for unused in range(count): await process_frame

func capture_frame(label_value: String) -> void:
	if not capture_requested: return
	await settle()
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	if not check(pixels != null and not pixels.is_empty(), "Actual GPU framebuffer exists: " + label_value): return
	check(pixels.get_size() == root.size, "Actual GPU framebuffer has requested resolution: " + label_value)
	var path: String = "user://map-reset-" + label_value + ".png"
	if check(pixels.save_png(path) == OK, "Actual GPU screenshot saves: " + label_value):
		captures.append({"label":label_value,"path":ProjectSettings.globalize_path(path),"size":[pixels.get_width(),pixels.get_height()]})

func write_fixture(path: String, value: Dictionary) -> bool:
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if output == null: return false
	output.store_string(JSON.stringify(value, "  "))
	output.close()
	return true

func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["native/main.gd","native/front_end.gd","native/progress.gd","native/maps.json","tests/qa_map_reset.gd"]:
		result[path] = FileAccess.get_file_as_string("res://" + path).sha256_text()
	return result

func campaign_ids() -> Array[String]:
	var result: Array[String] = []
	var history: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	for entry in history.get("stages",[]):
		if int(entry.get("stageNumber",0))<=14: result.append(str(entry.stageId))
	return result

func progressed_fixture(path: String) -> RefCounted:
	var fixture: RefCounted = Store.new()
	fixture.save_path = path
	fixture.data.settings.music = false
	fixture.data.settings.voice = false
	fixture.data.settings.effects = false
	fixture.data.settings.battleMinutes = 20
	for id in campaign_ids():
		fixture.data.maps[id] = {"wins":2,"correct":4,"bestAccuracy":1.0,"lastPlayedAt":1000.0}
	fixture.data.maps["archived-map-not-in-campaign"] = {"wins":3,"archiveNote":"Historical receipt retained while playable content is rebuilt"}
	fixture.data.army.currency = 5678
	fixture.data.army.levels.spear = 5
	fixture.data.army.levels.gunner = 7
	fixture.data.army.selected = "spear"
	fixture.data.army.training = {"spear":true,"gunner":true}
	var lesson: Dictionary = fixture.stage_lessons.get("basic-forest",{})
	var item_id: String = str(lesson.get("newWords",[])[0].id) if not lesson.get("newWords",[]).is_empty() else "historical-word"
	fixture.data.words[item_id] = {"seen":7,"correct":5,"wrong":1,"hinted":1,"streak":2}
	var context: Dictionary = fixture._new_skill()
	context.exposures = 7
	context.correct = 5
	context.cleanSuccesses = 2
	context.cleanStreak = 2
	context.lastOutcome = "correct"
	context.lastExposureAt = Time.get_unix_time_from_system()-120
	fixture.data.learning = {"items":{item_id:{"context":context}},"attempts":{"saved-attempt":{"skill":"context","itemId":item_id,"outcome":"correct"}},"assessments":{},"lastClockAt":Time.get_unix_time_from_system()-120}
	var count: int = lesson.get("newWords",[]).size()+lesson.get("grammarSteps",[]).size()
	fixture.data.learning.assessments["basic-forest"] = {"passed":true,"correctCount":count,"count":count,"scopeHash":Gate.scope_hash(lesson),"attemptId":"saved-gate","passedAt":1000.0}
	fixture.data.learning.assessments["archived-map-not-in-campaign"] = {"passed":true,"correctCount":2,"count":2,"scopeHash":"a".repeat(64),"attemptId":"archived-gate","passedAt":1000.0}
	check(write_fixture(path,fixture.data), "Version3 historical fixture is written only to isolated user storage")
	fixture.read_save()
	check(not fixture.playable_catalog_available and fixture.stage_numbers.get("basic-forest",0) == 1 and fixture.previous_map("basic-farm") == "basic-forest", "Historical stage identity and lesson chain survive an empty playable catalog")
	check(fixture.data.maps.size() == 15 and fixture.data.maps.has("archived-map-not-in-campaign"), "Empty map catalog preserves recognized and archived historical wins")
	check(fixture.data.army.currency == 5678 and fixture.army_level("spear") == 5 and fixture.army_level("gunner") == 7 and str(fixture.data.army.selected) == "spear" and fixture.unlocked_units().size() == 8 and fixture.is_unit_trained("spear") and fixture.is_unit_trained("gunner"), "Saved currency, permanent levels, selection, unlocks and training remain intact")
	check(fixture.data.learning.assessments.has("basic-forest") and fixture.data.learning.assessments.has("archived-map-not-in-campaign") and fixture.map_assessed("basic-forest"), "Historical learning assessment receipts and their actual lesson scope survive")
	check(int(fixture.data.words[item_id].seen) == 7 and int(fixture.data.learning.items[item_id].context.exposures) == 7 and fixture.data.learning.attempts.has("saved-attempt"), "Vocabulary counters, spaced-learning state and attempt receipts are preserved")
	var expected: Dictionary = fixture.data.duplicate(true)
	check(fixture.write_save(), "Version3 fixture can be saved with zero playable maps")
	var reread: RefCounted = Store.new()
	reread.save_path = path
	reread.read_save()
	check(reread.data == expected, "Version3 read/write/read roundtrip preserves the entire normalized historical account")
	observations.append({"case":"v3-historical-roundtrip","historicalWins":reread.data.maps.size(),"playableMaps":0,"currency":reread.data.army.currency,"unlocked":reread.unlocked_units(),"fixtureOnly":true})
	return reread

func legacy_fixture() -> void:
	var path: String = "user://map-reset-v1.json"
	var wins: Dictionary = {"basic-forest":{"wins":2},"basic-farm":{"wins":1},"archived-v1-map":{"wins":4}}
	var legacy: Dictionary = {"version":1,"maps":wins,"words":{"legacy-word":{"seen":9,"correct":6,"wrong":2,"hinted":1,"streak":1}},"settings":{"music":false,"voice":false,"effects":false,"battleMinutes":10}}
	check(write_fixture(path,legacy), "Version1 fixture is written without touching player saves")
	var fixture: RefCounted = Store.new()
	fixture.save_path = path
	fixture.read_save()
	var persisted_wins: Dictionary = JSON.parse_string(JSON.stringify(wins))
	check(fixture.data.maps == persisted_wins and int(fixture.data.words["legacy-word"].seen) == 9 and int(fixture.data.words["legacy-word"].correct) == 6, "Existing version1 compatibility preserves wins and word counters despite removed terrain")
	check(int(fixture.data.army.currency) == 180+(140+1*8)+(140+2*8), "Existing version1 first-clear funding uses stable historical stage numbers, with no invented reward for unknown IDs")
	var expected: Dictionary = fixture.data.duplicate(true)
	check(fixture.write_save(), "Existing version1 compatibility result can be saved in isolated storage")
	var reread: RefCounted = Store.new()
	reread.save_path = path
	reread.read_save()
	check(reread.data == expected, "Version1 compatibility roundtrip preserves its normalized account and archived receipt")
	observations.append({"case":"v1-existing-compatibility","historicalWins":reread.data.maps.size(),"currency":reread.data.army.currency,"fixtureOnly":true,"scope":"Existing v1 compatibility is retained; no new save-schema migration"})

func mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	await settle(1)

func gameplay_is_empty() -> bool:
	return app.maps.is_empty() and app.current_map.is_empty() and app.game.config.is_empty() and not app.battle_started and not app.game.running and not app.game.input_enabled and app.game.gold == 0 and app.game.paths.is_empty() and app.game.objectives.is_empty() and app.game.units.is_empty() and app.game.enemies.is_empty() and app.game.recruitment_queue.is_empty() and app.game.pending.is_empty()

func startup_and_navigation(fixture: RefCounted) -> void:
	root.size = Vector2i(1280,800)
	root.content_scale_size = root.size
	var expected: Dictionary = fixture.data.duplicate(true)
	app = load("res://native/main.tscn").instantiate()
	app.progress = fixture
	root.add_child(app)
	app.set_process(false)
	app.game.set_process(false)
	app.atmosphere.set_process(false)
	app.troops_3d.set_process(false)
	await settle()
	check(gameplay_is_empty() and app.front_end.visible and not app.field_clip.visible and not app.ui.visible and app.modal == null, "Actual Main starts in the menu with no fake stage, terrain, routes, actors, orders or battlefield input")
	check(app.catalog_preparation_ready and not app.catalog_preparation_started and app.get_node_or_null("CatalogPreparationRenderer") == null, "Zero-map startup skips all battlefield preview construction")
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		app._layout()
		app.front_end.show_home()
		await settle()
		for name_value in ["HomeSortie","HomeDictionary","HomeCampaignMap","HomeTraining"]:
			var action: Button = app.front_end.get_node_or_null(name_value) as Button
			check(action != null and action.disabled and root.get_visible_rect().encloses(action.get_global_rect()), "Map-dependent menu control is visibly disabled inside " + str(dimensions) + ": " + name_value)
		for name_value in ["HomeBarracks","HomeSettings","HomeExit"]:
			var action: Button = app.front_end.get_node_or_null(name_value) as Button
			check(action != null and not action.disabled, "Independent menu feature remains enabled: " + name_value)
		var status: Label = app.front_end.get_node("HomeCatalogPreparation") as Label
		check(status.text.contains("재설계") and status.text.contains("0개"), "Menu clearly states zero playable maps under reconstruction")
		if capture_requested:
			await capture_frame("home-%dx%d" % [dimensions.x,dimensions.y])
			app._show_catalog()
			await capture_frame("catalog-%dx%d" % [dimensions.x,dimensions.y])
			app._show_home()
			await settle()
	var sortie: Button = app.front_end.get_node("HomeSortie") as Button
	await mouse(sortie.get_global_rect().get_center(),true)
	await mouse(sortie.get_global_rect().get_center(),false)
	check(gameplay_is_empty() and app.front_end.view == "home", "Native pointer activation on disabled sortie cannot start a stage")
	app._select_map(0)
	app._choose_stage(0,0)
	app._start_gate_from_catalog(0,0)
	app._show_briefing()
	app._show_study()
	app._show_unit_training("archer")
	app._begin_battle()
	app._resume_from_navigation()
	await settle()
	check(gameplay_is_empty() and app.front_end.visible and app.modal == null and not app.unit_training.visible and not app.gate_active, "Direct stage, study, drill, briefing, assessment and resume entry points reject absent content safely")
	app._prepare_catalog_previews()
	check(app.get_node_or_null("CatalogPreparationRenderer") == null and app.catalog_preparation_ready, "Explicit preview preparation cannot synthesize an old map or renderer")
	app._show_catalog()
	await settle()
	check(app.front_end.get_node_or_null("CatalogEmptyStatus") != null and gameplay_is_empty(), "Empty catalog renders a reconstruction state instead of indexing its absent first stage")
	app.front_end.show_campaign_map()
	await settle()
	check(app.front_end.get_node_or_null("CatalogEmptyStatus") != null and app.front_end.get_node_or_null("CampaignAtlas") == null and gameplay_is_empty(), "Empty atlas safely displays content status without rebuilding old stage markers")
	app._show_home()
	app._show_barracks()
	await settle()
	check(app.barracks.visible and gameplay_is_empty() and app.progress.army_level("gunner") == 7, "Barracks remain accessible with saved progression and no playable map")
	await capture_frame("barracks-1440x900")
	app.barracks.hide()
	app._return_from_barracks()
	app.front_end.view = "settings"
	app.front_end._rebuild()
	await settle()
	check(app.front_end.view == "settings" and app.front_end.visible and gameplay_is_empty(), "Independent settings remain available without terrain")
	check(app.progress.data == expected, "Empty-content startup and navigation do not mutate historical saves, words, levels, currency or receipts")
	observations.append({"case":"actual-empty-Main-navigation","sizes":[[1280,800],[1440,900]],"playableMaps":0,"historicalRecords":app.progress.data.maps.size(),"scope":"Actual native UI/state verification with GPU screenshots" if capture_requested else "Headless native UI/state verification; no GPU pixels or gameplay completion claim"})
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	app.game.close_battle()
	app.queue_free()
	await settle()
	app = null
	check(fixture.write_save(), "Historical account still saves after empty-game teardown")
	var reread: RefCounted = Store.new()
	reread.save_path = fixture.save_path
	reread.read_save()
	check(reread.data == expected, "Empty-game teardown/read/write does not erase historical progression")

func run() -> void:
	capture_requested = "--capture" in OS.get_cmdline_user_args()
	if not guarded_profile(): quit(2); return
	var sources: Dictionary = source_hashes()
	var map_data = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if not check(map_data is Array and map_data.is_empty(), "Verifier requires the actual map catalog to be reset empty; no forced test-only replacement"):
		quit(2)
		return
	var fixture: RefCounted = progressed_fixture("user://map-reset-v3.json")
	legacy_fixture()
	await startup_and_navigation(fixture)
	check(source_hashes() == sources, "Guard sources and actual empty catalog remain unchanged during verification")
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"sourceHashes":sources,"sourceFreezeUnchanged":source_hashes() == sources,"profile":ProjectSettings.globalize_path("user://"),"captures":captures,"displayDriver":DisplayServer.get_name(),"gpu":RenderingServer.get_video_adapter_name() if capture_requested else "","scope":"Actual empty-map native startup, disabled stage entry and historical v3/v1-compatible account persistence using isolated fixtures. " + ("GPU captures cover menus only; no fake gameplay stage." if capture_requested else "No GPU or fake gameplay stage.")}
	var output: FileAccess = FileAccess.open("user://qa-map-reset.json",FileAccess.WRITE)
	if output == null: quit(2); return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("MAP_RESET ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path("user://qa-map-reset.json"))
	quit(0 if failures.is_empty() else 1)
