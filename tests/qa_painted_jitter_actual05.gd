extends "res://tests/qa_painted_click03.gd"
## Observe real paid units through the existing Home/learning route.
var jitter_tracks: Dictionary={}
var jitter_samples: Array=[]
var jitter_capture_started: bool=false
var jitter_capture_complete: bool=false

func observe_departures() -> void:
	super.observe_departures()
	if not alive() or not live_battle():
		jitter_tracks.clear()
		return
	var clock_value: float=app.game.elapsed
	for unit in app.game.units:
		if str(unit.type) not in ["spear","samurai","commander"] or float(unit.hp)<=0: continue
		var key: String=str(unit.id)
		var position_value: Vector2=unit.position
		var state_value: String=str(unit.get("combatState",""))
		if jitter_tracks.has(key):
			var prior: Dictionary=jitter_tracks[key]
			var displacement: Vector2=position_value-prior.position
			if displacement.length()>.00002:
				var previous: Vector2=prior.get("lastStep",Vector2.ZERO)
				var searching: bool=state_value in ["march","advance","charge","support_advance","support_return"] and str(prior.state) in ["march","advance","charge","support_advance","support_return"]
				if searching and previous.length()>.00002 and clock_value-float(prior.get("lastMoveClock",-100.0))<=.2 and displacement.normalized().dot(previous.normalized())<-.5:
					jitter_samples.append({"actorId":unit.id,"clock":clock_value,"targetId":unit.get("targetId",-1),"state":state_value,"position":str(position_value),"previousStep":str(previous),"step":str(displacement)})
				prior["lastStep"]=displacement
				prior["lastMoveClock"]=clock_value
			prior["position"]=position_value
			prior["state"]=state_value
		else:
			jitter_tracks[key]={"position":position_value,"state":state_value}
	if clock_value>=31.0 and not jitter_capture_started:
		jitter_capture_started=true
		call_deferred("capture_jitter_brawl")

func capture_jitter_brawl() -> void:
	if not alive() or not live_battle(): return
	await buffered_motion("later-brawl",36,3)
	if not alive(): return
	await capture("later-brawl-full-1440x900")
	jitter_capture_complete=true

func finish(reason: String="complete") -> void:
	if stopped: return
	var max_window: int=0
	for event in jitter_samples:
		var count: int=0
		for other in jitter_samples:
			if int(other.actorId)==int(event.actorId) and int(other.targetId)==int(event.targetId) and float(other.clock)>=float(event.clock) and float(other.clock)<float(event.clock)+.5: count+=1
		max_window=maxi(max_window,count)
	evidence["rapidSearchDirectionReversals"]={"count":jitter_samples.size(),"maxPerActorAndTargetHalfSecond":max_window,"events":jitter_samples,"definition":"Consecutive nontrivial actual advancing-unit displacements reverse >120 degrees within0.2 game seconds, outside pause/learning; not every direction change is a defect"}
	evidence["laterBrawlCaptureComplete"]=jitter_capture_complete
	if reason=="complete":
		check(jitter_capture_complete,"Later naturally populated brawl was captured without injected units or clocks")
		check(max_window<=2,"No repeated back-and-forth oscillation on the same target within half a second")
	super.finish(reason)
