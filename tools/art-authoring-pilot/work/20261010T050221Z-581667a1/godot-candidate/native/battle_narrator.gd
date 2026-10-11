extends Node
## Licensed Japanese human recordings for infrequent important battle moments.
## One player, bounded queue and short expiry. TTS always takes precedence.
## No battle clock/state, BGM bus, save data or operating-system TTS changes.

signal clip_started(caption: Dictionary)
signal clip_finished(caption: Dictionary)

const MANIFEST_PATH := "res://assets/narration/manifest.json"
const QUEUE_LIMIT := 4
const EVENT_MEMORY_LIMIT := 128
const DEFAULT_VOLUME := 0.8
const MIN_GAP := 0.25

var manifest_path: String = MANIFEST_PATH
var voice_channel: String = "male"
var shared_director: Node
var enabled: bool = true
var volume: float = DEFAULT_VOLUME
var paused: bool = false
var voice_active: bool = false
var is_ready: bool = false
var player: AudioStreamPlayer
var bus_name: String = ""
var streams: Dictionary = {}
var clips: Dictionary = {}
var events: Dictionary = {}
var missing: Array[String] = []
var queue: Array[Dictionary] = []
var current: Dictionary = {}
var played: int = 0
var rejected: int = 0
var expired: int = 0
var tts_interrupted: int = 0
var play_counts: Dictionary = {}
var _clock: float = 0.0
var _next_start: float = 0.0
var _sequence: int = 0
var _last_event: Dictionary = {}
var _seen: Dictionary = {}
var _seen_order: Array[String] = []
var _cursor: Dictionary = {}
var _shutdown: bool = false

func _ready() -> void:
	set_process(false)

func bind_director(director: Node, channel: String) -> void:
	shared_director = director
	voice_channel = channel
	if shared_director!=null:
		shared_director.register_voice(self)

func setup(initial_enabled: bool = true, initial_volume: float = DEFAULT_VOLUME) -> bool:
	if _shutdown or not is_inside_tree():
		return false
	if is_ready:
		set_volume(initial_volume)
		set_enabled(initial_enabled)
		return true
	missing.clear()
	streams.clear()
	clips.clear()
	events.clear()
	var library = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not library is Dictionary or not bool(library.get("recordedOnly",false)):
		missing.append(manifest_path)
		return false
	for entry in library.get("clips",[]):
		if not entry is Dictionary:
			continue
		var id := str(entry.get("id",""))
		var path := str(entry.get("path",""))
		var stream = load(path) if ResourceLoader.exists(path) else null
		if stream == null and FileAccess.file_exists(path):
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
			stream = AudioStreamMP3.load_from_buffer(bytes) if path.get_extension().to_lower()=="mp3" else AudioStreamWAV.load_from_buffer(bytes,{"compress/mode":0})
		if id.is_empty() or streams.has(id) or not (stream is AudioStreamWAV or stream is AudioStreamMP3):
			missing.append(path)
			continue
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		else:
			stream.loop = false
		streams[id] = stream
		clips[id] = entry.duplicate(true)
	events = library.get("events",{}).duplicate(true)
	for recipe in events.values():
		for id in recipe.get("clips",[]):
			if not streams.has(str(id)):
				missing.append(str(id))
	if streams.is_empty() or not missing.is_empty():
		return false
	bus_name = "BattleNarration_%s_%d" % [voice_channel,get_instance_id()]
	AudioServer.add_bus()
	var index := AudioServer.bus_count-1
	AudioServer.set_bus_name(index,bus_name)
	AudioServer.set_bus_send(index,"Master")
	_configure_voice_bus(index)
	var limiter := AudioEffectLimiter.new()
	limiter.threshold_db = -5.0
	limiter.ceiling_db = -3.0
	AudioServer.add_bus_effect(index,limiter)
	player = AudioStreamPlayer.new()
	player.name = "JapaneseBattleNarration_%s" % voice_channel
	player.max_polyphony = 1
	player.bus = bus_name
	add_child(player)
	player.finished.connect(_on_finished)
	is_ready = true
	set_volume(initial_volume)
	set_enabled(initial_enabled)
	set_process(true)
	return true

func _configure_voice_bus(_index: int) -> void:
	# The male library retains its original recording pitch and timing.
	pass

func _voice_pitch_scale() -> float:
	return 1.0

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop()
	_apply_gain()

func set_volume(value: float) -> void:
	volume = clampf(value,0.0,1.0) if is_finite(value) else DEFAULT_VOLUME
	if volume <= 0.0:
		stop()
	_apply_gain()

func set_paused(value: bool) -> void:
	paused = value
	if player != null:
		player.stream_paused = paused and not voice_active
	if not paused:
		_start_next()

func set_voice_active(value: bool) -> void:
	if voice_active == value:
		return
	voice_active = value
	if voice_active and not current.is_empty():
		# Do not resume the middle of a military phrase after a learning question.
		# A currently playing narration is discarded; queued events retain expiry.
		tts_interrupted += 1
		_finish_current(true)
	if not voice_active:
		_start_next()

func enqueue(event_key: String, context: Dictionary = {}) -> bool:
	if not _can_accept() or not events.has(event_key):
		return _reject()
	var recipe: Dictionary = events[event_key]
	if _clock-float(_last_event.get(event_key,-100000.0)) < float(recipe.get("cooldown",0.0)):
		return _reject()
	var options: Array = recipe.get("clips",[])
	if options.is_empty():
		return _reject()
	var index := int(_cursor.get(event_key,0)) % options.size()
	var accepted := _queue_clip(str(options[index]),event_key,recipe,context)
	if accepted:
		_cursor[event_key] = index+1
		_last_event[event_key] = _clock
	return accepted

func play(clip_id: String, context: Dictionary = {}) -> bool:
	if not _can_accept() or not clips.has(clip_id):
		return _reject()
	# Explicit clip playback still obeys the same single-player/TTS/queue rules.
	var event_key := str(clips[clip_id].get("event","direct"))
	var recipe: Dictionary = events.get(event_key,{"priority":50,"maxAge":6})
	return _queue_clip(clip_id,event_key,recipe,context)

func _queue_clip(clip_id: String, event_key: String, recipe: Dictionary, context: Dictionary) -> bool:
	var token := str(context.get("eventId",""))
	if bool(recipe.get("terminal",false)):
		token = "terminal:"+str(context.get("battleId",context.get("mapId","default")))
	if not token.is_empty() and _seen.has(token):
		return _reject()
	var priority := int(recipe.get("priority",50))
	if queue.size() >= QUEUE_LIMIT:
		var lowest := 0
		for index in queue.size():
			if int(queue[index].priority) < int(queue[lowest].priority): lowest = index
		if int(queue[lowest].priority) >= priority:
			return _reject()
		queue.remove_at(lowest)
	_sequence += 1
	var entry := {"clipId":clip_id,"event":event_key,"priority":priority,"expiresAt":_clock+clampf(float(recipe.get("maxAge",6.0)),1.0,15.0),"sequence":_sequence,"context":context.duplicate(true)}
	if bool(recipe.get("terminal",false)):
		# End-of-battle lines supersede stale tactical reports. At most one result.
		queue.clear()
		if not current.is_empty(): _finish_current(true)
	queue.append(entry)
	queue.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.priority)>int(b.priority) if int(a.priority)!=int(b.priority) else int(a.sequence)<int(b.sequence))
	if not token.is_empty():
		_seen[token] = true
		_seen_order.append(token)
		while _seen_order.size()>EVENT_MEMORY_LIMIT: _seen.erase(_seen_order.pop_front())
	_start_next()
	return true

func _can_accept() -> bool:
	return is_ready and not _shutdown and enabled and volume>0.0

func _reject() -> bool:
	rejected += 1
	return false

func _start_next() -> void:
	if not _can_accept() or paused or voice_active or not current.is_empty() or _clock<_next_start:
		return
	while not queue.is_empty():
		var entry: Dictionary = queue[0]
		if float(entry.expiresAt)<=_clock:
			queue.pop_front()
			expired += 1
			continue
		if shared_director!=null and not shared_director.try_acquire(self,int(entry.priority)):
			return
		queue.pop_front()
		current = entry
		var clip_id := str(entry.clipId)
		player.stream = streams[clip_id]
		player.volume_db = float(clips[clip_id].get("gainDb",-6.0))
		player.stream_paused = false
		player.play()
		played += 1
		play_counts[clip_id] = int(play_counts.get(clip_id,0))+1
		clip_started.emit(current_caption())
		return

func current_caption() -> Dictionary:
	if current.is_empty(): return {}
	var caption: Dictionary = clips[str(current.clipId)].duplicate(true)
	caption["event"] = current.event
	caption["context"] = current.context.duplicate(true)
	return caption

func is_speaking() -> bool:
	return player != null and player.playing and not player.stream_paused and not current.is_empty()

func _on_finished() -> void:
	_finish_current(false)

func _finish_current(interrupted: bool) -> void:
	var caption := current_caption()
	if player != null:
		player.stop()
		player.stream = null
		player.stream_paused = false
	current.clear()
	if shared_director!=null:
		shared_director.release(self)
	_next_start = _clock+MIN_GAP
	if not caption.is_empty():
		caption["interrupted"] = interrupted
		clip_finished.emit(caption)

func _process(delta: float) -> void:
	if not is_finite(delta) or delta<0.0: return
	# Queue age follows elapsed app time during TTS, but explicit pause freezes it.
	if not paused: _clock += delta
	if voice_active and not current.is_empty(): _finish_current(true)
	if not enabled or volume<=0.0:
		if not current.is_empty() or not queue.is_empty(): stop()
		return
	while not queue.is_empty() and float(queue[0].expiresAt)<=_clock:
		queue.pop_front()
		expired += 1
	_start_next()
	if _last_event.size()>64:
		for key in _last_event.keys():
			if _clock-float(_last_event[key])>120.0: _last_event.erase(key)

func _apply_gain() -> void:
	var index := AudioServer.get_bus_index(bus_name) if not bus_name.is_empty() else -1
	if index>0:
		AudioServer.set_bus_volume_db(index,linear_to_db(maxf(volume,.00001)))
		AudioServer.set_bus_mute(index,not enabled or volume<=0.0)

func stop() -> void:
	queue.clear()
	_finish_current(true)

func reset_battle() -> void:
	stop()
	_last_event.clear()
	_seen.clear()
	_seen_order.clear()
	_cursor.clear()
	_next_start = _clock

func shutdown() -> void:
	stop()
	_shutdown = true
	is_ready = false
	streams.clear()
	clips.clear()
	events.clear()
	set_process(false)

func _exit_tree() -> void:
	shutdown()
	var index := AudioServer.get_bus_index(bus_name)
	if index>0: AudioServer.remove_bus(index)

func diagnostics() -> Dictionary:
	var index := AudioServer.get_bus_index(bus_name) if not bus_name.is_empty() else -1
	return {"ready":is_ready,"enabled":enabled,"volume":volume,"paused":paused,"voiceActive":voice_active,"speaking":is_speaking(),"activePlayers":1 if is_speaking() else 0,"clips":streams.size(),"missing":missing.duplicate(),"queued":queue.size(),"queueLimit":QUEUE_LIMIT,"played":played,"rejected":rejected,"expired":expired,"ttsInterrupted":tts_interrupted,"playCounts":play_counts.duplicate(),"current":current_caption(),"eventMemory":_seen.size(),"clock":_clock,"busName":bus_name,"busIndex":index,"busDb":AudioServer.get_bus_volume_db(index) if index>0 else -80.0,"pitchScale":_voice_pitch_scale(),"playbackSpeed":player.pitch_scale if player!=null else 1.0,"shutdown":_shutdown}
