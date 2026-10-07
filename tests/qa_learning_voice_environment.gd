extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var profile := OS.get_environment("APPDATA").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/learning-voice/"):
		push_error("Learning voice diagnosis requires its isolated profile")
		quit(1)
		return
	var report := {"displayServer":DisplayServer.get_name(),"ttsEnabled":ProjectSettings.get_setting("audio/general/text_to_speech",false),"voices":DisplayServer.tts_get_voices(),"japaneseVoices":DisplayServer.tts_get_voices_for_language("ja"),"ttsSpeaking":DisplayServer.tts_is_speaking()}
	var file := FileAccess.open("user://learning-voice-environment.json",FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("LEARNING_VOICE_ENVIRONMENT "+JSON.stringify(report))
	quit(0)
