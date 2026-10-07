extends SceneTree
## Verifies road-derived deployment geometry, not photographed terrain depth.
var checks: int = 0
var failures: Array = []
var post_count: int = 0
var minimum_y: float = 1.0
var maximum_y: float = 0.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("TACTICS DATA QA "+message)

func point(value: Dictionary) -> Vector2:
	return Vector2(float(value.x),float(value.y))

func anchor(map: Dictionary, post: Dictionary) -> Vector2:
	var points: Array = map.paths[int(post.pathIndex)].points
	return point(points[int(post.segmentIndex)]).lerp(point(points[int(post.segmentIndex)+1]),float(post.t))

func segment_clip(a: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var delta: Vector2 = b-a
	var lower: float = 0.0
	var upper: float = 1.0
	for pair in [Vector2(-delta.x,a.x-rect.position.x),Vector2(delta.x,rect.end.x-a.x),Vector2(-delta.y,a.y-rect.position.y),Vector2(delta.y,rect.end.y-a.y)]:
		if absf(pair.x)<0.000001:
			if pair.y<0: return Vector2(-1,-1)
		elif pair.x<0:
			lower = maxf(lower,pair.y/pair.x)
		else:
			upper = minf(upper,pair.y/pair.x)
		if lower>upper: return Vector2(-1,-1)
	return Vector2(lower,upper)

func river_exit_distance(map: Dictionary, path_index: int) -> float:
	var points: Array = map.paths[path_index].points
	var travel: float = 0.0
	var last_exit: float = -1.0
	for segment in range(points.size()-1):
		var a: Vector2 = point(points[segment])
		var b: Vector2 = point(points[segment+1])
		var length: float = a.distance_to(b)
		for bridge in map.get("bridges",[]):
			var rect := Rect2(float(bridge.x),float(bridge.y),float(bridge.w),float(bridge.h))
			var clip: Vector2 = segment_clip(a,b,rect)
			if clip.x>=0 and clip.y-clip.x>0.0001:
				last_exit=maxf(last_exit,travel+length*clip.y)
		travel+=length
	return last_exit

func post_distance(map: Dictionary, post: Dictionary) -> float:
	var points: Array = map.paths[int(post.pathIndex)].points
	var distance: float = 0.0
	for segment in range(int(post.segmentIndex)):
		distance+=point(points[segment]).distance_to(point(points[segment+1]))
	distance+=point(points[int(post.segmentIndex)]).distance_to(point(points[int(post.segmentIndex)+1]))*float(post.t)
	return distance

func run() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var plans: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	check(maps.size()==40,"forty actual maps")
	var ids: Dictionary = {}
	var titles: Dictionary = {}
	var formations: Dictionary = {}
	for map in maps:
		var mid: String = map.id
		var tactics: Dictionary = map.get("tactics",{})
		check(not tactics.is_empty(),mid+" tactical record")
		check(not titles.has(tactics.get("nameKo","")),mid+" distinct tactical operation")
		titles[tactics.get("nameKo","")] = true
		for key in ["nameKo","descriptionKo","hintKo"]:
			check(not String(tactics.get(key,"")).is_empty(),mid+" "+key)
		check(String(tactics.get("descriptionKo","")).length()<=62,mid+" concise tactical description")
		var posts: Array = tactics.get("groundPosts",[])
		check(posts.size()>=2 and posts.size()<=4,mid+" two to four ground positions")
		var routes: Dictionary = {}
		var formation: Array = []
		for post in posts:
			check(not ids.has(post.id),mid+" unique ground identity")
			ids[post.id] = true
			check(String(post.nameKo).length()<=10,mid+" short post name")
			var route: int = int(post.pathIndex)
			var segment: int = int(post.segmentIndex)
			check(route>=0 and route<map.paths.size(),mid+" actual route")
			check(segment>=0 and segment<map.paths[route].points.size()-1,mid+" actual road segment")
			check(float(post.t)>=0 and float(post.t)<=1,mid+" segment interpolation")
			routes[route] = true
			var center: Vector2 = anchor(map,post)
			minimum_y=minf(minimum_y,center.y)
			maximum_y=maxf(maximum_y,center.y)
			formation.append({"x":center.x,"y":center.y})
			var radius: float = float(post.r)
			check(center.x-radius>=0.025 and center.x+radius<=0.975 and center.y-radius>=0.04 and center.y+radius<=0.96,mid+" complete placement circle inside field")
			check(center.y>=0.105 and center.y<=0.895,mid+" clickable center avoids compact HUD and footer")
			check(radius>=0.035 and radius<=0.075 and float(post.guardRadius)>=0.10 and float(post.guardRadius)<=0.18,mid+" bounded deployment and guard radius")
			check(float(post.mobilityFactor)>=0.5 and float(post.mobilityFactor)<=1.25 and int(post.capacityBonus)>=0 and int(post.capacityBonus)<=2,mid+" bounded terrain movement and finite capacity")
			for obstacle in map.get("obstacles",[]):
				if obstacle.get("blockPlacement",false):
					check(center.distance_to(point(obstacle))>=radius+float(obstacle.r),mid+" blocked terrain clearance")
			if map.theme=="harbor":
				check(segment>=int(map.landingIndex),mid+" post after disembarkation")
				var water := Rect2(float(map.water.x),float(map.water.y),float(map.water.w),float(map.water.h))
				check(not water.has_point(center),mid+" post center on land")
			if map.theme=="river":
				var exit: float = river_exit_distance(map,route)
				check(exit>=0 and post_distance(map,post)>exit+0.01,mid+" post beyond actual bridge exit")
			if map.theme=="convoy":
				check(segment<map.paths[route].points.size()-2,mid+" fixed road before moving cart's final target")
			post_count+=1
		check(routes.size()==map.paths.size(),mid+" every actual enemy route has a defense post")
		for i in posts.size():
			for j in range(i+1,posts.size()):
				check(anchor(map,posts[i]).distance_to(anchor(map,posts[j]))>float(posts[i].r)+float(posts[j].r),mid+" distinct post circles")
		var identity: String = JSON.stringify(formation)
		check(not formations.has(identity),mid+" frontage is not a copied formation")
		formations[identity] = true
		for mission in plans.stages[mid].missions:
			for target in mission.targets:
				check(map.buildZones.any(func(zone): return point(zone).distance_to(point(target.position))<0.000001),mid+" original learning support anchor retained")
		if mid=="basic-forest":
			check(posts.size()==4 and posts.all(func(post): return float(post.r)>=0.07),"first forest allows six ground classes across four broad posts")
	check(post_count==120,"120 authored road posts")
	var result: Dictionary = {"checks":checks,"failures":failures,"maps":maps.size(),"groundPosts":post_count,"minimumCenterY":minimum_y,"maximumCenterY":maximum_y,"resourceRoot":ProjectSettings.globalize_path("res://"),"limits":"Data geometry only; engine class placement, retreat, collision and cavalry movement are separate integration checks."}
	var file: FileAccess = FileAccess.open("user://qa_tactics_data.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"\t"));file.close()
	print("TACTICS_DATA_QA "+JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
