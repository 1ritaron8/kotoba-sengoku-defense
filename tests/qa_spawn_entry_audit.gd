extends SceneTree
## CPU read-only audit. Coordinates link to the separate DISPLAY GPU layout
## captures; passing land checks does not prove painted trees/gates are open.
const Game = preload("res://native/game.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
const SIZE: Vector2 = Vector2(1280,720)
const PROFILE_ROOT: String = "c:/jp_df/tests/profiles/spawn-entry-audit/"
const LAYOUT_MANIFEST: String = "C:/JP_DF/tests/profiles/native-battlefield-hybrid-campaign-layouts-final-gpu/AppData/Godot/app_userdata/말의 전장/campaign-layouts/manifest.json"
var checks: int = 0
var failures: Array = []
var stages: Array = []
var game: Node2D
var art_by_stage: Dictionary = {}
var spawn_count: int = 0
var side_count: int = 0
var path_count: int = 0
var blocked_count: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures.append(note)
		if failures.size() <= 20: push_error("SPAWN_ENTRY " + note)

func coordinates(value: Vector2) -> Dictionary:
	return {"x":value.x,"y":value.y}

func normalized_path(value: String) -> String:
	return value.replace("\\","/").simplify_path().to_lower().trim_suffix("/")

func safe_environment() -> bool:
	var appdata: String = normalized_path(OS.get_environment("APPDATA"))
	var localdata: String = normalized_path(OS.get_environment("LOCALAPPDATA"))
	var user_path: String = normalized_path(ProjectSettings.globalize_path("user://"))
	check(DisplayServer.get_name() == "headless","Audit uses only the headless CPU display")
	check(appdata.begins_with(PROFILE_ROOT) and appdata == localdata and user_path.begins_with(appdata+"/"),"APPDATA, LOCALAPPDATA and actual user:// are the same isolated workspace profile")
	return failures.is_empty()

func point_record(value: Vector2) -> Dictionary:
	var blocked: bool = not game.ground_combat.land_segment_safe(value,value,0)
	var scenic: Array = []
	for landmark in game.config.get("historicalBattlefield",{}).get("sceneLandmarks",[]):
		var scale_data: Dictionary = landmark.get("scale",{})
		var extent: Vector2 = Vector2(float(scale_data.get("w",0)),float(scale_data.get("h",0)))
		if extent.x <= 0 or extent.y <= 0: continue
		var bounds: Rect2 = Rect2(Presentation.point(landmark)-extent*.5,extent)
		if bounds.has_point(value):
			scenic.append({"id":landmark.get("id",""),"kind":landmark.get("kind",""),"labelKo":landmark.get("labelKo",""),"approximateBoundsOnly":true})
	var obstacles: Array = []
	var nearest_clearance: float = INF
	for obstacle in game.config.get("obstacles",[]):
		if not bool(obstacle.get("blockPlacement",false)): continue
		var clearance: float = value.distance_to(Presentation.point(obstacle))-float(obstacle.get("r",0))
		nearest_clearance = minf(nearest_clearance,clearance)
		if clearance <= 0: obstacles.append(str(obstacle.get("landmark","unnamed")))
	return {"canonical":coordinates(value),"displayed":coordinates(game.view_point(value)),"expectedCanonicalPixel":coordinates(value*SIZE),"expectedDisplayedPixel":coordinates(game.view_point(value)*SIZE),"blockedByActualLandProvider":blocked,"blockingObstacleIds":obstacles,"nearestBlockingObstacleClearance":nearest_clearance if is_finite(nearest_clearance) else null,"scenicBoundsHints":scenic}

func safe_point(value: Vector2, note: String) -> void:
	var legal: bool = game.ground_combat.land_segment_safe(value,value,0)
	if not legal: blocked_count += 1
	check(value.is_finite() and value.x >= 0 and value.x <= 1 and value.y >= 0 and value.y <= 1,note+": coordinate is finite and inside the map")
	check(legal,note+": real spawn/route anchor is not in blocked water or an actual obstacle")

func audit_routes() -> Array:
	var result: Array = []
	var common: Vector2 = Presentation.point(game.config.get("commonEnemyEntry",{}))
	var branch: Vector2 = Presentation.point(game.config.get("commonEnemyEntry",{}).get("branchPoint",{}))
	var route_shapes: Dictionary = {}
	for path_index in range(game.paths.size()):
		var route: Dictionary = game.paths[path_index]
		var note: String = "%02d %s path%d" % [int(game.config.stageNumber),str(game.config.id),path_index]
		path_count += 1
		check(route.points.size() >= 3,note+": route has a shared entry, branch and connected downstream geometry")
		if route.points.size() < 3: continue
		check(Vector2(route.points[0]).distance_to(common) < .00001 and Vector2(route.points[1]).distance_to(branch) < .00001,note+": exact common entry and branch are connected to this route")
		var nodes: Array = []
		var legal_segments: bool = true
		for index in range(route.points.size()):
			var value: Vector2 = route.points[index]
			safe_point(value,note+" node"+str(index))
			nodes.append(point_record(value))
			if index == 0: continue
			var previous: Vector2 = route.points[index-1]
			var safe: bool = game.ground_combat.land_segment_safe(previous,value,0)
			check(previous.distance_to(value) > .00001 and safe,note+" segment"+str(index-1)+": nonzero continuous centerline stays on actual traversable land")
			legal_segments = legal_segments and safe
		var shape: String = JSON.stringify(route.points).sha256_text()
		check(not route_shapes.has(shape),note+": downstream branch is a distinct geometric route")
		route_shapes[shape] = true
		var spawns: Array = []
		for lane in [-2,-1,0,1,2]:
			game.enemies.clear()
			var enemy: Dictionary = game._spawn_enemy("raider",2,{"pathIndex":path_index,"formationLane":lane})
			spawn_count += 1
			check(int(enemy.pathIndex) == path_index and int(enemy.spawnPathIndex) == path_index and str(enemy.combatRole) == game.ENEMY_PATH_ROLE,note+": native spawn keeps its requested branch and route role")
			check(enemy.position.distance_to(common) <= .01801,note+": actual formation spawn is at the original entry with only its native lane offset")
			safe_point(enemy.position,note+" spawn lane"+str(lane))
			var record: Dictionary = {"formationLane":lane,"actualBirth":point_record(enemy.position),"nativeBranchLanePoint":point_record(game._enemy_lane_point(enemy,1))}
			if lane == 0:
				var previous: Vector2 = enemy.position
				var maximum_step: float = 0.0
				var target_distance: float = float(game.ground_combat.cumulative[path_index][1])+.015
				var samples: int = 0
				for frame in range(1200):
					if game.ground_combat.enemy_distance(enemy) >= target_distance: break
					game._move_enemy(enemy,.025)
					check(game.ground_combat.land_segment_safe(previous,enemy.position,0),note+": real walking from the spawn through the junction stays on land")
					maximum_step = maxf(maximum_step,previous.distance_to(enemy.position))
					previous = enemy.position
					samples += 1
				check(game.ground_combat.enemy_distance(enemy) >= target_distance and maximum_step < .01,note+": actual walker crosses the branch continuously, without appearing past it")
				record.merge({"branchCrossed":true,"steps":samples,"maximumActualStep":maximum_step,"afterBranch":point_record(enemy.position)},true)
			spawns.append(record)
		result.append({"pathIndex":path_index,"pathId":route.get("id",""),"objectiveId":route.get("objectiveId",""),"allCenterlineSegmentsLandSafe":legal_segments,"nodes":nodes,"formationSpawns":spawns})
	return result

func audit_sides(guard_unlocked: bool) -> Array:
	var result: Array = []
	for authored in game.config.get("sideAmbushEntrances",[]):
		var path_index: int = int(authored.get("pathIndex",-1))
		var note: String = str(game.config.id)+" "+str(authored.get("id",""))
		var points: Array = [Presentation.point(authored.get("point",{}))]
		for value in authored.get("connectionPoints",[]):
			var next: Vector2 = Presentation.point(value)
			if points[-1].distance_to(next) > .00001: points.append(next)
		check(path_index >= 0 and path_index < game.paths.size() and points.size() >= 2,note+": authored side owns a valid joined branch")
		if path_index < 0 or path_index >= game.paths.size() or points.size() < 2: continue
		var geometry: Array = []
		for index in range(points.size()):
			var value: Vector2 = points[index]
			safe_point(value,note+" point"+str(index))
			geometry.append(point_record(value))
			if index > 0: check(game.ground_combat.land_segment_safe(points[index-1],value,.002),note+": authored walking side ingress avoids real water and obstacles")
		var prepared: Dictionary = game._prepared_ambush_entry(path_index)
		check(not prepared.is_empty() and str(prepared.get("id","")) == str(authored.id),note+": actual runtime accepts this exact side ingress rather than a silent missing-entry fallback")
		if prepared.is_empty(): continue
		var join: Vector2 = game.ground_combat.route_point(path_index,float(prepared.joinDistance))
		check(Vector2(points[-1]).distance_to(join) <= .00401,note+": ingress endpoint really connects to the owning route")
		game.enemies.clear();game.ambush_warnings.clear()
		game._queue_enemy_spawn("enemy_archer",2,{"pathIndex":path_index,"originKind":"raider"})
		check(game.ambush_warnings.size() == (1 if guard_unlocked else 0),note+": actual roster controls the two-second side-entry warning")
		game._advance_ambush_warnings(2.01)
		check(game.enemies.size() == 1,note+": native queued warning resolves to exactly one enemy")
		if game.enemies.size() != 1: continue
		var enemy: Dictionary = game.enemies[0]
		side_count += 1
		safe_point(enemy.position,note+" actual queued birth")
		check(int(enemy.pathIndex) == path_index and (bool(enemy.get("ingressActive",false)) == guard_unlocked),note+": actual spawned route/ingress matches the guard unlock")
		check(enemy.position.distance_to(points[0] if guard_unlocked else game.paths[path_index].points[0]) < .00001,note+": actual queued enemy appears at its authored side or protected common entry")
		result.append({"id":authored.id,"pathIndex":path_index,"guardUnlocked":guard_unlocked,"warningSeconds":2.0 if guard_unlocked else 0.0,"authoredCoordinates":geometry,"joinedRoutePoint":point_record(join),"actualQueuedKind":enemy.kind,"actualQueuedRole":enemy.combatRole,"actualQueuedSpawn":point_record(enemy.position)})
	return result

func run() -> void:
	if not safe_environment(): quit(2);return
	var source_raw: String = FileAccess.get_file_as_string("res://native/maps.json")
	var maps: Array = JSON.parse_string(source_raw)
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var art_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefields-rendered/manifest.json"))
	var art_manifest_hash: String = FileAccess.get_sha256("res://assets/battlefields-rendered/manifest.json")
	for entry in art_manifest.stages: art_by_stage[str(entry.stageId)] = entry
	check(maps.size() == 40 and art_by_stage.size() == 40 and bool(art_manifest.complete),"The audit is linked to all forty approved runtime artwork entries")
	check(str(art_manifest.sourceMapsSha256) == source_raw.sha256_text(),"Artwork and audited gameplay coordinates share the actual frozen map SHA")
	maps.sort_custom(func(a,b): return int(a.stageNumber) < int(b.stageNumber))
	game = Game.new();game.three_d_enabled = true
	root.add_child(game);game.set_process(false);game.set_input_enabled(false)
	for config in maps:
		var unlocked: Array = []
		for definition in catalog:
			if int(definition.unlockClears) <= int(config.stageNumber)-1: unlocked.append(str(definition.id))
		game.configure_roster(catalog,unlocked,{})
		game.set_seed(20261007);game.load_map(config,10)
		var guard_unlocked: bool = not game.emplacement_protection_active()
		var routes: Array = audit_routes()
		var sides: Array = audit_sides(guard_unlocked)
		check(game.config == config,"Audit never changes the authored stage dictionary: "+str(config.id))
		var art: Dictionary = art_by_stage.get(str(config.id),{})
		var capture_name: String = "stage-%02d-%s-layout.png" % [int(config.stageNumber),str(config.id)]
		stages.append({"stageNumber":int(config.stageNumber),"stageId":config.id,"title":config.get("title",""),"mirroredForDisplay":game.presentation_mirrored,"guardUnlocked":guard_unlocked,"commonEntry":point_record(Presentation.point(config.commonEnemyEntry)),"branch":point_record(Presentation.point(config.commonEnemyEntry.branchPoint)),"routes":routes,"sides":sides,"artPath":art.get("path",""),"artSha256":art.get("sha256",""),"layoutCaptureExpectedPath":LAYOUT_MANIFEST.get_base_dir().path_join(capture_name),"layoutCaptureLinked":false})
	game.free()
	check(FileAccess.get_file_as_string("res://native/maps.json") == source_raw,"All original paths, navigation and stage bytes remain unchanged")
	check(FileAccess.get_sha256("res://assets/battlefields-rendered/manifest.json") == art_manifest_hash,"Artwork registration remained frozen during the CPU audit")
	var report: Dictionary = {"checks":checks,"failures":failures,"stageCount":stages.size(),"pathCount":path_count,"formationSpawnCount":spawn_count,"queuedSideOrProtectedSpawnCount":side_count,"blockedAnchorCount":blocked_count,"mapsSha256":source_raw.sha256_text(),"artManifestSha256":art_manifest_hash,"gameSha256":FileAccess.get_sha256("res://native/game.gd"),"presentationSha256":FileAccess.get_sha256("res://native/battlefield_presentation.gd"),"layoutManifestExpectedPath":LAYOUT_MANIFEST,"layoutEvidenceLinked":false,"coordinateReference":{"width":SIZE.x,"height":SIZE.y,"nativeLayoutCaptureSpace":"displayed","authoredSpace":"canonical"},"stages":stages,"scopeKo":"원본 40맵의 공통 시작점·분기·전 구간 중심선, 실제 형성 5열 출격 좌표, 실제 잠금 조건의 측면 경고/출격 좌표를 CPU로 관찰했습니다. map/nav/production 수정은 없습니다. sceneLandmarks의 사각 범위는 그림 검토용 힌트이며 물리 충돌체로 판정하지 않습니다. 숲·성문 등 그림이 길을 가리는지 여부는 별도 최종 DISPLAY GPU 지도 캡처의 수동 검수가 필요하며, 이 보고서는 자연 플레이 완주 또는 미술 검수 통과를 주장하지 않습니다."}
	var file: FileAccess = FileAccess.open("user://spawn_entry_audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("SPAWN_ENTRY_AUDIT checks=%d failures=%d stages=%d paths=%d formationSpawns=%d queuedSpawns=%d blocked=%d report=%s" % [checks,failures.size(),stages.size(),path_count,spawn_count,side_count,blocked_count,ProjectSettings.globalize_path("user://spawn_entry_audit.json")])
	quit(0 if failures.is_empty() else 1)
