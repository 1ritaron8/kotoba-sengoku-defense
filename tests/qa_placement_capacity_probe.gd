extends SceneTree
const Game = preload("res://native/game.gd")
const TYPES: Array = ["archer","gunner","naginata","monk"]
const ROOT_PROFILE: String = "C:/JP_DF/tests/profiles/compact-placement/"
var checks: int = 0
var failures: Array[String] = []
var rejected_advertised: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size() <= 12: push_error("PLACEMENT_CAPACITY " + note)

func first_hint(game: Node2D, type_name: String) -> Vector2:
	for zone in game.zones:
		var hint: Vector2 = game._zone_placement_hint(zone, type_name)
		if hint.x < 0: continue
		var preview: Dictionary = game.placement_preview(hint)
		if bool(preview.valid): return hint
		if rejected_advertised.size()<100:
			rejected_advertised.append({"stageId":game.config.id,"zoneId":zone.id,"unitType":type_name,"activeUnits":game.units.size(),"hint":{"x":hint.x,"y":hint.y},"reason":preview.reason})
	return Vector2(-1,-1)

func observe(game: Node2D, stage: Dictionary, type_name: String) -> Dictionary:
	game.load_map(stage)
	game.gold = 10000
	var points: Array = []
	var ids: Array = []
	for index in range(int(stage.get("unitLimit",14))):
		if not game.begin_placement(type_name): break
		var hint: Vector2 = first_hint(game, type_name)
		if hint.x < 0:
			game.cancel_recruit()
			break
		var before: int = game.gold
		check(game.place_unit(hint.x,hint.y),str(stage.id)+" advertised homogeneous order commits " + type_name)
		game._advance_recruitment(100)
		check(game.gold == before-game.recruit_cost(type_name),str(stage.id)+" homogeneous order costs exactly once " + type_name)
		if game.units.size() != index+1: break
		points.append({"x":game.units[-1].position.x,"y":game.units[-1].position.y})
		ids.append(str(game.units[-1].get("postId",game.units[-1].get("zoneId",""))))
	return {"unitType":type_name,"count":game.units.size(),"positions":points,"postIds":ids}

func run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\","/").trim_suffix("/")
	check(profile.begins_with(ROOT_PROFILE) and OS.get_environment("LOCALAPPDATA").replace("\\","/").trim_suffix("/")==profile,"Private capacity profile only")
	if not failures.is_empty(): quit(2); return
	var source_sha: String = FileAccess.get_sha256("res://native/maps.json")
	var maps_path: String = OS.get_environment("QA_CANDIDATE_MAPS")
	if maps_path.is_empty(): maps_path = "res://native/maps.json"
	check(maps_path=="res://native/maps.json" or maps_path.replace("\\","/").begins_with(ROOT_PROFILE),"Candidate is a private workspace map")
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string(maps_path))
	check(maps.size()==40,"Forty stages inspected")
	var game: Node2D = Game.new()
	root.add_child(game)
	game.set_process(false)
	game.three_d_enabled = true
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	game.configure_roster(catalog,["archer","spear","samurai","gunner","naginata","monk","commander","ninja"],{})
	var rows: Array = []
	for stage in maps:
		var observations: Array = []
		for type_name in TYPES: observations.append(observe(game,stage,type_name))
		rows.append({"stageNumber":stage.stageNumber,"stageId":stage.id,"rangedPosts":stage.buildZones.size(),"groundPosts":stage.tactics.groundPosts.size(),"homogeneousPublicCapacity":observations})
	check(FileAccess.get_sha256("res://native/maps.json")==source_sha,"Read-only observation preserved production maps")
	game.free()
	var output: FileAccess = FileAccess.open(profile+"/capacity.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"scope":"Actual public order, hint followed by real placement_preview validity and production completion for homogeneous fixed classes; greedy player-style placement, not optimal packing or battle victory","checks":checks,"failures":failures,"passed":failures.is_empty(),"sourceMapsSha256":source_sha,"observedMapsSha256":FileAccess.get_sha256(maps_path),"rejectedAdvertisedHints":rejected_advertised,"rows":rows},"\t"))
	output.close()
	print("PLACEMENT_CAPACITY ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
