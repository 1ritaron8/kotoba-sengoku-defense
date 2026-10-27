extends "res://tests/qa_painted_game.gd"
## Focused actual-input review. The HQ is the sole engine executor.
const REVIEW_ROOT: String = "res://tests/profiles/painted-clarification-02"
const MainImplementation = preload("res://native/main.gd")
const ReviewUIStyle = preload("res://native/sengoku_ui.gd")
var birth_observations: Dictionary = {}

func home_spacing_observation(label_value: String) -> void:
	if not alive(): return
	var tagline: Control=app.front_end.find_child("HomeTagline",true,false)
	var title: Control=app.front_end.find_child("HomeTitle",true,false)
	var subtitle: Control=app.front_end.find_child("HomeSubtitle",true,false)
	check(is_instance_valid(tagline) and is_instance_valid(title) and is_instance_valid(subtitle),label_value+": existing home labels exist")
	if not is_instance_valid(tagline) or not is_instance_valid(title) or not is_instance_valid(subtitle): return
	check(tagline.get_global_rect().end.y+4<=title.get_global_rect().position.y,label_value+": tagline clears title readings")
	check(title.get_global_rect().end.y+4<=subtitle.get_global_rect().position.y,label_value+": title clears Korean subtitle")
	var outside: Array=[]
	for node in app.front_end.find_children("*","Control",true,false):
		if not node.is_visible_in_tree() or not node.has_method("get_text_layout"): continue
		for run in node.get_text_layout().get("runs",[]):
			var bounds: Rect2=node.get_global_transform_with_canvas()*Rect2(run.bounds)
			if not root.get_visible_rect().grow(2).encloses(bounds): outside.append({"path":str(node.get_path()),"text":str(run.get("text","")),"bounds":str(bounds)})
	evidence[label_value+"ViewportOverflow"]=outside
	check(outside.is_empty(),label_value+": annotated home text remains inside the full viewport")

func on_event(event: Dictionary) -> void:
	super.on_event(event)
	if str(event.get("type",""))!="recruited" or not alive(): return
	for id_value in event.get("actorIds",[]):
		for actor in app.game.units:
			if int(actor.id)!=int(id_value): continue
			birth_observations[str(id_value)]={"id":id_value,"type":str(actor.type),"state":actor.get("combatState",""),"gather":actor.get("gatherRemaining",0),"position":actor.position,"clock":app.game.elapsed}

func observe_departures() -> void:
	if not alive() or not live_battle(): return
	for actor in app.game.units:
		var key: String=str(actor.id)
		if not birth_observations.has(key): continue
		var birth: Dictionary=birth_observations[key]
		if str(birth.type)!="spear" or birth.has("firstMovementAfterSeconds"): continue
		if actor.position.distance_to(birth.position)>.00001:
			birth["firstMovementAfterSeconds"]=app.game.elapsed-float(birth.clock)
			birth["firstMovedPosition"]=actor.position

func observe_frames() -> void:
	var previous: int=Time.get_ticks_usec()
	var previous_eligible: bool=false
	var previous_clock: float=0.0
	var rid: RID=root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	while observing and bounded():
		await RenderingServer.frame_post_draw
		if not observing or not alive(): break
		var now: int=Time.get_ticks_usec()
		var eligible: bool=eligible_now()
		if eligible and previous_eligible and app.game.elapsed>previous_clock:
			var ms: float=float(now-previous)/1000.0
			var gpu: float=RenderingServer.viewport_get_measured_render_time_gpu(rid)
			frame_rows.append({"frameMs":ms,"clock":app.game.elapsed,"friendly":app.game.units.size(),"enemies":app.game.enemies.size(),"drawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"gpuMs":gpu if gpu>0.0 else null})
			eligible_wall_seconds+=ms/1000.0
		previous=now
		previous_eligible=eligible
		previous_clock=app.game.elapsed

func spear_order() -> bool:
	if not alive(): return false
	var bases: Array=app.game.snapshot().get("marchBases",[])
	if not check(not bases.is_empty(),"An actual marching spawn base is available"): return false
	var origin_id: int=card_id("spear")
	var token: String=begin_observation(origin_id,"Paid spear drag to the allied base")
	if token.is_empty(): return false
	var origin: Vector2=await stable_center(origin_id,token)
	if not alive() or not origin.is_finite(): end_observation(token);return false
	var base: Dictionary=bases[0]
	var target: Vector2=app.game.field_point_to_screen(Vector2(float(base.x),float(base.y)))
	var before: int=events.size()
	var wallet: int=app.game.gold
	clicks[token].dispatchCount=1
	await pointer(origin,true,false,token)
	await pointer(origin.lerp(target,.3),true,true,token)
	await pointer(target,true,true,token)
	await pointer(target,false,false,token)
	await settle(2)
	end_observation(token)
	if not alive(): return false
	var receipts: Array=queued_since(before,"spear")
	paid_orders.append({"unitType":"spear","goldBefore":wallet,"goldAfter":app.game.gold,"receipts":receipts,"token":token})
	return check(receipts.size()==1 and wallet-app.game.gold==app.game.recruit_cost("spear"),"One real spear drag pays and queues exactly one order")

func layout_observation(parent: Node, label_value: String) -> void:
	var rows: Array=[]
	for node in parent.find_children("*","Control",true,false):
		if not node.is_visible_in_tree(): continue
		if not (node is Label or node is Button or node.has_method("get_text_layout")): continue
		var row: Dictionary={"name":str(node.name),"path":str(node.get_path()),"bounds":str(node.get_global_rect()),"clip":str(visible_clip(node))}
		if node is Label or node is Button: row["text"]=node.text
		if node.has_method("get_text_layout"):
			row["layout"]=node.get_text_layout().duplicate(true)
			if node.get_parent() is Button:
				var button_parent: Button=node.get_parent()
				var interior: Rect2=button_parent.get_global_transform_with_canvas()*ReviewUIStyle.content_rect(button_parent,"normal")
				var outside: Array=[]
				for run in row.layout.get("runs",[]):
					var bounds: Rect2=node.get_global_transform_with_canvas()*Rect2(run.bounds)
					if not interior.grow(2).encloses(bounds): outside.append({"text":str(run.get("text","")),"bounds":str(bounds)})
				row["buttonInterior"]=str(interior)
				row["inkOutsideInterior"]=outside
				check(outside.is_empty(),label_value+": annotated text fits inside button border: "+str(node.get_path()))
		rows.append(row)
	evidence[label_value+"Text"]=rows

func finish(reason: String="complete") -> void:
	if stopped: return
	stopped=true
	observing=false
	var arguments: PackedStringArray=OS.get_cmdline_args()
	var log_index: int=arguments.find("--log-file")
	var runtime_errors: int=0
	if log_index>=0 and log_index+1<arguments.size() and FileAccess.file_exists(arguments[log_index+1]):
		runtime_errors=FileAccess.get_file_as_string(arguments[log_index+1]).count("SCRIPT ERROR:")
	check(runtime_errors==0,"Actual engine run has no GDScript runtime errors")
	evidence["engineScriptErrorCount"]=runtime_errors
	var ending: Dictionary=hash_sources()
	check(source_hashes==ending,"Product and artwork stay fixed throughout the actual run")
	var report: Dictionary={"status":"evidence_collected" if reason=="complete" and failures.is_empty() else "partial_or_failed","reason":reason,"checks":check_rows,"failures":failures,"incomplete":incomplete,"captures":captures,"events":events,"paidOrders":paid_orders,"clicks":clicks,"birthObservations":birth_observations,"evidence":evidence,"frameRows":frame_rows,"performance":performance_summary(),"sources":source_hashes,"sourcesAtEnd":ending,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"wallSeconds":wall_seconds(),"scope":"Actual Home/barracks/briefing/paid placement/natural movement/correct-answer reward/return. No gameplay funds, levels, clocks, positions or handlers injected. Full original captures; QA geometry is not visual acceptance.","automaticSecondClick":false}
	var file: FileAccess=FileAccess.open(output_dir.path_join("clarification-report.json"),FileAccess.WRITE)
	if file==null: push_error("Cannot write clarification evidence");quit(2);return
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("CLARIFICATION02 ",ProjectSettings.globalize_path(output_dir.path_join("clarification-report.json")))
	if is_instance_valid(app): app.queue_free()
	quit(0 if report.status=="evidence_collected" else 1)

func run() -> void:
	started=Time.get_ticks_usec()
	output_dir=REVIEW_ROOT.path_join("actual-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if not check(DisplayServer.get_name()!="headless" and canonical(ProjectSettings.globalize_path("user://")).begins_with(canonical(ProjectSettings.globalize_path(REVIEW_ROOT))+"/"),"Fresh isolated rendered QA profile"):
		finish("profile_rejected");return
	source_hashes=hash_sources()
	create_timer(180.0).timeout.connect(func(): finish("deadline") if not stopped else null)
	root.size=Vector2i(1440,900);root.content_scale_size=root.size
	app=load("res://native/main.tscn").instantiate()
	if not check(app.get_script()!=null,"Actual Main script loads before the GUI path"):
		finish("main_load_failed");return
	app.progress.save_path="user://clarification02-fresh.json"
	root.add_child(app)
	await settle(4)
	if not alive(): return
	app.game.game_event.connect(on_event)
	process_frame.connect(observe_departures)
	if OS.get_cmdline_user_args().has("--home-only"):
		await create_timer(.35).timeout
		if not alive(): return
	phase="actual_home_barracks"
	await capture("home-1440x900")
	layout_observation(app.front_end,"home1440")
	if OS.get_cmdline_user_args().has("--home-only"): home_spacing_observation("home1440")
	await resize(Vector2i(1280,800))
	if OS.get_cmdline_user_args().has("--home-only"):
		await create_timer(.35).timeout
		if not alive(): return
	await capture("home-1280x800")
	layout_observation(app.front_end,"home1280")
	if OS.get_cmdline_user_args().has("--home-only"):
		home_spacing_observation("home1280")
		finish();return
	if not await click_id(named_id(app.front_end,"HomeSettings"),"Home settings first click"): finish("settings_input_failed");return
	if not check(await wait_until(func(): return alive() and app.front_end.view=="settings",3.0),"Actual settings opens"): finish("settings_destination_failed");return
	await capture("settings-1280x800")
	layout_observation(app.front_end,"settings1280")
	await resize(Vector2i(1440,900))
	await capture("settings-1440x900")
	if not await click_id(visible_button_text(app.front_end,"돌아가기"),"Settings return first click"): finish("settings_return_failed");return
	if not await click_id(named_id(app.front_end,"HomeTraining"),"Home training first click"): finish("training_input_failed");return
	if not check(await wait_until(func(): return alive() and app.unit_training.visible,3.0),"Actual training catalog opens"): finish("training_destination_failed");return
	await capture("training-catalog-1440x900")
	layout_observation(app.unit_training,"training1440")
	await resize(Vector2i(1280,800))
	await capture("training-catalog-1280x800")
	layout_observation(app.unit_training,"training1280")
	if not await click_id(visible_button_text(app.unit_training,"뒤로"),"Training catalog return first click"): finish("training_return_failed");return
	if not await click_id(named_id(app.front_end,"HomeBarracks"),"Home barracks first click"): finish("barracks_entry_failed");return
	if not check(await wait_until(func(): return alive() and app.barracks.visible,3.0),"Actual Home reaches barracks"): finish("barracks_destination_failed");return
	await capture("barracks-archer-1280x800")
	layout_observation(app.barracks,"barracksArcher1280")
	await resize(Vector2i(1440,900))
	await capture("barracks-archer-1440x900")
	layout_observation(app.barracks,"barracksArcher1440")
	if not await click_id(named_id(app.barracks,"ArmyCard_spear"),"Barracks spear selection first click"): finish("barracks_spear_failed");return
	await capture("barracks-spear-1440x900")
	layout_observation(app.barracks,"barracksSpear1440")
	await resize(Vector2i(1280,800))
	await capture("barracks-spear-1280x800")
	layout_observation(app.barracks,"barracksSpear1280")
	if not await click_id(named_id(app.barracks,"BarracksBack"),"Barracks return first click"): finish("barracks_return_failed");return
	await resize(Vector2i(1440,900))
	await key_enter()
	if not check(await wait_until(func(): return alive() and is_instance_valid(app.modal) and app.modal_context=="briefing" and (not is_instance_valid(app.scene_transition) or not app.scene_transition.is_running()),12.0),"Actual Enter reaches briefing"): finish("briefing_failed");return
	await capture("briefing-1440x900")
	layout_observation(app.modal,"briefing1440")
	if not await click_id(named_id(app.modal,"ConfirmMission"),"Mission confirm first click"): finish("confirm_input_failed");return
	if not check(await wait_until(func(): return live_battle(),6.0),"Mission confirm reaches live battle"): finish("confirm_destination_failed");return
	phase="paid_placement"
	evidence["posts"]=app.game.shooting_position_snapshot().duplicate(true)
	check(evidence.posts.size()==8,"Stage01 exposes two original high posts and six allied roadside positions")
	var roadside_id: String=""
	for post in evidence.posts:
		if str(post.id).begins_with("painted-roadside-"):
			roadside_id=str(post.id)
			check(int(post.elevation)==0 and int(post.rangeBonusPercent)==0 and int(post.slotCapacity)==2,"Roadside position has two ground slots and no invented range bonus")
	await capture("battle-ready-1440x900")
	if not await spear_order(): finish("spear_input_failed");return
	await capture("production-ghost-1440x900")
	if not check(await wait_until(func(): return alive() and not birth_observations.is_empty(),5.0),"Paid spear naturally completes production"): finish("production_failed");return
	var birth: Dictionary=birth_observations.values()[0].duplicate(true)
	check(str(birth.state)=="march" and float(birth.gather)==0.0,"New spear begins marching without a gathering wait")
	await create_timer(.2).timeout
	if not alive(): return
	for actor in app.game.units:
		if int(actor.id)==int(birth.id):
			evidence["firstSpearMovement"]={"birth":birth,"afterPosition":actor.position,"afterClock":app.game.elapsed,"distance":actor.position.distance_to(birth.position)}
			check(actor.position.distance_to(birth.position)>.00001,"New spear moves within the first 0.2 seconds after production")
	if not await drag_archer("left-shoulder-pad"): finish("archer_input_failed");return
	if roadside_id.is_empty() or not await drag_archer(roadside_id): finish("roadside_archer_input_failed");return
	for unused in range(4):
		if app.game.gold>=app.game.recruit_cost("spear"):
			if not await spear_order(): finish("additional_spear_input_failed");return
	await capture("paid-production-1440x900")
	await wait_until(func(): return live_battle() and app.game.recruitment_queue.is_empty(),5.0)
	if not live_battle(): finish("production_not_live");return
	await create_timer(.3).timeout
	if not alive(): return
	var spear_births: int=0
	for birth_row in birth_observations.values():
		if str(birth_row.type)!="spear": continue
		spear_births+=1
		check(birth_row.has("firstMovementAfterSeconds") and float(birth_row.get("firstMovementAfterSeconds",999.0))<=.25,"Each paid spear starts moving within 0.25 seconds: "+str(birth_row.id))
	check(spear_births==5,"Five consecutive paid spear births are observed")
	phase="natural_walk_sequence"
	await buffered_motion("natural-walk",48,3)
	if not alive(): return
	await capture("battle-after-walk-1440x900")
	phase="natural_combat"
	measuring=true
	observing=true
	observe_frames()
	await wait_until(func(): return eligible_wall_seconds>=12.0 or not live_battle(),18.0)
	measuring=false
	evidence["combatTimingComplete"]=eligible_wall_seconds>=11.95
	await resize(Vector2i(1280,800))
	await capture("battle-1280x800")
	layout_observation(app.ui,"battle1280")
	phase="correct_answer_wait"
	if not check(await wait_until(func(): return alive() and app.context_task_active and app.learning_transition.accepts_answers(),45.0),"Natural contextual learning appears"): finish("learning_not_reached");return
	await capture("choices-1280x800")
	layout_observation(app.learning_field,"choices1280")
	await resize(Vector2i(1440,900))
	await capture("choices-1440x900")
	var answer: String=str(app.learning_field.correct_target)
	var answer_id: int=0
	var targets: Array=app.learning_field.mission.get("targets",[])
	for index in range(mini(targets.size(),app.learning_field.target_buttons.size())):
		if str(targets[index].get("id",""))==answer: answer_id=app.learning_field.target_buttons[index].get_instance_id()
	var event_start: int=events.size()
	if not await click_id(answer_id,"Correct answer first click"): finish("answer_input_failed");return
	if not check(await wait_until(func(): return alive() and app.quiz_resolved and app.learning_transition.accepts_actions(),4.0),"Correct answer immediately reaches a readable result"): finish("answer_destination_failed");return
	evidence["correctAnswer"]={"feedback":app.quiz_feedback_text,"events":events.slice(event_start),"receipts":app.game.snapshot().get("learningRewardReceipts",[])}
	await capture("correct-reward-1440x900")
	layout_observation(app.learning_field,"correctReward1440")
	await resize(Vector2i(1280,800))
	await capture("correct-reward-1280x800")
	layout_observation(app.learning_field,"correctReward1280")
	var return_id: int=visible_button_text(app.learning_field,"전투로 복귀")
	if not await click_id(return_id,"Correct answer return first click"): finish("return_input_failed");return
	if not check(await wait_until(func(): return live_battle(),5.0),"Learning result returns to live combat"): finish("return_destination_failed");return
	await create_timer(1.0).timeout
	if not alive(): return
	evidence["postReturnHint"]={"visible":app.hint_line.is_visible_in_tree(),"text":app.hint_line.text,"toastVisible":app.toast_label.is_visible_in_tree(),"toastText":app.toast_label.text}
	check(not app.toast_label.text.contains("지급 확정") and not app.toast_label.text.contains("획득 · 전투 복귀 후 발동"),"No correct-answer supply toast leaks into combat after return")
	await capture("return-no-reward-overlay-1280x800")
	finish()
