extends SceneTree
## Actual GPU hero/body and real game captures. This fixture uses isolated saves.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const TYPES=["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var app: Node
func _initialize() -> void:
	call_deferred("run")
func frames(count: int) -> void:
	for index in range(count): await process_frame
func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Body capture needs a real GPU display driver")
		quit(1)
		return
	root.title="말의 전장 · 성인 체형 검수"
	app=load("res://native/main.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	for index in range(14): app.progress.data.maps[str(app.maps[index].id)]={"wins":1}
	for type_name in TYPES: app.progress.data.army.levels[type_name]=1
	app.game.three_d_enabled=true
	app.troops_3d.show()
	for info in [{"index":0,"name":"forest"},{"index":4,"name":"harbor"},{"index":8,"name":"night"}]:
		app._select_map(int(info.index))
		app._begin_battle()
		app.player.stop()
		app.player.stream=null
		app.game.set_process(false)
		app.game.gold=1800
		app.game.set_seed(42)
		for type_name in TYPES:
			if not app.game.recruit(type_name): break
			var legal: Vector2=Vector2(-1,-1)
			for point in app.game.placement_hints:
				if point.x>=0:
					legal=point
					break
			if legal.x<0:
				app.game.cancel_recruit()
				break
			app.game.place_unit(legal.x,legal.y)
		for tick in range(320): app.game.advance_simulation(1.0/30.0)
		app.game.paused=true
		app._on_state(app.game.snapshot())
		app.toast_label.text=""
		await create_timer(.6).timeout
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://dist/preview-body-"+info.name+".png")==OK)
		var field: Image=app.troops_3d.viewport.get_texture().get_image()
		assert(field.save_png("res://dist/preview-body-"+info.name+"-field.png")==OK)
		# The close-up is explicitly a pixel crop of the actual full-size field.
		var unit: Dictionary=app.game.units[mini(2,app.game.units.size()-1)]
		var p: Vector2=unit.position*app.troops_3d.field_size
		var area: Rect2i=Rect2i(Vector2i(clampi(int(p.x)-180,0,field.get_width()-360),clampi(int(p.y)-160,0,field.get_height()-260)),Vector2i(360,260))
		var closeup: Image=field.get_region(area)
		closeup.resize(1080,780,Image.INTERPOLATE_NEAREST)
		assert(closeup.save_png("res://dist/preview-body-"+info.name+"-pixel-closeup.png")==OK)
		print("BODY_FIELD_CAPTURE ",info.name," actors=",app.troops_3d.actors.size()," field=",app.troops_3d.field_size)
	app.queue_free()
	await frames(2)
	await hero_capture()
	quit(0)
func hero_capture() -> void:
	var viewport=SubViewport.new()
	viewport.size=Vector2i(480,620)
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
	var sheet=Image.create(1920,1240,false,Image.FORMAT_RGBA8)
	for index in range(TYPES.size()):
		camera.size=3.05 if TYPES[index]=="commander" else 2.15
		camera.look_at(Vector3(0,1.12 if TYPES[index]=="commander" else .92,0))
		var actor=Actor.new()
		world.add_child(actor)
		actor.configure(TYPES[index],false,1,true,0)
		actor.apply_state({"animation":"idle","animationClock":.65,"animationPhase":0,"aimX":0,"aimY":-1})
		await create_timer(.15).timeout
		await RenderingServer.frame_post_draw
		var frame=viewport.get_texture().get_image()
		assert(frame.save_png("res://dist/preview-body-hero-"+TYPES[index]+".png")==OK)
		sheet.blit_rect(frame,Rect2i(0,0,480,620),Vector2i((index%4)*480,int(index/4)*620))
		actor.queue_free()
		await process_frame
	assert(sheet.save_png("res://dist/preview-body-heroes.png")==OK)
	print("BODY_HERO_CAPTURE eight adult full-body GPU renders")
	viewport.queue_free()
	await process_frame
