extends "res://tests/qa_marching_contracts.gd"
const Audio=preload("res://native/battle_audio.gd")
const Troops=preload("res://native/troops_3d.gd")

func draw(game: Node2D, kind: String, hinted: bool=false) -> Dictionary:
	for index in range(200):
		var id: String=kind+str(index)
		var receipt: Dictionary=game.grant_learning_reward(hinted,id,"meaning")
		if str(receipt.get("kind",""))==kind:
			game.battle_support.jobs=game.battle_support.jobs.filter(func(job): return str(job.receipt.attemptId)==id)
			return receipt
	check(false,"Draw reaches eligible reward "+kind)
	return {}

func support_fixture() -> Dictionary:
	var stage: Dictionary=fixture()
	stage.historicalBattlefield={"sceneBiome":"mountain_forest","heightFeatures":[{"kind":"ridge","x":.4,"y":.53,"w":.2,"h":.2,"amplitudeWorld":1.0}]}
	return stage

func reward_case(kind: String) -> void:
	var game: Node2D=make_game(support_fixture(),10)
	hold(game)
	game.spawn_clock=0.0
	game.paused=true
	var gold: int=game.gold
	var receipt: Dictionary=draw(game,kind)
	if receipt.is_empty(): game.free();return
	var replay: Dictionary=game.grant_learning_reward(true,str(receipt.attemptId),"grammar")
	check(replay.kind==receipt.kind and replay.strength==receipt.strength and replay.get("duplicate",false),kind+" replay fixes original draw and strength")
	check(game.gold==gold and game.units.is_empty() and game.recruitment_queue.is_empty() and game.learning_supports.is_empty(),kind+" changes no cash, permanent units, production or legacy aura")
	var before: String=JSON.stringify(game.battle_support.snapshot())
	game.advance_simulation(4.0)
	game.battle_support.step(4.0)
	check(JSON.stringify(game.battle_support.snapshot())==before,kind+" fully frozen during study")
	game.paused=false
	var origin: Vector2=game.battle_support.jobs[0].terrain.fire if kind in ["rockfall","mountain_matchlocks"] else Vector2(.4,.5)
	var enemy: Dictionary=game._spawn_enemy("heavy",1,{"pathIndex":int(receipt.pathIndex)})
	enemy.position=origin
	enemy.hp=1000.0;enemy.maxHp=1000.0
	var living_before: String=JSON.stringify(enemy)
	if kind=="march_drum":
		check(game.begin_placement("spear",int(receipt.pathIndex)),"Drum produces existing marching unit on fixed front")
		await_production(game)
		game.enemies.clear();game.enemies=[enemy]
	game.projectiles.clear()
	game.battle_support.step(.025)
	check(game.battle_support.claims[str(receipt.attemptId)].state=="active",kind+" begins after resume")
	if kind=="supply_disruption":
		check(JSON.stringify(enemy)==living_before and game.battle_support.departure_delay>2.0,"Supply delays departures without editing living enemy")
		var count: int=game.enemies.size()
		game.advance_simulation(.5)
		check(game.enemies.size()==count and game.spawn_queue.size()==1,"Supply actually prevents queued departure")
		game.advance_simulation(3.0)
		check(game.spawn_queue.is_empty(),"Supply releases future departure within finite time")
	if kind=="archer_cover": check(game.projectiles.size()==3,"Bow grants exactly three actual projectiles")
	if kind=="march_drum":
		var unit: Dictionary=game.units[0]
		var path: int=int(unit.postPathIndex)
		var factor: float=float(game.battle_support.mobility_bases[int(unit.id)])
		check(float(unit.mobilityFactor)>factor,"Drum has actual temporary march effect")
		var distance: float=float(unit.routeDistance)
		for tick in range(30):
			game.advance_simulation(.025)
			check(int(unit.postPathIndex)==path and float(unit.routeDistance)<=distance+.00001 and game.ground_combat.land_segment_safe(unit.position,unit.position,.003),"Drum preserves route, forward progress and land")
			distance=float(unit.routeDistance)
		game.battle_support.cease()
		check(float(unit.mobilityFactor)==factor,"Drum restores exact original mobility")
	if kind=="mountain_matchlocks":
		var count: int=game.units.size()
		var troops: Control=Troops.new()
		root.add_child(troops)
		troops.set_process(false)
		troops.set_stage(game.config)
		troops.bind_battle(game)
		troops.sync_actor_states(game.actor_states())
		check(troops.support_flags.size()==3,"Three original gunner actors carry blue support flags")
		for tick in range(64):
			game.battle_support.step(.025)
			var actors: Array=game.battle_support.actor_states()
			check(actors.size()==3,"Transient gunner group retains exactly three members")
			for actor in actors:
				check(actor.type=="gunner" and actor.friendly and actor.transientSupport and int(actor.supportPathIndex)==int(receipt.pathIndex) and not actor.sailing and game.ground_combat.land_segment_safe(Vector2(actor.x,actor.y),Vector2(actor.x,actor.y),.003),"Support uses friendly original gunner only on its authored dry front")
		check(game.projectiles.size()==3 and game.units.size()==count,"Gunners fire one three-shot volley and add no permanent roster")
		game.battle_support.step(.1)
		check(game.battle_support.actor_states().is_empty(),"Support group completes safe retreat and disappears")
		troops.sync_actor_states(game.actor_states())
		check(troops.support_flags.is_empty(),"Completed transient actors remove blue flags")
		troops.free()
	if kind=="rockfall":
		check(game.battle_support.rock_states().size()==3,"Rockfall has three actual visible stones")
		var troops: Control=Troops.new()
		root.add_child(troops)
		troops.set_process(false)
		troops.set_stage(game.config)
		troops.bind_battle(game)
		troops.sync_actor_states(game.actor_states())
		check(troops.support_rocks.size()==3,"Actual renderer creates three temporary stone meshes")
		game.battle_support.step(.8)
		check(float(enemy.hp)<1000.0 and game.battle_support.rock_states().is_empty(),"Rockfall releases bounded damage once")
		var hp: float=float(enemy.hp)
		game.battle_support.step(.1)
		check(float(enemy.hp)==hp,"Rockfall cannot duplicate damage")
		troops.sync_actor_states(game.actor_states())
		check(troops.support_rocks.is_empty(),"Completed stone effect cleans temporary meshes")
		troops.free()
	game.free()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/").to_lower()) or OS.get_environment("APPDATA")!=OS.get_environment("LOCALAPPDATA"): quit(2);return
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	maps=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var terrain_count: int=0
	var gun_count: int=0
	for stage in maps:
		var game: Node2D=make_game(stage,10)
		for path_index in range(game.paths.size()):
			var pool: Array=game.battle_support.eligible(path_index)
			var plan: Dictionary=game.battle_support.terrain_plan(path_index)
			if "rockfall" in pool: terrain_count+=1
			if "mountain_matchlocks" in pool: gun_count+=1
			check(("rockfall" in pool)==not plan.is_empty(),"Actual terrain controls rockfall eligibility")
			if not plan.is_empty():
				for member in range(3): check(game.ground_combat.land_segment_safe(plan.origins[member],plan.firing[member],.005),"Authored mountain support approach and retreat stay on land")
		game.free()
	check(terrain_count>0 and gun_count>0,"Actual campaign offers both terrain rewards")
	var flat: Node2D=make_game(fixture(),10)
	check(flat.battle_support.eligible(0)==["archer_cover","march_drum","supply_disruption"],"Flat battlefield excludes rockfall and mountain guns")
	var normal: float=flat.battle_support.strength(false,"meaning")
	check(is_equal_approx(flat.battle_support.strength(true,"meaning"),normal*.55),"Hints consistently weaken support")
	check(is_equal_approx(flat.battle_support.strength(false,"grammar"),normal*.85),"Grammar support uses restrained common scale")
	flat.config.stageNumber=40
	for type in Types: flat.campaign_levels[type]=10
	check(flat.battle_support.strength(false,"meaning")>normal and flat.battle_support.strength(false,"meaning")<=1.5,"Level/stage scaling is bounded")
	flat.free()
	for speed in [1.0,2.0]:
		var game: Node2D=make_game(fixture(),10)
		hold(game)
		game.paused=true
		var receipt: Dictionary=draw(game,"supply_disruption")
		for tick in range(10): game._process(.05)
		check(game.battle_support.snapshot()[0].age==0.0,"Study holds support clock at both battle speeds")
		game.paused=false;game.speed=speed
		for tick in range(10): game._process(.05)
		check(is_equal_approx(float(game.battle_support.snapshot()[0].age),.5*speed),"Support follows actual 1x/2x battle clock")
		game.close_battle()
		check(game.battle_support.jobs.is_empty() and game.battle_support.departure_delay==0.0,"Closing clears pending battle-only effect")
		game.free()
	var water: Node2D=make_game(support_fixture(),10)
	hold(water)
	var target: Dictionary=water._spawn_enemy("heavy",1,{"pathIndex":0})
	target.position=Vector2(.45,.5)
	water.ground_combat.water_rects.append(Rect2(.42,.49,.01,.02))
	check(water.battle_support._targets(0,Vector2(.4,.5),3,.28,true).is_empty(),"Land support cannot shoot or roll through a water boundary")
	check(water.battle_support._targets(1,target.position,3,.28,false).is_empty(),"Support cannot jump to another locked front")
	water.free()
	for kind in ["archer_cover","march_drum","supply_disruption","rockfall","mountain_matchlocks"]: reward_case(kind)
	var audio: Node=Audio.new()
	root.add_child(audio)
	check(audio._resolve_effect("learning-support",{"supportKind":"march_drum"})=="support_drum","Actual march event resolves external taiko clip")
	var wav: AudioStreamWAV=AudioStreamWAV.load_from_file("res://assets/sfx/taiko_march.wav")
	check(wav!=null and wav.format==AudioStreamWAV.FORMAT_16_BITS and wav.mix_rate==44100 and not wav.stereo and wav.get_length()>1.9,"Licensed taiko loads as bounded mono PCM16 WAV")
	audio.free()
	var report: Dictionary={"checks":checks,"failures":failures,"terrainFronts":terrain_count,"gunnerFronts":gun_count}
	var output: FileAccess=FileAccess.open("res://tests/qa_battle_support.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	print("BATTLE_SUPPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
