extends SceneTree
## Actual Main recruitment/combat event wiring, speed buttons, settings and outcomes.
var app: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func stop_app() -> void:
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	await create_timer(.5).timeout
	app.queue_free()
	await process_frame

func run() -> void:
	var profile := ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"):
		quit(2)
		return
	root.size = Vector2i(1440,900)
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://combat-app-%d.json" % Time.get_ticks_msec()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.game.set_process(false)
	app.combat_feedback.set_process(false)
	app.battle_audio.set_process(false)
	app.player.stop()
	app.progress.data.settings.voice = false
	app.progress.data.settings.music = false
	check(app.battle_audio.diagnostics().ready and app.battle_audio.diagnostics().missing.is_empty(),"Real Main initializes complete battle audio")
	check(app.game.external_combat_feedback,"Main selects the event-based feedback renderer")
	app._select_tier(0)
	app._select_map(0)
	app._begin_battle()
	app.game.set_process(false)
	var starting_gold: int = app.game.gold
	var paid := 0
	for type_name in ["spear","archer"]:
		app._choose_unit(type_name)
		var cost: int = int(app.progress.unit_definition(type_name).cost)
		check(str(app.game.pending.get("type",""))==type_name and bool(app.game.pending.get("preview",false)) and int(app.game.pending.get("paid",-1))==0,"Main card selects unpaid placement preview for "+type_name)
		check(app.game.gold==starting_gold-paid,"Choosing a class does not spend supply")
		var point: Vector2 = Vector2(-1,-1)
		var best := INF
		for hint in app.game.placement_hints:
			if hint.x<0: continue
			var distance: float = hint.distance_to(app.game.paths[0].points[mini(2,app.game.paths[0].points.size()-1)])
			if distance<best:
				point=hint
				best=distance
		check(point.x>=0 and app.game.place_unit(point.x,point.y),"Main places legal "+type_name+" post")
		paid += cost
		# Advance the real audio cooldown between two actions; no synthetic events.
		app.battle_audio._process(.3)
	check(app.game.gold==starting_gold-paid,"No artificial funds used in actual Main combat")
	for index in range(1200):
		app.game.advance_simulation(1.0/60.0)
		app._process(1.0/60.0)
		app.combat_feedback._process(1.0/60.0)
		app.battle_audio._process(1.0/60.0)
		if index%60==0:
			app.game._emit_state()
			await process_frame
		if int(app.combat_feedback.event_counts.get("hit",0))>=4 and app.game.kills>0:
			break
	var fx: Dictionary = app.combat_feedback.diagnostics()
	var audio: Dictionary = app.battle_audio.diagnostics()
	check(int(fx.events.get("shot",0))>0 and int(fx.events.get("hit",0))>0,"Real attack releases and committed HP loss reach Main feedback")
	check(int(fx.events.get("killed",0))>0 and app.game.kills>0,"Actual deaths reach feedback and combat counters")
	check(int(audio.playCounts.get("bow",0))>0,"Actual archer release reaches a real audio player")
	check(int(audio.playCounts.get("metal",0))+int(audio.playCounts.get("body",0))+int(audio.playCounts.get("wood",0))>0,"Actual damage reaches impact audio")
	check(int(audio.playCounts.get("deploy",0))>0,"Successful paid placement routes through Main deployment audio")
	check(fx.activeMarks>0 and fx.activeMarks<=96,"Actual combat marks are visible and bounded")
	check(app.army_panel.visible and app.army_grid.get_child_count()==8,"Battle retains all eight bottom recruitment cards")
	check(app.learning_panel.get_theme_stylebox("panel") is StyleBoxEmpty,"Learning captions retain transparent background")
	for expected in [2.0,3.0,1.0]:
		app.speed_button.pressed.emit()
		check(is_equal_approx(app.speed,expected) and is_equal_approx(app.game.speed,expected) and app.speed_button.text=="%d×"%int(expected),"Actual speed button selects %d×"%int(expected))
	app._show_pause_menu()
	check(app.game.paused and app.battle_audio.paused and app.combat_feedback.paused,"Actual menu pauses combat and feedback together")
	var effects_button: Button
	for child in app.modal_body.get_children():
		if child is Button and child.text.contains("전투 효과음"):
			effects_button=child
	check(effects_button!=null,"Pause menu exposes battle sound setting")
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions
		await process_frame
		await process_frame
		var bounds: Rect2=app.ui.get_global_rect()
		check(bounds.encloses(app.army_panel.get_global_rect()) and bounds.encloses(app.recruit_button.get_global_rect()),"Bottom recruitment remains on screen at "+str(dimensions))
		if effects_button!=null:
			check(app.modal_scroll.get_global_rect().encloses(effects_button.get_global_rect()),"Effect settings are reachable without clipping at "+str(dimensions))
	if effects_button!=null: effects_button.pressed.emit()
	check(not app.battle_audio.enabled and not bool(app.progress.data.settings.effects),"Actual settings button mutes all effect playback")
	app.progress.read_save()
	check(not bool(app.progress.data.settings.effects),"Effect preference survives actual save reload")
	if effects_button!=null: effects_button.pressed.emit()
	check(app.battle_audio.enabled and bool(app.progress.data.settings.effects),"Actual settings button restores playback")
	app._close_modal()
	app.game._finish(true)
	check(int(app.battle_audio.play_counts.get("victory",0))==1,"Actual battle finish routes exactly one victory sound")
	var victories: int=int(app.battle_audio.play_counts.get("victory",0))
	app._show_study()
	app._return_from_study()
	check(int(app.battle_audio.play_counts.get("victory",0))==victories,"Result dictionary return cannot replay victory")
	app._select_map(0)
	app._begin_battle()
	app.game.set_process(false)
	check(app.combat_feedback.event_counts.get("hit",0)==0 and app.combat_feedback.marks.is_empty(),"New battle discards old impact marks")
	app.game._finish(false)
	check(int(app.battle_audio.play_counts.get("defeat",0))==1,"Actual defeat routes a distinct result sound")
	var report := {"checks":checks,"failures":failures,"actualCombat":fx,"actualAudio":audio,"scope":"Actual Main card-to-unpaid-preview-to-committed-placement flow with Lv1 spear+archer, natural spawns, real attacks and damage, buttons and saved audio preference; outcomes invoked through real Game finish."}
	var file := FileAccess.open("user://qa_combat_app.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("COMBAT_APP ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path("user://qa_combat_app.json"))
	await stop_app()
	quit(0 if failures.is_empty() else 1)
