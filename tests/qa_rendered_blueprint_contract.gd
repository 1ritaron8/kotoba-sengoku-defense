extends SceneTree

const Battlefield = preload("res://native/battlefield_3d.gd")
const FROZEN_SOURCE: String = "res://tests/profiles/map-render-blueprints/export-73323cb9/source-snapshot/battlefield_3d.gd"
var FrozenBattlefield: GDScript
const BLUEPRINT_MANIFEST: String = "res://tests/profiles/map-render-blueprints/export-73323cb9/map_render_blueprints_manifest.json"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/native-battlefield-hybrid-").to_lower()):
		push_error("An isolated native-battlefield-hybrid profile is required")
		quit(2)
		return
	for historical_path in [FROZEN_SOURCE,FROZEN_SOURCE.get_base_dir()+"/battlefield_materials.gd",BLUEPRINT_MANIFEST]:
		if not FileAccess.file_exists(historical_path):
			push_error("BLUEPRINT_GEOMETRY preserved historical input missing: "+ProjectSettings.globalize_path(historical_path)+"; current Native cannot replace this baseline.")
			quit(2)
			return
	FrozenBattlefield=load(FROZEN_SOURCE) as GDScript
	if FrozenBattlefield==null or not FrozenBattlefield.can_instantiate() or FrozenBattlefield.resource_path!=FROZEN_SOURCE:
		push_error("BLUEPRINT_GEOMETRY cannot bind preserved historical renderer: "+FROZEN_SOURCE)
		quit(2)
		return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var blueprint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BLUEPRINT_MANIFEST))
	var by_id: Dictionary = {}
	for record in blueprint.get("stages",[]):
		by_id[str(record.get("stageId",""))] = record
	var builder: Node3D = Battlefield.new()
	var reports: Array = []
	var failures: Array[String] = []
	var fallback_height_report: Dictionary = {}
	for config in maps:
		var id: String = str(config.id)
		var actual: String = JSON.stringify(builder._physical_contract(config)).sha256_text()
		var expected: String = str(by_id.get(id,{}).get("geometry",{}).get("physicalGeometryFingerprint",""))
		if expected.is_empty() or expected != actual:
			failures.append(id)
			push_error("BLUEPRINT_GEOMETRY mismatch: "+id+" "+expected+" != "+actual)
		reports.append({"stageId":id,"actual":actual,"blueprint":expected,"match":expected == actual})
		if id == "advanced-farm":
			var frozen: Node3D = FrozenBattlefield.new()
			for field in [frozen,builder]:
				field.stage = config
				field.history = config.get("historicalBattlefield",{})
				field.width = 18.5
				field.depth = 18.5/(1280.0/720.0)/sin(deg_to_rad(50.0))
				field.elevation = 50.0
				field.seed_value = absi(id.hash())
				field._collect_geometry()
				field._build_height_grid()
			var same_grid: bool = builder.heights == frozen.heights
			var same_features: bool = JSON.stringify(builder.height_features) == JSON.stringify(frozen.height_features)
			fallback_height_report = {"stageId":id,"actualVertices":builder.heights.size(),"unchangedHeightGrid":same_grid,"unchangedDerivedFeatures":same_features}
			if not same_grid or not same_features:
				failures.append("advanced-farm actual relief changed")
			frozen.free()
	builder.free()
	Battlefield.release_shared_resources()
	var file: FileAccess = FileAccess.open("user://blueprint-fingerprints.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"mapsSha256":FileAccess.get_sha256("res://native/maps.json"),"blueprintManifest":BLUEPRINT_MANIFEST,"checks":maps.size()+1,"failures":failures,"stages":reports,"fallbackHeightComparison":fallback_height_report},"\t"))
	file.close()
	print("BLUEPRINT_GEOMETRY checks=%d failures=%d" % [maps.size()+1,failures.size()])
	quit(0 if maps.size() == 40 and failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
