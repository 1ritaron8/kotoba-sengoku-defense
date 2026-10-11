extends RefCounted
## Muted worn faction lacquer and navy cloth on the authored joint mesh.

static var shared_material: ShaderMaterial
static var shared_contact_material: ShaderMaterial
static var shared_preview_material: ShaderMaterial

const ART_DIRECTION: String = "period_worn_3d_v1"

static func configure_actor_material(value: ShaderMaterial, hostile: bool, unit_type: String) -> void:
	# Every soldier owns these uniforms. All original meshes/animation caches
	# remain shared; preview/standing actors must not change another team.
	value.set_shader_parameter("hostile_team",hostile)
	value.set_shader_parameter("unit_style",1 if unit_type=="monk" else 2 if unit_type=="ninja" else 0)
	value.set_meta("art_direction",ART_DIRECTION)
	value.set_meta("actor_type",unit_type)

static func placement_preview_material() -> ShaderMaterial:
	if shared_preview_material != null:
		return shared_preview_material
	# A private transparent shader reads the same baked material recipes. It
	# never changes the cached opaque materials used by actual combat actors.
	# Splice preview colour math before the shared final ALBEDO output boundary.
	var source: ShaderMaterial = material()
	var shader: Shader = Shader.new()
	shader.code = source.shader.code.replace("render_mode cull_disabled;","render_mode blend_mix, depth_draw_never, cull_disabled;").replace("NORMAL_MAP_DEPTH = normal_depth;","NORMAL_MAP_DEPTH = normal_depth;\n    ALBEDO = mix(ALBEDO/max(local_exposure,0.55),vec3(0.58,0.70,0.67),0.62)*clamp(local_exposure,0.94,1.20);\n    float preview_rim = pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),2.0);\n    EMISSION = vec3(0.48,0.68,0.62)*(0.055+preview_rim*0.18);\n    ALPHA = 0.75;")
	shared_preview_material = source.duplicate(false)
	shared_preview_material.shader = shader
	return shared_preview_material

static func contact_shadow_material() -> ShaderMaterial:
	if shared_contact_material != null:
		return shared_contact_material
	var shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
    vec2 point = (UV-vec2(0.5))*2.0;
    float falloff = 1.0-smoothstep(0.08,1.0,dot(point,point));
    ALBEDO = vec3(0.045,0.042,0.032);
    ALPHA = falloff*0.19;
}"""
	shared_contact_material = ShaderMaterial.new()
	shared_contact_material.shader = shader
	return shared_contact_material

static func material() -> ShaderMaterial:
	if shared_material != null:
		return shared_material
	var shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D steel_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloth_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D leather_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D steel_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloth_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D leather_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D steel_colour : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloth_colour : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D leather_colour : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sengoku_surface : source_color, filter_linear_mipmap;
uniform bool use_sengoku_surface = false;
uniform bool hostile_team = false;
uniform int unit_style = 0;
uniform vec3 friendly_armour = vec3(0.028,0.045,0.060);
uniform vec3 hostile_armour = vec3(0.130,0.032,0.024);
uniform float local_exposure = 1.0;
uniform vec3 local_tint = vec3(1.0);
uniform float local_saturation = 1.0;
uniform float local_roughness_bias = 0.0;
uniform float departure_fade = 0.0;
varying vec4 surface_recipe;
varying vec3 surface_colour;
varying vec3 surface_position;
vec3 sampled_colour(vec3 value) {
    // The calibrated references below are linear. Compatibility returns
    // source_color samples as sRGB; the other renderers already decode them.
    if (OUTPUT_IS_SRGB) {
        return mix(value/12.92,pow((value+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),value));
    }
    return value;
}
void vertex() {
    surface_recipe = CUSTOM0;
    surface_colour = COLOR.rgb;
    surface_position = VERTEX;
}
void fragment() {
    ALBEDO = surface_colour;
    // Per-actor departure works in GL Compatibility without alpha blending.
    if (departure_fade > 0.0) {
        float pixel = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
        if (pixel < departure_fade) { discard; }
    }
    METALLIC = surface_recipe.x;
    ROUGHNESS = surface_recipe.y;
    SPECULAR = 0.40;
    float texture_family = surface_recipe.z;
    bool lacquer_surface = abs(texture_family-0.10)<0.01 || abs(texture_family-0.25)<0.01;
    bool team_cloth = abs(texture_family-1.25)<0.01;
    bool rope_surface = abs(texture_family-1.35)<0.01;
    vec3 team_colour = hostile_team ? hostile_armour : friendly_armour;
    vec3 normal_value = vec3(0.5,0.5,1.0);
    float roughness_value = 0.5;
    float colour_variation = 1.0;
    float normal_depth = surface_recipe.w*0.35;
    AO = 1.0;
    if (texture_family < 0.5) {
        normal_value = texture(steel_normal,UV).rgb;
        roughness_value = texture(steel_rough,UV).r;
        vec3 source_colour = sampled_colour(texture(steel_colour,UV).rgb);
        float luma = dot(source_colour,vec3(0.2126,0.7152,0.0722));
        colour_variation = mix(0.97,1.03,smoothstep(0.025,0.37,luma));
        // Broad authored plate bevels supply the highlights. The worn atlas
        // and subpixel hammered grain no longer muddy the small live model.
        if (lacquer_surface) {
            ALBEDO = team_colour*surface_colour;
            METALLIC = 0.18;
            ROUGHNESS = 0.66;
            SPECULAR = 0.28;
        }
        normal_depth = min(normal_depth,0.06);
    } else if (texture_family < 1.5) {
        normal_value = texture(cloth_normal,UV*2.0).rgb;
        roughness_value = texture(cloth_rough,UV*2.0).r;
        vec3 source_colour = sampled_colour(texture(cloth_colour,UV*2.0).rgb);
        colour_variation = mix(0.97,1.02,smoothstep(0.008,0.23,dot(source_colour,vec3(0.2126,0.7152,0.0722))));
        if (!rope_surface && texture_family<1.40) {
            vec3 fabric = hostile_team ? vec3(0.073,0.033,0.039) : vec3(0.030,0.046,0.081);
            if (team_cloth) fabric = mix(fabric,team_colour,0.16);
            if (unit_style==1) fabric=vec3(0.34,0.30,0.21);
            if (unit_style==2) fabric=vec3(0.023,0.030,0.049);
            ALBEDO = fabric*surface_colour;
        }
        normal_depth = min(normal_depth,0.035);
        ROUGHNESS = 0.77;
        SPECULAR = 0.20;
    } else if (texture_family < 2.5) {
        normal_value = texture(leather_normal,UV).rgb;
        roughness_value = texture(leather_rough,UV).r;
        vec3 source_colour = sampled_colour(texture(leather_colour,UV).rgb);
        colour_variation = mix(0.96,1.03,smoothstep(0.02,0.30,dot(source_colour,vec3(0.2126,0.7152,0.0722))));
        normal_depth = min(normal_depth,0.055);
        SPECULAR = 0.30;
    } else {
        normal_depth = 0.0;
        float detail_kind = surface_recipe.w;
        if (detail_kind>0.5 && detail_kind<1.5) {
            // Existing sculpted facial planes and vertex shading remain.
            // Clean skin avoids noisy pores masquerading as dark face pixels.
            ROUGHNESS = 0.72;
            SPECULAR = 0.24;
        } else if (detail_kind>1.5 && detail_kind<2.5) {
            ROUGHNESS = 0.72;
            SPECULAR = 0.22;
        } else if (detail_kind>2.5 && detail_kind<3.5) {
            ROUGHNESS = 0.32;
            SPECULAR = 0.54;
        } else if (detail_kind>3.5 && detail_kind<4.5) {
            ROUGHNESS = 0.66;
            SPECULAR = 0.32;
        }
    }
    // Both armies are real lit surfaces; no emissive silhouette or fake rim.
    ALBEDO *= colour_variation;
    float local_luma = dot(ALBEDO,vec3(0.2126,0.7152,0.0722));
    ALBEDO = mix(vec3(local_luma),ALBEDO,local_saturation)*local_tint*local_exposure;
    ROUGHNESS = clamp(ROUGHNESS + (roughness_value-0.5)*0.035 + local_roughness_bias,0.28,0.92);
    NORMAL_MAP = normal_value;
    NORMAL_MAP_DEPTH = normal_depth;
    // Pigments and all multiplication above stay linear. The rendered
    // Compatibility probe matched StandardMaterial only at this boundary.
    // The preview splice also completes its linear colour edits above here.
    if (OUTPUT_IS_SRGB) {
        vec3 linear_albedo = max(ALBEDO,vec3(0.0));
        ALBEDO = mix(linear_albedo*12.92,1.055*pow(linear_albedo,vec3(1.0/2.4))-vec3(0.055),step(vec3(0.0031308),linear_albedo));
    }
}"""
	shared_material = ShaderMaterial.new()
	shared_material.shader = shader
	for family in [{"prefix":"steel","id":"metal_plate_02"},{"prefix":"cloth","id":"denim_fabric"},{"prefix":"leather","id":"brown_leather"}]:
		for channel in [{"parameter":"normal","file":"nor_gl"},{"parameter":"rough","file":"rough"},{"parameter":"colour","file":"diff"}]:
			var path: String = "res://assets/materials/%s/%s.jpg" % [family.id,channel.file]
			if ResourceLoader.exists(path):
				shared_material.set_shader_parameter("%s_%s" % [family.prefix,channel.parameter],load(path))
	var atlas_path: String = "res://assets/materials/sengoku/surface-atlas-v1.png"
	if ResourceLoader.exists(atlas_path):
		shared_material.set_shader_parameter("sengoku_surface",load(atlas_path))
		shared_material.set_shader_parameter("use_sengoku_surface",true)
	return shared_material

static func batch_by_joint(pieces: Array, recipes: Dictionary) -> Array:
	var builders: Dictionary = {}
	for piece in pieces:
		var bone_name: String = str(piece.bone)
		if not builders.has(bone_name):
			var builder = SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builder.set_custom_format(0,SurfaceTool.CUSTOM_RGBA_FLOAT)
			builders[bone_name] = builder
		var tool: SurfaceTool = builders[bone_name]
		var source_material: StandardMaterial3D = recipes[str(piece.material)]
		var recipe: Dictionary = source_material.get_meta("surface_recipe",{})
		var tint: Color = recipe.get("colour",source_material.albedo_color)
		var metallic_value: float = float(recipe.get("metallic",source_material.metallic))
		var roughness_value: float = float(recipe.get("roughness",source_material.roughness))
		var normal_strength: float = float(recipe.get("normalScale",source_material.normal_scale if source_material.normal_enabled else 0.0))
		var texture_name: String = str(recipe.get("texture",""))
		if texture_name.is_empty() and source_material.normal_texture != null:
			texture_name = source_material.normal_texture.resource_path.get_base_dir().get_file()
		var texture_family: float = 0.0 if texture_name=="metal_plate_02" else 1.0 if texture_name=="denim_fabric" else 2.0 if texture_name=="brown_leather" else 3.0
		if str(piece.material) in ["lacquer","battle_lacquer"]:
			texture_family = 0.10
		if bool(recipe.get("teamSurface",false)) and texture_family<1.5:
			texture_family += 0.25
		# Firing-cover banners and bindings also use this batching helper.
		# Preserve their authored cloth pigments instead of dyeing every prop
		# as a soldier's navy undershirt.
		if texture_family>=.5 and texture_family<1.5 and str(piece.material) not in ["cloth","faction_cloth","cord","faction_cord","faction_binding"]:
			texture_family=1.45
		if texture_family==2.0 and str(piece.material) in ["wood","coat"]:
			texture_family=2.25
		if texture_family==3.0:
			var face_key: String = str(piece.material)
			normal_strength = 1.0 if face_key=="skin" else 2.0 if face_key=="hair" else 3.0 if face_key in ["eye","eye_white","iris"] else 4.0 if face_key=="lip" else 0.0
		# Colour/response only: the original position, normal, UV and triangle
		# order below are copied unchanged. A separate rope tag keeps cream
		# odoshi/binding distinct from dark cloth in field and standing models.
		var clean: Dictionary = surface_palette(str(piece.material))
		if not clean.is_empty():
			tint = clean.colour
			metallic_value = float(clean.metallic)
			roughness_value = float(clean.roughness)
			if bool(clean.get("rope",false)): texture_family=1.35
		var mesh: ArrayMesh = piece.mesh
		for surface in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for cursor in range(count):
				var index: int = indices[cursor] if not indices.is_empty() else cursor
				tool.set_normal(normals[index])
				tool.set_uv(uvs[index] if index<uvs.size() else Vector2.ZERO)
				var vertex_colour: Color = colours[index] if index<colours.size() else Color.WHITE
				tool.set_color(tint*vertex_colour)
				tool.set_custom(0,Color(metallic_value,roughness_value,texture_family,normal_strength))
				tool.add_vertex(vertices[index])
	var result: Array = []
	for bone_name in builders:
		var tool: SurfaceTool = builders[bone_name]
		tool.index()
		tool.generate_tangents()
		result.append({"bone":bone_name,"material":"combined","mesh":tool.commit()})
	return result

static func surface_palette(key: String) -> Dictionary:
	match key:
		"lacquer","battle_lacquer": return {"colour":Color.WHITE,"metallic":.18,"roughness":.66}
		"cloth","faction_cloth": return {"colour":Color.WHITE,"metallic":0.0,"roughness":.77}
		"cord","faction_cord","faction_binding": return {"colour":_pigment("d8cfac"),"metallic":0.0,"roughness":.77,"rope":true}
		"metal": return {"colour":_pigment("9eadb8"),"metallic":.48,"roughness":.40}
		"gold": return {"colour":_pigment("b89349"),"metallic":.52,"roughness":.43}
		"leather": return {"colour":_pigment("685442"),"metallic":0.0,"roughness":.68}
		"wood": return {"colour":_pigment("8f6240"),"metallic":0.0,"roughness":.74}
		"coat": return {"colour":_pigment("996943"),"metallic":0.0,"roughness":.78}
		"skin": return {"colour":_pigment("cdb8a6"),"metallic":0.0,"roughness":.72}
		"skin_shadow": return {"colour":_pigment("a47c62"),"metallic":0.0,"roughness":.70}
		"eye_white","eye": return {"colour":_pigment("ddd5c5"),"metallic":0.0,"roughness":.32}
		"iris": return {"colour":_pigment("211c1a"),"metallic":0.0,"roughness":.32}
		"hair": return {"colour":_pigment("201c1d"),"metallic":0.0,"roughness":.72}
		"lip": return {"colour":_pigment("b9816d"),"metallic":0.0,"roughness":.66}
	return {}

static func _pigment(srgb: String) -> Color:
	# Bake display pigments once into linear COLOR for shared colour math.
	# The fragment's final output boundary handles the renderer encoding.
	return Color(srgb).srgb_to_linear()

static func style_contract() -> Dictionary:
	return {"id":ART_DIRECTION,"friendlyArmorLinear":Vector3(.028,.045,.060),"hostileArmorLinear":Vector3(.130,.032,.024),"geometry":"Authored mesh, rig, proportions and locomotion retained","surface":"Muted slate/navy and iron/rust lacquer, dark navy fabric, cream binding, existing steel/gold and skin; restrained existing texture normals","illumination":"Real shared sun and terrain/contact shadows; individual authored shade"}
