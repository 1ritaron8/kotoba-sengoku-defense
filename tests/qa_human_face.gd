extends SceneTree

const FACE = preload("res://native/human_face_3d.gd")
const MATERIALS = preload("res://native/actor_materials.gd")
var failures: Array = []
var checks = 0
var report: Dictionary = {}
var high_detail = true
var output_prefix = "res://tests/qa_human_face"
var batched = false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, name: String) -> void:
	checks += 1
	if not condition:
		failures.append(name)
		push_error(name)

func _run() -> void:
	high_detail = not OS.get_cmdline_user_args().has("--low")
	if OS.get_cmdline_user_args().has("--before"): output_prefix += "_before"
	if not high_detail: output_prefix += "_low"
	batched=OS.get_cmdline_user_args().has("--batched")
	if batched: output_prefix += "_batched"
	var parts = FACE.build(high_detail)
	_check(parts.size()==5,"Five material-batched meshes")
	var triangles = 0
	var total_vertices = 0
	var bounds = AABB()
	var first = true
	for part in parts:
		var mesh: ArrayMesh = part.mesh
		_check(FACE.material_recipe().has(part.material),"Material recipe exists for "+part.material)
		_check(mesh.get_surface_count()==1,"One surface per material batch")
		var arrays = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_check(indices.size()>0 and indices.size()%3==0,"Indexed triangles for "+part.material)
		_check(normals.size()==vertices.size() and uvs.size()==vertices.size(),"Smooth normals and UVs for "+part.material)
		var referenced = {}
		for index in indices: referenced[index] = true
		_check(referenced.size()==vertices.size(),"No unreferenced vertices for "+part.material)
		var finite = true
		var normalized = true
		var front_normal = 0.0
		var front_count = 0
		for index in range(vertices.size()):
			finite = finite and vertices[index].is_finite() and normals[index].is_finite()
			normalized = normalized and absf(normals[index].length()-1.0)<0.02
			if part.material=="skin" and vertices[index].z < -0.075 and absf(vertices[index].x)<0.030 and vertices[index].y>0.0 and vertices[index].y<0.08:
				front_normal += normals[index].z
				front_count += 1
		_check(finite,"Finite vertices/normals for "+part.material)
		_check(normalized,"Unit-length smooth normals for "+part.material)
		if part.material=="skin":
			_check(front_count>0 and front_normal/front_count < -0.5,"Face normals point toward local -Z")
		triangles+=indices.size()/3
		total_vertices+=vertices.size()
		bounds = mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
		first = false
	_check(bounds.size.x>0.21 and bounds.size.x<0.24,"Adult head and attached ears stay within .21-.24m")
	_check(bounds.size.y>0.248 and bounds.size.y<0.255,"Adult head height approx .25m")
	if not high_detail:
		_check(triangles<=4200,"Battle LOD has at most 4200 triangles")
		var high_bounds = AABB()
		var high_first = true
		for part in FACE.build(true):
			high_bounds = part.mesh.get_aabb() if high_first else high_bounds.merge(part.mesh.get_aabb())
			high_first = false
		_check(absf(high_bounds.size.x-bounds.size.x)<0.003 and absf(high_bounds.size.y-bounds.size.y)<0.003,"LOD keeps adult proportions and silhouette within 3mm")
		_check(parts[0].mesh!=FACE.build(true)[0].mesh,"High and low LOD caches are separate")
	_check(parts[0].mesh==FACE.build(high_detail)[0].mesh,"Repeated builds reuse the same geometry cache")
	report={"checks":checks,"detail":"high" if high_detail else "low","triangles":triangles,"vertices":total_vertices,"bounds":str(bounds),"renderer":RenderingServer.get_video_adapter_name(),"actualActorShader":batched,"failures":failures}
	if DisplayServer.get_name()!="headless":
		await _render(parts)
	var output=FileAccess.open(output_prefix+".json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("QA_HUMAN_FACE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _render(parts: Array[Dictionary]) -> void:
	var viewport=SubViewport.new()
	viewport.size=Vector2i(640,640)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_4X
	root.add_child(viewport)
	var world=Node3D.new()
	viewport.add_child(world)
	var environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(0.09,0.10,0.11)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color(0.80,0.83,0.88)
	environment.ambient_light_energy=0.55
	var environment_node=WorldEnvironment.new()
	environment_node.environment=environment
	world.add_child(environment_node)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-30,135,0)
	sun.light_color=Color(1.0,0.95,0.88)
	sun.light_energy=1.0
	world.add_child(sun)
	var recipes: Dictionary={}
	var pieces: Array=[]
	for part in parts:
		var info: Dictionary=FACE.material_recipe()[part.material]
		var material=StandardMaterial3D.new()
		material.albedo_color=info.albedo
		material.roughness=info.roughness
		material.metallic=info.metallic
		material.vertex_color_use_as_albedo=true
		material.set_meta("surface_recipe",{"colour":info.albedo,"metallic":info.metallic,"roughness":info.roughness,"texture":"","normalScale":0.0})
		recipes[part.material]=material
		pieces.append({"bone":"head","material":part.material,"mesh":part.mesh})
		if batched: continue
		var instance=MeshInstance3D.new()
		instance.mesh=part.mesh
		instance.material_override=material
		world.add_child(instance)
	if batched:
		for piece in MATERIALS.batch_by_joint(pieces,recipes):
			var instance=MeshInstance3D.new()
			instance.mesh=piece.mesh
			instance.material_override=MATERIALS.material()
			world.add_child(instance)
	var camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=0.32
	camera.near=0.01
	camera.far=3.0
	world.add_child(camera)
	camera.current=true
	for angle in [{"name":"front","angle":0.0},{"name":"threequarter","angle":35.0},{"name":"profile","angle":80.0}]:
		var radians=deg_to_rad(angle.angle)
		camera.position=Vector3(sin(radians),0.105,-cos(radians))
		camera.look_at(FACE.CENTER,Vector3.UP)
		for unused in range(6): await process_frame
		RenderingServer.force_draw(false)
		viewport.get_texture().get_image().save_png(output_prefix+"_"+angle.name+".png")
	report["gpuImages"]=[output_prefix+"_front.png",output_prefix+"_threequarter.png",output_prefix+"_profile.png"]
