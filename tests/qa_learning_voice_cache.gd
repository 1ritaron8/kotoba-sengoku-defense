extends SceneTree
## Actual offline Japanese coverage/decoded streams and shared recorded-player gate.
## Requires only an isolated workspace profile; no OS Japanese TTS or GPU needed.

const Director = preload("res://native/voice_director.gd")
const Male = preload("res://native/battle_narrator.gd")
const Female = preload("res://native/battle_announcer.gd")
var director: Node
var male: Node
var female: Node
var checks: int = 0
var failures: Array[String] = []
var max_voices: int = 0
var texts: Array[String] = []
var samples: Array = []
var missing: Array[String] = []
var sample_peak: float = 0.0
var learning_capture: AudioEffectCapture
var capture_bus: int = -1

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures.append(note)
		if failures.size()<=20: push_error("LEARNING_VOICE: "+note)

func collect(value: Variant) -> void:
	if value is Dictionary:
		if value.get("jp") is String and not str(value.jp).strip_edges().is_empty():
			var text: String = str(value.jp).strip_edges()
			if not text in texts: texts.append(text)
		for item in value.values(): collect(item)
	elif value is Array:
		for item in value: collect(item)

func observe() -> void:
	if learning_capture!=null and learning_capture.get_frames_available()>0:
		for pair in learning_capture.get_buffer(learning_capture.get_frames_available()):
			sample_peak = maxf(sample_peak,maxf(absf(pair.x),absf(pair.y)))
	var active: int = int(director.learning_audio.is_speaking())+int(male.is_speaking())+int(female.is_speaking())+int(DisplayServer.tts_is_speaking())
	max_voices = maxi(max_voices,active)
	check(active<=1,"Actual learning/male/female players never overlap")
	if director.learning_audio.is_speaking():
		check(director.is_tts_active() and not male.is_speaking() and not female.is_speaking(),"Cached player retains shared learning reservation")
	if samples.size()<80: samples.append(director.diagnostics())

func wait_seconds(duration: float) -> void:
	var until: int = Time.get_ticks_msec()+int(duration*1000.0)
	while Time.get_ticks_msec()<until:
		await process_frame
		observe()

func wait_silent(duration: float=15.0) -> void:
	var until: int = Time.get_ticks_msec()+int(duration*1000.0)
	while (director.is_voice_active() or not male.queue.is_empty() or not female.queue.is_empty() or not director._pending_learning.is_empty() or not director._scheduled_tts.is_empty()) and Time.get_ticks_msec()<until:
		await process_frame
		observe()
	check(not director.is_voice_active(),"All actual voices drain naturally")

func run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/learning-voice/").to_lower()):
		push_error("Offline learning QA requires its isolated workspace profile")
		quit(1)
		return
	director = Director.new()
	root.add_child(director)
	director.setup()
	director.set_audio_levels(1.0,.8)
	male = Male.new()
	root.add_child(male)
	male.bind_director(director,"male")
	female = Female.new()
	root.add_child(female)
	female.bind_director(director,"female")
	check(male.setup() and female.setup(),"Both original human recording libraries remain valid")
	check(director.learning_available(),"Complete offline learning manifest is available")
	AudioServer.add_bus()
	capture_bus = AudioServer.bus_count-1
	AudioServer.set_bus_name(capture_bus,"LearningVoiceQA")
	AudioServer.set_bus_send(capture_bus,"Master")
	learning_capture = AudioEffectCapture.new()
	learning_capture.buffer_length = 4.0
	AudioServer.add_bus_effect(capture_bus,learning_capture)
	director.learning_audio.player.bus = "LearningVoiceQA"
	var manifest: Dictionary = director.learning_audio.manifest
	check(bool(manifest.get("complete",false)) and int(manifest.get("wordCount",0))==900,"Manifest covers complete 900-word curriculum")
	check(director.learning_audio._streams.is_empty(),"Setup does not preload any audio stream")
	var word_count: int = 0
	var curriculum: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/curriculum.json"))
	for tier in curriculum.values():
		if not tier is Array: continue
		for lesson in tier: word_count += lesson.get("newWords",[]).size()
	check(word_count==900,"Current authored vocabulary still has 900 distinct word items")
	for path in ["res://native/curriculum.json","res://native/learning_plans.json","res://native/units.json"]:
		collect(JSON.parse_string(FileAccess.get_file_as_string(path)))
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	var briefings: int = 0
	for stage in story.get("stages",[]):
		var jp: String = str(stage.get("briefingJP","")).strip_edges()
		if jp.is_empty(): continue
		briefings += 1
		if not jp in texts: texts.append(jp)
		var entry: Dictionary = manifest.get("clips",{}).get(jp.sha256_text(),{})
		check(entry.get("voiceType","")=="mission-briefing" and int(entry.get("styleId",0))==10001,"Exact stage briefing uses a distinct neutral male Nemo style")
		check(str(entry.get("reading",""))==str(stage.get("briefingReading","")) and str(entry.get("ko",""))==str(stage.get("briefingKo","")),"Briefing audio/caption authored Japanese reading and Korean meaning remain aligned")
	check(briefings==40 and int(manifest.get("briefingStageCount",0))==40 and bool(manifest.get("briefingComplete",false)),"Every 40-stage briefing is included before final delivery")
	for text in texts:
		var available: bool = director.can_speak(text)
		check(available,"Authored Japanese text has an offline file: "+text)
		if not available:
			missing.append(text)
			continue
		var key: String = text.sha256_text()
		var info: Dictionary = manifest.clips[key]
		check(is_finite(float(info.get("duration",0))) and float(info.get("duration",0))>0.15,"Finite positive speech duration")
		check(float(info.get("peak",0))>.005 and float(info.get("rms",0))>.001,"Authored recording contains non-silent PCM")
		var stream: AudioStream = director.learning_audio._stream_for(key)
		check(stream!=null and is_finite(stream.get_length()) and stream.get_length()>.15,"Actual native stream decodes: "+text)
		var state: Dictionary = director.learning_audio.diagnostics()
		check(int(state.cacheCount)<=12 and int(state.cacheBytes)<=12*1024*1024,"Lazy LRU remains bounded across complete corpus")
		if checks%250==0: await process_frame
	check(director.speak("山","",true),"Reading works with an empty OS Japanese voice id")
	check(not director.learning_audio.current_key.is_empty(),"Actual offline stream selected")
	check(male.enqueue("danger",{"eventId":"learning:male"}) and female.enqueue("correct",{"eventId":"learning:female"}),"Human voices can wait behind Japanese learning")
	await wait_silent()
	check(sample_peak>.005 and sample_peak<1.0,"Actual learning PCM reaches the AudioServer mixer without clipping")
	check(director.failed_tts_starts==0,"A cached read never becomes a failed OS-TTS timeout")
	director.stop()
	await wait_seconds(.25)
	check(male.enqueue("battle_start",{"eventId":"learning:interrupt"}),"Human sortie starts before explicit listening request")
	check(director.speak("目印は山です。","",true),"Manual listening stops an active human phrase")
	await wait_seconds(.35)
	check(director.learning_audio.is_speaking() and not male.is_speaking() and not female.is_speaking(),"Only real learning audio is speaking after interruption")
	director.stop()
	await wait_seconds(.25)
	director.set_audio_levels(.5,.8)
	check(is_equal_approx(director.volume,.4) and is_equal_approx(director.learning_audio.volume,.8),"Master product for OS; voice-only gain for cached player avoids double Master multiplication")
	check(director.speak("川","",true),"Read after a positive volume adjustment")
	await wait_seconds(.25)
	director.set_audio_levels(0.0,.8)
	check(not director.is_voice_active() and not director.learning_audio.is_speaking(),"Master zero stops ongoing learning immediately")
	check(not director.speak("山","",true),"Master zero rejects new learning")
	check(not director.try_acquire(male,50),"Master zero cannot grant a new human voice reservation")
	director.set_audio_levels(1.0,0.0)
	check(not director.speak("山","",true),"Voice zero rejects new learning")
	director.set_audio_levels(1.0,.8)
	check(not director.speak("未登録の診断用文。","",true),"Missing text is explicitly rejected rather than a silent success")
	check(director.speak("山","",true),"Learning resumes after unmute")
	await wait_silent()
	var final_state: Dictionary = director.diagnostics()
	director.shutdown()
	male.shutdown()
	female.shutdown()
	check(director.learning_audio._streams.is_empty() and director.learning_audio.player.stream==null,"Teardown releases bounded streams and active audio")
	await create_timer(.5).timeout
	if capture_bus>=0: AudioServer.remove_bus(capture_bus)
	var report := {"checks":checks,"failures":failures,"pass":failures.is_empty(),"uniqueTextCount":texts.size(),"wordCount":word_count,"briefingCount":briefings,"missing":missing,"maxActualVoices":max_voices,"actualLearningMixerPeak":sample_peak,"finalDiagnostics":final_state,"samples":samples,"scope":"Actual cached learning stream playback and every authored Japanese text; no GPU/OS-Japanese installation"}
	var file := FileAccess.open("user://qa_learning_voice_cache.json",FileAccess.WRITE)
	if file==null:
		quit(1)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("LEARNING_VOICE_CACHE "+str(checks)+" checks / "+str(failures.size())+" failures")
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
