extends SceneTree
const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
var checks: int = 0
var failures: Array = []
var events: Array = []

func _initialize() -> void: call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description);push_error(description)

func actions(action: String) -> Array:
	return events.filter(func(event):return str(event.get("action",event.type))==action)

func create_game(map: Dictionary) -> Node2D:
	var game = Battle.new()
	root.add_child(game)
	game.set_process(false)
	var store = Store.new()
	game.configure_roster(store.unit_catalog,store.unit_catalog.map(func(unit):return unit.id),{})
	game.load_map(map)
	game.gold = 10000
	game.game_event.connect(func(event):events.append(event.duplicate(true)))
	return game

func deploy(game: Node2D, type_name: String) -> Dictionary:
	check(game.recruit(type_name),"Successful funded "+type_name+" recruitment")
	for point in game.placement_hints:
		if point.x>=0:
			check(game.place_unit(point.x,point.y),"Actual advertised "+type_name+" deployment")
			return game.units[-1]
	return {}

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"): quit(2);return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var game: Node2D = create_game(maps[0])
	var archer: Dictionary = deploy(game,"archer")
	check(game._selected_name_visible(archer),"An idle recruited unit keeps its selected Japanese name")
	check(actions("recruit").size()==1 and actions("deploy").size()==1,"Recruit and deploy each emit once without legacy duplicate signals")
	check(actions("recruit")[0].type=="recruited" and actions("deploy")[0].type=="placed","Existing notification types remain compatible")
	game.start_battle()
	game.spawn_queue.clear()
	game._spawn_enemy("shield")
	var enemy: Dictionary=game.enemies[-1]
	enemy.position=archer.position+Vector2(.025,0)
	var before_shots: int=actions("shot").size()
	game._update_units(.01)
	check(str(archer.animation)=="attack" and not game._selected_name_visible(archer),"Actual ranged windup hides only the selected overhead name policy")
	check(actions("shot").size()==before_shots,"Attack windup is silent until the actual release")
	game._advance_actor_animations(game._impact_time("archer")-.01)
	check(actions("shot").size()==before_shots,"No shot event before the actual impact clock")
	game._advance_actor_animations(.02)
	check(actions("shot").size()==before_shots+1,"Projectile release produces exactly one shot")
	check(actions("shot")[-1].weapon=="bow" and actions("shot")[-1].victimId==enemy.id,"Shot identifies actual bow, source and target")
	var before_hp: float=float(enemy.hp)
	game._update_projectiles(.2)
	var hit: Dictionary=actions("hit")[-1]
	check(is_equal_approx(float(hit.damage),before_hp-float(enemy.hp)),"Hit reports actual armor-reduced HP loss")
	check(float(hit.damage)<float(game._stats(archer).damage),"Shield armor is reflected in feedback damage")
	check(hit.side=="friendly" and hit.victimSide=="enemy" and hit.victimPosition.x==enemy.position.x,"Damage feedback uses source side and actual victim position")
	var remaining_health: float=float(enemy.hp)
	var actual: float=game._damage_enemy(enemy,100000,"archer",archer)
	check(is_equal_approx(actual,remaining_health) and is_equal_approx(float(actions("hit")[-1].damage),remaining_health),"Overkill reports lost HP rather than inflated planned damage")
	var hits_before: int=actions("hit").size()
	game._damage_enemy(enemy,100000,"archer",archer)
	check(actions("hit").size()==hits_before,"Already dead victim emits no duplicate hit")
	var gold_before: int=game.gold
	game.advance_simulation(.05)
	check(actions("killed").size()==1 and game.kills==1 and game.gold>=gold_before+int(enemy.reward),"Cleanup emits one death and pays one kill reward")
	game._process(.15)
	check(actions("killed").size()==1,"Death animation does not repeat the reward or killed event")
	check(actions("waveend").size()==1,"Wave completion notification emits once")
	check(game._selected_name_visible(archer),"The study boundary restores the selected name")
	game.free()
	# Real movement and enemy damage are observed in a separate fresh battle.
	game=create_game(maps[0])
	var spear: Dictionary=deploy(game,"spear")
	game.start_battle()
	game.spawn_queue.clear()
	game._spawn_enemy("raider")
	enemy=game.enemies[-1]
	enemy.pathIndex=spear.postPathIndex
	enemy.position=spear.position+Vector2(.001,0)
	enemy.pointIndex=clampi(int(game.zones[spear.get("zoneIndex",game.zones.size()-1)].get("segmentIndex",0))+1,1,game.paths[int(enemy.pathIndex)].points.size()-1)
	enemy.blockedBy=spear.id
	enemy.animation="attack"
	enemy.animationClock=.3
	enemy.counterPlan={"releaseTime":.25,"damage":20.0}
	var previous_hp: float=float(spear.hp)
	game.ground_combat.counterattack(enemy,.01)
	hit=actions("hit")[-1]
	check(hit.side=="enemy" and hit.victimSide=="friendly" and is_equal_approx(float(hit.damage),previous_hp-float(spear.hp)),"Enemy counterattack reports actual allied HP loss")
	var footsteps_before: int=actions("footstep").size()
	var previous_position: Vector2=spear.position
	game.ground_combat._walk(spear,float(spear.homeDistance)+.06,.8)
	check(actions("footstep").size()>footsteps_before and spear.position.distance_to(previous_position)>0,"Actual ground travel emits a footstep")
	footsteps_before=actions("footstep").size()
	game.paused=true
	game._process(.2)
	check(actions("footstep").size()==footsteps_before,"Paused battle emits no footstep")
	game.free()
	game=create_game(maps[4])
	game.start_battle()
	game.spawn_queue.clear()
	game._spawn_enemy("raider")
	enemy=game.enemies[-1]
	footsteps_before=actions("footstep").size()
	game._move_enemy(enemy,1.0)
	check(actions("footstep").size()==footsteps_before,"Sailing troops do not make land-footstep sounds")
	var objective: Dictionary=game.objectives[0]
	previous_hp=float(objective.hp)
	game._escape_enemy(enemy,str(objective.id))
	check(actions("objective_hit").size()==1 and float(actions("objective_hit")[0].damage)==previous_hp-float(objective.hp),"Objective hit is emitted at actual damage, once")
	game._escape_enemy(enemy,str(objective.id))
	check(actions("objective_hit").size()==1,"Escaped enemy cannot repeat objective damage or sound")
	game.free()
	game=create_game(maps[0])
	var commander: Dictionary=deploy(game,"commander")
	game.start_battle()
	game.spawn_queue.clear()
	game._spawn_enemy("heavy")
	enemy=game.enemies[-1]
	enemy.pathIndex=commander.postPathIndex
	var home_post: Dictionary={}
	for post in game.zones:
		if str(post.get("id",""))==str(commander.postId): home_post=post;break
	enemy.pointIndex=int(home_post.segmentIndex)+1
	enemy.position=game.ground_combat.route_point(int(commander.postPathIndex),float(commander.homeDistance)+.005)
	var charges_before: int=actions("charge_impact").size()
	game.ground_combat._cavalry_step(commander,.01)
	check(str(commander.combatState)=="impact" and not commander.attackPlan.is_empty(),"Actual cavalry contact schedules its attack and recovery")
	check(not game._selected_name_visible(commander),"Actual cavalry impact does not place a name box over the close encounter")
	game._advance_actor_animations(game._impact_time("commander")-.01)
	check(actions("charge_impact").size()==charges_before,"Cavalry preparation does not emit an early impact sound or effect")
	previous_hp=float(enemy.hp)
	game._advance_actor_animations(.02)
	check(actions("charge_impact").size()==charges_before+1 and is_equal_approx(float(actions("charge_impact")[-1].damage),previous_hp-maxf(0,float(enemy.hp))),"Actual cavalry release emits one impact with actual damage")
	check(actions("charge_impact")[-1].weapon=="charge" and float(commander.chargeCooldown)>0,"Cavalry payload and its real cooldown agree")
	game._advance_actor_animations(.5)
	check(actions("charge_impact").size()==charges_before+1,"Cavalry recovery does not repeat its burst event")
	game.ground_combat._cavalry_step(commander,.01)
	check(str(commander.combatState)=="charge_return" and game._selected_name_visible(commander),"Actual cavalry return restores its overhead name")
	commander.combatState="charge"
	check(not game._selected_name_visible(commander),"Cavalry approach hides the overhead name even before attack animation")
	commander.combatState="engaged"
	check(not game._selected_name_visible(commander),"A held melee stance hides the overhead name even between strikes")
	commander.combatState="guard"
	check(game._selected_name_visible(commander),"Guard stance displays the selected name again")
	game.free()
	var ids: Dictionary={}
	for event in events:
		check(event.has("mapId") and event.has("wave") and event.has("time") and event.has("eventId"),"Feedback has explicit map/wave/time/sequence")
		# A new Game starts its own sequence; ids are unique within each map run.
		if event.action=="wavebegin": ids.clear()
		if event.action not in ["recruit","deploy"]:
			check(not ids.has(event.eventId),"Battle event sequence is not duplicated")
			ids[event.eventId]=true
		for key in ["position","sourcePosition","victimPosition"]:
			if event.has(key):
				check(event[key] is Dictionary and event[key].has("x") and event[key].has("y"),"Feedback position is a normalized serializable dictionary")
		var roundtrip = JSON.parse_string(JSON.stringify(event))
		check(roundtrip is Dictionary and roundtrip.type==event.type,"Event payload survives JSON serialization")
	var report: Dictionary={"checks":checks,"failures":failures,"events":events,"scope":"Actual game methods and source/victim HP observations, successful vs rejected UI actions, release timing, armor/overkill actual damage, killed/reward deduplication, enemy counterattack, moving/paused/sailing footstep behavior and objective-hit deduplication. Isolated fixture funds are used only for mechanics; campaign balance is independently verified."}
	var output=FileAccess.open("user://qa_combat_events.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_combat_events.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("COMBAT_EVENTS_QA ",JSON.stringify({"checks":checks,"failures":failures,"events":events.size()}))
	quit(0 if failures.is_empty() else 1)
