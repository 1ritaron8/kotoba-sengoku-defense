extends SceneTree
const Game = preload("res://native/game.gd")
var PROFILE: String=qa_project_path("tests/profiles/compact-placement/")
var checks: int=0
var failures: Array=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool,note: String) -> void:
	checks+=1
	if not value: failures.append(note)
func run() -> void:
	var private: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not private.begins_with(PROFILE.to_lower()) or OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower()!=private: quit(2);return
	var source_sha: String=FileAccess.get_sha256("res://native/game.gd")
	var stages: Array=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"maps-pocket-draft.json"))
	var game: Node2D=Game.new();root.add_child(game);game.set_process(false);game.three_d_enabled=true
	var rows: Array=[]
	var stage_count: int=0
	for stage in stages:
		if not str(stage.id).ends_with("-harbor"): continue
		stage_count+=1
		check(str(stage.theme)!="harbor" or int(stage.get("landingIndex",-1))==0,str(stage.id)+" actual historical land layout has no sailing declaration")
		for path_index in range(stage.paths.size()):
			for kind in ["raider","enemy_archer","commander"]:
				game.load_map(stage);game.wave=1
				var enemy: Dictionary=game._spawn_enemy(kind,1,{"pathIndex":path_index})
				check(int(enemy.pointIndex)==1,str(stage.id)+" actual spawn first target node")
				check(not game._sailing_visual(enemy),str(stage.id)+" actual birth is land stance")
				var index_zero: Dictionary=enemy.duplicate(true);index_zero.pointIndex=0
				check(not game._sailing_visual(index_zero),str(stage.id)+" legacy index zero is also land")
				var initial: Vector2=enemy.position
				for sample in range(80):
					game._move_enemy(enemy,.05)
					check(not game._sailing_visual(enemy),str(stage.id)+" real first 4s of navigation has no boat")
				check(enemy.position.distance_to(initial)>.001,str(stage.id)+" actual soldier advances")
				for actor in game.actor_states():
					if int(actor.id)==int(enemy.id): check(not bool(actor.sailing),str(stage.id)+" renderer receives land state")
				rows.append({"stageId":stage.id,"actualTheme":stage.theme,"pathIndex":path_index,"requestedKind":kind,"actualKind":enemy.kind,"firstPointIndex":1,"finalPointIndex":enemy.pointIndex,"sailing":game._sailing_visual(enemy)})
		# Separately observe the compatibility branch discussed in the review;
		# this is a private fixture, never a replacement source map.
		var legacy: Dictionary=stage.duplicate(true);legacy.theme="harbor";legacy.landingIndex=0
		game.load_map(legacy)
		var old_enemy: Dictionary=game._spawn_enemy("raider",1,{"pathIndex":0})
		check(not game._sailing_visual(old_enemy),str(stage.id)+" optional legacy landing=0 also never sails at birth")
		old_enemy.pointIndex=0
		check(not game._sailing_visual(old_enemy),str(stage.id)+" optional legacy index 0 remains land")
	check(stage_count==4,"All four formerly harbor IDs actually exercised")
	game.free()
	check(FileAccess.get_sha256("res://native/game.gd")==source_sha,"Production source stays unchanged")
	var out: FileAccess=FileAccess.open(PROFILE+"all-land-harbor-spawn.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"scope":"Actual birth, first 4 simulated seconds and renderer sailing state of every all-land former-harbor route; no source changes","checks":checks,"failures":failures,"rows":rows,"gameSha256":source_sha},"\t"));out.close()
	print("ALL_LAND_HARBOR ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
