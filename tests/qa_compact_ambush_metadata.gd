extends SceneTree
const Game = preload("res://native/game.gd")
var PROFILE: String = qa_project_path("tests/profiles/compact-placement/")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var isolated: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not isolated.begins_with(PROFILE.to_lower()) or OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower()!=isolated: quit(2);return
	var candidate: String=PROFILE+"maps-pocket-draft.json"
	var source_sha: String=FileAccess.get_sha256("res://native/maps.json")
	var game: Node2D=Game.new();root.add_child(game);game.set_process(false)
	var stages: Array=JSON.parse_string(FileAccess.get_file_as_string(candidate))
	var rows: Array=[]
	var failures: Array=[]
	var count: int=0
	for stage in stages:
		game.load_map(stage)
		var actual: Array=[]
		for site in game.ground_combat.ambush_sites:
			if site.position.y<.115 or not game.ground_combat.ambush_position_legal(site.position,site.entryPosition): failures.append(str(site.id))
			actual.append({"id":site.id,"pathIndex":site.pathIndex,"x":site.position.x,"y":site.position.y,"entry":{"x":site.entryPosition.x,"y":site.entryPosition.y},"r":site.r,"role":"external_ambush_cover"})
			count+=1
		rows.append({"stageId":stage.id,"ambushClearings":actual})
	game.free()
	if FileAccess.get_sha256("res://native/maps.json")!=source_sha: failures.append("Production changed")
	var out: FileAccess=FileAccess.open(PROFILE+"ambush-verification.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"scope":"Actual Game-generated N sites, land/entry legality and original-body top margin; private metadata synchronization only","passed":failures.is_empty(),"failures":failures,"candidateSha256":FileAccess.get_sha256(candidate),"ambushEnrichments":rows,"count":count},"\t"));out.close()
	print("AMBUSH_METADATA ",count," actual sites, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
