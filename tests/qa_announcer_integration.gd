extends SceneTree
## Actual Main/native UI and the female MP3 mixer. Shared-gate matrices have separate QA.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var snapshots: Array = []
var images: Array = []
var context: String = ""
var capture_enabled: bool = false
var observing: bool = false
var observed_frames: int = 0
var max_active_voices: int = 0
var capture_effect: AudioEffectCapture
var captured_rms: float = 0.0

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(context+" · "+note)
		if failures.size()<=30: push_error("ANNOUNCER_INTEGRATION "+context+" · "+note)

func observe() -> void:
	if not observing: return
	app._update_caption_time(app.get_process_delta_time())
	app._update_voice_mix()
	var active: int = int(app.voice_director.diagnostics().activeVoices)
	max_active_voices = maxi(max_active_voices,active)
	observed_frames += 1
	if active>1:
		check(false,"Actual Main playback has overlapping voice channels")
		observing = false

func settle() -> void:
	for frame in range(4): await process_frame

func delay(seconds: float) -> void:
	await create_timer(seconds,true,false,true).timeout

func press(button: Button) -> void:
	check(button!=null and not button.disabled,"Actual native UI action is available")
	if button==null or button.disabled: return
	await mouse(button.get_global_rect().get_center())

func mouse(point: Vector2) -> void:
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await settle()

func find_button(parent: Node, prefix: String) -> Button:
	for button in parent.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and not button.is_queued_for_deletion() and button.text.begins_with(prefix): return button
	return null

func wait_female(id: String, timeout: float = 4.5) -> void:
	var deadline: int = Time.get_ticks_msec()+int(timeout*1000)
	while str(app.battle_announcer.current_caption().get("id",""))!=id and Time.get_ticks_msec()<deadline: await process_frame
	check(str(app.battle_announcer.current_caption().get("id",""))==id and app.battle_announcer.is_speaking(),"Actual female recording starts "+id)

func wait_female_finished(timeout: float = 3.5) -> void:
	var deadline: int = Time.get_ticks_msec()+int(timeout*1000)
	while not app.battle_announcer.current.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(app.battle_announcer.current.is_empty(),"Actual female recording completes naturally")
	check(app.announcement_subtitle.visible and app.announcement_caption_remaining>0.0,"Short recordings retain their subtitle long enough to read")
	app._update_voice_mix()
	check(app.player.volume_db!=-27 and not app.battle_audio.voice_active,"Held text does not reserve the voice channel or keep combat audio ducked")
	deadline = Time.get_ticks_msec()+17000
	while app.announcement_subtitle.visible and Time.get_ticks_msec()<deadline: await process_frame
	check(not app.announcement_subtitle.visible,"The reading timer naturally restores the original learning text")

func wait_phase(phase: String) -> void:
	var deadline: int = Time.get_ticks_msec()+2500
	while app.learning_transition.phase!=phase and Time.get_ticks_msec()<deadline: await process_frame
	check(app.learning_transition.phase==phase,"Production learning reaches "+phase)

func record(note: String) -> void:
	snapshots.append({"case":context,"note":note,"female":app.battle_announcer.diagnostics(),"director":app.voice_director.diagnostics(),"subtitleRect":app.announcement_subtitle.get_global_rect(),"subtitleWord":app.announcement_subtitle.word,"subtitleVisible":app.announcement_subtitle.is_visible_in_tree(),"wordVisible":app.active_word.visible,"exampleVisible":app.example_label.visible,"reportAlpha":app.learning_field.report_text.modulate.a,"quizAlpha":app.quiz_ruby.modulate.a if is_instance_valid(app.quiz_ruby) else null,"state":app.game.snapshot(),"mode":app.progress.data.settings.battleMinutes,"voiceSetting":app.progress.data.settings.voice,"musicDb":app.player.volume_db,"effectsVoiceActive":app.battle_audio.voice_active})

func geometry() -> void:
	var caption: Control = app.announcement_subtitle
	var rect: Rect2 = caption.get_global_rect()
	check(caption.is_visible_in_tree() and root.get_visible_rect().encloses(rect),"Female guide fits the actual viewport")
	check(caption.mouse_filter==Control.MOUSE_FILTER_IGNORE and not caption is Panel,"Guide is transparent Ruby text and captures no drag/deployment input")
	check((not app.hud_bar.is_visible_in_tree() or not rect.intersects(app.hud_bar.get_global_rect())) and (not app.army_toolbar.is_visible_in_tree() or not rect.intersects(app.army_toolbar.get_global_rect())),"Female guide covers neither the visible HUD nor recruitment row")
	if not app._learning_screen_active():
		check(app.learning_panel.get_global_rect().encloses(rect),"Battle announcement stays inside the existing bottom learning area")
		check(not app.active_word.visible and not app.example_label.visible and app.learning_field.report_text.modulate.a==1,"Female delivery replaces the bottom word row while preserving the separate report")
		if app.hint_bar.is_visible_in_tree(): check(not rect.intersects(app.hint_bar.get_global_rect()),"Bottom guide preserves deployment hints")
		if app.army_panel.is_visible_in_tree(): check(not rect.intersects(app.army_panel.get_global_rect()),"Bottom guide preserves the selected-unit inspector")
	elif app.context_task_active:
		check(app.learning_field.report_text.modulate.a==1 and not rect.intersects(app.learning_field.report_text.get_global_rect()),"Context guide preserves the entire question in its separate header slot")
		check(not rect.intersects(app.learning_field.action_card.get_global_rect()),"Context guide preserves reward feedback and action controls")
		for card in app.learning_field.target_buttons: check(not rect.intersects(card.get_global_rect()),"Context guide covers no destination card")
	else:
		check(app.quiz_ruby.modulate.a==1 and not rect.intersects(app.quiz_ruby.get_global_rect()),"Ordinary quiz guide preserves the entire question in its separate header slot")
		check(not rect.intersects(app.modal_footer.get_global_rect()),"Ordinary guide preserves reward feedback and action controls")
		for card in app.quiz_choices: check(not rect.intersects(card.get_global_rect()),"Ordinary guide covers no answer card")
	for run in caption.get_text_layout().runs:
		check(Rect2(Vector2.ZERO,caption.size).grow(1).encloses(run.bounds),"Every female caption glyph fits without clipping")
		check(int(run.size)>=16 if run.role=="reading" else int(run.size)>=20,"Guide preserves 16px readings and at least 20px Japanese/Korean")
	check(caption.base_size==26 and caption.meaning_size==20 and str(caption.word.jp)==str(app.battle_announcer.current_caption().jp) and str(caption.word.ko)==str(app.battle_announcer.current_caption().ko),"Guide uses the exact recording with 26px Japanese and 20px Korean")
	check(app.player.volume_db==-27 and app.battle_audio.voice_active,"Actual female clip ducks BGM and combat reactions")

func capture(name: String) -> void:
	if not capture_enabled: return
	app.battle_announcer.set_paused(true)
	app.troops_3d._process(0)
	await settle()
	await RenderingServer.frame_post_draw
	var path: String = "user://female-%s-%dx%d.png" % [name,root.content_scale_size.x,root.content_scale_size.y]
	check(root.get_texture().get_image().save_png(path)==OK,"Actual GPU guide capture saves")
	images.append(ProjectSettings.globalize_path(path))
	app.battle_announcer.set_paused(false)

func begin() -> void:
	app._select_map(0)
	await settle()
	await press(app.modal_footer.get_child(0))
	app.game.set_process(false)
	var deadline: int = Time.get_ticks_msec()+1000
	while app.battle_narrator.current_caption().get("id","")!="march" and Time.get_ticks_msec()<deadline: await process_frame
	check(app.battle_narrator.current_caption().get("id","")=="march" and app.battle_announcer.current.is_empty(),"Actual sortie starts male narration before its queued female report notification")
	await wait_female("message_received")

func field_checks() -> void:
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		context = "bottom guide "+str(dimensions)
		root.size = dimensions
		root.content_scale_size = dimensions
		await begin()
		if dimensions.x==1280:
			# The other voice's sortie filled this bus with silence before the handoff.
			capture_effect.clear_buffer()
			await delay(.45)
			var buffer: PackedVector2Array = capture_effect.get_buffer(capture_effect.get_frames_available())
			var energy: float = 0.0
			for sample in buffer: energy += sample.length_squared()*.5
			captured_rms = sqrt(energy/maxi(1,buffer.size()))
			check(buffer.size()>1000 and captured_rms>.003,"Actual Main female MP3 player produces recorded PCM in the mixer")
		geometry()
		check(str(app.learning_field.report_text.word.jp)!=str(app.announcement_subtitle.word.jp) and app.learning_field.mission.report.jp==app.learning_field.report_text.word.jp,"Fixed report-arrival clip never substitutes for the authored stage report")
		await capture("report")
		record("report-arrival")
		app.game._spawn_enemy("light")
		app.game._process(.1)
		app._on_state(app.game.snapshot())
		var enemy_before: Dictionary = app.game.enemies[0].duplicate(true)
		await press(app.pause_button)
		var clock: float = app.battle_announcer._clock
		app.game._process(.2)
		await delay(.09)
		check(app.battle_announcer.paused and app.battle_announcer._clock==clock and app.announcement_subtitle.visible and app.game.enemies[0]==enemy_before,"Native pause freezes the female phrase and the current enemy action/position")
		await press(app.pause_button)
		await wait_female_finished()
		check(app.active_word.visible and app.example_label.visible and app.learning_field.report_text.modulate.a==1 and app.learning_field.report_heading.modulate.a==1,"Natural female completion restores the same word/example/report reading")
		check(app.player.volume_db==-20 and not app.battle_audio.voice_active,"Female completion restores battle BGM and combat reactions")

func tts_and_master_checks() -> void:
	context = "automatic / manual / master voice"
	await begin()
	app.japanese_voice = "qa-silent-dispatch"
	var caption: String = str(app.announcement_subtitle.word.jp)
	await press(app.learning_panel.get_node("NextWordButton"))
	check(app.battle_announcer.is_speaking() and str(app.announcement_subtitle.word.jp)==caption and not app.voice_director._pending_learning.is_empty(),"Automatic next-word reading waits for the actual female phrase without replacing its caption")
	await press(app.learning_panel.get_node("ListenButton"))
	check(app.voice_director.is_tts_active() and not app.battle_announcer.is_speaking() and not app.announcement_subtitle.visible and app.active_word.visible and app.learning_field.report_text.modulate.a==1,"Native manual listening interrupts recording and restores learning text before protected TTS dispatch")
	app.japanese_voice = ""
	app._update_voice_mix()
	check(app.voice_director.is_tts_active() and app.player.volume_db==-27,"Main polling retains the reserved TTS slot when the OS has not started yet")
	app.voice_director._on_tts_ended(app.voice_director._tts_id)
	app._stop_narration()
	app._announce("level_up","master-off-fixture")
	await wait_female("level_up")
	app._show_home()
	app.front_end.view = "settings"
	app.front_end._rebuild()
	await settle()
	check(app.front_end.male_voice_available and app.front_end.female_voice_available and app.front_end.voice_available,"Actual settings distinguish both offline recorded voices from OS reading ability")
	var minutes: int = app.battle_minutes
	await press(find_button(app.front_end,"일본어 음성"))
	check(not app.battle_narrator.enabled and not app.battle_announcer.enabled and not app.voice_director.is_voice_active() and app.battle_announcer.queue.is_empty(),"Native master-off stops both recorded channels and protected/pending TTS")
	app.japanese_voice = "qa-silent-dispatch"
	var requests: int = app.voice_director.tts_requests
	app._speak_current()
	app._speak("山",true)
	check(app.voice_director.tts_requests==requests and not app.voice_director.is_voice_active(),"Master-off also blocks manual and automatic learning speech")
	app.japanese_voice = ""
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(app.progress.save_path))
	check(not bool(saved.settings.voice) and int(saved.settings.battleMinutes)==minutes,"Voice-off saves without changing the selected battle mode")
	await press(find_button(app.front_end,"일본어 음성"))
	check(app.battle_narrator.enabled and app.battle_announcer.enabled and app.battle_minutes==minutes,"Voice-on re-enables both original recordings and preserves battle mode")

func open_wave() -> void:
	app.game.elapsed = float(app.game._timed_wave().endSeconds)
	app.game._complete_wave()
	await wait_phase("choice")
	await wait_female("answer_select")
	geometry()
	await capture("context-ready" if app.context_task_active else "ordinary-ready")
	await wait_female_finished()

func learning_checks() -> void:
	context = "context hint / correct / skip cleanup"
	await open_wave()
	check(app.context_task_active,"Production first wave issues the actual destination task")
	await press(app.learning_field.hint_button)
	await wait_female("hint")
	geometry()
	await wait_female_finished()
	var mission: Dictionary = app.quiz_task.mission
	var correct_index: int = 0
	for index in range(mission.targets.size()):
		if str(mission.targets[index].id)==str(mission.answerId): correct_index=index
	var gold: int = app.game.gold
	await press(app.learning_field.target_buttons[correct_index])
	await wait_female("correct")
	geometry()
	await capture("context-correct")
	var plays: int = int(app.battle_announcer.play_counts.get("correct",0))
	app._answer_context(str(mission.answerId))
	check(app.game.gold==gold+25 and int(app.battle_announcer.play_counts.get("correct",0))==plays and app.battle_announcer.queue.is_empty(),"Accepted hinted answer retains +25 and duplicate callbacks cannot enqueue another answer voice/reward")
	record("context-correct")
	await wait_phase("result")
	await press(app.learning_field.continue_button)
	await wait_phase("idle")
	app.game.set_process(false)
	check(not app.announcement_subtitle.visible and app.active_word.visible and app.example_label.visible and app.learning_field.report_text.modulate.a==1,"Animated return stops old answer audio and restores the original bottom reading")
	context = "ordinary incorrect / native skip"
	await open_wave()
	check(not app.context_task_active and app.modal_context=="quiz","Production second wave issues an ordinary question")
	var wrong_index: int = 0
	for index in range(app.quiz_task.choices.size()):
		if str(app.quiz_task.choices[index].id)!=str(app.quiz_task.answerId): wrong_index=index;break
	gold = app.game.gold
	await press(app.quiz_choices[wrong_index])
	await wait_female("incorrect")
	geometry()
	await capture("ordinary-incorrect")
	check(app.game.gold==gold and not app.quiz_outcome_correct,"Recorded incorrect feedback adds no supply reward")
	record("ordinary-incorrect")
	await wait_phase("result")
	await press(app.quiz_continue_button)
	await wait_phase("idle")
	app.game.set_process(false)
	app._stop_narration()
	check(not app.announcement_subtitle.visible and app.active_word.visible and app.example_label.visible,"Ordinary return removes the old female caption without a stale callback")

func navigation_and_result_checks() -> void:
	context = "navigation / result / shutdown"
	app._announce("level_up","navigation-fixture")
	await wait_female("level_up")
	app._show_catalog()
	check(app.battle_announcer.current.is_empty() and app.battle_announcer.queue.is_empty() and not app.announcement_subtitle.visible and not app.voice_director.is_voice_active(),"Stage navigation clears active/waiting female and learning speech")
	app._resume_from_navigation()
	# Respect level_up's five-second recipe cooldown after the navigation fixture.
	app._announce("next_question","result-fixture")
	await wait_female("next_question")
	app.game._finish(false)
	var deadline: int = Time.get_ticks_msec()+1000
	while app.battle_narrator.current_caption().get("id","")!="defeat" and Time.get_ticks_msec()<deadline: await process_frame
	check(app.battle_announcer.current.is_empty() and app.battle_announcer.queue.is_empty() and not app.announcement_subtitle.visible and app.battle_narrator.current_caption().get("id","")=="defeat","Final result clears female guidance and keeps the existing male result narration")
	record("result")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/announcer-integration/"):
		push_error("Female integration QA refuses the player's profile")
		quit(2)
		return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2);return
	var fixture = Store.new()
	fixture.save_path = "user://announcer-integration-%d.json" % Time.get_ticks_usec()
	fixture.data.settings = {"music":false,"effects":false,"voice":true,"battleMinutes":10}
	check(fixture.write_save(),"Isolated actual Main voice/mode fixture saves")
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = fixture.save_path
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	if not capture_enabled:
		app.troops_3d.hide()
		app.troops_3d._process(0)
	app.troops_3d.set_process(false)
	app.japanese_voice = ""
	var wallet: int = int(app.progress.data.army.currency)
	check(app.battle_announcer.is_ready and app.battle_announcer.streams.size()==8 and app.voice_director.voices.size()==2,"Actual Main caches both male and female original recordings under one director")
	capture_effect = AudioEffectCapture.new()
	capture_effect.buffer_length = 1.0
	AudioServer.add_bus_effect(app.battle_announcer.diagnostics().busIndex,capture_effect)
	process_frame.connect(observe)
	observing = true
	await field_checks()
	await tts_and_master_checks()
	await learning_checks()
	await navigation_and_result_checks()
	check(max_active_voices<=1 and observed_frames>100,"Every observed actual Main frame has at most one active voice")
	check(int(app.progress.data.army.currency)==wallet and app.battle_minutes==10,"Voice feedback and real learning preserve permanent funds and selected mode")
	observing = false
	app._quit_game()
	check(not app.battle_announcer.is_ready and not app.announcement_subtitle.visible and app.voice_director.diagnostics().shutdown,"Actual close shuts down female recordings, captions, pending TTS and its director")
	var report: Dictionary = {"checks":checks,"failures":failures,"productionSnapshots":snapshots,"images":images,"capturedRms":captured_rms,"observedFrames":observed_frames,"maxActiveVoices":max_active_voices,"driver":DisplayServer.get_name(),"profile":profile,"scope":"Actual Main/native UI, original female MP3 mixer, three bottom caption geometries, male sortie/female report handoff, exact fixed phrases versus authored report, paused enemy/current audio action, automatic deferred reading versus manual protected TTS callbacks, master save/on/off/manual-off, real deployment, timed wave-boundary context hint/correct and ordinary incorrect with duplicate reward guards, return/navigation/result/shutdown. OS Japanese speech callbacks use a declared silent fixture, not audible TTS or artistic audition; shared-gate timing matrices have separate component QA."}
	var path: String = "user://qa_announcer_integration_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_announcer_integration_headless.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output==null: quit(2);return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("ANNOUNCER_INTEGRATION ",checks," checks / ",failures.size()," failures / ",snapshots.size()," snapshots; mixer RMS=",captured_rms," maxVoices=",max_active_voices,"; report=",ProjectSettings.globalize_path(path))
	if not failures.is_empty(): quit(1)
