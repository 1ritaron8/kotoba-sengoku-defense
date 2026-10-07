extends SceneTree
## Native HP, movement and skill boundaries, independent from render fixtures.
const Battle=preload("res://native/game.gd")
const Types: Array=["archer","spear","samurai","gunner","naginata","monk","ninja","commander"]
var catalog: Array=[]
var checks: int=0
var failures: Array=[]
var observations: Dictionary={}

func _initialize() -> void: call_deferred("run")
func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<=25: push_error("GUARD "+note)

func fixture() -> Dictionary:
	return {"id":"guard-combat-fixture","stageNumber":15,"theme":"forest","initialGold":4000,"unitLimit":24,"totalWaves":100,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":1000}],"buildZones":[{"id":"wall","x":.5,"y":.65,"r":.08}],"tactics":{"groundPosts":[{"id":"defense","pathIndex":0,"segmentIndex":0,"t":.5,"r":.22,"guardRadius":.22,"mobilityFactor":1.0}]}}

func game_for(levels: Dictionary = {}, data: Dictionary = {}) -> Node2D:
	var game: Node2D=Battle.new()
	root.add_child(game);game.set_process(false)
	game.configure_roster(catalog,Types,levels)
	game.load_map(fixture() if data.is_empty() else data)
	game.set_seed(857)
	return game

func hold(game: Node2D) -> void:
	game.start_battle();game.enemies.clear()
	game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=100000.0

func tick(game: Node2D, seconds: float) -> void:
	for index in range(ceili(seconds/.025)): game.advance_simulation(.025)

func produce(game: Node2D, type_name: String, point: Vector2 = Vector2(-1,-1)) -> Dictionary:
	check(game.begin_placement(type_name,0),type_name+" enters its actual production path")
	if str(game.placement_contract(type_name).deploymentKind)!="marching":
		if point.x<0:
			for zone in game.zones:
				var hint: Vector2=game._zone_placement_hint(zone,type_name)
				if hint.x>=0 and game.placement_preview(hint).valid: point=hint;break
		check(point.x>=0 and game.place_unit(point.x,point.y),type_name+" queues a valid reserved position")
	if not game.running: hold(game)
	for index in range(300):
		game.advance_simulation(.025)
		for unit in game.units:
			if str(unit.type)==type_name: return unit
	return {}

func enemy_at(game: Node2D, position: Vector2, kind: String = "heavy", stationary: bool = false) -> Dictionary:
	var enemy: Dictionary=game._spawn_enemy(kind,20,{"pathIndex":0})
	enemy.position=position;enemy.pointIndex=1
	if stationary: enemy.speed=0.0
	return enemy

func fixed_casualties() -> void:
	var rows: Array=[]
	for type_name in ["archer","gunner","monk","naginata"]:
		for ranged in [false,true]:
			var game: Node2D=game_for()
			var unit: Dictionary=produce(game,str(type_name))
			if unit.is_empty(): check(false,"Fixed role actually produced");game.free();continue
			var home: Vector2=unit.position
			var events: Array=[]
			game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
			var position: Vector2=home+Vector2(-.10,0) if ranged else Vector2(home.x-.07,.5)
			var enemy: Dictionary=enemy_at(game,position,"enemy_gunner" if ranged else "enemy_samurai")
			check(str(enemy.kind)==("enemy_gunner" if ranged else "enemy_samurai") and str(enemy.combatRole)==game.ENEMY_EMPLACEMENT_ROLE,"Late fixed-casualty fixture spawns an actual native emplacement hunter")
			enemy.hp=5000;enemy.maxHp=5000
			var previous: Vector2=enemy.position
			for index in range(2400):
				game.advance_simulation(.025)
				check(game.ground_combat.land_segment_safe(previous,enemy.position),"Actual enemy threat stays on legal land")
				check(enemy.position.distance_to(previous)<=.009,"Threat approach moves continuously instead of teleporting")
				previous=enemy.position
				if str(type_name) in ["archer","gunner","monk"]: check(unit.position==home,"Fixed friendly keeps its committed firing/support point")
				if float(unit.hp)<=0: break
			var hits: Array=[]
			for event in events:
				if str(event.type)=="hit" and str(event.get("victimSide",""))=="friendly" and int(event.get("victimId",-1))==int(unit.id):
					hits.append(event)
					check(absf(float(event.hpBefore)-float(event.hpAfter)-float(event.damage))<.00001,"Enemy common damage event equals actual friendly HP loss")
			check(not hits.is_empty() and float(unit.hp)<=0 and game.ground_combat._unit(int(unit.id)).is_empty(),str(type_name)+" is actually attacked and destroyed by "+("ranged" if ranged else "melee")+" enemies")
			check(game.death_actors.any(func(actor: Dictionary): return int(actor.id)==int(unit.id) and str(actor.animation)=="death"),"Destroyed fixed troop enters native death animation")
			var wallet: int=game.gold
			tick(game,1)
			check(game.units.is_empty() and game.gold==wallet,"A fixed casualty is never freely revived")
			check(game.begin_placement(str(type_name)),"After death the same fixed role can be recruited again")
			game.cancel_recruit()
			rows.append({"type":type_name,"rangedEnemy":ranged,"hits":hits.size(),"elapsed":game.elapsed,"dead":float(unit.hp)<=0})
			game.free()
	observations["fixedCasualties"]=rows

func guard_sortie_and_home() -> void:
	var rows: Array=[]
	for level in [2,3,4,5,7,8]:
		var game: Node2D=game_for({"naginata":level})
		var guard: Dictionary=produce(game,"naginata",Vector2(.5,.5))
		if guard.is_empty(): check(false,"Guard is produced");game.free();continue
		var home: Vector2=guard.position
		var events: Array=[]
		game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
		if level>=5: tick(game,8)
		var first: Dictionary=enemy_at(game,home+Vector2(-.12,0),"raider",true)
		var second: Dictionary=enemy_at(game,home+Vector2(-.145,.013),"raider",true)
		first.hp=500;first.maxHp=500;second.hp=500;second.maxHp=500
		var first_health: float=float(first.hp)
		var second_health: float=float(second.hp)
		var previous: Vector2=guard.position
		var dash: bool=false
		var hit: bool=false
		for index in range(800):
			game.advance_simulation(.025)
			check(guard.position.distance_to(home)<=float(guard.guardRadius)+.00001,"Guard never leaves the home defense circle")
			check(guard.position.distance_to(previous)<=.006,"Guard charge approaches through actual bounded movement")
			check(game.ground_combat.land_segment_safe(previous,guard.position),"Guard dash does not cross terrain barriers")
			previous=guard.position
			dash=dash or str(guard.get("combatState",""))=="guard_dash" or bool(guard.get("guardDashActive",false))
			if float(first.hp)<first_health and float(second.hp)<second_health: hit=true;break
		check(hit and guard.position!=home,"Native guard reaches the threat and its sweep damages multiple actual enemies")
		check(dash==(level>=5),"Naginata mana dash activates only from permanent level5")
		var shield: bool=float(guard.get("invulnerableUntil",0))>game.elapsed
		check(shield==(level>=8),"Post-dash invulnerability activates only from permanent level8")
		if shield:
			var before: float=float(guard.hp)
			game._damage_friendly(guard,50,first)
			check(float(guard.hp)==before,"Native friendly damage is blocked during the actual post-dash invulnerability")
		var frozen: String=JSON.stringify(game.snapshot().units)
		game.paused=true;game.advance_simulation(2)
		check(JSON.stringify(game.snapshot().units)==frozen,"Guard mana/position/attack/status clocks freeze under explicit pause")
		game.paused=false;game.between_waves=true;game.advance_simulation(2)
		check(JSON.stringify(game.snapshot().units)==frozen,"Guard mana and active skill clocks freeze during study")
		game.between_waves=false
		first.hp=0;second.hp=0;tick(game,.05)
		for index in range(400):
			game.advance_simulation(.025)
			if guard.position.distance_to(home)<.00001 and str(guard.combatState)=="guard": break
		check(guard.position.distance_to(home)<.00001 and str(guard.combatState)=="guard","No-danger guard physically returns to the original paid home")
		var actor: Dictionary={}
		for state in game.actor_states():
			if int(state.id)==int(guard.id): actor=state
		check(not actor.is_empty() and str(actor.supportState)=="guard" and bool(actor.flags.guard),"Actual guard actor exposes renderer support stance and unlocked skill flags")
		rows.append({"level":level,"dash":dash,"invulnerable":shield,"enemyLoss":[first_health-float(first.hp),second_health-float(second.hp)],"homeReturn":guard.position.distance_to(home)})
		game.free()
	observations["guards"]=rows

func terrain_barriers() -> void:
	for barrier in ["water","wall"]:
		var data: Dictionary=fixture()
		if barrier=="water": data.water={"x":.30,"y":.42,"w":.018,"h":.22}
		else: data.obstacles=[{"x":.31,"y":.5,"r":.018,"blockPlacement":true}]
		var game: Node2D=game_for({"naginata":8},data)
		var guard: Dictionary=produce(game,"naginata",Vector2(.40,.5))
		if guard.is_empty(): game.free();check(false,"Barrier guard produced");continue
		var home: Vector2=guard.position
		tick(game,8)
		var enemy: Dictionary=enemy_at(game,Vector2(.25,.5),"heavy",true)
		enemy.hp=1000;enemy.maxHp=1000
		tick(game,4)
		check(guard.position==home and float(enemy.hp)==1000 and not bool(guard.get("guardDashActive",false)),"Guard refuses an unreachable "+barrier+"-separated threat without spending mana or dealing damage")
		game.free()

func monk_healing_and_no_attack() -> void:
	var game: Node2D=game_for()
	var monk: Dictionary=produce(game,"monk",Vector2(.50,.5))
	var gunner: Dictionary=produce(game,"gunner",Vector2(.58,.5))
	if monk.is_empty() or gunner.is_empty(): check(false,"Monk/gunner really produced");game.free();return
	gunner.hp=float(gunner.maxHp)-25
	var before: float=float(gunner.hp)
	var events: Array=[]
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	var enemy: Dictionary=enemy_at(game,Vector2(.49,.5),"raider",true)
	enemy.hp=5000;enemy.maxHp=5000;enemy.attackCooldown=1000
	gunner.cooldown=1000
	var health: float=float(enemy.hp)
	tick(game,1.2)
	check(float(gunner.hp)>before and float(enemy.hp)==health,"Level-one monk heals actual missing friendly HP and never damages the nearby enemy")
	check(float(game._stats(monk).damage)==0 and game.ground_combat.attack_target(monk).is_empty() and monk.attackPlan.is_empty(),"Monk has zero attack stats and cannot create a staff attack plan")
	var healing_events: Array=events.filter(func(event: Dictionary): return str(event.type)=="heal" and int(event.actorId)==int(monk.id))
	check(not healing_events.is_empty() and float(healing_events[0].healAmount)>0,"Real monk restoration emits actual healAmount")
	check(not events.any(func(event: Dictionary): return str(event.type)=="shot" and int(event.actorId)==int(monk.id)),"Renderer/audio never receives a monk offensive shot")
	check(game.actor_states().any(func(actor: Dictionary): return int(actor.id)==int(monk.id) and bool(actor.healing) and str(actor.supportState)=="heal"),"Actual healing time exposes a monk support gesture instead of attack")
	game.free()

func cavalry_basic_and_charge() -> void:
	var rows: Array=[]
	for level in [1,2,3,5,8]:
		var game: Node2D=game_for({"commander":level})
		var unit: Dictionary=produce(game,"commander")
		if unit.is_empty(): check(false,"Mounted unit produced");game.free();continue
		tick(game,2.6)
		var events: Array=[]
		game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
		var enemy: Dictionary=enemy_at(game,unit.position+Vector2(-.10,0),"heavy",true)
		enemy.hp=3000;enemy.maxHp=3000
		for index in range(800):
			game.advance_simulation(.025)
			if float(enemy.hp)<3000: break
		check(float(enemy.hp)<3000,"Mounted unit level "+str(level)+" lands an actual native melee hit")
		var charged: bool=events.any(func(event: Dictionary): return str(event.type)=="charge_impact" and int(event.actorId)==int(unit.id))
		check(charged==(level>=3),"Mounted charge unlocks at permanent level3 while lower levels use ordinary melee")
		check(not bool(game._unit_public(unit).flags.formation),"An isolated cavalry actor does not gain a pretend formation bonus")
		rows.append({"level":level,"charge":charged,"hpLoss":3000-float(enemy.hp)})
		game.free()
	observations["cavalry"]=rows

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/guard-combat/").to_lower()): push_error("Guard QA refuses the player's profile");quit(2);return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	fixed_casualties()
	guard_sortie_and_home()
	terrain_barriers()
	monk_healing_and_no_attack()
	cavalry_basic_and_charge()
	var report: Dictionary={"checks":checks,"failures":failures,"observations":observations,"scope":"CPU-only actual production, native enemy melee/ranged damage and fixed casualties, bounded land guard movement/sweep/mana dash/home return/level8 invulnerability, pause/study, zero-attack level1 healing, ordinary mounted melee and level3 charge. Separate helper QA covers the complete skill matrix."}
	var path: String="user://qa_guard_combat_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_guard_combat.json"
	var output: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("GUARD_COMBAT ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path(path))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
