extends SceneTree

const Battle = preload("res://native/game.gd")
var failures: Array = []
var assertions: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_field_rect(Rect2(0,0,1100,620))
	game.load_map({"id":"render-test","theme":"forest","initialGold":1000,"totalWaves":10,"recruitCost":60,"unitLimit":14,"objectives":[{"id":"main","x":0.95,"y":0.5,"hp":30}],"paths":[{"points":[[0.01,0.5],[0.5,0.5],[0.95,0.5]],"objectiveId":"main"}],"buildZones":[{"x":0.4,"y":0.25,"r":0.1},{"x":0.7,"y":0.75,"r":0.1}]})
	check(game.recruit() and game.place_unit(0.4,0.25), "Rear squad deploys at original gameplay coordinates")
	check(game.recruit() and game.place_unit(0.7,0.75), "Front squad deploys at original gameplay coordinates")
	game.units[0].animation = "idle"
	game.units[1].animation = "idle"
	game._spawn_enemy("raider")
	game.enemies[0].position = Vector2(0.4,0.25)
	game.death_actors.append({"id":9999,"kind":"heavy","position":Vector2(0.5,0.4),"aim":Vector2.RIGHT,"animation":"death","animationClock":0.2,"animationPhase":0.0})
	var before: String = JSON.stringify(game.snapshot())
	var layout: Array = game.render_actor_list()
	check(layout.size() == 8, "Two three-person squads, enemy and corpse share one render list")
	var previous_y: float = -1000.0
	var member_positions: Dictionary = {}
	var member_phases: Array = []
	for actor in layout:
		check(float(actor.position.y) >= previous_y, "Every member, enemy and corpse sorts by its actual ground depth")
		previous_y = float(actor.position.y)
		if bool(actor.friendly) and actor.data.id == game.units[0].id:
			member_positions[str(actor.position)] = true
			member_phases.append(float(actor.phaseOffset))
	check(member_positions.size() == 3, "Squad has three distinct ground positions instead of a regular copied grid")
	member_phases.sort()
	check(float(member_phases[-1])-float(member_phases[0]) > 0.3, "Idle formation phases differ by multiple actual poses")
	var far_geometry: Dictionary = game.sprite_geometry(game._screen(Vector2(0.4,0.15)))
	var near_geometry: Dictionary = game.sprite_geometry(game._screen(Vector2(0.4,0.85)))
	check(float(near_geometry.size.y) > float(far_geometry.size.y)*1.2, "Near soldiers are visibly larger than distant soldiers")
	check(float(near_geometry.size.x) < 42.0, "New world actor size remains smaller than the old fixed 52 pixels")
	check(is_equal_approx(float(near_geometry.anchor.y),228.0/256.0), "Actual foot anchor reads the asset baseline metadata")
	check(is_equal_approx(float(near_geometry.offset.y)+float(near_geometry.size.y)*228.0/256.0,0.0), "Frame feet stay exactly on their ground point")
	var forest_tint: Color = game.actor_tint(Vector2(0.4,0.5))
	check(forest_tint.a == 1.0 and forest_tint.r < 1.0 and forest_tint.b < 1.0, "Environment light changes opaque RGB without making units transparent")
	game.enemies[0].hitClock = 0.12
	var hit_tint: Color = game.actor_tint(Vector2(0.4,0.5),game.enemies[0])
	check(hit_tint.r <= 1.0 and hit_tint.g <= 1.0 and hit_tint.b <= 1.0, "Hit flash stays within environmental brightness bounds")
	game.enemies[0].hitClock = 0.0
	game.queue_redraw()
	await process_frame
	await process_frame
	check(game.render_sprites.size() >= 8, "Actual rendering creates a sprite for every independently sorted body")
	check(game.actor_overlay != null and game.actor_overlay.z_index > 1000, "Labels and projectile feedback render above ground actors")
	if game.render_sprites.size() >= 8:
		previous_y = -1000.0
		var previous_z: int = -1
		for sprite in game.render_sprites:
			if not sprite.visible:
				continue
			check(sprite.position.y >= previous_y and sprite.z_index > previous_z, "Live Sprite2D depth order agrees with actual ground layout")
			previous_y = sprite.position.y
			previous_z = sprite.z_index
			check(sprite.material == game.actor_material and sprite.texture != null, "Every body uses real sprite texture and saturation shader")
			check(sprite.region_rect.size == Vector2(256,256), "Renderer preserves real 256-pixel animation frame crop")
		check(is_equal_approx(float(game.actor_material.get_shader_parameter("saturation")),0.70), "Real actor shader lowers source sheet saturation")
		var crop_before: Rect2 = game.render_sprites[0].region_rect
		for unit in game.units:
			unit.animationClock += 0.25
		game.queue_redraw()
		await process_frame
		await process_frame
		check(game.render_sprites[0].region_rect != crop_before, "Actual rendered Sprite2D changes to the next animation pose")
		for unit in game.units:
			unit.animationClock -= 0.25
	check(JSON.stringify(game.snapshot()) == before, "Depth, shadows and render bodies leave gameplay state unchanged")
	game.load_map({"id":"empty-snow","theme":"snow","objectives":[{"id":"main","x":0.9,"y":0.5,"hp":30}],"paths":[],"buildZones":[]})
	var snow_tint: Color = game.actor_tint(Vector2(0.4,0.5))
	check(snow_tint != forest_tint and snow_tint.b > snow_tint.r, "Snow lighting changes the actual actor RGB palette")
	game.queue_redraw()
	await process_frame
	await process_frame
	for sprite in game.render_sprites:
		check(not sprite.visible, "Stage change hides old render bodies")
	var stages: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check(game.visual_profiles.size() == 40, "All forty inspected stage lighting profiles load")
	for stage in stages:
		game.load_map(stage)
		check(str(game.visual_profile().get("stageId","")) == str(stage.id), "%s uses its own inspected environment lighting" % stage.id)
		check(game._depth_scale(0.85) > game._depth_scale(0.15), "%s keeps foreground soldiers larger than background soldiers" % stage.id)
		check(game.actor_tint(Vector2(0.5,0.5)).a == 1.0, "%s retains opaque actor alpha under environment lighting" % stage.id)
	game.queue_free()
	await process_frame
	print("RENDER_QA assertions=",assertions," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
