extends Node3D
## Render-only Sengoku firing cover. No health, AI, collider or combat registration.
## One combined mesh per emplacement; geometry, shader and textures are cached.

const ActorMaterials = preload("res://native/actor_materials.gd")
static var mesh_cache: Dictionary = {}
var kind: String = "enemy_archer"
var shell: MeshInstance3D
var surface_material: ShaderMaterial
var broken: bool = false
var last_light: Dictionary = {}

func configure(kind_value: String) -> void:
	kind = kind_value if kind_value in ["enemy_archer", "enemy_gunner"] else "enemy_archer"
	if shell == null:
		shell = MeshInstance3D.new()
		shell.name = "FiringCover"
		shell.layers = 3
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(shell)
		surface_material = ActorMaterials.material().duplicate(false)
		shell.material_override = surface_material
	broken = false
	shell.mesh = build_mesh(kind, false)
	set_meta("render_only", true)
	set_meta("fortification_kind", kind)

func apply_state(data: Dictionary) -> void:
	var next_broken: bool = bool(data.get("dead", false)) or str(data.get("animation", "")) == "death"
	if next_broken != broken:
		broken = next_broken
		shell.mesh = build_mesh(kind, broken)
	# The crew remains an independently articulated actor. Only the low cover
	# changes into fallen boards during the shared logical death interval.
	visible = not bool(data.get("sailing", false))
	var fall: float = smoothstep(0.0, 0.6667, maxf(0.0, float(data.get("animationClock", 0.0)))) if broken else 0.0
	shell.position.y = -0.012 * fall

func set_local_light(exposure: float, tint: Color, saturation: float = 1.0, roughness_bias: float = 0.0) -> void:
	var values: Dictionary = {"exposure": exposure, "tint": tint, "saturation": saturation, "roughness": roughness_bias}
	if surface_material == null or values == last_light:
		return
	last_light = values
	surface_material.set_shader_parameter("local_exposure", clampf(exposure, 0.55, 1.45))
	surface_material.set_shader_parameter("local_tint", Vector3(tint.r, tint.g, tint.b))
	surface_material.set_shader_parameter("local_saturation", clampf(saturation, 0.8, 1.1))
	surface_material.set_shader_parameter("local_roughness_bias", clampf(roughness_bias, -0.03, 0.06))

func diagnostics() -> Dictionary:
	var arrays: Array = shell.mesh.surface_get_arrays(0) if shell != null and shell.mesh != null else []
	return {"kind": kind, "broken": broken, "renderOnly": true, "meshInstances": 1,
		"surfaces": shell.mesh.get_surface_count() if shell != null and shell.mesh != null else 0,
		"triangles": (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if not arrays.is_empty() else 0,
		"realShadowCasting": shell != null and shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"privateLocalMaterial": surface_material != ActorMaterials.material()}

static func build_mesh(kind_value: String, ruined: bool = false) -> ArrayMesh:
	var cache_key: String = kind_value + (":ruined" if ruined else ":standing")
	if mesh_cache.has(cache_key):
		return mesh_cache[cache_key]
	var tools: Dictionary = {}
	var matchlock: bool = kind_value == "enemy_gunner"
	# Bare timber, coarse bindings and a small crimson field banner remain
	# readable without a luminous canopy or a large building hiding the crew.
	for x in [-0.47, 0.47]:
		for z in [-0.32, 0.31]:
			var rotation_value: Vector3 = Vector3(0.11 if ruined else 0.0, 0.0, signf(x) * 0.16 if ruined else 0.0)
			_box(tools, "wood", Vector3(x, 0.31, z), Vector3(0.065, 0.62, 0.065), rotation_value)
	# Low planks leave the bow and matchlock action visible above the rest.
	for row in range(2):
		var y: float = 0.28 + row * 0.17
		for side in [-1, 1]:
			var center: Vector3 = Vector3(side * 0.265, y, -0.34)
			var rotation_value: Vector3 = Vector3.ZERO
			if ruined:
				center = Vector3(side * 0.29, 0.07 + row * 0.035, -0.20 + row * 0.11)
				rotation_value = Vector3(1.29, side * 0.12, side * 0.16)
			_box(tools, "wood", center, Vector3(0.41, 0.125, 0.035), rotation_value)
	_box(tools, "wood", Vector3(0.0, 0.61 if not ruined else 0.105, -0.32 if not ruined else -0.03),
		Vector3(1.03, 0.065, 0.070), Vector3(0.0, 0.0, 0.05 if ruined else 0.0))
	# Open sides and two diagonal braces identify a prepared firing position.
	for side in [-1, 1]:
		_box(tools, "wood", Vector3(side * 0.47, 0.36, 0.03), Vector3(0.04, 0.055, 0.63))
		_box(tools, "wood", Vector3(side * 0.47, 0.24, -0.01), Vector3(0.035, 0.51, 0.035), Vector3(0.56, 0.0, 0.0))
		for y in [0.28, 0.46]:
			_box(tools, "binding", Vector3(side * 0.47, y, -0.32), Vector3(0.078, 0.025, 0.079))
	# Gun crews have a visible thick shooting rest. Archer cover uses a woven
	# reed screen below the open bow gap; silhouettes differ, not only colour.
	if matchlock:
		_box(tools, "wood", Vector3(0.0, 0.56 if not ruined else 0.14, -0.31), Vector3(0.90, 0.045, 0.15))
		for side in [-1, 1]:
			_box(tools, "iron", Vector3(side * 0.32, 0.586 if not ruined else 0.167, -0.31), Vector3(0.026, 0.012, 0.16))
	else:
		for index in range(8):
			var x: float = -0.40 + index * 0.114
			_box(tools, "binding", Vector3(x, 0.15 if not ruined else 0.06, -0.348), Vector3(0.013, 0.19, 0.013), Vector3(1.30 if ruined else 0.0, 0.0, 0.0))
	# A short banner behind the soldier does not obscure the face or aim.
	var flag_origin: Vector3 = Vector3(0.39, 0.0, 0.31)
	var flag_basis: Basis = Basis.from_euler(Vector3(0.0, 0.0, -0.46 if ruined else 0.0))
	_box(tools, "wood", flag_origin + flag_basis * Vector3(0, 0.66, 0), Vector3(0.021, 1.32, 0.021), flag_basis.get_euler())
	_box(tools, "flag", flag_origin + flag_basis * Vector3(-0.11, 1.06, 0), Vector3(0.24, 0.36, 0.009), flag_basis.get_euler())
	for y in [0.96, 1.07, 1.18]:
		_box(tools, "mark", flag_origin + flag_basis * Vector3(-0.11, y, -0.006), Vector3(0.075, 0.018, 0.006), flag_basis.get_euler())
	var pieces: Array = []
	for material_name in tools:
		var tool: SurfaceTool = tools[material_name]
		tool.index()
		pieces.append({"bone": "root", "material": material_name, "mesh": tool.commit()})
	var combined: Array = ActorMaterials.batch_by_joint(pieces, _recipes())
	var result: ArrayMesh = combined[0].mesh
	mesh_cache[cache_key] = result
	return result

static func _recipes() -> Dictionary:
	var result: Dictionary = {}
	for entry in [
		["wood", Color("615039"), 0.0, 0.87, "brown_leather", 0.065],
		["binding", Color("93836a"), 0.0, 0.93, "denim_fabric", 0.045],
		["iron", Color("34383a"), 0.55, 0.73, "metal_plate_02", 0.065],
		["flag", Color("ae4242"), 0.0, 0.91, "denim_fabric", 0.05],
		["mark", Color("d2bd97"), 0.0, 0.91, "denim_fabric", 0.035]]:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = entry[1]
		material.metallic = entry[2]
		material.roughness = entry[3]
		material.set_meta("surface_recipe", {"colour": entry[1], "metallic": entry[2], "roughness": entry[3], "texture": entry[4], "normalScale": entry[5], "teamSurface": entry[0] == "flag"})
		result[entry[0]] = material
	return result

static func _box(tools: Dictionary, material_name: String, center: Vector3, dimensions: Vector3, rotation_value: Vector3 = Vector3.ZERO) -> void:
	if not tools.has(material_name):
		var new_tool: SurfaceTool = SurfaceTool.new()
		new_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[material_name] = new_tool
	var tool: SurfaceTool = tools[material_name]
	var half: Vector3 = dimensions * 0.5
	var basis: Basis = Basis.from_euler(rotation_value)
	for face in [
		[Vector3.RIGHT, Vector3(half.x,-half.y,-half.z), Vector3(half.x,-half.y,half.z), Vector3(half.x,half.y,half.z), Vector3(half.x,half.y,-half.z)],
		[Vector3.LEFT, Vector3(-half.x,-half.y,half.z), Vector3(-half.x,-half.y,-half.z), Vector3(-half.x,half.y,-half.z), Vector3(-half.x,half.y,half.z)],
		[Vector3.UP, Vector3(-half.x,half.y,-half.z), Vector3(half.x,half.y,-half.z), Vector3(half.x,half.y,half.z), Vector3(-half.x,half.y,half.z)],
		[Vector3.DOWN, Vector3(-half.x,-half.y,half.z), Vector3(half.x,-half.y,half.z), Vector3(half.x,-half.y,-half.z), Vector3(-half.x,-half.y,-half.z)],
		[Vector3.BACK, Vector3(half.x,-half.y,half.z), Vector3(-half.x,-half.y,half.z), Vector3(-half.x,half.y,half.z), Vector3(half.x,half.y,half.z)],
		[Vector3.FORWARD, Vector3(-half.x,-half.y,-half.z), Vector3(half.x,-half.y,-half.z), Vector3(half.x,half.y,-half.z), Vector3(-half.x,half.y,-half.z)]]:
		for index in [0, 2, 1, 0, 3, 2]:
			tool.set_normal(basis * face[0])
			tool.set_uv([Vector2.ZERO, Vector2(1,0), Vector2.ONE, Vector2(0,1)][index])
			tool.add_vertex(center + basis * face[index + 1])
