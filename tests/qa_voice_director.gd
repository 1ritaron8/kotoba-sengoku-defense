extends SceneTree
## Observe real recorded-player handoffs. OS TTS callbacks use explicit fixtures
## because this machine has no Japanese system reading voice.
const Director = preload("res://native/voice_director.gd")
const Male = preload("res://native/battle_narrator.gd")
const Female = preload("res://native/battle_announcer.gd")
const Effects = preload("res://native/battle_audio.gd")
var director: Node
var male: Node
var female: Node
var effects: Node
var checks: int = 0
var failures: Array = []
var samples: Array = []
var starts: Array = []
var finishes: Array = []
var context: String = ""
var maximum_players: int = 0

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures.append(context+" / "+note)
		if failures.size()<=20: push_error("VOICE_DIRECTOR "+str(failures.back()))

func observe() -> void:
	var active: int = int(male.is_speaking())+int(female.is_speaking())
	maximum_players = maxi(maximum_players,active)
	check(active<=1,"At most one actual recorded player is speaking")
	if director.is_tts_active(): check(active==0,"TTS reservation blocks both actual recording players")
	if samples.size()<100:
		samples.append({"case":context,"at":Time.get_ticks_usec(),"activePlayers":active,"director":director.diagnostics(),"male":str(male.current_caption().get("id","")),"female":str(female.current_caption().get("id",""))})

func wait_seconds(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		await process_frame
		observe()

func wait_all_silent(timeout: float = 8.0) -> void:
	var deadline: int = Time.get_ticks_msec()+int(timeout*1000)
	while (not male.current.is_empty() or not female.current.is_empty() or not male.queue.is_empty() or not female.queue.is_empty()) and Time.get_ticks_msec()<deadline:
		await process_frame
		observe()
	check(male.current.is_empty() and female.current.is_empty() and male.queue.is_empty() and female.queue.is_empty(),"Actual finished signals drain both queues")

func wait_current(voice: Node, id: String, timeout: float = 2.0) -> void:
	var deadline: int = Time.get_ticks_msec()+int(timeout*1000)
	while str(voice.current_caption().get("id",""))!=id and Time.get_ticks_msec()<deadline:
		await process_frame
		observe()
	check(str(voice.current_caption().get("id",""))==id and voice.is_speaking(),"Actual stream starts "+id)

func stop_and_settle() -> void:
	director.stop()
	await wait_seconds(.23)
	check(not director.is_voice_active() and director._pending_learning.is_empty() and director._scheduled_tts.is_empty(),"Stop clears every voice and deferred reading")

func run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/").to_lower()):
		push_error("Voice QA needs an isolated workspace profile")
		quit(1)
		return
	director = Director.new()
	root.add_child(director)
	director.setup()
	# Process female first to expose child-order priority mistakes.
	female = Female.new()
	root.add_child(female)
	female.bind_director(director,"female")
	male = Male.new()
	root.add_child(male)
	male.bind_director(director,"male")
	context = "setup"
	check(female.setup() and male.setup(),"Both original recording libraries decode")
	check(female.streams.size()==8 and male.streams.size()==14,"Eight female and fourteen male clips remain available")
	for voice in [female,male]:
		voice.clip_started.connect(func(caption: Dictionary): starts.append({"channel":voice.voice_channel,"clip":caption.id,"at":Time.get_ticks_usec()}))
		voice.clip_finished.connect(func(caption: Dictionary): finishes.append({"channel":voice.voice_channel,"clip":caption.id,"interrupted":caption.interrupted,"at":Time.get_ticks_usec()}))
	context = "natural male then female"
	check(male.enqueue("battle_start",{"eventId":"start:1"}),"Male sortie is accepted")
	check(female.enqueue("message_received",{"eventId":"report:1"}),"Female report queues behind it")
	check(male.is_speaking() and not female.is_speaking() and female.queue.size()==1,"Second voice cannot start in the same dispatch frame")
	await wait_all_silent()
	check(starts.size()==2 and str(starts[0].channel)=="male" and str(starts[1].channel)=="female","Both original phrases finish in order")
	check(int(starts[1].at)-int(finishes[0].at)>=150000,"A phrase gap separates the two actual players")
	await stop_and_settle()
	context = "cross-channel priority and pending TTS"
	var reservation: int = director.reserve_tts()
	check(female.enqueue("hint",{"eventId":"hint:1"}) and male.enqueue("danger",{"eventId":"danger:1"}),"Two priorities wait behind learning speech")
	await wait_seconds(.25)
	check(director.is_tts_active() and not male.is_speaking() and not female.is_speaking(),"Missing OS start does not release the reserved slot on the next frame")
	director._on_tts_ended(reservation)
	await wait_current(male,"danger")
	check(not female.is_speaking() and female.queue.size()==1,"Higher male priority wins despite female-first process order")
	await wait_all_silent()
	await stop_and_settle()
	context = "recording interrupted by requested learning"
	check(female.enqueue("correct",{"eventId":"correct:1"}),"Correct-answer original recording accepted")
	await wait_current(female,"correct")
	var interruptions: int = female.tts_interrupted
	reservation = director.reserve_tts()
	check(not female.is_speaking() and female.tts_interrupted==interruptions+1,"TTS reservation synchronously stops the actual current female phrase")
	check(male.voice_active and female.voice_active,"Both registered voices respect the reservation")
	await wait_seconds(.20)
	var newer: int = director.reserve_tts()
	director._on_tts_started(newer)
	director._on_tts_ended(reservation)
	check(director.is_tts_active() and director._tts_id==newer,"A delayed cancellation from the old utterance cannot release a new one")
	director._on_tts_ended(newer)
	check(not director.is_tts_active() and not male.voice_active and not female.voice_active,"Matching completion releases both channels")
	await stop_and_settle()
	context = "failed OS start is canceled before release"
	reservation = director.reserve_tts()
	var canceled_starts: int = director.failed_tts_starts
	director._process(2.1)
	check(not director.is_tts_active() and director.failed_tts_starts==canceled_starts+1 and director._tts_id!=reservation,"Timeout cancels pending OS speech and invalidates its old callback ID")
	director._on_tts_started(reservation)
	check(not director.is_tts_active(),"A timed-out old start cannot revive a canceled utterance")
	await stop_and_settle()
	context = "canceled reading cannot dispatch later"
	check(female.play("correct",{"eventId":"cancel-before-dispatch"}),"Actual recorded phrase precedes the reading cancellation")
	await wait_current(female,"correct")
	check(director.speak("山","qa-no-system-voice"),"Requested reading reserves its audio gap")
	check(not director._scheduled_tts.is_empty(),"Interrupted recording leaves a real scheduled dispatch")
	reservation = director._tts_id
	director._on_tts_ended(reservation)
	check(director._scheduled_tts.is_empty() and not director.is_tts_active(),"Matching completion or cancellation removes the undispatched reading")
	await wait_seconds(.24)
	check(not director.is_tts_active() and director._scheduled_tts.is_empty(),"Canceled delayed dispatch cannot reopen or synthesize a phantom reading")
	await stop_and_settle()
	context = "automatic reading does not clip a real guide"
	check(female.enqueue("answer_select",{"eventId":"select:1"}),"Selection guidance is accepted")
	await wait_current(female,"answer_select")
	var reading_before: int = director.tts_requests
	check(director.speak("山","qa-no-system-voice",false),"Automatic visible reading can wait")
	check(director.speak("川","qa-no-system-voice",false),"New visible word replaces a stale waiting reading")
	check(str(director._pending_learning.get("text",""))=="川" and not director.is_tts_active() and female.is_speaking(),"Latest automatic reading waits without interrupting the female recording")
	var deadline: int = Time.get_ticks_msec()+3500
	while director.tts_requests==reading_before and Time.get_ticks_msec()<deadline:
		await process_frame
		observe()
	check(director.tts_requests==reading_before+1 and not female.is_speaking(),"Only one latest reading is dispatched after natural recorded completion")
	check(not bool(finishes.back().interrupted),"Automatic reading preserves the complete guide phrase")
	await stop_and_settle()
	context = "automatic expiry and native recording pause"
	check(female.enqueue("message_received",{"eventId":"report:2"}),"Next report accepted")
	await wait_current(female,"message_received")
	female.set_paused(true)
	check(director.speak("古い表示","qa-no-system-voice",false),"Paused current phrase retains the pending reading")
	director._process(5.1)
	check(director._pending_learning.is_empty() and not director.is_tts_active(),"Old automatic caption expires without dispatch")
	var before: float = female.player.get_playback_position()
	await wait_seconds(.12)
	check(female.player.stream_paused and absf(female.player.get_playback_position()-before)<.04,"Native pause holds the original recording position")
	female.set_paused(false)
	await wait_all_silent()
	await stop_and_settle()
	context = "combat human reaction cannot overlap"
	effects = Effects.new()
	root.add_child(effects)
	check(effects.setup(),"Existing battle effects are available")
	for iteration in range(3): effects._maybe_voice("killed",{"position":{"x":.5,"y":.5}})
	var reaction_players: int = 0
	for slot in effects.slots:
		if str(slot.get("effect","")) in ["pain_voice","death_voice"]: reaction_players += 1
	check(reaction_players==1,"A real combat voice reaction begins before the alert")
	effects.set_voice_active(true)
	reaction_players = 0
	for slot in effects.slots:
		if str(slot.get("effect","")) in ["pain_voice","death_voice"]: reaction_players += 1
	check(reaction_players==0,"Announcement priority stops even a previously active human reaction")
	for iteration in range(6): effects._maybe_voice("killed",{})
	check(effects.diagnostics().humanReactions==1,"New human reactions stay suppressed during guidance")
	effects.shutdown()
	context = "shutdown"
	director.shutdown()
	check(not director.is_voice_active() and not director.speak("山","qa-no-system-voice"),"Shutdown releases the slot and prevents new speech")
	male.shutdown()
	female.shutdown()
	var report: Dictionary = {"checks":checks,"failures":failures,"maximumRecordedPlayers":maximum_players,"starts":starts,"finishes":finishes,"samples":samples,"director":director.diagnostics(),"systemJapaneseVoices":DisplayServer.tts_get_voices_for_language("ja"),"ttsFixture":"Callback and delayed-start contract; no claim of auditory OS Japanese TTS validation."}
	var packed: bool = "--packed" in OS.get_cmdline_user_args()
	var path: String = "user://qa_voice_director_packed.json" if packed else "user://qa_voice_director.json"
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("VOICE_DIRECTOR %d checks / %d failures; max actual recorded voices=%d; report=%s" % [checks,failures.size(),maximum_players,ProjectSettings.globalize_path(path)])
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
