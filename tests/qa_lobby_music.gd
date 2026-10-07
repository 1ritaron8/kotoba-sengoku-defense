extends SceneTree
## Resource/attribution validation only; this does not claim auditory listening.
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		push_error("LOBBY_MUSIC "+note)

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/lobby-music/").to_lower()) or DisplayServer.get_name()!="headless":
		push_error("Refusing a player profile or GPU lobby-music check")
		quit(2)
		return
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/music/lobby/manifest.json"))
	for key in ["title","author","path","source","license","credit"]:
		check(metadata.has(key) and not str(metadata.get(key,"")).is_empty(),"runtime attribution field is present: "+key)
	check(metadata.license=="CC BY 4.0" and metadata.published=="2021-03-03","pre-March-2026 release and applicable license are explicit")
	check(str(metadata.credit).contains(metadata.source) and str(metadata.credit).contains(metadata.licenseUrl),"credit includes direct creator source and license link")
	check(not metadata.listeningVerified and str(metadata.officialStyleKo).contains("중국풍"),"selection states its actual style and unverified listening boundary")
	var tracks: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/music.json")).get("tracks",[])
	check(tracks.size()==40,"existing forty stage-track definitions are present")
	for track in tracks:
		check(str(track.compositionId)!=str(metadata.compositionId),"new lobby composition is not a reused stage work: "+str(track.stageId))
	var file: FileAccess=FileAccess.open(str(metadata.path),FileAccess.READ)
	check(file!=null,"official OGG is readable")
	if file==null:
		quit(1)
		return
	check(file.get_length()==int(metadata.bytes),"downloaded OGG byte count matches its manifest")
	check(file.get_buffer(4).get_string_from_ascii()=="OggS","file has the actual OGG container signature")
	file.close()
	check(FileAccess.get_sha256(str(metadata.path))==str(metadata.sha256),"exact original loop OGG hash matches its source provenance")
	var stream: AudioStreamOggVorbis=AudioStreamOggVorbis.load_from_file(str(metadata.path))
	check(stream!=null,"Godot actually decodes the original Vorbis stream without editor import")
	var duration: float=stream.get_length() if stream!=null else 0.0
	check(duration>30.0 and duration<600.0,"loop BGM has a plausible decoded duration")
	if stream!=null:
		stream.loop=true
		stream.loop_offset=float(metadata.loopOffset)
		check(stream.loop and stream.loop_offset==0.0,"runtime loop configuration is supported")
		check(stream.instantiate_playback()!=null,"decoded OGG can create an actual audio playback instance")
	var report: Dictionary={"checks":checks,"failed":failures.size(),"failures":failures,"durationSeconds":duration,"bytes":metadata.bytes,"sha256":metadata.sha256,"source":metadata.source,"scope":"CPU/headless: official OGG container/hash, actual Godot decoder/playback resource, loop configuration, all 40 composition IDs and runtime credit schema; no live listening or runtime Main music integration"}
	var output: FileAccess=FileAccess.open("user://qa_lobby_music.json",FileAccess.WRITE)
	if output!=null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	else: check(false,"isolated resource report is writable")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
