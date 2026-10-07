extends SceneTree
## Read-only feasibility evidence. Rotated dictionaries remain in memory only.
const Game = preload("res://native/game.gd")
var PROFILE_PREFIX: String = qa_project_path("tests/profiles/lower-layout-design/")
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []
var map_sha: String = ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		if failures.size()<=12: push_error("LOWER_LAYOUT_DESIGN "+message)

func rotate(point: Vector2, turns: int) -> Vector2:
	match turns%4:
		1: return Vector2(1-point.y,point.x)
		2: return Vector2(1-point.x,1-point.y)
		3: return Vector2(point.y,1-point.x)
	return point

func source_point(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x",0)),float(value.get("y",0)))

func transformed_rect(value: Dictionary, turns: int) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	var original: Rect2 = Rect2(source_point(value),Vector2(float(value.get("w",0)),float(value.get("h",0))))
	var corners: Array[Vector2] = [rotate(original.position,turns),rotate(Vector2(original.end.x,original.position.y),turns),rotate(original.end,turns),rotate(Vector2(original.position.x,original.end.y),turns)]
	var lower: Vector2 = corners[0]
	var upper: Vector2 = corners[0]
	for point in corners:
		lower=lower.min(point)
		upper=upper.max(point)
	result.x=lower.x
	result.y=lower.y
	result.w=upper.x-lower.x
	result.h=upper.y-lower.y
	return result

func rotated_data(value: Variant, path: String, turns: int) -> Variant:
	if value is Array:
		var result: Array=[]
		for item in value: result.append(rotated_data(item,path+"[]",turns))
		return result
	if not value is Dictionary: return value
	var result: Dictionary={}
	for key in value: result[key]=rotated_data(value[key],path+"."+str(key) if not path.is_empty() else str(key),turns)
	if not value.has("x") or not value.has("y"): return result
	if path in ["water","bridges[]","historicalBattlefield.waterFeatures[]"]:
		var rectangle: Dictionary=transformed_rect(value,turns)
		for key in ["x","y","w","h"]: result[key]=rectangle[key]
	else:
		var position: Vector2=rotate(source_point(value),turns)
		result.x=position.x
		result.y=position.y
		if path=="historicalBattlefield.heightFeatures[]":
			# These x/y denote a center and w/h are axes before orientation.
			# Rotate axes via orientation only; swapping w/h again would undo it.
			result.orientationRadians=float(value.get("orientationRadians",0))+float(turns)*PI*.5
		elif path in ["historicalBattlefield.sceneLandmarks[]","historicalBattlefield.landmarkLabels[]"]:
			# Only a candidate art-layout footprint, not a claim that anisotropic
			# world mesh/noise height is exactly rotated by the current renderer.
			if turns%2==1 and result.get("scale",null) is Dictionary:
				var size: Dictionary=result.scale
				var width: float=float(size.get("w",0))
				size.w=float(size.get("h",0))
				size.h=width
	return result

func captures(game: Node2D) -> Dictionary:
	var lengths: Array=[]
	for cumulative in game.ground_combat.cumulative: lengths.append(float(cumulative[-1]))
	var posts: Array=[]
	var generated: int=0
	for zone in game.zones:
		if str(zone.get("placementRole",""))=="ground": posts.append({"id":zone.id,"position":zone.position})
		elif str(zone.get("placementRole",""))=="ambush": generated+=1
	return {"lengths":lengths,"bases":game.ground_combat.march_bases.duplicate(true),"posts":posts,"ambushSiteCount":generated,"water":game.ground_combat.water_rects.duplicate(),"gold":game.gold,"objectiveHp":game.objectives.map(func(item):return int(item.hp)),"sourceWaves":game.total_waves}

func geometry_checks(source: Dictionary, candidate: Dictionary, original: Dictionary, actual: Dictionary, turns: int) -> void:
	var tag: String=str(source.id)+" "+str(turns*90)+" degrees"
	check(original.gold==actual.gold and original.objectiveHp==actual.objectiveHp and original.sourceWaves==actual.sourceWaves,tag+" retains economy, objective HP and wave count")
	check(source.tactics.groundPosts==candidate.tactics.groundPosts,tag+" retains path/segment/t tactical anchors and capacities")
	check(original.lengths.size()==actual.lengths.size(),tag+" retains path count")
	for index in range(original.lengths.size()):
		check(absf(float(original.lengths[index])-float(actual.lengths[index]))<.000002,tag+" keeps normalized path length "+str(index))
		check(source.paths[index].id==candidate.paths[index].id and source.paths[index].objectiveId==candidate.paths[index].objectiveId,tag+" retains path/objective identity")
		check(source.paths[index].points.size()==candidate.paths[index].points.size(),tag+" retains segment indices")
	for post in original.posts:
		var found: bool=false
		for other in actual.posts:
			if post.id==other.id:
				found=true
				check(rotate(post.position,turns).distance_to(other.position)<.000003,tag+" actual derived ground-post coordinate rotates with its route")
		check(found,tag+" retains every authored post")
	check(original.bases.size()==actual.bases.size(),tag+" retains actual legal march-base count")
	for base in original.bases:
		var found: bool=false
		for other in actual.bases:
			if base.pathIndex==other.pathIndex:
				found=true
				check(rotate(base.position,turns).distance_to(other.position)<.000003,tag+" actual march spawn follows the objective route")
				check(absf(float(base.baseDistance)-float(other.baseDistance))<.000003 and absf(float(base.routeMin)-float(other.routeMin))<.000003 and absf(float(base.routeMax)-float(other.routeMax))<.000003,tag+" keeps actual land-only marching bounds")
		check(found,tag+" retains each march-base identity")
	check(original.water.size()==actual.water.size(),tag+" retains collision water count")
	for x in range(1,20):
		for y in range(1,20):
			var p: Vector2=Vector2(float(x)/20,float(y)/20)
			var before: bool=false
			var after: bool=false
			for region in original.water: before=before or region.has_point(p)
			for region in actual.water: after=after or region.has_point(rotate(p,turns))
			# Rect2 is half-open; compare only points farther than float epsilon
			# from its boundaries so float32 rounding does not mislabel an edge.
			var boundary: bool=false
			for region in original.water:
				if absf(p.x-region.position.x)<.00001 or absf(p.x-region.end.x)<.00001 or absf(p.y-region.position.y)<.00001 or absf(p.y-region.end.y)<.00001: boundary=true
			if not boundary: check(before==after,tag+" water interior/exterior membership rotates exactly")
	if int(original.ambushSiteCount)!=int(actual.ambushSiteCount):
		observations.append({"stageId":source.id,"clockwiseDegrees":turns*90,"kind":"generated_ambush_count_differs","before":original.ambushSiteCount,"after":actual.ambushSiteCount,"causeToInspect":"Asymmetric normalized placement margins (.04/.96 x, .06/.94 y); generated sites are derived and must be re-exported, not rotated as cached guide metadata."})

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().trim_suffix("/")
	check(profile.to_lower().begins_with(PROFILE_PREFIX.to_lower()) and OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().trim_suffix("/").to_lower()==profile.to_lower(),"CPU verifier has a private workspace profile")
	if not failures.is_empty(): quit(2);return
	map_sha=FileAccess.get_sha256("res://native/maps.json")
	var stages: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var original_game: Node2D=Game.new()
	var rotated_game: Node2D=Game.new()
	root.add_child(original_game)
	root.add_child(rotated_game)
	original_game.set_process(false)
	rotated_game.set_process(false)
	var rows: Array=[]
	for stage in stages:
		var source_hash: String=JSON.stringify(stage).sha256_text()
		original_game.load_map(stage)
		var before: Dictionary=captures(original_game)
		var bases: Array=[]
		for base in before.bases: bases.append({"pathIndex":base.pathIndex,"position":{"x":base.position.x,"y":base.position.y}})
		rows.append({"stageId":stage.id,"stageNumber":stage.stageNumber,"actualMarchBases":bases,"actualAmbushSiteCount":before.ambushSiteCount})
		for turns in [1,2,3]:
			var candidate: Dictionary=rotated_data(stage,"",turns)
			rotated_game.load_map(candidate)
			geometry_checks(stage,candidate,before,captures(rotated_game),turns)
		check(JSON.stringify(stage).sha256_text()==source_hash,"Inspection never mutates caller map "+str(stage.id))
	check(FileAccess.get_sha256("res://native/maps.json")==map_sha,"Production maps source remains unchanged")
	original_game.free()
	rotated_game.free()
	var result: Dictionary={"scope":"Read-only in-memory quarter-turn feasibility; no route reconstruction or visual-quality claim","sourceMapsSha256":map_sha,"checks":checks,"failures":failures,"stageCount":stages.size(),"rotatedRuntimeLoads":stages.size()*3,"rows":rows,"observations":observations,"canonicalProductionWritten":false}
	var file: FileAccess=FileAccess.open("user://qa_lower_layout_design.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("LOWER_LAYOUT_DESIGN ",checks," checks, ",failures.size()," failures, ",observations.size()," observations; report ",ProjectSettings.globalize_path("user://qa_lower_layout_design.json"))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
