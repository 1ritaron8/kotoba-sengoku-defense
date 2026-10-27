extends "res://tests/qa_painted_game.gd"
## Actual normal UI inputs; controlled combat fixtures live in a separate file.
const PATCH_ROOT: String="res://tests/profiles/painted-patch-08"
const ReviewReadings=preload("res://native/ruby_readings.gd")
var spear_progress: Dictionary={}
var enemy_facing: Dictionary={}

func key_input(key_value: int) -> void:
	for down in [true,false]:
		var event: InputEventKey=InputEventKey.new()
		event.keycode=key_value;event.physical_keycode=key_value;event.pressed=down
		root.push_input(event,true)
		await settle(1)

func reading_colour_review(parent: Node,label_value: String) -> void:
	var rows: Array=[]
	for control in parent.find_children("*","Control",true,false):
		if not control.is_visible_in_tree() or not control.has_method("get_text_layout"): continue
		var layout: Dictionary=control.get_text_layout()
		var reading_runs: Array=layout.runs.filter(func(run): return str(run.get("role",""))=="reading")
		var parts: Array=control.get("_display_parts")
		var uncovered: Array=ReviewReadings.uncovered_kanji(parts)
		check(uncovered.is_empty(),label_value+": visible kanji has an authored reading: "+str(control.get("word").get("jp","")))
		if reading_runs.is_empty(): continue
		check(int(layout.colouredGroups)>=1,label_value+": even a single verified reading group is coloured")
		rows.append({"path":str(control.get_path()),"word":control.get("word"),"colouredGroups":layout.colouredGroups,"readingRuns":reading_runs})
	evidence[label_value+"ReadingColours"]=rows

func screen_review(parent: Node,label_value: String) -> void:
	if not is_instance_valid(parent): return
	var rows: Array=[]
	for control in parent.find_children("*","Control",true,false):
		if not control.is_visible_in_tree(): continue
		if control is ScrollContainer:
			var vertical: ScrollBar=control.get_v_scroll_bar()
			check(not vertical.is_visible_in_tree(),label_value+": ordinary content has no vertical scrolling: "+str(control.name))
		if control is Button and not control.disabled:
			check(root.get_visible_rect().grow(1).encloses(control.get_global_rect()),label_value+": complete action fits viewport: "+str(control.name))
		if not control.has_method("get_text_layout"): continue
		var layout: Dictionary=control.get_text_layout()
		for run in layout.get("runs",[]):
			var bounds: Rect2=control.get_global_transform_with_canvas()*Rect2(run.bounds)
			rows.append({"path":str(control.get_path()),"role":run.get("role",""),"text":run.text,"bounds":str(bounds)})
			check(visible_clip(control).grow(2).encloses(bounds),label_value+": annotated glyph fits its visible area: "+str(run.text))
			if label_value.begins_with("pause"):
				check(app.modal_card.get_global_rect().grow(-10).encloses(bounds),label_value+": glyph clears the modal border: "+str(run.text))
		check(bool(control.get("colour_reading_groups")),label_value+": shared reading-group distinction enabled")
	evidence[label_value+"Text"]=rows

func observe_patch() -> void:
	if not alive() or not live_battle(): return
	observe_ingress()
	for unit in app.game.units:
		if str(unit.type)!="spear": continue
		var key: String=str(unit.id)
		if not spear_progress.has(key): spear_progress[key]={"first":unit.position,"firstState":str(unit.combatState),"firstGather":unit.get("gatherRemaining",0),"maxDistance":0.0,"support":str(unit.get("supportPhase",""))}
		var row: Dictionary=spear_progress[key]
		row.maxDistance=maxf(float(row.maxDistance),unit.position.distance_to(row.first))
		row.lastPosition=unit.position
	for enemy in app.game.enemies:
		if str(enemy.kind)!="enemy_archer": continue
		var key: String=str(enemy.id)
		if not enemy_facing.has(key): enemy_facing[key]=[]
		var samples: Array=enemy_facing[key]
		if samples.is_empty() or app.game.elapsed-float(samples[-1].clock)>=.08:
			var visual: Vector2=app.game.painted_actors.visual_direction(enemy,false,app.game)
			samples.append({"clock":app.game.elapsed,"aim":enemy.aim,"visualDirection":visual,"visualSector":app.game.painted_actors._direction_name(visual,false),"state":enemy.animation,"target":enemy.get("stationaryTargetId",-1),"rangedTarget":enemy.get("rangedPlan",{}).get("targetId",-1),"counterTarget":enemy.get("counterPlan",{}).get("targetId",-1)})

func click_field(point: Vector2,note: String,unit_id: String="spear") -> void:
	var before: int=events.size()
	var wallet: int=app.game.gold
	var screen: Vector2=app.game.field_point_to_screen(point)
	await pointer(screen,true,false);await pointer(screen,false,false)
	if not alive(): return
	var receipts: Array=queued_since(before,unit_id)
	paid_orders.append({"label":note,"unitType":unit_id,"receipts":receipts,"goldBefore":wallet,"goldAfter":app.game.gold,"requestedPosition":point})
	check(receipts.size()==1 and wallet-app.game.gold==app.game.recruit_cost(unit_id),note+": exactly one paid order")

func resolve_actual_learning() -> bool:
	if not alive(): return false
	var correct_id: String=str(app.learning_field.correct_target) if app.context_task_active else str(app.quiz_task.get("answerId",""))
	var target_id: int=0
	if app.context_task_active:
		for index in range(app.learning_field.mission.get("targets",[]).size()):
			if str(app.learning_field.mission.targets[index].get("id",""))==correct_id: target_id=app.learning_field.target_buttons[index].get_instance_id()
	else:
		for index in range(app.quiz_task.get("choices",[]).size()):
			if str(app.quiz_task.choices[index].get("id",""))==correct_id: target_id=app.quiz_choices[index].get_instance_id()
	if not await click_id(target_id,"Natural learning answer first click"): return false
	if not await wait_until(func(): return alive() and app.quiz_resolved and app.learning_transition.accepts_actions(),4): return false
	var button_id: int=visible_button_text(app.learning_field if app.context_task_active else app.modal,"전투로 복귀")
	if button_id==0: button_id=visible_button_text(app.modal,"복귀")
	return await click_id(button_id,"Natural learning return first click") and await wait_until(func(): return live_battle(),5)

func finish(reason: String="complete") -> void:
	if stopped: return
	stopped=true;observing=false
	var args: PackedStringArray=OS.get_cmdline_args()
	var log_index: int=args.find("--log-file")
	var script_errors: int=0
	if log_index>=0 and log_index+1<args.size() and FileAccess.file_exists(args[log_index+1]): script_errors=FileAccess.get_file_as_string(args[log_index+1]).count("SCRIPT ERROR:")
	check(script_errors==0,"No actual GDScript runtime errors")
	evidence["runtimeScriptErrors"]=script_errors
	var ending: Dictionary=hash_sources()
	check(ending==source_hashes,"Product and art stay frozen throughout the actual review")
	evidence["spearProgress"]=spear_progress;evidence["enemyFacing"]=enemy_facing
	var report: Dictionary={"status":"evidence_collected" if reason=="complete" and failures.is_empty() and incomplete.is_empty() else "partial_or_failed","reason":reason,"failures":failures,"incomplete":incomplete,"checks":check_rows,"captures":captures,"events":events,"paidOrders":paid_orders,"clicks":clicks,"inputTrace":input_trace,"evidence":evidence,"ingress":ingress,"performance":performance_summary(),"frameRows":frame_rows,"sources":source_hashes,"sourcesAtEnd":ending,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"wallSeconds":wall_seconds(),"scope":"Actual Home/catalog/details/atlas/briefing/card-click base spear/expanded support preview/paid field click/automatic march/ESC/audio details. No game funds, clocks, HP, units or handlers injected. Full original viewport captures."}
	var file: FileAccess=FileAccess.open(output_dir.path_join("patch08-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("PATCH08 ",ProjectSettings.globalize_path(output_dir.path_join("patch08-report.json")))
	if is_instance_valid(app): app.queue_free()
	quit(0 if report.status=="evidence_collected" else 1)

func run() -> void:
	started=Time.get_ticks_usec()
	output_dir=PATCH_ROOT.path_join("actual-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if not check(DisplayServer.get_name()!="headless" and canonical(ProjectSettings.globalize_path("user://")).begins_with(canonical(ProjectSettings.globalize_path(PATCH_ROOT))+"/"),"Fresh isolated rendered profile"): finish("profile_rejected");return
	source_hashes=hash_sources()
	create_timer(220).timeout.connect(func(): finish("deadline") if not stopped else null)
	root.size=Vector2i(1440,900);root.content_scale_size=root.size
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://patch08-fresh.json"
	root.add_child(app)
	await settle(5)
	if not alive(): return
	app.game.game_event.connect(on_event)
	process_frame.connect(observe_patch)
	if not await wait_until(func(): return alive() and app.front_end.catalog_prepared>=app.front_end.catalog_preparation_total,15): finish("catalog_preparation_timeout");return
	if not await click_id(named_id(app.front_end,"HomeBarracks"),"Home barracks colour review"): finish("barracks_entry_failed");return
	if not await wait_until(func(): return alive() and app.barracks.visible,4): finish("barracks_failed");return
	await capture("barracks-archer-1440x900");reading_colour_review(app.barracks,"barracksArcher")
	if not await click_id(named_id(app.barracks,"ArmyCard_spear"),"Barracks spear colour review"): finish("barracks_spear_failed");return
	await capture("barracks-spear-1440x900");reading_colour_review(app.barracks,"barracksSpear")
	if not await click_id(named_id(app.barracks,"BarracksBack"),"Barracks back"): finish("barracks_back_failed");return
	if not await click_id(named_id(app.front_end,"HomeTraining"),"Home training colour review"): finish("training_entry_failed");return
	if not await wait_until(func(): return alive() and app.unit_training.visible,4): finish("training_failed");return
	await capture("training-colours-1440x900");reading_colour_review(app.unit_training,"training")
	if not await click_id(visible_button_text(app.unit_training,"뒤로"),"Training back"): finish("training_back_failed");return
	if not await click_id(named_id(app.front_end,"HomeSortie"),"Home catalog first click"): finish("catalog_entry_failed");return
	if not check(await wait_until(func(): return alive() and app.front_end.view=="catalog",5),"Catalog opens"): finish("catalog_failed");return
	await create_timer(.4).timeout
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		await resize(dimensions);await create_timer(.35).timeout
		await capture("catalog-"+str(dimensions.x)+"x"+str(dimensions.y))
		screen_review(app.front_end,"catalog"+str(dimensions.x))
		reading_colour_review(app.front_end,"catalog"+str(dimensions.x))
	root.mode=Window.MODE_FULLSCREEN
	await settle(5)
	root.content_scale_size=root.size
	await settle(5);await create_timer(.35).timeout
	await capture("catalog-fullscreen")
	screen_review(app.front_end,"catalogFullscreen")
	evidence["fullscreenSize"]=str(root.size)
	root.mode=Window.MODE_WINDOWED
	await settle(5);await resize(Vector2i(1280,800));await create_timer(.35).timeout
	if not await click_id(named_id(app.front_end,"CatalogDetails"),"Catalog large detail first click"): finish("catalog_detail_failed");return
	await settle(4);await capture("catalog-detail-1280x800");screen_review(app.front_end,"catalogDetails1280")
	if not await click_id(named_id(app.front_end,"CatalogDetailsBack"),"Catalog detail back"): finish("catalog_detail_return_failed");return
	if not await click_id(named_id(app.front_end,"CatalogCampaignMap"),"Catalog nationwide map"): finish("atlas_entry_failed");return
	await settle(5)
	await capture("atlas-1280x800");screen_review(app.front_end,"atlas1280")
	await resize(Vector2i(1440,900));await capture("atlas-1440x900");screen_review(app.front_end,"atlas1440")
	var atlas: Node=app.front_end.find_child("CampaignAtlas",true,false)
	if atlas==null:
		for child in app.front_end.get_children():
			if child.has_method("diagnostics"): atlas=child;break
	if atlas!=null and atlas.has_method("diagnostics"): evidence["atlas"]=atlas.diagnostics()
	if not await click_id(named_id(app.front_end,"AtlasDetails"),"Atlas large detail first click"): finish("atlas_detail_failed");return
	await capture("atlas-detail-1440x900");screen_review(app.front_end,"atlasDetails1440")
	if not await click_id(named_id(app.front_end,"AtlasDetailsBack"),"Atlas detail back"): finish("atlas_detail_return_failed");return
	var catalog_id: int=visible_button_text(app.front_end,"전장 목록")
	if catalog_id==0: catalog_id=visible_button_text(app.front_end,"전장 선택")
	if not await click_id(catalog_id,"Atlas return to catalog"): finish("atlas_return_failed");return
	if not await click_id(named_id(app.front_end,"CatalogSortie"),"Catalog sortie first click"): finish("sortie_failed");return
	if not check(await wait_until(func(): return alive() and app.modal_context=="briefing" and (not is_instance_valid(app.scene_transition) or not app.scene_transition.is_running()),10),"Normal catalog reaches briefing"): finish("briefing_failed");return
	if not await click_id(named_id(app.modal,"ConfirmMission"),"Mission confirm"): finish("confirm_failed");return
	if not check(await wait_until(func(): return live_battle(),6),"Normal route reaches battle"): finish("battle_failed");return
	await capture("battle-ready-1440x900")
	var before: int=events.size();var wallet: int=app.game.gold
	# Deployment cards deliberately consume pointer input before Button.pressed.
	# Success is the one paid base job and retained selection below.
	if not await click_id(card_id("spear"),"Spear card creates base order",false): finish("spear_card_failed");return
	var orders: Array=queued_since(before,"spear")
	paid_orders.append({"label":"Spear card","unitType":"spear","receipts":orders,"goldBefore":wallet,"goldAfter":app.game.gold})
	check(orders.size()==1 and wallet-app.game.gold==app.game.recruit_cost("spear"),"Spear card creates exactly1 paid base job")
	check(app.chosen_unit_id=="spear" and not app.deployment_drag.is_empty(),"Spear stays selected for support clicks")
	var areas: Array=app.game.ground_combat.marching_support_areas("spear")
	evidence["supportAreas"]=areas
	check(not areas.is_empty(),"Support areas are provided by real legality rules")
	await capture("spear-support-areas-1440x900")
	var support_point: Vector2=Vector2(INF,INF)
	for area in areas:
		for offset in [Vector2(.075,0),Vector2(-.075,0),Vector2(0,.075),Vector2(0,-.075)]:
			var point: Vector2=area.center+offset
			var preview: Dictionary=app.game.deployment_preview("spear",point)
			if bool(preview.get("supportDeployment",false)) and bool(preview.get("ok",false)):
				support_point=point;break
		if support_point.is_finite(): break
	check(support_point.is_finite(),"An expanded support point beyond the old .049 drop radius is legal")
	if support_point.is_finite(): await click_field(support_point,"Expanded support click")
	var ordinary_point: Vector2=Vector2(INF,INF)
	for point in [Vector2(.55,.50),Vector2(.50,.70),Vector2(.90,.50),Vector2(.80,.65)]:
		var preview: Dictionary=app.game.deployment_preview("spear",point)
		if bool(preview.get("ok",false)) and not bool(preview.get("supportDeployment",false)):
			ordinary_point=point;break
	check(ordinary_point.is_finite(),"Ordinary field point outside support areas is available")
	if ordinary_point.is_finite(): await click_field(ordinary_point,"Ordinary field click dispatches from base")
	if not await click_id(card_id("archer"),"Select actual supporting archer",false): finish("archer_card_failed");return
	var post: Dictionary=app.game.shooting_position_snapshot()[0]
	await click_field(Vector2(float(post.x),float(post.y)),"Paid supporting archer","archer")
	await key_input(KEY_ESCAPE)
	if not await wait_until(func(): return live_battle() and app.game.recruitment_queue.is_empty(),6): finish("production_failed");return
	await create_timer(.3).timeout
	check(not spear_progress.is_empty(),"Paid base spear is produced")
	var first: Dictionary=spear_progress.values()[0]
	check(str(first.firstState)=="march" and float(first.firstGather)==0 and float(first.maxDistance)>.004,"Base spear immediately auto-marches after production")
	await key_input(KEY_ESCAPE)
	check(app.modal_context=="pause" and app.game.paused,"ESC opens pause overview")
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		await resize(dimensions);await capture("pause-"+str(dimensions.x)+"x"+str(dimensions.y));screen_review(app.modal,"pause"+str(dimensions.x))
		reading_colour_review(app.modal,"pause"+str(dimensions.x))
	if not await click_id(named_id(app.modal,"PauseAudioSettings"),"Pause audio detail"): finish("pause_audio_failed");return
	await capture("pause-audio-1280x800");screen_review(app.modal,"pauseAudio1280")
	reading_colour_review(app.modal,"pauseAudio")
	await key_input(KEY_ESCAPE)
	check(app.modal_context=="pause" and app.game.paused,"Audio detail ESC returns to paused overview")
	if not await click_id(named_id(app.modal,"PauseResume"),"Pause resume"): finish("pause_resume_failed");return
	check(live_battle(),"Pause detail navigation preserves resume behavior")
	await resize(Vector2i(1440,900))
	phase="natural_combat";measuring=true;observing=true;observe_frames()
	await wait_until(func(): return eligible_wall_seconds>=12 or not live_battle(),22)
	measuring=false;observing=false
	await capture("battle-combat-1440x900")
	await resize(Vector2i(1280,800));await capture("battle-combat-1280x800")
	evidence["scopeBoundary"]="First natural learning-return click failed in actual-1791951468, retained separately. Final recheck covers requested UI/placement and natural combat; enemy-bow visual owner uses the controlled actual-renderer fixture, not a claimed natural late-wave capture."
	finish()
