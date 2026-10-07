extends SceneTree
## Actual Main callbacks and AudioStreamPlayer state, isolated saves, no GPU.
## Barracks internal layout/preview is intentionally outside this fixture's scope.
const Store = preload("res://native/progress.gd")
var checks: int = 0
var failures: Array[String] = []
var samples: Array = []
var app: Node
var music_player_id: int = 0
var music_paths: Dictionary = {}
var account_army: String = ""
var account_maps: String = ""
var male_manifest: String = ""
var fixture_save: String = ""

func _initialize() -> void:
	Engine.max_fps=60
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<30: push_error("LOBBY_CONTEXT "+note)

func frames(count: int = 3) -> void:
	for frame in range(count): await process_frame

func fade_finished() -> void:
	await create_timer(.45).timeout
	await frames()
	check(absf(app.music_fade_db)<.02,"0.35 second fade reaches its neutral endpoint")

func music_state(context: String, path: String, playing: bool, volume: float, scope: String) -> void:
	check(app.music_context==context,scope+": music context is "+context)
	check(app.music_resource_path==path,scope+": runtime music resource path is correct")
	check(app.current_music.get("path","")==path,scope+": metadata matches the selected audio")
	check(app.player.stream!=null and app.player.stream.resource_path==path,scope+": actual AudioStream matches metadata")
	check(app.player.playing==playing,scope+": playback honors current music preference")
	check(app.player.get_instance_id()==music_player_id,scope+": all screens use one persistent BGM player")
	check(absf(app.player.volume_db-volume)<.05,scope+": actual BGM mix level is "+str(volume)+"dB")
	var bgm_players: int=0
	for player in app.find_children("*","AudioStreamPlayer",true,false):
		if player.stream!=null and music_paths.has(str(player.stream.resource_path)):
			bgm_players+=1
	check(bgm_players==1,scope+": no second lobby or stage player overlaps")
	check(JSON.stringify(app.progress.data.army)==account_army,scope+": navigation preserves army/currency")
	check(JSON.stringify(app.progress.data.maps)==account_maps,scope+": navigation does not unlock/complete maps")
	samples.append({"scope":scope,"context":app.music_context,"path":app.music_resource_path,"playing":app.player.playing,"volumeDb":app.player.volume_db,"fadeDb":app.music_fade_db,"battleStarted":app.battle_started,"paused":app.game.paused,"inputEnabled":app.game.input_enabled,"voiceCount":app.voice_director.diagnostics().activeVoices})

func battle_signature() -> Dictionary:
	var state: Dictionary=app.game.snapshot()
	return {"map":state.get("mapId",""),"wave":state.get("wave",0),"gold":state.get("gold",0),"hp":state.get("hp",0),"elapsed":state.get("elapsed",0),"remainingSpawns":state.get("remainingSpawns",0),"objectives":state.get("objectives",[]).duplicate(true),"enemies":state.get("enemies",[]).duplicate(true),"units":state.get("units",[]).duplicate(true),"started":app.battle_started,"finished":app.battle_finished,"battleId":app.narration_battle_id}

func female_duck(context: String, path: String, normal_db: float) -> void:
	# A real recorded component event is injected to inspect the Main mixer in
	# each context; this does not imply menu gameplay emits battle announcements.
	app.voice_director.stop()
	app.battle_announcer.reset_battle()
	app.battle_narrator.reset_battle()
	await create_timer(.22).timeout
	check(app.battle_announcer.enqueue("correct",{"eventId":"lobby-mixer-"+context}),context+": actual female recording is accepted")
	await frames(2)
	check(app.battle_announcer.is_speaking(),context+": actual imported female recording starts")
	check(app.voice_director.diagnostics().activeVoices==1,context+": shared voice reservation has exactly one speaker")
	music_state(context,path,true,-27.0,context+" female duck")
	check(not app.battle_narrator.is_speaking(),context+": male narration does not overlap the female clip")
	app.voice_director.stop()
	await frames(2)
	music_state(context,path,true,normal_db,context+" female stop restores mix")
	check(app.voice_director.diagnostics().activeVoices==0,context+": stop releases the shared voice slot")

func cleanup() -> void:
	app.closing=true
	app.set_process(false)
	app.game.set_process(false)
	app.game.paused=true
	app.game.set_input_enabled(false)
	if app.music_fade!=null and app.music_fade.is_valid(): app.music_fade.kill()
	app._stop_narration()
	app.player.stop()
	app.player.stream=null
	app.battle_audio.shutdown()
	app.battle_narrator.shutdown()
	app.battle_announcer.shutdown()
	app.voice_director.shutdown()
	check(not app.player.playing,"teardown stops BGM")
	check(app.battle_narrator.diagnostics().shutdown and app.battle_announcer.diagnostics().shutdown,"teardown shuts down both recorded voice channels")
	await create_timer(.5).timeout
	app.queue_free()
	await frames(3)

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/lobby-ui-context/").to_lower()) or DisplayServer.get_name()!="headless":
		push_error("Refusing a player profile or GPU lobby-context fixture")
		quit(2)
		return
	root.size=Vector2i(1280,800)
	root.content_scale_size=root.size
	var save: RefCounted=Store.new()
	fixture_save="user://lobby-ui-fixture-"+str(Time.get_ticks_usec())+".json"
	save.save_path=fixture_save
	save.data.settings.voice=false
	save.data.settings.effects=false
	save.data.settings.music=true
	account_army=JSON.stringify(save.data.army)
	account_maps=JSON.stringify(save.data.maps)
	male_manifest=FileAccess.get_file_as_string("res://assets/narration/manifest.json")
	var scene: PackedScene=load("res://native/main.tscn")
	check(scene!=null,"actual Main scene loads")
	if scene==null:
		quit(1)
		return
	app=scene.instantiate()
	app.progress=save
	root.add_child(app)
	await frames(3)
	# Freeze only battle simulation while inspecting real navigation/audio timing.
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.unit_training.render_enabled=false
	music_player_id=app.player.get_instance_id()
	var lobby_path: String=str(app.lobby_music.path)
	var stage_path: String=str(app.music_by_stage[str(app.current_map.id)].path)
	music_paths[lobby_path]=true
	var composition_ids: Dictionary={}
	check(app.music_by_stage.size()==40,"Main loads all forty unchanged stage assignments")
	for track in app.music_by_stage.values():
		composition_ids[str(track.compositionId)]=true
		music_paths[str(track.path)]=true
		check(ResourceLoader.exists(str(track.path)),"stage audio is imported: "+str(track.stageId))
		var stream: AudioStream=load(str(track.path))
		check(stream!=null and stream.get_length()>20.0,"actual stage audio decodes: "+str(track.stageId))
	check(composition_ids.size()==40,"all forty stages keep distinct original compositions")
	check(not composition_ids.has(str(app.lobby_music.compositionId)),"new lobby composition does not replace/reuse a stage work")
	check(app.player.stream is AudioStreamOggVorbis and app.player.stream.loop,"Main uses the imported original OGG in loop mode")
	check(absf(app.player.stream.get_length()-float(app.lobby_music.durationSeconds))<.05,"Main imported lobby stream matches original decode duration")
	check(FileAccess.get_sha256(lobby_path)==str(app.lobby_music.sha256),"Main metadata points to the exact official OGG bytes")
	check(app.battle_narrator.streams.size()==14 and app.battle_announcer.streams.size()==8,"existing fourteen male and eight female recordings remain loaded")
	check(not app.battle_narrator.enabled and not app.battle_announcer.enabled,"initial voice-off settings keep both recording channels disabled")
	check(app.front_end.visible and app.front_end.view=="home" and not app.game.input_enabled,"fresh actual app starts at home with field input disabled")
	await fade_finished()
	music_state("lobby",lobby_path,true,-16.0,"home startup")
	app._toggle_voice()
	await frames()
	check(app.progress.data.settings.voice and app.battle_announcer.enabled and app.battle_narrator.enabled,"real voice toggle enables both unchanged recording components")
	await female_duck("lobby",lobby_path,-16.0)
	app._toggle_voice()
	await frames()
	app.front_end.barracks_requested.emit()
	await frames()
	check(app.barracks.visible and not app.front_end.visible,"real home callback opens barracks")
	music_state("lobby",lobby_path,true,-16.0,"barracks")
	app.barracks.training_requested.emit("archer")
	await frames()
	check(app.unit_training.visible and app.unit_training.view=="menu","real barracks callback opens training menu")
	music_state("lobby",lobby_path,true,-16.0,"training menu")
	app.unit_training.close()
	await frames()
	check(app.barracks.visible and not app.unit_training.visible,"training close returns to its barracks caller")
	app.barracks.hide()
	app.barracks.closed.emit()
	await frames()
	check(app.front_end.visible and app.front_end.view=="home","barracks close callback returns home")
	music_state("lobby",lobby_path,true,-16.0,"returned home")
	app._show_catalog()
	await frames()
	check(app.front_end.view=="catalog" and not app.game.input_enabled,"actual catalog keeps field input disabled")
	music_state("lobby",lobby_path,true,-16.0,"catalog")
	app.front_end.stage_chosen.emit(0,0,false)
	await frames()
	check(app.modal!=null and not app.front_end.visible and not app.battle_started,"first unlocked stage opens the actual briefing")
	check(app.music_fade_db<0.0,"new stage stream starts with a fade rather than full-volume overlap")
	await fade_finished()
	music_state("stage",stage_path,true,-16.0,"first-stage briefing")
	app._begin_battle()
	await frames()
	check(app.battle_started and app.modal==null and not app.game.paused and app.game.input_enabled,"actual briefing starts battle and restores field input")
	music_state("battle",stage_path,true,-20.0,"battle")
	var active_game_id: int=app.game.get_instance_id()
	var signature: Dictionary=battle_signature()
	app._show_home()
	await frames()
	check(app.game.paused and app.navigation_resume_battle and not app.game.input_enabled,"home navigation pauses active combat and disables field input")
	check(battle_signature()==signature and app.game.get_instance_id()==active_game_id,"home navigation preserves the exact active battle")
	await fade_finished()
	music_state("lobby",lobby_path,true,-16.0,"home during battle")
	app.front_end.resume_requested.emit()
	await frames()
	check(not app.game.paused and app.game.input_enabled and not app.front_end.visible,"real resume callback restores combat/input")
	check(battle_signature()==signature and app.game.get_instance_id()==active_game_id,"resume preserves combat state rather than reloading")
	await fade_finished()
	music_state("battle",stage_path,true,-20.0,"resumed battle")
	app._toggle_voice()
	await frames()
	await female_duck("battle",stage_path,-20.0)
	app._toggle_voice()
	await frames()
	app._toggle_music()
	await frames()
	check(not app.progress.data.settings.music,"real music toggle saves off preference in the isolated fixture")
	music_state("battle",stage_path,false,-20.0,"music off battle")
	app._show_home()
	await frames()
	music_state("lobby",lobby_path,false,-16.0,"music off home")
	app._show_catalog()
	await frames()
	music_state("lobby",lobby_path,false,-16.0,"music off catalog")
	app.front_end.resume_requested.emit()
	await frames()
	check(not app.game.paused and app.game.input_enabled,"home to catalog to resume preserves the original running intent")
	music_state("battle",stage_path,false,-20.0,"music off resume")
	check(battle_signature()==signature,"off preference and navigation do not alter the active battle")
	app._toggle_music()
	await frames()
	music_state("battle",stage_path,true,-20.0,"music on actual stream")
	# A pause chosen by the player must not be confused with navigation's
	# temporary pause: switching menu tabs preserves this opposite intent too.
	if not app.game.paused: app.game.pause_battle()
	app._show_home()
	await frames()
	check(not app.navigation_resume_battle,"explicitly paused combat has no automatic resume intent")
	app._show_catalog()
	await frames()
	app.front_end.resume_requested.emit()
	await frames()
	check(app.game.paused and app.game.input_enabled,"explicit pause is preserved after home/catalog/resume")
	check(battle_signature()==signature,"explicit pause navigation still preserves battle identity and state")
	await fade_finished()
	music_state("battle",stage_path,true,-20.0,"explicit pause resume")
	app._show_home()
	await frames()
	await fade_finished()
	check(not app.battle_announcer.enabled and not app.battle_narrator.enabled,"voice off ends both channels safely")
	check(FileAccess.get_file_as_string("res://assets/narration/manifest.json")==male_manifest,"male manifest and original clip metadata remain unchanged")
	check(app.progress.save_path==fixture_save and ProjectSettings.globalize_path(fixture_save).replace("\\","/").simplify_path().to_lower().begins_with(profile),"all actual settings saves remain inside the isolated fixture profile")
	var loaded: RefCounted=Store.new()
	loaded.save_path=fixture_save
	loaded.read_save()
	check(loaded.data.settings.music and not loaded.data.settings.voice,"saved toggle preferences reload correctly")
	check(JSON.stringify(loaded.data.army)==account_army and JSON.stringify(loaded.data.maps)==account_maps,"saved menu/audio changes preserve army and map progress")
	await cleanup()
	var report: Dictionary={"checks":checks,"failed":failures.size(),"failures":failures,"samples":samples,"fixtureSave":ProjectSettings.globalize_path(fixture_save),"scope":"Actual Main scene/callbacks and imported offline audio: startup, barracks, training menu, catalog, stage briefing, battle, home pause/resume, off/on, 0.35s fade, female voice ducking and one BGM player. Battle simulation frozen during comparison, direct recorded component event used for lobby mixer; no GPU, barracks internal layout, OS TTS or live listening."}
	var output: FileAccess=FileAccess.open("user://qa_lobby_ui_context.json",FileAccess.WRITE)
	if output!=null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	else: check(false,"isolated report is writable")
	print(JSON.stringify({"checks":checks,"failed":failures.size(),"samples":samples.size(),"report":ProjectSettings.globalize_path("user://qa_lobby_ui_context.json")}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
