extends SceneTree
## Deterministic CPU backend replay of paid requests, NOT GUI equivalence.
const Game = preload("res://native/game.gd")
const Painted = preload("res://native/painted_stage.gd")
const BeforeGround = preload("res://tests/profiles/painted-jitter-06/source-before/ground_combat.gd")
const BeforeCrowd = preload("res://tests/profiles/painted-jitter-06/source-before/crowd_melee.gd")
const INPUT = "res://tests/profiles/painted-click-03/actual-1791943476/click03-report.json"
const OUTPUT = "res://tests/profiles/painted-jitter-06"
const STEP: float = .016667
const END_TIME: float = 32.0
var failures: Array = []
var checks: int = 0
var orders: Array = []
var source_hashes: Dictionary = {}
var started: int = 0
var traces: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> bool:
	checks += 1
	if not ok:
		failures.append(note)
		if failures.size()<20: push_error("JITTER_REPLAY06 "+note)
	return ok

func hashes() -> Dictionary:
	var result: Dictionary = {}
	for directory in ["res://native",OUTPUT+"/source-before"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.get_extension() in ["gd","json"]:
				var path: String = directory.path_join(filename)
				result[path] = FileAccess.get_sha256(path)
	for path in [INPUT,"res://tests/qa_painted_jitter_replay06.gd","res://project.godot"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func load_orders() -> bool:
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	if not check(report is Dictionary and report.get("paidOrders",[]).size()==8,"Actual source report contains exactly eight paid orders"): return false
	var previous: float = -1.0
	for row in report.paidOrders:
		if not check(row.get("receipts",[]).size()==1,"Each recorded order has one real paid receipt"): return false
		var receipt: Dictionary = row.receipts[0]
		var parts: PackedStringArray = str(row.get("requestedPosition","")).replace("(","").replace(")","").split(",")
		if not check(parts.size()==2 and parts[0].strip_edges().is_valid_float() and parts[1].strip_edges().is_valid_float(),"Recorded requested position parses"): return false
		var point: Vector2 = Vector2(float(parts[0]),float(parts[1]))
		var time: float = float(receipt.get("time",-1))
		if not check(is_finite(time) and time>=previous and time<END_TIME and point.is_finite(),"Recorded simulation times are ordered and bounded"): return false
		orders.append({"time":time,"unitType":str(row.unitType),"position":point,"cost":int(receipt.cost),"quantity":int(receipt.quantity),"label":str(row.label)})
		previous = time
	return true

func on_event(event: Dictionary, game: Node2D, evidence: Dictionary) -> void:
	var kind: String = str(event.get("type",""))
	if kind in ["recruitment_queued","recruited","placed","killed"]: evidence.events.append(event.duplicate(true))
	if kind in ["recruited","placed"]:
		for id_value in event.get("actorIds",[]):
			for unit in game.units:
				if int(unit.id)==int(id_value): evidence.birthPositions[str(id_value)] = unit.position
	if kind=="hit" and str(event.get("side",""))=="friendly" and float(event.get("damage",0))>0:
		var victim: String = str(event.get("victimId",-1))
		var actor_id: int = int(event.get("actorId",-1))
		if not evidence.hitActors.has(victim): evidence.hitActors[victim] = []
		if not evidence.hitActors[victim].has(actor_id): evidence.hitActors[victim].append(actor_id)
		evidence.hitCount = int(evidence.hitCount)+1

func goal_metadata(unit: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in unit:
		var name_value: String = str(key).to_lower()
		if "goal" in name_value or "steer" in name_value or "detour" in name_value or "heading" in name_value or "contact" in name_value:
			result[str(key)] = unit[key]
	return result.duplicate(true)

func scenario(before: bool) -> Dictionary:
	var label_value: String = "before" if before else "current"
	var game: Node2D = Game.new()
	if before:
		game.ground_combat = BeforeGround.new()
		game.ground_combat.crowd = BeforeCrowd.new()
	root.add_child(game)
	game.set_process(false)
	game.hide()
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	game.configure_roster(catalog,["archer","spear"],{"archer":1,"spear":1})
	game.set_seed(505)
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	game.load_map(Painted.apply(maps[0]),10)
	check(game.gold==280,label_value+": untouched initial gold is280")
	game.start_battle()
	var evidence: Dictionary = {"events":[],"birthPositions":{},"hitActors":{},"hitCount":0,"backendTransitions":[]}
	game.game_event.connect(Callable(self,"on_event").bind(game,evidence))
	var raw: Array = []
	var flips: Array = []
	var last: Dictionary = {}
	var histories: Dictionary = {}
	var metrics: Dictionary = {}
	var admitted: Array = []
	var next_order: int = 0
	var steps: int = 0
	var illegal: int = 0
	var max_step: float = 0.0
	var max_speed: float = 0.0
	var max_window: int = 0
	var target_changes: int = 0
	var contacts_max: int = 0
	var axis: Vector2 = (Painted.INGRESS-Painted.GATE).normalized()
	while game.elapsed<END_TIME-.0000001 and steps<3000 and Time.get_ticks_usec()-started<120000000:
		if game.between_waves and not game.finished:
			var transition: Dictionary = {"route":"backend_only_public_continue_wave","clockBefore":game.elapsed,"waveBefore":game.wave,"goldBefore":game.gold}
			game.continue_wave()
			transition.merge({"clockAfter":game.elapsed,"waveAfter":game.wave,"goldAfter":game.gold,"betweenWavesAfter":game.between_waves})
			evidence.backendTransitions.append(transition)
			check(is_equal_approx(float(transition.clockBefore),game.elapsed),label_value+": public wave continuation does not inject simulation time")
			if game.between_waves: break
		while next_order<orders.size() and float(orders[next_order].time)<=game.elapsed+.0000001:
			var order: Dictionary = orders[next_order]
			var wallet: int = game.gold
			var result: Dictionary = game.submit_deployment(str(order.unitType),order.position)
			admitted.append({"request":order,"actualTime":game.elapsed,"goldBefore":wallet,"goldAfter":game.gold,"result":result.duplicate(true)})
			check(bool(result.get("ok",false)) and wallet-game.gold==int(order.cost),label_value+": exact recorded paid order "+str(next_order+1))
			next_order += 1
		var delta: float = minf(STEP,END_TIME-game.elapsed)
		if next_order<orders.size(): delta = minf(delta,maxf(0.0,float(orders[next_order].time)-game.elapsed))
		if delta<=.0000001: break
		var old_clock: float = game.elapsed
		game.advance_simulation(delta)
		steps += 1
		if game.elapsed<=old_clock: break
		for unit in game.units:
			if str(unit.type)!="spear" or float(unit.hp)<=0: continue
			var id_value: String = str(unit.id)
			var point: Vector2 = unit.position
			var target_id: int = int(unit.get("targetId",-1))
			var previous: Dictionary = last.get(id_value,{})
			var origin: Vector2 = previous.get("position",evidence.birthPositions.get(id_value,point))
			var movement: Vector2 = point-origin
			var distance: float = movement.length()
			max_step = maxf(max_step,distance)
			max_speed = maxf(max_speed,distance/delta)
			if distance>.000001 and not game.ground_combat.land_segment_safe(origin,point,.008): illegal += 1
			if not metrics.has(id_value): metrics[id_value] = {"firstPosition":origin,"firstClock":game.elapsed,"pathLength":0.0,"flips":0,"targetChanges":0,"forwardProjection":0.0}
			var metric: Dictionary = metrics[id_value]
			metric.pathLength = float(metric.pathLength)+distance
			metric["lastPosition"] = point
			metric["lastClock"] = game.elapsed
			metric.forwardProjection = (point-Vector2(metric.firstPosition)).dot(axis)
			if not previous.is_empty() and int(previous.targetId)!=target_id:
				target_changes += 1; metric.targetChanges = int(metric.targetChanges)+1
			var reversal: bool = false
			if distance>.00001:
				if previous.has("nonzeroDirection") and game.elapsed-float(previous.nonzeroTime)<=.2 and int(previous.nonzeroTarget)==target_id:
					reversal = movement.normalized().dot(previous.nonzeroDirection)<-.5
				if reversal:
					var key: String = id_value+":"+str(target_id)
					var times: Array = histories.get(key,[]).filter(func(value): return game.elapsed-float(value)<=.5)
					times.append(game.elapsed); histories[key] = times
					max_window = maxi(max_window,times.size())
					metric.flips = int(metric.flips)+1
					flips.append({"clock":game.elapsed,"actorId":int(unit.id),"targetId":target_id,"state":str(unit.get("combatState","")),"position":point,"previousNonzeroTime":previous.nonzeroTime,"dot":movement.normalized().dot(previous.nonzeroDirection),"sameActorTargetFlipsInRollingHalfSecond":times.size()})
				previous["nonzeroDirection"] = movement.normalized()
				previous["nonzeroTime"] = game.elapsed
				previous["nonzeroTarget"] = target_id
			previous["position"] = point; previous["targetId"] = target_id
			last[id_value] = previous
			var target: Dictionary = game._enemy(target_id)
			var radial: Variant = null
			if not target.is_empty(): radial = target.position+(point-Vector2(target.position)).normalized()*game.ground_combat.reach(unit)*.82
			contacts_max = maxi(contacts_max,unit.get("contactEnemyIds",[]).size())
			raw.append({"clock":game.elapsed,"delta":delta,"actorId":int(unit.id),"position":point,"forwardProjection":metric.forwardProjection,"routeDistance":unit.get("routeDistance",null),"targetId":target_id,"targetPosition":target.get("position",null),"state":unit.get("combatState",""),"animation":unit.get("animation",""),"stepLength":distance,"rapidReversal":reversal,"idealRadialContactPoint":radial,"suggestedGoalMetadata":goal_metadata(unit)})
	check(next_order==8,label_value+": all eight orders replayed")
	check(absf(game.elapsed-END_TIME)<.00001,label_value+": native unpaused simulation reaches32seconds")
	check(illegal==0,label_value+": all observed moving spear strides remain legal land")
	traces[label_value] = {"rows":raw,"flips":flips,"events":evidence.events}
	var summary: Dictionary = {"steps":steps,"endClock":game.elapsed,"paused":game.paused,"betweenWaves":game.between_waves,"finished":game.finished,"gold":game.gold,"friendlyAlive":game.units.filter(func(unit): return float(unit.get("hp",0))>0).size(),"enemiesAlive":game.enemies.filter(func(enemy): return float(enemy.get("hp",0))>0).size(),"orders":admitted,"rapidReversalsOver120":flips.size(),"marchFlipsFirstFiveSeconds":flips.filter(func(row): return float(row.clock)<=5 and str(row.state)=="march").size(),"advanceFlips20To29Seconds":flips.filter(func(row): return float(row.clock)>=20 and float(row.clock)<=29 and str(row.state) in ["advance","support_advance","charge"]).size(),"maximumSameActorTargetFlipsInRollingHalfSecond":max_window,"targetChanges":target_changes,"illegalMovingStrides":illegal,"maxStep":max_step,"maxObservedSpeed":max_speed,"maxEnemiesContactingOneSpear":contacts_max,"perActorProgress":metrics,"positiveDamageHits":evidence.hitCount,"independentHitActorsByVictim":evidence.hitActors,"rawRows":raw.size()}
	summary["backendTransitions"] = evidence.backendTransitions
	game.free()
	return summary

func run() -> void:
	started = Time.get_ticks_usec()
	source_hashes = hashes()
	if not load_orders(): quit(2); return
	var before: Dictionary = scenario(true)
	var current: Dictionary = scenario(false)
	var ending: Dictionary = hashes()
	check(source_hashes==ending,"Product, original baseline, input report and replay script stay unchanged during both scenarios")
	var directory: String = OUTPUT.path_join("replay-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var raw_path: String = directory.path_join("raw-trace.json")
	var raw_file: FileAccess = FileAccess.open(raw_path,FileAccess.WRITE)
	if raw_file==null: push_error("Cannot save replay raw trace"); quit(2); return
	raw_file.store_string(JSON.stringify(traces)); raw_file.close()
	var report: Dictionary = {"status":"replay_evidence_collected" if failures.is_empty() else "partial_or_failed","checks":checks,"failures":failures,"before":before,"current":current,"rawTrace":ProjectSettings.globalize_path(raw_path),"sources":source_hashes,"sourcesAtEnd":ending,"seed":505,"step":STEP,"targetSimulationSeconds":END_TIME,"wallSeconds":float(Time.get_ticks_usec()-started)/1000000.0,"engine":Engine.get_version_info(),"scope":"CPU backend fixture: exact eight recorded requested positions and receipt simulation times through submit_deployment, native Painted first map, Lv1 archer/spear, original280 gold, seed505 and natural enemies. Only Ground+Crowd differ. No UI equivalence, context/pause injection, extra funds/HP/units/clocks, visual/performance/jitter-fix acceptance. Ideal radial point is diagnostic geometry, not a claim about the selected contact goal; only exposed goal metadata is recorded without invoking steering."}
	report["backendTransitionScope"] = "Natural between-wave boundaries explicitly use public continue_wave() and record clock/wave/gold before and after. This backend-only transition is not actual learning/UI equivalence; no funds, HP or clock fields are assigned."
	var file: FileAccess = FileAccess.open(directory.path_join("replay-report.json"),FileAccess.WRITE)
	if file==null: push_error("Cannot save replay summary"); quit(2); return
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("JITTER_REPLAY06 ",JSON.stringify({"status":report.status,"beforeFlips":before.rapidReversalsOver120,"currentFlips":current.rapidReversalsOver120,"failures":failures,"report":ProjectSettings.globalize_path(directory.path_join("replay-report.json"))}))
	quit(0 if failures.is_empty() else 1)
