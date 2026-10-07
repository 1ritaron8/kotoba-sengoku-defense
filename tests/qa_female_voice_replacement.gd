extends "res://tests/qa_battle_announcer.gd"
## Replacement-specific checks plus the maintained actual decoder/mixer,
## volume, queue, subtitle, male-channel and TTS-reservation regression.
## Headless only; no player save writes, OS speech dispatch or GPU.

func _init() -> void:
	report_name = "qa_female_voice_replacement.json"

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
