extends Control
## The catalog shows the native battlefield itself, rendered only on changes.
const Battlefield = preload("res://native/battlefield_3d.gd")
const WorldAdapter = preload("res://native/battlefield_world_adapter.gd")
const RemasterVisualScene = preload("res://native/remaster_visual_slice.gd")
const RenderedArt = preload("res://native/rendered_battlefield_helpers.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
const WORLD_WIDTH: float = 18.5
const ELEVATION: float = 50.0
const MAX_RENDER_SIZE: Vector2 = Vector2(960,640)
const PRESENTATION_CACHE_VERSION: String = "native-preview-4-stage-viewpoint"

static var visual_profiles: Dictionary = {}
static var completed_previews: Dictionary = {}
static var completed_order: Array[String] = []
const COMPLETED_PREVIEW_LIMIT: int = 40
var stage: Dictionary = {}
var viewport: SubViewport
var image: TextureRect
var world: Node3D
var camera: Camera3D
var battlefield: Node3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var remaster_visuals: Node3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var pending_refresh: bool = false
var render_requests: int = 0
var render_key: String = ""
var building: bool = false
var cached_terrain: Dictionary = {}
var cache_hit: bool = false
var capturing: bool = false
var frame_budget_usec: int = Battlefield.INTERACTIVE_FRAME_BUDGET_USEC

static func _completed_key(value: Dictionary) -> String:
	if not value.get("worldGeometry",{}).is_empty():
		var authored_revision: String = FileAccess.get_file_as_string("res://native/remaster_visual_slice.gd").sha256_text()+FileAccess.get_file_as_string("res://native/remaster_surface_materials.gd").sha256_text()
		return "authored-world-preview-1:"+JSON.stringify(value).sha256_text()+":"+authored_revision
	return PRESENTATION_CACHE_VERSION+":"+JSON.stringify(value).sha256_text()+":"+RenderedArt.cache_revision()

static func has_cached_stage(value: Dictionary) -> bool:
	return completed_previews.has(_completed_key(value))

func is_loading() -> bool:
	return building or pending_refresh or capturing

func prepare() -> bool:
	_request_refresh()
	while is_loading(): await get_tree().process_frame
	return has_cached_stage(stage)

static func release_shared_resources() -> void:
	completed_previews.clear()
	completed_order.clear()
	visual_profiles.clear()

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
	camera.far=90.0
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
	sun.directional_shadow_max_distance=90.0
	sun.directional_shadow_fade_start=1.0
	world.add_child(sun)
	fill=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-42,145,0)
	fill.light_cull_mask=2
	fill.light_energy=0.0
	fill.shadow_enabled=false
	world.add_child(fill)
	battlefield=Battlefield.new()
	world.add_child(battlefield)
	image=TextureRect.new()
	image.texture=viewport.get_texture()
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
	if building or capturing: return
	call_deferred("_refresh")

func _refresh() -> void:
	if building or capturing: return
	pending_refresh=false
	if viewport==null or not is_visible_in_tree() or stage.is_empty(): return
	var logical_size: Vector2=size.max(Vector2(2,2))
	var scale_factor: float=minf(1.0,minf(MAX_RENDER_SIZE.x/logical_size.x,MAX_RENDER_SIZE.y/logical_size.y))
	var pixels: Vector2i=Vector2i(maxi(2,roundi(logical_size.x*scale_factor)),maxi(2,roundi(logical_size.y*scale_factor)))
	var requested_stage: Dictionary = stage.duplicate(true)
	var completed_key: String = _completed_key(requested_stage)
	var next_key: String=completed_key+":"+str(pixels)
	if next_key==render_key: return
	if completed_previews.has(completed_key):
		var cached: Dictionary = completed_previews[completed_key]
		image.texture = cached.texture
		viewport.size=pixels
		cached_terrain = cached.terrain
		cache_hit = true
		completed_order.erase(completed_key)
		completed_order.append(completed_key)
		viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		render_key=next_key
		return
	cache_hit = false
	building = true
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var authored: bool = not requested_stage.get("worldGeometry",{}).is_empty()
	_select_provider(authored)
	if authored:
		battlefield.configure(requested_stage)
		if not bool(battlefield.diagnostics().get("ready",false)):
			building=false
			push_error("Home preview rejected invalid authored Stage01 floor.")
			return
		_configure_authored_camera(requested_stage)
		if is_instance_valid(remaster_visuals):
			world.remove_child(remaster_visuals)
			remaster_visuals.queue_free()
		remaster_visuals=RemasterVisualScene.new()
		world.add_child(remaster_visuals)
		remaster_visuals.configure(requested_stage,battlefield)
	else:
		var stage_elevation: float = Presentation.elevation_for_stage(requested_stage)
		var depth: float=WORLD_WIDTH/(float(pixels.x)/float(pixels.y))/sin(deg_to_rad(stage_elevation))
		camera.size=WORLD_WIDTH
		camera.position=Vector3(0,30.0,30.0/tan(deg_to_rad(stage_elevation)))
		camera.look_at(Vector3.ZERO,Vector3.UP)
		await battlefield.configure_preview(requested_stage,WORLD_WIDTH,depth,stage_elevation,frame_budget_usec)
	building = false
	if requested_stage != stage or pending_refresh:
		pending_refresh=false
		_request_refresh()
		return
	render_key=next_key
	viewport.size=pixels
	image.texture=viewport.get_texture()
	cached_terrain.clear()
	_configure_lighting()
	render_requests+=1
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	if DisplayServer.get_name()!="headless":
		capturing=true
		await RenderingServer.frame_post_draw
		capturing=false
		if render_key!=next_key or building or not is_visible_in_tree():
			# A hidden/interrupted capture has no completed cache image. Allow a
			# subsequent show/configure to schedule a fresh render instead of
			# stranding pending_refresh or accepting this incomplete render key.
			render_key=""
			pending_refresh=false
			if is_visible_in_tree(): _request_refresh()
			return
		var captured: Image=viewport.get_texture().get_image()
		if captured!=null and not captured.is_empty():
			completed_previews[completed_key]={"texture":ImageTexture.create_from_image(captured),"terrain":_terrain_diagnostics()}
			completed_order.erase(completed_key)
			completed_order.append(completed_key)
			while completed_order.size()>COMPLETED_PREVIEW_LIMIT: completed_previews.erase(completed_order.pop_front())
		if pending_refresh:
			pending_refresh=false
			_request_refresh()

func _configure_lighting() -> void:
	if is_instance_valid(remaster_visuals):
		remaster_visuals.apply_lighting(self)
		return
	# Restore the existing preview lighting if this control switches from an
	# authored world back to a legacy stage during the same app session.
	fill.light_energy=0.0
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	sun.shadow_bias=.10
	sun.shadow_normal_bias=.80
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
	sun.position=Vector3(-axis.x*18,30,-axis.y*18/sin(deg_to_rad(Presentation.elevation_for_stage(stage))))
	sun.look_at(Vector3.ZERO,Vector3.UP)
	sun.light_color=ambient.lerp(Color.WHITE,.25)
	sun.light_energy=.55 if actual_time=="night" else 1.45*brightness
	environment.ambient_light_color=ambient
	environment.ambient_light_energy=.35 if actual_time=="night" else .32*brightness
	sky_material.sky_top_color=Color("29384e") if actual_time=="night" else ambient.lerp(Color(.40,.49,.60),.52)
	sky_material.sky_horizon_color=Color("566477") if actual_time=="night" else ambient*.75
	sky_material.ground_horizon_color=Color("202723") if actual_time=="night" else Color(.37,.35,.28)

func _select_provider(authored: bool) -> void:
	if is_instance_valid(battlefield) and ((authored and battlefield is WorldAdapter) or (not authored and battlefield is Battlefield)): return
	if is_instance_valid(remaster_visuals):
		world.remove_child(remaster_visuals)
		remaster_visuals.queue_free()
		remaster_visuals=null
	if is_instance_valid(battlefield):
		world.remove_child(battlefield)
		battlefield.queue_free()
	battlefield=WorldAdapter.new() if authored else Battlefield.new()
	world.add_child(battlefield)

func _configure_authored_camera(value: Dictionary) -> void:
	# Same authored camera as play. Only viewport aspect differs; world bounds
	# and camera width are never stretched to fit a menu thumbnail.
	var geometry: Dictionary=value.worldGeometry
	var settings: Dictionary=geometry.get("camera",{})
	var bounds: Dictionary=geometry.simulationBounds
	var target_values: Array=settings.get("worldTarget",[float(bounds.x)+float(bounds.width)*.5,0.0,float(bounds.z)+float(bounds.depth)*.5])
	var target:=Vector3(float(target_values[0]),float(target_values[1]),float(target_values[2]))
	var elevation: float=float(settings.get("elevationDegrees",ELEVATION))
	camera.size=float(settings.get("size",WORLD_WIDTH))
	camera.position=target+Vector3(0,30.0,30.0/tan(deg_to_rad(elevation)))
	camera.look_at(target,Vector3.UP)

func _terrain_diagnostics() -> Dictionary:
	var details: Dictionary=battlefield.diagnostics() if is_instance_valid(battlefield) else {}
	if is_instance_valid(remaster_visuals): details["remasterVisuals"]=remaster_visuals.diagnostics()
	return details

func diagnostics() -> Dictionary:
	return {"stageId":str(stage.get("id","")),"nativeBattlefield":is_instance_valid(battlefield),"authoredWorld":not stage.get("worldGeometry",{}).is_empty(),"static":true,"processing":is_processing(),"mouseIgnore":mouse_filter==Control.MOUSE_FILTER_IGNORE,"renderRequests":render_requests,"viewportSize":viewport.size if viewport!=null else Vector2i.ZERO,"updateMode":viewport.render_target_update_mode if viewport!=null else SubViewport.UPDATE_DISABLED,"worldWidth":camera.size if camera!=null else WORLD_WIDTH,"elevation":float(stage.get("worldGeometry",{}).get("camera",{}).get("elevationDegrees",Presentation.elevation_for_stage(stage))),"frameBudgetUsec":Battlefield.preview_frame_budget(frame_budget_usec),"loading":is_loading(),"cacheHit":cache_hit,"cachedPreviewCount":completed_previews.size(),"terrain":cached_terrain.duplicate(true) if cache_hit else _terrain_diagnostics()}
