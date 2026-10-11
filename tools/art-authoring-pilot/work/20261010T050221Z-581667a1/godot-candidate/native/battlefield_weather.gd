extends RefCounted
## Artistic weather and seasonal ground details. These do not create water,
## alter navigation, or claim to reconstruct observed historical weather.

static func profile_for_stage(stage: Dictionary) -> Dictionary:
	var historical: Dictionary = stage.get("historicalBattlefield", {})
	return historical.get("presentationWeather", {}).duplicate(true)

static func build_ground_details(scene: Node3D, stage: Dictionary, world_point: Callable, can_place: Callable) -> Dictionary:
	var profile: Dictionary = profile_for_stage(stage)
	var counts: Dictionary = {"wet_soil":0,"puddles":0,"leaves":0,"frost":0}
	if profile.is_empty():
		return counts
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = absi((str(stage.get("id", "")) + ":season-details").hash())
	var wetness: float = clampf(float(profile.get("wetness",0)),0,1)
	var leaves: float = clampf(float(profile.get("leafCoverage",0)),0,1)
	var frost: float = clampf(float(profile.get("frostCoverage",0)),0,1)
	var recipes: Array = [
		{"key":"wet_soil","count":int(wetness*38),"size":Vector2(.16,.34),"colour":Color(.25,.22,.16),"roughness":.56,"mask":0},
		{"key":"puddles","count":int(maxf(wetness-.4,0)*34),"size":Vector2(.12,.25),"colour":Color(.24,.31,.32),"roughness":.16,"mask":0},
		{"key":"leaves","count":int(leaves*155),"size":Vector2(.025,.065),"colour":Color(.49,.34,.16),"roughness":.92,"mask":1},
		{"key":"frost","count":int(frost*42),"size":Vector2(.10,.24),"colour":Color(.68,.72,.68),"roughness":.84,"mask":2}
	]
	for recipe in recipes:
		var transforms: Array[Transform3D] = []
		var colours: Array[Color] = []
		var target: int = int(recipe.count)
		for attempt in range(target*12):
			if transforms.size() >= target:
				break
			var p: Vector2 = Vector2(rng.randf_range(.035,.965),rng.randf_range(.035,.965))
			if can_place.is_valid() and not bool(can_place.call(p)):
				continue
			var center: Vector3 = world_point.call(p)
			var ex: Vector3 = world_point.call(p+Vector2(.003,0))
			var ez: Vector3 = world_point.call(p+Vector2(0,.003))
			var tangent_x: Vector3 = (ex-center).normalized()
			var tangent_z: Vector3 = (ez-center).normalized()
			var normal: Vector3 = tangent_z.cross(tangent_x).normalized()
			if normal.y < 0:
				normal = -normal
			# Puddles stay on gentle low ground. A slope's wet soil is distinct
			# from a navigational river or a flood polygon owned by the map.
			if str(recipe.key) == "puddles" and (center.y > .26 or normal.y < .975):
				continue
			var size_range: Vector2 = recipe.size
			var radius: float = rng.randf_range(size_range.x,size_range.y)
			var basis: Basis = Basis(tangent_x,normal,tangent_x.cross(normal).normalized())
			basis = basis.rotated(normal,rng.randf_range(0,TAU)).scaled(Vector3(radius,1,radius*rng.randf_range(.5,.85)))
			transforms.append(Transform3D(basis,center+normal*.011))
			var shade: float = rng.randf_range(.87,1.13)
			colours.append(Color(shade,shade,shade,1))
		if transforms.is_empty():
			continue
		var mesh: PlaneMesh = PlaneMesh.new()
		mesh.size = Vector2.ONE
		mesh.material = _detail_material(recipe)
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multimesh.set_instance_transform(index,transforms[index])
			multimesh.set_instance_color(index,colours[index])
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = "SeasonDetail_"+str(recipe.key)
		node.multimesh = multimesh
		node.layers = 1
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(node)
		counts[str(recipe.key)] = transforms.size()
	return counts

static func _detail_material(recipe: Dictionary) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color;
uniform float roughness_value = 0.8;
uniform int detail_mask = 0;
varying vec4 detail_colour;
void vertex() { detail_colour = COLOR; }
void fragment() {
    vec2 p = UV*2.0-1.0;
    float grain = sin(p.x*21.0+p.y*13.0)*sin(p.y*29.0-p.x*9.0);
    float edge = dot(p,p)+grain*0.09;
    if (detail_mask == 1) edge = abs(p.x)*0.8+abs(p.y);
    if (edge > 0.86) discard;
    if (detail_mask == 2 && grain > 0.36) discard;
    ALBEDO = tint.rgb*detail_colour.rgb*(0.95+grain*0.045);
    ROUGHNESS = roughness_value;
    SPECULAR = detail_mask == 0 ? 0.42 : 0.16;
}"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint",recipe.colour)
	material.set_shader_parameter("roughness_value",recipe.roughness)
	material.set_shader_parameter("detail_mask",recipe.mask)
	return material
