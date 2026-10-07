extends SceneTree
const Actor=preload("res://native/sengoku_actor_3d.gd")
var checks: int=0
var failures: Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		if failures.size()<20: push_error("SAILING DEATH "+message)

func state(clock: float,dead: bool=true) -> Dictionary:
	return {"animation":"death" if dead else "idle","animationClock":clock,"animationPhase":0.0,"aimX":0.0,"aimY":-1.0,"sailing":true,"dead":dead}

func endpoints(actor: Node3D) -> Dictionary:
	var result: Dictionary={}
	for key in actor.bones: result[key]=actor.bones[key].global_position
	return result

func test_actor(id: String) -> void:
	var actor=Actor.new()
	root.add_child(actor)
	actor.configure(id,id.begins_with("enemy"),29,false)
	actor.apply_state(state(0,false))
	var alive: Dictionary=endpoints(actor)
	var previous_y: float=actor.boat.position.y
	for frame in range(61):
		actor.apply_state(state(float(frame)*.6667/60.0))
		check(actor.boat.visible,id+": hull remains present during death")
		check(not actor.bones.weapon.visible,id+": water casualty does not draw a weapon")
		if id=="commander": check(not actor.mount.visible,"Mounted casualty stays in a boat without a horse")
		check(actor.motion_debug.mode=="sailing_death",id+": death avoids the land fall and settle branch")
		check(actor.boat.position.y<=previous_y+.000001,id+": hull descends continuously without rising or snapping")
		previous_y=actor.boat.position.y
		var seated: Vector3=actor.boat.global_transform.affine_inverse()*actor.rig.global_position
		check(absf(seated.y-.690)<.002 and absf(seated.z)<.002,id+": pelvis stays registered to the moving hull")
		for side in ["L","R"]:
			var foot: Vector3=actor.boat.global_transform.affine_inverse()*actor.bones["foot"+side].global_position
			check(foot.y>.12 and foot.y<.20 and foot.z<-.20,id+": tucked feet remain inside the deck rather than falling to land")
			var grip: Vector3=actor.bones["hand"+side].global_transform*Vector3(0,-.03,-.005)
			var oar_grip: Vector3=actor.bones["oar"+side].global_position
			check(absf(grip.distance_to(oar_grip)-.10)<.001,id+": oar handle follows the casualty hand")
		for key in actor.bones:
			check(actor.bones[key].global_transform.is_finite(),id+": finite water-death transforms")
		if frame==0:
			var jump: float=0
			for key in alive:
				# The explicitly hidden mount resets its legs for a later land death;
				# only visible crew/oar joints can cause a water-death visual jump.
				if id=="commander" and str(key).begins_with("horse"): continue
				jump=maxf(jump,alive[key].distance_to(actor.bones[key].global_position))
			check(jump<.10,id+": rowing to death does not teleport any joint")
	check(is_equal_approx(actor.boat.position.y,-.13),id+": final hull descent is restrained")
	var frozen: Dictionary=endpoints(actor)
	actor.apply_state(state(.6667))
	for key in frozen: check(frozen[key].distance_to(actor.bones[key].global_position)<.00001,id+": paused water death is deterministic")
	for mesh in actor.meshes: check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,id+": no land-contact shadow on water")
	actor.apply_state({"animation":"idle","animationClock":0,"sailing":false})
	check(not actor.boat.visible and actor.boat.position==Vector3.ZERO,id+": later land state does not inherit hull sink")
	actor.free()

func capture() -> void:
	var viewport=SubViewport.new()
	viewport.size=Vector2i(1280,800)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world=Node3D.new()
	viewport.add_child(world)
	var environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("344951")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("c5c9cb")
	environment.ambient_light_energy=.7
	var ambient=WorldEnvironment.new()
	ambient.environment=environment
	world.add_child(ambient)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,135,0)
	sun.light_energy=1.25
	world.add_child(sun)
	var water=MeshInstance3D.new()
	var plane=PlaneMesh.new()
	plane.size=Vector2(15,12)
	water.mesh=plane
	var material=StandardMaterial3D.new()
	material.albedo_color=Color("526a72")
	material.roughness=.7
	water.material_override=material
	water.position.y=-.08
	world.add_child(water)
	var camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=11.4
	camera.position=Vector3(0,9,-9)
	world.add_child(camera)
	camera.look_at(Vector3(0,.3,0))
	camera.current=true
	for row in range(2):
		for col in range(4):
			var actor=Actor.new()
			world.add_child(actor)
			actor.configure("enemy_light" if row==0 else "enemy_heavy",true,29,false)
			actor.position=Vector3(3.9-float(col)*2.6,0,1.9-float(row)*3.8)
			actor.apply_state(state(float(col)*.6667/3.0))
	for unused in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var path: String="user://preview-sailing-death.png" if OS.get_cmdline_user_args().has("--packed") else "res://dist/preview-sailing-death.png"
	check(viewport.get_texture().get_image().save_png(path)==OK,"Actual GPU water-death sheet saves")
	print("SAILING_DEATH_GPU ",RenderingServer.get_video_adapter_name())
	viewport.queue_free()
	await process_frame

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/sailing-death/").to_lower()):
		push_error("Sailing QA refuses a player profile")
		quit(2)
		return
	for id in ["enemy_light","enemy_heavy","archer","spear","samurai","gunner","naginata","monk","ninja","commander"]: test_actor(id)
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name()!="headless": await capture()
	var report_path: String="user://qa_sailing_death.json" if OS.get_cmdline_user_args().has("--packed") else "res://tests/qa_sailing_death.json"
	var file=FileAccess.open(report_path,FileAccess.WRITE)
	check(file!=null,"Sailing death QA report opens")
	if file!=null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Real hull, deck-relative joint endpoints, oar grips, finite transforms, retained hull visibility, steady descent and pause determinism; no claim of fluid simulation."},"  "))
		file.close()
	print("SAILING_DEATH_QA ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
