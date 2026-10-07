extends "res://tests/qa_historical_map_ui.gd"
## Dispatches actual Godot GUI mouse events through production screens.

func gui_click(control: Control) -> void:
	var point: Vector2=control.get_global_rect().get_center()
	var target: String=str(control.get_path())
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	await settle(2)
	var hovered: Control=root.gui_get_hovered_control()
	observations.append({"kind":"mouseClick","target":target,"point":point,"hovered":str(hovered.get_path()) if hovered!=null else "none"})
	for pressed in [true,false]:
		var event: InputEventMouseButton=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true)
		await settle(2)
	await settle(6)

func gui_wheel(scroll: ScrollContainer, down: bool=true, count: int=16) -> void:
	var point: Vector2=scroll.get_global_rect().get_center()
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	await settle(2)
	for index in range(count):
		var event: InputEventMouseButton=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		event.pressed=true
		root.push_input(event,true)
		await settle(1)
		event.pressed=false
		root.push_input(event,true)
	await settle(6)

func shot(label: String) -> void:
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=Vector2(8,8)
	motion.global_position=motion.position
	root.push_input(motion,true)
	await settle(3)
	await super.shot(label)

func new_front() -> Control:
	var front: Control=Front.new()
	front.maps=maps
	front.progress=account
	front.font=Fonts.body()
	front.campaign_story=story
	front.learning_plans=plans
	root.add_child(front)
	return front

func selected_pin_tooltip(atlas: Control) -> void:
	var pin: Button=atlas.get_node("AtlasPin_02")
	check(atlas.selected_stage_id==maps[1].id,"Compact tooltip is captured for the actual selected stage2 pin")
	check(pin.tooltip_text.split("\n").size()==3,"Pin tooltip contains only battle, historical place and current place lines")
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=pin.get_global_rect().get_center()
	motion.global_position=motion.position
	root.push_input(motion,true)
	await create_timer(1.0).timeout
	var tooltip_nodes: Array=[]
	var pending: Array=root.get_children(true)
	while not pending.is_empty():
		var node: Node=pending.pop_back()
		pending.append_array(node.get_children(true))
		if node is Window and node.visible:
			tooltip_nodes.append({"name":node.name,"class":node.get_class(),"rect":Rect2(node.position,node.size)})
			check(node.size.x<root.size.x*.6,"Actual tooltip popup remains substantially narrower than the window")
	check(not tooltip_nodes.is_empty(),"Actual hovered stage2 pin opens its native tooltip popup")
	observations.append({"kind":"selectedStage2Tooltip","text":pin.tooltip_text,"visibleTooltipNodes":tooltip_nodes})
	await super.shot("interaction_atlas_pin_tooltip_1280")
	var tooltip_report: Dictionary={"checks":checks,"failures":failures,"captures":captures,"selectedStageId":atlas.selected_stage_id,"text":pin.tooltip_text,"visibleTooltipNodes":tooltip_nodes}
	var tooltip_file: FileAccess=FileAccess.open("res://tests/qa_historical_map_ui_tooltip.json",FileAccess.WRITE)
	tooltip_file.store_string(JSON.stringify(tooltip_report,"\t"))
	tooltip_file.close()

func run() -> void:
	scope="isolated profile"
	var prefix: String="c:/jp_df/tests/profiles/historical-map-ui/"
	var appdata: String=OS.get_environment("APPDATA").replace("\\","/").to_lower().trim_suffix("/")
	var localdata: String=OS.get_environment("LOCALAPPDATA").replace("\\","/").to_lower().trim_suffix("/")
	check(appdata.begins_with(prefix) and localdata.begins_with(prefix),"Both environment paths are isolated")
	check(OS.get_user_data_dir().replace("\\","/").to_lower().begins_with(appdata+"/"),"Actual user:// path is isolated")
	check(FileAccess.file_exists(appdata+"/profile_guard.json"),"Profile guard file exists before fixtures are created")
	if not failures.is_empty(): quit(2); return
	capture=true
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	story=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	geography=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json"))
	plans=JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	account=Store.new()
	account.save_path="user://historical-map-ui-must-not-be-written.json"
	root.size=Vector2i(1280,800)
	root.content_scale_size=Vector2i(1280,800)
	complete_through(0)
	var atlas: Control=Atlas.new()
	atlas.configure(account,maps,story,geography,Fonts.body())
	root.add_child(atlas)
	atlas.show_stage(str(maps[0].id),false)
	await settle(12)
	scope="fresh atlas mouse navigation"
	check(atlas.get_node("AtlasChapterFilter").item_count==1,"Fresh chapter chooser exposes only chapter1")
	check(atlas.revealed_ids==[maps[0].id,maps[1].id],"Future battles remain hidden behind immediate stage2")
	await shot("interaction_fresh_atlas_1280")
	if "--tooltip-only" in OS.get_cmdline_user_args():
		await gui_click(atlas.get_node("AtlasPin_02"))
		await selected_pin_tooltip(atlas)
		atlas.free()
		await settle(12)
		await release_preview_resources()
		quit(0 if failures.is_empty() else 1)
		return
	await gui_click(atlas.get_node("AtlasPin_02"))
	check(atlas.selected_stage_id==maps[1].id,"Actual pin mouse click selects stage2")
	var selected_place: Control=atlas.get_node("SelectedPlaceCallout")
	var selected_labels: Dictionary=maps[1].historicalBattlefield.atlasLabels
	check(selected_place.get_node("CalloutHistoricPlace").text==selected_labels.historicPlaceKo and selected_place.get_node("CalloutModernPlace").text==selected_labels.modernPlaceKo,"Actual numbered-pin click replaces the single old/modern place card")
	check(selected_place.get_node("CalloutHistoricPlace").position.y<selected_place.get_node("CalloutModernPlace").position.y,"Actual selected card keeps today's place below historic place")
	check(atlas.action_button.disabled and not atlas.gate_button.visible,"Uncleared stage1 keeps stage2 sortie disabled without an exam shortcut")
	await shot("interaction_stage2_locked_before_clear_1280")
	await selected_pin_tooltip(atlas)
	account.data.maps[maps[0].id]={"wins":1}
	atlas.show_stage(str(maps[1].id),false)
	await settle(10)
	check(atlas.action_button.disabled and atlas.gate_button.visible,"Cleared stage1 exposes its required exam while stage2 stays locked")
	var exam: Dictionary={}
	atlas.assessment_requested.connect(func(id): exam["id"]=id,CONNECT_ONE_SHOT)
	await gui_click(atlas.gate_button)
	check(exam.get("id")==maps[0].id,"Actual exam button mouse event requests stage1 assessment")
	await shot("interaction_stage2_locked_exam_1280")
	complete_through(10)
	atlas.show_stage(str(maps[10].id),false)
	await settle(10)
	check(atlas.get_node("AtlasChapterFilter").item_count==2,"Reaching chapter2 keeps chapters3/4 absent from chooser")
	check(atlas.pin_groups.size()==2,"New chapter reveals only stage11 and immediate locked stage12")
	await shot("interaction_next_chapter_hidden_future_1280")
	complete_through(40)
	atlas.show_stage(str(maps[25].id),false)
	await settle(10)
	scope="atlas mouse scrolling and zoom"
	var details_before: int=atlas.detail_scroll.scroll_vertical
	await gui_wheel(atlas.detail_scroll)
	check(atlas.detail_scroll.scroll_vertical>details_before,"Mouse wheel scrolls long historical details")
	await gui_wheel(atlas.stage_scroll)
	check(atlas.stage_scroll.scroll_vertical>0,"Mouse wheel reaches lower stage list entries")
	text_geometry(atlas)
	await shot("interaction_atlas26_details_scrolled_1280")
	await gui_click(atlas.get_node("JapanZoom"))
	check(atlas.all_japan and atlas.bounds==Atlas.JAPAN,"Actual Japan-wide zoom button changes geographic bounds")
	check(atlas.pin_groups.size()==10,"Japan-wide zoom retains only the current chapter's10 battles")
	text_geometry(atlas)
	await shot("interaction_atlas3_japan_full_1280")
	await gui_click(atlas.get_node("CampaignZoom"))
	check(not atlas.all_japan and atlas.bounds==Atlas.CAMPAIGN,"Actual regional zoom returns to enlarged campaign geography")
	atlas.free()
	await settle(10)
	var front: Control=new_front()
	front.selected_stage=0
	front.show_catalog(3,false)
	await settle(45)
	scope="catalog mouse list and facts scrolling"
	var list_scroll: ScrollContainer=front.get_node("StageCatalogScroll")
	await gui_wheel(list_scroll)
	check(list_scroll.scroll_vertical>0,"Mouse wheel scrolls the ten-stage catalog")
	var final_row: Control=front.find_child("Stage_"+str(maps[39].id),true,false)
	check(list_scroll.get_global_rect().grow(1).encloses(final_row.get_global_rect()),"Final stage row becomes completely visible after mouse scrolling")
	await gui_click(final_row)
	check(front.selected_stage==9,"Actual final row click selects stage40")
	var preview: Control=front.get_node("CatalogBattlefieldPreview")
	check(preview.diagnostics().terrain.stageId==maps[39].id,"Actual selected row replaces native3D terrain with stage40")
	var facts: ScrollContainer=front.get_node("StageTacticalDescriptionScroll")
	var before: int=facts.scroll_vertical
	await gui_wheel(facts)
	check(facts.scroll_vertical>before,"Mouse wheel reveals the facts panel's final result lines")
	var modes: Dictionary={}
	front.battle_minutes_selected.connect(func(minutes): modes["minutes"]=minutes)
	await gui_click(front.get_node("BattleMinutes20"))
	check(modes.get("minutes")==20,"Actual20minute button click reaches existing mode signal")
	await gui_click(front.get_node("BattleMinutes10"))
	check(modes.get("minutes")==10,"Actual10minute button click reaches existing mode signal")
	text_geometry(front)
	await shot("interaction_catalog40_facts_scrolled_1280")
	front.free()
	await settle(20)
	complete_through(0)
	front=new_front()
	front.selected_stage=1
	front.show_catalog(0,false)
	await settle(40)
	scope="catalog predecessor lock"
	check(front.get_node("CatalogSortie").disabled,"Locked catalog sortie remains disabled")
	check(front.get_node("MapUnlockRequirement").text.contains("01단계"),"Stage2 catalog explains the real stage1 predecessor")
	text_geometry(front)
	await shot("interaction_catalog2_locked_1280")
	front.free()
	await settle(20)
	check(not FileAccess.file_exists(account.save_path),"GUI interactions never write player or fixture progress")
	await release_preview_resources()
	var report: Dictionary={"checks":checks,"failures":failures,"captures":captures,"observations":observations,"appData":appdata,"localAppData":localdata,"actualUserDataDir":OS.get_user_data_dir(),"inputMethod":"Actual InputEventMouseMotion and InputEventMouseButton events dispatched by Godot Window.push_input to production GUI; mouse coordinates are viewport-local","sourceScope":"UI and atlas source build; no PCK assertion","cleanup":cleanup}
	var output: FileAccess=FileAccess.open("res://tests/qa_historical_map_ui_interactions.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("HISTORICAL_MAP_UI_INTERACTIONS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
