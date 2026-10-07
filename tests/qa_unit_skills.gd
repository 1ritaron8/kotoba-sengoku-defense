extends SceneTree
## CPU integration fixtures use real recruitment, HP, projectiles and kill rewards.
## Fixture gold/unlocks isolate ability contracts; this is not campaign balance QA.
const Battle = preload("res://native/game.gd")
const Skills = preload("res://native/unit_skills.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int = 0
var failures: Array[String] = []
var catalog: Array = []
var events: Array = []
var observations: Dictionary = {}
var map_bytes: String = ""

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if value: return
	failures.append(message)
	if failures.size() <= 30: push_error("SKILLS: " + message)

func near(first: float, second: float, tolerance: float = .0001) -> bool:
	return absf(first-second) <= tolerance

func fixture() -> Dictionary:
	return {"id":"skills-fixture","theme":"farm","stageNumber":20,"initialGold":4000,"unitLimit":14,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]},{"id":"other","objectiveId":"main","points":[{"x":.05,"y":.35},{"x":.95,"y":.35}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"wall","x":.5,"y":.68,"r":.16,"elevation":1}],"tactics":{"groundPosts":[{"id":"road","nameKo":"전선","pathIndex":0,"segmentIndex":0,"t":.55,"r":.19,"guardRadius":.2,"mobilityFactor":1.0},{"id":"north","nameKo":"북쪽 전선","pathIndex":1,"segmentIndex":0,"t":.55,"r":.15,"guardRadius":.2,"mobilityFactor":1.0}]}}

func make_game(levels: Dictionary = {}) -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,TYPES,levels)
	game.load_map(fixture(),20)
	game.set_seed(83)
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	game.start_battle()
	game.spawn_queue = ["raider"]
	game.spawn_source_waves = [1]
	game.spawn_clock = 100000.0
	return game

func simulate(game: Node2D, seconds: float, delta: float = .025) -> void:
	var remaining: float = seconds
	while remaining > .000001 and not game.finished:
		if game.between_waves: game.continue_wave()
		game.advance_simulation(minf(delta,remaining))
		remaining -= minf(delta,remaining)

func recruit(game: Node2D, type_name: String) -> Dictionary:
	var old_id: int = game.next_id
	if not game.begin_placement(type_name,0): check(false,type_name+" queues through the real recruitment API"); return {}
	if not game.pending.is_empty():
		var placed: bool = false
		for point in game.placement_hints:
			var preview: Dictionary = game.placement_preview(point)
			if bool(preview.get("valid",false)):
				placed=game.place_unit(point.x,point.y)
				if placed: break
		if not placed:
			for x in [.4,.46,.52,.58,.64,.7]:
				for y in [.5,.68,.35,.6,.75]:
					if placed: break
					var preview: Dictionary=game.placement_preview(Vector2(x,y))
					if bool(preview.get("valid",false)): placed=game.place_unit(x,y)
		check(placed,type_name+" has a legal native placement")
	var count: int = 0
	while not game.recruitment_queue.is_empty() and count<500:
		game.advance_simulation(.025)
		count += 1
	for unit in game.units:
		if int(unit.id)>=old_id and str(unit.type)==type_name:
			check(unit.has("skillMana") and unit.get("campaignLevel",0)>0,type_name+" initializes abilities only when production actually completes")
			return unit
	check(false,type_name+" creates a real living actor after production")
	return {}

func pose(unit: Dictionary, position: Vector2, path_index: int = 0) -> void:
	if unit.is_empty(): return
	unit.merge({"position":position,"postPathIndex":path_index,"routeDistance":position.x-.05,"homeDistance":position.x-.05,"homePosition":position,"spawnPosition":position,"combatState":"guard" if str(unit.type) in ["monk","naginata","gunner"] else "engaged","gatherRemaining":0.0,"aim":Vector2.LEFT,"cooldown":1000.0,"animation":"idle","animationClock":0.0,"attackPlan":{},"deploying":false},true)

func enemy(game: Node2D, position: Vector2, kind: String = "raider", source_wave: int = 10, path_index: int = 0, extra: Dictionary = {}) -> Dictionary:
	var options: Dictionary={"pathIndex":path_index}
	options.merge(extra,true)
	var actor: Dictionary=game._spawn_enemy(kind,source_wave,options)
	actor.merge({"position":position,"pointIndex":1},true)
	return actor

func attack(game: Node2D, unit: Dictionary, target: Dictionary, charge: bool = false, amount: float = -1) -> Dictionary:
	var value: float=float(game._stats(unit).damage) if amount<0 else amount
	var plan: Dictionary=game.unit_skills.prepare_attack(unit,target,value,0.0,charge)
	if not plan.is_empty(): game._release_unit_attack(unit,plan)
	return plan

func incoming_source(game: Node2D, target: Dictionary) -> Dictionary:
	var source: Dictionary=enemy(game,target.position,"enemy_gunner",1)
	check(game.can_enemy_engage_unit(source,target,true),"generated emplacement attacker can exercise the incoming-damage contract")
	game.enemies.erase(source)
	return source

func impacts(game: Node2D, seconds: float = .8) -> void:
	for index in range(ceili(seconds/.01)): game._update_projectiles(.01)

func status_time(game: Node2D, seconds: float) -> void:
	# Isolates a committed status from new attacks, movement and production.
	for index in range(ceili(seconds/.025)):
		game.elapsed += .025
		game.unit_skills.step(.025)

func all_gates() -> void:
	for level in [1,2,3,4,5,7,8]:
		for type_name in TYPES:
			var game: Node2D=make_game({type_name:level})
			var actor: Dictionary=recruit(game,type_name)
			if actor.is_empty(): game.free(); continue
			var owned: Array=game.unit_skills.skill_ids(actor)
			for id in Skills.UNLOCKS:
				var expected: bool=str(Skills.UNLOCKS[id].type)==type_name and level>=int(Skills.UNLOCKS[id].level)
				check(game.unit_skills.has_skill(actor,id)==expected and (id in owned)==expected,"permanent gate %s/%s/Lv%d uses permanent training" % [type_name,id,level])
			check(game._unit_public(actor).skillIds==owned,"native snapshot exposes permanent abilities")
			check(not game.unit_skills.has_skill(actor,"unknown_skill"),"unknown ability cannot unlock")
			if type_name=="monk": check(near(float(game._stats(actor).damage),0),"all monk levels have zero native attack damage")
			if type_name=="ninja": check(owned.is_empty(),"ninja keeps its approved ambush without invented level abilities")
			if type_name=="spear": check(game.units.size()==(2 if level>=5 else 1),"one native spear order produces the permanently unlocked quantity")
			game.free()
	for definition in catalog:
		for unlock in definition.get("skillUnlocks",[]):
			check(Skills.UNLOCKS.has(str(unlock.id)) and int(Skills.UNLOCKS[str(unlock.id)].level)==int(unlock.level),"catalog and helper agree: "+str(unlock.id))

func spear_and_gunner() -> void:
	for type_name in ["spear","gunner"]:
		for level in [1,3,8]:
			var game: Node2D=make_game({type_name:level})
			var actor: Dictionary=recruit(game,type_name)
			pose(actor,Vector2(.55,.5))
			var first: Dictionary=enemy(game,Vector2(.525,.5))
			var behind: Dictionary=enemy(game,Vector2(.485,.5))
			var lateral: Dictionary=enemy(game,Vector2(.485,.532))
			var forward: Dictionary=enemy(game,Vector2(.54,.5))
			var other: Dictionary=enemy(game,Vector2(.485,.5),"raider",10,1)
			var before: float=float(behind.hp)
			var plan: Dictionary=attack(game,actor,first)
			if type_name=="gunner":
				check(near(float(first.hp),float(first.maxHp)) and near(float(behind.hp),before),"a gunshot changes no HP before actual projectile impact")
				impacts(game)
			check(float(first.hp)<float(first.maxHp),"native primary "+type_name+" attack actually damages HP")
			check((float(behind.hp)<before)==(level>=3),"only unlocked "+type_name+" penetrates a real enemy behind the target")
			check(near(float(lateral.hp),float(lateral.maxHp)) and near(float(forward.hp),float(forward.maxHp)) and near(float(other.hp),float(other.maxHp)),"pierce excludes lateral, forward and other-path enemies")
			var after: Array=[float(first.hp),float(behind.hp)]
			var projectile_count: int=game.projectiles.size()
			game._release_unit_attack(actor,plan)
			impacts(game)
			check(near(float(first.hp),after[0]) and near(float(behind.hp),after[1]) and game.projectiles.size()==projectile_count,"repeating a consumed native attack cannot duplicate HP loss or projectiles")
			if level==8:
				var kind: String="poison" if type_name=="spear" else "armor_break"
				check(first.get("skillStatuses",{}).has(kind),"unlocked "+kind+" is attached only after actual damage")
				if type_name=="spear":
					var health: float=float(first.hp)
					status_time(game,4.0)
					check(float(first.hp)<health and not first.skillStatuses.has("poison"),"native poison ticks damage HP and expire after four seconds")
				else:
					var before_armor: float=float(first.armor)
					check(game.unit_skills.modify_enemy_armor(first,before_armor)<before_armor or before_armor==0,"armor break weakens actual armor temporarily")
					status_time(game,2.425)
					check(near(game.unit_skills.modify_enemy_armor(first,before_armor),before_armor),"armor restores after the configured armor-break time")
			game.free()
	# A shield's real HP deltas demonstrate the armor change beyond metadata.
	var game: Node2D=make_game({"gunner":8})
	var gunner: Dictionary=recruit(game,"gunner")
	pose(gunner,Vector2(.55,.5))
	var shield: Dictionary=enemy(game,Vector2(.52,.5),"shield",20)
	attack(game,gunner,shield,false,10)
	impacts(game)
	var first_loss: float=float(shield.maxHp)-float(shield.hp)
	var health: float=float(shield.hp)
	attack(game,gunner,shield,false,10)
	impacts(game)
	check(float(health)-float(shield.hp)>first_loss,"a second real bullet inflicts more HP damage on armor weakened by the first")
	status_time(game,2.425)
	health=float(shield.hp)
	attack(game,gunner,shield,false,10)
	impacts(game)
	check(near(health-float(shield.hp),first_loss),"a real bullet returns to normal armor damage after weakness expires")
	game.free()

func archery() -> void:
	for level in [1,3,5,8]:
		var game: Node2D=make_game({"archer":level})
		var bow: Dictionary=recruit(game,"archer")
		pose(bow,Vector2(.55,.65))
		var first: Dictionary=enemy(game,Vector2(.55,.5),"heavy",20)
		var nearby: Dictionary=enemy(game,Vector2(.56,.5),"heavy",20)
		var remote: Dictionary=enemy(game,Vector2(.65,.5),"heavy",20)
		var plan: Dictionary=attack(game,bow,first)
		check(game.projectiles.size()==(3 if level>=8 else 1),"archer Lv%d launches the actual unlocked arrow count" % level)
		check(near(float(first.hp),float(first.maxHp)) and near(float(nearby.hp),float(nearby.maxHp)),"arrows deal no HP damage at release")
		for shot in game.projectiles:
			check(bool(shot.get("flags",{}).get("fireArrow",false))==(level>=5),"each real flying arrow carries only unlocked fire metadata")
			check(int(shot.get("campaignLevel",0))==level,"real projectile preserves permanent level")
		impacts(game)
		check(float(first.hp)<float(first.maxHp),"native arrows damage the selected real target on impact")
		check((float(nearby.hp)<float(nearby.maxHp))==(level>=8),"only actual barrage impacts damage nearby real enemies")
		check(near(float(remote.hp),float(remote.maxHp)),"barrage cannot damage enemies outside its actual impact radius")
		check(first.get("skillStatuses",{}).has("burn")==bool(level>=5),"only permanent fire arrows apply burn after impact")
		if level>=5:
			var health: float=float(first.hp)
			var initial_tick: float=float(first.skillStatuses.burn.nextTickAt)
			var initial_dps: float=float(first.skillStatuses.burn.dps)
			attack(game,bow,first)
			impacts(game)
			check(near(float(first.skillStatuses.burn.dps),initial_dps) and near(float(first.skillStatuses.burn.nextTickAt),initial_tick),"repeated fire refreshes one burn instead of multiplying DPS or delaying ticks")
			health=float(first.hp)
			bow.hp=0.0
			status_time(game,3.025)
			check(float(first.hp)<health and not first.skillStatuses.has("burn"),"already committed burn survives caster death, ticks actual HP and expires")
			check(game.unit_skills.prepare_attack(bow,first,10,0).is_empty(),"a dead archer cannot create a new attack")
		var count: int=game.projectiles.size()
		game.unit_skills.after_release(bow,first,plan)
		check(game.projectiles.size()==count,"duplicate helper release cannot invent another barrage")
		game.free()
	# Barrage arrows retain their landing point after their first target is killed.
	var game: Node2D=make_game({"archer":8})
	var bow: Dictionary=recruit(game,"archer")
	pose(bow,Vector2(.55,.65))
	var first: Dictionary=enemy(game,Vector2(.55,.5))
	var nearby: Dictionary=enemy(game,Vector2(.56,.5),"heavy",20)
	attack(game,bow,first)
	game._damage_enemy(first,float(first.hp)+1,"ninja",{})
	impacts(game)
	check(float(nearby.hp)<float(nearby.maxHp) and game.projectiles.is_empty(),"already airborne barrage lands and damages its area after the primary target dies")
	game.free()
	# Synchronization is observed from native shot events, not inferred from math.
	game=make_game({"archer":3})
	var bows: Array=[recruit(game,"archer"),recruit(game,"archer")]
	pose(bows[0],Vector2(.48,.65)); pose(bows[1],Vector2(.62,.65))
	for actor in bows: actor.cooldown=0.0
	first=enemy(game,Vector2(.55,.5),"heavy",40)
	var event_start: int=events.size()
	simulate(game,.8)
	var shot_times: Dictionary={}
	for index in range(event_start,events.size()):
		var event: Dictionary=events[index]
		if str(event.get("type",""))=="shot" and str(event.get("unitType",""))=="archer": shot_times[int(event.get("actorId",-1))]=float(event.get("time",-1))
	check(shot_times.size()==2,"two real unlocked archers both release a native shot during the same volley")
	if shot_times.size()==2: check(near(float(shot_times.values()[0]),float(shot_times.values()[1]),.05),"native volley release times synchronize within one simulation step")
	game.free()

func samurai_support_and_flash() -> void:
	var armor_losses: Array=[]
	for level in [1,3]:
		var game: Node2D=make_game({"samurai":level})
		var fighter: Dictionary=recruit(game,"samurai")
		pose(fighter,Vector2(.55,.5))
		var attacker: Dictionary=enemy(game,Vector2(.52,.5))
		var health: float=float(fighter.hp)
		game._damage_friendly(fighter,20,attacker)
		armor_losses.append(health-float(fighter.hp))
		game.free()
	check(armor_losses[1]<armor_losses[0],"permanent samurai armor reduces actual native incoming HP loss")
	var game: Node2D=make_game({"samurai":5,"spear":1})
	var spear: Dictionary=recruit(game,"spear")
	var one: Dictionary=recruit(game,"samurai")
	var two: Dictionary=recruit(game,"samurai")
	pose(spear,Vector2(.55,.5)); pose(one,Vector2(.57,.5)); pose(two,Vector2(.9,.5))
	var foe: Dictionary=enemy(game,Vector2(.525,.5),"heavy",20)
	var health: float=float(foe.hp)
	attack(game,spear,foe)
	var one_loss: float=health-float(foe.hp)
	pose(two,Vector2(.58,.5))
	health=float(foe.hp)
	attack(game,spear,foe)
	check(near(health-float(foe.hp),one_loss),"two nearby samurai cannot multiply the same spear attack aura")
	pose(one,Vector2(.9,.5)); pose(two,Vector2(.92,.5))
	health=float(foe.hp)
	attack(game,spear,foe)
	check(health-float(foe.hp)<one_loss,"actual spear damage loses the aura after both samurai leave its range")
	game.free()
	game=make_game({"samurai":8})
	var fighter: Dictionary=recruit(game,"samurai")
	pose(fighter,Vector2(.55,.5))
	game.set_seed(4001)
	var instant_count: int=0
	for index in range(180):
		game.enemies.clear()
		foe=enemy(game,Vector2(.525,.5),"enemy_samurai",20)
		attack(game,fighter,foe,false,1)
		if float(foe.hp)<=0: instant_count+=1
		else: check(not "samurai_flash" in game.unit_skills.public_state(fighter).activeSkillIds,"failed instant-kill rolls do not advertise a flash animation")
	check(instant_count>0 and instant_count<25,"ordinary enemy samurai can actually die from the bounded low-probability flash")
	for kind in ["raider","heavy","commander","enemy_samurai"]:
		for index in range(100):
			game.enemies.clear()
			foe=enemy(game,Vector2(.525,.5),kind,20)
			if kind=="enemy_samurai": foe.historicalCommander={"id":"named-boss","nameKo":"역사 장수"}
			attack(game,fighter,foe,false,1)
			check(float(foe.hp)>0,"flash never instantly kills a wrong class or a named historical commander")
	observations["flashOrdinaryInstantKills"] = instant_count
	game.free()

func monk_healing() -> void:
	for level in [1,3,5,8]:
		var game: Node2D=make_game({"monk":level,"naginata":5})
		var first: Dictionary=recruit(game,"monk")
		var second: Dictionary=recruit(game,"monk")
		var ally: Dictionary=recruit(game,"naginata")
		pose(first,Vector2(.52,.5)); pose(second,Vector2(.46,.5)); pose(ally,Vector2(.58,.5))
		game._damage_friendly(ally,40,incoming_source(game,ally))
		var health: float=float(ally.hp)
		var clock: float=float(game.elapsed)
		game.unit_skills._next_heal_at=clock+1.0
		var foe: Dictionary=enemy(game,Vector2(.525,.5),"heavy",20)
		var enemy_health: float=float(foe.hp)
		check(game.unit_skills.prepare_attack(first,foe,100,0).is_empty(),"healers cannot prepare attacks at any permanent level")
		game._update_units(.05)
		check(game.projectiles.is_empty() and near(float(foe.hp),enemy_health),"nearby enemies never cause a monk attack or projectile")
		game.enemies.clear()
		status_time(game,1.0)
		var expected_heal: float=float({1:6.0,3:6.96,5:8.8704,8:12.168}[level])
		check(near(float(ally.hp)-health,expected_heal),"two monks share one level-scaled basic heal per target per pulse")
		check(bool(game.unit_skills.public_state(first).healing) or bool(game.unit_skills.public_state(second).healing),"actual healing produces a bounded native heal pose")
		check(ally.get("friendlySkillStatuses",{}).has("talisman")==bool(level>=3),"only permanently unlocked basic heals grant a talisman")
		if level>=3:
			health=float(ally.hp)
			pose(ally,Vector2(.9,.5))
			status_time(game,4.025)
			var expected_talisman: float=float({3:9.28,5:11.8272,8:16.224}[level])
			check(near(float(ally.hp)-health,expected_talisman),"the one talisman continues four level-scaled ticks after leaving support range")
			check(not ally.friendlySkillStatuses.has("talisman"),"talisman removes itself after its approved short duration")
		pose(ally,Vector2(.58,.5))
		ally.hp=float(ally.maxHp)-1.0
		game.unit_skills._next_heal_at=float(game.elapsed)+.025
		status_time(game,.025)
		check(near(float(ally.hp),float(ally.maxHp)),"healing clamps to the actual maximum health")
		ally.hp=0.0
		status_time(game,1.025)
		check(near(float(ally.hp),0),"neither basic healing nor an existing talisman can resurrect a dead actor")
		game.free()
	# Resource readiness is independent of ordinary attack power and cannot stack.
	var game: Node2D=make_game({"monk":5,"naginata":5,"commander":3})
	var first: Dictionary=recruit(game,"monk")
	var second: Dictionary=recruit(game,"monk")
	var guard: Dictionary=recruit(game,"naginata")
	var horse: Dictionary=recruit(game,"commander")
	pose(guard,Vector2(.58,.5)); pose(horse,Vector2(.6,.5)); pose(first,Vector2(.52,.5)); pose(second,Vector2(.95,.5))
	guard.skillMana=0.0
	var power: float=float(game._stats(guard).damage)
	status_time(game,1.0)
	var one_gain: float=float(guard.skillMana)
	guard.skillMana=0.0
	pose(second,Vector2(.46,.5))
	status_time(game,1.0)
	check(near(float(guard.skillMana),one_gain) and one_gain>14,"nearby mantra accelerates actual guard mana once, regardless of monk count")
	check(near(float(game._stats(guard).damage),power),"mantra does not invent an ordinary attack-damage aura")
	horse.chargeCooldown=5.0
	game.ground_combat.step(.5)
	check(near(float(horse.chargeCooldown),4.411296),"native mounted cooldown uses the level-scaled non-stacking preparation bonus")
	game.free()

func prayer() -> void:
	var game: Node2D=make_game({"monk":8,"naginata":5,"commander":3,"spear":1})
	var priest: Dictionary=recruit(game,"monk")
	var other: Dictionary=recruit(game,"monk")
	var guard: Dictionary=recruit(game,"naginata")
	var horse: Dictionary=recruit(game,"commander")
	var killer: Dictionary=recruit(game,"spear")
	pose(priest,Vector2(.5,.5)); pose(other,Vector2(.46,.5)); pose(guard,Vector2(.58,.5)); pose(horse,Vector2(.6,.5)); pose(killer,Vector2(.54,.5))
	game._damage_friendly(guard,80,incoming_source(game,guard))
	guard.skillMana=0.0
	horse.chargeCooldown=8.0
	game.unit_skills._next_heal_at=10000
	var health: float=float(guard.hp)
	var gold: int=game.gold
	var reward: int=0
	var killed: Array=[]
	for index in range(6):
		var target: Dictionary=enemy(game,Vector2(.515,.5))
		reward+=int(target.reward)
		killed.append(target)
		game._damage_enemy(target,float(target.hp)+1,"spear",killer)
		game.advance_simulation(.025)
	check(game.kills==6 and game.gold==gold+reward,"six actual native deaths commit one real kill reward each")
	check(near(float(guard.hp)-health,36.504),"overlapping victory prayers cannot stack the same recipient's level-eight heal")
	check(float(guard.skillMana)>=20 and float(horse.chargeCooldown)<6.0,"actual charged prayer restores guard mana and mounted readiness")
	check(int(priest.prayerCount)==0 and float(priest.prayerReadyAt)>float(game.elapsed),"prayer consumes six kills and begins its twelve-second cooldown")
	var count: int=int(other.prayerCount)
	for target in killed: game.unit_skills.on_enemy_killed(target,killer)
	check(int(other.prayerCount)==count and game.kills==6 and game.gold==gold+reward,"replaying a native kill notification cannot accumulate prayer or duplicate gold")
	health=float(guard.hp)
	for index in range(6):
		var target: Dictionary=enemy(game,Vector2(.515,.5))
		game._damage_enemy(target,float(target.hp)+1,"spear",killer)
		game.advance_simulation(.025)
	check(near(float(guard.hp),health),"further real kills cannot bypass the recipient or caster prayer cooldown")
	game.free()

func formation_and_guard() -> void:
	for level in [1,3]:
		var game: Node2D=make_game({"commander":level})
		var horse: Dictionary=recruit(game,"commander")
		pose(horse,Vector2(.55,.5))
		check(game.unit_skills.can_charge(horse)==bool(level>=3),"only permanent commander Lv3 enables native charge")
		game.free()
	var game: Node2D=make_game({"commander":8,"spear":1,"samurai":1})
	var horse: Dictionary=recruit(game,"commander")
	var spear: Dictionary=recruit(game,"spear")
	var samurai: Dictionary=recruit(game,"samurai")
	pose(horse,Vector2(.55,.5)); pose(spear,Vector2(.58,.509)); pose(samurai,Vector2(.58,.491))
	horse.formationLane=0; spear.formationLane=1; samurai.formationLane=-1
	var foe: Dictionary=enemy(game,Vector2(.525,.5),"heavy",20,0,{"formationPattern":"formation","formationGroup":"enemy-lines","formationLane":0,"formationRank":0})
	var mate: Dictionary=enemy(game,Vector2(.485,.5),"heavy",20,0,{"formationPattern":"formation","formationGroup":"enemy-lines","formationLane":1,"formationRank":1})
	var outside: Dictionary=enemy(game,Vector2(.3,.5),"heavy",20,0,{"formationPattern":"formation","formationGroup":"enemy-lines","formationLane":-1,"formationRank":2})
	var health: float=float(foe.hp)
	attack(game,horse,foe)
	var aligned: float=health-float(foe.hp)
	samurai.aim=Vector2.RIGHT
	health=float(foe.hp)
	attack(game,horse,foe)
	check(health-float(foe.hp)<aligned,"actual joint alignment increases damage and a reversed member removes the formation bonus")
	attack(game,horse,foe,true)
	check(str(foe.formationPattern)=="disrupted" and str(mate.formationPattern)=="disrupted" and str(outside.formationPattern)=="formation","only an actual unlocked charge disrupts the nearby enemy formation")
	status_time(game,3.025)
	check(str(foe.formationGroup)=="enemy-lines" and str(mate.formationPattern)=="formation" and int(mate.formationLane)==1,"disruption restores original enemy formation metadata after its short duration")
	game.free()
	# Earn guard mana through real clock updates, then let native Ground move/strike.
	game=make_game({"naginata":8})
	var guard: Dictionary=recruit(game,"naginata")
	pose(guard,Vector2(.55,.5))
	guard.guardRadius=.2
	guard.skillMana=0.0
	simulate(game,7.2)
	check(near(float(guard.skillMana),100),"native guard mana reaches its cap through simulation time")
	foe=enemy(game,Vector2(.44,.5),"heavy",20)
	mate=enemy(game,Vector2(.425,.5),"heavy",20)
	var home: Vector2=guard.homePosition
	var saw_dash: bool=false
	var saw_invulnerability: bool=false
	for index in range(120):
		game.advance_simulation(.025)
		saw_dash=saw_dash or str(guard.combatState)=="guard_dash"
		saw_invulnerability=saw_invulnerability or float(guard.get("invulnerableUntil",0))>float(game.elapsed)
		check(guard.position.distance_to(home)<=.2+.0001 and game.ground_combat.land_segment_safe(home,guard.position),"native guard dash remains in its original legal land-defense area")
		if saw_invulnerability: break
	check(saw_dash and saw_invulnerability and float(foe.hp)<float(foe.maxHp),"actual mana dash moves, hits real HP and grants the unlocked post-impact guard")
	if saw_invulnerability:
		var before: float=float(guard.hp)
		game._damage_friendly(guard,20,incoming_source(game,guard))
		check(near(float(guard.hp),before),"actual native incoming damage is blocked during the brief charge guard")
		game.enemies.clear()
		simulate(game,1.2)
		before=float(guard.hp)
		game._damage_friendly(guard,20,incoming_source(game,guard))
		check(float(guard.hp)<before,"native damage resumes after the brief invulnerability expires")
		var mana: float=float(guard.skillMana)
		var deadline: float=float(guard.invulnerableUntil)
		game.unit_skills.finish_guard_dash(guard,true)
		check(near(float(guard.skillMana),mana) and near(float(guard.invulnerableUntil),deadline),"a duplicate dash completion cannot extend immunity or consume mana again")
	game.enemies.clear()
	simulate(game,4.0)
	check(guard.position.distance_to(home)<.001,"native guard returns to its original post after danger ends")
	game.free()

func timing_reset_and_limits() -> void:
	var outcomes: Array=[]
	for multiplier in [1.0,2.0,3.0]:
		var game: Node2D=make_game({"archer":5,"naginata":5,"monk":3})
		var bow: Dictionary=recruit(game,"archer")
		var guard: Dictionary=recruit(game,"naginata")
		var priest: Dictionary=recruit(game,"monk")
		pose(bow,Vector2(.55,.68)); pose(guard,Vector2(.85,.5)); pose(priest,Vector2(.52,.5))
		var target: Dictionary=enemy(game,Vector2(.12,.5),"heavy",20)
		game._damage_enemy(target,10,"archer",bow)
		guard.skillMana=0.0
		var clock: float=float(game.elapsed)
		var health: float=float(target.hp)
		game.paused=true
		for index in range(5): game._process(.2); game.unit_skills.step(.2)
		check(near(float(game.elapsed),clock) and near(float(target.hp),health) and near(float(guard.skillMana),0),"pause freezes actual HP statuses, mana and combat time")
		game.paused=false
		game.between_waves=true
		for index in range(5): game._process(.2); game.unit_skills.step(.2)
		check(near(float(game.elapsed),clock) and near(float(target.hp),health),"learning transitions freeze committed statuses without deleting them")
		game.between_waves=false
		game.speed=multiplier
		var real_seconds: float=3.0/multiplier
		var remaining: float=real_seconds
		while remaining>.000001:
			var frame: float=minf(.025,remaining)
			game._process(frame)
			remaining-=frame
		outcomes.append({"elapsed":float(game.elapsed)-clock,"health":float(target.hp),"mana":float(guard.skillMana)})
		check(near(float(game.elapsed)-clock,3.0),"native speed %.0f advances exactly three pure combat seconds" % multiplier)
		var mana: float=float(guard.skillMana)
		game.unit_skills.step(.05); game.unit_skills.step(0); game.unit_skills.step(-1)
		check(near(float(guard.skillMana),mana),"duplicate, zero and negative helper steps cannot add resource")
		var old: Dictionary=game.unit_skills.prepare_attack(bow,target,10,0)
		var stale_source: Dictionary=game._attack_source(bow,old)
		var generation: int=game.unit_skills.generation
		game.load_map(fixture(),5)
		check(game.unit_skills.generation>generation and game.units.is_empty() and game.enemies.is_empty() and game.projectiles.is_empty(),"new-map reset clears all actors, skills and committed missiles")
		var fresh: Dictionary=enemy(game,Vector2(.5,.5))
		health=float(fresh.hp)
		game._damage_enemy(fresh,100,"archer",stale_source)
		check(near(float(fresh.hp),health) and fresh.get("skillStatuses",{}).is_empty(),"an old generation's attack cannot affect the new battle")
		game.free()
	for index in range(1,outcomes.size()):
		check(near(outcomes[index].health,outcomes[0].health,.001) and near(outcomes[index].mana,outcomes[0].mana,.001),"native 1/2/3 speed preserves committed damage and resource outcomes")
	observations["speedOutcomes"]=outcomes
	# Behind-target effects have a conservative bounded number of native victims.
	var game: Node2D=make_game({"spear":3})
	var actor: Dictionary=recruit(game,"spear")
	pose(actor,Vector2(.55,.5))
	var primary: Dictionary=enemy(game,Vector2(.525,.5),"heavy",20)
	var targets: Array=[]
	for index in range(12): targets.append(enemy(game,Vector2(.515-float(index)*.005,.5),"heavy",20))
	attack(game,actor,primary)
	var hit_count: int=0
	for target in targets:
		if float(target.hp)<float(target.maxHp): hit_count+=1
	check(hit_count==4,"a native pierce has at most four additional actual HP victims")
	game.free()

func cooldown_sweep_and_retarget() -> void:
	var cadences: Array=[]
	for level in [4,5]:
		var game: Node2D=make_game({"gunner":level})
		var shooter: Dictionary=recruit(game,"gunner")
		pose(shooter,Vector2(.55,.5))
		shooter.cooldown=0.0
		var target: Dictionary=enemy(game,Vector2(.43,.5),"heavy",100)
		var start_event: int=events.size()
		for tick in range(200):
			game.elapsed+=.025
			game.unit_skills.step(.025)
			game._advance_actor_animations(.025)
			game._update_units(.025)
			game._update_projectiles(.025)
		var times: Array=[]
		for index in range(start_event,events.size()):
			if str(events[index].type)=="shot" and int(events[index].get("actorId",-1))==int(shooter.id): times.append(float(events[index].time))
		check(times.size()>=3 and float(target.hp)<float(target.maxHp),"real Lv%d gunner attacks repeatedly and changes native HP" % level)
		if times.size()>=3: cadences.append(float(times[2])-float(times[1]))
		game.free()
	if cadences.size()==2: check(cadences[1]<cadences[0] and cadences[1]>cadences[0]*.85,"Lv5 reload slightly improves actual native release cadence")
	observations["gunnerLv4And5ReleaseCadence"]=cadences
	for level in [1,3]:
		var game: Node2D=make_game({"naginata":level})
		var guard: Dictionary=recruit(game,"naginata")
		pose(guard,Vector2(.55,.5))
		var first: Dictionary=enemy(game,Vector2(.525,.5),"heavy",20)
		var inner: Dictionary=enemy(game,Vector2(.485,.5),"heavy",20)
		var extended: Dictionary=enemy(game,Vector2(.463,.5),"heavy",20)
		var wrong_path: Dictionary=enemy(game,Vector2(.485,.5),"heavy",20,1)
		attack(game,guard,first)
		check(float(inner.hp)<float(inner.maxHp),"basic naginata preserves its actual close sweep")
		check((float(extended.hp)<float(extended.maxHp))==bool(level>=3),"only permanent Lv3 extends actual sweep victims")
		check(near(float(wrong_path.hp),float(wrong_path.maxHp)),"naginata sweep does not jump to a different authored route")
		game.free()
	# A plan retargets once; selecting a different soldier cannot replay it.
	var game: Node2D=make_game({"spear":3})
	var actor: Dictionary=recruit(game,"spear")
	pose(actor,Vector2(.55,.5))
	var first: Dictionary=enemy(game,Vector2(.525,.5),"heavy",20)
	var replacement: Dictionary=enemy(game,Vector2(.522,.5),"heavy",20)
	var plan: Dictionary=game.unit_skills.prepare_attack(actor,first,10,0)
	game._damage_enemy(first,float(first.hp)*2+1,"ninja",{})
	check(float(first.hp)<=0,"retarget fixture really kills the original armored target through native damage")
	game.select_unit(-1)
	game._release_unit_attack(actor,plan)
	check(float(replacement.hp)<float(replacement.maxHp),"a living melee actor uses its real nearby replacement when the planned target dies")
	var health: float=float(replacement.hp)
	status_time(game,12.0)
	game.select_unit(int(actor.id))
	game._release_unit_attack(actor,plan)
	check(near(float(replacement.hp),health),"reselection and a delayed repeated release cannot replay the consumed damage")
	game.paused=true
	check(game.unit_skills.prepare_attack(actor,replacement,10,0).is_empty(),"pause rejects preparation of a new skill attack")
	game.paused=false
	game.between_waves=true
	check(game.unit_skills.prepare_attack(actor,replacement,10,0).is_empty(),"learning screen rejects preparation of a new skill attack")
	game.free()

func run() -> void:
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	map_bytes=FileAccess.get_file_as_string("res://native/maps.json")
	all_gates()
	spear_and_gunner()
	archery()
	samurai_support_and_flash()
	monk_healing()
	prayer()
	formation_and_guard()
	timing_reset_and_limits()
	cooldown_sweep_and_retarget()
	check(FileAccess.get_file_as_string("res://native/maps.json")==map_bytes,"ability integration preserves all 40 authored historical maps")
	var result: Dictionary={"checks":checks,"failures":failures,"observations":observations,"scope":"CPU actual native ability contracts; isolated gold/unlocks; no campaign balance or GPU claim"}
	var file: FileAccess=FileAccess.open("res://tests/qa_unit_skills.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("UNIT_SKILLS_QA "+JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
