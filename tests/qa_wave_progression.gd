extends SceneTree
## Roster budgets are compared to the actual preceding installed package.
const Battle = preload("res://native/game.gd")
var checks: int=0
var failures: Array[String]=[]
var observations: Array=[]
var REFERENCE: String=qa_project_path("tests/qa_wave_curve_reference.json")

func _initialize() -> void: call_deferred("run")
func check(ok: bool, note: String) -> void:
	checks+=1
	if not ok: failures.append(note); push_error(note)

func roster(stage: Dictionary) -> Dictionary:
	var game: Node2D=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.load_map(stage)
	var result: Dictionary={"id":stage.id,"waves":[],"count":0,"hp":0.0,"reward":0,"kindCounts":{}}
	for number in range(1,game.total_waves+1):
		game.wave=number-1
		game._begin_wave()
		var queue: Array=game.spawn_queue.duplicate()
		var sources: Array=game.spawn_source_waves.duplicate() if game.has_method("_build_wave_schedule") else []
		var info: Dictionary={"wave":number,"count":queue.size(),"delay":game.spawn_clock,"interval":game._spawn_interval(),"march":game._approach_march_factor() if game.has_method("_approach_march_factor") else 4.0}
		result.waves.append(info)
		for index in range(queue.size()):
			if sources.is_empty(): game._spawn_enemy(str(queue[index]))
			else: game._spawn_enemy(str(queue[index]),int(sources[index]))
			var enemy: Dictionary=game.enemies[-1]
			result.count=int(result.count)+1
			result.hp=float(result.hp)+float(enemy.maxHp)
			result.reward=int(result.reward)+int(enemy.reward)
			result.kindCounts[str(enemy.kind)]=int(result.kindCounts.get(str(enemy.kind),0))+1
			game.enemies.clear()
	game.free()
	return result

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("").to_lower()+"/"): quit(2); return
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if "--reference" in OS.get_cmdline_user_args():
		var stages: Dictionary={}
		for stage in maps: stages[str(stage.id)]=roster(stage)
		var output: FileAccess=FileAccess.open(REFERENCE,FileAccess.WRITE)
		output.store_string(JSON.stringify({"packSha":"5C6017388B583A8107503C7A5A23D24DBC3BA956B339DE501DF104C96FEBD24F","stages":stages,"scope":"Actual preceding installed package enemy roster and spawned HP/rewards. No combat/learning outcomes are claimed."},"  ")); output.close()
		print("WAVE_CURVE_REFERENCE stages=",stages.size())
		quit(0); return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(REFERENCE))
	for stage in maps:
		var before: Dictionary=reference.stages[str(stage.id)]
		var current: Dictionary=roster(stage)
		check(current.count==before.count,"Exact original enemy count retained: "+str(stage.id))
		var mixture_matches: bool=current.kindCounts.size()==before.kindCounts.size()
		for kind in before.kindCounts:
			mixture_matches=mixture_matches and int(current.kindCounts.get(kind,-1))==int(before.kindCounts[kind])
		check(mixture_matches,"Original type mixture retained: "+str(stage.id))
		check(absf(float(current.hp)-float(before.hp))<0.001,"Exact original total individual spawned HP retained: "+str(stage.id))
		check(current.reward==before.reward,"Exact original kill-reward budget retained: "+str(stage.id))
		check(float(current.waves[0].count)<float(before.waves[0].count)*0.75 and float(current.waves[1].count)<float(before.waves[1].count)*0.75,"First two waves are materially smaller than preceding package: "+str(stage.id))
		check(int(current.waves[-1].count)>=int(current.waves[0].count)*4,"Final army is visibly larger than initial patrol: "+str(stage.id))
		check(current.waves[0].delay==3.0 and current.waves[0].interval==1.5 and current.waves[1].interval==1.35,"Opening grants preparation and spaced troop arrivals: "+str(stage.id))
		check(current.waves[0].march==2.35 and current.waves[-1].march==4.0 and current.waves[-1].interval==0.62,"The final wave advances and spawns more densely: "+str(stage.id))
		for index in range(1,current.waves.size()):
			check(int(current.waves[index].count)>=int(current.waves[index-1].count),"Enemy headcount grows rather than alternating artificial gaps: "+str(stage.id)+"/"+str(index+1))
		observations.append(current)
	var file: FileAccess=FileAccess.open("user://qa_wave_progression.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_wave_progression.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"referencePackSha":reference.packSha,"stages":observations,"scope":"Actual prior package roster vs new forty-stage scheduler, spawned HP and reward totals, early preparation and final army sizes. Full combat/learning-mode campaign outcomes are independently simulated."},"  ")); file.close()
	print("WAVE_PROGRESSION_QA ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
