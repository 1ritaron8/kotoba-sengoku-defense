extends SceneTree

const Store = preload("res://native/progress.gd")
const GameFonts = preload("res://native/game_fonts.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []
var images: Array[String] = []
var capture_enabled: bool = false

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<20: push_error("AUDIO_VOLUME: "+note)

func settle(count: int = 8) -> void:
	for unused in range(count): await process_frame

func save_fixture(path: String, value: Dictionary) -> void:
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func storage() -> void:
	var store = Store.new()
	var original: Dictionary = store.data.duplicate(true)
	store.save_path = "user://volume-valid.json"
	for key in Store.AUDIO_DEFAULTS:
		check(is_equal_approx(store.audio_volume(key),float(Store.AUDIO_DEFAULTS[key])),"New profile has the intended default: "+key)
		for value in [0.0,0.01,0.33,0.75,1.0]:
			check(store.set_audio_volume(key,value) and store.write_save(),"Audio preference commits successfully: "+key)
			var reloaded = Store.new()
			reloaded.save_path = store.save_path
			reloaded.read_save()
			check(is_equal_approx(reloaded.audio_volume(key),value),"Saved audio value reloads exactly: "+key)
	check(store.data.army==original.army and store.data.maps==original.maps and store.data.words==original.words and store.data.learning==original.learning,"Changing audio preserves all player progress and army currency")
	check(not store.set_audio_volume("armyCurrency",0.0) and not store.set_audio_volume("masterVolume",NAN),"Audio setters reject unknown keys and non-finite values")
	for bad in [-8.0,7.0,"loud",true,null]:
		var fixture: Dictionary = original.duplicate(true)
		for key in Store.AUDIO_DEFAULTS: fixture.settings[key]=bad
		var path: String = "user://volume-invalid-%d.json" % Time.get_ticks_usec()
		save_fixture(path,fixture)
		var reloaded = Store.new()
		reloaded.save_path = path
		reloaded.read_save()
		for key in Store.AUDIO_DEFAULTS:
			var expected: float = clampf(float(bad),0,1) if bad is float else float(Store.AUDIO_DEFAULTS[key])
			check(is_equal_approx(reloaded.audio_volume(key),expected),"Invalid or out-of-range saved preference is repaired: "+key+" "+str(bad))
	var legacy: Dictionary = original.duplicate(true)
	legacy.version=1
	legacy.settings={"music":false,"voice":false,"battleMinutes":10}
	save_fixture("user://volume-legacy.json",legacy)
	var migrated = Store.new()
	migrated.save_path="user://volume-legacy.json"
	migrated.read_save()
	check(not migrated.data.settings.music and not migrated.data.settings.voice and migrated.data.settings.battleMinutes==10,"Old settings keep toggles and the chosen battle duration")
	for key in Store.AUDIO_DEFAULTS:
		check(is_equal_approx(migrated.audio_volume(key),float(Store.AUDIO_DEFAULTS[key])),"Old saves safely acquire an absent audio preference: "+key)
	var future: Dictionary=original.duplicate(true)
	future.version=99
	save_fixture("user://volume-future.json",future)
	var protected_hash: String=FileAccess.get_sha256("user://volume-future.json")
	var blocked = Store.new()
	blocked.save_path="user://volume-future.json"
	blocked.read_save()
	blocked.set_audio_volume("masterVolume",0.5)
	check(not blocked.write_save() and FileAccess.get_sha256(blocked.save_path)==protected_hash,"A newer save remains protected even after moving an audio slider")

func mixer() -> void:
	for key in Store.AUDIO_DEFAULTS: app._set_audio_volume(key,1.0)
	app._set_audio_volume("masterVolume",0.5)
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)),0.5) and not AudioServer.is_bus_mute(0),"Overall volume applies to the shared game mixer")
	app._set_audio_volume("musicVolume",0.25)
	var music_bus: int=AudioServer.get_bus_index(app.player.bus)
	check(music_bus>0 and AudioServer.get_bus_send(music_bus)=="Master" and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)),0.25),"Background music has its own gain underneath overall volume")
	app._set_audio_volume("effectsVolume",0.35)
	check(is_equal_approx(app.battle_audio.volume,0.35),"Effects get their own volume")
	app._set_audio_volume("voiceVolume",0.45)
	check(is_equal_approx(app.battle_narrator.volume,0.45) and is_equal_approx(app.battle_announcer.volume,0.45),"Both recorded narrators use the voice slider")
	check(is_equal_approx(app.voice_director.volume,0.225),"System Japanese reading also applies overall times voice volume")
	app._apply_voice_mix(true)
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)),0.25) and is_equal_approx(app.battle_audio.volume,0.35),"Narration ducking preserves the chosen music and effects gains")
	for key in ["musicVolume","effectsVolume","voiceVolume"]:
		app._set_audio_volume(key,0.0)
		var buses: Array = [music_bus] if key=="musicVolume" else [AudioServer.get_bus_index(app.battle_audio.bus_name)] if key=="effectsVolume" else [AudioServer.get_bus_index(app.battle_narrator.bus_name),AudioServer.get_bus_index(app.battle_announcer.bus_name)]
		for bus in buses: check(AudioServer.is_bus_mute(bus),"Zero percent really mutes the channel: "+key)
		check(not AudioServer.is_bus_mute(0),"Muting one channel preserves the overall mixer: "+key)
		app._set_audio_volume(key,0.5)
		for bus in buses: check(not AudioServer.is_bus_mute(bus),"Raising a slider restores that channel: "+key)
	app.voice_director.reserve_tts()
	app._set_audio_volume("masterVolume",0.0)
	check(AudioServer.is_bus_mute(0) and is_zero_approx(app.voice_director.volume) and not app.voice_director.diagnostics().ttsReserved,"Overall mute also cancels speech outside the game mixer")
	check(is_zero_approx(app.battle_narrator.volume) and is_zero_approx(app.battle_announcer.volume) and not app.battle_narrator.is_speaking() and not app.battle_announcer.is_speaking(),"Overall mute stops both recorded narrators instead of restoring half a phrase")
	check(not app.voice_director.speak("こんにちは","qa-voice"),"Muted system reading cannot queue audible speech")
	app._set_audio_volume("masterVolume",0.6)
	check(not AudioServer.is_bus_mute(0) and is_equal_approx(app.voice_director.volume,0.3),"Restoring overall volume restores system speech gain")
	app._save_audio_settings()
	var reloaded=Store.new()
	reloaded.save_path=app.progress.save_path
	reloaded.read_save()
	for key in Store.AUDIO_DEFAULTS:
		check(is_equal_approx(reloaded.audio_volume(key),app.progress.audio_volume(key)),"The actual Main controller stores its slider value: "+key)

func layout_controls(control: Control, label: String) -> void:
	var sliders: Array=control.find_children("VolumeSlider_*","HSlider",true,false)
	check(sliders.size()==4,"All four sliders exist in "+label)
	for slider in sliders:
		check(root.get_visible_rect().encloses(slider.get_global_rect()) and slider.size.x>=120 and slider.size.y>=16,"A real volume slider fits the screen and can be grabbed: "+label+" "+str(slider.name))
		check(slider.focus_mode==Control.FOCUS_ALL,"Volume supports keyboard focus: "+str(slider.name))
	var panel: Control=control.find_child("VolumeControls",true,false)
	check(panel!=null and panel.size.y>=180,"The complete audio panel has room for its four rows: "+label)
	if panel!=null:
		for row in panel.get_children():
			for item in row.get_children():
				if item is Label:
					check(item.get_theme_font("font").get_string_size(item.text,HORIZONTAL_ALIGNMENT_LEFT,-1,item.get_theme_font_size("font_size")).x<=item.size.x+1,"Volume labels and percentages are fully visible: "+item.text)

func capture(name_value: String) -> void:
	if not capture_enabled: return
	await RenderingServer.frame_post_draw
	var path: String="user://audio-%s-%dx%d.png" % [name_value,root.content_scale_size.x,root.content_scale_size.y]
	check(root.get_texture().get_image().save_png(path)==OK,"Actual audio settings capture saved")
	images.append(ProjectSettings.globalize_path(path))

func screens() -> void:
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.content_scale_size=dimensions
		root.size=dimensions
		app._show_home()
		app.front_end.view="settings"
		app.front_end._rebuild()
		await settle()
		layout_controls(app.front_end,"home "+str(dimensions))
		var slider: HSlider=app.front_end.find_child("VolumeSlider_effectsVolume",true,false)
		if slider!=null:
			slider.value=37
			check(is_equal_approx(app.battle_audio.volume,0.37),"The actual settings slider reaches the mixer controller")
		await capture("home")
		app.front_end.hide()
		app.ui.show()
		app.field_clip.show()
		app._show_pause_menu()
		app._layout()
		await settle()
		if app.modal_scroll!=null: app.modal_scroll.scroll_vertical=int(app.modal_scroll.get_v_scroll_bar().max_value)
		await settle()
		layout_controls(app.modal,"battle menu "+str(dimensions))
		await capture("battle-menu")
		app._close_modal(false)

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/audio-volume/").to_lower()):
		push_error("Audio QA requires an isolated workspace profile")
		quit(2)
		return
	capture_enabled="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	storage()
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://volume-main.json"
	root.add_child(app)
	await settle()
	app.game.set_process(false)
	app.atmosphere.set_process(false)
	app.troops_3d.set_process(false)
	mixer()
	await screens()
	app._save_audio_settings()
	var output: String="user://qa_audio_volume.json"
	var file=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"images":images,"settings":app.progress.data.settings,"voiceMix":app.voice_director.diagnostics()},"\t"))
	file.close()
	print("AUDIO_VOLUME checks=",checks," failures=",failures.size()," report=",ProjectSettings.globalize_path(output))
	app._stop_narration()
	app.player.stop()
	app.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
