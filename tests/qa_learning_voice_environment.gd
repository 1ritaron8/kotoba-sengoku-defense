extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var profile := OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/learning-voice/").to_lower()):
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

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
