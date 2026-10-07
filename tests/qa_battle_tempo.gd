extends SceneTree
const Battle = preload("res://native/game.gd")
const Store = preload("res://native/progress.gd")
var failures: Array = []
var checks: int = 0
var observations: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description);push_error(description)

func probe(config: Dictionary, multiplier: float) -> Dictionary:
	var game = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_seed(14571)
	var store = Store.new()
	game.configure_roster(store.unit_catalog,["archer","spear"],{})
	game.load_map(config)
	for type_name in ["archer","spear"]:
		check(game.recruit(type_name),str(config.id)+" recruits funded starter "+type_name)
		for point in game.placement_hints:
			if point.x>=0:
				check(game.place_unit(point.x,point.y),str(config.id)+" deploys advertised starter "+type_name)
				break
	var events: Array = []
	game.game_event.connect(func(event): events.append(event.duplicate(true)))
	game.set_speed(multiplier)
	game.start_battle()
	var spawn_time: float = -1
	var attack_time: float = -1
	var hit_time: float = -1
	var wall_time: float = 0
	var first_position: Vector2 = Vector2.ZERO
	for tick in range(1800):
		game._process(.05)
		wall_time += .05
		if spawn_time<0 and not game.enemies.is_empty(): spawn_time=wall_time;first_position=game.enemies[0].position
		for unit in game.units:
			if attack_time<0 and str(unit.animation)=="attack": attack_time=wall_time
		for enemy in game.enemies:
			if hit_time<0 and float(enemy.hp)<float(enemy.maxHp): hit_time=wall_time
		if hit_time>=0 or game.finished: break
	var result: Dictionary = {"mapId":config.id,"speed":multiplier,"spawnSeconds":spawn_time,"firstAttackSeconds":attack_time,"firstHitSeconds":hit_time,"simulationSeconds":game.elapsed,"wallSeconds":wall_time,"firstPosition":str(first_position),"events":events}
	game.free()
	return result

func frame_partition_probe(config: Dictionary, multiplier: float) -> void:
	var coarse = Battle.new()
	var fine = Battle.new()
	for game in [coarse,fine]:
		root.add_child(game)
		game.set_process(false)
		game.set_seed(4619)
		game.load_map(config)
		game.set_speed(multiplier)
		game.start_battle()
	for frame in range(20):
		coarse._process(.2)
		for subframe in range(4): fine._process(.05)
	check(is_equal_approx(coarse.elapsed,fine.elapsed),"Low-frame-rate and smooth frame delivery advance the same simulation time at "+str(multiplier))
	check(coarse.wave==fine.wave and coarse.spawn_queue==fine.spawn_queue and coarse.enemies.size()==fine.enemies.size(),"Frame delivery preserves wave/spawn density at "+str(multiplier))
	for index in range(mini(coarse.enemies.size(),fine.enemies.size())):
		check(coarse.enemies[index].position.distance_to(fine.enemies[index].position)<.00002 and is_equal_approx(float(coarse.enemies[index].hp),float(fine.enemies[index].hp)),"Actual marching position and HP do not depend on frame delivery")
	var before_time: float=coarse.elapsed
	var before_enemies: Array=coarse.enemies.duplicate(true)
	var before_queue: Array=coarse.spawn_queue.duplicate(true)
	coarse.paused=true
	coarse._process(.2)
	check(coarse.elapsed==before_time and coarse.enemies==before_enemies and coarse.spawn_queue==before_queue,"Explicit pause freezes march and spawning at "+str(multiplier))
	coarse.free();fine.free()

func density_probe(config: Dictionary) -> void:
	var game = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.load_map(config)
	game.start_battle()
	var observed_ids: Dictionary={}
	var peak_concurrent: int=0
	var spawn_times: Array=[]
	for frame in range(360):
		game._process(.05)
		peak_concurrent=maxi(peak_concurrent,game.enemies.size())
		for enemy in game.enemies:
			if not observed_ids.has(enemy.id):
				observed_ids[enemy.id]=true
				spawn_times.append(game.elapsed)
		if game.spawn_queue.is_empty(): break
	check(spawn_times.size()==4 and peak_concurrent==4,"First wave introduces a small four-soldier patrol instead of the previous eleven-soldier rush")
	for index in range(1,spawn_times.size()):
		check(absf(float(spawn_times[index])-float(spawn_times[index-1])-1.50)<=0.051,"Opening patrols arrive at a deliberate one-and-a-half-second interval")
	check(float(spawn_times[0])>=3 and float(spawn_times[-1])<8,"Three seconds of initial preparation precede the small patrol")
	observations.append({"densityMapId":config.id,"actualSpawnTimes":spawn_times,"peakConcurrentEnemies":peak_concurrent})
	game.free()

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("").to_lower()+"/"): quit(2);return
	var baseline: bool = "--baseline" in OS.get_cmdline_user_args()
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	for map in maps:
		if int(map.get("stageNumber",0)) not in [1,2,5,8,9,10]: continue
		for speed_value in [1.0,2.0,3.0]:
			var value: Dictionary = probe(map,speed_value)
			observations.append(value)
			if not baseline:
				check(absf(float(value.spawnSeconds)-3.0/speed_value)<=.051,"Preparation period follows requested speed at "+str(map.id)+" "+str(speed_value))
				check(float(value.firstHitSeconds)>0,"Actual damage occurs at "+str(map.id)+" "+str(speed_value))
				check(float(value.firstHitSeconds)<=25.0/speed_value+.075,"Prepared starters make contact after the readable initial approach")
				if speed_value>1:
					var normal: Dictionary=observations[observations.size()-int(speed_value)]
					check(absf(float(value.firstHitSeconds)*speed_value-float(normal.firstHitSeconds))<=.151,"Actual contact scales with the requested wall-clock speed")
			var brief: Dictionary = value.duplicate()
			brief.erase("events")
			print("BATTLE_TEMPO ",JSON.stringify(brief))
	if not baseline:
		for multiplier in [1.0,2.0,3.0]: frame_partition_probe(maps[0],multiplier)
		density_probe(maps[0])
	var report_path: String = "user://qa_battle_tempo.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_battle_tempo_%s.json" % ("baseline" if baseline else "final")
	var output: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"baseline":baseline,"scope":"Six actual first-tier maps, their funded two starter classes at advertised deployment hints, and real _process wall deltas at 1x/2x/3x. Measures first spawn, attack and HP damage. No audio/GPU assertion; campaign difficulty is tested separately."},"  "))
	output.close()
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
