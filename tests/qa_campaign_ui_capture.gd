extends SceneTree

var app: Node

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path)==OK)
	print("CAMPAIGN_CAPTURE ",path)

func run() -> void:
	app = load("res://native/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	# Isolated rendering fixture; it never writes or replaces player progression.
	for index in range(14):
		app.progress.data.maps[str(app.maps[index].id)] = {"wins":1}
	app.progress.data.army.currency = 1540
	app.progress.data.army.levels.archer = 4
	app.progress.data.army.levels.samurai = 8
	app.progress.data.army.levels.gunner = 4
	app._rebuild_army_cards()
	app._show_home()
	await create_timer(0.5).timeout
	await capture("res://dist/preview-home.png")
	app._show_barracks()
	await process_frame
	await capture("res://dist/preview-barracks.png")
	root.size = Vector2i(1280,800)
	await create_timer(0.3).timeout
	await capture("res://dist/preview-barracks-small.png")
	root.size = Vector2i(1440,900)
	app.barracks.hide()
	app._return_from_barracks()
	app.current_tier = 1
	app._select_map(3)
	app._begin_battle()
	app.game.set_process(false)
	app.player.stop()
	var types = ["samurai","archer","gunner"]
	for index in range(types.size()):
		app.chosen_unit_id = types[index]
		app._rebuild_army_cards()
		assert(app.game.recruit(types[index]))
		var point: Vector2 = app.game.placement_hints[index*2]
		assert(app.game.place_unit(point.x,point.y))
	for tick in range(330):
		app.game.advance_simulation(1.0/30.0)
	app._on_state(app.game.snapshot())
	app.toast_label.text = ""
	await create_timer(0.7).timeout
	await capture("res://dist/preview-campaign-battle.png")
	app.queue_free()
	await process_frame
	quit(0)
