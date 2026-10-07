extends SceneTree
## Actual official WAV decoder/mixer and shared male/female/TTS-reservation tests.
## No GPU, campaign/profile writes, external service or actual OS speech dispatch.

const Announcer = preload("res://native/battle_announcer.gd")
const Narrator = preload("res://native/battle_narrator.gd")
const Director = preload("res://native/voice_director.gd")
const EXPECTED := {
	"correct":"さすが！", "incorrect":"元気出して", "hint":"ご案内いたします",
	"level_up":"おめでとうございます", "message_received":"新しいメッセージです"
}

var checks: int = 0
var failures: Array[String] = []
var decoded: Array = []
var started: Array = []
var ended: Array = []
var female: Node
var male: Node
var director: Node
var packed: bool = false
var main_pack: String = ""
var peak: float = 0.0
var rms: float = 0.0
var mixer: Array = []
var bus_processing: Dictionary = {}
var report_name: String = "qa_battle_announcer.json"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("BATTLE ANNOUNCER: "+message)

func advance(seconds: float) -> void:
	for step in ceili(seconds/.05):
		director._process(.05)
		female._process(.05)
		male._process(.05)
		check(int(director.diagnostics().activeVoices)<=1,"At most one voice channel during shared scheduling step")

func reset() -> void:
	director.stop()
	female.set_enabled(true)
	male.set_enabled(true)
	female.set_volume(.8)
	male.set_volume(.8)
	female.set_paused(false)
	male.set_paused(false)
	female.reset_battle()
	male.reset_battle()
	advance(.3)

func inspect_library(library: Dictionary) -> void:
	check(bool(library.get("recordedOnly",false)),"Human recording library only")
	check(str(library.get("voiceActor",""))=="雛乃木まや","Named new actual female recording performer")
	check(str(library.get("language",""))=="ja-JP","Japanese audio with Korean captions")
	check(str(library.get("toneBasis","")).contains("cannot audition"),"No unsupported artistic-audition claim")
	check(library.clips.size()==5 and female.streams.size()==5,"Five distinct complete original WAV recordings loaded")
	check(female.voice_channel=="female" and male.voice_channel=="male","Distinct male/female channel identity")
	check(not library.events.has("reinforcements") and not library.events.has("supply") and not library.events.has("start"),"No invented military phrases or duplicate female sortie")
	check(library.sources.size()==1,"One verified original active performer library")
	var source: Dictionary = library.sources[0]
	var processing: Dictionary = library.get("playbackProcessing",{})
	check(float(processing.get("runtimePitchScale",0.0))==1.0,"New performer retains original pitch")
	check(float(processing.get("playbackSpeed",0.0))==1.0 and float(processing.get("malePitchScale",0.0))==1.0,"Female and male retain original speed and pitch")
	check(not bool(processing.get("pitchEffect",true)) and not bool(processing.get("formantShift",true)) and not bool(processing.get("phraseSplicing",true)),"No pitch processing, formant shifting or phrase splicing")
	check(bool(processing.get("sourceFilesUnmodified",false)),"Downloaded source bytes stay unchanged")
	check(str(source.sourceUrl)=="https://hinanogimaya.com/download/","Official free-source index linked")
	check(str(source.voiceEvidenceUrl)=="https://hinanogimaya.com/voice/","Human recording and equipment evidence linked")
	check(bool(source.commercialGameAllowed) and not bool(source.creditRequired),"Official pages permit commercial use free and optional credit")
	check(bool(source.creditsMustNotImplyCommissionedPerformance),"Credit accurately identifies pre-existing voice material")
	if not packed:
		var evidence := FileAccess.get_file_as_string(str(source.pageEvidence))
		check(evidence.contains("商用") and evidence.contains("非商用") and evidence.contains("無料"),"Saved official index contains commercial/free permission")
		var performer := FileAccess.get_file_as_string(str(source.humanEvidence))
		check(performer.contains("録音") and performer.contains("RODE NT2-A"),"Saved official page confirms actual recording environment")
	var hashes: Dictionary = {}
	for clip in library.clips:
		var id := str(clip.id)
		check(EXPECTED.has(id) and str(clip.jp)==str(EXPECTED.get(id,"")),"Caption exactly matches official full phrase: "+id)
		check(str(clip.originalFile).begins_with("voice-") and str(clip.originalFile).ends_with(".wav"),"Original filename retained: "+id)
		check(str(clip.sourcePage).begins_with("https://hinanogimaya.com/") and not clip.has("downloadUrl"),"Official phrase page retained, not a public audio hotlink: "+id)
		check(str(clip.sha256).length()==64 and not hashes.has(clip.sha256),"Distinct original SHA256: "+id)
		hashes[clip.sha256] = true
		var body := ""
		for part in clip.parts: body += str(part.get("text",""))
		check(body==str(clip.jp) and clip.parts==clip.segments,"Both furigana caption aliases reconstruct actual speech: "+id)
		check(not str(clip.reading).is_empty() and not str(clip.ko).is_empty(),"Reading and Korean translation present: "+id)
		var stream: AudioStreamWAV = female.streams[id]
		check(stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"Complete original WAV never loops: "+id)
		check(absf(stream.get_length()-float(clip.seconds))<.002,"Actual decoded duration matches original: "+id)
		check(stream.get_length()>=1.0 and stream.get_length()<3.0,"Short fixed announcement: "+id)
		check(is_finite(float(clip.gainDb)) and float(clip.gainDb)<=0.0,"Runtime attenuation only, no raised source gain: "+id)
		if packed:
			check(ResourceLoader.exists(str(clip.path)),"Packed imported WAV exists: "+id)
			check(stream.resource_path==str(clip.path),"Actual packed import is loaded: "+id)
		else:
			check(FileAccess.get_sha256(str(clip.path)).to_upper()==str(clip.sha256),"Unmodified downloaded WAV bytes: "+id)
			var permission := FileAccess.get_file_as_string(str(clip.pageEvidence))
			check(permission.contains("商用・非商用") and permission.contains("必須ではありません"),"Each actual phrase has its own free use/optional credit evidence: "+id)
		var playback := stream.instantiate_playback()
		playback.start()
		var frames := playback.mix_audio(1.0,ceili(stream.get_length()*AudioServer.get_mix_rate()))
		playback.stop()
		var energy := 0.0
		var raw_peak := 0.0
		var nonzero := 0
		for frame in frames:
			energy += frame.length_squared()*.5
			raw_peak = maxf(raw_peak,maxf(absf(frame.x),absf(frame.y)))
			if frame.length_squared()>0.0: nonzero += 1
		var raw_rms := sqrt(energy/maxi(1,frames.size()))
		check(nonzero>frames.size()/5 and raw_rms>.02,"Original contains actual non-silent voice PCM: "+id)
		check(absf(raw_rms-float(clip.rms))<.002,"Independent native decoder matches original WAV energy: "+id)
		check(raw_peak<=1.0 and absf(raw_peak-float(clip.peak))<.02,"Native decoder peak matches source PCM: "+id)
		check(raw_peak*db_to_linear(float(clip.gainDb))<.6,"Even maximum caller volume retains peak headroom: "+id)
		decoded.append({"id":id,"seconds":stream.get_length(),"frames":frames.size(),"rms":raw_rms,"peak":raw_peak,"resourcePath":stream.resource_path})
	var notice := FileAccess.get_file_as_string("res://assets/announcements/NOTICE.txt")
	check(notice.contains("雛乃木まや") and notice.contains("https://hinanogimaya.com/download/"),"Embedded notice identifies current performer and permission")
	check(notice.contains("pitch and speed are 1.0") and notice.contains("INACTIVE LEGACY"),"Notice records original playback and preserves archived-source conditions")
	for event_key in EXPECTED:
		check(library.events.has(event_key),"Matching real-event feedback exists: "+event_key)
		var recipe: Dictionary = library.events[event_key]
		check(recipe.clips.size()==1 and str(recipe.clips[0])==event_key,"Actual event selects its complete original phrase: "+event_key)
		check(float(recipe.maxAge)<=4.0 and int(recipe.priority)<70,"Short expiry and subordinate tactical priority: "+event_key)
	for generic_event in ["answer_select","next_question"]:
		check(library.events.has(generic_event) and library.events[generic_event].clips==["hint"],"Unavailable exact instruction uses accurately captioned generic guidance: "+generic_event)
	_after_library_checks(library)

func _after_library_checks(_library: Dictionary) -> void:
	pass

func inspect_bus_processing() -> void:
	var female_index: int = AudioServer.get_bus_index(female.bus_name)
	var male_index: int = AudioServer.get_bus_index(male.bus_name)
	var female_effects: Array = []
	var male_effects: Array = []
	for index in AudioServer.get_bus_effect_count(female_index):
		female_effects.append(AudioServer.get_bus_effect(female_index,index).get_class())
	for index in AudioServer.get_bus_effect_count(male_index):
		male_effects.append(AudioServer.get_bus_effect(male_index,index).get_class())
	check(female_effects==["AudioEffectLimiter"],"Female original playback has no pitch/formant effect")
	check(male_effects==["AudioEffectLimiter"],"Male original pitch remains unchanged")
	check(female.player.pitch_scale==1.0 and male.player.pitch_scale==1.0,"Both actual players use source speed 1.0")
	check(float(female.diagnostics().pitchScale)==1.0 and float(male.diagnostics().pitchScale)==1.0,"Diagnostics describe actual original pitch")
	check(float(female.diagnostics().playbackSpeed)==1.0 and float(male.diagnostics().playbackSpeed)==1.0,"Diagnostics match real player speed")
	if not packed:
		var male_library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/narration/manifest.json"))
		for clip in male_library.clips:
			check(FileAccess.get_sha256(str(clip.path)).to_lower()==str(clip.sha256).to_lower(),"New female replacement leaves original male WAV bytes unchanged: "+str(clip.id))
	bus_processing = {"femaleEffects":female_effects,"maleEffects":male_effects,"femalePitchScale":female.diagnostics().pitchScale,"malePitchScale":male.diagnostics().pitchScale,"femalePlaybackSpeed":female.player.pitch_scale,"malePlaybackSpeed":male.player.pitch_scale}

func run() -> void:
	packed = "--packed" in OS.get_cmdline_user_args()
	var profile := ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not (profile.begins_with(qa_project_path("tests/profiles/battle-announcer/").to_lower()) or profile.begins_with(qa_project_path("tests/profiles/female-voice-replacement/").to_lower())):
		quit(2)
		return
	if packed:
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--pack-file="): main_pack = argument.trim_prefix("--pack-file=")
		check(not main_pack.is_empty() and main_pack.replace("\\","/").simplify_path().to_lower().begins_with(qa_project_path("tests/").to_lower()),"Packed metadata identifies an isolated installed executable")
		check(not OS.get_cmdline_args().has("--path"),"No source-project override in packed verification")
	var initial_buses := AudioServer.bus_count
	director = Director.new()
	female = Announcer.new()
	male = Narrator.new()
	root.add_child(director)
	root.add_child(female)
	root.add_child(male)
	female.bind_director(director,"female")
	male.bind_director(director,"male")
	check(female.setup(),"Female component setup succeeds")
	check(male.setup(),"Existing male component remains available")
	check(female.setup(),"Repeated setup is idempotent")
	check(AudioServer.bus_count==initial_buses+2 and female.bus_name!=male.bus_name,"Two privately owned single-player buses")
	check(female.player.max_polyphony==1 and male.player.max_polyphony==1,"Each recording player is monophonic")
	director.set_process(false)
	female.set_process(false)
	male.set_process(false)
	female.clip_started.connect(func(caption: Dictionary): started.append(caption))
	female.clip_finished.connect(func(caption: Dictionary): ended.append(caption))
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/announcements/manifest.json"))
	inspect_library(library)
	inspect_bus_processing()
	if packed:
		var third_party := FileAccess.get_file_as_string(main_pack.get_base_dir().path_join("ThirdParty.txt"))
		check(third_party.contains("雛乃木まや") and third_party.contains("声素材"),"Installed credits name actual material provider without a cast-performance claim")
		check(third_party.contains("https://hinanogimaya.com/download/"),"Installed credits link official terms")
		for clip in library.clips:
			check(third_party.contains(str(clip.originalFile)),"Installed credits retain original filename: "+str(clip.id))
	var capture := AudioEffectCapture.new()
	# The source WAVs keep their original leading silence; inspect a complete
	# phrase rather than judging the first .45 seconds as missing audio.
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(female.bus_name),capture)
	check(female.enqueue("correct",{"eventId":"accepted-answer-1"}),"Actual accepted-answer recording begins")
	check(female.is_speaking() and female.current_caption().jp==EXPECTED.correct,"Current caption matches exact playing audio")
	check(not female.enqueue("correct",{"eventId":"accepted-answer-1"}),"Duplicate answer cannot repeat announcement")
	check(male.enqueue("battle_start",{"eventId":"battle-start-1"}),"Male recording can queue during female announcement")
	check(not male.is_speaking() and male.queue.size()==1,"Male cannot overlap female actual playback")
	await create_timer(1.2).timeout
	var buffer := capture.get_buffer(capture.get_frames_available())
	var energy := 0.0
	for frame in buffer:
		energy += frame.length_squared()*.5
		peak = maxf(peak,maxf(absf(frame.x),absf(frame.y)))
	rms = sqrt(energy/maxi(1,buffer.size()))
	check(buffer.size()>1000 and rms>.005,"Actual AudioStreamPlayer mixer contains female voice")
	check(peak<.75,"Real mixer gain/limiter output does not clip")
	var reservation: int = director.reserve_tts()
	check(reservation>0 and not female.is_speaking() and not male.is_speaking(),"TTS reservation synchronously interrupts recordings before OS dispatch")
	check(female.tts_interrupted==1 and female.current.is_empty(),"Interrupted female sentence is discarded rather than resumed halfway")
	advance(.4)
	check(not male.is_speaking() and int(director.diagnostics().activeVoices)==1,"Queued male recording remains blocked throughout TTS reservation")
	director._on_tts_ended(reservation)
	advance(.3)
	check(male.is_speaking() and not female.is_speaking(),"Pending male starts only after TTS release and phrase gap")
	check(female.enqueue("hint",{"eventId":"hint-1"}),"Female hint waits behind current male voice")
	check(not female.is_speaking() and female.queue.size()==1,"Female cannot overlap male actual playback")
	male._on_finished()
	advance(.35)
	check(female.is_speaking() and female.current_caption().id=="hint","Male completion hands slot to female after gap")
	female.set_paused(true)
	var old_clock: float = female._clock
	female._process(50.0)
	check(female._clock==old_clock and female.player.stream_paused,"Explicit pause preserves voice position and expiry clock")
	check(not director.try_acquire(male,100),"Paused phrase still owns the slot until it ends or is stopped")
	female.set_paused(false)
	check(female.is_speaking(),"Resume continues the paused phrase")
	reset()
	reservation = director.reserve_tts()
	check(female.enqueue("answer_select",{"eventId":"choice-a"}),"Visible-choice instruction queues while learning speech active")
	# Dummy has no actual OS utterance. Keep the explicit reservation while
	# advancing recording age; Director's real missing-start timeout is tested
	# by its own QA rather than pretending a silent Dummy voice is speaking.
	female._process(4.2)
	male._process(4.2)
	director._on_tts_ended(reservation)
	advance(.3)
	check(female.queue.is_empty() and not female.is_speaking(),"Old choice instruction expires instead of reading stale UI")
	reset()
	reservation = director.reserve_tts()
	for index in range(9): female.play("message_received",{"eventId":"message-%d" % index})
	check(female.queue.size()==4,"Female backlog capped at four phrases")
	check(female.enqueue("hint",{"eventId":"new-hint"}),"Fresh learner hint replaces lower-priority stale message")
	check(female.queue.size()==4 and female.queue[0].clipId=="hint","Highest-priority female event heads the bounded queue")
	check(male.enqueue("danger",{"eventId":"danger-now"}),"Urgent existing male warning can queue alongside female hints")
	director._on_tts_ended(reservation)
	advance(.3)
	check(male.is_speaking() and not female.is_speaking(),"Shared gate grants higher-priority male warning even when female processes first")
	female.set_enabled(false)
	check(male.is_speaking() and not female.is_speaking(),"Disabling female cannot stop or release male-owned slot")
	check(not female.enqueue("hint") and female.queue.is_empty(),"Disabled female rejects events and clears queue")
	reset()
	check(not female.enqueue("unknown") and not female.play("missing"),"Unknown event and missing recording safely rejected")
	female.set_volume(NAN)
	check(is_finite(female.volume),"Nonfinite volume safely normalized")
	female.set_volume(-1)
	check(female.volume==0 and not female.enqueue("correct"),"Zero volume cannot begin announcement")
	female.set_volume(10)
	check(female.volume==1,"Excessive volume clamped")
	reset()
	check(female.enqueue("message_received",{"eventId":"report-a"}),"A real report-arrival announcement begins")
	check(female.current_caption().jp==EXPECTED.message_received and not female.current_caption().has("reportText"),"Fixed delivery clip does not claim to read arbitrary mission sentence")
	director.stop()
	check(not female.is_speaking() and not male.is_speaking() and female.queue.is_empty() and male.queue.is_empty(),"Navigation stop clears both voices and waiting phrases")
	reset()
	female.play("correct",{"eventId":"actual-finish"})
	await create_timer(float(library.clips[0].seconds)+.35).timeout
	check(female.current.is_empty() and not female.is_speaking(),"Actual audio-finished signal releases female player")
	check(not is_instance_valid(director.current_voice),"Actual completion releases shared voice ownership")
	check(started.size()>1 and ended.size()>1,"Subtitle start/finish lifecycle signals delivered")
	for clip in library.clips:
		reset()
		female.set_volume(1.0)
		await create_timer(.06).timeout
		capture.clear_buffer()
		female.play(str(clip.id),{"eventId":"mixer-"+str(clip.id)})
		await create_timer(float(clip.seconds)+.12).timeout
		var clip_frames := capture.get_buffer(capture.get_frames_available())
		var clip_energy := 0.0
		var clip_peak := 0.0
		for frame in clip_frames:
			clip_energy += frame.length_squared()*.5
			clip_peak = maxf(clip_peak,maxf(absf(frame.x),absf(frame.y)))
		var clip_rms := sqrt(clip_energy/maxi(1,clip_frames.size()))
		check(clip_frames.size()>1000 and clip_rms>.005,"Actual maximum-volume mixer is audible: "+str(clip.id))
		check(clip_peak<=.75,"Actual maximum-volume limiter leaves headroom: "+str(clip.id))
		mixer.append({"id":clip.id,"rms":clip_rms,"peak":clip_peak,"frames":clip_frames.size(),"volume":1.0})
	director.stop()
	var diagnostics: Dictionary = female.diagnostics()
	female.shutdown()
	male.shutdown()
	director.shutdown()
	check(not female.setup() and not female.enqueue("correct"),"Shutdown cannot reactivate old female node")
	female.queue_free()
	male.queue_free()
	director.queue_free()
	await process_frame
	await create_timer(.5).timeout
	check(AudioServer.bus_count==initial_buses,"Owned players/buses drain and release without affecting existing audio")
	var report := {"checks":checks,"failures":failures,"packed":packed,"mainPack":main_pack,"packSha256":FileAccess.get_sha256(main_pack) if packed and not main_pack.is_empty() else "","decoded":decoded,"capturedRms":rms,"capturedPeak":peak,"allClipMixer":mixer,"busProcessing":bus_processing,"diagnostics":diagnostics,"scope":"Official unchanged human Japanese WAVs, exact complete-source captions and bounded generic guidance, real decoder/mixer, original female and male pitch/speed, male/female queue and simulated OS-TTS reservation callbacks. No actual OS speech, GPU, campaign save or source gameplay mutation. Artistic auditory review unavailable."}
	var output := FileAccess.open("user://"+report_name,FileAccess.WRITE)
	check(output!=null,"Isolated QA report opens")
	report.checks = checks
	if output!=null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	print("BATTLE_ANNOUNCER_QA ",JSON.stringify({"checks":checks,"failures":failures,"capturedRms":rms,"capturedPeak":peak,"packed":packed}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
