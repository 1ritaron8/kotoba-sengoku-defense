extends SceneTree
## External standalone pack verifier. The complete maintained announcer QA and
## replacement-specific hook are included here; no excluded res://tests import.
## Additional actual offline learning/channel/gain checks run only in Dummy audio.
## No GPU, campaign save, external service or operating-system speech dispatch.

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
var report_name: String = "qa_female_voice_packed.json"
var guard_metadata: Dictionary = {}
var event_dispatches: Array = []
var channel_observations: Dictionary = {}
var volume_observations: Dictionary = {}
var live_captures: Dictionary = {}
var phase_pcm: Dictionary = {}
var maximum_actual_voices: int = 0
var stable_pcm_overlap: Array = []
var last_observation_usec: int = 0
var last_transition_usec: int = 0
var phase_name: String = ""

func _option(arguments: PackedStringArray, name: String) -> String:
	for index in range(arguments.size()):
		if arguments[index]==name and index+1<arguments.size(): return arguments[index+1]
		if arguments[index].begins_with(name+"="): return arguments[index].trim_prefix(name+"=")
	return ""

func _normalized_path(path: String) -> String:
	return path.replace("\\","/").to_lower().trim_suffix("/")

func _packed_guard() -> bool:
	var appdata: String = _normalized_path(OS.get_environment("APPDATA"))
	var localdata: String = _normalized_path(OS.get_environment("LOCALAPPDATA"))
	var user_dir: String = _normalized_path(OS.get_user_data_dir())
	var prefix: String = "c:/jp_df/tests/profiles/female-voice-replacement/packed-"
	var arguments: PackedStringArray = OS.get_cmdline_args()
	var custom: PackedStringArray = OS.get_cmdline_user_args()
	var target: String = _option(custom,"--pack-file")
	var mounted: String = OS.get_environment("QA_MAIN_PACK")
	var expected_hash: String = _option(custom,"--expected-pack-sha").to_upper()
	var declared_cwd: String = _normalized_path(OS.get_environment("QA_VERIFIER_CWD"))
	# Godot removes consumed startup switches such as --audio-driver from
	# get_cmdline_args(). The launcher must pass Dummy to Godot and attest the
	# same value explicitly; do not infer the runtime driver from missing args.
	var declared_audio: String = OS.get_environment("QA_AUDIO_DRIVER")
	check(appdata.begins_with(prefix) and appdata==localdata and user_dir.begins_with(appdata+"/"),"APPDATA, LOCALAPPDATA and actual user:// are the same private packed-verifier profile")
	check(DisplayServer.get_name()=="headless" and declared_audio=="Dummy" and _option(custom,"--declared-audio-driver")=="Dummy","Explicit headless renderer and matching launcher Dummy audio declarations are mandatory")
	check(custom.has("--packed") and not arguments.has("--path"),"Pack-only execution has no source-project override")
	check(declared_cwd=="c:/jp_df/tools/pack-learning-verifier-empty","Launcher records the required empty verifier working directory")
	check(not target.is_empty() and _normalized_path(target)==_normalized_path(mounted) and _normalized_path(target).begins_with("c:/jp_df/tests/") and target.get_extension().to_lower()=="exe","Mounted main-pack is exactly the isolated installer-extracted executable")
	for contract in [{"argument":"--expected-voice-sha","path":"res://assets/announcements/manifest.json"},{"argument":"--expected-narration-sha","path":"res://assets/narration/manifest.json"}]:
		var expected_resource: String=_option(custom,str(contract.argument)).to_upper()
		check(expected_resource.length()==64 and FileAccess.get_sha256(str(contract.path)).to_upper()==expected_resource,"Actually mounted packed voice contract matches supplied final SHA: "+str(contract.path))
	check(not FileAccess.file_exists(declared_cwd+"/project.godot") and not DirAccess.dir_exists_absolute(declared_cwd+"/native"),"Declared verifier working directory has no loose project or native source")
	check(expected_hash.length()==64,"Caller supplies the expected final executable SHA256")
	var actual_hash: String = FileAccess.get_sha256(target).to_upper() if FileAccess.file_exists(target) else ""
	check(not actual_hash.is_empty() and actual_hash==expected_hash,"Actual executable bytes match the parent's final pack fingerprint")
	check(not FileAccess.file_exists("res://tests/qa_battle_announcer.gd"),"Excluded source test library is unavailable inside the mounted product")
	guard_metadata = {"appData":appdata,"localAppData":localdata,"actualUserDataDir":user_dir,"declaredVerifierCwd":declared_cwd,"displayDriver":DisplayServer.get_name(),"declaredAudioDriver":declared_audio,"startupAudioArgumentRetained":_option(arguments,"--audio-driver"),"startupMainPackArgumentRetained":_option(arguments,"--main-pack"),"declaredMountedMainPack":mounted,"targetPack":target,"expectedSha256":expected_hash,"actualSha256":actual_hash,"externalTest":true,"noSourceProjectOverride":not arguments.has("--path"),"mountedVoiceManifestSha256":FileAccess.get_sha256("res://assets/announcements/manifest.json"),"mountedNarrationManifestSha256":FileAccess.get_sha256("res://assets/narration/manifest.json")}
	Engine.max_fps = 60
	return failures.is_empty()

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

func _after_library_checks(library: Dictionary) -> void:
	check(int(library.version)==2,"New original-performer manifest version")
	check(bool(library.inactiveLegacySource.get("active",true))==false,"Old lowered voice library is explicitly inactive")
	check(str(library.inactiveLegacySource.voiceActor)=="音枝優日","Replacement uses a different human performer")
	check(library.unavailableExactPhrases.has("正解です") and library.unavailableExactPhrases.has("ヒントです"),"Unavailable exact voice lines are disclosed rather than fabricated")
	check(library.events.size()==7 and not library.events.has("start"),"Seven notification events, no second battle-start announcer")
	for clip in library.clips:
		check(str(clip.path).begins_with("res://assets/announcements/clips/hinanogimaya/"),"Each active event uses new performer directory: "+str(clip.id))
		check(not library.inactiveLegacySource.paths.has(str(clip.path)),"No event can select legacy pitch-treated recordings: "+str(clip.id))
		check(bool(clip.sourceFilesUnmodified),"Per-recording original-byte preservation: "+str(clip.id))
		check(str(clip.format.container)=="WAV" and str(clip.format.encoding)=="PCM" and int(clip.format.bitsPerSample)==16,"Original 16-bit PCM format: "+str(clip.id))
		var stream: AudioStreamWAV = female.streams[str(clip.id)]
		check(stream.mix_rate==int(clip.format.sampleRate) and stream.stereo==(int(clip.format.channels)==2),"Native audio retains recording rate/channel count: "+str(clip.id))
		if not packed:
			var bytes := FileAccess.get_file_as_bytes(str(clip.path))
			check(bytes.size()==int(clip.bytes) and bytes.slice(0,4).get_string_from_ascii()=="RIFF" and bytes.slice(8,12).get_string_from_ascii()=="WAVE","Actual complete RIFF/WAVE source file: "+str(clip.id))
			var page := FileAccess.get_file_as_string(str(clip.pageEvidence))
			check(page.contains(str(clip.originalFile)),"Original download filename occurs on official phrase page: "+str(clip.id))
	check(str(library.clips[0].ko)=="역시 잘하십니다!","Correct-answer caption is praise matching さすが")
	check(str(library.clips[1].ko)=="힘내세요.","Incorrect-answer caption is encouragement matching 元気出して")
	check(str(library.clips[2].ko)=="안내해 드리겠습니다.","Guidance caption does not claim to speak an arbitrary question")
	check(str(library.clips[3].ko)=="축하합니다.","Level-up congratulation keeps exact recorded meaning")
	check(str(library.clips[4].ko)=="새 전갈입니다.","Message-arrival caption keeps exact recorded meaning")

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
	if not _packed_guard():
		quit(2)
		return
	packed = "--packed" in OS.get_cmdline_user_args()
	var profile := ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not (profile.begins_with("c:/jp_df/tests/profiles/battle-announcer/") or profile.begins_with("c:/jp_df/tests/profiles/female-voice-replacement/")):
		quit(2)
		return
	if packed:
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--pack-file="): main_pack = argument.trim_prefix("--pack-file=")
		check(not main_pack.is_empty() and main_pack.replace("\\","/").to_lower().begins_with("c:/jp_df/tests/"),"Packed metadata identifies an isolated installed executable")
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
	await _inspect_packed_voice_channels(library,capture)
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
	report["packedGuards"] = guard_metadata
	report["eventDispatches"] = event_dispatches
	report["channelObservations"] = channel_observations
	report["volumeObservations"] = volume_observations
	report["maintainedSourceQA"] = {"baseSha256":"34DDA7DFBE780C1DC75AD76BE725E3D08FC2262FCD35836A11371667F030C42D","replacementSha256":"DA1D24D2C62EC00AC3E4B514CC87314C6B90765BFB57E7B032665ED647525913","allBaseCasesPreserved":true,"replacementHookPreserved":true}
	report["scope"] = "Exact installed pack; complete maintained announcer/replacement regression, five imported original-source WAV native decoders and actual mixers, seven real event dispatches, additional actual offline learning/male/female player and stable PCM-window non-overlap and controlled gain ratios. OS-TTS reservation callbacks remain simulated. No OS speech dispatch, GPU, campaign save, subjective listening or hardware speaker-volume claim. Imported audio may use Godot's native compression; the original recording speed/pitch and independently measured source energy remain checked."
	var output := FileAccess.open("user://"+report_name,FileAccess.WRITE)
	check(output!=null,"Isolated QA report opens")
	report.checks = checks
	if output!=null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	print("BATTLE_ANNOUNCER_QA ",JSON.stringify({"checks":checks,"failures":failures,"capturedRms":rms,"capturedPeak":peak,"packed":packed}))
	quit(0 if failures.is_empty() else 1)

func _pcm_stats(buffer: PackedVector2Array) -> Dictionary:
	var energy: float = 0.0
	var raw_peak: float = 0.0
	var nonzero: int = 0
	for frame in buffer:
		energy += frame.length_squared()*.5
		var amplitude: float = maxf(absf(frame.x),absf(frame.y))
		raw_peak = maxf(raw_peak,amplitude)
		if amplitude>.0005: nonzero += 1
	return {"frames":buffer.size(),"sumSquares":energy,"peak":raw_peak,"nonzeroFrames":nonzero,"rms":sqrt(energy/maxi(1,buffer.size()))}

func _begin_pcm_phase(name: String) -> void:
	phase_name = name
	phase_pcm = {}
	for channel in live_captures:
		live_captures[channel].clear_buffer()
		phase_pcm[channel] = {"frames":0,"sumSquares":0.0,"peak":0.0,"nonzeroFrames":0}
	last_observation_usec = Time.get_ticks_usec()
	last_transition_usec = last_observation_usec

func _observe_real_channels(delta: float) -> void:
	director._process(delta)
	female._process(delta)
	male._process(delta)
	var now: int = Time.get_ticks_usec()
	var active: int = int(director.learning_audio.is_speaking())+int(male.is_speaking())+int(female.is_speaking())+int(DisplayServer.tts_is_speaking())
	maximum_actual_voices = maxi(maximum_actual_voices,active)
	check(active<=1,"Actual packed male/female/offline learning players do not overlap: "+phase_name)
	if director.learning_audio.is_speaking():
		check(director.is_tts_active() and not male.is_speaking() and not female.is_speaking(),"Actual offline PCM owns the shared learning voice reservation")
	var hot: Array = []
	for channel in live_captures:
		var capture: AudioEffectCapture = live_captures[channel]
		var buffer: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
		var observed: Dictionary = _pcm_stats(buffer)
		var stats: Dictionary = phase_pcm[channel]
		stats.frames = int(stats.frames)+int(observed.frames)
		stats.sumSquares = float(stats.sumSquares)+float(observed.sumSquares)
		stats.peak = maxf(float(stats.peak),float(observed.peak))
		stats.nonzeroFrames = int(stats.nonzeroFrames)+int(observed.nonzeroFrames)
		if float(observed.peak)>.0005: hot.append(str(channel))
	# Bus buffers do not supply one sample-perfect shared timestamp. Exclude
	# transition windows, then combine actual player ownership with stable PCM.
	if phase_name=="three-channel-natural" and hot.size()>1 and now-last_observation_usec<=60000 and last_transition_usec<=last_observation_usec-60000:
		stable_pcm_overlap.append({"channels":hot,"atUsec":now,"windowUsec":now-last_observation_usec})
		check(false,"Two private voice buses emit in the same stable observation window")
	last_observation_usec = now

func _wait_real(seconds: float, drain: bool = false) -> void:
	var started_at: int = Time.get_ticks_usec()
	var previous: int = started_at
	while Time.get_ticks_usec()-started_at<int(seconds*1000000.0):
		await process_frame
		var now: int = Time.get_ticks_usec()
		_observe_real_channels(float(now-previous)/1000000.0)
		previous = now
		if drain and not director.is_voice_active() and female.queue.is_empty() and male.queue.is_empty() and director._pending_learning.is_empty() and director._scheduled_tts.is_empty():
			break
	if drain: check(not director.is_voice_active() and female.queue.is_empty() and male.queue.is_empty(),"Actual packed voice playback and queues finish naturally")

func _phase_results() -> Dictionary:
	var result: Dictionary = phase_pcm.duplicate(true)
	for stats in result.values(): stats["rms"] = sqrt(float(stats.sumSquares)/maxi(1,int(stats.frames)))
	return result

func _inspect_packed_voice_channels(library: Dictionary, female_capture: AudioEffectCapture) -> void:
	for event_key in library.events:
		reset()
		var event_id: String = "packed-seven-"+str(event_key)
		var accepted: bool = female.enqueue(str(event_key),{"eventId":event_id})
		var caption: Dictionary = female.current_caption()
		var recipe: Dictionary = library.events[event_key]
		check(accepted and female.is_speaking(),"Actual packed notification accepts and starts event: "+str(event_key))
		check(str(caption.get("id",""))==str(recipe.clips[0]) and str(caption.get("event",""))==str(event_key),"Event selects its original full phrase with matching caption: "+str(event_key))
		check(not female.enqueue(str(event_key),{"eventId":event_id}),"Duplicate event ID cannot replay a packed notification: "+str(event_key))
		event_dispatches.append({"event":event_key,"clipId":caption.get("id",""),"captionJP":caption.get("jp",""),"pitchScale":female.player.pitch_scale,"actualResource":female.player.stream.resource_path if female.player.stream!=null else ""})
		director.stop()
	check(event_dispatches.size()==7,"All seven final female events execute through the packed component")
	for item in decoded:
		var stream: AudioStreamWAV = female.streams[str(item.id)]
		item["nativeImportedFormat"] = stream.format
		item["mixRate"] = stream.mix_rate
		item["stereo"] = stream.stereo
	# Controlled whole-phrase capture at a lower slider value, compared with
	# the maintained maximum-volume capture of the same actual recording.
	reset()
	female.set_volume(.25)
	await create_timer(.12).timeout
	female_capture.clear_buffer()
	check(female.play("correct",{"eventId":"packed-quarter-volume"}),"Quarter-volume original phrase starts through the packed player")
	await create_timer(float(library.clips[0].seconds)+.12).timeout
	var quiet: Dictionary = _pcm_stats(female_capture.get_buffer(female_capture.get_frames_available()))
	var loud: Dictionary = {}
	for item in mixer:
		if str(item.id)=="correct": loud=item
	check(not loud.is_empty() and float(quiet.peak)>.005,"Controlled quiet phrase produces measurable actual PCM")
	if not loud.is_empty() and float(loud.peak)>0.0:
		var peak_ratio: float = float(quiet.peak)/float(loud.peak)
		var rms_ratio: float = float(quiet.rms)/maxf(.00001,float(loud.rms))
		check(absf(peak_ratio-.25)<.03 and rms_ratio>.20 and rms_ratio<.30,"Actual female mixer amplitude follows quarter volume")
		volume_observations["femaleQuarter"]={"ratioPeak":peak_ratio,"ratioRms":rms_ratio,"quiet":quiet,"loud":loud}
	reset()
	director.setup()
	director.set_process(false)
	check(director.learning_available() and director.can_speak("山"),"Packed complete offline learning cache is available without an OS voice ID")
	if not director.learning_available(): return
	var learning_capture = AudioEffectCapture.new()
	learning_capture.buffer_length = 4.0
	AudioServer.add_bus()
	var learning_bus: int = AudioServer.bus_count-1
	var learning_name: String = "PackedLearningVoiceQA_"+str(get_instance_id())
	AudioServer.set_bus_name(learning_bus,learning_name)
	AudioServer.set_bus_send(learning_bus,"Master")
	AudioServer.add_bus_effect(learning_bus,learning_capture)
	director.learning_audio.player.bus = learning_name
	var male_capture = AudioEffectCapture.new()
	male_capture.buffer_length = 4.0
	var male_bus: int = AudioServer.get_bus_index(male.bus_name)
	AudioServer.add_bus_effect(male_bus,male_capture)
	var male_effect_index: int = AudioServer.get_bus_effect_count(male_bus)-1
	live_captures={"male":male_capture,"female":female_capture,"learning":learning_capture}
	female.clip_started.connect(func(_caption: Dictionary): last_transition_usec=Time.get_ticks_usec())
	female.clip_finished.connect(func(_caption: Dictionary): last_transition_usec=Time.get_ticks_usec())
	male.clip_started.connect(func(_caption: Dictionary): last_transition_usec=Time.get_ticks_usec())
	male.clip_finished.connect(func(_caption: Dictionary): last_transition_usec=Time.get_ticks_usec())
	director.speech_started.connect(func(_text: String,_cached: bool): last_transition_usec=Time.get_ticks_usec())
	director.speech_finished.connect(func(_text: String,_interrupted: bool): last_transition_usec=Time.get_ticks_usec())
	await create_timer(.15).timeout
	_begin_pcm_phase("three-channel-natural")
	check(director.speak("山","",true),"Real packed offline Japanese reading starts without OS speech dispatch")
	check(director.learning_audio.is_speaking() and not male.is_speaking() and not female.is_speaking(),"Learning reading immediately owns the only voice slot")
	check(male.enqueue("wave_start",{"eventId":"packed-three-male"}) and female.enqueue("correct",{"eventId":"packed-three-female"}),"Male and female human phrases wait behind actual learning PCM")
	await _wait_real(8.0,true)
	await _wait_real(.15)
	var natural: Dictionary = _phase_results()
	for channel in natural:
		check(int(natural[channel].nonzeroFrames)>1000 and float(natural[channel].peak)>.005,"Actual packed "+str(channel)+" bus becomes audible during natural handoff")
		check(float(natural[channel].peak)<.75,"Packed "+str(channel)+" mixer retains output headroom")
	check(stable_pcm_overlap.is_empty() and maximum_actual_voices<=1,"Real three-channel scheduling has no player or stable PCM overlap")
	channel_observations={"maximumActualVoices":maximum_actual_voices,"stablePcmOverlapWindows":stable_pcm_overlap,"naturalHandoff":natural,"learningSource":director.learning_audio.diagnostics(),"noOsSpeechDispatch":true}
	# Observe effective voice gain and Master exactly once on actual cached PCM.
	var master_db: float = AudioServer.get_bus_volume_db(0)
	var master_muted: bool = AudioServer.is_bus_mute(0)
	var master_capture = AudioEffectCapture.new()
	master_capture.buffer_length=4.0
	AudioServer.add_bus_effect(0,master_capture)
	var master_effect_index: int = AudioServer.get_bus_effect_count(0)-1
	live_captures["master"] = master_capture
	AudioServer.set_bus_mute(0,false)
	AudioServer.set_bus_volume_db(0,0.0)
	director.stop()
	await _wait_real(.3)
	director.set_audio_levels(1.0,1.0)
	_begin_pcm_phase("cached-volume-full")
	check(director.speak("山","",true),"Full-volume cached reading starts")
	await _wait_real(2.0,true)
	await _wait_real(.12)
	var full: Dictionary = _phase_results()
	director.stop()
	await _wait_real(.3)
	AudioServer.set_bus_volume_db(0,linear_to_db(.5))
	director.set_audio_levels(.5,.4)
	male.set_volume(.4)
	female.set_volume(.4)
	check(is_equal_approx(director.volume,.2) and is_equal_approx(director.learning_audio.volume,.4),"Cached player gets voice slider once while reservation gets effective master-times-voice volume")
	check(absf(AudioServer.get_bus_volume_db(male_bus)-linear_to_db(.4))<.01 and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(female.bus_name))-linear_to_db(.4))<.01,"Both packed human recording buses receive the real voice slider")
	_begin_pcm_phase("cached-volume-fifth")
	check(director.speak("山","",true),"Cached reading starts with half Master and 40-percent voice")
	await _wait_real(2.0,true)
	await _wait_real(.12)
	var fifth: Dictionary = _phase_results()
	var master_ratio: float = float(fifth.master.peak)/maxf(.00001,float(full.master.peak))
	var player_ratio: float = float(fifth.learning.peak)/maxf(.00001,float(full.learning.peak))
	check(float(full.master.peak)>.005 and absf(master_ratio-.2)<.025,"Actual final Master PCM applies master and voice exactly once")
	check(absf(player_ratio-.4)<.025,"Actual cached voice bus applies only voice gain before Master")
	volume_observations["learningMasterAndVoice"]={"masterRatio":master_ratio,"playerRatio":player_ratio,"full":full,"fifth":fifth}
	director.set_audio_levels(0.0,.4)
	check(not director.speak("山","",true) and not director.try_acquire(male,50),"Zero Master prevents both new learning and human-voice grants")
	director.set_audio_levels(1.0,0.0)
	check(not director.speak("山","",true),"Zero voice slider rejects new learning playback")
	director.stop()
	AudioServer.set_bus_volume_db(0,master_db)
	AudioServer.set_bus_mute(0,master_muted)
	director.learning_audio.player.bus="Master"
	AudioServer.remove_bus_effect(0,master_effect_index)
	AudioServer.remove_bus_effect(male_bus,male_effect_index)
	AudioServer.remove_bus(learning_bus)
	live_captures.clear()

