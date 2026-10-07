extends SceneTree
## GPU evidence: copied production joint poses, then production learning tweens.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const Troops = preload("res://native/troops_3d.gd")
var frame_files: Array = []
var output_root: String = "C:/JP_DF/tests/running-capture-frames"
var app: Node

func _initialize() -> void:
	call_deferred("run")

func frame(group: String, index: int) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "%s/%s-%03d.png"%[output_root,group,index]
	assert(root.get_texture().get_image().save_png(path)==OK)
	frame_files.append(path)

func motion_capture() -> void:
	var driver: Control = Troops.new()
	root.add_child(driver)
	driver.set_process(false)
	driver.hide()
	driver.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	driver.set_stage(JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))[0])
	var screen = SubViewportContainer.new()
	screen.size = Vector2(1280,720)
	root.add_child(screen)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen.add_child(viewport)
	var world = Node3D.new()
	viewport.add_child(world)
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("19252b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d1dde0")
	environment.environment.ambient_light_energy = .6
	world.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42,-32,0)
	light.light_energy = 1.7
	light.shadow_enabled = true
	world.add_child(light)
	var ground = MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(20,20)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("34443b")
	material.roughness = 1.0
	ground.material_override = material
	world.add_child(ground)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.6
	camera.position = Vector3(0,3.2,8)
	world.add_child(camera)
	camera.look_at(Vector3(0,.9,0))
	camera.current = true
	var clones: Array = []
	var types: Array = ["spear","enemy_light","commander"]
	for index in range(types.size()):
		var actor = Actor.new()
		world.add_child(actor)
		actor.configure(types[index],index==1,19+index,false)
		actor.position.x = [-2.7,-.3,2.25][index]
		actor.rotation.y = 2.45
		clones.append(actor)
	var label = Label.new()
	label.position = Vector2(24,22)
	label.add_theme_font_override("font",load("res://assets/fonts/NotoSansCJKjp-Regular.otf"))
	label.add_theme_font_size_override("font_size",25)
	label.text = "확대 동작 확인  ·  아군 창병 / 적 보병 / 기마"
	root.add_child(label)
	for index in range(70):
		var clock: float = index*.05
		var states: Array = []
		for member in range(3):
			var speed: float = 3.4 if member==2 else 1.55
			var scale_value: float = driver._render_scale({},Vector2(.5,.5),{"type":types[member]})
			states.append({"id":19+member,"type":types[member],"friendly":member!=1,"x":.3+member*.2,"y":.70-speed*scale_value*clock/driver.world_depth,"aimX":0,"aimY":-1,"animation":"walk","animationClock":clock,"motionTime":clock,"animationPhase":member*.17,"sailing":false})
		driver.sync_actor_states(states)
		for member in range(3):
			var source: Node3D = driver.actors["%d:0"%(19+member)]
			for key in source.bones:
				clones[member].bones[key].transform = source.bones[key].transform
			if clones[member].skinned_renderer!=null:
				clones[member].skinned_renderer.sync_pose(clones[member])
		await frame("running",index)
	label.queue_free()
	screen.queue_free()
	driver.queue_free()
	await process_frame

func learning_capture(wave: int, group: String) -> void:
	app.game.wave = wave
	if app.game._is_timed_battle():
		app.game.elapsed = float(app.game._timed_wave().endSeconds)
	app.game.between_waves = true
	app._on_state(app.game.snapshot())
	app._show_quiz()
	var controller = app.learning_transition
	controller.set_process(false)
	var index: int = 0
	for unused in range(22):
		if controller.animation!=null and controller.animation.is_valid():
			controller.animation.pause()
			controller.animation.custom_step(.05)
		await frame(group,index)
		index += 1
	assert(controller.phase=="choice")
	if app.context_task_active:
		app._answer_context(str(app.quiz_task.mission.answerId))
	else:
		app._answer_quiz(str(app.quiz_task.answerId))
	for unused in range(18):
		if controller.animation!=null and controller.animation.is_valid():
			controller.animation.pause()
			controller.animation.custom_step(.05)
		await frame(group,index)
		index += 1
	assert(controller.phase=="result")
	app._continue_battle()
	for unused in range(10):
		if controller.animation!=null and controller.animation.is_valid():
			controller.animation.pause()
			controller.animation.custom_step(.05)
		await frame(group,index)
		index += 1
	assert(controller.phase=="idle" and app.game.input_enabled)
	controller.set_process(true)

func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i.ZERO
	DirAccess.make_dir_recursive_absolute(output_root)
	await motion_capture()
	if "--motion-only" in OS.get_cmdline_user_args():
		print("RUNNING_CAPTURE ",frame_files.size()," frames")
		quit(0)
		return
	root.size = Vector2i(1280,800)
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://capture-running-transition-%d.json"%Time.get_ticks_msec()
	root.add_child(app)
	await process_frame
	app.progress.data.settings.voice = false
	app.progress.data.settings.music = false
	app.progress.data.settings.effects = false
	app.player.stop()
	app.battle_audio.set_enabled(false)
	app._select_map(0)
	app._begin_battle()
	app.set_process(false)
	app.set_process_input(false)
	app.set_process_unhandled_key_input(false)
	root.gui_disable_input = true
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.game._spawn_enemy("runner")
	app.game._spawn_enemy("shield")
	app.troops_3d.sync_actor_states(app.game.actor_states())
	await process_frame
	await learning_capture(1,"support-transition")
	await learning_capture(2,"question-transition")
	var report = FileAccess.open("C:/JP_DF/tests/qa_running_capture.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"frames":frame_files,"adapter":RenderingServer.get_video_adapter_name(),"scope":"Actual GPU production joint poses enlarged for inspection; actual production learning tweens replayed at 20fps, simulation held throughout the learning screen."},"  "))
	report.close()
	app.battle_audio.shutdown()
	app.queue_free()
	await process_frame
	print("RUNNING_TRANSITION_CAPTURE ",frame_files.size()," frames")
	quit(0)
