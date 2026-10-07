extends SceneTree
const Game = preload("res://native/game.gd")
const PROFILE: String = "C:/JP_DF/tests/profiles/compact-placement/"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var isolated: String=OS.get_environment("APPDATA").replace("\\","/")
	if not isolated.begins_with(PROFILE) or OS.get_environment("LOCALAPPDATA").replace("\\","/")!=isolated: quit(2);return
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
