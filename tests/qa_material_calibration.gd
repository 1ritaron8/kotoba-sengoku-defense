extends SceneTree
## Render the production batched skin material at a known neutral pigment.
## This catches colour-space clipping without depending on portrait lighting.
const Materials = preload("res://native/actor_materials.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	var viewport = SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = Node3D.new()
	viewport.add_child(world)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2
	camera.position.z = 3
	camera.current = true
	world.add_child(camera)
	var quad = QuadMesh.new()
	quad.size = Vector2(2,2)
	var source_mesh = ArrayMesh.new()
	source_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,quad.surface_get_arrays(0))
	var pigment = StandardMaterial3D.new()
	pigment.albedo_color = Color(.5,.5,.5)
	var pieces = Materials.batch_by_joint([{"bone":"test","material":"skin","mesh":source_mesh}],{"skin":pigment})
	var instance = MeshInstance3D.new()
	instance.mesh = pieces[0].mesh
	var source = Materials.material()
	var material = source.duplicate()
	var unlit = Shader.new()
	unlit.code = source.shader.code.replace("render_mode cull_disabled;","render_mode unshaded, cull_disabled;")
	material.shader = unlit
	instance.material_override = material
	world.add_child(instance)
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	var frame = viewport.get_texture().get_image()
	var total = Vector3.ZERO
	var minimum = Vector3.ONE
	var maximum = Vector3.ZERO
	var count = 0
	for y in range(16,240,2):
		for x in range(16,240,2):
			var pixel: Color = frame.get_pixel(x,y)
			var value = Vector3(pixel.r,pixel.g,pixel.b)
			total += value
			minimum = minimum.min(value)
			maximum = maximum.max(value)
			count += 1
	var mean: Vector3 = total/count
	var range_value: Vector3 = maximum-minimum
	var passed = mean.x>.46 and mean.x<.54 and mean.y>.46 and mean.y<.54 and mean.z>.46 and mean.z<.54 and range_value.length()>.04
	var report = {"renderer":RenderingServer.get_video_adapter_name(),"pigment":.5,"mean":[mean.x,mean.y,mean.z],"range":[range_value.x,range_value.y,range_value.z],"passed":passed}
	FileAccess.open("res://tests/qa_material_calibration.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	frame.save_png("res://tests/qa_material_calibration.png")
	print("PRODUCTION_MATERIAL_CALIBRATION ",JSON.stringify(report))
	if not passed:
		push_error("Neutral skin pigment is clipped or loses the photographic detail")
	quit(0 if passed else 1)
