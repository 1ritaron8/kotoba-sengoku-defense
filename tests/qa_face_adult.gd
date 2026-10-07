extends SceneTree
## Independent shape checks and same-light rendered before/after comparison.

const Face = preload("res://native/human_face_3d.gd")
const Before = preload("res://tests/fixtures/face_round_baseline.gd")
const Materials = preload("res://native/actor_materials.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")

var checks: int = 0
var failures: Array = []
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func frames(count: int) -> void:
	for index in range(count):
		await process_frame

func vertices_for(parts: Array, material_name: String) -> PackedVector3Array:
	for part in parts:
		if str(part.material)==material_name:
			return part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return PackedVector3Array()

func slice_width(vertices: PackedVector3Array, y: float, tolerance: float) -> float:
	var left: float = INF
	var right: float = -INF
	for point in vertices:
		# Frontal skin only. Ear/concha vertices share the skin batch and must
		# not be mistaken for the cheek width in this independent measurement.
		if absf(point.y-y)<tolerance and point.z < -0.030:
			left = minf(left,point.x)
			right = maxf(right,point.x)
	return right-left

func iris_center(vertices: PackedVector3Array, side: float) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for point in vertices:
		if point.y>0.042 and point.y<0.068 and point.x*side>0.01:
			total += point
			count += 1
	return total/maxi(1,count)

func shape_report(helper: Script, high: bool) -> Dictionary:
	var parts: Array = helper.build(high)
	var skin: PackedVector3Array = vertices_for(parts,"skin")
	var iris: PackedVector3Array = vertices_for(parts,"iris")
	var bounds: AABB = parts[0].mesh.get_aabb()
	var triangles: int = 0
	for part in parts:
		bounds = bounds.merge(part.mesh.get_aabb())
		triangles += part.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3
	var right: Vector3 = iris_center(iris,1.0)
	var left: Vector3 = iris_center(iris,-1.0)
	return {"cheekWidth":slice_width(skin,0.020,0.006),"jawWidth":slice_width(skin,-0.042,0.006),"eyeCenterDistance":left.distance_to(right),"bounds":str(bounds),"triangles":triangles}

func run() -> void:
	var before: Dictionary = shape_report(Before,true)
	var after: Dictionary = shape_report(Face,true)
	var low: Dictionary = shape_report(Face,false)
	check(float(after.cheekWidth)<float(before.cheekWidth)*0.94,"Measured cheek envelope becomes visibly narrower than the spherical baseline")
	check(float(after.jawWidth)/float(after.cheekWidth)>float(before.jawWidth)/float(before.cheekWidth)+0.055,"Measured jaw-to-cheek ratio replaces the round lower-face silhouette")
	check(float(after.eyeCenterDistance)>0.062 and float(after.eyeCenterDistance)<0.074,"Eye spacing remains within a restrained adult envelope")
	check(absf(float(after.eyeCenterDistance)-float(low.eyeCenterDistance))<0.002,"Battle LOD preserves the actual eyes' spacing")
	check(int(low.triangles)<=4200,"Battle head remains within the existing face budget")
	for high in [true,false]:
		var parts: Array = Face.build(high)
		check(parts.size()==5,"Five original material batches remain available")
		for part in parts:
			var arrays: Array = part.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var used: Dictionary = {}
			var valid: bool = normals.size()==vertices.size() and colours.size()==vertices.size()
			for index in indices:
				valid = valid and index>=0 and index<vertices.size()
				used[index] = true
			for index in range(vertices.size()):
				valid = valid and vertices[index].is_finite() and normals[index].is_finite() and absf(normals[index].length()-1.0)<0.02
			for triangle in range(0,indices.size(),3):
				var a: Vector3 = vertices[indices[triangle]]
				var b: Vector3 = vertices[indices[triangle+1]]
				var c: Vector3 = vertices[indices[triangle+2]]
				valid = valid and (b-a).cross(c-a).length_squared()>1.0e-16
			check(valid,"Actual indexed mesh has finite normals and no degenerate triangles: "+str(part.material))
			check(used.size()==vertices.size(),"Every generated vertex is referenced: "+str(part.material))
			check(Face.material_recipe().has(part.material),"Original material recipe contract is preserved: "+str(part.material))
		check(parts[0].mesh==Face.build(high)[0].mesh,"Repeated builds retain geometry cache identity")
	report = {"checks":checks,"failures":failures,"before":before,"after":after,"low":low,"gpu":RenderingServer.get_video_adapter_name()}
	if DisplayServer.get_name()!="headless":
		await render_comparison()
	var file: FileAccess = FileAccess.open("res://tests/qa_face_adult.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("FACE_ADULT_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func create_head(helper: Script, high: bool) -> Node3D:
	var head: Node3D = Node3D.new()
	var recipes: Dictionary = {}
	var pieces: Array = []
	for part in helper.build(high):
		var recipe: Dictionary = helper.material_recipe()[part.material]
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.set_meta("surface_recipe",{"colour":recipe.albedo,"metallic":recipe.metallic,"roughness":recipe.roughness,"texture":"","normalScale":0.0})
		recipes[part.material] = material
		pieces.append({"bone":"head","material":part.material,"mesh":part.mesh})
	for piece in Materials.batch_by_joint(pieces,recipes):
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = piece.mesh
		instance.material_override = Materials.material()
		head.add_child(instance)
	return head

func render_comparison() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640,640)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202522")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d0d5d3")
	environment.ambient_light_energy = 0.45
	var light_world: WorldEnvironment = WorldEnvironment.new()
	light_world.environment = environment
	world.add_child(light_world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	# The key shines from local -Z onto the face, rather than lighting its back.
	sun.rotation_degrees = Vector3(-32,152,0)
	sun.light_color = Color("fff5e8")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.1
	world.add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18,-50,0)
	fill.light_color = Color("c4d2dc")
	fill.light_energy = 0.18
	world.add_child(fill)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.315
	camera.near = 0.01
	camera.far = 6.0
	camera.current = true
	world.add_child(camera)
	var images: Array = []
	var sheet: Image = Image.create(1920,1280,false,Image.FORMAT_RGBA8)
	sheet.fill(Color("202522"))
	var conditions: Array = [{"name":"before","helper":Before},{"name":"after","helper":Face}]
	var angles: Array = [{"name":"front","angle":0.0},{"name":"threequarter","angle":35.0},{"name":"profile","angle":80.0}]
	for row in range(conditions.size()):
		var condition: Dictionary = conditions[row]
		var head: Node3D = create_head(condition.helper,true)
		world.add_child(head)
		for column in range(angles.size()):
			var angle: Dictionary = angles[column]
			var radians: float = deg_to_rad(float(angle.angle))
			camera.position = Vector3(sin(radians),0.070,-cos(radians))
			camera.look_at(Vector3(0,0.035,0),Vector3.UP)
			await frames(10)
			await RenderingServer.frame_post_draw
			var frame: Image = viewport.get_texture().get_image()
			var path: String = "res://dist/preview-face-%s-%s.png" % [condition.name,angle.name]
			check(frame.save_png(path)==OK,"GPU comparison image saves: "+path)
			frame.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(frame,Rect2i(0,0,640,640),Vector2i(column*640,row*640))
			images.append(path)
			if row==1 and column==0:
				# Same mesh/material/camera/light direction; disable only the shadow
				# to separate surface noise from self-shadow acne in the close-up.
				sun.shadow_enabled = false
				await frames(10)
				await RenderingServer.frame_post_draw
				var unshadowed_path: String = "res://dist/preview-face-after-front-shadow-off.png"
				check(viewport.get_texture().get_image().save_png(unshadowed_path)==OK,"Single-variable shadow-off comparison saves")
				images.append(unshadowed_path)
				sun.shadow_enabled = true
				await frames(2)
		head.queue_free()
		await frames(2)
	check(sheet.save_png("res://dist/preview-face-before-after.png")==OK,"Same-light before/after contact sheet saves")
	var battle_head: Node3D = create_head(Face,false)
	world.add_child(battle_head)
	for angle in angles:
		var radians: float = deg_to_rad(float(angle.angle))
		camera.position = Vector3(sin(radians),0.070,-cos(radians))
		camera.look_at(Vector3(0,0.035,0),Vector3.UP)
		await frames(10)
		await RenderingServer.frame_post_draw
		var path: String = "res://dist/preview-face-battle-%s.png" % angle.name
		check(viewport.get_texture().get_image().save_png(path)==OK,"Battle LOD face saves: "+path)
		images.append(path)
	battle_head.queue_free()
	await frames(2)
	# Confirm the helper in the actual hero model rather than judging only a floating head.
	var actor: Node3D = Actor.new()
	world.add_child(actor)
	actor.configure("archer",false,37,true,0)
	actor.apply_state({"animation":"idle","animationClock":0.65,"motionTime":0.65,"aimX":0,"aimY":-1,"hitClock":0,"sailing":false})
	var target: Vector3 = actor.bones.head.global_position+Vector3(0,0.025,-0.005)
	camera.size = 0.61
	for angle in angles:
		var radians: float = deg_to_rad(float(angle.angle))
		camera.position = target+Vector3(sin(radians)*2.0,0.12,-cos(radians)*2.0)
		camera.look_at(target,Vector3.UP)
		await frames(10)
		await RenderingServer.frame_post_draw
		var path: String = "res://dist/preview-face-hero-%s.png" % angle.name
		check(viewport.get_texture().get_image().save_png(path)==OK,"Actual hero model face saves: "+path)
		images.append(path)
	report["gpuImages"] = images
	report["checks"] = checks
	actor.queue_free()
	viewport.queue_free()
	await frames(2)
