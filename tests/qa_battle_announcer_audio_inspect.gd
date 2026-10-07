extends SceneTree
## Offline decoder inspection only. No GPU, game data or operating-system speech.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var profile := ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/battle-announcer/").to_lower()):
		quit(2)
		return
	var records = JSON.parse_string(FileAccess.get_file_as_string("res://assets/announcements/sources/downloads.json"))
	var measurements: Array = []
	for record in records:
		var stream := AudioStreamMP3.load_from_buffer(FileAccess.get_file_as_bytes(str(record.path)))
		if stream==null:
			push_error("Official MP3 cannot decode: "+str(record.id))
			quit(1)
			return
		var playback := stream.instantiate_playback()
		playback.start()
		var frames := playback.mix_audio(1.0,ceili(stream.get_length()*AudioServer.get_mix_rate()))
		playback.stop()
		var energy := 0.0
		var peak := 0.0
		var nonzero := 0
		for frame in frames:
			energy += frame.length_squared()*.5
			peak = maxf(peak,maxf(absf(frame.x),absf(frame.y)))
			if frame.length_squared()>0: nonzero += 1
		measurements.append({"id":record.id,"seconds":stream.get_length(),"rms":sqrt(energy/maxi(1,frames.size())),"peak":peak,"frames":frames.size(),"nonzeroFrames":nonzero,"mixRate":AudioServer.get_mix_rate(),"format":"original MP3 decoded by Godot"})
	var file := FileAccess.open("user://decoded-analysis.json",FileAccess.WRITE)
	if file==null:
		quit(1)
		return
	file.store_string(JSON.stringify(measurements,"  "))
	file.close()
	print("ANNOUNCER_AUDIO_INSPECT ",JSON.stringify(measurements))
	quit(0)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
