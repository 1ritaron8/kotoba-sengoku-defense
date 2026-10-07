extends Node2D
const BattlefieldPresentation = preload("res://native/battlefield_presentation.gd")

var battle: Node2D
var profiles: Dictionary = {}
var visual_profile: Dictionary = {}
var haze_texture: GradientTexture2D
var world_time: float = 0.0
var seed_value: float = 0.0
var stage_data: Dictionary = {}
var weather_profile: Dictionary = {}
var atmosphere_points: Array[Dictionary] = []
var field_finish: ColorRect
var finish_material: ShaderMaterial
var redraw_clock: float = 0.0
var field_cache: Rect2 = Rect2()

func _ready() -> void:
	var profile_path = "res://native/visual_profiles.json"
	if FileAccess.file_exists(profile_path):
		var library = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
		if library is Dictionary:
			for item in library.get("profiles",[]):
				profiles[str(item.stageId)] = item
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,0.45,0.75,1.0])
	gradient.colors = PackedColorArray([Color(1,1,1,1),Color(1,1,1,0.5),Color(1,1,1,0.12),Color(1,1,1,0)])
	haze_texture = GradientTexture2D.new()
	haze_texture.gradient = gradient
	haze_texture.width = 128
	haze_texture.height = 128
	haze_texture.fill = GradientTexture2D.FILL_RADIAL
	haze_texture.fill_from = Vector2(0.5,0.5)
	haze_texture.fill_to = Vector2(0.5,0.0)
	# A light air pass uses the same field transform as the physical world.
	# It needs no screen texture copy and never touches the interface.
	var shader = Shader.new()
	shader.code = """shader_type canvas_item;
uniform vec3 horizon_colour = vec3(0.66,0.69,0.64);
uniform float horizon_amount = 0.012;
void fragment() {
    vec2 edge = abs(UV-vec2(0.5))*2.0;
    float vignette = pow(clamp(max(edge.x,edge.y),0.0,1.0),5.0)*0.075;
    float air = (1.0-smoothstep(0.0,0.38,UV.y))*horizon_amount;
    float opacity = vignette+air;
    COLOR = vec4(mix(vec3(0.025,0.032,0.032),horizon_colour,air/max(opacity,0.0001)),opacity);
}"""
	finish_material = ShaderMaterial.new()
	finish_material.shader = shader
	field_finish = ColorRect.new()
	field_finish.name = "BattlefieldEdgeFinish"
	field_finish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_finish.material = finish_material
	field_finish.z_index = -1
	add_child(field_finish)

func set_stage(stage: Dictionary) -> void:
	stage_data = stage.duplicate(true)
	var stage_id: String = str(stage.get("id",""))
	visual_profile = profiles.get(stage_id,{})
	var history: Dictionary = stage_data.get("historicalBattlefield",{})
	weather_profile = history.get("presentationWeather",{}).duplicate(true)
	if not history.is_empty():
		var is_night: bool = str(history.get("timeOfDay","neutral_daylight"))=="night"
		var damp: bool = float(weather_profile.get("wetness",0))>.5
		visual_profile = {"fogTint":"#71858e" if is_night else "#98adb4" if damp else "#aeb8a8","fogStrength":0.018 if damp else 0.012 if is_night else 0.006}
	# IDs distinguish all forty battlefields, including data without stageNumber.
	seed_value = float(stage_id.hash() & 0x7fffffff)/2147483647.0
	world_time = 0.0
	redraw_clock = 0.0
	_prepare_atmosphere_points()
	if finish_material != null:
		var horizon: Color = Color(str(visual_profile.get("fogTint","#aeb8a8")))
		finish_material.set_shader_parameter("horizon_colour",Vector3(horizon.r,horizon.g,horizon.b))
		finish_material.set_shader_parameter("horizon_amount",minf(float(visual_profile.get("fogStrength",0.025))*0.38,0.022))
	_update_field()
	queue_redraw()

func _update_field() -> void:
	if not is_instance_valid(battle) or not is_instance_valid(field_finish): return
	var field: Rect2 = battle.field_rect
	if field==field_cache: return
	field_cache = field
	field_finish.position = field.position
	field_finish.size = field.size
	queue_redraw()

func _prepare_atmosphere_points() -> void:
	atmosphere_points.clear()
	var kind: String = _air_kind()
	var count: int = 40 if kind=="snow" else int(lerpf(24,84,clampf(float(weather_profile.get("rainIntensity",.3)),0,1))) if kind=="rain" else 10 if kind=="autumn_leaves" else 8
	var stage_rng = RandomNumberGenerator.new()
	stage_rng.seed = int(seed_value*2147483647.0)
	var paths: Array = stage_data.get("paths",[])
	for index in range(count):
		var point = Vector2(stage_rng.randf(),stage_rng.randf())
		if kind=="dust" and not paths.is_empty():
			var path: Dictionary = paths[index%paths.size()]
			var points: Array = path.get("points",[])
			if not points.is_empty():
				var entry: Dictionary = points[stage_rng.randi_range(0,points.size()-1)]
				point = Vector2(float(entry.x),float(entry.y))+Vector2(stage_rng.randf_range(-0.025,0.025),stage_rng.randf_range(-0.025,0.025))
		atmosphere_points.append({"point":point.clamp(Vector2.ZERO,Vector2.ONE),"phase":stage_rng.randf()*TAU,"depth":stage_rng.randf(),"drift":stage_rng.randf_range(0.75,1.25)})

func _air_kind() -> String:
	var history: Dictionary = stage_data.get("historicalBattlefield",{})
	if history.is_empty():
		return "snow" if str(stage_data.get("theme",""))=="snow" else "dust"
	if not weather_profile.is_empty():
		if float(weather_profile.get("snowCoverage",0))>0: return "snow"
		if float(weather_profile.get("rainIntensity",0))>0: return "rain"
		if float(weather_profile.get("leafCoverage",0))>.14: return "autumn_leaves"
		return "none" if float(weather_profile.get("wetness",0))>.45 else "dust"
	var weather = history.get("weather",{})
	var key: String = str(weather.get("key","unknown")) if weather is Dictionary else str(weather)
	if key in ["snow","snowfall_reported"]: return "snow"
	if key in ["rain","rainfall_reported"]: return "rain"
	var biome: String = str(history.get("sceneBiome",""))
	if str(history.get("groundSeason","neutral"))=="autumn" and ("hill" in biome or "mountain" in biome or "forest" in biome):
		return "autumn_leaves"
	return "dust"

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(battle):
		return
	_update_field()
	redraw_clock += delta
	var next_time: float = float(battle.elapsed)
	if not is_equal_approx(next_time,world_time) and redraw_clock>=1.0/30.0:
		world_time = next_time
		redraw_clock = 0.0
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(battle) or battle.config.is_empty():
		return
	var field: Rect2 = battle.field_rect
	var history: Dictionary = stage_data.get("historicalBattlefield",{})
	var fog_amount: float = float(visual_profile.get("fogStrength",0.0))
	var fog_color = Color(str(visual_profile.get("fogTint","#bdc4b6")))
	if haze_texture != null and fog_amount > 0.0:
		for index in range(3):
			var center = Vector2(fposmod(seed_value+index*0.237+world_time*0.0018,1.45)-0.2,0.16+index*0.135)
			center.y += sin(world_time*0.023+index)*0.012
			var extent = field.size*Vector2(0.7,0.16)
			fog_color.a = minf(fog_amount*0.46,0.028)
			draw_texture_rect(haze_texture,Rect2(field.position+battle.view_point(center)*field.size-extent*0.5,extent),false,fog_color)
	_draw_wind(field,_air_kind())
	if str(history.get("timeOfDay",""))=="night": _draw_lantern_air(field)
	if not stage_data.get("water",{}).is_empty(): _draw_water_air(field)

func _draw_wind(field: Rect2, kind: String) -> void:
	if kind=="none": return
	# Okehazama's reported shower passes; wet ground remains throughout the
	# selected phase. Other rain profiles are artistic seasonal presentation.
	if kind=="rain":
		var timing: String=str(weather_profile.get("rainTiming",""))
		if timing=="intermittent_shower_then_clearing" and (world_time<12.0 or world_time>95.0): return
		if timing=="intermittent" and sin(world_time*.037+seed_value*TAU)<-.35: return
	for item in atmosphere_points:
		var phase: float = float(item.phase)
		var depth: float = float(item.depth)
		var speed: float = float(item.drift)
		var origin: Vector2 = item.point
		var x: float = fposmod(origin.x+world_time*0.0032*speed+sin(world_time*0.15+phase)*0.006,1.0)
		var y: float = fposmod(origin.y+world_time*(0.13 if kind=="rain" else 0.018 if kind=="snow" else 0.004)*speed,1.0)
		var point: Vector2 = field.position+battle.view_point(Vector2(x,y))*field.size
		var scale_value: float = lerpf(0.65,1.5,depth)*clampf(field.size.x/1280.0,0.8,1.35)
		var opacity: float = lerpf(0.08,0.20,depth)
		if kind=="snow":
			var wind: Vector2 = Vector2(1.8,2.0) if not battle.storm_active else Vector2(4.0,1.8)
			wind=BattlefieldPresentation.direction_to_view(wind,battle.presentation_mirrored)
			draw_line(point,point+wind*scale_value,Color(0.86,0.89,0.92,opacity*1.25),scale_value,true)
		elif kind=="rain":
			draw_line(point,point+BattlefieldPresentation.direction_to_view(Vector2(2,8),battle.presentation_mirrored)*scale_value,Color(0.67,0.75,0.81,opacity*.7),.8,true)
		elif kind=="autumn_leaves":
			var angle: float = phase+world_time*0.4
			var axis: Vector2 = Vector2(cos(angle),sin(angle))*scale_value
			axis=BattlefieldPresentation.direction_to_view(axis,battle.presentation_mirrored)
			var colour: Color = Color(0.62,0.44,0.25,opacity)
			draw_line(point-axis,point+axis,colour,1.2,true)
			draw_line(point,point+axis.rotated(0.65)*0.9,colour,0.7,true)
		else:
			# Low dust drifts along the real lanes instead of glittering across the map.
			draw_circle(point,scale_value,Color(0.68,0.63,0.50,opacity*0.6),true,-1.0,true)

func _draw_lantern_air(field: Rect2) -> void:
	if haze_texture==null: return
	var torches: Array = stage_data.get("torches",[])
	for index in range(torches.size()):
		var torch: Dictionary = torches[index]
		var source: Vector2 = field.position+battle.view_point(Vector2(float(torch.x),float(torch.y)))*field.size
		var flicker: float = 0.85+sin(world_time*5.7+index)*0.07+sin(world_time*9.3+index)*0.04
		var size_value: Vector2 = Vector2(54,30)*field.size.x/1280.0
		draw_texture_rect(haze_texture,Rect2(source-size_value*.5,size_value),false,Color(0.88,0.47,0.18,0.055*flicker))
		for ember in range(3):
			var phase: float = fposmod(world_time*0.27+seed_value+index*.217+ember*.31,1.0)
			var point: Vector2 = source+BattlefieldPresentation.direction_to_view(Vector2(sin(phase*5.0+index)*5.0,-phase*26.0),battle.presentation_mirrored)
			draw_circle(point,0.65,Color(0.93,0.60,0.27,(1.0-phase)*0.32),true,-1.0,true)

func _draw_water_air(field: Rect2) -> void:
	var water_data: Dictionary = stage_data.get("water",{})
	if water_data.is_empty() or haze_texture==null: return
	var water: Rect2 = Rect2(Vector2(float(water_data.get("x",0)),float(water_data.get("y",0))),Vector2(float(water_data.get("w",0)),float(water_data.get("h",0))))
	if water.size.x<=0 or water.size.y<=0: return
	# Water mist follows each map's own water region; no fabricated water plane
	# covers bridges, banks or the physical shore.
	var point: Vector2 = water.position+water.size*Vector2(0.5+sin(world_time*.025+seed_value)*0.06,0.45)
	var extent: Vector2 = field.size*Vector2(minf(water.size.x*.85,0.50),minf(water.size.y*.32,0.14))
	var centre: Vector2 = field.position+battle.view_point(point)*field.size
	draw_texture_rect(haze_texture,Rect2(centre-extent*.5,extent),false,Color(0.60,0.68,0.69,0.025))
