extends SceneTree
## GPU capture of naturally spawned enemies meeting paid troops. The unlocked
## visual fixture is isolated from the player's campaign and from balance QA.
const Store = preload("res://native/progress.gd")
var app: Node

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"):
		push_error("Hybrid capture refuses player progress")
		quit(2)
		return
	var fixture = Store.new()
	fixture.save_path = "user://hybrid-capture-%d.json" % Time.get_ticks_msec()
	for map in JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")):
		fixture.data.maps[str(map.id)] = {"wins":1}
	fixture.data.settings = {"music":false,"voice":false}
	fixture.write_save()
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = fixture.save_path
	root.add_child(app)
	await process_frame
	app._select_tier(0)
	app._select_map(0)
	app._begin_battle()
	app.set_process(false)
	app.game.set_process(false)
	app.player.stop()
	app.learning_field.clear()
	var original_gold: int = app.game.gold
	var ids: Dictionary = {}
	for definition in [{"type":"spear","zone":-2},{"type":"commander","zone":1},{"type":"archer","zone":0}]:
		if not app.game.recruit(str(definition.type)):
			push_error("Visual fixture cannot pay for "+str(definition.type))
			quit(1)
			return
		var candidates: Array = []
		for index in range(app.game.zones.size()):
			if str(app.game.zones[index].get("placementRole",""))==("ranged" if definition.type=="archer" else "ground"):
				candidates.append(index)
		var index: int = candidates[int(definition.zone)]
		var point: Vector2 = app.game.placement_hints[index]
		if point.x<0 or not app.game.place_unit(point.x,point.y):
			push_error("Visual fixture has no legal "+str(definition.type)+" position")
			quit(1)
			return
		ids[str(definition.type)] = int(app.game.units.back().id)
	app.game.select_unit(int(ids.commander))
	var observed: bool = false
	var defended: bool = false
	var original_positions: Dictionary = {}
	for unit in app.game.units: original_positions[str(unit.id)] = unit.position
	var maximum_travel: float = 0.0
	var images: Array = []
	for frame in range(1800):
		for step in range(4): app.game.advance_simulation(.025)
		app.troops_3d.sync_actor_states(app.game.actor_states())
		if frame%5==0: app.game._emit_state()
		for unit in app.game.units:
			if unit.type=="commander":
				maximum_travel=maxf(maximum_travel,unit.position.distance_to(original_positions[str(unit.id)]))
		if app.game.between_waves: app._continue_battle()
		await process_frame
		if not observed and maximum_travel>.035:
			app.game.select_unit(int(ids.commander))
			app.game._emit_state()
			app.learning_field.clear()
			await RenderingServer.frame_post_draw
			var path: String = "C:/JP_DF/dist/preview-hybrid-charge.png"
			root.get_texture().get_image().save_png(path)
			images.append(path)
			observed = true
		if not defended and not app.game.enemies.is_empty():
			var blocking: bool = false
			for unit in app.game.units:
				if unit.type=="spear" and int(app.game._unit_public(unit).get("blockCount",0))>0: blocking=true
			if blocking:
				app.game.select_unit(int(ids.spear))
				app.game._emit_state()
				app.learning_field.clear()
				await RenderingServer.frame_post_draw
				var path: String = "C:/JP_DF/dist/preview-hybrid-defense.png"
				root.get_texture().get_image().save_png(path)
				images.append(path)
				defended = true
		if observed and defended: break
		if app.game.finished: break
	var report = {"images":images,"observedCharge":observed,"observedBlocking":defended,"maximumCavalryTravel":maximum_travel,"initialSupply":original_gold,"finalState":app.game.snapshot(),"scope":"Unlocked isolated visual fixture, paid Lv1 troops and naturally spawned enemies; learning reports hidden only for an unobstructed screenshot."}
	var output = FileAccess.open("user://qa_hybrid_capture.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("HYBRID_GPU_CAPTURE ",JSON.stringify({"images":images,"observedCharge":observed,"maximumCavalryTravel":maximum_travel,"selected":app.game.snapshot().selected.get("stanceKo","")}))
	app.player.stream = null
	app.queue_free()
	await process_frame
	quit(0 if observed and images.size()==2 else 1)
