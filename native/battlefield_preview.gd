extends Control
## The catalog shows the native battlefield itself, rendered only on changes.
const Battlefield = preload("res://native/battlefield_3d.gd")
const WORLD_WIDTH: float = 18.5
const ELEVATION: float = 50.0
const MAX_RENDER_SIZE: Vector2 = Vector2(960,640)

static var visual_profiles: Dictionary = {}
var stage: Dictionary = {}
var viewport: SubViewport
var image: TextureRect
var world: Node3D
var camera: Camera3D
var battlefield: Node3D
var sun: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var pending_refresh: bool = false
var render_requests: int = 0
var render_key: String = ""

func configure(value: Dictionary) -> void:
	stage=value.duplicate(true)
	_request_refresh()

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	set_process(false)
	set_physics_process(false)
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.transparent_bg=false
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	world=Node3D.new()
	viewport.add_child(world)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1
	camera.far=45.0
	camera.current=true
	world.add_child(camera)
	var lighting: WorldEnvironment=WorldEnvironment.new()
	environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("19221e")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_sky_contribution=.55
	var sky: Sky=Sky.new()
	sky.radiance_size=Sky.RADIANCE_SIZE_128
	sky_material=ProceduralSkyMaterial.new()
	sky_material.ground_bottom_color=Color(.19,.20,.18)
	sky.sky_material=sky_material
	environment.sky=sky
	lighting.environment=environment
	world.add_child(lighting)
	sun=DirectionalLight3D.new()
	sun.shadow_enabled=true
	sun.shadow_bias=.10
	sun.shadow_normal_bias=.80
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=50.0
	sun.directional_shadow_fade_start=1.0
	world.add_child(sun)
	battlefield=Battlefield.new()
	world.add_child(battlefield)
	image=TextureRect.new()
	image.texture=viewport.get_texture()
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_SCALE
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(image)
	resized.connect(_request_refresh)
	visibility_changed.connect(_visibility_changed)
	_request_refresh()

func _visibility_changed() -> void:
	if viewport==null: return
	if not is_visible_in_tree():
		viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	else:
		_request_refresh()

func _request_refresh() -> void:
	if not is_inside_tree() or viewport==null or pending_refresh: return
	pending_refresh=true
	call_deferred("_refresh")

func _refresh() -> void:
	pending_refresh=false
	if viewport==null or not is_visible_in_tree() or stage.is_empty(): return
	var logical_size: Vector2=size.max(Vector2(2,2))
	var scale_factor: float=minf(1.0,minf(MAX_RENDER_SIZE.x/logical_size.x,MAX_RENDER_SIZE.y/logical_size.y))
	var pixels: Vector2i=Vector2i(maxi(2,roundi(logical_size.x*scale_factor)),maxi(2,roundi(logical_size.y*scale_factor)))
	var next_key: String=JSON.stringify(stage).sha256_text()+":"+str(pixels)
	if next_key==render_key: return
	render_key=next_key
	viewport.size=pixels
	var depth: float=WORLD_WIDTH/(float(pixels.x)/float(pixels.y))/sin(deg_to_rad(ELEVATION))
	camera.size=WORLD_WIDTH
	camera.position=Vector3(0,30.0,30.0/tan(deg_to_rad(ELEVATION)))
	camera.look_at(Vector3.ZERO,Vector3.UP)
	battlefield.configure(stage,WORLD_WIDTH,depth,ELEVATION)
	_configure_lighting()
	render_requests+=1
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _configure_lighting() -> void:
	if visual_profiles.is_empty():
		var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://native/visual_profiles.json"))
		if parsed is Dictionary:
			for profile in parsed.get("profiles",[]): visual_profiles[str(profile.get("stageId",""))]=profile
	var history: Dictionary=stage.get("historicalBattlefield",{})
	var time_data: Variant=history.get("timeOfDay","day")
	var actual_time: String=str(time_data.get("key",time_data.get("value","day"))) if time_data is Dictionary else str(time_data)
	var weather_data: Variant=history.get("weather",{})
	var actual_weather: String=str(weather_data.get("kind",weather_data.get("key","unknown"))) if weather_data is Dictionary else str(weather_data)
	var brightness: float=.85 if actual_weather in ["rain","cloudy","overcast"] else 1.0
	var ambient: Color=Color("dce6e2")
	var direction: Dictionary=visual_profiles.get(str(stage.get("id","")),{}).get("shadowDirection",{"x":-.65,"y":.4})
	var axis: Vector2=Vector2(float(direction.x),float(direction.y)).normalized()
	sun.position=Vector3(-axis.x*18,30,-axis.y*18/sin(deg_to_rad(ELEVATION)))
	sun.look_at(Vector3.ZERO,Vector3.UP)
	sun.light_color=ambient.lerp(Color.WHITE,.25)
	sun.light_energy=.55 if actual_time=="night" else 1.45*brightness
	environment.ambient_light_color=ambient
	environment.ambient_light_energy=.35 if actual_time=="night" else .32*brightness
	sky_material.sky_top_color=Color("29384e") if actual_time=="night" else ambient.lerp(Color(.40,.49,.60),.52)
	sky_material.sky_horizon_color=Color("566477") if actual_time=="night" else ambient*.75
	sky_material.ground_horizon_color=Color("202723") if actual_time=="night" else Color(.37,.35,.28)

func diagnostics() -> Dictionary:
	return {"stageId":str(stage.get("id","")),"nativeBattlefield":is_instance_valid(battlefield),"static":true,"processing":is_processing(),"mouseIgnore":mouse_filter==Control.MOUSE_FILTER_IGNORE,"renderRequests":render_requests,"viewportSize":viewport.size if viewport!=null else Vector2i.ZERO,"updateMode":viewport.render_target_update_mode if viewport!=null else SubViewport.UPDATE_DISABLED,"worldWidth":WORLD_WIDTH,"elevation":ELEVATION,"terrain":battlefield.diagnostics() if is_instance_valid(battlefield) else {}}
