extends RefCounted
## Shared, real surface scans. These materials use the battlefield's lights.

static var textures: Dictionary = {}
static var shared: Dictionary = {}
static var rendered_textures: Dictionary = {}
static var rendered_texture_order: Array[String] = []
static var rendered_shader: Shader
const RENDERED_TEXTURE_CACHE_LIMIT: int = 3

static func release_shared_resources() -> void:
	# Called once at application shutdown, after battlefield/preview nodes exit.
	shared.clear()
	textures.clear()
	rendered_textures.clear()
	rendered_texture_order.clear()
	rendered_shader = null

static func cache_diagnostics() -> Dictionary:
	var sizes: Dictionary = {}
	for path in textures:
		var value: Texture2D = textures[path]
		if value != null:
			sizes[path] = {"width":value.get_width(),"height":value.get_height()}
	return {"textureCount":textures.size(),"materialCount":shared.size(),"textureSizes":sizes,"renderedArtTextureCount":rendered_textures.size(),"renderedArtTextureLimit":RENDERED_TEXTURE_CACHE_LIMIT,"renderedShaderCached":rendered_shader != null}

static func rendered_art_texture(path: String,content_hash: String) -> Texture2D:
	var key: String = path+":"+content_hash
	if rendered_textures.has(key):
		rendered_texture_order.erase(key)
		rendered_texture_order.append(key)
		return rendered_textures[key]
	var value: Texture2D
	# A newly generated file can precede editor import. Prefer the raw source
	# here; release builds load the import-remapped resource instead.
	var raw_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(raw_path):
		var image: Image = Image.load_from_file(raw_path)
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			value = ImageTexture.create_from_image(image)
	if value == null and ResourceLoader.exists(path):
		value = load(path) as Texture2D
	if value == null:
		return null
	rendered_textures[key] = value
	rendered_texture_order.append(key)
	while rendered_texture_order.size() > RENDERED_TEXTURE_CACHE_LIMIT:
		var expired: String = rendered_texture_order.pop_front()
		rendered_textures.erase(expired)
	return value

static func rendered_art(record: Dictionary, stage: Dictionary = {}) -> ShaderMaterial:
	var art: Texture2D = rendered_art_texture(str(record.get("artPath","")),str(record.get("artSha256","")))
	if art == null:
		return null
	if rendered_shader == null:
		rendered_shader = Shader.new()
		rendered_shader.code = """shader_type spatial;
render_mode cull_back, ambient_light_disabled, specular_disabled, fog_disabled;
uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 normalized_bounds = vec4(0.0,0.0,1.0,1.0);
uniform float shadow_strength : hint_range(0.0,1.0) = 0.4;
uniform float relief_strength : hint_range(0.0,1.0) = 0.65;
uniform int relief_water_count = 0;
uniform vec4 relief_water_rects[32];
varying vec3 flat_normal_view;
varying float relief_land;
void vertex() {
    flat_normal_view = normalize(MODELVIEW_NORMAL_MATRIX * vec3(0.0,1.0,0.0));
}
void fragment() {
    vec2 mapped = (UV2-normalized_bounds.xy)/normalized_bounds.zw;
    vec3 source = texture(artwork,clamp(mapped,vec2(0.0),vec2(1.0))).rgb;
    ALBEDO = source;
    EMISSION = vec3(0.0);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    AO = 1.0;
    relief_land = 1.0;
    for (int i = 0; i < relief_water_count; i++) {
        vec4 water = relief_water_rects[i];
        if (UV2.x >= water.x && UV2.x <= water.x+water.z && UV2.y >= water.y && UV2.y <= water.y+water.w) {
            relief_land = 0.0;
        }
    }
}
void light() {
    // One key sun affects terrain layer 1. Actor fill lights use layer 2.
    // Artwork already contains its static lighting; only live shadow
    // attenuation is applied. Keep the colour in one lighting pass: GLES
    // shadow lights use an additive pass, so emission plus light would
    // add two independently gamma-encoded colours and brighten the art.
    // Godot multiplies DIFFUSE_LIGHT by ALBEDO.
    if (LIGHT_IS_DIRECTIONAL) {
        // Relative to flat ground, so level surfaces retain their exact art.
        // Existing painted/live shadows are not multiplied by a second shade.
        float slope = length(NORMAL-normalize(flat_normal_view));
        float grade_light = dot(NORMAL,LIGHT)-dot(normalize(flat_normal_view),LIGHT);
        float relief = clamp(1.0+relief_strength*grade_light,0.90,1.15);
        float relief_weight = relief_land*smoothstep(0.025,0.12,slope)*smoothstep(0.88,1.0,ATTENUATION);
        DIFFUSE_LIGHT += vec3((1.0-shadow_strength*(1.0-ATTENUATION))*mix(1.0,relief,relief_weight));
    }
}"""
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = rendered_shader
	result.set_shader_parameter("artwork",art)
	result.set_shader_parameter("normalized_bounds",record.get("normalizedBounds",Vector4(0,0,1,1)))
	var lighting: Dictionary = record.get("lighting",{})
	result.set_shader_parameter("shadow_strength",clampf(float(lighting.get("shadowStrength",.4)),0.0,1.0))
	var water_rects: PackedVector4Array = PackedVector4Array()
	var water_features: Array = []
	if not stage.get("water",{}).is_empty(): water_features.append(stage.water)
	var history: Dictionary = stage.get("historicalBattlefield",{})
	water_features.append_array(history.get("waterFeatures",[]))
	for landmark in history.get("sceneLandmarks",[]):
		if str(landmark.get("kind","")) in ["river","stream","valley_river","waterway","lake","bay","marsh","floodplain","wetland_lake"]:
			var extent: Dictionary = landmark.get("scale",{})
			var w: float = float(extent.get("w",0))
			var h: float = float(extent.get("h",0))
			water_features.append({"x":float(landmark.get("x",.5))-w*.5,"y":float(landmark.get("y",.5))-h*.5,"w":w,"h":h})
	for water in water_features:
		if water_rects.size()>=32: break
		if not water is Dictionary or float(water.get("w",0))<=0 or float(water.get("h",0))<=0: continue
		water_rects.append(Vector4(float(water.get("x",0)),float(water.get("y",0)),float(water.w),float(water.h)))
	result.set_shader_parameter("relief_water_count",water_rects.size())
	while water_rects.size()<32: water_rects.append(Vector4.ZERO)
	result.set_shader_parameter("relief_water_rects",water_rects)
	return result

static func texture(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path]
	var result: Texture2D
	if ResourceLoader.exists(path):
		result = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null:
			image.generate_mipmaps()
			result = ImageTexture.create_from_image(image)
	if result != null:
		var source: Image = result.get_image()
		if source != null and not source.has_mipmaps():
			if source.is_compressed():
				source.decompress()
			source.generate_mipmaps()
			result = ImageTexture.create_from_image(source)
	textures[path] = result
	return result

static func surface(family: String, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key: String = family + ":" + tint.to_html()
	if shared.has(key):
		return shared[key]
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = tint
	result.roughness = 0.9
	result.metallic_specular = 0.22
	var prefix: String = "res://assets/materials/terrain/"
	var source: String = "weathered_brown_planks" if family == "wood" else "rock_boulder_dry"
	if family == "earth":
		source = "brown_mud_leaves_01"
	elif family == "forest":
		source = "forest_ground_04"
	if family in ["wood", "rock", "earth", "forest"]:
		result.albedo_texture = texture(prefix + source + "_diff_1k.jpg")
		result.normal_enabled = true
		result.normal_texture = texture(prefix + source + "_nor_gl_1k.jpg")
		result.normal_scale = 0.65
		result.roughness_texture = texture(prefix + source + "_rough_1k.jpg")
		result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	else:
		result.roughness = 0.85
	shared[key] = result
	return result

static func terrain(theme: String, season: String) -> ShaderMaterial:
	var key: String = "terrain:" + theme + ":" + season
	if shared.has(key):
		return shared[key]
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_back;
uniform sampler2D forest_colour : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_colour : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_rough : filter_linear_mipmap, repeat_enable;
uniform vec3 growth_tint = vec3(0.49,0.60,0.30);
uniform vec3 soil_tint = vec3(0.70,0.61,0.45);
uniform float wetness = 0.0;
varying vec4 ground_recipe;
void vertex() { ground_recipe = COLOR; }
void fragment() {
    vec2 detail = UV * 1.4;
    vec3 forest = texture(forest_colour,detail).rgb;
    vec3 earth = texture(earth_colour,detail*0.86+vec2(0.32)).rgb;
    float grit = dot(earth,vec3(0.2126,0.7152,0.0722));
    vec3 soil = mix(earth,vec3(grit)*soil_tint,0.60);
    float leaf_luma = dot(forest,vec3(0.2126,0.7152,0.0722));
    vec3 growth = mix(forest,vec3(leaf_luma)*growth_tint*1.90,0.76);
    float road = clamp(ground_recipe.r,0.0,1.0);
    float grass = clamp(ground_recipe.g*(1.0-road),0.0,1.0);
    float surface_wet = max(wetness,ground_recipe.b);
    ALBEDO = mix(soil,growth,grass);
    ALBEDO *= mix(1.0,0.61,surface_wet);
    NORMAL_MAP = mix(texture(earth_normal,detail*0.86).rgb,texture(forest_normal,detail).rgb,grass);
    NORMAL_MAP_DEPTH = 0.66;
    ROUGHNESS = clamp(mix(texture(earth_rough,detail).r,texture(forest_rough,detail).r,grass),0.55,0.98);
    ROUGHNESS = mix(ROUGHNESS,0.38,surface_wet);
    SPECULAR = mix(0.15,0.33,surface_wet);
    AO = mix(0.85,1.0,ground_recipe.a);
}"""
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = shader
	var prefix: String = "res://assets/materials/terrain/"
	for family in ["forest", "earth"]:
		var source: String = "forest_ground_04" if family == "forest" else "brown_mud_leaves_01"
		result.set_shader_parameter(family + "_colour", texture(prefix + source + "_diff_1k.jpg"))
		result.set_shader_parameter(family + "_normal", texture(prefix + source + "_nor_gl_1k.jpg"))
		result.set_shader_parameter(family + "_rough", texture(prefix + source + "_rough_1k.jpg"))
	var growth: Color = Color(0.49, 0.60, 0.30)
	if season == "winter":
		growth = Color(0.55, 0.52, 0.34)
	elif season == "autumn":
		growth = Color(0.63, 0.53, 0.31)
	elif season == "spring":
		growth = Color(0.50, 0.62, 0.34)
	result.set_shader_parameter("growth_tint", growth)
	result.set_shader_parameter("wetness", 0.78 if theme == "wet_mud" else 0.0)
	if theme == "dry_earth":
		result.set_shader_parameter("soil_tint", Color(0.76, 0.68, 0.50))
	shared[key] = result
	return result

static func road(wet: bool) -> ShaderMaterial:
	var key: String = "road:" + str(wet)
	if shared.has(key):
		return shared[key]
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform sampler2D earth_colour : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wetness = 0.0;
void fragment() {
    vec3 source = texture(earth_colour,UV*1.5).rgb;
    float luminance = dot(source,vec3(0.2126,0.7152,0.0722));
    ALBEDO = mix(source,vec3(luminance*1.38)*vec3(1.0,0.82,0.54),0.85);
    float across = COLOR.a + sin(UV.x*7.0+UV.y*4.0)*0.018 + sin(UV.x*16.0-UV.y*12.0)*0.009;
    float edge = smoothstep(0.015,0.24,across) * (1.0-smoothstep(0.76,0.985,across));
    float tracks = smoothstep(0.08,0.14,abs(COLOR.a-0.28)) * smoothstep(0.08,0.14,abs(COLOR.a-0.72));
    float surface_wet = max(wetness,COLOR.b);
    ALBEDO *= mix(0.95,1.0,tracks) * mix(1.0,0.58,surface_wet);
    NORMAL_MAP = texture(earth_normal,UV*1.5).rgb;
    NORMAL_MAP_DEPTH = 0.5;
    ROUGHNESS = mix(0.94,0.43,surface_wet);
    SPECULAR = mix(0.12,0.30,surface_wet);
    ALPHA = edge*0.96;
}"""
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = shader
	result.set_shader_parameter("earth_colour", texture("res://assets/materials/terrain/brown_mud_leaves_01_diff_1k.jpg"))
	result.set_shader_parameter("earth_normal", texture("res://assets/materials/terrain/brown_mud_leaves_01_nor_gl_1k.jpg"))
	result.set_shader_parameter("wetness", 0.75 if wet else 0.0)
	shared[key] = result
	return result

static func water(kind: String = "river") -> ShaderMaterial:
	var key: String = "water:" + kind
	if shared.has(key):
		return shared[key]
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;
uniform vec3 water_colour = vec3(0.16,0.25,0.23);
uniform float flow = 0.6;
uniform vec2 shore_size = vec2(1.0);
uniform float shallowness = 0.0;
varying vec2 surface_world;
void vertex() { surface_world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
    vec2 p = surface_world;
    float wave = sin(p.x*5.8+p.y*2.3+TIME*flow)*sin(p.y*7.5-p.x*2.7+TIME*flow*0.77);
    float ripple = sin(p.x*15.0+p.y*11.0+TIME*flow*1.4);
    vec3 tangent_normal = normalize(vec3(wave*0.065,ripple*0.035,1.0));
    NORMAL_MAP = tangent_normal*0.5+0.5;
    NORMAL_MAP_DEPTH = 0.65;
    float shore = min(min(UV.x,1.0-UV.x)*shore_size.x,min(UV.y,1.0-UV.y)*shore_size.y);
    shore += sin(p.x*5.1+p.y*4.2)*0.032+sin(p.y*11.0-p.x*8.0)*0.018;
    float bank = 1.0-smoothstep(0.02,0.20,shore);
    ALBEDO = water_colour * (0.91+wave*0.045);
    ALBEDO = mix(ALBEDO,vec3(0.31,0.31,0.23),bank*0.17);
    METALLIC = 0.12;
    ROUGHNESS = mix(0.24,0.39,bank);
    SPECULAR = 0.55;
    ALPHA = smoothstep(0.0,0.055,shore)*mix(0.96,0.44,shallowness);
}"""
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = shader
	if kind in ["bay", "lake"]:
		result.set_shader_parameter("water_colour", Color(0.16, 0.25, 0.29))
		result.set_shader_parameter("flow", 0.20)
	elif kind in ["marsh", "moat", "floodplain", "wetland_lake"]:
		result.set_shader_parameter("water_colour", Color(0.22, 0.25, 0.15))
		result.set_shader_parameter("flow", 0.15)
	shared[key] = result
	return result

static func cloth(side: String) -> StandardMaterial3D:
	return surface("cloth", Color("244e66") if side == "friendly" else Color("702d2a"))

static func foliage() -> ShaderMaterial:
	if shared.has("pine_foliage"):
		return shared.pine_foliage
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;
uniform sampler2D canopy : source_color, filter_linear_mipmap;
varying float foliage_tone;
void vertex() {
    foliage_tone = INSTANCE_CUSTOM.x;
    float movement = sin(TIME*0.57+INSTANCE_CUSTOM.y*6.283+VERTEX.x*3.0+VERTEX.z*2.0)*0.014;
    VERTEX += NORMAL*movement;
}
void fragment() {
    vec4 source = texture(canopy,UV);
    ALBEDO = source.rgb * mix(vec3(0.89,0.96,0.83),vec3(1.08,1.02,0.84),foliage_tone);
    ALPHA = source.a;
    ALPHA_SCISSOR_THRESHOLD = 0.45;
    ROUGHNESS = 0.88;
    AO = 0.84;
}"""
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = shader
	result.set_shader_parameter("canopy", texture("res://assets/materials/terrain/pine-canopy-atlas-v1.png"))
	shared.pine_foliage = result
	return result
