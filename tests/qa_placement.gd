extends SceneTree

const Battle = preload("res://native/game.gd")
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func find_legal(game: Node2D, build_zone: Dictionary) -> Vector2:
	var center: Vector2 = build_zone.position
	var class_id: String = "spear" if str(build_zone.get("placementRole","ranged"))=="ground" else "archer"
	if not game._eligible_zone(center,class_id).is_empty():
		return center
	for x in range(-3,4):
		for y in range(-3,4):
			var candidate: Vector2 = center + Vector2(x,y) * .016
			if candidate.distance_to(center) <= float(build_zone.r) and not game._eligible_zone(candidate,class_id).is_empty():
				return candidate
	return Vector2(-1,-1)

func run() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--catalog":
		maps = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var checked_zones: int = 0
	var central_positions: int = 0
	var checked_hints: int = 0
	for map_data in maps:
		var game: Node2D = Battle.new()
		root.add_child(game)
		game.set_process(false)
		game.load_map(map_data)
		for hint_index in range(game.zones.size()):
			game.units.clear()
			game.gold = 1000
			var class_id: String = "spear" if str(game.zones[hint_index].get("placementRole","ranged"))=="ground" else "archer"
			check(game.recruit(class_id),"Each zone recruits its actual supported class")
			game._refresh_placement_hints()
			var hint: Vector2 = game.placement_hints[hint_index]
			check(hint.x >= 0, "%s empty zone %d has a visible legal hint" % [map_data.id,hint_index])
			if hint.x < 0:
				game.cancel_recruit()
				continue
			check(game.place_unit(hint.x,hint.y), "%s drawn hint %d accepts its supported class" % [map_data.id,hint_index])
			checked_hints += 1
			game.gold = 1000
			check(game.recruit(class_id),"Supported replacement class recruits")
			game._refresh_placement_hints()
			var next_hint: Vector2 = game.placement_hints[hint_index]
			check(next_hint.x < 0 or next_hint.distance_to(hint) >= .052, "Hint moves away from deployed unit collision")
			if next_hint.x >= 0:
				check(game.place_unit(next_hint.x,next_hint.y), "Occupied zone replacement hint accepts a new recruit")
				checked_hints += 1
			game.cancel_recruit()
		# Fill every hinted slot in one zone until its marker disappears.
		game.units.clear()
		game.gold = 1000
		game._refresh_placement_hints()
		var zone_guard: int = 0
		while game.placement_hints[0].x >= 0 and zone_guard < 30:
			var hint: Vector2 = game.placement_hints[0]
			game.gold = 1000
			check(game.recruit("archer") and game.place_unit(hint.x,hint.y), "Successive marker remains legal while filling the ranged zone")
			checked_hints += 1
			zone_guard += 1
		check(game.placement_hints[0].x < 0, "Full zone omits its visual marker")
		for index in range(game.zones.size()):
			var build_zone: Dictionary = game.zones[index]
			var class_id: String = "spear" if str(build_zone.get("placementRole","ranged"))=="ground" else "archer"
			var position_norm: Vector2 = find_legal(game,build_zone)
			check(position_norm.x >= 0, "%s zone %d has a legal central/nearby position" % [map_data.id,index])
			if position_norm.x < 0: continue
			if position_norm == build_zone.position: central_positions += 1
			game.gold = 1000
			game.units.clear()
			check(game.recruit(class_id), "%s zone %d supported recruit succeeds" % [map_data.id,index])
			var pending: Dictionary = game.snapshot().pending
			check(pending.has("damage") and pending.has("range") and pending.has("interval") and pending.has("dps"), "Pending unit includes attack statistics")
			check(not pending.has("mergeReady") and not pending.has("upgradeReady"), "Pending snapshot has no battlefield growth actions")
			check(game.place_unit(position_norm.x,position_norm.y), "%s zone %d deployment succeeds" % [map_data.id,index])
			var selected: Dictionary = game.snapshot().selected
			check(bool(selected.deployed), "Selected unit reports actual deployment")
			check(not selected.has("upgradeCost") and not selected.has("mergeCandidateId"), "Selected snapshot exposes no removed battlefield growth data")
			checked_zones += 1
		game.queue_free()
	print("PLACEMENT_TEST maps=",maps.size()," zones=",checked_zones," legal_centers=",central_positions," verified_drawn_hints=",checked_hints," failures=",failures.size())
	quit(0 if failures.is_empty() and (maps.size() == 40 or args.size() == 2) else 1)
