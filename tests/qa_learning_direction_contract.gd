extends SceneTree
## Read actual Game/Presentation/Nav coordinates without a parallel Python
## orientation policy. The generator consumes the resulting hash-bound snapshot.
const Game = preload("res://native/game.gd")
const Gate = preload("res://native/learning_gate.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
const LearningAudio = preload("res://native/learning_audio.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
const Store = preload("res://native/progress.gd")
const BASELINE: String = "res://tests/profiles/learning-direction-contract/baseline/source-baseline.json"
const PROFILE_PREFIX: String = "c:/jp_df/tests/profiles/learning-direction-contract/"
var checks: int = 0
var failures: Array[String] = []
var app: Node
var baseline: Dictionary = {}
var maps: Array = []
var plans: Dictionary = {}
var observations: Array = []
var layout_contract: Dictionary = {}
var source_maps_sha: String = ""
var selected_stage_ids: Array[String] = []
var totals: Dictionary = {"stages":0,"missions":0,"actualTargetPoints":0,"actualMainSupports":0,"voiceKeys":0,"assessmentScopes":40,"preservedWords":900}

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size() <= 30: push_error("LEARNING_DIRECTION: "+note)

func normalize(path: String) -> String:
	return path.replace("\\","/").simplify_path().to_lower().trim_suffix("/")

func option(name: String, fallback: String = "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name+"="): return argument.trim_prefix(name+"=")
	return fallback

func safe_environment() -> bool:
	var appdata: String = normalize(OS.get_environment("APPDATA"))
	var localdata: String = normalize(OS.get_environment("LOCALAPPDATA"))
	var actual: String = normalize(ProjectSettings.globalize_path("user://"))
	check(appdata.begins_with(PROFILE_PREFIX) and localdata == appdata,"APPDATA/LOCALAPPDATA share a private workspace test profile")
	check(actual.begins_with(appdata+"/"),"Actual user:// is contained by that private profile before any scene or save")
	check(DisplayServer.get_name() == "headless","Coordinate verification explicitly runs on CPU/headless")
	# Godot 4.7 removes platform startup switches from get_cmdline_args().
	# The launcher supplies --audio-driver Dummy and repeats its choice here;
	# the saved invocation log is the evidence for the actual startup switch.
	check(option("--qa-audio-driver").to_lower() == "dummy","The CPU launcher records its explicit Dummy audio selection")
	check(not FileAccess.file_exists("user://progress.json"),"The isolated profile contains no default player save")
	return failures.is_empty()

func read_json(path: String) -> Variant:
	check(FileAccess.file_exists(path),"JSON resource exists: "+path)
	var parser: JSON = JSON.new()
	check(parser.parse(FileAccess.get_file_as_string(path)) == OK,"JSON parses: "+path)
	return parser.data

func point(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x",0)),float(value.get("y",0)))

func record(value: Vector2) -> Dictionary:
	return {"x":value.x,"y":value.y}

func scopes(curriculum: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tier in ["basic","beginner","intermediate","advanced"]:
		for lesson in curriculum[tier]: result[str(lesson.id)] = Gate.scope_hash(lesson)
	return result

func snapshot_layout(path: String) -> void:
	var maps_sha: String = source_maps_sha
	var presentation_sha: String = FileAccess.get_sha256("res://native/battlefield_presentation.gd")
	var game_sha: String = FileAccess.get_sha256("res://native/game.gd")
	var game: Node2D = Game.new()
	game.three_d_enabled = true
	root.add_child(game)
	game.set_process(false)
	var stages: Dictionary = {}
	for stage in maps:
		game.load_map(stage)
		check(game.config.id == stage.id,"Actual Game loads coordinate source "+str(stage.id))
		check(game.presentation_mirrored == Presentation.mirror_for_stage(stage),"Actual Game uses the common presentation helper "+str(stage.id))
		var candidates: Array = []
		for index in range(stage.buildZones.size()):
			var zone: Dictionary = stage.buildZones[index]
			var canonical: Vector2 = point(zone)
			candidates.append({"zoneIndex":index,"zoneId":str(zone.id),"canonical":record(canonical),"displayed":record(game.view_point(canonical)),"landSafe":game.ground_combat.land_segment_safe(canonical,canonical),"margin":.008})
		var anchors: Dictionary = {}
		for mission_id in stage.get("historicalBattlefield",{}).get("learningSupportAnchors",{}):
			var canonical: Vector2 = point(stage.historicalBattlefield.learningSupportAnchors[mission_id])
			anchors[mission_id] = {"canonical":record(canonical),"displayed":record(game.view_point(canonical)),"landSafe":game.ground_combat.land_segment_safe(canonical,canonical),"margin":.008}
		stages[str(stage.id)] = {"mirrored":game.presentation_mirrored,"candidates":candidates,"learningSupportAnchors":anchors}
	var curriculum: Dictionary = read_json("res://native/curriculum.json")
	layout_contract = {"version":1,"mapsPath":path,"mapsSha256":maps_sha,"presentationSha256":presentation_sha,"gameSha256":game_sha,"coordinateAuthority":"Actual Game.view_point + BattlefieldPresentation; actual GroundCombat.land_segment_safe(.008)","stages":stages,"currentScopeHashes":scopes(curriculum),"baselineScopeHashes":scopes(baseline.curriculum)}
	check(maps_sha == FileAccess.get_sha256(path) and presentation_sha == FileAccess.get_sha256("res://native/battlefield_presentation.gd") and game_sha == FileAccess.get_sha256("res://native/game.gd"),"Maps and common runtime coordinate sources remain frozen throughout the snapshot")
	check(stages.size() == 40,"Snapshot contains all forty actual coordinate sources")
	check(layout_contract.currentScopeHashes == layout_contract.baselineScopeHashes,"All forty existing assessment scope hashes are unchanged")
	game.queue_free()
	await process_frame
	var output: FileAccess = FileAccess.open("user://learning-layout-contract.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(layout_contract,"  "))
	output.close()

func answer_target(mission: Dictionary) -> Dictionary:
	for target in mission.targets:
		if str(target.id) == str(mission.answerId): return target
	return {}

func same_authored_content(before: Dictionary, after: Dictionary, note: String) -> void:
	var previous: Dictionary = before.duplicate(true)
	var current: Dictionary = after.duplicate(true)
	for value in [previous,current]:
		value.erase("targets")
		value.erase("answerId")
		value.action.erase("position")
	check(previous == current,note+" keeps report/ruby/focus span/grammar/item credits/wave/mission ID/feedback")
	check(answer_target(before).label == answer_target(after).label,note+" keeps the exact requested destination meaning")
	for index in range(3): check(before.targets[index].label == after.targets[index].label,note+" keeps destination label and ruby "+str(index))

func axis_for(mission: Dictionary) -> String:
	var names: Array = []
	for target in mission.targets: names.append(str(target.label.jp))
	if names == ["左の支援点","中央の支援点","右の支援点"]: return "x"
	if names == ["上の支援点","中央の支援点","下の支援点"]: return "y"
	check(names == ["森","川","山"],str(mission.id)+" has a known authored destination meaning family")
	return "nature"

func includes_stage(id: String) -> bool:
	return selected_stage_ids.is_empty() or id in selected_stage_ids

func integration_complete() -> bool:
	var stage_count: int = maps.size() if selected_stage_ids.is_empty() else selected_stage_ids.size()
	var mission_count: int = stage_count*3
	return totals.stages == stage_count and totals.missions == mission_count and totals.actualTargetPoints == mission_count*3 and totals.actualMainSupports == mission_count and totals.voiceKeys == mission_count

func verify_authored_contract() -> void:
	check(FileAccess.get_sha256("res://native/curriculum.json") == baseline.sourceSHA256.curriculum,"All900 words, general examples, grammar and transfer examples retain the original exact bytes")
	check(FileAccess.get_sha256("res://assets/learning-voice/manifest.json") == baseline.sourceSHA256.voice,"The complete3117 voice cache retains the original exact manifest bytes")
	check(FileAccess.get_sha256("res://native/progress.gd") == baseline.sourceSHA256.progress and FileAccess.get_sha256("res://native/learning_gate.gd") == baseline.sourceSHA256.gate,"Progress and assessment implementation retain the original source bytes")
	var voice: Dictionary = read_json("res://assets/learning-voice/manifest.json")
	check(bool(voice.complete) and voice.clips.size() == 3117,"The existing3117 offline voices remain complete")
	check(plans.stages.size() == 40 and baseline.plans.stages.size() == 40,"Exactly forty old and new lesson plans")
	for stage in maps:
		var id: String = str(stage.id)
		if not includes_stage(id): continue
		var before: Dictionary = baseline.plans.stages[id]
		var after: Dictionary = plans.stages[id]
		var previous_metadata: Dictionary = before.duplicate(true)
		var current_metadata: Dictionary = after.duplicate(true)
		previous_metadata.erase("missions")
		current_metadata.erase("missions")
		check(previous_metadata == current_metadata,id+" keeps its goal, lesson, tier and grammar progression identity")
		check(before.missions.size() == 3 and after.missions.size() == 3,id+" retains all three authored missions")
		for index in range(3):
			var mission: Dictionary = after.missions[index]
			same_authored_content(before.missions[index],mission,str(mission.id))
			check(mission.targets == after.missions[0].targets,str(mission.id)+" shares the same three concrete destinations across its stage")
			check(point(mission.action.position).distance_to(point(answer_target(mission).position)) < .00001,str(mission.id)+" action and requested picture use the identical point")
			var overrides: Dictionary = stage.get("historicalBattlefield",{}).get("learningSupportAnchors",{})
			check(point(overrides.get(str(mission.id),mission.action.position)).distance_to(point(answer_target(mission).position)) < .00001,str(mission.id)+" actual Main override agrees with the requested picture/action")
			var key: String = LearningAudio.text_key(str(mission.report.jp))
			check(key == LearningAudio.text_key(str(before.missions[index].report.jp)) and voice.clips.has(key),str(mission.id)+" reuses the exact existing offline voice key")
			if voice.clips.has(key):
				check(str(voice.clips[key].text) == str(mission.report.jp) and ResourceLoader.exists(str(voice.clips[key].path),"AudioStream"),str(mission.id)+" unchanged report resolves to its real imported audio resource")
			totals.voiceKeys += 1

func settle_transition() -> void:
	for unused in range(16):
		if not app.learning_transition.is_busy(): break
		if app.learning_transition.animation != null and app.learning_transition.animation.is_valid():
			app.learning_transition.animation.custom_step(1.0)
		await process_frame
	check(not app.learning_transition.is_busy(),"Actual learning transition reaches its public input-ready phase")

func silence() -> void:
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.set_enabled(false)
	app._apply_audio_settings()

func prepare_prior_progress() -> RefCounted:
	var fixture: RefCounted = Store.new()
	fixture.save_path = "user://direction-main-prior-learning.json"
	for setting in ["music","voice","effects"]: fixture.data.settings[setting] = false
	var records: Array = []
	for tier in baseline.curriculum:
		for lesson in baseline.curriculum[tier]:
			for word in lesson.newWords:
				records.append({"itemId":str(word.id),"skill":"meaning","correct":true,"hinted":false,"contextId":"existing-word:"+str(word.id),"attemptId":"prior-word:"+str(word.id)})
	for id in baseline.plans.stages:
		for mission in baseline.plans.stages[id].missions:
			records.append({"itemId":str(mission.id),"skill":"context","correct":true,"hinted":false,"contextId":"mission:"+str(mission.id),"attemptId":"prior-mission:"+str(mission.id)})
	check(records.size() == 1020,"Private prior-progress fixture covers900 words and120 original mission identities")
	check(bool(fixture.record_learning_batch(records,1704067200.0).accepted),"Original authored IDs create a real atomic private progress receipt")
	fixture.data.learning["assessments"] = {}
	for stage in maps:
		var lesson: Dictionary = fixture.stage_lessons[str(stage.id)]
		var count: int = lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		fixture.data.maps[str(stage.id)] = {"wins":1}
		fixture.data.learning.assessments[str(stage.id)] = {"passed":true,"count":count,"correctCount":count,"scopeHash":layout_contract.baselineScopeHashes[str(lesson.id)],"attemptId":"prior-exam:"+str(stage.id),"passedAt":1704067200.0}
	check(fixture.write_save(),"Existing lesson receipts write only into the guarded test save")
	return fixture

func verify_actual_main() -> void:
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	var fixture: RefCounted = prepare_prior_progress()
	var prior_learning: Dictionary = fixture.data.learning.duplicate(true)
	var prior_army: Dictionary = fixture.data.army.duplicate(true)
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = fixture.save_path
	root.add_child(app)
	for node in [app,app.game,app.atmosphere,app.combat_feedback,app.troops_3d]: node.set_process(false)
	silence()
	await process_frame
	check(app.progress.data.learning == prior_learning,"Actual Main startup retains all900 word/120 mission histories and old assessment receipts without a reset")
	check(app.progress.data.army == prior_army,"Coordinate rebinding keeps the original private army funds and levels")
	var crop_source: Image = Image.create(1280,720,false,Image.FORMAT_RGBA8)
	crop_source.fill(Color(.27,.44,.58,1))
	var crop_texture: ImageTexture = ImageTexture.create_from_image(crop_source)
	for stage_index in range(maps.size()):
		var stage: Dictionary = maps[stage_index]
		if not includes_stage(str(stage.id)): continue
		var plan: Dictionary = plans.stages[str(stage.id)]
		check(app.progress.map_unlocked(str(stage.id)),str(stage.id)+" accepts its preexisting unchanged lesson scope")
		app._choose_stage(stage_index/10,stage_index%10,false)
		app._begin_battle()
		silence()
		check(str(app.current_map.id) == str(stage.id) and str(app.game.config.id) == str(stage.id),str(stage.id)+" actual Main/Game load the same stage")
		var mission_observations: Array = []
		for mission in plan.missions:
			var wave: int = int(mission.wave)
			if wave != 1:
				# Isolate real wave-start/task/support wiring. These are scenario
				# fixtures, never evidence of combat/time-window completion.
				app.game.wave = wave-1
				app.game._begin_wave()
			app.game.between_waves = true
			app.state = app.game.snapshot()
			app._show_quiz()
			await settle_transition()
			var issued: Dictionary = app.quiz_task
			check(str(issued.get("kind","")) == "context" and str(issued.get("mission",{}).get("id","")) == str(mission.id),str(mission.id)+" is issued by the real session and Main context presentation")
			check(app.learning_transition.accepts_answers() and app.context_task_active,str(mission.id)+" actual context input is ready")
			check(app.learning_field.target_buttons.size() == 3 and app.learning_field.target_anchors.size() == 3,str(mission.id)+" actual UI creates all three destination controls/anchors")
			# New artwork is prepared independently. This deterministic texture
			# isolates the real crop/ID/coordinate contract without approving art.
			app.learning_field.stage_texture = crop_texture
			app.learning_field._sync_presentation(issued.mission)
			var displayed: Array = []
			for target_index in range(3):
				var target: Dictionary = issued.mission.targets[target_index]
				var canonical: Vector2 = point(target.position)
				var actual: Vector2 = app.game.view_point(canonical)
				displayed.append(actual)
				check(app.game.ground_combat.land_segment_safe(canonical,canonical),str(mission.id)+" actual target is land-safe "+str(target.id))
				check(stage.buildZones.any(func(zone): return point(zone).distance_to(canonical) < .00001),str(mission.id)+" destination is grounded in an actual native build zone "+str(target.id))
				check(app.learning_field.target_anchors[target_index].distance_to(actual) < .00001,str(mission.id)+" actual UI anchor agrees with Game DISPLAY point "+str(target.id))
				var picture: TextureRect = app.learning_field.target_buttons[target_index].get_node("DestinationImage")
				var crop: AtlasTexture = picture.texture as AtlasTexture
				var extent: Vector2 = Vector2(1280,720)
				var crop_size: Vector2 = extent*Vector2(.34,.42)
				var expected_top_left: Vector2 = canonical*extent-crop_size*.5
				expected_top_left = expected_top_left.clamp(Vector2.ZERO,extent-crop_size)
				check(crop != null and crop.atlas == crop_texture and crop.region.position.distance_to(expected_top_left) < .01 and crop.region.size.distance_to(crop_size) < .01,str(mission.id)+" actual destination picture crops around that identical canonical target "+str(target.id))
				check(picture.flip_h == app.game.presentation_mirrored,str(mission.id)+" picture direction agrees with actual display transform")
				totals.actualTargetPoints += 1
			var axis: String = axis_for(mission)
			for index in range(2):
				if axis == "x": check(displayed[index].x < displayed[index+1].x-.00001,str(mission.id)+" 左/中央/右 follow actual DISPLAY left-to-right")
				if axis == "y": check(displayed[index].y < displayed[index+1].y-.00001,str(mission.id)+" 上/中央/下 follow actual DISPLAY top-to-bottom")
			var expected: Vector2 = point(answer_target(mission).position)
			var supports_before: int = app.game.battle_support.claims.size()
			var funds_before: int = app.game.gold
			app._answer_context(str(issued.answerId))
			check(app.quiz_resolved and app.quiz_outcome_correct,str(mission.id)+" actual Main accepts the issued semantic answer")
			check(app.game.battle_support.claims.size() == supports_before+1,str(mission.id)+" actual Main claims one and only one random support")
			var aura: Dictionary = app.game.battle_support.claims[str(issued.id)]
			check(point(aura.get("requestedAnchor",{})).distance_to(expected) < .00001,str(mission.id)+" actual Main support request, answer, action and picture retain the identical physical anchor")
			check(app.game.gold == funds_before and app.game.learning_supports.is_empty(),str(mission.id)+" approved support replaces cash and prevents the old aura double reward")
			app._answer_context(str(issued.answerId))
			check(app.game.battle_support.claims.size() == supports_before+1 and app.game.gold == funds_before,str(mission.id)+" repeated input cannot reroll or reward twice")
			mission_observations.append({"missionId":mission.id,"axis":axis,"answerMeaning":answer_target(mission).label.jp,"answerCanonical":record(expected),"answerDisplayed":record(app.game.view_point(expected)),"actualSupport":aura,"targets":mission.targets,"cropSource":"Deterministic1280x720QAtexture; visual artwork review is separate"})
			totals.actualMainSupports += 1
			totals.missions += 1
			await settle_transition()
			app._continue_battle()
			await settle_transition()
			check(app.quiz_task.is_empty(),str(mission.id)+" real return consumes its issued task")
		if stage_index==0:
			for word in app.learning_words:
				if not str(word.id) in app.seen_this_run: app.seen_this_run.append(str(word.id))
			for hinted in [false,true]:
				app.game.wave=2
				app.game.between_waves=true
				app.state=app.game.snapshot()
				app._show_quiz()
				await settle_transition()
				var issued: Dictionary=app.quiz_task.duplicate(true)
				check(not issued.is_empty() and str(issued.get("kind",""))!="context","General task uses actual normal result modal")
				if issued.is_empty(): continue
				if hinted: app._quiz_hint()
				var gold: int=app.game.gold
				var count: int=app.game.battle_support.claims.size()
				app._answer_quiz(str(issued.answerId))
				check(app.quiz_resolved and app.quiz_outcome_correct and app.game.gold==gold,"Normal/hinted correct answer replaces cash with support")
				var receipt: Dictionary=app.game.battle_support.claims[str(issued.id)]
				check(receipt.hinted==hinted and receipt.state=="queued" and app.game.battle_support.claims.size()==count+1,"Actual result fixes hint strength and one queued random reward")
				check(app.quiz_feedback.text.contains(str(receipt.nameKo)) and not app.quiz_feedback.text.contains("금화"),"Actual result displays support name and short effect")
				app._answer_quiz(str(issued.answerId))
				check(app.game.battle_support.claims.size()==count+1 and app.game.gold==gold,"Repeated actual normal input cannot reroll or pay twice")
				await settle_transition()
				app._continue_battle()
				await settle_transition()
				check(app.quiz_task.is_empty() and not app.game.paused,"Actual result returns to battle without a selection card")
		observations.append({"stageId":stage.id,"stageNumber":stage.stageNumber,"mirroredForDisplay":app.game.presentation_mirrored,"missions":mission_observations})
		totals.stages += 1
		app._show_catalog()
		await process_frame
	check(integration_complete(),"Every required stage/mission/target/Main support/voice observation is complete within the declared stage selection")
	app.progress.read_save()
	check(app.progress.data.learning.items.size() == 1020 and app.progress.data.learning.assessments == prior_learning.assessments,"All original900 word/120 mission histories and unchanged40 unlock receipts remain after real support answers/reload")
	silence()
	for service in [app.battle_audio,app.battle_narrator,app.battle_announcer,app.voice_director]: service.shutdown()
	app.free()
	await process_frame
	Battlefield.release_shared_resources()
	for frame in range(6): await process_frame

func run() -> void:
	if not safe_environment():
		quit(2)
		return
	baseline = read_json(BASELINE)
	var path: String = option("--maps","res://native/maps.json")
	check(path == "res://native/maps.json" or normalize(path).begins_with("c:/jp_df/tests/profiles/"),"Alternate coordinate source is an isolated project draft")
	if not failures.is_empty():
		quit(2)
		return
	var maps_text: String = FileAccess.get_file_as_string(path)
	source_maps_sha = maps_text.sha256_text()
	var decoded: Variant = JSON.parse_string(maps_text)
	check(decoded is Array and decoded.size() == 40,"Coordinate source parses all forty stages")
	if not decoded is Array or decoded.size() != 40:
		quit(2)
		return
	maps = decoded
	var stage_selection: String = option("--stage-ids")
	if not stage_selection.is_empty():
		for id in stage_selection.split(",",false):
			check(not id in selected_stage_ids and maps.any(func(stage): return str(stage.id) == id),"Selected Main stage is unique and exists in the forty-stage coordinate source: "+id)
			selected_stage_ids.append(id)
		if not failures.is_empty():
			quit(2)
			return
	await snapshot_layout(path)
	if not "--snapshot-only" in OS.get_cmdline_user_args():
		check(path == "res://native/maps.json","Actual Main integration uses the published source, never a private draft")
		plans = read_json("res://native/learning_plans.json")
		verify_authored_contract()
		if failures.is_empty(): await verify_actual_main()
		# Keep completion checks outside the integration coroutine as well:
		# an unexpected engine/script exception must never become a partial pass.
		check(integration_complete(),"Integration returned only after every observation required by its explicit stage selection completed")
		var output: FileAccess = FileAccess.open("user://qa_learning_direction_contract.json",FileAccess.WRITE)
		output.store_string(JSON.stringify({"checks":checks,"failures":failures,"totals":totals,"pass":failures.is_empty(),"selectedStageIds":selected_stage_ids,"coordinateSnapshotStages":layout_contract.stages.size(),"sourceMapsSha256":source_maps_sha,"plansSha256":FileAccess.get_sha256("res://native/learning_plans.json"),"curriculumSha256":FileAccess.get_sha256("res://native/curriculum.json"),"voiceSha256":FileAccess.get_sha256("res://assets/learning-voice/manifest.json"),"scopeHashes":layout_contract.currentScopeHashes,"baselineScopeHashes":layout_contract.baselineScopeHashes,"observations":observations,"scope":"CPU actual Main task/support for the explicit selected stages (empty selection means all40), common DISPLAY/land Nav, deterministic destination crop coordinates, original text/ruby/voice keys and private prior-learning persistence. Wave numbers are advanced as test scenarios; this does not approve new artwork, combat completion, audio playback, FPS or a packaged build."},"  "))
		output.close()
	print("LEARNING_DIRECTION ",checks," checks / ",failures.size()," failures; snapshot=",ProjectSettings.globalize_path("user://learning-layout-contract.json")," mapsSHA=",layout_contract.mapsSha256)
	quit(0 if failures.is_empty() else 1)
