extends Node
## The two recorded announcers and system learning speech share one voice slot.
## Reserve it before dispatching TTS; an operating-system start callback may be late.

const PHRASE_GAP := 0.18
const TTS_START_TIMEOUT := 2.0
const LearningAudio = preload("res://native/learning_audio.gd")

signal learning_unavailable(text: String, reason: String)
signal speech_started(text: String, cached: bool)
signal speech_finished(text: String, interrupted: bool)

var voices: Array[Node] = []
var current_voice: Node
var _clock: float = 0.0
var _available_at: float = 0.0
var _tts_active: bool = false
var _tts_id: int = 0
var _tts_age: float = 0.0
var _tts_observed: bool = false
var _pending_learning: Dictionary = {}
var _scheduled_tts: Dictionary = {}
var _ready_for_speech: bool = false
var _shutdown: bool = false
var grants: int = 0
var delayed: int = 0
var tts_requests: int = 0
var failed_tts_starts: int = 0
var volume: float = 0.8
var master_volume: float = 1.0
var voice_volume: float = 0.8
var learning_audio: Node
var _cached_active: bool = false
var _speech_text: String = ""
var _speech_started: bool = false

func set_volume(value: float) -> void:
	volume = clampf(value,0.0,1.0) if is_finite(value) else 0.0
	master_volume = 1.0
	voice_volume = volume
	if learning_audio!=null:
		learning_audio.set_volume(voice_volume)
		learning_audio.set_enabled(volume>0.0)
	if volume<=0.0:
		stop()

func set_audio_levels(master: float, voice: float) -> void:
	master_volume = clampf(master,0.0,1.0) if is_finite(master) else 0.0
	voice_volume = clampf(voice,0.0,1.0) if is_finite(voice) else 0.0
	volume = master_volume*voice_volume
	if learning_audio!=null:
		learning_audio.set_volume(voice_volume)
		learning_audio.set_enabled(volume>0.0)
	if volume<=0.0: stop()

func setup() -> void:
	if _ready_for_speech or _shutdown:
		return
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED,_on_tts_started)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED,_on_tts_ended)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED,_on_tts_ended)
	_ready_for_speech = true
	learning_audio = LearningAudio.new()
	add_child(learning_audio)
	learning_audio.finished.connect(_on_cached_finished)
	learning_audio.unavailable.connect(func(text: String, reason: String): learning_unavailable.emit(text,reason))
	learning_audio.setup()
	learning_audio.set_volume(voice_volume)
	learning_audio.set_enabled(volume>0.0)
	set_process(true)

func learning_available() -> bool:
	return learning_audio!=null and learning_audio.available()

func can_speak(text: String) -> bool:
	return learning_audio!=null and learning_audio.can_speak(text)

func register_voice(voice: Node) -> void:
	if not voices.has(voice):
		voices.append(voice)

func try_acquire(voice: Node, priority: int) -> bool:
	if _shutdown or volume<=0.0 or _tts_active or DisplayServer.tts_is_speaking() or _clock<_available_at:
		delayed += 1
		return false
	if is_instance_valid(current_voice):
		return current_voice==voice
	current_voice = null
	# A higher-priority queued phrase gets the first free slot, regardless of
	# the order in which the male and female child nodes receive their frames.
	for other in voices:
		if not is_instance_valid(other) or other==voice or not other.enabled or other.paused or other.voice_active or other.volume<=0.0:
			continue
		if not other.queue.is_empty():
			var next: Dictionary = other.queue[0]
			if float(next.expiresAt)>float(other._clock) and int(next.priority)>priority:
				delayed += 1
				return false
	current_voice = voice
	grants += 1
	return true

func release(voice: Node) -> void:
	if current_voice!=voice:
		return
	current_voice = null
	_available_at = _clock+PHRASE_GAP

func reserve_tts() -> int:
	_tts_id += 1
	_tts_active = true
	_tts_age = 0.0
	_tts_observed = false
	tts_requests += 1
	# Set the reservation before stopping a recording: finished signals must
	# not hand the just-freed slot to the other announcer during this dispatch.
	for voice in voices:
		if is_instance_valid(voice):
			voice.set_voice_active(true)
	return _tts_id

func speak(text: String, system_voice: String = "", interrupt_recordings: bool = true) -> bool:
	if _shutdown or volume<=0.0 or text.strip_edges().is_empty():
		return false
	if not can_speak(text) and system_voice.is_empty():
		learning_unavailable.emit(text,"이 문장의 일본어 읽기 음성을 사용할 수 없습니다.")
		return false
	if not interrupt_recordings and (is_voice_active() or is_instance_valid(current_voice) or _recordings_waiting() or _clock<_available_at):
		# Only the currently visible automatic reading is useful. Replace an older
		# waiting word, and never read it after its caption has become stale.
		_pending_learning = {"text":text,"voice":system_voice,"expiresAt":_clock+5.0}
		return true
	_dispatch_tts(text,system_voice)
	return true

func _dispatch_tts(text: String, system_voice: String) -> void:
	_pending_learning.clear()
	_finish_speech(true)
	_speech_text = text
	var utterance_id: int = reserve_tts()
	DisplayServer.tts_stop()
	if learning_audio!=null: learning_audio.stop()
	_cached_active = false
	_scheduled_tts = {"id":utterance_id,"text":text,"voice":system_voice,"at":maxf(_clock,_available_at)}
	_start_scheduled_tts()

func _start_scheduled_tts() -> void:
	if _scheduled_tts.is_empty() or _clock<float(_scheduled_tts.at):
		return
	var utterance: Dictionary = _scheduled_tts
	_scheduled_tts = {}
	_tts_age = 0.0
	if can_speak(str(utterance.text)):
		_cached_active = learning_audio.play_text(str(utterance.text))
		_tts_observed = _cached_active
		if _cached_active:
			_start_speech(true)
		else:
			_end_tts()
		return
	if str(utterance.voice).is_empty():
		learning_unavailable.emit(str(utterance.text),"학습 음성 파일을 재생할 수 없습니다.")
		_end_tts()
		return
	DisplayServer.tts_speak(str(utterance.text),str(utterance.voice),clampi(roundi(volume*100.0),1,100),1.0,0.88,int(utterance.id))

func _on_cached_finished() -> void:
	if _cached_active:
		_cached_active = false
		_end_tts()

func _recordings_waiting() -> bool:
	for voice in voices:
		if not is_instance_valid(voice) or not voice.enabled or voice.paused or voice.volume<=0.0:
			continue
		for phrase in voice.queue:
			if float(phrase.expiresAt)>float(voice._clock):
				return true
	return false

func _on_tts_started(utterance_id: int) -> void:
	if utterance_id==_tts_id:
		if not _tts_active:
			_tts_active = true
			for voice in voices:
				if is_instance_valid(voice): voice.set_voice_active(true)
		_tts_observed = true
		_start_speech(false)

func _start_speech(cached: bool) -> void:
	if _speech_started or _speech_text.is_empty(): return
	_speech_started = true
	speech_started.emit(_speech_text,cached)

func _finish_speech(interrupted: bool) -> void:
	if _speech_text.is_empty(): return
	var text: String = _speech_text
	_speech_text = ""
	_speech_started = false
	speech_finished.emit(text,interrupted)

func _on_tts_ended(utterance_id: int) -> void:
	if _tts_active and utterance_id==_tts_id:
		_end_tts()

func _end_tts() -> void:
	_finish_speech(false)
	_scheduled_tts.clear()
	_cached_active = false
	_tts_active = false
	_tts_observed = false
	_available_at = _clock+PHRASE_GAP
	for voice in voices:
		if is_instance_valid(voice):
			voice.set_voice_active(false)

func _process(delta: float) -> void:
	if _shutdown or not is_finite(delta) or delta<0.0:
		return
	_clock += delta
	_start_scheduled_tts()
	# Also protect against an unusually late OS start or speech from another
	# in-app accessibility callback, after the initial dispatch reservation.
	if not _tts_active and DisplayServer.tts_is_speaking():
		_tts_active = true
		_tts_observed = true
		for voice in voices:
			if is_instance_valid(voice): voice.set_voice_active(true)
	if _tts_active:
		_tts_age += delta
		if _cached_active and learning_audio!=null and learning_audio.is_speaking():
			_tts_observed = true
		elif DisplayServer.tts_is_speaking():
			_tts_observed = true
		elif _scheduled_tts.is_empty() and _tts_observed:
			# Some OS voices omit completion callbacks. Keep the reservation during
			# their initial dispatch, then release only after observed completion.
			_end_tts()
		elif _scheduled_tts.is_empty() and _tts_age>=TTS_START_TIMEOUT:
			# Cancel a failed pending start before reopening the recording slot.
			# Releasing it alone could let a late OS utterance overlap an announcer.
			failed_tts_starts += 1
			_tts_id += 1
			DisplayServer.tts_stop()
			_end_tts()
	if not _pending_learning.is_empty():
		if float(_pending_learning.expiresAt)<=_clock:
			_pending_learning.clear()
		elif not is_voice_active() and not is_instance_valid(current_voice) and not _recordings_waiting() and _clock>=_available_at:
			_dispatch_tts(str(_pending_learning.text),str(_pending_learning.voice))

func is_tts_active() -> bool:
	return _tts_active or _cached_active or DisplayServer.tts_is_speaking()

func is_voice_active() -> bool:
	return is_tts_active() or (is_instance_valid(current_voice) and current_voice.is_speaking())

func stop() -> void:
	# Block starts while clearing every player's active phrase and waiting queue.
	_tts_active = true
	_tts_id += 1
	_pending_learning.clear()
	_scheduled_tts.clear()
	_finish_speech(true)
	_cached_active = false
	if learning_audio!=null: learning_audio.stop()
	DisplayServer.tts_stop()
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
	current_voice = null
	_tts_active = false
	_tts_observed = false
	_available_at = _clock+PHRASE_GAP
	for voice in voices:
		if is_instance_valid(voice):
			voice.set_voice_active(false)

func shutdown() -> void:
	if _shutdown:
		return
	stop()
	_shutdown = true
	if learning_audio!=null: learning_audio.shutdown()
	if _ready_for_speech:
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED,Callable())
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED,Callable())
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED,Callable())
	set_process(false)

func _exit_tree() -> void:
	shutdown()

func diagnostics() -> Dictionary:
	var active: int = 1 if is_tts_active() else 0
	var channels: Array[String] = []
	for voice in voices:
		if is_instance_valid(voice) and voice.is_speaking():
			active += 1
			channels.append(str(voice.voice_channel))
	return {"activeVoices":active,"recordingChannels":channels,"ttsReserved":_tts_active,"ttsObserved":_tts_observed,"ttsId":_tts_id,"failedTtsStarts":failed_tts_starts,"pendingLearning":not _pending_learning.is_empty(),"scheduledTts":not _scheduled_tts.is_empty(),"grants":grants,"delayed":delayed,"ttsRequests":tts_requests,"registered":voices.size(),"volume":volume,"ttsVolume":roundi(volume*100.0),"masterVolume":master_volume,"voiceVolume":voice_volume,"cachedActive":_cached_active,"learning":learning_audio.diagnostics() if learning_audio!=null else {},"shutdown":_shutdown}
