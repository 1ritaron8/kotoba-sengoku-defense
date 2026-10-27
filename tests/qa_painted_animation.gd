extends SceneTree
## Focused visual-source and real-shot synchronization checks, no rendered
## performance or all-role-animation acceptance claim.
const Battle = preload("res://native/game.gd")
const Painter = preload("res://native/painted_actor_renderer.gd")
const PaintedStage = preload("res://native/painted_stage.gd")
var checks: int = 0
var failures: Array[String] = []
var evidence: Dictionary = {}
var catalog: Dictionary = {}
var maps: Array = []

func _init() -> void: call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	if not value: failures.append(note)

func source_actions() -> void:
	var renderer = Painter.new()
	check(renderer.is_ready(),"Painted action assets do not compile")
	var vectors: Dictionary = {"ne":Vector2(2,-1),"se":Vector2(2,1),"sw":Vector2(-2,1),"nw":Vector2(-2,-1)}
	for friendly in [true,false]:
		for role in ["archer","spear"]:
			var source: Dictionary = renderer.manifest.frames[role] if friendly else renderer.manifest.factions.enemy.frames[role]
			var fixed_height: float = -1
			for direction in vectors:
				check(source.has(direction),role+" missing "+direction)
				if not source.has(direction): continue
				var record: Dictionary = source[direction]
				check(record.has("idle") and record.has("attack"),role+" has no separate authored idle/attack: "+direction)
				if not record.has("idle") or not record.has("attack"): continue
				var attack: Dictionary = record.attack
				check(attack.frames.size()==4 and int(attack.releaseFrame)==2,"Expected authored windup/release/recovery sequence: "+role+"/"+direction)
				check(record.idle.frames[0].rect!=attack.frames[1].rect and attack.frames[1].rect!=attack.frames[2].rect,"Idle/draw/release reuse the same source region: "+role+"/"+direction)
				var height: float = float(attack.bodyHeightPixels)
				if fixed_height<0: fixed_height=height
				check(height==fixed_height,"Action directions received different body scaling: "+role)
				var actor: Dictionary = {"type":role,"animation":"idle","preview":true,"attackDuration":.6,"animationClock":0.0}
				var idle: Dictionary = renderer.animation_sample(actor,friendly,vectors[direction])
				check(str(idle.get("sourceDirection",""))==direction and str(idle.get("sourceState",""))=="idle" and bool(idle.get("authoredState",false)),"Actual idle sample uses wrong orientation/source: "+role+"/"+direction)
				actor.animation="attack"; actor.animationClock=.1
				var before: Dictionary = renderer.animation_sample(actor,friendly,vectors[direction])
				check(int(before.get("sourceFrame",99))<2,"Preview released before windup: "+role+"/"+direction)
				actor.animationClock=.45
				var after: Dictionary = renderer.animation_sample(actor,friendly,vectors[direction])
				check(int(after.get("sourceFrame",-1))>=2 and str(after.get("sourceDirection",""))==direction,"Preview attack did not reach correct release direction: "+role+"/"+direction)
				actor.animation="walk"
				var walk: Dictionary = renderer.animation_sample(actor,friendly,vectors[direction])
				if direction in ["se","nw"]:
					check(str(walk.get("sourceDirection",""))!=direction,"Unauthored walk direction falsely claimed implemented: "+role+"/"+direction)
	check(renderer.manifest.get("pendingAuthoredActions",[]).size()>0,"Other unfinished roles lost pending status")
	evidence["actionSourceDiagnostics"]=renderer.diagnostics()

func make_game(role: String) -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game); game.set_process(false)
	game.configure_roster(catalog.units,["archer","spear"],{})
	game.load_map(PaintedStage.apply(maps[0]),10)
	game.painted_actors.bind_battle(game)
	check(game.begin_placement(role,0),"Paid recruitment could not begin: "+role)
	if role=="archer":
		var point: Vector2 = Vector2(-1,-1)
		for zone in game.zones:
			if str(zone.get("placementRole",""))=="ranged":
				point=game._zone_placement_hint(zone,role)
				if point.x>=0: break
		check(point.x>=0 and game.place_unit(point.x,point.y),"Actual paid archer pad placement failed")
	game._advance_recruitment(20.0)
	check(game.units.size()==1,"Paid order did not produce one actual unit: "+role)
	game.start_battle()
	game.enemies.clear(); game.spawn_queue=["raider"]; game.spawn_source_waves=[1]; game.spawn_metadata=[{}]; game.spawn_clock=10000
	return game

func no_target_pad_facing() -> void:
	var game: Node2D = Battle.new()
	root.add_child(game); game.set_process(false)
	game.load_map(PaintedStage.apply(maps[0]),10)
	game.enemies.clear()
	var findings: Array = []
	for zone in game.zones:
		if str(zone.get("placementRole",""))!="ranged": continue
		var actor: Dictionary = {"id":-10,"type":"archer","position":zone.position,"hp":100.0,"animation":"idle","aim":Vector2.RIGHT,"postPathIndex":0}
		var original: String = JSON.stringify(actor)
		var direction: Vector2 = game.painted_actors.visual_direction(actor,true,game)
		var sample: Dictionary = game.painted_actors.animation_sample(actor,true,direction)
		var expected: String = "se" if str(zone.id)=="left-shoulder-pad" else "nw"
		check(str(sample.get("sourceDirection",""))==expected,"No-target pad faces away from guarded road: "+str(zone.id))
		check(JSON.stringify(actor)==original,"Idle facing modified actor target/aim")
		findings.append({"zone":str(zone.id),"expected":expected,"sample":sample,"screenDirection":[direction.x,direction.y]})
	check(findings.size()==2,"Actual first map does not expose both deck facing checks")
	evidence["noTargetPadFacing"]=findings
	game.free()

func real_release(role: String) -> void:
	var game: Node2D = make_game(role)
	if game.units.is_empty(): game.free(); return
	var unit: Dictionary = game.units[0]
	var enemy: Dictionary = game._spawn_enemy("raider",1,{"originKind":"raider","pathIndex":0})
	# Explicit isolated target fixture: retain real acquisition/animation/shot
	# logic, hold one target on the actual road with enough HP for both attacks.
	var road: Array = game.paths[0].points
	enemy.position=Geometry2D.get_closest_point_to_segment(unit.position,road[0],road[1]) if role=="archer" else game.ground_combat.route_point(0,float(game.ground_combat.cumulative[0][-1])-.075)
	enemy.speed=0.0; enemy.hp=10000.0; enemy.maxHp=10000.0
	var shots: Array = []
	game.game_event.connect(func(event: Dictionary) -> void:
		if str(event.get("type",""))=="shot" and str(event.get("side",""))=="friendly" and int(event.get("actorId",-1))==int(unit.id): shots.append(event.duplicate(true)))
	var saw_windup: bool = false
	var released: Dictionary = {}
	var state_before: String = JSON.stringify(unit)
	for unused in range(400):
		game.advance_simulation(.025)
		var sample: Dictionary = game.painted_actors.animation_sample(unit,true,game.painted_actors.visual_direction(unit,true,game))
		if str(unit.animation)=="attack" and not unit.get("attackPlan",{}).is_empty():
			saw_windup=true
			check(int(sample.get("sourceFrame",99))<2 and not bool(sample.get("releaseCommitted",false)),"Source released before actual shot: "+role)
		if not shots.is_empty():
			released=sample
			break
	check(saw_windup,"No real attack windup observed: "+role)
	check(not shots.is_empty(),"No actual committed shot observed: "+role)
	check(bool(released.get("releaseCommitted",false)) and int(released.get("sourceFrame",-1))==2,"Actual first shot did not select release frame: "+role)
	check(int(released.get("releaseEventId",-1))==int(shots[0].eventId) if not shots.is_empty() else false,"Release sample not tied to real event ID: "+role)
	# Finish this cycle, wait for the next real windup, then remove the target.
	var cancellation_windup: bool = false
	for unused in range(120):
		game.advance_simulation(.025)
		if str(unit.animation)=="attack" and not unit.get("attackPlan",{}).is_empty(): cancellation_windup=true; break
	if cancellation_windup: enemy.hp=0.0
	var prior_shots: int = shots.size()
	var cancelled: Dictionary = {}
	for unused in range(30):
		game.advance_simulation(.025)
		var sample: Dictionary = game.painted_actors.animation_sample(unit,true,game.painted_actors.visual_direction(unit,true,game))
		if bool(sample.get("cancelled",false)): cancelled=sample; break
	check(cancellation_windup and not cancelled.is_empty(),"Canceled real windup did not return to idle source: "+role)
	check(shots.size()==prior_shots,"Canceled attack emitted a real shot: "+role)
	check(str(cancelled.get("renderState",""))=="idle" and int(cancelled.get("sourceFrame",-1))==0,"Canceled attack displayed release/recovery source: "+role)
	# Sampling repeatedly must not mutate actor gameplay data or spend/emit.
	state_before=JSON.stringify(unit)
	var event_id: int = int(game.next_event_id)
	for unused in range(10): game.painted_actors.animation_sample(unit,true,Vector2(1,1))
	check(JSON.stringify(unit)==state_before and int(game.next_event_id)==event_id,"Renderer changed gameplay or emitted events: "+role)
	evidence[role]={"actualRelease":released,"actualShotCount":shots.size(),"cancelled":cancelled,"scope":"paid recruitment and isolated real combat simulation; target HP/location fixture; no UI/rendered performance claim"}
	game.free()

func real_enemy_release() -> void:
	var game: Node2D = make_game("archer")
	if game.units.is_empty(): game.free(); return
	var unit: Dictionary = game.units[0]
	unit.hp=10000.0; unit.maxHp=10000.0
	var enemy: Dictionary = game._spawn_enemy("enemy_archer",1,{"originKind":"raider","pathIndex":0})
	check(str(enemy.get("kind",""))=="enemy_archer","Actual enemy archer spawn contract failed")
	# A local valid-land combat fixture, not a claim about ingress or placement.
	var found: bool = false
	for offset in [Vector2(.07,0),Vector2(-.07,0),Vector2(0,.07),Vector2(0,-.07)]:
		var point: Vector2=unit.position+offset
		if game.ground_combat.land_segment_safe(point,unit.position):
			enemy.position=point; found=true; break
	check(found,"No reachable isolated enemy archer firing position")
	if not found: game.free(); return
	enemy.speed=0.0; enemy.hp=10000.0; enemy.maxHp=10000.0
	var shots: Array=[]
	game.game_event.connect(func(event: Dictionary) -> void:
		if str(event.get("type",""))=="shot" and str(event.get("side",""))=="enemy" and int(event.get("actorId",-1))==int(enemy.id): shots.append(event.duplicate(true)))
	var windup: bool=false
	var released: Dictionary={}
	for unused in range(160):
		game.advance_simulation(.025)
		var sample: Dictionary=game.painted_actors.animation_sample(enemy,false,game.painted_actors.visual_direction(enemy,false,game))
		if not enemy.get("rangedPlan",{}).is_empty():
			windup=true
			check(int(sample.get("sourceFrame",99))<2 and not bool(sample.get("releaseCommitted",false)),"Enemy source released before actual shot")
		if not shots.is_empty(): released=sample; break
	check(windup and not shots.is_empty(),"Actual enemy windup/shot not observed")
	check(bool(released.get("releaseCommitted",false)) and int(released.get("sourceFrame",-1))==2,"Enemy first actual shot did not display release frame")
	check(int(released.get("releaseEventId",-1))==int(shots[0].eventId) if not shots.is_empty() else false,"Enemy receipt side/actor/event does not match actual shot")
	var next_windup: bool=false
	for unused in range(100):
		game.advance_simulation(.025)
		if not enemy.get("rangedPlan",{}).is_empty(): next_windup=true; break
	if next_windup: unit.hp=0.0
	var prior: int=shots.size()
	for unused in range(25): game.advance_simulation(.025)
	var cancelled: Dictionary=game.painted_actors.animation_sample(enemy,false,game.painted_actors.visual_direction(enemy,false,game))
	check(next_windup and shots.size()==prior,"Canceled enemy windup emitted an additional shot")
	check(str(cancelled.get("renderState",""))!="attack" or bool(cancelled.get("cancelled",false)),"Canceled enemy windup retained attack release source")
	evidence["enemyArcher"]={"actualRelease":released,"shotCount":shots.size(),"afterTargetLoss":cancelled,"scope":"real spawned enemy and paid archer, isolated legal land position/HP fixture, normal advance_simulation only"}
	game.free()

func run() -> void:
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	source_actions()
	no_target_pad_facing()
	real_release("archer")
	real_release("spear")
	real_enemy_release()
	print(JSON.stringify({"suite":"painted-animation","checks":checks,"failures":failures,"evidence":evidence,"scope":"both factions archer/spear authored four-direction sources; paid friendly archer/spear and enemy archer real-shot timing; other roles, full walk directions and rendered acceptance remain pending"}))
	quit(0 if failures.is_empty() else 1)
