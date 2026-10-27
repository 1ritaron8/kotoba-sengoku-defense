extends SceneTree
## HQ executes this focused CPU fixture. No save, GPU or FPS claim.
const Battle = preload("res://native/game.gd")
const Painted = preload("res://native/painted_stage.gd")
var game: Node2D
var checks: int = 0
var failures: Array = []
var evidence: Array = []
var root_map: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label_value: String) -> void:
	checks+=1
	if not ok:
		failures.append(label_value)
		if failures.size()<=12: push_error("INGRESS05 "+label_value)

func clear_front() -> void:
	# Every scenario needs its own native wave deadline. Reusing 80 seconds
	# with wave=3 otherwise pauses the final case at the real wave deadline.
	game.load_map(root_map,10)
	game.start_battle()
	game.config["trainingOnly"]=true
	game.units.clear()
	game.enemies.clear()
	game.spawn_queue.clear()
	game.spawn_source_waves.clear()
	game.spawn_metadata.clear()
	game.spawn_clock=100000.0
	game.unit_skills.invalidate_roster_index()

func physical_progress(enemy: Dictionary) -> float:
	var points: Array=game.paths[int(enemy.pathIndex)].points
	return (enemy.position-points[0]).dot((points[1]-points[0]).normalized())

func run() -> void:
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var roster: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	var catalog: Array=roster.units
	var unlocked: Array=[]
	for definition in catalog: unlocked.append(str(definition.id))
	game=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.hide()
	game.configure_roster(catalog,unlocked,{})
	root_map=Painted.apply(maps[0])
	clear_front()
	var base: Dictionary=game.ground_combat.select_march_base(0)
	check(not base.is_empty(),"Original painted root has a real advance route")
	if base.is_empty(): finish();return
	check(game.select_deployment("spear"),"Spear selection remains free")
	var gold_before: int=game.gold
	var result: Dictionary=game.submit_deployment("spear",base.position,str(base.pathId))
	check(bool(result.get("ok",false)),"Real paid spear order is accepted")
	if not bool(result.get("ok",false)): finish();return
	var job: Dictionary=game.recruitment_queue[0]
	check(game.gold==gold_before-int(job.cost),"Exactly one real order is paid")
	game._advance_recruitment(float(job.totalSeconds))
	check(not game.units.is_empty(),"Paid order creates actual independent actors")
	if game.units.is_empty(): finish();return
	var spear: Dictionary=game.units[0]
	check(str(spear.combatState)=="march" and float(spear.get("gatherRemaining",0))==0,"Departure has no gathering delay")
	var total: float=0.0
	for step in range(10):
		var before: Vector2=spear.position
		game.advance_simulation(.05)
		var travelled: float=before.distance_to(spear.position)
		total+=travelled
		check(travelled<=.042*.05+.000001,"Actual infantry stride respects the slower walking limit")
	check(total>.0001,"Slower infantry actually starts walking immediately")
	evidence.append({"kind":"paid_departure","distanceInHalfSecond":total,"speedLimit":.042})
	for pattern in ["skirmish","formation","mounted_vanguard","rush"]:
		clear_front()
		game.wave=3
		game.attack_pattern=pattern
		game.spawn_plan_cursor=0
		for kind in ["heavy","raider","runner","shield","runner","raider"]: game._append_spawn_entry(kind,3)
		var slots: Dictionary={}
		for metadata in game.spawn_metadata:
			var key: String="%d:%d" % [int(metadata.formationLane),int(metadata.formationRank)]
			check(not slots.has(key),"Each cohort member has its own approach slot: "+pattern)
			slots[key]=true
		game.spawn_clock=0.0
		var seen: Dictionary={}
		var crossed: Dictionary={}
		var births: Array=[]
		for step in range(400):
			check(game.running and not game.paused and not game.between_waves and not game.finished,"Natural-ingress scenario remains live throughout its own time window")
			var previous: Dictionary={}
			for enemy in game.enemies: previous[int(enemy.id)]=enemy.position
			game.advance_simulation(.05)
			var born_this_step: int=0
			for enemy in game.enemies:
				var id: int=int(enemy.id)
				if not seen.has(id):
					seen[id]=enemy
					born_this_step+=1
					check(not Rect2(0,0,1,1).has_point(enemy.position),"Every natural birth physically starts offscreen: "+pattern)
					births.append({"id":id,"time":game.elapsed,"position":game._normalized_position(enemy.position),"lane":int(enemy.formationLane),"rank":int(enemy.formationRank)})
				elif previous.has(id):
					check(is_same(seen[id],enemy),"The same actual actor travels from offscreen: "+pattern)
					check((previous[id] as Vector2).distance_to(enemy.position)<=float(enemy.speed)*4.0*.05+.000001,"Natural approach uses bounded physical steps: "+pattern)
				if Rect2(0,0,1,1).has_point(enemy.position): crossed[id]=true
				for leader in game.enemies:
					if float(leader.hp)<=0 or float(enemy.hp)<=0 or bool(leader.get("escaped",false)) or int(leader.id)==id or str(leader.formationGroup)!=str(enemy.formationGroup) or int(leader.pathIndex)!=int(enemy.pathIndex) or int(leader.formationLane)!=int(enemy.formationLane) or int(leader.formationRank)>=int(enemy.formationRank): continue
					check(physical_progress(leader)-physical_progress(enemy)>=Battle.ENEMY_FORMATION_ROW_GAP-.00001,"Same-lane rear rank cannot overtake its living leader: "+pattern)
			check(born_this_step<=1,"Natural production does not burst a cohort into one frame")
		check(births.size()==6,"All six scheduled soldiers naturally arrive: "+pattern)
		check(crossed.size()==6,"The same six offscreen actors actually cross onto the field: "+pattern)
		evidence.append({"kind":"natural_ingress","pattern":pattern,"births":births,"slots":slots.keys()})
	clear_front()
	var join_distance: float=.3
	var join: Vector2=game.ground_combat.route_point(0,join_distance)
	var entry: Dictionary={"id":"ingress05-physical-extension","pathIndex":0,"points":[game.paths[0].points[0],join],"joinDistance":join_distance,"pointIndex":1}
	var entrant: Dictionary=game._spawn_enemy("enemy_archer",3,{"ambushEntry":entry,"formationPattern":"formation","formationGroup":"ingress05-transition","formationLane":1,"formationRank":0})
	check(not entrant.is_empty() and bool(entrant.get("ingressActive",false)) and not Rect2(0,0,1,1).has_point(entrant.position),"A real side-ingress actor starts on its offscreen entry")
	if not entrant.is_empty():
		var transitions: int=0
		for step in range(400):
			if not game.enemies.has(entrant): break
			check(game.running and not game.paused and not game.between_waves and not game.finished,"Side-ingress transition runs while its battle is live")
			var before: Vector2=entrant.position
			var was_ingress: bool=bool(entrant.get("ingressActive",false))
			game.advance_simulation(.05)
			check(before.distance_to(entrant.position)<=float(entrant.speed)*4.0*1.6*.05+.000001,"Side-ingress exit keeps a bounded physical step without a lane snap")
			if was_ingress and not bool(entrant.get("ingressActive",false)): transitions+=1
		check(transitions==1,"The same actor completes exactly one ingress-to-main-route transition")
		evidence.append({"kind":"side_ingress_transition","id":int(entrant.id),"transitions":transitions,"elapsed":game.elapsed,"position":game._normalized_position(entrant.position),"ingressActive":bool(entrant.get("ingressActive",false)),"betweenWaves":game.between_waves})
	finish()

func finish() -> void:
	print("PAINTED_INGRESS05 "+JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"scope":"CPU original painted root, actual paid departure and serial natural ingress; HQ engine execution required"}))
	quit(0 if failures.is_empty() else 1)
