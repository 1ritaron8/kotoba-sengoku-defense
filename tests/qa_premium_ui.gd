extends SceneTree
## Presentation and real UI signals; no combat economy/model matrix duplication.
const Store=preload("res://native/progress.gd")
const Portrait=preload("res://native/barracks_portrait.gd")
const UIStyle=preload("res://native/sengoku_ui.gd")
const TYPES=["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var app: Node
var checks:=0
var failures: Array[String]=[]
var images: Array=[]
var capture_enabled:=false
var current_dimensions:=Vector2i(1280,800)
var initial_gold:=0
var intermission_capture:=false
var battle_refresh:=false

func _initialize() -> void: call_deferred("run")

func check(value: bool,note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<30: push_error("PREMIUM_UI "+note)

func settle() -> void:
	for frame in range(4): await process_frame
	if not is_instance_valid(app) or app.learning_transition==null:
		return
	var deadline: int=Time.get_ticks_msec()+3000
	while app.learning_transition.is_busy() and Time.get_ticks_msec()<deadline:
		await process_frame
	check(not app.learning_transition.is_busy(),"Learning presentation reaches its input-ready phase")

func named(parent: Node,id: String) -> Node:
	for child in parent.find_children(id,"",true,false):
		if child is Control and child.is_visible_in_tree() and not child.is_queued_for_deletion(): return child
	return null

func press(button: Button,note: String) -> void:
	check(button!=null and not button.disabled,note+": actual action is available")
	if button!=null and not button.disabled:
		button.pressed.emit()
		await settle()

func mouse(position: Vector2,button: int=MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=button
		event.pressed=pressed
		event.position=position
		event.global_position=position
		Input.parse_input_event(event)
	await settle()

func motion(position: Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=position
	event.global_position=position
	Input.parse_input_event(event)
	await settle()

func capture(name: String) -> void:
	if not capture_enabled: return
	if intermission_capture and not (name in ["support-choice","support-result","meaning-choice","sentence-choice","sentence-result","listening-choice"] or (name=="barracks" and current_dimensions==Vector2i(1920,1080))): return
	if battle_refresh and not (name=="battle" and current_dimensions in [Vector2i(1280,800),Vector2i(1920,1080)]): return
	await create_timer(.36).timeout
	app.troops_3d._process(0)
	app.game.queue_redraw()
	app.game.actor_overlay.queue_redraw()
	await settle()
	await RenderingServer.frame_post_draw
	var path: String="C:/JP_DF/dist/premium-%s-%dx%d.png"%[name,current_dimensions.x,current_dimensions.y]
	check(root.get_texture().get_image().save_png(path)==OK,"GPU image saved: "+name)
	images.append(path)

func fits(control: Control,bounds: Rect2,note: String) -> void:
	check(control.is_visible_in_tree() and bounds.grow(1).encloses(control.get_global_rect()),note+": visible geometry fits its parent/window")

func label_bounds(parent: Node,note: String) -> void:
	for label in parent.find_children("*","Label",true,false):
		if not label.is_visible_in_tree(): continue
		var ancestor: Node=label.get_parent()
		var visible_rect: Rect2=label.get_global_rect()
		while ancestor!=null and ancestor!=parent:
			if ancestor is Control and ancestor.clip_contents:
				visible_rect=visible_rect.intersection(ancestor.get_global_rect())
			ancestor=ancestor.get_parent()
		if not visible_rect.has_area(): continue
		check(label.get_theme_font_size("font_size")>=20,note+": text remains at least 20px: "+label.text.left(25))
		check(root.get_visible_rect().grow(1).encloses(visible_rect),note+": visible label stays inside the viewport: "+label.text.left(25))

func legal_point(type_name: String) -> Vector2:
	for zone in app.game.zones:
		var point: Vector2=app.game._zone_placement_hint(zone,type_name)
		if point.x>=0 and point.y>.12 and point.y<.80: return point
	return Vector2(-1,-1)

func battle_checks() -> void:
	var bounds: Rect2=root.get_visible_rect()
	check(app.game.field_rect==Rect2(16,64,bounds.size.x-32,bounds.size.y-164),"Battlefield dimensions remain unchanged")
	check(app.army_grid.columns==8 and app.army_grid.get_child_count()==8,"All eight classes remain in the persistent bottom row")
	fits(app.army_toolbar,bounds,"Bottom toolbar")
	check(not app.army_scroll.get_h_scroll_bar().is_visible_in_tree(),"No horizontal scrolling is needed for recruitment")
	for id in TYPES:
		var card: Button=app.army_grid.get_node("DeployCard_"+id)
		fits(card,app.army_scroll.get_global_rect(),"Bottom "+id)
		check(card.tooltip_text.split("\n").size()<=2,"Card "+id+" has a concise non-repeated tooltip")
		var portrait: TextureRect=card.get_node("UnitPortrait_"+id)
		var expected: AtlasTexture=UIStyle.bust_texture(Portrait.first_frame_texture(id),id)
		check(portrait.texture.atlas.resource_path==expected.atlas.resource_path and portrait.texture.region==expected.region,"Card "+id+" retains its approved correctly cropped portrait")
		for label in card.get_children():
			if label is Label:
				check(label.get_theme_font_size("font_size")>=20,"Card "+id+" keeps names and costs readable")
				check(card.get_global_rect().grow(1).encloses(label.get_global_rect()),"Card "+id+" label stays within its own slot")
	for control in [app.map_title,app.hud_wave,app.hud_health,app.hud_gold,app.pause_button,app.speed_button,app.battle_menu_button]:
		fits(control,bounds,"Header "+str(control.name))
	check(app.map_title.get_global_rect().end.x<=app.hud_wave.get_global_rect().position.x,"Stage title does not cover wave information")
	check(app.hud_wave.get_global_rect().end.x<=app.hud_health.get_global_rect().position.x and app.hud_health.get_global_rect().end.x<=app.hud_gold.get_global_rect().position.x,"Header counters have consistent separate columns")
	check(app.learning_panel.get_theme_stylebox("panel") is StyleBoxEmpty and app.learning_panel.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Learning subtitles remain transparent and click-through")
	check(app.active_word.base_size==36 and app.example_label.base_size==24,"Japanese learning font sizes are preserved")
	check(not app.toast_label.visible,"Starting a battle does not paint a repeated full-width recruitment instruction")
	initial_gold=app.game.gold
	var wallet: int=int(app.progress.data.army.currency)
	await press(app.army_grid.get_node("DeployCard_archer"),"Choose archer")
	check(app.game.gold==initial_gold and str(app.game.pending.type)=="archer" and bool(app.game.pending.preview),"One class click prepares an unpaid exact-class ghost")
	var point:=legal_point("archer")
	check(point.x>=0,"This actual battlefield has a visible legal archer position")
	await motion(app.game._screen(point))
	check(app.game.placement_cursor_visible and not app.army_panel.visible,"Preview is visible while the inspector stays out of the way")
	app._update_placement_feedback()
	check(app.hint_line.text==app.placement_guidance,"A legal ghost retains concise normal deployment guidance")
	var invalid: Vector2=Vector2(-1,-1)
	for x in range(1,10):
		for y in range(2,7):
			var candidate:=Vector2(x*.1,y*.1)
			if not bool(app.game.placement_preview(candidate).valid): invalid=candidate;break
		if invalid.x>=0: break
	check(invalid.x>=0,"The real map has an invalid deployment position for feedback")
	await motion(app.game._screen(invalid))
	app._update_placement_feedback()
	check(app.hint_line.text==str(app.game.placement_preview(invalid).reason) and app.game.gold==initial_gold,"Invalid cursor shows the actual rejection reason without spending")
	await motion(app.game._screen(point))
	app._update_placement_feedback()
	check(app.hint_line.text==app.placement_guidance,"Moving back to a valid position clears the rejection reason")
	# The passive report was already tested by the unchanged learning integration.
	# Clear that temporary overlay only for unobstructed ghost/toolbar captures.
	app.learning_field.clear()
	await capture("ghost")
	await motion(app.army_toolbar.get_global_rect().get_center())
	app._update_placement_feedback()
	check(not app.game.placement_cursor_visible,"Entering GUI STOP toolbar hides the field ghost")
	check(app.hint_line.text==app.placement_guidance,"Leaving the battlefield restores normal deployment guidance")
	await press(app.army_grid.get_node("DeployCard_spear"),"Swap to spear")
	check(app.game.gold==initial_gold and str(app.game.pending.type)=="spear","Swapping classes stays free and immediately updates the ghost")
	point=legal_point("spear")
	check(point.x>=0,"This actual battlefield has a visible legal spear position")
	await motion(app.game._screen(point))
	await mouse(app.game._screen(point),MOUSE_BUTTON_RIGHT)
	check(app.game.pending.is_empty() and app.game.gold==initial_gold,"Right-click cancels without spending")
	app._update_placement_feedback()
	check(app.hint_line.text==app.placement_guidance and not app.hint_bar.visible,"Cancel clears stale placement failure feedback")
	await press(app.army_grid.get_node("DeployCard_spear"),"Prepare real placement")
	await mouse(app.game._screen(point))
	check(app.game.units.size()==1 and app.game.gold==initial_gold-int(app.progress.unit_definition("spear").cost),"Native viewport input commits one displayed-price deployment")
	check(app.army_panel.visible and app.selected_word.word.jp==app.progress.army_evolution("spear").jp,"Selected inspector retains the correct Japanese identity")
	fits(app.army_panel,app.game.field_rect,"Selected inspector")
	for control in [app.selected_portrait_window,app.selected_word,app.selected_label,app.army_tactics,app.army_health]:
		fits(control,app.army_panel.get_global_rect(),"Inspector "+str(control.name))
	check(app.army_tactics.get_combined_minimum_size().y<=app.army_tactics.size.y+1,"Tactical state/HP text fits the inspector")
	check(app.selected_label.get_combined_minimum_size().y<=app.selected_label.size.y+1,"Training and attack statistics fit the inspector")
	check(not app.hint_bar.visible,"Selected-unit information has no overlapping instruction strip")
	await capture("battle")
	check(int(app.progress.data.army.currency)==wallet,"UI actions preserve permanent funds")
	app._show_pause_menu()
	await settle()
	check(app.game.paused and app.modal_context=="pause","Battle menu still pauses the same battle")
	for child in app.modal_body.get_children():
		if child is Button: fits(child,app.modal_scroll.get_global_rect(),"Pause "+child.text)
	app._close_modal()

func intermission_checks(hinted: bool) -> void:
	app.game.begin_placement("archer")
	var pending_before: Dictionary=app.game.pending.duplicate(true)
	var gold_before: int=app.game.gold
	var unit_count: int=app.game.units.size()
	app.game.between_waves=true
	app.game.wave=1
	app._on_state(app.game.snapshot())
	app._show_quiz()
	await settle()
	check(app.context_task_active and app.learning_field.choosing,"Wave report opens the actual full-screen intermission")
	check(app.learning_field.get_global_rect()==root.get_visible_rect(),"Intermission covers the whole viewport")
	check(not app.field_clip.visible and not app.army_toolbar.visible and not app.learning_panel.visible,"Intermission hides world troops, recruitment and passive captions")
	check(not app.game.input_enabled and app.game.between_waves,"Intermission freezes battle input and between-wave simulation")
	check(app.learning_field.mouse_filter==Control.MOUSE_FILTER_STOP and app.learning_field.report_text.base_size==36,"Full-screen learning uses large Japanese ruby and blocks field clicks")
	check(not app.learning_field.report_text.meaning_visible,"Report meaning stays hidden until a hint or result")
	var cards: Array=app.learning_field.target_buttons
	check(cards.size()==app.quiz_task.mission.targets.size(),"Each existing target becomes exactly one large destination card")
	var previous_end: float=0
	for index in range(cards.size()):
		var button: Button=cards[index]
		fits(button,root.get_visible_rect(),"Intermission destination "+str(index))
		check(button.size.x>=280 and button.size.y>=240,"Destination cards are large enough to choose without finding world coordinates")
		check(button.position.x>=previous_end,"Destination cards have distinct non-overlapping hit regions")
		previous_end=button.position.x+button.size.x+10
		check(button.get_node("DestinationImage").texture!=null,"Destination illustration uses the actual selected stage")
		check(button.get_node("DestinationName").text==str(app.quiz_task.mission.targets[index].label.ko),"Card destination keeps the original answer identity")
	await motion(Vector2(28,root.size.y*.5))
	await mouse(Vector2(28,root.size.y*.5))
	app._choose_unit("spear")
	check(app.game.gold==gold_before and app.game.units.size()==unit_count and app.game.pending==pending_before,"Covered field clicks and class calls cannot deploy or change the prepared unit")
	if hinted:
		await press(app.learning_field.hint_button,"Actual report hint")
		check(app.quiz_hinted and app.learning_field.report_text.meaning_visible,"Hint reveals Korean meaning through the real signal")
	await capture("support-choice")
	var answer_index: int=-1
	for index in range(cards.size()):
		if str(cards[index].name)=="LearningTarget_"+str(app.quiz_task.mission.answerId): answer_index=index
	check(answer_index>=0,"A visible card maps to the original correct target ID")
	if current_dimensions==Vector2i(1440,900):
		var event=InputEventKey.new()
		event.keycode=KEY_1+answer_index
		event.pressed=true
		Input.parse_input_event(event)
		await settle()
	else:
		await mouse(cards[answer_index].get_global_rect().get_center())
	check(app.quiz_resolved and app.learning_field.resolved,"Actual large-card click or number key resolves the same learning task")
	check(app.game.gold==gold_before+(25 if hinted else 70),"Intermission preserves the actual hint-dependent reward")
	check(app.game.learning_supports.size()>0 and int(app.game.learning_supports.back().duration)==(6 if hinted else 12),"The destination answer still activates its real timed battlefield support")
	check(app.learning_field.continue_button.text.contains("복귀"),"Result provides an explicit return action")
	await capture("support-result")
	await press(app.learning_field.continue_button,"Return to battle")
	check(not app.context_task_active and app.game.input_enabled and app.field_clip.visible and app.army_toolbar.visible and app.learning_panel.visible,"Returning restores the real field, eight classes and transparent captions")
	check(app.game.pending==pending_before and app.game.units.size()==unit_count,"An unpaid prepared unit returns intact without being deployed")
	app.game.cancel_recruit()

func ordinary_intermission_checks() -> void:
	var types: Array=["meaning","sentence","listening"]
	for index in range(types.size()):
		app.game.begin_placement("archer")
		var pending_before: Dictionary=app.game.pending.duplicate(true)
		var gold_before: int=app.game.gold
		app.game.between_waves=true
		app.game.wave=2
		app._on_state(app.game.snapshot())
		if index==2:
			# Issue a real listening session task to verify both enabled and unavailable
			# speech UI; this is not evidence that Windows TTS was heard by a person.
			app.quiz_task=app.lesson_session.next_task(app.seen_this_run,2,true)
			app.quiz_hinted=false
			app.quiz_resolved=false
			app.quiz_feedback_text=""
		app._show_quiz()
		await settle()
		check(str(app.quiz_task.kind)==str(types[index]),"Actual session issues the expected "+str(types[index])+" card task")
		check(app.modal!=null and app.modal_context=="quiz" and app.modal.get_global_rect()==root.get_visible_rect(),"All question kinds use a full-screen focus transition")
		check(not app.field_clip.visible and not app.map_title.visible and not app.hud_gold.visible and not app.army_toolbar.visible,"Ordinary intermission hides world, HUD and recruitment")
		check(app.modal_card.get_theme_stylebox("panel") is StyleBoxEmpty and app.modal_card.size.x>=1184,"Quiz is a broad screen rather than the former narrow boxed modal")
		check(app.quiz_choices.size()==4 and app.quiz_grid.columns==4,"Ordinary questions present four independent side-by-side answer cards")
		check(not app.modal_scroll.get_h_scroll_bar().is_visible_in_tree() and not app.modal_scroll.get_v_scroll_bar().is_visible_in_tree(),"Question and answer cards fit without scrolling")
		for button in app.quiz_choices:
			fits(button,app.modal_scroll.get_global_rect(),"Ordinary answer card")
			check(button.size.x>=280 and button.size.y>=260 and button.get_theme_font_size("font_size")==28,"Answer hit regions and Korean sentences are comfortably large")
		check(not app.quiz_ruby.meaning_visible,"Quiz translation remains conditional on actual hint usage")
		await mouse(Vector2(28,root.size.y*.5))
		app._choose_unit("spear")
		check(app.game.gold==gold_before and app.game.pending==pending_before,"Full-screen ordinary questions cannot alter the prepared unit or spend funds")
		if index==2:
			var audio_button: Button=app.quiz_hint_button.get_parent().get_child(1)
			check(audio_button.disabled==app.japanese_voice.is_empty(),"Listening control reflects the actual local voice capability")
			check(str(app.quiz_ruby.word.jp)=="音声を聞いてください","Listening starts with its prompt rather than showing the answer word")
		await capture(str(types[index])+"-choice")
		if index==1:
			await press(app.quiz_hint_button,"Actual sentence hint")
			check(app.quiz_hinted and app.quiz_ruby.meaning_visible,"Sentence hint displays its whole Korean sentence")
		if index==2:
			var event=InputEventKey.new()
			event.keycode=KEY_ESCAPE
			event.pressed=true
			Input.parse_input_event(event)
			await settle()
			check(app.game.gold==gold_before,"Listening skip grants no answer reward")
		else:
			var answer_index: int=-1
			for choice_index in range(app.quiz_choices.size()):
				if str(app.quiz_task.choices[choice_index].id)==str(app.quiz_task.answerId): answer_index=choice_index
			check(answer_index>=0,"A visible answer card has the original issued answer ID")
			var answer_point: Vector2=app.quiz_choices[answer_index].get_global_rect().get_center()
			if index==1:
				var event=InputEventKey.new()
				event.keycode=KEY_1+answer_index
				event.pressed=true
				Input.parse_input_event(event)
				await settle()
			else:
				await mouse(answer_point)
			check(app.quiz_resolved and app.game.gold==gold_before+(25 if index==1 else 70),"Actual answer click/number key preserves the correct hint-dependent reward")
			var after_answer: int=app.game.gold
			await mouse(answer_point)
			check(app.game.gold==after_answer,"Repeated input on a resolved card cannot grant a duplicate reward")
			if index==1: await capture("sentence-result")
			await press(app.quiz_continue_button,"Return from ordinary question")
		check(app.modal==null and app.field_clip.visible and app.map_title.visible and app.army_toolbar.visible and app.learning_panel.visible,"Every ordinary question restores the battlefield and persistent controls")
		check(app.game.pending==pending_before,"Every question preserves the unpaid placement preview")
		app.game.cancel_recruit()

func intermission_layouts() -> void:
	var field=load("res://native/learning_field.gd").new()
	field.font=app.font
	field.size=Vector2(1280,800)
	root.add_child(field)
	await settle()
	var total:=0
	for plan in app.learning_plans.get("stages",{}).values():
		for mission in plan.get("missions",[]):
			field.begin_choice(mission,false)
			field.show_hint()
			await process_frame
			check(field.report_card.position.y+field.report_card.size.y+8<=field.target_buttons[0].position.y,"Hinted report fits above cards: "+str(mission.id))
			for button in field.target_buttons:
				check(button.size.y>=210 and button.position.y+button.size.y+8<=field.action_card.position.y,"Long report still leaves usable destination cards: "+str(mission.id))
				for child in button.get_children():
					if child is Control: check(Rect2(Vector2.ZERO,button.size).grow(1).encloses(Rect2(child.position,child.size)),"Destination contents fit: "+str(mission.id))
			total+=1
	check(total==120,"All 120 authored reports retain a full-screen layout at the minimum viewport")
	field.queue_free()
	await settle()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/premium-ui/"):
		quit(2)
		return
	capture_enabled=OS.get_cmdline_user_args().has("--capture")
	intermission_capture=OS.get_cmdline_user_args().has("--intermission-capture")
	battle_refresh=OS.get_cmdline_user_args().has("--battle-refresh")
	capture_enabled=capture_enabled or intermission_capture or battle_refresh
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2);return
	var fixture=Store.new()
	fixture.save_path="user://premium-ui-%d.json"%Time.get_ticks_msec()
	fixture.data.settings={"music":false,"voice":false,"effects":false}
	check(fixture.write_save(),"Isolated fresh campaign fixture saves")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=fixture.save_path
	root.add_child(app)
	await settle()
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.player.stop()
	app.player.stream=null
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		current_dimensions=dimensions
		root.size=dimensions
		root.content_scale_size=dimensions
		app._show_home()
		await settle()
		check(app.front_end.visible and app.front_end.view=="home","Home navigation is preserved at "+str(dimensions))
		label_bounds(app.front_end,"Home "+str(dimensions))
		await capture("home")
		await press(named(app.front_end,"HomeBarracks"),"Home to barracks")
		check(app.barracks.visible,"Home barracks action opens the actual roster")
		var hero: Control=named(app.barracks,"SelectedArmyPortrait")
		check(hero!=null and hero.diagnostics().ready and str(hero.diagnostics().unitId)==str(app.barracks.selected_unit_id),"Barracks keeps the approved standing character")
		label_bounds(app.barracks,"Barracks "+str(dimensions))
		var roster_row: Node=named(app.barracks,"ArmyCard_archer")
		for child in roster_row.get_children():
			if child is TextureRect:
				var expected: AtlasTexture=UIStyle.bust_texture(Portrait.first_frame_texture("archer"),"archer")
				check(child.texture.region==expected.region,"Barracks and recruitment use the same approved bust crop")
		await capture("barracks")
		for button in app.barracks.find_children("*","Button",true,false):
			if button.text=="돌아가기":
				await press(button,"Barracks return")
				break
		await press(named(app.front_end,"HomeSortie"),"Home to stage catalog")
		check(app.front_end.view=="catalog","Sortie action opens the actual stage list")
		check(named(app.front_end,"Stage_basic-forest")!=null,"Actual first stage is selectable")
		await press(named(app.front_end,"Stage_basic-river"),"Select river preview")
		var matched:=false
		for texture in app.front_end.find_children("*","TextureRect",true,false):
			if texture.texture!=null and texture.texture.resource_path==str(app.maps[3].background): matched=true
		check(matched,"Selected catalog preview matches the exact stage background")
		await press(named(app.front_end,"Stage_basic-forest"),"Restore first stage")
		label_bounds(app.front_end,"Catalog "+str(dimensions))
		await capture("catalog")
		await press(named(app.front_end,"CatalogSortie"),"Catalog sortie")
		check(app.modal_context=="briefing" and app.modal_footer!=null,"Sortie retains briefing and its fixed action footer")
		fits(app.modal_footer,app.modal_card.get_global_rect(),"Briefing footer")
		check(app.modal_scroll.get_global_rect().end.y<=app.modal_footer.get_global_rect().position.y,"Briefing scroll does not cover the sortie action")
		await press(app.modal_footer.get_child(0),"Briefing begin")
		app.game.set_process(false)
		await battle_checks()
		await intermission_checks(dimensions!=Vector2i(1280,800))
		await ordinary_intermission_checks()
	await intermission_layouts()

	var report={"checks":checks,"failures":failures,"images":images,"profile":profile,"driver":DisplayServer.get_name(),"resourceRoot":ProjectSettings.globalize_path("res://"),"scope":"Fresh isolated campaign; 3 viewport sizes; real home/barracks/catalog/briefing/toolbar/menu/support callbacks and Godot Input.parse_input_event dispatch. No OS-native mouse claims. Product progression, price and learning contracts remain unchanged."}
	var file=FileAccess.open("user://qa_premium_ui.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	app.battle_audio.shutdown()
	await create_timer(.5).timeout
	app.queue_free()
	await settle()
	print("PREMIUM_UI_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
