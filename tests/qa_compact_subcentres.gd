extends SceneTree
const Game = preload("res://native/game.gd")
var PROFILE: String = qa_project_path("tests/profiles/compact-placement/")
var game: Node2D
var additions: Array = []
var failures: Array = []
var radius_additions: Array = []

func _initialize() -> void: call_deferred("run")

func capacity(stage: Dictionary,type_name: String) -> int:
	game.load_map(stage)
	game.gold=20000
	for index in range(int(stage.unitLimit)):
		if not game.begin_placement(type_name): break
		var chosen: Vector2=Vector2(-1,-1)
		for zone in game.zones:
			var hint: Vector2=game._zone_placement_hint(zone,type_name)
			if hint.x>=0 and bool(game.placement_preview(hint).valid): chosen=hint;break
		if chosen.x<0: game.cancel_recruit();break
		if not game.place_unit(chosen.x,chosen.y): break
		game._advance_recruitment(100)
		if game.units.size()!=index+1: break
	return game.units.size()

func post_position(stage: Dictionary,post: Dictionary) -> Vector2:
	var points: Array=stage.paths[int(post.pathIndex)].points
	var index: int=int(post.segmentIndex)
	return Vector2(float(points[index].x),float(points[index].y)).lerp(Vector2(float(points[index+1].x),float(points[index+1].y)),float(post.t))

func projected_post(stage: Dictionary,source: Dictionary,point: Vector2,serial: int) -> Dictionary:
	var post: Dictionary=source.duplicate(true)
	var points: Array=stage.paths[int(post.pathIndex)].points
	var nearest: float=INF
	for index in range(points.size()-1):
		var a: Vector2=Vector2(float(points[index].x),float(points[index].y))
		var b: Vector2=Vector2(float(points[index+1].x),float(points[index+1].y))
		var t: float=clampf((point-a).dot(b-a)/maxf((b-a).length_squared(),.000000001),0,1)
		var distance: float=point.distance_to(a.lerp(b,t))
		if distance<nearest:
			nearest=distance
			post.segmentIndex=index
			post.t=t
	post.id=str(stage.id)+"-ground-capacity-"+str(serial)
	post.nameKo="예비 접전 진지 " + str(serial)
	post.r=.018
	return post

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(PROFILE.to_lower()) or OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower()!=profile: quit(2);return
	var source_sha: String=FileAccess.get_sha256("res://native/maps.json")
	var stages: Array=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"maps-pocket-capacity-draft.json"))
	var originals: Array=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"maps-pocket-before.json"))
	var before: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"baseline/capacity.json"))
	var search: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"capacity-restore-progress.json"))
	game=Game.new();root.add_child(game);game.set_process(false);game.three_d_enabled=true
	game.configure_roster(JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units,["archer","spear","samurai","gunner","naginata","monk","commander","ninja"],{})
	for missing in search.failures:
		var stage_index: int=-1
		for index in range(stages.size()):
			if str(stages[index].id)==str(missing.stageId): stage_index=index;break
		var stage: Dictionary=stages[stage_index]
		var old: Dictionary=originals[stage_index]
		var type_name: String=str(missing.type)
		var target: int=int(missing.target)
		var count: int=capacity(stage,type_name)
		# The first pass deliberately omitted lower-centre posts. Their raw
		# before geometry is already frame-safe, so retain one when needed.
		if type_name=="gunner":
			for post in stage.tactics.groundPosts:
				var centre: Vector2=post_position(stage,post)
				if centre.y<=.85 or centre.y>=.9: continue
				var source_post: Dictionary={}
				for old_post in old.tactics.groundPosts:
					if str(old_post.id)==str(post.id): source_post=old_post;break
				if source_post.is_empty(): continue
				var old_radius: float=float(post.r)
				post.r=minf(.055,float(source_post.r))
				var trial: int=capacity(stage,type_name)
				if trial<=count: post.r=old_radius;continue
				radius_additions.append({"stageId":stage.id,"role":"ground","id":post.id,"radius":post.r,"capacityBeforeException":count,"capacityAfterException":trial})
				count=trial
				if count>=target: break
		var observation: Dictionary={}
		for row in before.rows[stage_index].homogeneousPublicCapacity:
			if str(row.unitType)==type_name: observation=row;break
		if type_name!="gunner": failures.append(missing);continue
		for point_index in range(observation.positions.size()):
			if count>=target: break
			var point: Vector2=Vector2(float(observation.positions[point_index].x),float(observation.positions[point_index].y))
			if point.x<.12 or point.x>.87 or point.y<.20 or point.y>.85: continue
			var host: Dictionary={}
			for post in old.tactics.groundPosts:
				if str(post.id)==str(observation.postIds[point_index]): host=post;break
			if host.is_empty() or point.distance_to(post_position(old,host))>float(host.r)+.00001: continue
			var host_center: Vector2=post_position(old,host)
			var delta: Vector2=point-host_center
			# Partition the old circle with a usable small circle, retaining its
			# old outer legal point as an edge candidate instead of enlarging it.
			var compact_center: Vector2=host_center+delta.normalized()*minf(delta.length(),maxf(0,float(host.r)-.019))
			var post: Dictionary=projected_post(stage,host,compact_center,additions.size()+1)
			# A small authored centre may only partition an already legal source pocket.
			if post_position(stage,post).distance_to(post_position(old,host))>float(host.r)-.018+.00001: continue
			stage.tactics.groundPosts.insert(0,post)
			var trial: int=capacity(stage,type_name)
			if trial<=count: stage.tactics.groundPosts.remove_at(0);continue
			additions.append({"stageId":stage.id,"role":"ground","sourcePostId":host.id,"zone":post,"insertionIndex":0,"before":count,"after":trial})
			count=trial
			if count>=target: break
		if count<target: failures.append({"stageId":stage.id,"type":type_name,"actual":count,"target":target})
		print("SUBCENTRES ",stage.id," ",count," / ",target)
	game.free()
	var out: FileAccess=FileAccess.open(PROFILE+"additional-centres.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(additions,"\t"));out.close()
	var radii: Array=JSON.parse_string(FileAccess.get_file_as_string(PROFILE+"radius-exceptions.json"))
	for item in radius_additions: radii.append(item)
	var radius_out: FileAccess=FileAccess.open(PROFILE+"radius-exceptions.json",FileAccess.WRITE)
	radius_out.store_string(JSON.stringify(radii,"\t"));radius_out.close()
	var report: FileAccess=FileAccess.open(PROFILE+"subcentre-proof.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures,"additions":additions,"radiusAdditions":radius_additions,"productionUnchanged":FileAccess.get_sha256("res://native/maps.json")==source_sha},"\t"));report.close()
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
