extends SceneTree
const Game = preload("res://native/game.gd")
const PROFILE: String = "C:/JP_DF/tests/profiles/compact-placement/"
var game: Node2D
var changes: Array = []
var rows: Array = []
var failures: Array = []

func _initialize() -> void: call_deferred("run")

func capacity(stage: Dictionary,type_name: String) -> int:
	game.load_map(stage)
	game.gold=20000
	for index in range(int(stage.unitLimit)):
		if not game.begin_placement(type_name): break
		var choice: Vector2=Vector2(-1,-1)
		for zone in game.zones:
			var hint: Vector2=game._zone_placement_hint(zone,type_name)
			if hint.x>=0 and bool(game.placement_preview(hint).valid): choice=hint;break
		if choice.x<0: game.cancel_recruit();break
		if not game.place_unit(choice.x,choice.y): break
		game._advance_recruitment(100)
		if game.units.size()!=index+1: break
	return game.units.size()

func zone_position(stage: Dictionary,zone: Dictionary,role: String) -> Vector2:
	if role=="ranged": return Vector2(float(zone.x),float(zone.y))
	var points: Array=stage.paths[int(zone.pathIndex)].points
	return Vector2(float(points[int(zone.segmentIndex)].x),float(points[int(zone.segmentIndex)].y)).lerp(Vector2(float(points[int(zone.segmentIndex)+1].x),float(points[int(zone.segmentIndex)+1].y)),float(zone.t))

func candidates(stage: Dictionary,baseline: Dictionary,role: String,review: Dictionary) -> Array:
	var group: Array=stage.buildZones if role=="ranged" else stage.tactics.groundPosts
	var old_group: Array=baseline.buildZones if role=="ranged" else baseline.tactics.groundPosts
	var result: Array=[]
	for index in range(group.size()):
		var zone: Dictionary=group[index]
		var old: Dictionary=old_group[index]
		var radius: float=minf(.055,float(old.r))
		if radius<=float(zone.r)+.00001: continue
		var position: Vector2=zone_position(stage,zone,role)
		# These interior bounds also protect the older, larger raw-model edge
		# observations. Small unsafe top/side pockets are never expanded.
		if position.x<.12 or position.x>.87 or position.y<.235 or position.y>.85: continue
		var label: String=("B" if role=="ranged" else "S")+str(index+1)
		var clipped: bool=false
		for item in review.get("clippedLegalPockets",[]):
			if str(item.label)==label: clipped=true;break
		if clipped: continue
		var penalty: float=0
		for item in review.get("gateBodyPatchConflicts",[]):
			if str(item.placement)==label: penalty+=10 if bool(item.centreBodyOverlap) else 2
		for item in review.get("physicalFloorConflicts",[]):
			if str(item.label)==label: penalty+=1
		result.append({"zone":zone,"radius":radius,"score":penalty+position.distance_to(Vector2(.5,.5)),"label":label})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return float(a.score)<float(b.score))
	return result

func run() -> void:
	var private: String=OS.get_environment("APPDATA").replace("\\","/")
	if not private.begins_with(PROFILE) or OS.get_environment("LOCALAPPDATA").replace("\\","/")!=private: quit(2);return
	var source_sha: String=FileAccess.get_sha256("res://native/maps.json")
	var stages: Array=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"maps-pocket-draft.json"))
	var originals: Array=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"maps-pocket-before.json"))
	var before: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"baseline/capacity.json"))
	var geometry: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/profiles/map-render-blueprints/guided-lower-v4-20261007-cpu/guide_geometry_review.json"))
	game=Game.new();root.add_child(game);game.set_process(false);game.three_d_enabled=true
	game.configure_roster(JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units,["archer","spear","samurai","gunner","naginata","monk","commander","ninja"],{})
	for index in range(stages.size()):
		var stage: Dictionary=stages[index]
		for type_name in ["archer","gunner"]:
			var target: int=0
			for item in before.rows[index].homogeneousPublicCapacity:
				if str(item.unitType)==type_name: target=int(item.count)
			var count: int=capacity(stage,type_name)
			var initial: int=count
			var role: String="ranged" if type_name=="archer" else "ground"
			if count<target:
				for candidate in candidates(stage,originals[index],role,geometry.stages[index]):
					var zone: Dictionary=candidate.zone
					var old_radius: float=float(zone.r)
					zone.r=float(candidate.radius)
					var trial: int=capacity(stage,type_name)
					if trial<=count: zone.r=old_radius;continue
					changes.append({"stageId":stage.id,"role":role,"id":zone.id,"radius":zone.r,"label":candidate.label,"capacityBeforeException":count,"capacityAfterException":trial})
					count=trial
					if count>=target: break
			if count<target: failures.append({"stageId":stage.id,"type":type_name,"target":target,"actual":count})
			rows.append({"stageId":stage.id,"type":type_name,"baseline":target,"compact":initial,"restored":count})
		var output: FileAccess=FileAccess.open(PROFILE+"capacity-restore-progress.json",FileAccess.WRITE)
		output.store_string(JSON.stringify({"stagesCompleted":index+1,"radiusExceptions":changes,"failures":failures,"rows":rows},"\t"));output.close()
		print("CAPACITY_RESTORE stage ",int(stage.stageNumber)," complete; exceptions ",changes.size()," unresolved ",failures.size())
	game.free()
	var draft: FileAccess=FileAccess.open(PROFILE+"maps-pocket-capacity-draft.json",FileAccess.WRITE)
	draft.store_string(JSON.stringify(stages,"\t"));draft.close()
	var overrides: FileAccess=FileAccess.open(PROFILE+"radius-exceptions.json",FileAccess.WRITE)
	overrides.store_string(JSON.stringify(changes,"\t"));overrides.close()
	if FileAccess.get_sha256("res://native/maps.json")!=source_sha: failures.append("Production map changed during private search")
	print("CAPACITY_RESTORE final ",failures.size()," unresolved, ",changes.size()," exceptions")
	quit(0 if failures.is_empty() else 1)
