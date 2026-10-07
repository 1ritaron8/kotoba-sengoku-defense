extends SceneTree
const Actor=preload("res://native/sengoku_actor_3d.gd")
const TYPES=["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var profile=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/premium-models/") or DisplayServer.get_name()=="headless":
		quit(2)
		return
	await hero_capture()
	await create_timer(.5).timeout
	quit(0)
func hero_capture() -> void:
	var viewport=SubViewport.new()
	viewport.size=Vector2i(256,320)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world=Node3D.new()
	viewport.add_child(world)
	var sky_mat=ProceduralSkyMaterial.new()
	sky_mat.sky_top_color=Color("889cac")
	sky_mat.sky_horizon_color=Color("d7dbd0")
	sky_mat.ground_bottom_color=Color("2b332c")
	sky_mat.ground_horizon_color=Color("9d9c83")
	var sky=Sky.new()
	sky.sky_material=sky_mat
	var environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("2b302a")
	environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy=.75
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	var lighting=WorldEnvironment.new()
	lighting.environment=environment
	world.add_child(lighting)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-35,0)
	sun.light_color=Color("fff0d7")
	sun.light_energy=1.15
	sun.shadow_enabled=true
	sun.shadow_bias=.02
	sun.shadow_normal_bias=.1
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=20
	world.add_child(sun)
	var plane=MeshInstance3D.new()
	var plane_mesh=PlaneMesh.new()
	plane_mesh.size=Vector2(6,6)
	plane.mesh=plane_mesh
	plane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_mat=StandardMaterial3D.new()
	floor_mat.albedo_color=Color("484c42")
	floor_mat.roughness=1
	plane.material_override=floor_mat
	world.add_child(plane)
	var camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.near=.1
	camera.far=45
	camera.position=Vector3(2.6,2,-4)
	world.add_child(camera)
	camera.current=true
	var sheet=Image.create(2048,1280,false,Image.FORMAT_RGBA8)
	sheet.fill(Color("2b302a"))
	for index in range(26):
		var type_name: String=TYPES[index%8] if index<24 else ("enemy_light" if index==24 else "enemy_heavy")
		camera.size=3.05 if type_name=="commander" else 2.15
		camera.look_at(Vector3(0,1.12 if type_name=="commander" else .92,0))
		var actor=Actor.new()
		world.add_child(actor)
		actor.configure(type_name,index>=24,1,false,int(index/8) if index<24 else 0)
		actor.apply_state({"animation":"idle","animationClock":.65,"animationPhase":0,"aimX":0,"aimY":-1})
		await create_timer(.15).timeout
		await RenderingServer.frame_post_draw
		var frame=viewport.get_texture().get_image()
		
		sheet.blit_rect(frame,Rect2i(0,0,256,320),Vector2i((index%8)*256,int(index/8)*320))
		actor.queue_free()
		await process_frame
	assert(sheet.save_png("C:/JP_DF/dist/premium-"+("before" if "--before" in OS.get_cmdline_user_args() else "after")+"-close.png")==OK)
	print("BODY_HERO_CAPTURE eight adult full-body GPU renders")
	viewport.queue_free()
	await process_frame

