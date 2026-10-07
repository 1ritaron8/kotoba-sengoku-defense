extends SceneTree

var app: Node
var three_d: bool = false

func _initialize() -> void:
	call_deferred("run")

func populate_and_render(index: int, path: String) -> void:
	app._select_map(index)
	await process_frame
	app.game.set_seed(42)
	app._begin_battle()
	app.game.set_process(false)
	for i in range(4):
		if not app.game.recruit():
			break
		var zone = mini(i*2,app.game.placement_hints.size()-1)
		var point: Vector2 = app.game.placement_hints[zone]
		if point.x >= 0:
			app.game.place_unit(point.x,point.y)
	for tick in range(320):
		app.game.advance_simulation(1.0/30.0)
	app._on_state(app.game.snapshot())
	app.toast_label.text = ""
	await create_timer(0.7).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	var error = image.save_png(path)
	assert(error==OK,"Screenshot save succeeds")
	print("CAPTURE: ",path," ",image.get_size())

func run() -> void:
	app = load("res://native/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	three_d = "--3d" in OS.get_cmdline_user_args()
	if three_d:
		app.game.three_d_enabled = true
		app.troops_3d.show()
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/preview-home.png")
	app.front_end.show_catalog(3)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/preview-stages.png")
	app._select_map(0)
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/preview-briefing.png")
	await populate_and_render(0,"res://dist/preview-3d-forest.png" if three_d else "res://dist/preview-forest.png")
	app.game.pause_battle()
	app._show_quiz()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/preview-learning.png")
	await populate_and_render(4,"res://dist/preview-3d-harbor.png" if three_d else "res://dist/preview-harbor.png")
	if three_d:
		await populate_and_render(8,"res://dist/preview-3d-night.png")
		app.current_tier = 3
		await populate_and_render(7,"res://dist/preview-3d-snow.png")
	app._show_study()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/preview-study.png")
	app.player.stop()
	await create_timer(0.1).timeout
	app.queue_free()
	await process_frame
	quit(0)
