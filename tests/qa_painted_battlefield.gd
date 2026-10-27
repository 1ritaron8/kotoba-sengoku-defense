extends SceneTree
## Focused geometry/placement checks for the newly painted first battlefield.
## HQ executes this; it writes no saves and launches no secondary engine.
const Painted = preload("res://native/painted_battlefield.gd")
const Stage = preload("res://native/painted_stage.gd")
const Battle = preload("res://native/game.gd")
var checks: int = 0
var failures: Array[String] = []
var evidence: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		push_error("PAINTED_BATTLEFIELD " + note)

func point(data: Dictionary) -> Vector2:
	return Vector2(float(data.x),float(data.y))

func stage_checks(original: Dictionary, stage: Dictionary) -> void:
	check(bool(stage.get("paintedPresentation",false)),"The new map declares its 2D presentation explicitly")
	check(not stage.has("worldGeometry") and not stage.has("visualComposition"),"Retired 3D terrain and placement geometry cannot leak into this map")
	for key in ["id","stageNumber","tier","level","difficulty","initialGold","totalWaves","trait","music","mode"]:
		check(stage.get(key) == original.get(key),"Presentation retains campaign/combat field " + key)
	check(stage.paths.size() == 1 and stage.paths[0].points.size() == 2,"One straight authored approach replaces the bent old route")
	check(point(stage.paths[0].points[0]).is_equal_approx(Stage.INGRESS) and Stage.INGRESS.x > 1.0 and Stage.INGRESS.y < 0.0,"The actual route starts beyond the upper-right frame")
	check(point(stage.paths[0].points[-1]).is_equal_approx(Stage.GATE),"Route terminates outside the visible southwest castle gate")
	check(stage.objectives.size() == 1 and point(stage.objectives[0]).is_equal_approx(Stage.GATE),"Objective and route endpoint share the same visible gate")
	check(int(stage.objectives[0].hp) == int(original.objectives[0].hp),"Castle health is unchanged")
	check(stage.buildZones.size() == 2,"Only the two drawn firing decks are ranged placement sites")
	check(point(stage.buildZones[0]).is_equal_approx(Stage.NORTH_DECK) and point(stage.buildZones[1]).is_equal_approx(Stage.SOUTH_DECK),"Both live deck coordinates match authored image anchors")
	check(stage.tactics.groundPosts.size() == original.tactics.groundPosts.size(),"Existing number of frontline support markers is retained")
	for post in stage.tactics.groundPosts:
		check(int(post.pathIndex) == 0 and int(post.segmentIndex) == 0 and float(post.t) > 0.0 and float(post.t) < 1.0,"Every support marker references the replacement route")
	check(not bool(stage.camera.allowZoom),"The painted first stage uses a fixed camera")
	for anchor in stage.historicalBattlefield.learningSupportAnchors.values():
		check(point(anchor).is_equal_approx(Stage.LEARNING_SUPPORT),"Learning rewards use a valid position outside the castle")
	var unrelated: Dictionary = {"id":"another-stage","stageNumber":2,"paths":[{"custom":true}],"worldGeometry":{"keep":true}}
	check(Stage.apply(unrelated) == unrelated,"Unrelated battlefields are not remapped")

func renderer_checks(stage: Dictionary) -> void:
	var renderer = Painted.new()
	check(not renderer.configure({"background":Stage.BACKGROUND_PATH}),"A background path alone cannot activate the new renderer")
	check(not renderer.configure({"paintedPresentation":true,"paintedBackground":"res://assets/painted-battlefield/does-not-exist.png"}),"A missing asset reports inactive instead of hiding the original renderer")
	check(renderer.configure(stage),"The actual generated map asset can load")
	check(renderer.is_ready(),"Loaded renderer reports readiness")
	if renderer.texture != null:
		check(renderer.texture.get_size().is_equal_approx(Vector2(Stage.ART_SIZE)),"The mounted texture is the inspected 1831 by859 map")
	for field in [Rect2(16,70,1248,586),Rect2(16,70,1408,660)]:
		check(Painted.texture_rect(field) == field,"Complete map fills the same rectangle as actors without cropping")
		var mirrored: Rect2 = Painted.texture_rect(field,true)
		check(mirrored.position == Vector2(field.end.x,field.position.y) and mirrored.size == Vector2(-field.size.x,field.size.y),"Optional reflection follows the game's existing horizontal mirror contract")
	check(not Painted.valid_rect(Rect2(0,0,0,10)) and not Painted.valid_rect(Rect2(Vector2(NAN,0),Vector2.ONE)),"Zero or non-finite field rectangles never draw")
	evidence["renderer"] = renderer.diagnostics()

func advance(game: Node2D, seconds: float) -> void:
	for unused in range(ceili(seconds/.025)):
		game.advance_simulation(.025)

func gameplay_checks(stage: Dictionary) -> void:
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	var catalog: Array = roster.get("units",[])
	var game: Node2D = Battle.new()
	game.three_d_enabled = true # No legacy 2D sprites need loading for model checks.
	root.add_child(game)
	game.set_process(false)
	game.configure_roster(catalog,["archer","spear"],{"archer":5,"spear":1})
	game.load_map(stage)
	check(not game.presentation_mirrored,"Southwest castle does not trigger an unexpected map reflection")
	check(game.ground_combat.land_segment_safe(Stage.INGRESS,Stage.GATE,.008),"Whole new approach is clear of river and scenery footprints")
	check(not game.ground_combat.land_segment_safe(Vector2(.10,.08),Vector2(.10,.24),.008),"Crossing the drawn northwest river is rejected")
	check(not game.ground_combat.land_segment_safe(Vector2(.131,.855),Vector2(.131,.855),.008),"The castle building footprint is not a walkable shortcut")
	check(game.ground_combat.march_bases.size() == 1,"The actual new path has one usable recruitment origin")
	if not game.ground_combat.march_bases.is_empty():
		var base: Vector2 = game.ground_combat.march_bases[0].position
		check(base.distance_to(Stage.GATE) < .019 and game.ground_combat.land_segment_safe(base,Stage.GATE),"Recruitment origin is immediately outside the castle gate")
	for deck in [Stage.NORTH_DECK,Stage.SOUTH_DECK]:
		check(not game._eligible_zone(deck,"archer").is_empty(),"Archer placement is legal on a real painted deck")
		check(not game.ground_combat.marching_support_destination("spear",deck).is_empty(),"A locally dropped spear squad has a physical return route from each deck")
	for scenery in stage.obstacles:
		check(game._eligible_zone(point(scenery),"archer").is_empty(),"Ranged placement does not accept scenery " + str(scenery.id))
	game.start_battle()
	game.spawn_clock = 1000.0
	var gold_before: int = game.gold
	var north: Dictionary = game.submit_deployment("archer",Stage.NORTH_DECK)
	var south: Dictionary = game.submit_deployment("archer",Stage.SOUTH_DECK)
	check(bool(north.get("ok",false)) and bool(south.get("ok",false)),"Both actual paid deck orders are accepted")
	check(game.gold == gold_before - game.recruit_cost("archer")*2,"New map placement preserves actual archer order costs")
	advance(game,2.2)
	var bows: Array = game.units.filter(func(unit: Dictionary): return str(unit.type) == "archer")
	check(bows.size() == 4,"Two Lv5 orders produce four real soldiers on the two decks")
	var reach_rows: Array = []
	for bow in bows:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(bow.position,Stage.INGRESS,Stage.GATE)
		var actual_range: float = float(game._stats(bow).range)
		var separation: float = bow.position.distance_to(closest)
		check(separation <= actual_range,"Existing raised-position range reaches the actual enemy route")
		reach_rows.append({"position":str(bow.position),"range":actual_range,"nearestRoadDistance":separation,"elevation":bow.elevation})
	check(game.ground_combat.land_segment_safe(Stage.LEARNING_SUPPORT,Stage.GATE),"Learning support location is on the open approach")
	evidence["deckReach"] = reach_rows
	evidence["paidPlacement"] = {"north":north,"south":south,"realArchers":bows.size(),"goldSpent":gold_before-game.gold}
	game.free()

func run() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var original: Dictionary = maps[0]
	var source_before: String = JSON.stringify(original)
	var stage: Dictionary = Stage.apply(original)
	check(JSON.stringify(original) == source_before,"Applying the new presentation never mutates the source map")
	stage_checks(original,stage)
	renderer_checks(stage)
	gameplay_checks(stage)
	print("PAINTED_BATTLEFIELD_RESULT " + JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence}))
	quit(0 if failures.is_empty() else 1)
