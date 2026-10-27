extends SceneTree
## Isolated simulation checks. Paid recruitment is exercised through its public
## API; repositioning one recruited defender is an explicit combat fixture.
const Battle=preload("res://native/game.gd")
const PaintedStage=preload("res://native/painted_stage.gd")
var checks: int=0
var failures: Array=[]
var evidence: Dictionary={}

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)

func run() -> void:
	var maps: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	var base: Dictionary=PaintedStage.apply(maps[0])
	var scenario_counts: Dictionary={}
	for scenario_id in ["basic-forest","basic-town","basic-river"]:
		var stage: Dictionary=base.duplicate(true)
		# basic-town/basic-river borrow first-map geometry ONLY in this isolated
		# component fixture. No new map is registered or claimed playable.
		stage["id"]=scenario_id
		stage["stageNumber"]=1 if scenario_id=="basic-forest" else 3 if scenario_id=="basic-town" else 4
		stage["combatMode"]="siege" # Must be ignored by the story registry.
		var game: Node2D=Battle.new()
		root.add_child(game)
		game.set_process(false)
		game.configure_roster(catalog.units,["archer","spear","samurai","gunner","monk","commander","ninja"],{})
		game.explicit_selection_id=123
		game.load_map(stage,10)
		check(game.explicit_selection_id==-1,"Map load retained an explicit selection")
		check(game.paths.size()==1 and game.config.initialGold==base.initialGold,"Scenario fixture changed copied geometry/economy: "+scenario_id)
		if scenario_id=="basic-river":
			game.start_battle()
			# Cross the old combat deadline deliberately: a noncombat scenario
			# must wait for its future real handoff predicate, not auto-win.
			game.elapsed=float(game.battle_plan.get("targetSeconds",600.0))-.05
			game.advance_simulation(.1)
			game._append_spawn_entry("raider",3)
			check(game.spawn_queue.is_empty() and game.enemies.is_empty() and game.ambush_warnings.is_empty(),"Handoff scenario created combat pressure")
			check(not game.finished,"Handoff scenario falsely completed through old combat timer")
			scenario_counts[scenario_id]={"combatEnabled":game.config.enemyModeProfile.combatEnabled,"spawnCount":game.spawn_queue.size()}
			game.free()
			continue
		game.wave=5
		game._append_spawn_entry("raider",5)
		var queued_kind: String=str(game.spawn_queue[0])
		var queued_options: Dictionary=game.spawn_metadata[0]
		check(bool(queued_options.fortification)==(scenario_id=="basic-town"),"Story did not control the real stationary-target queue: "+scenario_id)
		scenario_counts[scenario_id]={"queuedKind":queued_kind,"profile":game.config.enemyModeProfile.id,"fixtureOnly":scenario_id!="basic-forest"}
		if scenario_id!="basic-town":
			game.wave=4
			check(not bool(game.emplacement_assault_plan().active),"Raid cadence leaked into wrong wave: "+scenario_id)
			game.free()
			continue
		game.spawn_queue.clear();game.spawn_source_waves.clear();game.spawn_metadata.clear()
		var crew: Dictionary=game._spawn_enemy(queued_kind,5,queued_options)
		check(not crew.is_empty() and bool(crew.get("stationaryAfterIngress",false)),"Story siege fixture has no reachable real structure crew")
		if crew.is_empty() or not bool(crew.get("stationaryAfterIngress",false)):
			evidence["crewFailure"]={"kind":queued_kind,"spawn":str(crew)}
			game.free()
			continue
		var actor_id: int=int(crew.id)
		var start_hp: float=float(crew.hp)
		var previous: Vector2=crew.position
		var first_visible: Dictionary={}
		var elapsed: float=0.0
		var largest_step: float=0.0
		check(not Rect2(-.05,-.05,1.1,1.1).has_point(previous),"Tower crew began inside the map")
		check(not bool(crew.stationaryEnemy) and not bool(crew.fortification),"Approaching crew was already a tower")
		for unused in range(1200):
			game._move_enemy(crew,.05)
			elapsed+=.05
			var traveled: float=previous.distance_to(crew.position)
			largest_step=maxf(largest_step,traveled)
			check(traveled<=float(crew.speed)*game._approach_march_factor()*1.6*.05+.00001,"Tower crew teleported during ingress")
			previous=crew.position
			if first_visible.is_empty() and Rect2(0,0,1,1).has_point(crew.position): first_visible={"id":int(crew.id),"x":crew.position.x,"y":crew.position.y,"hp":float(crew.hp)}
			if not bool(crew.get("ingressActive",false)): break
		check(int(crew.id)==actor_id and float(crew.hp)==start_hp,"Crew identity or health reset on arrival")
		check(bool(crew.stationaryEnemy) and bool(crew.fortification) and not bool(crew.ingressActive),"Arrival did not create the attackable stationary target")
		check(crew.position.distance_to(crew.fortificationPosition)<.00001,"Visual structure anchor differs from physical station")
		check(game.ground_combat.is_tower_attacker(crew),"Settled enemy does not satisfy actual tower-target predicate")
		check(game.begin_placement("spear",0),"Public paid spear recruitment failed")
		game._advance_recruitment(2.0)
		if not game.units.is_empty():
			var defender: Dictionary=game.units[0]
			defender.position=crew.position+Vector2(.045,0)
			var defender_hp: float=float(defender.hp)
			for unused in range(50):
				game._advance_actor_animations(.05)
				game._enemy_ranged_step(crew,.05)
				game._update_projectiles(.05)
			check(float(defender.hp)<defender_hp,"Real settled crew produced no projectile damage")
			check(crew.position.distance_to(crew.fortificationPosition)<.00001,"Firing tower pursued its target")
			game._damage_enemy(crew,1.0,"spear",defender)
			check(float(crew.hp)<start_hp,"Stationary target did not receive real damage")
			scenario_counts[scenario_id]["combatFixtureDamage"]=defender_hp-float(defender.hp)
		else: check(false,"Paid spear order produced no defender for isolated combat fixture")
		evidence["siegeIngress"]={"actorId":actor_id,"firstVisible":first_visible,"arrivalSeconds":elapsed,"largestStep":largest_step,"arrivalHp":start_hp,"station":str(crew.position),"sameID":int(crew.id)==actor_id}
		game.free()
	evidence["scenarios"]=scenario_counts
	print(JSON.stringify({"suite":"enemy-mode-integration","checks":checks,"failures":failures,"evidence":evidence,"scope":"actual stage01 plus isolated basic-town/basic-river scenario fixtures borrowing its geometry; queue, physical same-ID crew ingress and stationary combat; no claim of other registered maps, real UI or rendered performance"}))
	quit(0 if failures.is_empty() else 1)
