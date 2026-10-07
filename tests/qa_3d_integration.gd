extends SceneTree

var app: Node
var checks: int = 0
var failures: Array = []
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		push_error(note)

func frames(count: int) -> void:
	for index in range(count):
		await process_frame

func run() -> void:
	app = load("res://native/main.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	app.game.three_d_enabled = true
	app.troops_3d.show()
	check(app.front_end.visible,"Home remains the entry point")
	check(app.troops_3d.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Hidden battle viewport stops rendering")
	var photos: Dictionary = {}
	for tier in range(4):
		app.current_tier = tier
		for index in range(10):
			app._select_map(index)
			await frames(2)
			var photo: Texture2D = app.troops_3d.ground_material.get_shader_parameter("photo")
			check(photo!=null and photo.resource_path==app.current_map.background,"Stage owns its exact original photograph")
			photos[photo.resource_path] = true
			check(str(app.troops_3d.stage.id)==str(app.current_map.id),"Renderer follows forty selected stage identities")
	check(photos.size()==40,"Forty distinct maps remain distinct in 3D rendering")
	app.current_tier = 0
	app._select_map(0)
	app._begin_battle()
	app.player.stop()
	app.game.set_process(false)
	app.game.set_seed(42)
	for index in range(4):
		check(app.game.recruit(),"Recruiting still succeeds")
		var point: Vector2 = app.game.placement_hints[index*2]
		check(app.game.place_unit(point.x,point.y),"Original legal placement still succeeds")
	for tick in range(330):
		app.game.advance_simulation(1.0/30.0)
	await frames(3)
	var before: String = JSON.stringify(app.game.snapshot())
	app.troops_3d.sync_actor_states(app.game.actor_states())
	check(JSON.stringify(app.game.snapshot())==before,"3D render synchronization does not mutate combat state")
	check(app.troops_3d.actors.size()==app.game.actor_states().size(),"Visible units, enemies and death actors have exactly one 3D representation")
	for state in app.game.actor_states():
		var key = "%s:0" % str(state.id)
		check(app.troops_3d.actors.has(key),"Each live actor has a stable renderer identity")
		var actor = app.troops_3d.actors[key]
		var actual: Vector2 = app.troops_3d.camera.unproject_position(actor.position)
		var expected = Vector2(state.x,state.y)*app.troops_3d.field_size
		check(actual.distance_to(expected)<0.01,"3D ground anchors align with 2D placement and hit positions")
		check(actor.bones.size()>=17,"Actor uses actual articulated joints")
	app.game.paused = true
	var frozen_state: String = JSON.stringify(app.game.actor_states())
	var frozen_pose: Dictionary = {}
	for key in app.troops_3d.actors:
		frozen_pose[key] = app.troops_3d.actors[key].bones.armR.transform
	await frames(8)
	check(JSON.stringify(app.game.actor_states())==frozen_state,"Pause freezes actor state")
	for key in frozen_pose:
		check(app.troops_3d.actors[key].bones.armR.transform==frozen_pose[key],"Pause freezes actual mesh joint poses")
	app.game.paused = false
	app.troops_3d.battle = null
	var samples: Array = []
	for count in [24,56]:
		var states: Array = []
		for index in range(count):
			states.append({"id":10000+index,"type":["archer","spear","samurai","gunner","naginata","monk","commander","ninja","enemy_light","enemy_heavy"][index%10],"evolution":2 if index<14 else 0,"friendly":index<14,"x":0.12+float(index%8)*0.10,"y":0.18+float(int(index/8))*0.09,"aimX":1.0,"aimY":0.0,"animation":"walk","animationClock":0.4,"motionTime":0.4,"animationPhase":index*0.17,"sailing":false})
		app.troops_3d.manual_states = states
		await frames(20)
		var timings: Array = []
		var last: int = Time.get_ticks_usec()
		for frame in range(120):
			for state in states:
				state.animationClock += 1.0/60.0
				state.motionTime += 1.0/60.0
				state.x += 0.3/60.0/app.troops_3d.world_width
			await process_frame
			var current: int = Time.get_ticks_usec()
			timings.append(float(current-last)/1000.0)
			last = current
		var total: float = 0.0
		for value in timings: total += value
		timings.sort()
		var sample = {"actors":count,"meanFrameMs":total/timings.size(),"medianFrameMs":timings[int(timings.size()/2)],"p95FrameMs":timings[int(timings.size()*0.95)],"fps":1000.0/(total/timings.size()),"drawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
		samples.append(sample)
		print("GPU_PERFORMANCE ",JSON.stringify(sample))
		check(app.troops_3d.actors.size()==count,"Renderer sustains the requested representative battle population")
	report = {"checks":checks,"failures":failures,"stagePhotographs":photos.size(),"performance":samples,"gpu":RenderingServer.get_video_adapter_name(),"displayDriver":DisplayServer.get_name(),"viewport":str(app.troops_3d.viewport.size),"version":Engine.get_version_info()}
	var file = FileAccess.open("res://tests/qa_3d_integration.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("3D_INTEGRATION ",JSON.stringify(report))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
