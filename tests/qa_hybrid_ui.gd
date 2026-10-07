extends SceneTree
## Actual mouse/keyboard paths for the persistent eight-slot bottom toolbar.
## Headless bounds and interaction checks cannot establish rendered pixel contrast.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var observations: Array = []
var actual_deployments: int = 0
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		if failures.size()<30: push_error("HYBRID UI "+message)

func settle() -> void:
	for index in range(3): await process_frame

func inside(control: Control, parent: Control) -> bool:
	return parent.get_global_rect().grow(.5).encloses(control.get_global_rect())

func mouse_click(position: Vector2) -> void:
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = position
	click.global_position = position
	# Deliberately do not synthesize mouse motion: event.position must be used.
	Input.parse_input_event(click)
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await settle()

func escape_key() -> void:
	var key = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	var release: InputEventKey = key.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await settle()

func modal_button(fragment: String) -> Button:
	if app.modal==null: return null
	for button in app.modal.find_children("*","Button",true,false):
		if button.text.contains(fragment): return button
	return null

func check_toolbar(context: String, check_labels: bool = false) -> void:
	var visible: Rect2 = root.get_visible_rect()
	check(app.army_toolbar.is_visible_in_tree(),context+": bottom recruitment toolbar stays visible")
	check(app.army_grid.columns==8 and app.army_grid.get_child_count()==8,context+": all eight classes share one persistent row")
	check(visible.grow(.5).encloses(app.army_toolbar.get_global_rect()),context+": complete bottom toolbar fits in the window")
	check(app.army_toolbar.get_global_rect().position.y>=visible.size.y*.85,context+": recruitment remains at the bottom of the window")
	check(inside(app.army_scroll,app.army_toolbar),context+": class grid fits in its toolbar parent")
	check(inside(app.recruit_button,app.army_toolbar) and app.recruit_button.is_visible_in_tree(),context+": fixed recruitment button is available beside the class row")
	check(app.recruit_button.size.y>48 and app.recruit_button.get_theme_font_size("font_size")>=22,context+": fixed recruitment control is larger than the previous 48-pixel button")
	check(not app.army_scroll.get_h_scroll_bar().is_visible_in_tree() and not app.army_scroll.get_v_scroll_bar().is_visible_in_tree(),context+": all eight slots require no scrolling")
	check(app.army_scroll.scroll_horizontal==0 and app.army_scroll.scroll_vertical==0,context+": card focus does not scroll away another slot")
	var previous: Rect2 = Rect2()
	for id in TYPES:
		var card: Button = app.army_grid.get_node("DeployCard_"+id)
		var rect: Rect2 = card.get_global_rect()
		check(card.is_visible_in_tree() and not card.disabled and inside(card,app.army_scroll),context+": "+id+" slot is entirely visible and usable")
		check(card.size.y>58,context+": "+id+" selection slot is larger than the previous 58-pixel row")
		check(not rect.intersects(app.recruit_button.get_global_rect()),context+": "+id+" slot does not cover recruitment")
		if previous.size.x>0:
			check(absf(rect.position.y-previous.position.y)<.5 and rect.position.x>=previous.end.x-.5,context+": "+id+" remains in the nonoverlapping single row")
		previous=rect
		var portrait: Control = card.get_node("UnitPortrait_"+id)
		# Allow at most one pixel of authored frame bleed around the bust.
		check(rect.grow(1.1).encloses(portrait.get_global_rect()),context+": "+id+" authored bust fits its card within the one-pixel frame bleed")
		if check_labels:
			for child in card.get_children():
				if child is Label:
					check(inside(child,card),context+": "+id+" card label fits its own card")
			check(card.tooltip_text.contains(str(app.progress.army_evolution(id).name)),context+": "+id+" tooltip retains full evolution identity")

func check_field(context: String) -> void:
	var viewport: Rect2 = root.get_visible_rect()
	var field: Rect2 = app.game.field_rect
	check(viewport.encloses(field),context+": expanded battlefield fits the window")
	check(field.size.x>=viewport.size.x*.94,context+": battlefield uses nearly the full window width")
	check(field.get_area()/viewport.get_area()>=.65,context+": battlefield occupies approximately seventy percent or more of the window")
	check(field.encloses(app.learning_panel.get_global_rect()),context+": subtitles are displayed inside the expanded battlefield")
	check(app.learning_panel.get_theme_stylebox("panel") is StyleBoxEmpty,context+": subtitles have no painted panel background")
	check(app.learning_panel.mouse_filter==Control.MOUSE_FILTER_IGNORE,context+": transparent subtitle overlay passes battlefield mouse input")
	check(app.active_word.mouse_filter==Control.MOUSE_FILTER_IGNORE and app.example_label.mouse_filter==Control.MOUSE_FILTER_IGNORE,context+": subtitle text nodes also pass battlefield mouse input")
	check(not app.learning_paper.is_visible_in_tree(),context+": parchment artwork does not add a subtitle background")
	check(app.learning_panel.get_global_rect().end.y<=app.army_toolbar.get_global_rect().position.y,context+": learning strip and recruitment row stay separate")
	for control in [app.pause_button,app.speed_button,app.battle_menu_button]:
		check(control.is_visible_in_tree() and viewport.encloses(control.get_global_rect()) and control.get_global_rect().end.y<=field.position.y,context+": header command stays visible above the battlefield")
	check(app.game.actor_overlay!=null and app.game.actor_overlay.z_index>app.troops_3d.z_index,context+": placement overlay is ordered above the 3D background")

func check_inspector(context: String) -> void:
	check(app.army_panel.is_visible_in_tree(),context+": deployed selection opens its compact inspector")
	check(not app.hint_bar.is_visible_in_tree() and not app.hint_line.is_visible_in_tree(),context+": selected-unit inspector suppresses overlapping optional placement hints")
	check(app.game.field_rect.grow(.5).encloses(app.army_panel.get_global_rect()),context+": floating inspector fits inside the battlefield")
	check(not app.army_panel.get_global_rect().intersects(app.army_toolbar.get_global_rect()) and not app.army_panel.get_global_rect().intersects(app.learning_panel.get_global_rect()),context+": selection never covers recruitment or the learning strip")
	check(inside(app.selected_portrait_window,app.army_panel),context+": authored selection bust fits in the inspector")
	check(inside(app.selected_word,app.army_panel) and inside(app.selected_label,app.army_panel),context+": selected Japanese identity and permanent training fit in the inspector")
	check(inside(app.army_tactics,app.army_panel),context+": tactical text fits in inspector")
	check(inside(app.army_health,app.army_panel),context+": health bar fits in inspector")
	check(app.army_tactics.position.y+app.army_tactics.size.y<=app.army_health.position.y,context+": tactical text does not overlap health bar")
	check(app.army_tactics.get_combined_minimum_size().y<=app.army_tactics.size.y+.5,context+": complete tactical text fits its lines")
	check(not app.selected_portrait_window.get_global_rect().intersects(app.army_tactics.get_global_rect()),context+": portrait does not cover tactical status")
	if str(app.current_map.theme)=="river":
		check(app.bridge_button.is_visible_in_tree() and not app.bridge_button.get_global_rect().intersects(app.army_panel.get_global_rect()),context+": river control stays available outside the selected-unit inspector")

func check_menu(context: String) -> void:
	var gold: int = app.game.gold
	var count: int = app.game.units.size()
	var wallet: int = int(app.progress.data.army.currency)
	await escape_key()
	check(app.modal!=null and app.modal_context=="pause",context+": actual Esc key reaches the battle menu")
	if app.modal==null: return
	for fragment in ["전투 계속","학습 도감","다른 전장","배경음악","일본어 음성"]:
		var button: Button = modal_button(fragment)
		check(button!=null and button.is_visible_in_tree(),context+": menu exposes "+fragment)
	var audio: Button = modal_button("배경음악")
	if audio!=null:
		var before: bool = bool(app.progress.data.settings.music)
		await mouse_click(audio.get_global_rect().get_center())
		check(bool(app.progress.data.settings.music)!=before,context+": menu music callback toggles the persisted setting")
		await mouse_click(audio.get_global_rect().get_center())
		check(bool(app.progress.data.settings.music)==before,context+": menu music callback restores the original setting")
	var narration: Button = modal_button("일본어 음성")
	if narration!=null:
		var before: bool = bool(app.progress.data.settings.voice)
		await mouse_click(narration.get_global_rect().get_center())
		if app.japanese_voice.is_empty():
			check(bool(app.progress.data.settings.voice)==before and app.toast_label.text.contains("음성"),context+": unavailable Japanese speech is reported without fabricating availability")
		else:
			check(bool(app.progress.data.settings.voice)!=before,context+": menu speech callback toggles the real available voice setting")
			await mouse_click(narration.get_global_rect().get_center())
			check(bool(app.progress.data.settings.voice)==before,context+": menu speech callback restores the original setting")
	var study: Button = modal_button("학습 도감")
	if study!=null:
		await mouse_click(study.get_global_rect().get_center())
		check(app.modal!=null and app.modal_context=="study",context+": dictionary opens through the actual menu callback")
		await escape_key()
		check(app.modal==null and app.ui.is_visible_in_tree(),context+": dictionary Esc returns to the battlefield")
	await escape_key()
	var catalog: Button = modal_button("다른 전장")
	if catalog!=null:
		await mouse_click(catalog.get_global_rect().get_center())
		check(app.front_end.visible and app.front_end.view=="catalog",context+": stage catalog opens through the battle menu")
		await escape_key()
		check(not app.front_end.visible and app.ui.is_visible_in_tree(),context+": catalog Esc resumes the same battlefield")
	check(app.game.gold==gold and app.game.units.size()==count and int(app.progress.data.army.currency)==wallet,context+": menu navigation and audio settings never consume either combat or permanent funds")
	check_toolbar(context+" menu return")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"):
		push_error("Tactical UI QA refuses the player's profile")
		quit(2)
		return
	var save_path: String = "user://hybrid-ui-%d.json" % Time.get_ticks_msec()
	var fixture = Store.new()
	fixture.save_path = save_path
	for map in JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")):
		fixture.data.maps[str(map.id)] = {"wins":1}
	fixture.data.settings = {"music":false,"voice":false}
	check(fixture.write_save(),"QA fixture persists without touching player progress")
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = save_path
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	app.player.stop()
	var stage_indices: Array = [0,3] if OS.get_cmdline_user_args().has("--smoke") else range(40)
	for viewport in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = viewport
		root.content_scale_size = viewport
		app._layout()
		await settle()
		for stage in stage_indices:
			app._select_tier(stage/10)
			app._select_map(stage%10)
			await settle()
			var name: String = str(app.current_map.id)+" "+str(viewport)
			check(app.current_map.has("tactics"),name+": actual stage carries a tactical plan")
			check(app.modal_scroll.get_global_rect().end.y<=app.modal_footer.get_global_rect().position.y,name+": briefing scroll does not cover sortie button")
			app._begin_battle()
			app.game.set_process(false)
			app.game.gold = 10000
			check(not app.army_panel.is_visible_in_tree(),name+": no deployed selection leaves the inspector hidden")
			check_field(name)
			check_toolbar(name,true)
			var completed_classes: int = 0
			for id in TYPES:
				app.game.units.clear()
				app.game._emit_state()
				var card: Button = app.army_grid.get_node("DeployCard_"+id)
				await mouse_click(card.get_global_rect().get_center())
				check(app.chosen_unit_id==id,name+": actual bottom-card mouse click selects "+id)
				var supply: int = app.game.gold
				var cost: int = int(app.progress.unit_definition(id).cost)
				await mouse_click(app.recruit_button.get_global_rect().get_center())
				check(str(app.game.pending.get("type",""))==id,name+": UI recruits "+id)
				if str(app.game.pending.get("type",""))!=id:
					app.game.cancel_recruit()
					continue
				check(supply-app.game.gold==cost,name+": actual toolbar recruitment spends the displayed class cost once")
				check(not app.army_panel.is_visible_in_tree(),name+": pending "+id+" hides the inspector so placement is unobstructed")
				check(app.hint_line.is_visible_in_tree() and app.hint_bar.is_visible_in_tree(),name+": active recruitment exposes its placement hint")
				check(app.hint_line.text.contains("황금" if id=="archer" else "청록"),name+": placement instruction matches class")
				check_toolbar(name+" pending "+id)
				var point: Vector2 = Vector2(-1,-1)
				for hint in app.game.placement_hints:
					if hint.x>=0:
						point=hint
						break
				check(point.x>=0,name+": stage offers a legal "+id+" position")
				if point.x<0:
					app.game.cancel_recruit()
					continue
				await mouse_click(app.game.get_global_transform_with_canvas()*app.game._screen(point))
				var selected: Dictionary = app.game.snapshot().selected
				check(str(selected.get("type",""))==id and bool(selected.get("deployed",false)),name+": field click deploys "+id)
				if str(selected.get("type",""))!=id or not bool(selected.get("deployed",false)):
					app.game.cancel_recruit()
					continue
				completed_classes += 1
				actual_deployments += 1
				if not app.game.units.is_empty():
					check((app.game.units[-1].position as Vector2).distance_to(point)<.00005,name+": actual field click lands at the requested normalized point for "+id)
				check(app.game.gold==supply-cost,name+": field deployment does not charge supply twice")
				check(str(app.selected_word.word.jp)==str(app.progress.army_evolution(id).jp) and app.selected_label.text.contains("Lv."),name+": selected identity and permanent level remain accessible")
				check(not app.army_tactics.text.is_empty(),name+": actual tactical status is visible")
				if id=="archer":
					check(not app.army_health.visible and app.army_tactics.text.contains("원거리"),name+": ranged support has a distinct inspector")
				elif id=="gunner":
					check(app.army_health.visible and app.army_health.max_value>0 and app.army_tactics.text.contains("정지") and app.army_tactics.text.contains("사격"),name+": frontline shooter health and stationary fire are visible")
				else:
					check(app.army_health.visible and app.army_health.max_value>0 and app.army_tactics.text.contains("체력") and app.army_tactics.text.contains("저지"),name+": frontline health and block capacity are visible")
				check_inspector(name+" "+id)
				check_toolbar(name+" deployed "+id)
			check(completed_classes==8,name+": all eight real card/recruit/field interaction paths completed")
			observations.append({"stage":app.current_map.id,"viewport":str(viewport),"classes":completed_classes,"fieldAreaRatio":app.game.field_rect.get_area()/root.get_visible_rect().get_area(),"fixedSlots":app.army_grid.get_child_count()})
			if str(app.current_map.theme)=="river":
				var before_bridge: int = int(app.game.snapshot().bridge)
				var before_supply: int = app.game.gold
				await mouse_click(app.bridge_button.get_global_rect().get_center())
				check(int(app.game.snapshot().bridge)!=before_bridge,name+": real river-control click changes the bridge despite the selected popup")
				check(app.game.gold==before_supply,name+": river-control interaction does not debit recruitment supply")
			if stage==0:
				await mouse_click(app.active_word.get_global_rect().get_center())
				check(app.game.snapshot().selected.is_empty() and not app.army_panel.is_visible_in_tree(),name+": clicking through word subtitles reaches the field and clears the selected unit")
				check_toolbar(name+" subtitle click-through")
				await check_menu(name)
			app._show_catalog()
			app.front_end.selected_tier=stage/10
			app.front_end.selected_stage=stage%10
			app.front_end._rebuild()
			await settle()
			var description: Label = app.front_end.get_node("StageTacticalDescription")
			check(description.text==str(app.current_map.tactics.descriptionKo),name+": catalog displays its actual terrain tactic")
			check(description.get_combined_minimum_size().y<=description.size.y+.5,name+": catalog tactic is readable in full")
	app.player.stream = null
	app.queue_free()
	await process_frame
	var report = {"checks":checks,"failures":failures,"observations":observations,"deployments":actual_deployments,"stageCount":stage_indices.size(),"scope":"Default 40 stages x8 classes x3 viewport sizes; persistent eight-slot bottom toolbar; actual no-motion MouseInput/card/recruit/field paths; normalized deployment accuracy; compact selected inspector; Esc menu, music/voice and navigation callbacks.","profile":profile,"resourceRoot":ProjectSettings.globalize_path("res://"),"limits":"Headless geometry, visibility flags, stacking contract and interaction only. GPU pixel contrast, photograph compositing and native Japanese TTS output are inspected separately; no voice capability is fabricated."}
	var output = FileAccess.open("user://qa_hybrid_ui.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("HYBRID_UI ",JSON.stringify({"checks":checks,"failures":failures.size(),"stages":observations.size()}))
	quit(0 if failures.is_empty() else 1)
