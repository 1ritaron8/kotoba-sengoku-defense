extends "res://tests/qa_painted_jitter_actual05.gd"
## Real paid production must finish without a completion notice on the field.
var completion_notice_samples: Array=[]
var movement_progress: Dictionary={}

func select_card(unit_id: String) -> bool:
	var accepted: bool=await super.select_card(unit_id)
	if not accepted or not alive(): return false
	return check(app.army_grid.find_children("PlacementReadyBadge","Label",true,false).is_empty(),"Selected unit card has no placement-ready text over its portrait")

func on_event(event: Dictionary) -> void:
	super.on_event(event)
	if str(event.get("type","")) not in ["recruited","placed"] or not alive(): return
	var notice: String=app.toast_label.text if is_instance_valid(app.toast_label) else ""
	var visible: bool=is_instance_valid(app.toast_label) and app.toast_label.is_visible_in_tree()
	completion_notice_samples.append({"eventId":event.get("eventId",-1),"jobId":event.get("jobId",-1),"clock":app.game.elapsed,"notice":notice,"noticeVisible":visible})
	check(not (visible and "생산 완료" in notice),"Actual paid production completes without a completion notice")

func observe_departures() -> void:
	super.observe_departures()
	if not alive() or not live_battle(): return
	for unit in app.game.units:
		if str(unit.type)!="spear": continue
		var key: String=str(unit.id)
		var point: Vector2=unit.position
		if not movement_progress.has(key):
			movement_progress[key]={"firstPosition":point,"maxDisplacement":0.0,"lastPosition":point,"lastState":str(unit.get("combatState","")),"supportPhase":str(unit.get("supportPhase",""))}
		var progress_row: Dictionary=movement_progress[key]
		progress_row.maxDisplacement=maxf(float(progress_row.maxDisplacement),point.distance_to(progress_row.firstPosition))
		progress_row.lastPosition=point
		progress_row.lastState=str(unit.get("combatState",""))
		progress_row.supportPhase=str(unit.get("supportPhase",""))

func finish(reason: String="complete") -> void:
	if stopped: return
	evidence["productionCompletionNotices"]=completion_notice_samples
	evidence["actualMovementProgress"]=movement_progress
	var max_actor_window: int=0
	for event in jitter_samples:
		var count: int=0
		for other in jitter_samples:
			if int(other.actorId)==int(event.actorId) and float(other.clock)>=float(event.clock) and float(other.clock)<float(event.clock)+.5: count+=1
		max_actor_window=maxi(max_actor_window,count)
	evidence["maxRapidReversalsPerActorHalfSecond"]=max_actor_window
	if reason=="complete":
		check(completion_notice_samples.size()==paid_orders.size(),"Every actual paid job finishes with its completion notice checked")
		check(max_actor_window<=2,"A soldier does not repeatedly reverse direction even while its selected enemy changes")
		for key in movement_progress:
			check(float(movement_progress[key].maxDisplacement)>.1,"Paid spear actually advances rather than hiding oscillation by standing still: "+str(key))
		var attackers: Dictionary={}
		for event in events:
			if str(event.get("type",""))=="hit" and str(event.get("side",""))=="friendly" and str(event.get("unitType",""))=="spear" and float(event.get("damage",0))>0:
				attackers[str(event.actorId)]=true
		check(attackers.size()>=3,"Several actual paid spears independently damage enemies")
	super.finish(reason)
