extends SceneTree
## Actual Main, real UI callbacks and the narrator's real WAV/mixer lifecycle.
## Spawn/objective fixtures test integration without replaying combat/balance matrices.
const Store = preload("res://native/progress.gd")
const Gate = preload("res://native/learning_gate.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var snapshots: Array = []
var started: Array = []
var ended: Array = []
var images: Array = []
var capture_enabled: bool = false
var context: String = ""
var capture_effect: AudioEffectCapture
var captured_rms: float = 0.0
var pointer_samples: Array = []

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(context+" · "+note)
		if failures.size()<=30:
			push_error("NARRATOR_INTEGRATION "+context+" · "+note)

func settle() -> void:
	for frame in range(4): await process_frame

func delay(seconds: float) -> void:
	await create_timer(seconds,true,false,true).timeout

func tick_captions() -> void:
	if is_instance_valid(app) and not app.closing:
		app._update_caption_time(app.get_process_delta_time())
		app._update_voice_mix()

func motion(point: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	# The native window can supply another OS motion during the following frames.
	# Observe delivery of this exact injected event before any later pointer event.
	Input.flush_buffered_events()
	trace_pointer("synthetic-motion-delivered",point)
	var expected: Vector2 = (app.game.get_canvas_transform().affine_inverse()*point-app.game.field_rect.position)/app.game.field_rect.size
	check(app.game.placement_cursor_visible and app.game.placement_cursor.distance_to(expected)<.00001,"Native deployment motion reaches the production battlefield coordinates through the transparent caption")
	await settle()
	trace_pointer("after-four-native-frames",point)

func trace_pointer(note: String, requested: Vector2 = Vector2.ZERO) -> void:
	var sample: Dictionary = {"case":context,"note":note,"wallUsec":Time.get_ticks_usec(),"frame":Engine.get_process_frames(),"requested":requested,"inputEnabled":app.game.input_enabled,"pending":app.game.pending.duplicate(true),"cursorVisible":app.game.placement_cursor_visible,"cursor":app.game.placement_cursor,"viewportPointer":root.get_mouse_position(),"windowSize":root.size,"contentScaleSize":root.content_scale_size,"canvasTransform":app.game.get_canvas_transform(),"fieldRect":app.game.field_rect,"captionRect":app.narration_subtitle.get_global_rect(),"captionVisible":app.narration_subtitle.visible,"captionMouseFilter":app.narration_subtitle.mouse_filter,"speaking":app.battle_narrator.is_speaking()}
	if DisplayServer.get_name()!="headless":
		sample["osPointer"] = DisplayServer.mouse_get_position()
	pointer_samples.append(sample)

func mouse(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	await settle()

func button_with_text(parent: Node, prefix: String) -> Button:
	for child in parent.find_children("*","Button",true,false):
		if child.is_visible_in_tree() and child.text.begins_with(prefix): return child
	return null

func press(button: Button) -> void:
	check(button!=null and not button.disabled,"Actual UI action is available")
	if button!=null and not button.disabled:
		await mouse(button.get_global_rect().get_center())

func on_started(caption: Dictionary) -> void:
	started.append({"clip":caption.id,"event":caption.event,"context":caption.context,"at":Time.get_ticks_usec()})

func on_finished(caption: Dictionary) -> void:
	ended.append({"clip":caption.id,"interrupted":caption.get("interrupted",false),"at":Time.get_ticks_usec()})

func record(note: String) -> void:
	snapshots.append({"case":context,"note":note,"narrator":app.battle_narrator.diagnostics(),"subtitleVisible":app.narration_subtitle.is_visible_in_tree(),"subtitleRect":app.narration_subtitle.get_global_rect(),"subtitleWord":app.narration_subtitle.word,"musicDb":app.player.volume_db,"effectsVoiceActive":app.battle_audio.voice_active,"ttsVoice":app.japanese_voice,"battleId":app.narration_battle_id,"state":app.game.snapshot()})

func wait_clip(id: String, timeout: float = .8) -> void:
	var deadline: int = Time.get_ticks_msec()+int(timeout*1000)
	while str(app.battle_narrator.current_caption().get("id",""))!=id and Time.get_ticks_msec()<deadline:
		await process_frame
	check(str(app.battle_narrator.current_caption().get("id",""))==id and app.battle_narrator.is_speaking(),"Actual player starts "+id)

func wait_silent(timeout: float = 3.5) -> void:
	var deadline: int = Time.get_ticks_msec()+int(timeout*1000)
	while not app.battle_narrator.current.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
	check(app.battle_narrator.current.is_empty(),"Actual male recording completes naturally")
	check(app.narration_subtitle.visible and app.narration_caption_remaining>0.0,"Short male recordings retain the caption for its reading time")
	deadline = Time.get_ticks_msec()+17000
	while app.narration_subtitle.visible and Time.get_ticks_msec()<deadline:
		await process_frame
	check(not app.narration_subtitle.visible,"The male reading timer naturally expires its held subtitle")

func geometry() -> void:
	var caption: Control = app.narration_subtitle
	var rect: Rect2 = caption.get_global_rect()
	check(caption.is_visible_in_tree() and app.game.field_rect.grow(1).encloses(rect),"Caption stays within the existing battlefield")
	check(caption.mouse_filter==Control.MOUSE_FILTER_IGNORE and not caption is Panel,"Caption is transparent text and accepts no deployment/drag input")
	check(not rect.intersects(app.hud_bar.get_global_rect()) and not rect.intersects(app.army_toolbar.get_global_rect()) and not rect.intersects(app.learning_panel.get_global_rect()),"Caption covers neither HUD nor learning subtitles nor recruitment row")
	if app.learning_field.report_card.is_visible_in_tree():
		check(not rect.intersects(app.learning_field.report_card.get_global_rect()),"Recorded caption does not cover the passive learning report")
	if app.army_panel.is_visible_in_tree():
		check(not rect.intersects(app.army_panel.get_global_rect()),"Recorded caption does not cover the selected-unit inspector")
	if app.modal_context=="result":
		check(not rect.intersects(app.modal_card.get_global_rect()),"Result caption stays beside the result card and its controls")
	var layout: Dictionary = caption.get_text_layout()
	for run in layout.runs:
		check(Rect2(Vector2.ZERO,caption.size).grow(1).encloses(run.bounds),"Every subtitle glyph fits without clipping")
		check(int(run.size)>=16 if run.role=="reading" else int(run.size)>=20,"Japanese readings remain at least 16px and main/translation text at least 20px")
	check(caption.meaning_visible and str(caption.word.get("ko",""))==str(app.battle_narrator.current_caption().get("ko","")),"Korean translation matches the actual recording")

func capture(name: String) -> void:
	if not capture_enabled: return
	app.battle_narrator.set_paused(true)
	app.troops_3d._process(0)
	await settle()
	await RenderingServer.frame_post_draw
	var path: String = "user://narrator-%s-%dx%d.png" % [name,root.content_scale_size.x,root.content_scale_size.y]
	check(root.get_texture().get_image().save_png(path)==OK,"GPU caption capture saves")
	images.append(ProjectSettings.globalize_path(path))
	app.battle_narrator.set_paused(false)

func begin(stage_index: int = 0) -> void:
	app._select_map(stage_index)
	await settle()
	await press(app.modal_footer.get_child(0))
	app.game.set_process(false)
	await wait_clip("march")
	check(app.battle_narrator.player.stream is AudioStreamWAV and app.player.volume_db==-27 and app.battle_audio.voice_active,"Recorded player ducks BGM and combat reactions even without an OS Japanese voice")
	check(app.battle_narrator.player.max_polyphony==1,"All maps share one narrator player")

func settings_checks() -> void:
	context = "settings without OS TTS"
	app._show_home()
	app.front_end.view = "settings"
	app.front_end._rebuild()
	await settle()
	check(app.japanese_voice.is_empty() and app.front_end.voice_available and app.front_end.narration_available,"Recorded voice makes the real settings available without OS TTS")
	var wallet: int = int(app.progress.data.army.currency)
	await press(button_with_text(app.front_end,"일본어 음성"))
	check(not app.progress.data.settings.voice and not app.battle_narrator.enabled,"Native settings click disables the master voice flag and recording player")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(app.progress.save_path))
	check(not bool(saved.settings.voice),"Master voice-off click persists in the isolated save")
	await press(button_with_text(app.front_end,"일본어 음성"))
	check(app.progress.data.settings.voice and app.battle_narrator.enabled and int(app.progress.data.army.currency)==wallet,"Voice-on click works without TTS and preserves permanent funding")

func common_map_and_caption_checks() -> void:
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		context = "caption "+str(dimensions)
		root.size = dimensions
		root.content_scale_size = dimensions
		await begin()
		geometry()
		await capture("battle-start")
		record("start")
		app._stop_narration()
		app.game._spawn_enemy("heavy")
		app._on_state(app.game.snapshot())
		await wait_clip("strong_enemy")
		geometry()
		await capture("strong-enemy")
		var count: int = int(app.battle_narrator.play_counts.get("strong_enemy",0))
		app.game._spawn_enemy("commander")
		for iteration in range(20): app._on_state(app.game.snapshot())
		check(int(app.battle_narrator.play_counts.get("strong_enemy",0))==count and app.battle_narrator.queue.is_empty(),"First strong-enemy report is not repeated for later heavy/commander snapshots")
		record("first-strong")
		app._stop_narration()
	# Every map changes only data; verify the one Main/narrator instance and route identity.
	context = "40 common maps"
	var narrator_id: int = app.battle_narrator.get_instance_id()
	var stream_id: int = app.battle_narrator.streams.march.get_instance_id()
	for map_index in range(app.maps.size()):
		var map: Dictionary = app.maps[map_index]
		app.current_tier = int(map.tierIndex) if map.has("tierIndex") else ["basic","beginner","intermediate","advanced"].find(str(map.tier))
		app._select_map(map_index%10)
		check(app.battle_narrator.get_instance_id()==narrator_id and app.battle_narrator.streams.march.get_instance_id()==stream_id,"Map "+str(map.id)+" reuses the common narrator and cached recording")
		check(app.battle_narrator.current.is_empty() and app.battle_narrator.queue.is_empty() and app.narration_battle_id.is_empty() and not app.narration_subtitle.visible,"Map "+str(map.id)+" resets narration without starting a sortie prematurely")
	app.current_tier = 0

func pause_danger_and_input_checks() -> void:
	context = "pause / danger / native input"
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	await begin()
	var clock: float = app.battle_narrator._clock
	await press(app.pause_button)
	check(app.battle_narrator.paused and app.battle_narrator.player.stream_paused and app.narration_subtitle.visible,"Explicit battle pause freezes the current phrase and its caption")
	clock = app.battle_narrator._clock
	await delay(.09)
	check(app.battle_narrator._clock==clock,"Explicit pause freezes narration queue age")
	await press(app.pause_button)
	check(not app.battle_narrator.paused and app.battle_narrator.is_speaking(),"Actual resume restores the same recorded phrase")
	await press(app.army_grid.get_node("DeployCard_archer"))
	trace_pointer("after-native-archer-click")
	check(str(app.game.pending.get("type",""))=="archer" and app.game.input_enabled,"Native class click creates an actual unpaid archer preview before the caption-pointer probe")
	var position: Vector2 = app.narration_subtitle.get_global_rect().get_center()
	await motion(position)
	await mouse(position,MOUSE_BUTTON_RIGHT)
	trace_pointer("after-native-cancel",position)
	check(app.game.pending.is_empty() and app.battle_narrator.is_speaking(),"Native right-click under the caption cancels placement without disturbing narration")
	app._stop_narration()
	var objective: Dictionary = app.game.objectives[0]
	objective.hp = maxi(1,int(objective.maxHp*.25))
	app._on_state(app.game.snapshot())
	await wait_clip("danger")
	geometry()
	record("danger")
	var count: int = int(app.battle_narrator.play_counts.get("danger",0))
	for iteration in range(20): app._on_state(app.game.snapshot())
	check(int(app.battle_narrator.play_counts.get("danger",0))==count and app.battle_narrator.queue.is_empty(),"Low gate HP announces danger once per sortie")
	await wait_silent()
	check(app.player.volume_db==-20 and not app.battle_audio.voice_active,"Natural recorded completion restores the same battle BGM level and effects")

func tts_quiz_and_navigation_checks() -> void:
	context = "TTS / learning / navigation"
	await begin()
	var interrupted: int = app.battle_narrator.tts_interrupted
	app.japanese_voice = "qa-silent-dispatch"
	app._speak("山")
	check(app.battle_narrator.voice_active and not app.battle_narrator.is_speaking() and not app.narration_subtitle.visible and app.player.volume_db==-27,"Main _speak synchronously interrupts recording before dispatching TTS")
	check(app.battle_narrator.tts_interrupted==interrupted+1,"TTS precedence stops the actual active phrase exactly once")
	app.japanese_voice = ""
	app._update_voice_mix()
	check(app.voice_director.is_tts_active() and app.battle_narrator.voice_active and app.player.volume_db==-27,"Main preserves the director's reserved TTS slot before a delayed OS start")
	app.voice_director._on_tts_ended(app.voice_director._tts_id)
	app._update_voice_mix()
	check(not app.battle_narrator.voice_active and app.player.volume_db==-20,"The matching director completion callback releases voice priority and restores BGM")
	check(app.voice_director._scheduled_tts.is_empty(),"Canceled pre-dispatch learning cannot leave a delayed utterance behind")
	app.battle_narrator.reset_battle()
	app._narrate("strong_enemy","quiz-interruption-fixture")
	await wait_clip("strong_enemy")
	app.game.between_waves = true
	app.game.wave = 1
	app._on_state(app.game.snapshot())
	check(not app.battle_narrator.paused and app.battle_narrator.is_speaking(),"Between-wave state alone never pauses recorded playback")
	app._show_quiz()
	check(not app.battle_narrator.is_speaking() and app.battle_narrator.queue.is_empty() and not app.narration_subtitle.visible,"Quiz entry immediately clears recording and caption for the learning voice")
	var deadline: int = Time.get_ticks_msec()+2000
	while app.learning_transition.is_busy() and Time.get_ticks_msec()<deadline: await process_frame
	check(app.context_task_active and app.learning_field.listen_button.disabled,"Recorded voice availability never enables a missing OS learning-read voice")
	await press(app.learning_field.continue_button)
	deadline = Time.get_ticks_msec()+2000
	while app.learning_transition.is_busy() and Time.get_ticks_msec()<deadline: await process_frame
	app.game.set_process(false)
	app.battle_narrator.reset_battle()
	app._narrate("danger","menu-fixture")
	await wait_clip("danger")
	await press(app.battle_menu_button)
	check(app.modal_context=="pause" and not app.battle_narrator.is_speaking() and not app.narration_subtitle.visible,"Native battle-menu click clears speech and its subtitle")
	await press(button_with_text(app.modal_body,"音声"))
	check(not app.progress.data.settings.voice and not app.battle_narrator.enabled,"Pause-menu master voice control also stops recordings")
	await press(button_with_text(app.modal_body,"音声"))
	await press(button_with_text(app.modal_body,"続行"))
	app.battle_narrator.reset_battle()
	app._narrate("strong_enemy","catalog-fixture")
	await wait_clip("strong_enemy")
	app._show_catalog()
	check(app.front_end.visible and app.battle_narrator.current.is_empty() and app.battle_narrator.queue.is_empty() and not app.narration_subtitle.visible,"Stage navigation discards both active and queued recorded lines")
	record("catalog-stop")

func result_checks() -> void:
	for won in [true,false]:
		context = "terminal "+str(won)
		await begin()
		var identity: String = app.narration_battle_id
		app.game._finish(won)
		await wait_clip("victory" if won else "defeat")
		check(app.modal_context=="result" and not app.battle_narrator.paused,"Final result plays despite the finished combat state")
		geometry()
		await capture("victory" if won else "defeat")
		var count: int = app.battle_narrator.played
		var wallet: int = int(app.progress.data.army.currency)
		app._on_battle_finished(app.game.snapshot())
		app._on_battle_finished({"victory":not won})
		check(app.battle_narrator.played==count and int(app.progress.data.army.currency)==wallet and app.narration_battle_id==identity,"Repeated result/reopened callbacks cannot repeat narration or campaign rewards")
		geometry()
		record("result")
		await wait_silent()
		check(app.player.volume_db==-16,"Natural result completion restores the existing result BGM level")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/narrator-integration/"):
		push_error("Narrator integration refuses the player's profile")
		quit(2)
		return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2);return
	var fixture = Store.new()
	fixture.save_path = "user://narrator-integration-%d.json" % Time.get_ticks_usec()
	fixture.data.settings = {"music":false,"voice":true,"effects":false}
	# Voice reset QA visits every stage using an isolated completed-campaign fixture.
	# Actual victory/exam admission and persistence are verified in qa_new_flow_ui.
	fixture.data.learning.assessments = {}
	for stage_id in fixture.stage_lessons:
		var lesson: Dictionary = fixture.stage_lessons[stage_id]
		var count: int = lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		fixture.data.maps[stage_id] = {"wins":1}
		fixture.data.learning.assessments[stage_id] = {"passed":true,"count":count,"correctCount":count,"scopeHash":Gate.scope_hash(lesson),"attemptId":"voice-fixture","passedAt":1}
	check(fixture.write_save(),"Isolated narrator integration fixture saves")
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = fixture.save_path
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	process_frame.connect(tick_captions)
	if not capture_enabled:
		app.troops_3d.hide()
		app.troops_3d._process(0)
	app.troops_3d.set_process(false)
	app.japanese_voice = ""
	app.front_end.reading_voice_available = false
	app.player.stop()
	app.battle_narrator.clip_started.connect(on_started)
	app.battle_narrator.clip_finished.connect(on_finished)
	check(app.battle_narrator.is_ready and app.battle_narrator.streams.size()==14,"Actual Main loads the offline recorded narrator without requiring OS TTS")
	capture_effect = AudioEffectCapture.new()
	capture_effect.buffer_length = 1.0
	AudioServer.add_bus_effect(app.battle_narrator.diagnostics().busIndex,capture_effect)
	await settings_checks()
	await begin()
	await delay(.28)
	var buffer: PackedVector2Array = capture_effect.get_buffer(capture_effect.get_frames_available())
	var energy: float = 0.0
	for frame in buffer: energy += frame.length_squared()*.5
	captured_rms = sqrt(energy/maxi(1,buffer.size()))
	check(buffer.size()>1000 and captured_rms>.002,"Actual Main narrator mixer produces non-silent recorded PCM")
	app._stop_narration()
	await common_map_and_caption_checks()
	await pause_danger_and_input_checks()
	await tts_quiz_and_navigation_checks()
	await result_checks()
	context = "close"
	app._quit_game()
	check(app.closing and not app.battle_narrator.is_ready and not app.battle_narrator.is_speaking() and not app.narration_subtitle.visible and app.player.stream==null,"Actual application-close path shuts down narration, subtitles and BGM before its mixer drain")
	var report: Dictionary = {"checks":checks,"failures":failures,"productionSnapshots":snapshots,"pointerDelivery":pointer_samples,"started":started,"finished":ended,"images":images,"capturedRms":captured_rms,"profile":profile,"driver":DisplayServer.get_name(),"scope":"Actual Main callbacks/native Godot UI input, master voice flag without OS TTS, real WAV player/mixer/lifecycle, 40-map narrator/stream reuse/reset, three caption geometries, first heavy/commander, low objective HP, explicit pause versus between-waves, quiz/navigation/terminal/close cleanup and identical reward guard. Native archer preview plus synchronously flushed pointer coordinates are asserted; subsequent native-window pointer events are traced separately. Silent TTS dispatch verifies synchronous Main precedence, not audible OS TTS or artistic audition."}
	var path: String = "user://qa_narrator_integration_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_narrator_integration_headless.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output==null: quit(2);return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("NARRATOR_INTEGRATION ",checks," checks / ",failures.size()," failures / ",snapshots.size()," snapshots; real mixer RMS=",captured_rms,"; report=",ProjectSettings.globalize_path(path))
	if not failures.is_empty(): quit(1)
	# The actual Main close coroutine calls SceneTree.quit after its .5s mixer drain.
