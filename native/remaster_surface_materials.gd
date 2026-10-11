extends RefCounted
## Presentation only: real CC0 scan channels. No terrain/gameplay ownership.
const SourceTextures = preload("res://native/battlefield_materials.gd")
static var shared: Dictionary = {}

static func ground(composition: Dictionary) -> ShaderMaterial:
	if str(composition.get("renderStyle","")) == "compact-smooth-v2":
		return _smooth_ground(composition)
	var result := ShaderMaterial.new()
	var program := Shader.new()
	program.code = """shader_type spatial;
render_mode cull_back;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_ao : filter_linear_mipmap, repeat_enable;
uniform sampler2D edge_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D edge_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_ao : filter_linear_mipmap, repeat_enable;
uniform vec2 route_points[8];
uniform int route_count = 7;
uniform float route_half_width = 0.525;
varying vec3 authored_world;
float distance_to_segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b-a;
	float t = clamp(dot(p-a,ab)/max(dot(ab,ab),0.0001),0.0,1.0);
	return length(p-a-ab*t);
}
void vertex() { authored_world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p = authored_world.xz;
	vec2 detail_uv = p*0.5;
	float route_distance = 100.0;
	for (int i=0; i<7; i++) {
		if (i < route_count-1) {
			route_distance = min(route_distance,distance_to_segment(p,route_points[i],route_points[i+1]));
		}
	}
	float route = 1.0-smoothstep(route_half_width*0.78,route_half_width+0.36,route_distance);
	// Sparse organic margins; the walkable slope remains one actual mesh.
	float margins = smoothstep(5.8,8.5,abs(p.x))*0.63 +
		smoothstep(4.1,6.2,abs(p.y))*0.48;
	float edge = clamp(margins,0.0,0.78)*(1.0-route);
	vec3 compacted = texture(soil_albedo,detail_uv).rgb;
	vec3 organic = texture(edge_albedo,p*0.43+vec2(0.17)).rgb;
	vec2 mud_uv = mat2(vec2(0.96,-0.28),vec2(0.28,0.96))*p/1.3;
	vec3 clods = texture(mud_albedo,mud_uv).rgb;
	// Large variation is sampled from real scan occlusion, not generated noise.
	float scan_patch = 1.0-texture(mud_ao,p*0.16+vec2(0.2)).r;
	float damp = clamp(route*0.82+scan_patch*0.27,0.0,0.94);
	ALBEDO = mix(mix(compacted,clods,damp),organic,edge);
	ALBEDO *= vec3(0.91,0.94,0.95);
	vec3 soil_detail = mix(texture(soil_normal,detail_uv).rgb,texture(mud_normal,mud_uv).rgb,damp);
	NORMAL_MAP = mix(soil_detail,texture(edge_normal,p*0.43+vec2(0.17)).rgb,edge);
	NORMAL_MAP_DEPTH = 0.43;
	ROUGHNESS = clamp(mix(texture(soil_rough,detail_uv).r,texture(mud_rough,mud_uv).r,damp)*0.89+0.08,0.46,0.98);
	SPECULAR = 0.23;
	AO = mix(texture(soil_ao,detail_uv).r,texture(mud_ao,mud_uv).r,damp);
	AO_LIGHT_AFFECT = 0.20;
}
"""
	result.shader = program
	var prefix: String = "res://assets/battlefields-remaster/materials/dirt_"
	for entry in [["soil_albedo","diff"],["soil_normal","nor_gl"],["soil_rough","rough"],["soil_ao","ao"]]:
		result.set_shader_parameter(entry[0],SourceTextures.texture(prefix+entry[1]+"_1k.jpg"))
	result.set_shader_parameter("edge_albedo",SourceTextures.texture("res://assets/materials/terrain/brown_mud_leaves_01_diff_1k.jpg"))
	result.set_shader_parameter("edge_normal",SourceTextures.texture("res://assets/materials/terrain/brown_mud_leaves_01_nor_gl_1k.jpg"))
	for entry in [["mud_albedo","diff"],["mud_normal","nor_gl"],["mud_rough","rough"],["mud_ao","ao"]]:
		result.set_shader_parameter(entry[0],SourceTextures.texture("res://assets/battlefields-remaster/materials/brown_mud_03_"+entry[1]+"_1k.jpg"))
	var route: PackedVector2Array = PackedVector2Array()
	for point in composition.get("route",[]):
		route.append(Vector2(float(point[0]),float(point[1])))
	var count: int = mini(8,route.size())
	while route.size()<8: route.append(route[-1] if not route.is_empty() else Vector2.ZERO)
	result.set_shader_parameter("route_points",route)
	result.set_shader_parameter("route_count",count)
	result.set_shader_parameter("route_half_width",float(composition.get("routeWidth",1.05))*0.5)
	return result

static func _smooth_ground(composition: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	var program := Shader.new()
	program.code = """shader_type spatial;
render_mode cull_back;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_ao : filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_rough : filter_linear_mipmap, repeat_enable;
uniform vec2 route_points[8];
uniform int route_count = 7;
uniform float route_half_width = 0.65;
uniform vec2 retreat_points[12];
uniform int retreat_count = 0;
uniform float retreat_half_width = 0.36;
// Authored colors and scan samples share the renderer's source_color working space.
uniform vec4 ground_base_color : source_color = vec4(0.5703,0.5592,0.5331,1.0);
uniform vec4 grass_base_color : source_color = vec4(0.4639,0.4918,0.4248,1.0);
uniform vec4 approach_base_color : source_color = vec4(0.5767,0.5605,0.5270,1.0);
uniform vec4 retreat_base_color : source_color = vec4(0.5322,0.5450,0.5554,1.0);
uniform vec2 camp_center = vec2(-5.0,3.4);
uniform vec2 camp_radius = vec2(2.35,1.75);
uniform vec2 fort_points[16];
uniform int fort_count = 0;
uniform vec2 fence_starts[16];
uniform vec2 fence_ends[16];
uniform int fence_count = 0;
uniform vec2 gate_start = vec2(0.0);
uniform vec2 gate_end = vec2(0.0);
uniform bool has_gate = false;
uniform vec2 rear_gate_start = vec2(0.0);
uniform vec2 rear_gate_end = vec2(0.0);
uniform bool has_rear_gate = false;
uniform bool has_earthwork = false;
uniform vec3 grove_points[32];
uniform int grove_count = 0;
// Only genuine provider-height samples qualify a source-authored earthen pad.
uniform vec4 pad_centers[4]; // WORLD XZ centre, actual mean baseY, actual centreY.
uniform vec4 pad_radii[4]; // Source top radii XY, source bank radii ZW.
uniform int pad_count = 0;
uniform float detail_contrast = 0.18;
uniform float normal_depth = 0.12;
uniform float roughness_floor = 0.91;
varying vec3 authored_world;
varying vec3 authored_world_normal;
float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab=b-a;
	float t=clamp(dot(p-a,ab)/max(dot(ab,ab),0.0001),0.0,1.0);
	return length(p-a-ab*t);
}
float inside_fort(vec2 p) {
	bool inside=false;
	for(int i=0;i<16;i++) {
		if(i<fort_count) {
			int next=i+1;
			if(next>=fort_count) next=0;
			vec2 a=fort_points[i];
			vec2 b=fort_points[next];
			if((a.y>p.y)!=(b.y>p.y)) {
				float crossing=a.x+(p.y-a.y)*(b.x-a.x)/(b.y-a.y);
				if(p.x<crossing) inside=!inside;
			}
		}
	}
	return inside ? 1.0 : 0.0;
}
float luminance(vec3 color) { return dot(color,vec3(0.2126,0.7152,0.0722)); }
vec3 material_linear(vec3 color) {
	if(!OUTPUT_IS_SRGB) return color;
	return mix(color/12.92,pow((color+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),color));
}
vec3 material_output(vec3 color) {
	color=max(color,vec3(0.0));
	if(!OUTPUT_IS_SRGB) return color;
	return mix(color*12.92,1.055*pow(color,vec3(1.0/2.4))-vec3(0.055),step(vec3(0.0031308),color));
}
void vertex() {
	authored_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	authored_world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	vec2 p=authored_world.xz;
	float distance_main=100.0;
	for(int i=0;i<7;i++) {
		if(i<route_count-1) distance_main=min(distance_main,segment_distance(p,route_points[i],route_points[i+1]));
	}
	float distance_rear=100.0;
	for(int i=0;i<11;i++) {
		if(i<retreat_count-1) distance_rear=min(distance_rear,segment_distance(p,retreat_points[i],retreat_points[i+1]));
	}
	float approach_mask=1.0-smoothstep(route_half_width*0.7,route_half_width+0.27,distance_main);
	float retreat_mask=1.0-smoothstep(retreat_half_width*0.65,retreat_half_width,distance_rear);
	float traffic=max(approach_mask,retreat_mask);
	float interior=1.0-smoothstep(0.63,0.93,length((p-camp_center)/camp_radius));
	if(fort_count>=3) interior=inside_fort(p);
	traffic=max(traffic,interior*0.93);
	float wooded=0.0;
	for(int i=0;i<32;i++) {
		if(i<grove_count) {
			vec3 grove=grove_points[i];
			vec2 offset=p-grove.xy;
			float inner=grove.z*0.28;
			wooded=max(wooded,1.0-smoothstep(inner*inner,grove.z*grove.z,dot(offset,offset)));
		}
	}
	// The annulus and playable floor use these same world coordinates and scans.
	// Broad earth/olive masses come first; the scan's stones and leaf flecks stay subdued.
	vec2 soil_uv=p*0.40;
	vec2 forest_uv=mat2(vec2(0.94,-0.34),vec2(0.34,0.94))*p*0.37;
	vec3 soil=material_linear(textureLod(soil_albedo,soil_uv,5.0).rgb);
	vec3 forest=material_linear(textureLod(forest_albedo,forest_uv,5.0).rgb);
	float soil_luma=luminance(soil);
	float forest_luma=luminance(forest);
	float broad_scan=luminance(material_linear(textureLod(forest_albedo,p*0.105+vec2(0.23,0.47),5.0).rgb));
	float broad_patch=smoothstep(0.075,0.19,broad_scan);
	float broad_ao=textureLod(soil_ao,p*0.085+vec2(0.61,0.17),5.0).r;
	float broad_earth=luminance(material_linear(textureLod(soil_albedo,p*0.19+vec2(0.43,0.27),4.0).rgb));
	// Real dirt LOD4 has linear luma .0758-.1140; the old .065-.24 range flattened it.
	float earth_patch=smoothstep(0.078,0.112,broad_earth);
	float earth_finish=(0.58+earth_patch*0.26)*(0.91+broad_ao*0.10);
	vec3 compacted=material_linear(ground_base_color.rgb)+(soil_luma-0.14)*detail_contrast;
	compacted+=(soil-vec3(soil_luma))*0.035;
	// One broad real-soil field gives dry clearing value variation, not granular noise.
	compacted*=earth_finish;
	// Both roads retain the same scanned matte earth; only the muted color temperature differs.
	vec3 approach_compacted=material_linear(approach_base_color.rgb)+(soil_luma-0.14)*detail_contrast*vec3(1.025,1.005,0.975);
	approach_compacted+=(soil-vec3(soil_luma))*0.035*vec3(1.025,1.005,0.975);
	// Same scanned earth finish as the clearing; preserve the authored muted warm tint.
	approach_compacted*=earth_finish;
	vec3 retreat_compacted=material_linear(retreat_base_color.rgb)+(soil_luma-0.14)*detail_contrast;
	retreat_compacted+=(soil-vec3(soil_luma))*0.04;
	retreat_compacted*=0.91+broad_ao*0.10;
	vec3 short_grass=material_linear(grass_base_color.rgb)*(0.64+broad_patch*0.14);
	short_grass+=(forest_luma-0.14)*detail_contrast*0.65;
	// Dry earth dominates the clearing; coherent green masses follow actual groves.
	float grove_core=smoothstep(0.48,0.94,wooded);
	float grass_mass=clamp(0.025+broad_patch*0.10+grove_core*0.82,0.0,0.90);
	float soil_mass=1.0-grass_mass*(1.0-traffic);
	vec3 ground_color=mix(short_grass,compacted,soil_mass);
	// Material distinction follows the actual raised floor, never a generated skirt.
	// Ellipse, sampled height AND unperturbed provider normal must all agree.
	float provider_grade=1.0-clamp(abs(normalize(authored_world_normal).y),0.0,1.0);
	for(int i=0;i<4;i++) {
		if(i<pad_count) {
			vec4 pad=pad_centers[i];
			vec4 radii=pad_radii[i];
			float extent=length((p-pad.xy)/radii.zw);
			float footprint=1.0-smoothstep(0.94,1.0,extent);
			float actual_rise=clamp((authored_world.y-pad.z)/max(pad.w-pad.z,0.0001),0.0,1.0);
			float height_present=smoothstep(0.04,0.18,actual_rise);
			float top_extent=length((p-pad.xy)/radii.xy);
			float crest=(1.0-smoothstep(0.88,1.14,top_extent))*smoothstep(0.84,0.97,actual_rise);
			crest*=footprint;
			float bank=footprint*height_present*smoothstep(0.009,0.09,provider_grade)*(1.0-crest*0.80);
			ground_color=mix(ground_color,compacted*0.68,bank*0.90);
			ground_color=mix(ground_color,compacted*1.08,crest*0.88);
		}
	}
	// Material traces follow actual stockade segments, not a new relief mesh.
	// Both actual openings and their causeways remove bank/cut material traces.
	float fence_distance=100.0;
	for(int i=0;i<16;i++) {
		if(i<fence_count) fence_distance=min(fence_distance,segment_distance(p,fence_starts[i],fence_ends[i]));
	}
	float gate_clear=0.0;
	if(has_gate) gate_clear=1.0-smoothstep(0.04,0.34,segment_distance(p,gate_start,gate_end));
	float rear_gate_clear=0.0;
	if(has_rear_gate) rear_gate_clear=1.0-smoothstep(0.04,0.34,segment_distance(p,rear_gate_start,rear_gate_end));
	float earthwork_clear=max(gate_clear,1.0-smoothstep(route_half_width*0.80,route_half_width+0.09,distance_main));
	earthwork_clear=max(earthwork_clear,max(rear_gate_clear,retreat_mask));
	float bank=0.0;
	float dry_cut=0.0;
	if(has_earthwork && fort_count>=3 && fence_count>0) {
		bank=(1.0-smoothstep(0.07,0.31,fence_distance))*(1.0-earthwork_clear);
		dry_cut=smoothstep(0.17,0.30,fence_distance)*(1.0-smoothstep(0.40,0.63,fence_distance));
		dry_cut*=(1.0-interior)*(1.0-earthwork_clear);
	}
	ground_color=mix(ground_color,compacted*vec3(0.92,0.94,0.88),bank*0.62);
	ground_color=mix(ground_color,compacted*vec3(0.74,0.78,0.74),dry_cut*0.70);
	ground_color=mix(ground_color,approach_compacted,approach_mask);
	// Apply the retreat color after camp soil so the trail remains continuous inside the fort.
	ground_color=mix(ground_color,retreat_compacted,retreat_mask);
	ALBEDO=material_output(ground_color);
	NORMAL_MAP=mix(textureLod(forest_normal,forest_uv,5.0).rgb,textureLod(soil_normal,soil_uv,5.0).rgb,soil_mass);
	NORMAL_MAP_DEPTH=normal_depth;
	ROUGHNESS=clamp(mix(textureLod(forest_rough,forest_uv,4.5).r,textureLod(soil_rough,soil_uv,4.5).r,soil_mass)*0.10+roughness_floor,0.89,0.99);
	SPECULAR=0.10;
	AO=mix(1.0,textureLod(soil_ao,soil_uv,4.5).r,0.12);
	AO_LIGHT_AFFECT=0.08;
}
"""
	result.shader=program
	for family in ["soil","forest"]:
		var prefix: String="res://assets/battlefields-remaster/materials/dirt_" if family=="soil" else "res://assets/materials/terrain/forest_ground_04_"
		for channel in [["albedo","diff"],["normal","nor_gl"],["rough","rough"],["ao","ao"]]:
			if family=="forest" and channel[0]=="ao": continue
			result.set_shader_parameter(family+"_"+channel[0],SourceTextures.texture(prefix+channel[1]+"_1k.jpg"))
	_bind_approach_material(result,composition)
	_bind_retreat_material(result,composition)
	_bind_road_colors(result,composition)
	var center: Array=composition.get("campCenter",[-5.0,3.4])
	var radius: Array=composition.get("campRadius",[2.35,1.75])
	result.set_shader_parameter("camp_center",Vector2(float(center[0]),float(center[1])))
	result.set_shader_parameter("camp_radius",Vector2(float(radius[0]),float(radius[1])))
	_bind_ground_footprints(result,composition)
	# Staged Visual bridge samples the SAME sole provider before this material call.
	# Missing, nonfinite, or unraised samples omit tinting rather than guess a height.
	var pad_height_samples: Dictionary=composition.get("materialPadHeightSamples",{})
	var pad_centers:=PackedVector4Array()
	var pad_radii:=PackedVector4Array()
	for area in composition.get("deploymentAreas",[]):
		var presentation: Dictionary=area.get("earthworkPresentation",{})
		if str(presentation.get("kind",""))!="low-earthen-picket-pad": continue
		var samples: Dictionary=pad_height_samples.get(str(area.get("id","")),{})
		if int(samples.get("sampleCount",0))!=16: continue
		var centre_y: float=float(samples.get("centreY",NAN))
		var base_y: float=float(samples.get("baseYMean",NAN))
		var base_min: float=float(samples.get("baseYMin",NAN))
		var base_max: float=float(samples.get("baseYMax",NAN))
		if not is_finite(centre_y) or not is_finite(base_y) or not is_finite(base_min) or not is_finite(base_max): continue
		if base_min>base_y or base_y>base_max or centre_y<=base_max+0.02: continue
		var center_xz: Array=area.get("center",[])
		var top: Array=presentation.get("topRadiiWorld",[])
		var bank: Array=presentation.get("bankRadiiWorld",[])
		if center_xz.size()!=2 or top.size()!=2 or bank.size()!=2: continue
		var radii:=Vector4(float(top[0]),float(top[1]),float(bank[0]),float(bank[1]))
		if radii.x<=0.0 or radii.y<=0.0 or radii.z<=radii.x or radii.w<=radii.y: continue
		if pad_centers.size()>=4:
			push_error("Ground material supports at most 4 provider-qualified earthen pads; additional shading omitted.")
			break
		pad_centers.append(Vector4(float(center_xz[0]),float(center_xz[1]),base_y,centre_y))
		pad_radii.append(radii)
	var pad_count: int=pad_centers.size()
	while pad_centers.size()<4:
		pad_centers.append(Vector4.ZERO)
		pad_radii.append(Vector4.ONE)
	result.set_shader_parameter("pad_centers",pad_centers)
	result.set_shader_parameter("pad_radii",pad_radii)
	result.set_shader_parameter("pad_count",pad_count)
	var finish: Dictionary=composition.get("materialStyle",{})
	result.set_shader_parameter("ground_base_color",Color.from_string(str(finish.get("groundTint","")),Color(0.285,0.273,0.246).linear_to_srgb()))
	result.set_shader_parameter("grass_base_color",Color.from_string(str(finish.get("shortGrassTint","")),Color(0.205,0.226,0.163).linear_to_srgb()))
	result.set_shader_parameter("detail_contrast",clampf(float(finish.get("microtextureContrast",0.18)),0.08,0.28))
	result.set_shader_parameter("normal_depth",clampf(float(finish.get("normalDepth",0.12)),0.05,0.18))
	result.set_shader_parameter("roughness_floor",clampf(float(finish.get("roughness",0.91)),0.89,0.96))
	return result

static func _bind_road_colors(material: ShaderMaterial, composition: Dictionary) -> void:
	# Pass authored sRGB once; source_color and the shader normalize the renderer working space.
	for road in ["approach","retreat"]:
		var presentation: Dictionary=composition.get(road+"Presentation",{})
		var linear_default:=Color(0.292125,0.274365,0.23985) if road=="approach" else Color(0.245,0.258,0.269)
		var authored_color: Color=Color.from_string(str(presentation.get("color","")),linear_default.linear_to_srgb())
		material.set_shader_parameter(road+"_base_color",authored_color)

static func _bind_approach_material(material: ShaderMaterial, composition: Dictionary) -> void:
	# Scenery continuation is ordered entry outward; reverse it before the playable route.
	# Only this presentation mask consumes the continuation; the game retains composition.route.
	var presentation: Dictionary=composition.get("approachPresentation",{})
	var outer: Dictionary=presentation.get("outerContinuation",{})
	var outer_points: Array=outer.get("points",[]).duplicate()
	outer_points.reverse()
	var route:=PackedVector2Array()
	for section in [outer_points,composition.get("route",[])]:
		for point in section:
			var world_point:=Vector2(float(point[0]),float(point[1]))
			if route.is_empty() or route[-1]!=world_point: route.append(world_point)
	if route.size()>8:
		push_error("Approach material requires at most 8 ordered WORLD XZ points including outerContinuation; received %d." % route.size())
		route.clear()
	var count: int=route.size()
	while route.size()<8: route.append(route[-1] if not route.is_empty() else Vector2.ZERO)
	material.set_shader_parameter("route_points",route)
	material.set_shader_parameter("route_count",count)
	material.set_shader_parameter("route_half_width",maxf(0.02,float(composition.get("routeWidth",1.3))*0.5))

static func _bind_retreat_material(material: ShaderMaterial, composition: Dictionary) -> void:
	# WORLD XZ color strip only. It never supplies an enemy or friendly simulation route.
	var presentation: Dictionary=composition.get("retreatPresentation",{})
	var outer: Dictionary=presentation.get("outerContinuation",{})
	var rear:=PackedVector2Array()
	for section in [composition.get("retreatTrail",[]),outer.get("points",[])]:
		for point in section:
			var world_point:=Vector2(float(point[0]),float(point[1]))
			if rear.is_empty() or rear[-1]!=world_point: rear.append(world_point)
	# An invalid authoring budget is explicit; never silently discard the forest continuation.
	if rear.size()>12:
		push_error("Retreat material requires at most 12 ordered WORLD XZ points including outerContinuation; received %d." % rear.size())
		rear.clear()
	var rear_count: int=rear.size()
	while rear.size()<12: rear.append(rear[-1] if not rear.is_empty() else Vector2.ZERO)
	material.set_shader_parameter("retreat_points",rear)
	material.set_shader_parameter("retreat_count",rear_count)
	material.set_shader_parameter("retreat_half_width",maxf(0.02,float(presentation.get("widthWorld",0.72))*0.5))

static func _bind_ground_footprints(material: ShaderMaterial, composition: Dictionary) -> void:
	var fort: Dictionary=composition.get("fort",{})
	var outline: Array=fort.get("enclosureOutline",[])
	var fort_points:=PackedVector2Array()
	# Do not silently close a truncated footprint or manufacture an earthwork.
	if outline.size()<=16:
		for point in outline: fort_points.append(Vector2(float(point[0]),float(point[1])))
	var fort_count: int=fort_points.size()
	while fort_points.size()<16: fort_points.append(Vector2.ZERO)
	material.set_shader_parameter("fort_points",fort_points)
	material.set_shader_parameter("fort_count",fort_count)
	var fence_starts:=PackedVector2Array()
	var fence_ends:=PackedVector2Array()
	var fences: Array=composition.get("fences",[])
	if fences.size()<=16:
		for fence in fences:
			var a: Array=fence.get("a",[])
			var b: Array=fence.get("b",[])
			if a.size()<2 or b.size()<2: continue
			fence_starts.append(Vector2(float(a[0]),float(a[1])))
			fence_ends.append(Vector2(float(b[0]),float(b[1])))
	var fence_count: int=fence_starts.size()
	while fence_starts.size()<16:
		fence_starts.append(Vector2.ZERO)
		fence_ends.append(Vector2.ZERO)
	material.set_shader_parameter("fence_starts",fence_starts)
	material.set_shader_parameter("fence_ends",fence_ends)
	material.set_shader_parameter("fence_count",fence_count)
	var opening: Array=fort.get("openingSegment",[])
	var has_gate: bool=opening.size()==2
	material.set_shader_parameter("has_gate",has_gate)
	if has_gate:
		material.set_shader_parameter("gate_start",Vector2(float(opening[0][0]),float(opening[0][1])))
		material.set_shader_parameter("gate_end",Vector2(float(opening[1][0]),float(opening[1][1])))
	var rear_opening: Array=fort.get("rearOpeningSegment",[])
	var has_rear_gate: bool=rear_opening.size()==2
	material.set_shader_parameter("has_rear_gate",has_rear_gate)
	if has_rear_gate:
		material.set_shader_parameter("rear_gate_start",Vector2(float(rear_opening[0][0]),float(rear_opening[0][1])))
		material.set_shader_parameter("rear_gate_end",Vector2(float(rear_opening[1][0]),float(rear_opening[1][1])))
	var earthwork: Dictionary=composition.get("earthwork",{})
	material.set_shader_parameter("has_earthwork",float(earthwork.get("bankLocalReliefMax",0.0))>0.0 or float(earthwork.get("ditchLocalCutMax",0.0))>0.0)
	var groves: PackedVector3Array=_grove_color_fields(composition)
	var grove_count: int=groves.size()
	while groves.size()<32: groves.append(Vector3.ZERO)
	material.set_shader_parameter("grove_points",groves)
	material.set_shader_parameter("grove_count",grove_count)

static func _grove_color_fields(composition: Dictionary) -> PackedVector3Array:
	# Broad material fields only: authored peripheral groves, then coarse world cells.
	# No plant transforms or gameplay/deployment zones are derived from these groups.
	var points_by_group: Dictionary={}
	var scenery: Dictionary=composition.get("landscapeScenery",{})
	for area in [composition,scenery]:
		for family in ["trees","bushes"]:
			for plant in area.get(family,[]):
				var x: float=float(plant.get("x",0.0))
				var z: float=float(plant.get("z",0.0))
				var scale: float=maxf(0.0,float(plant.get("scale",1.0)))
				var spread: float=scale*(1.5 if family=="trees" else 1.2)+0.42
				var authored_group: String=str(plant.get("groveId",""))
				var key: String="authored:"+authored_group if not authored_group.is_empty() else "cell:%d:%d" % [floori(x/3.5),floori(z/3.5)]
				if not points_by_group.has(key): points_by_group[key]=[]
				points_by_group[key].append(Vector3(x,z,spread))
	var groups: Array[Dictionary]=[]
	for points in points_by_group.values():
		var total:=Vector2.ZERO
		for point in points: total+=Vector2(point.x,point.y)
		groups.append({"total":total,"count":points.size(),"points":points})
	# Preserve every input plant if a later composition exceeds the shader's fixed cap.
	while groups.size()>32:
		var closest_distance: float=INF
		var closest_a: int=0
		var closest_b: int=1
		for a in range(groups.size()-1):
			var a_center: Vector2=groups[a].total/float(groups[a].count)
			for b in range(a+1,groups.size()):
				var b_center: Vector2=groups[b].total/float(groups[b].count)
				var distance: float=a_center.distance_squared_to(b_center)
				if distance<closest_distance:
					closest_distance=distance
					closest_a=a
					closest_b=b
		groups[closest_a].total+=groups[closest_b].total
		groups[closest_a].count+=groups[closest_b].count
		groups[closest_a].points.append_array(groups[closest_b].points)
		groups.remove_at(closest_b)
	var fields:=PackedVector3Array()
	for group in groups:
		var center: Vector2=group.total/float(group.count)
		var radius: float=0.0
		for point in group.points:
			radius=maxf(radius,center.distance_to(Vector2(point.x,point.y))+point.z)
		fields.append(Vector3(center.x,center.y,radius))
	return fields

static func canopy(composition: Dictionary = {}) -> ShaderMaterial:
	# Opaque static crown meshes supply authored sRGB vertex colors and smooth normals.
	# The existing scan contributes quiet luminance only, never leaf-atlas padding or alpha.
	var material:=ShaderMaterial.new()
	var program: Shader
	if shared.has("canopy_program"):
		program=shared.canopy_program
	else:
		program=Shader.new()
		program.code="""shader_type spatial;
render_mode cull_back;
uniform sampler2D forest_diffuse : source_color, filter_linear_mipmap, repeat_enable;
uniform float detail_contrast = 0.05;
varying vec3 canopy_world;
vec3 from_srgb(vec3 color) {
	return mix(color/12.92,pow((color+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),color));
}
vec3 to_output(vec3 color) {
	color=max(color,vec3(0.0));
	if(!OUTPUT_IS_SRGB) return color;
	return mix(color*12.92,1.055*pow(color,vec3(1.0/2.4))-vec3(0.055),step(vec3(0.0031308),color));
}
void vertex() { canopy_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec3 scan=textureLod(forest_diffuse,canopy_world.xz*0.22+vec2(0.31,0.17),4.0).rgb;
	if(OUTPUT_IS_SRGB) scan=from_srgb(scan);
	float scan_luma=dot(scan,vec3(0.2126,0.7152,0.0722));
	float modulation=clamp(1.0+(scan_luma-0.14)*detail_contrast,0.96,1.04);
	// A small dark backing supplies canopy depth beneath the actual curved leaf sprays.
	ALBEDO=to_output(from_srgb(COLOR.rgb)*modulation*0.62);
	ROUGHNESS=0.94;
	SPECULAR=0.12;
}
"""
		shared.canopy_program=program
	material.shader=program
	material.set_shader_parameter("forest_diffuse",SourceTextures.texture("res://assets/materials/terrain/forest_ground_04_diff_1k.jpg"))
	var finish: Dictionary=composition.get("materialStyle",{})
	material.set_shader_parameter("detail_contrast",clampf(float(finish.get("microtextureContrast",0.10))*0.5,0.0,0.08))
	return material

static func leaf_spray(composition: Dictionary = {}) -> ShaderMaterial:
	# Curved opaque card outlines provide the leaf silhouette. UVs stay inside a
	# verified green interior of the real shrub scan; JPEG atlas padding never colors it.
	var material:=ShaderMaterial.new()
	var program: Shader
	if shared.has("leaf_spray_program"):
		program=shared.leaf_spray_program
	else:
		program=Shader.new()
		program.code="""shader_type spatial;
render_mode cull_disabled;
uniform sampler2D leaf_diffuse : source_color, filter_linear_mipmap, repeat_disable;
uniform float vein_contrast = 0.28;
vec3 from_srgb(vec3 color) {
	return mix(color/12.92,pow((color+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),color));
}
vec3 to_output(vec3 color) {
	color=max(color,vec3(0.0));
	if(!OUTPUT_IS_SRGB) return color;
	return mix(color*12.92,1.055*pow(color,vec3(1.0/2.4))-vec3(0.055),step(vec3(0.0031308),color));
}
void fragment() {
	// Inset the verified (.455,.16)-(.58,.295) crop by more than one source texel.
	vec2 leaf_uv=clamp(UV,vec2(0.457,0.162),vec2(0.578,0.293));
	vec3 leaf=textureLod(leaf_diffuse,leaf_uv,0.5).rgb;
	if(OUTPUT_IS_SRGB) leaf=from_srgb(leaf);
	float leaf_luma=dot(leaf,vec3(0.2126,0.7152,0.0722));
	float vein=clamp((leaf_luma-0.20)/0.20,-0.65,0.65);
	float modulation=1.0+vein*vein_contrast;
	ALBEDO=to_output(from_srgb(COLOR.rgb)*modulation);
	ROUGHNESS=0.94;
	SPECULAR=0.10;
}
"""
		shared.leaf_spray_program=program
	material.shader=program
	material.set_shader_parameter("leaf_diffuse",SourceTextures.texture("res://assets/models/battlefield/shrub_01/textures/shrub_01_diff_1k.jpg"))
	# Authored materialStyle is retained for API consistency; vein contrast has its
	# own bounded material-only scale rather than amplifying the terrain's microdetail.
	var finish: Dictionary=composition.get("materialStyle",{})
	material.set_shader_parameter("vein_contrast",clampf(float(finish.get("leafVeinContrast",0.28)),0.20,0.35))
	return material

static func cloth() -> StandardMaterial3D:
	if shared.has("cloth"): return shared.cloth
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("ada993")
	material.roughness=0.97
	material.metallic_specular=0.12
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	shared.cloth=material
	return material

static func scan(family: String) -> Material:
	if shared.has(family): return shared[family]
	var material := StandardMaterial3D.new()
	var source: String = "weathered_brown_planks" if family=="timber" else "rock_boulder_dry"
	var prefix: String = "res://assets/materials/terrain/"+source
	material.albedo_texture = SourceTextures.texture(prefix+"_diff_1k.jpg")
	material.normal_enabled = true
	material.normal_texture = SourceTextures.texture(prefix+"_nor_gl_1k.jpg")
	material.normal_scale = 0.26 if family=="timber" else 0.20
	material.roughness_texture = SourceTextures.texture(prefix+"_rough_1k.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness = 1.0
	material.metallic_specular = 0.10
	material.albedo_color = Color(0.78,0.80,0.79) if family=="timber" else Color(0.72,0.75,0.76)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var finished: Material=_static_scan_finish(material,"timber") if family=="timber" else material
	shared[family] = finished
	return finished

static func presentation_scan(source: BaseMaterial3D, family: String) -> Material:
	# Static scenery only. Unsupported configurations keep their duplicated material.
	if source==null: return null
	var material: BaseMaterial3D=source.duplicate() as BaseMaterial3D
	# Current native importer retains bark surfaces but calls them foliage.
	# Identify the inspected bark material only; leaf/grass alpha materials stay intact.
	var finish_family: String="trunk" if family=="foliage" and source.resource_name.to_lower().contains("bark") else family
	if finish_family in ["stone","trunk"] and _supports_scan_finish(source):
		return _static_scan_finish(source,finish_family)
	var tint:=Color.WHITE
	var normal_limit: float=0.20
	match family:
		"timber":
			tint=Color(0.78,0.80,0.79)
			normal_limit=0.26
		"stone":
			tint=Color(0.72,0.75,0.76)
		"foliage":
			tint=Color(0.72,0.79,0.73)
			normal_limit=0.12
		"grass":
			tint=Color(0.76,0.81,0.76)
			normal_limit=0.08
		_:
			return material
	material.albedo_color*=tint
	material.normal_scale=minf(material.normal_scale,normal_limit)
	material.roughness=maxf(material.roughness,0.94)
	material.metallic=0.0
	material.metallic_specular=minf(material.metallic_specular,0.10)
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

static func _supports_scan_finish(source: BaseMaterial3D) -> bool:
	# The inspected stone and bark scans are opaque, UV1, double-sided materials.
	# Preserve unfamiliar alpha, vertex-color, UV2 AO and triplanar configurations.
	return source.albedo_texture!=null and source.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and is_zero_approx(source.metallic) and not source.uv1_triplanar and not source.vertex_color_use_as_albedo and not source.ao_on_uv2

static func _scan_finish_texture(source: Texture2D) -> Texture2D:
	if source==null: return null
	var path: String=source.resource_path
	if not path.is_empty() and ResourceLoader.exists(path):
		# Same scan pixels; the established cache adds runtime mipmaps without asset writes.
		var cached: Texture2D=SourceTextures.texture(path)
		if cached!=null: return cached
	return source

static func _roughness_channel_weight(channel: int) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return Vector4(0,1,0,0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return Vector4(0,0,1,0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return Vector4(0,0,0,1)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: return Vector4(0.333333,0.333333,0.333333,0)
		_: return Vector4(1,0,0,0)

static func _static_scan_finish(source: BaseMaterial3D, family: String) -> ShaderMaterial:
	# Static scenery only. Original channels, UV transform and culling remain the source.
	var material:=ShaderMaterial.new()
	var cache_key: String="static_scan_program:%d:%s" % [source.cull_mode,str(source.texture_repeat)]
	var program: Shader
	if shared.has(cache_key):
		program=shared[cache_key]
	else:
		var cull_rule: String="cull_disabled" if source.cull_mode==BaseMaterial3D.CULL_DISABLED else "cull_front" if source.cull_mode==BaseMaterial3D.CULL_FRONT else "cull_back"
		program=Shader.new()
		program.code="""shader_type spatial;
render_mode CULL_RULE;
uniform sampler2D scan_diffuse : source_color, filter_linear_mipmap_anisotropic, REPEAT_RULE;
uniform sampler2D scan_normal : hint_normal, filter_linear_mipmap_anisotropic, REPEAT_RULE;
uniform sampler2D scan_rough : filter_linear_mipmap, REPEAT_RULE;
uniform sampler2D scan_ao : filter_linear_mipmap, REPEAT_RULE;
uniform vec4 source_tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec4 rough_channel = vec4(1.0,0.0,0.0,0.0);
uniform vec4 ao_channel = vec4(1.0,0.0,0.0,0.0);
uniform bool has_normal = false;
uniform bool has_rough = false;
uniform bool has_ao = false;
uniform float chroma_strength = 0.12;
uniform float fine_strength = 0.12;
uniform float fine_lod = 1.5;
uniform float broad_lod = 2.5;
uniform float normal_lod = 3.0;
uniform float normal_depth = 0.10;
uniform float rough_scalar = 1.0;
uniform float specular_amount = 0.08;
vec3 material_linear(vec3 color) {
	if(!OUTPUT_IS_SRGB) return color;
	return mix(color/12.92,pow((color+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),color));
}
vec3 material_output(vec3 color) {
	color=max(color,vec3(0.0));
	if(!OUTPUT_IS_SRGB) return color;
	return mix(color*12.92,1.055*pow(color,vec3(1.0/2.4))-vec3(0.055),step(vec3(0.0031308),color));
}
float luminance(vec3 color) { return dot(color,vec3(0.2126,0.7152,0.0722)); }
void fragment() {
	vec2 scan_uv=UV*uv_scale+uv_offset;
	vec3 fine=material_linear(textureLod(scan_diffuse,scan_uv,fine_lod).rgb);
	vec3 broad=material_linear(textureLod(scan_diffuse,scan_uv,broad_lod).rgb);
	float broad_value=luminance(broad);
	// Broad real cracks/grain retain value; only fine freckles and excess chroma recede.
	vec3 finish=vec3(broad_value+(luminance(fine)-broad_value)*fine_strength);
	finish+=(broad-vec3(broad_value))*chroma_strength;
	ALBEDO=material_output(finish*material_linear(source_tint.rgb));
	NORMAL_MAP=has_normal ? textureLod(scan_normal,scan_uv,normal_lod).rgb : vec3(0.5,0.5,1.0);
	NORMAL_MAP_DEPTH=has_normal ? normal_depth : 0.0;
	float rough=has_rough ? dot(textureLod(scan_rough,scan_uv,3.0),rough_channel)*rough_scalar : rough_scalar;
	ROUGHNESS=clamp(0.92+rough*0.06,0.92,0.99);
	// Both inspected GLTF materials are nonmetallic (metallicFactor=0).
	METALLIC=0.0;
	SPECULAR=specular_amount;
	AO=has_ao ? mix(1.0,dot(textureLod(scan_ao,scan_uv,3.0),ao_channel),0.18) : 1.0;
	AO_LIGHT_AFFECT=0.08;
}
""".replace("CULL_RULE",cull_rule).replace("REPEAT_RULE","repeat_enable" if source.texture_repeat else "repeat_disable")
		shared[cache_key]=program
	material.shader=program
	# StandardMaterial imports expose roughness separately; ORM imports use G/R.
	var orm: Texture2D=source.orm_texture if source is ORMMaterial3D else null
	var rough_texture: Texture2D=orm if orm!=null else source.roughness_texture
	var ao_texture: Texture2D=orm if orm!=null else source.ao_texture
	material.set_shader_parameter("scan_diffuse",_scan_finish_texture(source.albedo_texture))
	material.set_shader_parameter("scan_normal",_scan_finish_texture(source.normal_texture))
	material.set_shader_parameter("scan_rough",_scan_finish_texture(rough_texture))
	material.set_shader_parameter("scan_ao",_scan_finish_texture(ao_texture))
	material.set_shader_parameter("has_normal",source.normal_enabled and source.normal_texture!=null)
	material.set_shader_parameter("has_rough",rough_texture!=null)
	material.set_shader_parameter("has_ao",source.ao_enabled and ao_texture!=null)
	material.set_shader_parameter("rough_channel",_roughness_channel_weight(BaseMaterial3D.TEXTURE_CHANNEL_GREEN if orm!=null else source.roughness_texture_channel))
	material.set_shader_parameter("ao_channel",_roughness_channel_weight(BaseMaterial3D.TEXTURE_CHANNEL_RED if orm!=null else source.ao_texture_channel))
	material.set_shader_parameter("rough_scalar",source.roughness)
	material.set_shader_parameter("uv_scale",Vector2(source.uv1_scale.x,source.uv1_scale.y))
	material.set_shader_parameter("uv_offset",Vector2(source.uv1_offset.x,source.uv1_offset.y))
	material.set_shader_parameter("specular_amount",minf(source.metallic_specular,0.08))
	# scan("timber") has already applied its existing neutral weathering tint once.
	var tint: Color=Color(0.72,0.73,0.74) if family=="stone" else Color(0.82,0.79,0.75) if family=="trunk" else Color.WHITE
	material.set_shader_parameter("source_tint",source.albedo_color*tint)
	var normal_limit: float=0.10 if family=="stone" else 0.12 if family=="trunk" else 0.17
	material.set_shader_parameter("normal_depth",minf(source.normal_scale,normal_limit))
	if family!="stone":
		material.set_shader_parameter("chroma_strength",0.56 if family=="trunk" else 0.52)
		material.set_shader_parameter("fine_strength",0.20 if family=="trunk" else 0.28)
		material.set_shader_parameter("fine_lod",1.0)
		material.set_shader_parameter("broad_lod",2.2 if family=="trunk" else 2.0)
		material.set_shader_parameter("normal_lod",2.4 if family=="trunk" else 2.0)
	return material

static func rope() -> StandardMaterial3D:
	if shared.has("rope"): return shared.rope
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("80765e")
	material.roughness = 1.0
	material.metallic_specular = 0.10
	shared.rope = material
	return material

static func metal() -> StandardMaterial3D:
	if shared.has("metal"): return shared.metal
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("5b5d58")
	material.metallic = 0.72
	material.roughness = 0.81
	shared.metal = material
	return material
