extends SceneTree
## Observe real authored height mesh lighting without editing terrain or art.
const Battlefield = preload("res://native/battlefield_3d.gd")
const Materials = preload("res://native/battlefield_materials.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []

func _initialize() -> void:
	root.position = Vector2i(-16000,-16000)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func capture(viewport: SubViewport) -> Image:
	for unused in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func luminance(value: Color) -> float:
	return value.r*.2126+value.g*.7152+value.b*.0722

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var allowed: String = ProjectSettings.globalize_path("res://tests/profiles/terrain-relief/").replace("\\","/").to_lower()
	if not profile.begins_with(allowed) or DisplayServer.get_name()=="headless": quit(2);return
	root.size = Vector2i(32,32)
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var initial_data_hash: String = FileAccess.get_sha256("res://native/maps.json")
	for stage_index in [2,36]:
		var stage: Dictionary = maps[stage_index]
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(960,540)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var scene: Node3D = Node3D.new()
		viewport.add_child(scene)
		var camera: Camera3D = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = 18.5
		camera.near = .1
		camera.far = 50.0
		camera.position = Vector3(0,30,30/tan(deg_to_rad(50.0)))
		camera.look_at_from_position(camera.position,Vector3.ZERO)
		camera.current = true
		scene.add_child(camera)
		var sun: DirectionalLight3D = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-48,-38,0)
		sun.light_cull_mask = 1
		scene.add_child(sun)
		var terrain: Node3D = Battlefield.new()
		scene.add_child(terrain)
		# The production height and ground builder, without decorative scenery.
		terrain._begin_configure(stage,18.5,18.5/(960.0/540.0)/sin(deg_to_rad(50.0)),50)
		terrain._collect_geometry()
		terrain._build_height_grid()
		terrain._build_ground()
		check(str(terrain.render_record.mode)=="rendered","Verified authored art: "+str(stage.id))
		var height_hash: int = hash(terrain.heights)
		var art_hash: String = FileAccess.get_sha256(str(terrain.render_record.artPath))
		var material: ShaderMaterial = terrain.ground_mesh.material_override
		# Supply stage explicitly so the test covers the semantic water guard.
		material = Materials.rendered_art(terrain.render_record,stage)
		terrain.ground_mesh.material_override = material
		var caster: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(.8,.8,.8)
		caster.mesh = box
		caster.position = terrain.world_point(Vector2(.3,.4))+Vector3(0,1.2,0)
		caster.layers = 1
		scene.add_child(caster)
		material.set_shader_parameter("relief_strength",0.0)
		var without_shadow: Image = await capture(viewport)
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 50.0
		sun.shadow_bias = .05
		sun.shadow_normal_bias = .2
		var before: Image = await capture(viewport)
		material.set_shader_parameter("relief_strength",0.65)
		var after: Image = await capture(viewport)
		check(before.save_png("user://terrain-%02d-before.png" % int(stage.stageNumber))==OK,"Baseline screenshot saved")
		check(after.save_png("user://terrain-%02d-after.png" % int(stage.stageNumber))==OK,"Relief screenshot saved")
		var changed: int = 0
		var water_error: float = 0.0
		var minimum_ratio: float = 1.0
		var maximum_ratio: float = 1.0
		var water_samples: int = 0
		var shadow_samples: int = 0
		var shadow_error: float = 0.0
		var water_count: int = int(material.get_shader_parameter("relief_water_count"))
		var water_rects: PackedVector4Array = material.get_shader_parameter("relief_water_rects")
		for y in range(4,536):
			for x in range(4,956):
				var old: Color = before.get_pixel(x,y)
				var current: Color = after.get_pixel(x,y)
				var error: float = absf(old.r-current.r)+absf(old.g-current.g)+absf(old.b-current.b)
				var unshadowed: Color = without_shadow.get_pixel(x,y)
				if luminance(unshadowed)>.08 and luminance(old)<luminance(unshadowed)*.83:
					shadow_samples += 1
					shadow_error = maxf(shadow_error,error)
				if error>.012: changed += 1
				if luminance(old)>.05:
					var ratio: float = luminance(current)/luminance(old)
					minimum_ratio = minf(minimum_ratio,ratio)
					maximum_ratio = maxf(maximum_ratio,ratio)
				var p: Vector2 = Vector2((x+.5)/960.0,(y+.5)/540.0)
				for index in range(water_count):
					var water: Vector4 = water_rects[index]
					if Rect2(water.x,water.y,water.z,water.w).grow(-.005).has_point(p):
						water_samples += 1
						water_error = maxf(water_error,error)
		check(changed>100,"Real slopes receive visible relief lighting: "+str(stage.id))
		check(minimum_ratio>=.85 and maximum_ratio<=1.17,"Relief remains moderate and readable: "+str(stage.id))
		check(water_error<.012,"Semantic water pixels retain authored lighting: "+str(stage.id))
		check(shadow_samples>10 and shadow_error<.012,"Existing deep live shadows receive no extra darkening: "+str(stage.id))
		check(height_hash==hash(terrain.heights),"Source height values unchanged: "+str(stage.id))
		check(art_hash==FileAccess.get_sha256(str(terrain.render_record.artPath)),"Original art bytes unchanged: "+str(stage.id))
		# Flat ground uses an actual flat mesh and the same production shader.
		var flat: PlaneMesh = PlaneMesh.new()
		flat.size = Vector2(18.5,18.5/(960.0/540.0)/sin(deg_to_rad(50.0)))
		terrain.ground_mesh.mesh = flat
		material.set_shader_parameter("relief_strength",0.0)
		var flat_before: Image = await capture(viewport)
		material.set_shader_parameter("relief_strength",0.65)
		var flat_after: Image = await capture(viewport)
		check(flat_before.get_data()==flat_after.get_data(),"Flat geometry has exactly zero relief effect: "+str(stage.id))
		observations.append({"stage":stage.stageNumber,"changedSlopePixels":changed,"waterSamples":water_samples,"waterMaxError":water_error,"shadowSamples":shadow_samples,"shadowMaxError":shadow_error,"minimumBrightnessRatio":minimum_ratio,"maximumBrightnessRatio":maximum_ratio,"sourceHeightUnchanged":height_hash==hash(terrain.heights)})
		viewport.queue_free()
		await process_frame
	check(initial_data_hash==FileAccess.get_sha256("res://native/maps.json"),"All terrain JSON source bytes unchanged")
	var file: FileAccess = FileAccess.open("user://terrain-relief-gpu.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	print("TERRAIN_RELIEF checks=%d failures=%d path=%s" % [checks,failures.size(),ProjectSettings.globalize_path("user://terrain-relief-gpu.json")])
	quit(0 if failures.is_empty() else 1)
