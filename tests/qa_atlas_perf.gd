extends SceneTree
## Test-only, same-process comparison. Production scripts and shader code are untouched.

const Materials = preload("res://native/actor_materials.gd")
const TYPES: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja","enemy_light","enemy_heavy"]

var app: Node
var material: ShaderMaterial
var failures: Array = []
var samples: Array = []
var render_measurement: bool = false
var original_atlas: bool = true

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for index in range(count):
		await process_frame

func make_states(count: int) -> Array:
	var states: Array = []
	for index in range(count):
		states.append({"id":10000+index,"type":TYPES[index%10],"evolution":2 if index<14 else 0,"friendly":index<14,"x":0.12+float(index%8)*0.10,"y":0.18+float(int(index/8))*0.09,"aimX":1.0,"aimY":0.0,"animation":"walk","animationClock":0.4,"motionTime":0.4,"animationPhase":index*0.17,"sailing":false})
	return states

func aggregate(values: Array) -> Dictionary:
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()
	var total: float = 0.0
	for value in sorted_values:
		total += float(value)
	return {"mean":total/maxi(1,values.size()),"median":sorted_values[int(sorted_values.size()/2)],"p95":sorted_values[mini(sorted_values.size()-1,int(sorted_values.size()*0.95))]}

func sample_block(count: int, enabled: bool, order: int) -> void:
	# Each block begins with identical model identities, coordinates, poses and travel.
	material.set_shader_parameter("use_sengoku_surface",enabled)
	var states: Array = make_states(count)
	app.troops_3d.manual_states = states
	app.troops_3d.motion_tracks.clear()
	await frames(40)
	var frame_times: Array = []
	var process_times: Array = []
	var viewport_cpu: Array = []
	var viewport_gpu: Array = []
	var last: int = Time.get_ticks_usec()
	for frame in range(150):
		for state in states:
			state.animationClock += 1.0/60.0
			state.motionTime += 1.0/60.0
			state.x += 0.3/60.0/app.troops_3d.world_width
		await process_frame
		var current: int = Time.get_ticks_usec()
		frame_times.append(float(current-last)/1000.0)
		last = current
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		if render_measurement:
			viewport_cpu.append(float(RenderingServer.call("viewport_get_measured_render_time_cpu",app.troops_3d.viewport.get_viewport_rid())))
			viewport_gpu.append(float(RenderingServer.call("viewport_get_measured_render_time_gpu",app.troops_3d.viewport.get_viewport_rid())))
	var timing: Dictionary = aggregate(frame_times)
	var result: Dictionary = {"actors":count,"atlasEnabled":enabled,"order":order,"frames":frame_times.size(),"meanFrameMs":timing.mean,"medianFrameMs":timing.median,"p95FrameMs":timing.p95,"fps":1000.0/float(timing.mean),"processTimeMs":aggregate(process_times),"drawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),"actualActorCount":app.troops_3d.actors.size()}
	if render_measurement:
		result["viewportCpuMs"] = aggregate(viewport_cpu)
		result["viewportGpuMs"] = aggregate(viewport_gpu)
	if app.troops_3d.actors.size()!=count:
		failures.append("Unexpected actor count in block %d" % order)
	if bool(material.get_shader_parameter("use_sengoku_surface"))!=enabled:
		failures.append("Shader uniform did not match requested condition")
	samples.append(result)
	print("ATLAS_BLOCK ",JSON.stringify(result))

func run() -> void:
	app = load("res://native/main.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	app.game.three_d_enabled = true
	app.current_tier = 0
	app._select_map(0)
	app._begin_battle()
	app.player.stop()
	app.player.stream = null
	app.game.set_process(false)
	app.game.paused = true
	app.troops_3d.battle = null
	app.troops_3d.show()
	material = Materials.material()
	original_atlas = bool(material.get_shader_parameter("use_sengoku_surface"))
	render_measurement = RenderingServer.has_method("viewport_set_measure_render_time") and RenderingServer.has_method("viewport_get_measured_render_time_cpu") and RenderingServer.has_method("viewport_get_measured_render_time_gpu")
	if render_measurement:
		RenderingServer.call("viewport_set_measure_render_time",app.troops_3d.viewport.get_viewport_rid(),true)
	print("ATLAS_SETUP ",JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"viewport":str(app.troops_3d.viewport.size),"formationCount":app.troops_3d.friendly_formation_count,"originalAtlasEnabled":original_atlas,"viewportTimingSupported":render_measurement,"vsyncMode":DisplayServer.window_get_vsync_mode(),"maxFps":Engine.max_fps}))
	# Warm both branches, then ABBA / BAAB counters drift and first-use compilation.
	app.troops_3d.manual_states = make_states(24)
	material.set_shader_parameter("use_sengoku_surface",false)
	await frames(40)
	material.set_shader_parameter("use_sengoku_surface",true)
	await frames(40)
	var order: int = 0
	for count in [24,56]:
		var sequence: Array = [false,true,true,false] if count==24 else [true,false,false,true]
		for enabled in sequence:
			order += 1
			await sample_block(count,bool(enabled),order)
	var comparison: Array = []
	for count in [24,56]:
		var on_ms: float = 0.0
		var off_ms: float = 0.0
		for sample in samples:
			if int(sample.actors)==count:
				if bool(sample.atlasEnabled):
					on_ms += float(sample.meanFrameMs)/2.0
				else:
					off_ms += float(sample.meanFrameMs)/2.0
		comparison.append({"actors":count,"atlasOnMeanMs":on_ms,"atlasOffMeanMs":off_ms,"onMinusOffMs":on_ms-off_ms,"onRelativeCostPercent":100.0*(on_ms/off_ms-1.0),"atlasOnFps":1000.0/on_ms,"atlasOffFps":1000.0/off_ms})
	material.set_shader_parameter("use_sengoku_surface",original_atlas)
	var report: Dictionary = {"scope":"Same process, unchanged shader/model/scene, single uniform toggle; 40 warm-up frames then 150 identical animated frames per balanced block.","samples":samples,"comparison":comparison,"failures":failures,"gpu":RenderingServer.get_video_adapter_name(),"displayDriver":DisplayServer.get_name(),"viewport":str(app.troops_3d.viewport.size),"formationCount":app.troops_3d.friendly_formation_count,"version":Engine.get_version_info(),"limitations":["Synthetic 56-actor fixture includes friendly model types and mounted commanders among hostile-marked actors.","CPU process monitor includes scene processing and is not GPU timing.","Viewport timing may be unsupported or zero on this renderer; wall frame timing remains measured.","Balanced blocks reduce first-use and temporal drift, but one run does not establish performance on other hardware."]}
	var file: FileAccess = FileAccess.open("res://tests/qa_atlas_perf.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ATLAS_COMPARISON ",JSON.stringify(comparison))
	print("ATLAS_FAILURES ",JSON.stringify(failures))
	app.player.stop()
	app.player.stream = null
	await create_timer(0.5).timeout
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
