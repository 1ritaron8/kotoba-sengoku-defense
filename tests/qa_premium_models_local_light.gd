extends SceneTree
const Troops=preload("res://native/troops_3d.gd")
const Materials=preload("res://native/actor_materials.gd")
var checks: int=0
var failures: Array=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok: failures.append(note); push_error(note)
func source(id: int,x: float,clock: float) -> Dictionary:
	return {"id":id,"type":"archer","friendly":true,"x":x,"y":.5,"animation":"idle","animationClock":clock,"motionTime":clock,"aimX":0,"aimY":-1}
func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/premium-models/").to_lower()): quit(2);return
	var renderer=Troops.new()
	root.add_child(renderer)
	renderer.set_process(false)
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	renderer.set_stage(maps[0])
	var image=Image.create(48,32,false,Image.FORMAT_RGB8)
	for y in range(32):
		for x in range(48): image.set_pixel(x,y,Color(.11,.13,.11) if x<24 else Color(.65,.60,.50))
	renderer.local_light_field.configure({"background":"synthetic-illumination-contract"},image)
	renderer.sync_actor_states([source(1,.2,0),source(2,.8,0)])
	var dark=renderer.actors["1:0"]
	var bright=renderer.actors["2:0"]
	check(dark.materials.combined!=bright.materials.combined,"Each actor has isolated local-light uniforms")
	check(dark.materials.combined.shader==bright.materials.combined.shader,"Actual shader remains shared")
	check(dark.materials.combined.get_shader_parameter("cloth_colour")==bright.materials.combined.get_shader_parameter("cloth_colour"),"Textures remain shared")
	var before: float=float(dark.materials.combined.get_shader_parameter("local_exposure"))
	check(before<float(bright.materials.combined.get_shader_parameter("local_exposure"))-.20,"Actual material receives map-position shade/bright contrast")
	var frozen: float=float(bright.materials.combined.get_shader_parameter("local_exposure"))
	var updates: int=renderer.local_light_updates
	for tick in range(60): renderer.sync_actor_states([source(1,.2,0),source(2,.8,0)])
	check(renderer.local_light_updates==updates,"Repeated paused render does not advance local lighting")
	for tick in range(1,61): renderer.sync_actor_states([source(1,.20+.60*float(tick)/60,float(tick)/60),source(2,.8,float(tick)/60)])
	check(renderer.local_light_updates-updates<=30,"Two actors use at most15 uniform updates per simulation second")
	check(float(dark.materials.combined.get_shader_parameter("local_exposure"))>before+.2,"Walking out of shade brightens its own material")
	check(is_equal_approx(float(bright.materials.combined.get_shader_parameter("local_exposure")),frozen),"Another actor's light never changes with its neighbour")
	var alpha_shader: Shader=Materials.placement_preview_material().shader
	check(alpha_shader.code.contains("ALPHA = 0.75") and not Materials.material().shader.code.contains("ALPHA"),"Bright75% preview stays independent of opaque soldiers")
	renderer.sync_placement_preview({"active":true,"visible":true,"valid":true,"type":"archer","position":{"x":.2,"y":.5}},.1)
	check(renderer.placement_actor.materials.combined!=dark.materials.combined,"Ghost has independent terrain-light material")
	check(float(renderer.placement_actor.materials.combined.get_shader_parameter("local_exposure"))<.85,"Ghost receives same shade lookup before its readability floor")
	renderer.set_stage(maps[8])
	check(renderer.local_light_tracks.is_empty(),"Stage reset clears all prior light tracks")
	renderer.sync_actor_states([source(1,.4,1)])
	var energy: float=renderer.torch_lights[0].light_energy
	renderer.sync_actor_states([source(1,.4,1.6)])
	check(not is_equal_approx(renderer.torch_lights[0].light_energy,energy),"Real torch illumination flickers with the battlefield clock")
	energy=renderer.torch_lights[0].light_energy
	renderer.sync_actor_states([source(1,.4,1.6)])
	check(is_equal_approx(renderer.torch_lights[0].light_energy,energy),"Pause freezes actual torch illumination")
	check(renderer.local_light_field.diagnostics().available,"Actual authored night photograph supplies the lighting grid")
	check(renderer.local_light_field.diagnostics().gridWidth==48 and renderer.local_light_field.diagnostics().gridHeight==32,"Only bounded downsample lighting data retained")
	renderer.sync_actor_states([])
	check(not renderer.local_light_tracks.has("1:0"),"Obsolete actors release local-light state")
	var gpu_result: Dictionary={}
	if "--gpu" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		root.size=Vector2i(1440,900)
		renderer.set_field_size(Vector2(1440,900))
		renderer.set_stage(maps[0])
		# Controlled shader contract: identical actors/depth/key light over
		# neutral grey. Only the photo-derived illumination samples differ.
		var neutral=Image.create(8,8,false,Image.FORMAT_RGB8)
		neutral.fill(Color(.3,.3,.3))
		renderer.ground_material.set_shader_parameter("photo",ImageTexture.create_from_image(neutral))
		renderer.local_light_field.configure({"background":"synthetic-illumination-contract"},image)
		renderer.sync_actor_states([source(1,.35,2),source(2,.65,2)])
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		var gpu_image: Image=renderer.viewport.get_texture().get_image()
		var a: float=blue_luminance(gpu_image,Vector2(.35,.5)*renderer.field_size)
		var b: float=blue_luminance(gpu_image,Vector2(.65,.5)*renderer.field_size)
		check(a>0 and b>a*1.15,"Actual GPU shader visibly distinguishes local shade from light")
		check(root.get_texture().get_image().save_png(qa_project_path("dist/premium-local-light-contract.png"))==OK,"Actual controlled local-light GPU contract capture saves")
		gpu_result={"shadeBodyLuminance":a,"sunBodyLuminance":b,"ratio":b/maxf(.001,a),"path":qa_project_path("dist/premium-local-light-contract.png")}
	var result={"checks":checks,"failures":failures,"scope":"Peractor actual ShaderMaterial isolation, movement fade, pause, reset, bounded15Hz update, shared resources, opaque/ghost distinction and physical torch flicker."}
	result["gpu"]=gpu_result
	var file=FileAccess.open("user://qa_premium_models_local_light.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"  "));file.close()
	print("PREMIUM_LOCAL_LIGHT ",JSON.stringify(result))
	renderer.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func blue_luminance(image: Image, point: Vector2) -> float:
	var sum: float=0.0
	var count: int=0
	for y in range(int(point.y)-45,int(point.y)-8):
		for x in range(int(point.x)-14,int(point.x)+14):
			var colour: Color=image.get_pixel(x,y)
			if colour.b>colour.r*1.3 and colour.b>colour.g*1.04 and colour.b>.1:
				sum+=colour.r*.2126+colour.g*.7152+colour.b*.0722
				count+=1
	return sum/maxi(1,count)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
