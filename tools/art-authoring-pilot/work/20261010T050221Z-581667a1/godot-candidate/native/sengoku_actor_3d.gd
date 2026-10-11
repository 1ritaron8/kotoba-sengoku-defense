extends Node3D

const HumanFace = preload("res://native/human_face_3d.gd")
const HumanBody = preload("res://native/human_body_geometry.gd")
const ActorMaterials = preload("res://native/actor_materials.gd")
const Armour = preload("res://native/sengoku_armor_geometry.gd")
const Equipment = preload("res://native/sengoku_equipment_geometry.gd")
const SkinnedRenderer = preload("res://native/sengoku_skinned_renderer.gd")

static var material_cache: Dictionary = {}
static var geometry_cache: Dictionary = {}
static var terrain_sole_supports: PackedVector3Array = PackedVector3Array()
var unit_type: String = "samurai"
var hostile: bool = false
var bones: Dictionary[String,Node3D] = {}
var surfaces: Dictionary = {}
var materials: Dictionary = {}
var meshes: Array = []
var rig: Node3D
var boat: Node3D
var phase_offset: float = 0.0
var current_state: Dictionary = {}
var mount: Node3D
var sailing_visual: bool = false
var hero_detail: bool = true
var evolution_stage: int = 0
var foot_contacts: Dictionary = {}
var standing_foot_contacts: Dictionary = {}
var last_motion_animation: String = "idle"
var _motion_debug: Dictionary = {}
var motion_debug: Dictionary:
	get:
		# World-space probe points are only consumed by diagnostics. Fetching
		# them for every soldier on every frame forces unused joint updates.
		if _motion_debug.has("leftStance"):
			_motion_debug.leftFoot = bones.footL.global_position
			_motion_debug.rightFoot = bones.footR.global_position
		return _motion_debug
	set(value):
		_motion_debug = value
var contact_vertices: Dictionary = {}
var terrain_hoof_supports: Dictionary = {}
var hoof_lifts: PackedFloat32Array = PackedFloat32Array([0.0,0.0,0.0,0.0])
var motion_transition: Dictionary = {}
var motion_transition_time: float = 0.0
var landing_transition: Dictionary = {}
var landing_transition_time: float = 0.0
var skinned_renderer: SkinnedRenderer
const SHOULDER_HALF_WIDTH: float = 0.195
const HUMAN_HEIGHT_RATIO: float = 0.94
const HUMAN_STANCE_HALF_WIDTH: float = 0.130

func configure(type_name: String, is_hostile: bool = false, seed_value: int = 1, detail_enabled: bool = true, evolution_value: int = 0) -> void:
	unit_type = type_name
	hostile = is_hostile
	hero_detail = detail_enabled
	evolution_stage = clampi(evolution_value,0,2)
	phase_offset = fmod(float(seed_value)*0.173,1.0)
	materials = _shared_materials(type_name,is_hostile,not hero_detail).duplicate()
	# One private material per soldier, with shared shader/textures. Local
	# terrain light must never overwrite another soldier's cached material.
	materials["combined"] = ActorMaterials.material().duplicate(false)
	ActorMaterials.configure_actor_material(materials["combined"],hostile,unit_type)
	_build_rig()
	var cache_key: String = _geometry_cache_identity()
	if geometry_cache.has(cache_key):
		for piece in geometry_cache[cache_key]:
			_attach_mesh(str(piece.bone),piece.mesh,materials[str(piece.material)])
	else:
		_build_geometry()
		var pieces: Array = []
		for surface_key in surfaces:
			var info: Dictionary = surfaces[surface_key]
			var tool: SurfaceTool = info.tool
			tool.generate_tangents()
			var mesh: ArrayMesh = tool.commit()
			pieces.append({"bone":info.bone,"material":info.material,"mesh":mesh})
		pieces = ActorMaterials.batch_by_joint(pieces,materials)
		for piece in pieces:
			_attach_mesh(str(piece.bone),piece.mesh,materials.combined)
		geometry_cache[cache_key] = pieces
		surfaces.clear()
	if not hero_detail:
		skinned_renderer = SkinnedRenderer.new()
		add_child(skinned_renderer)
		skinned_renderer.build(self,cache_key)
	apply_state({"animation":"idle","animationClock":0.0,"animationPhase":phase_offset,"aimX":0.0,"aimY":1.0})

func _geometry_cache_identity() -> String:
	# Barracks commanders override the identity; field soldiers keep their
	# existing geometry cache and can never borrow a named commander's face.
	return "%s-%s-%s-%d-v15" % [unit_type,hostile,hero_detail,evolution_stage]

func _bone(name_value: String, parent_name: String, origin: Vector3) -> Node3D:
	var joint: Node3D = Node3D.new()
	joint.name = name_value
	joint.position = origin
	if parent_name.is_empty():
		add_child(joint)
	else:
		bones[parent_name].add_child(joint)
	bones[name_value] = joint
	return joint

func _build_rig() -> void:
	rig = _bone("pelvis","",Vector3(0,0.92*HUMAN_HEIGHT_RATIO,0))
	_bone("torso","pelvis",Vector3(0,0.21*HUMAN_HEIGHT_RATIO,0))
	_bone("head","torso",Vector3(0,0.33*HUMAN_HEIGHT_RATIO,0))
	bones.head.scale = Vector3(0.90,0.94,0.90)
	for side in [-1,1]:
		var suffix: String = "L" if side < 0 else "R"
		_bone("arm"+suffix,"torso",Vector3(float(side)*shoulder_half_width(),0.20*HUMAN_HEIGHT_RATIO,0))
		_bone("fore"+suffix,"arm"+suffix,Vector3(0,-0.29*HUMAN_HEIGHT_RATIO,0))
		_bone("hand"+suffix,"fore"+suffix,Vector3(0,-0.265*HUMAN_HEIGHT_RATIO,0))
		_bone("thigh"+suffix,"pelvis",Vector3(float(side)*(.115 if unit_type=="archer" else .125),-0.025*HUMAN_HEIGHT_RATIO,0))
		_bone("shin"+suffix,"thigh"+suffix,Vector3(0,-0.42*HUMAN_HEIGHT_RATIO,0))
		_bone("foot"+suffix,"shin"+suffix,Vector3(0,-0.425*HUMAN_HEIGHT_RATIO,0))
	_bone("weapon","handL" if unit_type == "archer" else "handR",Vector3(0,-0.035,-0.025))
	if unit_type == "archer":
		# These small attachments share the existing skinned palette/batches.
		# Their pose can change without rebuilding geometry or creating a shot.
		_bone("bowStringLower","weapon",Vector3.ZERO)
		_bone("bowStringUpper","weapon",Vector3.ZERO)
		_bone("nockedArrow","weapon",Vector3.ZERO)
	boat = _bone("boat","",Vector3.ZERO)
	boat.visible = false
	for side in [-1,1]:
		_bone("oarL" if side < 0 else "oarR","boat",Vector3(float(side)*0.18,0.16,0.18))
	if unit_type == "commander":
		mount = _bone("mount","",Vector3.ZERO)
		_bone("horse_neck","mount",Vector3(0,1.07,-0.37))
		_bone("horse_head","horse_neck",Vector3(0,0.29,-0.24))
		_bone("horse_tail","mount",Vector3(0,1.06,0.48))
		for leg in range(4):
			var front: bool = leg < 2
			var side: float = -1.0 if leg%2 == 0 else 1.0
			_bone("horse_leg%d" % leg,"mount",Vector3(side*0.19,0.83,-0.31 if front else 0.33))
			_bone("horse_calf%d" % leg,"horse_leg%d" % leg,Vector3(0,-0.37,0))

func shoulder_half_width() -> float:
	return .178 if unit_type=="archer" else SHOULDER_HALF_WIDTH

func set_local_light(exposure: float, tint: Color, saturation: float = 1.0, roughness_bias: float = 0.0) -> void:
	if hero_detail:
		return
	var material: ShaderMaterial = materials.combined
	material.set_shader_parameter("local_exposure",clampf(exposure,.55,1.45))
	material.set_shader_parameter("local_tint",Vector3(tint.r,tint.g,tint.b))
	material.set_shader_parameter("local_saturation",clampf(saturation,.8,1.1))
	material.set_shader_parameter("local_roughness_bias",clampf(roughness_bias,-.03,.06))

func _shared_materials(type_name: String, enemy: bool, battle_view: bool = false) -> Dictionary:
	var key: String = "%s-%s-%s" % [type_name,enemy,battle_view]
	if material_cache.has(key):
		return material_cache[key]
	# Original warrior designs use Sengoku commanders as visual references:
	# restrained archer, vermilion Sanada infantry, black Oda armour,
	# blue-grey Akechi matchlocks, Ii red guards, and Takeda cavalry.
	var lacquer_color: Color = Color("23303c")
	var fabric_color: Color = Color("494c3d")
	if type_name == "spear":
		lacquer_color = Color("742d26")
		fabric_color = Color("554238")
	elif type_name == "samurai":
		lacquer_color = Color("242827")
		fabric_color = Color("593b36")
	elif type_name == "commander":
		lacquer_color = Color("78332c")
		fabric_color = Color("63503c")
	elif type_name == "gunner":
		lacquer_color = Color("35424b")
		fabric_color = Color("686962")
	elif type_name == "naginata":
		lacquer_color = Color("81382f")
		fabric_color = Color("4e3d33")
	elif type_name == "monk":
		lacquer_color = Color("454239")
		fabric_color = Color("b0ab92")
	elif type_name == "ninja":
		lacquer_color = Color("242c2b")
		fabric_color = Color("303a3c")
	elif enemy:
		lacquer_color = Color("4a2722")
		fabric_color = Color("594740")
	var result: Dictionary = {
		"lacquer":_pbr(lacquer_color,0.16,0.66,"metal_plate_02",0.11),
		"metal":_pbr(Color("717878"),0.90,0.48,"metal_plate_02",0.18),
		"gold":_pbr(Color("b59755"),0.82,0.37,"metal_plate_02",0.15),
		"cloth":_pbr(fabric_color,0.0,0.86,"denim_fabric",0.10),
		"leather":_pbr(Color("302a20"),0.0,0.66,"brown_leather",0.24),
		"cord":_pbr(Color("60523f"),0.0,0.86,"denim_fabric",0.10),
		"skin":_pbr(Color("b18a70"),0.0,0.84,"",0.0),
		"skin_shadow":_pbr(Color("815f4c"),0.0,0.86,"",0.0),
		"eye_white":_pbr(Color("c4b9a4"),0.0,0.56,"",0.0),
		"eye":_pbr(Color("211813"),0.0,0.46,"",0.0),
		"hair":_pbr(Color("1c1b19"),0.0,0.84,"denim_fabric",0.06),
		"wood":_pbr(Color("55402b"),0.0,0.82,"brown_leather",0.15),
		"coat":_pbr(Color("543c2d"),0.0,0.90,"brown_leather",0.035),
	}
	for face_key in HumanFace.material_recipe():
		var recipe: Dictionary = HumanFace.material_recipe()[face_key]
		var face_material: StandardMaterial3D = _pbr(recipe.albedo,float(recipe.metallic),float(recipe.roughness),"",0.0)
		face_material.vertex_color_use_as_albedo = true
		result[face_key] = face_material
	if battle_view:
		# Lacquered iron is a dark material, not dyed plastic. Team colour lives
		# on the cloth shoulders, odoshi, waist binding and existing banners.
		var iron_color: Color = Color("30292a") if enemy else Color("292e30")
		if not enemy and type_name in ["archer","gunner"]:
			iron_color = Color("343b3d")
		elif not enemy and type_name in ["spear","naginata","commander"]:
			iron_color = Color("342d2b")
		result["battle_lacquer"] = _pbr(iron_color,0.22,0.62,"metal_plate_02",0.095)
		result["faction_cloth"] = _pbr(Color("7e4b46") if enemy else Color("4a687d"),0.0,0.91,"denim_fabric",0.075)
		result["faction_cord"] = _pbr(Color("bb3f42") if enemy else Color("448ec6"),0.0,0.88,"denim_fabric",0.07)
		result["faction_binding"] = _pbr(Color("a83c3c") if enemy else Color("4387b8"),0.0,0.90,"denim_fabric",0.075)
		for team_key in ["faction_cloth","faction_cord","faction_binding"]:
			var team_recipe: Dictionary = result[team_key].get_meta("surface_recipe")
			team_recipe["teamSurface"] = true
			result[team_key].set_meta("surface_recipe",team_recipe)
	material_cache[key] = result
	return result

func _pbr(color: Color, metallic_value: float, roughness_value: float, map_name: String, normal_strength: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic_value
	material.roughness = roughness_value
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.set_meta("surface_recipe",{"colour":color,"metallic":metallic_value,"roughness":roughness_value,"texture":map_name,"normalScale":normal_strength})
	if not map_name.is_empty():
		var normal_path: String = "res://assets/materials/%s/nor_gl.jpg" % map_name
		var rough_path: String = "res://assets/materials/%s/rough.jpg" % map_name
		if ResourceLoader.exists(normal_path):
			material.normal_enabled = true
			material.normal_texture = load(normal_path)
			material.normal_scale = normal_strength
		if ResourceLoader.exists(rough_path):
			material.roughness_texture = load(rough_path)
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return material

func _attach_mesh(bone_name: String, mesh: ArrayMesh, material: Material) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = 3
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	bones[bone_name].add_child(instance)
	meshes.append(instance)

func _faction_material_name(bone_name: String, material_name: String) -> String:
	if hero_detail:
		return material_name
	if material_name == "lacquer":
		return "battle_lacquer"
	if material_name == "cloth" and bone_name in ["torso","pelvis","armL","armR","foreL","foreR"]:
		return "faction_cloth"
	if material_name == "cord" and bone_name != "head":
		return "faction_cord"
	return material_name

func _append(bone_name: String, material_name: String, mesh: Mesh, origin: Vector3 = Vector3.ZERO, rotation_value: Vector3 = Vector3.ZERO, scale_value: Vector3 = Vector3.ONE) -> void:
	material_name = _faction_material_name(bone_name,material_name)
	var key: String = bone_name+"/"+material_name
	if not surfaces.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[key] = {"tool":tool,"bone":bone_name,"material":material_name}
	var builder: SurfaceTool = surfaces[key].tool
	var transform: Transform3D = Transform3D(Basis.from_euler(rotation_value).scaled(scale_value),origin)
	if bone_name in ["pelvis","torso","armL","armR","foreL","foreR","thighL","thighR","shinL","shinR"]:
		# Shorten only joint-local human segments: shoes, face, weapons, mount
		# and hull keep their actual dimensions. This is not a world-scale squash.
		transform = Transform3D(Basis.from_scale(Vector3(1,HUMAN_HEIGHT_RATIO,1)),Vector3.ZERO)*transform
		if unit_type=="archer" and bone_name in ["pelvis","torso"]:
			transform = Transform3D(Basis.from_scale(Vector3(.90,1,.88)),Vector3.ZERO)*transform
	builder.append_from(mesh,0,transform)

func _sphere(radius_value: float, height_value: float) -> SphereMesh:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius_value
	mesh.height = height_value
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh

func _cylinder(radius_bottom: float, radius_top: float, length_value: float, segments: int = 12) -> CylinderMesh:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.bottom_radius = radius_bottom
	mesh.top_radius = radius_top
	mesh.height = length_value
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh

func _rod(bone_name: String, material_name: String, start: Vector3, end: Vector3, radius_value: float) -> void:
	material_name = _faction_material_name(bone_name,material_name)
	var delta: Vector3 = end-start
	if delta.length() < 0.0001:
		return
	var orientation: Basis = Basis(Quaternion(Vector3.UP,delta.normalized()))
	var mesh: CylinderMesh = _cylinder(radius_value,radius_value,delta.length(),6)
	var key: String = bone_name+"/"+material_name
	if not surfaces.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[key] = {"tool":tool,"bone":bone_name,"material":material_name}
	var builder: SurfaceTool = surfaces[key].tool
	builder.append_from(mesh,0,Transform3D(orientation,(start+end)*0.5))

func _lathe(profile: Array, depth_ratio: float, segments: int, start_angle: float = 0.0, arc: float = TAU) -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size()-1):
		var lower: Vector2 = profile[row]
		var upper: Vector2 = profile[row+1]
		for segment in range(segments):
			var a0: float = start_angle+arc*float(segment)/segments
			var a1: float = start_angle+arc*float(segment+1)/segments
			var corners: Array = [Vector3(cos(a0)*lower.x,lower.y,sin(a0)*lower.x*depth_ratio),Vector3(cos(a1)*lower.x,lower.y,sin(a1)*lower.x*depth_ratio),Vector3(cos(a1)*upper.x,upper.y,sin(a1)*upper.x*depth_ratio),Vector3(cos(a0)*upper.x,upper.y,sin(a0)*upper.x*depth_ratio)]
			var slope: float = (upper.x-lower.x)/maxf(0.00001,upper.y-lower.y)
			for index in [0,2,1,0,3,2]:
				var angle: float = a1 if index in [1,2] else a0
				tool.set_normal(Vector3(cos(angle),-slope,sin(angle)/maxf(0.01,depth_ratio)).normalized())
				tool.set_uv(Vector2(float(segment+(1 if index in [1,2] else 0))/segments,float(row+(1 if index in [2,3] else 0))/maxi(1,profile.size()-1)))
				tool.add_vertex(corners[index])
	# append_from must receive indexed meshes consistently. An indexed primitive
	# combined with unindexed shell vertices otherwise leaves the shells undrawn.
	tool.index()
	return tool.commit()

func _build_geometry() -> void:
	# The armour wraps curved adult proportions; each rigid joint is batched by material.
	var lightly_armoured: bool = unit_type in ["archer","gunner","monk","ninja","enemy_light"] and evolution_stage < 2
	for piece in Armour.build(lightly_armoured,hero_detail):
		_append(str(piece.bone),str(piece.material),piece.mesh)
	# Tailored cloth, anatomical limbs and shaped footwear share the old IK
	# joint spaces; equipment owns armour on those limbs without duplicate shells.
	for piece in HumanBody.build(unit_type,hero_detail):
		_append(str(piece.bone),str(piece.material),piece.mesh)
	_append("pelvis","leather",_lathe([Vector2(0.183,-0.01),Vector2(0.183,0.062)],0.59,16))
	if not hero_detail:
		# One woven army binding occupies the existing belt joint/batch, with
		# no broad blue/red coating on the steel or changed body silhouette.
		_append("pelvis","faction_binding",_lathe([Vector2(.186,.002),Vector2(.186,.044)],.59,16))
	_append("pelvis","gold",_sphere(0.027,0.050),Vector3(0,0.025,-0.113),Vector3.ZERO,Vector3(1,1,0.3))
	_build_face()
	for piece in Equipment.build(unit_type,evolution_stage,hero_detail):
		_append(str(piece.bone),str(piece.material),piece.mesh)
	if unit_type == "archer":
		for key in ["bowStringLower","bowStringUpper"]:
			_rod(key,"cord",Vector3(0,-.5,0),Vector3(0,.5,0),.0016)
		_rod("nockedArrow","wood",Vector3.ZERO,Vector3(0,0,-.66),.004)
		_append("nockedArrow","metal",_cylinder(.012,0,.06,6),Vector3(0,0,-.69),Vector3(-PI/2,0,0))
		var feather: BoxMesh = BoxMesh.new()
		feather.size = Vector3(.025,.003,.050)
		_append("nockedArrow","cloth",feather,Vector3(0,0,-.04))
		_append("nockedArrow","cloth",feather,Vector3(0,0,-.04),Vector3(0,0,PI/2))
	_build_boat()
	if unit_type == "commander":
		_build_mount()

func _build_mount() -> void:
	# The existing horse rig receives continuous anatomical volumes; tack and
	# articulation remain the same, with no intersecting sphere muzzle/chest.
	for piece in HumanBody.build_horse(hero_detail):
		_append(str(piece.bone),str(piece.material),piece.mesh)
	for side in [-1,1]:
		_append("horse_head","iris",_sphere(0.015,0.018),Vector3(float(side)*0.092,0.060,-0.063),Vector3.ZERO,Vector3(0.26,1,1))
		_rod("horse_head","leather",Vector3(float(side)*0.108,0.100,0.009),Vector3(float(side)*0.080,-0.127,-0.186),0.009)
		_rod("mount","cord",Vector3(float(side)*0.095,1.24,-0.83),Vector3(float(side)*0.235,1.40,-0.02),0.005)
	_append("horse_head","leather",_lathe([Vector2(0.102,-0.012),Vector2(0.103,0.009)],1.0,12),Vector3(0,-0.09,-0.14),Vector3(PI/2,0,0),Vector3(1,1,0.72))
	_append("mount","cloth",_sphere(0.265,0.065),Vector3(0,1.178,0.065),Vector3.ZERO,Vector3(1,1,1.10))
	_append("mount","leather",_sphere(0.202,0.069),Vector3(0,1.213,0.043),Vector3.ZERO,Vector3(1,1,1.28))

func _build_face() -> void:
	for piece in HumanFace.build(hero_detail):
		_append("head",str(piece.material),piece.mesh)
	if unit_type == "archer" and evolution_stage < 2:
		_append("head","cloth",_lathe([Vector2(0.100,0.074),Vector2(0.100,0.091)],0.85,24))
		# A folded chonmage follows the shaved crown; it is not a ball above it.
		var knot: Array[Vector3] = [Vector3(0,.133,.062),Vector3(0,.170,.046),Vector3(0,.178,.010),Vector3(0,.177,-.036),Vector3(0,.168,-.058)]
		for index in range(knot.size()-1):
			_rod("head","hair",knot[index],knot[index+1],.013 if index==0 else .016)
		_rod("head","cord",Vector3(-.014,.174,-.008),Vector3(.014,.174,-.008),.002)

func _build_boat() -> void:
	var hull: ArrayMesh = _lathe([Vector2(0.18,0.02),Vector2(0.29,0.10),Vector2(0.31,0.18)],2.05,12)
	_append("boat","wood",hull)
	_append("boat","wood",_cylinder(0.24,0.24,0.03,12),Vector3(0,0.10,0),Vector3.ZERO,Vector3(1,1,2.25))
	for side in [-1,1]:
		var oar_name: String = "oarL" if side < 0 else "oarR"
		_rod(oar_name,"wood",Vector3.ZERO,Vector3(float(side)*0.32,-0.06,0.30),0.009)
		_append(oar_name,"wood",_sphere(0.032,0.12),Vector3(float(side)*0.32,-0.07,0.31),Vector3(0.3,0,float(side)*0.9),Vector3(1,0.8,2.0))

func apply_state(data: Dictionary) -> void:
	var previous_animation: String=str(current_state.get("animation","idle"))
	current_state = data
	if rig == null:
		return
	var animation: String = str(data.get("animation","idle"))
	var sailing: bool = bool(data.get("sailing",false))
	if sailing or bool(data.get("motionReset",false)) or animation=="death":
		landing_transition.clear()
	elif sailing_visual and previous_animation!="death" and data.has("motionTime"):
		landing_transition.clear()
		landing_transition_time=float(data.motionTime)
		for key in bones: landing_transition[key]=bones[key].transform
	# The support monk no longer swings a staff as a normal damage attack.
	# A real healing state alone opens the offering gesture; idle/guard never
	# invents a heal, and a casualty always retains its existing fall pose.
	if unit_type == "monk" and animation not in ["death", "walk"] and not sailing:
		if bool(data.get("healing", false)) or animation == "heal":
			animation = "heal"
		elif animation == "attack":
			animation = "idle"
	# Sailing is only a visual stance; logical enemy movement remains unchanged.
	if sailing and animation != "death":
		animation = "idle"
	if bool(data.get("motionReset",false)) or sailing or animation=="death":
		motion_transition.clear()
	elif bool(data.get("groundMotion",false)) and data.has("motionTime") and animation!=last_motion_animation and (animation=="walk" or last_motion_animation=="walk"):
		motion_transition = {"bones":{},"feet":{}}
		motion_transition_time = float(data.motionTime)
		for key in bones:
			motion_transition.bones[key] = bones[key].transform
		for key in (["horse_calf0","horse_calf1","horse_calf2","horse_calf3"] if unit_type=="commander" else ["footL","footR"]):
			var foot: Node3D = bones[key]
			motion_transition.feet[key] = {"point":foot.global_transform*Vector3(0,-.376,0) if unit_type=="commander" else foot.global_position,"basis":foot.global_basis,"minimum":_contact_minimum(key)}
	if bool(data.get("motionReset",false)) or animation in ["walk","death"] or sailing:
		standing_foot_contacts.clear()
	elif animation!=last_motion_animation and last_motion_animation=="walk" and unit_type!="commander":
		for suffix in ["L","R"]:
			standing_foot_contacts[suffix] = {"point":bones["foot"+suffix].global_position,"yaw":rotation.y}
	var clock: float = maxf(0.0,float(data.get("animationClock",0.0)))
	var phase: float = float(data.get("animationPhase",phase_offset))
	var idle: float = sin((clock+phase)*TAU*0.34)
	var full_body_walk: bool = animation=="walk" and not sailing
	if not full_body_walk:
		rig.position = Vector3(0,0.92*HUMAN_HEIGHT_RATIO,0)
		rig.rotation = Vector3.ZERO
		bones.torso.rotation = Vector3(0.008*idle,0.008*idle,0)
		bones.head.rotation = Vector3(0.025,0.010*idle,0)
	var torso_height: float = .21*HUMAN_HEIGHT_RATIO+(.0015*idle if animation=="idle" else 0.0)
	if bones.torso.position.y!=torso_height:
		bones.torso.position.y = torso_height
	for side in [-1,1]:
		var suffix: String = "L" if side < 0 else "R"
		var stride: float = 0.0
		# Full-body IK supplies these joints once. The former primitive walk
		# was immediately overwritten, causing extra transform propagation.
		if animation=="death":
			bones["thigh"+suffix].rotation = Vector3(stride*0.35,0,float(side)*0.015)
			bones["shin"+suffix].rotation = Vector3(maxf(0.0,-stride)*0.42,0,0)
			bones["foot"+suffix].rotation = Vector3(-maxf(0.0,-stride)*0.2,0,0)
		if animation!="walk" or sailing:
			bones["arm"+suffix].rotation = Vector3(-stride*0.15,0,float(side)*0.10)
			bones["fore"+suffix].rotation = Vector3(0.18,0,0)
		bones["hand"+suffix].rotation = Vector3.ZERO
	bones.weapon.rotation = Vector3(-0.08,0,-0.08)
	if unit_type=="ninja":
		bones.handL.rotation.x = -1.30-bones.armL.rotation.x-bones.foreL.rotation.x
	if unit_type == "archer" and (animation!="walk" or sailing):
		bones.armL.rotation = Vector3(0.25,0,-0.10)
		bones.foreL.rotation = Vector3(0.42,0,0)
		bones.armR.rotation = Vector3(0.25,0,0.12)
		bones.foreR.rotation = Vector3(0.65,0,0)
		bones.weapon.rotation.x = -0.67
	if animation == "attack":
		_pose_attack(data,clock)
	if animation == "death":
		var fall: float = smoothstep(0.0,0.6667,clock)
		rig.position.y = lerpf(0.92,0.23,fall)
		rig.rotation = Vector3(lerpf(0.0,1.46,fall),0,0.10*fall)
		bones.armL.rotation.z = -0.46*fall
		bones.armR.rotation.z = 0.58*fall
		bones.shinL.rotation.x = 0.34*fall
		bones.shinR.rotation.x = 0.20*fall
	if unit_type == "commander":
		if animation=="death":
			rig.position.y += .58
			for leg in range(4):
				bones["horse_leg%d"%leg].rotation.x = 0
				bones["horse_calf%d"%leg].rotation.x = 0
			bones.horse_neck.rotation.x = idle*.015
			bones.horse_head.rotation.x = idle*.018
			bones.horse_tail.rotation = Vector3(.05,0,idle*.075)
	var aiming: Vector2 = Vector2(float(data.get("aimX",0.0)),float(data.get("aimY",1.0)))
	if data.has("visualYaw"):
		rotation.y = wrapf(float(data.visualYaw),-PI,PI)
	elif aiming.length_squared() > 0.0001:
		rotation.y = atan2(-aiming.x,-aiming.y)
	boat.visible = sailing
	if boat.position!=Vector3.ZERO: boat.position = Vector3.ZERO
	if boat.rotation!=Vector3.ZERO: boat.rotation = Vector3.ZERO
	bones.weapon.visible = not sailing
	if mount != null:
		mount.visible = not sailing
	if sailing_visual != sailing:
		sailing_visual = sailing
		for instance in meshes:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if sailing else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if sailing:
		rig.position.y += 0.14
		boat.rotation.z = sin((clock+phase)*2.0)*0.02
		bones.oarL.rotation = Vector3(0,sin((clock+phase)*3.0)*0.32,-0.08)
		bones.oarR.rotation = Vector3(0,-sin((clock+phase)*3.0)*0.32,0.08)
	_animate_full_body(data,animation,clock,phase,sailing)
	_pose_hit(data,animation)
	if unit_type == "gunner" and not sailing and animation != "death":
		_pose_matchlock(data,animation,clock)
	elif unit_type in ["spear","samurai","naginata","monk","enemy_light"] and not sailing and animation != "death":
		_pose_braced_weapon(data,clock if animation=="attack" else 0.0)
	_blend_motion_pose(data)
	if not motion_transition.is_empty():
		if unit_type=="gunner":
			_pose_matchlock(data,animation,clock)
		elif unit_type in ["spear","samurai","naginata","monk","enemy_light"]:
			_pose_braced_weapon(data,clock if animation=="attack" else 0.0)
	if unit_type == "monk" and animation not in ["death", "walk"] and not sailing:
		_pose_support(data, animation, clock)
	_blend_landing_pose(data)
	_settle_feet_on_terrain(data)
	if unit_type == "archer":
		_pose_bow_motion(data,animation,clock,sailing)
	if skinned_renderer!=null:
			skinned_renderer.sync_pose(self)

func _settle_feet_on_terrain(data: Dictionary) -> void:
	var sampler: Callable=data.get("groundHeightSampler",Callable())
	if not sampler.is_valid() or bool(data.get("sailing",false)) or str(data.get("animation",""))=="death": return
	if unit_type=="commander":
		_settle_hooves_on_terrain(sampler)
		return
	# The original shoe is built from these eight authored sole sections.
	# Their left/right underside supports cover its heel, ball and toe without
	# sampling every upper-shoe/cord vertex. The edge lower bound is at most
	# 3mm below the rounded sole; unlike an AABB it follows the real outline.
	if terrain_sole_supports.is_empty():
		for section in HumanBody.FOOT_PROFILE:
			terrain_sole_supports.append(Vector3(-section.y,section.z,section.x))
			terrain_sole_supports.append(Vector3(section.y,section.z,section.x))
	# Keep gait, pitch and planted X/Z. If a stopped guard pose raises the
	# hips beyond a planted ankle's reach, lower only the local pelvis enough
	# for the existing leg IK; the logical route root never moves.
	var placements: Array[Dictionary] = []
	var pelvis_drop: float = 0.0
	var inverse: Transform3D = global_transform.affine_inverse()
	for suffix in ["L","R"]:
		var key: String="foot"+suffix
		var foot: Node3D=bones[key]
		var planted: bool = str(data.get("animation","idle"))!="walk" or bool(_motion_debug.get("leftStance" if suffix=="L" else "rightStance",true))
		var lift: float = _terrain_shoe_lift(foot,sampler,planted)
		if not is_finite(lift): lift=0.0
		var target: Vector3 = inverse*(foot.global_position+Vector3.UP*(lift+.0005 if absf(lift)>.0005 else 0.0))
		var rotation_value: Vector3 = (global_basis.inverse()*foot.global_basis).get_euler()
		placements.append({"suffix":suffix,"foot":foot,"target":target,"rotation":rotation_value,"planted":planted,"lift":lift})
		if planted:
			var hip: Vector3 = inverse*bones["thigh"+suffix].global_position
			var delta: Vector3 = hip-target
			var reach: float = bones["shin"+suffix].position.length()+foot.position.length()-.001
			var vertical_reach: float = sqrt(maxf(.001,reach*reach-delta.x*delta.x-delta.z*delta.z))
			pelvis_drop = maxf(pelvis_drop,delta.y-vertical_reach+.001)
	if pelvis_drop>.0005:
		rig.position.y -= minf(.18,pelvis_drop)
	for placement in placements:
		var foot: Node3D = placement.foot
		var rotation_value: Vector3 = placement.rotation
		if pelvis_drop>.0005 or absf(float(placement.lift))>.0005:
			_solve_leg(str(placement.suffix),placement.target,rotation_value.x,rotation_value.y)
		for attempt in range(3):
			var lift: float = _terrain_shoe_lift(foot,sampler,bool(placement.planted))
			if not is_finite(lift) or absf(lift)<=.0005: break
			var target: Vector3 = inverse*(foot.global_position+Vector3.UP*(lift+.0005))
			_solve_leg(str(placement.suffix),target,rotation_value.x,rotation_value.y)

func _terrain_shoe_lift(foot: Node3D, sampler: Callable, planted: bool) -> float:
	# A stationary/planted foot also lowers onto the downhill side;
	# a swinging foot keeps its authored clearance unless it penetrates.
	var lift: float = -INF if planted else 0.0
	for vertex in terrain_sole_supports:
		var point: Vector3 = foot.global_transform*vertex
		var ground: float = float(sampler.call(point))
		if is_finite(ground): lift=maxf(lift,ground-point.y)
	return lift

func _settle_hooves_on_terrain(sampler: Callable) -> void:
	var actor_scale: float = maxf(.0001,global_basis.get_scale().y)
	for leg in range(4):
		var key: String = "horse_calf%d" % leg
		var calf: Node3D = bones[key]
		if not terrain_hoof_supports.has(key):
			_contact_minimum(key)
			var supports: PackedVector3Array = PackedVector3Array()
			for vertex in contact_vertices[key]:
				if vertex.y<=-.401:
					supports.append(vertex)
			terrain_hoof_supports[key] = supports
		# Preserve the existing trot/gallop's actual hoof lift, then put its
		# real underside over the terrain at the unchanged route/root position.
		var clearance: float = (.005+hoof_lifts[leg])*actor_scale
		for attempt in range(4):
			var correction: float = -INF
			for vertex in terrain_hoof_supports[key]:
				var point: Vector3 = calf.global_transform*vertex
				var ground: float = float(sampler.call(point))
				if is_finite(ground):
					correction = maxf(correction,ground+clearance-point.y)
			if not is_finite(correction) or absf(correction)<=.0005:
				break
			var endpoint: Vector3 = calf.global_transform*Vector3(0,-.376,0)
			var target: Vector3 = global_transform.affine_inverse()*(endpoint+Vector3.UP*correction)
			var floor_height: float = _contact_minimum(key)+correction/actor_scale
			_solve_horse_leg(leg,target,floor_height)

func _blend_landing_pose(data: Dictionary) -> void:
	if landing_transition.is_empty(): return
	var progress: float=clampf((float(data.get("motionTime",landing_transition_time))-landing_transition_time)/.35,0.0,1.0)
	var amount: float=smoothstep(0.0,1.0,progress)
	if progress>=1.0:
		landing_transition.clear()
		return
	for key in landing_transition:
		bones[key].transform=(landing_transition[key] as Transform3D).interpolate_with(bones[key].transform,amount)
	# The hull is already hidden on land; only the crew rises and plants feet.
	bones.weapon.visible=progress>=.45
	_motion_debug["landingProgress"]=progress
	_motion_debug["mode"]="landing"

func _contact_minimum(key: String) -> float:
	var bone: Node3D = bones[key]
	if not contact_vertices.has(key):
		var points: PackedVector3Array = PackedVector3Array()
		var unique: Dictionary = {}
		for instance in meshes:
			if instance.get_parent()!=bone:
				continue
			for surface_index in range(instance.mesh.get_surface_count()):
				var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					var local: Vector3 = instance.transform*vertex
					if (not key.begins_with("horse") or local.y<=-.352) and not unique.has(local):
						points.append(local)
						unique[local] = true
		contact_vertices[key] = points
	var relative: Transform3D = global_transform.affine_inverse()*bone.global_transform
	var vertical: Vector3 = Vector3(relative.basis.x.y,relative.basis.y.y,relative.basis.z.y)
	var lowest: float = INF
	var points: PackedVector3Array = contact_vertices[key]
	for point in points:
		lowest = minf(lowest,vertical.dot(point))
	return lowest+relative.origin.y

func _blend_motion_pose(data: Dictionary) -> void:
	if motion_transition.is_empty():
		return
	var duration: float = .18
	if str(data.get("animation",""))=="attack":
		duration = minf(.14,float(data.get("attackDuration",.5))*float(_attack_phases(data,0).impact)*.5)
	var amount: float = smoothstep(0,duration,float(data.get("motionTime",motion_transition_time))-motion_transition_time)
	if amount>=1.0:
		motion_transition.clear()
		return
	var destinations: Dictionary = {}
	for key in motion_transition.feet:
		var foot: Node3D = bones[key]
		var previous: Dictionary = motion_transition.feet[key]
		var endpoint: Vector3 = foot.global_transform*Vector3(0,-.376,0) if unit_type=="commander" else foot.global_position
		var previous_basis: Basis = previous.basis
		var orientation: Basis = previous_basis.orthonormalized().slerp(foot.global_basis.orthonormalized(),amount)
		orientation = orientation.scaled(previous_basis.get_scale().lerp(foot.global_basis.get_scale(),amount))
		destinations[key] = {"point":(previous.point as Vector3).lerp(endpoint,amount),"basis":orientation,"minimum":lerpf(float(previous.minimum),_contact_minimum(key),amount)}
	for key in motion_transition.bones:
		bones[key].transform = (motion_transition.bones[key] as Transform3D).interpolate_with(bones[key].transform,amount)
	for key in destinations:
		var foot: Dictionary = destinations[key]
		var local: Vector3 = global_transform.affine_inverse()*(foot.point as Vector3)
		if unit_type=="commander":
			_solve_horse_leg(int(str(key).right(1)),local,float(foot.minimum))
		else:
			var suffix: String = str(key).right(1)
			_solve_leg(suffix,local,0)
			bones[key].global_basis = foot.basis
			var adjustment: float = float(foot.minimum)-_contact_minimum(key)
			if absf(adjustment)>.0005:
				local.y += adjustment
				_solve_leg(suffix,local,0)
				bones[key].global_basis = foot.basis

func _attack_phases(data: Dictionary, clock: float) -> Dictionary:
	# Live states carry the actual gameplay release timestamp. Catalogue and
	# older QA states retain their established normalized frame as a fallback.
	var duration: float = maxf(.05,float(data.get("attackDuration",.5)))
	var t: float = clampf(clock/duration,0,1)
	var fallback: float = 2.0/3.0 if unit_type in ["archer","samurai"] else .5
	var impact: float = clampf(float(data.get("releaseTime",duration*fallback))/duration,.001,.999)
	var cancelled: bool = bool(data.get("attackCancelled",false)) and not bool(data.get("attackReleased",false))
	return {"time":t,"impact":impact,"preparation":smoothstep(0,impact*.55,t),"drive":0.0 if cancelled else smoothstep(impact*.55,impact,t),"recovery":smoothstep(impact if cancelled else minf(.999,impact+.04),1,t)}

func _attack_released(data: Dictionary, clock: float) -> bool:
	if bool(data.get("attackCancelled",false)) and not bool(data.get("attackReleased",false)):
		return false
	if data.has("attackReleased"):
		return bool(data.attackReleased)
	var duration: float = maxf(.05,float(data.get("attackDuration",.5)))
	return clock >= duration*float(_attack_phases(data,clock).impact)

func _pose_hit(data: Dictionary, animation: String) -> void:
	if animation == "death":
		return
	var remaining: float = clampf(float(data.get("hitClock",0.0))/.12,0.0,1.0)
	var reaction: float = sin(remaining*PI)
	if reaction <= .00001:
		return
	# An upper-body flinch only: no translation, stopped gait, stun, or knockback.
	bones.torso.rotation.z += reaction*.095
	bones.head.rotation.x += reaction*.070
	bones.head.rotation.z -= reaction*.035
	_motion_debug["hitReaction"] = reaction

func _pose_bow_motion(data: Dictionary, animation: String, clock: float, sailing: bool) -> void:
	var phase: Dictionary = _attack_phases(data,clock)
	var attacking: bool = animation == "attack" and not sailing
	var released: bool = attacking and _attack_released(data,clock)
	var loaded: float = float(phase.preparation)*(1.0-float(phase.recovery)) if attacking else 0.0
	var drawn_nock: Vector3 = Vector3(0,.015,.18*loaded)
	var string_nock: Vector3 = drawn_nock
	if attacking:
		# The pulling hand follows the actual string while loading, then keeps
		# its draw position as the released string snaps independently.
		bones.weapon.global_basis = bones.weapon.global_basis.orthonormalized().slerp(global_basis.orthonormalized(),loaded)
		var arm_rotation: Vector3 = bones.armR.rotation
		var fore_rotation: Vector3 = bones.foreR.rotation
		var hand_rotation: Vector3 = bones.handR.rotation
		_solve_arm("R",bones.weapon.global_transform*drawn_nock,global_basis*Basis.from_euler(Vector3(PI/2,0,0)))
		bones.armR.rotation = arm_rotation.lerp(bones.armR.rotation,loaded)
		bones.foreR.rotation = fore_rotation.lerp(bones.foreR.rotation,loaded)
		bones.handR.rotation = hand_rotation.lerp(bones.handR.rotation,loaded)
		if released:
			var release_seconds: float = float(phase.impact)*maxf(.05,float(data.get("attackDuration",.5)))
			var since_release: float = maxf(0.0,clock-release_seconds)
			string_nock.z = sin(since_release*190.0)*.013*(1.0-smoothstep(0,.06,since_release))
	var length: float = 1.14+float(evolution_stage)*.09
	var bow_shown: bool = bones.weapon.visible and not sailing
	_set_bow_string("bowStringLower",Vector3(0,-length*.44,0),string_nock,bow_shown)
	_set_bow_string("bowStringUpper",string_nock,Vector3(0,length*.56,0),bow_shown)
	bones.nockedArrow.position = drawn_nock
	var nocked: bool = attacking and not released and bow_shown
	bones.nockedArrow.visible = nocked
	# The flat skin palette does not inherit Node3D visibility. Keep an
	# invisible attachment subpixel there while the detailed mesh is hidden.
	bones.nockedArrow.scale = Vector3.ONE if nocked else Vector3.ONE*.00001
	_motion_debug.merge({"bowDraw":loaded,"bowReleased":released,"nockedArrow":nocked,"bowStringNock":string_nock},true)

func _set_bow_string(key: String, start: Vector3, end: Vector3, shown: bool) -> void:
	var direction: Vector3 = end-start
	var orientation: Basis = Basis(Quaternion(Vector3.UP,direction.normalized()))
	var size: Vector3 = Vector3(1,direction.length(),1) if shown else Vector3.ONE*.00001
	bones[key].transform = Transform3D(orientation.scaled(size),(start+end)*.5)
	bones[key].visible = shown

func _attack_rotation(rest: Vector3, prepared: Vector3, contact: Vector3, phase: Dictionary) -> Vector3:
	return rest.lerp(prepared,float(phase.preparation)).lerp(contact,float(phase.drive)).lerp(rest,float(phase.recovery))

func _pose_attack(data: Dictionary, clock: float) -> void:
	var phase: Dictionary = _attack_phases(data,clock)
	var rest_right: Vector3 = Vector3(0,0,.10)
	var rest_fore: Vector3 = Vector3(.18,0,0)
	var blade_guard: float = .10
	var blade_prepared: float = .20
	var blade_contact: float = -1.48
	var prepared_right: Vector3 = Vector3(1.85,-.08,-.03)
	var contact_right: Vector3 = Vector3(.98,.10,.035)
	var prepared_fore: Vector3 = Vector3(.50,0,0)
	var contact_fore: Vector3 = Vector3(.25,0,0)
	if unit_type == "archer":
		bones.armL.rotation = _attack_rotation(Vector3(.25,0,-.10),Vector3(1.30,-.05,-.10),Vector3(1.30,-.05,-.10),phase)
		bones.foreL.rotation = _attack_rotation(Vector3(.42,0,0),Vector3(.12,0,0),Vector3(.12,0,0),phase)
		bones.armR.rotation = _attack_rotation(Vector3(.25,0,.12),Vector3(1.14,.45,.13),Vector3(1.14,.43,.13),phase)
		bones.foreR.rotation = _attack_rotation(Vector3(.65,0,0),Vector3(1.85,0,0),Vector3(1.70,0,0),phase)
		bones.weapon.rotation = Vector3(-bones.armL.rotation.x-bones.foreL.rotation.x,0,0)
		return
	if unit_type in ["spear","enemy_light"]:
		prepared_right = Vector3(.68,-.05,.06)
		contact_right = Vector3(1.02,.02,.035)
		prepared_fore = Vector3(.68,0,0)
		contact_fore = Vector3(.18,0,0)
		blade_prepared = -1.30
		blade_contact = -1.52
	elif unit_type == "gunner":
		prepared_right = Vector3(1.0,-.12,.16)
		contact_right = Vector3(.99,-.12,.16)
		prepared_fore = Vector3(.67,0,0)
		contact_fore = prepared_fore
		blade_prepared = -PI/2
		blade_contact = blade_prepared
	elif unit_type in ["naginata","monk"]:
		prepared_right = Vector3(1.35,.22,.08)
		contact_right = Vector3(.90,-.15,.06)
		prepared_fore = Vector3(.53,0,0)
		contact_fore = Vector3(.30,0,0)
		blade_prepared = -.48 if unit_type=="naginata" else -.95
		blade_contact = -1.42
	elif unit_type == "ninja":
		prepared_right = Vector3(1.25,-.18,.10)
		contact_right = Vector3(.96,.10,.07)
		prepared_fore = Vector3(.63,0,0)
		contact_fore = Vector3(.26,0,0)
		blade_prepared = -1.06
		blade_contact = -1.48
		bones.armL.rotation = _attack_rotation(Vector3(0,0,-.10),Vector3(.65,-.16,-.15),Vector3(.74,-.13,-.13),phase)
		bones.foreL.rotation = _attack_rotation(rest_fore,Vector3(.63,0,0),Vector3(.49,0,0),phase)
		bones.handL.rotation.x = -1.30-bones.armL.rotation.x-bones.foreL.rotation.x
	else:
		bones.armL.rotation = _attack_rotation(Vector3(0,0,-.10),Vector3(.58,-.12,-.12),Vector3(.81,.06,-.10),phase)
		bones.foreL.rotation = _attack_rotation(rest_fore,Vector3(.47,0,0),Vector3(.31,0,0),phase)
	bones.armR.rotation = _attack_rotation(rest_right,prepared_right,contact_right,phase)
	bones.foreR.rotation = _attack_rotation(rest_fore,prepared_fore,contact_fore,phase)
	var pitch: float = lerpf(lerpf(blade_guard,blade_prepared,float(phase.preparation)),blade_contact,float(phase.drive))
	pitch = lerpf(pitch,blade_guard,float(phase.recovery))
	bones.weapon.rotation = Vector3(pitch-bones.armR.rotation.x-bones.foreR.rotation.x,0,-.04)

func _pose_braced_weapon(data: Dictionary, clock: float) -> void:
	var phase: Dictionary = _attack_phases(data,clock)
	var loaded: float = float(phase.preparation)*(1.0-float(phase.recovery))
	var strike: float = float(phase.drive)*(1.0-float(phase.recovery))
	var rest: Vector3 = Vector3(.065,-.12,-.16)
	var prepared: Vector3 = Vector3(.065,-.035,-.18)
	var contact: Vector3 = Vector3(.040,-.020,-.275)
	var guard_pitch: float = -1.05
	var prepared_pitch: float = -1.22
	var contact_pitch: float = -1.53
	var yaw: float = 0.0
	if unit_type=="samurai":
		prepared = Vector3(.05,.18,-.12)
		contact = Vector3(.045,-.015,-.30)
		guard_pitch = -.55
		prepared_pitch = .20
		contact_pitch = -1.50
	elif unit_type=="naginata":
		prepared = Vector3(.09,.01,-.15)
		contact = Vector3(.045,-.025,-.275)
		prepared_pitch = -.40
		contact_pitch = -1.40
		yaw = .20*loaded-.34*strike
		if clock <= 0.0 and (str(data.get("supportState", "")) == "guard" or str(data.get("role", "")) == "guard"):
			# Hold the blade above the shoulder while watching the firing post.
			# Attack reach and its existing preparation/contact phases stay intact.
			guard_pitch = -.65
	elif unit_type=="monk":
		contact = Vector3(.055,-.020,-.255)
		prepared_pitch = -.78
		contact_pitch = -1.38
	var grip: Vector3 = rest.lerp(prepared,float(phase.preparation)).lerp(contact,float(phase.drive)).lerp(rest,float(phase.recovery))
	var wrist_basis: Basis = global_basis*Basis.from_euler(Vector3(PI/2,0,0))
	_solve_arm("R",bones.torso.global_transform*grip,wrist_basis)
	var pitch: float = lerpf(lerpf(guard_pitch,prepared_pitch,float(phase.preparation)),contact_pitch,float(phase.drive))
	pitch = lerpf(pitch,guard_pitch,float(phase.recovery))
	bones.weapon.global_basis = global_basis*Basis.from_euler(Vector3(pitch,yaw,0))
	_solve_arm("L",bones.weapon.global_transform*Vector3(0,.065 if unit_type=="samurai" else .13,0),wrist_basis)

func _pose_support(data: Dictionary, animation: String, clock: float) -> void:
	var offering: float = 0.0
	if animation == "heal":
		var t: float = clampf(clock/maxf(.12,float(data.get("healDuration", .6))), 0.0, 1.0)
		offering = smoothstep(.0,.35,t)*(1.0-smoothstep(.70,1.0,t))
	var wrist: Basis = global_basis*Basis.from_euler(Vector3(PI/2,0,0))
	_solve_arm("R",bones.torso.global_transform*Vector3(.075,-.12,-.10),wrist)
	# The staff remains vertical; only the free hand presents the talisman.
	bones.weapon.global_basis = global_basis*Basis.from_euler(Vector3(-.08,0,-.04))
	_solve_arm("L",bones.torso.global_transform*Vector3(-.12-.055*offering,-.025,-.13-.15*offering),wrist)
	bones.torso.rotation.x += -.035*offering
	bones.head.rotation.x += .025*offering
	_motion_debug["supportGesture"] = offering
	# The gameplay heal arrives at the start of this gesture. Record its
	# receipt/target without inventing a delayed recovery or another heal.
	_motion_debug.merge({"healCommitted":float(data.get("healAmount",0.0))>0.0,"healAmount":float(data.get("healAmount",0.0)),"healTargetId":int(data.get("healingTargetId",0)),"healCommittedAt":float(data.get("healCommittedAt",0.0))},true)

func _solve_arm(suffix: String, palm_target: Vector3, wrist_basis: Basis) -> void:
	var arm: Node3D = bones["arm"+suffix]
	var fore: Node3D = bones["fore"+suffix]
	var hand: Node3D = bones["hand"+suffix]
	var torso_inverse: Transform3D = bones.torso.global_transform.affine_inverse()
	var goal: Vector3 = torso_inverse*(palm_target-wrist_basis*Vector3(0,-0.03,-0.005))
	var direction: Vector3 = goal-arm.position
	var upper_length: float = fore.position.length()
	var lower_length: float = hand.position.length()
	var distance: float = clampf(direction.length(),0.001,upper_length+lower_length-.001)
	direction = direction.normalized()
	var outward: Vector3 = Vector3.LEFT if suffix == "L" else Vector3.RIGHT
	var bend: Vector3 = (outward-direction*outward.dot(direction)).normalized()
	if bend.length_squared()<0.00001: bend=Vector3.FORWARD
	var along: float = (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2*distance)
	var offset: float = sqrt(maxf(0,upper_length*upper_length-along*along))
	var elbow: Vector3 = arm.position+direction*along+bend*offset
	var upper_basis: Basis = Basis(Quaternion(Vector3.DOWN,(elbow-arm.position).normalized()))
	var lower_basis: Basis = Basis(Quaternion(Vector3.DOWN,(goal-elbow).normalized()))
	arm.basis = upper_basis
	fore.basis = upper_basis.inverse()*lower_basis
	hand.basis = lower_basis.inverse()*torso_inverse.basis*wrist_basis

func _pose_matchlock(data: Dictionary, animation: String, clock: float) -> void:
	var phase: Dictionary = _attack_phases(data,clock)
	var attacking: bool = animation == "attack"
	var raised: float = float(phase.preparation)*(1.0-float(phase.recovery)) if attacking else 0.0
	var since_release: float = float(phase.time)-float(phase.impact)
	var recoil: float = sin(clampf(since_release/.14,0,1)*PI) if attacking and _attack_released(data,clock) else 0.0
	var reloading: bool = animation not in ["attack","walk","death"] and (bool(data.get("reloadActive",false)) or str(data.get("motionPhase","")) in ["reload","reloading"])
	var reload_progress: float = clampf(float(data.get("reloadProgress",0.0)),0,1)
	var servicing: float = smoothstep(0,.16,reload_progress)*(1.0-smoothstep(.82,1.0,reload_progress)) if reloading else 0.0
	var grip_local: Vector3 = Vector3(0.04,lerpf(-0.04,0.025,raised),lerpf(-0.12,-0.20,raised)+recoil*0.008)
	grip_local.y -= servicing*.055
	grip_local.z += servicing*.045
	var right_grip: Vector3 = bones.torso.global_transform*grip_local
	var wrist_basis: Basis = global_basis*Basis.from_euler(Vector3(PI/2,0,0))
	_solve_arm("R",right_grip,wrist_basis)
	bones.weapon.global_basis = global_basis*Basis.from_euler(Vector3(-PI/2+.10*(1-raised)+servicing*.55,servicing*.08,0))
	var left_grip: Vector3 = bones.weapon.global_transform*Vector3(0,0.14,0)
	if reloading:
		# Charge near the muzzle, run the loading stroke, then return to the
		# support grip during the original cooldown. This adds no action delay.
		var loading_stroke: float = sin(clampf((reload_progress-.28)/.45,0,1)*PI)*.09
		left_grip = left_grip.lerp(bones.weapon.global_transform*Vector3(.025,.36-loading_stroke,-.025),servicing)
	_solve_arm("L",left_grip,wrist_basis)
	_motion_debug.merge({"reloading":reloading,"reloadProgress":reload_progress,"matchlockRecoil":recoil},true)

func _ankle_height(pitch: float) -> float:
	return HumanBody.ankle_height(pitch)

func _solve_leg(suffix: String, foot_target: Vector3, pitch: float, yaw_offset: float = 0.0) -> void:
	var thigh: Node3D = bones["thigh"+suffix]
	var shin: Node3D = bones["shin"+suffix]
	var foot: Node3D = bones["foot"+suffix]
	var rig_inverse: Transform3D = rig.transform.affine_inverse()
	var goal: Vector3 = rig_inverse*foot_target
	var hip: Vector3 = thigh.position
	var direction: Vector3 = goal-hip
	var upper_length: float = shin.position.length()
	var lower_length: float = foot.position.length()
	var distance: float = clampf(direction.length(),0.001,upper_length+lower_length-.001)
	direction = direction.normalized()
	var bending: Vector3 = Vector3.FORWARD-direction*Vector3.FORWARD.dot(direction)
	if bending.length_squared()<0.00001:
		bending = Vector3.RIGHT
	bending = bending.normalized()
	var along: float = (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2.0*distance)
	var height: float = sqrt(maxf(0.0,upper_length*upper_length-along*along))
	var knee: Vector3 = hip+direction*along+bending*height
	var upper_basis: Basis = Basis(Quaternion(Vector3.DOWN,(knee-hip).normalized()))
	var lower_basis: Basis = Basis(Quaternion(Vector3.DOWN,(goal-knee).normalized()))
	thigh.basis = upper_basis
	shin.basis = upper_basis.inverse()*lower_basis
	var desired: Basis = rig_inverse.basis*Basis.from_euler(Vector3(pitch,yaw_offset,0))
	foot.basis = lower_basis.inverse()*desired

func _walk_foot(suffix: String, cycle: float, data: Dictionary) -> Dictionary:
	var phase: float = fposmod(cycle,1.0)
	var side: float = -1.0 if suffix == "L" else 1.0
	var running: float = clampf(float(data.get("runBlend",0.0)),0.0,1.0)
	var stance: float = lerpf(0.58,0.40,running)
	var landing_pitch: float = lerpf(0.18,0.10,running)
	var toe_off_pitch: float = lerpf(-0.27,-0.56,running)
	var front: float = lerpf(-0.24,-0.17,running)*HUMAN_HEIGHT_RATIO
	var back: float = lerpf(0.28,0.20,running)*HUMAN_HEIGHT_RATIO
	var planted: bool = phase<stance
	var pitch: float
	var local_target: Vector3
	var lift: float = 0.0
	var ankle: float
	if planted:
		var progress: float = phase/stance
		pitch = lerpf(landing_pitch,toe_off_pitch,smoothstep(0.0,1.0,progress))
		ankle = _ankle_height(pitch)
		local_target = Vector3(side*HUMAN_STANCE_HALF_WIDTH,ankle,lerpf(front,back,progress))
	else:
		var progress: float = (phase-stance)/(1.0-stance)
		pitch = lerpf(toe_off_pitch,landing_pitch,smoothstep(0.12,0.92,progress))
		ankle = _ankle_height(pitch)
		# Recover the heel behind the hips before bringing the knee forward.
		# Running has a genuine aerial interval, unlike the low-speed walk.
		lift = sin(progress*PI)*lerpf(0.092,0.24,running)*HUMAN_HEIGHT_RATIO
		var recovery: float = lerpf(smoothstep(0,1,progress),smoothstep(0.18,1.0,progress),running)
		local_target = Vector3(side*HUMAN_STANCE_HALF_WIDTH,ankle+lift,lerpf(back,front,recovery))
	var yaw_offset: float = 0.0
	if bool(data.get("groundMotion",false)):
		var cycle_index: int = floori(cycle)
		var contact: Dictionary = foot_contacts.get(suffix,{})
		if contact.is_empty() or bool(data.get("motionReset",false)):
			contact = {"point":global_transform*local_target,"yaw":rotation.y,"cycle":cycle_index,"mode":"stance" if planted else "swing"}
			contact["start"] = contact.point
			contact["end"] = global_transform*Vector3(side*HUMAN_STANCE_HALF_WIDTH,_ankle_height(landing_pitch),front)
		if planted:
			if str(contact.mode)!="stance" or int(contact.cycle)!=cycle_index:
				contact.point = contact.end if str(contact.mode)=="swing" else global_transform*local_target
				contact.yaw = rotation.y
			contact.mode = "stance"
			contact.cycle = cycle_index
			var world_target: Vector3 = contact.point
			world_target.y = global_position.y+ankle*global_basis.get_scale().y
			local_target = global_transform.affine_inverse()*world_target
			yaw_offset = wrapf(float(contact.yaw)-rotation.y,-PI,PI)
		else:
			var progress: float = (phase-stance)/(1.0-stance)
			if str(contact.mode)!="swing":
				contact.start = contact.point
				var cadence: float = maxf(.1,float(data.get("locomotionCadence",1.35)))
				var velocity: Vector3 = data.get("travelVelocity",global_basis*Vector3.FORWARD*.90*HUMAN_HEIGHT_RATIO*cadence)
				contact.end = global_transform*Vector3(side*HUMAN_STANCE_HALF_WIDTH,_ankle_height(landing_pitch),front)+velocity*((1.0-phase)/cadence)
				contact.mode = "swing"
			var recovery: float = lerpf(smoothstep(0,1,progress),smoothstep(0.18,1.0,progress),running)
			var world_target: Vector3 = (contact.start as Vector3).lerp(contact.end,recovery)
			world_target.y = global_position.y+(ankle+lift)*global_basis.get_scale().y
			local_target = global_transform.affine_inverse()*world_target
		foot_contacts[suffix] = contact
	var sampler: Callable=data.get("groundHeightSampler",Callable())
	if sampler.is_valid():
		var world_target: Vector3=global_transform*local_target
		var ground: float=float(sampler.call(world_target))
		if is_finite(ground):
			world_target.y+=clampf(ground-global_position.y,-.14*global_basis.get_scale().y,.14*global_basis.get_scale().y)
			local_target=global_transform.affine_inverse()*world_target
	return {"target":local_target,"pitch":pitch,"yaw":yaw_offset,"stance":planted,"phase":phase}

func _animate_full_body(data: Dictionary, animation: String, clock: float, phase_offset_value: float, sailing: bool) -> void:
	var cycle: float = float(data.get("locomotionPhase",(clock+phase_offset_value)*1.35))
	var breathing: float = sin((clock+phase_offset_value)*TAU*0.34)
	if animation!=last_motion_animation or bool(data.get("motionReset",false)):
		foot_contacts.clear()
	last_motion_animation = animation
	var left_shoulder: Vector3 = Vector3(-shoulder_half_width(),.20*HUMAN_HEIGHT_RATIO,0)
	var right_shoulder: Vector3 = Vector3(shoulder_half_width(),.20*HUMAN_HEIGHT_RATIO,0)
	if bones.armL.position!=left_shoulder: bones.armL.position = left_shoulder
	if bones.armR.position!=right_shoulder: bones.armR.position = right_shoulder
	if animation == "death":
		if sailing:
			_animate_sailing_death(clock)
			return
		var t: float = clampf(clock/0.6667,0,1)
		var collapse: float = smoothstep(0.13,0.92,t*t)
		rig.position = Vector3(0,lerpf(0.875*HUMAN_HEIGHT_RATIO,0.18,collapse),0.10*collapse)
		rig.rotation = Vector3(-1.40*collapse,0,0.12*collapse*sin(phase_offset_value*19))
		bones.torso.rotation.x = -0.21*sin(t*PI)
		bones.head.rotation.x = 0.15*collapse
		bones.thighL.rotation = Vector3(0.36*sin(t*PI),0,-0.10*collapse)
		bones.thighR.rotation = Vector3(0.15*sin(t*PI),0,0.08*collapse)
		bones.shinL.rotation.x = -0.48*sin(t*PI)
		bones.shinR.rotation.x = -0.22*sin(t*PI)
		bones.armL.rotation = Vector3(0.78*collapse,0,-0.36*collapse)
		bones.armR.rotation = Vector3(0.45*collapse,0,0.33*collapse)
		_settle_death_on_ground()
		_motion_debug = {"mode":"death","fall":collapse}
		return
	if unit_type == "commander" and not sailing:
		_animate_mount(cycle,clock,phase_offset_value,animation,data)
		_motion_debug = {"mode":"mounted","phase":cycle,"runBlend":float(data.get("runBlend",0.0)),"gait":"gallop" if float(data.get("runBlend",0.0))>.8 else "trot"}
		return
	var left: Dictionary
	var right: Dictionary
	if animation!="walk" or sailing:
		var ankle: float = _ankle_height(0)
		left = {"target":Vector3(-HUMAN_STANCE_HALF_WIDTH,ankle,-.015),"pitch":0.0,"yaw":0.0,"stance":true}
		right = {"target":Vector3(HUMAN_STANCE_HALF_WIDTH,ankle,.015),"pitch":0.0,"yaw":0.0,"stance":true}
		rig.position = Vector3(breathing*0.003,0.880*HUMAN_HEIGHT_RATIO,0)
		rig.rotation = Vector3(0,0,breathing*0.004)
		bones.torso.rotation.z -= breathing*0.003
	if animation == "walk" and not sailing:
		var sway: float = sin(cycle*TAU)
		var running: float = clampf(float(data.get("runBlend",0.0)),0.0,1.0)
		var compression: float = -cos((cycle-.20)*TAU*2.0)
		var walk_height: float = .872*HUMAN_HEIGHT_RATIO+cos(cycle*TAU*2.0)*.005
		var run_height: float = .851*HUMAN_HEIGHT_RATIO+compression*.030
		rig.position = Vector3(sway*lerpf(.006,.011,running),lerpf(walk_height,run_height,running),0)
		rig.rotation = Vector3(lerpf(-.020,-.095,running)+compression*.010*running,cos(cycle*TAU)*lerpf(.014,.025,running),-sway*lerpf(.010,.020,running))
		bones.torso.rotation = Vector3(lerpf(.010,-.018,running),sway*lerpf(.038,.068,running),sway*lerpf(.007,.012,running))
		bones.head.rotation = Vector3(lerpf(.025,.085,running)-compression*.012*running,-sway*lerpf(.020,.040,running),sway*.008*running)
		var cover: float=clampf(float(data.get("approachCover",0.0)),0.0,1.0)
		var pitch: float=float(data.get("terrainPitch",0.0))
		var roll: float=float(data.get("terrainRoll",0.0))
		rig.position.y-=cover*.085*HUMAN_HEIGHT_RATIO
		rig.rotation.x-=cover*.12+pitch*.24
		rig.rotation.z-=roll*.20
		bones.torso.rotation.x-=cover*.08+pitch*.15
		bones.head.rotation.x+=cover*.10+pitch*.12
		left = _walk_foot("L",cycle,data)
		right = _walk_foot("R",cycle+0.5,data)
		for side in [-1,1]:
			var suffix: String = "L" if side<0 else "R"
			var arm_swing: float = cos(cycle*TAU)*float(side)*lerpf(.12,.29,running)
			bones["arm"+suffix].rotation = Vector3(arm_swing+(0.20 if unit_type=="archer" else 0.0),0,float(side)*.10)
			bones["fore"+suffix].rotation = Vector3(lerpf(.18,.72,running)+maxf(0.0,-arm_swing)*.5,0,0)
		if unit_type=="ninja":
			bones.handL.rotation.x = -1.30-bones.armL.rotation.x-bones.foreL.rotation.x
		bones.weapon.rotation.x = -bones["armL" if unit_type == "archer" else "armR"].rotation.x-bones["foreL" if unit_type == "archer" else "foreR"].rotation.x+0.05
	elif animation == "attack":
		var phases: Dictionary = _attack_phases(data,clock)
		var preparation: float = float(phases.preparation)
		var drive: float = float(phases.drive)
		var recovery: float = float(phases.recovery)
		if unit_type in ["archer","gunner"]:
			var brace: float = preparation*(1.0-recovery)
			rig.position = Vector3(-0.006*brace,0.880*HUMAN_HEIGHT_RATIO-0.006*brace,0.007*brace)
			rig.rotation.y = 0.014*brace
			bones.torso.rotation.y = -0.065*brace
		else:
			var push: float = drive*(1.0-recovery)
			var loaded: float = preparation*(1.0-recovery)
			rig.position = Vector3(-0.006*push,0.880*HUMAN_HEIGHT_RATIO-0.012*loaded,0.018*preparation*(1.0-drive)-0.040*push)
			rig.rotation = Vector3(-0.022*push,0.025*loaded-0.045*push,-0.010*push)
			bones.torso.rotation.y = -0.070*loaded+0.140*push
			bones.torso.rotation.x = -0.035*push
			bones.armR.position.z = -0.012*push
		_motion_debug = {"mode":"attack","phase":phases.time,"impactPhase":phases.impact,"preparation":preparation,"drive":drive,"recovery":recovery}
	if not sailing and animation in ["idle","attack","heal"]:
		var landing: float = float(_attack_phases(data,clock).preparation) if animation=="attack" else 1.0
		for entry in [{"suffix":"L","foot":left},{"suffix":"R","foot":right}]:
			var foot: Dictionary = entry.foot
			if standing_foot_contacts.has(entry.suffix):
				var contact: Dictionary = standing_foot_contacts[entry.suffix]
				var local: Vector3 = global_transform.affine_inverse()*contact.point
				foot.target = Vector3(local.x,_ankle_height(0)+maxf(0,local.y-_ankle_height(0))*(1.0-landing),local.z)
				foot.yaw = wrapf(float(contact.yaw)-rotation.y,-PI,PI)
	if sailing:
		var rowing: float = sin((clock+phase_offset_value)*TAU*0.65)
		rig.position = Vector3(0,0.690,0.024*rowing)
		rig.rotation = Vector3(-0.06*rowing,0,0.008*rowing)
		bones.torso.rotation.x = -0.10*rowing
		bones.head.rotation.x = 0.04*rowing
		for side in [-1,1]:
			var suffix: String = "L" if side<0 else "R"
			bones["arm"+suffix].rotation = Vector3(0.35+rowing*0.14,0,float(side)*0.12)
			bones["fore"+suffix].rotation.x = 0.70-rowing*0.22
			bones["oar"+suffix].rotation = Vector3(0.09*rowing,float(side)*0.28*rowing,float(side)*0.07)
		left.target = Vector3(-HUMAN_STANCE_HALF_WIDTH,_ankle_height(0)+0.14,-0.26)
		right.target = Vector3(HUMAN_STANCE_HALF_WIDTH,_ankle_height(0)+0.14,-0.26)
	_solve_leg("L",left.target,float(left.pitch),float(left.yaw))
	_solve_leg("R",right.target,float(right.pitch),float(right.yaw))
	if sailing:
		for side in [-1,1]:
			var suffix: String = "L" if side<0 else "R"
			var grip: Vector3 = bones["hand"+suffix].global_transform*Vector3(0,-0.03,-0.005)
			var rowing: float = sin((clock+phase_offset_value)*TAU*0.65)
			var blade: Vector3 = global_transform*Vector3(float(side)*0.75,0.035,0.26+rowing*0.18)
			var direction: Vector3 = blade-grip
			var original_direction: Vector3 = Vector3(float(side)*0.32,-0.06,0.30)
			var orientation: Basis = Basis(Quaternion(original_direction.normalized(),direction.normalized()))
			var oar_scale: float = (direction.length()+0.10)/original_direction.length()
			bones["oar"+suffix].global_transform = Transform3D(orientation.scaled(Vector3.ONE*oar_scale),grip-direction.normalized()*0.10)
	if animation!="attack" or sailing:
		_motion_debug = {"mode":"rowing" if sailing else animation,"phase":cycle,"runBlend":float(data.get("runBlend",0.0)),"gait":"run" if float(data.get("runBlend",0.0))>.8 else "walk"}
	_motion_debug.merge({"leftStance":left.stance,"rightStance":right.stance},true)

func _animate_sailing_death(clock: float) -> void:
	# A water casualty stays seated in the existing hull until its cosmetic
	# lifetime expires. Do not run the land fall or ground-settling solver.
	var fall: float = smoothstep(0.0,0.6667,clock)
	boat.position = Vector3(0,-0.13*fall,0)
	boat.rotation = Vector3(0.045*fall,0,0.070*fall)
	rig.position = boat.transform*Vector3(0,0.690,0)
	rig.rotation = boat.rotation+Vector3(-0.16*fall,0,0.020*fall)
	bones.torso.rotation = Vector3(-0.10*fall,0,0)
	bones.head.rotation = Vector3(0.025+0.20*fall,0,0)
	for side in [-1,1]:
		var suffix: String = "L" if side<0 else "R"
		bones["arm"+suffix].rotation = Vector3(0.35-0.14*fall,0,float(side)*0.12)
		bones["fore"+suffix].rotation = Vector3(0.70+0.08*fall,0,0)
		_solve_leg(suffix,boat.transform*Vector3(float(side)*HUMAN_STANCE_HALF_WIDTH,_ankle_height(0)+0.14,-0.26),boat.rotation.x)
		var grip: Vector3 = bones["hand"+suffix].global_transform*Vector3(0,-0.03,-0.005)
		var blade: Vector3 = boat.global_transform*Vector3(float(side)*0.75,0.035,0.26)
		var direction: Vector3 = blade-grip
		var original_direction: Vector3 = Vector3(float(side)*0.32,-0.06,0.30)
		var orientation: Basis = Basis(Quaternion(original_direction.normalized(),direction.normalized()))
		var oar_scale: float = (direction.length()+0.10)/original_direction.length()
		bones["oar"+suffix].global_transform = Transform3D(orientation.scaled(Vector3.ONE*oar_scale),grip-direction.normalized()*0.10)
	_motion_debug = {"mode":"sailing_death","fall":fall,"sink":-boat.position.y}

func _settle_death_on_ground() -> void:
	var minimum: float = INF
	var inverse_actor: Transform3D = global_transform.affine_inverse()
	for instance in meshes:
		if not rig.is_ancestor_of(instance):
			continue
		var relative: Transform3D = inverse_actor*instance.global_transform
		var bounds: AABB = instance.mesh.get_aabb()
		var half_size: Vector3 = bounds.size*0.5
		var center: Vector3 = relative*bounds.get_center()
		var support: float = absf(relative.basis.x.y)*half_size.x+absf(relative.basis.y.y)*half_size.y+absf(relative.basis.z.y)*half_size.z
		minimum = minf(minimum,center.y-support)
	if is_finite(minimum):
		rig.position.y += 0.006-minimum

func _animate_mount(cycle: float, clock: float, phase_offset_value: float, animation: String, data: Dictionary) -> void:
	var gait: float = cycle*TAU
	var moving: bool = animation == "walk"
	var running: float = clampf(float(data.get("runBlend",0.0)),0,1) if moving else 0.0
	var breathing: float = sin((clock+phase_offset_value)*TAU*0.28)
	var suspension: float = cos((cycle-.92)*TAU)
	var rise: float = lerpf(sin(gait*2)*.006,suspension*.035,running) if moving else breathing*.0015
	var rocking: float = lerpf(.007*sin(gait),.034*sin(gait+.22),running) if moving else 0.0
	mount.position = Vector3(0,-.145+rise,0)
	mount.rotation = Vector3(rocking,0,.005*sin(gait) if moving else 0.0)
	# The pelvis follows the saddle; knees absorb its impulse while the
	# torso and head settle slightly later instead of rigidly bobbing as one.
	var rider_rise: float = lerpf(sin(gait*2)*.010,rise+sin(gait-.32)*.012,running) if moving else breathing*.0015
	rig.position = Vector3(0,1.30+rider_rise,-.018*running)
	rig.rotation = Vector3(lerpf(-.014*sin(gait*2),rocking*.65-.025,running) if moving else 0.0,0,.007*sin(gait) if moving else 0.0)
	if moving:
		bones.torso.rotation.x = (-.025-rocking*.45)*running
		bones.torso.rotation.z = 0.0
		bones.head.rotation.x = .035*running+rocking*.30
		bones.head.rotation.z = 0.0
	if animation == "attack":
		var phases: Dictionary = _attack_phases(data,clock)
		var push: float = float(phases.drive)*(1.0-float(phases.recovery))
		rig.position.z = -0.020*push
		rig.rotation.x = -0.032*push
		bones.torso.rotation.y = -0.065*float(phases.preparation)*(1.0-float(phases.recovery))+.11*push
	for side in [-1,1]:
		var suffix: String = "L" if side<0 else "R"
		bones["thigh"+suffix].rotation = Vector3(.85+sin(gait-.32)*.018*running,0,float(side)*.40)
		bones["shin"+suffix].rotation = Vector3(-.98-sin(gait-.32)*.036*running,0,0)
		bones["foot"+suffix].rotation = Vector3(-.13+sin(gait-.32)*.018*running,0,0)
	for leg in range(4):
		# Right-lead transverse gallop: left hind, right hind, left fore,
		# right fore, then suspension. Slow travel retains the diagonal trot.
		var trot_offset: float = 0.0 if leg in [0,3] else .5
		var gallop_offset: float = [-.38,.44,0.0,-.18][leg]
		var leg_phase: float = cycle+lerpf(trot_offset,gallop_offset,running)
		var target: Vector3 = _horse_contact(leg,leg_phase,data) if moving else Vector3(-0.19 if leg%2 == 0 else 0.19,0.060,-0.31 if leg<2 else 0.33)
		hoof_lifts[leg] = maxf(0.0,target.y-.060)
		_solve_horse_leg(leg,target)
	bones.horse_neck.rotation.x = -.060*sin(gait)-rocking*.6 if moving else breathing*.015
	bones.horse_head.rotation.x = .035*sin(gait)+rocking*.45 if moving else breathing*.018
	bones.horse_tail.rotation = Vector3(0.07,0,(sin(gait)*0.075 if moving else breathing*0.065))

func _horse_contact(leg: int, cycle: float, data: Dictionary) -> Vector3:
	var phase: float = fposmod(cycle,1.0)
	var running: float = clampf(float(data.get("runBlend",0.0)),0,1)
	var stance: float = lerpf(.60,.31 if leg==1 else .28 if leg==0 else .29,running)
	var planted: bool = phase<stance
	var progress: float = phase/stance if planted else (phase-stance)/(1.0-stance)
	var side_x: float = -0.19 if leg%2 == 0 else 0.19
	var base_z: float = -0.31 if leg<2 else 0.33
	var reach: float = lerpf(.375,.265,running)
	var lift: float = 0.0 if planted else sin(progress*PI)*lerpf(.075,.205 if leg<2 else .175,running)
	var target: Vector3 = Vector3(side_x,.060+lift,base_z+(lerpf(-reach,reach,progress) if planted else lerpf(reach,-reach,smoothstep(0,1,progress))))
	if not bool(data.get("groundMotion",false)):
		return target
	var key: String = "horse%d" % leg
	var contact: Dictionary = foot_contacts.get(key,{})
	var cycle_index: int = floori(cycle)
	if contact.is_empty() or bool(data.get("motionReset",false)):
		contact = {"point":global_transform*target,"cycle":cycle_index,"mode":"stance" if planted else "swing"}
		contact.start = contact.point
		contact.end = global_transform*Vector3(side_x,.060,base_z-reach)
	if planted:
		if str(contact.mode)!="stance" or int(contact.cycle)!=cycle_index:
			contact.point = contact.end if str(contact.mode)=="swing" else global_transform*target
		contact.mode = "stance"
		contact.cycle = cycle_index
		target = global_transform.affine_inverse()*contact.point
		target.y = 0.060
	else:
		if str(contact.mode)!="swing":
			contact.start = contact.point
			var cadence: float = maxf(.1,float(data.get("locomotionCadence",1.35)))
			var velocity: Vector3 = data.get("travelVelocity",global_basis*Vector3.FORWARD*1.25*cadence)
			contact.end = global_transform*Vector3(side_x,.060,base_z-reach)+velocity*((1.0-phase)/cadence)
			contact.mode = "swing"
		target = global_transform.affine_inverse()*(contact.start as Vector3).lerp(contact.end,smoothstep(0,1,progress))
		target.y = .060+lift
	foot_contacts[key] = contact
	return target

func _solve_horse_leg(leg: int, target: Vector3, wanted_floor: float = -INF) -> void:
	var upper: Node3D = bones["horse_leg%d" % leg]
	var lower: Node3D = bones["horse_calf%d" % leg]
	var adjusted: Vector3 = target
	var mount_inverse: Transform3D = mount.transform.affine_inverse()
	var floor_height: float = .005+maxf(0,target.y-.060) if is_inf(wanted_floor) else wanted_floor
	# The hoof is part of the articulated calf mesh. Its lowest real vertex,
	# rather than a fixed ankle height, determines contact as the heel rolls.
	for iteration in range(3):
		var goal: Vector3 = mount_inverse*adjusted
		var delta: Vector3 = goal-upper.position
		var distance: float = clampf(delta.length(),0.001,0.745)
		var direction: Vector3 = delta.normalized()
		var bend: Vector3 = Vector3.FORWARD if leg<2 else Vector3.BACK
		bend = bend-direction*bend.dot(direction)
		bend = bend.normalized() if bend.length_squared()>.00001 else Vector3.RIGHT
		var along: float = (0.37*0.37-0.376*0.376+distance*distance)/(2*distance)
		var height: float = sqrt(maxf(0,0.37*0.37-along*along))
		var knee: Vector3 = upper.position+direction*along+bend*height
		var a: Basis = Basis(Quaternion(Vector3.DOWN,(knee-upper.position).normalized()))
		var b: Basis = Basis(Quaternion(Vector3.DOWN,(goal-knee).normalized()))
		upper.basis = a
		lower.basis = a.inverse()*b
		var error: float = floor_height-_contact_minimum("horse_calf%d"%leg)
		if absf(error)<.0003:
			break
		adjusted.y += error

func diagnostics() -> Dictionary:
	var triangles: int = 0
	var orphan_vertices: int = 0
	var visible_batches: int = 0
	for instance in meshes:
		if instance.is_visible_in_tree():
			visible_batches += 1
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size()/3 if not indices.is_empty() else vertices.size()/3
			if not indices.is_empty():
				var referenced: Dictionary = {}
				for index in indices:
					referenced[index] = true
				orphan_vertices += vertices.size()-referenced.size()
	if skinned_renderer!=null:
		visible_batches = skinned_renderer.visible_batches()
	return {"type":unit_type,"evolution":evolution_stage,"mounted":unit_type == "commander","heroDetail":hero_detail,"articulatedJoints":bones.size(),"meshBatches":skinned_renderer.groups.size() if skinned_renderer!=null else meshes.size(),"sourceJointMeshes":meshes.size(),"visibleMeshBatches":visible_batches,"triangleEstimate":triangles,"unreferencedVertices":orphan_vertices,"realNormalMaps":bool(materials.lacquer.normal_enabled),"materialsShared":material_cache.size(),"geometryVariantsCached":geometry_cache.size(),"skinned":skinned_renderer!=null}
