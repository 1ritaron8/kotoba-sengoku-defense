extends SceneTree
## Observe the renderer's actual texture sample and output colour spaces.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size = Vector2i(800,200)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(800,200)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = Node3D.new()
	viewport.add_child(world)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(0,0,5)
	world.add_child(camera)
	camera.current = true
	var shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded;
uniform sampler2D atlas : source_color, filter_linear;
uniform int mode = 0;
void fragment() {
    vec3 skin = texture(atlas,vec2(0.5)+UV*0.5).rgb;
    if (mode==0) ALBEDO=skin;
    else if (mode==1) ALBEDO=vec3(0.503,0.257,0.153);
    else if (mode==2) ALBEDO=0.5*clamp(skin/vec3(0.503,0.257,0.153),vec3(0.78),vec3(1.24));
    else ALBEDO=OUTPUT_IS_SRGB ? vec3(1.0,0.0,0.0) : vec3(0.0,1.0,0.0);
}"""
	for index in range(4):
		var quad = MeshInstance3D.new()
		var mesh = QuadMesh.new()
		mesh.size = Vector2(2,2)
		quad.mesh = mesh
		quad.position.x = -3.0+index*2.0
		var material = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("atlas",load("res://assets/materials/sengoku/surface-atlas-v1.png"))
		material.set_shader_parameter("mode",index)
		quad.material_override = material
		world.add_child(quad)
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	var frame = viewport.get_texture().get_image()
	if frame == null or frame.get_size()!=Vector2i(800,200):
		push_error("GPU colour probe has an unexpected viewport size")
		quit(1)
		return
	var result: Array = []
	for index in range(4):
		var total = Vector3.ZERO
		var count = 0
		for y in range(10,190,4):
			for x in range(10,190,4):
				var pixel: Color = frame.get_pixel(index*200+x,y)
				total += Vector3(pixel.r,pixel.g,pixel.b)
				count += 1
		var mean: Vector3 = total/count
		result.append({"mode":index,"mean":[mean.x,mean.y,mean.z]})
	print("GPU_ATLAS_COLOUR ",JSON.stringify(result))
	frame.save_png("res://tests/qa_atlas_colour_gpu.png")
	var file = FileAccess.open("res://tests/qa_atlas_colour_gpu.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	quit(0)
