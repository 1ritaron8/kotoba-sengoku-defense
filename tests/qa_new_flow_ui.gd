extends SceneTree
const Store = preload("res://native/progress.gd")
const Gate = preload("res://native/learning_gate.gd")
const Cloze = preload("res://native/learning_cloze.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var images: Array = []
var capture_enabled: bool = false
var packed: bool = false

func _initialize() -> void:
	Engine.max_fps = 90
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size()<25: push_error("NEW_FLOW: "+note)

func settle() -> void:
	for unused in range(4): await process_frame

func ready_phase() -> void:
	for unused in range(1200):
		if not app.learning_transition.is_busy(): break
		if DisplayServer.get_name()=="headless" and app.learning_transition.animation!=null and app.learning_transition.animation.is_valid():
			app.learning_transition.animation.pause()
			app.learning_transition.animation.custom_step(1.0)
		await process_frame
	check(not app.learning_transition.is_busy(),"Actual learning controller reaches its action phase")

func capture(name: String) -> void:
	if not capture_enabled: return
	app._layout()
	app.troops_3d._process(0)
	await settle()
	await RenderingServer.frame_post_draw
	var path: String = "user://new-flow-%s-%dx%d.png" % [name,root.content_scale_size.x,root.content_scale_size.y]
	check(root.get_texture().get_image().save_png(path)==OK,"GPU image saved: "+name)
	images.append(ProjectSettings.globalize_path(path))

func correct_choice(task: Dictionary, lesson: Dictionary) -> String:
	var expected: String = ""
	if task.has("wordId"):
		for word in lesson.newWords:
			if str(word.id)==str(task.wordId): expected = str(Cloze.build(word.example,word).cloze.answerText)
	else:
		for step in lesson.get("grammarSteps",[]):
			if str(step.id)==str(task.get("grammarId","")):
				for option in step.assessment.choices:
					if str(option.id)==str(step.assessment.answerId): expected=str(option.jp)
	for option in task.get("choices",[]):
		if str(option.get("item",{}).get("jp",""))==expected: return str(option.id)
	check(false,"An independently read curriculum answer exists in the issued choices")
	return ""

func question_geometry() -> void:
	app._layout()
	await settle()
	check(str(app.quiz_ruby.word.jp).count("＿＿")==1,"Only one target span is blank in the actual subtitle")
	check(app.quiz_ruby.meaning_visible and not str(app.quiz_ruby.word.ko).is_empty(),"The sentence keeps its Korean semantic cue")
	check(app.quiz_ruby.modulate.a==1.0,"An announcement never hides the question")
	check(not app.quiz_ruby.get_global_rect().intersects(app.quiz_announcement_slot.get_global_rect()),"The guide has a separate header slot")
	check(root.get_visible_rect().encloses(app.modal_footer.get_global_rect()),"Question action controls fit the viewport")
	for card in app.quiz_choices:
		check(not card.get_global_rect().intersects(app.modal_footer.get_global_rect()),"Answer cards preserve the action row")
		var ruby: Control = card.get_node("ChoiceRuby")
		check(ruby.base_size==34 and ruby.get_text_layout().ruby_size>=16,"Choices use large Japanese text and readable furigana")
		for run in ruby.get_text_layout().runs:
			check(Rect2(Vector2.ZERO,ruby.size).grow(1).encloses(run.bounds),"Choice glyphs fit their actual Ruby control")

func training_entry() -> void:
	root.content_scale_size=Vector2i(1280,800)
	root.size=Vector2i(1280,800)
	app._show_home()
	await settle()
	var entry: Button = app.front_end.get_node("HomeTraining")
	for menu_name in ["HomeSortie","HomeBarracks","HomeTraining","HomeDictionary"]:
		var menu: Control = app.front_end.get_node(menu_name)
		check(root.get_visible_rect().encloses(menu.get_global_rect()),"The home menu fits the minimum viewport: "+menu_name)
		var ruby: Control = menu.get_child(0)
		for run in ruby.get_text_layout().runs:
			check(menu.get_global_rect().grow(1).encloses(Rect2(ruby.global_position+run.bounds.position,run.bounds.size)),"Home furigana, Japanese and Korean glyphs fit their menu row: "+menu_name)
	check(not entry.get_global_rect().intersects(app.front_end.get_node("HomeDictionary").get_global_rect()),"The separate training entry preserves the dictionary menu")
	await capture("home-training")
	var before: Dictionary = app.progress.data.duplicate(true)
	var campaign_clock: float = app.game.elapsed
	entry.pressed.emit()
	await settle()
	check(app.unit_training.visible and app.unit_training.view=="menu" and not app.front_end.visible,"The actual home action opens the separate training menu")
	check(app.unit_training.z_index>app.front_end.z_index,"The drill controller appears above navigation")
	app.unit_training.render_enabled=capture_enabled
	check(app.unit_training.open("archer",app.maps[0]),"An unlocked archery drill opens through the real controller")
	app.unit_training.set_process(false)
	await settle()
	check(app.unit_training.deploy() and app.unit_training.place_at(app.unit_training.recommended),"The drill uses the real preparation and placement controls")
	await capture("training-archer")
	for unused in range(1600):
		if app.unit_training.phase not in ["producing","combat"]: break
		app.unit_training.advance_training(.05)
	check(app.unit_training.phase=="success" and app.progress.is_unit_trained("archer"),"Actual drill hits emit completion and save the badge in Main")
	check(app.game.elapsed==campaign_clock and app.progress.data.maps==before.maps and app.progress.data.words==before.words and app.progress.data.learning==before.learning and app.progress.data.army.currency==before.army.currency,"Training leaves the paused campaign and all rewards/learning untouched")
	await capture("training-complete")
	app.unit_training.close()
	await settle()
	check(app.front_end.visible and app.front_end.view=="home","Closing a home drill returns to the actual home menu")
	app._show_barracks()
	await settle()
	var button: Button = app.barracks.get_node("BarracksTraining")
	check(root.get_visible_rect().encloses(button.get_global_rect()),"The barracks training action fits its header")
	button.pressed.emit()
	await settle()
	check(app.unit_training.visible and app.training_return_view=="barracks","The barracks action opens a separate drill menu")
	app.unit_training.close()
	await settle()
	check(app.barracks.visible and not app.front_end.visible,"Closing a barracks drill returns to its selected troop")
	app.barracks.hide()
	app._return_from_barracks()

func progression_store() -> RefCounted:
	var store = Store.new()
	store.save_path = "user://chain-check.json"
	check(store.map_unlocked(str(app.maps[0].id)),"A new profile opens its first map")
	for index in range(40):
		var stage: Dictionary = app.maps[index]
		check(store.map_unlocked(str(stage.id)),"Passed prerequisites open stage %d" % (index+1))
		if index<39: check(not store.map_unlocked(str(app.maps[index+1].id)),"The next stage stays locked before a clear")
		store.complete_map(str(stage.id),{"correct":0})
		if index<39: check(not store.map_unlocked(str(app.maps[index+1].id)),"Victory alone cannot open the next stage")
		var gate = Gate.new()
		var lesson: Dictionary = store.stage_lessons[str(stage.id)]
		check(bool(gate.start(lesson,str(stage.id)).ok),"The complete authored lesson can be assessed")
		check(not store.record_assessment(gate),"An unfinished assessment cannot be stored as passed")
		while not bool(gate.snapshot().complete):
			var task: Dictionary = gate.current_task()
			check(bool(gate.answer(correct_choice(task,lesson)).correct),"An actual vocabulary/grammar answer is correct")
		check(store.record_assessment(gate),"Only a completed all-correct assessment saves")
		check(store.map_assessed(str(stage.id)),"The saved scope covers the entire current lesson")
		if index<39: check(store.map_unlocked(str(app.maps[index+1].id)),"Clear plus full assessment opens exactly the next stage")
	check(store.campaign_unified(),"All forty clears and prerequisite assessments complete the campaign")
	var restored = Store.new()
	restored.save_path = store.save_path
	restored.read_save()
	check(restored.campaign_unified() and restored.map_unlocked(str(app.maps[39].id)),"The complete campaign unlock chain survives a real save/reload")
	restored.data.learning.assessments[str(app.maps[38].id)].scopeHash = "0".repeat(64)
	check(not restored.map_unlocked(str(app.maps[39].id)),"A stale immediate predecessor certificate cannot open the next battle")
	var before: Dictionary = store.data.duplicate(true)
	store._save_read_blocked = true
	var replay = Gate.new()
	var first: Dictionary = store.stage_lessons[str(app.maps[0].id)]
	replay.start(first,str(app.maps[0].id))
	while not bool(replay.snapshot().complete): replay.answer(correct_choice(replay.current_task(),first))
	check(not store.record_assessment(replay) and store.data==before,"A failed save rolls back the assessment transaction")
	store._save_read_blocked=false
	return store

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/new-flow"):
		push_error("New flow QA refuses the player's profile")
		quit(2)
		return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	packed = "--packed" in OS.get_cmdline_user_args()
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://new-flow-%d.json" % Time.get_ticks_msec()
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	app.progress.data.settings.voice = false
	app.progress.data.settings.music = false
	app._stop_narration()
	app.player.stop()
	check(app.words_by_id.size()==900 and app.maps.size()==40,"The authored vocabulary and unique forty stages remain")
	check(app.campaign_story.get("stages",[]).size()==40 and str(app.current_story.get("stageId",""))==str(app.current_map.id),"The actual Main loads all forty linked historical chapters")
	await training_entry()
	app._show_catalog()
	app.front_end._select_catalog_stage(1)
	await settle()
	check(app.front_end.get_node("CatalogSortie").disabled,"The actual future-stage button is locked")
	var current_id: String = str(app.current_map.id)
	app._choose_stage(0,1)
	check(str(app.current_map.id)==current_id,"A direct callback cannot enter a locked map")
	await capture("locked-map")
	app._select_map(0)
	check(app.modal_body.find_child("StoryIntroduction",true,false)!=null and app.modal_body.find_child("StoryOpponent",true,false)!=null,"The real briefing explains this battle and its named Japanese opponent")
	app._begin_battle()
	await settle()
	var initial_words: int = app.seen_this_run.size()
	var report_time: float = app.learning_field.report_clock
	for unused in range(1000): app._process(.25)
	check(app.seen_this_run.size()>=15 and app.seen_this_run.size()>initial_words,"All fifteen beginner words rotate while a passive report remains")
	check(report_time>=17.5 and app._word_dwell_seconds()>=12.0,"Reports and word sentences provide adequate dwell time after the presentation frames")
	var gold: int = app.game.gold
	app.army_grid.get_node("DeployCard_spear").pressed.emit()
	check(app.game.gold==gold-65 and app.game.units.is_empty() and app.game.pending.is_empty() and app.game.snapshot().recruitmentQueue.size()==1,"One actual marching card click pays once and starts its independent production before birth")
	app.game.advance_simulation(2.275)
	check(app.game.units.size()==1 and app.game.snapshot().recruitmentQueue.is_empty(),"A paid spear appears only after its cost-proportional generation time")
	if app.game.units.is_empty():
		app.queue_free()
		quit(1)
		return
	var unit: Dictionary = app.game.units[0]
	check(str(unit.deploymentKind)=="marching" and unit.position.distance_to(unit.spawnPosition)<.0001,"Sortie starts at the authored allied base")
	app.game._process(.2)
	app._on_state(app.game.snapshot())
	app._layout()
	await settle()
	for card in app.army_grid.get_children():
		var badge: Label = card.get_node("DeploymentKindBadge")
		var name_label: Label = card.get_node("UnitNameLabel")
		check(app.army_scroll.get_global_rect().grow(1).encloses(badge.get_global_rect()),"Every deployment role remains fully visible in the bottom roster")
		check(app.font.get_string_size(name_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x<=name_label.size.x,"The actual unit name fits its roster card without truncation")
	check(not app.army_tactics.get_global_rect().intersects(app.army_health.get_global_rect()),"Long troop status text preserves the health bar")
	check(str(unit.combatState)=="gather" and float(unit.gatherRemaining)>0,"A new marching unit briefly rallies at base")
	app.game.advance_simulation(2.7)
	app._on_state(app.game.snapshot())
	check(float(unit.routeDistance)<float(unit.routeMax) and str(unit.animation)=="walk","After rally a sortie uses actual marching animation")
	var guide: Dictionary = {"jp":"正解です","reading":"せいかいです","ko":"정답입니다","parts":[{"text":"正解","reading":"せいかい"},{"text":"です"}]}
	app._on_announcement_started(guide)
	app._on_announcement_finished({"interrupted":false})
	check(app.announcement_subtitle.visible and app.announcement_caption_remaining>=4.5,"A short voice ending retains its readable subtitle")
	var displayed_index: int = app.learning_index
	var displayed_clock: float = app.learning_clock
	for unused in range(4): app._process(.25)
	check(app.learning_index==displayed_index and is_equal_approx(app.learning_clock,displayed_clock),"Covered learning text cannot lose its dwell budget")
	app.state.paused = true
	var remaining: float = app.announcement_caption_remaining
	app._update_caption_time(6)
	check(app.announcement_caption_remaining==remaining,"Explicit pause preserves the held subtitle")
	app.state.paused = false
	app._update_caption_time(20)
	check(not app.announcement_subtitle.visible and app.active_word.visible,"Natural caption expiry restores the original learning sentence")
	await capture("marching-battle")
	app.progress.complete_map(current_id,{"correct":0})
	check(not app.progress.map_unlocked(str(app.maps[1].id)),"A completed first map still needs its Japanese exam")
	app._start_gate()
	await ready_phase()
	check(app.gate_active and int(app.unlock_gate.snapshot().count)==17,"The actual first-map exam covers fifteen words and two grammar points")
	app._on_announcement_started(guide)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.content_scale_size=dimensions
		root.size=dimensions
		app._layout()
		await settle()
		await question_geometry()
		await capture("unlock-question")
	app._stop_narration()
	var right: String = correct_choice(app.quiz_task,app.current_lesson)
	for option in app.quiz_task.choices:
		if str(option.id)!=right:
			app._answer_quiz(str(option.id))
			break
	await ready_phase()
	check(not app.unlock_gate.snapshot().passed and not app.progress.map_unlocked(str(app.maps[1].id)),"A real wrong UI answer ends the attempt without unlocking")
	app._continue_battle()
	await ready_phase()
	var economy: int = app.game.gold
	while app.gate_active and not bool(app.unlock_gate.snapshot().complete):
		app._answer_quiz(correct_choice(app.quiz_task,app.current_lesson))
		await ready_phase()
		if not bool(app.unlock_gate.snapshot().complete):
			app._continue_battle()
			await ready_phase()
	check(app.gate_saved and app.progress.map_assessed(current_id) and app.progress.map_unlocked(str(app.maps[1].id)),"The actual all-correct native UI stores and unlocks the next map")
	check(app.game.gold==economy,"Exam questions cannot manufacture combat rewards")
	await capture("unlock-complete")
	app._continue_battle()
	await settle()
	check(not app.gate_active and str(app.current_map.id)==str(app.maps[1].id) and app.modal_context=="briefing","Successful assessment opens the actual next-map briefing")
	var completed = progression_store()
	app.progress.data=completed.data.duplicate(true)
	app._select_tier(3)
	app._select_map(9)
	app._begin_battle()
	app.game._finish(true)
	await settle()
	check(app.current_story.battleKo=="오다와라 합전" and app.current_story.year==1590 and app.modal_body.find_child("UnificationEnding",true,false)!=null,"The actual advanced tenth-stage victory presents the 1590 unification ending")
	await capture("unification-ending")
	var report: Dictionary = {"checks":checks,"failures":failures,"packed":packed,"images":images,"firstExamCount":17,"exposedWords":15}
	var output = FileAccess.open("user://qa_new_flow_ui%s.json" % ("_packed" if packed else ""),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("NEW_FLOW_UI checks=%d failures=%d images=%d" % [checks,failures.size(),images.size()])
	app._stop_narration()
	app.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
