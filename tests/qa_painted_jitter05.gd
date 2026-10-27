extends SceneTree
## HQ runs actual Crowd/Ground regressions. No save, GPU or FPS claim.
const Battle = preload("res://native/game.gd")
const BeforeCrowd = preload("res://tests/profiles/painted-jitter-05/source-before/crowd_melee.gd")
const CurrentCrowd = preload("res://native/crowd_melee.gd")
var checks: int = 0
var failures: Array = []
var evidence: Dictionary = {}
var catalog: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label_value: String) -> void:
	checks+=1
	if not ok:
		failures.append(label_value)
		if failures.size()<=15: push_error("JITTER05 "+label_value)

func crowd_case(script: Script, points: Array, change: String = "") -> Dictionary:
	var crowd = script.new()
	var actor: Dictionary={"id":2,"position":Vector2(.4,.5),"hp":100.0,"targetId":99}
	var allies: Array=[actor]
	for index in range(points.size()): allies.append({"id":20+index,"position":points[index],"hp":100.0})
	var goal: Vector2=Vector2(.48,.5)
	var previous: Vector2=Vector2.ZERO
	var reversals: int=0
	var waiting: int=0
	var travelled: float=0.0
	var max_step: float=0.0
	var release_step: float=0.0
	for tick in range(250):
		if tick==150:
			if change=="removed": allies=[actor]
			elif change=="dead":
				for index in range(1,allies.size()): allies[index].hp=0.0
			elif change=="moved":
				for index in range(1,allies.size()): allies[index].position+=Vector2(0,.06)
			elif change=="new_goal": goal=Vector2(.48,.56)
		crowd.rebuild(allies,[])
		var origin: Vector2=actor.position
		var desired: Vector2=origin.move_toward(goal,.0021)
		var legal: Callable=func(_a: Vector2,b: Vector2)->bool: return b.x<=.44 if change=="wall" else true
		actor.position=crowd.move_point(actor,desired,true,legal,goal,true)
		crowd.moved(actor,origin,true)
		var step: Vector2=actor.position-origin
		if step.length()>.00001 and previous.length()>.00001 and step.normalized().dot(previous.normalized())<-.5: reversals+=1
		if step.length()<=.00001: waiting+=1
		if tick==150: release_step=step.length()
		travelled+=step.length()
		max_step=maxf(max_step,step.length())
		previous=step
		if change=="wall": check(actor.position.x<=.440001,"Physical wall legality remains enforced")
	return {"reversalsOver120":reversals,"travelled":travelled,"remaining":actor.position.distance_to(goal),"maxStep":max_step,"waitingFrames":waiting,"firstReleaseStep":release_step,"targetIdChanges":0,"contactGoalChanges":1 if change=="new_goal" else 0}

func make_game(crowd_script: Script) -> Node2D:
	var game: Node2D=Battle.new()
	game.ground_combat.crowd=crowd_script.new()
	root.add_child(game)
	game.set_process(false)
	game.hide()
	game.configure_roster(catalog,["spear"],{})
	game.load_map({"id":"jitter05-cpu-fixture","theme":"farm","initialGold":4000,"trainingOnly":true,"totalWaves":10,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[]},10)
	game.start_battle()
	game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear()
	game.spawn_clock=100000.0
	game.set_seed(505)
	return game

func paid_spear(game: Node2D, position: Vector2) -> Dictionary:
	var id: int=game.next_id
	var result: Dictionary=game.submit_deployment("spear",position,"road")
	check(bool(result.get("ok",false)),"Ground regression creates each actual paid soldier")
	if not bool(result.get("ok",false)): return {}
	game._advance_recruitment(float(game.recruitment_queue[-1].totalSeconds))
	var unit: Dictionary=game.ground_combat._unit(id)
	# Controlled fixture positions, after genuine production; never product movement.
	unit.position=position
	game.ground_combat.initialize_march_departure(unit)
	return unit

func ground_case(crowd_script: Script) -> Dictionary:
	var game: Node2D=make_game(crowd_script)
	var positions: Array=[Vector2(.58,.5),Vector2(.534,.5),Vector2(.534,.516),Vector2(.596,.516),Vector2(.596,.484),Vector2(.612,.5)]
	for position in positions:
		if paid_spear(game,position).is_empty(): game.free();return {}
	var focus: Dictionary=game.units[0]
	var target: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":0})
	target.position=Vector2(.5,.5)
	target.hp=100000.0;target.maxHp=100000.0;target.stationaryEnemy=true
	var attackers: Dictionary={}
	game.game_event.connect(func(event: Dictionary):
		if str(event.get("type",""))=="hit" and str(event.get("side",""))=="friendly" and float(event.get("damage",0))>0: attackers[int(event.actorId)]=true)
	var target_changes: int=0
	var goal_changes: int=0
	var turns: int=0
	var previous_targets: Dictionary={}
	var previous_goals: Dictionary={}
	var previous_steps: Dictionary={}
	for tick in range(200):
		var origins: Dictionary={}
		for unit in game.units: origins[int(unit.id)]=unit.position
		game.advance_simulation(.025)
		for unit in game.units:
			var id: int=int(unit.id)
			var step: Vector2=unit.position-origins[id]
			check(step.length()<=.042*.025+.000001,"Actual Ground steps preserve the current slower pace")
			if previous_steps.has(id) and step.length()>.00001 and (previous_steps[id] as Vector2).length()>.00001 and step.normalized().dot((previous_steps[id] as Vector2).normalized())<-.5: turns+=1
			previous_steps[id]=step
			if previous_targets.has(id) and int(previous_targets[id])!=int(unit.targetId): target_changes+=1
			previous_targets[id]=int(unit.targetId)
			var chosen: Dictionary=game._enemy(int(unit.targetId))
			if not chosen.is_empty():
				var goal: Vector2=game.ground_combat._melee_point(unit,chosen)
				if previous_goals.has(id) and (previous_goals[id] as Vector2).distance_to(goal)>.007: goal_changes+=1
				previous_goals[id]=goal
	check(attackers.has(int(focus.id)),"A free alternative Ground contact remains reachable")
	check(attackers.size()>=3,"Several independently paid soldiers actually damage the same enemy")
	target.hp=0.0
	var replacement: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":0})
	replacement.position=Vector2(.5,.53);replacement.hp=100000.0;replacement.maxHp=100000.0;replacement.stationaryEnemy=true
	for tick in range(60): game.advance_simulation(.025)
	check(not game.ground_combat._nearest_enemy(focus).is_empty(),"A living replacement target is acquired after target death")
	var old_id: int=int(target.id)
	check(int(focus.targetId)!=old_id,"No stale target is pinned after death")
	game.ground_combat.structure_segment_clear=func(a: Vector2,b: Vector2,_margin: float)->bool: return (a.x-.56)*(b.x-.56)>=0.0
	focus.position=Vector2(.58,.5)
	game.ground_combat.initialize_march_departure(focus)
	game.ground_combat.crowd.rebuild(game.units,game.enemies)
	check(game.ground_combat._nearest_enemy(focus).is_empty(),"An enemy behind a newly blocked segment is rejected")
	var fresh: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":0})
	fresh.position=Vector2(.575,.51)
	game.ground_combat.crowd.rebuild(game.units,game.enemies)
	check(int(game.ground_combat._nearest_enemy(focus).get("id",-1))==int(fresh.id),"A newly reachable target is selected immediately")
	var report: Dictionary={"actualAttackers":attackers.keys(),"focusId":int(focus.id),"targetIdChanges":target_changes,"contactGoalChangesOverHalfBodyGap":goal_changes,"movementReversalsOver120":turns}
	game.free()
	return report

func run() -> void:
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	evidence["before"]={};evidence["current"]={}
	var cases: Dictionary={"occupied_goal":[Vector2(.475,.5)],"overlap":[Vector2(.475,.5),Vector2(.475,.5)],"nonoverlap":[Vector2(.475,.492),Vector2(.475,.508)],"traversable":[Vector2(.44,.5)],"open":[]}
	for name in cases:
		var before: Dictionary=crowd_case(BeforeCrowd,cases[name])
		var current: Dictionary=crowd_case(CurrentCrowd,cases[name])
		evidence.before[name]=before;evidence.current[name]=current
		check(float(current.maxStep)<=.002101,"Crowd never increases movement speed: "+str(name))
		if name in ["occupied_goal","overlap"]:
			check(int(before.reversalsOver120)>10,"Original actual Crowd reproduces occupied-goal oscillation")
			check(int(current.reversalsOver120)==0 and int(current.waitingFrames)>0,"Occupied goal waits without repeated reversals")
		elif name in ["traversable","open"]: check(float(current.remaining)<.00001,"A traversable goal remains reachable: "+str(name))
		else: check(int(current.reversalsOver120)==0,"Separated physical blockers do not cause repeated reversals")
	for change in ["removed","dead","moved","new_goal","wall"]:
		var current: Dictionary=crowd_case(CurrentCrowd,cases.occupied_goal,change)
		evidence.current[change]=current
		if change!="wall": check(float(current.firstReleaseStep)>.00001 and float(current.remaining)<.00001,"Movement resumes on the first updated frame: "+str(change))
	evidence["groundBefore"]=ground_case(BeforeCrowd)
	evidence["groundCurrent"]=ground_case(CurrentCrowd)
	check(int(evidence.groundCurrent.movementReversalsOver120)<=int(evidence.groundBefore.movementReversalsOver120),"Crowd correction does not worsen actual multi-attacker Ground approach reversals")
	print("PAINTED_JITTER05 "+JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"scope":"Actual deterministic Crowd/Ground movement and independent hits; no visual or full-game jitter claim"}))
	quit(0 if failures.is_empty() else 1)
