extends SceneTree
## Real attack/release/projectile/HP observations, without campaign win injection.
const Battle=preload("res://native/game.gd")
var checks: int=0
var failures: Array=[]
var catalog: Array=[]
var observations: Dictionary={}

func _initialize() -> void: call_deferred("run")
func check(value: bool, note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		push_error("BASIC_ROLES "+note)

func fixture() -> Dictionary:
	return {"id":"spear-gunner-observation","stageNumber":1,"theme":"forest","initialGold":1200,"unitLimit":8,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"bow","x":.5,"y":.7,"r":.08}],"tactics":{"groundPosts":[{"id":"firing","pathIndex":0,"segmentIndex":0,"t":.55,"r":.08,"guardRadius":.18,"mobilityFactor":1.0,"capacityBonus":0}]}}

func median(values: Array) -> float:
	var sorted: Array=values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size()/2]) if not sorted.is_empty() else INF

func observe(type_name: String, enemy_kind: String) -> Dictionary:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,["spear","gunner"],{})
	game.load_map(fixture(),0)
	check(game.begin_placement(type_name,0),type_name+" uses its actual recruitment route")
	if type_name=="gunner":
		var post: Dictionary={}
		for zone in game.zones:
			if str(zone.placementRole)=="ground": post=zone;break
		check(game.place_unit(post.position.x,post.position.y),"Gunner commits a legal fixed frontline point")
	game.start_battle()
	game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=100000.0
	for tick in range(300):
		if game.recruitment_queue.is_empty(): break
		game.advance_simulation(.025)
	check(game.units.size()==1 and game.recruitment_queue.is_empty(),"Real paid production creates the observed role before combat starts")
	var unit: Dictionary=game.units[0]
	var home: Vector2=unit.position
	game.start_battle()
	game.spawn_queue=["raider"];game.spawn_source_waves=[1];game.spawn_metadata=[{}];game.spawn_clock=100000.0
	var enemy: Dictionary=game._spawn_enemy(enemy_kind,1,{"pathIndex":0})
	var distance: float=float(unit.routeDistance)-.028 if type_name=="spear" else float(unit.homeDistance)-.10
	enemy.position=game.ground_combat.route_point(0,distance)
	enemy.pointIndex=1
	# Equal-HP stationary targets isolate effective hit intervals and armor.
	# Their shipped armor/counterattack/damage remain unchanged.
	enemy.speed=0.0;enemy.hp=200.0;enemy.maxHp=200.0
	var wallet: int=game.gold
	var events: Array=[]
	game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	var attack_started: float=-1.0
	var attack_lengths: Array=[]
	var animations: Array=[]
	for tick in range(2400):
		var previous: String=str(unit.animation)
		game.advance_simulation(.025)
		if type_name=="gunner": check(unit.position==home,"Matchlock firing preserves the selected fixed position")
		if str(unit.animation)=="attack" and previous!="attack":
			attack_started=game.elapsed
			animations.append({"start":game.elapsed,"releaseTime":unit.attackPlan.get("releaseTime",0),"duration":unit.attackDuration})
		if str(unit.animation)!="attack" and previous=="attack" and attack_started>=0:
			attack_lengths.append(game.elapsed-attack_started)
			attack_started=-1.0
		if float(enemy.hp)<=0 or game.units.is_empty(): break
	var hits: Array=[]
	var shots: Array=[]
	var kills: int=0
	for event in events:
		if int(event.get("actorId",-1))!=int(unit.id) or event.get("side","")!="friendly": continue
		if event.type=="shot": shots.append(event.time)
		if event.type=="hit" and int(event.get("victimId",-1))==int(enemy.id): hits.append({"time":event.time,"damage":event.damage,"before":event.hpBefore,"after":event.hpAfter})
		if event.type=="killed" and int(event.get("victimId",-1))==int(enemy.id): kills+=1
	check(float(enemy.hp)<=0 and not game.units.is_empty(),type_name+" completes the equal-HP "+enemy_kind+" fight using native attacks")
	check(hits.size()>=3 and shots.size()==hits.size(),type_name+" releases exactly one observable shot/hit for each completed attack")
	check(kills==1 and game.gold==wallet+int(enemy.reward),type_name+" real kill and original reward occur once")
	var intervals: Array=[]
	var observed_damage: float=0
	for index in range(hits.size()):
		check(absf(float(hits[index].before)-float(hits[index].after)-float(hits[index].damage))<.0001,"Hit event damage equals the observed HP loss")
		observed_damage+=float(hits[index].damage)
		if index>0: intervals.append(float(hits[index].time)-float(hits[index-1].time))
	check(absf(observed_damage-200.0)<.0001,"All observed hits conserve the equal target HP including the final capped hit")
	var hit_interval: float=median(intervals)
	check(absf(hit_interval-(.60 if type_name=="spear" else 1.55))<.051,type_name+" observed hit cadence matches its real fast-stab or slow-reload role")
	for length in attack_lengths: check(float(length)<=hit_interval+.026,"Observed weapon motion finishes before the next real attack; no overlapping attack cycles")
	check(not animations.is_empty() and float(animations[0].releaseTime)>0 and float(animations[0].releaseTime)<float(animations[0].duration),"Impact remains inside the original weapon animation rhythm")
	var result: Dictionary={"type":type_name,"enemyKind":enemy_kind,"nativeArmor":enemy.armor,"targetHP":200,"firstHitDamage":hits[0].damage if not hits.is_empty() else 0,"hitInterval":hit_interval,"hitCount":hits.size(),"killSeconds":game.elapsed,"finalHitDamage":hits[-1].damage if not hits.is_empty() else 0,"overkillAvoided":float(hits[0].damage)-float(hits[-1].damage) if not hits.is_empty() else 0,"remainingHP":unit.hp,"animationLengths":attack_lengths,"animations":animations,"hits":hits}
	game.free()
	return result

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/spear-gunner/").to_lower()): push_error("Basic roles QA refuses the player's profile");quit(2);return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	for type_name in ["spear","gunner"]:
		for enemy_kind in ["raider","shield"]: observations[str(type_name)+"_"+str(enemy_kind)]=observe(str(type_name),str(enemy_kind))
	var spear: Dictionary=observations.spear_raider
	var spear_armor: Dictionary=observations.spear_shield
	var gunner: Dictionary=observations.gunner_raider
	var gunner_armor: Dictionary=observations.gunner_shield
	check(float(spear.hitInterval)<float(gunner.hitInterval)*.5,"The spear actually hits more than twice as often as the matchlock")
	check(float(gunner.firstHitDamage)>float(spear.firstHitDamage)*3.0,"The matchlock delivers a slower heavier real hit")
	check(float(gunner_armor.firstHitDamage)/float(gunner.firstHitDamage)>float(spear_armor.firstHitDamage)/float(spear.firstHitDamage)+.20,"Observed shield armor suppresses spear damage more strongly than matchlock damage")
	check(absf(float(spear.firstHitDamage)/float(spear.hitInterval)-24.0/.9)<1.1,"The faster spear preserves the previously shipped light-target baseline DPS")
	check(float(spear_armor.killSeconds)>float(spear.killSeconds) and float(gunner_armor.hitCount)<=float(spear_armor.hitCount),"Native armored equal-HP targets visibly favor the heavy shot over rapid light stabs")
	var path: String="user://qa_spear_gunner_roles_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_spear_gunner_roles.json"
	var output: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"CPU-only actual attack animation/release/projectile/hit/kill/reward and native armor comparison. Equal 200 HP stationary targets and fixture gold isolate the two approved baseline roles; no campaign or new-counter claim."},"  "))
	output.close()
	print("SPEAR_GUNNER_ROLES ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path(path))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
