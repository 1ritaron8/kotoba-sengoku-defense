extends SceneTree
## Visual fixture with actual shipped units and an issued first-wave context task.
var app: Node

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("").to_lower()+"/"):
		push_error("Visual QA refuses the player's save profile")
		quit(2)
		return
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://learning-visual-%d.json" % Time.get_ticks_msec()
	root.add_child(app)
	await process_frame
	root.title = "말의 전장 · 학습 검수"
	app.progress.data.settings.music = false
	app.progress.data.settings.voice = false
	app.player.stop()
	var stage_number: int = 0
	var target_wave: int = 1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--stage="): stage_number = int(argument.trim_prefix("--stage="))
		if argument.begins_with("--wave="): target_wave = int(argument.trim_prefix("--wave="))
	app._select_tier(clampi(stage_number/10,0,3))
	app._select_map(clampi(stage_number%10,0,9))
	app._begin_battle()
	app.game.set_process(false)
	for target in app.stage_learning.missions[0].targets:
		var point: Dictionary = target.position
		if app.game.recruit("archer"):
			app.game.place_unit(float(point.x),float(point.y))
	for wave in range(1,target_wave+1):
		for index in range(4): app._advance_word()
		app.game._complete_wave()
		await process_frame
		if wave<target_wave:
			app._continue_battle()
	for index in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var prefix: String = "preview-learning" if stage_number==0 else "preview-learning-advanced"
	root.get_texture().get_image().save_png(qa_project_path("dist/%s-context.png") % prefix)
	print("LEARNING_VISUAL_READY ",JSON.stringify({"task":app.quiz_task.id,"kind":app.quiz_task.kind,"gold":app.game.gold,"profile":ProjectSettings.globalize_path("user://"),"japaneseVoiceAvailable":not app.japanese_voice.is_empty()}))
	if "--hold" in OS.get_cmdline_user_args():
		return
	app._answer_context(str(app.quiz_task.answerId))
	for index in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(qa_project_path("dist/%s-support.png") % prefix)
	app._continue_battle()
	for index in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(qa_project_path("dist/%s-support-active.png") % prefix)
	app.player.stream = null
	await create_timer(0.5).timeout
	app.queue_free()
	await process_frame
	quit(0)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
