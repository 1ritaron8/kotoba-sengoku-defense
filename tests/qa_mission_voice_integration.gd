extends SceneTree
## Production Main battle entry/listen controls and real three-channel mixer output.
## Start only after the final manifest is complete; both Windows data paths must
## point under tests/profiles/mission-voice-integration/. Never uses _quit_game().
## AudioEffectCapture is a non-modifying stereo float PCM bus tap:
## https://docs.godotengine.org/en/4.7/classes/class_audioeffectcapture.html

const Gate=preload("res://native/learning_gate.gd")
const LearningAudio=preload("res://native/learning_audio.gd")
var PROFILE_PREFIX: String=qa_project_path("tests/profiles/mission-voice-integration/").to_lower()
const PCM_THRESHOLD: float=.0005
var app: Node
var manifest: Dictionary={}
var checks: int=0
var failures: Array[String]=[]
var scope: String="startup"
var events: Array[Dictionary]=[]
var stage_results: Array[Dictionary]=[]
var interaction_results: Array[Dictionary]=[]
var images: Array[String]=[]
var bus_captures: Dictionary={}
var phase_pcm: Dictionary={}
var signal_channels: Dictionary={}
var max_actual_voices: int=0
var max_signal_voices: int=0
var stable_pcm_overlap_windows: Array[Dictionary]=[]
var last_observation_usec: int=0
var last_transition_usec: int=0
var learning_bus_name: String=""
var appdata: String=""
var localdata: String=""
var fixture_path: String=""
var fixture_user_default_existed: bool=false
var fixture_user_default_hash: String=""

func _initialize() -> void:
	Engine.max_fps=60
	call_deferred("run")

func check(condition: bool,note: String) -> void:
	checks+=1
	if not condition:
		failures.append(scope+": "+note)
		if failures.size()<=30: push_error("MISSION_VOICE_QA "+str(failures.back()))

func record_event(channel: String,kind: String,text: String,interrupted: bool=false,cached: bool=false) -> void:
	var now: int=Time.get_ticks_usec()
	last_transition_usec=now
	if kind=="started":
		signal_channels[channel]=true
		max_signal_voices=maxi(max_signal_voices,signal_channels.size())
		check(signal_channels.size()<=1,"Actual speech-start signals never hold two voice channels")
	else:
		signal_channels.erase(channel)
	events.append({"case":scope,"channel":channel,"kind":kind,"text":text,"interrupted":interrupted,"cached":cached,"atUsec":now})

func tap_bus(channel: String,bus_name: String) -> void:
	var index: int=AudioServer.get_bus_index(bus_name)
	check(index>=0,"Production voice bus exists for "+channel)
	if index<0: return
	var capture: AudioEffectCapture=AudioEffectCapture.new()
	capture.buffer_length=4.0
	AudioServer.add_bus_effect(index,capture)
	bus_captures[channel]={"effect":capture,"busName":bus_name}

func reset_pcm() -> void:
	phase_pcm.clear()
	for channel in bus_captures:
		var capture: AudioEffectCapture=bus_captures[channel].effect
		capture.clear_buffer()
		phase_pcm[channel]={"frames":0,"nonzeroFrames":0,"sumSquares":0.0,"peak":0.0,"discardedBefore":capture.get_discarded_frames()}
	last_observation_usec=Time.get_ticks_usec()

func observe() -> void:
	if not is_instance_valid(app): return
	var now: int=Time.get_ticks_usec()
	var delta: float=float(now-last_observation_usec)/1000000.0 if last_observation_usec>0 else 0.0
	var actual: int=int(app.voice_director.learning_audio.is_speaking())+int(app.battle_narrator.is_speaking())+int(app.battle_announcer.is_speaking())+int(DisplayServer.tts_is_speaking())
	max_actual_voices=maxi(max_actual_voices,actual)
	check(actual<=1,"Actual narrator/announcer/learning players never overlap")
	if app.voice_director.learning_audio.is_speaking():
		check(app.voice_director.is_tts_active() and not app.battle_narrator.is_speaking() and not app.battle_announcer.is_speaking(),"Offline PCM keeps the shared voice reservation")
	var hot: Array[String]=[]
	for channel in bus_captures:
		var capture: AudioEffectCapture=bus_captures[channel].effect
		var available: int=capture.get_frames_available()
		if available<=0: continue
		var buffer: PackedVector2Array=capture.get_buffer(available)
		var stats: Dictionary=phase_pcm[channel]
		var peak: float=0.0
		var square: float=0.0
		var nonzero: int=0
		for pair in buffer:
			var amplitude: float=maxf(absf(pair.x),absf(pair.y))
			peak=maxf(peak,amplitude)
			square+=pair.x*pair.x+pair.y*pair.y
			if amplitude>PCM_THRESHOLD: nonzero+=1
		stats.frames=int(stats.frames)+buffer.size()
		stats.nonzeroFrames=int(stats.nonzeroFrames)+nonzero
		stats.sumSquares=float(stats.sumSquares)+square
		stats.peak=maxf(float(stats.peak),peak)
		if peak>PCM_THRESHOLD: hot.append(str(channel))
	# Individual bus buffers are not a sample-perfect clock. Only short, stable
	# windows without a recent handoff are classified as PCM overlap. Actual
	# player states and start/finish intervals also cover the excluded windows.
	if hot.size()>1 and now-last_observation_usec<=60000 and last_transition_usec<=last_observation_usec-60000:
		stable_pcm_overlap_windows.append({"case":scope,"channels":hot,"atUsec":now,"windowUsec":now-last_observation_usec})
		check(false,"Two voice buses emit nonzero PCM in one stable mixer observation")
	app._update_caption_time(delta)
	last_observation_usec=now

func settle(frames: int=6) -> void:
	for unused in range(frames):
		await process_frame
		observe()

func wait_seconds(seconds: float) -> void:
	var deadline: int=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		await process_frame
		observe()

func wait_cached(text: String,timeout: float=2.5) -> bool:
	var deadline: int=Time.get_ticks_msec()+int(timeout*1000.0)
	while Time.get_ticks_msec()<deadline:
		observe()
		if app.voice_director.learning_audio.is_speaking() and app.voice_director.learning_audio.current_text==text: return true
		await process_frame
	return false

func voice_busy() -> bool:
	return app.voice_director.is_voice_active() or not app.battle_narrator.queue.is_empty() or not app.battle_announcer.queue.is_empty() or not app.voice_director._pending_learning.is_empty() or not app.voice_director._scheduled_tts.is_empty()

func wait_silent(timeout: float=20.0) -> void:
	var deadline: int=Time.get_ticks_msec()+int(timeout*1000.0)
	while voice_busy() and Time.get_ticks_msec()<deadline:
		await process_frame
		observe()
	await wait_seconds(.1)
	check(not voice_busy(),"Actual finished signals drain all voice players and queued reading")

func pcm_snapshot() -> Dictionary:
	var result: Dictionary={}
	for channel in phase_pcm:
		var stats: Dictionary=phase_pcm[channel].duplicate(true)
		var capture: AudioEffectCapture=bus_captures[channel].effect
		stats["rms"]=sqrt(float(stats.sumSquares)/float(maxi(1,int(stats.frames)*2)))
		stats["discardedFrames"]=capture.get_discarded_frames()-int(stats.discardedBefore)
		stats.erase("sumSquares")
		stats.erase("discardedBefore")
		result[channel]=stats
	return result

func assert_pcm(channel: String,stats: Dictionary) -> void:
	check(int(stats.frames)>100 and int(stats.nonzeroFrames)>100 and float(stats.peak)>PCM_THRESHOLD,"Real mixed nonzero PCM reaches "+channel+" bus")
	check(float(stats.peak)<1.0 and is_finite(float(stats.rms)),"Captured "+channel+" PCM is finite and unclipped")
	check(int(stats.discardedFrames)==0,"Capture consumption loses no "+channel+" mixer frames")

func caption_contract(entry: Dictionary) -> Dictionary:
	var subtitle: Control=app.narration_subtitle
	check(subtitle.visible,"Briefing start shows the actual battle subtitle")
	check(subtitle.word.jp==entry.briefingJP and subtitle.word.reading==entry.briefingReading and subtitle.word.ko==entry.briefingKo,"Ruby/KO caption is the exact spoken mission script")
	check(JSON.stringify(subtitle.word.parts)==JSON.stringify(entry.briefingParts),"Authored ruby groups survive the real Main signal callback")
	check(subtitle.meaning_visible,"Korean mission translation is enabled")
	var layout: Dictionary=subtitle.get_text_layout()
	var ruby_runs: int=0
	var meaning_runs: int=0
	for run in layout.runs:
		check(Rect2(Vector2.ZERO,subtitle.size).grow(1).encloses(run.bounds),"Actual subtitle glyph bounds fit their real control")
		if run.role=="reading": ruby_runs+=1
		if run.role=="meaning": meaning_runs+=1
	check(ruby_runs>0 and meaning_runs>0 and int(layout.ruby_size)>=22,"Real subtitle lays out furigana and readable Korean lines")
	check(root.get_visible_rect().grow(1).encloses(subtitle.get_global_rect()),"Actual mission caption fits the supported viewport")
	return {"word":subtitle.word.duplicate(true),"rect":subtitle.get_global_rect(),"rubyRuns":ruby_runs,"meaningRuns":meaning_runs,"rubySize":layout.ruby_size,"height":layout.height}

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var folder: String="user://qa_mission_voice_integration_captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path: String=folder+"/"+label+".png"
	var pixels: Image=root.get_texture().get_image()
	check(pixels!=null and not pixels.is_empty(),"GPU mission caption screenshot contains rendered pixels")
	if pixels!=null and not pixels.is_empty():
		pixels.save_png(path)
		images.append(ProjectSettings.globalize_path(path))

func gui_click(button: Button) -> void:
	check(button.is_visible_in_tree() and not button.disabled,"Existing listening control is visible and enabled")
	var point: Vector2=button.get_global_rect().get_center()
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	await settle(2)
	check(root.gui_get_hovered_control()==button,"Actual mouse input targets the existing listening button")
	for pressed in [true,false]:
		var event: InputEventMouseButton=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true)
		await settle(2)

func matching_events(text: String,kind: String,start_index: int) -> Array[Dictionary]:
	var found: Array[Dictionary]=[]
	for index in range(start_index,events.size()):
		var event: Dictionary=events[index]
		if event.channel=="learning" and event.text==text and event.kind==kind: found.append(event)
	return found

func unlock_fixtures() -> void:
	app.progress.data.learning["assessments"]={}
	for map in app.maps:
		var id: String=str(map.id)
		app.progress.data.maps[id]={"wins":1}
		var lesson: Dictionary=app.progress.stage_lessons[id]
		var count: int=lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
		app.progress.data.learning.assessments[id]={"passed":true,"count":count,"correctCount":count,"scopeHash":Gate.scope_hash(lesson),"attemptId":"mission-voice-fixture-"+id}

func briefing_case(index: int) -> void:
	var map: Dictionary=app.maps[index]
	var id: String=str(map.id)
	var entry: Dictionary=app.stories_by_id[id]
	var text: String=str(entry.briefingJP)
	scope="stage%02d %s"%[index+1,id]
	app._choose_stage(index/10,index%10,false)
	app.game.set_process(false)
	await wait_seconds(.3)
	check(not app.battle_started and not app.voice_director.learning_audio.is_speaking(),"Selecting a stage does not play its departure briefing")
	reset_pcm()
	var start_index: int=events.size()
	var before: int=app.voice_director.learning_audio.played
	var before_requests: int=app.voice_director.tts_requests
	app._begin_battle()
	check(app.battle_started and app.game.running,"Actual Main departure starts the selected battle")
	check(app.briefing_played_battle_id==app.narration_battle_id and not app.narration_battle_id.is_empty(),"Departure reserves this exact battle's one briefing")
	var began: bool=await wait_cached(text)
	check(began,"Actual _begin_battle starts the selected stage's offline briefing")
	if not began:
		stage_results.append({"stageId":id,"started":false,"diagnostics":app.voice_director.diagnostics()})
		app._stop_narration()
		return
	var caption: Dictionary=caption_contract(entry)
	var duration: float=app.voice_director.learning_audio.player.stream.get_length()
	check(app.voice_director.learning_audio.player.pitch_scale==1.0,"Commander speech plays at its authored1× pitch")
	if index in [0,25,39]: await shot("mission_%02d"%[index+1])
	var automatic_word: String=str(app.learning_words[app.learning_index].jp)
	app._speak(automatic_word,true)
	check(app.voice_director.tts_requests==before_requests+1 and app.voice_director._pending_learning.is_empty(),"A stale automatic word cannot interrupt or follow the mission instruction")
	var battle_id: String=app.narration_battle_id
	app._begin_battle()
	check(app.narration_battle_id==battle_id and app.voice_director.learning_audio.played==before+1,"Repeated/resumed departure cannot replay the mission briefing")
	var deadline: int=Time.get_ticks_msec()+int((duration+3.0)*1000.0)
	while app.voice_director.learning_audio.is_speaking() and app.voice_director.learning_audio.current_text==text and Time.get_ticks_msec()<deadline:
		await process_frame
		observe()
	check(not app.voice_director.learning_audio.is_speaking(),"Briefing recording finishes naturally")
	# SceneTree.process_frame resumes before child _process and queued finished
	# callbacks. A stopped player alone is not yet a received completion result.
	while matching_events(text,"finished",start_index).is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
		observe()
	var starts: Array[Dictionary]=matching_events(text,"started",start_index)
	var finishes: Array[Dictionary]=matching_events(text,"finished",start_index)
	check(starts.size()==1 and bool(starts[0].cached),"Exactly one cached briefing start is emitted for this battle")
	check(finishes.size()==1 and not bool(finishes[0].interrupted),"Exactly one natural briefing finish reaches Main")
	check(app.briefing_expected_text.is_empty() and app.narration_subtitle.visible and app.narration_caption_remaining>=1.7,"Completed mission retains Ruby/KO subtitle for its final reading dwell")
	var stats: Dictionary=pcm_snapshot()
	assert_pcm("learning",stats.learning)
	stage_results.append({"stageId":id,"stageNumber":index+1,"voiceType":manifest.clips[LearningAudio.text_key(text)].get("voiceType",""),"duration":duration,"startCount":starts.size(),"finishCount":finishes.size(),"caption":caption,"pcm":stats})
	print("MISSION_STAGE_QA stage=%d/40 starts=%d finishes=%d pcmPeak=%.6f"%[index+1,starts.size(),finishes.size(),float(stats.learning.peak)])
	app._stop_narration()
	await wait_seconds(.25)

func listening_cases() -> void:
	scope="recorded handoff and automatic learning"
	app._stop_narration()
	app.battle_narrator.reset_battle()
	app.battle_announcer.reset_battle()
	await wait_seconds(.3)
	reset_pcm()
	var first_event: int=events.size()
	var text: String=str(app.learning_words[app.learning_index].jp)
	check(app._narrate("battle_start","qa-natural-male"),"Main queues an actual male recording")
	await wait_seconds(.25)
	check(app.battle_narrator.is_speaking(),"Actual male player has started before its handoff")
	check(app._announce("answer_select","qa-natural-female"),"Main queues the female guidance behind the male")
	app._speak(text,true)
	check(app.voice_director._pending_learning.get("text","")==text,"Automatic visible word waits behind both recorded voices")
	await wait_silent(18.0)
	var stats: Dictionary=pcm_snapshot()
	for channel in ["male","female","learning"]: assert_pcm(channel,stats[channel])
	check(matching_events(text,"started",first_event).size()==1,"Waiting learning text starts once after recorded guidance")
	interaction_results.append({"case":scope,"pcm":stats,"events":events.slice(first_event)})
	scope="actual listening button interrupts female PCM"
	app._stop_narration()
	app.battle_narrator.reset_battle()
	app.battle_announcer.reset_battle()
	await wait_seconds(.3)
	reset_pcm()
	first_event=events.size()
	check(app._announce("correct","qa-listen-female"),"Main starts the actual female answer recording")
	await wait_seconds(.25)
	check(app.battle_announcer.is_speaking(),"A real female recording is audible before the listening click")
	var interrupted_before: int=app.battle_announcer.tts_interrupted
	var played_before: int=app.voice_director.learning_audio.played
	var listen: Button=app.ui.find_child("ListenButton",true,false)
	await gui_click(listen)
	check(await wait_cached(text),"Existing Main listening button starts its actual offline word stream")
	check(app.battle_announcer.tts_interrupted==interrupted_before+1 and not app.battle_announcer.is_speaking(),"Manual listening stops the female player before learning starts")
	check(app.voice_director.learning_audio.played==played_before+1,"One actual listening click causes one learning playback")
	await wait_silent(12.0)
	stats=pcm_snapshot()
	assert_pcm("female",stats.female)
	assert_pcm("learning",stats.learning)
	interaction_results.append({"case":scope,"pcm":stats,"events":events.slice(first_event)})

func teardown() -> void:
	if not is_instance_valid(app): return
	app._stop_narration()
	if app.music_fade!=null and app.music_fade.is_valid(): app.music_fade.kill()
	app.player.stop()
	app.player.stream=null
	app.battle_audio.shutdown()
	app.voice_director.shutdown()
	app.battle_narrator.shutdown()
	app.battle_announcer.shutdown()
	await wait_seconds(.5)
	app.queue_free()
	await process_frame
	await process_frame
	app=null
	var index: int=AudioServer.get_bus_index(learning_bus_name)
	if index>0: AudioServer.remove_bus(index)
	bus_captures.clear()

func run() -> void:
	appdata=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	localdata=OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	check(appdata.begins_with(PROFILE_PREFIX.to_lower()) and localdata.begins_with(PROFILE_PREFIX.to_lower()),"Both Windows data paths are in the isolated mission-voice profile")
	check(OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower().begins_with(appdata+"/"),"Actual user:// stays inside isolated APPDATA")
	if not failures.is_empty(): quit(2);return
	var decoded: Variant=JSON.parse_string(FileAccess.get_file_as_string(LearningAudio.MANIFEST_PATH))
	if not decoded is Dictionary or not bool(decoded.get("complete",false)):
		print("MISSION_VOICE_QA NOT_STARTED: final learning-voice manifest.complete is not true")
		quit(3)
		return
	manifest=decoded
	check(bool(manifest.get("briefingComplete",false)) and int(manifest.get("briefingStageCount",0))==40,"Complete manifest includes all40 commander briefings")
	if not failures.is_empty(): quit(3);return
	fixture_user_default_existed=FileAccess.file_exists("user://progress.json")
	if fixture_user_default_existed: fixture_user_default_hash=FileAccess.get_sha256("user://progress.json")
	fixture_path="user://mission-voice-main-%d.json"%Time.get_ticks_usec()
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=fixture_path
	app.progress.data.settings.music=false
	app.progress.data.settings.effects=false
	app.progress.data.settings.voice=true
	root.content_scale_size=Vector2i(1440,900)
	root.size=Vector2i(1440,900)
	root.add_child(app)
	app.set_process(false)
	app.game.set_process(false)
	app.atmosphere.set_process(false)
	app.troops_3d.set_process(false)
	app.combat_feedback.set_process(false)
	app.japanese_voice=""
	app._stop_narration()
	app.player.stop()
	app.battle_audio.set_enabled(false)
	app._apply_audio_settings()
	unlock_fixtures()
	check(app.maps.size()==40 and app.stories_by_id.size()==40,"Real Main joins all40 authored maps and mission scripts")
	check(app.voice_director.learning_available() and app.battle_narrator.is_ready and app.battle_announcer.is_ready,"Real Main sets up the offline commander and both recorded voice libraries")
	learning_bus_name="QAMissionLearning_%d"%app.get_instance_id()
	AudioServer.add_bus()
	var learning_index: int=AudioServer.bus_count-1
	AudioServer.set_bus_name(learning_index,learning_bus_name)
	AudioServer.set_bus_send(learning_index,"Master")
	app.voice_director.learning_audio.player.bus=learning_bus_name
	tap_bus("learning",learning_bus_name)
	tap_bus("male",app.battle_narrator.bus_name)
	tap_bus("female",app.battle_announcer.bus_name)
	reset_pcm()
	app.voice_director.speech_started.connect(func(text: String,cached: bool): record_event("learning","started",text,false,cached))
	app.voice_director.speech_finished.connect(func(text: String,interrupted: bool): record_event("learning","finished",text,interrupted))
	app.battle_narrator.clip_started.connect(func(caption: Dictionary): record_event("male","started",str(caption.id)))
	app.battle_narrator.clip_finished.connect(func(caption: Dictionary): record_event("male","finished",str(caption.id),bool(caption.interrupted)))
	app.battle_announcer.clip_started.connect(func(caption: Dictionary): record_event("female","started",str(caption.id)))
	app.battle_announcer.clip_finished.connect(func(caption: Dictionary): record_event("female","finished",str(caption.id),bool(caption.interrupted)))
	for index in range(40):
		var entry: Dictionary=app.stories_by_id[str(app.maps[index].id)]
		var text: String=str(entry.get("briefingJP",""))
		var metadata: Dictionary=manifest.clips.get(LearningAudio.text_key(text),{})
		check(not text.is_empty() and metadata.get("voiceType","")=="mission-briefing" and int(metadata.get("styleId",0))==10001,"Stage%d has its dedicated authored commander voice"%[index+1])
		check(str(metadata.get("reading",""))==str(entry.briefingReading) and str(metadata.get("ko",""))==str(entry.briefingKo),"Stage%d speech metadata matches Ruby and KO script"%[index+1])
		check(app.voice_director.can_speak(text),"Actual offline backend can read stage%d briefing"%[index+1])
	if failures.is_empty():
		for index in range(40): await briefing_case(index)
		await listening_cases()
	scope="final isolation and teardown"
	check(max_actual_voices<=1 and max_signal_voices<=1 and stable_pcm_overlap_windows.is_empty(),"Player states, speech intervals and stable PCM windows agree on single voice playback")
	check(app.voice_director.failed_tts_starts==0 and app.japanese_voice.is_empty(),"All speech uses offline PCM with no OS Japanese voice fallback")
	check(ProjectSettings.globalize_path(app.progress.save_path).replace("\\","/").simplify_path().to_lower().begins_with(appdata+"/"),"Every real Main persistence call stays inside its unique test fixture")
	check(FileAccess.file_exists("user://progress.json")==fixture_user_default_existed,"Default profile save existence is preserved")
	if fixture_user_default_existed: check(FileAccess.get_sha256("user://progress.json")==fixture_user_default_hash,"Default profile save bytes are preserved")
	var final_state: Dictionary=app.voice_director.diagnostics()
	await teardown()
	var report: Dictionary={"checks":checks,"failures":failures,"pass":failures.is_empty(),"stageResults":stage_results,"interactionResults":interaction_results,"events":events,"images":images,"maxActualVoices":max_actual_voices,"maxSignalVoices":max_signal_voices,"stablePcmOverlapWindows":stable_pcm_overlap_windows,"mixRate":AudioServer.get_mix_rate(),"finalDiagnostics":final_state,"appData":appdata,"localAppData":localdata,"actualUserDataDir":OS.get_user_data_dir(),"fixtureSave":ProjectSettings.globalize_path(fixture_path),"manifestSha256":FileAccess.get_sha256(LearningAudio.MANIFEST_PATH),"scope":"Production Main._choose_stage/_begin_battle and existing listening-button GUI dispatch. Three real AudioEffectCapture output taps plus player/signal overlap guards. Main combat/automatic-word clocks frozen for deterministic mission playback; no subjective listening, hardware output volume, OS voice configuration or sample-perfect bus alignment assertion."}
	var output: String="user://qa_mission_voice_integration.json"
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null: push_error("Cannot write isolated mission voice report");quit(2);return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("MISSION_VOICE_INTEGRATION checks=%d failures=%d stages=%d report=%s"%[checks,failures.size(),stage_results.size(),ProjectSettings.globalize_path(output)])
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
