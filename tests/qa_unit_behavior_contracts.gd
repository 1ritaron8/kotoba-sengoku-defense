extends SceneTree
## Synthetic geometry only; never reads, restores, or changes the campaign maps.
const Battle = preload("res://native/game.gd")
const Growth = preload("res://native/unit_growth.gd")
const Training = preload("res://native/unit_training.gd")
const TYPES: Array = ["archer","gunner","spear","samurai","commander","naginata","monk","ninja"]
const SOURCE_FILES: Array=["native/game.gd","native/ground_combat.gd","native/unit_skills.gd","native/units.json","native/unit_growth.gd","native/unit_training.gd","tests/qa_unit_behavior_contracts.gd"]
var catalog: Array = []
var checks: int = 0
var failures: Array = []
var observations: Dictionary = {}
var events: Array = []
var initial_hashes: Dictionary={}

func _initialize() -> void: call_deferred("run")

func hashes() -> Dictionary:
	var result: Dictionary={}
	for path in SOURCE_FILES: result[path]=FileAccess.get_sha256("res://"+str(path))
	return result

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		if failures.size() <= 35: push_error("UNIT_BEHAVIOR " + message)

func fixture(radius: float = .20) -> Dictionary:
	return {"id":"unit-behavior-isolated-fixture","stageNumber":20,"theme":"forest","initialGold":10000,"unitLimit":24,"totalWaves":100,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":1000}],"buildZones":[{"id":"firing","x":.5,"y":.65,"r":.13}],"tactics":{"groundPosts":[{"id":"defense","pathIndex":0,"segmentIndex":0,"t":.5,"r":.14,"guardRadius":radius,"mobilityFactor":1.0}]}}

func create_game(levels: Dictionary = {}, data: Dictionary = {}) -> Node2D:
	events.clear()
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,TYPES,levels)
	game.load_map(fixture() if data.is_empty() else data)
	game.set_seed(629)
	game.game_event.connect(func(event: Dictionary):
		var row: Dictionary=event.duplicate(true)
		if str(event.get("type",""))=="placed":
			var unit: Dictionary=game.ground_combat._unit(int(event.get("actorId",-1)))
			if not unit.is_empty() and str(unit.type)=="ninja":
				row["qaUnit"]=unit.duplicate(true)
				row["qaTargets"]=game.enemies.duplicate(true)
				row["qaValidTargets"]=game.enemies.map(func(enemy: Dictionary): return game.ground_combat.ninja_mission_target_valid(unit,enemy))
		events.append(row))
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue = ["raider"]
	game.spawn_source_waves = [1]
	game.spawn_metadata = [{}]
	game.spawn_clock = 100000.0
	return game

func tick(game: Node2D, seconds: float, quantum: float = .025) -> void:
	var left: float = seconds
	while left > .000001 and not game.finished:
		var amount: float = minf(quantum,left)
		game.advance_simulation(amount)
		left -= amount

func recruit(game: Node2D, type_name: String, wanted: Vector2 = Vector2(-1,-1)) -> Dictionary:
	var old_ids: Array = game.units.map(func(unit: Dictionary): return int(unit.id))
	check(game.begin_placement(type_name,0),type_name + " accepts a paid recruitment order independent of available targets")
	if str(game.placement_contract(type_name).deploymentKind) != "marching":
		var point: Vector2 = wanted
		if point.x < 0:
			if type_name == "ninja":
				var distance: float = INF
				for zone in game.zones:
					if str(zone.get("placementRole","")) != "ambush": continue
					var candidate: Vector2 = zone.position
					if game.placement_preview(candidate).valid and candidate.distance_to(Vector2(.5,.565)) < distance:
						distance = candidate.distance_to(Vector2(.5,.565));point = candidate
			else:
				for zone in game.zones:
					var candidate: Vector2 = game._zone_placement_hint(zone,type_name)
					if candidate.x >= 0 and game.placement_preview(candidate).valid: point = candidate;break
		check(point.x >= 0 and game.place_unit(point.x,point.y),type_name + " reserves a legal production destination")
	for index in range(600):
		game.advance_simulation(.025)
		for unit in game.units:
			if str(unit.type) == type_name and int(unit.id) not in old_ids: return unit
	if type_name=="ninja": observations["failedProduction-"+str(observations.size())]=events.slice(maxi(0,events.size()-8))
	check(false,type_name + " completes actual production")
	return {}

func enemy_at(game: Node2D, position: Vector2, kind: String = "enemy_gunner", tower: bool = false, role: String = "") -> Dictionary:
	var enemy: Dictionary = game._spawn_enemy(kind,1,{"pathIndex":0})
	enemy.merge({"position":position,"pointIndex":1,"speed":0.0,"hp":5000.0,"maxHp":5000.0,"armor":0.0,"attackCooldown":10000.0,"stationaryEnemy":tower,"fortification":tower,"blockedBy":-1,"stationThreatClock":10000.0},true)
	if not role.is_empty(): enemy.combatRole = role
	return enemy

func hits_by(actor_id: int) -> Array:
	return events.filter(func(event: Dictionary): return str(event.get("type","")) == "hit" and int(event.get("actorId",-1)) == actor_id and str(event.get("victimSide","")) == "enemy")

func wait_damage(game: Node2D, target: Dictionary, seconds: float = 8.0) -> bool:
	var initial: float = float(target.hp)
	for index in range(ceili(seconds/.025)):
		game.advance_simulation(.025)
		if float(target.hp) < initial: return true
	return false

func guard_roles_and_recognition() -> void:
	for level in [1,5,8]:
		var game: Node2D = create_game({"naginata":level})
		var guard: Dictionary = recruit(game,"naginata",Vector2(.5,.5))
		if guard.is_empty(): game.free();continue
		var home: Vector2 = guard.homePosition
		var raider: Dictionary = enemy_at(game,home+Vector2(-.075,0),"raider")
		var wallet: int = game.gold
		tick(game,3)
		check(guard.position == home and float(raider.hp) == 5000,"Naginata level %d ignores nearby ordinary route traffic" % level)
		check(not bool(guard.get("guardDashActive",false)) and int(guard.get("targetId",-1)) < 0,"Ordinary route enemy cannot start a guard dash or primary target")
		check(game.gold == wallet,"Ignoring a route enemy neither refunds nor changes paid recruitment")
		raider.hp = 0;tick(game,.05)
		var outside_recognition: Dictionary = enemy_at(game,home+Vector2(float(game._stats(guard).range)+.015,0))
		tick(game,2)
		check(guard.position == home and float(outside_recognition.hp) == 5000,"Recognition range stays separate from a larger movement zone")
		outside_recognition.hp = 0;tick(game,.05)
		var threat: Dictionary = enemy_at(game,home+Vector2(.12,0))
		var before: int = hits_by(int(guard.id)).size()
		check(wait_damage(game,threat),"Guard intercepts a real emplacement attacker recognized inside its defense zone")
		check(hits_by(int(guard.id)).size() > before,"Guard damage is tied to an actual native hit event")
		observations["guard-level-"+str(level)] = {"position":str(guard.position),"dash":bool(guard.get("guardDashActive",false)),"targetHp":threat.hp,"home":str(home)}
		threat.hp = 0;tick(game,4)
		check(guard.position.distance_to(home)<.00001 and int(guard.targetId)<0,"Guard physically returns to its paid waiting location after threat death")
		game.free()

func guard_zone_and_escape() -> void:
	var game: Node2D = create_game({"naginata":8},fixture(.09))
	var guard: Dictionary = recruit(game,"naginata",Vector2(.5,.5))
	if guard.is_empty(): game.free();return
	var home: Vector2 = guard.homePosition
	var target: Dictionary = enemy_at(game,home+Vector2(.15,0))
	tick(game,3)
	check(guard.position==home and float(target.hp)==5000,"A recognized target whose strike location is outside the authored zone is never chased")
	check(not bool(guard.get("guardDashActive",false)),"Invalid out-of-zone approach never starts the existing mana dash")
	target.position=home+Vector2(.07,0)
	check(wait_damage(game,target),"Inside-edge target remains interceptable")
	var safe_steps: bool = true
	var continuous: bool = true
	var previous: Vector2 = guard.position
	for index in range(160):
		target.position=home+Vector2(.16*cos(float(index)*.025),.16*sin(float(index)*.025))
		game.advance_simulation(.025)
		safe_steps=safe_steps and guard.position.distance_to(home)+.008<=.09+.00001
		continuous=continuous and guard.position.distance_to(previous)<=.01
		previous=guard.position
	check(safe_steps,"Whole .008 guard footprint stays within the circular defense boundary while an enemy flees along its edge")
	check(continuous,"Abandoning an edge target and returning never teleports")
	tick(game,3)
	check(guard.position.distance_to(home)<.00001,"Out-of-zone fleeing target ends pursuit and allows a real home return")
	game.free()

func guard_blocked_internal_route() -> void:
	var data: Dictionary = fixture(.14)
	var game: Node2D = create_game({"naginata":8},data)
	var guard: Dictionary = recruit(game,"naginata",Vector2(.5,.5))
	if guard.is_empty(): game.free();return
	var home: Vector2 = guard.homePosition
	# This wall reaches past both sides of the defense circle; all endpoints
	# remain valid, but no footprint-safe route exists inside that zone.
	game.ground_combat.structure_segment_clear=func(start: Vector2,end: Vector2,margin: float):
		return not (minf(start.x,end.x)-margin<=.555 and maxf(start.x,end.x)+margin>=.545 and maxf(start.y,end.y)+margin>=.34 and minf(start.y,end.y)-margin<=.66)
	var target: Dictionary = enemy_at(game,home+Vector2(.11,0))
	tick(game,6)
	check(guard.position==home and float(target.hp)==5000,"Blocked internal corridor prevents guard pursuit and any dash damage")
	check(not bool(guard.get("guardDashActive",false)),"An unreachable in-zone enemy does not consume a guard dash")
	game.ground_combat.structure_segment_clear=Callable()
	check(wait_damage(game,target),"Guard resumes a legal intercept when the internal corridor becomes passable")
	game.free()

func guard_concave_path_footprint() -> void:
	var data: Dictionary = fixture(.2)
	var polygon: Array = [{"x":.46,"y":.46},{"x":.65,"y":.46},{"x":.65,"y":.65},{"x":.56,"y":.65},{"x":.56,"y":.54},{"x":.46,"y":.54}]
	data.tactics.groundPosts[0].defenseZone={"polygon":polygon,"waypoints":[]}
	var game: Node2D = create_game({},data)
	var guard: Dictionary = recruit(game,"naginata",Vector2(.5,.5))
	if guard.is_empty(): game.free();return
	var target: Dictionary = enemy_at(game,Vector2(.60,.60))
	var bounds: PackedVector2Array = PackedVector2Array()
	for point in polygon: bounds.append(Vector2(point.x,point.y))
	var safe: bool=true
	var reached: bool=false
	var previous: Vector2=guard.position
	for index in range(480):
		game.advance_simulation(.025)
		for fraction in [.0,.25,.5,.75,1.0]:
			var center: Vector2=previous.lerp(guard.position,fraction)
			for side in range(16):
				var sample: Vector2=center+Vector2.from_angle(TAU*float(side)/16.0)*.008
				safe=safe and Geometry2D.is_point_in_polygon(sample,bounds)
		previous=guard.position
		if float(target.hp)<5000: reached=true;break
	check(safe,"Every guard movement segment and its radial footprint stay inside the concave defense polygon")
	check(reached,"A valid authored internal bend is followed to a reachable in-zone base attacker")
	observations.concaveGuard={"reached":reached,"safe":safe,"position":str(guard.position)}
	game.free()

func guard_windup_release_rules() -> void:
	var game: Node2D = create_game({"naginata":5},fixture(.09))
	var guard: Dictionary = recruit(game,"naginata",Vector2(.5,.5))
	if guard.is_empty(): game.free();return
	var home: Vector2=guard.homePosition
	var target: Dictionary=enemy_at(game,home+Vector2(.04,0))
	game.ground_combat.step(0.0)
	game._update_units(.01)
	check(str(guard.animation)=="attack" and not guard.attackPlan.is_empty(),"Valid guard begins a real attack preparation")
	var plan: Dictionary=guard.attackPlan
	target.combatRole=game.ENEMY_PATH_ROLE
	var hp: float=target.hp
	game._release_unit_attack(guard,plan)
	check(float(target.hp)==hp,"Guard revalidates the base-attacker role at actual strike time")
	game._release_unit_attack(guard,plan)
	check(float(target.hp)==hp,"Repeated release of the same invalid attack cannot deal duplicate damage")
	guard.animation="idle";guard.cooldown=0;guard.attackPlan={}
	target.combatRole=game.ENEMY_EMPLACEMENT_ROLE
	game.ground_combat.step(0.0)
	game._update_units(.01)
	plan=guard.attackPlan
	target.position=home+Vector2(.15,0)
	game._release_unit_attack(guard,plan)
	check(float(target.hp)==hp,"Guard revalidates zone and melee range after a prepared target flees")
	game.free()

func guard_dash_and_secondary() -> void:
	for level in [2,3,5,8]:
		var game: Node2D=create_game({"naginata":level})
		var guard: Dictionary=recruit(game,"naginata",Vector2(.5,.5))
		if guard.is_empty(): game.free();continue
		tick(game,8)
		var primary: Dictionary=enemy_at(game,Vector2(.62,.5))
		var ordinary: Dictionary=enemy_at(game,Vector2(.635,.508),"raider")
		var wider: Dictionary=enemy_at(game,Vector2(.682,.5),"raider")
		var start: int=events.size()
		check(wait_damage(game,primary),"Guard skill fixture reaches its permitted base-attacker primary")
		var activations: Array=events.slice(start).filter(func(event: Dictionary): return str(event.get("skillId",""))=="naginata_guard_charge" and str(event.get("type",""))=="skill")
		check((not activations.is_empty())==(level>=5),"Existing mana dash remains unlocked at permanent level 5 with its existing cluster condition")
		check(float(ordinary.hp)<5000,"Existing basic sweep secondary still damages nearby route traffic without selecting it as a primary")
		check((float(wider.hp)<5000)==(level>=3),"Existing wider sweep radius remains unlocked at permanent level 3")
		check(int(guard.get("targetId",-1))!=int(ordinary.id),"Sweep secondary does not become a permitted direct guard primary")
		check((float(guard.get("invulnerableUntil",0))>game.elapsed)==(level>=8),"Successful existing dash preserves level 8 post-impact invulnerability")
		if level>=8:
			var before: float=guard.hp
			game._damage_friendly(guard,20,primary)
			check(float(guard.hp)==before,"Actual friendly damage observes the unchanged dash invulnerability")
		game.free()

func queue_ninja(game: Node2D) -> Dictionary:
	var wallet: int=game.gold
	var id_before: int=game.next_id
	check(game.begin_placement("ninja",0),"Consumable ninja accepts its normal paid recruitment without target-based blocking")
	var point: Vector2=Vector2(-1,-1)
	var nearest: float=INF
	for zone in game.zones:
		if str(zone.get("placementRole",""))!="ambush": continue
		var candidate: Vector2=zone.position
		if game.placement_preview(candidate).valid and candidate.distance_to(Vector2(.5,.565))<nearest:
			point=candidate;nearest=candidate.distance_to(Vector2(.5,.565))
	check(point.x>=0 and game.place_unit(point.x,point.y),"Ninja order commits an existing legal concealed destination")
	var cost: int=wallet-game.gold
	var start_events: int=events.size()
	for index in range(500):
		game.advance_simulation(.025)
		if game.recruitment_queue.is_empty(): break
	var ids: Array=[]
	for event in events.slice(start_events):
		if str(event.get("type",""))=="placed" and str(event.get("actorType",""))=="ninja": ids=event.get("actorIds",[])
	if ids.is_empty():
		for event in events.slice(start_events):
			if str(event.get("type",""))=="placed" and event.has("actorIds"): ids=event.actorIds
	return {"cost":cost,"wallet":wallet,"idBefore":id_before,"ids":ids,"home":point,"eventsBefore":start_events}

func assert_consumed(game: Node2D, unit: Dictionary, paid_wallet: int, message: String) -> void:
	tick(game,.05)
	check(game.ground_combat._unit(int(unit.id)).is_empty() and bool(unit.get("consumed",false)),message+" removes the consumable actor from active capacity")
	check(int(unit.get("priorityTargetId",-1))<0 and int(unit.get("targetId",-1))<0 and unit.get("attackPlan",{}).is_empty(),message+" clears designated IDs and attack preparation")
	check(game.gold==paid_wallet,message+" retains the spent recruitment cost without refund")
	check(game.death_actors.all(func(actor: Dictionary): return int(actor.id)!=int(unit.id)),message+" does not fabricate a casualty death animation")
	check(not bool(game.order_assassination(-1,int(unit.id)).accepted),message+" cannot accept a reusable follow-up mission")
	var records: Array=events.filter(func(event: Dictionary): return str(event.get("type",""))=="unit_consumed" and int(event.get("actorId",-1))==int(unit.id))
	check(records.size()==1,message+" emits one consumption receipt")
	check(not events.any(func(event: Dictionary): return str(event.get("type",""))=="unit_fallen" and int(event.get("actorId",-1))==int(unit.id)),message+" never emits a fabricated friendly casualty")

func ninja_no_target_consumption() -> void:
	for target_kind in ["none","mobile_gunner","flag_only"]:
		var game: Node2D=create_game()
		var decoy: Dictionary={}
		if target_kind!="none":
			decoy=enemy_at(game,Vector2(.5,.5),"enemy_gunner",target_kind=="flag_only")
			if target_kind=="flag_only": decoy.combatRole=game.ENEMY_PATH_ROLE
		var summary: Dictionary=queue_ninja(game)
		tick(game,.1)
		check(summary.cost==game.recruit_cost("ninja"),"No-valid-tower recruitment charges the ordinary ninja cost")
		check(summary.ids.size()==1 and game.next_id>int(summary.idBefore),"No-valid-tower recruitment really produces one actor before consuming it")
		check(game.units.is_empty() and game.recruitment_queue.is_empty(),"Ninja with "+target_kind+" is consumed instead of waiting or becoming general infantry")
		check(game.gold==int(summary.wallet)-int(summary.cost) and game.kills==0,"No-valid-tower consumption neither refunds nor grants fake kills/rewards")
		check(game.death_actors.is_empty(),"No-valid-tower consumption does not claim a combat casualty")
		if not decoy.is_empty(): check(float(decoy.hp)==5000,"Mobile species or flags alone never become a ninja tower target")
		observations["ninja-no-target-"+target_kind]=summary
		game.free()

func ninja_preview_no_consumption() -> void:
	var game: Node2D=create_game()
	var wallet: int=game.gold
	var actor_serial: int=game.next_id
	var queue_serial: int=game.next_recruitment_id
	for index in range(20): game.deployment_preview("ninja",Vector2(.43,.565))
	check(game.gold==wallet and game.next_id==actor_serial and game.next_recruitment_id==queue_serial and game.units.is_empty() and game.recruitment_queue.is_empty(),"Ninja drag preview with no targets does not create, consume, charge, or reserve actor/order IDs")
	check(game.begin_placement("ninja",0),"Ninja preview cancellation starts the existing free placement preparation")
	game.cancel_recruit()
	check(game.gold==wallet and game.next_id==actor_serial and game.units.is_empty() and game.recruitment_queue.is_empty(),"Ninja cancellation never manufactures a consumed actor or charge")
	game.free()

func ninja_stats_growth_and_unlocks() -> void:
	var definition: Dictionary={}
	for entry in catalog:
		if str(entry.id)=="ninja": definition=entry
	check(float(definition.damage)==51 and float(definition.hp)==160,"Ninja base damage 51 and health 160 implement the explicit stronger consumable unit")
	check(float(definition.range)==.15 and float(definition.interval)==.46 and int(definition.cost)==110 and float(definition.recruitSeconds)==3.85 and int(definition.unlockClears)==14,"Ninja range, attack cycle, recruitment cost/time and unlock progression remain unchanged")
	for level in [1,4,8]:
		var game: Node2D=create_game({"ninja":level})
		var tower: Dictionary=enemy_at(game,Vector2(.5,.5),"enemy_gunner",true)
		var ninja: Dictionary=recruit(game,"ninja")
		if not ninja.is_empty():
			check(is_equal_approx(float(ninja.maxHp),Growth.max_health(ninja,definition)),"Actual ninja health agrees with the shared barracks growth calculation at level "+str(level))
			check((float(ninja.maxHp)>160)==(level>1) and (float(game._stats(ninja).damage)>51)==(level>1),"Permanent growth and evolution still strengthen the new base stats")
			check(int(ninja.evolution)==(0 if level==1 else 1 if level==4 else 2),"Ninja retains its existing evolution thresholds")
		game.free()
	var starter: Node2D=create_game()
	starter.configure_roster(catalog,["archer","spear"],{})
	var wallet: int=starter.gold
	var next_id: int=starter.next_id
	check(not starter.begin_placement("ninja") and starter.gold==wallet and starter.next_id==next_id,"Isolated late-role verification never unlocks ninja in the actual starter archer/spear roster")
	starter.free()

func ninja_pinned_target_and_loss() -> void:
	for phase in ["before_departure","movement","windup","blocked"]:
		var game: Node2D=create_game()
		var target: Dictionary=enemy_at(game,Vector2(.5,.5),"enemy_gunner",true)
		var ninja: Dictionary=recruit(game,"ninja")
		if ninja.is_empty(): game.free();continue
		game.ground_combat.step(0.0)
		var wallet: int=game.gold
		var home: Vector2=ninja.homePosition
		check(int(ninja.get("priorityTargetId",-1))==int(target.id) or int(ninja.get("targetId",-1))==int(target.id),"Produced ninja pins a valid stationary emplacement tower")
		if phase=="movement":
			tick(game,.4)
			check(ninja.position.distance_to(home)>.005,"Consumable assassin moves before its designated target disappears")
		elif phase=="windup":
			var prepared: bool=false
			for index in range(300):
				game.advance_simulation(.025)
				if not ninja.get("attackPlan",{}).is_empty(): prepared=true;break
			check(prepared,"Consumable assassin reaches a real attack windup")
		if phase=="blocked":
			var wall: float=(home.y+ninja.entryPosition.y)*.5
			game.ground_combat.structure_segment_clear=func(start: Vector2,end: Vector2,margin: float):
				return not (minf(start.y,end.y)-margin<=wall and maxf(start.y,end.y)+margin>=wall)
		else: target.hp=0
		var new_tower: Dictionary=enemy_at(game,Vector2(.44,.5),"enemy_archer",true)
		var infantry: Dictionary=enemy_at(game,ninja.position+Vector2(.003,0),"raider")
		var previous: Vector2=ninja.position
		var plan: Dictionary=ninja.get("attackPlan",{})
		if not plan.is_empty():
			game._release_unit_attack(ninja,plan)
			game._release_unit_attack(ninja,plan)
		tick(game,.1)
		check(ninja.position.distance_to(previous)<=.008,"Mission failure never teleports a ninja to another target or home")
		# Actual target cleanup may grant its real enemy kill reward; compare
		# consumption cost separately from ordinary enemy cleanup.
		if phase!="blocked": wallet+=int(target.reward)
		assert_consumed(game,ninja,wallet,"Ninja "+phase+" failure")
		check(float(new_tower.hp)==5000 and float(infantry.hp)==5000,"Failed consumable ninja never reassigns a new tower or falls back to ordinary infantry/self-defense")
		game.free()

func ninja_target_condition_at_release() -> void:
	for invalidation in ["role","stationary","fortification"]:
		var game: Node2D=create_game()
		var target: Dictionary=enemy_at(game,Vector2(.5,.5),"enemy_gunner",true)
		var ninja: Dictionary=recruit(game,"ninja")
		if ninja.is_empty(): game.free();continue
		for index in range(300):
			game.advance_simulation(.025)
			if not ninja.get("attackPlan",{}).is_empty(): break
		var plan: Dictionary=ninja.get("attackPlan",{})
		check(not plan.is_empty(),"Ninja "+invalidation+" fixture reaches native prepared attack")
		if invalidation=="role": target.combatRole=game.ENEMY_PATH_ROLE
		elif invalidation=="stationary": target.stationaryEnemy=false
		else: target.fortification=false
		var wallet: int=game.gold
		game._release_unit_attack(ninja,plan)
		check(float(target.hp)==5000,"Ninja release revalidates "+invalidation+" instead of species name")
		assert_consumed(game,ninja,wallet,"Ninja invalid "+invalidation)
		game.free()

func ninja_no_reassignment_or_self_defense() -> void:
	var game: Node2D=create_game()
	var original: Dictionary=enemy_at(game,Vector2(.5,.5),"enemy_gunner",true)
	var ninja: Dictionary=recruit(game,"ninja")
	if ninja.is_empty(): game.free();return
	game.ground_combat.step(0.0)
	var other: Dictionary=enemy_at(game,Vector2(.66,.5),"enemy_archer",true)
	check(not bool(game.order_assassination(int(other.id),int(ninja.id)).accepted) and int(ninja.priorityTargetId)==int(original.id),"A live consumable ninja cannot be reassigned from its pinned mission")
	var attacker: Dictionary=enemy_at(game,ninja.position+Vector2(.002,0),"raider")
	game._damage_friendly(ninja,10,attacker)
	tick(game,.15)
	check(float(attacker.hp)==5000 and float(other.hp)==5000 and int(ninja.priorityTargetId)==int(original.id),"Direct damage does not enable generic ninja self-defense or ordinary infantry pursuit")
	game.free()

func ninja_success_and_shared_target() -> void:
	var game: Node2D=create_game()
	var target: Dictionary=enemy_at(game,Vector2(.5,.5),"enemy_archer",true)
	var ninja: Dictionary=recruit(game,"ninja")
	if ninja.is_empty(): game.free();return
	game.ground_combat.step(0.0)
	var second: Dictionary=recruit(game,"ninja")
	if second.is_empty(): game.free();return
	game.ground_combat.step(0.0)
	check(int(ninja.get("priorityTargetId",-1))==int(target.id) and int(second.get("priorityTargetId",-1))==int(target.id),"Multiple consumable ninjas can pin the same living tower independently")
	var wallet: int=game.gold
	target.hp=1;target.maxHp=1
	var before: int=events.size()
	tick(game,8)
	var kills: Array=[]
	for event in events.slice(before):
		if str(event.get("type",""))=="killed" and int(event.get("victimId",-1))==int(target.id): kills.append(event)
	check(float(target.hp)<=0 and kills.size()==1 and game.kills==1,"Shared tower death emits one actual enemy kill and one reward")
	assert_consumed(game,ninja,wallet+int(target.reward),"Successful ninja mission")
	assert_consumed(game,second,wallet+int(target.reward),"Shared target ended ninja mission")
	var surviving: Dictionary=enemy_at(game,Vector2(.47,.5),"enemy_gunner",true)
	tick(game,2)
	check(game.units.is_empty() and float(surviving.hp)==5000,"Consumed successful ninjas are irreusable even when a new tower appears")
	game.free()

func counterattack_uses_enemy_rules() -> void:
	var game: Node2D=create_game()
	var guard: Dictionary=recruit(game,"naginata",Vector2(.5,.5))
	if guard.is_empty(): game.free();return
	var enemy: Dictionary=enemy_at(game,Vector2(.541,.5),"enemy_samurai")
	enemy.speed=.03;enemy.attackCooldown=0
	var hp: float=guard.hp
	var start: Vector2=enemy.position
	game.ground_combat.counterattack(enemy,.025,guard)
	check(float(guard.hp)==hp and enemy.get("counterPlan",{}).is_empty(),"Enemy counterattack does not inherit naginata's longer friendly reach")
	check(enemy.position.distance_to(start)>.0 and enemy.position.distance_to(start)<.01,"A mobile enemy closes its own remaining melee gap continuously")
	enemy.position=Vector2(.529,.5)
	game.ground_combat.counterattack(enemy,.025,guard)
	check(not enemy.get("counterPlan",{}).is_empty(),"Enemy within its own melee range prepares its existing attack cycle")
	enemy.animationClock=.3;enemy.position=Vector2(.55,.5)
	game.ground_combat.counterattack(enemy,.025,guard)
	check(float(guard.hp)==hp,"Counterattack release rechecks its own distance after contact separates")
	enemy.position=Vector2(.525,.5);enemy.attackCooldown=0
	game.ground_combat.counterattack(enemy,.025,guard)
	enemy.animationClock=.3
	game.ground_combat.counterattack(enemy,.025,guard)
	check(float(guard.hp)<hp,"Valid enemy contact still deals actual reciprocal damage using enemy rules")
	var before: float=guard.hp
	var stale: Dictionary=guard.duplicate(true)
	game.ground_combat.counterattack(enemy,.5,stale)
	check(float(guard.hp)==before and float(stale.hp)==before,"A stale friendly dictionary with a matching numeric ID cannot receive a counterattack")
	game.free()

func closed_battle_consumes_ninja() -> void:
	for action in ["finish","wave","close"]:
		var game: Node2D=create_game()
		var tower: Dictionary=enemy_at(game,Vector2(.5,.5),"enemy_archer",true)
		var ninja: Dictionary=recruit(game,"ninja")
		if ninja.is_empty(): game.free();continue
		var wallet: int=game.gold
		if action=="finish": game._finish(true)
		elif action=="wave": game._complete_wave()
		else: game.close_battle()
		check(game.units.is_empty() and game.snapshot().units.is_empty(),"Ninja is absent from final active snapshot after "+action)
		var expected_wallet: int=wallet+(40+game.wave*3 if action=="wave" else 0)
		check(game.gold==expected_wallet and game.death_actors.is_empty() and game.kills==0,"Battle "+action+" preserves only existing wave supply and consumes ninja without refund, casualty, or fake kill reward")
		game.free()

func event_map_change_boundaries() -> void:
	var game: Node2D=create_game()
	for index in range(2):
		check(game.begin_placement("ninja",0),"Parallel no-target ninja order is accepted")
		var point: Vector2=Vector2(-1,-1)
		for zone in game.zones:
			if str(zone.get("placementRole",""))=="ambush" and game.placement_preview(zone.position).valid: point=zone.position;break
		check(point.x>=0 and game.place_unit(point.x,point.y),"Parallel ninja order reserves a separate real site")
	var replacement: Dictionary=fixture();replacement.id="unit-behavior-after-event-reset"
	var consumed: Array=[]
	game.game_event.connect(func(event: Dictionary):
		if str(event.get("type",""))=="unit_consumed":
			consumed.append(event.duplicate(true))
			if consumed.size()==1: game.load_map(replacement))
	tick(game,4.1)
	check(consumed.size()==1 and str(consumed[0].mapId)=="unit-behavior-isolated-fixture","Consumption callback map reset cannot publish a second old actor under a new map")
	check(str(game.config.id)==replacement.id and not game.running and game.elapsed==0 and game.units.is_empty(),"A consumption-triggered replacement map is not advanced by the old simulation step")
	game.free()

	game=create_game()
	var guard: Dictionary=recruit(game,"naginata",Vector2(.5,.5))
	if guard.is_empty(): game.free();return
	var enemy: Dictionary=enemy_at(game,Vector2(.53,.5))
	game.ground_combat.step(0.0);game._update_units(.01)
	var plan: Dictionary=guard.attackPlan
	check(not plan.is_empty(),"Shot callback fixture uses a genuine native prepared attack")
	var hp: float=enemy.hp
	game.game_event.connect(func(event: Dictionary):
		if str(event.get("type",""))=="shot": game.load_map(replacement))
	game._release_unit_attack(guard,plan)
	check(str(game.config.id)==replacement.id and float(enemy.hp)==hp and game.projectiles.is_empty(),"Shot callback map reset stops old damage and projectile continuation")
	var effects: int=game.effects.size()
	var start_events: int=events.size()
	game._release_unit_attack(guard,plan)
	check(events.size()==start_events and game.effects.size()==effects and float(enemy.hp)==hp,"Old generation attack replay cannot emit another shot or mutate replacement effects")
	game.free()


func counterattack_event_boundaries() -> void:
	for reset in ["recursive","map","close"]:
		var game: Node2D=create_game()
		var guard: Dictionary=recruit(game,"naginata",Vector2(.5,.5))
		if guard.is_empty(): game.free();continue
		var enemy: Dictionary=enemy_at(game,Vector2(.525,.5),"enemy_samurai")
		enemy.attackCooldown=0
		game.ground_combat.counterattack(enemy,.025,guard)
		var planned: float=float(enemy.counterPlan.damage)
		enemy.animationClock=.3
		var hp: float=guard.hp
		var shot_count: Array=[0]
		game.game_event.connect(func(event: Dictionary):
			if str(event.get("type",""))!="shot" or int(event.get("actorId",-1))!=int(enemy.id): return
			shot_count[0]+=1
			if reset=="map":
				var replacement: Dictionary=fixture();replacement.id="counter-reset-map"
				game.load_map(replacement)
			elif reset=="close": game.close_battle()
			elif int(shot_count[0])==1: game.ground_combat.counterattack(enemy,.025,guard))
		game.ground_combat.counterattack(enemy,.025,guard)
		check(int(shot_count[0])==1,"A counter shot callback is consumed before recursive combat notification")
		if reset=="map":
			check(float(guard.hp)==hp and str(game.config.id)=="counter-reset-map" and game.units.is_empty(),"Counter shot callback map reset prevents damage to a detached old guard")
		elif reset=="close":
			check(float(guard.hp)==hp and game.battle_closed,"Counter shot callback closing a battle stops damage to its guard")
		else:
			var damage: float=hp-float(guard.hp)
			check(damage>0 and damage<=planned and events.filter(func(event: Dictionary): return str(event.get("type",""))=="hit" and str(event.get("victimSide",""))=="friendly").size()==1,"Reentrant counter callback produces one armor-adjusted actual HP loss")
		game.free()

func secondary_damage_map_boundary() -> void:
	var game: Node2D=create_game({"naginata":3})
	var guard: Dictionary=recruit(game,"naginata",Vector2(.5,.5))
	if guard.is_empty(): game.free();return
	var primary: Dictionary=enemy_at(game,Vector2(.53,.5))
	var first: Dictionary=enemy_at(game,Vector2(.543,.5),"raider")
	var next: Dictionary=enemy_at(game,Vector2(.557,.5),"raider")
	game.ground_combat.step(0.0);game._update_units(.01)
	var plan: Dictionary=guard.attackPlan
	check(not plan.is_empty(),"Secondary callback fixture prepares a genuine unlocked naginata sweep")
	var replacement: Dictionary=fixture();replacement.id="after-secondary-event-reset"
	game.game_event.connect(func(event: Dictionary):
		if str(event.get("type",""))=="hit" and int(event.get("victimId",-1))==int(first.id): game.load_map(replacement))
	var start: int=events.size()
	game._release_unit_attack(guard,plan)
	check(float(primary.hp)<5000 and float(first.hp)<5000 and float(next.hp)==5000,"Map reset inside the first secondary HP event stops all remaining old sweep damage")
	check(str(game.config.id)==replacement.id and game.units.is_empty() and game.enemies.is_empty(),"Secondary damage callback leaves its replacement battle empty and untouched")
	check(not events.slice(start).any(func(event: Dictionary): return str(event.get("type",""))=="skill_hit"),"No stale secondary skill notification is emitted after its HP callback changes the map")
	game.free()

func actual_training_controller() -> void:
	for type_name in TYPES:
		var controller: Control=Training.new()
		controller.render_enabled=false
		root.add_child(controller)
		controller.configure(null,[fixture()],null)
		var completed: Array=[]
		controller.completed.connect(func(id: String): completed.append(id))
		check(controller.open(str(type_name),fixture()),"Actual isolated training controller opens "+str(type_name)+" on synthetic geometry")
		controller.set_process(false)
		check(controller.deploy(),"Actual training deploy action accepts "+str(type_name))
		if controller.phase=="placing": check(controller.place_at(controller.recommended),"Actual training confirms its recommended legal "+str(type_name)+" position")
		for index in range(3200):
			if controller.phase in ["success","failed"]: break
			controller.advance_training(.025)
		check(controller.phase=="success","Actual training "+str(type_name)+" completes from native combat/support evidence: "+str(controller.error_ko))
		check(completed==[str(type_name)] and bool(controller.session_completed.get(str(type_name),false)),"Training "+str(type_name)+" records one real completion and its isolated session flag")
		if type_name=="ninja":
			check(float(controller.observations.get("fortDamage",0))>0 and bool(controller.observations.get("fortDestroyed",false)) and controller.battle.units.is_empty(),"Consumable ninja training requires actual tower damage/destruction and actor disappearance")
			check(not bool(controller.observations.get("returnObserved",false)),"Consumable ninja training no longer requires a reusable concealment return")
		observations["training-"+str(type_name)]=controller.diagnostics()
		controller.close();controller.free()
	var empty: Control=Training.new();empty.render_enabled=false;root.add_child(empty)
	empty.configure(null,[],null)
	check(empty._practice_map("archer").is_empty() and not empty.open("archer",{}),"Empty production map catalog cannot fabricate a playable training battlefield")
	empty.free()
	var failed: Control=Training.new();failed.render_enabled=false;root.add_child(failed)
	failed.configure(null,[fixture()],null)
	check(failed.open("ninja",fixture()) and failed.deploy() and failed.place_at(failed.recommended),"Ninja failed-training fixture accepts an actual paid order")
	failed.set_process(false)
	if not failed._fort_target.is_empty(): failed._fort_target.hp=0
	for index in range(250):
		if failed.phase=="failed": break
		failed.advance_training(.025)
	check(failed.phase=="failed" and not bool(failed.session_completed.get("ninja",false)),"Target disappearance cannot falsely complete or train a consumed ninja")
	check(not bool(failed.observations.get("unitFallen",false)),"Failed consumed ninja training does not misreport a combat death")
	failed.close();failed.free()

func unchanged_other_roles() -> void:
	for type_name in ["archer","gunner"]:
		var game: Node2D=create_game()
		var unit: Dictionary=recruit(game,type_name)
		if unit.is_empty(): game.free();continue
		var home: Vector2=unit.position
		var enemy: Dictionary=enemy_at(game,Vector2(home.x+.035,.5),"raider")
		check(wait_damage(game,enemy),type_name+" retains its existing stationary firing behavior")
		check(unit.position==home,type_name+" never turns into a pursuit unit")
		game.free()
	for type_name in ["spear","samurai","commander"]:
		var game: Node2D=create_game()
		var unit: Dictionary=recruit(game,type_name)
		if unit.is_empty(): game.free();continue
		var initial: Vector2=unit.position
		tick(game,3.1)
		check(unit.position.x<initial.x and int(unit.postPathIndex)==0,type_name+" marches forward on its selected path")
		var enemy: Dictionary=enemy_at(game,unit.position+Vector2(-.05,0),"raider")
		check(wait_damage(game,enemy),type_name+" retains reachable contact combat")
		enemy.hp=0;var before: float=unit.position.x
		tick(game,1.7)
		check(unit.position.x<before,type_name+" resumes existing forward progress after contact ends")
		game.free()
	var game: Node2D=create_game()
	var monk: Dictionary=recruit(game,"monk",Vector2(.5,.5))
	var gunner: Dictionary=recruit(game,"gunner",Vector2(.57,.5))
	if monk.is_empty() or gunner.is_empty(): game.free();return
	var enemy: Dictionary=enemy_at(game,Vector2(.51,.5),"raider")
	gunner.hp-=30;gunner.cooldown=10000
	var initial_hp: float=gunner.hp
	var home: Vector2=monk.position
	tick(game,1.5)
	check(gunner.hp>initial_hp and float(enemy.hp)==5000 and monk.position==home,"Monk remains a stationary healer and never falls back to an ordinary enemy attack")
	check(game.ground_combat.attack_target(monk).is_empty() and monk.attackPlan.is_empty(),"Monk has no attack preparation or primary enemy target")
	game.free()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var expected: String=ProjectSettings.globalize_path("res://tests/profiles/unit-behavior-").replace("\\","/").to_lower()
	if not profile.begins_with(expected): push_error("Unit behavior QA refuses the player's save profile");quit(2);return
	initial_hashes=hashes()
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	guard_roles_and_recognition()
	guard_zone_and_escape()
	guard_blocked_internal_route()
	guard_concave_path_footprint()
	guard_windup_release_rules()
	guard_dash_and_secondary()
	ninja_no_target_consumption()
	ninja_preview_no_consumption()
	ninja_stats_growth_and_unlocks()
	ninja_pinned_target_and_loss()
	ninja_target_condition_at_release()
	ninja_no_reassignment_or_self_defense()
	ninja_success_and_shared_target()
	counterattack_uses_enemy_rules()
	closed_battle_consumes_ninja()
	event_map_change_boundaries()
	counterattack_event_boundaries()
	secondary_damage_map_boundary()
	actual_training_controller()
	unchanged_other_roles()
	check(hashes()==initial_hashes,"Behavior and training source files stay unchanged throughout final CPU verification")
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"sourceHashes":initial_hashes,"sourceFreezeUnchanged":hashes()==initial_hashes,"scope":"Map-independent CPU recruitment, guard primary roles/recognition/zone/full segment footprint/dash/return/internal barriers/concave path/release, consumable ninja tower class/acceptance/absence/no-refund/stale IDs/vanish before departure and movement and windup/shared target/blocked ingress/no reassignment, own-enemy counter range/reentrant events/map reset/terminal cleanup, actual isolated all-eight-role training controllers and shared barracks growth, unchanged stationary/march/heal roles. Not GPU motion or natural campaign-wave verification. Latest human policy: ninja is consumable, no reuse, no concealment wait/return or self-defense fallback."}
	var path: String="user://qa_unit_behavior_contracts.json"
	var output: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("UNIT_BEHAVIOR ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path(path))
	quit(0 if failures.is_empty() else 1)
