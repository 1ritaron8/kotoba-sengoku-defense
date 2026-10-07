extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app=load("res://native/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._select_map(0)
	await process_frame
	await process_frame
	print("MODAL RECT ",app.modal_scroll.size," BODY ",app.modal_body.size," MIN ",app.modal_body.get_combined_minimum_size())
	assert(app.modal_scroll.size.x<=app.modal_card.size.x-56,"Wrapped content fits inside the modal")
	assert(app.modal_footer.get_global_rect().end.y<app.modal_card.get_global_rect().end.y,"Sortie actions remain inside the card")
	for child in app.modal_body.get_children():
		print(child.get_class()," ",child.size," MIN ",child.get_combined_minimum_size()," ",child.text if child is Label else "")
		if child is Label:
			assert(child.size.y>=28,"Modal text has a readable visible row")
			assert(child.size.x<=app.modal_scroll.size.x,"Label respects modal content width")
	assert(app.ui.z_index>app.game.actor_overlay.z_index,"Battlefield labels render beneath learning overlays")
	print("MODAL LAYOUT QA: PASS")
	app.player.stop()
	app.player.stream=null
	await create_timer(.5).timeout
	app.queue_free()
	await process_frame
	quit(0)
