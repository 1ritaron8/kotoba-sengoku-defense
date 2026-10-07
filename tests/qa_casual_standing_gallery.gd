extends SceneTree
## Actual authored full-detail actors rendered only for surface inspection.
## This gallery is a QA preview, not the existing static barracks portrait UI.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const Materials = preload("res://native/actor_materials.gd")
const TYPES: Array[String] = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
const NAMES: Array[String] = ["궁병","창병","무사","철포병","장도병","승병","기마 장군","닌자"]
var checks: int = 0
var failures: Array = []
var observations: Array = []
var live_actors: Array = []
var viewports: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label);push_error(label)

func run() -> void:
	var allowed: String = "c:/jp_df/tests/profiles/casual-actor-materials/"
	for name in ["APPDATA","LOCALAPPDATA"]:
		if not OS.get_environment(name).replace("\\","/").to_lower().begins_with(allowed): quit(2);return
	if DisplayServer.get_name()=="headless" or OS.get_environment("JP_CASUAL_DUMMY_AUDIO")!="1" or not ProjectSettings.globalize_path("user://").replace("\\","/").to_lower().begins_with(allowed): quit(2);return
	root.size=Vector2i(1440,900)
	var ui: Control=Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	var background: ColorRect=ColorRect.new()
	background.color=Color("e6dfcb")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(background)
	var font: Font=load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	var header: Label=Label.new()
	header.text="실제 3D 병사 재질 시연 · 기존 몸체·무기·동작 유지"
	header.position=Vector2(24,8)
	header.add_theme_font_override("font",font)
	header.add_theme_font_size_override("font_size",24)
	header.add_theme_color_override("font_color",Color("272d32"))
	ui.add_child(header)
	for index in range(TYPES.size()): create_cell(ui,index,font)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://casual-standing-gallery.png")==OK,"Actual standing render saves without retouching")
	for viewport in viewports:
		check(viewport.get_texture().get_image().save_png("user://standing-"+str(viewport.name)+".png")==OK,"Original detail/face/weapon render saves: "+str(viewport.name))
	var report: Dictionary={"checks":checks,"failures":failures,"gpu":RenderingServer.get_video_adapter_name(),"actors":observations,"scope":"Eight existing original soldier meshes, friendly blue and enemy crimson, full-detail actual 3D standing preview. This isolated QA gallery is not the current barracks static 2D portraits; geometry is never modified."}
	var file: FileAccess=FileAccess.open("user://standing-gallery.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  "));file.close()
	print("CASUAL_STANDING_GALLERY ",JSON.stringify({"checks":checks,"failures":failures,"actors":observations.size()}))
	ui.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func create_cell(ui: Control, index: int, font: Font) -> void:
	var origin: Vector2=Vector2(12+(index%4)*357,48+floori(index/4.0)*423)
	var label: Label=Label.new()
	label.text=NAMES[index]+" · 아군 파랑 / 적군 진홍"
	label.position=origin
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",20)
	label.add_theme_color_override("font_color",Color("272d32"))
	ui.add_child(label)
	var viewport: SubViewport=SubViewport.new()
	viewport.name=TYPES[index]
	viewport.size=Vector2i(340,388)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.mesh_lod_threshold=1.0
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	ui.add_child(viewport)
	viewports.append(viewport)
	var world: Node3D=Node3D.new()
	viewport.add_child(world)
	var environment_node: WorldEnvironment=WorldEnvironment.new()
	var environment: Environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("d5d4c7")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("e8e5ce")
	environment.ambient_light_energy=.4
	environment_node.environment=environment
	world.add_child(environment_node)
	var sun: DirectionalLight3D=DirectionalLight3D.new()
	sun.light_energy=1.12
	sun.light_color=Color("fff2d7")
	sun.rotation_degrees=Vector3(-48,-38,0)
	sun.shadow_enabled=true
	sun.shadow_bias=.10
	sun.shadow_normal_bias=.80
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	world.add_child(sun)
	var fill: DirectionalLight3D=DirectionalLight3D.new()
	fill.light_energy=.16
	fill.light_color=Color(.6,.7,.83)
	fill.rotation_degrees=Vector3(-50,145,0)
	world.add_child(fill)
	var camera: Camera3D=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=2.65 if TYPES[index]=="commander" else 2.30
	camera.position=Vector3(0,1.6,7)
	world.add_child(camera)
	camera.look_at(Vector3(0,1.05,0),Vector3.UP)
	camera.current=true
	var floor: MeshInstance3D=MeshInstance3D.new()
	var plane: PlaneMesh=PlaneMesh.new()
	plane.size=Vector2(10,10)
	floor.mesh=plane
	var floor_material: StandardMaterial3D=StandardMaterial3D.new()
	floor_material.albedo_color=Color("a6aa92")
	floor_material.roughness=.92
	floor.material_override=floor_material
	world.add_child(floor)
	for hostile in [false,true]:
		var actor: Node3D=Actor.new()
		world.add_child(actor)
		actor.configure(TYPES[index],hostile,7,true,0)
		actor.position=Vector3(.58 if hostile else -.58,0,0)
		actor.apply_state({"animation":"idle","animationClock":.6,"animationPhase":.2,"aimX":-.10 if hostile else .10,"aimY":1.0})
		live_actors.append(actor)
		check(actor.hero_detail and actor.skinned_renderer==null,"Full existing standing mesh is used: "+TYPES[index])
		check(actor.materials.combined.get_meta("art_direction","")==Materials.ART_DIRECTION,"Standing uses the same surface contract: "+TYPES[index])
		check(bool(actor.materials.combined.get_shader_parameter("hostile_team"))==hostile,"Standing team uniform has correct allegiance: "+TYPES[index])
		observations.append({"type":TYPES[index],"hostile":hostile,"fullDetail":actor.hero_detail,"privateMaterial":actor.materials.combined.get_instance_id(),"surfaceContract":Materials.style_contract(),"originalMeshCount":actor.meshes.size()})
	var texture: TextureRect=TextureRect.new()
	texture.position=origin+Vector2(0,30)
	texture.size=Vector2(340,388)
	texture.texture=viewport.get_texture()
	texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	ui.add_child(texture)
