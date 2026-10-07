extends Node
## Pre-generated Japanese learning speech; no OS voice or network is required.
## The manifest holds metadata only. Decoded streams have a bounded lazy LRU.

signal finished
signal unavailable(text: String, reason: String)

const MANIFEST_PATH := "res://assets/learning-voice/manifest.json"
const CACHE_LIMIT := 12
const CACHE_BYTE_LIMIT := 12*1024*1024
var manifest_path: String = MANIFEST_PATH
var manifest: Dictionary = {}
var clips: Dictionary = {}
var player: AudioStreamPlayer
var volume: float = 0.8
var enabled: bool = true
var is_ready: bool = false
var _shutdown: bool = false
var _streams: Dictionary = {}
var _sizes: Dictionary = {}
var _lru: Array[String] = []
var _cache_bytes: int = 0
var current_key: String = ""
var current_text: String = ""
var last_error: String = ""
var played: int = 0
var rejected: int = 0

static func text_key(text: String) -> String:
	return text.strip_edges().sha256_text()

func setup() -> bool:
	if _shutdown: return false
	if player==null:
		player = AudioStreamPlayer.new()
		player.name = "OfflineJapaneseLearningPlayer"
		player.bus = "Master"
		player.finished.connect(_on_finished)
		add_child(player)
	if not FileAccess.file_exists(manifest_path):
		last_error = "학습 음성 자료를 찾을 수 없습니다."
		return false
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not decoded is Dictionary or not decoded.get("clips") is Dictionary:
		last_error = "학습 음성 목록을 읽을 수 없습니다."
		return false
	manifest = decoded
	clips = manifest.clips
	is_ready = not clips.is_empty() and bool(manifest.get("complete",false))
	return is_ready

func available() -> bool:
	return is_ready and not _shutdown

func can_speak(text: String) -> bool:
	if not available(): return false
	var key: String = text_key(text)
	if not clips.has(key) or not clips[key] is Dictionary: return false
	var path: String = str(clips[key].get("path",""))
	return _safe_path(path) and (ResourceLoader.exists(path,"AudioStream") or FileAccess.file_exists(path))

func _safe_path(path: String) -> bool:
	return path.begins_with("res://assets/learning-voice/clips/") and not path.contains("..") and path.get_extension().to_lower() in ["wav","ogg"]

func set_volume(value: float) -> void:
	volume = clampf(value,0.0,1.0) if is_finite(value) else 0.0
	if volume<=0.0: stop()
	_apply_gain()

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled: stop()

func _apply_gain() -> void:
	if player==null: return
	# Only the voice slider belongs here: Master bus applies master exactly once.
	player.volume_db = linear_to_db(maxf(volume,0.00001))+float(manifest.get("gainDb",-4.0))

func play_text(text: String) -> bool:
	if not enabled or volume<=0.0 or not can_speak(text):
		return _fail(text,"이 문장의 학습 음성을 사용할 수 없습니다.")
	var key: String = text_key(text)
	var stream: AudioStream = _stream_for(key)
	if stream==null or not is_finite(stream.get_length()) or stream.get_length()<=0.0:
		return _fail(text,"학습 음성 파일을 재생할 수 없습니다.")
	stop()
	current_key = key
	current_text = text.strip_edges()
	player.stream = stream
	player.pitch_scale = 1.0
	_apply_gain()
	player.play()
	played += 1
	last_error = ""
	return true

func _stream_for(key: String) -> AudioStream:
	if _streams.has(key):
		_lru.erase(key)
		_lru.append(key)
		return _streams[key]
	var path: String = str(clips[key].get("path",""))
	var stream: AudioStream
	if ResourceLoader.exists(path,"AudioStream"):
		stream = ResourceLoader.load(path,"AudioStream",ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	elif path.get_extension().to_lower()=="wav":
		stream = AudioStreamWAV.load_from_file(path)
	elif path.get_extension().to_lower()=="ogg":
		stream = AudioStreamOggVorbis.load_from_file(path)
	if stream==null: return null
	var bytes: int = stream.data.size() if stream is AudioStreamWAV else maxi(1,int(clips[key].get("bytes",1)))
	while not _lru.is_empty() and (_streams.size()>=CACHE_LIMIT or _cache_bytes+bytes>CACHE_BYTE_LIMIT):
		var old: String = _lru.pop_front()
		_cache_bytes -= int(_sizes.get(old,0))
		_streams.erase(old)
		_sizes.erase(old)
	# An unusually long single recording still plays without exceeding the cache.
	if bytes<=CACHE_BYTE_LIMIT:
		_streams[key] = stream
		_sizes[key] = bytes
		_lru.append(key)
		_cache_bytes += bytes
	return stream

func _fail(text: String, reason: String) -> bool:
	rejected += 1
	last_error = reason
	unavailable.emit(text,reason)
	return false

func is_speaking() -> bool:
	return player!=null and player.playing and not current_key.is_empty()

func stop() -> void:
	if player!=null:
		player.stop()
		player.stream = null
	current_key = ""
	current_text = ""

func _on_finished() -> void:
	stop()
	finished.emit()

func shutdown() -> void:
	if _shutdown: return
	stop()
	_shutdown = true
	_streams.clear()
	_sizes.clear()
	_lru.clear()
	_cache_bytes = 0
	manifest.clear()
	clips.clear()
	is_ready = false

func _exit_tree() -> void:
	shutdown()

func diagnostics() -> Dictionary:
	return {"available":available(),"backend":"offline-voicevox-nemo","synthetic":true,"clipCount":clips.size(),"cacheCount":_streams.size(),"cacheBytes":_cache_bytes,"cacheLimit":CACHE_LIMIT,"cacheByteLimit":CACHE_BYTE_LIMIT,"currentText":current_text,"currentKey":current_key,"speaking":is_speaking(),"volume":volume,"pitch":player.pitch_scale if player!=null else 1.0,"played":played,"rejected":rejected,"lastError":last_error,"shutdown":_shutdown}
