extends "res://tests/qa_painted_clarification02.gd"
## Actual viewport input and naturally paid orders; no battle state injection.
const ROUND_ROOT: String="res://tests/profiles/painted-click-03"
const MassFixture=preload("res://tests/qa_painted_mass03.gd")
const AllRolesFixture=preload("res://tests/qa_painted_all_roles03.gd")
var contact_samples: Array=[]
var seen_many_contacts: bool=false
var release_probed: bool=false

func on_event(event: Dictionary) -> void:
	super.on_event(event)
	if str(event.get("type",""))!="placed" or not alive(): return
	for id_value in event.get("actorIds",[]):
		for actor in app.game.units:
			if int(actor.id)==int(id_value): birth_observations[str(id_value)]={"id":id_value,"type":str(actor.type),"state":actor.get("combatState",""),"gather":actor.get("gatherRemaining",0),"position":actor.position,"clock":app.game.elapsed}

func observe_departures() -> void:
	super.observe_departures()
	if not alive() or not live_battle(): return
	if contact_samples.size()>1200: return
	var pairs: Array=[]
	for unit in app.game.units:
		if str(unit.type)!="spear" or float(unit.hp)<=0: continue
		var ids: Array=unit.get("contactEnemyIds",[])
		if ids.size()>1: seen_many_contacts=true
		if not ids.is_empty(): pairs.append({"actorId":unit.id,"enemyIds":ids.duplicate(),"state":unit.get("combatState",""),"position":str(unit.position)})
	if not pairs.is_empty(): contact_samples.append({"clock":app.game.elapsed,"pairs":pairs})

func select_card(unit_id: String) -> bool:
	var before: int=events.size()
	var wallet: int=app.game.gold
	if not await click_id(card_id(unit_id),"Select "+unit_id+" without paying",false): return false
	return check(app.chosen_unit_id==unit_id and str(app.deployment_drag.get("unitId",""))==unit_id and queued_since(before,unit_id).is_empty() and wallet==app.game.gold,"Card selects "+unit_id+" and creates no order")

func field_order(unit_id: String, point: Vector2, label_value: String) -> bool:
	var before: int=events.size()
	var wallet: int=app.game.gold
	var screen: Vector2=app.game.field_point_to_screen(point)
	await pointer(screen,true,false)
	await pointer(screen,false,false)
	if not alive(): return false
	if not release_probed:
		var receipt_count: int=queued_since(before,unit_id).size()
		var released_wallet: int=app.game.gold
		await pointer(screen,false,false)
		check(queued_since(before,unit_id).size()==receipt_count and app.game.gold==released_wallet,"Duplicate release neither charges nor queues another order")
		release_probed=true
	var receipts: Array=queued_since(before,unit_id)
	paid_orders.append({"label":label_value,"unitType":unit_id,"goldBefore":wallet,"goldAfter":app.game.gold,"receipts":receipts,"requestedPosition":str(point)})
	return check(receipts.size()==1 and wallet-app.game.gold==app.game.recruit_cost(unit_id) and str(app.deployment_drag.get("unitId",""))==unit_id,label_value+": exactly one paid order, selection remains")

func keyboard(key_value: int) -> void:
	for down in [true,false]:
		var event: InputEventKey=InputEventKey.new()
		event.keycode=key_value
		event.physical_keycode=key_value
		event.pressed=down
		root.push_input(event,true)
		await settle(1)

func resolve_learning() -> bool:
	if not alive(): return false
	var correct_id: String=str(app.learning_field.correct_target) if app.context_task_active else str(app.quiz_task.get("answerId",""))
	var target_id: int=0
	if app.context_task_active:
		for index in range(app.learning_field.mission.get("targets",[]).size()):
			if str(app.learning_field.mission.targets[index].get("id",""))==correct_id: target_id=app.learning_field.target_buttons[index].get_instance_id()
	else:
		for index in range(app.quiz_task.get("choices",[]).size()):
			if str(app.quiz_task.choices[index].get("id",""))==correct_id: target_id=app.quiz_choices[index].get_instance_id()
	if not await click_id(target_id,"Answer actual learning first click"): return false
	if not await wait_until(func(): return alive() and app.quiz_resolved and app.learning_transition.accepts_actions(),4): return false
	await capture("reward-"+str(root.size.x))
	var button_id: int=visible_button_text(app.learning_field if app.context_task_active else app.modal,"전투로 복귀")
	if button_id==0: button_id=visible_button_text(app.modal,"복귀")
	return await click_id(button_id,"Learning return first click") and await wait_until(func(): return live_battle(),5)

func finish(reason: String="complete") -> void:
	if stopped: return
	stopped=true
	observing=false
	var args: PackedStringArray=OS.get_cmdline_args()
	var log_at: int=args.find("--log-file")
	var errors: int=0
	if log_at>=0 and log_at+1<args.size() and FileAccess.file_exists(args[log_at+1]): errors=FileAccess.get_file_as_string(args[log_at+1]).count("SCRIPT ERROR:")
	check(errors==0,"No actual runtime script errors")
	var ending: Dictionary=hash_sources()
	check(source_hashes==ending,"Frozen game/art sources remain unchanged during QA")
	evidence["runtimeScriptErrors"]=errors
	evidence["contactSamples"]=contact_samples
	evidence["manyContactsObserved"]=seen_many_contacts
	var shared: Dictionary={}
	for hit in events:
		if str(hit.get("type",""))!="hit" or str(hit.get("side",""))!="friendly" or str(hit.get("unitType",""))!="spear": continue
		var key: String=str(hit.get("victimId",-1))+":"+str(int(float(hit.get("time",0))/2))
		if not shared.has(key): shared[key]=[]
		if not shared[key].has(hit.actorId): shared[key].append(hit.actorId)
	evidence["sharedVictimTwoSecondWindows"]=shared
	evidence["sharedVictimObserved"]=not shared.values().filter(func(ids): return ids.size()>1).is_empty()
	if is_instance_valid(app) and is_instance_valid(app.game): evidence["profileCounters"]=app.game.performance_snapshot()
	var report: Dictionary={"status":"evidence_collected" if failures.is_empty() and incomplete.is_empty() and reason=="complete" else "partial_or_failed","reason":reason,"failures":failures,"incomplete":incomplete,"checks":check_rows,"captures":captures,"events":events,"paidOrders":paid_orders,"clicks":clicks,"inputTrace":input_trace,"births":birth_observations,"evidence":evidence,"frameRows":frame_rows,"performance":performance_summary(),"sources":source_hashes,"sourcesAtEnd":ending,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"wallSeconds":wall_seconds(),"scope":"Actual Home/briefing/select-and-click/repeated paid orders/placement/attack/pause/learning. No funds, levels, units, HP, clocks, positions or gameplay handlers injected. No automatic second click. Full original viewport captures."}
	var file: FileAccess=FileAccess.open(output_dir.path_join("click03-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("CLICK03 ",ProjectSettings.globalize_path(output_dir.path_join("click03-report.json")))
	if is_instance_valid(app): app.queue_free()
	quit(0 if report.status=="evidence_collected" else 1)

func run() -> void:
	started=Time.get_ticks_usec()
	output_dir=ROUND_ROOT.path_join("actual-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if not check(DisplayServer.get_name()!="headless" and canonical(ProjectSettings.globalize_path("user://")).begins_with(canonical(ProjectSettings.globalize_path(ROUND_ROOT))+"/"),"Fresh isolated rendered QA profile"): finish("profile_rejected");return
	source_hashes=hash_sources()
	create_timer(220).timeout.connect(func(): finish("deadline") if not stopped else null)
	root.size=Vector2i(1440,900);root.content_scale_size=root.size
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path="user://click03-fresh.json"
	root.add_child(app)
	await settle(5)
	if not alive(): return
	app.game.game_event.connect(on_event)
	process_frame.connect(observe_departures)
	await key_enter()
	if not check(await wait_until(func(): return alive() and app.modal_context=="briefing" and (not is_instance_valid(app.scene_transition) or not app.scene_transition.is_running()),12),"Home Enter reaches briefing"): finish("briefing_failed");return
	if not await click_id(named_id(app.modal,"ConfirmMission"),"Mission confirm first click"): finish("confirm_failed");return
	if not check(await wait_until(func(): return live_battle(),6),"Normal route reaches real battle"): finish("battle_failed");return
	await capture("battle-ready-1440x900")
	phase="select_click_paid_orders"
	evidence["posts"]=app.game.shooting_position_snapshot().duplicate(true)
	var road_id: String=""
	var road_point: Vector2
	for post in evidence.posts:
		if str(post.id).begins_with("painted-roadside-"):
			road_id=str(post.id);road_point=Vector2(float(post.x),float(post.y));break
	check(not road_id.is_empty(),"Actual grass shooting position exists")
	# A card dragged into the world is no longer a deployment gesture.
	var origin: Vector2=live_button(card_id("spear")).get_global_rect().get_center()
	var target: Vector2=app.game.field_point_to_screen(road_point)
	var event_before: int=events.size()
	await pointer(origin,true,false);await pointer(target,true,true);await pointer(target,false,false)
	check(queued_since(event_before,"spear").is_empty(),"Card drag creates no order")
	if not await select_card("archer"): finish("archer_selection_failed");return
	var locked: Button=live_button(card_id("samurai"))
	check(is_instance_valid(locked) and not "samurai" in app.progress.unlocked_units(),"Locked samurai card exists for release boundary")
	if is_instance_valid(locked):
		var locked_center: Vector2=locked.get_global_rect().get_center()
		var locked_wallet: int=app.game.gold
		var locked_events: int=events.size()
		await pointer(locked_center,true,false);await pointer(locked_center,false,false)
		check(app.game.gold==locked_wallet and queued_since(locked_events,"archer").is_empty() and str(app.deployment_drag.get("unitId",""))=="archer","Locked card release neither pays nor deploys the previous selection")
	var invalid_wallet: int=app.game.gold
	var invalid_point: Vector2=app.game.field_point_to_screen(Vector2(.50,.04))
	await pointer(invalid_point,true,false);await pointer(invalid_point,false,false)
	check(app.game.gold==invalid_wallet,"Invalid stationary point creates no paid order")
	for post_id in ["left-shoulder-pad",road_id]:
		for zone in app.game.zones:
			if str(zone.get("id",""))==post_id:
				if not await field_order("archer",zone.position,"Archer click on "+post_id): finish("archer_order_failed");return
	if not await select_card("spear"): finish("spear_selection_failed");return
	for index in range(4):
		if not await field_order("spear",road_point,"Repeated support order "+str(index+1)): finish("forward_support_failed");return
	var bases: Array=app.game.snapshot().get("marchBases",[])
	var base: Vector2=Vector2(float(bases[0].x),float(bases[0].y))
	# The latest click request includes a passable field point away from the gate.
	var field_point: Vector2=base.lerp(Vector2(1.07,-.05),.22)
	if app.game.gold>=app.game.recruit_cost("spear"):
		if not await field_order("spear",field_point,"Clicked road location outside the gate"): finish("field_location_failed");return
	var burst_start: int=Time.get_ticks_usec()
	var burst_count: int=0
	while burst_count<3 and app.game.gold>=app.game.recruit_cost("spear"):
		if not await field_order("spear",base,"Rapid base order "+str(burst_count+1)): finish("burst_failed");return
		burst_count+=1
	evidence["paidBurst"]={"orders":burst_count,"wallMs":float(Time.get_ticks_usec()-burst_start)/1000.0}
	await capture("selected-sticky-production-1440x900")
	await keyboard(KEY_ESCAPE)
	check(app.deployment_drag.is_empty() and not app.game.ui_deployment_active,"Escape retires free selection")
	if not await wait_until(func(): return live_battle() and app.game.recruitment_queue.is_empty(),6): finish("production_timeout");return
	var independent_ids: Dictionary={}
	for order in paid_orders:
		for queued in order.receipts:
			var completed: Array=events.filter(func(row): return str(row.get("type","")) in ["recruited","placed"] and int(row.get("jobId",-1))==int(queued.jobId))
			check(completed.size()==1,"Paid job completes exactly once: "+str(queued.jobId))
			if completed.size()!=1: continue
			var actor_ids: Array=completed[0].get("actorIds",[])
			check(actor_ids.size()==int(completed[0].get("quantity",1)),"Paid job creates its independent actors: "+str(queued.jobId))
			for id_value in actor_ids:
				check(not independent_ids.has(id_value),"Actor id belongs to one job: "+str(id_value))
				independent_ids[id_value]=true
	evidence["deployedArchers"]=app.game.snapshot().units.filter(func(unit): return str(unit.type)=="archer")
	for unit in evidence.deployedArchers:
		check(float(unit.range)>.23,"Placed archer uses increased real post range")
	await capture("battle-units-grass-1440x900")
	await keyboard(KEY_SPACE)
	check(app.game.paused,"Space pauses actual combat")
	var paused_clock: float=app.game.elapsed
	var paused_positions: Array=[]
	for unit in app.game.units: paused_positions.append(unit.position)
	await create_timer(.4).timeout
	var after_pause: Array=[]
	for unit in app.game.units: after_pause.append(unit.position)
	check(is_equal_approx(app.game.elapsed,paused_clock) and paused_positions==after_pause,"Pause holds combat clock and unit positions")
	await keyboard(KEY_SPACE)
	check(not app.game.paused,"Space resumes actual combat")
	await create_timer(.2).timeout
	check(app.game.elapsed>paused_clock,"Resume advances the combat clock")
	phase="natural_combat";measuring=true;observing=true;observe_frames()
	await wait_until(func(): return eligible_wall_seconds>=12 or not live_battle(),20)
	measuring=false
	phase="natural_group_motion"
	await buffered_motion("natural-group-fight",24,3)
	await capture("battle-combat-1440x900")
	await resize(Vector2i(1280,800));await capture("battle-combat-1280x800")
	phase="learning_wait"
	if not await wait_until(func(): return alive() and app._learning_screen_active() and app.learning_transition.accepts_answers(),55): finish("learning_timeout");return
	await capture("choices-1280x800")
	check(not app.narration_subtitle.visible and not app.announcement_subtitle.visible,"Battle captions stay hidden on the contextual learning screen")
	layout_observation(app.learning_field if app.context_task_active else app.modal,"choices1280")
	await resize(Vector2i(1440,900));await capture("choices-1440x900")
	if not await resolve_learning(): finish("learning_resolution_failed");return
	# Wait for the next genuine quiz; do not inject a quiz or advance game clocks.
	if not await wait_until(func(): return alive() and app._learning_screen_active() and app.learning_transition.accepts_answers(),65):
		incomplete.append("Second natural quiz not reached in bounded wait")
	else:
		await capture("next-quiz-1440x900")
		check(not app.narration_subtitle.visible and not app.announcement_subtitle.visible,"Battle captions stay hidden on the normal quiz screen")
		evidence["nextQuizKind"]=app.quiz_task.get("kind","")
		var background: Node=app.modal.get_node_or_null("QuizBattlefieldBackground") if is_instance_valid(app.modal) else null
		evidence["quizBackgroundMounted"]=background is TextureRect and background.texture!=null
		if str(app.quiz_task.get("kind",""))!="context":
			check(bool(evidence.quizBackgroundMounted) and background.texture==app.game.painted_field.texture,"Normal quiz reuses the actual mounted battlefield texture")
		else: incomplete.append("Normal quiz background not observed")
		await resize(Vector2i(1280,800));await capture("next-quiz-1280x800")
	finish()
