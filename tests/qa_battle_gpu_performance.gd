extends SceneTree
const Troops = preload("res://native/troops_3d.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
var results: Array = []
var label: String = "baseline"

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/battle-native-performance/").to_lower()) or not OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower().begins_with(qa_project_path("tests/profiles/battle-native-performance/").to_lower()):
		push_error("Native performance QA requires an isolated workspace profile")
		quit(2)
		return
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	root.size = Vector2i(1440,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var troops = Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(1440,736))
	troops.set_stage(JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))[0])
	for count in [24,56,80]:
		var states: Array = []
		for index in range(count):
			states.append({"id":1000+index,"type":["archer","spear","samurai","gunner","naginata","monk","commander","ninja","enemy_light","enemy_heavy"][index%10],"evolution":2 if index<14 else 0,"friendly":index<14,"x":.08+float(index%8)*.083,"y":.14+float(index/8)*.07,"aimX":1.0,"aimY":0.0,"animation":"walk","animationClock":0.0,"motionTime":0.0,"animationPhase":index*.17,"sailing":false})
		troops.sync_actor_states(states)
		if troops.actors.size()!=count:
			push_error("Performance fixture did not instantiate the requested actors")
			quit(2)
			return
		for unused in range(25): await process_frame
		var frame_times: Array = []
		var pose_times: Array = []
		var last: int = Time.get_ticks_usec()
		for index in range(100):
			for state in states:
				var speed: float = 3.4 if state.type=="commander" else 1.55
				var model_scale: float = troops._render_scale({},Vector2(state.x,state.y),state)
				state.x += speed*model_scale/(60*troops.world_width)
				state.motionTime += 1.0/60.0
				state.animationClock = state.motionTime
			var start: int = Time.get_ticks_usec()
			troops.sync_actor_states(states)
			pose_times.append((Time.get_ticks_usec()-start)/1000.0)
			await process_frame
			var now: int = Time.get_ticks_usec()
			frame_times.append((now-last)/1000.0)
			last = now
		frame_times.sort()
		var frame_average: float = 0.0
		var pose_average: float = 0.0
		for time in frame_times: frame_average += time/frame_times.size()
		for time in pose_times: pose_average += time/pose_times.size()
		var sample: Dictionary = {"actors":count,"meanFrameMs":frame_average,"medianFrameMs":frame_times[50],"p95FrameMs":frame_times[95],"fps":1000/frame_average,"poseCpuMs":pose_average,"drawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}
		results.append(sample)
		print("BATTLE_GPU_PERF ",JSON.stringify(sample))
	var file = FileAccess.open(qa_project_path("tests/qa_battle_gpu_performance_")+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"label":label,"adapter":RenderingServer.get_video_adapter_name(),"viewport":str(troops.viewport.size),"performance":results,"nativeTerrain":troops.battlefield.diagnostics(),"scope":"Artificial24/56/80 animated actors on the real native terrain at1440x736. Shared physical lights and real shadows, MSAA2, Vsync disabled.25warmup/100 measured frames. This measures the rendered troop/terrain workload; full-game UI and combat simulation are not included. Frame time includes render waiting; poseCpuMs is separately instrumented CPU time."},"  "))
	file.close()
	troops.queue_free()
	for unused in range(4): await process_frame
	Battlefield.release_shared_resources()
	for unused in range(4): await process_frame
	quit(0)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
