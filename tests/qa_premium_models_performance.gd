extends SceneTree
## Render workload fixture only, not a claim about population reached in play.
const Troops=preload("res://native/troops_3d.gd")
var checks: int=0
var failures: Array=[]

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for index in range(count): await process_frame

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/premium-models/") or DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size=Vector2i(1440,900)
	var variant: String="before" if "--before" in OS.get_cmdline_user_args() else "after"
	var troops=Troops.new()
	root.add_child(troops)
	troops.set_field_size(Vector2(1440,736))
	troops.set_stage(JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))[0])
	var samples: Array=[]
	for count in [24,56]:
		var states: Array=[]
		for index in range(count):
			states.append({"id":10000+index,"type":["archer","spear","samurai","gunner","naginata","monk","commander","ninja","enemy_light","enemy_heavy"][index%10],"evolution":2 if index<14 else 0,"friendly":index<14,"x":.12+float(index%8)*.1,"y":.18+float(index/8)*.09,"aimX":1.0,"aimY":0.0,"animation":"walk","animationClock":.4,"motionTime":.4,"animationPhase":index*.17,"sailing":false})
		troops.manual_states=states
		await frames(25)
		var timings: Array=[]
		var last: int=Time.get_ticks_usec()
		for frame in range(120):
			for state in states:
				state.animationClock+=1.0/60.0
				state.motionTime+=1.0/60.0
				state.x+=.3/60.0/troops.world_width
			await process_frame
			var now: int=Time.get_ticks_usec()
			timings.append(float(now-last)/1000.0)
			last=now
		var total: float=0
		for value in timings: total+=value
		timings.sort()
		samples.append({"actors":count,"meanFrameMs":total/timings.size(),"medianFrameMs":timings[60],"p95FrameMs":timings[114],"fps":1000.0/(total/timings.size()),"drawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"render":troops.diagnostics()})
		checks+=1
		if troops.actors.size()!=count: failures.append("Actor count "+str(count))
		print("PREMIUM_PERFORMANCE ",JSON.stringify({"variant":variant,"actors":count,"fps":samples[-1].fps,"meanFrameMs":samples[-1].meanFrameMs,"p95FrameMs":samples[-1].p95FrameMs,"drawCalls":samples[-1].drawCalls}))
	var result: Dictionary={"variant":variant,"checks":checks,"failures":failures,"performance":samples,"gpu":RenderingServer.get_video_adapter_name(),"viewport":str(troops.viewport.size),"scope":"Same field1440x736, existing MSAA2 and .70 actors, 120 timed frames after25warmup; artificial population render benchmark only."}
	var file=FileAccess.open("user://qa_premium_models_performance_"+variant+".json",FileAccess.WRITE)
	if file==null:
		failures.append("Report file unavailable")
	else:
		file.store_string(JSON.stringify(result,"  "))
		file.close()
	troops.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
