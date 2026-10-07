extends SceneTree
## Observe production signals, input guards, real-time phases and battle state.
## Wave completion is driven deliberately; no combat/economy values are altered.
var app: Node
var checks: int = 0
var failures: Array = []
var samples: Array = []
var timings: Array = []
var phase_events: Array = []
var context: String = ""
var run_started: int = 0
var clock_before: Dictionary = {}

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		var note: String = context+" · "+message
		failures.append(note)
		if failures.size()<=35:
			push_error("LEARNING_TRANSITION "+note)

func on_phase_changed(value: String) -> void:
	phase_events.append({"case":context,"phase":value,"atUsec":Time.get_ticks_usec()})

func phase_elapsed(start: String, end: String) -> float:
	var start_tick: int = 0
	for event in phase_events:
		if str(event.get("case",""))!=context:
			continue
		if str(event.phase)==start:
			start_tick = int(event.atUsec)
		elif start_tick>0 and str(event.phase)==end:
			return (int(event.atUsec)-start_tick)/1000000.0
	return -1.0

func real_delay(seconds: float) -> void:
	await create_timer(seconds,true,false,true).timeout

func wait_phase(expected: String, timeout: float = 1.5) -> float:
	var started: int = Time.get_ticks_usec()
	while app.learning_transition.phase!=expected and (Time.get_ticks_usec()-started)/1000000.0<timeout:
		await process_frame
	check(app.learning_transition.phase==expected,"Presentation reaches "+expected+" within real-time timeout")
	return (Time.get_ticks_usec()-started)/1000000.0

func input_key(keycode: int, echo: bool = false) -> void:
	var event = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	if not echo:
		var release = InputEventKey.new()
		release.keycode = keycode
		release.pressed = false
		Input.parse_input_event(release)
	await process_frame

func input_mouse(point: Vector2) -> void:
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
	await process_frame

func cards() -> Array:
	return app.learning_field.target_buttons if app.context_task_active else app.quiz_choices

func surface() -> Control:
	return app.learning_field if app.context_task_active else app.modal

func continue_button() -> Button:
	return app.learning_field.continue_button if app.context_task_active else app.quiz_continue_button

func hint_button() -> Button:
	return app.learning_field.hint_button if app.context_task_active else app.quiz_hint_button

func answer_index(correct: bool = true) -> int:
	for index in range(app.quiz_task.get("choices",[]).size()):
		if (str(app.quiz_task.choices[index].id)==str(app.quiz_task.answerId))==correct:
			return index
	return -1

func answer_direct(correct: bool = true) -> void:
	var index: int = answer_index(correct)
	if index<0:
		return
	if app.context_task_active:
		app._answer_context(str(app.quiz_task.choices[index].id))
	else:
		app._answer_quiz(str(app.quiz_task.choices[index].id))

func remember_clocks() -> void:
	var actual: Dictionary = app.game.snapshot()
	clock_before = {"elapsed":actual.elapsed,"animationTime":actual.animationTime,"wave":actual.wave}

func frozen() -> void:
	var actual: Dictionary = app.game.snapshot()
	check(bool(actual.betweenWaves) and actual.elapsed==clock_before.elapsed and actual.animationTime==clock_before.animationTime,"Battle and animation clocks remain frozen throughout the presentation")
	check(int(actual.wave)==int(clock_before.wave) and not app.game.input_enabled,"Wave and battlefield input remain suspended until return finishes")

func record_sample(label: String) -> void:
	var card_states: Array = []
	for card in cards():
		card_states.append({"alpha":card.modulate.a,"scale":[card.scale.x,card.scale.y],"disabled":card.disabled,"rect":str(card.get_global_rect())})
	var screen: Control = surface()
	samples.append({"case":context,"sample":label,"phase":app.learning_transition.phase,"wallMs":Time.get_ticks_msec()-run_started,"battle":app.game.snapshot(),"task":app.quiz_task.duplicate(true),"resolved":app.quiz_resolved,"hinted":app.quiz_hinted,"surfaceAlpha":screen.modulate.a if screen!=null else null,"shadeAlpha":app.learning_transition.shade.color.a,"fieldVisible":app.field_clip.visible,"hudVisible":app.hud_bar.visible,"toolbarVisible":app.army_toolbar.visible,"subtitleVisible":app.learning_panel.visible,"cards":card_states})

func resize_window(dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	app._layout()
	await process_frame
	check(app.learning_transition.get_global_rect().size==Vector2(dimensions),"Transition veil follows the actual viewport after resizing")

func start_battle(battle_speed: float, dimensions: Vector2i) -> void:
	paused = false
	Engine.time_scale = 1.0
	app._select_tier(0)
	app._select_map(0)
	await resize_window(dimensions)
	app._begin_battle()
	app.game.set_speed(battle_speed)
	await process_frame
	check(app.game.running and not app.game.between_waves,"Production battle is running before its wave-end signal")
	check(app.learning_transition.phase=="idle" and not app.learning_transition.visible,"Battle begins without a presentation overlay")

func open_wave() -> int:
	var started: int = Time.get_ticks_usec()
	# Exercise the real timed wave-end signal at its production deadline.
	# This matrix verifies presentation; exact clock progression has separate QA.
	if app.game._is_timed_battle():
		app.game.elapsed = float(app.game._timed_wave().endSeconds)
	app.game._complete_wave()
	remember_clocks()
	check(not app.quiz_task.is_empty() and app.learning_transition.phase=="preview","Production wave-end signal begins a pending card presentation")
	return started

func entry_checks(started: int, expected_kind: String, resize_to: Vector2i = Vector2i.ZERO, pause_tree: bool = false) -> void:
	check(str(app.quiz_task.kind)==expected_kind,"Session issues the expected "+expected_kind+" task")
	check(app.field_clip.visible and app.hud_bar.visible and app.army_toolbar.visible and app.learning_panel.visible,"Preview retains the real frozen battle, HUD, roster and subtitles underneath")
	check(surface().modulate.a==0 and app.learning_transition.visible,"Prepared question starts transparent with a dedicated preview veil")
	check(continue_button().disabled and hint_button().disabled,"Entry prevents accidental skip and hint activation")
	var before: Dictionary = app.progress.data.learning.duplicate(true)
	var gold: int = app.game.gold
	answer_direct()
	cards()[answer_index()].pressed.emit()
	app._quiz_hint()
	app._continue_battle()
	await input_key(KEY_1+answer_index())
	await input_mouse(cards()[answer_index()].get_global_rect().get_center())
	await input_key(KEY_SPACE)
	check(not app.quiz_resolved and not app.quiz_hinted and app.game.gold==gold and app.progress.data.learning==before,"Entry discards direct callbacks, card clicks, digits, hints and skip without learning/reward changes")
	if pause_tree:
		paused = true
		Engine.time_scale = 3.0
	await real_delay(.08)
	record_sample("preview")
	check(app.learning_transition.shade.color.a>0 and app.field_clip.visible,"Preview progressively darkens the visible frozen battle")
	frozen()
	if resize_to!=Vector2i.ZERO:
		await resize_window(resize_to)
	await wait_phase("entering")
	await real_delay(.14)
	record_sample("cards-entering")
	check(cards().front().modulate.a>cards().back().modulate.a,"Answer cards appear in sequence with the last card still behind the first")
	check(cards().front().scale.x<1.0 and cards().front().scale.x>=.94,"Visible cards grow smoothly from their center")
	check(app.field_clip.visible and app.hud_bar.visible and app.army_toolbar.visible,"Battle stays under the screen fade until presentation becomes ready")
	frozen()
	if resize_to!=Vector2i.ZERO:
		await resize_window(Vector2i(1440,900) if resize_to.x==1280 else Vector2i(1280,800))
	await wait_phase("choice")
	var duration: float = phase_elapsed("preview","choice")
	timings.append({"case":context,"phase":"entry","seconds":duration,"wallFromWaveSeconds":(Time.get_ticks_usec()-started)/1000000.0,"speed":app.game.speed,"engineTimeScale":Engine.time_scale,"treePaused":paused})
	check(duration>=.60 and duration<=1.10,"Complete card entry lasts approximately 0.6–0.9 real seconds")
	paused = false
	Engine.time_scale = 1.0
	record_sample("choice")
	check(not app.field_clip.visible and not app.hud_bar.visible and not app.army_toolbar.visible and not app.learning_panel.visible,"Ready learning screen deliberately hides the battlefield and fixed bottom strip")
	check(not app.learning_transition.visible and not continue_button().disabled,"Ready card choice removes the veil and enables deliberate actions")
	for card in cards():
		check(not card.disabled and absf(card.modulate.a-1.0)<.01 and card.scale.is_equal_approx(Vector2.ONE),"Ready answer card is fully revealed and interactive")
	await input_key(KEY_SPACE,true)
	await input_key(KEY_1+answer_index(),true)
	check(not app.quiz_resolved,"A key held during entry cannot answer through its repeated echo after input unlocks")
	frozen()

func result_checks(correct: bool, hinted: bool, use_mouse: bool = false) -> void:
	if hinted:
		hint_button().pressed.emit()
		check(app.quiz_hinted,"Deliberate hint records actual assistance before answering")
	var index: int = answer_index(correct)
	var gold: int = app.game.gold
	var supports: int = app.game.learning_supports.size()
	var attempts: int = app.progress.data.learning.attempts.size()
	var started: int = Time.get_ticks_usec()
	if use_mouse:
		await input_mouse(cards()[index].get_global_rect().get_center())
	else:
		await input_key(KEY_1+index)
	check(app.quiz_resolved and app.learning_transition.phase=="revealing","Real card input applies a result and immediately begins emphasis")
	check(app.game.gold==gold+(25 if hinted else 70) if correct else app.game.gold==gold,"Result preserves the existing exact reward contract")
	check(app.progress.data.learning.attempts.size()>attempts,"Accepted answer writes a persistent transaction receipt")
	if app.context_task_active:
		check(app.game.learning_supports.size()==supports+(1 if correct else 0),"Only a correct context answer creates one actual support")
		if correct:
			check(int(app.game.learning_supports.back().duration)==(6 if hinted else 12),"Context support duration remains 6/12 seconds")
	var actual_translation: Control = app.learning_field.report_text if app.context_task_active else app.quiz_ruby
	check(actual_translation.meaning_visible,"Result reveals translation alongside the reward and card emphasis")
	var receipt_count: int = app.progress.data.learning.attempts.size()
	var result_gold: int = app.game.gold
	var result_supports: int = app.game.learning_supports.size()
	answer_direct()
	cards()[index].pressed.emit()
	app._continue_battle()
	await input_key(KEY_1+index)
	await input_mouse(cards()[index].get_global_rect().get_center())
	check(app.game.gold==result_gold and app.game.learning_supports.size()==result_supports and app.progress.data.learning.attempts.size()==receipt_count,"Result emphasis and repeat input cannot duplicate receipts, supplies or support")
	check(continue_button().disabled,"Result emphasis prevents a click from dismissing the new feedback immediately")
	await real_delay(.08)
	record_sample("result-emphasis")
	check(cards()[answer_index()].scale.x>1.0,"Correct card is briefly emphasized for either answer outcome")
	frozen()
	await wait_phase("result")
	timings.append({"case":context,"phase":"result","seconds":phase_elapsed("revealing","result"),"wallFromAnswerSeconds":(Time.get_ticks_usec()-started)/1000000.0})
	check(not continue_button().disabled,"Explicit return becomes available after result emphasis")
	record_sample("result")

func return_checks(skip: bool = false) -> void:
	var gold: int = app.game.gold
	var attempt_count: int = app.progress.data.learning.attempts.size()
	var wave: int = app.game.wave
	var started: int = Time.get_ticks_usec()
	continue_button().pressed.emit()
	check(app.learning_transition.phase=="exiting" and app.field_clip.visible and app.army_toolbar.visible and app.learning_panel.visible,"Return unveils the actual frozen battlefield behind the departing screen")
	check(not app.game.input_enabled and app.game.between_waves,"Return keeps simulation and battlefield input blocked until the fade ends")
	app._continue_battle()
	answer_direct()
	await input_key(KEY_ESCAPE)
	await input_key(KEY_1)
	await input_mouse(app.army_toolbar.get_global_rect().get_center())
	await real_delay(.12)
	frozen()
	record_sample("returning")
	check(surface().modulate.a>0 and surface().modulate.a<1.0,"Learning screen fades away over visible battle content")
	await wait_phase("idle")
	var duration: float = phase_elapsed("exiting","idle")
	timings.append({"case":context,"phase":"return","seconds":duration,"wallThroughNextWaveSeconds":(Time.get_ticks_usec()-started)/1000000.0})
	check(duration>=.30 and duration<=.52,"Return lasts approximately 0.3–0.5 real seconds")
	check(app.quiz_task.is_empty() and app.lesson_session.pending.is_empty() and not app.context_task_active and app.modal==null,"Return consumes the task and clears both screen paths once")
	check(app.game.input_enabled and not app.game.between_waves and app.game.wave==wave+1,"Only completed return starts exactly one following wave")
	check(app.game.gold==gold and app.progress.data.learning.attempts.size()==attempt_count,"Return and skip do not manufacture any answer reward or receipt")
	check(app.field_clip.visible and app.hud_bar.visible and app.army_toolbar.visible and app.learning_panel.visible,"Battle, HUD, eight classes and Japanese subtitles are restored")
	check(not app.learning_transition.visible and app.learning_transition.visuals.is_empty() and app.learning_transition.surface==null,"Completed return clears all veil and visual references")
	if skip:
		check(not app.quiz_resolved,"Skipped task is consumed without a resolved answer")

func normal_cases() -> void:
	for speed_index in range(3):
		var battle_speed: float = speed_index+1.0
		context = "support / speed %d" % int(battle_speed)
		await start_battle(battle_speed,Vector2i(1440,900))
		var started: int = open_wave()
		await entry_checks(started,"context",Vector2i(1280,800) if speed_index==0 else Vector2i.ZERO)
		await result_checks(speed_index!=2,speed_index==0,speed_index==1)
		if speed_index==0:
			var task_id: String = str(app.quiz_task.id)
			var gold: int = app.game.gold
			app._show_study()
			check(app.learning_transition.phase=="idle" and app.modal_context=="study" and not app.learning_transition.visible,"Dictionary cancels the completed presentation cleanly")
			app._return_from_study()
			await wait_phase("result")
			check(str(app.quiz_task.id)==task_id and app.quiz_resolved and app.game.gold==gold,"Dictionary restores the same result without re-crediting it")
		await return_checks()
		context = "meaning / speed %d" % int(battle_speed)
		started = open_wave()
		await entry_checks(started,"meaning",Vector2i(1920,1080) if speed_index==1 else Vector2i.ZERO,speed_index==2)
		await result_checks(speed_index!=0,false,speed_index==0)
		await return_checks()
		# Wave three carries a taught context mission. Escape skips its preview.
		context = "support preview Escape / speed %d" % int(battle_speed)
		open_wave()
		await input_key(KEY_ESCAPE)
		check(app.learning_transition.phase=="exiting","Escape during preview requests a smooth skip instead of answering")
		await wait_phase("idle")
		check(app.game.wave==4 and app.quiz_task.is_empty() and app.lesson_session.pending.is_empty(),"Preview Escape consumes the pending mission and resumes exactly once")
		context = "sentence / speed %d" % int(battle_speed)
		started = open_wave()
		await entry_checks(started,"sentence")
		await result_checks(true,true)
		await return_checks()
		context = "listening / speed %d" % int(battle_speed)
		# Issue from the production session using an available-voice boundary.
		# No Windows speech playback is claimed by this silent UI test.
		app.lesson_session.next_task(app.seen_this_run,app.game.wave,true)
		started = open_wave()
		await entry_checks(started,"listening")
		check(str(app.quiz_ruby.word.jp)==str(app.quiz_task.questionItem.jp) and str(app.quiz_ruby.word.jp).count("＿＿")==1,"Listening preserves the issued source sentence with exactly one blank")
		check(app.quiz_ruby.meaning_visible and str(app.quiz_ruby.word.ko)==str(app.quiz_task.questionItem.ko),"Listening preserves the source's Korean semantic cue")
		check(app.quiz_listen_button.disabled==app.japanese_voice.is_empty(),"Listening availability follows the real local voice capability")
		if speed_index==2:
			await return_checks(true)
		else:
			await result_checks(speed_index==0,false)
			await return_checks()

func interruption_cases() -> void:
	context = "entry dictionary interruption"
	await start_battle(2,Vector2i(1440,900))
	open_wave()
	var task_id: String = str(app.quiz_task.id)
	await real_delay(.12)
	app._show_study()
	await real_delay(.90)
	check(app.learning_transition.phase=="idle" and app.modal_context=="study" and not app.learning_field.visible,"Interrupted entry has no stale callback or veil over the dictionary")
	check(str(app.quiz_task.id)==task_id and app.quiz_hinted and not app.lesson_session.pending.is_empty(),"Dictionary preserves the pending task and existing assisted-answer rule")
	app._return_from_study()
	await wait_phase("choice")
	check(str(app.quiz_task.id)==task_id and app.learning_field.report_text.meaning_visible,"Dictionary return re-presents the same hinted request")
	await return_checks(true)
	context = "entry navigation interruption"
	open_wave()
	task_id = str(app.quiz_task.id)
	await wait_phase("entering")
	app._show_catalog()
	await real_delay(.90)
	check(app.front_end.visible and not app.ui.visible and not app.field_clip.visible and app.learning_transition.phase=="idle","Navigation cancels entry without a callback restoring hidden battle UI")
	app._resume_from_navigation()
	await wait_phase("choice")
	check(str(app.quiz_task.id)==task_id,"Navigation returns to the same issued task")
	context = "entering Escape"
	app._show_study()
	app._return_from_study()
	await wait_phase("entering")
	var gold: int = app.game.gold
	await input_key(KEY_ESCAPE)
	check(app.learning_transition.phase=="exiting","Escape during screen entry begins a safe return from its current opacity")
	await wait_phase("idle")
	check(app.game.gold==gold and app.game.wave==3,"Entering Escape skips once without an answer reward")
	context = "result Escape"
	open_wave()
	await wait_phase("choice")
	answer_direct()
	gold = app.game.gold
	var receipts: int = app.progress.data.learning.attempts.size()
	await real_delay(.08)
	await input_key(KEY_ESCAPE)
	check(app.learning_transition.phase=="exiting","Escape during result emphasis follows the smooth return path")
	await input_key(KEY_ESCAPE)
	await wait_phase("idle")
	check(app.game.wave==4 and app.game.gold==gold and app.progress.data.learning.attempts.size()==receipts,"Repeated result Escape preserves the single earned reward and resumes once")
	context = "exit map interruption"
	open_wave()
	await wait_phase("choice")
	app._continue_battle()
	await real_delay(.12)
	# Reload the always-unlocked first map. A later map now requires its own
	# all-correct gate receipt, which is outside this presentation matrix.
	app._select_map(0)
	var new_map: String = str(app.current_map.id)
	await real_delay(.60)
	check(app.learning_transition.phase=="idle" and app.learning_transition.visuals.is_empty() and not app.learning_transition.visible,"Map change kills a departing tween and its visual references")
	check(str(app.current_map.id)==new_map and app.game.wave==0 and app.modal_context=="briefing" and not app.battle_started,"Canceled return cannot start a wave on the freshly reloaded first map")
	context = "result dictionary interruption"
	app._begin_battle()
	open_wave()
	await wait_phase("choice")
	answer_direct(false)
	app._show_study()
	await real_delay(.45)
	check(app.learning_transition.phase=="idle" and app.modal_context=="study","Dictionary safely cancels result emphasis")
	app._return_from_study()
	await wait_phase("result")
	check(app.quiz_resolved and not app.quiz_outcome_correct,"Interrupted wrong answer reopens its persistent result")
	await return_checks()

func run() -> void:
	run_started = Time.get_ticks_msec()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"):
		push_error("Learning transition QA refuses the player's profile")
		quit(2)
		return
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://learning-transition-%d.json" % Time.get_ticks_msec()
	root.add_child(app)
	app.learning_transition.phase_changed.connect(on_phase_changed)
	await process_frame
	app.progress.data.settings.voice = false
	app.progress.data.settings.music = false
	app.progress.data.settings.effects = false
	app.battle_audio.set_enabled(false)
	app.player.stop()
	var army_before: Dictionary = app.progress.data.army.duplicate(true)
	await normal_cases()
	await interruption_cases()
	check(app.progress.data.army==army_before,"Presentation and input handling preserve the permanent army economy")
	paused = false
	Engine.time_scale = 1.0
	var report: Dictionary = {"checks":checks,"failures":failures,"timings":timings,"phaseEvents":phase_events,"productionSnapshots":samples,"scope":"Real production wave signals and issued context/meaning/sentence/listening tasks at battle speeds 1/2/3, native mouse/key input, phase guards, translation/reward emphasis, frozen simulation and animation, resize, SceneTree pause/global timescale, dictionary/navigation/map interruptions and repeated Escape. Silent listening verifies UI capability only."}
	var report_path: String = "user://qa_learning_transition_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_learning_transition_headless.json"
	var out: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	if out == null:
		push_error("Learning transition QA cannot write its report: "+report_path)
		quit(2)
		return
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	print("LEARNING_TRANSITION ",checks," checks / ",failures.size()," failures / ",samples.size()," production snapshots; report=",ProjectSettings.globalize_path(report_path))
	app._cancel_learning_transition()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	await real_delay(.5)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
