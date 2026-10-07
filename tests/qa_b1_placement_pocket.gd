extends SceneTree

const Battlefield = preload("res://native/battlefield_3d.gd")
const Game = preload("res://native/game.gd")
const PROOF_PATH: String = "res://tests/profiles/native-battlefield-hybrid-b1-relocation/proof.json"
const BLUEPRINT_PATH: String = "res://tests/profiles/map-render-blueprints/export-73323cb9/map_render_blueprints_manifest.json"
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures.append(note)
		push_error("B1_POCKET: "+note)

func road_distance(source: Dictionary, point: Vector2) -> float:
	var nearest: float = INF
	for route in source.get("paths",[]):
		var points: Array = route.get("points",[])
		for index in range(points.size()-1):
			var start: Vector2 = Vector2(float(points[index].x),float(points[index].y))
			var end: Vector2 = Vector2(float(points[index+1].x),float(points[index+1].y))
			nearest = minf(nearest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,start,end)))
	return nearest

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/native-battlefield-hybrid-"):
		push_error("An isolated native-battlefield-hybrid profile is required")
		quit(2)
		return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var source: Dictionary = maps[0]
	var proof: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROOF_PATH))
	var blueprint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BLUEPRINT_PATH))
	check(source.id == "basic-forest" and source.buildZones.size() == 14,"All fourteen first-stage emplacement zones remain")
	check(source.buildZones[0] == proof.after,"The approved B1 x/y/r changes are the actual source")
	check(bool(proof.bytesOutsideChangedFieldsIdentical) and bool(proof.otherThirteenFirstStageZonesIdentical) and bool(proof.otherThirtyNineStagesIdentical),"Byte and semantic change proof covers every non-target value")
	check(FileAccess.get_sha256("res://native/maps.json") == str(proof.sourceMapsSha256After),"Runtime map bytes match the recorded relocated source")
	var builder: Node3D = Battlefield.new()
	var first_fingerprint: String = JSON.stringify(builder._physical_contract(source)).sha256_text()
	var original: Dictionary = source.duplicate(true)
	original.buildZones[0] = proof.before
	var before_fingerprint: String = JSON.stringify(builder._physical_contract(original)).sha256_text()
	var blueprint_by_id: Dictionary = {}
	for record in blueprint.get("stages",[]): blueprint_by_id[str(record.stageId)] = record
	check(before_fingerprint == str(blueprint_by_id[source.id].geometry.physicalGeometryFingerprint),"Restoring only B1 matches the untouched original first blueprint")
	var fingerprints: Array = []
	for index in range(maps.size()):
		var current: Dictionary = maps[index]
		var actual: String = JSON.stringify(builder._physical_contract(current)).sha256_text()
		var old: String = str(blueprint_by_id[current.id].geometry.physicalGeometryFingerprint)
		if index>0: check(actual == old,"Every other frozen geometry stays identical: "+str(current.id))
		fingerprints.append({"stageId":current.id,"actual":actual,"frozenBlueprint":old,"unchanged":actual == old})
	builder.free()
	var game: Node2D = Game.new()
	game.three_d_enabled = true
	root.add_child(game)
	game.hide()
	game.set_process(false)
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	game.configure_roster(catalog,["archer"],{"archer":1})
	game.load_map(source)
	check(game.begin_placement("archer"),"The real first-stage archer placement flow opens")
	var center: Vector2 = Vector2(float(source.buildZones[0].x),float(source.buildZones[0].y))
	var radius: float = float(source.buildZones[0].r)
	var old_point: Vector2 = Vector2(float(proof.before.x),float(proof.before.y))
	check(not bool(game.placement_preview(old_point).valid),"The previous gatepost-overlapping point is no longer placeable")
	var observations: Array = []
	var valid_count: int = 0
	var road_rejected: int = 0
	for index in range(33):
		var point: Vector2 = center
		if index>0: point += Vector2.from_angle(TAU*float(index-1)/32.0)*radius
		var preview: Dictionary = game.placement_preview(point)
		var distance: float = road_distance(source,point)
		var legal: bool = bool(preview.valid)
		if index == 0: check(legal,"The relocated B1 center is actually placeable")
		check(legal == (distance >= .022),"Circle sample preserves the existing road exclusion: "+str(index))
		if legal:
			valid_count += 1
			check(Vector2(float(preview.position.x),float(preview.position.y)).distance_to(point)<.00001,"Accepted placement keeps its requested position: "+str(index))
		else: road_rejected += 1
		observations.append({"index":index,"x":point.x,"y":point.y,"pixelX":point.x*1280,"pixelY":point.y*720,"valid":legal,"roadDistance":distance,"reason":preview.reason})
	check(valid_count>16 and road_rejected>0,"Most pocket samples allow placement and route-edge samples remain safely excluded")
	check(game.units.is_empty() and game.recruitment_queue.is_empty() and game.gold == int(source.initialGold),"Preview inspection does not create units, reserve production or spend money")
	game.free()
	Battlefield.release_shared_resources()
	var report: Dictionary = {"checks":checks,"failures":failures,"sourceMapsSha256":proof.sourceMapsSha256After,"firstPhysicalGeometryFingerprint":first_fingerprint,"beforeFirstPhysicalGeometryFingerprint":before_fingerprint,"validPocketSamples":valid_count,"roadRejectedPocketSamples":road_rejected,"samples":observations,"stageFingerprints":fingerprints,"changeProof":PROOF_PATH}
	var file: FileAccess = FileAccess.open("user://b1-pocket-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("B1_POCKET checks=%d failures=%d valid=%d roadRejected=%d fingerprint=%s" % [checks,failures.size(),valid_count,road_rejected,first_fingerprint])
	quit(0 if failures.is_empty() else 1)
