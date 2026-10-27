extends "res://tests/qa_painted_jitter06.gd"
## Same actual-input route as click03, with the newly authorized range bounds.
const BALANCE_ROOT: String="res://tests/profiles/painted-balance-07"
var balance_enemy_births: Dictionary={}
var balance_attack_starts: Array=[]
var balance_attack_keys: Dictionary={}
var balance_population: Dictionary={}

func observe_departures() -> void:
	super.observe_departures()
	if not alive() or not live_battle(): return
	var game=app.game
	var wave_key: String=str(game.wave)
	if not balance_population.has(wave_key): balance_population[wave_key]={"maxAlive":0,"firstClock":game.elapsed,"lastClock":game.elapsed}
	var population: Dictionary=balance_population[wave_key]
	population.maxAlive=maxi(int(population.maxAlive),game.enemies.size())
	population.lastClock=game.elapsed
	for enemy in game.enemies:
		var key: String=str(enemy.id)
		if not balance_enemy_births.has(key):
			balance_enemy_births[key]={"kind":str(enemy.kind),"originKind":str(enemy.get("originKind","")),"sourceWave":int(enemy.sourceWave),"maxHp":float(enemy.maxHp),"armor":float(enemy.armor),"clock":game.elapsed,"position":enemy.position}
	for unit in game.units:
		if str(unit.type)!="archer": continue
		var plan: Dictionary=unit.get("attackPlan",{})
		if str(unit.get("animation",""))!="attack" or plan.is_empty(): continue
		var key: String=str(unit.id)+":"+str(plan.get("targetId",-1))+":"+str(game.elapsed-float(unit.animationClock)).left(12)
		# One observation at the beginning of each actual attack animation.
		if float(unit.animationClock)>.04 or balance_attack_keys.has(key): continue
		balance_attack_keys[key]=true
		var target: Dictionary=game._enemy(int(plan.get("targetId",-1)))
		if target.is_empty(): continue
		var attack_range: float=float(game._stats(unit).range)
		var distance: float=unit.position.distance_to(target.position)
		balance_attack_starts.append({"actorId":unit.id,"targetId":target.id,"clock":game.elapsed,"elevation":unit.get("elevation",0),"range":attack_range,"distance":distance})
		check(distance<=attack_range+.003,"Natural archer begins attacking inside its shortened range (one-frame motion tolerance)")

func finish(reason: String="complete") -> void:
	if stopped: return
	evidence["balanceEnemyBirths"]=balance_enemy_births
	evidence["balanceAttackStarts"]=balance_attack_starts
	evidence["balanceWavePopulation"]=balance_population
	if reason=="complete":
		check(not balance_attack_starts.is_empty(),"Actual paid archers attack with shortened range")
		check(balance_enemy_births.size()>=10,"Natural stage supplies multiple enemy groups")
	super.finish(reason)

func run() -> void:
	started=Time.get_ticks_usec()
	output_dir=BALANCE_ROOT.path_join("actual-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if not check(DisplayServer.get_name()!="headless" and canonical(ProjectSettings.globalize_path("user://")).begins_with(canonical(ProjectSettings.globalize_path(BALANCE_ROOT))+"/"),"Fresh isolated rendered QA profile"): finish("profile_rejected");return
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
		var actor: Dictionary=app.game.ground_combat._unit(int(unit.id))
		check(not actor.is_empty(),"Paid archer is still present for its range observation")
		if not actor.is_empty():
			check(is_equal_approx(float(unit.range),.284704 if int(actor.get("elevation",0))==2 else .179375),"Actual paid archer uses the reduced Stage01 high/grass range")
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
