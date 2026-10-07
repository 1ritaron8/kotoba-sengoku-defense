extends SceneTree
## One installed-content stress fixture. Real session issuance and Godot input;
## no campaign unlock or OS-native input claim.
var app: Node
var checks:=0
var failures: Array[String]=[]
var images: Array=[]

func _initialize() -> void: call_deferred("run")

func check(value: bool,note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		push_error("LONG_SENTENCE_UI "+note)

func settle() -> void:
	for frame in range(4): await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await settle()
	await RenderingServer.frame_post_draw
	var path: String="C:/JP_DF/dist/premium-sentence-long-%s-1280x800.png"%name
	check(root.get_texture().get_image().save_png(path)==OK,"Actual installed GPU stress image saves")
	images.append(path)

func press(button: Button) -> void:
	check(button!=null and not button.disabled,"Actual fixture control is available")
	if button!=null and not button.disabled: button.pressed.emit()
	await settle()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/premium-ui/packed-long"):
		quit(2);return
	root.size=Vector2i(1280,800)
	root.content_scale_size=Vector2i(1280,800)
	var empty_root: String="C:/JP_DF/tools/pack-learning-verifier-empty/"
	var resource_root: String=ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	check(resource_root.is_empty() or resource_root==empty_root.to_lower(),"Pack uses a virtual or empty-verifier resource root, with no loose project root")
	check(DirAccess.open(empty_root).get_files().is_empty(),"Verifier cwd has no loose resource files")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://long-ui-%d.json"%Time.get_ticks_msec()
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.progress.data.settings={"music":false,"voice":false,"effects":false}
	app.battle_audio.set_enabled(false)
	app.player.stop()
	app.player.stream=null
	var selected_word: Dictionary={}
	var selected_tier:=0
	var selected_lesson:=0
	var selected_key: String=""
	var longest:=0
	for tier in range(4):
		var lessons: Array=app.curriculum[app.TIER_IDS[tier]]
		for index in range(lessons.size()):
			for word in lessons[index].newWords:
				for key in ["example","transferExample"]:
					var count: int=str(word[key].ko).length()
					if count>longest:
						longest=count;selected_word=word;selected_tier=tier;selected_lesson=index;selected_key=key
	check(longest>=31,"Installed curriculum supplies its real longest Korean sentence")
	app._select_tier(selected_tier)
	app._select_map(selected_lesson)
	app._begin_battle()
	app.game.set_process(false)
	for index in range(app.learning_words.size()):
		if str(app.learning_words[app.learning_index].id)==str(selected_word.id): break
		app._advance_word()
	check(str(app.active_word.word.id)==str(selected_word.id),"The target vocabulary was actually displayed before issuing its sentence")
	var found:=false
	for turn in range(8):
		# A one-word exposure subset controls this visual stress fixture; all
		# answer choices and sentence contexts still come from the real session.
		app.seen_this_run=[str(selected_word.id)]
		app.game.between_waves=true
		app.game.wave=2
		app._on_state(app.game.snapshot())
		app._show_quiz()
		await settle()
		if str(app.quiz_task.get("kind",""))=="sentence" and str(app.quiz_task.item.ko)==str(selected_word[selected_key].ko):
			found=true;break
		await press(app.learning_field.continue_button if app.context_task_active else app.quiz_continue_button)
	check(found,"Real LearningSession issues the authored longest sentence without replacing its answer key")
	check(app.quiz_choices.size()==4 and app.quiz_grid.columns==4,"Longest sentence has four independent cards")
	check(not app.modal_scroll.get_v_scroll_bar().is_visible_in_tree(),"Longest sentence and four cards fit without scrolling")
	for button in app.quiz_choices:
		check(app.modal_scroll.get_global_rect().grow(1).encloses(button.get_global_rect()),"Longest answer card fits the actual screen")
		var text=TextParagraph.new()
		var style: StyleBox=button.get_theme_stylebox("normal")
		text.add_string(button.text,button.get_theme_font("font"),button.get_theme_font_size("font_size"))
		text.width=button.size.x-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT)
		var available: float=button.size.y-style.get_content_margin(SIDE_TOP)-style.get_content_margin(SIDE_BOTTOM)
		check(text.get_size().y<=available,"Actual shaped Korean text fits inside its card")
	await capture("choice")
	await press(app.quiz_hint_button)
	check(app.quiz_hinted and app.quiz_ruby.meaning_visible,"Longest whole-sentence hint displays through the actual button")
	var before: int=app.game.gold
	var answer_index: int=-1
	for index in range(app.quiz_task.choices.size()):
		if str(app.quiz_task.choices[index].id)==str(app.quiz_task.answerId): answer_index=index
	check(answer_index>=0,"An actual card contains the issued correct sentence")
	var point: Vector2=app.quiz_choices[answer_index].get_global_rect().get_center()
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.position=point;event.global_position=point
		Input.parse_input_event(event)
	await settle()
	check(app.quiz_resolved and app.game.gold==before+25,"Actual installed long-card click grants exactly the hinted reward")
	await capture("result")
	await press(app.quiz_continue_button)
	check(app.modal==null and app.field_clip.visible and app.army_toolbar.visible,"Long-sentence fixture returns to the actual battlefield")
	var report={"checks":checks,"failures":failures,"images":images,"wordId":selected_word.id,"sentenceKey":selected_key,"koreanCharacters":longest,"japaneseCharacters":str(selected_word[selected_key].jp).length(),"driver":DisplayServer.get_name(),"resourceRoot":ProjectSettings.globalize_path("res://"),"profile":profile,"scope":"Actual installed content in an isolated late-stage visual fixture with one-word exposure subset, real session issuance and Godot Input.parse_input_event card selection. No unlock/OS-native/TTS-listening claim."}
	var file=FileAccess.open("user://qa_premium_long_sentence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	app.battle_audio.shutdown()
	await create_timer(.5).timeout
	app.queue_free()
	await settle()
	print("LONG_SENTENCE_UI_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
