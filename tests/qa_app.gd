extends SceneTree

var failures: Array = []
var app: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var scene = load("res://native/main.tscn")
	app = scene.instantiate()
	root.add_child(app)
	await process_frame
	check(app.maps.size()==40,"App loads forty maps")
	check(app.words_by_id.size()==900,"App loads nine hundred words")
	check(app.music_by_stage.size()==40,"Forty stage-specific music assignments load")
	check(app.field_clip.clip_contents,"Battle rendering stays within its viewport")
	check(app.game.three_d_enabled and app.troops_3d.visible,"Installed game enables articulated 3D troops by default")
	for actor_type in app.progress.unlocked_units():
		var portrait: TextureRect = app.army_grid.get_node("DeployCard_%s/UnitPortrait_%s" % [actor_type,actor_type])
		var source_path: String = str(portrait.get_meta("source_path",""))
		var expected_path: String = "res://assets/units-animated/%s.png" % actor_type if actor_type in ["archer","spear","samurai","commander"] else "res://assets/units-standing/idle-support-v1.png"
		check(portrait.texture is AtlasTexture and portrait.texture.atlas.resource_path==expected_path and source_path==expected_path and str(portrait.get_meta("unit_id",""))==actor_type,"Army card crops the selected class's approved authored portrait")
	check(app.front_end.visible and app.front_end.view=="home","Game starts on the Sengoku title screen")
	for tier in range(4):
		app._select_tier(tier)
		await process_frame
		for index in range(10):
			app._select_map(index)
			await process_frame
			check(app.current_map.tier==app.TIER_IDS[tier],"Tier selection matches loaded map")
			check(is_equal_approx(app.game.three_d_actor_scale,app.troops_3d.actor_base_scale()),"Every map shares the renderer scale with labels, health bars and projectile heights")
			check(app.learning_words.size()>=15,"Every map has learning content")
			check(app.modal!=null,"Map briefing opens")
			check(str(app.current_music.stageId)==str(app.current_map.id),"Selecting a map selects its own music")
			check(app.player.stream!=null and app.player.stream.get_length()>20,"Stage track is playable audio")
			var expected_path: String = str(app.music_by_stage[str(app.current_map.id)].path)
			check(app.player.stream.resource_path==expected_path,"Actual stream matches stage assignment")
	app._select_tier(0)
	await process_frame
	app.progress.data.settings.music = true
	app._toggle_music()
	check(not app.player.playing,"Music off stops playback")
	app._select_map(1)
	await process_frame
	check(not app.player.playing,"Changing stage preserves music off preference")
	app._toggle_music()
	check(app.player.playing,"Music on starts the selected stage track")
	app._select_map(0)
	await process_frame
	app._begin_battle()
	await process_frame
	check(app.battle_started and app.modal==null,"Briefing starts native battle")
	check(app.player.stream.resource_path==str(app.current_music.path),"Stage music continues during battle")
	app._show_pause_menu()
	check(app.modal_context=="pause" and app.game.paused,"Operations menu pauses battle")
	app._show_catalog()
	check(app.front_end.visible and app.front_end.battle_active and app.game.paused,"Map browser preserves a paused active battle")
	app._resume_from_navigation()
	app.recruit_button.grab_focus()
	var space = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	var space_gold: int = app.game.gold
	Input.parse_input_event(space)
	await process_frame
	check(app.game.paused and app.game.pending.is_empty() and app.game.gold==space_gold,"Space pauses without activating the focused recruit button")
	space.pressed = false
	Input.parse_input_event(space.duplicate())
	await process_frame
	space.pressed = true
	Input.parse_input_event(space.duplicate())
	await process_frame
	check(not app.game.paused and app.game.gold==space_gold,"Space resumes without spending gold")
	space.pressed = false
	Input.parse_input_event(space.duplicate())
	check(not app.front_end.visible and not app.game.paused,"Returning from map browser restores running battle")
	app._show_pause_menu()
	app._show_home()
	check(app.front_end.visible and app.game.paused,"Title screen pauses existing battle")
	var original_map: String = str(app.game.config.id)
	var original_wave: int = app.game.wave
	var original_gold: int = app.game.gold
	app.front_end.show_catalog(3,true)
	app._choose_stage(3,9,true)
	check(str(app.game.config.id)==original_map and app.game.wave==original_wave and app.game.gold==original_gold,"Browsing another stage's dictionary cannot reset current battle")
	check(str(app.catalog_study_lesson.id)==str(app.curriculum.advanced[9].id),"Dictionary shows the requested stage's content")
	app._return_from_study()
	check(app.curriculum.advanced[9].newWords.size()==30,"Closing dictionary preserves original curriculum data")
	check(app.front_end.visible and app.front_end.study_mode,"Dictionary returns to its stage catalog")
	app._resume_from_navigation()
	check(not app.game.paused and str(app.game.config.id)==original_map,"Dictionary navigation resumes preserved battle")
	app._show_catalog()
	var before_key: int = app.game.gold
	var hidden_key = InputEventKey.new()
	hidden_key.keycode = KEY_R
	hidden_key.pressed = true
	app._unhandled_key_input(hidden_key)
	check(app.game.pending.is_empty() and app.game.gold==before_key,"Battle shortcuts do not recruit behind menu")
	app._resume_from_navigation()
	for step in range(3):
		app._advance_word()
	check(app.example_label.word.jp==app.current_lesson.expressions[0].jp,"Map expressions appear naturally alongside battle words")
	var recruit_gold = int(app.game.snapshot().gold)
	app._recruit()
	check(not app.game.snapshot().pending.is_empty(),"Recruit creates a pending placement")
	app._recruit()
	check(app.game.snapshot().pending.is_empty() and int(app.game.snapshot().gold)==recruit_gold,"Recruit cancel button refunds exactly once")
	app._show_quiz()
	await process_frame
	check((app.modal!=null or app.context_task_active) and not app.quiz_resolved,"Optional reward challenge opens in its actual word or battlefield form")
	var gold = int(app.game.snapshot().gold)
	var answer: String = str(app.quiz_task.answerId)
	if app.context_task_active: app._answer_context(answer)
	else: app._answer_quiz(answer)
	check(int(app.game.snapshot().gold)==gold+70,"Correct answer grants bonus")
	if app.context_task_active: app._answer_context(answer)
	else: app._answer_quiz(answer)
	check(int(app.game.snapshot().gold)==gold+70,"Same answer cannot grant twice")
	app._continue_battle()
	await process_frame
	app._show_quiz()
	await process_frame
	app._quiz_hint()
	gold = int(app.game.snapshot().gold)
	if app.context_task_active: app._answer_context(str(app.quiz_task.answerId))
	else: app._answer_quiz(str(app.quiz_task.answerId))
	check(int(app.game.snapshot().gold)==gold+25,"Hinted answer grants smaller bonus")
	app._continue_battle()
	await process_frame
	app._show_study()
	await process_frame
	check(app.modal!=null,"Study opens during battle")
	app._return_from_study()
	await process_frame
	app._on_battle_finished({"victory":true})
	await process_frame
	var map_id = str(app.current_map.id)
	var wins = int(app.progress.data.maps[map_id].wins)
	var army_currency: int = int(app.progress.data.army.currency)
	app._show_study()
	await process_frame
	app._return_from_study()
	await process_frame
	check(int(app.progress.data.maps[map_id].wins)==wins,"Returning from result study cannot duplicate victory")
	check(int(app.progress.data.army.currency)==army_currency,"Returning from result study cannot duplicate campaign currency")
	app._show_home()
	app._show_barracks()
	check(app.barracks.visible and not app.front_end.visible,"Barracks opens from the home screen")
	check(app.barracks.can_train,"Training is available after a completed battle")
	check(app.barracks.find_child("ArmyCard_gunner",true,false)!=null,"Locked future unit is visible with its unlock condition")
	app.barracks.hide()
	app._return_from_barracks()
	check(app.front_end.visible and app.front_end.view=="home","Barracks returns to the home screen")
	print("APP QA: ","PASS" if failures.is_empty() else "FAIL"," (40 map selections/music, home/pause/navigation, dictionary preserves battle, rewards, duplicate protection)")
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	await create_timer(0.5).timeout
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
