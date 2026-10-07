extends SceneTree

var app: Node
var captured_states: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://native/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.game.three_d_enabled = true
	app.troops_3d.show()
	app._select_map(0)
	app.game.set_seed(42)
	app._begin_battle()
	app.game.set_process(false)
	for i in range(4):
		assert(app.game.recruit())
		var point: Vector2 = app.game.placement_hints[mini(i*2,app.game.placement_hints.size()-1)]
		assert(app.game.place_unit(point.x,point.y))
	await create_timer(0.7).timeout
	for tick in range(1800):
		app.game.advance_simulation(1.0/30.0)
		if app.game.units.any(func(unit): return str(unit.get("animation",""))=="attack"):
			break
	DirAccess.make_dir_recursive_absolute("res://dist/motion-3d-frames")
	for frame in range(180):
		for tick in range(2):
			app.game.advance_simulation(1.0/30.0)
		var snapshot: Dictionary = app.game.snapshot()
		for unit in snapshot.units:
			captured_states[str(unit.animation)+":"+str(unit.animationFrame)] = true
		app._on_state(snapshot)
		app.toast_label.text = ""
		app.game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var frame_image: Image = root.get_texture().get_image().get_region(Rect2i(24,104,1100,670))
		assert(frame_image.save_png("res://dist/motion-3d-frames/frame-%03d.png" % frame)==OK)
	print("MOTION CAPTURE: 180 real 3D battle frames, 12 simulated seconds, observed states ",captured_states.keys())
	app.player.stop()
	await create_timer(0.1).timeout
	app.queue_free()
	await process_frame
	quit(0)
