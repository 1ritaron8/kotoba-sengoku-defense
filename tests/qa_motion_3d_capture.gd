extends SceneTree
## Independent motion contact sheets. Does not write native/game or dist files.

const Actor = preload("res://native/sengoku_actor_3d.gd")
const TYPES = ["archer","spear","samurai","commander","enemy_light","enemy_heavy"]
var viewport: SubViewport
var camera: Camera3D
var models: Array = []
var heading: Label
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Motion capture requires an actual GPU display driver")
		quit(1)
		return
	viewport=SubViewport.new()
	viewport.size=Vector2i(1440,1800)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_2X
	root.add_child(viewport)
	var world=Node3D.new()
	viewport.add_child(world)
	var environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("282d2d")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("b8c7cf")
	environment.ambient_light_energy=0.65
	var env_node=WorldEnvironment.new()
	env_node.environment=environment
	world.add_child(env_node)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,140,0)
	sun.light_color=Color(1.0,0.94,0.85)
	sun.light_energy=1.2
	sun.shadow_enabled=true
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=55.0
	sun.shadow_bias=0.02
	sun.shadow_normal_bias=0.1
	world.add_child(sun)
	var floor_mesh=MeshInstance3D.new()
	var plane=PlaneMesh.new()
	plane.size=Vector2(17.0,24.0)
	floor_mesh.mesh=plane
	var ground=StandardMaterial3D.new()
	ground.albedo_color=Color("696d65")
	ground.roughness=1.0
	floor_mesh.material_override=ground
	world.add_child(floor_mesh)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=14.2
	camera.near=0.1
	camera.far=65.0
	camera.position=Vector3(0,sin(deg_to_rad(60.0))*30,-cos(deg_to_rad(60.0))*30)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO,Vector3.UP)
	camera.current=true
	for row in range(TYPES.size()):
		for column in range(4):
			var actor=Actor.new()
			world.add_child(actor)
			actor.configure(TYPES[row],TYPES[row].begins_with("enemy"),31,false)
			# This camera faces +Z, so camera screen-right is world -X.
			# Reverse world X to preserve chronological frames left to right.
			actor.position=Vector3(5.25-column*3.5,0,8.0-row*3.3)
			models.append(actor)
	var canvas=CanvasLayer.new()
	viewport.add_child(canvas)
	heading=Label.new()
	heading.position=Vector2(25,15)
	heading.add_theme_font_size_override("font_size",27)
	heading.add_theme_color_override("font_color",Color.WHITE)
	canvas.add_child(heading)
	for row in range(TYPES.size()):
		var label=Label.new()
		label.text=TYPES[row]
		label.add_theme_font_size_override("font_size",19)
		label.add_theme_color_override("font_shadow_color",Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x",1)
		label.add_theme_constant_override("shadow_offset_y",1)
		label.position=Vector2(25,camera.unproject_position(Vector3(0,0,8.0-row*3.3)).y+20)
		canvas.add_child(label)
	var outputs: Array = []
	for action in [{"name":"walk","times":[0.0,0.18,0.36,0.54],"sailing":false},{"name":"attack","times":[0.0,0.16,0.32,0.49],"sailing":false},{"name":"rowing","times":[0.0,0.52,1.05,1.57],"sailing":true},{"name":"death","times":[0.0,0.22,0.44,0.66],"sailing":false}]:
		heading.text="FULL BODY / "+str(action.name).to_upper()+"   |   clocks: "+str(action.times)+"   |   rows: 6 unit types"
		for index in range(models.size()):
			var clock: float=action.times[index%4]
			models[index].apply_state({"animation":"walk" if action.name=="rowing" else action.name,"animationClock":clock,"animationPhase":0.0,"aimX":0.0,"aimY":-1.0,"hitClock":0.0,"sailing":action.sailing})
		for unused in range(6): await process_frame
		RenderingServer.force_draw(false)
		var path="res://tests/qa_motion_3d_"+action.name+".png"
		viewport.get_texture().get_image().save_png(path)
		outputs.append({"action":action.name,"clocks":action.times,"path":path})
	report={"gpu":RenderingServer.get_video_adapter_name(),"version":Engine.get_version_info().string,"resolution":str(viewport.size),"outputs":outputs,"scope":"Actual GPU geometry contact sheets; 24 low-detail actors at four sampled times. No claim of mocap, skinned meshes, or automatic realism score."}
	var file=FileAccess.open("res://tests/qa_motion_3d_capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("QA_MOTION_CAPTURE ",JSON.stringify(report))
	quit(0)
