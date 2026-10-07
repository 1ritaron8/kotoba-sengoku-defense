extends SceneTree
var checks: int = 0
var failures: Array[String] = []

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		push_error("HISTORICAL_MUSIC: "+note)

func _initialize() -> void:
	var library: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/music.json"))
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var tracks: Array=library.get("tracks",[])
	check(tracks.size()==40,"There are exactly 40 stage tracks")
	var stages: Dictionary={}
	var works: Dictionary={}
	var audio_hashes: Dictionary={}
	var duration: float=0.0
	for track in tracks:
		var id: String=str(track.stageId)
		check(not stages.has(id),"A stage has only one track: "+id)
		stages[id]=true
		check(not works.has(str(track.compositionId)),"No composition is reused: "+id)
		works[str(track.compositionId)]=true
		check(not str(track.get("reasonKo","")).is_empty() and not str(track.get("mood","")).is_empty(),"The actual operation has a recorded music rationale: "+id)
		var bytes: PackedByteArray=FileAccess.get_file_as_bytes(str(track.path))
		check(bytes.size()>50000,"The distributed audio is present: "+id)
		var hasher: HashingContext=HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		hasher.update(bytes)
		var digest: String=hasher.finish().hex_encode()
		check(digest==str(track.get("sha256","")),"Audio matches the acquired original: "+id)
		check(not audio_hashes.has(digest),"Distinct tracks contain distinct audio: "+id)
		audio_hashes[digest]=true
		var stream: AudioStream
		if str(track.path).ends_with(".mp3"):
			var mp3: AudioStreamMP3=AudioStreamMP3.new()
			mp3.data=bytes
			stream=mp3
		else:
			stream=load(str(track.path)) as AudioStream
		check(stream!=null,"The real game decoder loads the file: "+id)
		if stream!=null:
			check(is_finite(stream.get_length()) and stream.get_length()>50.0,"The decoded stream is a full music work: "+id)
			check(stream.instantiate_playback()!=null,"The real decoder creates playable audio: "+id)
			duration+=stream.get_length()
		check(str(track.get("licenseUrl","")).begins_with("https://") and not str(track.get("author","")).is_empty(),"Credits and source terms are retained: "+id)
	for stage in maps:
		check(stages.has(str(stage.id)),"Every historical map has music: "+str(stage.id))
	print("HISTORICAL_MUSIC checks=",checks," failures=",failures.size()," distinctWorks=",works.size()," totalAudioSeconds=",duration)
	quit(0 if failures.is_empty() else 1)
