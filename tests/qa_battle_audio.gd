extends SceneTree
## PCM evidence, real player/mixer output, semantic event coverage, loudness
## boundaries, pause/UI separation, bounded overlap and teardown. No game save.
const BattleAudio = preload("res://native/battle_audio.gd")
const Battle = preload("res://native/game.gd")
var checks := 0
var failures: Array[String] = []
var pcm_results: Array = []
var real_events: Array = []
var captured_rms := 0.0
var capture_frames := 0
var click_rms := 0.0
var profile := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func wait_audio(seconds: float = .12) -> void:
	await create_timer(seconds).timeout

func source_pcm(library: Dictionary) -> void:
	var sources: Dictionary = {}
	for source in library.sources:
		sources[str(source.id)] = source
		check(not str(source.author).is_empty(),"SFX author recorded: "+str(source.id))
		check(not str(source.source).is_empty(),"SFX original source recorded: "+str(source.id))
		check(not str(source.license).is_empty(),"SFX license recorded: "+str(source.id))
	check(sources.size()==5 and sources.has("xinematix-taiko-491278") and not sources.has("project-percussion") and bool(library.get("recordedOnly",false)),"Five licensed source families include external taiko and exclude generated percussion")
	check(str(sources.get("brandon-song-adventurer",{}).get("author",""))=="Brandon Song (wolfwoot)","Real human voice performer credited by the requested name")
	var gun: Dictionary = sources.get("vincent-sevedge-gunshots",{})
	check(str(gun.get("license",""))=="CC BY 3.0" and str(gun.get("copyright",""))=="Copyright (c) 2009 Vincent Sevedge","Included original gunshot license and author retained conservatively")
	check(str(gun.get("licenseNote","")).contains("CC0") and str(gun.get("licenseNote","")).contains("CC BY 3.0"),"Source/archive license disagreement is disclosed")
	var hashes: Dictionary = {}
	var clip_ids: Dictionary = {}
	check(library.clips.size()==31,"31 short effects use licensed source audio")
	for clip in library.clips:
		var label := str(clip.id)
		check(not clip_ids.has(label),"Effect IDs unique: "+label)
		clip_ids[label] = true
		check(not hashes.has(str(clip.sha256)),"Different effect files have unique SHA256: "+label)
		hashes[str(clip.sha256)] = true
		for source_id in clip.sourceIds:
			check(sources.has(str(source_id)),"Effect references a real licensed source: "+label)
		check(not str(clip.changes).is_empty(),"Changes to source disclosed: "+label)
		check(clip.originalFiles.size()>0,"Every effect has a real recorded original, including UI and outcomes: "+label)
		var stream: AudioStreamWAV = load(str(clip.path)) if ResourceLoader.exists(str(clip.path)) else AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(str(clip.path)),{"compress/mode":0})
		check(stream is AudioStreamWAV,"Effect actually loads PCM WAV: "+label)
		if stream == null: continue
		check(stream.format==AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate==44100,"16-bit mono 44.1kHz actual audio format: "+label)
		check(stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"No endlessly looping effect: "+label)
		var bytes := stream.data
		var samples := bytes.size()/2
		var sum_squared := 0.0
		var peak := 0.0
		var dc := 0.0
		var nonzero := 0
		var clipped := 0
		for offset in range(0,bytes.size()-1,2):
			var value := float(bytes.decode_s16(offset))/32768.0
			sum_squared += value*value
			dc += value
			peak = maxf(peak,absf(value))
			if value != 0: nonzero += 1
			if absf(value) >= .999: clipped += 1
		var rms := sqrt(sum_squared/maxi(1,samples))
		check(samples>1700 and rms>.005 and nonzero>samples/4,"Effect is actual nonzero PCM, not a silent placeholder: "+label)
		check(peak<.8 and clipped==0,"Mastered PCM has headroom and no clipped samples: "+label)
		check(absf(dc/maxi(1,samples))<.015,"No large DC offset: "+label)
		check(absf(float(bytes.decode_s16(0))/32768.0)<.0001 and absf(float(bytes.decode_s16(bytes.size()-2))/32768.0)<.0001,"Click-free start and tail: "+label)
		check(absf(stream.get_length()-float(clip.seconds))<.001,"Manifest duration is the real recording: "+label)
		check(stream.get_length()<(2.01 if label=="taiko_march" else 1.2),"UI/battle effects remain bounded, including the two-second march clip: "+label)
		pcm_results.append({"id":label,"samples":samples,"rms":rms,"peak":peak,"seconds":stream.get_length(),"nonzero":nonzero,"clipped":clipped})
	for path in library.licenseFiles:
		check(FileAccess.file_exists(str(path)) and FileAccess.get_file_as_string(str(path)).length()>80,"Actual shipped source notice/legal text readable: "+str(path))

func semantic_events(audio: Node) -> void:
	var fixtures := [
		[{"type":"recruited","action":"recruit","actorId":1},"recruit"],
		[{"type":"placed","action":"deploy","position":{"x":.2,"y":.4}},"deploy"],
		[{"type":"shot","weapon":"bow","unitType":"archer"},"bow"],
		[{"type":"shot","weapon":"matchlock","unitType":"gunner"},"matchlock"],
		[{"type":"shot","weapon":"katana","unitType":"samurai"},"swing"],
		[{"type":"shot","weapon":"spear","unitType":"spear"},"swing"],
		[{"type":"shot","weapon":"naginata","unitType":"naginata"},"swing"],
		[{"type":"shot","weapon":"staff","unitType":"monk"},"swing"],
		[{"type":"shot","weapon":"dagger","unitType":"ninja"},"swing"],
		[{"type":"shot","weapon":"katana","unitType":"commander","side":"enemy"},"swing"],
		[{"type":"hit","weapon":"spear","damage":12},"wood"],
		[{"type":"hit","weapon":"staff","damage":12},"wood"],
		[{"type":"hit","weapon":"katana","damage":12},"metal"],
		[{"type":"hit","weapon":"bow","enemyKind":"heavy","damage":12},"metal"],
		[{"type":"hit","weapon":"bow","victimType":"shield","damage":12},"metal"],
		[{"type":"hit","weapon":"dagger","damage":12},"body"],
		[{"type":"charge_impact","weapon":"charge","damage":20},"charge"],
		[{"type":"footstep","unitType":"spear"},"footstep"],
		[{"type":"footstep","unitType":"commander"},"hoof"],
		[{"type":"footstep","unitType":"commander","side":"enemy"},"footstep"],
		[{"type":"killed","victimSide":"enemy"},"kill"],
		[{"type":"killed","victimSide":"friendly"},"ally_down"],
		[{"type":"objective_hit","damage":7},"objective"],
		[{"type":"wave","action":"wavebegin","wave":1},"wavebegin"],
		[{"type":"waveend"},"waveend"],
		[{"type":"victory","mapId":"fixture","battleId":1},"victory"],
		[{"type":"defeat","mapId":"fixture","battleId":2},"defeat"],
		[{"type":"learning-support","supportKind":"march_drum"},"support_drum"],
		[{"type":"ui_click"},"click"],
	]
	for fixture in fixtures:
		audio.stop_all()
		var count_before: int = audio.played
		check(audio.consume_event(fixture[0]),"Observable semantic event accepted: "+str(fixture[1]))
		await physics_frame
		var state: Dictionary = audio.diagnostics()
		check(state.lastEffect==fixture[1] and int(state.played)==count_before+1,"One event produces one correct effect: "+str(fixture[1]))
		var player = audio.players[0]
		# A 85ms wooden UI click can already finish inside an audio mixer quantum
		# before physics_frame resumes. Its actual nonzero output is captured
		# separately below; longer combat clips must remain visibly playing.
		check(int(state.activePlayers)==1 or (fixture[1]=="click" and player.has_stream_playback()),"A real AudioStreamPlayer2D plays the correct clip: "+str(fixture[1]))
		check(player.stream is AudioStreamWAV and player.has_stream_playback(),"Actual playback exists, not just a counter")
		check(player.volume_db<=-6 and player.pitch_scale>=.96 and player.pitch_scale<=1.04,"Conservative gain and tiny pitch variation")
	for event in [{"type":"hit","damage":0},{"type":"hit","damage":5,"weapon":"charge"},{"type":"charge_impact","damage":0},{"type":"shot","weapon":"charge","unitType":"commander"},{"type":"gold"},{"type":"unrelated"}]:
		audio.stop_all()
		check(not audio.consume_event(event) and audio.diagnostics().activePlayers==0,"Miss/failure/already supplied charge never produces a false effect: "+str(event.type))

func pause_overlap_duck(audio: Node) -> void:
	audio.stop_all()
	audio.set_field_rect(Rect2(16,64,1248,636))
	check(audio.consume_event({"type":"shot","weapon":"bow","position":{"x":0,"y":.2}}),"Left field bow shot starts")
	check(Vector2(audio.diagnostics().lastPosition).distance_to(Vector2(16,191.2))<.001,"Normalized position gives correct real left-field source")
	await physics_frame
	audio.set_paused(true)
	check(audio.players[0].stream_paused,"Pause actually pauses the live battle playback")
	check(not audio.consume_event({"type":"shot","weapon":"bow","actorId":99}),"No new combat audio during pause")
	check(audio.consume_event({"type":"placed","action":"deploy"}),"Real placement still gives feedback while battle paused")
	await physics_frame
	check(audio.players[1].playing and not audio.players[1].stream_paused,"Paused UI playback remains real and unpaused")
	audio.set_paused(false)
	check(not audio.players[0].stream_paused,"Resume unpauses existing battle playback")
	audio.stop_all()
	var right := {"type":"hit","damage":5,"weapon":"katana","position":{"x":1,"y":1},"eventId":"right-hit"}
	check(audio.consume_event(right),"Right-field real metal hit accepted")
	check(audio.diagnostics().lastPosition==Vector2(1264,700),"Right-field panning position follows actual normalized geometry")
	var before: int = audio.played
	check(not audio.consume_event(right) and audio.played==before,"Duplicate eventId does not play again")
	check(not audio.consume_event({"type":"hit","damage":5,"weapon":"katana","actorId":22}),"Same-frame repeated impacts are bounded")
	audio.stop_all()
	audio.set_voice_active(true)
	await wait_audio(.18)
	check(audio.diagnostics().duckDb<=-9.9,"Japanese speech lowers the SFX bus by ten dB")
	var ducked: float = audio.diagnostics().busDb
	audio.set_voice_active(false)
	await wait_audio(.5)
	check(audio.diagnostics().duckDb>-.1 and audio.diagnostics().busDb>ducked+9,"Speech completion restores effect gain smoothly")
	audio.set_volume(0)
	check(AudioServer.is_bus_mute(audio.bus_index) and not audio.consume_event({"type":"recruited"}),"Zero SFX volume actually mutes and suppresses playback")
	audio.set_volume(.8)
	audio.consume_event({"type":"recruited"})
	await physics_frame
	audio.set_enabled(false)
	check(AudioServer.is_bus_mute(audio.bus_index) and audio.diagnostics().activePlayers==0,"Effects OFF stops live sounds and mutes its own bus")
	check(not audio.consume_event({"type":"victory"}),"Mute suppresses even outcome feedback")
	audio.set_enabled(true)
	check(audio.consume_event({"type":"victory","mapId":"dedupe","battleId":8}),"Victory plays when re-enabled")
	await wait_audio(1.05)
	check(not audio.consume_event({"type":"victory","mapId":"dedupe","battleId":8}),"Duplicate terminal event remains blocked even after cooldown")
	audio.stop_all()
	for index in 80:
		audio._process(.051)
		audio.consume_event({"type":"hit","weapon":"spear","damage":5,"actorId":index})
		await physics_frame
		check(audio.diagnostics().activePlayers<=12,"Heavy impact burst never exceeds twelve live players")
		var wood_count := 0
		for slot in audio.diagnostics().playingClips:
			if str(slot.effect)=="wood": wood_count+=1
		check(wood_count<=3,"Three or fewer overlapping instances of the same impact")
	check(audio.consume_event({"type":"recruited","actorId":1000}),"Recruit feedback retains priority under a battle burst")
	audio.stop_all()

func mixer_pcm(audio: Node) -> void:
	var capture := AudioEffectCapture.new()
	capture.buffer_length = .5
	AudioServer.add_bus_effect(audio.bus_index,capture)
	audio.consume_event({"type":"objective_hit","damage":4,"position":{"x":.5,"y":.5}})
	await wait_audio(.22)
	capture_frames = capture.get_frames_available()
	var buffer := capture.get_buffer(capture_frames)
	var squared := 0.0
	for sample in buffer: squared += sample.length_squared()
	captured_rms = sqrt(squared/maxi(1,buffer.size()*2))
	check(capture_frames>1000 and captured_rms>.0001,"The actual AudioServer SFX bus mixed nonzero PCM")
	audio.stop_all()
	capture.clear_buffer()
	audio.consume_event({"type":"ui_click"})
	await wait_audio(.14)
	var click_buffer := capture.get_buffer(capture.get_frames_available())
	var click_squared := 0.0
	for sample in click_buffer: click_squared += sample.length_squared()
	click_rms = sqrt(click_squared/maxi(1,click_buffer.size()*2))
	check(click_buffer.size()>1000 and click_rms>.0001,"The short wooden UI click actually reaches the audio mixer")
	AudioServer.remove_bus_effect(audio.bus_index,1)
	audio.stop_all()

func human_reactions(audio: Node) -> void:
	audio.stop_all()
	audio.set_voice_active(false)
	var before: int = audio.diagnostics().humanReactions
	for index in 5:
		audio._process(.2)
		check(audio.consume_event({"type":"hit","weapon":"bow","damage":20,"actorId":index,"position":{"x":.5,"y":.5}}),"Eligible actual hit keeps its main impact")
		await wait_audio(.16)
		if index<4: check(audio.diagnostics().humanReactions==before,"Human pain reactions are not repeated on every hit")
	check(audio.diagnostics().humanReactions==before+1,"Every fifth eligible impact may supply one real recorded human reaction")
	var voice_slots := 0
	for slot in audio.diagnostics().playingClips:
		if str(slot.effect) in ["pain_voice","death_voice"]: voice_slots+=1
	check(voice_slots==1,"Exactly one genuine vocal playback is present")
	for index in 3:
		audio._process(.12)
		audio.consume_event({"type":"killed","victimSide":"enemy","actorId":100+index})
		await wait_audio(.11)
	check(audio.diagnostics().humanReactions==before+1,"Death reactions respect the same 1.4-second global voice cooldown")
	audio.stop_all()
	audio._process(2)
	before = audio.diagnostics().humanReactions
	for index in 3:
		audio._process(.2)
		check(audio.consume_event({"type":"killed","victimSide":"enemy","actorId":200+index}),"Actual death keeps its recorded landing effect")
		await wait_audio(.16)
	check(audio.diagnostics().humanReactions==before+1,"Occasional real death reaction uses the human performance source")
	audio.stop_all()
	audio.set_voice_active(true)
	before = audio.diagnostics().humanReactions
	for index in 5:
		audio._process(.2)
		audio.consume_event({"type":"hit","weapon":"bow","damage":20,"actorId":300+index})
		await wait_audio(.16)
	check(audio.diagnostics().humanReactions==before,"Educational Japanese speech prevents competing human battle grunts")
	audio.set_voice_active(false)
	audio.stop_all()

func observe_game_event(event: Dictionary, audio: Node) -> void:
	var accepted: bool = audio.consume_event(event)
	if str(event.get("action","")) in ["recruit","deploy","shot","hit","killed","charge_impact","objective_hit","wavebegin","waveend","victory","defeat","footstep"]:
		real_events.append({"action":event.get("action",""),"unitType":event.get("unitType",""),"weapon":event.get("weapon",""),"damage":event.get("damage",0),"accepted":accepted})

func real_battle_events(audio: Node) -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var ids: Array = []
	for unit in catalog: ids.append(str(unit.id))
	for type_name in ids:
		var game = Battle.new()
		root.add_child(game)
		game.set_process(false)
		game.load_map(maps[0])
		game.configure_roster(catalog,ids,{type_name:1})
		game.gold=5000
		audio.stop_all()
		game.game_event.connect(observe_game_event.bind(audio))
		var begin := real_events.size()
		if game.ground_combat.is_marching(type_name):
			check(game.begin_placement(type_name,0),"Actual forward class production: "+type_name)
			game.start_battle()
			game.spawn_queue=["raider"];game.spawn_clock=100000.0
			for tick in range(250):
				if not game.units.is_empty(): break
				game.advance_simulation(.025)
		else:
			check(game.recruit(type_name),"Actual class recruitment: "+type_name)
			audio._process(.12)
			game._refresh_placement_hints()
			var deployed := false
			for point in game.placement_hints:
				if game.place_unit(point.x,point.y): deployed=true;break
			check(deployed,"Actual typed legal deployment: "+type_name)
			game.start_battle()
			game.spawn_queue=["raider"];game.spawn_clock=100000.0
			for tick in range(250):
				if not game.units.is_empty(): break
				game.advance_simulation(.025)
			var feedback: int=0
			for index in range(begin,real_events.size()):
				if real_events[index].action in ["recruit","deploy"] and bool(real_events[index].accepted): feedback+=1
			check(feedback>=1,"Actual completed production produces deployment feedback")
		check(not game.units.is_empty(),"Actual class deployment completes: "+type_name)
		if game.units.is_empty(): game.free();continue
		game.start_battle()
		game.spawn_queue.clear()
		game.enemies.clear()
		game._spawn_enemy("shield")
		var unit: Dictionary = game.units[0]
		var target: Dictionary = game.enemies[0]
		target.position=unit.position+Vector2(.015,0)
		target.pathIndex=unit.get("postPathIndex",0)
		target.hp=1000.0
		target.maxHp=1000.0
		unit["deploying"]=false
		if unit.has("combatState"):
			unit["combatState"]="guard"
		audio._process(.15)
		var before := real_events.size()
		if type_name=="monk":
			game._release_unit_attack(unit,{"targetId":target.id,"damage":100.0})
			check(real_events.size()==before and target.hp==1000.0,"Healing monk emits no unapproved attack sound or damage")
			game.free();audio.stop_all();continue
		var plan: Dictionary=game.unit_skills.prepare_attack(unit,target,100.0,.1)
		plan.charge=type_name=="commander"
		game._release_unit_attack(unit,plan)
		for tick in range(30): game._update_projectiles(.025)
		var shots := 0
		var hits := 0
		var charges := 0
		for index in range(before,real_events.size()):
			var event: Dictionary = real_events[index]
			if event.action=="shot":
				shots+=1
				check(event.unitType==type_name and (event.accepted if type_name!="commander" else not event.accepted),"Actual weapon release maps to correct class feedback: "+type_name)
			elif event.action=="hit":
				hits+=1
				check(float(event.damage)>0,"Actual hit feedback reflects real HP loss")
			elif event.action=="charge_impact":
				charges+=1
				check(event.accepted and float(event.damage)>0,"Commander actual collision produces charge feedback once")
		check(shots==1,"One actual release event per class attack: "+type_name)
		check(hits>=1 and target.hp<1000,"Real attack deals damage and supplies hit audio event: "+type_name)
		if type_name=="commander": check(charges==1,"Commander impact, not windup, supplies one audible charge")
		game.free()
		audio.stop_all()
		await process_frame

func run() -> void:
	profile=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("").to_lower()+"/"):
		push_error("Use an isolated workspace APPDATA profile")
		quit(2)
		return
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/sfx_sources.json"))
	source_pcm(library)
	var buses_before := AudioServer.bus_count
	var audio = BattleAudio.new()
	root.add_child(audio)
	check(audio.setup(),"Real SFX player/bus setup loads every licensed clip")
	check(audio.setup() and audio.players.size()==12 and AudioServer.bus_count==buses_before+1,"Repeated setup cannot duplicate pool or audio buses")
	check(audio.streams.size()==library.clips.size() and audio.missing.is_empty(),"No missing placeholder or wrong fallback")
	await semantic_events(audio)
	await pause_overlap_duck(audio)
	await mixer_pcm(audio)
	await human_reactions(audio)
	await real_battle_events(audio)
	var before_shutdown: Dictionary = audio.diagnostics()
	audio.consume_event({"type":"recruited"})
	await physics_frame
	var playback = weakref(audio.players[0].get_stream_playback())
	audio.shutdown()
	check(audio.streams.is_empty() and audio.diagnostics().activePlayers==0,"Shutdown stops players and releases cached PCM resources")
	check(not audio.consume_event({"type":"recruited"}) and not audio.setup(),"Closed audio node cannot restart after shutdown")
	await wait_audio(.5)
	audio.queue_free()
	await process_frame
	await process_frame
	check(AudioServer.bus_count==buses_before,"Teardown removes only its owned bus, without leaving bus leaks")
	check(playback.get_ref()==null,"Mixer playback has actually been released after stop/teardown")
	var report := {"checks":checks,"failures":failures,"clips":pcm_results,"realEvents":real_events,"mixerCaptureFrames":capture_frames,"mixerRms":captured_rms,"clickMixerRms":click_rms,"beforeShutdown":before_shutdown,"profile":profile,"resourceRoot":ProjectSettings.globalize_path("res://"),"limits":"PCM/mixer and event/path tests establish nonzero output, timing contract and safe teardown. Human listening, device volume and final mix perception require actual native app listening; this headless run does not claim a recorded musket or human voice."}
	var file := FileAccess.open("user://qa_battle_audio.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("BATTLE_AUDIO_QA ",JSON.stringify({"checks":checks,"failures":failures,"clips":pcm_results.size(),"realEvents":real_events.size(),"captureFrames":capture_frames,"mixerRms":captured_rms,"clickMixerRms":click_rms}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
