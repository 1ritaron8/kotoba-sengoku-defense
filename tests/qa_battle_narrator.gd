extends SceneTree
## Isolated offline asset, queue, TTS-interruption and real mixer verification.
## No campaign save/UI, external service, GPU or operating-system TTS calls.
const Narrator = preload("res://native/battle_narrator.gd")
var checks: int = 0
var failures: Array[String] = []
var pcm: Array = []
var started: Array = []
var finished_clips: Array = []
var captured_rms: float = 0.0
var captured_peak: float = 0.0
var packed: bool = false
var main_pack: String = ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("BATTLE NARRATOR: "+message)

func inspect_sources(library: Dictionary, narrator: Node) -> void:
	check(bool(library.get("recordedOnly",false)),"Only documented human voice recordings")
	check(str(library.get("voiceActor",""))=="ユーフルカ / YouFulca","Named original human performer is credited; referenced celebrities are not credited as performers")
	check(str(library.get("toneBasis","")).contains("cannot audition"),"Artistic audition limitation is disclosed")
	check(library.clips.size()==14 and narrator.streams.size()==14,"Fourteen real offline clips load")
	var source_ids: Dictionary = {}
	for source in library.sources:
		source_ids[str(source.id)] = true
		check(bool(source.get("commercialGameAllowed",false)),"Commercial game use documented for "+str(source.id))
		check(not bool(source.get("standaloneRedistributionAllowed",true)),"Standalone redistribution prohibition documented")
		check(str(source.licenseUrl)=="https://youfulca.com/kiyaku_jp/","Primary original terms linked")
		check(str(source.voiceEvidenceUrl)=="https://youfulca.com/voice_assets/","Primary human recording statement linked")
	var hashes: Dictionary = {}
	for clip in library.clips:
		var id := str(clip.id)
		check(source_ids.has(str(clip.sourceId)),"Named source referenced by "+id)
		check(str(clip.downloadUrl).begins_with("https://youfulca.com/wp-content/uploads/"),"Official public HTTPS download "+id)
		check(str(clip.sha256).length()==64 and not hashes.has(str(clip.sha256)),"Unique original SHA256 "+id)
		hashes[str(clip.sha256)] = true
		var combined := ""
		for part in clip.parts: combined += str(part.get("text",""))
		check(combined==str(clip.jp),"Furigana parts reconstruct exact recorded phrase "+id)
		check(not str(clip.reading).is_empty() and not str(clip.ko).is_empty(),"Japanese reading and Korean translation provided "+id)
		var stream: AudioStreamWAV = narrator.streams[id]
		if packed:
			check(ResourceLoader.exists(str(clip.path)),"Packed imported resource exists "+id)
			check(stream.resource_path==str(clip.path),"Actual imported stream loaded from packed path, not source-file fallback "+id)
		check(stream.format in [AudioStreamWAV.FORMAT_16_BITS,AudioStreamWAV.FORMAT_QOA] and not stream.stereo and stream.mix_rate==44100,"Mono44100 source in supported PCM16/QOA imported codec "+id)
		check(stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"No narration loops "+id)
		check(absf(stream.get_length()-float(clip.seconds))<.001,"Real source duration "+id)
		check(stream.get_length()>.5 and stream.get_length()<4.0,"Short contextual announcement "+id)
		check(float(clip.gainDb)<=-5.0,"Playback gain leaves headroom "+id)
		var sum_squared := 0.0
		var peak := 0.0
		var nonzero := 0
		var samples := 0
		if stream.format==AudioStreamWAV.FORMAT_16_BITS:
			for offset in range(0,stream.data.size()-1,2):
				var value := float(stream.data.decode_s16(offset))/32768.0
				sum_squared += value*value
				peak = maxf(peak,absf(value))
				if value!=0: nonzero += 1
			samples = stream.data.size()/2
		else:
			# QOA data contains codec bytes, not signed PCM16. Decode through the
			# engine's actual playback API, independent of the narration player.
			var playback := stream.instantiate_playback()
			playback.start()
			var decoded := playback.mix_audio(1.0,ceili(stream.get_length()*AudioServer.get_mix_rate()))
			playback.stop()
			samples = decoded.size()
			for frame in decoded:
				var value: float = (frame.x+frame.y)*.5
				sum_squared += value*value
				peak = maxf(peak,absf(value))
				if value!=0: nonzero += 1
		var rms := sqrt(sum_squared/maxi(1,samples))
		check(rms>.02 and nonzero>samples/4,"Actual non-silent voice PCM "+id)
		check(peak<1.08 and rms<.4,"Decoded voice level bounded; final output clipping tested at real mixer "+id)
		var tolerance: float = .004 if stream.format==AudioStreamWAV.FORMAT_QOA else .0001
		check(absf(rms-float(clip.rms))<tolerance,"Decoded RMS matches original recording within codec tolerance "+id)
		pcm.append({"id":id,"seconds":stream.get_length(),"rms":rms,"peak":peak,"samples":samples,"codec":stream.format,"resourcePath":stream.resource_path})
	for key in ["battle_start","strong_enemy","victory","defeat"]:
		check(library.events.has(key),"Important battle event available: "+key)
	for path in library.licenseFiles:
		check(FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains("Copyright remains"),"Shipped attribution and prohibition notice readable")

func run() -> void:
	packed = "--packed" in OS.get_cmdline_user_args()
	var profile := ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	var allowed_profile := profile.begins_with(qa_project_path("tests/profiles/battle-narrator/").to_lower()) or (packed and profile.begins_with(qa_project_path("tests/profiles/narrator-component-packed/").to_lower()))
	if not allowed_profile:
		quit(2)
		return
	if packed:
		var arguments := OS.get_cmdline_args()
		var pack_index := arguments.find("--main-pack")
		if pack_index>=0 and pack_index+1<arguments.size(): main_pack = arguments[pack_index+1]
		# Godot consumes --main-pack before exposing OS arguments. The command
		# supplies the same absolute target as an explicit QA metadata label.
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--pack-file="): main_pack = argument.trim_prefix("--pack-file=")
		check(not main_pack.is_empty() and main_pack.replace("\\","/").simplify_path().to_lower().begins_with(qa_project_path("tests/").to_lower()),"Explicit installed pack inside the QA workspace")
		check(not arguments.has("--path"),"Packed run has no source-project --path override")
	var narrator = Narrator.new()
	var initial_buses := AudioServer.bus_count
	root.add_child(narrator)
	check(narrator.setup(),"Offline narrator sets up")
	check(narrator.setup(),"Repeated setup is idempotent")
	check(AudioServer.bus_count==initial_buses+1,"Exactly one independently owned audio bus")
	narrator.set_process(false)
	narrator.clip_started.connect(func(caption: Dictionary): started.append(caption))
	narrator.clip_finished.connect(func(caption: Dictionary): finished_clips.append(caption))
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/narration/manifest.json"))
	inspect_sources(library,narrator)
	if packed:
		var third_party_path := main_pack.get_base_dir().path_join("ThirdParty.txt")
		check(FileAccess.file_exists(third_party_path),"Installed payload includes external ThirdParty.txt")
		var notice := FileAccess.get_file_as_string(third_party_path)
		check(notice.contains("JAPANESE BATTLE NARRATION") and notice.contains(str(library.voiceActor)),"Installed credits name the actual narration performer")
		check(notice.contains(str(library.credit)) and notice.contains("https://youfulca.com/kiyaku_jp/"),"Installed credits link the official author and terms")
		check(notice.contains("Copyright remains with YouFulca") and notice.contains("standalone audio assets"),"Installed notice retains copyright and standalone distribution restrictions")
		for clip in library.clips:
			check(notice.contains("Narration: "+str(clip.id)+"\n") and notice.contains(str(clip.originalFile)),"Installed credits include original clip "+str(clip.id))
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var bus := AudioServer.get_bus_index(narrator.bus_name)
	AudioServer.add_bus_effect(bus,capture)
	check(narrator.enqueue("battle_start",{"eventId":"start-1","battleId":"battle-A"}),"Actual start phrase plays")
	check(narrator.current_caption().get("id","")=="march" and narrator.is_speaking(),"Default start is the cool male march recording")
	check(narrator.enqueue("strong_enemy",{"eventId":"strong-1"}),"Strong enemy report waits behind the current voice")
	check(narrator.diagnostics().activePlayers==1 and narrator.queue.size()==1,"Narration never overlaps itself")
	check(not narrator.enqueue("battle_start",{"eventId":"start-2"}),"Per-event cooldown prevents repetitive starts")
	check(not narrator.play("march",{"eventId":"start-1"}),"Duplicate real event is not paid/replayed")
	check(not narrator.enqueue("unknown") and not narrator.play("missing"),"Unknown event/asset safely rejected")
	await create_timer(.40).timeout
	var buffer := capture.get_buffer(capture.get_frames_available())
	var energy := 0.0
	for frame in buffer:
		energy += frame.length_squared()*.5
		captured_peak = maxf(captured_peak,maxf(absf(frame.x),absf(frame.y)))
	captured_rms = sqrt(energy/maxi(1,buffer.size()))
	check(buffer.size()>1000 and captured_rms>.002,"Real AudioStreamPlayer mixer contains the downloaded human recording")
	check(captured_peak<.75,"Actual gain/limiter output leaves headroom")
	narrator.set_voice_active(true)
	check(not narrator.is_speaking() and narrator.current.is_empty(),"TTS onset immediately stops current narration")
	check(narrator.tts_interrupted==1 and narrator.queue.size()==1,"Interrupted phrase is discarded, pending tactical line kept briefly")
	narrator._process(.30)
	check(not narrator.is_speaking(),"No narration while TTS is active")
	narrator.set_voice_active(false)
	check(narrator.current_caption().get("id","")=="strong_enemy","Deferred report resumes only after TTS ends")
	narrator.set_paused(true)
	var clock: float = narrator._clock
	narrator._process(50.0)
	check(narrator._clock==clock and narrator.player.stream_paused,"Explicit pause freezes narration and queue age")
	narrator.set_paused(false)
	check(narrator.is_speaking(),"Explicit resume restores the same phrase")
	narrator.set_voice_active(true)
	narrator.reset_battle()
	for index in range(9): narrator.play("honor",{"eventId":"queued-%d" % index})
	check(narrator.queue.size()==narrator.QUEUE_LIMIT,"Queue memory is bounded at four")
	check(narrator.enqueue("victory",{"battleId":"battle-A"}),"Terminal victory supersedes low-priority queued reports")
	check(narrator.queue.size()==1 and str(narrator.queue[0].clipId)=="victory","Only the terminal phrase remains")
	check(not narrator.enqueue("defeat",{"battleId":"battle-A"}),"One battle cannot announce both victory and defeat")
	narrator._process(11.0)
	narrator.set_voice_active(false)
	check(narrator.queue.is_empty() and not narrator.is_speaking(),"Stale announcement expires during a long learning voice")
	narrator.reset_battle()
	check(narrator.enqueue("battle_start",{"eventId":"start-1"}),"New battle explicitly resets deduplication and cooldown")
	check(not narrator.current_caption().get("parts",[]).is_empty(),"Live caption includes source furigana parts")
	narrator.stop()
	check(not narrator.is_speaking() and narrator.queue.is_empty(),"Navigation stop clears current voice and pending reports")
	narrator.set_enabled(false)
	check(not narrator.enqueue("battle_start") and AudioServer.is_bus_mute(bus),"Disabled setting rejects events and mutes only the narrator bus")
	narrator.set_enabled(true)
	narrator.set_volume(NAN)
	check(is_finite(narrator.volume),"Nonfinite volume safely normalized")
	narrator.set_volume(-4.0)
	check(narrator.volume==0.0 and not narrator.play("march"),"Zero/negative volume cannot start a voice")
	narrator.set_volume(4.0)
	check(narrator.volume==1.0,"Oversized volume clamped")
	narrator.reset_battle()
	narrator.play("begin")
	await create_timer(.80).timeout
	check(narrator.current.is_empty() and not narrator.is_speaking(),"Actual player-finished signal releases the narration slot")
	check(started.size()>0 and finished_clips.size()>0,"Subtitle lifecycle signals delivered")
	var final_diagnostics: Dictionary = narrator.diagnostics()
	narrator.shutdown()
	check(not narrator.setup() and not narrator.enqueue("victory"),"Shutdown cannot restart stale nodes")
	narrator.queue_free()
	await process_frame
	await create_timer(.5).timeout
	check(AudioServer.bus_count==initial_buses,"Owned audio bus/player cleanly removed without affecting other audio")
	var report := {"checks":checks,"failures":failures,"packed":packed,"mainPack":main_pack,"packSha256":FileAccess.get_sha256(main_pack) if packed and not main_pack.is_empty() else "","pcm":pcm,"capturedRms":captured_rms,"capturedPeak":captured_peak,"diagnostics":final_diagnostics,"scope":"Actual official human WAVs and mixer output; isolated profile, no TTS/GPU/game/save mutations. Artistic tone not verified by unsupported audio-input audition."}
	var file := FileAccess.open("user://qa_battle_narrator.json",FileAccess.WRITE)
	check(file!=null,"Isolated report file opens")
	report.checks = checks
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("BATTLE_NARRATOR_QA ",JSON.stringify({"checks":checks,"failures":failures,"capturedRms":captured_rms,"capturedPeak":captured_peak}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
