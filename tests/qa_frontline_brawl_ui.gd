extends SceneTree
const Store=preload("res://native/progress.gd")
var app: Node
var checks: int=0
var failures: Array=[]
var evidence: Dictionary={}

func _initialize() -> void: call_deferred("run")
func check(value: bool, note: String) -> void:
	checks+=1
	if not value: failures.append(note);push_error("FRONTLINE_UI "+note)
func settle() -> void:
	for unused in range(5): await process_frame

func pointer(point: Vector2, pressed: bool, motion: bool=false) -> void:
	var event: InputEvent
	if motion:
		event=InputEventMouseMotion.new()
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	else:
		event=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position=point;event.global_position=point
	Input.parse_input_event(event)
	await settle()

func zone_named(game: Node2D, id: String) -> Dictionary:
	for zone in game.zones:
		if str(zone.get("id",""))==id: return zone
	return {}

func stationary_survey(game: Node2D, zone: Dictionary) -> Dictionary:
	var found: Vector2=Vector2(-1,-1)
	var reasons: Dictionary={}
	var checked: int=0
	var center: Dictionary=game.deployment_preview("archer",zone.position)
	for ring in range(6):
		for sector in range(1 if ring==0 else 24):
			var point: Vector2=zone.position+Vector2.from_angle(float(sector)*TAU/24.0)*float(zone.get("r",.08))*float(ring)/5.0
			var preview: Dictionary=game.deployment_preview("archer",point)
			checked+=1
			if bool(preview.ok) and str(game._eligible_zone(point,"archer").get("id",""))==str(zone.id):
				found=point
				break
			var reason: String=str(preview.get("reason",""))
			reasons[reason]=int(reasons.get(reason,0))+1
		if found.x>=0: break
	return {"point":found,"checked":checked,"centerPreview":center,"rejectionReasons":reasons}

func drag_archer_order(game: Node2D, point: Vector2, note: String) -> Dictionary:
	var card: Node=app.army_grid.get_node_or_null("DeployCard_archer")
	check(card is Button and card.is_inside_tree() and card.is_visible_in_tree() and card.get_viewport()==root,note+": actual archer card is available")
	if not card is Button or not card.is_visible_in_tree(): return {}
	# Copy screen values before dispatch; a state update may replace the card.
	var origin: Vector2=card.get_global_rect().get_center()
	var destination: Vector2=game.field_point_to_screen(point)
	var wallet: int=game.gold
	var queued: int=game.recruitment_queue.size()
	await pointer(origin,false,true)
	await pointer(origin,true)
	await pointer(origin.lerp(destination,.5),true,true)
	await pointer(destination,true,true)
	var preview: Dictionary=app.deployment_drag.get("preview",{}).duplicate(true)
	check(bool(preview.get("ok",false)) and int(preview.get("quantity",0))==2,note+": native drag previews two paid Lv5 archers")
	await pointer(destination,false)
	check(game.recruitment_queue.size()==queued+1 and game.gold==wallet-int(preview.get("cost",0)),note+": one drop commits exactly one paid order")
	if game.recruitment_queue.size()!=queued+1: return {}
	var job: Dictionary=game.recruitment_queue[-1]
	var valid_pair: bool=str(job.type)=="archer" and int(job.quantity)==2 and job.memberPositions.size()==2
	check(valid_pair,note+": queue reserves two real squad members")
	if not valid_pair: return {}
	return job.duplicate(true)

func archer_pair_ui(game: Node2D) -> void:
	var auxiliary: Dictionary=zone_named(game,"inside-auxiliary-pad")
	check(not auxiliary.is_empty(),"Real Stage01 includes the authored auxiliary pad")
	if not auxiliary.is_empty():
		var pair_survey: Dictionary=stationary_survey(game,auxiliary)
		var saved_level: int=int(game.campaign_levels.get("archer",1))
		game.campaign_levels["archer"]=1
		var single_survey: Dictionary=stationary_survey(game,auxiliary)
		game.campaign_levels["archer"]=saved_level
		check(pair_survey.point.x<0,"Existing auxiliary geometry cannot fit the Lv5 archer pair")
		evidence["auxiliaryPad"]={"zoneId":str(auxiliary.id),"radius":float(auxiliary.r),"pairFits":pair_survey.point.x>=0,"pairCenterPreview":pair_survey.centerPreview,"pairRejectionReasons":pair_survey.rejectionReasons,"pairProbes":pair_survey.checked,"lv1SingleFits":single_survey.point.x>=0,"lv1CenterPreview":single_survey.centerPreview,"lv1RejectionReasons":single_survey.rejectionReasons,"lv1Position":game._normalized_position(single_survey.point),"scope":"Actual preview and bounded pad survey only; terrain and collisions unchanged. Pair placement remains unsupported here."}
	var posts: Array=[]
	for id in ["left-shoulder-pad","right-shoulder-pad"]:
		var zone: Dictionary=zone_named(game,id)
		check(not zone.is_empty(),"Actual main ranged zone exists: "+id)
		if zone.is_empty(): continue
		var survey: Dictionary=stationary_survey(game,zone)
		check(survey.point.x>=0,"Actual main pad accepts a legal Lv5 pair: "+id)
		if survey.point.x>=0: posts.append({"id":id,"point":survey.point})
	if posts.size()!=2: return
	var wallet: int=game.gold
	var cancelled: Dictionary=await drag_archer_order(game,posts[0].point,"Cancellation probe")
	if cancelled.is_empty(): return
	var reserved: Dictionary=game.deployment_preview("archer",posts[0].point)
	check(not bool(reserved.ok) and str(reserved.reason).contains("예약"),"Queued pair blocks a second order on its reserved anchor")
	for position in cancelled.memberPositions:
		var member_preview: Dictionary=game.deployment_preview("archer",position)
		check(not bool(member_preview.ok) and str(member_preview.reason).contains("예약"),"Both queued member positions reject a conflicting paid order")
	var queue_size: int=game.recruitment_queue.size()
	var paid_wallet: int=game.gold
	var rejected: Dictionary=game.submit_deployment("archer",posts[0].point)
	check(not bool(rejected.ok) and game.gold==paid_wallet and game.recruitment_queue.size()==queue_size,"Reserved-anchor submission neither charges nor creates an order")
	var cancel_card: Node=app.production_cards.get_node_or_null("RecruitmentJob_%d" % int(cancelled.id))
	check(cancel_card is Button and cancel_card.is_visible_in_tree(),"The actual paid archer order exposes its cancellation card")
	if not cancel_card is Button or not cancel_card.is_visible_in_tree(): return
	var cancel_point: Vector2=cancel_card.get_global_rect().get_center()
	await pointer(cancel_point,false,true)
	await pointer(cancel_point,true)
	await pointer(cancel_point,false)
	var cancelled_once: bool=game.recruitment_queue.size()==queue_size-1 and game.gold==wallet
	check(cancelled_once,"One actual production-card click cancels the whole pair and refunds once")
	if not cancelled_once:
		evidence["mainArcherPairs"]={"cancelledJobId":int(cancelled.id),"firstCancelClickSucceeded":false,"gold":game.gold,"queuedOrders":game.recruitment_queue.size()}
		return
	var refund_wallet: int=game.gold
	check(not game.cancel_recruitment(int(cancelled.id)) and game.gold==refund_wallet,"A cancelled order cannot refund twice")
	check(bool(game.deployment_preview("archer",posts[0].point).ok),"Cancellation releases both member reservations for another paid pair")
	var jobs: Array=[]
	for post in posts:
		var job: Dictionary=await drag_archer_order(game,post.point,"Main pad "+str(post.id))
		if job.is_empty(): continue
		jobs.append(job)
		for position in job.memberPositions:
			check(str(game._eligible_zone(position,"archer").get("id",""))==str(post.id),"Reserved archer member stays within its own legal real pad")
		check(job.memberPositions[0].distance_to(job.memberPositions[1])>=.0259,"Each paid pair reserves distinct physical positions")
	check(jobs.size()==2 and game.gold==wallet-int(game.recruit_cost("archer"))*2,"Both main pairs use the existing Stage01 wallet and one cost per order")
	game.advance_simulation(2.2)
	await settle()
	var archers: Array=[]
	var post_counts: Dictionary={}
	var paid_total: int=0
	for unit in game.units:
		if str(unit.type)!="archer": continue
		archers.append(unit)
		var id: String=str(unit.deploymentZoneId)
		post_counts[id]=int(post_counts.get(id,0))+1
		paid_total+=int(unit.paid)
		check(int(unit.campaignLevel)==5 and unit.position==unit.homePosition and str(game._eligible_zone(unit.position,"archer").get("id",""))==id,"Produced Lv5 archer has an independent legal home in its assigned main pad")
	check(archers.size()==4 and int(post_counts.get("left-shoulder-pad",0))==2 and int(post_counts.get("right-shoulder-pad",0))==2,"Actual paid production creates two archers at each main pad")
	check(paid_total==int(game.recruit_cost("archer"))*2 and game.recruitment_queue.is_empty(),"Produced member payments conserve the two completed order costs")
	for first in range(archers.size()):
		for second in range(first+1,archers.size()):
			check(archers[first].position.distance_to(archers[second].position)>=.0259,"All four produced archers occupy separate physical positions")
	var actors: Dictionary={}
	var hit_targets: Dictionary={}
	var targets: Array=[]
	game.game_event.connect(func(event: Dictionary):
		if str(event.get("type",""))=="shot" and str(event.get("side",""))=="friendly" and str(event.get("unitType",""))=="archer": actors[int(event.actorId)]=true
		if str(event.get("type",""))=="hit" and str(event.get("unitType",""))=="archer" and float(event.get("damage",0))>0: hit_targets[int(event.get("victimId",-1))]=true
	)
	for post in posts:
		var zone: Dictionary=zone_named(game,str(post.id))
		var nearest: Vector2=Vector2(INF,INF)
		var selected_path: int=-1
		var selected_segment: int=-1
		var shortest: float=INF
		for path_index in range(game.paths.size()):
			var points: Array=game.paths[path_index].points
			for segment in range(points.size()-1):
				var point: Vector2=Geometry2D.get_closest_point_to_segment(zone.position,points[segment],points[segment+1])
				var distance: float=point.distance_to(zone.position)
				if distance<shortest and game.ground_combat.land_segment_safe(point,point,.002):
					nearest=point;shortest=distance;selected_path=path_index;selected_segment=segment
		check(selected_path>=0,"Controlled attack witness has a real legal road point near "+str(post.id))
		if selected_path<0: continue
		var enemy: Dictionary=game._spawn_enemy("heavy",3,{"pathIndex":selected_path})
		enemy.position=nearest;enemy.pointIndex=selected_segment+1
		enemy.routeProgress=game.ground_combat.point_distance(selected_path,selected_segment,nearest)
		targets.append(enemy)
	for unused in range(120): game.advance_simulation(.025)
	var all_fired: bool=archers.size()==4
	for unit in archers: all_fired=all_fired and actors.has(int(unit.id))
	check(all_fired,"Every paid archer at both real main pads releases an attack through normal simulation")
	var damaged: bool=targets.size()==2
	var target_health: Array=[]
	for enemy in targets:
		damaged=damaged and float(enemy.hp)<float(enemy.maxHp) and hit_targets.has(int(enemy.id))
		target_health.append({"id":int(enemy.id),"hp":float(enemy.hp),"maxHp":float(enemy.maxHp)})
	check(damaged,"Actual projectiles damage controlled road enemies near both main pads")
	evidence["mainArcherPairs"]={"posts":posts,"cancelledJobId":int(cancelled.id),"firstCancelClickSucceeded":true,"reservationReason":str(reserved.reason),"completedJobs":jobs.map(func(job: Dictionary): return int(job.id)),"archers":archers.map(func(unit: Dictionary): return {"id":int(unit.id),"zoneId":str(unit.deploymentZoneId),"home":game._normalized_position(unit.homePosition),"paid":int(unit.paid)}),"shotActorIds":actors.keys(),"archerHitTargetIds":hit_targets.keys(),"targetHealth":target_health,"attackWindowSeconds":3.0,"scope":"Real native card drag and cancellation, actual paid production and legal member geometry. Controlled heavy enemies use real road points and normal simulation; this is not a natural combat or performance sample."}
	await settle()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(ProjectSettings.globalize_path("res://tests/profiles/frontline-brawl-01/").replace("\\","/").to_lower()): quit(2);return
	var saved=Store.new()
	saved.save_path="user://frontline-ui-fixture.json"
	saved.data.settings={"music":false,"voice":false,"effects":false}
	saved.data.army.levels={"archer":5,"spear":4}
	check(saved.write_save(),"UI fixture is saved only in isolated QA profile")
	root.size=Vector2i(1440,900);root.content_scale_size=root.size
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=saved.save_path
	root.add_child(app)
	await settle()
	app._select_map(0);app._begin_battle()
	app.game.set_process(false)
	app.set_process(false)
	app.player.stop();app.battle_audio.set_enabled(false)
	await settle()
	var game: Node2D=app.game
	game.enemies.clear();game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=10000
	var legal: Array=[]
	for zone in game.zones:
		if str(zone.get("placementRole",""))!="ranged": continue
		var found: Vector2=Vector2(-1,-1)
		for ring in range(5):
			if found.x>=0: break
			for sector in range(24):
				var point: Vector2=zone.position+Vector2.from_angle(float(sector)*TAU/24.0)*(float(zone.get("r",.08))*float(ring)/4.0)
				var preview: Dictionary=game.deployment_preview("spear",point)
				if bool(preview.ok) and bool(preview.get("supportDeployment",false)):
					found=point;break
		check(found.x>=0,"Actual terrain has legal marching support around "+str(zone.id))
		if found.x>=0: legal.append({"zone":str(zone.id),"point":found})
	if not legal.is_empty():
		var card: Button=app.army_grid.get_node("DeployCard_spear")
		var origin: Vector2=card.get_global_rect().get_center()
		var destination: Vector2=game.field_point_to_screen(legal[0].point)
		var wallet: int=game.gold
		await pointer(origin,false,true)
		await pointer(origin,true)
		await pointer(origin.lerp(destination,.5),true,true)
		await pointer(destination,true,true)
		check(not app.deployment_drag.is_empty() and bool(app.deployment_drag.preview.get("supportDeployment",false)),"Actual native pointer drag shows one-brawl support preview")
		await pointer(destination,false)
		check(game.recruitment_queue.size()==1 and bool(game.recruitment_queue[0].destination.get("supportDeployment",false)) and game.gold==wallet-25,"Single actual card drop commits one paid three-member support order")
		game.advance_simulation(1.3)
		await settle()
		check(game.units.size()==3,"Native drag produces the upgraded three real spearmen")
	await archer_pair_ui(game)
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		root.size=dimensions;root.content_scale_size=dimensions
		app._layout();game._emit_state()
		await settle()
		check(app.hud_capacity.text.contains("제한 없음") and not app.hud_capacity.text.contains("/"),"Actual HUD reports unlimited deployment at "+str(dimensions))
		check(not app.recruit_button.disabled,"Actual recruit control remains available without queue-cap comparisons at "+str(dimensions))
	evidence.merge({"legalSupportPosts":legal,"units":game.units.size(),"gold":game.gold,"hud":app.hud_capacity.text,"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"profile":profile})
	var output: FileAccess=FileAccess.open("res://tests/qa_frontline_brawl_ui.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"scope":"Real Stage01 terrain/navigation, actual native card drags and order cancellation, paid spear squad and main-pad Lv5 archer pairs, reservations/member validity, controlled projectile attacks, auxiliary pair/single preview limitations, 1440/1280 HUD. Headless verifies interactions/layout data; no rendered image or FPS claim."},"  "));output.close()
	print("FRONTLINE_UI checks=",checks," failures=",failures.size())
	app._cancel_learning_transition();app.player.stop();app.player.stream=null;app.battle_audio.shutdown()
	app.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
