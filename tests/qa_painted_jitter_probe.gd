extends SceneTree
## Isolated movement diagnostic. This does not establish visual/gameplay acceptance.
const Before = preload("res://tests/profiles/painted-jitter-05/source-before/crowd_melee.gd")
const Current = preload("res://native/crowd_melee.gd")

func _initialize() -> void:
	call_deferred("run")

func scenario(script: Script, positions: Array, release_at: int = -1) -> Dictionary:
	var crowd = script.new()
	var actor: Dictionary={"id":2,"position":Vector2.ZERO,"hp":100.0}
	var allies: Array=[actor]
	for index in range(positions.size()):
		allies.append({"id":index+20,"position":positions[index],"hp":100.0})
	var goal: Vector2=Vector2(.08,0)
	var previous_step: Vector2=Vector2.ZERO
	var reversals: int=0
	var travelled: float=0.0
	var max_step: float=0.0
	var held_distance: float=0.0
	var samples: Array=[]
	for tick in range(250):
		if tick==release_at:
			held_distance=actor.position.distance_to(goal)
			allies=[actor]
		crowd.rebuild(allies,[])
		var origin: Vector2=actor.position
		var desired: Vector2=origin.move_toward(goal,.0021)
		actor.position=crowd.move_point(actor,desired,true,func(_a:Vector2,_b:Vector2)->bool:return true,goal,true)
		crowd.moved(actor,origin,true)
		var step: Vector2=actor.position-origin
		if step.length()>.00001 and previous_step.length()>.00001 and step.normalized().dot(previous_step.normalized())<-.5:
			reversals+=1
		travelled+=step.length()
		max_step=maxf(max_step,step.length())
		previous_step=step
		if tick%10==0: samples.append({"tick":tick,"x":actor.position.x,"y":actor.position.y})
	return {"reversalsOver120":reversals,"travelled":travelled,"remaining":actor.position.distance_to(goal),"maxStep":max_step,"distanceAtRelease":held_distance,"samples":samples}

func run() -> void:
	var cases: Dictionary={
		"occupied_goal":[Vector2(.075,0)],
		"overlapping_blockers":[Vector2(.075,0),Vector2(.075,0)],
		"separate_blockers":[Vector2(.075,.008),Vector2(.075,-.008)],
		"single_blocker_open_sides":[Vector2(.04,0)],
		"free_route_around":[Vector2(.04,.006),Vector2(.04,-.006)],
		"open_lane":[]
	}
	var result: Dictionary={"scope":"Actual original/current Crowd movement functions, static local fixtures; not natural combat or visual acceptance","before":{},"current":{}}
	for name in cases:
		result.before[name]=scenario(Before,cases[name])
		result.current[name]=scenario(Current,cases[name])
	result.before["blockers_removed"]=scenario(Before,cases.overlapping_blockers,150)
	result.current["blockers_removed"]=scenario(Current,cases.overlapping_blockers,150)
	var path: String="res://tests/profiles/painted-jitter-05/probe-%d.json" % int(Time.get_unix_time_from_system())
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		push_error("Cannot save jitter probe evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("JITTER_PROBE "+ProjectSettings.globalize_path(path))
	quit(0)
