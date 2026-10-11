extends SceneTree
## HQ-only bounded probe; product files and lighting are never modified.
const Troops = preload("res://native/troops_3d.gd")
const Visuals = preload("res://native/remaster_visual_slice.gd")
const WORK: String="C:/JP_DF/tools/art-authoring-pilot/work/20261010T050221Z-581667a1"
var result: Dictionary={"scope":"Controlled material probe;not normal gameplay","product_writes":0,"rows":[],"captures":[]}
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var materials: Array=[]
var holder: WorldEnvironment
var output: String=WORK+"/evidence/material-probe"
var completed: bool=false

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(10.0).timeout.connect(func():
		if not completed:
			result["status"]="TIMEOUT"
			_finish(2))
	call_deferred("_run")

func _find_material(node: Node, name_value: String) -> BaseMaterial3D:
	if node is MeshInstance3D and node.mesh!=null:
		for index in range(node.mesh.get_surface_count()):
			var material: BaseMaterial3D=node.get_active_material(index) as BaseMaterial3D
			if material!=null and material.resource_name==name_value: return material
	for child in node.get_children():
		var found: BaseMaterial3D=_find_material(child,name_value)
		if found!=null: return found
	return null

func _custom(source: BaseMaterial3D, mode: String, unlit: bool=false) -> ShaderMaterial:
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform sampler2D diffuse : source_color,filter_linear_mipmap,repeat_enable;
uniform float rough=0.94;
uniform float spec=0.16;
vec3 linear_input(vec3 c){if(!OUTPUT_IS_SRGB)return c;return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
vec3 output_color(vec3 c){c=max(c,vec3(0.0));if(!OUTPUT_IS_SRGB)return c;return mix(c*12.92,1.055*pow(c,vec3(1.0/2.4))-vec3(.055),step(vec3(.0031308),c));}
void fragment(){vec3 pigment=linear_input(texture(diffuse,UV).rgb);ALBEDO=FINAL_COLOR;METALLIC=0.0;ROUGHNESS=rough;SPECULAR=spec;}
""".replace("FINAL_COLOR","output_color(pigment)" if mode=="boundary" else "pigment")
	if unlit: shader.code=shader.code.replace("render_mode cull_disabled;","render_mode cull_disabled,unshaded;")
	var material:=ShaderMaterial.new()
	material.shader=shader
	material.set_shader_parameter("diffuse",source.albedo_texture)
	material.set_shader_parameter("rough",source.roughness)
	material.set_shader_parameter("spec",source.metallic_specular)
	return material

func _run() -> void:
	result["renderer"]=RenderingServer.get_current_rendering_method()
	if result.renderer!="gl_compatibility":
		result["status"]="WRONG_RENDERER"
		_finish(2)
		return
	var stage: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefields-remaster/reference-scene-01.json"))
	var original=Troops.new()
	root.add_child(original)
	original.set_stage(stage)
	var visual=Visuals.new()
	visual.composition=stage.visualComposition.duplicate(true)
	visual.apply_lighting(original)
	viewport=SubViewport.new(); viewport.size=Vector2i(1440,900); viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world=Node3D.new();viewport.add_child(world)
	holder=WorldEnvironment.new();holder.environment=original.environment.duplicate(true);world.add_child(holder)
	world.add_child(original.sun.duplicate())
	if is_instance_valid(original.fill): world.add_child(original.fill.duplicate())
	camera=original.camera.duplicate() as Camera3D;world.add_child(camera);camera.current=true
	# Exact mounted camera readback from completed first-pass native showcase.
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=23.5;camera.position=Vector3(-.25,30.45,30.81591);camera.rotation_degrees=Vector3(-44,0,0)
	result["actual_cloned_environment"]={"tonemap":holder.environment.tonemap_mode,"exposure":holder.environment.tonemap_exposure,"ambient_energy":holder.environment.ambient_light_energy,"ambient_color":str(holder.environment.ambient_light_color),"fog":holder.environment.fog_enabled,"sun_energy":original.sun.light_energy,"sun_color":str(original.sun.light_color),"sun_rotation":str(original.sun.rotation_degrees),"fill_energy":original.fill.light_energy}
	original.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var library: Node3D=(load("res://assets/blender-pilot/asset.glb") as PackedScene).instantiate() as Node3D
	world.add_child(library);library.hide()
	var names: Array=["Broadleaf_LeafScale_ImagePBR_OPAQUE","CompactedDirt_ImagePBR","DryStone_ImagePBR"]
	for row in range(names.size()):
		var source: BaseMaterial3D=_find_material(library,str(names[row]))
		if source==null:
			result["status"]="MISSING_MATERIAL: "+str(names[row]);_finish(2);return
		for column in range(3):
			var mode: String=["standard","boundary","linear_output_test_only"][column]
			var mesh:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(3.7,2.1);mesh.mesh=quad
			mesh.position=Vector3(0,.9,0)+camera.basis.x*(-5.0+column*5.0)+camera.basis.y*(3.0-row*3.0)
			mesh.basis=camera.basis;mesh.layers=1
			var material: Material=source.duplicate(true) if column==0 else _custom(source,"boundary" if column==1 else "linear")
			# Leaf has no normal map; disable normals on every control for parity.
			if material is BaseMaterial3D:
				(material as BaseMaterial3D).normal_enabled=false
				(material as BaseMaterial3D).cull_mode=BaseMaterial3D.CULL_DISABLED
			mesh.material_override=material;world.add_child(mesh)
			materials.append({"mesh":mesh,"source":source,"mode":mode})
			result.rows.append({"family":names[row],"mode":mode,"screen":camera.unproject_position(mesh.position),"source_texture":source.albedo_texture.resource_path,"roughness":source.roughness,"specular":source.metallic_specular,"albedo_color":str(source.albedo_color)})
	await _capture("lit-common-environment.png","lit")
	for item in materials:
		if item.mode=="standard": item.mesh.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		else: item.mesh.material_override=_custom(item.source,"boundary" if item.mode=="boundary" else "linear",true)
	await _capture("unlit-common-environment.png","unlit_common")
	# Isolated control only; never writes the source Environment.
	holder.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	holder.environment.glow_enabled=false;holder.environment.fog_enabled=false;holder.environment.ssao_enabled=false
	await _capture("unlit-neutral-control.png","unlit_neutral")
	result["status"]="MEASURED_REQUIRES_REVIEW"
	_finish(0)

func _capture(filename: String, key: String) -> void:
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image()
	image.save_png(output+"/"+filename);result.captures.append(output+"/"+filename)
	for row in result.rows:
		var sum:=Color(0,0,0,0)
		var center: Vector2=row.screen
		for y in range(-15,16):
			for x in range(-15,16): sum+=image.get_pixel(roundi(center.x)+x,roundi(center.y)+y)
		var average: Color=sum/961.0
		row[key]=[average.r,average.g,average.b]
		row["screen"]=[center.x,center.y] if key=="unlit_neutral" else center

func _finish(code: int) -> void:
	if completed:return
	completed=true
	var file:=FileAccess.open(output+"/material-probe.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(result,"  "))
	print("MATERIAL_PROBE_REPORT="+output+"/material-probe.json")
	quit(code)
