extends SceneTree
## Native component QA: paid units, original stats and committed game receipts.
## Fixture positions and held spawns isolate the bridge, not campaign balance.
const Battle = preload("res://native/game.gd")
const Bridge = preload("res://native/troop_action_presentation.gd")
const Troops = preload("res://native/troops_3d.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var catalog: Array = []
var events: Array = []
var checks: int = 0
var failures: Array[String] = []
var observations: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size() <= 30: push_error("ACTION BRIDGE: " + note)

func fixture() -> Dictionary:
	return {"id":"troop-action-bridge-native","stageNumber":20,"theme":"farm","initialGold":4000,"unitLimit":24,"totalWaves":100,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":1000}],"buildZones":[{"id":"wall","x":.5,"y":.7,"r":.14,"elevation":1}],"tactics":{"groundPosts":[{"id":"post","nameKo":"전선","pathIndex":0,"segmentIndex":0,"t":.5,"r":.22,"guardRadius":.22,"mobilityFactor":1.0}]}}

func make_game() -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,TYPES,{})
	game.load_map(fixture())
	game.set_seed(57831)
	game.game_event.connect(func(value: Dictionary): events.append(value.duplicate(true)))
	game.start_battle()
	game.enemies.clear()
	game.spawn_queue=["raider"]
	game.spawn_source_waves=[1]
	game.spawn_metadata=[{}]
	game.spawn_clock=100000.0
	return game

func recruit(game: Node2D, type_name: String, point: Vector2 = Vector2(-1,-1)) -> Dictionary:
	var wallet: int = int(game.gold)
	var cost: int = int(game.recruit_cost(type_name))
	var first_id: int = int(game.next_id)
	check(game.begin_placement(type_name,0),type_name+" enters the real recruitment API")
	if str(game.placement_contract(type_name).deploymentKind) != "marching":
		if point.x < 0:
			for zone in game.zones:
				var hint: Vector2 = game._zone_placement_hint(zone,type_name)
				if hint.x >= 0 and bool(game.placement_preview(hint).get("valid",false)):
					point=hint
					break
		check(point.x >= 0 and game.place_unit(point.x,point.y),type_name+" commits a legal paid placement")
	check(int(game.gold)==wallet-cost,type_name+" pays the catalog price once")
	for index in range(600):
		game.advance_simulation(.025)
		for unit in game.units:
			if int(unit.id) >= first_id and str(unit.type)==type_name:
				check(float(unit.hp)==float(unit.maxHp) and int(unit.campaignLevel)==1,type_name+" arrives with original level-one native HP")
				return unit
	check(false,type_name+" actually finishes production")
	return {}

func enemy_at(game: Node2D, point: Vector2, kind: String = "raider", options: Dictionary = {}) -> Dictionary:
	var spawn: Dictionary = {"pathIndex":0}
	spawn.merge(options,true)
	var enemy: Dictionary = game._spawn_enemy(kind,1,spawn)
	check(not enemy.is_empty(),kind+" spawns through the native enemy API")
	if not enemy.is_empty():
		# Only fixture geometry/movement is controlled; damage, HP and attack
		# intervals remain exactly those created by the native spawn API.
		enemy.position=point
		enemy.pointIndex=1
		enemy.speed=0.0
	return enemy

func count_events(type_name: String, actor_id: int) -> int:
	var count: int = 0
	for event in events:
		if str(event.type)==type_name and int(event.get("actorId",-1))==actor_id: count+=1
	return count

func combat_fingerprint(game: Node2D) -> String:
	return JSON.stringify({"units":game.units,"enemies":game.enemies,"projectiles":game.projectiles,"deaths":game.death_actors,"effects":game.effects,"queue":game.recruitment_queue,"pending":game.pending,"gold":game.gold,"kills":game.kills,"recruits":game.recruits,"nextId":game.next_id,"eventId":game.next_event_id,"elapsed":game.elapsed,"animationTime":game.animation_time,"generation":game.battle_generation,"skillClock":game.unit_skills.clock,"skillReleases":game.unit_skills._seen_releases,"events":events})

func assert_read_only(game: Node2D, bridge: RefCounted, actor_id: int, note: String, renderer: Control = null) -> void:
	var first: String = JSON.stringify(bridge.state_for_id(actor_id))
	var before: String = combat_fingerprint(game)
	for index in range(4):
		check(JSON.stringify(bridge.state_for_id(actor_id))==first,note+": repeated adapter reads do not advance presentation")
		if renderer != null: renderer.sync_actor_states(game.actor_states())
	check(combat_fingerprint(game)==before,note+": rendering cannot change HP, positions, cooldowns, receipts or economy")

func make_renderer(game: Node2D) -> Control:
	var renderer: Control = Troops.new()
	root.add_child(renderer)
	renderer.set_process(false)
	renderer.set_stage(fixture())
	renderer.bind_battle(game)
	return renderer

func test_native_attacks() -> void:
	var rows: Array = []
	for type_name in ["archer","spear","samurai","gunner","naginata","commander"]:
		events.clear()
		var game: Node2D = make_game()
		var bridge: RefCounted = Bridge.new()
		bridge.bind(game)
		var unit: Dictionary = recruit(game,str(type_name))
		if unit.is_empty(): bridge.unbind();game.free();continue
		var point: Vector2 = unit.position+Vector2(-.022,0)
		if type_name=="archer": point=Vector2(unit.position.x,.5)
		elif type_name=="gunner": point=unit.position+Vector2(-.08,0)
		var enemy: Dictionary = enemy_at(game,point,"enemy_samurai" if type_name=="naginata" else "raider")
		var initial_hp: float = float(enemy.hp)
		var interval: float = float(game._stats(unit).interval)
		for index in range(400):
			game.advance_simulation(.005)
			if not unit.get("attackPlan",{}).is_empty(): break
		var plan: Dictionary = unit.get("attackPlan",{}).duplicate(true)
		check(not plan.is_empty(),str(type_name)+" schedules an actual native attack")
		if plan.is_empty(): bridge.unbind();game.free();continue
		var state: Dictionary = bridge.state_for_id(int(unit.id))
		check(str(state.motionPhase)=="windup" and not bool(state.attackReleased),str(type_name)+" prepares without inventing a release")
		check(absf(float(state.releaseTime)-float(plan.releaseTime))<.000001 and int(state.targetId)==int(plan.targetId),str(type_name)+" preparation uses the real plan target and release deadline")
		check(count_events("shot",int(unit.id))==0 and float(enemy.hp)==initial_hp,str(type_name)+" has no native damage/release during preparation")
		assert_read_only(game,bridge,int(unit.id),str(type_name)+" preparation")
		var renderer: Control = make_renderer(game) if type_name=="gunner" else null
		for index in range(400):
			game.advance_simulation(.005)
			state=bridge.state_for_id(int(unit.id))
			if count_events("shot",int(unit.id))>0: break
		check(count_events("shot",int(unit.id))==1 and bool(state.attackReleased) and str(state.motionPhase)=="release",str(type_name)+" release is backed by exactly one real shot receipt")
		check(absf(float(game._stats(unit).interval)-interval)<.000001,str(type_name)+" presentation preserves the original attack interval")
		var real_result: bool = float(enemy.hp)<initial_hp
		for projectile in game.projectiles:
			if int(projectile.get("sourceId",-1))==int(unit.id): real_result=true
		check(real_result,str(type_name)+" release corresponds to actual HP loss or its native projectile")
		assert_read_only(game,bridge,int(unit.id),str(type_name)+" release",renderer)
		if renderer != null:
			var key: String = str(unit.id)+":0"
			check(renderer.actors.has(key),"Actual gunner state reaches its existing articulated model")
			if renderer.actors.has(key):
				var model: Node3D = renderer.actors[key]
				var weapon: Transform3D = model.bones.weapon.global_transform
				var left: Vector3 = model.bones.footL.global_position
				var right: Vector3 = model.bones.footR.global_position
				renderer.sync_actor_states(game.actor_states())
				check(model.bones.weapon.global_transform.is_equal_approx(weapon) and model.bones.footL.global_position.is_equal_approx(left) and model.bones.footR.global_position.is_equal_approx(right),"Duplicate gunner renders freeze its weapon and foot pose")
		var saw_recovery: bool = false
		var saw_reload: bool = false
		for index in range(240):
			game.advance_simulation(.005)
			state=bridge.state_for_id(int(unit.id))
			saw_recovery=saw_recovery or str(state.motionPhase)=="recovery"
			if str(state.motionPhase)=="reload":
				saw_reload=true
				check(bool(state.reloadActive) and float(unit.cooldown)>0 and float(state.reloadProgress)>=0 and float(state.reloadProgress)<=1,"Native gunner reload follows its remaining cooldown")
				assert_read_only(game,bridge,int(unit.id),"Native gunner reload",renderer)
				break
			if str(unit.animation)!="attack" and type_name!="gunner": break
		check(saw_recovery,str(type_name)+" recovers only after its committed release")
		if type_name=="gunner": check(saw_reload,"Native gunner displays cooldown-based reload")
		rows.append({"type":type_name,"targetId":int(plan.targetId),"releaseTime":float(plan.releaseTime),"interval":interval,"recovery":saw_recovery,"reload":saw_reload})
		if type_name=="gunner":
			check(not bridge.attacks.is_empty(),"Generation reset fixture contains an actual gunner attack receipt")
			var generation: int = int(game.battle_generation)
			game.load_map(fixture())
			bridge.state_for_id(int(unit.id))
			check(int(game.battle_generation)>generation and bridge.attacks.is_empty(),"Map reset invalidates the populated native attack receipt")
		if renderer != null: renderer.free()
		bridge.unbind()
		game.free()
	observations["nativeAttacks"]=rows

func test_cancel_and_freeze() -> void:
	events.clear()
	var game: Node2D = make_game()
	var bridge: RefCounted = Bridge.new()
	bridge.bind(game)
	var unit: Dictionary = recruit(game,"archer")
	if unit.is_empty(): bridge.unbind();game.free();return
	var enemy: Dictionary = enemy_at(game,Vector2(unit.position.x,.5))
	for index in range(400):
		game.advance_simulation(.005)
		if not unit.get("attackPlan",{}).is_empty(): break
	check(not unit.get("attackPlan",{}).is_empty(),"Cancellation fixture has a real pending shot")
	var prepared: String = JSON.stringify(bridge.state_for_id(int(unit.id)))
	var frozen: String = combat_fingerprint(game)
	game.paused=true
	game.advance_simulation(.8)
	check(combat_fingerprint(game)==frozen and JSON.stringify(bridge.state_for_id(int(unit.id)))==prepared,"Explicit pause freezes native preparation and presentation clocks")
	game.paused=false
	game.between_waves=true
	game.advance_simulation(.8)
	check(combat_fingerprint(game)==frozen and JSON.stringify(bridge.state_for_id(int(unit.id)))==prepared,"Study freezes pending attack, HP, cooldown and presentation")
	game.between_waves=false
	var initial_hp: float = float(enemy.hp)
	game.enemies.erase(enemy)
	var cancelled: bool = false
	for index in range(200):
		game.advance_simulation(.005)
		var state: Dictionary = bridge.state_for_id(int(unit.id))
		if bool(state.get("attackCancelled",false)):
			cancelled=true
			check(not bool(state.attackReleased) and str(state.motionPhase)=="cancelled","A rejected native release cannot display a committed shot")
			break
	check(cancelled and count_events("shot",int(unit.id))==0 and game.projectiles.is_empty() and float(enemy.hp)==initial_hp,"Removed target cancels without fabricated projectile or damage")
	assert_read_only(game,bridge,int(unit.id),"Cancelled release")
	bridge.unbind()
	game.free()

func test_native_heal() -> void:
	events.clear()
	var game: Node2D = make_game()
	var bridge: RefCounted = Bridge.new()
	bridge.bind(game)
	var monk: Dictionary = recruit(game,"monk",Vector2(.44,.5))
	var ally: Dictionary = recruit(game,"naginata",Vector2(.56,.5))
	if monk.is_empty() or ally.is_empty(): bridge.unbind();game.free();return
	var attacker: Dictionary = enemy_at(game,Vector2(.54,.5),"enemy_gunner")
	var native_loss: float = float(game._damage_friendly(ally,12.0,attacker))
	check(native_loss>0 and float(ally.hp)<float(ally.maxHp),"Actual native incoming damage supplies the heal fixture")
	game.enemies.erase(attacker)
	var before_hp: float = float(ally.hp)
	var committed: Dictionary = {}
	for index in range(500):
		game.advance_simulation(.005)
		for event in events:
			if str(event.type)=="heal" and int(event.get("actorId",-1))==int(monk.id) and int(event.get("victimId",-1))==int(ally.id): committed=event
		if not committed.is_empty(): break
	check(not committed.is_empty(),"Original native healing pulse produces a positive receipt")
	if not committed.is_empty():
		var state: Dictionary = bridge.state_for_id(int(monk.id))
		check(str(state.motionPhase)=="heal" and int(state.get("healingTargetId",-1))==int(ally.id),"Healing pose identifies the actual recovered ally")
		check(absf(float(ally.hp)-before_hp-float(committed.healAmount))<.000001 and absf(float(state.get("healAmount",0))-float(committed.healAmount))<.000001,"Healing state reflects HP already committed at pose start")
		check(absf(float(state.get("healCommittedAt",-1))-float(game.animation_time))<.000001,"Healing commit timestamp precedes no invented preparation delay")
		var renderer: Control = make_renderer(game)
		assert_read_only(game,bridge,int(monk.id),"Actual monk heal",renderer)
		check(count_events("shot",int(monk.id))==0,"Monk rendering cannot invent an attack")
		renderer.free()
		observations["nativeHeal"]={"amount":committed.healAmount,"targetId":ally.id,"committedAt":state.healCommittedAt}
		check(not bridge.heals.is_empty(),"Generation reset fixture contains an actual HP-heal receipt")
		game.load_map(fixture())
		bridge.state_for_id(int(monk.id))
		check(bridge.heals.is_empty(),"Map reset invalidates the populated native heal receipt")
	bridge.unbind()
	game.free()

func test_enemy_plans() -> void:
	var rows: Array = []
	for spec in [{"unit":"monk","enemy":"enemy_gunner","ranged":true},{"unit":"spear","enemy":"raider","ranged":false},{"unit":"naginata","enemy":"enemy_samurai","ranged":false}]:
		events.clear()
		var game: Node2D = make_game()
		var bridge: RefCounted = Bridge.new()
		bridge.bind(game)
		var ranged: bool = bool(spec.ranged)
		var unit: Dictionary = recruit(game,str(spec.unit))
		if unit.is_empty(): bridge.unbind();game.free();continue
		var point: Vector2 = unit.position+Vector2(-.10 if ranged else -.018,0)
		var enemy: Dictionary = enemy_at(game,point,str(spec.enemy))
		var plan_key: String = "rangedPlan" if ranged else "counterPlan"
		for index in range(400):
			game.advance_simulation(.005)
			if not enemy.get(plan_key,{}).is_empty(): break
		var plan: Dictionary = enemy.get(plan_key,{}).duplicate(true)
		check(not plan.is_empty(),"Native enemy creates "+plan_key+" through actual targeting")
		if plan.is_empty(): bridge.unbind();game.free();continue
		var state: Dictionary = bridge.state_for_id(int(enemy.id))
		check(str(state.motionPhase)=="windup" and int(state.targetId)==int(unit.id) and absf(float(state.releaseTime)-float(plan.releaseTime))<.000001,"Enemy preparation reads its real "+plan_key)
		assert_read_only(game,bridge,int(enemy.id),"Enemy "+plan_key)
		for index in range(200):
			game.advance_simulation(.023)
			state=bridge.state_for_id(int(enemy.id))
			if count_events("shot",int(enemy.id))>0: break
		check(count_events("shot",int(enemy.id))==1 and bool(state.attackReleased),"Enemy "+plan_key+" release uses one actual enemy receipt")
		check(absf(float(state.releaseTime)-float(plan.releaseTime))<.000001,"Enemy release preserves its original preparation deadline after plan consumption")
		assert_read_only(game,bridge,int(enemy.id),"Enemy committed release")
		if ranged:
			var saw_reload: bool = false
			for index in range(160):
				game.advance_simulation(.005)
				state=bridge.state_for_id(int(enemy.id))
				if str(state.motionPhase)=="reload": saw_reload=true;break
			check(saw_reload and bool(state.reloadActive) and float(enemy.attackCooldown)>0,"Enemy gunner reload follows its native attackCooldown")
		rows.append({"kind":enemy.kind,"plan":plan_key,"releaseTime":plan.releaseTime})
		bridge.unbind()
		game.free()
	observations["enemyPlans"]=rows

func test_consumed_fade() -> void:
	events.clear()
	var game: Node2D = make_game()
	var bridge: RefCounted = Bridge.new()
	bridge.bind(game)
	check(not game.ground_combat.ambush_sites.is_empty(),"Single-use native ninja has an actual ambush placement")
	if game.ground_combat.ambush_sites.is_empty(): bridge.unbind();game.free();return
	var site: Dictionary = game.ground_combat.ambush_sites[0]
	var target: Dictionary = enemy_at(game,site.entryPosition,"enemy_archer",{"fortification":true})
	var unit: Dictionary = recruit(game,"ninja",site.position)
	if unit.is_empty(): bridge.unbind();game.free();return
	check(int(unit.get("priorityTargetId",-1))==int(target.id),"Actual produced ninja commits to its native tower attacker")
	var renderer: Control = make_renderer(game)
	renderer.sync_actor_states(game.actor_states())
	var key: String = str(unit.id)+":0"
	check(renderer.actors.has(key),"Consumed fade starts from the already existing ninja model")
	game.select_unit(int(unit.id))
	var wallet: int = int(game.gold)
	var recruit_count: int = int(game.recruits)
	game.enemies.erase(target)
	game.advance_simulation(.005)
	var departure: Dictionary = bridge.departure_state(int(unit.id))
	check(count_events("unit_consumed",int(unit.id))==1 and not departure.is_empty() and str(departure.get("reason",""))=="target_lost","Real target disappearance commits one native consumption receipt")
	check(game.ground_combat._unit(int(unit.id)).is_empty() and float(unit.hp)>0 and int(game.selected_id)==-1,"Consumed ninja leaves simulation/selection with surviving HP")
	check(not game.death_actors.any(func(actor: Dictionary): return int(actor.id)==int(unit.id)) and count_events("unit_fallen",int(unit.id))==0,"Consumption creates no corpse or fake death receipt")
	check(int(game.gold)==wallet and int(game.recruits)==recruit_count,"Consumption grants no refund or replacement recruit")
	renderer.sync_actor_states(game.actor_states())
	check(renderer.actors.has(key) and renderer.actors[key].has_meta("departure"),"Native consumption retains only its existing model for the fade")
	check(renderer.health_anchor_for(int(unit.id)).is_empty(),"Consumed fade has no health marker or targetable actor state")
	var before: String = combat_fingerprint(game)
	for index in range(4): renderer.sync_actor_states(game.actor_states())
	check(combat_fingerprint(game)==before,"Repeated departure render cannot restore unit, HP, money or emit gameplay events")
	var progress: float = float(bridge.departure_state(int(unit.id)).get("progress",-1))
	game.paused=true
	game.advance_simulation(.5)
	renderer.sync_actor_states(game.actor_states())
	check(float(bridge.departure_state(int(unit.id)).get("progress",-2))==progress,"Pause freezes the existing consumed fade")
	game.paused=false
	game.between_waves=true
	game.advance_simulation(.5)
	renderer.sync_actor_states(game.actor_states())
	check(float(bridge.departure_state(int(unit.id)).get("progress",-2))==progress,"Study freezes the consumed fade")
	game.between_waves=false
	game.advance_simulation(.15)
	renderer.sync_actor_states(game.actor_states())
	check(renderer.actors.has(key) and float(bridge.departure_state(int(unit.id)).get("progress",0))>.45,"Fade progresses only with actual resumed animation time")
	game.advance_simulation(.16)
	renderer.sync_actor_states(game.actor_states())
	check(not renderer.actors.has(key) and renderer.health_anchor_for(int(unit.id)).is_empty(),"Existing consumed model disappears when its actual fade ends")
	check(count_events("unit_consumed",int(unit.id))==1 and count_events("shot",int(unit.id))==0 and count_events("heal",int(unit.id))==0 and count_events("unit_fallen",int(unit.id))==0,"Fade adds no extra consumption, shot, heal or death")
	observations["consumedFade"]={"reason":departure.get("reason",""),"receiptCount":count_events("unit_consumed",int(unit.id)),"refund":int(game.gold)-wallet,"corpse":false,"modelExpired":not renderer.actors.has(key)}
	var generation: int = int(game.battle_generation)
	game.load_map(fixture())
	bridge.state_for_id(int(unit.id))
	check(int(game.battle_generation)>generation and bridge.attacks.is_empty() and bridge.heals.is_empty() and bridge.departures.is_empty(),"Map generation reset clears every old attack/heal/departure receipt")
	var reset_before: String = combat_fingerprint(game)
	renderer.sync_actor_states(game.actor_states())
	check(combat_fingerprint(game)==reset_before and renderer.actors.is_empty(),"A reset renderer cannot create old units, effects or refunds")
	renderer.free()
	bridge.unbind()
	game.free()

func run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\","/").to_lower()
	var allowed: String = ProjectSettings.globalize_path("res://tests/profiles/troop-action-bridge/").replace("\\","/").to_lower()
	if not profile.begins_with(allowed): push_error("Action bridge QA refuses the player's profile");quit(2);return
	var bridge_script: Script = Bridge
	var battle_script: Script = Battle
	var renderer_script: Script = Troops
	if not bridge_script.can_instantiate() or not battle_script.can_instantiate() or not renderer_script.can_instantiate():
		push_error("Action bridge dependencies failed compilation; no valid QA report can be produced")
		quit(2)
		return
	catalog=(JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")) as Dictionary).get("units",[])
	test_native_attacks()
	test_cancel_and_freeze()
	test_native_heal()
	test_enemy_plans()
	test_consumed_fade()
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"scope":"Headless native component QA with paid production and original level-one HP/damage/intervals. Actual friendly plans/releases, enemy ranged/counter plans, HP committed healing, cancellation, pause/study, read-only duplicate render, native single-use consumption fade and generation reset. Fixture positions/held spawns isolate behavior; GPU terrain, movement readability and campaign balance are separate checks."}
	var file: FileAccess = FileAccess.open("user://qa_troop_action_bridge.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify({"checks":checks,"failures":failures,"report":ProjectSettings.globalize_path("user://qa_troop_action_bridge.json")}))
	quit(0 if failures.is_empty() else 1)
