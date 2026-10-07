extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://footer-probe.json"
	root.add_child(app)
	await process_frame
	app.progress.data.settings.voice = false
	app._select_map(0)
	app._begin_battle()
	app.game.set_process(false)
	for wave in range(2):
		for index in range(4): app._advance_word()
		app.game._complete_wave()
		await process_frame
		await process_frame
		if app.context_task_active:
			app._continue_battle()
		else:
			print("FOOTER ",app.modal_footer.get_global_rect()," minimum=",app.modal_footer.get_combined_minimum_size()," CARD=",app.modal_card.get_global_rect())
			for child in app.modal_footer.get_children():
				print(child.get_class()," ",child.get_rect()," minimum=",child.get_combined_minimum_size()," text=",child.get("text"))
	app.queue_free()
	await process_frame
	quit()
