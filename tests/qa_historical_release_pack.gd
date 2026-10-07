extends "qa_pack_3d.gd"
## Supplement to qa_pack_3d and qa_female_voice_packed; mounted release only.
const Weather = preload("res://native/battlefield_weather.gd")
const FINAL_MAPS_SHA = "ea5a85f32c4a8962a1c19734f36ac58ec22301c17b1ba36a966408429df8e252"

func run() -> void:
	if not safe_environment(): quit(2);return
	check(not source_only,"Release supplement requires an actual embedded artifact")
	if source_only: quit(2);return
	check(FileAccess.get_sha256("res://native/maps.json")==FINAL_MAPS_SHA,"Final historical maps bytes match the frozen approved source")
	var stages: Array = json_resource("res://native/maps.json",TYPE_ARRAY)
	check(stages.size()==40,"All forty final historical stages are embedded")
	if not verify_rendered_art_manifest(stages): quit(1);return
	var manifest: Dictionary = json_resource("res://assets/battlefields-rendered/manifest.json",TYPE_DICTIONARY)
	var tag: String = option("--art-path-tag")
	check(not tag.is_empty(),"Launcher explicitly identifies the final art generation tag")
	check(manifest.get("stages",[]).size()==40,"Final generation contains forty manifest render records")
	for index in range(manifest.get("stages",[]).size()):
		var entry: Dictionary = manifest.stages[index]
		var expected_path: String = "res://assets/battlefields-rendered/stage-%02d-%s-%s.png" % [index+1,str(stages[index].id),tag]
		check(not tag.is_empty() and str(entry.get("path",""))==expected_path,"Approved render path exactly identifies the requested final generation")
	var game: Node2D = Game.new()
	root.add_child(game)
	game.set_process(false)
	var boats: Array = []
	for stage in stages:
		game.load_map(stage)
		var weather: Dictionary = Weather.profile_for_stage(stage)
		check(not weather.is_empty() and float(weather.get("snowCoverage",-1))==0,"Embedded weather helper reads the actual authored seasonal profile")
		game._update_map_mode(21.0)
		check(not game.storm_active,"Legacy snow roster cannot generate an unauthored blizzard")
		for index in range(stage.get("paths",[]).size()):
			var entry: Dictionary = game._prepared_ambush_entry(index)
			if str(entry.get("transportKind",""))!="boat": continue
			boats.append(int(stage.stageNumber))
			var points: Array = entry.get("transportPoints",[])
			check(points.size()==4,"Actual river transport retains four authored points")
			var enemy: Dictionary = game._spawn_enemy("enemy_samurai",1,{"pathIndex":index,"ambushEntry":entry})
			check(bool(enemy.get("transportActive",false)) and enemy.position.distance_to(points[0])<.00001,"Embedded game starts the crew at its enemy dock")
			check(game._sailing_visual(enemy) and game._hunter_target(enemy,.05).is_empty(),"Transport renders inland and suppresses crew ground-target acquisition")
			for tick in range(2000):
				game._move_enemy(enemy,.05)
				if not bool(enemy.get("transportActive",false)): break
			check(not bool(enemy.get("transportActive",false)) and enemy.position.distance_to(points[-1])<.00001,"Actual embedded crew reaches its authored landing in finite time")
			check(bool(enemy.get("ingressActive",false)) and not bool(enemy.get("escaped",false)),"Landing resumes the separate ground ingress without main-route escape")
			game.enemies.clear()
		for minutes in [10,20]:
			game.load_map(stage,minutes)
			check(game.battle_minutes==minutes and float(game.battle_plan.targetSeconds)==minutes*60.0,"Embedded mode selects exactly ten or twenty pure-combat minutes")
			check(int(game.battle_plan.totalWaves)==(21 if minutes==10 else 41),"Embedded duration expands into its actual finite wave schedule")
			for multiplier in [1,2]:
				game.load_map(stage,minutes)
				game.start_battle()
				game.speed=multiplier
				game.spawn_queue.clear()
				game.spawn_clock=100000.0
				var before: float = game.elapsed
				game._process(.05)
				check(absf(game.elapsed-before-.05*multiplier)<.000001,"Actual process clock advances at selected 1x/2x speed")
				before=game.elapsed
				game.paused=true
				game._process(.05)
				check(game.elapsed==before,"Manual pause excludes combat time at either speed")
				game.paused=false
				game.between_waves=true
				game._process(.05)
				check(game.elapsed==before,"Learning interval excludes combat time at either speed")
	check(boats==[9,12,39],"Exactly three actual boat routes belong to stages nine, twelve and thirty-nine")
	game.free()
	var report: Dictionary = {"checks":checks,"failures":failures,"guard":guard_metadata,"boats":boats,"artPathTag":tag,"scope":"Actual embedded historical maps, seasonal helper, boat state transitions, forty stages × 10/20 modes × 1x/2x process clocks. Full art/audio verification is supplied by existing pack and female-voice verifiers."}
	var output: FileAccess = FileAccess.open("user://qa_historical_release_pack.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("HISTORICAL_RELEASE_PACK checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
