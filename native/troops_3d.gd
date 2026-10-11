extends Control

const Actor = preload("res://native/sengoku_actor_3d.gd")
const ActorMaterials = preload("res://native/actor_materials.gd")
const Battlefield = preload("res://native/battlefield_3d.gd")
const BattlefieldNavigation = preload("res://native/battlefield_navigation.gd")
const TerrainLightField = preload("res://native/terrain_light_field.gd")
const EnemyFortification = preload("res://native/enemy_fortification_3d.gd")
const MobileObjectiveCart = preload("res://native/mobile_objective_cart_3d.gd")
const BattlefieldPresentation = preload("res://native/battlefield_presentation.gd")
const TroopActions = preload("res://native/troop_action_presentation.gd")
var action_presentation: RefCounted = TroopActions.new()
var presentation_mirrored: bool = false
const DEFAULT_ACTOR_BASE_SCALE: float = 0.70
const SAMURAI_BODY_SCALE: float = 1.07
var battle: Node2D
var stage: Dictionary = {}
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var output: TextureRect
var external_viewport_consumer: bool = false
var actors: Dictionary = {}
var fortifications: Dictionary = {}
var support_rocks: Dictionary = {}
var support_flags: Dictionary = {}
var mobile_objectives: Dictionary = {}
var visual_profiles: Dictionary = {}
var field_size: Vector2 = Vector2(1100,620)
var world_width: float = 18.5
var elevation_degrees: float = 50.0
var world_depth: float = 13.0
var friendly_formation_count: int = 1
var manual_states: Array = []
var battlefield: Node3D
var terrain_navigation: RefCounted = BattlefieldNavigation.new()
var navigation_fingerprint: String = ""
var navigation_battle_generation: int = -1
var navigation_segment_binding: Callable
var navigation_placement_binding: Callable
var world_geometry_signature: String = ""
var authored_world_active: bool = false
var legacy_world_width: float = 18.5
var torch_lights: Array = []
var motion_tracks: Dictionary = {}
var contact_shadows: Dictionary = {}
var contact_material: ShaderMaterial
var side_overlay: Node2D
var side_markers: Array = []
var placement_actor: Node3D
var placement_identity: String = ""
var placement_clock: float = 0.0
var ui_deployment_preview: Dictionary = {}
var local_light_field: RefCounted
var local_light_tracks: Dictionary = {}
var local_light_updates: int = 0
var light_clock: float = -1.0
var render_layer: Dictionary = {}
var render_lighting_signature: String = ""
const FRIENDLY_SIDE_COLOR: Color = Color("67c6ff")
const HOSTILE_SIDE_COLOR: Color = Color("ff6472")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -1
	viewport = SubViewport.new()
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = world_width
	camera.near = 0.1
	camera.far = 90.0
	camera.current = true
	world.add_child(camera)
	var lighting: WorldEnvironment = WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0,0,0,0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.55
	environment.ambient_light_energy = 0.5
	var sky: Sky = Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.42,0.51,0.61)
	sky_material.sky_horizon_color = Color(0.74,0.76,0.72)
	sky_material.ground_horizon_color = Color(0.39,0.37,0.30)
	sky_material.ground_bottom_color = Color(0.19,0.20,0.18)
	sky.sky_material = sky_material
	environment.sky = sky
	lighting.environment = environment
	world.add_child(lighting)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.65
	sun.light_color = Color(1.0,0.95,0.83)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.10
	sun.shadow_normal_bias = 0.80
	sun.directional_shadow_fade_start = 1.0
	# One fixed orthographic battlefield has no far terrain to justify split
	# cascades. Keep real joint shadows while avoiding duplicate shadow draws.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	world.add_child(sun)
	fill = DirectionalLight3D.new()
	fill.light_energy = 0.26
	fill.light_color = Color(0.60,0.70,0.83)
	fill.rotation_degrees = Vector3(-50,145,0)
	fill.shadow_enabled = false
	fill.light_cull_mask = 2
	world.add_child(fill)
	_load_profiles()
	battlefield=Battlefield.new()
	world.add_child(battlefield)
	contact_material=ActorMaterials.contact_shadow_material()
	output = TextureRect.new()
	output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	output.texture = viewport.get_texture()
	output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	output.stretch_mode = TextureRect.STRETCH_SCALE
	output.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(output)
	output.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Flat faction glyphs stay legible at battlefield scale. They follow the
	# exact projected ground anchor and are separate from HP/impact feedback.
	side_overlay = Node2D.new()
	side_overlay.name = "FactionFootMarkers"
	side_overlay.z_as_relative = false
	side_overlay.z_index = 2046
	side_overlay.draw.connect(_draw_side_markers)
	add_child(side_overlay)
	elevation_degrees = BattlefieldPresentation.elevation_for_stage(stage)
	set_field_size(field_size)
	set_stage(stage)

func _load_profiles() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://native/visual_profiles.json"))
	if data is Dictionary:
		for profile in data.get("profiles", []):
			visual_profiles[str(profile.get("stageId",""))] = profile

func _sync_contact_shadow(key: String, actor: Node3D, data: Dictionary) -> void:
	if not contact_shadows.has(key):
		var shadow = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(0.60,0.46) if actor.unit_type!="commander" else Vector2(0.82,1.38)
		shadow.mesh = plane
		shadow.material_override = contact_material
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shadow.layers = 1
		world.add_child(shadow)
		contact_shadows[key] = shadow
	var shadow: MeshInstance3D = contact_shadows[key]
	var footprint = Vector2(0.60,0.46) if actor.unit_type!="commander" else Vector2(0.82,1.38)
	if shadow.mesh.size!=footprint:
		shadow.mesh.size = footprint
	# This is ground occlusion beneath standing feet, not a silhouette shadow.
	# Actual directional shadows still come from the articulated model.
	shadow.visible = not bool(data.get("sailing",false)) and str(data.get("animation",""))!="death"
	var position_value: Vector3 = Vector3(actor.position.x,actor.position.y+.002,actor.position.z)
	if shadow.position!=position_value: shadow.position = position_value
	if shadow.rotation.y!=actor.rotation.y: shadow.rotation.y = actor.rotation.y
	if shadow.scale!=actor.scale: shadow.scale = actor.scale

func set_field_size(value: Vector2) -> void:
	field_size = Vector2(maxf(2.0,value.x),maxf(2.0,value.y))
	size = field_size
	if viewport == null:
		return
	viewport.size = Vector2i(roundi(field_size.x),roundi(field_size.y))
	_update_camera_projection()
	if is_instance_valid(battlefield): battlefield.configure(stage,world_width,world_depth,elevation_degrees)
	for torch in torch_lights:
		torch.position = normalized_to_world(torch.get_meta("normalized_point",Vector2.ZERO))+Vector3(0,0.65,0)
	_bind_terrain_navigation()
	if sun!=null and not stage.is_empty(): _configure_stage_lighting(false)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_external_viewport_consumer(active: bool) -> void:
	if external_viewport_consumer == active: return
	external_viewport_consumer = active
	if viewport != null:
		# A learning card can consume the scene while this Control is hidden.
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _update_camera_projection() -> void:
	var aspect: float = field_size.x/field_size.y
	if uses_world_geometry():
		var bounds: Dictionary = stage.get("worldGeometry",{}).get("simulationBounds",{})
		if not authored_world_active: legacy_world_width = world_width
		authored_world_active = true
		world_width = float(bounds.get("width",world_width))
		world_depth = float(bounds.get("depth",world_depth))
		if not is_instance_valid(camera): return
		var settings: Dictionary = stage.get("worldGeometry",{}).get("camera",{})
		var center: Vector3 = normalized_to_world(Vector2(.5,.5))
		var target: Vector3 = Vector3(float(bounds.get("x",0))+world_width*.5,center.y if center.is_finite() else 0.0,float(bounds.get("z",0))+world_depth*.5)
		var requested: Variant = settings.get("worldTarget",null)
		if requested is Array and requested.size() == 3:
			var requested_target: Vector3 = Vector3(float(requested[0]),float(requested[1]),float(requested[2]))
			if requested_target.is_finite(): target = requested_target
		var fit: float = maxf(world_width,world_depth*sin(deg_to_rad(elevation_degrees))*aspect)*1.08
		var requested_size: float = float(settings.get("size",fit))
		camera.size = requested_size if is_finite(requested_size) and requested_size > 0 else fit
		camera.position = target+Vector3(0,30.0,30.0/tan(deg_to_rad(elevation_degrees)))
		camera.look_at(target,Vector3.UP)
		return
	if authored_world_active:
		world_width = legacy_world_width
		authored_world_active = false
	world_depth = world_width/aspect/sin(deg_to_rad(elevation_degrees))
	if not is_instance_valid(camera): return
	camera.size = world_width
	camera.position = Vector3(0,30.0,30.0/tan(deg_to_rad(elevation_degrees)))
	camera.look_at(Vector3.ZERO,Vector3.UP)

func set_stage(value: Dictionary) -> void:
	var previous_elevation: float = elevation_degrees
	var previous_stage_id: String = str(stage.get("id",""))
	var previous_geometry: String = world_geometry_signature
	stage = value.duplicate(true)
	world_geometry_signature = JSON.stringify(stage.get("worldGeometry",{})).sha256_text()
	elevation_degrees = BattlefieldPresentation.elevation_for_stage(stage)
	var camera_settings: Dictionary = stage.get("worldGeometry",{}).get("camera",{})
	var authored_elevation: float = float(camera_settings.get("elevationDegrees",elevation_degrees))
	if is_finite(authored_elevation): elevation_degrees = clampf(authored_elevation,35,65)
	if previous_stage_id != str(stage.get("id","")) or previous_geometry != world_geometry_signature or not is_equal_approx(previous_elevation,elevation_degrees):
		motion_tracks.clear()
		navigation_fingerprint = ""
	_update_camera_projection()
	presentation_mirrored = BattlefieldPresentation.mirror_for_stage(stage)
	if output!=null: output.flip_h=presentation_mirrored
	for cart in mobile_objectives.values(): cart.reset_motion()
	local_light_tracks.clear()
	light_clock = -1.0
	if is_instance_valid(battlefield): battlefield.configure(stage,world_width,world_depth,elevation_degrees)
	_update_camera_projection()
	_bind_terrain_navigation()
	if is_instance_valid(placement_actor):
		placement_actor.hide()
	if sun == null:
		return
	_configure_stage_lighting()
	for torch in torch_lights:
		torch.queue_free()
	torch_lights.clear()
	for torch_config in stage.get("torches",[]):
		var torch: OmniLight3D = OmniLight3D.new()
		var normalized_point: Vector2 = Vector2(float(torch_config.x),float(torch_config.y))
		torch.set_meta("normalized_point",normalized_point)
		torch.position = normalized_to_world(normalized_point)+Vector3(0,0.65,0)
		torch.light_color = Color("e5a766")
		torch.light_energy = 0.65
		torch.omni_range = 3.2
		torch.omni_attenuation = 1.7
		torch.light_cull_mask = 2
		torch.shadow_enabled = false
		world.add_child(torch)
		torch_lights.append(torch)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _configure_stage_lighting(force: bool = true) -> void:
	var next_layer: Dictionary = battlefield.render_layer_contract() if is_instance_valid(battlefield) and battlefield.has_method("render_layer_contract") else {"mode":"native","lighting":{}}
	var next_signature: String = (JSON.stringify(next_layer)+":%.5f"%elevation_degrees).sha256_text()
	# Main can lay out unchanged field dimensions while a caption/production
	# card changes. Preserve the existing fifteen-Hz fade in that case.
	if not force and next_signature==render_lighting_signature: return
	render_layer = next_layer
	render_lighting_signature = next_signature
	local_light_field = null
	local_light_tracks.clear()
	light_clock = -1.0
	# Actors persist across same-ID resets. A native terrain stage must not keep
	# an earlier artwork's exposure/tint, and a new painting samples afresh.
	for actor in actors.values(): actor.set_local_light(1.0,Color.WHITE,1.0,0.0)
	for prop in fortifications.values(): prop.set_local_light(1.0,Color.WHITE,1.0,0.0)
	for cart in mobile_objectives.values(): cart.set_local_light(1.0,Color.WHITE,1.0,0.0)
	if is_instance_valid(placement_actor): placement_actor.set_local_light(1.0,Color.WHITE,1.0,0.0)
	var lighting: Dictionary = render_layer.get("lighting",{})
	var artwork: bool = str(render_layer.get("mode","native")) in ["rendered","legacy_preview"]
	if artwork and not str(render_layer.get("artPath","")).is_empty():
		local_light_field = TerrainLightField.new()
		local_light_field.configure({"background":str(render_layer.artPath),"sourceRevision":str(render_layer.get("artSha256",""))})
	var profile: Dictionary = visual_profiles.get(str(stage.get("id","")),{})
	var history: Dictionary=stage.get("historicalBattlefield",{})
	var time_data: Variant=history.get("timeOfDay","day")
	var actual_time: String=str(time_data.get("key",time_data.get("value","day"))) if time_data is Dictionary else str(time_data)
	var weather_data: Variant=history.get("weather",{})
	var actual_weather: String=str(weather_data.get("kind",weather_data.get("key","unknown"))) if weather_data is Dictionary else str(weather_data)
	var weather_presentation: Dictionary=history.get("presentationWeather",{})
	if not weather_presentation.is_empty(): actual_weather=str(weather_presentation.get("sky",actual_weather))
	var ambient: Color = _lighting_colour(lighting.get("ambientTint",null),Color("e4e1cb") if artwork else Color("dce6e2"))
	var brightness: float=.85 if actual_weather in ["rain","cloudy","overcast","rain_clouds_wet_ground_reported"] else 1.0
	var shadow_direction: Dictionary = lighting.get("shadowDirection",profile.get("shadowDirection",{"x":-0.65,"y":0.4}))
	var shadow_axis: Vector2 = Vector2(float(shadow_direction.get("x",-.65)),float(shadow_direction.get("y",.4)))
	if not shadow_axis.is_finite() or shadow_axis.is_zero_approx(): shadow_axis=Vector2(-.65,.4)
	shadow_axis=shadow_axis.normalized()
	sun.position = Vector3(-shadow_axis.x*18.0,30.0,-shadow_axis.y*18.0/sin(deg_to_rad(elevation_degrees)))
	sun.look_at(Vector3.ZERO,Vector3.UP)
	# The shadow-receiver shader preserves the painting's own light and colour.
	# Only the original live PBR actors receive the authored warm key and fill.
	sun.light_cull_mask = 3
	sun.light_color = _lighting_colour(lighting.get("keyTint",null),Color("fff1d5") if artwork else ambient.lerp(Color.WHITE,.25))
	sun.light_energy = _lighting_energy(lighting.get("keyEnergy",null),1.12 if artwork else 1.45*brightness)
	environment.ambient_light_color = ambient
	environment.ambient_light_energy = _lighting_energy(lighting.get("ambientEnergy",null),.32*brightness)
	sky_material.sky_top_color = ambient.lerp(Color(0.40,0.49,0.60),0.52)
	sky_material.sky_horizon_color = ambient*0.75
	sky_material.ground_horizon_color = Color(0.37,0.35,0.28)
	if actual_time=="night":
		sun.light_energy = _lighting_energy(lighting.get("keyEnergy",null),.55)
		fill.light_energy = _lighting_energy(lighting.get("fillEnergy",null),.32)
		environment.ambient_light_energy = _lighting_energy(lighting.get("ambientEnergy",null),.35)
		sky_material.sky_top_color = Color("29384e")
		sky_material.sky_horizon_color = Color("566477")
		sky_material.ground_horizon_color = Color("202723")
	else:
		fill.light_energy = _lighting_energy(lighting.get("fillEnergy",null),.12 if artwork else .30)
	fill.light_cull_mask = 2
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

static func _lighting_colour(value: Variant, fallback: Color) -> Color:
	if value is String: return Color.from_string(value,fallback)
	if value is Color: return value
	return fallback

static func _lighting_energy(value: Variant, fallback: float) -> float:
	return clampf(float(value),0.0,3.0) if (value is float or value is int) and is_finite(float(value)) else fallback

func refresh_rendered_art() -> void:
	if is_instance_valid(battlefield) and battlefield.has_method("refresh_rendered_art"): battlefield.refresh_rendered_art()
	_bind_terrain_navigation()
	if sun!=null: _configure_stage_lighting()

func bind_battle(value: Node2D) -> void:
	if battle != value:
		_clear_owned_navigation()
		motion_tracks.clear()
		navigation_fingerprint = ""
		navigation_battle_generation = -1
	battle = value
	if action_presentation.battle != value: action_presentation.bind(value)
	if is_instance_valid(battle) and battle.has_method("bind_render_projection"): battle.bind_render_projection(self)
	_bind_terrain_navigation()

func health_anchor_for(actor_id: int) -> Dictionary:
	for marker in side_markers:
		if int(marker.id)==actor_id and int(marker.member)==0:
			return {"headPosition":marker.healthAnchor,"footPosition":marker.position,"hp":float(marker.hp),"maxHp":float(marker.maxHp),"friendly":bool(marker.friendly),"flags":marker.get("healthFlags",{})}
	return {}

func normalized_to_world(point: Vector2) -> Vector3:
	return battlefield.world_point(point) if is_instance_valid(battlefield) else Vector3((point.x-0.5)*world_width,0,(point.y-0.5)*world_depth)

func _world_heading(point: Vector2, direction: Vector2) -> Vector3:
	# Face travel in the provider's actual world axes and lengths.
	if direction.length_squared()<.000000001: return Vector3.ZERO
	var step: Vector2=direction.normalized()*.006
	var heading: Vector3=normalized_to_world(point+step)-normalized_to_world(point-step)
	heading.y=0.0
	return heading

func _forest_approach_cover(point: Vector2) -> float:
	var history: Dictionary=stage.get("historicalBattlefield",{})
	if str(history.get("materialTheme",""))!="forest_ground": return 0.0
	var cover: float=0.0
	for site in history.get("ambushClearings",[]):
		if str(site.get("role",""))!="external_ambush_cover": continue
		var center: Vector2=Vector2(float(site.get("x",0)),float(site.get("y",0)))
		var radius: float=maxf(.01,float(site.get("r",.024)))
		cover=maxf(cover,1.0-smoothstep(radius,radius+.045,point.distance_to(center)))
	for landmark in history.get("sceneLandmarks",[]):
		if str(landmark.get("kind","")) not in ["forest","woodland","grove","tree_cover"]: continue
		var size: Dictionary=landmark.get("scale",{})
		var radius: Vector2=Vector2(maxf(.01,float(size.get("w",.08))*.5),maxf(.01,float(size.get("h",.08))*.5))
		var offset: Vector2=(point-Vector2(float(landmark.get("x",0)),float(landmark.get("y",0))))/radius
		cover=maxf(cover,1.0-smoothstep(.7,1.2,offset.length()))
	return clampf(cover,0.0,1.0)

func _ground_contact_height(world_point_value: Vector3) -> float:
	if uses_world_geometry():
		return float(battlefield.sample_world_height(world_point_value))
	if not is_instance_valid(battlefield) or not battlefield.has_method("height_at"): return 0.0
	var grid_height: float=_native_grid_contact_height(world_point_value)
	if is_finite(grid_height): return grid_height
	# Recover the terrain coordinate from X/Z without treating a lifted foot's
	# Y as terrain height. The existing artwork projection shear is unchanged.
	var normalized: Vector2=Vector2(world_point_value.x/world_width+.5,world_point_value.z/world_depth+.5)
	var shear: float=tan(deg_to_rad(elevation_degrees))
	# Fixed-point height subtraction can oscillate on a steep slope, choosing
	# a different patch of ground for the next foot sample. Solve the actual
	# sheared Z equation with the local terrain derivative instead.
	for iteration in range(8):
		var height: float=float(battlefield.height_at(normalized))
		var residual: float=(normalized.y-.5)*world_depth+height/shear-world_point_value.z
		if absf(residual)<.0005: break
		var slope: float=(float(battlefield.height_at(normalized+Vector2(0,.0005)))-float(battlefield.height_at(normalized-Vector2(0,.0005))))/.001
		var derivative: float=world_depth+slope/shear
		if absf(derivative)<.1: break
		normalized.y-=clampf(residual/derivative,-.04,.04)
	var final_height: float=float(battlefield.height_at(normalized))
	var final_residual: float=(normalized.y-.5)*world_depth+final_height/shear-world_point_value.z
	return final_height if absf(final_residual)<.0005 else NAN

func _native_grid_contact_height(world_point_value: Vector3) -> float:
	# Native height_at and the ground mesh share the same two linear triangles.
	# For fixed X, each triangle is h(ny)=slope*ny+intercept; invert its sheared
	# Z analytically. Other providers retain the Newton sampler above.
	if not battlefield is Battlefield: return NAN
	var terrain: Battlefield=battlefield as Battlefield
	var grid: PackedFloat32Array=terrain.heights
	if grid.size()!=(Battlefield.GRID_X+1)*(Battlefield.GRID_Y+1): return NAN
	var span: float=1.0+Battlefield.GRID_BORDER*2.0
	var grid_y_scale: float=Battlefield.GRID_Y/span
	var gx: float=clampf((world_point_value.x/world_width+.5+Battlefield.GRID_BORDER)/span*Battlefield.GRID_X,0.0,Battlefield.GRID_X-.0001)
	var column: int=floori(gx)
	var fx: float=gx-column
	var shear: float=tan(deg_to_rad(elevation_degrees))
	# Projection shear can fold a steep ridge over itself. Choose the actual
	# triangle nearest the foot's Y, rather than whichever branch Newton finds.
	var starting_ny: float=(world_point_value.z-world_point_value.y/shear)/world_depth+.5
	var starting_row: int=clampi(floori((starting_ny+Battlefield.GRID_BORDER)*grid_y_scale),0,Battlefield.GRID_Y-1)
	var nearest: float=NAN
	var nearest_error: float=INF
	# height_at extends the edge height beyond the mesh's padded boundary.
	for edge in [0,Battlefield.GRID_Y]:
		var edge_index: int=edge*(Battlefield.GRID_X+1)+column
		var edge_height: float=lerpf(grid[edge_index],grid[edge_index+1],fx)
		var edge_ny: float=(world_point_value.z-edge_height/shear)/world_depth+.5
		var edge_limit: float=edge/grid_y_scale-Battlefield.GRID_BORDER
		if (edge==0 and edge_ny<edge_limit) or (edge==Battlefield.GRID_Y and edge_ny>edge_limit):
			var error: float=absf(edge_height-world_point_value.y)
			if error<nearest_error: nearest=edge_height;nearest_error=error
	for radius in range(Battlefield.GRID_Y):
		for direction in [-1,1]:
			if radius==0 and direction==1: continue
			var row: int=starting_row+radius*direction
			if row<0 or row>=Battlefield.GRID_Y: continue
			var index: int=row*(Battlefield.GRID_X+1)+column
			var h00: float=grid[index]
			var h10: float=grid[index+1]
			var h01: float=grid[index+Battlefield.GRID_X+1]
			var h11: float=grid[index+Battlefield.GRID_X+2]
			var row_ny: float=row/grid_y_scale-Battlefield.GRID_BORDER
			for triangle in [0,1]:
				var slope: float=((h01-h00) if triangle==0 else (h11-h10))*grid_y_scale
				var base_height: float=h00+(h10-h00)*fx if triangle==0 else h11+(h01-h11)*(1.0-fx)+(h10-h11)
				var denominator: float=world_depth+slope/shear
				if absf(denominator)<.000001: continue
				var ny: float=(world_point_value.z+world_depth*.5-(base_height-slope*row_ny)/shear)/denominator
				var fy: float=(ny+Battlefield.GRID_BORDER)*grid_y_scale-row
				# Float32 mesh coordinates can fall a few micrometres across an
				# edge. Clamp to the real triangle and validate its projected surface.
				var bounded_fy: float=clampf(fy,0.0,1.0-fx) if triangle==0 else clampf(fy,1.0-fx,1.0)
				ny=row_ny+bounded_fy/grid_y_scale
				var height: float=base_height+slope*(ny-row_ny)
				if absf((ny-.5)*world_depth+height/shear-world_point_value.z)>.000005: continue
				var error: float=absf(height-world_point_value.y)
				if error<nearest_error: nearest=height;nearest_error=error
		# Any unvisited row is farther in normalized Y. At fixed X/Z the exact
		# height distance is depth*shear*Y distance, so this bounds all other hits.
		var lower_row: int=maxi(0,starting_row-radius)
		var upper_row: int=mini(Battlefield.GRID_Y-1,starting_row+radius)
		var remaining_distance: float=INF
		if lower_row>0:
			remaining_distance=maxf(0.0,starting_ny-(lower_row/grid_y_scale-Battlefield.GRID_BORDER))
		if upper_row<Battlefield.GRID_Y-1:
			remaining_distance=minf(remaining_distance,maxf(0.0,(upper_row+1)/grid_y_scale-Battlefield.GRID_BORDER-starting_ny))
		if is_finite(nearest) and remaining_distance*world_depth*shear>=nearest_error+.000007: return nearest
	return nearest

func _terrain_approach_profile(data: Dictionary, point: Vector2) -> Dictionary:
	var result: Dictionary={"cover":0.0,"pitch":0.0,"roll":0.0,"enabled":false}
	if str(data.get("animation",""))!="walk" or bool(data.get("sailing",false)) or bool(data.get("dead",false)): return result
	if not is_instance_valid(battlefield) or not battlefield.has_method("height_at"): return result
	var forward: Vector2=Vector2(float(data.get("aimX",0)),float(data.get("aimY",0))).normalized()
	if forward.length_squared()<.5: return result
	var across: Vector2=forward.orthogonal()
	var step: float=.006
	var horizontal: float=Vector2(forward.x*world_width,forward.y*world_depth).length()*step*2.0
	var lateral: float=Vector2(across.x*world_width,across.y*world_depth).length()*step*2.0
	var front: float = float(battlefield.height_at(point+forward*step))
	var back: float = float(battlefield.height_at(point-forward*step))
	var left: float = float(battlefield.height_at(point+across*step))
	var right: float = float(battlefield.height_at(point-across*step))
	if not is_finite(front) or not is_finite(back) or not is_finite(left) or not is_finite(right): return result
	result.pitch=clampf(atan2(front-back,horizontal),-.28,.28)
	result.roll=clampf(atan2(left-right,lateral),-.22,.22)
	result.enabled=true
	# Every marching foot soldier responds to the same real ground. Only the
	# hostile emplacement crew uses its existing concealed-approach crouch.
	if not bool(data.get("friendly",false)) and str(data.get("combatRole",""))=="emplacement_assault" and str(data.get("hunterState","")) in ["ingress","approach"]: result.cover=_forest_approach_cover(point)
	return result

func _boat_water_visual(point: Vector2) -> bool:
	if is_instance_valid(battle):
		for water in battle.ground_combat.water_rects:
			if water.has_point(point): return not battle.ground_combat.land_segment_safe(point,point,.002)
		return false
	var waters: Array=stage.get("historicalBattlefield",{}).get("waterFeatures",[]).duplicate()
	var primary: Dictionary=stage.get("water",{})
	if not primary.is_empty(): waters.append(primary)
	for feature in waters:
		if not bool(feature.get("blocksMovement",true)): continue
		var rect: Rect2=Rect2(float(feature.get("x",0)),float(feature.get("y",0)),float(feature.get("w",0)),float(feature.get("h",0)))
		if rect.has_point(point): return true
	return false

func project_world_to_field(point: Vector3) -> Vector2:
	if not is_instance_valid(camera) or not is_instance_valid(viewport): return Vector2.ZERO
	var projected: Vector2=camera.unproject_position(point)*field_size/Vector2(viewport.size)
	return BattlefieldPresentation.pixel_to_view(projected,field_size,presentation_mirrored)

func world_to_normalized(point: Vector3) -> Vector2:
	if uses_world_geometry(): return battlefield.world_to_normalized(point)
	# Terrain height is sheared into world Z so the projected ground anchor
	# matches the 2D authored point. Undo that shear before artwork sampling.
	return Vector2(point.x/world_width+.5,(point.z-point.y/tan(deg_to_rad(elevation_degrees)))/world_depth+.5)

func uses_world_geometry() -> bool:
	return is_instance_valid(battlefield) and battlefield.has_method("supports_world_geometry") and bool(battlefield.supports_world_geometry())

func model_to_field_point(point: Vector2) -> Vector2:
	var actual: Vector3 = normalized_to_world(point)
	return project_world_to_field(actual) if actual.is_finite() else Vector2(INF,INF)

func screen_to_model_point(global_pointer: Vector2) -> Dictionary:
	if not uses_world_geometry() or not is_instance_valid(camera) or not is_instance_valid(viewport): return {"valid":false}
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse()*global_pointer
	if not Rect2(Vector2.ZERO,field_size).has_point(local): return {"valid":false}
	var pixel: Vector2 = BattlefieldPresentation.pixel_to_view(local,field_size,presentation_mirrored)*Vector2(viewport.size)/field_size
	return battlefield.ray_pick(camera.project_ray_origin(pixel),camera.project_ray_normal(pixel))

func set_terrain_provider(provider: Node3D) -> void:
	if not is_instance_valid(provider) or not provider.has_method("world_point") or not provider.has_method("configure"): return
	if provider.has_method("supports_world_geometry"):
		for method in ["world_to_normalized","sample_world_height","ray_pick","height_at","segment_clear","placement_clear"]:
			if not provider.has_method(method):
				push_error("Authored terrain provider lacks " + str(method))
				return
	_clear_owned_navigation()
	if is_instance_valid(battlefield) and battlefield!=provider:
		battlefield.hide()
		if battlefield.get_parent()==world: world.remove_child(battlefield);battlefield.queue_free()
	battlefield=provider
	if provider.get_parent()==null: world.add_child(provider)
	battlefield.configure(stage,world_width,world_depth,elevation_degrees)
	_update_camera_projection()
	motion_tracks.clear()
	navigation_fingerprint = ""
	_bind_terrain_navigation()
	if sun!=null: _configure_stage_lighting()
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func actor_base_scale() -> float:
	var profile: Dictionary = visual_profiles.get(str(stage.get("id","")),{})
	return clampf(float(profile.get("actorBaseScale",DEFAULT_ACTOR_BASE_SCALE)),0.4,1.3)

func _bind_terrain_navigation() -> void:
	if not is_instance_valid(battle) or not is_instance_valid(battlefield) or stage.is_empty():
		return
	if str(battle.config.get("id","")) != str(stage.get("id","")):
		return
	if uses_world_geometry():
		var scene_key: String = "%d:%s" % [battlefield.get_instance_id(),world_geometry_signature]
		var segment: Callable = Callable(battlefield,"segment_clear")
		var placement: Callable = Callable(battlefield,"placement_clear")
		if navigation_fingerprint == scene_key and navigation_battle_generation == battle.battle_generation and battle.structure_placement_clear == placement and battle.ground_combat.structure_segment_clear == segment:
			return
		battle.bind_terrain_navigation(segment,placement)
		navigation_segment_binding = segment
		navigation_placement_binding = placement
		navigation_fingerprint = scene_key
		navigation_battle_generation = battle.battle_generation
		return
	if not battlefield.has_method("world_point") or not "structural_parts" in battlefield:
		return
	var scene_key: String = "%d:%s:%d:%s" % [battlefield.get_instance_id(),battlefield.geometry_fingerprint,battlefield.rebuild_count,battlefield.render_signature]
	if navigation_fingerprint == scene_key and navigation_battle_generation == battle.battle_generation and battle.structure_placement_clear.is_valid():
		return
	if navigation_fingerprint != scene_key:
		terrain_navigation.capture_current(battlefield.structural_parts,Callable(battlefield,"world_point"),world_width,world_depth)
		navigation_fingerprint = scene_key
	navigation_segment_binding = Callable(terrain_navigation,"segment_clear")
	navigation_placement_binding = Callable(terrain_navigation,"placement_clear")
	battle.bind_terrain_navigation(navigation_segment_binding,navigation_placement_binding)
	navigation_battle_generation = battle.battle_generation

func _clear_owned_navigation() -> void:
	if is_instance_valid(battle):
		if battle.structure_placement_clear == navigation_placement_binding: battle.structure_placement_clear = Callable()
		if battle.ground_combat.structure_segment_clear == navigation_segment_binding: battle.ground_combat.structure_segment_clear = Callable()
		if battle.ground_combat.structure_placement_clear == navigation_placement_binding: battle.ground_combat.structure_placement_clear = Callable()
	navigation_segment_binding = Callable()
	navigation_placement_binding = Callable()

func _exit_tree() -> void:
	action_presentation.unbind()
	_clear_owned_navigation()
	terrain_navigation.invalidate()

func _render_scale(profile: Dictionary, point: Vector2, data: Dictionary) -> float:
	var perspective: Dictionary = profile.get("perspective",{})
	var result: float = actor_base_scale()*lerpf(float(perspective.get("farScale",0.90)),float(perspective.get("nearScale",1.10)),clampf(point.y,0,1))
	if str(data.get("kind",""))=="commander":
		result *= 1.10
	elif str(data.get("kind",""))=="heavy":
		result *= 1.04
	if str(data.get("type", "")) == "samurai":
		result *= SAMURAI_BODY_SCALE
	return result

func render_scale_for(point: Vector2, data: Dictionary = {}) -> float:
	# FX anchors and placement previews use this same scale as the actor and
	# its contact shadow. No combat range, collision or logical point changes.
	return _render_scale(visual_profiles.get(str(stage.get("id", "")), {}), point, data)

func _process(delta: float) -> void:
	if viewport == null:
		return
	if not is_visible_in_tree():
		if is_instance_valid(placement_actor) and placement_actor.visible:
			placement_actor.hide()
			if external_viewport_consumer:
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		# UPDATE_ONCE is consumed by the renderer; the SubViewport getter can
		# retain ONCE. Clear the node property only after the requested draw.
		if external_viewport_consumer and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE:
			if not RenderingServer.frame_post_draw.is_connected(_finish_hidden_viewport_draw):
				RenderingServer.frame_post_draw.connect(_finish_hidden_viewport_draw,CONNECT_ONE_SHOT)
		else:
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var states: Array = manual_states
	if is_instance_valid(battle):
		states = battle.actor_states()
	sync_actor_states(states)
	if is_instance_valid(battle) and battle.ui_deployment_active:
		sync_placement_preview(ui_deployment_preview,delta)
	elif is_instance_valid(battle) and battle.has_method("placement_preview"):
		sync_placement_preview(battle.placement_preview(battle.placement_cursor),delta)
	else:
		sync_placement_preview({})

func _finish_hidden_viewport_draw() -> void:
	if is_instance_valid(viewport) and not is_visible_in_tree() and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _notification(what: int) -> void:
	if what==NOTIFICATION_VISIBILITY_CHANGED and viewport!=null and is_visible_in_tree():
		# Resume can expose a cached frame after a ghost was hidden in menus.
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func sync_placement_preview(data: Dictionary, delta: float = 0.0) -> void:
	if world == null:
		return
	var displayed: bool = bool(data.get("active",false)) and bool(data.get("visible",false)) and is_visible_in_tree()
	var position_data: Dictionary = data.get("position",{})
	var point: Vector2 = Vector2(float(position_data.get("x",-1)),float(position_data.get("y",-1)))
	if not displayed or not point.is_finite() or not Rect2(Vector2.ZERO,Vector2.ONE).has_point(point):
		if is_instance_valid(placement_actor) and placement_actor.visible:
			placement_actor.hide()
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	var type_name: String = str(data.get("type",""))
	if type_name.is_empty():
		if is_instance_valid(placement_actor) and placement_actor.visible:
			placement_actor.hide()
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	var evolution: int = clampi(int(data.get("evolution",0)),0,2)
	var identity: String = type_name+":"+str(evolution)
	if not is_instance_valid(placement_actor) or identity!=placement_identity:
		if is_instance_valid(placement_actor):
			placement_actor.hide()
			placement_actor.queue_free()
		placement_actor = Actor.new()
		placement_actor.name = "PlacementPreview"
		world.add_child(placement_actor)
		placement_actor.configure(type_name,false,1,false,evolution)
		placement_actor.set_meta("placement_preview",true)
		var preview_material: ShaderMaterial = ActorMaterials.placement_preview_material().duplicate(false)
		ActorMaterials.configure_actor_material(preview_material,false,type_name)
		placement_actor.materials["combined"] = preview_material
		for instance in placement_actor.meshes:
			instance.material_override = preview_material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		placement_identity = identity
		placement_clock = 0.0
		local_light_tracks.erase("placement")
	# Geometry uses exactly the committed snap position and battlefield scale.
	# This one actor belongs to no combat dictionary, side marker or shadow.
	var profile: Dictionary = visual_profiles.get(str(stage.get("id","")),{})
	var ground_point: Vector3 = normalized_to_world(point)
	if not ground_point.is_finite():
		placement_actor.hide()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	placement_actor.position = ground_point
	placement_actor.scale = Vector3.ONE*_render_scale(profile,point,{"type":type_name})
	placement_clock += maxf(0.0,delta)
	var preview_state: Dictionary = {"animation":"idle","animationClock":placement_clock,"animationPhase":0.0,"aimX":0.0,"aimY":-1.0,"sailing":false,"dead":false}
	if is_instance_valid(battlefield) and battlefield.has_method("height_at"):
		preview_state["groundHeightSampler"] = Callable(self,"_ground_contact_height")
	placement_actor.apply_state(preview_state)
	var preview_track: Dictionary = local_light_tracks.get("placement",{})
	var cursor_jump: bool = not preview_track.is_empty() and (preview_track.point as Vector2).distance_to(point)>.025
	_apply_local_light("placement",placement_actor,point,placement_clock,cursor_jump)
	placement_actor.show()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func sync_actor_states(states: Array) -> void:
	if world == null:
		return
	var clock: float = float(battle.animation_time) if is_instance_valid(battle) else 0.0
	if not states.is_empty():
		clock = float(states[0].get("motionTime",states[0].get("animationClock",clock)))
	var changed: bool = clock!=light_clock and not torch_lights.is_empty()
	if is_instance_valid(battle) and battle.has_method("field_markers"):
		changed = sync_field_markers(battle.field_markers(),float(battle.animation_time)) or changed
	_sync_torch_flicker(clock)
	_sync_support_rocks()
	var live: Dictionary = {}
	var live_ids: Dictionary = {}
	var generation: int = int(battle.battle_generation) if is_instance_valid(battle) else -1
	var surface_key: String = "%d:%s" % [battlefield.get_instance_id() if is_instance_valid(battlefield) else 0,world_geometry_signature]
	side_markers.clear()
	var profile: Dictionary = visual_profiles.get(str(stage.get("id","")),{})
	for source in states:
		live_ids[int(source.id)] = true
		var count: int = clampi(friendly_formation_count,1,3) if bool(source.get("friendly",false)) and not bool(source.get("transientSupport",false)) else 1
		for member in range(count):
			var key: String = "%s:%d" % [str(source.id),member]
			live[key] = true
			var actor: Actor
			var model_type: String = _model_type(source)
			var model_evolution: int = clampi(int(source.get("evolution",0)),0,2)
			if actors.has(key) and (actors[key].unit_type != model_type or actors[key].evolution_stage != model_evolution or actors[key].hostile == bool(source.get("friendly",false))):
				actors[key].queue_free()
				actors.erase(key)
				motion_tracks.erase(key)
				local_light_tracks.erase(key)
			if not actors.has(key):
				actor = Actor.new()
				world.add_child(actor)
				actor.configure(model_type,not bool(source.get("friendly",false)),int(source.id)+member*31,false,model_evolution)
				actors[key] = actor
				changed = true
			else:
				actor = actors[key]
			if actor.has_meta("departure"):
				# A fresh battle can reuse an ID. Never inherit the consumed fade.
				actor.materials.combined.set_shader_parameter("departure_fade",0.0)
				actor.remove_meta("departure")
			var point: Vector2 = Vector2(float(source.x),float(source.y))
			var data: Dictionary = source.duplicate()
			if not bool(data.get("dead",false)) and not bool(data.get("transientSupport",false)):
				data.merge(action_presentation.state_for_id(int(source.id)),true)
			if bool(data.get("sailing",false)): data.sailing=_boat_water_visual(point)
			if bool(data.get("transportActive",false)) and str(data.get("transportKind",""))=="boat":
				data.sailing=_boat_water_visual(point)
				if not bool(data.sailing) and not bool(data.get("dead",false)): data.animation="walk"
			if count > 1:
				var offset: Vector2 = [Vector2(-0.24,0.04),Vector2(0.24,0.09),Vector2(0,-0.19)][member]
				offset *= _render_scale(profile,point,data)
				point += Vector2(offset.x/world_width,offset.y/world_depth)
				data.animationPhase = float(data.get("animationPhase",0.0))+float(member)*0.18
			var position_value: Vector3 = normalized_to_world(point)
			if not position_value.is_finite():
				# Missing authored floor is not a fabricated standing surface.
				if actor.visible: changed = true
				actor.hide()
				actor.set_meta("pose_culled",true)
				for cache in [contact_shadows,fortifications,support_flags]:
					if cache.has(key): cache[key].hide()
				continue
			var render_scale: float = _render_scale(profile,point,data)
			# Models, mounts, boats and death poses share the same parent scale.
			# Terrain projection and every logical placement coordinate stay fixed.
			var scale_value: Vector3 = Vector3.ONE*render_scale
			if actor.scale!=scale_value: actor.scale = scale_value
			# Cull poses only beyond a generous projected body/weapon margin.
			# Projection includes camera framing/zoom, mirroring and each member's
			# formation offset; logical positions and combat snapshots stay live.
			var projected_ground: Vector2=project_world_to_field(position_value)
			var camera_width: float=maxf(.001,camera.size)
			var cull_margin: Vector2=Vector2(maxf(.35,render_scale*4.0/camera_width),maxf(.35,render_scale*4.0/camera_width*field_size.x/field_size.y))*field_size
			if not Rect2(-cull_margin,field_size+cull_margin*2.0).has_point(projected_ground):
				if actor.visible: changed=true
				actor.hide()
				actor.position=position_value
				actor.set_meta("pose_culled",true)
				for cache in [contact_shadows,fortifications,support_flags]:
					if cache.has(key): cache[key].hide()
				continue
			var returning_from_cull: bool=bool(actor.get_meta("pose_culled",false))
			if returning_from_cull:
				actor.show()
				actor.set_meta("pose_culled",false)
				for cache in [contact_shadows,fortifications,support_flags]:
					if cache.has(key): cache[key].show()
			var heading: Vector3=_world_heading(point,Vector2(float(data.get("aimX",0.0)),float(data.get("aimY",1.0))))
			var target_yaw: float = atan2(-heading.x,-heading.z)
			var motion_time: float = float(data.get("motionTime",data.get("animationClock",0.0)))
			if not uses_world_geometry() and bool(data.get("friendly",false)) and bool(data.get("deploying",false)) and str(data.get("animation","")) == "walk":
				var settling: float = clampf(1.0-float(data.get("animationClock",0.0))/0.35,0,1)
				position_value -= Vector3(-sin(target_yaw),0,-cos(target_yaw))*.24*render_scale*settling
			if actor.position!=position_value: actor.position = position_value
			var reset_motion: bool = not motion_tracks.has(key) or returning_from_cull
			var track: Dictionary = motion_tracks.get(key,{"point":actor.position,"time":motion_time,"phase":float(data.get("animationPhase",0.0)),"yaw":target_yaw})
			if int(track.get("generation",generation)) != generation or str(track.get("surface",surface_key)) != surface_key:
				reset_motion = true
				track = {"point":actor.position,"time":motion_time,"phase":float(data.get("animationPhase",0.0)),"yaw":target_yaw}
			if returning_from_cull:
				track={"point":actor.position,"time":motion_time,"phase":float(data.get("animationPhase",0.0)),"yaw":target_yaw}
			if motion_time < float(track.time)-0.00001:
				# A battle reset can reuse the same soldier ID and type. Its feet
				# must start from the new deployment instead of retaining old anchors.
				reset_motion = true
				track = {"point":actor.position,"time":motion_time,"phase":float(data.get("animationPhase",0.0)),"yaw":target_yaw}
			if not uses_world_geometry() and track.get("projection",field_size)!=field_size:
				reset_motion = true
			track.generation = generation
			track.surface = surface_key
			track.projection = field_size
			var dt: float = maxf(0.0,motion_time-float(track.time))
			var distance: float = actor.position.distance_to(track.point)
			if distance > 1.5:
				reset_motion = true
				distance = 0.0
			var mounted: bool = model_type == "commander"
			var moving: bool = str(data.get("animation","")) == "walk" and not bool(data.get("sailing",false))
			# A repeated draw at the same battle time preserves the whole gait.
			if dt>0.00001:
				track.speed = distance/dt if moving and not reset_motion else 0.0
				track.velocity = (actor.position-(track.point as Vector3))/dt if moving and not reset_motion else Vector3.ZERO
			elif reset_motion:
				track.speed = 0.0
				track.velocity = Vector3.ZERO
			if moving and not reset_motion:
				# Logical aim is already eased by combat. Measured displacement
				# avoids easing it twice and retains the last heading while queued.
				var travel: Vector3=track.get("velocity",Vector3.ZERO)
				if Vector2(travel.x,travel.z).length_squared()>.000000001:
					target_yaw=atan2(-travel.x,-travel.z)
					if dt>0.00001:
						var previous_point: Vector2=world_to_normalized(track.point)
						track.direction=(point-previous_point).normalized()
					var travel_direction: Vector2=track.get("direction",Vector2(float(data.get("aimX",0.0)),float(data.get("aimY",1.0))))
					data["aimX"]=travel_direction.x
					data["aimY"]=travel_direction.y
				else: target_yaw=float(track.yaw)
			var local_speed: float = float(track.get("speed",0.0))/maxf(render_scale,.001)
			var run_blend: float = smoothstep(.65,1.60,local_speed) if mounted else smoothstep(.50,1.05,local_speed)
			# The existing horse hoof solver uses its own level contact frame.
			var terrain_motion: Dictionary=_terrain_approach_profile(data,point) if not mounted else {"cover":0.0,"pitch":0.0,"roll":0.0,"enabled":false}
			var cover_target: float=float(terrain_motion.cover) if moving and local_speed>.03 else 0.0
			if reset_motion: track.cover=0.0
			if dt>0.00001: track.cover=lerpf(float(track.get("cover",0.0)),cover_target,1.0-exp(-dt*8.0))
			var cover: float=float(track.get("cover",0.0)) if moving else 0.0
			run_blend=maxf(run_blend,cover*.65)
			var cadence: float = clampf(1.40+local_speed*.13,1.50,2.05) if mounted else clampf(1.55+local_speed*.14,1.60,2.10)
			var stride: float = lerpf(1.25 if mounted else .90,maxf(1.35 if mounted else .55,local_speed/cadence),run_blend)
			stride*=1.0-cover*.23-absf(float(terrain_motion.pitch))*.35
			if moving and dt>0.00001:
				track.phase = float(track.phase)+distance/(stride*render_scale)
			track.yaw = lerp_angle(float(track.yaw),target_yaw,1.0-exp(-dt*11.0)) if not reset_motion else target_yaw
			data["locomotionPhase"] = float(track.phase)
			data["travelSpeed"] = float(track.get("speed",0.0))
			data["localTravelSpeed"] = local_speed
			data["travelVelocity"] = track.get("velocity",Vector3.ZERO)
			data["runBlend"] = run_blend
			data["strideLength"] = stride
			data["locomotionCadence"] = local_speed/stride if moving else 0.0
			data["groundMotion"] = true
			data["motionReset"] = reset_motion
			data["visualYaw"] = float(track.yaw)
			data["approachCover"] = cover
			data["terrainPitch"] = float(terrain_motion.pitch)
			data["terrainRoll"] = float(terrain_motion.roll)
			if is_instance_valid(battlefield) and battlefield.has_method("height_at") and not bool(data.get("sailing",false)):
				data["groundHeightSampler"] = Callable(self,"_ground_contact_height")
			track.point = actor.position
			track.time = motion_time
			motion_tracks[key] = track
			if reset_motion or actor.current_state!=data:
				actor.apply_state(data)
				changed = true
			var actual_point: Vector2 = world_to_normalized(actor.position)
			_apply_local_light(key,actor,actual_point,motion_time,reset_motion)
			_sync_fortification(key,actor,data)
			_sync_contact_shadow(key,actor,data)
			_sync_support_flag(key,actor,bool(data.get("transientSupport",false)))
			if not bool(data.get("dead",false)) and str(data.get("animation",""))!="death":
				var marker: Dictionary = {"id":str(source.id),"member":member,"friendly":bool(data.get("friendly",false)),"position":project_world_to_field(actor.position),"sailing":bool(data.get("sailing",false))}
				marker["healthAnchor"]=project_world_to_field(actor.bones.head.global_position+Vector3.UP*.26*actor.scale.y)
				marker["hp"]=float(data.get("hp",0))
				marker["maxHp"]=float(data.get("maxHp",0))
				marker["healthFlags"]=data.get("flags",{})
				marker.merge(_visual_skill_markers(actor,data),true)
				side_markers.append(marker)
	var obsolete: Array = []
	for key in actors:
		if not live.has(key):
			var actor: Node3D = actors[key]
			var departure: Dictionary = action_presentation.departure_state(int(str(key).get_slice(":",0)))
			if not departure.is_empty() and float(departure.progress) < 1:
				# A consumed ninja keeps its last upright pose only for this fade.
				# It is absent from targeting, health bars, collision and rewards.
				actor.materials.combined.set_shader_parameter("departure_fade",float(departure.progress))
				actor.set_meta("departure",departure)
				if contact_shadows.has(key): contact_shadows[key].hide()
				changed = true
				continue
			actors[key].queue_free()
			obsolete.append(key)
	for key in obsolete:
		changed = true
		actors.erase(key)
		motion_tracks.erase(key)
		if support_flags.has(key): support_flags[key].queue_free();support_flags.erase(key)
		local_light_tracks.erase(key)
		if contact_shadows.has(key):
			contact_shadows[key].queue_free()
			contact_shadows.erase(key)
		_remove_fortification(key)
	action_presentation.prune(live_ids)
	if side_overlay != null:
		side_overlay.queue_redraw()
	if changed:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _sync_support_flag(key: String, actor: Node3D, enabled: bool) -> void:
	if not enabled:
		if support_flags.has(key): support_flags[key].queue_free();support_flags.erase(key)
		return
	if not support_flags.has(key):
		var flag: Node3D=Node3D.new()
		world.add_child(flag)
		var pole: MeshInstance3D=MeshInstance3D.new()
		var cylinder: CylinderMesh=CylinderMesh.new()
		cylinder.top_radius=.008;cylinder.bottom_radius=.008;cylinder.height=.38;cylinder.radial_segments=6
		pole.mesh=cylinder
		flag.add_child(pole)
		var cloth: MeshInstance3D=MeshInstance3D.new()
		var quad: QuadMesh=QuadMesh.new()
		quad.size=Vector2(.20,.12)
		cloth.mesh=quad
		cloth.position=Vector3(.10,.12,0)
		var material: StandardMaterial3D=StandardMaterial3D.new()
		material.albedo_color=FRIENDLY_SIDE_COLOR
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		material.roughness=.95
		cloth.material_override=material
		flag.add_child(cloth)
		support_flags[key]=flag
	var flag: Node3D=support_flags[key]
	flag.position=actor.position+Vector3(0,1.25,0)*actor.scale.x
	flag.scale=actor.scale
	flag.rotation.y=camera.rotation.y if is_instance_valid(camera) else 0.0

func _sync_support_rocks() -> void:
	var live: Dictionary={}
	var records: Array=battle.battle_support.rock_states() if is_instance_valid(battle) else []
	for record in records:
		var key: String=str(record.id)
		live[key]=true
		if not support_rocks.has(key):
			var rock: MeshInstance3D=MeshInstance3D.new()
			var mesh: SphereMesh=SphereMesh.new()
			mesh.radius=.10;mesh.height=.17;mesh.radial_segments=7;mesh.rings=3
			rock.mesh=mesh
			var material: StandardMaterial3D=StandardMaterial3D.new()
			material.albedo_color=Color("797368")
			material.roughness=1.0
			rock.material_override=material
			world.add_child(rock)
			support_rocks[key]=rock
		var rock: Node3D=support_rocks[key]
		rock.position=normalized_to_world(record.point)+Vector3.UP*float(record.height)
		rock.scale=Vector3.ONE*(float(record.radius)/.10)
		rock.rotation=Vector3(float(record.angle),float(record.angle)*.35,0)
	for key in support_rocks.keys():
		if not live.has(key): support_rocks[key].queue_free();support_rocks.erase(key)

func _model_type(data: Dictionary) -> String:
	# Backend kinds retain their combat identity; only the visual model is
	# mapped to the existing original articulated soldier or mounted officer.
	var value: String = str(data.get("type", "samurai"))
	if not bool(data.get("friendly", false)):
		match str(data.get("kind", value)):
			"enemy_archer": return "archer"
			"enemy_gunner": return "gunner"
			"enemy_cavalry": return "commander"
			"enemy_samurai": return "samurai"
		match value:
			"enemy_archer": return "archer"
			"enemy_gunner": return "gunner"
			"enemy_cavalry": return "commander"
			"enemy_samurai": return "samurai"
	return value

func sync_field_markers(markers: Array, clock: float) -> bool:
	if world==null or not is_finite(clock): return false
	var changed: bool=false
	var live: Dictionary={}
	var route: Array=stage.get("escortRoute",[])
	var initial_heading: float=0.0
	if route.size()>=2:
		var first: Vector3=normalized_to_world(Vector2(float(route[0].x),float(route[0].y)))
		var next: Vector3=normalized_to_world(Vector2(float(route[1].x),float(route[1].y)))
		initial_heading=atan2(-(next-first).x,-(next-first).z)
	for marker in markers:
		if not bool(marker.get("mobile",false)) or str(marker.get("markerKind",""))!="objective": continue
		var point: Vector2=Vector2(float(marker.get("x",NAN)),float(marker.get("y",NAN)))
		if not point.is_finite(): continue
		var key: String=str(marker.get("id",""))
		if key.is_empty(): continue
		live[key]=true
		if not mobile_objectives.has(key):
			var cart=MobileObjectiveCart.new()
			cart.name="MobileObjective_"+key.replace(":","_")
			world.add_child(cart)
			cart.configure(key,initial_heading)
			mobile_objectives[key]=cart
			changed=true
		var cart: Node3D=mobile_objectives[key]
		cart.initial_heading=initial_heading
		var projection: Vector2=Vector2(world_width,world_depth)
		var reset: bool=cart.get_meta("projection",Vector2.ZERO)!=projection or not is_equal_approx(cart.scale.x,actor_base_scale())
		cart.set_meta("projection",projection)
		cart.scale=Vector3.ONE*actor_base_scale()
		changed=cart.apply_marker(marker,normalized_to_world(point),clock,reset) or changed
		_apply_local_light("mobile:"+key,cart,point,clock,reset)
	for key in mobile_objectives.keys():
		if not live.has(key):
			mobile_objectives[key].hide()
			mobile_objectives[key].queue_free()
			mobile_objectives.erase(key)
			local_light_tracks.erase("mobile:"+str(key))
			changed=true
	if changed and viewport!=null: viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	return changed

func _sync_fortification(key: String, actor: Node3D, data: Dictionary) -> void:
	var kind: String = str(data.get("kind", data.get("type", "")))
	var stationary: bool = bool(data.get("fortification", false)) or bool(data.get("stationaryEnemy", false))
	var eligible: bool = stationary and not bool(data.get("friendly", false)) and kind in ["enemy_archer", "enemy_gunner"] and not bool(data.get("sailing", false))
	if not eligible:
		_remove_fortification(key)
		return
	if fortifications.has(key) and fortifications[key].kind != kind:
		_remove_fortification(key)
	if not fortifications.has(key):
		var prop = EnemyFortification.new()
		prop.name = "EnemyFiringCover_" + key.replace(":", "_")
		world.add_child(prop)
		prop.configure(kind)
		ActorMaterials.configure_actor_material(prop.surface_material,true,kind)
		fortifications[key] = prop
	var prop: Node3D = fortifications[key]
	# Prepared cover belongs to the terrain, so it stays fixed when the crew
	# turns to aim. Its forward direction comes from the first actor snapshot.
	if bool(data.get("motionReset", false)) or not prop.has_meta("ground_yaw"):
		prop.set_meta("ground_yaw", actor.rotation.y)
	prop.position = actor.position
	prop.rotation.y = float(prop.get_meta("ground_yaw"))
	prop.scale = actor.scale
	prop.apply_state(data)
	var track: Dictionary = local_light_tracks.get(key, {})
	if not track.is_empty():
		prop.set_local_light(float(track.exposure), track.tint, float(track.saturation), 0.0)

func _remove_fortification(key: String) -> void:
	if fortifications.has(key):
		fortifications[key].hide()
		fortifications[key].queue_free()
		fortifications.erase(key)

func _visual_skill_markers(actor: Node3D, data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var flags: Variant = data.get("flags", {})
	if not flags is Dictionary or bool(data.get("sailing",false)): return result
	var active: Array = []
	for key in ["poisoned","burning","armorWeakened","invulnerable","talisman","mantra","spearAura","formationBroken"]:
		if bool(flags.get(key,false)): active.append(key)
	if not active.is_empty():
		result["statusFlags"] = active
		result["statusPoint"] = project_world_to_field(actor.position+Vector3.UP*1.25*actor.scale.y)
	if bool(flags.get("formation",false)):
		result["formation"] = true
	var ids: Variant = data.get("skillIds", [])
	if actor.unit_type == "spear" and bool(flags.get("poisonTip",false)) and ids is Array and "spear_poison" in ids and int(data.get("campaignLevel",8))>=8:
		# Project the real articulated weapon tip. No luminous extra mesh or
		# baseline draw batch is added to any of the 24 model variants.
		result["poisonTipPoint"] = project_world_to_field(actor.bones.weapon.global_transform*Vector3(0,1.22+actor.evolution_stage*.025,0))
	return result

func _sync_torch_flicker(clock: float) -> void:
	if not is_finite(clock) or is_equal_approx(clock,light_clock):
		return
	light_clock = clock
	for index in range(torch_lights.size()):
		var phase: float = float(absi(str(stage.get("id","")).hash())%997)*.013+index*1.73
		# Cosmetic illumination uses the same battle clock as the soldiers,
		# including pause/reset. It never modifies the artwork or simulation.
		torch_lights[index].light_energy = .65*(.96+.045*sin(clock*7.3+phase)+.025*sin(clock*11.8+phase*.7))

func _apply_local_light(key: String, actor: Node3D, point: Vector2, clock: float, force: bool = false) -> void:
	if local_light_field==null: return
	if not point.is_finite() or not is_finite(clock):
		return
	var track: Dictionary = local_light_tracks.get(key,{})
	force = force or track.is_empty() or clock<float(track.get("clock",0.0))
	# Fifteen uniform updates/second at most; render/motion remains full rate.
	var dt: float = maxf(0.0,clock-float(track.get("clock",clock)))
	if not force and dt<1.0/15.0:
		return
	var target: Dictionary = {"exposure":1.0,"tint":Color.WHITE,"saturation":1.0,"roughnessBias":0.0,"sourceLuminance":0.0}
	if local_light_field != null:
		var bounds: Vector4 = render_layer.get("normalizedBounds",Vector4(0,0,1,1))
		var uv: Vector2 = Vector2((point.x-bounds.x)/maxf(.001,bounds.z),(point.y-bounds.y)/maxf(.001,bounds.w))
		target = local_light_field.sample(uv)
	var amount: float = 1.0 if force else 1.0-exp(-minf(dt,.25)*5.0)
	var exposure: float = lerpf(float(track.get("exposure",target.exposure)),float(target.exposure),amount)
	var tint: Color = (track.get("tint",target.tint) as Color).lerp(target.tint,amount)
	var saturation: float = lerpf(float(track.get("saturation",target.saturation)),float(target.saturation),amount)
	actor.set_local_light(exposure,tint,saturation,float(target.roughnessBias))
	local_light_updates += 1
	local_light_tracks[key] = {"clock":clock,"point":point,"exposure":exposure,"tint":tint,"saturation":saturation,"sourceLuminance":target.sourceLuminance}

func _draw_side_markers() -> void:
	if side_overlay == null:
		return
	_draw_guard_bounds()
	for marker in side_markers:
		var p: Vector2 = marker.position+Vector2(0,4)
		if not Rect2(Vector2.ZERO,field_size).grow(-5).has_point(p):
			continue
		var ink: Color = Color(0.025,0.035,0.045,0.90)
		if bool(marker.friendly):
			# Two separate bars remain identifiable without a hue distinction.
			for side in [-1,1]:
				var a: Vector2 = p+Vector2(float(side)*2.5,0)
				var b: Vector2 = p+Vector2(float(side)*6.0,0)
				side_overlay.draw_line(a,b,ink,4.0,true)
				side_overlay.draw_line(a,b,FRIENDLY_SIDE_COLOR,2.0,true)
		else:
			var triangle: PackedVector2Array = PackedVector2Array([p+Vector2(0,-2.5),p+Vector2(5,2),p+Vector2(-5,2)])
			side_overlay.draw_colored_polygon(triangle,HOSTILE_SIDE_COLOR)
			triangle.append(triangle[0])
			side_overlay.draw_polyline(triangle,ink,1.4,true)
		if marker.has("poisonTipPoint"):
			var tip: Vector2 = marker.poisonTipPoint
			if Rect2(Vector2.ZERO,field_size).grow(-3).has_point(tip):
				side_overlay.draw_line(tip-Vector2(0,1.4),tip+Vector2(0,1.4),ink,3.6,true)
				side_overlay.draw_line(tip-Vector2(0,1.4),tip+Vector2(0,1.4),Color(.73,.82,.49,.93),1.6,true)
		if marker.has("statusPoint"):
			var status_point: Vector2 = marker.statusPoint
			var flags: Array = marker.statusFlags
			var shown: int = mini(4,flags.size())
			for index in range(shown):
				var center: Vector2 = status_point+Vector2((float(index)-float(shown-1)*.5)*5,0)
				if not Rect2(Vector2.ZERO,field_size).grow(-4).has_point(center): continue
				var colour: Color = Color(.75,.81,.49,.93)
				if str(flags[index])=="burning": colour=Color(.98,.70,.34,.94)
				elif str(flags[index])=="armorWeakened": colour=Color(.89,.74,.53,.94)
				elif str(flags[index])=="invulnerable": colour=Color(.93,.92,.77,.94)
				elif str(flags[index]) in ["talisman","mantra","spearAura"]: colour=Color(.93,.88,.72,.94)
				elif str(flags[index])=="formationBroken": colour=Color(.88,.66,.52,.94)
				side_overlay.draw_line(center-Vector2(0,2),center+Vector2(0,2),ink,3.6,true)
				side_overlay.draw_line(center-Vector2(0,2),center+Vector2(0,2),colour,1.6,true)
				if str(flags[index])=="armorWeakened":
					side_overlay.draw_line(center-Vector2(2,-1),center+Vector2(2,-1),colour,1.0,true)
		if bool(marker.get("formation",false)):
			for side in [-1.0,1.0]:
				side_overlay.draw_line(p+Vector2(side*7,2),p+Vector2(side*9,4),ink,2.6,true)
				side_overlay.draw_line(p+Vector2(side*7,2),p+Vector2(side*9,4),Color(.82,.85,.70,.86),1.0,true)

func _guard_view_point(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if value is Vector2: return value
	if value is Dictionary: return Vector2(float(value.get("x",fallback.x)),float(value.get("y",fallback.y)))
	return fallback

func guard_overlay_data() -> Dictionary:
	if not is_instance_valid(battle): return {}
	var unit: Dictionary = {}
	var preview: Dictionary = ui_deployment_preview if bool(battle.ui_deployment_active) else battle.placement_preview(battle.placement_cursor)
	if bool(preview.get("visible",false)) and bool(preview.get("valid",false)) and str(preview.get("type","")) == "naginata":
		var home: Vector2 = _guard_view_point(preview.get("position",{}))
		var post: Dictionary = battle._eligible_zone(home,"naginata")
		var radius: float = clampf(float(post.get("guardRadius",.15)),.07,.25)
		unit = {"homePosition":home,"guardZone":post.get("defenseZone",{"center":home,"radius":radius}),"guardRadius":radius,"guardTrail":[],"detectionRadius":float(preview.get("range",0))}
	elif battle.pending.is_empty() and not bool(battle.ui_deployment_active):
		var selected: Dictionary = battle._selected()
		if str(selected.get("type","")) != "naginata": return {}
		unit = selected
	else: return {}
	if unit.is_empty(): return {}
	var home: Vector2 = unit.get("homePosition",Vector2.ZERO)
	var zone: Dictionary = unit.get("guardZone",{})
	var boundary: PackedVector2Array = PackedVector2Array()
	for point in zone.get("polygon",[]): boundary.append(_guard_view_point(point))
	if boundary.size() < 3:
		boundary.clear()
		var center: Vector2 = _guard_view_point(zone.get("center",home),home)
		var radius: float = float(zone.get("radius",unit.get("guardRadius",.15)))
		for index in range(65): boundary.append(center+Vector2.from_angle(TAU*index/64.0)*radius)
	else: boundary.append(boundary[0])
	return {"home":home,"boundary":boundary,"detectionRadius":float(unit.get("detectionRadius",battle._stats(unit).range if unit.has("type") else 0)),"trail":unit.get("guardTrail",[]),"waypoints":zone.get("waypoints",[])}

func _draw_guard_bounds() -> void:
	var data: Dictionary = guard_overlay_data()
	if data.is_empty(): return
	var outline: PackedVector2Array = PackedVector2Array()
	for point in data.boundary: outline.append(project_world_to_field(normalized_to_world(point)))
	side_overlay.draw_colored_polygon(outline,Color(.3,.65,1,.018))
	side_overlay.draw_polyline(outline,Color(.42,.76,1,.70),1.6,true)
	var radius: float = float(data.detectionRadius)
	for index in range(0,64,2):
		var a: Vector2 = data.home+Vector2.from_angle(TAU*index/64.0)*radius
		var b: Vector2 = data.home+Vector2.from_angle(TAU*(index+1)/64.0)*radius
		side_overlay.draw_line(project_world_to_field(normalized_to_world(a)),project_world_to_field(normalized_to_world(b)),Color(.92,.76,.42,.60),1.3,true)
	var home: Vector2 = project_world_to_field(normalized_to_world(data.home))
	side_overlay.draw_arc(home,4,0,TAU,16,Color(.7,.86,1,.9),1.5,true)
	for waypoint in data.waypoints:
		side_overlay.draw_circle(project_world_to_field(normalized_to_world(_guard_view_point(waypoint))),2.5,Color(.42,.76,1,.6))
	var trail: PackedVector2Array = PackedVector2Array()
	for point in data.trail: trail.append(project_world_to_field(normalized_to_world(_guard_view_point(point))))
	if trail.size() > 1: side_overlay.draw_polyline(trail,Color(.42,.76,1,.32),1.0,true)

func diagnostics() -> Dictionary:
	var actor_info: Array = []
	var mobile_info: Array=[]
	for cart in mobile_objectives.values(): mobile_info.append(cart.diagnostics())
	for actor in actors.values():
		actor_info.append(actor.diagnostics())
	var light_info: Dictionary = local_light_field.diagnostics() if local_light_field!=null else {"available":false}
	light_info["physicalLighting"] = true
	light_info["normalizedBounds"] = render_layer.get("normalizedBounds",Vector4(0,0,1,1))
	light_info["mobileObjectives"]=mobile_info
	return {"artDirection":ActorMaterials.ART_DIRECTION,"actors":actors.size(),"fortifications":fortifications.size(),"actorBaseScale":actor_base_scale(),"viewportSize":{"x":viewport.size.x,"y":viewport.size.y},"projection":"orthographic","elevation":elevation_degrees,"worldWidth":world_width,"transparent":viewport.transparent_bg,"photoGround":false,"nativeBattlefield":is_instance_valid(battlefield),"renderMode":str(render_layer.get("mode","native")),"renderedArtwork":bool(render_layer.get("renderedArtwork",false)),"terrain":battlefield.diagnostics() if is_instance_valid(battlefield) else {},"realShadowCasting":sun.shadow_enabled,"real3DMeshes":true,"actorDiagnostics":actor_info,"sideMarkerCount":side_markers.size(),"sideMarkerShapes":{"friendly":"two-bars","hostile":"triangle"},"placementPreviewVisible":is_instance_valid(placement_actor) and placement_actor.visible,"localLightUpdates":local_light_updates,"localLightActors":local_light_tracks.size(),"lightField":light_info}
