extends SceneTree
const Game = preload("res://native/game.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const MARCHING: Array = ["spear","samurai","commander"]
var PROFILE: String = qa_project_path("tests/profiles/compact-placement/")
var checks: int = 0
var failures: Array[String] = []
var rows: Array = []
var ambush_enrichments: Array = []

func _initialize() -> void: call_deferred("run")
func check(value: bool,note: String) -> void:
	checks+=1
	if not value:
		failures.append(note)
		if failures.size()<=20: push_error("COMPACT_PLACEMENT "+note)

func legal_hint(game: Node2D,type_name: String) -> Vector2:
	for zone in game.zones:
		var hint: Vector2 = game._zone_placement_hint(zone,type_name)
		if hint.x>=0 and bool(game.placement_preview(hint).valid): return hint
	return Vector2(-1,-1)

func deploy(game: Node2D,type_name: String,tag: String) -> bool:
	var before_gold: int = game.gold
	var before_count: int = game.units.size()
	if not game.begin_placement(type_name): return false
	if not type_name in MARCHING:
		check(game.gold==before_gold,tag+" preview reserves no gold "+type_name)
		var hint: Vector2 = legal_hint(game,type_name)
		if hint.x<0: game.cancel_recruit();return false
		if not game.place_unit(hint.x,hint.y): return false
	game._advance_recruitment(100)
	check(game.gold==before_gold-game.recruit_cost(type_name),tag+" actual public order costs once "+type_name)
	check(game.units.size()==before_count+1,tag+" actual production creates requested soldier "+type_name)
	if game.units.size()==before_count+1:
		check(str(game.units[-1].type)==type_name,tag+" no different-class fallback "+type_name)
		return true
	return false

func stripped(stage: Dictionary) -> Dictionary:
	var result: Dictionary = stage.duplicate(true)
	result.erase("buildZones")
	result.tactics.erase("groundPosts")
	result.historicalBattlefield.erase("ambushClearings")
	return result

func run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	check(profile.begins_with(PROFILE.to_lower()) and OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower().trim_suffix("/")==profile,"Isolated private APPDATA and LOCALAPPDATA")
	if not failures.is_empty(): quit(2);return
	var source_sha: String = FileAccess.get_sha256("res://native/maps.json")
	var candidate: String = PROFILE+"maps-pocket-draft.json"
	var stages: Array = JSON.parse_string(FileAccess.get_file_as_string(candidate))
	var baseline: Array = JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"maps-pocket-before.json"))
	check(stages.size()==40 and baseline.size()==40,"All forty maps present")
	var game: Node2D = Game.new()
	root.add_child(game)
	game.set_process(false)
	game.three_d_enabled = true
	game.configure_roster(JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units,TYPES,{})
	var singles: int = 0
	var mixed: int = 0
	for index in range(stages.size()):
		var stage: Dictionary = stages[index]
		var old: Dictionary = baseline[index]
		var tag: String = str(stage.id)
		check(stripped(stage)==stripped(old),tag+" every road, objective, water, economic, story, trait and learning value is unchanged")
		check(stage.buildZones.size()==old.buildZones.size() and stage.tactics.groundPosts.size()>=old.tactics.groundPosts.size(),tag+" original placement points remain; only approved compact sub-centres may be added")
		var original_s_ids: Array=[]
		var candidate_s_ids: Array=[]
		for original_post in old.tactics.groundPosts: original_s_ids.append(str(original_post.id))
		for candidate_post in stage.tactics.groundPosts:
			if str(candidate_post.id) in original_s_ids: candidate_s_ids.append(str(candidate_post.id))
		check(candidate_s_ids==original_s_ids,tag+" original S IDs retain relative order and identity")
		game.load_map(stage)
		check(not game.presentation_mirrored,tag+" canonical lower-home layout retains orientation")
		var actual_clearings: Array=[]
		for site in game.ground_combat.ambush_sites:
			check(site.position.y>=.115,tag+" actual N floor retains original ninja head/weapon upper-frame margin")
			actual_clearings.append({"id":site.id,"pathIndex":site.pathIndex,"x":site.position.x,"y":site.position.y,"entry":{"x":site.entryPosition.x,"y":site.entryPosition.y},"r":site.r,"role":"external_ambush_cover"})
		ambush_enrichments.append({"stageId":stage.id,"ambushClearings":actual_clearings})
		for zone in game.zones:
			var type_name: String = "archer" if str(zone.placementRole)=="ranged" else "ninja" if str(zone.placementRole)=="ambush" else "gunner"
			check(game._zone_placement_hint(zone,type_name).x>=0,tag+" every advertised placement zone retains an actual compatible click "+str(zone.id))
		for type_name in TYPES:
			game.load_map(stage)
			game.gold=10000
			if deploy(game,type_name,tag): singles+=1
			else: check(false,tag+" single requested class can deploy "+type_name)
		game.load_map(stage)
		game.gold=20000
		for type_name in TYPES:
			if deploy(game,type_name,tag): mixed+=1
			else: check(false,tag+" eight distinct classes can coexist "+type_name)
		for filler in range(int(stage.unitLimit)-TYPES.size()):
			if not deploy(game,"archer",tag): check(false,tag+" mixed army reaches unchanged stage capacity");break
		check(game.units.size()==int(stage.unitLimit),tag+" mixed public recruitment reaches original 14/16/18/20 capacity")
		rows.append({"stageId":stage.id,"stageNumber":stage.stageNumber,"rangedCount":stage.buildZones.size(),"groundCount":stage.tactics.groundPosts.size(),"mixedUnitCount":game.units.size(),"unchangedUnitLimit":stage.unitLimit})
	check(FileAccess.get_sha256("res://native/maps.json")==source_sha,"Private QA never edits production maps")
	game.free()
	var output: FileAccess = FileAccess.open(PROFILE+"runtime-verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"scope":"Actual public eight-class selection, production, mixed unchanged army capacity and source-value preservation; body-geometry clearance is a separate Native exporter observation","passed":failures.is_empty(),"checks":checks,"failures":failures,"sourceMapsSha256":source_sha,"candidateSha256":FileAccess.get_sha256(candidate),"singleClassDeployments":singles,"mixedDistinctDeployments":mixed,"ambushEnrichments":ambush_enrichments,"rows":rows},"\t"));output.close()
	print("COMPACT_PLACEMENT ",checks," checks, ",failures.size()," failures; single ",singles," mixed ",mixed)
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
